#!/usr/bin/env bash
# folio 文書規律エンジン core (B2 / folio-5ua) — assemble 共通ライブラリ (SRS-pack ∩ ADR-pack)
#
# rule-of-three の core 抽出 (research/document-discipline-engine-design.html §7 の経験的地図):
# doc-type 非依存の共通 idiom (esc / mark_terms / band / cover(approval) / glossary / footer) を
# 共有層へ引き上げる。 assemble-srs.sh (SRS-pack) と assemble-adr.sh (ADR-pack) が source する。
# pack 固有の section emitter (req-table / option-card / decision-panel 等) は各 assembler に残す
# (= core / pack 境界。 「新 doc-type に持ち込んで改変が要らない」= core、 固有 = pack)。
#
# 前提 (source 側の責務):
#   - 冒頭で `set -euo pipefail` と `shopt -u patsub_replacement` 済 (esc の ${v//&/..} を守る)。
#   - $CONTRACT (contract path) と $CSS (srs.css path) と $OUT を設定済 (q/esc/footer/finalize が参照)。
#   - source 後に core_init_term_inline を呼ぶ (mark_terms の GMAP/LEDGER を構築)。

# ---- contract query / HTML escape (doc-type 非依存) ----
# patsub_replacement (bash 5.2+ 既定 ON) は esc() の ${v//&/..} を壊す (< → <lt;)。 source 側 pack が
# shopt を忘れても esc を堅牢化するため lib 自身でも無効化する (caller も冒頭で設定済=defense-in-depth)。
shopt -u patsub_replacement 2>/dev/null || true
q() { yq -r "$1" "$CONTRACT"; }
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

# ---- plain-language-term-inline 自動併記 (ADR-0042 §2.2 A / glossary 派生ビュー) ----
# glossary 語が本文の flowing 読み取り系フィールドに first-occurrence で現れたら、 その直後に
# plain_short (やさしい言い換え) を .term バッジで *併記* する (本文の専門語は SSoT ゆえ残し、 平易語を足す)。
# 適用先は呼び出し側で限定 (タイトル/短い headline=goals.headline/ラベル/glossary 表/RTM セルは対象外
#  = pill 断片化回避)。 flowing 出現が無い語 (EC では 二重課金) は glossary 章で被覆。
# once-per-doc は LEDGER *ファイル* で担保する: $(mark_terms ...) は command-substitution subshell ゆえ
# shell 変数 (連想配列) では状態が親へ伝播しない。 ファイル書き込みは subshell を越えて永続する。
# ascii 略語 (WMS/PCI DSS) は語境界でのみマッチ (WMSXYZ 中の WMS を誤マーク・トークン破断しない)。
core_init_term_inline() {
  GMAP_FILE="$(mktemp)"; TERM_LEDGER="$(mktemp)"
  trap 'rm -f "$GMAP_FILE" "$TERM_LEDGER"' EXIT
  # GMAP: te_esc <TAB> plain_esc <TAB> ascii(1/0)。 照合・出力とも escape 済み (verify と esc 対称)。
  while IFS=$'\t' read -r term plain; do
    [[ -n "$term" ]] || continue
    [[ -n "$plain" && "$plain" != "null" ]] || plain="$term"
    a=1; case "$term" in *[!\ -~]*) a=0 ;; esac
    printf '%s\t%s\t%s\n' "$(esc "$term")" "$(esc "$plain")" "$a"
  done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv') > "$GMAP_FILE"
}
# mark_terms <raw text> → escape 済みテキスト。 未マーク glossary 語の初出直後に plain_short バッジを併記。
mark_terms() {
  local e; e="$(esc "${1-}")"
  # -CSD: GMAP/LEDGER/STDIN を UTF-8 decode (CJK 語境界 \p{Han} 判定のため)。 print も UTF-8 encode。
  printf '%s' "$e" | GMAP="$GMAP_FILE" LEDGER="$TERM_LEDGER" perl -CSD -0777 -e '
    # -0777 は $/ を slurp に固定する。 GMAP/LEDGER の行読みは local $/="\n" で囲む
    # (素の while(<$fh>) は ファイル全体を 1 行として読み @g が壊れる = inject-prose と同じ gotcha)。
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
      # ascii 略語は前後が英数字でない位置のみ (WMSXYZ 中の WMS を誤マークしない)。
      # CJK 語は前後が漢字でない位置のみ (在庫引当金 など漢字複合語の内部に gloss を誤付与しない。
      #   かな/記号/英数字に隣接する正当な出現は許可)。 完全な形態素境界ではない軽量ヒューリスティック。
      my $pat = ($ascii eq "1")
        ? qr/(?<![A-Za-z0-9])\Q$te\E(?![A-Za-z0-9])/
        : qr/(?<!\p{Han})\Q$te\E(?!\p{Han})/;
      if ($text =~ s/$pat/$& . $badge/e) { $marked{$te}=1; push @newly,$te; }
    }
    print $text;
    if (@newly) { open(my $lw,">>",$ENV{LEDGER}) or die; print $lw "$_\n" for @newly; close $lw; }
  '
}

# ---- icon SVG (静的資産・pack 共用語彙のみ。 pack 固有 icon は各 assembler に残す) ----
ICO_FLOW='<path d="M12 2v6m0 0L9 5m3 3l3-3"/><circle cx="12" cy="14" r="6"/>'
ICO_SHIELD='<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>'
ICO_BOOK='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_CHECK_BIG='<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#ffe8a8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>'
ICO_USER='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#3a2c05" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
ico() { printf '<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">%s</svg>' "$1"; }

# ---- fail-closed contract validation の共通 helper (tab/改行 + glossary 部分文字列) ----
# pack 固有 validate は各 assembler に残す。 これらは「列ずれ防止」「term-inline ネスト防止」の普遍規律。
# $1 = エラー前置語 (prog 名)。 違反があれば stderr へ出し非 0 を返す (caller は `|| errs=1` で合算)。
core_validate_strings() {
  local prog="$1" rc=0
  if [[ "$(yq '[.. | select(tag=="!!str") | test("[\t\n]")] | any' "$CONTRACT")" == "true" ]]; then
    echo "$prog: contract の文字列に tab/改行が含まれます (列ずれ防止のため禁止)" >&2; rc=1; fi
  return $rc
}
core_validate_glossary_substring() {
  local prog="$1" rc=0
  local -a _gt; mapfile -t _gt < <(q '.glossary[].term'); local i j
  for i in "${!_gt[@]}"; do for j in "${!_gt[@]}"; do
    [[ "$i" != "$j" && -n "${_gt[$i]}" && "${_gt[$i]}" != "${_gt[$j]}" && "${_gt[$j]}" == *"${_gt[$i]}"* ]] \
      && { echo "$prog: glossary 語 '${_gt[$i]}' が '${_gt[$j]}' の部分文字列 (term-inline 曖昧化のため禁止)" >&2; rc=1; }
  done; done
  return $rc
}

# ---- chapter band (deck) ----
CHAPN=0
band() { # tint kicker heading icon_inner
  CHAPN=$((CHAPN+1)); local num; printf -v num '%02d' "$CHAPN"
  printf '<section data-component="chapter-deck-band" class="tint-%s"><span class="num">%s</span><span class="kicker">%s %s</span><h2>%s</h2><p class="lead" data-prose-slot="chapter-lead" data-slot-id="chapter-lead-%s"></p></section>\n<div class="chapbody">\n' \
    "$1" "$num" "$(ico "$4")" "$(esc "$2")" "$(esc "$3")" "$num"
}
band_end() { printf '</div>\n'; }

# ---- cover の共通骨格 (eyebrow/h1/subtitle/summary-card + approval + reader-chip) ----
# pack 固有 (cover-meta / cross-doc chip) は各 emit_cover に残し、 共通の頭・承認・尾だけ共有する。
core_emit_cover_head() { # $1 = summary-card label
  printf '<header data-component="doc-cover-band">\n'
  printf '<p class="cover-eyebrow"><span class="doc-type">%s</span> <span>%s</span></p>\n' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")"
  printf '<h1>%s</h1>\n' "$(esc "$(q '.meta.title')")"
  printf '<p class="cover-sub">%s</p>\n' "$(esc "$(q '.meta.subtitle')")"
  printf '<div class="summary-card"><span class="ic">%s</span><div><p class="lab">%s</p><p class="txt" data-prose-slot="cover-summary" data-slot-id="cover-summary"></p></div></div>\n' "$ICO_CHECK_BIG" "$1"
}
core_emit_approval_block() {
  printf '<div data-component="approval-block">\n'
  q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r role who when stamp; do
    [[ -n "$role" ]] || continue; sc=""; [[ "$stamp" != "承認済" ]] && sc=" self"
    printf '<div class="sign"><span class="role">%s</span><span class="who">%s</span><span class="when">%s</span><span class="stamp%s">%s</span></div>\n' "$(esc "$role")" "$(esc "$who")" "$(esc "$when")" "$sc" "$(esc "$stamp")"
  done
  printf '</div>\n'
}
core_emit_cover_tail() {
  printf '<div class="reader-chip">%s 想定読者: %s</div>\n' "$ICO_USER" "$(esc "$(q '.meta.reader')")"
  printf '</header>\n'
}

# ---- glossary 表 (doc-type 非依存・両 pack 同一) ----
emit_glossary() {
  printf '<div data-component="glossary-term-table">\n'
  q '.glossary[] | [.term, (.en // ""), .def] | @tsv' | while IFS=$'\t' read -r term en def; do
    [[ -n "$term" ]] || continue; enb=""; [[ -n "$en" ]] && enb="<span class=\"en\">$(esc "$en")</span>"
    printf '<div class="grow"><div class="gword">%s%s</div><div class="gdef">%s</div></div>\n' "$(esc "$term")" "$enb" "$(esc "$def")"
  done
  printf '</div>\n'
}

# ---- footer (fidelity-sync-meta)。 $1 = .tags の内側 HTML (pack 別ラベル) ----
core_emit_footer() {
  printf '<footer class="foot" data-component="fidelity-sync-meta"><div class="ft-grid">\n'
  printf '<div>機械SSoT: <b>%s</b> &middot; 生成: <b>%s</b> &middot; 検証状態: <b>structure ✓ fabrication-free / prose 未充填 (opus 待ち)</b></div>\n' "$(esc "${CONTRACT##*/}")" "$(date -u '+%Y-%m-%d %H:%M')"
  printf '<div class="tags">%s</div>\n' "$1"
  printf '</div></footer>\n'
}

# ---- 生成の締め (validate は pack 側で済ませた前提で build を temp 経由で出力) ----
# $1 = prog 名 (wrote メッセージ用)。 build() と $OUT は source 側で定義/設定済を前提。
core_finalize() {
  local tmp; tmp="$(mktemp)"; build > "$tmp"
  if [[ "$OUT" == "/dev/stdout" ]]; then cat "$tmp"; rm -f "$tmp"; else mv "$tmp" "$OUT"; echo "$1: wrote $OUT" >&2; fi
}
