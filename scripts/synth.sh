#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
YOSYS=${YOSYS:-yosys}
top=${1:-alapeno_top}
mode=${2:-generic}
case "$top" in alapeno_top|alapeno_tile_ctrl) ;; *) echo 'Unsupported top' >&2; exit 2;; esac
case "$mode" in generic|asic) ;; *) echo 'Unsupported synthesis mode' >&2; exit 2;; esac
if [[ "$mode" == asic ]]; then
  : "${LIBERTY:?Set LIBERTY to the selected PDK standard-cell Liberty file}"
  : "${CLOCK_PS:?Set CLOCK_PS to the target clock period in picoseconds}"
  [[ -f "$LIBERTY" && "$CLOCK_PS" =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 2
fi
script="$BUILD/$top-$mode.ys"
map_script="$BUILD/$top-$mode-map.ys"
rm -f "$BUILD/$top-$mode.json" "$BUILD/$top-$mode.v" "$BUILD/$top-wordlevel.json"
{
  echo 'plugin -i slang'
  printf 'read_slang --std latest --unroll-limit 100000 '
  # Preserve component boundaries to bound the size of each checked graph.
  if [[ "$top" == alapeno_top ]]; then printf '%s ' '--best-effort-hierarchy'; fi
  printf -- '--top %s ' "$top"
  printf '%s ' "${RTL[@]}"
  printf '\n'
  echo "hierarchy -check -top $top"
  echo 'proc; opt; fsm; opt; opt_clean -purge'
  echo 'wreduce; opt; alumacc; opt'
  # memory_dff in Yosys 0.69+190 disconnects eight matrix read bytes when
  # PROJECT is enabled. Retain explicit read registers instead.
  echo 'memory -nomap -nordff; opt; opt_clean -purge'
  echo 'check -assert; stat'
  echo "write_json $BUILD/$top-wordlevel.json"
} > "$script"
{
  # A fresh process releases frontend AST and optimization scratch storage.
  echo "read_json $BUILD/$top-wordlevel.json"
  if [[ "$mode" == asic ]]; then echo 'memory_map; opt; opt_clean -purge'; fi
  printf 'tcl scripts/techmap.tcl %s %s\n' "$BUILD" "$top"
  if [[ "$mode" == asic ]]; then
    printf 'read_liberty -lib -ignore_miss_func "%s"\n' "$LIBERTY"
    printf 'dfflibmap -liberty "%s"\n' "$LIBERTY"
    printf 'abc -liberty "%s" -D %s\n' "$LIBERTY" "$CLOCK_PS"
    echo 'clean'
  fi
  echo 'check -assert'
  if [[ "$mode" == asic ]]; then
    echo 'select -assert-none t:$*'
    printf 'stat -liberty "%s"\n' "$LIBERTY"
  else
    echo 'select -assert-none t:$* t:$_* %d t:$mem_v2 %d'
    echo 'stat'
  fi
  echo "write_json $BUILD/$top-$mode.json"
  echo "write_verilog -noattr $BUILD/$top-$mode.v"
} > "$map_script"
{
  provenance
  "$YOSYS" -V
  if [[ "$mode" == asic ]]; then sha256sum "$LIBERTY"; fi
  cat "$script" "$map_script"
  "$YOSYS" -Q -T -s "$script"
  [[ -s "$BUILD/$top-wordlevel.json" ]]
  echo 'wordlevel_yosys_exit 0'
  "$YOSYS" -Q -T -s "$map_script"
  # Also reject zero-status frontend failures that did not produce artifacts.
  [[ -s "$BUILD/$top-$mode.json" && -s "$BUILD/$top-$mode.v" ]]
  echo 'yosys_exit 0'
} > "$BUILD/logs/yosys_$top-$mode.log" 2>&1
tail -35 "$BUILD/logs/yosys_$top-$mode.log"
