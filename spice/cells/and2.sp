* SPDX-License-Identifier: AGPL-3.0-only
* 2-input AND = NAND2 + INV. Parent deck must .include nand2.sp and inv.sp first.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt and2 a b out vdd vss
Xnand a b nout vdd vss nand2
Xinv nout out vdd vss inv
.ends and2
