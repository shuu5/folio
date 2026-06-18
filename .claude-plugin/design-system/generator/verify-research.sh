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
  while (/<(\w+)\b[^>]*\bdata-component="cross-doc-leads-chip"[^>]*>(.*?)<\/\1>/gs) {
    my ($chip,$in)=($&,$2); my ($l)=$chip=~/\bdata-leads-to="([^"]*)"/; $l="" unless defined $l;
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
adr_id_e="$(esc "$(q '.cross_doc.adr_doc_id')")"
# (g') oc-resolved 内 <b> == 各ブロックの data-resolved-by / (h') cover ref-chip 内 <b> == adr_doc_id /
# (j') oc-tgt 内 <b> == adr_doc_id (assemble で <b> 包みに統一)。 いずれも 全<b>列挙 + ちょうど1本 == 期待で
#      追加 (第2 <b> 注入)・削除・改竄・併記の全方向を塞ぐ (round-2: substring/first-match は併記/追加に脆弱)。
# ★可視テキスト厳密一致 (round-4 ceiling + ds8 ceiling 深化): 各 echo ブロックの全タグ除去後の可視テキストが固定テンプレ+id(+title)と
#   完全一致を要求。 これらは prose スロットも自由文も無い *完全決定的* ブロックゆえ可視テキスト全体を厳密照合でき、
#   タグ併記・平文併記 (<b> の外に「実は ADR-FORGED」)・swap・任意注入 を一括封鎖する *不動点*。
#   ★while-regex は marker-keyed (<(\w+)\b ... marker ...>(.*?)</\1>) = マーカーを担持する任意 wrapper タグを捕捉する。
#   tag 固定 (<p>/<div>) だと wrapper-tag swap (例 <p class="oc-tgt"> → <div class="oc-tgt">) で while がスキップし可視検査を
#   逃れる fail-open が残っていた (ds8 ceiling 検出・B3 の「不動点」が wrapper-tag 選択で兄弟経路を残していた)。 marker-only count anchor (上) とパリティを取る。
echo_bad="$(EXP="$adr_id_e" TITLE="$(esc "$(q '.cross_doc.adr_title')")" perl -CSD -Mutf8 -0777 -ne '
  my $exp=$ENV{EXP}; utf8::decode($exp); my $title=$ENV{TITLE}; utf8::decode($title); my @bad;
  while (/<(\w+)\b[^>]*\bclass="oc-resolved"[^>]*>(.*?)<\/\1>/gs) {
    my ($blk,$in)=($&,$2); my ($rb)=$blk=~/\bdata-resolved-by="([^"]*)"/; $rb="" unless defined $rb;
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"oc-resolved:".scalar(@bs)."B"; next} if($bs[0] ne $rb){push @bad,"oc-resolved:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"oc-resolved:VIS" if $vis ne "この調査は $rb で決着しました";
  }
  while (/<(\w+)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my $in=$2; my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){push @bad,"ref-chip:".scalar(@bs)."B"; next} if($bs[0] ne $exp){push @bad,"ref-chip:b\x{2260}$bs[0]"}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " この調査の行き先: $exp \x{2014} $title";
  }
  while (/<(\w+)\b[^>]*\bclass="oc-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my $in=$2; my @bs=$in=~/<b>([^<]*)<\/b>/g;
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
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

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

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + cross-doc 前方照会解決 + term-inline + prose 全充填)"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 注入忠実)"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 空)"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
