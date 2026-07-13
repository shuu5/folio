#!/usr/bin/env bash
# folio engine post-B6 (folio-wdv0 / c5r capability-census) — risk-register-pack 決定的 assembler
#
# 入力 risk-register contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# testcases generator と *同型* の機構を risk-register-pack schema へ適用する:
#   - 内容・構造 (cover / severity matrix / risks[] (statement/likelihood/impact/mitigation/owner/status) /
#     trace / glossary) は contract から決定的組立。 元データに無いリスク・対策・trace edge を生成できない。
#   - ★severity (深刻度) は contract に *持たせない* = likelihood(L/M/H)×impact(L/M/H) から決定的導出する
#     (LNUM: L=1・M=2・H=3 の積 p → p<=2:低 / p<=4:中 / p>=6:高)。 元データに severity フィールドが無いため
#     「深刻度の捏造」は原理的に不可能。 severity matrix セル・card バッジ・tally・RTM は全て同一導出値を使う。
#   - ★card は severity の高い順 (積 desc・id asc) に決定的に並べ替える (安定 sort)。 verify-risk.sh が同一 sort を再導出。
#   - ★cross-doc 前方照会 edge: risks[].trace.refs[] (FR/NFR・role=claim) が参照先 SRS contract の
#     要件 / 非機能要件 ID に実在することを validate() が *生成前に* fail-closed で確かめる (集合外参照は拒否)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 likelihood/impact/status は拒否。
#   - prose スロット (章リード / plain 要約 / 1 文サマリ) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# inject-prose.sh は testcases/SRS/ADR と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-risk.sh <risk-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-risk.sh <risk-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-risk: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-risk: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-risk: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# likelihood / impact / status allowlist (risk-register-pack 固有)。
declare -A LNUM=( [L]=1 [M]=2 [H]=3 )         # 決定的 severity 導出の数値
declare -A LVL_OK=( [L]=1 [M]=1 [H]=1 )
declare -A LVL_LABEL=( [L]=低 [M]=中 [H]=高 ) # likelihood/impact レベルの可視ラベル
declare -A STATUS_OK=( [open]=1 [mitigating]=1 [accepted]=1 [closed]=1 )
declare -A STATUS_LABEL=( [open]=未対応 [mitigating]=対応中 [accepted]=受容 [closed]=対応済 )

# ★severity 決定的導出 (捏造原理不可の核)。 p = LNUM[likelihood]×LNUM[impact]。
#   p<=2:低(low) / p<=4:中(medium) / p>=6:高(high)。 verify-risk.sh が同一導出で card/matrix/tally/RTM を突合する。
sev_prod()  { printf '%s' "$(( LNUM[$1] * LNUM[$2] ))"; }   # $1=likelihood $2=impact
sev_label() { local p="$1"; if ((p<=2)); then printf '低'; elif ((p<=4)); then printf '中'; else printf '高'; fi; }
sev_class() { local p="$1"; if ((p<=2)); then printf 'low'; elif ((p<=4)); then printf 'medium'; else printf 'high'; fi; }

# ---- icon SVG (risk-register-pack 固有。 共用 icon=ICO_FLOW/SHIELD/BOOK/CHECK_BIG/USER + ico() は lib/common.sh) ----
ICO_ALERT='<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>'
ICO_GRID='<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p d lk im st
  core_validate_strings "assemble-risk" || errs=1
  # ★contract に severity フィールドを持たせない (決定的導出の不変条件・持つと捏造経路になる)。
  d="$(q '[.risks[] | select(has("severity"))] | length')"
  [[ "$d" == "0" ]] || { echo "assemble-risk: risks[] に severity フィールドが存在 ($d 件・severity は likelihood×impact から決定的導出ゆえ contract 禁止)" >&2; errs=1; }
  # risks id 一意性
  d="$(q '.risks[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-risk: risks id 重複: $d" >&2; errs=1; }
  # likelihood / impact allowlist
  for p in $(q '.risks[].likelihood'); do [[ -v LVL_OK[$p] ]] || { echo "assemble-risk: 未知の likelihood: $p (L|M|H)" >&2; errs=1; }; done
  for p in $(q '.risks[].impact'); do [[ -v LVL_OK[$p] ]] || { echo "assemble-risk: 未知の impact: $p (L|M|H)" >&2; errs=1; }; done
  # status allowlist
  for p in $(q '.risks[].status'); do [[ -v STATUS_OK[$p] ]] || { echo "assemble-risk: 未知の status: $p (open|mitigating|accepted|closed)" >&2; errs=1; }; done
  # 各 risk は trace.refs を 1 件以上持つ (cross-doc 照会が片側欠けない)
  local n_incomplete
  n_incomplete="$(q '[.risks[] | select((.trace.refs | length) == 0) | .id] | length')"
  [[ "$n_incomplete" == "0" ]] || { echo "assemble-risk: trace.refs 空の risk が $n_incomplete 件 (cross-doc 照会不成立)" >&2; errs=1; }
  # ★空/null の trace ref は dangling 判定 (comm -23) が空行を空 missing に畳んで素通すため明示拒否する。
  local n_edge n_ref
  n_edge="$(q '[.risks[].trace.refs[]] | length')"
  n_ref="$(q '[ (.risks[].trace.refs[]) | select((. // "") != "") ] | length')"
  [[ "$n_edge" == "$n_ref" ]] || { echo "assemble-risk: ★cross-doc 照会の空 ref (有効 $n_ref/$n_edge 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
  # ★cross-doc 前方照会の終端解決: 参照先 SRS contract 実在 + trace の FR/NFR が SRS の要件/非機能要件 ID に実在
  local srs_rel srs_abs srs_docid expect_docid missing
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-risk: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-risk: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    missing="$(comm -23 <(q '.risks[].trace.refs[]' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id)' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-risk: ★cross-doc 照会の dangling: trace の FR/NFR が SRS に実在しない: $missing" >&2; errs=1; }
  fi
  core_validate_glossary_substring "assemble-risk" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-risk: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- risk-register-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_risk_css() {
  cat <<'CSS'
/* ===== risk-register-pack 固有部品 (folio-wdv0)。 srs.css の token を流用 ===== */
table[data-component="severity-matrix"]{border-collapse:collapse;margin:10px 0;font-size:13px}
[data-component="severity-matrix"] th,[data-component="severity-matrix"] td{border:1px solid var(--line);padding:9px 12px;text-align:center;vertical-align:middle}
[data-component="severity-matrix"] thead th,[data-component="severity-matrix"] .sm-row{background:var(--paper-3);font-size:11.5px;color:var(--ink-soft);font-weight:700}
[data-component="severity-matrix"] .sm-corner{text-align:right;color:var(--ink-faint);font-weight:600}
[data-component="severity-matrix"] .sm-cell{font-weight:800}
[data-component="severity-matrix"] .sm-cell .sm-n{display:block;font-size:17px;line-height:1.2}
[data-component="severity-matrix"] .sm-cell .sm-lv{display:block;font-size:10.5px;font-weight:700}
[data-component="severity-matrix"] .sm-cell.high{color:var(--bad);background:var(--bad-tint)}
[data-component="severity-matrix"] .sm-cell.medium{color:var(--warn);background:var(--warn-tint)}
[data-component="severity-matrix"] .sm-cell.low{color:var(--ok);background:var(--ok-tint)}
[data-component="severity-tally"]{display:flex;gap:10px;flex-wrap:wrap;margin:10px 0}
.sm-tally{font-size:12.5px;font-weight:700;border-radius:8px;padding:5px 12px;border:1px solid}
.sm-tally b{font-size:15px}
.sm-tally.high{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.sm-tally.medium{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.sm-tally.low{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.rk-grid{display:flex;flex-direction:column;gap:14px;margin:10px 0}
[data-component="risk-card"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.rk-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:5px}
.rk-head .rk-id{font-weight:800;font-size:12px;color:var(--ink-soft);background:var(--paper-3);border:1px solid var(--line);border-radius:6px;padding:2px 8px}
.rk-sev{font-size:11px;font-weight:800;border-radius:999px;padding:2px 11px;border:1px solid}
.rk-sev.high{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.rk-sev.medium{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.rk-sev.low{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.rk-status{font-size:10.5px;font-weight:700;border-radius:5px;padding:1px 7px;border:1px solid var(--line);color:var(--ink-soft);background:var(--paper-2)}
.rk-status.mitigating{color:var(--info);border-color:var(--info-line);background:var(--info-tint)}
.rk-status.accepted{color:var(--warn);border-color:var(--warn-line);background:var(--warn-tint)}
.rk-status.closed{color:var(--ok);border-color:var(--ok-line);background:var(--ok-tint)}
.rk-head .rk-title{flex:1 1 100%;font-weight:800;font-size:15px;margin:4px 0 0;line-height:1.5}
[data-component="risk-card"] .rk-plain{display:block;margin:0 0 9px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px;line-height:1.7}
.rk-statement{font-size:13.5px;line-height:1.75;color:var(--ink);margin:4px 0 10px}
.rk-levels{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 10px}
.rk-level{font-size:11.5px;color:var(--ink-soft);background:var(--paper-2);border:1px solid var(--line);border-radius:7px;padding:3px 10px}
.rk-level b{font-weight:800;color:var(--ink)}
.rk-mit{display:flex;gap:10px;align-items:flex-start;font-size:13px;line-height:1.7;background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:9px;padding:8px 12px;margin:0 0 8px}
.rk-mit .rk-mit-k{flex:0 0 auto;font-weight:700;font-size:11.5px;color:var(--ok);padding-top:1px}
.rk-mit .rk-mit-v{flex:1 1 auto;color:var(--ink-soft)}
.rk-owner{font-size:12px;color:var(--ink-faint);margin:0 0 10px}
.rk-owner .rk-owner-k{font-weight:700;margin-right:6px}
.rk-owner .rk-owner-v{color:var(--ink-soft);font-weight:700}
.rk-trace{background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:9px 12px}
.rk-trace .rk-trace-h{font-size:11.5px;font-weight:700;color:var(--ink-faint);margin:0 0 6px}
.rk-trace-row{display:flex;gap:8px;align-items:baseline;padding:3px 0;flex-wrap:wrap}
.rk-trace-edge{display:inline-flex;align-items:baseline;gap:4px;margin-right:4px}
.rk-ref{font-weight:800;font-size:12px;border-radius:6px;padding:1px 9px;border:1px solid;flex:0 0 auto;color:var(--brand);background:var(--brand-tint);border-color:var(--brand)}
.rk-ref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
.rk-trace-tgt{font-size:11px;color:var(--ink-faint);margin:7px 0 0}
table[data-component="risk-rtm"]{width:100%;border-collapse:collapse;margin:8px 0;font-size:13px}
[data-component="risk-rtm"] th,[data-component="risk-rtm"] td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
[data-component="risk-rtm"] thead th{background:var(--paper-3);font-size:11.5px;color:var(--ink-soft);letter-spacing:.02em}
[data-component="risk-rtm"] .rrtm-id{font-weight:800;color:var(--ink-soft);white-space:nowrap}
[data-component="risk-rtm"] .rrtm-sev{white-space:nowrap}
[data-component="risk-rtm"] .rrtm-status{white-space:nowrap;font-size:12px;color:var(--ink-faint)}
[data-component="risk-rtm"] .rrtm-refs{font-size:12px;line-height:1.7}
[data-component="risk-rtm"] .rrtm-edge{display:inline}
[data-component="risk-rtm"] .rrtm-code{font-size:11px;font-weight:800;color:var(--brand)}
[data-component="risk-rtm"] .rrtm-label{font-weight:400;color:var(--ink-soft)}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="risk-register">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio risk-register-pack assembler (folio-wdv0) — deterministic structure + severity derivation, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_risk_css
  printf '\n</style>\n'
  core_emit_graph_head
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このリスク登録簿が約束すること (1 文サマリ)"
  local n_rk first last ref_label_join ref
  n_rk="$(q '.risks | length')"
  first="$(q '.risks[0].id')"; last="$(q '.risks[-1].id')"
  # ★cover は FR/NFR コード列挙でなく平易機能名要約 (非エンジニア可読)。 unique ref を SRS label へ
  #   fabrication-free に写像し first-occurrence 順で join (REF_LABEL = SRS 由来・verify が同一導出で突合)。
  ref_label_join=""
  while IFS= read -r ref; do [[ -n "$ref" ]] && ref_label_join+="${ref_label_join:+・}${REF_LABEL[$ref]}"; done < <(q '[.risks[].trace.refs[]] | unique | .[]')
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">件数</span><span class="v">%s</span></span><span class="m"><span class="k">検証対象</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "risk-register (リスク登録簿)" "$(esc "$n_rk")件 ($(esc "$first")–$(esc "$last"))" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (見張る対象 SRS と要件の平易機能名要約)
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 見張る対象: <b>%s</b> の要件 <b>%s</b></div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$ref_label_join")"
  core_emit_approval_block
  core_emit_cover_tail
}

# 深刻度マトリクス (severity-matrix)。 起こりやすさ (行 H/M/L) × 影響 (列 L/M/H) の 9 セル。
#   各セル = そのマスに属する risk 件数 + 決定的 severity ラベル (捏造原理不可)。 tally = band 別件数。
emit_matrix() {
  local lk im p cnt
  printf '<table data-component="severity-matrix"><thead><tr><th class="sm-corner">起こりやすさ \\ 影響</th><th class="sm-col">影響 低</th><th class="sm-col">影響 中</th><th class="sm-col">影響 高</th></tr></thead><tbody>\n'
  for lk in H M L; do
    printf '<tr><th class="sm-row">起こりやすさ %s</th>' "${LVL_LABEL[$lk]}"
    for im in L M H; do
      p="$(sev_prod "$lk" "$im")"
      cnt="$(q '[.risks[] | select(.likelihood=="'"$lk"'" and .impact=="'"$im"'")] | length')"
      printf '<td class="sm-cell %s" data-cell="%s"><b class="sm-n">%s</b><span class="sm-lv">%s</span></td>' \
        "$(sev_class "$p")" "${lk}${im}" "$(esc "$cnt")" "$(sev_label "$p")"
    done
    printf '</tr>\n'
  done
  printf '</tbody></table>\n'
  # band 別 tally (深刻度 高/中/低 の件数)。 各 risk の積からband を決定的に導出して集計。
  local -A BAND=( [high]=0 [medium]=0 [low]=0 )
  local rk_lk rk_im
  while IFS=$'\t' read -r rk_lk rk_im; do
    [[ -n "$rk_lk" ]] || continue
    p="$(sev_prod "$rk_lk" "$rk_im")"; BAND[$(sev_class "$p")]=$(( BAND[$(sev_class "$p")] + 1 ))
  done < <(q '.risks[] | [.likelihood, .impact] | @tsv')
  printf '<div data-component="severity-tally">'
  printf '<span class="sm-tally high" data-band="high">深刻度 高: <b>%s</b> 件</span>' "${BAND[high]}"
  printf '<span class="sm-tally medium" data-band="medium">深刻度 中: <b>%s</b> 件</span>' "${BAND[medium]}"
  printf '<span class="sm-tally low" data-band="low">深刻度 低: <b>%s</b> 件</span>' "${BAND[low]}"
  printf '</div>\n'
}

# ★severity 順に並べ替えた risk id 列 (積 desc・id asc の安定 sort)。 assemble/verify 共通導出。
sorted_rids() {
  q '.risks[] | [.id, .likelihood, .impact] | @tsv' | while IFS=$'\t' read -r id lk im; do
    [[ -n "$id" ]] || continue
    printf '%s\t%s\n' "$(sev_prod "$lk" "$im")" "$id"
  done | sort -t$'\t' -k1,1nr -k2,2 | cut -f2
}

emit_cards() {
  printf '<div class="rk-grid">\n'
  local -a RIDS; mapfile -t RIDS < <(sorted_rids)
  local rid lk im p sevc sevl status statuslabel
  for rid in "${RIDS[@]}"; do
    lk="$(q '.risks[] | select(.id=="'"$rid"'") | .likelihood')"
    im="$(q '.risks[] | select(.id=="'"$rid"'") | .impact')"
    p="$(sev_prod "$lk" "$im")"; sevc="$(sev_class "$p")"; sevl="$(sev_label "$p")"
    status="$(q '.risks[] | select(.id=="'"$rid"'") | .status')"
    statuslabel="${STATUS_LABEL[$status]:-$status}"
    printf '<div data-component="risk-card" id="rsk-%s">\n' "$(esc "$rid")"
    printf '<div class="rk-head"><span class="rk-id">%s</span><span class="rk-sev %s" data-sev-cell="%s">%s</span><span class="rk-status %s">%s</span><h3 class="rk-title">%s</h3></div>\n' \
      "$(esc "$rid")" "$(esc "$sevc")" "$(esc "${lk}${im}")" "$(esc "$sevl")" "$(esc "$status")" "$(esc "$statuslabel")" "$(esc "$(q '.risks[] | select(.id=="'"$rid"'") | .title')")"
    printf '<p class="rk-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$rid")"
    printf '<p class="rk-statement">%s</p>\n' "$(mark_terms "$(q '.risks[] | select(.id=="'"$rid"'") | .statement')")"
    printf '<div class="rk-levels"><span class="rk-level rk-lk">起こりやすさ <b>%s</b></span><span class="rk-level rk-im">影響の大きさ <b>%s</b></span></div>\n' \
      "$(esc "${LVL_LABEL[$lk]}")" "$(esc "${LVL_LABEL[$im]}")"
    printf '<div class="rk-mit"><span class="rk-mit-k">対策</span><span class="rk-mit-v">%s</span></div>\n' "$(mark_terms "$(q '.risks[] | select(.id=="'"$rid"'") | .mitigation')")"
    printf '<div class="rk-owner"><span class="rk-owner-k">担当</span><span class="rk-owner-v">%s</span></div>\n' "$(esc "$(q '.risks[] | select(.id=="'"$rid"'") | .owner')")"
    # ★cross-doc 前方照会 edge = 脅かす要件 (FR/NFR・role=claim)。
    printf '<div class="rk-trace"><p class="rk-trace-h">脅かす要件 (cross-doc 照会 \xe2\x86\x92 %s)</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")"
    printf '<div class="rk-trace-row">'
    while IFS= read -r ref; do [[ -n "$ref" ]] && printf '<span class="rk-trace-edge"><a class="rk-ref" href="%s#%s" data-trace-ref="%s" data-trace-role="claim">%s</a><span class="rk-ref-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$ref")" "$(esc "$ref")" "$(esc "$ref")" "$(esc "$ref")" "$(esc "${REF_LABEL[$ref]}")"; done < <(q '.risks[] | select(.id=="'"$rid"'") | .trace.refs[]')
    printf '</div>\n'
    printf '<p class="rk-trace-tgt">照会先: %s \xe2\x80\x94 %s</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$SRS_REF_TITLE")"
    printf '</div>\n</div>\n'
  done
  printf '</div>\n'
}

# RTM = リスク → 深刻度 → 状態 → 脅かす要件 の一覧 (severity 順)。 FR/NFR は code バッジ + SRS 由来 平易ラベル併記。
emit_rtm() {
  printf '<table data-component="risk-rtm"><thead><tr><th>リスク</th><th>深刻度</th><th>状態</th><th>脅かす要件</th></tr></thead><tbody>\n'
  local -a RIDS; mapfile -t RIDS < <(sorted_rids)
  local rid lk im p sevc sevl status statuslabel first x
  for rid in "${RIDS[@]}"; do
    lk="$(q '.risks[] | select(.id=="'"$rid"'") | .likelihood')"
    im="$(q '.risks[] | select(.id=="'"$rid"'") | .impact')"
    p="$(sev_prod "$lk" "$im")"; sevc="$(sev_class "$p")"; sevl="$(sev_label "$p")"
    status="$(q '.risks[] | select(.id=="'"$rid"'") | .status')"
    statuslabel="${STATUS_LABEL[$status]:-$status}"
    printf '<tr data-component="rtm-row"><td class="rrtm-id">%s</td><td class="rrtm-sev"><span class="rk-sev %s">%s</span></td><td class="rrtm-status">%s</td>' \
      "$(esc "$rid")" "$(esc "$sevc")" "$(esc "$sevl")" "$(esc "$statuslabel")"
    printf '<td class="rrtm-refs">'
    first=1
    while IFS= read -r x; do [[ -n "$x" ]] || continue; [[ "$first" -eq 1 ]] || printf '\xe3\x80\x81'; first=0; printf '<span class="rrtm-edge"><a class="rrtm-code" href="%s#%s">%s</a> <span class="rrtm-label" data-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$x")" "$(esc "$x")" "$(esc "$x")" "$(esc "${REF_LABEL[$x]}")"; done < <(q '.risks[] | select(.id=="'"$rid"'") | .trace.refs[]')
    printf '</td></tr>\n'
  done
  printf '</tbody></table>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# footer は core_emit_footer に risk-register-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>risk-register-pack</span><span>folio engine post-B6 (capability-census)</span><span>severity 決定的導出 + cross-doc 前方照会</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band bad    "深刻度の見取り図"                  "起こりやすさ × 影響で、 どこが深刻かを一目で"      "$ICO_GRID";  emit_matrix; band_end
  band brand  "リスク / 1 件ずつの中身と備え"       "何が起こりうるか・どれくらい深刻か・どう備えるか"  "$ICO_ALERT"; emit_cards;  band_end
  band ok     "リスク → 脅かす要件 の対応"          "どのリスクがどの要件・非機能要件を脅かすか"        "$ICO_LINK";  emit_rtm;    band_end
  band violet "用語集 / この文書で使う専門語"         "本文に出てくる専門語のやさしい説明"              "$ICO_BOOK";  emit_glossary; band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
# ★SRS 由来 ラベル map (fabrication-free・FR=requirements[].label / NFR=nfr[].label を verbatim)。
#   validate() が SRS 実在 + 全 trace ref が SRS に実在を保証済ゆえ、 参照される全 ref の label は欠落なし。
#   SRS contract は read-only (無編集)・既存 SRS-pack byte-identity 維持。 verify-risk.sh が同一導出で fidelity 突合。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
SRS_HTML="$(q '.cross_doc.srs_html')"   # ★cross-doc deep-link path 先 (root 平置き = prefix なし)
# ★cross-doc 照会ラベル live-mirror: 参照先 SRS の実 .meta.title を「SRS: <title>」へ統一 (手書き title 廃止=drift 防止)。
SRS_REF_TITLE="SRS: $(yq -r '.meta.title' "$SRS_ABS")"
declare -A REF_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && REF_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && REF_LABEL["$_id"]="$_lbl"; done < <(yq -r '.nfr[] | [.id, .label] | @tsv' "$SRS_ABS")
core_finalize "assemble-risk"
