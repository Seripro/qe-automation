#!/usr/bin/env bash
#
# mdx-server 上で、完了済みSCFの結果を使ってバンド構造を直接実行する。
# scripts/qe1.sh と scripts/qe2.sh のバンド構造処理を、PBS/MPI を使わない
# OpenMP 実行用に移植したもの。

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <SCF run directory>" >&2
    echo "Example: $0 \"$HOME/work/Si-scf-2026-11-19-run1\"" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCF_RUN_DIR="$1"
CALC_DIR="${SCF_RUN_DIR}/PWscf"
QE_BIN_DIR="${QE_BIN_DIR:-${HOME}/program/q-e-7.6/bin}"
OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"
KPATH_POINTS="${KPATH_POINTS:-20}"

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

for executable in pw.x bands.x; do
    if [[ ! -x "${QE_BIN_DIR}/${executable}" ]]; then
        echo "Error: QE executable not found or not executable: ${QE_BIN_DIR}/${executable}" >&2
        exit 2
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 command was not found." >&2
    exit 2
fi

if ! python3 -c 'import numpy, seekpath' >/dev/null 2>&1; then
    echo "Error: Python packages numpy and seekpath are required to generate the k-point path." >&2
    echo "Install them, then rerun this script. No band calculation has been started." >&2
    exit 2
fi

for output_file in band.in kp.pwscf band_plot.in band.out band_plot.out bands.out.gnu bands.png; do
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
if [[ ! "${NBND}" =~ ^[0-9]+$ ]]; then
    echo "Error: NBND must be a positive integer." >&2
    exit 2
fi
if (( NBND < 1 )); then
    echo "Error: NBND must be at least 1." >&2
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
echo "Kohn-Sham states: ${KOHN_SHAM_STATES}"
echo "Using nbnd: ${NBND}"
echo "Fermi energy: ${FERMI_ENERGY} eV"
echo "K-point path points per segment: ${KPATH_POINTS}"

cd "${CALC_DIR}"
cp pwscf.in band.in
sed -i "s/^[[:space:]]*calculation[[:space:]]*=.*/  calculation = 'bands'/" band.in
sed -i "/^[[:space:]]*&SYSTEM/a\\  nbnd = ${NBND}" band.in
sed -i '/^[[:space:]]*K_POINTS[[:space:]]\+automatic/,+1d' band.in

echo "Generating the high-symmetry k-point path with SeeK-path..."
python3 "${SCRIPT_DIR}/generate_kpath.py" pwscf.in "${KPATH_POINTS}"
cat kp.pwscf >> band.in

cat > band_plot.in <<'EOF'
&BANDS
  outdir = "./out/"
  prefix = "aiida"
/
EOF

export OMP_NUM_THREADS
export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Starting band calculation..."
BAND_STARTED_AT="$(date --iso-8601=seconds)"
if ! "${QE_BIN_DIR}/pw.x" -in band.in > band.out 2>&1; then
    echo "Error: pw.x exited with a non-zero status. See ${CALC_DIR}/band.out" >&2
    exit 1
fi

if ! grep -q "JOB DONE" band.out; then
    echo "Error: pw.x exited with status 0 but JOB DONE was not found in band.out." >&2
    exit 1
fi

echo "Post-processing band data with bands.x..."
if ! "${QE_BIN_DIR}/bands.x" -in band_plot.in > band_plot.out 2>&1; then
    echo "Error: bands.x exited with a non-zero status. See ${CALC_DIR}/band_plot.out" >&2
    exit 1
fi

if [[ ! -f bands.out.gnu ]]; then
    echo "Error: bands.out.gnu was not generated." >&2
    exit 1
fi

if command -v gnuplot >/dev/null 2>&1; then
    gnuplot <<EOF
set terminal pngcairo
set output "bands.png"
set yrange [-15:15]
Ef = ${FERMI_ENERGY}
plot "bands.out.gnu" using 1:(\$2-Ef) with lines lc rgb "blue" title "Bands", \\
     0 with lines lc rgb "black" dt 2 title "Fermi level"
EOF
    echo "Generated band plot: ${CALC_DIR}/bands.png"
elif python3 -c 'import matplotlib' >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/plot_bands.py" bands.out.gnu \
        --fermi "${FERMI_ENERGY}" \
        --output bands.png
    echo "Generated band plot with Matplotlib: ${CALC_DIR}/bands.png"
else
    echo "Warning: neither gnuplot nor Python Matplotlib was found; bands.out.gnu was generated, but bands.png was skipped." >&2
fi

{
    echo
    echo "band_started_at=${BAND_STARTED_AT}"
    echo "band_finished_at=$(date --iso-8601=seconds)"
    echo "kohn_sham_states=${KOHN_SHAM_STATES}"
    echo "nbnd=${NBND}"
    echo "fermi_energy_ev=${FERMI_ENERGY}"
    echo "kpath_points_per_segment=${KPATH_POINTS}"
    echo "band_result=success"
} >> "${SCF_RUN_DIR}/run-metadata.txt"

echo "Band calculation completed successfully."
echo "Band output: ${CALC_DIR}/band.out"
echo "Band data: ${CALC_DIR}/bands.out.gnu"
