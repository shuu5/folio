#!/usr/bin/env bash
# folio ceiling-anchors — contract prose slot → SSoT anchor manifest (JSON) を stdout へ (folio-mzn.1.1)。
#
# 目的 = verify-laundering 一次防壁: ceiling reviewer (fidelity-srs 等) が生成 HTML(DOM) を自己参照する
# 二重 SSoT を封じ、 contract を anchor にさせる **必須入力**。 各 prose slot を、 それが要約する contract
# フィールド (SSoT source) に対応づけ、 ssot_value (実値) まで yq で引く (reviewer が値を手にする)。
#
# 対応 doc_type = srs / adr (folio-1kif errata must-2 で adr を per-type authoring で追加。 各 doc_type の anchor 表は
# DOC_TYPE 分岐で独立 authoring・SRS path は改修前と byte 一致=回帰ゼロ。 adr の slot↔SSoT は fidelity-adr.md §2 が canonical)。
# slot↔SSoT 対応 (srs) は agents/fidelity-srs.md §2(a)+§2(b) の表が canonical (bd folio-mzn.1.1 契約が SSoT):
#   cover-summary   → meta + goals (文書全体の要旨)
#   chapter-lead-NN → 章別束ね (band() 採番 01..09 = SRS build() の 9 band に対応・固定順)
#   plain-FRx       → requirements[i].ears (条件 + 帰結)
#   plain-NFRx      → nfr[i] (区分/目標/測定)
#   rationale-FRx   → requirements[i].rationale_source (★ trace.backward ではない・単一 upper_need 参照を解決)
#   rtm-summary     → RTM 全体 (要件/NFR の trace 集合の要約)
#   term-inline:TE  → glossary[i].plain_short (派生ビュー §2(b))
#
# 機械/LLM 境界 (このセルの guardrail): 対応づけ + 実値抽出という algorithmic な仕事だけ。 自由文の
# 意味判定 (捏造か・忠実か) は一切やらない (それは LLM reviewer=別 cell の領分)。
#
# 凍結出力 schema: {"doc_type":"srs","contract":"<path>","anchors":[{"slot":..,"ssot_path":..,"ssot_value":..}]}
# usage: ceiling-anchors.sh <contract.yaml>
# exit:  0 = 出力成功 / 2 = tool error (入力不在 / doc_type 非対応 / tool 欠落)

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 必須 arg 欠如は「入力不在」= tool error ゆえ exit 2 (${1:?} の exit 1 でなく header の契約に合わせる・verify-srs と同型)。
if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: ceiling-anchors.sh <contract.yaml>" >&2; exit 2
fi
CONTRACT="$1"
[[ -f "$CONTRACT" ]] || { echo "ceiling-anchors: contract not found: $CONTRACT" >&2; exit 2; }
command -v yq >/dev/null || { echo "ceiling-anchors: yq required" >&2; exit 2; }
command -v jq >/dev/null || { echo "ceiling-anchors: jq required" >&2; exit 2; }

# ---- doc_type 検出 (srs / adr 対応・非対応は fail-closed。 folio-1kif errata must-2 で adr 追加) ----
base="$(basename "$CONTRACT")"
docid="$(yq -r '.meta.doc_id // ""' "$CONTRACT" 2>/dev/null)"
case "$base" in
  *.srs.yaml) DOC_TYPE=srs ;;
  *.adr.yaml) DOC_TYPE=adr ;;
  *) case "$docid" in
       SRS-*) DOC_TYPE=srs ;;
       ADR-*) DOC_TYPE=adr ;;
       *) echo "ceiling-anchors: srs / adr contract のみ対応 (got base=$base doc_id=$docid)" >&2; exit 2 ;;
     esac ;;
esac

# ---- lib 再利用: verify-common.sh の q()/esc() (q は $CONTRACT を参照) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "ceiling-anchors: lib/verify-common.sh not found" >&2; exit 2; }
source "$LVC" || { echo "ceiling-anchors: failed to source verify-common.sh" >&2; exit 2; }

ROWS="$(mktemp)"; trap 'rm -f "$ROWS"' EXIT
# emit_row <slot> <ssot_path> <ssot_value> : TSV 行を蓄積 (値の tab/改行は空白へ畳む = jq split("\t") 安全化。
#   contract 文字列は core_validate_strings が tab/改行を拒否済だが二重防御)。
emit_row() { printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$ROWS"; }

# ============================================================================
# doc-type 別 anchor 表 (per-type authoring・各 anchor は当該型 contract の SSoT フィールドに接地し
# 生成 HTML の DOM からは作らない = verify-laundering 禁止)。 SRS path は改修前と byte 一致 (回帰ゼロ)。
# ============================================================================
if [[ "$DOC_TYPE" == srs ]]; then

# ---- (1) cover-summary → meta + goals ----
emit_row "cover-summary" "meta+goals" \
  "$(q '.meta.title + " ｜ " + .meta.subtitle + " ｜ ゴール: " + ([.goals[].headline] | join(" / "))')"

# ---- (2) chapter-lead-01..09 → 章別束ね (SRS build() の band 順に固定・章番号は band() の %02d 採番と一致) ----
CH_LABEL=( "ゴール" "範囲・登場人物" "上位ニーズ" "機能要件" "非機能要件" "受入基準" "トレーサビリティ(RTM)" "制約・規制" "用語集" )
CH_PATH=( "goals" "scope+actors" "upper_needs" "requirements" "nfr" "acceptance" "requirements+nfr.trace(RTM)" "constraints" "glossary" )
CH_EXPR=(
  '[.goals[].headline] | join(" / ")'
  '"扱う" + ([.scope.in[]] | length | tostring) + "件/扱わない" + ([.scope.out[]] | length | tostring) + "件 ｜ 登場人物: " + ([.actors[].name] | join(", "))'
  '[.upper_needs[] | .id + ":" + .short] | join(" / ")'
  '[.requirements[] | .id + "(" + (.label // "") + ")"] | join(" / ")'
  '[.nfr[] | .id + ":" + (.category // "")] | join(" / ")'
  '[.acceptance[] | .id] | join(" / ")'
  '"要件" + ((.requirements + .nfr) | length | tostring) + "件/上位ニーズ" + (.upper_needs | length | tostring) + "件/受入" + (.acceptance | length | tostring) + "件"'
  '[.constraints[] | .id + ":" + (.label // "")] | join(" / ")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5 6 7 8; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${CH_PATH[$idx]}" "${CH_LABEL[$idx]}: $(q "${CH_EXPR[$idx]}")"
done

# ---- (3) plain-<reqid> → requirements[i].ears (i=配列位置は無条件増・n_plain_req=emit 数) ----
i=0; n_plain_req=0
while IFS=$'\t' read -r rid cond resp; do
  if [[ -n "$rid" ]]; then
    emit_row "plain-$rid" "requirements[$i].ears" "${cond:-（恒常）} → $resp"
    n_plain_req=$((n_plain_req + 1))
  fi
  i=$((i + 1))
done < <(q '.requirements[] | [.id, (.ears.condition // ""), (.ears.response // "")] | @tsv')

# ---- (4) plain-<nfrid> → nfr[i] ----
i=0; n_plain_nfr=0
while IFS=$'\t' read -r nid categ tgt meas; do
  if [[ -n "$nid" ]]; then
    emit_row "plain-$nid" "nfr[$i]" "$categ / 目標:$tgt / 測定:$meas"
    n_plain_nfr=$((n_plain_nfr + 1))
  fi
  i=$((i + 1))
done < <(q '.nfr[] | [.id, (.category // ""), (.target // ""), (.measure // "")] | @tsv')

# ---- (5) rationale-<reqid> → requirements[i].rationale_source (単一 upper_need 参照を解決して実値化) ----
declare -A NEED_TEXT
while IFS=$'\t' read -r nid ntext; do
  [[ -n "$nid" ]] && NEED_TEXT["$nid"]="$ntext"
done < <(q '.upper_needs[] | [.id, (.need + " (出どころ: " + .origin + ")")] | @tsv')
i=0; n_rationale=0
while IFS=$'\t' read -r rid rsrc; do
  if [[ -n "$rid" ]]; then
    if [[ -n "$rsrc" && "$rsrc" != "null" ]]; then
      rv="$rsrc — ${NEED_TEXT[$rsrc]:-(未解決の上位ニーズ参照: $rsrc)}"
    else
      rv="⟨rationale_source 未設定 — prose は接地なし⟩"
    fi
    emit_row "rationale-$rid" "requirements[$i].rationale_source" "$rv"
    n_rationale=$((n_rationale + 1))
  fi
  i=$((i + 1))
done < <(q '.requirements[] | [.id, (.rationale_source // "")] | @tsv')

# ---- (6) rtm-summary → RTM 全体 ----
emit_row "rtm-summary" "requirements+nfr.trace (RTM 全体)" \
  "$(q '"要件" + ((.requirements + .nfr) | length | tostring) + "件/トレースリンク" + ([(.requirements + .nfr)[].trace.backward[]] | length | tostring) + "本/孤立(出所なし)" + ([(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length | tostring) + "件/未検証(受入なし)" + ([(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length | tostring) + "件"')"

# ---- (7) term-inline:<term> → glossary[i].plain_short (派生ビュー・plain_short を持つ語のみ) ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed: 期待 anchor 種別ごとの最低件数を照合する (I1: dead -s guard の置換)。
#   cover-summary + chapter-lead-01..09 は値の有無に依らず無条件 10 行書くため `-s "$ROWS"` は常に真 = dead guard
#   だった。 requirements/nfr/glossary の抽出が空/yq 失敗でも cover+chapter だけの空 manifest を exit0 で emit し
#   reviewer に「anchor は揃った」と誤認させる fail-open を封じる。 contract に要素があるのに該当 anchor が emit
#   件数と不一致 (= @tsv 抽出失敗 / id 欠落等の構造不正) なら exit 2 (header の「構造不正なら exit2」契約を成立)。
# (a) slot 一意性 (構造不変条件): 正常な manifest は全 slot が一意。 null/欠落 id は yq -r @tsv が文字列 "null" を
#   出すため (rid 非空で skip されず) plain-null/rationale-null が衝突する = count 一致のまま構造不正を隠す fail-open。
#   slot 重複を検出して fail-closed する (id 欠落/null を直截に炙る)。
dup_slot="$(cut -f1 "$ROWS" | LC_ALL=C sort | LC_ALL=C uniq -d | head -3 | tr '\n' ' ')"
[[ -z "$dup_slot" ]] || { echo "ceiling-anchors: slot 重複 (null/欠落 id 等の構造不正): $dup_slot" >&2; exit 2; }
# (b) 期待 anchor 種別ごとの件数照合 (I1: dead -s guard の置換)。 contract に要素があるのに該当 anchor が emit 件数と
#   不一致 (= @tsv 抽出失敗 / 空文字 id 等) なら exit 2。 期待件数は *valid id を持つ* 要素数で数える (null/空 id は
#   emit されないため valid 数と一致すべき・全数と valid 数の乖離自体も構造不正として弾く)。
req_expected="$(q '.requirements | length' 2>/dev/null)"
req_valid="$(q '[.requirements[] | select((.id // "") != "")] | length' 2>/dev/null)"
nfr_expected="$(q '.nfr | length' 2>/dev/null)"
nfr_valid="$(q '[.nfr[] | select((.id // "") != "")] | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
for _v in req_expected req_valid nfr_expected nfr_valid gloss_expected; do
  case "${!_v}" in ''|*[!0-9]*) echo "ceiling-anchors: $_v の件数取得に失敗 (contract 不正/yq 失敗)" >&2; exit 2 ;; esac
done
mism=""
# 全数 ≠ valid 数 = null/空 id を持つ要素の存在 (構造不正)。
[[ "$req_expected" -ne "$req_valid" ]] && mism+=" req-id欠落($req_valid/$req_expected)"
[[ "$nfr_expected" -ne "$nfr_valid" ]] && mism+=" nfr-id欠落($nfr_valid/$nfr_expected)"
# emit 件数 ≠ valid 期待数 = @tsv 抽出の silent 失敗。
[[ "$req_valid"    -gt 0 && "$n_plain_req" -ne "$req_valid"   ]] && mism+=" plain-req($n_plain_req≠$req_valid)"
[[ "$req_valid"    -gt 0 && "$n_rationale" -ne "$req_valid"   ]] && mism+=" rationale($n_rationale≠$req_valid)"
[[ "$nfr_valid"    -gt 0 && "$n_plain_nfr" -ne "$nfr_valid"   ]] && mism+=" plain-nfr($n_plain_nfr≠$nfr_valid)"
[[ "$gloss_expected" -gt 0 && "$n_term"    -ne "$gloss_expected" ]] && mism+=" term-inline($n_term≠$gloss_expected)"
[[ -z "$mism" ]] || { echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗):$mism" >&2; exit 2; }

# ============================================================================
elif [[ "$DOC_TYPE" == adr ]]; then
# ADR anchor 表 (folio-1kif errata must-2)。 slot↔SSoT 対応は agents/fidelity-adr.md §2 が canonical:
#   cover-summary       → decision.statement + cross_doc (どの SRS 要件を支えるか)
#   chapter-lead-01..07 → context / drivers / options / decision+cross_doc / consequences / supersession+principle / glossary
#   plain-OPTx          → options[i].name + summary (平易な言い換えの接地)
#   decision-plain      → decision.statement (言い換えの接地)
#   decision-rationale  → ★context + drivers + options[].pros/cons のみ (S5.2 教訓: decision.statement ではない)
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → decision.statement + cross_doc ----
emit_row "cover-summary" "decision.statement+cross_doc" \
  "$(q '.decision.statement + " ｜ 支える SRS(" + (.cross_doc.srs_doc_id // "?") + "): " + ([.decision.justifies[].req] | join(", "))')"

# ---- (2) chapter-lead-01..07 → 章別束ね (ADR build() の band 順に固定) ----
ACH_LABEL=( "背景・力学" "評価の軸" "検討した選択肢" "決定" "結果・影響" "版の系譜・原則" "用語集" )
ACH_PATH=( "context" "drivers" "options" "decision+cross_doc" "consequences" "supersession+principle" "glossary" )
ACH_EXPR=(
  '[.context[].summary] | join(" / ")'
  '[.drivers[].driver] | join(" / ")'
  '[.options[] | .id + ":" + .name] | join(" / ")'
  '.decision.statement + " ｜ 照会: " + ([.decision.justifies[].req] | join(", "))'
  '"positive" + (.consequences.positive | length | tostring) + "件: " + ([.consequences.positive[].text] | join(" / ")) + " ｜ negative" + (.consequences.negative | length | tostring) + "件: " + ([.consequences.negative[].text] | join(" / "))'
  '"改訂状態: " + (.supersession.status // "?") + " ｜ 原則: " + (.principle.id // "?") + ":" + (.principle.text // "?")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5 6; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${ACH_PATH[$idx]}" "${ACH_LABEL[$idx]}: $(q "${ACH_EXPR[$idx]}")"
done

# ---- (3) plain-<optid> → options[i].name/summary (i=配列位置は無条件増・n_plain_opt=emit 数) ----
i=0; n_plain_opt=0
while IFS=$'\t' read -r oid oname osummary; do
  if [[ -n "$oid" ]]; then
    emit_row "plain-$oid" "options[$i].name+summary" "$oname — $osummary"
    n_plain_opt=$((n_plain_opt + 1))
  fi
  i=$((i + 1))
done < <(q '.options[] | [.id, (.name // ""), (.summary // "")] | @tsv')

# ---- (4) decision-plain → decision.statement (言い換えの接地) ----
#   ★term-inline と同じ null 規律に揃える (finding round-1 #1)。 adr で唯一の bare scalar だった decision-plain は
#   `.decision.statement` キーを丸ごと欠く contract で yq -r が literal 文字列 "null" を出し、 (c) の awk が
#   $3=="" しか見ないため "null"(非空) を通す fail-open があった。 `// ""` で absent→空文字に落とし (c) で確実に
#   捕捉させる (二重防御は下の (c) を "null" 拡張)。
emit_row "decision-plain" "decision.statement" "$(q '.decision.statement // ""')"

# ---- (5) decision-rationale → ★context + drivers + options[].pros/cons のみ (S5.2 誤 anchor 教訓) ----
#   pros/cons は null-safe (.pros // []) で包む: 単一 option の pros/cons 欠落で `null | join` が yq error → q() が
#   空文字を返し decision-rationale アンカー全体が空 ssot_value に潰れる fail-open を封じる (finding round-1(a)。
#   他の式が [.drivers[].driver] 配列包みで null-safe なのと対称。 潰れの二重防御は下の (c) 空値 invariant)。
emit_row "decision-rationale" "context+drivers+options[].pros/cons" \
  "$(q '"力学: " + ([.context[].summary] | join("; ")) + " ｜ 評価軸: " + ([.drivers[].driver] | join("; ")) + " ｜ 各案 pros/cons: " + ([.options[] | .id + "(pros:" + ((.pros // []) | join("、")) + " / cons:" + ((.cons // []) | join("、")) + ")"] | join(" ｜ "))')"

# ---- (6) term-inline:<term> → glossary[i].plain_short (派生ビュー・plain_short を持つ語のみ) ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (adr 用に per-column 再導出・SRS の (a)(b) と同型) ----
# (a) slot 一意性: null/欠落 id の option/term が plain-null / term-inline: 衝突を起こす fail-open を炙る。
adup_slot="$(cut -f1 "$ROWS" | LC_ALL=C sort | LC_ALL=C uniq -d | head -3 | tr '\n' ' ')"
[[ -z "$adup_slot" ]] || { echo "ceiling-anchors: slot 重複 (null/欠落 id 等の構造不正): $adup_slot" >&2; exit 2; }
# (b) 期待 anchor 種別ごとの件数照合: contract に要素があるのに anchor 抽出が空/失敗 = 空 manifest fail-open を封じる。
opt_expected="$(q '.options | length' 2>/dev/null)"
opt_valid="$(q '[.options[] | select((.id // "") != "")] | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
# ★decision-rationale / chapter-lead-01,02 が消費する context/drivers の非空 valid 件数 (finding round-1 #2)。
#   options空 (行下) と同型の非空検査。 これが無いと context=[]/drivers=[] の構造的に空虚な ADR が
#   floor(count 0==0) も ceiling-anchors も GREEN 通過し、 ★アンカーの grounding が hollow(verify-laundering 隣接)
#   になる (S5.2 が load-bearing とした 3 要素 = context+drivers+options.pros/cons のうち 2 が空)。
# S2 (round-2): 空白のみは (c) 不変条件 (/^[[:space:]]+$/) と揃えて空扱いにする (test("\S")=非空白を含む)。
ctx_valid="$(q '[.context[] | select((.summary // "") | test("\\S"))] | length' 2>/dev/null)"
drv_valid="$(q '[.drivers[] | select((.driver // "") | test("\\S"))] | length' 2>/dev/null)"
# ★M1 (round-2 MUST): decision-rationale の第 3 grounding 源 = 全 option 合算の pros+cons 総数。 固定ラベル
#   「各案 pros/cons: 」で (c) の列 3 が恒真非空になる計数恒真 PASS (jyfh/u7y2 クラス) を、 データ側の合算非空で塞ぐ。
#   ★全 option 合算で判定する (per-option 必須にしない — 単一 option の pros=[] は legit ゆえ exit0 を維持)。
pc_total="$(q '[.options[] | (.pros // [])[], (.cons // [])[]] | length' 2>/dev/null)"
# ★S1 (round-2・M1 と同 root-cause): chapter-lead-05 (consequences pos+neg) / chapter-lead-06 (supersession+principle)
#   も固定ラベルで恒真非空になる同型 hollow anchor。 合算非空を対称展開する (点パッチでなく同型 partial-enum を class ごと閉じる)。
csq_total="$(q '[.consequences.positive[]?, .consequences.negative[]?] | length' 2>/dev/null)"
supprin_valid="$(q '[(.supersession.status // ""), (.principle.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
for _v in opt_expected opt_valid gloss_expected ctx_valid drv_valid pc_total csq_total supprin_valid; do
  case "${!_v}" in ''|*[!0-9]*) echo "ceiling-anchors: $_v の件数取得に失敗 (contract 不正/yq 失敗)" >&2; exit 2 ;; esac
done
amism=""
# 全数 ≠ valid 数 = null/空 id を持つ option の存在 (構造不正)。
[[ "$opt_expected" -ne "$opt_valid" ]] && amism+=" opt-id欠落($opt_valid/$opt_expected)"
# emit 件数 ≠ valid 期待数 = @tsv 抽出の silent 失敗。
[[ "$opt_valid" -gt 0 && "$n_plain_opt" -ne "$opt_valid" ]] && amism+=" plain-opt($n_plain_opt≠$opt_valid)"
[[ "$gloss_expected" -gt 0 && "$n_term"  -ne "$gloss_expected" ]] && amism+=" term-inline($n_term≠$gloss_expected)"
# options は ADR の必須要素 (少なくとも 1 案) — 0 なら cover+chapter だけの空 manifest fail-open。
[[ "$opt_valid" -eq 0 ]] && amism+=" options空(ADR に選択肢が無い=構造不正 or 抽出失敗)"
# ★context/drivers も ADR の必須要素 (背景・力学が無い決定は grounding 不能) — 0 なら decision-rationale が hollow。
[[ "$ctx_valid" -eq 0 ]] && amism+=" context空(背景・力学が無い=decision-rationale が hollow・構造不正 or 抽出失敗)"
[[ "$drv_valid" -eq 0 ]] && amism+=" drivers空(評価の軸が無い=decision-rationale が hollow・構造不正 or 抽出失敗)"
# ★M1 (round-2 MUST): decision-rationale の第 3 leg (全案 pros/cons 合算) が全空 = 採用/却下の比較根拠が完全 hollow。
#   context空/drivers空 と対称。 全 option 合算 0 のみ弾く (単一 option の pros/cons 欠落 = legit ゆえ exit0 維持)。
[[ "$pc_total" -eq 0 ]] && amism+=" pros/cons全空(decision-rationale の比較根拠が hollow・全 option 合算 0)"
# ★S1 (round-2): consequences / supersession+principle の同型 hollow anchor を対称展開で弾く。
[[ "$csq_total" -eq 0 ]] && amism+=" consequences全空(chapter-lead-05 が hollow・pos+neg 合算 0)"
[[ "$supprin_valid" -eq 0 ]] && amism+=" supersession+principle全空(chapter-lead-06 が hollow・status/principle 両空)"
[[ -z "$amism" ]] || { echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗):$amism" >&2; exit 2; }
# (c) 構造的不変条件 (partial-enumeration trap 脱出・memory:ceiling-recursive): emit 済み全 anchor の ssot_value
#   (3 列目) 非空を fail-closed で強制する。 上の per-shape guard 群は特定 shape の列挙にすぎず、 test/adversarial が
#   invariant として assert する empty_val==0 を script 自身が強制していなかった (pros/cons=null / decision.statement=""
#   等での anchor 潰れ = verify-laundering を素通し)。 その invariant を script 側へ昇格する。
#   ★literal "null" も空扱いに拡張 (finding round-1 #1・二重防御): bare scalar が絶対キー欠落時に yq -r で
#   文字列 "null" になる shape を (4) の `// ""` と別経路でも捕捉する (今後 bare scalar anchor が増えた際の backstop)。
adr_empty="$(awk -F'\t' '($3=="")||($3 ~ /^[[:space:]]+$/)||($3=="null"){print $1}' "$ROWS" | head -3 | tr '\n' ' ')"
[[ -z "$adr_empty" ]] || { echo "ceiling-anchors: 空 ssot_value の anchor (SSoT 接地の潰れ=verify-laundering): $adr_empty" >&2; exit 2; }

fi

# ---- JSON 出力 (jq -Rn で TSV → 凍結 schema。 anchors 順序は上の emit 順で決定的) ----
[[ -s "$ROWS" ]] || { echo "ceiling-anchors: no anchors emitted (contract 構造不正?)" >&2; exit 2; }
jq -Rn --arg doc_type "$DOC_TYPE" --arg contract "$CONTRACT" '
  {doc_type: $doc_type, contract: $contract,
   anchors: [inputs | split("\t") | {slot: .[0], ssot_path: .[1], ssot_value: .[2]}]}
' < "$ROWS"
