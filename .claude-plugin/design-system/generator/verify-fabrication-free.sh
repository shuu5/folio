#!/usr/bin/env bash
# folio S4 generator — fabrication-free proof (ADR-0042 §2.1 / §3)
#
# 生成 HTML の *構造* が入力 contract から完全に導出されたことを機械検証する:
#   - 行数 (要件 / NFR / 出所) が contract の要素数と一致 (data-component 行マーカーで table-scoped に数える)。
#   - id 一意性 (要件+NFR / ニーズ / 受入)。
#   - RTM の backward (●) リンク集合・acceptance (受入) リンク集合が、 それぞれ contract の
#     trace.backward / trace.acceptance と *集合として一致* (捏造 0 + 脱落 0、 両軸対称)。
#   - 決定的サマリの数値 (要件/ニーズ/リンク/孤立/未検証) を contract から *独立再計算* して HTML と突合
#     (assembler のロジックバグ・後段改竄も捕捉)。
#   - within-doc 決定的フィールド値 (識別子/構造/数値/統制値 = §7e/§7f) + body prose 自由文値 (mark_terms 系 = §7g・folio-4cf)
#     を term-badge strip + 順序突合 + 占有数パリティの二層で contract と完全突合 (本文改竄を floor で捕捉)。
#   - prose スロット (既定 = pre-fill): 存在しかつ全て空 (perl で要素単位判定 = ネストタグ/改行始まりも捕捉)。
#   - prose スロット (--filled <manifest> = post-fill): 全て非空 (no-TBD) かつ各 data-slot-id の内容が
#     escape 済み manifest 値と完全一致 (注入忠実 = opus 散文の改竄・out-of-band 注入・脱落を捕捉)。
#     構造チェック (1-7d) は両モードで不変 (注入は prose のみ充填し構造を触らない)。
#
# usage: verify-fabrication-free.sh [--filled <manifest.yaml>] <contract.yaml> <generated.html>

set -uo pipefail
# esc() の ${v//pat/repl} を bash 5.2+ patsub_replacement が壊す (< → <lt;) ため無効化。
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
# --filled <manifest>: 注入忠実 (生成時)。 --artifact: prose 全充填のみ (manifest 不要、 成果物 floor = verify-srs gate G)。
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-fabrication-free.sh [--filled <manifest> | --artifact] <contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-fabrication-free.sh [--filled <manifest> | --artifact] <contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、
# <style> ブロックを除去した body-only ビュー ($BODY) で数える (make_body が用意・S5 floor gate も同じ前提)。
# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-44s ----
# 新依存 lib/verify-common.sh を fail-closed guard する (欠落/source 失敗を false-green に倒さない。
# set -e 無しゆえ source rc=1 でも継続し helper が command-not-found 化する)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-fabrication-free: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=44; source "$LVC" || { echo "verify-fabrication-free: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"

echo "fabrication-free proof: $HTML"
echo "  contract: $CONTRACT"

# 1-3. 行数 (data-component 行マーカーで table-scoped、 id 命名非依存)
chk "requirement rows == |requirements|" "$(q '.requirements | length')"  "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "nfr rows == |nfr|"                  "$(q '.nfr | length')"          "$(grep -c 'data-component="nfr-metric-row"' "$BODY")"
chk "origin rows == |upper_needs|"       "$(q '.upper_needs | length')"  "$(grep -c 'data-component="source-trace-row"' "$BODY")"

# 4. id 一意性 (ADR-0042 §2.1 の不変条件)
chk_empty "要件/NFR id 一意" "$(q '(.requirements[].id, .nfr[].id)' | sort | uniq -d | tr '\n' ' ')"
chk_empty "ニーズ id 一意"   "$(q '.upper_needs[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "受入 id 一意"     "$(q '.acceptance[].id' | sort | uniq -d | tr '\n' ' ')"

# 5. backward (●) リンク集合 == contract (要件ごと unique = assembler の 1 セル意味論に一致)
exp_b="$(q '(.requirements + .nfr)[] | .id as $i | (.trace.backward | unique)[] | $i + "__" + .' | sort)"
# ★round-9 ceiling: data-*-link 抽出は quote-robust な attr_values で (旧 grep 'attr="[^"]+"' は single-quote/unquoted の
#   偽 link を素通し、 acc-dot single-quote decoy で受入トレースを捏造できた = round-8 ceiling 実証)。
act_b="$(attr_values data-trace-link < "$BODY" | sort)"
chk     "backward link count == Σ unique backward" "$(printf '%s\n' "$exp_b" | grep -c .)" "$(printf '%s\n' "$act_b" | grep -c .)"
set_eq  "backward link SET == contract" "$exp_b" "$act_b"

# 6. acceptance (受入) リンク集合 == contract (backward と対称)
exp_a="$(q '(.requirements + .nfr)[] | .id as $i | (.trace.acceptance | unique)[] | $i + "__" + .' | sort)"
act_a="$(attr_values data-acc-link < "$BODY" | sort)"
chk     "acceptance link count == Σ unique acceptance" "$(printf '%s\n' "$exp_a" | grep -c .)" "$(printf '%s\n' "$act_a" | grep -c .)"
set_eq  "acceptance link SET == contract" "$exp_a" "$act_a"

# 7. 決定的サマリ数値を contract から独立再計算して HTML の data-derived と突合
declare -A D
while IFS='=' read -r k v; do [[ -n "$k" ]] && D[$k]="$v"; done \
  < <(grep -oE 'data-derived="[^"]+"' "$BODY" | sed 's/.*data-derived="//; s/"$//' | tr ';' '\n')
chk "summary req == |req+nfr|"          "$(q '(.requirements + .nfr) | length')"                                             "${D[req]:-MISSING}"
chk "summary need == |upper_needs|"     "$(q '.upper_needs | length')"                                                       "${D[need]:-MISSING}"
chk "summary link == Σ backward"        "$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"                        "${D[link]:-MISSING}"
chk "summary iso == 出所なし要件数"     "$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')" "${D[iso]:-MISSING}"
chk "summary unv == 受入なし要件数"     "$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')" "${D[unv]:-MISSING}"

# 7a. ★ds8 ceiling round-3: 表紙 cover-meta 4 KV (機能要件/非機能要件/受入基準/版) を決定的再導出突合 (ADR/research と parity・全 pack 共通の identity echo gap)。
#    round-2 まで SRS cover-meta は皆無検証で 可視 KV 改竄 (機能要件 6件→999件) が素通る fail-open だった。 acceptance metric の class="v" は class="k" 非隣接ゆえ非該当。
srs_meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 機能要件 == |req|+範囲"     "$(q '.requirements | length')件 ($(esc "$(q '.requirements[0].id')")–$(esc "$(q '.requirements[-1].id')"))" "$(printf '%s\n' "$srs_meta_kv" | grep -F '機能要件' | grep -vF '非機能' | head -1 | cut -f2)"
chk "cover-meta 非機能要件 == |nfr|+範囲"   "$(q '.nfr | length')件 ($(esc "$(q '.nfr[0].id')")–$(esc "$(q '.nfr[-1].id')"))" "$(printf '%s\n' "$srs_meta_kv" | grep -F '非機能要件' | head -1 | cut -f2)"
chk "cover-meta 受入基準 == |acceptance|+範囲" "$(q '.acceptance | length')件 ($(esc "$(q '.acceptance[0].id')")–$(esc "$(q '.acceptance[-1].id')"))" "$(printf '%s\n' "$srs_meta_kv" | grep -F '受入基準' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"           "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$srs_meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"              "4" "$(printf '%s\n' "$srs_meta_kv" | grep -c .)"

# 7b. 内容部品の行数 (contract 要素数と一致 = 捏造/脱落なし、 全て独立した行マーカーで table-scoped)
chk "goals == |goals|"             "$(q '.goals | length')"                               "$(grep -c 'class="card accent"' "$BODY")"
chk "scope items == |in|+|out|"    "$(q '(.scope.in | length) + (.scope.out | length)')"  "$(grep -c 'class="b">' "$BODY")"
chk "actors == |actors|"           "$(q '.actors | length')"                              "$(grep -c 'class="actor"' "$BODY")"
chk "acceptance == |acceptance|"   "$(q '.acceptance | length')"                          "$(grep -c 'class="aid"' "$BODY")"
chk "nfr-hero == |nfr(hero)|"      "$(q '[.nfr[] | select(.hero)] | length')"             "$(grep -c 'class="nfr-hero ' "$BODY")"
chk "constraints == |constraints|" "$(q '.constraints | length')"                         "$(grep -c 'class="cid2"' "$BODY")"
chk "glossary == |glossary|"       "$(q '.glossary | length')"                            "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"       "$(q '.approval | length')"                            "$(grep -c 'class="sign"' "$BODY")"
# 7b'. ★core 共通 chrome (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary term/en/def) の
#      値突合 (第1層・folio-mk9・lib/verify-common.sh の verify_core_chrome)。 上の件数のみ検証 (件数 OK でも値改竄が
#      素通る fail-open) を全 pack 共通で塞ぐ cross-pack gap の解消 (dty round-2 完全列挙が発見・ADR/research も同型 gap)。
# ★mzn.3 Phase C: verify_core_chrome の global 占有 pin (旧・第2層) と reader-chip decoy は退役 (repro-build byte-identity
#   が構造 fidelity を継承)。 旧・追加 home 数 ($1/$2) の引数受渡しも不要になった (関数は残っても無視する)。
verify_core_chrome

# 7c. yq の入れ子 optional 欠落で "null" セルが人間出力へ漏れていないか
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"
# 7d. esc 破綻 (patsub back-ref 化け) で壊れた entity が出ていないか
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"

# 7e. ★dty (folio-dty): within-doc 決定的可視フィールド値の順序付き突合 (ds8 round-4 ceiling 繰延・cxid/drid/cover-meta と同型・全 pack parity)。
#    7b の *件数のみ* 検証では 決定的フィールド値の改竄 (見出し『二重課金しない』→詐欺文・hero『1.0秒』→『99.0秒』・出所『経営方針』→捏造・
#    合否しきい値『1/2』→『999/9』) が件数保存のまま素通る fail-open だった。 これらは全て esc 済決定的値ゆえ floor 検証可能。
#    ★抽出の分類 (ds8 round-4 不動点の適用):
#      - plain leaf (esc 済 [^<]*) = grep+sed 順序突合 (cxid/drid と同型)。 ★ただし小文字 class grep ゆえ単体では case-drop+decoy
#        (class="CT" で偽要素を脱落させ class="ct" decoy で列保存) を素通す → 下の vcount: 各 value class の count_attr_token
#        占有数パリティ (case/quote/entity 非依存) を *併設* して偽要素の add を封じる二層 (round-5 ceiling 反映)。
#      - compound (固定 nested 構造 = 外部バッジ span / u span / metric の v·l) = structured-regex 順序突合 (literal nested タグで leaf 抽出)。
#    順序リスト厳密一致 (chk) = 値・順序の改竄を捕捉。 vcount の占有数パリティ = case-drop/entity/decoy の add を捕捉。 二層で被覆。
# (a) goals: id (cid) + headline (ct) — plain leaf・順序 = .goals[] 配列順
chk "within-doc: 可視 goals.id 列 == .goals[].id (順序)"            "$(qesc '.goals[].id')"       "$(grep -oE '<div class="cid">[^<]*</div>' "$BODY" | sed -E 's#<div class="cid">([^<]*)</div>#\1#')"
chk "within-doc: 可視 goals.headline 列 == .goals[].headline (順序)" "$(qesc '.goals[].headline')" "$(grep -oE '<p class="ct">[^<]*</p>' "$BODY" | sed -E 's#<p class="ct">([^<]*)</p>#\1#')"
# (b) actors: key (av) — plain leaf / name+外部バッジ (nm) — compound (固定 ext-badge span を含めて決定的再構築)
chk "within-doc: 可視 actors.key 列 == .actors[].key (順序)" "$(qesc '.actors[].key')" "$(grep -oE '<span class="av"[^>]*>[^<]*</span>' "$BODY" | sed -E 's#<span class="av"[^>]*>([^<]*)</span>#\1#')"
exp_nm="$(q '.actors[] | [.name, .external] | @tsv' | while IFS=$'\t' read -r _nm _ext; do
  _b=""; [[ "$_ext" == "true" ]] && _b='<span class="ext-badge">外部</span>'; printf '%s%s\n' "$(esc "$_nm")" "$_b"; done)"
act_nm="$(perl -CSD -0777 -ne 'while (/<div class="nm">(.*?)<\/div>/g){ print "$1\n"; }' "$BODY")"
chk "within-doc: actors.nm (name+外部バッジ) 列 == 再構築 (順序)" "$exp_nm" "$act_nm"
# (c) upper_needs: origin は class="origin" 一意。 nid は nfr 表と class 共有ゆえ source-trace-row 内に scope し (id, origin) を対で取る
exp_st="$(q '.upper_needs[] | [.id, .origin] | @tsv' | while IFS=$'\t' read -r _id _og; do printf '%s\t%s\n' "$(esc "$_id")" "$(esc "$_og")"; done)"
act_st="$(perl -CSD -0777 -ne 'while (/data-component="source-trace-row">.*?<span class="nid">([^<]*)<\/span>.*?<span class="origin">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "within-doc: source-trace (id, origin) 列 == .upper_needs (順序)" "$exp_st" "$act_st"
# (d) rtm-grid 列見出し (th.grp = esc(id) 半角空白 esc(short)) — plain leaf
exp_grp="$(q '.upper_needs[] | [.id, .short] | @tsv' | while IFS=$'\t' read -r _id _sh; do printf '%s %s\n' "$(esc "$_id")" "$(esc "$_sh")"; done)"
act_grp="$(grep -oE '<th class="grp">[^<]*</th>' "$BODY" | sed -E 's#<th class="grp">([^<]*)</th>#\1#')"
chk "within-doc: rtm 列見出し == .upper_needs[].id+short (順序)" "$exp_grp" "$act_grp"
# (e) acceptance: aid (id ← join('/',links)) — plain leaf / metric (v, l) — compound (class="metric" に scope)
exp_aid="$(q '.acceptance[] | [.id, (.links | join("/"))] | @tsv' | while IFS=$'\t' read -r _id _lk; do printf '%s ← %s\n' "$(esc "$_id")" "$(esc "$_lk")"; done)"
act_aid="$(grep -oE '<div class="aid">[^<]*</div>' "$BODY" | sed -E 's#<div class="aid">([^<]*)</div>#\1#')"
chk "within-doc: acceptance.aid (id ← links) 列 == 再構築 (順序)" "$exp_aid" "$act_aid"
exp_metric="$(q '.acceptance[] | [(.metric_v // ""), (.metric_l // "")] | @tsv' | while IFS=$'\t' read -r _v _l; do printf '%s\t%s\n' "$(esc "$_v")" "$(esc "$_l")"; done)"
act_metric="$(perl -CSD -0777 -ne 'while (/<div class="metric"><span class="v">([^<]*)<\/span><span class="l">([^<]*)<\/span><\/div>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "within-doc: acceptance.metric (合否しきい値 v, l) 列 == .acceptance (順序)" "$exp_metric" "$act_metric"
# (f) nfr-hero (表紙ダッシュボード hero 数値): cat / big / unit / qual — structured (big は text + u span の compound)
exp_hero="$(q '.nfr[] | select(.hero) | [(.hero.cat // ""), (.hero.big // ""), (.hero.unit // ""), (.hero.qual // "")] | @tsv' | while IFS=$'\t' read -r _c _bg _u _ql; do printf '%s\t%s\t%s\t%s\n' "$(esc "$_c")" "$(esc "$_bg")" "$(esc "$_u")" "$(esc "$_ql")"; done)"
act_hero="$(perl -CSD -0777 -ne 'while (/<div class="nfr-hero c\d+"><div class="cat">([^<]*)<\/div><div class="big">([^<]*)<span class="u">([^<]*)<\/span><\/div><div class="qual">([^<]*)<\/div><\/div>/g){ print "$1\t$2\t$3\t$4\n"; }' "$BODY")"
chk "within-doc: nfr-hero (cat,big,unit,qual) 列 == .nfr(hero) (順序)" "$exp_hero" "$act_hero"
# (g) data-source attr (= rationale_source 接地メタ・非可視ゆえ severity 低): (req-id, data-source) を非空 rationale_source と集合突合
#     (ADR の data-justifies-role attr 突合と parity。 重複/捏造は requirement-row 件数 anchor 〔上記 1-3〕が backstop)。
exp_ds="$(q '.requirements[] | select((.rationale_source // "") != "") | [.id, .rationale_source] | @tsv' | while IFS=$'\t' read -r _id _rs; do printf '%s\t%s\n' "$(esc "$_id")" "$(esc "$_rs")"; done | sort)"
act_ds="$(perl -CSD -0777 -ne 'while (/data-prose-slot="rationale" data-source="([^"]*)" data-slot-id="rationale-([^"]+)"/g){ print "$2\t$1\n"; }' "$BODY" | sort)"
set_eq "within-doc: (req-id, data-source) == 非空 rationale_source (集合)" "$exp_ds" "$act_ds"

# 7f. ★dty round-2 (独立 ceiling の完全列挙反映): §7e が *部分列挙* で残した決定的可視/attr フィールドを全突合する。
#    ds8 教訓#2「機械的完全性照合は全可視 echo を *列挙* せよ」の再適用 — ceiling が 9 種の fail-open を実証検出した:
#    要件 ID 本体 (fid/data-req-id の consistent rename が floor も verify-srs gate D も貫通 = blocker)・EARS 種別 (class+label)・
#    priority ラベル・vmethod・nfr 表の nid/category・constraint label/法令名・rtm 行ラベル・actor tint。 全て row-scope 抽出 + 順序突合で塞ぐ。
#    ★vmeth/prio/ears は legend (emit_legend) と class 共有ゆえ **必ず ears-requirement-row 内に scope** して抽出する (legend を拾うと count 不一致)。
#    ★EARS_CLASS/EARS_LABEL/PRIO_LABEL は assemble-srs の同名連想配列と二重保守 (detect↔remediate parity・mark_terms yq リストと同じ規律)。
declare -A DTY_EARS_CLASS=( [ubiquitous]=always [event]=trigger [state]=state [unwanted]=forbid [optional]=option )
declare -A DTY_EARS_LABEL=( [ubiquitous]=恒常 [event]=きっかけ [state]=状態 [unwanted]=禁止 [optional]=機能 )
declare -A DTY_PRIO_LABEL=( [must]=必須 [should]=推奨 [may]=任意 )
# ★folio-czo: 凡例 ears chip の en サブラベル (英語 EARS keyword)。 凡例は静的資産 (emit_legend) ゆえ DTY_*_ と同じく二重保守。
declare -A DTY_EARS_EN=( [event]=When [state]=While [unwanted]=If-Then [ubiquitous]=Ubiq. )
# (h) ★要件行の主要識別子+意味種別を 1 タプルで row-scope 突合: data-req-id・fid・ears(class,label)・priority(class,label)・vmethod。
#     ★blocker 封鎖: fid/data-req-id を contract id と突合し 可視↔attr↔contract の三者一致を強制 (consistent rename = FR1→FR99 を封鎖)。
exp_reqrow="$(q '.requirements[] | [.id, .ears.pattern, .priority, .vmethod] | @tsv' | while IFS=$'\t' read -r _id _pat _pr _vm; do
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(esc "$_id")" "$(esc "$_id")" "${DTY_EARS_CLASS[$_pat]}" "${DTY_EARS_LABEL[$_pat]}" "$_pr" "${DTY_PRIO_LABEL[$_pr]}" "$(esc "$_vm")"; done)"
act_reqrow="$(perl -CSD -0777 -ne 'while (/<tr data-component="ears-requirement-row" data-req-id="([^"]*)" id="[^"]*"><td><span class="fid">([^<]*)<\/span><\/td><td><span class="ears ([a-z]+)">([^<]*)<\/span><\/td>.*?<span class="prio ([a-z]+)" data-component="priority-badge">([^<]*)<\/span> <span class="vmeth">([^<]*)<\/span><\/td><\/tr>/g){ print "$1\t$2\t$3\t$4\t$5\t$6\t$7\n"; }' "$BODY")"
chk "within-doc: 要件行 (req-id,fid,ears,prio,vmethod) == .requirements (順序)" "$exp_reqrow" "$act_reqrow"
nreq="$(q '.requirements | length')"
reqrows="$(grep 'data-component="ears-requirement-row"' "$BODY")"
legendblk="$(grep 'class="ears-legend"' "$BODY")"
# ★round-9 ceiling: 凡例 chip の *可視ラベル* を (class,label) 対で SET 突合 (round-8 までは占有数 2/4/4 のみ縛り、
#   ラベルテキスト未突合ゆえ きっかけ↔禁止 swap・必須↔推奨・vmeth ラベル捏造が素通った = partial-enumeration の穴)。
#   凡例は静的デザイン資産 (emit_legend) ゆえ ears/prio は DTY_*_LABEL から再導出し detect↔remediate parity、 vmeth は固定。
# ★folio-czo: en (When/While/If-Then/Ubiq.) と lt (タイプ:/優先:/検証:) も SET に追加し R9 主ラベル突合と *対称化* する
#   (round-9 までは en/lt が EXEMPT で未突合 = ears 主ラベルは縛るのに英語 keyword/区分ラベルは縛らない非対称)。
#   en は親 ears chip の class と対 (en の位置 swap も捕捉)、 lt は単独ラベル。 ★en は glossary 表とも class 共有ゆえ
#   *legendblk scope* で数える (global vcount 化すると glossary en と混ざる = folio-mk9 chrome の領分)。
exp_legend="$( { for _pat in event state unwanted ubiquitous; do printf 'ears %s\t%s\n' "${DTY_EARS_CLASS[$_pat]}" "${DTY_EARS_LABEL[$_pat]}"; done
  for _pat in event state unwanted ubiquitous; do printf 'en %s\t%s\n' "${DTY_EARS_CLASS[$_pat]}" "${DTY_EARS_EN[$_pat]}"; done
  printf 'prio must\t%s\n' "${DTY_PRIO_LABEL[must]}"; printf 'prio should\t%s\n' "${DTY_PRIO_LABEL[should]}"
  printf 'vmeth\tT=テスト\nvmeth\tA=分析\nvmeth\tI=目視確認\nvmeth\tD=実演\n'
  printf 'lt\tタイプ:\nlt\t優先:\nlt\t検証:\n'; } | sort)"
act_legend="$(printf '%s\n' "$legendblk" | perl -CSD -0777 -e '
  my $q=chr(39); my $t=<STDIN>; $t="" unless defined $t; my @o;
  while ($t =~ /class\s*=\s*["$q]?ears\s+([a-z]+)["$q]?\s*>([^<]*?)\s*<span/g){ push @o,"ears $1\t$2"; }
  while ($t =~ /class\s*=\s*["$q]?ears\s+([a-z]+)["$q]?\s*>[^<]*?<span\s+class\s*=\s*["$q]?en["$q]?\s*>([^<]*)<\/span>/g){ push @o,"en $1\t$2"; }
  while ($t =~ /class\s*=\s*["$q]?prio\s+([a-z]+)["$q]?[^>]*>([^<]*)<\/span>/g){ push @o,"prio $1\t$2"; }
  while ($t =~ /class\s*=\s*["$q]?vmeth["$q]?\s*>([^<]*)<\/span>/g){ push @o,"vmeth\t$1"; }
  while ($t =~ /class\s*=\s*["$q]?lt["$q]?[^>]*>([^<]*)<\/span>/g){ push @o,"lt\t$1"; }
  print "$_\n" for sort @o;')"
set_eq "legend-scope: chip 可視ラベル (class,label) == 凡例期待 (swap/捏造封鎖・en/lt 対称)" "$exp_legend" "$act_legend"
ngoal="$(q '.goals | length')"; nact="$(q '.actors | length')"; nun="$(q '.upper_needs | length')"
ncon="$(q '.constraints | length')"; nacc="$(q '.acceptance | length')"; nhero="$(q '[.nfr[] | select(.hero)] | length')"
# ★round-7 ceiling: rtm-summary-derived の *可視* 5 数値 (要件/上位ニーズ/トレースリンク/孤立/未検証) を再導出突合 (§7 は data-derived
#   *属性* のみ・可視テキストはどの層も突合せず EXEMPT で素通った misclassification = 決定的 contract 値の捏造が可能だった)。
rtm_nreq="$(q '(.requirements + .nfr) | length')"; rtm_nneed="$(q '.upper_needs | length')"
rtm_nlinks="$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"
rtm_niso="$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')"
rtm_nunv="$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')"
exp_rtmsum="要件 ${rtm_nreq} 件 / 上位ニーズ ${rtm_nneed} 件 / トレースリンク ${rtm_nlinks} 本 / 孤立要件 (出所なし) ${rtm_niso} 件 / 未検証要件 (受入なし) ${rtm_nunv} 件"
act_rtmsum="$(perl -CSD -0777 -e 'my $q=chr(39); my $t=<STDIN>; $t="" unless defined $t; while ($t =~ /<p\b[^>]*\bclass\s*=\s*(?:"rtm-summary-derived"|${q}rtm-summary-derived${q}|rtm-summary-derived(?=[\s>]))[^>]*>(.*?)<\/p>/gs){ print $1 }' < "$BODY")"
chk "within-doc: rtm-summary 可視 5 数値 == 再導出 (data-derived 属性の可視版)" "$exp_rtmsum" "$act_rtmsum"
# (i) nfr-metric 行: 可視 nid + category を row-scope で対突合 (§7e(c) の source-trace nid と非対称だった穴 + category 取り違え)。
exp_nfrrow="$(q '.nfr[] | [.id, .category] | @tsv' | while IFS=$'\t' read -r _id _cat; do printf '%s\t%s\n' "$(esc "$_id")" "$(esc "$_cat")"; done)"
act_nfrrow="$(perl -CSD -0777 -ne 'while (/<tr data-component="nfr-metric-row" id="[^"]*"><td><span class="nid">([^<]*)<\/span><\/td><td>([^<]*)<\/td>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "within-doc: nfr 行 (nid, category) == .nfr (順序)" "$exp_nfrrow" "$act_nfrrow"
# (j) rtm 行見出し: 可視要件 id + 行ラベル (span.lbl) を結合して順序突合 ((requirements+nfr) 順)。
#   ★round-3 ceiling: 旧 (j) は span.lbl のみ突合し rtm 行見出しの *要件 id* (emit_rtm_fold の <tr><th>{id}{lbl}</th>) を漏らし、
#   FR1→FR99 (RTM 表だけ別 id) が素通っていた。 行見出し全体 (id + 任意 lbl) を再構築し突合する (id と label を同時被覆)。
#   ★thead の <tr><th>要件</th> は </th> の後が <th class="grp"> ゆえ </th><td アンカーで除外 (tbody 行のみ捕捉)。
exp_rtmh="$(q '(.requirements + .nfr)[] | [.id, (.label // "")] | @tsv' | while IFS=$'\t' read -r _id _lb; do
  _l=""; [[ -n "$_lb" ]] && _l=" <span class=\"lbl\">$(esc "$_lb")</span>"; printf '%s%s\n' "$(esc "$_id")" "$_l"; done)"
# ★round-5 ceiling: タグ抽出を case-insensitive (/gi) に。 rtm 行見出しは class-less (<tr><th>) で count-parity 不能ゆえ
#   case-drop (<TR><TH>FR99) した偽行 + 同値 decoy で素通せた → /gi で偽行も抽出列に入れ順序/件数不一致で FAIL。
# ★folio-bur round-4 (ceiling-recursion R3 是正): 旧 <tr><th> literal アンカーは <tr><th id="z">FR99偽要件 等の
#   属性付き th 行見出しを見逃し、 捏造要件行注入が act_rtmh に乗らず素通った (独立 ceiling 実証)。 <th[^>]*> + \s* で
#   属性/空白を許容し、 注入行も抽出して順序突合で捕捉する (thead 行は </th> の後が <th> ゆえ </th>\s*<td アンカーで引き続き除外)。
# ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 は <th> 側のみ属性許容化し兄弟 <tr> を literal 据置だったため、
#   属性を tr 側に置いた <tr id="z9"><th>FR99 偽要件</th><td>… 行が抽出を逃れ捏造要件が RTM に素通った (独立 ceiling 実証・blocker)。
#   <tr[^>]*> で tr の属性も許容し、 注入行も抽出列に乗せ順序突合で捕捉する (round-4 自身の fix の anchor 不完全=self-un-certify 是正)。
act_rtmh="$(perl -CSD -0777 -ne 'while (/<tr[^>]*>\s*<th[^>]*>(.*?)<\/th>\s*<td/gi){ print "$1\n"; }' "$BODY")"
chk "within-doc: rtm 行見出し (id+ラベル) == (requirements+nfr) (順序)" "$exp_rtmh" "$act_rtmh"
# (j2) rtm 受入ドットの可視テキスト == data-acc-link の末尾 (__ 後) セグメント (ds8 不動点: attr と可視 echo の両方を列挙)。
#   ★round-3 ceiling: §5-6 は data-acc-link attr のみ set 突合し、 ドットの可視 id (AC1→AC999) を見ていなかった (attr↔可視の非対称)。
#   ★アンカーは class でなく *data-acc-link* (set_eq §6 が検証済の attr ゆえ件数も §6 が anchor)。 class 構文に非依存。
#   ★round-5 ceiling: 可視を [^<]* で取ると <b>AC999</b> ネストで空に縮退し </span> マッチ失敗 → 要素脱落 → chk_empty 未検査=pass。
#   marker-keyed (.*?) で span 全体を捕捉し『可視に < があれば NESTED=FAIL』で nested-content 偽装を構造的に封じる (ds8 不動点)。
# ★round-9 ceiling: data-acc-link を quote-robust に parse (旧 data-acc-link="..." は double-quote 固定で、 single-quote decoy
#   <span class="dot ac" data-acc-link='FR1__AC1'>AC999</span> の可視 id 捏造 (suffix≠visible) を素通した = round-8 ceiling 実証)。
acc_vis_bad="$(perl -CSD -0777 -e 'my $q=chr(39); my $t=<STDIN>; $t="" unless defined $t; my @b; while ($t =~ /\bdata-acc-link\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))[^>]*>(.*?)<\/span>/gs){ my $lk=defined $1?$1:(defined $2?$2:$3); my $v=$4; my ($s)=$lk=~/^.*__(.*)$/; $s="" unless defined $s; push @b,"NESTED:$s" if $v=~/</; push @b,"$s\x{2260}$v" if $v ne $s; } print join(" ",@b);' < "$BODY")"
chk_empty "within-doc: 受入ドット可視 == data-acc-link suffix (quote 非依存・nested-reject)" "$acc_vis_bad"
# (k) constraint: 可視 id (cid2) + label (cl) — plain leaf / 規制バッジ (reg-badge=「法令 {reg}」) — 非空 regulation のみ compound。 §7e は 7b で件数のみだった。
chk "within-doc: constraint.id (cid2) == .constraints[].id (順序)"    "$(qesc '.constraints[].id')"    "$(grep -oE '<td class="cid2">[^<]*</td>' "$BODY" | sed -E 's#<td class="cid2">([^<]*)</td>#\1#')"
chk "within-doc: constraint.label (cl) == .constraints[].label (順序)" "$(qesc '.constraints[].label')" "$(grep -oE '<td class="cl">[^<]*</td>' "$BODY" | sed -E 's#<td class="cl">([^<]*)</td>#\1#')"
exp_reg="$(q '.constraints[] | select((.regulation // "") != "") | .regulation' | while IFS= read -r _r; do printf '法令 %s\n' "$(esc "$_r")"; done)"
act_reg="$(grep -oE '<span class="reg-badge">[^<]*</span>' "$BODY" | sed -E 's#<span class="reg-badge">([^<]*)</span>#\1#')"
chk "within-doc: 規制バッジ (reg-badge) == 「法令 {reg}」 非空 (順序)" "$exp_reg" "$act_reg"
# (l) actor tint (可視色を駆動する attr var(--TINT)・CSS allowlist 限定) — (key, tint) 対で順序突合 (§7e(b) は key/name のみ)。
exp_tint="$(q '.actors[] | [.key, .tint] | @tsv' | while IFS=$'\t' read -r _k _t; do printf '%s\t%s\n' "$(esc "$_k")" "$(esc "$_t")"; done)"
act_tint="$(perl -CSD -0777 -ne 'while (/<span class="av" style="background:var\(--([^)]*)\)">([^<]*)<\/span>/g){ print "$2\t$1\n"; }' "$BODY")"
chk "within-doc: actor (key, tint) == .actors (順序)" "$exp_tint" "$act_tint"

# 7g. ★body prose テキスト値の floor 突合 (folio-4cf・dty round-2 ceiling wf_997ee765 繰延分): mark_terms 系自由文フィールド
#    (ears.condition/response・nfr.target/measure・acceptance.criterion・upper_needs.need・goals.desc・scope.in/out・
#     actor.role・constraint.text) の *可視テキスト値* を contract と順序突合する。 §7e/§7f は識別子・構造・数値・統制値のみ
#    被覆し、 本文 prose 値は無検証で 生成後の本文改竄 (見出し以外の自由文を詐欺文へ・例 goals.headline=ct は §7e 突合済だが
#    goals.desc=cd は未突合の非対称) が floor を素通った。 全て決定的 (esc + mark_terms) ゆえ floor 検証可能。
#    ★手法 (mark_terms の語境界ロジックを複製せず plain-text 等価比較): term-inline バッジ (内容は verify_term_inline §9 が別途検証済) を
#    *legit double-quote 形のみ* strip した working body を作り、 各セルの可視テキストを抽出 → esc(contract値) と順序突合。
#    バッジ strip 後は body prose 値に生 < が無い (esc 済) ゆえ全セルが [^<]* で取れる。 quote 逸脱/追加した偽バッジは strip されず
#    残って突合 FAIL = tamper は必ず落ちる。 ★decoy-add (single-quote/case-drop 偽セル追加) は §7f vcount 占有数パリティ
#    (cd/cond/resp/meas/at/role/b を count_attr_token で |contract| binding) が quote/case 非依存に封鎖 (ds8/dty 二層)。
STRIPPED="$(mktemp)"
perl -CSD -0777 -pe 's{<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>}{}g' "$BODY" > "$STRIPPED"
# (a) goals.desc (p.cd) — plain leaf・順序 = .goals[] 配列順
chk "body-prose: goals.desc (cd) == .goals[].desc (順序)" "$(qesc '.goals[].desc')" \
  "$(grep -oE '<p class="cd">[^<]*</p>' "$STRIPPED" | sed -E 's#<p class="cd">([^<]*)</p>#\1#')"
# (b) scope.in / scope.out — scol.in / scol.out ブロックに scope し全 li を抽出 (in↔out 越境移動も捕捉ゆえ分離・bullet 無し偽 li も拾う)。
# ★bullet span の strip は中身を [^<]* で取る (literal ● は perl -CSD のソース literal 非 decode で不一致になるため文字非依存に)。
# ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 で research が得た while+占有+region-recon idiom を §7g が未受領で、 (i) li 抽出が
#   first-match `if` ゆえ 2 個目の scol-in block を無視 (ii) scol/li 占有 anchor 不在、 で 2 個目 scol-in に bullet-less 偽 li
#   『全顧客の個人情報を無断で第三者に販売する』を入れた偽 in-scope 宣言が素通った (独立 ceiling 実証・blocker)。 research と同型に
#   while-global li 抽出 + region-text reconciliation (各 scol の全可視テキスト==見出し+全bullet・nested-div reject) で機械的完遂
#   (scol 占有==2 の占有 pin は mzn.3 Phase C で退役・repro-build byte-identity が block 追加 decoy を継承捕捉)。
exp_scin="$(qesc '.scope.in[]')"
act_scin="$(perl -CSD -0777 -ne 'while (/class="scol in">(.*?)<\/div>/gs){ my $b=$1; while($b=~/<li>(.*?)<\/li>/gs){ my $it=$1; $it=~s/^<span class="b">[^<]*<\/span>//; print "$it\n" } }' "$STRIPPED")"
chk "body-prose: scope.in (scol in の li) == .scope.in (順序)" "$exp_scin" "$act_scin"
exp_scout="$(qesc '.scope.out[]')"
act_scout="$(perl -CSD -0777 -ne 'while (/class="scol out">(.*?)<\/div>/gs){ my $b=$1; while($b=~/<li>(.*?)<\/li>/gs){ my $it=$1; $it=~s/^<span class="b">[^<]*<\/span>//; print "$it\n" } }' "$STRIPPED")"
chk "body-prose: scope.out (scol out の li) == .scope.out (順序)" "$exp_scout" "$act_scout"
# region-text reconciliation: 各 scol ブロックの全可視テキスト (タグ/空白除去) == 見出し + 連結 ●bullet。 非li/非b/arbitrary-wrapper 捏造・第2列・nested-div を封鎖。
exp_scin_rc="✓ 扱う (in scope)"; while IFS= read -r _b; do exp_scin_rc+="●$(esc "$_b")"; done < <(q '.scope.in[]')
exp_scout_rc="✕ 扱わない (out of scope)"; while IFS= read -r _b; do exp_scout_rc+="●$(esc "$_b")"; done < <(q '.scope.out[]')
scol_recon_bad="$(EXPIN="$exp_scin_rc" EXPOUT="$exp_scout_rc" perl -CSD -Mutf8 -0777 -ne '
  my $ei=$ENV{EXPIN}; utf8::decode($ei); $ei=~s/\s+//g; my $eo=$ENV{EXPOUT}; utf8::decode($eo); $eo=~s/\s+//g;
  my @bad; my ($nin,$nout)=(0,0);
  while (/<div class="scol in">(.*?)<\/div>/gs){ my $c=$1; $nin++; push @bad,"in:NESTED-DIV" if $c=~/<div\b/i; my $v=$c; $v=~s/<[^>]+>//g; $v=~s/\s+//g; push @bad,"in:TEXT\x{2260}".substr($v,0,30) if $v ne $ei; }
  while (/<div class="scol out">(.*?)<\/div>/gs){ my $c=$1; $nout++; push @bad,"out:NESTED-DIV" if $c=~/<div\b/i; my $v=$c; $v=~s/<[^>]+>//g; $v=~s/\s+//g; push @bad,"out:TEXT\x{2260}".substr($v,0,30) if $v ne $eo; }
  push @bad,"in:N=$nin" if $nin!=1; push @bad,"out:N=$nout" if $nout!=1;
  print join(" ",@bad);' "$STRIPPED")"
chk_empty "body-prose: scol region-text == 見出し+全bullet (非li/非b/arbitrary-wrapper 捏造・第2列・nested-div 封鎖・folio-bur r6)" "$scol_recon_bad"
# (c) actor.role — <div class="role"> (approval の <span class="role"> はタグで区別 = folio-mk9 chrome)
chk "body-prose: actor.role (div.role) == .actors[].role (順序)" "$(qesc '.actors[].role')" \
  "$(grep -oE '<div class="role">[^<]*</div>' "$STRIPPED" | sed -E 's#<div class="role">([^<]*)</div>#\1#')"
# (d) upper_needs.need — source-trace-row の 2 番目 td (id/origin は §7e(c) が突合)
exp_need="$(qesc '.upper_needs[].need')"
act_need="$(perl -CSD -0777 -ne 'while (/<tr data-component="source-trace-row"><td>.*?<\/td><td>([^<]*)<\/td>/g){ print "$1\n"; }' "$STRIPPED")"
chk "body-prose: upper_needs.need (source-trace 2nd td) == .upper_needs[].need (順序)" "$exp_need" "$act_need"
# (e) ears.condition (td.cond) — plain leaf
chk "body-prose: ears.condition (td.cond) == .requirements[].ears.condition (順序)" "$(qesc '.requirements[].ears.condition')" \
  "$(grep -oE '<td class="cond">[^<]*</td>' "$STRIPPED" | sed -E 's#<td class="cond">([^<]*)</td>#\1#')"
# (f) ears.response — td.resp *全体* を取り出し prose-slot span (plain/why) を strip した残余 == esc(response)。
#     ★slot 前のみ抽出だと why-slot 後ろ・</td> 前への text-node 追記 (post-gen tamper) を素通す (cell-quality WF
#       robustness-security finding 反映)。 slot 内容は §8 が別途検証ゆえ span 全体を strip し応答テキストだけを残す
#       → 他 9 フィールドの full-cell 抽出と対称化 (slot 前/間/後ろのどこへの追記も残余不一致で FAIL)。
exp_resp="$(qesc '.requirements[].ears.response')"
act_resp="$(perl -CSD -0777 -ne 'while (/<td class="resp">(.*?)<\/td>/gs){ my $c=$1; $c=~s/<span class="(?:plain|why)"[^>]*>[^<]*<\/span>//g; print "$c\n"; }' "$STRIPPED")"
chk "body-prose: ears.response (td.resp 全体・slot strip) == .requirements[].ears.response (順序)" "$exp_resp" "$act_resp"
# (g) nfr.target (span.tgt) — plain leaf (badge strip 後は nested span 無し)
chk "body-prose: nfr.target (span.tgt) == .nfr[].target (順序)" "$(qesc '.nfr[].target')" \
  "$(grep -oE '<span class="tgt">[^<]*</span>' "$STRIPPED" | sed -E 's#<span class="tgt">([^<]*)</span>#\1#')"
# (h) nfr.measure (td.meas) — plain leaf
chk "body-prose: nfr.measure (td.meas) == .nfr[].measure (順序)" "$(qesc '.nfr[].measure')" \
  "$(grep -oE '<td class="meas">[^<]*</td>' "$STRIPPED" | sed -E 's#<td class="meas">([^<]*)</td>#\1#')"
# (i) acceptance.criterion (p.at) — plain leaf
chk "body-prose: acceptance.criterion (p.at) == .acceptance[].criterion (順序)" "$(qesc '.acceptance[].criterion')" \
  "$(grep -oE '<p class="at">[^<]*</p>' "$STRIPPED" | sed -E 's#<p class="at">([^<]*)</p>#\1#')"
# (j) constraint.text — constraint-callout 行の 3 番目 td (reg-badge 前の構造空白も除外。 id/label は §7f(k) が突合)
exp_ctext="$(qesc '.constraints[].text')"
act_ctext="$(perl -CSD -0777 -ne 'while (/<td class="cid2">[^<]*<\/td><td class="cl">[^<]*<\/td><td>([^<]*?)(?: <span class="reg-badge"|<\/td>)/g){ print "$1\n"; }' "$STRIPPED")"
chk "body-prose: constraint.text (3rd td) == .constraints[].text (順序)" "$exp_ctext" "$act_ctext"
rm -f "$STRIPPED"

# ★scope 境界 (no silent caps・round-2 ceiling で honest 後退): §7e+§7f+§7g は SRS 本体の
#   *識別子・構造・数値・統制値* フィールド (id/fid/data-req-id/ears class+label/priority class+label/vmethod/nid/category/
#   metric_v·l/nfr-hero 数値/cid2/label/regulation/rtm 列見出し+行見出し id+行ラベル/受入ドット可視/tint/origin/goals headline+id/actor key+name) を
#   *三層* で完全列挙・突合する: (1) 順序突合 (chk) = 値・順序の改竄、 (2) ★count_attr_token 占有数パリティ (HTML 属性構文非依存 =
#   quote/case/数値文字参照を吸収・全 value class + 統制値 marker は global∧要件行内∧legend-scope の三項 binding・RTM dot は joint-token) =
#   case-drop+decoy/entity ghost/chrome relocation/attr-absent 偽 dot の add を封鎖、 (3) ★class-token 機械的網羅 (全 token が COUNTED|EXEMPT =
#   vcount allowlist drift を構造封鎖・将来の value class 追加を必ず FAIL) + acc-dot marker-keyed nested-reject。 round-5/6 ceiling の HTML 属性構文 robustness
#   兄弟 (nested-content / case-drop+decoy / legend relocation / entity-encoding) を全て決定論的に封じた。 ★さらに §7g (folio-4cf) で
#   **body prose テキスト値** (mark_terms 系の自由文: ears.condition/response・nfr.target/measure・acceptance.criterion・upper_needs.need・
#   goals.desc・scope.in/out・actor.role・constraint.text) を term-badge strip + 順序突合 (値) + vcount 占有数パリティ (decoy-add) の二層で被覆した
#   (dty round-2 ceiling 繰延分の解消)。 ★さらに **core 共通 chrome** (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・
#   glossary-term-table term/en/def) を §7b' で verify_core_chrome (lib/verify-common.sh・全 pack 共通) が値突合 + 占有数パリティ済 (folio-mk9 で
#   core 昇格・dty round-2 完全列挙が指した cross-pack count-only gap の解消)。 凡例の en/lt 可視ラベルは §7f legend-scope SET で被覆済 (folio-czo)・
#   glossary 表の en は §7b' verify_core_chrome が grow 行内で被覆。
#   (ds8 教訓#4: gate funnel が掘り当てた broad pre-existing gap を bolt-on せず追跡 follow-up へ → folio-mk9 で着地。 識別子/構造/本文 prose/chrome は floor・gate J=content fidelity ceiling)。

# 8. prose スロット (perl で要素単位判定 = ネストタグ/改行/空白のみを正しく捕捉)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne '
  my $c=0;
  while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs) {
    my $inner=$2; $inner =~ s/\s+//g; $c++ if length($inner);
  }
  print $c;
' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-44s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-44s\n' "prose スロットが無い"; fail=1; fi

if [[ -n "$ARTIFACT" ]]; then
  # artifact (成果物 floor): manifest 無しで prose 全充填のみ検査 (gate G の prose 部分)
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
elif [[ -z "$FILLED_MANIFEST" ]]; then
  # pre-fill: assembler が prose を一切捏造しないことの証明 (全スロット空)
  chk "prose スロットは全て空 (filled=0)" "0" "$filled"
else
  # post-fill: 全スロット非空 (no-TBD) + 各 data-slot-id の内容が escape 済み manifest 値と一致 (注入忠実)
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  exp="$(mktemp)"; act="$(mktemp)"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    printf '%s\t%s\n' "$key" "$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST") | sort > "$exp"
  perl -0777 -ne 'while (/<([a-zA-Z]+)\b[^>]*\bdata-slot-id="([^"]+)"[^>]*>(.*?)<\/\1>/gs){ print "$2\t$3\n"; }' "$BODY" | sort > "$act"
  if diff -q "$exp" "$act" >/dev/null 2>&1; then
    printf '  [OK]   %-44s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-44s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ (脱落/改竄前) ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ (orphan/改竄後) ---";   comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# 9. plain-language-term-inline (glossary 派生ビュー、 ADR-0042 §2.2 A) の fidelity + 用語被覆 (両モード共通)。
#    実装は core (verify-common.sh の verify_term_inline)。 markable フィールド集合は SRS-pack 固有ゆえ
#    ここで yq 式を渡す (★この yq リストは assemble-srs の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.goals[].desc, .scope.in[], .scope.out[], .actors[].role, .upper_needs[].need, .requirements[].ears.condition, .requirements[].ears.response, .nfr[].target, .nfr[].measure, .acceptance[].criterion, .constraints[].text' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語、 同一語境界)"



echo
if [[ -n "$ARTIFACT" ]]; then
  if [[ "$fail" -eq 0 ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + term-inline 派生 + prose 全充填 = 成果物 floor の構造部)"; exit 0
  else echo "RESULT: FAIL"; exit 1; fi
elif [[ -n "$FILLED_MANIFEST" ]]; then
  if [[ "$fail" -eq 0 ]]; then echo "RESULT: filled PASS (構造は contract から完全導出・捏造 0 + prose 全充填・注入忠実 = 改竄/脱落/out-of-band なし)"; exit 0
  else echo "RESULT: FAIL"; exit 1; fi
else
  if [[ "$fail" -eq 0 ]]; then echo "RESULT: fabrication-free PASS (構造は contract から完全導出・捏造 0、 backward/acceptance 両軸・派生数値・prose 空 を被覆)"; exit 0
  else echo "RESULT: FAIL"; exit 1; fi
fi
