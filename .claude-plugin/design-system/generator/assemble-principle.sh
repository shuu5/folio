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
# ★folio-lq12 (qojv 決定 6 混合案 (c)) — canonical constitution の *節骨格 + rich 内容* を運ぶ:
#   - 節骨格 (存在 / 見出し / 順序 / anchor / class) = contract の sections[] へ構造化し、 生成物では
#     <section id="…" class="…"> + band で emit する (canonical の 8 section + 3 h3 = 計 11 anchor を全て emit)。
#   - 節内 rich 内容 (散文段落 / list / reader-persona aside / mermaid 図) = 逐語 blob (type: raw) と
#     ★typed mermaid (source_lines) で運ぶ。 多行 inner-HTML blob は lib/common.sh の core_validate_strings が
#     tab/改行を fail-closed abort するため原理的に不能ゆえ、 mermaid は既 flip 5 本と同じ typed 形にする。
#   - RAW emit する human 層 blob は ★肯定 allowlist の tokenizer (下記 RICH_*) を生成前に通す。
#     未知 tag / 未知属性名 / script / style / on* / 許可外 URL は無条件 abort (silent esc fallback をしない)。
#   - ai-rationale (canonical の <aside class="ai-rationale" hidden …>) は blob でなく ★構造化 field
#     (amended_by[].rationale / rationale_note) から emit する = メタの二重 SSoT を作らない。
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
# ★anchor (folio-lffq) = 生成物の navigable id (canonical <dt id="p-N"> と同形)。 前方照会ではない (自 doc 内の
#   anchor 名) ゆえ allowlist に載せる。 値の正しさ (非空 + lc(id) 一致) は下の validate が fail-closed で束縛する。
# ★folio-lq12: rationale_note (P-12 の data-rationale-for aside = 改訂来歴でない補足 rationale) を追加する。
#   ★追加は「キー名の追加のみ」であり、 「許可外キー = 終端不変条件違反で abort」という構造は緩めない。
PRINCIPLE_KEY_ALLOW='id|anchor|heading|statement|tier|amended_by|rationale_note'
# amended_by entry / rationale_note の許可キー (principles と同型の fail-closed。 未知キーは silent drop でなく abort)。
AMENDED_BY_KEY_ALLOW='adr|date|approved_by|rationale'
RATIONALE_NOTE_KEY_ALLOW='for|decided|text'
# head_graph に許可しない前方関係キー (principle は照会終端 = 宣言すれば捏造 edge になる・folio-lffq 裁定 1)。
HEAD_GRAPH_FORWARD_KEYS='part_of references depends_on extends'

# ---- ★folio-lq12: 節骨格 (sections) の closed allowlist 群 ----
# ★assemble-principle.sh は top-level 未知キーを拒否しない (禁止は cross_doc / outcome の 2 本のみ) ため、
#   contract に sections を足して emit を忘れても無音で floor PASS しうる。 ゆえ sections は
#   (a) 宣言があれば必ず emit する (b) 生成物との双方向等号を verify が持つ (c) キー allowlist を fail-closed
#   の 3 点で守る (verify-principle.sh の sections arm 群と detect↔remediate parity)。
SECTION_KEY_ALLOW='anchor|class|tint|heading|chapter_heading|chapters_key|blocks|subsections'
SUBSECTION_KEY_ALLOW='anchor|tier|heading'
SECTION_BLOCK_KEY_ALLOW='type|html|caption|source_lines'
# 節 block type (未知 type は silent drop でなく abort = assemble-spec.sh:713 と同規律)。
SECTION_BLOCK_TYPE_ALLOW='raw mermaid principles versioning amendment'
# section.class の closed allowlist (canonical 実値 = informative 5 / normative 3・先例 folio-5dad)。
declare -A CLASS_OK=( [normative]=1 [informative]=1 )
# band tint の closed allowlist (lib/common.sh band の tint-<v> class。 未知値は無スタイル band になる)。
declare -A TINT_OK=( [ok]=1 [warn]=1 [bad]=1 [brand]=1 [violet]=1 [info]=1 )
# tier → band tint / icon (subsection band。 従来 build() に焼かれていた 3 band の tint と同値)。
declare -A TIER_TINT=( [Always]=ok [Ask-first]=warn [Never]=bad )
# tier → chapters key (件数入り友好見出しの SSoT。 chapters.* は数詞 arm が守る既存キーゆえ移設しない)。
declare -A CK_TIER_KEY=( [Always]=always [Ask-first]=ask_first [Never]=never )
# ★sections[].chapters_key が指してよい chapters キー (= 数詞 arm が実件数と照合する 4 キーだけ)。
#   これ以外を許すと「件数を語るのに検証されない h2」が生まれる (件数 fabrication の逃げ道・verify と二重保守)。
declare -A CHAPTERS_KEY_OK=( [always]=1 [ask_first]=1 [never]=1 [amendment]=1 )

# ---- ★human 層 rich inline/block 機構 (folio-lq12: assemble-spec.sh:100-232 の tokenizer を pack-local へ inline port) ----
# ★lib へ refactor せず・assemble-spec.sh からの共通化 refactor もせず、 本 file へ port する (契約: pack-local 実装)。
# ★closed allowlist: canonical constitution の rich 内容に実在する tag/属性だけを ★肯定列挙 する。
#   tag  = a (§1/§3/§4/§5/§6/§7 の cross-ref) / aside (reader-persona) / code (§0 の meta 名) /
#          em (§1 の強調) / li・ul (§1 の核心 list・§7 の citations) / p (段落) / strong (強調)。
#   属性 = class (aside の reader-persona / informative) / data-persona (§0 の 3 persona) / href (a)。
#   ★script / style / on* 属性 / 未知 tag / 未知属性名 / 許可外 URL は無条件 abort (URL は下記 scheme + 相対形のみ)。
#   ★allowlist の廃止・正規表現化 (任意 tag 許可) を禁止する — RAW emit の唯一の防御ゆえ。 canonical が育って
#     新 tag が要るときだけ、 ここへ ★肯定列挙 を足す (contract コメントの列挙と二重保守 = 気づける形にする)。
RICH_INLINE_ALLOW='a|aside|code|em|li|p|strong|ul'
RICH_ATTR_ALLOW='class|data-persona|href'
# href scheme allowlist (§7 Citations の外部引用 = https のみ。 canonical 実測で http/mailto 等は 0 件)。
RICH_HREF_SCHEME='https'
# ★検査対象の被覆量下限 (恒真 PASS 封鎖・assemble-spec.sh:110-113 と同規律): rich_field_values の query drift で
#   検査対象が痩せると「対象 0 件 → bad なし → 恒真 PASS」で RAW emit が無防備に緑化する。 現契約 =
#   preamble_html 1 + sections[].blocks[type=raw].html 14 = 15。 契約が正当に育ったときのみ更新する。
RICH_FIELD_MIN=15

# ★RAW emit する human 層 field の全値を document 順に吐く (validate と emit で 1 対応・対象漏れの二重保守を防ぐ)。
#   = top-level preamble_html + sections[].blocks[type=="raw"].html。 mermaid の source_lines は RAW でなく
#     esc() 経由の <pre> 本文ゆえ本 tokenizer の対象外 (esc 済は markup を成さない)。
rich_field_values() {
  q '[ .preamble_html, (.sections[]?.blocks[]? | select(.type=="raw") | .html) ] | map(select(. != null)) | .[]'
}

# ★strict tokenizer 本体 (assemble-spec.sh:120-232 の ★逐語 port = 実 HTML parser の tag/属性 grammar を辿る
#   parser-differential 封鎖。 lib へは出さず pack-local に置く契約)。 perl 側 message は ASCII のみ。
RICH_TOKENIZE_PL='
    BEGIN {
      our %bad; our $re = qr/^(?:$ENV{ALLOW})$/i; our $attr_re = qr/^(?:$ENV{ATTRALLOW})$/i;
      our $url_attr = qr/^(?:href|src|xlink:href|formaction|action)$/i;
      sub decode_refs {
        my ($s) = @_; $s //= "";
        $s =~ s/&#x([0-9a-fA-F]+);?/chr(hex($1))/ge;
        $s =~ s/&#(\d+);?/chr($1)/ge;
        my %n = ("amp"=>"&","lt"=>"<","gt"=>">","quot"=>"\"","apos"=>"\x27","Tab"=>"\t","NewLine"=>"\n","colon"=>":","sol"=>"/");
        $s =~ s/&([a-zA-Z]+);?/exists $n{$1} ? $n{$1} : "&$1;"/ge;
        return $s;
      }
      sub decode_full {
        my ($s) = @_; my $prev = "";
        for (1..5) { last if $s eq $prev; $prev = $s; $s = decode_refs($s); }
        return $s;
      }
      # ★folio-a405 errata-1 (must-1): 相対 arm の path class 先頭 1 文字を / 抜き class へ固定する。 旧 [A-Za-z0-9._/-]+ は
      #   path class に / を含み先頭 // が match するため protocol-relative (//evil.com/x.html) / 多重スラッシュ (///a.html) が
      #   ALLOW される fail-open だった (perl 実測)。 先頭を [A-Za-z0-9._-] (/ 無し) に固定し、 2 文字目以降のみ / を許す。
      #   ./constitution.html#p-6 / ../decisions/ADR-0034.html 等の正規 doc-relative は不変で通る (実測)。
      our $href_ok = qr{^(?:
            \#[^\s]*
          | (?:\.{1,2}/)*[A-Za-z0-9._-][A-Za-z0-9._/-]*\.html(?:\#[^\s]*)?
          | (?:\.{1,2}/)*[A-Za-z0-9._-][A-Za-z0-9._/-]*\.md(?:\#[^\s]*)?
          | (?:$ENV{SCHEMEALLOW})://[A-Za-z0-9._~:/?\#\[\]@!$&\x27()*+,;=%-]+
        )$}x;
    }
    my $s = $_; my $n = length($s); my $i = 0;
    while ($i < $n) {
      my $lt = index($s, "<", $i);
      last if $lt < 0;
      my $rest = substr($s, $lt);
      if ($rest =~ /^<[!?]/) { $bad{"<! or <? (MALFORMED-MARKUP; declaration/comment not allowed in rich field)"}++; last; }
      unless ($rest =~ /^<(\/?)([a-zA-Z][a-zA-Z0-9]*)/) { $i = $lt + 1; next; }
      my ($close, $tag) = ($1, $2);
      $bad{"<$tag> (TAG-NOT-ALLOWED)"}++ unless $tag =~ $re;
      my $need_href = (!$close && lc($tag) eq "a") ? 1 : 0;
      my $saw_href = 0;
      $i = $lt + 1 + length($close) + length($tag);
      while (1) {
        my $ws = 0;
        while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; $ws = 1; }
        if ($i >= $n) { $bad{"<$tag> (MALFORMED-MARKUP; eof-in-tag = unterminated tag)"}++; last; }
        my $c = substr($s, $i, 1);
        if ($c eq ">") { $i++; last; }
        if ($c eq "/" && substr($s, $i + 1, 1) eq ">") { $i += 2; last; }
        if ($close) { $bad{"</$tag> (MALFORMED-MARKUP; attributes on end tag)"}++; last; }
        unless ($ws) {
          $bad{"<$tag> (MALFORMED-MARKUP; missing-whitespace-between-attributes)"}++; last;
        }
        unless (substr($s, $i) =~ /^([a-zA-Z_:][-a-zA-Z0-9_:.]*)/) {
          $bad{"<$tag> (MALFORMED-MARKUP; unreadable attr name: " . substr($s, $i, 12) . ")"}++; last;
        }
        my $name = $1; $i += length($name);
        $saw_href = 1 if lc($name) eq "href";
        while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; }
        my ($has_val, $raw) = (0, "");
        if (substr($s, $i, 1) eq "=") {
          $i++;
          while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; }
          my $r = substr($s, $i);
          if    ($r =~ /^"([^"]*)"/)            { $raw = $1; $i += length($1) + 2; $has_val = 1; }
          elsif ($r =~ /^\x27([^\x27]*)\x27/)   { $raw = $1; $i += length($1) + 2; $has_val = 1; }
          elsif ($r =~ /^([^\s"\x27>`=<]+)/)    { $raw = $1; $i += length($1);     $has_val = 1; }
          else { $bad{"$name= (MALFORMED-MARKUP; unreadable attr value: " . substr($r, 0, 12) . ")"}++; last; }
        }
        unless ($name =~ $attr_re) {
          my $why = ($name =~ /^on/i) ? "event handler attribute" : "ATTR-NAME-NOT-ALLOWED";
          $bad{"$name= ($why)"}++; next;
        }
        next unless $has_val && $name =~ $url_attr;
        my $u = decode_full($raw);
        $u =~ s/[\x00-\x20\x7f]//g;
        next if $u =~ $href_ok;
        $bad{"$name=\"$raw\" (URL-ALLOWLIST-VIOLATION; decoded: $u)"}++;
      }
      $bad{"<a> (MALFORMED-MARKUP; anchor-without-href)"}++ if $need_href && !$saw_href;
    }
    END { print join("; ", map { "$_ x$bad{$_}" } sort keys %bad) if %bad; }
'

# ★human 層 rich field の inline 健全性 (folio-lq12)。 caller は `|| errs=1` で呼ぶため set -e は無効 = 自前 exit-status 判定。
#   fail-closed 3 点: (a) 抽出失敗 (yq 非0) / (b) 被覆量下限割れ (恒真 PASS 封鎖) / (c) tokenizer 異常終了。
validate_rich_inline() {
  local bad vals n rc
  vals="$(mktemp)"
  if ! rich_field_values > "$vals"; then
    rm -f "$vals"; echo "assemble-principle: ★rich field の抽出に失敗 (yq 非 0 exit・検査不能ゆえ fail-closed)" >&2; return 1
  fi
  n="$(grep -c . "$vals" || true)"
  if [[ "$n" -lt "$RICH_FIELD_MIN" ]]; then
    rm -f "$vals"
    echo "assemble-principle: ★rich field の検査対象が $n 件 (期待下限 $RICH_FIELD_MIN)。 rich_field_values の query drift か" >&2
    echo "  flag 消失により RAW emit の注入防御が無被覆 (検査対象 0/過少での恒真 PASS を封鎖)。 契約が育った時のみ RICH_FIELD_MIN 更新。" >&2
    return 1
  fi
  bad="$(ALLOW="$RICH_INLINE_ALLOW" ATTRALLOW="$RICH_ATTR_ALLOW" SCHEMEALLOW="$RICH_HREF_SCHEME" \
         perl -CSD -ne "$RICH_TOKENIZE_PL" < "$vals")"; rc=$?
  rm -f "$vals"
  [[ $rc -eq 0 ]] || { echo "assemble-principle: ★rich field の tokenize に失敗 (perl 非 0 exit・検査不能ゆえ fail-closed)" >&2; return 1; }
  [[ -z "$bad" ]] && return 0
  echo "assemble-principle: ★human 層 rich field に allowlist 外の markup: $bad" >&2
  echo "  (rich field = preamble_html + sections[].blocks[type=raw].html。 RAW emit ゆえ許可 tag は肯定列挙のみ: $RICH_INLINE_ALLOW)" >&2
  echo "  (属性名も肯定 allowlist: $RICH_ATTR_ALLOW。 href 無し <a> / on*= / style / script は fail-closed)" >&2
  return 1
}

# ---- icon SVG (principle-pack 固有。 共用 icon=ICO_FLOW/SHIELD/BOOK/CHECK_BIG/USER + ico() は lib/common.sh) ----
ICO_ALWAYS='<path d="M12 2v20"/><path d="M2 12h20"/><circle cx="12" cy="12" r="9"/>'
ICO_ASK='<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.8.5-1 .9-1 1.7"/><path d="M12 17h.01"/>'
ICO_NEVER='<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>'
ICO_VERSION='<path d="M3 7h18"/><path d="M3 12h18"/><path d="M3 17h18"/><circle cx="7" cy="7" r="1.4"/><circle cx="13" cy="12" r="1.4"/><circle cx="9" cy="17" r="1.4"/>'
ICO_AMEND='<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>'
ICO_INBOUND='<path d="M20 12H6"/><path d="M11 18l-6-6 6-6"/><circle cx="21" cy="12" r="1.5"/>'
ICO_GUIDE='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_TARGET='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>'
ICO_LAYERS='<path d="M12 2 2 7l10 5 10-5z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>'
ICO_PLUG='<path d="M9 2v6M15 2v6"/><path d="M6 8h12v3a6 6 0 0 1-12 0z"/><path d="M12 17v5"/>'
ICO_QUOTE='<path d="M7 7h4v6a4 4 0 0 1-4 4"/><path d="M15 7h4v6a4 4 0 0 1-4 4"/>'
# ★節 band の icon (非テキストの静的デザイン資産・contract 由来でない)。 section index で循環選択する
#   (assemble-spec.sh:230 SECT_ICONS と同型 = anchor 名への hardcode を避ける)。
SECT_ICONS=("$ICO_GUIDE" "$ICO_TARGET" "$ICO_SHIELD" "$ICO_LAYERS" "$ICO_PLUG" "$ICO_VERSION" "$ICO_AMEND" "$ICO_QUOTE")

# ---- ★folio-lq12: 節骨格 (sections) の fail-closed validation ----
# ★存在 / 見出し / 順序 / anchor / class の 5 要素 + block 構造を生成前に束縛する。 caller は `|| errs=1` ゆえ
#   set -e は効かない = 自前で rc を積む。
validate_sections() {
  local rc=0 bad n i nb bi btype anc cls tint head ch ck nsub si tier
  # (0) sections / preamble_html の存在 (宣言忘れ = canonical 節骨格の無音喪失ゆえ hard fail-closed)。
  if [[ "$(q 'has("sections")')" != "true" ]]; then
    echo "assemble-principle: ★sections 欠落 (canonical の節骨格 8 節 + h3 3 個は本 pack の必須構造・fail-closed)" >&2; return 1
  fi
  n="$(q '.sections | length')"
  [[ "$n" -gt 0 ]] || { echo "assemble-principle: ★sections が空配列 (節骨格の喪失)" >&2; return 1; }
  if [[ -z "$(q '.preamble_html // ""')" || "$(q '.preamble_html // ""')" == "null" ]]; then
    echo "assemble-principle: ★preamble_html 欠落 (canonical:58-60 の RFC 2119 キーワード解釈 aside は section 外の前文・fail-closed)" >&2; rc=1
  fi
  # (1) key allowlist (未知キー = 運搬形の silent drop / 前方照会の疑い)。
  bad="$(q '.sections[] | keys | .[]' | sort -u | grep -vxE "$SECTION_KEY_ALLOW" || true)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★sections に許可外キー: $(echo $bad) (許可 = $SECTION_KEY_ALLOW)" >&2; rc=1; }
  bad="$(q '.sections[].subsections[]? | keys | .[]' | sort -u | grep -vxE "$SUBSECTION_KEY_ALLOW" || true)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★subsections に許可外キー: $(echo $bad) (許可 = $SUBSECTION_KEY_ALLOW)" >&2; rc=1; }
  bad="$(q '.sections[].blocks[]? | keys | .[]' | sort -u | grep -vxE "$SECTION_BLOCK_KEY_ALLOW" || true)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★section block に許可外キー: $(echo $bad) (許可 = $SECTION_BLOCK_KEY_ALLOW)" >&2; rc=1; }
  # (2) anchor: 非空 / 一意 / principles[].anchor と非衝突 (同一 id 属性が 2 個出る経路を塞ぐ)。
  bad="$(q '[.sections[].anchor, .sections[].subsections[]?.anchor] | .[]' | grep -c '^$' || true)"
  [[ "$bad" == "0" ]] || { echo "assemble-principle: ★section/subsection の anchor に空が $bad 件 (navigable id 無しは inbound #s… を無言で殺す)" >&2; rc=1; }
  bad="$(q '[.sections[].anchor, .sections[].subsections[]?.anchor, .principles[].anchor] | .[]' | sort | uniq -d)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★anchor 重複 (section/subsection/principle を跨いで一意必須): $(echo $bad)" >&2; rc=1; }
  # (3) class / tint の closed allowlist + heading 非空。
  # ★per-index で見る (cell-quality round-1 confirmed): `for x in $(q '.sections[].class')` は word-split ゆえ
  #   ★空文字・空白のみ の値が要素ごと消えて allowlist 判定を素通りする (空 class は属性欠落の生成物を生み、
  #   空 tint は無スタイル band を生むのに どちらも無音だった)。 index 走査なら空値も 1 件として判定される。
  local n_s; n_s="$(q '.sections | length')"
  for ((i=0; i<n_s; i++)); do
    cls="$(q ".sections[$i].class // \"\"")"; tint="$(q ".sections[$i].tint // \"\"")"
    anc="$(q ".sections[$i].anchor")"
    [[ -n "$cls" && -v CLASS_OK[$cls] ]] || { echo "assemble-principle: ★未知/空の section class: '${cls}' (sections[$anc]・normative|informative)" >&2; rc=1; }
    [[ -n "$tint" && -v TINT_OK[$tint] ]] || { echo "assemble-principle: ★未知/空の section tint: '${tint}' (sections[$anc]・ok|warn|bad|brand|violet|info)" >&2; rc=1; }
  done
  bad="$(q '[.sections[], (.sections[].subsections[]?)] | .[] | .heading // ""' | grep -c '^$' || true)"
  [[ "$bad" == "0" ]] || { echo "assemble-principle: ★section/subsection の heading (canonical 節見出し) に空が $bad 件" >&2; rc=1; }
  # (4) 友好 h2 の出所は chapter_heading か chapters_key の ★どちらか一方 (両方 / どちらも無し は abort)。
  #     chapters_key は既存 chapters.* (件数入り見出し = 数詞 arm の守備範囲) を指す参照であり値を二重化しない。
  for ((i=0; i<n; i++)); do
    ch="$(q ".sections[$i].chapter_heading // \"\"")"; ck="$(q ".sections[$i].chapters_key // \"\"")"
    anc="$(q ".sections[$i].anchor")"
    if [[ -n "$ch" && "$ch" != "null" && -n "$ck" && "$ck" != "null" ]]; then
      echo "assemble-principle: ★sections[$anc] が chapter_heading と chapters_key の両方を持つ (h2 の SSoT が 2 つ)" >&2; rc=1
    elif [[ ( -z "$ch" || "$ch" == "null" ) && ( -z "$ck" || "$ck" == "null" ) ]]; then
      echo "assemble-principle: ★sections[$anc] に友好 h2 が無い (chapter_heading か chapters_key のどちらかが必須)" >&2; rc=1
    elif [[ -n "$ck" && "$ck" != "null" ]]; then
      # ★closed set 必須 (cell-quality round-1 confirmed): chapters_key を任意キーにすると、 数詞 arm が守るのは
      #   always / ask_first / never / amendment の 4 キーだけなので、 それ以外のキー (chapters.foo 等) を指した
      #   瞬間に「件数を語るのに実件数と照合されない h2」が end-to-end GREEN で通る (件数 fabrication の逃げ道)。
      #   ★キー名は yq 式へ展開されるため、 allowlist 外を先に弾いてから参照する (式注入面も同時に閉じる)。
      [[ -v CHAPTERS_KEY_OK[$ck] ]] \
        || { echo "assemble-principle: ★sections[$anc].chapters_key '$ck' は allowlist 外 (数詞 arm が守るキーのみ: ${!CHAPTERS_KEY_OK[*]})" >&2; rc=1; continue; }
      [[ -n "$(q ".chapters.${ck} // \"\"")" ]] || { echo "assemble-principle: ★sections[$anc].chapters_key '$ck' が chapters に実在しない" >&2; rc=1; }
    fi
    # ★chapter_heading に数字を置かない (半角・全角とも)。 chapter_heading は canonical 由来でない ★著作見出し
    #   ゆえ census にも数詞 arm にも束縛されず、 数を書けば「検証されない件数の主張」が生まれる (件数 fabrication
    #   の逃げ道)。 件数を語ってよい見出しは chapters.* だけ (そこは数詞 arm が実件数と一致を強制する)。
    #   ★blocklist 列挙 (漢数字 / 丸数字 …) でなく「数字を置かない」という肯定形の不変条件で閉じる。
    if [[ -n "$ch" && "$ch" != "null" ]] && grep -qE '[0-9]|０|１|２|３|４|５|６|７|８|９' <<<"$ch"; then
      echo "assemble-principle: ★sections[$anc].chapter_heading に数字 (検証されない件数の主張になる・件数は chapters.* のみ): $ch" >&2; rc=1
    fi
  done
  # (5) block: type allowlist + type 別の必須 field。
  for ((i=0; i<n; i++)); do
    anc="$(q ".sections[$i].anchor")"; nb="$(q ".sections[$i].blocks // [] | length")"
    [[ "$nb" -gt 0 ]] || { echo "assemble-principle: ★sections[$anc] の blocks が空 (空節は canonical に無い)" >&2; rc=1; }
    for ((bi=0; bi<nb; bi++)); do
      btype="$(q ".sections[$i].blocks[$bi].type // \"\"")"
      case " $SECTION_BLOCK_TYPE_ALLOW " in
        *" $btype "*) ;;
        *) echo "assemble-principle: ★未対応 block type '$btype' (sections[$anc][$bi]・silent drop 禁止): 許可 = $SECTION_BLOCK_TYPE_ALLOW" >&2; rc=1; continue ;;
      esac
      case "$btype" in
        raw)
          [[ -n "$(q ".sections[$i].blocks[$bi].html // \"\"")" ]] \
            || { echo "assemble-principle: ★raw block の html が空 (sections[$anc][$bi])" >&2; rc=1; }
          ;;
        mermaid)
          [[ "$(q ".sections[$i].blocks[$bi].source_lines // [] | length")" -gt 0 ]] \
            || { echo "assemble-principle: ★mermaid block の source_lines が空 (sections[$anc][$bi]・図の無言消失)" >&2; rc=1; }
          [[ -n "$(q ".sections[$i].blocks[$bi].caption // \"\"")" ]] \
            || { echo "assemble-principle: ★mermaid block の caption (figcaption) が空 (sections[$anc][$bi])" >&2; rc=1; }
          ;;
      esac
    done
  done
  # (6) pack-native block (principles / versioning / amendment) は文書全体で ★ちょうど 1 回。
  #     0 回 = 14 原則 / 版方針 / 手順 が無言で消える (件数 arm は「HTML 側 0 == contract 側 N」で FAIL に倒れるが、
  #     生成段で先に落とすほうが原因が明快)。 2 回以上 = 重複 emit (占有数 arm が壊れる)。
  for btype in principles versioning amendment; do
    bad="$(q "[.sections[].blocks[]? | select(.type==\"$btype\")] | length")"
    [[ "$bad" == "1" ]] || { echo "assemble-principle: ★pack-native block '$btype' の出現が $bad 回 (ちょうど 1 回必須)" >&2; rc=1; }
  done
  # (7) subsections は principles block を持つ節にだけ在り、 tier 集合が principles の tier 集合と ★完全一致。
  for ((i=0; i<n; i++)); do
    anc="$(q ".sections[$i].anchor")"
    nsub="$(q ".sections[$i].subsections // [] | length")"
    [[ "$nsub" -gt 0 ]] || continue
    if [[ "$(q "[.sections[$i].blocks[]? | select(.type==\"principles\")] | length")" != "1" ]]; then
      echo "assemble-principle: ★sections[$anc] が subsections を持つのに principles block を持たない (tier band の宿無し)" >&2; rc=1
    fi
    for tier in $(q ".sections[$i].subsections[].tier"); do
      [[ -v TIER_OK[$tier] ]] || { echo "assemble-principle: ★未知の subsection tier: $tier" >&2; rc=1; }
    done
    if [[ "$(q ".sections[$i].subsections[].tier" | sort)" != "$(q '.principles[].tier' | sort -u)" ]]; then
      echo "assemble-principle: ★subsections の tier 集合が principles の tier 集合と不一致 (原則が宿無しの tier に落ちる)" >&2; rc=1
    fi
  done
  return $rc
}

# ---- ★folio-lq12: ai-rationale (改訂来歴の理由文 / 補足 rationale) の fail-closed validation ----
validate_rationale() {
  local rc=0 bad pid
  bad="$(q '.principles[].amended_by[]? | keys | .[]' | sort -u | grep -vxE "$AMENDED_BY_KEY_ALLOW" || true)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★amended_by に許可外キー: $(echo $bad) (許可 = $AMENDED_BY_KEY_ALLOW)" >&2; rc=1; }
  bad="$(q '.principles[].rationale_note? | select(. != null) | keys | .[]' | sort -u | grep -vxE "$RATIONALE_NOTE_KEY_ALLOW" || true)"
  [[ -z "$bad" ]] || { echo "assemble-principle: ★rationale_note に許可外キー: $(echo $bad) (許可 = $RATIONALE_NOTE_KEY_ALLOW)" >&2; rc=1; }
  # rationale_note を持つ原則は for / decided / text の 3 点が揃うこと (欠落 aside = 属性欠けの捏造)。
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    [[ "$(q ".principles[] | select(.id==\"$pid\") | .rationale_note | [has(\"for\"), has(\"decided\"), has(\"text\")] | all")" == "true" ]] \
      || { echo "assemble-principle: ★principles[$pid].rationale_note に for/decided/text のいずれかが無い" >&2; rc=1; }
    # for は当該原則の anchor と一致 (canonical data-rationale-for="p-12" の帰属を機械束縛)。
    [[ "$(q ".principles[] | select(.id==\"$pid\") | .rationale_note.for")" == "$(q ".principles[] | select(.id==\"$pid\") | .anchor")" ]] \
      || { echo "assemble-principle: ★principles[$pid].rationale_note.for が当該原則の anchor と不一致 (帰属の捏造)" >&2; rc=1; }
  done < <(q '.principles[] | select(has("rationale_note")) | .id')
  return $rc
}

# ---- fail-closed contract validation ----
validate() {
  local errs=0 d p
  core_validate_strings "assemble-principle" || errs=1
  # ★folio-lq12: RAW emit する human 層 blob (preamble_html / sections[].blocks[type=raw].html) を emit 前に
  #   tokenizer 検証する (人間層と対称の位置 = validate 内・emit 前 fail-closed。 emit 後 post-check だと
  #   毒入り生成物が一度存在する非対称が残る = assemble-spec.sh:236 と同規律)。
  validate_rich_inline || errs=1
  validate_sections || errs=1
  validate_rationale || errs=1
  # ★doc_type 束縛 (fail-open 封鎖・cell-quality critical): 本 pack は constitution 専用 assembler。 doc_type が
  #   constitution 以外なら abort。 doc_type を生成段で必須化することで、 doc_type flip により verify-principle.sh の
  #   baseline-diff / inbound gate (どちらも doc_type:constitution で起動) を bypass する経路を生成段でも塞ぐ。
  [[ "$(q '.meta.doc_type')" == "constitution" ]] || { echo "assemble-principle: ★meta.doc_type は constitution 必須 (principle-pack は constitution 専用・doc_type flip で gate bypass 不可)" >&2; errs=1; }
  # id 一意性 (principles)
  d="$(q '.principles[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-principle: principle id 重複: $d" >&2; errs=1; }
  # ★anchor (navigable id) fail-closed (folio-lffq 裁定 3): 空 anchor は「id 無しの原則」= inbound #p-N が
  #   silent に死ぬ (gate (i) は essence 空を無言 skip・gate (h) は anchor 存在しか見ない = 全経路が沈黙する)。
  #   大小文字は id を tr で小文字化した決定的導出値のみを受け、 contract 側の手書き drift を生成段で塞ぐ。
  local pid_a anc_a exp_a
  while IFS= read -r pid_a; do
    [[ -n "$pid_a" ]] || continue
    anc_a="$(q '.principles[] | select(.id=="'"$pid_a"'") | .anchor // ""')"
    exp_a="$(printf '%s' "$pid_a" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$anc_a" || "$anc_a" == "null" ]]; then
      echo "assemble-principle: ★principles[$pid_a].anchor が空 (navigable id 無しは inbound #p-N を無言で殺す・fail-closed)" >&2; errs=1
    elif [[ "$anc_a" != "$exp_a" ]]; then
      echo "assemble-principle: ★principles[$pid_a].anchor が id 小文字化と不一致 (期待 '$exp_a' / 実 '$anc_a')" >&2; errs=1
    fi
  done < <(q '.principles[].id')
  # anchor 一意性 (id 一意でも anchor 手書き重複で同一 id 属性が 2 個出る経路を塞ぐ)。
  d="$(q '.principles[].anchor' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-principle: principle anchor 重複: $d" >&2; errs=1; }
  # ★head_graph (spec graph 参加・folio-lffq 裁定 1) — constitution は @type=FolioConstitution で graph scan から
  #   外れる不変 anchor ゆえ、 宣言の欠落 / @type の flip はどちらも consumer 側 gate の意味を反転させる (flip すれば
  #   生成物が scan 対象に転じ、 欠落すれば switchover-harness の in-scan hard-fail = SWH-HARDFAIL head_graph-missing)。
  if [[ "$(q 'has("head_graph")')" != "true" ]]; then
    echo "assemble-principle: ★head_graph 欠落 (constitution は spec graph の head 参加が必須・fail-closed)" >&2; errs=1
  else
    local hgt hgk
    hgt="$(q '.head_graph.type // ""')"
    [[ "$hgt" == "FolioConstitution" ]] || { echo "assemble-principle: ★head_graph.type は FolioConstitution 必須 (実際: '${hgt}')。 flip すると生成物が spec graph の scan 対象へ転び inventory/validate/fix の除外と self-root 検出が一斉に反転する" >&2; errs=1; }
    #   前方関係は 1 本も持たない (照会終端 不変条件の head 面・principle-level の許可外キー check と同根)。
    for hgk in $HEAD_GRAPH_FORWARD_KEYS; do
      [[ "$(q "[.head_graph.${hgk} // []] | flatten | length")" == "0" ]] \
        || { echo "assemble-principle: ★head_graph に前方関係 '$hgk' (principle は照会終端ゆえ禁止・reverse 材化も検証もされない捏造 edge になる)" >&2; errs=1; }
    done
  fi
  # ★meta.stakeholders 型 guard (fail-open 封鎖・assemble-verification.sh:846-851 と同型): scalar を素で join すると
  #   1 要素扱いで通り、 CORE 側 JSON-LD folio:stakeholders が array→string へ型退行する (jsonld-lint / inventory /
  #   fedges のいずれも捕捉しない)。 型そのものを契約 gate で pin する。
  local stake_type; stake_type="$(q '.meta.stakeholders | type')"
  [[ "$stake_type" == "!!seq" || "$stake_type" == "!!null" ]] \
    || { echo "assemble-principle: ★meta.stakeholders は array 必須 (実際: $stake_type)。 scalar は CORE の JSON-LD folio:stakeholders を canonical の array から string へ型退行させる" >&2; errs=1; }
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
  # ★chapters (tier/amendment band 見出し) は contract 必須 (folio-c5r.2)。 instance#4 固有の件数入り見出し
  #   ("9 原則 — folio の土台" 等) を code に焼くと 2nd instance が偽の件数・偽の出自を表示する
  #   (glossary footer instance_tag = folio-c5r.3 BLK-FOOTER-INSTANCE-TAG と同根)。 件数入り文言は
  #   fabrication 面ゆえ neutral default を置かず fail-closed 必須とする。
  local ck cv ncnt tcnt
  local -A CK_TIER=( [always]=Always [ask_first]=Ask-first [never]=Never )
  for ck in always ask_first never amendment; do
    cv="$(q ".chapters.${ck} // \"\"")"
    [[ -n "$cv" ]] || { echo "assemble-principle: ★chapters.${ck} 欠落 (band 見出しは contract 必須・instance hardcode 禁止)" >&2; errs=1; }
  done
  # ★見出し内の数詞 == 派生実件数 (件数は machine floor の領分・verification §3.9): 「N 原則」は当該 tier の
  #   principles 実件数、 「N ステップ」は amendment.steps 実件数と一致必須 (件数 fabrication を生成段で封鎖)。
  #   ★数詞は ASCII 半角の「N 原則 / N ステップ」を **必須** とする肯定形 (c5r.2 ceiling round1):
  #   「数詞があれば照合」の任意形だと漢数字「九 原則」・丸数字等が照合を素通りする (回避表記の
  #   blocklist 列挙は partial-enum trap)。 canonical 表記を必須化すれば回避表記は「必須数詞なし」で
  #   一律 abort になり、 表記列挙なしで全回避経路が閉じる。
  #   全角数字の明示 guard は defense-in-depth として残す (★bracket 式 [０-９] は C locale で multibyte を
  #   byte 分解し誤 match するため、 明示 alternation で locale 非依存に)。
  for ck in always ask_first never amendment; do
    cv="$(q ".chapters.${ck} // \"\"")"
    if grep -qE '０|１|２|３|４|５|６|７|８|９' <<<"$cv"; then
      echo "assemble-principle: ★chapters.${ck} に全角数字 (数詞照合を回避する表記・半角で書く): $cv" >&2; errs=1
    fi
  done
  for ck in always ask_first never; do
    cv="$(q ".chapters.${ck} // \"\"")"
    [[ -n "$cv" ]] || continue  # 欠落は上の必須 check が既に errs 済
    ncnt="$(grep -oE '[0-9]+[[:space:]]*原則' <<<"$cv" | grep -oE '[0-9]+' | head -1 || true)"
    if [[ -z "$ncnt" ]]; then
      echo "assemble-principle: ★chapters.${ck} に ASCII 数字の件数「N 原則」が無い (数詞は半角 ASCII 必須 = 漢数字等の照合回避を封鎖): $cv" >&2; errs=1
    else
      tcnt="$(q "[.principles[] | select(.tier == \"${CK_TIER[$ck]}\")] | length")"
      [[ "$ncnt" == "$tcnt" ]] || { echo "assemble-principle: ★chapters.${ck} の数詞 ${ncnt} が tier ${CK_TIER[$ck]} 実件数 ${tcnt} と不一致 (件数 fabrication)" >&2; errs=1; }
    fi
  done
  cv="$(q '.chapters.amendment // ""')"
  if [[ -n "$cv" ]]; then
    ncnt="$(grep -oE '[0-9]+[[:space:]]*ステップ' <<<"$cv" | grep -oE '[0-9]+' | head -1 || true)"
    if [[ -z "$ncnt" ]]; then
      echo "assemble-principle: ★chapters.amendment に ASCII 数字の件数「N ステップ」が無い (数詞は半角 ASCII 必須 = 漢数字等の照合回避を封鎖): $cv" >&2; errs=1
    else
      tcnt="$(q '.amendment.steps | length')"
      [[ "$ncnt" == "$tcnt" ]] || { echo "assemble-principle: ★chapters.amendment の数詞 ${ncnt} が amendment.steps 実件数 ${tcnt} と不一致 (件数 fabrication)" >&2; errs=1; }
    fi
  fi
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
/* ★folio-lffq: h3.ph の中身は strong 要素 (canonical constitution.html の dt/strong と同形で bin/folio の
   principle essence 抽出が要求する形)。 UA 既定の strong{font-weight:bolder} は継承値 800 を 900 へ
   押し上げ、 見出しの weight が row ごとに変わって見える。 inherit で従来の 800 を維持する (可視 weight 不変)。 */
.p-head .ph strong{font-weight:inherit}
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
/* ===== 節 rich 内容 (folio-lq12)。 生成物は common.css を link せず srs.css を inline するため、
   canonical 側の .reader-persona / .ai-rationale / figure.diagram の装飾は ★ここで pack-local に張る ===== */
[data-component="constitution-section-body"]{margin:2px 0 4px}
[data-component="constitution-section-body"] p{margin:8px 0;font-size:13.5px;line-height:1.85;color:var(--ink)}
[data-component="constitution-section-body"] ul{margin:8px 0;padding-left:22px}
[data-component="constitution-section-body"] li{margin:4px 0;font-size:13.5px;line-height:1.8;color:var(--ink)}
[data-component="constitution-section-body"] code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;background:var(--paper-2);border:1px solid var(--line);border-radius:5px;padding:1px 5px}
[data-component="constitution-section-body"] a{color:var(--brand);text-decoration:underline;text-underline-offset:2px}
/* reader-persona = 「誰向けの読み方か」を示す囲み。 canonical では common.css が装飾するため、 生成物では
   ★pack CSS で明示スタイルする (未装飾だと地の文と見分けがつかず読者導線が消える = P-14 面の退行)。 */
[data-component="constitution-section-body"] aside.reader-persona{border:1px solid var(--info-line);border-left:3px solid var(--info);border-radius:10px;background:var(--info-tint);padding:9px 14px;margin:9px 0}
[data-component="constitution-section-body"] aside.reader-persona p{margin:0;font-size:13px;line-height:1.8}
[data-component="constitution-section-body"] aside.reader-persona strong{color:var(--info)}
/* informative aside (文書前文の RFC 2119 キーワード解釈)。 */
[data-component="constitution-preamble"] aside.informative{border:1px solid var(--line);border-left:3px solid var(--brand);border-radius:10px;background:var(--paper-2);padding:10px 15px;margin:10px 0}
[data-component="constitution-preamble"] aside.informative p{margin:0;font-size:13px;line-height:1.8;color:var(--ink-soft)}
/* ai-rationale = AI 向け rationale。 canonical と同じく hidden 属性で ★既定非表示 (UA 既定)。 display を
   上書きすると 5 本が可視化するため、 hidden へ効く指定は置かない (下は hidden を外した時の体裁のみ)。 */
[data-component="principle-ai-rationale"]{border:1px dashed var(--line);border-radius:8px;background:var(--paper-2);padding:8px 12px;margin:6px 0 0;font-size:12.5px;line-height:1.75;color:var(--ink-faint)}
/* 図 (mermaid)。 ★donor = assemble-vision.sh:196-199 / assemble-arch.sh:206-209 / assemble-datamodel.sh:136-139 の
   figure.diagram .mermaid 形 (canonical constitution.html と同じ figure.diagram > pre.mermaid の入れ子)。
   ★assemble-spec.sh:442-445 の figure[data-component="spec-diagram"] 形を写さない (本 pack の figure は
   data-component が別値ゆえ、 写すと ★CSS があるのに効かない無音 = 375px viewport で horizontal-overflow の芽)。 */
figure.diagram{margin:12px 0}
figure.diagram .mermaid{overflow-x:auto;background:var(--paper);border:1px solid var(--line);border-radius:10px;padding:10px}
figure.diagram .mermaid:not([data-processed]){white-space:pre;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--ink-soft)}
figure.diagram figcaption{margin-top:6px;font-size:12px;color:var(--ink-soft);text-align:center}
CSS
}

# ---- pack 固有 folio-* head meta (folio-lffq・assemble-verification.sh:837-862 と同型) ----
# ★CORE (lib/common.sh core_emit_graph_head) は doc-type / status / version の 3 本固定で、 16 pack 共有ゆえ編集禁止。
#   canonical constitution.html:6-10 はさらに folio-layer / folio-stakeholders を持つ (実測 = 計 5 本)。 欠けると
#   inventory の layer 面と stakeholder 面が生成物で失われる。 ゆえ pack-level で contract.meta 由来 emit する (CORE 不触)。
#   値が無ければ tag ごと省略 = canonical に無い meta を捏造しない (canonical に無い folio-glossary-automark /
#   folio-xref-completeness は contract に値を置かない = 本 emitter も出さない)。
#   ★stakeholders の型 guard (scalar abort) は validate() 側に置いた (生成前 fail-closed で一括判定するため)。
emit_pack_head_meta() {
  local layer stake
  layer="$(q '.meta.layer // ""')"
  # meta tag の content は canonical 逐語 1 行 ("Developer, AI Agent, External Reviewer") が SSoT ゆえ join して復元する。
  stake="$(q '(.meta.stakeholders // []) | join(", ")')"
  [[ -n "$layer" && "$layer" != "null" ]] && printf '<meta name="folio-layer" content="%s">\n' "$(esc "$layer")"
  [[ -n "$stake" && "$stake" != "null" ]] && printf '<meta name="folio-stakeholders" content="%s">\n' "$(esc "$stake")"
  return 0
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio principle-pack assembler (folio-igv / instance#4) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_principle_css
  printf '\n</style>\n'
  # ★図 (mermaid) がある doc にだけ vendor を head へ 1 回 load (defer・図ゼロなら 1 バイトも出さない)。
  #   ★参照形は canonical constitution.html:24 と同形の ★../assets/mermaid.min.js に固定する。 donor に
  #     assemble-vision.sh:387 / assemble-datamodel.sh:394 の assets/ 形を使ってはならない (canonical と不一致)。
  #   ★gate F は HTML の親 dir を配信 root にするため assets/ と ../assets/ を ★区別できない
  #     (verify-common.sh の staging + serve(html.parent)・CI も同型) = gate F green を本 path の正しさの
  #     根拠に引用しない。 ゆえ literal を assembler 内に pin し、 書換えを敵対 case (AN-MJ4) が撃つ。
  [[ "${HAS_MERMAID:-0}" -gt 0 ]] && printf '<script src="%s" defer></script>\n' "$MERMAID_VENDOR_SRC"
  # 呼出順は core → pack (assemble-verification.sh の emit_head と同型)。 CORE が doc-type/status/version +
  # @type 付き JSON-LD を、 pack が layer/stakeholders を出す。
  core_emit_graph_head
  emit_pack_head_meta
  printf '</head>\n<body>\n'
}

# ★mermaid vendor 参照 path の literal pin (canonical constitution.html:24 と逐語同形)。
MERMAID_VENDOR_SRC='../assets/mermaid.min.js'

# ---- ★folio-lq12: 節 rich 内容の emitter ----
# raw = 逐語 inner-HTML blob を ★RAW emit (esc しない)。 validate_rich_inline が肯定 allowlist で検証済ゆえ
#   ここへ来る値は inline/block の非実行要素のみ。 ★prose slot への markup 注入 (inject-prose.sh:29 の esc /
#   :43 の単一行必須) や machine_blocks 経路 (data-audience=machine + details 既定非表示 = 人間層からの
#   relocation) は使わない (qojv 決定 5 系裁定 / P-14 回帰の封鎖)。
emit_raw_block() { printf '%s\n' "$(q ".sections[$1].blocks[$2].html")"; }

# mermaid = typed block。 render target = <pre class="mermaid"> (head の vendor が SVG 描画) + raw DSL を
#   逐語保持 (round-trip 維持)。 DSL 行は 1 行ずつ esc して注入する (esc 済ゆえ markup を成さない)。
emit_mermaid_block() {
  local si="$1" bi="$2" line first=1
  printf '<figure data-component="principle-diagram" class="diagram"><pre class="mermaid">'
  while IFS= read -r line; do
    [[ "$first" -eq 1 ]] && first=0 || printf '\n'
    printf '%s' "$(esc "$line")"
  done < <(q ".sections[$si].blocks[$bi].source_lines[]")
  printf '</pre><figcaption>%s</figcaption></figure>\n' "$(esc "$(q ".sections[$si].blocks[$bi].caption")")"
}

emit_section_blocks() {
  local si="$1" nb bi btype opened=0
  nb="$(q ".sections[$si].blocks // [] | length")"
  for ((bi=0; bi<nb; bi++)); do
    btype="$(q ".sections[$si].blocks[$bi].type")"
    case "$btype" in
      raw|mermaid)
        # rich 内容は 1 つの容器へまとめる (pack CSS の scope 単位 = 生成物で装飾が効く形)。
        [[ "$opened" -eq 1 ]] || { printf '<div data-component="constitution-section-body">\n'; opened=1; }
        [[ "$btype" == "raw" ]] && emit_raw_block "$si" "$bi" || emit_mermaid_block "$si" "$bi"
        ;;
      principles|versioning|amendment)
        [[ "$opened" -eq 0 ]] || { printf '</div>\n'; opened=0; }
        case "$btype" in
          principles) emit_principles_subsections "$si" ;;
          versioning) emit_versioning ;;
          amendment)  emit_amendment ;;
        esac
        ;;
      *) echo "assemble-principle: ★到達不能: emit 時に未対応 block type '$btype' (validate を擦り抜けた・fail-closed)" >&2; exit 1 ;;
    esac
  done
  [[ "$opened" -eq 0 ]] || printf '</div>\n'
}

# 節 (canonical <section id class>) を band 付きで emit。
# ★band() は lib/common.sh = CORE (16 pack 波及) ゆえ不触。 band が開く <section data-component="chapter-deck-band">
#   へ id を足せないため、 pack-level で ★章全体を anchor 付き <section> で包む (assemble-spec.sh:718-745 と同形・
#   canonical 実構造とも同形)。 folio_chrome_toc_rows は h2/h3 の TOC target を (a) 見出し自身の id →
#   (b) 最近接の外側 <section id> の 2 段 fallback で解決するため、 span sibling では解決しない (aduv 0-a)。
# ★band の kicker = canonical 節見出し (逐語)・h2 = 友好見出し という割当は spec-pack (h2=canonical) と ★逆。
#   本 pack は canonical 見出しが英語主体 (§1. Purpose / §7. Citations) で、 h2 に置くと非エンジニア既定
#   (北極星) を割るため。 canonical 見出しは kicker として逐語で保存し census/verify が束縛する。
emit_section() {
  local si="$1" anchor cls tint heading ch ck icon nsub sub_i
  anchor="$(q ".sections[$si].anchor")"; cls="$(q ".sections[$si].class")"
  tint="$(q ".sections[$si].tint")";     heading="$(q ".sections[$si].heading")"
  ch="$(q ".sections[$si].chapter_heading // \"\"")"; ck="$(q ".sections[$si].chapters_key // \"\"")"
  [[ -n "$ch" && "$ch" != "null" ]] || ch="$(q ".chapters.${ck}")"
  icon="${SECT_ICONS[$(( si % ${#SECT_ICONS[@]} ))]}"
  printf '<section id="%s" class="%s">\n' "$(esc "$anchor")" "$cls"
  band "$tint" "$heading" "$ch" "$icon"
  emit_section_blocks "$si"
  band_end
  printf '</section>\n'
}

# principles block = tier ごとの subsection (canonical <h3 id="s2-N-…">) を anchor 付き band で emit。
emit_principles_subsections() {
  local si="$1" nsub k anchor heading tier tint icon
  nsub="$(q ".sections[$si].subsections // [] | length")"
  for ((k=0; k<nsub; k++)); do
    anchor="$(q ".sections[$si].subsections[$k].anchor")"
    heading="$(q ".sections[$si].subsections[$k].heading")"
    tier="$(q ".sections[$si].subsections[$k].tier")"
    tint="${TIER_TINT[$tier]}"
    case "$tier" in Always) icon="$ICO_ALWAYS" ;; Ask-first) icon="$ICO_ASK" ;; *) icon="$ICO_NEVER" ;; esac
    printf '<section id="%s">\n' "$(esc "$anchor")"
    band "$tint" "$heading" "$(q ".chapters.${CK_TIER_KEY[$tier]}")" "$icon"
    emit_tier "$tier"
    band_end
    printf '</section>\n'
  done
}

# 文書前文 (canonical:58-60 の RFC 2119 aside)。 section の外・cover の直後に置く (canonical と同じ位置関係)。
emit_preamble() {
  printf '<div data-component="constitution-preamble">\n%s\n</div>\n' "$(q '.preamble_html')"
}

# 図がある doc にだけ mermaid.initialize を 1 回 emit (図ゼロなら何も出さない = 他 pack 非回帰の条件分岐も移植)。
# ★SSoT = canonical constitution.html:274-301 の <script> 要素 ★全体 (notes の 276-277 は内側 2 行であり
#   逐語切出しは壊れた断片になる)。 assemble-spec.sh:809-839 とは ★非同型 で、実測の差分は 2 点:
#     (1) assemble-spec 側のみ themeVariables に edgeLabelBackground: '#15324a' を持つ (canonical は持たない)。
#     (2) canonical 側のみ querySelectorAll の直前にコメント
#         「/* 横スクロールが発生した図のみ keyboard-focusable 化 (WCAG 2.2 SC 2.1.1、 rules §4.6) */」を持つ。
#   本 pack は ★canonical を SSoT とする (= 上記 2 点とも canonical 側に合わせる)。
emit_mermaid_script() {
  [[ "${HAS_MERMAID:-0}" -gt 0 ]] || return 0
  cat <<'MJS'
<script>
window.addEventListener('DOMContentLoaded', async () => {
  if (!window.mermaid) return;
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'antiscript',
    theme: 'base',
    flowchart: { useMaxWidth: false },
    themeVariables: {
      primaryColor: '#2a4d6e',
      primaryTextColor: '#ffffff',
      lineColor: '#2a4d6e',
      secondaryColor: '#5ac8b8',
      tertiaryColor: '#f5f8fa'
    }
  });
  try { await mermaid.run(); } catch (e) {}
  /* 横スクロールが発生した図のみ keyboard-focusable 化 (WCAG 2.2 SC 2.1.1、 rules §4.6) */
  document.querySelectorAll('figure.diagram > pre.mermaid').forEach((p) => {
    if (p.scrollWidth > p.clientWidth + 1) {
      p.tabIndex = 0;
      p.setAttribute('role', 'region');
      const t = p.querySelector('svg title');
      if (t && t.textContent) p.setAttribute('aria-label', t.textContent + ' (横スクロール可能な図)');
    }
  });
});
</script>
MJS
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
# ★navigable id (folio-lffq 裁定 3 = 案 A): h3.ph に id="p-N" を置き、 同一行に <strong>P-N: heading</strong> を
#   同居させる (canonical constitution.html:141 の `<dt id="p-1"><strong>P-1: TITLE</strong></dt>` と同形)。
#   ★strong の同居は必須: bin/folio:1468-1472 の principle essence 抽出は 「id="p-n" を *含む行* の中の strong 要素」
#   を要求し、 値は先頭 P-N: を剥がした文字列を返す。 strong を欠くと essence は空になり、 gate (i) は essence 空を
#   無言 skip (fail-open)・gate (h) は anchor 存在しか見ず・prime golden は essence 文字列を持たない = 全経路が沈黙する
#   (= class=xref の inbound tooltip SSoT が無言で失われる)。
#   ★id は data-slot-id とは *別属性* として増設する (data-slot-id を id へ rename / 転用すると inject-prose の
#   prose 充填が silent に壊れる)。 挿入位置は h3 の class 直後 = principle-row の data-component↔class 隣接
#   (verify-principle.sh) と p-head 内 pid→ph 隣接の双方を保つ。
emit_principle_row() {
  local pid="$1" anchor heading statement tier tlabel tclass namend
  anchor="$(q '.principles[] | select(.id=="'"$pid"'") | .anchor')"
  heading="$(q '.principles[] | select(.id=="'"$pid"'") | .heading')"
  statement="$(q '.principles[] | select(.id=="'"$pid"'") | .statement')"
  tier="$(q '.principles[] | select(.id=="'"$pid"'") | .tier')"
  tlabel="${TIER_LABEL[$tier]:-$tier}"; tclass="${TIER_CLASS[$tier]:-tier-unknown}"
  printf '<div data-component="principle-row" class="%s">\n' "$tclass"
  printf '<div class="p-head"><span class="pid">%s</span><h3 class="ph" id="%s"><strong>%s: %s</strong></h3><span data-component="principle-tier-badge" class="%s">%s</span></div>\n' \
    "$(esc "$pid")" "$(esc "$anchor")" "$(esc "$pid")" "$(esc "$heading")" "$tclass" "$(esc "$tlabel")"
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
  emit_ai_rationale "$pid"
  printf '</div>\n'
}

# ★folio-lq12: ai-rationale (canonical の <aside class="ai-rationale" hidden …>) を ★構造化 field から emit。
#   2 形ある — (a) amended_by[].rationale = 改訂来歴に紐づく理由文 (canonical の data-adr/data-decision/
#   data-decision-by 付き 4 本) / (b) rationale_note = data-rationale-for 付きの補足 rationale (P-12 の 1 本)。
#   ★hidden 属性で ★既定非表示 (canonical と同じ UA 既定挙動)。 hidden を落とすと 5 本が可視化して人間層の
#     読書体験を壊すため、 属性は必ず出す (verify が hidden の実在と本数を pin する)。
#   ★本文は esc 経由 (canonical の aside 本文は markup を持たない実測値ゆえ RAW にしない = RAW 面を広げない)。
emit_ai_rationale() {
  local pid="$1" n k adr date by text
  # ★@tsv を使わない (cell-quality round-1 confirmed・捏造の実弾): yq の @tsv は値に " を含む field を
  #   ★CSV quote する (全体を "…" で括り内部の " を "" へ倍化) ため、 P-2 の rationale
  #   (canonical の 「"(constitution / rules / folio-self-spec)"」 等) が ★6 文字の捏造つきで emit されていた。
  #   さらに verify 側も同じ @tsv 経路で期待値を作っていたため ★両側同時退行で vacuous PASS していた。
  #   ゆえ emit も verify も ★index 指定の単値取得 (@tsv を通さない) へ変える (自由文 field は原則この形)。
  n="$(q '.principles[] | select(.id=="'"$pid"'") | (.amended_by // []) | length')"
  for ((k=0; k<n; k++)); do
    [[ "$(q '.principles[] | select(.id=="'"$pid"'") | .amended_by['"$k"'] | has("rationale")')" == "true" ]] || continue
    adr="$(q '.principles[] | select(.id=="'"$pid"'") | .amended_by['"$k"'].adr')"
    date="$(q '.principles[] | select(.id=="'"$pid"'") | .amended_by['"$k"'].date')"
    by="$(q '.principles[] | select(.id=="'"$pid"'") | .amended_by['"$k"'].approved_by')"
    text="$(q '.principles[] | select(.id=="'"$pid"'") | .amended_by['"$k"'].rationale')"
    printf '<aside data-component="principle-ai-rationale" class="ai-rationale" hidden data-decision="%s" data-adr="%s" data-decision-by="%s">%s</aside>\n' \
      "$(esc "$date")" "$(esc "$adr")" "$(esc "$by")" "$(esc "$text")"
  done
  if [[ "$(q '.principles[] | select(.id=="'"$pid"'") | has("rationale_note")')" == "true" ]]; then
    printf '<aside data-component="principle-ai-rationale" class="ai-rationale" hidden data-rationale-for="%s" data-decided="%s">%s</aside>\n' \
      "$(esc "$(q '.principles[] | select(.id=="'"$pid"'") | .rationale_note.for')")" \
      "$(esc "$(q '.principles[] | select(.id=="'"$pid"'") | .rationale_note.decided')")" \
      "$(esc "$(q '.principles[] | select(.id=="'"$pid"'") | .rationale_note.text')")"
  fi
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
  # ★folio-lq12: li に class を刻む。 節骨格の導入で §1 の核心 list / §7 Citations という ★別由来の <li> が
  #   同一文書に入るため、 「body 全体の <li> を数える」形の arm は amendment steps の件数検査として恒真化する
  #   (実測: 5 → 19)。 amendment 由来の li を class で識別可能にし、 verify 側を class-scoped へ厳格化する。
  while IFS= read -r step; do [[ -n "$step" ]] && printf '<li class="amp-step">%s</li>\n' "$(esc "$step")"; done < <(q '.amendment.steps[]')
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
# ★instance タグは hardcode せず contract (.footer.instance_tag) から取る (folio-c5r.3 BLK-FOOTER-INSTANCE-TAG
#   と同根: instance#4 リテラルは 2nd instance の成果物に虚偽の出自を表示する)。 欠落時の既定は instance 非依存の中立句。
emit_footer() {
  local itag; itag="$(q '.footer.instance_tag // "canonical immutable principles"')"
  core_emit_footer "<span>folio design system</span><span>principle-pack</span><span>$(esc "$itag")</span><span>照会終端 + baseline-diff</span>"
}

build() {
  local nsec si
  # ★図 (mermaid block) が 1 つ以上ある doc にだけ vendor + initialize を 1 回 emit (図ゼロなら script 無し)。
  #   ★述語は principle-pack の実 schema (sections[].blocks[].type) から数える。 assemble-spec.sh:845 の
  #     導出式をそのまま流用してはならない (旧 principle contract に sections も blocks も無く常に 0 を返す)。
  #   ★「述語が 0 を返したのに生成物に pre class="mermaid" が在る」状態は ★無言不描画 (vendor も init も
  #     出ないまま図の DSL だけが出る) ゆえ、 principle_finalize が生成物を検査して fail-closed abort する。
  HAS_MERMAID="$(q '[.sections[]?.blocks[]? | select(.type=="mermaid")] | length')"
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  # 文書前文 (RFC 2119 キーワード解釈) は canonical と同じく §0 の直前・cover の直後。
  emit_preamble
  # ★節 (canonical §0〜§7) を contract 配列順で emit。 原則 / 版方針 / 手順 は各節の pack-native block として
  #   当該節の中へ入る (= 節骨格が文書の順序 SSoT・build 側に章順を焼かない)。
  nsec="$(q '.sections | length')"
  for ((si=0; si<nsec; si++)); do emit_section "$si"; done
  # inbound / glossary は canonical に対応節を持たない pack-native band (見出しは pack 不変文言)。
  band info   "この憲法を参照する文書 / inbound"  "原則は照会の終端 — 受ける照会だけをここに示す"  "$ICO_INBOUND";  emit_inbound;         band_end
  band brand  "用語集 / この文書で使う専門語"      "本文に出てくる専門語のやさしい説明"              "$ICO_BOOK";     emit_glossary;        band_end
  printf '</div>\n'
  emit_footer
  emit_mermaid_script
  printf '</body>\n</html>\n'
}

# ★core_finalize (lib/common.sh:221) と同型 + mermaid coherence guard。 lib は 1 バイトも触らないまま
#   「図の DSL は出たが vendor/init が出ていない」= 無言不描画 を生成段で構造封鎖するため pack-local に置く。
#   出力先が /dev/stdout でも成立するよう、 core と同じく一旦 tmp へ組んでから検査 → 送出する。
principle_finalize() {
  local tmp; tmp="$(mktemp)"; build > "$tmp"
  local npre nvendor ninit
  npre="$(grep -c '<pre class="mermaid">' "$tmp" || true)"
  nvendor="$(grep -cF "<script src=\"$MERMAID_VENDOR_SRC\" defer></script>" "$tmp" || true)"
  ninit="$(grep -c 'mermaid.initialize({' "$tmp" || true)"
  if [[ "$npre" -gt 0 && ( "$nvendor" -ne 1 || "$ninit" -ne 1 ) ]]; then
    rm -f "$tmp"
    echo "assemble-principle: ★mermaid 無言不描画 (図 $npre 個に対し vendor script $nvendor / initialize $ninit)。" >&2
    echo "  HAS_MERMAID 述語と emit 実体の乖離 = 図が描画されないまま DSL だけが出る状態ゆえ fail-closed abort。" >&2
    exit 1
  fi
  if [[ "$npre" -eq 0 && ( "$nvendor" -ne 0 || "$ninit" -ne 0 ) ]]; then
    rm -f "$tmp"
    echo "assemble-principle: ★図ゼロなのに mermaid vendor/init を emit (vendor $nvendor / initialize $ninit)。" >&2
    echo "  図ゼロ時は 1 バイトも出さない条件分岐が壊れている (他 pack 非回帰の条件・fail-closed abort)。" >&2
    exit 1
  fi
  if [[ "$OUT" == "/dev/stdout" ]]; then cat "$tmp"; rm -f "$tmp"; else mv "$tmp" "$OUT"; echo "$1: wrote $OUT" >&2; fi
}

validate
principle_finalize "assemble-principle"
