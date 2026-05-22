# FOLIO PROJECT — META FRAMEWORK (Layer 0)

`folio` is a **META framework** for writing architecture specifications. It bundles universal rules and a Claude Code plugin harness as a single distributable Layer 0 package (ESLint pattern). It is **not** a specific project implementation.

## 2-Layer Architecture (overview)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Layer 0 — folio (META FRAMEWORK, this repo)                           │
│  ─────────────────────────────────────────                              │
│  rules:                                                                 │
│    • constitution.html (12 immutable principles, 3-tier)               │
│    • rules.html (Layer 1 向け universal rules: markup + naming + §10)  │
│    • folio-self-spec.html (folio Layer 0 self-spec: harness + plugin)  │
│  plugin harness (.claude-plugin/):                                     │
│    • plugin.json manifest with userConfig                              │
│    • skills/ × 8 (folio-init, folio-architect, folio-spec-edit, ...)   │
│    • agents/ × 8 (8 specialist agents)                                 │
│    • hooks/ (PreToolUse caller marker + PostToolUse validate)          │
│    • scripts/ + bin/ (CI checks + folio CLI)                           │
│    • refs/ + static/                                                   │
│  Universal, immutable, multi-project reusable. Single git repo.        │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ provides rules + harness
                                 │ (consumer declares in folio.config.yaml)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Layer 1 — consumer projects (per-project, each in its own git repo)   │
│  ──────────────────────────────────────────────────────────             │
│  Each consumer repo contains:                                          │
│    • folio.config.yaml (declares folio_version, override userConfig)   │
│    • architecture/ (folio rules で書かれた spec)                       │
│        spec/ + howto/ + tutorial/ + explanation/ (Diátaxis 4 modes)    │
│        + decisions/ + changes/ + research/ + steering/ + archive/      │
│    • implementation directories (src/, skills/, etc.)                  │
│                                                                         │
│  Examples:                                                             │
│    • scribe          — AI auto-implementation plugin (special role:    │
│                        folio harness の thin wrapper + impl auto-gen)  │
│    • my-ts-webapp    — regular consumer                                │
│    • my-python-ml    — regular consumer                                │
└─────────────────────────────────────────────────────────────────────────┘
```

`Layer 0.5` 等の小数点表記は採用しない。 harness は Layer 0 の構成要素として一体配布される (constitution P-12)。

## What `folio` is

- A universal, AI-Agent-first architecture **spec-writing framework + harness**.
- Distributed as a Claude Code plugin (`.claude-plugin/`).
- HTML-only spec documents. Markdown 例外: `FOLIO.md`, `README.md`, `CLAUDE.md`, YAML configs.
- Future-anchor philosophy: a spec is the *ideal future*, not a mirror of current implementation.
- Consumed by other repos via `folio.config.yaml` declaration.

## What `folio` is NOT

- Not a specific AI agent / consumer project (those are Layer 1; the first planned consumer is **scribe**, AI auto-implementation plugin).
- Not the twill plugin (`~/projects/local-projects/twill/`, freeze, historical artifact).
- Not an OpenSpec / Kiro / Spec Kit clone — those are studied and adapted, not copied.
- Not a Markdown-first project — HTML is the primary format (constitution P-2).
- Not a monorepo — does **not** contain `stacks/` or `projects/` directories; consumers are in separate git repos.
- Not MCP-based — `harness = skill + hook + CLI (local process)`, no network API.

## Layer 1 consumers (planned)

| project | role | repo (planned) |
|---|---|---|
| **scribe** | AI auto-implementation plugin. Special role: folio harness の thin wrapper + impl auto-gen helper for other consumers. | separate repo (`~/projects/local-projects/scribe/`, to be created in Phase X3) |
| (future) typescript webapps | each webapp consumes folio rules for its `architecture/` spec | one repo per webapp |
| (future) python ML projects | same | one repo per project |

## Entry points

- `constitution.html` — 12 immutable principles, 3-tier boundary declarations, 2 mermaid 図 (v0.4.2-draft 以降: 4 → 2 図、 §3 §4 cross-ref スタブ).
- `rules.html` — Layer 1 consumer 向け universal rules (directory layout + HTML markup + delta marker + EARS + §10 Mandatory Actions with REQ-CM/CI-* IDs).
- `folio-self-spec.html` — folio Layer 0 framework 自身の architecture spec (2-Layer + folio repo layout + Harness Layer + Plugin Integration + Bindings、 8 mermaid 図、 provisional: Phase X3+ で self-application 予定).
- `decisions/ADR-NNNN-<slug>.html` — Architecture Decision Records (ADR-0001 = architecture-rules split).
- `.claude-plugin/plugin.json` — plugin manifest (name, version, userConfig).
- `architecture/assets/mermaid.min.js` — self-hosted diagram rendering vendor.

## For AI Agents (Stakeholder Perspective)

When you open a file in this repository:
1. Verify `cwd` starts with `~/projects/local-projects/folio/`.
2. Read `constitution.html` before any spec edit.
3. Read `rules.html` for Layer 1 consumer rules (markup + naming + §10 Mandatory Actions).
4. Read `folio-self-spec.html` for folio framework 自身の architecture (Layer 0 = 本書の対象).
5. Read `CLAUDE.md` for caller marker convention (the platform-specific binding).
6. Set the caller marker env var (declared in `CLAUDE.md` / `.claude-plugin/plugin.json` userConfig) before writing to spec files.

Do not confuse this with twill conventions (constitution P-12, folio-self-spec.html §7.4 5-Layer Defense).
Do not confuse this with scribe / other Layer 1 consumer projects — those have their own `architecture/spec/`; folio provides the rules + harness they follow.
