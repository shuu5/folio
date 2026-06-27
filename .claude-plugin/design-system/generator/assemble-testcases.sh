#!/usr/bin/env bash
# folio engine 段階2c (folio-uvt) — test-cases-pack 決定的 assembler (instance#6 / rule-of-three)
#
# 入力 test-cases contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS / ADR generator と *同型* の機構を test-cases-pack schema へ適用する:
#   - 内容・構造 (cover / scope / test_cases[] (前提・操作・期待結果) / 三段 trace / RTM / glossary)
#     は contract から決定的組立。 元データに無いケース・手順・trace edge を生成できない。
#   - ★cross-doc 前方照会 edge: test_cases[].trace.verifies (FR・role=claim) /.confirms (AC・role=verification) が
#     参照先 SRS contract の要件 / 受入基準 ID に実在することを validate() が *生成前に* fail-closed で確かめる
#     (三段 trace = 要件 FR → 受入 AC → test case。 集合外参照は拒否)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 kind/priority は拒否。
#   - prose スロット (章リード / plain 要約 / 1 文サマリ) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# inject-prose.sh は SRS/ADR と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-testcases.sh <testcases-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-testcases.sh <testcases-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-testcases: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-testcases: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-testcases: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# kind / priority allowlist (test-cases-pack 固有・visible badge へ写像)。
declare -A KIND_OK=( [正常系]=1 [異常系]=1 [境界値]=1 )
declare -A KIND_CLASS=( [正常系]=normal [異常系]=abnormal [境界値]=boundary )
declare -A PRIO_OK=( [must]=1 [should]=1 )
declare -A PRIO_LABEL=( [must]=必須 [should]=推奨 )

# ---- icon SVG (test-cases-pack 固有。 共用 icon=ICO_FLOW/SHIELD/BOOK/CHECK_BIG/USER + ico() は lib/common.sh) ----
ICO_CHECKLIST='<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>'
ICO_TARGET='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>'
ICO_FILTER='<path d="M22 3H2l8 9.5V19l4 2v-8.5z"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p d
  core_validate_strings "assemble-testcases" || errs=1
  # test_cases id 一意性
  d="$(q '.test_cases[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-testcases: test_cases id 重複: $d" >&2; errs=1; }
  # kind allowlist
  for p in $(q '.test_cases[].kind'); do [[ -v KIND_OK[$p] ]] || { echo "assemble-testcases: 未知の kind: $p (正常系|異常系|境界値)" >&2; errs=1; }; done
  # priority allowlist
  for p in $(q '.test_cases[].priority'); do [[ -v PRIO_OK[$p] ]] || { echo "assemble-testcases: 未知の priority: $p (must|should)" >&2; errs=1; }; done
  # 各 test case は verifies(FR)・confirms(AC) を 1 件以上持つ (三段 trace が片側欠けない)
  local n_incomplete
  n_incomplete="$(q '[.test_cases[] | select((.trace.verifies | length) == 0 or (.trace.confirms | length) == 0) | .id] | length')"
  [[ "$n_incomplete" == "0" ]] || { echo "assemble-testcases: trace 片側欠落 (verifies/confirms が空の test case が $n_incomplete 件・三段 trace 不成立)" >&2; errs=1; }
  # ★空/null の trace ref は dangling 判定 (comm -23) が空行を空 missing に畳んで素通すため明示拒否する
  #   (空文字列は「SRS 要件/受入基準に繋がらない壊れた前方参照」= 本 pack の核の壊れ方そのもの・ds8 idiom)。
  local n_edge n_ref
  n_edge="$(q '[.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]] | length')"
  n_ref="$(q '[ (.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]) | select((. // "") != "") ] | length')"
  [[ "$n_edge" == "$n_ref" ]] || { echo "assemble-testcases: ★cross-doc 照会の空 ref (有効 $n_ref/$n_edge 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
  # ★cross-doc 前方照会の終端解決: 参照先 SRS contract 実在 + trace の FR/AC が SRS の要件/受入基準 ID に実在
  local srs_rel srs_abs srs_docid expect_docid missing
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-testcases: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-testcases: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    missing="$(comm -23 <(q '.test_cases[].trace.verifies[], .test_cases[].trace.confirms[]' | sort -u) <(yq -r '(.requirements[].id, .acceptance[].id)' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-testcases: ★cross-doc 照会の dangling: trace の FR/AC が SRS に実在しない: $missing" >&2; errs=1; }
  fi
  core_validate_glossary_substring "assemble-testcases" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-testcases: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- test-cases-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_testcases_css() {
  cat <<'CSS'
/* ===== test-cases-pack 固有部品 (folio-uvt / instance#6)。 srs.css の token を流用 ===== */
[data-component="scope-summary-panel"]{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:10px 0}
@media(max-width:640px){[data-component="scope-summary-panel"]{grid-template-columns:1fr}}
[data-component="scope-summary-panel"] .scol{border:1px solid var(--line);border-radius:11px;padding:12px 15px}
[data-component="scope-summary-panel"] .scol.in{background:var(--ok-tint);border-color:var(--ok-line)}
[data-component="scope-summary-panel"] .scol.out{background:var(--paper-2)}
[data-component="scope-summary-panel"] .scol h3{margin:0 0 6px;font-size:13.5px}
[data-component="scope-summary-panel"] .scol.in h3{color:var(--ok)}
[data-component="scope-summary-panel"] .scol ul{margin:0;padding:0;list-style:none}
[data-component="scope-summary-panel"] .scol li{font-size:13px;line-height:1.7;color:var(--ink-soft);padding-left:18px;position:relative;margin:3px 0}
[data-component="scope-summary-panel"] .scol li .b{position:absolute;left:2px;font-size:9px;top:5px}
[data-component="scope-summary-panel"] .scol.in li .b{color:var(--ok)} [data-component="scope-summary-panel"] .scol.out li .b{color:var(--ink-faint)}
.tc-grid{display:flex;flex-direction:column;gap:14px;margin:10px 0}
[data-component="testcase-card"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.tc-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:5px}
.tc-head .tc-id{font-weight:800;font-size:12px;color:var(--ink-soft);background:var(--paper-3);border:1px solid var(--line);border-radius:6px;padding:2px 8px}
.tc-kind{font-size:11px;font-weight:700;border-radius:999px;padding:2px 10px;border:1px solid}
.tc-kind.normal{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.tc-kind.abnormal{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.tc-kind.boundary{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.tc-prio{font-size:10.5px;font-weight:700;border-radius:5px;padding:1px 7px;border:1px solid var(--line);color:var(--ink-soft);background:var(--paper-2)}
.tc-prio.must{color:var(--brand);border-color:var(--brand-line);background:var(--brand-tint)}
.tc-head .tc-title{flex:1 1 100%;font-weight:800;font-size:15px;margin:4px 0 0;line-height:1.5}
[data-component="testcase-card"] .tc-plain{display:block;margin:0 0 9px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px;line-height:1.7}
.tc-steps{display:flex;flex-direction:column;gap:6px;margin:6px 0 10px}
.tc-step{display:flex;gap:10px;align-items:flex-start;font-size:13px;line-height:1.7}
.tc-step .tc-step-k{flex:0 0 64px;font-weight:700;font-size:11.5px;color:var(--ink-faint);padding-top:1px}
.tc-step.tc-pre .tc-step-k{color:var(--info)} .tc-step.tc-act .tc-step-k{color:var(--violet)} .tc-step.tc-exp .tc-step-k{color:var(--ok)}
.tc-step .tc-step-v{flex:1 1 auto;color:var(--ink-soft)}
.tc-step-list{margin:0;padding-left:18px;flex:1 1 auto;color:var(--ink-soft)}
.tc-step-list li{margin:2px 0;line-height:1.65}
.tc-trace{background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:9px 12px}
.tc-trace .tc-trace-h{font-size:11.5px;font-weight:700;color:var(--ink-faint);margin:0 0 6px}
.tc-trace-row{display:flex;gap:8px;align-items:baseline;padding:3px 0;flex-wrap:wrap}
.tc-trace-label{flex:0 0 auto;font-size:11px;color:var(--ink-soft);font-weight:700}
.tc-trace-row.confirm .tc-trace-label{color:var(--violet)}
.tc-trace-edge{display:inline-flex;align-items:baseline;gap:4px;margin-right:4px}
.tc-ref{font-weight:800;font-size:12px;border-radius:6px;padding:1px 9px;border:1px solid;flex:0 0 auto}
.tc-trace-row.verify .tc-ref{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.tc-trace-row.confirm .tc-ref{color:var(--violet);background:var(--violet-tint);border-color:var(--violet-line)}
.tc-ref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
.tc-trace-tgt{font-size:11px;color:var(--ink-faint);margin:7px 0 0}
table[data-component="testcase-rtm"]{width:100%;border-collapse:collapse;margin:8px 0;font-size:13px}
[data-component="testcase-rtm"] th,[data-component="testcase-rtm"] td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
[data-component="testcase-rtm"] thead th{background:var(--paper-3);font-size:11.5px;color:var(--ink-soft);letter-spacing:.02em}
[data-component="testcase-rtm"] .rtm-tc{font-weight:800;color:var(--ink-soft);white-space:nowrap}
[data-component="testcase-rtm"] .rtm-kind{white-space:nowrap;font-size:12px;color:var(--ink-faint)}
[data-component="testcase-rtm"] .rtm-fr,[data-component="testcase-rtm"] .rtm-ac{font-size:12px;line-height:1.7}
[data-component="testcase-rtm"] .rtm-edge{display:inline}
[data-component="testcase-rtm"] .rtm-code{font-size:11px;font-weight:800}
[data-component="testcase-rtm"] .rtm-fr .rtm-code{color:var(--ok)} [data-component="testcase-rtm"] .rtm-ac .rtm-code{color:var(--violet)}
[data-component="testcase-rtm"] .rtm-label{font-weight:400;color:var(--ink-soft)}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="test-cases">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio test-cases-pack assembler (folio-uvt / instance#6) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_testcases_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このテスト仕様が約束すること (1 文サマリ)"
  local n_tc first last fr_label_join fr
  n_tc="$(q '.test_cases | length')"
  first="$(q '.test_cases[0].id')"; last="$(q '.test_cases[-1].id')"
  # ★cover は FR コード列挙でなく平易機能名要約 (非エンジニア可読)。 unique FR を SRS requirements[].label へ
  #   fabrication-free に写像し first-occurrence 順で join (REF_LABEL = SRS 由来・verify が同一導出で突合)。
  fr_label_join=""
  while IFS= read -r fr; do [[ -n "$fr" ]] && fr_label_join+="${fr_label_join:+・}${REF_LABEL[$fr]}"; done < <(q '[.test_cases[].trace.verifies[]] | unique | .[]')
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">件数</span><span class="v">%s</span></span><span class="m"><span class="k">検証対象</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "test-cases (テストケース仕様)" "$(esc "$n_tc")件 ($(esc "$first")–$(esc "$last"))" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (検証対象 SRS と要件の平易機能名要約)
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 検証対象: <b>%s</b> の要件 <b>%s</b></div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$fr_label_join")"
  core_emit_approval_block
  core_emit_cover_tail
}

emit_scope() {
  printf '<div data-component="scope-summary-panel"><div class="scol in"><h3>\xe2\x9c\x93 試すこと</h3><ul>\n'
  while IFS= read -r item; do [[ -n "$item" ]] && printf '<li><span class="b">\xe2\x97\x8f</span>%s</li>\n' "$(esc "$item")"; done < <(q '.scope.in[]')
  printf '</ul></div><div class="scol out"><h3>\xe2\x80\x94 試さないこと</h3><ul>\n'
  while IFS= read -r item; do [[ -n "$item" ]] && printf '<li><span class="b">\xe2\x97\x8f</span>%s</li>\n' "$(esc "$item")"; done < <(q '.scope.out[]')
  printf '</ul></div></div>\n'
}

emit_cards() {
  printf '<div class="tc-grid">\n'
  local -a TIDS; mapfile -t TIDS < <(q '.test_cases[].id')
  local tid kind kindc prio priolabel
  for tid in "${TIDS[@]}"; do
    kind="$(q '.test_cases[] | select(.id=="'"$tid"'") | .kind')"
    kindc="${KIND_CLASS[$kind]:-normal}"
    prio="$(q '.test_cases[] | select(.id=="'"$tid"'") | .priority')"
    priolabel="${PRIO_LABEL[$prio]:-$prio}"
    printf '<div data-component="testcase-card" id="tc-%s">\n' "$(esc "$tid")"
    printf '<div class="tc-head"><span class="tc-id">%s</span><span class="tc-kind %s">%s</span><span class="tc-prio %s">%s</span><h3 class="tc-title">%s</h3></div>\n' \
      "$(esc "$tid")" "$(esc "$kindc")" "$(esc "$kind")" "$(esc "$prio")" "$(esc "$priolabel")" "$(esc "$(q '.test_cases[] | select(.id=="'"$tid"'") | .title')")"
    printf '<p class="tc-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$tid")"
    printf '<div class="tc-steps">\n'
    printf '<div class="tc-step tc-pre"><span class="tc-step-k">前提</span><span class="tc-step-v">%s</span></div>\n' "$(mark_terms "$(q '.test_cases[] | select(.id=="'"$tid"'") | .precondition')")"
    printf '<div class="tc-step tc-act"><span class="tc-step-k">操作</span><ol class="tc-step-list">\n'
    while IFS= read -r st; do [[ -n "$st" ]] && printf '<li>%s</li>\n' "$(mark_terms "$st")"; done < <(q '.test_cases[] | select(.id=="'"$tid"'") | .steps[]')
    printf '</ol></div>\n'
    printf '<div class="tc-step tc-exp"><span class="tc-step-k">期待結果</span><span class="tc-step-v">%s</span></div>\n' "$(mark_terms "$(q '.test_cases[] | select(.id=="'"$tid"'") | .expected')")"
    printf '</div>\n'
    # ★三段 trace = 要件(FR・claim) → 受入(AC・verification) → このケース。 cross-doc 前方照会 edge を担う。
    printf '<div class="tc-trace"><p class="tc-trace-h">検証する要件と確かめ方 (cross-doc 照会 \xe2\x86\x92 %s)</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")"
    # ★各 trace edge = code バッジ (tc-ref・data-trace-ref/role) + SRS 由来 平易ラベル (tc-ref-label・data-label-ref)。
    #   ラベルは FR=requirements[].label / AC=acceptance[].criterion を REF_LABEL から verbatim (fabrication-free)。
    printf '<div class="tc-trace-row verify"><span class="tc-trace-label">検証する要件</span>'
    while IFS= read -r fr; do [[ -n "$fr" ]] && printf '<span class="tc-trace-edge"><a class="tc-ref" href="%s#%s" data-trace-ref="%s" data-trace-role="claim">%s</a><span class="tc-ref-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${REF_LABEL[$fr]}")"; done < <(q '.test_cases[] | select(.id=="'"$tid"'") | .trace.verifies[]')
    printf '</div>\n'
    printf '<div class="tc-trace-row confirm"><span class="tc-trace-label">確かめる受入基準</span>'
    while IFS= read -r ac; do [[ -n "$ac" ]] && printf '<span class="tc-trace-edge"><a class="tc-ref" href="%s#%s" data-trace-ref="%s" data-trace-role="verification">%s</a><span class="tc-ref-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$ac")" "$(esc "$ac")" "$(esc "$ac")" "$(esc "$ac")" "$(esc "${REF_LABEL[$ac]}")"; done < <(q '.test_cases[] | select(.id=="'"$tid"'") | .trace.confirms[]')
    printf '</div>\n'
    printf '<p class="tc-trace-tgt">照会先: %s \xe2\x80\x94 %s</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.cross_doc.srs_title')")"
    printf '</div>\n</div>\n'
  done
  printf '</div>\n'
}

# RTM = 三段 trace の一覧 (要件 → 受入 → テスト)。 FR/AC は code バッジ + SRS 由来 平易ラベル併記 (cross-doc attr は
#   持たず data-label-ref のみ・cross-doc count anchor は card 側 / ラベル fidelity は data-label-ref で別途突合)。
emit_rtm() {
  printf '<table data-component="testcase-rtm"><thead><tr><th>テストケース</th><th>区分</th><th>検証する要件</th><th>確かめる受入基準</th></tr></thead><tbody>\n'
  local -a TIDS; mapfile -t TIDS < <(q '.test_cases[].id')
  local tid kind first x
  for tid in "${TIDS[@]}"; do
    kind="$(q '.test_cases[] | select(.id=="'"$tid"'") | .kind')"
    printf '<tr data-component="rtm-row"><td class="rtm-tc">%s</td><td class="rtm-kind">%s</td>' "$(esc "$tid")" "$(esc "$kind")"
    printf '<td class="rtm-fr">'
    first=1
    while IFS= read -r x; do [[ -n "$x" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="rtm-edge"><a class="rtm-code" href="%s#%s">%s</a> <span class="rtm-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$x")" "$(esc "$x")" "$(esc "$x")" "$(esc "${REF_LABEL[$x]}")"; done < <(q '.test_cases[] | select(.id=="'"$tid"'") | .trace.verifies[]')
    printf '</td><td class="rtm-ac">'
    first=1
    while IFS= read -r x; do [[ -n "$x" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="rtm-edge"><a class="rtm-code" href="%s#%s">%s</a> <span class="rtm-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$x")" "$(esc "$x")" "$(esc "$x")" "$(esc "${REF_LABEL[$x]}")"; done < <(q '.test_cases[] | select(.id=="'"$tid"'") | .trace.confirms[]')
    printf '</td></tr>\n'
  done
  printf '</tbody></table>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# footer は core_emit_footer に test-cases-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>test-cases-pack</span><span>folio engine 段階2c (instance#6)</span><span>三段 trace + cross-doc 前方照会</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "テストの考え方と範囲"            "何を試し、 何を試さないか"                    "$ICO_FILTER";    emit_scope;  band_end
  band brand  "テストケース / 1 件ずつの確かめ方"  "前提・操作・期待結果と、 検証する要件のつながり"  "$ICO_CHECKLIST"; emit_cards;  band_end
  band ok     "要件 → 受入 → テスト の対応"        "どのテストがどの要件・受入基準を確かめるか"      "$ICO_LINK";      emit_rtm;    band_end
  band violet "用語集 / この文書で使う専門語"        "本文に出てくる専門語のやさしい説明"            "$ICO_BOOK";      emit_glossary; band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
# ★SRS 由来 ラベル map (fabrication-free・FR=requirements[].label / AC=acceptance[].criterion を verbatim)。
#   validate() が SRS 実在 + 全 trace ref が SRS に実在を保証済ゆえ、 参照される全 ref の label/criterion は欠落なし。
#   SRS contract は read-only (無編集)・既存 SRS-pack byte-identity 維持。 verify-testcases.sh が同一導出で fidelity 突合。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
SRS_HTML="$(q '.cross_doc.srs_html')"   # ★cross-doc deep-link path 先 (folio-c5r.9・root 平置き = prefix なし)
declare -A REF_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && REF_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
while IFS=$'\t' read -r _id _crit; do [[ -n "$_id" ]] && REF_LABEL["$_id"]="$_crit"; done < <(yq -r '.acceptance[] | [.id, .criterion] | @tsv' "$SRS_ABS")
core_finalize "assemble-testcases"
