* SPDX-License-Identifier: AGPL-3.0-only
* 2-word by 2-bit SRAM array from four 6T bitcells with PMOS precharge.
* Ports: wl0 wl1 bl0 blb0 bl1 blb1 pch vdd vss
* Illustrative Level-1 MOSFET cards, not a foundry PDK / not measured silicon.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.include /workspace/alapeno/spice/sram/bitcell_6t.sp

.subckt array_2x2 wl0 wl1 bl0 blb0 bl1 blb1 pch vdd vss
* Word 0
Xc00 bl0 blb0 wl0 vdd vss bitcell_6t
Xc01 bl1 blb1 wl0 vdd vss bitcell_6t
* Word 1
Xc10 bl0 blb0 wl1 vdd vss bitcell_6t
Xc11 bl1 blb1 wl1 vdd vss bitcell_6t
* PMOS precharge on each bitline pair (active when pch=0)
Mp_bl0  bl0  pch vdd vdd pmos_tt L=0.18u W=0.72u
Mp_blb0 blb0 pch vdd vdd pmos_tt L=0.18u W=0.72u
Mp_bl1  bl1  pch vdd vdd pmos_tt L=0.18u W=0.72u
Mp_blb1 blb1 pch vdd vdd pmos_tt L=0.18u W=0.72u
* Equalize bitline pairs during precharge
Mp_eq0 bl0 pch blb0 vdd pmos_tt L=0.18u W=0.72u
Mp_eq1 bl1 pch blb1 vdd pmos_tt L=0.18u W=0.72u
.ends array_2x2
