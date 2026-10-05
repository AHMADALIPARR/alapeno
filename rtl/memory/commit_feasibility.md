# Memory and commit feasibility

This is a historical account of the earlier tile runs and storage layout.
Current storage uses 1536 bytes of bank-read register arrays, and PROJECT
stores both results compactly. See [sram_cut.md](sram_cut.md) and
[verification/STATUS.md](../../verification/STATUS.md) for current verification
and synthesis results. The older counts below describe their original scripts.

This note is not a new architecture and does not change the tile contract. It quotes the Yosys log already committed at `e5bc05b` as `verification/rtl/logs/yosys_synth.log`. That log does not name a device, and it prints no timing. Nothing here is a claim that a named FPGA or ASIC can implement this RTL.

## What the log actually ran

The script line is:

```
-- Running command `plugin -i /opt/oss-cad-suite/share/yosys/plugins/slang.so; read_slang --std latest /workspace/alapeno/rtl/core/alapeno_pkg.sv /workspace/alapeno/rtl/mac/alapeno_mac.sv /workspace/alapeno/rtl/matrix/alapeno_matrix.sv /workspace/alapeno/rtl/matrix/alapeno_tile_ctrl.sv; hierarchy -check -top alapeno_tile_ctrl; proc; opt; fsm; opt; memory -nomap; opt; techmap; opt; stat' --
```

The memory pass names the scratch array and does not map it. The first lines of that pass are:

```
7. Executing MEMORY pass.

7.1. Executing OPT_MEM pass (optimize memories).
Performed a total of 16 transformations.

7.2. Executing OPT_MEM_PRIORITY pass (removing unnecessary memory write priority relations).
Performed a total of 3160 transformations.

7.3. Executing OPT_MEM_FEEDBACK pass (finding memory read-to-write feedback paths).
  Analyzing alapeno_tile_ctrl.u_matrix.obuf write port 0.
```

`stat` then leaves that array as one memory cell:

```
=== alapeno_tile_ctrl ===

        +----------Local Count, excluding submodules.
        | 
     4904 wires
   111731 wire bits
       57 public wires
     2349 public wire bits
       13 ports
      591 port bits
    44288 cells
    18957   $_AND_
     4251   $_MUX_
      108   $_NOT_
     7404   $_OR_
      551   $_SDFFE_PP0P_
    13016   $_XOR_
        1   $mem_v2

End of script. Logfile hash: 0da3602271, time: 10.75s, user: 12.57s, system: 0.61s, MEM: 312.61 MB peak
Yosys 0.69+187 (git sha1 2f08661dd, Release, Clang /usr/bin/clang++ 21.1.8)
```

The array Yosys is analyzing is `logic [7:0] obuf [0:131071]` in `rtl/matrix/alapeno_matrix.sv`. The command used `memory -nomap`, so this log never shows `memory_map`. The word SIGKILL is not in this file. The reason given for `-nomap` is that an earlier map of this same `obuf` was killed. This log does not itself record that kill, and it does not show a successful map either.

## Can the wide memories be synthesized?

No conclusion from this log says they can.

The scratch `obuf` was left as one `$mem_v2`. Mapping it to memory cells was not done in the run that produced this stat. There is no area and no timing for it.

Whole-memory reset and whole-array publication live in `rtl/memory/alapeno_mem.sv`, which was not a file in the command above. Reset writes all 524288 `sram` bytes, all 524288 `shadow` bytes, and all 524288 `dirty` bits in one clock. Publish walks those same 524288 dirty bits in one clock and copies every dirty shadow byte into `sram`. Discard clears every dirty bit in one clock and does not copy. None of those loops appear in this Yosys run. They are larger than `obuf`, and `obuf` was the array that was not mapped. This log therefore does not show that the reset or the publication can be synthesized.

## Behavior that has to stay

These are properties of the current RTL, not results from the Yosys stat.

Old destination bytes stay visible until a successful publish. `visible_byte` returns `sram` unless `b_publish` is set and that byte is dirty, in which case it returns the shadow byte. A shadow write does not change `sram`.

Abort and fault do not publish a partial destination. The matrix raises `b_discard` on its fail path and does not raise `b_publish`. Discard clears `dirty` and leaves `sram` unchanged. The tile controller forwards that discard and only clears busy with done set when the matrix reports complete.

Port A wins a same-byte contest. A Port A write updates `sram` even when Port B writes the same byte in that cycle, and the Port B byte is dropped. On publish, a Port A write to a dirty byte is what lands in `sram`, not the shadow byte. Either case sets `conflict`.

DMA abort keeps the committed prefix. DMA writes go straight to `sram` through Port B with shadow off, eight bytes at a time. Abort returns the DMA to idle and stops further writes. Bytes already stored stay. DMA does not roll the prefix back, and it does not use the shadow publish path.

## 2026-10-04

Yosys 0.69+187 was run on `alapeno_tile_ctrl` after the matrix publish buffer depth was parameterized. The tile instance elaborates `OBUF_BYTES=512`. The command was:

```
/opt/oss-cad-suite/bin/yosys -Q -l /tmp/yosys_tile_mem.log -p 'plugin -i /opt/oss-cad-suite/share/yosys/plugins/slang.so; read_slang --std latest /workspace/alapeno/rtl/core/alapeno_pkg.sv /workspace/alapeno/rtl/matrix/alapeno_matrix.sv /workspace/alapeno/rtl/matrix/alapeno_tile_ctrl.sv; hierarchy -check -top alapeno_tile_ctrl; proc; memory; techmap; stat'
```

Exit code 0. The script uses `memory`, not `memory -nomap`. The `stat` cell list has no `$mem_v2`. `memory_map` printed `Mapping memory \u_matrix.obuf` and `created 512 $dff cells and 0 static cells of width 8.`
