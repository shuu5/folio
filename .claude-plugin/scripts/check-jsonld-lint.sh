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

set -uo pipefail

payload=$(cat 2>/dev/null || true)
[[ -z "$payload" ]] && exit 0

command -v jq >/dev/null 2>&1 || {
  echo "folio: jq not found in PATH (required for JSON-LD lint, fail-closed)" >&2
  exit 2
}

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
content=$(printf '%s' "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null)

# tool_name 空 = 不正 payload、 fail-closed
if [[ -z "$tool_name" ]]; then
  echo "folio: tool_name missing from hook payload (fail-closed)" >&2
  exit 2
fi

# Write 以外通過 (試作 minimum: Edit / NotebookEdit は scope 外、 完成形で対応)
[[ "$tool_name" == "Write" ]] || exit 0

# .html 以外通過
case "$file_path" in
  *.html) ;;
  *) exit 0 ;;
esac

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
  {
    echo "folio JSON-LD lint: JSON-LD block parse failed (invalid JSON)"
    echo "  file: ${file_path}"
    echo "  reference: scratch/specs/relations.html §3.2"
  } >&2
  exit 2
fi

# 必須 key check (@context, @id, @type) — 個別チェックで missing list を構築
missing=""
for key in '@context' '@id' '@type'; do
  if ! printf '%s' "$ldjson" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
    missing="${missing:+$missing, }$key"
  fi
done
if [[ -n "$missing" ]]; then
  {
    echo "folio JSON-LD lint: required keys missing"
    echo "  file: ${file_path}"
    echo "  missing: ${missing}"
    echo "  reference: scratch/specs/relations.html §3.2 (required: @context, @id, @type)"
  } >&2
  exit 2
fi

# @context は object 形式 MUST (新 pattern、 旧 string 形式は deny)
ctx_type=$(printf '%s' "$ldjson" | jq -r '."@context" | type' 2>/dev/null)
if [[ "$ctx_type" != "object" ]]; then
  {
    echo "folio JSON-LD lint: @context must be object (new pattern), got ${ctx_type}"
    echo "  file: ${file_path}"
    echo "  fix: change to object form, e.g. {\"dc\":\"http://purl.org/dc/terms/\", \"schema\":\"https://schema.org/\", \"folio\":\"https://folio.dev/spec/v1/\"}"
    echo "  reference: scratch/specs/relations.html §3.2"
  } >&2
  exit 2
fi

exit 0
