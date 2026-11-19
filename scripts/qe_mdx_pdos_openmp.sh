#!/usr/bin/env bash
#
# mdx-server 上で、完了済みSCFの結果を使ってNSCF・PDOS計算を直接実行する。
# scripts/qe2.sh のPDOS処理を、PBS/MPIを使わないOpenMP実行用に移植したもの。

set -euo pipefail
shopt -s nullglob

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <SCF run directory>" >&2
    echo "Example: $0 \"$HOME/work/Si-scf-2026-11-19-run1\"" >&2
    exit 2
fi

SCF_RUN_DIR="$1"
CALC_DIR="${SCF_RUN_DIR}/PWscf"
QE_BIN_DIR="${QE_BIN_DIR:-${HOME}/program/q-e-7.6/bin}"
OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"
PDOS_ELEMENT="${PDOS_ELEMENT:-Si}"

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

if [[ ! -d "${CALC_DIR}/out/aiida.save" ]]; then
    echo "Error: SCF restart data was not found: ${CALC_DIR}/out/aiida.save" >&2
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

for output_file in nscf.in nscf.out pdos.in pdos.out aiida.pdos_tot pdos.png; do
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

echo "SCF directory: ${SCF_RUN_DIR}"
echo "QE executable directory: ${QE_BIN_DIR}"
echo "OpenMP threads: ${OMP_NUM_THREADS}"
echo "Using nbnd: ${NBND}"
echo "PDOS element: ${PDOS_ELEMENT}"
echo "Fermi energy: ${FERMI_ENERGY} eV"

cd "${CALC_DIR}"
cp pwscf.in nscf.in
sed -i "s/^[[:space:]]*calculation[[:space:]]*=.*/  calculation = 'nscf'/" nscf.in
sed -i "/^[[:space:]]*&SYSTEM/a\\  nbnd = ${NBND}" nscf.in
sed -i "s/^[[:space:]]*occupations[[:space:]]*=.*/  occupations = 'tetrahedra_opt'/" nscf.in

cat > pdos.in <<'EOF'
&PROJWFC
  outdir = "./out/"
  prefix = "aiida"
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

if [[ ! -f aiida.pdos_tot ]]; then
    echo "Error: aiida.pdos_tot was not generated." >&2
    exit 1
fi

component_arguments=()
for orbital in s p d f; do
    orbital_files=(aiida.pdos_atm*"(${PDOS_ELEMENT})"_wfc*"(${orbital})"*)
    if (( ${#orbital_files[@]} == 0 )); then
        continue
    fi

    component_file="pdos_${PDOS_ELEMENT}_${orbital}.dat"
    "${QE_BIN_DIR}/sumpdos.x" "${orbital_files[@]}" > "${component_file}"
    component_arguments+=(--component "${component_file}")
done

if (( ${#component_arguments[@]} == 0 )); then
    echo "Error: no ${PDOS_ELEMENT} orbital-resolved PDOS files were found." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${SCRIPT_DIR}/plot_pdos.py" aiida.pdos_tot \
    --fermi "${FERMI_ENERGY}" \
    "${component_arguments[@]}" \
    --output pdos.png

{
    echo
    echo "pdos_started_at=${PDOS_STARTED_AT}"
    echo "pdos_finished_at=$(date --iso-8601=seconds)"
    echo "pdos_nbnd=${NBND}"
    echo "pdos_element=${PDOS_ELEMENT}"
    echo "pdos_fermi_energy_ev=${FERMI_ENERGY}"
    echo "pdos_result=success"
} >> "${SCF_RUN_DIR}/run-metadata.txt"

echo "PDOS calculation completed successfully."
echo "NSCF output: ${CALC_DIR}/nscf.out"
echo "PDOS output: ${CALC_DIR}/pdos.out"
echo "PDOS plot: ${CALC_DIR}/pdos.png"
