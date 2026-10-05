// SPDX-License-Identifier: AGPL-3.0-only
// Differential check against the pre-optimization element-by-element validator.
module tb_rect_bounds;
  import alapeno_pkg::*;
  function automatic logic legacy_rect(
    input logic [31:0] base, input logic [31:0] stride,
    input logic [31:0] rows, input logic [31:0] cols, input logic [31:0] ew
  );
    integer r, c;
    logic [63:0] ea, last;
    logic ok;
    begin
      ok = 1'b1;
      for (r = 0; r < 64; r = r + 1) begin
        if (r < rows) begin
          for (c = 0; c < 64; c = c + 1) begin
            if (c < cols) begin
              ea = {32'b0, base} + (r * {32'b0, stride}) + (c * {32'b0, ew});
              last = ea + {32'b0, ew} - 64'd1;
              if (((ea >> 32) != 0) || ((last >> 32) != 0) ||
                  (ea < {32'h0, SRAM_LO}) || (last > {32'h0, SRAM_HI})) ok = 1'b0;
              if ((ew == 32'd32) && ((ea & 64'h1F) != 64'h0)) ok = 1'b0;
              if ((ew == 32'd8) && ((ea & 64'h7) != 64'h0)) ok = 1'b0;
            end
          end
        end
      end
      legacy_rect = ok;
    end
  endfunction
  logic [31:0] base, stride, rows, cols, ew;
  integer i, j, seed, ignored;
  task automatic check;
    if (rect_in_sram(base, stride, rows, cols, ew) !==
        legacy_rect(base, stride, rows, cols, ew))
      $fatal(1, "FAIL RECT base=%h stride=%h rows=%0d cols=%0d ew=%0d", base, stride, rows, cols, ew);
  endtask
  initial begin
    seed = 32'h4a1a9e00;
    ignored = $urandom(seed);
    // Valid tiles, alignment faults, empty shapes and the original loop cap.
    for (i = 0; i < 3000; i = i + 1) begin
      rows = $urandom_range(0, 70);
      cols = $urandom_range(0, 70);
      ew = (i % 3 == 0) ? 32 : ((i % 3 == 1) ? 8 : $urandom_range(0, 40));
      stride = $urandom_range(0, 4096);
      base = SRAM_LO + $urandom_range(0, 524287);
      if (i % 2 == 0) begin
        base = base & 32'hffffffe0;
        stride = stride & 32'hffffffe0;
      end
      check();
    end
    // Address overflow, zero width, and dimensions above the 64-element cap.
    for (i = 0; i < 1000; i = i + 1) begin
      base = $urandom;
      stride = $urandom;
      rows = $urandom;
      cols = $urandom;
      ew = (i % 2 == 0) ? 0 : $urandom;
      check();
    end
    rows = 1; cols = 1; stride = 32'hffffffff;
    for (j = 0; j < 4; j = j + 1) begin
      case (j)
        0: base = SRAM_LO - 1;
        1: base = SRAM_LO;
        2: base = SRAM_HI;
        3: base = SRAM_HI + 1;
      endcase
      for (i = 0; i <= 33; i = i + 1) begin ew = i; check(); end
    end
    rows = 0; cols = 32'hffffffff; ew = 32'hffffffff; check();
    rows = 32'hffffffff; cols = 0; check();
    $display("PASS RECT: endpoint validator matches original loops (4138 shapes)");
    $finish;
  end
endmodule
