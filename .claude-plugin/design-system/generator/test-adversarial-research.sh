#!/usr/bin/env bash
# folio engine B3 (folio-ar1) — research-pack 敵対回帰テスト (instance#3)
#
# research-pack の fail-closed gate (assemble-research validate abort / verify-research FAIL / inject abort) が
# 構造捏造・★cross-doc 前方照会の dangling/改竄・prose 改竄・term-inline 改竄を捕捉することを回帰確認する。
# ADR-pack の test-adversarial-adr.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
#
# usage: test-adversarial-research.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-research.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-research.sh"
BASE="$SCRIPT_DIR/contract/clinic-double-booking.research.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/clinic-double-booking.research.prose.yaml"
ADR="$SCRIPT_DIR/contract/clinic-double-booking.adr.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# ★cross_doc 解決は contract dir 相対。 mutated research contract を $TMP に置くため、 照会先 ADR contract も
#   同名で $TMP へ複製する (これをしないと全 abort が「ADR 不在」で起き、 意図した理由を検証できない
#   false-pass になる = S4 の A1 否定検証 false-pass / ADR-pack の同型対策)。
cp "$ADR" "$TMP/clinic-double-booking.adr.yaml"
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

# expect_abort: assemble-research が exit!=0 で abort し、 かつ stderr に想定理由 ($3) を含むことを要求
# (理由検証で「別原因の誤 abort」= false-pass を弾く)。 mutated contract は $TMP に置く。
expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
expect_verify_fail_filled() { if bash "$VER" --filled "$2" "$3" "$4" >/dev/null 2>&1; then ng "$1 (--filled verify が PASS した)"; else ok "$1"; fi; }
expect_verify_pass() { if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi; }
expect_inject_abort() { if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi; }

# 健全 baseline を一度生成 (HTML 改竄系の元)
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }

echo "research-pack adversarial regression (fail-closed expected):"

# === assemble-research validate (生成前 fail-closed) ===

# R1. ★cross-doc 前方照会 dangling: leads_to を ADR に無い OPT99 に → abort
cp "$BASE" "$TMP/r1.yaml"; yq -i '.approaches[0].leads_to = "OPT99"' "$TMP/r1.yaml"
expect_abort "R1 ★cross-doc 前方照会 dangling (ADR に無い option) を生成前 abort" "$TMP/r1.yaml" "dangling"

# R2. ★cross_doc.adr_doc_id 不一致 → abort
cp "$BASE" "$TMP/r2.yaml"; yq -i '.cross_doc.adr_doc_id = "ADR-WRONG"' "$TMP/r2.yaml"
expect_abort "R2 ★cross_doc.adr_doc_id 不一致を abort" "$TMP/r2.yaml" "adr_doc_id"

# R3. ★cross-doc 照会先 contract 不在 → abort
cp "$BASE" "$TMP/r3.yaml"; yq -i '.cross_doc.adr_contract = "nonexistent.adr.yaml"' "$TMP/r3.yaml"
expect_abort "R3 ★照会先 ADR contract 不在を abort" "$TMP/r3.yaml" "見つからない"

# R4. 未知の照会 role (抽象 allowlist 外) → abort
cp "$BASE" "$TMP/r4.yaml"; yq -i '.approaches[0].role = "wild-role"' "$TMP/r4.yaml"
expect_abort "R4 未知の照会 role を abort" "$TMP/r4.yaml" "未知の照会 role"

# R5. ★outcome.resolved_by が adr_doc_id と不一致 → abort (照会終端側の整合・research 固有)
cp "$BASE" "$TMP/r5.yaml"; yq -i '.outcome.resolved_by = "ADR-OTHER"' "$TMP/r5.yaml"
expect_abort "R5 ★outcome.resolved_by が adr_doc_id と不一致を abort" "$TMP/r5.yaml" "resolved_by"

# R6. 未知の research_status → abort
cp "$BASE" "$TMP/r6.yaml"; yq -i '.meta.research_status = "vibes"' "$TMP/r6.yaml"
expect_abort "R6 未知の research_status を abort" "$TMP/r6.yaml" "未知の research_status"

# R7. approach id 重複 → abort
cp "$BASE" "$TMP/r7.yaml"; yq -i '.approaches[1].id = "AP1"' "$TMP/r7.yaml"
expect_abort "R7 approach id 重複を abort" "$TMP/r7.yaml" "approach id 重複"

# R8. finding id 重複 → abort
cp "$BASE" "$TMP/r8.yaml"; yq -i '.findings[1].id = "FND1"' "$TMP/r8.yaml"
expect_abort "R8 finding id 重複を abort" "$TMP/r8.yaml" "finding id 重複"

# R9. open-question id 重複 → abort
cp "$BASE" "$TMP/r9.yaml"; yq -i '.open_questions[1].id = "OQ1"' "$TMP/r9.yaml"
expect_abort "R9 open-question id 重複を abort" "$TMP/r9.yaml" "open-question id 重複"

# R10. 値に改行 (@tsv 列ずれの源) → abort
cp "$BASE" "$TMP/r10.yaml"; yq -i '.findings[0].detail = "line1" + "\n" + "line2"' "$TMP/r10.yaml"
expect_abort "R10 改行を含む値を abort" "$TMP/r10.yaml" "tab/改行"

# R11. glossary 部分文字列ペア (term-inline ネスト span) → abort
cp "$BASE" "$TMP/r11.yaml"; yq -i '.glossary += [{"term":"ロック","en":"lock","plain_short":"錠","def":"錠の説明。"}]' "$TMP/r11.yaml"
expect_abort "R11 glossary 部分文字列ペア (ロック ⊂ 楽観ロック) を abort" "$TMP/r11.yaml" "部分文字列"

# === HTML 改竄 (生成後 fail-closed = verify-research) ===

# R12. HTML に偽 data-leads-to を注入 → verify set/count/dangling 不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/r12.html"
perl -0777 -i -pe 's#(<p class="oc-tgt")#<span data-component="cross-doc-leads-chip" data-ap-id="APX" data-leads-to="OPT99" data-leads-role="exploration">x <b>OPT99</b></span>$1#' "$TMP/r12.html"
expect_verify_fail_filled "R12 ★HTML への偽 leads-to 注入を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/r12.html"

# R13. approach card を 1 枚削除 → 行数不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/r13.html"
perl -0777 -i -pe 's#<div data-component="research-approach-card">.*?<p class="ap-assess">.*?</p>\s*</div>##s' "$TMP/r13.html"
expect_verify_fail_filled "R13 approach card 削除を行数 gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/r13.html"

# R14. prose スロットの内容を改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/r14.html"
perl -0777 -i -pe 's#(data-slot-id="outcome-plain">)[^<]*#${1}改竄された散文#' "$TMP/r14.html"
expect_verify_fail_filled "R14 prose 改竄 (注入忠実) を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/r14.html"

# R15. term-inline の併記を誤った plain_short へ改竄 → fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/r15.html"
perl -0777 -i -pe 's#(data-term="ダブルブッキング">)[^<]*#${1}でたらめ#' "$TMP/r15.html"
expect_verify_fail_filled "R15 term-inline 併記改竄を fidelity が捕捉" "$BASE_PROSE" "$BASE" "$TMP/r15.html"

# R16. ★照会 role を allowlist 内の別 role へ改竄 (exploration→claim) → (leads_to,role) ペア不一致 FAIL
#      (allowlist 内別 role への偽装は role allowlist だけでは素通り = fail-open。 ペア集合突合で捕捉する)。
cp "$TMP/base-filled.html" "$TMP/r16.html"
perl -0777 -i -pe 's#(data-ap-id="AP1" data-leads-to="OPT1" data-leads-role=)"exploration"#${1}"claim"#' "$TMP/r16.html"
expect_verify_fail_filled "R16 ★照会 role を allowlist 内別 role へ改竄を (leads_to,role) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/r16.html"

# R17. ★方式→option edge の付け替え (AP1↔AP2 の leads_to を入替・attr/可視とも整合維持) → (ap-id,leads_to) ペア FAIL
#      (leads_to 集合・count・role は不変 = fail-open。 id↔leads_to ペア突合だけが捕捉する)。
cp "$TMP/base-filled.html" "$TMP/r17.html"
perl -0777 -i -pe 's#(data-ap-id="AP1" data-leads-to=)"OPT1"([^>]*>[^<]*<b>)OPT1(</b>)#${1}"OPT2"${2}OPT2${3}#' "$TMP/r17.html"
perl -0777 -i -pe 's#(data-ap-id="AP2" data-leads-to=)"OPT2"([^>]*>[^<]*<b>)OPT2(</b>)#${1}"OPT1"${2}OPT1${3}#' "$TMP/r17.html"
expect_verify_fail_filled "R17 ★方式→option edge 付け替え (集合不変) を (ap-id,leads_to) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/r17.html"

# R18. ★既存 leads chip を重複注入 (leads_to 集合は不変) → count anchor で FAIL
#      (set_eq は sort -u で重複を潰すため集合不変=fail-open。 count chk とペアで二重照会を捕捉)。
cp "$TMP/base-filled.html" "$TMP/r18.html"
perl -0777 -i -pe 's#(<span data-component="cross-doc-leads-chip" data-ap-id="AP1".*?</span>)#$1$1#s' "$TMP/r18.html"
expect_verify_fail_filled "R18 ★既存 leads chip の重複注入 (集合不変) を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r18.html"

# R19. ★outcome resolved-by を改竄 → outcome 整合 FAIL (照会終端 identity の偽装)
cp "$TMP/base-filled.html" "$TMP/r19.html"
perl -0777 -i -pe 's#(data-resolved-by=)"ADR-CLINIC-0001"#${1}"ADR-FORGED"#' "$TMP/r19.html"
expect_verify_fail_filled "R19 ★outcome resolved-by 改竄を捕捉" "$BASE_PROSE" "$BASE" "$TMP/r19.html"

# R24. ★チップ可視 <b>OPTx</b> のみ改竄 (attr data-leads-to は正) → 可視 id 整合で FAIL
#      (非エンジニアが読むのは attr でなく可視文字。 attr 突合だけでは fail-open = ADR の verdict 可視ラベルと対称)。
cp "$TMP/base-filled.html" "$TMP/r24.html"
perl -0777 -i -pe 's#(data-leads-to="OPT1"[^>]*>[^<]*<b>)OPT1(</b>)#${1}OPT2${2}#' "$TMP/r24.html"
expect_verify_fail_filled "R24 ★チップ可視 id のみ改竄 (attr は正) を vis 整合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r24.html"

# R25. ★チップから <b> 要素ごと削除し可視を平文の偽 id へ書換 (attr data-leads-to は正) → 可視 id 整合で FAIL
#      (R24 は <b> を保持したまま中身だけ変える経路のみ。 本ケースは <b> 欠落経路 = <b> マッチ前提の抽出だと
#      突合対象から外れ黙って素通る fail-open を回帰固定する。 NO-B 検出 + 可視 <b> 本数 count anchor の両方で捕捉)。
cp "$TMP/base-filled.html" "$TMP/r25.html"
perl -0777 -i -pe 's#(data-ap-id="AP1" data-leads-to="OPT1"[^>]*>)[^<]*<b>OPT1</b>#${1}つながる判断 OPT_FAKE#' "$TMP/r25.html"
expect_verify_fail_filled "R25 ★チップ <b> 欠落 + 可視平文偽 id (attr は正) を vis 整合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r25.html"

# === inject fail-closed ===

# R20. manifest から 1 スロットを削除 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/r20.prose.yaml"; yq -i 'del(.slots.["outcome-plain"])' "$TMP/r20.prose.yaml"
expect_inject_abort "R20 manifest 欠落スロットを inject が abort" "$TMP/r20.prose.yaml" "$TMP/base.html"

# R21. manifest に orphan キー追加 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/r21.prose.yaml"; yq -i '.slots.["ghost-slot"] = "幽霊"' "$TMP/r21.prose.yaml"
expect_inject_abort "R21 manifest orphan キーを inject が abort" "$TMP/r21.prose.yaml" "$TMP/base.html"

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_verify_pass "R22 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"

# R23. HTML 注入の escape 健全性 (生 markup が構造へ漏れない)
cp "$BASE" "$TMP/r23.yaml"; yq -i '.outcome.note = "<script>alert(1)</script>決着した"' "$TMP/r23.yaml"
bash "$ASM" "$TMP/r23.yaml" "$TMP/r23.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/r23.html"; then ng "R23 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/r23.html"; then ok "R23 HTML 注入を正規 entity に escape"
else ng "R23 正規 entity &lt;script&gt; が出ていない"; fi

echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
