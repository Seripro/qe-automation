#!/bin/bash

# ==========================================
# 1. ディレクトリとファイルの準備
# ==========================================
DIR_NAME="Al"
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

echo "計算おわり"