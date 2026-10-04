* SPDX-License-Identifier: AGPL-3.0-only
* 4-bit structural slice of an integer multiply-accumulate (Braun array +
* 8-bit ripple-carry accumulator). This is NOT a claim that the full 32-bit
* ISA datapath is laid out in SPICE. Illustrative Level-1 MOSFET cards,
* not a foundry PDK / not measured silicon.
* On clk: acc[7:0] <= (acc[7:0] + zero_ext(a[3:0]*b[3:0])) mod 256
* rst: synchronous clear of the accumulator flops (d forced to 0 while rst=1).
* Ports: a0..a3 b0..b3 clk rst vdd vss acc0..acc7
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
*
* Parent / including deck must provide MOSFET models (e.g. models.inc).
* Cell deps included below once.
.include /workspace/alapeno/spice/cells/inv.sp
.include /workspace/alapeno/spice/cells/nand2.sp
.include /workspace/alapeno/spice/cells/nor2.sp
.include /workspace/alapeno/spice/cells/and2.sp
.include /workspace/alapeno/spice/cells/xor2.sp
.include /workspace/alapeno/spice/cells/fa.sp
.include /workspace/alapeno/spice/cells/dff.sp
.include /workspace/alapeno/spice/cells/mux2.sp

.subckt mac4 a0 a1 a2 a3 b0 b1 b2 b3 clk rst vdd vss
+ acc0 acc1 acc2 acc3 acc4 acc5 acc6 acc7

* ---- Partial products pp[i][j] = a[i] AND b[j] ----
Xpp00 a0 b0 pp00 vdd vss and2
Xpp01 a1 b0 pp01 vdd vss and2
Xpp02 a2 b0 pp02 vdd vss and2
Xpp03 a3 b0 pp03 vdd vss and2
Xpp10 a0 b1 pp10 vdd vss and2
Xpp11 a1 b1 pp11 vdd vss and2
Xpp12 a2 b1 pp12 vdd vss and2
Xpp13 a3 b1 pp13 vdd vss and2
Xpp20 a0 b2 pp20 vdd vss and2
Xpp21 a1 b2 pp21 vdd vss and2
Xpp22 a2 b2 pp22 vdd vss and2
Xpp23 a3 b2 pp23 vdd vss and2
Xpp30 a0 b3 pp30 vdd vss and2
Xpp31 a1 b3 pp31 vdd vss and2
Xpp32 a2 b3 pp32 vdd vss and2
Xpp33 a3 b3 pp33 vdd vss and2

* ---- Braun array: merge row b0 with row b1 ----
* prod0 = pp00
* FA row1 (cin grounded via vss):
Xfa11 pp01 pp10 vss  s11 c11 vdd vss fa
Xfa12 pp02 pp11 c11 s12 c12 vdd vss fa
Xfa13 pp03 pp12 c12 s13 c13 vdd vss fa
Xfa14 vss  pp13 c13 s14 c14 vdd vss fa

* ---- Merge with row b2 (pp2x starts at column 2) ----
* col1: s11 passes (wire as s21)
* col2+: FA
Xfa22 s12 pp20 vss  s22 c22 vdd vss fa
Xfa23 s13 pp21 c22 s23 c23 vdd vss fa
Xfa24 s14 pp22 c23 s24 c24 vdd vss fa
Xfa25 c14 pp23 c24 s25 c25 vdd vss fa

* ---- Merge with row b3 (pp3x starts at column 3) ----
Xfa33 s23 pp30 vss  s33 c33 vdd vss fa
Xfa34 s24 pp31 c33 s34 c34 vdd vss fa
Xfa35 s25 pp32 c34 s35 c35 vdd vss fa
Xfa36 c25 pp33 c35 s36 c36 vdd vss fa

* ---- Product bits p0..p7 (unsigned 4x4 -> 8-bit) ----
* p0 = pp00
* p1 = s11
* p2 = s22
* p3 = s33
* p4 = s34
* p5 = s35
* p6 = s36
* p7 = c36
* (Alias via zero-ohm / just use those nets as p*)

* ---- 8-bit ripple-carry adder: sum = acc + product ----
Xadd0 acc0 pp00 vss   sum0 carry0 vdd vss fa
Xadd1 acc1 s11  carry0 sum1 carry1 vdd vss fa
Xadd2 acc2 s22  carry1 sum2 carry2 vdd vss fa
Xadd3 acc3 s33  carry2 sum3 carry3 vdd vss fa
Xadd4 acc4 s34  carry3 sum4 carry4 vdd vss fa
Xadd5 acc5 s35  carry4 sum5 carry5 vdd vss fa
Xadd6 acc6 s36  carry5 sum6 carry6 vdd vss fa
Xadd7 acc7 c36  carry6 sum7 carry7 vdd vss fa
* carry7 discarded: unsigned wrap mod 256

* ---- Sync clear: d = rst ? 0 : sum  (mux2: d0=sum, d1=vss, sel=rst) ----
Xmx0 sum0 vss rst d0 vdd vss mux2
Xmx1 sum1 vss rst d1 vdd vss mux2
Xmx2 sum2 vss rst d2 vdd vss mux2
Xmx3 sum3 vss rst d3 vdd vss mux2
Xmx4 sum4 vss rst d4 vdd vss mux2
Xmx5 sum5 vss rst d5 vdd vss mux2
Xmx6 sum6 vss rst d6 vdd vss mux2
Xmx7 sum7 vss rst d7 vdd vss mux2

* ---- 8-bit accumulator register ----
Xdff0 d0 clk acc0 acc0n vdd vss dff
Xdff1 d1 clk acc1 acc1n vdd vss dff
Xdff2 d2 clk acc2 acc2n vdd vss dff
Xdff3 d3 clk acc3 acc3n vdd vss dff
Xdff4 d4 clk acc4 acc4n vdd vss dff
Xdff5 d5 clk acc5 acc5n vdd vss dff
Xdff6 d6 clk acc6 acc6n vdd vss dff
Xdff7 d7 clk acc7 acc7n vdd vss dff

.ends mac4
