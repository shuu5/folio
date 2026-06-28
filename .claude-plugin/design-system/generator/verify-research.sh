#!/usr/bin/env bash
# folio engine B3 (folio-ar1) — research-pack fabrication-free + cross-doc 前方照会 proof (instance#3)
#
# 生成 research HTML の *構造* が入力 research contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS-pack) / verify-adr.sh (ADR-pack) と同型の規律を research-pack schema へ適用:
#   - 行数 (findings / approaches / open_questions / glossary / approval / 単一章ブロック) が contract 要素数と一致。
#   - id 一意性 (findings / approaches / open_questions)。
#   - ★cross-doc 前方照会 (本 pack の核): approaches[].leads_to が
#       (a) HTML の data-leads-to 集合と *集合一致* (捏造 0 + 脱落 0) + count anchor で |approaches| と一致
#           (set_eq は sort -u で重複を潰すため、 既存 edge の重複注入は count とペアにして捕捉)、
#       (b) 参照先 ADR contract の .options[].id に *実在* (dangling 照会 0)、
#       (c) cross_doc.adr_doc_id == ADR contract .meta.doc_id かつ outcome.resolved_by == cross_doc.adr_doc_id、
#       (d) data-leads-role が抽象ロール allowlist 内 (claim/rationale/exploration/principle/verification/implementation)、
#       (d') (leads_to,role) ペア集合が contract と *集合一致* (allowlist 内別 role への改竄 = 照会 graph 意味偽装を捕捉)、
#       (e') (ap-id,leads_to) ペア集合が contract と *集合一致* (どの方式がどの option へ繋がるかの edge 付け替え偽装を捕捉)。
#   - outcome 整合 (HTML data-resolved-by == contract .outcome.resolved_by)。
#   - research_status allowlist (open/concluded) の再導出。
#   - escape 健全性 (<lt; 等の化け 0 / >null< 漏れ 0)。
#   - prose スロット: 既定=全空 (pre-fill) / --filled <manifest>=全充填 + 注入忠実 / --artifact=全充填のみ。
#   - term-inline (plain-language-term-inline) の fidelity + 用語被覆 (assemble-research と同一語境界規律)。
#
# usage: verify-research.sh [--filled <manifest.yaml> | --artifact] <research-contract.yaml> <generated.html>
# exit:  0 = PASS / 1 = FAIL / 2 = tool error
#
# ★cross-doc 解決ブロック (SRS_REL/dangling/count/set_eq) は pack-local。 ADR の justifies 解決と同型 = 3 度目の重複。
#   lib/ には上げない (本 issue は core 不変が合格条件)。 core 昇格候補は bd notes へ記録 (実装は別 issue)。
#
# ★★floor / ceiling 境界 (two-gate モデル・S5.1)。 本 floor が担うのは *構造アンカー* の contract 突合:
#   id / 件数 / cross-doc 参照 / 集合 / 完全決定的ブロック (cross-doc echo・cover-meta) の可視テキスト厳密一致。
#   これらは決定的 assembler が出力を間違えれば必ず捕捉する (assembler バグ検出 = floor の責務)。
#   一方 *自由文を含む領域の可視内容 fidelity* (findings.detail / approaches.summary・assessment / outcome.note /
#   prose スロット) は floor の対象外 = ceiling (fidelity-research 相当 agent・読書 persona-walk) の責務。
#   後者の領域への生成後 HTML 改竄 (タグ/平文で偽情報を注入) は決定的 assembler が *到達しない状態* であり、
#   その内容真正性は ceiling が担保する。 floor 単独で GREEN にはならず CEILING=PENDING (taxonomy §5.1)。
#   research-pack 専用 ceiling agent の制度化は follow-up (ADR の folio-a3k と同型)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-research.sh [--filled <manifest> | --artifact] <research-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-research.sh [--filled <manifest> | --artifact] <research-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-research: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-research: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-research: yq required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-48s ----
# 新依存 lib/verify-common.sh を fail-closed guard する (欠落/source 失敗を false-green に倒さない)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-research: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=48; source "$LVC" || { echo "verify-research: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"      # body-only ($BODY、 inline CSS の data-component 混入回避)

echo "research-pack fabrication-free + cross-doc 前方照会 proof: $HTML"
echo "  contract: $CONTRACT"

# 0. ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 ceiling の container blocker (scope-panel 3rd column / finding-list 偽 row /
#   question-panel 偽 p) は全て *非 canonical な class/data-component* (scol2/bull/zq/research-finding-row-x) を container へ注入し token/tag-keyed の
#   個別 census を素通った (独立 ceiling 実証・blocker)。 srs の class-token 機械的網羅 idiom を移植: 全 class token・全 data-component が
#   allowlist に属することを quote-robust に強制 = novel-marker 注入 (container 階層 arbitrary-wrapper fabrication) を一網打尽に封鎖する根治。
RESEARCH_CLS="ak ap-assess ap-grid ap-head ap-id ap-name ap-plain ap-sum b chapbody cover-eyebrow cover-meta cover-sub doc-type en fnbody fnd fnh fnid foot ft-grid gdef grow gword ic ico in k kicker lab lead m num oc-kick oc-note oc-plain oc-resolved oc-tgt oqid oq-list oqt out page q-kick q-text reader-chip role scol self sign stamp summary-card tags term tint-brand tint-info tint-ok tint-violet tint-warn txt v when who xref-doc"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RESEARCH_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker container 注入封鎖・folio-bur r6)" "$unknown_cls"
RESEARCH_DC="approval-block chapter-deck-band cross-doc-leads-chip cross-doc-ref-chip doc-cover-band fidelity-sync-meta glossary-term-table plain-language-term-inline requirement-type-color-tokens research-approach-card research-finding-list research-finding-row research-open-question research-outcome-panel research-question-panel scope-summary-panel"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $RESEARCH_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel data-component 注入封鎖・folio-bur r6)" "$unknown_dc"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "finding rows == |findings|"          "$(q '.findings | length')"        "$(grep -c 'data-component="research-finding-row"' "$BODY")"
chk "approach cards == |approaches|"       "$(q '.approaches | length')"      "$(grep -c 'data-component="research-approach-card"' "$BODY")"
chk "leads chips == |approaches|"          "$(q '.approaches | length')"      "$(grep -c 'data-component="cross-doc-leads-chip"' "$BODY")"
chk "open-questions == |open_questions|"   "$(q '.open_questions | length')"  "$(grep -c 'data-component="research-open-question"' "$BODY")"
chk "question panel == 1"                  "1"                                "$(grep -c 'data-component="research-question-panel"' "$BODY")"
chk "scope panel == 1"                     "1"                                "$(grep -c 'data-component="scope-summary-panel"' "$BODY")"
# scope 項目 (in_scope + out_scope の <li>) も決定的 emit リスト = 件数突合 (round-5 ceiling: 唯一カウント漏れだった)。
chk "scope items == |in_scope|+|out_scope|" "$(( $(q '.question.in_scope | length') + $(q '.question.out_scope | length') ))" "$(grep -c '<li><span class="b">' "$BODY")"
chk "outcome panel == 1"                   "1"                                "$(grep -c 'data-component="research-outcome-panel"' "$BODY")"
chk "glossary == |glossary|"               "$(q '.glossary | length')"        "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"               "$(q '.approval | length')"        "$(grep -c 'class="sign"' "$BODY")"
# 1b. ★core 共通 chrome (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary term/en/def) の
#     値突合 + 占有数パリティ (folio-mk9・verify_core_chrome)。 件数のみ検証 (値改竄が素通る fail-open) を全 pack 共通で塞ぐ。
verify_core_chrome
# 1b'. ★research-pack reader-chip 占有数 (folio-mk9 self-review round-6): reader-chip class を持つ要素は genuine reader-chip 1 個
#   + cross-doc-ref-chip 1 個 = ちょうど 2 個。 SRS と非対称に ADR/research は reader-chip 総数を quote-robust に bind していなかった
#   ため、 single-quote/unquoted/entity の data-component を持つ偽 ref-chip decoy や 属性値内 > で count_genuine を断片化した
#   genuine-style decoy が素通った。 count_attr_token (quote/case/entity/>-attr 非依存の全文走査) で reader-chip 総数 == 2 を bind し封鎖 (SRS §7b'' と対称)。
chk "core-chrome(research): reader-chip class 総数 == 2 (genuine 1 + cross-doc-ref-chip 1)" "2" "$(count_attr_token class reader-chip < "$BODY")"

# 2. id 一意性
chk_empty "finding id 一意"        "$(q '.findings[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "approach id 一意"       "$(q '.approaches[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "open-question id 一意"  "$(q '.open_questions[].id' | sort | uniq -d | tr '\n' ' ')"
# research_status allowlist 再導出
chk_empty "research_status allowlist {open,concluded}" "$(q '.meta.research_status' | grep -vxE 'open|concluded' | tr '\n' ' ')"

# 3. ★cross-doc 前方照会 (本 pack の核 = research → ADR)
ADR_REL="$(q '.cross_doc.adr_contract')"; ADR_ABS="${CONTRACT_DIR}/${ADR_REL}"
# 共通スケルトン (照会先実在/doc_id/count/SET/dangling/★空値ガード/role allowlist/(key,role)ペア) は ds8 で core 昇格。
# expr は逐語で渡す (合成しない = 非破壊の証明を直截に保つ。 研究 49/49 緑が「昇格でスケルトンが弱化していない」一次証拠)。
verify_cross_doc_refs \
  --label-prefix "cross-doc" --target-label "ADR" \
  --target-abs "$ADR_ABS" --target-rel "$ADR_REL" \
  --key-attr "data-leads-to" --role-attr "data-leads-role" \
  --keys-expr '.approaches[].leads_to' \
  --count-expr '.approaches | length' \
  --nonempty-count-expr '[.approaches[] | select((.leads_to // "") != "")] | length' \
  --pair-expr '.approaches[] | [.leads_to, .role] | @tsv' \
  --target-ids-expr '.options[].id' \
  --contract-docid-expr '.cross_doc.adr_doc_id' \
  --target-docid-expr '.meta.doc_id'
# ↓ ここから research-pack 固有 (core に上げない)。 いずれも research contract/BODY のみ参照ゆえ照会先不在でも
#   安全に走る (上の helper が不在を FAIL 済 → overall FAIL は保存される)。
# outcome.resolved_by == adr_doc_id (照会終端側の整合・research 固有)
chk "cross-doc: outcome.resolved_by == adr_doc_id" "$(q '.cross_doc.adr_doc_id')" "$(q '.outcome.resolved_by')"
# (e') ★(ap-id,leads_to) ペア一致: どの方式がどの option へ繋がるかの edge 付け替え偽装を捕捉
#      (leads_to 集合保存型の付け替え = 集合 + count では素通り = fail-open。 id↔leads_to ペア突合で捕捉)。
exp_al="$(q '.approaches[] | [.id, .leads_to] | @tsv' | sort -u)"
act_al="$(grep -oE 'data-ap-id="[^"]+" data-leads-to="[^"]+"' "$BODY" \
  | sed -E 's/data-ap-id="([^"]+)" data-leads-to="([^"]+)"/\1\t\2/' | sort -u)"
set_eq "cross-doc: (ap-id,leads_to) ペア (contract == HTML)" "$exp_al" "$act_al"
# (f') ★可視 id 整合 (堅牢版・round-2 ceiling 反映): チップ内の <b> を *全列挙* し ちょうど 1 本かつ
#      data-leads-to と一致を要求。 first-<b> マッチだと正規 <b> の直後に 2 つ目の偽 <b> を注入する追加方向が
#      素通る (削除方向 R25 の対称兄弟 = round-2 が実証した fail-open)。 @bs 全列挙 + 本数!=1 検出で
#      追加 (>1)・削除 (0)・改竄 (!=期待) の全方向を一つの判定で塞ぐ。
# ★可視テキスト厳密一致 (round-4 ceiling): チップ inner の全タグを除去した *可視テキスト* が
#   固定テンプレ「→ つながる判断 <leads>」と完全一致を要求。 <b> 列挙+残留タグ検査は『タグ無しの平文で
#   偽 id を併記する経路 (つながる判断 OPT1 実は OPT9)』を取り逃す fail-open だった。 可視テキスト全体の
#   厳密一致は タグ併記・平文併記・swap・任意注入 を一括封鎖する *不動点* (チップは固定テンプレで自由文なし)。
lvis_bad="$(perl -CSD -Mutf8 -0777 -ne '
  my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-leads-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$chip,$in)=($1,$&,$2); push @bad,"leads-chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my ($l)=$chip=~/\bdata-leads-to="([^"]*)"/; $l="" unless defined $l;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"$l:".scalar(@bs)."B"; next}
    if ($bs[0] ne $l){push @bad,"$l:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g;
    push @bad,"$l:VIS" if $vis ne "\x{2192} つながる判断 $l";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: チップ可視テキスト == テンプレ+leads (平文/タグ併記封鎖)" "$lvis_bad"

# 4. outcome 整合 (HTML data-resolved-by == contract .outcome.resolved_by = 終端 identity の偽装を捕捉)
act_resolved="$(grep -oE 'data-resolved-by="[^"]+"' "$BODY" | sed 's/.*data-resolved-by="//; s/"$//')"
chk "outcome: HTML resolved-by == contract" "$(esc "$(q '.outcome.resolved_by')")" "$act_resolved"
# ★cross-doc 可視 <b> echo の堅牢検証 (g')(h')(j') — round-2 ceiling 反映 (first-<b> fail-open を全列挙で塞ぐ)。
#   可視 echo ブロックは必ず 1 個 (ブロックごと削除すると while が回らず @bad 空で素通る fail-open を count で塞ぐ)。
chk "outcome oc-resolved ブロック == 1"  "1" "$(grep -c 'class="oc-resolved"' "$BODY")"
chk "cover ref-chip ブロック == 1"       "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "outcome oc-tgt ブロック == 1"       "1" "$(grep -c 'class="oc-tgt"' "$BODY")"

# 4b-href. ★cross-doc deep-link 遷移先 fidelity (folio-c5r.9・Fork B coarse = ADR #decision 着地)。 research の ADR 照会
#   (leads-chip ×|approaches| + 表紙 ref-chip + oc-resolved + oc-tgt = |approaches|+3 本) を <a href> 化したので、
#   全 href が contract 派生 <adr_html>#decision へ束縛されることを件数 + 全件一致で証明 (anchor/filename swap・外部 host・
#   href 欠落封鎖)。 OPT 単位 deep-link は folio-c5r.9 で coarse 採用ゆえ全照会が #decision (ADR の決定パネル) へ着地。
ADR_HTML_E="$(esc "$(q '.cross_doc.adr_html')")"
chk "href: 研究→ADR href 総数 == |approaches|+3 (leads+ref-chip+oc-resolved+oc-tgt)" "$(( $(q '.approaches | length') + 3 ))" "$(grep -oE 'href="[^"]*"' "$BODY" | wc -l | tr -d ' ')"
bad_href="$(ADR="$ADR_HTML_E" perl -CSD -Mutf8 -0777 -ne 'my $a=$ENV{ADR}; utf8::decode($a); my @bad; while (/href="([^"]*)"/g){ push @bad,$1 if $1 ne "$a#decision"; } print join(" ",@bad);' "$BODY")"
chk_empty "href: 全 cross-doc href == <adr_html>#decision (anchor/filename swap・外部 host 封鎖)" "$bad_href"
adr_id_e="$(esc "$(q '.cross_doc.adr_doc_id')")"
# (g') oc-resolved 内 <b> == 各ブロックの data-resolved-by / (h') cover ref-chip 内 <b> == adr_doc_id /
# (j') oc-tgt 内 <b> == adr_doc_id (assemble で <b> 包みに統一)。 いずれも 全<b>列挙 + ちょうど1本 == 期待で
#      追加 (第2 <b> 注入)・削除・改竄・併記の全方向を塞ぐ (round-2: substring/first-match は併記/追加に脆弱)。
# ★可視テキスト厳密一致 (round-4 ceiling + ds8 ceiling round-2 深化): 各 echo ブロックの全タグ除去後の可視テキストが固定テンプレ+id(+title)と完全一致を要求。
#   ★while-regex は marker-keyed (<([A-Za-z][\w-]*)\b ... marker ...>(.*?)</\1>) = marker を担持する任意 wrapper タグ (ハイフン入り含む) を捕捉。
#   tag 固定 (<p>/<div>) や \w+ だと wrapper-tag swap / hyphen タグで while がスキップし可視検査を逃れる fail-open が残っていた (ds8 ceiling)。
#   加えて ★nested-same-tag reject ($in に同名 open タグ <$tag があれば即 FAIL): 非貪欲 (.*?) が内側同名 close で早期終端し捕捉群外へ偽情報を
#   逃がす経路 (空 <div></div> 注入) を構造的に封じる (round-2 ceiling 検出の blocker・B3「不動点」が残した最深の兄弟)。
#   ★floor が封じるのは *決定的 echo 要素自体* の改竄 (swap/別タグ/第2<b>/平文・タグ併記/nested 早期終端/削除・重複)。 echo の *外側* の自由文へ
#   偽 provenance を注入する経路 (marker 無し sibling・自由文中の偽 doc_id 言及) は prose の正当な doc_id 言及と区別不能ゆえ floor 対象外 = ceiling 領域
#   (内容 fidelity・two-gate 境界 S5.1)。 marker-only count anchor (上) と marker-keyed while でパリティを取る。
echo_bad="$(EXP="$adr_id_e" TITLE="$(esc "ADR: $(yq -r '.meta.title' "$ADR_ABS")")" perl -CSD -Mutf8 -0777 -ne '
  my $exp=$ENV{EXP}; utf8::decode($exp); my $title=$ENV{TITLE}; utf8::decode($title); my @bad;
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="oc-resolved"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$blk,$in)=($1,$&,$2); push @bad,"oc-resolved:NESTED" if $in=~/<\Q$tag\E\b/;
    my ($rb)=$blk=~/\bdata-resolved-by="([^"]*)"/; $rb="" unless defined $rb;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"oc-resolved:".scalar(@bs)."B"; next} if($bs[0] ne $rb){push @bad,"oc-resolved:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"oc-resolved:VIS" if $vis ne "この調査は $rb で決着しました";
  }
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"ref-chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"ref-chip:".scalar(@bs)."B"; next} if($bs[0] ne $exp){push @bad,"ref-chip:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " この調査の行き先: $exp \x{2014} $title";
  }
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="oc-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"oc-tgt:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"oc-tgt:".scalar(@bs)."B"; next} if($bs[0] ne $exp){push @bad,"oc-tgt:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"oc-tgt:VIS" if $vis ne "照会先 (前方参照): $exp \x{2014} $title";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc 可視 echo テキスト == テンプレ+id+title (平文/タグ併記封鎖)" "$echo_bad"

# (k') ★within-doc 可視構造 id (round-2/3 ceiling): 可視 <span class="ap-id|fnid|oqid"> を *文書順* で抽出し
#      contract id 列と順序付き一致を要求。 assembler は contract 順に emit する (mapfile/while) ため順序比較は
#      (i) 多重度保存 swap (round-3 #3)、 (ii) 属性付き偽 span の余分追加 (round-3 #2)、 (iii) 置換/欠落 を一括捕捉。
#      class 値は完全境界 (class="ap-id" の直後 ")・属性は許容 ([^>]*) して属性付き偽 span も actual に取り込む。
chk "within-doc: 可視 ap-id 列 == .approaches[].id (順序)" \
  "$(q '.approaches[].id')" \
  "$(grep -oE '<span class="ap-id"[^>]*>[^<]*</span>' "$BODY" | sed -E 's#<span class="ap-id"[^>]*>([^<]*)</span>#\1#')"
chk "within-doc: 可視 fnid 列 == .findings[].id (順序)" \
  "$(q '.findings[].id')" \
  "$(grep -oE '<span class="fnid"[^>]*>[^<]*</span>' "$BODY" | sed -E 's#<span class="fnid"[^>]*>([^<]*)</span>#\1#')"
chk "within-doc: 可視 oqid 列 == .open_questions[].id (順序)" \
  "$(q '.open_questions[].id')" \
  "$(grep -oE '<span class="oqid"[^>]*>[^<]*</span>' "$BODY" | sed -E 's#<span class="oqid"[^>]*>([^<]*)</span>#\1#')"
# (k2) ★id span 直後の隣接構造 (round-4 ceiling): 可視 id span の *直後* に既知構造要素が来ることを件数で要求し、
#      id span と隣接要素の間に平文偽 id を後置注入する経路 (<span class="ap-id">AP1</span> AP99<span class=ap-name>) を捕捉。
chk "within-doc: ap-id→ap-name 隣接 == |approaches|" "$(q '.approaches | length')" "$(grep -oE '<span class="ap-id">[^<]*</span><span class="ap-name">' "$BODY" | wc -l | tr -d ' ')"
chk "within-doc: fnid→fnbody 隣接 == |findings|"     "$(q '.findings | length')"   "$(grep -oE '<span class="fnid">[^<]*</span><div class="fnbody">' "$BODY" | wc -l | tr -d ' ')"
chk "within-doc: oqid→oqt 隣接 == |open_questions|"  "$(q '.open_questions | length')" "$(grep -oE '<span class="oqid">[^<]*</span><p class="oqt">' "$BODY" | wc -l | tr -d ' ')"

# (k3) ★folio-bur: 可視本文 echo の fidelity (id/件数は pin 済だが ap-name/fnh/oqt/q-text/scope 本文が *未 pin*)。
#   id intact のまま本文を捏造でき読者が別の調査結果/問い/範囲を読む fail-open が残った (folio-bur audit 実証の 5 穴)。
#   ap-name/scope は term-inline span を含みうるため body から除去した BODY_NM で抽出 (nested 早期終端回避)。findings[].detail は ceiling 据置。
BODY_NM="$(perl -CSD -0777 -pe 's{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g' "$BODY")"
chk "within-doc: 可視 q-text == .question.summary" "$(esc "$(q '.question.summary')")" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="q-text">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t"}')"
chk "within-doc: 可視 fnh == .findings[].summary (順序)" "$(qesc '.findings[].summary')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="fnh">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
chk "within-doc: 可視 ap-name == .approaches[].name (順序)" "$(qesc '.approaches[].name')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<span class="ap-name">([^<]*)<\/span>/gs){print "$1\n"}')"
chk "within-doc: 可視 oqt == .open_questions[].text (順序)" "$(qesc '.open_questions[].text')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="oqt">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
chk "within-doc: 可視 scope li 本文 == .question.in_scope[]+out_scope[] (順序)" "$(qesc '.question.in_scope[], .question.out_scope[]')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<li><span class="b">\xe2\x97\x8f<\/span>(.*?)<\/li>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
# ★folio-bur round-2 (ceiling-recursion 是正): 上の可視本文 chk は double-quote 固定 grep ゆえ single-quote/unquoted の additive
#   decoy (genuine intact で偽要素を足す) を見逃す (独立 ceiling 実証)。 dty 不動点 = quote-robust 占有数パリティ。 各 echo class の
#   占有数 == contract 件数を count_attr_token で pin し、 decoy が必ず占有を +1 する性質で封鎖 (二層目)。
chk "占有: q-text == 1"               "1"                              "$(count_attr_token class q-text < "$BODY")"
chk "占有: fnh == |findings|"         "$(q '.findings | length')"      "$(count_attr_token class fnh < "$BODY")"
chk "占有: ap-name == |approaches|"   "$(q '.approaches | length')"    "$(count_attr_token class ap-name < "$BODY")"
chk "占有: oqt == |open_questions|"   "$(q '.open_questions | length')" "$(count_attr_token class oqt < "$BODY")"
# scope li は class が共有 (b) ゆえ scol in/out ブロック内の <li タグ総数を quote 非依存に数える (既存 L70 grep '<li><span class="b">' は
#   double-quote 固定で single-quote li decoy を見逃す)。 scol ブロックは内側に div を持たぬため (.*?)</div> で正しく境界が取れる。
scope_li_n="$(perl -0777 -ne 'my $n=0; while(/<div class="scol (?:in|out)">(.*?)<\/div>/gs){my $b=$1; $n++ while $b=~/<li\b/g} print $n' "$BODY")"
chk "占有: scol in/out 内 <li> == |in_scope|+|out_scope|" "$(( $(q '.question.in_scope | length') + $(q '.question.out_scope | length') ))" "${scope_li_n:-0}"
# ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 は scol の li を *合計* でしか数えず (L230)、 L219 の可視本文 chk も
#   union を文書順で flat 突合するだけで *列メンバーシップ* を束縛しなかった → scol in/out 境界を動かすと合計 li 数も union 順も
#   不変のまま「調べた範囲」と「調べない範囲」が入れ替わる調査記録最重要セマンティクスの捏造が素通った (独立 ceiling 実証)。
#   各列の li 本文を列ごとに順序突合して membership を束縛 (in→out / out→in の境界移動・列内入替を封鎖)。
chk "within-doc: 可視 scol-in li 本文 == .question.in_scope[] (順序)" "$(qesc '.question.in_scope[]')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<div class="scol in">(.*?)<\/div>/gs){my $blk=$1; while($blk=~/<li><span class="b">\xe2\x97\x8f<\/span>(.*?)<\/li>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}}')"
chk "within-doc: 可視 scol-out li 本文 == .question.out_scope[] (順序)" "$(qesc '.question.out_scope[]')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<div class="scol out">(.*?)<\/div>/gs){my $blk=$1; while($blk=~/<li><span class="b">\xe2\x97\x8f<\/span>(.*?)<\/li>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}}')"
# ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 は scol 内 li 本文を class へ束縛したが reader-facing な *列見出し* (<h3>)
#   を未 pin で、 class (scol in/out) は intact のまま見出しテキストを swap すると『調べた範囲↔調べない範囲』が反転表示される
#   調査記録最重要セマンティクスの捏造が素通った (独立 ceiling 実証・blocker)。 spec の STATIC_BAND_H2 と同型に列見出しを静的リテラルで pin。
chk "within-doc: scol-in 見出し == '✓ 調べる範囲' (調査範囲ラベル反転封鎖・folio-bur r4)" "✓ 調べる範囲" "$(perl -0777 -ne 'if(/<div class="scol in"><h3[^>]*>([^<]*)<\/h3>/s){print $1}' "$BODY")"
chk "within-doc: scol-out 見出し == '⚖ 調べない範囲' (同上)" "⚖ 調べない範囲" "$(perl -0777 -ne 'if(/<div class="scol out"><h3[^>]*>([^<]*)<\/h3>/s){print $1}' "$BODY")"
# ★folio-bur round-4: round-3 の scol-内 占有 (L230) と round-2 の L70 (double-quote grep) は scol *外* (panel 内/任意位置) の
#   single-quote bullet decoy を見逃した → 大域 quote-robust census: class=b (scope bullet) 総数 == |in|+|out| で封鎖。
chk "占有: class=b (scope bullet) == |in_scope|+|out_scope| (quote-robust・scol外/single-quote decoy 封鎖・folio-bur r4)" "$(( $(q '.question.in_scope | length') + $(q '.question.out_scope | length') ))" "$(count_attr_token class b < "$BODY")"
# ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 までの scope 検査は census が class=b トークン + <li タグに keyed・
#   見出し pin が if-first-match・scol ブロック占有 anchor 不在で、 (#9) <div class="zz"><span class="bb">●</span>捏造</div> が
#   非li/非b/●glyph で全 proxy 素通り緑 in-scope box に捏造 scope 項目 (#10) 第2 <div class="scol in"> 列丸ごと無検査、 で素通った
#   (独立 ceiling 実証・blocker・new-category)。 token/tag-keyed census は arbitrary-wrapper 可視捏造を原理的に縛れない →
#   region-text reconciliation: 各 scol ブロックの *全可視テキスト* (BODY_NM・タグ/空白除去) == 見出し+全 bullet と完全突合 +
#   nested-<div> reject (canonical block は nested div を持たぬ・baseline 0) + scol ブロック占有 (count_attr_token class scol=2) で機械的完全化。
chk "占有: class=scol == 2 (scol ブロック追加 quote-robust 封鎖・folio-bur r5)" "2" "$(count_attr_token class scol < "$BODY")"
exp_scolin="✓ 調べる範囲"; while IFS= read -r _b; do exp_scolin+="●$(esc "$_b")"; done < <(q '.question.in_scope[]')
exp_scolout="⚖ 調べない範囲"; while IFS= read -r _b; do exp_scolout+="●$(esc "$_b")"; done < <(q '.question.out_scope[]')
scol_recon_bad="$(printf '%s' "$BODY_NM" | EXPIN="$exp_scolin" EXPOUT="$exp_scolout" perl -CSD -Mutf8 -0777 -ne '
  my $ei=$ENV{EXPIN}; utf8::decode($ei); $ei=~s/\s+//g; my $eo=$ENV{EXPOUT}; utf8::decode($eo); $eo=~s/\s+//g;
  my @bad; my ($nin,$nout)=(0,0);
  while (/<div class="scol in">(.*?)<\/div>/gs){ my $c=$1; $nin++; push @bad,"in:NESTED-DIV" if $c=~/<div\b/i; my $v=$c; $v=~s/<[^>]+>//g; $v=~s/\s+//g; push @bad,"in:TEXT\x{2260}".substr($v,0,30) if $v ne $ei; }
  while (/<div class="scol out">(.*?)<\/div>/gs){ my $c=$1; $nout++; push @bad,"out:NESTED-DIV" if $c=~/<div\b/i; my $v=$c; $v=~s/<[^>]+>//g; $v=~s/\s+//g; push @bad,"out:TEXT\x{2260}".substr($v,0,30) if $v ne $eo; }
  push @bad,"in:N=$nin" if $nin!=1; push @bad,"out:N=$nout" if $nout!=1;
  print join(" ",@bad);')"
chk_empty "scol region-text == 見出し+全bullet (非li/非b/arbitrary-wrapper 可視捏造・第2列・nested-div 封鎖・folio-bur r5)" "$scol_recon_bad"

# (l') ★表紙 cover-meta 集計の決定的再導出 (round-2/4 ceiling): 件数+範囲+状態が contract から導いた値と一致。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
exp_app_meta="$(q '.approaches | length')件 ($(esc "$(q '.approaches[0].id')")–$(esc "$(q '.approaches[-1].id')"))"
chk "cover-meta 検討した方式 == |approaches|+範囲" "$exp_app_meta" "$(printf '%s\n' "$meta_kv" | grep -F '検討した方式' | head -1 | cut -f2)"
chk "cover-meta わかったこと == |findings|件" "$(q '.findings | length')件" "$(printf '%s\n' "$meta_kv" | grep -F 'わかったこと' | head -1 | cut -f2)"
# 状態バッジ = research_status の allowlist 写像 (assemble の RSTATUS_LABEL と同一・detect↔remediate parity)。
rstat_raw="$(q '.meta.research_status')"; case "$rstat_raw" in open) exp_rstat="調査中";; concluded) exp_rstat="決着済";; *) exp_rstat="$rstat_raw";; esac
chk "cover-meta 状態 == research_status ラベル" "$exp_rstat" "$(printf '%s\n' "$meta_kv" | grep -F '状態' | head -1 | cut -f2)"
# 版 KV も決定的 emit (version/date) = 再導出突合 (round-5 ceiling: 兄弟 KV だけ突合され版が非対称に漏れていた)。
chk "cover-meta 版 == vX / date" "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
# cover-meta KV 基数アンカー: 4 KV ちょうど (状態/検討した方式/わかったこと/版)。 head -1 単一ペア依存だと重複 KV 後置注入が
#   素通る fail-open を塞ぐ (echo ブロックの ブロック==1 count anchor と対称・round-5 ceiling fix-flaw)。
# ★folio-bur round-3 (ceiling-recursion R2 是正): meta_kv は double-quote 固定 perl ゆえ single-quote/unquoted の KV decoy を
#   数えず、 表紙に矛盾する 2 行 (例「わかったこと 3件」+「わかったこと 99件(捏造)」) が素通った (独立 ceiling 実証)。
#   dty 不動点 = quote-robust count_attr_token で KEY span (class="k") の占有数を数える (decoy は quote に依らず +1)。
chk "cover-meta KV 総数 == 4 (quote-robust)" "4" "$(count_attr_token class k < "$BODY")"

# 5. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 6. prose スロット (perl で要素単位判定)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-48s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-48s\n' "prose スロットが無い"; fail=1; fi

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
    printf '  [OK]   %-48s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-48s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# 7. plain-language-term-inline fidelity + 用語被覆 (assemble-research と同一語境界規律)。
#    実装は core (verify-common.sh の verify_term_inline)。 markable フィールド集合は research-pack 固有ゆえ
#    ここで yq 式を渡す (★この yq リストは assemble-research の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.question.summary, .question.in_scope[], .question.out_scope[], .findings[].summary, .findings[].detail, .approaches[].name, .approaches[].summary, .approaches[].assessment, .open_questions[].text, .outcome.note' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"


# ===== folio-bur round-7: occupancy-from-contract 完全性 (真の不動点・membership≠occupancy) =====
# round-6 enumeration は novel marker を封鎖したが、 allowlist *内* の canonical chrome token を借りた
# additive 注入は占有 pin が無ければ素通る (ceiling: membership≠occupancy は直交防御)。 全 allowlist token に
# occupancy pin を付け additive 借用 family を構造封鎖する。 残る count 保存 value-swap は ceiling 領域 (正直な境界)。
# (a) display-state guard: genuine は inline display:none/visibility:hidden/hidden 属性を一切出さない (全 pack baseline=0)。
#     genuine を隠し fake を見せる二重攻撃の隠蔽半分ゆえ不在を要求 (aria-hidden は装飾で genuine も使うため対象外)。
chk_empty "占有(r7): inline display:none/visibility:hidden 不在 (隠蔽攻撃封鎖)" \
  "$(grep -oiE 'style="[^"]*(display[[:space:]]*:[[:space:]]*none|visibility[[:space:]]*:[[:space:]]*hidden)' "$BODY" | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "占有(r7): hidden 属性 不在 (隠蔽攻撃封鎖)" \
  "$(grep -oiE '<[a-z][a-z0-9-]*[^>]*[[:space:]]hidden([[:space:]>=])' "$BODY" | tr '\n' ' ' | sed 's/ *$//')"
# (d) occupancy-from-contract: 各 allowlist token の occupancy == contract 導出個数 (grouped loop)。
EXP="$(q '.approaches | length')"; for t in ak ap-assess ap-head ap-id ap-plain ap-sum; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '.findings | length')"; for t in fnbody fnd fnid; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '.open_questions | length')"; for t in oqid; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '[.approval[] | select(.stamp != "承認済")] | length')"; for t in self; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in ap-grid cover-meta foot ft-grid ic in lab oc-kick oc-note oc-plain oc-resolved oc-tgt oq-list out page q-kick summary-card tags tint-info tint-ok tint-violet tint-warn txt; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=6; for t in chapbody ico kicker lead num; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=4; for t in m v; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=2; for t in tint-brand; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=3; for t in xref-doc; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in approval-block doc-cover-band fidelity-sync-meta glossary-term-table requirement-type-color-tokens research-finding-list research-question-panel scope-summary-panel research-outcome-panel cross-doc-ref-chip; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP=6; for t in chapter-deck-band; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.findings | length')"; for t in research-finding-row; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.approaches | length')"; for t in research-approach-card cross-doc-leads-chip; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.open_questions | length')"; for t in research-open-question; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
# (e) term-inline 占有: bare <span class="term"> 注入を封鎖 (class term == data-component plain-language-term-inline・
#     構造化 badge は verify_term_inline が glossary 突合済)。
chk "占有(r7): term == plain-language-term-inline (bare .term 注入封鎖)" \
  "$(count_attr_token data-component plain-language-term-inline < "$BODY")" "$(count_attr_token class term < "$BODY")"
# ===== folio-bur round-7 ここまで =====

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + cross-doc 前方照会解決 + term-inline + prose 全充填)"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 注入忠実)"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 空)"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
