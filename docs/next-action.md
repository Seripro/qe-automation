# 次回の作業

- 更新日: 2026-11-22
- 状態: 進行中
- 参照タイミング: 研究作業を始めるときに、`AGENTS.md` の後で読む。

## 現在地

- フェーズ: CLI計算フロー検証（SiとMgB₂でSCF・バンド・PDOS完了）
- 基準入力: `docs/experiments/silicon/input/PWscf.zip`
- 入力方針: 初回の SCF → バンド構造 → NSCF/PDOS 計算では、基準入力ZIPを変更しない（[ADR-0003](decisions/0003-use-materials-cloud-zip-as-silicon-baseline.md)）。
- 直近の確認: NSCF・PDOS計算が正常終了し、全DOS・Si s/p成分の `pdos.png` を得た。詳細は [2026-11-19-pdos.md](experiments/silicon/2026-11-19-pdos.md)。
- 複数元素の確認: MgB₂でもSCF・バンド・NSCF・PDOSが正常終了し、Mg・BのPDOSを含む図を得た。詳細は [2026-11-21-band-pdos.md](experiments/mgb2/2026-11-21-band-pdos.md)。物理的妥当性は未検証。

## 次の具体的な作業

### 0. 一コマンドCLIの検証完了

- 採用方針は [ADR-0004](decisions/0004-stage-cli-workflow-before-pbs.md) を正とする。
- `~/qe-inputs/<material-label>/PWscf.zip` を入力配置規約とし、MgB₂で `make run MATERIAL=MgB2` によるSCF → バンド → PDOSの一回実行を確認した。
- 公開サービスでは、Webアプリの永続待ち行列とワーカーがmdx-server上で直接実行する。詳細は [ADR-0005](decisions/0005-use-application-queue-on-mdx.md) を正とする。

### 1. バックエンド初期実装の動作確認

SQLiteのジョブDB、匿名ブラウザCookie、アップロードAPI、直接実行ワーカーの初期実装を追加した。目的は、mdx-server上で依存関係を導入し、実計算を伴わないAPI確認から始めて段階的に動作を確認すること。

1. mdx-server上で`/api/health`、匿名Cookie、SQLite待ち行列、不正ZIPの検証失敗、MgB₂の`COMPLETED`までを確認した。
2. キャンセル・タイムアウト・ワーカー再起動時の挙動を別々に検証する。
3. React/Viteによる最小フロントエンドで、ZIP登録、状態表示、ログ、結果図表示まで確認した。内部限定運用ではサーバー上の絶対パスをログに表示する扱いとする。
4. Siの基準ZIPをWeb UIから投入し、SCF → Band → NSCF/PDOS → 結果図表示までの通常系E2E検証を完了した。
5. キャンセル、タイムアウト、ワーカー・API再起動時の回復を個別に検証する。
6. 未決定のブラウザ単位上限、アップロード容量、タイムアウト値を相談して採用する。

### 2. NaのBand段階エラーを切り分ける（未解決）

- NaではSCF成功後、Band計算中にQEの`cdiaghg: S matrix not positive definite`で停止した。
- GUI固有の障害ではなく、自動生成した`band.in`を含むQE計算条件の問題として扱う。
- 詳細と切り分け案は[Naのバンド計算における対角化エラー](experiments/sodium/2026-11-22-band-diagonalization-error.md)を参照する。

## その後の予定

1. **妥当性確認**: 必要に応じて、カットオフ・k点・`nbnd` の収束試験や実験値との比較を別実験として実施する。
2. **実験記録の更新**: 新しい実験ごとに成功・失敗、実行条件、妥当性確認、次の課題を残す。

## 未解決・確認待ち

- 匿名ブラウザIDと閲覧トークンを使うアクセス方式を採用した（[ADR-0006](decisions/0006-use-anonymous-browser-sessions-for-mvp.md)）。ブラウザ単位の待機・実行ジョブ上限、アップロード容量、学校Wi-Fi限定アクセスの公開前確認が残る。
- `mdx-server` に残るDKMSパッケージの未完了状態を、計算環境の運用課題としていつ解消するか。
- 高対称k点パスをSeeK-pathで自動生成するための依存パッケージを、`mdx-server` にどう導入するか。

## 更新ルール

- 実験を終えるたびに「現在地」と「次の具体的な作業」だけを更新する。
- 詳細な条件、ログ、エラー、解釈はこのファイルに増やさず、`docs/experiments/` の実験記録へ残す。
- 採用済みの重要判断は、対応するADRを正とする。
