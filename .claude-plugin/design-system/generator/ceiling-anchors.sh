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

# ---- @tsv 列ずれの fail-closed 強制 (load-bearing・本 entry point が自前で守る) ----
#   下の multi-field `IFS=$'\t' read` は「contract 文字列に tab/改行が無い」不変条件に依存する。 その強制は
#   lib/common.sh の core_validate_strings が担うが、 それを呼ぶのは assembler と verify-*.sh だけで、
#   **本 entry point (folio ceiling-anchors <contract> = bin/folio の独立 subcommand) は通らない**。 依存する
#   不変条件は依存する側が強制する (上流 gate への暗黙依存 = 空振りする trust anchor)。
#   ★なぜ tab が効くか (parser-differential・r8k クラス): mikefarah yq の @tsv は jq と非同型で、 tab を \t へ
#     escape せず値ごと CSV-quote する (実測 v4.53.2: `a: "x<TAB>y"` → `"x^Iy"^Iz`)。 よって tab は生のまま
#     区切りとして働き read が右詰めシフトし、 label↔value の per-card 束縛が崩れた anchor を **exit 0 で**
#     emit する (実測: glossary の canonical へ tab 1 個 → `分野:` に en 値・`正式定義:` に domain 値が入る
#     relocation を rc=0 で出力 = reviewer が偽の SSoT 接地を受け取る verify-laundering の silent 再開)。
#     改行 shape は件数照合 plain-slug(26≠25) で fail-closed に倒れるのに対し tab shape だけが素通りしていた
#     (partial-enumeration trap: 2 shape のうち片方だけが塞がっていた)。
#   ★文言は既存 guard と同じ canonical 句へ寄せる (assert_mk_kill が束縛する guard 語彙 3 系統に整合)。
if [[ "$(yq '[.. | select(tag=="!!str") | test("[\t\n]")] | any' "$CONTRACT" 2>/dev/null)" == "true" ]]; then
  echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗): tab/改行混入 (@tsv 列ずれで label↔value の per-card 束縛が壊れるため fail-closed)" >&2; exit 2
fi

# ---- doc_type 検出 (contract_suffix → canonical doc-type 写像・非対応は fail-closed) ----
#   folio-1kif が srs / adr で確立し、 folio-vxpc が 11 型 (research/principle/vision/glossary/architecture/
#   testcases/datamodel/interface/risk/changelog/roadmap) へ拡張。 各型の anchor 表は下の DOC_TYPE 分岐で
#   per-type authoring (srs のコピーではない)。 SRS/adr path は改修前と byte 一致 (回帰ゼロ・SHA pin で固定)。
#   ★spec 系 (folio-rules/relations/verification.spec.yaml) は本 script 非対応のまま (registry key 粒度 +
#     ceiling pair 帰属が未解決の設計判断ゆえ後続 bead folio-vhew へ切出し = admin 裁定 D1)。 suffix spec は
#     下の allowlist に無く doc_id fallback にも該当しないため fail-closed で exit 2 に落ちる。
base="$(basename "$CONTRACT")"
docid="$(yq -r '.meta.doc_id // ""' "$CONTRACT" 2>/dev/null)"
suffix=""
case "$base" in
  *.*.yaml) suffix="${base%.yaml}"; suffix="${suffix##*.}" ;;
esac
case "$suffix" in
  # ★D2 (admin 裁定): contract_suffix 'arch' は canonical 語彙 'architecture' へ写像する。 suffix は略記であり
  #   suffix→canonical の写像は検出層の責務 (registry key / agents 名 fidelity-architecture と一致・P-5)。
  arch) DOC_TYPE=architecture ;;
  srs|adr|research|principle|vision|glossary|testcases|datamodel|interface|risk|changelog|roadmap)
        DOC_TYPE="$suffix" ;;
  *) case "$docid" in
       SRS-*) DOC_TYPE=srs ;;
       ADR-*) DOC_TYPE=adr ;;
       *) echo "ceiling-anchors: 非対応の contract (got base=$base doc_id=$docid)" >&2
          echo "  対応 doc-type: srs adr research principle vision glossary architecture testcases datamodel interface risk changelog roadmap" >&2
          exit 2 ;;
     esac ;;
esac

# ---- lib 再利用: verify-common.sh の q()/esc() (q は $CONTRACT を参照) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "ceiling-anchors: lib/verify-common.sh not found" >&2; exit 2; }
source "$LVC" || { echo "ceiling-anchors: failed to source verify-common.sh" >&2; exit 2; }

ROWS="$(mktemp)"; trap 'rm -f "$ROWS"' EXIT
# emit_row <slot> <ssot_path> <ssot_value> : TSV 行を蓄積 (値の tab/改行は空白へ畳む = jq split("\t") 安全化。
#   contract 文字列は上の entry point guard (@tsv 列ずれの fail-closed) が tab/改行を拒否済だが二重防御。
#   ★以前ここは「core_validate_strings が拒否済」と書いていたが、 それは *成立していない前提* だった:
#     core_validate_strings を呼ぶのは assembler と verify-*.sh だけで本 script は呼ばない (空振りする trust
#     anchor)。 実際 tab 混入 contract は exit 0 で relocation anchor を emit していた。 二重防御の一次側は
#     上の guard であり、 本コメントはその実在する guard を指す)。
emit_row() { printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\t\n' '  ')" >> "$ROWS"; }

# ---- 共通 fail-closed helper (folio-vxpc・adr 分岐 (a)(c) と同型の規律を per-type 分岐から呼ぶ) ----
#   ★adr/srs 分岐は inline 版を保持する (byte 回帰ゼロ = SHA pin を動かさないため helper へ寄せない)。
# assert_slot_unique : (a) slot 一意性 — null/欠落 id が plain-null 等で衝突する構造不正を炙る。
assert_slot_unique() {
  local dup; dup="$(cut -f1 "$ROWS" | LC_ALL=C sort | LC_ALL=C uniq -d | head -3 | tr '\n' ' ')"
  [[ -z "$dup" ]] || { echo "ceiling-anchors: slot 重複 (null/欠落 id 等の構造不正): $dup" >&2; exit 2; }
}
# assert_no_empty_anchor : (c) 構造的不変条件 — emit 済み全 anchor の ssot_value 非空を強制する
#   (partial-enumeration trap 脱出)。 空文字 / 空白のみ / literal "null" (bare scalar のキー欠落で yq -r が
#   文字列 null を出す shape) を全て空扱いにする。 per-shape guard の列挙漏れに対する構造終端。
assert_no_empty_anchor() {
  local e; e="$(awk -F'\t' '($3=="")||($3 ~ /^[[:space:]]+$/)||($3=="null"){print $1}' "$ROWS" | head -3 | tr '\n' ' ')"
  [[ -z "$e" ]] || { echo "ceiling-anchors: 空 ssot_value の anchor (SSoT 接地の潰れ=verify-laundering): $e" >&2; exit 2; }
}
# assert_counts_numeric : 件数取得の失敗 (contract 不正 / yq 失敗) を fail-closed に落とす。
assert_counts_numeric() {
  local v; for v in "$@"; do
    case "${!v}" in ''|*[!0-9]*) echo "ceiling-anchors: $v の件数取得に失敗 (contract 不正/yq 失敗)" >&2; exit 2 ;; esac
  done
}
# assert_no_mismatch : 収集した不一致理由を 1 本の fail-closed に束ねる。
assert_no_mismatch() {
  [[ -z "$1" ]] || { echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗):$1" >&2; exit 2; }
}

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

# ============================================================================
elif [[ "$DOC_TYPE" == research ]]; then
# research anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT 対応は agents/fidelity-research.md §2 が canonical:
#   cover-summary       → question.summary + outcome (問い + どこへ引き継いだか)
#   chapter-lead-01..06 → question(+scope) / findings / approaches / open_questions / outcome / glossary
#   plain-APx           → approaches[i].name + summary + assessment (平易な言い換えの接地)
#   outcome-plain       → ★outcome.note (= 後続 ADR で *どう決着したかの事実の引用*。 research 自身の verdict ではない)
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# ★research の hallmark = 「探索は決めない」。 contract に verdict フィールドが無いことがその構造的担保ゆえ、
#   anchor は approaches[].assessment / outcome.{resolved_by,note} の literal に置き、 優劣判定を anchor 側で作らない
#   (prose の決定化・結論化を ceiling が検出できるよう SSoT 側は中立に保つ)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → question + outcome ----
emit_row "cover-summary" "question.summary+outcome" \
  "$(q '.question.summary + " ｜ 行き先: " + (.outcome.resolved_by // "?") + " — " + (.outcome.note // "?")')"

# ---- (2) chapter-lead-01..06 → 章別束ね (research build() の band 順に固定) ----
RCH_LABEL=( "調査の問い・範囲" "わかったこと" "検討した方式" "未解決の問い" "この調査の行き先" "用語集" )
RCH_PATH=( "question+scope" "findings" "approaches" "open_questions" "outcome" "glossary" )
RCH_EXPR=(
  '.question.summary + " ｜ 扱う" + (.question.in_scope | length | tostring) + "件/扱わない" + (.question.out_scope | length | tostring) + "件"'
  '[.findings[] | .id + ":" + .summary] | join(" / ")'
  '[.approaches[] | .id + ":" + .name] | join(" / ")'
  '[.open_questions[] | .id + ":" + .text] | join(" / ")'
  '"決着: " + (.outcome.resolved_by // "?") + " — " + (.outcome.note // "?")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${RCH_PATH[$idx]}" "${RCH_LABEL[$idx]}: $(q "${RCH_EXPR[$idx]}")"
done

# ---- (3) plain-<apid> → approaches[i].name+summary+assessment ----
# ★multi-field TSV read を使わない (shift-proof): `IFS=$'\t' read -r aid aname asum aass` は tab が IFS
#   *空白* ゆえ連続 tab を 1 区切りへ畳み、 空フィールドが消えて後続変数が右詰めシフトする
#   (実測: printf 'AP1\t\t\tASSESSMENT' → aname='ASSESSMENT')。 シフトすると assessment 本文が summary 位置へ
#   混入した anchor を **exit 0 のまま** emit し、 reviewer に偽の SSoT 期待を渡す (= SF-5 が禁じる
#   verify-laundering)。 id のみ 1 フィールドで読み、 各 field は index で個別に引く (datamodel/adr (3) と同型)。
i=0; n_plain_ap=0
while IFS= read -r aid; do
  if [[ -n "$aid" && "$aid" != "null" ]]; then
    emit_row "plain-$aid" "approaches[$i].name+summary+assessment" \
      "$(q ".approaches[$i].name // \"\"") — $(q ".approaches[$i].summary // \"\"") ｜ 評価: $(q ".approaches[$i].assessment // \"\"")"
    n_plain_ap=$((n_plain_ap + 1))
  fi
  i=$((i + 1))
done < <(q '.approaches[] | (.id // "")')

# ---- (4) outcome-plain → outcome.note (★research 自身の判定ではなく「ADR でこう決着した」事実の引用) ----
#   term-inline / adr decision-plain と同じ null 規律 (`// ""` で absent→空文字に落とし (c) invariant で捕捉)。
emit_row "outcome-plain" "outcome.note" "$(q '.outcome.note // ""')"

# ---- (5) term-inline:<term> → glossary[i].plain_short (派生ビュー・plain_short を持つ語のみ) ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (research 用に per-type 再導出・adr の (a)(b)(c) と同型) ----
assert_slot_unique
# (b) 期待 anchor 種別ごとの件数照合 + hollow-anchor class の合算非空。
#   ★固定ラベル ("わかったこと: " 等) で (c) の列 3 が恒真非空になる hollow anchor を、 データ側の合算非空で塞ぐ
#     (jyfh/u7y2 クラス = 計数恒真 PASS)。 research の hollow class を洗うと chapter-lead-01..06 の **全て** が該当:
#     01=question.summary / 02=findings / 03=approaches / 04=open_questions / 05=outcome / 06=glossary。
#     ★06 (用語集) は「gloss_expected が算出済ゆえ被覆済」と誤読しやすいが、 同変数は `-gt 0` gate 付きの
#       term-inline 件数照合にしか使われず 0 件を無検査で通す。 洗い漏れ = partial-enumeration trap ゆえ
#       gloss_n で独立に塞ぐ (per-row 潰れ = n_apfull と同じく「行は非空だが接地が無い」の別クラス)。
ap_expected="$(q '.approaches | length' 2>/dev/null)"
ap_valid="$(q '[.approaches[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★per-row 完全束縛 (principle の n_pfull と同型・**yq 側で数える**): plain-APx は "name — summary ｜ 評価: ass"
#   と固定 separator で組むため、 name/summary の片方が空でも行全体は恒真非空になり (c) invariant をすり抜ける
#   (jyfh/u7y2 の per-row 版)。 両方非空の案数を数えて ap_valid と突合する。
n_apfull="$(q '[.approaches[] | select(((.name // "") | test("\\S")) and ((.summary // "") | test("\\S")))] | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
# ★用語集章 (chapter-lead-06) の唯一の grounding。 0 件だと固定ラベル "用語集: " だけの hollow anchor になり
#   (c) invariant も gloss_expected の `-gt 0` gate 付き件数照合も素通りする (計数恒真 PASS = jyfh/u7y2 クラス)。
gloss_n="$(q '.glossary | length' 2>/dev/null)"
fnd_valid="$(q '[.findings[] | select((.summary // "") | test("\\S"))] | length' 2>/dev/null)"
# ★research の hallmark 保全: open_questions は「結論しない」ことの構造的担保であり chapter-lead-04 の唯一の
#   grounding。 空なら固定ラベルだけの hollow anchor になり、 かつ「未解決を消す = hallmark 毀損」を ceiling が
#   SSoT 側で検出できなくなる (fidelity-research.md §2(a) が最重脱落とする shape)。
oq_valid="$(q '[.open_questions[] | select((.text // "") | test("\\S"))] | length' 2>/dev/null)"
q_valid="$(q '[(.question.summary // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
scope_total="$(q '[.question.in_scope[]?, .question.out_scope[]?] | length' 2>/dev/null)"
outcome_valid="$(q '[(.outcome.resolved_by // ""), (.outcome.note // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
# ★plain-APx の第 3 grounding (assessment = 各方式の評価) 合算非空。 全案 assessment 空 = 比較の天秤が hollow
#   (fidelity-research.md §2(c) 比較の公平性が検査対象を失う)。 ★全 option 合算で判定 (単一案の欠落は legit)。
ass_total="$(q '[.approaches[] | select((.assessment // "") | test("\\S"))] | length' 2>/dev/null)"
assert_counts_numeric ap_expected ap_valid n_apfull gloss_expected gloss_n fnd_valid oq_valid q_valid scope_total outcome_valid ass_total
rmism=""
[[ "$ap_expected" -ne "$ap_valid" ]] && rmism+=" approach-id欠落($ap_valid/$ap_expected)"
[[ "$ap_valid" -gt 0 && "$n_plain_ap" -ne "$ap_valid" ]] && rmism+=" plain-ap($n_plain_ap≠$ap_valid)"
[[ "$ap_valid" -gt 0 && "$n_apfull" -ne "$ap_valid" ]] && rmism+=" plain-AP の name/summary 片欠け($n_apfull/$ap_valid・固定 separator ' — ' で恒真非空になる per-row 潰れ)"
[[ "$gloss_n" -eq 0 ]] && rmism+=" glossary空(用語集章 chapter-lead-06 が固定ラベルのみの hollow anchor になる)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && rmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$ap_valid" -eq 0 ]] && rmism+=" approaches空(検討した方式が無い=chapter-lead-03/plain-AP が hollow・構造不正 or 抽出失敗)"
[[ "$fnd_valid" -eq 0 ]] && rmism+=" findings空(観察が無い=chapter-lead-02 が hollow・構造不正 or 抽出失敗)"
[[ "$oq_valid" -eq 0 ]] && rmism+=" open_questions空(未解決の問いが無い=chapter-lead-04 が hollow・research の hallmark 毀損)"
[[ "$q_valid" -eq 0 ]] && rmism+=" question.summary空(中心の問いが無い=chapter-lead-01/cover が hollow)"
[[ "$scope_total" -eq 0 ]] && rmism+=" scope全空(in/out 合算 0=chapter-lead-01 の範囲が hollow)"
[[ "$outcome_valid" -eq 0 ]] && rmism+=" outcome全空(resolved_by/note 両空=chapter-lead-05/outcome-plain が hollow)"
[[ "$ass_total" -eq 0 ]] && rmism+=" assessment全空(全案の評価が空=plain-AP の比較根拠が hollow・全 approach 合算 0)"
assert_no_mismatch "$rmism"
# (c) 構造的不変条件 (全 anchor 非空・"null" 拡張込み)。
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == principle ]]; then
# principle / constitution anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-principle.md §2 が canonical:
#   cover-summary       → principles 件数 + tier 内訳 + versioning/amendment の要旨
#   chapter-lead-01..07 → Always / Ask-first / Never / versioning / amendment / inbound / glossary
#                         (band 順 = assemble-principle.sh:303-309。 採番は lib/common.sh band() の %02d 自動採番)
#   plain-P-x           → ★principles[i].heading + statement の 2 源のみ
#   versioning-plain    → versioning.{basis,rules,note}
#   amendment-plain     → amendment.steps
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# ★tier は生トークン (Always|Ask-first|Never) のまま ssot_value に出す — anchor 側で「例外なく常に守る」等と
#   言い換えると、 prose が tier を緩める/強める誤帰属 (§2 最重の 1 つ) を reviewer が検出する基準を失う
#   (research の assessment を literal に置き優劣判定を anchor 側で作らないのと同型)。
# ★plain-P-x に tier / amended_by / 他原則 / versioning を混ぜない (§2 の anchor 注意)。 混ぜると「義務作文」の
#   検出基準が汚染される。
# ★amended_by は per-principle anchor 行にしない: 14 原則中 4 本にしか無く、 行にすると 10 本が空 ssot_value と
#   なり (c) invariant が誤発火する。 そもそも対応する prose slot が無い (改訂来歴は assembler が決定的に emit し
#   floor が被覆する領域)。
# ★chapter-lead-04/06/07 は .chapters.* に接地しない: contract .chapters は 4 キー (always/ask_first/never/
#   amendment) しか持たず、 versioning/inbound/glossary の band 見出しは assembler 側にある。 実データ
#   (.versioning / .inbound / .glossary) に接地する (存在しないキーを引くと anchor が空に潰れる)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → principles 件数 + tier 内訳 + versioning/amendment ----
emit_row "cover-summary" "principles+versioning+amendment" \
  "$(q '"原則" + (.principles | length | tostring) + "件 (Always:" + ([.principles[] | select(.tier=="Always")] | length | tostring) + "/Ask-first:" + ([.principles[] | select(.tier=="Ask-first")] | length | tostring) + "/Never:" + ([.principles[] | select(.tier=="Never")] | length | tostring) + ") ｜ 版の基準: " + (.versioning.basis // "?") + " ｜ 改訂手順: " + (.amendment.steps | length | tostring) + "段"')"

# ---- (2) chapter-lead-01..07 → 章別束ね (principle build() の band 順に固定) ----
PCH_LABEL=( "いつも守る原則 (Always)" "変える前に確認する原則 (Ask-first)" "絶対にやらない原則 (Never)" "版の上げ方" "原則を変える手順" "この憲法を参照する文書 (inbound)" "用語集" )
PCH_PATH=( "principles[tier=Always]" "principles[tier=Ask-first]" "principles[tier=Never]" "versioning" "amendment.steps" "inbound" "glossary" )
PCH_EXPR=(
  '[.principles[] | select(.tier=="Always") | .id + ":" + .heading] | join(" / ")'
  '[.principles[] | select(.tier=="Ask-first") | .id + ":" + .heading] | join(" / ")'
  '[.principles[] | select(.tier=="Never") | .id + ":" + .heading] | join(" / ")'
  '"基準: " + (.versioning.basis // "") + " ｜ 規則: " + ([.versioning.rules[] | .bump + "=" + .condition] | join(" / ")) + " ｜ 注記: " + (.versioning.note // "")'
  '[.amendment.steps[]] | join(" / ")'
  '[.inbound[] | .ref + "(" + .from + "・role=" + .role + ")"] | join(" / ")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5 6; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${PCH_PATH[$idx]}" "${PCH_LABEL[$idx]}: $(q "${PCH_EXPR[$idx]}")"
done

# ---- (3) plain-P-x → principles[i].heading + statement (★2 源のみ) ----
i=0; n_plain_p=0
while IFS=$'\t' read -r pid phead pstate; do
  if [[ -n "$pid" ]]; then
    emit_row "plain-$pid" "principles[$i].heading+statement" "$phead — $pstate"
    n_plain_p=$((n_plain_p + 1))
  fi
  i=$((i + 1))
done < <(q '.principles[] | [.id, (.heading // ""), (.statement // "")] | @tsv')

# ---- (4) versioning-plain → versioning.{basis,rules,note} ----
emit_row "versioning-plain" "versioning.basis+rules+note" \
  "$(q '"基準: " + (.versioning.basis // "") + " ｜ 規則: " + ([.versioning.rules[] | .bump + "=" + .condition] | join(" / ")) + " ｜ 注記: " + (.versioning.note // "")')"

# ---- (5) amendment-plain → amendment.steps ----
emit_row "amendment-plain" "amendment.steps" "$(q '[.amendment.steps[]] | join(" / ")')"

# ---- (6) term-inline:<term> → glossary[i].plain_short (派生ビュー・plain_short を持つ語のみ) ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (principle 用に per-type 再導出) ----
assert_slot_unique
p_expected="$(q '.principles | length' 2>/dev/null)"
p_valid="$(q '[.principles[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★per-row 束縛: heading/statement の片方が空でも "見出し — " / " — 文" は固定 separator で非空になり
#   (c) invariant をすり抜ける。 両方非空の原則数を **yq 側で** 数える (shell TSV は空フィールドで
#   変数がシフトし誤診断するため = tab は IFS 空白・実測済)。
n_pfull="$(q '[.principles[] | select(((.heading // "") | test("\\S")) and ((.statement // "") | test("\\S")))] | length' 2>/dev/null)"
# ★tier allowlist 束縛: tier は不変性段階の SSoT ゆえ allowlist 外の値 = tier 体系の崩壊 (chapter-lead-01..03 の
#   どの章にも現れない原則が生じ、 tier 別 anchor が実集合を取り落とす silent な脱落になる)。
tier_ok="$(q '[.principles[] | select((.tier // "") == "Always" or (.tier // "") == "Ask-first" or (.tier // "") == "Never")] | length' 2>/dev/null)"
# ★tier 別件数: band は 3 tier とも固定章 (assemble-principle.sh:303-305 が無条件 emit) ゆえ、 ある tier が 0 件だと
#   その chapter-lead が固定ラベルだけの hollow anchor になる (jyfh/u7y2 クラス)。
always_n="$(q '[.principles[] | select(.tier=="Always")] | length' 2>/dev/null)"
ask_n="$(q '[.principles[] | select(.tier=="Ask-first")] | length' 2>/dev/null)"
never_n="$(q '[.principles[] | select(.tier=="Never")] | length' 2>/dev/null)"
ver_valid="$(q '[(.versioning.basis // ""), (.versioning.note // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
ver_rules="$(q '.versioning.rules | length' 2>/dev/null)"
# ★amendment.steps は「原則は黙って変わらない (改訂は必ず手順と版に残る)」規律の唯一の構造的担保 = research の
#   open_questions と同格の hallmark 保全。 空なら chapter-lead-05/amendment-plain が hollow になるだけでなく、
#   prose が改訂規律を緩めても ceiling が SSoT 側で照合できなくなる。
steps_valid="$(q '[.amendment.steps[]? | select(test("\\S"))] | length' 2>/dev/null)"
# ★inbound は照会終端 node が受ける edge の唯一の記録 = chapter-lead-06 の唯一の grounding (終端性の毀損検出源)。
inbound_n="$(q '.inbound | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric p_expected p_valid n_pfull tier_ok always_n ask_n never_n ver_valid ver_rules steps_valid inbound_n gloss_expected gloss_n
pmism=""
[[ "$p_expected" -ne "$p_valid" ]] && pmism+=" principle-id欠落($p_valid/$p_expected)"
[[ "$p_valid" -gt 0 && "$n_plain_p" -ne "$p_valid" ]] && pmism+=" plain-P($n_plain_p≠$p_valid)"
[[ "$p_valid" -gt 0 && "$n_pfull" -ne "$p_valid" ]] && pmism+=" plain-P の heading/statement 片欠け($n_pfull≠$p_valid・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$p_valid" -ne "$tier_ok" ]] && pmism+=" tier allowlist 外($tier_ok/$p_valid・許容 Always|Ask-first|Never)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && pmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && pmism+=" glossary空(用語集章 chapter-lead-07 が固定ラベルのみの hollow anchor になる)"
[[ "$p_valid" -eq 0 ]] && pmism+=" principles空(原則が無い=構造不正 or 抽出失敗)"
[[ "$always_n" -eq 0 ]] && pmism+=" Always空(chapter-lead-01 が hollow)"
[[ "$ask_n" -eq 0 ]] && pmism+=" Ask-first空(chapter-lead-02 が hollow)"
[[ "$never_n" -eq 0 ]] && pmism+=" Never空(chapter-lead-03 が hollow)"
[[ "$ver_valid" -eq 0 ]] && pmism+=" versioning全空(basis/note 両空=chapter-lead-04/versioning-plain が hollow)"
[[ "$ver_rules" -eq 0 ]] && pmism+=" versioning.rules空(版の上げ方が無い=改訂規律の grounding 喪失)"
[[ "$steps_valid" -eq 0 ]] && pmism+=" amendment.steps空(改訂手順が無い=chapter-lead-05/amendment-plain が hollow・hallmark 毀損)"
[[ "$inbound_n" -eq 0 ]] && pmism+=" inbound空(受ける照会が無い=chapter-lead-06 が hollow・終端性の grounding 喪失)"
assert_no_mismatch "$pmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == vision ]]; then
# vision anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-vision.md §2 が canonical:
#   cover-summary       → north_star + objectives/success_criteria 要旨 (+ cross_doc)
#   chapter-lead-01..07 → north_star / problem / stakeholders / objectives+success_criteria / features /
#                         risks+non_goals / principle (band 順 = assemble-vision.sh の CHAP_SPECS 配列順)
# ★vision は glossary 章を持たない (assemble-vision.sh:42 = 専門語は本文で括弧併記・term-inline 不使用)。
#   contract .glossary は [] の絶対キーゆえ term-inline 行を作らない (他型の表からの blind copy 禁止)。
# ★cross_doc は節ごと opt-in (folio-vision instance は非宣言) ゆえ `// "(なし)"` で null-safe に畳む。
#   pitch (Moore) / goal_tree は optional で不在が正常 — anchor 行にしない (不在を脱落として報告させない)。
# ★hallmark = 「なぜ作るか」の記述型 (決めない・探索しない・方向と価値を宣言する)。 最重の意味判定 =
#   principle の genuine 性 (sacrifice-order = 何を何より優先するかを名指す operational な判断規則か。
#   グラフ充足のための作文・北極星の単なる言い換えでないか)。 その判断材料は .principle.text *と*
#   .principle.narrative の両方であり、 narrative が空でも固定ラベルで anchor は非空になる = 最重 lens が
#   恒真 PASS する hollow。 よって text/narrative を per-field に束縛する (下の guard)。
# ★誤 anchor 警告 (§2): principle を objectives/features に照らして裁かない (原則は機能でなく判断規則の node)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → north_star + objectives/success_criteria (+ cross_doc) ----
emit_row "cover-summary" "north_star+objectives+success_criteria(+cross_doc)" \
  "$(q '"北極星: " + (.north_star.text // "") + " ｜ 目標" + (.objectives | length | tostring) + "件/成功基準" + (.success_criteria.entries | length | tostring) + "件 ｜ 照会先 SRS: " + (.cross_doc.srs_doc_id // "(なし)")')"

# ---- (2) chapter-lead-01..07 → 章別束ね (vision build() の CHAP_SPECS 順に固定) ----
VCH_LABEL=( "北極星" "解くに値する問題" "誰のためのビジョンか" "目標と成功基準" "主要機能の方向" "リスクと非目標" "指針価値" )
VCH_PATH=( "north_star" "problem.paragraphs" "stakeholders.entries" "objectives+success_criteria.entries" "features(+cross_doc)" "risks+non_goals" "principle" )
VCH_EXPR=(
  '"一文: " + (.north_star.text // "") + " ｜ 語り: " + (.north_star.narrative // "")'
  '[.problem.paragraphs[]] | join(" / ")'
  '[.stakeholders.entries[] | .name + ":" + .gain] | join(" / ")'
  '"目標: " + ([.objectives[] | .id + ":" + .name] | join(" / ")) + " ｜ 成功基準: " + ([.success_criteria.entries[] | .id + ":" + .name + "(対象goal:" + (.for_goal // "?") + ")"] | join(" / "))'
  '[.features[] | .id + ":" + .name + "→SRS(" + ((.refs.srs // []) | join(",")) + ")"] | join(" / ")'
  '"リスク: " + ([.risks[] | .id + ":" + .name] | join(" / ")) + " ｜ 非目標: " + (.non_goals.text // "")'
  '"指針価値 " + (.principle.id // "?") + ": " + (.principle.text // "") + " ｜ 判断規則 (sacrifice-order): " + (.principle.narrative // "")'
)
for idx in 0 1 2 3 4 5 6; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${VCH_PATH[$idx]}" "${VCH_LABEL[$idx]}: $(q "${VCH_EXPR[$idx]}")"
done

# ---- fail-closed guard (vision 用に per-type 再導出) ----
assert_slot_unique
# ★vision の可視 slot は cover + chapter-lead 7 本のみ = *全て固定ラベル付き束ね* ゆえ、 (c) invariant は
#   ほぼ恒真になる (jyfh/u7y2 の計数恒真 PASS が構造的に全面化する型)。 よって per-field の合算非空 guard が
#   この型の実質的な fail-closed 本体になる (assemble-vision.sh の validate() が非空を強制するのは
#   principle.id/text と footer.instance_tag の 3 つだけ = 上流も守っていない)。
ns_text="$(q '[(.north_star.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
ns_narr="$(q '[(.north_star.narrative // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
para_valid="$(q '[.problem.paragraphs[]? | select(test("\\S"))] | length' 2>/dev/null)"
stake_expected="$(q '.stakeholders.entries | length' 2>/dev/null)"
stake_valid="$(q '[.stakeholders.entries[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.gain // "") | test("\\S")))] | length' 2>/dev/null)"
obj_expected="$(q '.objectives | length' 2>/dev/null)"
obj_valid="$(q '[.objectives[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
sc_expected="$(q '.success_criteria.entries | length' 2>/dev/null)"
sc_valid="$(q '[.success_criteria.entries[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
feat_expected="$(q '.features | length' 2>/dev/null)"
feat_valid="$(q '[.features[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
risk_expected="$(q '.risks | length' 2>/dev/null)"
risk_valid="$(q '[.risks[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
ng_valid="$(q '[(.non_goals.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
prin_text="$(q '[(.principle.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
prin_narr="$(q '[(.principle.narrative // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
assert_counts_numeric ns_text ns_narr para_valid stake_expected stake_valid obj_expected obj_valid \
  sc_expected sc_valid feat_expected feat_valid risk_expected risk_valid ng_valid prin_text prin_narr
vmism=""
# 全数 ≠ valid 数 = id 欠落 / name 空を持つ要素の存在 (構造不正・該当 chapter-lead の束ねが実集合を取り落とす)。
[[ "$stake_expected" -ne "$stake_valid" ]] && vmism+=" stakeholder-id/name/gain欠落($stake_valid/$stake_expected)"
[[ "$obj_expected" -ne "$obj_valid" ]] && vmism+=" objective-id/name欠落($obj_valid/$obj_expected)"
[[ "$sc_expected" -ne "$sc_valid" ]] && vmism+=" success_criteria-id/name欠落($sc_valid/$sc_expected)"
[[ "$feat_expected" -ne "$feat_valid" ]] && vmism+=" feature-id/name欠落($feat_valid/$feat_expected)"
[[ "$risk_expected" -ne "$risk_valid" ]] && vmism+=" risk-id/name欠落($risk_valid/$risk_expected)"
# 固定ラベルで恒真非空になる hollow anchor を、 データ側の非空で塞ぐ (章ごとに 1 本ずつ)。
[[ "$ns_text" -eq 0 ]] && vmism+=" north_star.text空(chapter-lead-01/cover が hollow)"
[[ "$ns_narr" -eq 0 ]] && vmism+=" north_star.narrative空(chapter-lead-01 が hollow・principle の「言い換えでないか」対照項が消える)"
[[ "$para_valid" -eq 0 ]] && vmism+=" problem.paragraphs空(chapter-lead-02 が hollow)"
[[ "$stake_valid" -eq 0 ]] && vmism+=" stakeholders空(chapter-lead-03 が hollow)"
[[ "$obj_valid" -eq 0 ]] && vmism+=" objectives空(chapter-lead-04 が hollow)"
[[ "$sc_valid" -eq 0 ]] && vmism+=" success_criteria空(chapter-lead-04 が hollow・for_goal⊆objectives の集合検査も空集合で恒真化)"
[[ "$feat_valid" -eq 0 ]] && vmism+=" features空(chapter-lead-05 が hollow)"
[[ "$risk_valid" -eq 0 ]] && vmism+=" risks空(chapter-lead-06 が hollow)"
[[ "$ng_valid" -eq 0 ]] && vmism+=" non_goals.text空(chapter-lead-06 が hollow・「あえて行かない道」の grounding 喪失)"
# ★最重 (§2(c)): principle の genuine 性判定の SSoT anchor。 text/narrative を per-field に束縛する
#   (narrative 空 = sacrifice-order を名指す判断規則が SSoT に無い = ceiling の最重 lens が判定材料を失う)。
[[ "$prin_text" -eq 0 ]] && vmism+=" principle.text空(chapter-lead-07 が hollow)"
[[ "$prin_narr" -eq 0 ]] && vmism+=" principle.narrative空(genuine 性=sacrifice-order の判定材料が SSoT に無い・最重 lens が恒真 PASS 化)"
assert_no_mismatch "$vmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == glossary ]]; then
# glossary anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-glossary.md §2 が canonical:
#   cover-summary  → meta.title + subtitle + 用語数 (★用語集 *全体* の要旨。 個別 term に照らすのは誤 anchor)
#   plain-<slug>   → ★terms[i].formal_def (per-term・識別のため canonical/en/domain を添える)
# ★この型は章を持たない (index/lookup 型)。 chapter-lead 行を作らない — assembler にも prose にも
#   chapter-lead slot は 1 本も無く、 他型の表からの blind copy は架空 slot を生む。
# ★term-inline 行も作らない: 他型の term-inline は .glossary[i].plain_short に接地するが、 glossary contract の
#   chrome .glossary[] は {term,en,def} で plain_short を持たない (別集合の doc-mechanics 補助語であり主題語
#   .terms[] とは違う)。 glossary では「用語そのもの」が主題ゆえ派生ビューが本体 (.terms[] + plain-<slug>) に昇格する。
# ★per-term を 1 行ずつ出す (全語を join で 1 行に畳まない): この型の最重 finding = **近接概念の取り違え**
#   (ある語の plain が隣接語の意味を述べる) であり、 reviewer が「隣の語の formal_def」と弁別できる粒度が要る。
# ★slug は contract 手書きの明示値 (.terms[i].slug) から引く — en からの機械導出ではない (SSoT 大文字温存
#   'SSoT'/'ADR' と小文字化 'layer-architecture' が混在し、 canonical/en から乖離する語もある)。 正規化再計算は禁止。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → 用語集全体の要旨 (meta + 用語数・個別 term には照らさない) ----
emit_row "cover-summary" "meta.title+meta.subtitle+terms(count)" \
  "$(q '(.meta.title // "") + " ｜ " + (.meta.subtitle // "") + " ｜ 収録語: " + (.terms | length | tostring) + "語 / 分野: " + ([.domains[].label] | join(", "))')"

# ---- (2) plain-<slug> → terms[i].formal_def (★per-term 個別行・canonical/en/domain は識別用) ----
i=0; n_plain_t=0
while IFS=$'\t' read -r tslug tcanon ten tdomain tdef; do
  if [[ -n "$tslug" && "$tslug" != "null" ]]; then
    emit_row "plain-$tslug" "terms[$i].formal_def" "$tcanon ($ten) ｜ 分野: $tdomain ｜ 正式定義: $tdef"
    n_plain_t=$((n_plain_t + 1))
  fi
  i=$((i + 1))
done < <(q '.terms[] | [(.slug // ""), (.canonical // ""), (.en // ""), (.domain // ""), (.formal_def // "")] | @tsv')
# ★per-term 束縛は **yq 側で数える** (shell の TSV parse では数えない)。 理由 = `IFS=$'\t' read` は tab が IFS
#   *空白* ゆえ空フィールドを詰めて後続変数をシフトさせる (実測: printf 'A\tB\t\tD' → c='D' d='')。
#   シフトすると「formal_def 空」を「plain_slot 不一致」と誤診断する (fail-closed 側には倒れるが理由が嘘になる)。
# (1) formal_def = plain-<slug> の唯一の接地。 空でも識別部 (canonical/en/固定ラベル) で行全体は非空になるため
#     (c) invariant をすり抜ける = per-field で数える (jyfh/u7y2 の per-row 版)。
n_def_ok="$(q '[.terms[] | select(((.formal_def // "") | test("\\S")) and ((.formal_def // "") != "null"))] | length' 2>/dev/null)"
# (2) plain_slot は contract 側が宣言する slot id。 anchor の slot (plain-<slug>) と食い違うと、 reviewer が
#     別の語の平易定義を当該語の SSoT と突き合わせる relocation クラスの取り違えになる (per-card 完全束縛 =
#     relocation の構造終端)。 全 term で一致を要求する。
n_slotbind_ok="$(q '[.terms[] | select((.plain_slot // "") == ("plain-" + (.slug // "")))] | length' 2>/dev/null)"

# ---- fail-closed guard (glossary 用に per-type 再導出) ----
assert_slot_unique
t_expected="$(q '.terms | length' 2>/dev/null)"
# ★literal "null" を valid から除く: q() は欠落キーに文字列 "null" を返すため、 slug 欠落の全 term が
#   plain-null へ衝突する (assembler 側も同 idiom で id="term-null" 衝突を実弾再現している)。
t_valid="$(q '[.terms[] | select(((.slug // "") | test("\\S")) and (.slug != "null") and ((.canonical // "") | test("\\S")) and (.canonical != "null") and ((.en // "") | test("\\S")) and ((.domain // "") | test("\\S")))] | length' 2>/dev/null)"
dom_n="$(q '.domains | length' 2>/dev/null)"
dom_valid="$(q '[.domains[] | select(((.id // "") != "") and ((.label // "") | test("\\S")))] | length' 2>/dev/null)"
# ★domain 帰属: 各 term の domain が .domains[].id に実在するか (dangling 帰属 = 分野見出しから落ちる silent 脱落)。
dom_dangling="$(yq -r '[.terms[].domain] - [.domains[].id] | unique | length' "$CONTRACT" 2>/dev/null)"
title_valid="$(q '[(.meta.title // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
sub_valid="$(q '[(.meta.subtitle // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
assert_counts_numeric t_expected t_valid n_def_ok n_slotbind_ok dom_n dom_valid dom_dangling title_valid sub_valid
gmism=""
[[ "$t_expected" -ne "$t_valid" ]] && gmism+=" term の slug/canonical/en/domain 欠落($t_valid/$t_expected・literal null 含む)"
[[ "$t_valid" -gt 0 && "$n_plain_t" -ne "$t_valid" ]] && gmism+=" plain-slug($n_plain_t≠$t_valid)"
[[ "$t_valid" -gt 0 && "$n_def_ok" -ne "$t_valid" ]] && gmism+=" formal_def 空の term($n_def_ok≠$t_valid・plain-<slug> の唯一の接地が hollow・識別部で恒真非空になる per-row 潰れ)"
[[ "$t_valid" -gt 0 && "$n_slotbind_ok" -ne "$t_valid" ]] && gmism+=" plain_slot≠plain-<slug>($n_slotbind_ok≠$t_valid・slot↔term の per-card 束縛が崩れ relocation クラスの取り違えを許す)"
[[ "$t_valid" -eq 0 ]] && gmism+=" terms空(主題語が無い=用語集として構造不正 or 抽出失敗)"
[[ "$dom_n" -ne "$dom_valid" ]] && gmism+=" domain-id/label欠落($dom_valid/$dom_n)"
[[ "$dom_valid" -eq 0 ]] && gmism+=" domains空(分野が無い=cover の分野束ねが hollow)"
[[ "$dom_dangling" -ne 0 ]] && gmism+=" term.domain が domains[].id に無い($dom_dangling 種・dangling 帰属)"
[[ "$title_valid" -eq 0 ]] && gmism+=" meta.title空(cover-summary が hollow)"
[[ "$sub_valid" -eq 0 ]] && gmism+=" meta.subtitle空(cover-summary が hollow・固定 separator で恒真非空になる潰れ)"
assert_no_mismatch "$gmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == architecture ]]; then
# architecture anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-architecture.md §2 が canonical:
#   cover-summary       → meta.subtitle + context.problem 要旨 + components + cross_doc
#   chapter-lead-01..08 → context / strategy / components / runtime / decisions / quality / risks / glossary
#                         (band 順 = assemble-arch.sh:473-482)
#   plain-AD-x          → ★decisions[i].title + summary のみ (refs を混ぜない)
#   rationale-AD-x      → ★decisions[i].summary + refs.{srs,adr,principle} のみ (title を混ぜない)
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー・arch の .glossary[] は plain_short を持つ)
# ★hallmark = 記述型 (「何がどう組み合わさって動くか」を *記述する*)。 決めない = 採否の比較検討は照会先 ADR へ
#   委ねる (案A)。 その構造的担保は **arch contract に pros/cons フィールドが無いこと** ゆえ、 anchor は
#   summary/refs の literal だけを出し、 優劣・比較・因果を anchor 側で合成しない (合成すると「案A 違反」を
#   ceiling が検出する基準を失う = research の verdict 中立性と同型)。
# ★band 見出しの件数 fidelity: chapter-lead-03 の h2 は .chapters.components (「6 つの部品」等の数詞入り)。
#   floor の数詞照合は best-effort で可視 exotic 表記 (丸数字/数学用数字/homoglyph) を列挙できない = ceiling 領分。
#   よって **.chapters.* の生文字列を無加工で載せる** (数詞の正規化・再導出は禁止 — 正規化すると偽装を
#   reviewer が判定する基準が消える。 principle の tier 生トークンと同型)。
# ★図 (C4/mermaid): band 帰属は D1→chapter-01 / D2→chapter-03 / D3→chapter-04 (emit_diagram の呼出位置)。
#   caption を literal で載せる (lines[] = mermaid DSL は join して載せない — DSL 忠実は floor 被覆で、
#   ceiling の lens は caption ↔ 図構造 ↔ カタログの意味対応ゆえ caption が判定材料)。
# ★chapter-lead-01/02/05/06/07/08 を .chapters.* に接地しない: .chapters は 2 キー (components/runtime) のみで
#   他 6 章の h2 は assembler hardcode (principle の .chapters 4 キー非対称と同型の罠)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → meta.subtitle + context.problem + components + cross_doc ----
emit_row "cover-summary" "meta.subtitle+context.problem+components+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ 課題: " + (.context.problem // "") + " ｜ 部品" + (.components | length | tostring) + "件 ｜ 照会先: SRS(" + (.cross_doc.srs_doc_id // "?") + ") / ADR(" + (.cross_doc.adr_doc_id // "?") + ")"')"

# ---- (2) chapter-lead-01..08 → 章別束ね (arch build() の band 呼出順に固定) ----
ACH2_LABEL=( "課題と背景" "ソリューション戦略" "部品の組み立て" "動いているときの流れ" "アーキテクチャ決定" "品質特性" "リスク" "用語集" )
ACH2_PATH=( "context+diagrams[D1]" "strategy" "chapters.components+components+diagrams[D2]" "chapters.runtime+runtime.flows+diagrams[D3]" "decisions+cross_doc" "quality" "risks" "glossary" )
ACH2_EXPR=(
  '"課題: " + (.context.problem // "") + " ｜ 登場: " + ([.context.actors[] | .name + "(" + .kind + "・" + .role + ")"] | join(" / ")) + " ｜ 図: " + ([.diagrams[] | select(.id == "D1") | .caption] | join(""))'
  '[.strategy[] | .id + ":" + .name + " — " + .plain] | join(" / ")'
  '"band 見出し(生): " + (.chapters.components // "") + " ｜ 実 components " + (.components | length | tostring) + "件: " + ([.components[] | .id + ":" + .name + "(" + .kind + ")"] | join(" / ")) + " ｜ 図: " + ([.diagrams[] | select(.id == "D2") | .caption] | join(""))'
  '"band 見出し(生): " + (.chapters.runtime // "") + " ｜ 流れ: " + ([.runtime.flows[] | .id + ":" + .name + " — " + .summary] | join(" / ")) + " ｜ 図: " + ([.diagrams[] | select(.id == "D3") | .caption] | join(""))'
  '[.decisions[] | .id + ":" + .title + "→SRS(" + ((.refs.srs // []) | join(",")) + ")/ADR(" + ((.refs.adr // []) | join(",")) + ")/原則(" + ((.refs.principle // []) | join(",")) + ")"] | join(" ｜ ")'
  '[.quality[] | .id + ":" + .attribute + " 目標=" + .target + " (SRS " + (.srs_ref // "?") + ")"] | join(" / ")'
  '[.risks[] | .id + ":" + .risk + " (深刻度=" + .severity + ") 対策: " + .mitigation] | join(" / ")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5 6 7; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${ACH2_PATH[$idx]}" "${ACH2_LABEL[$idx]}: $(q "${ACH2_EXPR[$idx]}")"
done

# ---- (3) plain-AD-x → decisions[i].title + summary (★refs を混ぜない) ----
i=0; n_plain_ad=0
while IFS=$'\t' read -r did dtitle; do
  if [[ -n "$did" && "$did" != "null" ]]; then
    emit_row "plain-$did" "decisions[$i].title+summary" "$dtitle — $(q ".decisions[$i].summary // \"\"")"
    n_plain_ad=$((n_plain_ad + 1))
  fi
  i=$((i + 1))
done < <(q '.decisions[] | [(.id // ""), (.title // "")] | @tsv')

# ---- (4) rationale-AD-x → decisions[i].summary + refs.{srs,adr,principle} (★title を混ぜない) ----
#   ★refs は null-safe (.refs.adr // []): AD-2/3/4 は adr/principle を持たない (legit) ため、 null 素通しだと
#     yq error → q() が空文字を返し rationale anchor 全体が潰れる (adr の pros/cons null-safe と同型)。
i=0; n_rat_ad=0
while IFS=$'\t' read -r did _rest; do
  if [[ -n "$did" && "$did" != "null" ]]; then
    emit_row "rationale-$did" "decisions[$i].summary+refs" \
      "$(q "\"根拠: \" + (.decisions[$i].summary // \"\") + \" ｜ 充足する要件(claim): \" + ((.decisions[$i].refs.srs // []) | join(\", \")) + \" ｜ 判断の根拠(rationale): \" + ((.decisions[$i].refs.adr // []) | join(\", \")) + \" ｜ 行き着く原則: \" + ((.decisions[$i].refs.principle // []) | join(\", \"))")"
    n_rat_ad=$((n_rat_ad + 1))
  fi
  i=$((i + 1))
done < <(q '.decisions[] | [(.id // ""), (.title // "")] | @tsv')

# ---- (5) term-inline:<term> → glossary[i].plain_short (派生ビュー・plain_short を持つ語のみ) ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (architecture 用に per-type 再導出) ----
assert_slot_unique
comp_expected="$(q '.components | length' 2>/dev/null)"
comp_valid="$(q '[.components[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.responsibility // "") | test("\\S")))] | length' 2>/dev/null)"
# ★kind allowlist が 2 系統ある (components={core,external} / actors={internal,external}) — 同名キー別 allowlist。
comp_kind_ok="$(q '[.components[] | select((.kind // "") == "core" or (.kind // "") == "external")] | length' 2>/dev/null)"
act_expected="$(q '.context.actors | length' 2>/dev/null)"
act_valid="$(q '[.context.actors[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.role // "") | test("\\S")) and ((.kind // "") == "internal" or (.kind // "") == "external"))] | length' 2>/dev/null)"
strat_expected="$(q '.strategy | length' 2>/dev/null)"
strat_valid="$(q '[.strategy[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.plain // "") | test("\\S")))] | length' 2>/dev/null)"
flow_expected="$(q '.runtime.flows | length' 2>/dev/null)"
flow_valid="$(q '[.runtime.flows[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.summary // "") | test("\\S")) and ((.steps // []) | length > 0))] | length' 2>/dev/null)"
dec_expected="$(q '.decisions | length' 2>/dev/null)"
dec_valid="$(q '[.decisions[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★per-row 束縛 (yq 側で数える = shell TSV は空フィールドで変数がシフトし誤診断する・実測記録は glossary 節)。
#   plain-AD-x = "title — summary" / rationale-AD-x = 固定ラベル連結 ゆえ片欠けでも恒真非空 = (c) をすり抜ける。
dec_full="$(q '[.decisions[] | select(((.title // "") | test("\\S")) and ((.summary // "") | test("\\S")))] | length' 2>/dev/null)"
# ★照会の合算非空 (per-decision 必須にしない — AD-2/3/4 の refs.adr=[] は legit ゆえ over-block しない)。
refs_total="$(q '[.decisions[] | (.refs.srs // [])[], (.refs.adr // [])[], (.refs.principle // [])[]] | length' 2>/dev/null)"
qa_expected="$(q '.quality | length' 2>/dev/null)"
# ★.quality[].srs_ref は scalar (refs.*[] の配列 idiom を blind copy すると壊れる)。
qa_valid="$(q '[.quality[] | select(((.id // "") != "") and ((.attribute // "") | test("\\S")) and ((.target // "") | test("\\S")) and ((.srs_ref // "") | test("\\S")))] | length' 2>/dev/null)"
risk_expected="$(q '.risks | length' 2>/dev/null)"
risk_valid="$(q '[.risks[] | select(((.id // "") != "") and ((.risk // "") | test("\\S")) and ((.mitigation // "") | test("\\S")) and ((.severity // "") | test("\\S")))] | length' 2>/dev/null)"
# ★band 見出し (chapters) は 2 キーのみ・数詞 fidelity の判定材料ゆえ生文字列の非空を要求。
chap_valid="$(q '[(.chapters.components // ""), (.chapters.runtime // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
ctxprob_valid="$(q '[(.context.problem // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
# ★図 caption = §2 の図 lens の唯一の判定材料 (caption 内の件数は floor の数詞照合が及ばない = 全面 ceiling 領分)。
diag_expected="$(q '.diagrams | length' 2>/dev/null)"
diag_valid="$(q '[.diagrams[] | select(((.id // "") != "") and ((.caption // "") | test("\\S")) and ((.lines // []) | length > 0))] | length' 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // ""), (.cross_doc.adr_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric comp_expected comp_valid comp_kind_ok act_expected act_valid strat_expected strat_valid \
  flow_expected flow_valid dec_expected dec_valid dec_full refs_total qa_expected qa_valid risk_expected risk_valid \
  chap_valid ctxprob_valid diag_expected diag_valid xdoc_valid gloss_expected gloss_n
amism2=""
[[ "$comp_expected" -ne "$comp_valid" ]] && amism2+=" component-id/name/responsibility欠落($comp_valid/$comp_expected)"
[[ "$comp_expected" -ne "$comp_kind_ok" ]] && amism2+=" component.kind allowlist 外($comp_kind_ok/$comp_expected・許容 core|external)"
[[ "$act_expected" -ne "$act_valid" ]] && amism2+=" actor-id/name/role/kind不正($act_valid/$act_expected・kind 許容 internal|external)"
[[ "$strat_expected" -ne "$strat_valid" ]] && amism2+=" strategy-id/name/plain欠落($strat_valid/$strat_expected)"
[[ "$flow_expected" -ne "$flow_valid" ]] && amism2+=" flow-id/name/summary/steps欠落($flow_valid/$flow_expected)"
[[ "$dec_expected" -ne "$dec_valid" ]] && amism2+=" decision-id欠落($dec_valid/$dec_expected)"
[[ "$dec_valid" -gt 0 && "$n_plain_ad" -ne "$dec_valid" ]] && amism2+=" plain-AD($n_plain_ad≠$dec_valid)"
[[ "$dec_valid" -gt 0 && "$n_rat_ad" -ne "$dec_valid" ]] && amism2+=" rationale-AD($n_rat_ad≠$dec_valid)"
[[ "$dec_valid" -gt 0 && "$dec_full" -ne "$dec_valid" ]] && amism2+=" decision の title/summary 片欠け($dec_full≠$dec_valid・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$qa_expected" -ne "$qa_valid" ]] && amism2+=" quality-id/attribute/target/srs_ref欠落($qa_valid/$qa_expected)"
[[ "$risk_expected" -ne "$risk_valid" ]] && amism2+=" risk-id/risk/mitigation/severity欠落($risk_valid/$risk_expected)"
[[ "$diag_expected" -ne "$diag_valid" ]] && amism2+=" diagram-id/caption/lines欠落($diag_valid/$diag_expected)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && amism2+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && amism2+=" glossary空(用語集章 chapter-lead-08 が固定ラベルのみの hollow anchor になる)"
# 必須要素の非空 (固定ラベルで恒真非空になる chapter-lead を、 データ側の非空で塞ぐ)。
[[ "$comp_valid" -eq 0 ]] && amism2+=" components空(chapter-lead-03 が hollow・band 件数照合の被参照側が消える)"
[[ "$act_valid" -eq 0 ]] && amism2+=" actors空(chapter-lead-01 が hollow)"
[[ "$strat_valid" -eq 0 ]] && amism2+=" strategy空(chapter-lead-02 が hollow)"
[[ "$flow_valid" -eq 0 ]] && amism2+=" runtime.flows空(chapter-lead-04 が hollow・「動いているときの流れ」の grounding 喪失)"
[[ "$dec_valid" -eq 0 ]] && amism2+=" decisions空(chapter-lead-05/plain-AD/rationale-AD が hollow)"
[[ "$qa_valid" -eq 0 ]] && amism2+=" quality空(chapter-lead-06 が hollow)"
[[ "$risk_valid" -eq 0 ]] && amism2+=" risks空(chapter-lead-07 が hollow)"
[[ "$refs_total" -eq 0 ]] && amism2+=" refs全空(rationale-AD の cross-doc 照会 leg が hollow・全 decision 合算 0)"
[[ "$chap_valid" -ne 2 ]] && amism2+=" chapters.components/runtime 空($chap_valid/2・band 見出しの数詞 fidelity の判定材料が消える)"
[[ "$ctxprob_valid" -eq 0 ]] && amism2+=" context.problem空(chapter-lead-01/cover が hollow)"
[[ "$diag_valid" -eq 0 ]] && amism2+=" diagrams空(図 caption lens の判定材料が消える・図↔カタログ対応が検査不能)"
[[ "$xdoc_valid" -ne 2 ]] && amism2+=" cross_doc.srs_doc_id/adr_doc_id 空($xdoc_valid/2・照会でつなぐ=再掲しない の構造的担保が消える)"
assert_no_mismatch "$amism2"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == testcases ]]; then
# test-cases anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-testcases.md §2 が canonical:
#   cover-summary       → meta + |test_cases| + cross_doc.srs_doc_id
#   chapter-lead-01..04 → scope / test_cases(件数+kind 内訳) / RTM(trace edge 集合) / glossary
#                         (band 順 = assemble-testcases.sh:258-261)
#   plain-TCx           → test_cases[i].{title,precondition,steps,expected}
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# ★hallmark = 三段 trace (trace.verifies=検証する要件 FR / trace.confirms=確かめる受入基準 AC)。 anchor は
#   FR/AC の ID を literal で出し、 「この test が本当にその要件を検証しているか」の判定は合成しない
#   (research の verdict 中立性・arch の pros/cons 非合成と同型)。
# ★kind は生トークン (正常系|異常系|境界値) のまま出す — 正規化・言い換えをすると prose の kind 取り違え
#   (§2 の歪み lens) を reviewer が判定する基準が消える (principle の tier 生トークン規律と同型)。
# ★.chapters は **存在しない** (top-level 8 key に無い): 4 band の見出しは全て assembler hardcode ゆえ、
#   arch の「band 見出し(生)」idiom は移植不可 (引けば literal "null" に潰れる)。 章リードの件数 fidelity は
#   floor が prose を parse しない = 全面 ceiling 領分ゆえ、 anchor が件数を *数値で* 出すことが唯一の判定基準。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → meta + 件数 + 照会先 SRS ----
emit_row "cover-summary" "meta.subtitle+test_cases(count)+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ テスト" + (.test_cases | length | tostring) + "件 (" + ([.test_cases[].id] | join(", ")) + ") ｜ 照会先 SRS: " + (.cross_doc.srs_doc_id // "?")')"

# ---- (2) chapter-lead-01..04 → 章別束ね (testcases build() の band 呼出順に固定) ----
TCH_LABEL=( "テストの考え方と範囲" "テストケース" "要件→受入→テスト の対応 (RTM)" "用語集" )
TCH_PATH=( "scope.in+scope.out" "test_cases(count+kind 内訳)" "test_cases[].trace(verifies/confirms)" "glossary" )
TCH_EXPR=(
  '"試す" + (.scope.in | length | tostring) + "件: " + ([.scope.in[]] | join(" / ")) + " ｜ 試さない" + (.scope.out | length | tostring) + "件: " + ([.scope.out[]] | join(" / "))'
  '"全" + (.test_cases | length | tostring) + "件 (正常系" + ([.test_cases[] | select(.kind == "正常系")] | length | tostring) + "/異常系" + ([.test_cases[] | select(.kind == "異常系")] | length | tostring) + "/境界値" + ([.test_cases[] | select(.kind == "境界値")] | length | tostring) + "): " + ([.test_cases[] | .id + ":" + .title + "(" + .kind + ")"] | join(" / "))'
  '"検証リンク" + ([.test_cases[].trace.verifies[]] | length | tostring) + "本/受入リンク" + ([.test_cases[].trace.confirms[]] | length | tostring) + "本: " + ([.test_cases[] | .id + "→要件(" + ((.trace.verifies // []) | join(",")) + ")/受入(" + ((.trace.confirms // []) | join(",")) + ")"] | join(" ｜ "))'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${TCH_PATH[$idx]}" "${TCH_LABEL[$idx]}: $(q "${TCH_EXPR[$idx]}")"
done

# ---- (3) plain-TCx → test_cases[i].{title,precondition,steps,expected} ----
i=0; n_plain_tc=0
while IFS=$'\t' read -r tcid _rest; do
  if [[ -n "$tcid" && "$tcid" != "null" ]]; then
    emit_row "plain-$tcid" "test_cases[$i].precondition+steps+expected" \
      "$(q "\"種別: \" + (.test_cases[$i].kind // \"\") + \" ｜ \" + (.test_cases[$i].title // \"\") + \" ｜ 前提: \" + (.test_cases[$i].precondition // \"\") + \" ｜ 手順: \" + ((.test_cases[$i].steps // []) | join(\" → \")) + \" ｜ 期待結果: \" + (.test_cases[$i].expected // \"\")")"
    n_plain_tc=$((n_plain_tc + 1))
  fi
  i=$((i + 1))
done < <(q '.test_cases[] | [(.id // ""), (.title // "")] | @tsv')

# ---- (4) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (testcases 用に per-type 再導出) ----
assert_slot_unique
tc_expected="$(q '.test_cases | length' 2>/dev/null)"
tc_valid="$(q '[.test_cases[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★kind allowlist 束縛: 生トークンで出す以上、 allowlist 外の値はどの内訳にも数えられず silent に脱落する。
tc_kind_ok="$(q '[.test_cases[] | select((.kind // "") == "正常系" or (.kind // "") == "異常系" or (.kind // "") == "境界値")] | length' 2>/dev/null)"
# ★per-row 束縛 (yq 側で数える): plain-TCx は固定 separator 連結ゆえ 1 源が空でも恒真非空になる。
#   ★steps は assembler の validate() が非空を検査していない (実測) = ここが唯一の fail-closed。
tc_full="$(q '[.test_cases[] | select(((.title // "") | test("\\S")) and ((.precondition // "") | test("\\S")) and ((.expected // "") | test("\\S")) and (((.steps // []) | length) > 0))] | length' 2>/dev/null)"
# ★三段 trace は **per-card 必須** (arch の refs 合算 idiom を blind copy しない): verifies/confirms は
#   testcases の hallmark そのもの (どの要件/受入を確かめるテストか) で、 片欠けは合算では取り落とす。
tc_trace_ok="$(q '[.test_cases[] | select((((.trace.verifies // []) | length) > 0) and (((.trace.confirms // []) | length) > 0))] | length' 2>/dev/null)"
scope_total="$(q '[.scope.in[]?, .scope.out[]?] | length' 2>/dev/null)"
# ★scope.out =「試さないこと」= テスト範囲境界の担保。 空だと chapter-lead-01 の grounding が半減し、
#   「章リードが scope.out を覆い隠す」shape の SSoT 側基準が失われる。
scope_out="$(q '[.scope.out[]? | select(test("\\S"))] | length' 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric tc_expected tc_valid tc_kind_ok tc_full tc_trace_ok scope_total scope_out xdoc_valid gloss_expected gloss_n
tmism=""
[[ "$tc_expected" -ne "$tc_valid" ]] && tmism+=" test_case-id欠落($tc_valid/$tc_expected)"
[[ "$tc_valid" -gt 0 && "$n_plain_tc" -ne "$tc_valid" ]] && tmism+=" plain-TC($n_plain_tc≠$tc_valid)"
[[ "$tc_expected" -ne "$tc_kind_ok" ]] && tmism+=" kind allowlist 外($tc_kind_ok/$tc_expected・許容 正常系|異常系|境界値)"
[[ "$tc_valid" -gt 0 && "$tc_full" -ne "$tc_valid" ]] && tmism+=" test_case の title/precondition/steps/expected 片欠け($tc_full≠$tc_valid・固定 separator で恒真非空になる per-row 潰れ・steps は assembler も未検査)"
[[ "$tc_valid" -gt 0 && "$tc_trace_ok" -ne "$tc_valid" ]] && tmism+=" 三段 trace の片欠け($tc_trace_ok≠$tc_valid・verifies/confirms は per-card 必須 = hallmark の構造的担保)"
[[ "$tc_valid" -eq 0 ]] && tmism+=" test_cases空(chapter-lead-02/03 と plain-TC が hollow)"
[[ "$scope_total" -eq 0 ]] && tmism+=" scope全空(chapter-lead-01 が hollow)"
[[ "$scope_out" -eq 0 ]] && tmism+=" scope.out空(「試さないこと」= テスト範囲境界の grounding 喪失)"
[[ "$xdoc_valid" -eq 0 ]] && tmism+=" cross_doc.srs_doc_id空(照会先 SRS が無い=三段 trace の宛先が消える)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && tmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && tmism+=" glossary空(用語集章 chapter-lead-04 が固定ラベルのみの hollow anchor になる)"
assert_no_mismatch "$tmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == datamodel ]]; then
# data-model anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-datamodel.md §2 が canonical:
#   cover-summary       → meta.subtitle + entities/relationships 件数 + invariant + cross_doc
#   chapter-lead-01..06 → context / 全体図(ER 図) / chapters.entities_band+entities /
#                         chapters.relationships_band+relationships / data_policy+principle / glossary
#                         (band 順 = assemble-datamodel.sh:418-424)
#   plain-<entity-id>   → entities[i].description + fields
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# ★hallmark = 「何を持つか・どうつながるか」*だけ* を決める。 文書の中心 = relationships[].invariant
#   (「同じ枠に 2 人」が *データの形として* 起こらないことの宣言) ゆえ invariant は literal 無加工で載せる
#   (要約・強度の言い換えを anchor 側でしない = 軟化/すり替え/新造を reviewer が検出する基準を保つ)。
# ★inline principle (PRIN-DATA-MINIMUM) の genuine 性 = B3 graph-filler 弁別の最重 lens。
#   ★vision guard の blind copy 禁止: datamodel の .principle は {id,text} の 2 key のみで **narrative を持たない**
#     (実測)。 vision の prin_narr guard を写すと恒常 FAIL の over-block になる。 sacrifice-order 句は text 内に
#     literal で在り、 噛み合いの対照項は data_policy[].rule/reason ゆえ chapter-lead-05 に両者を併載する
#     (これが genuine 性判定の材料)。
# ★band 見出しの件数 fidelity: .chapters は 2 キー (entities_band/relationships_band) のみ = 03/04 だけが
#   contract 由来。 01/02/05/06 の h2 は assembler hardcode ゆえ .chapters.* に接地しない (arch と同型の非対称)。
#   生文字列を無加工で載せ実配列長を別 leg で併載する (数詞の正規化・再導出は禁止)。
# ★ER 図: ★arch は「lines[] (mermaid DSL) を載せない (caption が判定材料)」としたが、 datamodel では **載せる**。
#   理由 = fidelity-datamodel §2(c) の図 lens は (i) ノード集合↔entities[].name / (ii) エッジ↔(from,to,label) /
#   (iii) **cardinality 記号写像** (one-to-many→||--o{ 等) の忠実を見るが、 (iii) の記号は lines[] にしか現れず
#   caption だけでは判定不能。 floor は「HTML == esc(contract lines)」の echo しか守らず contract 内部の
#   図↔カタログ乖離を素通しする。 ★ただし写像の合成は禁止 — 生 lines と生 cardinality を *並置するだけ* に留める
#   (anchor 側で写像を計算すると乖離を判定する基準が消える = tier 生トークン / 数詞非正規化と同原理)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → meta + 件数 + invariant + cross_doc ----
emit_row "cover-summary" "meta.subtitle+entities+relationships+invariant+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ かたまり" + (.entities | length | tostring) + "件/つながり" + (.relationships | length | tostring) + "本 ｜ 埋め込んだ決まり: " + ([.relationships[] | select((.invariant // "") | test("\\S")) | .id + ":" + .invariant] | join(" / ")) + " ｜ 照会先 SRS: " + (.cross_doc.srs_doc_id // "?")')"

# ---- (2) chapter-lead-01..06 → 章別束ね (datamodel build() の band 呼出順に固定) ----
DCH_LABEL=( "課題と範囲" "全体図" "情報のかたまり" "つながりと決まり" "データの扱い" "用語" )
DCH_PATH=( "context.problem+context.scope_note" "diagrams[D1](caption+lines)" "chapters.entities_band+entities" "chapters.relationships_band+relationships" "data_policy+principle" "glossary" )
DCH_EXPR=(
  '"課題: " + (.context.problem // "") + " ｜ 委譲先 (この文書で決めないこと): " + (.context.scope_note // "")'
  '"図 caption: " + ([.diagrams[] | .caption] | join(" / ")) + " ｜ 図 DSL(生): " + ([.diagrams[] | (.lines // []) | join(" ; ")] | join(" ｜ "))'
  '"band 見出し(生): " + (.chapters.entities_band // "") + " ｜ 実 entities " + (.entities | length | tostring) + "件: " + ([.entities[] | .id + ":" + .name + "(" + .kind + "・機微=" + .sensitivity + "・項目" + ((.fields // []) | length | tostring) + ")"] | join(" / "))'
  '"band 見出し(生): " + (.chapters.relationships_band // "") + " ｜ 実 relationships " + (.relationships | length | tostring) + "本: " + ([.relationships[] | .id + ":" + .from + "→" + .to + "(" + .cardinality + ") " + .label + " ｜ 決まり: " + ((.invariant // "(なし)")) ] | join(" ／ "))'
  '"扱いの決まり: " + ([.data_policy[] | .id + ":" + .rule + " (理由: " + .reason + ")"] | join(" / ")) + " ｜ 埋め込み原則 " + (.principle.id // "?") + ": " + (.principle.text // "")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${DCH_PATH[$idx]}" "${DCH_LABEL[$idx]}: $(q "${DCH_EXPR[$idx]}")"
done

# ---- (3) plain-<entity-id> → entities[i].description + fields ----
i=0; n_plain_e=0
while IFS=$'\t' read -r eid _rest; do
  if [[ -n "$eid" && "$eid" != "null" ]]; then
    emit_row "plain-$eid" "entities[$i].description+fields" \
      "$(q "(.entities[$i].name // \"\") + \" (\" + (.entities[$i].kind // \"\") + \"・機微=\" + (.entities[$i].sensitivity // \"\") + \") ｜ \" + (.entities[$i].description // \"\") + \" ｜ 項目: \" + ([.entities[$i].fields[] | .name + \"(\" + .type + \")\"] | join(\", \")) + \" ｜ 照会: \" + ((.entities[$i].refs.srs // []) | join(\", \"))")"
    n_plain_e=$((n_plain_e + 1))
  fi
  i=$((i + 1))
done < <(q '.entities[] | [(.id // ""), (.name // "")] | @tsv')

# ---- (4) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (datamodel 用に per-type 再導出) ----
assert_slot_unique
ent_expected="$(q '.entities | length' 2>/dev/null)"
ent_valid="$(q '[.entities[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
# ★kind / sensitivity は別 allowlist の同居 2 系統 (arch の components.kind / actors.kind と同型の罠)。
#   §2 の「kind・sensitivity の意味帰属改変 = critical」lens の判定材料ゆえ allowlist 束縛が要る。
ent_kind_ok="$(q '[.entities[] | select((.kind // "") == "master" or (.kind // "") == "event")] | length' 2>/dev/null)"
ent_sens_ok="$(q '[.entities[] | select((.sensitivity // "") == "high" or (.sensitivity // "") == "normal")] | length' 2>/dev/null)"
# ★per-row 束縛 (yq 側): plain-<eid> は固定 separator 連結ゆえ description 空 / fields 空でも恒真非空。
ent_full="$(q '[.entities[] | select(((.description // "") | test("\\S")) and (((.fields // []) | length) > 0))] | length' 2>/dev/null)"
fld_total="$(q '[.entities[].fields[]?] | length' 2>/dev/null)"
fld_valid="$(q '[.entities[].fields[]? | select(((.name // "") | test("\\S")) and ((.type // "") | test("\\S")))] | length' 2>/dev/null)"
rel_expected="$(q '.relationships | length' 2>/dev/null)"
rel_valid="$(q '[.relationships[] | select(((.id // "") != "") and ((.from // "") | test("\\S")) and ((.to // "") | test("\\S")) and ((.label // "") | test("\\S")) and ((.plain // "") | test("\\S")))] | length' 2>/dev/null)"
# ★cardinality は §2(c)(iii) 記号写像 lens の判定材料ゆえ生トークンで出す = allowlist 束縛が要る。
rel_card_ok="$(q '[.relationships[] | select((.cardinality // "") == "one-to-many" or (.cardinality // "") == "one-to-zero-or-one")] | length' 2>/dev/null)"
# ★invariant は per-row 不可・合算で (3/5 が legit に持たない)。 ただし全空 = 文書の中心が消える。
inv_total="$(q '[.relationships[] | select((.invariant // "") | test("\\S"))] | length' 2>/dev/null)"
dp_expected="$(q '.data_policy | length' 2>/dev/null)"
dp_valid="$(q '[.data_policy[] | select(((.id // "") != "") and ((.rule // "") | test("\\S")) and ((.reason // "") | test("\\S")))] | length' 2>/dev/null)"
# ★refs.srs=[] は legit (practitioner / REL-1,3,4 が実際に持たない = 照会ゼロは設計上の意味) ゆえ合算で塞ぐ。
refs_total="$(q '[.entities[] | (.refs.srs // [])[]] + [.relationships[] | (.refs.srs // [])[]] + [.data_policy[] | (.refs.srs // [])[]] | length' 2>/dev/null)"
diag_expected="$(q '.diagrams | length' 2>/dev/null)"
# ★lines[] は図 lens (cardinality 記号写像) の唯一の判定材料 = caption と併せて非空を要求。
diag_valid="$(q '[.diagrams[] | select(((.id // "") != "") and ((.caption // "") | test("\\S")) and (((.lines // []) | length) > 0))] | length' 2>/dev/null)"
chap_valid="$(q '[(.chapters.entities_band // ""), (.chapters.relationships_band // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
ctx_valid="$(q '[(.context.problem // ""), (.context.scope_note // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
# ★principle は {id,text} のみ (narrative なし = vision との非対称)。 両 field を per-field 束縛する。
prin_id="$(q '[(.principle.id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
prin_text="$(q '[(.principle.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric gloss_n ent_expected ent_valid ent_kind_ok ent_sens_ok ent_full fld_total fld_valid \
  rel_expected rel_valid rel_card_ok inv_total dp_expected dp_valid refs_total diag_expected diag_valid \
  chap_valid ctx_valid prin_id prin_text xdoc_valid gloss_expected
dmism=""
[[ "$ent_expected" -ne "$ent_valid" ]] && dmism+=" entity-id/name欠落($ent_valid/$ent_expected)"
[[ "$ent_expected" -ne "$ent_kind_ok" ]] && dmism+=" entity.kind allowlist 外($ent_kind_ok/$ent_expected・許容 master|event)"
[[ "$ent_expected" -ne "$ent_sens_ok" ]] && dmism+=" entity.sensitivity allowlist 外($ent_sens_ok/$ent_expected・許容 high|normal)"
[[ "$ent_valid" -gt 0 && "$n_plain_e" -ne "$ent_valid" ]] && dmism+=" plain-entity($n_plain_e≠$ent_valid)"
[[ "$ent_valid" -gt 0 && "$ent_full" -ne "$ent_valid" ]] && dmism+=" entity の description/fields 片欠け($ent_full≠$ent_valid・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$fld_total" -ne "$fld_valid" ]] && dmism+=" field の name/type 欠落($fld_valid/$fld_total)"
[[ "$rel_expected" -ne "$rel_valid" ]] && dmism+=" relationship-id/from/to/label/plain欠落($rel_valid/$rel_expected)"
[[ "$rel_expected" -ne "$rel_card_ok" ]] && dmism+=" cardinality allowlist 外($rel_card_ok/$rel_expected・許容 one-to-many|one-to-zero-or-one)"
[[ "$dp_expected" -ne "$dp_valid" ]] && dmism+=" data_policy-id/rule/reason欠落($dp_valid/$dp_expected)"
[[ "$diag_expected" -ne "$diag_valid" ]] && dmism+=" diagram-id/caption/lines欠落($diag_valid/$diag_expected)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && dmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && dmism+=" glossary空(用語章 chapter-lead-06 が固定ラベルのみの hollow anchor になる)"
[[ "$ent_valid" -eq 0 ]] && dmism+=" entities空(chapter-lead-03/plain-entity が hollow)"
[[ "$rel_valid" -eq 0 ]] && dmism+=" relationships空(chapter-lead-04 が hollow)"
[[ "$dp_valid" -eq 0 ]] && dmism+=" data_policy空(chapter-lead-05 が hollow・principle genuine 性の対照項が消える)"
[[ "$inv_total" -eq 0 ]] && dmism+=" invariant全空(文書の中心=「事故がデータの形として起こらない」宣言が消える・全 relationship 合算 0)"
[[ "$refs_total" -eq 0 ]] && dmism+=" refs.srs全空(照会 leg が hollow・全 entity/relationship/data_policy 合算 0)"
[[ "$diag_valid" -eq 0 ]] && dmism+=" diagrams空(ER 図 lens の判定材料が消える・cardinality 記号写像が検査不能)"
[[ "$chap_valid" -ne 2 ]] && dmism+=" chapters.entities_band/relationships_band 空($chap_valid/2・band 見出しの数詞 fidelity の判定材料が消える)"
[[ "$ctx_valid" -ne 2 ]] && dmism+=" context.problem/scope_note 空($ctx_valid/2・scope_note は「この文書で決めないこと」= 委譲先の grounding)"
[[ "$prin_id" -eq 0 || "$prin_text" -eq 0 ]] && dmism+=" principle.id/text空(inline principle の genuine 性判定の SSoT anchor が消える)"
[[ "$xdoc_valid" -eq 0 ]] && dmism+=" cross_doc.srs_doc_id空(照会先 SRS が消える)"
assert_no_mismatch "$dmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == interface ]]; then
# interface anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-interface.md §2 が canonical:
#   cover-summary       → meta.subtitle(生・件数入り) + operations/errors/external 件数 + cross_doc
#   chapter-lead-01..06 → context / chapters.operations_band+operations / chapters.errors_band+errors /
#                         chapters.external_band+external / cross_cutting+principle / glossary
#                         (band 順 = assemble-interface.sh:426-432)
#   plain-<operation-id>→ operations[i].{request,response,errors}
#   term-inline:<term>  → glossary[i].plain_short (派生ビュー)
# ★hallmark = 窓口の約束 *だけ* を決める (プロトコル中立)。 文書の中心 = errors[].promise (正直な断り) ゆえ
#   promise/when は literal 無加工で載せる (要約・強度の言い換えを anchor 側でしない = 軟化/新造の検出基準を保つ)。
# ★負の主張 (「断りなし」) の束縛 (ehar クラス = 負の主張ラベルの束縛漏れ): operations[].errors == [] は
#   「この操作は断らない」という *契約上の約束* であって欠落ではない。 空配列を join すると空文字に潰れ、
#   anchor 表から負の主張が **消える** (reviewer が「断りなしの操作に断りを作文した」捏造を判定する基準を失う)。
#   よって空配列は明示 marker で per-op に束縛する (正の主張=チップだけでなく負の主張にも束縛を適用する)。
# ★binding は **予約席 (null)**: プロトコルを決めないことが本 version の設計。 素の値を emit すると literal
#   "null" になり (c) invariant が恒常発火するため、 null 性を「予約席」と明示して literal 接地する
#   (prose が HTTP/JSON/URL を作文する捏造を reviewer が判定する材料 = fidelity §1 の load-bearing 4 点の 1 つ)。
# ★.chapters は 3 キー (operations/errors/external_band) — arch(2)/datamodel(2) とキー数が違う。 01/05/06 の
#   h2 は assembler hardcode ゆえ接地しない。 meta.subtitle も件数入り (「5 つの操作・4 通りの断り方…」) ゆえ
#   生で載せ実配列長を別 leg で併載する (件数 fidelity の第 2 leg。 数詞の正規化・再導出は禁止)。
# ★.diagrams は存在しない (arch/datamodel の図 leg を blind copy しない)。
# ★principle は {id,text} のみで narrative を持たない (datamodel と同じ・vision のみ narrative 有) —
#   vision の prin_narr guard を写すと恒常 FAIL の over-block。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → meta.subtitle(生) + 実件数 + cross_doc ----
emit_row "cover-summary" "meta.subtitle+operations/errors/external(count)+cross_doc" \
  "$(q '"subtitle(生): " + (.meta.subtitle // "") + " ｜ 実件数: 操作" + (.operations | length | tostring) + "/断り方" + (.errors | length | tostring) + "/外部連携" + (.external | length | tostring) + " ｜ 照会先: SRS(" + (.cross_doc.srs_doc_id // "?") + ") / データモデル(" + (.cross_doc.datamodel_doc_id // "?") + ")"')"

# ---- (2) chapter-lead-01..06 → 章別束ね (interface build() の band 呼出順に固定) ----
ICH_LABEL=( "課題と範囲" "操作" "断り方の約束" "外部連携" "横断の決まり" "用語" )
ICH_PATH=( "context.problem+context.scope_note+binding(予約席)" "chapters.operations_band+operations" "chapters.errors_band+errors" "chapters.external_band+external" "cross_cutting+principle" "glossary" )
ICH_EXPR=(
  '"課題: " + (.context.problem // "") + " ｜ 委譲先 (この文書で決めないこと): " + (.context.scope_note // "") + " ｜ binding(通信方式): " + ((.binding | select(. != null) | tostring) // "予約席=未確定 (本 version はプロトコルを決めない)")'
  '"band 見出し(生): " + (.chapters.operations_band // "") + " ｜ 実 operations " + (.operations | length | tostring) + "件: " + ([.operations[] | .id + ":" + .name + "(頼む人=" + .actor + ")"] | join(" / "))'
  '"band 見出し(生): " + (.chapters.errors_band // "") + " ｜ 実 errors " + (.errors | length | tostring) + "通り: " + ([.errors[] | .id + ":" + .name + " ｜ どんなとき: " + .when + " ｜ 約束: " + .promise] | join(" ／ "))'
  '"band 見出し(生): " + (.chapters.external_band // "") + " ｜ 実 external " + (.external | length | tostring) + "件: " + ([.external[] | .id + ":" + .name + "(向き=" + .direction + "・相手=" + .partner + ") 約束: " + .promise] | join(" ／ "))'
  '"横断の決まり: " + ([.cross_cutting[] | .id + ":" + .rule] | join(" / ")) + " ｜ 埋め込み原則 " + (.principle.id // "?") + ": " + (.principle.text // "")'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3 4 5; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${ICH_PATH[$idx]}" "${ICH_LABEL[$idx]}: $(q "${ICH_EXPR[$idx]}")"
done

# ---- (3) plain-<operation-id> → operations[i].{request,response,errors} ----
#   ★「断りなし」= errors[] 空を marker で明示する (負の主張の per-op 束縛・ehar クラス)。 yq に if/then/else は
#     無いため select + alternative idiom で書く (実測: `((.x // []) | select(length > 0) | join(",")) // "(marker)"`)。
i=0; n_plain_op=0
while IFS=$'\t' read -r opid _rest; do
  if [[ -n "$opid" && "$opid" != "null" ]]; then
    emit_row "plain-$opid" "operations[$i].request+response+errors" \
      "$(q "(.operations[$i].name // \"\") + \" (頼む人: \" + (.operations[$i].actor // \"\") + \") ｜ 頼むこと: \" + (.operations[$i].request // \"\") + \" ｜ 返ること: \" + (.operations[$i].response // \"\") + \" ｜ 断り方: \" + (((.operations[$i].errors // []) | select(length > 0) | join(\", \")) // \"(断りなし=この操作は断らないという約束)\") + \" ｜ 使う情報: \" + ((.operations[$i].uses.entities // []) | join(\", \")) + \" ｜ 照会: \" + ((.operations[$i].refs.srs // []) | join(\", \"))")"
    n_plain_op=$((n_plain_op + 1))
  fi
  i=$((i + 1))
done < <(q '.operations[] | [(.id // ""), (.name // "")] | @tsv')

# ---- (4) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (interface 用に per-type 再導出) ----
assert_slot_unique
op_expected="$(q '.operations | length' 2>/dev/null)"
op_valid="$(q '[.operations[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★per-row 束縛 (yq 側): plain-<op-id> は固定 separator 連結ゆえ 1 源が空でも恒真非空。
op_full="$(q '[.operations[] | select(((.name // "") | test("\\S")) and ((.actor // "") | test("\\S")) and ((.request // "") | test("\\S")) and ((.response // "") | test("\\S")))] | length' 2>/dev/null)"
# ★refs.srs は interface では **per-row 非空が実測** (13 node 全て) = per-row 束縛が正しい。
#   ★arch/datamodel は空が legit ゆえ合算 guard に留めた — その非対称を blind copy しない (逆向きも同様)。
op_refs_ok="$(q '[.operations[] | select(((.refs.srs // []) | length) > 0)] | length' 2>/dev/null)"
# ★operations[].errors == [] は legit (「断らない」約束・実測 2/5) ゆえ per-row 非空にしない (over-block)。
#   代わりに (a) 全 op 合算の op-error 参照が 0 でないこと (b) errors カタログ自体が非空 で塞ぐ。
opern_total="$(q '[.operations[] | (.errors // [])[]] | length' 2>/dev/null)"
# ★op が参照する error id が errors[].id に実在するか (dangling = 断りの約束が宛先を失う)。
oper_dangling="$(yq -r '[.operations[].errors[]?] - [.errors[].id] | unique | length' "$CONTRACT" 2>/dev/null)"
err_expected="$(q '.errors | length' 2>/dev/null)"
err_valid="$(q '[.errors[] | select(((.id // "") != "") and ((.name // "") | test("\\S")))] | length' 2>/dev/null)"
# ★when/promise = 文書の中心 (正直な断り) の literal。 片欠けは固定 separator で恒真非空になる。
err_full="$(q '[.errors[] | select(((.when // "") | test("\\S")) and ((.promise // "") | test("\\S")))] | length' 2>/dev/null)"
ext_expected="$(q '.external | length' 2>/dev/null)"
ext_full="$(q '[.external[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.partner // "") | test("\\S")) and ((.promise // "") | test("\\S")))] | length' 2>/dev/null)"
# ★direction allowlist (out|in): 意味逆転 = critical lens の判定材料ゆえ生トークンで出し allowlist 束縛する。
ext_dir_ok="$(q '[.external[] | select((.direction // "") == "out" or (.direction // "") == "in")] | length' 2>/dev/null)"
cc_expected="$(q '.cross_cutting | length' 2>/dev/null)"
cc_valid="$(q '[.cross_cutting[] | select(((.id // "") != "") and ((.rule // "") | test("\\S")))] | length' 2>/dev/null)"
chap_valid="$(q '[(.chapters.operations_band // ""), (.chapters.errors_band // ""), (.chapters.external_band // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
ctx_valid="$(q '[(.context.problem // ""), (.context.scope_note // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
sub_valid="$(q '[(.meta.subtitle // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
prin_id="$(q '[(.principle.id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
prin_text="$(q '[(.principle.text // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // ""), (.cross_doc.datamodel_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric gloss_n op_expected op_valid op_full op_refs_ok opern_total oper_dangling err_expected err_valid err_full \
  ext_expected ext_full ext_dir_ok cc_expected cc_valid chap_valid ctx_valid sub_valid prin_id prin_text xdoc_valid gloss_expected
imism=""
[[ "$op_expected" -ne "$op_valid" ]] && imism+=" operation-id欠落($op_valid/$op_expected)"
[[ "$op_valid" -gt 0 && "$n_plain_op" -ne "$op_valid" ]] && imism+=" plain-operation($n_plain_op≠$op_valid)"
[[ "$op_valid" -gt 0 && "$op_full" -ne "$op_valid" ]] && imism+=" operation の name/actor/request/response 片欠け($op_full≠$op_valid・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$op_valid" -gt 0 && "$op_refs_ok" -ne "$op_valid" ]] && imism+=" operation の refs.srs 空($op_refs_ok/$op_valid・interface は per-row 非空が契約)"
[[ "$err_expected" -ne "$err_valid" ]] && imism+=" error-id/name欠落($err_valid/$err_expected)"
[[ "$err_valid" -gt 0 && "$err_full" -ne "$err_valid" ]] && imism+=" error の when/promise 片欠け($err_full≠$err_valid・文書の中心=正直な断りの literal が潰れる)"
[[ "$ext_expected" -ne "$ext_full" ]] && imism+=" external-id/name/partner/promise欠落($ext_full/$ext_expected)"
[[ "$ext_expected" -ne "$ext_dir_ok" ]] && imism+=" external.direction allowlist 外($ext_dir_ok/$ext_expected・許容 out|in)"
[[ "$cc_expected" -ne "$cc_valid" ]] && imism+=" cross_cutting-id/rule欠落($cc_valid/$cc_expected)"
[[ "$oper_dangling" -ne 0 ]] && imism+=" operations[].errors が errors[].id に無い($oper_dangling 種・断りの宛先が dangling)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && imism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && imism+=" glossary空(用語章 chapter-lead-06 が固定ラベルのみの hollow anchor になる)"
[[ "$op_valid" -eq 0 ]] && imism+=" operations空(chapter-lead-02/plain-operation が hollow)"
[[ "$err_valid" -eq 0 ]] && imism+=" errors空(chapter-lead-03 が hollow・文書の中心=断りの約束が消える)"
[[ "$ext_expected" -eq 0 ]] && imism+=" external空(chapter-lead-04 が hollow)"
[[ "$cc_valid" -eq 0 ]] && imism+=" cross_cutting空(chapter-lead-05 が hollow)"
[[ "$opern_total" -eq 0 ]] && imism+=" 全 operation が errors 参照 0(断りの約束が 1 つも操作に結ばれない・合算 0 のみ)"
[[ "$chap_valid" -ne 3 ]] && imism+=" chapters.operations/errors/external_band 空($chap_valid/3・band 見出しの数詞 fidelity の判定材料が消える)"
[[ "$ctx_valid" -ne 2 ]] && imism+=" context.problem/scope_note 空($ctx_valid/2・scope_note は binding 不扱い + 委譲先の唯一の grounding)"
[[ "$sub_valid" -eq 0 ]] && imism+=" meta.subtitle空(件数入り subtitle = 件数 fidelity の第 2 leg が消える)"
[[ "$prin_id" -eq 0 || "$prin_text" -eq 0 ]] && imism+=" principle.id/text空(PRIN-HONEST-BOUNDARY の genuine 性判定の SSoT anchor が消える)"
[[ "$xdoc_valid" -ne 2 ]] && imism+=" cross_doc.srs_doc_id/datamodel_doc_id 空($xdoc_valid/2)"
assert_no_mismatch "$imism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == risk ]]; then
# risk-register anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-risk.md §2 が canonical:
#   cover-summary       → meta + |risks| + cross_doc.srs_doc_id
#   chapter-lead-01..04 → 深刻度の見取り図 / risks カード群 / RTM(trace.refs) / glossary
#                         (band 順 = assemble-risk.sh:286-289)
#   plain-RSK-00x       → risks[i].{title,statement,mitigation}
#   term-inline:<term>  → glossary[i].plain_short
# ★hallmark = 「決める」でなく「見張る」文書。 statement / mitigation は literal 無加工で載せる
#   (要約・強度の言い換えを anchor 側でしない = 深刻度の歪みを reviewer が検出する基準を保つ)。
# ★severity (深刻度) は **contract に存在しない** — likelihood×impact からの決定的導出値であり、 導出は
#   assembler (sev_prod/sev_label) が持つ。 よって anchor は **生の likelihood/impact トークン (L|M|H) だけ**を
#   載せ、 severity を anchor 側で再計算しない: (a) 再計算は導出規則の第 2 SSoT を作りドリフトする、
#   (b) card バッジ/matrix/tally の導出一致は floor が既に数値で担保済で、 ceiling の領分は「plain 散文が
#   述べる深刻度が *導出と噛み合うか*」の意味面。 その判定材料は生の likelihood/impact である。
#   contract に severity が現れたら捏造経路ゆえ構造 assert で弾く (下の guard)。
# ★.chapters / .principle は存在しない型 (datamodel/arch/interface の band 見出し(生) leg・principle leg を
#   blind copy すると恒常 FAIL)。 4 band の h2 は全て assembler hardcode。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# ---- (1) cover-summary → meta + 件数 + 照会先 ----
emit_row "cover-summary" "meta.subtitle+risks(count)+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ リスク" + (.risks | length | tostring) + "件 (" + ([.risks[].id] | join(", ")) + ") ｜ 照会先 SRS: " + (.cross_doc.srs_doc_id // "?")')"

# ---- (2) chapter-lead-01..04 → 章別束ね (risk build() の band 呼出順に固定) ----
RKCH_LABEL=( "深刻度の見取り図" "リスク一覧" "どのリスクがどの要件を脅かすか (RTM)" "用語集" )
RKCH_PATH=( "risks[].likelihood+impact(導出元)" "risks" "risks[].trace.refs" "glossary" )
RKCH_EXPR=(
  '"起こりやすさ×影響 (深刻度の導出元・生トークン): " + ([.risks[] | .id + "(起=" + .likelihood + "×影=" + .impact + ")"] | join(" / ")) + " ｜ 起こりやすさ内訳 H" + ([.risks[] | select(.likelihood == "H")] | length | tostring) + "/M" + ([.risks[] | select(.likelihood == "M")] | length | tostring) + "/L" + ([.risks[] | select(.likelihood == "L")] | length | tostring) + " ｜ 影響内訳 H" + ([.risks[] | select(.impact == "H")] | length | tostring) + "/M" + ([.risks[] | select(.impact == "M")] | length | tostring) + "/L" + ([.risks[] | select(.impact == "L")] | length | tostring)'
  '"全" + (.risks | length | tostring) + "件: " + ([.risks[] | .id + ":" + .title + "(起=" + .likelihood + "×影=" + .impact + "・状態=" + .status + "・担当=" + .owner + ")"] | join(" / "))'
  '"脅かすリンク" + ([.risks[].trace.refs[]] | length | tostring) + "本: " + ([.risks[] | .id + "→要件(" + ((.trace.refs // []) | join(",")) + ")"] | join(" ｜ "))'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${RKCH_PATH[$idx]}" "${RKCH_LABEL[$idx]}: $(q "${RKCH_EXPR[$idx]}")"
done

# ---- (3) plain-RSK-00x → risks[i].{title,statement,mitigation} ----
i=0; n_plain_rk=0
while IFS=$'\t' read -r rkid _rest; do
  if [[ -n "$rkid" && "$rkid" != "null" ]]; then
    emit_row "plain-$rkid" "risks[$i].title+statement+mitigation" \
      "$(q "(.risks[$i].title // \"\") + \" ｜ 中身: \" + (.risks[$i].statement // \"\") + \" ｜ 備え: \" + (.risks[$i].mitigation // \"\") + \" ｜ 起こりやすさ(生)=\" + (.risks[$i].likelihood // \"\") + \" / 影響(生)=\" + (.risks[$i].impact // \"\") + \" ｜ 状態(生)=\" + (.risks[$i].status // \"\") + \" ｜ 担当: \" + (.risks[$i].owner // \"\") + \" ｜ 脅かす要件: \" + ((.risks[$i].trace.refs // []) | join(\", \"))")"
    n_plain_rk=$((n_plain_rk + 1))
  fi
  i=$((i + 1))
done < <(q '.risks[] | [(.id // ""), (.title // "")] | @tsv')

# ---- (4) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (risk 用に per-type 再導出) ----
assert_slot_unique
rk_expected="$(q '.risks | length' 2>/dev/null)"
rk_valid="$(q '[.risks[] | select((.id // "") != "")] | length' 2>/dev/null)"
# ★per-row 束縛 (yq 側): plain-RSK は固定 separator 連結ゆえ 1 源が空でも恒真非空。
rk_full="$(q '[.risks[] | select(((.title // "") | test("\\S")) and ((.statement // "") | test("\\S")) and ((.mitigation // "") | test("\\S")) and ((.owner // "") | test("\\S")))] | length' 2>/dev/null)"
# ★likelihood/impact allowlist (L|M|H) = severity 導出の入力。 allowlist 外は導出不能 = 深刻度が意味を失う。
rk_lvl_ok="$(q '[.risks[] | select(((.likelihood // "") == "L" or (.likelihood // "") == "M" or (.likelihood // "") == "H") and ((.impact // "") == "L" or (.impact // "") == "M" or (.impact // "") == "H"))] | length' 2>/dev/null)"
# ★status allowlist (open|mitigating|accepted|closed) = 状態バッジの誤りを検出する lens の判定材料。
rk_status_ok="$(q '[.risks[] | select((.status // "") == "open" or (.status // "") == "mitigating" or (.status // "") == "accepted" or (.status // "") == "closed")] | length' 2>/dev/null)"
# ★severity は contract に持たない (導出値) — 現れたら捏造経路 (第 2 SSoT) ゆえ構造 assert で弾く。
rk_sev_present="$(q '[.risks[] | select(has("severity"))] | length' 2>/dev/null)"
# ★trace.refs は risk では **per-row 必須** (assembler validate が 1 件でも空を拒否 = 実測)。
#   ★changelog/roadmap は片側空が legit ゆえ合算 — その非対称を blind copy しない。
rk_refs_ok="$(q '[.risks[] | select(((.trace.refs // []) | length) > 0)] | length' 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric rk_expected rk_valid rk_full rk_lvl_ok rk_status_ok rk_sev_present rk_refs_ok xdoc_valid gloss_expected gloss_n
rkmism=""
[[ "$rk_expected" -ne "$rk_valid" ]] && rkmism+=" risk-id欠落($rk_valid/$rk_expected)"
[[ "$rk_valid" -gt 0 && "$n_plain_rk" -ne "$rk_valid" ]] && rkmism+=" plain-RSK($n_plain_rk≠$rk_valid)"
[[ "$rk_valid" -gt 0 && "$rk_full" -ne "$rk_valid" ]] && rkmism+=" risk の title/statement/mitigation/owner 片欠け($rk_full≠$rk_valid・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$rk_expected" -ne "$rk_lvl_ok" ]] && rkmism+=" likelihood/impact allowlist 外($rk_lvl_ok/$rk_expected・許容 L|M|H = severity 導出の入力)"
[[ "$rk_expected" -ne "$rk_status_ok" ]] && rkmism+=" status allowlist 外($rk_status_ok/$rk_expected・許容 open|mitigating|accepted|closed)"
[[ "$rk_sev_present" -ne 0 ]] && rkmism+=" severity が contract に存在($rk_sev_present 件・深刻度は likelihood×impact の導出値ゆえ contract 側の保持は第 2 SSoT = 捏造経路)"
[[ "$rk_valid" -gt 0 && "$rk_refs_ok" -ne "$rk_valid" ]] && rkmism+=" trace.refs 空の risk($rk_refs_ok/$rk_valid・risk は per-row 必須 = 脅かす要件の無いリスクは登録簿として構造不正)"
[[ "$rk_valid" -eq 0 ]] && rkmism+=" risks空(chapter-lead-01..03 と plain-RSK が hollow)"
[[ "$xdoc_valid" -eq 0 ]] && rkmism+=" cross_doc.srs_doc_id空(照会先 SRS が消える)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && rkmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && rkmism+=" glossary空(用語集章 chapter-lead-04 が固定ラベルのみの hollow anchor になる)"
assert_no_mismatch "$rkmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == changelog ]]; then
# changelog anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-changelog.md §1/§5.1 が canonical
# (この型に §2 は無い)。
#   cover-summary       → meta + |entries| + cross_doc.{srs,adr}_doc_id
#   chapter-lead-01..04 → 最新版ハイライト / entries(版ごと) / refs(srs/adr) / glossary
#                         (band 順 = assemble-changelog.sh:299-302)
#   latest-highlight    → ★最新版 (semver 降順先頭) の categories のみ
#   plain-Cx            → 該当 item の text
#   term-inline:<term>  → glossary[i].plain_short
# ★hallmark = version-keyed の *事実記録* (決めない・宣言しない・すでに起きたこと)。 item text は literal
#   無加工で載せる (脚色・誇張・因果の作文を reviewer が検出する基準を保つ)。
# ★区分は生トークン (added|changed|deprecated|removed|fixed|security) のまま載せる — 「追加」等へ正規化すると
#   区分の取り違え (非推奨↔削除・修正↔追加) を reviewer が判定する基準が消える (tier 生トークン規律と同型)。
# ★負の主張 (「0 件 = この種別は変更なし」) の束縛 (ehar クラス): assembler は最新版ハイライトで 6 区分を
#   **0 を含めて全て**数値バッジ emit する。 anchor が 0 件区分を省略すると「変更なし」という負の主張が
#   anchor 表から消え、 prose がそこに変更を作文した捏造を reviewer が判定できなくなる。 よって
#   latest-highlight / chapter-lead-01 は **6 区分を 0 込みで全列挙**する。
# ★contract 構造の非対称: 区分は `categories` **map のキー** であって `kind` フィールドではない (risk/testcases
#   の kind idiom を blind copy しない)。 `unreleased` は opt-in ゆえ null-safe (`// {}`)。
# ★.chapters / .principle は存在しない型 (band 見出し(生) leg・principle leg を blind copy すると恒常 FAIL)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# 最新版 = semver 降順先頭 (assembler は sort -rV で決定的に選ぶ。 自作 parser を避け同じ決定手段を使う)。
LATEST_V="$(yq -r '.entries[].version' "$CONTRACT" 2>/dev/null | sort -rV | head -1)"
# ★文言は他 guard と同じ canonical 句を使う (「anchor 抽出が contract 期待と不一致」)。 MK の oracle は
#   guard 語彙で「guard に到達したか」を束縛するため、 ここだけ独自文言にすると本物の fail-closed が
#   「未知の経路」に見えて oracle と噛み合わない (実測で 2 件が該当した)。
[[ -n "$LATEST_V" ]] || { echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗): entries空/version欠落(最新版を決定できない=chapter-lead-01/latest-highlight が hollow)" >&2; exit 2; }
# ★contract 由来値は yq 式の *本文へ補間しない* — env 経由で **データとして束縛**する (strenv)。
#   本文補間は述語 (select(.version == "...")) を細工値で恒真化でき、 別 entry の内容を混ぜた anchor を
#   exit 0 で emit する (per-card 束縛の fail-open = SF-5 が禁ずる verify-laundering / relocation クラス)。
#   既存 guard は 3 つとも素通りする: slot 名は一意・件数は 1 行のまま・値はむしろ過剰に非空。
#   strenv なら細工値は「そんな id は無い」= 0 件となり assert_no_empty_anchor が exit 2 で fail-closed。
export LATEST_V

# ---- (1) cover-summary → meta + 件数 + 照会先 ----
emit_row "cover-summary" "meta.subtitle+entries(count)+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ 収録版 " + (.entries | length | tostring) + "件 (" + ([.entries[].version] | join(", ")) + ")" + (if (.unreleased // {}) == {} then "" else " + 未リリース枠あり" end) + " ｜ 照会先: SRS(" + (.cross_doc.srs_doc_id // "?") + ") / ADR(" + (.cross_doc.adr_doc_id // "?") + ")"' 2>/dev/null || q '(.meta.subtitle // "") + " ｜ 収録版 " + (.entries | length | tostring) + "件 (" + ([.entries[].version] | join(", ")) + ") ｜ 照会先: SRS(" + (.cross_doc.srs_doc_id // "?") + ") / ADR(" + (.cross_doc.adr_doc_id // "?") + ")"')"

# ---- (2) chapter-lead-01..04 → 章別束ね (changelog build() の band 呼出順に固定) ----
#   ★chapter-lead-01 (最新版ハイライト) は 6 区分を 0 込みで全列挙 (負の主張の束縛)。
CLCH_LABEL=( "最新版のハイライト" "版ごとの変更" "変更の照会先 (なぜ / どの要件)" "用語集" )
CLCH_PATH=( "entries[latest].categories(6 区分・0 込み)" "unreleased+entries" "entries[].categories[].refs" "glossary" )
CL_LATEST_EXPR='"最新版 " + strenv(LATEST_V) + " の 6 区分件数 (0 = この種別は変更なし): added=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.added // []) | length | tostring) + " / changed=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.changed // []) | length | tostring) + " / deprecated=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.deprecated // []) | length | tostring) + " / removed=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.removed // []) | length | tostring) + " / fixed=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.fixed // []) | length | tostring) + " / security=" + ((.entries[] | select(.version == strenv(LATEST_V)) | .categories.security // []) | length | tostring)'
CLCH_EXPR=(
  "$CL_LATEST_EXPR"
  '[.entries[] | .version + "(" + .date + "): " + ([.categories | to_entries[] | .key + "×" + (.value | length | tostring)] | join(", "))] | join(" ｜ ")'
  '"照会: " + ([.entries[] | .categories | to_entries[] | .value[] | .id + "→SRS(" + ((.refs.srs // []) | join(",")) + ")/ADR(" + ((.refs.adr // []) | join(",")) + ")"] | join(" / "))'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${CLCH_PATH[$idx]}" "${CLCH_LABEL[$idx]}: $(q "${CLCH_EXPR[$idx]}")"
done

# ---- (3) latest-highlight → ★最新版 (semver 降順先頭) の categories のみ (別版混入 = drift) ----
emit_row "latest-highlight" "entries[version=$LATEST_V].categories" \
  "$(q '"最新版 " + strenv(LATEST_V) + " (" + (.entries[] | select(.version == strenv(LATEST_V)) | .date) + ") で実際に変わったこと ｜ " + '"$CL_LATEST_EXPR"' + " ｜ 中身: " + ([.entries[] | select(.version == strenv(LATEST_V)) | .categories | to_entries[] | .key + ": " + ([.value[] | .text] | join(" / "))] | join(" ｜ "))')"

# ---- (4) plain-Cx → 該当 item の text (unreleased + entries 横断で id 通し) ----
i=0; n_plain_cl=0
while IFS=$'\t' read -r cid; do
  if [[ -n "$cid" && "$cid" != "null" ]]; then
    export CID="$cid"   # ★式本文へ補間せず strenv でデータ束縛 (LATEST_V の同注記を参照)。
    emit_row "plain-$cid" "categories[].items[id=$cid].text" \
      "$(q '[(.unreleased // {}), (.entries[])] | [.[] | (.version // "未リリース") as $v | (.categories // {}) | to_entries[] | .key as $k | .value[] | select(.id == strenv(CID)) | "版=" + $v + " ｜ 区分(生)=" + $k + " ｜ " + .text + " ｜ 照会: SRS(" + ((.refs.srs // []) | join(",")) + ")/ADR(" + ((.refs.adr // []) | join(",")) + ")"] | join("")')"
    n_plain_cl=$((n_plain_cl + 1))
  fi
  i=$((i + 1))
done < <(yq -r '[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | (.id // "")' "$CONTRACT" 2>/dev/null)

# ---- (5) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (changelog 用に per-type 再導出) ----
assert_slot_unique
ent_n="$(q '.entries | length' 2>/dev/null)"
ent_valid="$(q '[.entries[] | select(((.version // "") | test("\\S")) and ((.date // "") | test("\\S")))] | length' 2>/dev/null)"
item_total="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[]] | length' "$CONTRACT" 2>/dev/null)"
item_valid="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | select(((.id // "") != "") and ((.text // "") | test("\\S")))] | length' "$CONTRACT" 2>/dev/null)"
# ★区分 allowlist: map のキーが区分ゆえ、 allowlist 外のキーはどの区分バッジにも数えられず silent に脱落する。
cat_total="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .key] | length' "$CONTRACT" 2>/dev/null)"
cat_ok="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | select(.key == "added" or .key == "changed" or .key == "deprecated" or .key == "removed" or .key == "fixed" or .key == "security") | .key] | length' "$CONTRACT" 2>/dev/null)"
# ★空 category (キーはあるが item 0) の拒否: 0 件は **キー省略**で表現するのが本型の規約 (assembler も拒否)。
#   空配列で「0 件」を偽装させると、 負の主張 (この種別は変更なし) の表現が 2 通りになり束縛が壊れる。
cat_empty="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | select((.value | length) == 0)] | length' "$CONTRACT" 2>/dev/null)"
# ★照会は per-item 片側空が legit (srs/adr の少なくとも一方) ゆえ per-row 非空にしない。 doc 合算で塞ぐ。
refs_srs_total="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | (.refs.srs // [])[]] | length' "$CONTRACT" 2>/dev/null)"
refs_adr_total="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | (.refs.adr // [])[]] | length' "$CONTRACT" 2>/dev/null)"
# ★両側空の item は禁止 (どの要件のためでもなく なぜでもない変更 = 事実記録の grounding 喪失)。
refs_both_empty="$(yq -r '[[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | select((((.refs.srs // []) | length) == 0) and (((.refs.adr // []) | length) == 0))] | length' "$CONTRACT" 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.srs_doc_id // ""), (.cross_doc.adr_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric ent_n ent_valid item_total item_valid cat_total cat_ok cat_empty refs_srs_total refs_adr_total refs_both_empty xdoc_valid gloss_expected gloss_n
clmism=""
[[ "$ent_n" -ne "$ent_valid" ]] && clmism+=" entry の version/date 欠落($ent_valid/$ent_n)"
[[ "$item_total" -ne "$item_valid" ]] && clmism+=" item の id/text 欠落($item_valid/$item_total・固定 separator で恒真非空になる per-row 潰れ)"
[[ "$item_valid" -gt 0 && "$n_plain_cl" -ne "$item_valid" ]] && clmism+=" plain-C($n_plain_cl≠$item_valid)"
[[ "$cat_total" -ne "$cat_ok" ]] && clmism+=" categories キーが allowlist 外($cat_ok/$cat_total・許容 added|changed|deprecated|removed|fixed|security)"
[[ "$cat_empty" -ne 0 ]] && clmism+=" 空 category($cat_empty 件・0 件はキー省略で表現する規約。 空配列での偽装は負の主張の表現を 2 通りにし束縛を壊す)"
[[ "$ent_valid" -eq 0 ]] && clmism+=" entries空(chapter-lead-01/02 と latest-highlight が hollow)"
[[ "$item_valid" -eq 0 ]] && clmism+=" item全空(版はあるが変更が 1 件も無い=事実記録として構造不正)"
[[ "$refs_srs_total" -eq 0 ]] && clmism+=" refs.srs 全空(どの要件のための変更かが 1 件も無い・doc 合算 0)"
[[ "$refs_adr_total" -eq 0 ]] && clmism+=" refs.adr 全空(なぜ変えたかが 1 件も無い・doc 合算 0)"
[[ "$refs_both_empty" -ne 0 ]] && clmism+=" refs 両側空の item($refs_both_empty 件・srs/adr の少なくとも一方は必須)"
[[ "$xdoc_valid" -ne 2 ]] && clmism+=" cross_doc.srs_doc_id/adr_doc_id 空($xdoc_valid/2)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && clmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && clmism+=" glossary空(用語集章 chapter-lead-04 が固定ラベルのみの hollow anchor になる)"
assert_no_mismatch "$clmism"
assert_no_empty_anchor

# ============================================================================
elif [[ "$DOC_TYPE" == roadmap ]]; then
# roadmap anchor 表 (folio-vxpc・per-type authoring)。 slot↔SSoT は agents/fidelity-roadmap.md §1/§5.1 が canonical
# (この型に §2 は無い)。
#   cover-summary       → meta + |stages| + cross_doc.{vision,srs}_doc_id
#   chapter-lead-01..04 → 直近段階ハイライト / stages(段階ごと) / refs(vision/srs) / glossary
#                         (band 順 = assemble-roadmap.sh:297-300)
#   nearest-highlight   → ★直近段階 (seq 昇順先頭) の items のみ
#   plain-RMx           → 該当 item の text
#   term-inline:<term>  → glossary[i].plain_short
# ★hallmark = 未来の *宣言* (「決める」ADR でも「探索する」research でもない)。 item text / outcome / target は
#   literal 無加工で載せる (過去化・確定化「実現済み」の歪みを reviewer が検出する基準を保つ)。
# ★優先度は生トークン (must|should|could) のまま載せる — 「必須」等へ正規化すると優先度の取り違えを
#   reviewer が判定する基準が消える (tier / 区分 生トークン規律と同型)。
# ★負の主張 (「0 件 = この優先度の目標なし」) の束縛 (ehar クラス): assembler は直近段階ハイライトで 3 優先度を
#   **0 を含めて全て**数値バッジ emit する。 anchor が 0 件優先度を省略すると負の主張が消える。
# ★★自前 principle 終端を作らない (これ自体が仕様): roadmap は自前終端を持たず VISION 経由で終端到達する。
#   graph 充足のための作文終端は c5r.11 で **不採択**であり、 prose での終端作文も同罪。 よって
#   datamodel/vision/interface の principle leg を移植しない (.principle 不在は正であって欠落ではない)。
# ★.chapters も存在しない (band 見出し(生) leg を blind copy すると恒常 FAIL)。 段階は `goals` ではなく
#   stages[].items **map** (キー=優先度)。
# 全て $CONTRACT (SSoT) からのみ引き、 生成 HTML DOM は参照しない (verify-laundering 禁止)。
# ============================================================================

# 直近段階 = seq 昇順先頭 (assembler は sort -n で決定的に選ぶ。 contract の記載順に依存しない)。
NEAREST_ID="$(yq -r '.stages[] | (.seq | tostring) + "\t" + .id' "$CONTRACT" 2>/dev/null | sort -n | head -1 | cut -f2)"
# ★文言は他 guard と同じ canonical 句を使う (理由は changelog 分岐の同 guard 注記を参照)。
[[ -n "$NEAREST_ID" ]] || { echo "ceiling-anchors: anchor 抽出が contract 期待と不一致 (構造不正/抽出失敗): stages空/seq欠落(直近段階を決定できない=chapter-lead-01/nearest-highlight が hollow)" >&2; exit 2; }
# ★contract 由来値は式本文へ補間せず strenv でデータ束縛する (理由は changelog 分岐の同注記を参照)。
export NEAREST_ID

# ---- (1) cover-summary → meta + 件数 + 照会先 ----
emit_row "cover-summary" "meta.subtitle+stages(count)+cross_doc" \
  "$(q '(.meta.subtitle // "") + " ｜ 段階 " + (.stages | length | tostring) + "件 (" + ([.stages[] | .id + ":" + .name + "(" + .target + ")"] | join(", ")) + ") ｜ 照会先: VISION(" + (.cross_doc.vision_doc_id // "?") + ") / SRS(" + (.cross_doc.srs_doc_id // "?") + ")"')"

# ---- (2) chapter-lead-01..04 → 章別束ね (roadmap build() の band 呼出順に固定) ----
#   ★chapter-lead-01 (直近段階ハイライト) は 3 優先度を 0 込みで全列挙 (負の主張の束縛)。
RMCH_LABEL=( "直近段階のハイライト" "段階ごとの目標" "目標の照会先 (向かう先 / 要件)" "用語集" )
RMCH_PATH=( "stages[nearest].items(3 優先度・0 込み)" "stages" "stages[].items[].refs" "glossary" )
RM_NEAR_EXPR='"直近段階 " + strenv(NEAREST_ID) + " の 3 優先度件数 (0 = この優先度の目標なし): must=" + ((.stages[] | select(.id == strenv(NEAREST_ID)) | .items.must // []) | length | tostring) + " / should=" + ((.stages[] | select(.id == strenv(NEAREST_ID)) | .items.should // []) | length | tostring) + " / could=" + ((.stages[] | select(.id == strenv(NEAREST_ID)) | .items.could // []) | length | tostring)'
RMCH_EXPR=(
  "$RM_NEAR_EXPR"
  '[.stages[] | .id + "(seq=" + (.seq | tostring) + "・" + .name + "・目指す時期=" + .target + "): " + .outcome + " ｜ " + ([.items | to_entries[] | .key + "×" + (.value | length | tostring)] | join(", "))] | join(" ／ ")'
  '"照会: " + ([.stages[] | .items | to_entries[] | .value[] | .id + "→VISION(" + ((.refs.vision // []) | join(",")) + ")/SRS(" + ((.refs.srs // []) | join(",")) + ")"] | join(" / "))'
  '[.glossary[].term] | join(" / ")'
)
for idx in 0 1 2 3; do
  num="$(printf '%02d' $((idx + 1)))"
  emit_row "chapter-lead-$num" "${RMCH_PATH[$idx]}" "${RMCH_LABEL[$idx]}: $(q "${RMCH_EXPR[$idx]}")"
done

# ---- (3) nearest-highlight → ★直近段階 (seq 昇順先頭) の items のみ (別段階混入 = drift) ----
emit_row "nearest-highlight" "stages[id=$NEAREST_ID].items" \
  "$(q '"直近段階 " + (.stages[] | select(.id == strenv(NEAREST_ID)) | .name) + " (目指す時期=" + (.stages[] | select(.id == strenv(NEAREST_ID)) | .target) + ") で目指すこと ｜ " + (.stages[] | select(.id == strenv(NEAREST_ID)) | .outcome) + " ｜ " + '"$RM_NEAR_EXPR"' + " ｜ 中身: " + ([.stages[] | select(.id == strenv(NEAREST_ID)) | .items | to_entries[] | .key + ": " + ([.value[] | .text] | join(" / "))] | join(" ｜ "))')"

# ---- (4) plain-RMx → 該当 item の text ----
#   ★per-item の vision/srs 件数を 0 込みで併載する: 片側だけ照会する目標は「負の主張の器」であり
#     (どちらが legit に空かを reviewer に見せないと)、 欠けている側を prose が捏造で埋めた作文を判定できない。
i=0; n_plain_rm=0
while IFS=$'\t' read -r rmid; do
  if [[ -n "$rmid" && "$rmid" != "null" ]]; then
    export RMID="$rmid"   # ★式本文へ補間せず strenv でデータ束縛 (NEAREST_ID の同注記を参照)。
    emit_row "plain-$rmid" "stages[].items[id=$rmid].text" \
      "$(q '[.stages[] | .id as $sid | .name as $sname | .items | to_entries[] | .key as $prio | .value[] | select(.id == strenv(RMID)) | "段階=" + $sid + "(" + $sname + ") ｜ 優先度(生)=" + $prio + " ｜ " + .text + " ｜ 向かう先 VISION " + ((.refs.vision // []) | length | tostring) + "件(" + ((.refs.vision // []) | join(",")) + ") / 要件 SRS " + ((.refs.srs // []) | length | tostring) + "件(" + ((.refs.srs // []) | join(",")) + ")"] | join("")')"
    n_plain_rm=$((n_plain_rm + 1))
  fi
  i=$((i + 1))
done < <(yq -r '.stages[] | .items | to_entries[] | .value[] | (.id // "")' "$CONTRACT" 2>/dev/null)

# ---- (5) term-inline:<term> → glossary[i].plain_short ----
g=0; n_term=0
while IFS=$'\t' read -r term plain; do
  if [[ -n "$term" && -n "$plain" && "$plain" != "null" ]]; then
    emit_row "term-inline:$term" "glossary[$g].plain_short" "$plain"
    n_term=$((n_term + 1))
  fi
  g=$((g + 1))
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')

# ---- fail-closed guard (roadmap 用に per-type 再導出) ----
assert_slot_unique
st_n="$(q '.stages | length' 2>/dev/null)"
st_valid="$(q '[.stages[] | select(((.id // "") != "") and ((.name // "") | test("\\S")) and ((.target // "") | test("\\S")) and ((.outcome // "") | test("\\S")))] | length' 2>/dev/null)"
# ★seq は段階順 (近い→遠い) の SSoT = 「段階順の意味的乱れ」lens の判定材料。 正の整数かつ一意。
st_seq_ok="$(yq -r '[.stages[] | select(((.seq // "") | tostring) | test("^[0-9]+$"))] | length' "$CONTRACT" 2>/dev/null)"
st_seq_uniq="$(yq -r '[.stages[].seq] | unique | length' "$CONTRACT" 2>/dev/null)"
item_total="$(yq -r '[.stages[] | .items | to_entries[] | .value[]] | length' "$CONTRACT" 2>/dev/null)"
item_valid="$(yq -r '[.stages[] | .items | to_entries[] | .value[] | select(((.id // "") != "") and ((.text // "") | test("\\S")))] | length' "$CONTRACT" 2>/dev/null)"
# ★優先度 allowlist: map のキーが優先度ゆえ allowlist 外は silent に脱落する。
prio_total="$(yq -r '[.stages[] | .items | to_entries[] | .key] | length' "$CONTRACT" 2>/dev/null)"
prio_ok="$(yq -r '[.stages[] | .items | to_entries[] | select(.key == "must" or .key == "should" or .key == "could") | .key] | length' "$CONTRACT" 2>/dev/null)"
# ★空 priority (キーはあるが item 0) の拒否: 0 件はキー省略で表現する規約 (changelog と同型)。
prio_empty="$(yq -r '[.stages[] | .items | to_entries[] | select((.value | length) == 0)] | length' "$CONTRACT" 2>/dev/null)"
# ★照会は per-item 片側空が legit (vision/srs の少なくとも一方) ゆえ doc 合算で塞ぐ (risk の per-row 必須と非対称)。
refs_vis_total="$(yq -r '[.stages[] | .items | to_entries[] | .value[] | (.refs.vision // [])[]] | length' "$CONTRACT" 2>/dev/null)"
refs_srs_total="$(yq -r '[.stages[] | .items | to_entries[] | .value[] | (.refs.srs // [])[]] | length' "$CONTRACT" 2>/dev/null)"
refs_both_empty="$(yq -r '[.stages[] | .items | to_entries[] | .value[] | select((((.refs.vision // []) | length) == 0) and (((.refs.srs // []) | length) == 0))] | length' "$CONTRACT" 2>/dev/null)"
# ★自前 principle を持たないことが仕様 (c5r.11 で作文終端は不採択) — 現れたら graph 充足のための捏造終端。
prin_present="$(yq -r 'has("principle")' "$CONTRACT" 2>/dev/null)"
xdoc_valid="$(q '[(.cross_doc.vision_doc_id // ""), (.cross_doc.srs_doc_id // "")] | map(select(test("\\S"))) | length' 2>/dev/null)"
gloss_expected="$(q '[.glossary[] | select((.plain_short // "") != "")] | length' 2>/dev/null)"
gloss_n="$(q '.glossary | length' 2>/dev/null)"
assert_counts_numeric gloss_n st_n st_valid st_seq_ok st_seq_uniq item_total item_valid prio_total prio_ok prio_empty \
  refs_vis_total refs_srs_total refs_both_empty xdoc_valid gloss_expected
rmmism=""
[[ "$st_n" -ne "$st_valid" ]] && rmmism+=" stage の id/name/target/outcome 欠落($st_valid/$st_n)"
[[ "$st_n" -ne "$st_seq_ok" ]] && rmmism+=" seq が正の整数でない($st_seq_ok/$st_n・段階順の SSoT)"
[[ "$st_n" -ne "$st_seq_uniq" ]] && rmmism+=" seq 重複($st_seq_uniq/$st_n・直近段階の決定が非決定的になる)"
[[ "$item_total" -ne "$item_valid" ]] && rmmism+=" item の id/text 欠落($item_valid/$item_total)"
[[ "$item_valid" -gt 0 && "$n_plain_rm" -ne "$item_valid" ]] && rmmism+=" plain-RM($n_plain_rm≠$item_valid)"
[[ "$prio_total" -ne "$prio_ok" ]] && rmmism+=" items キーが allowlist 外($prio_ok/$prio_total・許容 must|should|could)"
[[ "$prio_empty" -ne 0 ]] && rmmism+=" 空 priority($prio_empty 件・0 件はキー省略で表現する規約)"
[[ "$st_valid" -eq 0 ]] && rmmism+=" stages空(chapter-lead-01/02 と nearest-highlight が hollow)"
[[ "$item_valid" -eq 0 ]] && rmmism+=" item全空(段階はあるが目標が 1 件も無い)"
[[ "$refs_vis_total" -eq 0 ]] && rmmism+=" refs.vision 全空(どの機能の方向へ向かうかが 1 件も無い・doc 合算 0)"
[[ "$refs_srs_total" -eq 0 ]] && rmmism+=" refs.srs 全空(どの要件のためかが 1 件も無い・doc 合算 0)"
[[ "$refs_both_empty" -ne 0 ]] && rmmism+=" refs 両側空の item($refs_both_empty 件・vision/srs の少なくとも一方は必須)"
[[ "$prin_present" == "true" ]] && rmmism+=" 自前 principle が存在(roadmap は VISION 経由で終端到達する型ゆえ自前終端は graph 充足のための捏造 = c5r.11 で不採択)"
[[ "$xdoc_valid" -ne 2 ]] && rmmism+=" cross_doc.vision_doc_id/srs_doc_id 空($xdoc_valid/2)"
[[ "$gloss_expected" -gt 0 && "$n_term" -ne "$gloss_expected" ]] && rmmism+=" term-inline($n_term≠$gloss_expected)"
[[ "$gloss_n" -eq 0 ]] && rmmism+=" glossary空(用語集章 chapter-lead-04 が固定ラベルのみの hollow anchor になる)"
assert_no_mismatch "$rmmism"
assert_no_empty_anchor

fi

# ---- JSON 出力 (jq -Rn で TSV → 凍結 schema。 anchors 順序は上の emit 順で決定的) ----
[[ -s "$ROWS" ]] || { echo "ceiling-anchors: no anchors emitted (contract 構造不正?)" >&2; exit 2; }
jq -Rn --arg doc_type "$DOC_TYPE" --arg contract "$CONTRACT" '
  {doc_type: $doc_type, contract: $contract,
   anchors: [inputs | split("\t") | {slot: .[0], ssot_path: .[1], ssot_value: .[2]}]}
' < "$ROWS"
