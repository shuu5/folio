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
