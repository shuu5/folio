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
#   - prose スロットは存在しかつ全て空 (perl で要素単位判定 = ネストタグ/改行始まりも捕捉)。
#
# usage: verify-fabrication-free.sh <contract.yaml> <generated.html>

set -uo pipefail

CONTRACT="${1:?usage: verify-fabrication-free.sh <contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-fabrication-free.sh <contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify: input not found" >&2; exit 2; }

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、
# <style> ブロックを除去した body-only ビューで数える (S5 floor gate も同じ前提が要る)。
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
sed '/<style>/,/<\/style>/d' "$HTML" > "$BODY"

q() { yq -r "$1" "$CONTRACT"; }
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

# 8. prose スロット: 存在しかつ全て空 (perl で要素単位判定 = ネストタグ/改行/空白のみを正しく捕捉)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne '
  my $c=0;
  while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs) {
    my $inner=$2; $inner =~ s/\s+//g; $c++ if length($inner);
  }
  print $c;
' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-44s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-44s\n' "prose スロットが無い"; fail=1; fi
chk "prose スロットは全て空 (filled=0)" "0" "$filled"

echo
if [[ "$fail" -eq 0 ]]; then echo "RESULT: fabrication-free PASS (構造は contract から完全導出・捏造 0、 backward/acceptance 両軸・派生数値・prose 空 を被覆)"; exit 0
else echo "RESULT: FAIL"; exit 1; fi
