#!/usr/bin/env bash
# folio srs-ceiling-oracle — differential comparator (dev-time・folio-mzn.1.5 S11)。
#
# JS 基準器 (srs-ceiling-oracle.workflow.js) の reference-verdicts.json と、prose skill
# (folio-verify) が同じ fixture 群に書いた verify-state (.folio/verify-state/*.json) を突合する。
#
# ★設計原則 (独立 ceiling wf_3161e4a6 / wf_3f5ce994 / wf_62e776c3): **reference/verify-state の
#   自己申告値を信用しない** — comparator が消費する値は全て
#   (a) SSoT 結合 (expect_commit / detector 要求 lens 名集合 / fixture 名集合 = expected.json 由来)、
#   (b) hash 結合 (html/contract bytes = 現物 sha256 との three-way 一致)、
#   (c) 機械計算 (reference に永続化済の findings/ran_lenses から ceiling-commit-check を再実行して
#       commit verdict を再導出・detector 帰属を findings から名前集合で再導出・rc/件数/集合比較)
#   のいずれかに fail-closed に接地する。自己申告値 (actual_commit / detector_hit / allPass) は
#   機械再導出との一致検査のみに使う (食い違い = fail)。
# ★exit 0 の意味: (i) 機械再導出 commit == SSoT expect ∧ 自己申告と無矛盾 ∧ pass==true (BLOCKED で
#   SSoT が detector を要求する fixture は findings 再導出の帰属成立も) ∧ (ii) prose 側 state が SSoT
#   expect の写像に一致 ∧ (iii) fixture 名多重集合が expected.json と exactly-once 一致 ∧
#   (iv) 両経路が同一 bytes を検証した (three-way hash)。
# ★意味判定はしない — 文字列/集合/hash 照合と、決定論的 default-block 述語 (folio ceiling-commit-check)
#   の rc 読取りのみ (述語の追加は件数/集合/rc の機械計算であって意味判定の追加ではない)。
#
# usage: compare-verdicts.sh [<reference-verdicts.json>] [<verify-state-dir>]
#   既定: <script-dir>/out/reference-verdicts.json / <repo-root>/.folio/verify-state
# exit: 0 = 全 fixture で (proof 合格 ∧ 経路一致 ∧ bytes 同一) / 1 = 不合格・不一致・STALE / 2 = tool error

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BIN_FOLIO="$GEN/../../bin/folio"   # generator → design-system → .claude-plugin/bin/folio
REF="${1:-$SCRIPT_DIR/out/reference-verdicts.json}"
STATE_DIR="${2:-$REPO_ROOT/.folio/verify-state}"
EXPECTED="$SCRIPT_DIR/expected.json"
command -v jq >/dev/null || { echo "compare-verdicts: jq required" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "compare-verdicts: sha256sum required" >&2; exit 2; }
[[ -f "$REF" ]] || { echo "compare-verdicts: reference not found: $REF (先に oracle WF を走らせよ)" >&2; exit 2; }
[[ -f "$EXPECTED" ]] || { echo "compare-verdicts: expected.json not found: $EXPECTED" >&2; exit 2; }
[[ -x "$BIN_FOLIO" ]] || { echo "compare-verdicts: folio CLI not found: $BIN_FOLIO (commit verdict の機械再導出に必須)" >&2; exit 2; }
[[ -d "$STATE_DIR" ]] || { echo "compare-verdicts: verify-state dir not found: $STATE_DIR (先に prose 側 /folio-verify を fixture 群へ走らせよ)" >&2; exit 2; }

echo "=== srs-ceiling-oracle differential: JS 基準器 ↔ prose skill (folio-verify) ==="
echo "  reference:  $REF"
echo "  state-dir:  $STATE_DIR"

# expected_lenses の SSoT (workflow.js の LENSES 定義と一致させる固定 3 lens・SKILL §3 と同一)
EXPECTED_LENSES='["fidelity-srs","persona-walk-srs","completeness-critic-srs"]'

# ---- SSoT (expected.json) を写像として読む — expect_commit / detector 要求 lens 名は reference から読まない ----
# (round-3 B-R3-1(1): detector は件数でなく名前集合で保持する — 件数保存の名前 drift を封鎖)
exp_rows="$(jq -r '.fixtures[] | [.name, .expect_commit, ((.expect_detector // []) | join(","))] | @tsv' "$EXPECTED")" \
  || { echo "compare-verdicts: expected.json parse 失敗" >&2; exit 2; }
[[ -n "$exp_rows" ]] || { echo "compare-verdicts: expected.json の fixtures が空" >&2; exit 2; }
declare -A EXPECT DET_NAMES
exp_names=""
while IFS=$'\t' read -r n e d; do EXPECT["$n"]="$e"; DET_NAMES["$n"]="$d"; exp_names+="$n"$'\n'; done <<< "$exp_rows"
con_rel="$(jq -r '.contract // empty' "$EXPECTED")"
[[ -n "$con_rel" && -f "$GEN/$con_rel" ]] || { echo "compare-verdicts: expected.json の contract が解決できない ($con_rel)" >&2; exit 2; }
cur_ch="$(sha256sum "$GEN/$con_rel" | cut -d' ' -f1)"

# ---- fail-closed parse: jq 非零・空 perFixture・allPass 非 true を握り潰さない (has() 3 値化) ----
refN="$(jq -r '.perFixture | length' "$REF" 2>/dev/null)" || { echo "compare-verdicts: reference parse 失敗" >&2; exit 2; }
[[ "$refN" =~ ^[0-9]+$ && "$refN" -ge 1 ]] || { echo "compare-verdicts: perFixture が空/不正 — 0 件比較を『一致』と報告しない (fail-closed)" >&2; exit 2; }
allpass="$(jq -r 'if has("allPass") then (.allPass | tostring) else "missing" end' "$REF")"
if [[ "$allpass" != "true" ]]; then
  echo "compare-verdicts: reference の allPass != true ($allpass) — JS 基準器が defect-injection proof を宣言していない (退化/切詰め/旧 schema の reference を fail-closed で拒否)" >&2
  exit 1
fi

# ---- (iii) fixture 名の多重集合 exactly-once 被覆 (件数一致は必要条件であって十分条件でない) ----
ref_names="$(jq -r '.perFixture[].fixture // "MISSING"' "$REF")"
if ! diff <(sort <<< "$exp_names" | grep -v '^$') <(sort <<< "$ref_names" | grep -v '^$') >/dev/null; then
  echo "compare-verdicts: reference の fixture 名多重集合が expected.json と不一致 (脱落/複製/未知名) — fail-closed" >&2
  diff <(sort <<< "$exp_names" | grep -v '^$') <(sort <<< "$ref_names" | grep -v '^$') | sed 's/^/    /' >&2
  exit 2
fi

fail=0
for ((i = 0; i < refN; i++)); do
  fx="$(jq -c ".perFixture[$i]" "$REF")" || { echo "compare-verdicts: perFixture[$i] 抽出失敗" >&2; exit 2; }
  name="$(jq -r '.fixture // empty' <<< "$fx")"
  expect="${EXPECT[$name]:-}"
  det_names="${DET_NAMES[$name]:-}"
  js_commit="$(jq -r '.actual_commit // "NULL"' <<< "$fx")"
  js_pass="$(jq -r '(.pass // false) | tostring' <<< "$fx")"
  det="$(jq -r 'if has("detector_hit") then (.detector_hit | tostring) else "absent" end' <<< "$fx")"
  ref_hh="$(jq -r '.html_hash // "missing"' <<< "$fx")"
  ref_ch="$(jq -r '.contract_hash // "missing"' <<< "$fx")"

  # ---- (c) commit verdict の機械再導出 (round-3 B-R3-1(2)): 永続化済 findings/ran_lenses から
  #      normalized を再構成し、決定論的 default-block 述語 ceiling-commit-check を再実行する。
  #      自己申告 actual_commit は再導出値との一致検査のみに使う (単一 LLM relay の rc 誤報・
  #      degenerate-ceiling masking・edit-without-rerun を cross-check で捕捉)。 ----
  normalized="$(jq -c --argjson el "$EXPECTED_LENSES" '{expected_lenses: $el, ran_lenses: (.ran_lenses // []), floor: "PENDING", findings: ((.findings // []) | map({id, agent, severity} + (if has("verdict") then {verdict} else {} end)))}' <<< "$fx")" \
    || { echo "compare-verdicts: perFixture[$i] の normalized 再構成失敗" >&2; exit 2; }
  printf '%s' "$normalized" | "$BIN_FOLIO" ceiling-commit-check >/dev/null 2>&1; ccrc=$?
  case "$ccrc" in
    0) recomputed="OK" ;;
    1) recomputed="BLOCKED" ;;
    *) printf '  [FAIL] %-16s ceiling-commit-check 再実行が tool error (rc=%s) — 再導出不能を一致と詐称しない\n' "$name" "$ccrc"; fail=1; continue ;;
  esac

  # ---- (i) 機械再導出 == SSoT expect ∧ 自己申告と無矛盾 ∧ pass==true ----
  if [[ -z "$expect" || "$recomputed" != "$expect" || "$js_pass" != "true" ]]; then
    printf '  [FAIL] %-16s 機械再導出=%s (SSoT expect=%s, 自己申告=%s, pass=%s) — JS 基準器が期待 verdict に不合格\n' "$name" "$recomputed" "${expect:-?}" "$js_commit" "$js_pass"; fail=1; continue
  fi
  if [[ "$js_commit" != "$recomputed" ]]; then
    printf '  [FAIL] %-16s 自己申告 actual_commit=%s ≠ findings からの機械再導出=%s — self-report 矛盾 (rc 誤報/改竄/部分再生成)\n' "$name" "$js_commit" "$recomputed"; fail=1; continue
  fi
  # ---- detector 帰属の機械再導出 (round-3 B-R3-1(3)): findings から SSoT 要求 lens 名集合で再導出し、
  #      自己申告 detector_hit と突合する (帰属は GREEN 反転帯 = critical/high の未 refute finding)。 ----
  rehit="$(jq -r --arg dets "$det_names" '[.findings[]? | select((.agent as $a | ($dets | split(",")) | index($a)) and (.severity == "critical" or .severity == "high") and (.verdict != "refuted"))] | length' <<< "$fx")"
  if [[ "$expect" == "BLOCKED" && -n "$det_names" ]]; then
    if [[ "$det" != "true" || "$rehit" -lt 1 ]]; then
      printf '  [FAIL] %-16s detector 帰属不成立 (自己申告=%s / findings 再導出=%s 件・SSoT 要求 lens: %s)\n' "$name" "$det" "$rehit" "$det_names"; fail=1; continue
    fi
  elif [[ "$det" != "absent" ]]; then
    if ! { [[ "$det" == "true" && "$rehit" -ge 1 ]] || [[ "$det" == "false" && "$rehit" -eq 0 ]]; }; then
      printf '  [FAIL] %-16s detector_hit 自己申告 (%s) と findings 再導出 (%s 件) の食い違い — self-report 矛盾\n' "$name" "$det" "$rehit"; fail=1; continue
    fi
  fi

  # ---- (iv) three-way hash 結合: JS が検証した bytes == 現物 == prose が検証した bytes ----
  fixture_path="$SCRIPT_DIR/out/fixtures/$name.html"
  [[ -f "$fixture_path" ]] || { printf '  [FAIL] %-16s fixture 現物が不在 (%s)\n' "$name" "$fixture_path"; fail=1; continue; }
  cur_hh="$(sha256sum "$fixture_path" | cut -d' ' -f1)"
  if [[ "$ref_hh" != "$cur_hh" || "$ref_ch" != "$cur_ch" ]]; then
    printf '  [FAIL] %-16s reference が STALE (JS 側 hash ≠ 現物: html %s / contract %s) — JS oracle の再実行漏れか fixture 再生成後の残骸\n' "$name" "$([[ "$ref_hh" == "$cur_hh" ]] && echo ok || echo NG)" "$([[ "$ref_ch" == "$cur_ch" ]] && echo ok || echo NG)"; fail=1; continue
  fi
  # ---- verify-state 解決: 絶対パス一致・件数 exactly-1・hash 照合 (stale/曖昧を黙って採用しない) ----
  matches=()
  for sf in "$STATE_DIR"/*.json; do
    [[ -f "$sf" ]] || continue
    jq -e --arg p "$fixture_path" '.html == $p' "$sf" >/dev/null 2>&1 && matches+=("$sf")
  done
  if [[ ${#matches[@]} -ne 1 ]]; then
    printf '  [FAIL] %-16s verify-state 解決 %s 件 (0=欠落 / ≥2=曖昧) — 黙って採用しない\n' "$name" "${#matches[@]}"; fail=1; continue
  fi
  sf="${matches[0]}"
  rec_hh="$(jq -r '.html_hash // empty' "$sf")"
  rec_ch="$(jq -r '.contract_hash // empty' "$sf")"
  if [[ -z "$rec_hh" || "$rec_hh" != "$cur_hh" || -z "$rec_ch" || "$rec_ch" != "$cur_ch" ]]; then
    printf '  [FAIL] %-16s verify-state が STALE (prose 側 hash ≠ 現物) — 検証後に fixture/contract が変わった記録を採用しない\n' "$name"; fail=1; continue
  fi
  # ---- (ii) prose 側 state が SSoT expect の写像に一致 ----
  skill_state="$(jq -r '.state // empty' "$sf")"
  ok=0
  case "$expect" in
    OK)      [[ "$skill_state" == "READY" || "$skill_state" == "GREEN" ]] && ok=1 ;;
    BLOCKED) [[ "$skill_state" == "CEILING-FAIL" ]] && ok=1 ;;
  esac
  if [[ "$ok" == 1 ]]; then printf '  [OK]   %-16s SSoT expect=%s ⟺ js=%s(機械再導出一致・pass) ⟺ skill=%s (bytes three-way 一致)\n' "$name" "$expect" "$recomputed" "$skill_state"
  else printf '  [FAIL] %-16s SSoT expect=%s / js=%s / skill=%s — prose 側が期待 verdict の写像に不一致\n' "$name" "$expect" "$recomputed" "$skill_state"; fail=1; fi
done

if [[ "$fail" -eq 0 ]]; then echo "RESULT: proof 合格 ∧ 経路一致 ∧ bytes 同一 (fixture 集合 = expected.json と exactly-once 一致・commit/detector は findings から機械再導出) — prose-conduit は本 corpus 上で JS 基準器と同 verdict"; exit 0
else echo "RESULT: 不合格/不一致/STALE あり — prose skill 手順の取りこぼし (trust gap) / JS 側 machinery / 記録・reference の鮮度を調査せよ"; exit 1; fi
