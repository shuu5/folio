#!/usr/bin/env bash
# folio engine B4 (folio-igv) — principle-pack 決定的 assembler (instance#4 / rule-of-three 追試)
#
# 入力 principle contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS (assemble-srs.sh) / ADR (assemble-adr.sh) / research (assemble-research.sh) と *同型* の機構を
# principle-pack schema (principles / versioning / amendment / inbound) へ適用する:
#   - 内容・構造は contract から決定的組立。 元データに無い原則・tier・amendment edge を生成できない。
#   - ★終端強制 (生成前 fail-closed): principle は前方照会を持たない。 principle に許可外キー
#     (leads_to/justifies 等の前方照会) があれば abort / top-level に cross_doc/outcome があれば abort。
#   - ★inbound (受ける照会のみ): inbound.ref が principles[].id に実在し role が抽象 allowlist 内であることを生成前確認。
#   - 全自由記述値は HTML escape してから注入。 id 重複・tab/改行・未知 tier/role は拒否。
#   - prose スロット (章リード / plain / 1 文サマリ) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# ★B4 の合格条件 = lib/ (core) を 1 バイトも変えず純粋 pack として挿さること (rule-of-three 止め時判定)。
# inject-prose.sh も SRS/ADR/research と無改変共用 (data-slot-id ベースで pack 非依存)。
#
# usage: assemble-principle.sh <principle-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-principle.sh <principle-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-principle: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-principle: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-principle: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
# B2 (folio-5ua): SRS/ADR/research-pack と共通の idiom は lib/common.sh から source。 本 file は principle-pack 固有
# (終端強制 / inbound / principles emitter / versioning / amendment) を残す。
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# tier allowlist + 表示ラベル (verify-principle.sh と二重保守 = detect↔remediate parity)。
declare -A TIER_OK=( [Always]=1 [Ask-first]=1 [Never]=1 )
declare -A TIER_LABEL=( [Always]="いつも守る (例外なし)" [Ask-first]="変える前に確認" [Never]="絶対にやらない" )
declare -A TIER_CLASS=( [Always]="tier-always" [Ask-first]="tier-askfirst" [Never]="tier-never" )
# 抽象ロール (B0 论点2 照会 graph)。 inbound (受ける照会) の role allowlist。 verify-common.sh の CROSS_DOC_ROLE_ALLOWLIST と一致。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
# principle に許可するキー (これ以外 = 前方照会の疑い → 終端不変条件 違反で abort)。
PRINCIPLE_KEY_ALLOW='id|heading|statement|tier|amended_by'

# ---- icon SVG (principle-pack 固有。 共用 icon=ICO_FLOW/SHIELD/BOOK/CHECK_BIG/USER + ico() は lib/common.sh) ----
ICO_ALWAYS='<path d="M12 2v20"/><path d="M2 12h20"/><circle cx="12" cy="12" r="9"/>'
ICO_ASK='<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.8.5-1 .9-1 1.7"/><path d="M12 17h.01"/>'
ICO_NEVER='<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>'
ICO_VERSION='<path d="M3 7h18"/><path d="M3 12h18"/><path d="M3 17h18"/><circle cx="7" cy="7" r="1.4"/><circle cx="13" cy="12" r="1.4"/><circle cx="9" cy="17" r="1.4"/>'
ICO_AMEND='<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>'
ICO_INBOUND='<path d="M20 12H6"/><path d="M11 18l-6-6 6-6"/><circle cx="21" cy="12" r="1.5"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 d p
  core_validate_strings "assemble-principle" || errs=1
  # ★doc_type 束縛 (fail-open 封鎖・cell-quality critical): 本 pack は constitution 専用 assembler。 doc_type が
  #   constitution 以外なら abort。 doc_type を生成段で必須化することで、 doc_type flip により verify-principle.sh の
  #   baseline-diff / inbound gate (どちらも doc_type:constitution で起動) を bypass する経路を生成段でも塞ぐ。
  [[ "$(q '.meta.doc_type')" == "constitution" ]] || { echo "assemble-principle: ★meta.doc_type は constitution 必須 (principle-pack は constitution 専用・doc_type flip で gate bypass 不可)" >&2; errs=1; }
  # id 一意性 (principles)
  d="$(q '.principles[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-principle: principle id 重複: $d" >&2; errs=1; }
  # tier allowlist
  for p in $(q '.principles[].tier'); do [[ -v TIER_OK[$p] ]] || { echo "assemble-principle: 未知の tier: $p (Always|Ask-first|Never)" >&2; errs=1; }; done
  # ★終端強制 (照会終端 不変条件・B0 论点4): principle は前方照会を持たない。
  #   (a) principle-level の許可外キー (leads_to/justifies/cross_doc/refines/depends_on 等) は前方照会の疑い → abort。
  local badkeys
  badkeys="$(q '.principles[] | keys | .[]' | sort -u | grep -vxE "$PRINCIPLE_KEY_ALLOW" || true)"
  [[ -z "$badkeys" ]] || { echo "assemble-principle: ★principle に許可外キー (前方照会の疑い・終端不変条件 違反): $(echo $badkeys)" >&2; errs=1; }
  #   (b) top-level の前方照会 section (cross_doc/outcome = research/ADR の前方照会形) は principle pack では禁止。
  local fk
  for fk in cross_doc outcome; do
    [[ "$(q "has(\"$fk\")")" == "true" ]] && { echo "assemble-principle: ★top-level に前方照会 section '$fk' (principle pack は照会終端ゆえ禁止)" >&2; errs=1; }
  done
  # ★inbound (受ける照会のみ): ref が principles[].id に実在 + role allowlist + 空 ref 禁止。
  if [[ "$(q 'has("inbound")')" == "true" ]]; then
    for p in $(q '.inbound[].role'); do [[ -v ROLE_OK[$p] ]] || { echo "assemble-principle: 未知の inbound role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done
    local n_ib n_ibne missing_ib
    n_ib="$(q '.inbound | length')"; n_ibne="$(q '[.inbound[] | select((.ref // "") != "")] | length')"
    [[ "$n_ib" == "$n_ibne" ]] || { echo "assemble-principle: ★inbound に空 ref ($n_ibne/$n_ib 件・空 ref は壊れた照会ゆえ禁止)" >&2; errs=1; }
    missing_ib="$(comm -23 <(q '.inbound[].ref' | sort -u) <(q '.principles[].id' | sort -u))"
    [[ -z "$missing_ib" ]] || { echo "assemble-principle: ★inbound dangling: inbound.ref が principles に実在しない (phantom): $(echo $missing_ib)" >&2; errs=1; }
  fi
  # ★amended_by の adr が decisions dir に実在 (照会先 ADR の実在 = baseline-diff gate と同根)。
  if [[ "$(q 'has("decisions_dir")')" == "true" ]]; then
    local dec_rel dec_abs adr
    dec_rel="$(q '.decisions_dir')"
    if [[ "$dec_rel" == /* ]]; then dec_abs="$dec_rel"; else dec_abs="${CONTRACT_DIR}/${dec_rel}"; fi
    if [[ -d "$dec_abs" ]]; then
      for adr in $(q '.principles[].amended_by[]?.adr' | sort -u); do
        [[ -n "$adr" ]] || continue
        compgen -G "${dec_abs}/${adr}-*.html" >/dev/null 2>&1 || { echo "assemble-principle: ★amended_by の照会先 ADR が実在しない: $adr (decisions_dir に ${adr}-*.html 無し)" >&2; errs=1; }
      done
    else
      echo "assemble-principle: decisions_dir が見つからない: $dec_rel (amended_by 実在確認不能)" >&2; errs=1
    fi
  fi
  core_validate_glossary_substring "assemble-principle" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-principle: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# band / band_end (chapter-deck-band) は lib/common.sh (core) を使う。

# ---- principle 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_principle_css() {
  cat <<'CSS'
/* ===== principle-pack 固有部品 (folio-igv / instance#4)。 srs.css の token を流用 ===== */
.pr-list{display:flex;flex-direction:column;gap:13px;margin:10px 0}
[data-component="principle-row"]{border:1px solid var(--line);border-left:3px solid var(--brand);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
[data-component="principle-row"].tier-always{border-left-color:var(--ok)}
[data-component="principle-row"].tier-askfirst{border-left-color:var(--warn)}
[data-component="principle-row"].tier-never{border-left-color:var(--bad)}
.p-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:5px}
.p-head .pid{flex:0 0 auto;font-weight:700;font-size:12px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:6px;padding:2px 9px;letter-spacing:.02em}
.p-head .ph{font-weight:800;font-size:15.5px;margin:0}
[data-component="principle-tier-badge"]{margin-left:auto;display:inline-flex;align-items:center;gap:5px;font-size:11px;font-weight:800;letter-spacing:.03em;border-radius:999px;padding:2px 11px;white-space:nowrap}
[data-component="principle-tier-badge"].tier-always{color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line)}
[data-component="principle-tier-badge"].tier-askfirst{color:var(--warn);background:var(--warn-tint);border:1px solid var(--warn-line)}
[data-component="principle-tier-badge"].tier-never{color:var(--bad);background:var(--bad-tint);border:1px solid var(--bad-line)}
[data-component="principle-row"] .pst{margin:2px 0 9px;color:var(--ink);font-size:13.5px;line-height:1.75}
[data-component="principle-row"] .p-plain{display:block;margin:0 0 9px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px}
[data-component="principle-amendment-history"]{display:flex;gap:8px;align-items:center;flex-wrap:wrap;font-size:12px;border-top:1px dashed var(--line);padding-top:8px;margin-top:2px}
[data-component="principle-amendment-history"] .am-kick{font-size:10.5px;font-weight:800;letter-spacing:.04em;color:var(--ink-faint);text-transform:uppercase}
[data-component="principle-amendment-history"] .am-row{display:inline-flex;align-items:center;gap:5px;font-weight:700;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:999px;padding:2px 10px}
[data-component="principle-amendment-history"] .am-row .am-meta{font-weight:600;color:var(--ink-faint)}
[data-component="versioning-policy-table"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper-2);margin:8px 0}
[data-component="versioning-policy-table"] .vp-basis{margin:0 0 9px;font-size:13.5px;color:var(--ink)}
[data-component="versioning-policy-table"] table{width:100%;border-collapse:collapse;font-size:13px}
[data-component="versioning-policy-table"] th{text-align:left;padding:6px 10px;background:var(--brand-tint);border:1px solid var(--line);font-size:11.5px;letter-spacing:.03em;color:var(--ink-soft)}
[data-component="versioning-policy-table"] td{padding:6px 10px;border:1px solid var(--line);line-height:1.6}
[data-component="versioning-policy-table"] .vp-bump{font-weight:800;color:var(--brand);white-space:nowrap}
[data-component="versioning-policy-table"] .vp-note{margin:9px 0 0;font-size:12.5px;color:var(--ink-soft);background:var(--paper);border:1px solid var(--line);border-radius:8px;padding:7px 11px;line-height:1.7}
[data-component="versioning-policy-table"] .vp-plain{display:block;margin:9px 0 0;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px}
[data-component="amendment-procedure-steps"]{border:1px solid var(--line);border-radius:12px;padding:14px 18px;background:var(--paper);margin:8px 0}
[data-component="amendment-procedure-steps"] ol{margin:0;padding-left:22px}
[data-component="amendment-procedure-steps"] li{margin:5px 0;font-size:13.5px;color:var(--ink);line-height:1.7}
[data-component="amendment-procedure-steps"] .amp-plain{display:block;margin:10px 0 0;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px}
.ib-grid{display:flex;flex-direction:column;gap:9px;margin:8px 0}
[data-component="principle-inbound-chip"]{display:flex;gap:9px;align-items:center;flex-wrap:wrap;border:1px solid var(--info-line);border-left:3px solid var(--info);border-radius:10px;padding:9px 14px;background:var(--info-tint);font-size:13px}
[data-component="principle-inbound-chip"] .ib-from{font-weight:700;color:var(--ink)}
[data-component="principle-inbound-chip"] .ib-arrow{color:var(--info);font-weight:800}
[data-component="principle-inbound-chip"] .ib-ref{font-weight:700;color:var(--info)}
[data-component="principle-inbound-chip"] .ib-role{margin-left:auto;font-size:11px;font-weight:700;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:999px;padding:1px 10px;white-space:nowrap}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio principle-pack assembler (folio-igv / instance#4) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_principle_css
  printf '\n</style>\n</head>\n<body>\n'
}

# 各 tier の件数を決定的に算出 (cover-meta 内訳・verify と二重保守)。
tier_count() { q '[.principles[] | select(.tier=="'"$1"'")] | length'; }

emit_cover() {
  core_emit_cover_head "この憲法が約束すること (1 文サマリ)"
  local nprin namend
  nprin="$(q '.principles | length')"
  # ★非空 amended_by を持つ原則数 (empty amended_by:[] は「改訂来歴なし」として扱う = verify と整合・cell-quality minor)。
  namend="$(q '[.principles[] | select((.amended_by // []) | length > 0)] | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">原則の総数</span><span class="v">%s 件</span></span><span class="m"><span class="k">tier 内訳</span><span class="v">Always %s / Ask-first %s / Never %s</span></span><span class="m"><span class="k">改訂来歴</span><span class="v">%s 件</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$nprin" "$(tier_count Always)" "$(tier_count Ask-first)" "$(tier_count Never)" "$namend" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# 1 つの principle row を emit ($1 = id)。
emit_principle_row() {
  local pid="$1" heading statement tier tlabel tclass namend
  heading="$(q '.principles[] | select(.id=="'"$pid"'") | .heading')"
  statement="$(q '.principles[] | select(.id=="'"$pid"'") | .statement')"
  tier="$(q '.principles[] | select(.id=="'"$pid"'") | .tier')"
  tlabel="${TIER_LABEL[$tier]:-$tier}"; tclass="${TIER_CLASS[$tier]:-tier-unknown}"
  printf '<div data-component="principle-row" class="%s">\n' "$tclass"
  printf '<div class="p-head"><span class="pid">%s</span><h3 class="ph">%s</h3><span data-component="principle-tier-badge" class="%s">%s</span></div>\n' \
    "$(esc "$pid")" "$(esc "$heading")" "$tclass" "$(esc "$tlabel")"
  printf '<p class="pst">%s</p>\n' "$(mark_terms "$statement")"
  printf '<span class="p-plain" data-prose-slot="plain" data-slot-id="plain-%s"></span>\n' "$(esc "$pid")"
  # 改訂来歴 (amended_by を持つ原則のみ・無ければ history ブロック自体を出さない)。
  namend="$(q '.principles[] | select(.id=="'"$pid"'") | (.amended_by // []) | length')"
  if [[ "$namend" -gt 0 ]]; then
    printf '<div data-component="principle-amendment-history"><span class="am-kick">改訂来歴</span>'
    q '.principles[] | select(.id=="'"$pid"'") | .amended_by[] | [.adr, .date, .approved_by] | @tsv' | while IFS=$'\t' read -r adr date by; do
      [[ -n "$adr" ]] || continue
      printf '<span class="am-row" data-amended-adr="%s"><b>%s</b> <span class="am-meta">(%s · %s)</span></span>' "$(esc "$adr")" "$(esc "$adr")" "$(esc "$date")" "$(esc "$by")"
    done
    printf '</div>\n'
  fi
  printf '</div>\n'
}

# 1 つの tier に属する principle を contract 配列順 (= 表示順) で emit。
emit_tier() {
  local tier="$1" pid
  printf '<div class="pr-list">\n'
  while IFS= read -r pid; do [[ -n "$pid" ]] && emit_principle_row "$pid"; done < <(q '.principles[] | select(.tier=="'"$tier"'") | .id')
  printf '</div>\n'
}

emit_versioning() {
  printf '<div data-component="versioning-policy-table">\n'
  printf '<p class="vp-basis">準拠: <b>%s</b></p>\n' "$(esc "$(q '.versioning.basis')")"
  printf '<table><thead><tr><th>bump</th><th>条件</th></tr></thead><tbody>\n'
  q '.versioning.rules[] | [.bump, .condition] | @tsv' | while IFS=$'\t' read -r bump cond; do
    [[ -n "$bump" ]] || continue
    printf '<tr><td class="vp-bump">%s</td><td class="vp-cond">%s</td></tr>\n' "$(esc "$bump")" "$(esc "$cond")"
  done
  printf '</tbody></table>\n'
  printf '<p class="vp-note">%s</p>\n' "$(esc "$(q '.versioning.note')")"
  printf '<span class="vp-plain" data-prose-slot="plain" data-slot-id="versioning-plain"></span>\n'
  printf '</div>\n'
}

emit_amendment() {
  printf '<div data-component="amendment-procedure-steps">\n<ol>\n'
  while IFS= read -r step; do [[ -n "$step" ]] && printf '<li>%s</li>\n' "$(esc "$step")"; done < <(q '.amendment.steps[]')
  printf '</ol>\n'
  printf '<span class="amp-plain" data-prose-slot="plain" data-slot-id="amendment-plain"></span>\n'
  printf '</div>\n'
}

emit_inbound() {
  printf '<div class="ib-grid">\n'
  # ★inbound チップ: ref / role を同一要素に固定属性で刻む (verify_cross_doc_refs が target=self で突合)。
  #   可視 id は <b>P-x</b> に出し、 data-inbound-ref と一致を verify が突合 (照会先 principle の偽装を捕捉)。
  q '.inbound[] | [.ref, .from, .role] | @tsv' | while IFS=$'\t' read -r ref from role; do
    [[ -n "$ref" ]] || continue
    printf '<div data-component="principle-inbound-chip" data-inbound-ref="%s" data-inbound-role="%s"><span class="ib-from">%s</span><span class="ib-arrow">\xe2\x86\x92</span><span class="ib-ref"><b>%s</b></span><span class="ib-role">%s</span></div>\n' \
      "$(esc "$ref")" "$(esc "$role")" "$(esc "$from")" "$(esc "$ref")" "$(esc "$role")"
  done
  printf '</div>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# footer は core_emit_footer に principle-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>principle-pack</span><span>folio engine B4 (instance#4)</span><span>照会終端 + baseline-diff</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band ok     "いつも守る原則 (Always)"        "例外なく常に守る 9 原則 — folio の土台"          "$ICO_ALWAYS";   emit_tier Always;     band_end
  band warn   "変える前に確認する原則 (Ask-first)" "user 承認を取ってから変えてよい 3 原則"        "$ICO_ASK";      emit_tier Ask-first;  band_end
  band bad    "絶対にやらない原則 (Never)"      "踏み越え禁止の 2 原則 — 守りの最後の線"          "$ICO_NEVER";    emit_tier Never;      band_end
  band brand  "版の上げ方 / Versioning"          "原則をどう変えると版がどう上がるか"              "$ICO_VERSION";  emit_versioning;      band_end
  band violet "原則を変える手順 / Amendment"      "変更を ADR と版に必ず残す 5 ステップ"            "$ICO_AMEND";    emit_amendment;       band_end
  band info   "この憲法を参照する文書 / inbound"  "原則は照会の終端 — 受ける照会だけをここに示す"  "$ICO_INBOUND";  emit_inbound;         band_end
  band brand  "用語集 / この文書で使う専門語"      "本文に出てくる専門語のやさしい説明"              "$ICO_BOOK";     emit_glossary;        band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-principle"
