// SPDX-License-Identifier: AGPL-3.0-only
// Core on port A. Accelerator owns port B while busy; otherwise DMA may.

module alapeno_top
  import alapeno_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  logic        rom_load_we,
  input  logic [15:0] rom_load_addr,
  input  logic [7:0]  rom_load_wdata,
  output logic [31:0] pc_q,
  output logic [31:0] tcause_q,
  output logic [31:0] tpc_q,
  output logic        halted
);

  logic         a_valid, a_we, b_valid, b_we, b_shadow, b_publish, b_discard;
  logic [31:0]  a_addr, b_addr;
  logic [6:0]   a_size, b_size;
  logic [255:0] a_wdata, b_wdata, a_rdata, b_rdata;
  logic         conflict;
  logic         acc_rd, acc_wr, dma_rd, dma_wr;
  logic [11:0]  acc_addr, dma_addr;
  logic [31:0]  acc_wdata, acc_rdata, dma_wdata, dma_rdata;
  logic         accel_busy, dma_busy;
  logic         ab_valid, ab_we, ab_shadow, ab_publish, ab_discard;
  logic [31:0]  ab_addr;
  logic [6:0]   ab_size;
  logic [255:0] ab_wdata;
  logic         db_valid, db_we;
  logic [31:0]  db_addr;
  logic [6:0]   db_size;
  logic [255:0] db_wdata;
  logic         g0_v, g1_v, g2_v;
  logic [31:0]  g0_base, g0_stride, g0_rows, g0_cols, g0_ew;
  logic [31:0]  g1_base, g1_stride, g1_rows, g1_cols, g1_ew;
  logic [31:0]  g2_base, g2_stride, g2_rows, g2_cols, g2_ew;

  alapeno_core u_core (
    .clk(clk), .rst(rst),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size),
    .a_wdata(a_wdata), .a_rdata(a_rdata),
    .acc_rd(acc_rd), .acc_wr(acc_wr), .acc_addr(acc_addr), .acc_wdata(acc_wdata), .acc_rdata(acc_rdata),
    .dma_rd(dma_rd), .dma_wr(dma_wr), .dma_addr(dma_addr), .dma_wdata(dma_wdata), .dma_rdata(dma_rdata),
    .pc_q(pc_q), .tcause_q(tcause_q), .tpc_q(tpc_q), .halted(halted)
  );

  alapeno_accel u_accel (
    .clk(clk), .rst(rst),
    .mmio_rd(acc_rd), .mmio_wr(acc_wr), .mmio_addr(acc_addr), .mmio_wdata(acc_wdata), .mmio_rdata(acc_rdata),
    .dma_busy(dma_busy), .conflict_stb(conflict),
    .b_valid(ab_valid), .b_we(ab_we), .b_shadow(ab_shadow), .b_publish(ab_publish), .b_discard(ab_discard),
    .b_addr(ab_addr), .b_size(ab_size), .b_wdata(ab_wdata), .b_rdata(b_rdata),
    .busy(accel_busy),
    .g0_v(g0_v), .g0_base(g0_base), .g0_stride(g0_stride), .g0_rows(g0_rows), .g0_cols(g0_cols), .g0_ew(g0_ew),
    .g1_v(g1_v), .g1_base(g1_base), .g1_stride(g1_stride), .g1_rows(g1_rows), .g1_cols(g1_cols), .g1_ew(g1_ew),
    .g2_v(g2_v), .g2_base(g2_base), .g2_stride(g2_stride), .g2_rows(g2_rows), .g2_cols(g2_cols), .g2_ew(g2_ew)
  );

  alapeno_dma u_dma (
    .clk(clk), .rst(rst),
    .mmio_rd(dma_rd), .mmio_wr(dma_wr), .mmio_addr(dma_addr), .mmio_wdata(dma_wdata), .mmio_rdata(dma_rdata),
    .b_valid(db_valid), .b_we(db_we), .b_addr(db_addr), .b_size(db_size), .b_wdata(db_wdata), .b_rdata(b_rdata),
    .accel_busy(accel_busy), .conflict_stb(conflict),
    .g0_v(g0_v), .g0_base(g0_base), .g0_stride(g0_stride), .g0_rows(g0_rows), .g0_cols(g0_cols), .g0_ew(g0_ew),
    .g1_v(g1_v), .g1_base(g1_base), .g1_stride(g1_stride), .g1_rows(g1_rows), .g1_cols(g1_cols), .g1_ew(g1_ew),
    .g2_v(g2_v), .g2_base(g2_base), .g2_stride(g2_stride), .g2_rows(g2_rows), .g2_cols(g2_cols), .g2_ew(g2_ew),
    .busy(dma_busy)
  );

  always_comb begin
    if (accel_busy) begin
      b_valid = ab_valid;
      b_we = ab_we;
      b_shadow = ab_shadow;
      b_publish = ab_publish;
      b_discard = ab_discard;
      b_addr = ab_addr;
      b_size = ab_size;
      b_wdata = ab_wdata;
    end else begin
      b_valid = db_valid;
      b_we = db_we;
      b_shadow = 1'b0;
      b_publish = 1'b0;
      b_discard = 1'b0;
      b_addr = db_addr;
      b_size = db_size;
      b_wdata = db_wdata;
    end
  end

  alapeno_mem u_mem (
    .clk(clk), .rst(rst),
    .rom_load_we(rom_load_we), .rom_load_addr(rom_load_addr), .rom_load_wdata(rom_load_wdata),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size), .a_wdata(a_wdata), .a_rdata(a_rdata),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow), .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .conflict(conflict)
  );

endmodule
