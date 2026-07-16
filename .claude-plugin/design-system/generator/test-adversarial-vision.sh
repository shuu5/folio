#!/usr/bin/env bash
# test-adversarial-vision.sh — vision-pack floor の敵対検査 (verify-vision.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-vision.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (floor 三本柱): ① 照会グラフ (偽 FR・role 偽装・count・per-feature 入替・SRS ラベル捏造・href swap) /
#   ② navigable id アンカー (削除/改名) / ③ 固定章 + 必須要素 (件数・genuine-shape decoy) / 横展開 (CJK 空白規律) /
#   図 (goal-tree mermaid・optional) / 可視テキスト捏造 / cross-doc 可視 echo / core chrome / prose 注入 /
#   opt-in (pitch/goal-tree 不在でも PASS) / floor 単独 GREEN 禁止 を *全捕捉*。
# ★vision は band 見出しに件数/ドメインを持たない (全 pack 不変) ゆえ arch の band_numchk (数詞 fabrication) 系は N/A。
#   genuine-shape 構造不変条件 (要素単位・ci・attribute-tolerant) の decoy 封鎖のみ課す。
#
# usage: test-adversarial-vision.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-appointment.vision.yaml"
MANIFEST="$HERE/prose/clinic-appointment.vision.prose.yaml"
ASSEMBLE="$HERE/assemble-vision.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-vision.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm (verify_repro_build・folio-3d23) は verify-*.sh 既定 ON。 bulk case は honest skip で 10 分/suite を維持し
# (arm 未 skip は assemble 再 build で timeout)、 conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
export SKIP_REPRO="${SKIP_REPRO:-1}"
# gate F (playwright visual・folio-vuf A) も floor-adversarial では skip (重い render を外す・SKIP_REPRO と同型)。
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

# expect_abort <label> <contract.yaml> [expected_stderr_substring] — assemble 段の contract fail-closed。
expect_abort() {
  local label="$1" c="$2" want="${3:-}" out rc
  total=$((total+1))
  out="$("$ASSEMBLE" "$c" 2>&1 >/dev/null)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  [SLIP] $label — assemble が abort せず生成した (exit 0)"
  elif [[ -n "$want" && "$out" != *"$want"* ]]; then
    echo "  [SLIP] $label — abort したが理由が想定外 (期待 '$want' / 実: $(printf '%s' "$out" | tail -1))"
  else
    echo "  [OK]   $label — 生成前 abort"; pass=$((pass+1))
  fi
}
# vision_base <dst.yaml> — contract を TMP へコピーし、 cross_doc が相対参照する SRS contract も同じ dir へコピーする
#   (assemble-vision のパス解決は CONTRACT_DIR 相対の素朴連結 = 兄弟配置が前提)。 コピー先で参照が巻き添え failure し
#   expect_abort が「mutation 以外の理由」で偽 [OK] 化するのを防ぐ (arch_base 同旨)。 vision は SRS のみ照会 (ADR なし)。
vision_base() {
  local d; d="$(dirname "$1")"
  cp "$CONTRACT" "$1"
  cp "$HERE/contract/clinic-appointment.srs.yaml" "$d/"
}
# expect_pass_variant <label> <mutate-yq-prog> — contract を opt-in 要素で改変 (pitch/goal-tree 削除) しても
#   assemble → inject → verify が PASS することを確認する positive test (必須化しない設計の回帰封鎖・grill 論点5)。
expect_pass_variant() {
  local label="$1" yqprog="$2" c="$TMP/pv.yaml" raw="$TMP/pv-raw.html" out="$TMP/pv.html"
  total=$((total+1))
  vision_base "$c"; yq -i "$yqprog" "$c"
  if "$ASSEMBLE" "$c" > "$raw" 2>/dev/null && "$INJECT" "$MANIFEST" "$raw" "$out" >/dev/null 2>&1 \
     && "$VERIFY" --artifact "$c" "$out" >/dev/null 2>&1; then
    echo "  [OK]   $label — opt-in 要素なしでも PASS"; pass=$((pass+1))
  else
    echo "  [SLIP] $label — opt-in 要素なしで FAIL (必須化されている回帰)"
  fi
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi
# baseline sanity: vision_base コピー (無改竄) は assemble を通過すべき
total=$((total+1))
vision_base "$TMP/base-sanity.yaml"
if "$ASSEMBLE" "$TMP/base-sanity.yaml" >/dev/null 2>&1; then
  echo "  [OK]   baseline vision_base コピーは assemble PASS"; pass=$((pass+1))
else echo "  [SLIP] vision_base コピーが assemble FAIL (helper 前提崩壊)"; fi

# --- ③ 固定章 + 必須要素 (件数) ---
expect_fail "V01 vision-north-star マーカー削除"     "$(mut 1 's{<div data-component="vision-north-star" id="northstar">}{<div data-component="vision-XXX" id="northstar">}')"
expect_fail "V02 chapter-deck-band 削除 (7 章崩れ)"  "$(mut 2 's{data-component="chapter-deck-band" class="tint-warn"}{data-component="chapter-XXX" class="tint-warn"}')"
expect_fail "V03 goal-tree-diagram マーカー削除"     "$(mut 3 's{data-component="goal-tree-diagram"}{data-component="goal-XXX"}')"
expect_fail "V04 feature card マーカー削除 (件数)"    "$(mut 4 's{<div class="vm-feat" id="f-1">}{<div class="vm-XXX" id="f-1">}')"
expect_fail "V05 stakeholder card 削除 (件数)"        "$(mut 5 's{<div class="vm-card" id="st-3">}{<div class="vm-XXX" id="st-3">}')"
expect_fail "V06 no-restate aside 削除 (3→2)"         "$(mut 6 's{<aside data-component="no-restate-note">この章は}{<aside data-component="no-XXX">この章は}')"

# --- ③ genuine-shape 不変条件 (要素単位・ci・attribute-tolerant の decoy 封鎖・folio-bhe ceiling wf_6166a844 同型) ---
expect_fail "V07 ★属性付き decoy <h2 class> を band 内注入 (attribute-tolerant + NH2≠7 で封鎖)" "$(mut 7 's{(<h2>なぜ、 いま作るのか</h2>)}{$1<h2 class="decoy">偽の見出しを注入</h2>}')"
expect_fail "V08 ★大文字 <SECTION>/<H2> で捏造 8 章目 (case-insensitive count で封鎖)" "$(mut 8 's{(<section data-component="chapter-deck-band" class="tint-info")}{<SECTION data-component="chapter-deck-band" class="tint-brand"><span class="num">08</span><span class="kicker">FAKE</span><H2>捏造8章</H2></SECTION>$1}')"
expect_fail "V09 ★band 範囲外の bare <h2> (全 <h2>==7 不変条件で封鎖)" "$(mut 9 's{(<div class="chapbody">)}{$1<h2>範囲外の捏造見出し</h2>}')"
expect_fail "V10 ★band h2 pack 固定文言の改竄 (問題→速度)" "$(mut 10 's{<h2>なぜ、 いま作るのか</h2>}{<h2>なぜ、 いま速くするのか</h2>}')"

# --- ② navigable id アンカー (削除/改名) ---
expect_fail "V11 stakeholder anchor 改名 (st-1→st-FAKE)" "$(mut 11 's{id="st-1"}{id="st-FAKE"}')"
expect_fail "V12 feature anchor 削除"                     "$(mut 12 's{ id="f-2"}{}')"
expect_fail "V13 objective anchor 改名 (g-1→g-XXX)"       "$(mut 13 's{id="g-1"}{id="g-XXX"}')"
expect_fail "V14 principle 終端 anchor 改名"              "$(mut 14 's{id="principle-PRIN-PATIENT-TRUST"}{id="principle-FAKE"}')"
expect_fail "V15 章 anchor northstar 改名"                "$(mut 15 's{id="northstar"}{id="north-XXX"}')"
expect_fail "V16 章 anchor problem 削除"                  "$(mut 16 's{<p id="problem">}{<p>}')"

# --- ① 照会グラフ (cross-doc 前方照会の核・SRS 充足照会) ---
expect_fail "V17 偽 FR 参照 (dangling・SRS に無い FR99)"  "$(mut 17 's{data-vision-ref="FR2" data-vision-role="claim"}{data-vision-ref="FR99" data-vision-role="claim"}')"
expect_fail "V18 SRS role 意味偽装 (claim→rationale)"     "$(mut 18 's{data-vision-ref="FR2" data-vision-role="claim"}{data-vision-ref="FR2" data-vision-role="rationale"}')"
expect_fail "V19 SRS ref 削除 (count mismatch)"           "$(mut 19 's{<a class="xref-link" href="clinic-appointment.srs.html#FR2" data-vision-ref="FR2" data-vision-role="claim"><span class="xref-code">FR2</span><span class="xref-label" data-srs-label-ref="FR2">予約受付</span></a>}{}')"
# per-feature 入替 (FR3↔FR4 を F-1↔F-2・global set/count/(ref,label)/href 不変ゆえ per-feature のみ捕捉)
expect_fail "V20 ★per-feature FR 入替 (F-1↔F-2・global 不変)" "$(mut 20 's{<a class="xref-link" href="clinic-appointment.srs.html#FR3" data-vision-ref="FR3".*?</a>}{@@F3@@}s; s{<a class="xref-link" href="clinic-appointment.srs.html#FR4" data-vision-ref="FR4".*?</a>}{<a class="xref-link" href="clinic-appointment.srs.html#FR3" data-vision-ref="FR3" data-vision-role="claim"><span class="xref-code">FR3</span><span class="xref-label" data-srs-label-ref="FR3">競合拒否</span></a>}s; s{\@\@F3\@\@}{<a class="xref-link" href="clinic-appointment.srs.html#FR4" data-vision-ref="FR4" data-vision-role="claim"><span class="xref-code">FR4</span><span class="xref-label" data-srs-label-ref="FR4">枠外拒否</span></a>}')"

# --- SRS 機能名ラベル fidelity ---
expect_fail "V21 SRS ラベル捏造 (非 SRS 由来)"     "$(mut 21 's{<span class="xref-label" data-srs-label-ref="FR2">予約受付}{<span class="xref-label" data-srs-label-ref="FR2">でたらめ機能}')"
expect_fail "V22 SRS ラベル swap (FR2 に FR3 ラベル)" "$(mut 22 's{<span class="xref-label" data-srs-label-ref="FR2">予約受付}{<span class="xref-label" data-srs-label-ref="FR2">競合拒否}')"

# --- ★可視 xref-code 単独改竄 (属性 intact のまま可視だけ捏造) + href 遷移先改竄 ---
expect_fail "V23 可視 xref-code SRS 捏造 (FR1→FR99・data-vision-ref intact)" "$(mut 23 's{<span class="xref-code">FR1</span>}{<span class="xref-code">FR99</span>}')"
expect_fail "V24 href SRS anchor swap (#FR1→#FR99・data-vision-ref=FR1 intact)" "$(mut 24 's{href="clinic-appointment.srs.html#FR1" data-vision-ref="FR1"}{href="clinic-appointment.srs.html#FR99" data-vision-ref="FR1"}')"
expect_fail "V25 href 外部host注入 (SRS→https://evil・属性 intact)" "$(mut 25 's{href="clinic-appointment.srs.html#FR4" data-vision-ref="FR4"}{href="https://evil.example#FR4" data-vision-ref="FR4"}')"

# --- cross-doc 可視 echo (表紙 ref-chip・1 <b> = SRS) ---
expect_fail "V26 ref-chip srs_doc_id 捏造" "$(mut 26 's{(data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"

# --- 可視テキスト fidelity (属性 intact のまま可視だけ捏造) ---
expect_fail "V27 north-star text 捏造"        "$(mut 27 's{<p class="vm-ns-text">予約が「ちゃんと取れている」}{<p class="vm-ns-text">予約はだいたい取れている}')"
expect_fail "V28 north-star narrative 捏造"    "$(mut 28 's{いまは、 予約が取れているはずなのに}{いまは、 何も問題が起きていないが}')"
expect_fail "V29 stakeholder name (vm-ct) 捏造" "$(mut 29 's{<span class="vm-ct">受付スタッフ</span>}{<span class="vm-ct">捏造の立場</span>}')"
expect_fail "V30 objective desc (vm-cd) 捏造"   "$(mut 30 's{二重予約が「注意していたのに起きた」ではなく}{二重予約は起きても構わないが}')"
expect_fail "V31 sc for_goal 捏造 (G-1→G-9)"    "$(mut 31 's{<span class="vm-sc-for">→ G-1 の物差し</span>}{<span class="vm-sc-for">→ G-9 の物差し</span>}')"
expect_fail "V32 feature name 捏造"            "$(mut 32 's{<span class="vm-ct">枠の確定を仕組みで守る</span>}{<span class="vm-ct">でたらめ機能</span>}')"
expect_fail "V33 risk desc 捏造"               "$(mut 33 's{操作が受付の実際の手の動きに合わないと}{操作は完璧なので問題ないが}')"
expect_fail "V34 non-goals text 捏造"          "$(mut 34 's{診察内容・カルテの記録、 会計・診療報酬の請求}{カルテも会計も全部作ります}')"
expect_fail "V35 principle text 捏造"          "$(mut 35 's{<p class="pt-text">患者との約束 \(予約\) を守ることを}{<p class="pt-text">開発の速さを何より優先することを}')"
expect_fail "V36 principle narrative 捏造"      "$(mut 36 's{これは北極星の言い換えではなく、 判断の規則です}{これは単なる北極星の言い換えです}')"
expect_fail "V37 可視 vm-cid 捏造 (ST-1→ST-99)"  "$(mut 37 's{<span class="vm-cid">ST-1</span>}{<span class="vm-cid">ST-99</span>}')"
expect_fail "V38 pitch value 捏造"             "$(mut 38 's{<span class="vm-pg-v">診療予約の受付システム</span>}{<span class="vm-pg-v">なんでも屋システム</span>}')"
expect_fail "V39 no-restate 本文 捏造"          "$(mut 39 's{この章は「なぜ解くに値するか」だけを述べています}{この章では上位ニーズを全部書きます}')"

# --- 目標ツリー図 (optional) fidelity ---
expect_fail "V40 goal-tree mermaid DSL 改竄"   "$(mut 40 's{G-1 取り合いのない予約}{G-1 捏造された目標}')"
expect_fail "V41 goal-tree figcaption 改竄"    "$(mut 41 's{<span class="diag-tag">目標ツリー</span>図 1}{<span class="diag-tag">目標ツリー</span>でたらめ図}')"

# --- 横展開: CJK inline 強調の空白規律 ---
expect_fail "V42 CJK 隣接の <b> 前空白 注入"   "$(mut 42 's{<p class="vm-ns-text">予約が}{<p class="vm-ns-text">予約 <b>が</b>}')"

# --- cover-meta / core chrome / prose ---
expect_fail "V43 cover-meta 構成 捏造"          "$(mut 43 's{(<span class="k">構成</span><span class="v">)[^<]+}{${1}捏造構成}')"
expect_fail "V44 approval who 捏造 (core-chrome)" "$(mut 44 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "V45 cover-eyebrow 捏造 (core-chrome)" "$(mut 45 's{<span class="doc-type">folio design-system / vision</span>}{<span class="doc-type">捏造ラベル</span>}')"
expect_fail "V46 prose 注入改竄 (注入忠実)"     "$(mut 46 's{(data-slot-id="chapter-lead-01">)[^<]+}{${1}改竄プローズ}')"
expect_fail "V47 prose 未充填"                  "$(mut 47 's{(data-slot-id="cover-summary">)[^<]+(</p>)}{${1}${2}}')"

# --- contract-side abort (assemble fail-closed) ---
vision_base "$TMP/a1.yaml"; yq -i '.doc_type = "wrong"' "$TMP/a1.yaml"
expect_abort "V48 ★doc_type 誤りを生成前 abort" "$TMP/a1.yaml" "doc_type が vision でない"
vision_base "$TMP/a2.yaml"; yq -i '.features[0].refs.srs[0] = "FR99"' "$TMP/a2.yaml"
expect_abort "V49 ★偽 FR 参照 (SRS に無い FR99) を dangling で abort" "$TMP/a2.yaml" "SRS 照会の dangling"
vision_base "$TMP/a3.yaml"; yq -i '.success_criteria.entries[0].for_goal = "G-9"' "$TMP/a3.yaml"
expect_abort "V50 ★sc.for_goal dangling (G-9) を abort" "$TMP/a3.yaml" "success_criteria.for_goal の dangling"
vision_base "$TMP/a4.yaml"; yq -i '.pitch.rows[0].ref_anchor = "nonexistent-anchor"' "$TMP/a4.yaml"
expect_abort "V51 ★pitch.ref_anchor dangling 内部照会を abort" "$TMP/a4.yaml" "pitch.ref_anchor の dangling"
vision_base "$TMP/a5.yaml"; yq -i '.stakeholders.entries[1].id = "ST-1"' "$TMP/a5.yaml"
expect_abort "V52 ★stakeholder id 重複を abort" "$TMP/a5.yaml" "id 重複"
vision_base "$TMP/a6.yaml"; yq -i 'del(.principle.id)' "$TMP/a6.yaml"
expect_abort "V53 ★principle.id 欠落 (照会 graph 終端不備) を abort" "$TMP/a6.yaml" "principle.id 欠落"

# --- opt-in positive (pitch/goal-tree 不在でも PASS = 必須化しない設計の回帰封鎖・grill 論点5) ---
expect_pass_variant "V54 ★pitch 削除でも PASS (Moore pitch は opt-in)"    'del(.pitch)'
expect_pass_variant "V55 ★goal-tree 削除でも PASS (目標ツリー図は optional)" 'del(.goal_tree)'

# --- ★aside/pitch 照会 fidelity (ceiling wf_64344fbe 是正・兄弟は検査済だが label/href/ref_label が非対称に欠けていた穴) ---
expect_fail "V56 ★non-goals xref-label 捏造 (兄弟 code intact・green-flip repro)" "$(mut 56 's{<span class="xref-label">範囲 \(SRS-CLINIC-APPT\)</span>}{<span class="xref-label">悪意ある捏造ラベル (WRONG)</span>}')"
expect_fail "V57 ★success_criteria aside href swap (#AC1→#WRONG・属性外)" "$(mut 57 's{href="clinic-appointment.srs.html#AC1"}{href="clinic-appointment.srs.html#WRONG"}')"
expect_fail "V58 ★pitch ref_label 捏造 (兄弟 key/value/href intact)" "$(mut 58 's{↔ §3 関係者</a>}{↔ 捏造ラベル</a>}')"
expect_fail "V59 ★data-doc-id 捏造 (自文書 doc_id)" "$(mut 59 's{data-doc-id="VISION-CLINIC-APPT"}{data-doc-id="FAKE-DOC"}')"
# V60 ★cross-aside chip 並べ替え (集合保存・本文↔chip 帰属 desync・再cert 発見の自 fix 回帰 pin): problem chip(§3上位ニーズ)
#   ↔ stakeholders chip(§2アクター定義) を入替。 chip 集合は不変ゆえ sorted set なら素通るが positional で帰属崩れを捕捉。
expect_fail "V60 ★cross-aside chip 並べ替え (集合保存・§2問題章がアクター定義を誤引用)" "$(mut 60 's{<span class="xref-code">SRS §3</span><span class="xref-label">上位ニーズ N-1〜N-4 \(SRS-CLINIC-APPT\)</span>}{ZZAZZ}; s{<span class="xref-code">SRS §2</span><span class="xref-label">アクター定義 \(SRS-CLINIC-APPT\)</span>}{<span class="xref-code">SRS §3</span><span class="xref-label">上位ニーズ N-1〜N-4 (SRS-CLINIC-APPT)</span>}; s{ZZAZZ}{<span class="xref-code">SRS §2</span><span class="xref-label">アクター定義 (SRS-CLINIC-APPT)</span>}')"
# V61 ★footer provenance red pin (folio-r8k inline 経路): vision は verify_core_chrome を呼ばず inline で
#   verify_footer_provenance を呼ぶ第 2 構造クラス。 引用符内 > を含む split タグ (<b t="a>z">) で機械SSoT/検証状態
#   token を分割した偽 provenance div を footer へ注入。 naive [^>]* strip は quote 内 > で誤終端し素通り、
#   quote-aware projection のみが token=2 で FAIL。 per-shape MK: core caller (datamodel) が通っても inline 経路の
#   穴は別クラスゆえ本 pin が必要 (jyfh per-shape 教訓)。
expect_fail "V61 ★footer 偽 provenance (quote-embedded > tag-split・inline 経路)" "$(mut 61 's{</footer>}{<div data-audience="machine">\xe6\xa9\x9f\xe6\xa2\xb0<b t="a>z">SSoT: <b>evil.vision.yaml</b> &middot; \xe7\x94\x9f\xe6\x88\x90: <b>2026-01-01 00:00</b> &middot; \xe6\xa4\x9c\xe8\xa8\xbc<b t="c>z">\xe7\x8a\xb6\xe6\x85\x8b: <b>\xe5\x85\xac\xe5\xbc\x8f\xe6\x89\xbf\xe8\xaa\x8d</b></div></footer>}')"

# --- ★cross_doc opt-in 非発火 (folio-qvv 裁定A): 非発火 baseline + 痕跡ゼロ不変条件 + 片肺 contract abort ---
# 非発火 contract = clinic から cross_doc/no_restate/srs_* を全て畳み refs.srs を空配列化した派生 (folio-self と同形)。
NFC="$TMP/nf.yaml"
vision_base "$NFC"
yq -i 'del(.cross_doc) | del(.problem.no_restate) | del(.stakeholders.no_restate) | del(.success_criteria.no_restate) | del(.non_goals.srs_code) | del(.non_goals.srs_label) | (.features[].refs.srs) = []' "$NFC"
NFRAW="$TMP/nf-raw.html"; NFGOOD="$TMP/nf-good.html"
total=$((total+1))
if "$ASSEMBLE" "$NFC" > "$NFRAW" 2>/dev/null && "$INJECT" "$MANIFEST" "$NFRAW" "$NFGOOD" >/dev/null 2>&1 \
   && "$VERIFY" --artifact "$NFC" "$NFGOOD" >/dev/null 2>&1; then
  echo "  [OK]   V61 ★非発火 baseline (cross_doc なし) assemble→inject→verify PASS"; pass=$((pass+1))
else
  echo "  [SLIP] V61 非発火 baseline が FAIL (opt-in 化の回帰)"; fi
mutnf() { local n="$1" prog="$2"; local m="$TMP/nf-m$n.html"; perl -0777 -pe "$prog" "$NFGOOD" > "$m"; printf '%s' "$m"; }
expect_fail_nf() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --artifact "$NFC" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
expect_fail_nf "V62 ★非発火に no-restate aside 注入 (偽照会)" "$(mutnf 62 's{(<p id="problem">)}{<aside data-component="no-restate-note">捏造照会 <a class="xref-link" href="fake.html"><span class="xref-code">SRS §9</span><span class="xref-label">捏造先</span></a></aside>$1}')"
expect_fail_nf "V63 ★非発火に cross-doc-ref-chip 注入 (偽照会先チップ)" "$(mutnf 63 's{(<div class="reader-chip">)}{<div class="reader-chip" data-component="cross-doc-ref-chip">偽 照会先: <b>FAKE-SRS</b></div>$1}')"
expect_fail_nf "V64 ★非発火に data-vision-ref 照会行注入" "$(mutnf 64 's{(<div class="vm-feat" id="f-1">.*?<p class="vm-cd">[^<]*</p>)}{$1<div class="ad-ref-row claim"><span class="ad-ref-lab">実現する要件</span><a class="xref-link" href="fake.html#FR1" data-vision-ref="FR1" data-vision-role="claim"><span class="xref-code">FR1</span></a></div>}s')"
expect_fail_nf "V65 ★非発火に cover-meta 照会先 KV 注入" "$(mutnf 65 's{(<span class="m"><span class="k">版</span>)}{<span class="m"><span class="k">照会先</span><span class="v">FAKE-SRS</span></span>$1}')"
# 片肺 contract (cross_doc なしで照会データ残存) の assemble abort
cp "$NFC" "$TMP/a7.yaml"; yq -i '.features[0].refs.srs = ["FR1"]' "$TMP/a7.yaml"
expect_abort "V66 ★片肺 contract: cross_doc なしの refs.srs を abort" "$TMP/a7.yaml" "cross_doc 節なしで SRS 照会"
cp "$NFC" "$TMP/a8.yaml"; yq -i '.problem.no_restate = {"text":"x","srs_code":"SRS §3","srs_label":"y"}' "$TMP/a8.yaml"
expect_abort "V67 ★片肺 contract: cross_doc なしの no_restate を abort" "$TMP/a8.yaml" "no_restate が存在"
# instance 出自タグの fail-closed (c5r.3 恒久処方の vision 展開)
vision_base "$TMP/a9.yaml"; yq -i 'del(.footer.instance_tag)' "$TMP/a9.yaml"
expect_abort "V68 ★instance_tag 欠落を abort (虚偽出自の fail-closed)" "$TMP/a9.yaml" "instance_tag 欠落"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
# ★bare token grep にしない (folio-vxpc errata): verify-*.sh の統一 sentinel は「GREEN ではない」と *否定*
#   するために GREEN の語を含む。 bare `grep -q 'GREEN'` はその否定文にも lexical 衝突して恒真 [SLIP] となり、
#   本 suite が exit 1 へ飽和して **他の全 assert が exit-code 判定から不可視になる** (番人喪失 = fail-open)。
#   assert の意図「floor 単独 GREEN 禁止」は不変のまま、 GREEN を *主張* する行の検出へ精密化する (緩和ではない)。
#   精密化が番人を殺していないことは直下 2 本 (捏造の陽性対照 / 否定文の陰性対照) が実弾で pin する。
GREEN_CLAIM='RESULT:[^—]*GREEN|GREEN 認定|全 gate.*GREEN'
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -qE "$GREEN_CLAIM"; then
  echo "  [SLIP] verify が GREEN を主張 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 主張なし・CEILING=PENDING を強制"; pass=$((pass+1)); fi
# 陽性対照: 精密化しても本物の GREEN 捏造は殺せる (殺せないなら精密化でなく番人の喪失)。
total=$((total+1))
if printf '%s' "RESULT: GREEN (全 gate 通過)" | grep -qE "$GREEN_CLAIM"; then
  echo "  [OK]   MK 陽性対照: 本物の 'RESULT: GREEN' 捏造は今も主張パターンで殺せる"; pass=$((pass+1))
else
  echo "  [SLIP] MK 陽性対照 破れ: 主張パターンが 'RESULT: GREEN' 捏造を見逃す (緩和が番人を殺した)"; fi
# 陰性対照: 現行 sentinel の否定文を主張と誤検出しない (誤検出するなら上の番人は恒真 SLIP = 元の衝突の再生産)。
total=$((total+1))
if printf '%s' "RESULT: floor PASS (mode=artifact) — ただし CEILING=PENDING (*GREEN ではない*)" | grep -qE "$GREEN_CLAIM"; then
  echo "  [SLIP] MK 陰性対照 破れ: sentinel の否定文を主張と誤検出 (lexical 衝突の再生産)"
else
  echo "  [OK]   MK 陰性対照: sentinel の「GREEN ではない」否定文は主張と誤検出されない"; pass=$((pass+1)); fi

echo ""
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" vision "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
