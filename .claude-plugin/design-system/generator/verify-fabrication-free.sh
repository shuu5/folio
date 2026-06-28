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
#      値突合 + 占有数パリティ (folio-mk9・lib/verify-common.sh の verify_core_chrome)。 上の件数のみ検証 (件数 OK でも値改竄が
#      素通る fail-open) を全 pack 共通で塞ぐ cross-pack gap の解消 (dty round-2 完全列挙が発見・ADR/research も同型 gap)。
verify_core_chrome
# 7b''. ★SRS-pack 固有 reader-chip 占有数 (folio-mk9 self-review round-5): SRS は cross_doc を持たず cross-doc-ref-chip を emit しない
#   ゆえ reader-chip class を持つ要素は genuine reader-chip ちょうど 1 個のみ。 core の count_genuine_reader_chip (ref-chip 除外・要素単位)
#   は『class="reader-chip" data-component="cross-doc-ref-chip">任意 text』の additive decoy を ref-chip 側へ分類し genuine count を増やさず、
#   global『想定読者:』marker も marker 無し text なら不変ゆえ、 SRS では偽 ref-chip (= 捏造 chrome box) が verify を素通った
#   (ADR/research は cross-doc-ref-chip ブロック==1 を別途 bind ゆえ既に捕捉・SRS のみ ref-chip count 検証が無かった)。
#   SRS の reader-chip class 総数 == 1 (quote-robust) を bind し、 ref-chip 構文を借りた捏造 reader-chip box を封鎖する。
chk "core-chrome(SRS): reader-chip class 総数 == 1 (cross_doc 無し=ref-chip 不在)" "1" "$(count_attr_token class reader-chip < "$BODY")"

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
# ★marker 占有数パリティ (ds8 不動点)。 (h) の row-scope タプルは非貪欲 .*? ゆえ resp セルへデコイ (第2 prio/vmeth/fid 対) を
#   注入すると末尾の正規対を拾い可視虚偽を素通す (second-element-injection)。 占有数で塞ぐ。 ★occurrence で数える (grep -c は
#   複数同一行を 1 と数える line-count gotcha = legend の 4 ears 等を過少計上 → grep -oE | wc -l)。
#   ★round-3 ceiling (wf_97d52cb2) 反映: (a) ★quote 非依存 — assembler は double-quote のみ emit ゆえ single-quote ghost
#   (class='fid') は tamper の証拠だが double-quote literal grep を素通る → char class [\"'] で両受容。 (b) ★統制値も global —
#   prio-badge/vmeth/ears を要件行内 scope にすると req-row|legend 以外の chrome (h2 等) への ghost 注入を見逃す (fid/nid global との
#   非対称) → legend 静的 chip 数 (prio-badge 1 / vmeth 4 / ears 4 = emit_legend の固定本数・detect↔remediate parity) を足した global occurrence で突合。
# ★count は core の count_attr_token (quote 構文・属性名 case 非依存の token-match)。 grep "class=\"fid\"" は
#   single-quote/unquoted/multi-class/大文字属性名の ghost を素通す (round-4 ceiling 兄弟)。 token-match で不動点化。
# ★統制値は *可視 styling の class token* で数える (CSS は .fid/.nid/.prio/.ears/.vmeth で描画・data-component は metadata)。
#   priority を data-component="priority-badge" で数えると class-prio-only ghost (legend 推奨と同型・data-component 無しでも
#   .prio で描画される偽バッジ) を素通す → 可視 class "prio" で数える (legend は must+should の 2 本)。
nreq="$(q '.requirements | length')"
chk "marker: fid 占有 == |requirements| (token global)"        "$nreq"                                            "$(count_attr_token class fid < "$BODY")"
chk "marker: nid 占有 == |upper_needs|+|nfr| (token global)"    "$(q '(.upper_needs | length) + (.nfr | length)')"  "$(count_attr_token class nid < "$BODY")"
chk "marker: prio 占有 == |requirements|+2(legend, global)"     "$((nreq + 2))"                                    "$(count_attr_token class prio < "$BODY")"
chk "marker: vmeth 占有 == |requirements|+4(legend, global)"    "$((nreq + 4))"                                    "$(count_attr_token class vmeth < "$BODY")"
chk "marker: ears 占有 == |requirements|+4(legend, global)"     "$((nreq + 4))"                                    "$(count_attr_token class ears < "$BODY")"
# ★統制値は global (chrome ghost) に加え *要件行内* occurrence も == |requirements| で二重に縛る。 global だけだと
#   『legend chip を 1 個削除し req 行へ偽 badge を 1 個足す』count 保存攻撃 (global 不変・tuple は末尾を拾う) を素通す
#   (round-4 自己予見の兄弟)。 row-scope は legend と独立に req 行側を binding し add-row を必ず捕捉する。
reqrows="$(grep 'data-component="ears-requirement-row"' "$BODY")"
chk "marker: 要件行内 prio 占有 == |requirements|"  "$nreq" "$(printf '%s\n' "$reqrows" | count_attr_token class prio)"
chk "marker: 要件行内 vmeth 占有 == |requirements|" "$nreq" "$(printf '%s\n' "$reqrows" | count_attr_token class vmeth)"
chk "marker: 要件行内 ears 占有 == |requirements|"  "$nreq" "$(printf '%s\n' "$reqrows" | count_attr_token class ears)"
# ★round-5 ceiling: legend-scope の独立 binding。 統制値 global は req-rows+legend 定数の和ゆえ『legend chip 削除 + chrome 注入』で
#   global/row-scope を保存したまま偽バッジを chrome (h2 等) へ描画できた (count-conservation relocation)。 emit_legend は静的ゆえ
#   ears-legend ブロック内の prio/vmeth/ears 占有数を固定本数 (2/4/4) に厳密 binding する = global・row-scope(req)・legend-scope の三項を
#   両端で独立に縛り relocation を legend-scope drop で必ず捕捉 (legend wrapper の大文字化は legendblk 空→0 不一致で FAIL)。
legendblk="$(grep 'class="ears-legend"' "$BODY")"
chk "legend-scope: prio == 2 (must+should)" "2" "$(printf '%s\n' "$legendblk" | count_attr_token class prio)"
chk "legend-scope: vmeth == 4 (T/A/I/D)"    "4" "$(printf '%s\n' "$legendblk" | count_attr_token class vmeth)"
chk "legend-scope: ears == 4 (4 type chip)" "4" "$(printf '%s\n' "$legendblk" | count_attr_token class ears)"
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
# ★dty round-5 ceiling (wf_ad9f22bc): value-internal class の count-parity (count_attr_token = case/quote/entity 非依存)。
#   下の ordered 値突合 (§7e/§7f) は小文字 class grep ゆえ『case-drop (class="CT") した偽要素 + 同値 decoy (class="ct")』で
#   抽出列を保存したまま可視捏造を素通せた (round-5 ceiling blocker)。 占有数 (decoy=+1・entity ghost=+1) を robust counter で
#   突合して add 方向を封鎖する (ds8 不動点)。 値そのものの改竄は下の ordered 突合が担う = 二層。
ngoal="$(q '.goals | length')"; nact="$(q '.actors | length')"; nun="$(q '.upper_needs | length')"
ncon="$(q '.constraints | length')"; nacc="$(q '.acceptance | length')"; nhero="$(q '[.nfr[] | select(.hero)] | length')"
chk "vcount: ct == |goals|"          "$ngoal" "$(count_attr_token class ct < "$BODY")"
chk "vcount: cid == |goals|"         "$ngoal" "$(count_attr_token class cid < "$BODY")"
chk "vcount: card == |goals|"        "$ngoal" "$(count_attr_token class card < "$BODY")"
chk "vcount: av == |actors|"         "$nact"  "$(count_attr_token class av < "$BODY")"
chk "vcount: nm == |actors|"         "$nact"  "$(count_attr_token class nm < "$BODY")"
chk "vcount: grp == |upper_needs|"   "$nun"   "$(count_attr_token class grp < "$BODY")"
chk "vcount: lbl == |labeled req+nfr|" "$(q '[(.requirements + .nfr)[] | select((.label // "") != "")] | length')" "$(count_attr_token class lbl < "$BODY")"
chk "vcount: cl == |constraints|"    "$ncon"  "$(count_attr_token class cl < "$BODY")"
chk "vcount: cid2 == |constraints|"  "$ncon"  "$(count_attr_token class cid2 < "$BODY")"
chk "vcount: reg-badge == |非空 regulation|" "$(q '[.constraints[] | select((.regulation // "") != "")] | length')" "$(count_attr_token class reg-badge < "$BODY")"
chk "vcount: aid == |acceptance|"    "$nacc"  "$(count_attr_token class aid < "$BODY")"
chk "vcount: metric == |acceptance|" "$nacc"  "$(count_attr_token class metric < "$BODY")"
chk "vcount: cat == |nfr(hero)|"     "$nhero" "$(count_attr_token class cat < "$BODY")"
chk "vcount: qual == |nfr(hero)|"    "$nhero" "$(count_attr_token class qual < "$BODY")"
chk "vcount: big == |nfr(hero)|"     "$nhero" "$(count_attr_token class big < "$BODY")"
chk "vcount: u == |nfr(hero)|"       "$nhero" "$(count_attr_token class u < "$BODY")"
# ★round-6 ceiling: vcount allowlist の drift で漏れていた origin/cover-meta(k/v)/RTM dot を追加 (case-drop+decoy / attr-absent 偽 dot を封鎖)。
chk "vcount: origin == |upper_needs|" "$nun" "$(count_attr_token class origin < "$BODY")"
chk "vcount: cover-meta k == 4"       "4"    "$(count_attr_token class k < "$BODY")"
chk "vcount: cover-meta v + metric v == 4+|acceptance|" "$((4 + nacc))" "$(count_attr_token class v < "$BODY")"
chk "vcount: tgt == |nfr|"           "$(q '.nfr | length')" "$(count_attr_token class tgt < "$BODY")"
# RTM 可視ドット: data-*-link 属性 absent の偽ドット (class だけで .dot.ac 緑 pill 描画) を封鎖。 §5/§6 は attr のみ anchor ゆえ素通った。
#   joint-token: dot∧ac == data-acc-link 出現数 (受入) / dot∧¬ac == data-trace-link 出現数 (後方●)。 ('ac' 単独は受入カード class="ac" と衝突ゆえ joint 必須)
# ★round-7 ceiling: dot joint-token は quote-robust な class_tokens 経由で数える (旧 inline perl は double-quote 固定ゆえ
#   single-quote/unquoted の偽 dot を素通した — .rtm td .dot.ac は class 名 match=quote 非依存ゆえ偽緑 pill が実描画される)。
chk "vcount: dot∧ac == |data-acc-link|"   "$(grep -o 'data-acc-link=' "$BODY" | wc -l | tr -d ' ')"   "$(class_tokens < "$BODY" | awk '{d=a=0;for(i=1;i<=NF;i++){if($i=="dot")d=1;if($i=="ac")a=1}if(d&&a)c++}END{print c+0}')"
chk "vcount: dot∧¬ac == |data-trace-link|" "$(grep -o 'data-trace-link=' "$BODY" | wc -l | tr -d ' ')" "$(class_tokens < "$BODY" | awk '{d=a=0;for(i=1;i<=NF;i++){if($i=="dot")d=1;if($i=="ac")a=1}if(d&&!a)c++}END{print c+0}')"
chk "vcount: l == |acceptance| (metric_l)" "$nacc" "$(count_attr_token class l < "$BODY")"
# ★folio-4cf: body prose 系自由文フィールドの値 class も占有数パリティ (§7g の順序突合と二層)。 case-drop+decoy/quote 逸脱で
#   偽セルを add する攻撃を quote/case 非依存に封鎖する (cd/cond/resp/meas/at は doc-type 別 1 対 1・role は actor+approval 共有・b は scope bullet)。
chk "vcount: cd == |goals|"          "$ngoal" "$(count_attr_token class cd < "$BODY")"
chk "vcount: cond == |requirements|" "$nreq"  "$(count_attr_token class cond < "$BODY")"
chk "vcount: resp == |requirements|" "$nreq"  "$(count_attr_token class resp < "$BODY")"
chk "vcount: meas == |nfr|"          "$(q '.nfr | length')" "$(count_attr_token class meas < "$BODY")"
chk "vcount: at == |acceptance|"     "$nacc"  "$(count_attr_token class at < "$BODY")"
chk "vcount: role == |actors|+|approval|" "$((nact + $(q '.approval | length')))" "$(count_attr_token class role < "$BODY")"
chk "vcount: b == |scope.in|+|scope.out|" "$(q '(.scope.in | length) + (.scope.out | length)')" "$(count_attr_token class b < "$BODY")"
# ★round-6 ceiling 根本 fix: vcount allowlist drift の *構造封鎖*。 上の vcount は手選別ゆえ drift する (origin/k/v/dot が漏れていた)。
#   body の全 class token は COUNTED (占有数パリティ済の value class) か EXEMPT (構造/modifier/繰延 prose·chrome) のいずれかに *機械的に* 分類されねばならない。
#   未分類トークン = 将来の value class 追加 (enumeration drift) を必ず FAIL し count-parity 追加 (COUNTED 登録) を強制する = allowlist drift を構造的に検出。
#   ★EXEMPT は非 field の構造/modifier と、 明示繰延 (prose slot=opus 充填 §8: why/plain)。
# ★folio-4cf: body prose 値 class (cd/at/resp/cond/meas/role/b) を EXEMPT → COUNTED へ移した (§7g で値を順序突合 + ここで占有数パリティ)。
# ★folio-mk9: core 共通 chrome の value class (doc-type/cover-eyebrow/cover-sub・sign/who/when/stamp・grow/gword/gdef) を
#   EXEMPT → COUNTED へ移した。 verify_core_chrome (§7b') が値を順序突合 + 占有数パリティ済 (global) ゆえ「明示繰延」ではなくなった。
#   ★en は EXEMPT 維持: glossary 表 (verify_core_chrome が grow 行内で占有数突合) と EARS legend (folio-czo の legend-scope SET) で
#     class 共有ゆえ *global* vcount は不可 (両 scope の和になる)。 両 scope で個別に被覆済。
#   ★folio-mk9 self-review round-5: reader-chip を EXEMPT → COUNTED へ移した。 ADR/research では cross-doc-ref-chip が同 class を再利用
#     (global 2 個) ゆえ class count 不可だが、 SRS は cross_doc を持たず ref-chip を emit しないため reader-chip class 総数 == 1 (§7b'') で
#     global 占有数を bind 済 (ref-chip 構文を借りた捏造 reader-chip box を封鎖)。 reader 値は verify_core_chrome が別途突合。
COUNTED="fid nid prio vmeth ears ct cid card av nm grp lbl cl cid2 reg-badge aid metric cat qual big u origin k v tgt l dot ac rtm-summary-derived cd cond resp meas at role b doc-type cover-eyebrow cover-sub sign who when stamp grow gword gdef reader-chip"
# ★EXEMPT = 非 field の構造/modifier + 明示繰延 (prose slot=§8) + 共有 class (en は scope 別被覆)。
# ★round-9 ceiling: rtm-summary-derived は可視 contract 値 (派生 5 数値) を運ぶゆえ EXEMPT から外し COUNTED へ移した。
#   round-8 は値突合 chk (下) は追加したが EXEMPT に残したため占有数パリティが無く、 single-quote decoy の偽 <p> 追記
#   (real を無傷に残し別 <p class='rtm-summary-derived'>孤立要件 999件</p> を併置) を網羅検査も値突合 (double-quote 固定) も素通した。
#   COUNTED 化で count_attr_token 占有数 == 1 を強制し decoy-append を quote 非依存に封鎖する。
EXEMPT="accent actor always trigger state forbid option must should hit self in out c1 c2 c3 c4 tint-brand tint-info tint-ok tint-violet tint-warn page tbl-wrap cover-meta summary-card ic lab txt chapbody kicker lead num ico foot ft-grid tags rtm rtm-fold scol ears-legend lt m ext-badge nfr-hero why plain term en"
# ★quote-robust: class_tokens 経由 (旧 inline perl は double-quote 固定で single/unquoted novel token を分類漏れ = drift 構造封鎖の overclaim)。
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $COUNTED $EXEMPT | sort -u) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が COUNTED|EXEMPT (未分類=enumeration drift)" "$unknown_cls"
# ★folio-bur round-6 (ceiling-recursion R5 是正): EXEMPT 静的 chrome は占有数も値も未 pin ゆえ duplicate-decoy
#   (2 個目 <p class="lab">緊急: …全顧客データを自動削除…</p>) で誤誘導ラベルが素通った (独立 ceiling 実証・major)。
#   意味的に単数の lab を占有==1 で封鎖。 ★per-chapter EXEMPT chrome (kicker/num/chapbody/lead/m/why=章構造依存 cardinality) の
#   体系的占有 binding は folio-czo-class static-chrome follow-up (folio-bur 後続) へ繰延 (chapter 構造由来 count の慎重な導出が要・major)。
chk "占有: lab == 1 (duplicate 静的 chrome decoy 封鎖・folio-bur r6)" "1" "$(count_attr_token class lab < "$BODY")"
# ★round-7 ceiling: rtm-summary-derived の *可視* 5 数値 (要件/上位ニーズ/トレースリンク/孤立/未検証) を再導出突合 (§7 は data-derived
#   *属性* のみ・可視テキストはどの層も突合せず EXEMPT で素通った misclassification = 決定的 contract 値の捏造が可能だった)。
# ★round-9 ceiling: 占有数パリティ (count_attr_token == 1・quote 非依存) で偽 <p> 追記を封鎖 + 値抽出を quote-robust 化
#   (旧 <p class="rtm-summary-derived" は double-quote 固定で single-quote real を見失い、 decoy 併置を素通した)。
rtm_nreq="$(q '(.requirements + .nfr) | length')"; rtm_nneed="$(q '.upper_needs | length')"
rtm_nlinks="$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"
rtm_niso="$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')"
rtm_nunv="$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')"
exp_rtmsum="要件 ${rtm_nreq} 件 / 上位ニーズ ${rtm_nneed} 件 / トレースリンク ${rtm_nlinks} 本 / 孤立要件 (出所なし) ${rtm_niso} 件 / 未検証要件 (受入なし) ${rtm_nunv} 件"
chk "vcount: rtm-summary-derived == 1 (decoy 追記封鎖)" "1" "$(count_attr_token class rtm-summary-derived < "$BODY")"
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
# (j3) ★folio-bur: 後方トレースドット (data-trace-link) の可視テキスト == ● 固定記号 (acc ドット j2 と対称・visible-text-vs-attribute)。
#   §5-6 は data-trace-link attr のみ set 突合し、 上の dot∧¬ac は class+attr 件数のみ → attr/class/件数 intact のまま
#   ●→"N-3" 等の捏造 need ID を表示でき読者がトレース関係を誤読する fail-open が残った (folio-bur audit 実証)。
#   acc j2 と同じ quote-robust + marker-keyed (.*?) + nested-reject (可視に < があれば NESTED=FAIL) で封じる。
backdot_vis_bad="$(perl -CSD -0777 -e 'my $q=chr(39); my $t=<STDIN>; $t="" unless defined $t; my @b; while ($t =~ /\bdata-trace-link\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))[^>]*>(.*?)<\/span>/gs){ my $lk=defined $1?$1:(defined $2?$2:$3); my $v=$4; push @b,"NESTED:$lk" if $v=~/</; push @b,"$lk\x{2260}$v" if $v ne "\x{25CF}"; } print join(" ",@b);' < "$BODY")"
chk_empty "within-doc: 後方トレースドット可視 == ● 固定記号 (quote 非依存・nested-reject・folio-bur)" "$backdot_vis_bad"
# ★folio-bur round-2 (ceiling-recursion 是正): j3 は data-trace-link span の *内側* しか見ないため、 (A) span は intact のまま
#   同一セルに sibling text-node (` N-3`) を追記 / (B) 空セル <td></td> に裸 ● グリフを置く、 で偽 need ID/偽トレースを描画でき
#   素通った (独立 ceiling 実証)。 ds8 不動点 = full-cell remainder (セル全体が canonical 形と完全一致) + ● glyph 占有数パリティ。
# (j3a) 後方トレースセル full-cell: data-trace-link を含む各 <td> 内容が canonical span と完全一致 (sibling text-node を封鎖)。
backdot_cell_bad="$(perl -CSD -0777 -ne 'my @b; while (/<td\b[^>]*>(.*?)<\/td>/gs){ my $c=$1; next unless $c=~/data-trace-link/; my $lk=""; if($c=~/data-trace-link\s*=\s*"([^"]*)"/){$lk=$1} push @b,"BADCELL" unless $c eq "<span class=\"dot\" data-trace-link=\"$lk\">\x{25cf}</span>"; } print join(" ",@b);' < "$BODY")"
chk_empty "RTM 後方トレースセル == canonical-dot span のみ (sibling text-node 封鎖・folio-bur r2)" "$backdot_cell_bad"
# (j3b) ● glyph 占有数パリティ: BODY 中の literal ● 総数 == data-trace-link 数 (後方ドット) + class=b 数 (scope バレット)。
#   acc ドットは可視が AC suffix で ● を使わない。 裸 ● グリフ (B) は trace-link/class=b を伴わず総数を +1 し FAIL に倒す。
chk "● glyph 占有 == data-trace-link + class=b (裸 ● 封鎖・folio-bur r2)" \
  "$(( $(grep -o 'data-trace-link=' "$BODY" | wc -l) + $(count_attr_token class b < "$BODY") ))" \
  "$(grep -o '●' "$BODY" | wc -l | tr -d ' ')"
# (j3c) ★folio-bur round-3 (ceiling-recursion R2 是正): RTM (table.rtm) の空セル <td></td> は class/glyph/attr を持たぬ
#   自由 fabrication 面で、 j3a (data-trace-link を含むセルのみ検査・next unless) も §5-6 (attr set) も class-token 網羅も拾わず、
#   ⚫(U+26AB confusable・グリフ占有数を欺く)/N-9 (裸テキスト) 等の捏造を空セルに直書きする無痕跡な偽トレースが素通った
#   (独立 ceiling 実証・blocker)。 partition 不変条件: table.rtm の全 <td> は {空 / canonical trace-dot / canonical acc-dot} に限る
#   (それ以外=BADCELL)。 これがグリフ占有数パリティの射程外 (confusable / 裸テキスト) を構造的に封じる根治。
# ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 の j3c は `<table class="rtm">` literal anchor + `if` 先頭マッチで、
#   (a) 表タグを single-quote/空白化 (<table class='rtm'> / <table class="rtm" >) すると anchor が外れ partition が vacuous-pass
#   (b) 2 個目の <table class="rtm"> を追記すると先頭マッチのみゆえ捏造表を無検査、 で空セル自由 fab が再開した (独立 ceiling 実証・blocker)。
#   quote-robust に class トークン rtm を持つ *全* table を while 列挙 (glossary container 同型) + table.rtm 占有数==1 で複数表 decoy も封鎖。
# ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 の partition は (a) outer `<table\b`/inner `<td\b` が case-sensitive ゆえ
#   大文字 <TABLE>/<TD> セルが BADCELL 分類を逃れ任意捏造トレースが RTM 流入 (b) outer 非貪欲 (.*?)</table> が入れ子 <table></table> で
#   early-term し truncation 後の捏造 <td> 未 partition (ds8 nested-same-tag 機構の <table> 再発)、 で空セル自由 fab が 2 vector で再開した
#   (独立 ceiling 実証・blocker)。 outer/inner を /i 化 + nested-table-reject (rtm 表本体に <table 開タグがあれば即 BADCELL) + 下の開閉平衡で機械的完全化。
rtm_cell_bad="$(perl -CSD -0777 -ne 'my $q=chr(39); my @b; while(/<table\b([^>]*)>(.*?)<\/table>/gis){ my ($a,$tbl)=($1,$2); my $cls=""; if($a=~/\bclass\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/i){$cls=defined $1?$1:(defined $2?$2:$3)} $cls=~s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $cls=~s/&#(\d+);/chr($1)/ge; next unless grep { lc($_) eq "rtm" } split(/\s+/,$cls); push @b,"NESTED-TABLE" if $tbl=~/<table\b/i; while($tbl=~/<td\b[^>]*>(.*?)<\/td>/gis){ my $in=$1; next if $in eq ""; next if $in=~/^<span class="dot" data-trace-link="[^"]*">\x{25cf}<\/span>$/; next if $in=~/^<span class="dot ac" data-acc-link="[^"]*">[^<]*<\/span>$/; push @b, substr($in,0,24); } } print join(" | ",@b);' "$BODY")"
chk_empty "RTM 全 <td> ∈ {空 / canonical trace-dot / canonical acc-dot} (空セル自由 fab・confusable・大文字 td・nested-table 封鎖・quote-robust 列挙・folio-bur r3/r4/r5)" "$rtm_cell_bad"
chk "table.rtm 占有 == 1 (複数 table.rtm decoy 封鎖・folio-bur r4)" "1" "$(count_attr_token class rtm < "$BODY")"
chk "table 開閉タグ平衡 (stray </table> truncation 封鎖・folio-bur r5)" "$(grep -oiE '<table\b' "$BODY" | wc -l | tr -d ' ')" "$(grep -oiE '</table\b' "$BODY" | wc -l | tr -d ' ')"
# ★folio-bur round-6 (ceiling-recursion R5 是正): act_rtmh (L326) は <th> に td が続く行のみ抽出するため、 td 無しの <th> 単独行
#   (<tr><th class="lt">FR99 偽要件</th></tr>・class lt は EXEMPT) を rtm tbody へ注入すると act_rtmh も partition (td のみ列挙) も見ず
#   偽要件が RTM に描画され素通った (独立 ceiling 実証・blocker)。 rtm table 内 <tr> 総数 == 1(thead) + |requirements+nfr| を pin し
#   phantom 行 (th-only 含む) を行数で封鎖 (act_rtmh の th-only 死角の構造的 backstop)。
chk "rtm table 内 <tr> == 1 + |requirements+nfr| (th-only phantom 行封鎖・folio-bur r6)" \
  "$(( 1 + $(q '(.requirements + .nfr) | length') ))" \
  "$(perl -CSD -0777 -ne 'my $q=chr(39); my $n=0; while(/<table\b([^>]*)>(.*?)<\/table>/gis){ my ($a,$tbl)=($1,$2); my $cls=""; if($a=~/\bclass\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/i){$cls=defined $1?$1:(defined $2?$2:$3)} next unless grep { lc($_) eq "rtm" } split(/\s+/,$cls); $n++ while $tbl=~/<tr\b/gi; } print $n' "$BODY")"
# (j3d) per-source ● パリティ: scope バレット (class=b) の各 span 内 ● 数 == |class=b| — バレットから ● を略奪し別所 (comment 等)
#   へ funding する count-conservation relocation を封鎖 (round-4/5 ceiling の per-source 分割を ● パリティへ横展開)。
chk "● in class=b == |class=b| (scope バレット ● 略奪封鎖・folio-bur r3)" "$(count_attr_token class b < "$BODY")" "$(perl -CSD -0777 -ne 'my $n=0; while(/<span class="b">(.*?)<\/span>/gs){$n++ if $1 eq "\x{25cf}"} print $n' "$BODY")"
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
#   while-global li 抽出 + scol 占有==2 + region-text reconciliation (各 scol の全可視テキスト==見出し+全bullet・nested-div reject) で機械的完遂。
chk "占有: class=scol == 2 (scol ブロック追加 quote-robust 封鎖・folio-bur r6)" "2" "$(count_attr_token class scol < "$BODY")"
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
# (c) data-component enumeration (srs は class を COUNTED/EXEMPT で網羅済・dc を新規追加で foreign dc 封鎖)。
R7_DC="acceptance-criteria-checklist actor-stakeholder-table approval-block chapter-deck-band constraint-callout doc-cover-band ears-requirement-row fidelity-sync-meta glossary-term-table nfr-hero-metrics nfr-metric-row nfr-metrics-table plain-language-term-inline priority-badge requirement-matrix-table requirement-type-color-tokens rtm-collapse rtm-grid scope-summary-panel section-lead-callout source-trace-origin source-trace-row"
chk_empty "enumeration(r7): 全 data-component が allowlist (foreign dc 封鎖)" \
  "$(attr_values data-component < $BODY | grep . | sort -u | grep -vxF -f <(printf '%s\n' $R7_DC) | tr '\n' ' ' | sed 's/ *$//')"
# (d) occupancy-from-contract: 各 allowlist token の occupancy == contract 導出個数 (grouped loop)。
EXP="$(q '(.acceptance | length) + ([(.requirements + .nfr)[].trace.acceptance[]] | length)')"; for t in ac; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '.actors | length')"; for t in actor; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '[.actors[] | select(.external == true)] | length')"; for t in ext-badge; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '[.nfr[] | select(.hero)] | length')"; for t in nfr-hero; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '(.requirements | length) + (.nfr | length)')"; for t in plain; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '.requirements | length')"; for t in why; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=9; for t in chapbody kicker lead num ico; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in page cover-meta summary-card ic txt foot ft-grid tags rtm-fold ears-legend; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=4; for t in m; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=3; for t in lt; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=3; for t in tbl-wrap; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=3; for t in tint-brand; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=2; for t in tint-info tint-violet; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in tint-ok tint-warn; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in acceptance-criteria-checklist actor-stakeholder-table approval-block constraint-callout doc-cover-band fidelity-sync-meta glossary-term-table nfr-hero-metrics nfr-metrics-table requirement-matrix-table requirement-type-color-tokens rtm-collapse rtm-grid scope-summary-panel section-lead-callout source-trace-origin; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP=9; for t in chapter-deck-band; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '(.requirements | length) + 1')"; for t in priority-badge; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.requirements | length')"; for t in ears-requirement-row; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.nfr | length')"; for t in nfr-metric-row; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.upper_needs | length')"; for t in source-trace-row; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
# (e) term-inline 占有: bare <span class="term"> 注入を封鎖 (class term == data-component plain-language-term-inline・
#     構造化 badge は verify_term_inline が glossary 突合済)。
chk "占有(r7): term == plain-language-term-inline (bare .term 注入封鎖)" \
  "$(count_attr_token data-component plain-language-term-inline < "$BODY")" "$(count_attr_token class term < "$BODY")"
# ===== folio-bur round-7 ここまで =====

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
