#!/usr/bin/env bash
# folio engine post-B6 (folio-8ptq / c5r capability-census) — changelog-pack 決定的 assembler
#
# 入力 changelog contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# testcases / ADR generator と *同型* の機構を changelog-pack schema へ適用する:
#   - 内容・構造 (cover / 最新版ハイライト / version 別 entry 群 (Keep a Changelog categories) / 変更→参照 trace / glossary)
#     は contract から決定的組立。 元データに無い版・変更・照会 edge を生成できない。
#   - ★順序 = semver 降順を assembler が決定的に sort (sort -rV = 決定的手段・自作 parser の車輪再発明を避ける)。
#     contract の記載順に依存しない = 版順の乱れ/捏造は原理的に不可。 unreleased 節は opt-in (存在すれば先頭別枠)。
#   - ★cross-doc 後方照会 edge: 各変更項目の refs.srs[] (FR・role=claim) / refs.adr[] (ADR doc_id・role=rationale) が
#     参照先 SRS / ADR contract に実在することを validate() が *生成前に* fail-closed で確かめる (集合外参照は拒否)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・不正 semver・未知 category は拒否。
#   - prose スロット (章リード / cover 1 文サマリ / 最新版ハイライト) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# inject-prose.sh は SRS/ADR/testcases と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-changelog.sh <changelog-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-changelog.sh <changelog-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-changelog: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-changelog: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-changelog: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# ---- Keep a Changelog カテゴリ (canonical 順・label・class)。 空 category は省略・未知 category は validate で拒否。
#   ★assembler は *この固定 canonical 順* で category を反復する (contract のキー順に依存しない = 決定的)。
CAT_ORDER=(added changed deprecated removed fixed security)
declare -A CAT_LABEL=( [added]=追加 [changed]=変更 [deprecated]=非推奨 [removed]=削除 [fixed]=修正 [security]=セキュリティ )
declare -A CAT_CLASS=( [added]=add [changed]=chg [deprecated]=dep [removed]=rem [fixed]=fix [security]=sec )
declare -A CAT_OK=( [added]=1 [changed]=1 [deprecated]=1 [removed]=1 [fixed]=1 [security]=1 )

# 全変更項目 (unreleased + entries 横断・全 category flatten) の base 式。 順序・件数・id 突合の SSoT。
ITEMS_EXPR='[(.unreleased.categories // {} | .[][]), (.entries[].categories | .[][])]'

# ---- icon SVG (changelog-pack 固有。 共用 icon=ICO_BOOK/USER + ico() は lib/common.sh) ----
ICO_TAG='<path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/>'
ICO_LIST='<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>'
ICO_SPARK='<path d="M12 2v4m0 12v4m8-10h-4M6 12H2m14.5-6.5l-2.8 2.8M9.3 14.7l-2.8 2.8m11 0l-2.8-2.8M9.3 9.3L6.5 6.5"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p d
  core_validate_strings "assemble-changelog" || errs=1
  # 変更項目 id 一意性 (全 doc 横断)
  d="$(q "$ITEMS_EXPR | .[].id" | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-changelog: 変更項目 id 重複: $d" >&2; errs=1; }
  # version が semver (X.Y.Z) かつ一意
  local badver; badver="$(q '.entries[].version' | { grep -vE '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$badver" ]] || { echo "assemble-changelog: version が semver (X.Y.Z) でない: $badver" >&2; errs=1; }
  local dupver; dupver="$(q '.entries[].version' | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$dupver" ]] || { echo "assemble-changelog: version 重複: $dupver" >&2; errs=1; }
  [[ "$(q '.entries | length')" -ge 1 ]] || { echo "assemble-changelog: entries が空 (リリース済み版が 1 件以上必要)" >&2; errs=1; }
  # category キー ⊆ canonical (unreleased + entries)。 未知 category を拒否。
  local badcat; badcat="$(q '[(.unreleased.categories // {}), (.entries[].categories)] | .[] | keys | .[]' | sort -u \
    | while IFS= read -r k; do [[ -z "$k" || -v CAT_OK[$k] ]] || printf '%s ' "$k"; done)"
  [[ -z "$badcat" ]] || { echo "assemble-changelog: 未知の category: $badcat (added|changed|deprecated|removed|fixed|security)" >&2; errs=1; }
  # ★空 category (キーはあるが item 0) を拒否 (省略すべき = 「変更なし」の負の主張を空配列で偽装させない)。
  local emptycat; emptycat="$(q '[(.unreleased.categories // {}), (.entries[].categories)] | .[] | to_entries | .[] | select((.value | length) == 0) | .key' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  [[ -z "$emptycat" ]] || { echo "assemble-changelog: 空 category (item 0 のキー・省略すべき): $emptycat" >&2; errs=1; }
  # 各変更項目は refs.srs / refs.adr の少なくとも一方を 1 件以上持つ (照会なしの宙に浮いた変更を禁止)。
  local n_noref; n_noref="$(q "$ITEMS_EXPR | [.[] | select(((.refs.srs // []) | length) == 0 and ((.refs.adr // []) | length) == 0) | .id] | length")"
  [[ "$n_noref" == "0" ]] || { echo "assemble-changelog: refs 空の変更項目が $n_noref 件 (各項目は ADR か SRS FR の照会を 1 件以上持つ)" >&2; errs=1; }
  # ★空/null の ref を dangling 判定 (comm -23) が空行に畳んで素通すため明示拒否 (壊れた後方参照・ds8 idiom)。
  local n_srs n_srs_ne n_adr n_adr_ne
  n_srs="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[]] | length")"; n_srs_ne="$(q "$ITEMS_EXPR | [.[].refs.srs // [] | .[] | select((. // \"\") != \"\")] | length")"
  [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-changelog: ★空 SRS 照会 ref (有効 $n_srs_ne/$n_srs 件)" >&2; errs=1; }
  n_adr="$(q "$ITEMS_EXPR | [.[].refs.adr // [] | .[]] | length")"; n_adr_ne="$(q "$ITEMS_EXPR | [.[].refs.adr // [] | .[] | select((. // \"\") != \"\")] | length")"
  [[ "$n_adr" == "$n_adr_ne" ]] || { echo "assemble-changelog: ★空 ADR 照会 ref (有効 $n_adr_ne/$n_adr 件)" >&2; errs=1; }
  # ★edge-bearing graph の要請 (rolemap): SRS/ADR 双方に 1 件以上照会 (照会先ありで 0 件 = verify-graph vacuum guard FAIL)。
  [[ "$n_srs" -ge 1 ]] || { echo "assemble-changelog: SRS 照会が 0 件 (rolemap edge の照会先ありゆえ 1 件以上必要)" >&2; errs=1; }
  [[ "$n_adr" -ge 1 ]] || { echo "assemble-changelog: ADR 照会が 0 件 (rolemap edge の照会先ありゆえ 1 件以上必要)" >&2; errs=1; }
  # ★cross-doc 後方照会の終端解決: 参照先 SRS/ADR contract 実在 + refs の FR/ADR が実在
  local srs_rel srs_abs srs_docid adr_rel adr_abs adr_docid missing amissing
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-changelog: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"
    [[ "$srs_docid" == "$(q '.cross_doc.srs_doc_id')" ]] || { echo "assemble-changelog: cross_doc.srs_doc_id が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    missing="$(comm -23 <(q "$ITEMS_EXPR | .[].refs.srs // [] | .[]" | sort -u) <(yq -r '.requirements[].id' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-changelog: ★SRS 照会の dangling: refs.srs が SRS 要件に実在しない: $missing" >&2; errs=1; }
  fi
  adr_rel="$(q '.cross_doc.adr_contract')"; adr_abs="${CONTRACT_DIR}/${adr_rel}"
  if [[ ! -f "$adr_abs" ]]; then
    echo "assemble-changelog: cross_doc.adr_contract が見つからない: $adr_rel (照会先 ADR 不在)" >&2; errs=1
  else
    adr_docid="$(yq -r '.meta.doc_id' "$adr_abs")"
    [[ "$adr_docid" == "$(q '.cross_doc.adr_doc_id')" ]] || { echo "assemble-changelog: cross_doc.adr_doc_id が ADR contract の doc_id ($adr_docid) と不一致" >&2; errs=1; }
    amissing="$(comm -23 <(q "$ITEMS_EXPR | .[].refs.adr // [] | .[]" | sort -u) <(yq -r '.meta.doc_id' "$adr_abs" | sort -u))"
    [[ -z "$amissing" ]] || { echo "assemble-changelog: ★ADR 照会の dangling: refs.adr が ADR doc_id でない: $amissing" >&2; errs=1; }
  fi
  core_validate_glossary_substring "assemble-changelog" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-changelog: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- changelog-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_changelog_css() {
  cat <<'CSS'
/* ===== changelog-pack 固有部品 (folio-8ptq)。 srs.css の token を流用 ===== */
[data-component="changelog-highlights"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow);margin:10px 0}
.hl-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:6px}
.hl-head .hl-ver{font-weight:800;font-size:17px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand-line);border-radius:7px;padding:2px 11px}
.hl-head .hl-date{font-size:12.5px;color:var(--ink-faint)}
.hl-head .hl-tag{font-size:11px;font-weight:700;color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:999px;padding:2px 10px}
[data-component="changelog-highlights"] .hl-summary{display:block;margin:0 0 10px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px;line-height:1.7}
.hl-counts{display:flex;flex-wrap:wrap;gap:8px}
.hl-count{display:inline-flex;align-items:center;gap:6px;font-size:12px;border:1px solid var(--line);border-radius:7px;padding:3px 10px;background:var(--paper-2)}
.hl-count .hlc-label{font-weight:700;color:var(--ink-soft)}
.hl-count .hlc-n{font-weight:800;font-size:13px;color:var(--ink-soft);background:var(--paper-3);border-radius:5px;padding:0 7px}
.hl-count.add .hlc-label{color:var(--ok)} .hl-count.chg .hlc-label{color:var(--brand)} .hl-count.dep .hlc-label{color:var(--warn)}
.hl-count.rem .hlc-label{color:var(--violet)} .hl-count.fix .hlc-label{color:var(--info)} .hl-count.sec .hlc-label{color:var(--bad)}
.cl-entries{display:flex;flex-direction:column;gap:16px;margin:10px 0}
[data-component="changelog-entry"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
.cl-ver-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap;margin-bottom:8px;padding-bottom:7px;border-bottom:1px solid var(--line)}
.cl-ver-head .cl-ver-badge{font-weight:800;font-size:16px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand-line);border-radius:7px;padding:2px 11px}
.cl-ver-head .cl-ver-badge.unreleased{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.cl-ver-head .cl-ver-date{font-size:12.5px;color:var(--ink-faint)}
.cl-cats{display:flex;flex-direction:column;gap:11px}
.cl-cat-head{display:flex;align-items:center;gap:8px;margin-bottom:4px}
.cl-cat .cl-cat-label{font-size:12px;font-weight:700;border-radius:999px;padding:2px 11px;border:1px solid}
.cl-cat.add .cl-cat-label{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.cl-cat.chg .cl-cat-label{color:var(--brand);background:var(--brand-tint);border-color:var(--brand-line)}
.cl-cat.dep .cl-cat-label{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
.cl-cat.rem .cl-cat-label{color:var(--violet);background:var(--violet-tint);border-color:var(--violet-line)}
.cl-cat.fix .cl-cat-label{color:var(--info);background:var(--info-tint,var(--paper-3));border-color:var(--line)}
.cl-cat.sec .cl-cat-label{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.cl-items{margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:8px}
[data-component="changelog-item"]{border:1px solid var(--line);border-radius:9px;padding:9px 12px;background:var(--paper-2)}
[data-component="changelog-item"] .cl-id{font-size:10.5px;font-weight:800;color:var(--ink-faint);margin-right:6px}
[data-component="changelog-item"] .cl-text{margin:0;font-size:13.5px;line-height:1.7;color:var(--ink)}
[data-component="changelog-item"] .cl-plain{display:block;margin:6px 0 0;font-size:12.5px;color:var(--ink-soft);background:var(--brand-tint);border-radius:6px;padding:5px 9px;line-height:1.7}
.cl-refs{margin:7px 0 0;display:flex;flex-direction:column;gap:4px}
.cl-ref-row{display:flex;gap:7px;align-items:baseline;flex-wrap:wrap}
.cl-ref-row .cl-ref-k{flex:0 0 auto;font-size:11px;font-weight:700;color:var(--ink-faint)}
.cl-ref-row.why .cl-ref-k{color:var(--brand)} .cl-ref-row.req .cl-ref-k{color:var(--ok)}
a.cl-ref{display:inline-flex;align-items:baseline;gap:5px;text-decoration:none;margin-right:5px}
.cl-ref .xref-code{font-weight:800;font-size:11.5px;border-radius:6px;padding:1px 8px;border:1px solid}
.cl-ref-row.why .xref-code{color:var(--brand);background:var(--brand-tint);border-color:var(--brand-line)}
.cl-ref-row.req .xref-code{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.cl-ref .cl-ref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
table[data-component="changelog-trace"]{width:100%;border-collapse:collapse;margin:8px 0;font-size:13px}
[data-component="changelog-trace"] th,[data-component="changelog-trace"] td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
[data-component="changelog-trace"] thead th{background:var(--paper-3);font-size:11.5px;color:var(--ink-soft);letter-spacing:.02em}
[data-component="changelog-trace"] .trc-id{font-weight:800;color:var(--ink-soft);white-space:nowrap}
[data-component="changelog-trace"] .trc-ver{white-space:nowrap;font-size:12px;color:var(--ink-faint)}
[data-component="changelog-trace"] .trc-cat{white-space:nowrap;font-size:12px}
[data-component="changelog-trace"] .trc-ref{font-size:12px;line-height:1.7}
[data-component="changelog-trace"] .trc-edge{display:inline}
[data-component="changelog-trace"] .trc-code{font-size:11px;font-weight:800}
[data-component="changelog-trace"] .trc-ref .trc-why{color:var(--brand)} [data-component="changelog-trace"] .trc-ref .trc-req{color:var(--ok)}
[data-component="changelog-trace"] .trc-label{font-weight:400;color:var(--ink-soft)}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="changelog">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio changelog-pack assembler (folio-8ptq) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_changelog_css
  printf '\n</style>\n'
  core_emit_graph_head
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "この変更履歴が約束すること (1 文サマリ)"
  local n_ent first last latest latest_date
  n_ent="$(q '.entries | length')"
  first="$(printf '%s\n' "${OV[@]}" | tail -1)"; last="${OV[0]}"; latest="${OV[0]}"
  latest_date="$(q '.entries[] | select(.version=="'"$latest"'") | .date')"
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">収録</span><span class="v">%s</span></span><span class="m"><span class="k">最新</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "changelog (変更履歴)" "$(esc "${n_ent} 版 (v${first}–v${last})")" "$(esc "v${latest} / ${latest_date}")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 後方照会の可視チップ (照会先 SRS / ADR)。 ADR と対称の 2-<b> テンプレ。
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の要件 / <b>%s</b>の判断</div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.cross_doc.adr_doc_id')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# 最新版 (semver 降順の先頭 = OV[0]) のハイライト。 6 category の件数 (0 含む = 負の主張「この種別の変更なし」) を
#   contract から決定的に emit する。 highlight 散文は prose スロット。
emit_highlights() {
  local latest="${OV[0]}" latest_date cat n
  latest_date="$(q '.entries[] | select(.version=="'"$latest"'") | .date')"
  printf '<div data-component="changelog-highlights">\n'
  printf '<div class="hl-head"><span class="hl-ver">v%s</span><span class="hl-date">%s</span><span class="hl-tag">最新版</span></div>\n' "$(esc "$latest")" "$(esc "$latest_date")"
  printf '<p class="hl-summary" data-prose-slot="highlight" data-slot-id="latest-highlight"></p>\n'
  printf '<div class="hl-counts">\n'
  for cat in "${CAT_ORDER[@]}"; do
    n="$(q '.entries[] | select(.version=="'"$latest"'") | .categories.'"$cat"' // [] | length')"
    printf '<span class="hl-count %s"><span class="hlc-label">%s</span><span class="hlc-n">%s</span></span>\n' \
      "${CAT_CLASS[$cat]}" "$(esc "${CAT_LABEL[$cat]}")" "$(esc "$n")"
  done
  printf '</div>\n</div>\n'
}

# 1 変更項目カード (id=cl-<id>)。 text (mark_terms) + refs (ADR=なぜ / SRS=要件) を emit。
emit_item() {
  local base="$1" id text nadr nsrs
  id="$(yq -r "$base"' | .id' "$CONTRACT")"
  text="$(yq -r "$base"' | .text' "$CONTRACT")"
  nadr="$(yq -r "$base"' | .refs.adr // [] | length' "$CONTRACT")"
  nsrs="$(yq -r "$base"' | .refs.srs // [] | length' "$CONTRACT")"
  printf '<li data-component="changelog-item" id="cl-%s"><p class="cl-text"><span class="cl-id">%s</span>%s</p>\n' "$(esc "$id")" "$(esc "$id")" "$(mark_terms "$text")"
  printf '<p class="cl-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$id")"
  printf '<div class="cl-refs">\n'
  if [[ "$nadr" -gt 0 ]]; then
    printf '<div class="cl-ref-row why"><span class="cl-ref-k">なぜ</span>'
    while IFS= read -r ar; do [[ -n "$ar" ]] || continue; printf '<a class="cl-ref" href="%s#decision" data-cl-adr-ref="%s" data-cl-adr-role="rationale"><span class="xref-code">%s</span><span class="cl-ref-label" data-adr-label-ref="%s">%s</span></a>' \
      "$(esc "$ADR_HTML")" "$(esc "$ar")" "$(esc "$ar")" "$(esc "$ar")" "$(esc "$ADR_TITLE")"; done < <(yq -r "$base"' | .refs.adr // [] | .[]' "$CONTRACT")
    printf '</div>\n'
  fi
  if [[ "$nsrs" -gt 0 ]]; then
    printf '<div class="cl-ref-row req"><span class="cl-ref-k">要件</span>'
    while IFS= read -r fr; do [[ -n "$fr" ]] || continue; printf '<a class="cl-ref" href="%s#%s" data-cl-srs-ref="%s" data-cl-srs-role="claim"><span class="xref-code">%s</span><span class="cl-ref-label" data-srs-label-ref="%s">%s</span></a>' \
      "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"; done < <(yq -r "$base"' | .refs.srs // [] | .[]' "$CONTRACT")
    printf '</div>\n'
  fi
  printf '</div>\n</li>\n'
}

# 1 版 (または unreleased) のカード。 $1 = "unreleased" | version。 category は canonical 順・present+nonempty のみ。
emit_entry() {
  local key="$1" sel badge bcls vdate cat nitem i
  if [[ "$key" == "unreleased" ]]; then
    sel='.unreleased'; badge="未リリース"; bcls=" unreleased"; vdate="次リリース予定"
    printf '<div data-component="changelog-entry" id="ver-unreleased">\n'
  else
    sel='.entries[] | select(.version=="'"$key"'")'; badge="v$key"; bcls=""
    vdate="$(q "$sel"' | .date')"
    printf '<div data-component="changelog-entry" id="ver-%s">\n' "$(esc "$key")"
  fi
  printf '<div class="cl-ver-head"><span class="cl-ver-badge%s">%s</span><span class="cl-ver-date">%s</span></div>\n' "$bcls" "$(esc "$badge")" "$(esc "$vdate")"
  printf '<div class="cl-cats">\n'
  for cat in "${CAT_ORDER[@]}"; do
    nitem="$(q "$sel"' | .categories.'"$cat"' // [] | length')"
    [[ "$nitem" -gt 0 ]] || continue
    printf '<div class="cl-cat %s"><div class="cl-cat-head"><span class="cl-cat-label">%s</span></div>\n' "${CAT_CLASS[$cat]}" "$(esc "${CAT_LABEL[$cat]}")"
    printf '<ul class="cl-items">\n'
    for ((i=0; i<nitem; i++)); do
      emit_item "$sel"' | .categories.'"$cat"'['"$i"']'
    done
    printf '</ul></div>\n'
  done
  printf '</div>\n</div>\n'
}

emit_entries() {
  printf '<div class="cl-entries">\n'
  [[ "$HAS_UNREL" == "true" ]] && emit_entry "unreleased"
  local v
  for v in "${OV[@]}"; do emit_entry "$v"; done
  printf '</div>\n'
}

# 変更 → 参照の trace 表。 行 = 各変更項目 (emission 順 = unreleased→版 semver 降順・category canonical 順)。
#   列 = 変更 (id・#cl-<id> リンク) / 版 / 区分 / 参照先 (ADR=なぜ / SRS=要件 の code バッジ + 由来ラベル併記)。
emit_trace() {
  printf '<table data-component="changelog-trace"><thead><tr><th>変更</th><th>版</th><th>区分</th><th>参照先 (なぜ / 要件)</th></tr></thead><tbody>\n'
  local key vlabel base id cat nitem i ar fr
  for key in "${TRACE_KEYS[@]}"; do
    if [[ "$key" == "unreleased" ]]; then base='.unreleased'; vlabel="未リリース"; else base='.entries[] | select(.version=="'"$key"'")'; vlabel="v$key"; fi
    for cat in "${CAT_ORDER[@]}"; do
      nitem="$(q "$base"' | .categories.'"$cat"' // [] | length')"
      [[ "$nitem" -gt 0 ]] || continue
      for ((i=0; i<nitem; i++)); do
        id="$(q "$base"' | .categories.'"$cat"'['"$i"'] | .id')"
        printf '<tr data-component="trace-row"><td class="trc-id"><a href="#cl-%s">%s</a></td><td class="trc-ver">%s</td><td class="trc-cat">%s</td><td class="trc-ref">' \
          "$(esc "$id")" "$(esc "$id")" "$(esc "$vlabel")" "$(esc "${CAT_LABEL[$cat]}")"
        local first=1
        while IFS= read -r ar; do [[ -n "$ar" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="trc-edge"><a class="trc-code trc-why" href="%s#decision">%s</a> <span class="trc-label" data-adr-label-ref="%s">%s</span></span>' "$(esc "$ADR_HTML")" "$(esc "$ar")" "$(esc "$ar")" "$(esc "$ADR_TITLE")"; done < <(q "$base"' | .categories.'"$cat"'['"$i"'] | .refs.adr // [] | .[]')
        while IFS= read -r fr; do [[ -n "$fr" ]] || continue; [[ "$first" -eq 1 ]] || printf '、'; first=0; printf '<span class="trc-edge"><a class="trc-code trc-req" href="%s#%s">%s</a> <span class="trc-label" data-srs-label-ref="%s">%s</span></span>' "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"; done < <(q "$base"' | .categories.'"$cat"'['"$i"'] | .refs.srs // [] | .[]')
        printf '</td></tr>\n'
      done
    done
  done
  printf '</tbody></table>\n'
}

emit_footer() {
  core_emit_footer '<span>folio design system</span><span>changelog-pack</span><span>folio engine post-B6 (folio-8ptq)</span><span>version-keyed indexed + cross-doc 後方照会</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "最新版のハイライト"          "いちばん新しい版で何が変わったか"                  "$ICO_SPARK"; emit_highlights; band_end
  band brand  "版ごとの変更"                "新しい版から順に、 追加・変更・修正を並べる"        "$ICO_LIST";  emit_entries;   band_end
  band ok     "変更 → 参照のつながり"        "どの変更が、 なぜ (ADR) / どの要件 (SRS) のためか"  "$ICO_LINK";  emit_trace;     band_end
  band violet "用語集 / この文書で使う専門語"  "本文に出てくる専門語のやさしい説明"                "$ICO_BOOK";  emit_glossary;  band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
# ★semver 降順の決定的順序 (sort -rV = version 比較の決定的手段・自作 parser を避ける)。 版順の SSoT。
mapfile -t OV < <(q '.entries[].version' | sort -rV)
HAS_UNREL="$(q 'has("unreleased")')"
# trace / entry の emission key 順 (unreleased 先頭 + 版 semver 降順)。
TRACE_KEYS=()
[[ "$HAS_UNREL" == "true" ]] && TRACE_KEYS+=("unreleased")
TRACE_KEYS+=("${OV[@]}")
# ★cross-doc 照会先の live 導出 (fabrication-free)。 validate() が SRS/ADR 実在 + 全 ref 実在を保証済。
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
ADR_REL="$(q '.cross_doc.adr_contract')"; ADR_ABS="${CONTRACT_DIR}/${ADR_REL}"
SRS_HTML="$(q '.cross_doc.srs_html')"; ADR_HTML="$(q '.cross_doc.adr_html')"
# ★ADR ラベル = 「ADR: <参照先 ADR の実 .meta.title>」 live-mirror (folio-c5r.13・手書き title 廃止=retitle drift 防止)。
ADR_TITLE="ADR: $(yq -r '.meta.title' "$ADR_ABS")"
# ★SRS FR ラベル = requirements[].label を verbatim (fabrication-free)。 validate() が全 srs ref 実在を保証済。
declare -A SRS_LABEL
while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && SRS_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
core_finalize "assemble-changelog"
