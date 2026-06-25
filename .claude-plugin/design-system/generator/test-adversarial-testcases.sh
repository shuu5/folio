#!/usr/bin/env bash
# test-adversarial-testcases.sh — test-cases-pack floor の敵対検査 (verify-testcases.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-testcases.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (worker brief): trace 改竄・偽 FR/AC 参照 (dangling)・捏造手順・(ref,role) 意味偽装・可視 echo 改竄を *全捕捉*。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-testcases.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-appointment.testcases.yaml"
MANIFEST="$HERE/prose/clinic-appointment.testcases.prose.yaml"
ASSEMBLE="$HERE/assemble-testcases.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-testcases.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# expect_fail <label> <mutated.html> — verify が exit 1 (FAIL) を返すべき
expect_fail() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
# mut <case-num> <perl-prog> — GOOD を 1 箇所改竄して $TMP/m<N>.html を作り path を返す
mut() { local n="$1" prog="$2"; local m="$TMP/m$n.html"; perl -0777 -pe "$prog" "$GOOD" > "$m"; printf '%s' "$m"; }

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- 件数 / 構造 ---
expect_fail "testcase-card マーカー削除 (件数)" "$(mut 1 's{<div data-component="testcase-card" id="tc-TC1">}{<div data-component="testcase-XXX" id="tc-TC1">}')"
expect_fail "rtm-row 削除 (件数 + RTM 脱落)"    "$(mut 2 's{<tr data-component="rtm-row">.*?</tr>\n}{}s')"

# --- 可視 card テキスト fidelity (属性 intact のまま可視だけ改竄・捏造ケース) ---
expect_fail "tc-id 可視捏造"                  "$(mut 3 's{<span class="tc-id">TC1</span>}{<span class="tc-id">TCX</span>}')"
expect_fail "tc-title 可視捏造"               "$(mut 4 's{(<h3 class="tc-title">)[^<]+}{${1}捏造タイトル}')"
expect_fail "tc-kind 可視ラベル捏造"          "$(mut 5 's{(<span class="tc-kind normal">)[^<]+}{${1}でたらめ}')"
expect_fail "tc-kind class 改竄 (label/class 不整合)" "$(mut 6 's{<span class="tc-kind normal">正常系}{<span class="tc-kind abnormal">正常系}')"
expect_fail "tc-prio class 改竄 (must→should)" "$(mut 7 's{<span class="tc-prio must">必須</span>}{<span class="tc-prio should">必須</span>}')"
expect_fail "tc-prio ラベル捏造"             "$(mut 8 's{(<span class="tc-prio must">)[^<]+}{${1}最優先}')"

# --- 捏造手順 (前提・操作・期待結果の可視テキスト改竄) ---
expect_fail "precondition 捏造手順"          "$(mut 9 's{残りが 2 人ぶん空いている}{残りが 999 人ぶん空いている}')"
expect_fail "expected 捏造結果"              "$(mut 10 's{空き枠が「残り 2」}{空き枠が「残り 99」}')"
expect_fail "step 捏造操作"                  "$(mut 11 's{患者が日時を選び、 その枠の空きを問い合わせる}{捏造した操作手順}')"

# --- scope-summary-panel (試すこと/試さないこと) 改竄 ---
expect_fail "scope.in 項目捏造 (rewrite)"    "$(mut 28 's{空き枠の確認・予約受付・競合時の確定・診療時間外の拒否}{でたらめな捏造スコープ}')"
expect_fail "scope.out 項目捏造 (rewrite)"   "$(mut 29 's{診察内容・カルテ・会計・診療報酬の正しさ}{でたらめな除外スコープ}')"
expect_fail "scope.in 項目削除 (件数脱落)"   "$(mut 30 's{<li><span class="b">[^<]*</span>受付時の本人確認の差し戻し[^<]*</li>\n}{}s')"

# --- ★三段 trace / cross-doc 照会の改竄 (本 pack の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 12 's{data-trace-ref="FR1" data-trace-role="claim">FR1}{data-trace-ref="FR99" data-trace-role="claim">FR99}')"
expect_fail "trace role 意味偽装 (claim→verification)" "$(mut 13 's{data-trace-ref="FR1" data-trace-role="claim"}{data-trace-ref="FR1" data-trace-role="verification"}')"
expect_fail "trace ref 削除 (count mismatch)" "$(mut 14 's{<span class="tc-ref" data-trace-ref="FR1" data-trace-role="claim">FR1</span>}{}')"
expect_fail "tc-ref 可視 vs attr desync"      "$(mut 15 's{(data-trace-ref="FR1" data-trace-role="claim">)FR1(</span>)}{${1}FRX${2}}')"
expect_fail "RTM FR code 改竄"                "$(mut 16 's{<b class="rtm-code">FR1</b>}{<b class="rtm-code">FR-FAKE</b>}')"
# ★per-card trace pin (card-keyed) の regression: card 間で FR/AC を入替える (RTM 無改竄)。 global key SET・
#   (key,role) ペア SET・count・RTM は全て不変ゆえ 3/3c は素通る。 3d (per-card 三つ組) のみが捕捉する。
expect_fail "card 間 FR 入替 (TC1↔TC8・RTM 無改竄)" "$(mut 26 's{(id="tc-TC1">.*?)data-trace-ref="FR1" data-trace-role="claim">FR1(</span>)}{${1}data-trace-ref="FR3" data-trace-role="claim">FR3${2}}s; s{(id="tc-TC8">.*?)data-trace-ref="FR3" data-trace-role="claim">FR3(</span>)}{${1}data-trace-ref="FR1" data-trace-role="claim">FR1${2}}s')"
expect_fail "card 間 AC 入替 (TC4↔TC5・RTM 無改竄)" "$(mut 27 's{(id="tc-TC4">.*?)data-trace-ref="AC4" data-trace-role="verification">AC4(</span>)}{${1}data-trace-ref="AC5" data-trace-role="verification">AC5${2}}s; s{(id="tc-TC5">.*?)data-trace-ref="AC5" data-trace-role="verification">AC5(</span>)}{${1}data-trace-ref="AC4" data-trace-role="verification">AC4${2}}s')"

# --- ★FR/AC 平易ラベル併記の fidelity (persona ceiling 是正・SRS 由来でないラベルを封鎖) ---
# card trace の併記ラベルを捏造 (data-label-ref intact のまま可視ラベルだけ非 SRS 値へ)
expect_fail "card ラベル捏造 (非 SRS 由来)"   "$(mut 31 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{<span class="tc-ref-label" data-label-ref="FR1">でたらめ機能</span>}')"
# FR1 のラベルを別 FR(FR2)の正規ラベルへ swap (SRS には在るが ref↔label の対応が誤り)
expect_fail "card ラベル swap (FR1↔FR2 ラベル)" "$(mut 32 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{<span class="tc-ref-label" data-label-ref="FR1">予約受付</span>}')"
# RTM の併記ラベルを捏造
expect_fail "RTM ラベル捏造 (非 SRS 由来)"     "$(mut 33 's{<span class="rtm-label" data-label-ref="FR1">空き確認</span>}{<span class="rtm-label" data-label-ref="FR1">捏造RTMラベル</span>}')"
# card ラベル要素を削除 (件数脱落)
expect_fail "card ラベル削除 (件数)"           "$(mut 34 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{}')"
# cover ref-chip の機能名要約を部分捏造 (b2 の先頭ラベルだけ非 SRS 値へ)
expect_fail "cover 機能名要約 部分捏造"        "$(mut 35 's{(data-component="cross-doc-ref-chip">.*?の要件 <b>)空き確認}{${1}捏造機能}s')"

# --- cross-doc 可視 echo (表紙 ref-chip / trace 見出し・照会先) 改竄 ---
expect_fail "cover ref-chip srs_doc_id 捏造" "$(mut 17 's{(<div class="reader-chip" data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"
expect_fail "cover ref-chip FR join 捏造"    "$(mut 18 's{(data-component="cross-doc-ref-chip">.*?の要件 <b>)[^<]+}{${1}FR1だけ}s')"
expect_fail "tc-trace-h テンプレ改竄"        "$(mut 19 's{検証する要件と確かめ方}{でたらめな見出し}')"
expect_fail "tc-trace-tgt 照会先改竄"        "$(mut 20 's{照会先: SRS-CLINIC-APPT}{照会先: FAKE-SRS}')"

# --- core chrome / cover-meta / term-inline / escape ---
expect_fail "cover-meta 件数捏造"            "$(mut 21 's{(<span class="k">件数</span><span class="v">)[^<]+}{${1}999件}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 22 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"      "$(mut 23 's{data-term="診療枠">予約できる時間帯}{data-term="GHOST">予約できる時間帯}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 24 's{(data-prose-slot="plain" data-slot-id="plain-TC1">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 25 's{(data-slot-id="plain-TC1">)[^<]+(</p>)}{${1}${2}}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi

echo ""
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
