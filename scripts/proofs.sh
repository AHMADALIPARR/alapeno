#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
WHY3=${WHY3:-why3}
PROVER=${PROVER:-Z3,4.13.3}
trap 'tail -30 "$log"' ERR
args=()
if [[ -n "${WHY3_CONFIG:-}" ]]; then args+=(-C "$WHY3_CONFIG"); fi
for model in compiler/compile.mlw verification/isa/isa_check.mlw why3/tile.mlw why3/accelerator.mlw why3/memory.mlw why3/arithmetic.mlw why3/isa.mlw; do
  name=$(basename "$model" .mlw)
  log="$BUILD/logs/why3-$name.log"
  (
    provenance
    sha256sum compiler/*.mlw why3/*.mlw verification/isa/*.mlw
    "$WHY3" --version
    set -x
    "$WHY3" "${args[@]}" prove -L compiler -L why3 -P "$PROVER" -a split_vc -t 10 "$model"
    echo 'why3_exit 0'
  ) > "$log" 2>&1
  # Parse-only models may contain no goals. Report that explicitly.
  if rg 'Prover result is:' "$log" >/dev/null; then
    if rg 'Prover result is:' "$log" | rg -v 'Prover result is: Valid' >/dev/null; then
      echo "Unproved goal in $model"; exit 1
    fi
    echo "PASS $model: $(rg -c 'Prover result is: Valid' "$log") Valid results"
  else
    # The ISA file defines predicates only; all other models must emit VCs.
    [[ "$model" == why3/isa.mlw ]] || { tail -30 "$log"; exit 1; }
    echo "TYPECHECK ONLY $model: no proof goals"
  fi
done
