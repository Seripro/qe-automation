#!/usr/bin/env bash
#
# mdx-server 上で、完了済みSCFの結果を使ってNSCF・PDOS計算を直接実行する。
# scripts/qe2.sh のPDOS処理を、PBS/MPIを使わないOpenMP実行用に移植したもの。

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qe_input_utils.sh
source "${SCRIPT_DIR}/qe_input_utils.sh"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <SCF run directory>" >&2
    echo "Example: $0 \"$HOME/work/Si-scf-2026-11-19-run1\"" >&2
    exit 2
fi

SCF_RUN_DIR="$1"
CALC_DIR="${SCF_RUN_DIR}/PWscf"
QE_BIN_DIR="${QE_BIN_DIR:-${HOME}/program/q-e-7.6/bin}"
OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"

for required_file in "${CALC_DIR}/pwscf.in" "${CALC_DIR}/scf.out"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "Error: required SCF file was not found: ${required_file}" >&2
        exit 2
    fi
done

if ! grep -q "JOB DONE" "${CALC_DIR}/scf.out"; then
    echo "Error: SCF output does not contain JOB DONE: ${CALC_DIR}/scf.out" >&2
    exit 2
fi

QE_PREFIX="$(qe_control_value "${CALC_DIR}/pwscf.in" prefix)"
QE_PREFIX="${QE_PREFIX:-aiida}"
QE_OUTDIR="$(qe_control_value "${CALC_DIR}/pwscf.in" outdir)"
QE_OUTDIR="${QE_OUTDIR:-./out/}"
SAVE_DIR="$(qe_outdir_path "${CALC_DIR}" "${QE_OUTDIR}")/${QE_PREFIX}.save"

if [[ ! -d "${SAVE_DIR}" ]]; then
    echo "Error: SCF restart data was not found: ${SAVE_DIR}" >&2
    exit 2
fi

for executable in pw.x projwfc.x sumpdos.x; do
    if [[ ! -x "${QE_BIN_DIR}/${executable}" ]]; then
        echo "Error: QE executable not found or not executable: ${QE_BIN_DIR}/${executable}" >&2
        exit 2
    fi
done

if ! python3 -c 'import matplotlib, numpy' >/dev/null 2>&1; then
    echo "Error: Python packages matplotlib and numpy are required to generate pdos.png." >&2
    echo "Activate the qe-tools virtual environment, then rerun this script." >&2
    exit 2
fi

TOTAL_DOS_FILE="${QE_PREFIX}.pdos_tot"
for output_file in nscf.in nscf.out pdos.in pdos.out "${TOTAL_DOS_FILE}" pdos.png; do
    if [[ -e "${CALC_DIR}/${output_file}" ]]; then
        echo "Error: refusing to overwrite existing file: ${CALC_DIR}/${output_file}" >&2
        exit 2
    fi
done

KOHN_SHAM_STATES="$(awk -F= '/number of Kohn-Sham states/ {gsub(/ /, "", $2); states=$2} END {print states}' "${CALC_DIR}/scf.out")"
if [[ ! "${KOHN_SHAM_STATES}" =~ ^[0-9]+$ ]]; then
    echo "Error: could not extract the number of Kohn-Sham states from scf.out." >&2
    exit 2
fi

NBND="${NBND:-$((KOHN_SHAM_STATES * 2))}"
if [[ ! "${NBND}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: NBND must be a positive integer." >&2
    exit 2
fi

FERMI_ENERGY="$(awk '/the Fermi energy is/ {value=$(NF-1)} END {print value}' "${CALC_DIR}/scf.out")"
if [[ -z "${FERMI_ENERGY}" ]]; then
    echo "Error: could not extract the Fermi energy from scf.out." >&2
    exit 2
fi

PDOS_ELEMENTS="${PDOS_ELEMENTS:-${PDOS_ELEMENT:-}}"
if [[ -z "${PDOS_ELEMENTS}" ]]; then
    PDOS_ELEMENTS="$(qe_atomic_species_labels "${CALC_DIR}/pwscf.in" | paste -sd, -)"
fi
if [[ -z "${PDOS_ELEMENTS}" ]]; then
    echo "Error: no elements were found in the ATOMIC_SPECIES card." >&2
    exit 2
fi
IFS=',' read -r -a PDOS_ELEMENT_LIST <<< "${PDOS_ELEMENTS}"

echo "SCF directory: ${SCF_RUN_DIR}"
echo "QE executable directory: ${QE_BIN_DIR}"
echo "OpenMP threads: ${OMP_NUM_THREADS}"
echo "Using nbnd: ${NBND}"
echo "PDOS elements: ${PDOS_ELEMENTS}"
echo "Fermi energy: ${FERMI_ENERGY} eV"
echo "QE prefix: ${QE_PREFIX}"
echo "QE outdir: ${QE_OUTDIR}"

cd "${CALC_DIR}"
cp pwscf.in nscf.in
sed -i "s/^[[:space:]]*calculation[[:space:]]*=.*/  calculation = 'nscf'/" nscf.in
sed -i "/^[[:space:]]*nbnd[[:space:]]*=/d" nscf.in
sed -i "/^[[:space:]]*occupations[[:space:]]*=/d" nscf.in
sed -i "/^[[:space:]]*&SYSTEM/a\\  nbnd = ${NBND}" nscf.in
sed -i "/^[[:space:]]*&SYSTEM/a\\  occupations = 'tetrahedra_opt'" nscf.in

cat > pdos.in <<EOF
&PROJWFC
  outdir = "${QE_OUTDIR}"
  prefix = "${QE_PREFIX}"
  deltae = 0.02
/
EOF

export OMP_NUM_THREADS
export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Starting NSCF calculation..."
PDOS_STARTED_AT="$(date --iso-8601=seconds)"
if ! "${QE_BIN_DIR}/pw.x" -in nscf.in > nscf.out 2>&1; then
    echo "Error: pw.x exited with a non-zero status. See ${CALC_DIR}/nscf.out" >&2
    exit 1
fi

if ! grep -q "JOB DONE" nscf.out; then
    echo "Error: pw.x exited with status 0 but JOB DONE was not found in nscf.out." >&2
    exit 1
fi

echo "Calculating projected DOS with projwfc.x..."
if ! "${QE_BIN_DIR}/projwfc.x" -in pdos.in > pdos.out 2>&1; then
    echo "Error: projwfc.x exited with a non-zero status. See ${CALC_DIR}/pdos.out" >&2
    exit 1
fi

if ! grep -q "JOB DONE" pdos.out; then
    echo "Error: projwfc.x exited with status 0 but JOB DONE was not found in pdos.out." >&2
    exit 1
fi

if [[ ! -f "${TOTAL_DOS_FILE}" ]]; then
    echo "Error: ${TOTAL_DOS_FILE} was not generated." >&2
    exit 1
fi

component_arguments=()
for element in "${PDOS_ELEMENT_LIST[@]}"; do
    for orbital in s p d f; do
        orbital_files=("${QE_PREFIX}".pdos_atm*"(${element})"_wfc*"(${orbital})"*)
        if (( ${#orbital_files[@]} == 0 )); then
            continue
        fi

        component_file="pdos_${element}_${orbital}.dat"
        "${QE_BIN_DIR}/sumpdos.x" "${orbital_files[@]}" > "${component_file}"
        component_arguments+=(--component "${component_file}")
    done
done

if (( ${#component_arguments[@]} == 0 )); then
    echo "Error: no orbital-resolved PDOS files were found for: ${PDOS_ELEMENTS}" >&2
    exit 1
fi

python3 "${SCRIPT_DIR}/plot_pdos.py" "${TOTAL_DOS_FILE}" \
    --fermi "${FERMI_ENERGY}" \
    "${component_arguments[@]}" \
    --output pdos.png

{
    echo
    echo "pdos_started_at=${PDOS_STARTED_AT}"
    echo "pdos_finished_at=$(date --iso-8601=seconds)"
    echo "pdos_nbnd=${NBND}"
    echo "pdos_elements=${PDOS_ELEMENTS}"
    echo "pdos_fermi_energy_ev=${FERMI_ENERGY}"
    echo "pdos_result=success"
} >> "${SCF_RUN_DIR}/run-metadata.txt"

echo "PDOS calculation completed successfully."
echo "NSCF output: ${CALC_DIR}/nscf.out"
echo "PDOS output: ${CALC_DIR}/pdos.out"
echo "PDOS plot: ${CALC_DIR}/pdos.png"
