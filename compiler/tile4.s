# SPDX-License-Identifier: AGPL-3.0-only
# Frozen 4x4 tile host sequence from spec/accelerator/TILE.md.
# DMA STATUS polled at 0x30000010 (MEMORY.md §5 / rtl/dma/alapeno_dma.sv
# mmio_addr 12'h010). TILE.md names the DMA base but not the STATUS offset;
# MEMORY.md and the RTL agree on +0x10.

# ---- 4.2 load A at 0x10000000 (flat: 2,4,0,0, 3,3,0,4, 3,3,3,2, 2,1,2,0) ----
lui   x10, 0x1000          # x10 = PTR_A = 0x10000000
addi  x11, x0, 2
sd    x11, 0(x10)
addi  x11, x0, 4
sd    x11, 8(x10)
sd    x0, 16(x10)
sd    x0, 24(x10)
addi  x11, x0, 3
sd    x11, 32(x10)
addi  x11, x0, 3
sd    x11, 40(x10)
sd    x0, 48(x10)
addi  x11, x0, 4
sd    x11, 56(x10)
addi  x11, x0, 3
sd    x11, 64(x10)
addi  x11, x0, 3
sd    x11, 72(x10)
addi  x11, x0, 3
sd    x11, 80(x10)
addi  x11, x0, 2
sd    x11, 88(x10)
addi  x11, x0, 2
sd    x11, 96(x10)
addi  x11, x0, 1
sd    x11, 104(x10)
addi  x11, x0, 2
sd    x11, 112(x10)
sd    x0, 120(x10)

# ---- load B at 0x10000080 (flat: 1,3,2,2, 4,3,2,3, 0,3,2,4, 2,1,0,1) ----
addi  x10, x10, 0x80       # x10 = PTR_B = 0x10000080
addi  x11, x0, 1
sd    x11, 0(x10)
addi  x11, x0, 3
sd    x11, 8(x10)
addi  x11, x0, 2
sd    x11, 16(x10)
addi  x11, x0, 2
sd    x11, 24(x10)
addi  x11, x0, 4
sd    x11, 32(x10)
addi  x11, x0, 3
sd    x11, 40(x10)
addi  x11, x0, 2
sd    x11, 48(x10)
addi  x11, x0, 3
sd    x11, 56(x10)
sd    x0, 64(x10)
addi  x11, x0, 3
sd    x11, 72(x10)
addi  x11, x0, 2
sd    x11, 80(x10)
addi  x11, x0, 4
sd    x11, 88(x10)
addi  x11, x0, 2
sd    x11, 96(x10)
addi  x11, x0, 1
sd    x11, 104(x10)
sd    x0, 112(x10)
addi  x11, x0, 1
sd    x11, 120(x10)

# ---- 4.3 accelerator MMIO at 0x20000000 ----
lui   x20, 0x2000          # accel base
addi  x11, x0, 1
sw    x11, 0x08(x20)       # OP = 1 (MATMUL)
addi  x11, x0, 4
sw    x11, 0x0C(x20)       # M = 4
sw    x11, 0x10(x20)       # N = 4
sw    x11, 0x14(x20)       # K = 4
lui   x12, 0x1000          # 0x10000000
sw    x12, 0x18(x20)       # PTR_A
addi  x13, x12, 0x80       # 0x10000080
sw    x13, 0x1C(x20)       # PTR_B
addi  x14, x12, 0x100      # 0x10000100
sw    x14, 0x20(x20)       # PTR_C
addi  x11, x0, 32
sw    x11, 0x24(x20)       # LDA = 32
sw    x11, 0x28(x20)       # LDB = 32
addi  x11, x0, 128
sw    x11, 0x2C(x20)       # LDC = 128
sw    x0, 0x34(x20)        # MODE = 0
addi  x11, x0, 1
sw    x11, 0x00(x20)       # CTRL = 1 (start)

# ---- 4.4 poll accel STATUS at 0x20000004 until (busy,done,fault)=(0,1,0) ----
addi  x15, x0, 2           # expect bits[2:0] == 2
accel_poll:
lwu   x16, 0x04(x20)
andi  x17, x16, 7
beq   x17, x15, accel_done
jal   x0, accel_poll
accel_done:

# ---- 4.5 DMA at 0x30000000: SRC, DST, LEN, CTRL; poll STATUS at +0x10 ----
lui   x21, 0x3000          # dma base
addi  x14, x12, 0x100      # SRC = 0x10000100 (rebuild; x14 may still hold it)
sw    x14, 0x00(x21)       # SRC
addi  x18, x12, 0x400      # DST = 0x10000400
sw    x18, 0x04(x21)       # DST
addi  x11, x0, 512
sw    x11, 0x08(x21)       # LEN = 512
addi  x11, x0, 1
sw    x11, 0x0C(x21)       # CTRL = 1
# STATUS at 0x30000010 (MEMORY.md / RTL); TILE.md does not override.
dma_poll:
lwu   x16, 0x10(x21)
andi  x17, x16, 7
beq   x17, x15, dma_done
jal   x0, dma_poll
dma_done:

halt
