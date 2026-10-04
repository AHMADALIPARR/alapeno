// SPDX-License-Identifier: AGPL-3.0-only
// Accelerator abort is all-or-nothing. A legal 1x1 non-field MATMUL (2*3=6,
// inside signed 256; not an overflow) shadow-writes C, then CTRL bit 1 aborts
// on the publish cycle before b_publish is clocked. Destination bytes must
// stay at the seed. Bound to alapeno_accel (CTRL abort / b_discard) and
// alapeno_mem (shadow stays invisible). Failures use $fatal.

`timescale 1ns/1ps

module tb_accel_abort;
  import alapeno_pkg::*;

  logic clk, rst;
  logic dma_busy, conflict_stb;
  logic mmio_rd, mmio_wr;
  logic [11:0] mmio_addr;
  logic [31:0] mmio_wdata, mmio_rdata;
  logic b_valid, b_we, b_shadow, b_publish, b_discard;
  logic [31:0] b_addr;
  logic [6:0] b_size;
  logic [255:0] b_wdata, b_rdata;
  logic busy;
  logic g0_v, g1_v, g2_v;
  logic [31:0] g0_base, g0_stride, g0_rows, g0_cols, g0_ew;
  logic [31:0] g1_base, g1_stride, g1_rows, g1_cols, g1_ew;
  logic [31:0] g2_base, g2_stride, g2_rows, g2_cols, g2_ew;

  logic a_valid, a_we;
  logic [31:0] a_addr;
  logic [6:0] a_size;
  logic [255:0] a_wdata, a_rdata;
  logic conflict;

  alapeno_accel u_accel (
    .clk(clk), .rst(rst),
    .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_addr(mmio_addr),
    .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
    .dma_busy(dma_busy), .conflict_stb(conflict_stb),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow), .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .busy(busy),
    .g0_v(g0_v), .g0_base(g0_base), .g0_stride(g0_stride), .g0_rows(g0_rows), .g0_cols(g0_cols), .g0_ew(g0_ew),
    .g1_v(g1_v), .g1_base(g1_base), .g1_stride(g1_stride), .g1_rows(g1_rows), .g1_cols(g1_cols), .g1_ew(g1_ew),
    .g2_v(g2_v), .g2_base(g2_base), .g2_stride(g2_stride), .g2_rows(g2_rows), .g2_cols(g2_cols), .g2_ew(g2_ew)
  );

  alapeno_mem u_mem (
    .clk(clk), .rst(rst),
    .rom_load_we(1'b0), .rom_load_addr(16'h0), .rom_load_wdata(8'h0),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size),
    .a_wdata(a_wdata), .a_rdata(a_rdata),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow), .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .conflict(conflict)
  );

  assign dma_busy = 1'b0;
  assign conflict_stb = conflict;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  localparam logic [31:0] PA = 32'h1000_0000;
  localparam logic [31:0] PB = 32'h1000_0008;
  localparam logic [31:0] PC = 32'h1000_0020;
  localparam integer CBYTES = 32;

  integer i, dirty_n, guard;
  logic [7:0] gotb;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic awrite(input logic [31:0] addr, input logic [6:0] sz, input logic [255:0] data);
    begin
      a_valid = 1'b1;
      a_we = 1'b1;
      a_addr = addr;
      a_size = sz;
      a_wdata = data;
      tick;
      a_valid = 1'b0;
      a_we = 1'b0;
    end
  endtask

  task automatic mmio(input logic [11:0] addr, input logic [31:0] data);
    begin
      mmio_wr = 1'b1;
      mmio_rd = 1'b0;
      mmio_addr = addr;
      mmio_wdata = data;
      tick;
      mmio_wr = 1'b0;
    end
  endtask

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

    awrite(PA, 7'd8, 256'h2);
    awrite(PB, 7'd8, 256'h3);
    awrite(PC, 7'd32, {32{8'h5A}});

    mmio(12'h008, 32'd1);
    mmio(12'h00C, 32'd1);
    mmio(12'h010, 32'd1);
    mmio(12'h014, 32'd1);
    mmio(12'h018, PA);
    mmio(12'h01C, PB);
    mmio(12'h020, PC);
    mmio(12'h024, 32'd8);
    mmio(12'h028, 32'd8);
    mmio(12'h02C, 32'd32);
    mmio(12'h034, 32'd0);
    mmio(12'h000, 32'd1);

    if (busy !== 1'b1) begin
      $display("FAIL accel did not go busy (status rd will follow)");
      $fatal(1, "FAIL");
    end
    $display("accel busy after start");

    guard = 0;
    begin : wait_pub
      forever begin
        @(negedge clk);
        guard = guard + 1;
        if (guard > 5000) begin
          $display("FAIL no publish cycle (shadow abort window missed)");
          $fatal(1, "FAIL");
        end
        if (b_publish === 1'b1) disable wait_pub;
      end
    end

    dirty_n = 0;
    for (i = 0; i < CBYTES; i = i + 1) begin
      gotb = u_mem.sram[32'h20 + i];
      if (gotb !== 8'h5A) begin
        $display("FAIL dest byte %0d changed before publish/abort got %h", i, gotb);
        $fatal(1, "FAIL");
      end
      if (u_mem.dirty[32'h20 + i] === 1'b1) dirty_n = dirty_n + 1;
    end
    $display("pre-abort shadow dirty_bytes=%0d sram_still_seed=1 b_publish=%b b_discard=%b",
             dirty_n, b_publish, b_discard);
    if (dirty_n != CBYTES) begin
      $display("FAIL expected 32 shadow dirty bytes before abort, got %0d", dirty_n);
      $fatal(1, "FAIL");
    end
    if (u_mem.shadow[32'h20] !== 8'h06) begin
      $display("FAIL shadow low byte %h (expected product 6); abort would not prove a real shadow",
               u_mem.shadow[32'h20]);
      $fatal(1, "FAIL");
    end

    // CTRL bit 1 while busy, still before the publish edge.
    mmio_wr = 1'b1;
    mmio_rd = 1'b0;
    mmio_addr = 12'h000;
    mmio_wdata = 32'h2;
    @(posedge clk);
    #1;
    mmio_wr = 1'b0;

    $display("post-abort busy=%b done=%b fault=%b discard_seen_now=%b publish_now=%b",
             busy, u_accel.done_b, u_accel.fault_b, b_discard, b_publish);
    if (busy !== 1'b0 || u_accel.done_b !== 1'b0) begin
      $display("FAIL abort status busy=%b done=%b", busy, u_accel.done_b);
      $fatal(1, "FAIL");
    end
    if (u_accel.fault_b !== 1'b0) begin
      $display("FAIL abort raised fault");
      $fatal(1, "FAIL");
    end

    for (i = 0; i < CBYTES; i = i + 1) begin
      gotb = u_mem.sram[32'h20 + i];
      if (gotb !== 8'h5A) begin
        $display("FAIL dest byte %0d after abort got %h expected 5a", i, gotb);
        $fatal(1, "FAIL");
      end
      if (u_mem.dirty[32'h20 + i] !== 1'b0) begin
        $display("FAIL dirty still set at dest byte %0d after discard", i);
        $fatal(1, "FAIL");
      end
    end
    $display("PASS ACCEL ABORT: all %0d destination bytes unchanged at 0x10000020 (seed 5a); shadow product was not published",
             CBYTES);
    $finish(0);
  end

  initial begin
    #2000000;
    $display("FAIL timeout watchdog");
    $fatal(1, "FAIL");
  end
endmodule
