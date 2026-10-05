#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
trap 'tail -40 "${log:-$BUILD/logs/assembler.log}"' ERR
IVERILOG=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
{
  provenance
  "${CC:-cc}" --version | head -1
  "${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror compiler/alapeno_as.c -o "$BUILD/alapeno_as"
  "$BUILD/alapeno_as" compiler/encode_check.s "$BUILD/encode_check.bin"
  [[ "$(od -An -tx1 -N4 "$BUILD/encode_check.bin" | tr -d ' \n')" == 00182200 ]]
  "$BUILD/alapeno_as" compiler/tile4.s "$BUILD/tile4.bin"
  cmp "$BUILD/tile4.bin" verification/rtl/tile4.bin
  printf 'PASS ASSEMBLER: strict build and tile image byte comparison\n'
} > "$BUILD/logs/assembler.log" 2>&1
for bench in rect_bounds geom_overlap mem_equiv project_capacity tile4_rom tile_top les_diff accel_abort porta_contest dma_abort zmac_neg vec_extrema mac_ref; do
  log="$BUILD/logs/$bench.log"
  (
    provenance
    "$IVERILOG" -V
    sha256sum "verification/rtl/tb_$bench.sv" verification/rtl/mac_ref.sv verification/rtl/mem_reference.sv
    set -x
    "$IVERILOG" -g2012 -s "tb_$bench" -I rtl/core -o "$BUILD/$bench.vvp" \
      "${RTL[@]}" verification/rtl/mac_ref.sv verification/rtl/mem_reference.sv "verification/rtl/tb_$bench.sv"
    printf 'iverilog_exit 0\n'
    # The ROM bench uses a relative filename; run it beside the freshly assembled image.
    cd "$BUILD"
    "$VVP" "$BUILD/$bench.vvp"
    printf 'vvp_exit 0\n'
  ) > "$log" 2>&1
  rg 'PASS' "$log" >/dev/null || { echo "Missing PASS: $bench"; exit 1; }
  echo "PASS $bench"
done
