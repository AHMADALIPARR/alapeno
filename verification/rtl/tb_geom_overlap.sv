// SPDX-License-Identifier: AGPL-3.0-only
// Differential check against the original all-pairs row overlap validator.
module tb_geom_overlap;
  import alapeno_pkg::*;
  function automatic logic legacy_overlap(
    input logic [31:0] a_base, input logic [31:0] a_stride,
    input logic [31:0] a_rows, input logic [31:0] a_cols, input logic [31:0] a_ew,
    input logic [31:0] b_base, input logic [31:0] b_stride,
    input logic [31:0] b_rows, input logic [31:0] b_cols, input logic [31:0] b_ew
  );
    integer ra, rb;
    logic [63:0] ab, al, bb, bl;
    logic hit;
    begin
      hit = 1'b0;
      if ((a_rows != 0) && (a_cols != 0) && (b_rows != 0) && (b_cols != 0)) begin
        for (ra = 0; ra < 64; ra = ra + 1) begin
          if (ra < a_rows) begin
            ab = {32'b0, a_base} + (ra * {32'b0, a_stride});
            al = {32'b0, a_cols} * {32'b0, a_ew};
            for (rb = 0; rb < 64; rb = rb + 1) begin
              if (rb < b_rows) begin
                bb = {32'b0, b_base} + (rb * {32'b0, b_stride});
                bl = {32'b0, b_cols} * {32'b0, b_ew};
                if (((ab >> 32) == 0) && ((bb >> 32) == 0) &&
                    ((ab + al) <= 64'h0000_0001_0000_0000) &&
                    ((bb + bl) <= 64'h0000_0001_0000_0000)) begin
                  if (ranges_overlap(ab, al, bb, bl)) hit = 1'b1;
                end else hit = 1'b1;
              end
            end
          end
        end
      end
      legacy_overlap = hit;
    end
  endfunction
  logic [31:0] a, sa, ra, ca, wa, b, sb, rb, cb, wb;
  integer i, seed, ignored;
  task automatic check;
    if (geom_pair_overlap(a, sa, ra, ca, wa, b, sb, rb, cb, wb) !==
        legacy_overlap(a, sa, ra, ca, wa, b, sb, rb, cb, wb))
      $fatal(1, "FAIL GEOM a=%h sa=%0d ra=%0d ca=%0d wa=%0d b=%h sb=%0d rb=%0d cb=%0d wb=%0d",
             a, sa, ra, ca, wa, b, sb, rb, cb, wb);
  endtask
  initial begin
    seed = 32'h711e0100; ignored = $urandom(seed);
    // Dense, sparse, overlapping and disjoint row intervals.
    for (i = 0; i < 2000; i = i + 1) begin
      a = SRAM_LO + $urandom_range(0, 4096);
      b = SRAM_LO + $urandom_range(0, 4096);
      ra = $urandom_range(0, 70); rb = $urandom_range(0, 70);
      ca = $urandom_range(0, 64); cb = $urandom_range(0, 64);
      wa = (i % 2 == 0) ? 8 : 32; wb = (i % 3 == 0) ? 8 : 32;
      sa = $urandom_range(0, 4096); sb = $urandom_range(0, 4096);
      check();
    end
    // Arbitrary 32-bit inputs, overflow, empty rows, zero width and stride.
    for (i = 0; i < 500; i = i + 1) begin
      a = $urandom; b = $urandom; sa = $urandom; sb = $urandom;
      ra = $urandom; rb = $urandom; ca = $urandom; cb = $urandom;
      wa = $urandom; wb = $urandom;
      if (i % 5 == 0) wa = 0;
      if (i % 5 == 1) ra = 0;
      if (i % 5 == 2) cb = 0;
      if (i % 5 == 3) begin sa = 0; sb = 0; end
      check();
    end
    // Bounding boxes overlap, but alternating sparse rows do not.
    a = SRAM_LO; b = SRAM_LO + 8; sa = 16; sb = 16;
    ra = 64; rb = 64; ca = 1; cb = 1; wa = 8; wb = 8; check();
    if (geom_pair_overlap(a, sa, ra, ca, wa, b, sb, rb, cb, wb))
      $fatal(1, "FAIL GEOM sparse non-alias");
    b = SRAM_LO + 7; check();
    if (!geom_pair_overlap(a, sa, ra, ca, wa, b, sb, rb, cb, wb))
      $fatal(1, "FAIL GEOM one-byte alias");
    // A legal 2^32-byte length has the legacy truncated zero length.
    a = 0; b = 0; ra = 1; rb = 1; ca = 65536; cb = 1;
    wa = 65536; wb = 8; sa = 0; sb = 0; check();
    $display("PASS GEOM: sorted-row validator matches original all-pairs loops (2503 shapes)");
    $finish;
  end
endmodule
