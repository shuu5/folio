#!/usr/bin/env bash
# folio engine post-B6 (folio-1q8o / c5r Tier C) — data-model-pack 決定的 assembler (instance#1 / hybrid frontier)
#
# 入力 data-model contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# hybrid 型 = indexed (entities カタログ) + descriptive (ER 図 + domain 散文)。 arch-pack (記述型) を範に、
# entity/relationship/data-policy/principle-terminal/ER 図 を data-model schema へ適用する。
#   - 構造・内容 (6 章 / entity / つながり / データ方針 / 原則終端 / ER 図 / 用語) は contract から決定的組立。
#     元データに無い entity・つながり・方針・図・cross-ref edge は生成できない。
#   - ★cross-doc 前方照会 edge (案A = 別文書 link・再掲ゼロ): entities/relationships/data_policy[].refs.srs[] (claim)
#     → SRS 要件 (FR/NFR)。 validate() が *生成前に* 参照先 SRS contract 実在 + 当該 ID 実在を fail-closed で確かめる。
#     ★deep-link: 各照会バッジの href = <srs_html>#<ref> (fragment == 表示 REQ-ID)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 kind/sensitivity/cardinality は拒否。
#   - prose スロット (cover-summary / chapter-lead-NN / 各 entity の plain-<id>) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は lib/common.sh (core) を共用 (= term-inline 機構は pack 非依存)。
#   - ER 図は raw DSL を esc して <pre class="mermaid"> へ join 出力 (raw DSL 露出 = gate blocker・folio-97z 教訓)。
#
# inject-prose.sh は SRS/ADR/arch 等と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-datamodel.sh <datamodel-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-datamodel.sh <datamodel-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-datamodel: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-datamodel: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-datamodel: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/mark_terms/ico/band/cover骨格/glossary/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
core_init_term_inline

# kind / sensitivity / cardinality / field-type allowlist (datamodel-pack 固有・visible badge へ写像)。
declare -A ENT_KIND_OK=( [master]=1 [event]=1 )
declare -A ENT_KIND_LABEL=( [master]=台帳 [event]=記録 )
declare -A SENS_OK=( [high]=1 [normal]=1 )
declare -A CARD_OK=( [one-to-many]=1 [one-to-zero-or-one]=1 [one-to-one]=1 [many-to-many]=1 )
declare -A CARD_LABEL=( [one-to-many]="1 対 多" [one-to-zero-or-one]="1 対 0〜1" [one-to-one]="1 対 1" [many-to-many]="多 対 多" )
declare -A DIAG_KIND_OK=( [er]=1 )
declare -A DIAG_COMPONENT=( [er]=er-diagram )
declare -A DIAG_TAG=( [er]="ER — Entity Relationship" )

# ---- icon SVG (datamodel-pack 固有。 共用 ICO_BOOK は lib/common.sh) ----
ICO_SCOPE='<path d="M12 3v18M3 8h18M3 16h18"/>'
ICO_GRAPH='<circle cx="6" cy="6" r="3"/><circle cx="18" cy="18" r="3"/><path d="M9 6h6a3 3 0 0 1 3 3v6"/>'
ICO_BLOCKS='<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'
ICO_LINK='<circle cx="5" cy="12" r="2.5"/><circle cx="19" cy="6" r="2.5"/><circle cx="19" cy="18" r="2.5"/><path d="M7.2 11l9.6-4M7.2 13l9.6 4"/>'
ICO_SHIELD='<path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z"/><path d="M9 12l2 2 4-4"/>'

# ---- fail-closed contract validation ----
validate() {
  local errs=0 p
  core_validate_strings "assemble-datamodel" || errs=1
  # doc_type guard (hybrid 型 pack の identity・誤 contract 混入を拒否)
  [[ "$(q '.doc_type')" == "data-model" ]] || { echo "assemble-datamodel: doc_type が data-model でない: $(q '.doc_type')" >&2; errs=1; }
  # id 一意性 (entities / relationships / data_policy / diagrams)
  local axis
  for axis in '.entities[].id' '.relationships[].id' '.data_policy[].id' '.diagrams[].id'; do
    d="$(q "$axis" | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-datamodel: id 重複 ($axis): $d" >&2; errs=1; }
  done
  # entity kind / sensitivity allowlist
  for p in $(q '.entities[].kind'); do [[ -v ENT_KIND_OK[$p] ]] || { echo "assemble-datamodel: 未知の entity kind: $p (master|event)" >&2; errs=1; }; done
  for p in $(q '.entities[].sensitivity'); do [[ -v SENS_OK[$p] ]] || { echo "assemble-datamodel: 未知の sensitivity: $p (high|normal)" >&2; errs=1; }; done
  # relationship cardinality allowlist + from/to が entity id に実在
  for p in $(q '.relationships[].cardinality'); do [[ -v CARD_OK[$p] ]] || { echo "assemble-datamodel: 未知の cardinality: $p" >&2; errs=1; }; done
  local relend
  relend="$(comm -23 <(q '(.relationships[].from, .relationships[].to)' | sort -u) <(q '.entities[].id' | sort -u))"
  [[ -z "$relend" ]] || { echo "assemble-datamodel: relationship from/to が entity id に実在しない: $relend" >&2; errs=1; }
  # diagram kind allowlist
  for p in $(q '.diagrams[].kind'); do [[ -v DIAG_KIND_OK[$p] ]] || { echo "assemble-datamodel: 未知の diagram kind: $p (er)" >&2; errs=1; }; done
  # 図 D1 必須 (ER 図 = §2 全体図の要)
  [[ "$(q '[.diagrams[] | select(.id=="D1")] | length')" == "1" ]] || { echo "assemble-datamodel: 図 D1 (ER) が無い or 重複" >&2; errs=1; }

  # ★cross-doc 前方照会の終端解決 (SRS): 参照先 SRS contract 実在 + doc_id 一致 + 各 srs ref が SRS 要件/NFR に実在 + 空 ref 禁止。
  local srs_rel srs_abs srs_docid expect_docid missing n_srs n_srs_ne
  srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-datamodel: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-datamodel: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    n_srs="$(q '[.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]] | length')"
    n_srs_ne="$(q '[ (.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[]) | select((. // "") != "") ] | length')"
    [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-datamodel: ★SRS 照会の空 ref (有効 $n_srs_ne/$n_srs 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
    missing="$(comm -23 <(q '(.entities[].refs.srs[], .relationships[].refs.srs[], .data_policy[].refs.srs[])' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id)' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-datamodel: ★SRS 照会の dangling: refs.srs が SRS 要件/NFR に実在しない: $missing" >&2; errs=1; }
  fi

  # ★chapters (band 見出しのうち instance 固有の 2 章) は contract 必須 (folio-bhe・arch chapters と同型)。
  #   entities_band = 件数入り (「N つの情報のかたまり」== |entities|)・relationships_band = 件数入り (「N つのつながり」== |relationships|)。
  #   件数を code に焼くと 2nd instance が偽件数を表示する (fabrication 面ゆえ neutral default を置かず fail-closed 必須)。
  #   数詞は ASCII 半角必須の肯定形 (c5r.2)。 不可視/format 文字は Default_Ignorable クラス全体で拒否 (ceiling wf_cb58ae5a)。
  local ck cv
  for ck in entities_band relationships_band; do
    cv="$(q ".chapters.${ck} // \"\"")"
    [[ -n "$cv" ]] || { echo "assemble-datamodel: ★chapters.${ck} 欠落 (band 見出しは contract 必須・instance hardcode 禁止)" >&2; errs=1; }
    if [[ -n "$cv" ]] && perl -CSD -Mutf8 -ne 'exit(/\p{Default_Ignorable_Code_Point}/?0:1)' <<<"$cv"; then
      echo "assemble-datamodel: ★chapters.${ck} に不可視/format 文字 (ゼロ幅・BOM 等・数詞照合を無効化する injection): $cv" >&2; errs=1
    fi
    # 全角数字 (ASCII 件数照合の回避表記) を拒否 (bracket 式でなく明示 alternation で locale 非依存)。
    if grep -qE '０|１|２|３|４|５|６|７|８|９' <<<"$cv"; then
      echo "assemble-datamodel: ★chapters.${ck} に全角数字 (ASCII 件数照合の回避表記・半角で書く): $cv" >&2; errs=1
    fi
  done
  # 数詞 == 実件数 (肯定形・複合語 false-match 除去・sc= 句読点境界)。 entities_band=「N つの情報のかたまり」/ relationships_band=「N つのつながり」。
  validate_numeral "entities_band" "$(q '.chapters.entities_band')" 'つの情報のかたまり' "$(q '.entities | length')" || errs=1
  validate_numeral "relationships_band" "$(q '.chapters.relationships_band')" 'つのつながり' "$(q '.relationships | length')" || errs=1

  core_validate_glossary_substring "assemble-datamodel" || errs=1
  [[ "$errs" -eq 0 ]] || { echo "assemble-datamodel: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# validate_numeral <name> <heading> <unit> <expected> — 「N <unit>」の ASCII 数詞を全出現照合し expected と一致を要求 (肯定形)。
#   unit 直後が漢字/カタカナ/長音 (複合語継続) なら不採用 (perl negative-lookahead)。 sc= で句読点を境界扱い (fail-open 回避)。
#   perl は -CSD (I/O UTF-8) + -Mutf8 (プログラム内日本語リテラルも UTF-8 = 両方必須)。 戻り値: 一致=0 / 不一致・数詞なし=1。
validate_numeral() {
  local name="$1" heading="$2" unit="$3" expected="$4" ns n rc=0
  ns="$(UNIT="$unit" perl -CSD -Mutf8 -ne 'my $u=$ENV{UNIT}; utf8::decode($u); while(/([0-9]+)\s*\Q$u\E(?![\p{sc=Han}\p{sc=Katakana}ー])/g){print "$1\n"}' <<<"$heading" || true)"
  if [[ -z "$ns" ]]; then
    echo "assemble-datamodel: ★chapters.${name} に ASCII 数字の件数「N ${unit}」が無い (数詞は半角 ASCII 必須 = 漢数字等の照合回避を封鎖): $heading" >&2; return 1
  fi
  while IFS= read -r n; do
    [[ "$n" == "$expected" ]] || { echo "assemble-datamodel: ★chapters.${name} の数詞 ${n} が実件数 ${expected} と不一致 (件数 fabrication)" >&2; rc=1; }
  done <<<"$ns"
  return $rc
}

# ---- datamodel-pack 固有 CSS (srs.css token を流用。 ER 図 chrome は arch の figure.diagram/.er-legend を継承) ----
emit_datamodel_css() {
  cat <<'CSS'
/* ===== data-model-pack 固有部品 (folio-1q8o / instance#1)。 srs.css / arch.css の token を流用 ===== */
/* ER 図 (mermaid render target) + クロウフット記法凡例 (arch.css から継承) */
figure.diagram{margin:14px 0;border:1px solid var(--line);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);overflow:hidden}
figure.diagram .mermaid{margin:0;padding:14px 10px;overflow-x:auto;text-align:center}
figure.diagram .mermaid:not([data-processed]){font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;line-height:1.55;white-space:pre;text-align:left;color:var(--ink-soft);background:var(--paper-2);border-radius:10px}
figure.diagram figcaption{padding:11px 15px 13px;font-size:12px;color:var(--ink-faint);border-top:1px dashed var(--line);background:var(--paper);line-height:1.6}
.diag-tag{display:inline-block;font-size:10px;font-weight:800;letter-spacing:.06em;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:5px;padding:1px 7px;margin-right:7px}
.er-legend{display:flex;flex-wrap:wrap;align-items:center;gap:9px 18px;padding:12px 15px;border-top:1px dashed var(--line);background:var(--paper-2)}
.er-legend .ell-title{font-size:10px;font-weight:800;letter-spacing:.05em;color:var(--ink-faint)}
.er-legend .ell{display:inline-flex;align-items:center;gap:7px;font-size:12px;color:var(--ink-soft)}
.er-legend .ell-ico{width:40px;height:18px;flex:0 0 auto;color:var(--brand)}
.er-legend .ell-txt{line-height:1.4}
.er-legend .ell-txt b{color:var(--ink);font-weight:800}
.er-legend .ell-note{flex:1 1 100%;font-size:12px;color:var(--ink-soft);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:8px;padding:8px 12px;line-height:1.65}
.er-legend .ell-note b{color:var(--ok);font-weight:800}
.dm-grid{display:flex;flex-direction:column;gap:14px;margin:10px 0}
/* §1 scope note (context-problem を info 版で) */
[data-component="context-problem"]{border:1px solid var(--line);border-left:5px solid var(--brand);border-radius:12px;padding:14px 18px;background:var(--brand-tint);font-size:14px;line-height:1.75;color:var(--ink-soft);margin:0 0 16px}
[data-component="scope-note-callout"]{border:1px solid var(--line);border-left:5px solid var(--info);border-radius:12px;padding:14px 18px;background:var(--info-tint);font-size:13.5px;line-height:1.75;color:var(--ink-soft);margin:0}
[data-component="scope-note-callout"] .sn-lab{display:block;font-size:11px;font-weight:800;letter-spacing:.08em;color:var(--info);margin-bottom:5px;text-transform:uppercase}
/* reusable SRS 照会 badge */
.srs-badge{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:800;text-decoration:none;color:var(--brand);background:var(--brand-tint);border:1px solid var(--brand);border-radius:6px;padding:2px 8px;white-space:nowrap}
.srs-badge:hover{box-shadow:inset 0 0 0 1px var(--brand)}
.refs-lab{font-size:10.5px;font-weight:800;letter-spacing:.06em;color:var(--ink-faint);margin-right:2px}
.refs-none{font-size:11.5px;color:var(--ink-faint);font-weight:600}
.refs-row{display:flex;flex-wrap:wrap;gap:7px;align-items:center;margin-top:2px}
/* kind 凡例 */
.kind-legend{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;margin:2px 0 14px;font-size:12px;color:var(--ink-soft)}
.kind-legend .kl{display:inline-flex;align-items:center;gap:6px}
/* §3 entity cards */
[data-component="entity-catalog-grid"]{display:grid;grid-template-columns:repeat(2,1fr);gap:16px;margin:8px 0}
[data-component="entity-card"]{border:1px solid var(--line);border-radius:14px;background:var(--paper);box-shadow:var(--shadow);padding:16px 18px 15px;display:flex;flex-direction:column;gap:11px;position:relative;overflow:hidden}
[data-component="entity-card"].sens-high{border-color:var(--bad-line)}
[data-component="entity-card"].sens-high::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:var(--bad)}
.ec-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap}
.ec-name{font-size:17px;font-weight:800;color:var(--ink);line-height:1.3}
.ec-kind{font-size:10px;font-weight:800;letter-spacing:.06em;padding:2px 8px;border-radius:6px;border:1px solid}
.ec-kind.master{background:var(--brand-tint);color:var(--brand);border-color:var(--brand)}
.ec-kind.event{background:var(--violet-tint);color:var(--violet);border-color:var(--violet-line)}
.ec-sens{font-size:10px;font-weight:800;letter-spacing:.04em;text-decoration:none;padding:2px 9px;border-radius:999px;background:var(--bad-tint);color:var(--bad);border:1px solid var(--bad-line);display:inline-flex;align-items:center;gap:4px}
.ec-sens:hover{box-shadow:inset 0 0 0 1px var(--bad)}
.ec-desc{font-size:13px;color:var(--ink-soft);line-height:1.65;margin:0}
.ec-tblwrap{border:1px solid var(--line);border-radius:9px;overflow-x:auto}
.ec-fields{width:100%;border-collapse:separate;border-spacing:0;font-size:12.5px;min-width:340px}
.ec-fields thead th{background:var(--paper-3);text-align:left;font-size:10px;font-weight:800;letter-spacing:.05em;color:var(--ink-soft);padding:7px 10px;text-transform:uppercase}
tr[data-component="entity-field-row"] td{padding:8px 10px;border-bottom:1px solid var(--line-soft);vertical-align:top;line-height:1.5}
tr[data-component="entity-field-row"]:last-child td{border-bottom:none}
.ef-name{font-weight:800;color:var(--ink);white-space:nowrap}
.ef-type{font-size:10px;font-weight:800;padding:1px 7px;border-radius:5px;border:1px solid;background:var(--paper-3);color:var(--ink-soft);border-color:var(--line);white-space:nowrap}
.ef-type.ref{background:var(--info-tint);color:var(--info);border-color:var(--info-line)}
.ef-type.id{background:var(--brand-tint);color:var(--brand);border-color:var(--brand)}
.ef-req{font-size:9.5px;font-weight:800;padding:1px 6px;border-radius:5px;background:var(--bad-tint);color:var(--bad);border:1px solid var(--bad-line);white-space:nowrap}
.ef-note{font-size:11.5px;color:var(--ink-faint);line-height:1.5}
.ec-plain{font-size:12.5px;color:var(--ink-soft);background:var(--paper-2);border-radius:8px;padding:8px 11px;line-height:1.7;margin:0}
.ec-plain::before{content:"やさしく言うと ";font-weight:700;font-size:10px;color:var(--brand)}
/* §4 relationships */
[data-component="relationship-list"]{display:flex;flex-direction:column;gap:13px;margin:8px 0}
[data-component="relationship-row"]{border:1px solid var(--line);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);padding:14px 17px;display:flex;flex-direction:column;gap:9px}
[data-component="relationship-row"].has-invariant{border-left:5px solid var(--ok)}
.rel-head{display:flex;align-items:center;gap:11px;flex-wrap:wrap}
.rel-id{font-weight:800;font-size:11.5px;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:6px;padding:2px 8px;white-space:nowrap}
.rel-flow{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:14px}
.rel-ent{font-weight:800;color:var(--ink);background:var(--paper-2);border:1px solid var(--line);border-radius:8px;padding:3px 10px}
.rel-verb{font-size:11.5px;font-weight:700;color:var(--brand);display:inline-flex;align-items:center;gap:6px}
.rel-verb .ar{color:var(--ink-faint);font-weight:800;font-size:13px}
.rel-card{margin-left:auto;font-size:11.5px;font-weight:800;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:999px;padding:3px 11px;white-space:nowrap}
.rel-plain{font-size:13px;color:var(--ink-soft);line-height:1.65;margin:0}
[data-component="invariant-callout"]{display:flex;gap:10px;align-items:flex-start;background:var(--ok-tint);border:1px solid var(--ok-line);border-left:5px solid var(--ok);border-radius:10px;padding:11px 14px}
[data-component="invariant-callout"] .iv-lab{flex:0 0 auto;font-size:10px;font-weight:800;letter-spacing:.06em;color:var(--ok);background:var(--paper);border:1px solid var(--ok-line);border-radius:5px;padding:2px 8px;margin-top:1px;white-space:nowrap}
[data-component="invariant-callout"] .iv-txt{font-size:13px;font-weight:700;color:var(--ink);line-height:1.6}
/* §5 data policy */
[data-component="data-policy-grid"]{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:8px 0}
[data-component="data-policy-card"]{border:1px solid var(--line);border-left:5px solid var(--warn);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);padding:15px 17px;display:flex;flex-direction:column;gap:9px}
.dp-head{display:flex;align-items:baseline;gap:9px}
.dp-id{font-weight:800;font-size:12px;color:var(--warn);background:var(--warn-tint);border:1px solid var(--warn-line);border-radius:6px;padding:2px 8px}
.dp-rule{font-size:14.5px;font-weight:800;line-height:1.5;margin:0;color:var(--ink)}
.dp-reason{font-size:12.5px;color:var(--ink-faint);line-height:1.7;margin:0}
.dp-reason::before{content:"↳ なぜ ";font-weight:700;color:var(--warn)}
.dp-refs{margin-top:auto}
/* §5 原則終端 (arch の principle-terminal と同型) */
[data-component="principle-terminal"]{margin:12px 0 0;border:1px solid var(--violet-line);border-radius:12px;padding:13px 16px;background:var(--violet-tint)}
.pt-label{font-size:10.5px;font-weight:800;letter-spacing:.08em;color:var(--violet);background:var(--paper);border:1px solid var(--violet-line);border-radius:5px;padding:1px 7px;margin-right:8px}
.pt-id{font-weight:800;font-size:12.5px;color:var(--violet);font-family:ui-monospace,monospace}
.pt-text{font-size:13.5px;color:var(--ink-soft);line-height:1.75;margin:7px 0 0}
/* data-model 固有 responsive */
@media(max-width:1080px){ [data-component="data-policy-grid"]{grid-template-columns:1fr} }
@media(max-width:900px){ [data-component="entity-catalog-grid"]{grid-template-columns:1fr} }
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="data-model">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio data-model-pack assembler (folio-1q8o / instance#1) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_datamodel_css
  printf '\n</style>\n'
  core_emit_graph_head
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このデータモデルが約束すること (1 文サマリ)"
  local n_ent n_rel
  n_ent="$(q '.entities | length')"; n_rel="$(q '.relationships | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">構成</span><span class="v">%s</span></span><span class="m"><span class="k">照会先</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "data-model (データモデル)" "$(esc "情報のかたまり ${n_ent} / つながり ${n_rel}")" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  # ★cross-doc 前方照会の可視チップ (照会先 SRS の要件・案A)。 CJK 規律: <b> 閉じ直後に助詞なし ((FR / NFR) は ASCII 括弧)。
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の要件 (FR / NFR)</div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# ER 図 emit (raw DSL を esc して <pre class="mermaid"> へ join。 クロウフット記法凡例を固定 chrome として emit・raw DSL 露出 = blocker・folio-97z)。
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
  printf '</pre>\n'
  # クロウフット記法凡例 (固定 chrome・線端記号を平易語に翻訳。 repro-build byte-identity が改竄を捕捉)。
  cat <<'LEGEND'
<div class="er-legend" data-component="er-notation-legend" aria-label="線の端の記号の読み方">
<span class="ell-title">線の端の記号の読み方</span>
<span class="ell"><svg class="ell-ico" viewBox="0 0 40 18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><line x1="2" y1="9" x2="38" y2="9"/><line x1="25" y1="3.5" x2="25" y2="14.5"/><line x1="31" y1="3.5" x2="31" y2="14.5"/></svg><span class="ell-txt"><b>ちょうど 1 つ</b></span></span>
<span class="ell"><svg class="ell-ico" viewBox="0 0 40 18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><line x1="2" y1="9" x2="38" y2="9"/><circle cx="22" cy="9" r="4"/><line x1="32" y1="3.5" x2="32" y2="14.5"/></svg><span class="ell-txt"><b>0 か 1 つ</b></span></span>
<span class="ell"><svg class="ell-ico" viewBox="0 0 40 18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><line x1="2" y1="9" x2="23" y2="9"/><circle cx="14" cy="9" r="3.8"/><path d="M23 9 L38 3 M23 9 L38 9 M23 9 L38 15"/></svg><span class="ell-txt"><b>いくつでも</b> (0 以上)</span></span>
<span class="ell-note">→ だから「診療枠 — 予約」の線は〈ちょうど 1 つ〉対〈0 か 1 つ〉＝<b>最大 1 件</b>。 これが二重予約をデータの形で封じる要です。</span>
</div>
LEGEND
  printf '<figcaption><span class="diag-tag">%s</span>%s</figcaption>\n</figure>\n' "$(esc "$tag")" "$(esc "$cap")"
}

# §1 課題と範囲
emit_context() {
  printf '<p data-component="context-problem">%s</p>\n' "$(mark_terms "$(q '.context.problem')")"
  printf '<div data-component="scope-note-callout"><span class="sn-lab">この文書の範囲</span>%s</div>\n' "$(esc "$(q '.context.scope_note')")"
}

# §2 全体図 (ER 図)
emit_overview() { emit_diagram D1; }

# refs-row emit (照会 SRS バッジ or 「—」)。 $1=srs_html $2=refs の yq expr $3=(任意) 追加 class
emit_refs_row() {
  local srs_html="$1" refs_expr="$2" extra="${3:-}"
  local -a R; mapfile -t R < <(q "$refs_expr")
  printf '<div class="refs-row%s"><span class="refs-lab">照会 (SRS)</span>' "$extra"
  if [[ "${#R[@]}" -eq 0 ]]; then
    printf '<span class="refs-none">—</span>'
  else
    local r
    for r in "${R[@]}"; do
      [[ -n "$r" ]] || continue
      printf '<a class="srs-badge" href="%s#%s" data-dm-ref="%s" data-dm-role="claim">%s</a>' \
        "$(esc "$srs_html")" "$(esc "$r")" "$(esc "$r")" "$(esc "$r")"
    done
  fi
  printf '</div>\n'
}

# §3 情報のかたまり (entity cards)
emit_entities() {
  local SRS_HTML; SRS_HTML="$(q '.cross_doc.srs_html')"
  printf '<div class="kind-legend"><span class="kl"><span class="ec-kind master">台帳</span> = ずっと使う土台の情報</span><span class="kl"><span class="ec-kind event">記録</span> = できごとの記録</span><span class="kl"><span class="ec-sens" style="cursor:default">特に慎重に扱う情報</span> = とくに慎重に扱う個人情報</span></div>\n'
  printf '<div data-component="entity-catalog-grid">\n'
  local -a EIDS; mapfile -t EIDS < <(q '.entities[].id')
  local eid kind klabel sens acls sbadge
  for eid in "${EIDS[@]}"; do
    kind="$(q '.entities[] | select(.id=="'"$eid"'") | .kind')"; klabel="${ENT_KIND_LABEL[$kind]:-$kind}"
    sens="$(q '.entities[] | select(.id=="'"$eid"'") | .sensitivity')"
    acls=""; sbadge=""
    if [[ "$sens" == "high" ]]; then
      acls=" class=\"sens-high\""
      sbadge='<a class="ec-sens" href="#sec-data-policy"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>特に慎重に扱う情報</a>'
    fi
    printf '<article data-component="entity-card"%s id="entity-%s">\n' "$acls" "$(esc "$eid")"
    printf '<div class="ec-head"><span class="ec-name">%s</span><span class="ec-kind %s">%s</span>%s</div>\n' \
      "$(esc "$(q '.entities[] | select(.id=="'"$eid"'") | .name')")" "$(esc "$kind")" "$(esc "$klabel")" "$sbadge"
    printf '<p class="ec-desc">%s</p>\n' "$(mark_terms "$(q '.entities[] | select(.id=="'"$eid"'") | .description')")"
    printf '<div class="ec-tblwrap"><table class="ec-fields"><thead><tr><th>項目</th><th>型</th><th>必須</th><th>説明</th></tr></thead><tbody>\n'
    local fname ftype freq fnote tclass rqcell
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      fname="${line%%$'\t'*}"; rest="${line#*$'\t'}"; ftype="${rest%%$'\t'*}"; rest2="${rest#*$'\t'}"; freq="${rest2%%$'\t'*}"; fnote="${rest2#*$'\t'}"
      tclass="ef-type"; case "$ftype" in 識別子) tclass="ef-type id" ;; 参照) tclass="ef-type ref" ;; esac
      if [[ "$freq" == "true" ]]; then rqcell='<span class="ef-req">必須</span>'; else rqcell='<span class="ef-note">任意</span>'; fi
      printf '<tr data-component="entity-field-row"><td class="ef-name">%s</td><td><span class="%s">%s</span></td><td>%s</td><td class="ef-note">%s</td></tr>\n' \
        "$(esc "$fname")" "$(esc "$tclass")" "$(esc "$ftype")" "$rqcell" "$(esc "$fnote")"
    done < <(q '.entities[] | select(.id=="'"$eid"'") | .fields[] | [.name, .type, (.required|tostring), (.note // "")] | @tsv')
    printf '</tbody></table></div>\n'
    emit_refs_row "$SRS_HTML" '.entities[] | select(.id=="'"$eid"'") | .refs.srs[]'
    printf '<p class="ec-plain" data-prose-slot="plain" data-slot-id="plain-%s"></p>\n' "$(esc "$eid")"
    printf '</article>\n'
  done
  printf '</div>\n'
}

# §4 つながりと決まり (relationship rows)
emit_relationships() {
  local SRS_HTML; SRS_HTML="$(q '.cross_doc.srs_html')"
  printf '<div data-component="relationship-list">\n'
  local -a RIDS; mapfile -t RIDS < <(q '.relationships[].id')
  local rid frm to card clab lbl inv nrefs hasinv
  for rid in "${RIDS[@]}"; do
    frm="$(q '.relationships[] | select(.id=="'"$rid"'") | .from')"; to="$(q '.relationships[] | select(.id=="'"$rid"'") | .to')"
    card="$(q '.relationships[] | select(.id=="'"$rid"'") | .cardinality')"; clab="${CARD_LABEL[$card]:-$card}"
    lbl="$(q '.relationships[] | select(.id=="'"$rid"'") | .label')"
    inv="$(q '.relationships[] | select(.id=="'"$rid"'") | .invariant // ""')"
    nrefs="$(q '.relationships[] | select(.id=="'"$rid"'") | .refs.srs | length')"
    hasinv=""; [[ -n "$inv" ]] && hasinv=' class="has-invariant"'
    printf '<article data-component="relationship-row"%s id="rel-%s">\n' "$hasinv" "$(esc "$rid")"
    printf '<div class="rel-head"><span class="rel-id">%s</span><span class="rel-flow"><span class="rel-ent">%s</span><span class="rel-verb"><span class="ar">—</span>%s<span class="ar">→</span></span><span class="rel-ent">%s</span></span><span class="rel-card">%s</span></div>\n' \
      "$(esc "$rid")" "$(esc "$(q '.entities[] | select(.id=="'"$frm"'") | .name')")" "$(esc "$lbl")" "$(esc "$(q '.entities[] | select(.id=="'"$to"'") | .name')")" "$(esc "$clab")"
    printf '<p class="rel-plain">%s</p>\n' "$(mark_terms "$(q '.relationships[] | select(.id=="'"$rid"'") | .plain')")"
    if [[ -n "$inv" ]]; then
      printf '<div data-component="invariant-callout"><span class="iv-lab">不変条件</span><span class="iv-txt">%s</span></div>\n' "$(mark_terms "$inv")"
    fi
    if [[ "$nrefs" != "0" ]]; then
      emit_refs_row "$SRS_HTML" '.relationships[] | select(.id=="'"$rid"'") | .refs.srs[]'
    fi
    printf '</article>\n'
  done
  printf '</div>\n'
}

# §5 データの扱い (data-policy cards + 原則終端)
emit_data_policy() {
  local SRS_HTML; SRS_HTML="$(q '.cross_doc.srs_html')"
  printf '<div data-component="data-policy-grid" id="sec-data-policy">\n'
  local -a DIDS; mapfile -t DIDS < <(q '.data_policy[].id')
  local dpid
  for dpid in "${DIDS[@]}"; do
    printf '<div data-component="data-policy-card" id="dp-%s">\n' "$(esc "$dpid")"
    printf '<div class="dp-head"><span class="dp-id">%s</span></div>\n' "$(esc "$dpid")"
    printf '<p class="dp-rule">%s</p>\n' "$(mark_terms "$(q '.data_policy[] | select(.id=="'"$dpid"'") | .rule')")"
    printf '<p class="dp-reason">%s</p>\n' "$(mark_terms "$(q '.data_policy[] | select(.id=="'"$dpid"'") | .reason')")"
    emit_refs_row "$SRS_HTML" '.data_policy[] | select(.id=="'"$dpid"'") | .refs.srs[]' " dp-refs"
    printf '</div>\n'
  done
  printf '</div>\n'
  # 原則終端 panel (照会 graph の終端・within-doc anchor target)
  printf '<div data-component="principle-terminal" id="principle-%s"><span class="pt-label">貫く原則</span><span class="pt-id">%s</span><p class="pt-text">%s</p></div>\n' \
    "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.text')")"
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

emit_footer() {
  core_emit_footer '<span>folio design system</span><span>data-model-pack</span><span>folio engine post-B6 (instance#1)</span><span>entity catalog + ER + cross-doc 照会 graph</span>'
}

# mermaid render JS (defer 済みで window.mermaid 利用可・ER 図を SVG へ。 no-JS では pre が読める fallback)。
emit_mermaid_js() {
  printf '<script src="assets/mermaid.min.js" defer></script>\n'
  cat <<'JS'
<script>
window.addEventListener('DOMContentLoaded', async () => {
  if (!window.mermaid) return;
  mermaid.initialize({
    startOnLoad: false, securityLevel: 'antiscript', theme: 'base',
    flowchart: { useMaxWidth: true }, sequence: { useMaxWidth: true }, er: { useMaxWidth: true },
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
  band info   "課題と範囲"        "なぜ「情報の持ち方」を先に決めるのか"       "$ICO_SCOPE";  emit_context;       band_end
  band ok     "全体図"            "全体像を一枚の ER 図で見渡す"               "$ICO_GRAPH";  emit_overview;      band_end
  # ★entities/relationships の band 見出しは contract .chapters.* 由来 (instance 固有の件数を code に焼かない・folio-bhe)。 他 4 章は pack 不変文言。
  band brand  "情報のかたまり"    "$(q '.chapters.entities_band')"             "$ICO_BLOCKS"; emit_entities;      band_end
  band violet "つながりと決まり"  "$(q '.chapters.relationships_band')"        "$ICO_LINK";   emit_relationships; band_end
  band warn   "データの扱い"      "何を持たず、 何のために使い、 いつ消すか"    "$ICO_SHIELD"; emit_data_policy;   band_end
  band violet "用語"              "本文に出てくる言葉のやさしい説明"           "$ICO_BOOK";   emit_glossary;      band_end
  printf '</div>\n'
  emit_footer
  emit_mermaid_js
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-datamodel"
