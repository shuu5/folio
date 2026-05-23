#!/usr/bin/env bash
# .claude-plugin/scripts/check-path-boundary.sh
# PreToolUse hook: spec_path 配下以外で spec (folio-doc-type=spec) を作成しようと
# したら deny する。
# Phase X3 試作 (ADR-0003 §2.1 path boundary、 Option Pragmatic 採用)
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input.{file_path, content})
# stdout: 無音
# stderr: 失敗時に reason を出力
# exit: 0 = allow, 2 = deny
#
# 判定 (試作 minimum):
#   - Write tool のみ (Edit は既存 file 修正なので path boundary 不問)
#   - file_path が .html
#   - content に `<meta name="folio-doc-type" content="spec">` を含む
#   - file_path が spec_path 配下でない
#   → deny
#
# 環境変数:
#   FOLIO_SPEC_PATH  既定 "scratch/specs/"
#
# 試作 note: content の grep は単純 proximity match (typical HTML head での 1 行 meta タグ前提)。
# multi-line meta や属性順 reverse 等の edge case は試作 scope 外、 spec 化時に整理。

set -uo pipefail

SPEC_PATH_RAW="${FOLIO_SPEC_PATH:-scratch/specs/}"
[[ -z "$SPEC_PATH_RAW" ]] && SPEC_PATH_RAW="scratch/specs/"
SPEC_PATH="${SPEC_PATH_RAW%/}/"

# stdin payload (空文字許容 = direct test invocation)
payload=$(cat 2>/dev/null || true)
[[ -z "$payload" ]] && exit 0

# jq 必須、 fail-closed
command -v jq >/dev/null 2>&1 || {
  echo "folio: jq not found in PATH (required for path boundary check, fail-closed)" >&2
  exit 2
}

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null)

# Write 以外通過 (Edit / NotebookEdit は既存 file 修正)
[[ "$tool_name" == "Write" ]] || exit 0

# .html 以外通過
case "$file_path" in
  *.html) ;;
  *) exit 0 ;;
esac

# content に folio-doc-type=spec を含むか (両属性順序を許容)
if ! printf '%s' "$content" | grep -E -q 'name="folio-doc-type"[^>]*content="spec"|content="spec"[^>]*name="folio-doc-type"'; then
  # spec ではない (cluster-readme / adr / rules 等) → 通過
  exit 0
fi

# spec_path 配下なら通過
case "$file_path" in
  "${SPEC_PATH}"*|*"/${SPEC_PATH}"*) exit 0 ;;
esac

# spec_path 外で spec を作ろうとしている → deny
{
  echo "folio path boundary check: spec files (folio-doc-type=spec) must be created under ${SPEC_PATH}"
  echo "  file: ${file_path}"
  echo "  reference: scratch/decisions/ADR-0003-plugin-architecture.html §2.1 path boundary"
} >&2
exit 2
