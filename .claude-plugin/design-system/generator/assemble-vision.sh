#!/usr/bin/env bash
# folio 文書規律エンジン roadmap 段階3 後 (folio-c5r.4) — vision-pack 決定的 assembler (instance#1 / 記述型)
#
# 入力 vision contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# 記述型 (descriptive) doc-type の 2 例目 (arch = 1 例目)。 schema = Pichler Product Vision Board の骨 +
# Wiegers Vision&Scope の測定可能要素を選抜移植した lean hybrid。 7 章 (北極星 / 問題 / 関係者 /
# 目標+成功基準 / 機能方向 / リスク+非目標 / 指針価値)。 glossary 章は持たない (専門語は本文で括弧併記)。
#   - 構造・内容 (北極星 / 関係者 / 目標 / 成功基準 / 機能 / リスク / 原則) は contract から決定的組立。
#     元データに無い関係者・目標・機能・照会 edge は生成できない。
#   - ★cross-doc 前方照会 edge (案A = 別文書 link・再掲ゼロ): features[].refs.srs[] (claim) → SRS 要件。
#     validate() が *生成前に* 参照先 SRS contract 実在 + 当該 ID 実在を fail-closed で確かめる (集合外参照は拒否)。
#     問題/関係者/目標/非目標 の no-restate aside は SRS 章へ *文書単位照会* ((b) 形)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 for_goal・pitch dangling は拒否。
#   - prose スロット (cover-summary / 章リード chapter-lead-NN) は *空* で出力し ③ inject-prose.sh が充填。
#   - 北極星文・叙述本体・機能の方向は決定的値 (捏造/歪みは fidelity ceiling = folio-5se の検査対象)。
#   - Moore pitch (opt-in) / 目標ツリー図 (optional) は contract に在る時だけ描画 (必須化しない・grill 論点5)。
#   - goal_tree の mermaid 図は raw DSL を esc して <pre class="mermaid"> へ join 出力 (raw DSL 露出 = gate I blocker)。
#
# ★章数は CHAP_SPECS 配列 (単一 SSoT) から再導出する。 「== 7」の magic number を blind copy しない
#   (folio-bhe ceiling wf_966c2160 教訓: verify-arch の arc42 専用「==8」が vision へ流用時に破綻した反面教師)。
# ★band 見出し (h2) は pack 不変 (件数/ドメイン非依存) ゆえ CHAP_SPECS に置く (arch の components「N つの部品」の
#   ような instance 固有件数を見出しに焼かない = 予防規律・grill 論点6)。 cover の構成件数は配列長から導出。
#
# inject-prose.sh は SRS/ADR/arch と共通 (data-slot-id ベースで pack 非依存)。 core (lib/ + inject-prose.sh) は無改変。
#
# usage: assemble-vision.sh <vision-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-vision.sh <vision-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-vision: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-vision: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-vision: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/band/cover骨格/approval/footer/finalize) ----
source "$SCRIPT_DIR/lib/common.sh"
# vision は glossary 章を持たない (専門語は本文で括弧併記) ゆえ term-inline は使わず esc 直で描画する。

# ★cross-doc 照会は opt-in (folio-qvv 裁定A 2026-07-04): .cross_doc 節が contract に在れば従来の全検査 + 全描画
#   (KV/chip/no-restate aside/feature 照会行/non-goals 照会リンク)、 無ければ照会痕跡ゼロで出力する。
#   SRS を持たない instance (folio-self) が照会を捏造せず honest に立つための pack 汎化 (pitch/goal_tree opt-in と
#   同精神)。 片肺 contract (cross_doc なしで refs.srs/no_restate/srs_code が残存) は validate() が fail-closed で拒否。
#   verify-vision.sh が同じ opt-in 単位で非発火の痕跡ゼロを検査する (detect↔verify parity)。
XDOC="$(q 'has("cross_doc")')"
# ★instance 出自タグは hardcode せず contract (.footer.instance_tag) から取る (folio-c5r.3 ceiling blocker の恒久処方
#   を vision へ横展開: instance#2 成果物が虚偽の出自 instance#1 を表示し gen-meta と自己矛盾するのを防ぐ)。
#   head <meta generator> と footer tag 列の 2 箇所に埋まる。 validate() が非空を強制 (fail-closed)。
ITAG="$(q '.footer.instance_tag')"

# ---- icon SVG (vision-pack 固有。 共用 ICO_SHIELD/USER は lib/common.sh) ----
ICO_STAR='<path d="M12 2l2.4 6.9H22l-5.8 4.2 2.2 6.9-6.4-4.2-6.4 4.2 2.2-6.9L2 8.9h7.6z"/>'
ICO_ALERT='<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>'
ICO_USERS='<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>'
ICO_TARGET='<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>'
ICO_PLUG='<path d="M14.7 6.3a5 5 0 0 0-7.07 7.07l-4.35 4.35a1.5 1.5 0 0 0 2.12 2.12l4.35-4.35a5 5 0 0 0 7.07-7.07l-2.83 2.83-2.12-2.12z"/>'
ICO_BAN='<circle cx="12" cy="12" r="10"/><path d="M4.9 4.9l14.2 14.2"/>'

# ★章定義 (単一 SSoT)。 各行: tint|kicker|heading|icon|emitter。 heading (h2) は pack 不変文言
#   (件数/ドメイン非依存 = instance hardcode でない)。 章数 NCHAP はこの配列長から導出する (magic「==7」禁止)。
#   区切りは | (SVG path/日本語に | は現れない)。 emitter は build() が動的呼び出しする。
CHAP_SPECS=(
  "brand|北極星|目指す状態を、 一文で言い切る|${ICO_STAR}|emit_north_star"
  "warn|解くに値する問題|なぜ、 いま作るのか|${ICO_ALERT}|emit_problem"
  "violet|誰のためのビジョンか|関係者と、 それぞれが得るもの|${ICO_USERS}|emit_stakeholders"
  "ok|目標と成功基準|北極星を、 測れる形に割る|${ICO_TARGET}|emit_objectives"
  "info|主要機能の方向|何を作るか — 方向だけを約束する|${ICO_PLUG}|emit_features"
  "bad|リスクと非目標|うまくいかない道と、 あえて行かない道|${ICO_BAN}|emit_risks"
  "violet|指針価値|迷ったとき、 どちらへ倒すか|${ICO_SHIELD}|emit_principle"
)
NCHAP="${#CHAP_SPECS[@]}"

# ---- fail-closed contract validation ----
validate() {
  local errs=0
  core_validate_strings "assemble-vision" || errs=1
  # doc_type guard (vision-pack の identity・誤 contract 混入を拒否)
  [[ "$(q '.doc_type')" == "vision" ]] || { echo "assemble-vision: doc_type が vision でない: $(q '.doc_type')" >&2; errs=1; }
  # id 一意性 (stakeholders / objectives / success_criteria / features / risks)
  local axis d
  for axis in '.stakeholders.entries[].id' '.objectives[].id' '.success_criteria.entries[].id' '.features[].id' '.risks[].id'; do
    d="$(q "$axis" | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-vision: id 重複 ($axis): $d" >&2; errs=1; }
  done
  # success_criteria.for_goal ⊆ objectives.id (物差しが実在しない目標を指すのを拒否)
  local scmissing
  scmissing="$(comm -23 <(q '.success_criteria.entries[].for_goal' | sort -u) <(q '.objectives[].id' | sort -u))"
  [[ -z "$scmissing" ]] || { echo "assemble-vision: ★success_criteria.for_goal の dangling: objectives に実在しない: $scmissing" >&2; errs=1; }

  # ★cross-doc 前方照会 (opt-in・qvv 裁定A): cross_doc 節が在れば終端解決を全検査 (SRS 実在 + doc_id 一致 +
  #   dangling 0 + 空 ref 禁止)、 無ければ照会系 key の残存を拒否 (非発火なのに照会データがある片肺 contract を fail-closed)。
  local srs_rel srs_abs srs_docid expect_docid missing n_srs n_srs_ne sect
  n_srs="$(q '[.features[].refs.srs[]] | length')"
  if [[ "$XDOC" == "true" ]]; then
    srs_rel="$(q '.cross_doc.srs_contract')"; srs_abs="${CONTRACT_DIR}/${srs_rel}"
    if [[ ! -f "$srs_abs" ]]; then
      echo "assemble-vision: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
    else
      srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"; expect_docid="$(q '.cross_doc.srs_doc_id')"
      [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-vision: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
      n_srs_ne="$(q '[ .features[].refs.srs[] | select((. // "") != "") ] | length')"
      [[ "$n_srs" == "$n_srs_ne" ]] || { echo "assemble-vision: ★SRS 照会の空 ref (有効 $n_srs_ne/$n_srs 件・空/null は壊れた前方参照ゆえ禁止)" >&2; errs=1; }
      missing="$(comm -23 <(q '.features[].refs.srs[]' | sort -u) <(yq -r '.requirements[].id' "$srs_abs" | sort -u))"
      [[ -z "$missing" ]] || { echo "assemble-vision: ★SRS 照会の dangling: refs.srs が SRS 要件に実在しない: $missing" >&2; errs=1; }
    fi
  else
    [[ "$n_srs" == "0" ]] || { echo "assemble-vision: ★cross_doc 節なしで SRS 照会 (refs.srs) が $n_srs 件 (opt-in 片肺 contract・非発火なら refs.srs は空配列 [] を明示)" >&2; errs=1; }
    for sect in problem stakeholders success_criteria; do
      [[ "$(q ".${sect} | has(\"no_restate\")")" == "false" ]] || { echo "assemble-vision: ★cross_doc 節なしで .${sect}.no_restate が存在 (opt-in 片肺 contract)" >&2; errs=1; }
    done
    { [[ "$(q '.non_goals | has("srs_code")')" == "false" ]] && [[ "$(q '.non_goals | has("srs_label")')" == "false" ]]; } \
      || { echo "assemble-vision: ★cross_doc 節なしで .non_goals.srs_code/srs_label が存在 (opt-in 片肺 contract)" >&2; errs=1; }
  fi

  # principle 終端: id/text 必須 (照会 graph の終端・空だと終端不備)
  [[ -n "$(q '.principle.id // ""')" ]]   || { echo "assemble-vision: principle.id 欠落 (照会 graph の終端が無い)" >&2; errs=1; }
  [[ -n "$(q '.principle.text // ""')" ]] || { echo "assemble-vision: principle.text 欠落" >&2; errs=1; }

  # instance 出自タグ: 非空必須 (hardcode 復活・欠落による虚偽出自を fail-closed で拒否・c5r.3 恒久処方)
  [[ -n "$ITAG" && "$ITAG" != "null" ]] || { echo "assemble-vision: .footer.instance_tag 欠落 (instance 出自タグは contract 由来・hardcode 禁止)" >&2; errs=1; }

  # ★pitch (opt-in) の内部照会 anchor 実在検証: pitch.rows[].ref_anchor ⊆ {本文の生成 anchor 集合} (dangling 内部 link を拒否)。
  #   生成 anchor = northstar / problem / st-<n> / g-<n> / sc-<n> / f-<n> / r-<n> / principle-<id> (build と同一導出)。
  local np
  np="$(q '.pitch.rows // [] | length')"
  if [[ "$np" != "0" ]]; then
    local -a VALID_ANCHORS=(northstar problem)
    local _id
    for _id in $(q '.stakeholders.entries[].id');      do VALID_ANCHORS+=("${_id,,}"); done
    for _id in $(q '.objectives[].id');                do VALID_ANCHORS+=("${_id,,}"); done
    for _id in $(q '.success_criteria.entries[].id');  do VALID_ANCHORS+=("${_id,,}"); done
    for _id in $(q '.features[].id');                  do VALID_ANCHORS+=("${_id,,}"); done
    for _id in $(q '.risks[].id');                     do VALID_ANCHORS+=("${_id,,}"); done
    VALID_ANCHORS+=("principle-$(q '.principle.id')")
    local anc ok ra
    while IFS= read -r ra; do
      [[ -n "$ra" ]] || continue
      ok=0; for anc in "${VALID_ANCHORS[@]}"; do [[ "$ra" == "$anc" ]] && { ok=1; break; }; done
      [[ "$ok" -eq 1 ]] || { echo "assemble-vision: ★pitch.ref_anchor の dangling 内部照会: #$ra は本文 anchor に実在しない" >&2; errs=1; }
    done < <(q '.pitch.rows[].ref_anchor')
  fi

  [[ "$errs" -eq 0 ]] || { echo "assemble-vision: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- vision-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従。 arch と共有する終端/照会/図の
#      視覚語彙 = principle-terminal / xref / ad-ref-row / figure.diagram は各 pack 独立に持つ = pack 境界) ----
emit_vision_css() {
  cat <<'CSS'
/* ===== vision-pack 固有部品 (folio-c5r.4 / instance#1)。 srs.css の token を流用 ===== */
/* §1 北極星 */
[data-component="vision-north-star"]{margin:18px 0;padding:26px 28px;border-radius:16px;background:linear-gradient(135deg,var(--brand-tint),var(--paper));border:1px solid var(--brand);text-align:center}
.vm-ns-label{font-size:11.5px;font-weight:800;letter-spacing:.12em;color:var(--brand);margin:0 0 10px}
.vm-ns-text{font-size:22px;font-weight:900;line-height:1.7;margin:0;color:var(--ink)}
[data-component="vision-pitch-grammar"]{margin:20px 0 6px;border:1px dashed var(--line);border-radius:14px;padding:16px 18px;background:var(--paper-2)}
.vm-pg-title{font-size:12px;color:var(--ink-soft);margin:0 0 10px}
.vm-pg-row{display:flex;gap:10px;align-items:baseline;padding:7px 0;border-top:1px solid var(--line-soft);flex-wrap:wrap}
.vm-pg-k{flex:0 0 92px;font-size:11.5px;font-weight:800;color:var(--brand)}
.vm-pg-v{flex:1 1 300px;font-size:13.5px;line-height:1.7}
.vm-pg-ref{font-size:11px;text-decoration:none;color:var(--ink-soft);border:1px solid var(--line);border-radius:999px;padding:1px 8px;white-space:nowrap}
.vm-pg-ref:hover{background:var(--brand-tint)}
/* §3/§4/§6 カード (関係者/目標/成功基準/リスク) */
.vm-card{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;align-items:baseline;border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:10px 0;background:var(--paper)}
.vm-cid{font-family:ui-monospace,monospace;font-weight:800;font-size:12px;border-radius:6px;padding:1px 8px;border:1px solid var(--violet-line);color:var(--violet);background:var(--violet-tint)}
.vm-card.obj .vm-cid{border-color:var(--ok-line);color:var(--ok);background:var(--ok-tint)}
.vm-card.sc .vm-cid{border-color:var(--brand);color:var(--brand);background:var(--brand-tint)}
.vm-card.risk .vm-cid{border-color:var(--bad-line);color:var(--bad);background:var(--bad-tint)}
.vm-ct{font-weight:800;font-size:14.5px}
.vm-cd{grid-column:2;margin:0;font-size:13px;line-height:1.75;color:var(--ink-soft)}
.vm-sc-for{grid-column:2;font-size:11.5px;color:var(--brand);font-weight:700}
/* §5 機能カード */
.vm-feat{border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:10px 0;background:var(--paper)}
.vm-fh{display:flex;gap:10px;align-items:baseline;margin-bottom:4px}
.vm-feat .vm-cid{border-color:var(--info-line);color:var(--info);background:var(--info-tint)}
.vm-feat .vm-cd{margin:0 0 8px;font-size:13px;line-height:1.75;color:var(--ink-soft)}
/* no-restate aside / 非目標 */
[data-component="no-restate-note"]{margin:14px 0 4px;padding:10px 14px;border-left:3px solid var(--line);background:var(--paper-2);border-radius:0 10px 10px 0;font-size:12.5px;line-height:1.8;color:var(--ink-soft)}
[data-component="vision-non-goals"]{margin:16px 0 4px;border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper-2)}
.vm-ng-title{font-size:12px;font-weight:800;color:var(--ink);margin:0 0 6px}
[data-component="vision-non-goals"] p{margin:0;font-size:13px;line-height:1.8}
/* 照会チップ (SRS 前方照会・arch と同じ視覚語彙・claim ロール) */
.ad-ref-row{display:flex;gap:8px;align-items:baseline;flex-wrap:wrap;margin-top:2px}
.ad-ref-lab{flex:0 0 auto;font-size:11px;font-weight:800;color:var(--ok)}
.xref-link{display:inline-flex;align-items:baseline;gap:5px;text-decoration:none;border-radius:6px;padding:1px 4px;margin-right:3px}
.xref-link:hover{background:var(--brand-tint)}
.xref-code{font-weight:800;font-size:12px;border-radius:6px;padding:1px 8px;border:1px solid;color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.xref-label{font-size:11.5px;color:var(--ink-soft);line-height:1.5}
/* §7 原則終端 (arch と同じ視覚語彙) */
[data-component="principle-terminal"]{margin:12px 0 0;border:1px solid var(--violet-line);border-radius:12px;padding:13px 16px;background:var(--violet-tint)}
.pt-label{font-size:10.5px;font-weight:800;letter-spacing:.08em;color:var(--violet);background:var(--paper);border:1px solid var(--violet-line);border-radius:5px;padding:1px 7px;margin-right:8px}
.pt-id{font-weight:800;font-size:12.5px;color:var(--violet);font-family:ui-monospace,monospace}
.pt-text{font-size:13.5px;color:var(--ink-soft);line-height:1.75;margin:7px 0 0}
/* 目標ツリー図 (mermaid render target・arch と同じ figure.diagram 視覚語彙) */
figure.diagram{margin:14px 0;border:1px solid var(--line);border-radius:12px;background:var(--paper);box-shadow:var(--shadow);overflow:hidden}
figure.diagram .mermaid{margin:0;padding:14px 10px;overflow-x:auto;text-align:center}
figure.diagram .mermaid:not([data-processed]){font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;line-height:1.55;white-space:pre;text-align:left;color:var(--ink-soft);background:var(--paper-2);border-radius:10px}
figure.diagram figcaption{padding:11px 15px 13px;font-size:12px;color:var(--ink-faint);border-top:1px dashed var(--line);background:var(--paper);line-height:1.6}
.diag-tag{display:inline-block;font-size:10px;font-weight:800;letter-spacing:.06em;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:5px;padding:1px 7px;margin-right:7px}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="vision">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' "$(esc "$(q '.meta.doc_id')")"
  printf '<meta name="generator" content="folio vision-pack assembler (folio-c5r.4 / %s) — deterministic structure, prose slots unfilled">\n' "$(esc "$ITAG")"
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_vision_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "このビジョンが約束すること (1 文サマリ)"
  # 構成件数は各配列長から導出 (instance hardcode 禁止・folio-bhe 予防規律)。 章数は CHAP_SPECS 由来 NCHAP。
  local n_g n_sc n_f n_st n_r
  n_g="$(q '.objectives | length')"; n_sc="$(q '.success_criteria.entries | length')"
  n_f="$(q '.features | length')"; n_st="$(q '.stakeholders.entries | length')"; n_r="$(q '.risks | length')"
  if [[ "$XDOC" == "true" ]]; then
    printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">構成</span><span class="v">%s</span></span><span class="m"><span class="k">照会先</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
      "vision (ビジョン — なぜ作るか)" "$(esc "${NCHAP} 章 (目標 ${n_g} / 成功基準 ${n_sc} / 機能方向 ${n_f} / 関係者 ${n_st} / リスク ${n_r} / 原則 1)")" \
      "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
    # ★cross-doc 前方照会の可視チップ (照会先 SRS の要件・受入基準・案A)。 ★CJK 規律: <b> 閉じ直後に助詞 (の) を空白なしで置く。
    printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 照会先: <b>%s</b>の要件・受入基準 (このビジョンの「何を作るか」の具体)</div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")"
  else
    # 非発火 (opt-in): 照会先 KV と ref-chip を出さない (「無ければ出さない」= pitch/goal_tree と同じ痕跡ゼロ規律)。
    printf '<div class="cover-meta"><span class="m"><span class="k">種別</span><span class="v">%s</span></span><span class="m"><span class="k">構成</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
      "vision (ビジョン — なぜ作るか)" "$(esc "${NCHAP} 章 (目標 ${n_g} / 成功基準 ${n_sc} / 機能方向 ${n_f} / 関係者 ${n_st} / リスク ${n_r} / 原則 1)")" \
      "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  fi
  core_emit_approval_block
  core_emit_cover_tail
}

# ---- §1 北極星 (vision-north-star + narrative + opt-in Moore pitch) ----
emit_north_star() {
  printf '<div data-component="vision-north-star" id="northstar"><p class="vm-ns-label">北極星 (このプロジェクトが目指す状態)</p><p class="vm-ns-text">%s</p></div>\n' \
    "$(esc "$(q '.north_star.text')")"
  printf '<p>%s</p>\n' "$(esc "$(q '.north_star.narrative')")"
  local np; np="$(q '.pitch.rows // [] | length')"
  if [[ "$np" != "0" ]]; then
    printf '<div data-component="vision-pitch-grammar"><p class="vm-pg-title">エレベーターピッチ (Moore 型の穴埋め — 任意: 埋めた場合は各穴と本文の章が対応します)</p>\n'
    q '.pitch.rows[] | [.key, .value, .ref_anchor, .ref_label] | @tsv' | while IFS=$'\t' read -r key value ranchor rlabel; do
      [[ -n "$key" ]] || continue
      printf '<div class="vm-pg-row"><span class="vm-pg-k">%s</span><span class="vm-pg-v">%s</span><a class="vm-pg-ref" href="#%s">↔ %s</a></div>\n' \
        "$(esc "$key")" "$(esc "$value")" "$(esc "$ranchor")" "$(esc "$rlabel")"
    done
    printf '</div>\n'
  fi
}

# ---- no-restate aside (本文末尾に SRS 照会チップを付す・(b) 文書単位照会) ----
# $1 = base jq path (例 '.problem.no_restate')  $2 = 追加 anchor (空可)
emit_no_restate() {
  local base="$1" anchor="${2:-}" href
  href="$(q '.cross_doc.srs_html')"; [[ -n "$anchor" ]] && href="${href}#${anchor}"
  printf '<aside data-component="no-restate-note">%s <a class="xref-link" href="%s"><span class="xref-code">%s</span><span class="xref-label">%s</span></a></aside>\n' \
    "$(esc "$(q "${base}.text")")" "$(esc "$href")" "$(esc "$(q "${base}.srs_code")")" "$(esc "$(q "${base}.srs_label")")"
}

# ---- §2 解くに値する問題 (narrative 段落 + no-restate → SRS §3) ----
emit_problem() {
  local first=1 p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ "$first" -eq 1 ]]; then printf '<p id="problem">%s</p>\n' "$(esc "$p")"; first=0
    else printf '<p>%s</p>\n' "$(esc "$p")"; fi
  done < <(q '.problem.paragraphs[]')
  if [[ "$XDOC" == "true" ]]; then emit_no_restate '.problem.no_restate'; fi
}

# ---- §3 関係者 (vision-stakeholder-list = ST-<n> カード + no-restate → SRS §2) ----
emit_stakeholders() {
  printf '<div data-component="vision-stakeholder-list">\n'
  local -a IDS; mapfile -t IDS < <(q '.stakeholders.entries[].id')
  local id
  for id in "${IDS[@]}"; do
    printf '<div class="vm-card" id="%s"><span class="vm-cid">%s</span><span class="vm-ct">%s</span><p class="vm-cd">%s</p></div>\n' \
      "$(esc "${id,,}")" "$(esc "$id")" \
      "$(esc "$(q '.stakeholders.entries[] | select(.id=="'"$id"'") | .name')")" \
      "$(esc "$(q '.stakeholders.entries[] | select(.id=="'"$id"'") | .gain')")"
  done
  printf '</div>\n'
  if [[ "$XDOC" == "true" ]]; then emit_no_restate '.stakeholders.no_restate'; fi
}

# ---- §4 目標 (vision-objective-list = G-<n>) + 成功基準 (vision-success-criteria = SC-<n>) + 目標ツリー図 (optional) ----
emit_objectives() {
  printf '<div data-component="vision-objective-list">\n'
  local -a GIDS; mapfile -t GIDS < <(q '.objectives[].id')
  local id
  for id in "${GIDS[@]}"; do
    printf '<div class="vm-card obj" id="%s"><span class="vm-cid">%s</span><span class="vm-ct">%s</span><p class="vm-cd">%s</p></div>\n' \
      "$(esc "${id,,}")" "$(esc "$id")" \
      "$(esc "$(q '.objectives[] | select(.id=="'"$id"'") | .name')")" \
      "$(esc "$(q '.objectives[] | select(.id=="'"$id"'") | .desc')")"
  done
  printf '</div>\n'
  printf '<div data-component="vision-success-criteria">\n'
  local -a SIDS; mapfile -t SIDS < <(q '.success_criteria.entries[].id')
  local fg
  for id in "${SIDS[@]}"; do
    fg="$(q '.success_criteria.entries[] | select(.id=="'"$id"'") | .for_goal')"
    printf '<div class="vm-card sc" id="%s"><span class="vm-cid">%s</span><span class="vm-ct">%s</span><p class="vm-cd">%s</p><span class="vm-sc-for">→ %s の物差し</span></div>\n' \
      "$(esc "${id,,}")" "$(esc "$id")" \
      "$(esc "$(q '.success_criteria.entries[] | select(.id=="'"$id"'") | .name')")" \
      "$(esc "$(q '.success_criteria.entries[] | select(.id=="'"$id"'") | .desc')")" "$(esc "$fg")"
  done
  printf '</div>\n'
  # 目標ツリー図 (optional・在る時だけ)
  local ntl; ntl="$(q '.goal_tree.lines // [] | length')"
  if [[ "$ntl" != "0" ]]; then
    printf '<figure class="diagram" data-component="goal-tree-diagram">\n<pre class="mermaid">'
    local gfirst=1 ln
    while IFS= read -r ln; do
      [[ "$gfirst" -eq 1 ]] || printf '\n'; gfirst=0
      printf '%s' "$(esc "$ln")"
    done < <(q '.goal_tree.lines[]')
    printf '</pre>\n<figcaption><span class="diag-tag">目標ツリー</span>%s</figcaption>\n</figure>\n' "$(esc "$(q '.goal_tree.caption')")"
  fi
  if [[ "$XDOC" == "true" ]]; then emit_no_restate '.success_criteria.no_restate' "$(q '.success_criteria.no_restate.srs_anchor // ""')"; fi
}

# ---- §5 主要機能の方向 (vision-feature-list = F-<n> + SRS 充足照会 claim 行) ----
emit_features() {
  printf '<div data-component="vision-feature-list">\n'
  local SRS_HTML; SRS_HTML="$(q '.cross_doc.srs_html')"
  local -a FIDS; mapfile -t FIDS < <(q '.features[].id')
  local id fr
  for id in "${FIDS[@]}"; do
    printf '<div class="vm-feat" id="%s"><div class="vm-fh"><span class="vm-cid">%s</span><span class="vm-ct">%s</span></div><p class="vm-cd">%s</p>\n' \
      "$(esc "${id,,}")" "$(esc "$id")" \
      "$(esc "$(q '.features[] | select(.id=="'"$id"'") | .name')")" \
      "$(esc "$(q '.features[] | select(.id=="'"$id"'") | .desc')")"
    if [[ "$XDOC" == "true" ]]; then
      printf '<div class="ad-ref-row claim"><span class="ad-ref-lab">実現する要件</span>'
      while IFS= read -r fr; do
        [[ -n "$fr" ]] || continue
        printf '<a class="xref-link" href="%s#%s" data-vision-ref="%s" data-vision-role="claim"><span class="xref-code">%s</span><span class="xref-label" data-srs-label-ref="%s">%s</span></a>' \
          "$(esc "$SRS_HTML")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "$fr")" "$(esc "${SRS_LABEL[$fr]}")"
      done < <(q '.features[] | select(.id=="'"$id"'") | .refs.srs[]')
      printf '</div>'
    fi
    printf '</div>\n'
  done
  printf '</div>\n'
}

# ---- §6 リスク (vision-risk-list = R-<n>) + 非目標 (vision-non-goals → SRS §2) ----
emit_risks() {
  printf '<div data-component="vision-risk-list">\n'
  local -a RIDS; mapfile -t RIDS < <(q '.risks[].id')
  local id
  for id in "${RIDS[@]}"; do
    printf '<div class="vm-card risk" id="%s"><span class="vm-cid">%s</span><span class="vm-ct">%s</span><p class="vm-cd">%s</p></div>\n' \
      "$(esc "${id,,}")" "$(esc "$id")" \
      "$(esc "$(q '.risks[] | select(.id=="'"$id"'") | .name')")" \
      "$(esc "$(q '.risks[] | select(.id=="'"$id"'") | .desc')")"
  done
  printf '</div>\n'
  # 非目標 (発火時は SRS 範囲章へ文書単位照会・非発火時は本文のみ = 照会痕跡ゼロ)
  printf '<div data-component="vision-non-goals"><p class="vm-ng-title">非目標 (このビジョンでは作らない、 と決めていること)</p>\n'
  if [[ "$XDOC" == "true" ]]; then
    printf '<p>%s <a class="xref-link" href="%s"><span class="xref-code">%s</span><span class="xref-label">%s</span></a></p>\n</div>\n' \
      "$(esc "$(q '.non_goals.text')")" "$(esc "$(q '.cross_doc.srs_html')")" "$(esc "$(q '.non_goals.srs_code')")" "$(esc "$(q '.non_goals.srs_label')")"
  else
    printf '<p>%s</p>\n</div>\n' "$(esc "$(q '.non_goals.text')")"
  fi
}

# ---- §7 指針価値 (principle-terminal = 照会 graph の終端 + narrative) ----
emit_principle() {
  printf '<div data-component="principle-terminal" id="principle-%s"><span class="pt-label">原則終端</span><span class="pt-id">%s</span><p class="pt-text">%s</p></div>\n' \
    "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.id')")" "$(esc "$(q '.principle.text')")"
  printf '<p>%s</p>\n' "$(esc "$(q '.principle.narrative')")"
}

emit_footer() {
  core_emit_footer "<span>folio design system</span><span>vision-pack</span><span>folio engine 段階3 後 ($(esc "$ITAG"))</span><span>Pichler 骨 + Wiegers 選抜 + 原則終端</span>"
}

# mermaid render JS (goal_tree がある時だけ emit・defer 済みで window.mermaid 利用可)。
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
  # ★章は CHAP_SPECS (単一 SSoT) から駆動する。 heading は pack 不変・emitter を動的呼び出し。
  local spec tint kicker heading icon emitter
  for spec in "${CHAP_SPECS[@]}"; do
    IFS='|' read -r tint kicker heading icon emitter <<<"$spec"
    band "$tint" "$kicker" "$heading" "$icon"
    "$emitter"
    band_end
  done
  printf '</div>\n'
  emit_footer
  [[ "$(q '.goal_tree.lines // [] | length')" != "0" ]] && emit_mermaid_js
  printf '</body>\n</html>\n'
}

validate
# ★SRS 由来 ラベル map (fabrication-free・FR=requirements[].label を verbatim)。 validate() が SRS 実在 +
#   全 srs ref が SRS に実在を保証済ゆえ、 参照される全 ref の label は欠落なし。 SRS contract は read-only (無編集)。
#   verify-vision.sh が同一導出で fidelity 突合。 非発火 (cross_doc なし) は map 不要 (照会行を描かない)。
declare -A SRS_LABEL
if [[ "$XDOC" == "true" ]]; then
  SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
  while IFS=$'\t' read -r _id _lbl; do [[ -n "$_id" ]] && SRS_LABEL["$_id"]="$_lbl"; done < <(yq -r '.requirements[] | [.id, .label] | @tsv' "$SRS_ABS")
fi
core_finalize "assemble-vision"
