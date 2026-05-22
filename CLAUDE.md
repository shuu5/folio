# CLAUDE.md — Claude Code project instructions for folio (Layer 0 META FRAMEWORK)

Claude Code が session 開始時に自動 read する project-level instruction。 本 file の位置づけは `constitution.html` P-11 (HOW を spec に書かない) の **root 例外** として platform binding (HOW) を許容する場所 (architecture-rules.html §9 Bindings)。

## 0. Identity check (MUST、 最初に確認)

- cwd: `~/projects/local-projects/folio/` で始まることを確認。 異なる場合は folio の spec edit をしてはならない。
- このプロジェクトは **folio (Layer 0 META FRAMEWORK)** である。 以下のいずれでもない:
  - **twill** (`~/projects/local-projects/twill/`、 旧 plugin、 freeze、 historical artifact)
  - **scribe** (将来作成予定の Layer 1 AI 自動実装 plugin、 folio の最初の consumer)
  - 各 typescript webapp / python ML project 等 (Layer 1 consumers)
- 混同した場合は immediate stop し user に確認すること。

## 1. 必読 file (順序)

1. `FOLIO.md` — project identity、 2-Layer 図、 Layer 1 consumer roster
2. `constitution.html` — 12 不変原則 3-tier (Always 7 / Ask first 3 / Never 2)、 4 mermaid 図
3. `architecture-rules.html` — directory + markup + 7-phase + Harness Layer + Plugin Integration、 8 mermaid 図

上記 3 file を読まずに spec edit を行ってはならない。

## 2. Spec edit 前 MUST (caller marker)

```bash
export FOLIO_ARCHITECT_CONTEXT=folio-architect
```

これは architecture-rules.html §7.3 で規定される caller marker 機構の **Claude Code 固有 binding 実装** である (架空 platform-agnostic な §7.3 WHAT に対する、 本書の HOW binding)。 spec 編集を行う tool (Edit/Write/NotebookEdit) を呼ぶ前に必須。

`core/spec/`、 各 Layer 1 consumer の `architecture/spec/` 配下を編集する場合の caller marker。 未 set / 異なる値の場合、 PreToolUse hook (`.claude-plugin/hooks/`、 Phase X2 で実装) が permissionDecision=deny を返す。

編集後は必ず:

```bash
unset FOLIO_ARCHITECT_CONTEXT
```

leak 防止 MUST (sub-process env 継承で他 agent が誤動作するため)。

## 3. 3 axis での区別 (LLM 混同回避 5 層防御、 architecture-rules §7.4)

LLM は 3 つの context boundary を混同し得る:
- **(a)** folio (Layer 0) vs twill (旧 plugin、 freeze)
- **(b)** folio (Layer 0、 本 repo) vs scribe 等 (Layer 1、 別 repo)
- **(c)** Layer 1 spec edit (`architecture/spec/`) vs Layer 1 実装 edit (`skills/`、 `src/` 等)

| 層 | folio (Layer 0、 本 repo) | scribe 等 (Layer 1、 別 repo) | twill (旧、 reference のみ) |
|---|---|---|---|
| L1 物理 path | `~/projects/local-projects/folio/` | `~/projects/local-projects/scribe/` 等 | `~/projects/local-projects/twill/` |
| L2 root marker | `FOLIO.md` "META FRAMEWORK" | `SCRIBE.md` 等 "folio consumer" | (なし) |
| L3 meta tag | `<meta folio-layer="core">` | `<meta folio-layer="project">` + `<meta folio-project="scribe">` | (なし) |
| L4 caller marker | `FOLIO_ARCHITECT_CONTEXT=folio-architect` (本書 §2 で規定) | 同 env var (Layer 1 spec 編集時) | `TWL_TOOL_CONTEXT` (異名) |
| L5 dir naming | `.claude-plugin/` | `architecture/spec/, howto/, tutorial/, explanation/` + 実装 dir | `plugins/twl/`, `architecture/spec/` (混在) |

5 層全てを通過したときのみ folio repo の spec を編集できる (architecture-rules.html §7.4 参照)。

## 4. spec philosophy (constitution.html §1)

spec は **未来理想 anchor** であり実装の mirror ではない。 drift は想定内、 機械 diff 不要。 user-AI dialog で spec を natural language reasoning で検証する (P-8 AI dialog accountability)。

OpenSpec の「現在挙動 SSoT」 思想と分岐するため、 spec と実装の差異を 「bug」 と扱わないこと。

## 5. format ルール (constitution P-2)

- spec / ADR / constitution / architecture-rules / changes proposal: HTML
- Markdown 例外: `FOLIO.md` (root marker)、 `README.md` (GitHub 表示用)、 本 `CLAUDE.md` (Claude Code binding)、 `folio.config.yaml` / `vocabulary.yaml` 等 (YAML config)

それ以外の Markdown 生成は禁止。

## 6. plugin 構造 (architecture-rules.html §8)

folio は **Claude Code plugin として配布**される。 plugin 構成:

```
.claude-plugin/
├── plugin.json            # manifest (userConfig: spec_path / caller_marker_env / caller_marker_value / review_model)
├── skills/                # 8 skill (folio-init, folio-architect, folio-spec-edit, folio-validate, review-* × 4)
├── agents/                # 8 specialist agents (explorer, architect, review-* × 6)
├── hooks/hooks.json       # PreToolUse caller marker + PostToolUse spec validate (Phase X2 で実装)
├── scripts/               # CI check scripts (Python / shell)
├── bin/                   # folio CLI executables
├── refs/                  # skill + agent 共有 reference (principles, vocabulary, EARS templates)
└── static/                # plugin-bundled static assets
```

Phase X1 では plugin.json + skeleton README のみ。 実装 (skill content / agent content / hook script) は Phase X2。

## 7. tailnet preview

ホスト上で `python3 -m http.server 8000` が稼働中。 tailnet device から以下でアクセス可:
- MagicDNS full form: `http://ipatho-server-2.taild4e917.ts.net:8000/<file>`
- IPv4 direct: `http://100.127.217.108:8000/<file>`

(short form `ipatho-server-2:8000` は device の DNS 設定次第で resolve できない場合あり、 full form 推奨。)

## 8. 本 file の位置づけ

- 本 file は **HOW (caller marker bash command、 cwd 絶対 path、 5 層防御 table) を含む** Claude Code 固有 instruction。 constitution P-11 (HOW を spec に書かない) の **root 例外** として配置。
- Claude Code 公式 convention に従い repo root 維持。 将来 platform 拡張時は `core/bindings/claude-code/` への移管も検討 (architecture-rules §9 Bindings)。
- 内容変更時は ADR 起票 + constitution の変更通知が必要 (constitution P-10)。
