// SPDX-License-Identifier: AGPL-3.0-only
// MEMORY.md §4 on alapeno_mem ports a_* and b_*, same cycle.
// Conflict sticky bit is STATUS bit 3 in both alapeno_dma and alapeno_accel
// (alapeno_top wires mem.conflict to both conflict_stb inputs). Those STATUS
// registers are not ports of alapeno_mem, so both engines are instantiated
// and only their conflict_stb/MMIO are used. Their b_* masters are not
// connected to SRAM; the contest is driven on mem's a_* and b_*.
// Failures use $fatal.

`timescale 1ns/1ps

module tb_porta_contest;
  import alapeno_pkg::*;

  logic clk, rst;
  logic a_valid, a_we, b_valid, b_we, b_shadow, b_publish, b_discard, conflict;
  logic [31:0] a_addr, b_addr;
  logic [6:0] a_size, b_size;
  logic [255:0] a_wdata, b_wdata, a_rdata, b_rdata;

  logic dma_rd, dma_wr, acc_rd, acc_wr;
  logic [11:0] dma_addr, acc_addr;
  logic [31:0] dma_wdata, dma_rdata, acc_wdata, acc_rdata;
  logic dma_busy_o, acc_busy_o;

  alapeno_mem u_mem (
    .clk(clk), .rst(rst),
    .rom_load_we(1'b0), .rom_load_addr(16'h0), .rom_load_wdata(8'h0),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size),
    .a_wdata(a_wdata), .a_rdata(a_rdata),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow), .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .conflict(conflict)
  );

  alapeno_dma u_dma (
    .clk(clk), .rst(rst),
    .mmio_rd(dma_rd), .mmio_wr(dma_wr), .mmio_addr(dma_addr),
    .mmio_wdata(dma_wdata), .mmio_rdata(dma_rdata),
    .b_valid(), .b_we(), .b_addr(), .b_size(), .b_wdata(), .b_rdata(256'h0),
    .accel_busy(1'b0), .conflict_stb(conflict),
    .g0_v(1'b0), .g0_base(32'h0), .g0_stride(32'h0), .g0_rows(32'h0), .g0_cols(32'h0), .g0_ew(32'h0),
    .g1_v(1'b0), .g1_base(32'h0), .g1_stride(32'h0), .g1_rows(32'h0), .g1_cols(32'h0), .g1_ew(32'h0),
    .g2_v(1'b0), .g2_base(32'h0), .g2_stride(32'h0), .g2_rows(32'h0), .g2_cols(32'h0), .g2_ew(32'h0),
    .busy(dma_busy_o)
  );

  logic g0_v, g1_v, g2_v;
  logic [31:0] g0b, g0s, g0r, g0c, g0e, g1b, g1s, g1r, g1c, g1e, g2b, g2s, g2r, g2c, g2e;
  logic acc_bv, acc_bw, acc_bs, acc_bp, acc_bd;
  logic [31:0] acc_ba;
  logic [6:0] acc_bz;
  logic [255:0] acc_bwdata;

  alapeno_accel u_accel (
    .clk(clk), .rst(rst),
    .mmio_rd(acc_rd), .mmio_wr(acc_wr), .mmio_addr(acc_addr),
    .mmio_wdata(acc_wdata), .mmio_rdata(acc_rdata),
    .dma_busy(1'b0), .conflict_stb(conflict),
    .b_valid(acc_bv), .b_we(acc_bw), .b_shadow(acc_bs), .b_publish(acc_bp), .b_discard(acc_bd),
    .b_addr(acc_ba), .b_size(acc_bz), .b_wdata(acc_bwdata), .b_rdata(256'h0),
    .busy(acc_busy_o),
    .g0_v(g0_v), .g0_base(g0b), .g0_stride(g0s), .g0_rows(g0r), .g0_cols(g0c), .g0_ew(g0e),
    .g1_v(g1_v), .g1_base(g1b), .g1_stride(g1s), .g1_rows(g1r), .g1_cols(g1c), .g1_ew(g1e),
    .g2_v(g2_v), .g2_base(g2b), .g2_stride(g2s), .g2_rows(g2r), .g2_cols(g2c), .g2_ew(g2e)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic quiet_b;
    begin
      a_valid = 1'b0;
      a_we = 1'b0;
      b_valid = 1'b0;
      b_we = 1'b0;
      b_shadow = 1'b0;
      b_publish = 1'b0;
      b_discard = 1'b0;
    end
  endtask

  initial begin
    quiet_b;
    a_addr = 32'h0;
    b_addr = 32'h0;
    a_size = 7'd0;
    b_size = 7'd0;
    a_wdata = '0;
    b_wdata = '0;
    dma_rd = 1'b0;
    dma_wr = 1'b0;
    dma_addr = 12'h0;
    dma_wdata = 32'h0;
    acc_rd = 1'b0;
    acc_wr = 1'b0;
    acc_addr = 12'h0;
    acc_wdata = 32'h0;
    rst = 1'b1;
    repeat (2) tick;
    rst = 1'b0;
    tick;

    // Split: different bytes, both must store, conflict must stay clear.
    a_valid = 1'b1;
    a_we = 1'b1;
    a_addr = 32'h1000_0000;
    a_size = 7'd1;
    a_wdata = 256'h11;
    b_valid = 1'b1;
    b_we = 1'b1;
    b_shadow = 1'b0;
    b_publish = 1'b0;
    b_discard = 1'b0;
    b_addr = 32'h1000_0001;
    b_size = 7'd1;
    b_wdata = 256'h22;
    tick;
    quiet_b;
    $display("split stored b0=%h b1=%h mem_conflict=%b",
             u_mem.sram[0], u_mem.sram[1], conflict);
    if (u_mem.sram[0] !== 8'h11 || u_mem.sram[1] !== 8'h22) begin
      $display("FAIL split store");
      $fatal(1, "FAIL");
    end
    // conflict output is registered; give the sticky STATUS a cycle to sample it.
    tick;
    if (conflict !== 1'b0 || u_dma.conflict_b !== 1'b0 || u_accel.conflict_b !== 1'b0) begin
      $display("FAIL split raised conflict mem=%b dma=%b accel=%b",
               conflict, u_dma.conflict_b, u_accel.conflict_b);
      $fatal(1, "FAIL");
    end

    // Same byte: A writes 0xAA, B writes 0xBB.
    a_valid = 1'b1;
    a_we = 1'b1;
    a_addr = 32'h1000_0000;
    a_size = 7'd1;
    a_wdata = 256'hAA;
    b_valid = 1'b1;
    b_we = 1'b1;
    b_shadow = 1'b0;
    b_publish = 1'b0;
    b_discard = 1'b0;
    b_addr = 32'h1000_0000;
    b_size = 7'd1;
    b_wdata = 256'hBB;
    @(posedge clk);
    #1;
    $display("contest stored=%h mem_conflict=%b a_next=%h b_next=%h a_rdata=%h b_rdata=%h",
             u_mem.sram[0], conflict, u_mem.a_next[7:0], u_mem.b_next[7:0],
             a_rdata[7:0], b_rdata[7:0]);
    if (u_mem.sram[0] !== 8'hAA) begin
      $display("FAIL stored byte %h expected aa", u_mem.sram[0]);
      $fatal(1, "FAIL");
    end
    // Same-cycle read mux. rdata itself does not latch: both ports have we=1,
    // and alapeno_mem updates a_rdata/b_rdata only when that port is not writing.
    if (u_mem.a_next[7:0] !== 8'hAA || u_mem.b_next[7:0] !== 8'hAA) begin
      $display("FAIL same-cycle read mux a_next=%h b_next=%h expected aa",
               u_mem.a_next[7:0], u_mem.b_next[7:0]);
      $fatal(1, "FAIL");
    end
    quiet_b;

    // mem.conflict rises on the contest edge; STATUS samples conflict_stb one
    // cycle later (separate always_ff). Then MMIO reads that sticky bit.
    tick;
    if (u_dma.conflict_b !== 1'b1 || u_accel.conflict_b !== 1'b1) begin
      $display("FAIL STATUS conflict sticky dma=%b accel=%b mem_conflict=%b",
               u_dma.conflict_b, u_accel.conflict_b, conflict);
      $fatal(1, "FAIL");
    end
    dma_rd = 1'b1;
    dma_addr = 12'h010;
    acc_rd = 1'b1;
    acc_addr = 12'h004;
    tick;
    dma_rd = 1'b0;
    acc_rd = 1'b0;
    $display("DMA STATUS=%h ACCEL STATUS=%h", dma_rdata, acc_rdata);
    if (dma_rdata[3] !== 1'b1 || acc_rdata[3] !== 1'b1) begin
      $display("FAIL STATUS bit3 dma=%h accel=%h", dma_rdata, acc_rdata);
      $fatal(1, "FAIL");
    end
    $display("PASS PORT A: stored 0xAA, same-cycle read mux 0xAA, split 0x11/0x22 both stored, STATUS bit3 set in DMA and accel");
    $finish(0);
  end

  initial begin
    #1000000;
    $display("FAIL timeout watchdog");
    $fatal(1, "FAIL");
  end
endmodule
