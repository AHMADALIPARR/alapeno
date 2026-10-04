// SPDX-License-Identifier: AGPL-3.0-only
// ROM (external image) and one SRAM window. Port A is the core. Port B is
// the accelerator and the DMA. Reads return on the following clock. A write
// is visible to a later read. A same-cycle read sees the winning new byte.
// Shadow stores stay invisible until publish, which moves every dirty byte
// in one step. Port A wins a same-byte contest and raises conflict.
// Storage is the first 1536 bytes of the window (indices 0..1535). A higher
// offset misses and does not wrap. 0x10000400 is byte 1024 and still fits.

module alapeno_mem
  import alapeno_pkg::*;
(
  input  logic         clk,
  input  logic         rst,
  input  logic         rom_load_we,
  input  logic [15:0]  rom_load_addr,
  input  logic [7:0]   rom_load_wdata,

  input  logic         a_valid,
  input  logic         a_we,
  input  logic [31:0]  a_addr,
  input  logic [6:0]   a_size,
  input  logic [255:0] a_wdata,
  output logic [255:0] a_rdata,

  input  logic         b_valid,
  input  logic         b_we,
  input  logic         b_shadow,
  input  logic         b_publish,
  input  logic         b_discard,
  input  logic [31:0]  b_addr,
  input  logic [6:0]   b_size,
  input  logic [255:0] b_wdata,
  output logic [255:0] b_rdata,

  output logic         conflict
);

  localparam int SRAM_BYTES = 1536;

  logic [7:0] rom [0:65535];
  logic [7:0] sram [0:SRAM_BYTES-1];
  logic [7:0] shadow [0:SRAM_BYTES-1];
  logic       dirty [0:SRAM_BYTES-1];

  function automatic logic sram_hit(input logic [31:0] a);
    sram_hit = (a[31:19] == 13'h0200);
  endfunction

  function automatic logic sram_stored(input logic [31:0] a);
    sram_stored = sram_hit(a) && (a[18:0] < 19'(SRAM_BYTES));
  endfunction

  function automatic logic [10:0] sram_idx(input logic [31:0] a);
    sram_idx = a[10:0];
  endfunction

  function automatic logic rom_hit(input logic [31:0] a);
    rom_hit = (a[31:16] == 16'h0000);
  endfunction

  function automatic logic range_hit(
    input logic [31:0] addr,
    input logic [31:0] base,
    input logic [6:0] sz
  );
    logic [32:0] endb;
    begin
      endb = {1'b0, base} + {26'b0, sz};
      range_hit = (sz != 7'd0) && (addr >= base) && ({1'b0, addr} < endb);
    end
  endfunction

  function automatic logic [7:0] lane_byte(input logic [255:0] bus, input logic [31:0] addr, input logic [31:0] base);
    logic [31:0] diff;
    begin
      diff = addr - base;
      lane_byte = bus[(diff[4:0] * 8) +: 8];
    end
  endfunction

  function automatic logic [7:0] visible_byte(input logic [31:0] addr);
    logic [7:0] b;
    logic [10:0] ix;
    begin
      b = 8'h00;
      if (rom_hit(addr)) b = rom[addr[15:0]];
      else if (sram_stored(addr)) begin
        ix = sram_idx(addr);
        b = sram[ix];
        if (b_publish && dirty[ix]) b = shadow[ix];
      end
      if (b_valid && b_we && !b_shadow && !b_publish && sram_stored(addr) && range_hit(addr, b_addr, b_size))
        b = lane_byte(b_wdata, addr, b_addr);
      if (a_valid && a_we && sram_stored(addr) && range_hit(addr, a_addr, a_size))
        b = lane_byte(a_wdata, addr, a_addr);
      visible_byte = b;
    end
  endfunction

  integer i;
  integer k;
  logic [31:0] ba, bb;
  logic [10:0] ix;
  logic [255:0] a_next, b_next;
  logic hit_conflict;

  always_ff @(posedge clk) begin
    if (rst) begin
      a_rdata <= '0;
      b_rdata <= '0;
      conflict <= 1'b0;
      a_next = '0;
      b_next = '0;
      hit_conflict = 1'b0;
      for (i = 0; i < SRAM_BYTES; i = i + 1) begin
        sram[i] <= 8'h00;
        shadow[i] <= 8'h00;
        dirty[i] <= 1'b0;
      end
    end else begin
      a_next = '0;
      b_next = '0;
      hit_conflict = 1'b0;
      for (k = 0; k < 32; k = k + 1) begin
        if (k < a_size) a_next[(k * 8) +: 8] = visible_byte(a_addr + k[31:0]);
        if (k < b_size) b_next[(k * 8) +: 8] = visible_byte(b_addr + k[31:0]);
      end
      if (a_valid && a_we && b_valid && b_we && !b_shadow) begin
        for (k = 0; k < 32; k = k + 1) begin
          if (k < a_size) begin
            ba = a_addr + k[31:0];
            if (sram_stored(ba) && range_hit(ba, b_addr, b_size)) hit_conflict = 1'b1;
          end
        end
      end
      if (b_publish && a_valid && a_we) begin
        for (k = 0; k < 32; k = k + 1) begin
          if (k < a_size) begin
            ba = a_addr + k[31:0];
            if (sram_stored(ba) && dirty[sram_idx(ba)]) hit_conflict = 1'b1;
          end
        end
      end
      conflict <= hit_conflict;
      if (a_valid && !a_we) a_rdata <= a_next;
      if (b_valid && !b_we && !b_publish) b_rdata <= b_next;

      if (a_valid && a_we) begin
        for (k = 0; k < 32; k = k + 1) begin
          if (k < a_size) begin
            ba = a_addr + k[31:0];
            if (sram_stored(ba)) sram[sram_idx(ba)] <= a_wdata[(k * 8) +: 8];
          end
        end
      end

      if (b_valid && b_we && b_shadow && !b_publish && !b_discard) begin
        for (k = 0; k < 32; k = k + 1) begin
          if (k < b_size) begin
            bb = b_addr + k[31:0];
            if (sram_stored(bb)) begin
              ix = sram_idx(bb);
              shadow[ix] <= b_wdata[(k * 8) +: 8];
              dirty[ix] <= 1'b1;
            end
          end
        end
      end else if (b_valid && b_we && !b_shadow && !b_publish && !b_discard) begin
        for (k = 0; k < 32; k = k + 1) begin
          if (k < b_size) begin
            bb = b_addr + k[31:0];
            if (sram_stored(bb) && !(a_valid && a_we && range_hit(bb, a_addr, a_size)))
              sram[sram_idx(bb)] <= b_wdata[(k * 8) +: 8];
          end
        end
      end

      if (b_discard) begin
        for (i = 0; i < SRAM_BYTES; i = i + 1) dirty[i] <= 1'b0;
      end else if (b_publish) begin
        for (i = 0; i < SRAM_BYTES; i = i + 1) begin
          if (dirty[i]) begin
            ba = SRAM_LO + i[31:0];
            if (a_valid && a_we && range_hit(ba, a_addr, a_size)) begin
              sram[i] <= lane_byte(a_wdata, ba, a_addr);
            end else begin
              sram[i] <= shadow[i];
            end
            dirty[i] <= 1'b0;
          end
        end
      end
    end
    if (rom_load_we) rom[rom_load_addr] <= rom_load_wdata;
  end

endmodule
