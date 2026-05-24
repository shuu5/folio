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
#
# 共通ロジックは plugin-lib.sh に集約 (Phase 3 DRY refactor)。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

SPEC_PATH=$(folio_spec_path)

payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

folio_require_jq "path boundary check"

tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')
content=$(folio_json_field "$payload" '.tool_input.content // empty')

# tool_name 空 → fail-closed (R2-H2)、 Write 以外は対象外として通過
folio_require_write_tool "$tool_name"

# .html 以外通過
folio_is_html "$file_path" || exit 0

# folio-doc-type=spec を word boundary 付きで検出 (R2-H1 false positive 防止 + R2-M3 single quote)
# 文字クラス `["']` で name / content 両属性の double quote / single quote を同時許容。
# spec 値は閉じ quote で boundary (e.g. `content="spec-draft"` は match しない)。
if ! printf '%s' "$content" | grep -E -q "name=[\"']folio-doc-type[\"'][^>]*content=[\"']spec[\"']|content=[\"']spec[\"'][^>]*name=[\"']folio-doc-type[\"']"; then
  exit 0
fi

# spec_path 配下なら通過
folio_under_spec_path "$file_path" "$SPEC_PATH" && exit 0

folio_deny \
  "folio path boundary check: spec files (folio-doc-type=spec) must be created under ${SPEC_PATH}" \
  "  file: ${file_path}" \
  "  reference: scratch/decisions/ADR-0003-plugin-architecture.html §2.1 path boundary"
