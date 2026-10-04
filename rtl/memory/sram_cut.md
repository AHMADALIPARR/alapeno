# SRAM cut for alapeno_mem

`alapeno_mem` cannot be mapped as written. The arrays are:

```systemverilog
logic [7:0] rom [0:65535];
logic [7:0] sram [0:524287];
logic [7:0] shadow [0:524287];
logic       dirty [0:524287];
```

Yosys `memory` without `-nomap` calls `memory_map`, which converts memories to word-wide DFFs. Reset, discard, and publish also walk all 524288 entries inside `always_ff`:

```systemverilog
for (i = 0; i < 524288; i = i + 1) begin
  sram[i] <= 8'h00;
  shadow[i] <= 8'h00;
  dirty[i] <= 1'b0;
end
for (i = 0; i < 524288; i = i + 1) dirty[i] <= 1'b0;
for (i = 0; i < 524288; i = i + 1) begin
  if (dirty[i]) begin
    ba = SRAM_LO + i[31:0];
    if (a_valid && a_we && range_hit(ba, a_addr, a_size))
      sram[i[18:0]] <= lane_byte(a_wdata, ba, a_addr);
    else
      sram[i[18:0]] <= shadow[i[18:0]];
    dirty[i] <= 1'b0;
  end
end
```

The live Yosys is still inside `read_slang`. It was started with `--unroll-limit 4000000`, so slang is unrolling those loops. Hierarchy has not run. This note does not claim a measured kill.

The frozen tile (`alapeno_tile_ctrl`) uses SRAM offsets `ptr_a` 0, `ptr_b` `0x80`, `ptr_c` `0x100`, `ldc` 128, and 4 rows. C occupies `4 * 128 = 512` bytes, so the last C byte is `0x100 + 512 - 1 = 767`. The smallest SRAM depth that contains bytes 0 through 767 is 768. That is the cut that would let the unroll finish. It was not re-run in Yosys, because a second Yosys was forbidden while the stuck read holds the machine.

`alapeno_top` also elaborates `alapeno_matrix` with the default `obuf [0:131071]`, which is not in `alapeno_mem`.
