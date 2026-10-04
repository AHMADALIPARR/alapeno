SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Alapeno contributors
The grant is AGPL-3.0-only and there is no MIT license.

# Alapeno accelerator

This is the MMIO contract for the integer matrix, reduction, route, and projection engine. It is not a softmax accelerator and not an IEEE floating-point unit. SHA-512 sealing is out of scope for this contract.

The scalar ISA is in `spec/isa/ISA.md`. SRAM ports, conflict, and DMA are in `spec/memory/MEMORY.md`. Field arithmetic and topology names are in `spec/arithmetic/ARITHMETIC.md`. This file is the operation contract. No timings and no bandwidth numbers are part of conformance.

The core must not take a trap because of an accelerator or DMA fault. Software starts an operation and polls STATUS.

The first frozen compute-tile workload (non-field MATMUL with M = N = K = 4,
seeded Sovereign Reduction Algebra operands, and the host command sequence
reset / load / execute / status / store) is specified in `spec/accelerator/TILE.md`.
TILE.md does not rewrite this contract; on any conflict this file wins.

## 1. Register map

Base `0x20000000`. Each register is 32 bits, little-endian, and 4-byte aligned. The scalar core may touch one only with LW, LWU, or SW. Any other access size is a core trap, not an accelerator fault (MEMORY.md).

| Offset | Name | Role |
| --- | --- | --- |
| `0x00` | CTRL | bit 0 start, bit 1 abort. Reads as 0. |
| `0x04` | STATUS | bit 0 busy, bit 1 done, bit 2 fault, bit 3 conflict. |
| `0x08` | OP | operation code. |
| `0x0C` | M | unsigned row count. |
| `0x10` | N | unsigned column count. |
| `0x14` | K | unsigned inner count. |
| `0x18` | PTR_A | byte address of operand A. |
| `0x1C` | PTR_B | byte address of operand B. |
| `0x20` | PTR_C | byte address of operand C or the projection. |
| `0x24` | LDA | row stride of A, in bytes. |
| `0x28` | LDB | row stride of B, in bytes. |
| `0x2C` | LDC | row stride of C, in bytes. |
| `0x30` | VL | vector length. |
| `0x34` | MODE | bit 0 = field mode. bit 1 must be 0. bits [31:2] must be 0. |

Undefined offsets in `0x20000000 .. 0x20000FFF` are core cause 3. They are not extra operations.

OP codes:

| OP | Name |
| --- | --- |
| 1 | MATMUL |
| 2 | VADD |
| 3 | VSUB |
| 4 | RED.SUM |
| 5 | RED.MIN |
| 6 | RED.MAX |
| 7 | ROUTE |
| 8 | PROJECT |

Any other OP value, including 0, must fault the attempt and must not write a destination.

Operand registers must read back the last value written, including values that are out of limit. The limit check runs at start, not at the write. Writes to operand registers while busy must update the register file and must not change the values sampled for the in-flight operation. Those sampled values are the ones captured in the cycle a start is accepted.

## 2. STATUS and CTRL

| Bit | STATUS | Write effect |
| --- | --- | --- |
| 0 | busy, read-only | writes ignored |
| 1 | done, sticky | write 1 clears |
| 2 | fault, sticky | write 1 clears |
| 3 | conflict, sticky | write 1 clears |

Writing 0 must not clear a sticky bit. conflict is also set by the SRAM same-cycle rule in MEMORY.md, which sets bit 3 in both this STATUS and the DMA STATUS. Clearing one does not clear the other.

A start (CTRL bit 0 = 1, and bit 1 = 0) is accepted only when this engine is not busy, STATUS.fault is 0, and the DMA is not busy. Acceptance must sample the operand registers, set busy = 1, and clear done. If the whole-shape check fails, the engine must not enter a state that writes destinations: busy = 0, done = 0, fault = 1, destinations unchanged. Starting while this engine is busy, while fault is still 1, or while DMA is busy, must set fault = 1, leave busy = 0 if it was idle, force done = 0, and must not change destinations. A start refused because this engine is already busy must leave the in-flight operation running: busy stays 1, fault becomes 1, and destinations stay unchanged until that operation's own completion rule.

CTRL bit 1 = 1 while busy aborts. Abort must return the engine to idle with no destination write of any byte. Accelerator completion is all-or-nothing. Abort is not a fault by itself: busy = 0, done = 0, and the previous fault and conflict bits stay as they are unless this same CTRL write is not an abort. If one CTRL write sets both bit 0 and bit 1 while busy, abort wins and the new start is ignored. If both are set while idle, bit 1 is ignored and bit 0 is the start request.

On success the engine must set busy = 0 and done = 1 in one completion, and must make every destination byte visible together, subject only to the Port A same-cycle conflict rule. Bytes dropped because Port A won must set conflict. Fault and abort must not publish a prefix of the destination. DMA abort is different and is not all-or-nothing; see MEMORY.md.

## 3. Element layout

Row-major element (r, c) of a pointer P with stride S and element width W is the W bytes at mathematical address `P + r * S + c * W`. Address arithmetic is mathematical and must not wrap. Every byte that the operation reads or writes must lie in the SRAM window `0x10000000 .. 0x1007FFFF`. The check covers the whole rectangle or vector before any destination write.

| Operand kind | Width W | Alignment of pointer and of each element | Stride |
| --- | --- | --- | --- |
| signed 64-bit element, MODE.field = 0 | 8 | 8 | multiple of 8 and >= columns * 8 |
| residue in [0, p), MODE.field = 1 | 8 | 8 | multiple of 8 and >= columns * 8 |
| signed 256-bit result | 32 | 32 | multiple of 32 and >= columns * 32 |

The locked 8-byte stride rule is this table's middle rows. A signed-256 result cannot be stored in 8 bytes, so non-field MATMUL destinations and the non-field RED.SUM destination use the 32-byte row of the same rule: stride >= columns * element width, and the stride is a multiple of the element width. An implementation must not store those results in 8 bytes.

Signed 256-bit elements use the Z limb layout. Limb 0 is at the lowest address.

Which width applies:

| Operation | MODE.field = 0 | MODE.field = 1 |
| --- | --- | --- |
| MATMUL A and B | signed 64 | residues |
| MATMUL C | signed 256, 32 bytes | residue, 8 bytes |
| VADD, VSUB | signed 64 in and out | residues in and out |
| RED.SUM source | signed 64 | residues |
| RED.SUM destination | one signed-256 value, 32 bytes | one residue, 8 bytes |
| RED.MIN, RED.MAX | signed 64 in and out | residues, centered compare, residue out |
| ROUTE Q and Kmat | signed 64 | residues |
| ROUTE PR | signed 256, 32 bytes | residue, 8 bytes |
| PROJECT E, PR, Proj | signed 64 | illegal; fault, no write |

Vectors are contiguous: element i is at `PTR + i * W` with W = 8, except non-field RED.SUM, whose single destination is 32 bytes at PTR_C. Stride registers are not used for VADD, VSUB, or RED. M, N, and K are not used for those vector ops. VL is not used for MATMUL, ROUTE, or PROJECT. K is not used for PROJECT. Unused registers are not limit-checked.

Pointers of 8-byte operands must be 8-byte aligned. A 32-byte destination pointer must be 32-byte aligned. A violation is a fault, not a core cause-4 trap.

## 4. Limits checked before any destination write

When the register is used by the operation:

* M, N, K, and VL must each be <= 64.
* Stride must meet the table above.
* Every element address must lie entirely in `0x10000000 .. 0x1007FFFF`.
* In field mode, every source element, viewed as an unsigned 64-bit value, must be in [0, p). p = 18446744069414584321.
* MODE bits other than bit 0 must be 0.
* Destination bytes must not overlap source bytes, except where an operation below says a buffer is updated in place.

On any violation: STATUS.fault = 1, busy = 0, done = 0, and destination bytes are unchanged. A zero-size shape that touches no bytes is not a violation. MATMUL, ROUTE, VADD, or VSUB with no output elements (M = 0 or N = 0, or VL = 0 for the vector ops) must complete successfully and must not write. A MATMUL or ROUTE with K = 0 and a positive output shape writes the identity of the sum, which is 0, to each output element.

## 5. MATMUL

A is M by K at PTR_A with stride LDA. B is K by N at PTR_B with stride LDB. C is M by N at PTR_C with stride LDC. C must not share any byte with A or with B. Overlap is a fault and must not write C.

Non-field: `C[m, n] = sum_{k=0}^{K-1} A[m, k] * B[k, n]`, exact signed product and exact signed sum. If any dot product is outside signed 256, fault and C is unchanged. With the limits M, N, K <= 64 and signed-64 inputs, every such dot product lies in [-K * 2^126, K * 2^126], which is inside signed 256. The fault rule remains part of the contract. The stored value is the 32-byte two's-complement limb tuple.

Field: the same products and the same exact sum, then one residue modulo p at the end of each dot product. The result is in [0, p). Associativity of the exact sum means the modulus applies to that exact integer, not to a wrapped intermediate. An implementation may reduce modulo p early only if the residue equals this definition. Early reduction is topology R2 or R3 on field addition after the exact products, and it is legal only under that equality.

This MATMUL is the unmasked head. For the bi-encoder, when the programmer supplies a matrix W,

* Q = A times W
* Ktower = B^T times W
* exact head = Q times Ktower^T

If W is a permutation matrix and W times W^T = I, that head equals A times B. This is an invariant of those operand choices. The accelerator must not check that W is a permutation, and a failing invariant is not a hardware fault.

## 6. VADD and VSUB

Length VL. Element i of A, B, and C is an 8-byte value at PTR + 8*i. C must not overlap A or B.

Non-field: `C[i] = A[i] + B[i]` or `C[i] = A[i] - B[i]`, signed. If any result is outside signed 64, fault and C is unchanged. The accelerator must not wrap. This is not scalar ADD.

Field: each source must already lie in [0, p). `C[i] = (A[i] + B[i]) mod p` or `C[i] = (A[i] - B[i]) mod p`, using the Euclidean residue. The residue of a negative difference is p plus that difference when the difference is in [-p + 1, -1]. The stored byte pattern is the unsigned residue, even when bit 63 is set.

## 7. RED

One destination at PTR_C. The source vector is at PTR_A with length VL. PTR_B is ignored. Empty and range rules match the scalar reductions.

| OP | VL = 0 | Non-field result | Field result |
| --- | --- | --- | --- |
| RED.SUM | write 0 | exact signed sum; fault if outside signed 256; 32-byte store | `(sum) mod p` in [0, p); 8-byte store |
| RED.MIN | fault, no write | mathematical minimum; 8-byte signed store | residue whose centered value is minimum |
| RED.MAX | fault, no write | mathematical maximum; 8-byte signed store | residue whose centered value is maximum |

A non-field RED.SUM of VL = 0 writes 32 zero bytes at PTR_C, and PTR_C must be 32-byte aligned. A field RED.SUM of VL = 0 writes an 8-byte zero. Reference order is R1. R2, R3, and R4 are legal because the operators are associative on the stated domains. A field-mode element greater than or equal to p is a fault and must not write. Centered compare is the ARITHMETIC.md rule: r maps to r if r <= HALF and to r - p otherwise, with HALF = 9223372034707292160. The stored MIN or MAX in field mode is the original residue, not a negative centered integer.

## 8. ROUTE (topology R7)

Q is M by K at PTR_A. Kmat is N by K at PTR_B. PR is M by N at PTR_C. PR must not share bytes with Q or with Kmat.

Non-field, for each (i, j) and for t in 0 .. K-1:

```
diff[t] = Kmat[j, t] - Q[i, t]
pred[t] = 1 if diff[t] <= 0 else 0
PR[i, j] = sum_t pred[t] * Q[i, t] * Kmat[j, t]
```

The products and the sum are exact integers. If the sum leaves signed 256, fault and write nothing. The stored PR element is 32 bytes. This routed prediction is not required to equal the unmasked MATMUL product. Hardware must not replace ROUTE with MATMUL.

Field:

```
diff     = (Kmat[j, t] - Q[i, t]) mod p
centered = diff - p if diff > HALF else diff
pred     = 1 if centered <= 0 else 0
term     = pred * ((Q[i, t] * Kmat[j, t]) mod p)
PR[i, j] = (sum of terms) mod p
```

Each source element must already lie in [0, p). The stored value is one residue. Because a residue compares as centered <= 0 exactly when it is 0 or greater than HALF, an implementation may use that test. The result must still match the definition above.

Worked non-field pair, K = 2, Q row = (1, 2), Kmat row = (0, 2):

```
diff     = (0 - 1, 2 - 2) = (-1, 0)
pred     = (1, 1)
products = (0, 4)
PR       = 4
```

Second pair, Q row = (1, 2), Kmat row = (3, 0):

```
diff     = (3 - 1, 0 - 2) = (2, -2)
pred     = (0, 1)
products = (3, 0)
PR       = 0
```

The unmasked dot of the second pair is 3, not 0. Field mode on these same small values also yields PR = 4 and PR = 0, because the negative differences become p - 1 and p - 2, both center to negatives, and the masked sums are already residues.

## 9. PROJECT

PROJECT is one integer training step. It is not a loop and not a softmax. PTR_A is the exact head E (M by N). PTR_B is the routed prediction PR (M by N). PTR_C is the integer projection Proj (M by N). All three are signed 64-bit elements with 8-byte stride. MODE.field must be 0. Field mode, or any other MODE bit, faults and must not write.

PR and Proj are updated in place. E must not overlap PR or Proj. PR must not overlap Proj. Weights are not operands and must not be modified by this operation.

For every element, on an accepted start whose range checks pass:

```
Proj' = Proj + (E - PR)
PR'    = PR + Proj'
```

The functional result is that pair of assignments. It is not the claim that PR' equals E in general.

* If Proj starts at 0, Proj' = E - PR and PR' = PR + (E - PR) = E.
* If Proj starts at Proj_old which is not 0, PR' = E + Proj_old, which is not E.

The sovereign training step defines Proj as 0 before the step. The architectural rule still requires the programmer to supply Proj, including when that value is 0. Hardware must implement the general assignment.

If any intermediate or final value leaves signed 64, the operation faults and must not write either buffer. The intermediates are E - PR, Proj', and PR', at every element. The check is all-or-nothing across the whole rectangle.

Worked step, one element. E = 10, PR = 4, Proj = 0.

```
Proj' = 0 + (10 - 4) = 6
PR'    = 4 + 6 = 10
```

PR' equals E only because Proj started at 0.

Same E and PR with Proj = 3:

```
Proj' = 3 + (10 - 4) = 9
PR'    = 4 + 9 = 13
```

13 = E + Proj_old. An implementation that always stored E into PR would be wrong.

Overflow witness: E = 2^62, PR = -2^62, Proj = 0. Then E - PR = 2^63, which is outside signed 64 (the maximum is 2^63 - 1). The operation must fault and must leave both buffers unchanged.

## 10. Port B and DMA

The accelerator uses SRAM Port B. It must not use Port B in a cycle where DMA owns Port B. DMA must not start while the accelerator is busy, and must not start when a DMA byte overlaps an in-flight accelerator source or destination. The accelerator must not start while DMA is busy.

Destination bytes become visible only at a successful all-or-nothing commit. Until that commit, a scalar read of a destination byte must observe the old value. Source bytes are read on Port B under the MEMORY.md same-cycle rule. The commit itself is a Port B write: a same-cycle Port A write to the same byte wins, that destination byte keeps the Port A value, and conflict is set. That is the only conforming tear, and it is reported. A fault or an abort publishes none of the new destination bytes.

Scalar reductions and this engine are different mechanisms. A scalar RED uses opcode `0x19` and writes a Z register. This engine uses OP at `0x20000008` and writes SRAM. They must not be treated as the same instruction.
