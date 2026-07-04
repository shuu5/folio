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

# 13. 可視見出し語 (h4 term-name・folio-229 で domain h3 の下へ h3→h4 降格) を捏造 (data-term="spec" は intact)
m="$TMP/m13.html"; perl -0777 -pe 's{(<h4 class="term-name">)spec(</h4>)}{${1}GHOST${2}}' "$GOOD" > "$m"
expect_fail "可視見出し語 (h4 term-name) 捏造 / 属性 intact" "$m"

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

# 20. ★folio-bur: xref li 可視 "使われる文書: {target}" を捏造 (data-xref-target 属性は intact・visible-text-vs-attribute)
#   ★folio-229: ラベル『定義元:』→『使われる文書:』改称に伴い期待値更新 (改竄検出ロジックは不変)。
m="$TMP/m20.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">)使われる文書: P-3(</li>)}{${1}使われる文書: FAKE-XREF${2}}' "$GOOD" > "$m"
expect_fail "★xref li 可視捏造 (使われる文書: target≠属性) / 属性 intact" "$m"

# 21. ★folio-bur: data-xref-target 属性なしの孤立 li を term-xrefs <ul> 内へ挿入 (orphan-or-count)
m="$TMP/m21.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">使われる文書: P-3</li>)}{${1}<li>GHOST-XREF</li>}' "$GOOD" > "$m"
expect_fail "★孤立 xref li 挿入 (属性なし) を li 総数で捕捉" "$m"

# 22/23. ★folio-bur round-2 (ceiling-recursion): Pin A/B の double-quote 固定の射程外を quote-robust 抽出 + 残差検査で捕捉。
m="$TMP/m22.html"; perl -0777 -pe "s{<li data-xref-target=\"P-3\" data-xref-rel=\"glossary-anchor\">使われる文書: P-3</li>}{<li data-xref-target='P-3' data-xref-rel='glossary-anchor'>使われる文書: 捏造先</li>}" "$GOOD" > "$m"
expect_fail "★single-quote 属性 + 可視捏造 (使われる文書: 捏造先) を quote-robust 可視 set_eq で捕捉" "$m"
m="$TMP/m23.html"; perl -0777 -pe 's{(<li data-xref-target="P-3" data-xref-rel="glossary-anchor">使われる文書: P-3</li>)}{${1}<p>使われる文書: 捏造</p>}' "$GOOD" > "$m"
expect_fail "★term-xrefs ul への非 li タグ混入 (<p>) を残差 whitespace-only 検査で捕捉" "$m"
# 24-27. ★folio-bur round-3 (ceiling-recursion R2 是正): container tag-swap (ol/div) + 別class/classless provenance + 2個目 cover-meta dl。
#   いずれも大域 '使われる文書:' marker parity / cover-meta dl 占有数で捕捉 (anchor の class/タグに依らず可視 provenance マーカーを数える)。
m="$TMP/m24.html"; perl -0777 -pe 's{</main>}{<ol class="term-xrefs"><li>使われる文書: OL-FAKE-REF</li></ol>\n</main>}' "$GOOD" > "$m"
expect_fail "★<ol class=term-xrefs> tag-swap 偽 provenance を大域 '使われる文書:' parity で捕捉" "$m"
m="$TMP/m25.html"; perl -0777 -pe 's{</main>}{<div class="term-xrefs"><li>使われる文書: DIV-FAKE-REF</li></div>\n</main>}' "$GOOD" > "$m"
expect_fail "★<div class=term-xrefs> tag-swap 偽 provenance を大域 '使われる文書:' parity で捕捉" "$m"
m="$TMP/m26.html"; perl -0777 -pe 's{</main>}{<div style="font-weight:700">使われる文書: 全顧客個人情報DB-EXPORT</div>\n</main>}' "$GOOD" > "$m"
expect_fail "★classless <div> の偽 provenance を大域 '使われる文書:' parity で捕捉" "$m"
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

# --- folio-229: domain 区分 (PW-01) + 人間層 usage (PW-02) の新 human 層トークン捏造を封鎖 (§2c) ---
# F229-a. 人間層 term-usage の friendly gloss を捏造 (data-usage-for 属性 intact・可視 text のみ) → tuple set_eq で捕捉
m="$TMP/f229a.html"; perl -0777 -pe 's{(<p class="term-usage" data-audience="human" data-usage-for="spec">)使われる文書: 原則 P-3、原則 P-7(</p>)}{${1}使われる文書: 秘密DB-EXPORT(捏造)${2}}' "$GOOD" > "$m"
expect_fail "★F229-a 人間層 usage friendly gloss 捏造 → term-usage tuple set_eq で捕捉" "$m"
# F229-h. ★folio-229 errata: usage 行を隣接 term-entry へ relocate (大域 emission 順・件数・parity 保存)。
#   spec の usage を除去し ADR カード直下へ挿入 → 大域順は不変ゆえ tuple set_eq(b) は素通るが、 移動先 term-entry の
#   data-term(ADR) と usage の data-usage-for(spec) が食い違うため §2c-usage-binding(a) が親帰属で fail-closed 化する。
m="$TMP/f229h.html"; perl -0777 -pe '
  my $u;
  s{(\n\s*<p class="term-usage" data-audience="human" data-usage-for="spec">.*?</p>)}{ $u=$1; "" }se;
  s{(\n\s*<p class="term-usage" data-audience="human" data-usage-for="ADR">.*?</p>)}{$u$1}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-h relocation 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-h usage 行を隣接カードへ relocate (大域順保存) を data-usage-for 親帰属で捕捉" "$m"; fi
# F229-i. ★folio-229 errata-2 (blind region): 先頭 term(spec)の usage を domain-heading 直下 = *最初の term-entry より前* へ
#   relocate。 大域 emission 順・占有・parity を保存するため errata-1 の (a)block-scope 帰属も (b)tuple set_eq も素通った
#   (green-flip)。 肯定形 (i)per-card 個数 + (ii)総数==slice内総数 で先頭カードの usage 喪失 (orphan) を捕捉する。
m="$TMP/f229i.html"; perl -0777 -pe '
  my $u;
  s{(\n\s*<p class="term-usage" data-audience="human" data-usage-for="spec">.*?</p>)}{ $u=$1; "" }se;
  s{(<h3 class="domain-heading">[^<]*</h3>\n)}{$1$u\n}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-i blind region 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-i 先頭 usage を blind region (最初の term-entry より前) へ relocate を per-card/総数不変条件で捕捉" "$m"; fi
# F229-i2. ★prefix-of-2 変種: 先頭 2 語 (spec, ADR) の usage を順序保持で blind region へ detach。 大域順保存でも per-card=0/総数不足で FAIL。
m="$TMP/f229i2.html"; perl -0777 -pe '
  my ($us,$ua);
  s{(\n\s*<p class="term-usage" data-audience="human" data-usage-for="spec">.*?</p>)}{ $us=$1; "" }se;
  s{(\n\s*<p class="term-usage" data-audience="human" data-usage-for="ADR">.*?</p>)}{ $ua=$1; "" }se;
  s{(<h3 class="domain-heading">[^<]*</h3>\n)}{$1$us$ua\n}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-i2 prefix-of-2 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-i2 prefix-of-2 (先頭2語 usage を順序保持で blind region へ) を per-card/総数不変条件で捕捉" "$m"; fi
# F229-j. ★folio-229 errata-3 (round-3 repro・機械層 term-xrefs li の隣接カード跨ぎ relocate): spec 末尾の P-7 li を ADR の
#   term-xrefs 先頭へ移設。 大域 data-xref-target 順は [P-3,P-7,rules§10.3,…] のまま byte 一致で §5 全大域検査を素通るが、
#   spec カードは P-7 出典喪失・ADR カードは P-7 虚偽帰属 (人間層無傷=desync)。 §5b per-card 完全束縛の xref 系列で捕捉する。
m="$TMP/f229j.html"; perl -0777 -pe '
  my $li; s{(\n\s*<li data-xref-target="P-7"[^>]*>.*?</li>)}{ $li=$1; "" }se;
  s{(<ul class="term-xrefs">)(\s*<li data-xref-target="rules)}{$1$li$2}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-j 機械層 li relocate 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-j 機械層 term-xrefs li の隣接カード跨ぎ relocate (大域順保存) を §5b per-card xref 系列で捕捉" "$m"; fi
# F229-k. ★sweep 代表 (人間可視 term-name h4 の隣接カード跨ぎ relocate): spec の h4 を ADR カード先頭へ移設。 大域 h4 順は保存
#   されるが spec カードが用語名喪失・ADR が spec 名を虚偽表示。 §5b per-card 完全束縛の h4 field で捕捉する (面族の代表)。
m="$TMP/f229k.html"; perl -0777 -pe '
  my $h; s{(\n\s*<h4 class="term-name">spec</h4>)}{ $h=$1; "" }se;
  s{(<section class="term-entry" id="term-ADR"[^>]*>)}{$1$h}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-k term-name relocate 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-k 人間可視 term-name h4 の隣接カード跨ぎ relocate を §5b per-card 完全束縛で捕捉" "$m"; fi
# F229-l. ★folio-229 errata-4 (round-4 repro・plainswap): term-plain の双子属性 data-prose-slot + 注入本文を 2 カード間で
#   対称 swap し data-slot-id は据置。 §5b (data-slot-id per-card) [OK]・§8 (data-prose-slot read-back 注入忠実) [OK] のまま
#   spec カードが ADR の平易定義を表示する帰属詐称。 data-slot-id == data-prose-slot の双子等値検査で捕捉する (三方塞がりの片方 swap)。
m="$TMP/f229l.html"; perl -0777 -pe '
  my ($sps,$sb,$aps,$ab);
  if (/<p class="term-plain" data-slot-id="plain-spec" data-prose-slot="([^"]*)">(.*?)<\/p>/s){ ($sps,$sb)=($1,$2); }
  if (/<p class="term-plain" data-slot-id="plain-ADR" data-prose-slot="([^"]*)">(.*?)<\/p>/s){ ($aps,$ab)=($1,$2); }
  s{<p class="term-plain" data-slot-id="plain-spec" data-prose-slot="[^"]*">.*?</p>}{<p class="term-plain" data-slot-id="plain-spec" data-prose-slot="$aps">$ab</p>}s;
  s{<p class="term-plain" data-slot-id="plain-ADR" data-prose-slot="[^"]*">.*?</p>}{<p class="term-plain" data-slot-id="plain-ADR" data-prose-slot="$sps">$sb</p>}s;
' "$GOOD" > "$m"
if cmp -s "$GOOD" "$m"; then total=$((total+1)); echo "  [SLIP] ★F229-l plainswap 改竄が no-op (perl 構造不一致・vacuous)"; else
  expect_fail "★F229-l plainswap (data-prose-slot+本文 対称 swap・data-slot-id 据置) を双子等値検査で捕捉" "$m"; fi
# F229-b. domain-heading の friendly ラベル/語数を捏造 → domain-heading set_eq で捕捉
m="$TMP/f229b.html"; perl -0777 -pe 's{(<h3 class="domain-heading">)folio-framework の言葉 \(33 語\)(</h3>)}{${1}偽ドメイン (99 語)${2}}' "$GOOD" > "$m"
expect_fail "★F229-b domain-heading label/語数 捏造 → domain-heading set_eq で捕捉" "$m"
# F229-c. 偽 term-domain section を additive 注入 → term-domain 占有 (==|domains|) + id set_eq で捕捉
m="$TMP/f229c.html"; perl -0777 -pe 's{</main>}{<section class="term-domain" id="domain-fake">偽区分(捏造)</section>\n</main>}' "$GOOD" > "$m"
expect_fail "★F229-c 偽 term-domain section additive を占有+id set_eq で捕捉" "$m"
# F229-d. TOC リンク文言を捏造 (domain-heading と desync) → TOC link 文言 set_eq で捕捉
m="$TMP/f229d.html"; perl -0777 -pe 's{(<a href="#domain-folio-closed">)folio-framework の言葉 \(33 語\)(</a>)}{${1}偽TOC文言(捏造)${2}}' "$GOOD" > "$m"
expect_fail "★F229-d TOC link 文言 捏造 (heading desync) → TOC set_eq で捕捉" "$m"
# F229-e. 偽 term-usage を additive 注入 → term-usage 占有 + 大域『使われる文書:』parity で捕捉
m="$TMP/f229e.html"; perl -0777 -pe 's{</body>}{<p class="term-usage">使われる文書: 偽(捏造)</p></body>}' "$GOOD" > "$m"
expect_fail "★F229-e 偽 term-usage additive を占有+大域 parity で捕捉" "$m"
# F229-f. 偽 glossary-toc nav を additive 注入 → glossary-toc 占有 (==1) で捕捉
m="$TMP/f229f.html"; perl -0777 -pe 's{</main>}{<nav class="glossary-toc"><ul><li><a href="#domain-ghost">偽索引</a></li></ul></nav>\n</main>}' "$GOOD" > "$m"
expect_fail "★F229-f 偽 glossary-toc nav additive を占有==1 で捕捉" "$m"
# F229-g. genuine nav 内へ偽 TOC entry を注入 → TOC href set_eq (件数/集合) で捕捉
m="$TMP/f229g.html"; perl -0777 -pe 's{(<a href="#domain-folio-closed">folio-framework の言葉 \(33 語\)</a></li>)}{${1}<li><a href="#domain-ghost">偽索引entry</a></li>}' "$GOOD" > "$m"
expect_fail "★F229-g genuine nav 内 偽 TOC entry を TOC href set_eq で捕捉" "$m"

# --- folio-229 self-review: multi-domain nesting (境界 shift) を §2c-nesting が捕捉 (clinic 3 domain instance) ---
#   folio は単一 domain ゆえ内部境界が無く term-entry↔domain-section の nesting 改竄を露出できない (finding-1)。
#   3 domain の clinic で domain 境界の section-open (term-domain + heading) を 1 term ずらし、 clinic-domain 語
#   (個情法) を engineering 見出し下へ移す。 term-name 順・data-term-domain 順・見出し順・term-entry 総数は保存され
#   旧 floor を素通ったが、 §2c-nesting (直下 term-entry 数 == domain 別語数 + data-term-domain == 親 section id) が捕捉する。
CLINIC_C="$HERE/contract/clinic-appointment.glossary.yaml"
CLINIC_M="$HERE/prose/clinic-glossary.prose.yaml"
"$ASSEMBLE" "$CLINIC_C" > "$TMP/clinic-raw.html" 2>/dev/null
"$INJECT" "$CLINIC_M" "$TMP/clinic-raw.html" "$TMP/clinic-good.html" >/dev/null 2>&1
# baseline: genuine clinic (3 domain) は PASS (nesting テストの前提)。
total=$((total+1))
if "$VERIFY" --filled "$CLINIC_M" "$CLINIC_C" "$TMP/clinic-good.html" >/dev/null 2>&1; then
  echo "  [OK]   clinic baseline (3 domain) 正常生成物は PASS"; pass=$((pass+1))
else echo "  [SLIP] clinic baseline が FAIL (nesting テスト前提崩壊)"; fi
# 境界 shift: engineering の section-open+heading を最終 clinic-domain 語 (個情法) の前へ移し、 個情法を engineering 見出し下へ nest。
m="$TMP/clinic-shift.html"; perl -0777 -pe '
  my $eng = qq{  <section class="term-domain" id="domain-engineering" data-audience="human">\n    <h3 class="domain-heading">実現方式の言葉 (7 語)</h3>\n};
  s/\Q$eng\E//;
  s/(    <section class="term-entry" id="term-appi" )/$eng$1/;
' "$TMP/clinic-good.html" > "$m"
total=$((total+1))
if "$VERIFY" --filled "$CLINIC_M" "$CLINIC_C" "$m" >/dev/null 2>&1; then
  echo "  [SLIP] ★F229-nesting clinic 境界 shift を verify が通過させた (exit 0・§2c-nesting fail-open)"
else
  echo "  [OK]   ★F229-nesting clinic 境界 shift (個情法→engineering 見出し下) を §2c-nesting で捕捉"; pass=$((pass+1)); fi

# --- folio-229 self-review: assemble fail-closed 不変条件の negative test (TDD red→green・finding-2) ---
#   assemble emit_terms には (a) .domains 空 (b) 空/未使用 domain (c) 未知 term.domain (d) 非連続 domain
#   (e) 宣言 domain が terms に不在 (f) xref_gloss 欠落 の exit-1 guard があるが、 従来 selftest/adversarial は整形式
#   contract の happy path しか流さず「guard が実際に発火する」ことが未検証だった (guard が typo で常時 pass=fail-open
#   化しても検出されない)。 malformed contract を食わせ assemble が exit 非0 で拒否することを機械的に実証する。
#   ((e) は述語が (b) と同一 = 宣言 domain に term 無し で (b) が先に発火するゆえ defense-in-depth。 観測可能な
#    malformation〔宣言 domain 未使用〕は F229-asm-b で被覆。)
expect_assemble_fail() { # <label> <contract> — assemble が malformed contract を exit 非0 で拒否すべき
  local label="$1" contract="$2"
  total=$((total+1))
  if "$ASSEMBLE" "$contract" >/dev/null 2>&1; then
    echo "  [SLIP] $label — assemble が malformed contract を通過させた (exit 0・guard 不発火)"
  else
    echo "  [OK]   $label — assemble block (exit 非0)"; pass=$((pass+1))
  fi
}
yq '.domains = []' "$CONTRACT" > "$TMP/mal-a.yaml"
expect_assemble_fail "★F229-asm-a .domains 空 → guard(a) 発火" "$TMP/mal-a.yaml"
yq '.terms[0].domain = "BOGUS-UNKNOWN"' "$CONTRACT" > "$TMP/mal-c.yaml"
expect_assemble_fail "★F229-asm-c 未知 term.domain (domains[] に無い) → guard(c) 発火" "$TMP/mal-c.yaml"
yq '.domains = [{"id":"folio-closed","label":"folio-framework の言葉"},{"id":"extra-dom","label":"追加区分"}] | .terms[1].domain = "extra-dom"' "$CONTRACT" > "$TMP/mal-d.yaml"
expect_assemble_fail "★F229-asm-d 非連続 domain (A-B-A) → guard(d) 発火" "$TMP/mal-d.yaml"
yq '.domains += [{"id":"ghost-dom","label":"未使用区分"}]' "$CONTRACT" > "$TMP/mal-b.yaml"
expect_assemble_fail "★F229-asm-b 宣言 domain に term 無し (空/未使用 domain) → guard(b) 発火" "$TMP/mal-b.yaml"
yq 'del(.xref_gloss["P-3"])' "$CONTRACT" > "$TMP/mal-f.yaml"
expect_assemble_fail "★F229-asm-f xref_gloss 欠落 (cross_ref token 無 gloss) → guard(f) 発火" "$TMP/mal-f.yaml"

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
