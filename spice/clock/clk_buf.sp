* SPDX-License-Identifier: AGPL-3.0-only
* Two-inverter clock buffer. Ports: cin cout vdd vss
* Parent deck must .include inv.sp (and MOSFET models) first.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt clk_buf cin cout vdd vss
X1 cin mid vdd vss inv
X2 mid cout vdd vss inv
.ends clk_buf
