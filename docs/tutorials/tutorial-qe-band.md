# QEバンド構造・PDOS計算チュートリアル

- 元資料: `tutorial_qe_band.pdf`
- 対象例: MgB₂
- 整理日: 2026-11-17

> **注意:** キュー名（`S24hdd`）、QEの配置先（`~/program/q-e/`）、実行コア数（`24`）、VESTA・XCrySDenの配置先は、研究室の計算環境に依存する。実行前に自分の環境に合わせて確認する。

## 1. Quantum ESPRESSOのインストール

Quantum ESPRESSO（QE）は第一原理計算プログラムである。QE公式サイトとGitリポジトリは以下。

- <https://www.quantum-espresso.org/>
- <https://gitlab.com/QEF/q-e>

```bash
cd ~/program/
git clone https://gitlab.com/QEF/q-e.git
cd q-e

export LANG=C
./configure LANG=C --enable-openmp
make pw pp
```

このチュートリアルでは、主に以下の実行ファイルを使う。

- `pw.x`: SCF、バンド、NSCF計算
- `bands.x`: バンド計算の結果を後処理する
- `projwfc.x`: PDOSを計算する
- `sumpdos.x`: 原子・軌道ごとのPDOSを集計する
- `fermi_velocity.x`: フェルミ面可視化に用いるデータを生成する

## 2. 構造データを探す

結晶構造ファイル（CIF）は、Crystallography Open Database（COD）などから取得する。

- COD: <http://www.crystallography.net/cod/search.html>
- 例: chemical formula (in Hill notation) に `B2 Mg` を入力して検索する。

取得したCIFはVESTAで確認できる。

```bash
/home/app/VESTA-gtk2/VESTA ~/Downloads/1000026.cif
```

QE入力ファイルの作成やCIFのサーバーへの転送は、この元チュートリアルではブラウザや `scp` で行う。

## 3. 計算入力一式をサーバーへ配置する

`PWscf.zip` をサーバーに転送し、物質ごとの作業ディレクトリで展開する。ZIPには少なくとも `pwscf.in` が含まれることを想定する。

```bash
# ローカルPCからの例
scp /mnt/c/Users/kawam/Downloads/PWscf.zip nordstrom:~/

# サーバー上での例
scp ~/Downloads/PWscf.zip nordstrom:~/
mkdir -p ~/work/MgB2/
mv ~/Downloads/PWscf.zip ~/work/MgB2/
cd ~/work/MgB2/
unzip PWscf.zip
cd PWscf/
```

## 4. SCF計算

`scf.sh` を作成し、PBSへ投入する。

```bash
nano scf.sh
```

```bash
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V
cd ${PBS_O_WORKDIR}
source ~/.bashrc
export OMP_NUM_THREADS=1
mpiexec -np 24 ~/program/q-e/bin/pw.x -nk 24 -in pwscf.in > scf.out 2>&1
```

```bash
qsub scf.sh
```

計算終了後、`scf.out` を確認する。後続のバンド・PDOS計算では、Kohn–Sham状態数とフェルミ準位を参照する。

```bash
grep "number of Kohn-Sham states=" scf.out
grep Fermi scf.out
```

## 5. バンド構造計算

### 5.1 `band.in` の作成

SCF用入力を複製し、計算種別を `bands` に変更する。`nbnd` は表示したい非占有バンドも含めるために設定する。この例では `20` を使っているが、物質や目的に応じて決める必要がある。

```bash
cp pwscf.in band.in
nano band.in
```

```text
calculation = "bands"
nbnd = 20
```

SCFで用いた自動k点メッシュは、バンド構造用の高対称k点経路へ置き換える。

```text
K_POINTS automatic
16 16 12 0 0 0
```

XCrySDenを使い、`pwscf.in` からk点パスを作成して `kp.pwscf` として保存する。

```bash
/home/app/xcrysden-1.5.60-bin-semishared/xcrysden --pwi pwscf.in
```

作成したk点パスを `band.in` に追記する。

```bash
cat kp.pwscf >> band.in
```

### 5.2 `bands.x` 用入力の作成

```bash
nano band_plot.in
```

```text
&BANDS
  outdir = "./out/"
  prefix = "aiida"
/
```

### 5.3 バンド計算の投入

SCF用スクリプトを複製して `band.sh` を作成し、`pw.x` と `bands.x` を順に実行する。

```bash
cp scf.sh band.sh
nano band.sh
```

```bash
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V
#PBS -o temp.txt
cd ${PBS_O_WORKDIR}
source ~/.bashrc
export OMP_NUM_THREADS=1
mpiexec -np 24 ~/program/q-e/bin/pw.x -nk 24 -in band.in > band.out 2>&1
mpiexec -np 24 ~/program/q-e/bin/bands.x -nk 24 -in band_plot.in > band_plot.out 2>&1
```

```bash
qsub band.sh
```

### 5.4 バンド図の作成

SCF出力からフェルミ準位を確認する。

```bash
grep Fermi scf.out
```

元資料の例ではフェルミ準位 `7.5143 eV` を用い、gnuplotでエネルギーをフェルミ準位基準に移して描画する。

```gnuplot
plot "bands.out.gnu" u 1:($2-7.5143) w l, 0
```

`7.5143` はMgB₂のこの計算条件での例であり、他の計算に固定してはならない。実際には各 `scf.out` から抽出した値を使う。

## 6. PDOS計算

### 6.1 `nscf.in` と `pdos.in` の作成

SCF用入力を複製し、計算種別を `nscf` に変更する。

```bash
cp pwscf.in nscf.in
nano nscf.in
```

```text
calculation = "nscf"
nbnd = 20
occupations = "tetrahedra_opt"
```

`pdos.in` を作成する。

```bash
nano pdos.in
```

```text
&PROJWFC
  outdir = "./out/"
  prefix = "aiida"
  emin = 0
  emax = 15
  deltae = 0.02
/
```

### 6.2 PDOS計算の投入

`pdos.sh` を作成し、NSCF計算、PDOS計算、フェルミ面用データ生成を順に実行する。

```bash
cp scf.sh pdos.sh
nano pdos.sh
```

```bash
#!/bin/bash
#PBS -q S24hdd
#PBS -j oe
#PBS -V
#PBS -o temp.txt
cd ${PBS_O_WORKDIR}
source ~/.bashrc
export OMP_NUM_THREADS=1
mpiexec -np 24 ~/program/q-e/bin/pw.x -nk 24 -in nscf.in > nscf.out 2>&1
mpiexec -np 24 ~/program/q-e/bin/projwfc.x -nk 24 -in pdos.in > pdos.out 2>&1
mpiexec -np 1 ~/program/q-e/bin/fermi_velocity.x -nk 1 -in nscf.in 2>&1
```

```bash
qsub pdos.sh
```

### 6.3 原子・軌道別PDOSの集計と描画

MgB₂の例では、ホウ素のs軌道・p軌道、マグネシウムの寄与をそれぞれ集計する。

```bash
~/program/q-e/bin/sumpdos.x aiida.*B*s* > pdos_B2s.dat
~/program/q-e/bin/sumpdos.x aiida.*B*p* > pdos_B2p.dat
~/program/q-e/bin/sumpdos.x aiida.*Mg* > pdos_Mg.dat
```

gnuplotで、全DOSと各PDOSをフェルミ準位基準で描画する。

```gnuplot
plot "aiida.pdos_tot" u ($1-7.5143):2 w l, \
     "pdos_B2s.dat" u ($1-7.5143):2 w l, \
     "pdos_B2p.dat" u ($1-7.5143):2 w l, \
     "pdos_Mg.dat" u ($1-7.5143):2 w l
```

## 7. フェルミ面の可視化（発展）

`fermi_velocity.x` が生成するファイルをFermiSurferで開く。

```bash
fermisurfer out/aiida_vfermi.frmsf
```

この処理はGUIの将来拡張候補とし、最初のMVPには含めない。

## GUI化との対応

このチュートリアルは、GUIでは次の一つのワークフローとして扱う。

```text
入力ZIPのアップロード
  → SCF計算
  → バンド入力・k点パスの準備
  → バンド計算・バンド図表示
  → NSCF・PDOS計算（任意）
  → PDOS表示・結果ダウンロード
```

入力ZIP方式は、`pwscf.in` の完全自動生成を最初から扱わずに、ジョブ管理と結果理解のGUIを検証できるため、初期MVPの候補である。
