MATERIAL ?=
INPUT_ROOT ?= $(HOME)/qe-inputs

export MATERIAL
export INPUT_ROOT

.PHONY: help run venv web-dev

help:
	@echo "make run MATERIAL=<material-label> [INPUT_ROOT=<input-root>]"
	@echo "Example: make run MATERIAL=MgB2"
	@echo "make web-dev"

run:
	@bash scripts/qe_run_direct.sh

venv:
	@echo "source ~/.venvs/qe-tools-v1/bin/activate"

web-dev:
	@bash scripts/run_webapp_dev.sh
