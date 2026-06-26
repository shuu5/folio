#!/usr/bin/env bash
# test-adversarial-arch.sh — architecture-description-pack floor の敵対検査 (verify-arch.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-arch.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (worker brief・floor 三本柱): ① 照会グラフ (偽 FR/ADR・role 偽装・count・per-card 入替・SRS ラベル捏造) /
#   ② navigable id アンカー (削除/改名) / ③ 固定章 + 必須要素 (件数) / 横展開 (CJK 空白規律) / 図 (mermaid/caption) /
#   可視テキスト捏造 / cross-doc 可視 echo / core chrome / prose 注入 / floor 単独 GREEN 禁止 を *全捕捉*。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-arch.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-architecture.arch.yaml"
MANIFEST="$HERE/prose/clinic-architecture.arch.prose.yaml"
ASSEMBLE="$HERE/assemble-arch.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-arch.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
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
# expect_warn <label> <mutated.html> — 横展開の advisory WARN モダリティ (実装HOWリーク) が *発火し* かつ floor を割らない
#   (exit 0) ことを確認する positive test。 block 系 (expect_fail) と対称: denylist 語の混入で WARN が出ない/scan が no-op
#   化する回帰を捕捉する (WARN は exit 0 ゆえ expect_fail では検出できない = cell-quality minor 是正)。
expect_warn() {
  local label="$1" html="$2" out ec
  total=$((total+1))
  out="$("$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" 2>&1)"; ec=$?
  if [[ "$ec" -eq 0 ]] && printf '%s' "$out" | grep -q '実装HOWリーク'; then
    echo "  [OK]   $label — WARN 発火 + floor 非破壊 (advisory exit 0)"; pass=$((pass+1))
  else
    echo "  [SLIP] $label — WARN 不発 or exit 非0 (ec=$ec・HOWリーク scan が no-op 化した回帰)"
  fi
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- ③ 固定章 + 必須要素 (件数) ---
expect_fail "decision-card マーカー削除 (件数)"  "$(mut 1 's{<div data-component="arch-decision-card" id="ad-AD-1">}{<div data-component="arch-decision-XXX" id="ad-AD-1">}')"
expect_fail "component-row マーカー削除 (件数)"  "$(mut 2 's{<tr data-component="component-row" id="comp-web-front">}{<tr data-component="component-XXX" id="comp-web-front">}')"
expect_fail "chapter-deck-band 削除 (8 章崩れ)"  "$(mut 3 's{data-component="chapter-deck-band" class="tint-warn"}{data-component="chapter-XXX" class="tint-warn"}')"
expect_fail "mermaid pre 削除 (図 件数)"         "$(mut 4 's{<pre class="mermaid">flowchart TB}{<pre class="XXX">flowchart TB}')"

# --- ② navigable id アンカー (削除/改名) ---
expect_fail "decision anchor 改名 (ad-AD-1→ad-FAKE)" "$(mut 5 's{id="ad-AD-1"}{id="ad-FAKE"}')"
expect_fail "component anchor 削除"                   "$(mut 6 's{ id="comp-slot-store"}{}')"
expect_fail "quality anchor 改名"                     "$(mut 7 's{id="qa-QA-1"}{id="qa-XXX"}')"
expect_fail "principle terminal anchor 改名"          "$(mut 8 's{id="principle-PRIN-SAFETY-FIRST"}{id="principle-FAKE"}')"

# --- ① 照会グラフ (cross-doc 前方照会の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 10 's{data-arch-ref="FR2" data-arch-role="claim"}{data-arch-ref="FR99" data-arch-role="claim"}')"
expect_fail "SRS role 意味偽装 (claim→rationale)"     "$(mut 11 's{data-arch-ref="FR2" data-arch-role="claim"}{data-arch-ref="FR2" data-arch-role="rationale"}')"
expect_fail "SRS ref 削除 (count mismatch)"            "$(mut 12 's{<a class="xref-link" href="../clinic-appointment.srs.html#FR2" data-arch-ref="FR2" data-arch-role="claim"><span class="xref-code">FR2</span><span class="xref-label" data-srs-label-ref="FR2">予約受付</span></a>}{}')"
expect_fail "偽 ADR 参照 (dangling・別 doc_id)"        "$(mut 13 's{data-adr-ref="ADR-CLINIC-0001" data-adr-role="rationale"}{data-adr-ref="ADR-CLINIC-9999" data-adr-role="rationale"}')"
expect_fail "ADR role 偽装 (rationale→claim)"          "$(mut 14 's{data-adr-ref="ADR-CLINIC-0001" data-adr-role="rationale"}{data-adr-ref="ADR-CLINIC-0001" data-adr-role="claim"}')"
expect_fail "principle ref 改竄 (別原則)"              "$(mut 15 's{data-principle-ref="PRIN-SAFETY-FIRST"}{data-principle-ref="PRIN-FAKE"}')"
# per-card 入替 (FR2↔FR4 を AD-1↔AD-2・global set/count 不変ゆえ 1d のみ捕捉)
expect_fail "card 間 FR 入替 (AD-1↔AD-2)" "$(mut 16 's{(id="ad-AD-1">.*?)data-arch-ref="FR2" data-arch-role="claim">(<span class="xref-code">)FR2(</span><span class="xref-label" data-srs-label-ref=")FR2(">)予約受付}{${1}data-arch-ref="FR4" data-arch-role="claim">${2}FR4${3}FR4${4}枠外拒否}s; s{(id="ad-AD-2">.*?)data-arch-ref="FR4" data-arch-role="claim">(<span class="xref-code">)FR4(</span><span class="xref-label" data-srs-label-ref=")FR4(">)枠外拒否}{${1}data-arch-ref="FR2" data-arch-role="claim">${2}FR2${3}FR2${4}予約受付}s')"

# --- SRS 機能名ラベル fidelity (persona ceiling 是正) ---
expect_fail "SRS ラベル捏造 (非 SRS 由来)"   "$(mut 17 's{<span class="xref-label" data-srs-label-ref="FR2">予約受付}{<span class="xref-label" data-srs-label-ref="FR2">でたらめ機能}')"
expect_fail "SRS ラベル swap (FR2 に FR3 ラベル)" "$(mut 18 's{<span class="xref-label" data-srs-label-ref="FR2">予約受付}{<span class="xref-label" data-srs-label-ref="FR2">競合拒否}')"
expect_fail "ADR ラベル捏造 (非 adr_title)" "$(mut 19 's{(<span class="xref-label" data-adr-label-ref="ADR-CLINIC-0001">)[^<]+}{${1}捏造ADRタイトル}')"

# --- ★可視 xref-code 単独改竄 (照会の正準コード・属性 intact のまま可視だけ捏造・folio-5uu self-review fail-open 封鎖) ---
expect_fail "可視 xref-code SRS 捏造 (FR2→FR99・data-arch-ref intact)"        "$(mut 45 's{<span class="xref-code">FR2</span>}{<span class="xref-code">FR99</span>}')"
expect_fail "可視 xref-code ADR 捏造 (0001→9999・data-adr-ref intact)"        "$(mut 46 's{<span class="xref-code">ADR-CLINIC-0001</span>}{<span class="xref-code">ADR-CLINIC-9999</span>}')"
expect_fail "可視 xref-code 原則 捏造 (PRIN偽装・data-principle-ref intact)"  "$(mut 47 's{<span class="xref-code">PRIN-SAFETY-FIRST</span>}{<span class="xref-code">PRIN-TOTALLY-FAKE</span>}')"

# --- ★href 遷移先 改竄 (属性+可視コード/ラベル intact のまま 飛び先だけ swap・folio-5uu self-review fail-open 封鎖) ---
expect_fail "href SRS anchor swap (#FR2→#FR99・data-arch-ref=FR2 intact)"           "$(mut 52 's{href="../clinic-appointment.srs.html#FR2"}{href="../clinic-appointment.srs.html#FR99"}')"
expect_fail "href filename 外部host注入 (SRS→https://evil.example・属性 intact)"     "$(mut 53 's{href="../clinic-appointment.srs.html#FR3"}{href="https://evil.example#FR3"}')"
expect_fail "href 原則 within-doc デッドリンク (#principle-PRIN…→#principle-FAKE)"   "$(mut 54 's{href="#principle-PRIN-SAFETY-FIRST"}{href="#principle-FAKE"}')"
expect_fail "href quality anchor swap (#AC1→#AC99・data-quality-srs-ref=AC1 intact)" "$(mut 55 's{href="../clinic-appointment.srs.html#AC1"}{href="../clinic-appointment.srs.html#AC99"}')"

# --- cross-doc 可視 echo (表紙 ref-chip) ---
expect_fail "ref-chip srs_doc_id 捏造" "$(mut 20 's{(data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"
expect_fail "ref-chip adr_doc_id 捏造" "$(mut 21 's{(data-component="cross-doc-ref-chip">.*?の要件 / <b>)ADR-CLINIC-0001(</b>)}{${1}FAKE-ADR${2}}s')"

# --- 可視テキスト fidelity (属性 intact のまま可視だけ捏造) ---
expect_fail "decision title 捏造"   "$(mut 22 's{(<h3 class="ad-title">)[^<]+}{${1}捏造タイトル}')"
expect_fail "decision summary 捏造手順" "$(mut 23 's{残数が 1 以上のときだけ 1 減らす}{残数が 99 以上のときだけ減らす}')"
expect_fail "component name 捏造"   "$(mut 24 's{<span class="cn">予約UI}{<span class="cn">捏造部品}')"
expect_fail "strategy plain 捏造"   "$(mut 25 's{二重予約は「注意」でなく仕組みで防ぐ}{二重予約は注意でなんとか防ぐ}')"
expect_fail "quality target 捏造"   "$(mut 26 's{二重予約 0 件 \(最優先\)}{二重予約 99 件まで許容}')"
expect_fail "quality srs_ref 捏造 (AC1→AC9)" "$(mut 27 's{data-quality-srs-ref="AC1">AC1}{data-quality-srs-ref="AC1">AC9}')"
expect_fail "risk severity class 改竄 (high→mid)" "$(mut 28 's{<span class="rk-sev high">高}{<span class="rk-sev mid">高}')"
expect_fail "actor name 捏造"       "$(mut 29 's{<span class="nm">患者<span class="akind}{<span class="nm">捏造アクター<span class="akind}')"
expect_fail "context problem 捏造"  "$(mut 30 's{一番こわいのは同じ時間に 2 人を入れてしまう事故}{一番こわいのは特に何もない}')"

# --- 可視 kind / runtime flow name / strategy id fidelity (folio-5uu self-review: actor kind / rt-name / st-id / component kind 反転の取りこぼし封鎖) ---
expect_fail "actor kind 反転 (患者 internal→external)"  "$(mut 41 's{<span class="nm">患者<span class="akind internal">内部</span>}{<span class="nm">患者<span class="akind external">外部</span>}')"
expect_fail "component kind 反転 (予約UI core→external)" "$(mut 42 's{<span class="cn">予約UI</span><br><span class="ckind core">中核</span>}{<span class="cn">予約UI</span><br><span class="ckind external">外部連携</span>}')"
expect_fail "runtime flow name 捏造 (rt-name)"           "$(mut 43 's{<p class="rt-name">同時申込の二重予約防止</p>}{<p class="rt-name">でたらめな流れ</p>}')"
expect_fail "strategy id 改竄 (S1→S9)"                   "$(mut 44 's{<span class="st-id">S1</span>}{<span class="st-id">S9</span>}')"

# --- ★可視 識別子バッジ (ad-id/qa-id/rk-id) / risk severity 可視ラベル 単独改竄 (anchor id・class intact・folio-5uu self-review fail-open 封鎖) ---
expect_fail "可視 ad-id 捏造 (AD-1→AD-99・anchor id=ad-AD-1 intact)" "$(mut 48 's{<span class="ad-id">AD-1</span>}{<span class="ad-id">AD-99</span>}')"
expect_fail "可視 qa-id 捏造 (QA-1→QA-99・anchor id=qa-QA-1 intact)" "$(mut 49 's{<span class="qa-id">QA-1</span>}{<span class="qa-id">QA-99</span>}')"
expect_fail "可視 rk-id 捏造 (R-1→R-99・anchor id=risk-R-1 intact)"  "$(mut 50 's{<span class="rk-id">R-1</span>}{<span class="rk-id">R-99</span>}')"
expect_fail "可視 risk severity ラベル単独改竄 (高→中・class=high intact)" "$(mut 51 's{<span class="rk-sev high">高</span>}{<span class="rk-sev high">中</span>}')"

# --- 図 (mermaid DSL + figcaption) ---
expect_fail "mermaid DSL 改竄 (図 内容捏造)" "$(mut 31 's{(<pre class="mermaid">flowchart TB\n  patient\[&quot;)患者}{${1}捏造ノード}')"
expect_fail "figcaption 改竄"                "$(mut 32 's{図 1 \(C4 — System Context 図\)}{でたらめな図の説明}')"
expect_fail "diag-tag 改竄"                  "$(mut 33 's{<span class="diag-tag">C4 — System Context</span>}{<span class="diag-tag">FAKE-TAG</span>}')"

# --- 横展開: CJK inline 強調の空白規律 ---
expect_fail "CJK 隣接の <b> 前空白 注入"   "$(mut 34 's{<p class="ad-summary">確定の瞬間に}{<p class="ad-summary">確定の瞬間 <b>に</b>}')"
expect_fail "CJK 隣接の term バッジ前空白" "$(mut 35 's{<span class="term" data-component="plain-language-term-inline" data-term="ダブルブッキング">}{ <span class="term" data-component="plain-language-term-inline" data-term="ダブルブッキング">}')"

# --- cover-meta / core chrome / term-inline ---
expect_fail "cover-meta 構成 捏造"           "$(mut 36 's{(<span class="k">構成</span><span class="v">)[^<]+}{${1}捏造構成}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 37 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"      "$(mut 38 's{data-term="ダブルブッキング">二重予約}{data-term="GHOST">二重予約}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 39 's{(data-slot-id="plain-AD-1">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 40 's{(data-slot-id="cover-summary">)[^<]+(</p>)}{${1}${2}}')"

# --- ★横展開 (a) 実装HOWリーク = positive WARN test (denylist 語注入で WARN が発火し floor は割れない・mut45-55 の block 系と対称) ---
expect_warn "実装HOWリーク WARN 発火 (PostgreSQL/Redis 注入・advisory exit 0)" "$(mut 60 's{</body>}{<!-- impl note: PostgreSQL + Redis -->\n</body>}')"

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
