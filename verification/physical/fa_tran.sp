* SPDX-License-Identifier: AGPL-3.0-only
* Transient sweep of full-adder through 8 input combinations (a,b,cin).
* License: see spice/COPYING
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* Solver aids (cshunt/slow edges) are testbench-only; models keep CGSO=CGDO=0.
.include spice/corners/models_tt.inc
.include spice/cells/inv.sp
.include spice/cells/nand2.sp
.include spice/cells/nor2.sp
.include spice/cells/and2.sp
.include spice/cells/xor2.sp
.include spice/cells/fa.sp

Vdd vdd 0 DC 1.8
Vss vss 0 DC 0
* Each of 8 combos held 10ns; 1ns linear edges (a,b,cin = binary count)
Va a 0 PWL(0n 0 9n 0 10n 0 19n 0 20n 0 29n 0 30n 0 39n 0
+ 40n 0 41n 1.8 49n 1.8 50n 1.8 59n 1.8 60n 1.8 69n 1.8 70n 1.8 80n 1.8)
Vb b 0 PWL(0n 0 19n 0 20n 0 21n 1.8 29n 1.8 30n 1.8 39n 1.8
+ 40n 1.8 41n 0 49n 0 50n 0 51n 0 59n 0 60n 0 61n 1.8 69n 1.8 70n 1.8 80n 1.8)
Vcin cin 0 PWL(0n 0 9n 0 10n 0 11n 1.8 19n 1.8 20n 1.8 21n 0 29n 0
+ 30n 0 31n 1.8 39n 1.8 40n 1.8 41n 0 49n 0 50n 0 51n 1.8 59n 1.8
+ 60n 1.8 61n 0 69n 0 70n 0 71n 1.8 80n 1.8)

Xfa a b cin sum cout vdd vss fa
Clsum sum 0 5f
Clcout cout 0 5f

* Tiny shunt C on every node helps Level-1 (CGS=0) transient convergence
.options method=gear reltol=1e-3 abstol=1e-10 chgtol=1e-16
.options cshunt=1e-15 rshunt=1e12

.tran 0.1n 80n
.print tran v(a) v(b) v(cin) v(sum) v(cout)
.end
