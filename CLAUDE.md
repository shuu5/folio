# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 twill (`~/projects/local-projects/twill/`) / scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `architecture/spec/constitution.html` — folio の 13 不変原則。 **不変資産、 編集禁止**。
- `architecture/decisions/ADR-0003-plugin-architecture.html` + `architecture/spec/verification.html` (試作 plugin 実装の規範)。
- X4-C (ADR-0023) で `scratch/` 試作層を canonical layout (`architecture/` + repo-root `verification/`) へ物理移植済。 `scratch/` は存在しない。

## 2. 編集禁止 (MUST NOT)

- **`architecture/spec/constitution.html`** — 不変資産、 特別枠。 Amendment は user 承認必須 (P-10)。 cross-ref 含め原則として触らない。 spec graph scan 対象外 (別 `FolioConstitution` schema)。
- **`architecture/decisions/` 配下の既存 ADR** — frozen (historical record)。 新規起票は user 承認必須。 既存 ADR 本文は改訂せず、 移植に伴う cross-ref rewrite のみ許容済 (P-6 link-integrity)。

## 3. 編集可 (ブラッシュアップ対象)

- **`architecture/spec/` 配下** — `rules.html` / `folio-self-spec.html` / `relations.html` / `verification.html` / `README.html` は試作の進行に応じて自由に改訂する (constitution は除く、 §2)。
- **`architecture/research/` 配下** — user 要望 + 業界調査の集約 (exploration domain)、 自由形式 HTML。
- **`verification/` 配下 (repo-root sibling)** — Phase X3 sandbox verification framework (scenarios / fixtures / baselines / e2e / runner.sh)、 ADR-0013 + verification.html。 executable HOW のため `architecture/` の外 (P-3 / P-11 / P-13)。
- **`hooks/` 配下 (plugin root 直下)** — Claude Code 公式仕様で hooks/ は plugin root 直下 MUST、 `hooks/hooks.json` で hook 宣言 (Phase 2.5 移動済)。
- **`.claude-plugin/` 配下** — 試作 plugin の manifest (`plugin.json`) + scripts/ skills/ 等の HOW 実装 (hooks/ は plugin root へ移動済、 P-11 部分隔離)。

## 4. 作業場所

design-intent spec は `architecture/`、 検証 framework は repo-root `verification/`、 plugin harness は `.claude-plugin/` + `hooks/` で行う。

- `architecture/{spec,decisions,research}/` は folio 自身の design-intent 空間 (P-7 3-domain、 folio が canonical layout を self-host)。
- `verification/` は HOW-test sibling (`architecture/` の外、 executable runner + scenarios + golden)。
- `hooks/` は Claude Code 公式仕様の hook 宣言 location (plugin root 直下 MUST)。
- `.claude-plugin/` は P-11 部分隔離先 (HOW のうち hooks/ skills/ agents/ commands/ 以外を集約、 詳細は ADR-0003 §2.3 と本 §6 Layout 注記)。
- spec edit (`architecture/spec/` 配下、 `spec_path` 既定) は caller-marker hook で gate される。 `/folio-architect` SKILL 経由か `.folio/architect-active` marker で allow。

## 5. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `.claude-plugin/` 配下は HOW のため bash / json / md 等を許容 (P-11 部分隔離)。
- `hooks/hooks.json` は Claude Code 公式 schema 準拠 (JSON)。
- `verification/scenarios/` は YAML (verification.html §3.2 schema)。

## 6. Directory Layout

```
folio/                                      Layer 0 META FRAMEWORK plugin root (ADR-0003)
├── README.md / CLAUDE.md / common.css     root meta + style (永続)
├── architecture/                           folio 自身の design-intent 空間 (self-host、 P-7 3-domain)
│   ├── spec/                               constitution / rules / folio-self-spec / relations / verification / README
│   ├── decisions/                          ADR cluster (既存 frozen、 新規は user 承認) + README
│   ├── research/                           exploration (要望 + 業界調査、 superseded planning 退避先)
│   └── assets/                             mermaid vendor 等 (support、 domain でない)
├── verification/                           HOW-test sibling (architecture/ の外、 P-3 / P-11 / P-13)
│   ├── scenarios/                          use case 別 YAML (caller-marker / path-boundary / jsonld-lint / readme-index / inventory-gen / prime-digest / validate-clean / validate-violations)
│   ├── fixtures/                           テストデータ (validate-violations/spec/ 等)
│   ├── baselines/{reference,local}/        golden (VCS) vs 実行生成 (.gitignore)
│   ├── e2e/                                agent-driven e2e integration (runbook + golden)
│   └── runner.sh                           軽量 bash runner (bash + yq + jq、 REPO_ROOT = ../)
├── hooks/                                  Claude Code 公式仕様 = plugin root 直下 MUST
│   └── hooks.json                          hook 宣言 (PreToolUse × 2 + PostToolUse = MVP core)
├── .claude-plugin/                         Claude Code manifest + 内部 HOW (P-11 部分隔離)
│   ├── plugin.json                         Claude Code 必須 manifest (spec_path = architecture/spec/)
│   ├── scripts/                            hook script (hooks.json から path 指定で参照)
│   ├── bin/folio                           CLI (version / inventory / prime / validate、 走査 base = architecture/)
│   ├── skills/ refs/ static/               試作 placeholder
└── inventory.json                          folio inventory CLI の生成物 (repo-root、 .gitignore)
```

`scratch/` は X4-C (ADR-0023) で撤去済。 constitution + rules + folio-self-spec は `architecture/spec/` に flat self-host (P-12 Layer 0 一体配布、 ADR-0022)。 完成形では `.claude-plugin/` 内 skills/ 等を plugin root 直下へ移動する余地が残る (P-11 部分隔離の段階的解消)。

**X4-C (ADR-0023)**: `scratch/{specs→spec,decisions,research,assets}` → `architecture/`、 `scratch/constitution.html` → `architecture/spec/`、 `scratch/verification/` → repo-root `verification/`、 planning doc (x4-plan / amendment-proposal) は `status=superseded` 化して `architecture/research/` 退避。 全クロス参照 rewrite (P-6 link-integrity)、 bin/folio scan base + scripts/plugin.json spec_path 更新、 inventory.json 出力先を repo-root へ。 検証: `folio validate` clean + sandbox 8/8 GREEN。

**Phase 2.5 (commit 1b18ddb)**: 公式 plugin 仕様 (plugins-reference L733: 「`.claude-plugin/` には plugin.json のみ、 hooks/ skills/ 等は plugin root 直下」) に従い、 `hooks/` を plugin root 直下に移動。 scripts/ は `.claude-plugin/scripts/` 維持で P-11 部分隔離継続 (hooks.json command で path 指定参照)。 ADR-0003 §2.3 「.claude-plugin/ 配下に隔離」 の適用範囲は scripts/ 等の HOW 実装に narrowing (ADR 本文は frozen、 適用解釈は本 §6 + architecture/spec/README.html で trace)。
