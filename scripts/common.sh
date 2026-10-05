#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
BUILD="$ROOT/build"
mkdir -p "$BUILD/logs"
RTL=(rtl/core/alapeno_pkg.sv rtl/core/alapeno_core.sv
     rtl/mac/alapeno_mac.sv rtl/matrix/alapeno_matrix.sv
     rtl/vector/alapeno_vector.sv rtl/matrix/alapeno_accel.sv
     rtl/matrix/alapeno_tile_ctrl.sv rtl/dma/alapeno_dma.sv
     rtl/memory/alapeno_mem.sv rtl/alapeno_top.sv)
provenance() {
  git rev-parse HEAD
  git diff --binary > "$BUILD/source.patch"
  git status --short
  sha256sum "${RTL[@]}" compiler/alapeno_as.c compiler/tile4.s scripts/*.sh scripts/*.tcl
}
