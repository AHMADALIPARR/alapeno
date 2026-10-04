# alapeno

Alapeno is an RTL-and-verification hardware stack. It is not a chip. The license is the GNU Affero General Public License, version 3 only (`LICENSE`). Spec and RTL sources carry `SPDX-License-Identifier: AGPL-3.0-only`. The tree has no Python files.

`verification/HARDWARE_V1.md` was written against commit `5dda740` and says no log shows `tile_k4_cannot_overflow` printed Valid. That sentence is stale. `verification/isa/logs/why3-tile-k4.log` prints that goal Valid. This file follows logs and sources at HEAD, not that note.

## Locked spec

`spec/isa/ISA.md` locks general registers X0..X31 and signed 256-bit accumulators Z0..Z7. ZMAC is opcode `0x18` with funct3 6. `spec/arithmetic/ARITHMETIC.md` and `spec/accelerator/TILE.md` lock the field prime `p = 18446744069414584321`. `spec/memory/MEMORY.md` and TILE.md lock the SRAM window `0x10000000 .. 0x1007FFFF`. TILE.md says the machine must not switch to INT8 or INT32, and that there is no IEEE float.

TILE.md freezes one non-field 4x4x4 MATMUL (OP 1, MODE 0). The addresses in that file are PTR_A `0x10000000` (128 bytes), PTR_B `0x10000080` (128 bytes), PTR_C `0x10000100` (512 bytes), and PTR_C_COPY `0x10000400` (512 bytes), with LDA 32, LDB 32, and LDC 128. The known C matrix there is:

```
C = 18 18 12 16
    23 22 12 19
    19 29 18 29
     6 15 10 15
```

## RTL sources

`rtl/` holds SystemVerilog: `alapeno_top.sv`, `core/alapeno_core.sv`, `core/alapeno_pkg.sv`, `dma/alapeno_dma.sv`, `mac/alapeno_mac.sv`, `matrix/alapeno_accel.sv`, `matrix/alapeno_matrix.sv`, `matrix/alapeno_tile_ctrl.sv`, `memory/alapeno_mem.sv`, and `vector/alapeno_vector.sv`.

An earlier README said these RTL sources were not synthesized and that there were no synthesis results. That is no longer true for the tile controller. Finished Yosys stats exist for `alapeno_tile_ctrl`. There is still no measured synthesis stat for `alapeno_top`.

## What a log shows proved

Only goals whose logs print `Prover result is: Valid` are treated as proved. A predicate in a source file is not a proof.

`verification/isa/logs/why3-compile.log` prints 121 lines of `Prover result is: Valid`, all for `compiler/compile.mlw`, and no other prover result. `verification/isa/logs/why3-isa.log` prints Valid for `x0_after_add`, `zmac_is_acc_plus_mul`, `modp_neg_one`, `compile_zmac_then_halt`, `red_two_word_sum`, and `add_wrap_not_a_trap` in `verification/isa/isa_check.mlw`. `verification/isa/logs/why3-tile-k4.log` prints Valid for `dot4'vc`, `tile_k4_cannot_overflow`, `elem64_addr_is_ptr_plus_8i`, `decode_i64_le_seeded_two`, and `decode_i64_le_seeded_four` in `why3/tile.mlw`.

Other predicates were not proved. Comments in `why3/accelerator.mlw`, `why3/memory.mlw`, and `why3/arithmetic.mlw` name further goals, but those files have no log under `verification/isa/logs/`. The header of `why3/isa.mlw` says no goal was printed Valid. `why3/tile.mlw` says no RTL satisfaction is claimed. None of the Valid lines above is a proof about the SystemVerilog.

## What a log shows simulated

Counted runs are logs that print `vvp_exit 0` or `vvp_exit: 0` and a PASS line. `verification/rtl/logs/mac_ref.log` has result lines and no vvp exit, so it is not counted.

Logs that do not name a commit:

- `verification/rtl/logs/tile4_rom.log` prints `PASS TILE4 ROM: all 512 copy bytes matched at 0x10000400 (tile4.bin loaded unchanged)` and `vvp_exit 0`.
- `verification/rtl/logs/tile_top.log` prints `PASS spin: pc=0 tcause=0 halted=0 while ROM image loads`, `PASS TILE: all 512 copy bytes matched at 0x10000400`, and `vvp_exit 0`. `verification/rtl/tb_tile4_rom.sv` says that bench is not a run of `tile4.s`.
- `verification/rtl/logs/les_diff.log` prints `PASS reset: complete=0 fail=0 publish=0 (idle)`, `PASS LES: 4x4x4 non-field MATMUL C bit-exact (TILE known)`, `PASS abort: kill while not idle set saw_discard, fail stayed 0, no publish; 512 C bytes unchanged (TILE product)`, and `PASS field-fault: field_mode residue >= p (A[0]=P) raised fail and b_discard; 512 C bytes unchanged (seed 0xA5). Not a MATMUL overflow.`, then `vvp_exit 0`. The same file also records an earlier probe with `vvp_exit 1`.
- `verification/rtl/logs/accel_abort.log` prints `PASS ACCEL ABORT: all 32 destination bytes unchanged at 0x10000020 (seed 5a); shadow product was not published` and `vvp_exit 0`.
- `verification/rtl/logs/porta_contest.log` prints `PASS PORT A: stored 0xAA, same-cycle read mux 0xAA, split 0x11/0x22 both stored, STATUS bit3 set in DMA and accel` and `vvp_exit 0`.
- `verification/rtl/logs/dma_abort.log` prints `PASS DMA ABORT: committed prefix 8 bytes kept, remaining 24 bytes unchanged, busy=0 done=0` and `vvp_exit 0`.
- `verification/rtl/logs/zmac_neg.log` prints `PASS ZMAC NEG: a=-5 b=7 Z=11 -> published accumulator -24 (exact signed 256 limbs)` and `vvp_exit 0`.
- `verification/rtl/logs/vec_extrema.log` prints `PASS VEC EXTREMA: RED.MIN of [INT64_MAX,-1,INT64_MIN,42] published INT64_MIN` and `vvp_exit 0`.

Logs that name a commit:

- `verification/rtl/logs/tile4_rom_7d67e15.log` records `git rev-parse HEAD: 7d67e15c7f3052602fa235aa66183763bda29e29`, the same TILE4 ROM PASS line, and `vvp_exit: 0`.
- `verification/rtl/logs/accel_abort_7d67e15.log`, `verification/rtl/logs/dma_abort_7d67e15.log`, and `verification/rtl/logs/porta_contest_7d67e15.log` each record `git rev-parse HEAD: 79743fe326138b8b9e3a2d281efb7fd2846a61f0`, `vvp_exit: 0`, and the same PASS line as the older log of that bench. The filenames say `7d67e15`. The recorded HEAD inside those three files does not.

The 512-byte compare in `verification/rtl/tb_tile4_rom.sv` still reads `dut.u_mem.sram`. That file says `alapeno_top` exports no SRAM data port.

## What a log shows synthesized

Both finished Yosys logs use top `alapeno_tile_ctrl`. Neither names a device or prints timing. Cell counts are not area.

`verification/rtl/logs/yosys_synth.log` is a finished run. Its script reads `alapeno_pkg.sv`, `alapeno_mac.sv`, `alapeno_matrix.sv`, and `alapeno_tile_ctrl.sv`, then runs `memory -nomap`, `techmap`, and `stat`. The log contains `Removing unused module `\alapeno_mac'.` The stat is 4904 wires, 111731 wire bits, 57 public wires, 2349 public wire bits, 13 ports, 591 port bits, and 44288 cells: 18957 `$_AND_`, 4251 `$_MUX_`, 108 `$_NOT_`, 7404 `$_OR_`, 551 `$_SDFFE_PP0P_`, 13016 `$_XOR_`, and 1 `$mem_v2`. The word SIGKILL is not in this log. `rtl/memory/commit_feasibility.md` says so, and says this log does not record the earlier map. Commit `e5bc05b` says memory mapping of `obuf` was killed and that the finished run used `memory -nomap` and left one `$mem_v2`.

`rtl/matrix/alapeno_tile_ctrl.sv` instantiates the matrix with `OBUF_BYTES` 512. `verification/rtl/logs/yosys_tile_mem.log` is the run whose script is `memory` (not `memory -nomap`), then `techmap`, then `stat`, on `alapeno_pkg.sv`, `alapeno_matrix.sv`, and `alapeno_tile_ctrl.sv`. The log does not print the text `OBUF_BYTES`. It does print `Mapping memory \u_matrix.obuf` and `created 512 $dff cells and 0 static cells of width 8.` The stat list has no `$mem_v2`. It reports 567020 wires, 5089351 wire bits, 574 public wires, 6863 public wire bits, 13 ports, 591 port bits, and 1934683 cells: 768634 `$_AND_`, 5321 `$_DFF_P_`, 485512 `$_MUX_`, 46694 `$_NOT_`, 252856 `$_OR_`, and 375666 `$_XOR_`. The mapped memory is those flip-flops, not a RAM macro. The log has no timing and names no device.

## What did not happen

There is no measured `alapeno_top` synthesis stat. `verification/rtl/logs/yosys_top.log` is not in the tree.

No log says a full-memory map of the default SRAM was killed. `rtl/memory/sram_cut.md` says it does not claim a measured kill. That note documents a 768-byte cut (bytes 0 through 767) and says that cut was not re-run in Yosys.

Through `cbc3cf0`, `rtl/memory/alapeno_mem.sv` declared `sram`, `shadow`, and `dirty` as `[0:524287]`. This tree sets `SRAM_BYTES` to 1536, so those three arrays are `[0:1535]`. `sram_cut.md` says the copy at `0x10000400` is byte 1024 and the last copy byte is 1535, so the 768-byte cut would not hold it. `rtl/matrix/alapeno_accel.sv` instantiates `alapeno_matrix #(.OBUF_BYTES(512))`. The matrix default in `alapeno_matrix.sv` stays 131072. `alapeno_tile_ctrl.sv` already used 512. Neither the 1536-byte SRAM nor that accelerator override has a Yosys stat.

## Assembler

`compiler/encode_check.s` says `ADD x1, x2, x3` must be `0x00221800`. That check is not a core run. No log in the tree records an assembler invocation. `compiler/tile4.s` is 121 lines and 3197 bytes. `verification/rtl/tile4.bin` is 400 bytes, matching `fread tile4.bin bytes=400` in the tile4 logs.

`spice/` holds illustrative netlists. Nothing above is a timing, area, FPGA, ASIC, or silicon result.
