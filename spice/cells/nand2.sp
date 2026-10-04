* SPDX-License-Identifier: AGPL-3.0-only
* 2-input CMOS NAND. Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt nand2 a b out vdd vss
Mp1 out a vdd vdd pmos_tt L=0.18u W=0.72u
Mp2 out b vdd vdd pmos_tt L=0.18u W=0.72u
Mn1 out a mid vss nmos_tt L=0.18u W=0.72u
Mn2 mid b vss vss nmos_tt L=0.18u W=0.72u
.ends nand2
