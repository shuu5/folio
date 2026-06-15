#!/usr/bin/env bash
# folio S4 generator — 決定的 assembler (ADR-0042 §2.1 / §2.2 / §3)
#
# 入力 contract (YAML) → 人間プレゼン HTML (catalog 部品準拠、 srs.css inline、 自己完結)。
# 内容・構造 (cover/goals/scope/actor/上位ニーズ/要件/NFR/受入/RTM/制約/用語) は contract から決定的組立。
#   - RTM の ●(backward)/受入(acceptance) は contract 集合から導出。 集合外参照・id 重複・自由記述の
#     tab/改行・未知 EARS/priority は validate() が fail-closed で生成前に拒否。
#   - 全自由記述値は HTML escape してから注入 (任意 markup を構造へ通さない)。
#   - 検証可能な数値 (件数/トレースリンク/孤立/未検証) は決定的集計し data-derived に刻む。
# 読みやすさの足場 (章リード / plain やさしい言い換え / 「なぜ要る」根拠 / 1 文サマリ) は *空* prose スロット
#   (data-prose-slot) で出力し、 後段 (③) で opus が rationale_source/glossary に接地して充填する。
# icon SVG / legend は静的デザイン資産 (CSS と同様、 contract 由来でない)。
#
# 承認デザイン (S3 example-srs.html) 相当を contract から *再生成* することを目標とする。
# usage: assemble.sh <contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement では ${v//pat/repl} の repl 中の & が
# 「マッチしたテキスト」後方参照になり esc() の HTML escape を破壊する (< → <lt; 等)。無効化する。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble.sh <contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble: yq required" >&2; exit 1; }

q() { yq -r "$1" "$CONTRACT"; }
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

declare -A EARS_CLASS=( [ubiquitous]=always [event]=trigger [state]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=恒常 [event]=きっかけ [state]=状態 [unwanted]=禁止 [optional]=機能 )
declare -A PRIO_LABEL=( [must]=必須 [should]=推奨 [may]=任意 )

# ---- icon SVG (静的資産) ----
ICO_TARGET='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1"/>'
ICO_BOX='<path d="M3 7l9-4 9 4-9 4-9-4z"/><path d="M3 7v10l9 4 9-4V7"/>'
ICO_FLOW='<path d="M12 2v6m0 0L9 5m3 3l3-3"/><circle cx="12" cy="14" r="6"/>'
ICO_CHECKSQ='<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M9 12l2 2 4-4"/>'
ICO_BOLT='<path d="M13 2L3 14h7l-1 8 10-12h-7l1-8z"/>'
ICO_CHECKSHIELD='<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'
ICO_ARROW='<path d="M5 12h14M12 5l7 7-7 7"/>'
ICO_SHIELD='<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>'
ICO_BOOK='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_CHECK_BIG='<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#ffe8a8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>'
ICO_USER='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#3a2c05" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
ico() { printf '<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">%s</svg>' "$1"; }

# ---- fail-closed contract validation ----
validate() {
  local errs=0 d p
  if [[ "$(yq '[.. | select(tag=="!!str") | test("[\t\n]")] | any' "$CONTRACT")" == "true" ]]; then
    echo "assemble: contract の文字列に tab/改行が含まれます (列ずれ防止のため禁止)" >&2; errs=1; fi
  d="$(q '(.requirements[].id, .nfr[].id)' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble: 要件/NFR id 重複: $d" >&2; errs=1; }
  d="$(q '.upper_needs[].id' | sort | uniq -d)";               [[ -z "$d" ]] || { echo "assemble: ニーズ id 重複: $d" >&2; errs=1; }
  d="$(q '.acceptance[].id' | sort | uniq -d)";                [[ -z "$d" ]] || { echo "assemble: 受入 id 重複: $d" >&2; errs=1; }
  d="$(comm -23 <(q '(.requirements + .nfr)[].trace.backward[]' | sort -u) <(q '.upper_needs[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble: 未定義の上位ニーズ参照: $d" >&2; errs=1; }
  d="$(comm -23 <(q '(.requirements + .nfr)[].trace.acceptance[]' | sort -u) <(q '.acceptance[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble: 未定義の受入基準参照: $d" >&2; errs=1; }
  d="$(comm -23 <(q '.acceptance[].links[]' | sort -u) <(q '(.requirements[].id, .nfr[].id)' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble: 受入の links が未定義の要件を指す: $d" >&2; errs=1; }
  for p in $(q '.requirements[].ears.pattern'); do [[ -v EARS_CLASS[$p] ]] || { echo "assemble: 未知の EARS pattern: $p" >&2; errs=1; }; done
  for p in $(q '.requirements[].priority');     do [[ -v PRIO_LABEL[$p] ]] || { echo "assemble: 未知の priority: $p" >&2; errs=1; }; done
  for p in $(q '.actors[].tint'); do case "$p" in brand|violet|warn|info|ok|bad) ;; *) echo "assemble: 未知の actor tint (CSS allowlist 外): $p" >&2; errs=1 ;; esac; done
  [[ "$errs" -eq 0 ]] || { echo "assemble: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

in_csv() { local needle="$1" hay="${2-}" x; IFS=',' read -ra _a <<< "$hay"; for x in "${_a[@]}"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

CHAPN=0
band() { # tint kicker heading icon_inner
  CHAPN=$((CHAPN+1)); local num; printf -v num '%02d' "$CHAPN"
  printf '<section data-component="chapter-deck-band" class="tint-%s"><span class="num">%s</span><span class="kicker">%s %s</span><h2>%s</h2><p class="lead" data-prose-slot="chapter-lead" data-slot-id="chapter-lead-%s"></p></section>\n<div class="chapbody">\n' \
    "$1" "$num" "$(ico "$4")" "$(esc "$2")" "$(esc "$3")" "$num"
}
band_end() { printf '</div>\n'; }

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio S4 assembler (ADR-0042) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  printf '<header data-component="doc-cover-band">\n'
  printf '<p class="cover-eyebrow"><span class="doc-type">%s</span> <span>%s</span></p>\n' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")"
  printf '<h1>%s</h1>\n' "$(esc "$(q '.meta.title')")"
  printf '<p class="cover-sub">%s</p>\n' "$(esc "$(q '.meta.subtitle')")"
  printf '<div class="summary-card"><span class="ic">%s</span><div><p class="lab">この文書が約束すること (1 文サマリ)</p><p class="txt" data-prose-slot="cover-summary" data-slot-id="cover-summary"></p></div></div>\n' "$ICO_CHECK_BIG"
  frng="$(q '.requirements | length')件 ($(esc "$(q '.requirements[0].id')")–$(esc "$(q '.requirements[-1].id')"))"
  nrng="$(q '.nfr | length')件 ($(esc "$(q '.nfr[0].id')")–$(esc "$(q '.nfr[-1].id')"))"
  arng="$(q '.acceptance | length')件 ($(esc "$(q '.acceptance[0].id')")–$(esc "$(q '.acceptance[-1].id')"))"
  printf '<div class="cover-meta"><span class="m"><span class="k">機能要件</span><span class="v">%s</span></span><span class="m"><span class="k">非機能要件</span><span class="v">%s</span></span><span class="m"><span class="k">受入基準</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$frng" "$nrng" "$arng" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  printf '<div data-component="approval-block">\n'
  q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r role who when stamp; do
    [[ -n "$role" ]] || continue; sc=""; [[ "$stamp" != "承認済" ]] && sc=" self"
    printf '<div class="sign"><span class="role">%s</span><span class="who">%s</span><span class="when">%s</span><span class="stamp%s">%s</span></div>\n' "$(esc "$role")" "$(esc "$who")" "$(esc "$when")" "$sc" "$(esc "$stamp")"
  done
  printf '</div>\n'
  printf '<div class="reader-chip">%s 想定読者: %s</div>\n' "$ICO_USER" "$(esc "$(q '.meta.reader')")"
  printf '</header>\n'
}

emit_goals() {
  printf '<div data-component="section-lead-callout">\n'
  q '.goals[] | [.id, .headline, .desc] | @tsv' | while IFS=$'\t' read -r id head desc; do
    [[ -n "$id" ]] || continue
    printf '<div class="card accent"><div class="cid">%s</div><p class="ct">%s</p><p class="cd">%s</p></div>\n' "$(esc "$id")" "$(esc "$head")" "$(esc "$desc")"
  done
  printf '</div>\n'
}

emit_scope() {
  printf '<div data-component="scope-summary-panel"><div class="scol in"><h3>✓ 扱う (in scope)</h3><ul>\n'
  q '.scope.in[]' | while IFS= read -r item; do [[ -n "$item" ]] && printf '<li><span class="b">●</span>%s</li>\n' "$(esc "$item")"; done
  printf '</ul></div><div class="scol out"><h3>✕ 扱わない (out of scope)</h3><ul>\n'
  q '.scope.out[]' | while IFS= read -r item; do [[ -n "$item" ]] && printf '<li><span class="b">●</span>%s</li>\n' "$(esc "$item")"; done
  printf '</ul></div></div>\n'
}

emit_actors() {
  printf '<div data-component="actor-stakeholder-table" style="margin-top:20px">\n'
  q '.actors[] | [.key, .name, .role, .external, .tint] | @tsv' | while IFS=$'\t' read -r key name role ext tint; do
    [[ -n "$key" ]] || continue; extb=""; [[ "$ext" == "true" ]] && extb='<span class="ext-badge">外部</span>'
    printf '<div class="actor"><span class="av" style="background:var(--%s)">%s</span><div><div class="nm">%s%s</div><div class="role">%s</div></div></div>\n' \
      "$(esc "$tint")" "$(esc "$key")" "$(esc "$name")" "$extb" "$(esc "$role")"
  done
  printf '</div>\n'
}

emit_origin_table() {
  printf '<div class="tbl-wrap"><table data-component="source-trace-origin"><thead><tr><th>ニーズID</th><th>事業ニーズ</th><th>出どころ</th></tr></thead><tbody>\n'
  q '.upper_needs[] | [.id, .need, .origin] | @tsv' | while IFS=$'\t' read -r id need origin; do
    [[ -n "$id" ]] || continue
    printf '<tr data-component="source-trace-row"><td><span class="nid">%s</span></td><td>%s</td><td><span class="origin">%s</span></td></tr>\n' "$(esc "$id")" "$(esc "$need")" "$(esc "$origin")"
  done
  printf '</tbody></table></div>\n'
}

emit_legend() {
  printf '<div class="ears-legend"><span class="lt">タイプ:</span> <span class="ears trigger">きっかけ <span class="en">When</span></span> <span class="ears state">状態 <span class="en">While</span></span> <span class="ears forbid">禁止 <span class="en">If-Then</span></span> <span class="ears always">恒常 <span class="en">Ubiq.</span></span> <span class="lt" style="margin-left:8px">優先:</span><span class="prio must" data-component="priority-badge">必須</span><span class="prio should">推奨</span> <span class="lt" style="margin-left:8px">検証:</span><span class="vmeth">T=テスト</span></div>\n'
}

emit_req_table() {
  printf '<div class="tbl-wrap"><table data-component="requirement-matrix-table"><thead><tr><th>ID</th><th>タイプ</th><th>いつ (条件)</th><th>何をする (+ やさしい言い換え + なぜ要る)</th><th>優先/検証</th></tr></thead><tbody>\n'
  q '.requirements[] | [.id, .ears.pattern, .ears.condition, .ears.response, .priority, .vmethod, (.rationale_source // "")] | @tsv' \
  | while IFS=$'\t' read -r id pat cond resp prio vmeth rsrc; do
      [[ -n "$id" ]] || continue; src_attr=""; [[ -n "$rsrc" && "$rsrc" != "null" ]] && src_attr=" data-source=\"$(esc "$rsrc")\""
      printf '<tr data-component="ears-requirement-row"><td><span class="fid">%s</span></td><td><span class="ears %s">%s</span></td><td class="cond">%s</td><td class="resp">%s<span class="plain" data-prose-slot="plain" data-slot-id="plain-%s"></span><span class="why" data-prose-slot="rationale"%s data-slot-id="rationale-%s"></span></td><td><span class="prio %s">%s</span> <span class="vmeth">%s</span></td></tr>\n' \
        "$(esc "$id")" "${EARS_CLASS[$pat]}" "${EARS_LABEL[$pat]}" "$(esc "$cond")" "$(esc "$resp")" "$(esc "$id")" "$src_attr" "$(esc "$id")" "$prio" "${PRIO_LABEL[$prio]}" "$(esc "$vmeth")"
    done
  printf '</tbody></table></div>\n'
}

emit_nfr_hero() {
  printf '<div data-component="nfr-hero-metrics">\n'; i=0
  q '.nfr[] | select(.hero) | [.hero.cat // "", .hero.big // "", .hero.unit // "", .hero.qual // ""] | @tsv' | while IFS=$'\t' read -r cat big unit qual; do
    i=$((i+1)); printf '<div class="nfr-hero c%s"><div class="cat">%s</div><div class="big">%s<span class="u">%s</span></div><div class="qual">%s</div></div>\n' "$i" "$(esc "$cat")" "$(esc "$big")" "$(esc "$unit")" "$(esc "$qual")"
  done
  printf '</div>\n'
}

emit_nfr_table() {
  printf '<div class="tbl-wrap"><table data-component="nfr-metrics-table"><thead><tr><th>ID</th><th>区分</th><th>目標値 (+ やさしい言い換え)</th><th>測り方</th></tr></thead><tbody>\n'
  q '.nfr[] | [.id, .category, .target, .measure] | @tsv' | while IFS=$'\t' read -r id categ tgt meas; do
    [[ -n "$id" ]] || continue
    printf '<tr data-component="nfr-metric-row"><td><span class="nid">%s</span></td><td>%s</td><td><span class="tgt">%s</span><span class="plain" data-prose-slot="plain" data-slot-id="plain-%s"></span></td><td class="meas">%s</td></tr>\n' "$(esc "$id")" "$(esc "$categ")" "$(esc "$tgt")" "$(esc "$id")" "$(esc "$meas")"
  done
  printf '</tbody></table></div>\n'
}

emit_acceptance() {
  printf '<div data-component="acceptance-criteria-checklist">\n'
  q '.acceptance[] | [.id, (.links | join("/")), .criterion, (.metric_v // ""), (.metric_l // "")] | @tsv' | while IFS=$'\t' read -r id links crit mv ml; do
    [[ -n "$id" ]] || continue
    printf '<div class="ac"><div class="aid">%s ← %s</div><p class="at">%s</p><div class="metric"><span class="v">%s</span><span class="l">%s</span></div></div>\n' "$(esc "$id")" "$(esc "$links")" "$(esc "$crit")" "$(esc "$mv")" "$(esc "$ml")"
  done
  printf '</div>\n'
}

emit_rtm_fold() {
  local nreq nneed nlinks niso nunv
  nreq="$(q '(.requirements + .nfr) | length')"; nneed="$(q '.upper_needs | length')"
  nlinks="$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"
  niso="$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')"
  nunv="$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')"
  printf '<details data-component="rtm-collapse" class="rtm-fold"><summary>トレーサビリティ表 (RTM) を開く</summary>\n'
  printf '<p class="rtm-summary-derived" data-derived="req=%s;need=%s;link=%s;iso=%s;unv=%s">要件 %s 件 / 上位ニーズ %s 件 / トレースリンク %s 本 / 孤立要件 (出所なし) %s 件 / 未検証要件 (受入なし) %s 件</p>\n' \
    "$nreq" "$nneed" "$nlinks" "$niso" "$nunv" "$nreq" "$nneed" "$nlinks" "$niso" "$nunv"
  printf '<p data-prose-slot="rtm-summary" data-slot-id="rtm-summary"></p>\n'
  local -a NEEDS NSHORT; mapfile -t NEEDS < <(q '.upper_needs[].id'); mapfile -t NSHORT < <(q '.upper_needs[].short')
  printf '<div data-component="rtm-grid"><table class="rtm"><thead><tr><th>要件</th>'
  local k; for k in "${!NEEDS[@]}"; do printf '<th class="grp">%s %s</th>' "$(esc "${NEEDS[$k]}")" "$(esc "${NSHORT[$k]}")"; done
  printf '<th>受入で検証</th></tr></thead><tbody>\n'
  q '(.requirements + .nfr)[] | [.id, (.label // ""), (.trace.backward | join(",")), (.trace.acceptance | join(","))] | @tsv' \
  | while IFS=$'\t' read -r id label back acc; do
      [[ -n "$id" ]] || continue
      lbl=""; [[ -n "$label" ]] && lbl=" <span class=\"lbl\">$(esc "$label")</span>"
      printf '<tr><th>%s%s</th>' "$(esc "$id")" "$lbl"
      for k in "${!NEEDS[@]}"; do
        if in_csv "${NEEDS[$k]}" "$back"; then printf '<td class="hit"><span class="dot" data-trace-link="%s__%s">●</span></td>' "$(esc "$id")" "$(esc "${NEEDS[$k]}")"
        else printf '<td></td>'; fi
      done
      printf '<td class="hit">'; IFS=',' read -ra _ac <<< "$acc"
      for a in "${_ac[@]}"; do [[ -n "$a" ]] && printf '<span class="dot ac" data-acc-link="%s__%s">%s</span>' "$(esc "$id")" "$(esc "$a")" "$(esc "$a")"; done
      printf '</td></tr>\n'
    done
  printf '</tbody></table></div></details>\n'
}

emit_constraints() {
  printf '<table data-component="constraint-callout"><tbody>\n'
  q '.constraints[] | [.id, .label, .text, (.regulation // "")] | @tsv' | while IFS=$'\t' read -r id label text reg; do
    [[ -n "$id" ]] || continue; rb=""; [[ -n "$reg" ]] && rb=" <span class=\"reg-badge\">法令 $(esc "$reg")</span>"
    printf '<tr><td class="cid2">%s</td><td class="cl">%s</td><td>%s%s</td></tr>\n' "$(esc "$id")" "$(esc "$label")" "$(esc "$text")" "$rb"
  done
  printf '</tbody></table>\n'
}

emit_glossary() {
  printf '<div data-component="glossary-term-table">\n'
  q '.glossary[] | [.term, (.en // ""), .def] | @tsv' | while IFS=$'\t' read -r term en def; do
    [[ -n "$term" ]] || continue; enb=""; [[ -n "$en" ]] && enb="<span class=\"en\">$(esc "$en")</span>"
    printf '<div class="grow"><div class="gword">%s%s</div><div class="gdef">%s</div></div>\n' "$(esc "$term")" "$enb" "$(esc "$def")"
  done
  printf '</div>\n'
}

emit_footer() {
  printf '<footer class="foot" data-component="fidelity-sync-meta"><div class="ft-grid">\n'
  printf '<div>機械SSoT: <b>%s</b> &middot; 生成: <b>%s</b> &middot; 検証状態: <b>structure ✓ fabrication-free / prose 未充填 (opus 待ち)</b></div>\n' "$(esc "${CONTRACT##*/}")" "$(date -u '+%Y-%m-%d %H:%M')"
  printf '<div class="tags"><span>folio design system</span><span>deck × B2</span><span>ISO/IEC/IEEE 29148</span><span>S4 生成</span></div>\n'
  printf '</div></footer>\n'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band brand  "ゴール / 絶対に避けたい 3 つの事故"      "「これが起きたら失敗」を先に決める"          "$ICO_TARGET";        emit_goals;                  band_end
  band info   "範囲 / だれが関わるか"                    "この文書が扱う範囲と、 登場人物"            "$ICO_BOX";           emit_scope; emit_actors;     band_end
  band violet "上位ニーズ / なぜこの要件群が要るか"      "この文書の要件は、 どの事業ニーズから来たか" "$ICO_FLOW";          emit_origin_table;           band_end
  band brand  "機能要件 / システムが必ずやること"        "注文確定までに、 システムが何をするか"      "$ICO_CHECKSQ";       emit_legend; emit_req_table;  band_end
  band violet "非機能要件 / 速さ・安定・安全の数値約束"  "「どれくらい速く・落ちず・安全か」を数字で約束する" "$ICO_BOLT";   emit_nfr_hero; emit_nfr_table; band_end
  band ok     "受入基準 / 「できた」と言える条件"        "これを満たせば「完成」と判定する"          "$ICO_CHECKSHIELD";   emit_acceptance;             band_end
  band info   "トレーサビリティ / 抜け漏れチェック表"    "事業ニーズ → 機能 → 検証 が全部つながっているか" "$ICO_ARROW";     emit_rtm_fold;               band_end
  band warn   "制約・規制 / 守らねばならない外枠"        "設計の前に決まっている制約と、 法令"        "$ICO_SHIELD";        emit_constraints;            band_end
  band brand  "用語集 / この文書で使う専門語"            "本文に出てくる専門語のやさしい説明"        "$ICO_BOOK";          emit_glossary;               band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
tmp="$(mktemp)"; build > "$tmp"
if [[ "$OUT" == "/dev/stdout" ]]; then cat "$tmp"; rm -f "$tmp"; else mv "$tmp" "$OUT"; echo "assemble: wrote $OUT" >&2; fi
