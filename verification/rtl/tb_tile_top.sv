// SPDX-License-Identifier: AGPL-3.0-only
// Integrated TILE.md 4x4x4 non-field MATMUL through alapeno_top.
// Program bytes enter only on rom_load_we/addr/wdata.
// Scalar SD writes A and B. SW writes the frozen MMIO command.
// LWU polls accelerator STATUS at 0x20000004 and DMA status at 0x30000010
// (alapeno_dma.sv: {conflict,fault,done,busy} is MMIO 0x10; CTRL start is 0x0C bit0).
// Completion required: busy=0, done=1, fault=0, i.e. (status & 7) == 2.
// The 512-byte compare reads alapeno_top.u_mem.sram, the SRAM the DMA writes.
// alapeno_top does not export an SRAM data port. That read is observation, not a load path.
// Failures use $fatal. Icarus 12.0: $finish(1) process status 0, $fatal(1) process status 1.

`timescale 1ns/1ps

module tb_tile_top;
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

  logic [31:0] prog [0:255];
  integer wptr;
  logic [63:0] Aflat [0:15];
  logic [63:0] Bflat [0:15];
  logic [63:0] Cknown [0:15];

  function automatic logic [31:0] enc(
    input logic [5:0] opc,
    input logic [4:0] f_a,
    input logic [4:0] f_b,
    input logic [15:0] imm
  );
    enc = {opc, f_a, f_b, imm};
  endfunction

  task automatic emit(input logic [31:0] w);
    begin
      if (wptr > 255) begin
        $display("FAIL program image overflow");
        $fatal(1, "FAIL");
      end
      prog[wptr] = w;
      wptr = wptr + 1;
    end
  endtask

  // Poll (status & 7) == 2. Fault or idle-without-done executes HALT.
  // Still-busy branches back to the LWU.
  task automatic emit_poll(input logic [4:0] base, input logic [15:0] off);
    begin
      emit(enc(OP_LWU, 5'd5, base, off));
      emit(enc(OP_ANDI, 5'd6, 5'd5, 16'd7));
      emit(enc(OP_ADDI, 5'd7, 5'd0, 16'd2));
      emit(enc(OP_BEQ, 5'd6, 5'd7, 16'd16));
      emit(enc(OP_ANDI, 5'd6, 5'd5, 16'd1));
      emit(enc(OP_BNE, 5'd6, 5'd0, 16'hFFEC));
      emit({OP_HALT, 26'h0});
    end
  endtask

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

  integer i, ai, bi, mism, cycles;
  logic [15:0] soff;
  logic [255:0] expv, got;
  logic [31:0] word;

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

    for (i = 0; i < 256; i = i + 1)
      prog[i] = {OP_HALT, 26'h0};
    // Final word at 0 is JAL x0, +0x44. A one-byte patch turns a JAL +0 spin into this.
    prog[0] = enc(OP_JAL, 5'd0, 5'd0, 16'h0044);
    wptr = 17;

    emit(enc(OP_LUI, 5'd1, 5'd0, 16'h1000));
    emit(enc(OP_LUI, 5'd4, 5'd0, 16'h2000));
    emit(enc(OP_LUI, 5'd8, 5'd0, 16'h3000));
    for (ai = 0; ai < 16; ai = ai + 1) begin
      soff = ai[15:0] * 16'd8;
      emit(enc(OP_ADDI, 5'd2, 5'd0, Aflat[ai][15:0]));
      emit(enc(OP_SD, 5'd2, 5'd1, soff));
    end
    for (bi = 0; bi < 16; bi = bi + 1) begin
      soff = 16'h0080 + (bi[15:0] * 16'd8);
      emit(enc(OP_ADDI, 5'd2, 5'd0, Bflat[bi][15:0]));
      emit(enc(OP_SD, 5'd2, 5'd1, soff));
    end
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd1));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0008));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd4));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h000C));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0010));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0014));
    emit(enc(OP_SW, 5'd1, 5'd4, 16'h0018));
    emit(enc(OP_ADDI, 5'd2, 5'd1, 16'h0080));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h001C));
    emit(enc(OP_ADDI, 5'd2, 5'd1, 16'h0100));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0020));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd32));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0024));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0028));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd128));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h002C));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd0));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0034));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd1));
    emit(enc(OP_SW, 5'd2, 5'd4, 16'h0000));
    emit_poll(5'd4, 16'h0004);
    emit(enc(OP_ADDI, 5'd2, 5'd1, 16'h0100));
    emit(enc(OP_SW, 5'd2, 5'd8, 16'h0000));
    emit(enc(OP_ADDI, 5'd2, 5'd1, 16'h0400));
    emit(enc(OP_SW, 5'd2, 5'd8, 16'h0004));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd512));
    emit(enc(OP_SW, 5'd2, 5'd8, 16'h0008));
    emit(enc(OP_ADDI, 5'd2, 5'd0, 16'd1));
    emit(enc(OP_SW, 5'd2, 5'd8, 16'h000C));
    emit_poll(5'd8, 16'h0010);
    emit({OP_HALT, 26'h0});

    $display("program words=%0d entry=%h spin=%h", wptr, prog[0], 32'hD800_0000);

    rom_load_we = 1'b0;
    rom_load_addr = 16'h0;
    rom_load_wdata = 8'h0;
    rst = 1'b1;
    // One instruction, JAL x0, +0, so the core spins at pc=0 while the image loads.
    // Differs from prog[0] only in byte 0 (0x00 vs 0x44), so the later patch is one byte.
    rom_byte(16'h0000, 8'h00);
    rom_byte(16'h0001, 8'h00);
    rom_byte(16'h0002, 8'h00);
    rom_byte(16'h0003, 8'hD8);
    rst = 1'b0;
    repeat (4) tick;
    if (pc_q !== 32'h0 || tcause_q !== 32'h0 || halted !== 1'b0) begin
      $display("FAIL spin: pc=%h tcause=%h halted=%b", pc_q, tcause_q, halted);
      $fatal(1, "FAIL");
    end
    $display("PASS spin: pc=0 tcause=0 halted=0 while ROM image loads");

    for (i = 1; i < wptr; i = i + 1) begin
      word = prog[i];
      rom_byte(i[15:0] * 16'd4, word[7:0]);
      rom_byte(i[15:0] * 16'd4 + 16'd1, word[15:8]);
      rom_byte(i[15:0] * 16'd4 + 16'd2, word[23:16]);
      rom_byte(i[15:0] * 16'd4 + 16'd3, word[31:24]);
    end
    if (pc_q !== 32'h0 || tcause_q !== 32'h0 || halted !== 1'b0) begin
      $display("FAIL still spinning: pc=%h tcause=%h halted=%b", pc_q, tcause_q, halted);
      $fatal(1, "FAIL");
    end
    rom_byte(16'h0000, prog[0][7:0]);
    $display("patched rom[0] to %h (JAL x0, +0x44)", prog[0]);

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

    mism = 0;
    for (i = 0; i < 16; i = i + 1) begin
      expv = {192'h0, Cknown[i]};
      got = '0;
      for (bi = 0; bi < 32; bi = bi + 1)
        got[(bi * 8) +: 8] = dut.u_mem.sram[32'h400 + (i * 32) + bi];
      $display("COPY[%0d] expected=%0d (%h) actual=%0d (%h)",
               i, Cknown[i], expv, got[63:0], got);
      if (got !== expv) begin
        $display("FAIL COPY mismatch at element %0d", i);
        mism = mism + 1;
      end
    end
    if (mism != 0) begin
      $display("FAIL TILE: %0d of 16 elements mismatched (512 bytes at 0x10000400)", mism);
      $fatal(1, "FAIL");
    end
    $display("PASS TILE: all 512 copy bytes matched at 0x10000400");
    $finish(0);
  end

  initial begin
    #5000000;
    $display("FAIL timeout watchdog");
    $fatal(1, "FAIL");
  end
endmodule
