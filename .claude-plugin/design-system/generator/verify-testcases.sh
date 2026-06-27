#!/usr/bin/env bash
# folio engine 段階2c (folio-uvt) — test-cases-pack fabrication-free + 三段 trace + cross-doc 照会 proof (instance#6)
#
# 生成 test-cases HTML の *構造* が入力 test-cases contract から完全に導出されたことを機械検証する floor gate。
# verify-adr.sh (ADR-pack) / verify-glossary.sh (glossary-pack) と同型の規律を test-cases-pack schema へ適用:
#   - 件数 (testcase-card / rtm-row / prose スロット) が contract 要素数と一致。
#   - id 一意性 (test_cases)。
#   - ★cross-doc 前方照会 (本 pack の核): test_cases[].trace.{verifies,confirms} の FR/AC 集合が
#       (a) HTML の data-trace-ref 集合と *集合一致* (捏造 0 + 脱落 0) + count anchor で |edges| と一致、
#       (b) 参照先 SRS contract の要件/受入基準 ID に *実在* (dangling 照会 0)、
#       (c) cross_doc.srs_doc_id == SRS contract .meta.doc_id、
#       (d) data-trace-role が抽象ロール allowlist 内、
#       (d') (ref,role) ペア集合が contract と *集合一致* (FR=claim / AC=verification の改竄 = 照会 graph 意味偽装を捕捉)。
#     共通スケルトンは core (verify-common.sh の verify_cross_doc_refs・named-flag・fail-closed)。
#   - ★cross-doc 可視 echo 厳密一致 (表紙 ref-chip / 各 card の trace 見出し・照会先 / tc-ref 可視==attr) =
#       marker-keyed + nested-same-tag reject (ds8/B3 不動点)。
#   - ★三段 trace の within-doc fidelity: RTM 行 (tc,kind,FR,AC) + 各 card の可視テキスト
#       (id/kind/priority/title/precondition/steps/expected) を *emission 順* で contract へ pin
#       (捏造手順・捏造ケース・属性 intact のまま可視文字だけ改竄を封鎖)。
#   - core 共通 chrome (cover-head/approval/glossary)・escape 健全性・prose スロット mode・term-inline。
#
# usage: verify-testcases.sh [--filled <manifest.yaml> | --artifact] <testcases-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合。
#   plain 要約 (cover-summary / chapter-lead / plain-TCx prose スロット) の *内容真正性* (平易さ・捏造の不在) は
#   floor の対象外 = ceiling (fidelity-srs 相当の機械 SSoT 突合 + persona-walk)。 floor 単独で GREEN にはならず
#   CEILING=PENDING を出力する。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-testcases.sh [--filled <manifest> | --artifact] <testcases-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-testcases.sh [--filled <manifest> | --artifact] <testcases-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-testcases: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-testcases: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-testcases: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-testcases: perl required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-testcases: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=52; source "$LVC" || { echo "verify-testcases: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"

NTC="$(q '.test_cases | length')"
NEDGE="$(q '[.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]] | length')"
echo "test-cases-pack fabrication-free + 三段 trace + cross-doc 照会 proof: $HTML"
echo "  contract: $CONTRACT  ($NTC ケース / $NEDGE trace edge)"

# 1. 件数 (data-component / class 行マーカーで scoped)
chk "testcase-card 数 == |test_cases|" "$NTC" "$(grep -c 'data-component="testcase-card"' "$BODY")"
chk "rtm-row 数 == |test_cases|"       "$NTC" "$(grep -c 'data-component="rtm-row"' "$BODY")"
# 1a. ★scope-summary-panel (試すこと/試さないこと) の件数 + fidelity 突合。
#   scope.in[]/scope.out[] は esc 済 plain text を <li><span class="b">●</span>… として決定的 emit する
#   (mark_terms 不適用 = 可視 == esc 済 contract)。 panel/item 件数 anchor (sibling verify-research.sh:68-70 の
#   round-5 ceiling precedent = scope panel の count 漏れ fail-open を family 内で逐語継承) に加え、 in/out を分離した
#   set_eq で「捏造文への書換・項目の差し替え」も封鎖する (件数 anchor だけでは rewrite が素通る fail-open を塞ぐ)。
chk "scope panel == 1"                  "1" "$(grep -c 'data-component="scope-summary-panel"' "$BODY")"
chk "scope items == |in|+|out|"         "$(( $(q '.scope.in | length') + $(q '.scope.out | length') ))" "$(grep -c '<li><span class="b">' "$BODY")"
# in/out を .scol in / .scol out ブロックへ scope して可視 li テキスト (●マーカー span 除去後) を emission 順で contract と突合。
scope_in_act="$(perl -CSD -0777 -ne 'if (/<div class="scol in">(.*?)<\/div>/s){ my $b=$1; while ($b=~/<li><span class="b">[^<]*<\/span>(.*?)<\/li>/gs){ print "$1\n"; } }' "$BODY")"
scope_out_act="$(perl -CSD -0777 -ne 'if (/<div class="scol out">(.*?)<\/div>/s){ my $b=$1; while ($b=~/<li><span class="b">[^<]*<\/span>(.*?)<\/li>/gs){ print "$1\n"; } }' "$BODY")"
set_eq "scope.in 可視 == contract (順序)"  "$(qesc '.scope.in[]')"  "$scope_in_act"
set_eq "scope.out 可視 == contract (順序)" "$(qesc '.scope.out[]')" "$scope_out_act"
# 1b. core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)
verify_core_chrome
# 1b'. reader-chip class 総数 == 2 (genuine reader-chip 1 + cross-doc-ref-chip 1。 ADR と対称・quote-robust)
chk "core-chrome: reader-chip class 総数 == 2 (genuine 1 + cross-doc-ref-chip 1)" "2" "$(count_attr_token class reader-chip < "$BODY")"

# 2. id 一意性
chk_empty "test_cases id 一意" "$(q '.test_cases[].id' | sort | uniq -d | tr '\n' ' ')"

# 3. ★cross-doc 前方照会 (本 pack の核・core 共通スケルトン)
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
verify_cross_doc_refs \
  --label-prefix "cross-doc" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-trace-ref" --role-attr "data-trace-role" \
  --keys-expr '.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]' \
  --count-expr '[.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]] | length' \
  --nonempty-count-expr '[ (.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]) | select((. // "") != "") ] | length' \
  --pair-expr '(.test_cases[].trace.verifies[] | [., "claim"] | @tsv), (.test_cases[].trace.confirms[] | [., "verification"] | @tsv)' \
  --target-ids-expr '(.requirements[].id, .acceptance[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 3b. ★cross-doc 可視 echo の堅牢検証 (ADR Part 2b template を test-cases の可視 echo へ)。
#   非エンジニアが読むのは attr でなく *可視テキスト*。 各 echo ブロックは固定個数 (ブロック削除で while 不発の fail-open を count anchor で塞ぐ)。
chk "cross-doc: ref-chip ブロック == 1"             "1"    "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "cross-doc: tc-trace-h ブロック == |test_cases|" "$NTC" "$(grep -c 'class="tc-trace-h"' "$BODY")"
chk "cross-doc: tc-trace-tgt ブロック == |test_cases|" "$NTC" "$(grep -c 'class="tc-trace-tgt"' "$BODY")"
chk "cross-doc: tc-ref span == |edges|"             "$NEDGE" "$(grep -o 'class="tc-ref"' "$BODY" | wc -l | tr -d ' ')"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
# ★cover ref-chip b2 = FR の平易機能名要約 (SRS requirements[].label を unique FR の first-occurrence 順で join)。
#   assembler emit_cover と同一導出 (REF_LABEL = SRS 由来・fabrication-free)。 SRS_ABS は §3 で設定済。 これにより
#   非エンジニアは表紙で裸 FR コードでなく機能名で検証対象を把握できる (persona ceiling BLOCKER 是正)。
fr_label_join=""
while IFS= read -r _fr; do [[ -n "$_fr" ]] && fr_label_join+="${fr_label_join:+・}$(FR="$_fr" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")"; done < <(q '[.test_cases[].trace.verifies[]] | unique | .[]')
fr_join_e="$(esc "$fr_label_join")"
srs_title_e="$(esc "$(q '.cross_doc.srs_title')")"
# ★可視テキスト厳密一致 (marker-keyed・nested-same-tag reject = ds8/B3 不動点)。 各 echo の全タグ除去後の可視テキストが固定テンプレ+id と完全一致を要求。
#   ref-chip = <b> ちょうど 2 本 (srs_doc_id / FR label join)・tc-trace-h と tc-trace-tgt = <b> 無し平文・tc-ref = attr==可視。
tc_echo_bad="$(SRS="$srs_id_e" FRJ="$fr_join_e" TITLE="$srs_title_e" perl -CSD -Mutf8 -0777 -ne '
  my $srs=$ENV{SRS}; utf8::decode($srs); my $frj=$ENV{FRJ}; utf8::decode($frj); my $title=$ENV{TITLE}; utf8::decode($title);
  my @bad;
  # (h) 表紙 cross-doc-ref-chip: <b> ちょうど 2 本 (b1=srs_doc_id / b2=unique FR join)・可視テキスト厳密一致
  #     (先頭 ICO_USER svg は全タグ除去で消えるが直後の半角空白は可視に残る = テンプレ先頭に空白)。
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"ref-chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"ref-chip:".scalar(@bs)."B"; next}
    push @bad,"ref-chip:b1\x{2260}$bs[0]" if $bs[0] ne $srs;
    push @bad,"ref-chip:b2\x{2260}$bs[1]" if $bs[1] ne $frj;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " 検証対象: $srs の要件 $frj";
  }
  # (i) tc-trace-h (各 card・<b> 無し平文): 可視テキスト全体が固定テンプレ (照会先 srs_doc_id を可視補間)
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="tc-trace-h"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"tc-trace-h:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"tc-trace-h:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"tc-trace-h:VIS" if $vis ne "検証する要件と確かめ方 (cross-doc 照会 \x{2192} $srs)";
  }
  # (j) tc-trace-tgt (各 card・<b> 無し平文): 照会先 footnote
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="tc-trace-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"tc-trace-tgt:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"tc-trace-tgt:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"tc-trace-tgt:VIS" if $vis ne "照会先: $srs \x{2014} $title";
  }
  # (k) tc-ref 可視 == data-trace-ref attr (可視 ref だけ改竄し attr 温存を封鎖。 marker-keyed・ref span 内は id のみ = [^<]*)
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="tc-ref"[^>]*\bdata-trace-ref="([^"]*)"[^>]*>([^<]*)<\/\1>/gs) {
    my ($attr,$vis)=($2,$3); push @bad,"tc-ref:$attr\x{2260}$vis" if $vis ne $attr;
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: 可視 echo == テンプレ+id (marker-keyed・swap/平文/nested 封鎖)" "$tc_echo_bad"

# 3b-href. ★cross-doc deep-link 遷移先 fidelity (folio-c5r.9・arch gate 1h 同型)。 tc-ref / rtm-code を <a href> 化した
#   ので、 href 値が contract 派生 <srs_html>#<ref> へ束縛されることを set_eq + 件数で証明する (anchor swap / filename swap /
#   外部 host / デッドリンク / href 欠落〔span 残存〕を fail-closed 封鎖)。 root 平置きゆえ path prefix なし (#<ref>=裸 id・folio-lzz)。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
chk "href: <a class=tc-ref href> 数 == |edges| (span 残存/href 欠落封鎖)" "$NEDGE" "$(grep -oE '<a class="tc-ref" href=' "$BODY" | wc -l | tr -d ' ')"
exp_tcref_href="$(q '.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_tcref_href="$(perl -CSD -0777 -ne 'while (/<a class="tc-ref" href="([^"]*)"\s+data-trace-ref="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: tc-ref (href, ref) == <srs_html>#<ref> (anchor/filename swap 封鎖)" "$exp_tcref_href" "$act_tcref_href"
chk "href: <a class=rtm-code href> 数 == |edges| (RTM href 欠落封鎖)" "$NEDGE" "$(grep -oE '<a class="rtm-code" href=' "$BODY" | wc -l | tr -d ' ')"
rtmcode_href_bad="$(SRS="$SRS_HTML_E" perl -CSD -Mutf8 -0777 -ne 'my $s=$ENV{SRS}; utf8::decode($s); my @bad; while (/<a class="rtm-code" href="([^"]*)">([^<]*)<\/a>/g){ push @bad,"$1\x{2260}$2" if $1 ne "$s#$2"; } print join(" ",@bad);' "$BODY")"
chk_empty "href: rtm-code href == <srs_html>#<code> (可視コード==飛び先 anchor)" "$rtmcode_href_bad"

# 3c. ★三段 trace の within-doc RTM fidelity: (tc,kind,FR-codes,AC-codes) を *emission 順* で contract へ pin。
#   RTM の FR/AC セルは code バッジ (<b class="rtm-code">) + SRS 由来 label を併記する構造ゆえ、 セル内の rtm-code 値のみを
#   行スコープで抽出して join し contract の verifies/confirms join と突合する (label の fidelity は §3e が別途・data-label-ref で担う)。
#   要件→受入→テストの対応の *code* 改竄 (count anchor は card 側) をここで封鎖。
exp_rtm="$(q '.test_cases[] | [.id, .kind, (.trace.verifies | join("・")), (.trace.confirms | join("・"))] | @tsv' | while IFS=$'\t' read -r a b c d; do printf '%s\t%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")" "$(esc "$d")"; done)"
act_rtm="$(perl -CSD -0777 -ne '
  while (/<tr[^>]*\bdata-component="rtm-row"[^>]*>(.*?)<\/tr>/gs) {
    my $row=$1;
    my ($tc)   = $row =~ /<td class="rtm-tc">([^<]*)<\/td>/;
    my ($kind) = $row =~ /<td class="rtm-kind">([^<]*)<\/td>/;
    my ($frc)  = $row =~ /<td class="rtm-fr">(.*?)<\/td>/s;
    my ($acc)  = $row =~ /<td class="rtm-ac">(.*?)<\/td>/s;
    my @fr = (defined $frc) ? ($frc =~ /<a class="rtm-code"[^>]*>([^<]*)<\/a>/g) : ();
    my @ac = (defined $acc) ? ($acc =~ /<a class="rtm-code"[^>]*>([^<]*)<\/a>/g) : ();
    print join("\t", ($tc//""), ($kind//""), join("\x{30FB}",@fr), join("\x{30FB}",@ac)), "\n";
  }' "$BODY")"
set_eq "RTM 行 (tc,kind,FR-codes,AC-codes) == contract (順序)" "$exp_rtm" "$act_rtm"

# 3d. ★★per-card 三段 trace pin (card-keyed cross-doc edge fidelity)。
#   3 (verify_cross_doc_refs) は edge を *全 card 横断* の key SET / (key,role) ペア SET / count でしか見ず、
#   RTM (3c) も別 emission ゆえ、 card 間で FR/AC を入れ替える (TC1↔TC8 の FR・TC4↔TC5 の AC、 RTM 無改竄) と
#   global set・count・(key,role) ペア・RTM が全て不変のまま、 可視 trace chip と RTM が内部矛盾する文書が floor を
#   素通る fail-open があった (兄弟 ADR-pack の (opt-id,verdict) card 束縛 = verify-adr.sh:186-189 に対する欠落回帰)。
#   ここで各 testcase-card (id=tc-TCx) スコープ内の (data-trace-ref, data-trace-role) を tc-id へ束ねた三つ組
#   集合を contract (.test_cases[id].trace.{verifies→claim / confirms→verification}) と *集合一致* で突合し、
#   「どの card がどの FR/AC を持つか」を pin する (card-to-card relocation を封鎖)。 ★assembler は無改変
#   (card は既に id="tc-TCx" + per-card data-trace-ref/role を emit 済 = card 開始タグ id から再導出して照合)。
exp_cardtrace="$(q '.test_cases[] | .id as $id | ((.trace.verifies[] | [$id, ., "claim"]), (.trace.confirms[] | [$id, ., "verification"])) | @tsv' \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$(esc "$b")" "$(esc "$c")"; done | LC_ALL=C sort)"
# marker-keyed: 各 card block は次の testcase-card マーカー (無ければ EOF) まで。 trace ref/role は card 内のみ出現する
#   (RTM td / cover ref-chip は data-trace-ref を持たない) ゆえ card 境界跨ぎの誤収集は起きない。
act_cardtrace="$(perl -CSD -0777 -ne '
  while (/<div data-component="testcase-card" id="tc-([^"]+)">(.*?)(?=<div data-component="testcase-card"|$)/gs) {
    my ($id,$blk)=($1,$2);
    while ($blk=~/\bdata-trace-ref="([^"]*)"\s+data-trace-role="([^"]*)"/gs) { print "$id\t$1\t$2\n"; }
  }' "$BODY" | LC_ALL=C sort)"
set_eq "per-card trace 三つ組 (tc-id, FR/AC, role) == contract (card-keyed)" "$exp_cardtrace" "$act_cardtrace"

# 3e. ★FR/AC 平易ラベル併記の fidelity (persona ceiling BLOCKER 是正)。 card trace 行・RTM・cover の裸 FR/AC コードに
#   SRS 由来の機能名/合格条件を併記する (data-label-ref="<ref>"・FR=requirements[].label / AC=acceptance[].criterion)。
#   ★fabrication-free: 表示ラベルは SRS から *決定的に* 引いた値のみ許可。 (ref, 可視ラベル) ペア集合が SRS 由来の
#   期待集合と *厳密一致* (捏造ラベル・ref↔label swap・非 SRS 由来ラベルを封鎖)。 SRS contract は read-only (無編集)。
#   照会先実在・FR/AC 実在は §3 (verify_cross_doc_refs) が保証済ゆえ、 期待 label は欠落なし。 cover ref-chip b2 は
#   FR label join として §3b が別途突合 (こちらは per-ref data-label-ref 要素)。
chk "tc-ref-label 数 == |edges| (card 各 trace edge にラベル)" "$NEDGE" "$(grep -o 'class="tc-ref-label"' "$BODY" | wc -l | tr -d ' ')"
chk "rtm-label 数 == |edges| (RTM 各 FR/AC にラベル)"          "$NEDGE" "$(grep -o 'class="rtm-label"' "$BODY" | wc -l | tr -d ' ')"
chk "data-label-ref 総数 == 2×|edges| (card + RTM)"           "$((NEDGE*2))" "$(grep -o 'data-label-ref=' "$BODY" | wc -l | tr -d ' ')"
exp_labels="$( {
  q '[.test_cases[].trace.verifies[]] | unique | .[]' | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(FR="$_r" yq -r '.requirements[] | select(.id==strenv(FR)) | .label' "$SRS_ABS")")"; done
  q '[.test_cases[].trace.confirms[]] | unique | .[]' | while IFS= read -r _r; do [[ -n "$_r" ]] && printf '%s\t%s\n' "$(esc "$_r")" "$(esc "$(AC="$_r" yq -r '.acceptance[] | select(.id==strenv(AC)) | .criterion' "$SRS_ABS")")"; done
} | LC_ALL=C sort -u)"
act_labels="$(perl -CSD -0777 -ne 'while (/<span[^>]*\bdata-label-ref="([^"]*)"[^>]*>([^<]*)<\/span>/gs){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "併記ラベル (ref, label) == SRS 由来 (FR=label / AC=criterion)" "$exp_labels" "$act_labels"

# 4. ★各 card の可視テキスト fidelity (emission 順)。 属性 intact のまま可視文字だけ改竄・捏造手順を封鎖。
# 4a. tc-id (label・term-inline なし [^<]*)
set_eq "可視 tc-id == .test_cases[].id (順序)" "$(q '.test_cases[].id')" \
  "$(grep -oE '<span class="tc-id">[^<]*</span>' "$BODY" | sed -E 's#<span class="tc-id">([^<]*)</span>#\1#')"
# 4b. tc-title (h3・term-inline なし [^<]*)
set_eq "可視 tc-title == .test_cases[].title (順序)" "$(qesc '.test_cases[].title')" \
  "$(perl -CSD -0777 -ne 'while (/<h3 class="tc-title">([^<]*)<\/h3>/g){ print "$1\n"; }' "$BODY")"
# 4c. tc-kind 可視ラベル (emission 順) + (kind, class) 整合 (class は normal/abnormal/boundary 派生)
set_eq "可視 tc-kind == .test_cases[].kind (順序)" "$(q '.test_cases[].kind')" \
  "$(grep -oE '<span class="tc-kind [a-z]+">[^<]*</span>' "$BODY" | sed -E 's#<span class="tc-kind [a-z]+">([^<]*)</span>#\1#')"
exp_kc="$(printf '正常系\tnormal\n異常系\tabnormal\n境界値\tboundary\n' | LC_ALL=C sort)"
act_kc="$(grep -oE '<span class="tc-kind [a-z]+">[^<]*</span>' "$BODY" | sed -E 's#<span class="tc-kind ([a-z]+)">([^<]*)</span>#\2\t\1#' | LC_ALL=C sort -u)"
chk_empty "tc-kind バッジの可視ラベルが class と整合" "$(LC_ALL=C comm -13 <(printf '%s\n' "$exp_kc") <(printf '%s\n' "$act_kc") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
# 4d. tc-prio: class (emission 順 == contract priority) + (class, 可視ラベル) 整合 (must→必須 / should→推奨)
set_eq "可視 tc-prio class == .test_cases[].priority (順序)" "$(q '.test_cases[].priority')" \
  "$(grep -oE '<span class="tc-prio [a-z]+">' "$BODY" | sed -E 's#<span class="tc-prio ([a-z]+)">#\1#')"
exp_pl="$(printf 'must\t必須\nshould\t推奨\n' | LC_ALL=C sort)"
act_pl="$(grep -oE '<span class="tc-prio [a-z]+">[^<]*</span>' "$BODY" | sed -E 's#<span class="tc-prio ([a-z]+)">([^<]*)</span>#\1\t\2#' | LC_ALL=C sort -u)"
chk_empty "tc-prio バッジの可視ラベルが priority と整合" "$(LC_ALL=C comm -13 <(printf '%s\n' "$exp_pl") <(printf '%s\n' "$act_pl") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
# 4e. precondition (前提)・expected (期待結果): term-inline バッジを除去した可視テキストが esc 済 contract と一致 (順序)。
#   strip = mark_terms が挿入する <span class="term" data-component="plain-language-term-inline" ...>plain</span> を除去 → 元の esc 済テキストに戻る。
# strip = mark_terms が挿入する term バッジ span を *$t に対して* 除去 (★$t=~ を付けないと素の s/// が $_=slurp 全体を破壊し while の pos() を壊す)。
strip_marks='$t=~s{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g'
# ★perl 正規表現に日本語リテラル (前提/期待結果) を含むため -Mutf8 必須 (-CSD で decode された $_ と byte リテラルの照合不整合を回避)。
set_eq "可視 precondition (前提) == contract (順序)" "$(qesc '.test_cases[].precondition')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<div class="tc-step tc-pre"><span class="tc-step-k">前提<\/span><span class="tc-step-v">(.*?)<\/span><\/div>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
set_eq "可視 expected (期待結果) == contract (順序)" "$(qesc '.test_cases[].expected')" \
  "$(perl -CSD -Mutf8 -0777 -ne 'while (/<div class="tc-step tc-exp"><span class="tc-step-k">期待結果<\/span><span class="tc-step-v">(.*?)<\/span><\/div>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; }' "$BODY")"
# 4f. steps (操作・list): tc-step-list 内の各 <li> を term-inline 除去して可視テキスト == 全 test_cases の steps[] flatten (順序)
set_eq "可視 steps (操作) == contract (順序)" "$(qesc '.test_cases[].steps[]')" \
  "$(perl -CSD -0777 -ne 'while (/<ol class="tc-step-list">(.*?)<\/ol>/gs){ my $b=$1; while ($b=~/<li>(.*?)<\/li>/gs){ my $t=$1; '"$strip_marks"'; $t=~s/[\t\n]/ /g; print "$t\n"; } }' "$BODY")"

# 5. cover-meta KV (種別/件数/検証対象/版) の決定的再導出突合 (ADR cover-meta と同型・fabrication-free)
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 種別 == test-cases ラベル"   "test-cases (テストケース仕様)" "$(printf '%s\n' "$meta_kv" | grep -F '種別' | head -1 | cut -f2)"
chk "cover-meta 件数 == |test_cases|+範囲"    "$(esc "${NTC}件 ($(q '.test_cases[0].id')–$(q '.test_cases[-1].id'))")" "$(printf '%s\n' "$meta_kv" | grep -F '件数' | head -1 | cut -f2)"
chk "cover-meta 検証対象 == srs_doc_id"       "$srs_id_e" "$(printf '%s\n' "$meta_kv" | grep -F '検証対象' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"             "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"                "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# 6. escape 健全性
chk "化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"          "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 7. prose スロット mode (pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)
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

# 8. plain-language-term-inline fidelity + 用語被覆 (assemble-testcases と同一語境界規律)。
#    markable フィールド集合は test-cases-pack 固有ゆえここで yq 式を渡す
#    (★この yq リストは assemble-testcases の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.test_cases[].precondition, .test_cases[].steps[], .test_cases[].expected' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 三段 trace + cross-doc 照会解決 + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
