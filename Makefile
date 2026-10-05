# SPDX-License-Identifier: AGPL-3.0-only
.PHONY: all test synth synth-tile synth-asic gate-test gate-project proofs physical clean
all: test synth
test:
	bash scripts/regress.sh
synth:
	bash scripts/synth.sh alapeno_top
synth-tile:
	bash scripts/synth.sh alapeno_tile_ctrl
gate-test: synth-tile
	bash scripts/gate-test.sh
gate-project: synth
	bash scripts/gate-project.sh
synth-asic:
	bash scripts/synth.sh alapeno_top asic
proofs:
	bash scripts/proofs.sh
physical:
	bash scripts/physical.sh
clean:
	rm -rf build
