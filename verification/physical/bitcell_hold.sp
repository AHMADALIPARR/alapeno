* SPDX-License-Identifier: AGPL-3.0-only
* 6T bitcell hold: brief write of q high, then hold with wl low.
* License: see spice/COPYING
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
.include spice/corners/models_tt.inc
.include spice/sram/bitcell_6t.sp

Vdd vdd 0 DC 1.8
Vss vss 0 DC 0
* Write phase: wl high, bl=1.8, blb=0 for 2ns; then wl low (hold)
Vwl wl 0 PWL(0 0 0.1n 1.8 2n 1.8 2.1n 0 20n 0)
Vbl bl 0 PWL(0 1.8 20n 1.8)
Vblb blb 0 PWL(0 0 20n 0)

Xcell bl blb wl vdd vss bitcell_6t

* Seed storage toward written state (helps Level-1 convergence)
.ic v(xcell.q)=1.8 v(xcell.qb)=0

.tran 10p 20n uic
.print tran v(xcell.q) v(xcell.qb) v(wl)
.end
