* SPDX-License-Identifier: AGPL-3.0-only
* Positive-edge master-slave D flip-flop using transmission gates and inverters.
* When clk rises, slave captures master; master samples while clk low.
* Ports: d clk q qn vdd vss
* Parent must .include inv.sp first (models from parent deck).
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt dff d clk q qn vdd vss
* clk complement
Xiclk clk clkb vdd vss inv
* Master transmission gate: pass d -> m when clk=0 (clkb=1)
* NMOS on with clkb, PMOS on with clk
Mtn_m m clkb d vss nmos_tt L=0.18u W=0.36u
Mtp_m m clk d vdd pmos_tt L=0.18u W=0.72u
* Master latch inverters (cross-coupled via weak feedback TG when clk=1)
Xim1 m mb vdd vss inv
Xim2 mb mfb vdd vss inv
* Feedback TG enabled when clk=1 (hold)
Mtn_mf m clk mfb vss nmos_tt L=0.18u W=0.36u
Mtp_mf m clkb mfb vdd pmos_tt L=0.18u W=0.72u
* Slave transmission gate: pass mb -> s when clk=1
Mtn_s s clk mb vss nmos_tt L=0.18u W=0.36u
Mtp_s s clkb mb vdd pmos_tt L=0.18u W=0.72u
* Slave latch
Xis1 s qn vdd vss inv
Xis2 qn q vdd vss inv
* Slave feedback TG when clk=0
Mtn_sf s clkb q vss nmos_tt L=0.18u W=0.36u
Mtp_sf s clk q vdd pmos_tt L=0.18u W=0.72u
.ends dff
