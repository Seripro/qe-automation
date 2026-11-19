#!/usr/bin/env bash
#
# mdx-server 上でシリコンの基準入力を用いて SCF を直接実行するスクリプト。
# scripts/qe1.sh の「入力準備 → SCF → 出力確認」を、PBS/MPI を使わない
# OpenMP 実行用に移植したもの。既存の qe1.sh, qe2.sh は変更しない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

if ! command -v unzip >/dev/null 2>&1; then
    echo "Error: unzip command was not found. Install the 'unzip' package first." >&2
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

if [[ ! -f "${CALC_DIR}/pseudo/Si.pbesol-n-rrkjus_psl.1.0.0.UPF" ]]; then
    echo "Error: expected Si pseudopotential was not found after extracting the ZIP." >&2
    exit 2
fi

{
    echo "run_name=${RUN_NAME}"
    echo "material_label=${MATERIAL_LABEL}"
    echo "started_at=$(date --iso-8601=seconds)"
    echo "hostname=$(hostname)"
    echo "input_zip_sha256=$(sha256sum "${WORK_DIR}/PWscf.zip" | awk '{print $1}')"
    echo "qe_executable=${QE_BIN_DIR}/pw.x"
    echo "qe_version=$(${QE_BIN_DIR}/pw.x -version 2>&1 | head -n 1 || true)"
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

if [[ ! -d out/aiida.save ]]; then
    echo "Error: SCF output directory out/aiida.save was not created." >&2
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
