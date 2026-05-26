#!/usr/bin/env bash
# tests/runner.sh
# Phase X3 試作 sandbox verification runner (bash + yq + jq、 Gap 2 採用)
#
# 用法: runner.sh [--accept] <scenario.yaml>
#   scenario YAML 1 件を読み、 scenario.kind に応じて 3 経路へ dispatch:
#     - kind: hook (既定、 省略可)  … 各 scenario を hook script に mock payload で実行、
#                                       exit_code + stderr_contains を assert (REQ-VER-001〜008)。
#     - kind: cli-golden            … bin/folio を command で repo root 実行 → output_file と
#                                       golden を jq -S + normalize.exclude_paths 削除で正規化 →
#                                       byte-exact 比較 + exit_code assert (REQ-VER-010/011)。
#                                       --accept で local→reference golden 更新 (REQ-VER-004)。
#     - kind: cli-scaffold          … `folio init <tmp>` を fresh temp root に実行 →
#                                       (a) exit_code (b) 生成 file 集合 + folio.config.yaml の
#                                       golden 比較 (c) `folio validate --root` clean (d) idempotency
#                                       を assert (REQ-VER-014、 init = tree 生成のため単一 output の
#                                       cli-golden と別経路)。 --accept で golden 更新。
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

# ============================================================================
# kind: cli-scaffold handler (REQ-VER-014 + ADR-0024)
#   init は tree (複数 file) を temp dir に生成するため、 単一 output 前提の cli-golden では
#   不足。 verification.html REQ-VER-014 が委譲する 「既存 cli-golden harness の拡張、 HOW は
#   実装時確定」 の HOW として別 kind を新設する。 §3.2 schema と整合: schema_version / req_id /
#   kind / command / golden / expect.exit_code を踏襲し、 scaffold 固有の validate_root を足す。
#   既存 hook / cli-golden 経路は kind 分岐で隔離され不変 (既存 8 scenario に影響なし)。
#
#   flow: fresh temp root に `folio init <tmp>` → 4 assertion:
#     (a) init exit_code == expect.exit_code
#     (b) 生成 file 集合 (find -printf '%P' 相対 sort) + folio.config.yaml content == golden (byte-exact)
#     (c) `folio validate --root <tmp>/<validate_root>` clean (exit 0)
#     (d) idempotency: 再 init で全 file content 不変 (preserve、 上書きなし)
#   golden / report に temp path は焼かない (%P で root prefix 除去 → 非決定値を排除)。
#   --accept: local → reference golden 更新 (§3.4 REQ-VER-004、 cli-golden と共通方針)。
#   temp dir は SCAFFOLD_TMP (global) に置き dispatcher が後始末する (早期 return 多数のため)。
# ============================================================================
run_cli_scaffold() {
  local scenario="$1"
  local req_id golden exp_exit validate_root
  req_id=$(yq -r '.req_id // "(unknown)"' "$scenario")
  golden=$(yq -r '.golden' "$scenario")                    # SCRIPT_DIR (verification dir) 相対
  exp_exit=$(yq -r '.expect.exit_code // 0' "$scenario")
  validate_root=$(yq -r '.validate_root // "architecture"' "$scenario")   # 生成 tree 内の validate root

  local -a cmd=()
  while IFS= read -r c; do [[ -n "$c" ]] && cmd+=("$c"); done < <(yq -r '.command[]' "$scenario")

  local golden_abs local_dir local_abs
  golden_abs="${SCRIPT_DIR}/${golden}"
  local_dir="${SCRIPT_DIR}/baselines/local"
  local_abs="${local_dir}/$(basename "$golden")"
  mkdir -p "$local_dir"

  echo "=== scenario: ${scenario}"
  echo "    req_id:  ${req_id}"
  echo "    kind:    cli-scaffold"
  echo "    command: folio ${cmd[*]} <tmp>"
  echo ""

  # fresh temp root (dispatcher が後で rm -rf。 golden は %P 相対のみ → temp path 非依存)
  SCAFFOLD_TMP=$(mktemp -d) || { echo "  [FAIL] ${req_id}: mktemp failed" >&2; echo ""; echo "Results: 0 passed, 1 failed (total 1)"; return 1; }
  local tmp="$SCAFFOLD_TMP"

  # 1. init を temp root に実行 (cwd=REPO_ROOT、 他 CLI subcommand と同条件)
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" "$tmp" ) >/dev/null
  local init_exit=$?

  # 2. 決定的 manifest = 生成 file 集合 (%P 相対 sort) + folio.config.yaml content → local へ materialize
  {
    find "$tmp" -mindepth 1 -type f -printf '%P\n' | LC_ALL=C sort
    echo "--- folio.config.yaml ---"
    cat "${tmp}/folio.config.yaml" 2>/dev/null
  } > "$local_abs"

  # --accept: local → reference golden (§3.4 REQ-VER-004 accept workflow)
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

  # 3. assertions (a)〜(d)
  local ok=true reasons=()
  if [[ "$init_exit" != "$exp_exit" ]]; then
    ok=false; reasons+=("init exit_code mismatch (expected=${exp_exit}, got=${init_exit})")
  fi
  if ! cmp -s "$local_abs" "$golden_abs"; then
    ok=false; reasons+=("scaffold manifest (file 集合 + config) != golden (byte diff)")
  fi
  local vexit
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" validate --root "${tmp}/${validate_root}" ) >/dev/null
  vexit=$?
  if [[ "$vexit" != "0" ]]; then
    ok=false; reasons+=("folio validate on scaffold not clean (exit ${vexit})")
  fi
  # idempotency: 再 init 前後で全 file の sha256 が不変 = preserve (上書きなし) を実証
  local snap1 snap2 reinit_exit
  snap1=$( cd "$tmp" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" "$tmp" ) >/dev/null
  reinit_exit=$?
  snap2=$( cd "$tmp" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )
  if [[ "$reinit_exit" != "0" ]]; then
    ok=false; reasons+=("re-init exit_code != 0 (got=${reinit_exit})")
  fi
  if [[ "$snap1" != "$snap2" ]]; then
    ok=false; reasons+=("re-init mutated existing files (idempotency violated)")
  fi

  if $ok; then
    echo "  [PASS] ${req_id} (scaffold == golden, validate clean, idempotent)"
    echo ""; echo "Results: 1 passed, 0 failed (total 1)"
    return 0
  fi

  echo "  [FAIL] ${req_id}" >&2
  for r in "${reasons[@]}"; do echo "         - $r" >&2; done
  echo "         --- manifest diff (< golden | > actual) ---" >&2
  diff "$golden_abs" "$local_abs" >&2 || true
  echo ""; echo "Results: 0 passed, 1 failed (total 1)"
  return 1
}

# ============================================================================
# kind: cli-fix handler (REQ-VER-015 + ADR-0025)
#   fix は spec graph を mutate するため temp copy で検証する (cli-golden の単一 output や
#   cli-scaffold の tree 生成と別経路)。 fixture tree を temp へ copy し RED→GREEN を実証:
#     (a) pre-fix  `folio validate --root <tmp>` が broken-reverse で FAIL (exit≠0) = 修正対象あり
#     (b) `folio fix --root <tmp>` が exit == expect.exit_code (0)
#     (c) post-fix `folio validate --root <tmp>` clean (exit 0) = reverse materialize 成功
#     (d) idempotency: 再 fix で exit 0 かつ tree の sha256 不変 (no-op)
#   golden 不要 (behavioral assertion = RED→GREEN + idempotent、 HTML 整形の byte-golden は脆く
#   post-fix validate clean が materialize 正当性の proxy)。 既存 hook / cli-golden / cli-scaffold
#   経路は kind 分岐で隔離され不変。 temp dir は FIX_TMP (global) に置き dispatcher が後始末する。
# ============================================================================
run_cli_fix() {
  local scenario="$1"
  local req_id fixture exp_exit
  req_id=$(yq -r '.req_id // "(unknown)"' "$scenario")
  fixture=$(yq -r '.fixture' "$scenario")                  # SCRIPT_DIR (verification dir) 相対の fixture tree
  exp_exit=$(yq -r '.expect.exit_code // 0' "$scenario")

  local -a cmd=()
  while IFS= read -r c; do [[ -n "$c" ]] && cmd+=("$c"); done < <(yq -r '.command[]' "$scenario")

  echo "=== scenario: ${scenario}"
  echo "    req_id:  ${req_id}"
  echo "    kind:    cli-fix"
  echo "    command: folio ${cmd[*]} --root <tmp>"
  echo ""

  local fixture_abs="${SCRIPT_DIR}/${fixture}"
  if [[ ! -d "$fixture_abs" ]]; then
    echo "  [FAIL] ${req_id}: fixture tree not found: ${fixture}" >&2
    echo ""; echo "Results: 0 passed, 1 failed (total 1)"; return 1
  fi

  FIX_TMP=$(mktemp -d) || { echo "  [FAIL] ${req_id}: mktemp failed" >&2; echo ""; echo "Results: 0 passed, 1 failed (total 1)"; return 1; }
  cp -r "${fixture_abs}/." "$FIX_TMP/"
  local tmp="$FIX_TMP"

  local ok=true reasons=()

  # (a) pre-fix validate = RED (broken-reverse 等で exit≠0、 fixture が修正対象を seed している前提)
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" validate --root "$tmp" ) >/dev/null 2>&1
  local pre_exit=$?
  if [[ "$pre_exit" -eq 0 ]]; then
    ok=false; reasons+=("pre-fix validate already clean (fixture should seed a broken-reverse = RED state)")
  fi

  # (b) fix = exit expect (0)
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" --root "$tmp" ) >/dev/null
  local fix_exit=$?
  if [[ "$fix_exit" != "$exp_exit" ]]; then
    ok=false; reasons+=("fix exit_code mismatch (expected=${exp_exit}, got=${fix_exit})")
  fi

  # (c) post-fix validate = GREEN (3-gate clean、 exit 0 = reverse materialize 成功)
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" validate --root "$tmp" ) >/dev/null
  local post_exit=$?
  if [[ "$post_exit" != "0" ]]; then
    ok=false; reasons+=("post-fix validate not clean (exit ${post_exit}; reverse not materialized?)")
  fi

  # (d) idempotency: 再 fix で exit 0 かつ tree の sha256 不変 (no-op)
  local snap1 snap2 refix_exit
  snap1=$( cd "$tmp" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )
  ( cd "$REPO_ROOT" && "${PLUGIN_ROOT}/bin/folio" "${cmd[@]}" --root "$tmp" ) >/dev/null
  refix_exit=$?
  snap2=$( cd "$tmp" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )
  if [[ "$refix_exit" != "0" ]]; then
    ok=false; reasons+=("re-fix exit_code != 0 (got=${refix_exit})")
  fi
  if [[ "$snap1" != "$snap2" ]]; then
    ok=false; reasons+=("re-fix mutated files (idempotency violated)")
  fi

  if $ok; then
    echo "  [PASS] ${req_id} (RED pre-fix → fix exit ${fix_exit} → GREEN post-fix, idempotent)"
    echo ""; echo "Results: 1 passed, 0 failed (total 1)"
    return 0
  fi

  echo "  [FAIL] ${req_id}" >&2
  for r in "${reasons[@]}"; do echo "         - $r" >&2; done
  echo ""; echo "Results: 0 passed, 1 failed (total 1)"
  return 1
}

# --- kind dispatch: cli-golden / cli-scaffold / cli-fix は別経路、 省略時 (hook) は以降の既存 flow ---
KIND=$(yq -r '.kind // "hook"' "$SCENARIO_FILE")
if [[ "$KIND" == "cli-golden" ]]; then
  run_cli_golden "$SCENARIO_FILE"
  exit $?
fi
if [[ "$KIND" == "cli-scaffold" ]]; then
  run_cli_scaffold "$SCENARIO_FILE"
  rc=$?
  [[ -n "${SCAFFOLD_TMP:-}" && -d "$SCAFFOLD_TMP" ]] && rm -rf "$SCAFFOLD_TMP"
  exit $rc
fi
if [[ "$KIND" == "cli-fix" ]]; then
  run_cli_fix "$SCENARIO_FILE"
  rc=$?
  [[ -n "${FIX_TMP:-}" && -d "$FIX_TMP" ]] && rm -rf "$FIX_TMP"
  exit $rc
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
