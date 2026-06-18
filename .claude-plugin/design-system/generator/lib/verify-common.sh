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
    print "$_\n" for sort @out;
  ')"
  rm -f "$MKF" "$GF2"
  act_marks="$(printf '%s\n' "${MARKS[@]}" | grep . | sed -E 's/.*data-term="([^"]*)".*/\1/' | sort -u)"
  set_eq "$cov_label" "$exp_marks" "$act_marks"
}
