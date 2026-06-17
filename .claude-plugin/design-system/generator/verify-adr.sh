#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack fabrication-free + cross-doc 照会 proof (instance#2)
#
# 生成 ADR HTML の *構造* が入力 ADR contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS-pack) と同型の規律を ADR-pack schema へ適用:
#   - 行数 (context / drivers / options / consequences pos+neg / glossary / approval) が contract 要素数と一致。
#   - id 一意性 (context / drivers / options / consequences)。
#   - ★cross-doc 照会 (本 pack の核): decision.justifies の要件集合が
#       (a) HTML の data-justifies-req 集合と *集合一致* (捏造 0 + 脱落 0)、
#       (b) 参照先 SRS contract の要件 ID に *実在* (dangling 照会 0)、
#       (c) cross_doc.srs_doc_id == SRS contract .meta.doc_id、
#       (d) data-justifies-role が抽象ロール allowlist 内 (claim/rationale/exploration/principle/verification/implementation)。
#   - verdict 整合 (chosen ちょうど 1 + decision.chosen 一致)。
#   - escape 健全性 (<lt; 等の化け 0 / >null< 漏れ 0)。
#   - prose スロット: 既定=全空 (pre-fill) / --filled <manifest>=全充填 + 注入忠実 / --artifact=全充填のみ。
#   - term-inline (plain-language-term-inline) の fidelity + 用語被覆 (assemble-adr と同一語境界規律)。
#
# usage: verify-adr.sh [--filled <manifest.yaml> | --artifact] <adr-contract.yaml> <generated.html>
# exit:  0 = PASS / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-adr: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-adr: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-adr: yq required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
sed '/<style>/,/<\/style>/d' "$HTML" > "$BODY"      # body-only (inline CSS の data-component 混入回避)

q() { yq -r "$1" "$CONTRACT"; }
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }
fail=0
chk() { if [[ "$2" == "$3" ]]; then printf '  [OK]   %-48s %s\n' "$1" "$2"; else printf '  [FAIL] %-48s expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi; }
chk_empty() { if [[ -z "$2" ]]; then printf '  [OK]   %-48s\n' "$1"; else printf '  [FAIL] %-48s 重複: %s\n' "$1" "$2"; fail=1; fi; }
set_eq() {
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-48s %s\n' "$1" "識別"
  else
    printf '  [FAIL] %-48s\n' "$1"
    echo "    --- contract のみ (脱落) ---"; comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    echo "    --- HTML のみ (捏造) ---";     comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    fail=1
  fi
}

echo "ADR-pack fabrication-free + cross-doc 照会 proof: $HTML"
echo "  contract: $CONTRACT"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "context rows == |context|"           "$(q '.context | length')"                 "$(grep -c 'data-component="adr-context-row"' "$BODY")"
chk "driver rows == |drivers|"            "$(q '.drivers | length')"                 "$(grep -c 'data-component="adr-driver-row"' "$BODY")"
chk "option cards == |options|"          "$(q '.options | length')"                 "$(grep -c 'data-component="adr-option-card"' "$BODY")"
chk "consequence(pos) == |positive|"     "$(q '.consequences.positive | length')"   "$(grep -c 'data-component="adr-consequence-pos"' "$BODY")"
chk "consequence(neg) == |negative|"     "$(q '.consequences.negative | length')"   "$(grep -c 'data-component="adr-consequence-neg"' "$BODY")"
chk "glossary == |glossary|"             "$(q '.glossary | length')"                "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"             "$(q '.approval | length')"                "$(grep -c 'class="sign"' "$BODY")"

# 2. id 一意性
chk_empty "context id 一意"     "$(q '.context[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "driver id 一意"      "$(q '.drivers[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "option id 一意"      "$(q '.options[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "consequence id 一意" "$(q '(.consequences.positive + .consequences.negative)[].id' | sort | uniq -d | tr '\n' ' ')"

# 3. ★cross-doc 照会 (本 pack の核)
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
if [[ ! -f "$SRS_ABS" ]]; then
  printf '  [FAIL] %-48s 参照先 SRS contract 不在: %s\n' "cross-doc: 照会先 SRS contract 実在" "$SRS_REL"; fail=1
else
  printf '  [OK]   %-48s %s\n' "cross-doc: 照会先 SRS contract 実在" "${SRS_REL}"
  # (c) doc_id 一致
  chk "cross-doc: srs_doc_id == SRS .meta.doc_id" "$(yq -r '.meta.doc_id' "$SRS_ABS")" "$(q '.cross_doc.srs_doc_id')"
  # (a) decision.justifies の req 集合 == HTML data-justifies-req 集合
  exp_j="$(q '.decision.justifies[].req' | sort -u)"
  act_j="$(grep -oE 'data-justifies-req="[^"]+"' "$BODY" | sed 's/.*data-justifies-req="//; s/"$//' | sort -u)"
  set_eq "cross-doc: justifies req SET (contract == HTML)" "$exp_j" "$act_j"
  # (b) ★dangling 照会 0: justifies の req が参照先 SRS の要件 ID に実在
  dangling="$(comm -23 <(q '.decision.justifies[].req' | sort -u) <(yq -r '(.requirements[].id, .nfr[].id)' "$SRS_ABS" | sort -u))"
  chk_empty "cross-doc: dangling 照会 (SRS に無い req)" "$(printf '%s' "$dangling" | tr '\n' ' ' | sed 's/ *$//')"
  # (d) role allowlist (HTML 側 data-justifies-role)
  badrole="$(grep -oE 'data-justifies-role="[^"]+"' "$BODY" | sed 's/.*data-justifies-role="//; s/"$//' | sort -u \
    | grep -vxE 'claim|rationale|exploration|principle|verification|implementation' | tr '\n' ' ')"
  chk_empty "cross-doc: 照会 role が抽象 allowlist 内" "$badrole"
fi

# 4. verdict 整合 (chosen ちょうど 1 + decision.chosen 一致)
chk "verdict=chosen はちょうど 1 件" "1" "$(q '[.options[] | select(.verdict=="chosen")] | length')"
chk "decision.chosen == verdict=chosen option" "$(q '[.options[] | select(.verdict=="chosen")][0].id // "MISSING"')" "$(q '.decision.chosen')"
# HTML 側: opt-verdict.chosen の数 (可視 verdict 捏造検出)
chk "HTML chosen バッジ == 1" "1" "$(grep -oE 'class="opt-verdict chosen"' "$BODY" | wc -l | tr -d ' ')"

# 5. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 6. prose スロット (perl で要素単位判定)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-48s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-48s\n' "prose スロットが無い"; fail=1; fi

if [[ -n "$ARTIFACT" ]]; then
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
elif [[ -z "$FILLED_MANIFEST" ]]; then
  chk "prose スロットは全て空 (pre-fill, filled=0)" "0" "$filled"
else
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  exp="$(mktemp)"; act="$(mktemp)"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    printf '%s\t%s\n' "$key" "$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST") | sort > "$exp"
  perl -0777 -ne 'while (/<([a-zA-Z]+)\b[^>]*\bdata-slot-id="([^"]+)"[^>]*>(.*?)<\/\1>/gs){ print "$2\t$3\n"; }' "$BODY" | sort > "$act"
  if diff -q "$exp" "$act" >/dev/null 2>&1; then
    printf '  [OK]   %-48s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-48s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# 7. plain-language-term-inline fidelity + 用語被覆 (assemble-adr と同一語境界規律)
declare -A GPLAIN GALL GASCII
while IFS=$'\t' read -r gterm gplain; do
  [[ -n "$gterm" ]] || continue
  [[ -n "$gplain" && "$gplain" != "null" ]] || gplain="$gterm"
  gte="$(esc "$gterm")"; GALL[$gte]=1; GPLAIN[$gte]="$(esc "$gplain")"
  a=1; case "$gterm" in *[!\ -~]*) a=0 ;; esac; GASCII[$gte]="$a"
done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')
mapfile -t MARKS < <(grep -oE '<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>' "$BODY")
tfail=0; declare -A TSEEN
for m in "${MARKS[@]}"; do
  dt="$(printf '%s' "$m" | sed -E 's/.*data-term="([^"]*)".*/\1/')"
  ct="$(printf '%s' "$m" | sed -E 's#.*">([^<]*)</span>#\1#')"
  [[ -n "${GALL[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が glossary に無い (捏造)"; tfail=1; fail=1; }
  [[ -z "${GALL[$dt]:-}" || "$ct" == "${GPLAIN[$dt]}" ]] || { echo "  [FAIL] term-inline '$dt' 併記が plain_short と不一致 (期待 '${GPLAIN[$dt]}' 実 '$ct')"; tfail=1; fail=1; }
  [[ -z "${TSEEN[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が重複マーク"; tfail=1; fail=1; }
  TSEEN[$dt]=1
done
[[ "$tfail" -eq 0 ]] && printf '  [OK]   %-48s %s\n' "term-inline 派生・一意 (data-term∈glossary・併記==plain_short)" "${#MARKS[@]}"
# 用語被覆: マーク集合 == markable フィールド出現 glossary 語 (assemble-adr の mark_terms 適用先と二重保守)。
MKF="$(mktemp)"; GF2="$(mktemp)"
esc "$(q '.context[].summary, .context[].detail, .drivers[].driver, .options[].name, .options[].summary, .options[].pros[], .options[].cons[], .decision.statement, .decision.justifies[].note, .consequences.positive[].text, .consequences.negative[].text, .supersession.note, .principle.text, .principle.note')" > "$MKF"
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
set_eq "term-inline 被覆 (マーク == markable 出現 glossary 語)" "$exp_marks" "$act_marks"

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + cross-doc 照会解決 + term-inline + prose 全充填)"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実)"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空)"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
