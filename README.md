# folio

A clean-slate, AI-Agent-first architecture spec framework. HTML-only, 3-layer overlay (core / stacks / projects), future-anchor philosophy.

**Status**: v0.1.0-draft (Phase 4.5 — Constitution Draft + Reconcile)

## Entry points

| file | role |
|------|------|
| [`constitution.html`](./constitution.html) | 12 immutable principles (3-tier: Always 7 / Ask first 3 / Never 2) |
| [`architecture-rules.html`](./architecture-rules.html) | 3-layer overlay, directory structure, HTML markup conventions, 7-phase PR cycle, 8 specialist agents |
| [`FOLIO.md`](./FOLIO.md) | project identity (LLM-agnostic root marker) |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions (HOW binding, P-11 root exception) |
| [`common.css`](./common.css) | design tokens (inspired by [note via awesome-design-md-jp](https://github.com/kzhrknt/awesome-design-md-jp/blob/main/design-md/note/DESIGN.md): 18px article body, line-height 2.0, palt heading, 620px width, dual-shadow elevation, dark mode) |

## Local preview (tailnet)

`python3 -m http.server 8000` is served on `ipatho-server-2` (port 8000, 0.0.0.0 bind). Use one of:

- **MagicDNS (full form, most reliable across devices)**:
  - <http://ipatho-server-2.taild4e917.ts.net:8000/constitution.html>
  - <http://ipatho-server-2.taild4e917.ts.net:8000/architecture-rules.html>
- **IPv4 direct**: <http://100.127.217.108:8000/> (then click `constitution.html` / `architecture-rules.html`)
- MagicDNS short form (`http://ipatho-server-2:8000/`) may fail to resolve on some devices depending on DNS configuration; prefer the full form above.

(Reachable only from tailnet-joined devices.)

## Philosophy (one-paragraph)

spec is the *ideal future anchor*, not a mirror of current implementation. drift between spec and code is *expected* — the spec's job is to prevent ad-hoc divergence by making user-AI dialog converge on a shared, declarative, future-oriented document. See `constitution.html` §1 Purpose for the full statement.

## Distinction from twill

This is **not** the twill plugin (`~/projects/local-projects/twill/`). folio is a separate git repository with its own caller marker (`FOLIO_ARCHITECT_CONTEXT`, distinct from `TWL_TOOL_CONTEXT`) and directory naming. See constitution.html P-12 and architecture-rules.html §10 for the 5-layer LLM-confusion-avoidance system.
