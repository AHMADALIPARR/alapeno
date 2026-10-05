#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
log="$BUILD/logs/tile_gate.log"
trap 'tail -30 "$log"' ERR
sed 's/^module alapeno_tile_ctrl(/module alapeno_tile_ctrl_synth(/' \
  "$BUILD/alapeno_tile_ctrl-generic.v" > "$BUILD/tile-synth.v"
(
  provenance
  sha256sum "$BUILD/alapeno_tile_ctrl-generic.v" verification/rtl/tb_tile_gate.sv
  "${IVERILOG:-iverilog}" -V
  set -x
  "${IVERILOG:-iverilog}" -g2012 -s tb_tile_gate -o "$BUILD/tile_gate.vvp" \
    rtl/core/alapeno_pkg.sv rtl/matrix/alapeno_matrix.sv rtl/matrix/alapeno_tile_ctrl.sv \
    "$BUILD/tile-synth.v" verification/rtl/tb_tile_gate.sv
  echo 'iverilog_exit 0'
  "${VVP:-vvp}" "$BUILD/tile_gate.vvp"
  echo 'vvp_exit 0'
) > "$log" 2>&1
rg '^PASS' "$log"
