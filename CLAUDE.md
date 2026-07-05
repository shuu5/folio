# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `design-intent/spec/constitution.html` — folio の 14 不変原則。 **不変資産、 編集禁止**。
- `design-intent/decisions/ADR-0003-plugin-architecture.html` + `design-intent/spec/verification.html` (試作 plugin 実装の規範)。
- X4-C (ADR-0023) で `scratch/` 試作層を canonical layout (当時 `architecture/` + repo-root `tests/`) へ物理移植済。 `scratch/` は存在しない。 X4-F (ADR-0026) で HOW-test dir を `verification/` → `tests/` に rename済。 X4-G (ADR-0048) で design-intent 空間 dir を `architecture/` → `design-intent/` に rename済 (概念「verification」「architecture」は dir 名と独立、 §6 末尾注記)。

## 2. 編集禁止 (MUST NOT)

- **`design-intent/spec/constitution.html`** — 不変資産、 特別枠。 Amendment は user 承認必須 (P-10)。 cross-ref 含め原則として触らない。 spec graph scan 対象外 (別 `FolioConstitution` schema)。
- **`design-intent/decisions/` 配下の既存 ADR** — frozen (historical record)。 新規起票は user 承認必須。 既存 ADR 本文は改訂せず、 移植に伴う cross-ref rewrite のみ許容済 (P-6 link-integrity)。

## 3. 編集可 (ブラッシュアップ対象)

- **`design-intent/spec/` 配下** — `rules.html` / `folio-self-spec.html` / `relations.html` / `verification.html` / `README.html` は試作の進行に応じて自由に改訂する (constitution は除く、 §2)。
- **`design-intent/research/` 配下** — user 要望 + 業界調査の集約 (exploration domain)、 自由形式 HTML。
- **`tests/` 配下 (repo-root sibling)** — Phase X3 sandbox verification framework (scenarios / fixtures / baselines / e2e / runner.sh)、 ADR-0013 + verification.html (X4-F/ADR-0026 で `verification/` から rename、 spec 名 verification.html は不変)。 executable HOW のため `design-intent/` の外 (P-3 / P-11 / P-13)。
- **`hooks/` 配下 (plugin root 直下)** — Claude Code 公式仕様で hooks/ は plugin root 直下 MUST、 `hooks/hooks.json` で hook 宣言 (Phase 2.5 移動済)。
- **`.claude-plugin/` 配下** — 試作 plugin の manifest (`plugin.json`) + scripts/ + bin/ + refs/ の HOW 実装 (hooks/ + skills/ は plugin root = 公式仕様、 P-11 部分隔離)。

## 4. 作業場所

design-intent spec は `design-intent/`、 検証 framework は repo-root `tests/`、 plugin harness は `.claude-plugin/` + `hooks/` で行う。

- `design-intent/{spec,decisions,research}/` は folio 自身の design-intent 空間 (P-7 3-domain、 folio が canonical layout を self-host)。
- `tests/` は HOW-test sibling (`design-intent/` の外、 executable runner + scenarios + golden)。
- `hooks/` は Claude Code 公式仕様の hook 宣言 location (plugin root 直下 MUST)。
- `.claude-plugin/` は P-11 部分隔離先 (HOW のうち hooks/ skills/ agents/ commands/ 以外を集約、 詳細は ADR-0003 §2.3 と本 §6 Layout 注記)。
- spec edit (`design-intent/spec/` 配下、 `spec_path` 既定) は caller-marker hook で gate される。 `/folio-architect` SKILL 経由か `.folio/architect-active` marker で allow。

## 5. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `.claude-plugin/` 配下は HOW のため bash / json / md 等を許容 (P-11 部分隔離)。
- `hooks/hooks.json` は Claude Code 公式 schema 準拠 (JSON)。
- `tests/scenarios/` は YAML (verification.html §3.2 schema)。

## 6. Directory Layout

```
folio/                                      Layer 0 META FRAMEWORK plugin root (ADR-0003)
├── README.md / CLAUDE.md / common.css     root meta + style (永続)
├── design-intent/                           folio 自身の design-intent 空間 (self-host、 P-7 3-domain)
│   ├── spec/                               constitution / rules / folio-self-spec / relations / verification / README
│   ├── decisions/                          ADR cluster (既存 frozen、 新規は user 承認) + README
│   ├── research/                           exploration (要望 + 業界調査、 superseded planning 退避先)
│   └── assets/                             mermaid vendor 等 (support、 domain でない)
├── tests/                                  HOW-test sibling (design-intent/ の外、 P-3 / P-11 / P-13、 X4-F で verification/ から rename)
│   ├── scenarios/                          use case 別 YAML (caller-marker / path-boundary / jsonld-lint / readme-index / inventory-gen / prime-digest / validate-clean / validate-violations)
│   ├── fixtures/                           テストデータ (validate-violations/spec/ 等)
│   ├── baselines/{reference,local}/        golden (VCS) vs 実行生成 (.gitignore)
│   ├── e2e/                                agent-driven e2e integration (runbook + golden)
│   └── runner.sh                           軽量 bash runner (bash + yq + jq、 REPO_ROOT = ../)
├── hooks/                                  Claude Code 公式仕様 = plugin root 直下 MUST
│   └── hooks.json                          hook 宣言 (PreToolUse × 3 [caller-marker / path-boundary / content-boundary] + PostToolUse × 2 + SessionStart、 MVP core + B5-III tier2 content-boundary)
├── skills/                                 SKILL (公式仕様 = plugin root 直下): folio-architect (spec 編集の正規路) + folio-compress (ADR-0040 圧縮 migration)
├── agents/                                 review subagent (公式仕様 = plugin root 直下): Phase F spec-review-* 5 本 + readability-walk (rules §11.4 readability lens) + doc-type 別 ceiling 対 9 doc-type (persona-walk-{srs,adr,research,principle,spec,vision,glossary,architecture,testcases} = gate I / fidelity-同 9 種 = gate J、 taxonomy §5.3) + completeness-critic-srs (§5.2.6 第 3 lens 候補) + finding-refuter (ceiling 2-pass 汎用・中立 bias)
├── .claude-plugin/                         Claude Code manifest + 内部 HOW (P-11 部分隔離)
│   ├── plugin.json                         Claude Code 必須 manifest (spec_path = design-intent/spec/)
│   ├── scripts/                            hook script (hooks.json から path 指定で参照)
│   ├── bin/folio                           CLI (version / init / inventory / prime / validate / fix / build、 走査 base = design-intent/)
│   └── refs/                               試作 placeholder (X4-D specialist agent 用 ref data 予約)
└── inventory.json                          folio inventory CLI の生成物 (repo-root、 .gitignore)
```

`scratch/` は X4-C (ADR-0023) で撤去済。 constitution + rules + folio-self-spec は `design-intent/spec/` に flat self-host (P-12 Layer 0 一体配布、 ADR-0022)。 `.claude-plugin/` には scripts/ (hook 実装) + bin/folio (CLI) + refs/ (X4-D specialist ref data 予約) が残り、 skills/agents は plugin root に置く (公式仕様)。 X4-F で `.claude-plugin/` 内の空 skills/agents/static placeholder を撤去した (P-11 部分隔離の段階的解消)。

**X4-C (ADR-0023)**: `scratch/{specs→spec,decisions,research,assets}` → `architecture/` (現 `design-intent/`、 X4-G で rename)、 `scratch/constitution.html` → 同 `spec/`、 `scratch/verification/` → repo-root `verification/`、 planning doc (x4-plan / amendment-proposal) は `status=superseded` 化して同 `research/` 退避。 全クロス参照 rewrite (P-6 link-integrity)、 bin/folio scan base + scripts/plugin.json spec_path 更新、 inventory.json 出力先を repo-root へ。 検証: `folio validate` clean + sandbox 8/8 GREEN。

**Phase 2.5 (commit 1b18ddb)**: 公式 plugin 仕様 (plugins-reference L733: 「`.claude-plugin/` には plugin.json のみ、 hooks/ skills/ 等は plugin root 直下」) に従い、 `hooks/` を plugin root 直下に移動。 scripts/ は `.claude-plugin/scripts/` 維持で P-11 部分隔離継続 (hooks.json command で path 指定参照)。 ADR-0003 §2.3 「.claude-plugin/ 配下に隔離」 の適用範囲は scripts/ 等の HOW 実装に narrowing (ADR 本文は frozen、 適用解釈は本 §6 + design-intent/spec/README.html で trace)。

**X4-F (ADR-0026)**: HOW-test dir を `verification/` → `tests/` に rename (folio の bash stack 慣習に整合)。 「verification」 は P-13 概念 + `design-intent/spec/verification.html` contract + `folio validate` として **dir 名と独立に存続** (spec 名・REQ-VER-* は不変)。 test-placement model を是正: (a) spec 適合性 = `folio validate` (framework 提供・普遍・dir なし)、 (b) 実装適合性 = 各 stack 慣習 (`tests/` 等、 folio 非 mandate)。 consumer の (b) test 配置は規定せず、 `folio init` も test dir を scaffold しない (P-13(b))。 frozen ADR は移動ファイルへの `<a href>` のみ tests/ に rewrite (link maintenance、 prose の歴史記述は据置)。 検証: `folio validate` 3-gate clean + sandbox 10/10 GREEN。

**X4-G (ADR-0048)**: design-intent 空間 dir を `architecture/` → `design-intent/` に rename (c5r.7 canonical 語彙「design-intent space」と物理名を一致)。 語彙「architecture」は doc-type (architecture-description) / constitution §1 用法として **dir 名と独立に存続** (X4-F と同じ原理)。 constitution 無改訂 (ADR-0021 の layout 非依存設計により P-10 不要)。 consumer 公開 default (plugin.json `spec_path` / `folio init` scaffold) も同時変更で Layer 0/1 同型維持。 frozen ADR の歴史 prose は据置 (機能参照のみ rewrite)。 検証: `folio validate` 3-gate clean + sandbox 全 GREEN + repo-root landing / render-gate 独立確認。

## 7. Beads Issue Tracker (bd) + scribe

タスク追跡は **bd (beads)**。 SessionStart hook が `bd prime` で bd 基礎の文脈を毎セッション注入する (SSOT = `.beads/PRIME.md`)。 本節は bd 未導入時のフォールバック。

- **タスク = beads / 知識 = doobidoo**: 永続・横断の作業は bd issue で追跡。 知見は doobidoo + 自動メモリ (MEMORY.md) に保存し、 **`bd remember/recall/memories` は使わない**。
- **役割を帯びた規約 (誰が create/dep/close/dolt push するか・終了プロトコル) の SSOT は scribe plugin の role 別 SessionStart 注入** (admin / worker / consult)。 PRIME は role 中立な基礎のみを持つ。
- コードは本リポ慣習 (conventional + 日本語 + Claude footer 無し + explicit `git add`) で commit し main へ push。
