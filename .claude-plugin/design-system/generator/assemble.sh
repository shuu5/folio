#!/usr/bin/env bash
# folio S4 generator — 決定的 assembler (ADR-0042 §2.1)
#
# 入力 contract (YAML) → 人間プレゼンの *構造* HTML (data-component 付き、 srs.css inline)。
# 構造 (要件表 / NFR 表 / 出所表 / RTM グリッド) は contract から *決定的に* 組み立てる:
#   - RTM の ● セルは trace.backward から、 受入 (検証) セルは trace.acceptance から導出。
#   - backward は upper_needs、 acceptance は acceptance の *正典集合* からのみ参照でき、
#     集合外の参照・id 重複・自由記述中の tab/改行は validate() が fail-closed で拒否する。
#   - 自由記述値は全て HTML escape してから注入する (markup 注入を構造へ通さない)。
#   よって assembler は元データに無い行・列・リンクを生成できない (構成上 fabrication-free)。
# prose スロット (章リード / plain やさしい言い換え / 「なぜ要る」根拠 / RTM サマリ) は *空* で出力し
#   data-prose-slot で印付ける。 後段 (step 3) で opus が rationale_source / glossary に接地して充填する。
# 検証可能な数値 (件数・トレースリンク数・孤立件数・未検証件数) は assembler が決定的集計で埋める
#   (= opus に書かせない。 ADR-0042 §3 の要約捏造リスク緩和)。verify が独立再計算で突合する。
#
# 注: rtm-collapse / nfr-metric-row / source-trace-row / plain スロットは generator 導入の新部品。
#     catalog 正式登録 + taxonomy §3 + gate G 被覆は S6 (folio-16y) へ申し送る (README open-items)。
#
# usage: assemble.sh <contract.yaml> [out.html]   (out 省略時は stdout)

set -euo pipefail

CONTRACT="${1:?usage: assemble.sh <contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"

[[ -f "$CONTRACT" ]] || { echo "assemble: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble: yq required" >&2; exit 1; }

q() { yq -r "$1" "$CONTRACT"; }

# HTML escape (& を最初に)。pure param-expansion ゆえ subprocess なし。
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

declare -A EARS_CLASS=( [ubiquitous]=always [event]=trigger [state]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=常時 [event]=きっかけ [state]=状態 [unwanted]=禁止 [optional]=機能 )
declare -A PRIO_LABEL=( [must]=必須 [should]=推奨 [may]=任意 )

# ---- fail-closed contract validation (これが @tsv / 参照整合 / fabrication-free の前提) ----
validate() {
  local errs=0 d p
  # 1. 自由記述値に tab / 改行 (@tsv 列ずれ・phantom 行の原因) を禁止
  if [[ "$(yq '[.. | select(tag=="!!str") | test("[\t\n]")] | any' "$CONTRACT")" == "true" ]]; then
    echo "assemble: contract の文字列に tab/改行が含まれます (列ずれ防止のため禁止)" >&2; errs=1
  fi
  # 2. id 一意性 (要件+NFR は RTM 行空間を共有 / ニーズ / 受入)
  d="$(q '(.requirements[].id, .nfr[].id)' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble: 要件/NFR id 重複: $d" >&2; errs=1; }
  d="$(q '.upper_needs[].id' | sort | uniq -d)";               [[ -z "$d" ]] || { echo "assemble: ニーズ id 重複: $d" >&2; errs=1; }
  d="$(q '.acceptance[].id' | sort | uniq -d)";                [[ -z "$d" ]] || { echo "assemble: 受入 id 重複: $d" >&2; errs=1; }
  # 3. 参照整合性: backward ∈ upper_needs / acceptance ∈ acceptance 正典集合
  d="$(comm -23 <(q '(.requirements + .nfr)[].trace.backward[]' | sort -u) <(q '.upper_needs[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble: 未定義の上位ニーズ参照: $d" >&2; errs=1; }
  d="$(comm -23 <(q '(.requirements + .nfr)[].trace.acceptance[]' | sort -u) <(q '.acceptance[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble: 未定義の受入基準参照: $d" >&2; errs=1; }
  # 4. EARS pattern / priority が既知値か
  for p in $(q '.requirements[].ears.pattern'); do [[ -v EARS_CLASS[$p] ]] || { echo "assemble: 未知の EARS pattern: $p" >&2; errs=1; }; done
  for p in $(q '.requirements[].priority');     do [[ -v PRIO_LABEL[$p] ]] || { echo "assemble: 未知の priority: $p" >&2; errs=1; }; done
  [[ "$errs" -eq 0 ]] || { echo "assemble: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

in_csv() { local needle="$1"; shift; local x; IFS=',' read -ra _a <<< "${1-}"; for x in "${_a[@]}"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n'
  printf '<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio S4 assembler (ADR-0042) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"                 # CSS は verbatim (cat ゆえ heredoc 展開なし)
  printf '\n</style>\n</head>\n<body class="srs">\n'
}

emit_req_table() {
  [[ "$(q '.requirements | length')" -gt 0 ]] || return 0
  printf '<div class="tbl-wrap"><table data-component="requirement-matrix-table">\n'
  printf '<thead><tr><th>ID</th><th>タイプ</th><th>いつ (条件)</th><th>何をする (+ やさしい言い換え + なぜ要る)</th><th>優先/検証</th></tr></thead><tbody>\n'
  q '.requirements[] | [.id, .ears.pattern, .ears.condition, .ears.response, .priority, .vmethod, (.rationale_source // "")] | @tsv' \
  | while IFS=$'\t' read -r id pat cond resp prio vmeth rsrc; do
      [[ -n "$id" ]] || continue
      local src_attr=""; [[ -n "$rsrc" && "$rsrc" != "null" ]] && src_attr=" data-source=\"$(esc "$rsrc")\""
      printf '<tr data-component="ears-requirement-row"><td><span class="fid">%s</span></td><td><span class="ears %s">%s</span></td><td class="cond">%s</td><td class="resp">%s<span class="plain" data-prose-slot="plain"></span><span class="why" data-prose-slot="rationale"%s></span></td><td><span class="prio %s">%s</span> <span class="vmeth">%s</span></td></tr>\n' \
        "$(esc "$id")" "${EARS_CLASS[$pat]}" "${EARS_LABEL[$pat]}" "$(esc "$cond")" "$(esc "$resp")" "$src_attr" "$prio" "${PRIO_LABEL[$prio]}" "$(esc "$vmeth")"
    done
  printf '</tbody></table></div>\n'
}

emit_nfr_table() {
  [[ "$(q '.nfr | length')" -gt 0 ]] || return 0
  printf '<div class="tbl-wrap"><table data-component="nfr-metrics-table">\n'
  printf '<thead><tr><th>ID</th><th>区分</th><th>目標値 (+ やさしい言い換え)</th><th>測り方</th></tr></thead><tbody>\n'
  q '.nfr[] | [.id, .category, .target, .measure] | @tsv' \
  | while IFS=$'\t' read -r id categ tgt meas; do
      [[ -n "$id" ]] || continue
      printf '<tr data-component="nfr-metric-row"><td><span class="nid">%s</span></td><td>%s</td><td><span class="tgt">%s</span><span class="plain" data-prose-slot="plain"></span></td><td class="meas">%s</td></tr>\n' \
        "$(esc "$id")" "$(esc "$categ")" "$(esc "$tgt")" "$(esc "$meas")"
    done
  printf '</tbody></table></div>\n'
}

emit_origin_table() {
  [[ "$(q '.upper_needs | length')" -gt 0 ]] || return 0
  printf '<div class="tbl-wrap"><table data-component="source-trace-origin">\n'
  printf '<thead><tr><th>ニーズID</th><th>事業ニーズ</th><th>出どころ</th></tr></thead><tbody>\n'
  q '.upper_needs[] | [.id, .need, .origin] | @tsv' \
  | while IFS=$'\t' read -r id need origin; do
      [[ -n "$id" ]] || continue
      printf '<tr data-component="source-trace-row"><td><span class="nid">%s</span></td><td>%s</td><td><span class="origin">%s</span></td></tr>\n' \
        "$(esc "$id")" "$(esc "$need")" "$(esc "$origin")"
    done
  printf '</tbody></table></div>\n'
}

emit_rtm_grid() {
  local -a NEEDS; mapfile -t NEEDS < <(q '.upper_needs[].id')
  printf '<div data-component="rtm-grid"><table class="rtm">\n'
  printf '<thead><tr><th>要件</th>'
  local n; for n in "${NEEDS[@]}"; do printf '<th class="grp">%s</th>' "$(esc "$n")"; done
  printf '<th>受入で検証</th></tr></thead><tbody>\n'
  q '(.requirements + .nfr)[] | [.id, (.trace.backward | join(",")), (.trace.acceptance | join(","))] | @tsv' \
  | while IFS=$'\t' read -r id back acc; do
      [[ -n "$id" ]] || continue
      printf '<tr><th>%s</th>' "$(esc "$id")"
      for n in "${NEEDS[@]}"; do
        if in_csv "$n" "$back"; then
          printf '<td class="hit"><span class="dot" data-trace-link="%s__%s">●</span></td>' "$(esc "$id")" "$(esc "$n")"
        else
          printf '<td></td>'
        fi
      done
      # 受入セル: acceptance id ごとに data-acc-link を出す (validate 済 = 集合内のみ)
      printf '<td class="hit">'
      local a; IFS=',' read -ra _ac <<< "$acc"
      for a in "${_ac[@]}"; do [[ -n "$a" ]] && printf '<span class="dot ac" data-acc-link="%s__%s">%s</span>' "$(esc "$id")" "$(esc "$a")" "$(esc "$a")"; done
      printf '</td></tr>\n'
    done
  printf '</tbody></table></div>\n'
}

emit_rtm_section() {
  local nreq nneed nlinks niso nunv
  nreq="$(q '(.requirements + .nfr) | length')"
  nneed="$(q '.upper_needs | length')"
  nlinks="$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"
  niso="$(q '[(.requirements + .nfr)[] | select((.trace.backward | length) == 0)] | length')"
  nunv="$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length) == 0)] | length')"
  printf '<section data-chapter="traceability">\n'
  printf '<div data-component="chapter-deck-band" class="tint-warn"><span class="kicker">追跡</span><h2>どの要件がどのニーズから来て、 どう検証されるか</h2><p class="lead" data-prose-slot="chapter-lead"></p></div>\n'
  printf '<details data-component="rtm-collapse" class="rtm-fold">\n'   # B = 既定折りたたみ
  printf '<summary>トレーサビリティ表 (RTM) を開く</summary>\n'
  # 決定的サマリ (検証可能な数値 = assembler が集計、 opus に書かせない。 verify が独立再計算で突合)
  printf '<p class="rtm-summary-derived" data-derived="req=%s;need=%s;link=%s;iso=%s;unv=%s">要件 %s 件 / 上位ニーズ %s 件 / トレースリンク %s 本 / 孤立要件 (出所なし) %s 件 / 未検証要件 (受入なし) %s 件</p>\n' \
    "$nreq" "$nneed" "$nlinks" "$niso" "$nunv" "$nreq" "$nneed" "$nlinks" "$niso" "$nunv"
  printf '<p data-prose-slot="rtm-summary"></p>\n'                      # opus 充填スロット (平易要約)
  emit_rtm_grid
  printf '</details></section>\n'
}

emit_footer() {
  printf '<footer data-component="fidelity-sync-meta">\n<dl>\n'
  printf '<dt>生成</dt><dd>folio S4 assembler (ADR-0042) / %s</dd>\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '<dt>元 SSoT</dt><dd>%s</dd>\n' "$(esc "${CONTRACT##*/}")"
  printf '<dt>検証状態</dt><dd>structure-only — 構造は決定的組立で fabrication-free / prose スロットは未充填 (opus step 3 待ち)</dd>\n'
  printf '</dl>\n</footer>\n</body>\n</html>\n'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<header data-component="doc-cover-band" class="tint-brand"><span class="kicker">要件定義書</span><h1>%s</h1><p class="doc-id">%s &middot; v%s</p></header>\n' \
    "$(esc "$(q '.meta.title')")" "$(esc "$(q '.meta.doc_id')")" "$(esc "$(q '.meta.version')")"

  printf '<section data-chapter="functional">\n'
  printf '<div data-component="chapter-deck-band" class="tint-info"><span class="kicker">機能要件</span><h2>システムは何をするか</h2><p class="lead" data-prose-slot="chapter-lead"></p></div>\n'
  emit_req_table
  printf '</section>\n'

  printf '<section data-chapter="nfr">\n'
  printf '<div data-component="chapter-deck-band" class="tint-violet"><span class="kicker">非機能要件</span><h2>どれくらいの品質か</h2><p class="lead" data-prose-slot="chapter-lead"></p></div>\n'
  emit_nfr_table
  printf '</section>\n'

  printf '<section data-chapter="origin">\n'
  printf '<div data-component="chapter-deck-band" class="tint-ok"><span class="kicker">出所</span><h2>なぜ要るのか (上位ニーズ)</h2><p class="lead" data-prose-slot="chapter-lead"></p></div>\n'
  emit_origin_table
  printf '</section>\n'

  emit_rtm_section
  emit_footer
}

validate
tmp="$(mktemp)"
build > "$tmp"
if [[ "$OUT" == "/dev/stdout" ]]; then cat "$tmp"; rm -f "$tmp"; else mv "$tmp" "$OUT"; echo "assemble: wrote $OUT" >&2; fi
