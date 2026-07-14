#!/usr/bin/env bash
# folio engine post-B6 (folio-8cha / c5r capability-census) — roadmap-pack 決定的 assembler
#
# 入力 roadmap contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# changelog / vision generator と *同型* の機構を roadmap-pack schema へ適用する:
#   - 内容・構造 (cover / 直近段階のハイライト / 段階別目標 (priority 群) / 目標→照会 trace / glossary)
#     は contract から決定的組立。 元データに無い段階・目標・照会 edge を生成できない。
#   - ★順序 = seq 昇順を assembler が決定的に sort (sort -n = 決定的手段)。 contract の記載順に依存しない
#     = 段階順の乱れ/捏造は原理的に不可 (changelog の semver 降順 sort と同型・方向は未来へ向かう昇順)。
#   - ★区分 = priority (MoSCoW: must/should/could) の固定 canonical 順で反復 (contract のキー順に依存しない)。
#     空 priority は省略・未知 priority は validate で拒否。
#   - ★cross-doc 前方照会 edge: 各目標項目の refs.vision[] (F・role=claim) / refs.srs[] (FR・role=claim) が
#     参照先 VISION / SRS contract に実在することを validate() が *生成前に* fail-closed で確かめる (集合外参照は拒否)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・不正 seq・未知 priority は拒否。
#   - prose スロット (章リード / cover 1 文サマリ / 直近段階ハイライト) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# inject-prose.sh は SRS/ADR/changelog と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-roadmap.sh <roadmap-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-roadmap.sh <roadmap-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-roadmap: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-roadmap: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-roadmap: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# ---- MoSCoW priority (canonical 順・label・class)。 空 priority は省略・未知 priority は validate で拒否。
#   ★assembler は *この固定 canonical 順* で priority を反復する (contract のキー順に依存しない = 決定的)。
PRIO_ORDER=(must should could)
declare -A PRIO_LABEL=( [must]=必須 [should]=推奨 [could]=任意 )
declare -A PRIO_CLASS=( [must]=must [should]=should [could]=could )
declare -A PRIO_OK=( [must]=1 [should]=1 [could]=1 )

# 全目標項目 (全 stage・全 priority flatten) の base 式。 順序・件数・id 突合の SSoT。
ITEMS_EXPR='[.stages[].items | .[][]]'

# ---- icon SVG (roadmap-pack 固有。 共用 icon=ICO_BOOK/USER + ico() は lib/common.sh) ----
ICO_TARGET='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>'
ICO_FLAG='<path d="M4 22V4"/><path d="M4 4h13l-2 4 2 4H4"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0
  core_validate_strings "assemble-roadmap" || errs=1
  # stage id 一意性
  local dupid; dupid="$(q '.stages[].id' | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$dupid" ]] || { echo "assemble-roadmap: stage id 重複: $dupid" >&2; errs=1; }
  # seq が正の整数かつ一意
  local badseq; badseq="$(q '.stages[].seq' | { grep -vE '^[0-9]+$' || true; } | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$badseq" ]] || { echo "assemble-roadmap: seq が正の整数でない: $badseq" >&2; errs=1; }
  local dupseq; dupseq="$(q '.stages[].seq' | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$dupseq" ]] || { echo "assemble-roadmap: seq 重複: $dupseq" >&2; errs=1; }
  [[ "$(q '.stages | length')" -ge 1 ]] || { echo "assemble-roadmap: stages が空 (段階が 1 件以上必要)" >&2; errs=1; }
  # 目標項目 id 一意性 (全 doc 横断)
  local d; d="$(q "$ITEMS_EXPR | .[].id" | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$d" ]] || { echo "assemble-roadmap: 目標項目 id 重複: $d" >&2; errs=1; }
  # priority キー ⊆ canonical (全 stage)。 未知 priority を拒否。
  local badprio; badprio="$(q '[.stages[].items] | .[] | keys | .[]' | sort -u \
    | while IFS= read -r k; do [[ -z "$k" || -v PRIO_OK[$k] ]] || printf '%s ' "$k"; done)"
  [[ -z "$badprio" ]] || { echo "assemble-roadmap: 未知の priority: $badprio (must|should|could)" >&2; errs=1; }
  # ★空 priority (キーはあるが item 0) を拒否 (省略すべき = 「該当なし」の負の主張を空配列で偽装させない)。
  local emptyprio; emptyprio="$(q '[.stages[].items] | .[] | to_entries | .[] | select((.value | length) == 0) | .key' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$emptyprio" ]] || { echo "assemble-roadmap: 空 priority (item 0 のキー・省略すべき): $emptyprio" >&2; errs=1; }
  # 各目標項目は refs.vision / refs.srs の少なくとも一方を 1 件以上持つ (照会なしの宙に浮いた目標を禁止)。
  local n_noref; n_noref="$(q "$ITEMS_EXPR | [.[] | select(((.refs.vision // []) | length) == 0 and ((.refs.srs // []) | length) == 0) | .id] | length")"
  [[ "$n_noref" == "0" ]] || { echo "assemble-roadmap: refs 空の目標項目が $n_noref 件 (各項目は VISION 方向か SRS FR の照会を 1 件以上持つ)" >&2; errs=1; }
  # ★空/null の ref を dangling 判定 (comm -23) が空行に畳んで素通すため明示拒否 (壊れた前方参照)。
  local n_vis n_vis_ne n_srs n_srs_ne
  n_vis="$(q "$ITEMS_EXPR | [.[].refs.vision // [] | .[]] | length")"; n_vis_ne="$(q "$ITEMS_EXPR | [.[].refs.vision // [] | .[] | select((. // \"\") != \"\")] | length")"
  [[ "$n_vis" == "$n_vis_ne" ]] || { echo "assemble-roadmap: ★空 VISION 照会 ref (有効 $n_vis_ne/$n_vis 件)" >&2; errs=1; }
  n_srs="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length")"; n_srs_ne="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[] | select((. // \"\") != \"\")] | length")"
  [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-roadmap: ★空 SRS 照会 ref (有効 $n_srs_ne/$n_srs 件)" >&2; errs=1; }
  # ★edge-bearing graph の要請 (rolemap): VISION/SRS 双方に 1 件以上照会 (照会先ありで 0 件 = verify-graph vacuum guard FAIL)。
  [[ "$n_vis" -ge 1 ]] || { echo "assemble-roadmap: VISION 照会が 0 件 (rolemap edge の照会先ありゆえ 1 件以上必要)" >&2; errs=1; }
  [[ "$n_srs" -ge 1 ]] || { echo "assemble-roadmap: SRS 照会が 0 件 (rolemap edge の照会先ありゆえ 1 件以上必要)" >&2; errs=1; }
  # ★cross-doc 前方照会の終端解決: 参照先 VISION/SRS contract 実在 + refs の F/FR が実在
  local vis_rel vis_abs vis_docid srs_rel srs_abs srs_docid missing smissing
  vis_rel="$(q '.cross_doc.vision_contract')"; vis_abs="${CONTRACT_DIR}/${vis_rel}"
  if [[ ! -f "$vis_abs" ]]; then
    echo "assemble-roadmap: cross_doc.vision_contract が見つからない: $vis_rel (照会先 VISION 不在)" >&2; errs=1
  else
    vis_docid="$(yq -r '.meta.doc_id' "$vis_abs")"
    [[ "$vis_docid" == "$(q '.cross_doc.vision_doc_id')" ]] || { echo "assemble-roadmap: cross_doc.vision_doc_id が VISION contract の doc_id ($vis_docid) と不一致" >&2; errs=1; }
    missing="$(comm -23 <(q "$ITEMS_EXPR | .[].refs.vision // [] | .[]" | sort -u) <(yq -r '.features[].id' "$vis_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-roadmap: ★VISION 照会の dangling: refs.vision が VISION 機能に実在しない: $missing" >&2; errs=1; }
  fi
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-roadmap: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"
    [[ "$srs_docid" == "$(q '.cross_doc.srs_doc_id')" ]] || { echo "assemble-roadmap: cross_doc.srs_doc_id が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    smissing="$(comm -23 <(q "$ITEMS_EXPR | .[].refs.srs // [] | .[]" | sort -u) <(yq -r '.requirements[].id' "$srs_abs" | sort -u))"
    [[ -z "$smissing" ]] || { echo "assemble-roadmap: ★SRS 照会の dangling: refs.srs が SRS 要件に実在しない: $smissing" >&2; errs=1; }
  fi
  core_validate_glossary_substring "assemble-roadmap" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-roadmap: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- roadmap-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_roadmap_css() {
  cat <<'CSS'
/* ===== roadmap-pack 固有部品 (folio-8cha)。 srs.css の token を流用 ===== */
[data-component="roadmap-highlights"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow);margin:10px 0}
.hl-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:6px}
.hl-head .hl-stage{font-weight:800;font-size:17px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand-line);border-radius:7px;padding:2px 11px}
.hl-head .hl-target{font-size:12.5px;color:var(--ink-faint)}
.hl-head .hl-tag{font-size:11px;font-weight:700;color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:999px;padding:2px 10px}
[data-component="roadmap-highlights"] .hl-summary{display:block;margin:0 0 10px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px;line-height:1.7}
.hl-counts{display:flex;flex-wrap:wrap;gap:8px}
.hl-count{display:inline-flex;align-items:center;gap:6px;font-size:12px;border:1px solid var(--line);border-radius:7px;padding:3px 10px;background:var(--paper-2)}
.hl-count .hlc-label{font-weight:700;color:var(--ink-soft)}
.hl-count .hlc-n{font-weight:800;font-size:13px;color:var(--ink-soft);background:var(--paper-3);border-radius:5px;padding:0 7px}
.hl-count.must .hlc-label{color:var(--brand)} .hl-count.should .hlc-label{color:var(--info)} .hl-count.could .hlc-label{color:var(--ink-faint)}
.rm-stages{display:flex;flex-direction:column;gap:16px;margin:10px 0}
[data-component="roadmap-stage"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.rm-stage-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap;margin-bottom:8px;padding-bottom:7px;border-bottom:1px solid var(--line)}
.rm-stage-head .rm-stage-badge{font-weight:800;font-size:16px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand-line);border-radius:7px;padding:2px 11px}
.rm-stage-head .rm-stage-name{font-weight:700;font-size:14.5px;color:var(--ink)}
.rm-stage-head .rm-stage-target{font-size:12.5px;color:var(--ink-faint);margin-left:auto}
.rm-stage-outcome{margin:0 0 10px;font-size:13.5px;line-height:1.75;color:var(--ink-soft)}
.rm-prios{display:flex;flex-direction:column;gap:11px}
.rm-prio-head{display:flex;align-items:center;gap:8px;margin-bottom:4px}
.rm-prio .rm-prio-label{font-size:12px;font-weight:700;border-radius:999px;padding:2px 11px;border:1px solid}
.rm-prio.must .rm-prio-label{color:var(--brand);background:var(--brand-tint);border-color:var(--brand-line)}
.rm-prio.should .rm-prio-label{color:var(--info);background:var(--info-tint,var(--paper-3));border-color:var(--line)}
.rm-prio.could .rm-prio-label{color:var(--ink-faint);background:var(--paper-3);border-color:var(--line)}
.rm-items{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px}
[data-component="roadmap-item"]{border:1px solid var(--line);border-radius:9px;padding:9px 12px;background:var(--paper-2)}
[data-component="roadmap-item"] .rm-id{font-size:10.5px;font-weight:800;color:var(--ink-faint);margin-right:6px}
[data-component="roadmap-item"] .rm-text{margin:0;font-size:13.5px;line-height:1.7;color:var(--ink)}
[data-component="roadmap-item"] .rm-plain{display:block;margin:6px 0 0;font-size:12.5px;color:var(--ink-soft);background:var(--brand-tint);border-radius:6px;padding:5px 9px;line-height:1.7}
.rm-refs{margin:7px 0 0;display:flex;flex-direction:column;gap:4px}
.rm-ref-row{display:flex;gap:7px;align-items:baseline;flex-wrap:wrap}
.rm-ref-row .rm-ref-k{flex:0 0 auto;font-size:11px;font-weight:700;color:var(--ink-faint)}
.rm-ref-row.dir .rm-ref-k{color:var(--brand)} .rm-ref-row.req .rm-ref-k{color:var(--ok)}
a.rm-ref{display:inline-flex;align-items:baseline;gap:5px;text-decoration:none;margin-right:5px}
.rm-ref .xref-code{font-weight:800;font-size:11.5px;border-radius:6px;padding:1px 8px;border:1px solid}
.rm-ref-row.dir .xref-code{color:var(--brand);background:var(--brand-tint);border-color:var(--brand-line)}
.rm-ref-row.req .xref-code{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.rm-ref .rm-ref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
table[data-component="roadmap-trace"]{width:100%;border-collapse:collapse;margin:8px 0;font-size:13px}
[data-component="roadmap-trace"] th,[data-component="roadmap-trace"] td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
[data-component="roadmap-trace"] thead th{background:var(--paper-3);font-size:11.5px;color:var(--ink-soft);letter-spacing:.02em}
[data-component="roadmap-trace"] .trc-id{font-weight:800;color:var(--ink-soft);white-space:nowrap}
[data-component="roadmap-trace"] .trc-stage{white-space:nowrap;font-size:12px;color:var(--ink-faint)}
[data-component="roadmap-trace"] .trc-prio{white-space:nowrap;font-size:12px}
[data-component="roadmap-trace"] .trc-ref{font-size:12px;line-height:1.7}
[data-component="roadmap-trace"] .trc-edge{display:inline}
[data-component="roadmap-trace"] .trc-code{font-size:11px;font-weight:800}
[data-component="roadmap-trace"] .trc-ref .trc-dir{color:var(--brand)} [data-component="roadmap-trace"] .trc-ref .trc-req{color:var(--ok)}
[data-component="roadmap-trace"] .trc-label{font-weight:400;color:var(--ink-soft)}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="roadmap">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio roadmap-pack assembler (folio-8cha) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_roadmap_css
  printf '\n</style>\n'
  core_emit_graph_head
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このロードマップが約束すること (1 文サマリ)"
  local n_st first last first_target last_target
  n_st="$(q '.stages | length')"
  first="$(q '.stages[] | select(.seq=='"${OS[0]}"') | .id')"; last="$(q '.stages[] | select(.seq=='"${OS[-1]}"') | .id')"
  first_target="$(q '.stages[] | select(.seq=='"${OS[0]}"') | .target')"; last_target="$(q '.stages[] | select(.seq=='"${OS[-1]}"') | .target')"
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">収録</span><span class="v">%s</span></span><span class="m"><span class="k">期間</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "roadmap (ロードマップ)" "$(esc "${n_st} 段階 (${first}–${last})")" "$(esc "${first_target} – ${last_target}")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (照会先 VISION / SRS)。 changelog と対称の 2-<b> テンプレ。
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の機能方向 / <b>%s</b>の要件</div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.vision_doc_id')")" "$(esc "$(q '.cross_doc.srs_doc_id')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# 直近段階 (seq 昇順の先頭 = OS[0]) のハイライト。 3 priority の件数 (0 含む = 負の主張「この優先度の項目なし」) を
#   contract から決定的に emit する。 highlight 散文は prose スロット。
emit_highlights() {
  local first="${OS[0]}" sel_first sid starget prio n
  sel_first="$(q '.stages[] | select(.seq=='"$first"') | .id')"; sid="$sel_first"
  starget="$(q '.stages[] | select(.seq=='"$first"') | .target')"
  printf '<div data-component="roadmap-highlights">\n'
  printf '<div class="hl-head"><span class="hl-stage">%s</span><span class="hl-target">%s</span><span class="hl-tag">直近</span></div>\n' "$(esc "$sid")" "$(esc "$starget")"
  printf '<p class="hl-summary" data-prose-slot="highlight" data-slot-id="nearest-highlight"></p>\n'
  printf '<div class="hl-counts">\n'
  for prio in "${PRIO_ORDER[@]}"; do
    n="$(q '.stages[] | select(.seq=='"$first"') | .items.'"$prio"' // [] | length')"
    printf '<span class="hl-count %s"><span class="hlc-label">%s</span><span class="hlc-n">%s</span></span>\n' \
      "${PRIO_CLASS[$prio]}" "$(esc "${PRIO_LABEL[$prio]}")" "$(esc "$n")"
  done
  printf '</div>\n</div>\n'
}

# 1 目標項目カード (id=rm-<id>)。 text (mark_terms) + refs (VISION=方向 / SRS=要件) を emit。
emit_item() {
  local base="$1" id text nvis nsrs
  id="$(yq -r "$base"' | .id' "$CONTRACT")"
  text="$(yq -r "$base"' | .text' "$CONTRACT")"
  nvis="$(yq -r "$base"' | .refs.vision // [] | length' "$CONTRACT")"
  nsrs="$(yq -r "$base"' | .refs.srs // [] | length' "$CONTRACT")"
  printf '<li data-component="roadmap-item" id="rm-%s"><p class="rm-text"><span class="rm-id">%s</span>%s</p>\n' "$(esc "$id")" "$(esc "$id")" "$(mark_terms "$text")"
  printf '<p class="rm-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$id")"
  printf '<div class="rm-refs">\n'
  if [[ "$nvis" -gt 0 ]]; then
    printf '<div class="rm-ref-row dir"><span class="rm-ref-k">方向</span>'
    while IFS= read -r fv; do [[ -n "$fv" ]] || continue; printf '<a class="rm-ref" href="%s#%s" data-rm-vision-ref="%s" data-rm-vision-role="claim"><span class="xref-code">%s</span><span class="rm-ref-label" data-vision-label-ref="%s">%s</span></a>' \
      "$(esc "$VISION_HTML")" "$(esc "$fv")" "$(esc "$fv")" "$(esc "$fv")" "$(esc "$fv")" "$(esc "${VISION_LABEL[$fv]}")"; done < <(yq -r "$base"' | .refs.vision // [] | .[]' "$CONTRACT")
    printf '</div>\n'
  fi
  if [[ "$nsrs" -gt 0 ]]; then
    printf '<div class="rm-ref-row req"><span class="rm-ref-k">要件</span>'
    while IFS= read -r fr; do [[ -n "$fr" ]] || continue; printf '<a class="rm-ref" href="%s#%s" data-rm-srs-ref="%s" data-rm-srs-role="claim"><span class="xref-code">%s</span><span class="rm-ref-label" data-srs-label-ref="%s">%s</span></a>' \
      "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"; done < <(yq -r "$base"' | .refs.srs // [] | .[]' "$CONTRACT")
    printf '</div>\n'
  fi
  printf '</div>\n</li>\n'
}

# 1 段階のカード。 $1 = seq。 priority は canonical 順・present+nonempty のみ。
emit_stage() {
  local seq="$1" sel sid sname starget soutcome prio nitem i
  sel='.stages[] | select(.seq=='"$seq"')'
  sid="$(q "$sel"' | .id')"; sname="$(q "$sel"' | .name')"; starget="$(q "$sel"' | .target')"; soutcome="$(q "$sel"' | .outcome')"
  printf '<div data-component="roadmap-stage" id="stage-%s">\n' "$(esc "$seq")"
  printf '<div class="rm-stage-head"><span class="rm-stage-badge">%s</span><span class="rm-stage-name">%s</span><span class="rm-stage-target">%s</span></div>\n' "$(esc "$sid")" "$(esc "$sname")" "$(esc "$starget")"
  printf '<p class="rm-stage-outcome">%s</p>\n' "$(mark_terms "$soutcome")"
  printf '<div class="rm-prios">\n'
  for prio in "${PRIO_ORDER[@]}"; do
    nitem="$(q "$sel"' | .items.'"$prio"' // [] | length')"
    [[ "$nitem" -gt 0 ]] || continue
    printf '<div class="rm-prio %s"><div class="rm-prio-head"><span class="rm-prio-label">%s</span></div>\n' "${PRIO_CLASS[$prio]}" "$(esc "${PRIO_LABEL[$prio]}")"
    printf '<ul class="rm-items">\n'
    for ((i=0; i<nitem; i++)); do
      emit_item "$sel"' | .items.'"$prio"'['"$i"']'
    done
    printf '</ul></div>\n'
  done
  printf '</div>\n</div>\n'
}

emit_stages() {
  printf '<div class="rm-stages">\n'
  local s
  for s in "${OS[@]}"; do emit_stage "$s"; done
  printf '</div>\n'
}

# 目標 → 照会の trace 表。 行 = 各目標項目 (emission 順 = stage seq 昇順・priority canonical 順)。
#   列 = 目標 (id・#rm-<id> リンク) / 段階 / 優先度 / 参照先 (VISION=方向 / SRS=要件 の code バッジ + 由来ラベル併記)。
emit_trace() {
  printf '<table data-component="roadmap-trace"><thead><tr><th>目標</th><th>段階</th><th>優先度</th><th>参照先 (方向 / 要件)</th></tr></thead><tbody>\n'
  local seq sel sid prio nitem i id fv fr
  for seq in "${OS[@]}"; do
    sel='.stages[] | select(.seq=='"$seq"')'; sid="$(q "$sel"' | .id')"
    for prio in "${PRIO_ORDER[@]}"; do
      nitem="$(q "$sel"' | .items.'"$prio"' // [] | length')"
      [[ "$nitem" -gt 0 ]] || continue
      for ((i=0; i<nitem; i++)); do
        id="$(q "$sel"' | .items.'"$prio"'['"$i"'] | .id')"
        printf '<tr data-component="trace-row"><td class="trc-id"><a href="#rm-%s">%s</a></td><td class="trc-stage">%s</td><td class="trc-prio">%s</td><td class="trc-ref">' \
          "$(esc "$id")" "$(esc "$id")" "$(esc "$sid")" "$(esc "${PRIO_LABEL[$prio]}")"
        local first=1
        while IFS= read -r fv; do [[ -n "$fv" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="trc-edge"><a class="trc-code trc-dir" href="%s#%s">%s</a> <span class="trc-label" data-vision-label-ref="%s">%s</span></span>' "$(esc "$VISION_HTML")" "$(esc "$fv")" "$(esc "$fv")" "$(esc "$fv")" "$(esc "${VISION_LABEL[$fv]}")"; done < <(q "$sel"' | .items.'"$prio"'['"$i"'] | .refs.vision // [] | .[]')
        while IFS= read -r fr; do [[ -n "$fr" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="trc-edge"><a class="trc-code trc-req" href="%s#%s">%s</a> <span class="trc-label" data-srs-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"; done < <(q "$sel"' | .items.'"$prio"'['"$i"'] | .refs.srs // [] | .[]')
        printf '</td></tr>\n'
      done
    done
  done
  printf '</tbody></table>\n'
}

emit_footer() {
  core_emit_footer '<span>folio design system</span><span>roadmap-pack</span><span>folio engine post-B6 (folio-8cha)</span><span>stage-keyed indexed + cross-doc 前方照会</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "直近の段階"                  "いちばん近い段階で何を目指すか"                    "$ICO_TARGET"; emit_highlights; band_end
  band brand  "段階ごとの目標"              "近い段階から順に、 何をどの優先度で目指すか"        "$ICO_FLAG";   emit_stages;    band_end
  band ok     "目標 → 照会のつながり"        "どの目標が、 どの機能方向 (VISION) / どの要件 (SRS) に向かうか"  "$ICO_LINK";   emit_trace;     band_end
  band violet "用語集 / この文書で使う専門語"  "本文に出てくる専門語のやさしい説明"                "$ICO_BOOK";   emit_glossary;  band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
# ★seq 昇順の決定的順序 (sort -n = 整数比較の決定的手段)。 段階順の SSoT (未来へ向かう昇順)。
mapfile -t OS < <(q '.stages[].seq' | sort -n)
# ★cross-doc 照会先の live 導出 (fabrication-free)。 validate() が VISION/SRS 実在 + 全 ref 実在を保証済。
VISION_REL="$(q '.cross_doc.vision_contract')"; VISION_ABS="${CONTRACT_DIR}/${VISION_REL}"
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
VISION_HTML="$(q '.cross_doc.vision_html')"; SRS_HTML="$(q '.cross_doc.srs_html')"
# ★VISION 方向ラベル = features[].name を verbatim / SRS 要件ラベル = requirements[].label を verbatim (fabrication-free)。
declare -A VISION_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && VISION_LABEL["$_id"]="$_lbl"; done < <(yq -r '.features[] | [.id, .name] | @tsv' "$VISION_ABS")
declare -A SRS_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && SRS_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
core_finalize "assemble-roadmap"
