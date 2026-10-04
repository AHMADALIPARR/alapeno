// SPDX-License-Identifier: AGPL-3.0-only
// Integer MAC reference. No shortreal, no real.
// product = a[3:0] * b[3:0]
// acc_next = (acc[7:0] + product) wrapped modulo 256.

module mac_ref (
  input  wire [7:0] acc,
  input  wire [3:0] a,
  input  wire [3:0] b,
  output reg  [7:0] acc_next
);
  function automatic [7:0] mac_acc_next(
    input [7:0] acc_i,
    input [3:0] a_i,
    input [3:0] b_i
  );
    integer product;
    integer sum;
    begin
      product = {28'b0, a_i} * {28'b0, b_i};
      sum = {24'b0, acc_i} + product;
      mac_acc_next = sum[7:0];
    end
  endfunction

  always @* begin
    acc_next = mac_acc_next(acc, a, b);
  end
endmodule
