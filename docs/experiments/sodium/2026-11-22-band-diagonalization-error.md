# Naのバンド計算における対角化エラー

- 発生日: 2026-11-22
- 状態: 未解決（切り分け待ち）
- 対象物質: Na
- 実行経路: Web UI → API → SQLite待ち行列 → 直接実行ワーカー
- QE: 7.6、OpenMP 4スレッド

## 現象

Naの入力ZIPをWeb UIから投入したところ、SCF計算は完了したが、Band段階で失敗した。

```text
BAND_RUNNING exited with status 1
```

`band.out` の末尾では、高対称k点経路の122点中104点目を計算中に次のエラーが出た。

```text
Error in routine cdiaghg (70):
S matrix not positive definite
```

## 確認できた事実

- SCF段階は成功している。
- SeeK-pathはNaを体心立方（`cI`）として認識し、`Γ → H → N → Γ → P → H → P → N` の経路を生成した。
- 自動化スクリプトは元の`pwscf.in`を`band.in`へ複製し、`calculation = 'bands'`、`nbnd = 18`、生成した高対称k点経路を設定している。
- エラーはWeb UIそのものではなく、生成済み`band.in`をQEの`pw.x`で実行したときに生じた。

## 現時点の解釈

このエラーは、QEが一般化固有値問題を解く際の数値的な対角化失敗である。構造不正、擬ポテンシャル、カットオフ、`nbnd`、高対称k点経路、対角化法、QEの版・実行環境などが関係し得るため、現時点で単一の原因とは断定しない。

Materials CloudまたはCOD由来のZIPを用いる全利用者に必ず起きるとは限らない。ZIPに含まれるSCF入力に対して、アプリがBand用の設定を自動生成するため、同一の`band.in`・QE版・擬ポテンシャル・実行環境であれば、GUIの有無にかかわらず再現する事象である。

## 次の切り分け（提案中）

1. 元の`pwscf.in`と生成済み`band.in`を比較し、`ecutwfc`、`ecutrho`、擬ポテンシャル、`nbnd`、`K_POINTS`、`&ELECTRONS`を記録する。
2. `&ELECTRONS` の `diagonalization = 'cg'` を指定した別入力で、Band段階が通るかを確認する。
3. `nbnd`と高対称k点経路を一つずつ変え、エラー要因を切り分ける。
4. 原因と対処が再現可能になってから、アプリの自動再試行・利用者向けエラー表示の方針を検討する。

この時点では、アプリが全物質に`cg`を自動適用する変更は行わない。入力条件を自動変更する方針は、検証結果を基に別途相談する。
