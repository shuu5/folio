#!/usr/bin/env bash
# folio engine B3 (folio-ar1) — research-pack fabrication-free + cross-doc 前方照会 proof (instance#3)
#
# 生成 research HTML の *構造* が入力 research contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS-pack) / verify-adr.sh (ADR-pack) と同型の規律を research-pack schema へ適用:
#   - 行数 (findings / approaches / open_questions / glossary / approval / 単一章ブロック) が contract 要素数と一致。
#   - id 一意性 (findings / approaches / open_questions)。
#   - ★cross-doc 前方照会 (本 pack の核): approaches[].leads_to が
#       (a) HTML の data-leads-to 集合と *集合一致* (捏造 0 + 脱落 0) + count anchor で |approaches| と一致
#           (set_eq は sort -u で重複を潰すため、 既存 edge の重複注入は count とペアにして捕捉)、
#       (b) 参照先 ADR contract の .options[].id に *実在* (dangling 照会 0)、
#       (c) cross_doc.adr_doc_id == ADR contract .meta.doc_id かつ outcome.resolved_by == cross_doc.adr_doc_id、
#       (d) data-leads-role が抽象ロール allowlist 内 (claim/rationale/exploration/principle/verification/implementation)、
#       (d') (leads_to,role) ペア集合が contract と *集合一致* (allowlist 内別 role への改竄 = 照会 graph 意味偽装を捕捉)、
#       (e') (ap-id,leads_to) ペア集合が contract と *集合一致* (どの方式がどの option へ繋がるかの edge 付け替え偽装を捕捉)。
#   - outcome 整合 (HTML data-resolved-by == contract .outcome.resolved_by)。
#   - research_status allowlist (open/concluded) の再導出。
#   - escape 健全性 (<lt; 等の化け 0 / >null< 漏れ 0)。
#   - prose スロット: 既定=全空 (pre-fill) / --filled <manifest>=全充填 + 注入忠実 / --artifact=全充填のみ。
#   - term-inline (plain-language-term-inline) の fidelity + 用語被覆 (assemble-research と同一語境界規律)。
#
# usage: verify-research.sh [--filled <manifest.yaml> | --artifact] <research-contract.yaml> <generated.html>
# exit:  0 = PASS / 1 = FAIL / 2 = tool error
#
# ★cross-doc 解決ブロック (SRS_REL/dangling/count/set_eq) は pack-local。 ADR の justifies 解決と同型 = 3 度目の重複。
#   lib/ には上げない (本 issue は core 不変が合格条件)。 core 昇格候補は bd notes へ記録 (実装は別 issue)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-research.sh [--filled <manifest> | --artifact] <research-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-research.sh [--filled <manifest> | --artifact] <research-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-research: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-research: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-research: yq required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-48s ----
# 新依存 lib/verify-common.sh を fail-closed guard する (欠落/source 失敗を false-green に倒さない)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-research: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=48; source "$LVC" || { echo "verify-research: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"      # body-only ($BODY、 inline CSS の data-component 混入回避)

echo "research-pack fabrication-free + cross-doc 前方照会 proof: $HTML"
echo "  contract: $CONTRACT"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "finding rows == |findings|"          "$(q '.findings | length')"        "$(grep -c 'data-component="research-finding-row"' "$BODY")"
chk "approach cards == |approaches|"       "$(q '.approaches | length')"      "$(grep -c 'data-component="research-approach-card"' "$BODY")"
chk "leads chips == |approaches|"          "$(q '.approaches | length')"      "$(grep -c 'data-component="cross-doc-leads-chip"' "$BODY")"
chk "open-questions == |open_questions|"   "$(q '.open_questions | length')"  "$(grep -c 'data-component="research-open-question"' "$BODY")"
chk "question panel == 1"                  "1"                                "$(grep -c 'data-component="research-question-panel"' "$BODY")"
chk "scope panel == 1"                     "1"                                "$(grep -c 'data-component="scope-summary-panel"' "$BODY")"
chk "outcome panel == 1"                   "1"                                "$(grep -c 'data-component="research-outcome-panel"' "$BODY")"
chk "glossary == |glossary|"               "$(q '.glossary | length')"        "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"               "$(q '.approval | length')"        "$(grep -c 'class="sign"' "$BODY")"

# 2. id 一意性
chk_empty "finding id 一意"        "$(q '.findings[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "approach id 一意"       "$(q '.approaches[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "open-question id 一意"  "$(q '.open_questions[].id' | sort | uniq -d | tr '\n' ' ')"
# research_status allowlist 再導出
chk_empty "research_status allowlist {open,concluded}" "$(q '.meta.research_status' | grep -vxE 'open|concluded' | tr '\n' ' ')"

# 3. ★cross-doc 前方照会 (本 pack の核 = research → ADR)
ADR_REL="$(q '.cross_doc.adr_contract')"; ADR_ABS="${CONTRACT_DIR}/${ADR_REL}"
if [[ ! -f "$ADR_ABS" ]]; then
  printf '  [FAIL] %-48s 参照先 ADR contract 不在: %s\n' "cross-doc: 照会先 ADR contract 実在" "$ADR_REL"; fail=1
else
  printf '  [OK]   %-48s %s\n' "cross-doc: 照会先 ADR contract 実在" "${ADR_REL}"
  # (c) doc_id 一致 + outcome.resolved_by == adr_doc_id (照会終端側の整合)
  chk "cross-doc: adr_doc_id == ADR .meta.doc_id" "$(yq -r '.meta.doc_id' "$ADR_ABS")" "$(q '.cross_doc.adr_doc_id')"
  chk "cross-doc: outcome.resolved_by == adr_doc_id" "$(q '.cross_doc.adr_doc_id')" "$(q '.outcome.resolved_by')"
  # (a) approaches の leads_to 集合 == HTML data-leads-to 集合 + count anchor (重複注入を count で捕捉)
  chk "cross-doc: leads count == |approaches|" "$(q '.approaches | length')" "$(grep -o 'data-leads-to=' "$BODY" | wc -l | tr -d ' ')"
  exp_l="$(q '.approaches[].leads_to' | sort -u)"
  act_l="$(grep -oE 'data-leads-to="[^"]+"' "$BODY" | sed 's/.*data-leads-to="//; s/"$//' | sort -u)"
  set_eq "cross-doc: leads_to SET (contract == HTML)" "$exp_l" "$act_l"
  # (b) ★dangling 照会 0: leads_to が参照先 ADR の option ID に実在
  dangling="$(comm -23 <(q '.approaches[].leads_to' | sort -u) <(yq -r '.options[].id' "$ADR_ABS" | sort -u))"
  chk_empty "cross-doc: dangling 照会 (ADR に無い option)" "$(printf '%s' "$dangling" | tr '\n' ' ' | sed 's/ *$//')"
  # (d) role allowlist (HTML 側 data-leads-role)
  badrole="$(grep -oE 'data-leads-role="[^"]+"' "$BODY" | sed 's/.*data-leads-role="//; s/"$//' | sort -u \
    | grep -vxE 'claim|rationale|exploration|principle|verification|implementation' | tr '\n' ' ')"
  chk_empty "cross-doc: 照会 role が抽象 allowlist 内" "$badrole"
  # (d') ★(leads_to,role) ペア一致: allowlist 内別 role への改竄 = 照会 graph の意味偽装を捕捉
  exp_lr="$(q '.approaches[] | [.leads_to, .role] | @tsv' | sort -u)"
  act_lr="$(grep -oE 'data-leads-to="[^"]+" data-leads-role="[^"]+"' "$BODY" \
    | sed -E 's/data-leads-to="([^"]+)" data-leads-role="([^"]+)"/\1\t\2/' | sort -u)"
  set_eq "cross-doc: (leads_to,role) ペア (contract == HTML)" "$exp_lr" "$act_lr"
  # (e') ★(ap-id,leads_to) ペア一致: どの方式がどの option へ繋がるかの edge 付け替え偽装を捕捉
  #      (leads_to 集合保存型の付け替え = 集合 + count では素通り = fail-open。 id↔leads_to ペア突合で捕捉)。
  exp_al="$(q '.approaches[] | [.id, .leads_to] | @tsv' | sort -u)"
  act_al="$(grep -oE 'data-ap-id="[^"]+" data-leads-to="[^"]+"' "$BODY" \
    | sed -E 's/data-ap-id="([^"]+)" data-leads-to="([^"]+)"/\1\t\2/' | sort -u)"
  set_eq "cross-doc: (ap-id,leads_to) ペア (contract == HTML)" "$exp_al" "$act_al"
  # (f') ★可視 id 整合: チップ可視 <b>OPTx</b> が data-leads-to と一致 (class/attr は正のまま可視文字だけ改竄する
  #      偽装を捕捉。 非エンジニアが読むのは attr でなく可視文字 = ADR の verdict 可視ラベル整合と対称)。
  #      ★全 chip 要素を *漏れなく* 列挙してから突合する (チップを <b> ごと削除し可視を平文の偽 id に
  #      書き換える経路 = <b> マッチ前提の抽出だと突合対象から外れ黙って素通る fail-open を塞ぐ)。
  #      <b> を欠くチップは NO-B として非空 → chk_empty で FAIL に倒す。 さらに <b>OPTx</b> の本数が
  #      |approaches| と一致することを count anchor で要求し、 <b> 欠落で本数が減る偽装を二重に捕捉する。
  lvis_bad="$(perl -CSD -0777 -ne '
    my @bad;
    while (/<span\b[^>]*\bdata-component="cross-doc-leads-chip"[^>]*>(.*?)<\/span>/gs) {
      my ($chip, $inner) = ($&, $1);
      my ($leads) = $chip =~ /\bdata-leads-to="([^"]*)"/; $leads = "" unless defined $leads;
      if ($inner =~ /<b>([^<]*)<\/b>/) { my $vis = $1; push @bad, "$leads\x{2260}$vis" if $vis ne $leads; }
      else { push @bad, "$leads:NO-B"; }
    }
    print join(" ", @bad);
  ' "$BODY")"
  chk_empty "cross-doc: チップ可視 id == data-leads-to" "$lvis_bad"
  chk "cross-doc: 可視 <b>OPTx</b> 本数 == |approaches|" "$(q '.approaches | length')" "$(grep -oE 'data-component="cross-doc-leads-chip"[^>]*>[^<]*<b>[^<]*</b>' "$BODY" | wc -l | tr -d ' ')"
fi

# 4. outcome 整合 (HTML data-resolved-by == contract .outcome.resolved_by = 終端 identity の偽装を捕捉)
act_resolved="$(grep -oE 'data-resolved-by="[^"]+"' "$BODY" | sed 's/.*data-resolved-by="//; s/"$//')"
chk "outcome: HTML resolved-by == contract" "$(esc "$(q '.outcome.resolved_by')")" "$act_resolved"

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

# 7. plain-language-term-inline fidelity + 用語被覆 (assemble-research と同一語境界規律)。
#    実装は core (verify-common.sh の verify_term_inline)。 markable フィールド集合は research-pack 固有ゆえ
#    ここで yq 式を渡す (★この yq リストは assemble-research の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.question.summary, .question.in_scope[], .question.out_scope[], .findings[].summary, .findings[].detail, .approaches[].name, .approaches[].summary, .approaches[].assessment, .open_questions[].text, .outcome.note' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + cross-doc 前方照会解決 + term-inline + prose 全充填)"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 注入忠実)"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 前方照会解決 + prose 空)"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
