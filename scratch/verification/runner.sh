#!/usr/bin/env bash
# scratch/verification/runner.sh
# Phase X3 試作 sandbox verification runner (bash + yq + jq、 Gap 2 採用)
#
# 用法: runner.sh <scenario.yaml>
#   scenario YAML 1 件を読み、 各 scenario を hook script に対し実行、
#   exit_code + stderr_contains を assert、 PASS/FAIL カウントを表示。
#
# scenario file 名 (basename without .yaml) と hook script 名は次の規約で mapping:
#   scenarios/caller-marker.yaml → .claude-plugin/scripts/check-caller-marker.sh
#   scenarios/path-boundary.yaml → .claude-plugin/scripts/check-path-boundary.sh
#
# verification.html §3.2 schema 準拠の YAML を期待。
# Step 2 で `given.content` を payload に含めるよう拡張 (Write hook 対応)。
# Step 3 以降 multi-scenario / multi-hook 対応は本 runner を拡張予定。

set -uo pipefail

# --- dependencies ---
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq (mikefarah/yq v4.x) not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found in PATH" >&2; exit 1; }

# --- args ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <scenario.yaml>" >&2
  exit 1
fi
SCENARIO_FILE="$1"
[[ -f "$SCENARIO_FILE" ]] || { echo "ERROR: scenario file not found: $SCENARIO_FILE" >&2; exit 1; }

# --- repo root + plugin root 推定 ---
SCRIPT_DIR=$(dirname "$(realpath "$0")")
REPO_ROOT=$(realpath "${SCRIPT_DIR}/../..")
PLUGIN_ROOT="${REPO_ROOT}/.claude-plugin"

# --- scenario file → hook script の mapping (試作: 単純 basename mapping) ---
SCENARIO_BASENAME=$(basename "$SCENARIO_FILE" .yaml)
HOOK_SCRIPT="${PLUGIN_ROOT}/scripts/check-${SCENARIO_BASENAME}.sh"
[[ -x "$HOOK_SCRIPT" ]] || { echo "ERROR: hook script not found or not executable: $HOOK_SCRIPT" >&2; exit 1; }

# --- metadata 表示 ---
REQ_ID=$(yq -r '.req_id // "(unknown)"' "$SCENARIO_FILE")
echo "=== scenario: ${SCENARIO_FILE}"
echo "    req_id:  ${REQ_ID}"
echo "    hook:    ${HOOK_SCRIPT}"
echo ""

# --- 各 scenario を実行 ---
PASS=0
FAIL=0
COUNT=$(yq -r '.scenarios | length' "$SCENARIO_FILE")

for i in $(seq 0 $((COUNT - 1))); do
  name=$(yq -r ".scenarios[$i].name" "$SCENARIO_FILE")
  tool=$(yq -r ".scenarios[$i].when.tool" "$SCENARIO_FILE")
  file_path=$(yq -r ".scenarios[$i].given.file_path // \"\"" "$SCENARIO_FILE")
  scenario_content=$(yq -r ".scenarios[$i].given.content // \"\"" "$SCENARIO_FILE")
  exp_exit=$(yq -r ".scenarios[$i].expect.exit_code" "$SCENARIO_FILE")
  exp_stderr=$(yq -r ".scenarios[$i].expect.stderr_contains // \"\"" "$SCENARIO_FILE")

  # given.env を JSON で取得 (空 dict なら "{}")
  env_keys_json=$(yq -o=json ".scenarios[$i].given.env // {}" "$SCENARIO_FILE")

  # mock hook JSON payload (tool_name + tool_input.{file_path, content})
  payload=$(jq -n --arg tool "$tool" --arg fp "$file_path" --arg ct "$scenario_content" \
    '{tool_name: $tool, tool_input: {file_path: $fp, content: $ct}}')

  # env 構築: scenario 指定 env + HOME/PATH 継承の clean 環境
  env_args=()
  if [[ "$env_keys_json" != "{}" ]]; then
    while IFS=$'\t' read -r k v; do
      [[ -z "$k" ]] && continue
      env_args+=("${k}=${v}")
    done < <(printf '%s' "$env_keys_json" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
  fi

  # 実行 (set -e 未使用、 exit code は $? で補足、 redirect は left-to-right で
  # `2>&1 >/dev/null` は「stderr → 元 stdout、 stdout → /dev/null」 の意 (R2-3 検証済))
  actual_stderr=$(env -i HOME="$HOME" PATH="$PATH" ${env_args[@]+"${env_args[@]}"} \
    "$HOOK_SCRIPT" <<<"$payload" 2>&1 >/dev/null)
  actual_exit=$?

  # assertion
  ok=true
  reasons=()
  if [[ "$actual_exit" != "$exp_exit" ]]; then
    ok=false
    reasons+=("exit_code mismatch (expected=${exp_exit}, got=${actual_exit})")
  fi
  if [[ -n "$exp_stderr" ]] && [[ "$actual_stderr" != *"${exp_stderr}"* ]]; then
    ok=false
    reasons+=("stderr does not contain '${exp_stderr}'")
  fi

  if $ok; then
    echo "  [PASS] $name"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $name" >&2
    for r in "${reasons[@]}"; do
      echo "         - $r" >&2
    done
    [[ -n "$actual_stderr" ]] && echo "         actual_stderr: ${actual_stderr}" >&2
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed (total ${COUNT})"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
