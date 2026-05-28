#!/usr/bin/env bash
# .claude-plugin/scripts/inject-inventory.sh
# folio Phase X3 試作 plugin — SessionStart context injection hook (ADR-0007 §2.1〜2.3)。
#
# folio prime の stdout (Tier 1 inventory digest) を agent context へ注入する薄い wrapper
# (Beads `bd prime` pattern、 plugin-architecture-research §5.2)。 SessionStart hook は exit 0 の
# stdout がそのまま agent context に注入される (Claude Code 公式仕様 = verified) ため、 wrapper は
# digest を stdout に流すだけでよい。 digest 生成・staleness auto-regen の実体は bin/folio prime 側
# (HOW は CLI に集約、 hook は注入経路のみ。 P-11)。
#
# ※ folio prime は cwd=project root を前提に repo-root inventory.json を読む (不在/stale 時 auto-regen)。
#   Claude Code hook は project root を cwd として起動するため追加の cd は不要。
# ※ SessionStart は matcher 省略で startup/resume/clear/compact 全 source 発火 (compact source が
#   post-compaction 再注入を担う)。 SessionStart:startup 注入は e2e PASS (REQ-VER-009、 §3.6)。
#   PreCompact hook は stdout 非注入のため ADR-0007 amend (2026-05-25) で除去済 (旧設計)。

set -uo pipefail

# bin/folio を本 script から相対解決 (scripts/ と bin/ は .claude-plugin/ 直下の sibling)。
# ${CLAUDE_PLUGIN_ROOT} 環境変数に依存せず self-locate するため hook 起動環境差に頑健。
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FOLIO="${SCRIPT_DIR}/../bin/folio"

[[ -x "$FOLIO" ]] || { echo "inject-inventory: folio CLI not found/executable at ${FOLIO}" >&2; exit 1; }

# architecture/ が無い cwd (folio install 直後 / folio init 前 / folio 非対応 project) では
# prime は scan root not found で error。 SessionStart hook 経路は consumer onboarding の noise
# を避けるため silent skip (exit 0、 stdout 空) で振る舞う (#93)。 prime の error は CLI を
# 直接実行した場合のみ surface する (CLI 利用者には明示的 fail-closed のままが正しい)。
[[ -d architecture ]] || exit 0

# stdout = digest (= 注入される context)、 exit code は folio prime に委譲。
exec "$FOLIO" prime
