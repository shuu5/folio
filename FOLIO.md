# FOLIO PROJECT — META FRAMEWORK (Layer 0)

`folio` is a **META framework** — a set of universal rules for writing architecture specifications. It is **not** an implementation, **not** a Claude Code plugin, **not** a specific project. It is the *rules layer* that other projects consume.

## 3-Layer Architecture (overview)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 0 — META FRAMEWORK (this repo: folio)                       │
│  ────────────────────────────────────────                           │
│  • constitution.html (12 immutable principles)                     │
│  • architecture-rules.html (3-layer + directory + markup + 7-phase)│
│  • core/agents/, core/checks/, core/templates/                     │
│  • Universal, immutable, multi-project reusable                    │
│  • Lives in its own git repo                                       │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ provides rules
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1 — ARCHITECTURE SPECS (per-project, in each project's repo) │
│  ──────────────────────────────────────────────────────────────     │
│  • <project>/architecture/spec/, decisions/, changes/, ...          │
│  • Each project writes its spec using folio rules                   │
│  • Lives inside the project repo, not in folio                      │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ spec to follow
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 2 — IMPLEMENTATIONS (per-project, also in each project repo) │
│  ───────────────────────────────────────────────────────────────    │
│  • scribe   (AI auto-implementation plugin, the first consumer)     │
│  • specific TypeScript webapp                                       │
│  • specific Python ML project                                       │
│  • ... (any project that consumes folio rules)                      │
│  • Lives inside the project repo, follows architecture/ spec        │
└─────────────────────────────────────────────────────────────────────┘
```

## What `folio` is

- A universal, AI-Agent-first architecture **spec-writing framework**.
- HTML-only documents (no Markdown except this root marker, README.md, CLAUDE.md, and YAML configs).
- Future-anchor philosophy: a spec is the *ideal future*, not a mirror of current implementation.
- Consumed by other repos via `folio.config.yaml` declaration.

## What `folio` is NOT

- Not an AI agent / not a Claude Code plugin (that role belongs to the **scribe** project, Layer 2).
- Not the twill plugin (`~/projects/local-projects/twill/`, freeze, historical artifact).
- Not an OpenSpec / Kiro / Spec Kit clone — those are studied and adapted, not copied.
- Not a Markdown-first project — HTML is the primary format (constitution P-2).
- Not a monorepo — does not contain `stacks/` or `projects/` directories; consumers are in **separate git repos**.

## Layer 2 consumers (planned)

| project | role | repo (planned) |
|---|---|---|
| **scribe** | AI auto-implementation plugin (twill v2 successor, Claude Code plugin) | separate repo (`~/projects/local-projects/scribe/`, to be created) |
| (future) typescript webapps | each webapp consumes folio rules for its architecture/ spec | one repo per webapp |
| (future) python ML projects | same | one repo per project |

## Entry points

- `constitution.html` — 12 immutable principles, 3-tier boundary declarations.
- `architecture-rules.html` — directory layout, HTML markup conventions, 7-phase PR cycle, 8 specialist agents, 5-layer LLM-confusion-avoidance system.

## For AI Agents (Stakeholder Perspective)

When you open a file in this repository:
1. Verify `cwd` starts with `~/projects/local-projects/folio/`.
2. Read `constitution.html` before any spec edit.
3. Read `architecture-rules.html` to understand directory layout and markup conventions.
4. Set `FOLIO_ARCHITECT_CONTEXT=folio-architect` before writing to `core/spec/`.

Do not confuse this with twill conventions (e.g., `TWL_TOOL_CONTEXT`, `tool-architect`, `R-1..R-44`).
Do not confuse this with scribe / consumer projects — those have their own `architecture/spec/`; folio provides the rules they follow.
