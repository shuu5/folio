# html-spec-craft (informative reference)

folio Layer 0 spec HTML を「読みやすく / accessible に」書くための knowledge pool。 normative ではなく **informative**。 folio-architect SKILL.md は薄く保ち、 詳細は本 reference から pull する (Progressive Disclosure pattern、 [Anthropic skill-development 公式 docs](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/skill-development/SKILL.md) と整合)。

本 reference は rules.html `§4.6 Accessibility Minimum Rules` (normative) の根拠 verbatim 引用集 + 業界 HOW knowledge の集約。 spec author (人間および `folio-architect`) は editing 中に必要に応じ本 reference を pull する。

<!-- Sources: WCAG 2.2 (W3C Document License, verbatim quote 可) / mermaid 公式 docs (MIT) / MDN (CC BY-SA) / IETF RFC / Python PEP / Rust RFC / Anthropic skills (Apache 2.0)。 詳細出典は §7 references + repo の citations.md。 -->

## 0. 適用範囲

- folio `architecture/spec/` 配下の HTML spec、 ADR、 constitution
- folio-architect skill が生成する HTML spec の templating reference
- folio rules.html `§4.6` Accessibility Minimum Rules の補強材料

## 1. WCAG 2.2 verbatim quote (rules.html §4.6 根拠)

### 1.1 SC 1.4.3 Contrast (Minimum), Level AA

> "The visual presentation of text and images of text has a contrast ratio of at least 4.5:1, except for the following:"

- 例外: large-scale text **3:1** (18 point / 14 point bold)、 incidental text、 logotype
- 出典: https://www.w3.org/TR/WCAG22/#contrast-minimum (W3C Document License、 出典明記で verbatim 引用可)

### 1.2 SC 1.4.6 Contrast (Enhanced), Level AAA

> "The visual presentation of text and images of text has a contrast ratio of at least 7:1, except for the following:"

- 例外: large text 4.5:1、 incidental、 logotype
- 出典: https://www.w3.org/TR/WCAG22/#contrast-enhanced

### 1.3 SC 1.4.11 Non-text Contrast, Level AA

> "The visual presentation of the following have a contrast ratio of at least 3:1 against adjacent color(s):"

- 対象: User Interface Components + **Graphical Objects (parts of graphics required to understand the content)**
- ★ 注記: mermaid SVG fill への適用は **WCAG 文言上の解釈**。 W3C 公式の mermaid SVG 特化解釈文書は不在。
- 出典: https://www.w3.org/TR/WCAG22/#non-text-contrast

### 1.4 SC 1.1.1 Non-text Content, Level A

> "All non-text content that is presented to the user has a text alternative that serves the equivalent purpose, except for the situations listed below."

- 例外: controls (name 必須)、 time-based media、 tests、 sensory、 CAPTCHA、 decoration
- ★ mermaid SVG に `accDescr` 必要となる根拠
- 出典: https://www.w3.org/TR/WCAG22/#non-text-content

## 2. mermaid a11y 仕様 (rules.html §4.6 根拠)

### 2.0 mermaid loader — vendored MUST (CDN 不可)

mermaid を採用する spec の `<head>` に置く loader は **vendored 1 file** を参照する:

```html
<script src="../assets/mermaid.min.js" defer></script>
```

- パスは spec の位置に対する相対 (folio 慣習: spec が `architecture/spec/` 配下なら `../assets/` = `architecture/assets/mermaid.min.js`)。 folio 自身の全 spec (constitution / rules / relations / self-spec / verification / README) がこの形を使う。
- **runtime CDN (`https://cdn.jsdelivr.net/npm/mermaid...` / `unpkg` / ES module `import ... from 'https://...'`) は MUST NOT** — [rules.html §8 REQ-DA-JS-2](../../../architecture/spec/rules.html#s8-js-governance) が「library は vendoring (no runtime CDN)」「ES modules + `fetch()` は file:// 破綻ゆえ不使用」と規定する。 no-cloud 原則 (生成物が外部 fetch なしで完結) にも整合。
- **consumer は mermaid.min.js を自分で vendoring する** (`folio init` は assets/ を scaffold しない = REQ-DA-JS-2 の「自分の lib は自分で vendor」)。 未 vendoring の段階でも raw `<pre class="mermaid">` syntax は人間に可読 (graceful degradation、 §8 / grilling-protocol.md)。 図の visual render は consumer が `architecture/assets/mermaid.min.js` を置いた時点で有効化される。
- loader を classic `<script src defer>` (single-file) にするのは REQ-DA-JS-2 の「single-file classic `<script>` か inline」要件 + `defer` で DOMContentLoaded 後 render のため。

### 2.1 accTitle / accDescr 構文 (mermaid v11.15.0 verbatim)

```
flowchart TD
  accTitle: Single line title
  accDescr: Single line description.
  accDescr {
    Multi-line description.
    Continues here.
  }
  A[Node] --> B[Node]
```

→ SVG 出力 (公式 verbatim):

```html
<svg
  aria-labelledby="chart-title-mermaid_XXX"
  aria-describedby="chart-desc-mermaid_XXX"
  aria-roledescription="flowchart-v2"
>
  <title id="chart-title-mermaid_XXX">Title text</title>
  <desc id="chart-desc-mermaid_XXX">Description text</desc>
</svg>
```

出典: https://mermaid.js.org/config/accessibility.html (MIT)

### 2.2 themeVariables / primaryTextColor 公式定義

- `primaryTextColor` = "Color to be used as text color in nodes using primaryColor" (公式 verbatim)
- default: "calculated from darkMode #ddd/#333"
- `nodeTextColor` の default = `primaryTextColor` (公式継承定義)
- 制約: hex のみ (color name 不可)
- `themeVariables` 変更可能: **base のみ**。 default / neutral / dark / forest は変更不可 → `classDef` / `style` の `color` プロパティが唯一の手段
- 出典: https://mermaid.js.org/config/theming.html

### 2.3 fill-only override が text contrast 不足を起こす機序

**公式根拠**: `nodeTextColor` の default = `primaryTextColor` (継承定義、 §2.2)

**folio 解釈** (公式 docs に直接記述は **不在**、 GitHub Issue が二次根拠):

- SVG 生成時に theme が text の `color` CSS を埋め込む
- `fill` だけ `classDef` / `style` で override しても text の `color` は theme 値が残る
- → folio common.css は themeVariables で `primaryTextColor: '#ffffff'` を指定済ゆえ、 light fill (`#fefbea` 等) 上に白文字が乗り WCAG SC 1.4.3 違反

**二次根拠 (GitHub Issue)**:

- mermaid #1955 (https://github.com/mermaid-js/mermaid/issues/1955): classDef color プロパティが無効になるバグ (PR #1956 で修正済)
- mermaid #5052 (https://github.com/mermaid-js/mermaid/issues/5052): edge label が `primaryTextColor` を使い続ける、 公式 workaround = "Change the style to use secondary text color"

★ rules.html §4.6 では「mermaid 公式: `nodeTextColor` 継承定義」+「folio 規約: paired override 必須」と **分けて記述** している (本 reference §2.2/§2.3 が hook)。

### 2.4 paired override 正攻法

```mermaid
%% 個別 style (公式 docs verbatim 例)
style nodeA fill:#bbf,stroke:#f66,stroke-width:2px,color:#fff,stroke-dasharray:5 5

%% classDef paired override (folio 推奨 pattern)
classDef critical fill:#FFE6E6,stroke:#CC0000,stroke-width:2px,color:#000000
classDef danger   fill:#CC0000,stroke:#880000,stroke-width:2px,color:#FFFFFF
classDef safe     fill:#E6FFE6,stroke:#006600,stroke-width:2px,color:#000000
```

判断ガイドライン:

- 淡色 fill (`#FFE6E6` / `#E6FFE6` 等) → `color:#000000` 系の dark text
- 濃色 fill (`#CC0000` / `#1a1a1a` 等) → `color:#FFFFFF` 系の light text
- contrast ratio **4.5:1 (normal text) / 3:1 (large text)** を満たすこと (§1.1 SC 1.4.3 verbatim)

出典: https://mermaid.js.org/syntax/flowchart.html (style 例) + GitHub Issue #1956 (classDef color 修正済)

## 3. 業界 spec HTML pattern (1.x wave で R 昇格候補)

| # | Pattern | folio 1.0.0 status | 1.x 昇格 priority | 出典 |
|---|---------|---|---|---|
| 1 | Pilcrow Paragraph Anchor (¶) | informative only | 高 | IETF RFC 7992 / RFC 9110 |
| 2 | TOC 自動生成 (e.g. `<!--toc-->`) | informative only | 中 (folio prime 拡張時) | WHATWG wattsi / W3C ReSpec |
| 3 | `<dfn>` + cross-ref | informative only | 高 | W3C ReSpec / WHATWG HTML LS |
| 4 | Sticky sidebar TOC (`position: sticky`) | informative only | 高 | MDN / Python PEP |
| 5 | Note / Warning / Example aside callout | informative only | **最高** (common.css 変更必要) | MDN / W3C ReSpec / WCAG |
| 6 | Freshness Signature (last-modified、 Status: Draft 等) | informative only | 高 | Python PEP / MDN / WHATWG |
| 7 | `<details>` / `<summary>` Progressive Disclosure | informative only (非規範限定) | 中 | W3C APG / MDN |
| 8 | Dark mode Auto (`prefers-color-scheme`) | informative only | 中 | Rust RFC / Python PEP / IETF 2026 |
| 9 | Metadata Header `<dl>` (Status / Type / Author の visible 化) | informative only | **最高** (既存 status の visible 化) | Python PEP / IETF / Kubernetes KEP |
| 10 | Breadcrumb nav (`aria-current`) | informative only | 高 | MDN / Python PEP / Rust RFC |

各 pattern の本文 description / 実装スケッチは 1.x wave で着手時に展開する (本 reference は MVP scope = 一覧 + 出典のみ)。

## 4. HTML interactivity reference (spec authoring HOW)

### 4.1 `<details>` / `<summary>` の使い分け

- `open` 属性は boolean (`open="false"` は **無効**)
- 暗黙 ARIA role = `group`、 追加 role 不許可
- keyboard accessible (Tab → Space で toggle、 JS 不要)
- spec 判断基準: 規範定義は `open` default、 補足・変更履歴は closed
- `name` 属性 (HTML 5.3+) で accordion group (同名 `<details>` は同時 1 つのみ open)
- ★ folio: 非規範セクション (Alternatives Considered、 Appendix 等) のみ採用、 規範セクションには使わない (P-3 WHAT-only の見落とし risk)
- 出典: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/details

### 4.2 dark mode (`prefers-color-scheme` + CSS Custom Properties)

- `@media (prefers-color-scheme: dark)` は Baseline Widely Available (2020-01-)
- pattern: `:root` で Custom Properties 定義 → media query で上書き
- モダン代替: `light-dark()` CSS 関数 (browser support 較新)
- ★ folio: common.css に Auto mode (`@media (prefers-color-scheme: dark)`) のみ minimal 実装、 1.x で手動 toggle 拡張候補
- 出典: https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-color-scheme

### 4.3 anchor highlight (`:target` + `:focus-visible`)

- `:target` で URL fragment ハイライト (progressive enhancement)
- `:focus-visible` (Baseline 2022-03) で keyboard ナビ時のみフォーカスリング
- WCAG SC 1.4.11 フォーカスインジケータ contrast 3:1 要件
- 出典: https://developer.mozilla.org/en-US/docs/Web/CSS/:target + https://www.htmldog.com/articles/target/

### 4.4 sticky TOC (`position: sticky`)

- top / right / bottom / left の 1 つ以上必須
- `<nav role="navigation" aria-label="Table of contents">`
- 高度実装: IntersectionObserver で active section 検出 → `aria-current="true"`
- skip link 衝突注意 (z-index 管理)
- 出典: https://developer.mozilla.org/en-US/docs/Web/CSS/position#sticky_positioning

### 4.5 footnote / sidenote (DPUB-ARIA Module)

```html
<sup><a href="#fn1" role="doc-noteref" aria-label="footnote 1">1</a></sup>

<aside id="fn1" role="doc-footnote">
  <p>注釈テキスト。 <a href="#ref-fn1">↩</a></p>
</aside>
```

- `doc-footnote` は `<aside>` に付与 (`<li>` 不可、 list semantics を破壊)
- back link 必須 (keyboard user 向け)
- 出典: https://www.w3.org/TR/dpub-aria/

## 5. mermaid 代替検討 (1.x 長期視点)

| 比較項目 | mermaid | D2 | Excalidraw embed | inline SVG | Bikeshed | asciidoctor HTML |
|---|---|---|---|---|---|---|
| License | MIT | MPL 2.0 | MIT | n/a | MIT | MIT |
| 実装 | JS | Go CLI / WASM | JS / React | 手書き | Python | Ruby |
| 導入容易性 (vendored 1 file) | ○ | × (CLI install) | △ (iframe 限界) | ○ (依存ゼロ) | × | × |
| a11y (現状) | `accTitle` / `accDescr` | CLI SVG に title/desc 可 | 限定的 | 最も高い (手動) | spec autolink | 中 |
| folio 適合 | **採用中** | 1.x 切替 cost > benefit | 不適合 | アイコン用途のみ | W3C 依存で過剰 | HTML-first と重複 |

★ **結論**: folio 1.x での mermaid 切替 ROI は低い。 現状維持 + `accTitle` / `accDescr` 必須化 + paired override の方が現実的。 D2 は CLI install (Go) が必要で folio の "vendored 1 file (`assets/mermaid.min.js`) + Claude が text syntax で描ける" model と相性が悪い (folio は runtime CDN を使わない = [REQ-DA-JS-2](../../../architecture/spec/rules.html#s8-js-governance))。 Bikeshed は W3C 依存が強く独立 spec には過剰。 inline SVG は手書きコストが高くアーキテクチャ図には不適。

出典: D2 FAQ (https://d2lang.com/tour/faq/) + Bikeshed docs (https://speced.github.io/bikeshed/)

## 6. EARS / declarative form readability (folio P-5 正当化)

### 6.1 EARS (Easy Approach to Requirements Syntax)

- Mavin 2009 (Rolls-Royce、 RE 09 カンファレンス) で発表
- 5 pattern (Ubiquitous / State-Driven / When / Where / If-Then) すべて `The [system] shall [response]` 骨格
- 利点: temporal logic 順序で認知負荷軽減、 能動態統一、 非ネイティブ英語話者でも解読容易
- 採用企業: Airbus / Bosch / Intel / NASA / Siemens
- 出典: https://alistairmavin.com/ears/ (著者公式)

### 6.2 plain language readability

- 文長 15-20 語以内で理解度向上 (NCBI PMC9955962、 peer-reviewed)
- 能動態は受動態より文長 -20-30%
- 1 文 1 アイデア → 情報吸収速度向上
- 出典: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9955962/ + US National Archives Plain Language

### 6.3 terminology consistency (folio P-5 canonical name)

- 呼称ブレ = extraneous cognitive load (technical writing 業界知見)
- 統一の効果: 読者の content 処理集中・検索精度向上・翻訳コスト低下
- folio P-5 はこの知見の実装

## 7. references

- WCAG 2.2 (W3C TR): https://www.w3.org/TR/WCAG22/
- WCAG SC 1.4.3 Contrast Minimum: https://www.w3.org/TR/WCAG22/#contrast-minimum
- WCAG SC 1.4.6 Contrast Enhanced: https://www.w3.org/TR/WCAG22/#contrast-enhanced
- WCAG SC 1.4.11 Non-text Contrast: https://www.w3.org/TR/WCAG22/#non-text-contrast
- WCAG SC 1.1.1 Non-text Content: https://www.w3.org/TR/WCAG22/#non-text-content
- mermaid Accessibility: https://mermaid.js.org/config/accessibility.html
- mermaid Theming: https://mermaid.js.org/config/theming.html
- mermaid Flowchart syntax: https://mermaid.js.org/syntax/flowchart.html
- W3C DPUB-ARIA Module: https://www.w3.org/TR/dpub-aria/
- MDN `<details>`: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/details
- MDN prefers-color-scheme: https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-color-scheme
- MDN `<dfn>`: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dfn
- IETF RFC 7992 (HTML for RFCs): https://datatracker.ietf.org/doc/html/rfc7992
- WHATWG HTML Living Standard: https://html.spec.whatwg.org/multipage/
- Rust RFC Book: https://rust-lang.github.io/rfcs/
- Python PEP 8: https://peps.python.org/pep-0008/
- Anthropic skill-development: https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/skill-development/SKILL.md
- Anthropic doc-coauthoring: https://github.com/anthropics/skills/blob/main/skills/doc-coauthoring/SKILL.md
- Anthropic accessibility-review: https://github.com/anthropics/knowledge-work-plugins/blob/main/design/skills/accessibility-review/SKILL.md
- D2 FAQ: https://d2lang.com/tour/faq/
- Bikeshed docs: https://speced.github.io/bikeshed/
- EARS (Mavin): https://alistairmavin.com/ears/
- NCBI sentence length (PMC9955962): https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9955962/

完了基準: refs/html-spec-craft.md が folio rules.html `§4.6` から `<a href="../../skills/folio-architect/refs/html-spec-craft.md">` で参照可能になり、 spec authoring の HOW knowledge pool として機能する状態。
