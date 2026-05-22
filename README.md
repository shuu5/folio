# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy. Distributed as a single package; consumed by other repos to write their `architecture/` specifications.

**Status**: v0.4.0-draft (Phase X1 — Constitution + Architecture-Rules complete, plugin skeleton scaffolded)

## 2-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)            : rules + plugin harness 一体配布 (ESLint pattern)
                ↓ provides rules + harness (via folio.config.yaml)
Layer 1 — <consumer-project>/          : architecture/ spec + implementation in same repo
```

`Layer 0.5` 等の小数点表記は採用しない。 詳細図は [`constitution.html` §3 Layer Architecture](./constitution.html) または `FOLIO.md` を参照。

## Entry points

| file | role |
|------|------|
| [`constitution.html`](./constitution.html) | 12 immutable principles (3-tier: Always 7 / Ask first 3 / Never 2), 4 mermaid 図 |
| [`architecture-rules.html`](./architecture-rules.html) | 2-Layer + directory + HTML markup + 7-phase + harness layer + plugin integration + 8 mermaid 図 |
| [`FOLIO.md`](./FOLIO.md) | project identity, 2-Layer diagram, Layer 1 consumer roster |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions (HOW binding, P-11 root exception) |
| [`common.css`](./common.css) | design tokens (inspired by [note via awesome-design-md-jp](https://github.com/kzhrknt/awesome-design-md-jp/blob/main/design-md/note/DESIGN.md): 18px / line-height 2.0 / palt headings / 940px main / dual-shadow elevation / dark mode) |
| [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) | plugin manifest (Claude Code plugin protocol、 v0.4.0-draft) |
| `architecture/assets/mermaid.min.js` | self-hosted Mermaid (no CDN dependency) |

## Planned Layer 1 consumers

| project | role | status |
|---|---|---|
| **scribe** | AI auto-implementation plugin (folio harness thin wrapper + impl auto-gen helper) | repo not yet created (Phase X3 にて) |
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

This is **not** the twill plugin (`~/projects/local-projects/twill/`). twill is a frozen historical artifact; folio extracts twill's universal-ready principles (declarative narrative, link integrity, caller marker idea, drift prevention) as a clean-slate framework and leaves twill-specific implementation behind. See constitution P-12 and architecture-rules.html §7.4 for the 3-axis × 5-layer LLM-confusion-avoidance system.
