#!/usr/bin/env bash
# folio ceiling-adjudicate — normalized findings を集計し advisory verdict を出す (folio-mzn.1.1)。
#
# skill(.1.4) が全 reviewer (fidelity-* / persona-walk-* / completeness-critic) 出力を集約して渡す前提。
# severity 件数を数え、 machinery (期待 lens 全走 + floor=PENDING) を裏打ちに verdict を裁定する。
#
# 凍結入力 schema (stdin or file):
#   {"expected_lenses":["fidelity-srs","persona-walk-srs","completeness-critic-srs"],
#    "ran_lenses":[...], "floor":"PENDING",
#    "findings":[{"id":"F1","agent":"fidelity-srs","severity":"critical","verdict":"upheld|refuted|uncertain"}]}
#
# 判定規則 (skeleton 既定・cell-quality で調整可・全て fail-closed):
#   machinery≠clean (expected_lenses 空/欠落 or ran ⊉ expected or floor≠PENDING) → PENDING (裁定しない)
#     ※ PASS の *必要条件* = expected_lenses 非空 ∧ ran⊇expected ∧ floor=PENDING (machinery を確認できねば PASS 禁止)。
#   upheld critical が1件でも                                                   → FAIL
#   非正準/欠落 severity を持つ upheld/uncertain が1件でも / upheld high / uncertain critical → ESCALATE (人間へ)
#   上記いずれもなし                                                            → PASS
#
# ★境界の再帰 (guardrail): severity ラベルは agent(LLM) が付けた値を *そのまま読むだけ*。 adjudicate は
#   「数えて閾値を当てる」だけで、 機械が severity を推定/再判定/正規化してはならない (counting=機械 / labeling=LLM)。
#   非正準 (null / 表記ゆれ) は *正規化せず*「非正準ラベルの存在」を数えて ESCALATE に倒す (fail-closed・境界維持)。
# ★exit code は verdict に依らず *常に 0* (advisory 構造担保・FAIL でも CI を止めない = REQ-VER-026)。
#   verdict は stdout に VERDICT=PASS|FAIL|ESCALATE|PENDING。 tool error (不正 JSON) のみ exit 2。
#
# usage: ceiling-adjudicate.sh [<normalized-findings.json>]   (省略時 stdin)

set -uo pipefail
command -v jq >/dev/null || { echo "ceiling-adjudicate: jq required" >&2; exit 2; }

if [[ $# -ge 1 ]]; then
  [[ -f "$1" ]] || { echo "ceiling-adjudicate: input file not found: $1" >&2; exit 2; }
  INPUT="$(cat "$1")"
else
  INPUT="$(cat)"
fi
[[ -n "$INPUT" ]] || { echo "ceiling-adjudicate: empty input (normalized findings JSON を渡すこと)" >&2; exit 2; }

# JSON 妥当性 (tool error は exit 2・verdict とは無関係)。
jq -e . >/dev/null 2>&1 <<<"$INPUT" || { echo "ceiling-adjudicate: invalid findings JSON" >&2; exit 2; }

# ★非正準/欠落 severity の surface (fail-closed・verdict に反映する)。 upheld/uncertain finding が
#   canonical severity {critical,high,medium,low} 以外 (null / 表記ゆれ "Critical"/"crit" 等) を持つと
#   literal 突合で数えられず黙殺され vacuous-PASS になる。 ★null が [null]|join で "" に畳まれ警告すら
#   出ないバグを (.severity // "(null)") で修正 (null を可視トークン化)。 verdict 側は強制 ESCALATE で吸収。
#   ★境界維持: severity を機械が推定/再判定/正規化してはならない。 「非正準・欠落ラベルの *存在*」を
#   fail-closed 事由として数えるだけ (counting=機械 / labeling=LLM の再帰を崩さない)。
unk="$(jq -r '
  [ (.findings // [])[]
    | select(.verdict=="upheld" or .verdict=="uncertain")
    | (.severity // "(null)")
    | select(. as $s | (["critical","high","medium","low"] | any(. == $s)) | not) ]
  | unique | join(",")' <<<"$INPUT")"
[[ -n "$unk" ]] && echo "ceiling-adjudicate: warn — upheld/uncertain finding に非正準/欠落 severity: $unk → 強制 ESCALATE (fail-closed・labeling は LLM 責務)" >&2

# 集計 + 裁定 (severity は literal 突合のみ = counting)。
OUT="$(jq -r '
  ["critical","high","medium","low"] as $canon
  | (.expected_lenses // []) as $exp
  | (.ran_lenses // [])   as $ran
  | (.floor // "")        as $floor
  | (.findings // [])     as $f
  | ($exp - $ran)         as $missing
  # ★非正準/欠落 severity を持つ upheld/uncertain finding の *件数* (severity を再判定せず存在を数える)。
  #   membership は any(. == $s) の等値突合で見る。jq の index($s) は $s が配列だと subarray 検索に化け、
  #   severity=["critical"] 等 canon の連続部分列を「正準」と誤判定して silent vacuous-PASS を作る (ceiling-recursion)。
  #   any(. == $s) は配列/null/数値/表記ゆれを全て非正準として数え ESCALATE に倒す (型に頑健・境界維持)。
  | ($f | map(select((.verdict=="upheld" or .verdict=="uncertain")
                     and (.severity as $s | ($canon | any(. == $s)) | not))) | length) as $nc
  | ($f | map(select(.verdict=="upheld"    and .severity=="critical")) | length) as $uc
  | ($f | map(select(.verdict=="upheld"    and .severity=="high"))     | length) as $uh
  | ($f | map(select(.verdict=="uncertain" and .severity=="critical")) | length) as $xc
  # machinery-not-clean = expected 空 or ran⊉expected or floor≠PENDING → 裁定しない (floor と同方向の fail-closed)。
  #   PASS の必要条件は「expected 非空 ∧ ran⊇expected ∧ floor=PENDING」。
  | (if (($exp|length) == 0 or ($missing|length) > 0 or ($floor != "PENDING")) then "PENDING"
     elif $uc > 0 then "FAIL"
     elif ($nc > 0 or $uh > 0 or $xc > 0) then "ESCALATE"
     else "PASS" end) as $verdict
  | "VERDICT=\($verdict)",
    "  machinery: expected=\($exp|length) ran=\($ran|length) missing=[\($missing|join(","))] floor=\($floor) noncanonical_labels=\($nc)",
    "  counts: upheld_critical=\($uc) upheld_high=\($uh) uncertain_critical=\($xc) findings_total=\($f|length)"
' <<<"$INPUT")" || { echo "ceiling-adjudicate: 集計中に jq エラー" >&2; exit 2; }

printf '%s\n' "$OUT"
exit 0
