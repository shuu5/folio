#!/usr/bin/env bash
# folio engine B6 (folio-8ct) — spec-pack fabrication-free + 非終端 照会 floor (instance#5 / self-dogfood)
#
# 生成 spec (rules) HTML の *構造* が入力 spec contract から完全に導出されたことを機械検証する floor gate。
# verify-fabrication-free.sh (SRS) / verify-adr.sh / verify-research.sh / verify-principle.sh と同型の規律を
# spec-pack schema (sections / requirements(EARS) / references(非終端 照会) / glossary) へ適用する:
#   - 行数 = contract 導出 (section / band / 要件 row / ref chip / block 種別ごとの件数)。
#   - 要件 fidelity: data-req-id 集合一致 + (id, ears-pattern, badge class/label, essence, statement) を emission 順で突合。
#   - section fidelity: 可視 heading 列 / essence 列が contract と順序一致。
#   - block fidelity: prose / note / list / code / table / mermaid / subhead の可視テキストを順序突合 (silent drop 検出)。
#   - ★非終端 照会 (references): chip が token/doc/role を faithfully echo (count / SET / role allowlist / (token,role) ペア / 可視 <b>==attr)。
#   - core 共通 chrome (cover-head / approval / glossary) = verify_core_chrome (folio-mk9)。 cover-meta 4 KV 再導出。
#   - escape 健全 / prose スロット (3 mode = pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)。
#
# usage: verify-spec.sh [--filled <manifest.yaml> | --artifact] <spec-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate モデル・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合。
#   prose スロット (cover-summary / chapter-lead-NN) の *内容真正性* は floor の対象外 = ceiling (fidelity-* 相当・persona-walk)。
#   floor 単独で GREEN にはならず CEILING=PENDING (taxonomy §5.1)。 spec-pack 専用 ceiling agent の制度化は follow-up (admin 起票)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-spec: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-spec: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-spec: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-spec: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_core_chrome) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-spec: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-spec: failed to source verify-common.sh" >&2; exit 2; }

# EARS pattern → class / label (assemble-spec.sh と二重保守 = detect↔remediate parity)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=恒常 [event-driven]=きっかけ [state-driven]=状態 [unwanted]=禁止 [optional]=機能 )

fail=0
make_body "$HTML"

echo "spec-pack fabrication-free + 非終端 照会 floor: $HTML"
echo "  contract: $CONTRACT"

NSEC="$(q '.sections | length')"
NREQ="$(q '.requirements | length')"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)。
#    chapter-deck-band = section 数 + 2 (references band + glossary band)。
chk "chapter-deck-band == sections + 2"   "$((NSEC + 2))"                  "$(grep -c 'data-component="chapter-deck-band"' "$BODY")"
chk "section-essence-callout == sections" "$NSEC"                          "$(grep -c 'data-component="section-essence-callout"' "$BODY")"
chk "ears-requirement-row == |requirements|" "$NREQ"                       "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "ears-badge == |requirements|"        "$NREQ"                          "$(grep -c 'data-component="ears-badge"' "$BODY")"
chk "cross-doc-ref-chip == |references|"   "$(q '.references | length')"   "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "glossary == |glossary|"              "$(q '.glossary | length')"      "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"              "$(q '.approval | length')"      "$(grep -c 'class="sign"' "$BODY")"
# block 種別ごとの件数 (silent drop / 偽 add を捕捉)。
chk "spec-prose == Σ prose blocks"        "$(q '[.sections[].blocks[]? | select(.type=="prose")] | length')"   "$(grep -c 'data-component="spec-prose"' "$BODY")"
chk "spec-note == Σ note blocks"          "$(q '[.sections[].blocks[]? | select(.type=="note")] | length')"    "$(grep -c 'data-component="spec-note"' "$BODY")"
chk "spec-list-block == Σ list blocks"    "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"    "$(grep -c 'data-component="spec-list-block"' "$BODY")"
chk "list 項目 (lbi) == Σ list items"     "$(q '[.sections[].blocks[]? | select(.type=="list") | .items[]] | length')" "$(grep -c 'class="lbi"' "$BODY")"
chk "spec-code == Σ code blocks"          "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"    "$(grep -c 'data-component="spec-code"' "$BODY")"
chk "spec-table == Σ table blocks"        "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"   "$(grep -c 'data-component="spec-table"' "$BODY")"
chk "spec-diagram == Σ mermaid blocks"    "$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')" "$(grep -c 'data-component="spec-diagram"' "$BODY")"
chk "spec-subhead == Σ subhead blocks"    "$(q '[.sections[].blocks[]? | select(.type=="subhead")] | length')" "$(grep -c 'data-component="spec-subhead"' "$BODY")"

# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# 2. id 一意性 + doc_type
chk_empty "要件 id 一意"     "$(q '.requirements[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "section id 一意"  "$(q '.sections[].id' | sort | uniq -d | tr '\n' ' ')"
chk "doc_type == rules"      "rules" "$(q '.meta.doc_type')"

# 3. section fidelity: 可視 heading 列 (先頭 NSEC 個の h2) == sections[].heading (順序) / essence 列 == sections[].essence (順序)。
exp_sh="$(q '.sections[].heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_sh="$(grep -oE '<h2>[^<]*</h2>' "$BODY" | sed -E 's#<h2>([^<]*)</h2>#\1#' | head -n "$NSEC")"
chk "section 可視 heading 列 == sections[].heading (順序)" "$exp_sh" "$act_sh"
exp_se="$(q '.sections[].essence' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_se="$(perl -CSD -0777 -ne 'while (/<div data-component="section-essence-callout"><p class="sec-se">([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
chk "section essence 列 == sections[].essence (順序)" "$exp_se" "$act_se"
# ★kicker 列 fidelity (folio-l93): band() が可視 emit する <span class="kicker"> の §N/トピック ラベルは
#   sections[].kicker 由来の *決定的フィールド* ゆえ doctrine 上 floor (heading/essence と同列の section fidelity)。
#   未突合だと §番号 swap・トピック取り違え・heading の §N との drift が全 gate (floor/persona-walk/fidelity) を素通った (17n ceiling HIGH)。
#   全 NSEC+2 band の kicker を document 順で突合: 先頭 NSEC = sections[].kicker / 末尾 2 = references・glossary band の
#   静的リテラル (assemble-spec.sh build() と二重保守 = detect↔remediate parity)。 静的 2 件も期待列へ含め band 並び替え・
#   静的ラベル drift も lock する (heading は head -n NSEC で section のみだが kicker は全 band を被覆)。
#   抽出: <span class="kicker"><svg ...>…</svg> {esc kicker}</span> の svg 後の可視テキスト ([^<]* = esc 済ゆえ安全)。
STATIC_KICKERS=("この規約が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
exp_kicker="$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_kicker="$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "section kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" "$exp_kicker" "$act_kicker"

# 4. 要件 fidelity: data-req-id 集合一致 + emission 順タプル (id, pattern, class, label, essence, statement) 突合。
exp_rid="$(q '.requirements[].id' | sort -u)"
act_rid="$(grep -oE 'data-req-id="[^"]+"' "$BODY" | sed 's/.*data-req-id="//; s/"$//' | sort -u)"
set_eq "要件 data-req-id 集合 (contract == HTML)" "$exp_rid" "$act_rid"
# emission 順 = sections→blocks(requirements).ids の document 順。
EXPF="$(mktemp)"; ACTF="$(mktemp)"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  ess="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # ★contract 由来 pattern が allowlist 外なら expected タプルを :-unknown で組まず fail-closed (assemble validate と parity)。
  # silent な class="unknown" 同士の偽一致 (双辺で同じ fallback を引いて tuple PASS する fail-open) を封鎖。
  if ! [[ -v EARS_CLASS[$pat] ]]; then echo "verify-spec: ★contract 要件 $id の EARS pattern が allowlist 外: $pat (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(esc "$id")" "$(esc "$pat")" "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$(esc "$ess")" "$(esc "$stmt")"
done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]') > "$EXPF"
perl -CSD -0777 -ne '
  while (/<div data-component="ears-requirement-row" data-req-id="([^"]*)" data-ears-pattern="([^"]*)">\s*<div class="rq-head"><span class="rid">([^<]*)<\/span><span data-component="ears-badge" class="([^"]*)">([^<]*)<\/span><\/div>\s*<p class="rq-essence">([^<]*)<\/p>\s*<details class="rq-norm"><summary>[^<]*<\/summary><p class="rq-stmt">([^<]*)<\/p><\/details>/g) {
    my ($rid,$pat,$vrid,$cls,$lab,$ess,$stmt)=($1,$2,$3,$4,$5,$6,$7);
    # 可視 rid == data-req-id (attr-vs-visible)
    if ($rid ne $vrid) { print "VIS-MISMATCH:$rid\xe2\x89\xa0$vrid\n"; next; }
    print "$rid\t$pat\t$cls\t$lab\t$ess\t$stmt\n";
  }
' "$BODY" > "$ACTF"
if diff -q "$EXPF" "$ACTF" >/dev/null 2>&1; then
  printf '  [OK]   %-'"$CHKW"'s %s\n' "要件タプル (id/pattern/class/label/essence/statement) 順序突合" "$NREQ"
else
  printf '  [FAIL] %-'"$CHKW"'s\n' "要件タプル不一致 (id/pattern/badge/essence/statement 改竄 or 順序)"
  echo "    --- contract 期待のみ ---"; comm -23 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  echo "    --- HTML 実体のみ ---";     comm -13 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  fail=1
fi
rm -f "$EXPF" "$ACTF"

# 5. block 内容 fidelity (順序突合・silent drop / 値改竄を捕捉)。 全 leaf は esc 済ゆえ [^<]* / perl で安全。
# prose
chk "prose 可視テキスト列 == prose blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="prose") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<p data-component="spec-prose">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# note
chk "note 可視テキスト列 == note blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="note") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-note"><p>([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
# list 項目
chk "list 項目列 == list blocks.items (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="list") | .items[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<li class="lbi">[^<]*</li>' "$BODY" | sed -E 's#<li class="lbi">([^<]*)</li>#\1#')"
# subhead heading + essence
chk "subhead heading 列 == subhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-subhead"><h3>([^<]*)<\/h3><p class="sub-se">([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
chk "subhead essence 列 == subhead blocks.essence (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .essence' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-subhead"><h3>[^<]*<\/h3><p class="sub-se">([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
# table caption / header / cell (全 spec-table 横断・順序)
chk "table caption 列 == table blocks.caption (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | (.caption // "")' | grep -v '^$' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<table data-component="spec-table"><caption>([^<]*)<\/caption>/g){ print "$1\n"; }' "$BODY")"
chk "table th 列 == table blocks.headers (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .headers[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<th>[^<]*</th>' "$BODY" | sed -E 's#<th>([^<]*)</th>#\1#')"
chk "table td 列 == table blocks.rows cells (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .rows[][]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<td>[^<]*</td>' "$BODY" | sed -E 's#<td>([^<]*)</td>#\1#')"
# mermaid caption + source lines
chk "mermaid figcaption 列 == mermaid blocks.caption (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | (.caption // "")' | grep -v '^$' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<figcaption>([^<]*)<\/figcaption>/g){ print "$1\n"; }' "$BODY")"
chk "mermaid source 行列 == mermaid blocks.source_lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | .source_lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre class="mermaid-src">(.*?)<\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"
# code 行 (全 spec-code 横断・順序)
chk "code 行列 == code blocks.lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="code") | .lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre data-component="spec-code"><code>(.*?)<\/code><\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"

# 6. ★非終端 照会 (references) fidelity: chip echo 厳密一致。
NREF="$(q '.references | length')"
# count anchor (data-ref-token= 出現数)
chk "references: count == |references|" "$NREF" "$(grep -o 'data-ref-token=' "$BODY" | wc -l | tr -d ' ')"
# SET 一致 (token)
set_eq "references: token SET (contract == HTML)" \
  "$(q '.references[].token' | sort -u)" \
  "$(grep -oE 'data-ref-token="[^"]+"' "$BODY" | sed 's/.*data-ref-token="//; s/"$//' | sort -u)"
# role allowlist
badrole="$(grep -oE 'data-ref-role="[^"]+"' "$BODY" | sed 's/.*data-ref-role="//; s/"$//' | sort -u | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
chk_empty "references: role が抽象 allowlist 内" "$badrole"
# (token, doc, role) タプル順序突合 (可視 doc / role / attr 全部) + 可視 <b>token</b> == attr。
chk "references: (token,doc,role) 順序突合 + 可視 <b>==attr" \
  "$(q '.references[] | [.token, .doc, .role] | @tsv' | while IFS=$'\t' read -r t d r; do printf '%s\t%s\t%s\n' "$(esc "$t")" "$(esc "$d")" "$(esc "$r")"; done)" \
  "$(perl -CSD -0777 -ne '
    while (/<div data-component="cross-doc-ref-chip" data-ref-token="([^"]*)" data-ref-role="([^"]*)"><span class="rf-token"><b>([^<]*)<\/b><\/span><span class="rf-arrow">[^<]*<\/span><span class="rf-doc">([^<]*)<\/span><span class="rf-role">([^<]*)<\/span><\/div>/g) {
      my ($tok,$role,$vtok,$doc,$vrole)=($1,$2,$3,$4,$5);
      if ($tok ne $vtok) { print "TOKEN-VIS:$tok\xe2\x89\xa0$vtok\n"; next; }
      if ($role ne $vrole) { print "ROLE-VIS:$role\xe2\x89\xa0$vrole\n"; next; }
      print "$tok\t$doc\t$role\n";
    }
  ' "$BODY")"

# 7. cover-meta 4 KV 再導出突合。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 章の数 == |sections|章"   "$NSEC 章"               "$(printf '%s\n' "$meta_kv" | grep -F '章の数' | head -1 | cut -f2)"
chk "cover-meta 規範要件 == |requirements|件" "$NREQ 件 (EARS)"      "$(printf '%s\n' "$meta_kv" | grep -F '規範要件' | head -1 | cut -f2)"
chk "cover-meta 用語 == |glossary|語"     "$(q '.glossary | length') 語" "$(printf '%s\n' "$meta_kv" | grep -F '用語' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"          "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"             "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# 8. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"                   "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 9. prose スロット (perl で要素単位判定・3 mode)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-'"$CHKW"'s\n' "prose スロットが無い"; fail=1; fi
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
    printf '  [OK]   %-'"$CHKW"'s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 要件/section/block/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
