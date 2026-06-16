#!/usr/bin/env bash
# folio S4 generator — fabrication-free proof (ADR-0042 §2.1 / §3)
#
# 生成 HTML の *構造* が入力 contract から完全に導出されたことを機械検証する:
#   - 行数 (要件 / NFR / 出所) が contract の要素数と一致 (data-component 行マーカーで table-scoped に数える)。
#   - id 一意性 (要件+NFR / ニーズ / 受入)。
#   - RTM の backward (●) リンク集合・acceptance (受入) リンク集合が、 それぞれ contract の
#     trace.backward / trace.acceptance と *集合として一致* (捏造 0 + 脱落 0、 両軸対称)。
#   - 決定的サマリの数値 (要件/ニーズ/リンク/孤立/未検証) を contract から *独立再計算* して HTML と突合
#     (assembler のロジックバグ・後段改竄も捕捉)。
#   - prose スロット (既定 = pre-fill): 存在しかつ全て空 (perl で要素単位判定 = ネストタグ/改行始まりも捕捉)。
#   - prose スロット (--filled <manifest> = post-fill): 全て非空 (no-TBD) かつ各 data-slot-id の内容が
#     escape 済み manifest 値と完全一致 (注入忠実 = opus 散文の改竄・out-of-band 注入・脱落を捕捉)。
#     構造チェック (1-7d) は両モードで不変 (注入は prose のみ充填し構造を触らない)。
#
# usage: verify-fabrication-free.sh [--filled <manifest.yaml>] <contract.yaml> <generated.html>

set -uo pipefail
# esc() の ${v//pat/repl} を bash 5.2+ patsub_replacement が壊す (< → <lt;) ため無効化。
shopt -u patsub_replacement 2>/dev/null || true

FILLED_MANIFEST=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2; fi
CONTRACT="${1:?usage: verify-fabrication-free.sh [--filled <manifest>] <contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-fabrication-free.sh [--filled <manifest>] <contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、
# <style> ブロックを除去した body-only ビューで数える (S5 floor gate も同じ前提が要る)。
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
sed '/<style>/,/<\/style>/d' "$HTML" > "$BODY"

q() { yq -r "$1" "$CONTRACT"; }
# assemble.sh / inject-prose.sh と同一の escape 規律 (注入忠実比較に使う)。
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }
fail=0
chk() { # label expected actual
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-44s %s\n' "$1" "$2"
  else printf '  [FAIL] %-44s expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}
chk_empty() { # label value(空であるべき)
  if [[ -z "$2" ]]; then printf '  [OK]   %-44s\n' "$1"
  else printf '  [FAIL] %-44s 重複: %s\n' "$1" "$2"; fail=1; fi
}
set_eq() { # label expected-multiline actual-multiline
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-44s %s\n' "$1" "識別"
  else
    printf '  [FAIL] %-44s\n' "$1"
    echo "    --- contract のみ (脱落) ---"; comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    echo "    --- HTML のみ (捏造) ---";     comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    fail=1
  fi
}

echo "fabrication-free proof: $HTML"
echo "  contract: $CONTRACT"

# 1-3. 行数 (data-component 行マーカーで table-scoped、 id 命名非依存)
chk "requirement rows == |requirements|" "$(q '.requirements | length')"  "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "nfr rows == |nfr|"                  "$(q '.nfr | length')"          "$(grep -c 'data-component="nfr-metric-row"' "$BODY")"
chk "origin rows == |upper_needs|"       "$(q '.upper_needs | length')"  "$(grep -c 'data-component="source-trace-row"' "$BODY")"

# 4. id 一意性 (ADR-0042 §2.1 の不変条件)
chk_empty "要件/NFR id 一意" "$(q '(.requirements[].id, .nfr[].id)' | sort | uniq -d | tr '\n' ' ')"
chk_empty "ニーズ id 一意"   "$(q '.upper_needs[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "受入 id 一意"     "$(q '.acceptance[].id' | sort | uniq -d | tr '\n' ' ')"

# 5. backward (●) リンク集合 == contract (要件ごと unique = assembler の 1 セル意味論に一致)
exp_b="$(q '(.requirements + .nfr)[] | .id as $i | (.trace.backward | unique)[] | $i + "__" + .' | sort)"
act_b="$(grep -oE 'data-trace-link="[^"]+"' "$BODY" | sed 's/.*data-trace-link="//; s/"$//' | sort)"
chk     "backward link count == Σ unique backward" "$(printf '%s\n' "$exp_b" | grep -c .)" "$(printf '%s\n' "$act_b" | grep -c .)"
set_eq  "backward link SET == contract" "$exp_b" "$act_b"

# 6. acceptance (受入) リンク集合 == contract (backward と対称)
exp_a="$(q '(.requirements + .nfr)[] | .id as $i | (.trace.acceptance | unique)[] | $i + "__" + .' | sort)"
act_a="$(grep -oE 'data-acc-link="[^"]+"' "$BODY" | sed 's/.*data-acc-link="//; s/"$//' | sort)"
chk     "acceptance link count == Σ unique acceptance" "$(printf '%s\n' "$exp_a" | grep -c .)" "$(printf '%s\n' "$act_a" | grep -c .)"
set_eq  "acceptance link SET == contract" "$exp_a" "$act_a"

# 7. 決定的サマリ数値を contract から独立再計算して HTML の data-derived と突合
declare -A D
while IFS='=' read -r k v; do [[ -n "$k" ]] && D[$k]="$v"; done \
  < <(grep -oE 'data-derived="[^"]+"' "$BODY" | sed 's/.*data-derived="//; s/"$//' | tr ';' '\n')
chk "summary req == |req+nfr|"          "$(q '(.requirements + .nfr) | length')"                                             "${D[req]:-MISSING}"
chk "summary need == |upper_needs|"     "$(q '.upper_needs | length')"                                                       "${D[need]:-MISSING}"
chk "summary link == Σ backward"        "$(q '[(.requirements + .nfr)[].trace.backward[]] | length')"                        "${D[link]:-MISSING}"
chk "summary iso == 出所なし要件数"     "$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')" "${D[iso]:-MISSING}"
chk "summary unv == 受入なし要件数"     "$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')" "${D[unv]:-MISSING}"

# 7b. 内容部品の行数 (contract 要素数と一致 = 捏造/脱落なし、 全て独立した行マーカーで table-scoped)
chk "goals == |goals|"             "$(q '.goals | length')"                               "$(grep -c 'class="card accent"' "$BODY")"
chk "scope items == |in|+|out|"    "$(q '(.scope.in | length) + (.scope.out | length)')"  "$(grep -c 'class="b">' "$BODY")"
chk "actors == |actors|"           "$(q '.actors | length')"                              "$(grep -c 'class="actor"' "$BODY")"
chk "acceptance == |acceptance|"   "$(q '.acceptance | length')"                          "$(grep -c 'class="aid"' "$BODY")"
chk "nfr-hero == |nfr(hero)|"      "$(q '[.nfr[] | select(.hero)] | length')"             "$(grep -c 'class="nfr-hero ' "$BODY")"
chk "constraints == |constraints|" "$(q '.constraints | length')"                         "$(grep -c 'class="cid2"' "$BODY")"
chk "glossary == |glossary|"       "$(q '.glossary | length')"                            "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"       "$(q '.approval | length')"                            "$(grep -c 'class="sign"' "$BODY")"

# 7c. yq の入れ子 optional 欠落で "null" セルが人間出力へ漏れていないか
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"
# 7d. esc 破綻 (patsub back-ref 化け) で壊れた entity が出ていないか
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"

# 8. prose スロット (perl で要素単位判定 = ネストタグ/改行/空白のみを正しく捕捉)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne '
  my $c=0;
  while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs) {
    my $inner=$2; $inner =~ s/\s+//g; $c++ if length($inner);
  }
  print $c;
' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-44s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-44s\n' "prose スロットが無い"; fail=1; fi

if [[ -z "$FILLED_MANIFEST" ]]; then
  # pre-fill: assembler が prose を一切捏造しないことの証明 (全スロット空)
  chk "prose スロットは全て空 (filled=0)" "0" "$filled"
else
  # post-fill: 全スロット非空 (no-TBD) + 各 data-slot-id の内容が escape 済み manifest 値と一致 (注入忠実)
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  exp="$(mktemp)"; act="$(mktemp)"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    printf '%s\t%s\n' "$key" "$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST") | sort > "$exp"
  perl -0777 -ne 'while (/<([a-zA-Z]+)\b[^>]*\bdata-slot-id="([^"]+)"[^>]*>(.*?)<\/\1>/gs){ print "$2\t$3\n"; }' "$BODY" | sort > "$act"
  if diff -q "$exp" "$act" >/dev/null 2>&1; then
    printf '  [OK]   %-44s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-44s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ (脱落/改竄前) ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ (orphan/改竄後) ---";   comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# 9. plain-language-term-inline (glossary 派生ビュー、 ADR-0042 §2.2 A) の fidelity + 用語被覆 (両モード共通)。
#    バッジ構造: <span class="term" data-component="plain-language-term-inline" data-term="TE">PLAIN</span>
#    照合は assemble と同じ esc() 済みで行う (esc 非対称による偽 FAIL を避ける = §8 と同じ規律)。
declare -A GPLAIN GALL GASCII
while IFS=$'\t' read -r gterm gplain; do
  [[ -n "$gterm" ]] || continue
  [[ -n "$gplain" && "$gplain" != "null" ]] || gplain="$gterm"
  gte="$(esc "$gterm")"; GALL[$gte]=1; GPLAIN[$gte]="$(esc "$gplain")"
  a=1; case "$gterm" in *[!\ -~]*) a=0 ;; esac; GASCII[$gte]="$a"   # assemble と同じ ascii 判定
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')
mapfile -t MARKS < <(grep -oE '<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>' "$BODY")
tfail=0; declare -A TSEEN
for m in "${MARKS[@]}"; do
  dt="$(printf '%s' "$m" | sed -E 's/.*data-term="([^"]*)".*/\1/')"
  ct="$(printf '%s' "$m" | sed -E 's#.*">([^<]*)</span>#\1#')"
  # (a) fidelity: data-term ∈ glossary かつ 併記 == その語の plain_short
  [[ -n "${GALL[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が glossary に無い (捏造)"; tfail=1; fail=1; }
  [[ -z "${GALL[$dt]:-}" || "$ct" == "${GPLAIN[$dt]}" ]] || { echo "  [FAIL] term-inline '$dt' 併記が plain_short と不一致 (期待 '${GPLAIN[$dt]}' 実 '$ct')"; tfail=1; fail=1; }
  # (b) uniqueness: 各 data-term 1 回
  [[ -z "${TSEEN[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が重複マーク"; tfail=1; fail=1; }
  TSEEN[$dt]=1
done
[[ "$tfail" -eq 0 ]] && printf '  [OK]   %-44s %s\n' "term-inline 派生・一意 (data-term∈glossary・併記==plain_short)" "${#MARKS[@]}"
# (c) 用語被覆: マーク data-term 集合 == markable フィールドに出現する glossary 語 (assemble と *同一の語境界規律* で再導出)。
#     markable は assemble.sh の mark_terms 適用先と一致 (★この yq リストは assemble の mark_terms 呼出先と二重保守。
#     片方更新時はもう片方も合わせること = detect↔remediate parity)。 照合は ascii=英数境界 / CJK=漢字非隣接 (perl -CSD)。
MKF="$(mktemp)"; GF2="$(mktemp)"
esc "$(q '.goals[].desc, .scope.in[], .scope.out[], .actors[].role, .upper_needs[].need, .requirements[].ears.condition, .requirements[].ears.response, .nfr[].target, .nfr[].measure, .acceptance[].criterion, .constraints[].text')" > "$MKF"
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
set_eq "term-inline 被覆 (マーク == markable 出現 glossary 語、 同一語境界)" "$exp_marks" "$act_marks"

echo
if [[ -n "$FILLED_MANIFEST" ]]; then
  if [[ "$fail" -eq 0 ]]; then echo "RESULT: filled PASS (構造は contract から完全導出・捏造 0 + prose 全充填・注入忠実 = 改竄/脱落/out-of-band なし)"; exit 0
  else echo "RESULT: FAIL"; exit 1; fi
else
  if [[ "$fail" -eq 0 ]]; then echo "RESULT: fabrication-free PASS (構造は contract から完全導出・捏造 0、 backward/acceptance 両軸・派生数値・prose 空 を被覆)"; exit 0
  else echo "RESULT: FAIL"; exit 1; fi
fi
