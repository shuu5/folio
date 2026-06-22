#!/usr/bin/env bash
# folio engine B6 (folio-8ct) — bootstrap extractor: rules.html → folio-rules.spec.yaml (one-shot)
#
# architecture/spec/rules.html を *read-only* で走査し、 spec-pack contract (folio-rules.spec.yaml) の
# DRAFT を起こす one-shot スクリプト。 ★出力は人間 (= 次サイクル admin) レビュー前提 (機械抽出の下書き)。
#
# 抽出する属性マーク (rules.html の構造化された人間層):
#   - meta: <meta name="folio-*"> + doc-header
#   - sections: <section id> + <h2>/<h3> + <p class="section-essence">
#   - requirements (EARS): <details class="spec-row" id> → badge id / data-ears-pattern / .essence / p.ears(plain)
#   - glossary: <span class="term" data-term data-tooltip> (dedup by data-term)
#   - references (非終端 照会・前方): <a class="xref" href> + 外部 doc への <a href> (constitution#p-* / ADR-* / verification#req-ver-*)
#   - content blocks (document 順): subhead(h3+essence) / table / code(pre>code) / mermaid(pre.mermaid) / requirements(spec-list)
#
# ★silent drop 禁止 (no silent caps): 各 section で *モデル化しなかった* prose 段落 (data-audience="machine" の
#   verbose 地の文 = rules.html 自身が §11.5 で既定非表示にする「機械層」) の件数を stderr に LOG する。
#   人間層プレゼン (essence + subhead + 表 + 図 + 要件) を抽出し、 機械層 verbose prose は意図的に範囲外として LOG する。
#
# usage: extract-rules-spec.sh [<rules.html>] > <draft contract.yaml>   (LOG は stderr)
#        既定 <rules.html> = <repo-root>/architecture/spec/rules.html

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES="${1:-$REPO_ROOT/architecture/spec/rules.html}"
[[ -f "$RULES" ]] || { echo "extract-rules-spec: rules.html not found: $RULES" >&2; exit 1; }
command -v perl >/dev/null || { echo "extract-rules-spec: perl required" >&2; exit 1; }

RULES="$RULES" perl -CSD -0777 <<'PERL'
use strict; use warnings;
my $file = $ENV{RULES};
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
  s0=>"info", s2=>"brand", s3=>"violet", s4=>"info", s5=>"warn", s6=>"brand",
  s7=>"violet", s8=>"warn", s9=>"info", s10=>"bad", s11=>"ok", s12=>"brand",
);
my %KICK = (
  s0=>"§0 / 読み方", s2=>"§2 / ディレクトリ", s3=>"§3 / 命名", s4=>"§4 / HTML 書式",
  s5=>"§5 / delta marker", s6=>"§6 / EARS 記法", s7=>"§7 / dual-audience", s8=>"§8 / JS 統制",
  s9=>"§9 / 照会 (xref)", s10=>"§10 / 必須義務", s11=>"§11 / 人間向け提示", s12=>"§12 / 要件定義書 design system",
);
# rules.html の実 section id (full form)。 contract section.id は short prefix (s0..s12) を使う (TINT/KICK の key)。
my @SECORDER = qw(s0-reader-guide s2-directory s3-naming s4-format s5-delta s6-ears
                  s7-dual-audience s8-js-governance s9-xref s10-mandatory s11-presentation s12-srs-design-system);
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
  my $prose_skipped = 0;

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
    # opener より手前に <p ...> や <ul data-audience="machine"> の prose があれば LOG（モデル化しない）。
    my $gap = substr($inner, $p, $at - $p);
    $prose_skipped += () = ($gap =~ /<p\b(?![^>]*class="section-essence")[^>]*>/g);
    $prose_skipped += () = ($gap =~ /<ul data-audience="machine">/g);

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
  # 末尾 prose (最後の opener 以降) も概算 LOG。
  my $tail = substr($inner, $p);
  $prose_skipped += () = ($tail =~ /<p\b(?![^>]*class="section-essence")[^>]*>/g);

  push @LOG, "section $id: モデル化しなかった prose/aside 段落 ≈ $prose_skipped 件 (rules.html の data-audience=machine 機械層・§11.5 で既定非表示・human 層は essence+subhead+表+図+要件として抽出)";
  push @sections, { id=>shortid($id), heading=>$heading, essence=>$essence, blocks=>\@blocks };
}

# ===== YAML 出力 =====
print "# folio engine B6 (folio-8ct) — spec-pack contract (instance#5 / self-dogfood)\n";
print "# ★機械抽出 DRAFT (scripts/extract-rules-spec.sh が architecture/spec/rules.html から起こした)。 人間レビュー前提。\n";
print "# doc_type = rules (Layer 1 consumer universal rules)。 EARS 章立て規範文 + 非終端 照会 (前方 references)。\n";
print "# ★抽出範囲 = rules.html の *人間層* (section essence + subhead essence + 表 + 図(mermaid source) + EARS 要件 + 用語 + 照会)。\n";
print "#   モデル化しなかった verbose machine prose は §11.5 で rules.html 自身が既定非表示にする機械層 (件数は extractor が stderr に LOG)。\n";
print "\n";
print "meta:\n";
print "  doc_id: FOLIO-RULES\n";
print "  doc_type: rules\n";
print "  title: ", ys("folio rules — Layer 1 consumer universal rules"), "\n";
print "  eyebrow_left: ", ys("ルール (Rules)"), "\n";
print "  eyebrow_right: ", ys("folio — Layer 1 consumer 向け普遍規約"), "\n";
print "  subtitle: ", ys($hmeta ne "" ? $hmeta : "Layer 1 consumer 向け universal rules (markup + naming + EARS + Mandatory Actions)"), "\n";
print "  version: ", ys($meta{version}), "\n";
print "  date: ", ys("2026-06-22"), "\n";
print "  status: ", ys($meta{status}), "\n";
print "  reader: ", ys("$stake — folio を consume する開発者・AI Agent・外部レビュアー"), "\n";
print "\n";
print "# 承認記録 (core 共用 approval-block)。 rules.html は署名欄を持たないため doc lifecycle を忠実に再提示する (synthesized chrome)。\n";
print "approval:\n";
print "  - { role: ", ys("文書種別"), ", who: ", ys("rules (Layer 1 universal rules)"), ", when: ", ys("v$meta{version}"), ", stamp: ", ys("active"), " }\n";
print "  - { role: ", ys("生成 (engine B6 spec-pack)"), ", who: ", ys("folio design system"), ", when: ", ys("2026-06-22 生成"), ", stamp: ", ys("生成"), " }\n";
print "\n";
print "# ★非終端 照会の graph 接続: rules → constitution (FOLIO-CONSTITUTION 終端) の前方 edge (role=implementation)。\n";
print "#   verify-graph.sh の rolemap edge がこの 1 本を pin し、 reachability で rules が principle 終端へ到達することを実証する。\n";
print "graph:\n";
print "  principle_edge: { target_doc_id: FOLIO-CONSTITUTION, role: implementation }\n";
print "\n";
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

# ===== LOG (silent drop 禁止: モデル化しなかった content を stderr へ) =====
print STDERR "=== extract-rules-spec LOG (no silent caps) ===\n";
print STDERR "$_\n" for @LOG;
printf STDERR "抽出: %d sections / %d requirements / %d references / %d glossary terms\n",
  scalar(@sections), scalar(@reqs), scalar(@refs), scalar(@gloss);
PERL
