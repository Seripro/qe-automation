#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# 1. ディレクトリとファイルの準備
# ==========================================
DIR_NAME="Na"
WORK_DIR="$HOME/work/${DIR_NAME}"
ZIP_FILE="${1:-$HOME/Downloads/PWscf.zip}"

echo "${DIR_NAME}の計算"
mkdir -p "$WORK_DIR"

if [ ! -f "$ZIP_FILE" ]; then
    echo "Error: ZIP file not found: $ZIP_FILE" >&2
    exit 1
fi

cp "$ZIP_FILE" "$WORK_DIR/PWscf.zip"
cd "$WORK_DIR"
unzip -o PWscf.zip
cd PWscf/

# ==========================================
# 2. SCF計算 (Self-Consistent Field)
# ==========================================
cat << 'EOF' > scf.sh
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V 
cd ${PBS_O_WORKDIR}
source ~/.bashrc

# 決定的な解決策：見つかった2021.3.0のMKLパスを明示的に追加
export LD_LIBRARY_PATH="/opt/intel/oneapi/mkl/2021.3.0/lib/intel64:$LD_LIBRARY_PATH"
export OMP_NUM_THREADS=1

mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 24 ~/program/q-e/bin/pw.x -nk 24 -in pwscf.in > scf.out 2>&1
EOF

echo "Submitting SCF calculation..."
qsub scf.sh

echo "Waiting for SCF calculation to finish..."
while ! grep -q "JOB DONE" scf.out 2>/dev/null; do
    sleep 10
done
echo "SCF calculation finished!"

KOHN_SHAM_STATES=$(grep 'number of Kohn-Sham states=' scf.out | awk '{print $NF}' | tail -n 1)
if [ -z "$KOHN_SHAM_STATES" ]; then
    echo "Error: Could not extract number of Kohn-Sham states from scf.out." >&2
    exit 1
fi
NBND=$((KOHN_SHAM_STATES * 2))
echo "Using nbnd=${NBND} (2x number of Kohn-Sham states: ${KOHN_SHAM_STATES})"

# pwscf.in をコピーして band.in を作成
cp pwscf.in band.in
sed -i 's/calculation.*/calculation = "bands"/' band.in
sed -i "/&SYSTEM/a \\  nbnd = ${NBND}" band.in
sed -i '/K_POINTS automatic/{N;d;}' band.in

echo "xcrysden前の計算おわり"

# ==========================================
# 1.5. K点パスの自動生成 (SeeK-path)
# ==========================================
echo "Generating k-point path using SeeK-path..."

python3 "${SCRIPT_DIR}/generate_kpath.py" pwscf.in 20

if [ $? -ne 0 ] || [ ! -f kp.pwscf ]; then
    echo "Error: Failed to generate k-point path with SeeK-path." >&2
    echo "Make sure 'seekpath' and 'numpy' are installed: pip install seekpath numpy" >&2
    exit 1
fi

cat kp.pwscf >> band.in

echo "k点パス終わり"


cat << 'EOF' > band_plot.in
&BANDS
  outdir = "./out/"
  prefix = "aiida"
/
EOF

# ==========================================
# 2. バンド計算
# ==========================================
cat << 'EOF' > band.sh
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V
#PBS -o temp.txt

cd ${PBS_O_WORKDIR}
source ~/.bashrc

export LD_LIBRARY_PATH="/opt/intel/oneapi/mkl/2021.3.0/lib/intel64:$LD_LIBRARY_PATH"
export OMP_NUM_THREADS=1 

mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 24 ~/program/q-e/bin/pw.x -nk 24 -in band.in > band.out 2>&1
mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 24 ~/program/q-e/bin/bands.x -nk 24 -in band_plot.in > band_plot.out 2>&1
EOF

echo "Submitting Band calculation..."
qsub band.sh

echo "Waiting for Band calculation to finish..."
while [ ! -f bands.out.gnu ]; do
    sleep 10
done
sleep 5
echo "Band calculation finished!"

# ==========================================
# 3. バンド図のプロット
# ==========================================
FERMI=$(grep 'Fermi' scf.out | awk '{print $(NF-1)}')

if [ -z "$FERMI" ]; then
    echo "Error: Could not extract Fermi energy."
else
    echo "Fermi energy extracted: ${FERMI} eV"
    gnuplot << EOF
    set terminal pngcairo
    set output "bands.png"
    set yrange [-15:15]
    Ef = ${FERMI}
    plot "bands.out.gnu" u 1:(\$2-Ef) w l lc rgb "blue" title "Bands", 0 lc rgb "black" dt 2 title "Fermi level"
EOF
    echo "Generated bands.png"
fi

# ==========================================
# 4. PDOS計算の準備
# ==========================================
KOHN_SHAM_STATES=$(grep 'number of Kohn-Sham states=' scf.out | awk '{print $NF}' | tail -n 1)
NBND=$((KOHN_SHAM_STATES * 2))

cp pwscf.in nscf.in
sed -i 's/calculation.*/calculation = "nscf"/' nscf.in
sed -i "/&SYSTEM/a \\  nbnd = ${NBND}" nscf.in
sed -i 's/occupations.*/occupations = "tetrahedra_opt"/' nscf.in

cat << 'EOF' > pdos.in
&PROJWFC
  outdir = "./out/"
  prefix = "aiida"
  deltae = 0.02
/
EOF

# ==========================================
# 5. PDOS計算
# ==========================================
cat << 'EOF' > pdos.sh
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V
#PBS -o temp.txt

cd ${PBS_O_WORKDIR}
source ~/.bashrc

export LD_LIBRARY_PATH="/opt/intel/oneapi/mkl/2021.3.0/lib/intel64:$LD_LIBRARY_PATH"
export OMP_NUM_THREADS=1

mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 24 ~/program/q-e/bin/pw.x -nk 24 -in nscf.in > nscf.out 2>&1
mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 24 ~/program/q-e/bin/projwfc.x -nk 24 -in pdos.in > pdos.out 2>&1
mpiexec -genv LD_LIBRARY_PATH "$LD_LIBRARY_PATH" -np 1 ~/program/q-e/bin/fermi_velocity.x -nk 1 -in nscf.in 2>&1
EOF

echo "Submitting PDOS calculation..."
qsub pdos.sh

echo "Waiting for PDOS calculation to finish..."
while ! grep -q "JOB DONE" pdos.out 2>/dev/null; do
    sleep 10
done
echo "PDOS calculation finished!"

# ==========================================
# 6. PDOSの集計とプロット (自動軌道抽出)
# ==========================================
echo "Processing PDOS files dynamically..."
PLOT_CMD="plot 'aiida.pdos_tot' u (\$1-Ef):2 w l lc rgb 'black' title 'Total'"
ELEMENTS=$(ls aiida.pdos_atm* 2>/dev/null | sed -n 's/.*(\([A-Za-z]*\))_wfc.*/\1/p' | sort -u)

for elem in $ELEMENTS; do
    for orb in s p d f; do
        # Bashエラーを防ぐため \( \) でエスケープ
        if ls aiida.pdos_atm*\(${elem}\)_wfc*\(${orb}\)* 1> /dev/null 2>&1; then
            echo "Found orbitals for ${elem}-${orb}, running sumpdos.x..."
            ~/program/q-e/bin/sumpdos.x aiida.pdos_atm*\(${elem}\)_wfc*\(${orb}\)* > "pdos_${elem}_${orb}.dat" 2>/dev/null
            PLOT_CMD="${PLOT_CMD}, 'pdos_${elem}_${orb}.dat' u (\$1-Ef):2 w l title '${elem}-${orb}'"
        fi
    done
done

gnuplot << EOF
set terminal pngcairo
set output "pdos.png"
set xrange [-15:15]
Ef = ${FERMI}
${PLOT_CMD}
EOF

echo "All tasks completed! (Generated bands.png and pdos.png)"