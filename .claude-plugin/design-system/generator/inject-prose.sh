#!/usr/bin/env bash
# folio S4 generator — 決定的 prose injector (ADR-0042 §2.1 の③)
#
# 空の prose スロット (assemble-srs.sh / assemble-adr.sh が data-slot-id 付きで出力) へ、 prose manifest の散文を
# HTML escape して注入する。 opus が書くのは manifest だけ。 注入は機械的で fabrication-free を
# prose 層でも保つ (任意 markup は escape され構造を壊せない)。
#
# fail-closed:
#   - HTML スロット id 集合と manifest key 集合が *完全一致* (未充填=脱落 / 余剰=orphan を両方拒否)。
#   - manifest 値に tab/改行 (列ずれ・注入崩れの源) や空値があれば拒否。
#   - 注入後に空スロットが 1 個でも残れば拒否 (no-TBD 自己検査)。
#
# usage: inject-prose.sh <manifest.yaml> <assembled.html> [out.html]

set -euo pipefail
# patsub_replacement (bash 5.2+ 既定 ON) は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true

MANIFEST="${1:?usage: inject-prose.sh <manifest.yaml> <assembled.html> [out.html]}"
HTML="${2:?usage: inject-prose.sh <manifest.yaml> <assembled.html> [out.html]}"
OUT="${3:-/dev/stdout}"
[[ -f "$MANIFEST" && -f "$HTML" ]] || { echo "inject: input not found" >&2; exit 1; }
command -v yq >/dev/null || { echo "inject: yq required" >&2; exit 1; }
command -v perl >/dev/null || { echo "inject: perl required" >&2; exit 1; }

esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

MAP="$(mktemp)"; TMP="$(mktemp)"; trap 'rm -f "$MAP" "$TMP"' EXIT

# 1. HTML 側スロット id 集合 / manifest 側 key 集合
mapfile -t HTML_IDS < <(grep -oE 'data-slot-id="[^"]+"' "$HTML" | sed 's/.*data-slot-id="//; s/"$//' | sort -u)
mapfile -t MAN_KEYS < <(yq -r '.slots | keys | .[]' "$MANIFEST" | sort -u)

# 2. 集合一致 (脱落=未充填 / orphan=HTML に無い manifest を両方 fail-closed)
miss="$(comm -23 <(printf '%s\n' "${HTML_IDS[@]}") <(printf '%s\n' "${MAN_KEYS[@]}"))"
extra="$(comm -13 <(printf '%s\n' "${HTML_IDS[@]}") <(printf '%s\n' "${MAN_KEYS[@]}"))"
[[ -z "$miss"  ]] || { echo "inject: manifest に無いスロット (未充填になる): $(echo $miss)" >&2; exit 1; }
[[ -z "$extra" ]] || { echo "inject: HTML に対応スロットの無い manifest エントリ (orphan): $(echo $extra)" >&2; exit 1; }

# 3. 値を validate (tab/改行/空を拒否) し、 escape 済み id<TAB>prose map を構築
for key in "${MAN_KEYS[@]}"; do
  val="$(key="$key" yq -r '.slots[strenv(key)]' "$MANIFEST")"
  [[ -n "$val" && "$val" != "null" ]] || { echo "inject: 空 prose: $key" >&2; exit 1; }
  case "$val" in *$'\t'*|*$'\n'*) echo "inject: prose に tab/改行: $key" >&2; exit 1 ;; esac
  printf '%s\t%s\n' "$key" "$(esc "$val")" >> "$MAP"
done

# 4. perl で各空スロットへ escape 済み prose を注入 (data-slot-id でターゲット、 空要素のみ match)
#    注意: -0777 は $/ を slurp に固定する。 map 読みは local $/ + lexical 変数で行う
#    (素の while(<$fh>) は $_ = HTML 本体を破壊し出力が空になる)。
MAPFILE="$MAP" perl -0777 -ne '
  my %m;
  {
    local $/ = "\n";
    open(my $fh, "<", $ENV{MAPFILE}) or die "inject: map open 失敗: $!\n";
    while (my $line = <$fh>) { chomp $line; next unless length $line; my ($k,$v) = split(/\t/, $line, 2); $m{$k} = $v; }
    close($fh);
  }
  s{<(\w+)\b([^>]*\bdata-slot-id="([^"]+)"[^>]*)></\1>}{
    exists $m{$3} ? "<$1$2>$m{$3}</$1>" : die "inject: prose 不在: $3\n"
  }ge;
  print;
' "$HTML" > "$TMP"

# 5. footer 検証状態トークンを決定的に更新 (充填済を反映)。 両状態を許容し、 どちらも無ければ drift として拒否。
#    注意: 置換文字列の ✓ → は \x{} エスケープでなくリテラル UTF-8 バイトで書く。 perl を byte (Latin-1)
#    モードで走らせ、 同一行の日本語バイトの二重エンコード (wide character 化) を避ける。
if grep -qF 'prose 未充填 (opus 待ち)' "$TMP"; then
  perl -i -pe 's/prose 未充填 \(opus 待ち\)/prose ✓ 充填済 (fidelity ceiling → S5 対象)/g' "$TMP"
elif ! grep -qF 'prose ✓ 充填済' "$TMP"; then
  echo "inject: footer 検証状態トークンが見つからない (assembler drift?)" >&2; exit 1
fi

# 6. self-check: 充填後に空 prose スロットが残っていないか (no-TBD)
remain="$(perl -0777 -ne 'my $c=0; while (/<(\w+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ unless length($i); } print $c;' "$TMP")"
[[ "$remain" == "0" ]] || { echo "inject: 充填後も空スロットが $remain 個残存 (no-TBD 違反)" >&2; exit 1; }

if [[ "$OUT" == "/dev/stdout" ]]; then cat "$TMP"; else mv "$TMP" "$OUT"; echo "inject: wrote $OUT" >&2; fi
