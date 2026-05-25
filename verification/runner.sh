#!/usr/bin/env bash
# verification/runner.sh
# Phase X3 試作 sandbox verification runner (bash + yq + jq、 Gap 2 採用)
#
# 用法: runner.sh [--accept] <scenario.yaml>
#   scenario YAML 1 件を読み、 scenario.kind に応じて 2 経路へ dispatch:
#     - kind: hook (既定、 省略可)  … 各 scenario を hook script に mock payload で実行、
#                                       exit_code + stderr_contains を assert (REQ-VER-001〜008)。
#     - kind: cli-golden            … bin/folio を command で repo root 実行 → output_file と
#                                       golden を jq -S + normalize.exclude_paths 削除で正規化 →
#                                       byte-exact 比較 + exit_code assert (REQ-VER-010/011)。
#                                       --accept で local→reference golden 更新 (REQ-VER-004)。
#
# kind: hook の scenario file 名 (basename without .yaml) と hook script 名の mapping:
#   scenarios/caller-marker.yaml → .claude-plugin/scripts/check-caller-marker.sh
#   scenarios/path-boundary.yaml → .claude-plugin/scripts/check-path-boundary.sh
#
# verification.html §3.2 schema 準拠の YAML を期待。
# Step 2 で `given.content` を payload に含めるよう拡張 (Write hook 対応)。
# Step 3 で kind: cli-golden を追加 (CLI subcommand 検証、 hook flow は不変)。

set -uo pipefail

# --- dependencies ---
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq (mikefarah/yq v4.x) not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found in PATH" >&2; exit 1; }

# --- args (--accept は kind: cli-golden 専用、 hook scenario では無視される) ---
ACCEPT=0
SCENARIO_FILE=""
for arg in "$@"; do
  case "$arg" in
    --accept) ACCEPT=1 ;;
    -*) echo "ERROR: unknown flag: $arg" >&2; exit 1 ;;
    *) SCENARIO_FILE="$arg" ;;
  esac
done
if [[ -z "$SCENARIO_FILE" ]]; then
  echo "Usage: $0 [--accept] <scenario.yaml>" >&2
  exit 1
fi
[[ -f "$SCENARIO_FILE" ]] || { echo "ERROR: scenario file not found: $SCENARIO_FILE" >&2; exit 1; }

# --- repo root + plugin root 推定 ---
SCRIPT_DIR=$(dirname "$(realpath "$0")")
REPO_ROOT=$(realpath "${SCRIPT_DIR}/..")
PLUGIN_ROOT="${REPO_ROOT}/.claude-plugin"

# ============================================================================
# kind: cli-golden handler (REQ-VER-010/011/012 + REQ-VER-004 2-dir + --accept)
#   capture (file|stdout) × compare (json|text) の 2 軸で 2 種の CLI 出力に対応
#   (verification.html §3.2):
#     - capture:file  (既定) … CLI が生成する output_file を読む  (例 inventory-gen)
#     - capture:stdout       … command の stdout を捕捉            (例 prime-digest)
#     - compare:json  (既定) … jq -S 正規化 + exclude_paths 削除後に byte-exact (inventory)
#     - compare:text         … 正規化なしの plain byte-exact diff          (prime digest)
#   共通 flow: actual を baselines/local/ へ materialize (2-dir model) → golden と比較。
#   --accept: local → reference golden を更新 (両 mode 共通、 §3.4 REQ-VER-004 accept workflow)。
# 出力 format は hook flow と揃える ("Results: N passed, M failed (total T)")。
# ============================================================================
run_cli_golden() {
  local scenario="$1"
  local req_id golden exp_exit capture compare output_file
  req_id=$(yq -r '.req_id // "(unknown)"' "$scenario")
  golden=$(yq -r '.golden' "$scenario")                    # SCRIPT_DIR (verification dir) 相対
  exp_exit=$(yq -r '.expect.exit_code // 0' "$scenario")
  capture=$(yq -r '.capture // "file"' "$scenario")        # file (既定) | stdout
  compare=$(yq -r '.compare // "json"' "$scenario")        # json (既定) | text
  output_file=$(yq -r '.output_file // ""' "$scenario")    # capture:file 専用 (repo root 相対)

  local -a cmd=()
  while IFS= read -r c; do [[ -n "$c" ]] && cmd+=("$c"); done < <(yq -r '.command[]' "$scenario")

  local golden_abs local_dir local_abs
  golden_abs="${SCRIPT_DIR}/${golden}"
  local_dir="${SCRIPT_DIR}/baselines/local"
  local_abs="${local_dir}/$(basename "$golden")"
  mkdir -p "$local_dir"

  echo "=== scenario: ${scenario}"
  echo "    req_id:  ${req_id}"
  echo "    kind:    cli-golden (capture:${capture}, compare:${compare})"
  echo "    command: folio ${cmd[*]}"
  echo ""

  # 1. CLI を repo root 実行 → actual を baselines/local/ へ materialize (REQ-VER-004 2-dir、 .gitignore 済)
  local actual_exit
  if [[ "$capture" == "stdout" ]]; then
    # stdout を捕捉 (stderr は端末へ素通し = auto-regen log 等の観察用)
    ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" ) > "$local_abs"
    actual_exit=$?
  else
    # capture:file — CLI が output_file を生成、 それを local へ複写
    local out_abs="${REPO_ROOT}/${output_file}"
    ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" )
    actual_exit=$?
    if [[ ! -f "$out_abs" ]]; then
      echo "  [FAIL] ${req_id}: output_file not produced: ${output_file}" >&2
      echo ""; echo "Results: 0 passed, 1 failed (total 1)"
      return 1
    fi
    cp "$out_abs" "$local_abs"
  fi

  # 2. --accept: local → reference golden (両 mode 共通、 §3.4 REQ-VER-004 accept workflow)
  if [[ "$ACCEPT" == "1" ]]; then
    mkdir -p "$(dirname "$golden_abs")"
    cp "$local_abs" "$golden_abs"
    echo "  [ACCEPT] golden refreshed from local: ${golden}"
    echo ""; echo "Results: accepted (1 golden updated)"
    return 0
  fi

  if [[ ! -f "$golden_abs" ]]; then
    echo "  [FAIL] ${req_id}: golden not found: ${golden} (run with --accept to create)" >&2
    echo ""; echo "Results: 0 passed, 1 failed (total 1)"
    return 1
  fi

  # 3. assert: exit_code 一致 + (compare mode 別) 出力一致
  local ok=true reasons=() diff_kind=""
  local norm_actual="" norm_golden=""
  if [[ "$actual_exit" != "$exp_exit" ]]; then
    ok=false; reasons+=("exit_code mismatch (expected=${exp_exit}, got=${actual_exit})")
  fi

  if [[ "$compare" == "text" ]]; then
    # plain byte-exact (正規化なし)
    if ! cmp -s "$local_abs" "$golden_abs"; then
      ok=false; reasons+=("output != golden (byte diff)"); diff_kind="text"
    fi
  else
    # compare:json — jq -S 正規化 + normalize.exclude_paths 削除後に byte-exact
    local norm_filter="." p
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      norm_filter="${norm_filter} | del(${p})"
    done < <(yq -r '.normalize.exclude_paths // [] | .[]' "$scenario")

    norm_actual=$(jq -S "$norm_filter" "$local_abs" 2>&1) || {
      echo "  [FAIL] ${req_id}: jq normalize failed (actual): ${norm_actual}" >&2
      echo ""; echo "Results: 0 passed, 1 failed (total 1)"; return 1; }
    norm_golden=$(jq -S "$norm_filter" "$golden_abs" 2>&1) || {
      echo "  [FAIL] ${req_id}: jq normalize failed (golden): ${norm_golden}" >&2
      echo ""; echo "Results: 0 passed, 1 failed (total 1)"; return 1; }
    if [[ "$norm_actual" != "$norm_golden" ]]; then
      ok=false; reasons+=("normalized output != golden (byte diff)"); diff_kind="json"
    fi
  fi

  if $ok; then
    echo "  [PASS] ${req_id} (output == golden, exit ${actual_exit})"
    echo ""; echo "Results: 1 passed, 0 failed (total 1)"
    return 0
  fi

  echo "  [FAIL] ${req_id}" >&2
  for r in "${reasons[@]}"; do echo "         - $r" >&2; done
  if [[ "$diff_kind" == "text" ]]; then
    echo "         --- diff (< golden | > actual) ---" >&2
    diff "$golden_abs" "$local_abs" >&2 || true
  elif [[ "$diff_kind" == "json" ]]; then
    echo "         --- diff (< golden | > actual、 正規化後) ---" >&2
    diff <(printf '%s\n' "$norm_golden") <(printf '%s\n' "$norm_actual") >&2 || true
  fi
  echo ""; echo "Results: 0 passed, 1 failed (total 1)"
  return 1
}

# --- kind dispatch: cli-golden のみ別経路、 省略時 (hook) は以降の既存 flow ---
KIND=$(yq -r '.kind // "hook"' "$SCENARIO_FILE")
if [[ "$KIND" == "cli-golden" ]]; then
  run_cli_golden "$SCENARIO_FILE"
  exit $?
fi

# --- (kind: hook) scenario file → hook script の mapping (試作: 単純 basename mapping) ---
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
  # hook は cwd=REPO_ROOT で起動する: 実機 Claude Code は project root を cwd とし file_path を
  # 絶対化するため、 hook が file_path から実 file (例 cluster README、 readme-index.yaml) を読む
  # 場合に runner 起動 cwd へ依存しないよう REPO_ROOT へ cd する。 cd は command substitution の
  # subshell 内なので runner 本体の cwd・上記 yq 読込・payload 構築には影響しない。 disk を読まない
  # 既存 hook (caller-marker / path-boundary / jsonld-lint) は cwd 非依存のため挙動不変。
  actual_stderr=$(cd "$REPO_ROOT" && env -i HOME="$HOME" PATH="$PATH" ${env_args[@]+"${env_args[@]}"} \
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
