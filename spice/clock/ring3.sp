* SPDX-License-Identifier: AGPL-3.0-only
* Three-inverter ring oscillator netlist. No frequency claim.
* Ports: vdd vss; internal ring nodes n1 n2 n3.
* Parent deck must .include inv.sp (and MOSFET models) first.
* Illustrative Level-1 MOSFET cards, not a foundry PDK.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.subckt ring3 vdd vss
X1 n1 n2 vdd vss inv
X2 n2 n3 vdd vss inv
X3 n3 n1 vdd vss inv
.ends ring3
