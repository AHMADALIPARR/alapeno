// SPDX-License-Identifier: AGPL-3.0-only
// Vector add, sub, and reductions. Results stay in a buffer until publish.

module alapeno_vector
  import alapeno_pkg::*;
(
  input  logic         clk,
  input  logic         rst,
  input  logic         run,
  input  logic         kill,
  input  logic         field_mode,
  input  logic [31:0]  op,
  input  logic [31:0]  vl,
  input  logic [31:0]  ptr_a,
  input  logic [31:0]  ptr_b,
  input  logic [31:0]  ptr_c,
  output logic         b_valid,
  output logic         b_we,
  output logic         b_shadow,
  output logic         b_publish,
  output logic         b_discard,
  output logic [31:0]  b_addr,
  output logic [6:0]   b_size,
  output logic [255:0] b_wdata,
  input  logic [255:0] b_rdata,
  output logic         complete,
  output logic         fail
);

  localparam logic [3:0] V_IDLE = 4'd0;
  localparam logic [3:0] V_RDA  = 4'd1;
  localparam logic [3:0] V_CPA  = 4'd2;
  localparam logic [3:0] V_RDB  = 4'd3;
  localparam logic [3:0] V_CPB  = 4'd4;
  localparam logic [3:0] V_SH   = 4'd5;
  localparam logic [3:0] V_PUB  = 4'd6;
  localparam logic [3:0] V_BAD  = 4'd7;

  logic [3:0] state;
  logic [31:0] idx, sh;
  logic [63:0] hold_a, acc64, cur64;
  logic signed [255:0] accz;
  logic [7:0] obuf [0:511];
  logic saw;
  integer bi;
  s64r_t sr;
  zadd_t za;
  logic [63:0] elem, other, outv, srval;
  logic bad_elem;
  logic [31:0] ew;
  logic red_sum, red_mm, vec_op;

  assign red_sum = (op == AOP_SUM);
  assign red_mm = (op == AOP_MIN) || (op == AOP_MAX);
  assign vec_op = (op == AOP_VADD) || (op == AOP_VSUB);
  assign ew = (red_sum && !field_mode) ? 32'd32 : 32'd8;

  always_comb begin
    b_valid = 1'b0;
    b_we = 1'b0;
    b_shadow = 1'b0;
    b_publish = 1'b0;
    b_discard = 1'b0;
    b_addr = 32'h0;
    b_size = 7'd8;
    b_wdata = '0;
    complete = 1'b0;
    fail = 1'b0;
    if (kill && (state != V_IDLE)) begin
      b_discard = 1'b1;
    end else if (state == V_RDA) begin
      b_valid = 1'b1;
      b_addr = ptr_a + (idx * 32'd8);
      b_size = 7'd8;
    end else if (state == V_RDB) begin
      b_valid = 1'b1;
      b_addr = ptr_b + (idx * 32'd8);
      b_size = 7'd8;
    end else if (state == V_SH) begin
      b_valid = 1'b1;
      b_we = 1'b1;
      b_shadow = 1'b1;
      b_size = ew[6:0];
      if (vec_op) begin
        b_addr = ptr_c + (sh * 32'd8);
        for (bi = 0; bi < 8; bi = bi + 1)
          b_wdata[(bi * 8) +: 8] = obuf[(sh * 8) + bi[31:0]];
      end else if (red_sum && !field_mode) begin
        b_addr = ptr_c;
        b_size = 7'd32;
        b_wdata = accz;
      end else if (red_sum) begin
        b_addr = ptr_c;
        b_wdata = {192'h0, acc64};
      end else begin
        b_addr = ptr_c;
        b_wdata = {192'h0, cur64};
      end
    end else if (state == V_PUB) begin
      b_publish = 1'b1;
      complete = 1'b1;
    end else if (state == V_BAD) begin
      b_discard = 1'b1;
      fail = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= V_IDLE;
      idx <= 32'h0;
      sh <= 32'h0;
      hold_a <= 64'h0;
      acc64 <= 64'h0;
      cur64 <= 64'h0;
      accz <= '0;
      saw <= 1'b0;
    end else if (kill) begin
      state <= V_IDLE;
    end else begin
      case (state)
        V_IDLE: begin
          if (run) begin
            idx <= 32'h0;
            sh <= 32'h0;
            acc64 <= 64'h0;
            cur64 <= 64'h0;
            accz <= '0;
            saw <= 1'b0;
            if (vec_op && (vl == 32'h0)) state <= V_PUB;
            else if (red_sum && (vl == 32'h0)) state <= V_SH;
            else if (red_mm && (vl == 32'h0)) state <= V_BAD;
            else state <= V_RDA;
          end
        end
        V_RDA: state <= V_CPA;
        V_CPA: begin
          elem = b_rdata[63:0];
          bad_elem = field_mode && (elem >= P);
          if (bad_elem) state <= V_BAD;
          else if (vec_op) begin
            hold_a <= elem;
            state <= V_RDB;
          end else if (red_sum && field_mode) begin
            acc64 <= field_add(acc64, elem);
            if ((idx + 32'd1) == vl) state <= V_SH;
            else begin idx <= idx + 32'd1; state <= V_RDA; end
          end else if (red_sum) begin
            za = z_add(accz, {{192{elem[63]}}, elem});
            if (!za.ok) state <= V_BAD;
            else begin
              accz <= za.sum;
              if ((idx + 32'd1) == vl) state <= V_SH;
              else begin idx <= idx + 32'd1; state <= V_RDA; end
            end
          end else begin
            if (!saw) cur64 <= elem;
            else if (field_mode) begin
              if (op == AOP_MIN) cur64 <= center_less(elem, cur64) ? elem : cur64;
              else cur64 <= center_less(cur64, elem) ? elem : cur64;
            end else if (op == AOP_MIN) begin
              cur64 <= ($signed(elem) < $signed(cur64)) ? elem : cur64;
            end else begin
              cur64 <= ($signed(elem) > $signed(cur64)) ? elem : cur64;
            end
            saw <= 1'b1;
            if ((idx + 32'd1) == vl) state <= V_SH;
            else begin idx <= idx + 32'd1; state <= V_RDA; end
          end
        end
        V_RDB: state <= V_CPB;
        V_CPB: begin
          other = b_rdata[63:0];
          bad_elem = field_mode && ((hold_a >= P) || (other >= P));
          if (bad_elem) state <= V_BAD;
          else if (field_mode) begin
            outv = (op == AOP_VADD) ? field_add(hold_a, other) : field_sub(hold_a, other);
            for (bi = 0; bi < 8; bi = bi + 1)
              obuf[(idx * 8) + bi[31:0]] <= outv[(bi * 8) +: 8];
            if ((idx + 32'd1) == vl) begin sh <= 32'h0; state <= V_SH; end
            else begin idx <= idx + 32'd1; state <= V_RDA; end
          end else begin
            if (op == AOP_VADD) sr = s64_add(hold_a, other);
            else sr = s64_sub(hold_a, other);
            if (!sr.ok) state <= V_BAD;
            else begin
              srval = sr.val;
              for (bi = 0; bi < 8; bi = bi + 1)
                obuf[(idx * 8) + bi[31:0]] <= srval[(bi * 8) +: 8];
              if ((idx + 32'd1) == vl) begin sh <= 32'h0; state <= V_SH; end
              else begin idx <= idx + 32'd1; state <= V_RDA; end
            end
          end
        end
        V_SH: begin
          if (vec_op) begin
            if ((sh + 32'd1) == vl) state <= V_PUB;
            else sh <= sh + 32'd1;
          end else state <= V_PUB;
        end
        V_PUB: state <= V_IDLE;
        V_BAD: state <= V_IDLE;
        default: state <= V_IDLE;
      endcase
    end
  end

endmodule
