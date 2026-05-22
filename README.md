# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy.

**Status**: 試作段階 (Phase X2)。 すべての試作・調査・要望整理は [`scratch/`](./scratch/) で行う。 完成後 (Phase X3) に正式 location (`architecture/`) に移植予定。

## 2-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)            : rules + plugin harness 一体配布
                ↓ provides rules + harness (via folio.config.yaml)
Layer 1 — <consumer-project>/          : architecture/ spec + implementation in same repo
```

## Entry points

| file / dir | role |
|---|---|
| [`scratch/constitution.html`](./scratch/constitution.html) | folio の 12 不変原則 (編集禁止) |
| [`scratch/`](./scratch/) | 試作・調査・実装試行の作業場所 |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions |
| [`.claude-plugin/`](./.claude-plugin/) | plugin harness placeholder (試作段階、 触らない) |

## Local preview (tailnet)

`python3 -m http.server 8000` is served on `ipatho-server-2`:

- <http://ipatho-server-2.taild4e917.ts.net:8000/scratch/constitution.html>
- <http://ipatho-server-2.taild4e917.ts.net:8000/scratch/>

(Reachable only from tailnet-joined devices.)

## Distinction from twill

**Not** the twill plugin (`~/projects/local-projects/twill/`、 frozen historical artifact). folio is a clean-slate framework.
