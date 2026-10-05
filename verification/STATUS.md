# Current synthesis and verification status

This records the work against main commit
`288abae9a50e3fc19d9f2148ed18ae78eb37527a`. Saved receipts are in
[current/](current/); source hashes identify the exact inputs to each run.
The historical HARDWARE_V1 report is not the status of these changes.

## Completed

- Reproducible Make targets for assembly, RTL regression, synthesis, netlist
  simulation, Why3 proofs and SPICE smoke simulations. The assembler builds
  with `-Wall -Wextra -Werror`; its freshly generated tile image matches the
  checked-in 400-byte program without modification.
- Thirteen RTL benches pass. They include 4,138 rectangle-bound comparisons,
  2,503 overlap comparisons against the original algorithms, 600 randomized
  memory cycles checked against the original implementation, PROJECT result
  and capacity checks (including two strided 2x2 output matrices), the
  whole-system ROM program and abort/conflict tests.
- PROJECT now retains both distinct results. A matrix transaction whose result
  cannot fit the configured buffer fails before publication. Oversized and
  arithmetic-overflow transactions are checked for unchanged destinations.
- Bounds and overlap checks use bounded arithmetic and row-interval merging.
  SRAM writes use individual register enables and banked reads. These preserve
  the existing prototype's semantics while making elaboration tractable.
- The frozen tile's synthesized generic netlist matches RTL every cycle and
  all 512 result bytes match an independent integer reference.
- A matrix preflight extracted from the whole-top word-level checkpoint maps
  to 317,343 generic cells with zero check errors. Its synthesized PROJECT
  datapath passes the 1x1 and strided 2x2 results, overflow discard and capacity
  rejection checks against the same independent constants as the RTL bench.
  This is a standalone matrix check; final whole-top mapping is still running.
- All 168 emitted Why3 goals are Valid with Why3 1.8.0 / Z3 4.13.3: compiler
  121, ISA checks 13, tile 12, accelerator 5, memory 14 and arithmetic 3.
  `why3/isa.mlw` has predicates but no goals; it only type-checks.
- The inverter, full-adder and bitcell transient decks run with ngspice 44.2.
  Their relative include paths work from a fresh checkout.

## Synthesis profile

The whole-top word-level stage passed with 139,744 primitive cells and six
explicit memories. Final whole-top generic gate expansion is still running;
its cell count is not yet confirmed. The tile gate result is complete.

The flow uses OSS CAD Suite 2026-10-04, Yosys 0.69+190 and the slang frontend.
Whole-system synthesis keeps component hierarchy; the tile is synthesized as
one module. Generic outputs retain explicit memories and map combinational
logic and registers to Yosys primitives. They are not standard-cell netlists.
Bounded arithmetic stages, width reduction and constant folding precede dynamic
byte selectors, allowing repeated selectors to share their inputs before gate
expansion. Atomic checkpoints are saved in `build/` every four mapping batches.

Yosys `memory_dff` in this version disconnected eight matrix read bytes with
PROJECT enabled. The recipe uses `memory -nomap -nordff` and retains explicit
read registers; both stages require `check -assert`. No undriven-net warnings
are suppressed. Final synthesis statistics are recorded in the saved logs.

The prototype implements 1,536 SRAM bytes, shadow storage and atomic publication
with registers, a 64 KiB externally loaded ROM, and a 512-byte matrix result
buffer. It does **not** implement the specified full 512 KiB SRAM. Higher SRAM
addresses miss rather than wrap. The read banking is not an SRAM macro mapping.

## Remaining ASIC work

A process/PDK and clock target have not been supplied. `make synth-asic` accepts
`LIBERTY` and `CLOCK_PS` to perform standard-cell mapping when these are known;
that target has not been validated against an actual process library. It maps
remaining memories to logic and does not bind foundry SRAM/ROM macros.

Before an ASIC can be called complete, select the process and memory macros,
resolve the full-memory implementation, provide timing/IO/reset constraints,
and perform technology mapping, static timing, floorplanning, placement,
clock-tree synthesis, routing, extraction, DRC/LVS and signoff. The illustrative
SPICE cells do not establish any foundry process, silicon area or timing result.

The Why3 results concern mathematical models, not an RTL equivalence proof.
The simulations do not establish complete ISA coverage. Expanding those claims
requires additional specification and verification work.
