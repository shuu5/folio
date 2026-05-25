#!/usr/bin/env bash
# .claude-plugin/scripts/check-jsonld-lint.sh
# PostToolUse hook: 新規作成 .html file の JSON-LD block が
# relations.html §3.2 pattern (object @context + @id + @type 必須) に準拠か check。
#
# Phase X3 試作 minimum (Option B Light、 ADR-0004 候補で trace 予定):
#   - jq + bash + sed の純粋 shell 実装
#   - 完成形は ajv (JSON Schema) + pyld (semantic + unmapped property) 2 層 (ADR-0004 候補)
#   - Write tool のみ対象 (Edit は file_path 再読み込みコスト、 完成形で対応)
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input.{file_path, content})
# stdout: 無音
# stderr: 失敗時に reason を出力
# exit: 0 = allow, 2 = violation (PostToolUse なので tool は実行済、 user 通知用)
#
# 失敗時は fail-closed (jq 不在 / tool_name 空 → exit 2)。
#
# 共通ロジックは plugin-lib.sh に集約 (Phase 3 DRY refactor)。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

folio_require_jq "JSON-LD lint"

tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')
content=$(folio_json_field "$payload" '.tool_input.content // empty')

# tool_name 空 → fail-closed、 Write 以外は対象外として通過
folio_require_write_tool "$tool_name"

# .html 以外通過
folio_is_html "$file_path" || exit 0

# JSON-LD block 抽出 (試作 minimum: 単一 block 前提、 複数 block は ADR-0004 完成形で対応)
# sed: 開始 tag 〜 終了 tag を含む全行を出力 → 開始 tag より前と終了 tag より後を削除
#   - R2-H2 fix: type 属性 single quote / double quote 両対応 ([\"'])
#   - R1-H1 fix: 開始 tag と data が同一行に書かれた場合も data を欠落させない
ldjson=$(printf '%s' "$content" | \
  sed -n "/<script[^>]*type=[\"']application\/ld+json[\"']/,/<\/script>/p" | \
  sed "s/.*<script[^>]*type=[\"']application\/ld+json[\"'][^>]*>//; s/<\/script>.*//")

# JSON-LD block 不在 → spec / ADR / cluster-readme ではない可能性、 通過
if [[ -z "$ldjson" ]]; then
  exit 0
fi

# 構造 check は plugin-lib.sh の共有関数に委譲 (ADR-0020 §2.4 DRY、 bin/folio validate と共用)。
# folio_jsonld_structural_check は parse → 必須 key (@context/@id/@type) → @context==object を
# short-circuit で判定し、 clean なら return 0 (無出力)、 違反なら reason を stdout + return 1。
# 旧 inline 3 段 check の deny 文言 (parse failed / required keys missing / @context must be object)
# は reason に内包され、 sandbox jsonld-lint scenario の stderr_contains assertion を保持する。
if ! reason=$(folio_jsonld_structural_check "$ldjson"); then
  folio_deny \
    "folio JSON-LD lint: ${reason}" \
    "  file: ${file_path}" \
    "  reference: scratch/specs/relations.html §3.2 (required @context/@id/@type, @context object)"
fi

exit 0
