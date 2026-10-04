* SPDX-License-Identifier: AGPL-3.0-only
* NAND-based clock gate: gout = en AND clk (NAND then INV).
* Ports: clk en gout vdd vss
* Parent deck must .include nand2.sp and inv.sp (and MOSFET models) first.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt clk_gate clk en gout vdd vss
Xn clk en nout vdd vss nand2
Xi nout gout vdd vss inv
.ends clk_gate
