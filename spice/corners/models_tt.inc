* SPDX-License-Identifier: AGPL-3.0-only
* Illustrative Level-1 MOSFET cards — TT corner parameter set only.
* NOT a foundry PDK and NOT measured silicon.
* See /workspace/alapeno/spice/COPYING for the full AGPL-3.0 text.
.model nmos_tt NMOS (LEVEL=1 VTO=0.5 KP=120u GAMMA=0.4 LAMBDA=0.02 PHI=0.6 TOX=9n CGSO=0 CGDO=0)
.model pmos_tt PMOS (LEVEL=1 VTO=-0.5 KP=40u GAMMA=0.4 LAMBDA=0.02 PHI=0.6 TOX=9n CGSO=0 CGDO=0)
