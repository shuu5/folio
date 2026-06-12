---
name: folio-compress
description: 既存 spec ページを人間層プレゼン圧縮 (ADR-0040) へ batch migration する道具。readability-floor warn (人間層可視 prose 上限/章要旨不在/図ゼロ×長文) が出ているページに対し、章要旨案・audience 仕分け案・mermaid 章図案を章単位で一括起草して適用し、user の Pages walk で検収する。圧縮基準の SSoT は rules §11.5 (本 SKILL は複製しない)。新規/改訂編集の恒久規律は folio-architect の presentation pass が担い、本 SKILL は既存 corpus の一括変換専用。user が明示起動する。
disable-model-invocation: true
---

# folio-compress SKILL — 人間層プレゼン圧縮の batch migration

> **応答言語**: 本 SKILL の出力 (提案・要約・user 向けメッセージ) は **user の使用言語** (default = global CLAUDE.md = 日本語) で行う。folio canonical 用語 (`section-essence` / `data-audience` / `EARS` / `REQ-*` / `P-N` 等) は英語のまま維持する。

既存ページを「人間層 = time-box 付きプレゼン / 機械層 = 無制限の原稿」(ADR-0040) へ一括変換する。**圧縮基準の単一 SSoT は [rules.html §11.5](../../architecture/spec/rules.html#s11-5-compression)** — time-box (目標/上限の字数)・章要旨/章図の語彙・仕分け規律・一次資料層の定義はそちらを読む。本 SKILL は手順だけを定める (基準・数値を複製するとドリフトする)。

**folio-architect との分担** (ADR-0040 §2.4): architect の presentation pass = 新規/改訂章に圧縮規律を**以後ずっと**守らせる恒久装置。本 SKILL = 規律導入前に書かれた**既存 corpus の一括変換**。1 回の migration が終われば本 SKILL の出番は減り、 architect 側が引き継ぐ。

## 手順

### Step 1 — 対象選定と baseline

```bash
.claude-plugin/bin/folio validate 2>&1 | grep "readability-floor"
```

圧縮 3 arm の warn (`人間層可視 prose > 12000` / `章要旨が 1 つも無い` / `図ゼロのまま > 6000`) が**そのまま migration TODO リスト** — 数値の大きい順が優先順位。重量級 (rules / verification / folio-self-spec / relations) は **1 ページ = 1 slice** に分割する。baseline 数値を記録し、 slice 完了時の before/after に使う。

### Step 2 — 章単位の batch 起草 (適用前に全章分を作る)

対象ページを通読し、 **h2/h3 章ごと**に 3 点セットを起草する:

1. **章要旨** — `<p class="section-essence" data-audience="human">` 1〜3 文。降格する地の文の**正確な要約** (脱落・誇張・矛盾・drift は Phase F fidelity が検査する — 要約は「読者が要旨だけ読んでも誤解しない」が合格線)。
2. **仕分け** — 残す (見出し/図/表/REQ essence) と降格 (`data-audience="machine"`、 複数段落は wrapper `<div>`) の割当。**削除は禁止** — 圧縮は降格であり情報はゼロ損失 (§11.5 MUST)。
3. **章図** — 構造 (依存・流れ・階層・状態) を持つ章に mermaid。loader は vendored (`../assets/mermaid.min.js`)・`accTitle`/`accDescr` 付与・図は人間層に置く (machine 降格しない、 §11.5)。

入口群 (landing / cluster README) を圧縮する slice では、 curated 文言に **audience toggle の存在を案内する 1 文**を足す (toggle 発見可能性の解消 — readability-walk lens 2026-06-12 の申し送り。 migration 固有の追加動作なので §11.5 でなく本 SKILL が持つ)。

### Step 3 — 適用 (caller-marker lifecycle)

spec 編集は folio-architect Phase E と同じ marker 手順に従う — **エラー・中断時も unset を最優先**:

```bash
mkdir -p .folio && touch .folio/architect-active   # set
# … Edit (各章について「章要旨の追加」と「当該章 prose の降格」を 1 編集単位でペアにする = per-chapter) …
rm -f .folio/architect-active                       # unset (MUST)
```

章要旨と降格を同時 (per-chapter) にする理由は **§11.5 の内在的依存** — 章要旨は降格される地の文の要約なので、 片方だけ適用すると「章の入口が要旨でも地の文でもない」空白状態になる (本 SKILL が定める migration 規律。 readability-walk lens はこの中間状態を体験不良として**事後検出**する装置であって、 順序を課す規範ではない)。

### Step 4 — 機械検証

- `folio validate` — 17 gate clean + 対象ページの readability-floor warn が baseline から改善したか (上限 box 内に入ったか)。
- **per-chapter 確認 (手動)** — page 単位 warn が消えた後も、 編集した**全 h2/h3 章**に section-essence が付いたかを確認する (floor の presence warn は v1 page 単位しか見ない — §11.5 の MUST は章単位。 章ごとの presence と品質は Step 5 の fidelity (a2) も検査する)。
- `folio fix` → 再 validate。**REQ essence を改訂した場合**は xref の stale-tooltip に注意 — fix は既存 tooltip を再生成できない (parity hole、 folio-dpz)。`folio_xref_tooltip_text` を source して期待値を計算し手動同期する。
- `folio build --check` clean。
- sandbox 全 suite を **for ループ + exit code 判定**で実行。**validate-clean golden は実 corpus の warn 行を byte-exact で機械追跡している** (codepoint 実数・h2 章数が golden に埋まる) ため、 **可視 prose codepoint / h2 章数 / warn 集合のいずれかが変わる slice では golden regen を同梱**する: `cd tests && bash runner.sh --accept scenarios/validate-clean.yaml` → `git diff` で意図した行だけが変わったことを review してから commit。
- mermaid 章図を追加/改訂した slice は、 push 後 CI の **render-gate** (REQ-VER-022、 幾何 overlap × 3 viewport) が block しうる — ローカルで先に回すなら `uv run --with playwright==1.60.0 python tests/render-gate/check.py` (validate の render-safety は pure-bash で render 後 DOM を見れない死角。 walk は読書体験の検査で幾何の代替にならない)。

### Step 5 — review と検収

1. **Phase F fidelity** (`folio:spec-review-fidelity`) を spawn — 章要旨 ↔ 地の文 (降格分含む) / 図 ↔ 本文の 3 粒度検査。findings の critical/high は Step 3 を再実行して反映。
2. ultracode 時は独立 ceiling (Workflow) を commit 前に回す。
3. push → GitHub Pages 反映 → **user の実機 walk で検収 (batch 型、 rules §11.4 MUST)**。walk の指摘は次 slice より優先して iteration する。

### time-box 未達の扱い

降格を尽くしても上限 box を切れない場合、 **削除では解決しない** — 章分割・別 spec への切り出し等の構成再編を選択肢として user に提示し判断を仰ぐ (P-10 系の構造変更になりうるため独断しない)。

## 対象外 (§11.5 一次資料層)

frozen ADR (decisions/ 配下の `ADR-*.html`。 **decisions/README.html は cluster README = 圧縮対象**で、 Step 1 の TODO に普通に現れる)・research の非 README・constitution は**圧縮しない**。これらは AI が読む原稿そのもの (ADR-0040 §2.6)。
