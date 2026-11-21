#!/usr/bin/env bash
#
# mdx-server 上で検証済みPWscf.zipを用いてSCFを直接実行するスクリプト。
# scripts/qe1.sh の「入力準備 → SCF → 出力確認」を、PBS/MPI を使わない
# OpenMP 実行用に移植したもの。既存の qe1.sh, qe2.sh は変更しない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=qe_input_utils.sh
source "${SCRIPT_DIR}/qe_input_utils.sh"

# 引数または環境変数で上書きできる。デフォルトはリポジトリ内の基準入力。
ZIP_FILE="${1:-${ZIP_FILE:-${REPOSITORY_ROOT}/docs/experiments/silicon/input/PWscf.zip}}"
MATERIAL_LABEL="${MATERIAL_LABEL:-Si}"
RUN_NAME="${RUN_NAME:-${MATERIAL_LABEL}-scf-$(date +%F)}"
WORK_DIR="${WORK_DIR:-${HOME}/work/${RUN_NAME}}"
QE_BIN_DIR="${QE_BIN_DIR:-${HOME}/program/q-e-7.6/bin}"
OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"

if [[ ! "${MATERIAL_LABEL}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Error: MATERIAL_LABEL must contain only letters, digits, _ or -." >&2
    exit 2
fi

if [[ ! -f "${ZIP_FILE}" ]]; then
    echo "Error: input ZIP file not found: ${ZIP_FILE}" >&2
    exit 2
fi

if [[ ! -x "${QE_BIN_DIR}/pw.x" ]]; then
    echo "Error: QE executable not found or not executable: ${QE_BIN_DIR}/pw.x" >&2
    exit 2
fi

QE_SOURCE_DIR="$(cd "${QE_BIN_DIR}/.." && pwd)"
QE_SOURCE_REVISION="$(git -C "${QE_SOURCE_DIR}" describe --tags --always --dirty 2>/dev/null || echo unknown)"

if ! command -v unzip >/dev/null 2>&1; then
    echo "Error: unzip command was not found. Install the 'unzip' package first." >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 command was not found; it is required to validate the ZIP archive." >&2
    exit 2
fi

if ! python3 "${SCRIPT_DIR}/validate_qe_zip.py" "${ZIP_FILE}"; then
    exit 2
fi

if [[ -e "${WORK_DIR}" ]]; then
    echo "Error: work directory already exists: ${WORK_DIR}" >&2
    echo "Use a different RUN_NAME or WORK_DIR; do not overwrite a previous run." >&2
    exit 2
fi

echo "Material label: ${MATERIAL_LABEL}"
echo "Input ZIP: ${ZIP_FILE}"
echo "Work directory: ${WORK_DIR}"
echo "QE executable: ${QE_BIN_DIR}/pw.x"
echo "OpenMP threads: ${OMP_NUM_THREADS}"

mkdir -p "${WORK_DIR}"
cp -p "${ZIP_FILE}" "${WORK_DIR}/PWscf.zip"
(
    cd "${WORK_DIR}"
    unzip -q PWscf.zip
)

CALC_DIR="${WORK_DIR}/PWscf"
if [[ ! -f "${CALC_DIR}/pwscf.in" ]]; then
    echo "Error: pwscf.in was not found after extracting the ZIP." >&2
    exit 2
fi

QE_PREFIX="$(qe_control_value "${CALC_DIR}/pwscf.in" prefix)"
QE_PREFIX="${QE_PREFIX:-aiida}"
QE_OUTDIR="$(qe_control_value "${CALC_DIR}/pwscf.in" outdir)"
QE_OUTDIR="${QE_OUTDIR:-./out/}"
QE_PSEUDO_DIR="$(qe_control_value "${CALC_DIR}/pwscf.in" pseudo_dir)"
QE_PSEUDO_DIR="${QE_PSEUDO_DIR:-./pseudo/}"
PSEUDO_DIR_PATH="$(qe_outdir_path "${CALC_DIR}" "${QE_PSEUDO_DIR}")"
SAVE_DIR="$(qe_outdir_path "${CALC_DIR}" "${QE_OUTDIR}")/${QE_PREFIX}.save"

mapfile -t PSEUDOPOTENTIAL_FILES < <(qe_pseudopotential_files "${CALC_DIR}/pwscf.in")
if (( ${#PSEUDOPOTENTIAL_FILES[@]} == 0 )); then
    echo "Error: no pseudopotentials were found in the ATOMIC_SPECIES card." >&2
    exit 2
fi

for pseudopotential in "${PSEUDOPOTENTIAL_FILES[@]}"; do
    if [[ ! -f "${PSEUDO_DIR_PATH}/${pseudopotential}" ]]; then
        echo "Error: pseudopotential listed in pwscf.in was not found: ${PSEUDO_DIR_PATH}/${pseudopotential}" >&2
        exit 2
    fi
done

{
    echo "run_name=${RUN_NAME}"
    echo "material_label=${MATERIAL_LABEL}"
    echo "started_at=$(date --iso-8601=seconds)"
    echo "hostname=$(hostname)"
    echo "input_zip_sha256=$(sha256sum "${WORK_DIR}/PWscf.zip" | awk '{print $1}')"
    echo "qe_executable=${QE_BIN_DIR}/pw.x"
    echo "qe_prefix=${QE_PREFIX}"
    echo "qe_outdir=${QE_OUTDIR}"
    echo "qe_pseudo_dir=${QE_PSEUDO_DIR}"
    echo "qe_source_revision=${QE_SOURCE_REVISION}"
    echo "omp_num_threads=${OMP_NUM_THREADS}"
} > "${WORK_DIR}/run-metadata.txt"

cd "${CALC_DIR}"
export OMP_NUM_THREADS
export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Starting SCF calculation..."
if ! "${QE_BIN_DIR}/pw.x" -in pwscf.in > scf.out 2>&1; then
    echo "Error: pw.x exited with a non-zero status. See ${CALC_DIR}/scf.out" >&2
    exit 1
fi

if ! grep -q "JOB DONE" scf.out; then
    echo "Error: pw.x exited with status 0 but JOB DONE was not found in scf.out." >&2
    exit 1
fi

if [[ ! -d "${SAVE_DIR}" ]]; then
    echo "Error: SCF restart data was not created: ${SAVE_DIR}" >&2
    exit 1
fi

{
    echo
    echo "finished_at=$(date --iso-8601=seconds)"
    grep -F "total energy" scf.out | tail -n 1 || true
    grep -i "Fermi" scf.out | tail -n 1 || true
    grep "number of Kohn-Sham states" scf.out | tail -n 1 || true
    echo "result=success"
} >> "${WORK_DIR}/run-metadata.txt"

echo "SCF calculation completed successfully."
echo "SCF output: ${CALC_DIR}/scf.out"
echo "Run metadata: ${WORK_DIR}/run-metadata.txt"
