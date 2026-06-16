#!/usr/bin/env bash
# folio S4 generator — 敵対回帰テスト
# ceiling review (wf_41fcbde3) が突いた攻撃を、 hardening 後の assembler/verify が
# fail-closed (assemble abort) または verify FAIL で捕捉することを回帰確認する。
#
# usage: test-adversarial.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-fabrication-free.sh"
BASE="$SCRIPT_DIR/contract/ec-checkout.srs.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/ec-checkout.prose.yaml"
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
expect_inject_abort() { # label manifest assembled  (inject が exit!=0 を期待)
  if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi
}
expect_verify_pass_filled() { # label manifest contract html
  if bash "$VER" --filled "$2" "$3" "$4" >/dev/null 2>&1; then ok "$1"; else ng "$1 (--filled verify FAIL)"; fi
}
expect_verify_fail_filled() { # label manifest contract html  (--filled verify が exit!=0 を期待)
  if bash "$VER" --filled "$2" "$3" "$4" >/dev/null 2>&1; then ng "$1 (--filled verify が PASS した)"; else ok "$1"; fi
}

echo "adversarial regression (fail-closed expected):"

# A1. HTML 注入 → escape されて生 markup が出ない / 構造は健全 (verify PASS)
cp "$BASE" "$TMP/inj.yaml"
yq -i '.meta.title = "<script>alert(1)</script>注文書"' "$TMP/inj.yaml"
yq -i '.upper_needs[0].need = "A<B & C 部門"' "$TMP/inj.yaml"
bash "$ASM" "$TMP/inj.yaml" "$TMP/inj.html" >/dev/null 2>&1
# 否定: 生 <script> や back-ref 化け (<lt; 等) が無い / 肯定: 正規 entity &lt;script&gt; が出る
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/inj.html"; then ng "A1 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/inj.html"; then ok "A1 HTML 注入を正規 entity に escape (&lt;script&gt; 出力・化けなし)"
else ng "A1 正規 entity &lt;script&gt; が出ていない"; fi
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
sed -E 's/req=[0-9]+/req=999/' "$TMP/good.html" > "$TMP/tamper.html"
expect_verify_fail "A7 サマリ数値の改竄を verify が捕捉" "$BASE" "$TMP/tamper.html"

# A8. 生成後に ● トレースリンクを捏造追加 (最初の空セル) → verify が集合比較で捕捉
awk '!d && sub(/<td><\/td>/, "<td class=\"hit\"><span class=\"dot\" data-trace-link=\"FR1__N-1\">\xe2\x97\x8f</span></td>"){d=1} {print}' "$TMP/good.html" > "$TMP/fab.html"
expect_verify_fail "A8 捏造トレースリンクを verify が捕捉" "$BASE" "$TMP/fab.html"

# A9. 受入リンクを捏造追加 → verify が acceptance 集合比較で捕捉
sed '0,/data-acc-link="[^"]*"/{s#<td class="hit"><span class="dot ac" data-acc-link="\([^"]*\)">#<td class="hit"><span class="dot ac" data-acc-link="FR1__AC-FAKE">X</span><span class="dot ac" data-acc-link="\1">#}' "$TMP/good.html" > "$TMP/facc.html"
expect_verify_fail "A9 捏造受入リンクを verify が捕捉" "$BASE" "$TMP/facc.html"

echo
echo "prose 層 (③ 注入) の fail-closed:"

# 健全な充填物を 1 本 (good.html は A7 で生成済み)
bash "$INJ" "$BASE_PROSE" "$TMP/good.html" "$TMP/good-filled.html" >/dev/null 2>&1

# A10. HTML に対応スロットの無い manifest エントリ (orphan) → inject abort
cp "$BASE_PROSE" "$TMP/orphan.yaml"; key="plain-FR999" yq -i '.slots[strenv(key)] = "捏造スロット"' "$TMP/orphan.yaml"
expect_inject_abort "A10 orphan manifest エントリ (HTML に無い slot) は abort" "$TMP/orphan.yaml" "$TMP/good.html"

# A11. manifest からスロット削除 (未充填 = 脱落) → inject abort
cp "$BASE_PROSE" "$TMP/miss.yaml"; key="rtm-summary" yq -i 'del(.slots[strenv(key)])' "$TMP/miss.yaml"
expect_inject_abort "A11 manifest 欠落スロット (未充填になる) は abort" "$TMP/miss.yaml" "$TMP/good.html"

# A12. prose に HTML 注入 → escape されて生 markup が出ない / 構造健全 (--filled verify PASS)
cp "$BASE_PROSE" "$TMP/injm.yaml"; key="cover-summary" yq -i '.slots[strenv(key)] = "<script>alert(1)</script> 約束"' "$TMP/injm.yaml"
bash "$INJ" "$TMP/injm.yaml" "$TMP/good.html" "$TMP/injm.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/injm.html"; then ng "A12 prose escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/injm.html"; then ok "A12 prose の HTML 注入を正規 entity に escape"
else ng "A12 正規 entity &lt;script&gt; が出ていない"; fi
expect_verify_pass_filled "A12b prose escape 後も --filled verify PASS" "$TMP/injm.yaml" "$BASE" "$TMP/injm.html"

# A13. prose に改行 → inject abort (validate)
cp "$BASE_PROSE" "$TMP/nlp.yaml"; key="cover-summary" yq -i '.slots[strenv(key)] = "line1" + "\n" + "line2"' "$TMP/nlp.yaml"
expect_inject_abort "A13 prose に改行を含む値は abort" "$TMP/nlp.yaml" "$TMP/good.html"

# A14. 充填後にスロット内容を改竄 → --filled verify が注入忠実比較で捕捉
sed 's#data-slot-id="cover-summary">[^<]*<#data-slot-id="cover-summary">改竄された別の約束<#' "$TMP/good-filled.html" > "$TMP/tamp-filled.html"
expect_verify_fail_filled "A14 充填後の内容改竄を --filled verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/tamp-filled.html"

echo
echo "term-inline 層 (§2.2 A glossary 派生ビュー) の fail-closed:"

WMSBADGE='<span class="term" data-component="plain-language-term-inline" data-term="WMS">倉庫の在庫管理</span>'

# A15. 非 glossary 語を term-inline マーク → fidelity (data-term ∈ glossary) で捕捉
sed 's#<div class="page"[^>]*>#&<span class="term" data-component="plain-language-term-inline" data-term="捏造語">x</span>#' "$TMP/good.html" > "$TMP/fakemark.html"
expect_verify_fail "A15 非 glossary 語 (data-term) の term-inline マークを捕捉" "$BASE" "$TMP/fakemark.html"

# A16. 同一 glossary 語を二重マーク → uniqueness で捕捉
sed "s#$WMSBADGE#&&#" "$TMP/good.html" > "$TMP/dupmark.html"
expect_verify_fail "A16 glossary 語の二重マークを捕捉" "$BASE" "$TMP/dupmark.html"

# A17. glossary 語のバッジを剥がす (用語被覆漏れ) → coverage で捕捉
sed "s#$WMSBADGE##" "$TMP/good.html" > "$TMP/uncov.html"
expect_verify_fail "A17 glossary 語のマーク欠落 (用語被覆漏れ) を捕捉" "$BASE" "$TMP/uncov.html"

# A18. glossary 語どうしが部分文字列 → validate abort (ネスト span 防止)
cp "$BASE" "$TMP/sub.yaml"; yq -i '.glossary += [{"term":"DSS","plain_short":"x","def":"y"}]' "$TMP/sub.yaml"   # PCI DSS の部分文字列
expect_abort "A18 glossary 部分文字列ペアは abort" "$TMP/sub.yaml"

# A19. 併記 (plain_short) を改竄 → fidelity (併記 == plain_short) で捕捉
sed 's#\(data-term="WMS">\)倉庫の在庫管理#\1ニセの説明#' "$TMP/good.html" > "$TMP/tampterm.html"
expect_verify_fail "A19 plain_short 併記の改竄を捕捉" "$BASE" "$TMP/tampterm.html"

# A20. CJK glossary 語が漢字複合語の内部のみに出現 (在庫引当金) → 誤マークせず verify と parity (misattribution 防止)
cp "$BASE" "$TMP/cjk.yaml"; key='在庫引当金の計上ルールのみ扱う' yq -i '.scope.in[0] = strenv(key)' "$TMP/cjk.yaml"
bash "$ASM" "$TMP/cjk.yaml" "$TMP/cjk.html" 2>/dev/null
[[ "$(grep -oE 'data-term="在庫引当"' "$TMP/cjk.html" | wc -l)" == "0" ]] && ok "A20 CJK 複合語内部の glossary 語は非マーク (\\p{Han} 境界)" || ng "A20 在庫引当金 に誤マーク"
expect_verify_pass "A20b 複合語のみでも verify は assemble と parity (PASS)" "$TMP/cjk.yaml" "$TMP/cjk.html"

# A21. ascii glossary 語が大トークンの内部のみ (PCI DSSv4) → 非マーク + verify 偽FAIL なし (coverage parity)
cp "$BASE" "$TMP/asc.yaml"; key='監査 PCI DSSv4 準拠' yq -i '.nfr[3].measure = strenv(key)' "$TMP/asc.yaml"
bash "$ASM" "$TMP/asc.yaml" "$TMP/asc.html" 2>/dev/null
[[ "$(grep -oE 'data-term="PCI DSS"' "$TMP/asc.html" | wc -l)" == "0" ]] && ok "A21 ascii 語の大トークン内部は非マーク (語境界)" || ng "A21 PCI DSSv4 に誤マーク"
expect_verify_pass "A21b embedded ascii でも verify 偽FAIL なし (coverage parity)" "$TMP/asc.yaml" "$TMP/asc.html"

echo
echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]] && { echo "RESULT: 全攻撃を fail-closed で捕捉"; exit 0; } || { echo "RESULT: 取りこぼしあり"; exit 1; }
