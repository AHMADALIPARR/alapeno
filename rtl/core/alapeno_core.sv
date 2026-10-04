// SPDX-License-Identifier: AGPL-3.0-only
// Multi-cycle integer core. Opcode is instr[31:26]. ZMAC is op 0x18, funct3 6.

module alapeno_core
  import alapeno_pkg::*;
(
  input  logic         clk,
  input  logic         rst,
  output logic         a_valid,
  output logic         a_we,
  output logic [31:0]  a_addr,
  output logic [6:0]   a_size,
  output logic [255:0] a_wdata,
  input  logic [255:0] a_rdata,
  output logic         acc_rd,
  output logic         acc_wr,
  output logic [11:0]  acc_addr,
  output logic [31:0]  acc_wdata,
  input  logic [31:0]  acc_rdata,
  output logic         dma_rd,
  output logic         dma_wr,
  output logic [11:0]  dma_addr,
  output logic [31:0]  dma_wdata,
  input  logic [31:0]  dma_rdata,
  output logic [31:0]  pc_q,
  output logic [31:0]  tcause_q,
  output logic [31:0]  tpc_q,
  output logic         halted
);

  localparam logic [2:0] ST_FETCH = 3'd0;
  localparam logic [2:0] ST_EXEC  = 3'd1;
  localparam logic [2:0] ST_WB    = 3'd2;
  localparam logic [2:0] ST_RRD   = 3'd3;
  localparam logic [2:0] ST_RWB   = 3'd4;
  localparam logic [2:0] ST_HALT  = 3'd5;

  logic [31:0] pc;
  logic [63:0] xr [0:31];
  logic signed [255:0] zr [0:7];
  logic [31:0] tcause, tpc;
  logic [2:0] state;

  logic [5:0]  ld_op;
  logic [4:0]  ld_rd;
  logic        ld_mmio, ld_dma, ld_z;
  logic [31:0] red_base;
  logic [63:0] red_len;
  logic [31:0] red_idx;
  logic [4:0]  red_zd;
  logic [10:0] red_funct;
  logic signed [255:0] red_acc;
  logic [63:0] red_res, red_cur;

  function automatic logic [63:0] xrd(input logic [4:0] idx);
    if (idx == 5'd0) xrd = 64'h0;
    else xrd = xr[idx];
  endfunction

  function automatic logic [63:0] fmt_load(input logic [5:0] op, input logic [255:0] raw);
    begin
      if (op == OP_LD) fmt_load = raw[63:0];
      else if (op == OP_LW) fmt_load = {{32{raw[31]}}, raw[31:0]};
      else if (op == OP_LH) fmt_load = {{48{raw[15]}}, raw[15:0]};
      else if (op == OP_LB) fmt_load = {{56{raw[7]}}, raw[7:0]};
      else if (op == OP_LWU) fmt_load = {32'h0, raw[31:0]};
      else if (op == OP_LHU) fmt_load = {48'h0, raw[15:0]};
      else fmt_load = {56'h0, raw[7:0]};
    end
  endfunction

  logic trap;
  logic [31:0] tcause_c;
  logic pc_we;
  logic [31:0] pc_next;
  logic x_we, z_we;
  logic [4:0] x_wa, z_wa;
  logic [63:0] x_wd;
  logic signed [255:0] z_wd;
  logic [2:0] next_state;
  logic arm_red, red_step;
  logic [31:0] arm_base;
  logic [63:0] arm_len;
  logic [4:0] arm_zd;
  logic [10:0] arm_funct;
  logic save_ld;
  logic [5:0] save_op;
  logic [4:0] save_rd;
  logic save_mmio, save_dma, save_z;
  logic signed [255:0] red_acc_n;
  logic [63:0] red_res_n, red_cur_n;

  logic [31:0] instr;
  logic [5:0] op;
  logic [4:0] i25, i20, i15;
  logic [10:0] funct;
  logic [15:0] imm;
  logic [2:0] f3;
  logic [7:0] zlo;
  logic [63:0] sum, xv, yv, rs_b, rs_s;
  logic [31:0] phys;
  logic [6:0] sz;
  logic signed [33:0] t34;
  logic [31:0] tgt;
  logic taken;
  logic [66:0] nbytes, end_m;
  logic span_ok;
  zadd_t za;
  logic [63:0] elem, chosen, res_n;
  logic [63:0] link;
  logic [63:0] r25, r20, r15, modv;
  logic signed [127:0] sp128;
  logic [127:0] up128;

  always_comb begin
    trap = 1'b0;
    tcause_c = 32'h0;
    pc_we = 1'b0;
    pc_next = pc;
    x_we = 1'b0;
    z_we = 1'b0;
    x_wa = 5'd0;
    z_wa = 5'd0;
    x_wd = 64'h0;
    z_wd = '0;
    a_valid = 1'b0;
    a_we = 1'b0;
    a_addr = 32'h0;
    a_size = 7'd0;
    a_wdata = '0;
    acc_rd = 1'b0;
    acc_wr = 1'b0;
    acc_addr = 12'h0;
    acc_wdata = 32'h0;
    dma_rd = 1'b0;
    dma_wr = 1'b0;
    dma_addr = 12'h0;
    dma_wdata = 32'h0;
    next_state = state;
    arm_red = 1'b0;
    red_step = 1'b0;
    arm_base = 32'h0;
    arm_len = 64'h0;
    arm_zd = 5'd0;
    arm_funct = 11'h0;
    save_ld = 1'b0;
    save_op = 6'h0;
    save_rd = 5'd0;
    save_mmio = 1'b0;
    save_dma = 1'b0;
    save_z = 1'b0;
    red_acc_n = red_acc;
    red_res_n = red_res;
    red_cur_n = red_cur;
    instr = a_rdata[31:0];
    op = instr[31:26];
    i25 = instr[25:21];
    i20 = instr[20:16];
    i15 = instr[15:11];
    funct = instr[10:0];
    imm = instr[15:0];
    f3 = instr[10:8];
    zlo = instr[7:0];
    sum = 64'h0;
    phys = 32'h0;
    sz = 7'd0;
    t34 = '0;
    tgt = 32'h0;
    taken = 1'b0;
    nbytes = '0;
    end_m = '0;
    span_ok = 1'b0;
    za = '0;
    elem = 64'h0;
    chosen = 64'h0;
    res_n = 64'h0;
    link = {32'h0, pc + 32'd4};
    r25 = xrd(i25);
    r20 = xrd(i20);
    r15 = xrd(i15);
    sp128 = mul_s64(r20, r15);
    up128 = mul_u64(r20, r15);
    modv = 64'h0;

    if (!rst) begin
      case (state)
        ST_FETCH: begin
          if (pc[1:0] != 2'b00) begin
            trap = 1'b1;
            tcause_c = CAUSE_CTRL;
          end else if (!fetch_ok(pc)) begin
            trap = 1'b1;
            tcause_c = CAUSE_PERM;
          end else begin
            a_valid = 1'b1;
            a_addr = pc;
            a_size = 7'd4;
            next_state = ST_EXEC;
          end
        end
        ST_HALT: next_state = ST_HALT;
        ST_WB: begin
          if (ld_z) begin
            z_we = 1'b1;
            z_wa = ld_rd;
            z_wd = a_rdata;
          end else if (ld_mmio) begin
            x_we = 1'b1;
            x_wa = ld_rd;
            if (ld_op == OP_LW)
              x_wd = ld_dma ? {{32{dma_rdata[31]}}, dma_rdata} : {{32{acc_rdata[31]}}, acc_rdata};
            else
              x_wd = ld_dma ? {32'h0, dma_rdata} : {32'h0, acc_rdata};
          end else begin
            x_we = 1'b1;
            x_wa = ld_rd;
            x_wd = fmt_load(ld_op, a_rdata);
          end
          pc_we = 1'b1;
          pc_next = pc + 32'd4;
          next_state = ST_FETCH;
        end
        ST_RRD: begin
          a_valid = 1'b1;
          a_we = 1'b0;
          a_addr = red_base + {red_idx[28:0], 3'b000};
          a_size = 7'd8;
          next_state = ST_RWB;
        end
        ST_RWB: begin
          elem = a_rdata[63:0];
          if ((red_funct == RED_MODP) && (elem >= P)) begin
            trap = 1'b1;
            tcause_c = CAUSE_RED;
          end else if (red_funct == RED_SUM) begin
            za = z_add(red_acc, {{192{elem[63]}}, elem});
            if (!za.ok) begin
              trap = 1'b1;
              tcause_c = CAUSE_ZRANGE;
            end else begin
              red_acc_n = za.sum;
              if ({32'h0, red_idx} + 64'd1 == red_len) begin
                z_we = 1'b1;
                z_wa = red_zd;
                z_wd = za.sum;
                pc_we = 1'b1;
                pc_next = pc + 32'd4;
                next_state = ST_FETCH;
              end else begin
                red_step = 1'b1;
                next_state = ST_RRD;
              end
            end
          end else if (red_funct == RED_MODP) begin
            res_n = field_add(red_res, elem);
            red_res_n = res_n;
            if ({32'h0, red_idx} + 64'd1 == red_len) begin
              z_we = 1'b1;
              z_wa = red_zd;
              z_wd = {{192{1'b0}}, res_n};
              pc_we = 1'b1;
              pc_next = pc + 32'd4;
              next_state = ST_FETCH;
            end else begin
              red_step = 1'b1;
              next_state = ST_RRD;
            end
          end else begin
            if (red_idx == 32'h0) chosen = elem;
            else if (red_funct == RED_MIN) chosen = ($signed(elem) < $signed(red_cur)) ? elem : red_cur;
            else chosen = ($signed(elem) > $signed(red_cur)) ? elem : red_cur;
            red_cur_n = chosen;
            if ({32'h0, red_idx} + 64'd1 == red_len) begin
              z_we = 1'b1;
              z_wa = red_zd;
              z_wd = {{192{chosen[63]}}, chosen};
              pc_we = 1'b1;
              pc_next = pc + 32'd4;
              next_state = ST_FETCH;
            end else begin
              red_step = 1'b1;
              next_state = ST_RRD;
            end
          end
        end
        ST_EXEC: begin
          if ((op == OP_ADD) || (op == OP_SUB) || (op == OP_AND) || (op == OP_OR) ||
              (op == OP_XOR) || (op == OP_SLL) || (op == OP_SRL) || (op == OP_SRA) ||
              (op == OP_SLT) || (op == OP_SLTU) || (op == OP_MULLO) ||
              (op == OP_MULHI) || (op == OP_MULUHI)) begin
            if (funct != 11'h0) begin
              trap = 1'b1;
              tcause_c = CAUSE_ILL;
            end else begin
              xv = xrd(i20);
              yv = xrd(i15);
              x_wa = i25;
              x_we = 1'b1;
              pc_we = 1'b1;
              pc_next = pc + 32'd4;
              next_state = ST_FETCH;
              if (op == OP_ADD) x_wd = xv + yv;
              else if (op == OP_SUB) x_wd = xv - yv;
              else if (op == OP_AND) x_wd = xv & yv;
              else if (op == OP_OR) x_wd = xv | yv;
              else if (op == OP_XOR) x_wd = xv ^ yv;
              else if (op == OP_SLL) x_wd = xv << yv[5:0];
              else if (op == OP_SRL) x_wd = xv >> yv[5:0];
              else if (op == OP_SRA) x_wd = $unsigned($signed(xv) >>> yv[5:0]);
              else if (op == OP_SLT) x_wd = ($signed(xv) < $signed(yv)) ? 64'd1 : 64'd0;
              else if (op == OP_SLTU) x_wd = (xv < yv) ? 64'd1 : 64'd0;
              else if (op == OP_MULLO) x_wd = sp128[63:0];
              else if (op == OP_MULHI) x_wd = sp128[127:64];
              else x_wd = up128[127:64];
            end
          end else if ((op == OP_ADDI) || (op == OP_ANDI) || (op == OP_ORI) ||
                       (op == OP_XORI) || (op == OP_SLTI) || (op == OP_SLTIU) ||
                       (op == OP_LUI)) begin
            xv = xrd(i20);
            x_wa = i25;
            x_we = 1'b1;
            pc_we = 1'b1;
            pc_next = pc + 32'd4;
            next_state = ST_FETCH;
            if (op == OP_ADDI) x_wd = xv + sext16(imm);
            else if (op == OP_ANDI) x_wd = xv & zext16(imm);
            else if (op == OP_ORI) x_wd = xv | zext16(imm);
            else if (op == OP_XORI) x_wd = xv ^ zext16(imm);
            else if (op == OP_SLTI) x_wd = ($signed(xv) < $signed(sext16(imm))) ? 64'd1 : 64'd0;
            else if (op == OP_SLTIU) x_wd = (xv < sext16(imm)) ? 64'd1 : 64'd0;
            else x_wd = {{32{imm[15]}}, imm, 16'h0000};
          end else if (op == OP_Z) begin
            if (zlo != 8'h00) begin
              trap = 1'b1;
              tcause_c = CAUSE_ILL;
            end else if (f3 == Z_CLR) begin
              if ((i25 > 5'd7) || (i20 != 5'd0) || (i15 != 5'd0)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                z_we = 1'b1; z_wa = i25; z_wd = '0;
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end else if (f3 == Z_SEXT) begin
              if ((i25 > 5'd7) || (i15 != 5'd0)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                z_we = 1'b1; z_wa = i25;
                z_wd = {{192{r20[63]}}, r20};
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end else if (f3 == Z_LIMB) begin
              if ((i25 > 5'd7) || (i15 > 5'd3)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                x_we = 1'b1; x_wa = i20;
                if (i15[1:0] == 2'd0) x_wd = zr[i25][63:0];
                else if (i15[1:0] == 2'd1) x_wd = zr[i25][127:64];
                else if (i15[1:0] == 2'd2) x_wd = zr[i25][191:128];
                else x_wd = zr[i25][255:192];
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end else if (f3 == Z_FIT) begin
              if ((i25 > 5'd7) || (i15 != 5'd0)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else if (!z_fit64(zr[i25])) begin
                trap = 1'b1; tcause_c = CAUSE_ZRANGE;
              end else begin
                x_we = 1'b1; x_wa = i20; x_wd = zr[i25][63:0];
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end else if ((f3 == Z_ADD) || (f3 == Z_SUB)) begin
              if ((i25 > 5'd7) || (i20 > 5'd7) || (i15 > 5'd7)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                if (f3 == Z_ADD) za = z_add(zr[i20], zr[i15]);
                else za = z_sub(zr[i20], zr[i15]);
                if (!za.ok) begin
                  trap = 1'b1; tcause_c = CAUSE_ZRANGE;
                end else begin
                  z_we = 1'b1; z_wa = i25; z_wd = za.sum;
                  pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
                end
              end
            end else if (f3 == Z_MAC) begin
              if (i25 > 5'd7) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                za = z_mac(zr[i25], r20, r15);
                if (!za.ok) begin
                  trap = 1'b1; tcause_c = CAUSE_ZRANGE;
                end else begin
                  z_we = 1'b1; z_wa = i25; z_wd = za.sum;
                  pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
                end
              end
            end else begin
              if ((i25 > 5'd7) || (i20 > 5'd7) || (i15 != 5'd0)) begin
                trap = 1'b1; tcause_c = CAUSE_ILL;
              end else begin
                z_we = 1'b1; z_wa = i25;
                modv = euclid_mod_p(zr[i20]); z_wd = {{192{1'b0}}, modv};
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end
          end else if (op == OP_RED) begin
            if (i25 > 5'd7) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else if (!((funct == RED_SUM) || (funct == RED_MIN) ||
                           (funct == RED_MAX) || (funct == RED_MODP))) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else if (r20[63:32] != 32'h0) begin
              trap = 1'b1; tcause_c = CAUSE_PERM;
            end else if (r20[2:0] != 3'b000) begin
              trap = 1'b1; tcause_c = CAUSE_ALIGN;
            end else if (r15 == 64'h0) begin
              if ((funct == RED_MIN) || (funct == RED_MAX)) begin
                trap = 1'b1; tcause_c = CAUSE_EMPTY;
              end else begin
                z_we = 1'b1; z_wa = i25; z_wd = '0;
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end
            end else begin
              nbytes = {r15, 3'b000};
              end_m = {35'b0, r20[31:0]} + nbytes;
              if (end_m > 67'h1_0000_0000) span_ok = 1'b0;
              else if ((r20[31:0] <= ROM_HI) && ((end_m[31:0] - 32'd1) <= ROM_HI)) span_ok = 1'b1;
              else if ((r20[31:0] >= SRAM_LO) && ((end_m[31:0] - 32'd1) <= SRAM_HI)) span_ok = 1'b1;
              else span_ok = 1'b0;
              if (!span_ok) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else if (r15 > 64'd4096) begin
                trap = 1'b1; tcause_c = CAUSE_RED;
              end else begin
                arm_red = 1'b1;
                arm_base = r20[31:0];
                arm_len = r15;
                arm_zd = i25;
                arm_funct = funct;
                next_state = ST_RRD;
              end
            end
          end else if ((op == OP_BEQ) || (op == OP_BNE) || (op == OP_BLT) ||
                       (op == OP_BGE) || (op == OP_BLTU) || (op == OP_BGEU)) begin
            if (imm[1:0] != 2'b00) begin
              trap = 1'b1; tcause_c = CAUSE_CTRL;
            end else begin
              xv = r25;
              yv = r20;
              if (op == OP_BEQ) taken = (xv == yv);
              else if (op == OP_BNE) taken = (xv != yv);
              else if (op == OP_BLT) taken = ($signed(xv) < $signed(yv));
              else if (op == OP_BGE) taken = ($signed(xv) >= $signed(yv));
              else if (op == OP_BLTU) taken = (xv < yv);
              else taken = (xv >= yv);
              if (!taken) begin
                pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
              end else begin
                t34 = $signed({2'b00, pc}) + $signed({{18{imm[15]}}, imm});
                if (t34[33:32] != 2'b00) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else if (!fetch_ok(t34[31:0])) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else begin
                  pc_we = 1'b1; pc_next = t34[31:0]; next_state = ST_FETCH;
                end
              end
            end
          end else if (op == OP_JAL) begin
            if (i20 != 5'd0) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else if (imm[1:0] != 2'b00) begin
              trap = 1'b1; tcause_c = CAUSE_CTRL;
            end else begin
              t34 = $signed({2'b00, pc}) + $signed({{18{imm[15]}}, imm});
              if (t34[33:32] != 2'b00) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else if (!fetch_ok(t34[31:0])) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else begin
                x_we = 1'b1; x_wa = i25; x_wd = link;
                pc_we = 1'b1; pc_next = t34[31:0]; next_state = ST_FETCH;
              end
            end
          end else if (op == OP_JALR) begin
            if (r20[63:32] != 32'h0) begin
              trap = 1'b1; tcause_c = CAUSE_PERM;
            end else begin
              t34 = $signed({2'b00, r20[31:0]}) + $signed({{18{imm[15]}}, imm});
              tgt = {t34[31:2], 2'b00};
              if (t34[33:32] != 2'b00) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else if (!fetch_ok(tgt)) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else begin
                x_we = 1'b1; x_wa = i25; x_wd = link;
                pc_we = 1'b1; pc_next = tgt; next_state = ST_FETCH;
              end
            end
          end else if (op == OP_HALT) begin
            if (funct != 11'h0) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else next_state = ST_HALT;
          end else if (op == OP_ECALL) begin
            if (funct != 11'h0) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else begin
              trap = 1'b1; tcause_c = CAUSE_ECALL;
            end
          end else if ((op == OP_LD) || (op == OP_LW) || (op == OP_LH) || (op == OP_LB) ||
                       (op == OP_LWU) || (op == OP_LHU) || (op == OP_LBU) ||
                       (op == OP_SD) || (op == OP_SW) || (op == OP_SH) || (op == OP_SB) ||
                       (op == OP_ZLD) || (op == OP_ZST)) begin
            if (((op == OP_ZLD) || (op == OP_ZST)) && (i25 > 5'd7)) begin
              trap = 1'b1; tcause_c = CAUSE_ILL;
            end else begin
              sum = r20 + sext16(imm);
              if ((op == OP_LD) || (op == OP_SD)) sz = 7'd8;
              else if ((op == OP_LW) || (op == OP_LWU) || (op == OP_SW)) sz = 7'd4;
              else if ((op == OP_LH) || (op == OP_LHU) || (op == OP_SH)) sz = 7'd2;
              else if ((op == OP_LB) || (op == OP_LBU) || (op == OP_SB)) sz = 7'd1;
              else sz = 7'd32;
              phys = sum[31:0];
              if (sum[63:32] != 32'h0) begin
                trap = 1'b1; tcause_c = CAUSE_PERM;
              end else if (!aligned(phys, sz)) begin
                trap = 1'b1; tcause_c = CAUSE_ALIGN;
              end else if (in_accel_win(phys) || in_dma_win(phys)) begin
                if (!((sz == 7'd4) && ((op == OP_LW) || (op == OP_LWU) || (op == OP_SW)))) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else if (in_accel_win(phys) && !accel_off_ok(phys[11:0])) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else if (in_dma_win(phys) && !dma_off_ok(phys[11:0])) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else if (op == OP_SW) begin
                  if (in_accel_win(phys)) begin
                    acc_wr = 1'b1; acc_addr = phys[11:0]; acc_wdata = r25[31:0];
                  end else begin
                    dma_wr = 1'b1; dma_addr = phys[11:0]; dma_wdata = r25[31:0];
                  end
                  pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
                end else begin
                  if (in_accel_win(phys)) begin
                    acc_rd = 1'b1; acc_addr = phys[11:0];
                  end else begin
                    dma_rd = 1'b1; dma_addr = phys[11:0];
                  end
                  save_ld = 1'b1; save_op = op; save_rd = i25;
                  save_mmio = 1'b1; save_dma = in_dma_win(phys); save_z = 1'b0;
                  next_state = ST_WB;
                end
              end else if ((op == OP_SD) || (op == OP_SW) || (op == OP_SH) ||
                           (op == OP_SB) || (op == OP_ZST)) begin
                if (!bytes_in_sram(phys, sz)) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else begin
                  a_valid = 1'b1; a_we = 1'b1; a_addr = phys; a_size = sz;
                  if (op == OP_ZST) a_wdata = zr[i25];
                  else a_wdata = {192'h0, r25};
                  pc_we = 1'b1; pc_next = pc + 32'd4; next_state = ST_FETCH;
                end
              end else begin
                if (!(bytes_in_rom(phys, sz) || bytes_in_sram(phys, sz))) begin
                  trap = 1'b1; tcause_c = CAUSE_PERM;
                end else begin
                  a_valid = 1'b1; a_we = 1'b0; a_addr = phys; a_size = sz;
                  save_ld = 1'b1; save_op = op; save_rd = i25;
                  save_mmio = 1'b0; save_dma = 1'b0; save_z = (op == OP_ZLD);
                  next_state = ST_WB;
                end
              end
            end
          end else begin
            trap = 1'b1;
            tcause_c = CAUSE_ILL;
          end
        end
        default: next_state = ST_FETCH;
      endcase
    end
  end

  integer ri;
  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= 32'h0;
      tcause <= 32'h0;
      tpc <= 32'h0;
      state <= ST_FETCH;
      ld_op <= 6'h0;
      ld_rd <= 5'd0;
      ld_mmio <= 1'b0;
      ld_dma <= 1'b0;
      ld_z <= 1'b0;
      red_base <= 32'h0;
      red_len <= 64'h0;
      red_idx <= 32'h0;
      red_zd <= 5'd0;
      red_funct <= 11'h0;
      red_acc <= '0;
      red_res <= 64'h0;
      red_cur <= 64'h0;
      for (ri = 0; ri < 32; ri = ri + 1) xr[ri] <= 64'h0;
      for (ri = 0; ri < 8; ri = ri + 1) zr[ri] <= '0;
    end else if (trap) begin
      tpc <= pc;
      tcause <= tcause_c;
      pc <= TRAP_PC;
      state <= ST_FETCH;
    end else begin
      if (pc_we) pc <= pc_next;
      if (x_we && (x_wa != 5'd0)) xr[x_wa] <= x_wd;
      if (z_we) zr[z_wa] <= z_wd;
      state <= next_state;
      if (save_ld) begin
        ld_op <= save_op;
        ld_rd <= save_rd;
        ld_mmio <= save_mmio;
        ld_dma <= save_dma;
        ld_z <= save_z;
      end
      if (arm_red) begin
        red_base <= arm_base;
        red_len <= arm_len;
        red_idx <= 32'h0;
        red_zd <= arm_zd;
        red_funct <= arm_funct;
        red_acc <= '0;
        red_res <= 64'h0;
        red_cur <= 64'h0;
      end
      if (red_step) begin
        red_idx <= red_idx + 32'd1;
        red_acc <= red_acc_n;
        red_res <= red_res_n;
        red_cur <= red_cur_n;
      end
    end
  end

  assign pc_q = pc;
  assign tcause_q = tcause;
  assign tpc_q = tpc;
  assign halted = (state == ST_HALT);

endmodule
