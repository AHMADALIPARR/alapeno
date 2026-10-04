// SPDX-License-Identifier: AGPL-3.0-only
// One accelerator register file. Matrix ops and vector ops share STATUS.

module alapeno_accel
  import alapeno_pkg::*;
(
  input  logic         clk,
  input  logic         rst,
  input  logic         mmio_rd,
  input  logic         mmio_wr,
  input  logic [11:0]  mmio_addr,
  input  logic [31:0]  mmio_wdata,
  output logic [31:0]  mmio_rdata,
  input  logic         dma_busy,
  input  logic         conflict_stb,
  output logic         b_valid,
  output logic         b_we,
  output logic         b_shadow,
  output logic         b_publish,
  output logic         b_discard,
  output logic [31:0]  b_addr,
  output logic [6:0]   b_size,
  output logic [255:0] b_wdata,
  input  logic [255:0] b_rdata,
  output logic         busy,
  output logic         g0_v,
  output logic [31:0]  g0_base,
  output logic [31:0]  g0_stride,
  output logic [31:0]  g0_rows,
  output logic [31:0]  g0_cols,
  output logic [31:0]  g0_ew,
  output logic         g1_v,
  output logic [31:0]  g1_base,
  output logic [31:0]  g1_stride,
  output logic [31:0]  g1_rows,
  output logic [31:0]  g1_cols,
  output logic [31:0]  g1_ew,
  output logic         g2_v,
  output logic [31:0]  g2_base,
  output logic [31:0]  g2_stride,
  output logic [31:0]  g2_rows,
  output logic [31:0]  g2_cols,
  output logic [31:0]  g2_ew
);

  logic [31:0] reg_op, reg_m, reg_n, reg_k;
  logic [31:0] reg_pa, reg_pb, reg_pc, reg_lda, reg_ldb, reg_ldc, reg_vl, reg_mode;
  logic [31:0] s_op, s_m, s_n, s_k, s_pa, s_pb, s_pc, s_lda, s_ldb, s_ldc, s_vl;
  logic        s_field;
  logic        done_b, fault_b, conflict_b;
  logic        run_m, run_v;
  logic        m_valid, m_we, m_shadow, m_pub, m_disc, m_complete, m_fail;
  logic [31:0] m_addr;
  logic [6:0]  m_size;
  logic [255:0] m_wdata;
  logic        v_valid, v_we, v_shadow, v_pub, v_disc, v_complete, v_fail;
  logic [31:0] v_addr;
  logic [6:0]  v_size;
  logic [255:0] v_wdata;
  logic        kill;
  logic        start_now, abort_now;
  logic        mode_bad, op_ok, is_mat, is_vec, empty_ok, shape_bad, limit_bad;
  logic        want_m, want_v;
  logic [31:0] ew_ab, ew_c;
  logic        a_on, b_on, c_on;

  assign busy = run_m | run_v;
  assign kill = mmio_wr && (mmio_addr == 12'h000) && mmio_wdata[1] && busy;
  assign abort_now = kill;
  assign start_now = mmio_wr && (mmio_addr == 12'h000) && mmio_wdata[0] && !kill;

  assign is_mat = (reg_op == AOP_MATMUL) || (reg_op == AOP_ROUTE) || (reg_op == AOP_PROJECT);
  assign is_vec = (reg_op == AOP_VADD) || (reg_op == AOP_VSUB) || (reg_op == AOP_SUM) ||
                  (reg_op == AOP_MIN) || (reg_op == AOP_MAX);
  assign op_ok = is_mat || is_vec;
  assign mode_bad = (reg_mode[31:1] != 31'h0) || ((reg_op == AOP_PROJECT) && (reg_mode != 32'h0));
  assign ew_ab = 32'd8;
  assign ew_c = ((reg_op == AOP_MATMUL) || (reg_op == AOP_ROUTE) || (reg_op == AOP_SUM)) && (reg_mode[0] == 1'b0)
                ? 32'd32 : 32'd8;

  always_comb begin
    shape_bad = 1'b0;
    empty_ok = 1'b0;
    limit_bad = 1'b0;
    if (!op_ok || mode_bad) shape_bad = 1'b1;
    else if ((reg_op == AOP_MIN) || (reg_op == AOP_MAX)) begin
      if (reg_vl == 32'h0) shape_bad = 1'b1;
      else if (reg_vl > 32'd64) limit_bad = 1'b1;
    end else if ((reg_op == AOP_VADD) || (reg_op == AOP_VSUB)) begin
      if (reg_vl == 32'h0) empty_ok = 1'b1;
      else if (reg_vl > 32'd64) limit_bad = 1'b1;
    end else if (reg_op == AOP_SUM) begin
      if (reg_vl > 32'd64) limit_bad = 1'b1;
    end else if ((reg_m == 32'h0) || (reg_n == 32'h0)) begin
      empty_ok = 1'b1;
    end else begin
      if ((reg_m > 32'd64) || (reg_n > 32'd64)) limit_bad = 1'b1;
      if ((reg_op != AOP_PROJECT) && (reg_k > 32'd64)) limit_bad = 1'b1;
    end
    if (limit_bad) shape_bad = 1'b1;
    if (!empty_ok && !shape_bad && ((reg_op == AOP_VADD) || (reg_op == AOP_VSUB))) begin
      if (!ptr_align(reg_pa, 32'd8) || !ptr_align(reg_pb, 32'd8) || !ptr_align(reg_pc, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pb, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pc, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pc, 32'd8, 32'd1, reg_vl, 32'd8, reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pc, 32'd8, 32'd1, reg_vl, 32'd8, reg_pb, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
    end
    if (!shape_bad && (reg_op == AOP_SUM)) begin
      if (!ptr_align(reg_pc, ew_c)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pc, ew_c, 32'd1, 32'd1, ew_c)) shape_bad = 1'b1;
      if (reg_vl != 32'h0) begin
        if (!ptr_align(reg_pa, 32'd8)) shape_bad = 1'b1;
        if (!rect_in_sram(reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
        if (geom_pair_overlap(reg_pc, ew_c, 32'd1, 32'd1, ew_c, reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      end
    end
    if (!shape_bad && ((reg_op == AOP_MIN) || (reg_op == AOP_MAX)) && (reg_vl != 32'h0)) begin
      if (!ptr_align(reg_pa, 32'd8) || !ptr_align(reg_pc, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pc, 32'd8, 32'd1, 32'd1, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pc, 32'd8, 32'd1, 32'd1, 32'd8, reg_pa, 32'd8, 32'd1, reg_vl, 32'd8)) shape_bad = 1'b1;
    end
    if (!empty_ok && !shape_bad && ((reg_op == AOP_MATMUL) || (reg_op == AOP_ROUTE))) begin
      if (!stride_ok(reg_lda, reg_k, ew_ab) || !ptr_align(reg_pa, ew_ab)) shape_bad = 1'b1;
      if (reg_op == AOP_MATMUL) begin
        if (!stride_ok(reg_ldb, reg_n, ew_ab) || !ptr_align(reg_pb, ew_ab)) shape_bad = 1'b1;
      end else begin
        if (!stride_ok(reg_ldb, reg_k, ew_ab) || !ptr_align(reg_pb, ew_ab)) shape_bad = 1'b1;
      end
      if (!stride_ok(reg_ldc, reg_n, ew_c) || !ptr_align(reg_pc, ew_c)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && !rect_in_sram(reg_pa, reg_lda, reg_m, reg_k, ew_ab)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && (reg_op == AOP_MATMUL) && !rect_in_sram(reg_pb, reg_ldb, reg_k, reg_n, ew_ab)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && (reg_op == AOP_ROUTE) && !rect_in_sram(reg_pb, reg_ldb, reg_n, reg_k, ew_ab)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pc, reg_ldc, reg_m, reg_n, ew_c)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && geom_pair_overlap(reg_pc, reg_ldc, reg_m, reg_n, ew_c, reg_pa, reg_lda, reg_m, reg_k, ew_ab)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && (reg_op == AOP_MATMUL) &&
          geom_pair_overlap(reg_pc, reg_ldc, reg_m, reg_n, ew_c, reg_pb, reg_ldb, reg_k, reg_n, ew_ab)) shape_bad = 1'b1;
      if ((reg_k != 32'h0) && (reg_op == AOP_ROUTE) &&
          geom_pair_overlap(reg_pc, reg_ldc, reg_m, reg_n, ew_c, reg_pb, reg_ldb, reg_n, reg_k, ew_ab)) shape_bad = 1'b1;
    end
    if (!empty_ok && !shape_bad && (reg_op == AOP_PROJECT)) begin
      if (!stride_ok(reg_lda, reg_n, 32'd8) || !stride_ok(reg_ldb, reg_n, 32'd8) || !stride_ok(reg_ldc, reg_n, 32'd8))
        shape_bad = 1'b1;
      if (!ptr_align(reg_pa, 32'd8) || !ptr_align(reg_pb, 32'd8) || !ptr_align(reg_pc, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pa, reg_lda, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pb, reg_ldb, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
      if (!rect_in_sram(reg_pc, reg_ldc, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pa, reg_lda, reg_m, reg_n, 32'd8, reg_pb, reg_ldb, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pa, reg_lda, reg_m, reg_n, 32'd8, reg_pc, reg_ldc, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
      if (geom_pair_overlap(reg_pb, reg_ldb, reg_m, reg_n, 32'd8, reg_pc, reg_ldc, reg_m, reg_n, 32'd8)) shape_bad = 1'b1;
    end
    want_m = is_mat && !empty_ok && !shape_bad;
    want_v = is_vec && !empty_ok && !shape_bad;
  end

  alapeno_matrix u_matrix (
    .clk(clk), .rst(rst), .run(run_m), .kill(kill), .field_mode(s_field), .op(s_op),
    .m_dim(s_m), .n_dim(s_n), .k_dim(s_k),
    .ptr_a(s_pa), .ptr_b(s_pb), .ptr_c(s_pc),
    .lda(s_lda), .ldb(s_ldb), .ldc(s_ldc),
    .b_valid(m_valid), .b_we(m_we), .b_shadow(m_shadow), .b_publish(m_pub), .b_discard(m_disc),
    .b_addr(m_addr), .b_size(m_size), .b_wdata(m_wdata), .b_rdata(b_rdata),
    .complete(m_complete), .fail(m_fail)
  );

  alapeno_vector u_vector (
    .clk(clk), .rst(rst), .run(run_v), .kill(kill), .field_mode(s_field), .op(s_op),
    .vl(s_vl), .ptr_a(s_pa), .ptr_b(s_pb), .ptr_c(s_pc),
    .b_valid(v_valid), .b_we(v_we), .b_shadow(v_shadow), .b_publish(v_pub), .b_discard(v_disc),
    .b_addr(v_addr), .b_size(v_size), .b_wdata(v_wdata), .b_rdata(b_rdata),
    .complete(v_complete), .fail(v_fail)
  );

  assign b_valid = run_m ? m_valid : (run_v ? v_valid : 1'b0);
  assign b_we = run_m ? m_we : (run_v ? v_we : 1'b0);
  assign b_shadow = run_m ? m_shadow : (run_v ? v_shadow : 1'b0);
  assign b_publish = (run_m && m_pub) || (run_v && v_pub);
  assign b_discard = (run_m && m_disc) || (run_v && v_disc);
  assign b_addr = run_m ? m_addr : v_addr;
  assign b_size = run_m ? m_size : v_size;
  assign b_wdata = run_m ? m_wdata : v_wdata;

  always_comb begin
    a_on = 1'b0; b_on = 1'b0; c_on = 1'b0;
    g0_base = s_pa; g0_stride = s_lda; g0_rows = s_m; g0_cols = s_k; g0_ew = ew_ab;
    g1_base = s_pb; g1_stride = s_ldb; g1_rows = s_k; g1_cols = s_n; g1_ew = ew_ab;
    g2_base = s_pc; g2_stride = s_ldc; g2_rows = s_m; g2_cols = s_n; g2_ew = 32'd32;
    if (!busy) begin
      g0_v = 1'b0; g1_v = 1'b0; g2_v = 1'b0;
    end else if ((s_op == AOP_MATMUL) || (s_op == AOP_ROUTE)) begin
      g0_v = (s_k != 0);
      g0_rows = s_m; g0_cols = s_k; g0_stride = s_lda; g0_ew = 32'd8; g0_base = s_pa;
      g1_v = (s_k != 0);
      if (s_op == AOP_MATMUL) begin
        g1_rows = s_k; g1_cols = s_n;
      end else begin
        g1_rows = s_n; g1_cols = s_k;
      end
      g1_stride = s_ldb; g1_ew = 32'd8; g1_base = s_pb;
      g2_v = 1'b1;
      g2_rows = s_m; g2_cols = s_n; g2_stride = s_ldc; g2_base = s_pc;
      g2_ew = s_field ? 32'd8 : 32'd32;
    end else if (s_op == AOP_PROJECT) begin
      g0_v = 1'b1; g0_base = s_pa; g0_stride = s_lda; g0_rows = s_m; g0_cols = s_n; g0_ew = 32'd8;
      g1_v = 1'b1; g1_base = s_pb; g1_stride = s_ldb; g1_rows = s_m; g1_cols = s_n; g1_ew = 32'd8;
      g2_v = 1'b1; g2_base = s_pc; g2_stride = s_ldc; g2_rows = s_m; g2_cols = s_n; g2_ew = 32'd8;
    end else if ((s_op == AOP_VADD) || (s_op == AOP_VSUB)) begin
      g0_v = 1'b1; g0_base = s_pa; g0_stride = 32'd8; g0_rows = 32'd1; g0_cols = s_vl; g0_ew = 32'd8;
      g1_v = 1'b1; g1_base = s_pb; g1_stride = 32'd8; g1_rows = 32'd1; g1_cols = s_vl; g1_ew = 32'd8;
      g2_v = 1'b1; g2_base = s_pc; g2_stride = 32'd8; g2_rows = 32'd1; g2_cols = s_vl; g2_ew = 32'd8;
    end else begin
      g0_v = (s_vl != 0);
      g0_base = s_pa; g0_stride = 32'd8; g0_rows = 32'd1; g0_cols = s_vl; g0_ew = 32'd8;
      g1_v = 1'b0;
      g2_v = 1'b1;
      g2_base = s_pc; g2_stride = (s_op == AOP_SUM && !s_field) ? 32'd32 : 32'd8;
      g2_rows = 32'd1; g2_cols = 32'd1; g2_ew = g2_stride;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      reg_op <= 32'h0; reg_m <= 32'h0; reg_n <= 32'h0; reg_k <= 32'h0;
      reg_pa <= 32'h0; reg_pb <= 32'h0; reg_pc <= 32'h0;
      reg_lda <= 32'h0; reg_ldb <= 32'h0; reg_ldc <= 32'h0;
      reg_vl <= 32'h0; reg_mode <= 32'h0;
      s_op <= 32'h0; s_m <= 32'h0; s_n <= 32'h0; s_k <= 32'h0;
      s_pa <= 32'h0; s_pb <= 32'h0; s_pc <= 32'h0;
      s_lda <= 32'h0; s_ldb <= 32'h0; s_ldc <= 32'h0; s_vl <= 32'h0;
      s_field <= 1'b0;
      done_b <= 1'b0; fault_b <= 1'b0; conflict_b <= 1'b0;
      run_m <= 1'b0; run_v <= 1'b0;
      mmio_rdata <= 32'h0;
    end else begin
      if (mmio_wr && (mmio_addr == 12'h004)) begin
        if (mmio_wdata[1]) done_b <= 1'b0;
        if (mmio_wdata[2]) fault_b <= 1'b0;
        if (mmio_wdata[3]) conflict_b <= 1'b0;
      end
      if (conflict_stb) conflict_b <= 1'b1;
      if (mmio_wr && (mmio_addr == 12'h008)) reg_op <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h00C)) reg_m <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h010)) reg_n <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h014)) reg_k <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h018)) reg_pa <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h01C)) reg_pb <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h020)) reg_pc <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h024)) reg_lda <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h028)) reg_ldb <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h02C)) reg_ldc <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h030)) reg_vl <= mmio_wdata;
      if (mmio_wr && (mmio_addr == 12'h034)) reg_mode <= mmio_wdata;

      if (abort_now) begin
        run_m <= 1'b0;
        run_v <= 1'b0;
        done_b <= 1'b0;
      end else if ((run_m && m_complete) || (run_v && v_complete)) begin
        run_m <= 1'b0;
        run_v <= 1'b0;
        done_b <= 1'b1;
      end else if ((run_m && m_fail) || (run_v && v_fail)) begin
        run_m <= 1'b0;
        run_v <= 1'b0;
        fault_b <= 1'b1;
        done_b <= 1'b0;
      end else if (start_now) begin
        if (busy) begin
          fault_b <= 1'b1;
          done_b <= 1'b0;
        end else if (fault_b || dma_busy || shape_bad) begin
          fault_b <= 1'b1;
          done_b <= 1'b0;
        end else if (empty_ok) begin
          done_b <= 1'b1;
          fault_b <= 1'b0;
        end else begin
          s_op <= reg_op; s_m <= reg_m; s_n <= reg_n; s_k <= reg_k;
          s_pa <= reg_pa; s_pb <= reg_pb; s_pc <= reg_pc;
          s_lda <= reg_lda; s_ldb <= reg_ldb; s_ldc <= reg_ldc; s_vl <= reg_vl;
          s_field <= reg_mode[0];
          done_b <= 1'b0;
          fault_b <= 1'b0;
          run_m <= want_m;
          run_v <= want_v;
        end
      end

      if (mmio_rd) begin
        case (mmio_addr)
          12'h000: mmio_rdata <= 32'h0;
          12'h004: mmio_rdata <= {28'h0, conflict_b, fault_b, done_b, busy};
          12'h008: mmio_rdata <= reg_op;
          12'h00C: mmio_rdata <= reg_m;
          12'h010: mmio_rdata <= reg_n;
          12'h014: mmio_rdata <= reg_k;
          12'h018: mmio_rdata <= reg_pa;
          12'h01C: mmio_rdata <= reg_pb;
          12'h020: mmio_rdata <= reg_pc;
          12'h024: mmio_rdata <= reg_lda;
          12'h028: mmio_rdata <= reg_ldb;
          12'h02C: mmio_rdata <= reg_ldc;
          12'h030: mmio_rdata <= reg_vl;
          12'h034: mmio_rdata <= reg_mode;
          default: mmio_rdata <= 32'h0;
        endcase
      end
    end
  end

endmodule
