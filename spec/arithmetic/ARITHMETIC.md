SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Alapeno contributors
The grant is AGPL-3.0-only and there is no MIT license.

# Alapeno arithmetic

This is the numeric contract. It is not IEEE floating point. There is no float sort, no rounding mode, no NaN, no subnormal, and no rounding of an exact integer result. Truncation exists only where an instruction says wrap (the 64-bit ALU and MUL.LO) or where an instruction is a bit extract (ZLIMB, and the low or high half of a product). Every other result is an exact mathematical integer, or a residue modulo the prime below. If an exact result leaves the destination's signed range, the operation traps or, on the accelerator, raises STATUS.fault. It must not wrap.

The instruction encodings that call these operations are in `spec/isa/ISA.md`. Memory widths are in `spec/memory/MEMORY.md`. Accelerator modes are in `spec/accelerator/ACCELERATOR.md`.

## 1. Ranges

| Domain | Closed range | Where it lives |
| --- | --- | --- |
| signed 64 | [-2^63, 2^63 - 1] | signed view of an X register or of an 8-byte element |
| unsigned 64 | [0, 2^64) | unsigned view of the same 64 bits |
| signed 128 | [-2^127, 2^127 - 1] | MUL.HI / MUL.LO product only; not a register |
| signed 256 | [-2^255, 2^255 - 1] | a Z register, or a 32-byte memory value |
| residue | [0, p) | a Z register after MODP, or the unsigned view of one limb |

Decimal bounds used by checks:

| Symbol | Value |
| --- | --- |
| 2^63 - 1 | 9223372036854775807 |
| -2^63 | -9223372036854775808 |
| 2^64 | 18446744073709551616 |
| 2^255 - 1 | 57896044618658097711785492504343953926634992332820282019728792003956564819967 |
| -2^255 | -57896044618658097711785492504343953926634992332820282019728792003956564819968 |

A 32-byte signed-256 memory value uses the same limb layout as Z: limb 0 at the lowest address holds bits [63:0].

## 2. Wrap, extract, and exact add

Scalar ADD, SUB, ADDI, and MUL.LO write the low 64 bits and must not trap on overflow. Example: `0x7FFFFFFFFFFFFFFF + 1` writes `0x8000000000000000`, the signed value -2^63.

Wrapping 64-bit addition is not associative once overflow is possible. `(2^63 - 1) + 1 + (-1)` depends on parenthesization if each step wraps. There is no wrapping vector reduction. RED.SUM, ZADD, ZMAC, and non-field accelerator MATMUL and VADD must not be implemented with wrapping 64-bit add.

MUL.HI returns bits [127:64] of the exact signed 128-bit product. MULU.HI returns bits [127:64] of the exact unsigned 128-bit product. MUL.LO returns bits [63:0] of the signed product. The signed and unsigned low halves of a product are the same bits; the high halves are not.

ZLIMB copies one existing 64-bit limb into an X container. It must not sign-extend, zero-extend, or range-check. ZSEXT and ZFIT are the value conversions. ZFIT succeeds only for a mathematical value inside signed 64.

## 3. MAC

ZMAC computes `acc' = acc + a * b` where `a` and `b` are signed 64-bit values and `acc` is signed 256-bit. The product is exact, so it lies in [-2^126, 2^126], and the sum is exact. If `acc'` is outside signed 256, the instruction traps with cause 5 and leaves every Z register unchanged. Otherwise Z[zd] becomes `acc'`.

The largest magnitude product of two signed 64-bit values is 2^126, from `(-2^63) * (-2^63)`. Adding that product to a signed-256 accumulator can leave the signed-256 range, and that case must trap. The machine must not saturate.

## 4. The prime

```
p    = 18446744069414584321
     = 2^64 - 2^32 + 1
HALF = floor(p / 2) = 9223372034707292160
```

p is odd, so HALF = (p - 1) / 2. Also HALF = 2^63 - 2^31. In particular p > 2^63, so a residue is not a signed int64. Field values must live in a Z register or in the unsigned view of a 64-bit limb. They must not live in the signed view of X.

Euclidean residue: for any mathematical integer z there is a unique r in [0, p) such that z - r is divisible by p. That r is the residue. Equivalently z = q * p + r with q an integer and 0 <= r < p. The quotient is toward negative infinity, not toward zero. An implementation must not use a remainder that is negative.

| z | residue |
| --- | --- |
| -1 | p - 1 = 18446744069414584320 |
| 0 | 0 |
| 5 | 5 |
| p | 0 |
| p + 5 | 5 |
| 2p - 1 | p - 1 |

MODP writes that residue into Z. Limbs 1..3 are 0. The result always fits in signed 256 and in an unsigned 64-bit limb. MODP must not trap for range.

Centering, used only by field compare: if r > HALF then the centered value is r - p, otherwise it is r. Because p = 2*HALF + 1, the centered image of [0, p) is exactly [-HALF, HALF]. The endpoint checks are: r = 0 stays 0; r = HALF stays HALF; r = HALF + 1 centers to HALF + 1 - p = -HALF; r = p - 1 centers to -1.

A residue compares as less than or equal to zero under centering exactly when r = 0 or r > HALF. Residues 1 .. HALF center to positive values.

## 5. Identities and field sequences

| Operator | Identity | Empty input |
| --- | --- | --- |
| integer sum | 0 | the identity 0 |
| integer min | none | trap or accelerator fault |
| integer max | none | trap or accelerator fault |
| field sum | 0 | the identity 0 |
| field mul | 1 | not a hardware empty-product instruction |

funct3 is three bits and values 0..7 are all assigned (ZCLR, ZSEXT, ZLIMB, ZFIT, ZADD, ZSUB, ZMAC, MODP). This contract must not add FMUL or FADD as further funct3 values.

Field add of two residues a and b already in [0, p): ZADD, then MODP. The sum is at most 2p - 2, which fits in signed 256, so that ZADD must not trap. Field sub is ZSUB, then MODP. The field-mul identity is 1. There is no FMUL instruction.

A residue with bit 63 set must not be used as a signed ZMAC input. The scalar sequence that multiplies any two residues uses the congruence 2^64 ≡ 2^32 - 1 (mod p), which holds because p = 2^64 - 2^32 + 1, and it uses only ZCLR, ZMAC, ZADD, ZSUB, ZLIMB, AND, and SRL.

1. Move each residue into an X register with ZLIMB of limb 0 and split it with a logical shift. al is bits [31:0] of a, ah is bits [63:32], and likewise bl and bh. Each half lies in [0, 2^32) and therefore in signed 64.
2. ZCLR an accumulator and ZMAC to form the four exact products al*bl, al*bh, ah*bl, and ah*bh. Each factor fits in signed 64 and each product is less than 2^64, so each ZMAC fits in signed 256.
3. Combine modulo p by the congruence, not by a wrapping X shift. In particular, multiplying a residue r by 2^32 modulo p splits r into rh = bits [63:32] and rl = bits [31:0], both in signed 64, then computes (rh + rl) * 2^32 - rh with one ZMAC by the constant 2^32 and one ZSUB, then MODP. Both rh + rl and 2^32 fit in signed 64.
4. The full product reduced by that congruence, then one final MODP, is the field product in [0, p).

p^2 = 340282366762482138490186164457219031041, which is less than 2^128 and fits in signed 256. The exact product of two residues therefore always fits in a Z register before the final MODP.

The accelerator field mode is the hardware path that multiplies and adds residues without passing through the signed view of X. Scalar software must not reinterpret a limb with bit 63 set as a negative ZMAC operand.

## 6. Reduction topologies

These names are the architectural vocabulary. A topology is legal for an operator only when every allowed parenthesization returns the same mathematical result as the reference, and the same trap-or-fault decision.

| Name | Meaning | Architecturally visible as |
| --- | --- | --- |
| R0 | scalar, length 1 | the length-1 case of RED or of a dot product with K = 1 |
| R1 | sequential fold, index 0 then 1 then ... | the reference order for RED.SUM and for unmasked dots |
| R2 | balanced tree | legal only for integer add, min, max, and add modulo p |
| R3 | chunked fold | legal under the same condition as R2 |
| R4 | segmented fold, segments concatenated in increasing address order | legal under the same condition as R2 |
| R5 | tacit fusion | legal only when the fused result equals R1 |
| R6 | Goldilocks field sum | the RED.SUM.MODP contract, and accelerator RED.SUM in field mode |
| R7 | subleq-routed field | the accelerator ROUTE contract |

R2, R3, and R4 must not be used for wrapping 64-bit addition. They are legal for RED.SUM because the elements are signed 64, the sum is mathematical, and the cause 5 decision depends only on the final sum. They are legal for MIN and MAX because those operators are associative on mathematical integers. They are legal for add modulo p because field addition is associative. R5 is a schedule, not a second result: if fusion changes the value or the fault decision, it is not R5 and it is not a conforming implementation.

The accelerator ROUTE result is R7. It is not required to equal the unmasked matrix product. R6 is the unmasked sum reduced modulo p.

## 7. Worked route and the unmasked comparison

Non-field ROUTE, one row pair, K = 2. Q = (1, 2) and Krow = (0, 2).

```
diff     = (0 - 1, 2 - 2) = (-1, 0)
pred     = (1, 1)          because both differences are <= 0
products = (1*0, 2*2) = (0, 4)
masked   = 1*0 + 1*4 = 4
```

Second pair, Q = (1, 2) and Krow = (3, 0).

```
diff     = (3 - 1, 0 - 2) = (2, -2)
pred     = (0, 1)
products = (1*3, 2*0) = (3, 0)
masked   = 0*3 + 1*0 = 0
```

The unmasked dot of the second pair is `1*3 + 2*0 = 3`, which is not the routed value 0. Conforming hardware must produce 0 for that routed pair and must not substitute the unmasked dot.

The same pairs in field mode, with residues already in [0, p), give the same predicates because -1 and -2 reduce to p - 1 and p - 2, both greater than HALF, and both center to negative values. The field masked sums are 4 and 0, each already in [0, p).

## 8. Accelerator width reminder

Non-field VADD and VSUB destinations are signed 64-bit elements. A mathematical sum or difference outside signed 64 is a fault, not a wrap and not a 256-bit result. Non-field MATMUL and non-field RED.SUM produce exact signed integers and fault only outside signed 256; those results are stored as 32-byte limb tuples because they do not fit in signed 64. Field results are residues in [0, p) and occupy one unsigned 64-bit limb. PROJECT stays inside signed 64. The byte-level statement of those widths is in ACCELERATOR.md.
