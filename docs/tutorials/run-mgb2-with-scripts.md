# MgB₂のバンド構造・PDOSをスクリプトで計算する手順

- 状態: 実行検証済み（2026-11-21、物理的妥当性は未検証）
- 更新日: 2026-11-21

## 目的

Siで検証したSCF → バンド構造 → NSCF/PDOSの流れを、MgB₂の入力一式に対して実行する。各段階で前段の出力を確認してから次へ進むため、計算失敗と物理的妥当性の確認を区別できる。

## 事前に用意するもの

- MgB₂の結晶構造に基づく `PWscf.zip`
  - `PWscf/pwscf.in`
  - `pwscf.in` の `ATOMIC_SPECIES` で指定したMg用・B用の擬ポテンシャル
- QEの `pw.x`、`bands.x`、`projwfc.x`、`sumpdos.x`
- Pythonの `numpy`、`seekpath`、`matplotlib`

`PWscf.zip` はMaterials Cloud QE input generatorなどで作成する。入力の取得だけでは計算条件の物理的妥当性は保証されないため、擬ポテンシャル、カットオフ、k点メッシュは記録し、必要に応じて収束試験を行う。

SCFスクリプトは展開前にZIPを検査する。`PWscf/pwscf.in` を含まないZIP、`PWscf/` 外へ展開するパス、シンボリックリンク、暗号化エントリ、既定の上限（1,000ファイルまたは展開後2 GiB）を超えるZIPは拒否する。

## 実行

計算サーバー上で、入力ZIPを `~/qe-inputs/MgB2/PWscf.zip` に置く。入力配置と一コマンドCLIの方針は [ADR-0004](../decisions/0004-stage-cli-workflow-before-pbs.md) を参照する。

```bash
make run MATERIAL=MgB2
```

このコマンドは、固有の実行ディレクトリを作成し、SCFが成功した場合だけバンド計算へ、さらに成功した場合だけNSCF・PDOS計算へ進む。各段階の失敗時には後続を実行せず停止する。

既定では `~/.venvs/qe-tools-v1` を自動的に使うため、実行前に仮想環境を有効化する必要はない。別の仮想環境を使う場合は、有効化してから実行するか、`QE_TOOLS_VENV` を指定する。

デフォルトでは `pwscf.in` の `ATOMIC_SPECIES` にあるMgとBの両方をPDOSへ集計する。Mgだけ、またはBだけを描きたい場合は、互換用の `PDOS_ELEMENT` または複数指定用の `PDOS_ELEMENTS` を指定する。

```bash
PDOS_ELEMENTS=Mg,B make run MATERIAL=MgB2
```

## 成功時の確認

- SCF: `scf.out` に `JOB DONE` があり、`pwscf.in` の `outdir` と `prefix` に対応する再始動データ `<prefix>.save/` がある。
- バンド: `band.out`、`band_plot.out`、`bands.out.gnu`、`bands.png` がある。
- PDOS: `nscf.out`、`pdos.out`、`<prefix>.pdos_tot`、`pdos_Mg_*.dat`、`pdos_B_*.dat`、`pdos.png` がある。

`bands.png` と `pdos.png` が作成されたことはプログラム上の成功を示すだけである。MgB₂の物理的な解釈は、フェルミ準位近傍のバンド、Mg・Bの軌道寄与、計算条件の収束性を別途確認して行う。
