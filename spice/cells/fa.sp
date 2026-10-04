* SPDX-License-Identifier: AGPL-3.0-only
* Full adder. Boolean: sum = a XOR b XOR cin; cout = majority(a,b,cin)
*   = (a AND b) OR (a AND cin) OR (b AND cin)
* Structure: p = a XOR b; sum = p XOR cin; g = a AND b; cout = g OR (p AND cin)
* Parent must .include nand2.sp inv.sp and2.sp xor2.sp nor2.sp (or equiv) first.
* This is a 1-bit structural slice for the integer MAC; not a claim that the
* full 32-bit ISA is laid out in SPICE.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt fa a b cin sum cout vdd vss
* p = a xor b
Xp a b p vdd vss xor2
* sum = p xor cin
Xs p cin sum vdd vss xor2
* g = a and b
Xg a b g vdd vss and2
* t = p and cin
Xt p cin t vdd vss and2
* cout = g or t  via NOR of inverted inputs, or NAND-NAND OR:
* cout = ~(~g & ~t) = NAND(~g, ~t)
Xig g ng vdd vss inv
Xit t nt vdd vss inv
Xco ng nt cout vdd vss nand2
.ends fa
