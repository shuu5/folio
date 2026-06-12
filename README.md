# folio

A clean-slate, AI-Agent-first **architecture spec-writing framework + Claude Code plugin harness** (META FRAMEWORK, Layer 0). HTML-only, future-anchor philosophy.

**Status**: Phase X5-γ (選択的完成)。 現行 `v1.0.0`、 v1.0 昇格基準は [ADR-0030](./architecture/decisions/ADR-0030-v1-stability-criteria.html) (accepted) で定義。 試作層 (`scratch/`) は X4-C (ADR-0023) で canonical layout (`architecture/` design-intent + repo-root `tests/` HOW-test) へ物理移植済 (HOW-test dir は X4-F/ADR-0026 で `verification/` → `tests/` に rename、 概念「verification」は spec 名・`folio validate` として存続)。 folio は自身の rules を self-host する。

## Install

**Prerequisites**: `bash` + `jq` + `yq` ([mikefarah v4.x](https://github.com/mikefarah/yq)) + GNU `realpath` (Linux 標準)。 **Supported**: **Linux canonical** (sandbox + CI 共に ubuntu-latest で検証)。 macOS / Windows は post-1.0 で fix 予定の best-effort 状態。

Claude Code 内で:

```
/plugin marketplace add shuu5/folio
/plugin install folio@folio
```

reload 後、`~/.claude/plugins/folio/` に install され、 `/folio-architect` SKILL と canonical CLI path (`~/.claude/plugins/folio/.claude-plugin/bin/folio`) が available になります。

**First run** — greenfield consumer project:

```
mkdir my-project && cd my-project
# Claude Code を起動して:
/folio-architect この project に folio を導入し、 最初の design-intent spec を整備せよ
```

adoption-aware Phase A が greenfield 検出 → `folio init` で構造生成 → onboarding grill (1 問ずつ + 推奨回答) で実体を引き出し → Phase E で非 hollow な constitution / overview を materialize → Phase F で 4-agent quality review ([ADR-0031](./architecture/decisions/ADR-0031-mattpocock-authoring-absorption.html) protocol-only authoring 吸収)。

## 2-Layer Architecture (at a glance)

```
Layer 0 — folio (this repo)            : rules + plugin harness 一体配布
                ↓ provides rules + harness (via folio.config.yaml)
Layer 1 — <consumer-project>/          : architecture/ spec + implementation in same repo
```

## Entry points

| file / dir | role |
|---|---|
| [`architecture/spec/constitution.html`](./architecture/spec/constitution.html) | folio の 14 不変原則 (編集禁止) |
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
