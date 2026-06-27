#!/usr/bin/env bash
# folio engine 段階3 (folio-5uu) — architecture-description-pack 決定的 assembler (instance#1 / 記述型 frontier)
#
# 入力 architecture-description contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# 要件索引型 (SRS / ADR / research / testcases) を脱した初の *記述型 (descriptive)* doc-type。 schema =
# arc42 (固定 8 章: 課題/戦略/部品/流れ/決定/品質/リスク/用語) + C4 (3 図) ハイブリッド。
#   - 構造・内容 (8 章 / actor / 戦略 / 部品 / 流れ / 決定 / 品質 / リスク / 用語 / 図) は contract から決定的組立。
#     元データに無い部品・決定・図・cross-ref edge は生成できない。
#   - ★cross-doc 前方照会 edge (案A = 別文書 link・再掲ゼロ): decisions[].refs.srs[] (claim) → SRS 要件 /
#     decisions[].refs.adr[] (rationale) → ADR doc_id / decisions[].refs.principle[] (terminal) → 原則終端。
#     validate() が *生成前に* 参照先 contract 実在 + 当該 ID 実在を fail-closed で確かめる (集合外参照は拒否)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 kind/severity は拒否。
#   - prose スロット (cover-summary / 章リード / 決定の plain-AD / rationale-AD) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#   - mermaid 図は raw DSL を esc して <pre class="mermaid"> へ join 出力 (raw DSL 露出 = gate I blocker・folio-97z 教訓)。
#
# inject-prose.sh は SRS/ADR/testcases と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-arch.sh <architecture-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-arch.sh <architecture-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-arch: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-arch: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-arch: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# kind / severity allowlist (arch-pack 固有・visible badge へ写像)。
declare -A COMP_KIND_OK=( [core]=1 [external]=1 )
declare -A COMP_KIND_LABEL=( [core]=中核 [external]=外部連携 )
declare -A ACTOR_KIND_OK=( [internal]=1 [external]=1 )
declare -A ACTOR_KIND_LABEL=( [internal]=内部 [external]=外部 )
declare -A SEV_OK=( [高]=1 [中]=1 )
declare -A SEV_CLASS=( [高]=high [中]=mid )
declare -A DIAG_KIND_OK=( [context]=1 [container]=1 [sequence]=1 )
declare -A DIAG_COMPONENT=( [context]=context-diagram [container]=container-diagram [sequence]=runtime-flow-diagram )
declare -A DIAG_TAG=( [context]="C4 — System Context" [container]="C4 — Container" [sequence]="フロー (sequence)" )

# ---- icon SVG (arch-pack 固有。 共用 ICO_BOOK/ICO_USER は lib/common.sh) ----
ICO_MAP='<path d="M9 20l-5.5 2V5l5.5-2 6 2 5.5-2v17l-5.5 2-6-2z"/><path d="M9 3v17M15 5v17"/>'
ICO_COMPASS='<circle cx="12" cy="12" r="9"/><path d="M16 8l-2.5 6.5L7 17l2.5-6.5z"/>'
ICO_BLOCKS='<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'
ICO_ARROW='<path d="M5 12h14M13 6l6 6-6 6"/>'
ICO_GAVEL='<path d="M14 13l-7 7-3-3 7-7"/><path d="M14.5 6.5l3 3M17 4l3 3-3 3-3-3z"/><path d="M3 21h7"/>'
ICO_GAUGE='<path d="M3 13a9 9 0 0 1 18 0"/><path d="M12 13l4-3"/><circle cx="12" cy="13" r="1.6"/>'
ICO_ALERT='<path d="M10.3 3.3L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.3a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p
  core_validate_strings "assemble-arch" || errs=1
  # doc_type guard (記述型 pack の identity・誤 contract 混入を拒否)
  [[ "$(q '.doc_type')" == "architecture-description" ]] || { echo "assemble-arch: doc_type が architecture-description でない: $(q '.doc_type')" >&2; errs=1; }
  # id 一意性 (decisions / components / quality / risks / strategy / actors / diagrams)
  local axis
  for axis in '.decisions[].id' '.components[].id' '.quality[].id' '.risks[].id' '.strategy[].id' '.context.actors[].id' '.diagrams[].id'; do
    d="$(q "$axis" | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-arch: id 重複 ($axis): $d" >&2; errs=1; }
  done
  # component kind allowlist
  for p in $(q '.components[].kind'); do [[ -v COMP_KIND_OK[$p] ]] || { echo "assemble-arch: 未知の component kind: $p (core|external)" >&2; errs=1; }; done
  # actor kind allowlist
  for p in $(q '.context.actors[].kind'); do [[ -v ACTOR_KIND_OK[$p] ]] || { echo "assemble-arch: 未知の actor kind: $p (internal|external)" >&2; errs=1; }; done
  # risk severity allowlist
  for p in $(q '.risks[].severity'); do [[ -v SEV_OK[$p] ]] || { echo "assemble-arch: 未知の risk severity: $p (高|中)" >&2; errs=1; }; done
  # diagram kind allowlist
  for p in $(q '.diagrams[].kind'); do [[ -v DIAG_KIND_OK[$p] ]] || { echo "assemble-arch: 未知の diagram kind: $p (context|container|sequence)" >&2; errs=1; }; done

  # ★cross-doc 前方照会の終端解決 (SRS): 参照先 SRS contract 実在 + doc_id 一致 + 各 srs ref が SRS 要件に実在 + 空 ref 禁止。
  local srs_rel srs_abs srs_docid expect_docid missing n_srs n_srs_ne
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-arch: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-arch: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    n_srs="$(q '[.decisions[].refs.srs[]] | length')"; n_srs_ne="$(q '[ .decisions[].refs.srs[] | select((. // "") != "") ] | length')"
    [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-arch: ★SRS 照会の空 ref (有効 $n_srs_ne/$n_srs 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
    missing="$(comm -23 <(q '.decisions[].refs.srs[]' | sort -u) <(yq -r '.requirements[].id' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-arch: ★SRS 照会の dangling: refs.srs が SRS 要件に実在しない: $missing" >&2; errs=1; }
    # quality srs_ref は SRS の referenceable id (要件/NFR/受入/ゴール) に実在 (照会のみ・充足は SRS が SSoT)
    local qmissing
    qmissing="$(comm -23 <(q '.quality[].srs_ref' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id, .acceptance[].id, .goals[].id)' "$srs_abs" | sort -u))"
    [[ -z "$qmissing" ]] || { echo "assemble-arch: ★quality.srs_ref の dangling: SRS に実在しない: $qmissing" >&2; errs=1; }
  fi
  # ★cross-doc 前方照会の終端解決 (ADR): 参照先 ADR contract 実在 + doc_id 一致 + 各 adr ref が ADR doc_id に実在 (doc 粒度照会)。
  local adr_rel adr_abs adr_docid expect_adr amissing n_adr n_adr_ne
  adr_rel="$(q '.cross_doc.adr_contract')"; adr_abs="${CONTRACT_DIR}/${adr_rel}"
  if [[ ! -f "$adr_abs" ]]; then
    echo "assemble-arch: cross_doc.adr_contract が見つからない: $adr_rel (照会先 ADR 不在)" >&2; errs=1
  else
    adr_docid="$(yq -r '.meta.doc_id' "$adr_abs")"; expect_adr="$(q '.cross_doc.adr_doc_id')"
    [[ "$adr_docid" == "$expect_adr" ]] || { echo "assemble-arch: cross_doc.adr_doc_id ($expect_adr) が ADR contract の doc_id ($adr_docid) と不一致" >&2; errs=1; }
    n_adr="$(q '[.decisions[].refs.adr[]] | length')"; n_adr_ne="$(q '[ .decisions[].refs.adr[] | select((. // "") != "") ] | length')"
    [[ "$n_adr" == "$n_adr_ne" ]] || { echo "assemble-arch: ★ADR 照会の空 ref (有効 $n_adr_ne/$n_adr 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
    amissing="$(comm -23 <(q '.decisions[].refs.adr[]' | sort -u) <(yq -r '.meta.doc_id' "$adr_abs" | sort -u))"
    [[ -z "$amissing" ]] || { echo "assemble-arch: ★ADR 照会の dangling: refs.adr が ADR doc_id でない: $amissing" >&2; errs=1; }
  fi
  # principle 終端: refs.principle[] ⊆ {principle.id} (空 ref 禁止・存在しない原則照会を拒否)
  local pmissing n_prin n_prin_ne
  n_prin="$(q '[.decisions[].refs.principle[]] | length')"; n_prin_ne="$(q '[ .decisions[].refs.principle[] | select((. // "") != "") ] | length')"
  [[ "$n_prin" == "$n_prin_ne" ]] || { echo "assemble-arch: ★principle 照会の空 ref (有効 $n_prin_ne/$n_prin 件)" >&2; errs=1; }
  pmissing="$(comm -23 <(q '.decisions[].refs.principle[]' | sort -u) <(q '.principle.id' | sort -u))"
  [[ -z "$pmissing" ]] || { echo "assemble-arch: ★principle 照会の dangling: refs.principle が principle.id でない: $pmissing" >&2; errs=1; }

  core_validate_glossary_substring "assemble-arch" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-arch: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- arch-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_arch_css() {
  cat <<'CSS'
/* ===== architecture-description-pack 固有部品 (folio-5uu / instance#1)。 srs.css の token を流用 ===== */
.arch-grid{display:flex;flex-direction:column;gap:14px;margin:10px 0}
/* §1 problem callout + actors */
[data-component="context-problem"]{border:1px solid var(--line);border-left:5px solid var(--brand);border-radius:12px;padding:14px 18px;background:var(--brand-tint);font-size:14px;line-height:1.75;color:var(--ink-soft);margin:0 0 16px}
[data-component="actor-stakeholder-table"]{display:flex;flex-wrap:wrap;gap:12px;margin:6px 0 16px}
.arch-actor{display:flex;flex-direction:column;gap:2px;background:var(--paper);border:1px solid var(--line);border-radius:12px;padding:11px 15px;box-shadow:var(--shadow);min-width:0}
.arch-actor .nm{font-size:14px;font-weight:800;line-height:1.25;display:flex;align-items:center;gap:7px}
.arch-actor .ar-role{font-size:11.5px;color:var(--ink-faint);font-weight:600}
.akind{font-size:9.5px;font-weight:800;letter-spacing:.08em;padding:1px 6px;border-radius:5px;border:1px solid}
.akind.internal{background:var(--ok-tint);color:var(--ok);border-color:var(--ok-line)}
.akind.external{background:var(--warn-tint);color:var(--warn);border-color:var(--warn-line)}
/* §2 strategy cards */
[data-component="strategy-card-grid"]{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin:8px 0}
@media(max-width:640px){[data-component="strategy-card-grid"]{grid-template-columns:1fr}}
[data-component="strategy-card"]{border:1px solid var(--line);border-left:5px solid var(--ok);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.st-head{display:flex;align-items:baseline;gap:9px;margin-bottom:5px}
.st-id{font-weight:800;font-size:12px;color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:6px;padding:2px 8px}
.st-name{font-weight:800;font-size:15.5px}
.st-plain{font-size:13.5px;color:var(--ink-soft);background:var(--ok-tint);border-radius:7px;padding:6px 10px;margin:4px 0 8px;line-height:1.7}
.st-why{font-size:12.5px;color:var(--ink-faint);line-height:1.7}
.st-why::before{content:"↳ なぜ ";font-weight:700;color:var(--ink-faint)}
/* §3 components table */
table[data-component="component-table"]{width:100%;border-collapse:separate;border-spacing:0;font-size:13.5px}
[data-component="component-table"] thead th{background:var(--info);color:#fff;text-align:left;font-size:11.5px;font-weight:800;letter-spacing:.06em;padding:11px 14px}
[data-component="component-table"] thead th:first-child{border-top-left-radius:12px} [data-component="component-table"] thead th:last-child{border-top-right-radius:12px}
[data-component="component-table"] tbody td{padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:top;line-height:1.6}
[data-component="component-table"] tbody tr:nth-child(even) td{background:var(--paper-2)}
.cn{font-weight:800;font-size:14px;color:var(--info)}
.ckind{display:inline-block;margin-top:4px;font-size:10px;font-weight:800;letter-spacing:.06em;padding:1px 7px;border-radius:5px;border:1px solid}
.ckind.core{background:var(--info-tint);color:var(--info);border-color:var(--info-line)}
.ckind.external{background:var(--warn-tint);color:var(--warn);border-color:var(--warn-line)}
.cwhy{display:block;margin-top:5px;font-size:11.5px;color:var(--ink-faint)}
.cwhy::before{content:"↳ なぜ分ける ";font-weight:700}
/* §4 runtime flow */
[data-component="runtime-flow"]{border:1px solid var(--line);border-radius:12px;padding:8px 6px;background:var(--paper);box-shadow:var(--shadow);margin:8px 0}
.rt-name{font-size:14px;font-weight:800;color:var(--violet);padding:8px 12px 2px}
.rt-step{display:flex;gap:11px;align-items:flex-start;font-size:13px;line-height:1.65;padding:5px 14px}
.rt-step .rt-n{flex:0 0 22px;height:22px;border-radius:50%;background:var(--violet);color:#fff;font-size:11px;font-weight:800;display:grid;place-items:center;margin-top:1px}
.rt-step .rt-v{flex:1 1 auto;color:var(--ink-soft)}
.rt-summary{font-size:13px;color:var(--ink-soft);line-height:1.7;padding:2px 14px 6px;margin:0}
/* C4 / sequence diagram (mermaid render target) */
figure.diagram{margin:14px 0;border:1px solid var(--line);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);overflow:hidden}
figure.diagram .mermaid{margin:0;padding:14px 10px;overflow-x:auto;text-align:center}
figure.diagram .mermaid:not([data-processed]){font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;line-height:1.55;white-space:pre;text-align:left;color:var(--ink-soft);background:var(--paper-2);border-radius:10px}
figure.diagram figcaption{padding:11px 15px 13px;font-size:12px;color:var(--ink-faint);border-top:1px dashed var(--line);background:var(--paper);line-height:1.6}
.diag-tag{display:inline-block;font-size:10px;font-weight:800;letter-spacing:.06em;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:5px;padding:1px 7px;margin-right:7px}
/* §5 decision cards */
[data-component="arch-decision-card"]{border:1px solid var(--line);border-radius:12px;padding:15px 17px;background:var(--paper);box-shadow:var(--shadow)}
.ad-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:6px}
.ad-id{font-weight:800;font-size:12px;color:#fff;background:var(--brand);border-radius:6px;padding:2px 9px}
.ad-title{flex:1 1 100%;font-weight:800;font-size:16px;margin:4px 0 0;line-height:1.5}
.ad-plain{display:block;margin:0 0 8px;font-size:13.5px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:7px 11px;line-height:1.7}
.ad-summary{font-size:13.5px;color:var(--ink-soft);line-height:1.75;margin:0 0 8px}
.ad-rationale{font-size:12.5px;color:var(--ink-faint);line-height:1.75;margin:0 0 10px;padding-left:14px;border-left:3px solid var(--line)}
.ad-rationale::before{content:"なぜこの案か ";font-weight:700;color:var(--brand)}
.ad-refs{display:flex;flex-direction:column;gap:6px;background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:10px 13px}
.ad-ref-row{display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}
.ad-ref-lab{flex:0 0 auto;font-size:11px;font-weight:800;color:var(--ink-soft)}
.ad-ref-row.claim .ad-ref-lab{color:var(--ok)} .ad-ref-row.rationale .ad-ref-lab{color:var(--brand)} .ad-ref-row.principle .ad-ref-lab{color:var(--violet)}
.xref-link{display:inline-flex;align-items:baseline;gap:5px;text-decoration:none;border-radius:6px;padding:1px 4px;margin-right:3px}
.xref-link:hover{background:var(--brand-tint)}
.xref-code{font-weight:800;font-size:12px;border-radius:6px;padding:1px 8px;border:1px solid}
.ad-ref-row.claim .xref-code{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.ad-ref-row.rationale .xref-code{color:var(--brand);background:var(--brand-tint);border-color:var(--brand)}
.ad-ref-row.principle .xref-code{color:var(--violet);background:var(--violet-tint);border-color:var(--violet-line)}
.xref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
[data-component="principle-terminal"]{margin:12px 0 0;border:1px solid var(--violet-line);border-radius:12px;padding:13px 16px;background:var(--violet-tint)}
.pt-label{font-size:10.5px;font-weight:800;letter-spacing:.08em;color:var(--violet);background:var(--paper);border:1px solid var(--violet-line);border-radius:5px;padding:1px 7px;margin-right:8px}
.pt-id{font-weight:800;font-size:12.5px;color:var(--violet);font-family:ui-monospace,monospace}
.pt-text{font-size:13.5px;color:var(--ink-soft);line-height:1.75;margin:7px 0 0}
/* §6 quality table */
table[data-component="quality-table"]{width:100%;border-collapse:separate;border-spacing:0;font-size:13.5px}
[data-component="quality-table"] thead th{background:var(--ok);color:#fff;text-align:left;font-size:11.5px;font-weight:800;letter-spacing:.06em;padding:11px 14px}
[data-component="quality-table"] thead th:first-child{border-top-left-radius:12px} [data-component="quality-table"] thead th:last-child{border-top-right-radius:12px}
[data-component="quality-table"] tbody td{padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:top;line-height:1.6}
[data-component="quality-table"] tbody tr:nth-child(even) td{background:var(--paper-2)}
.qa-id{font-weight:800;font-family:ui-monospace,monospace;color:var(--ok);white-space:nowrap}
.qa-attr{font-weight:800;font-size:13.5px}
.qa-target{font-weight:800;color:var(--ink);white-space:nowrap}
.qa-plain{display:block;margin-top:4px;font-size:12px;color:var(--ink-soft)}
.qa-srs{font-size:11px;font-weight:800;text-decoration:none;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand);border-radius:6px;padding:1px 7px;white-space:nowrap}
/* §7 risks */
[data-component="risk-card-grid"]{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin:8px 0}
@media(max-width:640px){[data-component="risk-card-grid"]{grid-template-columns:1fr}}
[data-component="risk-card"]{border:1px solid var(--line);border-radius:12px;padding:13px 16px;background:var(--paper);box-shadow:var(--shadow)}
.rk-head{display:flex;align-items:center;gap:9px;margin-bottom:5px}
.rk-id{font-weight:800;font-size:12px;color:var(--ink-soft);background:var(--paper-3);border:1px solid var(--line);border-radius:6px;padding:2px 8px}
.rk-sev{font-size:10.5px;font-weight:800;border-radius:999px;padding:2px 10px;border:1px solid}
.rk-sev.high{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.rk-sev.mid{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.rk-risk{font-weight:800;font-size:14px;line-height:1.5;margin:2px 0 6px}
.rk-row{font-size:12.5px;color:var(--ink-soft);line-height:1.7;margin:2px 0}
.rk-row .rk-k{font-weight:700;color:var(--ink-faint);margin-right:5px}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="architecture-description">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio architecture-description-pack assembler (folio-5uu / instance#1) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_arch_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このアーキテクチャ記述が約束すること (1 文サマリ)"
  local n_comp n_dec
  n_comp="$(q '.components | length')"; n_dec="$(q '.decisions | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">構成</span><span class="v">%s</span></span><span class="m"><span class="k">照会先</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "architecture-description (アーキテクチャ記述)" "$(esc "arc42 8 章 (部品 ${n_comp} / 決定 ${n_dec})")" "$(esc "$(q '.cross_doc.srs_doc_id')・$(q '.cross_doc.adr_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (照会先 SRS の要件 / ADR の判断・案A)。 ★CJK 規律: <b> 閉じ直後に助詞 (の) を空白なしで
  #   置く (`</b>の要件` = 空白を挟むと行頭に助詞が落ちる・verify-arch の CJK 空白規律と整合)。 区切り ' / ' は ASCII 間ゆえ可。
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の要件 / <b>%s</b>の判断</div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.cross_doc.adr_doc_id')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# mermaid 図 emit (raw DSL を esc して <pre class="mermaid"> へ join。 raw DSL 露出 = gate I blocker・folio-97z)。
emit_diagram() {
  local did="$1" kind comp tag cap
  kind="$(q '.diagrams[] | select(.id=="'"$did"'") | .kind')"
  comp="${DIAG_COMPONENT[$kind]}"; tag="${DIAG_TAG[$kind]}"
  cap="$(q '.diagrams[] | select(.id=="'"$did"'") | .caption')"
  printf '<figure class="diagram" data-component="%s">\n<pre class="mermaid">' "$(esc "$comp")"
  local first=1 ln
  while IFS= read -r ln; do
    [[ "$first" -eq 1 ]] || printf '\n'; first=0
    printf '%s' "$(esc "$ln")"
  done < <(q '.diagrams[] | select(.id=="'"$did"'") | .lines[]')
  printf '</pre>\n<figcaption><span class="diag-tag">%s</span>%s</figcaption>\n</figure>\n' "$(esc "$tag")" "$(esc "$cap")"
}

emit_context() {
  printf '<p data-component="context-problem">%s</p>\n' "$(mark_terms "$(q '.context.problem')")"
  printf '<div data-component="actor-stakeholder-table">\n'
  local -a AIDS; mapfile -t AIDS < <(q '.context.actors[].id')
  local aid kind klabel
  for aid in "${AIDS[@]}"; do
    kind="$(q '.context.actors[] | select(.id=="'"$aid"'") | .kind')"; klabel="${ACTOR_KIND_LABEL[$kind]:-$kind}"
    printf '<div class="arch-actor"><span class="nm">%s<span class="akind %s">%s</span></span><span class="ar-role">%s</span></div>\n' \
      "$(esc "$(q '.context.actors[] | select(.id=="'"$aid"'") | .name')")" "$(esc "$kind")" "$(esc "$klabel")" "$(esc "$(q '.context.actors[] | select(.id=="'"$aid"'") | .role')")"
  done
  printf '</div>\n'
  emit_diagram D1
}

emit_strategy() {
  printf '<div data-component="strategy-card-grid">\n'
  local -a SIDS; mapfile -t SIDS < <(q '.strategy[].id')
  local sid
  for sid in "${SIDS[@]}"; do
    printf '<div data-component="strategy-card"><div class="st-head"><span class="st-id">%s</span><span class="st-name">%s</span></div>\n' \
      "$(esc "$sid")" "$(esc "$(q '.strategy[] | select(.id=="'"$sid"'") | .name')")"
    printf '<p class="st-plain">%s</p>\n' "$(mark_terms "$(q '.strategy[] | select(.id=="'"$sid"'") | .plain')")"
    printf '<p class="st-why">%s</p>\n</div>\n' "$(mark_terms "$(q '.strategy[] | select(.id=="'"$sid"'") | .rationale')")"
  done
  printf '</div>\n'
}

emit_components() {
  emit_diagram D2
  printf '<div class="tbl-wrap"><table data-component="component-table"><thead><tr><th>部品 (コンテナ)</th><th>担当すること (責務)</th></tr></thead><tbody>\n'
  local -a CIDS; mapfile -t CIDS < <(q '.components[].id')
  local cid kind klabel
  for cid in "${CIDS[@]}"; do
    kind="$(q '.components[] | select(.id=="'"$cid"'") | .kind')"; klabel="${COMP_KIND_LABEL[$kind]:-$kind}"
    printf '<tr data-component="component-row" id="comp-%s"><td><span class="cn">%s</span><br><span class="ckind %s">%s</span></td><td>%s<span class="cwhy">%s</span></td></tr>\n' \
      "$(esc "$cid")" "$(esc "$(q '.components[] | select(.id=="'"$cid"'") | .name')")" "$(esc "$kind")" "$(esc "$klabel")" \
      "$(mark_terms "$(q '.components[] | select(.id=="'"$cid"'") | .responsibility')")" "$(mark_terms "$(q '.components[] | select(.id=="'"$cid"'") | .separation_reason')")"
  done
  printf '</tbody></table></div>\n'
}

emit_runtime() {
  local -a FIDS; mapfile -t FIDS < <(q '.runtime.flows[].id')
  local fid
  for fid in "${FIDS[@]}"; do
    printf '<div data-component="runtime-flow"><p class="rt-name">%s</p>\n' "$(esc "$(q '.runtime.flows[] | select(.id=="'"$fid"'") | .name')")"
    # ★folio-c5r.10: runtime flow の summary (流れの概要・SSoT にあるが従来未描画 = silent field-drop) を name と steps の間に描画。
    #   rt-name/rt-step と同じ plain (esc・term-inline なし) 慣習で出し verify が set_eq で fidelity 突合。
    printf '<p class="rt-summary">%s</p>\n' "$(esc "$(q '.runtime.flows[] | select(.id=="'"$fid"'") | .summary')")"
    local n=0 st
    while IFS= read -r st; do [[ -n "$st" ]] || continue; n=$((n+1)); printf '<div class="rt-step"><span class="rt-n">%s</span><span class="rt-v">%s</span></div>\n' "$n" "$(esc "$st")"; done < <(q '.runtime.flows[] | select(.id=="'"$fid"'") | .steps[]')
    printf '</div>\n'
  done
  emit_diagram D3
}

emit_decisions() {
  printf '<div class="arch-grid">\n'
  local -a DIDS; mapfile -t DIDS < <(q '.decisions[].id')
  local did
  local SRS_HTML ADR_HTML ADR_TITLE
  SRS_HTML="$(q '.cross_doc.srs_html')"; ADR_HTML="$(q '.cross_doc.adr_html')"; ADR_TITLE="$ADR_REF_TITLE"
  for did in "${DIDS[@]}"; do
    printf '<div data-component="arch-decision-card" id="ad-%s">\n' "$(esc "$did")"
    printf '<div class="ad-head"><span class="ad-id">%s</span><h3 class="ad-title">%s</h3></div>\n' \
      "$(esc "$did")" "$(esc "$(q '.decisions[] | select(.id=="'"$did"'") | .title')")"
    printf '<p class="ad-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$did")"
    printf '<p class="ad-summary">%s</p>\n' "$(mark_terms "$(q '.decisions[] | select(.id=="'"$did"'") | .summary')")"
    printf '<p class="ad-rationale" data-prose-slot="rationale" data-slot-id="rationale-%s"></p>\n' "$(esc "$did")"
    printf '<div class="ad-refs">\n'
    # ★SRS 充足照会 (role=claim・別文書 link・コード + SRS 由来機能名ラベル併記)
    printf '<div class="ad-ref-row claim"><span class="ad-ref-lab">充足する要件</span>'
    local fr
    while IFS= read -r fr; do [[ -n "$fr" ]] || continue; printf '<a class="xref-link" href="%s#%s" data-arch-ref="%s" data-arch-role="claim"><span class="xref-code">%s</span><span class="xref-label" data-srs-label-ref="%s">%s</span></a>' \
      "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"; done < <(q '.decisions[] | select(.id=="'"$did"'") | .refs.srs[]')
    printf '</div>\n'
    # ★ADR 根拠照会 (role=rationale・別文書 link・doc_id + ADR タイトルラベル併記)
    local nadr; nadr="$(q '.decisions[] | select(.id=="'"$did"'") | .refs.adr | length')"
    if [[ "$nadr" != "0" ]]; then
      printf '<div class="ad-ref-row rationale"><span class="ad-ref-lab">判断の根拠</span>'
      local ar
      while IFS= read -r ar; do [[ -n "$ar" ]] || continue; printf '<a class="xref-link" href="%s#decision" data-adr-ref="%s" data-adr-role="rationale"><span class="xref-code">%s</span><span class="xref-label" data-adr-label-ref="%s">%s</span></a>' \
        "$(esc "$ADR_HTML")" "$(esc "$ar")" "$(esc "$ar")" "$(esc "$ar")" "$(esc "$ADR_TITLE")"; done < <(q '.decisions[] | select(.id=="'"$did"'") | .refs.adr[]')
      printf '</div>\n'
    fi
    # ★原則終端 照会 (role=principle・within-doc anchor link)
    local nprin; nprin="$(q '.decisions[] | select(.id=="'"$did"'") | .refs.principle | length')"
    if [[ "$nprin" != "0" ]]; then
      printf '<div class="ad-ref-row principle"><span class="ad-ref-lab">行き着く原則</span>'
      local pr
      while IFS= read -r pr; do [[ -n "$pr" ]] || continue; printf '<a class="xref-link" href="#principle-%s" data-principle-ref="%s" data-principle-role="principle"><span class="xref-code">%s</span></a>' \
        "$(esc "$pr")" "$(esc "$pr")" "$(esc "$pr")"; done < <(q '.decisions[] | select(.id=="'"$did"'") | .refs.principle[]')
      printf '</div>\n'
    fi
    printf '</div>\n</div>\n'
  done
  printf '</div>\n'
  # 原則終端 panel (照会 graph の終端・within-doc anchor target)
  printf '<div data-component="principle-terminal" id="principle-%s"><span class="pt-label">原則終端</span><span class="pt-id">%s</span><p class="pt-text">%s</p></div>\n' \
    "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.text')")"
}

emit_quality() {
  printf '<div class="tbl-wrap"><table data-component="quality-table"><thead><tr><th>品質特性</th><th>目標とやさしい説明</th><th>照会先 (SRS)</th></tr></thead><tbody>\n'
  local SRS_HTML; SRS_HTML="$(q '.cross_doc.srs_html')"
  local -a QIDS; mapfile -t QIDS < <(q '.quality[].id')
  local qid sref
  for qid in "${QIDS[@]}"; do
    sref="$(q '.quality[] | select(.id=="'"$qid"'") | .srs_ref')"
    printf '<tr data-component="quality-row" id="qa-%s"><td><span class="qa-id">%s</span> <span class="qa-attr">%s</span></td><td><span class="qa-target">%s</span><span class="qa-plain">%s</span></td><td><a class="qa-srs" href="%s#%s" data-quality-srs-ref="%s">%s</a></td></tr>\n' \
      "$(esc "$qid")" "$(esc "$qid")" "$(esc "$(q '.quality[] | select(.id=="'"$qid"'") | .attribute')")" \
      "$(esc "$(q '.quality[] | select(.id=="'"$qid"'") | .target')")" "$(mark_terms "$(q '.quality[] | select(.id=="'"$qid"'") | .plain')")" \
      "$(esc "$SRS_HTML")" "$(esc "$sref")" "$(esc "$sref")" "$(esc "$sref")"
  done
  printf '</tbody></table></div>\n'
}

emit_risks() {
  printf '<div data-component="risk-card-grid">\n'
  local -a RIDS; mapfile -t RIDS < <(q '.risks[].id')
  local rid sev sevc
  for rid in "${RIDS[@]}"; do
    sev="$(q '.risks[] | select(.id=="'"$rid"'") | .severity')"; sevc="${SEV_CLASS[$sev]:-mid}"
    printf '<div data-component="risk-card" id="risk-%s"><div class="rk-head"><span class="rk-id">%s</span><span class="rk-sev %s">%s</span></div>\n' \
      "$(esc "$rid")" "$(esc "$rid")" "$(esc "$sevc")" "$(esc "$sev")"
    printf '<p class="rk-risk">%s</p>\n' "$(mark_terms "$(q '.risks[] | select(.id=="'"$rid"'") | .risk')")"
    printf '<p class="rk-row"><span class="rk-k">起きると</span>%s</p>\n' "$(mark_terms "$(q '.risks[] | select(.id=="'"$rid"'") | .impact')")"
    printf '<p class="rk-row"><span class="rk-k">どう抑える</span>%s</p>\n</div>\n' "$(mark_terms "$(q '.risks[] | select(.id=="'"$rid"'") | .mitigation')")"
  done
  printf '</div>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

emit_footer() {
  core_emit_footer '<span>folio design system</span><span>architecture-description-pack</span><span>folio engine 段階3 (instance#1)</span><span>arc42 + C4 + cross-doc 照会 graph</span>'
}

# mermaid render JS (defer 済みで window.mermaid 利用可・raw DSL を SVG へ。 no-JS では pre が読める fallback)。
emit_mermaid_js() {
  printf '<script src="assets/mermaid.min.js" defer></script>\n'
  cat <<'JS'
<script>
window.addEventListener('DOMContentLoaded', async () => {
  if (!window.mermaid) return;
  mermaid.initialize({
    startOnLoad: false, securityLevel: 'antiscript', theme: 'base',
    flowchart: { useMaxWidth: true }, sequence: { useMaxWidth: true },
    themeVariables: {
      primaryColor: '#e8f0f7', primaryTextColor: '#08131a', primaryBorderColor: '#2a4d6e',
      lineColor: '#2a4d6e', secondaryColor: '#f0eafa', tertiaryColor: '#f5f8fa',
      fontFamily: '"Noto Sans CJK JP","Noto Sans JP",system-ui,sans-serif'
    }
  });
  try { await mermaid.run(); } catch (e) {}
});
</script>
JS
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "課題と背景"                "何を解こうとしているか、 誰が関わるか"            "$ICO_MAP";     emit_context;    band_end
  band ok     "ソリューション戦略"        "全体を貫く設計方針と、 それぞれの理由"            "$ICO_COMPASS"; emit_strategy;   band_end
  band info   "部品の組み立て"            "システムを 6 つの部品に分け、 何を担当するか"      "$ICO_BLOCKS";  emit_components; band_end
  band violet "動いているときの流れ"      "二重予約をどう止めるか、 部品がどう連携するか"      "$ICO_ARROW";   emit_runtime;    band_end
  band brand  "アーキテクチャ決定"        "何を決めたか・なぜその案か・どの要件と判断につながるか" "$ICO_GAVEL";   emit_decisions;  band_end
  band ok     "品質特性"                  "どんな品質をどこまで目指すか"                      "$ICO_GAUGE";   emit_quality;    band_end
  band warn   "リスク"                    "何が危うく、 どう抑えるか"                          "$ICO_ALERT";   emit_risks;      band_end
  band violet "用語集"                    "本文に出てくる専門語のやさしい説明"                "$ICO_BOOK";    emit_glossary;   band_end
  printf '</div>\n'
  emit_footer
  emit_mermaid_js
  printf '</body>\n</html>\n'
}

validate
# ★SRS 由来 ラベル map (fabrication-free・FR=requirements[].label を verbatim)。 validate() が SRS 実在 +
#   全 srs ref が SRS に実在を保証済ゆえ、 参照される全 ref の label は欠落なし。 SRS contract は read-only (無編集)。
#   verify-arch.sh が同一導出で fidelity 突合。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
declare -A SRS_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && SRS_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
# ★cross-doc 照会ラベル live-mirror (folio-c5r.13・Option A): 参照先 ADR の実 .meta.title を「ADR: <title>」へ
#   統一 (手書き cross_doc.adr_title 廃止・retitle drift を verify が fail-closed 化)。 validate 後ゆえ実在保証済。
ADR_REF_TITLE="ADR: $(yq -r '.meta.title' "${CONTRACT_DIR}/$(q '.cross_doc.adr_contract')")"
core_finalize "assemble-arch"
