# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy.

**Status**: Phase X5-γ (選択的完成)。 現行 `v0.5.0-draft`、 v1.0 昇格基準は [ADR-0030](./architecture/decisions/ADR-0030-v1-stability-criteria.html) (proposed) で定義。 試作層 (`scratch/`) は X4-C (ADR-0023) で canonical layout (`architecture/` design-intent + repo-root `tests/` HOW-test) へ物理移植済 (HOW-test dir は X4-F/ADR-0026 で `verification/` → `tests/` に rename、 概念「verification」は spec 名・`folio validate` として存続)。 folio は自身の rules を self-host する。

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
| [`tests/`](./tests/) | sandbox verification framework (scenarios / fixtures / golden / runner.sh、 X4-F で verification/ から rename) |
| [`CLAUDE.md`](./CLAUDE.md) | Claude Code project instructions |
| [`.claude-plugin/`](./.claude-plugin/) + [`hooks/`](./hooks/) | plugin harness (manifest + CLI + hook 宣言 / script) |

## View

**Published spec site (canonical)**: <https://shuu5.github.io/folio/> — GitHub Pages, always available.

- [Architecture](https://shuu5.github.io/folio/architecture/) · [Constitution](https://shuu5.github.io/folio/architecture/spec/constitution.html) · [ADR index](https://shuu5.github.io/folio/architecture/decisions/README.html)

**Local preview** (offline / pre-publish): serve the repo root, then open `/architecture/`:

```bash
# repo root から (specs の ../../common.css 等を解決するため root 配信が必須)
python3 -m http.server 8000 --bind 127.0.0.1            # localhost のみ
# tailnet 経由で見る場合は tailscale IP を bind:
# python3 -m http.server 8000 --bind "$(tailscale ip -4)"
```

## Distinction from twill

**Not** the twill plugin (`~/projects/local-projects/twill/`、 frozen historical artifact). folio is a clean-slate framework.

## License

[MIT](./LICENSE) © 2026 shuu5. OSS — 誰でも自由に利用・改変・再配布できます。
