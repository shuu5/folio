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
# repro-build arm (verify_repro_build・folio-3d23) は verify-*.sh 既定 ON。 bulk case は honest skip で 10 分/suite を維持し
# (arm 未 skip は assemble 再 build で timeout)、 conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
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

# expect_abort <label> <contract.yaml> [expected_stderr_substring] — assemble 段の contract fail-closed (folio-bhe)。
#   abort 系の reason substring は stderr の label 語で判定可 (verify FAIL 系 pin の「FAIL 行にしか出ない値」
#   基準とは別・c5r.2 実証)。
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
# expect_vfail_contract <label> <contract.yaml> <html> [fail-substr] — 改竄 contract を verify へ渡し FAIL を要求
#   (verify 側独立 pin の FAIL 経路を発火させる・principle 敵対の expect_vprefill_fail 同旨・ceiling wf_7edab13c major 是正)。
#   ★fail-substr は FAIL 行にしか出ない値 ("expected 6, got 7" 等) にする — label 語は [OK] 行にも出て判別力ゼロ。
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
# arch_base <dst.yaml> — contract を TMP へコピーし、 cross_doc が相対参照する SRS/ADR contract も同じ dir へ
#   コピーする (assemble-arch のパス解決は CONTRACT_DIR 相対の素朴連結 = 兄弟配置が前提・絶対パスは解決不能)。
#   コピー先で参照が巻き添え failure し expect_abort が「mutation 以外の理由」で偽 [OK] 化するのを防ぐ
#   (principle 敵対の bd_base と同旨)。
arch_base() {
  local d; d="$(dirname "$1")"
  cp "$CONTRACT" "$1"
  cp "$HERE/contract/clinic-appointment.srs.yaml" "$HERE/contract/clinic-double-booking.adr.yaml" "$d/"
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# baseline sanity: arch_base コピー (cross_doc 絶対化のみ・無改竄) は assemble を通過すべき
#   (これが崩れると以降の expect_abort が「mutation 以外の理由」で全 false-pass する)
total=$((total+1))
arch_base "$TMP/base-sanity.yaml"
if "$ASSEMBLE" "$TMP/base-sanity.yaml" >/dev/null 2>&1; then
  echo "  [OK]   baseline arch_base コピーは assemble PASS"; pass=$((pass+1))
else
  echo "  [SLIP] arch_base コピーが assemble FAIL (helper 前提崩壊)"; fi

# --- ③ 固定章 + 必須要素 (件数) ---
expect_fail "decision-card マーカー削除 (件数)"  "$(mut 1 's{<div data-component="arch-decision-card" id="ad-AD-1">}{<div data-component="arch-decision-XXX" id="ad-AD-1">}')"
expect_fail "component-row マーカー削除 (件数)"  "$(mut 2 's{<tr data-component="component-row" id="comp-web-front">}{<tr data-component="component-XXX" id="comp-web-front">}')"
expect_fail "chapter-deck-band 削除 (8 章崩れ)"  "$(mut 3 's{data-component="chapter-deck-band" class="tint-warn"}{data-component="chapter-XXX" class="tint-warn"}')"
expect_fail "mermaid pre 削除 (図 件数)"         "$(mut 4 's{<pre class="mermaid">flowchart TB}{<pre class="XXX">flowchart TB}')"

# --- ③b ★band 見出し (folio-bhe: instance hardcode 封鎖 + 数詞 fabrication・principle-pack c5r.2 CH1-CH9 同型。
#     amendment 対称の CH7/CH8 は arch に amendment 章が無いため N/A) ---
# BH1/BH2. chapters.* 欠落 → 生成前 abort (band 見出しは contract 必須・neutral default を置かない)
arch_base "$TMP/bh1.yaml"; yq -i 'del(.chapters.components)' "$TMP/bh1.yaml"
expect_abort "BH1 ★chapters.components 欠落を abort (band 見出しは contract 必須)" "$TMP/bh1.yaml" "chapters.components 欠落"
arch_base "$TMP/bh2.yaml"; yq -i 'del(.chapters.runtime)' "$TMP/bh2.yaml"
expect_abort "BH2 ★chapters.runtime 欠落を abort (band 見出しは contract 必須)" "$TMP/bh2.yaml" "chapters.runtime 欠落"
# BH3. chapters 数詞改竄 (6→7・実件数 6 のまま) → 生成前 abort (件数 fabrication)
arch_base "$TMP/bh3.yaml"; yq -i '.chapters.components = "システムを 7 つの部品に分け、 何を担当するか"' "$TMP/bh3.yaml"
# ★pin substring は guard 固有語 "components 実件数" (旧 "不一致" は srs/adr doc_id guard とも共有・ceiling wf_6166a844 是正)
expect_abort "BH3 ★chapters.components 数詞 7≠components 実件数 6 を生成前 abort (件数 fabrication)" "$TMP/bh3.yaml" "components 実件数"
# BH4. 全角数字 (数詞照合の回避表記) → 生成前 abort
arch_base "$TMP/bh4.yaml"; yq -i '.chapters.components = "システムを ６ つの部品に分け、 何を担当するか"' "$TMP/bh4.yaml"
expect_abort "BH4 ★chapters の全角数字 (数詞照合回避) を生成前 abort" "$TMP/bh4.yaml" "全角数字"
# BH5. 漢数字 (ASCII 照合回避) → 数詞必須の肯定形で生成前 abort (回避表記の blocklist 列挙をしない)
arch_base "$TMP/bh5.yaml"; yq -i '.chapters.components = "システムを 六 つの部品に分け、 何を担当するか"' "$TMP/bh5.yaml"
expect_abort "BH5 ★chapters の漢数字数詞 (ASCII 照合回避) を数詞必須で生成前 abort" "$TMP/bh5.yaml" "ASCII 数字の件数"
# BH6-BH8. HTML band h2 改竄 (contract は正) → verify FAIL (band h2 fidelity)
expect_fail "BH6 ★HTML band h2 件数改竄 (6→7 つの部品)"          "$(mut 70 's{<h2>システムを 6 つの部品に分け}{<h2>システムを 7 つの部品に分け}')"
expect_fail "BH7 ★HTML band h2 ドメイン差替 (二重予約→会計)"     "$(mut 71 's{<h2>二重予約をどう止めるか、 部品がどう連携するか</h2>}{<h2>会計をどう締めるか、 部品がどう連携するか</h2>}')"
expect_fail "BH8 ★HTML band h2 pack 固定文言の改竄 (品質→速度)"   "$(mut 72 's{<h2>どんな品質をどこまで目指すか</h2>}{<h2>どんな速度をどこまで目指すか</h2>}')"
# BH9/BH10. additive-decoy 系 (ceiling wf_7edab13c blocker の pin): 置換でなく *追加* — 同一行に decoy h2 を注入 /
#   同一行に捏造 band を丸ごと packing。行ベース抽出だと末尾の real h2 を拾い素通り (要素単位抽出で fail-closed)。
expect_fail "BH9 ★同一行 decoy h2 注入 (real h2 は無傷・偽「9 つの部品」が描画される)" "$(mut 73 's{(<h2>システムを 6 つの部品に分け)}{<h2>システムを 9 つの部品に分け、 何を担当するか</h2>$1}')"
expect_fail "BH10 ★同一行 9 本目 band packing (行数 8 のまま要素数 9)" "$(mut 74 's{(<section data-component="chapter-deck-band" class="tint-warn")}{<section data-component="chapter-deck-band" class="tint-info"><span class="num">09</span><h2>捏造の章</h2></section>$1}')"
# BH11/BH12. ★verify 側独立数詞 pin (c5r.2 CH4/CH9 相当・ceiling wf_7edab13c major の pin): contract+HTML の
#   *両側* を辻褄合わせても verify が |components| から独立再導出して捕捉する (assemble guard 回帰への defense-in-depth)。
arch_base "$TMP/bh11.yaml"; yq -i '.chapters.components = "システムを 7 つの部品に分け、 何を担当するか"' "$TMP/bh11.yaml"
expect_vfail_contract "BH11 ★両側辻褄合わせ (contract+HTML=7 つの部品) を verify が独立数詞 pin で捕捉" "$TMP/bh11.yaml" \
  "$(mut 75 's{<h2>システムを 6 つの部品に分け}{<h2>システムを 7 つの部品に分け}')" "expected 6, got 7"
arch_base "$TMP/bh12.yaml"; yq -i '.chapters.components = "システムを 六 つの部品に分け、 何を担当するか"' "$TMP/bh12.yaml"
expect_vfail_contract "BH12 ★両側漢数字 (六 つの部品) を verify の ASCII 数詞必須で捕捉" "$TMP/bh12.yaml" \
  "$(mut 76 's{<h2>システムを 6 つの部品に分け}{<h2>システムを 六 つの部品に分け}')" "(ASCII 数詞なし=半角必須)"
# BH13. 第 2 数詞の偽件数併記 (先頭 6 は正・後続 9 が偽) → 全出現照合で生成前 abort (head -1 是正の pin)
arch_base "$TMP/bh13.yaml"; yq -i '.chapters.components = "システムを 6 つの部品に分け、 何を担当するか — 実は 9 つの部品もある"' "$TMP/bh13.yaml"
expect_abort "BH13 ★第 2 数詞の偽件数併記 (6 正 + 9 偽) を全出現照合で生成前 abort" "$TMP/bh13.yaml" "数詞 9 が components 実件数 6 と不一致"
# BH14-BH16. ★genuine-shape 不変条件の pin (ceiling wf_6166a844 blocker C1/A1 + minor A2): 狭い正規表現の
#   パーサ差分 (属性付き decoy h2 / 大文字 SECTION・H2 / band 範囲外 h2) を要素単位・ci・attribute-tolerant 抽出で封鎖。
expect_fail "BH14 ★属性付き decoy <h2 class> を band 内注入 (attribute-tolerant 抽出 + NH2≠8 で封鎖)" "$(mut 77 's{(<h2>システムを 6 つの部品に分け、 何を担当するか</h2>)}{$1<h2 class="decoy">実は 9 つの部品に分けた</h2>}')"
expect_fail "BH15 ★大文字 <SECTION>/<H2> で捏造 9 章目 (case-insensitive count で封鎖)" "$(mut 78 's{(<section data-component="chapter-deck-band" class="tint-violet"><span class="num">08)}{<SECTION data-component="chapter-deck-band" class="tint-brand"><span class="num">09</span><span class="kicker">FAKE</span><H2>捏造9章</H2></SECTION>$1}')"
expect_fail "BH16 ★band 範囲外の bare <h2> (全 <h2>==8 不変条件で封鎖)" "$(mut 79 's{(<div class="chapbody">)}{$1<h2>範囲外の捏造見出し</h2>}')"
# BH17/BH18. ★components-only 収束の positive pin (ceiling wf_966c2160): 数詞/全角 guard は components のみ。
#   runtime の全角固有名詞 (「Ｇ７世代」) と SEMANTIC な偽件数 (「9 個の部品」= 任意 unit 語で機械列挙不能) は floor で
#   捕捉せず ceiling/fidelity 領分 (machine/LLM 境界)。round2 の runtime 全角 abort は components-only へ収束し撤回。
total=$((total+1))
arch_base "$TMP/bh17.yaml"; yq -i '.chapters.runtime = "Ｇ７世代の予約エンジンで二重予約を止める流れ"' "$TMP/bh17.yaml"
if "$ASSEMBLE" "$TMP/bh17.yaml" >/dev/null 2>&1; then echo "  [OK]   BH17 ★runtime の全角固有名詞は assemble PASS (全角/数詞 guard は components のみ)"; pass=$((pass+1)); else echo "  [SLIP] BH17 runtime 全角が誤 reject (components-only 収束が崩れた)"; fi
total=$((total+1))
arch_base "$TMP/bh18.yaml"; yq -i '.chapters.runtime = "24 時間の予約フローで二重予約を止める仕組み"' "$TMP/bh18.yaml"
if "$ASSEMBLE" "$TMP/bh18.yaml" >/dev/null 2>&1; then echo "  [OK]   BH18 ★runtime の ASCII 数字も assemble PASS (runtime は数詞 guard なし)"; pass=$((pass+1)); else echo "  [SLIP] BH18 runtime の ASCII 数字が誤 reject された"; fi
# BH19. ★複合語 false-match 回避の pin (ceiling wf_966c2160 major): components 見出しが「N つの部品グループ/群」を
#   含んでも部分文字列 false-match せず正当な「N つの部品」count だけ照合する (perl negative-lookahead)。
total=$((total+1))
arch_base "$TMP/bh19.yaml"; yq -i '.chapters.components = "システムを 6 つの部品に分け、 3 つの部品グループに整理する"' "$TMP/bh19.yaml"
if "$ASSEMBLE" "$TMP/bh19.yaml" >/dev/null 2>&1; then echo "  [OK]   BH19 ★複合語「部品グループ」を含む正当な components 見出しは assemble PASS"; pass=$((pass+1)); else echo "  [SLIP] BH19 複合語を含む見出しが誤 reject された (false-match)"; fi
# BH20/BH21. ★CJK 句読点直前の偽件数を捕捉 (ceiling wf_191f044b major の pin): scx 版 \p{Han}/\p{Katakana} は
#   。、「」・ を除外に混入させ「9 つの部品、」を素通したが、 sc= 版は句読点を境界扱いし偽件数を捕捉する (assemble+verify parity)。
arch_base "$TMP/bh20.yaml"; yq -i '.chapters.components = "システムを 6 つの部品に分けます、 実は 9 つの部品、 本来より多い"' "$TMP/bh20.yaml"
expect_abort "BH20 ★読点直前の偽件数「9 つの部品、」を生成前 abort (sc= 句読点境界)" "$TMP/bh20.yaml" "数詞 9 が components 実件数 6 と不一致"
arch_base "$TMP/bh21.yaml"; yq -i '.chapters.components = "システムを 6 つの部品に分ける。 実は 9 つの部品。"' "$TMP/bh21.yaml"
expect_abort "BH21 ★句点直前の偽件数「9 つの部品。」を生成前 abort (sc= 句読点境界)" "$TMP/bh21.yaml" "数詞 9 が components 実件数 6 と不一致"
# BH22. ★ゼロ幅文字 injection (ceiling wf_cb58ae5a blocker): 数字と unit の間に ZWSP を挟むと数詞照合の隣接が壊れ
#   偽件数「9<ZWSP>つの部品」が hidden 化する不可視版 BH13。 Default_Ignorable クラス拒否で生成前 abort。
ZWSP=$'​'
arch_base "$TMP/bh22.yaml"; VAL22="システムを 6 つの部品に分け、 実は 9${ZWSP}つの部品ある" yq -i '.chapters.components = strenv(VAL22)' "$TMP/bh22.yaml"
expect_abort "BH22 ★ゼロ幅文字 injection「9<ZWSP>つの部品」を生成前 abort (不可視 fabrication)" "$TMP/bh22.yaml" "不可視/format 文字"
# BH23. ★verify 側でも rendered 見出しの不可視文字を検出 (HTML 経路の ZWSP injection・assemble と parity)。
#   contract は正常だが HTML h2 に ZWSP を注入 → band 見出し不可視文字 chk で FAIL (h2 fidelity より先に不可視で捕捉)。
expect_fail "BH23 ★HTML band 見出しへの ZWSP 注入を verify が捕捉" "$(mut 80 "s{システムを 6 つの部品に分け}{システムを 6 つの部品に分${ZWSP}け}")"

# --- ② navigable id アンカー (削除/改名) ---
expect_fail "decision anchor 改名 (ad-AD-1→ad-FAKE)" "$(mut 5 's{id="ad-AD-1"}{id="ad-FAKE"}')"
expect_fail "component anchor 削除"                   "$(mut 6 's{ id="comp-slot-store"}{}')"
expect_fail "quality anchor 改名"                     "$(mut 7 's{id="qa-QA-1"}{id="qa-XXX"}')"
expect_fail "principle terminal anchor 改名"          "$(mut 8 's{id="principle-PRIN-SAFETY-FIRST"}{id="principle-FAKE"}')"

# --- ① 照会グラフ (cross-doc 前方照会の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 10 's{data-arch-ref="FR2" data-arch-role="claim"}{data-arch-ref="FR99" data-arch-role="claim"}')"
expect_fail "SRS role 意味偽装 (claim→rationale)"     "$(mut 11 's{data-arch-ref="FR2" data-arch-role="claim"}{data-arch-ref="FR2" data-arch-role="rationale"}')"
expect_fail "SRS ref 削除 (count mismatch)"            "$(mut 12 's{<a class="xref-link" href="clinic-appointment.srs.html#FR2" data-arch-ref="FR2" data-arch-role="claim"><span class="xref-code">FR2</span><span class="xref-label" data-srs-label-ref="FR2">予約受付</span></a>}{}')"
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
expect_fail "href SRS anchor swap (#FR2→#FR99・data-arch-ref=FR2 intact)"           "$(mut 52 's{href="clinic-appointment.srs.html#FR2"}{href="clinic-appointment.srs.html#FR99"}')"
expect_fail "href filename 外部host注入 (SRS→https://evil.example・属性 intact)"     "$(mut 53 's{href="clinic-appointment.srs.html#FR3"}{href="https://evil.example#FR3"}')"
expect_fail "href 原則 within-doc デッドリンク (#principle-PRIN…→#principle-FAKE)"   "$(mut 54 's{href="#principle-PRIN-SAFETY-FIRST"}{href="#principle-FAKE"}')"
expect_fail "href quality anchor swap (#AC1→#AC99・data-quality-srs-ref=AC1 intact)" "$(mut 55 's{href="clinic-appointment.srs.html#AC1"}{href="clinic-appointment.srs.html#AC99"}')"

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
# ★folio-c5r.10: runtime flow summary (rt-summary・従来 silent field-drop だった) の fidelity
expect_fail "runtime summary 捏造 (rt-summary・SSoT 外作文)"  "$(mut 61 's{<p class="rt-summary">[^<]*</p>}{<p class="rt-summary">でたらめな概要を作文</p>}')"
expect_fail "runtime summary 削除 (rt-summary・field-drop 再発)" "$(mut 62 's{<p class="rt-summary">[^<]*</p>}{}')"
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
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" arch "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
