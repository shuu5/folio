#!/usr/bin/env bash
# folio S4 generator — 敵対回帰テスト
# ceiling review (wf_41fcbde3) が突いた攻撃を、 hardening 後の assembler/verify が
# fail-closed (assemble abort) または verify FAIL で捕捉することを回帰確認する。
#
# usage: test-adversarial.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble.sh"
VER="$SCRIPT_DIR/verify-fabrication-free.sh"
BASE="$SCRIPT_DIR/contract/ec-checkout.srs.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

expect_abort() { # label contract  (assemble が exit!=0 を期待)
  if bash "$ASM" "$2" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず生成された)"; else ok "$1"; fi
}
expect_verify_fail() { # label contract html  (verify が exit!=0 を期待)
  if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ng "$1 (verify が PASS した)"; else ok "$1"; fi
}
expect_verify_pass() { # label contract html
  if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi
}

echo "adversarial regression (fail-closed expected):"

# A1. HTML 注入 → escape されて生 markup が出ない / 構造は健全 (verify PASS)
cp "$BASE" "$TMP/inj.yaml"
yq -i '.meta.title = "<script>alert(1)</script>注文書"' "$TMP/inj.yaml"
yq -i '.upper_needs[0].need = "A<B & C 部門"' "$TMP/inj.yaml"
bash "$ASM" "$TMP/inj.yaml" "$TMP/inj.html" >/dev/null 2>&1
if grep -q '<script>alert' "$TMP/inj.html"; then ng "A1 HTML 注入が生で出力された"; else ok "A1 HTML 注入は escape 済 (生 <script> なし)"; fi
expect_verify_pass "A1b 注入 escape 後も構造健全で verify PASS" "$TMP/inj.yaml" "$TMP/inj.html"

# A2. 値に改行 → @tsv 列ずれの源。validate abort
cp "$BASE" "$TMP/nl.yaml"; yq -i '.upper_needs[0].need = "line1" + "\n" + "line2"' "$TMP/nl.yaml"
expect_abort "A2 改行を含む値は fail-closed abort" "$TMP/nl.yaml"

# A3. 捏造 AC id (acceptance 正典集合外) → validate abort
cp "$BASE" "$TMP/ac.yaml"; yq -i '.requirements[0].trace.acceptance = ["AC-INVENTED"]' "$TMP/ac.yaml"
expect_abort "A3 未定義の受入基準参照は abort" "$TMP/ac.yaml"

# A4. dangling backward (upper_needs 外) → validate abort
cp "$BASE" "$TMP/bw.yaml"; yq -i '.requirements[0].trace.backward = ["N-NOPE"]' "$TMP/bw.yaml"
expect_abort "A4 未定義の上位ニーズ参照は abort" "$TMP/bw.yaml"

# A5. 要件 id 重複 → validate abort
cp "$BASE" "$TMP/dup.yaml"; yq -i '.requirements[1].id = "FR1"' "$TMP/dup.yaml"
expect_abort "A5 要件 id 重複は abort" "$TMP/dup.yaml"

# A6. 未知 EARS pattern → validate abort
cp "$BASE" "$TMP/ears.yaml"; yq -i '.requirements[0].ears.pattern = "bogus"' "$TMP/ears.yaml"
expect_abort "A6 未知 EARS pattern は abort" "$TMP/ears.yaml"

# 健全な生成物を 1 本作る
bash "$ASM" "$BASE" "$TMP/good.html" >/dev/null 2>&1

# A7. 生成後にサマリ数値を改竄 → verify が独立再計算で捕捉
sed 's/req=8/req=999/' "$TMP/good.html" > "$TMP/tamper.html"
expect_verify_fail "A7 サマリ数値の改竄を verify が捕捉" "$BASE" "$TMP/tamper.html"

# A8. 生成後に ● トレースリンクを捏造追加 (最初の空セル) → verify が集合比較で捕捉
awk '!d && sub(/<td><\/td>/, "<td class=\"hit\"><span class=\"dot\" data-trace-link=\"FR1__N-1\">\xe2\x97\x8f</span></td>"){d=1} {print}' "$TMP/good.html" > "$TMP/fab.html"
expect_verify_fail "A8 捏造トレースリンクを verify が捕捉" "$BASE" "$TMP/fab.html"

# A9. 受入リンクを捏造追加 → verify が acceptance 集合比較で捕捉
sed '0,/data-acc-link="[^"]*"/{s#<td class="hit"><span class="dot ac" data-acc-link="\([^"]*\)">#<td class="hit"><span class="dot ac" data-acc-link="FR1__AC-FAKE">X</span><span class="dot ac" data-acc-link="\1">#}' "$TMP/good.html" > "$TMP/facc.html"
expect_verify_fail "A9 捏造受入リンクを verify が捕捉" "$BASE" "$TMP/facc.html"

echo
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]] && { echo "RESULT: 全攻撃を fail-closed で捕捉"; exit 0; } || { echo "RESULT: 取りこぼしあり"; exit 1; }
