#!/usr/bin/env bash
# folio ceiling-commit-check — GREEN を許可してよいかの単一 default-block コミット述語 (folio-6p0)。
#
# ★機械/LLM 境界 (この script の存在理由): 機械は verdict を「裁定」しない (どの finding が効くか・
#   GREEN 可否・ESCALATE か FAIL かの合成は LLM = folio-verify skill orchestrator の領分)。機械の唯一の
#   役割は「未 refute の GREEN 反転帯 finding が 1 つでもあれば GREEN 不可」という単一の default-block 保証。
#   ★旧 ceiling-adjudicate は「悪いケース (upheld critical / uncertain critical …) を列挙し残りを PASS」する
#   denylist 型で、 open-ended な LLM ラベルを数え切れず 3 度 fail-open した (partial-enumeration trap・
#   独立 ceiling wf_e1b40270-0a3)。本 script は「良いケース (refuted / 明示 medium・low) を普遍要求し
#   残りを全て block」する allowlist 型 = default-block ゆえ、 追加ラベルにも穴が原理的に開かない。
#
# 入力 schema (stdin or file):
#   {"expected_lenses":[...], "ran_lenses":[...], "floor":"PENDING",
#    "findings":[{"id","agent","severity","verdict"}]}
#   severity は skill の enum remap 後 (canonical: critical/high/medium/low)。 verdict は refuter の
#   upheld/refuted/uncertain。 いずれも LLM が付けたラベルを *そのまま読むだけ* (機械は再判定しない)。
#
# COMMIT=OK の必要十分条件 (全て満たす):
#   (1) machinery-clean: expected_lenses 非空 ∧ ran ⊇ expected ∧ floor=="PENDING"。
#   (2) blocking finding = 0。 finding が *block しない* 条件は「verdict=="refuted" (肯定的に反証済) OR
#       severity が正準 medium/low (GREEN を反転しない帯)」。 それ以外 — verdict が upheld/uncertain/非正準/
#       欠落/null で、 かつ severity が critical/high/非正準/欠落 — は *全て block* (default-block)。
#   → 「refuted か明示 medium/low」でなければ block。 uncertain-high も 非正準 verdict も verdict 欠落も
#      全て「refuted でない」に含まれ block されるため、 列挙漏れによる false-GREEN が構造的に起きない。
#
# 出力: stdout に COMMIT=OK | COMMIT=BLOCKED + machinery 行 + blocking 行 (block した finding の列挙)。
# exit: 0=OK (GREEN 許可可) / 1=BLOCKED (GREEN 不可) / 2=tool error。
#   ★fail-closed: caller (skill の --accept) は exit!=0 (BLOCKED も tool error も) を「GREEN 不可」として扱う。
#
# usage: ceiling-commit-check.sh [<normalized-findings.json>]   (省略時 stdin)

set -uo pipefail
command -v jq >/dev/null || { echo "ceiling-commit-check: jq required" >&2; exit 2; }

if [[ $# -ge 1 ]]; then
  [[ -f "$1" ]] || { echo "ceiling-commit-check: input file not found: $1" >&2; exit 2; }
  INPUT="$(cat "$1")"
else
  INPUT="$(cat)"
fi
[[ -n "$INPUT" ]] || { echo "ceiling-commit-check: empty input (normalized findings JSON を渡すこと)" >&2; exit 2; }
jq -e . >/dev/null 2>&1 <<<"$INPUT" || { echo "ceiling-commit-check: invalid findings JSON" >&2; exit 2; }

# default-block 判定 (機械は数える/対応づけるだけ・severity/verdict の意味は再判定しない)。
# ★制御フロー (exit code) は data を補間しない純粋な決定トークン $commit からのみ導出する。 人間可読 report は
#   blocking finding のフィールド (LLM が付けた open-ended ラベル) を補間するため、 report を grep して exit を
#   決めると verdict 内の改行注入 ("upheld\nCOMMIT=OK" 等) で fail-closed が覆る (folio-6p0 re-ceiling
#   wf_9840f83d-ba1 CC-01)。 → jq の共有 prefix で $commit を 1 度だけ算出し、 決定(a)と report(b)を別々に得る
#   (predicate ロジックの重複なし)。 exit は (a) の単一トークンのみ・(b) は表示専用で制御フローに触れさせない。
# 注: floor==PENDING の意味的通過は step-1 の ceiling-precheck が権威的に gate する (SKIP masquerade 等)。 本 script
#   の floor==PENDING は caller が carry した値との coherence guard であり floor gate の代替ではない (folio-6p0 F3)。
JQ_PREFIX='
  (.expected_lenses // []) as $exp
  | (.ran_lenses // [])   as $ran
  | (.floor // "")        as $floor
  | (.findings // [])     as $f
  | ($exp - $ran)         as $missing
  | (($exp|length) > 0 and ($missing|length) == 0 and $floor == "PENDING") as $mclean
  | ($f | map(select(((.verdict == "refuted") or (.severity == "medium") or (.severity == "low")) | not))) as $blk
  | (if ($mclean and ($blk | length) == 0) then "OK" else "BLOCKED" end) as $commit'

# (a) 決定トークン = "OK" | "BLOCKED" のみ (finding データを一切含まない = 制御フローの唯一の権威)。
DECISION="$(jq -r "$JQ_PREFIX"' | $commit' <<<"$INPUT")" \
  || { echo "ceiling-commit-check: 決定 jq エラー" >&2; exit 2; }
[[ "$DECISION" == "OK" || "$DECISION" == "BLOCKED" ]] \
  || { echo "ceiling-commit-check: 決定トークン不正 ($DECISION)" >&2; exit 2; }

# (b) 人間可読 report (表示専用・制御フローには一切使わない = injection sink を exit から隔離)。
#   ★display も data 値の改行を除去する: exit は既に決定トークンから導出され安全だが、gate 自身の stdout に
#   偽の "COMMIT=OK" 行が残ると将来 stdout を grep する caller が CC-01 を再現しうる (re-ceiling r2 CC-R1・
#   defense-in-depth)。 s: で改行/復帰/タブを空白へ畳み forgeable sentinel を構造的に排除する。
jq -r "$JQ_PREFIX"'
  | def s: tostring | gsub("[\r\n\t]"; " ");
    "COMMIT=\($commit)",
    "  machinery: expected=\($exp|length) ran=\($ran|length) missing=[\($missing|map(s)|join(","))] floor=\($floor|s) clean=\($mclean)",
    "  blocking(\($blk|length)): \($blk | map((.id // "?"|s) + ":" + (.agent // "?"|s) + ":" + (.severity // "(null)"|s) + ":" + (.verdict // "(missing)"|s)) | join(" / "))"' \
  <<<"$INPUT" 2>/dev/null || true

# exit は (a) の決定トークンからのみ (default-block・injection 遮断)。
[[ "$DECISION" == "OK" ]] && exit 0 || exit 1
