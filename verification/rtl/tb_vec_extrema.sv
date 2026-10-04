// SPDX-License-Identifier: AGPL-3.0-only
// Signed-extrema RED.MIN on rtl/vector/alapeno_vector.sv.
// ACCELERATOR.md §7 RED.MIN non-field: "mathematical minimum; 8-byte signed
// store". RTL (alapeno_vector.sv): non-field MIN uses
//   cur64 <= ($signed(elem) < $signed(cur64)) ? elem : cur64
// and publishes once via V_SH then V_PUB (b_publish+complete).
// Stimulus VL=4: INT64_MAX, -1, INT64_MIN, 42. Expected destination = INT64_MIN.
// Failures call $fatal. Icarus 12: $finish exits 0; $fatal exits nonzero.

`timescale 1ns/1ps

module tb_vec_extrema;
  import alapeno_pkg::*;

  logic         clk, rst, run, kill, field_mode;
  logic [31:0]  op, vl, ptr_a, ptr_b, ptr_c;
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

  localparam logic [63:0] V_INT64_MAX = 64'h7fffffffffffffff;
  localparam logic [63:0] V_NEG1      = 64'hffffffffffffffff;
  localparam logic [63:0] V_INT64_MIN = 64'h8000000000000000;
  localparam logic [63:0] V_42        = 64'h000000000000002a;

  alapeno_vector dut (
    .clk(clk), .rst(rst), .run(run), .kill(kill), .field_mode(field_mode),
    .op(op), .vl(vl), .ptr_a(ptr_a), .ptr_b(ptr_b), .ptr_c(ptr_c),
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

  function automatic logic [63:0] sram_get8(input [31:0] addr);
    logic [63:0] v;
    integer i;
    begin
      v = '0;
      for (i = 0; i < 8; i = i + 1)
        v[(i * 8) +: 8] = sram[off(addr) + i[11:0]];
      sram_get8 = v;
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
  logic [63:0] got;

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
    op = 32'h0;
    vl = 32'h0;
    ptr_a = 32'h0; ptr_b = 32'h0; ptr_c = 32'h0;
    cap_clr = 1'b0;
    mem_clear;

    rst = 1'b1;
    repeat (4) tick;
    rst = 1'b0;
    tick;

    ptr_a = 32'h1000_0000;
    ptr_b = 32'h1000_0100; // unused by RED.MIN
    ptr_c = 32'h1000_0200;

    // Vector: INT64_MAX, -1, INT64_MIN, 42. Mathematical min = INT64_MIN.
    sram_put8(ptr_a + 32'd0,  V_INT64_MAX);
    sram_put8(ptr_a + 32'd8,  V_NEG1);
    sram_put8(ptr_a + 32'd16, V_INT64_MIN);
    sram_put8(ptr_a + 32'd24, V_42);

    begin : seed_c
      integer ci;
      for (ci = 0; ci < 8; ci = ci + 1)
        sram[off(ptr_c) + ci[11:0]] = 8'h5A;
    end

    op = AOP_MIN;
    field_mode = 1'b0;
    vl = 32'd4;

    $display("stimulus RED.MIN VL=4: [INT64_MAX,-1,INT64_MIN,42]; expect INT64_MIN");

    cap_clr = 1'b1; tick; cap_clr = 1'b0; tick;
    run = 1'b1; tick; run = 1'b0;
    wait_done_or_fail(2000);

    if (!done_pulse || fail_pulse || !saw_publish || saw_fail || saw_discard) begin
      $display("FAIL RED.MIN status: done=%b fail=%b publish=%b saw_fail=%b saw_discard=%b cycles=%0d",
               done_pulse, fail_pulse, saw_publish, saw_fail, saw_discard, cycles);
      $fatal(1, "FAIL");
    end

    got = sram_get8(ptr_c);
    $display("C expected=%h actual=%h", V_INT64_MIN, got);
    if (got !== V_INT64_MIN) begin
      $display("FAIL RED.MIN value mismatch: expected INT64_MIN");
      $fatal(1, "FAIL");
    end

    $display("PASS VEC EXTREMA: RED.MIN of [INT64_MAX,-1,INT64_MIN,42] published INT64_MIN");
    $finish(0);
  end

  initial begin
    #200000;
    $display("FAIL timeout");
    $fatal(1, "FAIL");
  end
endmodule
