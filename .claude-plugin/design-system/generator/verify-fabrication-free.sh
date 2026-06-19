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
act_b="$(grep -oE 'data-trace-link="[^"]+"' "$BODY" | sed 's/.*data-trace-link="//; s/"$//' | sort)"
chk     "backward link count == Σ unique backward" "$(printf '%s\n' "$exp_b" | grep -c .)" "$(printf '%s\n' "$act_b" | grep -c .)"
set_eq  "backward link SET == contract" "$exp_b" "$act_b"

# 6. acceptance (受入) リンク集合 == contract (backward と対称)
exp_a="$(q '(.requirements + .nfr)[] | .id as $i | (.trace.acceptance | unique)[] | $i + "__" + .' | sort)"
act_a="$(grep -oE 'data-acc-link="[^"]+"' "$BODY" | sed 's/.*data-acc-link="//; s/"$//' | sort)"
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
# (h) ★要件行の主要識別子+意味種別を 1 タプルで row-scope 突合: data-req-id・fid・ears(class,label)・priority(class,label)・vmethod。
#     ★blocker 封鎖: fid/data-req-id を contract id と突合し 可視↔attr↔contract の三者一致を強制 (consistent rename = FR1→FR99 を封鎖)。
exp_reqrow="$(q '.requirements[] | [.id, .ears.pattern, .priority, .vmethod] | @tsv' | while IFS=$'\t' read -r _id _pat _pr _vm; do
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(esc "$_id")" "$(esc "$_id")" "${DTY_EARS_CLASS[$_pat]}" "${DTY_EARS_LABEL[$_pat]}" "$_pr" "${DTY_PRIO_LABEL[$_pr]}" "$(esc "$_vm")"; done)"
act_reqrow="$(perl -CSD -0777 -ne 'while (/<tr data-component="ears-requirement-row" data-req-id="([^"]*)"><td><span class="fid">([^<]*)<\/span><\/td><td><span class="ears ([a-z]+)">([^<]*)<\/span><\/td>.*?<span class="prio ([a-z]+)" data-component="priority-badge">([^<]*)<\/span> <span class="vmeth">([^<]*)<\/span><\/td><\/tr>/g){ print "$1\t$2\t$3\t$4\t$5\t$6\t$7\n"; }' "$BODY")"
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
chk "vcount: dot∧ac == |data-acc-link|" "$(grep -o 'data-acc-link=' "$BODY" | wc -l | tr -d ' ')" "$(perl -CSD -0777 -ne 'my $c=0; while (/\bclass\s*=\s*"([^"]*)"/gi){ my %t=map{lc($_)=>1} split /\s+/,$1; $c++ if $t{dot}&&$t{ac}; } print $c;' "$BODY")"
chk "vcount: dot∧¬ac == |data-trace-link|" "$(grep -o 'data-trace-link=' "$BODY" | wc -l | tr -d ' ')" "$(perl -CSD -0777 -ne 'my $c=0; while (/\bclass\s*=\s*"([^"]*)"/gi){ my %t=map{lc($_)=>1} split /\s+/,$1; $c++ if $t{dot}&&!$t{ac}; } print $c;' "$BODY")"
chk "vcount: l == |acceptance| (metric_l)" "$nacc" "$(count_attr_token class l < "$BODY")"
# ★round-6 ceiling 根本 fix: vcount allowlist drift の *構造封鎖*。 上の vcount は手選別ゆえ drift する (origin/k/v/dot が漏れていた)。
#   body の全 class token は COUNTED (占有数パリティ済の value class) か EXEMPT (構造/modifier/繰延 prose·chrome) のいずれかに *機械的に* 分類されねばならない。
#   未分類トークン = 将来の value class 追加 (enumeration drift) を必ず FAIL し count-parity 追加 (COUNTED 登録) を強制する = allowlist drift を構造的に検出。
#   ★EXEMPT は非 field の構造/modifier と、 明示繰延 (body prose=folio-4cf: cd/at/resp/cond/meas/role/why/plain・chrome=folio-mk9: when/who/stamp/sign/grow/gword/gdef/en/term)。
COUNTED="fid nid prio vmeth ears ct cid card av nm grp lbl cl cid2 reg-badge aid metric cat qual big u origin k v tgt l dot ac"
EXEMPT="accent actor always trigger state forbid option must should hit self in out c1 c2 c3 c4 tint-brand tint-info tint-ok tint-violet tint-warn page tbl-wrap cover-eyebrow cover-meta cover-sub doc-type reader-chip summary-card ic lab txt chapbody kicker lead num ico foot ft-grid tags rtm rtm-fold rtm-summary-derived scol ears-legend lt m b ext-badge nfr-hero cd at resp cond meas role why plain term en gword gdef grow when who stamp sign"
unknown_cls="$(KNOWN="$COUNTED $EXEMPT" perl -CSD -0777 -ne 'my %k=map{$_=>1} split /\s+/,$ENV{KNOWN}; my %seen; while (/\bclass\s*=\s*"([^"]*)"/gi){ for (split /\s+/,$1){ my $t=lc; next unless length; $seen{$t}=1 unless $k{$t}; } } print join(" ", sort keys %seen);' "$BODY")"
chk_empty "class-token 機械的網羅: 全 token が COUNTED|EXEMPT (未分類=enumeration drift)" "$unknown_cls"
# (i) nfr-metric 行: 可視 nid + category を row-scope で対突合 (§7e(c) の source-trace nid と非対称だった穴 + category 取り違え)。
exp_nfrrow="$(q '.nfr[] | [.id, .category] | @tsv' | while IFS=$'\t' read -r _id _cat; do printf '%s\t%s\n' "$(esc "$_id")" "$(esc "$_cat")"; done)"
act_nfrrow="$(perl -CSD -0777 -ne 'while (/<tr data-component="nfr-metric-row"><td><span class="nid">([^<]*)<\/span><\/td><td>([^<]*)<\/td>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "within-doc: nfr 行 (nid, category) == .nfr (順序)" "$exp_nfrrow" "$act_nfrrow"
# (j) rtm 行見出し: 可視要件 id + 行ラベル (span.lbl) を結合して順序突合 ((requirements+nfr) 順)。
#   ★round-3 ceiling: 旧 (j) は span.lbl のみ突合し rtm 行見出しの *要件 id* (emit_rtm_fold の <tr><th>{id}{lbl}</th>) を漏らし、
#   FR1→FR99 (RTM 表だけ別 id) が素通っていた。 行見出し全体 (id + 任意 lbl) を再構築し突合する (id と label を同時被覆)。
#   ★thead の <tr><th>要件</th> は </th> の後が <th class="grp"> ゆえ </th><td アンカーで除外 (tbody 行のみ捕捉)。
exp_rtmh="$(q '(.requirements + .nfr)[] | [.id, (.label // "")] | @tsv' | while IFS=$'\t' read -r _id _lb; do
  _l=""; [[ -n "$_lb" ]] && _l=" <span class=\"lbl\">$(esc "$_lb")</span>"; printf '%s%s\n' "$(esc "$_id")" "$_l"; done)"
# ★round-5 ceiling: タグ抽出を case-insensitive (/gi) に。 rtm 行見出しは class-less (<tr><th>) で count-parity 不能ゆえ
#   case-drop (<TR><TH>FR99) した偽行 + 同値 decoy で素通せた → /gi で偽行も抽出列に入れ順序/件数不一致で FAIL。
act_rtmh="$(perl -CSD -0777 -ne 'while (/<tr><th>(.*?)<\/th><td/gi){ print "$1\n"; }' "$BODY")"
chk "within-doc: rtm 行見出し (id+ラベル) == (requirements+nfr) (順序)" "$exp_rtmh" "$act_rtmh"
# (j2) rtm 受入ドットの可視テキスト == data-acc-link の末尾 (__ 後) セグメント (ds8 不動点: attr と可視 echo の両方を列挙)。
#   ★round-3 ceiling: §5-6 は data-acc-link attr のみ set 突合し、 ドットの可視 id (AC1→AC999) を見ていなかった (attr↔可視の非対称)。
#   ★アンカーは class でなく *data-acc-link* (set_eq §6 が検証済の attr ゆえ件数も §6 が anchor)。 class 構文に非依存。
#   ★round-5 ceiling: 可視を [^<]* で取ると <b>AC999</b> ネストで空に縮退し </span> マッチ失敗 → 要素脱落 → chk_empty 未検査=pass。
#   marker-keyed (.*?) で span 全体を捕捉し『可視に < があれば NESTED=FAIL』で nested-content 偽装を構造的に封じる (ds8 不動点)。
acc_vis_bad="$(perl -CSD -0777 -ne 'while (/data-acc-link="[^"]*__([^"]*)"[^>]*>(.*?)<\/span>/gs){ my ($s,$v)=($1,$2); push @b,"NESTED:$s" if $v=~/</; push @b,"$s\x{2260}$v" if $v ne $s; } END{ print join(" ",@b); }' "$BODY")"
chk_empty "within-doc: 受入ドット可視 == data-acc-link suffix (class 非依存・nested-reject)" "$acc_vis_bad"
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
# ★scope 境界 (no silent caps・round-2 ceiling で honest 後退): §7e+§7f は SRS 本体の
#   *識別子・構造・数値・統制値* フィールド (id/fid/data-req-id/ears class+label/priority class+label/vmethod/nid/category/
#   metric_v·l/nfr-hero 数値/cid2/label/regulation/rtm 列見出し+行見出し id+行ラベル/受入ドット可視/tint/origin/goals headline+id/actor key+name) を
#   *三層* で完全列挙・突合する: (1) 順序突合 (chk) = 値・順序の改竄、 (2) ★count_attr_token 占有数パリティ (HTML 属性構文非依存 =
#   quote/case/数値文字参照を吸収・全 value class + 統制値 marker は global∧要件行内∧legend-scope の三項 binding・RTM dot は joint-token) =
#   case-drop+decoy/entity ghost/chrome relocation/attr-absent 偽 dot の add を封鎖、 (3) ★class-token 機械的網羅 (全 token が COUNTED|EXEMPT =
#   vcount allowlist drift を構造封鎖・将来の value class 追加を必ず FAIL) + acc-dot marker-keyed nested-reject。 round-5/6 ceiling の HTML 属性構文 robustness
#   兄弟 (nested-content / case-drop+decoy / legend relocation / entity-encoding) を全て決定論的に封じた。 ★ただし以下 2 つは本 issue scope 外として *明示繰延* する:
#   (1) **body prose テキスト値** (mark_terms 系の自由文: ears.condition/response・nfr.target/measure・acceptance.criterion・
#       upper_needs.need・goals.desc・scope.in/out・actor.role・constraint.text) — 決定的だが本文 prose ゆえ value 突合は別カテゴリ。
#       gate J (agents/fidelity-srs) が content fidelity を暫定 backstop。 strip-term-badge 突合の floor 化は専用 follow-up (bd folio-4cf)。
#   (2) **core 共通 chrome** (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary-term-table term/en/def) —
#       lib/common.sh が全 pack 同一構造で emit (ADR/research も同じ count-only gap) ゆえ verify_core_chrome 昇格の cross-pack follow-up (bd folio-mk9)。
#   (ds8 教訓#4: gate funnel が掘り当てた broad pre-existing gap を bolt-on せず追跡 follow-up へ。 識別子/構造は floor・本文 prose 内容は ceiling 寄り)。

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
