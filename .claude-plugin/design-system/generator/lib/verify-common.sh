#!/usr/bin/env bash
# folio 文書規律エンジン core (B2 / folio-5ua) — verify 共通ライブラリ (fabrication-free 規律ヘルパ)
#
# rule-of-three の core 抽出 (research/document-discipline-engine-design.html §7):
# fabrication-free 規律 (chk / chk_empty / set_eq / 行数=contract 導出 / escape / fail-closed) と
# 2-gate 型の verify 足回りは doc-type 非依存 = core。 verify-fabrication-free.sh (SRS-pack) /
# verify-adr.sh (ADR-pack) / verify-srs.sh (SRS floor) が source する。 pack 固有の検査
# (RTM 集合 / cross-doc 照会解決 / ADR verdict 整合 等) は各 verify に残す。
#
# 前提 (source 側の責務):
#   - 冒頭で `set -uo pipefail` と `shopt -u patsub_replacement` 済 (esc の ${v//&/..} を守る)。
#   - $CONTRACT (contract path) を設定済 (q が参照)。 $fail を 0 で初期化済 (chk 系が立てる)。
#   - chk 系の整列幅は $CHKW で決まる (既定 48。 各 verify は元の幅に合わせて設定: fab=44/adr=48/srs=50)。
#   - make_body 後は $BODY (style 除去 body-only view) が使える。

# patsub_replacement (bash 5.2+) は esc() の ${v//&/..} を壊す。 source 側が忘れても lib 自身で無効化し堅牢化。
shopt -u patsub_replacement 2>/dev/null || true
CHKW="${CHKW:-48}"

q() { yq -r "$1" "$CONTRACT"; }
# assemble / inject-prose と同一の escape 規律 (注入忠実・term-inline 照合に使う)。
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }
# qesc — yq 式 $1 の各行を esc して 1 行ずつ出力 (順序付き決定的フィールド値の HTML 突合用)。
# within-doc 可視フィールド値の順序付き突合 (cxid/drid 同型) で、 contract 側を HTML と同じ escape 規律へ
# 揃える複数行 esc。 値は core_validate_strings が tab/改行を拒否済ゆえ 1 値 = 1 行で安全。
qesc() { q "$1" | while IFS= read -r _v; do esc "$_v"; printf '\n'; done; }

# count_attr_token — stdin の HTML から、 属性 $1 の値に トークン $2 が現れる occurrence 数を
# *quote 構文・属性名 case 非依存* で数える。 marker 占有数パリティ用。 assembler は小文字 double-quote のみ emit ゆえ
# single-quote (class='fid') / unquoted (class=fid) / multi-class (class="x fid") / 大文字属性名 (CLASS=/Class=) は
# 全て tamper だが、 素朴な grep 'class="fid"' を素通る (round-4 ceiling 兄弟・case 版は不完全 ceiling の唯一完走 lens が検出)。
# 本 helper は attr="..." / attr='...' / attr=unquoted を全 parse し、 値を空白でトークン分割して $2 *完全一致* を数える。
# ★属性名・値トークンとも case 非依存 (lc 比較)。 属性名は HTML 仕様で case-insensitive。 値トークンも:
# assembler は小文字 ASCII class のみ emit ゆえ大文字 class (class="CT") は tamper で、 .ct 非適用でも
# *無 style の可視要素として詐欺テキストを描画する* (round-5 ceiling: case-drop した偽 <p> + 同値小文字 decoy で
# 抽出列を保存したまま可視捏造を素通せた)。 占有数は case 込みで数えて偽要素の add を必ず捕捉する。 chr(39) で single-quote 回避。
# class_tokens — stdin HTML の各 class 属性のトークン集合を 1 行ずつ出力 (quote 構文・属性名 case・数値文字参照 非依存・値は lc)。
# joint-token 占有数 (RTM dot) や class-token 機械的網羅を *quote-robust* に走査するため (count_attr_token と同じ 3 分岐 parse)。
class_tokens() { # HTML は stdin
  perl -CSD -0777 -e '
    my $q=chr(39); my $txt=<STDIN>; $txt="" unless defined $txt;
    while ($txt =~ /\b(?i:class)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g) {
      my $v = defined $1 ? $1 : (defined $2 ? $2 : $3);
      $v =~ s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $v =~ s/&#([0-9]+);?/chr($1)/ge;
      my @t = grep { length } map { lc } split(/\s+/, $v);
      print "@t\n" if @t;
    }
  '
}

count_attr_token() { # $1=attr $2=token ; HTML は stdin
  ATTR="$1" TOK="$2" perl -CSD -0777 -e '
    my ($attr,$tok)=($ENV{ATTR},$ENV{TOK}); my $q=chr(39); my $txt=<STDIN>; $txt="" unless defined $txt; my $tl=lc $tok;
    my $c=0;
    while ($txt =~ /\b(?i:\Q$attr\E)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g) {
      my $v = defined $1 ? $1 : (defined $2 ? $2 : $3);
      # ★HTML 数値文字参照を decode (round-5 ceiling: <span class="&#102;id"> は .fid 描画されるが
      #   未 decode だと token に一致せず ghost を見逃す)。 assembler は literal ASCII class のみ emit。
      $v =~ s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge;
      $v =~ s/&#([0-9]+);?/chr($1)/ge;
      $c++ if grep { lc($_) eq $tl } split(/\s+/, $v);
    }
    print $c;
  '
}

# attr_values — stdin HTML から属性 $1 の各 occurrence の *値* を quote 構文・属性名 case・数値文字参照 非依存に 1 行ずつ出力。
# count_attr_token の値版 (data-*-link 等の集合/件数突合を quote-robust に行うため。 旧 grep -oE 'attr="[^"]+"' は
# single-quote/unquoted の偽属性を素通す = round-8 ceiling が acc-dot single-quote decoy で実証した穴)。 値内の tab/改行は空白へ畳む。
attr_values() { # $1=attr ; HTML は stdin
  ATTR="$1" perl -CSD -0777 -e '
    my $attr=$ENV{ATTR}; my $q=chr(39); my $txt=<STDIN>; $txt="" unless defined $txt;
    while ($txt =~ /\b(?i:\Q$attr\E)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g) {
      my $v = defined $1 ? $1 : (defined $2 ? $2 : $3);
      $v =~ s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $v =~ s/&#([0-9]+);?/chr($1)/ge;
      $v =~ s/[\t\n]/ /g;
      print "$v\n";
    }
  '
}

chk() { # label expected actual
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "$1" "$2"
  else printf '  [FAIL] %-'"$CHKW"'s expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}
chk_empty() { # label value(空であるべき)
  if [[ -z "$2" ]]; then printf '  [OK]   %-'"$CHKW"'s\n' "$1"
  else printf '  [FAIL] %-'"$CHKW"'s 重複: %s\n' "$1" "$2"; fail=1; fi
}
set_eq() { # label expected-multiline actual-multiline
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "$1" "識別"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "$1"
    echo "    --- contract のみ (脱落) ---"; comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    echo "    --- HTML のみ (捏造) ---";     comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    fail=1
  fi
}

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、 <style> ブロックの
# *中身を除去* した body-only ビューで数える ($BODY をグローバルに設定し EXIT で掃除)。
# ★folio-wq4: 旧版は 行範囲削除 (sed) → 単純 perl 置換 → state machine と進めたが、 独立 ceiling が逐次に
#   parser-differential fail-open を実証した (round-1: comment smuggle / case / 未閉じ → round-2: 属性値内 <style> /
#   不正 close 文法 </style x>)。 これは「regex/手書きで rendering を忠実モデルする」arms race = whack-a-mole。
#   ★方針転換 (user 判断 = fail-closed): rendering を完全モデルせず、 *genuine 不変条件* を機械強制して破る入力を
#   *拒否* する。 genuine 生成物は (1) 全 < が esc() 済 (属性値・本文に raw < 無し) (2) style/script/comment は
#   clean な既知形のみ という narrow shape を満たす。 単一パス scanner が clean 入力は処理し (comment=verbatim /
#   style=中身空化 / script=verbatim 保持〔JSON-LD 死守・opaque〕)、 それを破る adversarial を fail-closed する:
#     (a) タグ開始内の raw <  = 属性値への <style>/<script> 注入 (open-tag differential)
#     (b) RAWTEXT の不正 close 文法 </style x> </style/>  (close-tag differential)
#     (c) 未閉じ RAWTEXT (style/script) / (d) 未閉じコメント / (e) 未閉じタグ
#   fail-closed 時は空 $BODY を出し全 floor check を欠落 FAIL させる + 診断を echo (verify 非0 exit)。 これで
#   「非描画領域に捏造をくるんで $BODY から消す」テキスト隠蔽クラスを *構成的に* 封鎖する (rendering モデルの
#   完全性証明に依らず genuine shape の機械強制で完結 = whack-a-mole の停止)。 byte-level (UTF-8 安全: '>' 0x3E)。
make_body() { # $1 = html path
  BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
  if ! perl -e '
    binmode STDIN; binmode STDOUT;
    local $/; my $h = <STDIN>; $h = "" unless defined $h;
    my $o = ""; my $n = length($h); my $i = 0; my $fail = "";
    while ($i < $n && $fail eq "") {
      my $lt = index($h, "<", $i);
      if ($lt < 0) { $o .= substr($h, $i); last; }
      $o .= substr($h, $i, $lt - $i);
      my $rest = substr($h, $lt, 16);
      if (substr($h, $lt, 4) eq "<!--") {
        my $end = index($h, "-->", $lt + 4);
        if ($end < 0) { $fail = "unclosed-comment"; last; }
        $o .= substr($h, $lt, $end + 3 - $lt); $i = $end + 3;
      } elsif ($rest =~ /^<(style|script)\b/i) {
        my $kind = lc($1);
        my $gt = index($h, ">", $lt);
        if ($gt < 0) { $fail = "unclosed-opentag-$kind"; last; }
        my $opentag = substr($h, $lt, $gt + 1 - $lt);
        if (index(substr($opentag, 1), "<") >= 0) { $fail = "raw-lt-in-$kind-opentag"; last; }
        $o .= $opentag;
        my $after = $gt + 1; my $tail = substr($h, $after);
        if ($tail =~ m{</\Q$kind\E([^>]*)>}i) {
          my $junk = $1; my $cs = $after + $-[0]; my $ce = $after + $+[0];
          if ($junk =~ /\S/) { $fail = "malformed-close-$kind"; last; }
          if ($kind eq "style") { $o .= "</style>"; }
          else { $o .= substr($h, $after, $ce - $after); }
          $i = $ce;
        } else { $fail = "unclosed-$kind"; last; }
      } elsif ($rest =~ m{^</?[a-zA-Z]}) {
        my $gt = index($h, ">", $lt);
        if ($gt < 0) { $fail = "unclosed-tag"; last; }
        my $tag = substr($h, $lt, $gt + 1 - $lt);
        if (index(substr($tag, 1), "<") >= 0) { $fail = "raw-lt-in-tag"; last; }
        $o .= $tag; $i = $gt + 1;
      } else { $o .= "<"; $i = $lt + 1; }
    }
    if ($fail ne "") { print STDERR "make_body fail-closed: $fail\n"; exit 3; }
    print $o;
  ' < "$1" > "$BODY" 2>/dev/null; then
    : > "$BODY"   # fail-closed: 空 body で全 floor check を欠落 FAIL させる (genuine shape を破る adversarial 入力)
    echo "  [FAIL] make_body fail-closed: 非 genuine な <style>/<script>/comment/タグ構造を検出 (属性値内 raw < / 不正 close 文法 / 未閉じ 等)"
    fail=1
  fi
}

# ---- plain-language-term-inline (glossary 派生ビュー、 ADR-0042 §2.2 A) の fidelity + 用語被覆 ----
# バッジ構造: <span class="term" data-component="plain-language-term-inline" data-term="TE">PLAIN</span>
# 照合は assemble と同じ esc() 済みで行う (esc 非対称による偽 FAIL を避ける)。 markable フィールドは
# pack 固有ゆえ呼出側が yq 式で渡す ($1)。 被覆 set_eq のラベルも pack 別ゆえ $2 で受ける。
# (a) fidelity: data-term ∈ glossary かつ 併記 == その語の plain_short / (b) uniqueness: 各 data-term 1 回 /
# (c) 用語被覆: マーク data-term 集合 == markable に出現する glossary 語 (assemble と *同一の語境界規律* で再導出)。
verify_term_inline() { # $1 = markable フィールドの yq 式  $2 = 被覆 set_eq ラベル
  local markable_expr="$1" cov_label="$2"
  declare -A GPLAIN GALL GASCII
  while IFS=$'\t' read -r gterm gplain; do
    [[ -n "$gterm" ]] || continue
    [[ -n "$gplain" && "$gplain" != "null" ]] || gplain="$gterm"
    gte="$(esc "$gterm")"; GALL[$gte]=1; GPLAIN[$gte]="$(esc "$gplain")"
    a=1; case "$gterm" in *[!\ -~]*) a=0 ;; esac; GASCII[$gte]="$a"   # assemble と同じ ascii 判定
  done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')
  mapfile -t MARKS < <(grep -oE '<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>' "$BODY")
  local tfail=0; declare -A TSEEN
  local m dt ct
  for m in "${MARKS[@]}"; do
    dt="$(printf '%s' "$m" | sed -E 's/.*data-term="([^"]*)".*/\1/')"
    ct="$(printf '%s' "$m" | sed -E 's#.*">([^<]*)</span>#\1#')"
    [[ -n "${GALL[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が glossary に無い (捏造)"; tfail=1; fail=1; }
    [[ -z "${GALL[$dt]:-}" || "$ct" == "${GPLAIN[$dt]}" ]] || { echo "  [FAIL] term-inline '$dt' 併記が plain_short と不一致 (期待 '${GPLAIN[$dt]}' 実 '$ct')"; tfail=1; fail=1; }
    [[ -z "${TSEEN[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が重複マーク"; tfail=1; fail=1; }
    TSEEN[$dt]=1
  done
  [[ "$tfail" -eq 0 ]] && printf '  [OK]   %-'"$CHKW"'s %s\n' "term-inline 派生・一意 (data-term∈glossary・併記==plain_short)" "${#MARKS[@]}"
  # (c) 用語被覆: ascii=英数境界 / CJK=漢字非隣接 (perl -CSD) で assemble と同一の語境界規律。
  # ★照合統一 (folio-wqh): exp は perl 既定 sort (codepoint 照合・locale 非依存)、 act は shell `sort -u`
  #   (LC_COLLATE 依存) で両辺の照合が食い違っていた。 glossary に大文字 ascii 語 (SSoT 等) と小文字語が
  #   混在すると、 en_US.UTF-8 の辞書照合 (大小文字を同位扱い: api < SSoT) と codepoint 照合 (大文字が先:
  #   SSoT < api) で並びがズレ、 set_eq の厳密 == が *集合は同一なのに* false FAIL した (verify-side 限定の
  #   latent core fragility)。 両辺を LC_ALL=C sort -u に揃えて照合を locale 非依存へ固定する: perl 内の sort は
  #   外出しし exp/act とも同一の C 照合へ通す (= 「両辺同一照合」を明示)。 さらに set_eq の内部 comm (-23/-13)
  #   も LC_ALL=C 下で呼んで C-sorted 入力と整合させる (en_US.UTF-8 のままだと genuine FAIL 時に comm が
  #   "input is not in sorted order" を出し診断が崩れる。 一時代入は set_eq とその comm に伝播しリークしない)。
  local MKF GF2 gte exp_marks act_marks
  MKF="$(mktemp)"; GF2="$(mktemp)"
  esc "$(q "$markable_expr")" > "$MKF"
  for gte in "${!GALL[@]}"; do printf '%s\t%s\n' "$gte" "${GASCII[$gte]}"; done > "$GF2"
  exp_marks="$(MKF="$MKF" GF2="$GF2" perl -CSD -e '
    local $/; open(my $mf,"<",$ENV{MKF}) or die; my $m=<$mf>; close $mf; $m="" unless defined $m;
    my @out;
    { local $/="\n"; open(my $gf,"<",$ENV{GF2}) or die;
      while (my $l=<$gf>){ chomp $l; next unless length $l; my ($te,$a)=split(/\t/,$l,2);
        my $pat=($a eq "1")?qr/(?<![A-Za-z0-9])\Q$te\E(?![A-Za-z0-9])/:qr/(?<!\p{Han})\Q$te\E(?!\p{Han})/;
        push @out,$te if $m=~$pat; } close $gf; }
    print "$_\n" for @out;
  ' | LC_ALL=C sort -u)"
  rm -f "$MKF" "$GF2"
  act_marks="$(printf '%s\n' "${MARKS[@]}" | grep . | sed -E 's/.*data-term="([^"]*)".*/\1/' | LC_ALL=C sort -u)"
  LC_ALL=C set_eq "$cov_label" "$exp_marks" "$act_marks"
}

# ---- core 共通 chrome (cover-head / approval-block / glossary-term-table) の floor 突合 (folio-mk9) ----
# lib/common.sh が *全 pack 同一構造で emit* する決定的可視 chrome 値 — cover-head (eyebrow/title/subtitle/reader)・
# approval-block (role/who/when/stamp)・glossary-term-table (term/en/def) — を contract と *順序付き値突合* (第1層) で
# 検証する。 SRS/ADR/research 全 pack 共通の cross-pack gap (dty round-2 完全列挙が発見): 7b 相当の *件数のみ* 検証で
# 値改竄 (eyebrow『要件定義書』→詐欺・承認者名 swap・glossary 定義の捏造) が件数保存のまま素通る fail-open だった。
# ★ds8/dty 不動点を踏襲: row/block-scope 抽出 + 順序リスト厳密一致 (set でなく ordered match)。
# ★抽出は固定 nested 構造の structured-regex で leaf を [^<]* に限定する = 内側へのタグ注入は構造不一致で row 脱落 →
#   件数/順序 FAIL (ds8 の marker-keyed nested-reject と同値の堅牢性。 [^<]* leaf は < を含めないゆえ非貪欲の早期終端・
#   空要素 early-match・偽 provenance を構造的に拒否する)。 値そのものの改竄は順序突合 (chk) が担う。
# ★mzn.3 Phase C 退役: 旧・第 2 層 = quote-robust count_attr_token 占有数パリティ (case-drop/decoy/entity ghost の add
#   封鎖) と reader-chip decoy 4 層は撤去した。 構造 fidelity (第 1 層が拾わない occupancy 逸脱・偽部品 add・偽
#   reader-chip box) は repro-build byte-identity gate (REQ-VER-030 blocking) が contract からの再組立 byte 比較で
#   *一括* 継承する (占有 pin が部品ごとに数えるのに対し、 全 body の byte 恒等で任意の post-build 改変を捕捉)。
#   例外: vcount who だけ第 1 層 pin として存続 (下記・U3K1-3 の数値文字参照 decode red pin が anchor するため)。
# ★reader-chip class は ADR/research で cross-doc-ref-chip が同 class を再利用するため 2 個 = global count 不可 →
#   genuine reader-chip は `class="reader-chip">` (閉じ引用直後が >) で識別し値突合する (ref-chip は
#   `class="reader-chip" data-component=...` = 引用後に空白)。 marker 有無に依らない占有 anchor 検査は退役 (repro-build 継承)。
# 前提: $BODY (make_body 済) / $CONTRACT / q / esc / chk / count_attr_token / $fail / $CHKW。 mode 非依存 (chrome は構造ゆえ
#  pre-fill/--filled/--artifact のいずれでも同一・prose slot を持たない)。 全 pack verify から無条件に呼ぶ。
verify_core_chrome() { # 引数不要 (mzn.3 Phase C 占有 pin 退役後・旧 $1/$2=role/en 追加 home 数は消費者無し = 渡されても無視)
  local nap readerlines
  nap="$(q '.approval | length')"
  # genuine reader-chip 行を厳密 anchor で抽出 (第1層 値突合用): 本物は `class="reader-chip">` (閉じ引用直後が >)、
  # cross-doc-ref-chip は `class="reader-chip" data-component=...` (引用後に空白+属性) ゆえ別物。 これで
  # (i) ref-chip を除外 / (ii) 自由文 prose 中の "想定読者:" 偶然一致を除外 (false-positive 防止) する。
  readerlines="$(grep 'class="reader-chip">' "$BODY")"

  # ★mzn.3 Phase C 退役: 占有数パリティ (vcount) 群と reader-chip decoy 4 層 (marker/anchor/genuine/global marker) は
  #   撤去した — 構造 fidelity (case-drop/decoy/entity ghost の add・偽 reader-chip box) は repro-build byte-identity
  #   gate (REQ-VER-030 blocking) が contract からの再組立 byte 比較で一括継承する。 本 helper は *第 1 層* = contract
  #   由来値の順序付き突合 (値・順序の改竄捕捉) のみを担う。 例外: vcount who だけ存続する (下記)。

  # (1) cover-head (core_emit_cover_head / _tail): eyebrow (doc-type + 右 bare span を *対で*)・title (h1)・
  #     subtitle (cover-sub)・reader (reader-chip の "想定読者: " 後の可視テキスト) を順序付き値突合 (第1層)。
  chk "core-chrome: cover-eyebrow (左,右) == .meta.eyebrow_left/right" \
    "$(printf '%s\t%s' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")")" \
    "$(perl -CSD -0777 -ne 'while (/<p class="cover-eyebrow"><span class="doc-type">([^<]*)<\/span> <span>([^<]*)<\/span><\/p>/g){ print "$1\t$2\n"; }' "$BODY")"
  chk "core-chrome: cover h1 == .meta.title" "$(esc "$(q '.meta.title')")" \
    "$(grep -oE '<h1>[^<]*</h1>' "$BODY" | sed -E 's#<h1>([^<]*)</h1>#\1#')"
  chk "core-chrome: cover-sub == .meta.subtitle" "$(esc "$(q '.meta.subtitle')")" \
    "$(grep -oE '<p class="cover-sub">[^<]*</p>' "$BODY" | sed -E 's#<p class="cover-sub">([^<]*)</p>#\1#')"
  chk "core-chrome: reader-chip 想定読者 == .meta.reader" "$(esc "$(q '.meta.reader')")" \
    "$(printf '%s\n' "$readerlines" | grep -oE '想定読者: [^<]*</div>' | sed -E 's/^想定読者: //; s#</div>$##')"

  # (2) approval-block (core_emit_approval_block): (role,who,when,stamp) を sign 行から *配列順* で突合 (第1層)。
  #     stamp class は stamp | stamp self (stamp != 承認済 で self・修飾子) ゆえ (?: self)? で両形を受ける。
  chk "core-chrome: approval (role,who,when,stamp) == .approval (順序)" \
    "$(q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r _r _w _t _s; do printf '%s\t%s\t%s\t%s\n' "$(esc "$_r")" "$(esc "$_w")" "$(esc "$_t")" "$(esc "$_s")"; done)" \
    "$(perl -CSD -0777 -ne 'while (/<div class="sign"><span class="role">([^<]*)<\/span><span class="who">([^<]*)<\/span><span class="when">([^<]*)<\/span><span class="stamp(?: self)?">([^<]*)<\/span><\/div>/g){ print "$1\t$2\t$3\t$4\n"; }' "$BODY")"
  # ★vcount who — mzn.3 Phase C 占有 pin 退役後も残る *唯一の* 第 1 層 occupancy pin。 U3K1-3 (class 名を数値文字参照
  #   &#X77;ho / &#x77ho / &#119ho 等で entity-encode した who decoy を注入し、 count_attr_token の decode robustness を
  #   pin する reason-gated red pin) が anchor するゆえ存続する (他の vcount sign/when/stamp/role/en 等は退役)。
  chk "core-chrome: vcount who == |approval|"   "$nap" "$(count_attr_token class who < "$BODY")"

  # (3) glossary-term-table (emit_glossary): (term,en,def) を grow 行から *配列順* で突合 (第1層)。 en 空時は enb 無し ((?:...)? で両対応)。
  chk "core-chrome: glossary (term,en,def) == .glossary (順序)" \
    "$(q '.glossary[] | [.term, (.en // ""), .def] | @tsv' | while IFS=$'\t' read -r _te _en _de; do printf '%s\t%s\t%s\n' "$(esc "$_te")" "$(esc "$_en")" "$(esc "$_de")"; done)" \
    "$(perl -CSD -0777 -ne 'while (/<div class="grow"><div class="gword">([^<]*)(?:<span class="en">([^<]*)<\/span>)?<\/div><div class="gdef">([^<]*)<\/div><\/div>/g){ my $e=defined $2 ? $2 : ""; print "$1\t$e\t$3\n"; }' "$BODY")"

  # (4) footer provenance (機械SSoT basename / 検証状態 固定2状態) を全 pack で pin (folio-r8k で SRS gate H 相当を core 昇格)。
  #     昇格前は footer 値の厳密一致検査は verify-srs.sh gate H のみ (SRS 専用) で本 helper は footer を一切見ず、 非 SRS 全 pack は
  #     footer の value-swap (別ファイル名・偽『検証済』token) を検出できなかった。 verify_footer_provenance が第 1 層値突合と同じ規律で塞ぐ。
  verify_footer_provenance
}

# ---- footer provenance pin (機械SSoT basename / 検証状態 固定2状態) を doc-type 非依存で core 昇格 (folio-r8k) ----
# verify-srs.sh gate H (ds8/i6f9 で 3 巡 hardening 済) の footer 値 pin を全 pack へ配る core helper。 verify_core_chrome から
# 無条件に呼ばれ、 非 SRS 全 pack (adr/arch/datamodel/glossary/interface/principle/relations/research/spec/testcases/
# verification/vision + fabrication-free cross-cut) の footer value-swap を捕捉する。
#   part1 = fidelity-sync-meta 部品 存在 (==1) — 欠落/rename を捕捉 (has() は SRS 専用ゆえ core は直接 grep で self-contained)。
#   part2 = canonical machine div を *block-scoped 可視テキスト厳密一致* — basename value-swap / 検証状態 詐称 / </b>外可視追記 /
#           非難読化 sibling (n>1) / NESTED を決定的・FP-free に封鎖 (値改竄 = この issue の主題そのもの)。
#   part3 = footer 要素内に scope した projection の token 総数 (機械SSoT/検証状態 が各ちょうど 1 回) — 難読化偽 sibling
#           (属性なし div / 数値文字参照 / tag-split / comment-split / ゼロ幅) を tag 形状非依存に捕捉する backstop。
# ★SRS gate H との *意図的差異* (machine/LLM 境界・folio-mzn): SRS は part3 の token 総数を *body 全体* で数える (SRS の業務ドメイン
#   corpus は 機械SSoT/検証状態 を本文に一切含まないゆえ安全)。 だが folio 自身の meta pack (verification spec = REQ-VER-024
#   statement) は本文に「機械SSoT / 検証状態」を literal で含む (実測: body 全体で各 2)。 ゆえに core は part3 を *footer 要素内へ scope* し
#   本文の legit 言及を FP にしない。 footer 外へ注入した偽 provenance div は repro-build byte 同一性 (REQ-VER-030・blocking) と
#   ceiling gate J が担う (「機械は best-effort・可視の完全性判定は ceiling 領分」= gate H コメントと同じ分界)。 part2 は body 全体でも
#   canonical div anchor (`<div data-audience="machine">機械SSoT:`) 依存ゆえ本文言及に false-match せず FP-free。
# 前提: $BODY (make_body 済) / $CONTRACT / esc / chk / chk_empty / $fail / $CHKW (verify_core_chrome と同一)。
verify_footer_provenance() {
  # part1: 部品 存在 (==1)。 fidelity-sync-meta の欠落 (footer 全欠) と data-component rename を捕捉。
  chk "core-chrome: footer-meta 部品 == 1" 1 "$(grep -c 'data-component="fidelity-sync-meta"' "$BODY")"
  # part2+part3: block-scoped 可視テキスト厳密一致 + footer-scoped token 総数 backstop を 1 perl で。
  local fp_ssot_e; fp_ssot_e="$(esc "${CONTRACT##*/}")"
  local fp_bad
  fp_bad="$(SSOT="$fp_ssot_e" \
    STPRE='structure ✓ fabrication-free / prose 未充填 (opus 待ち)' \
    STPOST='structure ✓ fabrication-free / prose ✓ 充填済 (fidelity ceiling → S5 対象)' \
    perl -CSD -Mutf8 -0777 -ne '
    my $ssot=$ENV{SSOT}; utf8::decode($ssot);
    my $pre=$ENV{STPRE}; utf8::decode($pre); my $post=$ENV{STPOST}; utf8::decode($post);
    my @bad; my $n=0;
    # part2: canonical machine div を block-scoped で捕捉し、 全タグ除去後の可視テキストが固定テンプレ (機械SSoT=basename /
    #   生成=timestamp placeholder / 検証状態=固定2状態) と厳密一致か照合。 生成のみ非決定的ゆえ \d 桁 placeholder で許容、
    #   basename/区切り/検証状態 は厳密一致。 </b> 外・</div> 前への偽 provenance 可視追記も block-scoped ゆえ死角にならない。
    while (/<div data-audience="machine">機械SSoT:(.*?)<\/div>/gs) {
      my $in=$1; $n++;
      push @bad,"sync-meta:NESTED" if $in=~/<div\b/;
      my $vis="機械SSoT:".$in; $vis=~s/<[^>]+>//g;
      unless ($vis=~/^機械SSoT: \Q$ssot\E &middot; 生成: \d{4}-\d\d-\d\d \d\d:\d\d &middot; 検証状態: (.*)$/) { push @bad,"sync-meta:VIS"; next; }
      my $state=$1; push @bad,"検証状態\x{2260}固定2状態" if ($state ne $pre && $state ne $post);
    }
    push @bad,"sync-meta:count=$n" if $n!=1;
    # part3 (backstop): footer 要素内へ scope した projection 上で 機械SSoT/検証状態 が各ちょうど 1 回。 難読化偽 sibling
    #   (属性なし div / 数値文字参照〔x/X・; 任意〕/ tag-split / comment-split / ゼロ幅) を tag 形状非依存に捕捉する。
    #   ★footer-scope が SRS gate H (body 全体) との意図的差異 (上記関数コメント・folio meta pack の本文 literal を FP にしない)。
    #   projection: comment 除去 → tag 除去 (tag-open は < 直後が [a-zA-Z!/?] のときのみ = 生の《< 検証状態 >》は文字として残す) →
    #   数値文字参照 decode → Default_Ignorable (ゼロ幅) 除去。 順序が本質: tag を先に除去し entity 化タグ文字列は文字として残す。
    #   ★tag 除去は quote-aware (引用符内の > を tag 終端と誤認しない): naive [^>]* は <b t="a>z"> 型の
    #   引用符内 > 分割で実 parser と乖離し偽 provenance を素通りさせる (folio-r8k 独立 ceiling が実弾突破・
    #   parser differential)。未終端引用符の擬似タグは除去されず literal 残置 = token を再構成しない fail-safe 方向。
    my $foot = (/<footer\b.*?<\/footer>/s) ? $& : "";
    my $dec = $foot;
    $dec =~ s/<!--.*?-->//gs;
    $dec =~ s/<[!\/?a-zA-Z](?:[^>"\x27]|"[^"]*"|\x27[^\x27]*\x27)*>//g;
    $dec =~ s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $dec =~ s/&#([0-9]+);?/chr($1)/ge;
    $dec =~ s/\p{Default_Ignorable_Code_Point}//g;
    my $t1=()= $dec =~ /機械SSoT/g;  push @bad,"footer-token-ssot=$t1" if $t1!=1;
    my $t2=()= $dec =~ /検証状態/g;  push @bad,"footer-token-state=$t2" if $t2!=1;
    print join(" ", @bad);
  ' < "$BODY")"
  chk_empty "core-chrome: footer 可視テキスト == テンプレ (basename/ts/固定2状態・偽 sibling 封鎖)" "$fp_bad"
}

# ---- cross-doc 照会解決の共通スケルトン (rule-of-three: verify-adr §3 ∩ verify-research §3、 ds8 で core 昇格) ----
# B3 までは verify-adr.sh (justifies→SRS) と verify-research.sh (leads_to→ADR) に *同型の解決ブロックが重複*
# していた (照会先 contract 実在 / doc_id 一致 / count anchor / SET 一致 / dangling / 空値ガード / role allowlist /
#  (key,role) ペア SET 一致 の 8 検査)。 これは doc-type 非依存 = core。 pack 固有 (research の outcome.resolved_by・
# (ap-id,leads_to) ペア・可視チップ厳密一致・within-doc 順序・cover-meta / ADR の verdict 整合・supersession/principle・
# 可視 echo 厳密一致) は各 verify に残す (= core/pack 境界。 「新 doc-type に持ち込んで改変が要らない」= core)。
#
# ★空値ガード (|edges| == |非空 edges|) を core に入れて *両 pack へ無料で配る* のが ds8 の核:
#   comm -23 は空行を空 missing に畳むため dangling 判定が空文字列キーを素通す fail-open (research round-5 ceiling 発見)。
#   research は verify 側に持っていたが ADR は欠いていた (= 横展開で塞ぐ穴。 empty-value バグは assemble 側でも実在)。
#
# 抽象ロール allowlist は両 pack 文字列完全一致 = core 定数 (照会 graph のロール語彙・B0 论点2 終端解決)。
CROSS_DOC_ROLE_ALLOWLIST='claim|rationale|exploration|principle|verification|implementation'

# verify_cross_doc_refs — named-flag で受ける (12 引数の位置依存は誤順 = silent fail-open ゆえ flag で防ぐ)。
# 必須: --label-prefix --target-label --target-abs --key-attr --role-attr --keys-expr --count-expr
#       --nonempty-count-expr --pair-expr --target-ids-expr --contract-docid-expr --target-docid-expr
# 任意: --target-rel (不在メッセージ用)。 expr は呼出側 pack から *逐語で* 渡す (合成しない = 非破壊の証明を直截に保つ)。
# chk/chk_empty/set_eq が立てる $fail と $BODY/$CONTRACT/q (source 側責務) をそのまま使う。
verify_cross_doc_refs() {
  local label_prefix="" target_label="" target_abs="" target_rel="" key_attr="" role_attr=""
  local keys_expr="" count_expr="" nonempty_count_expr="" pair_expr="" target_ids_expr=""
  local contract_docid_expr="" target_docid_expr=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label-prefix)         label_prefix="$2";        shift 2 ;;
      --target-label)         target_label="$2";        shift 2 ;;
      --target-abs)           target_abs="$2";          shift 2 ;;
      --target-rel)           target_rel="$2";          shift 2 ;;
      --key-attr)             key_attr="$2";            shift 2 ;;
      --role-attr)            role_attr="$2";           shift 2 ;;
      --keys-expr)            keys_expr="$2";           shift 2 ;;
      --count-expr)           count_expr="$2";          shift 2 ;;
      --nonempty-count-expr)  nonempty_count_expr="$2"; shift 2 ;;
      --pair-expr)            pair_expr="$2";           shift 2 ;;
      --target-ids-expr)      target_ids_expr="$2";     shift 2 ;;
      --contract-docid-expr)  contract_docid_expr="$2"; shift 2 ;;
      --target-docid-expr)    target_docid_expr="$2";   shift 2 ;;
      *) echo "  [FAIL] verify_cross_doc_refs: 未知の引数 '$1'"; fail=1; return 1 ;;
    esac
  done
  # 必須パラメータ欠落は fail-closed (空 expr で検査を false-green に倒さない = この issue の主題そのもの)。
  local _p _missing=""
  for _p in label_prefix target_label target_abs key_attr role_attr keys_expr count_expr \
            nonempty_count_expr pair_expr target_ids_expr contract_docid_expr target_docid_expr; do
    [[ -n "${!_p}" ]] || _missing+=" --${_p//_/-}"
  done
  [[ -z "$_missing" ]] || { echo "  [FAIL] verify_cross_doc_refs: 必須パラメータ欠落:$_missing"; fail=1; return 1; }

  local prefix="$label_prefix"
  # (existence) 照会先 contract 実在 (fail-closed・不在なら以降は走らせない = 元の if/else 構造を保存)
  if [[ ! -f "$target_abs" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s 参照先 %s contract 不在: %s\n' "${prefix}: 照会先 ${target_label} contract 実在" "$target_label" "${target_rel:-$target_abs}"; fail=1
    return 1
  fi
  printf '  [OK]   %-'"$CHKW"'s %s\n' "${prefix}: 照会先 ${target_label} contract 実在" "${target_rel:-$target_abs}"
  # (c) doc_id 一致 (contract 側 docid フィールド == target 側 docid フィールド)
  chk "${prefix}: doc_id == ${target_label} contract" "$(yq -r "$target_docid_expr" "$target_abs")" "$(q "$contract_docid_expr")"
  # (a) count anchor: |edges| == HTML の data-<keyAttr>= 出現数 (set_eq は sort -u で重複を潰す → 重複注入は count で捕捉)
  chk "${prefix}: count == |edges|" "$(q "$count_expr")" "$(grep -o "${key_attr}=" "$BODY" | wc -l | tr -d ' ')"
  # (a) SET 一致: contract key 集合 == HTML data-<keyAttr> 集合 (捏造 0 + 脱落 0)
  # ★collation 統一 (folio-tv5 / folio-wqh と同根): 両辺の sort -u + 内部 comm を呼ぶ set_eq を *全て LC_ALL=C 下*で
  #   揃え、 data-key/role に大文字 ascii と小文字が混在しても locale 照合差で set_eq が *集合は同一なのに* false FAIL する
  #   verify-side latent fragility を封じる (現状 lowercase 主体で未発火・B5 论点4 が本関数を graph 到達性へ拡張する土台ゆえ
  #   同時是正が自然)。 verify_term_inline (folio-wqh) の LC_ALL=C 不動点を複製。 verify-side only・出力 (PASS/FAIL 判定) 不変。
  local exp_k act_k
  exp_k="$(q "$keys_expr" | LC_ALL=C sort -u)"
  act_k="$(grep -oE "${key_attr}=\"[^\"]+\"" "$BODY" | sed "s/.*${key_attr}=\"//; s/\"\$//" | LC_ALL=C sort -u)"
  LC_ALL=C set_eq "${prefix}: key SET (contract == HTML)" "$exp_k" "$act_k"
  # (b) dangling 照会 0: contract key が参照先 ID に実在 (sort -u と comm を同一 C 照合へ揃える = sort/comm 照合不整合回避)
  local dangling
  dangling="$(LC_ALL=C comm -23 <(q "$keys_expr" | LC_ALL=C sort -u) <(yq -r "$target_ids_expr" "$target_abs" | LC_ALL=C sort -u))"
  chk_empty "${prefix}: dangling 照会 (${target_label} に無い key)" "$(printf '%s' "$dangling" | tr '\n' ' ' | sed 's/ *$//')"
  # (i') ★空値ガード (core の核): comm -23 が空行を空 missing に畳む fail-open を塞ぐ。 contract key 全件非空を明示要求
  #      (空照会キー = option/要件 に繋がらない壊れた前方/後方参照。 assemble validate と対称・両 pack 共通)。
  chk "${prefix}: key 全て非空 (空照会キー禁止)" "$(q "$count_expr")" "$(q "$nonempty_count_expr")"
  # (d) role allowlist (HTML 側 data-<roleAttr> ⊆ 抽象ロール allowlist)
  local badrole
  badrole="$(grep -oE "${role_attr}=\"[^\"]+\"" "$BODY" | sed "s/.*${role_attr}=\"//; s/\"\$//" | LC_ALL=C sort -u \
    | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
  chk_empty "${prefix}: 照会 role が抽象 allowlist 内" "$badrole"
  # (d') (key,role) ペア SET 一致: allowlist 内別 role への改竄 = 照会 graph の意味偽装を捕捉 (role allowlist だけでは fail-open)
  local exp_kr act_kr
  exp_kr="$(q "$pair_expr" | LC_ALL=C sort -u)"
  act_kr="$(grep -oE "${key_attr}=\"[^\"]+\" ${role_attr}=\"[^\"]+\"" "$BODY" \
    | sed -E "s/${key_attr}=\"([^\"]+)\" ${role_attr}=\"([^\"]+)\"/\1\t\2/" | LC_ALL=C sort -u)"
  LC_ALL=C set_eq "${prefix}: (key,role) ペア (contract == HTML)" "$exp_kr" "$act_kr"
  return 0
}

# ---- repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-mzn.3 Phase B / folio-3d23) ----
# 占有 pin 群の *構造終端後継*: contract (+prose) から assemble-<pack>.sh → inject-prose.sh を mktemp へ
# *再 build* し、 footer 生成時刻 (lib/common.sh core_emit_footer の「生成: <b>YYYY-MM-DD HH:MM</b>」= 唯一の
# 非決定源・verified: 全 assembler で date-current は core_emit_footer のみ・2× build diff 空) *だけ* を両辺
# *同一 strict regex* で正規化して cmp する。 不一致 = post-build 改変 (任意の手編集・占有 pin が個別に数え
# ない領域の改竄) を byte 逸脱として *一括* blocking FAIL する (占有 pin が個々の部品数を数えるのに対し、
# 本 arm は生成物 *全体* の byte 恒等を 1 本で守る = pin 群の構造終端後継)。
#
# ★正規化の健全性論証 (設計 SSoT): 正規化は両辺を *同一関数* で写像する quotient-map。 商クラスは
#   「生成: <b>\d{4}-\d\d-\d\d \d\d:\d\d</b>」の *厳密 timestamp 形* のみ。 緩い regex は差分 masking の穴
#   (= blocking 差戻し級)。 攻撃者が本文へ timestamp 形テキストを注入しても、 再 build 側に *その行が無い*
#   ため byte 差として残る (置換は footer の当該 <b>…</b> context 内でしか起きない)。 健全。
#
# prose 解決優先順: REPRO_PROSE (明示 env override) > 呼出元 --filled manifest ($2) > contract 名規約 (2-try)。
#   対象 HTML が pre-fill 状態 (footer「prose 未充填 (opus 待ち)」) なら prose 不要 (assemble のみ再 build)。
# 入力欠落 (contract/prose/assemble 不在)・assemble/inject 再実行の非零 exit = 測定系 tool-integrity error
#   (exit 2 idiom・gate 判定と分離。 verify を即 exit 2 で終える = 「測定不能を clean と詐称しない」)。
# SKIP_REPRO=1 で honest SKIP (floor 不完全と明示・PASS 詐称せず。 敵対 suite の bulk case 高速化用。 arm 自体は
#   verify-*.sh 既定 ON = 消費者は SKIP_REPRO 無しで走らせ本 arm が効く。 gate F の SRS_SKIP_RENDER と同型 idiom)。
#
# ★prose-sensitivity 注記: 本 arm は post-build 改変に加え「manifest から逸脱した prose」も byte 逸脱として
#   捕捉する (floor が prose-sensitive 化する)。欠陥 fixture 等を検証する caller は対象を manifest-backed に
#   保ち REPRO_PROSE=<fixture>.prose.yaml で arm ON のまま正直に通す (oracle/build-fixtures.sh が実例。
#   SKIP_REPRO 方式は ceiling-precheck の [SKIP] masquerade guard と衝突するため oracle では撤回済)。
#
# usage: verify_repro_build <pack> [filled_manifest]
#   <pack>            assemble-<pack>.sh / の pack 名 (srs/adr/research/arch/vision/testcases/spec/principle/glossary/verification/relations/datamodel/interface)
#   [filled_manifest] 呼出元が --filled で受けた manifest path (無ければ空文字。 srs は mode 無しゆえ常に空)
# 前提: $SCRIPT_DIR / $CONTRACT / $HTML / $fail / $CHKW。 byte 不一致 = $fail=1 (gate FAIL)、 tool error = exit 2。
verify_repro_build() { # $1 = pack  $2 = filled_manifest (optional)
  local pack="$1" filled_manifest="${2:-}"
  if [[ -n "${SKIP_REPRO:-}" ]]; then
    printf '  [SKIP] %-'"$CHKW"'s %s\n' "repro-build: SKIP_REPRO 指定 (floor 不完全・PASS 詐称せず)" "skip"
    return 0
  fi
  local asm="$SCRIPT_DIR/assemble-$pack.sh" inj="$SCRIPT_DIR/inject-prose.sh"
  [[ -f "$asm" ]] || { echo "  [TOOLERR] repro-build: assemble-$pack.sh 不在 ($asm) — 測定不能 (exit 2)"; exit 2; }
  [[ -f "$inj" ]] || { echo "  [TOOLERR] repro-build: inject-prose.sh 不在 ($inj) — 測定不能 (exit 2)"; exit 2; }
  [[ -f "$CONTRACT" ]] || { echo "  [TOOLERR] repro-build: contract 不在 ($CONTRACT) — 測定不能 (exit 2)"; exit 2; }
  # 対象 HTML の充填状態を footer トークンで判定 (inject が決定的に flip する 2 状態のいずれか)。
  local want_filled=0
  grep -qF 'prose ✓ 充填済' "$HTML" && want_filled=1
  # 1. assemble 再実行 (原 contract path のまま渡す → cross_doc 兄弟解決を保つ・出力のみ mktemp へ)。
  #   ★出力は stdout redirect で受ける (OUT 引数非依存): 大半の assembler は [out.html] を取るが assemble-glossary.sh
  #   は stdout 専用 (OUT 引数を取らない) ため、 全 assembler が OUT 既定 /dev/stdout へ書く形に統一して捕捉する。
  local tmp_a tmp_f="" built
  tmp_a="$(mktemp)"
  if ! bash "$asm" "$CONTRACT" > "$tmp_a" 2>/dev/null; then
    rm -f "$tmp_a"; echo "  [TOOLERR] repro-build: assemble-$pack 再実行が非零 exit (測定不能・exit 2)"; exit 2
  fi
  built="$tmp_a"
  if [[ "$want_filled" -eq 1 ]]; then
    # 2. prose 解決 (env override > --filled manifest > 規約 2-try)。
    local prose="${REPRO_PROSE:-$filled_manifest}"
    [[ -n "$prose" ]] || prose="$(_repro_prose_convention "$CONTRACT")"
    if [[ -z "$prose" || ! -f "$prose" ]]; then
      rm -f "$tmp_a"; echo "  [TOOLERR] repro-build: prose manifest 不在 (充填 HTML の再 build に必須・REPRO_PROSE で明示可): '${prose:-<未解決>}' — 測定不能 (exit 2)"; exit 2
    fi
    tmp_f="$(mktemp)"
    if ! bash "$inj" "$prose" "$tmp_a" "$tmp_f" >/dev/null 2>&1; then
      rm -f "$tmp_a" "$tmp_f"; echo "  [TOOLERR] repro-build: inject-prose 再実行が非零 exit (測定不能・exit 2)"; exit 2
    fi
    built="$tmp_f"
  fi
  # 3. footer 生成時刻のみ両辺を同一 strict regex で正規化 (quotient-map) → 4. byte 比較。
  #   ★正規化 (perl) の失敗・空出力は測定不能 = exit 2 (perl 起動故障で両辺空 → cmp 一致の false-PASS を
  #   封鎖・「測定不能を clean と詐称しない」契約の残存穴 fix・folio-3d23 ceiling round-1 minor)。
  local tmp_bn tmp_hn; tmp_bn="$(mktemp)"; tmp_hn="$(mktemp)"
  if ! _repro_normalize_ts < "$built" > "$tmp_bn" || ! _repro_normalize_ts < "$HTML" > "$tmp_hn" \
     || [[ ! -s "$tmp_bn" || ! -s "$tmp_hn" ]]; then
    rm -f "$tmp_a" "$tmp_f" "$tmp_bn" "$tmp_hn"
    echo "  [TOOLERR] repro-build: 正規化 (perl) 失敗 or 空出力 — 測定不能 (exit 2)"; exit 2
  fi
  if cmp -s "$tmp_bn" "$tmp_hn"; then
    printf '  [OK]   %-'"$CHKW"'s %s\n' "repro-build: 再 build byte-identity (時刻正規化のみ)" "識別"
  else
    # ★reason substring 'repro-build:BYTE-DIFF' は [FAIL] 行にしか出ない値 (gate 一意・判別力保持)。
    printf '  [FAIL] %-'"$CHKW"'s\n' "repro-build:BYTE-DIFF 再 build が byte 不一致 (post-build 改変検出)"
    cmp "$tmp_bn" "$tmp_hn" 2>&1 | head -1 | sed 's/^/      repro-diff: /'
    fail=1
  fi
  rm -f "$tmp_a" "$tmp_f" "$tmp_bn" "$tmp_hn"
}

# footer 生成時刻の strict 正規化 (両辺同一適用の quotient-map)。 「生成: <b>YYYY-MM-DD HH:MM</b>」の *厳密
# timestamp 形* のみを固定 placeholder へ畳む (緩めない = masking 防止)。 byte モード perl (no -C): program 内
# literal 日本語バイト == 入力 UTF-8 バイトで一致・[0-9] は ASCII digit のみ。 stdin→stdout。
_repro_normalize_ts() {
  perl -0777 -pe 's{生成: <b>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}</b>}{生成: <b>REPRO-TS-NORMALIZED</b>}g'
}

# prose 規約導出 (2-try): contract が <dir>/contract/<base>.<pack>.yaml のとき prose は <dir>/../prose/ 配下。
#   try1: <stem>.prose.yaml (stem = basename の .yaml 除去 = <base>.<pack>) = .pack.prose.yaml 系 (adr/research/arch/vision/testcases/principle)。
#   try2: <base>.prose.yaml (pack infix 除去) = 旧 base.prose.yaml 系 (srs/spec/glossary/verification/relations)。
#   先に存在する方を返す (無ければ空文字 = 呼出側で tool error 判定)。 不規則命名は REPRO_PROSE env で上書き。
_repro_prose_convention() { # $1 = contract path
  local contract="$1" dir stem base p
  dir="$(cd "$(dirname "$contract")" && pwd)/../prose"
  stem="$(basename "$contract" .yaml)"       # <base>.<pack>
  base="${stem%.*}"                          # <base>
  for p in "$dir/$stem.prose.yaml" "$dir/$base.prose.yaml"; do
    [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }
  done
  printf ''
}

# ---- gate F (render 健全性・visual) cross-pack helper (folio-vuf A 段) ----
# 既存 SRS gate F (render-gate-srs.py + probe-srs.js、 mzn.3 baseline 6df5365) を *非 mermaid pack* へ
# drop-in 展開する共有 helper。 render-gate-srs.py は doc-type 非依存 (probe-srs.js は data-component /
# contrast / horizontal-overflow / clipped-content を見るだけで SRS 構造を parse しない・verified) ゆえ、
# 生成 HTML を単一ファイルとして light/dark × 3 viewport で検査する。 render-gate-srs.py 本体は *無改変*
# ゆえ SRS 非回帰は構造保証 (verify-srs.sh の inline gate F もそのまま)。 本 helper は非 mermaid pack 用の
# 独立 wiring。
#
# ★mermaid-aware render (A/B 境界・B 段 folio-jyfh で defer 解消): 対象 HTML が <pre class="…mermaid…"> を含む
#   なら、 A 段の honest SKIP を撤廃し *実 render* する。 mermaid pack は assets/mermaid.min.js を非同期 render
#   するため、 render-gate-srs.py 側が SVG 本数の期待図数到達を polling (最大 15s) してから幾何/contrast を
#   検査し、 settle 不足 (svgCount<期待) は fail-closed FAIL に倒す。 render 直前に vendor を配信 root へ staging
#   する (下記・srs.css staging と同型)。 vision doc-type は instance 依存 (folio-vision=図なし / clinic-
#   appointment.vision=goal_tree flowchart) だが、 doc-type でなく *生成 HTML の実体* で mermaid を検出するため
#   どちらの instance も正しく分岐する。
#
# ★T7 fail-closed guard (mzn.3 教訓・展開先でも維持): render-gate-srs.py の exit を sed パイプで洗浄しない。
#   PIPESTATUS[0] で render-gate の exit を *直接* 読み、 violation (exit 1) も crash/tool error (exit 2) も
#   *等しく* $fail=1 に倒す (warn/pass への洗浄禁止・set -o pipefail 有無に非依存)。 text 0 (render 破綻) は
#   render-gate-srs.py 内部で既に fail-closed FAIL (exit 1)。
#
# SKIP 条件 (いずれも honest SKIP・PASS 詐称せず floor 不完全と明示):
#   (a) <SKIP_ENV>=1 / SKIP_RENDER=1 明示 (敵対 bash floor 高速化・SRS_SKIP_RENDER と同型 idiom)
#   (b) render-gate-srs.py 不在  (c) playwright renderer 不在 (python3 / uv)
#   ※ mermaid 検出はもはや SKIP でなく render + vendor staging (B 段 folio-jyfh)。
#
# usage: render_gate_f <html> [skip_env_name]
# 前提: $SCRIPT_DIR (generator dir) / $fail。 violation/crash = $fail=1、 SKIP/pass は $fail 不変。 return 0 固定
#   (gate 結果は $fail 経由でのみ伝える = 呼出側 `render_gate_f ... || ...` の誤用で SKIP を fail 化しない)。
render_gate_f() { # $1 = 生成 HTML  $2 = skip env 名 (任意)
  local html="$1" skip_env="${2:-}" gate="$SCRIPT_DIR/render-gate-srs.py"
  echo
  echo "--- gate F: render 健全性 (playwright: low-contrast / horizontal-overflow / component-overlap・cross-pack 展開 folio-vuf A) ---"
  # SKIP (a): 明示 skip env (pack 別 <SKIP_ENV> か共通 SKIP_RENDER)。 実トリガを正しく表示する。
  local trigger=""
  if [[ -n "$skip_env" && "${!skip_env:-0}" == "1" ]]; then trigger="$skip_env"
  elif [[ "${SKIP_RENDER:-0}" == "1" ]]; then trigger="SKIP_RENDER"; fi
  if [[ -n "$trigger" ]]; then
    printf '  [SKIP] gate F (%s=1 — bash floor のみ・PASS 詐称せず・floor 不完全)\n' "$trigger"
    return 0
  fi
  # SKIP (c): render-gate-srs.py 不在
  if [[ ! -f "$gate" ]]; then
    printf '  [SKIP] gate F (render-gate-srs.py 不在: %s — floor 不完全)\n' "$gate"
    return 0
  fi
  # mermaid 図検出 (B 段・folio-jyfh): A 段の honest SKIP を撤廃し、 実 render する。 render-gate-srs.py が
  #   assets/mermaid.min.js を非同期 load し、 SVG 本数が期待図数へ到達するまで polling (最大 15s) してから
  #   幾何/contrast を検査する (settle 不足は svgCount<期待 で fail-closed FAIL)。 vendor が配信 root から届く
  #   よう render 直前に staging する (下記・srs.css staging と同型)。 mermaid 無しなら has_mermaid=0 で従来通り。
  local has_mermaid=0
  if grep -qE '<pre[^>]*class="[^"]*mermaid|class="[^"]*mermaid[^"]*"' "$html"; then has_mermaid=1; fi
  # RUNNER 検出 (verify-srs.sh gate F と同型: python3 import > uv > ~/.local/bin/uv)。
  local runner=""
  if python3 -c "import playwright" >/dev/null 2>&1; then runner="python3"
  elif command -v uv >/dev/null 2>&1; then runner="uv run --with playwright==1.60.0 python"
  elif [[ -x "$HOME/.local/bin/uv" ]]; then runner="$HOME/.local/bin/uv run --with playwright==1.60.0 python"
  fi
  # SKIP (d): renderer 不在
  if [[ -z "$runner" ]]; then
    printf '  [SKIP] gate F (playwright renderer 不在 — CI/uv 環境で render-gate-srs.py を実行・floor 不完全)\n'
    return 0
  fi
  # ★外部 stylesheet staging (glossary pack のみ srs.css を <link> 外部参照 = inline しない)。 配信 root
  #   (html の親 dir) に実体が無いと未スタイル描画になり contrast 面が vacuous-green 化する (folio-jyfh
  #   wiring cert 実証) — render 直前に staging し、 cp 不能は tool error として FAIL (fail-closed・素通り禁止)。
  #   inline pack は link を持たず no-op。
  if grep -q '<link rel="stylesheet" href="srs.css">' "$html" && [[ ! -f "$(dirname "$html")/srs.css" ]]; then
    if ! cp "$SCRIPT_DIR/../srs.css" "$(dirname "$html")/srs.css" 2>/dev/null; then
      printf '  [FAIL] gate F (外部 stylesheet srs.css を配信 root へ staging 不能 — 未スタイル描画は contrast vacuous ゆえ fail-closed)\n'
      fail=1; return 0
    fi
  fi
  # ★mermaid vendor staging (B 段・folio-jyfh)。 生成 HTML は assets/mermaid.min.js を相対参照 (clinic pack=
  #   assets/・folio self-spec pack=../assets/ だが、 配信 root 直下 serve では browser の URL 正規化で両者とも
  #   /assets/mermaid.min.js に解決する = RFC3986 の .. は root で discard)。 実体が配信 root に無いと mermaid が
  #   render せず svgCount=0 → shortfall FAIL (vacuous-green でなく fail-closed) ゆえ、 render 直前に staging し、
  #   cp 不能は tool error として FAIL (素通り禁止)。 mermaid 無し pack は no-op。
  if [[ "$has_mermaid" == "1" ]]; then
    local mvendor="$SCRIPT_DIR/../../../design-intent/assets/mermaid.min.js"
    local mdest_dir; mdest_dir="$(dirname "$html")/assets"
    if [[ ! -f "$mdest_dir/mermaid.min.js" ]]; then
      if ! { mkdir -p "$mdest_dir" && cp "$mvendor" "$mdest_dir/mermaid.min.js"; } 2>/dev/null; then
        printf '  [FAIL] gate F (mermaid vendor を配信 root へ staging 不能: %s — 未 render は render 不全ゆえ fail-closed)\n' "$mvendor"
        fail=1; return 0
      fi
    fi
  fi
  echo "  render-gate-srs.py を実行 ($runner)..."
  # ★T7 fail-closed: pipe 経由でも PIPESTATUS[0] で render-gate の exit を直接読む (sed の exit で洗浄しない)。
  $runner "$gate" "$html" 2>&1 | sed 's/^/    /'
  local rc="${PIPESTATUS[0]}"
  if [[ "$rc" -eq 0 ]]; then
    printf '  [OK]   gate F pass (0 overflow / 0 overlap / 0 low-contrast・light+dark × 3 viewport render 確認済)\n'
  else
    printf '  [FAIL] gate F (render-gate-srs.py exit %s — violation or render 破綻/tool error・fail-closed)\n' "$rc"
    fail=1
  fi
  return 0
}
