SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Alapeno contributors
The grant is AGPL-3.0-only and there is no MIT license.

# Alapeno integer ISA

This is the programmer-visible instruction contract for an integer reduction-algebra core. It is not RISC-V, not a softmax accelerator, and not IEEE floating point. There is no float sort, no rounding mode, no NaN, and no subnormal. Numeric authority is mathematical integers and one prime field. The field prime and the reduction identities are normatively defined in `spec/arithmetic/ARITHMETIC.md`. The address map, SRAM port rules, and DMA are normatively defined in `spec/memory/MEMORY.md`. The MMIO engine is normatively defined in `spec/accelerator/ACCELERATOR.md`. Where this file states an encoding, that encoding is locked.

Normative words: **must** and **must not**. A conforming core implements every rule below. Examples state required numeric results, not measurements.

## 1. Architectural state

| Name | Width | Meaning |
| --- | --- | --- |
| PC | 32-bit byte address | Fetch address. Bits [1:0] are always 0. |
| X0..X31 | 64-bit bit-containers | General registers. |
| Z0..Z7 | signed 256-bit | Extended accumulators. |
| tcause | 32-bit | Cause code of the latest trap. |
| tpc | 32-bit | PC of the trapping instruction. |

Reset must set PC = 0, every X register = 0, every Z register = 0, tcause = 0, and tpc = 0. Reset must set every SRAM byte to 0 and must set accelerator and DMA status to idle. ROM is the external image and must not be cleared by reset. See MEMORY.md for the SRAM and MMIO reset image.

X registers are bit-containers. The signed interpretation is two's complement in [-2^63, 2^63 - 1]. The unsigned interpretation is the integer in [0, 2^64). Both views are the same 64 bits. X0 must read as 0. A write to X0 must be ignored and must not change any other register.

Each Z register holds a mathematical integer in the closed signed 256-bit range [-2^255, 2^255 - 1]. The in-memory and in-register encoding is four little-endian 64-bit limbs. Limb 0 is bits [63:0] of the two's-complement 256-bit representation. Limb k is bits [64k+63 : 64k]. Bit 255 is the sign bit. The value -1 is four limbs of `0xFFFFFFFFFFFFFFFF`.

tcause and tpc are mandatory architectural state. This revision defines no instruction and no MMIO offset that moves them into X. They are updated only by reset and by the trap rule below. A testbench must be able to observe them.

## 2. Trap rule

On any trap defined in this contract, the trapping instruction must write nothing. No X register, no Z register, no SRAM byte, and no MMIO register changes because of that instruction. Then tpc must become the PC of the trapping instruction, tcause must become the cause code, and PC must become `0x00000040`. The vector `0x00000040` is inside ROM and is executable.

Cause codes:

| Code | Name | Meaning |
| --- | --- | --- |
| 1 | misaligned control | PC or a branch/JAL offset is not a multiple of 4. |
| 2 | illegal instruction | The encoding is not a defined instruction. |
| 3 | address or permission | High address bits, a hole, a non-executable fetch, a write to ROM, or a non-executable JALR/branch target. |
| 4 | misaligned data | A data address is not aligned for its access size. |
| 5 | extended overflow | A Z result is outside signed 256-bit, or ZFIT does not fit in signed 64-bit. |
| 6 | empty reduction | RED.MIN or RED.MAX with length 0. |
| 7 | reduction fault | Scalar length greater than 4096, or a RED.SUM.MODP element not in [0, p). This code is also the name used for accelerator/DMA faults, but those faults must not trap the core. |
| 8 | not a trap | HALT must not use a trap and must not write cause 8. |
| 9 | ECALL | ECALL with funct = 0. Cause 2 must not be used for a legal ECALL. |

Priority, first match wins, and the instruction writes nothing:

1. Fetch alignment, then fetch permission (section 8).
2. Decode illegality (cause 2), including a reserved field that is not the required zero.
3. For B-type and JAL, an offset that is not a multiple of 4 (cause 1), whether or not the branch is taken.
4. For JALR, bits [63:32] of X[rs1] nonzero (cause 3).
5. Effective-address high half (cause 3), then data alignment (cause 4), then permission (cause 3).
6. Reduction length or residue checks (cause 7), empty MIN/MAX (cause 6), then range (cause 5).
7. Z-range checks (cause 5).

HALT is not a trap. A taken branch or jump whose target is not executable raises cause 3 and must not leave PC at that target. A not-taken branch whose offset is a multiple of 4 completes and sets PC to PC+4 even if the untaken target would have been illegal. The next fetch then applies the fetch rules.

## 3. Encodings

Every instruction is one fixed 32-bit word, little-endian in memory. The word at address A has bits [7:0] at byte A, bits [15:8] at A+1, bits [23:16] at A+2, and bits [31:24] at A+3.

| Format | 31:26 | 25:21 | 20:16 | 15:11 | 10:0 |
| --- | --- | --- | --- | --- | --- |
| R | op | rd | rs1 | rs2 | funct |
| I | op | rd | rs1 | imm16 | (imm16 occupies 15:0) |
| S | op | rs2 (store data) | rs1 | imm16 | (imm16 occupies 15:0) |
| B | op | rs1 | rs2 | imm16 | (imm16 occupies 15:0) |
| Z | op | zd | src1 | src2 | funct3 at [10:8], reserved0 at [7:0] |

Reduction instructions use the R field positions with op = `0x19`: zd, base rs1, length rs2, funct.

imm16 is sign-extended to 64 bits except where an instruction says zero-extend. Sign extension copies bit 15 into bits [63:16]. Zero extension writes zeros into bits [63:16].

X index fields are 5 bits and every value 0..31 names an X register. A Z index in a 5-bit field must be 0..7. A Z index of 8..31 is illegal (cause 2).

## 4. Opcode map

| op | Mnemonic | Format | Operation |
| --- | --- | --- | --- |
| 0x00 | ADD | R | signed wrap add |
| 0x01 | SUB | R | signed wrap sub |
| 0x02 | AND | R | bitwise and |
| 0x03 | OR | R | bitwise or |
| 0x04 | XOR | R | bitwise xor |
| 0x05 | SLL | R | logical left |
| 0x06 | SRL | R | logical right |
| 0x07 | SRA | R | arithmetic right |
| 0x08 | SLT | R | signed less-than |
| 0x09 | SLTU | R | unsigned less-than |
| 0x0C | MUL.LO | R | low 64 of signed product |
| 0x0D | MUL.HI | R | high 64 of signed product |
| 0x0E | MULU.HI | R | high 64 of unsigned product |
| 0x10 | ADDI | I | add immediate |
| 0x11 | ANDI | I | and immediate, zero-extend |
| 0x12 | ORI | I | or immediate, zero-extend |
| 0x13 | XORI | I | xor immediate, zero-extend |
| 0x14 | SLTI | I | signed less-than immediate |
| 0x15 | SLTIU | I | unsigned compare of sign-extended immediate |
| 0x16 | LUI | I | load upper immediate |
| 0x18 | Z-group | Z | funct3 selects ZCLR..MODP |
| 0x19 | RED | R-like | funct selects the reduction |
| 0x1A | ZLD | I | 32-byte load into Z |
| 0x1B | ZST | S | 32-byte store from Z |
| 0x20 | LD | I | 8-byte load |
| 0x21 | LW | I | 4-byte signed load |
| 0x22 | LH | I | 2-byte signed load |
| 0x23 | LB | I | 1-byte signed load |
| 0x24 | LWU | I | 4-byte unsigned load |
| 0x25 | LHU | I | 2-byte unsigned load |
| 0x26 | LBU | I | 1-byte unsigned load |
| 0x28 | SD | S | 8-byte store |
| 0x29 | SW | S | 4-byte store |
| 0x2A | SH | S | 2-byte store |
| 0x2B | SB | S | 1-byte store |
| 0x30 | BEQ | B | equal |
| 0x31 | BNE | B | not equal |
| 0x32 | BLT | B | signed less |
| 0x33 | BGE | B | signed greater or equal |
| 0x34 | BLTU | B | unsigned less |
| 0x35 | BGEU | B | unsigned greater or equal |
| 0x36 | JAL | I | jump and link; rs1 field must be 0 |
| 0x37 | JALR | I | jump and link register |
| 0x3E | HALT | R | freeze PC; funct must be 0 |
| 0x3F | ECALL | R | trap cause 9; funct must be 0 |

Any other op must trap as illegal (cause 2). For opcodes 0x00..0x09 and 0x0C..0x0E, funct must be 0; any other funct is illegal. HALT and ECALL require funct = 0.

Z-group funct3 in bits [10:8], and bits [7:0] must be 0:

| funct3 | Mnemonic | Sources |
| --- | --- | --- |
| 0 | ZCLR | zd is Z destination; src1 and src2 must be 0 |
| 1 | ZSEXT | zd is Z destination; src1 is X; src2 must be 0 |
| 2 | ZLIMB | zd is Z source; src1 is X destination; src2 selects the limb |
| 3 | ZFIT | zd is Z source; src1 is X destination; src2 must be 0 |
| 4 | ZADD | zd, src1, src2 are all Z |
| 5 | ZSUB | zd, src1, src2 are all Z |
| 6 | ZMAC | zd is Z accumulator; src1 and src2 are X |
| 7 | MODP | zd is Z destination; src1 is Z; src2 must be 0 |

There is no eighth funct3. Field multiply and field add are software sequences of ZMAC or ZADD followed by MODP, specified in ARITHMETIC.md. An implementation must not decode a ninth Z operation.

RED funct in bits [10:0]:

| funct | Mnemonic |
| --- | --- |
| 0 | RED.SUM |
| 1 | RED.MIN |
| 2 | RED.MAX |
| 3 | RED.SUM.MODP |

Any other RED funct is illegal.

## 5. Register ALU

All R-type ALU operations read the old register values, then write X[rd]. A write to X0 is discarded. Wrap means the low 64 bits of the two's-complement representation. It is not a trap.

Let `sx(i)` be the signed view of X[i] and `ux(i)` the unsigned view.

| Op | Result bits |
| --- | --- |
| ADD | low 64 of `sx(rs1) + sx(rs2)` |
| SUB | low 64 of `sx(rs1) - sx(rs2)` |
| AND, OR, XOR | bitwise on the containers |
| SLL | `ux(rs1)` shifted left by `ux(rs2) mod 64`, zeros enter at bit 0 |
| SRL | `ux(rs1)` shifted right by `ux(rs2) mod 64`, zeros enter at bit 63 |
| SRA | `sx(rs1)` shifted right by `ux(rs2) mod 64`, the sign bit fills |
| SLT | 1 if `sx(rs1) < sx(rs2)`, else 0 |
| SLTU | 1 if `ux(rs1) < ux(rs2)`, else 0 |
| MUL.LO | low 64 bits of the two's-complement 128-bit product `sx(rs1) * sx(rs2)` |
| MUL.HI | bits [127:64] of that same signed 128-bit product |
| MULU.HI | bits [127:64] of the unsigned product `ux(rs1) * ux(rs2)` |

The shift amount is the full unsigned register modulo 64, which is bits [5:0]. There is no shift-immediate instruction.

## 6. Immediates

| Op | Definition |
| --- | --- |
| ADDI | same wrap add as ADD, of `sx(rs1)` and sign-extended imm16 |
| ANDI | X[rs1] AND zero-extended imm16 |
| ORI | X[rs1] OR zero-extended imm16 |
| XORI | X[rs1] XOR zero-extended imm16 |
| SLTI | 1 if `sx(rs1)` is less than the sign-extended immediate, else 0 |
| SLTIU | Sign-extend imm16 to 64 bits, then compare that bit-container unsigned with `ux(rs1)`. The immediate is not zero-extended. |
| LUI | Bits [15:0] = 0, bits [31:16] = imm16, and bit 31 is copied into every bit of [63:32]. |

SLTIU of imm16 = `0xFFFF` therefore compares against the unsigned value 2^64 - 1. The result is 1 for every X[rs1] except the all-ones container, which yields 0.

LUI of imm16 = `0x0001` yields `0x0000000000010000`. LUI of imm16 = `0xFFFF` yields `0xFFFFFFFFFFFF0000`.

## 7. Loads, stores, ZLD, and ZST

### 7.1 Effective address

One rule, used by every scalar load and store including ZLD and ZST:

> Let S be the 64-bit wrap (the low 64 bits) of the mathematical sum of the X[rs1] bit-container and the sign-extended imm16. If bits [63:32] of S are not all zero, the instruction traps with cause 3 and writes nothing. Otherwise the physical address is bits [31:0] of S.

The addition is the full 64-bit signed wrap. The high-half check applies to that wrapped sum, not to a wider mathematical sum and not to X[rs1] alone. Example: X[rs1] = `0x00000000FFFFFFFF` and imm16 = 1 produce S = `0x0000000100000000`, which must trap with cause 3. Example: X[rs1] = `0x0000000010000000` and imm16 = 8 produce physical address `0x10000008`.

### 7.2 Accesses

| Op | Size | Alignment | Value |
| --- | --- | --- | --- |
| LD | 8 | 8 | the 64-bit little-endian container |
| LW | 4 | 4 | sign-extend bits [31:0] to 64 |
| LH | 2 | 2 | sign-extend bits [15:0] to 64 |
| LB | 1 | 1 | sign-extend bits [7:0] to 64 |
| LWU | 4 | 4 | zero-extend |
| LHU | 2 | 2 | zero-extend |
| LBU | 1 | 1 | zero-extend |
| SD | 8 | 8 | store all 64 bits of X[rs2] |
| SW | 4 | 4 | store bits [31:0] of X[rs2] |
| SH | 2 | 2 | store bits [15:0] of X[rs2] |
| SB | 1 | 1 | store bits [7:0] of X[rs2] |
| ZLD | 32 | 32 | four limbs into Z[zd] |
| ZST | 32 | 32 | four limbs from Z[zd] |

ZLD is I-type: the rd field is the Z destination, rs1 is the base, imm16 is the byte offset. ZST is S-type: the rs2 field is the Z source, rs1 is the base, imm16 is the byte offset. Limb 0 is stored at the lowest address.

A misaligned data address must trap with cause 4. SRAM and the destination register must be unchanged. A trapping instruction must not update SRAM. There is no speculative store.

Permission and the regions are defined in MEMORY.md. A short form the decoder needs:

| Region | Read | Write | Execute |
| --- | --- | --- | --- |
| ROM `0x00000000..0x0000FFFF` | yes | no, cause 3, no data change | yes |
| hole `0x00010000..0x0FFFFFFF` | cause 3 | cause 3 | cause 3 |
| SRAM0 `0x10000000..0x1003FFFF` | yes | yes | yes |
| SRAM1 `0x10040000..0x1007FFFF` | yes | yes | no, fetch is cause 3 |
| ACCEL `0x20000000..0x20000FFF` | 32-bit register only | 32-bit register only | no |
| DMA `0x30000000..0x30000FFF` | 32-bit register only | 32-bit register only | no |
| every other address | cause 3 | cause 3, no write | cause 3 |

Every byte of an access must lie in one region that permits the operation. Crossing a region boundary is cause 3 and must not write. MMIO bytes may be touched only by a 4-byte-aligned LW, LWU, or SW whose address is a defined register (MEMORY.md and ACCELERATOR.md). Any other size, any misaligned MMIO access, ZLD, ZST, or an undefined offset in an MMIO window is cause 3 if the address is otherwise inside the window and not a natural-alignment failure; a natural-alignment failure is cause 4. LD to MMIO is therefore cause 3.

Little-endian: byte A+i holds bits [8i+7 : 8i] of a multi-byte value.

Worked load. Bytes at `0x10000000` are `FF FF 00 00 00 00 00 00`. LD returns `0x000000000000FFFF`. LH returns `0xFFFFFFFFFFFFFFFF`. LHU returns `0x000000000000FFFF`. LB returns `0xFFFFFFFFFFFFFFFF`. LBU returns `0x00000000000000FF`.

## 8. Fetch, sequential PC, branches, jumps, HALT

Fetch reads the 4-byte instruction at PC. If PC is not a multiple of 4, the fetch traps with cause 1 and the instruction does not run. Else if any of the four bytes is not executable, the fetch traps with cause 3 and the instruction does not run. ROM and SRAM0 are the only executable regions. SRAM1, MMIO, the hole, and every other address are not executable.

A successful instruction that is not a taken branch, not a successful jump, and not HALT must set PC to (PC + 4) mod 2^32. The link value written by JAL and JALR is that same sequential address, zero-extended into the 64-bit X register.

Branch and JAL offsets are signed byte offsets from the current PC and must be a multiple of 4. Otherwise cause 1, and the only PC change is the trap redirect to `0x00000040`. The B-type compare is X[rs1] against X[rs2]: signed for BLT and BGE, unsigned for BLTU and BGEU, and equality of the bit-containers for BEQ and BNE. A taken branch sets PC to PC + sign-extended(imm16). If that mathematical target is outside [0, 2^32) or is not executable, the branch traps with cause 3 and writes nothing, including no PC update other than the trap redirect.

JAL is I-form. The rs1 field must be 0; otherwise illegal. X[rd] must become PC+4 and PC must become PC + sign-extended(imm16), under the same target rule as a taken branch. A trap writes neither the link nor the target PC.

JALR: if bits [63:32] of X[rs1] are nonzero, cause 3 and no write. Otherwise let `base32` be the unsigned value of bits [31:0] and let `T = base32 + sign_extend(imm16)` as a mathematical integer. If T is not in [0, 2^32), cause 3 and no write. Otherwise the target is T with bits [1:0] cleared. If that target is not executable, cause 3 and no write. On success, X[rd] = PC+4 and PC = target. The base register is read before the link is written, so JALR with rd = rs1 still uses the old base.

HALT (op `0x3E`, funct 0) must leave PC on this instruction. It must not trap, must not set tcause, and must not set tpc. Further fetches must not advance. The freeze stops the instruction stream only. An accelerator or DMA operation already in flight must be allowed to reach its own completion rule. Reset is the resume path.

ECALL (op `0x3F`, funct 0) is a precise trap with cause 9.

## 9. Z operations

All Z operations are exact on mathematical integers. They must not wrap. On cause 5 the previous Z and X values remain.

| Op | Rule |
| --- | --- |
| ZCLR | Z[zd] = 0. src1 and src2 must be 0. |
| ZSEXT | Z[zd] is the sign extension of `sx(src1)` into signed 256. src2 must be 0. Limb 0 receives the 64 bits of X[src1]. Limbs 1..3 are 0 if bit 63 of X[src1] is 0, otherwise all-ones. |
| ZLIMB | Bit extract, not a value conversion. zd selects the Z source. src1 selects the X destination. src2 bits [1:0] select limb 0..3. src2 bits [4:2] must be 0, so the src2 field itself is 0, 1, 2, or 3. X[src1] receives that limb's 64 bits. No range trap. A write to X0 is discarded. |
| ZFIT | zd is the Z source, src1 is the X destination, src2 must be 0. If Z[zd] is inside [-2^63, 2^63 - 1], X[src1] receives those low 64 bits. Otherwise precise cause 5 and no write. Equivalent bit test: limb 0 bit 63 is the sign s, and limbs 1, 2, and 3 are each 0 when s = 0 and each all-ones when s = 1. |
| ZADD | Z[zd] = Z[src1] + Z[src2], mathematical. Both sources are read before the write. zd may alias a source. Cause 5 if the sum is outside signed 256, and every Z register is unchanged. |
| ZSUB | Same for subtraction. |
| ZMAC | Z[zd] = Z[zd] + `sx(src1) * sx(src2)`. The product is the exact 128-bit signed product. The sum is exact. Cause 5 if the sum is outside signed 256. On that trap Z is unchanged. |
| MODP | Z[zd] = the residue of Z[src1] modulo p = 18446744069414584321, in [0, p). src2 must be 0. For a negative integer the residue is the unique r in [0, p) such that Z[src1] - r is divisible by p. The result always fits in signed 256 and in an unsigned 64-bit limb: limbs 1..3 are 0 and limb 0 holds r. |

ZMAC is opcode `0x18` with funct3 = 6. It is not a separate primary opcode.

A residue may be greater than or equal to 2^63 because p > 2^63. That bit pattern must not be read with the signed view of X. ZFIT of such a residue must trap with cause 5. ZLIMB is the bit extract that moves limb 0 into an X container; software must then use the unsigned view. Field values live in Z, or in the unsigned view of a 64-bit limb, never in the signed view of X.

## 10. Scalar reductions

Encoding: op = `0x19`, zd in bits [25:21], base in rs1 bits [20:16], length in rs2 bits [15:11], funct in bits [10:0].

The base address is the X[rs1] container under the same address rule as LD, except that there is no immediate: bits [63:32] of X[rs1] must be 0, and bits [31:0] are the physical base. The base must be 8-byte aligned. A high-half failure is cause 3. A misaligned base is cause 4. These two checks apply even when the length is 0.

The length is `ux(rs2)` and must be less than or equal to 4096. A larger length is cause 7 and must not write Z. Elements are contiguous. Stride is exactly 8. Element i is at the mathematical address `base + 8*i`. If that address is outside [0, 2^32) or any byte of the element is not entirely inside ROM or entirely inside the SRAM window, the instruction traps with cause 3 and writes nothing. Reduction elements must not be fetched from MMIO.

RED.SUM and RED.MIN and RED.MAX read little-endian signed 64-bit elements. RED.SUM.MODP reads unsigned 64-bit residues that must already lie in [0, p). If any element, viewed unsigned, is greater than or equal to p, the instruction traps with cause 7 and writes nothing.

| Op | Length 0 | Result |
| --- | --- | --- |
| RED.SUM | Z[zd] = 0, no element access | mathematical sum of the signed elements, starting from 0 |
| RED.MIN | cause 6, Z unchanged | mathematical minimum, sign-extended into Z[zd] |
| RED.MAX | cause 6, Z unchanged | mathematical maximum, sign-extended into Z[zd] |
| RED.SUM.MODP | Z[zd] = 0, no element access | `(e0 + e1 + ... + e_{n-1}) mod p` in [0, p) |

RED.SUM must trap with cause 5 if the mathematical sum is outside signed 256, and Z must be unchanged. Order does not change the sum. The reference evaluation order is index 0, then 1, then length-1. That order is topology R1. A balanced tree (R2) is a legal implementation only because addition of mathematical integers is associative and the trap depends only on the final sum. Each element fits in signed 64 by encoding. Wrapping 64-bit addition is a different operator and must not be used to implement RED.SUM.

RED.MIN and RED.MAX results fit in signed 64 and are written sign-extended to 256 bits. Any association is legal. They have no identity element.

RED.SUM.MODP writes a residue, so limbs 1..3 are 0. Field addition is associative, so a tree is legal. The modulus is applied to the exact integer sum. An implementation may reduce modulo p early only when the residue equals that definition.

## 11. Worked encoding

ADD x1, x2, x3 is op = 0, rd = 1, rs1 = 2, rs2 = 3, funct = 0.

```
bits [31:26] = 000000
bits [25:21] = 00001
bits [20:16] = 00010
bits [15:11] = 00011
bits [10:0]  = 000 0000 0000
word         = 0x00221800
```

In little-endian memory the four bytes are `00 18 22 00`.

If X2 = 3 and X3 = 5, the instruction writes X1 = 8 and advances PC by 4. If instead X2 = `0x7FFFFFFFFFFFFFFF` and X3 = 1, ADD writes X1 = `0x8000000000000000`, which is the signed value -2^63. That wrap is not a trap.

ZMAC with zd = 0, src1 = 1, src2 = 2, funct3 = 6, reserved0 = 0, and Z0 = 10, X1 = 3, X2 = 5, writes Z0 = 25. The product 15 is exact and the sum 25 is inside signed 256.

MODP of Z = -1 writes residue p - 1 = 18446744069414584320. MODP of Z = p writes 0. MODP of Z = p + 5 writes 5. The implementation must use Euclidean division with a non-negative remainder, not a truncating remainder that would leave -1 unchanged.
