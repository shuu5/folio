#!/usr/bin/env bash
# folio ceiling-anchors — contract prose slot → SSoT anchor manifest (JSON) を stdout へ (folio-mzn.1.1)。
#
# 目的 = verify-laundering 一次防壁: ceiling reviewer (fidelity-srs 等) が生成 HTML(DOM) を自己参照する
# 二重 SSoT を封じ、 contract を anchor にさせる **必須入力**。 各 prose slot を、 それが要約する contract
# フィールド (SSoT source) に対応づけ、 ssot_value (実値) まで yq で引く (reviewer が値を手にする)。
#
# slot↔SSoT 対応は agents/fidelity-srs.md §2(a)+§2(b) の表が canonical (bd folio-mzn.1.1 契約が SSoT):
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

# ---- doc_type 検出 (このセルは srs のみ対応・非対応は fail-closed) ----
base="$(basename "$CONTRACT")"
docid="$(yq -r '.meta.doc_id // ""' "$CONTRACT" 2>/dev/null)"
case "$base" in
  *.srs.yaml) DOC_TYPE=srs ;;
  *) case "$docid" in
       SRS-*) DOC_TYPE=srs ;;
       *) echo "ceiling-anchors: srs contract のみ対応 (got base=$base doc_id=$docid)" >&2; exit 2 ;;
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

# ---- JSON 出力 (jq -Rn で TSV → 凍結 schema。 anchors 順序は上の emit 順で決定的) ----
[[ -s "$ROWS" ]] || { echo "ceiling-anchors: no anchors emitted (contract 構造不正?)" >&2; exit 2; }
jq -Rn --arg doc_type "$DOC_TYPE" --arg contract "$CONTRACT" '
  {doc_type: $doc_type, contract: $contract,
   anchors: [inputs | split("\t") | {slot: .[0], ssot_path: .[1], ssot_value: .[2]}]}
' < "$ROWS"
