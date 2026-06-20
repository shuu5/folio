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

# R26. ★空文字列 leads_to (comm -23 が空行を空 missing に畳む dangling fail-open の兄弟) → 生成前 abort
cp "$BASE" "$TMP/r26.yaml"; yq -i '.approaches[0].leads_to = ""' "$TMP/r26.yaml"
expect_abort "R26 ★空 leads_to (dangling fail-open 兄弟) を生成前 abort" "$TMP/r26.yaml" "空 leads_to"

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

# R27. ★outcome 可視 <b> のみ改竄 (attr data-resolved-by は正) → outcome 可視 id 整合で FAIL
#      (R19 は attr 改竄。 本ケースは attr 正・可視 <b> だけ捏造 = チップ (f')/R24 の outcome 版兄弟。
#       「この調査は <b>偽ADR</b> で決着」と文書最重要事実〔どの ADR に決着〕を偽装する経路を回帰固定)。
cp "$TMP/base-filled.html" "$TMP/r27.html"
perl -0777 -i -pe 's#(data-resolved-by="ADR-CLINIC-0001">[^<]*<b>)ADR-CLINIC-0001(</b>)#${1}ADR-FORGED-FAKE${2}#' "$TMP/r27.html"
expect_verify_fail_filled "R27 ★outcome 可視 <b> のみ改竄 (attr は正) を vis 整合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r27.html"

# R28. ★表紙 cross-doc-ref-chip 可視 <b> を改竄 → cover ref-chip 可視 id 整合で FAIL
#      (表紙=読者が最初に見るカードの「行き先」doc id 偽装。 これまで検証属性すら無い完全死角だった)。
cp "$TMP/base-filled.html" "$TMP/r28.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>)ADR-CLINIC-0001(</b>)#${1}ADR-NONSENSE${2}#s' "$TMP/r28.html"
expect_verify_fail_filled "R28 ★表紙 ref-chip 可視 id 改竄を cover 整合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r28.html"

# R29. ★oc-tgt 照会先 footnote の可視 <b> id を偽 id へ改竄 (assemble で <b> 包みに統一済) → echo 整合で FAIL
cp "$TMP/base-filled.html" "$TMP/r29.html"
perl -0777 -i -pe 's#(class="oc-tgt"[^>]*>照会先 \(前方参照\): <b>)ADR-CLINIC-0001(</b>)#${1}ADR-PHANTOM${2}#' "$TMP/r29.html"
expect_verify_fail_filled "R29 ★oc-tgt 可視 <b> id 改竄を echo 整合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r29.html"

# R30. ★round-2 ceiling: 正規 <b> の直後に 2 つ目の偽 <b> を *追加* (outcome) → 全<b>列挙 MULTI-B で FAIL
#      (first-<b> マッチ版は「この調査は ADR-CLINIC-0001 (実は ADR-FORGED)」が読者に見えるのに素通った fail-open)。
cp "$TMP/base-filled.html" "$TMP/r30.html"
perl -0777 -i -pe 's#(class="oc-resolved"[^>]*>[^<]*<b>ADR-CLINIC-0001</b>)#${1} (実は <b>ADR-FORGED</b>)#' "$TMP/r30.html"
expect_verify_fail_filled "R30 ★outcome 第2 <b> 追加 (追加方向) を全<b>列挙で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r30.html"

# R31. ★チップに第2 <b> を追加 (leads) → 全<b>列挙 MULTI-B で FAIL
cp "$TMP/base-filled.html" "$TMP/r31.html"
perl -0777 -i -pe 's#(data-ap-id="AP1" data-leads-to="OPT1"[^>]*>[^<]*<b>OPT1</b>)#${1}<b>OPT9</b>#' "$TMP/r31.html"
expect_verify_fail_filled "R31 ★チップ第2 <b> 追加 (追加方向) を全<b>列挙で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r31.html"

# R32. ★表紙 ref-chip に第2 <b> を追加 → 全<b>列挙 MULTI-B で FAIL
cp "$TMP/base-filled.html" "$TMP/r32.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>ADR-CLINIC-0001</b>)#${1} <b>ADR-FAKE</b>#s' "$TMP/r32.html"
expect_verify_fail_filled "R32 ★表紙 ref-chip 第2 <b> 追加を全<b>列挙で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r32.html"

# R33. ★within-doc 可視 ap-id を改竄 (data-ap-id 属性は正) → (k') 可視 id set_eq で FAIL
cp "$TMP/base-filled.html" "$TMP/r33.html"
perl -0777 -i -pe 's#<span class="ap-id">AP1</span>#<span class="ap-id">AP99</span>#' "$TMP/r33.html"
expect_verify_fail_filled "R33 ★可視 ap-id 改竄 (属性正) を within-doc set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r33.html"

# R34. ★within-doc 可視 fnid を改竄 → (k') FAIL
cp "$TMP/base-filled.html" "$TMP/r34.html"
perl -0777 -i -pe 's#<span class="fnid">FND1</span>#<span class="fnid">FND99</span>#' "$TMP/r34.html"
expect_verify_fail_filled "R34 ★可視 fnid 改竄を within-doc set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r34.html"

# R35. ★within-doc 可視 oqid を改竄 → (k') FAIL
cp "$TMP/base-filled.html" "$TMP/r35.html"
perl -0777 -i -pe 's#<span class="oqid">OQ1</span>#<span class="oqid">OQ99</span>#' "$TMP/r35.html"
expect_verify_fail_filled "R35 ★可視 oqid 改竄を within-doc set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r35.html"

# R36. ★表紙 cover-meta の件数を捏造 (わかったこと N件→99件) → (l') 集計再導出で FAIL
cp "$TMP/base-filled.html" "$TMP/r36.html"
perl -0777 -i -pe 's#(<span class="k">わかったこと</span><span class="v">)[0-9]+件#${1}99件#' "$TMP/r36.html"
expect_verify_fail_filled "R36 ★cover-meta 件数捏造を集計再導出で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r36.html"

# R37. ★表紙 cover-meta の方式範囲を捏造 (末尾 AP3→AP9) → (l') 範囲再導出で FAIL
cp "$TMP/base-filled.html" "$TMP/r37.html"
perl -0777 -i -pe 's#(検討した方式</span><span class="v">[0-9]+件 \([^)]*)AP3#${1}AP9#' "$TMP/r37.html"
expect_verify_fail_filled "R37 ★cover-meta 方式範囲捏造を範囲再導出で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r37.html"

# R38. ★round-3 ceiling: 正規 <b> を残し兄弟 <strong> で偽 id を併記 (outcome) → 残留タグ検査で FAIL
#      (全<b>列挙は <b> リテラルのみ見るため <strong>/<em>/<span> 併記が素通った fail-open)。
cp "$TMP/base-filled.html" "$TMP/r38.html"
perl -0777 -i -pe 's#(class="oc-resolved"[^>]*>[^<]*<b>ADR-CLINIC-0001</b>)#${1} (実は <strong>ADR-FORGED</strong>)#' "$TMP/r38.html"
expect_verify_fail_filled "R38 ★outcome <strong> 偽id併記 (別タグ注入) を残留タグ検査で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r38.html"

# R39. ★チップに兄弟 <em> で偽 id を併記 → 残留タグ検査で FAIL
cp "$TMP/base-filled.html" "$TMP/r39.html"
perl -0777 -i -pe 's#(data-ap-id="AP1" data-leads-to="OPT1"[^>]*>[^<]*<b>OPT1</b>)#${1} <em>OPT_EM</em>#' "$TMP/r39.html"
expect_verify_fail_filled "R39 ★チップ <em> 偽id併記を残留タグ検査で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r39.html"

# R40. ★属性付き偽 ap-id span を *追加* (正規 bare span は維持) → 順序付き within-doc 列で FAIL
#      (bare-class 限定 grep は属性付き span を見逃した fail-open。 属性許容 grep + 順序比較で捕捉)。
cp "$TMP/base-filled.html" "$TMP/r40.html"
perl -0777 -i -pe 's#(<span class="ap-id">AP1</span>)#${1}<span class="ap-id" data-x="1">AP_EXTRA</span>#' "$TMP/r40.html"
expect_verify_fail_filled "R40 ★属性付き偽 ap-id span 追加を順序付き within-doc で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r40.html"

# R41. ★可視 ap-id を多重度保存 swap (AP1↔AP2・属性は不変) → 順序付き within-doc 列で FAIL
#      (multiset set_eq は {AP1,AP2,AP3} 保存ゆえ素通った binding fail-open。 文書順比較が入替を捕捉)。
cp "$TMP/base-filled.html" "$TMP/r41.html"
perl -0777 -i -pe 's#(<span class="ap-id">)AP1(</span>)#${1}__SWAP__${2}#; s#(<span class="ap-id">)AP2(</span>)#${1}AP1${2}#; s#(<span class="ap-id">)__SWAP__(</span>)#${1}AP2${2}#' "$TMP/r41.html"
expect_verify_fail_filled "R41 ★可視 ap-id 多重度保存 swap を順序付き within-doc で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r41.html"

# R42. ★可視 fnid を多重度保存 swap (FND1↔FND2) → 順序付き within-doc 列で FAIL
cp "$TMP/base-filled.html" "$TMP/r42.html"
perl -0777 -i -pe 's#(<span class="fnid">)FND1(</span>)#${1}__SWAP__${2}#; s#(<span class="fnid">)FND2(</span>)#${1}FND1${2}#; s#(<span class="fnid">)__SWAP__(</span>)#${1}FND2${2}#' "$TMP/r42.html"
expect_verify_fail_filled "R42 ★可視 fnid 多重度保存 swap を順序付き within-doc で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r42.html"

# R43. ★round-4 ceiling: <b> の外に *タグ無しの平文* で偽 id を併記 (outcome) → 可視テキスト厳密一致で FAIL
#      (残留タグ検査はタグ無し平文を取り逃した。 全タグ除去後の可視テキスト==テンプレ で平文併記も封鎖)。
cp "$TMP/base-filled.html" "$TMP/r43.html"
perl -0777 -i -pe 's#(class="oc-resolved"[^>]*>[^<]*<b>ADR-CLINIC-0001</b>)#${1} (実は ADR-FORGED)#' "$TMP/r43.html"
expect_verify_fail_filled "R43 ★outcome 平文偽id併記 (タグ無し) を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r43.html"

# R44. ★チップに平文で偽 leads を併記 (つながる判断 OPT1 実は OPT9) → 可視テキスト厳密一致で FAIL
cp "$TMP/base-filled.html" "$TMP/r44.html"
perl -0777 -i -pe 's#(data-leads-to="OPT1"[^>]*>[^<]*<b>OPT1</b>)#${1} 実は OPT9#' "$TMP/r44.html"
expect_verify_fail_filled "R44 ★チップ平文偽id併記を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r44.html"

# R45. ★within-doc 可視 id span の直後に平文偽 id を後置 (AP1</span> AP99) → 隣接構造件数で FAIL
cp "$TMP/base-filled.html" "$TMP/r45.html"
perl -0777 -i -pe 's#(<span class="ap-id">AP1</span>)#${1} AP99#' "$TMP/r45.html"
expect_verify_fail_filled "R45 ★ap-id span 後置平文偽id を隣接構造で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r45.html"

# R46. ★表紙 cover-meta の状態バッジを捏造 → 状態 allowlist 写像再導出で FAIL
cp "$TMP/base-filled.html" "$TMP/r46.html"
perl -0777 -i -pe 's#(<span class="k">状態</span><span class="v">)[^<]*#${1}捏造状態#' "$TMP/r46.html"
expect_verify_fail_filled "R46 ★cover-meta 状態捏造を写像再導出で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r46.html"

# R47. ★round-5 ceiling: scope 項目 (<li>) を 1 件削除 → scope items 件数突合で FAIL (唯一カウント漏れだった決定的リスト)
cp "$TMP/base-filled.html" "$TMP/r47.html"
perl -0777 -i -pe 's#<li><span class="b">.*?</li>##s' "$TMP/r47.html"
expect_verify_fail_filled "R47 ★scope 項目脱落を件数突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r47.html"

# R48. ★cover-meta 版 KV を捏造 → 版 再導出で FAIL
cp "$TMP/base-filled.html" "$TMP/r48.html"
perl -0777 -i -pe 's#(<span class="k">版</span><span class="v">)[^<]*#${1}v9.9 / 偽日付#' "$TMP/r48.html"
expect_verify_fail_filled "R48 ★cover-meta 版捏造を再導出で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r48.html"

# R49. ★cover-meta に重複 KV ペアを後置注入 → KV 総数==4 基数アンカーで FAIL (head -1 単一ペア依存の fail-open)
cp "$TMP/base-filled.html" "$TMP/r49.html"
perl -0777 -i -pe 's#(<span class="m"><span class="k">版</span>)#<span class="m"><span class="k">版</span><span class="v">vDUP</span></span>${1}#' "$TMP/r49.html"
expect_verify_fail_filled "R49 ★cover-meta 重複 KV 注入を基数アンカーで捕捉" "$BASE_PROSE" "$BASE" "$TMP/r49.html"

# === ds8 ceiling 反映: wrapper-tag swap (marker-keyed parity)。 B3 の「可視テキスト厳密一致=不動点」が wrapper-tag 選択で
#     兄弟経路を残していた = tag 固定 while だと swap で可視検査を回避できる fail-open。 marker-keyed while で封鎖する。 ===

# R50. ★outcome oc-tgt の wrapper-tag swap (<p>→<div>) + <b> 内 adr_doc_id 偽装 → marker-keyed while で FAIL
cp "$TMP/base-filled.html" "$TMP/r50.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="oc-tgt"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{<b>ADR-CLINIC-0001</b>}{<b>ADR-PHANTOM</b>}r)."</div>"#se' "$TMP/r50.html"
expect_verify_fail_filled "R50 ★oc-tgt wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r50.html"

# R51. ★表紙 ref-chip の wrapper-tag swap (<div>→<span>) + <b> 内 adr_doc_id 偽装 → marker-keyed while で FAIL
cp "$TMP/base-filled.html" "$TMP/r51.html"
perl -0777 -i -pe 's#<div(\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>)(.*?)</div>#"<span".$1.($2 =~ s{<b>ADR-CLINIC-0001</b>}{<b>ADR-PHANTOM</b>}r)."</span>"#se' "$TMP/r51.html"
expect_verify_fail_filled "R51 ★ref-chip wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r51.html"

# R52. ★outcome oc-resolved の wrapper-tag swap (<p>→<div>) + <b> 内 adr_doc_id 偽装 → marker-keyed while で FAIL
cp "$TMP/base-filled.html" "$TMP/r52.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="oc-resolved"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{<b>ADR-CLINIC-0001</b>}{<b>ADR-PHANTOM</b>}r)."</div>"#se' "$TMP/r52.html"
expect_verify_fail_filled "R52 ★oc-resolved wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r52.html"

# === ds8 ceiling round-2 反映: nested-same-tag early-match / hyphen-tag ===

# R53. ★oc-tgt に空 <p></p> を入れ子注入し (.*?) を早期終端 → 群外に偽 adr_doc_id を可視追記 → nested-same-tag reject で FAIL
cp "$TMP/base-filled.html" "$TMP/r53.html"
perl -0777 -i -pe 's#(<p class="oc-tgt">.*?)</p>#${1}<p></p></p> 実は ADR-EVIL が行き先#s' "$TMP/r53.html"
expect_verify_fail_filled "R53 ★oc-tgt nested-tag early-match+群外偽id を nested-reject で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r53.html"

# R54. ★ref-chip の hyphen-tag swap (<div>→<my-tag>) + <b> 内 adr_doc_id 偽装 → marker-keyed [A-Za-z][\w-]* で捕捉して FAIL
cp "$TMP/base-filled.html" "$TMP/r54.html"
perl -0777 -i -pe 's#<div(\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>)(.*?)</div>#"<my-tag".$1.($2 =~ s{<b>ADR-CLINIC-0001</b>}{<b>ADR-PHANTOM</b>}r)."</my-tag>"#se' "$TMP/r54.html"
expect_verify_fail_filled "R54 ★ref-chip hyphen-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r54.html"

# === R55-R74: core 共通 chrome (cover-head/approval/glossary) の floor 突合 (folio-mk9・verify_core_chrome) ===
# lib/common.sh が全 pack 同一構造で emit する決定的可視 chrome 値の改竄を verify_core_chrome が FAIL することを回帰確認 (SRS A110-A129 / ADR A52-A71 と parity)。
# (a) 値改竄 = 順序突合が捕捉 / (b) decoy 注入 (大文字化/entity/unquoted/single-quote) = 占有数パリティが捕捉。 python landed-assert で改竄着地を強制。
chrome_tamper_fail() { # label needle replacement
  if python3 -c "
d=open('$TMP/base-filled.html').read()
o='''$2'''; assert o in d, 'needle not found'
open('$TMP/chrome.html','w').write(d.replace(o,'''$3''',1))
" 2>/dev/null; then expect_verify_fail_filled "$1" "$BASE_PROSE" "$BASE" "$TMP/chrome.html"; else ng "$1 setup 失敗"; fi
}
chrome_decoy_fail() { # label decoy_html (</h1> 直後へ decoy 注入)
  if python3 -c "
d=open('$TMP/base-filled.html').read()
o='</h1>'; assert o in d, 'anchor not found'
open('$TMP/chromed.html','w').write(d.replace(o,o+'''$2''',1))
" 2>/dev/null; then expect_verify_fail_filled "$1" "$BASE_PROSE" "$BASE" "$TMP/chromed.html"; else ng "$1 setup 失敗"; fi
}
# (a) 値改竄
chrome_tamper_fail "R55 ★cover eyebrow_left 改竄を core-chrome 順序突合で捕捉" '<span class="doc-type">調査記録 (Research)</span>' '<span class="doc-type">詐欺ラベル</span>'
chrome_tamper_fail "R56 ★cover eyebrow_right 改竄を core-chrome 順序突合で捕捉" '<span>クリニック — 二重予約防止の方式調査</span>' '<span>詐欺の右ラベル</span>'
chrome_tamper_fail "R57 ★cover title (h1) 改竄を core-chrome 順序突合で捕捉" '<h1>同じ診療枠への二重予約をどう防ぐか — 確定方式の比較調査</h1>' '<h1>詐欺タイトル</h1>'
chrome_tamper_fail "R58 ★cover subtitle 改竄を core-chrome 順序突合で捕捉" '<p class="cover-sub">安全 (二重予約ゼロ) と速さ (ピーク応答) を両立する確定方式を、 決めずに洗い出す</p>' '<p class="cover-sub">詐欺サブタイトル</p>'
chrome_tamper_fail "R59 ★reader (想定読者) 改竄を core-chrome 順序突合で捕捉" '想定読者: クリニックの事業責任者 + 開発リード — 医療コーディングの専門知識は不要 (専門語はやさしい言葉を併記)</div>' '想定読者: 詐欺の読者</div>'
chrome_tamper_fail "R60 ★approval role 改竄を core-chrome 順序突合で捕捉" '<span class="role">承認 (院長)</span>' '<span class="role">詐欺の役職</span>'
chrome_tamper_fail "R61 ★approval who (承認者名) 改竄を core-chrome 順序突合で捕捉" '<span class="who">山田 理恵</span>' '<span class="who">詐欺 太郎</span>'
chrome_tamper_fail "R62 ★approval when (承認日) 改竄を core-chrome 順序突合で捕捉" '<span class="when">2026-06-15 承認</span>' '<span class="when">1999-01-01 承認</span>'
chrome_tamper_fail "R63 ★approval stamp (印) 改竄を core-chrome 順序突合で捕捉" '<span class="stamp">承認済</span>' '<span class="stamp">却下</span>'
chrome_tamper_fail "R64 ★glossary term 改竄を core-chrome 順序突合で捕捉" '<div class="gword">ダブルブッキング<span class="en">' '<div class="gword">詐欺用語<span class="en">'
chrome_tamper_fail "R65 ★glossary en 改竄を core-chrome 順序突合で捕捉" '<span class="en">double booking</span>' '<span class="en">fraud-en</span>'
chrome_tamper_fail "R66 ★glossary def 改竄を core-chrome 順序突合で捕捉" '<div class="gdef">同じ枠に 2 人以上を入れてしまう事故。 来院した患者を待たせたり断ることになる。</div>' '<div class="gdef">詐欺の定義</div>'
# (b) decoy 注入 (占有数パリティが捕捉)
chrome_decoy_fail "R67 ★doc-type 大文字化 decoy を doc-type 占有数で捕捉" '<span class="DOC-TYPE">詐欺の文書種</span>'
chrome_decoy_fail "R68 ★sign 行 大文字化 decoy (偽承認行) を sign 占有数で捕捉" '<div class="SIGN"><span class="role">詐欺</span><span class="who">x</span><span class="when">y</span><span class="stamp">z</span></div>'
chrome_decoy_fail "R69 ★grow 行 大文字化 decoy (偽用語行) を grow 占有数で捕捉" '<div class="GROW"><div class="gword">詐欺</div><div class="gdef">x</div></div>'
chrome_decoy_fail "R70 ★who entity-encoded decoy (&#119;ho) を文字参照 decode 占有数で捕捉" '<span class="&#119;ho">詐欺の承認者</span>'
chrome_decoy_fail "R71 ★stamp unquoted decoy (class=stamp) を quote 非依存 占有数で捕捉" '<span class=stamp>詐欺の印</span>'
chrome_decoy_fail "R72 ★h1 大文字化 decoy (<H1>) を h1 タグ占有数で捕捉" '<H1>詐欺の第二タイトル</H1>'
chrome_decoy_fail "R73 ★想定読者 marker decoy (偽 reader-chip) を marker 占有数 + 値突合で捕捉" '<div class="reader-chip"> 想定読者: 詐欺の第二読者</div>'
# R73b ★marker *無し* の偽 reader-chip decoy (anchor 一致だが "想定読者:" 無し) を構造 anchor 占有数で捕捉 (R73 では漏れる fail-open を塞いだ folio-mk9 self-review 回帰)。
chrome_decoy_fail "R73b ★想定読者 *無し* の偽 reader-chip decoy を anchor 占有数で捕捉" '<div class="reader-chip"> 詐欺の追加チップ</div>'
# R73c ★ref-chip *構文形* の偽 reader-chip decoy (`class="reader-chip" role="note">…` = 閉じ引用後に空白+任意属性) を占有数パリティで捕捉。
#        R73b の anchor grep (`class="reader-chip">` = > 直後) は不一致・marker count も "想定読者:" 無しで不一致ゆえ素通る fail-open を
#        (class reader-chip 占有) − (data-component cross-doc-ref-chip 占有) == 1 で塞いだ回帰 (folio-mk9 self-review round-3)。
chrome_decoy_fail "R73c ★ref-chip 構文形の偽 reader-chip decoy を占有数パリティで捕捉" '<div class="reader-chip" role="note">詐欺の偽 reader-chip…</div>'
# R73d ★ref-chip と *同一構文* (class="reader-chip" data-component="cross-doc-ref-chip") を持つ additive decoy に偽『想定読者:』text を載せた攻撃。
#        旧 差分式 `(class reader-chip 占有) − (cross-doc-ref-chip 占有)` は被減数 (+1)・減数 (+1) が同タグ上で同時に増えて差 1 のまま不変ゆえ素通った
#        (folio-mk9 self-review round-4 が SRS full verify exit 0 で実証)。 element-level genuine count + global『想定読者:』marker count==1 で塞いだ回帰。
chrome_decoy_fail "R73d ★ref-chip 同一構文+偽『想定読者:』additive decoy を要素単位+marker 全体数で捕捉" '<div class="reader-chip" data-component="cross-doc-ref-chip">想定読者: 詐欺の偽読者</div>'
# R73e/f ★ref-chip 構文形 + single-quote/unquoted data-component の偽 ref-chip decoy (folio-mk9 self-review round-6・FO-1)。
#         count_genuine は ref-chip 側へ分類・ref-chip ブロック grep は double-quote 固定で見逃す・marker 無し ゆえ素通った fail-open を、
#         reader-chip class 総数 == 2 (§1b'・quote-robust count_attr_token) で封鎖した回帰。
chrome_decoy_fail "R73e ★single-quote data-component の偽 ref-chip decoy を reader-chip 総数==2 で捕捉" "<div class=\"reader-chip\" data-component='cross-doc-ref-chip'>規制当局承認済（捏造）</div>"
chrome_decoy_fail "R73f ★unquoted data-component の偽 ref-chip decoy を reader-chip 総数==2 で捕捉" '<div class="reader-chip" data-component=cross-doc-ref-chip>法的拘束力契約（捏造）</div>'
# R73g ★属性値内 > で count_genuine の tag-splitter を断片化した genuine-style decoy (folio-mk9 self-review round-6・FO-2)。
#        tag-splitter 堅牢化 + reader-chip 総数==2 の二層で封鎖した回帰。
chrome_decoy_fail "R73g ★title内 > で断片化する genuine-style decoy を tag-splitter堅牢化+総数==2 で捕捉" '<div title="x>y" class="reader-chip" role="z">捏造の権威 box</div>'
chrome_tamper_fail "R74 ★glossary en single-quote decoy を grow 行内 en 占有数で捕捉" '<div class="gword">ダブルブッキング<span class="en">double booking</span></div>' "<div class=\"gword\">ダブルブッキング<span class=\"en\">double booking</span><span class='en'>詐欺</span></div>"

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
