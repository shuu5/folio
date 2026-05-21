# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy. Consumed by other repos to write their `architecture/` specifications.

**Status**: v0.2.0-draft (Phase 4.5 — Constitution Draft + Reconcile)

## 3-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)        : universal rules for writing architecture specs
                ↓ provides rules
Layer 1 — <project>/architecture/  : spec written using folio rules (lives in each project repo)
                ↓ spec to follow
Layer 2 — <project>/ (impl)        : implementation (lives in each project repo)
```

**folio repo contains only Layer 0** (META FRAMEWORK). Layer 1 and Layer 2 live in separate consumer repos. See `FOLIO.md` for the full diagram.

## Entry points

| file | role |
|------|------|
| [`constitution.html`](./constitution.html) | 12 immutable principles (3-tier: Always 7 / Ask first 3 / Never 2) |
| [`architecture-rules.html`](./architecture-rules.html) | 3-layer repo separation, directory structure, HTML markup conventions, 7-phase PR cycle, 8 specialist agents |
| [`FOLIO.md`](./FOLIO.md) | project identity, 3-layer diagram, Layer 2 consumer roster |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions (HOW binding, P-11 root exception) |
| [`common.css`](./common.css) | design tokens (inspired by [note via awesome-design-md-jp](https://github.com/kzhrknt/awesome-design-md-jp/blob/main/design-md/note/DESIGN.md): 18px / line-height 2.0 / palt headings / 940px main / dual-shadow elevation / dark mode) |

## Planned Layer 2 consumers

| project | role | status |
|---|---|---|
| **scribe** | AI auto-implementation plugin (twill v2 successor, Claude Code plugin) | repo not yet created |
| (future) TypeScript webapps | each consumes folio rules | — |
| (future) Python ML projects | same | — |

## Local preview (tailnet)

`python3 -m http.server 8000` is served on `ipatho-server-2` (port 8000, 0.0.0.0 bind):

- **MagicDNS full form**:
  - <http://ipatho-server-2.taild4e917.ts.net:8000/constitution.html>
  - <http://ipatho-server-2.taild4e917.ts.net:8000/architecture-rules.html>
- **IPv4 direct**: <http://100.127.217.108:8000/>
- (MagicDNS short form `http://ipatho-server-2:8000/` may fail to resolve on some devices; prefer the full form.)

(Reachable only from tailnet-joined devices.)

## Philosophy (one-paragraph)

A spec is the *ideal future anchor*, not a mirror of current implementation. drift between spec and code is *expected* — the spec's job is to prevent ad-hoc divergence by making user-AI dialog converge on a shared, declarative, future-oriented document. See `constitution.html` §1 Purpose for the full statement.

## Distinction from twill

This is **not** the twill plugin (`~/projects/local-projects/twill/`). twill is a frozen historical artifact; folio extracts twill's universal-ready principles (declarative narrative, link integrity, caller marker, drift prevention) as a clean-slate framework and leaves twill-specific implementation behind. See constitution P-12 and architecture-rules.html §10 for the 3-axis × 5-layer LLM-confusion-avoidance system.
