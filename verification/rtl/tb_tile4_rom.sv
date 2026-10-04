// SPDX-License-Identifier: AGPL-3.0-only
// Run the assembled compiler/tile4.s image (verification/rtl/tile4.bin) on alapeno_top.
// tb_tile_top.sv builds a different program (JAL x0,+0x44 at word 0, sixteen HALT
// pads, different registers and poll sequences). That bench is not a run of tile4.s.
// Bytes enter only through rom_load_we/rom_load_addr/rom_load_wdata and are placed
// at byte 0 because alapeno_core resets pc to 32'h0. The file is not patched.
// The 512-byte compare reads dut.u_mem.sram. alapeno_top exports no SRAM data port.
// That read is observation, not a load path. The program itself stores A and B.
// Failures use $fatal. Icarus 12.0: $finish(1) process status 0, $fatal(1) status 1.

`timescale 1ns/1ps

module tb_tile4_rom;
  import alapeno_pkg::*;

  logic        clk, rst, rom_load_we;
  logic [15:0] rom_load_addr;
  logic [7:0]  rom_load_wdata;
  logic [31:0] pc_q, tcause_q, tpc_q;
  logic        halted;

  alapeno_top dut (
    .clk(clk), .rst(rst),
    .rom_load_we(rom_load_we), .rom_load_addr(rom_load_addr), .rom_load_wdata(rom_load_wdata),
    .pc_q(pc_q), .tcause_q(tcause_q), .tpc_q(tpc_q), .halted(halted)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  logic [7:0] img [0:65535];
  logic [63:0] Cknown [0:15];

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic rom_byte(input logic [15:0] addr, input logic [7:0] data);
    begin
      rom_load_we = 1'b1;
      rom_load_addr = addr;
      rom_load_wdata = data;
      tick;
      rom_load_we = 1'b0;
    end
  endtask

  integer fd, nbytes, i, bi, cycles, mism, first_off;
  logic [7:0] expb, gotb;
  logic [255:0] expv, got;

  initial begin
    Cknown[ 0]=64'd18; Cknown[ 1]=64'd18; Cknown[ 2]=64'd12; Cknown[ 3]=64'd16;
    Cknown[ 4]=64'd23; Cknown[ 5]=64'd22; Cknown[ 6]=64'd12; Cknown[ 7]=64'd19;
    Cknown[ 8]=64'd19; Cknown[ 9]=64'd29; Cknown[10]=64'd18; Cknown[11]=64'd29;
    Cknown[12]=64'd6;  Cknown[13]=64'd15; Cknown[14]=64'd10; Cknown[15]=64'd15;

    rom_load_we = 1'b0;
    rom_load_addr = 16'h0;
    rom_load_wdata = 8'h0;
    rst = 1'b1;
    repeat (2) tick;

    fd = $fopen("/workspace/alapeno/verification/rtl/tile4.bin", "rb");
    if (fd == 0) begin
      $display("FAIL could not open tile4.bin");
      $fatal(1, "FAIL");
    end
    nbytes = $fread(img, fd);
    $fclose(fd);
    $display("fread tile4.bin bytes=%0d", nbytes);
    if (nbytes < 4 || (nbytes % 4) != 0 || nbytes > 65536) begin
      $display("FAIL tile4.bin size %0d", nbytes);
      $fatal(1, "FAIL");
    end
    if ({img[3], img[2], img[1], img[0]} !== 32'h59401000) begin
      $display("FAIL tile4.bin word0=%h expected 59401000 (lui x10, 0x1000)",
               {img[3], img[2], img[1], img[0]});
      $fatal(1, "FAIL");
    end

    // Hold reset (core pc stays 0, fetch is gated by rst) and write every
    // byte of the assembled image, unchanged, at ROM address 0 upward.
    for (i = 0; i < nbytes; i = i + 1)
      rom_byte(i[15:0], img[i]);

    for (i = 0; i < nbytes; i = i + 1) begin
      if (dut.u_mem.rom[i[15:0]] !== img[i]) begin
        $display("FAIL rom port byte %0d got %h file %h", i, dut.u_mem.rom[i[15:0]], img[i]);
        $fatal(1, "FAIL");
      end
    end
    $display("loaded tile4.bin unchanged at rom[0] (%0d bytes) word0=%h",
             nbytes, {dut.u_mem.rom[3], dut.u_mem.rom[2], dut.u_mem.rom[1], dut.u_mem.rom[0]});

    if (pc_q !== 32'h0 || tcause_q !== 32'h0) begin
      $display("FAIL reset before release pc=%h tcause=%h", pc_q, tcause_q);
      $fatal(1, "FAIL");
    end
    rst = 1'b0;

    cycles = 0;
    while (cycles < 200000 && halted !== 1'b1 && tcause_q === 32'h0) begin
      tick;
      cycles = cycles + 1;
    end
    $display("stop cycles=%0d pc=%h tcause=%h tpc=%h halted=%b",
             cycles, pc_q, tcause_q, tpc_q, halted);
    $display("OBS accel busy=%b done=%b fault=%b",
             dut.u_accel.busy, dut.u_accel.done_b, dut.u_accel.fault_b);
    $display("OBS dma busy=%b done=%b fault=%b",
             dut.u_dma.busy, dut.u_dma.done_b, dut.u_dma.fault_b);
    if (tcause_q !== 32'h0) begin
      $display("FAIL trap tcause=%0d tpc=%h pc=%h", tcause_q, tpc_q, pc_q);
      $fatal(1, "FAIL");
    end
    if (halted !== 1'b1) begin
      $display("FAIL timeout");
      $fatal(1, "FAIL");
    end

    // 0x10000400 is SRAM index 0x400 (SRAM_LO = 0x10000000). Observation only.
    mism = 0;
    first_off = -1;
    for (i = 0; i < 16; i = i + 1) begin
      expv = {192'h0, Cknown[i]};
      got = '0;
      for (bi = 0; bi < 32; bi = bi + 1) begin
        expb = expv[(bi * 8) +: 8];
        gotb = dut.u_mem.sram[32'h400 + (i * 32) + bi];
        got[(bi * 8) +: 8] = gotb;
        if (gotb !== expb) begin
          if (first_off < 0) begin
            first_off = (i * 32) + bi;
            $display("FAIL first mismatch byte offset %0d (addr %h) expected %h actual %h",
                     first_off, 32'h10000400 + first_off, expb, gotb);
          end
          mism = mism + 1;
        end
      end
      $display("COPY[%0d] expected=%0d (%h) actual=%0d (%h)",
               i, Cknown[i], expv, got[63:0], got);
    end
    if (mism != 0) begin
      $display("FAIL TILE4: %0d of 512 copy bytes mismatched at 0x10000400 (first offset %0d)",
               mism, first_off);
      $fatal(1, "FAIL");
    end
    $display("PASS TILE4 ROM: all 512 copy bytes matched at 0x10000400 (tile4.bin loaded unchanged)");
    $finish(0);
  end

  initial begin
    #5000000;
    $display("FAIL timeout watchdog");
    $fatal(1, "FAIL");
  end
endmodule
