// SPDX-License-Identifier: AGPL-3.0-only
// Integer ISA, Goldilocks prime, and address windows. No floating point.

package alapeno_pkg;

  localparam logic [63:0] P    = 64'hFFFF_FFFF_0000_0001; // 2^64 - 2^32 + 1
  localparam logic [63:0] HALF = 64'h7FFF_FFFF_8000_0000; // floor(p/2) = 2^63 - 2^31
  localparam int X_COUNT = 32;
  localparam int Z_COUNT = 8;
  localparam logic [31:0] TRAP_PC = 32'h0000_0040;

  localparam logic [31:0] CAUSE_CTRL   = 32'd1;
  localparam logic [31:0] CAUSE_ILL    = 32'd2;
  localparam logic [31:0] CAUSE_PERM   = 32'd3;
  localparam logic [31:0] CAUSE_ALIGN  = 32'd4;
  localparam logic [31:0] CAUSE_ZRANGE = 32'd5;
  localparam logic [31:0] CAUSE_EMPTY  = 32'd6;
  localparam logic [31:0] CAUSE_RED    = 32'd7;
  localparam logic [31:0] CAUSE_ECALL  = 32'd9;

  localparam logic [31:0] ROM_LO   = 32'h0000_0000;
  localparam logic [31:0] ROM_HI   = 32'h0000_FFFF;
  localparam logic [31:0] SRAM_LO  = 32'h1000_0000;
  localparam logic [31:0] SRAM_HI  = 32'h1007_FFFF;
  localparam logic [31:0] SRAM0_HI = 32'h1003_FFFF;
  localparam logic [31:0] ACC_LO   = 32'h2000_0000;
  localparam logic [31:0] ACC_HI   = 32'h2000_0FFF;
  localparam logic [31:0] DMA_LO   = 32'h3000_0000;
  localparam logic [31:0] DMA_HI   = 32'h3000_0FFF;

  localparam logic [5:0] OP_ADD    = 6'h00;
  localparam logic [5:0] OP_SUB    = 6'h01;
  localparam logic [5:0] OP_AND    = 6'h02;
  localparam logic [5:0] OP_OR     = 6'h03;
  localparam logic [5:0] OP_XOR    = 6'h04;
  localparam logic [5:0] OP_SLL    = 6'h05;
  localparam logic [5:0] OP_SRL    = 6'h06;
  localparam logic [5:0] OP_SRA    = 6'h07;
  localparam logic [5:0] OP_SLT    = 6'h08;
  localparam logic [5:0] OP_SLTU   = 6'h09;
  localparam logic [5:0] OP_MULLO  = 6'h0C;
  localparam logic [5:0] OP_MULHI  = 6'h0D;
  localparam logic [5:0] OP_MULUHI = 6'h0E;
  localparam logic [5:0] OP_ADDI   = 6'h10;
  localparam logic [5:0] OP_ANDI   = 6'h11;
  localparam logic [5:0] OP_ORI    = 6'h12;
  localparam logic [5:0] OP_XORI   = 6'h13;
  localparam logic [5:0] OP_SLTI   = 6'h14;
  localparam logic [5:0] OP_SLTIU  = 6'h15;
  localparam logic [5:0] OP_LUI    = 6'h16;
  localparam logic [5:0] OP_Z      = 6'h18;
  localparam logic [5:0] OP_RED    = 6'h19;
  localparam logic [5:0] OP_ZLD    = 6'h1A;
  localparam logic [5:0] OP_ZST    = 6'h1B;
  localparam logic [5:0] OP_LD     = 6'h20;
  localparam logic [5:0] OP_LW     = 6'h21;
  localparam logic [5:0] OP_LH     = 6'h22;
  localparam logic [5:0] OP_LB     = 6'h23;
  localparam logic [5:0] OP_LWU    = 6'h24;
  localparam logic [5:0] OP_LHU    = 6'h25;
  localparam logic [5:0] OP_LBU    = 6'h26;
  localparam logic [5:0] OP_SD     = 6'h28;
  localparam logic [5:0] OP_SW     = 6'h29;
  localparam logic [5:0] OP_SH     = 6'h2A;
  localparam logic [5:0] OP_SB     = 6'h2B;
  localparam logic [5:0] OP_BEQ    = 6'h30;
  localparam logic [5:0] OP_BNE    = 6'h31;
  localparam logic [5:0] OP_BLT    = 6'h32;
  localparam logic [5:0] OP_BGE    = 6'h33;
  localparam logic [5:0] OP_BLTU   = 6'h34;
  localparam logic [5:0] OP_BGEU   = 6'h35;
  localparam logic [5:0] OP_JAL    = 6'h36;
  localparam logic [5:0] OP_JALR   = 6'h37;
  localparam logic [5:0] OP_HALT   = 6'h3E;
  localparam logic [5:0] OP_ECALL  = 6'h3F;

  localparam logic [2:0] Z_CLR  = 3'd0;
  localparam logic [2:0] Z_SEXT = 3'd1;
  localparam logic [2:0] Z_LIMB = 3'd2;
  localparam logic [2:0] Z_FIT  = 3'd3;
  localparam logic [2:0] Z_ADD  = 3'd4;
  localparam logic [2:0] Z_SUB  = 3'd5;
  localparam logic [2:0] Z_MAC  = 3'd6;
  localparam logic [2:0] Z_MODP = 3'd7;

  localparam logic [10:0] RED_SUM  = 11'd0;
  localparam logic [10:0] RED_MIN  = 11'd1;
  localparam logic [10:0] RED_MAX  = 11'd2;
  localparam logic [10:0] RED_MODP = 11'd3;

  localparam logic [31:0] AOP_MATMUL  = 32'd1;
  localparam logic [31:0] AOP_VADD    = 32'd2;
  localparam logic [31:0] AOP_VSUB    = 32'd3;
  localparam logic [31:0] AOP_SUM     = 32'd4;
  localparam logic [31:0] AOP_MIN     = 32'd5;
  localparam logic [31:0] AOP_MAX     = 32'd6;
  localparam logic [31:0] AOP_ROUTE   = 32'd7;
  localparam logic [31:0] AOP_PROJECT = 32'd8;

  typedef struct packed {
    logic        ok;
    logic [63:0] val;
  } s64r_t;

  typedef struct packed {
    logic                ok;
    logic signed [255:0] sum;
  } zadd_t;

  function automatic logic [63:0] sext16(input logic [15:0] imm);
    logic sign;
    begin
      // imm[15] via a logical shift, not a constant select.
      sign = imm >> 15;
      sext16 = {{48{sign}}, imm};
    end
  endfunction

  function automatic logic [63:0] zext16(input logic [15:0] imm);
    zext16 = {48'b0, imm};
  endfunction

  function automatic logic exec_byte(input logic [31:0] a);
    exec_byte = (a <= ROM_HI) || ((a >= SRAM_LO) && (a <= SRAM0_HI));
  endfunction

  function automatic logic fetch_ok(input logic [31:0] pc);
    logic [32:0] b1, b2, b3;
    logic b1_hi, b2_hi, b3_hi;
    logic [31:0] b1_lo, b2_lo, b3_lo;
    begin
      b1 = {1'b0, pc} + 33'd1;
      b2 = {1'b0, pc} + 33'd2;
      b3 = {1'b0, pc} + 33'd3;
      // bN[32] is the carry bit; bN[31:0] is the low word.
      b1_hi = b1 >> 32; b1_lo = b1;
      b2_hi = b2 >> 32; b2_lo = b2;
      b3_hi = b3 >> 32; b3_lo = b3;
      fetch_ok = exec_byte(pc) && (b1_hi == 1'b0) && exec_byte(b1_lo) &&
                 (b2_hi == 1'b0) && exec_byte(b2_lo) &&
                 (b3_hi == 1'b0) && exec_byte(b3_lo);
    end
  endfunction

  function automatic logic bytes_in_rom(input logic [31:0] a, input logic [6:0] n);
    logic [32:0] last;
    logic last_hi;
    logic [31:0] last_lo;
    begin
      if (n == 7'd0) bytes_in_rom = 1'b0;
      else begin
        last = {1'b0, a} + {26'b0, n} - 33'd1;
        last_hi = last >> 32;
        last_lo = last;
        bytes_in_rom = (last_hi == 1'b0) && (a <= ROM_HI) && (last_lo <= ROM_HI);
      end
    end
  endfunction

  function automatic logic bytes_in_sram(input logic [31:0] a, input logic [6:0] n);
    logic [32:0] last;
    logic last_hi;
    logic [31:0] last_lo;
    begin
      if (n == 7'd0) bytes_in_sram = 1'b0;
      else begin
        last = {1'b0, a} + {26'b0, n} - 33'd1;
        last_hi = last >> 32;
        last_lo = last;
        bytes_in_sram = (last_hi == 1'b0) && (a >= SRAM_LO) && (last_lo <= SRAM_HI);
      end
    end
  endfunction

  function automatic logic in_accel_win(input logic [31:0] a);
    in_accel_win = (a >= ACC_LO) && (a <= ACC_HI);
  endfunction

  function automatic logic in_dma_win(input logic [31:0] a);
    in_dma_win = (a >= DMA_LO) && (a <= DMA_HI);
  endfunction

  function automatic logic accel_off_ok(input logic [11:0] off);
    case (off)
      12'h000, 12'h004, 12'h008, 12'h00C,
      12'h010, 12'h014, 12'h018, 12'h01C,
      12'h020, 12'h024, 12'h028, 12'h02C,
      12'h030, 12'h034: accel_off_ok = 1'b1;
      default: accel_off_ok = 1'b0;
    endcase
  endfunction

  function automatic logic dma_off_ok(input logic [11:0] off);
    case (off)
      12'h000, 12'h004, 12'h008, 12'h00C, 12'h010: dma_off_ok = 1'b1;
      default: dma_off_ok = 1'b0;
    endcase
  endfunction

  function automatic logic aligned(input logic [31:0] a, input logic [6:0] n);
    logic a0;
    logic [1:0] a10;
    logic [2:0] a20;
    logic [4:0] a40;
    begin
      // Truncation keeps the low bits: a[0], a[1:0], a[2:0], a[4:0].
      a0 = a;
      a10 = a;
      a20 = a;
      a40 = a;
      if (n == 7'd1) aligned = 1'b1;
      else if (n == 7'd2) aligned = (a0 == 1'b0);
      else if (n == 7'd4) aligned = (a10 == 2'b00);
      else if (n == 7'd8) aligned = (a20 == 3'b000);
      else if (n == 7'd32) aligned = (a40 == 5'b00000);
      else aligned = 1'b0;
    end
  endfunction

  function automatic logic [63:0] field_add(input logic [63:0] a, input logic [63:0] b);
    logic [64:0] s;
    logic [63:0] slo;
    begin
      s = {1'b0, a} + {1'b0, b};
      slo = s;
      if (s >= {1'b0, P}) field_add = slo - P;
      else field_add = slo;
    end
  endfunction

  function automatic logic [63:0] field_sub(input logic [63:0] a, input logic [63:0] b);
    logic signed [65:0] d;
    begin
      d = $signed({2'b0, a}) - $signed({2'b0, b});
      if (d < 0) field_sub = d[63:0] + P;
      else field_sub = d[63:0];
    end
  endfunction

  function automatic logic center_le_zero(input logic [63:0] r);
    center_le_zero = (r == 64'h0) || (r > HALF);
  endfunction

  function automatic logic center_less(input logic [63:0] a, input logic [63:0] b);
    logic a_neg, b_neg;
    begin
      a_neg = a > HALF;
      b_neg = b > HALF;
      if (a_neg && !b_neg) center_less = 1'b1;
      else if (!a_neg && b_neg) center_less = 1'b0;
      else center_less = (a < b);
    end
  endfunction

  function automatic s64r_t s64_add(input logic [63:0] a, input logic [63:0] b);
    logic [64:0] w;
    begin
      w = {a[63], a} + {b[63], b};
      s64_add.val = w[63:0];
      s64_add.ok = (w[64] == w[63]);
    end
  endfunction

  function automatic s64r_t s64_sub(input logic [63:0] a, input logic [63:0] b);
    logic [64:0] w;
    begin
      w = {a[63], a} - {b[63], b};
      s64_sub.val = w[63:0];
      s64_sub.ok = (w[64] == w[63]);
    end
  endfunction

  function automatic zadd_t z_add(input logic signed [255:0] a, input logic signed [255:0] b);
    logic signed [256:0] w;
    logic a_sign, b_sign, w_ext, w_sign, ok;
    logic signed [255:0] sum;
    begin
      a_sign = a >> 255;
      b_sign = b >> 255;
      w = {a_sign, a} + {b_sign, b};
      sum = w;
      w_ext = w >> 256;
      w_sign = w >> 255;
      ok = (w_ext == w_sign);
      z_add = {ok, sum};
    end
  endfunction

  function automatic zadd_t z_sub(input logic signed [255:0] a, input logic signed [255:0] b);
    logic signed [256:0] w;
    logic a_sign, b_sign, w_ext, w_sign, ok;
    logic signed [255:0] sum;
    begin
      a_sign = a >> 255;
      b_sign = b >> 255;
      w = {a_sign, a} - {b_sign, b};
      sum = w;
      w_ext = w >> 256;
      w_sign = w >> 255;
      ok = (w_ext == w_sign);
      z_sub = {ok, sum};
    end
  endfunction

  function automatic logic zadd_ok(input zadd_t z);
    logic [256:0] bits;
    begin
      bits = z;
      zadd_ok = bits >> 256;
    end
  endfunction

  function automatic logic signed [255:0] zadd_sum(input zadd_t z);
    begin
      zadd_sum = z;
    end
  endfunction

  function automatic logic z_fit64(input logic signed [255:0] z);
    logic z63;
    logic [191:0] zhi;
    begin
      z63 = z >> 63;
      zhi = z >> 64;
      if (z63) z_fit64 = (zhi == {192{1'b1}});
      else z_fit64 = (zhi == {192{1'b0}});
    end
  endfunction

  function automatic logic signed [127:0] mul_s64(input logic [63:0] a, input logic [63:0] b);
    logic a_sign, b_sign;
    logic signed [127:0] as, bs;
    begin
      a_sign = a >> 63;
      b_sign = b >> 63;
      as = {{64{a_sign}}, a};
      bs = {{64{b_sign}}, b};
      mul_s64 = as * bs;
    end
  endfunction

  function automatic logic [127:0] mul_u64(input logic [63:0] a, input logic [63:0] b);
    mul_u64 = {64'b0, a} * {64'b0, b};
  endfunction

  function automatic zadd_t z_mac(input logic signed [255:0] acc, input logic [63:0] a, input logic [63:0] b);
    logic signed [127:0] prod;
    logic prod_sign;
    logic signed [255:0] wide;
    begin
      prod = mul_s64(a, b);
      prod_sign = prod >> 127;
      wide = {{128{prod_sign}}, prod};
      z_mac = z_add(acc, wide);
    end
  endfunction

  // Euclidean residue of a signed 256-bit integer modulo p, in [0, p).
  // Limbs L0..L3 are the little-endian two's-complement words.
  // Goldilocks: 2^64 ≡ 2^32-1, so 2^128 ≡ -2^32, 2^192 ≡ 1, 2^256 ≡ 2^32-1.
  // z ≡ L0 + L1*(2^32-1) + L2*(-2^32) + L3 - sign*(2^32-1)  (mod p),
  // where sign is bit 255 because a negative encoding is the unsigned
  // bit pattern minus 2^256. The representative is then brought into
  // [0, p) by adding (2^32+1)*p when negative and subtracting shifted
  // copies of p. The remainder is never negative.
  function automatic logic [63:0] euclid_mod_p(input logic signed [255:0] z);
    logic [63:0] limb0, limb1, limb2, limb3;
    logic signed [191:0] acc;
    logic [191:0] rem;
    logic [191:0] pk;
    integer sh;
    begin
      limb0 = z;
      limb1 = z >> 64;
      limb2 = z >> 128;
      limb3 = z >> 192;
      acc = {{128{1'b0}}, limb0};
      acc = acc + {{128{1'b0}}, limb1} * 192'd4294967295;
      acc = acc - {{128{1'b0}}, limb2} * 192'd4294967296;
      acc = acc + {{128{1'b0}}, limb3};
      if ((z >> 255) != 0) acc = acc - 192'd4294967295;
      if (acc < 0) acc = acc + $signed(192'd4294967297 * {{128{1'b0}}, P});
      rem = acc;
      for (sh = 40; sh >= 0; sh = sh - 1) begin
        pk = {{128{1'b0}}, P} << sh;
        if (rem >= pk) rem = rem - pk;
      end
      euclid_mod_p = rem;
    end
  endfunction

  function automatic logic ranges_overlap(
    input logic [31:0] a, input logic [31:0] alen,
    input logic [31:0] b, input logic [31:0] blen
  );
    logic [32:0] aend, bend;
    begin
      aend = {1'b0, a} + {1'b0, alen};
      bend = {1'b0, b} + {1'b0, blen};
      ranges_overlap = (alen != 32'h0) && (blen != 32'h0) &&
                       ({1'b0, a} < bend) && ({1'b0, b} < aend);
    end
  endfunction

  function automatic logic geom_hits(
    input logic [31:0] dma_base, input logic [31:0] dma_len,
    input logic valid,
    input logic [31:0] base, input logic [31:0] stride,
    input logic [31:0] rows, input logic [31:0] cols,
    input logic [31:0] ew
  );
    integer r;
    logic [63:0] rowb, rowl;
    logic hit;
    begin
      hit = 1'b0;
      if (valid && (rows != 32'h0) && (cols != 32'h0) && (ew != 32'h0) && (dma_len != 32'h0)) begin
        for (r = 0; r < 64; r = r + 1) begin
          if (r < rows) begin
            rowb = {32'b0, base} + (r * {32'b0, stride});
            rowl = {32'b0, cols} * {32'b0, ew};
            if (((rowb >> 32) != 32'h0) || ((rowb + rowl) > 64'h0000_0001_0000_0000)) hit = 1'b1;
            else if (ranges_overlap(dma_base, dma_len, rowb, rowl)) hit = 1'b1;
          end
        end
      end
      geom_hits = hit;
    end
  endfunction

  function automatic logic geom_pair_overlap(
    input logic [31:0] a_base, input logic [31:0] a_stride,
    input logic [31:0] a_rows, input logic [31:0] a_cols, input logic [31:0] a_ew,
    input logic [31:0] b_base, input logic [31:0] b_stride,
    input logic [31:0] b_rows, input logic [31:0] b_cols, input logic [31:0] b_ew
  );
    integer ra, rb;
    logic [63:0] ab, al, bb, bl;
    logic hit;
    begin
      hit = 1'b0;
      if ((a_rows != 0) && (a_cols != 0) && (b_rows != 0) && (b_cols != 0)) begin
        for (ra = 0; ra < 64; ra = ra + 1) begin
          if (ra < a_rows) begin
            ab = {32'b0, a_base} + (ra * {32'b0, a_stride});
            al = {32'b0, a_cols} * {32'b0, a_ew};
            for (rb = 0; rb < 64; rb = rb + 1) begin
              if (rb < b_rows) begin
                bb = {32'b0, b_base} + (rb * {32'b0, b_stride});
                bl = {32'b0, b_cols} * {32'b0, b_ew};
                if (((ab >> 32) == 0) && ((bb >> 32) == 0) &&
                    ((ab + al) <= 64'h0000_0001_0000_0000) &&
                    ((bb + bl) <= 64'h0000_0001_0000_0000)) begin
                  if (ranges_overlap(ab, al, bb, bl)) hit = 1'b1;
                end else hit = 1'b1;
              end
            end
          end
        end
      end
      geom_pair_overlap = hit;
    end
  endfunction

  function automatic logic rect_in_sram(
    input logic [31:0] base, input logic [31:0] stride,
    input logic [31:0] rows, input logic [31:0] cols, input logic [31:0] ew
  );
    integer r, c;
    logic [63:0] ea, last;
    logic ok;
    begin
      ok = 1'b1;
      for (r = 0; r < 64; r = r + 1) begin
        if (r < rows) begin
          for (c = 0; c < 64; c = c + 1) begin
            if (c < cols) begin
              ea = {32'b0, base} + (r * {32'b0, stride}) + (c * {32'b0, ew});
              last = ea + {32'b0, ew} - 64'd1;
              if (((ea >> 32) != 0) || ((last >> 32) != 0) ||
                  (ea < {32'h0, SRAM_LO}) || (last > {32'h0, SRAM_HI})) ok = 1'b0;
              if ((ew == 32'd32) && ((ea & 64'h1F) != 64'h0)) ok = 1'b0;
              if ((ew == 32'd8) && ((ea & 64'h7) != 64'h0)) ok = 1'b0;
            end
          end
        end
      end
      rect_in_sram = ok;
    end
  endfunction

  function automatic logic stride_ok(input logic [31:0] stride, input logic [31:0] cols, input logic [31:0] ew);
    logic [63:0] need;
    begin
      need = {32'b0, cols} * {32'b0, ew};
      if (ew == 32'd32) stride_ok = ((stride & 32'h1F) == 32'h0) && ({32'b0, stride} >= need);
      else if (ew == 32'd8) stride_ok = ((stride & 32'h7) == 32'h0) && ({32'b0, stride} >= need);
      else stride_ok = 1'b0;
    end
  endfunction

  function automatic logic ptr_align(input logic [31:0] ptr, input logic [31:0] ew);
    begin
      if (ew == 32'd32) ptr_align = ((ptr & 32'h1F) == 32'h0);
      else ptr_align = ((ptr & 32'h7) == 32'h0);
    end
  endfunction

endpackage
