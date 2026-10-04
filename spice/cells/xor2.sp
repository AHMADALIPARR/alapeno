* SPDX-License-Identifier: AGPL-3.0-only
* CMOS XOR from four NAND2 gates. Parent deck must .include nand2.sp first.
* Boolean: out = (a NAND (a NAND b)) NAND (b NAND (a NAND b))
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt xor2 a b out vdd vss
Xn1 a b n1 vdd vss nand2
Xn2 a n1 o1 vdd vss nand2
Xn3 b n1 o2 vdd vss nand2
Xn4 o1 o2 out vdd vss nand2
.ends xor2
