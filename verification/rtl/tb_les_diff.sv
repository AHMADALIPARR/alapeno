// SPDX-License-Identifier: AGPL-3.0-only
// Differential check for TILE.md 4x4x4 non-field MATMUL (Why3 Goal dot4'vc).
// Bound to rtl/matrix/alapeno_matrix.sv module alapeno_matrix
// (rtl/ may still be moving). Not bound to rtl/mac/alapeno_mac.sv (one ZMAC only).
// Ports:
//   reset:     rst -> complete/fail idle (M_IDLE)
//   load:      b_valid+!b_we M_ZA/M_ZB; A at ptr_a+(m*lda)+(k*8), B at ptr_b+(k*ldb)+(n*8)
//   execute:   run with op=AOP_MATMUL, field_mode=0; mul_s64 then z_add into accz
//   store:     M_SH b_we+b_shadow+b_wdata to ptr_c+(m*ldc)+(n*ew), ew=32
//   complete:  M_PUB b_publish+complete
//   fail:      M_BAD b_discard+fail (no publish)
// Overflow: TILE.md section 5. A sum of K signed-64 products stays in
// signed 256 for every K <= 2^129 - 1. This tile has K=4. Legal K is at most 64.
// Cite tile_k4_cannot_overflow (not printed Valid) and tile_overflow_faults_without_write
// for the general rule. Do not fake M_BAD. Do not raise K above 64.

`timescale 1ns/1ps

module tb_les_diff;
  import alapeno_pkg::*;

  logic         clk, rst, run, kill, field_mode;
  logic [31:0]  op, m_dim, n_dim, k_dim;
  logic [31:0]  ptr_a, ptr_b, ptr_c, lda, ldb, ldc;
  logic         b_valid, b_we, b_shadow, b_publish, b_discard;
  logic [31:0]  b_addr;
  logic [6:0]   b_size;
  logic [255:0] b_wdata, b_rdata, b_rdata_q;
  logic         complete, fail;

  logic [7:0] sram   [0:4095];
  logic [7:0] shadow [0:4095];
  logic       dirty  [0:4095];
  integer     bi, si;

  logic         cap_clr;
  logic         saw_complete, saw_fail, saw_publish, saw_discard;

  logic [63:0] Aflat [0:15];
  logic [63:0] Bflat [0:15];
  logic [63:0] Cknown [0:15];

  alapeno_matrix dut (
    .clk(clk), .rst(rst), .run(run), .kill(kill), .field_mode(field_mode),
    .op(op), .m_dim(m_dim), .n_dim(n_dim), .k_dim(k_dim),
    .ptr_a(ptr_a), .ptr_b(ptr_b), .ptr_c(ptr_c),
    .lda(lda), .ldb(ldb), .ldc(ldc),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow),
    .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(b_rdata),
    .complete(complete), .fail(fail)
  );

  assign b_rdata = b_rdata_q;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic logic [11:0] off(input logic [31:0] addr);
    off = addr[11:0];
  endfunction

  task automatic mem_clear;
    integer i;
    begin
      for (i = 0; i < 4096; i = i + 1) begin
        sram[i] = 8'h00;
        shadow[i] = 8'h00;
        dirty[i] = 1'b0;
      end
    end
  endtask

  task automatic sram_put8(input [31:0] addr, input [63:0] val);
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1)
        sram[off(addr) + i[11:0]] = val[(i * 8) +: 8];
    end
  endtask

  function automatic logic [255:0] sram_get32(input [31:0] addr);
    logic [255:0] v;
    integer i;
    begin
      v = '0;
      for (i = 0; i < 32; i = i + 1)
        v[(i * 8) +: 8] = sram[off(addr) + i[11:0]];
      sram_get32 = v;
    end
  endfunction

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  always_ff @(posedge clk) begin
    if (rst) begin
      b_rdata_q <= '0;
      for (si = 0; si < 4096; si = si + 1) dirty[si] <= 1'b0;
    end else begin
      if (b_valid && !b_we && !b_publish && !b_discard) begin
        b_rdata_q <= '0;
        for (bi = 0; bi < 32; bi = bi + 1) begin
          if (bi < b_size)
            b_rdata_q[(bi * 8) +: 8] <= sram[off(b_addr) + bi[11:0]];
        end
      end
      if (b_valid && b_we && b_shadow && !b_discard) begin
        for (bi = 0; bi < 32; bi = bi + 1) begin
          if (bi < b_size) begin
            shadow[off(b_addr) + bi[11:0]] <= b_wdata[(bi * 8) +: 8];
            dirty[off(b_addr) + bi[11:0]] <= 1'b1;
          end
        end
      end
      if (b_discard) begin
        for (si = 0; si < 4096; si = si + 1) dirty[si] <= 1'b0;
      end else if (b_publish) begin
        for (si = 0; si < 4096; si = si + 1) begin
          if (dirty[si]) begin
            sram[si] <= shadow[si];
            dirty[si] <= 1'b0;
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst || cap_clr) begin
      saw_complete <= 1'b0;
      saw_fail <= 1'b0;
      saw_publish <= 1'b0;
      saw_discard <= 1'b0;
    end else begin
      if (complete) saw_complete <= 1'b1;
      if (fail) saw_fail <= 1'b1;
      if (b_publish) saw_publish <= 1'b1;
      if (b_discard) saw_discard <= 1'b0;
    end
  end

  integer cycles, idx, mism;
  logic done_pulse, fail_pulse;
  logic pass_reset, pass_les;
  logic [255:0] got, expv;

  task automatic wait_done_or_fail(input integer maxc);
    begin
      cycles = 0;
      done_pulse = 1'b0;
      fail_pulse = 1'b0;
      while (cycles < maxc && !done_pulse && !fail_pulse) begin
        tick;
        cycles = cycles + 1;
        if (complete) done_pulse = 1'b1;
        if (fail) fail_pulse = 1'b1;
      end
      if (done_pulse || fail_pulse) tick;
      tick;
    end
  endtask

  initial begin
    Aflat[ 0]=64'd2; Aflat[ 1]=64'd4; Aflat[ 2]=64'd0; Aflat[ 3]=64'd0;
    Aflat[ 4]=64'd3; Aflat[ 5]=64'd3; Aflat[ 6]=64'd0; Aflat[ 7]=64'd4;
    Aflat[ 8]=64'd3; Aflat[ 9]=64'd3; Aflat[10]=64'd3; Aflat[11]=64'd2;
    Aflat[12]=64'd2; Aflat[13]=64'd1; Aflat[14]=64'd2; Aflat[15]=64'd0;

    Bflat[ 0]=64'd1; Bflat[ 1]=64'd3; Bflat[ 2]=64'd2; Bflat[ 3]=64'd2;
    Bflat[ 4]=64'd4; Bflat[ 5]=64'd3; Bflat[ 6]=64'd2; Bflat[ 7]=64'd3;
    Bflat[ 8]=64'd0; Bflat[ 9]=64'd3; Bflat[10]=64'd2; Bflat[11]=64'd4;
    Bflat[12]=64'd2; Bflat[13]=64'd1; Bflat[14]=64'd0; Bflat[15]=64'd1;

    Cknown[ 0]=64'd18; Cknown[ 1]=64'd18; Cknown[ 2]=64'd12; Cknown[ 3]=64'd16;
    Cknown[ 4]=64'd23; Cknown[ 5]=64'd22; Cknown[ 6]=64'd12; Cknown[ 7]=64'd19;
    Cknown[ 8]=64'd19; Cknown[ 9]=64'd29; Cknown[10]=64'd18; Cknown[11]=64'd29;
    Cknown[12]=64'd6;  Cknown[13]=64'd15; Cknown[14]=64'd10; Cknown[15]=64'd15;

    pass_reset = 1'b0;
    pass_les = 1'b0;
    run = 1'b0;
    kill = 1'b0;
    field_mode = 1'b0;
    op = 32'h0;
    m_dim = 32'h0; n_dim = 32'h0; k_dim = 32'h0;
    ptr_a = 32'h0; ptr_b = 32'h0; ptr_c = 32'h0;
    lda = 32'h0; ldb = 32'h0; ldc = 32'h0;
    cap_clr = 1'b0;
    mem_clear;

    // ---- 1. Reset ----
    rst = 1'b1;
    repeat (4) tick;
    if (complete !== 1'b0 || fail !== 1'b0 || b_publish !== 1'b0) begin
      $display("FAIL reset: complete=%b fail=%b publish=%b", complete, fail, b_publish);
      $finish(1);
    end
    $display("PASS reset: complete=0 fail=0 publish=0 (idle)");
    pass_reset = 1'b1;
    rst = 1'b0;
    tick;

    // ---- 2. TILE 4x4x4 non-field MATMUL ----
    mem_clear;
    ptr_a = 32'h1000_0000;
    ptr_b = 32'h1000_0080;
    ptr_c = 32'h1000_0100;
    lda = 32'd32;
    ldb = 32'd32;
    ldc = 32'd128;
    for (idx = 0; idx < 16; idx = idx + 1) begin
      sram_put8(ptr_a + (idx * 32'd8), Aflat[idx]);
      sram_put8(ptr_b + (idx * 32'd8), Bflat[idx]);
    end
    op = AOP_MATMUL;
    field_mode = 1'b0;
    m_dim = 32'd4;
    n_dim = 32'd4;
    k_dim = 32'd4;

    cap_clr = 1'b1; tick; cap_clr = 1'b0; tick;
    run = 1'b1; tick; run = 1'b0;
    wait_done_or_fail(5000);

    if (!done_pulse || fail_pulse || !saw_publish || saw_fail) begin
      $display("FAIL LES status: done=%b fail=%b publish=%b saw_fail=%b cycles=%0d",
               done_pulse, fail_pulse, saw_publish, saw_fail, cycles);
      $finish(1);
    end

    mism = 0;
    for (idx = 0; idx < 16; idx = idx + 1) begin
      expv = {192'h0, Cknown[idx]};
      got = sram_get32(ptr_c + (idx * 32'd32));
      $display("C[%0d] expected=%0d (%h) actual=%0d (%h)",
               idx, Cknown[idx], expv, got[63:0], got);
      if (got !== expv) begin
        $display("FAIL LES mismatch at C[%0d]", idx);
        mism = mism + 1;
      end
    end
    if (mism != 0) begin
      $display("FAIL LES: %0d element mismatches", mism);
      $finish(1);
    end
    $display("PASS LES: 4x4x4 non-field MATMUL C bit-exact (TILE known)");
    pass_les = 1'b1;

    // ---- 3. Overflow not reachable on current ports ----
    $display("OVF not a tile stimulus: TILE.md section 5. K signed-64 products stay in signed 256 for K <= 2^129-1. This tile K=4. Legal accelerator K <= 64. Cite tile_k4_cannot_overflow (Why3 did not print it Valid) and tile_overflow_faults_without_write for the general rule. No faked M_BAD. No K above 64.");

    if (pass_reset && pass_les) begin
      $display("all LES differential checks matched (4x4 C; overflow not a legal-K stimulus)");
      $finish(0);
    end
    $display("FAIL aggregate");
    $finish(1);
  end

  initial begin
    #500000;
    $display("FAIL timeout");
    $finish(1);
  end
endmodule
