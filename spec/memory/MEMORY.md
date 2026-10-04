SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Alapeno contributors
The grant is AGPL-3.0-only and there is no MIT license.

# Alapeno memory, SRAM, and DMA

This is the memory contract for the integer reduction-algebra core. It is not a cache hierarchy, not a floating-point memory, and not a RISC-V physical-memory model. Instruction encodings that move data are defined in `spec/isa/ISA.md`. Numeric meaning of the bytes is defined in `spec/arithmetic/ARITHMETIC.md`. The accelerator engine that shares Port B is defined in `spec/accelerator/ACCELERATOR.md`.

Normative words: **must** and **must not**.

## 1. Address map

Physical addresses are 32-bit byte addresses. Multi-byte data are little-endian: the byte at address A+i holds bits [8i+7 : 8i].

| Region | Range | Size | Read | Write | Execute |
| --- | --- | --- | --- | --- | --- |
| ROM | `0x00000000 .. 0x0000FFFF` | 64 KiB | yes | no | yes |
| hole | `0x00010000 .. 0x0FFFFFFF` | — | no | no | no |
| SRAM0 | `0x10000000 .. 0x1003FFFF` | 256 KiB | yes | yes | yes |
| SRAM1 | `0x10040000 .. 0x1007FFFF` | 256 KiB | yes | yes | no |
| hole | `0x10080000 .. 0x1FFFFFFF` | — | no | no | no |
| ACCEL | `0x20000000 .. 0x20000FFF` | 4 KiB | MMIO | MMIO | no |
| hole | `0x20001000 .. 0x2FFFFFFF` | — | no | no | no |
| DMA | `0x30000000 .. 0x30000FFF` | 4 KiB | MMIO | MMIO | no |
| hole | `0x30001000 .. 0xFFFFFFFF` | — | no | no | no |

SRAM0 and SRAM1 together are one contiguous 512 KiB SRAM window, `0x10000000 .. 0x1007FFFF`. Fetch from SRAM1 must trap with cause 3. A write whose every byte is in ROM must trap with cause 3 and must not change ROM. A byte in a hole, or any address not listed above, must trap with cause 3 and must not be written.

Power-on and reset must set every SRAM byte to 0. ROM must keep the external image across reset. Reset must set both STATUS registers to idle: busy = 0, done = 0, fault = 0, conflict = 0. Every other implemented MMIO register must read as 0 after reset.

## 2. Effective address

Scalar loads and stores, including ZLD and ZST, use this single rule:

> Let S be the 64-bit wrap, that is the low 64 bits, of the mathematical sum of the X[rs1] bit-container and the sign-extended imm16. If bits [63:32] of S are not all zero, trap with cause 3 and write nothing. Otherwise the physical address is bits [31:0] of S.

Alignment is checked on that physical address after the high-half check. A high-half failure is cause 3 even if the low bits would also have been misaligned. A misaligned physical address is cause 4, SRAM unchanged, destination register unchanged.

| Access | Alignment |
| --- | --- |
| LB, LBU, SB | 1 |
| LH, LHU, SH | 2 |
| LW, LWU, SW | 4 |
| LD, SD | 8 |
| ZLD, ZST | 32 |

ZLD (opcode `0x1A`, I-type) uses the rd field as zd. ZST (opcode `0x1B`, S-type) uses the rs2 field as zd. Both move four little-endian limbs. Limb 0 is at the lowest address. zd must be 0..7 or the instruction is illegal (cause 2).

An access that is not entirely inside one permitted region must trap with cause 3 and must not write any byte. MMIO is permitted only for a naturally aligned 4-byte LW, LWU, or SW at a defined register offset. LD, SD, ZLD, ZST, byte and halfword accesses, and undefined offsets inside the ACCEL or DMA windows must not perform a partial register update. Alignment failure is cause 4. An in-window address that fails the 4-byte register rule for any other reason is cause 3.

## 3. SRAM cycle contract

SRAM is synchronous and byte-addressed.

* A read presented in cycle T, whose bytes are not written by either port in cycle T, returns data in cycle T+1.
* A write accepted in cycle T is visible to a read presented in cycle T+1.
* A same-cycle read and write of the same byte is write-first: the read returns the winning new byte.

Port A is the scalar core. Port B is the accelerator and the DMA. The accelerator and the DMA must never both own Port B in the same cycle. If either is busy, the other must not start (ACCELERATOR.md and section 5).

Same-cycle writes of the same byte: Port A wins. Same byte, same cycle: Port A wins, the read is write-first, and both STATUS registers get sticky conflict bit 3. Port B's data for that byte is dropped. Each other byte of the Port B transfer that Port A does not write in that cycle must commit. If any Port B byte is dropped, the sticky conflict bit (STATUS bit 3) must be set in both the DMA STATUS register and the accelerator STATUS register.

A scalar store and a DMA or accelerator beat that touch disjoint bytes must both commit.

Atomicity with respect to the other port:

* An aligned 8-byte LD or SD is atomic.
* An aligned 32-byte ZLD or ZST is atomic.
* A DMA beat is 8 bytes and is atomic.
* An accelerator element access is atomic at its element width (8 or 32 bytes, as ACCELERATOR.md defines for that operand).

Narrower scalar accesses are atomic at their own width. "Atomic" means the other port must not observe a torn value of that access. The core must not write SRAM for an instruction that traps. There is no speculative store.

## 4. Conflict example

Take address `0x10000000` in a cycle where Port A writes byte `0xAA` and Port B writes byte `0xBB`. The stored byte must be `0xAA`. A same-cycle read of that byte must return `0xAA`. Both STATUS registers must then have bit 3 set. A write of `0x11` by Port A to `0x10000000` and a write of `0x22` by Port B to `0x10000001` in the same cycle must store both bytes.

Conflict is sticky. Software clears it by writing 1 to STATUS bit 3 (write-1-to-clear) in the register it wants to clear. Writing 0 must not clear it. The bit is set in both STATUS registers, and each register clears only its own bit.

## 5. DMA

MMIO base `0x30000000`. Registers are 32-bit, little-endian, and 4-byte aligned. A defined register responds to LW, LWU, and SW only.

| Offset | Name | Meaning |
| --- | --- | --- |
| `0x00` | SRC | Source byte address. |
| `0x04` | DST | Destination byte address. |
| `0x08` | LEN | Byte count. |
| `0x0C` | CTRL | bit 0 start, bit 1 abort. Reads as 0. |
| `0x10` | STATUS | bit 0 busy, bit 1 done, bit 2 fault, bit 3 conflict. |

STATUS bit 0 is read-only. Writing 1 to bit 1, bit 2, or bit 3 clears that sticky bit and no other bit. busy is set by a start that is accepted and cleared when the copy completes, faults at the start check, or is aborted. CTRL bit 0 = 1 requests a start. CTRL bit 1 = 1 aborts an in-flight copy. If one write has both bits set and the DMA is busy, the abort wins and the start is ignored. If both bits are set while idle, the abort is ignored and the start is considered.

A start must be refused, STATUS.fault set, STATUS.busy left 0, STATUS.done cleared, and no byte written, when any of the following holds:

* DMA STATUS.busy is already 1, or DMA STATUS.fault is already 1.
* The accelerator STATUS.busy is 1.
* LEN is not a multiple of 8, or LEN is not in [1, 524288].
* SRC or DST is not 8-byte aligned.
* Either half-open range [SRC, SRC+LEN) or [DST, DST+LEN) is not entirely inside `0x10000000 .. 0x1007FFFF`. Address arithmetic is mathematical. Wrap out of 32 bits is a fault.
* Any byte of either DMA range overlaps a source or destination byte of an in-flight accelerator operation.

DMA must never write ROM or MMIO. The copy is pure bytes and must not apply arithmetic. On an accepted start, busy = 1 and done = 0. On successful completion, busy = 0 and done = 1.

Overlapping SRC and DST are legal. The observable result must equal this procedure, which reads and writes current memory one byte at a time in ascending address order:

```
for i from 0 to LEN-1:
    memory[DST + i] = memory[SRC + i]
```

This order is deterministic. When DST > SRC and the ranges overlap, the result is the ascending-order result above. It is not the downward copy used by the C library in that case. The contract requires ascending order anyway.

Abort is not all-or-nothing. Beats already committed must stay committed. Abort must write nothing further and must not roll those beats back. Bytes already copied stay as a committed prefix, and bytes not yet copied stay at their old values. Programmers who need all-or-nothing must not abort a DMA. After abort, busy = 0 and done = 0. fault and conflict are left as they were.

Each committed beat is 8 bytes in ascending order, and each beat is atomic with respect to Port A under section 3. A scalar store to a different byte in the same cycle commits as well. A scalar store to the same byte wins, drops that Port B byte, and sets conflict in both STATUS registers.

The accelerator completion rule is the opposite of DMA abort: an accelerator abort must not leave a partial destination. That rule is stated in ACCELERATOR.md and must not be applied in reverse to DMA.
