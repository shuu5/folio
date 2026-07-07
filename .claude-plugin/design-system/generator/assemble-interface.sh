#!/usr/bin/env bash
# folio engine post-B6 (folio-ehar / c5r Tier C) — interface-pack 決定的 assembler (instance#2 / hybrid frontier / code 固有 doc-type 初例)
#
# 入力 interface contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# hybrid 型 = indexed (操作/エラー catalog) + descriptive (外部連携 + 横断散文)。 agnostic (案A = domain operation
# catalog・プロトコル中立・HTTP/JSON を書かない)。 datamodel-pack (hybrid) を範に、 operation/error/external/
# cross-cutting/principle-terminal を interface schema へ適用する。
#   - 構造・内容 (6 章 / 操作 / エラー / 外部連携 / 横断 / 原則終端 / 用語) は contract から決定的組立。
#     元データに無い操作・エラー・連携・cross-ref edge は生成できない。 mermaid 図は使わない (境界図は arch の領分)。
#   - ★cross-doc 前方照会 edge (案A = 別文書 link・再掲ゼロ): operations/errors/external/cross_cutting[].refs.srs[] (claim)
#     → SRS 要件 (FR/NFR/CON/AC)。 validate() が *生成前に* 参照先 SRS contract 実在 + 当該 ID 実在を fail-closed で確かめる。
#     ★deep-link: FR/NFR は href = <srs_html>#<ref> (fragment == 表示 REQ-ID) / CON/AC は href = <srs_html> (文書単位) + title 注記
#       (SRS 側 CON/AC アンカー未整備・x8mn 昇格まで暫定)。
#   - ★datamodel entity 参照 (uses.entities[]) は presentational (graph edge にしない)。 ent-chip href = <datamodel_html>#entity-<id>
#     (deep-link)・表示名は datamodel contract の entity 名から決定的に解決 (validate() が ID 実在を fail-closed)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 direction は拒否。
#   - ★binding 予約席 = プロトコル束縛 (本 version 未対応)。 非 null なら生成前 abort する fail-closed 予約 (案A 批准)。
#   - prose スロット (cover-summary / chapter-lead-NN / 各 operation の plain-<id>) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#
# inject-prose.sh は SRS/ADR/datamodel 等と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-interface.sh <interface-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-interface.sh <interface-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-interface: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-interface: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-interface: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# direction allowlist (interface-pack 固有・visible badge へ写像)。
declare -A DIR_OK=( [out]=1 [in]=1 )
declare -A DIR_LABEL=( [out]="送る (out)" [in]="受け取る (in)" )

# ---- cross_doc 解決先 (SRS / datamodel contract の絶対パス) ----
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
DM_REL="$(q '.cross_doc.datamodel_contract')"; DM_ABS="${CONTRACT_DIR}/${DM_REL}"
SRS_HTML="$(q '.cross_doc.srs_html')"
DM_HTML="$(q '.cross_doc.datamodel_html')"

# ---- SRS ref 分類集合 (FR/NFR = fragment deep-link / CON/AC = 文書単位 + title) + datamodel entity 名解決 ----
# 生成前に SRS/datamodel contract を読み込む。 不在時は空集合のまま validate() が fail-closed で捕捉する。
declare -A FRAG_SET      # requirements[].id ∪ nfr[].id (fragment deep-link 対象)
declare -A DOCREF_SET    # constraints[].id ∪ acceptance[].id (文書単位 link 対象)
declare -A ENT_NAME      # entity-id → 表示名 (datamodel contract 由来)
if [[ -f "$SRS_ABS" ]]; then
  while IFS= read -r _id; do [[ -n "$_id" && "$_id" != "null" ]] && FRAG_SET[$_id]=1; done < <(yq -r '(.requirements[].id, .nfr[].id)' "$SRS_ABS" 2>/dev/null)
  while IFS= read -r _id; do [[ -n "$_id" && "$_id" != "null" ]] && DOCREF_SET[$_id]=1; done < <(yq -r '(.constraints[].id, .acceptance[].id)' "$SRS_ABS" 2>/dev/null)
fi
if [[ -f "$DM_ABS" ]]; then
  while IFS=$'\t' read -r _eid _enm; do [[ -n "$_eid" ]] && ENT_NAME[$_eid]="$_enm"; done < <(yq -r '.entities[] | [.id, .name] | @tsv' "$DM_ABS" 2>/dev/null)
fi

# ---- icon SVG (interface-pack 固有・kicker 用。 共用 ICO_BOOK は lib/common.sh) ----
ICO_CTX='<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M8 4v6M8 14v2M12 14v2M16 14v2"/>'
ICO_OPS='<path d="M4 7h16M4 12h16M4 17h10"/><circle cx="19" cy="17" r="2"/>'
ICO_ERR='<circle cx="12" cy="12" r="9"/><path d="M15 9l-6 6M9 9l6 6"/>'
ICO_EXT='<path d="M7 8l-4 4 4 4M17 8l4 4-4 4M13 4l-2 16"/>'
ICO_CROSS='<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p
  core_validate_strings "assemble-interface" || errs=1
  # doc_type guard (hybrid 型 pack の identity・誤 contract 混入を拒否)
  [[ "$(q '.doc_type')" == "interface" ]] || { echo "assemble-interface: doc_type が interface でない: $(q '.doc_type')" >&2; errs=1; }
  # id 一意性 (operations / errors / external / cross_cutting)
  local axis
  for axis in '.operations[].id' '.errors[].id' '.external[].id' '.cross_cutting[].id'; do
    d="$(q "$axis" | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-interface: id 重複 ($axis): $d" >&2; errs=1; }
  done
  # external direction allowlist
  for p in $(q '.external[].direction'); do [[ -v DIR_OK[$p] ]] || { echo "assemble-interface: 未知の direction: $p (out|in)" >&2; errs=1; }; done
  # operations[].errors[] の各 id が errors[] に実在 (§3 の断り方 catalog に接地)
  local eref_missing
  eref_missing="$(comm -23 <(q '.operations[].errors[]' | sort -u | grep -v '^$') <(q '.errors[].id' | sort -u))"
  [[ -z "$eref_missing" ]] || { echo "assemble-interface: operations[].errors が errors[] に実在しない: $eref_missing" >&2; errs=1; }

  # ★binding 予約席 = non-null なら abort (fail-closed 予約・案A 批准。 通信方式束縛は本 version 未対応)。
  local bind; bind="$(q '.binding')"
  [[ "$bind" == "null" || -z "$bind" ]] || { echo "assemble-interface: ★binding が non-null ($bind) — プロトコル束縛は本 version 未対応 (fail-closed 予約席・案A)" >&2; errs=1; }

  # ★cross-doc 前方照会の終端解決 (SRS): 参照先 SRS contract 実在 + doc_id 一致 + 各 srs ref が SRS 要件/NFR/制約/受入に実在 + 空 ref 禁止。
  local srs_docid expect_docid missing n_srs n_srs_ne
  if [[ ! -f "$SRS_ABS" ]]; then
    echo "assemble-interface: cross_doc.srs_contract が見つからない: $SRS_REL (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$SRS_ABS")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-interface: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    n_srs="$(q '[.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]] | length')"
    n_srs_ne="$(q '[ (.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[]) | select((. // "") != "") ] | length')"
    [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-interface: ★SRS 照会の空 ref (有効 $n_srs_ne/$n_srs 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
    missing="$(comm -23 <(q '(.operations[].refs.srs[], .errors[].refs.srs[], .external[].refs.srs[], .cross_cutting[].refs.srs[])' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id, .constraints[].id, .acceptance[].id)' "$SRS_ABS" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-interface: ★SRS 照会の dangling: refs.srs が SRS 要件/NFR/制約/受入に実在しない: $missing" >&2; errs=1; }
  fi

  # ★datamodel entity 参照 (presentational・fail-closed): 参照先 datamodel contract 実在 + uses.entities の各 id が entity に実在。
  local dm_missing
  if [[ ! -f "$DM_ABS" ]]; then
    echo "assemble-interface: cross_doc.datamodel_contract が見つからない: $DM_REL (entity 参照先 不在)" >&2; errs=1
  else
    dm_missing="$(comm -23 <(q '(.operations[].uses.entities[], .external[].uses.entities[])' | sort -u | grep -v '^$') <(yq -r '.entities[].id' "$DM_ABS" | sort -u))"
    [[ -z "$dm_missing" ]] || { echo "assemble-interface: ★datamodel entity 参照の dangling: uses.entities が datamodel entity に実在しない: $dm_missing" >&2; errs=1; }
  fi

  # ★chapters (band 見出しのうち instance 固有の 3 章) は contract 必須 (folio-bhe・datamodel chapters と同型)。
  #   operations_band = 件数入り (「N つの操作」== |operations|)・errors_band = 件数入り (「N 通りの断り方」== |errors|)・
  #   external_band = 件数入り (「N つの外部連携」== |external|)。 件数を code に焼くと 2nd instance が偽件数を表示する
  #   (fabrication 面ゆえ neutral default を置かず fail-closed 必須)。 数詞は ASCII 半角必須の肯定形 (c5r.2)。
  local ck cv
  for ck in operations_band errors_band external_band; do
    cv="$(q ".chapters.${ck} // \"\"")"
    [[ -n "$cv" ]] || { echo "assemble-interface: ★chapters.${ck} 欠落 (band 見出しは contract 必須・instance hardcode 禁止)" >&2; errs=1; }
    if [[ -n "$cv" ]] && perl -CSD -Mutf8 -ne 'exit(/\p{Default_Ignorable_Code_Point}/?0:1)' <<<"$cv"; then
      echo "assemble-interface: ★chapters.${ck} に不可視/format 文字 (ゼロ幅・BOM 等・数詞照合を無効化する injection): $cv" >&2; errs=1
    fi
    # 全角数字 (ASCII 件数照合の回避表記) を拒否 (bracket 式でなく明示 alternation で locale 非依存)。
    if grep -qE '０|１|２|３|４|５|６|７|８|９' <<<"$cv"; then
      echo "assemble-interface: ★chapters.${ck} に全角数字 (ASCII 件数照合の回避表記・半角で書く): $cv" >&2; errs=1
    fi
  done
  # 数詞 == 実件数 (肯定形・複合語 false-match 除去・sc= 句読点境界)。
  validate_numeral "operations_band" "$(q '.chapters.operations_band')" 'つの操作' "$(q '.operations | length')" || errs=1
  validate_numeral "errors_band" "$(q '.chapters.errors_band')" '通りの断り方' "$(q '.errors | length')" || errs=1
  validate_numeral "external_band" "$(q '.chapters.external_band')" 'つの外部連携' "$(q '.external | length')" || errs=1

  core_validate_glossary_substring "assemble-interface" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-interface: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# validate_numeral <name> <heading> <unit> <expected> — 「N <unit>」の ASCII 数詞を全出現照合し expected と一致を要求 (肯定形)。
#   unit 直後が漢字/カタカナ/長音 (複合語継続) なら不採用 (perl negative-lookahead)。 sc= で句読点を境界扱い (fail-open 回避)。
#   perl は -CSD (I/O UTF-8) + -Mutf8 (プログラム内日本語リテラルも UTF-8 = 両方必須)。 戻り値: 一致=0 / 不一致・数詞なし=1。
validate_numeral() {
  local name="$1" heading="$2" unit="$3" expected="$4" ns n rc=0
  ns="$(UNIT="$unit" perl -CSD -Mutf8 -ne 'my $u=$ENV{UNIT}; utf8::decode($u); while(/([0-9]+)\s*\Q$u\E(?![\p{sc=Han}\p{sc=Katakana}ー])/g){print "$1\n"}' <<<"$heading" || true)"
  if [[ -z "$ns" ]]; then
    echo "assemble-interface: ★chapters.${name} に ASCII 数字の件数「N ${unit}」が無い (数詞は半角 ASCII 必須 = 漢数字等の照合回避を封鎖): $heading" >&2; return 1
  fi
  while IFS= read -r n; do
    [[ "$n" == "$expected" ]] || { echo "assemble-interface: ★chapters.${name} の数詞 ${n} が実件数 ${expected} と不一致 (件数 fabrication)" >&2; rc=1; }
  done <<<"$ns"
  return $rc
}

# ---- interface-pack 固有 CSS (srs.css token を流用。 mockup interface-demo/ の確定形を忠実にミラー) ----
emit_interface_css() {
  cat <<'CSS'
/* ===== interface-pack 固有部品 (folio-ehar / instance#2)。 srs.css / datamodel token を流用 ===== */
/* §1 課題と範囲 (context-problem / scope-note・datamodel と共有) */
[data-component="context-problem"]{border:1px solid var(--line);border-left:5px solid var(--brand);border-radius:12px;padding:14px 18px;background:var(--brand-tint);font-size:14px;line-height:1.75;color:var(--ink-soft);margin:0 0 16px}
[data-component="scope-note-callout"]{border:1px solid var(--line);border-left:5px solid var(--info);border-radius:12px;padding:14px 18px;background:var(--info-tint);font-size:13.5px;line-height:1.75;color:var(--ink-soft);margin:0}
[data-component="scope-note-callout"] .sn-lab{display:block;font-size:11px;font-weight:800;letter-spacing:.08em;color:var(--info);margin-bottom:5px;text-transform:uppercase}
/* reusable SRS 照会 badge + refs-row (datamodel と共有) */
.srs-badge{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:800;text-decoration:none;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand);border-radius:6px;padding:2px 8px;white-space:nowrap}
.srs-badge:hover{box-shadow:inset 0 0 0 1px var(--brand)}
.refs-lab{font-size:10.5px;font-weight:800;letter-spacing:.06em;color:var(--ink-faint);margin-right:2px}
.refs-none{font-size:11.5px;color:var(--ink-faint);font-weight:600}
.refs-row{display:flex;flex-wrap:wrap;gap:7px;align-items:center;margin-top:2px}
/* if-grid (縦積みカードリスト) + ent-chip (datamodel entity への presentational deep-link) + opc-slot / slot-lab */
.if-grid{display:flex;flex-direction:column;gap:14px;margin:10px 0}
.ent-chip{display:inline-flex;align-items:center;gap:5px;font-size:11px;font-weight:700;text-decoration:none;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:6px;padding:2px 9px;white-space:nowrap}
.ent-chip:hover{box-shadow:inset 0 0 0 1px var(--info)}
.ent-chip .en{font-family:ui-monospace,monospace;font-size:9px;opacity:.72}
.slot-lab{font-size:10.5px;font-weight:800;letter-spacing:.06em;color:var(--ink-faint);margin-right:2px}
.opc-slot{display:flex;flex-wrap:wrap;gap:7px;align-items:center}
/* §2 operation cards */
[data-component="operation-card"]{position:relative;overflow:hidden;border:1px solid var(--line);border-radius:14px;background:var(--paper);box-shadow:var(--shadow);padding:16px 18px 15px 22px;display:flex;flex-direction:column;gap:12px}
[data-component="operation-card"]::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:var(--brand)}
.opc-head{display:flex;align-items:center;gap:11px;flex-wrap:wrap}
.opc-num{font-size:11px;font-weight:800;font-family:ui-monospace,monospace;color:#fff;background:var(--brand);border-radius:7px;padding:3px 9px;white-space:nowrap}
.opc-name{font-size:17.5px;font-weight:800;color:var(--ink);line-height:1.3}
.opc-actor{margin-left:auto;font-size:12px;font-weight:700;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:999px;padding:3px 12px;display:inline-flex;align-items:center;gap:7px;white-space:nowrap}
.opc-actor .a-lab{font-size:9px;font-weight:800;letter-spacing:.06em;color:var(--ink-faint);text-transform:uppercase}
[data-component="op-io-row"]{display:flex;align-items:stretch;flex-wrap:wrap;border:1px solid var(--line);border-radius:11px;overflow:hidden}
.io-cell{flex:1 1 240px;padding:11px 15px;display:flex;flex-direction:column;gap:4px;min-width:0}
.io-cell.req{background:var(--brand-tint)}
.io-cell.res{background:var(--ok-tint)}
.io-lab{font-size:10px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}
.io-cell.req .io-lab{color:var(--brand)}
.io-cell.res .io-lab{color:var(--ok)}
.io-val{font-size:13.5px;color:var(--ink-soft);line-height:1.6}
.io-arrow{flex:0 0 auto;display:grid;place-items:center;padding:0 12px;color:var(--ink-faint);font-weight:900;font-size:18px;background:var(--paper-2);border-left:1px solid var(--line);border-right:1px solid var(--line)}
.io-arrow::before{content:"→"}
.op-noerror{font-size:11.5px;font-weight:700;color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:999px;padding:3px 11px;display:inline-flex;align-items:center;gap:6px}
[data-component="op-error-chip"]{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;font-weight:800;text-decoration:none;color:var(--bad);background:var(--bad-tint);border:1px solid var(--bad-line);border-radius:999px;padding:3px 11px;white-space:nowrap}
[data-component="op-error-chip"]:hover{box-shadow:inset 0 0 0 1px var(--bad)}
[data-component="op-error-chip"] .ec-code{font-family:ui-monospace,monospace;font-size:9px;opacity:.8}
.opc-plain{font-size:12.5px;color:var(--ink-soft);background:var(--paper-2);border-radius:8px;padding:8px 11px;line-height:1.7;margin:0}
.opc-plain::before{content:"やさしく言うと ";font-weight:700;font-size:10px;color:var(--brand)}
/* §3 error cards */
.err-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin:8px 0}
[data-component="error-card"]{border:1px solid var(--bad-line);border-left:5px solid var(--bad);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);padding:15px 17px;display:flex;flex-direction:column;gap:10px;scroll-margin-top:16px}
[data-component="error-card"]:target{box-shadow:0 0 0 3px var(--bad-line),var(--shadow)}
.erc-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.erc-id{font-weight:800;font-size:11.5px;font-family:ui-monospace,monospace;color:var(--bad);background:var(--bad-tint);border:1px solid var(--bad-line);border-radius:6px;padding:2px 9px;white-space:nowrap}
.erc-name{font-size:16px;font-weight:800;color:var(--ink)}
.erc-body{display:flex;flex-direction:column;gap:7px}
.erc-when{font-size:13px;color:var(--ink-soft);line-height:1.65;margin:0}
.erc-when .erc-k{font-weight:800;font-size:10.5px;letter-spacing:.04em;color:var(--ink-faint);margin-right:6px}
.erc-promise{font-size:13.5px;font-weight:700;color:var(--ink);background:var(--bad-tint);border-radius:8px;padding:9px 12px;line-height:1.7;margin:0}
.erc-promise .erc-k{display:block;font-weight:800;font-size:10px;letter-spacing:.06em;color:var(--bad);margin-bottom:2px;text-transform:uppercase}
/* §4 external rows */
[data-component="external-row"]{border:1px solid var(--line);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);padding:14px 17px;display:flex;flex-direction:column;gap:10px}
[data-component="external-row"].dir-out{border-left:5px solid var(--info)}
[data-component="external-row"].dir-in{border-left:5px solid var(--violet)}
.exr-head{display:flex;align-items:center;gap:11px;flex-wrap:wrap}
.exr-name{font-size:15.5px;font-weight:800;color:var(--ink)}
.exr-dir{font-size:10.5px;font-weight:800;letter-spacing:.04em;border-radius:999px;padding:2px 11px;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
.exr-dir.out{color:var(--info);background:var(--info-tint);border:1px solid var(--info-line)}
.exr-dir.in{color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line)}
.exr-partner{margin-left:auto;font-size:12px;font-weight:700;color:var(--ink-soft);display:inline-flex;align-items:center;gap:7px}
.exr-partner .p-lab{font-size:9px;font-weight:800;letter-spacing:.06em;color:var(--ink-faint);text-transform:uppercase}
.exr-flow{display:flex;align-items:center;gap:9px;flex-wrap:wrap;font-size:13px;background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:8px 12px}
.exr-node{font-weight:800;color:var(--ink);background:var(--paper);border:1px solid var(--line);border-radius:8px;padding:3px 11px}
.exr-node.self{color:var(--brand);border-color:var(--brand);background:var(--brand-tint)}
.exr-verb{font-size:11.5px;font-weight:800;display:inline-flex;align-items:center;gap:5px}
.exr-verb .ar{font-size:14px;font-weight:900}
.dir-out .exr-verb{color:var(--info)} .dir-in .exr-verb{color:var(--violet)}
.exr-promise{font-size:13px;color:var(--ink-soft);line-height:1.7;margin:0}
/* §5 cross-cutting cards */
[data-component="cross-cutting-card"]{border:1px solid var(--line);border-left:5px solid var(--violet);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);padding:15px 17px;display:flex;flex-direction:column;gap:9px}
.ccc-head{display:flex;align-items:baseline;gap:9px}
.ccc-id{font-weight:800;font-size:12px;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:6px;padding:2px 8px;white-space:nowrap}
.ccc-rule{font-size:14.5px;font-weight:800;line-height:1.55;margin:0;color:var(--ink)}
/* §5 原則終端 (datamodel の principle-terminal と同型) */
[data-component="principle-terminal"]{margin:12px 0 0;border:1px solid var(--violet-line);border-radius:12px;padding:13px 16px;background:var(--violet-tint)}
.pt-label{font-size:10.5px;font-weight:800;letter-spacing:.08em;color:var(--violet);background:var(--paper);border:1px solid var(--violet-line);border-radius:5px;padding:1px 7px;margin-right:8px}
.pt-id{font-weight:800;font-size:12.5px;color:var(--violet);font-family:ui-monospace,monospace}
.pt-text{font-size:13.5px;color:var(--ink-soft);line-height:1.75;margin:7px 0 0}
/* interface 固有 responsive */
@media(max-width:900px){ .err-grid{grid-template-columns:1fr} }
@media(max-width:640px){ .io-arrow{flex:1 1 100%;padding:3px 0;border-left:0;border-right:0;border-top:1px solid var(--line);border-bottom:1px solid var(--line)} .io-arrow::before{content:"↓"} }
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="interface">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio interface-pack assembler (folio-ehar / instance#2) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_interface_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このインターフェース仕様が約束すること (1 文サマリ)"
  local n_op n_err n_ext
  n_op="$(q '.operations | length')"; n_err="$(q '.errors | length')"; n_ext="$(q '.external | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">構成</span><span class="v">%s</span></span><span class="m"><span class="k">照会先</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "interface (インターフェース)" "$(esc "操作 ${n_op} / 断り方 ${n_err} / 外部連携 ${n_ext}")" "$(esc "$(q '.cross_doc.srs_doc_id') / $(q '.cross_doc.datamodel_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (照会先 SRS 要件 + datamodel 情報のかたまり・案A)。 CJK 規律: <b> 閉じ直後に助詞なし ((FR / CON) は ASCII 括弧)。
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の要件 (FR / CON)・<b>%s</b>の情報のかたまり</div>\n' \
    "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.cross_doc.datamodel_doc_id')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# §1 課題と範囲 (datamodel と同型)
emit_context() {
  printf '<p data-component="context-problem">%s</p>\n' "$(mark_terms "$(q '.context.problem')")"
  printf '<div data-component="scope-note-callout"><span class="sn-lab">この文書の範囲</span>%s</div>\n' "$(esc "$(q '.context.scope_note')")"
}

# SRS 照会バッジ emit (FR/NFR = fragment deep-link / CON/AC = 文書単位 + title)。 $1=refs の yq expr $2=(任意) 追加 class
emit_srs_refs() {
  local refs_expr="$1" extra="${2:-}"
  local -a R; mapfile -t R < <(q "$refs_expr")
  printf '<div class="refs-row%s"><span class="refs-lab">照会 (SRS)</span>' "$extra"
  if [[ "${#R[@]}" -eq 0 ]]; then
    printf '<span class="refs-none">—</span>'
  else
    local r
    for r in "${R[@]}"; do
      [[ -n "$r" ]] || continue
      if [[ -v FRAG_SET[$r] ]]; then
        printf '<a class="srs-badge" href="%s#%s" data-if-ref="%s" data-if-role="claim">%s</a>' \
          "$(esc "$SRS_HTML")" "$(esc "$r")" "$(esc "$r")" "$(esc "$r")"
      else
        printf '<a class="srs-badge" href="%s" title="%s" data-if-ref="%s" data-if-role="claim">%s</a>' \
          "$(esc "$SRS_HTML")" "$(esc "SRS ${r} — SRS ページに該当アンカーが無いため文書単位でリンク")" "$(esc "$r")" "$(esc "$r")"
      fi
    done
  fi
  printf '</div>\n'
}

# ent-chip emit (uses.entities → datamodel entity への presentational deep-link)。 $1=entities の yq expr
emit_ent_chips() {
  local ents_expr="$1"
  printf '<div class="opc-slot"><span class="slot-lab">使う情報</span>'
  local eid ename
  while IFS= read -r eid; do
    [[ -n "$eid" ]] || continue
    ename="${ENT_NAME[$eid]:-$eid}"
    printf '<a class="ent-chip" href="%s#entity-%s">%s <span class="en">%s</span></a>' \
      "$(esc "$DM_HTML")" "$(esc "$eid")" "$(esc "$ename")" "$(esc "$eid")"
  done < <(q "$ents_expr")
  printf '</div>\n'
}

# §2 操作 (operation cards)
emit_operations() {
  printf '<div class="if-grid">\n'
  local -a OIDS; mapfile -t OIDS < <(q '.operations[].id')
  local oid n=0 nerr
  for oid in "${OIDS[@]}"; do
    n=$((n+1))
    printf '<article data-component="operation-card" id="op-%s">\n' "$(esc "$oid")"
    printf '<div class="opc-head"><span class="opc-num">OP-%s</span><span class="opc-name">%s</span><span class="opc-actor"><span class="a-lab">使う人</span>%s</span></div>\n' \
      "$n" "$(esc "$(q '.operations[] | select(.id=="'"$oid"'") | .name')")" "$(esc "$(q '.operations[] | select(.id=="'"$oid"'") | .actor')")"
    printf '<div data-component="op-io-row"><div class="io-cell req"><span class="io-lab">渡すもの</span><span class="io-val">%s</span></div><div class="io-arrow" aria-hidden="true"></div><div class="io-cell res"><span class="io-lab">返るもの</span><span class="io-val">%s</span></div></div>\n' \
      "$(esc "$(q '.operations[] | select(.id=="'"$oid"'") | .request')")" "$(esc "$(q '.operations[] | select(.id=="'"$oid"'") | .response')")"
    # 断られ方 slot (error chips or op-noerror)
    nerr="$(q '.operations[] | select(.id=="'"$oid"'") | .errors | length')"
    printf '<div class="opc-slot"><span class="slot-lab">断られ方</span>'
    if [[ "$nerr" == "0" ]]; then
      printf '<span class="op-noerror"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>この操作に「断り」はありません</span>'
    else
      local eid ename
      while IFS= read -r eid; do
        [[ -n "$eid" ]] || continue
        ename="$(q '.errors[] | select(.id=="'"$eid"'") | .name')"
        printf '<a class="op-error-chip" data-component="op-error-chip" href="#error-%s">%s <span class="ec-code">%s</span></a>' \
          "$(esc "$eid")" "$(esc "$ename")" "$(esc "$eid")"
      done < <(q '.operations[] | select(.id=="'"$oid"'") | .errors[]')
    fi
    printf '</div>\n'
    # 使う情報 slot (ent-chips)
    emit_ent_chips '.operations[] | select(.id=="'"$oid"'") | .uses.entities[]'
    # 照会 slot
    emit_srs_refs '.operations[] | select(.id=="'"$oid"'") | .refs.srs[]' " refs-row"
    printf '<p class="opc-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$oid")"
    printf '</article>\n'
  done
  printf '</div>\n'
}

# §3 エラーカタログ (error cards)
emit_errors() {
  printf '<div class="err-grid">\n'
  local -a EIDS; mapfile -t EIDS < <(q '.errors[].id')
  local eid
  for eid in "${EIDS[@]}"; do
    printf '<article data-component="error-card" id="error-%s">\n' "$(esc "$eid")"
    printf '<div class="erc-head"><span class="erc-id">%s</span><span class="erc-name">%s</span></div>\n' \
      "$(esc "$eid")" "$(esc "$(q '.errors[] | select(.id=="'"$eid"'") | .name')")"
    printf '<div class="erc-body"><p class="erc-when"><span class="erc-k">こんなとき</span>%s</p><p class="erc-promise"><span class="erc-k">こう断る</span>%s</p></div>\n' \
      "$(esc "$(q '.errors[] | select(.id=="'"$eid"'") | .when')")" "$(esc "$(q '.errors[] | select(.id=="'"$eid"'") | .promise')")"
    emit_srs_refs '.errors[] | select(.id=="'"$eid"'") | .refs.srs[]'
    printf '</article>\n'
  done
  printf '</div>\n'
}

# §4 外部連携 (external rows)
emit_external() {
  printf '<div class="if-grid">\n'
  local -a XIDS; mapfile -t XIDS < <(q '.external[].id')
  local xid dir dcls name partner
  for xid in "${XIDS[@]}"; do
    dir="$(q '.external[] | select(.id=="'"$xid"'") | .direction')"
    name="$(q '.external[] | select(.id=="'"$xid"'") | .name')"
    partner="$(q '.external[] | select(.id=="'"$xid"'") | .partner')"
    printf '<article data-component="external-row" class="dir-%s" id="ext-%s">\n' "$(esc "$dir")" "$(esc "$xid")"
    # head (name / dir badge / partner)
    printf '<div class="exr-head"><span class="exr-name">%s</span><span class="exr-dir %s">%s%s</span><span class="exr-partner"><span class="p-lab">相手</span>%s</span></div>\n' \
      "$(esc "$name")" "$(esc "$dir")" \
      "$([[ "$dir" == "out" ]] && printf '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7M8 7h9v9"/></svg>' || printf '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M17 7 7 17M16 17H7V8"/></svg>')" \
      "$(esc "${DIR_LABEL[$dir]}")" "$(esc "$partner")"
    # flow (direction を「送る/受け取る」の矢印表現で)
    if [[ "$dir" == "out" ]]; then
      printf '<div class="exr-flow"><span class="exr-node self">この仕組み</span><span class="exr-verb">送る<span class="ar">→</span></span><span class="exr-node">%s</span></div>\n' "$(esc "$partner")"
    else
      printf '<div class="exr-flow"><span class="exr-node">%s</span><span class="exr-verb">受け取る<span class="ar">→</span></span><span class="exr-node self">この仕組み</span></div>\n' "$(esc "$partner")"
    fi
    printf '<p class="exr-promise">%s</p>\n' "$(mark_terms "$(q '.external[] | select(.id=="'"$xid"'") | .promise')")"
    emit_ent_chips '.external[] | select(.id=="'"$xid"'") | .uses.entities[]'
    emit_srs_refs '.external[] | select(.id=="'"$xid"'") | .refs.srs[]'
    printf '</article>\n'
  done
  printf '</div>\n'
}

# §5 横断の決まり (cross-cutting cards + 原則終端)
emit_cross_cutting() {
  printf '<div class="if-grid">\n'
  local -a CIDS; mapfile -t CIDS < <(q '.cross_cutting[].id')
  local cid
  for cid in "${CIDS[@]}"; do
    printf '<div data-component="cross-cutting-card" id="cc-%s">\n' "$(esc "$cid")"
    printf '<div class="ccc-head"><span class="ccc-id">%s</span></div>\n' "$(esc "$cid")"
    printf '<p class="ccc-rule">%s</p>\n' "$(mark_terms "$(q '.cross_cutting[] | select(.id=="'"$cid"'") | .rule')")"
    emit_srs_refs '.cross_cutting[] | select(.id=="'"$cid"'") | .refs.srs[]'
    printf '</div>\n'
  done
  printf '</div>\n'
  # 原則終端 panel (照会 graph の終端・within-doc anchor target)
  printf '<div data-component="principle-terminal" id="principle-%s"><span class="pt-label">原則終端</span><span class="pt-id">%s</span><p class="pt-text">%s</p></div>\n' \
    "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.text')")"
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

emit_footer() {
  core_emit_footer '<span>folio design system</span><span>interface-pack</span><span>folio engine post-B6 (instance#2)</span><span>operation catalog + error contract + cross-doc 照会 graph</span>'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "課題と範囲"    "なぜ「窓口の約束」を先に決めるのか"   "$ICO_CTX";   emit_context;       band_end
  # ★operations/errors/external の band 見出しは contract .chapters.* 由来 (instance 固有の件数を code に焼かない・folio-bhe)。 他 3 章は pack 不変文言。
  band brand  "操作"          "$(q '.chapters.operations_band')"      "$ICO_OPS";   emit_operations;    band_end
  band bad    "断り方の約束"  "$(q '.chapters.errors_band')"          "$ICO_ERR";   emit_errors;        band_end
  band ok     "外部連携"      "$(q '.chapters.external_band')"        "$ICO_EXT";   emit_external;      band_end
  band warn   "横断の決まり"  "どの操作にも共通してかかる決まり"     "$ICO_CROSS"; emit_cross_cutting; band_end
  band violet "用語"          "本文に出てくる言葉のやさしい説明"     "$ICO_BOOK";  emit_glossary;      band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-interface"
