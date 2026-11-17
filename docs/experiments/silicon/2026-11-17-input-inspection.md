# シリコン入力一式の確認

- 実施日: 2026-11-17
- 状態: 入力確認のみ。QE計算は未実行。
- 対象物質: Si
- 入力アーカイブ: [`input/PWscf.zip`](input/PWscf.zip)
- 入力作成元: Materials Cloud QE input generator（Webサイトの初期設定で生成）

## 目的

Materials Cloudから取得した `PWscf.zip` の構成と `pwscf.in` を確認し、SCF計算前に分かっている条件と未確認事項を記録する。

## アーカイブの構成

```text
PWscf.zip
└── PWscf/
    ├── pwscf.in
    └── pseudo/
        └── Si.pbesol-n-rrkjus_psl.1.0.0.UPF
```

既存の `scripts/qe_auto_kp.sh` はZIPを展開後に `PWscf/` へ移動して計算を始めるため、この構成と互換である。

## `pwscf.in` から確認できた条件

| 項目 | 値 | 現時点での意味 |
|---|---:|---|
| 計算種別 | `scf` | 自己無撞着な電子密度を求める計算 |
| 原子数 / 元素種数 | `nat = 2` / `ntyp = 1` | 原始胞にSi原子が2個、元素種は1種類 |
| 格子指定 | `ibrav = 0` + `CELL_PARAMETERS` | 格子ベクトルを明示的にangstrom単位で与える |
| 原子座標 | `(0,0,0)`, `(0.75,0.75,0.75)` | 格子に対する分率座標（`crystal`） |
| 擬ポテンシャル | `Si.pbesol-n-rrkjus_psl.1.0.0.UPF` | PBEsol系のSi擬ポテンシャル |
| 波動関数カットオフ | `ecutwfc = 30 Ry` | 平面波基底の大きさを決める |
| 電荷密度カットオフ | `ecutrho = 240 Ry` | 電荷密度・ポテンシャル用のカットオフ |
| k点メッシュ | `14 × 14 × 14`, offset `0 0 0` | SCF用のブリルアンゾーン積分 |
| 占有 | `smearing = 'cold'`, `degauss = 0.02 Ry` | 分数占有を用いる設定 |
| SCFしきい値 | `conv_thr = 4.0d-10` | 電子密度の自己無撞着性に関するしきい値 |
| 出力先 / 名前 | `./out/` / `aiida` | 後続のバンド・PDOS計算で引き継ぐデータの位置と名前 |

## 確認できたこと

- `pseudo_dir = './pseudo/'` と、アーカイブ内の擬ポテンシャル配置が一致している。
- `prefix = 'aiida'` と `outdir = './out/'` は、既存のバンド・PDOS自動化スクリプトで使われる値と一致している。
- `ibrav = 0` と明示的な `CELL_PARAMETERS` を使う形式は、既存のk点パス生成スクリプトが対象としている形式である。

## 未確認事項・実行前に確認すること

1. CIFの出典（COD ID）と、Materials Cloudが初期設定として選んだプロトコル・交換相関汎関数・磁性／smearing設定を記録する。
2. この入力は `occupations = 'smearing'` と `smearing = 'cold'` を使っている。これはMaterials Cloudの生成結果であり、現段階では教授から案内された標準手順の基準入力として扱う。固定占有との比較や設定変更が必要かは、SCF・バンド・PDOSの結果を読めるようになってから検討する。
3. `ecutwfc = 30 Ry`、`ecutrho = 240 Ry`、14×14×14 k点メッシュが今回の目的に十分か、収束試験で確認する。
4. 研究室サーバー上のQE・MPI・PBS環境でSCFが正常終了するか確認する。

## 次の作業

1. `pwscf.in` を各ブロックごとに読み、SCFで何を設定しているかを理解する。
2. 元のZIPを変更せずに、教授から案内された標準手順としてサーバーでSCFを試行する。
3. 実行結果を別の実験記録として残す。
4. 固定占有との比較や設定変更は、結果の解釈と必要性を理解してから検討する。
