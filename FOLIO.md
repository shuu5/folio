# FOLIO PROJECT — This is NOT twill

`folio` is a clean-slate architecture spec project, distinct from the twill plugin.

## What this is

- A universal, AI-Agent-first architecture specification framework.
- HTML-only documents (no Markdown except this root marker).
- 3-layer overlay: `core/` (universal, immutable) → `stacks/` (technology-specific) → `projects/` (individual).
- Future-anchor philosophy: spec is the *ideal future*, not a mirror of current implementation.

## What this is NOT

- This is **not** the twill plugin (`~/projects/local-projects/twill/`).
- This is **not** an OpenSpec / Kiro / Spec Kit clone — those are studied and adapted, not copied.
- This is **not** a Markdown-first project — HTML is the primary format (constitution P-2).

## Entry points

- `constitution.html` — 12 immutable principles, 3-tier boundary declarations.
- `architecture-rules.html` — directory structure, file naming, HTML markup conventions, 7-phase PR cycle.

## For AI Agents (Stakeholder Perspective)

When you open a file in this repository:
1. Verify `cwd` starts with `~/projects/local-projects/folio/`.
2. Read `constitution.html` before any spec edit.
3. Read `architecture-rules.html` to understand directory layout and markup conventions.
4. Set `FOLIO_ARCHITECT_CONTEXT=folio-architect` before writing to `core/spec/`, `stacks/*/spec/`, or `projects/*/architecture/spec/`.

Do not confuse this with twill conventions (e.g., `TWL_TOOL_CONTEXT`, `tool-architect`, `R-1..R-44`).
