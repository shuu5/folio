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
      $v =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $v =~ s/&#(\d+);/chr($1)/ge;
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
      $v =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
      $v =~ s/&#(\d+);/chr($1)/ge;
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
      $v =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $v =~ s/&#(\d+);/chr($1)/ge;
      $v =~ s/[\t\n]/ /g;
      print "$v\n";
    }
  '
}

# count_genuine_reader_chip — stdin HTML を *要素単位* に走査し、 class に reader-chip トークンを持ち かつ
# data-component に cross-doc-ref-chip トークンを *持たない* 開始タグ数を出力 (quote 構文・属性名 case・数値文字参照 非依存)。
# ★なぜ要素単位か (folio-mk9 self-review): 旧実装は (class reader-chip 占有) − (data-component cross-doc-ref-chip 占有)
#   の *差分* で genuine reader-chip 数を求めていた。 だが ref-chip と同一構文 `class="reader-chip" data-component="cross-doc-ref-chip"`
#   を持つ additive decoy を 1 個注入すると 被減数 (+1)・減数 (+1) が *同じタグ上で同時に* 増えて差は 1 のまま不変
#   = 偽『想定読者:』chip を SRS へ捏造注入しても全 verify を素通る fail-open があった (被減数/減数が独立に動かない前提が崩れる)。
#   本 helper は *各タグ内で* class と data-component を突合し「reader-chip だが cross-doc-ref-chip でない」を要素単位で数えるゆえ、
#   両属性を併載した decoy は ref-chip 側に分類され genuine count を増やさない = additive decoy を構造的に封鎖する。
# 走査: 開始タグ `<tag ...>` を 1 個ずつ取り、 その属性文字列内の class / data-component 各 occurrence を 3 分岐 (double/single/unquoted)
#   parse + 数値文字参照 decode + 空白トークン分割 + lc 比較で照合する (count_attr_token と同じ quote-robust 規律)。
count_genuine_reader_chip() { # HTML は stdin
  perl -CSD -0777 -e '
    my $q=chr(39); my $txt=<STDIN>; $txt="" unless defined $txt;
    # attr 値 (3 分岐) を decode + lc トークン集合へ畳む sub。
    my $toks = sub { my ($attrs,$name)=@_; my %h;
      while ($attrs =~ /\b(?i:\Q$name\E)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g) {
        my $v = defined $1 ? $1 : (defined $2 ? $2 : $3);
        $v =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $v =~ s/&#(\d+);/chr($1)/ge;
        $h{lc $_}=1 for grep { length } split(/\s+/, $v);
      } return \%h; };
    my $c=0;
    # 開始タグの属性文字列 (タグ名直後 〜 タグを閉じる > まで) を 1 個ずつ。 ★属性値内の > に耐える:
    #   素朴な [^>]* は `<div title="x>y" class="reader-chip">` の title 内 > で早期終端し class を取り逃す
    #   (folio-mk9 self-review round-6: count_genuine が genuine-style decoy を見逃す >-断片化 fail-open)。
    #   属性部を『"..." | '"'"'...'"'"' | 非> 文字』の連なりとして取り、 quoted attr 内の > を構造的に飲み込む。
    while ($txt =~ /<[A-Za-z][\w-]*((?:"[^"]*"|$q[^$q]*$q|[^>])*)>/g) {
      my $attrs=$1;
      my $cls=$toks->($attrs,"class"); my $dc=$toks->($attrs,"data-component");
      $c++ if $cls->{"reader-chip"} && !$dc->{"cross-doc-ref-chip"};
    }
    print $c;
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

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、
# <style> ブロックを除去した body-only ビューで数える ($BODY をグローバルに設定し EXIT で掃除)。
make_body() { # $1 = html path
  BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
  sed '/<style>/,/<\/style>/d' "$1" > "$BODY"
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
# approval-block (role/who/when/stamp)・glossary-term-table (term/en/def) — を contract と *順序付き値突合 + 占有数パリティ*
# の二層で検証する。 SRS/ADR/research 全 pack 共通の cross-pack gap (dty round-2 完全列挙が発見): 7b 相当の *件数のみ* 検証で
# 値改竄 (eyebrow『要件定義書』→詐欺・承認者名 swap・glossary 定義の捏造) が件数保存のまま素通る fail-open だった。
# ★ds8/dty 不動点を踏襲: row/block-scope 抽出 + 順序リスト厳密一致 (set でなく ordered match) + quote-robust
#   count_attr_token 占有数パリティ (case-drop+decoy / quote 逸脱 / entity ghost の add を封鎖) の二層。
# ★抽出は固定 nested 構造の structured-regex で leaf を [^<]* に限定する = 内側へのタグ注入は構造不一致で row 脱落 →
#   件数/順序 FAIL (ds8 の marker-keyed nested-reject と同値の堅牢性。 [^<]* leaf は < を含めないゆえ非貪欲の早期終端・
#   空要素 early-match・偽 provenance を構造的に拒否する)。 値そのものの改竄は順序突合 (chk) が、 case-drop/quote/entity の
#   add は占有数パリティ (count_attr_token) が担う = 二層。
# ★shared class の占有数は block-scope で数える: role は approval の <span class="role"> だが SRS actor の <div class="role"> と
#   class 共有ゆえ *sign 行内* occurrence で数える / en は glossary 表と EARS legend (folio-czo) で class 共有ゆえ *grow 行内* で数える。
#   approval 専有 (sign/who/when/stamp)・glossary 専有 (grow/gword/gdef)・cover 単一 (doc-type/cover-eyebrow/cover-sub) は global。
# ★scope 外 (= 対象外): summary-card の lab (per-pack 固定リテラル "この文書が約束すること" 等) は contract 由来でない静的 chrome
#   ゆえ突合しない (legend lt と同型・改竄しても contract 値の捏造ではない)。 reader-chip class は ADR/research で
#   cross-doc-ref-chip が同 class を再利用するため 2 個 = global count 不可 → genuine reader-chip は `class="reader-chip">`
#   (閉じ引用直後が >) で識別する (ref-chip は `class="reader-chip" data-component=...` = 引用後に空白)。 行 scope で値突合 + marker count==1。
# 前提: $BODY (make_body 済) / $CONTRACT / q / esc / chk / count_attr_token / $fail / $CHKW。 mode 非依存 (chrome は構造ゆえ
#  pre-fill/--filled/--artifact のいずれでも同一・prose slot を持たない)。 3 pack verify から無条件に呼ぶ。
verify_core_chrome() {
  local nap ngl nen signrows growrows readerlines
  nap="$(q '.approval | length')"; ngl="$(q '.glossary | length')"
  nen="$(q '[.glossary[] | select((.en // "") != "")] | length')"
  signrows="$(grep 'class="sign"' "$BODY")"; growrows="$(grep 'class="grow"' "$BODY")"
  # genuine reader-chip 行を厳密 anchor で抽出: 本物は `class="reader-chip">` (閉じ引用直後が >)、
  # cross-doc-ref-chip は `class="reader-chip" data-component=...` (引用後に空白+属性) ゆえ別物。 これで
  # (i) ref-chip を除外 / (ii) 自由文 prose 中の "想定読者:" 偶然一致を除外 (false-positive 防止) しつつ、
  # 偽 reader-chip decoy (同 class 構造) は readerlines に複数行入り値突合/marker count で必ず FAIL する。
  readerlines="$(grep 'class="reader-chip">' "$BODY")"

  # (1) cover-head (core_emit_cover_head / _tail): eyebrow (doc-type + 右 bare span を *対で*)・title (h1)・
  #     subtitle (cover-sub)・reader (reader-chip の "想定読者: " 後の可視テキスト) を順序付き値突合。
  chk "core-chrome: cover-eyebrow (左,右) == .meta.eyebrow_left/right" \
    "$(printf '%s\t%s' "$(esc "$(q '.meta.eyebrow_left')")" "$(esc "$(q '.meta.eyebrow_right')")")" \
    "$(perl -CSD -0777 -ne 'while (/<p class="cover-eyebrow"><span class="doc-type">([^<]*)<\/span> <span>([^<]*)<\/span><\/p>/g){ print "$1\t$2\n"; }' "$BODY")"
  chk "core-chrome: cover h1 == .meta.title" "$(esc "$(q '.meta.title')")" \
    "$(grep -oE '<h1>[^<]*</h1>' "$BODY" | sed -E 's#<h1>([^<]*)</h1>#\1#')"
  chk "core-chrome: cover-sub == .meta.subtitle" "$(esc "$(q '.meta.subtitle')")" \
    "$(grep -oE '<p class="cover-sub">[^<]*</p>' "$BODY" | sed -E 's#<p class="cover-sub">([^<]*)</p>#\1#')"
  chk "core-chrome: reader-chip 想定読者 == .meta.reader" "$(esc "$(q '.meta.reader')")" \
    "$(printf '%s\n' "$readerlines" | grep -oE '想定読者: [^<]*</div>' | sed -E 's/^想定読者: //; s#</div>$##')"
  # 占有数パリティ (single anchor・global・quote/case/entity 非依存)。 h1 は class 無しゆえ タグ count (case 非依存) で偽 h1 を封鎖。
  chk "core-chrome: vcount doc-type == 1"      "1" "$(count_attr_token class doc-type < "$BODY")"
  chk "core-chrome: vcount cover-eyebrow == 1" "1" "$(count_attr_token class cover-eyebrow < "$BODY")"
  chk "core-chrome: vcount cover-sub == 1"     "1" "$(count_attr_token class cover-sub < "$BODY")"
  chk "core-chrome: h1 タグ == 1"              "1" "$(grep -oiE '<h1[[:space:]>]' "$BODY" | wc -l | tr -d ' ')"
  chk "core-chrome: reader-chip 想定読者 == 1" "1" "$(printf '%s\n' "$readerlines" | grep -oF '想定読者:' | wc -l | tr -d ' ')"
  # ★構造 anchor 占有数パリティ (genuine reader-chip == 1)。 上の marker count は *想定読者: 内容* に keyed ゆえ、
  #   marker を *持たない* 偽 reader-chip decoy (`class="reader-chip"> 詐欺` = anchor 一致だが marker 無し) を素通す
  #   fail-open があった (reader-chip は cross-doc-ref-chip と class 共有で EXEMPT = class-occupancy anchor が無い)。
  #   genuine anchor `class="reader-chip">` (閉じ引用直後が >) は全 pack で正確に 1 個・ref-chip は `class="reader-chip" data-...`
  #   (引用後に空白) ゆえ偽陽性しない。 marker 有無に依らず anchor 数で decoy add を封鎖する (二層目)。
  chk "core-chrome: vcount reader-chip anchor == 1" "1" "$(grep -c 'class="reader-chip">' "$BODY")"
  # ★占有数パリティ (genuine reader-chip == 1) を *要素単位* で quote-robust に強制する (三層目)。 上の anchor grep は
  #   `class="reader-chip">` (閉じ引用直後が >) という *string anchor* に keyed ゆえ、 ref-chip *構文形* の decoy
  #   (`class="reader-chip" role="note">詐欺…` = 閉じ引用後に空白+任意属性) を素通す fail-open があった
  #   (anchor は > 直後でなく不一致 / marker count も "想定読者:" 無しで不一致 / class-token 機械的網羅は reader-chip を
  #   既知 EXEMPT として黙認)。 ★さらに 旧 `(class reader-chip 占有) − (data-component cross-doc-ref-chip 占有)` *差分* 方式は、
  #   ref-chip と同一構文 `class="reader-chip" data-component="cross-doc-ref-chip">想定読者: 詐欺…` の additive decoy を 1 個注入すると
  #   被減数 (+1)・減数 (+1) が *同じタグ上で同時に* 増えて差が 1 のまま不変 = 偽『想定読者:』chip 捏造を全 verify が素通す fail-open があった
  #   (folio-mk9 self-review round-4 が SRS で実証: full verify exit 0)。 被減数/減数の独立性を前提にした差分式は構造的に脆い。
  #   genuine reader-chip は「class に reader-chip かつ data-component に cross-doc-ref-chip *無し*」を満たす要素 = 全 pack で厳密に 1 個ゆえ、
  #   count_genuine_reader_chip で *各タグ内* に両属性を突合して == 1 を強制する (両属性併載 decoy は ref-chip 側に分類され count に乗らない)。
  chk "core-chrome: genuine reader-chip 占有 (ref-chip 除外・要素単位) == 1" "1" \
    "$(count_genuine_reader_chip < "$BODY")"
  # ★『想定読者:』marker は genuine reader-chip 専有 (ref-chip は "この調査の行き先:"/"正当化する要件:" 別 marker・全 pack で 1 個ちょうど)
  #   ゆえ *body 全体* の marker 出現数 == 1 を強制する (四層目)。 上の element-level count は両属性併載 decoy を ref-chip 側に正しく
  #   分類するが、 decoy が ref-chip でありながら『想定読者: 詐欺…』text を載せると genuine count は 1 のまま偽『想定読者』chrome を描画できる
  #   (folio-mk9 self-review round-4: SRS で full verify exit 0 のまま偽読者 chip 捏造)。 marker は本物の reader 値 1 つにしか付かない不変ゆえ、
  #   anchor-keyed (readerlines) でなく *global* marker count で ref-chip へ寄生した偽 marker を封鎖する (readerlines は anchor 外の decoy を含まない)。
  chk "core-chrome: 想定読者 marker 全体 == 1" "1" "$(grep -oF '想定読者:' "$BODY" | wc -l | tr -d ' ')"

  # (2) approval-block (core_emit_approval_block): (role,who,when,stamp) を sign 行から *配列順* で突合。
  #     stamp class は stamp | stamp self (stamp != 承認済 で self・修飾子) ゆえ (?: self)? で両形を受ける。
  chk "core-chrome: approval (role,who,when,stamp) == .approval (順序)" \
    "$(q '.approval[] | [.role, .who, .when, .stamp] | @tsv' | while IFS=$'\t' read -r _r _w _t _s; do printf '%s\t%s\t%s\t%s\n' "$(esc "$_r")" "$(esc "$_w")" "$(esc "$_t")" "$(esc "$_s")"; done)" \
    "$(perl -CSD -0777 -ne 'while (/<div class="sign"><span class="role">([^<]*)<\/span><span class="who">([^<]*)<\/span><span class="when">([^<]*)<\/span><span class="stamp(?: self)?">([^<]*)<\/span><\/div>/g){ print "$1\t$2\t$3\t$4\n"; }' "$BODY")"
  chk "core-chrome: vcount sign == |approval|"  "$nap" "$(count_attr_token class sign < "$BODY")"
  chk "core-chrome: vcount who == |approval|"   "$nap" "$(count_attr_token class who < "$BODY")"
  chk "core-chrome: vcount when == |approval|"  "$nap" "$(count_attr_token class when < "$BODY")"
  chk "core-chrome: vcount stamp == |approval|" "$nap" "$(count_attr_token class stamp < "$BODY")"
  chk "core-chrome: sign 行内 role == |approval| (actor div.role と分離)" "$nap" "$(printf '%s\n' "$signrows" | count_attr_token class role)"

  # (3) glossary-term-table (emit_glossary): (term,en,def) を grow 行から *配列順* で突合。 en 空時は enb 無し ((?:...)? で両対応)。
  chk "core-chrome: glossary (term,en,def) == .glossary (順序)" \
    "$(q '.glossary[] | [.term, (.en // ""), .def] | @tsv' | while IFS=$'\t' read -r _te _en _de; do printf '%s\t%s\t%s\n' "$(esc "$_te")" "$(esc "$_en")" "$(esc "$_de")"; done)" \
    "$(perl -CSD -0777 -ne 'while (/<div class="grow"><div class="gword">([^<]*)(?:<span class="en">([^<]*)<\/span>)?<\/div><div class="gdef">([^<]*)<\/div><\/div>/g){ my $e=defined $2 ? $2 : ""; print "$1\t$e\t$3\n"; }' "$BODY")"
  chk "core-chrome: vcount grow == |glossary|"  "$ngl" "$(count_attr_token class grow < "$BODY")"
  chk "core-chrome: vcount gword == |glossary|" "$ngl" "$(count_attr_token class gword < "$BODY")"
  chk "core-chrome: vcount gdef == |glossary|"  "$ngl" "$(count_attr_token class gdef < "$BODY")"
  chk "core-chrome: grow 行内 en == |非空 en| (legend en と分離)" "$nen" "$(printf '%s\n' "$growrows" | count_attr_token class en)"
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
