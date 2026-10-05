* SPDX-License-Identifier: AGPL-3.0-only
* Transient simulation of CMOS inverter (TT corner).
* License: see spice/COPYING
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
.include spice/corners/models_tt.inc
.include spice/cells/inv.sp

Vdd vdd 0 DC 1.8
Vss vss 0 DC 0
Vin in 0 PULSE(0 1.8 1n 0.1n 0.1n 5n 10n)

Xinv in out vdd vss inv

.tran 10p 20n
.print tran v(in) v(out)
.end
