#!/usr/bin/env bash
# folio engine tr0 (folio-hd0) — bootstrap extractor: relations.html → folio-relations.spec.yaml (one-shot)
#
# architecture/spec/relations.html を *read-only* で走査し、 spec-pack contract (folio-relations.spec.yaml) の
# DRAFT を起こす one-shot スクリプト。 ★出力は人間 (= 次サイクル admin) レビュー前提 (機械抽出の下書き)。
# ★spec-pack fork (scripts/extract-rules-spec.sh から fork・共有 core 無改変)。 relations の section/meta/graph へ差し替えただけ。
#
# 抽出する属性マーク (relations.html の構造化された人間層):
#   - meta: <meta name="folio-*"> + doc-header
#   - sections: <section id> + <h2>/<h3> + <p class="section-essence">
#   - requirements (EARS): <details class="spec-row" id> → badge id / data-ears-pattern / .essence / p.ears(plain)
#   - glossary: <span class="term" data-term data-tooltip> (dedup by data-term)
#   - references (非終端 照会・前方): <a class="xref" href> + 外部 doc への <a href> (constitution#p-* / ADR-* / verification#req-ver-*)
#   - content blocks (document 順): subhead(h3+essence) / table / code(pre>code) / mermaid(pre.mermaid) / requirements(spec-list)
#   - ★機械層自由文 (w1f cell-1 / ADR-0045): data-audience="machine" の <p>/<aside>/<ul> (rationale/context/運用説明) を
#     machine_preamble (文書前文) + sections[].machine_blocks (section 内) として *逐語* capture する (inner HTML 保持・p→prose / aside→note / ul→list)。
#
# ★silent drop 禁止 (no silent caps): 機械層自由文を skip せず逐語 capture し、 capture 件数を stderr に LOG する (旧版は範囲外として
#   件数のみ LOG していたが w1f cell-1 で skip→capture へ反転)。 capture 漏れ (live machine opener 数 ≠ capture 数) は ★uncaptured
#   警告を出して fail-loud にする。 人間層プレゼン (essence + subhead + 表 + 図 + 要件) は従来どおり構造化 field へ抽出する。
#
# usage: extract-relations-spec.sh [<relations.html>] > <draft contract.yaml>   (LOG は stderr)
#        既定 <relations.html> = <repo-root>/architecture/spec/relations.html

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELATIONS="${1:-$REPO_ROOT/architecture/spec/relations.html}"
[[ -f "$RELATIONS" ]] || { echo "extract-relations-spec: relations.html not found: $RELATIONS" >&2; exit 1; }
command -v perl >/dev/null || { echo "extract-relations-spec: perl required" >&2; exit 1; }

RELATIONS="$RELATIONS" perl -CSD -0777 <<'PERL'
use strict; use warnings;
my $file = $ENV{RELATIONS};
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
sub plain {
  my ($s) = @_; $s //= "";
  $s =~ s/<[^>]*>//g;
  $s = decode_ent($s);
  $s =~ s/\s+/ /g; $s =~ s/^\s+//; $s =~ s/\s+$//;
  return $s;
}
# preline: code/mermaid 行用 (タグ除去 + decode・leading space 保持・trailing trim・tab→space)。
sub preline {
  my ($s) = @_; $s //= "";
  $s =~ s/<[^>]*>//g;
  $s = decode_ent($s);
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
  return $s;
}
# extract_machine_blocks: region 内の data-audience="machine" 自由文 (<p>/<aside>/<ul>) を document 順に capture。
#   live tag のみ対象 (escape 済 code 例示 &lt;p は live に data-audience を持たないので除外 = escape 区別)。 p→prose / aside→note / ul→list。
#   aside は inner を一括保持 (内側 <p> は data-audience を持たず別 capture されない)。 ul は balanced match で nested list を誤終端しない。
#   返り値 (\@blocks, $expected)。 $expected = capture 漏れ検出用の live machine opener 数 (aside 内側は mask 済・no silent caps)。
sub extract_machine_blocks {
  my ($region) = @_;
  my @mb; my $p = 0;
  while ($p < length($region)) {
    my %cand;
    if (substr($region,$p) =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>/)    { $cand{prose} = $p + $-[0]; }
    if (substr($region,$p) =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>/) { $cand{note}  = $p + $-[0]; }
    if (substr($region,$p) =~ /<ul\b[^>]*\sdata-audience="machine"[^>]*>/)    { $cand{list}  = $p + $-[0]; }
    last unless %cand;
    my ($kind) = sort { $cand{$a} <=> $cand{$b} } keys %cand;
    my $at = $cand{$kind};
    if ($kind eq "prose") {
      substr($region,$at) =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/p>/s;
      push @mb, { type=>"prose", html=>inner_norm($1) }; $p = $at + $+[0];
    } elsif ($kind eq "note") {
      substr($region,$at) =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/aside>/s;
      push @mb, { type=>"note", html=>inner_norm($1) }; $p = $at + $+[0];
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
  # expected: aside を mask (一括 capture 済) してから p/ul/aside opener を数える (nested を二重計上しない)。
  my $masked = $region;
  my $n_aside = () = ($masked =~ /<aside\b[^>]*\sdata-audience="machine"[^>]*>.*?<\/aside>/gs);
  $masked =~ s/<aside\b[^>]*\sdata-audience="machine"[^>]*>.*?<\/aside>//gs;
  my $n_p  = () = ($masked =~ /<p\b[^>]*\sdata-audience="machine"[^>]*>/g);
  my $n_ul = () = ($masked =~ /<ul\b[^>]*\sdata-audience="machine"[^>]*>/g);
  return (\@mb, $n_aside + $n_p + $n_ul);
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
  my $ess   = ($body =~ /<span class="essence">(.*?)<\/span>\s*<\/summary>/s) ? plain($1) : "";
  my $pat   = ($body =~ /data-ears-pattern="([^"]*)"/) ? $1 : "";
  my $stmt  = ($body =~ /<p class="ears"[^>]*>(.*?)<\/p>/s) ? plain($1) : "";
  next unless $badge;
  push @reqs, { id => $badge, pat => $pat, ess => $ess, stmt => $stmt };
}

# ---- references (前方 照会・外部 doc): a.xref / a[href] → constitution#p-* / ADR-NNNN / verification#req-ver-* ----
# token / doc / role を distinct に集める (初出順保持)。 role: principle→implementation / decision→rationale / verification→verification。
my (%rseen, @refs);
sub addref { my ($tok,$doc,$role)=@_; my $k="$tok|$doc"; return if $rseen{$k}++; push @refs, { token=>$tok, doc=>$doc, role=>$role }; }
# constitution P-N
while ($H =~ /href="[^"]*constitution\.html#p-(\d+)"/g) { addref("P-$1", "constitution.html", "implementation"); }
# verification REQ-VER-NNN
while ($H =~ /href="[^"]*verification\.html#req-ver-(\d+)"/g) { addref("REQ-VER-".sprintf("%03d",$1), "verification.html", "verification"); }
# ADR-NNNN (decisions/ADR-NNNN-*.html)
while ($H =~ /href="[^"]*decisions\/ADR-(\d{4})-[^"]*"/g) { addref("ADR-$1", "decisions/", "rationale"); }

# ---- sections (top-level <section id>) ----
# 各 top-level section の inner を doc 順に走査し block を抽出する。 nested <section> (§10.1 等) は親に内包されるが、
# §10 の inner 走査で h3 を subhead として拾う (二重 nest の inner section tag は plain 除去で透過)。
# top-level section 抽出: <section id="sN" class="..."> ... </section> の最外側。 §10 は nested を含むため balanced
# にせず「次の top-level <section id」直前まで」で切る方が安全だが、 ここでは正規表現で各 top-level を順に取り、
# nested section open/close tag は block 抽出時に無視する (h3/table/pre/spec-list マーカーのみ拾う)。
my %TINT = (
  s0=>"info", s1=>"brand", s2=>"violet", s3=>"info", s4=>"warn", s5=>"ok", s6=>"brand",
);
my %KICK = (
  s0=>"§0 / 読み方", s1=>"§1 / W3C 標準語彙", s2=>"§2 / folio 独自語彙", s3=>"§3 / JSON-LD",
  s4=>"§4 / inventory", s5=>"§5 / 双方向参照", s6=>"§6 / 参照",
);
# relations.html の実 section id (full form)。 contract section.id は short prefix (s0..s6) を使う (TINT/KICK の key)。
my @SECORDER = qw(s0-reader-guide s1-w3c-vocab s2-folio-vocab s3-jsonld s4-inventory s5-bidirectional s6-refs);
sub shortid { my ($f)=@_; return ($f =~ /^(s\d+)/) ? $1 : $f; }

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
  my $inner = $SECINNER{$id} // next;
  my $heading = ($inner =~ /<h2>(.*?)<\/h2>/s) ? plain($1) : $id;
  # top-level section の最初の section-essence (h2 直後) を section essence とする。
  my $essence = ($inner =~ /<p class="section-essence"[^>]*>(.*?)<\/p>/s) ? plain($1) : "";
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
      substr($inner,$at) =~ /<h3[^>]*>(.*?)<\/h3>/s;
      my $h3 = plain($1); my $afterh3 = $at + $+[0];
      # h3 直後の section-essence を subhead essence にする (無ければ空)。
      my $se = "";
      if (substr($inner,$afterh3,600) =~ /^\s*<p class="section-essence"[^>]*>(.*?)<\/p>/s) { $se = plain($1); }
      push @blocks, { type=>"subhead", heading=>$h3, essence=>$se };
      $p = $afterh3;
    } elsif ($kind eq "table") {
      substr($inner,$at) =~ /<table\b[^>]*>(.*?)<\/table>/s;
      my $tbl = $1; my $afterend = $at + $+[0];
      my $cap = ($tbl =~ /<caption>(.*?)<\/caption>/s) ? plain($1) : "";
      my @headers; while ($tbl =~ /<th\b[^>]*>(.*?)<\/th>/gs) { push @headers, plain($1); }
      my @rows;
      while ($tbl =~ /<tr\b[^>]*>(.*?)<\/tr>/gs) {
        my $tr = $1; next unless $tr =~ /<td/;   # header 行 (th のみ) は skip
        my @cells; while ($tr =~ /<td\b[^>]*>(.*?)<\/td>/gs) { push @cells, plain($1); }
        push @rows, \@cells if @cells;
      }
      push @blocks, { type=>"table", caption=>$cap, headers=>\@headers, rows=>\@rows } if @headers && @rows;
      $p = $afterend;
    } elsif ($kind eq "mermaid") {
      substr($inner,$at) =~ /<pre class="mermaid">(.*?)<\/pre>/s;
      my $src = $1; my $afterend = $at + $+[0];
      # figcaption (直後の figure 内) を caption に。
      my $cap = "";
      if (substr($inner,$afterend,400) =~ /<figcaption>(.*?)<\/figcaption>/s) { $cap = plain($1); }
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
  my ($mblocks, $mexp) = extract_machine_blocks($inner);
  my $mcap = scalar(@$mblocks);
  push @LOG, "section $id: 機械層 prose capture $mcap 件 (data-audience=machine の <p>/<aside>/<ul> を逐語取り込み)"
    . ($mcap == $mexp ? "" : " ★uncaptured " . ($mexp - $mcap) . " 件 (expected $mexp・要調査)");
  push @sections, { id=>shortid($id), heading=>$heading, essence=>$essence, blocks=>\@blocks, machine_blocks=>$mblocks };
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
print "# folio engine tr0 (folio-hd0) — spec-pack contract (relations dual-audience self-host・spec-pack fork)\n";
print "# ★機械抽出 DRAFT (scripts/extract-relations-spec.sh が architecture/spec/relations.html から起こした)。 人間レビュー前提。\n";
print "# doc_type = spec (spec 間の関係性表現規約)。 EARS 章立て規範文 + 非終端 照会 (前方 references)。\n";
print "# ★抽出範囲 = relations.html の人間層 (section essence + subhead + 表 + 図(mermaid source) + EARS 要件 + 用語 + 照会) + 機械層自由文 (w1f cell-1)。\n";
print "#   機械層 = data-audience=\"machine\" の <p>/<aside>/<ul> を machine_preamble (文書前文) + sections[].machine_blocks (section 内) に *逐語* capture。\n";
print "#   ★JSON-LD: head の <script type=application/ld+json> は doc 自身のメタデータ (assemble が head 生成・machine_blocks でない)。 §3 の <pre><code>&lt;script…&gt;</code></pre> は人間層エスケープ code 例 (通常の code block として往復・特別機構なし)。\n";
print "\n";
print "meta:\n";
print "  doc_id: FOLIO-RELATIONS\n";
print "  doc_type: spec\n";
print "  title: ", ys("folio relations — spec 間の関係性表現規約"), "\n";
print "  eyebrow_left: ", ys("関係性 spec (Relations)"), "\n";
print "  eyebrow_right: ", ys("folio — spec 間の関係性表現規約"), "\n";
print "  subtitle: ", ys($hmeta ne "" ? $hmeta : "spec 間の関係性表現規約 (JSON-LD + W3C 語彙 + inventory)"), "\n";
print "  version: ", ys($meta{version}), "\n";
print "  date: ", ys("2026-06-24"), "\n";
print "  status: ", ys($meta{status}), "\n";
print "  reader: ", ys("$stake — folio spec を編集する開発者・AI Agent・外部レビュアー"), "\n";
print "\n";
print "# 承認記録 (core 共用 approval-block)。 relations.html は署名欄を持たないため doc lifecycle を忠実に再提示する (synthesized chrome)。\n";
print "approval:\n";
print "  - { role: ", ys("文書種別"), ", who: ", ys("spec (relation management spec)"), ", when: ", ys("v$meta{version}"), ", stamp: ", ys("active"), " }\n";
print "  - { role: ", ys("生成 (engine tr0 spec-pack fork)"), ", who: ", ys("folio design system"), ", when: ", ys("2026-06-24 生成"), ", stamp: ", ys("生成"), " }\n";
print "\n";
print "# ★非終端 照会の graph 接続: relations → constitution (FOLIO-CONSTITUTION 終端) の前方 edge (role=implementation)。\n";
print "#   verify-graph.sh の rolemap edge がこの 1 本を pin し、 reachability で relations が principle 終端へ到達することを実証する (rolemap 登録は admin/graph 領分)。\n";
print "graph:\n";
print "  principle_edge: { target_doc_id: FOLIO-CONSTITUTION, role: implementation }\n";
print "\n";
# ★機械層 preamble (w1f cell-1): section に属さない文書前文の data-audience="machine" prose を逐語 capture。
emit_mblocks("machine_preamble", 0, $preamble_blocks);
print "\n" if @$preamble_blocks;
print "sections:\n";
for my $s (@sections) {
  print "  - id: ", ys($s->{id}), "\n";
  print "    tint: ", ys($TINT{$s->{id}} // "brand"), "\n";
  print "    kicker: ", ys($KICK{$s->{id}} // $s->{id}), "\n";
  print "    heading: ", ys($s->{heading}), "\n";
  print "    essence: ", ys($s->{essence}), "\n";
  if (@{$s->{blocks}}) {
    print "    blocks:\n";
    for my $b (@{$s->{blocks}}) {
      if ($b->{type} eq "subhead") {
        print "      - { type: subhead, heading: ", ys($b->{heading}), ", essence: ", ys($b->{essence}), " }\n";
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
print "requirements:\n";
for my $r (@reqs) {
  print "  - id: ", ys($r->{id}), "\n";
  print "    ears_pattern: ", ys($r->{pat}), "\n";
  print "    essence: ", ys($r->{ess}), "\n";
  print "    statement: ", ys($r->{stmt}), "\n";
}
print "\n";
print "# 非終端 照会 (前方・他文書へ)。 constitution P-x (role=implementation) / ADR (rationale) / verification REQ-VER (verification)。\n";
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
print STDERR "=== extract-relations-spec LOG (no silent caps) ===\n";
print STDERR "$_\n" for @LOG;
my $mtot = scalar(@$preamble_blocks); $mtot += scalar(@{$_->{machine_blocks}}) for @sections;
my ($mprose, $mnote, $mlist) = (0,0,0);
for my $b (@$preamble_blocks, map { @{$_->{machine_blocks}} } @sections) {
  $mprose++ if $b->{type} eq "prose"; $mnote++ if $b->{type} eq "note"; $mlist++ if $b->{type} eq "list";
}
printf STDERR "抽出: %d sections / %d requirements / %d references / %d glossary terms\n",
  scalar(@sections), scalar(@reqs), scalar(@refs), scalar(@gloss);
printf STDERR "機械層 prose capture: %d 件 (prose=%d / note=%d / list=%d・preamble %d 件含む)\n",
  $mtot, $mprose, $mnote, $mlist, scalar(@$preamble_blocks);
PERL
