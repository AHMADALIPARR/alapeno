#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
NGSPICE=${NGSPICE:-ngspice}
trap 'tail -30 "$log"' ERR
for deck in inv_tran fa_tran bitcell_hold; do
  log="$BUILD/logs/ngspice-$deck.log"
  (
    provenance
    "$NGSPICE" --version
    sha256sum "verification/physical/$deck.sp" spice/cells/*.sp spice/corners/*.inc spice/sram/*.sp
    set -x
    "$NGSPICE" -b "verification/physical/$deck.sp"
    echo 'ngspice_exit 0'
  ) > "$log" 2>&1
  echo "PASS $deck: transient simulation completed (illustrative models)"
done
