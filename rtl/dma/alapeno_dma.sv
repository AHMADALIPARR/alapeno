// SPDX-License-Identifier: AGPL-3.0-only
// DMA byte copy. Beats are 8 bytes in ascending order. Abort keeps committed beats.

module alapeno_dma
  import alapeno_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  logic        mmio_rd,
  input  logic        mmio_wr,
  input  logic [11:0] mmio_addr,
  input  logic [31:0] mmio_wdata,
  output logic [31:0] mmio_rdata,
  output logic        b_valid,
  output logic        b_we,
  output logic [31:0] b_addr,
  output logic [6:0]  b_size,
  output logic [255:0] b_wdata,
  input  logic [255:0] b_rdata,
  input  logic        accel_busy,
  input  logic        conflict_stb,
  input  logic        g0_v,
  input  logic [31:0] g0_base, g0_stride, g0_rows, g0_cols, g0_ew,
  input  logic        g1_v,
  input  logic [31:0] g1_base, g1_stride, g1_rows, g1_cols, g1_ew,
  input  logic        g2_v,
  input  logic [31:0] g2_base, g2_stride, g2_rows, g2_cols, g2_ew,
  output logic        busy
);

  localparam logic [1:0] D_IDLE = 2'd0;
  localparam logic [1:0] D_RD   = 2'd1;
  localparam logic [1:0] D_WR   = 2'd2;

  logic [31:0] src, dst, len;
  logic [31:0] copy_src, copy_dst, copy_len, copy_off;
  logic done_b, fault_b, conflict_b;
  logic [1:0] state;
  logic abort_now, start_now, stop_now;
  logic [32:0] src_end, dst_end;
  logic bad_len, bad_align, bad_range, bad_ov;
  logic accept;
  logic [2:0] len_lo, src_lo, dst_lo;
  logic src_end_hi, dst_end_hi;

  assign busy = (state != D_IDLE);
  // Low 3 bits outside the always_comb. Same bits as len[2:0], src[2:0], dst[2:0].
  assign len_lo = len[2:0];
  assign src_lo = src[2:0];
  assign dst_lo = dst[2:0];
  assign abort_now = mmio_wr && (mmio_addr == 12'h00C) && mmio_wdata[1] && busy;
  assign start_now = mmio_wr && (mmio_addr == 12'h00C) && mmio_wdata[0] && !(mmio_wdata[1] && busy);
  assign stop_now = abort_now || (start_now && busy);

  always_comb begin
    src_end = {1'b0, src} + {1'b0, len};
    dst_end = {1'b0, dst} + {1'b0, len};
    bad_len = (len_lo != 3'b000) || (len == 32'h0) || (len > 32'd524288);
    bad_align = (src_lo != 3'b000) || (dst_lo != 3'b000);
    src_end_hi = src_end >> 32;
    dst_end_hi = dst_end >> 32;
    bad_range = src_end_hi || dst_end_hi ||
                (src < SRAM_LO) || (src_end > 33'h0_1008_0000) ||
                (dst < SRAM_LO) || (dst_end > 33'h0_1008_0000);
    bad_ov = geom_hits(src, len, g0_v, g0_base, g0_stride, g0_rows, g0_cols, g0_ew) ||
             geom_hits(src, len, g1_v, g1_base, g1_stride, g1_rows, g1_cols, g1_ew) ||
             geom_hits(src, len, g2_v, g2_base, g2_stride, g2_rows, g2_cols, g2_ew) ||
             geom_hits(dst, len, g0_v, g0_base, g0_stride, g0_rows, g0_cols, g0_ew) ||
             geom_hits(dst, len, g1_v, g1_base, g1_stride, g1_rows, g1_cols, g1_ew) ||
             geom_hits(dst, len, g2_v, g2_base, g2_stride, g2_rows, g2_cols, g2_ew);
    accept = start_now && !busy && !fault_b && !accel_busy && !bad_len && !bad_align && !bad_range && !bad_ov;
  end

  always_comb begin
    b_valid = 1'b0;
    b_we = 1'b0;
    b_addr = 32'h0;
    b_size = 7'd8;
    b_wdata = '0;
    if (!stop_now && !accel_busy && (state == D_RD)) begin
      b_valid = 1'b1;
      b_we = 1'b0;
      b_addr = copy_src + copy_off;
    end else if (!stop_now && !accel_busy && (state == D_WR)) begin
      b_valid = 1'b1;
      b_we = 1'b1;
      b_addr = copy_dst + copy_off;
      b_wdata = b_rdata;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      src <= 32'h0;
      dst <= 32'h0;
      len <= 32'h0;
      copy_src <= 32'h0;
      copy_dst <= 32'h0;
      copy_len <= 32'h0;
      copy_off <= 32'h0;
      done_b <= 1'b0;
      fault_b <= 1'b0;
      conflict_b <= 1'b0;
      state <= D_IDLE;
      mmio_rdata <= 32'h0;
    end else begin
      if (mmio_wr && (mmio_addr == 12'h010)) begin
        if (mmio_wdata[1]) done_b <= 1'b0;
        if (mmio_wdata[2]) fault_b <= 1'b0;
        if (mmio_wdata[3]) conflict_b <= 1'b0;
      end
      if (conflict_stb) conflict_b <= 1'b1;
      if (mmio_wr && (mmio_addr == 12'h000)) src <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h004)) dst <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h008)) len <= mmio_wdata;

      if (stop_now) begin
        state <= D_IDLE;
        if (abort_now) done_b <= 1'b0;
        if (start_now && busy && !abort_now) begin
          fault_b <= 1'b1;
          done_b <= 1'b0;
        end
      end else if (accept) begin
        copy_src <= src;
        copy_dst <= dst;
        copy_len <= len;
        copy_off <= 32'h0;
        done_b <= 1'b0;
        state <= D_RD;
      end else if (start_now && !accept) begin
        fault_b <= 1'b1;
        done_b <= 1'b0;
        state <= D_IDLE;
      end else if (state == D_RD) begin
        if (!accel_busy) state <= D_WR;
      end else if (state == D_WR) begin
        if (!accel_busy) begin
          if ((copy_off + 32'd8) == copy_len) begin
            state <= D_IDLE;
            done_b <= 1'b1;
          end else begin
            copy_off <= copy_off + 32'd8;
            state <= D_RD;
          end
        end
      end

      if (mmio_rd) begin
        case (mmio_addr)
          12'h000: mmio_rdata <= src;
          12'h004: mmio_rdata <= dst;
          12'h008: mmio_rdata <= len;
          12'h00C: mmio_rdata <= 32'h0;
          12'h010: mmio_rdata <= {28'h0, conflict_b, fault_b, done_b, busy};
          default: mmio_rdata <= 32'h0;
        endcase
      end
    end
  end

endmodule
