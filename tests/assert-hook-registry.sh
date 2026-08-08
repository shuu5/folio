#!/usr/bin/env bash
# tests/assert-hook-registry.sh
# hooks/hooks.json の **登録** assert (folio-v6tv / folio-qojv 決定 7 (ii))。
#
# sandbox runner (tests/runner.sh) は scenario basename → hook script を直接叩くため、 script が
# hooks.json に **登録されているか** を一切見ない (script は緑なのに hook が発火しない = 登録漏れの
# vacuous-green が構造的に可能)。 本 assert はその穴だけを塞ぐ純静的検査であり、 runner の kind /
# payload schema には触れない (verification contract 改訂 → 生成 canonical → drift gate の連鎖を引かない)。
#
# 検査 (fence ■6-2):
#   (1) hooks/hooks.json が jq で parse 可能
#   (2) 全 hook entry の command の ${CLAUDE_PLUGIN_ROOT} を repo root へ置換した path が実在かつ実行可能
#       (既存 hook entry も対象に含める)
#   (3) constitution guard が PreToolUse かつ matcher に Edit / Write / NotebookEdit を **全て** 含む
#       entry として、 ちょうど 1 つ宣言されている
#
# exit: 0 = 全 assert 緑 / 1 = 1 件以上の違反 (fail-closed: 依存欠落・parse 不能も 1)
# 用法: bash tests/assert-hook-registry.sh   (cwd 非依存)

set -uo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
REPO_ROOT=$(realpath "${SCRIPT_DIR}/..")
HOOKS_JSON="${REPO_ROOT}/hooks/hooks.json"

# 検査対象の新 gate (script basename) と、 その entry が満たすべき matcher tool 集合
GUARD_SCRIPT="check-constitution-guard.sh"
GUARD_EVENT="PreToolUse"
GUARD_TOOLS=(Edit Write NotebookEdit)

fail=0
note_fail() { echo "  [FAIL] $*" >&2; fail=1; }
note_pass() { echo "  [PASS] $*"; }

echo "=== assert-hook-registry: ${HOOKS_JSON#"${REPO_ROOT}/"}"
echo ""

command -v jq >/dev/null 2>&1 || { echo "  [FAIL] jq not found in PATH (fail-closed)" >&2; exit 1; }
[[ -f "$HOOKS_JSON" ]] || { echo "  [FAIL] hooks.json not found: ${HOOKS_JSON}" >&2; exit 1; }

# --- (1) JSON parse -----------------------------------------------------------
if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
  note_pass "(1) hooks.json は valid JSON"
else
  note_fail "(1) hooks.json が jq で parse できない"
  exit 1
fi

# --- (2) 全 hook entry の command が実在 + 実行可能 -----------------------------
# 出力形式: <event>\t<matcher>\t<type>\t<command>
entries=$(jq -r '
  .hooks // {} | to_entries[] as $ev
  | $ev.value[]? as $group
  | ($group.hooks // [])[] as $h
  | [ $ev.key, ($group.matcher // "(none)"), ($h.type // ""), ($h.command // "") ]
  | @tsv
' "$HOOKS_JSON" 2>/dev/null)

if [[ -z "$entries" ]]; then
  note_fail "(2) hook entry が 1 件も抽出できない (schema 崩れ or 空)"
else
  n=0
  while IFS=$'\t' read -r ev matcher htype cmd; do
    [[ -z "$ev" ]] && continue
    n=$((n + 1))
    if [[ "$htype" != "command" ]]; then
      note_fail "(2) ${ev} / ${matcher}: hook type が command でない ('${htype}')"
      continue
    fi
    if [[ -z "$cmd" ]]; then
      note_fail "(2) ${ev} / ${matcher}: command が空"
      continue
    fi
    resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/${REPO_ROOT}}"
    if [[ "$resolved" == *'${CLAUDE_PLUGIN_ROOT}'* || "$resolved" == *'$CLAUDE_PLUGIN_ROOT'* ]]; then
      note_fail "(2) ${ev} / ${matcher}: CLAUDE_PLUGIN_ROOT を解決できない command: ${cmd}"
      continue
    fi
    if [[ ! -f "$resolved" ]]; then
      note_fail "(2) ${ev} / ${matcher}: command の実体が不在: ${cmd}"
      continue
    fi
    if [[ ! -x "$resolved" ]]; then
      note_fail "(2) ${ev} / ${matcher}: command が実行可能でない (mode): ${cmd}"
      continue
    fi
  done <<< "$entries"
  [[ "$fail" -eq 0 ]] && note_pass "(2) 全 ${n} hook entry の command が実在 + 実行可能"
fi

# --- (3) constitution guard の登録 (event + matcher の tool 集合) ---------------
guard_matchers=$(jq -r --arg s "$GUARD_SCRIPT" --arg ev "$GUARD_EVENT" '
  .hooks // {} | to_entries[] | select(.key == $ev)
  | .value[]? | select( [ (.hooks // [])[] | .command // "" | endswith($s) ] | any )
  | .matcher // ""
' "$HOOKS_JSON" 2>/dev/null)

guard_count=0
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  guard_count=$((guard_count + 1))
  # matcher は "Edit|Write|NotebookEdit" 形。 alternative へ分解して集合として検査する
  # (部分文字列一致に頼ると "NotebookEdit" が "Edit" を含意して誤 PASS するため厳密分解)。
  IFS='|' read -ra alts <<< "$m"
  for want in "${GUARD_TOOLS[@]}"; do
    found=0
    for a in "${alts[@]}"; do
      a="${a//[[:space:]]/}"
      [[ "$a" == "$want" ]] && found=1
    done
    [[ "$found" -eq 1 ]] || note_fail "(3) ${GUARD_SCRIPT} の matcher '${m}' に '${want}' が含まれない"
  done
done <<< "$guard_matchers"

if [[ "$guard_count" -eq 0 ]]; then
  note_fail "(3) ${GUARD_SCRIPT} が ${GUARD_EVENT} entry として登録されていない (script は在っても hook が発火しない)"
elif [[ "$guard_count" -gt 1 ]]; then
  note_fail "(3) ${GUARD_SCRIPT} の ${GUARD_EVENT} entry が ${guard_count} 件 (1 件であること)"
else
  [[ "$fail" -eq 0 ]] && note_pass "(3) ${GUARD_SCRIPT} は ${GUARD_EVENT} / matcher に Edit・Write・NotebookEdit を全て含む entry として 1 件登録"
fi

echo ""
if [[ "$fail" -eq 0 ]]; then
  echo "Results: hook registry assertions GREEN"
  exit 0
fi
echo "Results: hook registry assertions FAILED" >&2
exit 1
