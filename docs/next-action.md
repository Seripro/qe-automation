# 次回の作業

- 更新日: 2026-11-19
- 状態: 進行中
- 参照タイミング: 研究作業を始めるときに、`AGENTS.md` の後で読む。

## 現在地

- フェーズ: シリコンを用いた初回の計算フロー検証（バンド図生成完了）
- 基準入力: `docs/experiments/silicon/input/PWscf.zip`
- 入力方針: 初回の SCF → バンド構造 → NSCF/PDOS 計算では、基準入力ZIPを変更しない（[ADR-0003](decisions/0003-use-materials-cloud-zip-as-silicon-baseline.md)）。
- 直近の確認: SCF出力を用いたバンド計算が正常終了し、SeeK-pathのk点経路、`bands.out.gnu`、フェルミ準位基準の `bands.png` を得た。詳細は [2026-11-19-band.md](experiments/silicon/2026-11-19-band.md)。

## 次の具体的な作業

### 1. NSCF・PDOS計算を実行する

目的は、SCF結果を用いて状態密度と原子・軌道別の寄与を計算し、PDOS図を得ること。

1. 既存の `qe2.sh` のNSCF・PDOS処理を確認する。
2. `mdx-server` 用にPBS・MPI依存を除いたNSCF・PDOS実行スクリプトを作成する。
3. `nscf.in` と `pdos.in` を生成し、`pw.x` と `projwfc.x` を実行する。
4. 全DOS・原子／軌道別PDOSデータを確認し、PDOS図を生成する。
5. 成功・失敗を問わず、実験記録を更新する。

## その後の予定

1. **PDOS計算**: `nscf.in`、`pdos.in`、`pdos.out`、原子・軌道別データ、`pdos.png` のつながりを確認する。
2. **実験記録の更新**: 各段階ごとに成功・失敗、実行条件、妥当性確認、次の課題を残す。

## 未解決・確認待ち

- `mdx-server` に残るDKMSパッケージの未完了状態を、計算環境の運用課題としていつ解消するか。
- 高対称k点パスをSeeK-pathで自動生成するための依存パッケージを、`mdx-server` にどう導入するか。

## 更新ルール

- 実験を終えるたびに「現在地」と「次の具体的な作業」だけを更新する。
- 詳細な条件、ログ、エラー、解釈はこのファイルに増やさず、`docs/experiments/` の実験記録へ残す。
- 採用済みの重要判断は、対応するADRを正とする。
