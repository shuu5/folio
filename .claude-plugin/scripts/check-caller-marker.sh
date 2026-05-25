#!/usr/bin/env bash
# .claude-plugin/scripts/check-caller-marker.sh
# PreToolUse hook: spec_path 配下への Edit/Write/NotebookEdit を caller marker でゲートする
# Phase X3 試作 (ADR-0003 §2.1 / rules.html §10.1 REQ-CM-001~003)
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input)
# stdout: 無音
# stderr: 失敗時に reason を出力
# exit: 0 = allow, 2 = deny (REQ-VER-006: exit code 中心 assertion)
#
# 環境変数 (userConfig から injection 想定、 試作中は default):
#   FOLIO_CALLER_MARKER_ENV   既定 "FOLIO_ARCHITECT_CONTEXT"
#   FOLIO_CALLER_MARKER_VALUE 既定 "folio-architect"
#   FOLIO_SPEC_PATH           既定 "architecture/spec/"
#   FOLIO_MARKER_FILE         既定 ".folio/architect-active" (hybrid marker file)
#
# marker は hybrid (env var OR file) で判定する (Stage 1):
#   - env var ($FOLIO_CALLER_MARKER_ENV == $FOLIO_CALLER_MARKER_VALUE): cld 起動時に
#     set する従来方式。 sandbox scenario はこちらを given.env で検証。
#   - marker file ($FOLIO_MARKER_FILE 存在): folio-architect SKILL が mid-session で
#     touch/rm する方式。 env は実行中の hook へ伝播しないため、 SKILL 経由の正規
#     spec 編集はこの file marker で allow する。
#   どちらか一方で allow、 両方無ければ deny (fail-closed)。
#
# 失敗時は fail-closed (jq 不在 / 不正変数名 / env・file 共に無し → deny)。
# 必須依存欠落で bypass されないこと優先 (R2-1 / R2-2 review 反映)。
#
# 共通ロジックは plugin-lib.sh に集約 (Phase 3 DRY refactor)。
# 注: 空 tool_name は下記 case *) で allow される (現行挙動)。 path-boundary /
#     jsonld-lint の fail-closed (空→deny) とは非一貫だが本 refactor では厳密保持。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

EXPECTED_VAR="${FOLIO_CALLER_MARKER_ENV:-FOLIO_ARCHITECT_CONTEXT}"
EXPECTED_VAL="${FOLIO_CALLER_MARKER_VALUE:-folio-architect}"
SPEC_PATH=$(folio_spec_path)

# 変数名 sanity check (alnum + _ のみ、 数字始まり禁止) — indirect expansion 防御 (R2-2)
if [[ ! "$EXPECTED_VAR" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "folio: invalid caller marker env var name: '${EXPECTED_VAR}'" >&2
  exit 2
fi

# stdin payload (空文字許容 = direct test invocation)
payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

# tool_name / file_path 抽出 (jq 必須、 fail-closed (R2-1))
folio_require_jq "spec edit gating"
tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')

# matcher 外の tool は通過 (hooks.json matcher で絞り込み済の想定だが念のため)
# ※ 空 tool_name もここで allow される (現行挙動を厳密保持)
case "$tool_name" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

# spec_path 配下でない file は通過
folio_under_spec_path "$file_path" "$SPEC_PATH" || exit 0

# caller marker 検証 (hybrid: env var OR marker file のどちらかで allow)
# (1) env var 方式 (cld 起動時 set、 sandbox scenario はこちら)
actual_val="${!EXPECTED_VAR:-}"
if [[ "$actual_val" == "$EXPECTED_VAL" ]]; then
  exit 0
fi

# (2) marker file 方式 (folio-architect SKILL が mid-session で touch、 env が実行中に
#     hook へ伝播しない制約への対処)。 file の存在のみで判定 (内容は問わない)。
marker_file="${FOLIO_MARKER_FILE:-.folio/architect-active}"
if [[ -f "$marker_file" ]]; then
  exit 0
fi

# deny (env・file 共に無し)
folio_deny \
  "folio caller marker check: edit of ${SPEC_PATH} requires ${EXPECTED_VAR}='${EXPECTED_VAL}' OR marker file '${marker_file}'" \
  "  current env value: '${actual_val:-(unset)}'" \
  "  marker file '${marker_file}': absent" \
  "  file: ${file_path}" \
  "  hint: invoke /folio-architect to set the marker (or set ${EXPECTED_VAR}=${EXPECTED_VAL})" \
  "  reference: architecture/spec/rules.html §10.1 (REQ-CM-001~003)"
