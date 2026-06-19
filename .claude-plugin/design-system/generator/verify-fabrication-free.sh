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
#      - plain leaf (esc 済 [^<]*・nested 不能) = grep+sed 順序突合 (cxid/drid と同型)。 wrapper-tag swap は値が抽出列から脱落
#        → 順序リスト不一致で FAIL。 escape 済ゆえ nested-same-tag 早期終端は起こりえず marker-keyed 重機構は不要 (過剰=偽 FAIL 源)。
#      - compound (固定 nested 構造 = 外部バッジ span / u span / metric の v·l) = structured-regex 順序突合 (literal nested タグで leaf 抽出)。
#    順序リストの厳密一致 (chk) は値・順序・件数を同時に被覆する (= echo block 専用の marker-keyed+nested-reject とは別レイヤ)。
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
# (i) nfr-metric 行: 可視 nid + category を row-scope で対突合 (§7e(c) の source-trace nid と非対称だった穴 + category 取り違え)。
exp_nfrrow="$(q '.nfr[] | [.id, .category] | @tsv' | while IFS=$'\t' read -r _id _cat; do printf '%s\t%s\n' "$(esc "$_id")" "$(esc "$_cat")"; done)"
act_nfrrow="$(perl -CSD -0777 -ne 'while (/<tr data-component="nfr-metric-row"><td><span class="nid">([^<]*)<\/span><\/td><td>([^<]*)<\/td>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "within-doc: nfr 行 (nid, category) == .nfr (順序)" "$exp_nfrrow" "$act_nfrrow"
# (j) rtm 行ラベル (span.lbl) == 非空 .label ((requirements+nfr) 順) — plain leaf。 §7e(d) は列見出し th.grp のみで行ラベルを漏らしていた。
chk "within-doc: rtm 行ラベル (lbl) == 非空 .label (順序)" "$(qesc '(.requirements + .nfr)[] | select((.label // "") != "") | .label')" "$(grep -oE '<span class="lbl">[^<]*</span>' "$BODY" | sed -E 's#<span class="lbl">([^<]*)</span>#\1#')"
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
# ★scope 境界 (no silent caps): §7e+§7f で SRS *本体* (body) の決定的可視/attr フィールド値は完全列挙・突合済。
#   一方 core 共通 chrome (cover-head の eyebrow/title/subtitle/reader・approval-block の role/who/when/stamp・glossary-term-table の term/en/def) は
#   lib/common.sh が全 pack 同一構造で emit する決定的値だが、 現状なお 7b 相当の *件数のみ* 検証 (= ADR/research も同じ穴を持つ cross-pack gap)。
#   これは body field (pack 固有=本 issue scope) でなく core chrome (cross-pack) ゆえ、 verify_core_chrome を core 昇格し SRS+ADR+research へ
#   一括適用する専用 follow-up へ繰延する (ds8 教訓#4: 無関係な broad pre-existing gap を bolt-on せず追跡 follow-up へ)。 → bd: 下記コミット参照。

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
