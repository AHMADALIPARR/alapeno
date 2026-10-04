// SPDX-License-Identifier: AGPL-3.0-only
// Integer vectors for mac_ref. Mismatch calls $error and $finish(1).

module tb_mac_ref;
  reg  [7:0] acc;
  reg  [3:0] a;
  reg  [3:0] b;
  wire [7:0] acc_next;
  integer errors;

  mac_ref dut (
    .acc(acc),
    .a(a),
    .b(b),
    .acc_next(acc_next)
  );

  initial begin
    errors = 0;

    acc = 8'd0; a = 4'd0; b = 4'd0; #1;
    if (acc_next !== 8'd0) begin
      $error("0*0+0 expected 0 got %0d", acc_next);
      errors = errors + 1;
    end else begin
      $display("check 0*0+0 -> %0d", acc_next);
    end

    acc = 8'd0; a = 4'd15; b = 4'd15; #1;
    if (acc_next !== 8'd225) begin
      $error("15*15+0 expected 225 got %0d", acc_next);
      errors = errors + 1;
    end else begin
      $display("check 15*15+0 -> %0d", acc_next);
    end

    acc = 8'd31; a = 4'd15; b = 4'd15; #1;
    if (acc_next !== 8'd0) begin
      $error("15*15+31 expected wrap 0 got %0d", acc_next);
      errors = errors + 1;
    end else begin
      $display("check 15*15+31 wrap -> %0d", acc_next);
    end

    acc = 8'd4; a = 4'd2; b = 4'd3; #1;
    if (acc_next !== 8'd10) begin
      $error("2*3+4 expected 10 got %0d", acc_next);
      errors = errors + 1;
    end else begin
      $display("check 2*3+4 -> %0d", acc_next);
    end

    acc = 8'd241; a = 4'd15; b = 4'd1; #1;
    if (acc_next !== 8'd0) begin
      $error("15*1+241 expected wrap 0 got %0d", acc_next);
      errors = errors + 1;
    end else begin
      $display("check 15*1+241 wrap -> %0d", acc_next);
    end

    if (errors != 0) begin
      $display("mismatches %0d", errors);
      $finish(1);
    end else begin
      $display("all integer mac vectors matched");
      $finish(0);
    end
  end
endmodule
