#!/usr/bin/env bash
# test-adversarial-datamodel.sh — data-model-pack floor の敵対検査 (verify-datamodel.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-datamodel.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (floor 三本柱): ① 照会グラフ (偽 FR・role 偽装・count・per-card relocation・可視コード捏造・href deep-link) /
#   ② navigable id アンカー (削除/改名) / ③ census-count (件数・空 block red pin) / band 数詞 (abort + HTML fidelity) /
#   図 (ER mermaid DSL/figcaption) / 可視テキスト捏造 / kind・cardinality 反転 / cross-doc 可視 echo / core chrome /
#   CJK 空白規律 / prose 注入 / floor 単独 GREEN 禁止 / repro-build conformance を *全捕捉*。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-datamodel.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-appointment.datamodel.yaml"
MANIFEST="$HERE/prose/clinic-appointment.datamodel.prose.yaml"
ASSEMBLE="$HERE/assemble-datamodel.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-datamodel.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm (verify_repro_build) は verify-*.sh 既定 ON。 bulk case は honest skip で速度維持し、 conformance pin (末尾) だけ arm ON 実走。
export SKIP_REPRO="${SKIP_REPRO:-1}"
# gate F (playwright visual) は floor-adversarial では skip (重い render を外す・SKIP_REPRO と同型)。 B 段
# (folio-jyfh) で mermaid も render 対象になったが、 bash floor では従来通り skip し CI 側で実 render する。
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
# expect_abort <label> <contract.yaml> [expected_stderr_substring] — assemble 段の contract fail-closed (folio-bhe)。
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
# expect_vfail_contract <label> <contract.yaml> <html> [fail-substr] — 改竄 contract を verify へ渡し FAIL を要求 (verify 側独立 pin)。
expect_vfail_contract() {
  local label="$1" c="$2" html="$3" want="${4:-}" out rc
  total=$((total+1))
  out="$("$VERIFY" --filled "$MANIFEST" "$c" "$html" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  [SLIP] $label — verify が通過させた (exit 0)"
  elif [[ -n "$want" && "$out" != *"$want"* ]]; then
    echo "  [SLIP] $label — FAIL したが理由が想定外 (期待 '$want')"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
# dm_base <dst.yaml> — contract を TMP へコピーし、 cross_doc が相対参照する SRS contract も同じ dir へコピーする
#   (assemble-datamodel のパス解決は CONTRACT_DIR 相対の素朴連結 = 兄弟配置が前提)。
dm_base() {
  local d; d="$(dirname "$1")"
  cp "$CONTRACT" "$1"
  cp "$HERE/contract/clinic-appointment.srs.yaml" "$d/"
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi
total=$((total+1))
dm_base "$TMP/base-sanity.yaml"
if "$ASSEMBLE" "$TMP/base-sanity.yaml" >/dev/null 2>&1; then
  echo "  [OK]   baseline dm_base コピーは assemble PASS"; pass=$((pass+1))
else
  echo "  [SLIP] dm_base コピーが assemble FAIL (helper 前提崩壊)"; fi

# --- ③ census-count (件数) ---
expect_fail "entity-card マーカー削除 (census)"      "$(mut 1 's{<article data-component="entity-card" id="entity-practitioner">}{<article data-component="entity-XXX" id="entity-practitioner">}')"
expect_fail "entity-field-row マーカー削除 (census)"  "$(mut 2 's{<tr data-component="entity-field-row"><td class="ef-name">診療科</td>}{<tr data-component="entity-XXX"><td class="ef-name">診療科</td>}')"
expect_fail "relationship-row マーカー削除 (census)"  "$(mut 3 's{<article data-component="relationship-row" id="rel-REL-1">}{<article data-component="rel-XXX" id="rel-REL-1">}')"
expect_fail "data-policy-card マーカー削除 (census)"  "$(mut 4 's{<div data-component="data-policy-card" id="dp-DP-1">}{<div data-component="dp-XXX" id="dp-DP-1">}')"
expect_fail "er-diagram mermaid pre 削除 (census)"    "$(mut 5 's{<pre class="mermaid">erDiagram}{<pre class="XXX">erDiagram}')"
# ★census red pin: 空 entity-card block を追加注入 (件数 6→7・id anchor も崩す)
expect_fail "census red pin: 偽 entity-card block 追加注入" "$(mut 6 's{</div>\n</div>\n<footer}{<article data-component="entity-card" id="entity-fake"></article></div>\n</div>\n<footer}')"

# --- ③b band 見出し (folio-bhe: instance hardcode 封鎖 + 数詞 fabrication) ---
dm_base "$TMP/bh1.yaml"; yq -i 'del(.chapters.entities_band)' "$TMP/bh1.yaml"
expect_abort "BH1 ★chapters.entities_band 欠落を abort" "$TMP/bh1.yaml" "chapters.entities_band 欠落"
dm_base "$TMP/bh2.yaml"; yq -i 'del(.chapters.relationships_band)' "$TMP/bh2.yaml"
expect_abort "BH2 ★chapters.relationships_band 欠落を abort" "$TMP/bh2.yaml" "chapters.relationships_band 欠落"
dm_base "$TMP/bh3.yaml"; yq -i '.chapters.entities_band = "7 つの情報のかたまりに分け、 何をどう持つか"' "$TMP/bh3.yaml"
expect_abort "BH3 ★entities_band 数詞 7≠実件数 6 を abort (件数 fabrication)" "$TMP/bh3.yaml" "実件数 6 と不一致"
dm_base "$TMP/bh4.yaml"; yq -i '.chapters.entities_band = "６ つの情報のかたまりに分け、 何をどう持つか"' "$TMP/bh4.yaml"
expect_abort "BH4 ★entities_band 全角数字 (数詞照合回避) を abort" "$TMP/bh4.yaml" "全角数字"
dm_base "$TMP/bh5.yaml"; yq -i '.chapters.entities_band = "六 つの情報のかたまりに分け、 何をどう持つか"' "$TMP/bh5.yaml"
expect_abort "BH5 ★entities_band 漢数字 (ASCII 照合回避) を数詞必須で abort" "$TMP/bh5.yaml" "ASCII 数字の件数"
dm_base "$TMP/bh6.yaml"; yq -i '.chapters.relationships_band = "6 つのつながりで結び、 事故を防ぐ決まりを埋め込む"' "$TMP/bh6.yaml"
expect_abort "BH6 ★relationships_band 数詞 6≠実件数 5 を abort" "$TMP/bh6.yaml" "実件数 5 と不一致"
# HTML band h2 改竄 (contract は正) → verify FAIL
expect_fail "BH7 ★HTML band h2 件数改竄 (6→7 つの情報のかたまり)" "$(mut 7 's{<h2>6 つの情報のかたまりに分け}{<h2>7 つの情報のかたまりに分け}')"
expect_fail "BH8 ★HTML band h2 pack 固定文言改竄 (データ→会計の扱い)" "$(mut 8 's{<h2>何を持たず、 何のために使い、 いつ消すか</h2>}{<h2>会計をどう締めるか</h2>}')"
# verify 側独立数詞 pin (両側辻褄合わせ)
dm_base "$TMP/bh9.yaml"; yq -i '.chapters.entities_band = "7 つの情報のかたまりに分け、 何をどう持つか"' "$TMP/bh9.yaml"
expect_vfail_contract "BH9 ★両側辻褄合わせ (contract+HTML=7) を verify 独立数詞 pin で捕捉" "$TMP/bh9.yaml" \
  "$(mut 9 's{<h2>6 つの情報のかたまりに分け}{<h2>7 つの情報のかたまりに分け}')" "expected 6, got 7"
# verify 側 非 ASCII 拒否の肯定形ブランチを独立 pin (representation-evasion・assemble を経ない --filled 直検では
# assemble 側 BH5 abort が走らず verify 側が唯一の防御 = ceiling round-1 処方)
dm_base "$TMP/bh10.yaml"; yq -i '.chapters.entities_band = "六 つの情報のかたまりに分け、 何をどう持つか"' "$TMP/bh10.yaml"
expect_vfail_contract "BH10 ★両側辻褄合わせ (contract+HTML=漢数字 六) を verify 側 ASCII 必須肯定形で捕捉" "$TMP/bh10.yaml" \
  "$(mut 92 's{<h2>6 つの情報のかたまりに分け}{<h2>六 つの情報のかたまりに分け}')" "ASCII 数詞なし"

# --- ② navigable id アンカー ---
expect_fail "entity anchor 改名 (entity-patient→entity-FAKE)" "$(mut 10 's{id="entity-patient"}{id="entity-FAKE"}')"
expect_fail "relationship anchor 削除"                        "$(mut 11 's{ id="rel-REL-2"}{}')"
expect_fail "data-policy anchor 改名"                         "$(mut 12 's{id="dp-DP-2"}{id="dp-XXX"}')"
expect_fail "principle terminal anchor 改名"                  "$(mut 13 's{id="principle-PRIN-DATA-MINIMUM"}{id="principle-FAKE"}')"

# --- ① 照会グラフ (cross-doc 前方照会の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 20 's{data-dm-ref="FR7" data-dm-role="claim"}{data-dm-ref="FR99" data-dm-role="claim"}')"
expect_fail "SRS role 意味偽装 (claim→rationale)"    "$(mut 21 's{data-dm-ref="FR3" data-dm-role="claim"}{data-dm-ref="FR3" data-dm-role="rationale"}')"
expect_fail "SRS ref 削除 (count mismatch)"           "$(mut 22 's{<a class="srs-badge" href="clinic-appointment.srs.html#FR6" data-dm-ref="FR6" data-dm-role="claim">FR6</a>}{}')"
# per-card relocation (FR2↔FR6 を appointment↔reminder・global set/count/pair 不変ゆえ per-card のみ捕捉)
expect_fail "card 間 ref relocation (appointment FR2 ↔ reminder FR6)" "$(mut 23 's{href="clinic-appointment.srs.html#FR2" data-dm-ref="FR2" data-dm-role="claim">FR2</a>}{__SWP__}g; s{href="clinic-appointment.srs.html#FR6" data-dm-ref="FR6" data-dm-role="claim">FR6</a>}{href="clinic-appointment.srs.html#FR2" data-dm-ref="FR2" data-dm-role="claim">FR2</a>}g; s{__SWP__}{href="clinic-appointment.srs.html#FR6" data-dm-ref="FR6" data-dm-role="claim">FR6</a>}g')"
# 可視コード捏造 (data-dm-ref intact・可視だけ捏造)
expect_fail "可視 srs-badge コード捏造 (FR7→FR99・data-dm-ref intact)" "$(mut 24 's{data-dm-ref="FR7" data-dm-role="claim">FR7</a>}{data-dm-ref="FR7" data-dm-role="claim">FR99</a>}')"
# href deep-link 改竄 (fragment swap・data-dm-ref intact)
expect_fail "href anchor swap (#FR7→#FR99・data-dm-ref=FR7 intact)"   "$(mut 25 's{href="clinic-appointment.srs.html#FR7" data-dm-ref="FR7"}{href="clinic-appointment.srs.html#FR99" data-dm-ref="FR7"}')"
expect_fail "href 外部 host 注入 (SRS→https://evil・属性 intact)"      "$(mut 26 's{href="clinic-appointment.srs.html#FR1" data-dm-ref="FR1"}{href="https://evil.example#FR1" data-dm-ref="FR1"}')"

# --- cross-doc 可視 echo (表紙 ref-chip) ---
expect_fail "ref-chip srs_doc_id 捏造" "$(mut 30 's{(data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"

# --- 可視テキスト fidelity (属性 intact のまま可視だけ捏造) ---
expect_fail "entity name 捏造"        "$(mut 40 's{<span class="ec-name">患者</span>}{<span class="ec-name">捏造かたまり</span>}')"
expect_fail "entity description 捏造"  "$(mut 41 's{予約を取り受診する人。}{でたらめな説明。}')"
expect_fail "entity kind 反転 (患者 master→event)" "$(mut 42 's{<span class="ec-name">患者</span><span class="ec-kind master">台帳</span>}{<span class="ec-name">患者</span><span class="ec-kind event">記録</span>}')"
expect_fail "field name 捏造"          "$(mut 43 's{<td class="ef-name">患者番号</td>}{<td class="ef-name">捏造項目</td>}')"
expect_fail "field type 捏造"          "$(mut 44 's{<span class="ef-type id">識別子</span>}{<span class="ef-type id">捏造型</span>}')"
expect_fail "field note 捏造"          "$(mut 45 's{<td class="ef-note">院内で重複しない番号。</td>}{<td class="ef-note">でたらめな注記。</td>}')"
expect_fail "field type class 改竄 (id→ref)" "$(mut 46 's{<span class="ef-type id">識別子</span>}{<span class="ef-type ref">識別子</span>}')"
expect_fail "rel-plain 捏造"           "$(mut 47 's{一人の患者は予約をいくつも持てる。}{でたらめな関係。}')"
expect_fail "rel-verb label 捏造"      "$(mut 48 's{<span class="ar">—</span>取る<span class="ar">→</span>}{<span class="ar">—</span>捏造<span class="ar">→</span>}')"
expect_fail "rel-card 捏造 (1 対 多→1 対 1)" "$(mut 49 's{<span class="rel-card">1 対 多</span>}{<span class="rel-card">1 対 1</span>}')"
expect_fail "invariant iv-txt 捏造"    "$(mut 50 's{二重予約 \(ダブルブッキング\) は、 この決まりによってデータの形として起こらない。}{でたらめな不変条件。}')"
expect_fail "dp-rule 捏造"             "$(mut 51 's{診療の中身 \(症状・診断・処方\) は、 この仕組みでは持たない。}{でたらめな方針。}')"
expect_fail "principle pt-text 捏造"   "$(mut 52 's{迷ったら「持たない」に倒す。}{迷ったら全部持つ。}')"
expect_fail "context problem 捏造"     "$(mut 53 's{予約の事故 \(同じ枠に 2 人}{予約は安全 (何も起きず}')"
expect_fail "scope_note 捏造"          "$(mut 54 's{この文書は「何を持つか・どうつながるか」だけを決める。}{この文書は全部を決める。}')"

# --- ★per-row relocation (件数/順序保存ゆえ count-only/flat-set 層を素通し・per-row 束縛が単独で捕捉。 SKIP_REPRO=1 前提) ---
# 機微度: patient(high) と practitioner(normal) の sens-high class + ec-sens バッジを入替え (ec-sens/sens-high 件数=1 保持)。
#   「患者は非慎重・医師は慎重」という虚偽 = データガバナンスの中核捏造を per-entity 機微度束縛が単独で FAIL させる。
expect_fail "機微度 relocation (patient↔practitioner sens-high+badge 入替・件数保持)" "$(mut 55 'my ($b)=/(<a class="ec-sens".*?<\/a>)/s; s/(<article data-component="entity-card") class="sens-high"( id="entity-patient">)/$1$2/; s/(<article data-component="entity-card")( id="entity-practitioner">)/$1 class="sens-high"$2/; s/\Q$b\E//; s/(<span class="ec-name">医師<\/span><span class="ec-kind master">台帳<\/span>)/$1$b/;')"
# required: patient 患者番号 の必須バッジを氏名へ移す (患者番号→任意・氏名に重複必須注入で ef-req 件数 24 保持)。
#   「必須フィールドを任意と偽る」= 入力規律の捏造を per-field required 束縛が単独で FAIL させる。
expect_fail "required relocation (患者番号 必須→氏名・ef-req 件数保持)" "$(mut 56 's{<td class="ef-name">患者番号</td><td><span class="ef-type id">識別子</span></td><td><span class="ef-req">必須</span></td>}{<td class="ef-name">患者番号</td><td><span class="ef-type id">識別子</span></td><td><span class="ef-note">任意</span></td>}; s{<td class="ef-name">氏名</td>}{<td class="ef-name">氏名</td><span class="ef-req">必須</span>};')"
# invariant: REL-2 の不変条件 (callout + has-invariant class) を「順序保存で」REL-1 へ移す (callout/has-invariant 件数=2・
#   emission 順 flat iv-txt set も不変)。 「二重予約は起こらない」不変条件を別 rel の帰属と偽る捏造を per-rel 不変条件束縛が単独で FAIL。
expect_fail "invariant relocation (REL-2 不変条件→REL-1・順序保存で flat set/件数 不変)" "$(mut 57 'my ($cal)=/(<div data-component="invariant-callout">.*?<\/div>)/s; s/\Q$cal\E//; s{(<article data-component="relationship-row" id="rel-REL-1">.*?<p class="rel-plain">.*?<\/p>)}{$1$cal}s; s{<article data-component="relationship-row" class="has-invariant" id="rel-REL-2">}{<article data-component="relationship-row" id="rel-REL-2">}; s{<article data-component="relationship-row" id="rel-REL-1">}{<article data-component="relationship-row" class="has-invariant" id="rel-REL-1">};')"

# --- 図 (ER mermaid DSL + figcaption + diag-tag) ---
expect_fail "ER mermaid DSL 改竄 (図 内容捏造)" "$(mut 60 's{ : &quot;取る&quot;}{ : &quot;捏造&quot;}')"
expect_fail "figcaption 改竄"                  "$(mut 61 's{図 1 \(ER 図 — 情報のつながり\)}{でたらめな図の説明}')"
expect_fail "diag-tag 改竄"                    "$(mut 62 's{<span class="diag-tag">ER — Entity Relationship</span>}{<span class="diag-tag">FAKE-TAG</span>}')"

# --- 横展開: CJK inline 強調の空白規律 ---
expect_fail "CJK 隣接の <b> 前空白 注入"  "$(mut 70 's{<p class="dp-rule">診療の中身}{<p class="dp-rule">診療の中身 <b>を</b>}')"

# --- cover-meta / core chrome ---
expect_fail "cover-meta 構成 捏造"           "$(mut 80 's{(<span class="k">構成</span><span class="v">)[^<]+}{${1}捏造構成}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 81 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "glossary def 捏造 (core-chrome)" "$(mut 82 's{ひとまとまりで扱う情報の単位。 この文書では 6 つに分けている。}{でたらめな定義。}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 90 's{(data-slot-id="plain-patient">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 91 's{(data-slot-id="cover-summary">)[^<]+(</p>)}{${1}${2}}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi

echo ""
echo "--- repro-build conformance (verify_repro_build): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" datamodel "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
