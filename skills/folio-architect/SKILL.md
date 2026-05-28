---
name: folio-architect
description: folio spec edit の唯一の正規 author entry point (7-Phase PR Cycle orchestrator)。architecture/spec/ 配下の spec HTML を編集する際に user が明示起動する。Phase A で adoption-state を検出し greenfield (onboarding grilling → constitution/overview を lazy materialize) / maintenance に分岐、Phase C で refs/grilling-protocol.md に沿い gap-driven に grill、Phase E で caller marker を set→編集→folio validate→unset、Phase F で 4 review agent (folio:spec-review-ears/vocabulary/ssot/temporal) を並列 spawn して品質検証する。folio-self-spec.html §7.1 準拠。
disable-model-invocation: true
---

# folio-architect SKILL — 7-Phase PR Cycle orchestrator

> **応答言語**: 本 SKILL の出力 (grill 質問・推奨回答・todo・要約・user 向けメッセージ等) は **user の使用言語** (default = global CLAUDE.md = 日本語) で行う。folio canonical 用語 (`Phase A〜G` / `EARS` / `vocabulary` / `ADR-XXX` / `P-N` / `FolioConstitution` 等、 P-5 vocabulary 由来) は英語のまま維持し、 記述・対話・接続詞は user の言語に合わせる。

folio spec edit の**唯一の正規 author entry point**。folio-self-spec.html §7.1 の **7-Phase PR Cycle (A〜G)** を main-session で順次 orchestrate する。

`architecture/spec/` 配下の spec HTML は caller-marker hook で gate されており、本 SKILL の **Phase E** で caller marker を set しないと Edit/Write が deny される。本 SKILL を使わずに spec を編集しようとすると hook が止める。

> **本 SKILL は SKILL のまま (subagent 化しない)**。Phase F で review agent を並列 spawn する側は main-session でなければならない (subagent は subagent を spawn できない = nesting 制約)。`disable-model-invocation: true` で、Claude が spec 編集を予期して自動起動し marker を即 set/unset する事故を防ぐ。起動は user が明示的に `/folio-architect` で行う。

## 7-Phase 概観

| Phase | name | 必須 | X4-D での実体 |
|-------|------|------|---------------|
| A | Discovery | MUST | adoption-state 検出 → greenfield onboarding / maintenance 分岐 (+ todo list + `folio.config.yaml` load) |
| B | Exploration | MUST | **inline** (関連 spec/ADR + established では consumer code も Grep/Read で grounding、ADR-0031 §2.6。`spec-explorer` agent 化は X5+) |
| C | Clarifying / Grilling | **MUST NOT SKIP** | `refs/grilling-protocol.md` に沿い gap-driven に 1 問ずつ grill + persist-as-you-go |
| D | Design | optional | structural change 時のみ inline 設計 (`spec-architect` agent 化は X5+) |
| E | Implementation | MUST | marker set → Edit → `folio validate` → marker unset |
| F | Quality Review | **MUST NOT SKIP** | 4 review agent (ears/vocabulary/ssot/temporal) を **並列 spawn** → findings 集約 → 高 severity を再 Phase E で修正 |
| G | Summary | MUST | delta marker check + 変更要約 |

各 phase を **順に** 実行する。Phase C と F は **MUST NOT SKIP**。Phase D は structural change が無ければ skip 可。

## folio CLI の解決 (consumer / self-host 両対応)

本 SKILL は folio CLI を `~/.claude/plugins/folio/.claude-plugin/bin/folio` で呼ぶ。consumer project でも folio self-host (cwd = repo) でも同じ bin に解決する (plugin install が symlink で repo bin を指す canonical layout)。これが見つからない場合は `command -v folio` を fallback とし、どちらも無ければ consumer に install を案内して abort (fail-closed)。以降、各 phase で folio CLI を呼ぶときはこの canonical path を使用する (bare `folio` や repo-relative `.claude-plugin/bin/folio` は consumer cwd で解決しないため禁止)。

---

## Phase A — Discovery (MUST、adoption-aware)

1. **todo list を作成**し、本タスクで編集する spec / 達成条件を列挙する。
2. **`folio.config.yaml` を load** する (あれば)。`spec_path` / `caller_marker_*` / `review_model` の override を確認する。folio 自身 (Layer 0) を編集する場合は `.claude-plugin/plugin.json` userConfig の default (`spec_path = architecture/spec/`、`review_model = opus`) を用いる。
3. **adoption-state を検出**して分岐する (ADR-0031 §2.3)。判定は **design-intent spec の実体の有無**による:
   - **greenfield** (`spec_path` に実体ある spec が無い — `constitution.html` 不在 / cluster README skeleton のみ) → **onboarding grilling 分岐**。構造 (config + cluster README) が未生成なら先に `~/.claude/plugins/folio/.claude-plugin/bin/folio init` を実行する (CLI なので caller-marker 不要、構造のみ決定論生成、canonical path は §「folio CLI の解決」)。次いで Phase C で onboarding grill を行い、引き出した実体から constitution / overview を **Phase E で lazy-materialize** する (中身がある時のみ。空 placeholder は書かない)。
   - **established** (実体 spec あり) → **maintenance 分岐**。通常の spec 編集 (Phase B 探索 → Phase C で変更の未解決点を grill)。
   - `folio.config.yaml` の存在は構造 scaffold 済を示すが established を意味しない (`folio init` は実体に先立ち config を作る)。

> grilling の具体規律は **`refs/grilling-protocol.md`** (folio 自前 / spec-aware / gap-driven / persist-as-you-go、MIT-attr) を Phase A/C で参照する。

## Phase B — Exploration (MUST、inline)

編集対象に関連する spec / ADR / research を **inline で Grep/Read** して文脈を把握する:

- 編集する spec の現行内容、cross-ref している spec、関連 ADR (decisions/)、未昇格の research。
- 影響を受ける REQ-ID、用語 (P-5 canonical name)、領域境界 (P-7)。
- **code-cross-reference** (established project、ADR-0031 §2.6): consumer code も読み、spec の主張と実装現実の食い違いを把握する。食い違いは Phase C grilling で surface して spec を研ぐ。code は spec を**研ぐ証拠**であって test する gate ではない (出力は良い spec であり pass する test ではない) — gate / 新 review agent は作らない (ADR-0026 実装適合性境界を遵守)。

> `spec-explorer` agent による並列探索は完成形 (§7.2)。X4-D では folio-architect が inline で実行する (agent 化は **X5+**)。

## Phase C — Clarifying / Grilling (MUST NOT SKIP)

Phase B で判明した未解決点を、**`refs/grilling-protocol.md`** に沿って **1 問ずつ user に grill** する (AskUserQuestion、各問に推奨回答付き)。silently choosing は禁止 (constitution P-8 AI dialog accountability)。

- **gap-driven**: 既存 spec / `vocabulary.yaml` / ADR / 会話 context から settled を認識し、**未解決論点だけ**を尋ねる (解決済みは再尋問しない)。codebase / spec を読めば分かることは読んで確かめる。
- **spec-aware**: 概念 → canonical name 提案 (P-5)、要件 → EARS scenario で境界 stress-test、hard-to-reverse かつ surprising かつ real-trade-off な決定 → ADR を offer (sparingly、§10.3。新 ADR 起票は user 承認 MUST)。
- **persist-as-you-go**: grilling 中に決まった軽い anchor (`vocabulary.yaml` の用語 / ADR — caller-marker 非 gate) を **inline 永続化**する。重い spec は Phase E で materialize。settled を artifact に宿すことで folio-architect は何度でも安全に再起動できる (`grill-me` 先行・反復が非冗長 = read-persist ループからの創発)。
- **greenfield onboarding** の場合は protocol の onboarding 論点 (不変原則 / system context / building blocks / domain 用語) を grill し、Phase E で**非 hollow** な constitution / overview を materialize する。

## Phase D — Design (optional、structural change 時のみ)

directory 構成・新規 spec file・REQ 体系の追加など **structural change を伴う場合のみ**、inline で設計を起こす (minimal / clean / pragmatic の trade-off を簡潔に提示)。本文の追記・修正だけなら skip 可。

> `spec-architect` agent による 3 案並列設計は完成形 (§7.2)。X4-D では inline (agent 化は **X5+**、optional)。

## Phase E — Implementation (MUST)

spec 編集の中核。**caller marker lifecycle** に従う (旧最小版 SKILL の手順を内包):

### marker 機構 (hybrid: env OR file)

caller-marker hook (`.claude-plugin/scripts/check-caller-marker.sh`) は次のどちらかで spec 編集を allow する:
- env var `FOLIO_ARCHITECT_CONTEXT=folio-architect` (cld 起動時 set。session 開始後は変更不可)
- marker file `.folio/architect-active` の存在 (本 SKILL が mid-session で touch/rm する方式)

env は実行中の hook に伝播しないため、**session 内での正規 spec 編集には file marker を使う**。`.folio/` は `.gitignore` 済。marker file path は env `FOLIO_MARKER_FILE` で override 可 (hook と整合、default `.folio/architect-active`)。

### Step 1: marker を set

```bash
mkdir -p .folio && touch .folio/architect-active
```

これ以降、`architecture/spec/` 配下の Edit/Write が caller-marker hook で allow される。

### Step 2: spec を編集

通常の Edit / Write tool で `architecture/spec/` 配下の spec HTML を編集する。

- path-boundary / jsonld-lint / readme-index hook は別途有効。新規 spec は `spec_path` 配下に置き、JSON-LD は object 形式 `@context` にする。
- README index に未掲載の新 spec は readme-index hook が notify する → cluster README の inventory にも追記する。

### Step 3: 機械検証 (`folio validate`)

```bash
~/.claude/plugins/folio/.claude-plugin/bin/folio validate
```

3-gate (internal link-integrity + jsonld structural + broken-reverse) が **clean (exit 0)** であることを確認する。double-link が崩れたら `~/.claude/plugins/folio/.claude-plugin/bin/folio fix` で reverse を materialize してから再 validate する。

### Step 4: marker を unset (MUST、エラー時も優先実行)

```bash
rm -f .folio/architect-active
```

spec 編集が完了したら**必ず**削除する。怠ると marker が残留し、以後の非意図的 spec 編集が通過する (fail-open リスク)。**エラー・中断時も cleanup を最優先**する。

### セルフチェック

```bash
test -f .folio/architect-active && echo "SET (spec 編集可)" || echo "UNSET (spec 編集は deny される)"
```

- [ ] Step 1 で marker を set したか
- [ ] 編集が `architecture/spec/` 配下に収まっているか (spec_path 外は path-boundary が deny)
- [ ] Step 3 で `folio validate` が clean か
- [ ] Step 4 で marker を削除したか
- [ ] domain の構造を反映する **HTML 視覚要素** (mermaid stateDiagram / sequenceDiagram / flowchart / classDiagram / erDiagram、 `<table>` / `<details>` / `<dl>` 等) を selective に採用したか (canonical list は [rules.html §4.5](../../architecture/spec/rules.html#s4-5-visual)、 grill 時の声かけは [refs/grilling-protocol.md `## 視覚表現レパートリー`](./refs/grilling-protocol.md))。 plain text に止まらず folio の HTML 表現メリットを活用する。

### stale marker の cleanup

異常終了等で `.folio/architect-active` が残留した場合、明示的に削除する: `rm -f .folio/architect-active`。

## Phase F — Quality Review (MUST NOT SKIP)

`folio validate` の機械 gate が検査**しない** folio 固有の 3 品質軸を、LLM review agent で並列検証する。

### 3 review agent を 1 メッセージで並列 spawn

**Agent tool を使い、以下の 3 つの subagent を 1 つのメッセージ内で同時に (並列に) 起動する** (3 つの Agent tool 呼び出しを同一 response にまとめる = 並列実行):

| scoped name | 軸 | 検査内容 |
|-------------|----|---------| 
| `folio:spec-review-ears` | EARS | EARS 5-pattern 網羅 + REQ-ID uniqueness + traceability |
| `folio:spec-review-vocabulary` | vocabulary | P-5 canonical name 違反 + forbidden synonym |
| `folio:spec-review-ssot` | SSoT | P-7 content domain exclusivity + ADR/research 境界 |
| `folio:spec-review-temporal` | temporal | P-4 declarative form + wave-specific narrative 検出 (REQ-CI-011 の LLM ceiling、 ADR-0028 §2.3) |

各 agent には **Phase E で編集した spec file の path 群** と「担当軸を review し構造化 findings (severity / location / rule / fix) を返せ」という指示を渡す。3 agent は read-only (自ら Edit しない) ため、並列で安全に走る。model は `review_model` (default opus)。

> 完成形 §7.2 は当初 Phase F 6 軸構想だったが、X5-γ (ADR-0029) で **v1.0 = 4 軸 (ears / vocabulary / ssot / temporal)** に確定。`spec-review-structure` は `folio validate` (link-integrity + readme-index) が機械被覆ゆえ **cut**、`spec-review-stakeholder` と Phase B/D の `spec-explorer` / `spec-architect` (inline で機能) は **post-1.0 defer**。temporal は REQ-CI-011 declarative-form の LLM ceiling (ADR-0028 §2.3)。

### findings 集約 → 修正適用 (再 Phase E)

1. 3 agent の findings を集約し、severity (critical → low) で整列・重複統合する。
2. **critical / high severity の指摘は folio-architect が修正を適用**する = **Phase E を再実行** (marker set → Edit → `folio validate` → unset)。
3. medium / low は user に提示し、適用するか記録に留めるか判断する。
4. 修正適用後は再度 Phase F を回しても良い (findings が収束するまで)。ただし無限ループを避け、収束しない軸は G で残課題として報告する。

## Phase G — Summary (MUST)

1. **delta marker check** (rules.html §5): 規範要件の改訂は `<ins class="delta" data-delta-id="D-YYYY-MM-DD-NNN">` / `<del class="delta" ...>` で inline trace されているか確認する (該当する変更がある場合)。
2. **変更要約**: 編集した spec / 追加・変更した REQ-ID / Phase F で適用した修正 / 残課題を要約する。
3. marker が unset 済 (`.folio/architect-active` 不在) であることを最終確認する。

---

## 制約・注記

- 本 SKILL は `disable-model-invocation: true`。user が明示的に `/folio-architect` で起動する。
- folio-architect は **SKILL のまま (subagent 化しない)**。Phase F の 3 agent を spawn する orchestrator は main-session 必須 (nesting 制約)。
- review agent は **read-only** (`tools: Read, Grep, Glob`)。spec への Edit は folio-architect が Phase E/F で一元的に行う (caller-marker hook の author 一元性)。
- 7-Phase orchestration + Phase F review agent を実装。X4-D で 3 軸 (ears/vocabulary/ssot)、X5-γ (ADR-0029) で temporal を追加し **v1.0 = 4 review agent**。完成形 §7.2 の残 (spec-explorer / spec-architect / spec-review-stakeholder) は post-1.0 defer、spec-review-structure は `folio validate` 被覆ゆえ cut。

## 参照

- folio-self-spec.html §7.1 (7-Phase PR Cycle) / §7.2 (8 specialist 完成形) / §7.3 (caller marker flow) / §7.4 (5-Layer Defense) / §7.6 (growth path)
- ADR-0027 (X4-D folio-architect 7-Phase 昇格 + review agents 3 個) / ADR-0029 (X5-γ Phase F = 4 review agent: temporal 追加・structure cut・explorer/architect/stakeholder defer) / ADR-0028 (二層 enforcement: REQ-CI-011 を temporal agent ceiling に委譲) / ADR-0031 (mattpocock authoring 吸収: adoption-aware Phase A + grilling Phase C + init lazy)
- rules.html §6 (EARS) / §5 (delta marker) / §10.1 (REQ-CM-001〜003 caller marker)
- verification.html §3.6 REQ-VER-016 (Phase F review agent の検証 contract)
- agents/spec-review-{ears,vocabulary,ssot,temporal}.md (Phase F で spawn する review agent)
- refs/grilling-protocol.md (Phase A/C grilling 規律: spec-aware / gap-driven / persist-as-you-go、mattpocock grill-me/grill-with-docs 由来 MIT-attr)
- .claude-plugin/scripts/check-caller-marker.sh (hybrid enforcement logic)
