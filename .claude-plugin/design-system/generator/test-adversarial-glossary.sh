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

# 22/23. ★folio-bur round-2 (ceiling-recursion): Pin A/B の double-quote 固定の射程外を quote-robust 抽出 + 残差検査で捕捉。
m="$TMP/m22.html"; perl -0777 -pe "s{<li data-xref-target=\"P-3\" data-xref-rel=\"glossary-anchor\">定義元: P-3</li>}{<li data-xref-target='P-3' data-xref-rel='glossary-anchor'>定義元: 捏造先</li>}" "$GOOD" > "$m"
expect_fail "★single-quote 属性 + 可視捏造 (定義元: 捏造先) を quote-robust 可視 set_eq で捕捉" "$m"
m="$TMP/m23.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">定義元: P-3</li>)}{${1}<p>定義元: 捏造</p>}' "$GOOD" > "$m"
expect_fail "★term-xrefs ul への非 li タグ混入 (<p>) を残差 whitespace-only 検査で捕捉" "$m"
# 24-27. ★folio-bur round-3 (ceiling-recursion R2 是正): container tag-swap (ol/div) + 別class/classless provenance + 2個目 cover-meta dl。
#   いずれも大域 '定義元:' marker parity / cover-meta dl 占有数で捕捉 (anchor の class/タグに依らず可視 provenance マーカーを数える)。
m="$TMP/m24.html"; perl -0777 -pe 's{</main>}{<ol class="term-xrefs"><li>定義元: OL-FAKE-REF</li></ol>\n</main>}' "$GOOD" > "$m"
expect_fail "★<ol class=term-xrefs> tag-swap 偽 provenance を大域 '定義元:' parity で捕捉" "$m"
m="$TMP/m25.html"; perl -0777 -pe 's{</main>}{<div class="term-xrefs"><li>定義元: DIV-FAKE-REF</li></div>\n</main>}' "$GOOD" > "$m"
expect_fail "★<div class=term-xrefs> tag-swap 偽 provenance を大域 '定義元:' parity で捕捉" "$m"
m="$TMP/m26.html"; perl -0777 -pe 's{</main>}{<div style="font-weight:700">定義元: 全顧客個人情報DB-EXPORT</div>\n</main>}' "$GOOD" > "$m"
expect_fail "★classless <div> の偽 provenance を大域 '定義元:' parity で捕捉" "$m"
m="$TMP/m27.html"; perl -0777 -pe 's{</main>}{<dl class="cover-meta"><dt>機密度</dt><dd>最高機密-FAKEMETA</dd></dl>\n</main>}' "$GOOD" > "$m"
expect_fail "★2個目 <dl class=cover-meta> 捏造 KV を dl 占有数+while//g で捕捉" "$m"
# 28. ★folio-bur round-4 (ceiling-recursion R3 是正): genuine dl 内へ大文字 <DT>/<DD> の偽 KV (内部抽出 case-sensitive の死角)
#   → dt/dd 抽出 case 非依存化で html_meta に乗り set_eq で捕捉。
m="$TMP/m28.html"; perl -0777 -pe 's{(<dl[^>]*class="cover-meta"[^>]*>)}{${1}<DT>機密度</DT><DD>最高機密-UPPERCASE-FAKE</DD>}' "$GOOD" > "$m"
expect_fail "★大文字 <DT>/<DD> 偽 KV (内部抽出 case 死角) を case 非依存 dt/dd 抽出で捕捉" "$m"
# 29-30. ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 までの §2b term-name / §6b gen-meta は double-quote 固定抽出 +
#   占有数 anchor 無しゆえ single-quote マーカー decoy が抽出を逃れ set_eq/chk は genuine のまま PASS、 用語見出し語・footer 生成メタが捏造され素通った。
m="$TMP/m29.html"; perl -0777 -pe "s{</main>}{<h3 class='term-name'>偽用語GHOST</h3>\n</main>}" "$GOOD" > "$m"
expect_fail "★single-quote <h3 class=term-name> 偽見出し語 → term-name 占有数で捕捉" "$m"
m="$TMP/m30.html"; perl -0777 -pe "s{</main>}{<p class='gen-meta'>FABRICATED-GENMETA</p>\n</main>}" "$GOOD" > "$m"
expect_fail "★single-quote <p class=gen-meta> 偽 footer メタ → gen-meta 占有数で捕捉" "$m"
# 31-34. ★folio-bur round-6 (ceiling-recursion R5 是正): 最 load-bearing な term-formal 占有欠如 + novel-marker 系統封鎖。
m="$TMP/m31.html"; perl -0777 -pe "s{</main>}{<dd class='term-formal'>偽の正式定義(FABRICATED)</dd>\n</main>}" "$GOOD" > "$m"
expect_fail "★single-quote <dd class=term-formal> 偽正式定義 → term-formal 占有数で捕捉" "$m"
m="$TMP/m32.html"; perl -0777 -pe "s{</main>}{<dd class=term-formal>偽の正式定義(unquoted)</dd>\n</main>}" "$GOOD" > "$m"
expect_fail "★unquoted <dd class=term-formal> 偽正式定義 → term-formal 占有数で捕捉" "$m"
m="$TMP/m33.html"; perl -0777 -pe "s{</main>}{<p class='evil-novel'>偽の用語(捏造 novel class)</p>\n</main>}" "$GOOD" > "$m"
expect_fail "★novel class 注入を class-token 機械的網羅で捕捉" "$m"
m="$TMP/m34.html"; perl -0777 -pe "s{</main>}{<div data-component='gloss-evil'>偽 component(捏造 novel dc)</div>\n</main>}" "$GOOD" > "$m"
expect_fail "★novel data-component 注入を data-component 機械的網羅で捕捉" "$m"

# 19. verify が GREEN を *決して* 出さない (floor 単独 GREEN 禁止)
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi


# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
m="$TMP/r7g1.html"; perl -0777 -pe 's{</body>}{<div class="summary-card">偽サマリ(捏造)</div></body>}' "$GOOD" > "$m"; expect_fail "R7-glo-a ★summary-card additive (ceiling 残余) を占有==1 で捕捉" "$m"
m="$TMP/r7g2.html"; perl -0777 -pe 's{</body>}{<span class="term-plain">偽の平易語義(捏造)</span></body>}' "$GOOD" > "$m"; expect_fail "R7-glo-b ★term-plain additive を占有==|terms| で捕捉" "$m"
m="$TMP/r7g3.html"; perl -0777 -pe 's{</body>}{<div data-component="doc-cover-band">偽(捏造)</div></body>}' "$GOOD" > "$m"; expect_fail "R7-glo-c ★doc-cover-band additive を占有==1 で捕捉" "$m"
m="$TMP/r7g4.html"; perl -0777 -pe 's{</body>}{<p style="display:none">隠蔽(捏造)</p></body>}' "$GOOD" > "$m"; expect_fail "R7-glo-d ★display:none 隠蔽を display-state guard で捕捉" "$m"

echo ""
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
