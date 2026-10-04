* SPDX-License-Identifier: AGPL-3.0-only
* CMOS inverter. Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt inv in out vdd vss
Mp out in vdd vdd pmos_tt L=0.18u W=0.72u
Mn out in vss vss nmos_tt L=0.18u W=0.36u
.ends inv
