# Alapeno

Alapeno is an RTL and verification hardware stack with a custom integer ISA, a
matrix/vector accelerator, DMA, a C assembler, Why3 models and illustrative
SPICE cells. It is licensed under AGPL-3.0-only. Current results and unfinished
ASIC work are recorded in [verification/STATUS.md](verification/STATUS.md).

## Build and verification

Install a C compiler, GNU Make, Icarus Verilog, and Yosys with the `slang`
frontend (the OSS CAD Suite supplies both RTL tools). Why3 1.8.0 with Z3 4.13.3
and ngspice are required for their separate targets. Add the tools to `PATH`
and run `why3 config detect` to register the installed Z3 prover.

```sh
make test        # strict assembler build, image comparison, 13 RTL benches
make synth       # whole alapeno_top, generic logic and explicit memories
make synth-tile  # frozen tile controller with the same synthesis flow
make gate-test   # synthesize the tile, then compare its netlist with RTL
make proofs      # all runnable Why3 goals; ISA predicates type-check only
make physical    # three illustrative transient decks, not PDK verification
```

Generated logs, simulation executables, synthesis scripts and netlists are in
`build/`. Every run records source hashes, tool versions, commands and exit
status. `make test` runs the freshly assembled tile program without patching it
and compares the full 512-byte copied result. Historical logs remain under
`verification/rtl/logs/`, `verification/isa/logs/` and
`verification/physical/logs/`. The older
[HARDWARE_V1.md](verification/HARDWARE_V1.md) describes its original snapshot.

Tool paths can be overridden with `CC`, `IVERILOG`, `VVP`, `YOSYS`, `WHY3` and
`NGSPICE`. For proofs, `WHY3_CONFIG` selects an existing prover configuration
and `PROVER` defaults to `Z3,4.13.3` (the version used for the saved proofs).

## ASIC mapping

```sh
LIBERTY=/path/to/standard_cells.lib CLOCK_PS=10000 make synth-asic
```

This target maps registers and combinational gates to the supplied Liberty
library. `CLOCK_PS` is the ABC delay target, not a measured chip clock period.
A selected PDK, memory implementation, timing constraints, place and route,
extraction, and signoff checks are still required for an ASIC. No process,
area, timing or silicon result is claimed for the illustrative SPICE models.

## Implemented profile

The locked specifications are in `spec/`. X0..X31 are 64-bit general registers;
Z0..Z7 are signed 256-bit accumulators. ZMAC is opcode `0x18`, funct3 6. The
field prime is `18446744069414584321`. There is no IEEE floating point or INT8
replacement datapath.

The current prototype physically stores the first **1536 bytes** of the
specified 512 KiB SRAM address window. Higher offsets miss rather than wrap.
Whole-array reset and atomic shadow publication use registers; these are not
inferred single-port SRAM macros. The top-level accelerator has a 512-byte
matrix result buffer. Matrix operations exceeding its capacity now fail and
discard without publication. PROJECT stores its two results compactly so
both destinations receive their distinct values.

The frozen non-field 4x4x4 MATMUL uses A at `0x10000000`, B at `0x10000080`,
C at `0x10000100` and its 512-byte copy at `0x10000400`. Its result is:

```text
18 18 12 16
23 22 12 19
19 29 18 29
 6 15 10 15
```

Why3 results prove properties of the mathematical models. Differential tests
and RTL simulations exercise the implementation; they do not establish full
RTL-to-model equivalence or complete ISA coverage.
