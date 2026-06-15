# folio S4 generator (ADR-0042)

機械 SSoT (構造化された要件レコード) から人間プレゼン HTML を **ハイブリッド生成**する道具。
ADR-0042 §2.1 (生成方式) / §2.2 (A/B 可読化) / §3 (捏造リスク緩和) を実装する。

## パイプライン

```
contract.yaml ──validate──▶ assemble.sh ──▶ 構造 HTML (prose スロット空) ──③──▶ [opus prose 充填] ──④──▶ 完成
              (fail-closed)  (決定的・捏造不可)        ▲                          (後段スライス)
                                                       └ verify-fabrication-free.sh で②を機械証明
                                                         test-adversarial.sh で攻撃の fail-closed を回帰
```

- **① 入力 contract** (`contract/*.srs.yaml`) — 決定的 assembler が読む構造化データ。
  `upper_needs` (出所=RTM backward 端点) / `acceptance` (受入正典集合=RTM forward 端点) /
  `requirements` (id/type/ears{pattern,condition,response}/priority/vmethod/trace{backward,acceptance}/rationale_source) /
  `nfr` (測定可能メトリクス + trace) / `glossary` (専門語の plain 接地)。
- **② 決定的 assembler** (`assemble.sh`) — contract → catalog 契約準拠の構造 HTML (`srs.css` inline)。
  - RTM の ● は `trace.backward` から、 受入セルは `trace.acceptance` から導出。 元データに無い行・列・リンクを生成できない。
  - **fail-closed validate**: 自由記述中の tab/改行・id 重複・dangling 参照 (backward∉needs / acceptance∉正典集合)・
    未知 EARS/priority を生成前に abort (= `@tsv` 列ずれ・捏造の窓を源で塞ぐ)。
  - **HTML escape**: 全自由記述値を `& < > "` 実体参照化してから注入 (任意 markup を構造へ通さない)。
  - **検証可能な数値** (件数/トレースリンク/孤立/未検証) は assembler が決定的集計で `data-derived` に埋める
    (opus に書かせない。 §3 の要約捏造リスク緩和)。
  - prose スロット (章リード / plain やさしい言い換え / 「なぜ要る」根拠 / RTM 平易要約) は **空** で出力し `data-prose-slot` で印付ける。
- **③ opus prose 充填** (後段スライス) — 空スロットだけを `rationale_source` / `glossary` に接地して充填。
- **④ 組立 + 同期** — `fidelity-sync-meta` に生成日時 / 元 SSoT / 検証状態を刻む。

## A/B 可読化 (ADR-0042 §2.2)

- **B = 畳む** (`rtm-grid` register): RTM を `<details>` で既定折りたたみ + 空不可の平易要約スロット。
  全グリッドは DOM 保持 (ゼロ損失、 AI/印刷は展開)。 数値主張は決定的集計、 平易文だけ opus。
- **A = 噛み砕く** (要件本体・NFR): 各行に空不可の **plain (やさしい言い換え) スロット**。
  要件行はさらに rationale (「なぜ要る」) スロットを持つ (catalog ears-requirement-row 由来、 §2.1)。

## 使い方

```bash
./assemble.sh contract/ec-checkout.srs.yaml out.html   # 構造 HTML 生成 (prose スロット空)
./verify-fabrication-free.sh contract/ec-checkout.srs.yaml out.html   # 捏造ゼロを機械証明
./test-adversarial.sh                                  # 攻撃の fail-closed/FAIL 捕捉を回帰
```

## 本スライスの範囲 (S4 第一スライス)

EC 注文確定・決済 SRS を題材に、 **決定的構造組立 + 両軸 fabrication-free 証明**を実証する最小実装:
`doc-cover-band` / `chapter-deck-band` / `requirement-matrix-table` (+ `ears-requirement-row`) /
`nfr-metrics-table` / `source-trace-origin` / `rtm-grid` (B 折りたたみ) / `fidelity-sync-meta`。

**未実装 (後段)**: opus prose 充填 (③) / `plain-language-term-inline` 専門語自動併記 (glossary 接地マーク) /
残り部品 (interface/actor/use-case 等) の assembler 被覆 / S5 floor gate (no-TBD = `data-prose-slot` 非空)。

## open-items (後段へ申し送り)

- **新部品の catalog/taxonomy 登録 (→ S6 folio-16y)**: 本 assembler が導入した
  `rtm-collapse` (B 折りたたみ容器) / `nfr-metric-row` / `source-trace-row` (table-scoped 行マーカー) /
  `data-prose-slot="plain"` (A やさしい言い換えスロット) は **catalog.html に未登録**。
  ADR-0042 §3 は「新スロットを部品庫 (catalog) へ登録」を課す。 S6 で catalog 登録 + taxonomy §3 + gate G 被覆を凍結する。
- **A/据置 の全 dense 部品 allowlist 凍結 (→ S6)**: ADR-0042 §2.2 の代表例示を完全カタログ化。
- **S5 floor gate**: `data-prose-slot` 非空 (no-TBD) を本 verify と同じ前提 (`<style>` 除去 + 要素単位の空判定) で実装。

## 重要 gotcha

- `srs.css` を inline するため生成 HTML に CSS セレクタ `[data-component="..."]` が含まれる。
  `data-component` を grep で数える検証 (verify・S5 floor gate) は **`<style>` ブロックを除去**してから数えること。
- 行数カウントは id 命名 (`NFR`/`N-` prefix) でなく **`data-component` 行マーカー**で table-scoped に数える
  (命名次第で落とした行を隠蔽する穴を回避)。
- `@tsv` は値内の tab/改行で列ずれ・phantom 行を生む。 assembler は validate でこれを fail-closed 拒否する
  (生成前ガードが proof の前提)。

## Trace

ADR-0042 (hybrid generation + dense-table readability) / taxonomy `architecture/research/srs-component-taxonomy.html` §3 (部品 register) §5 (二層 done-condition) / design system `../catalog.html` (部品契約) `../srs.css` (視覚)。
独立 3-lens ceiling review (wf_41fcbde3) の blocker 2 (HTML escape / 改行 phantom) + major (acceptance 無検証 / 派生数値未検証 / 行カウント id 結合 / A plain スロット欠落 / rtm-collapse catalog 未登録) を反映。
