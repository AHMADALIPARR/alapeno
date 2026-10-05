// SPDX-License-Identifier: AGPL-3.0-only
`timescale 1ns/1ps
module tb_tile_gate;
  logic clk = 0, rst = 1, start = 0;
  always #5 clk = ~clk;
  wire [31:0] status, gs, addr, ga;
  wire valid, we, shadow, publish, discard, gv, gw, gh, gp, gd;
  wire [6:0] size, gz;
  wire [255:0] data, gdata;
  logic [255:0] read_data = 0;
  alapeno_tile_ctrl rtl (
    .clk(clk), .rst(rst), .start(start), .status(status),
    .b_valid(valid), .b_we(we), .b_shadow(shadow), .b_publish(publish), .b_discard(discard),
    .b_addr(addr), .b_size(size), .b_wdata(data), .b_rdata(read_data)
  );
  alapeno_tile_ctrl_synth gate (
    .clk(clk), .rst(rst), .start(start), .status(gs),
    .b_valid(gv), .b_we(gw), .b_shadow(gh), .b_publish(gp), .b_discard(gd),
    .b_addr(ga), .b_size(gz), .b_wdata(gdata), .b_rdata(read_data)
  );
  logic [63:0] a[0:15], b[0:15], expected[0:15];
  logic [255:0] result[0:15];
  integer i, index, writes = 0, cycles = 0;
  logic saw_publish = 0;
  always @(posedge clk) begin
    if (!rst) begin
      if (valid && !we) begin
        if (addr < 32'h10000080) read_data <= {192'd0, a[(addr-32'h10000000)/8]};
        else read_data <= {192'd0, b[(addr-32'h10000080)/8]};
      end
      if (valid && we) begin
        if (!shadow || size != 32) $fatal(1, "FAIL GATE unexpected destination beat");
        index = (addr - 32'h10000100) / 32;
        if (index < 0 || index >= 16) $fatal(1, "FAIL GATE destination index");
        result[index] = data; writes = writes + 1;
      end
      if (publish) saw_publish = 1;
    end
    #1;
    if ({status,valid,we,shadow,publish,discard,addr,size,data} !==
        {gs,gv,gw,gh,gp,gd,ga,gz,gdata})
      $fatal(1, "FAIL GATE RTL/netlist interface mismatch at cycle %0d", cycles);
    cycles = cycles + 1;
  end
  initial begin
    a[0]=1; a[1]=2; a[2]=0; a[3]=1;
    a[4]=3; a[5]=1; a[6]=2; a[7]=0;
    a[8]=0; a[9]=1; a[10]=4; a[11]=2;
    a[12]=2; a[13]=0; a[14]=1; a[15]=1;
    b[0]=2; b[1]=1; b[2]=0; b[3]=3;
    b[4]=4; b[5]=2; b[6]=1; b[7]=0;
    b[8]=1; b[9]=3; b[10]=2; b[11]=1;
    b[12]=0; b[13]=1; b[14]=4; b[15]=2;
    // Compute an independent exact integer reference for these bounded inputs.
    for (i = 0; i < 16; i = i + 1) begin
      expected[i] = a[(i/4)*4]*b[i%4] + a[(i/4)*4+1]*b[4+i%4] +
                    a[(i/4)*4+2]*b[8+i%4] + a[(i/4)*4+3]*b[12+i%4];
      result[i] = 0;
    end
    repeat (2) begin @(posedge clk); #2; end
    rst = 0; start = 1; @(posedge clk); #2; start = 0;
    while (!status[1] && cycles < 2000) begin @(posedge clk); #2; end
    if (!status[1] || status[2] || !saw_publish || writes != 16)
      $fatal(1, "FAIL GATE completion status=%h writes=%0d publish=%b", status, writes, saw_publish);
    for (i = 0; i < 16; i = i + 1)
      if (result[i] !== {192'd0, expected[i]}) $fatal(1, "FAIL GATE C[%0d]", i);
    $display("PASS GATE TILE: synthesized netlist matches RTL every cycle and all 512 result bytes match integer reference");
    $finish;
  end
endmodule
