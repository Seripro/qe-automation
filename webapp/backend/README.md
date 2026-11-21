# QE Web Backend（初期実装）

FastAPIのAPIと、別プロセスで動かす直接実行ワーカーで構成する。Web APIはQEを直接実行しない。

## 開発起動

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

別ターミナルでワーカーを起動する。

```bash
cd webapp/backend
QE_APP_DATA_ROOT=/absolute/path/to/runtime python3 -m app.worker
```

本番では、APIとワーカーを別サービスとして管理する。`QE_COOKIE_SECURE=true` を設定し、HTTPSの背後で動かす。
`QE_VIEW_TOKEN_SECRET` には、デプロイごとに生成した十分長い秘密値を設定する。

## 注意

- 初期の同時実行数は、ワーカーを1プロセスだけ起動して実現する。
- 実行時間、容量、ネットワーク制限、結果の保存期間はデプロイ前に設定・検証が必要。
- 現在のワーカーは直接実行版であり、mdx-server上のQE実行環境・Python仮想環境を前提とする。
