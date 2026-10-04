# alapeno

Hardware stack. There is no Python in this tree.

Licensed under the GNU Affero General Public License v3.0 only (`LICENSE`). Not MIT.

`spec/` holds the programmer-visible contracts: `isa/ISA.md`, `memory/MEMORY.md`, `arithmetic/ARITHMETIC.md`, and `accelerator/ACCELERATOR.md`. ISA general registers are X0-X31. ZMAC is opcode `0x18` with funct3 6.

`why3/` holds four standalone modules (`isa.mlw`, `memory.mlw`, `arithmetic.mlw`, `accelerator.mlw`) under AGPL-3.0-only. Why3 1.8.0 loaded the four modules, 7 goals Valid, 0 failures. Those goals are the termination VCs the tool generated (memory `step_byte`, arithmetic `fold_sum` `route_dot` `field_route_dot`, accelerator `dot` `route_dot` `field_route_dot`). `isa.mlw` loaded with no goals. This does not claim proofs of `x0_zero`, `trap_writes_nothing`, `dma_stays_in_sram`, or `mac_exact`.

`compiler/` holds `compile.mlw` and `COPYING` (AGPL-3.0 text). `verification/isa/` holds `isa_check.mlw` and Why3 logs in `logs/` (`why3-compile.log`, `why3-isa.log`). Measured with Why3 1.8.0: `compile.mlw` 121 Valid, `isa_check.mlw` 6 Valid, zero timeouts in those logs (dated Sat Oct 3 20:32:16 2026 and Sat Oct 3 20:32:19 2026).

`rtl/` holds SystemVerilog sources: `alapeno_top.sv`, `core/` (`alapeno_core.sv`, `alapeno_pkg.sv`), `dma/alapeno_dma.sv`, `matrix/` (`alapeno_accel.sv`, `alapeno_matrix.sv`), `memory/alapeno_mem.sv`, and `vector/alapeno_vector.sv`. The RTL sources are present and were not synthesized. There are no synthesis results.

`verification/rtl/` holds `mac_ref.sv`, `tb_mac_ref.sv`, and `logs/mac_ref.log`. The log has five checks and the line `all integer mac vectors matched`:

```
check 0*0+0 -> 0
check 15*15+0 -> 225
check 15*15+31 wrap -> 0
check 2*3+4 -> 10
check 15*1+241 wrap -> 0
all integer mac vectors matched
```

`spice/` holds illustrative Level-1 MOSFET netlists (not a foundry PDK): `cells/` (`and2`, `dff`, `fa`, `inv`, `mux2`, `nand2`, `nor2`, `xor2`, `models.inc`), `clock/` (`clk_buf`, `clk_gate`, `ring3`), `corners/` (`models_ff`, `models_ss`, `models_tt`), `mac/mac4.sp`, `sram/` (`bitcell_6t`, `array_2x2`), and `COPYING` (AGPL-3.0 text).

`verification/physical/` has three transient decks (`inv_tran.sp`, `fa_tran.sp`, `bitcell_hold.sp`) and ngspice logs in `logs/`. Each log is a completed transient listing headed Sat Oct 3 20:06:56 2026 (analysis times 0.00527863 s, 0.0362391 s, and 0.00826417 s). They are raw voltage-versus-time output, not a claim of timing closure, functional signoff, or silicon results.
