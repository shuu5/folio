# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 twill (`~/projects/local-projects/twill/`) / scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `scratch/constitution.html` — folio の 12 不変原則。 **不変資産、 編集禁止**。
- Phase X3 着手中: `scratch/decisions/ADR-0003-plugin-architecture.html` + `scratch/specs/verification.html` (試作 plugin 実装の規範)。

## 2. 編集禁止 (MUST NOT)

現在 folio は試作段階。 以下は **触らない / 作らない**:

- **`scratch/constitution.html`** — 不変資産、 特別枠。 Amendment は user 承認必須 (P-10)。 cross-ref 含め原則として触らない。
- **`scratch/decisions/` 配下** — 既存 ADR は frozen (historical record)。 新規起票は user 承認必須。
- **`architecture/` dir** — **作らない、 dir 自体を存在させない**。 Phase X4+ に user 主導で作成予定。

## 3. 編集可 (試作段階のブラッシュアップ対象)

- **`scratch/specs/` 配下** — `rules.html` / `folio-self-spec.html` / `relations.html` / `verification.html` は試作の進行に応じて自由に改訂する。
- **`scratch/research/` 配下** — user 要望 + 業界調査の集約場所、 自由形式 HTML。
- **`scratch/verification/` 配下** — Phase X3 sandbox verification framework (scenarios / fixtures / baselines / runner.sh)、 ADR-0013 + verification.html。
- **`hooks/` 配下 (plugin root 直下)** — Claude Code 公式仕様で hooks/ は plugin root 直下 MUST、 `hooks/hooks.json` で hook 宣言 (Phase 2.5 移動済)。
- **`.claude-plugin/` 配下** — Phase X3 試作 plugin の manifest (`plugin.json`) + scripts/ skills/ 等の HOW 実装 (hooks/ は plugin root へ移動済、 P-11 部分隔離)。
- **`scratch/` 直下に新規 file / dir 作成** — 思考 memo / 一時 work / prototype 等は柔軟に。

## 4. 作業場所

試作・調査・要望整理は `scratch/`、 plugin 本体実装は `.claude-plugin/` + `hooks/` で行う (Phase X3 着手後)。

- `scratch/` は folio rule に縛られない **工事用の一時的な箱**。
- `hooks/` は Claude Code 公式仕様の hook 宣言 location (plugin root 直下 MUST)。
- `.claude-plugin/` は P-11 部分隔離先 (HOW のうち hooks/ skills/ agents/ commands/ 以外を集約、 詳細は ADR-0003 §2.3 と本 §6 Layout 注記)。
- 完成後 (Phase X4+) に正式 location 移植予定、 `scratch/` は撤去候補。

## 5. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `.claude-plugin/` 配下は HOW のため bash / json / md 等を許容 (P-11 部分隔離)。
- `hooks/hooks.json` は Claude Code 公式 schema 準拠 (JSON)。
- `scratch/verification/scenarios/` は YAML (verification.html §3.2 schema)。

## 6. Directory Layout

```
folio/                                      Phase X3 試作 plugin root (ADR-0003)
├── README.md / CLAUDE.md / common.css     root meta + style (永続)
├── .claude-plugin/                         Claude Code manifest + 内部 HOW (P-11 部分隔離)
│   ├── plugin.json                         Claude Code 必須 manifest (場所固定)
│   ├── scripts/                            hook script (hooks.json から path 指定で参照)
│   ├── skills/                             試作 placeholder (完成形では plugin root へ移動候補)
│   ├── refs/ static/                       試作 placeholder
│   └── bin/folio                           CLI skeleton (将来 plugin root 移動候補)
├── hooks/                                  Claude Code 公式仕様 = plugin root 直下 MUST
│   └── hooks.json                          hook 宣言 (PreToolUse × 2 + PostToolUse、 Phase X3 Step 1-3 = MVP core)
├── scratch/                                作業場所 (試作・調査・実装試行)
│   ├── README.html                         scratch cluster index
│   ├── constitution.html                   (不変、 編集禁止、 特別枠)
│   ├── specs/                              (rules / folio-self-spec / relations / verification + README、 ブラッシュアップ可)
│   ├── decisions/                          (ADR cluster、 既存 frozen、 新規は user 承認)
│   ├── research/                           (要望 + 業界調査、 自由形式)
│   ├── verification/                       (Phase X3 sandbox verification、 ADR-0013)
│   │   ├── scenarios/                      use case 別 YAML (caller-marker / path-boundary / jsonld-lint)
│   │   ├── fixtures/                       テストデータ
│   │   ├── baselines/{reference,local}/    golden (VCS) vs 実行生成 (.gitignore)
│   │   └── runner.sh                       軽量 bash runner (bash + yq + jq)
│   └── assets/                             (mermaid vendor 等)
```

`architecture/` は **存在しない**。 完成形 (Phase X4+) では `.claude-plugin/` 内残部 + 移植先 `architecture/` の役割分担に移行 (P-12)。 Phase X3 着手段階では `.claude-plugin/` + `hooks/` のみ実装、 `architecture/` は作らない。

**Phase 2.5 (commit 1b18ddb)**: 公式 plugin 仕様 (plugins-reference L733: 「`.claude-plugin/` には plugin.json のみ、 hooks/ skills/ 等は plugin root 直下」) に従い、 `hooks/` を plugin root 直下に移動。 scripts/ は `.claude-plugin/scripts/` 維持で P-11 部分隔離継続 (hooks.json command で path 指定参照)。 ADR-0003 §2.3 「.claude-plugin/ 配下に隔離」 の適用範囲は scripts/ 等の HOW 実装に narrowing (ADR 本文は frozen、 適用解釈は本 §6 + specs/README.html §6.2 で trace)。
