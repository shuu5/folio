#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack fabrication-free + cross-doc 照会 proof (instance#2)
#
# 生成 ADR HTML の *構造* が入力 ADR contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS-pack) と同型の規律を ADR-pack schema へ適用:
#   - 行数 (context / drivers / options / consequences pos+neg / glossary / approval) が contract 要素数と一致。
#   - id 一意性 (context / drivers / options / consequences)。
#   - ★cross-doc 照会 (本 pack の核): decision.justifies の要件集合が
#       (a) HTML の data-justifies-req 集合と *集合一致* (捏造 0 + 脱落 0) + count anchor で |justifies| と一致
#           (set_eq は sort -u で重複を潰すため、 既存 edge の重複注入は count とペアにして捕捉)、
#       (b) 参照先 SRS contract の要件 ID に *実在* (dangling 照会 0)、
#       (c) cross_doc.srs_doc_id == SRS contract .meta.doc_id、
#       (d) data-justifies-role が抽象ロール allowlist 内 (claim/rationale/exploration/principle/verification/implementation)、
#       (d') (req,role) ペア集合が contract と *集合一致* (allowlist 内別 role への改竄 = 照会 graph 意味偽装を捕捉)。
#   - verdict 整合 (chosen ちょうど 1 + decision.chosen 一致 + (opt-id,verdict) ペアが contract と集合一致
#       = count 保存型のバッジ付け替え〔採用カード偽装〕を捕捉 + (verdict,可視ラベル) 整合
#       = class は正のまま human-visible 文字だけ改竄する偽装を捕捉)。
#   - supersession / principle (emit する終端章の fabrication-free): adr-supersession/adr-principle 各 1 件 +
#       principle.id / supersession.status / supersedes / superseded_by が contract 導出と一致。
#   - escape 健全性 (<lt; 等の化け 0 / >null< 漏れ 0)。
#   - prose スロット: 既定=全空 (pre-fill) / --filled <manifest>=全充填 + 注入忠実 / --artifact=全充填のみ。
#   - term-inline (plain-language-term-inline) の fidelity + 用語被覆 (assemble-adr と同一語境界規律)。
#
# usage: verify-adr.sh [--filled <manifest.yaml> | --artifact] <adr-contract.yaml> <generated.html>
# exit:  0 = PASS / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-adr: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-adr: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-adr: yq required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-48s ----
# 新依存 lib/verify-common.sh を fail-closed guard する (欠落/source 失敗を false-green に倒さない。
# set -e 無しゆえ source rc=1 でも継続し helper が command-not-found 化する)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-adr: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=48; source "$LVC" || { echo "verify-adr: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"      # body-only ($BODY、 inline CSS の data-component 混入回避)
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build adr "$FILLED_MANIFEST"

echo "ADR-pack fabrication-free + cross-doc 照会 proof: $HTML"
echo "  contract: $CONTRACT"
# ★folio-bur round-6 (ceiling-recursion R5 是正・収束根治): srs の class-token 機械的網羅 idiom を移植。 全 class token・全 data-component が
#   allowlist に属することを quote-robust に強制 = container/任意位置への novel-marker (非 canonical class/data-component) 注入を一網打尽に封鎖
#   (research container blocker と同型の系統的 fail-open を未然に塞ぐ・enumeration drift も検出)。
ADR_CLS="b chapbody chosen cons cover-eyebrow cover-meta cover-sub cxbody cxd cxh cxid dec-kick dec-plain dec-state dec-why doc-type drg drid en foot ft-grid ft-plain gdef grow gword ic ico in jh justify-box justify-note justify-req justify-role justify-row justify-tgt k kicker lab lead m num opt-grid opt-head opt-id opt-name opt-pc opt-plain opt-sum opt-verdict out page prin-id prin-note prin-text pros reader-chip rejected role scol self sign ss-k ss-row stamp summary-card tags term tint-brand tint-info tint-ok tint-violet tint-warn txt v when who"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $ADR_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker 注入封鎖・folio-bur r6)" "$unknown_cls"
ADR_DC="adr-consequence-neg adr-consequence-pos adr-context-list adr-context-row adr-decision-panel adr-driver-row adr-driver-table adr-option-card adr-principle adr-supersession approval-block chapter-deck-band cross-doc-ref-chip doc-cover-band fidelity-sync-meta glossary-term-table plain-language-term-inline requirement-type-color-tokens scope-summary-panel"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $ADR_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel data-component 注入封鎖・folio-bur r6)" "$unknown_dc"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "context rows == |context|"           "$(q '.context | length')"                 "$(grep -c 'data-component="adr-context-row"' "$BODY")"
chk "driver rows == |drivers|"            "$(q '.drivers | length')"                 "$(grep -c 'data-component="adr-driver-row"' "$BODY")"
chk "option cards == |options|"          "$(q '.options | length')"                 "$(grep -c 'data-component="adr-option-card"' "$BODY")"
chk "consequence(pos) == |positive|"     "$(q '.consequences.positive | length')"   "$(grep -c 'data-component="adr-consequence-pos"' "$BODY")"
chk "consequence(neg) == |negative|"     "$(q '.consequences.negative | length')"   "$(grep -c 'data-component="adr-consequence-neg"' "$BODY")"
chk "glossary == |glossary|"             "$(q '.glossary | length')"                "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"             "$(q '.approval | length')"                "$(grep -c 'class="sign"' "$BODY")"
# 1b. ★core 共通 chrome (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary term/en/def) の
#     値突合 + 占有数パリティ (folio-mk9・verify_core_chrome)。 件数のみ検証 (値改竄が素通る fail-open) を全 pack 共通で塞ぐ。
verify_core_chrome
# 1b'. ★ADR-pack reader-chip 占有数 (folio-mk9 self-review round-6): reader-chip class を持つ要素は genuine reader-chip 1 個
#   + cross-doc-ref-chip 1 個 = ちょうど 2 個。 SRS と非対称に ADR/research は reader-chip 総数を quote-robust に bind していなかった
#   ため、 (i) single-quote/unquoted/entity の data-component を持つ偽 ref-chip decoy (count_genuine は ref-chip 側へ分類・ref-chip ブロック
#   grep は double-quote 固定で見逃す) や (ii) 属性値内 > で count_genuine の tag-splitter を断片化した genuine-style decoy が素通った。
#   count_attr_token (quote/case/entity/>-attr 非依存の全文走査) で reader-chip class 総数 == 2 を bind し両系統を封鎖する (SRS の §7b'' と対称)。

# 2. id 一意性
chk_empty "context id 一意"     "$(q '.context[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "driver id 一意"      "$(q '.drivers[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "option id 一意"      "$(q '.options[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "consequence id 一意" "$(q '(.consequences.positive + .consequences.negative)[].id' | sort | uniq -d | tr '\n' ' ')"

# 3. ★cross-doc 照会 (本 pack の核)
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
# 共通スケルトン (照会先実在/doc_id/count/SET/dangling/★空値ガード/role allowlist/(key,role)ペア) は ds8 で core 昇格。
# ★空値ガード (key 全件非空) は helper が両 pack へ無料配布する = ADR が従来欠いていた fail-open 穴を ds8 で塞ぐ
#   (empty-value バグは assemble-adr validate でも実在を修正済・本 verify 側は helper が二重に担保)。
verify_cross_doc_refs \
  --label-prefix "cross-doc" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-justifies-req" --role-attr "data-justifies-role" \
  --keys-expr '.decision.justifies[].req' \
  --count-expr '.decision.justifies | length' \
  --nonempty-count-expr '[.decision.justifies[] | select((.req // "") != "")] | length' \
  --pair-expr '.decision.justifies[] | [.req, .role] | @tsv' \
  --target-ids-expr '(.requirements[].id, .nfr[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 3b. ★Part 2b: ADR cross-doc 可視 echo の堅牢検証 (research round-2/4 ceiling template を ADR の 3 可視 echo へ横展開)。
#   非エンジニアが実際に読むのは attr でなく *可視テキスト*。 attr 突合 (上の helper) だけでは可視文字の偽装が素通る fail-open。
#   各 echo ブロックは固定個数 (ブロックごと削除すると while が回らず @bad 空で素通る fail-open を count anchor で塞ぐ)。
# ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 が pros/cons/k/ss-row/ss-k へ展開した count_attr_token 占有 idiom を
#   これら可視 echo の count anchor (double-quote 固定 grep -c) に未展開だったため、 single-quote additive decoy
#   (<p class='dec-kick'>採用 — OPT-EVIL</p> / <p class='jh'>…→SRS-EVIL</p> 等) が二重「採用」見出し・偽 cross-doc 照会を捏造でき
#   素通った (独立 ceiling 実証・dec-kick/jh=blocker)。 全 echo count anchor を quote-robust count_attr_token へ統一 (uniform sweep)。
chk "cross-doc: ref-chip ブロック == 1"          "1" "$(count_attr_token data-component cross-doc-ref-chip < "$BODY")"
chk "cross-doc: justify-tgt ブロック == 1"        "1" "$(count_attr_token class justify-tgt < "$BODY")"
# ★ds8 ceiling: jh 見出し (assemble-adr emit の第4の可視 cross-doc echo・srs_doc_id を可視補間) も突合する。
#   Part 2b が ref-chip/justify-tgt/justify-req の 3 echo のみを列挙し jh を見落としていた = 機械的完全性照合 (全可視 echo の enumeration) の漏れ。
chk "cross-doc: jh 見出しブロック == 1"           "1" "$(count_attr_token class jh < "$BODY")"
chk "cross-doc: justify-req span == |justifies|" "$(q '.decision.justifies | length')" "$(count_attr_token class justify-req < "$BODY")"
# ★ds8 ceiling round-2: dec-kick (採用見出し) は identity echo だが round-1 では未検証 (jh と同型の列挙漏れ)。可視テキストは下の perl で照合・ここで個数固定。
chk "dec-kick ブロック == 1" "1" "$(count_attr_token class dec-kick < "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
srs_join_e="$(esc "$(q '[.decision.justifies[].req] | join("・")')")"
# ★照会チップ title = 「SRS: <参照先 SRS の実 .meta.title>」 live-mirror (folio-c5r.13・手書き srs_title 廃止)。
#   justify-tgt の可視テキストが「照会先: <srs_doc_id> — SRS: <実 title>」と完全一致を要求 = retitle drift を fail-closed 捕捉。
srs_title_e="$(esc "SRS: $(yq -r '.meta.title' "$SRS_ABS")")"
# ★可視テキスト厳密一致 (round-4 不動点 + ds8 ceiling round-2 深化): 各 echo の全タグ除去後の可視テキストが固定テンプレ+id(+title) と完全一致を要求。
#   ★while-regex は *marker-keyed* (<([A-Za-z][\w-]*)\b ... marker ...>(.*?)</\1>) = marker を担持する任意 wrapper タグ (ハイフン入り <my-tag> 含む) を捕捉。
#   tag 固定 (<div>/<p>) や \w+ だと wrapper-tag swap / hyphen タグで while がスキップし可視検査を逃れる fail-open があった (round-2 ceiling)。
#   加えて ★nested-same-tag reject (捕捉内容 $in に同名 open タグ <$tag があれば即 FAIL): 非貪欲 (.*?) が内側同名 close で *早期終端* し
#   捕捉群外へ偽情報を逃がす経路 (空 <div></div> 注入) を構造的に封じる (round-2 ceiling 検出の blocker・B3「不動点」が残した最深の兄弟)。
#   ★floor が封じるのは *決定的 echo 要素自体* の改竄: wrapper-tag swap / 別タグ / 第2<b> / 平文・タグ併記 / nested 早期終端 / ブロック削除・重複 (count anchor)。
#   ★floor の対象外 (= ceiling 領域・two-gate 境界): echo の *外側* の自由文へ偽 provenance を注入する経路 (marker 無し sibling・自由文中の偽 doc_id 言及)。
#   これは prose 中の正当な doc_id 言及 (例 別 ADR への参照 ADR-0041) と構造的に区別できず、 floor で追うと正当 prose を誤 FAIL する = 内容 fidelity ゆえ
#   fidelity ceiling agent / persona-walk が担保 (verify-research.sh の floor/ceiling 注記・two-gate モデル S5.1)。 floor は「決定的構造の改竄検出」に限定する。
#   ref-chip は <b> ちょうど 2 本 (srs_doc_id, join(req,・))・jh と justify-tgt は <b> 無し平文・justify-req は attr==可視・dec-kick は 採用 — chosen。
adr_echo_bad="$(EXP="$srs_id_e" JOIN="$srs_join_e" TITLE="$srs_title_e" CHOSEN="$(esc "$(q '.decision.chosen')")" perl -CSD -Mutf8 -0777 -ne '
  my $exp=$ENV{EXP}; utf8::decode($exp); my $join=$ENV{JOIN}; utf8::decode($join); my $title=$ENV{TITLE}; utf8::decode($title);
  my $chosen=$ENV{CHOSEN}; utf8::decode($chosen);
  my @bad;
  # (h) 表紙 cross-doc-ref-chip: <b> ちょうど 2 本 (b1=srs_doc_id / b2=join(req,・))・可視テキスト厳密一致
  #     (先頭の ICO_USER svg は全タグ除去で消えるが直後の半角空白は可視テキストに残る = テンプレ先頭に空白)。
  while (/<([A-Za-z][\w-]*)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"ref-chip:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"ref-chip:".scalar(@bs)."B"; next}
    push @bad,"ref-chip:b1\x{2260}$bs[0]" if $bs[0] ne $exp;
    push @bad,"ref-chip:b2\x{2260}$bs[1]" if $bs[1] ne $join;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " 正当化する要件: $exp の $join";
  }
  # (i) jh 見出し (ds8 ceiling 是正・第4の可視 cross-doc echo): <b> 無し平文・可視テキスト全体が固定テンプレと一致。
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="jh"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"jh:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"jh:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"jh:VIS" if $vis ne "この判断が正当化する要件 (cross-doc 照会 \x{2192} $exp)";
  }
  # (j) 照会先 footnote justify-tgt: <b> 無し・平文ゆえ可視テキスト全体が固定テンプレと一致
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="justify-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"justify-tgt:NESTED" if $in=~/<\Q$tag\E\b/;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"justify-tgt:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"justify-tgt:VIS" if $vis ne "照会先: $exp \x{2014} $title";
  }
  # (k) within-doc 可視 req == data-justifies-req (attr-vs-visible 厳密一致。 可視 req だけ改竄し attr 温存を封鎖。
  #     marker-keyed: class="justify-req" を担持する任意タグを捕捉・justify-req span 内は req id のみ = [^<]* で安全に抽出)。
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="justify-req"[^>]*\bdata-justifies-req="([^"]*)"[^>]*>([^<]*)<\/\1>/gs) {
    my ($attr,$vis)=($2,$3); push @bad,"justify-req:$attr\x{2260}$vis" if $vis ne $attr;
  }
  # (l) dec-kick 採用見出し (ds8 ceiling round-2 是正・identity echo の列挙漏れ): <b> 無し平文・可視テキスト == 採用 — {chosen}
  while (/<([A-Za-z][\w-]*)\b[^>]*\bclass="dec-kick"[^>]*>(.*?)<\/\1>/gs) {
    my ($tag,$in)=($1,$2); push @bad,"dec-kick:NESTED" if $in=~/<\Q$tag\E\b/;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"dec-kick:VIS" if $vis ne "採用 \x{2014} $chosen";
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: 可視 echo == テンプレ+id(+title)・req attr==可視 (marker-keyed・swap/平文/タグ併記封鎖)" "$adr_echo_bad"

# 3b-href. ★cross-doc deep-link 遷移先 fidelity (folio-c5r.9・arch gate 1h 同型)。 justify-req を <a href> 化したので、
#   href が contract 派生 <srs_html>#<req> へ束縛されることを set_eq + 件数で証明 (anchor swap / filename swap / 外部 host /
#   href 欠落〔span 残存〕を fail-closed 封鎖)。 root 平置きゆえ path prefix なし (#<req>=SRS の裸 id・folio-lzz)。
SRS_HTML_E="$(esc "$(q '.cross_doc.srs_html')")"
chk "href: <a class=justify-req href> 数 == |justifies| (span 残存/href 欠落封鎖)" "$(q '.decision.justifies | length')" "$(grep -oE '<a class="justify-req" href=' "$BODY" | wc -l | tr -d ' ')"
exp_just_href="$(q '.decision.justifies[].req' | while IFS= read -r _r; do [[ -n "$_r" ]] || continue; printf '%s#%s\t%s\n' "$SRS_HTML_E" "$(esc "$_r")" "$(esc "$_r")"; done | LC_ALL=C sort -u)"
act_just_href="$(perl -CSD -0777 -ne 'while (/<a class="justify-req" href="([^"]*)"\s+data-justifies-req="([^"]*)"/g){ print "$1\t$2\n"; }' "$BODY" | LC_ALL=C sort -u)"
LC_ALL=C set_eq "href: justify-req (href, req) == <srs_html>#<req> (anchor/filename swap 封鎖)" "$exp_just_href" "$act_just_href"

# 3c. ★ds8 ceiling round-3: ADR identity echo の parity (research within-doc (k') / cover-meta (l') と対称)。
#   round-2 まで ADR は cxid/drid 可視 id 列・cover-meta を皆無検証で、 可視 id 改竄 (CTX1→CTX-PHANTOM)・cover-meta 改竄が素通る fail-open だった
#   (research は (k')(l') で突合済 = parity gap)。 cxid/drid は plain (esc) ゆえ [^<]* で安全抽出・opt-name は mark_terms で nested ゆえ対象外。
# ★folio-bur round-5 (ceiling-recursion R4 是正): cxid/justify-role は値順突合のみで count anchor が無く、 single-quote additive
#   decoy (<span class='cxid'>CTX-EVIL</span> / <span class='justify-role'>verification</span>) で phantom 文脈 id・偽 cross-doc edge role が
#   素通った (独立 ceiling 実証・major)。 drid と同型に quote-robust 占有数で封鎖 (uniform sweep)。
chk "within-doc: 可視 cxid 列 == .context[].id (順序)" "$(q '.context[].id')" "$(grep -oE '<span class="cxid">[^<]*</span>' "$BODY" | sed -E 's#<span class="cxid">([^<]*)</span>#\1#')"
chk "within-doc: 可視 drid 列 == .drivers[].id (順序)"  "$(q '.drivers[].id')"  "$(grep -oE 'class="drid">[^<]*</td>' "$BODY" | sed -E 's#class="drid">([^<]*)</td>#\1#')"
# ★dty (folio-dty): 可視 drg (driver grounds バッジ) == 非空 .drivers[].grounds (順序)。 round-4 で drid は突合したが
#   grounds (根拠の可視テキスト・grounds 非空時のみ emit) を漏らし、 値改竄が素通る fail-open だった。 drg は esc plain leaf。
# ★folio-bur round-6 (ceiling-recursion R5 是正): drg は値順突合のみで count anchor が無く (兄弟 drid は L223 で占有済の非対称)、
#   driver 本文 td の外へ single-quote drg decoy を注入すると driver-body 検査 (L209) も値順突合も逃れ偽の grounds linkage が素通った
#   (独立 ceiling 実証・major)。 drid と同型に quote-robust 占有で封鎖 (期待=非空 grounds 件数)。
chk "within-doc: 可視 drg 列 == 非空 .drivers[].grounds (順序)" "$(qesc '.drivers[] | select((.grounds // "") != "") | .grounds')" "$(grep -oE '<span class="drg">[^<]*</span>' "$BODY" | sed -E 's#<span class="drg">([^<]*)</span>#\1#')"
# ★ds8 ceiling round-4: 可視 justify-role 列 == .decision.justifies[].role (順序)。 round-2 で可視 req==attr は強制したが role の可視を漏らし、
#   allowlist 内 role の *可視* swap (claim→rationale・attr は正) が素通る fail-open だった (cross-doc edge の可視 fidelity parity 漏れ)。 role は esc plain。
chk "within-doc: 可視 justify-role 列 == .decision.justifies[].role (順序)" "$(q '.decision.justifies[].role')" "$(grep -oE '<span class="justify-role">[^<]*</span>' "$BODY" | sed -E 's#<span class="justify-role">([^<]*)</span>#\1#')"
# ★folio-bur: 可視テキスト echo の fidelity (visible-text-vs-attribute・id/sibling/件数は pin 済だが *可視本文* が未 pin)。
#   id/verdict/件数 intact のまま判断宣言文・原則文・選択肢名/要約・文脈要約・driver/consequence 本文を捏造でき、 読者が
#   別の決定/根拠を読む fail-open が残った (folio-bur audit 実証の 8 穴)。 term-inline span を body から除去した BODY_NM で
#   抽出し、 nested term span の早期終端 (opt-name の対象外化 = round-2 で諦めた箇所) を回避する。
BODY_NM="$(perl -CSD -0777 -pe 's{<span class="term" data-component="plain-language-term-inline"[^>]*>[^<]*</span>}{}g' "$BODY")"
# (a) ★HIGH: decision statement (判断宣言文・ADR で最も load-bearing・dec-kick は pin 済 sibling)。
chk "within-doc: 可視 dec-state == .decision.statement" "$(esc "$(q '.decision.statement')")" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="dec-state">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t"}')"
# (b) option name ((opt-id,verdict) ペア pin の姉妹として (opt-id,opt-name) を順序突合・term-strip 済ゆえ [^<]* 安全)。
chk "within-doc: 可視 (opt-id,opt-name) == .options[] [id,name] (順序)" "$(q '.options[]|[.id,.name]|@tsv' | while IFS=$'\t' read -r a b; do printf '%s\t%s\n' "$a" "$(esc "$b")"; done)" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<span class="opt-id">([^<]+)<\/span><span class="opt-name">([^<]*)<\/span>/gs){print "$1\t$2\n"}')"
# (c) principle text (照会グラフ終端・prin-id は pin 済 sibling・silent 改竄封鎖の重要度高)。
chk "within-doc: 可視 prin-text == .principle.text" "$(esc "$(q '.principle.text')")" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="prin-text">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t"}')"
# (d) principle note (prin-text と同型・同 adr-principle ブロック)。
chk "within-doc: 可視 prin-note == .principle.note" "$(esc "$(q '.principle.note')")" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="prin-note">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t"}')"
# (e) context summary (cxid は pin 済 sibling・同順序)。
chk "within-doc: 可視 cxh (context summary) == .context[].summary (順序)" "$(qesc '.context[].summary')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="cxh">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
# (f) option summary (opt-name と同数対応・同順序)。
chk "within-doc: 可視 opt-sum == .options[].summary (順序)" "$(qesc '.options[].summary')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="opt-sum">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
# (g) driver body text (drid は pin 済・drg バッジ除去後の本文を順序突合)。
chk "within-doc: 可視 driver 本文 == .drivers[].driver (順序)" "$(qesc '.drivers[].driver')" "$(printf '%s' "$BODY_NM" | perl -CSD -0777 -ne 'while(/<td class="drid">[^<]*<\/td><td>(.*?)<\/td>/gs){my $t=$1;$t=~s{<span class="drg">.*?</span>}{}g;$t=~s/<[^>]+>//g;$t=~s/\s+$//;print "$t\n"}')"
# (h) consequence positive text (件数 pin 済・b● 除去後の本文を順序突合・orphan-or-count の content 層)。
chk "within-doc: 可視 consequence-pos 本文 == .consequences.positive[].text (順序)" "$(qesc '.consequences.positive[].text')" "$(printf '%s' "$BODY_NM" | perl -CSD -0777 -ne 'while(/<li data-component="adr-consequence-pos">(.*?)<\/li>/gs){my $t=$1;$t=~s{<span class="b">[^<]*</span>}{};$t=~s/<[^>]+>//g;print "$t\n"}')"
# ★folio-bur round-2 (ceiling-recursion 是正): 上の可視本文 chk は double-quote 固定 grep + 完全一致ゆえ、 genuine を
#   display:none/コメント/single-quote 変種で隠し可視 decoy を描く hide-twin/quote-variation で素通る (独立 ceiling 実証)。
#   dty 不動点 = quote-robust 占有数パリティ (count_attr_token は double/single/unquoted/multi-class/entity/属性名 case を全 parse)。
#   各 echo class の占有数 == contract 件数を pin し、 decoy が必ず占有を +1 する性質で hide-twin+decoy を捕捉 (二層目)。
# consequence-pos は class が共有 (b) ゆえ data-component で quote-robust 占有数を取る (既存 L57 grep は double-quote 固定)。
# ★folio-bur round-3 (ceiling-recursion R2 是正): round-1/2 は positive 兄弟だけ可視 content+占有で pin し、 negative・
#   context detail・option pros/cons・justify-note・supersession 自由文注記の 5 可視サーフェスを列挙漏れ → 「欠点は一切無く完璧」
#   「問題は実在せず対策不要」「無限スケール+無コスト」「別理由で正当化」「既に廃止され置換済」等の決定根拠捏造が素通った
#   (独立 ceiling 実証・blocker×2 含む)。 positive と同型に可視 content (BODY_NM で nested term span 早期終端回避) + quote-robust 占有で pin。
# (R3-a) consequence-negative (positive の対称・トレードオフ捏造を封鎖)。
chk "within-doc: 可視 consequence-neg 本文 == .consequences.negative[].text (順序)" "$(qesc '.consequences.negative[].text')" "$(printf '%s' "$BODY_NM" | perl -CSD -0777 -ne 'while(/<li data-component="adr-consequence-neg">(.*?)<\/li>/gs){my $t=$1;$t=~s{<span class="b">[^<]*</span>}{};$t=~s/<[^>]+>//g;print "$t\n"}')"
# (R3-b) context detail cxd (cxh summary の sibling・文脈捏造を封鎖)。
chk "within-doc: 可視 cxd (context detail) == .context[].detail (順序)" "$(qesc '.context[].detail')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="cxd">(.*?)<\/p>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
# (R3-c) option pros/cons を option へ束縛 (option-keyed・本文捏造 + 件数追加 + cross-option relocation を封鎖)。
exp_optpc="$(q '.options[] | .id as $id | ((.pros[] | [$id,"pros",.]),(.cons[] | [$id,"cons",.])) | @tsv' \
  | while IFS=$'\t' read -r a b c; do printf '%s\t%s\t%s\n' "$(esc "$a")" "$b" "$(esc "$c")"; done | LC_ALL=C sort)"
act_optpc="$(printf '%s' "$BODY_NM" | perl -CSD -Mutf8 -0777 -ne '
  while (/<div data-component="adr-option-card"[^>]*>(.*?)(?=<div data-component="adr-option-card"|$)/gs){ my $blk=$1;
    my ($id) = $blk=~/<span class="opt-id">([^<]*)<\/span>/;
    if($blk=~/<div class="pros">(.*?)<\/div>/s){ my $p=$1; while($p=~/<li>(.*?)<\/li>/gs){ my $t=$1;$t=~s/<[^>]+>//g; print "$id\tpros\t$t\n"; } }
    if($blk=~/<div class="cons">(.*?)<\/div>/s){ my $c=$1; while($c=~/<li>(.*?)<\/li>/gs){ my $t=$1;$t=~s/<[^>]+>//g; print "$id\tcons\t$t\n"; } }
  }' | LC_ALL=C sort)"
set_eq "per-option pros/cons == contract (option-keyed・捏造+追加+relocation封鎖)" "$exp_optpc" "$act_optpc"
# ★folio-bur round-4 (ceiling-recursion R3 是正): R3-c の parser は <div class="pros"> double-quote 固定 + first-match (if) ゆえ
#   (D-1) single-quote <div class='pros'> decoy / (D-2) 同 card への 2 個目 double-quote pros div、 で比較根拠 (利点/欠点) を捏造でき
#   素通った (独立 ceiling 実証・blocker)。 各 option は pros/cons 各 1 個ゆえ quote-robust 占有数 == |options| で +1 decoy を封鎖。
# (R3-d) cross-doc justify-note (照会根拠説明文・req/role/href は pin 済 sibling)。
chk "within-doc: 可視 justify-note == .decision.justifies[].note (順序)" "$(qesc '.decision.justifies[].note')" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<span class="justify-note">(.*?)<\/span>/gs){my $t=$1;$t=~s/<[^>]+>//g;print "$t\n"}')"
# (R3-e) supersession 自由文注記 (<p class="ss-row"> で ss-k span を持たない note 行・構造化フィールドは pin 済)。
chk "within-doc: 可視 ss-row note == .supersession.note" "$(esc "$(q '.supersession.note')")" "$(printf '%s' "$BODY_NM" | perl -0777 -ne 'while(/<p class="ss-row">(.*?)<\/p>/gs){my $t=$1; next if $t=~/class="ss-k"/; $t=~s/<[^>]+>//g;print "$t"}')"
# 表紙 cover-meta 4 KV (状態/選択肢/結果/版) の決定的再導出突合 (research (l') と同型)。
adr_meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 状態 == adr_status"          "$(esc "$(q '.meta.adr_status')")" "$(printf '%s\n' "$adr_meta_kv" | grep -F '状態' | head -1 | cut -f2)"
chk "cover-meta 選択肢 == |options|+範囲"     "$(q '.options | length')件 ($(esc "$(q '.options[0].id')")–$(esc "$(q '.options[-1].id')"))" "$(printf '%s\n' "$adr_meta_kv" | grep -F '選択肢' | head -1 | cut -f2)"
chk "cover-meta 結果 == 良い/トレードオフ件数"  "$(esc "良い $(q '.consequences.positive | length') / トレードオフ $(q '.consequences.negative | length')")" "$(printf '%s\n' "$adr_meta_kv" | grep -F '結果' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"             "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$adr_meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"                "4" "$(printf '%s\n' "$adr_meta_kv" | grep -c .)"
# ★folio-bur round-4 (ceiling-recursion R3 是正): 上の adr_meta_kv / 総数==4 は double-quote 固定 grep ゆえ single-quote KV decoy
#   (<span class='k'>状態</span><span class='v'>廃止(虚偽)</span>) を数えず、 表紙に矛盾する文書状態が素通った (独立 ceiling 実証)。
#   research (l') と同型に quote-robust count_attr_token で KEY span を数える (decoy は quote に依らず +1)。
# ★folio-bur round-6 (ceiling-recursion R5 是正): round-4 は k 占有のみ pin し sibling の class="v" を未 pin だったため、 adr_meta_kv が
#   k+v 隣接対のみ数える死角を突き、 genuine 状態 v の直後へ単独 <span class="v">廃止済み(捏造)</span> を注入すると矛盾する表紙状態値が
#   素通った (独立 ceiling 実証・major)。 testcases r5 と同型に v 占有も対称に pin (k と v は KV で常に等数)。

# 3d. ★navigable anchor (folio-lzz: cross-doc deep-link 着地点)。 arch referrer の #decision が着地する固定 anchor。
#     decision panel に id="decision" がちょうど 1 個 (脱落=anchor 不在で 404 復活) + body 全体で id="decision" 一意
#     (別要素への重複 id 注入 = collision を封鎖)。 ADR の cross-doc 被参照点は decision 固定リテラル 1 つ (案A・D-1)。
chk "anchor: decision panel id=decision == 1" "1" "$(grep -c 'data-component="adr-decision-panel" id="decision"' "$BODY")"
# ★folio-lzz ceiling [必須-2]: id collision 検査を quote/entity-robust + global 一意へ。 旧 grep -oE ' id="decision"' は
#   double-quote リテラル固定で id='decision' (single-quote) / id="decisio&#110;" (数値文字参照) が DOM 上 id=decision に解決されるのに
#   数えず、 本物前方への偽 decoy で #decision 着地点を奪取できる fail-open があった (reader-chip/dty の quote-robust 教訓を id uniqueness へ
#   未適用)。 id 属性を attribute-name 境界 ((?<![\w-])(?i:id) で data-*-id 〔直前ハイフン〕除外・whitespace と HTML5 self-closing slash 区切り両捕捉) + quote/entity/case/unquoted-robust に全列挙し body 全体で重複 0 を要求 (SRS [必須-1] と同一 idiom・ceiling round-2 が slash 封鎖)。
allids_dup="$(perl -CSD -0777 -ne 'my $q=chr(39); while (/(?<![\w-])(?i:id)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g){ my $v=defined $1?$1:(defined $2?$2:$3); $v=~s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $v=~s/&#(\d+);?/chr($1)/ge; print "$v\n"; }' < "$BODY" | LC_ALL=C sort | LC_ALL=C uniq -d | grep -c .)"
chk "anchor: navigable id は body 全体で一意 (collision=0・quote/entity/case-robust)" 0 "$allids_dup"
# ★folio-na3: id-alphabet invariant (folio-lzz ceiling round-5 の R4 robustness 再 grounding)。 上の collision gate は
#   抽出 id を numeric entity (&#..) のみ decode し named char-ref (&period;=. &lowbar;=_ 等) は decode しない。 R4 は
#   「named ref は ASCII 英数を綴れないゆえ numeric decode で完全」と論じたが、 named ref は非英数字 (. _ 等) を綴れる —
#   id alphabet にそれらが入れば id="decisio&period;n" が browser で decisio.n に解決しつつ collision gate は生 &period;
#   のまま数え衝突を見逃す fail-open が開く。 ★robustness を「grammar 枯渇」から「制約 alphabet」へ再 grounding: 全 navigable
#   id ∈ [A-Za-z0-9-] は named-ref 不在文字のみ (英数 + ASCII hyphen 0x2D は named ref を持たない) ゆえ named-ref 成りすまし面が
#   *構造的に* 閉じる。 抽出全 id が alphabet に収まることを hard 強制し、 外れる id が 1 つでもあれば FAIL (fail-closed —
#   alphabet 外 id は named-ref decode 面が開く)。 legit id が外れたら alphabet を広げず停止・escalate (id-alphabet-inv)。
allids_badn="$(perl -CSD -0777 -ne 'my $q=chr(39); while (/(?<![\w-])(?i:id)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g){ my $v=defined $1?$1:(defined $2?$2:$3); $v=~s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $v=~s/&#(\d+);?/chr($1)/ge; print "$v\n" if $v !~ /^[A-Za-z0-9-]+\z/; }' < "$BODY" | LC_ALL=C sort -u | grep -c .)"
chk "anchor: 全 navigable id ∈ [A-Za-z0-9-] (制約 alphabet・named-ref 成りすまし面=0・id-alphabet-inv)" 0 "$allids_badn"

# 4. verdict 整合 (chosen ちょうど 1 + decision.chosen 一致)
chk "verdict=chosen はちょうど 1 件" "1" "$(q '[.options[] | select(.verdict=="chosen")] | length')"
chk "decision.chosen == verdict=chosen option" "$(q '[.options[] | select(.verdict=="chosen")][0].id // "MISSING"')" "$(q '.decision.chosen')"
# HTML 側: opt-verdict.chosen の数 (可視 verdict 捏造検出)
chk "HTML chosen バッジ == 1" "1" "$(grep -oE 'class="opt-verdict chosen"' "$BODY" | wc -l | tr -d ' ')"
# ★(opt-id, verdict) ペア一致: どの card が chosen/rejected/deferred かを contract と突合
#   (count 保存型のバッジ付け替え = 採用カードの偽装を捕捉。 総数 1 だけでは fail-open)。
exp_ov="$(q '.options[] | [.id, .verdict] | @tsv' | sort -u)"
act_ov="$(grep -oE '<span class="opt-id">[^<]+</span><span class="opt-name">.*</span><span class="opt-verdict [a-z]+"' "$BODY" \
  | sed -E 's#<span class="opt-id">([^<]+)</span>.*<span class="opt-verdict ([a-z]+)"#\1\t\2#' | sort -u)"
set_eq "HTML (opt-id, verdict) ペア (contract == HTML)" "$exp_ov" "$act_ov"
# ★(verdict, 可視ラベル) ペア一致: バッジの human-visible 文字 (採用/不採用/保留) が verdict と整合する
#   (非エンジニアが実際に読むのは class でなく可視文字。 class は正のまま可視ラベルだけ改竄する偽装は
#    上の (opt-id,verdict) class 突合を素通り = fail-open。 VERDICT_LABEL 相当を突合して捕捉する)。
exp_vl="$(printf 'chosen\t採用\nrejected\t不採用\ndeferred\t保留\n' | sort)"
act_vl="$(grep -oE '<span class="opt-verdict [a-z]+">[^<]*</span>' "$BODY" \
  | sed -E 's#<span class="opt-verdict ([a-z]+)">([^<]*)</span>#\1\t\2#' | sort -u)"
# HTML に出た各 verdict class が正しい可視ラベルを持つことを要求 (HTML 側 ⊆ 期待マップ)。
bad_vl="$(comm -13 <(printf '%s\n' "$exp_vl") <(printf '%s\n' "$act_vl") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "HTML verdict バッジの可視ラベルが verdict と整合" "$bad_vl"

# 4b. supersession / principle (assembler が emit する終端章。 fabrication-free を emit 全章へ拡張)
#     これらが構造検証外だと principle.id 改竄・supersession.status 偽装・supersedes 捏造が fail-open になる
#     (SRS-pack の verify-fabrication-free と「同型」を謳う以上、 emit する全章は contract 導出を証明する)。
chk "adr-supersession ブロック == 1"       "1" "$(grep -c 'data-component="adr-supersession"' "$BODY")"
chk "adr-principle ブロック == 1"          "1" "$(grep -c 'data-component="adr-principle"' "$BODY")"
# ★ds8 ceiling round-2: prin-id / 各 ss-row を *個数固定* (duplicate-decoy = 隠し正規 <p> + 可視偽 <div> の付け足しを count で捕捉。
#   round-1 では tag固定 grep 抽出のみで wrapper-swap は mismatch で捕捉できたが duplicate-decoy が素通っていた = round-2 ceiling 指摘)。
# ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 sweep が cxid/justify-role を count_attr_token へ昇格したが兄弟 prin-id を
#   取りこぼし、 single-quote prin-id decoy が grep -c (double-quote) を逃れ照会 graph 終端 principle identity (ADR pack の core 保証) を
#   捏造でき素通った (独立 ceiling 実証・blocker)。 quote-robust 占有へ統一 (uniform sweep の機械的完遂)。
chk "prin-id 行 == 1"            "1" "$(count_attr_token class prin-id < "$BODY")"
chk "ss-row 改訂状態 == 1"        "1" "$(grep -c '<span class="ss-k">改訂状態</span>' "$BODY")"
chk "ss-row 置き換える ADR == 1"  "1" "$(grep -c '<span class="ss-k">置き換える ADR</span>' "$BODY")"
chk "ss-row 置き換えられた == 1"  "1" "$(grep -c '<span class="ss-k">置き換えられた</span>' "$BODY")"
# ★folio-bur round-4 (ceiling-recursion R3 是正): 上の固定 3 ラベル個別 count は allowlist 列挙ゆえ、 (a) allowlist 外の novel
#   ss-k 行 (<span class="ss-k">廃止予定日</span>...) (b) single-quote の ss-row note decoy、 で改訂状態を捏造でき素通った
#   (独立 ceiling 実証)。 dty が round-9 で確立した『allowlist 列挙→総数アサート』へ昇格: ss-row 総数==4 (構造 3 + note 1)・ss-k 総数==3。
# (b) principle.id == contract .principle.id (照会終端の identity 偽装を捕捉)
act_prin="$(grep -oE '<p class="prin-id">[^<]*</p>' "$BODY" | sed -E 's#.*— ([^<]*)</p>#\1#')"
chk "principle.id == contract .principle.id" "$(esc "$(q '.principle.id')")" "$act_prin"
# (c) supersession.status == contract .supersession.status (改訂状態の偽装を捕捉)
act_ss="$(grep -oE '<p class="ss-row"><span class="ss-k">改訂状態</span>[^<]*</p>' "$BODY" | sed -E 's#.*改訂状態</span>([^<]*)</p>#\1#')"
chk "supersession.status == contract .status" "$(esc "$(q '.supersession.status')")" "$act_ss"
# (d) supersedes / superseded_by の内容一致 (捏造リンクを捕捉。 空は assembler の「なし」sentinel と突合)
sup_n="$(q '.supersession.supersedes | length')"; superby_n="$(q '.supersession.superseded_by | length')"
exp_sup="$([[ "$sup_n" -gt 0 ]] && q '.supersession.supersedes | join(", ")' || echo "なし (新規)")"
exp_superby="$([[ "$superby_n" -gt 0 ]] && q '.supersession.superseded_by | join(", ")' || echo "なし (現行)")"
act_sup="$(grep -oE '<p class="ss-row"><span class="ss-k">置き換える ADR</span>[^<]*</p>' "$BODY" | sed -E 's#.*ADR</span>([^<]*)</p>#\1#')"
act_superby="$(grep -oE '<p class="ss-row"><span class="ss-k">置き換えられた</span>[^<]*</p>' "$BODY" | sed -E 's#.*置き換えられた</span>([^<]*)</p>#\1#')"
chk "supersession.supersedes == contract"     "$(esc "$exp_sup")"    "$act_sup"
chk "supersession.superseded_by == contract"  "$(esc "$exp_superby")" "$act_superby"

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

# 7. plain-language-term-inline fidelity + 用語被覆 (assemble-adr と同一語境界規律)。
#    実装は core (verify-common.sh の verify_term_inline)。 markable フィールド集合は ADR-pack 固有ゆえ
#    ここで yq 式を渡す (★この yq リストは assemble-adr の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.context[].summary, .context[].detail, .drivers[].driver, .options[].name, .options[].summary, .options[].pros[], .options[].cons[], .decision.statement, .decision.justifies[].note, .consequences.positive[].text, .consequences.negative[].text, .supersession.note, .principle.text, .principle.note' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"



echo
# ---- gate F: render 健全性 (visual) cross-pack 展開 (folio-vuf A・helper=render_gate_f)。
#      非 mermaid pack の生成 HTML を light/dark × 3 viewport で render-gate。 mermaid 検出時は honest
#      SKIP (B 段 folio-vuf B へ defer)。 fail-closed (violation/crash = $fail=1・T7 guard 維持)。 ----
render_gate_f "$HTML" "ADR_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  # mode 別詳細 (旧 reason 語 artifact/filled/fabrication-free を substring 保全)。
  if [[ -n "$ARTIFACT" ]]; then mode_detail="mode=artifact: 構造 fabrication-free + cross-doc 照会解決 + term-inline + prose 全充填"
  elif [[ -n "$FILLED_MANIFEST" ]]; then mode_detail="mode=filled: 構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実"
  else mode_detail="mode=fabrication-free: 構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空"; fi
  # ceiling-precheck sentinel を verify-srs.sh:386-400 と同型で統一 emit (folio-1kif errata must-1)。
  # ceiling-precheck.sh は doc-type 非依存の文字列照合 = 'RESULT: floor PASS' ∧ 'CEILING=PENDING' を要求する。
  # gate 全通過時のみ CEILING=PENDING を advisory 宣言 (floor 単独で GREEN を宣言しない)。 render honest-SKIP は
  # render_gate_f が '[SKIP] gate F' を emit し ceiling-precheck が SKIP-masquerade(exit3) に落とす = PENDING と
  # 区別する (検証実体なしの捏造印字を防ぐ・honest-SKIP≠PENDING)。 捏造印字は禁止 (SKIP-masquerade 再輸入)。
  echo "RESULT: floor PASS ($mode_detail) — ただし CEILING=PENDING (*GREEN ではない*)"
  # ★S4 (round-2): ceiling-precheck の SKIP-masquerade 検出を render_gate_f 単一 marker '[SKIP]' のみに依存させない。
  #   env-skip 時は verify-srs.sh:391-393 と同型の 'render gate 未完' marker も併記し、 ceiling-precheck.sh の 3-fold
  #   marker (grep '[SKIP]' / 'render gate 未完' / 'gateF=skip') のうち 2 本を verify-adr 側で load-bearing に保つ
  #   (cross-ref pin: この文字列は ceiling-precheck.sh の SKIP-masquerade guard と load-bearing・回帰 assert は
  #   test-adversarial-verify-dispatch.sh B2 が exit3 転落で pin)。 renderer 不在時は render_gate_f の '[SKIP]' が担保。
  if [[ "${ADR_SKIP_RENDER:-0}" == "1" || "${SKIP_RENDER:-0}" == "1" ]]; then
    echo "  ※ render gate 未完 (F=見た目崩れ が未実行: ADR_SKIP_RENDER/SKIP_RENDER) — CI/uv 環境で render を回すまで floor は不完全。"
  fi
  echo "  ceiling = persona-walk-adr + fidelity-adr (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に blocking arm (構造/cross-doc/prose/term-inline/gate F) が不合格"
  exit 1
fi
