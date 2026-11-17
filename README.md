# Quantum ESPRESSO Web GUI 卒業研究

Quantum ESPRESSO（QE）をWebブラウザから操作し、第一原理計算の実行と結果の理解を支援するGUIを開発する卒業研究用リポジトリです。

現時点では、QEのバンド構造・PDOS計算を自動化するスクリプトと、Webアプリケーションの要件草案があります。物理の学習、計算実験、設計判断、実装を同じリポジトリに蓄積します。

## このリポジトリの読み方

- `docs/physics/`: 学習した物理とQEの基礎。確定知識・仮説・疑問を区別する。
- `docs/experiments/`: 実行した計算、入力条件、結果、エラー、考察。
- `docs/decisions/`: 研究スコープや設計に関する判断記録（ADR）。
- `docs/templates/`: 各記録のテンプレート。
- `docs/tutorials/`: 研究室チュートリアルを整理した実行手順。
- `docs/gui-workflow-spec.md`: チュートリアルを基にしたGUIのMVP仕様案。
- `docs/milestones.md`: MVPまでの作業段階と完了条件。
- `docs/requirements.md`: GUIの機能要件と未決定事項の整理。
- `scripts/`: 既存のQE自動計算スクリプト。
- `webapp/`: Webアプリケーションの要件および今後の実装。
- `memo/`: 整理前の過去メモ。

最初に読む資料は、[マイルストーン](docs/milestones.md)、[学習ロードマップ](docs/physics/00-learning-roadmap.md)、[第一原理計算とDFT](docs/physics/01-first-principles-and-dft.md)、[QEバンド構造・PDOS計算チュートリアル](docs/tutorials/tutorial-qe-band.md)、[GUIワークフロー仕様案](docs/gui-workflow-spec.md)、[要件の整理](docs/requirements.md) です。

## 記録時の約束

- 未確認の内容は「確定した知識」として記録しない。
- 計算の正常終了と、物理的に妥当な結果であることを区別する。
- 重要な研究方針や設計判断は、相談後に `docs/decisions/` へ採用として記録する。
- QEの仕様に関わる内容は、必要に応じて公式ドキュメントや使用したバージョンを併記する。

## 既存スクリプトの実行手順

以下は大学計算サーバーでの既存スクリプトの使い方です。キュー名、QEの実行パス、MKLのパスなどは特定環境に依存します。

### k点パスを手動で決める場合

1. ~/DownloadsにPWscf.zipを配置
2. qe1.sh, qe2.shのDIR_NAMEを計算したい物質名に変更
3. nohup bash qe1.sh > run1.log 2>&1 &
4. PWscfディレクトリで/home/app/xcrysden-1.5.60-bin-semishared/xcrysden --pwi pwscf.inを実行
5. nohup bash qe2.sh > run2.log 2>&1 &

### k点パスをSeeK-pathで自動で決める場合

1. ~/DownloadsにPWscf.zipを配置
2. qe_auto_kp.shのDIR_NAMEを計算したい物質名に変更
3. bash run.shを実行

### コマンド一覧

qstat
qdel
jobs
kill %1
