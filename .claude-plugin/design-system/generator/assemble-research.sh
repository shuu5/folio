#!/usr/bin/env bash
# folio engine B3 (folio-ar1) — research-pack 決定的 assembler (instance#3 / rule-of-three)
#
# 入力 research contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS generator (assemble-srs.sh) / ADR generator (assemble-adr.sh) と *同型* の機構を research-pack schema
# (question / findings / approaches / open_questions / outcome) へ適用する:
#   - 内容・構造は contract から決定的組立。 元データに無い行・方式・照会 edge を生成できない。
#   - ★cross-doc 前方照会 edge: approaches[].leads_to が後続 ADR contract の .options[].id に実在することを
#     validate() が *生成前に* fail-closed で確かめる (B0 论点2 抽象ロール graph・ADR→SRS と同じ機構を別ターゲットへ)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 role/status は拒否。
#   - prose スロット (章リード / plain / 1 文サマリ) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# ★B3 の合格条件 = lib/ (core) を 1 バイトも変えず純粋 pack として挿さること (rule-of-three 止め時判定)。
# inject-prose.sh も SRS/ADR と無改変共用 (data-slot-id ベースで pack 非依存)。
#
# usage: assemble-research.sh <research-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-research.sh <research-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-research: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-research: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-research: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
# B2 (folio-5ua): SRS-pack / ADR-pack と共通の idiom は lib/common.sh から source。 本 file は research-pack 固有
# (cross-doc 前方照会 / question/findings/approaches/open_questions/outcome emitter) を残す。
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# 抽象ロール (B0 论点2 照会 graph) / research_status の allowlist。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
declare -A RSTATUS_OK=( [open]=1 [concluded]=1 )
declare -A RSTATUS_LABEL=( [open]=調査中 [concluded]=決着済 )

# ---- icon SVG (research-pack 固有。 共用 icon=ICO_FLOW/SHIELD/BOOK/CHECK_BIG/USER + ico() は lib/common.sh) ----
ICO_QUESTION='<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.8.5-1 .9-1 1.7"/><path d="M12 17h.01"/>'
ICO_MAGNIFY='<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>'
ICO_FORK='<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="12" r="2.5"/><path d="M8.5 6H13a3 3 0 0 1 3 3v.5M8.5 18H13a3 3 0 0 0 3-3v-.5"/>'
ICO_OPENQ='<circle cx="12" cy="12" r="9"/><circle cx="8" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="16" cy="12" r="1"/>'
ICO_ARROW='<path d="M4 12h14"/><path d="M13 6l6 6-6 6"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 d p
  core_validate_strings "assemble-research" || errs=1
  # id 一意性 (findings / approaches / open_questions)
  d="$(q '.findings[].id' | sort | uniq -d)";        [[ -z "$d" ]] || { echo "assemble-research: finding id 重複: $d" >&2; errs=1; }
  d="$(q '.approaches[].id' | sort | uniq -d)";       [[ -z "$d" ]] || { echo "assemble-research: approach id 重複: $d" >&2; errs=1; }
  d="$(q '.open_questions[].id' | sort | uniq -d)";   [[ -z "$d" ]] || { echo "assemble-research: open-question id 重複: $d" >&2; errs=1; }
  # research_status allowlist
  p="$(q '.meta.research_status')"; [[ -v RSTATUS_OK[$p] ]] || { echo "assemble-research: 未知の research_status: $p (open|concluded)" >&2; errs=1; }
  # approaches[].role allowlist (抽象ロール graph)
  for p in $(q '.approaches[].role'); do [[ -v ROLE_OK[$p] ]] || { echo "assemble-research: 未知の照会 role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done
  # ★cross-doc 前方照会の終端解決: 参照先 ADR contract 実在 + approaches[].leads_to が ADR option ID に実在
  #   ＋ adr_doc_id 一致 ＋ outcome.resolved_by == adr_doc_id (照会終端側の整合)。
  #   ★この cross-doc 解決ブロックは pack-local (ADR の justifies 解決と同型・3 度目の重複)。
  #     lib/ に上げず本 file に置く = helper 自身の rule-of-three。 core 昇格候補は bd notes へ記録 (実装は別 issue)。
  local adr_rel adr_abs adr_docid expect_docid resolved missing
  adr_rel="$(q '.cross_doc.adr_contract')"
  adr_abs="${CONTRACT_DIR}/${adr_rel}"
  if [[ ! -f "$adr_abs" ]]; then
    echo "assemble-research: cross_doc.adr_contract が見つからない: $adr_rel (照会先 ADR 不在)" >&2; errs=1
  else
    adr_docid="$(yq -r '.meta.doc_id' "$adr_abs")"
    expect_docid="$(q '.cross_doc.adr_doc_id')"
    [[ "$adr_docid" == "$expect_docid" ]] || { echo "assemble-research: cross_doc.adr_doc_id ($expect_docid) が ADR contract の doc_id ($adr_docid) と不一致" >&2; errs=1; }
    resolved="$(q '.outcome.resolved_by')"
    [[ "$resolved" == "$expect_docid" ]] || { echo "assemble-research: outcome.resolved_by ($resolved) が cross_doc.adr_doc_id ($expect_docid) と不一致" >&2; errs=1; }
    # ★空/null の leads_to は dangling 判定 (comm -23) が空行を空 missing に畳んで素通すため明示拒否する
    #   (空文字列は「option に繋がらない壊れた前方参照」= 本 pack の核の壊れ方そのもの。 ADR pack も同型 idiom)。
    local n_app n_leads
    n_app="$(q '.approaches | length')"; n_leads="$(q '[.approaches[] | select((.leads_to // "") != "")] | length')"
    [[ "$n_app" == "$n_leads" ]] || { echo "assemble-research: ★cross-doc 前方照会の空 leads_to (有効 $n_leads/$n_app 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
    missing="$(comm -23 <(q '.approaches[].leads_to' | sort -u) <(yq -r '.options[].id' "$adr_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-research: ★cross-doc 前方照会の dangling: approaches の leads_to が ADR option に実在しない: $missing" >&2; errs=1; }
  fi
  core_validate_glossary_substring "assemble-research" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-research: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# band / band_end (chapter-deck-band) は lib/common.sh (core) を使う。

# ---- research 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_research_css() {
  cat <<'CSS'
/* ===== research-pack 固有部品 (folio-ar1 / instance#3)。 srs.css の token を流用 ===== */
[data-component="research-question-panel"]{border:1px solid var(--info-line);border-left:3px solid var(--info);border-radius:12px;padding:15px 18px;background:var(--info-tint);margin:6px 0 16px}
[data-component="research-question-panel"] .q-kick{font-size:11.5px;font-weight:800;letter-spacing:.05em;color:var(--info);text-transform:uppercase;margin:0 0 6px}
[data-component="research-question-panel"] .q-text{font-size:15.5px;font-weight:700;line-height:1.7;margin:0;color:var(--ink)}
[data-component="research-finding-row"]{display:flex;gap:12px;align-items:flex-start;padding:13px 16px;border:1px solid var(--line);border-left:3px solid var(--brand);border-radius:10px;background:var(--paper-2);margin:10px 0}
[data-component="research-finding-row"] .fnid{flex:0 0 auto;font-weight:700;font-size:12px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:6px;padding:2px 8px;letter-spacing:.02em}
[data-component="research-finding-row"] .fnbody .fnh{font-weight:700;margin:0 0 3px;font-size:14.5px}
[data-component="research-finding-row"] .fnbody .fnd{margin:0;color:var(--ink-soft);font-size:13.5px;line-height:1.7}
.ap-grid{display:flex;flex-direction:column;gap:12px;margin:10px 0}
[data-component="research-approach-card"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.ap-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:4px}
.ap-head .ap-id{font-weight:700;font-size:12px;color:var(--ink-soft)}
.ap-head .ap-name{font-weight:800;font-size:15px}
[data-component="cross-doc-leads-chip"]{margin-left:auto;display:inline-flex;align-items:center;gap:5px;font-size:11.5px;font-weight:700;border-radius:999px;padding:2px 11px;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);white-space:nowrap}
[data-component="research-approach-card"] .ap-sum{margin:2px 0 8px;color:var(--ink-soft);font-size:13.5px;line-height:1.7}
[data-component="research-approach-card"] .ap-plain{display:block;margin:0 0 9px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px}
[data-component="research-approach-card"] .ap-assess{margin:0;font-size:13px;color:var(--ink);background:var(--paper-2);border:1px solid var(--line);border-radius:8px;padding:8px 11px;line-height:1.7}
[data-component="research-approach-card"] .ap-assess .ak{font-size:11px;font-weight:800;letter-spacing:.04em;color:var(--ink-faint);margin-right:6px}
.oq-list{display:flex;flex-direction:column;gap:10px;margin:8px 0}
[data-component="research-open-question"]{display:flex;gap:11px;align-items:flex-start;border:1px dashed var(--warn-line);background:var(--warn-tint);border-radius:10px;padding:11px 15px}
[data-component="research-open-question"] .oqid{flex:0 0 auto;font-weight:800;font-size:12px;color:var(--warn);background:var(--paper);border:1px solid var(--warn-line);border-radius:6px;padding:1px 8px}
[data-component="research-open-question"] .oqt{margin:0;font-size:13.5px;color:var(--ink);line-height:1.65}
[data-component="research-outcome-panel"]{border:2px solid var(--ok);border-radius:14px;padding:16px 18px;background:var(--ok-tint);margin:8px 0}
[data-component="research-outcome-panel"] .oc-kick{font-size:11.5px;font-weight:700;letter-spacing:.05em;color:var(--ok);text-transform:uppercase}
[data-component="research-outcome-panel"] .oc-resolved{font-size:15.5px;font-weight:700;line-height:1.7;margin:5px 0 4px}
[data-component="research-outcome-panel"] .oc-plain{display:block;font-size:13.5px;color:var(--ink-soft);line-height:1.7;margin:0 0 8px}
[data-component="research-outcome-panel"] .oc-note{display:block;font-size:13px;color:var(--ink);background:var(--paper);border:1px solid var(--ok-line);border-radius:8px;padding:8px 11px;line-height:1.75}
[data-component="research-outcome-panel"] .oc-tgt{font-size:11.5px;color:var(--ink-faint);margin:8px 0 0}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio research-pack assembler (folio-ar1 / instance#3) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_research_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "この調査がたどり着いたこと (1 文サマリ)"
  local rstat napp nfnd
  rstat="${RSTATUS_LABEL[$(q '.meta.research_status')]:-$(q '.meta.research_status')}"
  napp="$(q '.approaches | length')件 ($(esc "$(q '.approaches[0].id')")–$(esc "$(q '.approaches[-1].id')"))"
  nfnd="$(q '.findings | length')件"
  printf '<div class="cover-meta"><span class="m"><span class="k">状態</span><span class="v">%s</span></span><span class="m"><span class="k">検討した方式</span><span class="v">%s</span></span><span class="m"><span class="k">わかったこと</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$(esc "$rstat")" "$napp" "$nfnd" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (この調査の行き先 = 決着した ADR・folio-c5r.9 で #decision へ deep-link)
  local ADR_HTML; ADR_HTML="$(q '.cross_doc.adr_html')"
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s この調査の行き先: <a class="xref-doc" href="%s#decision"><b>%s</b></a> — %s</div>\n' "$ICO_USER" "$(esc "$ADR_HTML")" "$(esc "$(q '.cross_doc.adr_doc_id')")" "$(esc "$(q '.cross_doc.adr_title')")"
  core_emit_approval_block
  core_emit_cover_tail
}

emit_question() {
  printf '<div data-component="research-question-panel"><p class="q-kick">中心の問い</p><p class="q-text">%s</p></div>\n' "$(mark_terms "$(q '.question.summary')")"
  printf '<div data-component="scope-summary-panel"><div class="scol in"><h3>\xe2\x9c\x93 調べる範囲</h3><ul>\n'
  while IFS= read -r s; do [[ -n "$s" ]] && printf '<li><span class="b">\xe2\x97\x8f</span>%s</li>\n' "$(mark_terms "$s")"; done < <(q '.question.in_scope[]')
  printf '</ul></div><div class="scol out"><h3>\xe2\x9a\x96 調べない範囲</h3><ul>\n'
  while IFS= read -r s; do [[ -n "$s" ]] && printf '<li><span class="b">\xe2\x97\x8f</span>%s</li>\n' "$(mark_terms "$s")"; done < <(q '.question.out_scope[]')
  printf '</ul></div></div>\n'
}

emit_findings() {
  printf '<div data-component="research-finding-list">\n'
  while IFS=$'\t' read -r id summ det; do
    [[ -n "$id" ]] || continue
    printf '<div data-component="research-finding-row"><span class="fnid">%s</span><div class="fnbody"><p class="fnh">%s</p><p class="fnd">%s</p></div></div>\n' "$(esc "$id")" "$(mark_terms "$summ")" "$(mark_terms "$det")"
  done < <(q '.findings[] | [.id, .summary, .detail] | @tsv')
  printf '</div>\n'
}

emit_approaches() {
  printf '<div class="ap-grid">\n'
  local -a AIDS; mapfile -t AIDS < <(q '.approaches[].id')
  local aid name summ assess leads role
  local ADR_HTML; ADR_HTML="$(q '.cross_doc.adr_html')"   # ★cross-doc deep-link path 先 (folio-c5r.9・root 平置き・coarse=#decision)
  for aid in "${AIDS[@]}"; do
    name="$(q '.approaches[] | select(.id=="'"$aid"'") | .name')"
    summ="$(q '.approaches[] | select(.id=="'"$aid"'") | .summary')"
    assess="$(q '.approaches[] | select(.id=="'"$aid"'") | .assessment')"
    leads="$(q '.approaches[] | select(.id=="'"$aid"'") | .leads_to')"
    role="$(q '.approaches[] | select(.id=="'"$aid"'") | .role')"
    printf '<div data-component="research-approach-card">\n'
    # ★cross-doc 前方照会チップ: ap-id / leads-to / leads-role を同一要素に固定順で刻む (verify が突合)。
    #   可視 id は <b>OPTx</b> に出し、 verify が data-leads-to との一致を突合 (非エンジニアが読む文字の偽装を捕捉)。
    printf '<div class="ap-head"><span class="ap-id">%s</span><span class="ap-name">%s</span><a data-component="cross-doc-leads-chip" href="%s#decision" data-ap-id="%s" data-leads-to="%s" data-leads-role="%s">\xe2\x86\x92 つながる判断 <b>%s</b></a></div>\n' \
      "$(esc "$aid")" "$(mark_terms "$name")" "$(esc "$ADR_HTML")" "$(esc "$aid")" "$(esc "$leads")" "$(esc "$role")" "$(esc "$leads")"
    printf '<p class="ap-sum">%s</p>\n' "$(mark_terms "$summ")"
    printf '<span class="ap-plain" data-prose-slot="plain" data-slot-id="plain-%s"></span>\n' "$(esc "$aid")"
    printf '<p class="ap-assess"><span class="ak">評価</span>%s</p>\n' "$(mark_terms "$assess")"
    printf '</div>\n'
  done
  printf '</div>\n'
}

emit_open_questions() {
  printf '<div class="oq-list">\n'
  while IFS=$'\t' read -r id text; do
    [[ -n "$id" ]] || continue
    printf '<div data-component="research-open-question"><span class="oqid">%s</span><p class="oqt">%s</p></div>\n' "$(esc "$id")" "$(mark_terms "$text")"
  done < <(q '.open_questions[] | [.id, .text] | @tsv')
  printf '</div>\n'
}

emit_outcome() {
  printf '<div data-component="research-outcome-panel">\n'
  local ADR_HTML; ADR_HTML="$(q '.cross_doc.adr_html')"   # ★cross-doc deep-link path 先 (folio-c5r.9・coarse=#decision)
  printf '<p class="oc-kick">調査の行き先 — 決着した判断</p>\n'
  printf '<p class="oc-resolved" data-resolved-by="%s">この調査は <a class="xref-doc" href="%s#decision"><b>%s</b></a> で決着しました</p>\n' "$(esc "$(q '.outcome.resolved_by')")" "$(esc "$ADR_HTML")" "$(esc "$(q '.outcome.resolved_by')")"
  printf '<span class="oc-plain" data-prose-slot="plain" data-slot-id="outcome-plain"></span>\n'
  printf '<span class="oc-note">%s</span>\n' "$(mark_terms "$(q '.outcome.note')")"
  printf '<p class="oc-tgt">照会先 (前方参照): <a class="xref-doc" href="%s#decision"><b>%s</b></a> — %s</p>\n' "$(esc "$ADR_HTML")" "$(esc "$(q '.cross_doc.adr_doc_id')")" "$(esc "$(q '.cross_doc.adr_title')")"
  printf '</div>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# footer は core_emit_footer に research-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>research-pack</span><span>folio engine B3 (instance#3)</span><span>cross-doc 前方照会</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "調査の問い / 何を確かめるか"        "中心の問いと、 調べる範囲・調べない範囲"        "$ICO_QUESTION"; emit_question;       band_end
  band brand  "わかったこと / 観察された事実"        "調査で確かめた、 決める前の手がかり"            "$ICO_MAGNIFY";  emit_findings;       band_end
  band violet "検討した方式 / 3 つの確定方式"        "それぞれの評価と、 どの判断へつながるか"        "$ICO_FORK";     emit_approaches;     band_end
  band warn   "未解決の問い / まだ決めていないこと"  "この調査では結論を出さない論点"                "$ICO_OPENQ";    emit_open_questions; band_end
  band ok     "この調査の行き先 / どこで決着したか"  "前方参照 — どの設計判断 (ADR) に引き継いだか"  "$ICO_ARROW";    emit_outcome;        band_end
  band brand  "用語集 / この文書で使う専門語"        "本文に出てくる専門語のやさしい説明"            "$ICO_BOOK";     emit_glossary;       band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-research"
