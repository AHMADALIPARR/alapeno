SPDX-License-Identifier: AGPL-3.0-only
Copyright (C) 2026 Alapeno contributors
The grant is AGPL-3.0-only and there is no MIT license.

# Alapeno compute-tile milestone: non-field MATMUL 4x4x4

This file freezes one compute-tile workload. It does not redefine the accelerator
contract. Where any fact here would contradict `spec/accelerator/ACCELERATOR.md`,
ACCELERATOR.md wins and this file states that fact as already locked there.
Encodings, reset, and the SRAM window are locked in `spec/isa/ISA.md` and
`spec/memory/MEMORY.md`. Numeric ranges are locked in `spec/arithmetic/ARITHMETIC.md`.

Normative words: **must** and **must not**.

## 1. Frozen operation

One operation only:

| Parameter | Frozen value |
| --- | --- |
| OP | 1 (MATMUL) |
| MODE | 0 (MODE.field = 0; every other MODE bit 0) |
| M | 4 |
| N | 4 |
| K | 4 |
| A, B element | signed 64-bit little-endian, width 8 |
| C element | signed 256-bit little-endian limb tuple, width 32 (ACCELERATOR.md non-field MATMUL destination) |
| Field mode | not this tile |
| ROUTE, PROJECT, VADD, VSUB, RED.* | not this tile |
| Empty shape (M=0 or N=0) | not this tile |
| INT8 / INT32 | forbidden; this machine stays on the locked formats |

The machine must not switch to INT8 or INT32. There is no IEEE float. The field
prime remains `p = 18446744069414584321`. Extended integers and signed 256-bit
accumulators Z0..Z7, and X0..X31, are unchanged. ZMAC remains opcode `0x18`
funct3 6. The SRAM window remains `0x10000000` through `0x1007FFFF`.

## 2. Fixed addresses and strides

All pointers are inside the SRAM window. A and B are 8-byte aligned. C and the
host copy buffer are 32-byte aligned. The three rectangles do not overlap.

| Name | Address | Byte length | Role |
| --- | --- | --- | --- |
| PTR_A | `0x10000000` | 128 | A, M by K, row-major signed-64 |
| PTR_B | `0x10000080` | 128 | B, K by N, row-major signed-64 |
| PTR_C | `0x10000100` | 512 | C, M by N, row-major signed-256 limbs |
| PTR_C_COPY | `0x10000400` | 512 | host store destination for C |

| Stride register | Value | Rule |
| --- | --- | --- |
| LDA | 32 | `>= K * 8` and multiple of 8 |
| LDB | 32 | `>= N * 8` and multiple of 8 |
| LDC | 128 | `>= N * 32` and multiple of 32 |

Element `(r, c)` of a pointer `P` with stride `S` and width `W` is at
`P + r * S + c * W`, as ACCELERATOR.md already requires.

## 3. Seeded operands (Sovereign Reduction Algebra)

Generator constants (from `sovereign-reduction-algebra/j/biencoder.ijs`):

```
LCGA  = 48271
LCGM  = 2147483647
SEED0 = 20261002
RADIX = 5
```

Draw rule: start with `seed = SEED0`. For each draw,
`seed = (LCGA * seed) mod LCGM`, then `value = seed mod RADIX`.
Draw 16 values for A (row-major 4 by 4), then 16 more for B.

Exact matrices:

```
A = 2 4 0 0
    3 3 0 4
    3 3 3 2
    2 1 2 0

B = 1 3 2 2
    4 3 2 3
    0 3 2 4
    2 1 0 1
```

KNOWN product (from `sovereign-reduction-algebra/j/train_step.ijs`, row-major):

```
C = 18 18 12 16
    23 22 12 19
    19 29 18 29
     6 15 10 15
```

Each `C[m, n]` is the exact mathematical integer
`sum_{k=0}^{3} A[m, k] * B[k, n]`. The product above matches KNOWN exactly.
Each stored C element is four little-endian 64-bit limbs: limb 0 holds the
unsigned low 64 bits of the two's-complement value; limbs 1..3 are zero for
every element of this tile (every entry is in `0 .. 29`).

## 4. Host command sequence

Commands run in this order. Addresses and register values are exact. The core
is not trapped by this tile. One start, one tile, not a loop. There is no
interrupt; completion is by polling STATUS.

### 4.1 reset

Architectural reset as ISA.md and MEMORY.md already define:

* PC = 0
* every X register = 0
* every Z register = 0
* tcause = 0, tpc = 0
* every SRAM byte = 0
* accelerator STATUS idle: busy = 0, done = 0, fault = 0, conflict = 0
* DMA STATUS idle: busy = 0, done = 0, fault = 0, conflict = 0
* every other implemented MMIO register reads as 0
* ROM is not cleared

### 4.2 load

Place A and B by a sequence of scalar SD stores (8-byte stores). DMA is
SRAM-to-SRAM only (MEMORY.md), so the initial fill uses Port A stores.

For `i` in `0 .. 15`, store A flat element `i` (signed 64 LE) with SD to
`0x10000000 + 8*i`. Then for `i` in `0 .. 15`, store B flat element `i` with
SD to `0x10000080 + 8*i`. Total payload: 256 bytes (128 + 128). After load,
SRAM holds A and B at those addresses and every byte of C at `0x10000100` is
still 0. PTR_C_COPY is still 0.

Flat A order: `2, 4, 0, 0, 3, 3, 0, 4, 3, 3, 3, 2, 2, 1, 2, 0`.
Flat B order: `1, 3, 2, 2, 4, 3, 2, 3, 0, 3, 2, 4, 2, 1, 0, 1`.

### 4.3 execute

Write accelerator registers at base `0x20000000` (offsets from ACCELERATOR.md),
then start once:

| Address | Register | Value written |
| --- | --- | --- |
| `0x20000008` | OP | 1 |
| `0x2000000C` | M | 4 |
| `0x20000010` | N | 4 |
| `0x20000014` | K | 4 |
| `0x20000018` | PTR_A | `0x10000000` |
| `0x2000001C` | PTR_B | `0x10000080` |
| `0x20000020` | PTR_C | `0x10000100` |
| `0x20000024` | LDA | 32 |
| `0x20000028` | LDB | 32 |
| `0x2000002C` | LDC | 128 |
| `0x20000034` | MODE | 0 |
| `0x20000000` | CTRL | 1 (bit 0 start; bit 1 = 0) |

VL is unused for MATMUL and is not written for this tile. The start must be
accepted under ACCELERATOR.md (engine idle, fault clear, DMA idle). The core
must not trap because of this start.

### 4.4 status

Poll STATUS at `0x20000004` with LW or LWU.

* Completion: `busy = 0` and `done = 1` and `fault = 0`.
* Failure: `fault = 1` and C unchanged (no destination byte published).
* Polling is the host command. There is no interrupt in this tile.

### 4.5 store

The result commit is the accelerator write of C at successful completion.
The host store command then copies C to PTR_C_COPY with DMA base
`0x30000000`:

| Address | Register | Value |
| --- | --- | --- |
| `0x30000000` | SRC | `0x10000100` |
| `0x30000004` | DST | `0x10000400` |
| `0x30000008` | LEN | 512 |
| `0x3000000C` | CTRL | 1 (start) |

After DMA STATUS shows busy = 0 and done = 1 and fault = 0, PTR_C_COPY holds
the same 16 signed-256 limb tuples as C. The exact output integers are the
KNOWN matrix above. Encoding of each integer `v` in `0 .. 29`: four LE limbs
`(v, 0, 0, 0)`.

## 5. Overflow and fault

This tile must not fault. Every seeded element is in `0 .. 4`, so every
product and every dot product fits in signed 64 and in signed 256.

A signed 64-bit product lies in `[-2^126 + 2^63, 2^126]`. The extreme
positive product is `(-2^63) * (-2^63) = 2^126`. The extreme negative
product is `(-2^63) * (2^63 - 1) = -2^126 + 2^63`. A sum of K such products
therefore lies in `[-K * 2^126, K * 2^126]`. Signed 256 holds
`[-2^255, 2^255 - 1]`. `K * 2^126` stays inside that range for every
`K <= 2^129 - 1`. This tile has K = 4, and the accelerator limit is
`K <= 64`. Both are far below `2^129`. So no non-field MATMUL of signed
64-bit elements at legal K, including this tile, can produce a dot product
outside signed 256.

The general rule stays, and it is not a stimulus for this tile: if an exact
non-field dot product were outside signed 256, STATUS.fault = 1, done = 0,
and C is unchanged. That antecedent cannot occur on the signed-64 ports
with `K <= 64`. A check of this tile must not invent an INT8 or INT32
matrix, a K above 64, or any other operand outside signed 64 in order to
force the fault. Abort and shape faults follow ACCELERATOR.md and also
leave C unchanged.

The Why3 name for the unreachability statement is `tile_k4_cannot_overflow`.
The Why3 name for the general fault rule is `tile_overflow_faults_without_write`.
Neither statement says the RTL obeys it.

## 6. Out of scope for this tile

Empty shapes, field mode (MODE.field = 1), ROUTE, PROJECT, VADD, VSUB, and
RED.* are not this tile. They remain defined only by ACCELERATOR.md.
