#!/usr/bin/env bash
# folio engine post-B6 (folio-1q8o / c5r Tier C) — data-model-pack fabrication-free + 固定章 + 照会 graph + id anchor proof (instance#1)
#
# 生成 data-model HTML の *構造* が入力 contract から完全に導出されたことを機械検証する floor gate (hybrid・entity catalog + ER)。
# verify-arch.sh (記述型) と同型の規律を data-model schema へ適用。
#
# ★floor 三本柱:
#   ① 照会グラフ整合: entities/relationships/data_policy[].refs.srs[] の cross-doc 照会が (a) HTML data-dm-ref 集合と集合一致 +
#      count anchor、 (b) 参照先 SRS contract に実在 (dangling 0)、 (c) doc_id 一致、 (d)(d') role 整合、
#      (e) href 遷移先 = <srs_html>#<ref> (deep-link・fragment == 表示 REQ-ID)。 共通スケルトン = core (verify_cross_doc_refs)。
#      graph 終端完備は verify-graph.sh が別途 (自前 inline principle 終端)。
#   ② navigable id アンカー: entity→entity-/relationship→rel-/data_policy→dp-/principle→principle- の id= 集合が contract と集合一致。
#   ③ 固定章 + 必須要素 (census-count): 6 章 (chapter-deck-band) + entity-card 6/entity-field-row Σ/relationship-row 5/data-policy-card 3/er-diagram 1 が contract と一致。
#
# ★fab-free: 可視テキスト fidelity (emission 順 pin)・cross-doc 可視 echo 厳密一致・ER 図 mermaid DSL 忠実・band 数詞 fidelity。
# ★floor PASS でも GREEN にせず CEILING=PENDING・exit 0 (floor 単独 GREEN 禁止・two-gate)。
#
# usage: verify-datamodel.sh [--filled <manifest.yaml> | --artifact] <datamodel-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-datamodel.sh [--filled <manifest> | --artifact] <datamodel-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-datamodel.sh [--filled <manifest> | --artifact] <datamodel-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-datamodel: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-datamodel: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-datamodel: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-datamodel: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-datamodel: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=56; source "$LVC" || { echo "verify-datamodel: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build datamodel "$FILLED_MANIFEST"

NENT="$(q '.entities | length')"; NREL="$(q '.relationships | length')"; NDP="$(q '.data_policy | length')"
NDIAG="$(q '.diagrams | length')"; NFIELD="$(q '[.entities[].fields[]] | length')"
NSRS="$(q '[.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]] | length')"
NHIGH="$(q '[.entities[] | select(.sensitivity=="high")] | length')"
echo "data-model-pack fabrication-free + 固定章 + 照会 graph + id anchor proof: $HTML"
echo "  contract: $CONTRACT  (かたまり $NENT / 項目 $NFIELD / つながり $NREL / データ方針 $NDP / 図 $NDIAG / SRS照会 $NSRS)"

# ============ ③ 固定章 + 必須要素 (census-count = contract 導出) ============
## ★genuine-shape 不変条件 (verify-arch と同型): band/h2 を要素単位・case-insensitive・attribute-tolerant に数え、
##   行 packing / decoy <h2 class> / 大文字 <SECTION>/<H2> のパーサ差分を fail-closed にする。
NBAND="$(perl -CSD -0777 -ne '$n++ while m{<section\b[^>]*data-component="chapter-deck-band"}gi; END{print $n+0}' "$BODY")"
NH2ALL="$(perl -CSD -0777 -ne '$n++ while m{<h2\b}gi; END{print $n+0}' "$BODY")"
chk "固定 6 章 (band-section 要素数・ci)"                 "6" "$NBAND"
chk "全 <h2> 要素数 == 6 (band 外/属性 decoy/大文字 h2 封鎖・ci)" "6" "$NH2ALL"
chk "entity-card 数 == |entities| (census)"      "$NENT"   "$(grep -o 'data-component="entity-card"' "$BODY" | wc -l | tr -d ' ')"
chk "entity-field-row 数 == Σ|fields| (census)"  "$NFIELD" "$(grep -o 'data-component="entity-field-row"' "$BODY" | wc -l | tr -d ' ')"
chk "relationship-row 数 == |relationships| (census)" "$NREL" "$(grep -o 'data-component="relationship-row"' "$BODY" | wc -l | tr -d ' ')"
chk "data-policy-card 数 == |data_policy| (census)" "$NDP"  "$(grep -o 'data-component="data-policy-card"' "$BODY" | wc -l | tr -d ' ')"
chk "er-diagram (mermaid pre) 数 == |diagrams| (census)" "$NDIAG" "$(grep -c 'class="mermaid"' "$BODY")"
chk "er-diagram data-component 数 == |diagrams|"  "$NDIAG"  "$(grep -o 'data-component="er-diagram"' "$BODY" | wc -l | tr -d ' ')"
chk "figcaption 数 == |diagrams|"                "$NDIAG"  "$(grep -c '<figcaption>' "$BODY")"
chk "er-notation-legend == |diagrams|"           "$NDIAG"  "$(grep -o 'data-component="er-notation-legend"' "$BODY" | wc -l | tr -d ' ')"
chk "principle-terminal == 1"                    "1"       "$(grep -c 'data-component="principle-terminal"' "$BODY")"

# ============ ③b ★band 見出し fidelity (folio-bhe・arch chapters と同型) ============
BAND_H2S="$(perl -CSD -0777 -ne 'while (m{<section\b[^>]*data-component="chapter-deck-band"[^>]*>(.*?)</section>}gis){ my $b=$1; my @h=($b =~ m{<h2\b[^>]*>(.*?)</h2>}gis); print scalar(@h)==1 ? "$h[0]\n" : "(band 内 h2 数=".scalar(@h)."≠1)\n"; }' "$BODY")"
band_h2_at() { sed -n "${1}p" <<<"$BAND_H2S"; }
chk "band h2[1] == context (pack 固定)"         "なぜ「情報の持ち方」を先に決めるのか"      "$(band_h2_at 1)"
chk "band h2[2] == overview (pack 固定)"        "全体像を一枚の ER 図で見渡す"              "$(band_h2_at 2)"
chk "band h2[3] == esc(chapters.entities_band)" "$(esc "$(q '.chapters.entities_band')")"    "$(band_h2_at 3)"
chk "band h2[4] == esc(chapters.relationships_band)" "$(esc "$(q '.chapters.relationships_band')")" "$(band_h2_at 4)"
chk "band h2[5] == data-policy (pack 固定)"     "何を持たず、 何のために使い、 いつ消すか"   "$(band_h2_at 5)"
chk "band h2[6] == glossary (pack 固定)"        "本文に出てくる言葉のやさしい説明"          "$(band_h2_at 6)"

# ★数詞 == 派生実件数 (肯定形・全出現照合 + 複合語 false-match 除去 + sc= 句読点境界。 assemble-datamodel と parity)。
band_numchk() { # $1=label $2=heading-text $3=unit-literal $4=expected-count
  local ns n bad=""
  ns="$(UNIT="$3" perl -CSD -Mutf8 -ne 'my $u=$ENV{UNIT}; utf8::decode($u); while(/([0-9]+)\s*\Q$u\E(?![\p{sc=Han}\p{sc=Katakana}ー])/g){print "$1\n"}' <<<"$2" || true)"
  if [[ -z "$ns" ]]; then chk "$1" "$4" "(ASCII 数詞なし=半角必須)"; return; fi
  while IFS= read -r n; do [[ "$n" == "$4" ]] || bad="$n"; done <<<"$ns"
  chk "$1" "$4" "${bad:-$4}"
}
# HTML h2 == contract 上で一致済ゆえ contract 値で判定 (detect↔remediate parity)。 entities=「N つの情報のかたまり」/ relationships=「N つのつながり」。
band_numchk "band 数詞: entities_band「N つの情報のかたまり」== |entities|" "$(q '.chapters.entities_band')" 'つの情報のかたまり' "$NENT"
band_numchk "band 数詞: relationships_band「N つのつながり」== |relationships|" "$(q '.chapters.relationships_band')" 'つのつながり' "$NREL"
# 全角数字 (件数照合の回避表記) を entities/relationships band で禁止 (HTML==contract fidelity 成立済ゆえ contract 値で判定)。
chk "band 数詞: entities_band に全角数字なし" "0" "$(q '.chapters.entities_band' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
chk "band 数詞: relationships_band に全角数字なし" "0" "$(q '.chapters.relationships_band' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
# 不可視/format 文字 (ゼロ幅・BOM 等) を全 6 見出しで拒否 (数詞隣接破壊 injection 封鎖)。
chk "band 見出し (全 6) に不可視/format 文字なし" "0" \
  "$(printf '%s' "$BAND_H2S" | perl -CSD -Mutf8 -ne '$n++ while /\p{Default_Ignorable_Code_Point}/g; END{print $n+0}')"

# ============ ② navigable id アンカー (照会されうる全ノードに id= ・集合一致) ============
exp_anchor="$( {
  q '.entities[].id'     | sed 's/^/entity-/'
  q '.relationships[].id' | sed 's/^/rel-/'
  q '.data_policy[].id'  | sed 's/^/dp-/'
} | LC_ALL=C sort )"
act_anchor="$(perl -CSD -0777 -ne 'while (/\bid="(entity-[^"]+|rel-[^"]+|dp-[^"]+)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "navigable id アンカー (entity-/rel-/dp-) == contract" "$exp_anchor" "$act_anchor"
chk "principle 終端 anchor id=principle-<id>" "1" "$(grep -c "id=\"principle-$(q '.principle.id')\"" "$BODY")"
chk "sec-data-policy anchor (ec-sens deep-link 先) == 1" "1" "$(grep -c 'id="sec-data-policy"' "$BODY")"
chk "ec-sens link 数 == |sensitivity high|"   "$NHIGH" "$(grep -o '<a class="ec-sens"' "$BODY" | wc -l | tr -d ' ')"
chk "entity-card.sens-high 数 == |sensitivity high|" "$NHIGH" "$(grep -o 'data-component="entity-card" class="sens-high"' "$BODY" | wc -l | tr -d ' ')"
# ★per-entity 機微度 束縛 (kind と同型・folio-229 relocation 封鎖)。 entity-card の class="sens-high" と ec-sens バッジ有無を
#   entity-id 単位で対に束ね contract の (entity-id, sensitivity) と集合一致。 上の count-only (ec-sens/sens-high 件数) は
#   high↔normal 入替 (件数保持) を素通しする — どの個人情報が「特に慎重に扱う PII」かはデータガバナンスの中核主張ゆえ per-entity で捕捉する。
exp_sens="$(q '.entities[] | ["entity-"+.id, .sensitivity] | @tsv' | while IFS=$'\t' read -r _eid _s; do
  if [[ "$_s" == "high" ]]; then printf '%s\thigh\t1\n' "$(esc "$_eid")"; else printf '%s\tnormal\t0\n' "$(esc "$_eid")"; fi
done | LC_ALL=C sort)"
act_sens="$(perl -CSD -0777 -ne '
  while (/<article data-component="entity-card"([^>]*?)\bid="entity-([^"]+)">(.*?)<\/article>/gs) {
    my ($attrs,$id,$blk)=($1,$2,$3);
    my $sens=($attrs=~/class="sens-high"/)?"high":"normal";
    my $badge=($blk=~/<a class="ec-sens"/)?1:0;
    print "entity-$id\t$sens\t$badge\n";
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-entity 機微度 三つ組 (entity-id, sens-class, ec-sens badge) == contract" "$exp_sens" "$act_sens"

# ============ id 一意性 ============
chk_empty "entities id 一意"     "$(q '.entities[].id'     | sort | uniq -d | tr '\n' ' ')"
chk_empty "relationships id 一意" "$(q '.relationships[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "data_policy id 一意"   "$(q '.data_policy[].id'  | sort | uniq -d | tr '\n' ' ')"

# ============ ① 照会グラフ整合 (cross-doc 前方照会・core 共通スケルトン) ============
# SRS 充足照会 (role=claim・data-dm-ref/data-dm-role)。 entities+relationships+data_policy の refs.srs を横断集合で。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-dm-ref" --role-attr "data-dm-role" \
  --keys-expr '(.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[])' \
  --count-expr '[.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]] | length' \
  --nonempty-count-expr '[ (.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]) | select((. // "") != "") ] | length' \
  --pair-expr '(.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]) | [., "claim"] | @tsv' \
  --target-ids-expr '(.requirements[].id, .nfr[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 1d. ★per-card 照会 fidelity (card-keyed・folio-229 §5b relocation 封鎖)。 entity-/rel-/dp- カードスコープ内の
#   (data-dm-ref, claim) を card-id へ束ねた三つ組集合を contract と突合。 card 間で ref を入替えても global set 不変ゆえ本 pin が捕捉。
exp_cardref="$( {
  q '.entities[]     | .id as $id | .refs.srs[] | ["entity-"+$id, ., "claim"] | @tsv'
  q '.relationships[] | .id as $id | .refs.srs[] | ["rel-"+$id, ., "claim"] | @tsv'
  q '.data_policy[]  | .id as $id | .refs.srs[] | ["dp-"+$id, ., "claim"] | @tsv'
} | grep . | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardref="$(perl -CSD -0777 -ne '
  while (/<article data-component="entity-card"[^>]*\bid="entity-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-dm-ref="([^"]*)"\s+data-dm-role="([^"]*)"/gs) { print "entity-$id\t$1\t$2\n"; }
  }
  while (/<article data-component="relationship-row"[^>]*\bid="rel-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-dm-ref="([^"]*)"\s+data-dm-role="([^"]*)"/gs) { print "rel-$id\t$1\t$2\n"; }
  }
  while (/<div data-component="data-policy-card"[^>]*\bid="dp-([^"]+)">(.*?)(?=<div data-component="data-policy-card"|<div data-component="principle-terminal")/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-dm-ref="([^"]*)"\s+data-dm-role="([^"]*)"/gs) { print "dp-$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card SRS 照会 三つ組 (card-id, ref, claim) == contract" "$exp_cardref" "$act_cardref"

# 1g. ★可視 srs-badge テキスト == 兄弟 data-dm-ref (照会コードの可視捏造封鎖・deep-link 表示 REQ-ID pin の一部)。
badge_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-dm-ref="([^"]*)"\s+data-dm-role="[^"]*">([^<]*)<\/a>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 srs-badge テキスト == 兄弟 data-dm-ref (可視捏造封鎖)" "$badge_bad"
chk "srs-badge 総数 == |SRS照会| (孤立 badge 封鎖)" "$NSRS" "$(grep -o '<a class="srs-badge"' "$BODY" | wc -l | tr -d ' ')"

# 1h. ★href 遷移先 deep-link fidelity (fragment == 表示 REQ-ID・anchor swap / 外部 host / filename swap 封鎖)。
#   (href, data-dm-ref) == (<srs_html>#<ref>, ref)。 href が決定的に contract 由来 + fragment==REQ-ID を証明。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
exp_href="$(q '(.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[])' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-dm-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: SRS badge (href, ref) == <srs_html>#<ref> (deep-link fragment==REQ-ID)" "$exp_href" "$act_href"

# ============ cross-doc 可視 echo 厳密一致 (表紙 ref-chip・marker-keyed・nested reject) ============
chk "cross-doc: ref-chip ブロック == 1" "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
chip_bad="$(SRS="$srs_id_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"chip:".scalar(@bs)."B"; next}
    push @bad,"chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"chip:VIS" if $vis ne " 照会先: ${srs}の要件 (FR / NFR)";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: ref-chip 可視 echo == テンプレ+doc_id (swap/平文/nested 封鎖)" "$chip_bad"

# ============ core 共通 chrome (cover-head/approval/glossary 値突合・folio-mk9) ============
verify_core_chrome

# ============ cover-meta KV (種別/構成/照会先/版) の決定的再導出突合 ============
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別"   "data-model (データモデル)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 構成"   "$(esc "情報のかたまり ${NENT} / つながり ${NREL}")" "$(printf '%s\n' "$meta_kv" | grep -F '構成' | head -1 | cut -f2)"
chk "cover-meta 照会先" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(printf '%s\n' "$meta_kv" | grep -F '照会先' | head -1 | cut -f2)"
chk "cover-meta 版"     "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# ============ 各章ノードの可視テキスト fidelity (emission 順・属性 intact のまま可視改竄/捏造を封鎖) ============
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
# --- §1 context ---
set_eq "可視 context problem == .context.problem" "$(qesc '.context.problem')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p data-component="context-problem">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 scope_note == .context.scope_note" "$(qesc '.context.scope_note')" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="scope-note-callout"><span class="sn-lab">[^<]*<\/span>([^<]*)<\/div>/g){ print "$1\n"; }' "$BODY")"
# --- §3 entities ---
set_eq "可視 entity name == .entities[].name" "$(qesc '.entities[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ec-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 entity description == .entities[].description" "$(qesc '.entities[].description')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="ec-desc">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# entity kind (class,label) ordered — ec-name 直後の ec-kind に anchor (kind-legend の demo badge を除外)。
exp_ekind="$(q '.entities[].kind' | while IFS= read -r _k; do case "$_k" in master) printf 'master\t台帳\n' ;; event) printf 'event\t記録\n' ;; *) printf '%s\t%s\n' "$_k" "$_k" ;; esac; done)"
set_eq "可視 entity kind (class,label) == .entities[].kind 派生" "$exp_ekind" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ec-name">[^<]*<\/span><span class="ec-kind ([a-z]+)">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
# entity field: name / type(class,label) / note / required
set_eq "可視 field name == .entities[].fields[].name" "$(qesc '.entities[].fields[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<td class="ef-name">([^<]*)<\/td>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 field type label == .entities[].fields[].type" "$(qesc '.entities[].fields[].type')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ef-type[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# field type class 整合 (識別子→id / 参照→ref / それ以外→無印) を emission 順 (class-suffix, label) で突合。
exp_ftype_cls="$(q '.entities[].fields[].type' | while IFS= read -r _t; do case "$_t" in 識別子) printf 'ef-type id\t%s\n' "$_t" ;; 参照) printf 'ef-type ref\t%s\n' "$_t" ;; *) printf 'ef-type\t%s\n' "$_t" ;; esac; done)"
set_eq "可視 field type (class,label) == type 派生 (識別子=id/参照=ref)" "$exp_ftype_cls" \
  "$(perl -CSD -0777 -ne 'while (/<span class="(ef-type(?: id| ref)?)">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
set_eq "可視 field note == .entities[].fields[].note" "$(qesc '.entities[].fields[].note')" \
  "$(perl -CSD -0777 -ne 'while (/<td class="ef-note">([^<]*)<\/td>/g){ print "$1\n"; }' "$BODY")"
chk "ef-req 必須バッジ数 == Σ required=true" "$(q '[.entities[].fields[] | select(.required==true)] | length')" "$(grep -o '<span class="ef-req">必須</span>' "$BODY" | wc -l | tr -d ' ')"
# ★per-field required 束縛 (entity-id, field-name, required)。 上の Σ count は必須バッジを別フィールドへ移す (件数保持) 捏造を
#   素通しする — どのフィールドが必須かは入力規律の主張ゆえ、 field を entity-id/field-name へ束ねて required 有無を突合する。
exp_req="$(q '.entities[] | .id as $id | .fields[] | ["entity-"+$id, .name, (.required|tostring)] | @tsv' \
  | grep . | while IFS=$'\t' read -r _a _b _c; do printf '%s\t%s\t%s\n' "$(esc "$_a")" "$(esc "$_b")" "$_c"; done | LC_ALL=C sort)"
act_req="$(perl -CSD -0777 -ne '
  while (/<article data-component="entity-card"[^>]*\bid="entity-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/<tr data-component="entity-field-row">(.*?)<\/tr>/gs) {
      my $row=$1; my ($fn)=$row=~/<td class="ef-name">([^<]*)<\/td>/;
      my $req=($row=~/<span class="ef-req">/)?"true":"false";
      print "entity-$id\t$fn\t$req\n";
    }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-field required 三つ組 (entity-id, field-name, required) == contract" "$exp_req" "$act_req"
# --- §4 relationships ---
set_eq "可視 rel-id == .relationships[].id" "$(qesc '.relationships[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rel-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# rel-ent (from-name, to-name) を emission 順 (per-row interleave) で突合。 ★mikefarah yq の `(.from,.to)` は
#   from 全件→to 全件の順ゆえ interleave にならない。 per-rel [.from,.to] を tsv で受け 1 行ずつ name 化する。
exp_relent="$(q '.relationships[] | [.from, .to] | @tsv' | while IFS=$'\t' read -r _f _t; do
  esc "$(FROMID="$_f" yq -r '.entities[] | select(.id==strenv(FROMID)) | .name' "$CONTRACT")"; printf '\n'
  esc "$(TOID="$_t" yq -r '.entities[] | select(.id==strenv(TOID)) | .name' "$CONTRACT")"; printf '\n'
done)"
set_eq "可視 rel-ent (from,to name) == .relationships[].from/to 派生" "$exp_relent" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rel-ent">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# ★rel-verb 抽出パターンは — / → の multibyte リテラルを含むゆえ -Mutf8 必須 (無いと byte/char 不一致で無 match)。
set_eq "可視 rel-verb label == .relationships[].label" "$(qesc '.relationships[].label')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="ar">—<\/span>([^<]*)<span class="ar">→<\/span>/g){ print "$1\n"; }' "$BODY")"
# rel-card (cardinality 派生ラベル) emission 順 (ラベルに esc 要文字なし = 直接構築。 while-read の最終行 drop を避ける)。
exp_relcard="$(q '.relationships[].cardinality' | while IFS= read -r _c; do case "$_c" in one-to-many) echo '1 対 多' ;; one-to-zero-or-one) echo '1 対 0〜1' ;; one-to-one) echo '1 対 1' ;; many-to-many) echo '多 対 多' ;; *) echo "$_c" ;; esac; done)"
set_eq "可視 rel-card == .relationships[].cardinality 派生" "$exp_relcard" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rel-card">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 rel-plain == .relationships[].plain" "$(qesc '.relationships[].plain')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="rel-plain">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# invariant (存在するもののみ・emission 順)
exp_inv="$(q '.relationships[] | select(.invariant) | .invariant' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
set_eq "可視 invariant iv-txt == .relationships[].invariant (存在分)" "$exp_inv" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="iv-txt">(.*?)<\/span>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
chk "invariant-callout 数 == |invariant 保有 rel|" "$(q '[.relationships[] | select(.invariant)] | length')" "$(grep -o 'data-component="invariant-callout"' "$BODY" | wc -l | tr -d ' ')"
# has-invariant class 数 == invariant 保有数
chk "relationship-row.has-invariant 数 == |invariant 保有 rel|" "$(q '[.relationships[] | select(.invariant)] | length')" "$(grep -o 'data-component="relationship-row" class="has-invariant"' "$BODY" | wc -l | tr -d ' ')"
# ★per-rel 不変条件 束縛 (rel-id, has-invariant class, iv-txt)。 上の flat set (line 上の invariant iv-txt set) は
#   *emission 順の* 平坦集合ゆえ、 不変条件を「順序を保ったまま」別 rel へ移す (例 REL-2→REL-1) と set/count が不変で素通しする
#   — 「どの rel が不変条件を持つか」は不変条件の帰属主張ゆえ、 rel-id へ class+text を束ねて突合する (relocation 封鎖)。
exp_relinv="$(q '.relationships[] | ["rel-"+.id, (.invariant // "")] | @tsv' | while IFS=$'\t' read -r _rid _iv; do
  if [[ -n "$_iv" ]]; then printf '%s\thasinv\t%s\n' "$(esc "$_rid")" "$(esc "$_iv")"; else printf '%s\tnoinv\t\n' "$(esc "$_rid")"; fi
done | LC_ALL=C sort)"
act_relinv="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<article data-component="relationship-row"([^>]*?)\bid="rel-([^"]+)">(.*?)<\/article>/gs) {
    my ($attrs,$id,$blk)=($1,$2,$3);
    my $cls=($attrs=~/class="has-invariant"/)?"hasinv":"noinv";
    my $iv="";
    if ($blk=~/<span class="iv-txt">(.*?)<\/span>/s) { $iv=$1; $iv=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g; $iv=~s/[\t\n]/ /g; }
    print "rel-$id\t$cls\t$iv\n";
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-rel 不変条件 三つ組 (rel-id, has-invariant, iv-txt) == contract" "$exp_relinv" "$act_relinv"
# --- §5 data_policy ---
set_eq "可視 dp-id == .data_policy[].id" "$(qesc '.data_policy[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="dp-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 dp-rule == .data_policy[].rule" "$(qesc '.data_policy[].rule')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="dp-rule">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 dp-reason == .data_policy[].reason" "$(qesc '.data_policy[].reason')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="dp-reason">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# --- §5 原則終端 (pt-id / pt-text) ---
chk "principle-terminal pt-id == principle.id" "$(esc "$(q '.principle.id')")" \
  "$(perl -CSD -0777 -ne 'while (/<span class="pt-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "principle-terminal pt-text == principle.text" "$(esc "$(q '.principle.text')")" \
  "$(perl -CSD -0777 -ne 'while (/<p class="pt-text">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"

# ============ ER 図 (mermaid DSL + figcaption) fidelity ============
declare -A DIAG_TAG_V=( [er]="ER — Entity Relationship" )
mapfile -t DIAGIDS < <(q '.diagrams[].id')
mapfile -t ACT_MERMAID < <(perl -CSD -0777 -ne 'while (/<pre class="mermaid">(.*?)<\/pre>/gs){ my $t=$1; $t=~s/\n/\x01/g; print "$t\n"; }' "$BODY")
mapfile -t ACT_FIGCAP < <(perl -CSD -0777 -ne 'while (/<figcaption>(.*?)<\/figcaption>/gs){ my $t=$1; $t=~s/\n/ /g; print "$t\n"; }' "$BODY")
diag_i=0
for did in "${DIAGIDS[@]}"; do
  kind="$(q '.diagrams[] | select(.id=="'"$did"'") | .kind')"
  exp_m="$(q '.diagrams[] | select(.id=="'"$did"'") | .lines[]' | while IFS= read -r ln; do esc "$ln"; printf '\x01'; done | sed 's/\x01$//')"
  chk "図[$did] mermaid DSL == esc(contract lines)" "$exp_m" "${ACT_MERMAID[$diag_i]:-MISSING}"
  exp_cap="<span class=\"diag-tag\">$(esc "${DIAG_TAG_V[$kind]}")</span>$(esc "$(q '.diagrams[] | select(.id=="'"$did"'") | .caption')")"
  chk "図[$did] figcaption == diag-tag + esc(caption)" "$exp_cap" "${ACT_FIGCAP[$diag_i]:-MISSING}"
  diag_i=$((diag_i+1))
done

# ============ 横展開 CJK inline 強調の空白規律 (FAIL) ============
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

# ============ plain-language-term-inline fidelity + 用語被覆 (assemble-datamodel と同一語境界規律) ============
verify_term_inline \
  '.context.problem, .entities[].description, .relationships[].plain, .relationships[].invariant, .data_policy[].rule, .data_policy[].reason' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
# ---- gate F: render 健全性 (visual) mermaid pack 展開 (folio-jyfh B 段・helper=render_gate_f)。 mermaid 図 (ER
#      diagram) を含む生成 HTML を light/dark × 3 viewport で render-gate し、 SVG settle polling (最大 15s) で
#      非同期 render を待ってから幾何/contrast を検査する。 vendor は render_gate_f が配信 root へ staging。
#      fail-closed (violation/crash/settle 不足 = $fail=1・T7 guard 維持)。 SKIP_RENDER=1 で bash floor は SKIP。 ----
render_gate_f "$HTML" "DATAMODEL_SKIP_RENDER"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 固定章 + 照会 graph + id anchor + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
