#!/usr/bin/env bash
# folio engine (folio-cuom) — bootstrap extractor: folio-self-spec.html → folio-self-spec.spec.yaml (one-shot)
#
# ★extract-verification-spec.sh の doc-type=spec 4例目への FORK (8dkl self-spec flip の bootstrap = Leg A)。 共有 core (lib/) 無改変。
# design-intent/spec/folio-self-spec.html を *read-only* で走査し、 spec-pack contract (folio-self-spec.spec.yaml) の
# DRAFT を起こす one-shot スクリプト。 ★出力は人間 (= 次サイクル admin) レビュー前提 (機械抽出の下書き)。
#
# ★self-spec 固有差分 (fork 元 verification.html に無い / 有る):
#   (1) ★要件 0 件 — self-spec は EARS 要件 (details.spec-row) を 1 件も持たない (規範 MUST の SSoT は rules.html §10)。
#       ゆえ requirements は ★明示的な空配列 で emit する (null は recapture-parity の malformed 判定・assembler の
#       length 参照に当たる = folio-cuom M4)。
#   (2) ★section id が ★非連番 — §0..§3 / §7..§9 (§4/5/6 は ★欠番)。 ゆえ @SECORDER を literal に持ち、
#       ★原本に在って @SECORDER に無い <section id> は fail-loud (下記 M1)。 fork 元は verification の id を
#       hardcode しており、 無改造で self-spec へ当てると exit 0・警告なしで「1 sections」へ silent collapse する。
#   (3) ★demoted / dl は self-spec に ★0 件 (実測)。 分岐は fork 元のまま ★残す (将来 canonical が持ったときに
#       silent drop しないため・分岐撤去は被覆の縮小)。
#   (4) ★mermaid の <br/> が 73 個 — fork 元 preline() は <br> を ★無置換除去する既知欠陥 (open: folio-bqzl /
#       folio-4ly3) を持つ。 本 fork は mermaid arm でのみ <br\s*/?> を ★改行へ変換する (下記 M2)。
#   (5) ★人間層 body list は 0 本 (ul/ol の human 祖先 0・dl 0)。 canonical に無い list を契約へ書き起こさない。
#
# 抽出する属性マーク (folio-self-spec.html の構造化された人間層):
#   - meta: <meta name="folio-*"> + doc-header
#   - sections: <section id> + <h2>/<h3> + <p class="section-essence">
#   - requirements (EARS): <details class="spec-row" id> → badge id / data-ears-pattern / .essence / p.ears(plain)
#   - glossary: <span class="term" data-term data-tooltip> (dedup by data-term)
#   - references (非終端 照会・前方): <a class="xref" href> + 外部 doc への <a href>
#     (constitution#p-* / ADR-* / verification#req-ver-* / ★self-spec 追加 arm = rules.html#req-* )
#   - content blocks (document 順): subhead(h3+essence) / table / code(pre>code) / mermaid(pre.mermaid) / requirements(spec-list)
#   - ★機械層自由文 (w1f cell-1 / ADR-0045): data-audience="machine" の <p>/<aside>/<ul>/<div class="demoted"> (rationale/context/運用説明/降格分) を
#     machine_preamble (文書前文) + sections[].machine_blocks (section 内) として *逐語* capture する (inner HTML 保持・p→prose / aside→note / ul→list / div.demoted→demoted)。
#
# ★silent drop 禁止 (no silent caps): 機械層自由文を skip せず逐語 capture し、 capture 件数を stderr に LOG する (旧版は範囲外として
#   件数のみ LOG していたが w1f cell-1 で skip→capture へ反転)。 capture 漏れ (live machine opener 数 ≠ capture 数) は ★uncaptured
#   警告を出して fail-loud にする。 人間層プレゼン (essence + subhead + 表 + 図 + 要件) は従来どおり構造化 field へ抽出する。
#
# usage: extract-self-spec-spec.sh [<folio-self-spec.html>] > <draft contract.yaml>   (LOG は stderr)
#        既定 = ★origin snapshot (.claude-plugin/design-system/generator/spec-origin/self-spec.origin.html)
#        env override = SELF_SPEC_ORIGIN_HTML (明示引数 $1 が最優先)
#
# ★★folio-mkwc (flip cell) M2(iii): 既定入力を live canonical から ★origin snapshot へ re-home した。
#   ★理由: flip 後 design-intent/spec/folio-self-spec.html は ★本 extractor 由来 contract の生成物 になる。
#     既定をそこへ向けたままだと「生成物から contract を起こして生成物と比べる」★自己比較 に退化し、
#     extractor の silent-collapse (rich→plain 退行・@SECORDER 不一致) を撃つ敵対 arm が ★恒真化 する
#     (範型 relations の RELATIONS_ORIGIN_HTML と同じ転換・ci.yml の明示注入も同理由)。
#   ★不在は exit 2 で fail-closed (旧 exit 1 から変更): 「入力が無いから抽出できなかった」を
#     ★測定系 error として gate 判定 (0/1) から分離する。 skip / 空出力に落とさない。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIF="${1:-${SELF_SPEC_ORIGIN_HTML:-$REPO_ROOT/.claude-plugin/design-system/generator/spec-origin/self-spec.origin.html}}"
[[ -f "$VERIF" ]] || { echo "extract-self-spec-spec: origin snapshot not found (fail-closed): $VERIF" >&2; exit 2; }
command -v perl >/dev/null || { echo "extract-self-spec-spec: perl required" >&2; exit 1; }

VERIF="$VERIF" perl -CSD -0777 <<'PERL'
use strict; use warnings;
my $file = $ENV{VERIF};
open(my $fh, "<:encoding(UTF-8)", $file) or die "open: $!";
local $/; my $H = <$fh>; close $fh;

# ---- helpers ----
sub decode_ent {
  my ($s) = @_;
  $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g;
  $s =~ s/&middot;/\xb7/g; $s =~ s/&rarr;/\x{2192}/g; $s =~ s/&larr;/\x{2190}/g;
  $s =~ s/&hellip;/\x{2026}/g; $s =~ s/&mdash;/\x{2014}/g; $s =~ s/&ndash;/\x{2013}/g;
  $s =~ s/&nbsp;/ /g; $s =~ s/&apos;/'/g; $s =~ s/&#39;/'/g;
  $s =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $s =~ s/&#(\d+);/chr($1)/ge;
  $s =~ s/&amp;/&/g;   # amp 最後 (二重 decode 回避)
  return $s;
}
# plain: タグ除去 + entity decode + 空白畳み + trim (1 行値用)。
# ★適用先は inline HTML を持たない field に限る (h2/h3 heading = 原本検証で tag 0)。 inline HTML を持つ
#   人間層 field (essence / statement / table cell) に使うと xref link / term tooltip / delta marker /
#   <code> mask が *silent に落ちる* (folio-aduv 実測: xref 25 / term 17 / delta 5 / code 374 が喪失) ため rich() を使う。
sub plain {
  my ($s) = @_; $s //= "";
  $s =~ s/<[^>]*>//g;
  $s = decode_ent($s);
  $s =~ s/\s+/ /g; $s =~ s/^\s+//; $s =~ s/\s+$//;
  return $s;
}
# ★rich: 人間層 field の inner HTML を *逐語* 保持する (folio-aduv / lossless flip 前置)。
#   plain() と違い タグ除去・entity decode をしない = inline 資産 (a.xref / span.term / ins|del.delta /
#   <code> / <strong>) が原本のまま契約へ入り、 assembler が raw emit して生成物で復元される。
#   ★<code>jq -S</code> の <code> mask も保存される = P-11 how-outside の「PRESERVE + mask」(0-e を同一機構で解決。
#     plain() が <code> を剥ぐと裸の jq -S が prose へ落ち folio_prose_only の mask を外れて [how-outside] FAIL になる)。
#   空白畳みのみゆえ tab/改行が消え core_validate_strings (tab/改行禁止) を通過し、 単一行で ys() の \\・" escape で閉じる。
#   機械層の inner_norm と同一規律 (raw 保持) を人間層へ広げたもの = 1 機構 (extract rich → assemble raw emit)。
# ★@RICHVALS = 契約へ実際に載った raw 値の台帳。 LOG の rich 資産 実数は *この実返り値* から数える
#   (field を列挙して数え直す式は field 追加時に静かにズレる = 実測を騙る LOG になる。 実際に契約へ入った値だけを数える)。
my @RICHVALS;
sub rich {
  my ($s) = @_; $s //= "";
  $s =~ s/\s+/ /g; $s =~ s/^\s+//; $s =~ s/\s+$//;
  push @RICHVALS, $s;
  return $s;
}
# preline: code/mermaid 行用 (タグ除去 + decode・leading space 保持・trailing trim・tab→space)。
# ★★M1 (folio-cuom errata-1 / 独立 ceiling blocking): <b> / </b> は ★逐語保持 する。
#   fork 元 preline() は ★全タグを無置換除去 するため、 canonical mermaid の subgraph ラベル強調
#   (<b>…</b> ★9 組 = 18 tag・実測) が契約へ入らず ★silent に消えていた (= errata folio-642 とは別の
#   ★未承認の第 2 delta。 flip すると canonical 側で恒久喪失する)。 <br> は M2 で ★改行へ変換 されるが、
#   <b> は改行のような等価表現を持たないため ★タグのまま運ぶ しかない。
#   ★mask → タグ除去 → decode → 復元 の 4 段: <b>/</b> ★だけ を保護し、 他の inline 資産は従来どおり
#   除去する (未対応資産は pre_inline_guard が ★fail-loud で止める = 静かに落とさない)。
#   ★対の remediate: assemble-self-spec.sh esc_mermaid() が この 2 literal だけ を raw へ戻し、
#   verify-self-spec.sh の同名 helper が期待側を同規律で作る (detect↔remediate parity)。
sub preline {
  my ($s) = @_; $s //= "";
  $s =~ s/<(\/?)b>/\x00$1b\x01/g;
  $s =~ s/<[^>]*>//g;
  $s = decode_ent($s);
  $s =~ s/\x00(\/?)b\x01/<$1b>/g;
  $s =~ s/\t/    /g; $s =~ s/\s+$//;
  return $s;
}
# YAML double-quoted scalar (安全 escape)。
sub ys { my ($s)=@_; $s//=""; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; return "\"$s\""; }

# ---- 機械層自由文 capture (w1f cell-1 / ADR-0045: skip→capture) ----
# inner_norm: 機械層 prose の inner HTML を *逐語* 保持する (タグ・entity を残し空白のみ単一空白へ畳む)。
#   plain()/preline() と異なり タグ除去・entity decode をしない (round-trip 逐語性・cell-2 が raw emit する前提)。
#   空白畳みのみゆえ tab/改行が消え core_validate_strings (tab/改行禁止) を通過し、 単一行で ys() の \\・" escape で閉じる。
sub inner_norm {
  my ($s) = @_; $s //= "";
  $s =~ s/\s+/ /g; $s =~ s/^\s+//; $s =~ s/\s+$//;
  push @RICHVALS, $s;   # ★機械層 blob も契約へ載る raw 値ゆえ rich 資産 LOG の計数母体に含める (rich() と同一台帳)。
  return $s;
}
# extract_machine_blocks: region 内の data-audience="machine" 自由文 (<p>/<aside>/<ul>/<div class="demoted">) を document 順に capture。
#   live tag のみ対象 (escape 済 code 例示 &lt;p は live に data-audience を持たないので除外 = escape 区別)。 p→prose / aside→note / ul→list / div.demoted→demoted。
#   aside は inner を一括保持 (内側 <p> は data-audience を持たず別 capture されない)。 ul は balanced match で nested list を誤終端しない。
#   ★demoted (verification 固有・ADR-0040 機械層降格分) は <div class="demoted" data-audience="machine"> の inner (<p>/<ul>/<pre><code> 等) を
#     balanced div match で一括 *逐語* capture (cell-2 が raw emit・round-trip で原本と双方向照合)。 inner の <p>/<ul> は data-audience を持たず別 capture されない。
#   返り値 (\@blocks, $expected)。 $expected = capture 漏れ検出用の live machine opener 数 (aside/demoted 内側は mask 済・no silent caps)。
sub extract_machine_blocks {
  my ($region) = @_;
  my @mb; my $p = 0;
  while ($p < length($region)) {
    my %cand;
    if (substr($region,$p) =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>/)    { $cand{prose} = $p + $-[0]; }
    if (substr($region,$p) =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>/) { $cand{note}  = $p + $-[0]; }
    if (substr($region,$p) =~ /<ul\b[^>]*\sdata-audience="machine"[^>]*>/)    { $cand{list}  = $p + $-[0]; }
    if (substr($region,$p) =~ /<div\b[^>]*\bclass="demoted"[^>]*\sdata-audience="machine"[^>]*>/) { $cand{demoted} = $p + $-[0]; }
    # ★dl (folio-aduv): <dl class="doc-meta" data-audience="machine"> = 文書前文の機械層 定義リスト。 旧版は p/aside/ul/div.demoted
    #   のみ対象で <dl> が *死角* であり、 しかも expected 計数 (下記) も <dl> を数えないため ★uncaptured 警告すら出ない
    #   = no-silent-caps 規律を擦り抜ける silent drop だった (実測: canonical term 27 のうち 1 件 (data-term="spec") が本 dl 内で
    #   契約へ入らず喪失)。 chrome ではない (folio:chrome-toc 閉じマーカーより後 = bin/folio の chrome 再生成範囲外) ため
    #   契約責任領域であり capture する。 dl は nested <dl> を持たない (原本検証済) ゆえ非貪欲で正しく閉じる。
    if (substr($region,$p) =~ /<dl\b[^>]*\sdata-audience="machine"[^>]*>/)    { $cand{dl}    = $p + $-[0]; }
    last unless %cand;
    my ($kind) = sort { $cand{$a} <=> $cand{$b} } keys %cand;
    my $at = $cand{$kind};
    if ($kind eq "prose") {
      substr($region,$at) =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/p>/s;
      push @mb, { type=>"prose", html=>inner_norm($1) }; $p = $at + $+[0];
    } elsif ($kind eq "note") {
      substr($region,$at) =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/aside>/s;
      push @mb, { type=>"note", html=>inner_norm($1) }; $p = $at + $+[0];
    } elsif ($kind eq "dl") {
      # ★dl (folio-aduv): inner (<div><dt>..</dt><dd>..</dd></div> 列) を逐語 capture (cell-2 が raw emit・round-trip 照合)。
      substr($region,$at) =~ /<dl\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/dl>/s;
      push @mb, { type=>"dl", html=>inner_norm($1) }; $p = $at + $+[0];
    } elsif ($kind eq "demoted") {
      # ★balanced <div> match で demoted の閉じ </div> を見つける (非貪欲は inner pre/code の </div> 等で誤終端しうる・
      #   speclist と同型の depth 追跡)。 inner を逐語 capture (round-trip で原本 div.demoted と双方向照合)。
      my $sub = substr($region, $at);
      $sub =~ /^<div\b[^>]*>/; my $open_len = $+[0];
      my $depth = 0; my $end_off = length($sub);
      while ($sub =~ /(<div\b[^>]*>|<\/div>)/g) {
        my $tok = $1; my $te = pos($sub);
        if ($tok =~ /^<div/) { $depth++; } else { $depth--; if ($depth == 0) { $end_off = $te; last; } }
      }
      my $whole = substr($sub, 0, $end_off);
      my $inner = substr($whole, $open_len, length($whole) - $open_len - length("</div>"));
      push @mb, { type=>"demoted", html=>inner_norm($inner) }; $p = $at + $end_off;
    } else {
      my $sub = substr($region, $at);
      my $depth = 0; my $end_off = length($sub); my $open_len = 0;
      while ($sub =~ /(<ul\b[^>]*>|<\/ul>)/g) {
        my $tok = $1; my $te = pos($sub);
        if ($tok =~ /^<ul/) { $depth++; $open_len = $te if $depth == 1; }
        else { $depth--; if ($depth == 0) { $end_off = $te; last; } }
      }
      my $whole = substr($sub, 0, $end_off);
      my $inner = substr($whole, $open_len, length($whole) - $open_len - length("</ul>"));
      # ★top-level <li> を nested <ul>/<ol> 深さを追って切る (naive 非貪欲 (.*?)</li> は nested list 内の </li> で
      #   早期終端し top-level 項目を silent 分割するため・w1f cell-1 errata)。 nested list は親 <li> の inner に逐語保持。
      my @items;
      while ($inner =~ /<li\b[^>]*>/g) {
        my $li_start = pos($inner);
        my $ldepth = 0; my $li_end = -1;
        while ($inner =~ /(<(?:ul|ol)\b[^>]*>|<\/(?:ul|ol)>|<\/li>)/g) {
          my $t = $1;
          if    ($t =~ /^<(?:ul|ol)/)   { $ldepth++; }
          elsif ($t =~ /^<\/(?:ul|ol)>/){ $ldepth--; }
          elsif ($ldepth == 0)          { $li_end = $-[0]; last; }   # depth 0 の </li> = この項目の終端
        }
        last if $li_end < 0;
        push @items, inner_norm(substr($inner, $li_start, $li_end - $li_start));
        pos($inner) = $li_end;
      }
      push @mb, { type=>"list", items=>\@items }; $p = $at + $end_off;
    }
  }
  # expected: aside / demoted を mask (一括 capture 済) してから p/ul/aside/demoted opener を数える (nested を二重計上しない)。
  #   ★demoted の inner <p>/<ul> は data-audience を持たないため n_p/n_ul に計上されないが、 mask して防御的に対称化する。
  my $masked = $region;
  my $n_aside = () = ($masked =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>.*?<\/aside>/gs);
  $masked =~ s/<aside\b[^>]*\sdata-audience="machine"[^>]*>.*?<\/aside>//gs;
  my $n_dem = () = ($masked =~ /<div\b[^>]*\bclass="demoted"[^>]*\sdata-audience="machine"[^>]*>/g);
  $masked =~ s/<div\b[^>]*\bclass="demoted"[^>]*\sdata-audience="machine"[^>]*>.*?<\/div>//gs;
  # ★dl も mask してから数える (folio-aduv): inner の <div>/<dt>/<dd> は data-audience を持たないので二重計上しないが、
  #   aside/demoted と対称に mask する。 ★本 n_dl を expected へ加算することが silent drop 封鎖の要 —
  #   capture 側だけ足して expected を据え置くと、 dl の取り逃しが再び ★uncaptured 警告なしで素通る (fail-open)。
  my $n_dl = () = ($masked =~ /<dl\b[^>]*\sdata-audience="machine"[^>]*>/g);
  $masked =~ s/<dl\b[^>]*\sdata-audience="machine"[^>]*>.*?<\/dl>//gs;
  my $n_p  = () = ($masked =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>/g);
  my $n_ul = () = ($masked =~ /<ul\b[^>]*\sdata-audience="machine"[^>]*>/g);
  return (\@mb, $n_aside + $n_dem + $n_dl + $n_p + $n_ul);
}
# emit_mblocks: machine block 列を YAML 出力 (key=machine_preamble|machine_blocks, indent=0|4)。 空なら key を出さない。
sub emit_mblocks {
  my ($key, $indent, $blocks) = @_;
  return if !@$blocks;
  my $pad = " " x $indent; my $ipad = " " x ($indent + 2);
  print "${pad}$key:\n";
  for my $b (@$blocks) {
    if ($b->{type} eq "list") {
      print "${ipad}- type: list\n${ipad}  items:\n";
      print "${ipad}    - ", ys($_), "\n" for @{$b->{items}};
    } else {
      print "${ipad}- { type: ", $b->{type}, ", html: ", ys($b->{html}), " }\n";
    }
  }
}

my @LOG;

# ---- meta ----
my %meta;
$meta{version} = ($H =~ /<meta name="folio-version" content="([^"]*)"/) ? $1 : "1.0.0";
$meta{status}  = ($H =~ /<meta name="folio-status" content="([^"]*)"/) ? $1 : "active";
my $stake = ($H =~ /<meta name="folio-stakeholders" content="([^"]*)"/) ? $1 : "Developer, AI Agent";
my $hmeta = ($H =~ /<div class="meta">(.*?)<\/div>/s) ? plain($1) : "";
# ★head meta 同期 (folio-aduv 0-c): core_emit_graph_head (lib/=CORE・全 pack 共有) は doc-type/status/version の
#   3 本しか emit しない。 canonical verification.html はさらに folio-layer / folio-glossary-automark /
#   folio-stakeholders / folio-xref-completeness を持つ (実測 = 計 7 本) ため、 pack 固有 field として契約へ同期し
#   assemble-verification.sh emit_head が contract.meta 由来で emit する (CORE 不触・glossary pack の per-pack emit と同型)。
#   ★folio-xref-completeness は「実 emit を実測で確定」(2mla 0-c 保留分) → canonical に content="enabled" が *実在* を確認済ゆえ同期対象。
$meta{layer}         = ($H =~ /<meta name="folio-layer" content="([^"]*)"/) ? $1 : "";
$meta{automark}      = ($H =~ /<meta name="folio-glossary-automark" content="([^"]*)"/) ? $1 : "";
$meta{xref_complete} = ($H =~ /<meta name="folio-xref-completeness" content="([^"]*)"/) ? $1 : "";

# ---- glossary (span.term[data-term][data-tooltip]) dedup ----
my (%gseen, @gloss);
while ($H =~ /<span class="term"[^>]*\bdata-term="([^"]*)"[^>]*\bdata-tooltip="([^"]*)"[^>]*>(.*?)<\/span>/gs) {
  my ($term, $tip, $disp) = ($1, $2, $3);
  $term = decode_ent($term); $disp = plain($disp); $tip = plain($tip);
  next if $gseen{$term}++;
  # en = canonical token (data-term)、 def = tooltip。 term = 表示語 (disp)。 ★core emit_glossary は空 en で
  #   IFS=tab read が空フィールドを畳む既存 bug ゆえ en は必ず非空 (canonical を入れる)。
  push @gloss, { term => $disp ne "" ? $disp : $term, en => $term, def => $tip };
}

# ---- requirements (details.spec-row[id]) ----
my @reqs;
while ($H =~ /<details class="spec-row" id="([^"]*)"[^>]*>(.*?)<\/details>/gs) {
  my ($rid, $body) = ($1, $2);
  my $badge = ($body =~ /<span class="badge badge--req">([^<]*)<\/span>/) ? $1 : "";
  # ★essence / statement は rich() = inline HTML 逐語 (xref link / term tooltip / delta marker / <code> mask を保存)。
  #   旧 plain() は これらを silent に落としていた (実測: essence xref2/term7/delta0・statement xref10/term10/delta5)。
  my $ess   = ($body =~ /<span class="essence">(.*?)<\/span>\s*<\/summary>/s) ? rich($1) : "";
  my $pat   = ($body =~ /data-ears-pattern="([^"]*)"/) ? $1 : "";
  my $stmt  = ($body =~ /<p class="ears"[^>]*>(.*?)<\/p>/s) ? rich($1) : "";
  next unless $badge;
  # ★anchor = canonical の実 id 属性 (小文字 req-ver-* / req-nav-*) を *逐語 capture* する (folio-aduv 0-a)。
  #   lc($badge) で導出せず原本 SSoT を運ぶ (導出は canonical との drift を silent に飲む)。 corpus inbound
  #   (#req-ver-* / #req-nav-*) の解決先ゆえ、 assembler が row へ id= として emit する。
  push @reqs, { id => $badge, pat => $pat, ess => $ess, stmt => $stmt, anchor => $rid };
}

# ---- references (前方 照会・外部 doc): a.xref / a[href] → constitution#p-* / ADR-NNNN / verification#req-ver-* ----
# token / doc / role を distinct に集める (初出順保持)。 role: principle→implementation / decision→rationale / verification→verification。
my (%rseen, @refs);
sub addref { my ($tok,$doc,$role)=@_; my $k="$tok|$doc"; return if $rseen{$k}++; push @refs, { token=>$tok, doc=>$doc, role=>$role }; }
# constitution P-N
while ($H =~ /href="[^"]*constitution\.html#p-(\d+)"/g) { addref("P-$1", "constitution.html", "implementation"); }
# verification REQ-VER-NNN (doc は basename を capture で判別 — greedy [^"]* が srs- prefix を吸収して
# srs-verification.html を verification.html へ誤帰属する fail-open を封鎖 = pyus ceiling 実証・0853249 の
# extract-rules-spec.sh 側 fix を本 fork へ移植 (folio-6lsu)。 07m 分割で REQ-VER-024〜030 が
# srs-verification.html へ移った以上、 本 fork も同じ穴を持てない)。
while ($H =~ /href="[^"]*?((?:srs-)?verification)\.html#req-ver-(\d+)"/g) { addref("REQ-VER-".sprintf("%03d",$2), "$1.html", "verification"); }
# ADR-NNNN (decisions/ADR-NNNN-*.html)
while ($H =~ /href="[^"]*decisions\/ADR-(\d{4})-[^"]*"/g) { addref("ADR-$1", "decisions/", "rationale"); }
# ---- ★self-spec 追加 arm (folio-cuom・手起こし 2 点のうち 1): rules.html#req-* (規約要件への前方照会) ----
# ★fork 元 arm は constitution P-x / (srs-)verification REQ-VER / ADR の 3 種しか拾わず、 self-spec が持つ
#   rules.html#req-* (実測 distinct 8: REQ-CI-001/010/011/012/014/016 / REQ-CM-001 / REQ-DA-STRUCT-1) が ★未捕捉 だった。
#   self-spec は「規範 MUST 要件の SSoT は rules.html §10」と繰り返し宣言し ★実際に anchor 付きで前方照会する ため、
#   落とすと 照会 graph の前方 edge が 8 本欠ける (over-promise でなく ★under-capture 側の silent drop)。
# ★role = claim ("この文書が満たすと主張する要件"・ROLE_OK allowlist 内)。 constitution P-x の implementation
#   (原則の実装宣言) とも ADR の rationale (決定根拠) とも別種ゆえ、 既存 role を流用せず 4 種目として立てる。
# ★token 正規化: 原本 anchor は小文字 (#req-ci-010 / #req-da-struct-1) だが、 照会 token は ★大文字 canonical
#   (REQ-CI-010 / REQ-DA-STRUCT-1) が SSoT (rules.html の badge 表記・corpus 横断の 1 entity = 1 canonical name)。
#   ★数値部の zero-pad は ★しない — REQ-VER-* (3 桁 pad) と違い rules 側 canonical は素の桁 (REQ-DA-STRUCT-1) ゆえ、
#   pad すると canonical に存在しない token を捏造する。
# ★§ anchor (#s10-1 / #s7-dual-audience 等) は ★拾わない: defined-object でなく節への案内リンクであり、
#   照会 chip の token になる canonical ID を持たない (拾うと token 空間が汚れる)。
while ($H =~ /href="[^"]*rules\.html#(req-[a-z0-9-]+)"/g) { addref(uc($1), "rules.html", "claim"); }

# ---- sections (top-level <section id>) ----
# 各 top-level section の inner を doc 順に走査し block を抽出する。 nested <section> (§10.1 等) は親に内包されるが、
# §10 の inner 走査で h3 を subhead として拾う (二重 nest の inner section tag は plain 除去で透過)。
# top-level section 抽出: <section id="sN" class="..."> ... </section> の最外側。 §10 は nested を含むため balanced
# にせず「次の top-level <section id」直前まで」で切る方が安全だが、 ここでは正規表現で各 top-level を順に取り、
# nested section open/close tag は block 抽出時に無視する (h3/table/pre/spec-list マーカーのみ拾う)。
my %TINT = (
  s0=>"info", s1=>"brand", s2=>"violet", s3=>"info", s7=>"warn", s8=>"ok", s9=>"brand",
);
my %KICK = (
  s0=>"§0 / 読み方", s1=>"§1 / 2 層構造", s2=>"§2 / repo Layout", s3=>"§3 / 二層提示",
  s7=>"§7 / harness 部品", s8=>"§8 / plugin 統合", s9=>"§9 / 実装への橋渡し",
);
# folio-self-spec.html の実 section id (full form)。 contract section.id は short prefix (s0..s3 / s7..s9) を使う (TINT/KICK の key)。
# ★§4/5/6 は ★欠番 (canonical に存在しない = 正常)。 番号の連続性は不変条件ではない。
my @SECORDER = qw(s0-reader-guide s1-architecture s2-folio-layout s3-dual-audience
                  s7-harness s8-plugin s9-bindings);
sub shortid { my ($f)=@_; return ($f =~ /^(s\d+)/) ? $1 : $f; }

# ---- ★M1 (folio-cuom): @SECORDER と ★原本の実 <section id> 集合の ★完全一致 を fail-loud で要求する ----
# ★fork 元の欠陥 (実測・2 lens 一致): @SECORDER は fork 元 doc の id を hardcode しており、 別 doc へ無改造で
#   当てると 各 id の match が全て空振りして SECINNER が空になり、 ★exit 0・警告なし で「1 sections」等へ
#   silent collapse する (= 抽出の大半が無言で消える fail-open)。 fork の第一手として ★両方向 の集合一致を課す:
#     (a) 原本に在って @SECORDER に無い id  → ★未知 section の silent drop (本 M1 の主たる封鎖対象)
#     (b) @SECORDER に在って原本に無い id  → ★stale な fork 定数 (silent collapse の直接原因)
#   ★§番号の欠番 (§4/5/6) は ★正常として通す — 検査するのは ★id 集合の一致 であって番号の連続性ではない。
# ★nested <section> は canonical に存在しない (実測 0) が、 将来現れたら (a) 側で fail-loud になる = 意図どおり
#   (未知の入れ子を無言で親へ畳まない)。
{
  my @doc_ids;
  while ($H =~ /<section\b[^>]*\bid="([^"]*)"[^>]*>/g) { push @doc_ids, $1; }
  my %want = map { $_ => 1 } @SECORDER;
  my %have = map { $_ => 1 } @doc_ids;
  my @unknown = grep { !$want{$_} } @doc_ids;
  my @missing = grep { !$have{$_} } @SECORDER;
  my @dup = do { my %s; grep { $s{$_}++ == 1 } @doc_ids };
  if (@unknown || @missing || @dup) {
    print STDERR "extract-self-spec-spec: \x{2605}@SECORDER と原本 <section id> の集合が不一致 (fail-loud・silent collapse 封鎖)\n";
    print STDERR "  原本の section id (", scalar(@doc_ids), "): @doc_ids\n";
    print STDERR "  \@SECORDER (", scalar(@SECORDER), "): @SECORDER\n";
    print STDERR "  \x{2605}未知 (原本に在り SECORDER に無い): @unknown\n" if @unknown;
    print STDERR "  \x{2605}欠落 (SECORDER に在り原本に無い): @missing\n" if @missing;
    print STDERR "  \x{2605}重複 id: @dup\n" if @dup;
    exit 1;
  }
  # ★TINT/KICK の被覆も同時に課す (short id の取りこぼしは band の tint/kicker を静かに既定値へ落とす)。
  for my $f (@SECORDER) {
    my $s = shortid($f);
    unless (exists $TINT{$s} && exists $KICK{$s}) {
      print STDERR "extract-self-spec-spec: \x{2605}%TINT / %KICK に short id '$s' ($f) の項が無い (band 属性の silent 既定化を封鎖)\n";
      exit 1;
    }
  }
}

# ---- ★M1 (folio-cuom errata-1): <pre> 内 inline 資産の ★閉集合 guard (未対応資産の silent 喪失を fail-closed 化) ----
# ★動機 (独立 ceiling blocking M1): preline() は 元来 ★全タグを無置換除去 しており、 canonical mermaid の
#   <b>…</b> 18 tag が ★警告なしで消えていた。 <b> は逐語保持へ是正した (preline) が、 ★次に別の inline 資産
#   (<i> / <em> / <sup> …) が canonical へ入ったときに ★同じ事故が再演する。 ゆえ「preline に通る <pre> の中に
#   現れてよい ★出現 literal」を ★閉集合 として宣言し、 外れたら ★抽出を止める (silent drop でなく fail-loud)。
#     - mermaid pre  : { <b>, </b>, <br> / <br/> / <br /> }  … b = 逐語保持 / br = 改行へ変換 (M2)
#     - code pre     : { <code>, </code> }                    … <pre><code> wrapper literal のみ (実測)
# ★★粒度 (errata-1 self-review 是正・declared == actual): 判定は ★tag 名 (lc + 属性無視) ではなく
#   ★出現 literal 全体 で行う。 下流の 保存 / 変換 述語は ★完全 literal だから:
#     - preline の mask      = s/<(\/?)b>/…/g          … 属性付き `<b class="x">` も 大文字 `<B>` も ★当たらない
#     - M2 の <br> 変換      = s/<br\s*\/?>/\n/g        … case-sensitive
#     - code 本体の抽出      = /<pre><code>(.*?)<\/code><\/pre>/s … literal 一致
#   tag 名で allow すると これらが guard を ★通過したまま preline に silent 除去 / 不均衡化 される
#   (実測 shape: `<b class="x">HOLE</b>` は開始タグだけ消えて `HOLE</b>` が契約へ残った) = ★粒度不一致 fail-open。
#   ★scan する pattern も preline が ★実際に剥ぐ pattern (<[^>]*>) と同一にして、
#   「剥がれうる出現 ⊆ allowlist literal」を byte 単位で強制する。
# ★entity guard: mermaid pre 内に '<' / '>' へ decode される entity が在ると、 preline の decode_ent が
#   ★原本では文字列 だったものを裸の < > にし、 assembler の esc → esc_mermaid が '&lt;b&gt;' を raw へ戻す規律で
#   ★live タグへ昇格 させうる (曖昧化)。 named (&lt; &gt;) だけでなく ★numeric ref (&#60; &#x3C; …) も
#   decode_ent は復号する ゆえ、 ★decode 結果で 判定する (literal 列挙は取りこぼす = 同じ粒度不一致)。
#   canonical mermaid の実測は 0 件ゆえ、 現れたら ★止める (機構を広げる判断を次の cell へ明示的に渡す)。
# ★残余 net (backstop): preline 相当の変換を ★実際に適用 し、 復元後の文字列に <b>/</b> 以外の
#   「タグに見える形」が ★残っていない ことを assert する。 ★射程を正確に言う: 上の 2 guard を抜けるのは
#   ★閉じ '>' を持たない 生の '<' (例: 本文中の `<foo` — <[^>]*> にも entity にも当たらず preline が
#   ★そのまま契約へ運ぶ) のクラスであり、 これは assembler では esc される ゆえ ★live タグ昇格ではない。
#   ただし 原本の literal と 逐語保持タグ の ★区別が崩れる 入力 (= 多くは malformed HTML) ゆえ止める。
#   ★live タグ昇格 そのものを閉じているのは 上の literal allowlist + entity guard の 2 本である。
my %PRE_INLINE;   # tag 名 → occurrence (mermaid pre 内・LOG と census の母体)
{
  my %ALLOW_LIT = (
    'mermaid' => qr{\A(?:<b>|</b>|<br\s*/?>)\z},
    'code'    => qr{\A(?:<code>|</code>)\z},
  );
  my $npre = 0;
  while ($H =~ /<pre\b([^>]*)>(.*?)<\/pre>/gs) {
    my ($attr, $body) = ($1, $2); $npre++;
    my $kind = ($attr =~ /class="mermaid"/) ? 'mermaid' : 'code';
    my (%lit, @bad);
    while ($body =~ /(<[^>]*>)/g) {   # ★preline が剥ぐ pattern と ★同一
      my $l = $1;
      if ($l =~ $ALLOW_LIT{$kind}) { $lit{$l}++; } else { push @bad, $l; }
    }
    if (@bad) {
      my %u; my @show = grep { !$u{$_}++ } @bad;
      print STDERR "extract-self-spec-spec: \x{2605}<pre> ($kind・第 $npre 個) に ★未対応の inline 資産: @show\n";
      print STDERR "  \x{2605}判定は ★literal 単位 (属性付き / 大文字 / 別 tag はいずれも非該当)。 preline() は これらを\n";
      print STDERR "  \x{2605}★無置換除去 する = 契約へ入らず flip で恒久喪失する (folio-cuom errata-1 M1)。\n";
      print STDERR "  \x{2605}対処: preline() / esc_mermaid() / 凍結 census (FZ_PRE_*) を同時に拡張するか、 原本から外すこと。\n";
      exit 1;
    }
    if ($kind eq 'mermaid') {
      for my $l (keys %lit) { my ($t) = $l =~ m{\A<\s*/?\s*([a-zA-Z][a-zA-Z0-9]*)}; $PRE_INLINE{lc $t} += $lit{$l}; }
      my (@ebad, %eu);
      while ($body =~ /(&\#?[0-9a-zA-Z]+;)/g) {
        my $e = $1; my $d = decode_ent($e);
        push @ebad, $e if ($d eq '<' || $d eq '>') && !$eu{$e}++;
      }
      if (@ebad) {
        print STDERR "extract-self-spec-spec: \x{2605}mermaid <pre> (第 $npre 個) に '<'/'>' へ decode される entity: @ebad\n";
        print STDERR "  \x{2605}named / numeric ref を問わず preline() の decode_ent が復号するため、 assembler の\n";
        print STDERR "  \x{2605}esc_mermaid() が 原本の ★文字列 を ★live タグ へ昇格させうる (曖昧化) = fail-loud。\n";
        exit 1;
      }
      # ★残余 net: preline 相当を実適用し、 復元後に <b>/</b> 以外の tag 形が残らないことを assert。
      my $sim = $body;
      $sim =~ s/<br\s*\/?>/\n/g;              # M2 (mermaid arm)
      $sim =~ s/<(\/?)b>/\x00$1b\x01/g;       # preline mask
      $sim =~ s/<[^>]*>//g;
      $sim = decode_ent($sim);
      $sim =~ s/\x00(\/?)b\x01/<$1b>/g;
      my $probe = $sim; $probe =~ s{</?b>}{}g;
      if ($probe =~ /(<\s*\/?\s*[a-zA-Z][a-zA-Z0-9]*)/) {
        print STDERR "extract-self-spec-spec: \x{2605}mermaid <pre> (第 $npre 個): preline 後の文字列に <b>/</b> 以外の\n";
        print STDERR "  \x{2605}tag 形 ('$1…') が残る = 原本の literal と 逐語保持タグ の区別が崩れる (fail-loud・errata-1 M1 残余 net)。\n";
        exit 1;
      }
    }
  }
  push @LOG, sprintf("pre inline 資産 (mermaid・閉集合 guard 通過): %s",
    join(" ", map { "$_=$PRE_INLINE{$_}" } sort keys %PRE_INLINE) || "(なし)");
}

# section の inner を抽出: 各 top-level id について <section id="ID"> から、 次の top-level <section id か </body 直前まで。
my %SECINNER;
for my $i (0..$#SECORDER) {
  my $id = $SECORDER[$i];
  my $next = ($i < $#SECORDER) ? $SECORDER[$i+1] : undef;
  my $startre = qr/<section id="\Q$id\E"[^>]*>/;
  next unless $H =~ /$startre/g;
  my $start = pos($H);
  my $end;
  if (defined $next) {
    if ($H =~ /<section id="\Q$next\E"[^>]*>/g) { $end = pos($H) - length($&); }
  }
  $end //= ($H =~ /<!-- folio:chrome-bottom -->/ ? index($H,"<!-- folio:chrome-bottom -->") : length($H));
  pos($H) = 0;
  $SECINNER{$id} = substr($H, $start, $end - $start);
}

# section heading + essence + block 抽出。
my @sections;
for my $id (@SECORDER) {
  my $inner_full = $SECINNER{$id} // next;   # ★ORIGINAL (machine_blocks capture 用・demoted 含む)。
  # ★block scan 用 inner = demoted (機械層・<pre><code> 内包しうる) を mask した copy。 demoted の inner pre/code を
  #   human-layer code block として誤捕捉するのを防ぐ (machine_blocks は $inner_full から別途 capture ゆえ情報は落ちない)。
  #   非貪欲 mask: demoted は nested div を持たず inner に </div> リテラルも無い (verification.html 検証済) ゆえ最初の </div> で正しく閉じる。
  my $inner = $inner_full;
  $inner =~ s/<div\b[^>]*\bclass="demoted"[^>]*\sdata-audience="machine"[^>]*>.*?<\/div>//gs;
  # ★heading (h2/h3) は plain() 継続 = 原本検証で inline tag 0 件 (rich 化は無意味な契約 diff を生むだけ)。
  my $heading = ($inner =~ /<h2>(.*?)<\/h2>/s) ? plain($1) : $id;
  # top-level section の最初の section-essence (h2 直後) を section essence とする。 ★rich() = inline HTML 逐語。
  my $essence = ($inner =~ /<p class="section-essence"[^>]*>(.*?)<\/p>/s) ? rich($1) : "";
  my @blocks;

  # doc 順走査: block opener を左から順に処理する。 各 iteration で最も近い opener を見つけて処理し pos を進める。
  pos($inner) = 0;
  my $p = 0;
  while ($p < length($inner)) {
    # 候補 opener の位置を集める。
    my %cand;
    # h3 (subhead) — 最初の h2 essence は別途取得済ゆえ h3 のみ subhead 化。
    if (substr($inner,$p) =~ /<h3[^>]*>/) { $cand{h3} = $p + $-[0]; }
    if (substr($inner,$p) =~ /<table\b[^>]*>/) { $cand{table} = $p + $-[0]; }
    if (substr($inner,$p) =~ /<pre class="mermaid">/) { $cand{mermaid} = $p + $-[0]; }
    if (substr($inner,$p) =~ /<pre><code>/) { $cand{code} = $p + $-[0]; }
    if (substr($inner,$p) =~ /<div class="spec-list">/) { $cand{speclist} = $p + $-[0]; }
    last unless %cand;
    # 最小位置の opener。
    my ($kind) = sort { $cand{$a} <=> $cand{$b} } keys %cand;
    my $at = $cand{$kind};

    if ($kind eq "h3") {
      substr($inner,$at) =~ /<h3\b([^>]*)>(.*?)<\/h3>/s;
      my $h3attr = $1; my $h3 = plain($2); my $afterh3 = $at + $+[0];
      # ★fine section anchor (folio-aduv 0-a): h3 の実 id 属性を逐語 capture (原本 18/18 が id 保有)。
      #   corpus inbound の 81 link がこの fine anchor 宛て = 落とすと link-integrity が破断する。
      my $h3id = ($h3attr =~ /\bid="([^"]*)"/) ? $1 : "";
      # h3 直後の section-essence を subhead essence にする (無ければ空)。 ★rich() = inline HTML 逐語。
      # ★★folio-cuom で是正した ★silent drop (fork 元は substr(...,600) の ★長さ上限窓 で探していた):
      #   窓は「隣接性」を担保するつもりの最適化だが、 隣接性を担保しているのは ★^\s* anchor の方であり、
      #   窓長は「essence 全体が 600 byte に収まるか」という ★無関係な条件 を暗黙に足していた。 self-spec の
      #   §3.4 / §7.1 は essence が inline HTML 込みで 600 byte を超えるため、 ★警告なしで空 essence になった
      #   (実測: 13 subhead 中 2 本が空 = 生成物の該当 subsection が本文ゼロ見出しになる)。
      #   ★是正 = 窓を外し ★anchor だけで隣接性を担保する (^\s* は h3 直後に ★空白しか許さない ため、
      #   後続の別 subsection の essence を誤って拾うことはない)。 長さに依存する silent 打ち切りを構造から除去。
      my $se = "";
      if (substr($inner,$afterh3) =~ /^\s*<p class="section-essence"[^>]*>(.*?)<\/p>/s) { $se = rich($1); }
      push @blocks, { type=>"subhead", heading=>$h3, essence=>$se, anchor=>$h3id };
      $p = $afterh3;
    } elsif ($kind eq "table") {
      substr($inner,$at) =~ /<table\b[^>]*>(.*?)<\/table>/s;
      my $tbl = $1; my $afterend = $at + $+[0];
      # ★caption / th / td は rich() = inline HTML 逐語 (実測: table 全体で xref13 / a12 / code41 / strong11 を保存)。
      my $cap = ($tbl =~ /<caption>(.*?)<\/caption>/s) ? rich($1) : "";
      my @headers; while ($tbl =~ /<th\b[^>]*>(.*?)<\/th>/gs) { push @headers, rich($1); }
      my @rows;
      while ($tbl =~ /<tr\b[^>]*>(.*?)<\/tr>/gs) {
        my $tr = $1; next unless $tr =~ /<td/;   # header 行 (th のみ) は skip
        my @cells; while ($tr =~ /<td\b[^>]*>(.*?)<\/td>/gs) { push @cells, rich($1); }
        push @rows, \@cells if @cells;
      }
      push @blocks, { type=>"table", caption=>$cap, headers=>\@headers, rows=>\@rows } if @headers && @rows;
      $p = $afterend;
    } elsif ($kind eq "mermaid") {
      substr($inner,$at) =~ /<pre class="mermaid">(.*?)<\/pre>/s;
      my $src = $1; my $afterend = $at + $+[0];
      # figcaption (直後の figure 内) を caption に。 ★rich() = inline HTML 逐語 (原本 figcaption は <code> 2 +
      #   span.term 1 を持つ = canonical term 27 番目の在処。 plain() だと この 1 件が silent に落ちて occurrence-parity が破れる)。
      # ★★folio-cuom で是正した ★silent drop (fork 元は substr(...,400) の ★長さ上限窓 + ★非 anchor 探索):
      #   (a) 窓長 400 は figcaption 全体が収まる保証が無く、 self-spec の 図 1 (長い caption) が ★無警告で
      #       空になった (実測: 9 図中 8 図しか caption を持たない契約になった)。
      #   (b) 非 anchor 探索 (窓内のどこでもよい) は、 窓を広げると ★次の図の figcaption を誤って拾う。
      #   ★是正 = 窓を外し ★^\s* anchor へ寄せる。 原本の figure は </pre> の直後に空白のみを挟んで
      #   <figcaption> が来る形 (9/9 実測) ゆえ anchor で厳密に、 かつ長さ非依存に取れる。
      my $cap = "";
      if (substr($inner,$afterend) =~ /^\s*<figcaption>(.*?)<\/figcaption>/s) { $cap = rich($1); }
      # ---- ★M2 (folio-cuom): mermaid DSL 内の <br> を ★改行へ変換してから行分割する ----
      # ★fork 元 preline() は タグを ★無置換除去 する (既知欠陥・open: folio-bqzl 恒久修正 / folio-4ly3 round-trip 検査)。
      #   verification / rules は mermaid に <br> を持たないため露出しなかったが (既 flip 2 本で 6 / 4 個が喪失済)、
      #   self-spec は 9 mermaid に ★73 個 を持つ (12〜18 倍の露出) — 無置換除去だと node label の改行が全消滅し
      #   「design-intent/spec/(Layer 1 spec…)」のように ★語が無言で連結 する。
      # ★なぜ <br> のまま契約へ運ばないのか: assembler は source_lines を esc() して <pre class="mermaid"> へ出すため
      #   契約に <br/> を残すと生成物では &lt;br/&gt; へ escape され ★可視文字列として露出する (原本の live <br> と別物)。
      #   一方 ★改行 は esc() を素通りし、 再抽出 (round-trip) でも同じ行分割へ戻る = 契約 ↔ 生成物 ↔ 再抽出 が閉じる。
      # ★scope は ★mermaid arm のみ (M2 明示)。 code arm / rich field は fork 元の規律を 1 byte も変えない。
      $src =~ s/<br\s*\/?>/\n/g;
      my @lines = map { preline($_) } split(/\n/, $src, -1);
      shift @lines while @lines && $lines[0] eq "";   # 先頭空行除去
      pop @lines while @lines && $lines[-1] eq "";     # 末尾空行除去
      push @blocks, { type=>"mermaid", caption=>$cap, source_lines=>\@lines } if @lines;
      $p = $afterend;
    } elsif ($kind eq "code") {
      substr($inner,$at) =~ /<pre><code>(.*?)<\/code><\/pre>/s;
      my $src = $1; my $afterend = $at + $+[0];
      my @lines = map { preline($_) } split(/\n/, $src, -1);
      shift @lines while @lines && $lines[0] eq "";
      pop @lines while @lines && $lines[-1] eq "";
      push @blocks, { type=>"code", lines=>\@lines } if @lines;
      $p = $afterend;
    } elsif ($kind eq "speclist") {
      # ★balanced <div> マッチで spec-list の閉じ </div> を見つける (nested spec-normative div があるため
      #   非貪欲 (.*?)+lookahead は最初の inner </div> で誤終端する = REQ-ADR-001 等を取り逃した bug の修正)。
      my $sub = substr($inner, $at);
      my $depth = 0; my $end_off = 0;
      while ($sub =~ /(<div\b[^>]*>|<\/div>)/g) {
        my $tok = $1; my $tokend = pos($sub);
        if ($tok =~ /^<div/) { $depth++; } else { $depth--; if ($depth == 0) { $end_off = $tokend; last; } }
      }
      $end_off = length($sub) if $end_off == 0;
      my $block = substr($sub, 0, $end_off);
      my @ids; while ($block =~ /<details class="spec-row" id="[^"]*"[^>]*>.*?<span class="badge badge--req">([^<]*)<\/span>/gs) { push @ids, $1; }
      push @blocks, { type=>"requirements", ids=>\@ids } if @ids;
      $p = $at + $end_off;
    }
  }
  # ★機械層自由文 capture (skip→capture・w1f cell-1)。 section inner の data-audience="machine" prose を document 順に取り込む。
  #   ★ORIGINAL ($inner_full) から capture する (demoted を含む・block scan 用 masked $inner ではない)。
  my ($mblocks, $mexp) = extract_machine_blocks($inner_full);
  my $mcap = scalar(@$mblocks);
  push @LOG, "section $id: 機械層 prose capture $mcap 件 (data-audience=machine の <p>/<aside>/<ul>/div.demoted を逐語取り込み)"
    . ($mcap == $mexp ? "" : " ★uncaptured " . ($mexp - $mcap) . " 件 (expected $mexp・要調査)");
  # ★anchor = canonical の top-level section 実 id (s0-reader-guide 等・full form)。 contract の id は short prefix
  #   (s0..s6 = TINT/KICK の key) ゆえ、 corpus inbound (#s1-contract 等) の解決先となる full id を別 field で運ぶ
  #   (id を full 化すると TINT/KICK key と band 実装へ波及するため anchor を追加する = CORE 不触の最小形)。
  push @sections, { id=>shortid($id), anchor=>$id, heading=>$heading, essence=>$essence, blocks=>\@blocks, machine_blocks=>$mblocks };
}

# ★機械層 preamble (最初の section より前の文書前文 = RFC2119 / constitution 実装宣言の boilerplate aside)。
#   section に属さない body 直下の data-audience="machine" prose を別 capture する (tr0 汎用: 他文書も body 先頭 boilerplate を持つ)。
my $preamble_region = ($H =~ /^(.*?)<section id="/s) ? $1 : "";
my ($preamble_blocks, $pre_exp) = extract_machine_blocks($preamble_region);
{
  my $pcap = scalar(@$preamble_blocks);
  push @LOG, "preamble: 機械層 prose capture $pcap 件 (section 外の文書前文)"
    . ($pcap == $pre_exp ? "" : " ★uncaptured " . ($pre_exp - $pcap) . " 件 (expected $pre_exp・要調査)");
}

# ===== YAML 出力 =====
print "# folio engine (folio-cuom) — spec-pack contract (instance#4 doc-type=spec / folio-self-spec self-host)\n";
print "# ★機械抽出 DRAFT (scripts/extract-self-spec-spec.sh が design-intent/spec/folio-self-spec.html から起こした)。 人間レビュー前提。\n";
print "# doc_type = spec (folio 自身の self-spec)。 ★要件 0 件 (規範 MUST の SSoT は rules.html §10) + 非終端 照会 (前方 references)。\n";
print "# ★抽出範囲 = folio-self-spec.html の人間層 (section essence + subhead + 表 + 図(mermaid source) + 用語 + 照会) + 機械層自由文 (w1f cell-1 / tr0)。\n";
print "#   機械層 = data-audience=\"machine\" の <p>/<aside>/<ul>/<div class=\"demoted\"> を machine_preamble (文書前文) + sections[].machine_blocks (section 内) に *逐語* capture。\n";
print "#   ★self-spec 実測: demoted / dl は 0 件・人間層 body list (human 祖先の ul/ol/dl) も 0 本。 分岐は fork 元のまま残す (被覆の縮小をしない)。\n";
print "\n";
print "meta:\n";
# ★M3 (folio-cuom): meta identity は self-spec 実体へ ★全面差し替え。 doc_type == spec は 4 契約が共有し
#   識別力ゼロゆえ、 fork した assemble/verify の入口は doc_id (FOLIO-SELF-SPEC) を literal guard に使う。
print "  doc_id: FOLIO-SELF-SPEC\n";
print "  doc_type: spec\n";
# ★title は canonical JSON-LD の dc:title 逐語 ("folio self-spec") に合わせる — core_emit_graph_head が
#   .meta.title を dc:title へ ★そのまま 転記するため、 ここが graph の値そのものになる (h1 も同値で canonical 一致)。
print "  title: ", ys("folio self-spec"), "\n";
print "  eyebrow_left: ", ys("仕様 (Spec)"), "\n";
print "  eyebrow_right: ", ys("folio — Layer 0 META FRAMEWORK 自身の architecture spec"), "\n";
print "  subtitle: ", ys($hmeta ne "" ? $hmeta : "folio Layer 0 framework 自身の architecture spec"), "\n";
print "  version: ", ys($meta{version}), "\n";
print "  date: ", ys("2026-08-04"), "\n";
print "  status: ", ys($meta{status}), "\n";
print "  reader: ", ys("$stake — folio を consume する開発者・AI Agent・外部レビュアー"), "\n";
# ★head meta 同期 (0-c): CORE (core_emit_graph_head) が emit しない pack 固有 folio-* meta を契約 SSoT として運ぶ。
#   値が空なら key ごと省略 (assembler も空なら emit しない = canonical に無い meta を捏造しない)。
#   stakeholders は reader (散文) と別に canonical 逐語を独立 field 化する (meta tag は逐語が SSoT)。
print "  layer: ", ys($meta{layer}), "\n" if $meta{layer} ne "";
print "  glossary_automark: ", ys($meta{automark}), "\n" if $meta{automark} ne "";
print "  xref_completeness: ", ys($meta{xref_complete}), "\n" if $meta{xref_complete} ne "";
# ★stakeholders は ★YAML sequence で持つ (scalar string 禁止)。 CORE (lib/common.sh core_emit_graph_head) が
#   同じ .meta.stakeholders を JSON-LD の "folio:stakeholders" へ *そのまま* 転記するため、 scalar で入れると
#   canonical の array (["Developer","AI Agent","External Reviewer"]) が string へ型退行する (CORE 不触でも
#   contract 経由で CORE 出力を壊す = fence HIGH-2 の意図違反)。 どの既存 gate も捕捉しない (jsonld-lint は
#   folio:stakeholders を型検査対象外と明記・inventory は非 array を捨てて meta split fallback で隠蔽) ため
#   契約側で canonical と同型に固定するのが唯一の構造的封鎖。 meta tag 側 (逐語 1 行) は assembler が join して復元する。
my @stake_list = grep { $_ ne "" } split(/\s*,\s*/, $stake);
print "  stakeholders: [", join(", ", map { ys($_) } @stake_list), "]\n" if @stake_list;
print "\n";
print "# 承認記録 (core 共用 approval-block)。 folio-self-spec.html は署名欄を持たないため doc lifecycle を忠実に再提示する (synthesized chrome)。\n";
print "approval:\n";
print "  - { role: ", ys("文書種別"), ", who: ", ys("spec (folio self-spec)"), ", when: ", ys("v$meta{version}"), ", stamp: ", ys($meta{status}), " }\n";
print "  - { role: ", ys("生成 (engine spec-pack)"), ", who: ", ys("folio design system"), ", when: ", ys("2026-08-04 生成"), ", stamp: ", ys("生成"), " }\n";
print "\n";
print "# ★非終端 照会の graph 接続: folio-self-spec → constitution (FOLIO-CONSTITUTION 終端) の前方 edge (role=implementation)。\n";
print "#   self-spec は constitution P-x (P-3 / P-7 / P-11 / P-12 等) を前方照会し実装する (folio:extends constitution)。\n";
print "graph:\n";
print "  principle_edge: { target_doc_id: FOLIO-CONSTITUTION, role: implementation }\n";
print "\n";
# ★機械層 preamble (w1f cell-1): section に属さない文書前文の data-audience="machine" prose を逐語 capture。
emit_mblocks("machine_preamble", 0, $preamble_blocks);
print "\n" if @$preamble_blocks;
print "sections:\n";
for my $s (@sections) {
  print "  - id: ", ys($s->{id}), "\n";
  print "    anchor: ", ys($s->{anchor}), "\n";
  print "    tint: ", ys($TINT{$s->{id}} // "brand"), "\n";
  print "    kicker: ", ys($KICK{$s->{id}} // $s->{id}), "\n";
  print "    heading: ", ys($s->{heading}), "\n";
  print "    essence: ", ys($s->{essence}), "\n";
  if (@{$s->{blocks}}) {
    print "    blocks:\n";
    for my $b (@{$s->{blocks}}) {
      if ($b->{type} eq "subhead") {
        print "      - { type: subhead, anchor: ", ys($b->{anchor}), ", heading: ", ys($b->{heading}), ", essence: ", ys($b->{essence}), " }\n";
      } elsif ($b->{type} eq "requirements") {
        print "      - type: requirements\n        ids: [", join(", ", map { ys($_) } @{$b->{ids}}), "]\n";
      } elsif ($b->{type} eq "table") {
        print "      - type: table\n";
        print "        caption: ", ys($b->{caption}), "\n";
        print "        headers: [", join(", ", map { ys($_) } @{$b->{headers}}), "]\n";
        print "        rows:\n";
        for my $r (@{$b->{rows}}) { print "          - [", join(", ", map { ys($_) } @$r), "]\n"; }
      } elsif ($b->{type} eq "code") {
        print "      - type: code\n        lines:\n";
        for my $l (@{$b->{lines}}) { print "          - ", ys($l), "\n"; }
      } elsif ($b->{type} eq "mermaid") {
        print "      - type: mermaid\n        caption: ", ys($b->{caption}), "\n        source_lines:\n";
        for my $l (@{$b->{source_lines}}) { print "          - ", ys($l), "\n"; }
      }
    }
  } else {
    print "    blocks: []\n";
  }
  # ★機械層自由文 (section 内・data-audience="machine") を blocks の sibling として出力 (cell-2 が canonical form へ)。
  emit_mblocks("machine_blocks", 4, $s->{machine_blocks});
}
print "\n";
# ★M4 (folio-cuom): requirements は ★空でも null にせず ★明示的な空配列 で書く。
#   null は (a) verify-recapture-parity.sh の malformed 判定に当たり (b) assembler の `.requirements | length`
#   参照が null 起点になる。 「要件が無い」ことを ★型として宣言する (欠落と区別できる形にする)。
if (!@reqs) { print "requirements: []\n"; }
else {
print "requirements:\n";
for my $r (@reqs) {
  print "  - id: ", ys($r->{id}), "\n";
  print "    anchor: ", ys($r->{anchor}), "\n";
  print "    ears_pattern: ", ys($r->{pat}), "\n";
  print "    essence: ", ys($r->{ess}), "\n";
  print "    statement: ", ys($r->{stmt}), "\n";
}
}
print "\n";
print "# 非終端 照会 (前方・他文書へ)。 constitution P-x (implementation) / ADR (rationale) / verification REQ-VER (verification)\n";
print "#   / ★rules.html REQ-* (claim・self-spec 追加 arm = 規約要件への前方照会)。\n";
print "references:\n";
for my $r (@refs) {
  print "  - { token: ", ys($r->{token}), ", doc: ", ys($r->{doc}), ", role: ", ys($r->{role}), " }\n";
}
print "\n";
print "# 用語集 (core 共用 glossary-term-table)。 term = 表示語 / en = canonical (data-term) / def = data-tooltip 由来定義。\n";
print "glossary:\n";
for my $g (@gloss) {
  print "  - { term: ", ys($g->{term}), ", en: ", ys($g->{en}), ", def: ", ys($g->{def}), " }\n";
}

# ===== LOG (silent drop 禁止: capture 件数を stderr へ・uncaptured があれば ★ 警告) =====
print STDERR "=== extract-self-spec-spec LOG (no silent caps) ===\n";
print STDERR "$_\n" for @LOG;
my $mtot = scalar(@$preamble_blocks); $mtot += scalar(@{$_->{machine_blocks}}) for @sections;
my ($mprose, $mnote, $mlist, $mdem, $mdl) = (0,0,0,0,0);
for my $b (@$preamble_blocks, map { @{$_->{machine_blocks}} } @sections) {
  $mprose++ if $b->{type} eq "prose"; $mnote++ if $b->{type} eq "note"; $mlist++ if $b->{type} eq "list";
  $mdem++ if $b->{type} eq "demoted"; $mdl++ if $b->{type} eq "dl";
}
printf STDERR "抽出: %d sections / %d requirements / %d references / %d glossary terms\n",
  scalar(@sections), scalar(@reqs), scalar(@refs), scalar(@gloss);
printf STDERR "機械層 prose capture: %d 件 (prose=%d / note=%d / list=%d / demoted=%d / dl=%d・preamble %d 件含む)\n",
  $mtot, $mprose, $mnote, $mlist, $mdem, $mdl, scalar(@$preamble_blocks);
# ★rich 資産 LOG (folio-aduv・no silent caps): 人間層 rich field + 機械層 blob に載った inline 資産の実数を出す。
#   契約へ *何が入ったか* を抽出時点で可視化し、 assembler 側 occurrence-parity assert の期待値と突き合わせられるようにする。
{
  my $all = join("\x1e", @RICHVALS);
  my $x = () = ($all =~ /<a\b[^>]*\bclass="xref"/g);
  my $t = () = ($all =~ /<span class="term"/g);
  my $d = () = ($all =~ /<(?:ins|del)\b[^>]*\bclass="delta"/g);
  my $c = () = ($all =~ /<code>/g);
  printf STDERR "rich 資産 capture: a.xref=%d / span.term=%d / ins|del.delta=%d / <code>=%d (人間層 rich field + 機械層 blob の実返り値 %d 本を計数)\n",
    $x, $t, $d, $c, scalar(@RICHVALS);
}
PERL
