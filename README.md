# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy. Distributed as a single package; consumed by other repos to write their `architecture/` specifications.

**Status**: v0.4.2-draft (Phase X2 — architecture-rules.html を rules.html + folio-self-spec.html に split 済、 ADR-0001 v3、 plugin content 実装は次)

## 2-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)            : rules + plugin harness 一体配布 (ESLint pattern)
                ↓ provides rules + harness (via folio.config.yaml)
Layer 1 — <consumer-project>/          : architecture/ spec + implementation in same repo
```

`Layer 0.5` 等の小数点表記は採用しない。 詳細図は [`folio-self-spec.html` §1 2-Layer Architecture](./folio-self-spec.html) または `FOLIO.md` を参照 (constitution.html §3 は cross-ref スタブ)。

## Entry points

| file | role |
|------|------|
| [`constitution.html`](./constitution.html) | 12 immutable principles (3-tier: Always 7 / Ask first 3 / Never 2), 2 mermaid 図 (v0.4.2 で 4 → 2 図、 §3 §4 cross-ref スタブ) |
| [`rules.html`](./rules.html) | Layer 1 consumer 向け universal rules (directory layout + HTML markup + delta marker + EARS + §10 Mandatory Actions with REQ-CM/CI-* IDs) |
| [`folio-self-spec.html`](./folio-self-spec.html) | folio Layer 0 framework 自身の architecture spec (2-Layer + harness + plugin integration + bindings, 8 mermaid 図、 provisional: Phase X3+ で self-application 予定) |
| [`decisions/ADR-0001-architecture-rules-split.html`](./decisions/ADR-0001-architecture-rules-split.html) | ADR-0001 (architecture-rules.html を 2 file に split した決定) |
| [`FOLIO.md`](./FOLIO.md) | project identity, 2-Layer diagram, Layer 1 consumer roster |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions (HOW binding, P-11 root exception) |
| [`common.css`](./common.css) | design tokens (inspired by [note via awesome-design-md-jp](https://github.com/kzhrknt/awesome-design-md-jp/blob/main/design-md/note/DESIGN.md): 18px / line-height 2.0 / palt headings / 940px main / dual-shadow elevation / dark mode) |
| [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) | plugin manifest (Claude Code plugin protocol、 v0.4.2-draft) |
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
  - <http://ipatho-server-2.taild4e917.ts.net:8000/rules.html>
  - <http://ipatho-server-2.taild4e917.ts.net:8000/folio-self-spec.html>
  - <http://ipatho-server-2.taild4e917.ts.net:8000/decisions/ADR-0001-architecture-rules-split.html>
- **IPv4 direct**: <http://100.127.217.108:8000/>
- (MagicDNS short form `http://ipatho-server-2:8000/` may fail to resolve on some devices; prefer the full form.)

(Reachable only from tailnet-joined devices.)

## Philosophy (one-paragraph)

A spec is the future-ideal anchor (design intent reference), not a mirror of current implementation. drift between spec and code is expected. The spec exists to prevent ad-hoc divergence — user or AI may lose sight of the original design intent over time, and the spec serves as the shared declarative reference both consult. See `constitution.html` §1 Purpose for the full statement.

## Distinction from twill

This is **not** the twill plugin (`~/projects/local-projects/twill/`). twill is a frozen historical artifact; folio extracts twill's universal-ready principles (declarative narrative, link integrity, caller marker idea, drift prevention) as a clean-slate framework and leaves twill-specific implementation behind. See constitution P-12 and folio-self-spec.html §7.4 for the 3-axis × 5-layer LLM-confusion-avoidance system.
