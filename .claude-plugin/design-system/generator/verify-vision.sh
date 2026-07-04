#!/usr/bin/env bash
# folio 文書規律エンジン roadmap 段階3 後 (folio-c5r.4) — vision-pack fabrication-free + 固定章 + 照会 graph + id anchor proof (instance#1)
#
# 生成 vision HTML の *構造* が入力 contract から完全に導出されたことを機械検証する floor gate (記述型・Pichler+Wiegers hybrid)。
# verify-arch.sh (記述型 1 例目) と同型の規律を vision-pack schema (7 章・glossary 章なし) へ適用。
#
# ★floor 三本柱:
#   ① 照会グラフ整合: features[].refs.srs[] の cross-doc 照会が (a) HTML data-vision-ref 集合と集合一致 + count anchor、
#      (b) 参照先 SRS contract に実在 (dangling 0)、 (c) doc_id 一致、 (d) role 整合、 (e) href 遷移先が contract 派生値。
#      共通スケルトン = core (verify_cross_doc_refs)。 graph 終端完備 (principle) は verify-graph.sh が別途。 vision は ADR を照会しない。
#   ② navigable id アンカー: stakeholder/objective/success-criteria/feature/risk の id= (lowercase) 集合が contract と集合一致
#      + principle 終端 anchor + northstar/problem 章 anchor (arch の id anchor 規律を vision schema へ)。
#   ③ 固定章 + 必須要素: 7 章 (chapter-deck-band) + 各章の必須要素件数が contract と一致。
#      ★章数は EXPECTED_H2 配列長 (単一 SSoT) から導出 = magic「==7」を書かない (folio-bhe ceiling wf_966c2160 教訓:
#        verify-arch の arc42 専用「==8」が pack 流用で破綻した反面教師)。 vision の band 見出しは全て pack 不変
#        (件数/ドメイン非依存) ゆえ literal pin で足り、 arch の band_numchk / Default_Ignorable / 全角 guard (件数入り
#        見出しの count-fabrication 封鎖) は vision に不要 (見出しに件数が無い)。 genuine-shape 構造不変条件のみ課す。
#
# ★fab-free: 可視テキスト fidelity (emission 順 pin)・cross-doc 可視 echo 厳密一致・図 mermaid DSL 忠実 (goal_tree は optional)。
# ★floor PASS でも GREEN にせず CEILING=PENDING・exit 0 (floor 単独 GREEN 禁止・S5.1 two-gate)。 可視 count-fidelity
#   (章リードの「3 つの目標」等の prose 件数 == 配列長) は自由文の意味 fidelity ゆえ ceiling/fidelity 領分 (machine/LLM 境界・folio-5se)。
#
# usage: verify-vision.sh [--filled <manifest.yaml> | --artifact] <vision-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-vision.sh [--filled <manifest> | --artifact] <vision-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-vision.sh [--filled <manifest> | --artifact] <vision-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-vision: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-vision: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-vision: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-vision: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-vision: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=56; source "$LVC" || { echo "verify-vision: failed to source verify-common.sh" >&2; exit 2; }
fail=0
declare -i nwarn=0
make_body "$HTML"

# ★band 見出し (h2) は全て pack 不変 = literal pin。 章数 NCHAP_EXP はこの配列長から導出 (magic「==7」を書かない・bhe 教訓)。
EXPECTED_H2=(
  "目指す状態を、 一文で言い切る"
  "なぜ、 いま作るのか"
  "関係者と、 それぞれが得るもの"
  "北極星を、 測れる形に割る"
  "何を作るか — 方向だけを約束する"
  "うまくいかない道と、 あえて行かない道"
  "迷ったとき、 どちらへ倒すか"
)
NCHAP_EXP="${#EXPECTED_H2[@]}"

NST="$(q '.stakeholders.entries | length')"; NG="$(q '.objectives | length')"; NSC="$(q '.success_criteria.entries | length')"
NF="$(q '.features | length')"; NR="$(q '.risks | length')"; NSRS="$(q '[.features[].refs.srs[]] | length')"
NPITCH="$(q '.pitch.rows // [] | length')"; NGTREE="$(q '.goal_tree.lines // [] | length')"
echo "vision-pack fabrication-free + 固定章 + 照会 graph + id anchor proof: $HTML"
echo "  contract: $CONTRACT  (関係者 $NST / 目標 $NG / 成功基準 $NSC / 機能 $NF / リスク $NR / SRS照会 $NSRS / pitch $NPITCH / goal-tree行 $NGTREE)"

# ============ ③ 固定章 + 必須要素 (7 章 + 件数 = contract 導出) ============
## ★genuine-shape 不変条件 (folio-bhe ceiling wf_7edab13c/wf_6166a844 教訓): band/h2 を要素単位・case-insensitive・
##   attribute-tolerant に数え、 行 packing / 属性付き decoy <h2 class> / 大文字 <SECTION>/<H2> / band 外 h2 を封鎖する。
##   本物 = band-section NCHAP_EXP・全 <h2> NCHAP_EXP (全て band 内・1 band=1 h2)。 h2 以外の要素 (styled <p>/<div>) の
##   見出し擬態は射程外 = ceiling reviewer 領分 (machine/LLM 境界・folio-5se)。
NBAND="$(perl -CSD -0777 -ne '$n++ while m{<section\b[^>]*data-component="chapter-deck-band"}gi; END{print $n+0}' "$BODY")"
NH2ALL="$(perl -CSD -0777 -ne '$n++ while m{<h2\b}gi; END{print $n+0}' "$BODY")"
chk "固定 $NCHAP_EXP 章 (band-section 要素数・ci)"        "$NCHAP_EXP" "$NBAND"
chk "全 <h2> 要素数 == $NCHAP_EXP (band 外/属性 decoy/大文字 h2 封鎖・ci)" "$NCHAP_EXP" "$NH2ALL"
# 各 band 内の <h2> がちょうど 1 個 (attribute-tolerant)・見出しテキストを positional 抽出 (2 個目 decoy は poison token 化)。
BAND_H2S="$(perl -CSD -0777 -ne 'while (m{<section\b[^>]*data-component="chapter-deck-band"[^>]*>(.*?)</section>}gis){ my $b=$1; my @h=($b =~ m{<h2\b[^>]*>(.*?)</h2>}gis); print scalar(@h)==1 ? "$h[0]\n" : "(band 内 h2 数=".scalar(@h)."≠1)\n"; }' "$BODY")"
band_h2_at() { sed -n "${1}p" <<<"$BAND_H2S"; }
i=0
for h in "${EXPECTED_H2[@]}"; do
  i=$((i+1))
  chk "band h2[$i] == pack 固定見出し" "$(esc "$h")" "$(band_h2_at "$i")"
done
# 各章の必須要素件数 (要素単位・contract 配列長と一致)。
chk "vision-north-star == 1"          "1"    "$(perl -CSD -0777 -ne '$n++ while m{<div\b[^>]*data-component="vision-north-star"}gi; END{print $n+0}' "$BODY")"
chk "stakeholder card == |stakeholders|" "$NST" "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-card" id=}g; END{print $n+0}' "$BODY")"
chk "objective card == |objectives|"  "$NG"  "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-card obj" id=}g; END{print $n+0}' "$BODY")"
chk "success-criteria card == |sc|"   "$NSC" "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-card sc" id=}g; END{print $n+0}' "$BODY")"
chk "feature card == |features|"      "$NF"  "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-feat" id=}g; END{print $n+0}' "$BODY")"
chk "risk card == |risks|"            "$NR"  "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-card risk" id=}g; END{print $n+0}' "$BODY")"
chk "vision-feature-list == 1"        "1"    "$(perl -CSD -0777 -ne '$n++ while m{data-component="vision-feature-list"}g; END{print $n+0}' "$BODY")"
chk "principle-terminal == 1"         "1"    "$(perl -CSD -0777 -ne '$n++ while m{<div\b[^>]*data-component="principle-terminal"}gi; END{print $n+0}' "$BODY")"
chk "vision-non-goals == 1"           "1"    "$(perl -CSD -0777 -ne '$n++ while m{<div\b[^>]*data-component="vision-non-goals"}gi; END{print $n+0}' "$BODY")"
chk "no-restate aside == 3 (問題/関係者/成功基準)" "3" "$(perl -CSD -0777 -ne '$n++ while m{<aside\b[^>]*data-component="no-restate-note"}gi; END{print $n+0}' "$BODY")"
# pitch (opt-in): 在れば pitch-grammar 1 + rows == |pitch.rows|、 無ければ両方 0。
chk "vision-pitch-grammar == (pitch 有:1/無:0)" "$([[ "$NPITCH" != "0" ]] && echo 1 || echo 0)" "$(perl -CSD -0777 -ne '$n++ while m{data-component="vision-pitch-grammar"}g; END{print $n+0}' "$BODY")"
chk "pitch row == |pitch.rows|" "$NPITCH" "$(perl -CSD -0777 -ne '$n++ while m{<div class="vm-pg-row">}g; END{print $n+0}' "$BODY")"
# goal-tree (optional): 在れば diagram 1 + mermaid pre 1 + figcaption 1、 無ければ 0。
NGT_EXP="$([[ "$NGTREE" != "0" ]] && echo 1 || echo 0)"
chk "goal-tree-diagram == (goal_tree 有:1/無:0)" "$NGT_EXP" "$(perl -CSD -0777 -ne '$n++ while m{data-component="goal-tree-diagram"}g; END{print $n+0}' "$BODY")"

# ============ ② navigable id アンカー (照会されうる全ノードに id= (lowercase)・集合一致) ============
exp_anchor="$( { q '.stakeholders.entries[].id'; q '.objectives[].id'; q '.success_criteria.entries[].id'; q '.features[].id'; q '.risks[].id'; } | tr 'A-Z' 'a-z' | LC_ALL=C sort )"
act_anchor="$(perl -CSD -0777 -ne 'while (/\bid="(st-[^"]+|g-[^"]+|sc-[^"]+|f-[^"]+|r-[^"]+)"/g){ print "$1\n"; }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "navigable id アンカー (st-/g-/sc-/f-/r-) == contract (lowercase)" "$exp_anchor" "$act_anchor"
chk "principle 終端 anchor id=principle-<id>" "1" "$(grep -c "id=\"principle-$(q '.principle.id')\"" "$BODY")"
chk "章 anchor id=northstar == 1" "1" "$(grep -c 'id="northstar"' "$BODY")"
chk "章 anchor id=problem == 1"   "1" "$(grep -c 'id="problem"' "$BODY")"

# ============ id 一意性 ============
chk_empty "stakeholders id 一意"     "$(q '.stakeholders.entries[].id'     | sort | uniq -d | tr '\n' ' ')"
chk_empty "objectives id 一意"       "$(q '.objectives[].id'               | sort | uniq -d | tr '\n' ' ')"
chk_empty "success_criteria id 一意" "$(q '.success_criteria.entries[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "features id 一意"         "$(q '.features[].id'                 | sort | uniq -d | tr '\n' ' ')"
chk_empty "risks id 一意"            "$(q '.risks[].id'                    | sort | uniq -d | tr '\n' ' ')"
# success_criteria.for_goal ⊆ objectives.id (物差しが実在しない目標を指さない)
chk_empty "success_criteria.for_goal ⊆ objectives.id" \
  "$(LC_ALL=C comm -23 <(q '.success_criteria.entries[].for_goal' | LC_ALL=C sort -u) <(q '.objectives[].id' | LC_ALL=C sort -u) | tr '\n' ' ')"

# ============ ① 照会グラフ整合 (cross-doc 前方照会・core 共通スケルトン) ============
# SRS 充足照会 (role=claim・data-vision-ref/data-vision-role)。 vision は SRS のみ照会 (ADR 根拠照会は持たない)。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc(SRS)" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-vision-ref" --role-attr "data-vision-role" \
  --keys-expr '.features[].refs.srs[]' \
  --count-expr '[.features[].refs.srs[]] | length' \
  --nonempty-count-expr '[ .features[].refs.srs[] | select((. // "") != "") ] | length' \
  --pair-expr '.features[].refs.srs[] | [., "claim"] | @tsv' \
  --target-ids-expr '.requirements[].id' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# per-feature 照会 fidelity (card-keyed)。 各 feature (id=f-<lc>) スコープ内の (data-vision-ref, claim) を feature id へ束ねて突合。
# ★lowercase は shell (${id,,}) で行う: mikefarah yq に jq の ascii_downcase は無い (silent empty expected = fail-open)。
exp_featref="$(q '.features[].id' | while IFS= read -r fid; do
  [[ -n "$fid" ]] || continue; lc="${fid,,}"
  FID="$fid" q '.features[] | select(.id==strenv(FID)) | .refs.srs[]' | while IFS= read -r fr; do
    [[ -n "$fr" ]] && printf '%s\t%s\tclaim\n' "$(esc "$lc")" "$(esc "$fr")"
  done
done | LC_ALL=C sort)"
act_featref="$(perl -CSD -0777 -ne '
  while (/<div class="vm-feat" id="([^"]+)">(.*?)(?=<div class="vm-feat"|<\/div>\s*<\/div>\s*<section|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/\bdata-vision-ref="([^"]*)"\s+data-vision-role="([^"]*)"/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
LC_ALL=C set_eq "per-feature SRS 照会 三つ組 (f-id, FR, claim) == contract" "$exp_featref" "$act_featref"

# SRS 由来 機能名ラベル fidelity (裸 FR コードに機能名併記)。 (ref, 可視ラベル) 集合 == SRS requirements[].label。
chk "data-srs-label-ref 数 == |SRS照会|" "$NSRS" "$(grep -o 'data-srs-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_srslabels="$(q '[.features[].refs.srs[]] | unique | .[]' | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(FR="$_r" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")")"; done | LC_ALL=C sort -u)"
act_srslabels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-srs-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "SRS 機能名ラベル (ref, label) == SRS 由来 (FR=label)" "$exp_srslabels" "$act_srslabels"

# 1g. 可視 xref-code バッジ == 兄弟 data-vision-ref 属性 (照会コードの可視捏造封鎖) + 総数 pin。
xref_code_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/data-vision-ref="([^"]*)"[^>]*?><span class="xref-code">([^<]*)<\/span>/gs){ push @bad, "$1\x{2260}$2" if $1 ne $2; }
  print join(" ", @bad);
' "$BODY")"
chk_empty "可視 xref-code == 兄弟 data-vision-ref 属性 (照会コードの可視捏造封鎖)" "$xref_code_bad"
# xref-code 総数 == SRS照会 (feature) + no-restate aside(3) + non-goals(1)。 no-restate/non-goals も xref-code を持つ。
chk "可視 xref-code 総数 == |SRS照会|+no-restate3+non-goals1" "$((NSRS + 3 + 1))" "$(grep -o '<span class="xref-code">' "$BODY" | wc -l | tr -d ' ')"

# 1h. href 遷移先 fidelity (feature SRS claim の飛び先を contract 派生値へ束縛)。 (href, data-vision-ref) == <srs_html>#<ref>。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
exp_srs_href="$(q '.features[].refs.srs[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_srs_href="$(perl -CSD -0777 -ne 'while (/\bhref="([^"]*)"\s+data-vision-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: SRS claim (href, FR) == <srs_html>#<ref>" "$exp_srs_href" "$act_srs_href"

# ============ cross-doc-ref-chip 可視 echo 厳密一致 (vision は <b> 1 個 = SRS のみ) ============
chk "cross-doc: ref-chip ブロック == 1" "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
chip_bad="$(SRS="$srs_id_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"chip:".scalar(@bs)."B"; next}
    push @bad,"chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"chip:VIS" if $vis ne " 照会先: ${srs}の要件・受入基準 (このビジョンの「何を作るか」の具体)";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: ref-chip 可視 echo == テンプレ+doc_id (swap/平文/nested 封鎖)" "$chip_bad"

# ============ core 共通 chrome (cover-head/approval/reader-chip 占有・vision は glossary 表を持たない) ============
# ★verify_core_chrome (core) を呼ばず inline する: vision は用語集章を持たない = glossary 表が無い。 core の glossary
#   chrome 突合は `.glossary[] | [.term,…] | @tsv` を使うが、 mikefarah yq v4.53 の collect+@tsv は *空入力に対し
#   phantom 1 行 (\t\t)* を吐く (`.glossary[]` 単体は正しく空だが `| [..] | @tsv` が空 collect を 1 個生む quirk・
#   absent でも [] でも再現)。 core 無改変 (byte-identity 最重 gate) を保つため、 glossary 表 4 検査を除いた
#   cover-head/approval/reader-chip 占有検査のみを faithful subset として inline する (vision に glossary 表は無く
#   検査対象が存在しない = honest な pack 差分。 term-inline/用語被覆も vision は非適用)。
nap="$(q '.approval | length')"
readerlines="$(grep 'class="reader-chip">' "$BODY")"
# (1) cover-head 値突合 (eyebrow 左右対 / h1 / sub / 想定読者)
chk "core-chrome: cover-eyebrow (左,右) == .meta.eyebrow_left/right" \
  "$(printf '%s\t%s' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")")" \
  "$(perl -CSD -0777 -ne 'while (/<p class="cover-eyebrow"><span class="doc-type">([^<]*)<\/span> <span>([^<]*)<\/span><\/p>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "core-chrome: cover h1 == .meta.title" "$(esc "$(q '.meta.title')")" \
  "$(grep -oE '<h1>[^<]*</h1>' "$BODY" | sed -E 's#<h1>([^<]*)</h1>#\1#')"
chk "core-chrome: cover-sub == .meta.subtitle" "$(esc "$(q '.meta.subtitle')")" \
  "$(grep -oE '<p class="cover-sub">[^<]*</p>' "$BODY" | sed -E 's#<p class="cover-sub">([^<]*)</p>#\1#')"
chk "core-chrome: reader-chip 想定読者 == .meta.reader" "$(esc "$(q '.meta.reader')")" \
  "$(printf '%s\n' "$readerlines" | grep -oE '想定読者: [^<]*</div>' | sed -E 's/^想定読者: //; s#</div>$##')"
chk "core-chrome: vcount doc-type == 1"      "1" "$(count_attr_token class doc-type < "$BODY")"
chk "core-chrome: vcount cover-eyebrow == 1" "1" "$(count_attr_token class cover-eyebrow < "$BODY")"
chk "core-chrome: vcount cover-sub == 1"     "1" "$(count_attr_token class cover-sub < "$BODY")"
chk "core-chrome: h1 タグ == 1"              "1" "$(grep -oiE '<h1[[:space:]>]' "$BODY" | wc -l | tr -d ' ')"
chk "core-chrome: genuine reader-chip 占有 (ref-chip 除外・要素単位) == 1" "1" "$(count_genuine_reader_chip < "$BODY")"
chk "core-chrome: 想定読者 marker 全体 == 1" "1" "$(grep -oF '想定読者:' "$BODY" | wc -l | tr -d ' ')"
# (2) approval-block 順序突合 + 占有数
chk "core-chrome: approval (role,who,when,stamp) == .approval (順序)" \
  "$(q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r _r _w _t _s; do printf '%s\t%s\t%s\t%s\n' "$(esc "$_r")" "$(esc "$_w")" "$(esc "$_t")" "$(esc "$_s")"; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div class="sign"><span class="role">([^<]*)<\/span><span class="who">([^<]*)<\/span><span class="when">([^<]*)<\/span><span class="stamp(?: self)?">([^<]*)<\/span><\/div>/g){ print "$1\t$2\t$3\t$4\n"; }' "$BODY")"
chk "core-chrome: vcount sign == |approval|"  "$nap" "$(count_attr_token class sign < "$BODY")"
chk "core-chrome: vcount who == |approval|"   "$nap" "$(count_attr_token class who < "$BODY")"
chk "core-chrome: vcount when == |approval|"  "$nap" "$(count_attr_token class when < "$BODY")"
chk "core-chrome: vcount stamp == |approval|" "$nap" "$(count_attr_token class stamp < "$BODY")"
# (3) role/en global 占有 (glossary 表なし = |非空 en| 0・追加 home なし)
chk "core-chrome: vcount role global == |approval|" "$nap" "$(count_attr_token class role < "$BODY")"
chk "core-chrome: vcount en global == 0 (glossary 表なし)" "0" "$(count_attr_token class en < "$BODY")"
chk "core-chrome: reader-chip class 総数 == 2 (genuine 1 + cross-doc-ref-chip 1)" "2" "$(count_attr_token class reader-chip < "$BODY")"

# ============ cover-meta KV (種別/構成/照会先/版) の決定的再導出突合 ============
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別"   "vision (ビジョン — なぜ作るか)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 構成"   "$(esc "${NCHAP_EXP} 章 (目標 ${NG} / 成功基準 ${NSC} / 機能方向 ${NF} / 関係者 ${NST} / リスク ${NR} / 原則 1)")" "$(printf '%s\n' "$meta_kv" | grep -F '構成' | head -1 | cut -f2)"
chk "cover-meta 照会先" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(printf '%s\n' "$meta_kv" | grep -F '照会先' | head -1 | cut -f2)"
chk "cover-meta 版"     "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"
# ★自文書 doc_id (data-doc-id 属性) fidelity (ceiling wf_64344fbe low 是正・rendered contract 値の floor 被覆)。
chk "data-doc-id == .meta.doc_id" "$(esc "$(q '.meta.doc_id')")" \
  "$(perl -CSD -0777 -ne 'if(/\bdata-doc-id="([^"]*)"/){print "$1"}' "$BODY")"

# ============ 各章ノードの可視テキスト fidelity (emission 順・属性 intact のまま可視改竄/捏造を封鎖) ============
# vm-cid / vm-ct / vm-cd は 5 セクション (関係者→目標→成功基準→機能→リスク) を横断する共有クラス。 文書順は決定的
# (assembler の band 順) ゆえ、 contract を同順で連結し emission 順 set_eq (positional) すると per-item 捏造・入替を封鎖する。
exp_cid="$( { q '.stakeholders.entries[].id'; q '.objectives[].id'; q '.success_criteria.entries[].id'; q '.features[].id'; q '.risks[].id'; } | while IFS= read -r v; do esc "$v"; printf '\n'; done )"
act_cid="$(perl -CSD -0777 -ne 'while(/<span class="vm-cid">([^<]*)<\/span>/g){print "$1\n"}' "$BODY")"
set_eq "可視 vm-cid (ST/G/SC/F/R id 連結) == contract (emission 順)" "$exp_cid" "$act_cid"
exp_ct="$( { q '.stakeholders.entries[].name'; q '.objectives[].name'; q '.success_criteria.entries[].name'; q '.features[].name'; q '.risks[].name'; } | while IFS= read -r v; do esc "$v"; printf '\n'; done )"
act_ct="$(perl -CSD -0777 -ne 'while(/<span class="vm-ct">([^<]*)<\/span>/g){print "$1\n"}' "$BODY")"
set_eq "可視 vm-ct (名前 連結) == contract (emission 順)" "$exp_ct" "$act_ct"
exp_cd="$( { q '.stakeholders.entries[].gain'; q '.objectives[].desc'; q '.success_criteria.entries[].desc'; q '.features[].desc'; q '.risks[].desc'; } | while IFS= read -r v; do esc "$v"; printf '\n'; done )"
act_cd="$(perl -CSD -0777 -ne 'while(/<p class="vm-cd">([^<]*)<\/p>/g){print "$1\n"}' "$BODY")"
set_eq "可視 vm-cd (便益/説明 連結) == contract (emission 順)" "$exp_cd" "$act_cd"
# success-criteria の for_goal (→ G-x の物差し)
set_eq "可視 sc for_goal (→ G の物差し) == .success_criteria.for_goal" \
  "$(q '.success_criteria.entries[] | "→ " + .for_goal + " の物差し"' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while(/<span class="vm-sc-for">([^<]*)<\/span>/g){print "$1\n"}' "$BODY")"
# 北極星 text / narrative
chk "可視 north-star text == .north_star.text" "$(esc "$(q '.north_star.text')")" \
  "$(perl -CSD -0777 -ne 'if(/<p class="vm-ns-text">([^<]*)<\/p>/){print "$1"}' "$BODY")"
# north_star.narrative は north-star box 直後の素<p> / principle.narrative は principle-terminal box 直後の素<p> (box 後へ scope)。
chk "可視 north-star narrative == .north_star.narrative" "$(esc "$(q '.north_star.narrative')")" \
  "$(perl -CSD -0777 -ne 'if(/data-component="vision-north-star"[^>]*>.*?<\/div>\s*<p>([^<]*)<\/p>/s){print "$1"}' "$BODY")"
chk "可視 principle narrative == .principle.narrative" "$(esc "$(q '.principle.narrative')")" \
  "$(perl -CSD -0777 -ne 'if(/data-component="principle-terminal"[^>]*>.*?<\/div>\s*<p>([^<]*)<\/p>/s){print "$1"}' "$BODY")"
# problem paragraphs (§2・id="problem" 開始〜<aside まで scope し、 その内の全 <p> を emission 順抽出・段落数非依存)。
set_eq "可視 problem paragraphs == .problem.paragraphs[]" "$(qesc '.problem.paragraphs[]')" \
  "$(perl -CSD -0777 -ne 'if(/(<p id="problem">.*?)<aside\b/s){my $blk=$1; while($blk=~/<p[^>]*>([^<]*)<\/p>/g){print "$1\n"}}' "$BODY")"
# pitch rows (key/value/ref_label) — opt-in
if [[ "$NPITCH" != "0" ]]; then
  set_eq "可視 pitch key == .pitch.rows[].key" "$(qesc '.pitch.rows[].key')" \
    "$(perl -CSD -0777 -ne 'while(/<span class="vm-pg-k">([^<]*)<\/span>/g){print "$1\n"}' "$BODY")"
  set_eq "可視 pitch value == .pitch.rows[].value" "$(qesc '.pitch.rows[].value')" \
    "$(perl -CSD -0777 -ne 'while(/<span class="vm-pg-v">([^<]*)<\/span>/g){print "$1\n"}' "$BODY")"
  set_eq "pitch ref href == #<ref_anchor> (内部照会先 fidelity)" \
    "$(q '.pitch.rows[].ref_anchor' | while IFS= read -r v; do printf '#%s\n' "$(esc "$v")"; done)" \
    "$(perl -CSD -0777 -ne 'while(/<a class="vm-pg-ref" href="([^"]*)">/g){print "$1\n"}' "$BODY")"
  # ★pitch ref_label (可視「↔ §3 関係者」等) fidelity (ceiling wf_64344fbe medium 是正): key/value/href は突合済だが
  #   ref_label だけ未突合で捏造がすり抜けた。 emit は「↔ {ref_label}」ゆえ contract 値に「↔ 」を前置して emission 順突合。
  set_eq "可視 pitch ref_label (↔ ラベル) == .pitch.rows[].ref_label" \
    "$(q '.pitch.rows[].ref_label' | while IFS= read -r v; do esc "↔ $v"; printf '\n'; done)" \
    "$(perl -CSD -0777 -ne 'while(/<a class="vm-pg-ref" href="[^"]*">([^<]*)<\/a>/g){print "$1\n"}' "$BODY")"
fi
# no-restate aside 本文 (問題/関係者/成功基準 の順) + non-goals 本文
set_eq "可視 no-restate 本文 == .{problem,stakeholders,success_criteria}.no_restate.text" \
  "$( { q '.problem.no_restate.text'; q '.stakeholders.no_restate.text'; q '.success_criteria.no_restate.text'; } | while IFS= read -r v; do esc "$v"; printf '\n'; done )" \
  "$(perl -CSD -0777 -ne 'while(/<aside data-component="no-restate-note">(.*?) <a class="xref-link"/gs){print "$1\n"}' "$BODY")"
chk "可視 non-goals 本文 == .non_goals.text" "$(esc "$(q '.non_goals.text')")" \
  "$(perl -CSD -0777 -ne 'if(/<div data-component="vision-non-goals"><p class="vm-ng-title">[^<]*<\/p>\s*<p>(.*?) <a class="xref-link"/s){print "$1"}' "$BODY")"
# ★no-restate / non-goals の照会リンク 三つ組 (href, xref-code, xref-label) fidelity (ceiling wf_64344fbe high 是正):
#   兄弟の xref-code (SRS 章コード) は突合していたが xref-label (可視参照ラベル 4 本) と href (遷移先 4 本) が未突合で
#   捏造がすり抜けた (feature の label/href は L#feature で束縛済なのに aside/非目標だけ非対称に欠落)。 aside/非目標の
#   <a class="xref-link" href="..."> は href 引用直後が > (feature は data-vision-ref が挟まる) ゆえ属性で分離可能。
#   href = srs_html [+ #srs_anchor (success_criteria のみ AC1)]・code/label は contract 値へ束縛 (link-integrity P-6・feature と対称)。
# ★positional 突合 (ceiling 再cert 是正・自 fix 回帰): 三つ組を sorted set にすると本文 (positional 突合) と chip
#   (set) が独立になり、 4 chip を aside 間で集合保存的に並べ替えると body[i]↔chip[i] の帰属が desync しても素通る
#   (§2 問題章が「アクター定義」を誤引用する mis-citation が floor PASS)。 emission 順 (problem→stakeholders→
#   success_criteria→非目標) は contract exp 順と一致するゆえ positional で body と同 index を共有し帰属を束縛する
#   (positional ⊇ set = 既存捕捉を緩めない・bhe「各巡の blocker は前巡自身の fix の回帰」の実証)。
SRS_HTML_A="$(q '.cross_doc.srs_html')"
exp_aside="$( {
  printf '%s\t%s\t%s\n' "$(esc "$SRS_HTML_A")"                                        "$(esc "$(q '.problem.no_restate.srs_code')")"          "$(esc "$(q '.problem.no_restate.srs_label')")"
  printf '%s\t%s\t%s\n' "$(esc "$SRS_HTML_A")"                                        "$(esc "$(q '.stakeholders.no_restate.srs_code')")"     "$(esc "$(q '.stakeholders.no_restate.srs_label')")"
  printf '%s#%s\t%s\t%s\n' "$(esc "$SRS_HTML_A")" "$(esc "$(q '.success_criteria.no_restate.srs_anchor')")" "$(esc "$(q '.success_criteria.no_restate.srs_code')")" "$(esc "$(q '.success_criteria.no_restate.srs_label')")"
  printf '%s\t%s\t%s\n' "$(esc "$SRS_HTML_A")"                                        "$(esc "$(q '.non_goals.srs_code')")"                   "$(esc "$(q '.non_goals.srs_label')")"
} )"
act_aside="$(perl -CSD -0777 -ne 'while(/<a class="xref-link" href="([^"]*)"><span class="xref-code">([^<]*)<\/span><span class="xref-label">([^<]*)<\/span><\/a>/g){print "$1\t$2\t$3\n"}' "$BODY")"
set_eq "可視 no-restate/非目標 照会 (href, code, label) == contract 派生 (emission 順)" "$exp_aside" "$act_aside"
# principle-terminal pt-id / pt-text
chk "principle-terminal pt-id == principle.id" "$(esc "$(q '.principle.id')")" \
  "$(perl -CSD -0777 -ne 'if(/<span class="pt-id">([^<]*)<\/span>/){print "$1"}' "$BODY")"
chk "principle-terminal pt-text == principle.text" "$(esc "$(q '.principle.text')")" \
  "$(perl -CSD -0777 -ne 'if(/<p class="pt-text">([^<]*)<\/p>/){print "$1"}' "$BODY")"

# ============ 目標ツリー図 (optional) fidelity ============
if [[ "$NGTREE" != "0" ]]; then
  exp_m="$(q '.goal_tree.lines[]' | while IFS= read -r ln; do esc "$ln"; printf '\x01'; done | sed 's/\x01$//')"
  act_m="$(perl -CSD -0777 -ne 'if(/<pre class="mermaid">(.*?)<\/pre>/s){my $t=$1; $t=~s/\n/\x01/g; print "$t"}' "$BODY")"
  chk "goal-tree mermaid DSL == esc(contract lines)" "$exp_m" "$act_m"
  chk "goal-tree figcaption == diag-tag + esc(caption)" \
    "<span class=\"diag-tag\">目標ツリー</span>$(esc "$(q '.goal_tree.caption')")" \
    "$(perl -CSD -0777 -ne 'if(/<figcaption>(.*?)<\/figcaption>/s){my $t=$1;$t=~s/\n/ /g;print "$t"}' "$BODY")"
fi

# ============ CJK inline 強調の空白規律 (FAIL) ============
cjk_bad="$(perl -CSD -Mutf8 -0777 -ne '
  my $cjk=qr/[\p{Han}\p{Hiragana}\p{Katakana}]/; my $n=0;
  $n++ while /$cjk[ \t]+<(?:b|strong)\b/g;
  $n++ while /<\/(?:b|strong)>[ \t]+$cjk/g;
  print $n;
' "$BODY")"
chk "CJK inline 強調の空白規律 (CJK 隣接の <b> 前後空白 0)" "0" "$cjk_bad"

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

echo
[[ "$nwarn" -eq 0 ]] || echo "  ($nwarn 件の WARN は advisory・floor を割らない)"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 固定章 + 照会 graph + id anchor + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + 照会 graph 解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
