#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack 敵対回帰テスト (instance#2)
#
# ADR-pack の fail-closed gate (assemble-adr validate abort / verify-adr FAIL / inject abort) が
# 構造捏造・★cross-doc 照会の dangling/改竄・prose 改竄・term-inline 改竄を捕捉することを回帰確認する。
# SRS-pack の test-adversarial.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
#
# usage: test-adversarial-adr.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-adr.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-adr.sh"
BASE="$SCRIPT_DIR/contract/clinic-double-booking.adr.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/clinic-double-booking.adr.prose.yaml"
SRS="$SCRIPT_DIR/contract/clinic-appointment.srs.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# ★cross_doc 解決は contract dir 相対。 mutated ADR contract を $TMP に置くため、 照会先 SRS contract も
#   同名で $TMP へ複製する (これをしないと全 abort が「SRS 不在」で起き、 意図した理由を検証できない
#   false-pass になる = S4 の A1 否定検証 false-pass 教訓と同型)。
cp "$SRS" "$TMP/clinic-appointment.srs.yaml"
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

# expect_abort: assemble-adr が exit!=0 で abort し、 かつ stderr に想定理由 ($3) を含むことを要求
# (理由検証で「別原因の誤 abort」= false-pass を弾く)。 mutated contract は $TMP に置く。
expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
expect_verify_fail() { if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ng "$1 (verify が PASS した)"; else ok "$1"; fi; }
expect_verify_pass() { if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi; }
expect_verify_fail_filled() { if bash "$VER" --filled "$2" "$3" "$4" >/dev/null 2>&1; then ng "$1 (--filled verify が PASS した)"; else ok "$1"; fi; }
expect_inject_abort() { if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi; }

# 健全 baseline を一度生成 (HTML 改竄系の元)
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }

echo "ADR-pack adversarial regression (fail-closed expected):"

# === assemble-adr validate (生成前 fail-closed) ===

# A1. ★cross-doc dangling: justifies の req を SRS に無い FR99 に → abort
cp "$BASE" "$TMP/a1.yaml"; yq -i '.decision.justifies[0].req = "FR99"' "$TMP/a1.yaml"
expect_abort "A1 ★cross-doc dangling 照会 (SRS に無い req) を生成前 abort" "$TMP/a1.yaml" "dangling"

# A2. ★cross-doc doc_id 不一致 → abort
cp "$BASE" "$TMP/a2.yaml"; yq -i '.cross_doc.srs_doc_id = "SRS-WRONG"' "$TMP/a2.yaml"
expect_abort "A2 ★cross_doc.srs_doc_id 不一致を abort" "$TMP/a2.yaml" "srs_doc_id"

# A3. ★cross-doc 照会先 contract 不在 → abort
cp "$BASE" "$TMP/a3.yaml"; yq -i '.cross_doc.srs_contract = "nonexistent.srs.yaml"' "$TMP/a3.yaml"
expect_abort "A3 ★照会先 SRS contract 不在を abort" "$TMP/a3.yaml" "見つからない"

# A4. 未知の照会 role (抽象 allowlist 外) → abort
cp "$BASE" "$TMP/a4.yaml"; yq -i '.decision.justifies[0].role = "wild-role"' "$TMP/a4.yaml"
expect_abort "A4 未知の照会 role を abort" "$TMP/a4.yaml" "未知の照会 role"

# A5. verdict=chosen が 2 件 → abort
cp "$BASE" "$TMP/a5.yaml"; yq -i '.options[1].verdict = "chosen"' "$TMP/a5.yaml"
expect_abort "A5 verdict=chosen が複数を abort" "$TMP/a5.yaml" "ちょうど 1 件"

# A6. decision.chosen と verdict=chosen option の不一致 → abort
cp "$BASE" "$TMP/a6.yaml"; yq -i '.decision.chosen = "OPT2"' "$TMP/a6.yaml"
expect_abort "A6 decision.chosen と chosen option 不一致を abort" "$TMP/a6.yaml" "verdict=chosen option"

# A7. decision.chosen が options に無い → abort
cp "$BASE" "$TMP/a7.yaml"; yq -i '.decision.chosen = "OPT-GHOST"' "$TMP/a7.yaml"
expect_abort "A7 decision.chosen が options に無いを abort" "$TMP/a7.yaml" "options に無い"

# A8. 未知の verdict → abort
cp "$BASE" "$TMP/a8.yaml"; yq -i '.options[1].verdict = "maybe"' "$TMP/a8.yaml"
expect_abort "A8 未知の verdict を abort" "$TMP/a8.yaml" "未知の verdict"

# A9. 未知の adr_status → abort
cp "$BASE" "$TMP/a9.yaml"; yq -i '.meta.adr_status = "vibes"' "$TMP/a9.yaml"
expect_abort "A9 未知の adr_status を abort" "$TMP/a9.yaml" "未知の adr_status"

# A10. option id 重複 → abort
cp "$BASE" "$TMP/a10.yaml"; yq -i '.options[1].id = "OPT1"' "$TMP/a10.yaml"
expect_abort "A10 option id 重複を abort" "$TMP/a10.yaml" "option id 重複"

# A11. 値に改行 (@tsv 列ずれの源) → abort
cp "$BASE" "$TMP/a11.yaml"; yq -i '.context[0].detail = "line1" + "\n" + "line2"' "$TMP/a11.yaml"
expect_abort "A11 改行を含む値を abort" "$TMP/a11.yaml" "tab/改行"

# A12. glossary 部分文字列ペア (term-inline ネスト span) → abort
cp "$BASE" "$TMP/a12.yaml"; yq -i '.glossary += [{"term":"ロック","en":"lock","plain_short":"錠","def":"錠の説明。"}]' "$TMP/a12.yaml"
expect_abort "A12 glossary 部分文字列ペア (ロック ⊂ 楽観ロック) を abort" "$TMP/a12.yaml" "部分文字列"

# === HTML 改竄 (生成後 fail-closed = verify-adr) ===

# A13. HTML に偽 data-justifies-req を注入 → verify set 不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/a13.html"
perl -0777 -i -pe 's#(<p class="justify-tgt")#<span data-justifies-req="FR99" data-justifies-role="claim">x</span>$1#' "$TMP/a13.html"
expect_verify_fail_filled "A13 ★HTML への偽 justifies-req 注入を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a13.html"

# A14. option card を 1 枚削除 → 行数不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/a14.html"
perl -0777 -i -pe 's#<div data-component="adr-option-card"[^>]*>.*?</div>\s*</div>##s' "$TMP/a14.html"
expect_verify_fail_filled "A14 option card 削除を行数 gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a14.html"

# A15. prose スロットの内容を改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/a15.html"
perl -0777 -i -pe 's#(data-slot-id="decision-rationale">)[^<]*#${1}改竄された根拠#' "$TMP/a15.html"
expect_verify_fail_filled "A15 prose 改竄 (注入忠実) を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a15.html"

# A16. term-inline の併記を誤った plain_short へ改竄 → fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/a16.html"
perl -0777 -i -pe 's#(data-term="ダブルブッキング">)[^<]*#${1}でたらめ#' "$TMP/a16.html"
expect_verify_fail_filled "A16 term-inline 併記改竄を fidelity が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a16.html"

# A17. HTML 改竄: chosen バッジを 2 個に → 可視 verdict 捏造 FAIL
cp "$TMP/base-filled.html" "$TMP/a17.html"
perl -0777 -i -pe 's#class="opt-verdict rejected"#class="opt-verdict chosen"#' "$TMP/a17.html"
expect_verify_fail_filled "A17 可視 chosen バッジ捏造 (2 個) を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a17.html"

# A22. ★HTML 改竄: 照会 role を allowlist 内の別 role へ改竄 (claim→rationale) → (req,role) ペア不一致 FAIL
#      (allowlist 内別 role への偽装は role 数だけでは素通り = fail-open。 ペア集合突合で捕捉する)。
cp "$TMP/base-filled.html" "$TMP/a22.html"
perl -0777 -i -pe 's#(data-justifies-req="FR2" data-justifies-role=)"claim"#${1}"rationale"#' "$TMP/a22.html"
expect_verify_fail_filled "A22 ★照会 role を allowlist 内別 role へ改竄を (req,role) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/a22.html"

# A23. ★HTML 改竄: chosen/rejected バッジを別カードへ付け替え (chosen 総数 1 のまま) → (opt-id,verdict) ペア不一致 FAIL
#      (件数保存型の採用カード偽装は総数==1 だけでは素通り = fail-open。 id↔verdict ペア突合で捕捉する)。
cp "$TMP/base-filled.html" "$TMP/a23.html"
perl -0777 -i -pe 's#(<span class="opt-id">OPT1</span><span class="opt-name">.*?</span><span class="opt-verdict )chosen#${1}rejected#s' "$TMP/a23.html"
perl -0777 -i -pe 's#(<span class="opt-id">OPT2</span><span class="opt-name">.*?</span><span class="opt-verdict )rejected#${1}chosen#s' "$TMP/a23.html"
expect_verify_fail_filled "A23 ★verdict バッジ付け替え (総数不変) を (opt-id,verdict) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/a23.html"

# A24. ★HTML 改竄: 既存 justify edge (FR2 row) を重複注入 (req 集合は不変) → count anchor で FAIL
#      (set_eq は sort -u で重複を潰すため集合不変=fail-open。 count chk とペアで二重 cross-doc 照会を捕捉)。
cp "$TMP/base-filled.html" "$TMP/a24.html"
perl -0777 -i -pe 's#(<div class="justify-row"><span class="justify-req" data-justifies-req="FR2".*?</div>)#$1$1#s' "$TMP/a24.html"
expect_verify_fail_filled "A24 ★既存 justify edge の重複注入 (集合不変) を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a24.html"

# A25. ★HTML 改竄: verdict バッジの class は正 (chosen) のまま可視ラベルだけ改竄 (採用→不採用) → 可視ラベル整合で FAIL
#      (非エンジニアが読むのは class でなく可視文字。 class 突合だけでは fail-open)。
cp "$TMP/base-filled.html" "$TMP/a25.html"
perl -0777 -i -pe 's#(<span class="opt-verdict chosen">)採用(</span>)#${1}不採用${2}#' "$TMP/a25.html"
expect_verify_fail_filled "A25 ★verdict バッジの可視ラベルのみ改竄 (class は正) を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a25.html"

# A26. ★HTML 改竄: principle.id 改竄 / supersession.status 偽装 / superseded_by 捏造 → 終端章の構造検証で FAIL
#      (assembler が emit する supersession/principle を fabrication-free 対象に拡張)。
cp "$TMP/base-filled.html" "$TMP/a26a.html"; perl -0777 -i -pe 's#PRIN-SAFETY-FIRST#PRIN-FORGED#' "$TMP/a26a.html"
expect_verify_fail_filled "A26a ★principle.id 改竄を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26a.html"
cp "$TMP/base-filled.html" "$TMP/a26b.html"; perl -0777 -i -pe 's#(改訂状態</span>)current#${1}superseded#' "$TMP/a26b.html"
expect_verify_fail_filled "A26b ★supersession.status 偽装を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26b.html"
cp "$TMP/base-filled.html" "$TMP/a26c.html"; perl -0777 -i -pe 's#(置き換えられた</span>)なし \(現行\)#${1}ADR-Z#' "$TMP/a26c.html"
expect_verify_fail_filled "A26c ★superseded_by 捏造リンクを捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26c.html"

# === ds8: cross-doc helper core 昇格 + research 堅牢化の ADR 横展開 (Part 2a 空値ガード / Part 2b 可視 echo 厳密一致) ===

# A27. ★空 justifies[].req (comm -23 が空行を空 missing に畳む dangling fail-open の兄弟) → 生成前 abort (assemble 側ガード = 実バグ修正)
cp "$BASE" "$TMP/a27.yaml"; yq -i '.decision.justifies[0].req = ""' "$TMP/a27.yaml"
expect_abort "A27 ★空 justifies req (dangling fail-open 兄弟) を生成前 abort" "$TMP/a27.yaml" "空 req"

# A28. ★表紙 ref-chip に平文で偽 id を併記 → 可視テキスト厳密一致で FAIL (research R43/R44 平文併記の ADR 版・attr/<b> は正のまま)
cp "$TMP/base-filled.html" "$TMP/a28.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>FR2・FR3</b>)#${1} 実は FR9#s' "$TMP/a28.html"
expect_verify_fail_filled "A28 ★表紙 ref-chip 平文偽id併記を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a28.html"

# A29. ★表紙 ref-chip に第2 <b> を追加 → <b> ちょうど 2 本要求 (MULTI-B) で FAIL (research R30/R32 追加方向・first-<b> 素通り封鎖)
cp "$TMP/base-filled.html" "$TMP/a29.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>SRS-CLINIC-APPT</b>)#${1} <b>SRS-FAKE</b>#s' "$TMP/a29.html"
expect_verify_fail_filled "A29 ★表紙 ref-chip 第2<b> 追加を <b> 本数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a29.html"

# A30. ★表紙 ref-chip に別タグ <strong> で偽 id を併記 → 全タグ除去後の可視テキスト厳密一致で FAIL (research R38/R39 別タグ注入の ADR 版)
cp "$TMP/base-filled.html" "$TMP/a30.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>FR2・FR3</b>)#${1} <strong>FR9</strong>#s' "$TMP/a30.html"
expect_verify_fail_filled "A30 ★表紙 ref-chip <strong> 偽id併記を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a30.html"

# A31. ★表紙 ref-chip の b1<->b2 swap (両 <b> は正規値・位置だけ入替) → 位置別 <b> 突合 (b1==srs_doc_id) で FAIL
cp "$TMP/base-filled.html" "$TMP/a31.html"
perl -0777 -i -pe 's#<b>SRS-CLINIC-APPT</b> の <b>FR2・FR3</b>#<b>FR2・FR3</b> の <b>SRS-CLINIC-APPT</b>#' "$TMP/a31.html"
expect_verify_fail_filled "A31 ★表紙 ref-chip b1<->b2 swap を位置別 <b> 突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a31.html"

# A32. ★照会先 footnote justify-tgt の可視 srs_doc_id を偽 id へ改竄 (<b> 無し平文) → 可視テキスト全体一致で FAIL
cp "$TMP/base-filled.html" "$TMP/a32.html"
perl -0777 -i -pe 's#(class="justify-tgt">照会先: )SRS-CLINIC-APPT#${1}SRS-PHANTOM#' "$TMP/a32.html"
expect_verify_fail_filled "A32 ★justify-tgt 平文 srs_doc_id 改竄を可視テキスト全体一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a32.html"

# A33. ★justify-tgt をブロックごと削除 → ブロック==1 count anchor で FAIL (while が回らず @bad 空の素通りを塞ぐ・research と同じ規律)
cp "$TMP/base-filled.html" "$TMP/a33.html"
perl -0777 -i -pe 's#<p class="justify-tgt">.*?</p>##s' "$TMP/a33.html"
expect_verify_fail_filled "A33 ★justify-tgt ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a33.html"

# A34. ★justify-row の可視 req を改竄 (data-justifies-req 属性は正) → attr-vs-visible 厳密一致で FAIL
#      (research R24/within-doc (k') の ADR 版。 非エンジニアが読む可視 req だけ捏造し attr 温存する経路を封鎖)。
cp "$TMP/base-filled.html" "$TMP/a34.html"
perl -0777 -i -pe 's#(data-justifies-req="FR2" data-justifies-role="claim">)FR2(</span>)#${1}FR9${2}#' "$TMP/a34.html"
expect_verify_fail_filled "A34 ★justify-row 可視 req 改竄 (attr 正) を attr-vs-visible で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a34.html"

# A35. ★justify-req span を 1 枚削除 → justify-req span == |justifies| count anchor で FAIL (cross-doc count とも二重に捕捉)
cp "$TMP/base-filled.html" "$TMP/a35.html"
perl -0777 -i -pe 's#<span class="justify-req" data-justifies-req="FR3".*?</span>##s' "$TMP/a35.html"
expect_verify_fail_filled "A35 ★justify-req span 削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a35.html"

# A36. ★表紙 ref-chip をブロックごと削除 → ブロック==1 count anchor で FAIL (可視テキスト厳密一致は while 空回りで素通る=
#      設計が名指しする fail-open。 88行 count anchor が唯一の guard ゆえ A33/justify-tgt・A35/justify-req と対称に固定する)。
cp "$TMP/base-filled.html" "$TMP/a36.html"
perl -0777 -i -pe 's#<div class="reader-chip" data-component="cross-doc-ref-chip">.*?</div>##s' "$TMP/a36.html"
expect_verify_fail_filled "A36 ★表紙 ref-chip ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a36.html"

# === ds8 ceiling 反映: jh 見出し (第4の可視 cross-doc echo) + wrapper-tag swap (marker-keyed parity) ===

# A37. ★jh 見出しの可視 srs_doc_id を偽 id へ改竄 (tag 維持・<b> 無し平文) → 可視テキスト全体一致で FAIL
#      (ds8 ceiling 検出: Part 2b が jh を列挙し忘れ偽 doc_id が素通っていた = 機械的完全性照合の漏れ是正)。
cp "$TMP/base-filled.html" "$TMP/a37.html"
perl -0777 -i -pe 's#(class="jh">.*?)SRS-CLINIC-APPT#${1}SRS-PHANTOM#s' "$TMP/a37.html"
expect_verify_fail_filled "A37 ★jh 見出し平文 srs_doc_id 改竄を可視テキスト全体一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a37.html"

# A38. ★jh 見出しの wrapper-tag swap (<p>→<div>) + 偽 id → marker-keyed while が任意タグを捕捉して FAIL
#      (tag 固定だと <p> 以外へ swap で while スキップ→可視検査回避の fail-open。 marker-keyed で封鎖)。
cp "$TMP/base-filled.html" "$TMP/a38.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="jh"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</div>"#se' "$TMP/a38.html"
expect_verify_fail_filled "A38 ★jh wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a38.html"

# A39. ★jh 見出しをブロックごと削除 → jh ブロック==1 count anchor で FAIL (while 空回り素通りを塞ぐ・A33/A36 と対称)
cp "$TMP/base-filled.html" "$TMP/a39.html"
perl -0777 -i -pe 's#<p class="jh">.*?</p>##s' "$TMP/a39.html"
expect_verify_fail_filled "A39 ★jh ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a39.html"

# A40. ★表紙 ref-chip の wrapper-tag swap (<div>→<span>) + <b> 内 srs_doc_id 偽装 → marker-keyed while で FAIL
#      (ds8 ceiling major: count anchor は marker-only だが while が tag 固定 = selector 非パリティで swap が可視検査を逃れていた)。
cp "$TMP/base-filled.html" "$TMP/a40.html"
perl -0777 -i -pe 's#<div(\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>)(.*?)</div>#"<span".$1.($2 =~ s{<b>SRS-CLINIC-APPT</b>}{<b>SRS-PHANTOM</b>}r)."</span>"#se' "$TMP/a40.html"
expect_verify_fail_filled "A40 ★ref-chip wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a40.html"

# A41. ★justify-tgt の wrapper-tag swap (<p>→<div>) + 偽 id → marker-keyed while で FAIL
cp "$TMP/base-filled.html" "$TMP/a41.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="justify-tgt"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</div>"#se' "$TMP/a41.html"
expect_verify_fail_filled "A41 ★justify-tgt wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a41.html"

# === ds8 ceiling round-2 反映: nested-same-tag early-match / hyphen-tag / identity echo (dec-kick/prin-id) ===

# A42. ★jh に空 <p></p> を入れ子注入し (.*?) を早期終端 → 捕捉群外に偽 provenance を可視追記 → nested-same-tag reject で FAIL
#      (round-2 blocker: marker-keyed backreference の最深兄弟。 早期終端の痕跡 <p> が捕捉群に残るのを reject する不動点)。
cp "$TMP/base-filled.html" "$TMP/a42.html"
perl -0777 -i -pe 's#(<p class="jh">[^<]*)</p>#${1}<p></p></p> 実は SRS-EVIL が正当化#' "$TMP/a42.html"
expect_verify_fail_filled "A42 ★jh nested-tag early-match+群外偽provenance を nested-reject で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a42.html"

# A43. ★ref-chip に空 <div></div> を入れ子注入し早期終端 → 群外に偽要件を可視追記 → nested-same-tag reject で FAIL
cp "$TMP/base-filled.html" "$TMP/a43.html"
perl -0777 -i -pe 's#(<div class="reader-chip" data-component="cross-doc-ref-chip">.*?)</div>#${1}<div></div></div> 実は SRS-EVIL の正当化要件#s' "$TMP/a43.html"
expect_verify_fail_filled "A43 ★ref-chip nested-tag early-match+群外偽要件 を nested-reject で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a43.html"

# A44. ★justify-tgt の hyphen-tag swap (<p>→<my-tag>) + 偽 id → marker-keyed の [A-Za-z][\w-]* がハイフンタグを捕捉して FAIL
#      (round-2 blocker: \w+ だとハイフンタグを取りこぼし count anchor も backstop にならなかった)。
cp "$TMP/base-filled.html" "$TMP/a44.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="justify-tgt"[^>]*>)(.*?)</p>#"<my-tag".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</my-tag>"#se' "$TMP/a44.html"
expect_verify_fail_filled "A44 ★justify-tgt hyphen-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a44.html"

# A45. ★dec-kick (採用見出し) の可視 chosen を偽 id へ改竄 → 可視テキスト厳密一致で FAIL (round-2: identity echo の列挙漏れ是正)
cp "$TMP/base-filled.html" "$TMP/a45.html"
perl -0777 -i -pe 's#(<p class="dec-kick">採用 — )[^<]*#${1}OPT-EVIL#' "$TMP/a45.html"
expect_verify_fail_filled "A45 ★dec-kick chosen 改竄を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a45.html"

# A46. ★prin-id を duplicate-decoy (隠し正規 <p> を残し可視偽 <p> を付け足し) → prin-id 行==1 count anchor で FAIL (round-2 major)
cp "$TMP/base-filled.html" "$TMP/a46.html"
perl -0777 -i -pe 's#(<p class="prin-id">[^<]*</p>)#${1}<p class="prin-id">原則 — PRIN-FORGED</p>#' "$TMP/a46.html"
expect_verify_fail_filled "A46 ★prin-id duplicate-decoy を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a46.html"

# === ds8 ceiling round-3 反映: ADR identity echo parity (cover-meta / cxid / drid) ===

# A47. ★表紙 cover-meta の 結果 KV を可視改竄 → 決定的再導出突合で FAIL (round-2 まで ADR cover-meta は皆無検証 = research (l') との parity gap)
cp "$TMP/base-filled.html" "$TMP/a47.html"
perl -0777 -i -pe 's#(<span class="k">結果</span><span class="v">)[^<]*#${1}良い 9 / トレードオフ 9#' "$TMP/a47.html"
expect_verify_fail_filled "A47 ★cover-meta 結果 改竄を再導出突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a47.html"

# A48. ★可視 cxid (context id) を改竄 (attr/contract 一意性は不変) → within-doc 順序突合で FAIL (research (k') との parity)
cp "$TMP/base-filled.html" "$TMP/a48.html"
perl -0777 -i -pe 's#(<span class="cxid">)CTX1#${1}CTX-PHANTOM#' "$TMP/a48.html"
expect_verify_fail_filled "A48 ★可視 cxid 改竄を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a48.html"

# A49. ★可視 drid (driver id) を改竄 → within-doc 順序突合で FAIL
cp "$TMP/base-filled.html" "$TMP/a49.html"
perl -0777 -i -pe 's#(class="drid">)DR1#${1}DR-PHANTOM#' "$TMP/a49.html"
expect_verify_fail_filled "A49 ★可視 drid 改竄を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a49.html"

# A50. ★round-4: 可視 justify-role を allowlist 内別 role へ swap (claim→rationale・data-justifies-role attr は正) → within-doc 順序突合で FAIL
#      (round-2 で可視 req==attr は強制したが role の可視を漏らした parity 漏れ = cross-doc edge の可視 fidelity)
cp "$TMP/base-filled.html" "$TMP/a50.html"
perl -0777 -i -pe 's#(<span class="justify-role">)claim#${1}rationale#' "$TMP/a50.html"
expect_verify_fail_filled "A50 ★可視 justify-role swap を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a50.html"

# === inject fail-closed ===

# A18. manifest から 1 スロットを削除 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/a18.prose.yaml"; yq -i 'del(.slots.["decision-rationale"])' "$TMP/a18.prose.yaml"
expect_inject_abort "A18 manifest 欠落スロットを inject が abort" "$TMP/a18.prose.yaml" "$TMP/base.html"

# A19. manifest に orphan キー追加 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/a19.prose.yaml"; yq -i '.slots.["ghost-slot"] = "幽霊"' "$TMP/a19.prose.yaml"
expect_inject_abort "A19 manifest orphan キーを inject が abort" "$TMP/a19.prose.yaml" "$TMP/base.html"

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_verify_pass "A20 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"

# A21. HTML 注入の escape 健全性 (生 markup が構造へ漏れない)
cp "$BASE" "$TMP/a21.yaml"; yq -i '.decision.statement = "<script>alert(1)</script>確定する"' "$TMP/a21.yaml"
bash "$ASM" "$TMP/a21.yaml" "$TMP/a21.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/a21.html"; then ng "A21 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/a21.html"; then ok "A21 HTML 注入を正規 entity に escape"
else ng "A21 正規 entity &lt;script&gt; が出ていない"; fi

echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
