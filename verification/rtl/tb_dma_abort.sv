// SPDX-License-Identifier: AGPL-3.0-only
// DMA abort keeps the committed prefix. Beats are 8 bytes, shadow off
// (alapeno_dma has no b_shadow port; mem b_shadow is tied 0). CTRL bit 1
// (mmio 12'h00C, wdata bit 1) while busy. Bound to alapeno_dma and alapeno_mem.
// Failures use $fatal.

`timescale 1ns/1ps

module tb_dma_abort;
  import alapeno_pkg::*;

  logic clk, rst;
  logic mmio_rd, mmio_wr;
  logic [11:0] mmio_addr;
  logic [31:0] mmio_wdata, mmio_rdata;
  logic b_valid, b_we;
  logic [31:0] b_addr;
  logic [6:0] b_size;
  logic [255:0] b_wdata, b_rdata;
  logic busy;
  logic a_valid, a_we;
  logic [31:0] a_addr;
  logic [6:0] a_size;
  logic [255:0] a_wdata, a_rdata;
  logic conflict;

  localparam logic [31:0] SRC = 32'h1000_0000;
  localparam logic [31:0] DST = 32'h1000_0100;
  localparam integer LEN = 32;

  alapeno_dma u_dma (
    .clk(clk), .rst(rst),
    .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
    .b_valid(b_valid), .b_we(b_we), .b_addr(b_addr), .b_size(b_size),
    .b_wdata(b_wdata), .b_rdata(b_rdata),
    .accel_busy(1'b0), .conflict_stb(conflict),
    .g0_v(1'b0), .g0_base(32'h0), .g0_stride(32'h0), .g0_rows(32'h0), .g0_cols(32'h0), .g0_ew(32'h0),
    .g1_v(1'b0), .g1_base(32'h0), .g1_stride(32'h0), .g1_rows(32'h0), .g1_cols(32'h0), .g1_ew(32'h0),
    .g2_v(1'b0), .g2_base(32'h0), .g2_stride(32'h0), .g2_rows(32'h0), .g2_cols(32'h0), .g2_ew(32'h0),
    .busy(busy)
  );

  alapeno_mem u_mem (
    .clk(clk), .rst(rst),
    .rom_load_we(1'b0), .rom_load_addr(16'h0), .rom_load_wdata(8'h0),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size),
    .a_wdata(a_wdata), .a_rdata(a_rdata),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(1'b0), .b_publish(1'b0), .b_discard(1'b0),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .conflict(conflict)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  integer i, committed, guard;
  logic [7:0] srcb, seedb, gotb;
  logic [255:0] beat;
  logic prefix_ok;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic awrite(input logic [31:0] addr, input logic [255:0] data);
    begin
      a_valid = 1'b1;
      a_we = 1'b1;
      a_addr = addr;
      a_size = 7'd8;
      a_wdata = data;
      tick;
      a_valid = 1'b0;
      a_we = 1'b0;
    end
  endtask

  function automatic logic [7:0] src_byte(input integer n);
    src_byte = 8'hA0 + n[7:0];
  endfunction

  function automatic logic [7:0] seed_byte(input integer n);
    seed_byte = 8'h50 + n[7:0];
  endfunction

  initial begin
    a_valid = 1'b0;
    a_we = 1'b0;
    a_addr = 32'h0;
    a_size = 7'd0;
    a_wdata = '0;
    mmio_rd = 1'b0;
    mmio_wr = 1'b0;
    mmio_addr = 12'h0;
    mmio_wdata = 32'h0;
    rst = 1'b1;
    repeat (2) tick;
    rst = 1'b0;
    tick;

    for (i = 0; i < LEN; i = i + 8) begin
      beat = '0;
      beat[7:0]   = src_byte(i);
      beat[15:8]  = src_byte(i + 1);
      beat[23:16] = src_byte(i + 2);
      beat[31:24] = src_byte(i + 3);
      beat[39:32] = src_byte(i + 4);
      beat[47:40] = src_byte(i + 5);
      beat[55:48] = src_byte(i + 6);
      beat[63:56] = src_byte(i + 7);
      awrite(SRC + i, beat);
      beat[7:0]   = seed_byte(i);
      beat[15:8]  = seed_byte(i + 1);
      beat[23:16] = seed_byte(i + 2);
      beat[31:24] = seed_byte(i + 3);
      beat[39:32] = seed_byte(i + 4);
      beat[47:40] = seed_byte(i + 5);
      beat[55:48] = seed_byte(i + 6);
      beat[63:56] = seed_byte(i + 7);
      awrite(DST + i, beat);
    end

    mmio_wr = 1'b1;
    mmio_addr = 12'h000;
    mmio_wdata = SRC;
    tick;
    mmio_addr = 12'h004;
    mmio_wdata = DST;
    tick;
    mmio_addr = 12'h008;
    mmio_wdata = LEN;
    tick;
    mmio_addr = 12'h00C;
    mmio_wdata = 32'h1;
    tick;
    mmio_wr = 1'b0;

    if (busy !== 1'b1) begin
      $display("FAIL dma did not start fault=%b", u_dma.fault_b);
      $fatal(1, "FAIL");
    end

    committed = 0;
    guard = 0;
    while (committed < 8 && guard < 100) begin
      tick;
      guard = guard + 1;
      committed = 0;
      prefix_ok = 1'b1;
      for (i = 0; i < LEN; i = i + 1) begin
        gotb = u_mem.sram[32'h100 + i];
        if (prefix_ok && gotb === src_byte(i)) committed = committed + 1;
        else prefix_ok = 1'b0;
      end
    end
    $display("seen committed_prefix=%0d bytes busy=%b state=%h off=%h",
             committed, busy, u_dma.state, u_dma.copy_off);
    if (committed < 8 || committed >= LEN) begin
      $display("FAIL wanted a proper prefix, committed=%0d len=%0d", committed, LEN);
      $fatal(1, "FAIL");
    end
    if (busy !== 1'b1) begin
      $display("FAIL dma idle before abort");
      $fatal(1, "FAIL");
    end

    // Abort before the next beat commits. CTRL bit 1 at 12'h00C.
    mmio_wr = 1'b1;
    mmio_addr = 12'h00C;
    mmio_wdata = 32'h2;
    tick;
    mmio_wr = 1'b0;

    $display("after abort busy=%b done=%b fault=%b", busy, u_dma.done_b, u_dma.fault_b);
    if (busy !== 1'b0 || u_dma.done_b !== 1'b0) begin
      $display("FAIL abort status busy=%b done=%b", busy, u_dma.done_b);
      $fatal(1, "FAIL");
    end

    for (i = 0; i < LEN; i = i + 1) begin
      gotb = u_mem.sram[32'h100 + i];
      srcb = src_byte(i);
      seedb = seed_byte(i);
      if (i < committed) begin
        if (gotb !== srcb) begin
          $display("FAIL prefix rolled back or corrupted at %0d got %h expected %h", i, gotb, srcb);
          $fatal(1, "FAIL");
        end
      end else if (gotb !== seedb) begin
        $display("FAIL byte %0d past prefix got %h expected seed %h", i, gotb, seedb);
        $fatal(1, "FAIL");
      end
    end
    $display("PASS DMA ABORT: committed prefix %0d bytes kept, remaining %0d bytes unchanged, busy=0 done=0",
             committed, LEN - committed);
    $finish(0);
  end

  initial begin
    #2000000;
    $display("FAIL timeout watchdog");
    $fatal(1, "FAIL");
  end
endmodule
