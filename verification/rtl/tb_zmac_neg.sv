// SPDX-License-Identifier: AGPL-3.0-only
// Negative-operand ZMAC on rtl/mac/alapeno_mac.sv.
// ISA.md §9 ZMAC: "Z[zd] = Z[zd] + sx(src1) * sx(src2). The product is the
// exact 128-bit signed product. The sum is exact."
// Opcode 0x18 funct3 6. Non-field path: load a,b (signed-64 LE) and Z
// (signed-256 LE limbs), publish result to ptr_c (32-byte limb tuple).
// Stimulus: a=-5, b=7, Z0=11 -> product=-35, sum=-24.
// Expected limbs from gcc __int128 ref (see verification/rtl/logs/zmac_neg.log).
// Failures call $fatal. Icarus 12: $finish exits 0; $fatal exits nonzero.

`timescale 1ns/1ps

module tb_zmac_neg;
  import alapeno_pkg::*;

  logic         clk, rst, run, kill, field_mode;
  logic [31:0]  ptr_a, ptr_b, ptr_z, ptr_c;
  logic         b_valid, b_we, b_shadow, b_publish, b_discard;
  logic [31:0]  b_addr;
  logic [6:0]   b_size;
  logic [255:0] b_wdata, b_rdata, b_rdata_q;
  logic         complete, fail;

  logic [7:0] sram   [0:4095];
  logic [7:0] shadow [0:4095];
  logic       dirty  [0:4095];
  integer     bi, si;

  logic         cap_clr;
  logic         saw_complete, saw_fail, saw_publish, saw_discard;

  // Expected: -24 as signed-256 LE limbs (gcc /tmp/zmac_neg_ref.c).
  localparam logic [255:0] EXP_NEG24 =
      {64'hffffffffffffffff, 64'hffffffffffffffff,
       64'hffffffffffffffff, 64'hffffffffffffffe8};

  alapeno_mac dut (
    .clk(clk), .rst(rst), .run(run), .kill(kill), .field_mode(field_mode),
    .ptr_a(ptr_a), .ptr_b(ptr_b), .ptr_z(ptr_z), .ptr_c(ptr_c),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow),
    .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .complete(complete), .fail(fail)
  );

  assign b_rdata = b_rdata_q;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic [11:0] off(input logic [31:0] addr);
    off = addr[11:0];
  endfunction

  task automatic mem_clear;
    integer i;
    begin
      for (i = 0; i < 4096; i = i + 1) begin
        sram[i] = 8'h00;
        shadow[i] = 8'h00;
        dirty[i] = 1'b0;
      end
    end
  endtask

  task automatic sram_put8(input [31:0] addr, input [63:0] val);
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1)
        sram[off(addr) + i[11:0]] = val[(i * 8) +: 8];
    end
  endtask

  task automatic sram_put32(input [31:0] addr, input [255:0] val);
    integer i;
    begin
      for (i = 0; i < 32; i = i + 1)
        sram[off(addr) + i[11:0]] = val[(i * 8) +: 8];
    end
  endtask

  function automatic logic [255:0] sram_get32(input [31:0] addr);
    logic [255:0] v;
    integer i;
    begin
      v = '0;
      for (i = 0; i < 32; i = i + 1)
        v[(i * 8) +: 8] = sram[off(addr) + i[11:0]];
      sram_get32 = v;
    end
  endfunction

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  always_ff @(posedge clk) begin
    if (rst) begin
      b_rdata_q <= '0;
      for (si = 0; si < 4096; si = si + 1) dirty[si] <= 1'b0;
    end else begin
      if (b_valid && !b_we && !b_publish && !b_discard) begin
        b_rdata_q <= '0;
        for (bi = 0; bi < 32; bi = bi + 1) begin
          if (bi < b_size)
            b_rdata_q[(bi * 8) +: 8] <= sram[off(b_addr) + bi[11:0]];
        end
      end
      if (b_valid && b_we && b_shadow && !b_discard) begin
        for (bi = 0; bi < 32; bi = bi + 1) begin
          if (bi < b_size) begin
            shadow[off(b_addr) + bi[11:0]] <= b_wdata[(bi * 8) +: 8];
            dirty[off(b_addr) + bi[11:0]] <= 1'b1;
          end
        end
      end
      if (b_discard) begin
        for (si = 0; si < 4096; si = si + 1) dirty[si] <= 1'b0;
      end else if (b_publish) begin
        for (si = 0; si < 4096; si = si + 1) begin
          if (dirty[si]) begin
            sram[si] <= shadow[si];
            dirty[si] <= 1'b0;
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst || cap_clr) begin
      saw_complete <= 1'b0;
      saw_fail <= 1'b0;
      saw_publish <= 1'b0;
      saw_discard <= 1'b0;
    end else begin
      if (complete) saw_complete <= 1'b1;
      if (fail) saw_fail <= 1'b1;
      if (b_publish) saw_publish <= 1'b1;
      if (b_discard) saw_discard <= 1'b1;
    end
  end

  integer cycles;
  logic done_pulse, fail_pulse;
  logic [255:0] got;

  task automatic wait_done_or_fail(input integer maxc);
    begin
      cycles = 0;
      done_pulse = 1'b0;
      fail_pulse = 1'b0;
      while (cycles < maxc && !done_pulse && !fail_pulse) begin
        tick;
        cycles = cycles + 1;
        if (complete) done_pulse = 1'b1;
        if (fail) fail_pulse = 1'b1;
      end
      if (done_pulse || fail_pulse) tick;
      tick;
    end
  endtask

  initial begin
    run = 1'b0;
    kill = 1'b0;
    field_mode = 1'b0;
    ptr_a = 32'h0; ptr_b = 32'h0; ptr_z = 32'h0; ptr_c = 32'h0;
    cap_clr = 1'b0;
    mem_clear;

    rst = 1'b1;
    repeat (4) tick;
    rst = 1'b0;
    tick;

    // Addresses: a,b 8-aligned; z,c 32-aligned; inside SRAM window.
    ptr_a = 32'h1000_0000;
    ptr_b = 32'h1000_0008;
    ptr_z = 32'h1000_0020;
    ptr_c = 32'h1000_0040;

    // a = -5 (signed 64 LE), b = 7, Z = 11 (signed 256, low limb only).
    sram_put8(ptr_a, 64'hfffffffffffffffb); // -5
    sram_put8(ptr_b, 64'h0000000000000007); // 7
    sram_put32(ptr_z, {192'h0, 64'd11});
    // Seed destination so a false pass cannot look like leftover zeros.
    begin : seed_c
      integer ci;
      for (ci = 0; ci < 32; ci = ci + 1)
        sram[off(ptr_c) + ci[11:0]] = 8'h5A;
    end

    $display("stimulus: a=-5 b=7 Z=11; expect sum=-24 (ISA ZMAC exact signed product+sum)");

    cap_clr = 1'b1; tick; cap_clr = 1'b0; tick;
    run = 1'b1; tick; run = 1'b0;
    wait_done_or_fail(500);

    if (!done_pulse || fail_pulse || !saw_publish || saw_fail || saw_discard) begin
      $display("FAIL ZMAC status: done=%b fail=%b publish=%b saw_fail=%b saw_discard=%b cycles=%0d",
               done_pulse, fail_pulse, saw_publish, saw_fail, saw_discard, cycles);
      $fatal(1, "FAIL");
    end

    got = sram_get32(ptr_c);
    $display("C expected=%h actual=%h", EXP_NEG24, got);
    if (got !== EXP_NEG24) begin
      $display("FAIL ZMAC limb mismatch: expected -24 as signed-256 LE");
      $fatal(1, "FAIL");
    end

    $display("PASS ZMAC NEG: a=-5 b=7 Z=11 -> published accumulator -24 (exact signed 256 limbs)");
    $finish(0);
  end

  initial begin
    #200000;
    $display("FAIL timeout");
    $fatal(1, "FAIL");
  end
endmodule
