// SPDX-License-Identifier: AGPL-3.0-only
// One MAC transaction: load a, b, and Z accumulator; ZMAC; store; done.
// Uses package z_mac (signed 64 x 64 into signed 256) and Euclidean residue.
// One clock. Destination bytes publish only after a full success.

module alapeno_mac
  import alapeno_pkg::*;
(
  input  logic         clk,
  input  logic         rst,
  input  logic         run,
  input  logic         kill,
  input  logic         field_mode,
  input  logic [31:0]  ptr_a,
  input  logic [31:0]  ptr_b,
  input  logic [31:0]  ptr_z,
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

  localparam logic [3:0] S_IDLE = 4'd0;
  localparam logic [3:0] S_RA   = 4'd1;
  localparam logic [3:0] S_CA   = 4'd2;
  localparam logic [3:0] S_RB   = 4'd3;
  localparam logic [3:0] S_CB   = 4'd4;
  localparam logic [3:0] S_RZ   = 4'd5;
  localparam logic [3:0] S_CZ   = 4'd6;
  localparam logic [3:0] S_EX   = 4'd7;
  localparam logic [3:0] S_SH   = 4'd8;
  localparam logic [3:0] S_PUB  = 4'd9;
  localparam logic [3:0] S_BAD  = 4'd10;

  logic [3:0] state;
  logic [63:0] hold_a, hold_b, fres;
  logic signed [255:0] accz, hold_z;
  logic [255:0] beat;
  logic [31:0] ew;
  zadd_t za;
  logic bad_ptr;
  logic [63:0] aval, bval;

  assign ew = field_mode ? 32'd8 : 32'd32;

  always_comb begin
    bad_ptr = 1'b0;
    if (!ptr_align(ptr_a, 32'd8) || !ptr_align(ptr_b, 32'd8) || !ptr_align(ptr_z, 32'd32))
      bad_ptr = 1'b1;
    if (!ptr_align(ptr_c, ew)) bad_ptr = 1'b1;
    if (!bytes_in_sram(ptr_a, 7'd8) || !bytes_in_sram(ptr_b, 7'd8) ||
        !bytes_in_sram(ptr_z, 7'd32) || !bytes_in_sram(ptr_c, ew[6:0]))
      bad_ptr = 1'b1;
  end

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
    if (kill && (state != S_IDLE)) begin
      b_discard = 1'b1;
    end else if (state == S_RA) begin
      b_valid = 1'b1;
      b_addr = ptr_a;
      b_size = 7'd8;
    end else if (state == S_RB) begin
      b_valid = 1'b1;
      b_addr = ptr_b;
      b_size = 7'd8;
    end else if (state == S_RZ) begin
      b_valid = 1'b1;
      b_addr = ptr_z;
      b_size = 7'd32;
    end else if (state == S_SH) begin
      b_valid = 1'b1;
      b_we = 1'b1;
      b_shadow = 1'b1;
      b_addr = ptr_c;
      b_size = ew[6:0];
      b_wdata = beat;
    end else if (state == S_PUB) begin
      b_publish = 1'b1;
      complete = 1'b1;
    end else if (state == S_BAD) begin
      b_discard = 1'b1;
      fail = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      hold_a <= 64'h0;
      hold_b <= 64'h0;
      hold_z <= '0;
      accz <= '0;
      fres <= 64'h0;
      beat <= '0;
    end else if (kill) begin
      state <= S_IDLE;
    end else begin
      case (state)
        S_IDLE: begin
          if (run) begin
            hold_a <= 64'h0;
            hold_b <= 64'h0;
            hold_z <= '0;
            accz <= '0;
            fres <= 64'h0;
            beat <= '0;
            if (bad_ptr) state <= S_BAD;
            else state <= S_RA;
          end
        end
        S_RA: state <= S_CA;
        S_CA: begin
          aval = b_rdata[63:0];
          if (field_mode && (aval >= P)) state <= S_BAD;
          else begin
            hold_a <= aval;
            state <= S_RB;
          end
        end
        S_RB: state <= S_CB;
        S_CB: begin
          bval = b_rdata[63:0];
          if (field_mode && (bval >= P)) state <= S_BAD;
          else begin
            hold_b <= bval;
            state <= S_RZ;
          end
        end
        S_RZ: state <= S_CZ;
        S_CZ: begin
          hold_z <= b_rdata;
          state <= S_EX;
        end
        S_EX: begin
          // ZMAC: acc' = acc + a * b, signed 256-bit, Euclidean residue path for field.
          za = z_mac(hold_z, hold_a, hold_b);
          if (!za.ok) state <= S_BAD;
          else begin
            accz <= za.sum;
            if (field_mode) begin
              fres <= euclid_mod_p(za.sum);
              beat <= {192'h0, euclid_mod_p(za.sum)};
            end else begin
              fres <= 64'h0;
              beat <= za.sum;
            end
            state <= S_SH;
          end
        end
        S_SH: state <= S_PUB;
        S_PUB: state <= S_IDLE;
        S_BAD: state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
