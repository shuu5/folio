#!/usr/bin/env bash
# folio engine B6 (folio-8ct) — spec-pack 決定的 assembler (instance#5 / self-dogfood endgame)
#
# 入力 spec contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS (assemble-srs.sh) / ADR (assemble-adr.sh) / research (assemble-research.sh) / principle (assemble-principle.sh)
# と *同型* の機構を spec-pack schema (sections / requirements(EARS) / references(非終端 照会) / glossary) へ適用する:
#   - 内容・構造は contract から決定的組立。 元データに無い section・要件・照会・block を生成できない (fab-free by construction)。
#   - 全自由記述値は HTML escape してから注入。 id 重複・tab/改行・未知 EARS/role・集合外参照・★未対応 block type は
#     validate() が **fail-closed** で生成前に拒否 (silent drop 禁止)。
#   - prose スロット (cover-summary / 章リード chapter-lead-NN) は *空* で出力し ③ inject-prose.sh が充填。
#   - 内容 (section essence / 要件 essence・normative / 照会 / 用語) は全て contract = SSoT。 opus は読みの足場 prose のみ。
#
# ★rules の hallmark (principle 終端 / SRS RTM の *中間*): EARS 章立て規範文 + **非終端 照会** (前方 references を持つ)。
#   references[] は他文書 (constitution P-x / ADR / verification REQ-VER) への前方照会 = rolemap edge + external-ref で
#   graph に接続する (verify-graph.sh)。 inbound は受ける側 (principle pack が宣言済)。
#
# ★B6 の合格条件 = lib/ (core) を 1 バイトも変えず純粋 pack として挿さること (rule-of-three の B6 完成サイン)。
# inject-prose.sh も SRS/ADR/research/principle と無改変共用 (data-slot-id ベースで pack 非依存)。
#
# usage: assemble-spec.sh <spec-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-spec.sh <spec-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-spec: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-spec: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-spec: yq required" >&2; exit 1; }

# ---- core 共通層 (q/esc/ico/band/cover骨格/glossary/footer/finalize) ----
# B2 (folio-5ua): SRS/ADR/research/principle-pack と共通の idiom は lib/common.sh から source。 本 file は spec-pack 固有
# (sections/blocks emitter / requirements(EARS) / references(非終端 照会)) を残す。
# ★term-inline (mark_terms) は spec-pack では不使用 = rules の用語は plain_short(やさしい言い換え) を持たないため
#   (glossary は term + def のみ・rules.html の span.term[data-tooltip] 由来)。 ゆえ core_init_term_inline は呼ばない。
source "$SCRIPT_DIR/lib/common.sh"

# EARS pattern (canonical = rules.html の data-ears-pattern 値) → 表示 class / label (verify-spec.sh と二重保守 = detect↔remediate parity)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=恒常 [event-driven]=きっかけ [state-driven]=状態 [unwanted]=禁止 [optional]=機能 )
# 抽象ロール (B0 论点2 照会 graph)。 references (前方照会) の role allowlist。 verify-common.sh の CROSS_DOC_ROLE_ALLOWLIST と一致。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
# CSS tint allowlist (section.tint / band)。
declare -A TINT_OK=( [brand]=1 [violet]=1 [warn]=1 [info]=1 [ok]=1 [bad]=1 )
# 対応 block type (これ以外 = silent drop の疑い → fail-closed abort)。
BLOCK_TYPE_ALLOW='prose|note|list|code|table|mermaid|subhead|requirements'

# ---- icon SVG (spec-pack 固有 + 共用。 section index で循環選択する静的デザイン資産・contract 由来でない) ----
ICO_GUIDE='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_DIR='<path d="M3 7a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'
ICO_TAG='<path d="M20.6 13.4 13 21l-9-9V4h8z"/><circle cx="7.5" cy="7.5" r="1.2"/>'
ICO_CODE='<path d="M16 18l6-6-6-6"/><path d="M8 6l-6 6 6 6"/>'
ICO_DELTA='<path d="M12 3l9 16H3z"/>'
ICO_EARS='<path d="M4 12h4l3 8 4-16 3 8h2"/>'
ICO_LAYERS='<path d="M12 2 2 7l10 5 10-5z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>'
ICO_SCRIPT='<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>'
ICO_GAVEL='<path d="M14 13l-7 7"/><path d="M5 12l7-7 5 5-7 7z"/><path d="M16 3l5 5"/>'
ICO_EYE='<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>'
ICO_GRID='<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>'
ICO_ARROW='<path d="M5 12h14M12 5l7 7-7 7"/>'
SECT_ICONS=("$ICO_GUIDE" "$ICO_DIR" "$ICO_TAG" "$ICO_CODE" "$ICO_DELTA" "$ICO_EARS" "$ICO_LAYERS" "$ICO_SCRIPT" "$ICO_LINK" "$ICO_GAVEL" "$ICO_EYE" "$ICO_GRID")

# ---- fail-closed contract validation (普遍規律 = core_validate_strings、 spec 固有 = doc_type/EARS/role/tint/block/集合) ----
validate() {
  local errs=0 d p si bi nsec nblk btype
  core_validate_strings "assemble-spec" || errs=1
  # ★doc_type 束縛 (fail-open 封鎖): 本 pack は rules 専用 assembler。 doc_type が rules 以外なら abort。
  [[ "$(q '.meta.doc_type')" == "rules" ]] || { echo "assemble-spec: ★meta.doc_type は rules 必須 (spec-pack は rules 専用・doc_type flip で gate bypass 不可)" >&2; errs=1; }
  # 要件 id 一意性
  d="$(q '.requirements[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-spec: 要件 id 重複: $d" >&2; errs=1; }
  # section id 一意性
  d="$(q '.sections[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-spec: section id 重複: $d" >&2; errs=1; }
  # EARS pattern allowlist (★逐値判定: word-split に依存させない。 "ubiquitous unwanted" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する)。
  while IFS= read -r p; do [[ -v EARS_CLASS[$p] ]] || { echo "assemble-spec: 未知の EARS pattern: $p (ubiquitous|event-driven|state-driven|unwanted|optional)" >&2; errs=1; }; done < <(q '.requirements[].ears_pattern')
  # section tint allowlist (★逐値判定: 同上。 "brand violet" 等が band の class 属性へ stray token を注入する fail-open を封鎖)。
  while IFS= read -r p; do [[ -v TINT_OK[$p] ]] || { echo "assemble-spec: 未知の section tint (CSS allowlist 外): $p" >&2; errs=1; }; done < <(q '.sections[].tint')
  # ★block type allowlist (silent drop 禁止・fail-closed): 未対応 block type は捨てず abort する。
  nsec="$(q '.sections | length')"
  for ((si=0; si<nsec; si++)); do
    nblk="$(q ".sections[$si].blocks // [] | length")"
    for ((bi=0; bi<nblk; bi++)); do
      btype="$(q ".sections[$si].blocks[$bi].type")"
      printf '%s' "$btype" | grep -qxE "$BLOCK_TYPE_ALLOW" \
        || { echo "assemble-spec: ★未対応 block type '$btype' (section[$si] block[$bi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
    done
  done
  # ★要件 ↔ requirements block の集合一致 (孤立要件・二重参照・存在しない要件参照を生成前に拒否)。
  #   block で参照する全 id ⊆ requirements[].id (存在しない要件参照を拒否)
  d="$(comm -23 <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u) <(q '.requirements[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-spec: requirements block が未定義の要件を参照: $d" >&2; errs=1; }
  #   requirements[].id ⊆ block 参照集合 (どこにも配置されない孤立要件を拒否)
  d="$(comm -23 <(q '.requirements[].id' | sort -u) <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-spec: 配置先 block の無い孤立要件: $d" >&2; errs=1; }
  #   要件 id は block 全体で 1 回だけ参照 (二重配置を拒否 = 行数二重カウント防止)
  d="$(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort | uniq -d)"
  [[ -z "$d" ]] || { echo "assemble-spec: 要件が複数 block に重複配置: $d" >&2; errs=1; }
  # references role allowlist + 空 token 禁止
  # ★逐値判定 (EARS/tint と対称): word-split/glob に依存させない。 "claim rationale" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v ROLE_OK[$p] ]] || { echo "assemble-spec: 未知の reference role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done < <(q '.references[]?.role')
  if [[ "$(q 'has("references")')" == "true" ]]; then
    local n_ref n_refne
    n_ref="$(q '.references | length')"; n_refne="$(q '[.references[] | select((.token // "") != "")] | length')"
    [[ "$n_ref" == "$n_refne" ]] || { echo "assemble-spec: ★references に空 token ($n_refne/$n_ref 件・空照会 token は壊れた前方照会ゆえ禁止)" >&2; errs=1; }
  fi
  # ★graph.principle_edge (rules→constitution 終端 edge・非終端 照会の graph 接続)。
  if [[ "$(q '.graph | has("principle_edge")')" == "true" ]]; then
    p="$(q '.graph.principle_edge.role')"; [[ -v ROLE_OK[$p] ]] || { echo "assemble-spec: graph.principle_edge.role が allowlist 外: $p" >&2; errs=1; }
    d="$(q '.graph.principle_edge.target_doc_id')"; [[ -n "$d" && "$d" != "null" ]] || { echo "assemble-spec: graph.principle_edge.target_doc_id が空" >&2; errs=1; }
  fi
  [[ "$errs" -eq 0 ]] || { echo "assemble-spec: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# band / band_end (chapter-deck-band) は lib/common.sh (core) を使う。

# ---- spec-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_spec_css() {
  cat <<'CSS'
/* ===== spec-pack 固有部品 (folio-8ct / instance#5)。 srs.css の token を流用 ===== */
[data-component="section-essence-callout"]{border:1px solid var(--brand-line,var(--line));border-left:3px solid var(--brand);border-radius:10px;padding:11px 15px;background:var(--brand-tint);margin:4px 0 12px}
[data-component="section-essence-callout"] .sec-se{margin:0;font-size:13.5px;line-height:1.7;color:var(--ink)}
[data-component="spec-subhead"]{margin:14px 0 6px}
[data-component="spec-subhead"] h3{margin:0 0 3px;font-size:14.5px;font-weight:800;color:var(--ink)}
[data-component="spec-subhead"] .sub-se{margin:0;font-size:12.5px;line-height:1.65;color:var(--ink-soft);background:var(--paper-2);border-radius:7px;padding:6px 11px}
[data-component="spec-prose"]{margin:8px 0;font-size:13px;line-height:1.75;color:var(--ink-soft)}
[data-component="spec-note"]{border:1px solid var(--info-line);border-left:3px solid var(--info);border-radius:9px;padding:9px 14px;background:var(--info-tint);margin:8px 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
[data-component="spec-note"] p{margin:0}
ul[data-component="spec-list-block"]{margin:8px 0;padding-left:4px;list-style:none;display:flex;flex-direction:column;gap:5px}
ul[data-component="spec-list-block"] .lbi{position:relative;padding-left:18px;font-size:13px;line-height:1.7;color:var(--ink-soft)}
ul[data-component="spec-list-block"] .lbi::before{content:"●";position:absolute;left:0;color:var(--brand);font-size:9px;top:5px}
pre[data-component="spec-code"]{background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:11px 14px;overflow-x:auto;font-size:12px;line-height:1.6;margin:8px 0}
pre[data-component="spec-code"] code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--ink);white-space:pre}
[data-component="spec-table"]{width:100%;border-collapse:collapse;font-size:12.5px;margin:2px 0}
[data-component="spec-table"] caption{caption-side:top;text-align:left;font-size:11.5px;color:var(--ink-faint);padding:0 0 5px;font-weight:700}
[data-component="spec-table"] th{text-align:left;padding:6px 10px;background:var(--brand-tint);border:1px solid var(--line);font-size:11.5px;letter-spacing:.02em;color:var(--ink-soft)}
[data-component="spec-table"] td{padding:6px 10px;border:1px solid var(--line);line-height:1.6;color:var(--ink)}
figure[data-component="spec-diagram"]{margin:10px 0;border:1px solid var(--line);border-radius:10px;background:var(--paper-2);overflow:hidden}
figure[data-component="spec-diagram"] .mermaid-src{margin:0;padding:12px 15px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;line-height:1.55;white-space:pre;overflow-x:auto;color:var(--ink-soft);background:var(--paper-2)}
figure[data-component="spec-diagram"] figcaption{padding:7px 15px;font-size:11.5px;color:var(--ink-faint);border-top:1px dashed var(--line);background:var(--paper)}
.rq-list{display:flex;flex-direction:column;gap:10px;margin:8px 0}
[data-component="ears-requirement-row"]{border:1px solid var(--line);border-left:3px solid var(--brand);border-radius:11px;padding:11px 14px;background:var(--paper);box-shadow:var(--shadow)}
[data-component="ears-requirement-row"] .rq-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:5px}
[data-component="ears-requirement-row"] .rid{font-weight:800;font-size:12px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:6px;padding:2px 9px;letter-spacing:.02em}
[data-component="ears-badge"]{margin-left:auto;display:inline-flex;align-items:center;font-size:11px;font-weight:800;letter-spacing:.03em;border-radius:999px;padding:2px 11px;white-space:nowrap}
[data-component="ears-badge"].always{color:var(--brand);background:var(--brand-tint);border:1px solid var(--line)}
[data-component="ears-badge"].trigger{color:var(--info);background:var(--info-tint);border:1px solid var(--info-line)}
[data-component="ears-badge"].state{color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line)}
[data-component="ears-badge"].forbid{color:var(--bad);background:var(--bad-tint);border:1px solid var(--bad-line)}
[data-component="ears-badge"].option{color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line)}
[data-component="ears-requirement-row"] .rq-essence{margin:0 0 7px;font-size:13.5px;line-height:1.7;color:var(--ink)}
[data-component="ears-requirement-row"] .rq-norm{font-size:12px;border-top:1px dashed var(--line);padding-top:6px}
[data-component="ears-requirement-row"] .rq-norm summary{cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.04em;color:var(--ink-faint);text-transform:uppercase}
[data-component="ears-requirement-row"] .rq-stmt{margin:6px 0 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
.ref-grid{display:flex;flex-direction:column;gap:8px;margin:8px 0}
[data-component="cross-doc-ref-chip"]{display:flex;gap:9px;align-items:center;flex-wrap:wrap;border:1px solid var(--violet-line);border-left:3px solid var(--violet);border-radius:10px;padding:8px 13px;background:var(--violet-tint);font-size:12.5px}
[data-component="cross-doc-ref-chip"] .rf-token{font-weight:800;color:var(--violet)}
[data-component="cross-doc-ref-chip"] .rf-arrow{color:var(--violet);font-weight:800}
[data-component="cross-doc-ref-chip"] .rf-doc{font-weight:700;color:var(--ink)}
[data-component="cross-doc-ref-chip"] .rf-role{margin-left:auto;font-size:11px;font-weight:700;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:999px;padding:1px 10px;white-space:nowrap}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio spec-pack assembler (folio-8ct / instance#5) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_spec_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "この規約集が約束すること (1 文サマリ)"
  local nsec nreq ngl
  nsec="$(q '.sections | length')"; nreq="$(q '.requirements | length')"; ngl="$(q '.glossary | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">章の数</span><span class="v">%s 章</span></span><span class="m"><span class="k">規範要件</span><span class="v">%s 件 (EARS)</span></span><span class="m"><span class="k">用語</span><span class="v">%s 語</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$nsec" "$nreq" "$ngl" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# ---- block emitter (section[$si].blocks[$bi]) ----
emit_prose() { printf '<p data-component="spec-prose">%s</p>\n' "$(esc "$(q ".sections[$1].blocks[$2].text")")"; }
emit_note()  { printf '<div data-component="spec-note"><p>%s</p></div>\n' "$(esc "$(q ".sections[$1].blocks[$2].text")")"; }
emit_list() {
  printf '<ul data-component="spec-list-block">\n'
  while IFS= read -r item; do [[ -n "$item" ]] && printf '<li class="lbi">%s</li>\n' "$(esc "$item")"; done < <(q ".sections[$1].blocks[$2].items[]")
  printf '</ul>\n'
}
emit_code() {
  printf '<pre data-component="spec-code"><code>'
  local first=1
  while IFS= read -r line; do [[ "$first" -eq 1 ]] && first=0 || printf '\n'; printf '%s' "$(esc "$line")"; done < <(q ".sections[$1].blocks[$2].lines[]")
  printf '</code></pre>\n'
}
emit_table() {
  local si="$1" bi="$2" cap nrow ri c
  cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
  printf '<div class="tbl-wrap"><table data-component="spec-table">'
  [[ -n "$cap" && "$cap" != "null" ]] && printf '<caption>%s</caption>' "$(esc "$cap")"
  printf '<thead><tr>'
  while IFS= read -r h; do printf '<th>%s</th>' "$(esc "$h")"; done < <(q ".sections[$si].blocks[$bi].headers[]")
  printf '</tr></thead><tbody>\n'
  nrow="$(q ".sections[$si].blocks[$bi].rows | length")"
  for ((ri=0; ri<nrow; ri++)); do
    printf '<tr>'
    while IFS= read -r c; do printf '<td>%s</td>' "$(esc "$c")"; done < <(q ".sections[$si].blocks[$bi].rows[$ri][]")
    printf '</tr>\n'
  done
  printf '</tbody></table></div>\n'
}
emit_mermaid() {
  local si="$1" bi="$2"
  printf '<figure data-component="spec-diagram" class="diagram"><pre class="mermaid-src">'
  local first=1
  while IFS= read -r line; do [[ "$first" -eq 1 ]] && first=0 || printf '\n'; printf '%s' "$(esc "$line")"; done < <(q ".sections[$si].blocks[$bi].source_lines[]")
  printf '</pre><figcaption>%s</figcaption></figure>\n' "$(esc "$(q ".sections[$si].blocks[$bi].caption // \"\"")")"
}
emit_subhead() {
  printf '<div data-component="spec-subhead"><h3>%s</h3><p class="sub-se">%s</p></div>\n' \
    "$(esc "$(q ".sections[$1].blocks[$2].heading")")" "$(esc "$(q ".sections[$1].blocks[$2].essence")")"
}
# 1 要件 row を emit ($1 = 要件 id)。
emit_requirement_row() {
  local id="$1" pat essence stmt class label
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  essence="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # validate() が ears_pattern を allowlist 逐値判定済 = ここは到達不能であるべき。 :-unknown silent fallback でなく
  # hard error 化し、 万一 validate を擦り抜けた未知 pattern が無スタイル class="unknown" badge として silent emit されるのを封鎖。
  [[ -v EARS_CLASS[$pat] ]] || { echo "assemble-spec: ★到達不能: emit 時に未知 EARS pattern '$pat' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
  class="${EARS_CLASS[$pat]}"; label="${EARS_LABEL[$pat]}"
  printf '<div data-component="ears-requirement-row" data-req-id="%s" data-ears-pattern="%s">\n' "$(esc "$id")" "$(esc "$pat")"
  printf '<div class="rq-head"><span class="rid">%s</span><span data-component="ears-badge" class="%s">%s</span></div>\n' "$(esc "$id")" "$class" "$(esc "$label")"
  printf '<p class="rq-essence">%s</p>\n' "$(esc "$essence")"
  printf '<details class="rq-norm"><summary>normative (machine)</summary><p class="rq-stmt">%s</p></details>\n' "$(esc "$stmt")"
  printf '</div>\n'
}
emit_requirements() {
  printf '<div class="rq-list">\n'
  while IFS= read -r id; do [[ -n "$id" ]] && emit_requirement_row "$id"; done < <(q ".sections[$1].blocks[$2].ids[]")
  printf '</div>\n'
}

emit_blocks() {
  local si="$1" nblk bi btype
  nblk="$(q ".sections[$si].blocks // [] | length")"
  for ((bi=0; bi<nblk; bi++)); do
    btype="$(q ".sections[$si].blocks[$bi].type")"
    case "$btype" in
      prose)        emit_prose "$si" "$bi" ;;
      note)         emit_note "$si" "$bi" ;;
      list)         emit_list "$si" "$bi" ;;
      code)         emit_code "$si" "$bi" ;;
      table)        emit_table "$si" "$bi" ;;
      mermaid)      emit_mermaid "$si" "$bi" ;;
      subhead)      emit_subhead "$si" "$bi" ;;
      requirements) emit_requirements "$si" "$bi" ;;
      *) echo "assemble-spec: ★未対応 block type '$btype' (silent drop 禁止・fail-closed)" >&2; exit 1 ;;
    esac
  done
}

emit_section() {
  local si="$1" tint kicker heading essence icon
  tint="$(q ".sections[$si].tint")"
  kicker="$(q ".sections[$si].kicker")"
  heading="$(q ".sections[$si].heading")"
  essence="$(q ".sections[$si].essence")"
  icon="${SECT_ICONS[$(( si % ${#SECT_ICONS[@]} ))]}"
  band "$tint" "$kicker" "$heading" "$icon"
  printf '<div data-component="section-essence-callout"><p class="sec-se">%s</p></div>\n' "$(esc "$essence")"
  emit_blocks "$si"
  band_end
}

# references = 非終端 照会 (前方・他文書へ)。 token/doc/role を固定属性で刻む (verify-spec が echo 厳密一致で突合)。
emit_references() {
  printf '<div class="ref-grid">\n'
  q '.references[] | [.token, .doc, .role] | @tsv' | while IFS=$'\t' read -r token doc role; do
    [[ -n "$token" ]] || continue
    printf '<div data-component="cross-doc-ref-chip" data-ref-token="%s" data-ref-role="%s"><span class="rf-token"><b>%s</b></span><span class="rf-arrow">\xe2\x86\x92</span><span class="rf-doc">%s</span><span class="rf-role">%s</span></div>\n' \
      "$(esc "$token")" "$(esc "$role")" "$(esc "$token")" "$(esc "$doc")" "$(esc "$role")"
  done
  printf '</div>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# footer は core_emit_footer に spec-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>spec-pack</span><span>folio engine B6 (instance#5)</span><span>EARS 章立て + 非終端 照会</span>'
}

build() {
  local nsec si
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  nsec="$(q '.sections | length')"
  for ((si=0; si<nsec; si++)); do emit_section "$si"; done
  # 非終端 照会 (前方 references) band。
  band violet "この規約が参照する文書 / 照会 (前方)" "rules は照会の終端ではない — 原則・ADR・検証へ前方照会する" "$ICO_ARROW"
  emit_references
  band_end
  # 用語集 band (core glossary)。
  band brand "用語集 / この文書で使う専門語" "本文に出てくる専門語のやさしい説明" "$ICO_TAG"
  emit_glossary
  band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-spec"
