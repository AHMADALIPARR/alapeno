* SPDX-License-Identifier: AGPL-3.0-only
* Classic 6T SRAM bitcell: two cross-coupled inverters + two NMOS access FETs.
* Ports: bl blb wl vdd vss. Internal storage nodes q and qb.
* Illustrative Level-1 MOSFET cards, not a foundry PDK / not measured silicon.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt bitcell_6t bl blb wl vdd vss
* Inverter 1: q -> qb
Mp1 qb q vdd vdd pmos_tt L=0.18u W=0.72u
Mn1 qb q vss vss nmos_tt L=0.18u W=0.36u
* Inverter 2: qb -> q
Mp2 q qb vdd vdd pmos_tt L=0.18u W=0.72u
Mn2 q qb vss vss nmos_tt L=0.18u W=0.36u
* Access transistors
MnA1 bl  wl q  vss nmos_tt L=0.18u W=0.36u
MnA2 blb wl qb vss nmos_tt L=0.18u W=0.36u
.ends bitcell_6t
