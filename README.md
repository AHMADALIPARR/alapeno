# alapeno

Hardware stack. There is no Python in this tree.

Licensed under the GNU Affero General Public License v3.0 only (`LICENSE`). Not MIT.

`spec/` holds the programmer-visible contracts: `isa/ISA.md`, `memory/MEMORY.md`, `arithmetic/ARITHMETIC.md`, and `accelerator/ACCELERATOR.md`.

`why3/` holds four standalone modules (`isa.mlw`, `memory.mlw`, `arithmetic.mlw`, `accelerator.mlw`) under AGPL-3.0-only. Why3 1.8.0 loaded the four modules, 7 goals Valid, 0 failures. Those goals are the termination VCs the tool generated (memory `step_byte`, arithmetic `fold_sum` `route_dot` `field_route_dot`, accelerator `dot` `route_dot` `field_route_dot`). `isa.mlw` loaded with no goals. This does not claim proofs of `x0_zero`, `trap_writes_nothing`, `dma_stays_in_sram`, or `mac_exact`.

Only the files present in this commit exist. `rtl/` (`core/`, `dma/`, `matrix/`, `memory/`, `vector/`), `compiler/`, `verification/isa/`, and `verification/rtl/` are not in this commit: no RTL and no synthesis results.

`spice/` holds illustrative Level-1 MOSFET netlists (not a foundry PDK): `cells/` (`and2`, `dff`, `fa`, `inv`, `mux2`, `nand2`, `nor2`, `xor2`, `models.inc`), `clock/` (`clk_buf`, `clk_gate`, `ring3`), `corners/` (`models_ff`, `models_ss`, `models_tt`), `mac/mac4.sp`, `sram/` (`bitcell_6t`, `array_2x2`), and `COPYING` (AGPL-3.0 text).

`verification/physical/` has three transient decks (`inv_tran.sp`, `fa_tran.sp`, `bitcell_hold.sp`) and ngspice logs in `logs/`. Each log is a completed transient listing headed Sat Oct 3 20:06:56 2026 (analysis times 0.00527863 s, 0.0362391 s, and 0.00826417 s). They are raw voltage-versus-time output, not a claim of timing closure, functional signoff, or silicon results.
