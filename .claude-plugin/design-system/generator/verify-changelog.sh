#!/usr/bin/env bash
# folio engine post-B6 (folio-8ptq) — changelog-pack fabrication-free + version-keyed + semver 順序 + cross-doc 後方照会 proof
#
# 生成 changelog HTML の *構造* が入力 changelog contract から完全に導出されたことを機械検証する floor gate。
# verify-testcases.sh (cross-doc 照会型) / verify-arch.sh (多目標照会型) と同型の規律を changelog-pack schema へ適用:
#   - 件数 (changelog-entry / changelog-item / trace-row / prose スロット / hl-count) が contract 要素数と一致。
#   - ★semver 降順の決定的順序 (本 pack の核): entry の version バッジ emission 順 == sort -rV (unreleased 先頭)。
#       version の乱れ/捏造/入替を封鎖。 trace-row / item-card の emission 順も同一の決定的順序に pin。
#   - ★最新版ハイライトの 6 category 件数 (正の主張 + 負の主張「0 件=変更なし」の両方) を contract から決定的再導出で突合。
#   - ★cross-doc 後方照会 (本 pack の核): 各変更項目の refs.srs (FR・claim) / refs.adr (ADR・rationale) が
#       (a) HTML data-cl-{srs,adr}-ref 集合と集合一致 + count anchor、 (b) 参照先 SRS/ADR contract に実在、
#       (c) doc_id 一致、 (d)(d') role 整合、 (e) href 遷移先が contract 派生。 共通スケルトン = core (verify_cross_doc_refs × 2)。
#   - ★per-item card-keyed 束縛 (relocation 封鎖): 各 item が (どの版・どの category・どの照会) を持つかを構造的に pin。
#   - core 共通 chrome・escape 健全性・prose スロット mode・term-inline。
#
# usage: verify-changelog.sh [--filled <manifest.yaml> | --artifact] <changelog-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate・S5.1)。 plain 要約 (cover-summary / chapter-lead / latest-highlight / plain-Cx) の
#   *内容真正性* は floor の対象外 = ceiling (fidelity-changelog + persona-walk-changelog)。 floor 単独 GREEN にはならず CEILING=PENDING。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-changelog.sh [--filled <manifest> | --artifact] <changelog-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-changelog.sh [--filled <manifest> | --artifact] <changelog-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-changelog: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-changelog: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-changelog: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-changelog: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-changelog: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-changelog: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23)。
verify_repro_build changelog "$FILLED_MANIFEST"

# ---- 決定的順序 + category メタ (assembler と同一・detect↔remediate parity) ----
ITEMS_EXPR='[(.unreleased.categories // {} | .[][]), (.entries[].categories | .[][])]'
mapfile -t OV < <(q '.entries[].version' | sort -rV)
HAS_UNREL="$(q 'has("unreleased")')"
KEYS=(); [[ "$HAS_UNREL" == "true" ]] && KEYS+=("unreleased"); KEYS+=("${OV[@]}")
CAT_ORDER=(added changed deprecated removed fixed security)
declare -A CAT_LABEL=( [added]=追加 [changed]=変更 [deprecated]=非推奨 [removed]=削除 [fixed]=修正 [security]=セキュリティ )
declare -A CAT_CLASS=( [added]=add [changed]=chg [deprecated]=dep [removed]=rem [fixed]=fix [security]=sec )
sel_of() { [[ "$1" == "unreleased" ]] && printf '.unreleased' || printf '.entries[] | select(.version=="%s")' "$1"; }
verlabel_of() { [[ "$1" == "unreleased" ]] && printf '未リリース' || printf 'v%s' "$1"; }
# gen_order — emission 順 (unreleased 先頭 → 版 semver 降順 → category canonical 順 → 配列順) の (key<TAB>cat<TAB>id)。
gen_order() {
  local key sel cat n i id
  for key in "${KEYS[@]}"; do
    sel="$(sel_of "$key")"
    for cat in "${CAT_ORDER[@]}"; do
      n="$(q "$sel | .categories.$cat // [] | length")"
      for ((i=0; i<n; i++)); do id="$(q "$sel | .categories.$cat[$i] | .id")"; printf '%s\t%s\t%s\n' "$key" "$cat" "$id"; done
    done
  done
}
mapfile -t ORDER < <(gen_order)

NITEM="$(q "$ITEMS_EXPR | length")"
NSRS="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length")"
NADR="$(q "$ITEMS_EXPR | [.[].refs.adr // [] | .[]] | length")"
NEDGE=$((NSRS + NADR))
NVER="$(q '.entries | length')"
NENTRY=${#KEYS[@]}
LATEST="${OV[0]}"

# ★class-token / data-component 機械的網羅 (srs idiom・novel-marker 注入を一網打尽に封鎖)。
CL_CLS="add chapbody chg cl-cat cl-cat-head cl-cat-label cl-cats cl-entries cl-id cl-items cl-plain cl-ref cl-ref-k cl-ref-label cl-ref-row cl-refs cl-text cl-ver-badge cl-ver-date cl-ver-head cover-eyebrow cover-meta cover-sub dep doc-type en fix foot ft-grid ft-plain gdef grow gword hl-count hl-counts hl-date hl-head hl-summary hl-tag hl-ver hlc-label hlc-n ic ico k kicker lab lead m num page reader-chip rem req role sec self sign stamp summary-card tags term tint-brand tint-info tint-ok tint-violet trc-cat trc-code trc-edge trc-id trc-label trc-ref trc-req trc-ver trc-why txt unreleased v when who why xref-code"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $CL_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker 注入封鎖)" "$unknown_cls"
CL_DC="approval-block changelog-entry changelog-highlights changelog-item changelog-trace chapter-deck-band cross-doc-ref-chip doc-cover-band fidelity-sync-meta glossary-term-table plain-language-term-inline requirement-type-color-tokens trace-row"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $CL_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel dc 注入封鎖)" "$unknown_dc"
echo "changelog-pack fabrication-free + version-keyed + semver 順序 + cross-doc 後方照会 proof: $HTML"
echo "  contract: $CONTRACT  ($NVER 版 / $NITEM 項目 / SRS照会 $NSRS / ADR照会 $NADR)"

# ============ 1. 件数 ============
chk "changelog-entry 数 == 版数(+unreleased)" "$NENTRY" "$(grep -c 'data-component="changelog-entry"' "$BODY")"
chk "changelog-item 数 == |items|"            "$NITEM"  "$(grep -c 'data-component="changelog-item"' "$BODY")"
chk "trace-row 数 == |items|"                 "$NITEM"  "$(grep -c 'data-component="trace-row"' "$BODY")"
chk "changelog-highlights == 1"               "1"       "$(grep -c 'data-component="changelog-highlights"' "$BODY")"
chk "hl-count 数 == 6 (Keep a Changelog 全 category)" "6" "$(count_attr_token class hl-count < "$BODY")"
# 全 h2 は band 見出しのみ (4 章)。 band 外/属性 decoy/大文字 h2 封鎖 (arch idiom・ci)。
NH2="$(perl -CSD -0777 -ne '$n++ while m{<h2\b}gi; END{print $n+0}' "$BODY")"
chk "全 <h2> 要素数 == 4 (band 4 章のみ・decoy 封鎖・ci)" "4" "$NH2"

# ============ 2. ★semver 降順の決定的順序 (本 pack の核) ============
# entry の version バッジ (cl-ver-badge) の可視テキスト emission 順が「unreleased 先頭 → 版 semver 降順」と厳密一致。
exp_verorder="$( { [[ "$HAS_UNREL" == "true" ]] && printf '未リリース\n'; for v in "${OV[@]}"; do printf 'v%s\n' "$v"; done; } )"
act_verorder="$(perl -CSD -0777 -ne 'while (/<span class="cl-ver-badge[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "版バッジ emission 順 == unreleased+semver 降順 (順序改竄封鎖)" "$exp_verorder" "$act_verorder"
# ★版バッジ class == unreleased 修飾子の整合 (unreleased だけ .unreleased・版は無印)。
exp_verbadge_cls="$( { [[ "$HAS_UNREL" == "true" ]] && printf 'cl-ver-badge unreleased\n'; for v in "${OV[@]}"; do printf 'cl-ver-badge\n'; done; } )"
act_verbadge_cls="$(perl -CSD -0777 -ne 'while (/<span class="(cl-ver-badge[^"]*)">/g){ print "$1\n"; }' "$BODY")"
set_eq "版バッジ class (unreleased 修飾子) == 期待 (順序)" "$exp_verbadge_cls" "$act_verbadge_cls"
# ★版の日付 (cl-ver-date) emission 順 == 各 entry の date (unreleased は「次リリース予定」固定)。
exp_verdate="$( { [[ "$HAS_UNREL" == "true" ]] && printf '次リリース予定\n'; for v in "${OV[@]}"; do esc "$(q '.entries[] | select(.version=="'"$v"'") | .date')"; printf '\n'; done; } )"
act_verdate="$(perl -CSD -0777 -ne 'while (/<span class="cl-ver-date">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "版の日付 emission 順 == contract date (順序)" "$exp_verdate" "$act_verdate"

# ============ 3. ★最新版ハイライトの category 件数 (正の主張 + 負の主張「0 件」両方) ============
sel_latest="$(sel_of "$LATEST")"
chk "highlights hl-ver == v<latest>"  "v$(esc "$LATEST")" "$(perl -CSD -0777 -ne 'while (/<span class="hl-ver">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "highlights hl-date == latest date" "$(esc "$(q "$sel_latest | .date")")" "$(perl -CSD -0777 -ne 'while (/<span class="hl-date">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "highlights hl-tag == 最新版 (固定)" "1" "$(grep -c '<span class="hl-tag">最新版</span>' "$BODY")"
# 6 category (canonical 順) の (label, 件数) を contract から決定的再導出し emission 順で厳密突合。
#   ★件数 0 (負の主張「この種別の変更なし」) も *必ず* 表示され contract 由来値と一致 (0→非0 偽装を封鎖)。
exp_hlcounts="$(for cat in "${CAT_ORDER[@]}"; do printf '%s\t%s\n' "$(esc "${CAT_LABEL[$cat]}")" "$(esc "$(q "$sel_latest | .categories.$cat // [] | length")")"; done)"
act_hlcounts="$(perl -CSD -0777 -ne 'while (/<span class="hlc-label">([^<]*)<\/span><span class="hlc-n">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
set_eq "highlights (category, 件数) == contract 派生 (0=負の主張含む・順序)" "$exp_hlcounts" "$act_hlcounts"

# ============ 4. id 一意性 + 全 item id emission 順 ============
chk_empty "変更項目 id 一意" "$(q "$ITEMS_EXPR | .[].id" | sort | uniq -d | tr '\n' ' ')"
exp_idorder="$(printf '%s\n' "${ORDER[@]}" | cut -f3)"
act_idorder="$(perl -CSD -0777 -ne 'while (/<li data-component="changelog-item" id="cl-([^"]+)">/g){ print "$1\n"; }' "$BODY")"
set_eq "item card id emission 順 == 決定的順序 (unreleased→semver降順→category→配列)" "$exp_idorder" "$act_idorder"
# 可視 cl-id バッジ == item id (emission 順)。
set_eq "可視 cl-id == item id (順序)" "$exp_idorder" \
  "$(perl -CSD -0777 -ne 'while (/<span class="cl-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"

# ============ 5. ★cross-doc 後方照会 (本 pack の核・core 共通スケルトン × 2) ============
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
ADR_REL="$(q '.cross_doc.adr_contract')"; ADR_ABS="${CONTRACT_DIR}/${ADR_REL}"
# SRS FR 照会 (role=claim・data-cl-srs-ref/role)。
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-cl-srs-ref" --role-attr "data-cl-srs-role" \
  --keys-expr "$ITEMS_EXPR | .[].refs.srs // [] | .[]" \
  --count-expr "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length" \
  --nonempty-count-expr "$ITEMS_EXPR | [.[].refs.srs // [] | .[] | select((. // \"\") != \"\")] | length" \
  --pair-expr "$ITEMS_EXPR | .[].refs.srs // [] | .[] | [., \"claim\"] | @tsv" \
  --target-ids-expr '.requirements[].id' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'
# ADR 判断 照会 (role=rationale・data-cl-adr-ref/role・doc 粒度照会 = ADR doc_id)。
verify_cross_doc_refs \
  --label-prefix "cross-doc(ADR)" --target-label "ADR" \
  --target-abs "$ADR_ABS" --target-rel "$ADR_REL" \
  --key-attr "data-cl-adr-ref" --role-attr "data-cl-adr-role" \
  --keys-expr "$ITEMS_EXPR | .[].refs.adr // [] | .[]" \
  --count-expr "$ITEMS_EXPR | [.[].refs.adr // [] | .[]] | length" \
  --nonempty-count-expr "$ITEMS_EXPR | [.[].refs.adr // [] | .[] | select((. // \"\") != \"\")] | length" \
  --pair-expr "$ITEMS_EXPR | .[].refs.adr // [] | .[] | [., \"rationale\"] | @tsv" \
  --target-ids-expr '.meta.doc_id' \
  --contract-docid-expr '.cross_doc.adr_doc_id' \
  --target-docid-expr '.meta.doc_id'

# ============ 6. ★per-item card-keyed 照会束縛 (relocation 封鎖) ============
# 各 item card (id=cl-<id>) スコープ内の (data-cl-*-ref, role) を id へ束ねた三つ組集合を contract と集合一致で突合。
# global set / count / (key,role) ペアは 5 で担保済ゆえ、 「どの変更がどの照会を持つか」を pin (card 間 relocation 封鎖)。
# ★mikefarah yq の `.id as $id | ((A),(B))` は空 branch (片側 refs 欠如) で空行を吐く ゆえ grep . で除去 (arch idiom)。
exp_cardref="$(q "$ITEMS_EXPR | .[] | .id as \$id | ((.refs.srs // [] | .[] | [\$id, ., \"claim\"]), (.refs.adr // [] | .[] | [\$id, ., \"rationale\"])) | @tsv" | grep . \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardref="$(perl -CSD -0777 -ne '
  while (/<li data-component="changelog-item" id="cl-([^"]+)">(.*?)<\/li>/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/data-cl-srs-ref="([^"]*)" data-cl-srs-role="([^"]*)"/g){ print "$id\t$1\t$2\n"; }
    while ($blk=~/data-cl-adr-ref="([^"]*)" data-cl-adr-role="([^"]*)"/g){ print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-item 照会 三つ組 (id, ref, role) == contract (card-keyed・relocation封鎖)" "$exp_cardref" "$act_cardref"

# ============ 7. ★href 遷移先 fidelity (リンクの飛び先を contract 派生へ束縛) ============
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"; ADR_HTML_E="$(esc "$(q '.cross_doc.adr_html')")"
# (SRS claim href, FR) == <srs_html>#<ref> — item カードの cl-ref のみ (trace は下で別途)。
chk "href: <a class=cl-ref ... data-cl-srs-ref> 数 == |SRS照会|" "$NSRS" "$(grep -oE '<a class="cl-ref" href="[^"]*" data-cl-srs-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_srs_href="$(q "$ITEMS_EXPR | .[].refs.srs // [] | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_srs_href="$(perl -CSD -0777 -ne 'while (/<a class="cl-ref" href="([^"]*)" data-cl-srs-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: cl-ref SRS (href, FR) == <srs_html>#<ref> (anchor/filename swap 封鎖)" "$exp_srs_href" "$act_srs_href"
# (ADR rationale href, doc_id) == <adr_html>#decision。
chk "href: <a class=cl-ref ... data-cl-adr-ref> 数 == |ADR照会|" "$NADR" "$(grep -oE '<a class="cl-ref" href="[^"]*" data-cl-adr-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_adr_href="$(q "$ITEMS_EXPR | .[].refs.adr // [] | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#decision\t%s\n' "$ADR_HTML_E" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_adr_href="$(perl -CSD -0777 -ne 'while (/<a class="cl-ref" href="([^"]*)" data-cl-adr-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: cl-ref ADR (href, doc_id) == <adr_html>#decision" "$exp_adr_href" "$act_adr_href"
# ★可視 xref-code == 兄弟 data-cl-*-ref 属性 (照会コードの可視捏造封鎖)。 xref-code 総数 == |edges|×2 (item + trace)。
xref_code_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-cl-(?:srs|adr)-ref="([^"]*)"[^>]*><span class="xref-code">([^<]*)<\/span>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 xref-code == 兄弟 data-cl-*-ref (item 照会コードの可視捏造封鎖)" "$xref_code_bad"
chk "item xref-code 総数 == |SRS+ADR照会| (孤立 echo 封鎖)" "$NEDGE" "$(grep -o '<span class="xref-code">' "$BODY" | wc -l | tr -d ' ')"

# ============ 8. ★照会ラベル併記 fidelity (SRS=機能名 / ADR=live title) ============
# item + trace 両所にラベル併記。 (ref, 可視ラベル) 集合が SRS/ADR 由来と厳密一致 (捏造/swap 封鎖)。
chk "data-srs-label-ref 数 == |SRS照会|×2 (item + trace)" "$((NSRS*2))" "$(grep -o 'data-srs-label-ref=' "$BODY" | wc -l | tr -d ' ')"
chk "data-adr-label-ref 数 == |ADR照会|×2 (item + trace)" "$((NADR*2))" "$(grep -o 'data-adr-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_srslabels="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | unique | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(FR="$_r" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")")"; done | LC_ALL=C sort -u)"
act_srslabels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-srs-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "SRS 機能名ラベル (ref, label) == SRS 由来 (FR=label)" "$exp_srslabels" "$act_srslabels"
# ADR ラベル = 「ADR: <参照先 ADR の実 .meta.title>」 live-mirror (retitle drift fail-closed)。
ADR_TITLE_E="$(esc "ADR: $(yq -r '.meta.title' "$ADR_ABS")")"
act_adrlabel="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-adr-label-ref="[^"]*"[^>]*>([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
chk "ADR ラベル == 「ADR: 」+ 参照先 .meta.title (live-mirror・retitle drift 封鎖)" "$ADR_TITLE_E" "$act_adrlabel"
# ★双子属性 per-edge 等値 (8ptq ceiling 実証: valid-pair を card 間 relocation すると上の集合一致は素通り)。
# item card: <a class="cl-ref" ... data-cl-<k>-ref="X"> 内包 label span の data-<k>-label-ref は kind/値とも X に等値。
twin_item_pairs="$(perl -CSD -0777 -ne '
  while (/<a class="cl-ref"[^>]*data-cl-(srs|adr)-ref="([^"]*)"[^>]*>(.*?)<\/a>/gs) {
    my ($k,$ref,$inner)=($1,$2,$3);
    while ($inner=~/data-(srs|adr)-label-ref="([^"]*)"/gs){ print "$k\t$ref\t$1\t$2\n"; }
  }' "$BODY")"
chk "双子属性 抽出 (cl-ref 内 label span) 数 == |SRS+ADR照会| (存在 assert・恒真PASS封鎖)" "$NEDGE" "$(printf '%s' "$twin_item_pairs" | grep -c .)"
twin_item_bad="$(printf '%s' "$twin_item_pairs" | awk -F'\t' '$1!=$3 || $2!=$4 {printf "cl:%s(%s)!=%s(%s) ", $4, $3, $2, $1}')"
chk_empty "双子属性等値: cl-ref anchor data-cl-*-ref == 内包 data-*-label-ref (valid-pair relocation 封鎖)" "$twin_item_bad"
# trace edge: <a class="trc-code ...">CODE</a> 直後 label span の data-*-label-ref は CODE に等値。
twin_trc_pairs="$(perl -CSD -0777 -ne '
  while (/<span class="trc-edge"><a class="trc-code[^"]*"[^>]*>([^<]*)<\/a> <span class="trc-label" data-(?:srs|adr)-label-ref="([^"]*)"/gs){ print "$1\t$2\n"; }' "$BODY")"
chk "双子属性 抽出 (trc-edge label span) 数 == |SRS+ADR照会| (存在 assert)" "$NEDGE" "$(printf '%s' "$twin_trc_pairs" | grep -c .)"
twin_trc_bad="$(printf '%s' "$twin_trc_pairs" | awk -F'\t' '$1!=$2 {printf "trc:%s!=%s ", $2, $1}')"
chk_empty "双子属性等値: trc-edge 可視コード == 隣接 data-*-label-ref (trace relocation 封鎖)" "$twin_trc_bad"

# ============ 9. ★per-item 構造束縛 (item が どの版・どの category に属すか) ============
# entry card (id=ver-*) スコープ内の cl-cat グループ (class=category) → item id を構造抽出し、 (key, cat-class, cat-label, id) を
# 決定的順序から導出した期待集合と *集合一致* で突合。 item card を別版/別 category へ動かす relocation を構造的に封鎖。
exp_struct="$(printf '%s\n' "${ORDER[@]}" | while IFS=$'\t' read -r key cat id; do printf '%s\t%s\t%s\t%s\n' "$(esc "$key")" "${CAT_CLASS[$cat]}" "$(esc "${CAT_LABEL[$cat]}")" "$(esc "$id")"; done | LC_ALL=C sort)"
act_struct="$(perl -CSD -0777 -ne '
  while (/<div data-component="changelog-entry" id="ver-([^"]+)">(.*?)(?=<div data-component="changelog-entry"|<section data-component="chapter-deck-band")/gs) {
    my ($key,$eblk)=($1,$2);
    while ($eblk=~/<div class="cl-cat (\w+)"><div class="cl-cat-head"><span class="cl-cat-label">([^<]*)<\/span><\/div>(.*?)<\/ul><\/div>/gs) {
      my ($cls,$lbl,$cblk)=($1,$2,$3);
      while ($cblk=~/<li data-component="changelog-item" id="cl-([^"]+)"/g){ print "$key\t$cls\t$lbl\t$1\n"; }
    }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-item 構造束縛 (版, category-class, label, id) == 決定的順序 (relocation封鎖)" "$exp_struct" "$act_struct"

# ============ 10. ★item text 可視 fidelity (card-keyed・term-inline strip) ============
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
exp_cardtext="$(q "$ITEMS_EXPR | .[] | [.id, .text] | @tsv" | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_cardtext="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<li data-component="changelog-item" id="cl-([^"]+)">(.*?)<\/li>/gs) {
    my ($id,$blk)=($1,$2);
    if ($blk=~/<p class="cl-text"><span class="cl-id">[^<]*<\/span>(.*?)<\/p>/s){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$id\t$t\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "item text 可視 (id, text) == contract (card-keyed・捏造/relocation封鎖)" "$exp_cardtext" "$act_cardtext"

# ============ 11. ★trace 表 fidelity (行=変更項目・emission 順 + code 束縛) ============
# 各 trace-row の (id, verlabel, catlabel) を決定的順序から導出し emission 順で厳密突合。
exp_trace="$(printf '%s\n' "${ORDER[@]}" | while IFS=$'\t' read -r key cat id; do printf '%s\t%s\t%s\n' "$(esc "$id")" "$(esc "$(verlabel_of "$key")")" "$(esc "${CAT_LABEL[$cat]}")"; done)"
act_trace="$(perl -CSD -0777 -ne '
  while (/<tr data-component="trace-row"><td class="trc-id"><a href="#cl-[^"]*">([^<]*)<\/a><\/td><td class="trc-ver">([^<]*)<\/td><td class="trc-cat">([^<]*)<\/td>/g){ print "$1\t$2\t$3\n"; }' "$BODY")"
set_eq "trace 行 (id, 版, 区分) == 決定的順序 (順序・捏造封鎖)" "$exp_trace" "$act_trace"
# trace 行の trc-id リンク先 == #cl-<id> (自 doc 内 anchor 健全性)。
trcid_href_bad="$(perl -CSD -0777 -ne 'my @b; while (/<td class="trc-id"><a href="#cl-([^"]*)">([^<]*)<\/a>/g){ push @b,"$1\x{2260}$2" if $1 ne $2; } print join(" ",@b);' "$BODY")"
chk_empty "trace trc-id リンク == #cl-<id> (可視 id == anchor)" "$trcid_href_bad"
# trace 内の照会 code (trc-code) を row スコープで抽出し (id → refs code 集合) を contract と card-keyed 突合。
exp_trace_ref="$(q "$ITEMS_EXPR | .[] | .id as \$id | ((.refs.adr // [] | .[]), (.refs.srs // [] | .[])) | [\$id, .] | @tsv" | grep . \
  | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_trace_ref="$(perl -CSD -0777 -ne '
  while (/<tr data-component="trace-row">(.*?)<\/tr>/gs){ my $row=$1; my ($id)=$row=~/trc-id"><a href="#cl-([^"]*)"/;
    while ($row=~/<a class="trc-code[^"]*"[^>]*>([^<]*)<\/a>/g){ print "$id\t$1\n"; } }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "trace 照会 code (id, ref) == contract (row-keyed)" "$exp_trace_ref" "$act_trace_ref"
# trace href (trc-code) の飛び先 == contract 派生 (ADR=#decision / SRS=#<fr>)。可視 code == href anchor。
trace_href_bad="$(SRS="$SRS_HTML_E" ADR="$ADR_HTML_E" perl -CSD -Mutf8 -0777 -ne '
  my $s=$ENV{SRS}; utf8::decode($s); my $a=$ENV{ADR}; utf8::decode($a); my @bad;
  while (/<a class="trc-code (trc-why|trc-req)" href="([^"]*)">([^<]*)<\/a>/g){ my ($k,$h,$c)=($1,$2,$3);
    my $exp = $k eq "trc-why" ? "$a#decision" : "$s#$c"; push @bad,"$c:$h" if $h ne $exp; }
  print join(" ",@bad);' "$BODY")"
chk_empty "trace href == contract 派生 (ADR=#decision / SRS=#<fr>・可視 code と整合)" "$trace_href_bad"

# ============ 12. ★静的テンプレ chrome ラベルの固定値 pin (visible-text-vs-attribute の "other" 型) ============
# (a) band 見出し (h2・pack 固定 4 本・順序)。 assembler drift / 見出し捏造を封鎖。
exp_h2="$(printf '%s\n%s\n%s\n%s' 'いちばん新しい版で何が変わったか' '新しい版から順に、 追加・変更・修正を並べる' 'どの変更が、 なぜ (ADR) / どの要件 (SRS) のためか' '本文に出てくる専門語のやさしい説明')"
act_h2="$(perl -CSD -0777 -ne 'while (/<h2>([^<]*)<\/h2>/g){ print "$1\n"; }' "$BODY" | perl -pe 'chomp if eof')"
set_eq "band h2 見出し 4 本 == pack 固定 (順序・捏造封鎖)" "$exp_h2" "$act_h2"
# (b) cl-ref-k ラベル (なぜ/要件) は行 role に束縛 (why→なぜ / req→要件・swap 封鎖) + 件数。
clrefk_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<div class="cl-ref-row (why|req)"><span class="cl-ref-k">([^<]*)<\/span>/g){ my ($r,$l)=($1,$2); my $e=$r eq "why"?"なぜ":"要件"; push @b,"$r:$l" if $l ne $e; } print join(" ",@b);' "$BODY")"
chk_empty "cl-ref-k 行 role 束縛 (why→なぜ/req→要件・swap封鎖)" "$clrefk_bad"
# cl-ref-row why 数 == adr を持つ item 数 / req 数 == srs を持つ item 数。
chk "cl-ref-row.why 数 == adr を持つ item 数" "$(q "$ITEMS_EXPR | [.[] | select(((.refs.adr // []) | length) > 0)] | length")" "$(grep -c '<div class="cl-ref-row why">' "$BODY")"
chk "cl-ref-row.req 数 == srs を持つ item 数" "$(q "$ITEMS_EXPR | [.[] | select(((.refs.srs // []) | length) > 0)] | length")" "$(grep -c '<div class="cl-ref-row req">' "$BODY")"
# (c) cl-cat-label 総数 == 全 entry の present category 数 + 各 label ⊆ canonical。
n_catgroups="$(printf '%s\n' "${ORDER[@]}" | cut -f1,2 | sort -u | wc -l | tr -d ' ')"
chk "cl-cat-label 総数 == present category グループ数" "$n_catgroups" "$(grep -c '<span class="cl-cat-label">' "$BODY")"
catlabel_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<span class="cl-cat-label">([^<]*)<\/span>/g){ my $l=$1; push @b,$l unless $l eq "追加"||$l eq "変更"||$l eq "非推奨"||$l eq "削除"||$l eq "修正"||$l eq "セキュリティ"; } print join(" ",@b);' "$BODY")"
chk_empty "cl-cat-label ⊆ {追加,変更,非推奨,削除,修正,セキュリティ} (未知 category label 封鎖)" "$catlabel_bad"
# (d) trace thead 列ヘッダ 4 本 (順序固定) + <th> 総数 == 4 (case/attr-robust・列追加封鎖)。
exp_th="$(printf '変更\n版\n区分\n参照先 (なぜ / 要件)')"
act_th="$(grep -oE '<th>[^<]*</th>' "$BODY" | sed -E 's#<th>([^<]*)</th>#\1#')"
chk "trace thead 列ヘッダ 4 本 == 固定 (順序)" "$exp_th" "$act_th"
chk "trace <th> 総数 == 4 (case/attr-robust・列追加封鎖)" "4" "$(grep -oiE '<th\b' "$BODY" | wc -l | tr -d ' ')"
chk "trace tbody <tr> 総数 == 1+|items| (phantom 行封鎖)" "$((NITEM+1))" "$(grep -oiE '<tr\b' "$BODY" | wc -l | tr -d ' ')"
chk "trace <td> 総数 == 4×|items| (余剰 td 封鎖)" "$((NITEM*4))" "$(grep -oiE '<td\b' "$BODY" | wc -l | tr -d ' ')"
chk "trace <tfoot> == 0 (偽承認 tfoot 封鎖)" "0" "$(grep -oiE '<tfoot\b' "$BODY" | wc -l | tr -d ' ')"
chk "trace <caption> == 0 (偽承認 caption 封鎖)" "0" "$(grep -oiE '<caption\b' "$BODY" | wc -l | tr -d ' ')"
chk "全 <table> == 1 (別 table 注入封鎖)" "1" "$(grep -oiE '<table\b' "$BODY" | wc -l | tr -d ' ')"

# ============ 13. ★cross-doc 可視 echo (表紙 ref-chip) 厳密一致 (marker-keyed・nested-reject) ============
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

# ============ 14. core 共通 chrome + cover-meta KV ============
verify_core_chrome
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
# ★key で exact 抽出 (grep -F は 収録 value「N 版」が key「版」に誤 match するため awk 完全一致で分離)。
kv_v() { printf '%s\n' "$meta_kv" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }
chk "cover-meta 種別"   "changelog (変更履歴)" "$(kv_v 種別)"
chk "cover-meta 収録"   "$(esc "${NVER} 版 (v${OV[-1]}–v${OV[0]})")" "$(kv_v 収録)"
chk "cover-meta 最新"   "$(esc "v${LATEST} / $(q "$sel_latest | .date")")" "$(kv_v 最新)"
chk "cover-meta 版"     "$(esc "v$(q '.meta.version') / $(q '.meta.date')")" "$(kv_v 版)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# ============ 15. escape 健全性 ============
chk "化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"          "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# ============ 16. prose スロット mode (pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実) ============
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

# ============ 17. plain-language-term-inline fidelity + 用語被覆 (assemble-changelog と同一語境界規律) ============
verify_term_inline \
  "$ITEMS_EXPR | .[].text" \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
# ---- gate F: render 健全性 (visual) 非 mermaid pack 展開。 ----
render_gate_f "$HTML" "CHANGELOG_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  # mode 別詳細 (旧 reason 語 artifact/filled/fabrication-free を substring 保全)。
  if [[ -n "$ARTIFACT" ]]; then mode_detail="mode=artifact: 構造 fabrication-free + semver 順序 + cross-doc 照会解決 + prose 全充填"
  elif [[ -n "$FILLED_MANIFEST" ]]; then mode_detail="mode=filled: 構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実"
  else mode_detail="mode=fabrication-free: 構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空"; fi
  # ceiling-precheck sentinel を verify-adr.sh:398 同型で統一 emit (folio-vxpc)。 詳細は verify-research.sh の同節参照。
  echo "RESULT: floor PASS ($mode_detail) — ただし CEILING=PENDING (*GREEN ではない*)"
  if [[ "${CHANGELOG_SKIP_RENDER:-0}" == "1" || "${SKIP_RENDER:-0}" == "1" ]]; then
    echo "  ※ render gate 未完 (F=見た目崩れ が未実行: CHANGELOG_SKIP_RENDER/SKIP_RENDER) — CI/uv 環境で render を回すまで floor は不完全。"
  fi
  echo "  ceiling = persona-walk-changelog + fidelity-changelog (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に blocking arm (構造/semver 順序/cross-doc 照会/prose/gate F) が不合格"
  exit 1
fi
