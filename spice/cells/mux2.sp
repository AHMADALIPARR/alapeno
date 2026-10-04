* SPDX-License-Identifier: AGPL-3.0-only
* 2:1 CMOS mux. Boolean: out = (d0 AND NOT sel) OR (d1 AND sel)
* Built as: out = NAND( NAND(d0, nsel), NAND(d1, sel) ); nsel = NOT sel
* Parent must .include nand2.sp and inv.sp first.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt mux2 d0 d1 sel out vdd vss
Xnsel sel nsel vdd vss inv
Xn0 d0 nsel t0 vdd vss nand2
Xn1 d1 sel t1 vdd vss nand2
Xout t0 t1 out vdd vss nand2
.ends mux2
