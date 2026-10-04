// SPDX-License-Identifier: AGPL-3.0-only
// MATMUL, ROUTE, and PROJECT. Destination bytes publish only after a full success.

module alapeno_matrix
  import alapeno_pkg::*;
#(
  parameter int OBUF_BYTES = 131072
)
(
  input  logic         clk,
  input  logic         rst,
  input  logic         run,
  input  logic         kill,
  input  logic         field_mode,
  input  logic [31:0]  op,
  input  logic [31:0]  m_dim,
  input  logic [31:0]  n_dim,
  input  logic [31:0]  k_dim,
  input  logic [31:0]  ptr_a,
  input  logic [31:0]  ptr_b,
  input  logic [31:0]  ptr_c,
  input  logic [31:0]  lda,
  input  logic [31:0]  ldb,
  input  logic [31:0]  ldc,
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

  localparam logic [3:0] M_IDLE = 4'd0;
  localparam logic [3:0] M_ZA   = 4'd1;
  localparam logic [3:0] M_CA   = 4'd2;
  localparam logic [3:0] M_ZB   = 4'd3;
  localparam logic [3:0] M_CB   = 4'd4;
  localparam logic [3:0] M_ZEL  = 4'd5;
  localparam logic [3:0] M_RE   = 4'd6;
  localparam logic [3:0] M_CE   = 4'd7;
  localparam logic [3:0] M_RP   = 4'd8;
  localparam logic [3:0] M_CP   = 4'd9;
  localparam logic [3:0] M_RJ   = 4'd10;
  localparam logic [3:0] M_CJ   = 4'd11;
  localparam logic [3:0] M_SH   = 4'd12;
  localparam logic [3:0] M_PUB  = 4'd13;
  localparam logic [3:0] M_BAD  = 4'd14;
  localparam logic [3:0] M_PACK = 4'd15;

  logic [3:0] state;
  logic [31:0] m, n, k, pass;
  logic [63:0] hold_a, hold_b, hold_e, hold_p, hold_j, fres;
  logic signed [255:0] accz;
  logic [7:0] obuf [0:OBUF_BYTES-1];
  integer bi;
  logic [31:0] ew, ix, baddr;
  logic is_proj, is_route;
  logic signed [64:0] ks, qs, diff65;
  logic pred;
  logic [63:0] bval, dres, pmod;
  logic signed [127:0] sprod;
  zadd_t za;
  s64r_t d0, d1, d2;
  logic [255:0] pack_w;
  logic [255:0] beat;
  logic [255:0] zbytes;
  logic [63:0] d1b, d2b, jnew;
  logic step_bad;

  assign is_proj = (op == AOP_PROJECT);
  assign is_route = (op == AOP_ROUTE);
  assign ew = is_proj ? 32'd8 : (field_mode ? 32'd8 : 32'd32);
  // ew_sz outside the always_comb so Icarus does not widen the read.
  logic [6:0] ew_sz;
  assign ew_sz = ew[6:0];

  always_comb begin
    b_valid = 1'b0;
    b_we = 1'b0;
    b_shadow = 1'b0;
    b_publish = 1'b0;
    b_discard = 1'b0;
    b_addr = 32'h0;
    b_size = ew_sz;
    b_wdata = '0;
    complete = 1'b0;
    fail = 1'b0;
    if (kill && (state != M_IDLE)) b_discard = 1'b1;
    else if (state == M_ZA) begin
      b_valid = 1'b1;
      b_size = 7'd8;
      b_addr = ptr_a + (m * lda) + (k * 32'd8);
    end else if (state == M_ZB) begin
      b_valid = 1'b1;
      b_size = 7'd8;
      if (is_route) b_addr = ptr_b + (n * ldb) + (k * 32'd8);
      else b_addr = ptr_b + (k * ldb) + (n * 32'd8);
    end else if (state == M_RE) begin
      b_valid = 1'b1;
      b_size = 7'd8;
      b_addr = ptr_a + (m * lda) + (n * 32'd8);
    end else if (state == M_RP) begin
      b_valid = 1'b1;
      b_size = 7'd8;
      b_addr = ptr_b + (m * ldb) + (n * 32'd8);
    end else if (state == M_RJ) begin
      b_valid = 1'b1;
      b_size = 7'd8;
      b_addr = ptr_c + (m * ldc) + (n * 32'd8);
    end else if (state == M_SH) begin
      b_valid = 1'b1;
      b_we = 1'b1;
      b_shadow = 1'b1;
      b_size = ew_sz;
      if (is_proj && (pass == 32'd1))
        b_addr = ptr_b + (m * ldb) + (n * 32'd8);
      else if (is_proj)
        b_addr = ptr_c + (m * ldc) + (n * 32'd8);
      else
        b_addr = ptr_c + (m * ldc) + (n * ew);
      b_wdata = beat;
    end else if (state == M_PUB) begin
      b_publish = 1'b1;
      complete = 1'b1;
    end else if (state == M_BAD) begin
      b_discard = 1'b1;
      fail = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= M_IDLE;
      m <= 32'h0;
      n <= 32'h0;
      k <= 32'h0;
      pass <= 32'h0;
      hold_a <= 64'h0;
      hold_b <= 64'h0;
      hold_e <= 64'h0;
      hold_p <= 64'h0;
      hold_j <= 64'h0;
      fres <= 64'h0;
      accz <= '0;
      beat <= '0;
    end else if (kill) begin
      state <= M_IDLE;
    end else begin
      case (state)
        M_IDLE: begin
          if (run) begin
            m <= 32'h0;
            n <= 32'h0;
            k <= 32'h0;
            pass <= 32'h0;
            fres <= 64'h0;
            accz <= '0;
            if (is_proj && field_mode) state <= M_BAD;
            else if ((m_dim == 32'h0) || (n_dim == 32'h0)) state <= M_PUB;
            else if (is_proj) state <= M_RE;
            else if (k_dim == 32'h0) state <= M_ZEL;
            else state <= M_ZA;
          end
        end
        M_ZA: state <= M_CA;
        M_CA: begin
          if (field_mode && (b_rdata[63:0] >= P)) state <= M_BAD;
          else begin
            hold_a <= b_rdata[63:0];
            state <= M_ZB;
          end
        end
        M_ZB: state <= M_CB;
        M_CB: begin
          bval = b_rdata[63:0];
          step_bad = 1'b0;
          if (field_mode && ((hold_a >= P) || (bval >= P))) begin
            state <= M_BAD;
            step_bad = 1'b1;
          end else begin
            if (is_route && field_mode) begin
              dres = field_sub(bval, hold_a);
              pred = center_le_zero(dres);
              pmod = euclid_mod_p({{128{1'b0}}, mul_u64(hold_a, bval)});
              if (pred) fres <= field_add(fres, pmod);
            end else if (is_route) begin
              ks = {bval[63], bval};
              qs = {hold_a[63], hold_a};
              diff65 = ks - qs;
              pred = (diff65 <= 0);
              if (pred) begin
                sprod = mul_s64(hold_a, bval);
                za = z_add(accz, {{128{sprod[127]}}, sprod});
              end else za = z_add(accz, '0);
              if (!za.ok) begin state <= M_BAD; step_bad = 1'b1; end
              else accz <= za.sum;
            end else if (field_mode) begin
              za = z_add(accz, {{128{1'b0}}, mul_u64(hold_a, bval)});
              if (!za.ok) begin state <= M_BAD; step_bad = 1'b1; end
              else accz <= za.sum;
            end else begin
              sprod = mul_s64(hold_a, bval);
              za = z_add(accz, {{128{sprod[127]}}, sprod});
              if (!za.ok) begin state <= M_BAD; step_bad = 1'b1; end
              else accz <= za.sum;
            end
            if (!step_bad) begin
              if ((k + 32'd1) == k_dim) begin
                ix = (m * n_dim + n) * ew;
                if (is_route && field_mode) begin
                  pmod = pred ? field_add(fres, pmod) : fres;
                  for (bi = 0; bi < 8; bi = bi + 1)
                    obuf[ix + bi[31:0]] <= pmod[(bi * 8) +: 8];
                end else if (field_mode) begin
                  pmod = euclid_mod_p(za.sum);
                  for (bi = 0; bi < 8; bi = bi + 1)
                    obuf[ix + bi[31:0]] <= pmod[(bi * 8) +: 8];
                end else begin
                  zbytes = za.sum;
                  for (bi = 0; bi < 32; bi = bi + 1)
                    obuf[ix + bi[31:0]] <= zbytes[(bi * 8) +: 8];
                end
                k <= 32'h0;
                fres <= 64'h0;
                accz <= '0;
                if ((n + 32'd1) == n_dim) begin
                  n <= 32'h0;
                  if ((m + 32'd1) == m_dim) begin
                    m <= 32'h0;
                    state <= M_PACK;
                  end else begin
                    m <= m + 32'd1;
                    state <= M_ZA;
                  end
                end else begin
                  n <= n + 32'd1;
                  state <= M_ZA;
                end
              end else begin
                k <= k + 32'd1;
                state <= M_ZA;
              end
            end
          end
        end
        M_ZEL: begin
          ix = (m * n_dim + n) * ew;
          for (bi = 0; bi < 32; bi = bi + 1)
            if (bi < ew) obuf[ix + bi[31:0]] <= 8'h00;
          if ((n + 32'd1) == n_dim) begin
            n <= 32'h0;
            if ((m + 32'd1) == m_dim) begin
              m <= 32'h0;
              state <= M_PACK;
            end else m <= m + 32'd1;
          end else n <= n + 32'd1;
        end
        M_RE: state <= M_CE;
        M_CE: begin
          hold_e <= b_rdata[63:0];
          state <= M_RP;
        end
        M_RP: state <= M_CP;
        M_CP: begin
          hold_p <= b_rdata[63:0];
          state <= M_RJ;
        end
        M_RJ: state <= M_CJ;
        M_CJ: begin
          jnew = b_rdata[63:0];
          hold_j <= jnew;
          d0 = s64_sub(hold_e, hold_p);
          d1 = s64_add(jnew, d0.val);
          d2 = s64_add(hold_p, d1.val);
          if (!d0.ok || !d1.ok || !d2.ok) state <= M_BAD;
          else begin
            ix = (m * n_dim + n) * 32'd8;
            d1b = d1.val;
            d2b = d2.val;
            for (bi = 0; bi < 8; bi = bi + 1) begin
              obuf[ix + bi[31:0]] <= d1b[(bi * 8) +: 8];
              if (OBUF_BYTES > 65536)
                obuf[32'd65536 + ix + bi[31:0]] <= d2b[(bi * 8) +: 8];
            end
            if ((n + 32'd1) == n_dim) begin
              n <= 32'h0;
              if ((m + 32'd1) == m_dim) begin
                m <= 32'h0;
                pass <= 32'h0;
                state <= M_PACK;
              end else m <= m + 32'd1;
            end else n <= n + 32'd1;
            if (!((n + 32'd1) == n_dim && (m + 32'd1) == m_dim)) state <= M_RE;
          end
        end
        M_PACK: begin
          pack_w = '0;
          if (is_proj && (pass == 32'd1) && (OBUF_BYTES > 65536))
            ix = 32'd65536 + (m * n_dim + n) * 32'd8;
          else if (is_proj) ix = (m * n_dim + n) * 32'd8;
          else ix = (m * n_dim + n) * ew;
          for (bi = 0; bi < 32; bi = bi + 1) begin
            if (bi < ew) pack_w[(bi * 8) +: 8] = obuf[ix + bi[31:0]];
          end
          beat <= pack_w;
          state <= M_SH;
        end
        M_SH: begin
          if ((n + 32'd1) == n_dim) begin
            n <= 32'h0;
            if ((m + 32'd1) == m_dim) begin
              m <= 32'h0;
              if (is_proj && (pass == 32'd0)) begin
                pass <= 32'd1;
                state <= M_PACK;
              end else state <= M_PUB;
            end else begin
              m <= m + 32'd1;
              state <= M_PACK;
            end
          end else begin
            n <= n + 32'd1;
            state <= M_PACK;
          end
        end
        M_PUB: state <= M_IDLE;
        M_BAD: state <= M_IDLE;
        default: state <= M_IDLE;
      endcase
    end
  end

endmodule
