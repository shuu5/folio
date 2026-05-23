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
#   - content に `name="folio-doc-type"` + `content="spec"` (or single quote 版) を
#     word boundary 付きで検出 (`spec-draft` 等の誤検出回避、 属性順両対応)
#   - file_path が spec_path 配下でない
#   → deny
#
# 環境変数:
#   FOLIO_SPEC_PATH  既定 "scratch/specs/"
#
# Phase 6 Step 2 review 反映:
#   - R2-H1 regex word boundary (closing quote で limit)
#   - R2-H2 tool_name 空時 fail-closed
#   - R2-M3 single quote 属性対応
#   - R1-M1 dead code (二重 fallback) 削除

set -uo pipefail

SPEC_PATH="${FOLIO_SPEC_PATH:-scratch/specs/}"
SPEC_PATH="${SPEC_PATH%/}/"

payload=$(cat 2>/dev/null || true)
[[ -z "$payload" ]] && exit 0

command -v jq >/dev/null 2>&1 || {
  echo "folio: jq not found in PATH (required for path boundary check, fail-closed)" >&2
  exit 2
}

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null)

# tool_name 空 = 不正 payload、 fail-closed (R2-H2)
if [[ -z "$tool_name" ]]; then
  echo "folio: tool_name missing from hook payload (fail-closed)" >&2
  exit 2
fi

# Write 以外通過 (Edit / NotebookEdit は既存 file 修正)
[[ "$tool_name" == "Write" ]] || exit 0

# .html 以外通過
case "$file_path" in
  *.html) ;;
  *) exit 0 ;;
esac

# folio-doc-type=spec を word boundary 付きで検出 (R2-H1 false positive 防止 + R2-M3 single quote)
# 文字クラス `["']` で name / content 両属性の double quote / single quote を同時許容。
# spec 値は閉じ quote で boundary (e.g. `content="spec-draft"` は match しない)。
if ! printf '%s' "$content" | grep -E -q "name=[\"']folio-doc-type[\"'][^>]*content=[\"']spec[\"']|content=[\"']spec[\"'][^>]*name=[\"']folio-doc-type[\"']"; then
  exit 0
fi

# spec_path 配下なら通過
case "$file_path" in
  "${SPEC_PATH}"*|*"/${SPEC_PATH}"*) exit 0 ;;
esac

{
  echo "folio path boundary check: spec files (folio-doc-type=spec) must be created under ${SPEC_PATH}"
  echo "  file: ${file_path}"
  echo "  reference: scratch/decisions/ADR-0003-plugin-architecture.html §2.1 path boundary"
} >&2
exit 2
