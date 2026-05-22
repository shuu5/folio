# FOLIO PROJECT — META FRAMEWORK (Layer 0)

`folio` is a **META framework** for writing architecture specifications. It bundles universal rules and a Claude Code plugin harness as a single distributable Layer 0 package (ESLint pattern). It is **not** a specific project implementation.

## 2-Layer Architecture (overview)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Layer 0 — folio (META FRAMEWORK, this repo)                           │
│  ─────────────────────────────────────────                              │
│  rules:                                                                 │
│    • constitution.html (12 immutable principles, 3-tier)               │
│    • architecture-rules.html (directory + markup + 7-phase + harness)  │
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

- `constitution.html` — 12 immutable principles, 3-tier boundary declarations, 4 mermaid 図.
- `architecture-rules.html` — directory layout, HTML markup, 7-phase PR cycle, harness layer, plugin integration, 8 mermaid 図.
- `.claude-plugin/plugin.json` — plugin manifest (name, version, userConfig).
- `architecture/assets/mermaid.min.js` — self-hosted diagram rendering vendor.

## For AI Agents (Stakeholder Perspective)

When you open a file in this repository:
1. Verify `cwd` starts with `~/projects/local-projects/folio/`.
2. Read `constitution.html` before any spec edit.
3. Read `architecture-rules.html` to understand directory layout, markup conventions, and harness layer.
4. Read `CLAUDE.md` for caller marker convention (the platform-specific binding).
5. Set the caller marker env var (declared in `CLAUDE.md` / `.claude-plugin/plugin.json` userConfig) before writing to spec files.

Do not confuse this with twill conventions (constitution P-12, architecture-rules §7.4).
Do not confuse this with scribe / other Layer 1 consumer projects — those have their own `architecture/spec/`; folio provides the rules + harness they follow.
