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

# jq parse 可能か (well-formed check)
if ! printf '%s' "$ldjson" | jq . >/dev/null 2>&1; then
  folio_deny \
    "folio JSON-LD lint: JSON-LD block parse failed (invalid JSON)" \
    "  file: ${file_path}" \
    "  reference: scratch/specs/relations.html §3.2"
fi

# 必須 key check (@context, @id, @type) — 個別チェックで missing list を構築
missing=""
for key in '@context' '@id' '@type'; do
  if ! printf '%s' "$ldjson" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
    missing="${missing:+$missing, }$key"
  fi
done
if [[ -n "$missing" ]]; then
  folio_deny \
    "folio JSON-LD lint: required keys missing" \
    "  file: ${file_path}" \
    "  missing: ${missing}" \
    "  reference: scratch/specs/relations.html §3.2 (required: @context, @id, @type)"
fi

# @context は object 形式 MUST (新 pattern、 旧 string 形式は deny)
ctx_type=$(printf '%s' "$ldjson" | jq -r '."@context" | type' 2>/dev/null)
if [[ "$ctx_type" != "object" ]]; then
  folio_deny \
    "folio JSON-LD lint: @context must be object (new pattern), got ${ctx_type}" \
    "  file: ${file_path}" \
    "  fix: change to object form, e.g. {\"dc\":\"http://purl.org/dc/terms/\", \"schema\":\"https://schema.org/\", \"folio\":\"https://folio.dev/spec/v1/\"}" \
    "  reference: scratch/specs/relations.html §3.2"
fi

exit 0
