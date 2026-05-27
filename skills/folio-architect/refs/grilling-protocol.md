# folio grilling protocol

folio-architect の **Phase A (adoption-state 検出 + greenfield onboarding)** と **Phase C (Clarifying)** が参照する、spec-aware な 1 問ずつの elicitation 規律。「実装前に対話で要件を詰める」普遍的上流活動を folio の design-intent 著述に内在化する (ADR-0031)。

<!-- Adapted from mattpocock grill-me + grill-with-docs (github.com/mattpocock/skills, MIT License, (c) Matt Pocock). folio 化 (spec-aware / gap-driven / persist-as-you-go) は ADR-0031 §2.2 による。 -->

## Core stance (grill-me 由来)

- **1 問ずつ**尋ねる。複数問を束ねない。
- 設計ツリーを枝ごとに歩き、決定間の依存を 1 つずつ解消する。
- **各問いに推奨回答を添える** (silently choosing は禁止、constitution P-8)。
- **codebase / 既存 spec を読めば分かることは尋ねず、読んで確かめる**。
- "relentless" は<strong>未解決論点の徹底</strong>にかかる。解決済みの再尋問ではない。

## spec-aware (folio 固有)

汎用 grill と違い、folio の grilling は質問を folio の規範資産に紐づける:

- **概念が出たら** → canonical name を提案し (P-5)、`vocabulary.yaml` に persist する (canonical + 1 行 definition、 必要なら relationships / flagged_ambiguities も。 schema は rules §3)。
- **要件が出たら** → EARS pattern (rules §6) の scenario で境界を stress-test する (ubiquitous / event-driven / state-driven / unwanted / optional)。
- **曖昧語が出たら** → 具体例・具体シナリオで研ぎ、EARS の測定可能条件に落とす。
- **hard-to-reverse かつ surprising かつ real-trade-off な決定が出たら** → ADR を offer する (sparingly、rules §10.3。新 ADR 起票は user 承認 MUST)。

## gap-driven (settled を再尋問しない)

- 尋ねる前に **既存 spec / `vocabulary.yaml` / ADR / 会話 context** を読み、**settled (解決済み) を認識**する。
- **残る gap (未解決論点) だけ**を grill する。
- これにより `grill-me` 先行・folio-architect の複数回反復が**非冗長**になる (settled は artifact に宿るため)。

## persist-as-you-go

grilling 中に決まったものを、その場で適切な層に永続化する:

- **軽い anchor** (caller-marker 非 gate ゆえ会話中に自由追記):
  - 用語 → `vocabulary.yaml` に inline 追記 (batch しない)。
  - §10.3 を満たす決定 → ADR を offer (承認後に decisions/ へ)。
- **重い spec** (`architecture/spec/` の HTML) → **Phase E** で caller-marker→Edit→`folio validate`→unset により materialize する。
- settled を artifact に宿すことで、後続の起動が再尋問にならない (repeatability は read-persist ループからの創発)。

## 2 つの grilling context

### greenfield onboarding grill (Phase A: 実体ある spec が未だ無い)

**目標**: 中身ある (= 非 hollow) constitution / overview を lazy-write できるだけの実体を引き出す。`folio init` は構造 (config + cluster README) のみ生成済で、実体は未だ無い状態が入口。

引き出す論点 (1 問ずつ、推奨回答付き):

1. この project が**守る不変原則**は何か (移植しても書き直し不要な WHAT、platform 非依存)。→ constitution §2 (EARS ubiquitous `The project SHALL ...`)。
2. **system は何を解決し、誰 / 何と相互作用する**か。→ overview §2 (System Context)。
3. 主要**コンポーネントと責務**は。→ overview §3 (Building Blocks)。
4. **domain 用語** (頻出する名詞・概念)。→ `vocabulary.yaml` (canonical + forbidden synonym)。

**MUST**: 実体が引き出せるまで constitution / overview を**書かない**。空 placeholder (`P-1: SHALL <ここに記述>` 等) を残すのは禁止 — それは whisper の hollow-constitution failure そのものである。原則が 1 つも無い project なら constitution.html を作らない (folio Layer 0 core を継承すれば足りる)。

### maintenance grill (Phase A: 実体ある spec が既に在る)

**目標**: 既存設計に対する spec 変更を明確化する。

- 対象 spec + 関連 (cross-ref / ADR / vocabulary) を読み、変更が埋める**gap** を特定する。
- 変更の**未解決な側面だけ**を grill する (既存の settled は尋ねない)。
- 既存 spec との vocabulary (P-5) / EARS / SSoT (P-7) 整合を確認する。

## anti-patterns (やってはいけない)

- settled 済みを尋ねる (gap-driven 違反)。
- 空 placeholder spec を書く (lazy 違反、hollow spec を生む)。
- glossary 更新を batch する (inline persist せよ)。
- 複数問を一度に投げる (1 問ずつ)。
- codebase / spec を読めば分かることを尋ねる。

## 参照

- folio-self-spec.html §7.1 (7-Phase: Phase A adoption-aware / Phase C grilling)
- rules.html §6 (EARS) / §10.3 (ADR Worthiness、REQ-ADR-001) / §5 (delta marker) / §3 (vocabulary.yaml schema)
- ADR-0031 (mattpocock authoring 吸収: §2.2 grilling / §2.3 adoption-aware + lazy init)
- `vocabulary.yaml` (P-5 canonical name SSoT、canonical/forbidden + optional definition/relationships/flagged_ambiguities)
