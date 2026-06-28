#!/usr/bin/env bash
# test-adversarial-glossary.sh — glossary-pack floor の敵対検査 (verify-glossary.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-glossary.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗。
#
# usage: test-adversarial-glossary.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/folio-glossary.glossary.yaml"
MANIFEST="$HERE/prose/folio-glossary.prose.yaml"
ASSEMBLE="$HERE/assemble-glossary.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-glossary.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# expect_fail <label> <mutated.html> — verify が exit 1 (FAIL) を返すべき
expect_fail() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# 1. term-entry を 1 個削除 (canonical/en/slug 集合 脱落)
m="$TMP/m1.html"; perl -0777 -pe 's{<section class="term-entry"[^>]*>.*?</section>}{}s' "$GOOD" > "$m"
expect_fail "term-entry 削除" "$m"

# 2. canonical (data-term) を捏造
m="$TMP/m2.html"; perl -0777 -pe 's{data-term="spec"}{data-term="GHOST"}' "$GOOD" > "$m"
expect_fail "canonical(data-term) 捏造" "$m"

# 3. 機械 en (data-term-en) を改竄
m="$TMP/m3.html"; perl -0777 -pe 's{data-term-en="spec"}{data-term-en="FAKE"}' "$GOOD" > "$m"
expect_fail "機械 en(data-term-en) 改竄" "$m"

# 4. 機械 slug (data-term-slug) を改竄
m="$TMP/m4.html"; perl -0777 -pe 's{data-term-slug="spec"}{data-term-slug="bogus"}' "$GOOD" > "$m"
expect_fail "機械 slug(data-term-slug) 改竄" "$m"

# 5. 正式定義 (term-formal) のテキストを改竄
m="$TMP/m5.html"; perl -0777 -pe 's{(<dd class="term-formal">)[^<]+}{${1}改竄定義テキスト}s' "$GOOD" > "$m"
expect_fail "正式定義 (term-formal) 改竄" "$m"

# 6. human anchor id を改竄
m="$TMP/m6.html"; perl -0777 -pe 's{id="term-spec"}{id="term-WRONG"}' "$GOOD" > "$m"
expect_fail "human anchor id 改竄" "$m"

# 7. JSON-LD DefinedTerm name を可視と desync
m="$TMP/m7.html"; perl -0777 -pe 's{("\@type":"DefinedTerm","\@id":"folio:term/spec","name":")spec(")}{${1}DESYNC${2}}' "$GOOD" > "$m"
expect_fail "JSON-LD name desync" "$m"

# 8. cross-doc anchor (data-xref-target) を改竄
m="$TMP/m8.html"; perl -0777 -pe 's{data-xref-target="P-3"}{data-xref-target="FAKE-REF"}' "$GOOD" > "$m"
expect_fail "cross-doc anchor 改竄" "$m"

# 9. cover-meta KV を捏造
m="$TMP/m9.html"; perl -0777 -pe 's{(<dl class="cover-meta">.*?<dd[^>]*>)[^<]+}{${1}捏造値}s' "$GOOD" > "$m"
expect_fail "cover-meta KV 捏造" "$m"

# 10. term 2 個を並べ替え (emission 順 不一致) — 先頭 2 つの term-entry を入れ替え
m="$TMP/m10.html"; perl -0777 -e '
  local $/; my $h=<>;
  my @e; $h =~ s{(<section class="term-entry".*?</section>\n)}{ push @e,$1; "\x00SLOT".(scalar @e - 1)."\x00" }ges;
  if (@e >= 2){ ($e[0],$e[1])=($e[1],$e[0]); }
  $h =~ s/\x00SLOT(\d+)\x00/$e[$1]/g;
  print $h;
' "$GOOD" > "$m"
expect_fail "term 並べ替え (emission 順)" "$m"

# 11. prose 注入テキストを改竄 (注入忠実 fail)
m="$TMP/m11.html"; perl -0777 -pe 's{(data-prose-slot="plain-spec"[^>]*>)[^<]+}{${1}注入を改竄}s' "$GOOD" > "$m"
expect_fail "prose 注入改竄 (注入忠実)" "$m"

# 12. prose スロットを空に戻す (未充填)
m="$TMP/m12.html"; perl -0777 -pe 's{(data-prose-slot="plain-spec"[^>]*>)[^<]+(</p>)}{${1}${2}}s' "$GOOD" > "$m"
expect_fail "prose 未充填" "$m"

# --- 可視 human 層テキストと machine 属性の desync (§2b 可視-属性 双子 bind の証明) ---
# いずれも属性 (data-term* / id) は intact のまま *可視テキストだけ* を捏造する。 §2 (属性のみ bind) は
# これらを通すが §2b (可視テキスト bind) が block するはず = fail-open の封鎖を機械的に実証。

# 13. 可視見出し語 (h3 term-name) を捏造 (data-term="spec" は intact)
m="$TMP/m13.html"; perl -0777 -pe 's{(<h3 class="term-name">)spec(</h3>)}{${1}GHOST${2}}' "$GOOD" > "$m"
expect_fail "可視見出し語 (h3 term-name) 捏造 / 属性 intact" "$m"

# 14. 可視 en (dd data-term-en テキスト) を捏造 (data-term-en="spec" 属性は intact)
m="$TMP/m14.html"; perl -0777 -pe 's{(<dd data-term-en="spec">)spec(</dd>)}{${1}FAKEEN${2}}' "$GOOD" > "$m"
expect_fail "可視 en テキスト 捏造 / 属性 intact" "$m"

# 15. 可視 domain (dd data-term-domain テキスト) を捏造 (data-term-domain 属性は intact)
m="$TMP/m15.html"; perl -0777 -pe 's{(<dd data-term-domain="folio-closed">)folio-closed(</dd>)}{${1}fake-domain${2}}' "$GOOD" > "$m"
expect_fail "可視 domain テキスト 捏造 / 属性 intact" "$m"

# 16. 可視 slug-anchor (dd data-term-slug テキスト #term-<slug>) を捏造 (data-term-slug 属性は intact)
m="$TMP/m16.html"; perl -0777 -pe 's{(<dd data-term-slug="spec">)#term-spec(</dd>)}{${1}#term-WRONG${2}}' "$GOOD" > "$m"
expect_fail "可視 slug-anchor テキスト 捏造 / 属性 intact" "$m"

# --- glossary-pack 固有 emit (継承パターン外) の可視 contract 由来トークン捏造 ---
# gen-meta (<p class="gen-meta">) と用語数 h2 はこの pack が新規に開けた fail-open ゆえ専用に pin する。

# 17. gen-meta 値 (<p class="gen-meta"> 可視 contract 値) を捏造
m="$TMP/m17.html"; perl -0777 -pe 's{(<p class="gen-meta">)[^<]+}{${1}FABRICATED-GENMETA}s' "$GOOD" > "$m"
expect_fail "gen-meta 捏造 (可視 contract 値)" "$m"

# 18. 用語数 h2 (<h2>用語 (N 語)</h2> の N) を捏造 (term-entry 数とは別の可視トークン)
m="$TMP/m18.html"; perl -0777 -pe 's{(<h2>用語 \()\d+( 語\)</h2>)}{${1}999${2}}s' "$GOOD" > "$m"
expect_fail "用語数 h2 count 捏造" "$m"

# 20. ★folio-bur: xref li 可視 "定義元: {target}" を捏造 (data-xref-target 属性は intact・visible-text-vs-attribute)
m="$TMP/m20.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">)定義元: P-3(</li>)}{${1}定義元: FAKE-XREF${2}}' "$GOOD" > "$m"
expect_fail "★xref li 可視捏造 (定義元: target≠属性) / 属性 intact" "$m"

# 21. ★folio-bur: data-xref-target 属性なしの孤立 li を term-xrefs <ul> 内へ挿入 (orphan-or-count)
m="$TMP/m21.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">定義元: P-3</li>)}{${1}<li>GHOST-XREF</li>}' "$GOOD" > "$m"
expect_fail "★孤立 xref li 挿入 (属性なし) を li 総数で捕捉" "$m"

# 19. verify が GREEN を *決して* 出さない (floor 単独 GREEN 禁止)
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi

echo ""
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
