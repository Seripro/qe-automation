# 次回の作業

- 更新日: 2026-11-21
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

### 1. CLI計算フローをGUI実装の処理単位へ整理する

目的は、シリコンで確認したCLIフローを、GUIが安全に実行・監視・表示する処理単位へ対応付けること。

1. [ジョブ待ち行列・直接実行ワーカー仕様案](job-queue-workflow-spec.md) を基に、未決定の認証・上限・タイムアウトを相談する。
2. 各段階の入力、成功根拠、失敗時の停止条件、保持すべき成果物をバックエンド実装へ対応付ける。
3. GUIのバックエンド実装範囲を小さく決める。

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
