#!/usr/bin/env bash
# folio engine 段階3 (folio-5uu) — architecture-description-pack fabrication-free + 固定章 + 照会 graph + id anchor proof (instance#1)
#
# 生成 architecture HTML の *構造* が入力 contract から完全に導出されたことを機械検証する floor gate (記述型・arc42+C4)。
# verify-testcases.sh (cross-doc 照会型) / verify-glossary.sh (id anchor 型) と同型の規律を arch-pack schema へ適用。
#
# ★floor 三本柱 (folio-5uu grill 確定):
#   ① 照会グラフ整合: decisions[].refs.{srs,adr}[] の cross-doc 照会が (a) HTML data-{arch,adr}-ref 集合と集合一致 +
#      count anchor、 (b) 参照先 SRS/ADR contract に実在 (dangling 0)、 (c) doc_id 一致、 (d)(d') role 整合、
#      (e) href 遷移先が contract 派生値 (1h・SRS/quality=<srs_html>#<ref> / ADR=<adr_html>#decision / principle=#principle-<ref>)。
#      共通スケルトン = core (verify_cross_doc_refs)。 SRS 向け・ADR 向けに 2 回呼ぶ。 graph 終端完備は verify-graph.sh が別途。
#   ② navigable id アンカー: decision→ad-/component→comp-/quality→qa-/risk→risk- の id= 集合が contract と集合一致
#      (glossary の id=term-<slug> 方式を踏襲・案A の人間半分・folio-lzz の手本)。
#   ③ 固定章 + 必須要素: arc42 固定 8 章 (chapter-deck-band) + 各章の必須要素件数 (部品6/決定4/品質5/リスク4/戦略4/actor5/図3) が contract と一致。
#
# ★横展開: (a) 実装HOWリーク = 保守的 advisory scan (WARN・FAIL でない・denylist は contract)、 (b) CJK inline 強調の空白規律 (FAIL)。
# ★fab-free: 可視テキスト fidelity (emission 順 pin)・cross-doc 可視 echo 厳密一致 (marker-keyed・nested-reject)・図 mermaid DSL 忠実。
# ★floor PASS でも GREEN にせず CEILING=PENDING・exit 0 (floor 単独 GREEN 禁止・S5.1 two-gate)。
#
# usage: verify-arch.sh [--filled <manifest.yaml> | --artifact] <architecture-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-arch.sh [--filled <manifest> | --artifact] <architecture-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-arch.sh [--filled <manifest> | --artifact] <architecture-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-arch: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-arch: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-arch: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-arch: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-arch: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-arch: failed to source verify-common.sh" >&2; exit 2; }
fail=0
declare -i nwarn=0
make_body "$HTML"

NDEC="$(q '.decisions | length')"; NCOMP="$(q '.components | length')"; NQA="$(q '.quality | length')"
NRISK="$(q '.risks | length')"; NSTRAT="$(q '.strategy | length')"; NACTOR="$(q '.context.actors | length')"; NDIAG="$(q '.diagrams | length')"
NSRS="$(q '[.decisions[].refs.srs[]] | length')"; NADR="$(q '[.decisions[].refs.adr[]] | length')"; NPRIN="$(q '[.decisions[].refs.principle[]] | length')"
echo "architecture-description-pack fabrication-free + 固定章 + 照会 graph + id anchor proof: $HTML"
echo "  contract: $CONTRACT  (部品 $NCOMP / 決定 $NDEC / 品質 $NQA / リスク $NRISK / 図 $NDIAG / SRS照会 $NSRS / ADR照会 $NADR)"

# ============ ③ 固定章 + 必須要素 (arc42 8 章 + 件数 = contract 導出) ============
chk "arc42 固定 8 章 (chapter-deck-band)" "8" "$(grep -c 'data-component="chapter-deck-band"' "$BODY")"
chk "decision-card 数 == |decisions|"     "$NDEC"   "$(grep -c 'data-component="arch-decision-card"' "$BODY")"
chk "component-row 数 == |components|"     "$NCOMP"  "$(grep -c 'data-component="component-row"' "$BODY")"
chk "quality-row 数 == |quality|"         "$NQA"    "$(grep -c 'data-component="quality-row"' "$BODY")"
chk "risk-card 数 == |risks|"             "$NRISK"  "$(grep -c 'data-component="risk-card"' "$BODY")"
chk "strategy-card 数 == |strategy|"      "$NSTRAT" "$(grep -c 'data-component="strategy-card"' "$BODY")"
chk "arch-actor 数 == |actors|"           "$NACTOR" "$(grep -o 'class="arch-actor"' "$BODY" | wc -l | tr -d ' ')"
chk "diagram (mermaid pre) 数 == |diagrams|" "$NDIAG" "$(grep -c 'class="mermaid"' "$BODY")"
chk "figcaption 数 == |diagrams|"         "$NDIAG"  "$(grep -c '<figcaption>' "$BODY")"
chk "principle-terminal == 1"             "1"       "$(grep -c 'data-component="principle-terminal"' "$BODY")"

# ============ ② navigable id アンカー (照会されうる全ノードに id= ・集合一致) ============
# decision→ad-<id> / component→comp-<id> / quality→qa-<id> / risk→risk-<id> を contract id から再導出して集合突合。
exp_anchor="$( {
  q '.decisions[].id'  | sed 's/^/ad-/'
  q '.components[].id'  | sed 's/^/comp-/'
  q '.quality[].id'     | sed 's/^/qa-/'
  q '.risks[].id'       | sed 's/^/risk-/'
} | LC_ALL=C sort )"
act_anchor="$(perl -CSD -0777 -ne 'while (/\bid="(ad-[^"]+|comp-[^"]+|qa-[^"]+|risk-[^"]+)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "navigable id アンカー (ad-/comp-/qa-/risk-) == contract" "$exp_anchor" "$act_anchor"
# principle 終端 anchor (id=principle-<principle.id>)
chk "principle 終端 anchor id=principle-<id>" "1" "$(grep -c "id=\"principle-$(q '.principle.id')\"" "$BODY")"

# ============ id 一意性 ============
chk_empty "decisions id 一意"  "$(q '.decisions[].id'  | sort | uniq -d | tr '\n' ' ')"
chk_empty "components id 一意"  "$(q '.components[].id'  | sort | uniq -d | tr '\n' ' ')"
chk_empty "quality id 一意"     "$(q '.quality[].id'     | sort | uniq -d | tr '\n' ' ')"
chk_empty "risks id 一意"       "$(q '.risks[].id'       | sort | uniq -d | tr '\n' ' ')"

# ============ ① 照会グラフ整合 (cross-doc 前方照会・core 共通スケルトン × 2) ============
# SRS 充足照会 (role=claim・data-arch-ref/data-arch-role)。 ★attr 名は SRS=data-arch-ref / ADR=data-adr-ref で分離
#   (両者を同一 attr にすると verify_cross_doc_refs の body 全域 grep が混線し dangling 誤検出するため・worker 設計判断)。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-arch-ref" --role-attr "data-arch-role" \
  --keys-expr '.decisions[].refs.srs[]' \
  --count-expr '[.decisions[].refs.srs[]] | length' \
  --nonempty-count-expr '[ .decisions[].refs.srs[] | select((. // "") != "") ] | length' \
  --pair-expr '.decisions[].refs.srs[] | [., "claim"] | @tsv' \
  --target-ids-expr '.requirements[].id' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'
# ADR 根拠照会 (role=rationale・data-adr-ref/data-adr-role・doc 粒度照会 = ADR doc_id)。
ADR_REL="$(q '.cross_doc.adr_contract')"; ADR_ABS="${CONTRACT_DIR}/${ADR_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc(ADR)" --target-label "ADR" \
  --target-abs "$ADR_ABS" --target-rel "$ADR_REL" \
  --key-attr "data-adr-ref" --role-attr "data-adr-role" \
  --keys-expr '.decisions[].refs.adr[]' \
  --count-expr '[.decisions[].refs.adr[]] | length' \
  --nonempty-count-expr '[ .decisions[].refs.adr[] | select((. // "") != "") ] | length' \
  --pair-expr '.decisions[].refs.adr[] | [., "rationale"] | @tsv' \
  --target-ids-expr '.meta.doc_id' \
  --contract-docid-expr '.cross_doc.adr_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 1d. ★per-card 照会 fidelity (card-keyed)。 verify_cross_doc_refs は edge を全 card 横断の SET でしか見ず、 card 間で
#   FR を入替えても global set/count/(key,role) が不変のまま矛盾文書が素通る fail-open (testcases 3d と同型)。
#   各 decision-card (id=ad-ADx) スコープ内の (data-arch-ref, claim) を ad-id へ束ねた三つ組集合を contract と突合。
# ★mikefarah yq の `.id as $id` は空 refs の decision で空行を吐く (array 収集でも残る) ゆえ grep . で空行を除く。
exp_cardref="$(q '.decisions[] | .id as $id | .refs.srs[] | [$id, ., "claim"] | @tsv' | grep . \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardref="$(perl -CSD -0777 -ne '
  while (/<div data-component="arch-decision-card" id="ad-([^"]+)">(.*?)(?=<div data-component="arch-decision-card"|<div data-component="principle-terminal"|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/\bdata-arch-ref="([^"]*)"\s+data-arch-role="([^"]*)"/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card SRS 照会 三つ組 (ad-id, FR, claim) == contract" "$exp_cardref" "$act_cardref"
# ADR 照会も card-keyed (どの決定が ADR を根拠照会するか)
exp_cardadr="$(q '.decisions[] | .id as $id | .refs.adr[] | [$id, ., "rationale"] | @tsv' | grep . \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardadr="$(perl -CSD -0777 -ne '
  while (/<div data-component="arch-decision-card" id="ad-([^"]+)">(.*?)(?=<div data-component="arch-decision-card"|<div data-component="principle-terminal"|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/\bdata-adr-ref="([^"]*)"\s+data-adr-role="([^"]*)"/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card ADR 照会 三つ組 (ad-id, doc_id, rationale) == contract" "$exp_cardadr" "$act_cardadr"

# 1e. ★SRS 由来 機能名ラベル fidelity (persona ceiling 是正・裸 FR コードに機能名併記)。 (ref, 可視ラベル) 集合 ==
#   SRS requirements[].label (FR=label・fabrication-free)。 SRS contract は read-only・FR 実在は §① が保証済。
chk "data-srs-label-ref 数 == |SRS照会|" "$NSRS" "$(grep -o 'data-srs-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_srslabels="$(q '[.decisions[].refs.srs[]] | unique | .[]' | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(FR="$_r" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")")"; done | LC_ALL=C sort -u)"
act_srslabels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-srs-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "SRS 機能名ラベル (ref, label) == SRS 由来 (FR=label)" "$exp_srslabels" "$act_srslabels"
# ADR ラベル = 「ADR: <参照先 ADR の実 .meta.title>」 live-mirror (folio-c5r.13・手書き title 廃止)。
# 参照先 ADR を改題すると本 chk が fail-closed で drift を捕捉する (ADR_ABS は §照会先解決で設定済)。
ADR_TITLE_E="$(esc "ADR: $(yq -r '.meta.title' "$ADR_ABS")")"
act_adrlabel="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-adr-label-ref="[^"]*"[^>]*>([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
chk "ADR ラベル == 「ADR: 」+ 参照先 .meta.title (live-mirror・retitle drift fail-closed)" "$ADR_TITLE_E" "$act_adrlabel"

# 1f. principle 終端照会 (within-doc・data-principle-ref) + 終端 panel fidelity
chk "data-principle-ref 数 == |principle照会|" "$NPRIN" "$(grep -o 'data-principle-ref=' "$BODY" | wc -l | tr -d ' ')"
set_eq "principle 照会 ref == contract refs.principle" "$(q '.decisions[].refs.principle[]' | LC_ALL=C sort -u)" \
  "$(perl -CSD -0777 -ne 'while (/\bdata-principle-ref="([^"]*)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
chk "principle-terminal pt-id == principle.id" "$(esc "$(q '.principle.id')")" \
  "$(perl -CSD -0777 -ne 'while (/<span class="pt-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "principle-terminal pt-text == principle.text" "$(esc "$(q '.principle.text')")" \
  "$(perl -CSD -0777 -ne 'while (/<p class="pt-text">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"

# 1g. ★可視 xref-code バッジ == 兄弟 data-*-ref 属性 (照会の正準コードの *可視層*・fail-open 封鎖)。 attr 値は §①/per-card で
#   contract に束縛済ゆえ、 各 <a> 内の 可視 xref-code == 兄弟 data-{arch,adr,principle}-ref を強制すれば可視層も transitively
#   contract 束縛される (FR コード・ADR doc_id・原則 id を読者に偽提示する単独改竄を封鎖・SRS/ADR/principle 共通)。
#   併せて 可視 xref-code 総数 == |SRS照会|+|ADR照会|+|principle照会| を pin し、 ペア外の孤立 xref-code (未束縛 echo) も封鎖。
xref_code_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-(?:arch|adr|principle)-ref="([^"]*)"[^>]*?><span class="xref-code">([^<]*)<\/span>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 xref-code == 兄弟 data-*-ref 属性 (照会コードの可視捏造封鎖)" "$xref_code_bad"
chk "可視 xref-code 総数 == |SRS+ADR+principle照会| (孤立 echo 封鎖)" "$((NSRS + NADR + NPRIN))" "$(grep -o '<span class="xref-code">' "$BODY" | wc -l | tr -d ' ')"

# 1h. ★href 遷移先 fidelity (リンクの *飛び先* を contract 派生値へ束縛・fail-open 封鎖)。 §①/per-card/1g は data-*-ref 属性と
#   可視 xref-code を contract に pin するが、 実際の遷移先である href 値は *全く* 検査していなかった (grep -c href = 0)。 ゆえ
#   属性・可視ラベル intact のまま href だけを 別要件 (#FR99) / 外部 URL (https://evil) / 別文書 / within-doc デッドアンカー
#   (#principle-FAKE) へ swap でき、 読者が正しいコード/ラベルを見てクリックすると別所へ飛ぶ fail-open があった
#   (folio-5uu self-review・worker mut45-51 で塞いだ『属性 intact・可視捏造』と対称の『属性+可視 intact・href 改竄』)。
#   各 <a> の (href, 兄弟 data-*-ref) ペアを contract 派生 href へ束ねて set_eq する: SRS/quality = <srs_html>#<ref> /
#   ADR = <adr_html>#decision / principle = #principle-<ref>。 href が決定的に contract 由来であることを証明し、
#   anchor swap / filename swap / 外部 host / within-doc デッドリンクを fail-closed で封鎖する (cross-doc *target* アンカー
#   の後付けは folio-lzz scope だが、 href *値* が contract 派生であること自体 + 原則 within-doc 遷移先健全性は本 cell scope)。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"; ADR_HTML_E="$(esc "$(q '.cross_doc.adr_html')")"
# (SRS claim href, FR) == <srs_html>#<ref>
exp_srs_href="$(q '.decisions[].refs.srs[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_srs_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-arch-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: SRS claim (href, FR) == <srs_html>#<ref>" "$exp_srs_href" "$act_srs_href"
# (ADR rationale href, doc_id) == <adr_html>#decision
exp_adr_href="$(q '.decisions[].refs.adr[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#decision\t%s\n' "$ADR_HTML_E" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_adr_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-adr-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: ADR rationale (href, doc_id) == <adr_html>#decision" "$exp_adr_href" "$act_adr_href"
# (principle href, id) == #principle-<ref> (within-doc 遷移先健全性・デッドリンク封鎖)
exp_prin_href="$(q '.decisions[].refs.principle[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '#principle-%s\t%s\n' "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_prin_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-principle-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: principle (href, id) == #principle-<ref> (デッドリンク封鎖)" "$exp_prin_href" "$act_prin_href"
# (quality srs href, AC/NFR) == <srs_html>#<srs_ref>
exp_qa_href="$(q '.quality[].srs_ref' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_qa_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-quality-srs-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: quality (href, srs_ref) == <srs_html>#<srs_ref>" "$exp_qa_href" "$act_qa_href"
# href 総数 == 全照会数 (孤立/追加 href の add を封鎖。 set_eq の -u が畳む重複・余剰 href を件数で捕捉)
chk "href: 総数 == |SRS+ADR+principle+quality照会| (孤立 href 封鎖)" "$((NSRS + NADR + NPRIN + NQA))" "$(grep -oE 'href="[^"]*"' "$BODY" | wc -l | tr -d ' ')"

# ============ cross-doc 可視 echo 厳密一致 (marker-keyed・nested-same-tag reject = ds8/B3 不動点) ============
chk "cross-doc: ref-chip ブロック == 1" "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"; adr_id_e="$(esc "$(q '.cross_doc.adr_doc_id')")"
chip_bad="$(SRS="$srs_id_e" ADR="$adr_id_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my $adr=$ENV{ADR}; utf8::decode($adr); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"chip:".scalar(@bs)."B"; next}
    push @bad,"chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    push @bad,"chip:b2\x{2260}$bs[1]" if $bs[1] ne $adr;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"chip:VIS" if $vis ne " 照会先: ${srs}の要件 / ${adr}の判断";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: ref-chip 可視 echo == テンプレ+doc_id (swap/平文/nested 封鎖)" "$chip_bad"

# ============ core 共通 chrome (cover-head/approval/glossary 値突合 + 占有数パリティ・folio-mk9) ============
verify_core_chrome
chk "core-chrome: reader-chip class 総数 == 2 (genuine 1 + cross-doc-ref-chip 1)" "2" "$(count_attr_token class reader-chip < "$BODY")"

# ============ cover-meta KV (種別/構成/照会先/版) の決定的再導出突合 ============
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別"   "architecture-description (アーキテクチャ記述)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 構成"   "$(esc "arc42 8 章 (部品 ${NCOMP} / 決定 ${NDEC})")" "$(printf '%s\n' "$meta_kv" | grep -F '構成' | head -1 | cut -f2)"
chk "cover-meta 照会先" "$(esc "$(q '.cross_doc.srs_doc_id')・$(q '.cross_doc.adr_doc_id')")" "$(printf '%s\n' "$meta_kv" | grep -F '照会先' | head -1 | cut -f2)"
chk "cover-meta 版"     "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# ============ 各章ノードの可視テキスト fidelity (emission 順・属性 intact のまま可視改竄/捏造を封鎖) ============
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
# ★可視 ad-id バッジ == .decisions[].id (navigable anchor id=ad-* とは別の *可視識別子*・偽 AD コード提示を封鎖)。
#   anchor id 健全のまま可視 ad-id だけ捏造する fail-open を塞ぐ (st-id/ad-id/qa-id/rk-id は同型の可視識別子)。
set_eq "可視 ad-id == .decisions[].id" "$(qesc '.decisions[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ad-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# decision title (h3.ad-title・term-inline なし [^<]*)
set_eq "可視 decision title == .decisions[].title" "$(qesc '.decisions[].title')" \
  "$(perl -CSD -0777 -ne 'while (/<h3 class="ad-title">([^<]*)<\/h3>/g){ print "$1\n"; }' "$BODY")"
# decision summary (p.ad-summary・term-inline strip)
set_eq "可視 decision summary == .decisions[].summary" "$(qesc '.decisions[].summary')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="ad-summary">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# component name (.cn・[^<]*) + 責務/分離理由 (term-inline strip)
set_eq "可視 component name == .components[].name" "$(qesc '.components[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="cn">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 component 責務 == .components[].responsibility" "$(qesc '.components[].responsibility')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<td><span class="cn">.*?<\/span><br><span class="ckind [a-z]+">[^<]*<\/span><\/td><td>(.*?)<span class="cwhy">/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 component 分離理由 == .components[].separation_reason" "$(qesc '.components[].separation_reason')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="cwhy">(.*?)<\/span><\/td><\/tr>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# component kind (class, 可視ラベル) 整合
exp_ckind="$(printf 'core\t中核\nexternal\t外部連携\n' | LC_ALL=C sort)"
act_ckind="$(grep -oE '<span class="ckind [a-z]+">[^<]*</span>' "$BODY" | sed -E 's#<span class="ckind ([a-z]+)">([^<]*)</span>#\1\t\2#' | LC_ALL=C sort -u)"
chk_empty "component kind バッジが class と整合" "$(LC_ALL=C comm -13 <(printf '%s\n' "$exp_ckind") <(printf '%s\n' "$act_ckind") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
# ★component kind (class, label) per-row ordered (emission 順)。 上の set 検査 (sort -u membership) は core↔external の
#   『妥当だが誤った』反転を集合不変ゆえ素通す fail-open (他 core 行が残れば集合 {core,external} 不変)。 emission 順
#   (class,label) tuple を contract 派生と突合し per-row 反転・行入替・label 改竄を封鎖 (kind の意味は arch で load-bearing)。
exp_ckind_ord="$(q '.components[].kind' | while IFS= read -r _k; do case "$_k" in core) printf 'core\t中核\n' ;; external) printf 'external\t外部連携\n' ;; *) printf '%s\t%s\n' "$_k" "$_k" ;; esac; done)"
set_eq "可視 component kind (class,label) == .components[].kind 派生" "$exp_ckind_ord" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ckind ([a-z]+)">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
# strategy id / name / plain / rationale。 ★st-id (S1 等の戦略識別子) は未突合だった = S1→S9 改竄が素通る fail-open。
#   emission 順で contract .strategy[].id と突合 (id は可視バッジ・戦略カードの見出し級)。
set_eq "可視 strategy id == .strategy[].id" "$(qesc '.strategy[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="st-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 strategy name == .strategy[].name" "$(qesc '.strategy[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="st-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 strategy plain == .strategy[].plain" "$(qesc '.strategy[].plain')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="st-plain">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 strategy rationale == .strategy[].rationale" "$(qesc '.strategy[].rationale')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="st-why">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# quality id / attribute / target / plain / srs_ref
# ★可視 qa-id バッジ == .quality[].id (navigable anchor id=qa-* とは別の *可視識別子*・偽 QA コード提示を封鎖)。
set_eq "可視 qa-id == .quality[].id" "$(qesc '.quality[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="qa-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 quality attribute == .quality[].attribute" "$(qesc '.quality[].attribute')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="qa-attr">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 quality target == .quality[].target" "$(qesc '.quality[].target')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="qa-target">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 quality plain == .quality[].plain" "$(qesc '.quality[].plain')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="qa-plain">(.*?)<\/span>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 quality srs_ref (data-quality-srs-ref) == .quality[].srs_ref" "$(qesc '.quality[].srs_ref')" \
  "$(perl -CSD -0777 -ne 'while (/<a[^>]*\bdata-quality-srs-ref="([^"]*)"[^>]*>([^<]*)<\/a>/g){ print "$2\n"; }' "$BODY")"
# risk id / severity (class, 可視ラベル) + risk/impact/mitigation
# ★可視 rk-id バッジ == .risks[].id (navigable anchor id=risk-* とは別の *可視識別子*・偽 R コード提示を封鎖)。
set_eq "可視 rk-id == .risks[].id" "$(qesc '.risks[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rk-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# ★risk severity は (class, 可視ラベル) ordered tuple で突合。 class (色) のみの突合は label-only 改竄 (色=正・語=偽=
#   <span class="rk-sev high">中</span>) を素通す fail-open ゆえ、 高→high\t高 / 中→mid\t中 を派生し emission 順で
#   (class,label) を突合し色と語の整合まで担保 (component/actor kind と同型・読者は『語』で重大度を判断ゆえ load-bearing)。
exp_sev_ord="$(q '.risks[].severity' | while IFS= read -r _s; do case "$_s" in 高) printf 'high\t高\n' ;; 中) printf 'mid\t中\n' ;; *) printf '%s\t%s\n' "$_s" "$_s" ;; esac; done)"
set_eq "可視 risk severity (class,label) == .risks[].severity 派生" "$exp_sev_ord" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rk-sev ([a-z]+)">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
set_eq "可視 risk 本文 == .risks[].risk" "$(qesc '.risks[].risk')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="rk-risk">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 risk impact == .risks[].impact" "$(qesc '.risks[].impact')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="rk-row"><span class="rk-k">起きると<\/span>(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 risk mitigation == .risks[].mitigation" "$(qesc '.risks[].mitigation')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="rk-row"><span class="rk-k">どう抑える<\/span>(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# actor name / role / kind
set_eq "可視 actor name == .context.actors[].name" "$(qesc '.context.actors[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="nm">([^<]*)<span class="akind/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 actor role == .context.actors[].role" "$(qesc '.context.actors[].role')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ar-role">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# ★actor kind (class, label) per-row ordered。 akind は name 抽出の区切りに使うだけで未突合だった = internal↔external
#   (患者=内部↔外部) の system-boundary 意味反転が素通る fail-open (component kind と同型の取りこぼし)。 emission 順
#   (class,label) tuple を contract 派生と突合し class 反転・label 改竄・行入替を封鎖。
exp_akind_ord="$(q '.context.actors[].kind' | while IFS= read -r _k; do case "$_k" in internal) printf 'internal\t内部\n' ;; external) printf 'external\t外部\n' ;; *) printf '%s\t%s\n' "$_k" "$_k" ;; esac; done)"
set_eq "可視 actor kind (class,label) == .context.actors[].kind 派生" "$exp_akind_ord" \
  "$(perl -CSD -0777 -ne 'while (/<span class="akind ([a-z]+)">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
# context problem (term-inline strip)
set_eq "可視 context problem == .context.problem" "$(qesc '.context.problem')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p data-component="context-problem">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# ★runtime flow name (rt-name・violet の見出し級可視要素) は未突合だった = 「同時申込の二重予約防止」を任意テキストへ
#   捏造しても素通る fail-open。 emission 順で contract .runtime.flows[].name と突合 (esc・term-inline なし [^<]*)。
set_eq "可視 runtime flow name == .runtime.flows[].name" "$(qesc '.runtime.flows[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<p class="rt-name">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# runtime flow steps (esc・term-inline なし)
set_eq "可視 runtime steps == .runtime.flows[].steps[]" "$(qesc '.runtime.flows[].steps[]')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rt-v">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# ★folio-c5r.10: runtime flow summary (rt-summary・流れの概要) も突合する。 従来 contract に summary があるのに HTML 未描画 =
#   silent field-drop (SSoT の情報落ち・S5 gradient-skip 型の round-trip 死角) だった。 emission 順で contract と set_eq (esc・term-inline なし)。
set_eq "可視 runtime summary == .runtime.flows[].summary" "$(qesc '.runtime.flows[].summary')" \
  "$(perl -CSD -0777 -ne 'while (/<p class="rt-summary">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"

# ============ 図 (mermaid DSL + figcaption) fidelity ============
# 各図の <pre class="mermaid"> 内容 == esc(join lines) / figcaption 可視 == diag-tag + esc(caption)。
declare -A DIAG_TAG_V=( [context]="C4 — System Context" [container]="C4 — Container" [sequence]="フロー (sequence)" )
mapfile -t DIAGIDS < <(q '.diagrams[].id')
# 抽出: 各 pre.mermaid 内容 (emission 順)
mapfile -t ACT_MERMAID < <(perl -CSD -0777 -ne 'while (/<pre class="mermaid">(.*?)<\/pre>/gs){ my $t=$1; $t=~s/\n/\x01/g; print "$t\n"; }' "$BODY")
mapfile -t ACT_FIGCAP < <(perl -CSD -0777 -ne 'while (/<figcaption>(.*?)<\/figcaption>/gs){ my $t=$1; $t=~s/\n/ /g; print "$t\n"; }' "$BODY")
diag_i=0
for did in "${DIAGIDS[@]}"; do
  kind="$(q '.diagrams[] | select(.id=="'"$did"'") | .kind')"
  # 期待 mermaid = esc(各 line) を \n join → \x01 表現で照合
  exp_m="$(q '.diagrams[] | select(.id=="'"$did"'") | .lines[]' | while IFS= read -r ln; do esc "$ln"; printf '\x01'; done | sed 's/\x01$//')"
  chk "図[$did] mermaid DSL == esc(contract lines)" "$exp_m" "${ACT_MERMAID[$diag_i]:-MISSING}"
  exp_cap="<span class=\"diag-tag\">$(esc "${DIAG_TAG_V[$kind]}")</span>$(esc "$(q '.diagrams[] | select(.id=="'"$did"'") | .caption')")"
  chk "図[$did] figcaption == diag-tag + esc(caption)" "$exp_cap" "${ACT_FIGCAP[$diag_i]:-MISSING}"
  diag_i=$((diag_i+1))
done

# ============ 横展開 (a) 実装HOWリーク = 保守的 advisory scan (WARN・FAIL でない) ============
# 本文 ($BODY = make_body で <style> 中身を空化・<script> は残置) に対し denylist 語を語境界・大文字小文字非依存で scan。 検出 = WARN (floor を割らない)。
mapfile -t DENY < <(q '.how_leak_denylist[]' 2>/dev/null)
how_hits=""
for term in "${DENY[@]}"; do
  [[ -n "$term" ]] || continue
  if grep -qiF -- "$term" "$BODY"; then how_hits+=" $term"; fi
done
if [[ -z "$how_hits" ]]; then
  printf '  [OK]   %-'"$CHKW"'s %s\n' "実装HOWリーク scan (denylist 語 不在・advisory)" "0"
else
  printf '  [WARN] %-'"$CHKW"'s%s\n' "実装HOWリーク (architecture=構造WHAT に実装HOW語が混入):" "$how_hits"; nwarn+=1
fi

# ============ 横展開 (b) CJK inline 強調の空白規律 (FAIL) ============
# CJK 文字と強調 (<b>/<strong>/.term バッジ) の間に空白を入れると助詞前で改行が崩れる (mockup 実証・既知 CJK 難所)。
# CJK 直後の空白+強調開始 / 強調閉じ+空白+CJK / term バッジ前後の CJK 隣接空白を検出して FAIL。
cjk_bad="$(perl -CSD -Mutf8 -0777 -ne '
  my $cjk=qr/[\p{Han}\p{Hiragana}\p{Katakana}]/; my $n=0;
  $n++ while /$cjk[ \t]+<(?:b|strong)\b/g;
  $n++ while /<\/(?:b|strong)>[ \t]+$cjk/g;
  $n++ while /$cjk[ \t]+<span class="term"/g;
  $n++ while /<span class="term"[^>]*>[^<]*<\/span>[ \t]+$cjk/g;
  print $n;
' "$BODY")"
chk "CJK inline 強調の空白規律 (CJK 隣接の <b>/.term 前後空白 0)" "0" "$cjk_bad"

# ============ escape 健全性 ============
chk "化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"          "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# ============ prose スロット mode (pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実) ============
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

# ============ plain-language-term-inline fidelity + 用語被覆 (assemble-arch と同一語境界規律) ============
verify_term_inline \
  '.context.problem, .strategy[].plain, .strategy[].rationale, .components[].responsibility, .components[].separation_reason, .decisions[].summary, .quality[].plain, .risks[].risk, .risks[].impact, .risks[].mitigation' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
[[ "$nwarn" -eq 0 ]] || echo "  ($nwarn 件の WARN は advisory・floor を割らない)"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 固定章 + 照会 graph + id anchor + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
