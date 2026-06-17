#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack 決定的 assembler (instance#2 / rule-of-three)
#
# 入力 ADR contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS generator (assemble.sh) と *同型* の機構を ADR-pack schema へ適用する:
#   - 内容・構造 (cover/context/drivers/options/decision/consequences/supersession/principle/glossary)
#     は contract から決定的組立。 元データに無い行・選択肢・照会 edge を生成できない。
#   - ★cross-doc 照会 edge: decision.justifies[].req が参照先 SRS contract の要件 ID に実在することを
#     validate() が *生成前に* fail-closed で確かめる (B0 论点2 抽象ロール graph の終端解決)。
#   - 全自由記述値は HTML escape してから注入。 集合外参照・id 重複・tab/改行・未知 role/verdict/status は拒否。
#   - prose スロット (章リード / plain / 判断根拠 / 1 文サマリ) は *空* で出力し ③ inject-prose.sh が充填。
#   - 専門語 plain_short 併記 (mark_terms) は assemble.sh と同一実装を流用 (= term-inline 機構は pack 非依存=core 候補)。
#
# inject-prose.sh は SRS と共通 (data-slot-id ベースで pack 非依存)。 ★この共通化が rule-of-three の
# 「SRS-pack ∩ ADR-pack = core」を炙る一次証拠 (後続 別 bd で core 抽出)。
#
# usage: assemble-adr.sh <adr-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-adr.sh <adr-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-adr: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-adr: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-adr: yq required" >&2; exit 1; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
q() { yq -r "$1" "$CONTRACT"; }
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

# 抽象ロール (B0 论点2 照会 graph) / verdict / adr_status の allowlist。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
declare -A VERDICT_OK=( [chosen]=1 [rejected]=1 [deferred]=1 )
declare -A STATUS_OK=( [proposed]=1 [accepted]=1 [superseded]=1 [deprecated]=1 )
declare -A VERDICT_LABEL=( [chosen]=採用 [rejected]=不採用 [deferred]=保留 )

# ---- plain-language-term-inline 自動併記 (assemble.sh と同一実装 = pack 非依存の core 候補) ----
GMAP_FILE="$(mktemp)"; TERM_LEDGER="$(mktemp)"
trap 'rm -f "$GMAP_FILE" "$TERM_LEDGER"' EXIT
while IFS=$'\t' read -r term plain; do
  [[ -n "$term" ]] || continue
  [[ -n "$plain" && "$plain" != "null" ]] || plain="$term"
  a=1; case "$term" in *[!\ -~]*) a=0 ;; esac
  printf '%s\t%s\t%s\n' "$(esc "$term")" "$(esc "$plain")" "$a"
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv') > "$GMAP_FILE"
mark_terms() {
  local e; e="$(esc "${1-}")"
  printf '%s' "$e" | GMAP="$GMAP_FILE" LEDGER="$TERM_LEDGER" perl -CSD -0777 -e '
    my %marked;
    { local $/="\n"; if (open(my $lf,"<",$ENV{LEDGER})) { while (my $l=<$lf>){ chomp $l; $marked{$l}=1 if length $l; } close $lf; } }
    my @g;
    { local $/="\n"; open(my $gf,"<",$ENV{GMAP}) or die "gmap: $!";
      while (my $l=<$gf>){ chomp $l; next unless length $l; my @f=split(/\t/,$l,3); push @g,\@f; } close $gf; }
    local $/; my $text=<STDIN>; $text="" unless defined $text;
    my @newly;
    for my $r (@g) {
      my ($te,$plain,$ascii)=@$r;
      next if $marked{$te};
      my $badge="<span class=\"term\" data-component=\"plain-language-term-inline\" data-term=\"$te\">$plain</span>";
      my $pat = ($ascii eq "1")
        ? qr/(?<![A-Za-z0-9])\Q$te\E(?![A-Za-z0-9])/
        : qr/(?<!\p{Han})\Q$te\E(?!\p{Han})/;
      if ($text =~ s/$pat/$& . $badge/e) { $marked{$te}=1; push @newly,$te; }
    }
    print $text;
    if (@newly) { open(my $lw,">>",$ENV{LEDGER}) or die; print $lw "$_\n" for @newly; close $lw; }
  '
}

# ---- icon SVG (静的資産・assemble.sh と共用語彙) ----
ICO_FLOW='<path d="M12 2v6m0 0L9 5m3 3l3-3"/><circle cx="12" cy="14" r="6"/>'
ICO_SCALE='<path d="M12 3v18"/><path d="M5 7l-3 6h6z"/><path d="M19 7l-3 6h6z"/><path d="M3 21h18"/>'
ICO_FORK='<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="12" r="2.5"/><path d="M8.5 6H13a3 3 0 0 1 3 3v.5M8.5 18H13a3 3 0 0 0 3-3v-.5"/>'
ICO_GAVEL='<path d="M14 4l6 6-3 3-6-6z"/><path d="M11 7L4 14l3 3 7-7"/><path d="M3 21h10"/>'
ICO_BALANCE='<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'
ICO_CLOCK='<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'
ICO_SHIELD='<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>'
ICO_BOOK='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_CHECK_BIG='<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#ffe8a8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>'
ICO_USER='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#3a2c05" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
ico() { printf '<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">%s</svg>' "$1"; }

# ---- fail-closed contract validation ----
validate() {
  local errs=0 d p
  if [[ "$(yq '[.. | select(tag=="!!str") | test("[\t\n]")] | any' "$CONTRACT")" == "true" ]]; then
    echo "assemble-adr: contract の文字列に tab/改行が含まれます (列ずれ防止のため禁止)" >&2; errs=1; fi
  # id 一意性 (context / drivers / options / consequences)
  d="$(q '.context[].id' | sort | uniq -d)";  [[ -z "$d" ]] || { echo "assemble-adr: context id 重複: $d" >&2; errs=1; }
  d="$(q '.drivers[].id' | sort | uniq -d)";  [[ -z "$d" ]] || { echo "assemble-adr: driver id 重複: $d" >&2; errs=1; }
  d="$(q '.options[].id' | sort | uniq -d)";  [[ -z "$d" ]] || { echo "assemble-adr: option id 重複: $d" >&2; errs=1; }
  d="$(q '(.consequences.positive + .consequences.negative)[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-adr: consequence id 重複: $d" >&2; errs=1; }
  # adr_status allowlist
  p="$(q '.meta.adr_status')"; [[ -v STATUS_OK[$p] ]] || { echo "assemble-adr: 未知の adr_status: $p (proposed|accepted|superseded|deprecated)" >&2; errs=1; }
  # option.verdict allowlist + chosen 整合 (verdict=chosen はちょうど 1 件かつ decision.chosen と一致)
  for p in $(q '.options[].verdict'); do [[ -v VERDICT_OK[$p] ]] || { echo "assemble-adr: 未知の verdict: $p (chosen|rejected|deferred)" >&2; errs=1; }; done
  local nchosen chosen_opt dec_chosen
  nchosen="$(q '[.options[] | select(.verdict=="chosen")] | length')"
  [[ "$nchosen" == "1" ]] || { echo "assemble-adr: verdict=chosen の option はちょうど 1 件であること (実 $nchosen 件)" >&2; errs=1; }
  chosen_opt="$(q '[.options[] | select(.verdict=="chosen")][0].id // ""')"
  dec_chosen="$(q '.decision.chosen')"
  [[ "$chosen_opt" == "$dec_chosen" ]] || { echo "assemble-adr: decision.chosen ($dec_chosen) と verdict=chosen option ($chosen_opt) が不一致" >&2; errs=1; }
  # decision.chosen ∈ options[].id
  if [[ -z "$(q '.options[] | select(.id=="'"$dec_chosen"'") | .id')" ]]; then
    echo "assemble-adr: decision.chosen '$dec_chosen' が options に無い" >&2; errs=1; fi
  # decision.justifies[].role allowlist (抽象ロール graph)
  for p in $(q '.decision.justifies[].role'); do [[ -v ROLE_OK[$p] ]] || { echo "assemble-adr: 未知の照会 role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done
  # ★cross-doc 照会の終端解決: 参照先 SRS contract 実在 + decision.justifies[].req が SRS の要件 ID に実在
  local srs_rel srs_abs srs_docid expect_docid
  srs_rel="$(q '.cross_doc.srs_contract')"
  srs_abs="${CONTRACT_DIR}/${srs_rel}"
  if [[ ! -f "$srs_abs" ]]; then
    echo "assemble-adr: cross_doc.srs_contract が見つからない: $srs_rel (照会先 SRS 不在)" >&2; errs=1
  else
    srs_docid="$(yq -r '.meta.doc_id' "$srs_abs")"
    expect_docid="$(q '.cross_doc.srs_doc_id')"
    [[ "$srs_docid" == "$expect_docid" ]] || { echo "assemble-adr: cross_doc.srs_doc_id ($expect_docid) が SRS contract の doc_id ($srs_docid) と不一致" >&2; errs=1; }
    local req missing
    missing="$(comm -23 <(q '.decision.justifies[].req' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id)' "$srs_abs" | sort -u))"
    [[ -z "$missing" ]] || { echo "assemble-adr: ★cross-doc 照会の dangling: decision.justifies の要件が SRS に実在しない: $missing" >&2; errs=1; }
  fi
  # glossary 語どうしの部分文字列ペアを拒否 (term-inline のネスト span 防止、 assemble.sh と同一)
  local -a _gt; mapfile -t _gt < <(q '.glossary[].term'); local i j
  for i in "${!_gt[@]}"; do for j in "${!_gt[@]}"; do
    [[ "$i" != "$j" && -n "${_gt[$i]}" && "${_gt[$i]}" != "${_gt[$j]}" && "${_gt[$j]}" == *"${_gt[$i]}"* ]] \
      && { echo "assemble-adr: glossary 語 '${_gt[$i]}' が '${_gt[$j]}' の部分文字列 (term-inline 曖昧化のため禁止)" >&2; errs=1; }
  done; done
  [[ "$errs" -eq 0 ]] || { echo "assemble-adr: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

CHAPN=0
band() { # tint kicker heading icon_inner
  CHAPN=$((CHAPN+1)); local num; printf -v num '%02d' "$CHAPN"
  printf '<section data-component="chapter-deck-band" class="tint-%s"><span class="num">%s</span><span class="kicker">%s %s</span><h2>%s</h2><p class="lead" data-prose-slot="chapter-lead" data-slot-id="chapter-lead-%s"></p></section>\n<div class="chapbody">\n' \
    "$1" "$num" "$(ico "$4")" "$(esc "$2")" "$(esc "$3")" "$num"
}
band_end() { printf '</div>\n'; }

# ---- ADR 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_adr_css() {
  cat <<'CSS'
/* ===== ADR-pack 固有部品 (folio-bwc / instance#2)。 srs.css の token を流用 ===== */
[data-component="adr-context-row"]{display:flex;gap:12px;align-items:flex-start;padding:13px 16px;border:1px solid var(--line);border-left:3px solid var(--info);border-radius:10px;background:var(--paper-2);margin:10px 0}
[data-component="adr-context-row"] .cxid{flex:0 0 auto;font-weight:700;font-size:12px;color:var(--info);background:var(--info-tint);border:1px solid var(--info-line);border-radius:6px;padding:2px 8px;letter-spacing:.02em}
[data-component="adr-context-row"] .cxbody .cxh{font-weight:700;margin:0 0 3px;font-size:14.5px}
[data-component="adr-context-row"] .cxbody .cxd{margin:0;color:var(--ink-soft);font-size:13.5px;line-height:1.7}
table[data-component="adr-driver-table"]{width:100%;border-collapse:collapse;margin:8px 0;font-size:13.5px}
[data-component="adr-driver-row"] td{border:1px solid var(--line);padding:9px 12px;vertical-align:top}
[data-component="adr-driver-row"] .drid{font-weight:700;color:var(--brand);white-space:nowrap}
[data-component="adr-driver-row"] .drg{display:inline-block;margin-left:6px;font-size:11px;color:var(--ink-soft);background:var(--paper-3);border:1px solid var(--line);border-radius:5px;padding:1px 6px}
.opt-grid{display:flex;flex-direction:column;gap:12px;margin:10px 0}
[data-component="adr-option-card"]{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--paper);box-shadow:var(--shadow)}
[data-component="adr-option-card"].chosen{border:2px solid var(--ok);background:var(--ok-tint)}
[data-component="adr-option-card"].rejected{opacity:.92}
.opt-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:4px}
.opt-head .opt-id{font-weight:700;font-size:12px;color:var(--ink-soft)}
.opt-head .opt-name{font-weight:800;font-size:15px}
.opt-verdict{font-size:11.5px;font-weight:700;border-radius:999px;padding:2px 11px;border:1px solid}
.opt-verdict.chosen{color:var(--ok);background:var(--ok-tint);border-color:var(--ok-line)}
.opt-verdict.rejected{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
.opt-verdict.deferred{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
[data-component="adr-option-card"] .opt-sum{margin:2px 0 8px;color:var(--ink-soft);font-size:13.5px;line-height:1.7}
[data-component="adr-option-card"] .opt-plain{display:block;margin:0 0 9px;font-size:13px;color:var(--ink-soft);background:var(--brand-tint);border-radius:7px;padding:6px 10px}
.opt-pc{display:grid;grid-template-columns:1fr 1fr;gap:10px}
@media(max-width:640px){.opt-pc{grid-template-columns:1fr}}
.opt-pc ul{margin:3px 0 0;padding-left:2px;list-style:none}
.opt-pc li{font-size:12.5px;line-height:1.65;padding-left:18px;position:relative;margin:3px 0;color:var(--ink-soft)}
.opt-pc .pros h4,.opt-pc .cons h4{margin:0;font-size:11.5px;letter-spacing:.04em}
.opt-pc .pros h4{color:var(--ok)} .opt-pc .cons h4{color:var(--bad)}
.opt-pc .pros li::before{content:"+";position:absolute;left:2px;color:var(--ok);font-weight:800}
.opt-pc .cons li::before{content:"\2212";position:absolute;left:2px;color:var(--bad);font-weight:800}
[data-component="adr-decision-panel"]{border:2px solid var(--ok);border-radius:14px;padding:16px 18px;background:var(--ok-tint);margin:8px 0}
[data-component="adr-decision-panel"] .dec-kick{font-size:11.5px;font-weight:700;letter-spacing:.05em;color:var(--ok);text-transform:uppercase}
[data-component="adr-decision-panel"] .dec-state{font-size:15.5px;font-weight:700;line-height:1.7;margin:5px 0 4px}
[data-component="adr-decision-panel"] .dec-plain{display:block;font-size:13.5px;color:var(--ink-soft);line-height:1.7;margin:0 0 8px}
[data-component="adr-decision-panel"] .dec-why{display:block;font-size:13px;color:var(--ink);background:var(--paper);border:1px solid var(--ok-line);border-radius:8px;padding:8px 11px;line-height:1.75;margin:0 0 10px}
.justify-box{background:var(--paper);border:1px solid var(--line);border-radius:9px;padding:10px 12px}
.justify-box .jh{font-size:12px;font-weight:700;color:var(--ink-faint);margin:0 0 6px}
.justify-row{display:flex;gap:9px;align-items:baseline;padding:5px 0;border-top:1px dashed var(--line)}
.justify-row:first-of-type{border-top:0}
.justify-req{flex:0 0 auto;font-weight:800;font-size:12.5px;color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line);border-radius:6px;padding:1px 9px}
.justify-role{flex:0 0 auto;font-size:10.5px;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:999px;padding:1px 8px}
.justify-note{flex:1 1 auto;font-size:12.5px;color:var(--ink-soft);line-height:1.6}
.justify-tgt{font-size:11.5px;color:var(--ink-faint);margin:8px 0 0}
[data-component="adr-supersession"],[data-component="adr-principle"]{border:1px solid var(--line);border-radius:10px;padding:12px 15px;margin:10px 0;font-size:13.5px;line-height:1.7}
[data-component="adr-supersession"]{background:var(--paper-2)}
[data-component="adr-principle"]{background:var(--violet-tint);border-color:var(--violet-line)}
[data-component="adr-principle"] .prin-id{font-weight:700;color:var(--violet);font-size:12px;letter-spacing:.02em}
[data-component="adr-principle"] .prin-text{font-weight:700;margin:4px 0 2px;color:var(--ink)}
[data-component="adr-principle"] .prin-note{color:var(--ink-soft);font-size:12.5px}
.ss-row{margin:3px 0}.ss-row .ss-k{font-weight:700;color:var(--ink-soft);font-size:12px;margin-right:6px}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio ADR-pack assembler (folio-bwc / instance#2) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_adr_css
  printf '\n</style>\n</head>\n<body>\n'
}

emit_cover() {
  printf '<header data-component="doc-cover-band">\n'
  printf '<p class="cover-eyebrow"><span class="doc-type">%s</span> <span>%s</span></p>\n' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")"
  printf '<h1>%s</h1>\n' "$(esc "$(q '.meta.title')")"
  printf '<p class="cover-sub">%s</p>\n' "$(esc "$(q '.meta.subtitle')")"
  printf '<div class="summary-card"><span class="ic">%s</span><div><p class="lab">この判断が約束すること (1 文サマリ)</p><p class="txt" data-prose-slot="cover-summary" data-slot-id="cover-summary"></p></div></div>\n' "$ICO_CHECK_BIG"
  local nopt ncsq jr
  nopt="$(q '.options | length')件 ($(esc "$(q '.options[0].id')")–$(esc "$(q '.options[-1].id')"))"
  ncsq="良い $(q '.consequences.positive | length') / トレードオフ $(q '.consequences.negative | length')"
  # ★cross-doc 照会の可視チップ (正当化する SRS 要件)
  jr="$(q '[.decision.justifies[].req] | join("・")')"
  printf '<div class="cover-meta"><span class="m"><span class="k">状態</span><span class="v">%s</span></span><span class="m"><span class="k">選択肢</span><span class="v">%s</span></span><span class="m"><span class="k">結果</span><span class="v">%s</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$(esc "$(q '.meta.adr_status')")" "$nopt" "$(esc "$ncsq")" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  printf '<div class="reader-chip" data-component="cross-doc-ref-chip">%s 正当化する要件: <b>%s</b> の <b>%s</b></div>\n' "$ICO_USER" "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$jr")"
  printf '<div data-component="approval-block">\n'
  q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r role who when stamp; do
    [[ -n "$role" ]] || continue; sc=""; [[ "$stamp" != "承認済" ]] && sc=" self"
    printf '<div class="sign"><span class="role">%s</span><span class="who">%s</span><span class="when">%s</span><span class="stamp%s">%s</span></div>\n' "$(esc "$role")" "$(esc "$who")" "$(esc "$when")" "$sc" "$(esc "$stamp")"
  done
  printf '</div>\n'
  printf '<div class="reader-chip">%s 想定読者: %s</div>\n' "$ICO_USER" "$(esc "$(q '.meta.reader')")"
  printf '</header>\n'
}

emit_context() {
  printf '<div data-component="adr-context-list">\n'
  while IFS=$'\t' read -r id summ det; do
    [[ -n "$id" ]] || continue
    printf '<div data-component="adr-context-row"><span class="cxid">%s</span><div class="cxbody"><p class="cxh">%s</p><p class="cxd">%s</p></div></div>\n' "$(esc "$id")" "$(mark_terms "$summ")" "$(mark_terms "$det")"
  done < <(q '.context[] | [.id, .summary, .detail] | @tsv')
  printf '</div>\n'
}

emit_drivers() {
  printf '<table data-component="adr-driver-table"><tbody>\n'
  while IFS=$'\t' read -r id driver grounds; do
    [[ -n "$id" ]] || continue; gb=""; [[ -n "$grounds" && "$grounds" != "null" ]] && gb=" <span class=\"drg\">$(esc "$grounds")</span>"
    printf '<tr data-component="adr-driver-row"><td class="drid">%s</td><td>%s%s</td></tr>\n' "$(esc "$id")" "$(mark_terms "$driver")" "$gb"
  done < <(q '.drivers[] | [.id, .driver, (.grounds // "")] | @tsv')
  printf '</tbody></table>\n'
}

emit_options() {
  printf '<div class="opt-grid">\n'
  local -a OIDS; mapfile -t OIDS < <(q '.options[].id')
  local oid v vlabel chosenc
  for oid in "${OIDS[@]}"; do
    v="$(q '.options[] | select(.id=="'"$oid"'") | .verdict')"
    vlabel="${VERDICT_LABEL[$v]:-$v}"; chosenc=""; [[ "$v" == "chosen" ]] && chosenc=" chosen"; [[ "$v" == "rejected" ]] && chosenc=" rejected"
    printf '<div data-component="adr-option-card" class="%s">\n' "${chosenc# }"
    printf '<div class="opt-head"><span class="opt-id">%s</span><span class="opt-name">%s</span><span class="opt-verdict %s">%s</span></div>\n' \
      "$(esc "$oid")" "$(mark_terms "$(q '.options[] | select(.id=="'"$oid"'") | .name')")" "$(esc "$v")" "$(esc "$vlabel")"
    printf '<p class="opt-sum">%s</p>\n' "$(mark_terms "$(q '.options[] | select(.id=="'"$oid"'") | .summary')")"
    printf '<span class="opt-plain" data-prose-slot="plain" data-slot-id="plain-%s"></span>\n' "$(esc "$oid")"
    printf '<div class="opt-pc"><div class="pros"><h4>+ 利点</h4><ul>\n'
    while IFS= read -r pro; do [[ -n "$pro" ]] && printf '<li>%s</li>\n' "$(mark_terms "$pro")"; done < <(q '.options[] | select(.id=="'"$oid"'") | .pros[]')
    printf '</ul></div><div class="cons"><h4>\xe2\x88\x92 欠点</h4><ul>\n'
    while IFS= read -r con; do [[ -n "$con" ]] && printf '<li>%s</li>\n' "$(mark_terms "$con")"; done < <(q '.options[] | select(.id=="'"$oid"'") | .cons[]')
    printf '</ul></div></div>\n</div>\n'
  done
  printf '</div>\n'
}

emit_decision() {
  printf '<div data-component="adr-decision-panel">\n'
  printf '<p class="dec-kick">採用 — %s</p>\n' "$(esc "$(q '.decision.chosen')")"
  printf '<p class="dec-state">%s</p>\n' "$(mark_terms "$(q '.decision.statement')")"
  printf '<span class="dec-plain" data-prose-slot="plain" data-slot-id="decision-plain"></span>\n'
  printf '<span class="dec-why" data-prose-slot="rationale" data-slot-id="decision-rationale"></span>\n'
  printf '<div class="justify-box"><p class="jh">この判断が正当化する要件 (cross-doc 照会 → %s)</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")"
  while IFS=$'\t' read -r req role note; do
    [[ -n "$req" ]] || continue
    printf '<div class="justify-row"><span class="justify-req" data-justifies-req="%s" data-justifies-role="%s">%s</span><span class="justify-role">%s</span><span class="justify-note">%s</span></div>\n' \
      "$(esc "$req")" "$(esc "$role")" "$(esc "$req")" "$(esc "$role")" "$(mark_terms "$note")"
  done < <(q '.decision.justifies[] | [.req, .role, (.note // "")] | @tsv')
  printf '<p class="justify-tgt">照会先: %s — %s</p>\n' "$(esc "$(q '.cross_doc.srs_doc_id')")" "$(esc "$(q '.cross_doc.srs_title')")"
  printf '</div>\n</div>\n'
}

emit_consequences() {
  printf '<div data-component="scope-summary-panel"><div class="scol in"><h3>\xe2\x9c\x93 良い結果</h3><ul>\n'
  while IFS=$'\t' read -r id text; do [[ -n "$id" ]] && printf '<li data-component="adr-consequence-pos"><span class="b">●</span>%s</li>\n' "$(mark_terms "$text")"; done < <(q '.consequences.positive[] | [.id, .text] | @tsv')
  printf '</ul></div><div class="scol out"><h3>\xe2\x9a\x96 トレードオフ・代償</h3><ul>\n'
  while IFS=$'\t' read -r id text; do [[ -n "$id" ]] && printf '<li data-component="adr-consequence-neg"><span class="b">●</span>%s</li>\n' "$(mark_terms "$text")"; done < <(q '.consequences.negative[] | [.id, .text] | @tsv')
  printf '</ul></div></div>\n'
}

emit_supersession() {
  local st
  st="$(q '.supersession.status')"
  printf '<div data-component="adr-supersession">\n'
  printf '<p class="ss-row"><span class="ss-k">改訂状態</span>%s</p>\n' "$(esc "$st")"
  local sup_n superby_n
  sup_n="$(q '.supersession.supersedes | length')"; superby_n="$(q '.supersession.superseded_by | length')"
  printf '<p class="ss-row"><span class="ss-k">置き換える ADR</span>%s</p>\n' "$([[ "$sup_n" -gt 0 ]] && q '.supersession.supersedes | join(", ")' || echo "なし (新規)")"
  printf '<p class="ss-row"><span class="ss-k">置き換えられた</span>%s</p>\n' "$([[ "$superby_n" -gt 0 ]] && q '.supersession.superseded_by | join(", ")' || echo "なし (現行)")"
  printf '<p class="ss-row">%s</p>\n' "$(mark_terms "$(q '.supersession.note')")"
  printf '</div>\n'
  # 原則終端 (照会 graph の終端、 B0 论点4)
  printf '<div data-component="adr-principle">\n'
  printf '<p class="prin-id">照会終端 — %s</p>\n' "$(esc "$(q '.principle.id')")"
  printf '<p class="prin-text">%s</p>\n' "$(mark_terms "$(q '.principle.text')")"
  printf '<p class="prin-note">%s</p>\n' "$(mark_terms "$(q '.principle.note')")"
  printf '</div>\n'
}

emit_glossary() {
  printf '<div data-component="glossary-term-table">\n'
  q '.glossary[] | [.term, (.en // ""), .def] | @tsv' | while IFS=$'\t' read -r term en def; do
    [[ -n "$term" ]] || continue; enb=""; [[ -n "$en" ]] && enb="<span class=\"en\">$(esc "$en")</span>"
    printf '<div class="grow"><div class="gword">%s%s</div><div class="gdef">%s</div></div>\n' "$(esc "$term")" "$enb" "$(esc "$def")"
  done
  printf '</div>\n'
}

emit_footer() {
  printf '<footer class="foot" data-component="fidelity-sync-meta"><div class="ft-grid">\n'
  printf '<div>機械SSoT: <b>%s</b> &middot; 生成: <b>%s</b> &middot; 検証状態: <b>structure ✓ fabrication-free / prose 未充填 (opus 待ち)</b></div>\n' "$(esc "${CONTRACT##*/}")" "$(date -u '+%Y-%m-%d %H:%M')"
  printf '<div class="tags"><span>folio design system</span><span>ADR-pack</span><span>folio engine B1 (instance#2)</span><span>cross-doc 照会</span></div>\n'
  printf '</div></footer>\n'
}

build() {
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  band info   "背景 / なぜこの判断が要るか"        "いま何が問題か (確定方式を決める力学)"          "$ICO_FLOW";     emit_context;       band_end
  band brand  "判断を縛る力 / 評価の軸"            "選択肢を測るものさし (安全・速さ)"             "$ICO_SCALE";    emit_drivers;       band_end
  band violet "検討した選択肢 / 3 つの確定方式"      "それぞれの利点と欠点を並べる"                  "$ICO_FORK";     emit_options;       band_end
  band ok     "採用した判断 / どの方式を選ぶか"      "選んだ方式と、 それが守る要件 (cross-doc 照会)"  "$ICO_GAVEL";    emit_decision;      band_end
  band warn   "結果 / 良い面とトレードオフ"          "この判断で何が良くなり、 何を引き受けるか"      "$ICO_BALANCE";  emit_consequences;  band_end
  band info   "改訂関係と原則 / この判断の位置づけ"  "版の系譜と、 行き着く原則 (照会終端)"          "$ICO_CLOCK";    emit_supersession;  band_end
  band brand  "用語集 / この文書で使う専門語"        "本文に出てくる専門語のやさしい説明"            "$ICO_BOOK";     emit_glossary;      band_end
  printf '</div>\n'
  emit_footer
  printf '</body>\n</html>\n'
}

validate
tmp="$(mktemp)"; build > "$tmp"
if [[ "$OUT" == "/dev/stdout" ]]; then cat "$tmp"; rm -f "$tmp"; else mv "$tmp" "$OUT"; echo "assemble-adr: wrote $OUT" >&2; fi
