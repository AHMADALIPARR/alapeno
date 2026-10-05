// SPDX-License-Identifier: AGPL-3.0-only
`timescale 1ns/1ps
module tb_mem_equiv;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic rom_load_we = 0;
  logic [15:0] rom_load_addr = 0;
  logic [7:0] rom_load_wdata = 0;
  logic a_valid = 0, a_we = 0, b_valid = 0, b_we = 0;
  logic b_shadow = 0, b_publish = 0, b_discard = 0;
  logic [31:0] a_addr = 0, b_addr = 0;
  logic [6:0] a_size = 0, b_size = 0;
  logic [255:0] a_wdata = 0, b_wdata = 0;
  wire [255:0] a_rdata, b_rdata, ref_a, ref_b;
  wire conflict, ref_conflict;
  alapeno_mem dut (.*);
  mem_reference reference (
    .clk(clk), .rst(rst), .rom_load_we(rom_load_we), .rom_load_addr(rom_load_addr), .rom_load_wdata(rom_load_wdata),
    .a_valid(a_valid), .a_we(a_we), .a_addr(a_addr), .a_size(a_size), .a_wdata(a_wdata), .a_rdata(ref_a),
    .b_valid(b_valid), .b_we(b_we), .b_shadow(b_shadow), .b_publish(b_publish), .b_discard(b_discard),
    .b_addr(b_addr), .b_size(b_size), .b_wdata(b_wdata), .b_rdata(ref_b), .conflict(ref_conflict)
  );
  integer i, j, seed, ignored;
  task automatic tick_and_compare;
    @(posedge clk); #1;
    if (a_rdata !== ref_a || b_rdata !== ref_b || conflict !== ref_conflict)
      $fatal(1, "FAIL MEM bus/conflict at cycle %0d", i);
    for (j = 0; j < 1536; j = j + 1)
      if (dut.sram[j] !== reference.sram[j] || dut.shadow[j] !== reference.shadow[j] ||
          dut.dirty[j] !== reference.dirty[j])
        $fatal(1, "FAIL MEM byte %0d cycle %0d", j, i);
  endtask
  initial begin
    seed = 32'h1a1a9e00; ignored = $urandom(seed); i = 0;
    tick_and_compare(); rst = 0;
    for (i = 0; i < 600; i = i + 1) begin
      a_valid = $urandom; a_we = $urandom; b_valid = $urandom; b_we = $urandom;
      b_shadow = $urandom; b_publish = (i % 7 == 0); b_discard = (i % 11 == 0);
      a_size = $urandom; b_size = $urandom;
      a_addr = 32'h10000000 + $urandom_range(0, 1550);
      b_addr = (i % 2 == 0) ? a_addr + $urandom_range(0, 20) : 32'h10000000 + $urandom_range(0, 1550);
      if (i % 17 == 0) begin a_addr = 32'h0; b_addr = 32'h10000800; end
      if (i % 19 == 0) begin a_addr = 32'h0ffffff8; b_addr = 32'h100005f8; end
      rst = (i % 113 == 112);
      rom_load_we = (i % 3 == 0); rom_load_addr = i; rom_load_wdata = i;
      for (j = 0; j < 8; j = j + 1) begin
        a_wdata[j*32 +: 32] = $urandom; b_wdata[j*32 +: 32] = $urandom;
      end
      tick_and_compare();
    end
    $display("PASS MEM: register storage matches baseline across 600 randomized cycles, all 1536 bytes, reads and conflicts");
    $finish;
  end
  initial begin #100000; $fatal(1, "FAIL MEM timeout"); end
endmodule
