#!/usr/bin/env bash
# folio engine post-B6 (folio-8cha) — roadmap-pack fabrication-free + stage-keyed + seq 順序 + cross-doc 前方照会 proof
#
# 生成 roadmap HTML の *構造* が入力 roadmap contract から完全に導出されたことを機械検証する floor gate。
# verify-changelog.sh (stage/version-keyed 型) / verify-vision.sh (記述型 cross-doc) と同型の規律を roadmap-pack schema へ適用:
#   - 件数 (roadmap-stage / roadmap-item / trace-row / prose スロット / hl-count) が contract 要素数と一致。
#   - ★seq 昇順の決定的順序 (本 pack の核): stage の badge/name/target/outcome emission 順 == sort -n。
#       段階の乱れ/捏造/入替を封鎖。 trace-row / item-card の emission 順も同一の決定的順序に pin。
#   - ★直近段階ハイライトの 3 priority 件数 (正の主張 + 負の主張「0 件=この優先度の目標なし」の両方) を contract から決定的再導出で突合。
#   - ★cross-doc 前方照会 (本 pack の核): 各目標項目の refs.vision (F・claim) / refs.srs (FR・claim) が
#       (a) HTML data-rm-{vision,srs}-ref 集合と集合一致 + count anchor、 (b) 参照先 VISION/SRS contract に実在、
#       (c) doc_id 一致、 (d)(d') role 整合、 (e) href 遷移先が contract 派生。 共通スケルトン = core (verify_cross_doc_refs × 2)。
#   - ★per-item card-keyed 束縛 (relocation 封鎖): 各 item が (どの段階・どの priority・どの照会) を持つかを構造的に pin。
#   - ★照会ラベル双子属性 per-edge 等値 (8ptq ceiling 実証を最初から組込): item + trace 両 shape で anchor-ref == label-ref。
#   - core 共通 chrome・escape 健全性・prose スロット mode・term-inline。
#
# usage: verify-roadmap.sh [--filled <manifest.yaml> | --artifact] <roadmap-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate・S5.1)。 plain 要約 (cover-summary / chapter-lead / nearest-highlight / plain-RMx) の
#   *内容真正性* は floor の対象外 = ceiling (fidelity-roadmap + persona-walk-roadmap)。 floor 単独 GREEN にはならず CEILING=PENDING。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-roadmap.sh [--filled <manifest> | --artifact] <roadmap-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-roadmap.sh [--filled <manifest> | --artifact] <roadmap-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-roadmap: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-roadmap: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-roadmap: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-roadmap: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-roadmap: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-roadmap: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23)。
verify_repro_build roadmap "$FILLED_MANIFEST"

# ---- 決定的順序 + priority メタ (assembler と同一・detect↔remediate parity) ----
ITEMS_EXPR='[.stages[].items | .[][]]'
mapfile -t OS < <(q '.stages[].seq' | sort -n)
PRIO_ORDER=(must should could)
declare -A PRIO_LABEL=( [must]=必須 [should]=推奨 [could]=任意 )
declare -A PRIO_CLASS=( [must]=must [should]=should [could]=could )
sel_of() { printf '.stages[] | select(.seq==%s)' "$1"; }
sid_of() { q ".stages[] | select(.seq==$1) | .id"; }
# gen_order — emission 順 (stage seq 昇順 → priority canonical 順 → 配列順) の (seq<TAB>prio<TAB>id)。
gen_order() {
  local seq sel prio n i id
  for seq in "${OS[@]}"; do
    sel="$(sel_of "$seq")"
    for prio in "${PRIO_ORDER[@]}"; do
      n="$(q "$sel | .items.$prio // [] | length")"
      for ((i=0; i<n; i++)); do id="$(q "$sel | .items.$prio[$i] | .id")"; printf '%s\t%s\t%s\n' "$seq" "$prio" "$id"; done
    done
  done
}
mapfile -t ORDER < <(gen_order)

NITEM="$(q "$ITEMS_EXPR | length")"
NVIS="$(q "$ITEMS_EXPR | [.[].refs.vision // [] | .[]] | length")"
NSRS="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length")"
NEDGE=$((NVIS + NSRS))
NSTAGE="$(q '.stages | length')"
FIRST="${OS[0]}"

# ★class-token / data-component 機械的網羅 (srs idiom・novel-marker 注入を一網打尽に封鎖)。
RM_CLS="chapbody could cover-eyebrow cover-meta cover-sub dir doc-type en foot ft-grid ft-plain gdef grow gword hl-count hl-counts hl-head hl-stage hl-summary hl-tag hl-target hlc-label hlc-n ic ico k kicker lab lead m must num page reader-chip req rm-id rm-items rm-plain rm-prio rm-prio-head rm-prio-label rm-prios rm-ref rm-ref-k rm-ref-label rm-ref-row rm-refs rm-stage-badge rm-stage-head rm-stage-name rm-stage-outcome rm-stage-target rm-stages rm-text role self should sign stamp summary-card tags term tint-brand tint-info tint-ok tint-violet trc-code trc-dir trc-edge trc-id trc-label trc-prio trc-ref trc-req trc-stage txt v when who xref-code"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RM_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker 注入封鎖)" "$unknown_cls"
RM_DC="approval-block chapter-deck-band cross-doc-ref-chip doc-cover-band fidelity-sync-meta glossary-term-table plain-language-term-inline requirement-type-color-tokens roadmap-highlights roadmap-item roadmap-stage roadmap-trace trace-row"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RM_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel dc 注入封鎖)" "$unknown_dc"
echo "roadmap-pack fabrication-free + stage-keyed + seq 順序 + cross-doc 前方照会 proof: $HTML"
echo "  contract: $CONTRACT  ($NSTAGE 段階 / $NITEM 項目 / VISION照会 $NVIS / SRS照会 $NSRS)"

# ============ 1. 件数 ============
chk "roadmap-stage 数 == 段階数"                  "$NSTAGE" "$(grep -c 'data-component="roadmap-stage"' "$BODY")"
chk "roadmap-item 数 == |items|"                  "$NITEM"  "$(grep -c 'data-component="roadmap-item"' "$BODY")"
chk "trace-row 数 == |items|"                     "$NITEM"  "$(grep -c 'data-component="trace-row"' "$BODY")"
chk "roadmap-highlights == 1"                     "1"       "$(grep -c 'data-component="roadmap-highlights"' "$BODY")"
chk "hl-count 数 == 3 (MoSCoW 全 priority)"        "3"       "$(count_attr_token class hl-count < "$BODY")"
# 全 h2 は band 見出しのみ (4 章)。 band 外/属性 decoy/大文字 h2 封鎖 (arch idiom・ci)。
NH2="$(perl -CSD -0777 -ne '$n++ while m{<h2\b}gi; END{print $n+0}' "$BODY")"
chk "全 <h2> 要素数 == 4 (band 4 章のみ・decoy 封鎖・ci)" "4" "$NH2"

# ============ 2. ★seq 昇順の決定的順序 (本 pack の核) ============
# stage の badge (rm-stage-badge=stage id) の可視テキスト emission 順が「seq 昇順の stage id」と厳密一致。
exp_stageorder="$(for s in "${OS[@]}"; do esc "$(sid_of "$s")"; printf '\n'; done)"
act_stageorder="$(perl -CSD -0777 -ne 'while (/<span class="rm-stage-badge">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "stage badge emission 順 == seq 昇順の stage id (順序改竄封鎖)" "$exp_stageorder" "$act_stageorder"
# stage name emission 順 == seq 昇順の name。
exp_stagename="$(for s in "${OS[@]}"; do esc "$(q "$(sel_of "$s") | .name")"; printf '\n'; done)"
act_stagename="$(perl -CSD -0777 -ne 'while (/<span class="rm-stage-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "stage name emission 順 == contract name (順序)" "$exp_stagename" "$act_stagename"
# stage target emission 順 == seq 昇順の target。
exp_stagetarget="$(for s in "${OS[@]}"; do esc "$(q "$(sel_of "$s") | .target")"; printf '\n'; done)"
act_stagetarget="$(perl -CSD -0777 -ne 'while (/<span class="rm-stage-target">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "stage target emission 順 == contract target (順序)" "$exp_stagetarget" "$act_stagetarget"

# ============ 3. ★直近段階ハイライトの priority 件数 (正の主張 + 負の主張「0 件」両方) ============
sel_first="$(sel_of "$FIRST")"
chk "highlights hl-stage == <直近 stage id>"  "$(esc "$(sid_of "$FIRST")")" "$(perl -CSD -0777 -ne 'while (/<span class="hl-stage">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "highlights hl-target == 直近 target"     "$(esc "$(q "$sel_first | .target")")" "$(perl -CSD -0777 -ne 'while (/<span class="hl-target">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "highlights hl-tag == 直近 (固定)"         "1" "$(grep -c '<span class="hl-tag">直近</span>' "$BODY")"
# 3 priority (canonical 順) の (label, 件数) を contract から決定的再導出し emission 順で厳密突合。
#   ★件数 0 (負の主張「この優先度の目標なし」) も *必ず* 表示され contract 由来値と一致 (0→非0 偽装を封鎖)。
exp_hlcounts="$(for prio in "${PRIO_ORDER[@]}"; do printf '%s\t%s\n' "$(esc "${PRIO_LABEL[$prio]}")" "$(esc "$(q "$sel_first | .items.$prio // [] | length")")"; done)"
act_hlcounts="$(perl -CSD -0777 -ne 'while (/<span class="hlc-label">([^<]*)<\/span><span class="hlc-n">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
set_eq "highlights (priority, 件数) == contract 派生 (0=負の主張含む・順序)" "$exp_hlcounts" "$act_hlcounts"

# ============ 4. id 一意性 + 全 item id emission 順 ============
chk_empty "目標項目 id 一意" "$(q "$ITEMS_EXPR | .[].id" | sort | uniq -d | tr '\n' ' ')"
exp_idorder="$(printf '%s\n' "${ORDER[@]}" | cut -f3)"
act_idorder="$(perl -CSD -0777 -ne 'while (/<li data-component="roadmap-item" id="rm-([^"]+)">/g){ print "$1\n"; }' "$BODY")"
set_eq "item card id emission 順 == 決定的順序 (seq昇順→priority→配列)" "$exp_idorder" "$act_idorder"
# 可視 rm-id バッジ == item id (emission 順)。
set_eq "可視 rm-id == item id (順序)" "$exp_idorder" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rm-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"

# ============ 5. ★cross-doc 前方照会 (本 pack の核・core 共通スケルトン × 2) ============
VISION_REL="$(q '.cross_doc.vision_contract')"; VISION_ABS="${CONTRACT_DIR}/${VISION_REL}"
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
# VISION 方向 照会 (role=claim・data-rm-vision-ref/role・ID 粒度照会 = feature F)。
verify_cross_doc_refs \
  --label-prefix "cross-doc(VISION)" --target-label "VISION" \
  --target-abs "$VISION_ABS" --target-rel "$VISION_REL" \
  --key-attr "data-rm-vision-ref" --role-attr "data-rm-vision-role" \
  --keys-expr "$ITEMS_EXPR | .[].refs.vision // [] | .[]" \
  --count-expr "$ITEMS_EXPR | [.[].refs.vision // [] | .[]] | length" \
  --nonempty-count-expr "$ITEMS_EXPR | [.[].refs.vision // [] | .[] | select((. // \"\") != \"\")] | length" \
  --pair-expr "$ITEMS_EXPR | .[].refs.vision // [] | .[] | [., \"claim\"] | @tsv" \
  --target-ids-expr '.features[].id' \
  --contract-docid-expr '.cross_doc.vision_doc_id' \
  --target-docid-expr '.meta.doc_id'
# SRS 要件 照会 (role=claim・data-rm-srs-ref/role・ID 粒度照会 = 要件 FR)。
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-rm-srs-ref" --role-attr "data-rm-srs-role" \
  --keys-expr "$ITEMS_EXPR | .[].refs.srs // [] | .[]" \
  --count-expr "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length" \
  --nonempty-count-expr "$ITEMS_EXPR | [.[].refs.srs // [] | .[] | select((. // \"\") != \"\")] | length" \
  --pair-expr "$ITEMS_EXPR | .[].refs.srs // [] | .[] | [., \"claim\"] | @tsv" \
  --target-ids-expr '.requirements[].id' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# ============ 6. ★per-item card-keyed 照会束縛 (relocation 封鎖) ============
# 各 item card (id=rm-<id>) スコープ内の (data-rm-*-ref, role) を id へ束ねた三つ組集合を contract と集合一致で突合。
# global set / count / (key,role) ペアは 5 で担保済ゆえ、 「どの目標がどの照会を持つか」を pin (card 間 relocation 封鎖)。
exp_cardref="$(q "$ITEMS_EXPR | .[] | .id as \$id | ((.refs.vision // [] | .[] | [\$id, ., \"claim\"]), (.refs.srs // [] | .[] | [\$id, ., \"claim\"])) | @tsv" | grep . \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardref="$(perl -CSD -0777 -ne '
  while (/<li data-component="roadmap-item" id="rm-([^"]+)">(.*?)<\/li>/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/data-rm-vision-ref="([^"]*)" data-rm-vision-role="([^"]*)"/g){ print "$id\t$1\t$2\n"; }
    while ($blk=~/data-rm-srs-ref="([^"]*)" data-rm-srs-role="([^"]*)"/g){ print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-item 照会 三つ組 (id, ref, role) == contract (card-keyed・relocation封鎖)" "$exp_cardref" "$act_cardref"

# ============ 7. ★href 遷移先 fidelity (リンクの飛び先を contract 派生へ束縛) ============
VISION_HTML_E="$(esc "$(q '.cross_doc.vision_html')")"; SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
# (VISION claim href, F) == <vision_html>#<ref> — item カードの rm-ref のみ (trace は下で別途)。
chk "href: <a class=rm-ref ... data-rm-vision-ref> 数 == |VISION照会|" "$NVIS" "$(grep -oE '<a class="rm-ref" href="[^"]*" data-rm-vision-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_vis_href="$(q "$ITEMS_EXPR | .[].refs.vision // [] | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$VISION_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_vis_href="$(perl -CSD -0777 -ne 'while (/<a class="rm-ref" href="([^"]*)" data-rm-vision-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: rm-ref VISION (href, F) == <vision_html>#<ref> (anchor/filename swap 封鎖)" "$exp_vis_href" "$act_vis_href"
# (SRS claim href, FR) == <srs_html>#<ref>。
chk "href: <a class=rm-ref ... data-rm-srs-ref> 数 == |SRS照会|" "$NSRS" "$(grep -oE '<a class="rm-ref" href="[^"]*" data-rm-srs-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_srs_href="$(q "$ITEMS_EXPR | .[].refs.srs // [] | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_srs_href="$(perl -CSD -0777 -ne 'while (/<a class="rm-ref" href="([^"]*)" data-rm-srs-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: rm-ref SRS (href, FR) == <srs_html>#<ref>" "$exp_srs_href" "$act_srs_href"
# ★可視 xref-code == 兄弟 data-rm-*-ref 属性 (照会コードの可視捏造封鎖)。 xref-code 総数 == |edges| (item)。
xref_code_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-rm-(?:vision|srs)-ref="([^"]*)"[^>]*><span class="xref-code">([^<]*)<\/span>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 xref-code == 兄弟 data-rm-*-ref (item 照会コードの可視捏造封鎖)" "$xref_code_bad"
chk "item xref-code 総数 == |VISION+SRS照会| (孤立 echo 封鎖)" "$NEDGE" "$(grep -o '<span class="xref-code">' "$BODY" | wc -l | tr -d ' ')"

# ============ 8. ★照会ラベル併記 fidelity (VISION=機能方向名 / SRS=要件ラベル) ============
# item + trace 両所にラベル併記。 (ref, 可視ラベル) 集合が VISION/SRS 由来と厳密一致 (捏造/swap 封鎖)。
chk "data-vision-label-ref 数 == |VISION照会|×2 (item + trace)" "$((NVIS*2))" "$(grep -o 'data-vision-label-ref=' "$BODY" | wc -l | tr -d ' ')"
chk "data-srs-label-ref 数 == |SRS照会|×2 (item + trace)"       "$((NSRS*2))" "$(grep -o 'data-srs-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_vislabels="$(q "$ITEMS_EXPR | [.[].refs.vision // [] | .[]] | unique | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(F="$_r" yq -r '.features[] | select(.id==strenv(F)) | .name' "$VISION_ABS")")"; done | LC_ALL=C sort -u)"
act_vislabels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-vision-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "VISION 機能方向ラベル (ref, label) == VISION 由来 (F=name)" "$exp_vislabels" "$act_vislabels"
exp_srslabels="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | unique | .[]" | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(FR="$_r" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")")"; done | LC_ALL=C sort -u)"
act_srslabels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-srs-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "SRS 要件ラベル (ref, label) == SRS 由来 (FR=label)" "$exp_srslabels" "$act_srslabels"
# ★双子属性 per-edge 等値 (8ptq ceiling 実証: valid-pair を card 間 relocation すると上の集合一致は素通り)。
# item card: <a class="rm-ref" ... data-rm-<k>-ref="X"> 内包 label span の data-<k>-label-ref は kind/値とも X に等値。
twin_item_pairs="$(perl -CSD -0777 -ne '
  while (/<a class="rm-ref"[^>]*data-rm-(vision|srs)-ref="([^"]*)"[^>]*>(.*?)<\/a>/gs) {
    my ($k,$ref,$inner)=($1,$2,$3);
    while ($inner=~/data-(vision|srs)-label-ref="([^"]*)"/gs){ print "$k\t$ref\t$1\t$2\n"; }
  }' "$BODY")"
chk "双子属性 抽出 (rm-ref 内 label span) 数 == |VISION+SRS照会| (存在 assert・恒真PASS封鎖)" "$NEDGE" "$(printf '%s' "$twin_item_pairs" | grep -c .)"
twin_item_bad="$(printf '%s' "$twin_item_pairs" | awk -F'\t' '$1!=$3 || $2!=$4 {printf "rm:%s(%s)!=%s(%s) ", $4, $3, $2, $1}')"
chk_empty "双子属性等値: rm-ref anchor data-rm-*-ref == 内包 data-*-label-ref (valid-pair relocation 封鎖)" "$twin_item_bad"
# trace edge: <a class="trc-code ...">CODE</a> 直後 label span の data-*-label-ref は CODE に等値。
twin_trc_pairs="$(perl -CSD -0777 -ne '
  while (/<span class="trc-edge"><a class="trc-code[^"]*"[^>]*>([^<]*)<\/a> <span class="trc-label" data-(?:vision|srs)-label-ref="([^"]*)"/gs){ print "$1\t$2\n"; }' "$BODY")"
chk "双子属性 抽出 (trc-edge label span) 数 == |VISION+SRS照会| (存在 assert)" "$NEDGE" "$(printf '%s' "$twin_trc_pairs" | grep -c .)"
twin_trc_bad="$(printf '%s' "$twin_trc_pairs" | awk -F'\t' '$1!=$2 {printf "trc:%s!=%s ", $2, $1}')"
chk_empty "双子属性等値: trc-edge 可視コード == 隣接 data-*-label-ref (trace relocation 封鎖)" "$twin_trc_bad"

# ============ 9. ★per-item 構造束縛 (item が どの段階・どの priority に属すか) ============
# stage card (id=stage-*) スコープ内の rm-prio グループ (class=priority) → item id を構造抽出し、 (seq, prio-class, prio-label, id) を
# 決定的順序から導出した期待集合と *集合一致* で突合。 item card を別段階/別 priority へ動かす relocation を構造的に封鎖。
exp_struct="$(printf '%s\n' "${ORDER[@]}" | while IFS=$'\t' read -r seq prio id; do printf '%s\t%s\t%s\t%s\n' "$(esc "$seq")" "${PRIO_CLASS[$prio]}" "$(esc "${PRIO_LABEL[$prio]}")" "$(esc "$id")"; done | LC_ALL=C sort)"
act_struct="$(perl -CSD -0777 -ne '
  while (/<div data-component="roadmap-stage" id="stage-([^"]+)">(.*?)(?=<div data-component="roadmap-stage"|<section data-component="chapter-deck-band")/gs) {
    my ($seq,$sblk)=($1,$2);
    while ($sblk=~/<div class="rm-prio (\w+)"><div class="rm-prio-head"><span class="rm-prio-label">([^<]*)<\/span><\/div>(.*?)<\/ul><\/div>/gs) {
      my ($cls,$lbl,$pblk)=($1,$2,$3);
      while ($pblk=~/<li data-component="roadmap-item" id="rm-([^"]+)"/g){ print "$seq\t$cls\t$lbl\t$1\n"; }
    }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-item 構造束縛 (seq, priority-class, label, id) == 決定的順序 (relocation封鎖)" "$exp_struct" "$act_struct"

# ============ 10. ★item text + stage outcome 可視 fidelity (card-keyed・term-inline strip) ============
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
exp_cardtext="$(q "$ITEMS_EXPR | .[] | [.id, .text] | @tsv" | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_cardtext="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<li data-component="roadmap-item" id="rm-([^"]+)">(.*?)<\/li>/gs) {
    my ($id,$blk)=($1,$2);
    if ($blk=~/<p class="rm-text"><span class="rm-id">[^<]*<\/span>(.*?)<\/p>/s){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$id\t$t\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "item text 可視 (id, text) == contract (card-keyed・捏造/relocation封鎖)" "$exp_cardtext" "$act_cardtext"
# stage outcome (叙述) の可視 fidelity (seq-keyed・記述型の核)。
exp_outcome="$(q '.stages[] | [.seq, .outcome] | @tsv' | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_outcome="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<div data-component="roadmap-stage" id="stage-([^"]+)">(.*?)<p class="rm-stage-outcome">(.*?)<\/p>/gs) {
    my ($seq,$t)=($1,$3); '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$seq\t$t\n";
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "stage outcome 可視 (seq, outcome) == contract (seq-keyed・捏造封鎖)" "$exp_outcome" "$act_outcome"

# ============ 11. ★trace 表 fidelity (行=目標項目・emission 順 + code 束縛) ============
# 各 trace-row の (id, stage-id, prio-label) を決定的順序から導出し emission 順で厳密突合。
exp_trace="$(printf '%s\n' "${ORDER[@]}" | while IFS=$'\t' read -r seq prio id; do printf '%s\t%s\t%s\n' "$(esc "$id")" "$(esc "$(sid_of "$seq")")" "$(esc "${PRIO_LABEL[$prio]}")"; done)"
act_trace="$(perl -CSD -0777 -ne '
  while (/<tr data-component="trace-row"><td class="trc-id"><a href="#rm-[^"]*">([^<]*)<\/a><\/td><td class="trc-stage">([^<]*)<\/td><td class="trc-prio">([^<]*)<\/td>/g){ print "$1\t$2\t$3\n"; }' "$BODY")"
set_eq "trace 行 (id, 段階, 優先度) == 決定的順序 (順序・捏造封鎖)" "$exp_trace" "$act_trace"
# trace 行の trc-id リンク先 == #rm-<id> (自 doc 内 anchor 健全性)。
trcid_href_bad="$(perl -CSD -0777 -ne 'my @b; while (/<td class="trc-id"><a href="#rm-([^"]*)">([^<]*)<\/a>/g){ push @b,"$1\x{2260}$2" if $1 ne $2; } print join(" ",@b);' "$BODY")"
chk_empty "trace trc-id リンク == #rm-<id> (可視 id == anchor)" "$trcid_href_bad"
# trace 内の照会 code (trc-code) を row スコープで抽出し (id → refs code 集合) を contract と card-keyed 突合。
exp_trace_ref="$(q "$ITEMS_EXPR | .[] | .id as \$id | ((.refs.vision // [] | .[]), (.refs.srs // [] | .[])) | [\$id, .] | @tsv" | grep . \
  | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_trace_ref="$(perl -CSD -0777 -ne '
  while (/<tr data-component="trace-row">(.*?)<\/tr>/gs){ my $row=$1; my ($id)=$row=~/trc-id"><a href="#rm-([^"]*)"/;
    while ($row=~/<a class="trc-code[^"]*"[^>]*>([^<]*)<\/a>/g){ print "$id\t$1\n"; } }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "trace 照会 code (id, ref) == contract (row-keyed)" "$exp_trace_ref" "$act_trace_ref"
# trace href (trc-code) の飛び先 == contract 派生 (VISION=#<F> / SRS=#<FR>)。可視 code == href anchor。
trace_href_bad="$(VIS="$VISION_HTML_E" SRS="$SRS_HTML_E" perl -CSD -Mutf8 -0777 -ne '
  my $v=$ENV{VIS}; utf8::decode($v); my $s=$ENV{SRS}; utf8::decode($s); my @bad;
  while (/<a class="trc-code (trc-dir|trc-req)" href="([^"]*)">([^<]*)<\/a>/g){ my ($k,$h,$c)=($1,$2,$3);
    my $exp = $k eq "trc-dir" ? "$v#$c" : "$s#$c"; push @bad,"$c:$h" if $h ne $exp; }
  print join(" ",@bad);' "$BODY")"
chk_empty "trace href == contract 派生 (VISION=#<F> / SRS=#<FR>・可視 code と整合)" "$trace_href_bad"

# ============ 12. ★静的テンプレ chrome ラベルの固定値 pin (visible-text-vs-attribute の "other" 型) ============
# (a) band 見出し (h2・pack 固定 4 本・順序)。 assembler drift / 見出し捏造を封鎖。
exp_h2="$(printf '%s\n%s\n%s\n%s' 'いちばん近い段階で何を目指すか' '近い段階から順に、 何をどの優先度で目指すか' 'どの目標が、 どの機能方向 (VISION) / どの要件 (SRS) に向かうか' '本文に出てくる専門語のやさしい説明')"
act_h2="$(perl -CSD -0777 -ne 'while (/<h2>([^<]*)<\/h2>/g){ print "$1\n"; }' "$BODY" | perl -pe 'chomp if eof')"
set_eq "band h2 見出し 4 本 == pack 固定 (順序・捏造封鎖)" "$exp_h2" "$act_h2"
# (b) rm-ref-k ラベル (方向/要件) は行 role に束縛 (dir→方向 / req→要件・swap 封鎖) + 件数。
rmrefk_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<div class="rm-ref-row (dir|req)"><span class="rm-ref-k">([^<]*)<\/span>/g){ my ($r,$l)=($1,$2); my $e=$r eq "dir"?"方向":"要件"; push @b,"$r:$l" if $l ne $e; } print join(" ",@b);' "$BODY")"
chk_empty "rm-ref-k 行 role 束縛 (dir→方向/req→要件・swap封鎖)" "$rmrefk_bad"
# rm-ref-row dir 数 == vision を持つ item 数 / req 数 == srs を持つ item 数。
chk "rm-ref-row.dir 数 == vision を持つ item 数" "$(q "$ITEMS_EXPR | [.[] | select(((.refs.vision // []) | length) > 0)] | length")" "$(grep -c '<div class="rm-ref-row dir">' "$BODY")"
chk "rm-ref-row.req 数 == srs を持つ item 数"    "$(q "$ITEMS_EXPR | [.[] | select(((.refs.srs // []) | length) > 0)] | length")" "$(grep -c '<div class="rm-ref-row req">' "$BODY")"
# (c) rm-prio-label 総数 == 全 stage の present priority 数 + 各 label ⊆ canonical。
n_priogroups="$(printf '%s\n' "${ORDER[@]}" | cut -f1,2 | sort -u | wc -l | tr -d ' ')"
chk "rm-prio-label 総数 == present priority グループ数" "$n_priogroups" "$(grep -c '<span class="rm-prio-label">' "$BODY")"
priolabel_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<span class="rm-prio-label">([^<]*)<\/span>/g){ my $l=$1; push @b,$l unless $l eq "必須"||$l eq "推奨"||$l eq "任意"; } print join(" ",@b);' "$BODY")"
chk_empty "rm-prio-label ⊆ {必須,推奨,任意} (未知 priority label 封鎖)" "$priolabel_bad"
# (d) trace thead 列ヘッダ 4 本 (順序固定) + <th> 総数 == 4 (case/attr-robust・列追加封鎖)。
exp_th="$(printf '目標\n段階\n優先度\n参照先 (方向 / 要件)')"
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
vis_id_e="$(esc "$(q '.cross_doc.vision_doc_id')")"; srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
chip_bad="$(VIS="$vis_id_e" SRS="$srs_id_e" perl -CSD -Mutf8 -0777 -ne '
  my $vis=$ENV{VIS}; utf8::decode($vis); my $srs=$ENV{SRS}; utf8::decode($srs); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"chip:".scalar(@bs)."B"; next}
    push @bad,"chip:b1\x{2260}$bs[0]" if $bs[0] ne $vis;
    push @bad,"chip:b2\x{2260}$bs[1]" if $bs[1] ne $srs;
    my $vist=$in; $vist=~s/<[^>]+>//g; push @bad,"chip:VIS" if $vist ne " 照会先: ${vis}の機能方向 / ${srs}の要件";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: ref-chip 可視 echo == テンプレ+doc_id (swap/平文/nested 封鎖)" "$chip_bad"

# ============ 14. core 共通 chrome + cover-meta KV ============
verify_core_chrome
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
kv_v() { printf '%s\n' "$meta_kv" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }
chk "cover-meta 種別"   "roadmap (ロードマップ)" "$(kv_v 種別)"
chk "cover-meta 収録"   "$(esc "${NSTAGE} 段階 ($(sid_of "${OS[0]}")–$(sid_of "${OS[-1]}"))")" "$(kv_v 収録)"
chk "cover-meta 期間"   "$(esc "$(q "$(sel_of "${OS[0]}") | .target") – $(q "$(sel_of "${OS[-1]}") | .target")")" "$(kv_v 期間)"
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

# ============ 17. plain-language-term-inline fidelity + 用語被覆 (assemble-roadmap と同一語境界規律) ============
verify_term_inline \
  "[.stages[].outcome, (.stages[].items | .[][] | .text)] | .[]" \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
# ---- gate F: render 健全性 (visual) 非 mermaid pack 展開。 ----
render_gate_f "$HTML" "ROADMAP_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + seq 順序 + cross-doc 照会解決 + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
