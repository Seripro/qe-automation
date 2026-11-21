#!/usr/bin/env bash
#
# 物質別のPWscf.zipを解決し、直接実行でSCF → Band → PDOSを順に実行する。
# PBS実行器を追加するときも、入力配置・段階の順序・成果物の案内はこの
# インターフェースから分離して維持する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATERIAL_LABEL="${MATERIAL:-}"
INPUT_ROOT="${INPUT_ROOT:-${HOME}/qe-inputs}"
WORK_ROOT="${WORK_ROOT:-${HOME}/work}"
QE_TOOLS_VENV="${QE_TOOLS_VENV:-${HOME}/.venvs/qe-tools-v1}"
CURRENT_STAGE="initialization"

usage() {
    cat >&2 <<'EOF'
Usage:
  make run MATERIAL=<material-label> [INPUT_ROOT=<input-root>]

Expected input:
  <input-root>/<material-label>/PWscf.zip

Example:
  make run MATERIAL=MgB2
EOF
}

on_error() {
    local exit_code=$?
    echo "Error: workflow stopped during ${CURRENT_STAGE}." >&2
    exit "${exit_code}"
}
trap on_error ERR

if [[ -z "${MATERIAL_LABEL}" ]]; then
    echo "Error: MATERIAL is required." >&2
    usage
    exit 2
fi

if [[ ! "${MATERIAL_LABEL}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Error: MATERIAL must contain only letters, digits, _ or -." >&2
    exit 2
fi

INPUT_ZIP="${INPUT_ROOT}/${MATERIAL_LABEL}/PWscf.zip"
if [[ ! -f "${INPUT_ZIP}" ]]; then
    echo "Error: input ZIP was not found: ${INPUT_ZIP}" >&2
    usage
    exit 2
fi

RUN_NAME="${MATERIAL_LABEL}-$(date +%Y%m%dT%H%M%S)"
RUN_DIR="${WORK_ROOT}/${RUN_NAME}"

if [[ -z "${VIRTUAL_ENV:-}" && -x "${QE_TOOLS_VENV}/bin/python3" ]]; then
    export PATH="${QE_TOOLS_VENV}/bin:${PATH}"
    echo "Python environment: ${QE_TOOLS_VENV}"
elif [[ -n "${VIRTUAL_ENV:-}" ]]; then
    echo "Python environment: ${VIRTUAL_ENV}"
else
    echo "Warning: ${QE_TOOLS_VENV} was not found; using the current python3." >&2
fi

echo "Material label: ${MATERIAL_LABEL}"
echo "Input ZIP: ${INPUT_ZIP}"
echo "Run directory: ${RUN_DIR}"
echo "Executor: direct OpenMP execution"

CURRENT_STAGE="SCF"
MATERIAL_LABEL="${MATERIAL_LABEL}" RUN_NAME="${RUN_NAME}" WORK_DIR="${RUN_DIR}" \
    bash "${SCRIPT_DIR}/qe_mdx_scf_openmp.sh" "${INPUT_ZIP}"

CURRENT_STAGE="band calculation"
bash "${SCRIPT_DIR}/qe_mdx_band_openmp.sh" "${RUN_DIR}"

CURRENT_STAGE="NSCF and PDOS calculation"
bash "${SCRIPT_DIR}/qe_mdx_pdos_openmp.sh" "${RUN_DIR}"

CURRENT_STAGE="completed"
echo
echo "Workflow completed successfully."
echo "Band plot: ${RUN_DIR}/PWscf/bands.png"
echo "PDOS plot: ${RUN_DIR}/PWscf/pdos.png"
echo "Metadata: ${RUN_DIR}/run-metadata.txt"
