#!/usr/bin/env bash
# folio engine post-B6 (folio-wdv0) — risk-register-pack fabrication-free + severity 決定的導出 + cross-doc 照会 proof
#
# 生成 risk-register HTML の *構造* が入力 risk contract から完全に導出されたことを機械検証する floor gate。
# verify-testcases.sh (test-cases-pack) と同型の規律を risk-register-pack schema へ適用し、 加えて
# ★severity 決定的導出の再突合 (本 pack の核) を課す:
#   - 件数 (risk-card / rtm-row / prose スロット / severity-matrix 9 セル / tally 3 band) が contract 導出値と一致。
#   - id 一意性 (risks)。
#   - ★severity 決定的導出 fabrication-free (本 pack の核): severity は contract に無く likelihood×impact から
#       導出されるため、 (a) 各 card の rk-sev バッジ (ラベル/class/data-sev-cell) が contract の likelihood/impact
#       から再導出した値と *card-keyed で一致*、 (b) severity-matrix の 9 セル (件数/sevclass/レベルラベル/data-cell) が
#       再導出値と一致、 (c) tally 3 band の件数が再導出値と一致、 で「深刻度の捏造・改竄」を封鎖する。
#   - ★card は severity 高い順 (積 desc・id asc の安定 sort) で emit される。 emission 順を再導出値と *順序付き* で pin。
#   - ★cross-doc 前方照会: risks[].trace.refs[] の FR/NFR 集合が (a) HTML の data-trace-ref 集合と集合一致 +
#       count anchor、 (b) 参照先 SRS contract の 要件/非機能要件 ID に実在 (dangling 0)、
#       (c) srs_doc_id == SRS .meta.doc_id、 (d) data-trace-role が allowlist 内、 (d') (ref,role) ペア集合が一致。
#       共通スケルトンは core (verify_cross_doc_refs)。
#   - ★cross-doc 可視 echo 厳密一致 (表紙 ref-chip / 各 card の trace 見出し・照会先 / rk-ref 可視==attr)。
#   - ★RTM within-doc fidelity + per-card trace pin (card 間 relocation 封鎖) + FR/NFR ラベル併記 fidelity。
#   - ★per-table 構造完全性 (severity-matrix / risk-rtm の tr/td/th/tfoot/caption) = phantom 行/セル/別 table 注入封鎖。
#   - core 共通 chrome (cover-head/approval/glossary)・escape 健全性・prose スロット mode・term-inline。
#
# usage: verify-risk.sh [--filled <manifest.yaml> | --artifact] <risk-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate)。 本 floor が担うのは *構造アンカー + 決定的フィールド値 (severity 導出含む)*
#   の contract 突合。 plain 要約 (cover-summary / chapter-lead / plain-RSKx prose スロット) の *内容真正性* は
#   floor の対象外 = ceiling (fidelity-risk = 機械 SSoT 突合 + persona-walk)。 floor 単独で GREEN にならず CEILING=PENDING。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-risk.sh [--filled <manifest> | --artifact] <risk-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-risk.sh [--filled <manifest> | --artifact] <risk-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-risk: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-risk: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-risk: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-risk: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-risk: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-risk: failed to source verify-common.sh" >&2; exit 2; }
fail=0

# ---- severity 決定的導出 (assemble-risk.sh と *同一* ロジック。 verify 側で再導出して HTML と突合) ----
declare -A LNUM=( [L]=1 [M]=2 [H]=3 )
declare -A LVL_LABEL=( [L]=低 [M]=中 [H]=高 )
declare -A STATUS_LABEL=( [open]=未対応 [mitigating]=対応中 [accepted]=受容 [closed]=対応済 )
sev_prod()  { printf '%s' "$(( LNUM[$1] * LNUM[$2] ))"; }
sev_label() { local p="$1"; if ((p<=2)); then printf '低'; elif ((p<=4)); then printf '中'; else printf '高'; fi; }
sev_class() { local p="$1"; if ((p<=2)); then printf 'low'; elif ((p<=4)); then printf 'medium'; else printf 'high'; fi; }
# ★severity 順 risk id 列 (assemble-risk.sh sorted_rids と同一導出: 積 desc・id asc の安定 sort)。
sorted_rids() {
  q '.risks[] | [.id, .likelihood, .impact] | @tsv' | while IFS=$'\t' read -r id lk im; do
    [[ -n "$id" ]] || continue
    printf '%s\t%s\n' "$(sev_prod "$lk" "$im")" "$id"
  done | sort -t$'\t' -k1,1nr -k2,2 | cut -f2
}

make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23)。
verify_repro_build risk "$FILLED_MANIFEST"

NRK="$(q '.risks | length')"
NEDGE="$(q '[.risks[].trace.refs[]] | length')"
# ★class-token / data-component 機械的網羅 (novel-marker 注入一網打尽・testcases folio-bur r6 idiom 移植)。
RK_CLS="accepted chapbody closed cover-eyebrow cover-meta cover-sub doc-type en foot ft-grid ft-plain gdef grow gword high ic ico k kicker lab lead low m medium mitigating num open page reader-chip rk-grid rk-head rk-id rk-im rk-level rk-levels rk-lk rk-mit rk-mit-k rk-mit-v rk-owner rk-owner-k rk-owner-v rk-plain rk-ref rk-ref-label rk-sev rk-statement rk-status rk-title rk-trace rk-trace-edge rk-trace-h rk-trace-row rk-trace-tgt role rrtm-code rrtm-edge rrtm-id rrtm-label rrtm-refs rrtm-sev rrtm-status self sign sm-cell sm-col sm-corner sm-lv sm-n sm-row sm-tally stamp summary-card tags term tint-bad tint-brand tint-ok tint-violet txt v when who"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RK_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker 注入封鎖)" "$unknown_cls"
RK_DC="approval-block chapter-deck-band cross-doc-ref-chip doc-cover-band fidelity-sync-meta glossary-term-table plain-language-term-inline requirement-type-color-tokens risk-card risk-rtm rtm-row severity-matrix severity-tally"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RK_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel dc 注入封鎖)" "$unknown_dc"
echo "risk-register-pack fabrication-free + severity 決定的導出 + cross-doc 照会 proof: $HTML"
echo "  contract: $CONTRACT  ($NRK リスク / $NEDGE trace edge)"

# 1. 件数
chk "risk-card 数 == |risks|"        "$NRK" "$(grep -c 'data-component="risk-card"' "$BODY")"
chk "rtm-row 数 == |risks|"          "$NRK" "$(grep -c 'data-component="rtm-row"' "$BODY")"
chk "severity-matrix 部品 == 1"      "1"    "$(grep -c 'data-component="severity-matrix"' "$BODY")"
chk "severity-tally 部品 == 1"       "1"    "$(grep -c 'data-component="severity-tally"' "$BODY")"
chk "risk-rtm 部品 == 1"             "1"    "$(grep -c 'data-component="risk-rtm"' "$BODY")"
chk "sm-cell 数 == 9 (3×3 マトリクス)" "9"   "$(count_attr_token class sm-cell < "$BODY")"
chk "sm-tally 数 == 3 (高/中/低 band)"  "3"   "$(count_attr_token class sm-tally < "$BODY")"

# 2. id 一意性
chk_empty "risks id 一意" "$(q '.risks[].id' | sort | uniq -d | tr '\n' ' ')"

# ============================================================================
# 3. ★★severity 決定的導出 fabrication-free (本 pack の核)
# ============================================================================
# 3a. severity-matrix 9 セル: (data-cell, 件数, sevclass, レベルラベル) を contract から *再導出* して集合一致。
#     セル件数 = そのマス (likelihood=行 / impact=列) の risk 数、 sevclass/レベル = likelihood×impact の決定的導出。
exp_matrix="$(for lk in H M L; do for im in L M H; do
    p="$(sev_prod "$lk" "$im")"
    cnt="$(q '[.risks[] | select(.likelihood=="'"$lk"'" and .impact=="'"$im"'")] | length')"
    printf '%s\t%s\t%s\t%s\n' "${lk}${im}" "$cnt" "$(sev_class "$p")" "$(sev_label "$p")"
  done; done | LC_ALL=C sort)"
act_matrix="$(perl -CSD -0777 -ne 'while (/<td class="sm-cell ([a-z]+)" data-cell="([A-Z]+)"><b class="sm-n">([0-9]+)<\/b><span class="sm-lv">([^<]*)<\/span><\/td>/g){ print "$2\t$3\t$1\t$4\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "severity-matrix 9 セル (cell,件数,sevclass,ラベル) == 決定的導出" "$exp_matrix" "$act_matrix"
# 3a'. data-cell 集合が固定 9 マス (捏造セル・欠落封鎖) + sevclass↔レベルラベル 整合 (band 定義の改竄封鎖)。
chk "sm-cell data-cell 集合 == 9 固定マス" "HH HL HM LH LL LM MH ML MM" \
  "$(perl -CSD -0777 -ne 'while (/data-cell="([A-Z]+)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ *$//')"
smcell_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<td class="sm-cell (high|medium|low)" data-cell="[A-Z]+"><b class="sm-n">[0-9]+<\/b><span class="sm-lv">([^<]*)<\/span>/g){ my ($c,$l)=($1,$2); my $exp = $c eq "high" ? "高" : ($c eq "medium" ? "中" : "低"); push @b,"$c:$l" if $l ne $exp; } print join(" ",@b);' "$BODY")"
chk_empty "sm-cell sevclass↔レベルラベル 整合 (high→高/medium→中/low→低)" "$smcell_bad"
# 3b. tally 3 band: (data-band, 件数) を contract から再導出して突合 + band↔ラベル整合。
exp_tally="$( { declare -A B=([high]=0 [medium]=0 [low]=0)
    while IFS=$'\t' read -r lk im; do [[ -n "$lk" ]] || continue; c="$(sev_class "$(sev_prod "$lk" "$im")")"; B[$c]=$((B[$c]+1)); done < <(q '.risks[] | [.likelihood, .impact] | @tsv')
    for b in high medium low; do printf '%s\t%s\n' "$b" "${B[$b]}"; done; } | LC_ALL=C sort)"
act_tally="$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="sm-tally (high|medium|low)" data-band="([a-z]+)">深刻度 [^<]*: <b>([0-9]+)<\/b> 件<\/span>/g){ print "$2\t$3\n" if $1 eq $2; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "severity-tally 3 band (band,件数) == 決定的導出" "$exp_tally" "$act_tally"
tally_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @b; while (/<span class="sm-tally (high|medium|low)" data-band="[a-z]+">深刻度 ([^:<]*):/g){ my ($c,$l)=($1,$2); my $exp = $c eq "high" ? "高" : ($c eq "medium" ? "中" : "低"); push @b,"$c:$l" if $l ne $exp; } print join(" ",@b);' "$BODY")"
chk_empty "sm-tally band↔深刻度ラベル 整合" "$tally_bad"
# 3c. ★card severity バッジ (card-keyed): 各 card の rk-sev (ラベル/class/data-sev-cell) が contract の
#     likelihood/impact から再導出した値と一致 (深刻度の捏造・改竄を card 単位で封鎖 = fabrication-free の核)。
exp_cardsev="$(q '.risks[] | [.id, .likelihood, .impact] | @tsv' | while IFS=$'\t' read -r id lk im; do
    [[ -n "$id" ]] || continue; p="$(sev_prod "$lk" "$im")"
    printf '%s\t%s\t%s\t%s\n' "$(esc "$id")" "$(sev_label "$p")" "$(sev_class "$p")" "${lk}${im}"
  done | LC_ALL=C sort)"
act_cardsev="$(perl -CSD -0777 -ne '
  while (/<div data-component="risk-card" id="rsk-([^"]+)">(.*?)(?=<div data-component="risk-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    if ($blk=~/<span class="rk-sev ([a-z]+)" data-sev-cell="([A-Z]+)">([^<]*)<\/span>/){ print "$id\t$3\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "★card severity (id,ラベル,class,cell) == likelihood×impact 決定的導出 (捏造封鎖)" "$exp_cardsev" "$act_cardsev"

# 4. ★card 群の emission 順 == severity 順 (積 desc・id asc)。 順序付き突合で並べ替えの改竄を封鎖。
exp_order="$(sorted_rids)"
act_order="$(grep -oE '<div data-component="risk-card" id="rsk-[^"]+"' "$BODY" | sed -E 's#.*id="rsk-([^"]+)"#\1#')"
set_eq "risk-card emission 順 == severity 順 (積 desc・id asc)" "$exp_order" "$act_order"

# 5. ★cross-doc 前方照会 (core 共通スケルトン)。 refs → SRS FR/NFR (全 role=claim)。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-trace-ref" --role-attr "data-trace-role" \
  --keys-expr '.risks[].trace.refs[]' \
  --count-expr '[.risks[].trace.refs[]] | length' \
  --nonempty-count-expr '[ (.risks[].trace.refs[]) | select((. // "") != "") ] | length' \
  --pair-expr '.risks[].trace.refs[] | [., "claim"] | @tsv' \
  --target-ids-expr '(.requirements[].id, .nfr[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 5b. ★cross-doc 可視 echo の堅牢検証 (各 echo ブロックは固定個数・ブロック削除の fail-open を count anchor で塞ぐ)。
chk "cross-doc: ref-chip ブロック == 1"           "1"    "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "cross-doc: rk-trace-h ブロック == |risks|"    "$NRK" "$(grep -c 'class="rk-trace-h"' "$BODY")"
chk "cross-doc: rk-trace-tgt ブロック == |risks|"  "$NRK" "$(grep -c 'class="rk-trace-tgt"' "$BODY")"
chk "cross-doc: rk-ref span == |edges|"           "$NEDGE" "$(grep -o 'class="rk-ref"' "$BODY" | wc -l | tr -d ' ')"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
# ★cover ref-chip b2 = ref の平易機能名要約 (SRS label を unique ref の first-occurrence 順で join)。 assembler emit_cover と同一導出。
ref_label_join=""
while IFS= read -r _r; do [[ -n "$_r" ]] && ref_label_join+="${ref_label_join:+・}$(R="$_r" yq -r '(.requirements[], .nfr[]) | select(.id==strenv(R)) | .label' "$SRS_ABS")"; done < <(q '[.risks[].trace.refs[]] | unique | .[]')
ref_join_e="$(esc "$ref_label_join")"
srs_title_e="$(esc "SRS: $(yq -r '.meta.title' "$SRS_ABS")")"
# ★可視テキスト厳密一致 (marker-keyed・nested-same-tag reject)。 各 echo の全タグ除去後の可視テキストが固定テンプレ+id と完全一致。
rk_echo_bad="$(SRS="$srs_id_e" RJ="$ref_join_e" TITLE="$srs_title_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my $rj=$ENV{RJ}; utf8::decode($rj); my $title=$ENV{TITLE}; utf8::decode($title);
  my @bad;
  # (h) 表紙 cross-doc-ref-chip: <b> ちょうど 2 本 (b1=srs_doc_id / b2=unique ref label join)・可視テキスト厳密一致
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"ref-chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"ref-chip:".scalar(@bs)."B"; next}
    push @bad,"ref-chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    push @bad,"ref-chip:b2\x{2260}$bs[1]" if $bs[1] ne $rj;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " 見張る対象: $srs の要件 $rj";
  }
  # (i) rk-trace-h (各 card・<b> 無し平文): 可視テキスト全体が固定テンプレ (照会先 srs_doc_id を可視補間)
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="rk-trace-h"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"rk-trace-h:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"rk-trace-h:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"rk-trace-h:VIS" if $vis ne "脅かす要件 (cross-doc 照会 \x{2192} $srs)";
  }
  # (j) rk-trace-tgt (各 card・<b> 無し平文): 照会先 footnote
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="rk-trace-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"rk-trace-tgt:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"rk-trace-tgt:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"rk-trace-tgt:VIS" if $vis ne "照会先: $srs \x{2014} $title";
  }
  # (k) rk-ref 可視 == data-trace-ref attr (可視 ref だけ改竄し attr 温存を封鎖)
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="rk-ref"[^>]*\bdata-trace-ref="([^"]*)"[^>]*>([^<]*)<\/\1>/gs) {
    my ($attr,$vis)=($2,$3); push @bad,"rk-ref:$attr\x{2260}$vis" if $vis ne $attr;
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: 可視 echo == テンプレ+id (marker-keyed・swap/平文/nested 封鎖)" "$rk_echo_bad"

# 5c. ★cross-doc deep-link 遷移先 fidelity。 rk-ref / rrtm-code の href が contract 派生 <srs_html>#<ref> へ束縛。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
chk "href: <a class=rk-ref href> 数 == |edges| (span 残存/href 欠落封鎖)" "$NEDGE" "$(grep -oE '<a class="rk-ref" href=' "$BODY" | wc -l | tr -d ' ')"
exp_rkref_href="$(q '.risks[].trace.refs[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_rkref_href="$(perl -CSD -0777 -ne 'while (/<a class="rk-ref" href="([^"]*)"\s+data-trace-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: rk-ref (href, ref) == <srs_html>#<ref> (anchor/filename swap 封鎖)" "$exp_rkref_href" "$act_rkref_href"
chk "href: <a class=rrtm-code href> 数 == |edges| (RTM href 欠落封鎖)" "$NEDGE" "$(grep -oE '<a class="rrtm-code" href=' "$BODY" | wc -l | tr -d ' ')"
rrtmcode_href_bad="$(SRS="$SRS_HTML_E" perl -CSD -Mutf8 -0777 -ne 'my $s=$ENV{SRS}; utf8::decode($s); my @bad; while (/<a class="rrtm-code" href="([^"]*)">([^<]*)<\/a>/g){ push @bad,"$1\x{2260}$2" if $1 ne "$s#$2"; } print join(" ",@bad);' "$BODY")"
chk_empty "href: rrtm-code href == <srs_html>#<code> (可視コード==飛び先 anchor)" "$rrtmcode_href_bad"

# 6. ★RTM within-doc fidelity: (rid, sev-label, status-label, ref-codes) を *emission 順* (severity 順) で pin。
exp_rtm="$(sorted_rids | while IFS= read -r rid; do
    [[ -n "$rid" ]] || continue
    lk="$(q '.risks[] | select(.id=="'"$rid"'") | .likelihood')"; im="$(q '.risks[] | select(.id=="'"$rid"'") | .impact')"
    st="$(q '.risks[] | select(.id=="'"$rid"'") | .status')"
    refs="$(q '.risks[] | select(.id=="'"$rid"'") | .trace.refs | join("・")')"
    printf '%s\t%s\t%s\t%s\n' "$(esc "$rid")" "$(sev_label "$(sev_prod "$lk" "$im")")" "$(esc "${STATUS_LABEL[$st]}")" "$(esc "$refs")"
  done)"
act_rtm="$(perl -CSD -0777 -ne '
  while (/<tr[^>]*\bdata-component="rtm-row"[^>]*>(.*?)<\/tr>/gs) {
    my $row=$1;
    my ($rid)  = $row =~ /<td class="rrtm-id">([^<]*)<\/td>/;
    my ($sev)  = $row =~ /<td class="rrtm-sev"><span class="rk-sev [a-z]+">([^<]*)<\/span><\/td>/;
    my ($stat) = $row =~ /<td class="rrtm-status">([^<]*)<\/td>/;
    my ($rfc)  = $row =~ /<td class="rrtm-refs">(.*?)<\/td>/s;
    my @rf = (defined $rfc) ? ($rfc =~ /<a class="rrtm-code"[^>]*>([^<]*)<\/a>/g) : ();
    print join("\t", ($rid//""), ($sev//""), ($stat//""), join("\x{30FB}",@rf)), "\n";
  }' "$BODY")"
set_eq "RTM 行 (rid,深刻度,状態,ref-codes) == contract (severity 順)" "$exp_rtm" "$act_rtm"

# 6b. ★per-card trace pin (card-keyed cross-doc edge fidelity)。 card 間で FR/NFR を入替える改竄 (global set 不変) を封鎖。
exp_cardtrace="$(q '.risks[] | .id as $id | (.trace.refs[] | [$id, ., "claim"]) | @tsv' \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardtrace="$(perl -CSD -0777 -ne '
  while (/<div data-component="risk-card" id="rsk-([^"]+)">(.*?)(?=<div data-component="risk-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/\bdata-trace-ref="([^"]*)"\s+data-trace-role="([^"]*)"/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
set_eq "per-card trace 三つ組 (rid, ref, role) == contract (card-keyed)" "$exp_cardtrace" "$act_cardtrace"

# 6c. ★FR/NFR 平易ラベル併記の fidelity。 card rk-ref-label + RTM rrtm-label = 2×|edges|・(ref,可視ラベル) が SRS 由来。
chk "rk-ref-label 数 == |edges| (card 各 trace edge にラベル)" "$NEDGE" "$(grep -o 'class="rk-ref-label"' "$BODY" | wc -l | tr -d ' ')"
chk "rrtm-label 数 == |edges| (RTM 各 ref にラベル)"          "$NEDGE" "$(grep -o 'class="rrtm-label"' "$BODY" | wc -l | tr -d ' ')"
chk "data-label-ref 総数 == 2×|edges| (card + RTM)"          "$((NEDGE*2))" "$(grep -o 'data-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_labels="$(q '[.risks[].trace.refs[]] | unique | .[]' | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(R="$_r" yq -r '(.requirements[], .nfr[]) | select(.id==strenv(R)) | .label' "$SRS_ABS")")"; done | LC_ALL=C sort -u)"
act_labels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "併記ラベル (ref, label) == SRS 由来 (FR/NFR=label)" "$exp_labels" "$act_labels"
# 6c'. ★card-keyed (ref,label): card 内の rk-ref-label が *その card の ref* の SRS ラベルと一致 (FR↔機能名 誤対応封鎖)。
exp_cardlabel="$(q '.risks[] | .id as $id | (.trace.refs[] | [$id, .]) | @tsv' \
  | while IFS=$'\t' read -r _id _r; do _lab="$(R="$_r" yq -r '(.requirements[], .nfr[]) | select(.id==strenv(R)) | .label' "$SRS_ABS")"; printf '%s\t%s\t%s\n' "$(esc "$_id")" "$(esc "$_r")" "$(esc "$_lab")"; done | LC_ALL=C sort)"
act_cardlabel="$(perl -CSD -0777 -ne '
  while (/<div data-component="risk-card" id="rsk-([^"]+)">(.*?)(?=<div data-component="risk-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/<span class="rk-ref-label" data-label-ref="([^"]*)">([^<]*)<\/span>/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card (ref, label) == SRS 由来 (card-keyed・ref↔機能名 誤対応封鎖)" "$exp_cardlabel" "$act_cardlabel"

# 7. ★各 card の可視テキスト fidelity (card-keyed・relocation 封鎖 + 捏造封鎖)。
# 7a. id / title / owner / status / levels を card-keyed で contract 突合 (term-inline なし・[^<]*)。
exp_cardvis="$(q '.risks[] | [.id, .title, .owner, .status, .likelihood, .impact] | @tsv' \
  | while IFS=$'\t' read -r id ti ow st lk im; do
      printf '%s\tid\t%s\n%s\ttitle\t%s\n%s\towner\t%s\n%s\tstatus\t%s\n%s\tlk\t%s\n%s\tim\t%s\n' \
        "$(esc "$id")" "$(esc "$id")" "$(esc "$id")" "$(esc "$ti")" "$(esc "$id")" "$(esc "$ow")" \
        "$(esc "$id")" "$(esc "${STATUS_LABEL[$st]}")" "$(esc "$id")" "$(esc "${LVL_LABEL[$lk]}")" "$(esc "$id")" "$(esc "${LVL_LABEL[$im]}")"
    done | LC_ALL=C sort)"
act_cardvis="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<div data-component="risk-card" id="rsk-([^"]+)">(.*?)(?=<div data-component="risk-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    if ($blk=~/<span class="rk-id">([^<]*)<\/span>/){ print "$id\tid\t$1\n"; }
    if ($blk=~/<h3 class="rk-title">([^<]*)<\/h3>/){ print "$id\ttitle\t$1\n"; }
    if ($blk=~/<span class="rk-owner-v">([^<]*)<\/span>/){ print "$id\towner\t$1\n"; }
    if ($blk=~/<span class="rk-status [a-z]*">([^<]*)<\/span>/){ print "$id\tstatus\t$1\n"; }
    if ($blk=~/<span class="rk-level rk-lk">起こりやすさ <b>([^<]*)<\/b><\/span>/){ print "$id\tlk\t$1\n"; }
    if ($blk=~/<span class="rk-level rk-im">影響の大きさ <b>([^<]*)<\/b><\/span>/){ print "$id\tim\t$1\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "card 可視 (id/title/owner/status/起こりやすさ/影響) == contract (card-keyed)" "$exp_cardvis" "$act_cardvis"
# 7b. status class (emission 順) + (class, 可視ラベル) 整合 (open→未対応/mitigating→対応中/accepted→受容/closed→対応済)。
exp_stcls="$(printf 'accepted\t受容\nclosed\t対応済\nmitigating\t対応中\nopen\t未対応\n' | LC_ALL=C sort)"
act_stcls="$(grep -oE '<span class="rk-status [a-z]+">[^<]*</span>' "$BODY" | sed -E 's#<span class="rk-status ([a-z]+)">([^<]*)</span>#\1\t\2#' | LC_ALL=C sort -u)"
chk_empty "rk-status class↔可視ラベル 整合" "$(LC_ALL=C comm -13 <(printf '%s\n' "$exp_stcls") <(printf '%s\n' "$act_stcls") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
# 7c. statement (地の文・term-inline バッジ除去) を card-keyed で contract 突合 (捏造・relocation 封鎖)。
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
exp_cardtext="$(q '.risks[] | .id as $id | ([$id, "stmt", .statement], [$id, "mit", .mitigation]) | @tsv' \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardtext="$(perl -CSD -Mutf8 -0777 -ne '
  while (/<div data-component="risk-card" id="rsk-([^"]+)">(.*?)(?=<div data-component="risk-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    if ($blk=~/<p class="rk-statement">(.*?)<\/p>/s){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$id\tstmt\t$t\n"; }
    if ($blk=~/<span class="rk-mit-v">(.*?)<\/span><\/div>/s){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$id\tmit\t$t\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "card 可視 statement/mitigation == contract (card-keyed・term-inline 除去・捏造/relocation 封鎖)" "$exp_cardtext" "$act_cardtext"

# 8. ★静的テンプレ chrome ラベルの固定値 pin (visible-text-vs-attribute "other" 型)。
# 8a. severity-matrix thead 列ヘッダ 4 本 (順序固定)。
exp_smth="$(printf '起こりやすさ \\ 影響\n影響 低\n影響 中\n影響 高')"
act_smth="$(perl -CSD -0777 -ne 'if (/<table data-component="severity-matrix"><thead><tr>(.*?)<\/tr>/s){ my $r=$1; while ($r=~/<th[^>]*>(.*?)<\/th>/gs){ print "$1\n"; } }' "$BODY")"
chk "severity-matrix thead 列ヘッダ 4 本 == 固定 (順序)" "$exp_smth" "$act_smth"
# 8b. severity-matrix 行ヘッダ (sm-row) 3 本 == 起こりやすさ 高/中/低 (順序固定)。
exp_smrow="$(printf '起こりやすさ 高\n起こりやすさ 中\n起こりやすさ 低')"
act_smrow="$(perl -CSD -0777 -ne 'while (/<th class="sm-row">([^<]*)<\/th>/g){ print "$1\n"; }' "$BODY")"
chk "severity-matrix 行ヘッダ 3 本 == 起こりやすさ 高/中/低 (順序)" "$exp_smrow" "$act_smrow"
# 8c. RTM thead 列ヘッダ 4 本 (順序固定)。
exp_rtmth="$(printf 'リスク\n深刻度\n状態\n脅かす要件')"
act_rtmth="$(perl -CSD -0777 -ne 'if (/<table data-component="risk-rtm"><thead><tr>(.*?)<\/tr>/s){ my $r=$1; while ($r=~/<th[^>]*>(.*?)<\/th>/gs){ print "$1\n"; } }' "$BODY")"
chk "risk-rtm thead 列ヘッダ 4 本 == 固定 (順序)" "$exp_rtmth" "$act_rtmth"
# 8d. card の固定ラベル (対策 / 担当 / 起こりやすさ / 影響の大きさ) 件数 == |risks| (捏造で件数割れ)。
chk "rk-mit-k '対策' == |risks|"             "$NRK" "$(grep -c '<span class="rk-mit-k">対策</span>' "$BODY")"
chk "rk-owner-k '担当' == |risks|"           "$NRK" "$(grep -c '<span class="rk-owner-k">担当</span>' "$BODY")"
chk "rk-level '起こりやすさ' == |risks|"      "$NRK" "$(grep -c '<span class="rk-level rk-lk">起こりやすさ ' "$BODY")"
chk "rk-level '影響の大きさ' == |risks|"      "$NRK" "$(grep -c '<span class="rk-level rk-im">影響の大きさ ' "$BODY")"

# 9. ★per-table 構造完全性 (phantom 行/セル/別 table/tfoot/caption 注入封鎖・case/attr-robust)。
# 9a. table 総数 == 2 (severity-matrix + risk-rtm のみ)。
chk "table 総数 == 2 (別 table 注入封鎖)" "2" "$(grep -oiE '<table\b' "$BODY" | wc -l | tr -d ' ')"
chk "tfoot 総数 == 0 (偽承認 tfoot 封鎖)" "0" "$(grep -oiE '<tfoot\b' "$BODY" | wc -l | tr -d ' ')"
chk "caption 総数 == 0 (偽承認 caption 封鎖)" "0" "$(grep -oiE '<caption\b' "$BODY" | wc -l | tr -d ' ')"
# 9b. severity-matrix 内: tr==4 (thead1+tbody3) / th==7 (thead4+行頭3) / td==9 / tfoot==0 / caption==0。
sm_counts="$(perl -CSD -0777 -ne 'if (/<table data-component="severity-matrix">.*?<\/table>/s){ my $t=$&; my $tr=()=$t=~/<tr\b/gi; my $th=()=$t=~/<th\b/gi; my $td=()=$t=~/<td\b/gi; my $tf=()=$t=~/<tfoot\b/gi; my $cp=()=$t=~/<caption\b/gi; print "$tr $th $td $tf $cp"; }' "$BODY")"
chk "severity-matrix (tr,th,td,tfoot,caption) == (4,7,9,0,0)" "4 7 9 0 0" "$sm_counts"
# 9c. risk-rtm 内: tr==1+NRK / th==4 / td==4×NRK / tfoot==0 / caption==0。
rtm_counts="$(perl -CSD -0777 -ne 'if (/<table data-component="risk-rtm">.*?<\/table>/s){ my $t=$&; my $tr=()=$t=~/<tr\b/gi; my $th=()=$t=~/<th\b/gi; my $td=()=$t=~/<td\b/gi; my $tf=()=$t=~/<tfoot\b/gi; my $cp=()=$t=~/<caption\b/gi; print "$tr $th $td $tf $cp"; }' "$BODY")"
chk "risk-rtm (tr,th,td,tfoot,caption) == (1+NRK,4,4×NRK,0,0)" "$((NRK+1)) 4 $((NRK*4)) 0 0" "$rtm_counts"

# 10. cover-meta KV (種別/件数/検証対象/版) の決定的再導出突合。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別 == risk-register ラベル" "risk-register (リスク登録簿)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 件数 == |risks|+範囲"        "$(esc "${NRK}件 ($(q '.risks[0].id')–$(q '.risks[-1].id'))")" "$(printf '%s\n' "$meta_kv" | grep -F '件数' | head -1 | cut -f2)"
chk "cover-meta 検証対象 == srs_doc_id"      "$srs_id_e" "$(printf '%s\n' "$meta_kv" | grep -F '検証対象' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"            "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"               "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"
chk "cover-meta k 占有 == 4 (quote-robust)"  "4" "$(count_attr_token class k < "$BODY")"
chk "cover-meta v 占有 == 4 (quote-robust)"  "4" "$(count_attr_token class v < "$BODY")"

# 11. core 共通 chrome (cover-head/approval/glossary の値突合 + footer provenance)。
verify_core_chrome

# 12. escape 健全性
chk "化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"          "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 13. prose スロット mode (pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)
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

# 14. plain-language-term-inline fidelity + 用語被覆 (assemble-risk と同一語境界規律)。
verify_term_inline \
  '.risks[].statement, .risks[].mitigation' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
# ---- gate F: render 健全性 (visual)。 非 mermaid pack の生成 HTML を light/dark × 3 viewport で render-gate。 ----
render_gate_f "$HTML" "RISK_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  # mode 別詳細 (旧 reason 語 artifact/filled/fabrication-free を substring 保全)。
  if [[ -n "$ARTIFACT" ]]; then mode_detail="mode=artifact: 構造 fabrication-free + severity 決定的導出 + cross-doc 照会解決 + prose 全充填"
  elif [[ -n "$FILLED_MANIFEST" ]]; then mode_detail="mode=filled: 構造 contract 完全導出・捏造 0 + severity 導出 + cross-doc 照会解決 + prose 注入忠実"
  else mode_detail="mode=fabrication-free: 構造 contract 完全導出・捏造 0 + severity 導出 + cross-doc 照会解決 + prose 空"; fi
  # ceiling-precheck sentinel を verify-adr.sh:398 同型で統一 emit (folio-vxpc)。 詳細は verify-research.sh の同節参照。
  echo "RESULT: floor PASS ($mode_detail) — ただし CEILING=PENDING (*GREEN ではない*)"
  if [[ "${RISK_SKIP_RENDER:-0}" == "1" || "${SKIP_RENDER:-0}" == "1" ]]; then
    echo "  ※ render gate 未完 (F=見た目崩れ が未実行: RISK_SKIP_RENDER/SKIP_RENDER) — CI/uv 環境で render を回すまで floor は不完全。"
  fi
  echo "  ceiling = persona-walk-risk + fidelity-risk (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に blocking arm (構造/severity 導出/cross-doc 照会/prose/gate F) が不合格"
  exit 1
fi
