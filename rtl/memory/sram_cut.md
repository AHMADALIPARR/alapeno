# SRAM implementation profile

The current `alapeno_mem` stores 1536 bytes (offsets 0 through 1535) of the
specification's SRAM window `0x10000000 .. 0x1007ffff`. The frozen tile's copy
starts at offset 1024 and ends at 1535. A 768-byte cut would hold C but would
not hold this copy. Higher offsets are rejected by `sram_stored`; they do not
alias low storage.

SRAM, shadow bytes and dirty flags are packed register arrays with one process
per byte. This directly expresses the existing priority: reset, Port A write,
atomic publication, and direct Port B write. Shadow stores remain invisible;
abort/discard clears dirty flags without changing SRAM. Publication copies
all dirty bytes in one cycle, while Port A wins a contest. The ROM remains a
65536-byte loadable memory.

The previous implementation generated thousands of inferred write ports from
whole-array reset and publication plus dynamic multi-lane writes. The current
register implementation avoids the memory-port priority expansion. It is not
an SRAM macro mapping and does not implement all 512 KiB of the specification.

`tb_mem_equiv.sv` compares all stored bytes, shadow bytes, dirty flags,
registered read values and conflict signals against the baseline implementation
for 600 randomized cycles, including publication/discard collisions and sizes
larger than the 32-lane bus. Run it with `make test`.

Reads visit the 32 byte banks once each and rotate the bank-order bus into
address-order lanes. Each bank selects among 48 stored bytes, instead of each
lane selecting across all 1536 bytes. This preserves unaligned and crossing
reads while reducing the multiplexers required by register storage.

For current measured synthesis results and remaining ASIC prerequisites,
see [verification/STATUS.md](../../verification/STATUS.md).
