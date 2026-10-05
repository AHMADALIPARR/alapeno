#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
source "$(dirname "$0")/common.sh"
IVERILOG=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
PROJECT_NETLIST=${PROJECT_NETLIST:-$BUILD/alapeno_top-generic.v}
[[ -s "$PROJECT_NETLIST" ]] || { echo 'Run make synth first' >&2; exit 2; }
# Extract only the matrix module so unrelated gates need not be parsed.
python3 - "$BUILD" "$PROJECT_NETLIST" <<'PY'
import sys
from pathlib import Path
build = Path(sys.argv[1])
found = complete = False
with Path(sys.argv[2]).open() as source, (build / 'matrix-synth.v').open('w') as output:
    for line in source:
        if line.startswith('module \\alapeno_matrix$'):
            if found:
                raise RuntimeError('Multiple synthesized matrix modules')
            found = True
            line = 'module alapeno_matrix_synth ' + line[line.index('('):]
        if found and not complete:
            output.write(line)
            if line.strip() == 'endmodule':
                complete = True
if not complete:
    raise RuntimeError('Missing synthesized matrix module')
bench = Path('verification/rtl/tb_project_capacity.sv').read_text()
assert bench.count('alapeno_matrix #(.OBUF_BYTES(512)) dut') == 1
bench = bench.replace('module tb_project_capacity;', 'module tb_project_gate;').replace(
    'alapeno_matrix #(.OBUF_BYTES(512)) dut', 'alapeno_matrix_synth dut')
(build / 'tb_project_gate.sv').write_text(bench)
PY
log="$BUILD/logs/project_gate.log"
trap 'tail -40 "$log"' ERR
(
  provenance
  sha256sum "$PROJECT_NETLIST" "$BUILD/matrix-synth.v" verification/rtl/tb_project_capacity.sv "$BUILD/tb_project_gate.sv"
  "$IVERILOG" -V
  set -x
  "$IVERILOG" -g2012 -s tb_project_gate -o "$BUILD/project_gate.vvp" \
    rtl/core/alapeno_pkg.sv rtl/memory/alapeno_mem.sv "$BUILD/matrix-synth.v" "$BUILD/tb_project_gate.sv"
  echo 'iverilog_exit 0'
  "$VVP" "$BUILD/project_gate.vvp"
  echo 'vvp_exit 0'
) > "$log" 2>&1
rg 'PASS PROJECT 2x2' "$log" >/dev/null
rg 'PASS CAPACITY' "$log" >/dev/null
rg 'PASS PROJECT fault' "$log" >/dev/null
rg 'PASS' "$log"
