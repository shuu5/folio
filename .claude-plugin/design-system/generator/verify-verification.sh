#!/usr/bin/env bash
# folio engine tr0 (folio-nxp) — spec-pack fabrication-free + 非終端 照会 floor の FORK (doc-type=spec / verification self-host)
#
# ★verify-spec.sh (rules 用) の FORK。 共有 core (lib/) 無改変。 doc_type guard を rules→spec へ、 ORIG 原本を verification.html へ、
#   機械層 round-trip / 件数に verification 固有の demoted (ADR-0040 降格分) を追加した以外は verify-spec.sh と同型。
# 生成 spec (verification) HTML の *構造* が入力 spec contract から完全に導出されたことを機械検証する floor gate。
# verify-fabrication-free.sh (SRS) / verify-adr.sh / verify-research.sh / verify-principle.sh と同型の規律を
# spec-pack schema (sections / requirements(EARS) / references(非終端 照会) / glossary) へ適用する:
#   - 行数 = contract 導出 (section / band / 要件 row / ref chip / block 種別ごとの件数)。
#   - 要件 fidelity: data-req-id 集合一致 + (id, ears-pattern, badge class/label, essence, statement) を emission 順で突合。
#   - section fidelity: 可視 heading 列 / essence 列が contract と順序一致。
#   - block fidelity: prose / note / list / code / table / mermaid / subhead の可視テキストを順序突合 (silent drop 検出)。
#   - ★非終端 照会 (references): chip が token/doc/role を faithfully echo (count / SET / role allowlist / (token,role) ペア / 可視 <b>==attr)。
#   - core 共通 chrome (cover-head / approval / glossary) = verify_core_chrome (folio-mk9)。 cover-meta 4 KV 再導出。
#   - escape 健全 / prose スロット (3 mode = pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)。
#
# usage: verify-spec.sh [--filled <manifest.yaml> | --artifact] <spec-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate モデル・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合。
#   prose スロット (cover-summary / chapter-lead-NN) の *内容真正性* は floor の対象外 = ceiling (fidelity-* 相当・persona-walk)。
#   floor 単独で GREEN にはならず CEILING=PENDING (taxonomy §5.1)。 spec-pack 専用 ceiling agent の制度化は follow-up (admin 起票)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-spec: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-spec: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-spec: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-spec: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_core_chrome) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-spec: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-spec: failed to source verify-common.sh" >&2; exit 2; }

# EARS pattern → class / label (assemble-spec.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table「用途」列 SSoT に一致 (folio-2jr drift 是正)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1・assemble-spec と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )

fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build verification "$FILLED_MANIFEST"

echo "spec-pack fabrication-free + 非終端 照会 floor: $HTML"
echo "  contract: $CONTRACT"

NSEC="$(q '.sections | length')"
NREQ="$(q '.requirements | length')"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)。
#    chapter-deck-band = section 数 + 2 (references band + glossary band)。
chk "chapter-deck-band == sections + 2"   "$((NSEC + 2))"                  "$(grep -c 'data-component="chapter-deck-band"' "$BODY")"
chk "section-essence-callout == sections" "$NSEC"                          "$(grep -c 'data-component="section-essence-callout"' "$BODY")"
chk "ears-requirement-row == |requirements|" "$NREQ"                       "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "ears-badge == |requirements|"        "$NREQ"                          "$(grep -c 'data-component="ears-badge"' "$BODY")"
# ★EARS 凡例 (folio-2jr・静的 key): 1 個・5 item・label は EARS_LABEL (= rules.html §6 用途 SSoT) と §6 行順で一致 (assemble-spec と二重保守=parity)。
chk "ears-legend == 1"                    "1"                              "$(grep -o 'data-component="ears-legend"' "$BODY" | wc -l)"
chk "ears-legend-item == 5"               "5"                              "$(grep -o 'data-component="ears-legend-item"' "$BODY" | wc -l)"
exp_legend="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_LABEL[$p]}"; printf '\n'; done)"
act_legend="$(perl -CSD -0777 -ne 'while (/<span data-component="ears-legend-item" class="[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend label 列 == EARS_LABEL (§6 用途 順)" "$exp_legend" "$act_legend"
# ★凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1): 5 件・EARS_WHEN と §6 順で一致。
chk "ears-legend el-when == 5"            "5"                              "$(grep -o 'class="el-when"' "$BODY" | wc -l)"
exp_when="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_WHEN[$p]}"; printf '\n'; done)"
act_when="$(perl -CSD -0777 -ne 'while (/<span class="el-when">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend el-when 列 == EARS_WHEN (順序)" "$exp_when" "$act_when"
chk "cross-doc-ref-chip == |references|"   "$(q '.references | length')"   "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "glossary == |glossary|"              "$(q '.glossary | length')"      "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"              "$(q '.approval | length')"      "$(grep -c 'class="sign"' "$BODY")"
# block 種別ごとの件数 (silent drop / 偽 add を捕捉)。
chk "spec-prose == Σ prose blocks"        "$(q '[.sections[].blocks[]? | select(.type=="prose")] | length')"   "$(grep -c 'data-component="spec-prose"' "$BODY")"
chk "spec-note == Σ note blocks"          "$(q '[.sections[].blocks[]? | select(.type=="note")] | length')"    "$(grep -c 'data-component="spec-note"' "$BODY")"
chk "spec-list-block == Σ list blocks"    "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"    "$(grep -c 'data-component="spec-list-block"' "$BODY")"
chk "list 項目 (lbi) == Σ list items"     "$(q '[.sections[].blocks[]? | select(.type=="list") | .items[]] | length')" "$(grep -c 'class="lbi"' "$BODY")"
chk "spec-code == Σ code blocks"          "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"    "$(grep -c 'data-component="spec-code"' "$BODY")"
chk "spec-table == Σ table blocks"        "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"   "$(grep -c 'data-component="spec-table"' "$BODY")"
chk "spec-diagram == Σ mermaid blocks"    "$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')" "$(grep -c 'data-component="spec-diagram"' "$BODY")"
chk "spec-subhead == Σ subhead blocks"    "$(q '[.sections[].blocks[]? | select(.type=="subhead")] | length')" "$(grep -c 'data-component="spec-subhead"' "$BODY")"

# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# 1c. ★pack 固有 folio-* head meta (folio-aduv 0-c)。 CORE (core_emit_graph_head) が emit する 3 本 (doc-type/status/version)
#   の外側に、 verification.html は folio-layer / folio-glossary-automark / folio-stakeholders / folio-xref-completeness を
#   持つ (canonical 実測 = 計 7 本)。 これらは inventory / automark / xref-completeness の ★opt-in signal ゆえ、 欠けると
#   flip 後に該当 gate が keystone skip へ落ちる = 無検査の silent 化になる。
#   ★mutation-kill 実弾で確認した穴: assembler の emit_pack_head_meta 呼出を 1 行落とすと生成物の folio-* meta が
#   7→3 本へ落ちるのに、 本 script の FAIL 件数は baseline と完全一致だった (= 喪失に vacuous PASS)。 repro-build の
#   BYTE-DIFF も artifact 事後改変しか捕まえず、 contract と生成物が両側で同時に欠ける generator 回帰には無力。
#   ★双方向 chk (捏造も喪失も捕捉): contract に key が在れば逐字存在を要求し、 無ければ生成物にも不在を要求する。
#   ★stakeholders は contract 側が array (canonical JSON-LD と同型) ゆえ meta content は join(", ") で期待を組む。
verify_pack_head_meta() {
  local key tag exp act pair
  for pair in 'layer:folio-layer' 'glossary_automark:folio-glossary-automark' \
              'stakeholders:folio-stakeholders' 'xref_completeness:folio-xref-completeness'; do
    key="${pair%%:*}"; tag="${pair##*:}"
    if [[ "$key" == "stakeholders" ]]; then exp="$(q '(.meta.stakeholders // []) | join(", ")')"
    else exp="$(q ".meta.$key // \"\"")"; fi
    [[ "$exp" == "null" ]] && exp=""
    act="$(T="$tag" perl -CSD -0777 -ne 'BEGIN{$t=$ENV{T}} while (/<meta name="\Q$t\E" content="([^"]*)">/g){ print "$1\n"; }' "$HTML")"
    if [[ -n "$exp" ]]; then
      chk "head meta $tag == contract .meta.$key" "$(esc "$exp")" "$act"
    else
      chk "head meta $tag 不在 (contract 側も空 = 捏造禁止)" "" "$act"
    fi
  done
  # ★folio-* meta の総数 pin: 上の per-meta chk は「知っている 4 本」しか見ないため、 CORE 3 本の喪失や
  #   未知 meta の捏造混入を数で挟む (canonical 実測 = 7 本 = CORE 3 + pack 4)。
  chk "folio-* head meta 総数 == 7 (CORE 3 + pack 4)" "7" \
    "$(grep -o '<meta name="folio-[^"]*"' "$HTML" | wc -l | tr -d ' ')"
}
verify_pack_head_meta

# 2. id 一意性 + doc_type
chk_empty "要件 id 一意"     "$(q '.requirements[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "section id 一意"  "$(q '.sections[].id' | sort | uniq -d | tr '\n' ' ')"
chk "doc_type == spec"       "spec" "$(q '.meta.doc_type')"

# 3. section fidelity: 可視 heading 列 (先頭 NSEC 個の h2) == sections[].heading (順序) / essence 列 == sections[].essence (順序)。
exp_sh="$(q '.sections[].heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_sh="$(grep -oE '<h2>[^<]*</h2>' "$BODY" | sed -E 's#<h2>([^<]*)</h2>#\1#' | head -n "$NSEC")"
chk "section 可視 heading 列 == sections[].heading (順序)" "$exp_sh" "$act_sh"
# ★rich 契約値 (folio-aduv): essence は inline HTML (a.xref / span.term / <code> …) を逐語で持ち assembler が RAW emit する。
#   ゆえ期待側は esc せず *契約値そのもの*、 実測側は ([^<]*) でなく (.*?) + 固有終端で取る。
#   ★検出力は落ちない: 期待 == 実測の逐字一致は不変で、 escape 由来の化け・脱落・改竄はそのまま diff に出る
#   (esc したままだと raw emit と永久に不一致 = gate が意味を失う。 assert を緩めるのでなく *正しい期待値へ* 移す)。
exp_se="$(q '.sections[].essence')"
act_se="$(perl -CSD -0777 -ne 'while (/<div data-component="section-essence-callout"><p class="sec-se">(.*?)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
chk "section essence 列 == sections[].essence (順序・rich raw)" "$exp_se" "$act_se"
# ★kicker 列 fidelity (folio-l93): band() が可視 emit する <span class="kicker"> の §N/トピック ラベルは
#   sections[].kicker 由来の *決定的フィールド* ゆえ doctrine 上 floor (heading/essence と同列の section fidelity)。
#   未突合だと §番号 swap・トピック取り違え・heading の §N との drift が全 gate (floor/persona-walk/fidelity) を素通った (17n ceiling HIGH)。
#   全 NSEC+2 band の kicker を document 順で突合: 先頭 NSEC = sections[].kicker / 末尾 2 = references・glossary band の
#   静的リテラル (assemble-spec.sh build() と二重保守 = detect↔remediate parity)。 静的 2 件も期待列へ含め band 並び替え・
#   静的ラベル drift も lock する (heading は head -n NSEC で section のみだが kicker は全 band を被覆)。
#   抽出: <span class="kicker"><svg ...>…</svg> {esc kicker}</span> の svg 後の可視テキスト ([^<]* = esc 済ゆえ安全)。
STATIC_KICKERS=("この仕様が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
exp_kicker="$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_kicker="$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "section kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" "$exp_kicker" "$act_kicker"
# ★top-level section anchor 列 (folio-aduv 0-a)。 要件 anchor (tuple 同梱) / subhead anchor (SUBHEAD_RE) と並ぶ
#   ★3 クラス目の navigable id で、 ここだけ未配線だと非対称な穴になる (mutation-kill 実弾で確認: assembler の
#   章 anchor emit 行を落とすと生成物の section id が 7→0 本へ消え corpus inbound (#s1-contract 等) が
#   解決不能になるのに、 本 script の FAIL 件数は baseline と完全一致 = vacuous PASS だった)。
#   assembler 側の `[[ -n "$anchor" ]] || exit 1` は *契約値が空* の場合しか守らず emit 自体の脱落は守らない。
#   ★selector は emit_section の ★章包み <section id="…"> 形に固定する (旧 <span data-component="spec-section-anchor">
#   sibling 形からの追随)。 span 形は bin/folio の folio_chrome_toc_rows から ★不可視で章 TOC を全喪失させたため
#   canonical と同形の <section> 包みへ是正した (assemble-verification.sh emit_section の注記に機序と実測)。
#   band が開く <section data-component="chapter-deck-band"> は id を持たないので本 selector には掛からない。
chk "section anchor 列 == sections[].anchor (順序)" \
  "$(q '.sections[].anchor' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<section id="([^"]*)">/g){ print "$1\n"; }' "$BODY")"

# 4. 要件 fidelity: data-req-id 集合一致 + emission 順タプル (id, pattern, class, label, essence, statement) 突合。
exp_rid="$(q '.requirements[].id' | sort -u)"
act_rid="$(grep -oE 'data-req-id="[^"]+"' "$BODY" | sed 's/.*data-req-id="//; s/"$//' | sort -u)"
set_eq "要件 data-req-id 集合 (contract == HTML)" "$exp_rid" "$act_rid"
# emission 順 = sections→blocks(requirements).ids の document 順。
EXPF="$(mktemp)"; ACTF="$(mktemp)"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  ess="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # ★anchor (folio-aduv) = 生成物 row の navigable id (小文字 req-ver-* / req-nav-*)。 tuple に *同梱* して
  #   「id= が data-req-id (大文字) の置換でなく追加である」ことを 1 本の突合で pin する (両方が同時に等しくなければ FAIL)。
  anc="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anc" && "$anc" != "null" ]] || { echo "verify-spec: ★contract 要件 $id の anchor が空 (navigable id 不在・fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; }
  # ★contract 由来 pattern が allowlist 外なら expected タプルを :-unknown で組まず fail-closed (assemble validate と parity)。
  # silent な class="unknown" 同士の偽一致 (双辺で同じ fallback を引いて tuple PASS する fail-open) を封鎖。
  if ! [[ -v EARS_CLASS[$pat] ]]; then echo "verify-spec: ★contract 要件 $id の EARS pattern が allowlist 外: $pat (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
  # ★essence / statement は rich 契約値ゆえ esc しない (assembler の RAW emit と対称)。 id/pat/label は esc 経路のまま。
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(esc "$anc")" "$(esc "$id")" "$(esc "$pat")" "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$ess" "$stmt"
done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]') > "$EXPF"
perl -CSD -0777 -ne '
  # ★canonical dual-audience form (w1f cell-2): row opener に data-audience="human"、 rq-norm に data-audience="machine" を
  #   literal で要求し structured-regex に組み込む (= REQ-DA-STRUCT-1/-4 の構造 anchor を tuple 突合に同梱・属性 drop は row 脱落→件数 FAIL)。
  # ★folio-aduv: row opener に id="<小文字 navigable id>" を literal 要求 (anchor 脱落 = row 脱落 → 件数 FAIL = fail-closed)。
  #   essence / statement は rich raw ゆえ ([^<]*) から (.*?) + 固有終端へ (改行は跨がせない = inner_norm 単一行の暗黙 assert)。
  while (/<div data-component="ears-requirement-row" id="([^"]*)" data-req-id="([^"]*)" data-ears-pattern="([^"]*)" data-audience="human">\s*<div class="rq-head"><span class="rid">([^<]*)<\/span><span data-component="ears-badge" class="([^"]*)">([^<]*)<\/span><\/div>\s*<p class="rq-essence">(.*?)<\/p>\s*<details class="rq-norm" data-audience="machine"><summary>[^<]*<\/summary><p class="rq-stmt">(.*?)<\/p><\/details>/g) {
    my ($anc,$rid,$pat,$vrid,$cls,$lab,$ess,$stmt)=($1,$2,$3,$4,$5,$6,$7,$8);
    # 可視 rid == data-req-id (attr-vs-visible)
    if ($rid ne $vrid) { print "VIS-MISMATCH:$rid\xe2\x89\xa0$vrid\n"; next; }
    print "$anc\t$rid\t$pat\t$cls\t$lab\t$ess\t$stmt\n";
  }
' "$BODY" > "$ACTF"
if diff -q "$EXPF" "$ACTF" >/dev/null 2>&1; then
  printf '  [OK]   %-'"$CHKW"'s %s\n' "要件タプル (id/pattern/class/label/essence/statement) 順序突合" "$NREQ"
else
  printf '  [FAIL] %-'"$CHKW"'s\n' "要件タプル不一致 (id/pattern/badge/essence/statement 改竄 or 順序)"
  echo "    --- contract 期待のみ ---"; comm -23 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  echo "    --- HTML 実体のみ ---";     comm -13 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  fail=1
fi
rm -f "$EXPF" "$ACTF"

# 5. block 内容 fidelity (順序突合・silent drop / 値改竄を捕捉)。 全 leaf は esc 済ゆえ [^<]* / perl で安全。
# prose
chk "prose 可視テキスト列 == prose blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="prose") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<p data-component="spec-prose">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# note
chk "note 可視テキスト列 == note blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="note") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-note"><p>([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
# list 項目
chk "list 項目列 == list blocks.items (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="list") | .items[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<li class="lbi">[^<]*</li>' "$BODY" | sed -E 's#<li class="lbi">([^<]*)</li>#\1#')"
# subhead anchor + heading + essence
# ★folio-aduv: h3 に id="<fine section anchor>" を literal 要求 (corpus inbound 81 link の解決先)。 heading は plain 契約値 (esc 経路)、
#   essence は rich raw。 3 者を同一 regex から取り 3 本の chk で突合する (anchor 脱落は 3 本とも件数 FAIL = fail-closed)。
SUBHEAD_RE='<div data-component="spec-subhead"><h3 id="([^"]*)">([^<]*)<\/h3><p class="sub-se">(.*?)<\/p><\/div>'
chk "subhead anchor 列 == subhead blocks.anchor (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .anchor' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$1\n"; }' "$BODY")"
chk "subhead heading 列 == subhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$2\n"; }' "$BODY")"
chk "subhead essence 列 == subhead blocks.essence (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .essence')" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$3\n"; }' "$BODY")"
# table caption / header / cell (全 spec-table 横断・順序)
# ★folio-aduv: caption / th / td は rich 契約値 (原本 table は a.xref 13 / <code> 41 / <strong> 11 を内包) ゆえ
#   期待は esc せず契約値そのもの、 実測は (.*?) + 固有終端。 grep -oE の行内 [^<]* 抽出では tag 入りセルを取り落とす
#   (= 静かに空集合になり得る) ため perl の要素単位抽出へ寄せる。
chk "table caption 列 == table blocks.caption (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | (.caption // "")' | grep -v '^$')" \
  "$(perl -CSD -0777 -ne 'while (/<table data-component="spec-table"><caption>(.*?)<\/caption>/g){ print "$1\n"; }' "$BODY")"
chk "table th 列 == table blocks.headers (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .headers[]')" \
  "$(perl -CSD -0777 -ne 'while (/<th>(.*?)<\/th>/g){ print "$1\n"; }' "$BODY")"
chk "table td 列 == table blocks.rows cells (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .rows[][]')" \
  "$(perl -CSD -0777 -ne 'while (/<td>(.*?)<\/td>/g){ print "$1\n"; }' "$BODY")"
# mermaid caption + source lines
# ★folio-aduv: figcaption も rich 契約値 (原本 figcaption は <code> 2 + span.term 1 を内包 = canonical term 27 番目の在処)。
chk "mermaid figcaption 列 == mermaid blocks.caption (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | (.caption // "")' | grep -v '^$')" \
  "$(perl -CSD -0777 -ne 'while (/<figcaption>(.*?)<\/figcaption>/g){ print "$1\n"; }' "$BODY")"
chk "mermaid source 行列 == mermaid blocks.source_lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | .source_lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre class="mermaid">(.*?)<\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"
# code 行 (全 spec-code 横断・順序)
chk "code 行列 == code blocks.lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="code") | .lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre data-component="spec-code"><code>(.*?)<\/code><\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"

# 6. ★非終端 照会 (references) fidelity: chip echo 厳密一致。
NREF="$(q '.references | length')"
# count anchor (data-ref-token= 出現数)
chk "references: count == |references|" "$NREF" "$(grep -o 'data-ref-token=' "$BODY" | wc -l | tr -d ' ')"
# SET 一致 (token)
set_eq "references: token SET (contract == HTML)" \
  "$(q '.references[].token' | sort -u)" \
  "$(grep -oE 'data-ref-token="[^"]+"' "$BODY" | sed 's/.*data-ref-token="//; s/"$//' | sort -u)"
# role allowlist
badrole="$(grep -oE 'data-ref-role="[^"]+"' "$BODY" | sed 's/.*data-ref-role="//; s/"$//' | sort -u | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
chk_empty "references: role が抽象 allowlist 内" "$badrole"
# (token, doc, role) タプル順序突合 (可視 doc / role / attr 全部) + 可視 <b>token</b> == attr。
chk "references: (token,doc,role) 順序突合 + 可視 <b>==attr" \
  "$(q '.references[] | [.token, .doc, .role] | @tsv' | while IFS=$'\t' read -r t d r; do printf '%s\t%s\t%s\n' "$(esc "$t")" "$(esc "$d")" "$(esc "$r")"; done)" \
  "$(perl -CSD -0777 -ne '
    while (/<div data-component="cross-doc-ref-chip" data-ref-token="([^"]*)" data-ref-role="([^"]*)"><span class="rf-token"><b>([^<]*)<\/b><\/span><span class="rf-arrow">[^<]*<\/span><span class="rf-doc">([^<]*)<\/span><span class="rf-role">([^<]*)<\/span><\/div>/g) {
      my ($tok,$role,$vtok,$doc,$vrole)=($1,$2,$3,$4,$5);
      if ($tok ne $vtok) { print "TOKEN-VIS:$tok\xe2\x89\xa0$vtok\n"; next; }
      if ($role ne $vrole) { print "ROLE-VIS:$role\xe2\x89\xa0$vrole\n"; next; }
      print "$tok\t$doc\t$role\n";
    }
  ' "$BODY")"

# 7. cover-meta 4 KV 再導出突合。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 章の数 == |sections|章"   "$NSEC 章"               "$(printf '%s\n' "$meta_kv" | grep -F '章の数' | head -1 | cut -f2)"
chk "cover-meta 規範要件 == |requirements|件" "$NREQ 件 (EARS)"      "$(printf '%s\n' "$meta_kv" | grep -F '規範要件' | head -1 | cut -f2)"
chk "cover-meta 用語 == |glossary|語"     "$(q '.glossary | length') 語" "$(printf '%s\n' "$meta_kv" | grep -F '用語' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"          "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"             "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# 8. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"                   "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 9. prose スロット (perl で要素単位判定・3 mode)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-'"$CHKW"'s\n' "prose スロットが無い"; fail=1; fi
if [[ -n "$ARTIFACT" ]]; then
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
elif [[ -z "$FILLED_MANIFEST" ]]; then
  chk "prose スロットは全て空 (pre-fill, filled=0)" "0" "$filled"
else
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  exp="$(mktemp)"; act="$(mktemp)"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    printf '%s\t%s\n' "$key" "$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST") | sort > "$exp"
  perl -0777 -ne 'while (/<([a-zA-Z]+)\b[^>]*\bdata-slot-id="([^"]+)"[^>]*>(.*?)<\/\1>/gs){ print "$2\t$3\n"; }' "$BODY" | sort > "$act"
  if diff -q "$exp" "$act" >/dev/null 2>&1; then
    printf '  [OK]   %-'"$CHKW"'s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# ============================================================================
# 10. ★機械層 (machine free-prose) dual-audience floor — w1f cell-2 / ADR-0045。
#     生成物が 71 機械層 block + 要件 fold を canonical data-audience="machine" form で持ち、
#     REQ-DA-STRUCT-1..5 に適合する (folio_check_dual_audience 相当・bin/folio:865)。
# ============================================================================
# 件数 (contract 由来・silent drop / 偽 add を捕捉)。 fold = machine_blocks を持つ section 数 + (preamble 非空 ? 1 : 0)。
NPRE="$(q '.machine_preamble // [] | length')"
MB_PROSE="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="prose")) | length')"
MB_NOTE="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="note")) | length')"
MB_LIST="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | length')"
MB_LI="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | [.[].items[]] | length')"
# ★demoted (tr0 / verification・ADR-0040 機械層降格分): silent drop / 偽 add を件数で捕捉。
MB_DEMOTED="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="demoted")) | length')"
# ★dl (folio-aduv): dl.doc-meta = 旧 cell-1 の死角で silent drop されていた機械層 block。 raw emit 経路を足した以上
#   件数 pin も足す (件数無しだと 脱落/偽 add が §11 round-trip 以外どこにも出ない)。
MB_DL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="dl")) | length')"
SEC_WITH_MB="$(q '[.sections[] | select((.machine_blocks // []) | length > 0)] | length')"
EXP_FOLD="$SEC_WITH_MB"; [[ "$NPRE" -gt 0 ]] && EXP_FOLD="$((SEC_WITH_MB + 1))"
chk "spec-machine-prose == Σ machine prose"  "$MB_PROSE" "$(grep -c 'data-component="spec-machine-prose"' "$BODY")"
chk "spec-machine-note == Σ machine note"    "$MB_NOTE"  "$(grep -c 'data-component="spec-machine-note"' "$BODY")"
chk "spec-machine-list == Σ machine list"    "$MB_LIST"  "$(grep -c 'data-component="spec-machine-list"' "$BODY")"
chk "machine li (mli) == Σ machine list items" "$MB_LI"  "$(grep -c 'class="mli"' "$BODY")"
chk "spec-machine-demoted == Σ machine demoted" "$MB_DEMOTED" "$(grep -c 'data-component="spec-machine-demoted"' "$BODY")"
chk "spec-machine-dl == Σ machine dl"          "$MB_DL"      "$(grep -c 'data-component="spec-machine-dl"' "$BODY")"
chk "spec-machine-fold == sections(mb) + preamble" "$EXP_FOLD" "$(grep -c 'data-component="spec-machine-fold"' "$BODY")"

echo
echo "--- census-count (blocking arm・folio-jmmk): 容器 block / machine 部品の source DOM 静的件数 == contract 期待件数 ---"
# 機械/LLM 境界 (verification §3.9) の render 非依存 blocking 件数照合。 count_attr_token (quote 構文・属性名 case・数値
# 文字参照 非依存の occurrence 数え = SRS 499ab7b census-count arm と同規律) で data-component トークン件数を数え、 期待値は
# contract から自己導出 (DOM 非参照・contract-anchor)。 内容の順序値 chk (list=items / code=lines / table=cell / machine
# round-trip / fold グルーピング) は容器 block の *境界/個数* を 1:1 で守らない (空 block 追加・block 分割/併合・fold 再グルー
# ピングが順序値を素通る) ため占有 pin (folio-bur) が唯一 anchor。 本 arm は占有 pin de-scope (Phase C) 後も同強度で件数
# 照合を継承する static 後継 (sweep 分類表 = folio-3d23【B2 占有pin sweep 成果物】の第 1 層無し唯一 anchor)。
chk "census-count: spec-list-block == |list blocks|"            "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"   "$(count_attr_token data-component spec-list-block < "$BODY")"
chk "census-count: spec-code == |code blocks|"                  "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"   "$(count_attr_token data-component spec-code < "$BODY")"
chk "census-count: spec-table == |table blocks|"                "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"  "$(count_attr_token data-component spec-table < "$BODY")"
chk "census-count: spec-machine-list == |machine list blocks|"  "$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | length')" "$(count_attr_token data-component spec-machine-list < "$BODY")"
chk "census-count: spec-machine-fold == sections(mb) + preamble" "$(q '([.sections[] | select((.machine_blocks // []) | length > 0)] | length) + ([ ((.machine_preamble // []) | length), 1 ] | min)')" "$(count_attr_token data-component spec-machine-fold < "$BODY")"

# REQ-DA-STRUCT-3 (P-5): 全 live data-audience 値 ∈ {machine, human} (escape 済 code 例示は live tag でないので除外)。
bad_da="$(perl -CSD -0777 -ne 'while (/<[a-z]+\b[^>]*\sdata-audience="([^"]*)"/g){ print "$1\n" unless $1 eq "machine" || $1 eq "human"; }' "$BODY" | LC_ALL=C sort -u | tr '\n' ' ')"
chk_empty "REQ-DA-STRUCT-3: data-audience 値域 (machine|human のみ)" "$bad_da"
# REQ-DA-STRUCT-4: machine 部 (data-audience="machine" を持つ live tag) に aria-hidden が無い (AI/AT 不可視化禁止)。
aria_machine="$(perl -CSD -0777 -ne 'while (/<[a-z]+\b([^>]*)>/g){ my $a=$1; print "x\n" if $a=~/\sdata-audience="machine"/ && $a=~/\baria-hidden\b/; }' "$BODY" | wc -l | tr -d ' ')"
chk "REQ-DA-STRUCT-4: machine 部に aria-hidden 不在" "0" "$aria_machine"
# REQ-DA-STRUCT-1: 各 ears-requirement-row (data-audience="human") が data-audience="machine" 子孫 (rq-norm fold) を持つ。
#   tuple 突合 (§4) が row→rq-norm(machine) の構造隣接を literal 要求済 = NREQ tuple PASS が -1 の構造保証。 件数でも二重に固定。
chk "REQ-DA-STRUCT-1: human 要件 container 数 == |requirements|" "$NREQ" "$(grep -c 'data-component="ears-requirement-row" id="[^"]*" data-req-id="[^"]*" data-ears-pattern="[^"]*" data-audience="human"' "$BODY")"
chk "REQ-DA-STRUCT-1: machine fold (rq-norm) 数 == |requirements|" "$NREQ" "$(grep -c 'class="rq-norm" data-audience="machine"' "$BODY")"
# REQ-DA-STRUCT-2 (id 整合) / -5 (EARS-pattern 整合) は §4 要件タプル突合が enforce 済 (data-req-id==rid / class==EARS_CLASS[pattern])。
printf '  [OK]   %-'"$CHKW"'s %s\n' "REQ-DA-STRUCT-2/-5 (id/EARS-pattern 整合) は §4 tuple が enforce" "委譲"

# raw-emit (★二重 escape 検出): 機械層 raw HTML が壊れず emit されたか。 機械層 region に live inline tag が在り (raw 生存)、
#   機械層 fold 内に二重 escape 痕 (&lt;code&gt; 化けた wrapper) が無いことを確認。 厳密 fidelity は §11 round-trip が担う。
#   ★注: 機械層 prose は <code>&lt;p ...&gt;</code> 等の *正当な escape 済 HTML 例示* を含む (原文由来) ため
#   「&lt; が無い」検査はできない (false-positive)。 二重 escape の確定検出は §11 round-trip (原本テキストと差が出る) が担う。
mfold_region="$(perl -CSD -0777 -ne 'while (/<details data-component="spec-machine-fold"[^>]*>(.*?)<\/details>/gs){ print "$1"; }' "$BODY")"
chk "raw-emit: 機械層に live <code> 生存 (raw 生存)" "$([[ "$(printf '%s' "$mfold_region" | grep -c '<code>')" -gt 0 ]] && echo yes || echo no)" "yes"
chk "raw-emit: 機械層に live <a href 生存"          "$([[ "$(printf '%s' "$mfold_region" | grep -c '<a href=')" -gt 0 ]] && echo yes || echo no)" "yes"
chk "raw-emit: 機械層に live <span class=\"term\" 生存" "$([[ "$(printf '%s' "$mfold_region" | grep -c '<span class="term"')" -gt 0 ]] && echo yes || echo no)" "yes"

# ============================================================================
# 11. ★contract↔生成物 機械層テキスト 双方向 *順序付き* 一致 (round-trip fidelity)。
#     ★政策 A (folio-7n17 / ADR-0053): LEFT を snapshot でも live canonical でもなく
#     ★contract.machine_preamble[] + sections[].machine_blocks[] (25 block) から再構成する。
#     旧版は原本 (snapshot ORIG) を直 grep して LEFT にしていたが、 flip 後 ORIG==生成物 で自己比較恒真化する
#     ため、 政策 A では LEFT を edit-SSoT (contract) 由来へ re-home した。 RIGHT は生成物の機械層。
#     ★tr0: p/aside/ul/li に加え div.demoted (ADR-0040 機械層降格分) と dl も対象 (contract type / 生成物 component 対称)。
#     双方向 (完全性 = contract の全機械層が生成物に / no-fabrication = 生成物の機械層が全て contract に) を照合する。
#     ★順序付き (集合でない): 両側を sort せず document 順の配列のまま diff する (人間層 §4/§5 と対称)。
#       - 順序保存: 機械層 block の document 順を enforce → 同型 block の入替を捕捉。
#       - section 帰属: machine_blocks[] は section ごとに連続して emit される (build()/emit_section) ため、
#         ある block を別 section の fold へ移すと document 順が contract 順とずれる → cross-section 誤帰属も検出。
#     ★本 arm が守るのは assembler バグ (生成物が contract から乖離): silent drop / 順序入替 / cross-section 誤帰属 /
#       二重 escape。 ★両側 contract 由来ゆえ ★両側同時退行 (extractor collapse) では vacuous PASS しうる →
#       §10b 凍結 census + extractor-collapse 敵対 test が塞ぐ (mandate: (a)(b) は両側 contract 由来ゆえ (c) で塞ぐ)。
# ============================================================================
NMB_TOTAL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | length')"
# ★ORIG (snapshot) = 政策 A で census / round-trip の【非消費】へ転換 (bootstrap 記録として残置)。 §10b / §11 の
#   存在 fail-closed pin (照合不能 silent skip の回帰 pin・M15) のみが ORIG を参照する (内容不読)。 snapshot の
#   provenance (folio-lwhz land) = `git show c705c75:design-intent/spec/verification.html | sed 's|<dd>1\.1\.0</dd>|<dd>1.2.0</dd>|g'`。
#   snapshot は cell 内改変禁止 (selftest が sha256 pin + 非消費 assert で保護・ADR-0053 に去就を記載)。
ORIG="${SPEC_ORIGIN_HTML:-$SCRIPT_DIR/spec-origin/verification.origin.html}"

# ============================================================================
# 10b. ★literal census arm (folio-7n17 政策 A・snapshot oracle bootstrap 退役後の恒久防御 (a))。
#   ★政策 A への転換 (user 裁定 2026-07-18 / ADR-0053): 旧 arm は ORIG (=snapshot 既定・flip 後 生成物) と
#     HTML の ★相対 parity (c_xref(ORIG) vs c_xref(HTML)) を撃っていたが、 flip 後 ORIG==生成物 で ★自己比較
#     恒真化する (verify-verification.sh 旧:461-464 実証)。 政策 A はこれを撤去し、 expected を canonical /
#     artifact / 生成物から【導出しない】★凍結 literal (spec-origin/verification.frozen-census.txt) とし、
#     measured 側を ★生成物 HTML (verify の subject) へ固定する。 ORIG は census を【消費しない】 (下記存在 pin のみ)。
#   ★なぜ独立 anchor が要るか: §4/§5 の rich 突合は全て「contract vs 生成物」で ★両側同時退行で vacuous PASS
#     する (extractor が plain() へ戻ると contract も生成物も同時に rich を失う = mandate HIGH-4)。 凍結 literal
#     census は両側と独立ゆえ、 collapse しても frozen 31 vs 生成物 6 で FAIL する (test-adversarial の collapse
#     test / 本番自己比較 MK が red→green で実証)。
#   ★ORIG 存在 fail-closed pin は【存置】(照合不能 silent skip の回帰 pin・M15)。 snapshot file は bootstrap
#     記録として残置し census は消費しない (非消費 = selftest の非消費 assert + hash pin が cell 内改変を FAIL に)。
# ============================================================================
# 凍結 census 読み取り (frozen literal SSoT・source せず grep で読む = tab / bracket / quote 安全)。
FROZEN_CENSUS="$SCRIPT_DIR/spec-origin/verification.frozen-census.txt"
[[ -f "$FROZEN_CENSUS" ]] || { echo "verify-spec: ★凍結 census 不在 (政策A anchor 喪失・fail-closed): $FROZEN_CENSUS" >&2; exit 2; }
fz()     { grep -m1 "^$1=" "$FROZEN_CENSUS" | sed "s/^$1=//"; }                                  # scalar
fz_ld()  { grep -m1 "^FZ_STAKEHOLDERS_LD=" "$FROZEN_CENSUS" | sed 's/^FZ_STAKEHOLDERS_LD=//'; }  # 型\t値 (tab 保持)
fz_set() { sed -n "/#BEGIN_$1/,/#END_$1/p" "$FROZEN_CENSUS" | grep -vE '^#'; }                    # id / delta set

# ★inert region 除去 (folio-7wbn ceiling major fix・parser-differential 封鎖)。
#   census の regex counter は raw HTML を素で舐めるため、 ★HTML コメント (<!-- ... -->) と <script>/<style> の
#   text 本体に書かれた「タグ様文字列」を live 要素として数えてしまう。 これは政策A の【唯一の独立 anchor】を
#   edit-SSoT (contract) 側から水増し/目減りさせる laundering 経路になる:
#     - deflate/laundering: live な a.xref を 1 個失っても `<!-- <a class="xref"></a> -->` を 1 個足せば凍結値へ復元でき、
#       COLLAPSE-2 が守る性質 (両側同時退行の捕捉) が破れる。 contract の machine_blocks[].html は raw 出力ゆえ到達可能。
#     - false-FAIL: 機械層 block に正当なコメント (タグ様文字列を含む) を 1 つ書くだけで census が偽 FAIL する。
#   ★同一 arm 内で計数方式を揃える: h_inline は実 HTML parser で subtree 境界を読む (parser-differential 回避) 一方、
#   regex counter だけが naive だった。 そこで ★実 HTML parser (html.parser) で comment / script / style の span を
#   特定し、 その ★raw byte 範囲だけを除去した view を作り、 後段の計数はその view に対して走らせる。
#   (parser を「除去範囲の特定」にのみ使い本文は byte 保存する。)
#   ★★本 view だけでは足りない (folio-7wbn 2 巡目 ceiling major・attribute laundering): comment / script / style を
#   除いても ★属性値 は raw byte として残るため、 naive regex counter は単引用符属性の中のタグ様文字列を live 要素として
#   数えてしまう (例 `<div data-note='<a class="xref" href="#z">z</a>'>` で c_xref が +1 / `data-x='<section id="s5-delta">'`
#   で id census も復元できる = CEN-id1/id2・CEN-rich1/2・COLLAPSE-2 の teeth が同一クラスの手で破れる)。
#   ゆえに ★全 census 計数 (id / a.xref / span.term / ins|del.delta / delta-id / escape literal) を regex から
#   ★実 HTML parser の walk (census_dump) へ寄せた: 属性値は attrs として構造的に読まれ本文計数へ混入しえず、
#   escape literal (&lt;a class="xref" 等) は ★text node 限定 (entity 記法を復元して) 数える。 comment / script /
#   style は parser 段でも非計数。 ★この結果 strip_inert 前処理は冗長となり (計数側が単独で成立する)、 かつ bogus
#   comment のオフセット誤算という fail-open を持つため ★両 arm とも census subject から外してある (folio-gt4s・下記隔離注記)。
strip_inert() { python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys
src = open(sys.argv[1], encoding='utf-8').read()
starts = []; acc = 0
for line in src.splitlines(keepends=True):
    starts.append(acc); acc += len(line)
starts.append(acc)
def off(pos):
    ln, col = pos
    return starts[ln - 1] + col
class S(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False); self.cuts = []; self.raw = None
    def handle_comment(self, data):          # <!-- ... --> = 4 + len + 3 byte
        s = off(self.getpos()); self.cuts.append((s, s + len(data) + 7))
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'): self.raw = tag
    def handle_data(self, data):             # CDATA mode ゆえ raw text と 1:1
        if self.raw:
            s = off(self.getpos()); self.cuts.append((s, s + len(data)))
    def handle_endtag(self, tag):
        if tag == self.raw: self.raw = None
p = S(); p.feed(src); p.close()
out = []; prev = 0
for a, b in p.cuts:
    if a < prev: continue
    out.append(src[prev:a]); prev = b
out.append(src[prev:])
sys.stdout.write(''.join(out))
PYEOF
}
# ★★【隔離中・census は本 view を消費しない】(folio-7st6 ceiling major fix)。
#   strip_inert には ★bogus comment のオフセット誤算 という fail-open 欠陥がある: handle_comment は cut 終端を
#   `s + len(data) + 7` (= `<!--` 4 byte + `-->` 3 byte の決め打ち) で算出するが、 Python html.parser は
#   ★bogus comment `<!x>` (実長 4 byte) に対しても handle_comment(data='x') を発火するため、 計算長 8 で
#   ★直後の live 4 byte を過剰削除する。 実測: `A<!x><template><code>z</code></template>B`
#   → `Aplate><code>z</code></template>B` で <template> 開始タグが破壊され ★中身が live 化する。
#   ゆえに本 view を census subject にすると、 `<!x>` を 4 byte 前置するだけで <template> inert 除外が破れ、
#   (1) inflate (decoy 注入で凍結値が動く) と (2) deflate/laundering (live 資産を剥奪しても凍結値へ「復元」できる)
#   の ★両方向 が再開通する = 政策 A の【唯一の独立 anchor】の fail-open (実測再現済・CEN-tpl6/7 が pin)。
#   ★修正方針 (finding 提案 A = 呼び先のみ是正): census_dump / h_inline は ★共に実 HTML parser であり、
#   comment / script / style を非計数・<template> を除外 ★済 ゆえ、 strip_inert 前処理は「二重の帯」ではなく
#   ★実際には唯一の穴 だった。 よって census subject を RAW $HTML へ戻す (実測: 生 $HTML で 31/57/79 = 凍結一致)。
#   ★関数本体 (strip_inert) は契約 (a) の verify-spec.sh からの byte-identical 逐語移植ゆえ ★改変しない。
#   同一欠陥は rules arm (verify-spec.sh) にも存在したが、 ★folio-gt4s で ★両 arm 同時に 同じ経路 (呼び先のみ
#   RAW $HTML へ切替・本体は無改変) で是正済 = 現在は ★両 arm とも strip_inert を消費しない対称形。
#   ★本注記だけを唯一の記録にしない (回避表記封鎖 = c5r.2・追跡は folio-gt4s / folio-7st6)。
#   ★本 view は構造 parity 維持のため生成のみ残置し ★どの census も消費しない。 再配線するなら先に本体を直すこと。
HTML_LIVE="$(mktemp)"
strip_inert "$HTML" > "$HTML_LIVE" || { echo "verify-spec: ★census live view 生成に失敗 (fail-closed): $HTML" >&2; exit 2; }
[[ -s "$HTML_LIVE" ]] || { echo "verify-spec: ★census live view が空 (fail-closed): $HTML" >&2; exit 2; }

# ★census 計数 helper (census subject = 生成物 HTML の ★RAW byte / ORIG は非消費・上記隔離注記を参照)。
#   ★実 HTML parser の 1 walk で全軸を出す (attribute laundering 封鎖・上記 ★★参照):
#     - element 軸 (id / a.xref / span.term / ins|del.delta / delta-id) は starttag の ★attrs から数える
#       (属性値の中に書かれたタグ様文字列は attrs の ★値 でしかなく、 要素として計上されえない)。
#     - escape literal 軸 (&lt;a class="xref" / &lt;code / &lt;span) は ★text node のみ から数える
#       (entityref / charref を元記法へ復元して連結。 属性値・comment・script/style 本文は非計数)。
#   出力形式: `KEY=n` 行 → `#IDS` 節 (navigable id) → `#DIDS` 節 (delta-id)。
# ★【是正済・folio-gt4s】自己閉じ形 `<template/>` による element 軸の 1 byte 迂回は handle_startendtag を
#   ★HTML 準拠 (非 void の trailing solidus は無視され template を ★開く) へ寄せて封鎖済:
#   `self._tag(tag, attrs); if tag in INERT_SUBTREE: self.stack.append(tag)` (★両 arm へ逐字同一に適用)。
#   ★push を INERT_SUBTREE のみ に絞るのが要点: `if tag not in VOID` 相当だと canonical の SVG foreign content
#   (`<path/>` 等) が閉じられず stack を汚染し、 region / inert 判定を巻き添えで壊す (別クラスの誤計数)。
#   text/inline 軸 (h_inline) の同一迂回は folio-7st6 で是正済 (下記 h_inline.handle_startendtag)。
#   ★本体へ手を入れる際は ★両 arm 同時 に逐字同一で行う (片 arm のみの改変は cross-arm 非対称の新設)。
census_dump() { python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys, re
VOID={'br','img','meta','link','input','hr','wbr','source','col','area','base','embed','param','track'}
# ★非描画 subtree (folio-7wbn 3 巡目 ceiling major fix): <template> の内容は browser が ★描画しない
#   (inert DocumentFragment) ため「live 資産」ではなく census が数えてはならない。 数えると comment / 属性値と
#   ★同一クラス の laundering 経路が開く: live な a.xref を 1 個失っても
#   `<template><a class="xref" href="#z">z</a></template>` を 1 個足せば凍結 26 へ「復元」でき、
#   COLLAPSE-2 が守る性質 (両側同時退行を独立 anchor が捕捉する) が破れる (実測再現済)。
#   到達性は comment / 属性 vector と同じ (contract.machine_blocks[].html は raw 出力・extractor は原本 inner HTML を
#   逐語 capture)。 ★element 軸 (id / a.xref / span.term / delta) と ★text 軸 (escape literal) の ★両方 を除外する
#   (片方だけだと escape literal 側に同じ穴が残る)。
#   ★noscript は除外しない: scripting 無効時には ★描画される = live たりうるため、 除外すると逆に「正当な資産の
#   数え落とし」= 偽 FAIL / 隠し場所を作る。 除外の対象は「どの条件でも描画されない」template に限る。
#   ★raw text / RCDATA 要素も inert に含める (folio-gt4s errata-1 MUST-3)。 通常形は html.parser の CDATA mode が
#   中身をタグとして emit しないため実害が無かったが、 ★自己閉じ形 `<script/>` `<xmp/>` 等は handle_startendtag
#   発火ゆえ CDATA mode に入らず、 browser が閉じタグまで raw text (= 要素として描画しない) 扱いする区間を
#   census が ★live 計上 していた (実測: 凍結値復元が成立)。
#   ★集合は ★手書き列挙せず parser 自身から導出する (partial-enumeration trap の回避): {'script','style'} だけを
#   手書きした版は textarea / title / xmp / iframe / noembed / noframes の自己閉じで ★同一クラスが再開通した。
#   html.parser が自ら宣言する CDATA / RCDATA 集合を土台にすれば、 parser の認識と census の inert 判定が
#   ★構造的に同期する (parser 側が集合を増やせば census も自動追随し、 列挙漏れが原理的に生じない)。
#   ★noscript は入らない (導出集合に含まれない) = 正しい: scripting 無効時には ★描画される = live たりうるため、
#   除外すると逆に「正当な資産の数え落とし」= 偽 FAIL / 隠し場所を作る (folio-7wbn 裁定を維持)。
#   ★INERT_SUBTREE へ足す形ゆえ handle_startendtag の最小形 (契約固定) を ★逐字そのまま 使える
#   (push 条件が `tag in INERT_SUBTREE` ゆえ全 raw text 要素が同経路で inert 区間になる)。
#   canonical に該当要素の自己閉じは 0 件 (grep verified) ゆえ正当な資産の計数には無影響。
# ★RAWTEXT 系 / element 系の分離 (folio-ahn3)。 両者は「中身を描画しない」点で同じ inert だが ★閉じ方の
#   semantics が違う: RAWTEXT 系 (CDATA / RCDATA) は ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列 —
#   一方 template は通常の element ゆえ入れ子構造を持つ。 集合の ★実体は不変 (INERT_SUBTREE は従来と同一) で、
#   ★自己閉じ経路に CDATA mode を与えるための ★名前付き部分集合 を切り出すだけ (parser 由来導出も従来どおり
#   維持 = 手書き列挙による partial-enumeration trap を再導入しない)。
RAWTEXT_INERT = (set(HTMLParser.CDATA_CONTENT_ELEMENTS)
    | set(getattr(HTMLParser, 'RCDATA_CONTENT_ELEMENTS', ('textarea', 'title'))))
INERT_SUBTREE = {'template'} | RAWTEXT_INERT
class C(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack=[]; self.raw=None; self.ids=[]; self.dids=[]; self.text=[]
        self.n_xref=0; self.n_term=0; self.n_delta=0
    def inert(self):
        return any(t in INERT_SUBTREE for t in self.stack)
    def _tag(self, tag, attrs):
        if self.inert(): return
        d={}
        for k,v in attrs:
            if k not in d: d[k] = v if v is not None else ''
        if d.get('id'): self.ids.append(d['id'])
        cls = d.get('class') or ''
        if tag=='a' and 'xref' in cls.split(): self.n_xref+=1
        if tag=='span' and cls=='term' and 'data-term' in d: self.n_term+=1
        if tag in ('ins','del') and cls=='delta' and 'data-delta-id' in d:
            self.n_delta+=1; self.dids.append(d['data-delta-id'])
    def handle_starttag(self, tag, attrs):
        self._tag(tag, attrs)
        if tag in ('script','style'): self.raw=tag
        if tag not in VOID: self.stack.append(tag)
    def handle_startendtag(self, tag, attrs):
        # ★自己閉じ形 `<template/>` の 1 byte 迂回封鎖 (folio-gt4s・element 軸)。 HTML Standard では非 void 要素の
        #   trailing solidus は無視され `<template/>` は template を ★開く (中身は inert)。 一方 Python html.parser は
        #   本 hook を発火し stack へ push しないため INERT_SUBTREE 判定が効かず、 element 軸だけ 1 文字で
        #   inert 除外を迂回できていた (実測再現済)。 ★push は inert 判定に必要な template のみ に限る:
        #   canonical は SVG foreign content (`<path/>` 等) を持ち、 これらは自己閉じが ★正規 ゆえ無条件に push すると
        #   閉じられず stack を汚染し、 region / inert 判定を巻き添えで壊す (fail-closed でなく ★別クラスの誤計数)。
        # ★RAWTEXT 系は push ★だけ では足りない (folio-ahn3)。 push は「中身を数えない」を作るが、 HTML5 の
        #   raw text 区間は ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列 という semantics を持つ。
        #   push のみだと html.parser は区間内の `<template>` 等を ★実タグとして emit し stack へ積むため、
        #   後続の `</script>` が (最内 inert = template に阻まれ) 自分自身を閉じられず inert が解除されない。
        #   結果 attacker は `<script/><template></script>…</template></script>` で「browser では ★描画される
        #   のに census は数えない」★有界な盲点 (他 census 値は無傷) を 8 タグ × 両軸で作れた (実測・base
        #   8d4eeda からの pre-existing)。 ★是正は parser 自身の CDATA mode を ★自己閉じ経路にも与えること:
        #   set_cdata_mode により区間は handle_data へ流れ (= タグとして emit されない)、 `</script>` が
        #   handle_endtag を発火して inert を ★正しく閉じ、 以降が live 計上へ戻る (ground truth 一致)。
        #   ★push は撤去しない (追加であって置換ではない): set_cdata_mode 単独だと raw 区間の handle_data が
        #   stack 上の inert 不在ゆえ text 軸 (escape literal) を汚染する。 push が inert() を真に保つ。
        self._tag(tag, attrs)
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
        if tag in INERT_SUBTREE: self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag==self.raw: self.raw=None
        # ★inert subtree は ★scope 境界 (folio-gt4s errata-1 MUST-4)。 素朴な `del self.stack[i:]` は ★祖先 に
        #   一致する end tag でも inert を巻き取って外すため、 stray end tag 1 本で inert 区間が解除され中身が
        #   live 計上された。 HTML5 では inert 内の不一致 end tag は無視され (raw text 内なら ★ただの文字列)
        #   inert は開いたまま = 中身は非描画。
        #   ★探索下限は ★最内 inert 位置から ★無条件に 導出する (以前は `tag not in INERT_SUBTREE` のときだけ
        #   導出していたため、 inert 名の end tag が ★入れ子 inert を外から閉じられた:
        #   `<template><script/></template>` で凍結値復元が成立・実測)。 inert 名の end tag は ★最内 inert 自身
        #   のみを閉じうる (lo=m)、 それ以外は最内 inert より ★内側 のみ (lo=m+1)。 inert 不在なら従来どおり全域。
        #   ★★この scope 境界の ★捕捉範囲 (宣言能力 == 実能力・errata-2 MUST-B / ★folio-ahn3 で
        #   ★HTML 名前空間の当該形を閉塞・★foreign content 経由は ★未閉塞):
        #     ★捕れる = element 系 inert (template) の scope 境界 / 正しく閉じた入れ子 inert /
        #               指定 2 shape (<template><script/></template> / <template><textarea/></template>)。
        #               per-shape MK (CEN-nest1/2/3/5) で実弾 pin 済。 ★逆順 shape (<script/><template></script>)
        #               は folio-ahn3 の是正で ★捕捉対象から外れた: `</script>` が raw text を閉じ後続は
        #               ground truth どおり ★live ゆえ、 剥奪分を live 資産で復元する形は ★正当 (既 admin 裁定
        #               「実描画される注入での復元は MK にしない」と同クラス)。 CEN-nest4 は ★期待反転 で保持され
        #               (admin 裁定 2026-07-21)、 「後続が live 計上される」ground truth 整合を pin する。
        #     ★閉塞済 (folio-ahn3・★HTML 名前空間 に限る) = RAWTEXT 系 inert (script/style/xmp/iframe/
        #               noembed/noframes/textarea/title) を ★自己閉じで開いた後に別の inert 開始タグを挟み
        #               ★末尾で閉じ直す 形 (例 `<script/><template></script>…</template></script>`)。 かつては
        #               挟んだ区間の資産が census の ★有界な盲点 になっていた (他の census 値は無傷・8 タグ ×
        #               両軸で同型・実測。 ★base 8d4eeda から存在した pre-existing)。 ★是正済: handle_startendtag
        #               が RAWTEXT 系に set_cdata_mode を与えるため区間内のタグは emit されず (= 挟めない)、
        #               自分の end tag が inert を正しく閉じて以降は live 計上へ戻る。 CEN-rawnest 群が 8 タグ ×
        #               両軸 × 両 arm で per-shape に実弾 pin し、 SETCDATA 存在 pin が producer 側を静的に押さえる。
        #     ★未閉塞 (★同族・foreign content 経由・★live fail-open) = `<svg>` / `<math>` 内の ★自己閉じ RAWTEXT。
        #               foreign content では自己閉じが ★正規に閉じる ため実 browser は raw text を ★開かない が、
        #               本 census は set_cdata_mode を ★名前空間非依存 に与えるため raw 区間を開いてしまい、
        #               attacker は末尾の stray end tag で閉じ直せる。 ★実測 fixture (両 arm 同一結果):
        #                 <html><body><svg><script/></svg><div id="INJ"></div><code>zz</code>&lt;span
        #                 </script><div id="tail"></div></body></html>
        #               → IDS=[tail] のみ (INJ ★非計数) / ESC_SPAN=0 / 人間層 code=0 なのに tail は計上され続ける
        #               = ★他 census 値は無傷 の同族 bounded blind spot。 ground truth (html5lib) では INJ の
        #               ancestor chain = ['html','body','div'] = ★実描画。 同型が `<math><style/></math>…</style>` /
        #               `<svg><textarea/></svg>…</textarea>` でも再現 (CDATA / RCDATA 双方)。
        #               ★base c55bac6 でも同一挙動 = pre-existing (folio-ahn3 の退行ではない)。 fix は名前空間
        #               追跡を要する parser semantics の再設計で本 cell の契約 (3 分岐の逐字温存) の外ゆえ
        #               ★folio-3z10 として ★起票済 (admin 裁定 2026-07-21)。 本 cell は ★宣言を実能力へ縮小する
        #               に留める (「全クラス閉塞」と書けば次の cell が探索を打ち切る = false record ゆえ書かない。
        #               「ついでに塞ぐ」も禁止 = 契約 fence 外)。
        m=-1
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i] in INERT_SUBTREE: m=i; break
        lo = 0 if m<0 else (m if tag in INERT_SUBTREE else m+1)
        for i in range(len(self.stack)-1,lo-1,-1):
            if self.stack[i]==tag: del self.stack[i:]; break
    def handle_data(self, data):
        if not self.raw and not self.inert(): self.text.append(data)
    def handle_entityref(self, name):
        if not self.raw and not self.inert(): self.text.append('&'+name+';')
    def handle_charref(self, name):
        if not self.raw and not self.inert(): self.text.append('&#'+name+';')
p=C(); p.feed(open(sys.argv[1], encoding='utf-8').read()); p.close()
t=''.join(p.text)
print('C_XREF=%d' % p.n_xref)
print('C_TERM=%d' % p.n_term)
print('C_DELTA=%d' % p.n_delta)
print('ESC_XREF=%d' % len(re.findall(r'&lt;a class="xref"', t)))
print('ESC_CODE=%d' % len(re.findall(r'&lt;code', t)))
print('ESC_SPAN=%d' % len(re.findall(r'&lt;span', t)))
# ★ID_TOTAL = dedup ★前 の総出現数 (folio-7wbn 3 巡目 ceiling major fix)。 下段 #IDS 節は set() で dedup するため、
#   ★既存 id の複製注入 (例 <div id="s5-delta"></div> を body 直後へ) は count census (unique 58) でも SET census でも
#   原理的に検出できず verify を rc=0 で素通っていた (実測再現済)。 HTML の fragment 解決は文書順 first-match ゆえ、
#   本文より前へ空の複製 anchor を置くと当該 id を指す全 xref がその空要素へ ★hijack され navigation が壊れる。
#   unique == 総出現 を ★構造的不変条件 として撃つ (凍結 literal を増やさない = census file / provenance sha 無改訂)。
print('ID_TOTAL=%d' % len(p.ids))
print('#IDS')
for i in sorted(set(p.ids)): print(i)
print('#DIDS')
for i in sorted(set(p.dids)): print(i)
PYEOF
}
# generic inline (code/span) の ★人間層 (data-audience="machine" subtree の外) occurrence を region 別に数える。
#   実 HTML parser で ancestor を辿る (naive tag-strip regex は subtree 境界を読めず parser-differential を生む)。
h_inline() { python3 - "$1" "$2" "$3" <<'PYEOF'
from html.parser import HTMLParser
import sys
VOID={'br','img','meta','link','input','hr','wbr','source','col','area','base','embed','param','track'}
# ★非描画 subtree 集合 (census_dump の INERT_SUBTREE と ★同一 導出・folio-gt4s errata-1 MUST-3)。
#   template に加え raw text / RCDATA 要素を含める: 通常形は html.parser の CDATA mode が中身をタグとして
#   emit しないため実害が無かったが、 ★自己閉じ形 `<script/>` `<xmp/>` 等は handle_startendtag 発火ゆえ
#   CDATA mode に入らず、 browser が閉じタグまで raw text (非描画) 扱いする区間の <code> / <span> を
#   ★live 計上 していた (実測: 凍結値復元が成立)。
#   ★手書き列挙せず parser 自身から導出する (partial-enumeration trap の回避): {'script','style'} だけを
#   手書きした版は textarea / title / xmp / iframe / noembed / noframes の自己閉じで同一クラスが再開通した。
#   ★noscript は導出集合に含まれない = 正しい (scripting 無効時に描画されるため除外しない・folio-7wbn 裁定)。
# ★RAWTEXT 系 / element 系の分離 (folio-ahn3・census_dump の RAWTEXT_INERT と ★同一 導出)。 RAWTEXT 系は
#   ★自分の end tag だけ が閉じ間のタグは ★ただの文字列 という semantics を持つため、 自己閉じ経路へ
#   CDATA mode を与える必要がある (下記 handle_startendtag)。 集合の ★実体は不変 (INERT は従来と同一)。
RAWTEXT_INERT = (set(HTMLParser.CDATA_CONTENT_ELEMENTS)
    | set(getattr(HTMLParser, 'RCDATA_CONTENT_ELEMENTS', ('textarea', 'title'))))
INERT = {'template'} | RAWTEXT_INERT
class W(HTMLParser):
    def __init__(self, target, region):
        super().__init__(convert_charrefs=False); self.stack=[]; self.n=0
        self.target=target; self.region=region
    def inert(self):
        return any(t in INERT for t,_ in self.stack)
    def handle_starttag(self, tag, attrs):
        # ★重複属性は ★first-wins (folio-7st6 ceiling major fix)。 HTML Standard では 2 つ目以降の同名属性は
        #   parse error として ★破棄 される (最初が勝つ)。 dict(attrs) は last-wins ゆえ
        #   `<div data-audience="machine" data-audience="human">` を browser は機械層と解釈するのに h_inline は
        #   人間層として計上し、 live 資産 1 個剥奪 → 重複属性で偽の人間層資産 1 個注入 で凍結値へ復元できた
        #   (= CEN-tpl4/M18 が守る性質が同一クラスの手で破れる)。 census_dump は既に first-wins ゆえ
        #   ★同一 walk 内の計数規約を揃える (intra-arm 非対称の解消)。
        d={}
        for k,v in attrs:
            if k not in d: d[k] = v if v is not None else ''
        # ★非描画 subtree 除外 (census_dump と同型・folio-7wbn 3 巡目 ceiling): <template> 内は描画されないため
        #   live inline 資産でない。 除外しないと td/figcaption へ <template><code>z</code></template> を置くだけで
        #   region 別 occurrence を水増しでき、 element 軸を閉じた意味が無くなる (計数方式を arm 内で揃える)。
        if tag==self.target and not self.inert():
            if not any(a.get('data-audience')=='machine' for _,a in self.stack):
                r='rest'
                for t,a in reversed(self.stack):
                    cls=a.get('class') or ''
                    if t in ('td','th'): r='table-cell'; break
                    if t=='figcaption' or 'caption' in cls: r='caption'; break
                if self.region=='human' or self.region==r: self.n+=1
        if tag not in VOID: self.stack.append((tag,d))
    def handle_startendtag(self, tag, attrs):
        # ★自己閉じ形 `<template/>` の 1 byte 迂回封鎖 (folio-7st6 ceiling major fix)。
        #   HTML Standard では ★非 void 要素の trailing solidus は無視され `<template/>` は template を ★開く
        #   (後続内容は browser で描画されない = inert)。 一方 Python html.parser は handle_startendtag を発火し、
        #   base 既定は starttag→endtag を続けて呼ぶため push 直後に pop され ★inert 区間にならなかった。
        #   結果 `<template/>` 1 形で CEN-tpl4/8 が封鎖した laundering クラスが丸ごと再開通していた (実測再現済)。
        #   ★HTML 準拠に合わせ「開始タグとして扱う」へ是正する。 ただし ★開いたままにするのは inert 判定に必要な
        #   template のみ に限る: canonical は SVG foreign content (`<path/>` 16 / `<circle/>` 3) を持ち、 これらは
        #   自己閉じが ★正規 ゆえ無条件に push すると閉じられず stack を汚染し、 後続の region 判定と
        #   data-audience="machine" 判定を巻き添えで壊す (fail-closed でなく ★別クラスの誤計数 になる)。
        # ★RAWTEXT 系は push ★だけ では足りない (folio-ahn3・census_dump と ★同型)。 HTML5 の raw text 区間は
        #   ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列。 push のみだと区間内の `<template>` 等が
        #   ★実タグとして emit され stack へ積まれ、 後続の `</script>` が最内 inert に阻まれて自分を閉じられず
        #   inert が解除されない → `<script/><template></script>…</template></script>` で「browser では描画される
        #   のに census は数えない」★有界な盲点 が 8 タグ × 両軸に開いていた (実測・base 8d4eeda から pre-existing)。
        #   ★是正は parser 自身の CDATA mode を自己閉じ経路へ与えること (set_cdata_mode)。 ★push は撤去しない
        #   (追加であって置換ではない): 単独適用だと raw 区間が region / machine 判定へ素通りする。
        self.handle_starttag(tag, attrs)
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
        if tag not in INERT and self.stack and self.stack[-1][0] == tag: self.stack.pop()
    def handle_endtag(self, tag):
        # ★inert subtree は ★scope 境界 (census_dump と同型・folio-gt4s errata-1 MUST-4)。 素朴な
        #   `del self.stack[i:]` は ★祖先 に一致する stray end tag でも inert を巻き取って外すため、
        #   stray end tag 1 本で inert 区間が解除され中身が live 計上された。 HTML5 では inert 内の不一致
        #   end tag は無視され (raw text 内なら ★ただの文字列) inert は開いたまま = 非描画。
        #   ★探索下限は ★最内 inert 位置から ★無条件に 導出する (以前は `tag not in INERT` のときだけ導出して
        #   いたため、 inert 名の end tag が ★入れ子 inert を外から閉じられた: `<template><script/></template>`
        #   で凍結値復元が成立・実測)。 inert 名の end tag は ★最内 inert 自身のみを閉じうる (lo=m)、
        #   それ以外は最内 inert より ★内側 のみ (lo=m+1)。 inert 不在なら従来どおり全域。
        #   ★★この scope 境界の ★捕捉範囲 (宣言能力 == 実能力・errata-2 MUST-B / ★folio-ahn3 で
        #   ★HTML 名前空間の当該形を閉塞・★foreign content 経由は ★未閉塞):
        #     ★捕れる = element 系 inert (template) の scope 境界 / 正しく閉じた入れ子 inert /
        #               指定 2 shape (<template><script/></template> / <template><textarea/></template>)。
        #               per-shape MK (CEN-nest1/2/3/5) で実弾 pin 済。 ★逆順 shape (<script/><template></script>)
        #               は folio-ahn3 の是正で ★捕捉対象から外れた: `</script>` が raw text を閉じ後続は
        #               ground truth どおり ★live ゆえ、 剥奪分を live 資産で復元する形は ★正当 (既 admin 裁定
        #               「実描画される注入での復元は MK にしない」と同クラス)。 CEN-nest4 は ★期待反転 で保持され
        #               (admin 裁定 2026-07-21)、 「後続が live 計上される」ground truth 整合を pin する。
        #     ★閉塞済 (folio-ahn3・★HTML 名前空間 に限る) = RAWTEXT 系 inert (script/style/xmp/iframe/
        #               noembed/noframes/textarea/title) を ★自己閉じで開いた後に別の inert 開始タグを挟み
        #               ★末尾で閉じ直す 形 (例 `<script/><template></script>…</template></script>`)。 かつては
        #               挟んだ区間の資産が census の ★有界な盲点 になっていた (他の census 値は無傷・8 タグ ×
        #               両軸で同型・実測。 ★base 8d4eeda から存在した pre-existing)。 ★是正済: handle_startendtag
        #               が RAWTEXT 系に set_cdata_mode を与えるため区間内のタグは emit されず (= 挟めない)、
        #               自分の end tag が inert を正しく閉じて以降は live 計上へ戻る。 CEN-rawnest 群が 8 タグ ×
        #               両軸 × 両 arm で per-shape に実弾 pin し、 SETCDATA 存在 pin が producer 側を静的に押さえる。
        #     ★未閉塞 (★同族・foreign content 経由・★live fail-open) = `<svg>` / `<math>` 内の ★自己閉じ RAWTEXT。
        #               foreign content では自己閉じが ★正規に閉じる ため実 browser は raw text を ★開かない が、
        #               本 census は set_cdata_mode を ★名前空間非依存 に与えるため raw 区間を開いてしまい、
        #               attacker は末尾の stray end tag で閉じ直せる。 ★実測 fixture (両 arm 同一結果):
        #                 <html><body><svg><script/></svg><div id="INJ"></div><code>zz</code>&lt;span
        #                 </script><div id="tail"></div></body></html>
        #               → IDS=[tail] のみ (INJ ★非計数) / ESC_SPAN=0 / 人間層 code=0 なのに tail は計上され続ける
        #               = ★他 census 値は無傷 の同族 bounded blind spot。 ground truth (html5lib) では INJ の
        #               ancestor chain = ['html','body','div'] = ★実描画。 同型が `<math><style/></math>…</style>` /
        #               `<svg><textarea/></svg>…</textarea>` でも再現 (CDATA / RCDATA 双方)。
        #               ★base c55bac6 でも同一挙動 = pre-existing (folio-ahn3 の退行ではない)。 fix は名前空間
        #               追跡を要する parser semantics の再設計で本 cell の契約 (3 分岐の逐字温存) の外ゆえ
        #               ★folio-3z10 として ★起票済 (admin 裁定 2026-07-21)。 本 cell は ★宣言を実能力へ縮小する
        #               に留める (「全クラス閉塞」と書けば次の cell が探索を打ち切る = false record ゆえ書かない。
        #               「ついでに塞ぐ」も禁止 = 契約 fence 外)。
        m=-1
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0] in INERT: m=i; break
        lo = 0 if m<0 else (m if tag in INERT else m+1)
        for i in range(len(self.stack)-1,lo-1,-1):
            if self.stack[i][0]==tag: del self.stack[i:]; break
src=open(sys.argv[1],encoding='utf-8').read()
w=W(sys.argv[2], sys.argv[3]); w.feed(src)
print(w.n)
PYEOF
}
# JSON-LD folio:stakeholders の型+値 (型\t値・生成物 HTML から抽出)。
ld_stake() { perl -CSD -0777 -ne 'my ($j) = /<script type="application\/ld\+json">(.*?)<\/script>/s; print $j if defined $j;' "$1" \
  | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
v = d.get("folio:stakeholders")
print(type(v).__name__ + "\t" + json.dumps(v, ensure_ascii=False, sort_keys=True))'; }

# ★ORACLE 存在 pin (bootstrap 記録・fail-closed。 照合不能 silent skip の回帰 pin・M15・非消費)。 snapshot は census を消費しないが、
#   SPEC_ORIGIN_HTML を存在しない path へ向けて gate を silent skip する逃げ道は塞ぐ (存在検査のみ・内容不読)。
if [[ ! -f "$ORIG" ]]; then
  printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (照合不能・fail-closed)\n' "ORACLE 存在 pin (bootstrap 記録)" "$ORIG"; fail=1
fi

# --- (a) literal census: expected = 凍結 literal / subject = 生成物 HTML (ORIG 非消費) ---
# ★census 実測は parser walk 1 回に集約する (計数方式の混在 = parser-differential の温床ゆえ single-source)。
CEN_DUMP="$(mktemp)"
census_dump "$HTML" > "$CEN_DUMP" || { echo "verify-spec: ★census parser walk に失敗 (fail-closed): $HTML" >&2; exit 2; }
grep -q '^C_XREF=' "$CEN_DUMP" || { echo "verify-spec: ★census parser walk の出力が不正 (fail-closed): $HTML" >&2; exit 2; }
cen()  { grep -m1 "^$1=" "$CEN_DUMP" | sed "s/^$1=//"; }
cen_ids()  { sed -n '/^#IDS$/,/^#DIDS$/p' "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
cen_dids() { sed -n '/^#DIDS$/,$p'        "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
# navigable id census (count + rename SET・deliverable 5)。
g_ids="$(mktemp)"; cen_ids > "$g_ids"
# D-* (delta 印) は navigable id へ混入禁止 (fail-closed・生成物側で撃つ)。
chk "census navigable id: 生成物の D-* id == 0 (delta 印 anchor 混入を fail-closed に)" "0" "$(grep -c '^D-' "$g_ids" || true)"
# ★count census (frozen literal・subject=生成物)。
chk "census navigable id: 総数 == 凍結 $(fz FZ_ID_COUNT)" "$(fz FZ_ID_COUNT)" "$(grep -c . "$g_ids")"
# ★重複 0 の構造的不変条件 (folio-7wbn 3 巡目 ceiling major fix の port・folio-7st6)。 count / SET census は共に dedup 後の
#   unique 集合を見るため ★既存 id の複製注入 (unique 57 保存) を原理的に検出できない。 文書順 first-match の fragment
#   解決ゆえ複製は anchor hijack を起こす。 凍結 literal でなく「unique == 総出現」で撃つ (census file 無改訂)。
chk "census navigable id: 重複 0 (unique == 総出現・anchor hijack 封鎖)" "$(cen ID_TOTAL)" "$(grep -c . "$g_ids")"
# ★id-rename SET census (deliverable 5): count 保存 substitution (55==55) を見逃さないよう凍結 SET と comm。
FZ_IDS="$(mktemp)"; fz_set ID_SET | LC_ALL=C sort -u > "$FZ_IDS"
chk_empty "census id-rename SET: 生成物にあり凍結 SET に無い余剰 0 (rename / 捏造)" "$(LC_ALL=C comm -13 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
chk_empty "census id-rename SET: 凍結 SET にあり生成物に無い欠落 0 (rename / 脱落)" "$(LC_ALL=C comm -23 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
rm -f "$g_ids" "$FZ_IDS"
# ★rich 資産 occurrence (frozen literal・subject=生成物)。
chk "census rich: a.xref occurrence == 凍結 $(fz FZ_XREF)"        "$(fz FZ_XREF)"  "$(cen C_XREF)"
chk "census rich: span.term occurrence == 凍結 $(fz FZ_TERM)"     "$(fz FZ_TERM)"  "$(cen C_TERM)"
chk "census rich: ins|del.delta occurrence == 凍結 $(fz FZ_DELTA)" "$(fz FZ_DELTA)" "$(cen C_DELTA)"
# delta-id SET census (frozen・count 保存 rename を見逃さない)。
G_DID="$(mktemp)"; FZ_DID="$(mktemp)"
cen_dids > "$G_DID"
fz_set DELTA_SET | LC_ALL=C sort -u > "$FZ_DID"
chk_empty "census delta-id SET: 余剰 0 (凍結 SET 対)" "$(LC_ALL=C comm -13 "$FZ_DID" "$G_DID" | tr '\n' ' ')"
chk_empty "census delta-id SET: 欠落 0 (凍結 SET 対)" "$(LC_ALL=C comm -23 "$FZ_DID" "$G_DID" | tr '\n' ' ')"
rm -f "$G_DID" "$FZ_DID"
# escape 済 literal 'a class="xref"' (過剰 linkify 禁止・subject=生成物・★text node 限定計数)。
chk "census escape: 'a class=\"xref\"' literal == 凍結 $(fz FZ_ESC_XREF)" "$(fz FZ_ESC_XREF)" "$(cen ESC_XREF)"
# generic inline (code/span) の人間層 region 別 occurrence (frozen・subject=生成物・region 相殺封鎖のため総和も撃つ)。
chk "census generic: 人間層 <code> table-cell == 凍結 $(fz FZ_CODE_TABLE_CELL)" "$(fz FZ_CODE_TABLE_CELL)" "$(h_inline "$HTML" code table-cell)"
chk "census generic: 人間層 <code> caption == 凍結 $(fz FZ_CODE_CAPTION)"       "$(fz FZ_CODE_CAPTION)"    "$(h_inline "$HTML" code caption)"
chk "census generic: 人間層 <code> rest == 凍結 $(fz FZ_CODE_REST)"            "$(fz FZ_CODE_REST)"       "$(h_inline "$HTML" code rest)"
chk "census generic: 人間層 <code> 総数 == 凍結 $(fz FZ_CODE_TOTAL) (region 相殺封鎖)" "$(fz FZ_CODE_TOTAL)" "$(h_inline "$HTML" code human)"
chk "census generic: 人間層 <span> table-cell == 凍結 $(fz FZ_SPAN_TABLE_CELL)" "$(fz FZ_SPAN_TABLE_CELL)" "$(h_inline "$HTML" span table-cell)"
chk "census generic: 人間層 <span> caption == 凍結 $(fz FZ_SPAN_CAPTION)"       "$(fz FZ_SPAN_CAPTION)"    "$(h_inline "$HTML" span caption)"
# double-escape 直接検出 (frozen・subject=生成物・★text node 限定計数)。
chk "census double-escape: &lt;code literal == 凍結 $(fz FZ_ESC_CODE)" "$(fz FZ_ESC_CODE)" "$(cen ESC_CODE)"
chk "census double-escape: &lt;span literal == 凍結 $(fz FZ_ESC_SPAN) (散文中の正当 literal)" "$(fz FZ_ESC_SPAN)" "$(cen ESC_SPAN)"
# jq -S PRESERVE + mask (frozen・subject=生成物)。
chk "census jq-S: 'jq -S' 総出現 == 凍結 $(fz FZ_JQS_TOTAL)" "$(fz FZ_JQS_TOTAL)" \
  "$(perl -CSD -0777 -ne 'my $n=()=(/jq -S/g); print $n;' "$HTML")"
chk "census jq-S: masked <code> == 凍結 $(fz FZ_JQS_MASKED) (P-11 primitive 露出なし)" "$(fz FZ_JQS_MASKED)" \
  "$(perl -CSD -0777 -ne 'my $n=()=(/<code>[^<]*jq -S[^<]*<\/code>/g); print $n;' "$HTML")"
# JSON-LD folio:stakeholders 型+値 (frozen literal・subject=生成物・array 型退行封鎖)。
chk "census JSON-LD: folio:stakeholders 型+値 == 凍結 literal (array 退行封鎖)" \
  "$(fz_ld)" "$(ld_stake "$HTML")"
rm -f "$HTML_LIVE" "$CEN_DUMP"

if [[ "$NMB_TOTAL" -gt 0 ]]; then
  # ★ORACLE 存在 pin (bootstrap 記録・fail-closed。 照合不能 silent skip の回帰 pin・M15・非消費)。 §11 LEFT は政策 A (folio-7n17) で
  #   contract 由来へ re-home したため ORIG を消費しないが、 SPEC_ORIGIN_HTML=/nonexistent による silent skip の
  #   逃げ道は §10b と対称に塞ぐ (存在検査のみ・内容不読)。
  if [[ ! -f "$ORIG" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (照合不能・fail-closed)\n' "機械層 round-trip 存在 pin" "$ORIG"; fail=1
  fi
  command -v jq >/dev/null || { echo "verify-spec: jq required (§11 contract round-trip)" >&2; exit 2; }
  LF="$(mktemp)"; RF="$(mktemp)"
  # LEFT: ★政策 A (folio-7n17)。 snapshot / live canonical でなく contract.machine_preamble[] +
  #   sections[].machine_blocks[] (25 block) から document 順に再構成する。 contract の html field は
  #   extract-verification-spec.sh の inner_norm 済 (空白畳み + trim) ゆえ RIGHT の norm 出力と 1:1 で突合する
  #   (folio-7n17 で snapshot LEFT とバイト一致を実測)。 list は items[] を li 単位へ展開 (RIGHT の <li class="mli"> と対称)。
  #   ★両側 contract 由来ゆえ両側同時退行で vacuous になりうる → §10b 凍結 census + extractor-collapse test で塞ぐ
  #     (mandate: (a)(b) は両側 contract 由来ゆえ (c) で塞ぐ)。 本 arm が守るのは assembler バグ (生成物が
  #     contract から乖離・silent drop / 順序入替 / cross-section 誤帰属) の検出。
  yq -o=json '[.machine_preamble[]?, .sections[].machine_blocks[]?]' "$CONTRACT" | jq -r '.[] |
    if .type=="list" then (.items[] | "li\t"+.)
    elif .type=="prose" then "prose\t"+.html
    elif .type=="note" then "note\t"+.html
    elif .type=="demoted" then "demoted\t"+.html
    elif .type=="dl" then "dl\t"+.html
    else "UNKNOWN\t"+(.type//"?") end' > "$LF"
  # RIGHT: 生成物の機械層 block を document 順に再抽出 + inner_norm。 prose/note/li は fold 内で交互に出現しうるため、
  #   型ごとに別 pass で集めず *位置走査* で混在順序を保存する (LEFT と同型・順序付き突合のため必須)。
  #   mli は machine list 専有 class・spec-machine-{prose,note} は machine 専有 component ゆえ live tag のみ抽出。
  perl -CSD -0777 -e '
    local $/; open(my $fh,"<:encoding(UTF-8)",$ARGV[0]) or die; my $B=<$fh>; close $fh;
    sub norm { my ($s)=@_; $s//=""; $s=~s/\s+/ /g; $s=~s/^\s+//; $s=~s/\s+$//; return $s; }
    my @u; my $p=0; my $len=length($B);
    while ($p<$len) {
      my %c;
      if (substr($B,$p)=~/<p data-component="spec-machine-prose" data-audience="machine">/)  { $c{prose}=$p+$-[0]; }
      if (substr($B,$p)=~/<aside data-component="spec-machine-note" data-audience="machine">/) { $c{note}=$p+$-[0]; }
      if (substr($B,$p)=~/<li class="mli">/) { $c{li}=$p+$-[0]; }
      # ★demoted (tr0 / verification): 生成物の spec-machine-demoted を balanced div で inner 一括 norm (RIGHT・LEFT と同型)。
      if (substr($B,$p)=~/<div data-component="spec-machine-demoted" data-audience="machine">/) { $c{demoted}=$p+$-[0]; }
      # ★dl (folio-aduv): 生成物の spec-machine-dl inner を norm (RIGHT・LEFT と同型)。
      if (substr($B,$p)=~/<dl data-component="spec-machine-dl" data-audience="machine">/) { $c{dl}=$p+$-[0]; }
      last unless %c;
      my ($k)=sort { $c{$a}<=>$c{$b} } keys %c; my $at=$c{$k};
      if ($k eq "prose") { substr($B,$at)=~/<p data-component="spec-machine-prose" data-audience="machine">(.*?)<\/p>/s; push @u,"prose\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "note") { substr($B,$at)=~/<aside data-component="spec-machine-note" data-audience="machine">(.*?)<\/aside>/s; push @u,"note\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "dl") { substr($B,$at)=~/<dl data-component="spec-machine-dl" data-audience="machine">(.*?)<\/dl>/s; push @u,"dl\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "demoted") { my $sub=substr($B,$at); $sub=~/^<div\b[^>]*>/; my $ol=$+[0]; my $d=0; my $eo=length($sub);
             while ($sub=~/(<div\b[^>]*>|<\/div>)/g){ my $t=$1; my $te=pos($sub); if($t=~/^<div/){$d++}else{$d--; if($d==0){$eo=$te;last}} }
             my $w=substr($sub,0,$eo); my $in=substr($w,$ol,length($w)-$ol-length("</div>")); push @u,"demoted\t".norm($in); $p=$at+$eo; }
      else { substr($B,$at)=~/<li class="mli">(.*?)<\/li>/s; push @u,"li\t".norm($1); $p=$at+$+[0]; }
    }
    print "$_\n" for @u;
  ' "$BODY" > "$RF"
  if diff -q "$LF" "$RF" >/dev/null 2>&1; then
    printf '  [OK]   %-'"$CHKW"'s %s\n' "contract↔生成物 機械層 双方向 順序付き一致 (round-trip)" "$(grep -c . "$LF")"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "contract↔生成物 機械層 不一致 (脱落 / 捏造 / 二重 escape / 改竄 / 順序入替 / cross-section 誤帰属)"
    echo "    --- 順序付き diff (< contract / > 生成物) ---"; diff "$LF" "$RF" | sed 's/^/      /' | head -20
    echo "    --- contract のみ (生成物に脱落) ---"; LC_ALL=C comm -23 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
    echo "    --- 生成物のみ (contract に無い = 捏造/改竄) ---"; LC_ALL=C comm -13 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
    fail=1
  fi
  rm -f "$LF" "$RF"
fi

echo
# ---- gate F: render 健全性 (visual) mermaid pack 展開 (folio-jyfh B 段・helper=render_gate_f)。 mermaid 図を
#      含む生成 HTML (../assets/mermaid.min.js 参照は serve root で /assets/ に正規化解決) を light/dark × 3
#      viewport で render-gate し、 SVG settle polling (最大 15s) で非同期 render を待つ。 vendor は render_gate_f
#      が staging。 fail-closed (violation/crash/settle 不足 = $fail=1)。 SKIP_RENDER=1 で bash floor は SKIP。 ----
render_gate_f "$HTML" "VERIFICATION_SKIP_RENDER"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 要件/section/block/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
