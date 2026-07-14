#!/usr/bin/env bash
# test-adversarial-roadmap.sh — roadmap-pack floor の敵対検査 (verify-roadmap.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-roadmap.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼: seq 順序改竄・stage-keyed 構造改竄・偽 F/FR 照会 (dangling)・(ref,role) 意味偽装・per-item relocation・
#   直近段階ハイライトの負の主張 (0 件→非0) 偽装・可視 echo 改竄・双子属性 valid-pair relocation を *全捕捉* (per-shape MK)。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-roadmap.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-roadmap.roadmap.yaml"
MANIFEST="$HERE/prose/clinic-roadmap.roadmap.prose.yaml"
ASSEMBLE="$HERE/assemble-roadmap.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-roadmap.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm / gate F (playwright) は bulk case では honest skip (10分/suite を維持)。 conformance pin は末尾で明示解除。
export SKIP_REPRO="${SKIP_REPRO:-1}"
export SKIP_RENDER="${SKIP_RENDER:-1}"
source "$HERE/lib/test-repro-pins.sh"
expect_fail() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
mut() { local n="$1" prog="$2"; local m="$TMP/m$n.html"; perl -0777 -pe "$prog" "$GOOD" > "$m"; printf '%s' "$m"; }

# baseline sanity
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- 件数 / 構造マーカー ---
expect_fail "roadmap-stage マーカー削除 (件数)" "$(mut 1 's{<div data-component="roadmap-stage" id="stage-1">}{<div data-component="roadmap-XXX" id="stage-1">}')"
expect_fail "roadmap-item マーカー削除 (件数)"  "$(mut 2 's{<li data-component="roadmap-item" id="rm-RM1">}{<li data-component="roadmap-XXX" id="rm-RM1">}')"
expect_fail "trace-row 削除 (件数)"             "$(mut 3 's{<tr data-component="trace-row"><td class="trc-id"><a href="#rm-RM1">.*?</tr>\n}{}s')"

# --- ★seq 昇順の決定的順序 (本 pack の核) ---
expect_fail "stage badge 捏造 (順序 pin)"       "$(mut 4 's{<span class="rm-stage-badge">M1</span>}{<span class="rm-stage-badge">M9</span>}')"
expect_fail "stage badge 入替 (M1↔M2・順序改竄)" "$(mut 5 's{<span class="rm-stage-badge">M1</span>}{<span class="rm-stage-badge">__SW__</span>}; s{<span class="rm-stage-badge">M2</span>}{<span class="rm-stage-badge">M1</span>}; s{<span class="rm-stage-badge">__SW__</span>}{<span class="rm-stage-badge">M2</span>}')"
expect_fail "stage target 捏造"                 "$(mut 6 's{<span class="rm-stage-target">2026 Q3</span>}{<span class="rm-stage-target">2099 Q9</span>}')"

# --- ★直近段階ハイライトの件数 (正の主張 + 負の主張「0 件」) ---
expect_fail "★ハイライト 0 件→非0 偽装 (負の主張 flip・任意 0→3)" "$(mut 7 's{(<span class="hl-count could"><span class="hlc-label">任意</span><span class="hlc-n">)0}{${1}3}')"
expect_fail "ハイライト 件数 捏造 (必須 1→9)"     "$(mut 8 's{(<span class="hl-count must"><span class="hlc-label">必須</span><span class="hlc-n">)1}{${1}9}')"
expect_fail "ハイライト hl-stage 捏造"            "$(mut 9 's{<span class="hl-stage">M1</span>}{<span class="hl-stage">M9</span>}')"

# --- ★cross-doc 前方照会の改竄 (本 pack の核) ---
expect_fail "偽 VISION 照会 (dangling・F-99)"     "$(mut 10 's{data-rm-vision-ref="F-1" data-rm-vision-role="claim"><span class="xref-code">F-1</span>}{data-rm-vision-ref="F-99" data-rm-vision-role="claim"><span class="xref-code">F-99</span>}')"
expect_fail "偽 SRS 照会 (dangling・FR99)"        "$(mut 11 's{data-rm-srs-ref="FR3" data-rm-srs-role="claim"><span class="xref-code">FR3</span>}{data-rm-srs-ref="FR99" data-rm-srs-role="claim"><span class="xref-code">FR99</span>}')"
expect_fail "照会 role 意味偽装 (claim→rationale)" "$(mut 12 's{data-rm-vision-ref="F-1" data-rm-vision-role="claim"}{data-rm-vision-ref="F-1" data-rm-vision-role="rationale"}')"
expect_fail "SRS 照会 ref 削除 (count mismatch)"  "$(mut 13 's{<a class="rm-ref" href="clinic-appointment.srs.html#FR3" data-rm-srs-ref="FR3" data-rm-srs-role="claim"><span class="xref-code">FR3</span><span class="rm-ref-label" data-srs-label-ref="FR3">[^<]*</span></a>}{}')"
expect_fail "xref-code 可視 vs attr desync"       "$(mut 14 's{(data-rm-srs-ref="FR3" data-rm-srs-role="claim"><span class="xref-code">)FR3(</span>)}{${1}FRX${2}}')"

# --- ★per-item card-keyed 束縛 (relocation・attr swap で global set 不変) ---
expect_fail "★card 間 SRS ref attr 入替 (RM1.FR3↔RM5.FR7・global set 不変) → card-keyed/双子で捕捉" "$(mut 15 's{(id="rm-RM1">.*?)data-rm-srs-ref="FR3"(.*?id="rm-RM5">.*?)data-rm-srs-ref="FR7"}{${1}data-rm-srs-ref="FR7"${2}data-rm-srs-ref="FR3"}s')"
# ★item を別 priority へ relocation (M1 must グループの class を should へ・label は「必須」のまま = class↔label 不整合)
#   → §6 card-keyed (id,ref,role) 不変・§12 label 総数不変を素通りし、 構造束縛 §9 (seq, prio-class, label, id) *のみ* が捕捉。
expect_fail "★priority relocation (M1 must→should class・label 必須のまま) → 構造束縛 §9 で捕捉" "$(mut 16 's{<div class="rm-prio must"><div class="rm-prio-head"><span class="rm-prio-label">必須</span></div>}{<div class="rm-prio should"><div class="rm-prio-head"><span class="rm-prio-label">必須</span></div>}')"

# --- ★href 遷移先 fidelity ---
expect_fail "VISION href anchor swap (#F-1→#F-99・attr 温存)" "$(mut 17 's{(<a class="rm-ref" href="clinic-appointment.vision.html)#F-1(" data-rm-vision-ref="F-1")}{${1}#F-99${2}}')"
expect_fail "SRS href 外部 host swap"             "$(mut 18 's{<a class="rm-ref" href="clinic-appointment.srs.html#FR1"}{<a class="rm-ref" href="https://evil.example#FR1"}')"
expect_fail "SRS href anchor swap (#FR3→#FR99)"   "$(mut 19 's{(<a class="rm-ref" href="clinic-appointment.srs.html)#FR3(" data-rm-srs-ref="FR3")}{${1}#FR99${2}}')"

# --- ★照会ラベル併記 fidelity ---
expect_fail "VISION ラベル捏造 (非 VISION 由来)"  "$(mut 20 's{<span class="rm-ref-label" data-vision-label-ref="F-1">枠の確定を仕組みで守る</span>}{<span class="rm-ref-label" data-vision-label-ref="F-1">でたらめ方向</span>}')"
expect_fail "VISION ラベル swap (F-1→F-2 の正規名)" "$(mut 21 's{<span class="rm-ref-label" data-vision-label-ref="F-1">枠の確定を仕組みで守る</span>}{<span class="rm-ref-label" data-vision-label-ref="F-1">決めた診療時間の外では受けない</span>}')"
expect_fail "SRS ラベル捏造"                       "$(mut 22 's{<span class="rm-ref-label" data-srs-label-ref="FR3">競合拒否</span>}{<span class="rm-ref-label" data-srs-label-ref="FR3">でたらめ機能</span>}')"

# --- ★可視テキスト fidelity (card-keyed) ---
expect_fail "item text 捏造 (数値改竄)"           "$(mut 23 's{確定は 1 件だけになるようにする}{確定は 999 件だけになるようにする}')"
expect_fail "rm-id 可視捏造"                       "$(mut 24 's{<span class="rm-id">RM1</span>}{<span class="rm-id">RMXX</span>}')"

# --- ★trace 表 fidelity ---
expect_fail "trace 優先度捏造 (必須→でたらめ)"    "$(mut 25 's{<td class="trc-prio">必須</td>}{<td class="trc-prio">でたらめ</td>}')"
expect_fail "trace 段階捏造"                       "$(mut 26 's{<td class="trc-stage">M1</td>}{<td class="trc-stage">M0</td>}')"
expect_fail "trace code 捏造 (可視==href anchor)"  "$(mut 27 's{(<a class="trc-code trc-req" href="clinic-appointment.srs.html#FR1">)FR1(</a>)}{${1}FRX${2}}')"
expect_fail "trace trc-id リンク swap (#rm-RM1→#rm-RM9)" "$(mut 28 's{<td class="trc-id"><a href="#rm-RM1">RM1</a>}{<td class="trc-id"><a href="#rm-RM9">RM1</a>}')"

# --- ★静的 chrome ラベル ---
expect_fail "band h2 見出し捏造"                  "$(mut 29 's{近い段階から順に、 何をどの優先度で目指す}{でたらめな見出しにする}')"
expect_fail "rm-ref-k swap (方向→要件)"           "$(mut 30 's{(<div class="rm-ref-row dir"><span class="rm-ref-k">)方向}{${1}要件}')"
expect_fail "rm-prio-label 捏造 (未知 priority label)" "$(mut 31 's{<span class="rm-prio-label">必須</span>}{<span class="rm-prio-label">でっちあげ</span>}')"
expect_fail "trace thead 列ヘッダ捏造"            "$(mut 32 's{<th>優先度</th>}{<th>FAKE列</th>}')"
expect_fail "trace phantom 行注入 (承認詐称)"     "$(mut 33 's{(<tr data-component="trace-row"><td class="trc-id"><a href="#rm-RM2">)}{<tr><td class="trc-id">偽</td><td class="trc-stage">M9</td><td class="trc-prio">承認</td><td class="trc-ref">全件承認済み</td></tr>${1}}')"
expect_fail "trace tfoot 注入 (承認詐称)"         "$(mut 34 's{(</table>)}{<tfoot><tr><td>承認済みとみなす</td></tr></tfoot>${1}}')"

# --- ★cross-doc 可視 echo / cover-meta / core chrome / term-inline / prose ---
expect_fail "cover ref-chip vision_doc_id 捏造"   "$(mut 35 's{(data-component="cross-doc-ref-chip">.*?<b>)VISION-CLINIC-APPT(</b>)}{${1}FAKE-VISION${2}}s')"
expect_fail "cover-meta 収録捏造"                 "$(mut 36 's{(<span class="k">収録</span><span class="v">)[^<]+}{${1}999 段階}')"
expect_fail "cover-meta 期間捏造 (収録との分離確認)" "$(mut 37 's{(<span class="k">期間</span><span class="v">)[^<]+}{${1}2099 Q9 – 2100 Q1}')"
expect_fail "approval who 捏造 (core-chrome)"      "$(mut 38 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"          "$(mut 39 's{data-term="満枠">空きなし}{data-term="GHOST">空きなし}')"
expect_fail "prose 注入改竄 (注入忠実)"           "$(mut 40 's{(data-slot-id="plain-RM1">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                        "$(mut 41 's{(data-slot-id="plain-RM1">)[^<]+(</p>)}{${1}${2}}')"
expect_fail "highlight prose 注入改竄"            "$(mut 42 's{(data-slot-id="nearest-highlight">)[^<]+}{${1}改竄ハイライト}')"

# --- ★双子属性 per-edge 等値 (valid-pair relocation・anchor 温存で集合一致を素通りする shape・ceiling 8ptq 実証) ---
expect_fail "★ラベル双子属性 relocation (item: anchor F-1 温存・label を F-2 valid-pair へ)" "$(mut 43 's{<span class="rm-ref-label" data-vision-label-ref="F-1">枠の確定を仕組みで守る</span>}{<span class="rm-ref-label" data-vision-label-ref="F-2">決めた診療時間の外では受けない</span>}')"
expect_fail "★ラベル双子属性 relocation (trace: 同 shape)" "$(mut 44 's{<span class="trc-label" data-vision-label-ref="F-1">枠の確定を仕組みで守る</span>}{<span class="trc-label" data-vision-label-ref="F-2">決めた診療時間の外では受けない</span>}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi

echo ""
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" roadmap "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
