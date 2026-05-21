# CLAUDE.md — Claude Code project instructions for folio (Layer 0 META FRAMEWORK)

Claude Code が session 開始時に自動 read する project-level instruction。 本 file の位置づけは `constitution.html` P-11 (HOW を spec に書かない) の **root 例外** として platform binding (HOW) を許容する場所。 将来 `core/bindings/claude-code/` に移管候補だが、 Claude Code 公式 convention に従い root 配置を維持する。

## 0. Identity check (MUST、 最初に確認)

- cwd: `~/projects/local-projects/folio/` で始まることを確認。 異なる場合は folio の spec edit をしてはならない。
- このプロジェクトは **folio (Layer 0 META FRAMEWORK)** である。 以下のいずれでもない:
  - **twill** (`~/projects/local-projects/twill/`、 旧 plugin、 freeze、 historical artifact)
  - **scribe** (将来作成予定の Layer 2 AI 自動実装 plugin、 folio の最初の consumer)
  - 各 typescript webapp / python ML project 等 (Layer 2 consumers)
- 混同した場合は immediate stop し user に確認すること。

## 1. 必読 file (順序)

1. `FOLIO.md` — project identity、 LLM 混同回避用 root marker
2. `constitution.html` — 12 不変原則 3-tier (Always 7 / Ask first 3 / Never 2)
3. `architecture-rules.html` — 3-layer overlay + directory + markup + 7-phase + specialist 仕様

上記 3 file を読まずに spec edit を行ってはならない。

## 2. Spec edit 前 MUST

```bash
export FOLIO_ARCHITECT_CONTEXT=folio-architect
```

`core/spec/`、 `stacks/*/spec/`、 `projects/*/architecture/spec/` 配下を Edit/Write/NotebookEdit する場合の caller marker。 未 set / 異なる値の場合、 PreToolUse hook (`core/hooks/pre-spec-write-boundary.sh`、 将来実装) が permissionDecision=deny を返す。

編集後は必ず:

```bash
unset FOLIO_ARCHITECT_CONTEXT
```

leak 防止 MUST (sub-process env 継承で他 agent が誤動作するため)。

## 3. 3 axis での区別 (LLM 混同回避 5 層防御)

LLM は 3 つの context boundary を混同し得る:
- (a) folio (Layer 0) vs twill (旧 plugin、 freeze)
- (b) folio (Layer 0、 本 repo) vs scribe 等 (Layer 2、 別 repo)
- (c) Layer 1 spec edit (architecture/spec/) vs Layer 2 impl edit (skills/、 src/ 等)

| 層 | folio (Layer 0、 本 repo) | scribe 等 (Layer 2、 別 repo) | twill (旧、 reference のみ) |
|---|---|---|---|
| 物理 path | `~/projects/local-projects/folio/` | `~/projects/local-projects/scribe/` 等 | `~/projects/local-projects/twill/` |
| root marker | `FOLIO.md` "META FRAMEWORK" | `SCRIBE.md` 等 "folio consumer" | (なし) |
| meta tag | `<meta name="folio-layer" content="core">` | `<meta name="folio-layer" content="project">` | (なし) |
| caller marker | `FOLIO_ARCHITECT_CONTEXT=folio-architect` (core 編集時) | 同 env var (Layer 1 spec 編集時) | `TWL_TOOL_CONTEXT` (異名) |
| dir naming | `core/` のみ | `architecture/spec/, howto/, tutorial/, explanation/` + 実装 dir | `plugins/twl/`, `architecture/spec/` (混在) |

5 層全てを通過したときのみ folio repo の spec を編集できる (architecture-rules.html §10 参照)。

## 4. spec philosophy (constitution.html §1)

spec は **未来理想 anchor** であり実装の mirror ではない。 drift は想定内、 機械 diff 不要。 user-AI dialog で spec を natural language reasoning で検証する (P-8 AI dialog accountability)。

OpenSpec の「現在挙動 SSoT」 思想と分岐するため、 spec と実装の差異を 「bug」 と扱わないこと。

## 5. format ルール (constitution P-2)

- spec / ADR / constitution / architecture-rules / changes proposal: HTML
- Markdown 例外: `FOLIO.md` (root marker)、 `README.md` (GitHub 表示用)、 本 `CLAUDE.md` (Claude Code binding)、 `stacks/*/vocabulary.yaml` / `folio.config.yaml` (machine-readable config)

それ以外の Markdown 生成は禁止。

## 6. tailnet preview

ホスト上で `python3 -m http.server 8000` が稼働中。 tailnet device から以下でアクセス可:
- MagicDNS full form: `http://ipatho-server-2.taild4e917.ts.net:8000/<file>`
- IPv4 direct: `http://100.127.217.108:8000/<file>`

(short form `ipatho-server-2:8000` は device の DNS 設定次第で resolve できない場合あり、 full form 推奨。)

## 7. 本 file の更新ルール

- 本 file は HOW (Claude Code 固有 instruction) を含むため P-3/P-11 例外。
- Claude Code platform 以外への移行が必要になった場合、 本 file は `core/bindings/claude-code/CLAUDE.md` へ移動。 root にはその時点で `core/bindings/<new-platform>/AGENTS.md` 等を配置。
- 内容変更時は ADR (`core/decisions/ADR-NNNN-claude-code-binding-*.html`) を起票する。
