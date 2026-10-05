// SPDX-License-Identifier: AGPL-3.0-only
`timescale 1ns/1ps
module tb_project_capacity;
  import alapeno_pkg::*;
  logic clk = 0, rst = 1, run = 0;
  always #5 clk = ~clk;
  logic [31:0] op = AOP_PROJECT, md = 1, nd = 1, kd = 0;
  logic [31:0] bp = SRAM_LO + 8, cp = SRAM_LO + 16;
  logic valid, we, shadow, publish, discard, complete, fail;
  logic [31:0] addr;
  logic [6:0] size;
  logic [255:0] wdata, rdata, ardata;
  logic av = 0, aw = 0;
  logic [31:0] aa = 0;
  logic [255:0] ad = 0;
  logic conflict;
  alapeno_matrix #(.OBUF_BYTES(512)) dut (
    .clk(clk), .rst(rst), .run(run), .kill(1'b0), .field_mode(1'b0), .op(op),
    .m_dim(md), .n_dim(nd), .k_dim(kd),
    .ptr_a(alapeno_pkg::SRAM_LO), .ptr_b(bp), .ptr_c(cp),
    .lda(32'd32), .ldb(32'd32), .ldc(32'd128),
    .b_valid(valid), .b_we(we), .b_shadow(shadow), .b_publish(publish), .b_discard(discard),
    .b_addr(addr), .b_size(size), .b_wdata(wdata), .b_rdata(rdata), .complete(complete), .fail(fail)
  );
  alapeno_mem mem (
    .clk(clk), .rst(rst), .rom_load_we(1'b0), .rom_load_addr(16'd0), .rom_load_wdata(8'd0),
    .a_valid(av), .a_we(aw), .a_addr(aa), .a_size(7'd8), .a_wdata(ad), .a_rdata(ardata),
    .b_valid(valid), .b_we(we), .b_shadow(shadow), .b_publish(publish), .b_discard(discard),
    .b_addr(addr), .b_size(size), .b_wdata(wdata), .b_rdata(rdata), .conflict(conflict)
  );
  task automatic tick;
    @(posedge clk); #1;
  endtask
  task automatic store(input logic [31:0] address, input logic [63:0] value);
    aa = address; ad = {192'd0, value}; av = 1; aw = 1;
    tick(); av = 0; aw = 0;
  endtask
  function automatic logic [63:0] word_at(input integer offset);
    integer j;
    for (j = 0; j < 8; j = j + 1) word_at[j*8 +: 8] = mem.sram[offset+j];
  endfunction
  task automatic execute(input logic expect_fail);
    integer cycles;
    run = 1; tick(); run = 0;
    cycles = 0;
    while (!complete && !fail && cycles < 200) begin tick(); cycles = cycles + 1; end
    if (cycles == 200 || fail !== expect_fail || complete === expect_fail)
      $fatal(1, "FAIL PROJECT status fail=%b complete=%b expected fail=%b", fail, complete, expect_fail);
    if (expect_fail && (!discard || publish || we)) $fatal(1, "FAIL fault published");
    tick();
  endtask
  initial begin
    tick(); tick(); rst = 0;
    store(alapeno_pkg::SRAM_LO, 10); store(alapeno_pkg::SRAM_LO+8, 3); store(alapeno_pkg::SRAM_LO+16, 2);
    execute(0);
    if (word_at(0) !== 64'd10 || word_at(8) !== 64'd12 || word_at(16) !== 64'd9)
      $fatal(1, "FAIL PROJECT E=%0d P=%0d J=%0d", word_at(0), word_at(8), word_at(16));
    $display("PASS PROJECT: E=10 P=3 J=2 publishes J'=9 and P'=12 with 512-byte buffer");
    // Two rows and columns exercise the compact second-matrix offset,
    // source strides, destination strides, and both publication passes.
    md = 2; nd = 2; bp = alapeno_pkg::SRAM_LO + 64; cp = alapeno_pkg::SRAM_LO + 128;
    store(alapeno_pkg::SRAM_LO, 10); store(alapeno_pkg::SRAM_LO+8, 20);
    store(alapeno_pkg::SRAM_LO+32, 30); store(alapeno_pkg::SRAM_LO+40, 40);
    store(bp, 3); store(bp+8, 4); store(bp+32, 5); store(bp+40, 6);
    store(cp, 2); store(cp+8, 7); store(cp+128, 9); store(cp+136, 11);
    execute(0);
    if (word_at(128) !== 64'd9 || word_at(136) !== 64'd23 ||
        word_at(256) !== 64'd34 || word_at(264) !== 64'd45 ||
        word_at(64) !== 64'd12 || word_at(72) !== 64'd27 ||
        word_at(96) !== 64'd39 || word_at(104) !== 64'd51 ||
        word_at(0) !== 64'd10 || word_at(40) !== 64'd40)
      $fatal(1, "FAIL PROJECT 2x2 results or preserved source");
    $display("PASS PROJECT 2x2: distinct strided matrices publish both compact results");
    md = 1; nd = 1; bp = alapeno_pkg::SRAM_LO + 8; cp = alapeno_pkg::SRAM_LO + 16;
    store(alapeno_pkg::SRAM_LO, 64'h7fffffffffffffff);
    store(alapeno_pkg::SRAM_LO+8, 64'h7fffffffffffffff);
    store(alapeno_pkg::SRAM_LO+16, 64'h7fffffffffffffff);
    execute(1);
    if (word_at(8) !== 64'h7fffffffffffffff || word_at(16) !== 64'h7fffffffffffffff)
      $fatal(1, "FAIL PROJECT overflow changed destinations");
    $display("PASS PROJECT fault: arithmetic overflow discarded both destinations");
    op = AOP_MATMUL; md = 5; nd = 4; kd = 0;
    execute(1);
    if (word_at(8) !== 64'h7fffffffffffffff || word_at(16) !== 64'h7fffffffffffffff)
      $fatal(1, "FAIL capacity changed memory");
    $display("PASS CAPACITY: 640-byte result rejected by 512-byte buffer without publication");
    $finish;
  end
  initial begin #100000; $fatal(1, "FAIL timeout"); end
endmodule
