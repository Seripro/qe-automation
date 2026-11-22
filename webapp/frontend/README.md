# QE Web Frontend

最小のReact画面。Vite開発サーバーは`/api`をFastAPIへプロキシするため、匿名Cookieを同一オリジンとして扱える。

```bash
npm install
npm run dev
```

FastAPIが`http://127.0.0.1:8000`以外で動く場合は、起動前に`VITE_API_TARGET`を指定する。
