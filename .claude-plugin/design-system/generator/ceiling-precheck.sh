#!/usr/bin/env bash
# folio ceiling-precheck — floor が *真に* CEILING=PENDING を出したかを fail-closed に確認する (folio-mzn.1.1)。
#
# 目的 = 起動順序不変条件 (floor→ceiling) を prose でなく機械で担保する。 floor (verify-srs) が全 gate を
# 通過して advisory PENDING を出したときだけ ceiling を起動してよい。 honest-SKIP (gate F renderer 不在等で
# [SKIP]) が PENDING を偽装する = floor 不完全なのに ceiling を起動する masquerade を排除する。
#
# 入力 = verify-srs の stdout (floor 結果)。 file 引数 or stdin。
# 判定:
#   0 = 真の PENDING   : "RESULT: floor PASS" ∧ "CEILING=PENDING" ∧ SKIP 痕跡なし (ceiling 起動可)
#   1 = floor 未通過   : floor FAIL、 または floor PASS/CEILING=PENDING を検出できず
#   3 = SKIP masquerade: floor PASS を宣言したが gate SKIP あり (floor 不完全・ceiling 起動不可)
#   2 = tool error     : 入力不在 / 空
#
# 機械/LLM 境界: 文字列痕跡の照合だけ (数える・順序を担保する)。 意味判定はしない。
# usage: ceiling-precheck.sh [<floor-output.txt>]   (省略時 stdin)

set -uo pipefail

if [[ $# -ge 1 ]]; then
  [[ -f "$1" ]] || { echo "ceiling-precheck: input file not found: $1" >&2; exit 2; }
  INPUT="$(cat "$1")"
else
  INPUT="$(cat)"
fi
[[ -n "$INPUT" ]] || { echo "ceiling-precheck: empty input (verify-srs の stdout を渡すこと)" >&2; exit 2; }

# ---- floor 未通過: floor FAIL ----
if grep -q 'RESULT: floor FAIL' <<<"$INPUT"; then
  echo "PRECHECK=FAIL — floor が不合格 (RESULT: floor FAIL)。 ceiling 以前に floor を直せ" >&2
  echo "PRECHECK=FAIL"
  exit 1
fi

# ---- floor PASS + CEILING=PENDING の positive 確認 (両方要る) ----
if ! grep -q 'RESULT: floor PASS' <<<"$INPUT"; then
  echo "PRECHECK=FAIL — 'RESULT: floor PASS' を検出できず (floor 結果でない or 不完全出力)" >&2
  echo "PRECHECK=FAIL"
  exit 1
fi
if ! grep -q 'CEILING=PENDING' <<<"$INPUT"; then
  echo "PRECHECK=FAIL — 'CEILING=PENDING' を検出できず (floor が advisory PENDING を宣言していない)" >&2
  echo "PRECHECK=FAIL"
  exit 1
fi

# ---- SKIP masquerade 検出: floor PASS/PENDING を宣言したが gate が SKIP されている痕跡 ----
# verify-srs は render gate 未実行時に "[SKIP] gate F..." / "render gate 未完" / "gateF=skip census=skip" を出す。
skip=""
grep -q '\[SKIP\]'                         <<<"$INPUT" && skip+=" [SKIP]-gate"
grep -q 'render gate 未完'                 <<<"$INPUT" && skip+=" render-未完"
grep -qE 'gateF=skip|gateCensus=skip|census=skip' <<<"$INPUT" && skip+=" gate=skip"
if [[ -n "$skip" ]]; then
  echo "PRECHECK=SKIP-MASQUERADE — floor は PENDING を出したが gate SKIP あり (floor 不完全・ceiling 起動不可):$skip" >&2
  echo "  → renderer 在環境で render-gate を回し floor を完成させてから ceiling を起動せよ (honest-SKIP≠PENDING)" >&2
  echo "PRECHECK=SKIP-MASQUERADE"
  exit 3
fi

echo "PRECHECK=TRUE-PENDING — floor 全 gate 通過 + CEILING=PENDING (ceiling 起動可)"
exit 0
