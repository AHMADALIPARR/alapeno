// SPDX-License-Identifier: AGPL-3.0-only
// One non-field MATMUL tile. Drives the existing alapeno_matrix ports.
// One clock. C is published only when that matrix run succeeds.

module alapeno_tile_ctrl
(
  input  logic         clk,
  input  logic         rst,
  input  logic         start,
  output logic [31:0]  status,
  output logic         b_valid,
  output logic         b_we,
  output logic         b_shadow,
  output logic         b_publish,
  output logic         b_discard,
  output logic [31:0]  b_addr,
  output logic [6:0]   b_size,
  output logic [255:0] b_wdata,
  input  logic [255:0] b_rdata
);

  logic run_q;
  logic done_b;
  logic fault_b;
  logic m_complete;
  logic m_fail;

  assign status = {28'h0, 1'b0, fault_b, done_b, run_q};

  alapeno_matrix #(
    .OBUF_BYTES(512)
  ) u_matrix (
    .clk(clk),
    .rst(rst),
    .run(run_q),
    .kill(1'b0),
    .field_mode(1'b0),
    .op(32'd1),
    .m_dim(32'd4),
    .n_dim(32'd4),
    .k_dim(32'd4),
    .ptr_a(32'h1000_0000),
    .ptr_b(32'h1000_0080),
    .ptr_c(32'h1000_0100),
    .lda(32'd32),
    .ldb(32'd32),
    .ldc(32'd128),
    .b_valid(b_valid),
    .b_we(b_we),
    .b_shadow(b_shadow),
    .b_publish(b_publish),
    .b_discard(b_discard),
    .b_addr(b_addr),
    .b_size(b_size),
    .b_wdata(b_wdata),
    .b_rdata(b_rdata),
    .complete(m_complete),
    .fail(m_fail)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      run_q <= 1'b0;
      done_b <= 1'b0;
      fault_b <= 1'b0;
    end else if (run_q && m_complete) begin
      run_q <= 1'b0;
      done_b <= 1'b1;
      fault_b <= 1'b0;
    end else if (run_q && m_fail) begin
      run_q <= 1'b0;
      done_b <= 1'b0;
      fault_b <= 1'b1;
    end else if (start && !run_q && !fault_b) begin
      run_q <= 1'b1;
      done_b <= 1'b0;
      fault_b <= 1'b0;
    end
  end

endmodule
