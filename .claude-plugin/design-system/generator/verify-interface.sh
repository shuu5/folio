#!/usr/bin/env bash
# folio engine post-B6 (folio-ehar / c5r Tier C) — interface-pack fabrication-free + 固定章 + 照会 graph + id anchor proof (instance#2)
#
# 生成 interface HTML の *構造* が入力 contract から完全に導出されたことを機械検証する floor gate (hybrid・operation catalog + error contract)。
# verify-datamodel.sh (hybrid) と同型の規律を interface schema へ適用。 mermaid 図は無い (境界図は arch の領分)。
#
# ★floor 三本柱:
#   ① 照会グラフ整合: operations/errors/external/cross_cutting[].refs.srs[] の cross-doc 照会が (a) HTML data-if-ref 集合と集合一致 +
#      count anchor、 (b) 参照先 SRS contract に実在 (dangling 0)、 (c) doc_id 一致、 (d)(d') role 整合、
#      (e) href 遷移先 = FR/NFR は <srs_html>#<ref> (deep-link) / CON/AC は <srs_html> (文書単位)。 共通スケルトン = core (verify_cross_doc_refs)。
#      graph 終端完備は verify-graph.sh が別途 (自前 inline principle 終端)。 datamodel entity 参照 (uses.entities) は presentational (pack 固有検査)。
#   ② navigable id アンカー: operation→op-/error→error-/external→ext-/cross_cutting→cc-/principle→principle- の id= 集合が contract と集合一致。
#   ③ 固定章 + 必須要素 (census-count): 6 章 (chapter-deck-band) + operation-card 5/error-card 4/external-row 2/cross-cutting-card 2/
#      op-error-chip Σ|op.errors|/ent-chip Σ|uses.entities|/srs-badge Σ|refs.srs| が contract と一致。
#
# ★fab-free: 可視テキスト fidelity (emission 順 pin)・cross-doc 可視 echo 厳密一致・band 数詞 fidelity・binding null 予約。
# ★floor PASS でも GREEN にせず CEILING=PENDING・exit 0 (floor 単独 GREEN 禁止・two-gate)。
#
# usage: verify-interface.sh [--filled <manifest.yaml> | --artifact] <interface-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-interface.sh [--filled <manifest> | --artifact] <interface-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-interface.sh [--filled <manifest> | --artifact] <interface-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-interface: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-interface: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-interface: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-interface: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-interface: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=58; source "$LVC" || { echo "verify-interface: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build interface "$FILLED_MANIFEST"

# cross_doc 解決先 (SRS / datamodel contract) + SRS ref 分類集合 (FR/NFR = fragment / CON/AC = 文書単位)。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
DM_REL="$(q '.cross_doc.datamodel_contract')"; DM_ABS="${CONTRACT_DIR}/${DM_REL}"
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
DM_HTML_E="$(esc "$(q '.cross_doc.datamodel_html')")"
declare -A FRAG_SET DOCREF_SET ENT_NAME
if [[ -f "$SRS_ABS" ]]; then
  while IFS= read -r _id; do [[ -n "$_id" && "$_id" != "null" ]] && FRAG_SET[$_id]=1; done < <(yq -r '(.requirements[].id, .nfr[].id)' "$SRS_ABS" 2>/dev/null)
  while IFS= read -r _id; do [[ -n "$_id" && "$_id" != "null" ]] && DOCREF_SET[$_id]=1; done < <(yq -r '(.constraints[].id, .acceptance[].id)' "$SRS_ABS" 2>/dev/null)
fi
if [[ -f "$DM_ABS" ]]; then
  while IFS=$'\t' read -r _eid _enm; do [[ -n "$_eid" ]] && ENT_NAME[$_eid]="$_enm"; done < <(yq -r '.entities[] | [.id, .name] | @tsv' "$DM_ABS" 2>/dev/null)
fi

NOP="$(q '.operations | length')"; NERR="$(q '.errors | length')"; NEXT="$(q '.external | length')"; NCC="$(q '.cross_cutting | length')"
NOPERR="$(q '[.operations[].errors[]] | length')"
NENT="$(q '[.operations[].uses.entities[], .external[].uses.entities[]] | length')"
NSRS="$(q '[.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]] | length')"
NNOERR="$(q '[.operations[] | select((.errors | length)==0)] | length')"
echo "interface-pack fabrication-free + 固定章 + 照会 graph + id anchor proof: $HTML"
echo "  contract: $CONTRACT  (操作 $NOP / エラー $NERR / 外部連携 $NEXT / 横断 $NCC / op-error $NOPERR / ent $NENT / SRS照会 $NSRS)"

# ============ ★binding null 予約 (案A・fail-closed 予約席) ============
chk "binding 予約席 == null (プロトコル束縛 未対応)" "null" "$(q '.binding')"

# ============ ③ 固定章 + 必須要素 (census-count = contract 導出) ============
## ★genuine-shape 不変条件 (verify-datamodel と同型): band/h2 を要素単位・case-insensitive・attribute-tolerant に数える。
NBAND="$(perl -CSD -0777 -ne '$n++ while m{<section\b[^>]*data-component="chapter-deck-band"}gi; END{print $n+0}' "$BODY")"
NH2ALL="$(perl -CSD -0777 -ne '$n++ while m{<h2\b}gi; END{print $n+0}' "$BODY")"
chk "固定 6 章 (band-section 要素数・ci)"                 "6" "$NBAND"
chk "全 <h2> 要素数 == 6 (band 外/属性 decoy/大文字 h2 封鎖・ci)" "6" "$NH2ALL"
chk "operation-card 数 == |operations| (census)"     "$NOP"    "$(grep -o 'data-component="operation-card"' "$BODY" | wc -l | tr -d ' ')"
chk "error-card 数 == |errors| (census)"             "$NERR"   "$(grep -o 'data-component="error-card"' "$BODY" | wc -l | tr -d ' ')"
chk "external-row 数 == |external| (census)"         "$NEXT"   "$(grep -o 'data-component="external-row"' "$BODY" | wc -l | tr -d ' ')"
chk "cross-cutting-card 数 == |cross_cutting| (census)" "$NCC" "$(grep -o 'data-component="cross-cutting-card"' "$BODY" | wc -l | tr -d ' ')"
chk "op-error-chip 数 == Σ|op.errors| (census)"      "$NOPERR" "$(grep -o 'data-component="op-error-chip"' "$BODY" | wc -l | tr -d ' ')"
chk "ent-chip 数 == Σ|uses.entities| (census)"       "$NENT"   "$(grep -o 'class="ent-chip"' "$BODY" | wc -l | tr -d ' ')"
chk "op-io-row 数 == |operations| (census)"          "$NOP"    "$(grep -o 'data-component="op-io-row"' "$BODY" | wc -l | tr -d ' ')"
chk "op-noerror 数 == |errors 空の operation|"       "$NNOERR" "$(grep -o 'class="op-noerror"' "$BODY" | wc -l | tr -d ' ')"
chk "principle-terminal == 1"                        "1"       "$(grep -c 'data-component="principle-terminal"' "$BODY")"

# ============ ③b ★band 見出し fidelity (folio-bhe・datamodel chapters と同型) ============
BAND_H2S="$(perl -CSD -0777 -ne 'while (m{<section\b[^>]*data-component="chapter-deck-band"[^>]*>(.*?)</section>}gis){ my $b=$1; my @h=($b =~ m{<h2\b[^>]*>(.*?)</h2>}gis); print scalar(@h)==1 ? "$h[0]\n" : "(band 内 h2 数=".scalar(@h)."≠1)\n"; }' "$BODY")"
band_h2_at() { sed -n "${1}p" <<<"$BAND_H2S"; }
chk "band h2[1] == context (pack 固定)"           "なぜ「窓口の約束」を先に決めるのか"     "$(band_h2_at 1)"
chk "band h2[2] == esc(chapters.operations_band)" "$(esc "$(q '.chapters.operations_band')")" "$(band_h2_at 2)"
chk "band h2[3] == esc(chapters.errors_band)"     "$(esc "$(q '.chapters.errors_band')")"     "$(band_h2_at 3)"
chk "band h2[4] == esc(chapters.external_band)"   "$(esc "$(q '.chapters.external_band')")"    "$(band_h2_at 4)"
chk "band h2[5] == cross-cutting (pack 固定)"     "どの操作にも共通してかかる決まり"       "$(band_h2_at 5)"
chk "band h2[6] == glossary (pack 固定)"          "本文に出てくる言葉のやさしい説明"       "$(band_h2_at 6)"

# ★数詞 == 派生実件数 (肯定形・全出現照合 + 複合語 false-match 除去 + sc= 句読点境界。 assemble-interface と parity)。
band_numchk() { # $1=label $2=heading-text $3=unit-literal $4=expected-count
  local ns n bad=""
  ns="$(UNIT="$3" perl -CSD -Mutf8 -ne 'my $u=$ENV{UNIT}; utf8::decode($u); while(/([0-9]+)\s*\Q$u\E(?![\p{sc=Han}\p{sc=Katakana}ー])/g){print "$1\n"}' <<<"$2" || true)"
  if [[ -z "$ns" ]]; then chk "$1" "$4" "(ASCII 数詞なし=半角必須)"; return; fi
  while IFS= read -r n; do [[ "$n" == "$4" ]] || bad="$n"; done <<<"$ns"
  chk "$1" "$4" "${bad:-$4}"
}
band_numchk "band 数詞: operations_band「N つの操作」== |operations|" "$(q '.chapters.operations_band')" 'つの操作' "$NOP"
band_numchk "band 数詞: errors_band「N 通りの断り方」== |errors|"     "$(q '.chapters.errors_band')" '通りの断り方' "$NERR"
band_numchk "band 数詞: external_band「N つの外部連携」== |external|" "$(q '.chapters.external_band')" 'つの外部連携' "$NEXT"
# 全角数字 (件数照合の回避表記) を 3 band で禁止 (HTML==contract fidelity 成立済ゆえ contract 値で判定)。
chk "band 数詞: operations_band に全角数字なし" "0" "$(q '.chapters.operations_band' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
chk "band 数詞: errors_band に全角数字なし"     "0" "$(q '.chapters.errors_band' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
chk "band 数詞: external_band に全角数字なし"   "0" "$(q '.chapters.external_band' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
# 不可視/format 文字 (ゼロ幅・BOM 等) を全 6 見出しで拒否 (数詞隣接破壊 injection 封鎖)。
chk "band 見出し (全 6) に不可視/format 文字なし" "0" \
  "$(printf '%s' "$BAND_H2S" | perl -CSD -Mutf8 -ne '$n++ while /\p{Default_Ignorable_Code_Point}/g; END{print $n+0}')"

# ============ ② navigable id アンカー (照会されうる全ノードに id= ・集合一致) ============
exp_anchor="$( {
  q '.operations[].id'    | sed 's/^/op-/'
  q '.errors[].id'        | sed 's/^/error-/'
  q '.external[].id'      | sed 's/^/ext-/'
  q '.cross_cutting[].id' | sed 's/^/cc-/'
} | LC_ALL=C sort )"
act_anchor="$(perl -CSD -0777 -ne 'while (/\bid="(op-[^"]+|error-[^"]+|ext-[^"]+|cc-[^"]+)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "navigable id アンカー (op-/error-/ext-/cc-) == contract" "$exp_anchor" "$act_anchor"
chk "principle 終端 anchor id=principle-<id>" "1" "$(grep -c "id=\"principle-$(q '.principle.id')\"" "$BODY")"

# ============ id 一意性 ============
chk_empty "operations id 一意"    "$(q '.operations[].id'    | sort | uniq -d | tr '\n' ' ')"
chk_empty "errors id 一意"        "$(q '.errors[].id'        | sort | uniq -d | tr '\n' ' ')"
chk_empty "external id 一意"      "$(q '.external[].id'      | sort | uniq -d | tr '\n' ' ')"
chk_empty "cross_cutting id 一意" "$(q '.cross_cutting[].id' | sort | uniq -d | tr '\n' ' ')"

# ============ ① 照会グラフ整合 (cross-doc 前方照会・core 共通スケルトン) ============
# SRS 充足照会 (role=claim・data-if-ref/data-if-role)。 operations+errors+external+cross_cutting の refs.srs を横断集合で。
# 参照先 = SRS の要件/NFR/制約/受入 (FR/NFR は fragment・CON/AC は文書単位・target-ids は 4 節)。
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-if-ref" --role-attr "data-if-role" \
  --keys-expr '(.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[])' \
  --count-expr '[.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]] | length' \
  --nonempty-count-expr '[ (.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]) | select((. // "") != "") ] | length' \
  --pair-expr '(.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]) | [., "claim"] | @tsv' \
  --target-ids-expr '(.requirements[].id, .nfr[].id, .constraints[].id, .acceptance[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 1d. ★per-card 照会 fidelity (card-keyed・folio-229 §5b relocation 封鎖)。 op-/error-/ext-/cc- カードスコープ内の
#   (data-if-ref, claim) を card-id へ束ねた三つ組集合を contract と突合。 card 間で ref を入替えても global set 不変ゆえ本 pin が捕捉。
exp_cardref="$( {
  q '.operations[]    | .id as $id | .refs.srs[] | ["op-"+$id, ., "claim"] | @tsv'
  q '.errors[]        | .id as $id | .refs.srs[] | ["error-"+$id, ., "claim"] | @tsv'
  q '.external[]      | .id as $id | .refs.srs[] | ["ext-"+$id, ., "claim"] | @tsv'
  q '.cross_cutting[] | .id as $id | .refs.srs[] | ["cc-"+$id, ., "claim"] | @tsv'
} | grep . | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
act_cardref="$(perl -CSD -0777 -ne '
  while (/<article data-component="operation-card"[^>]*\bid="op-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-if-ref="([^"]*)"\s+data-if-role="([^"]*)"/gs) { print "op-$id\t$1\t$2\n"; }
  }
  while (/<article data-component="error-card"[^>]*\bid="error-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-if-ref="([^"]*)"\s+data-if-role="([^"]*)"/gs) { print "error-$id\t$1\t$2\n"; }
  }
  while (/<article data-component="external-row"[^>]*\bid="ext-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-if-ref="([^"]*)"\s+data-if-role="([^"]*)"/gs) { print "ext-$id\t$1\t$2\n"; }
  }
  while (/<div data-component="cross-cutting-card"[^>]*\bid="cc-([^"]+)">(.*?)(?=<div data-component="cross-cutting-card"|<div data-component="principle-terminal")/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/\bdata-if-ref="([^"]*)"\s+data-if-role="([^"]*)"/gs) { print "cc-$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card SRS 照会 三つ組 (card-id, ref, claim) == contract" "$exp_cardref" "$act_cardref"

# 1g. ★可視 srs-badge テキスト == 兄弟 data-if-ref (照会コードの可視捏造封鎖)。
badge_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-if-ref="([^"]*)"\s+data-if-role="[^"]*">([^<]*)<\/a>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 srs-badge テキスト == 兄弟 data-if-ref (可視捏造封鎖)" "$badge_bad"
chk "srs-badge 総数 == |SRS照会| (孤立 badge 封鎖)" "$NSRS" "$(grep -o '<a class="srs-badge"' "$BODY" | wc -l | tr -d ' ')"

# 1h. ★href 遷移先 deep-link fidelity (FR/NFR = <srs_html>#<ref> / CON/AC = <srs_html> 文書単位・anchor swap / 外部 host / filename swap 封鎖)。
#   (href, data-if-ref) == 分類別の期待 href。 href が決定的に contract 由来 + FR/NFR は fragment==REQ-ID を証明。
exp_href="$(q '(.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[])' | LC_ALL=C sort -u | while IFS= read -r _r; do
  [[ -n "$_r" ]] || continue
  if [[ -v FRAG_SET[$_r] ]]; then printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"
  else printf '%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")"; fi
done | LC_ALL=C sort -u)"
act_href="$(perl -CSD -0777 -ne 'while (/<a class="srs-badge" href="([^"]*)"(?:\s+title="[^"]*")?\s+data-if-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: SRS badge (href, ref) == 分類別 (FR/NFR=#ref・CON/AC=doc)" "$exp_href" "$act_href"
# ★CON/AC バッジは title 注記必須 (文書単位リンクの明示・deep-link 未整備の可視化)。 FR/NFR バッジは title を持たない。
exp_title="$(q '(.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[])' | LC_ALL=C sort -u | while IFS= read -r _r; do
  [[ -n "$_r" ]] || continue; [[ -v FRAG_SET[$_r] ]] || printf '%s\n' "$(esc "$_r")"
done | LC_ALL=C sort -u)"
act_title="$(perl -CSD -0777 -ne 'while (/<a class="srs-badge" href="[^"]*" title="[^"]*" data-if-ref="([^"]*)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "CON/AC バッジ title 注記 == 文書単位 ref (FR/NFR は title なし)" "$exp_title" "$act_title"

# ============ ★op-error-chip fidelity (§2 → §3 内部アンカーリンク・per-op 束縛) ============
# 各 chip: href="#error-<eid>" + 可視 ec-code == eid。 eid ∈ errors[]。 per-op で (op-id, error-id set) を contract と突合 (relocation 封鎖)。
# 1) 可視 ec-code == href fragment (chip 内部整合)。
chip_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/<a class="op-error-chip" data-component="op-error-chip" href="#error-([^"]+)">[^<]*<span class="ec-code">([^<]*)<\/span><\/a>/g){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "op-error-chip: 可視 ec-code == href fragment (chip 内部整合)" "$chip_bad"
# 2) fragment #error-<eid> == errors[].id 実在 (dangling chip 封鎖)。
exp_errids="$(q '.errors[].id' | LC_ALL=C sort -u)"
act_chipids="$(perl -CSD -0777 -ne 'while (/<a class="op-error-chip" data-component="op-error-chip" href="#error-([^"]+)">/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "op-error-chip fragment ⊆ errors[] (chip の #error-<id> 実在)" "$exp_errids" "$( { printf '%s\n' "$act_chipids"; printf '%s\n' "$exp_errids"; } | LC_ALL=C sort -u)"
# 3) per-op (op-id, error-id) 束縛 == contract operations[].errors (op 間 chip relocation 封鎖・件数保存でも捕捉)。
exp_operr="$(q '.operations[] | .id as $id | .errors[] | ["op-"+$id, .] | @tsv' | grep . | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_operr="$(perl -CSD -0777 -ne '
  while (/<article data-component="operation-card"[^>]*\bid="op-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/<a class="op-error-chip" data-component="op-error-chip" href="#error-([^"]+)">/g){ print "op-$id\t$1\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-op エラーチップ 束縛 (op-id, error-id) == contract" "$exp_operr" "$act_operr"
# 4) ★per-op noerror 束縛 (op-id, has-noerror) == contract (|errors|==0)。 datamodel per-entity 機微度と同型
#   (folio-229 relocation 封鎖)。 上の count-only (op-noerror 数) は op 間の移設 (件数保持) を素通しする —
#   「この操作に断りはありません」は境界の中核主張 (誤帰属 = 断り 3 種ある操作を無条件成功と偽る) ゆえ per-op で捕捉 (ceiling round-1 処方)。
exp_noerr="$(q '.operations[] | ["op-"+.id, (.errors | length)] | @tsv' | while IFS=$'\t' read -r _oid _n; do
  if [[ "$_n" == "0" ]]; then printf '%s\t1\n' "$(esc "$_oid")"; else printf '%s\t0\n' "$(esc "$_oid")"; fi
done | LC_ALL=C sort)"
act_noerr="$(perl -CSD -0777 -ne '
  while (/<article data-component="operation-card"[^>]*\bid="op-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); my $n=($blk=~/class="op-noerror"/)?1:0; print "op-$id\t$n\n";
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-op noerror 束縛 (op-id, has-noerror) == contract (|errors|==0)" "$exp_noerr" "$act_noerr"

# ============ ★ent-chip fidelity (uses.entities → datamodel entity への presentational deep-link・per-card 束縛) ============
# 各 ent-chip: href = <datamodel_html>#entity-<eid> + 可視 en == eid + 可視 name == datamodel entity 名。 eid ∈ datamodel entities[]。
# 1) href deep-link + 可視 en == fragment eid (chip 内部整合)。
ent_href_bad="$(DMH="$DM_HTML_E" perl -CSD -0777 -ne '
  my $dm=$ENV{DMH}; utf8::decode($dm) if 0; my @bad;
  while (/<a class="ent-chip" href="([^"]*)#entity-([^"]+)">[^<]*<span class="en">([^<]*)<\/span><\/a>/g){
    my ($base,$frag,$en)=($1,$2,$3);
    push @bad, "base:$base" if $base ne $dm;
    push @bad, "en:$frag\x{2260}$en" if $frag ne $en;
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "ent-chip: href base == datamodel_html + 可視 en == fragment (chip 内部整合)" "$ent_href_bad"
# 2) entity-id ∈ datamodel entities (dangling ent-chip 封鎖)。
exp_dment="$( { for k in "${!ENT_NAME[@]}"; do printf '%s\n' "$k"; done; } | LC_ALL=C sort -u)"
act_entids="$(perl -CSD -0777 -ne 'while (/<a class="ent-chip" href="[^"]*#entity-([^"]+)">/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "ent-chip entity-id ⊆ datamodel entities (dangling 封鎖)" "$exp_dment" "$( { printf '%s\n' "$act_entids"; printf '%s\n' "$exp_dment"; } | LC_ALL=C sort -u)"
# 3) 可視 name == datamodel entity 名 (entity-id → name の決定的解決忠実)。
name_bad=""
while IFS=$'\t' read -r _eid _nm; do
  [[ -n "$_eid" ]] || continue
  exp_nm="$(esc "${ENT_NAME[$_eid]:-__UNKNOWN__}")"
  [[ "$_nm" == "$exp_nm" ]] || name_bad+=" $_eid:got=$_nm/exp=$exp_nm"
done < <(perl -CSD -0777 -ne 'while (/<a class="ent-chip" href="([^"]*)#entity-([^"]+)">(.*?)<span class="en">([^<]*)<\/span><\/a>/g){ my ($eid,$name)=($2,$3); $name=~s/\s+$//; print "$eid\t$name\n"; }' "$BODY")
chk_empty "ent-chip 可視 name == datamodel entity 名 (id→name 解決忠実)" "${name_bad# }"
# 4) per-card (card-id, entity-id) 束縛 == contract uses.entities (op/ext カード間 relocation 封鎖)。
exp_cardent="$( {
  q '.operations[] | .id as $id | .uses.entities[] | ["op-"+$id, .] | @tsv'
  q '.external[]   | .id as $id | .uses.entities[] | ["ext-"+$id, .] | @tsv'
} | grep . | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$(esc "$a")" "$(esc "$b")"; done | LC_ALL=C sort)"
act_cardent="$(perl -CSD -0777 -ne '
  while (/<article data-component="operation-card"[^>]*\bid="op-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/<a class="ent-chip" href="[^"]*#entity-([^"]+)">/g){ print "op-$id\t$1\n"; }
  }
  while (/<article data-component="external-row"[^>]*\bid="ext-([^"]+)">(.*?)<\/article>/gs) {
    my ($id,$blk)=($1,$2); while ($blk=~/<a class="ent-chip" href="[^"]*#entity-([^"]+)">/g){ print "ext-$id\t$1\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-card ent-chip 束縛 (card-id, entity-id) == contract" "$exp_cardent" "$act_cardent"

# ============ cross-doc 可視 echo 厳密一致 (表紙 ref-chip・marker-keyed・nested reject・<b>×2) ============
chk "cross-doc: ref-chip ブロック == 1" "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"; dm_id_e="$(esc "$(q '.cross_doc.datamodel_doc_id')")"
chip_bad2="$(SRS="$srs_id_e" DMID="$dm_id_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my $dmid=$ENV{DMID}; utf8::decode($dmid); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"chip:".scalar(@bs)."B"; next}
    push @bad,"chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    push @bad,"chip:b2\x{2260}$bs[1]" if $bs[1] ne $dmid;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"chip:VIS" if $vis ne " 照会先: ${srs}の要件 (FR / CON)・${dmid}の情報のかたまり";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: ref-chip 可視 echo == テンプレ+doc_id×2 (swap/平文/nested 封鎖)" "$chip_bad2"

# ============ core 共通 chrome (cover-head/approval/glossary 値突合・folio-mk9) ============
verify_core_chrome

# ============ cover-meta KV (種別/構成/照会先/版) の決定的再導出突合 ============
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別"   "interface (インターフェース)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 構成"   "$(esc "操作 ${NOP} / 断り方 ${NERR} / 外部連携 ${NEXT}")" "$(printf '%s\n' "$meta_kv" | grep -F '構成' | head -1 | cut -f2)"
chk "cover-meta 照会先" "$(esc "$(q '.cross_doc.srs_doc_id') / $(q '.cross_doc.datamodel_doc_id')")" "$(printf '%s\n' "$meta_kv" | grep -F '照会先' | head -1 | cut -f2)"
chk "cover-meta 版"     "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# ============ 各章ノードの可視テキスト fidelity (emission 順・属性 intact のまま可視改竄/捏造を封鎖) ============
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
# --- §1 context ---
set_eq "可視 context problem == .context.problem" "$(qesc '.context.problem')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p data-component="context-problem">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 scope_note == .context.scope_note" "$(qesc '.context.scope_note')" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="scope-note-callout"><span class="sn-lab">[^<]*<\/span>([^<]*)<\/div>/g){ print "$1\n"; }' "$BODY")"
# --- §2 operations ---
# opc-num (OP-1..OP-N・位置導出)
exp_opnum="$(seq 1 "$NOP" | sed 's/^/OP-/')"
set_eq "可視 opc-num == OP-1..OP-N (位置導出)" "$exp_opnum" \
  "$(perl -CSD -0777 -ne 'while (/<span class="opc-num">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 opc-name == .operations[].name" "$(qesc '.operations[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="opc-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 opc-actor == .operations[].actor" "$(qesc '.operations[].actor')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="a-lab">使う人<\/span>([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
# io req/res (per-op interleave: request → response)。 ★mikefarah yq の (.request,.response) は request 全件→response 全件で
#   interleave にならない (verify-datamodel rel-ent と同 gotcha)。 per-op [.request,.response] を tsv で受け 1 行ずつ esc する。
exp_io="$(q '.operations[] | [.request, .response] | @tsv' | while IFS=$'\t' read -r _rq _rs; do esc "$_rq"; printf '\n'; esc "$_rs"; printf '\n'; done)"
set_eq "可視 io-val (request,response) == .operations[] 派生" "$exp_io" \
  "$(perl -CSD -0777 -ne 'while (/<div class="io-cell (?:req|res)"><span class="io-lab">[^<]*<\/span><span class="io-val">([^<]*)<\/span><\/div>/g){ print "$1\n"; }' "$BODY")"
# --- §3 errors ---
set_eq "可視 erc-id == .errors[].id" "$(qesc '.errors[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="erc-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 erc-name == .errors[].name" "$(qesc '.errors[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="erc-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 erc-when == .errors[].when" "$(qesc '.errors[].when')" \
  "$(perl -CSD -0777 -ne 'while (/<p class="erc-when"><span class="erc-k">[^<]*<\/span>([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 erc-promise == .errors[].promise" "$(qesc '.errors[].promise')" \
  "$(perl -CSD -0777 -ne 'while (/<p class="erc-promise"><span class="erc-k">[^<]*<\/span>([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# --- §4 external ---
set_eq "可視 exr-name == .external[].name" "$(qesc '.external[].name')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="exr-name">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 exr-partner == .external[].partner" "$(qesc '.external[].partner')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<span class="p-lab">相手<\/span>([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 exr-promise == .external[].promise" "$(qesc '.external[].promise')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="exr-promise">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# exr-dir (class,label) emission 順 == direction 派生 (out→送る (out) / in→受け取る (in))
exp_exrdir="$(q '.external[].direction' | while IFS= read -r _d; do case "$_d" in out) printf 'out\t送る (out)\n' ;; in) printf 'in\t受け取る (in)\n' ;; *) printf '%s\t%s\n' "$_d" "$_d" ;; esac; done)"
set_eq "可視 exr-dir (class,label) == .external[].direction 派生" "$exp_exrdir" \
  "$(perl -CSD -0777 -ne 'while (/<span class="exr-dir (out|in)"><svg.*?<\/svg>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY")"
# ★per-external 方向 束縛 (ext-id, dir-class)。 exr-dir class を ext-id へ束ね contract の (ext-id, direction) と集合一致
#   (上の count/emission-順 だけでは out↔in を順序保存で入替える relocation を素通す)。
exp_extdir="$(q '.external[] | ["ext-"+.id, .direction] | @tsv' | while IFS=$'\t' read -r _eid _d; do printf '%s\t%s\n' "$(esc "$_eid")" "$_d"; done | LC_ALL=C sort)"
act_extdir="$(perl -CSD -0777 -ne '
  while (/<article data-component="external-row" class="dir-(out|in)" id="ext-([^"]+)">/g){ print "ext-$2\t$1\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-external 方向 束縛 (ext-id, direction) == contract" "$exp_extdir" "$act_extdir"
# (被覆宣言・ceiling round-1 裁定) exr-flow (self/partner ノード図の verb 送る/受け取る) は direction の第 3 の冗長表現で
#   あり個別検査しない — 帰属は上の per-external (ext-id, dir-class) 束縛が pin し (assemble は direction から決定的導出)、
#   post-build 改竄は repro-build (REQ-VER-030) が捕捉する。repro-covered redundant presentation として明示受容。
# --- §5 cross-cutting ---
set_eq "可視 ccc-id == .cross_cutting[].id" "$(qesc '.cross_cutting[].id')" \
  "$(perl -CSD -0777 -ne 'while (/<span class="ccc-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
set_eq "可視 ccc-rule == .cross_cutting[].rule" "$(qesc '.cross_cutting[].rule')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<p class="ccc-rule">(.*?)<\/p>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# --- §5 原則終端 (pt-id / pt-text) ---
chk "principle-terminal pt-id == principle.id" "$(esc "$(q '.principle.id')")" \
  "$(perl -CSD -0777 -ne 'while (/<span class="pt-id">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "principle-terminal pt-text == principle.text" "$(esc "$(q '.principle.text')")" \
  "$(perl -CSD -0777 -ne 'while (/<p class="pt-text">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"

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

# ============ plain-language-term-inline fidelity + 用語被覆 (assemble-interface と同一語境界規律) ============
# markable = mark_terms を通す flowing フィールド (context.problem / external.promise / cross_cutting.rule)。
# operations の request/response/name/actor と errors/scope_note は esc のみ (term-inline 対象外)。
verify_term_inline \
  '.context.problem, .external[].promise, .cross_cutting[].rule' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
# ---- gate F: render 健全性 (visual) cross-pack 展開 (folio-vuf A・helper=render_gate_f)。
#      非 mermaid pack の生成 HTML を light/dark × 3 viewport で render-gate。 mermaid 検出時は honest
#      SKIP (B 段 folio-vuf B へ defer)。 fail-closed (violation/crash = $fail=1・T7 guard 維持)。 ----
render_gate_f "$HTML" "INTERFACE_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 固定章 + 照会 graph + id anchor + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
