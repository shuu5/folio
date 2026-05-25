# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy.

**Status**: Phase X4。 試作層 (`scratch/`) は X4-C (ADR-0023) で canonical layout (`architecture/` design-intent + repo-root `verification/` HOW-test) へ物理移植済。 folio は自身の rules を self-host する。

## 2-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)            : rules + plugin harness 一体配布
                ↓ provides rules + harness (via folio.config.yaml)
Layer 1 — <consumer-project>/          : architecture/ spec + implementation in same repo
```

## Entry points

| file / dir | role |
|---|---|
| [`architecture/spec/constitution.html`](./architecture/spec/constitution.html) | folio の 13 不変原則 (編集禁止) |
| [`architecture/`](./architecture/) | design-intent 空間 (spec / decisions / research / assets、 self-host) |
| [`verification/`](./verification/) | sandbox verification framework (scenarios / fixtures / golden / runner.sh) |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions |
| [`.claude-plugin/`](./.claude-plugin/) + [`hooks/`](./hooks/) | plugin harness (manifest + CLI + hook 宣言 / script) |

## Local preview (tailnet)

`python3 -m http.server 8000` is served on `ipatho-server-2`:

- <http://ipatho-server-2.taild4e917.ts.net:8000/architecture/spec/constitution.html>
- <http://ipatho-server-2.taild4e917.ts.net:8000/architecture/>

(Reachable only from tailnet-joined devices.)

## Distinction from twill

**Not** the twill plugin (`~/projects/local-projects/twill/`、 frozen historical artifact). folio is a clean-slate framework.
