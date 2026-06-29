#!/usr/bin/env bash
# folio S4 generator — 敵対回帰テスト
# ceiling review (wf_41fcbde3) が突いた攻撃を、 hardening 後の assembler/verify が
# fail-closed (assemble abort) または verify FAIL で捕捉することを回帰確認する。
#
# usage: test-adversarial.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-srs.sh"
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
# 共通 helper: good.html 内の literal 部分文字列 $2 を $3 へ置換した tamper を作り、 verify FAIL を期待 (mid-value 改竄=順序突合が捕捉)。
# ★folio-bur round-3: 旧版は定義が L651 で初使用 (A86b・L594) より後ろにあり、 全 body_tamper_fail 呼び出しが
#   「command not found」で空振り → stderr エラーは pass/fail を増やさず false GREEN だった (独立 ceiling 検証中に発見)。
#   helper 群と同じ前方位置へ移動して A86b-g (j3/j3a/j3b/j3c/j3d の回帰) を実際に走らせる。
body_tamper_fail() { # label needle replacement
  if python3 -c "
d=open('$TMP/good.html').read()
o='''$2'''; assert o in d, 'needle not found'
open('$TMP/bp.html','w').write(d.replace(o,'''$3''',1))
" 2>/dev/null; then expect_verify_fail "$1" "$BASE" "$TMP/bp.html"; else ng "$1 setup 失敗"; fi
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
echo "verify-srs floor (taxonomy §5 gate A-H + visual-first) の fail-closed:"
SRS="$SCRIPT_DIR/verify-srs.sh"
# gate A-E,G,H (bash) の fail-closed を検査する arm ゆえ重い gate F (playwright) は SRS_SKIP_RENDER で外す
# (gate F の回帰は末尾の render-gate-srs --selftest arm が別途担う)。
expect_srs_pass() { if SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (floor FAIL)"; fi; }
expect_srs_fail() { if SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" >/dev/null 2>&1; then ng "$1 (floor PASS した)"; else ok "$1"; fi; }
# 健全な充填済み artifact を 1 本
bash "$INJ" "$BASE_PROSE" "$TMP/good.html" "$TMP/art.html" >/dev/null 2>&1

# A22. 健全 artifact は floor PASS (ceiling PENDING = exit 0)
expect_srs_pass "A22 健全 artifact は floor PASS (ceiling PENDING)" "$BASE" "$TMP/art.html"
# A23. 空 prose スロット → gate G (prose 充填) で FAIL
sed 's#\(data-slot-id="cover-summary">\)[^<]*#\1#' "$TMP/art.html" > "$TMP/empty.html"
expect_srs_fail "A23 空 prose スロットを gate G が捕捉" "$BASE" "$TMP/empty.html"
# A24. TBD/TODO マーカー → gate G
sed 's#<td class="cond">#<td class="cond">TODO #' "$TMP/art.html" > "$TMP/tbd.html"
expect_srs_fail "A24 TBD/TODO マーカーを gate G が捕捉" "$BASE" "$TMP/tbd.html"
# A25. 孤立要件 (backward 空) → gate C-D
cp "$BASE" "$TMP/orphreq.yaml"; yq -i '.requirements[0].trace.backward = []' "$TMP/orphreq.yaml"
bash "$ASM" "$TMP/orphreq.yaml" "$TMP/oa.html" 2>/dev/null; bash "$INJ" "$BASE_PROSE" "$TMP/oa.html" "$TMP/of.html" 2>/dev/null
expect_srs_fail "A25 孤立要件 (出所なし) を gate C-D が捕捉" "$TMP/orphreq.yaml" "$TMP/of.html"
# A26. sync-meta 欠落 → gate H
sed 's#data-component="fidelity-sync-meta"#data-component="zzz"#' "$TMP/art.html" > "$TMP/nometa.html"
expect_srs_fail "A26 fidelity-sync-meta 欠落を gate H が捕捉" "$BASE" "$TMP/nometa.html"
# A27. gate A 凍結集合の MUST 部品欠落 (actor-stakeholder-table) → gate A
sed 's#data-component="actor-stakeholder-table"#data-component="zzz"#' "$TMP/art.html" > "$TMP/noactor.html"
expect_srs_fail "A27 凍結 MUST 部品 (actor-stakeholder-table) 欠落を gate A が捕捉" "$BASE" "$TMP/noactor.html"
# A28. gate H 値の空白化 (<b>  </b>) → gate H 非空白要求
sed 's#機械SSoT: <b>[^<]*</b>#機械SSoT: <b>  </b>#' "$TMP/art.html" > "$TMP/wsmeta.html"
expect_srs_fail "A28 sync-meta 値の空白化を gate H が捕捉" "$BASE" "$TMP/wsmeta.html"
# A28b. ★ds8 ceiling: 機械SSoT を別 contract 名へ偽装 (非空だが偽 provenance) → gate H 厳密一致 (==basename) で捕捉
#       (非空のみ照合だと別ソースからの生成と詐称できる fail-open。 verify-adr の可視 echo 厳密一致を SRS 決定的 footer へ横展開)。
sed 's#機械SSoT: <b>[^<]*</b>#機械SSoT: <b>totally-different-source.yaml</b>#' "$TMP/art.html" > "$TMP/fakessot.html"
expect_srs_fail "A28b ★偽 機械SSoT (別 contract 名) を gate H 厳密一致で捕捉" "$BASE" "$TMP/fakessot.html"
# A28c. ★ds8 ceiling: 検証状態を固定2状態外の偽値へ詐称 (『全 gate PASS・GREEN 認定済』) → gate H 厳密一致 (∈固定2状態) で捕捉
sed 's#検証状態: <b>[^<]*</b>#検証状態: <b>全 gate PASS・GREEN 認定済み (ウソ)</b>#' "$TMP/art.html" > "$TMP/fakevstate.html"
expect_srs_fail "A28c ★偽 検証状態 (固定2状態外) を gate H 厳密一致で捕捉" "$BASE" "$TMP/fakevstate.html"
# A28d. ★ds8 ceiling round-2: <b> 値は正規のまま </b> の *外* (= </div> 前) に偽 provenance を可視追記 → gate H block-scoped 可視テキスト厳密一致で捕捉
#       (round-1 の value-only 照合は </b> 後の平文が死角だった。 sync-meta div をブロックごと可視テキスト照合する block-scoped で封鎖)。
sed 's#検証状態: <b>structure[^<]*</b>#&  全 gate GREEN・出荷承認#' "$TMP/art.html" > "$TMP/appendmeta.html"
expect_srs_fail "A28d ★sync-meta </b>外への偽 provenance 追記を block-scoped 可視テキストで捕捉" "$BASE" "$TMP/appendmeta.html"
# A28e. ★ds8 ceiling round-3: 表紙 cover-meta の 機能要件 KV を可視改竄 → 決定的再導出突合で FAIL (全 pack 共通の cover-meta gap・ADR/research と parity)
sed 's#<span class="k">機能要件</span><span class="v">[^<]*</span>#<span class="k">機能要件</span><span class="v">999件 (FR1–FR99)</span>#' "$TMP/art.html" > "$TMP/covermeta.html"
expect_srs_fail "A28e ★cover-meta 機能要件 改竄を再導出突合で捕捉" "$BASE" "$TMP/covermeta.html"
# A29. gate G 日本語 placeholder (セルまるごと 未定) → gate G
sed 's#<td class="cond">[^<]*#<td class="cond">未定#' "$TMP/art.html" > "$TMP/jph.html"
expect_srs_fail "A29 日本語 placeholder (未定) セルを gate G が捕捉" "$BASE" "$TMP/jph.html"
# A30. gate D data-req-id 重複 → gate D
sed '0,/data-req-id="FR2"/{s/data-req-id="FR2"/data-req-id="FR1"/}' "$TMP/art.html" > "$TMP/dupid.html"
expect_srs_fail "A30 data-req-id 重複を gate D が捕捉" "$BASE" "$TMP/dupid.html"
# A31. gate G prose *中段* の placeholder (語境界) → gate G (anchor 撤廃の回帰)
sed 's#\(data-slot-id="cover-summary">\)[^<]*#\1この約束は TBD のため後日確定#' "$TMP/art.html" > "$TMP/midtbd.html"
expect_srs_fail "A31 prose 中段の TBD (語境界) を gate G が捕捉" "$BASE" "$TMP/midtbd.html"
# A31b. 語内包含 (TODOリスト管理) は誤検出しない (false-FAIL 回帰)
sed 's#\(data-slot-id="cover-summary">\)[^<]*#\1注文のTODOリスト管理を扱う仕組み#' "$TMP/art.html" > "$TMP/notodo.html"
expect_srs_pass "A31b 語内包含 (TODOリスト) は gate G 誤検出しない" "$BASE" "$TMP/notodo.html"
# A32. gate D 可視 fid 捏造 (data-req-id と乖離) → gate D
sed '0,/<span class="fid">FR1<\/span>/{s#<span class="fid">FR1</span>#<span class="fid">FR-NISE</span>#}' "$TMP/art.html" > "$TMP/fidfake.html"
expect_srs_fail "A32 可視 fid 捏造 (data-req-id 乖離) を gate D が捕捉" "$BASE" "$TMP/fidfake.html"
# A33. gate B 実 dark media をコメント擬装に置換 → gate B (@media 規則ブロックを要求・文字列擬装を弾く)
perl -0777 -pe 's!\@media\s*\([^)]*prefers-color-scheme:\s*dark[^)]*\)\s*\{!/* prefers-color-scheme: dark is a TODO comment */ .x {!gs' "$TMP/art.html" > "$TMP/darkfake.html"
expect_srs_fail "A33 dark media のコメント擬装を gate B が捕捉" "$BASE" "$TMP/darkfake.html"

# ★folio-lzz: navigable anchor gate (案A 裸ミラー・cross-doc deep-link 着地点) の fail-closed。
# A33b. 要件 navigable id ミラー不一致 (id 値だけ偽装・data-req-id 温存) → anchor gate 固有の検出
#       (within-doc tuple は id を [^"]* で無視ゆえ捕捉できない = anchor gate だけが破れを検出)。
sed 's# id="FR2"# id="FR-NISE"#' "$TMP/art.html" > "$TMP/anchormis.html"
expect_srs_fail "A33b ★要件 navigable id ミラー不一致を anchor gate が捕捉" "$BASE" "$TMP/anchormis.html"
# A33c. 要件 navigable id 欠落 (anchor 不在 = cross-doc #FR2 が 404 復活) → anchor gate が捕捉。
sed 's# id="FR2"##' "$TMP/art.html" > "$TMP/anchordrop.html"
expect_srs_fail "A33c ★要件 navigable id 欠落 (404 復活) を anchor gate が捕捉" "$BASE" "$TMP/anchordrop.html"
# A33d. NFR navigable id 欠落 → anchor gate (NFR set) が捕捉。
sed 's#nfr-metric-row" id="NFR1"#nfr-metric-row"#' "$TMP/art.html" > "$TMP/anchornfr.html"
expect_srs_fail "A33d ★NFR navigable id 欠落を anchor gate が捕捉" "$BASE" "$TMP/anchornfr.html"
# A33e. 受入 navigable id 欠落 → anchor gate (受入 set) 固有の検出 (verify-fab 受入 regex は内側 div ゆえ素通る)。
sed 's#<div class="ac" id="AC1"#<div class="ac"#' "$TMP/art.html" > "$TMP/anchorac.html"
expect_srs_fail "A33e ★受入 navigable id 欠落を anchor gate が捕捉" "$BASE" "$TMP/anchorac.html"
# ★folio-lzz ceiling [必須-1] 回帰: 非 component 要素へ同 id を注入 (collision) → fragment が tree-order 先頭の偽要素へ着地する
#   fail-open を global uniqueness gate が捕捉。 set_eq は component 行しか見ないため collision は uniqueness gate 固有の検出。
# A33f. double-quote collision decoy → uniqueness FAIL。
sed 's#<body>#<body><a id="FR2"></a>#' "$TMP/art.html" > "$TMP/coll_dq.html"
expect_srs_fail "A33f ★id collision (double-quote decoy) を uniqueness gate が捕捉" "$BASE" "$TMP/coll_dq.html"
# A33g. single-quote collision decoy (quote-robust) → uniqueness FAIL。
sed "s#<body>#<body><a id='FR2'></a>#" "$TMP/art.html" > "$TMP/coll_sq.html"
expect_srs_fail "A33g ★id collision (single-quote decoy・quote-robust) を uniqueness gate が捕捉" "$BASE" "$TMP/coll_sq.html"
# A33h. 数値文字参照 collision decoy (FR&#50; = FR2・entity-robust) → uniqueness FAIL。
perl -0777 -pe 's{<body>}{<body><a id="FR&#50;"></a>}' "$TMP/art.html" > "$TMP/coll_ent.html"
expect_srs_fail "A33h ★id collision (数値文字参照 decoy・entity-robust) を uniqueness gate が捕捉" "$BASE" "$TMP/coll_ent.html"
# A33i. 大文字 ID 属性 collision decoy (HTML 属性名は case-insensitive・case-robust) → uniqueness FAIL。
sed 's#<body>#<body><a ID="FR2"></a>#' "$TMP/art.html" > "$TMP/coll_uc.html"
expect_srs_fail "A33i ★id collision (大文字 ID 属性・case-robust) を uniqueness gate が捕捉" "$BASE" "$TMP/coll_uc.html"
# A33j. ★ceiling round-2: HTML5 self-closing slash separator collision (<a/id="FR2"> は valid な id=FR2 要素を生む)。
#   旧 (?<=\s) は / を空白と見なさず取りこぼした fail-open を (?<![\w-]) attribute-name 境界が捕捉。
perl -0777 -pe 's{<body>}{<body><a/id="FR2"></a>}' "$TMP/art.html" > "$TMP/coll_sl.html"
expect_srs_fail "A33j ★id collision (HTML5 slash separator <a/id=…>) を attribute-name 境界 gate が捕捉" "$BASE" "$TMP/coll_sl.html"
# A33k/l. ★ceiling round-3: semicolon-less 数値文字参照 collision (HTML5 は &#50/&#x32 を ; 無しでも decode)。
#   旧 ; 必須 decode が見逃した fail-open を ;? optional terminator が捕捉 (10進・16進)。
perl -0777 -pe 's{<body>}{<body><a id="FR&#50"></a>}' "$TMP/art.html" > "$TMP/coll_sld.html"
expect_srs_fail "A33k ★id collision (semicolon-less 10進実体 FR&#50) を entity-robust gate が捕捉" "$BASE" "$TMP/coll_sld.html"
perl -0777 -pe 's{<body>}{<body><a id="FR&#x32"></a>}' "$TMP/art.html" > "$TMP/coll_slh.html"
expect_srs_fail "A33l ★id collision (semicolon-less 16進実体 FR&#x32) を entity-robust gate が捕捉" "$BASE" "$TMP/coll_slh.html"
# A33m/n. ★ceiling round-4: capital-X 16進数値参照 (HTML5 は &#X.. の大文字 X も 16進受理)。
#   旧 lowercase-x リテラル decode が見逃した fail-open を [xX] が捕捉 (;有/;無)。char-ref 文法枯渇。
perl -0777 -pe 's{<body>}{<body><a id="FR&#X32;"></a>}' "$TMP/art.html" > "$TMP/coll_Xc.html"
expect_srs_fail "A33m ★id collision (capital-X 16進実体 FR&#X32;) を entity-robust gate が捕捉" "$BASE" "$TMP/coll_Xc.html"
perl -0777 -pe 's{<body>}{<body><a id="FR&#X32"></a>}' "$TMP/art.html" > "$TMP/coll_Xn.html"
expect_srs_fail "A33n ★id collision (capital-X 16進実体 ;無 FR&#X32) を entity-robust gate が捕捉" "$BASE" "$TMP/coll_Xn.html"

echo
echo "gate F (render-gate-srs) detector の検出力 (selftest):"
# A34. gate F detector — low-contrast/overflow/overlap × light/dark の kind 完全一致発火を fixture で検証。
# 重い playwright ゆえ renderer 在環境でのみ実行 (CI=pip / host=uv)。 不在なら honest SKIP (count しない)。
RGRUN=""
if python3 -c "import playwright" >/dev/null 2>&1; then RGRUN="python3"
elif command -v uv >/dev/null 2>&1; then RGRUN="uv run --with playwright==1.60.0 python"
elif [[ -x "$HOME/.local/bin/uv" ]]; then RGRUN="$HOME/.local/bin/uv run --with playwright==1.60.0 python"
fi
gateF_skipped=0
if [[ -z "$RGRUN" ]]; then
  echo "  [SKIP] A34 gate F detector selftest (playwright renderer 不在 — CI/uv で実行)"; gateF_skipped=1
elif $RGRUN "$SCRIPT_DIR/render-gate-srs.py" --selftest >/dev/null 2>&1; then
  ok "A34 gate F detector selftest (low-contrast/overflow/overlap × light/dark) 全 PASS"
else
  ng "A34 gate F detector selftest が FAIL"
fi

# A35. probe-srs.js の幾何定数が probe.js (ADR-0037 SSoT) と一致するか (literal 複製の drift 検知)。
REF_PROBE="$SCRIPT_DIR/../../../tests/render-gate/probe.js"
if [[ -f "$REF_PROBE" ]]; then
  ref_htol=$(grep -oE 'H_OVERFLOW_TOL = [0-9.]+' "$REF_PROBE" | grep -oE '[0-9.]+$')
  ref_frac=$(grep -oE 'NAV_OVERLAP_FRAC = [0-9.]+' "$REF_PROBE" | grep -oE '[0-9.]+$')
  srs_htol=$(grep -oE 'H_OVERFLOW_TOL = [0-9.]+' "$SCRIPT_DIR/probe-srs.js" | grep -oE '[0-9.]+$')
  srs_frac=$(grep -oE 'OVERLAP_FRAC = [0-9.]+' "$SCRIPT_DIR/probe-srs.js" | head -1 | grep -oE '[0-9.]+$')
  if [[ -n "$ref_htol" && "$ref_htol" == "$srs_htol" && "$ref_frac" == "$srs_frac" ]]; then
    ok "A35 probe-srs.js の幾何定数が probe.js と一致 (H_OVERFLOW_TOL=$srs_htol / overlap-frac=$srs_frac)"
  else
    ng "A35 幾何定数 drift (probe.js htol=$ref_htol frac=$ref_frac / srs htol=$srs_htol frac=$srs_frac)"
  fi
else
  echo "  [SKIP] A35 probe.js 不在で定数 drift 未検査"
fi

echo
echo "within-doc 決定的フィールド値 (dty / folio-dty) の fail-closed:"
# ★ds8 round-4 で繰延した SRS floor の決定的可視フィールド値完全性。 7b の件数のみ検証では値改竄が件数保存のまま
#   素通った fail-open を、 7e の順序付き再導出突合 (cxid/drid と同型) が捕捉することを回帰確認する。 good.html は A7 で生成済み。
# A36. goals.headline 改竄 (ゴール文の捏造) → 7e (a)
sed 's#<p class="ct">二重課金しない</p>#<p class="ct">詐欺してもよい</p>#' "$TMP/good.html" > "$TMP/g_head.html"
expect_verify_fail "A36 goals.headline 改竄を 7e が捕捉" "$BASE" "$TMP/g_head.html"
# A37. actor.name 改竄 → 7e (b)
sed 's#<div class="nm">購入者#<div class="nm">攻撃者#' "$TMP/good.html" > "$TMP/g_name.html"
expect_verify_fail "A37 actor.name 改竄を 7e が捕捉" "$BASE" "$TMP/g_name.html"
# A38. 外部バッジ除去 (external 真偽の詐称) → 7e (b) compound 再構築
sed 's#決済代行<span class="ext-badge">外部</span>#決済代行#' "$TMP/good.html" > "$TMP/g_ext.html"
expect_verify_fail "A38 外部バッジ除去 (external 詐称) を 7e が捕捉" "$BASE" "$TMP/g_ext.html"
# A39. upper_needs.origin 改竄 (出所の捏造) → 7e (c)
sed 's#<span class="origin">経営方針 2026Q1</span>#<span class="origin">捏造の出所</span>#' "$TMP/good.html" > "$TMP/g_origin.html"
expect_verify_fail "A39 upper_needs.origin 改竄を 7e が捕捉" "$BASE" "$TMP/g_origin.html"
# A40. rtm-grid 列見出し改竄 → 7e (d)
sed 's#<th class="grp">N-1 二重課金防止</th>#<th class="grp">N-1 ニセ見出し</th>#' "$TMP/good.html" > "$TMP/g_grp.html"
expect_verify_fail "A40 rtm 列見出し改竄を 7e が捕捉" "$BASE" "$TMP/g_grp.html"
# A41. acceptance.metric_v 改竄 (合否しきい値の捏造『1/2 だけ成功』→『999/9』) → 7e (e)
sed 's#<span class="v">1/2</span>#<span class="v">999/9</span>#' "$TMP/good.html" > "$TMP/g_mv.html"
expect_verify_fail "A41 acceptance 合否しきい値 (metric_v) 改竄を 7e が捕捉" "$BASE" "$TMP/g_mv.html"
# A42. acceptance.links 改竄 (aid の検証対象要件すり替え) → 7e (e)
sed 's#<div class="aid">AC1 ← FR1/FR4</div>#<div class="aid">AC1 ← FR99/FR98</div>#' "$TMP/good.html" > "$TMP/g_aid.html"
expect_verify_fail "A42 acceptance.links (aid) 改竄を 7e が捕捉" "$BASE" "$TMP/g_aid.html"
# A43. nfr-hero big 改竄 (表紙 hero 数値『1.0秒』→『99.0秒』) → 7e (f)
sed 's#<div class="big">1.0<span class="u">秒</span>#<div class="big">99.0<span class="u">秒</span>#' "$TMP/good.html" > "$TMP/g_hero.html"
expect_verify_fail "A43 nfr-hero 数値 (big) 改竄を 7e が捕捉" "$BASE" "$TMP/g_hero.html"
# A44. nfr-hero cat 改竄 (区分『速さ』→『遅さ』) → 7e (f)
sed 's#<div class="cat">速さ</div>#<div class="cat">遅さ</div>#' "$TMP/good.html" > "$TMP/g_cat.html"
expect_verify_fail "A44 nfr-hero 区分 (cat) 改竄を 7e が捕捉" "$BASE" "$TMP/g_cat.html"
# A45. data-source (rationale_source 接地メタ) 改竄 → 7e (g) 集合突合
sed 's#data-source="N-2" data-slot-id="rationale-FR1"#data-source="N-99" data-slot-id="rationale-FR1"#' "$TMP/good.html" > "$TMP/g_ds.html"
expect_verify_fail "A45 data-source 改竄を 7e (集合突合) が捕捉" "$BASE" "$TMP/g_ds.html"
# A46. ★wrapper-tag swap で偽値を隠す試み (ct→span) → 値が抽出列から脱落し順序不一致で捕捉 (ds8 不動点の検証)
sed 's#<p class="ct">二重課金しない</p>#<span class="ct">詐欺してよい</span>#' "$TMP/good.html" > "$TMP/g_swap.html"
expect_verify_fail "A46 wrapper-tag swap (ct→span)+偽値を 7e 順序突合が捕捉" "$BASE" "$TMP/g_swap.html"

echo
echo "within-doc 本体フィールド (dty round-2 / 独立 ceiling 完全列挙) の fail-closed:"
# ★dty round-1 ceiling (wf_5d54fb6b) が §7e の *部分列挙* を看破し実証した 9+ の fail-open を §7f で塞いだ回帰。
#   ceiling が「test-adversarial 55/55 は fixture-disjoint の見かけ green = これら攻撃は suite 未収録」と指摘した穴を固定する。
# A47. ★blocker: 要件 ID の consistent rename (fid + data-req-id を整合させ FR1→FR99) → §7f(h) が contract id 三者一致で捕捉
perl -0777 -pe 's#data-req-id="FR1"#data-req-id="FR99"#; s#<span class="fid">FR1</span>#<span class="fid">FR99</span>#' "$TMP/good.html" > "$TMP/g_rename.html"
expect_verify_fail "A47 ★要件 ID consistent rename (fid+data-req-id) を 7f(h) が捕捉" "$BASE" "$TMP/g_rename.html"
# A48. EARS 種別 (class+可視ラベル) 改竄 (きっかけ→禁止) → §7f(h) が .ears.pattern 写像と突合
perl -0777 -pe 's#<span class="ears trigger">きっかけ</span>#<span class="ears forbid">禁止</span>#' "$TMP/good.html" > "$TMP/g_ears.html"
expect_verify_fail "A48 EARS 種別 (class+label) 改竄を 7f(h) が捕捉" "$BASE" "$TMP/g_ears.html"
# A49. nfr-metric-row の可視 nid 捏造 (§7e source-trace nid と非対称だった穴) → §7f(i)
perl -0777 -pe 's#(<tr data-component="nfr-metric-row" id="[^"]*"><td><span class="nid">)NFR1(</span>)#${1}NFRX${2}#' "$TMP/good.html" > "$TMP/g_nnid.html"
expect_verify_fail "A49 nfr 表 nid 捏造を 7f(i) が捕捉" "$BASE" "$TMP/g_nnid.html"
# A50. ★要件行 *内* の priority ラベル改竄 (legend の静的 badge でなく row-scope) → §7f(h)
perl -0777 -pe 's#(data-req-id="FR1".*?priority-badge">)必須(</span> <span class="vmeth">)#${1}任意${2}#s' "$TMP/good.html" > "$TMP/g_prio.html"
expect_verify_fail "A50 要件行内 priority ラベル改竄を 7f(h) が捕捉 (legend と非混線)" "$BASE" "$TMP/g_prio.html"
# A51. 要件行 vmethod 改竄 (T→D・両方 valid letter ゆえ gate D 集合検査を貫通) → §7f(h) 順序値突合
perl -0777 -pe 's#(data-req-id="FR1".*?<span class="vmeth">)T(</span>)#${1}D${2}#s' "$TMP/good.html" > "$TMP/g_vm.html"
expect_verify_fail "A51 要件行 vmethod 改竄 (T→D) を 7f(h) が捕捉" "$BASE" "$TMP/g_vm.html"
# A52. nfr 区分 (category) 改竄 → §7f(i)
perl -0777 -pe 's#(nfr-metric-row" id="[^"]*"><td><span class="nid">NFR1</span></td><td>)性能(</td>)#${1}捏造区分${2}#' "$TMP/good.html" > "$TMP/g_cat.html"
expect_verify_fail "A52 nfr category 改竄を 7f(i) が捕捉" "$BASE" "$TMP/g_cat.html"
# A53. constraint id (cid2) 改竄 → §7f(k)
perl -0777 -pe 's#<td class="cid2">CON1</td>#<td class="cid2">CONX</td>#' "$TMP/good.html" > "$TMP/g_cid.html"
expect_verify_fail "A53 constraint id (cid2) 改竄を 7f(k) が捕捉" "$BASE" "$TMP/g_cid.html"
# A54. constraint label 改竄 → §7f(k)
perl -0777 -pe 's#<td class="cl">決済方式</td>#<td class="cl">捏造ラベル</td>#' "$TMP/good.html" > "$TMP/g_clbl.html"
expect_verify_fail "A54 constraint label 改竄を 7f(k) が捕捉" "$BASE" "$TMP/g_clbl.html"
# A55. 規制バッジ法令名 改竄 (法令 PCI DSS→でたらめ法) → §7f(k)
perl -0777 -pe 's#法令 PCI DSS#法令 でたらめ法#' "$TMP/good.html" > "$TMP/g_reg.html"
expect_verify_fail "A55 規制バッジ法令名 改竄を 7f(k) が捕捉" "$BASE" "$TMP/g_reg.html"
# A56. rtm 行ラベル (span.lbl) 改竄 → §7f(j)
perl -0777 -pe 's#<span class="lbl">在庫引当</span>#<span class="lbl">捏造ラベル</span># if !$d++' "$TMP/good.html" > "$TMP/g_lbl.html"
expect_verify_fail "A56 rtm 行ラベル (lbl) 改竄を 7f(j) が捕捉" "$BASE" "$TMP/g_lbl.html"
# A57. actor tint (可視色 attr) 改竄 (brand→bad) → §7f(l)
perl -0777 -pe 's#(class="av" style="background:var\(--)brand(\)")#${1}bad${2}# if !$d++' "$TMP/good.html" > "$TMP/g_tint.html"
expect_verify_fail "A57 actor tint (可視色 attr) 改竄を 7f(l) が捕捉" "$BASE" "$TMP/g_tint.html"

# ★dty round-2 ceiling (wf_997ee765) が看破した §7f 自身の兄弟欠陥 (count parity 欠落 / decoy 注入) の回帰。
#   perl の Japanese-text 置換は silent fail しうる (ceiling が偽陽性を踏んだ) ため python で landed を assert してから検査する。
# A58. ★priority/vmeth decoy 注入: §7f(h) の非貪欲 .*? が末尾の正規対を拾い、可視の虚偽 prio/vmeth を素通す穴 → marker 占有数パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'
n='<td class=\"resp\"><span class=\"prio should\" data-component=\"priority-badge\">推奨</span> <span class=\"vmeth\">D</span>'
assert o in d
open('$TMP/g_decoy.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A58 ★priority/vmeth decoy 注入を marker 占有数パリティが捕捉" "$BASE" "$TMP/g_decoy.html"; else ng "A58 setup 失敗"; fi
# A59. ★ghost 要件IDバッジ (fid) を自由文セルへ注入 → global fid 占有数 == |requirements| パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'
n='<td class=\"resp\"><span class=\"fid\">FR-捏造</span>'
assert o in d
open('$TMP/g_gfid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A59 ★ghost fid バッジ注入を global fid 占有数パリティが捕捉" "$BASE" "$TMP/g_gfid.html"; else ng "A59 setup 失敗"; fi
# A60. ★ghost ニーズIDバッジ (nid) を注入 → global nid 占有数 == |upper_needs|+|nfr| パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'
n='<td class=\"resp\"><span class=\"nid\">N-捏造</span>'
assert o in d
open('$TMP/g_gnid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A60 ★ghost nid バッジ注入を global nid 占有数パリティが捕捉" "$BASE" "$TMP/g_gnid.html"; else ng "A60 setup 失敗"; fi
# ★dty round-3 ceiling (wf_97d52cb2) が看破した count anchor 自身の兄弟 + 後退 scope の漏れ。
# A61. ★single-quote ghost fid (class='fid') — double-quote literal grep を素通る → quote 非依存 occurrence で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=\\'fid\\'>FR99</span>'
assert o in d and \"class='fid'\" in n
open('$TMP/g_sqfid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A61 ★single-quote ghost fid を quote 非依存 占有数で捕捉" "$BASE" "$TMP/g_sqfid.html"; else ng "A61 setup 失敗"; fi
# A62. ★single-quote ghost nid
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=\\'nid\\'>N-99</span>'
assert o in d
open('$TMP/g_sqnid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A62 ★single-quote ghost nid を quote 非依存 占有数で捕捉" "$BASE" "$TMP/g_sqnid.html"; else ng "A62 setup 失敗"; fi
# A63. ★chrome (req-row|legend 外) への ghost priority-badge — row-scope の死角 → global occurrence で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='</h1>'; n='</h1><span class=\"prio must\" data-component=\"priority-badge\">必須</span>'
assert o in d
open('$TMP/g_chprio.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A63 ★chrome への ghost priority-badge を global 占有数で捕捉" "$BASE" "$TMP/g_chprio.html"; else ng "A63 setup 失敗"; fi
# A64. ★chrome への ghost vmeth
if python3 -c "
d=open('$TMP/good.html').read()
o='</h1>'; n='</h1><span class=\"vmeth\">D</span>'
assert o in d
open('$TMP/g_chvm.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A64 ★chrome への ghost vmeth を global 占有数で捕捉" "$BASE" "$TMP/g_chvm.html"; else ng "A64 setup 失敗"; fi
# A65. ★rtm 行見出しの可視要件 id (FR1→FR99・fid は据置=tuple 非該当) → rtm 行見出し突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<tr><th>FR1 <span class=\"lbl\">'; n='<tr><th>FR99 <span class=\"lbl\">'
assert o in d
open('$TMP/g_rtmid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A65 ★rtm 行見出し id 改竄を行見出し突合が捕捉" "$BASE" "$TMP/g_rtmid.html"; else ng "A65 setup 失敗"; fi
# A66. ★受入ドット可視テキスト (AC1→AC999・data-acc-link attr 据置) → attr↔可視 echo 突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='data-acc-link=\"FR1__AC1\">AC1</span>'; n='data-acc-link=\"FR1__AC1\">AC999</span>'
assert o in d
open('$TMP/g_accv.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A66 ★受入ドット可視改竄を attr↔可視 echo 突合が捕捉" "$BASE" "$TMP/g_accv.html"; else ng "A66 setup 失敗"; fi
# A67. ★自己予見の兄弟: delete-legend + add-row (count 保存攻撃) — legend chip を 1 個消し req 行へ偽 badge を足すと
#   global occurrence 不変・tuple は末尾を拾い素通る → *要件行内* occurrence パリティ (legend と独立) で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
leg='<span class=\"prio must\" data-component=\"priority-badge\">必須</span>'
o='<td class=\"resp\">'
n='<td class=\"resp\"><span class=\"prio should\" data-component=\"priority-badge\">推奨</span>'
assert leg in d and o in d
open('$TMP/g_dla.html','w').write(d.replace(leg,'',1).replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A67 ★delete-legend+add-row (count 保存) を 要件行内 占有数で捕捉" "$BASE" "$TMP/g_dla.html"; else ng "A67 setup 失敗"; fi
# A68. ★unquoted ghost fid (class=fid・有効 HTML・ブラウザ描画) — quote literal grep を素通る → token-match で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=fid>FR99</span>'
assert o in d
open('$TMP/g_uqfid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A68 ★unquoted ghost fid を token-match 占有数で捕捉" "$BASE" "$TMP/g_uqfid.html"; else ng "A68 setup 失敗"; fi
# A69. ★multi-class ghost fid (class=\"y fid\"・.fid 適用) — fid が 2 番目 class でも token-match で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=\"y fid\">FR99</span>'
assert o in d
open('$TMP/g_mcfid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A69 ★multi-class ghost fid を token-match 占有数で捕捉" "$BASE" "$TMP/g_mcfid.html"; else ng "A69 setup 失敗"; fi
# ★round-4 ceiling (不完全=session limit で 1/5 完走) の唯一 lens + admin 自力点検が看破した case / class-prio 兄弟。
# A70. ★大文字属性名 ghost (CLASS="fid"・Class=fid) — HTML 属性名は case-insensitive ゆえブラウザ描画される → count_attr_token (?i:) で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span CLASS=\"fid\">FR99</span>'
assert o in d
open('$TMP/g_CLfid.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A70 ★大文字属性名 CLASS=fid ghost を case 非依存 token-match で捕捉" "$BASE" "$TMP/g_CLfid.html"; else ng "A70 setup 失敗"; fi
# A71. ★class-prio-only ghost (data-component 無し・legend 推奨と同型で .prio 描画) — data-component count を素通る → 可視 class prio count で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=\"prio must\">必須</span>'
assert o in d
open('$TMP/g_cponly.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A71 ★class-prio-only ghost (data-comp 無し) を 可視 class prio 占有数で捕捉" "$BASE" "$TMP/g_cponly.html"; else ng "A71 setup 失敗"; fi
# A72. ★大文字 DATA-COMPONENT + 大文字属性名の統制値 ghost (CLASS="ears forbid") を case 非依存 token-match で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span CLASS=\"ears forbid\">禁止</span>'
assert o in d
open('$TMP/g_CLears.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A72 ★大文字 CLASS=ears ghost を case 非依存 token-match で捕捉" "$BASE" "$TMP/g_CLears.html"; else ng "A72 setup 失敗"; fi
# A73. ★acc-dot の class を大文字化して可視チェックを回避 + 可視改竄 (data-acc-link 据置で set_eq 通過) → data-acc-link アンカーで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<span class=\"dot ac\" data-acc-link=\"FR1__AC1\">AC1</span>'
n='<span CLASS=\"dot ac\" data-acc-link=\"FR1__AC1\">AC999</span>'
assert o in d
open('$TMP/g_adcase.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A73 ★acc-dot CLASS 大文字化+可視改竄を data-acc-link アンカーで捕捉" "$BASE" "$TMP/g_adcase.html"; else ng "A73 setup 失敗"; fi
# ★round-5 ceiling (wf_ad9f22bc) が看破した HTML 属性構文 robustness の残り 4 兄弟 (round-6 で封鎖)。
# A74. ★acc-dot nested-content (<b>AC999</b>) — [^<]* が空縮退し要素脱落 → marker-keyed nested-reject で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<span class=\"dot ac\" data-acc-link=\"FR1__AC1\">AC1</span>'; n='<span class=\"dot ac\" data-acc-link=\"FR1__AC1\"><b>AC999</b></span>'
assert o in d
open('$TMP/g_accnest.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A74 ★acc-dot nested-content (<b>) を nested-reject で捕捉" "$BASE" "$TMP/g_accnest.html"; else ng "A74 setup 失敗"; fi
# A75. ★値 grep case-drop+decoy (goals.headline ct): 偽 class=\"CT\" の <p> で詐欺文を描画 + 同値 class=\"ct\" decoy で列保存 → ct count-parity で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
import re
m=re.search(r'<p class=\"ct\">[^<]*</p>', d); assert m
frag=m.group(0)
n='<p class=\"CT\">詐欺:'+frag[len('<p class=\"ct\">'):-4]+'</p>'+frag
open('$TMP/g_ctdrop.html','w').write(d.replace(frag,n,1))
" 2>/dev/null; then expect_verify_fail "A75 ★ct case-drop+decoy (可視詐欺文) を ct count-parity で捕捉" "$BASE" "$TMP/g_ctdrop.html"; else ng "A75 setup 失敗"; fi
# A76. ★値 grep case-drop+decoy (constraint.label cl)
if python3 -c "
d=open('$TMP/good.html').read()
import re
m=re.search(r'<td class=\"cl\">[^<]*</td>', d); assert m
frag=m.group(0)
n='<td class=\"CL\">捏造制約ラベル</td>'+frag
open('$TMP/g_cldrop.html','w').write(d.replace(frag,n,1))
" 2>/dev/null; then expect_verify_fail "A76 ★cl case-drop+decoy を cl count-parity で捕捉" "$BASE" "$TMP/g_cldrop.html"; else ng "A76 setup 失敗"; fi
# A77. ★legend chip 削除 + chrome 注入 (count-conservation): global/row-scope 保存だが legend-scope drop で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
import re
m=re.search(r'<span class=\"vmeth\">[^<]*</span>', d); assert m
leg=m.group(0)
d2=d.replace(leg,'',1).replace('</h1>','</h1><span class=\"vmeth\">X=偽検証法</span>',1)
open('$TMP/g_legreloc.html','w').write(d2)
" 2>/dev/null; then expect_verify_fail "A77 ★legend削除+chrome注入 (count保存) を legend-scope binding で捕捉" "$BASE" "$TMP/g_legreloc.html"; else ng "A77 setup 失敗"; fi
# A78. ★entity-encoded class ghost (&#102;id → .fid 描画) — count_attr_token の数値文字参照 decode で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; n='<td class=\"resp\"><span class=\"&#102;id\">FRX-GHOST</span>'
assert o in d
open('$TMP/g_entity.html','w').write(d.replace(o,n,1))
" 2>/dev/null; then expect_verify_fail "A78 ★entity-encoded class ghost (&#102;id) を文字参照 decode で捕捉" "$BASE" "$TMP/g_entity.html"; else ng "A78 setup 失敗"; fi
# ★round-6 ceiling (wf_15affdca): vcount allowlist drift (origin/cover-meta/RTM dot 漏れ) + 構造的 drift 封鎖 (round-7)。
# A79. ★origin case-drop+decoy (vcount allowlist 漏れ) → origin count-parity で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
import re
m=re.search(r'<span class=\"origin\">[^<]*</span>', d); assert m; frag=m.group(0)
open('$TMP/g_origin.html','w').write(d.replace(frag,'<span class=\"ORIGIN\">捏造出所</span>'+frag,1))
" 2>/dev/null; then expect_verify_fail "A79 ★origin case-drop+decoy を origin count-parity で捕捉" "$BASE" "$TMP/g_origin.html"; else ng "A79 setup 失敗"; fi
# A80. ★cover-meta k/v case-drop+decoy (機能要件 6件→999件 = round-5 が名指しした fraud) → k/v count-parity で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
import re
m=re.search(r'<span class=\"k\">[^<]*</span><span class=\"v\">[^<]*</span>', d); assert m; kv=m.group(0)
open('$TMP/g_kv.html','w').write(d.replace(kv,'<span class=\"K\">機能要件</span><span class=\"V\">999件</span>'+kv,1))
" 2>/dev/null; then expect_verify_fail "A80 ★cover-meta k/v case-drop+decoy を k/v count-parity で捕捉" "$BASE" "$TMP/g_kv.html"; else ng "A80 setup 失敗"; fi
# A81. ★RTM dot ac (受入) の data-acc-link attr-absent 偽ドット (.dot.ac 緑 pill 描画) → dot∧ac 占有数パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"hit\">'; assert o in d
open('$TMP/g_dotac.html','w').write(d.replace(o,o+'<span class=\"dot ac\">AC999</span>',1))
" 2>/dev/null; then expect_verify_fail "A81 ★dot ac attr-absent 偽ドットを dot∧ac 占有数で捕捉" "$BASE" "$TMP/g_dotac.html"; else ng "A81 setup 失敗"; fi
# A82. ★RTM dot 後方● の data-trace-link attr-absent 偽ドット → dot∧¬ac 占有数パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"hit\">'; assert o in d
open('$TMP/g_dotb.html','w').write(d.replace(o,o+'<span class=\"dot\">●</span>',1))
" 2>/dev/null; then expect_verify_fail "A82 ★dot 後方● attr-absent 偽ドットを dot∧¬ac 占有数で捕捉" "$BASE" "$TMP/g_dotb.html"; else ng "A82 setup 失敗"; fi
# A83. ★novel-class drift: 未分類の新 class token を持つ ghost → class-token 機械的網羅 (構造的 drift 封鎖) で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; assert o in d
open('$TMP/g_novel.html','w').write(d.replace(o,o+'<span class=\"zzznovelclass\">捏造</span>',1))
" 2>/dev/null; then expect_verify_fail "A83 ★novel-class drift を class-token 機械的網羅で捕捉" "$BASE" "$TMP/g_novel.html"; else ng "A83 setup 失敗"; fi
# ★round-7 ceiling (wf_5cd6b11d): EXEMPT misclassification + dot/novel の quote-syntax 穴 (round-8 で封鎖)。
# A84. ★rtm-summary-derived の *可視* 派生数値 (孤立要件 0→999件) を改竄 (data-derived 属性は無傷) → 可視 5 数値突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='孤立要件 (出所なし) 0 件'
assert o in d
open('$TMP/g_rtmsum.html','w').write(d.replace(o,'孤立要件 (出所なし) 999 件',1))
" 2>/dev/null; then expect_verify_fail "A84 ★rtm-summary 可視派生数値 改竄を可視 5 数値突合で捕捉" "$BASE" "$TMP/g_rtmsum.html"; else ng "A84 setup 失敗"; fi
# A85. ★dot ac single-quote attr-absent 偽ドット (.dot.ac 緑 pill 描画・data-acc-link 無し) → quote-robust dot joint-token で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"hit\">'; assert o in d
open('$TMP/g_dotsq.html','w').write(d.replace(o,o+'<span class=\\'dot ac\\'>AC9</span>',1))
" 2>/dev/null; then expect_verify_fail "A85 ★dot ac single-quote attr-absent を quote-robust joint-token で捕捉" "$BASE" "$TMP/g_dotsq.html"; else ng "A85 setup 失敗"; fi
# A86. ★dot 後方● unquoted attr-absent → quote-robust dot∧¬ac で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"hit\">'; assert o in d
open('$TMP/g_dotuq.html','w').write(d.replace(o,o+'<span class=dot>●</span>',1))
" 2>/dev/null; then expect_verify_fail "A86 ★dot 後方● unquoted attr-absent を quote-robust joint-token で捕捉" "$BASE" "$TMP/g_dotuq.html"; else ng "A86 setup 失敗"; fi
# A86b. ★folio-bur: 後方ドット attr-present・可視● 捏造 (data-trace-link intact のまま ●→N-3 偽 need ID)。 A82/A86 は attr-absent
#   偽ドットを件数で捕捉するが、 attr/class/件数 intact のまま span 内可視テキストだけ捏造する fail-open は別物 (visible-text-vs-attribute)。
#   (j3) 可視==● 固定記号 pin で封鎖 (acc ドット j2 と対称)。
body_tamper_fail "A86b ★後方ドット attr-present・可視●捏造 (●→N-3) を可視==●固定記号で捕捉" '<span class="dot" data-trace-link="FR1__N-2">●</span>' '<span class="dot" data-trace-link="FR1__N-2">N-3</span>'
# A86c/d ★folio-bur round-2 (ceiling-recursion): j3 span-inner の射程外を突く 2 bypass を full-cell remainder + ● glyph パリティで捕捉。
body_tamper_fail "A86c ★span intact のまま同一セルに sibling text-node (● N-3) を追記 → full-cell remainder で捕捉" '<span class="dot" data-trace-link="FR1__N-2">●</span></td>' '<span class="dot" data-trace-link="FR1__N-2">●</span> N-3</td>'
body_tamper_fail "A86d ★空トレースセルへ裸 ● グリフ注入 (<td></td>→<td>●</td>) → ● glyph 占有数パリティで捕捉" '<td></td>' '<td>●</td>'
# A86e/f/g ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 fix 自体の残存 fail-open。
#   (e) confusable ⚫(U+26AB) を空セルへ (grep -o '●' は exact U+25CF のみ数え占有数を欺く) → RTM partition 不変条件 (j3c) で捕捉
#   (f) 裸テキスト need-ID を空セルへ (グリフ占有数の射程外) → RTM partition 不変条件 (j3c) で捕捉
#   (g) scope バレットから ● を略奪し comment へ退避 (global ● 数保存) → per-source ● パリティ (j3d) で捕捉
body_tamper_fail "A86e ★confusable ⚫(U+26AB) を空セルへ (グリフ占有数を欺く) → RTM partition 不変条件で捕捉" '<td></td>' '<td>⚫</td>'
body_tamper_fail "A86f ★裸テキスト need-ID を空セルへ (<td></td>→<td>N-9</td>) → RTM partition 不変条件で捕捉" '<td></td>' '<td>N-9</td>'
body_tamper_fail "A86g ★scope バレット ● を略奪し comment 退避 (global ● 保存) → per-source ● パリティで捕捉" '<span class="b">●</span>' '<span class="b"></span><!--●-->'
# A86h/i/j ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 j3c/j 自体の残存 fail-open。
#   (h) 表タグを single-quote 化し anchor を外して partition を vacuous-pass させ ⚫ を空セルへ → quote-robust 列挙で捕捉
#   (i) 2 個目 <table class="rtm"> を追記 (first-match の射程外) → table.rtm 占有==1 で捕捉
#   (j) <th id="z"> 属性付き偽要件行を注入 (literal <tr><th> anchor の射程外) → attr 許容 row-heading 突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
d=d.replace('<table class=\"rtm\">','<table class=\x27rtm\x27>',1)
assert '<td></td>' in d
d=d.replace('<td></td>','<td>⚫</td>',1)
open('$TMP/g_r4h.html','w').write(d)
" 2>/dev/null; then expect_verify_fail "A86h ★single-quote 表タグ+⚫ で partition vacuous-pass を quote-robust 列挙で捕捉" "$BASE" "$TMP/g_r4h.html"; else ng "A86h setup 失敗"; fi
body_tamper_fail "A86i ★2個目 <table class=rtm> 追記 (first-match 射程外) → table.rtm 占有==1 で捕捉" '</table>' '</table><table class="rtm"><tbody><tr><td>⚫ N-9 偽トレース</td></tr></tbody></table>'
body_tamper_fail "A86j ★<th id=z> 属性付き偽要件行注入 → attr 許容 row-heading 突合で捕捉" '</tr>' '</tr><tr><th id="z">FR99 偽の要件</th><td></td></tr>'
# A87. ★novel-class を single-quote で書いた drift → quote-robust class-token 機械的網羅で捕捉 (double-quote 固定の overclaim 是正)
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"resp\">'; assert o in d
open('$TMP/g_novelsq.html','w').write(d.replace(o,o+'<span class=\\'zzznovelsq\\'>x</span>',1))
" 2>/dev/null; then expect_verify_fail "A87 ★single-quote novel-class を quote-robust 機械的網羅で捕捉" "$BASE" "$TMP/g_novelsq.html"; else ng "A87 setup 失敗"; fi
# ★round-9 ceiling (wf_a2a3db7c): R8 が dot/novel で達成した quote-robust 不動点を *未適用* の兄弟 3 種。
# A88. ★rtm-summary single-quote decoy-append (real 無傷 + 偽 <p class='rtm-summary-derived'>999件 併置・EXEMPT で占有数パリティ無し) → COUNTED 化 count==1 で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<div class=\"ears-legend\">'; assert o in d
open('$TMP/g_rtmdecoy.html','w').write(d.replace(o,'<p class=\\'rtm-summary-derived\\'>孤立要件 999 件</p>'+o,1))
" 2>/dev/null; then expect_verify_fail "A88 ★rtm-summary single-quote decoy を占有数パリティ(count==1)で捕捉" "$BASE" "$TMP/g_rtmdecoy.html"; else ng "A88 setup 失敗"; fi
# A89. ★acc-dot single-quote decoy (class=\"dot ac\" double-quote + data-acc-link single-quote・可視 id 捏造 suffix≠visible) → quote-robust attr_values/acc_vis_bad で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"hit\">'; assert o in d
open('$TMP/g_accsq.html','w').write(d.replace(o,o+'<span class=\"dot ac\" data-acc-link=\\'FR1__AC1\\'>AC999</span>',1))
" 2>/dev/null; then expect_verify_fail "A89 ★acc-dot single-quote 可視 id 捏造を quote-robust data-acc-link 突合で捕捉" "$BASE" "$TMP/g_accsq.html"; else ng "A89 setup 失敗"; fi
# A90. ★凡例 ears ラベル改竄 (class=ears trigger 不変・きっかけ→誤訳) → (class,label) SET 値突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<span class=\"ears trigger\">きっかけ '; assert o in d
open('$TMP/g_legears.html','w').write(d.replace(o,'<span class=\"ears trigger\">誤訳 ',1))
" 2>/dev/null; then expect_verify_fail "A90 ★凡例 ears ラベル改竄を (class,label) 値突合で捕捉" "$BASE" "$TMP/g_legears.html"; else ng "A90 setup 失敗"; fi
# A91. ★凡例 prio ラベル swap (推奨→必須・class 不変) → (class,label) SET 値突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<span class=\"prio should\">推奨</span>'; assert o in d
open('$TMP/g_legprio.html','w').write(d.replace(o,'<span class=\"prio should\">必須</span>',1))
" 2>/dev/null; then expect_verify_fail "A91 ★凡例 prio ラベル改竄を (class,label) 値突合で捕捉" "$BASE" "$TMP/g_legprio.html"; else ng "A91 setup 失敗"; fi
# A92. ★凡例 vmeth ラベル捏造 (T=テスト→T=捏造) → (class,label) SET 値突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<span class=\"vmeth\">T=テスト</span>'; assert o in d
open('$TMP/g_legvm.html','w').write(d.replace(o,'<span class=\"vmeth\">T=捏造</span>',1))
" 2>/dev/null; then expect_verify_fail "A92 ★凡例 vmeth ラベル捏造を (class,label) 値突合で捕捉" "$BASE" "$TMP/g_legvm.html"; else ng "A92 setup 失敗"; fi
# A93. ★rtm-summary unquoted decoy (class=rtm-summary-derived 無引用) → count_attr_token unquoted 分岐 + 占有数パリティで捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<div class=\"ears-legend\">'; assert o in d
open('$TMP/g_rtmuq.html','w').write(d.replace(o,'<p class=rtm-summary-derived>fake</p>'+o,1))
" 2>/dev/null; then expect_verify_fail "A93 ★rtm-summary unquoted decoy を quote-robust 占有数パリティで捕捉" "$BASE" "$TMP/g_rtmuq.html"; else ng "A93 setup 失敗"; fi

# ---- A94-A108: body prose テキスト値 floor 突合 (folio-4cf §7g) + 凡例 en/lt SET (folio-czo) ----
# A94. goals.desc (cd) 本文改竄 (約束の意味反転: 請求しない→請求する) → §7g(a) 順序突合
body_tamper_fail "A94 ★body prose goals.desc 改竄 (cd) を順序突合で捕捉" "2 回請求しない" "2 回請求する"
# A95. scope.in item 改竄 → §7g(b)
body_tamper_fail "A95 ★body prose scope.in 改竄を順序突合で捕捉" "注文番号の発行と確認メール" "詐欺スコープ"
# A96. scope.in に bullet 無し偽 li を追加 (全 li 抽出ゆえ余分行→不一致) → §7g(b)
if python3 -c "
d=open('$TMP/good.html').read()
o='<div class=\"scol in\"><h3>✓ 扱う (in scope)</h3><ul>'; assert o in d
open('$TMP/bp96.html','w').write(d.replace(o,o+'<li>偽スコープ項目</li>',1))
" 2>/dev/null; then expect_verify_fail "A96 ★scope.in bullet 無し偽 li 追加を全 li 抽出で捕捉" "$BASE" "$TMP/bp96.html"; else ng "A96 setup 失敗"; fi
# A97. actor.role (div.role) 改竄 → §7g(c) (approval の span.role はタグで区別)
body_tamper_fail "A97 ★body prose actor.role 改竄 (div.role) を順序突合で捕捉" "注文を確定する人" "偽ロール"
# A98. upper_needs.need (source-trace 2nd td) 改竄 → §7g(d)
body_tamper_fail "A98 ★body prose upper_needs.need 改竄を順序突合で捕捉" "クレーム・チャージバックを減らし" "捏造ニーズを増やし"
# A99. ears.condition (td.cond) 改竄 → §7g(e)
body_tamper_fail "A99 ★body prose ears.condition 改竄 (td.cond) を順序突合で捕捉" "「注文確定」を押したとき" "偽条件のとき"
# A100. ears.response (td.resp の slot 前) 改竄 → §7g(f)
body_tamper_fail "A100 ★body prose ears.response 改竄 (td.resp) を順序突合で捕捉" "在庫を確保 (引当) してから決済に進む" "詐欺応答"
# A101. nfr.target (span.tgt) 改竄 (1.0 秒→99 秒) → §7g(g)
body_tamper_fail "A101 ★body prose nfr.target 改竄 (span.tgt) を順序突合で捕捉" "95% が 1.0 秒以内" "1% が 99 秒以内"
# A102. nfr.measure (td.meas) 改竄 → §7g(h)
body_tamper_fail "A102 ★body prose nfr.measure 改竄 (td.meas) を順序突合で捕捉" "負荷試験で確定処理の応答時間を計測" "詐欺測定"
# A103. acceptance.criterion (p.at) 改竄 (1 件→999 件) → §7g(i)
body_tamper_fail "A103 ★body prose acceptance.criterion 改竄 (p.at) を順序突合で捕捉" "確定は 1 件だけ" "確定は 999 件"
# A104. constraint.text (3rd td・reg-badge 前) 改竄 (意味反転) → §7g(j)
body_tamper_fail "A104 ★body prose constraint.text 改竄 (3rd td) を順序突合で捕捉" "カード情報は自社で持たず" "カード情報は自社で持ち"
# A105. cond セル single-quote decoy 追加 (順序突合は double-quote 抽出ゆえ素通るが vcount 占有数パリティが捕捉) → §7f×§7g 二層
if python3 -c "
d=open('$TMP/good.html').read()
o='<td class=\"cond\">購入者が「注文確定」を押したとき</td>'; assert o in d
open('$TMP/bp105.html','w').write(d.replace(o,o+\"<td class='cond'>偽の条件セル</td>\",1))
" 2>/dev/null; then expect_verify_fail "A105 ★cond single-quote decoy 追加を vcount 占有数パリティで捕捉 (二層)" "$BASE" "$TMP/bp105.html"; else ng "A105 setup 失敗"; fi
# A106. 凡例 en (folio-czo) 改竄 (When→Whatever・class 不変) → legend-scope SET 値突合
body_tamper_fail "A106 ★凡例 en ラベル改竄 (folio-czo) を legend SET で捕捉" "<span class=\"en\">When</span>" "<span class=\"en\">Whatever</span>"
# A107. 凡例 lt (folio-czo) 改竄 (タイプ:→詐欺:) → legend-scope SET 値突合
body_tamper_fail "A107 ★凡例 lt ラベル改竄 (folio-czo) を legend SET で捕捉" "<span class=\"lt\">タイプ:</span>" "<span class=\"lt\">詐欺:</span>"
# A108. 凡例 en の位置 swap (folio-czo・When↔While・親 ears class と対ゆえ swap も捕捉) → legend-scope SET
if python3 -c "
d=open('$TMP/good.html').read()
a='class=\"ears trigger\">きっかけ <span class=\"en\">When</span>'; b='class=\"ears state\">状態 <span class=\"en\">While</span>'
assert a in d and b in d
d=d.replace(a,'class=\"ears trigger\">きっかけ <span class=\"en\">While</span>',1).replace(b,'class=\"ears state\">状態 <span class=\"en\">When</span>',1)
open('$TMP/bp108.html','w').write(d)
" 2>/dev/null; then expect_verify_fail "A108 ★凡例 en 位置 swap (folio-czo・親 ears 対) を legend SET で捕捉" "$BASE" "$TMP/bp108.html"; else ng "A108 setup 失敗"; fi
# A109. ★ears.response の prose-slot 後ろ・</td> 前へ可視 text-node を post-gen 追記 (slot 前のみ抽出だと素通る residual gap) → td.resp 全体 strip 突合で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
import re
o='<span class=\"why\" data-prose-slot=\"rationale\" data-source=\"N-2\" data-slot-id=\"rationale-FR1\"></span></td>'; assert o in d, 'why-slot 末尾 not found'
open('$TMP/g_resptail.html','w').write(d.replace(o,'<span class=\"why\" data-prose-slot=\"rationale\" data-source=\"N-2\" data-slot-id=\"rationale-FR1\"></span>詐欺の追記応答</td>',1))
" 2>/dev/null; then expect_verify_fail "A109 ★ears.response slot 後ろ text-node 追記を td.resp 全体 strip 突合で捕捉" "$BASE" "$TMP/g_resptail.html"; else ng "A109 setup 失敗"; fi

# ---- A110-A129: core 共通 chrome (cover-head/approval/glossary) の floor 突合 (folio-mk9・verify_core_chrome) ----
# lib/common.sh が全 pack 同一構造で emit する決定的可視 chrome 値の改竄を verify_core_chrome が FAIL することを回帰確認する。
# (a) 値改竄 = body_tamper_fail (順序突合が捕捉) / (b) decoy 注入 (大文字化/entity/unquoted/single-quote/偽要素併置) = 占有数パリティが捕捉。
echo
echo "core 共通 chrome 層 (cover-head/approval/glossary・folio-mk9) の fail-closed:"
# </h1> 直後へ decoy を 1 個注入し verify FAIL を期待する helper (占有数パリティ検証用・python landed-assert)。
chrome_decoy_fail() { # label decoy_html
  if python3 -c "
d=open('$TMP/good.html').read()
o='</h1>'; assert o in d, 'anchor not found'
open('$TMP/cd.html','w').write(d.replace(o,o+'''$2''',1))
" 2>/dev/null; then expect_verify_fail "$1" "$BASE" "$TMP/cd.html"; else ng "$1 setup 失敗"; fi
}
# (a) 値改竄 (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary term/en/def) → 順序突合 FAIL
body_tamper_fail "A110 ★cover eyebrow_left 改竄を core-chrome 順序突合で捕捉" '<span class="doc-type">要件定義書 (SRS)</span>' '<span class="doc-type">詐欺ラベル</span>'
body_tamper_fail "A111 ★cover eyebrow_right 改竄を core-chrome 順序突合で捕捉" '<span>EC サイト — 注文確定・決済</span>' '<span>詐欺の右ラベル</span>'
body_tamper_fail "A112 ★cover title (h1) 改竄を core-chrome 順序突合で捕捉" '<h1>カートの商品を、 確実に・二重課金せず・売り越さず「注文確定」までやり切る仕組み</h1>' '<h1>詐欺タイトル</h1>'
body_tamper_fail "A113 ★cover subtitle 改竄を core-chrome 順序突合で捕捉" '<p class="cover-sub">在庫の取り合いも、 決済の失敗も、 ボタン連打も起こりうる前提で設計する</p>' '<p class="cover-sub">詐欺サブタイトル</p>'
body_tamper_fail "A114 ★reader (想定読者) 改竄を core-chrome 順序突合で捕捉" '想定読者: EC 事業の事業責任者 — プログラミング・会計の専門知識は不要 (専門語は必ずやさしい言葉を併記)</div>' '想定読者: 詐欺の読者</div>'
body_tamper_fail "A115 ★approval role 改竄を core-chrome 順序突合で捕捉" '<span class="role">承認 (事業責任者)</span>' '<span class="role">詐欺の役職</span>'
body_tamper_fail "A116 ★approval who (承認者名) 改竄を core-chrome 順序突合で捕捉" '<span class="who">田中 葵</span>' '<span class="who">詐欺 太郎</span>'
body_tamper_fail "A117 ★approval when (承認日) 改竄を core-chrome 順序突合で捕捉" '<span class="when">2026-06-15 承認</span>' '<span class="when">1999-01-01 承認</span>'
body_tamper_fail "A118 ★approval stamp (印) 改竄を core-chrome 順序突合で捕捉" '<span class="stamp">承認済</span>' '<span class="stamp">却下</span>'
body_tamper_fail "A119 ★glossary term 改竄を core-chrome 順序突合で捕捉" '<div class="gword">在庫引当<span class="en">' '<div class="gword">詐欺用語<span class="en">'
body_tamper_fail "A120 ★glossary en 改竄を core-chrome 順序突合で捕捉" '<span class="en">stock allocation</span>' '<span class="en">fraud-en</span>'
body_tamper_fail "A121 ★glossary def 改竄を core-chrome 順序突合で捕捉" '<div class="gdef">注文の瞬間に在庫を「この人の分」として押さえること。 押さえないと同じ 1 個を 2 人に売ってしまう。</div>' '<div class="gdef">詐欺の定義</div>'
# (b) decoy 注入 (占有数パリティが捕捉・順序突合は anchored ゆえ素通りうる経路を二層目で封鎖)
chrome_decoy_fail "A122 ★doc-type 大文字化 decoy (CLASS 偽要素) を doc-type 占有数で捕捉" '<span class="DOC-TYPE">詐欺の文書種</span>'
chrome_decoy_fail "A123 ★sign 行 大文字化 decoy (偽承認行) を sign 占有数で捕捉" '<div class="SIGN"><span class="role">詐欺</span><span class="who">x</span><span class="when">y</span><span class="stamp">z</span></div>'
chrome_decoy_fail "A124 ★grow 行 大文字化 decoy (偽用語行) を grow 占有数で捕捉" '<div class="GROW"><div class="gword">詐欺</div><div class="gdef">x</div></div>'
chrome_decoy_fail "A126 ★who entity-encoded decoy (&#119;ho) を文字参照 decode 占有数で捕捉" '<span class="&#119;ho">詐欺の承認者</span>'
chrome_decoy_fail "A127 ★stamp unquoted decoy (class=stamp) を quote 非依存 占有数で捕捉" '<span class=stamp>詐欺の印</span>'
chrome_decoy_fail "A128 ★h1 大文字化 decoy (<H1>) を h1 タグ占有数 (case 非依存) で捕捉" '<H1>詐欺の第二タイトル</H1>'
chrome_decoy_fail "A129 ★想定読者 marker decoy (偽 reader-chip) を marker 占有数 + 値突合で捕捉" '<div class="reader-chip"> 想定読者: 詐欺の第二読者</div>'
# A130 ★marker *無し* の偽 reader-chip decoy (`class="reader-chip">` anchor 一致だが "想定読者:" 無し) を構造 anchor 占有数で捕捉。
#       marker count に keyed した A129 では捕捉できない fail-open を anchor 占有数パリティ (genuine == 1) で塞いだ回帰 (folio-mk9 self-review)。
chrome_decoy_fail "A130 ★想定読者 *無し* の偽 reader-chip decoy を anchor 占有数で捕捉" '<div class="reader-chip"> 詐欺の追加チップ</div>'
# A130b ★ref-chip *構文形* の偽 reader-chip decoy (`class="reader-chip" role="note">…` = 閉じ引用後に空白+任意属性) を占有数パリティで捕捉。
#        A130 の anchor grep (`class="reader-chip">` = > 直後) は > 直後でないため不一致・marker count も "想定読者:" 無しで不一致ゆえ素通る fail-open を
#        (class reader-chip 占有) − (data-component cross-doc-ref-chip 占有) == 1 で塞いだ回帰 (folio-mk9 self-review round-3)。
chrome_decoy_fail "A130b ★ref-chip 構文形の偽 reader-chip decoy を占有数パリティで捕捉" '<div class="reader-chip" role="note">詐欺の偽 reader-chip…</div>'
# A130c ★ref-chip と *同一構文* (class="reader-chip" data-component="cross-doc-ref-chip") を持つ additive decoy に偽『想定読者:』text を載せた攻撃。
#        旧 差分式 `(class reader-chip 占有) − (cross-doc-ref-chip 占有)` は被減数 (+1)・減数 (+1) が同タグ上で同時に増えて差 1 のまま不変ゆえ素通った
#        (folio-mk9 self-review round-4 が SRS full verify exit 0 で実証)。 element-level genuine count + global『想定読者:』marker count==1 で塞いだ回帰。
chrome_decoy_fail "A130c ★ref-chip 同一構文+偽『想定読者:』additive decoy を要素単位+marker 全体数で捕捉" '<div class="reader-chip" data-component="cross-doc-ref-chip">想定読者: 詐欺の偽読者</div>'
# A130d ★ref-chip 同一構文 (class="reader-chip" data-component="cross-doc-ref-chip") で marker を *持たない* 任意 text の additive decoy。
#        element-level genuine count は ref-chip 側へ分類し count を増やさず・global『想定読者:』marker も marker 無しゆえ不変 = SRS で素通る fail-open
#        (folio-mk9 self-review round-5)。 SRS は cross_doc を持たず ref-chip 不在ゆえ reader-chip class 総数 == 1 (§7b'') で捏造 ref-chip box を封鎖した回帰。
chrome_decoy_fail "A130d ★ref-chip 構文+marker無し任意 text の捏造 box を SRS reader-chip 総数==1 で捕捉" '<div class="reader-chip" data-component="cross-doc-ref-chip">詐欺の任意テキスト box</div>'
# A130e ★A130d の single-quote data-component 変種 (quote-robust count_attr_token が classify) も封鎖。
chrome_decoy_fail "A130e ★ref-chip 構文 single-quote data-component の捏造 box を quote-robust 占有数で捕捉" "<div class=\"reader-chip\" data-component='cross-doc-ref-chip'>詐欺 single-quote box</div>"
# A130f ★属性値内 > で count_genuine の tag-splitter を断片化した genuine-style decoy (folio-mk9 self-review round-6・FO-2)。
#        SRS は §7b'' の reader-chip 総数==1 (count_attr_token 全文走査=>-attr 非依存) で既に封鎖。 tag-splitter 堅牢化 + 総数 bind の二層回帰。
chrome_decoy_fail "A130f ★title内 > で断片化する genuine-style decoy を SRS 総数==1 で捕捉" '<div title="x>y" class="reader-chip" role="z">捏造の権威 box</div>'
# A125 ★glossary en single-quote decoy (grow 行内・double-quote real は無傷) を grow 行内 en 占有数で捕捉
body_tamper_fail "A125 ★glossary en single-quote decoy を grow 行内 en 占有数で捕捉" '<div class="gword">在庫引当<span class="en">stock allocation</span></div>' "<div class=\"gword\">在庫引当<span class=\"en\">stock allocation</span><span class='en'>詐欺</span></div>"
# A131-A134 ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 fix 自体の残存 fail-open (act_rtmh の <tr> literal / partition の
#   inner-td case-sensitive / outer non-greedy nested-table early-term)。
# A131 ★act_rtmh: round-4 は <th> のみ属性許容化し兄弟 <tr> を literal 据置 → <tr id> 付き phantom 要件行で捏造要件が RTM 素通り。<tr[^>]*> 抽出+順序突合で捕捉。
if python3 -c "
d=open('$TMP/good.html').read()
o='<tbody>\n<tr><th>FR1'; assert o in d
open('$TMP/g_phantomrow.html','w').write(d.replace(o,'<tbody>\n<tr id=\"z9\"><th>FR99 重大な捏造要件（実在せず）</th><td></td><td></td><td></td><td></td><td></td></tr>\n<tr><th>FR1',1))
" 2>/dev/null; then expect_verify_fail "A131 ★<tr id> 属性付き phantom 要件行 (act_rtmh の <tr> literal 死角) を <tr[^>]*> 抽出+順序突合で捕捉" "$BASE" "$TMP/g_phantomrow.html"; else ng "A131 setup 失敗"; fi
# A132 ★partition: round-4 の inner <td\b は case-sensitive → 大文字 <TD> セルが BADCELL 分類を逃れ任意捏造トレースが RTM 流入。inner /i で捕捉。
if python3 -c "
d=open('$TMP/good.html').read()
o='data-acc-link=\"FR1__AC1\">AC1</span></td>'; assert o in d
open('$TMP/g_uppertd.html','w').write(d.replace(o,o+'<TD>N-9 偽トレース（捏造）</TD>',1))
" 2>/dev/null; then expect_verify_fail "A132 ★大文字 <TD> セル (partition inner case 死角) を /i partition で BADCELL 捕捉" "$BASE" "$TMP/g_uppertd.html"; else ng "A132 setup 失敗"; fi
# A133 ★partition: round-4 outer (.*?)</table> は入れ子 <table></table> で early-term (ds8 nested-same-tag 機構の <table> 再発) → truncation 後の捏造セル未 partition。nested-table-reject で捕捉。
if python3 -c "
d=open('$TMP/good.html').read()
o='data-acc-link=\"FR1__AC1\">AC1</span></td></tr>'; assert o in d
open('$TMP/g_nesttable.html','w').write(d.replace(o,o+'<table></table>',1))
" 2>/dev/null; then expect_verify_fail "A133 ★入れ子 <table></table> (partition outer early-term 死角) を nested-table-reject で捕捉" "$BASE" "$TMP/g_nesttable.html"; else ng "A133 setup 失敗"; fi
# A134 ★partition: stray </table> (開タグ無し) で outer (.*?)</table> を早期終端させ後続セルを未 partition 化する経路を table 開閉タグ平衡で捕捉。
if python3 -c "
d=open('$TMP/good.html').read()
o='<tr><th>FR2'; assert o in d
open('$TMP/g_straytable.html','w').write(d.replace(o,'</table><tr><th>FR2',1))
" 2>/dev/null; then expect_verify_fail "A134 ★stray </table> (partition early-term 死角) を table 開閉タグ平衡で捕捉" "$BASE" "$TMP/g_straytable.html"; else ng "A134 setup 失敗"; fi
# A135-A138 ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 fix 自体の残存 sibling fail-open (§7g scol 未 region-recon / act_rtmh th-only 死角 / EXEMPT 静的 chrome 占有欠如)。
# A135 ★§7g scol: 2 個目 scol-in block (偽 in-scope 宣言) を first-match `if` 死角へ注入 → scol 占有==2 + region-recon で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<div class=\"scol out\">'; assert o in d
open('$TMP/g_scol2.html','w').write(d.replace(o,'<div class=\"scol in\"><ul><li>偽: 全顧客の個人情報を無断で第三者に販売する</li></ul></div>'+o,1))
" 2>/dev/null; then expect_verify_fail "A135 ★§7g 2個目 scol-in 偽 in-scope 宣言を scol 占有+region-recon で捕捉" "$BASE" "$TMP/g_scol2.html"; else ng "A135 setup 失敗"; fi
# A136 ★act_rtmh: td 無し <th> 単独 phantom 行 (rtm tbody・class lt は EXEMPT) → rtm <tr> 占有で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<tbody>\n<tr><th>FR1'; assert o in d
open('$TMP/g_thonly.html','w').write(d.replace(o,'<tbody><tr><th class=\"lt\">FR99 偽要件: 管理者は全パスワードを平文閲覧</th></tr>\n<tr><th>FR1',1))
" 2>/dev/null; then expect_verify_fail "A136 ★td 無し <th> phantom 要件行 (act_rtmh th-only 死角) を rtm <tr> 占有で捕捉" "$BASE" "$TMP/g_thonly.html"; else ng "A136 setup 失敗"; fi
# A137 ★EXEMPT 静的 chrome: duplicate <p class=lab> 偽ラベル → lab 占有==1 で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<p class=\"lab\">'; assert o in d
open('$TMP/g_lab.html','w').write(d.replace(o,'<p class=\"lab\">緊急: 全顧客データを30日で自動削除(捏造)</p>'+o,1))
" 2>/dev/null; then expect_verify_fail "A137 ★duplicate <p class=lab> 静的 chrome decoy を lab 占有==1 で捕捉" "$BASE" "$TMP/g_lab.html"; else ng "A137 setup 失敗"; fi
# A138 ★§7g scol arbitrary-wrapper: 非li/非b/●glyph の捏造 scope を scol-in <ul> 内へ → region-text+nested-div reject で捕捉
if python3 -c "
import re
d=open('$TMP/good.html').read()
d2=re.sub(r'(<div class=\"scol in\">.*?)</ul>', r'\1<div class=\"zz\"><span class=\"bb\">●</span>捏造範囲</div></ul>', d, count=1, flags=re.S)
assert d2!=d
open('$TMP/g_scolnd.html','w').write(d2)
" 2>/dev/null; then expect_verify_fail "A138 ★非li/非b arbitrary-wrapper 捏造 scope を region-text+nested-div reject で捕捉" "$BASE" "$TMP/g_scolnd.html"; else ng "A138 setup 失敗"; fi

echo
echo "PASS=$pass FAIL=$fail"
if [[ "$fail" -ne 0 ]]; then echo "RESULT: 取りこぼしあり"; exit 1; fi

# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
perl -0777 -pe 's{</body>}{<p class="txt">虚偽: 全顧客の個人情報を無断販売する(捏造)</p></body>}' "$TMP/good.html" > "$TMP/r7txt.html"
expect_verify_fail "R7-srs-a ★txt-on-cover additive (ceiling 残余) を txt 占有==1 で捕捉" "$BASE" "$TMP/r7txt.html"
perl -0777 -pe 's{</body>}{<span class="lt">偽の凡例(捏造)</span></body>}' "$TMP/good.html" > "$TMP/r7lt.html"
expect_verify_fail "R7-srs-b ★lt phantom (ceiling 残余・rtm 兄弟表) を lt 占有==3 で捕捉" "$BASE" "$TMP/r7lt.html"
perl -0777 -pe 's{</body>}{<div data-component="adr-option-card">foreign dc(捏造)</div></body>}' "$TMP/good.html" > "$TMP/r7fdc.html"
expect_verify_fail "R7-srs-c ★foreign data-component を新規 dc enumeration で捕捉" "$BASE" "$TMP/r7fdc.html"
perl -0777 -pe 's{</body>}{<div class="nfr-hero">偽メトリクス(捏造)</div></body>}' "$TMP/good.html" > "$TMP/r7nh.html"
expect_verify_fail "R7-srs-d ★nfr-hero additive を占有で捕捉" "$BASE" "$TMP/r7nh.html"
perl -0777 -pe 's{</body>}{<p style="display:none">genuine 隠蔽(捏造)</p></body>}' "$TMP/good.html" > "$TMP/r7dn.html"
expect_verify_fail "R7-srs-e ★display:none 隠蔽を display-state guard で捕捉" "$BASE" "$TMP/r7dn.html"

# ===== folio-wq4 回帰: make_body substrate (style co-located) + occupancy global pin (blocker 1+3) =====
# blocker 1: 旧 make_body (sed '/<style>/,/</style>/d' 行範囲削除) は <style> 同居行の実 DOM 捏造を巻き込み消去し
#   verify を偽 PASS させた。 新 make_body (perl 中身空化) は捏造を $BODY に surface させ既存/新 occupancy が捕捉する。
perl -0777 -pe 's{</body>}{<p><style>.wq4{color:red}</style><span class="aid">捏造AC(style同居)</span></p></body>}' "$TMP/good.html" > "$TMP/wq4a.html"
expect_verify_fail "WQ4-a ★<style>同居行の偽 aid を make_body 中身空化で surface→aid 占有が捕捉 (旧 sed 行範囲削除は素通り)" "$BASE" "$TMP/wq4a.html"
perl -0777 -pe 's{</body>}{<div><style>.q{}</style><span class="role">偽の承認者(style同居)</span></div></body>}' "$TMP/good.html" > "$TMP/wq4b.html"
expect_verify_fail "WQ4-b ★<style>同居行の偽 role を surface→global role 占有が捕捉" "$BASE" "$TMP/wq4b.html"
# blocker 3: 行 scope (sign/grow) 外へ注入した偽 role/en を global 占有 pin が捕捉。
perl -0777 -pe 's{</body>}{<span class="role">偽の承認者(scope外)</span></body>}' "$TMP/good.html" > "$TMP/wq4c.html"
expect_verify_fail "WQ4-c ★行 scope 外 (sign 行外) の偽 role を global 占有 (==|approval|+actors) で捕捉" "$BASE" "$TMP/wq4c.html"
perl -0777 -pe 's{</body>}{<span class="en">FAKE-EN(scope外)</span></body>}' "$TMP/good.html" > "$TMP/wq4d.html"
expect_verify_fail "WQ4-d ★行 scope 外 (grow/legend 外) の偽 en を global 占有 (==|非空 en|+legend) で捕捉" "$BASE" "$TMP/wq4d.html"
perl -0777 -pe 's{</body>}{<p>genuine見出し<style>.h{}</style><span class="role">偽承認(混在)</span></p></body>}' "$TMP/good.html" > "$TMP/wq4e.html"
expect_verify_fail "WQ4-e ★テキスト+<style>+偽 role 混在行を surface→global role が捕捉" "$BASE" "$TMP/wq4e.html"

# ===== folio-wq4 fix round 1 (独立 ceiling 発見の parser-differential): make_body を HTML tokenizer 忠実な =====
# state machine に変更し、 非描画領域 (comment/style/script) へ捏造をくるんで $BODY から消す smuggle を一括封鎖。
perl -0777 -pe 's{</body>}{<!-- <style> --><span class="role">偽承認(comment smuggle)</span><!-- </style> --></body>}' "$TMP/good.html" > "$TMP/wq4f1.html"
expect_verify_fail "WQ4-f1 ★comment 内 <style> トークン smuggle (間の実 DOM 隠蔽) を state machine が surface→role 占有で捕捉" "$BASE" "$TMP/wq4f1.html"
perl -0777 -pe 's{</body>}{<style></STYLE><span class="role">偽承認(case)</span></style></body>}' "$TMP/good.html" > "$TMP/wq4f2.html"
expect_verify_fail "WQ4-f2 ★case-insensitive </STYLE> 取りこぼしを閉じ role 占有で捕捉" "$BASE" "$TMP/wq4f2.html"
perl -0777 -pe 's{<div data-component="approval-block">}{<style>HIDE<div data-component="approval-block">}' "$TMP/good.html" > "$TMP/wq4f3.html"
expect_verify_fail "WQ4-f3 ★未閉じ <style> の RAWTEXT 隠蔽 (approval 以降を browser が隠す) を floor 欠落検出で捕捉" "$BASE" "$TMP/wq4f3.html"
perl -0777 -pe 's{</body>}{<script>z="<style>"</script><span class="role">偽承認(script smuggle)</span><script>z="</style>"</script></body>}' "$TMP/good.html" > "$TMP/wq4f4.html"
expect_verify_fail "WQ4-f4 ★script 内 <style> トークン smuggle を opaque-script 処理で閉じ role 占有で捕捉" "$BASE" "$TMP/wq4f4.html"

# ===== folio-wq4 fix round 2 (独立 ceiling round-2 + user 判断=fail-closed): make_body を rendering 完全モデルでなく =====
# genuine 不変条件 (全 < esc 済・style/script clean 形のみ) の機械強制に転換し、 破る入力を fail-closed (空 body→欠落 FAIL)。
perl -0777 -pe 's{</body>}{<div data-x="<style>FAB</style>"><span class="role">偽承認(attr 内 style)</span></div></body>}' "$TMP/good.html" > "$TMP/wq4g1.html"
expect_verify_fail "WQ4-g1 ★属性値内 <style> (open-tag parser-differential) を fail-closed で拒否" "$BASE" "$TMP/wq4g1.html"
perl -0777 -pe 's{</body>}{<style></style x><span class="role">偽承認(不正close)</span></style></body>}' "$TMP/good.html" > "$TMP/wq4g2.html"
expect_verify_fail "WQ4-g2 ★不正 close 文法 </style x> (close-tag parser-differential) を fail-closed で拒否" "$BASE" "$TMP/wq4g2.html"
perl -0777 -pe 's{</body>}{<style></style/><span class="role">偽承認(slash close)</span></style></body>}' "$TMP/good.html" > "$TMP/wq4g3.html"
expect_verify_fail "WQ4-g3 ★不正 close 文法 </style/> を fail-closed で拒否" "$BASE" "$TMP/wq4g3.html"

# ===== folio-6jb render-gate census slice 1: 静的 script-ban (4gz render-time DOM-swap / 459 script-container) =====
# SRS は <script>==0 (verified) ゆえ任意の <script> = 捏造コンテナ。 render を要さず pack-additive 静的 invariant
# (この doc-type の HTML は <script>==0) で原理封鎖する。 検査は verify-srs.sh floor ゆえ expect_srs_fail。
# art.html=健全充填済 artifact を mutate し script 注入のみで FAIL を分離 (script-ban 固有の検出を確認)。
sed 's#</body>#<script>document.querySelector(".who").textContent="偽の取締役会が承認";</script></body>#' "$TMP/art.html" > "$TMP/rg1a.html"
expect_srs_fail "RG1-a ★注入 <script> (render-time DOM-swap container=4gz) を script-ban が捕捉" "$BASE" "$TMP/rg1a.html"
# 459 script-container: 必須要素を <script type=template> で包むと静的 grep を素通しつつ browser 非描画 → script-ban が捕捉。
sed 's#<body>#<body><script type="text/template"><tr data-component="ears-requirement-row" data-req-id="FR99">隠した要件</tr></script>#' "$TMP/art.html" > "$TMP/rg1b.html"
expect_srs_fail "RG1-b ★<script> コンテナで要素を包む OMISSION (459-script) を script-ban が捕捉" "$BASE" "$TMP/rg1b.html"
# case-robust: 大文字 <SCRIPT> も タグ境界 (\b) + case-insensitive で捕捉。
sed 's#</body>#<SCRIPT>void 0;</SCRIPT></body>#' "$TMP/art.html" > "$TMP/rg1c.html"
expect_srs_fail "RG1-c ★大文字 <SCRIPT> (case-robust) を script-ban が捕捉" "$BASE" "$TMP/rg1c.html"

# ===== folio-6jb render-gate census slice 2: 描画後 content-fidelity (2b8 pseudo-content 捏造 / 459 描画後 omission) =====
# census は render を要する gate F の sibling。 renderer 在環境 (A34 と同じ $RGRUN) でのみ実行し、 不在なら honest SKIP。
# genuine art.html を mutate し、 静的 floor (make_body は <style> 空化 / comment verbatim) を素通りする render 依存の
# 捏造 (semantic セレクタ ::after content) / 隠蔽 (comment・条件付き display:none で非描画) を census が捕捉することを確認する。
# 期待件数は contract から導出 (verify-srs.sh と同経路)。 census detector は render-gate-srs.py --census が SSoT (selftest=$RGRUN --census --selftest)。
CEXPECT="ears-requirement-row=$(yq -r '.requirements | length' "$BASE"),nfr-metric-row=$(yq -r '.nfr | length' "$BASE")"
expect_census_fail() { # label html  (render census が exit!=0 を期待)
  if $RGRUN "$SCRIPT_DIR/render-gate-srs.py" --census --expect "$CEXPECT" "$2" >/dev/null 2>&1; then ng "$1 (census が PASS した)"; else ok "$1"; fi
}
expect_census_pass() { # label html
  if $RGRUN "$SCRIPT_DIR/render-gate-srs.py" --census --expect "$CEXPECT" "$2" >/dev/null 2>&1; then ok "$1"; else ng "$1 (census FAIL)"; fi
}
if [[ -z "$RGRUN" ]]; then
  echo "  [SKIP] RG2 census detector (playwright renderer 不在 — CI/uv で render-gate-srs.py --census を実行)"
else
  # census detector の自己検出力 (fixture・kind 完全一致・viewport/scheme plumbing・fail-closed)
  if $RGRUN "$SCRIPT_DIR/render-gate-srs.py" --census --selftest >/dev/null 2>&1; then
    ok "RG2-selftest census detector (pseudo-content 2b8 / 描画後 omission 459 × light/dark × viewport) 全 PASS"
  else ng "RG2-selftest census detector が FAIL"; fi
  # 正対照: genuine artifact は census PASS (捏造/隠蔽なし)
  expect_census_pass "RG2-pass ★genuine artifact は census PASS (描画後 content-fidelity clean)" "$TMP/art.html"
  # RG2-a 2b8: semantic セレクタ .fid に ::after content で偽サフィックス注入 (<style> 追記)。 make_body は <style> 空化で静的素通り。
  perl -0777 -pe 's{</style>}{.fid::after{content:"-改竄済";}\n</style>}' "$TMP/art.html" > "$TMP/rg2a.html"
  expect_census_fail "RG2-a ★pseudo-content 捏造 (.fid::after content=2b8) を census 反転 assert が捕捉" "$TMP/rg2a.html"
  # RG2-b 459-comment: 要件行 1 本を HTML コメントで包む。 静的 grep は数えるが browser 非描画 → 可視 < 期待。
  perl -0777 -pe 's{(<tr[^>]*data-component="ears-requirement-row"[^>]*>.*?</tr>)}{<!-- $1 -->}s' "$TMP/art.html" > "$TMP/rg2b.html"
  expect_census_fail "RG2-b ★comment 隠蔽 OMISSION (459-comment) を census 可視 row count が捕捉" "$TMP/rg2b.html"
  # RG2-c 条件付き omission: 狭幅でのみ NFR 行を display:none。 census の viewport 直積が条件付き隠蔽を捕捉。
  perl -0777 -pe 's{</style>}{\@media(max-width:400px){[data-component="nfr-metric-row"]{display:none!important;}}\n</style>}' "$TMP/art.html" > "$TMP/rg2c.html"
  expect_census_fail "RG2-c ★条件付き隠蔽 (@media 狭幅 display:none) を census viewport 直積が捕捉" "$TMP/rg2c.html"
  # RG2-d 条件付き 2b8: dark scheme でのみ ::after content 注入。 census の scheme 直積が条件付き捏造を捕捉。
  perl -0777 -pe 's{</style>}{\@media(prefers-color-scheme:dark){.fid::after{content:"承認済";}}\n</style>}' "$TMP/art.html" > "$TMP/rg2d.html"
  expect_census_fail "RG2-d ★条件付き捏造 (@media dark .fid::after) を census scheme 直積が捕捉" "$TMP/rg2d.html"
  # RG2-e T7 fail-closed: 全要件/NFR 行を display:none。 可視 0 = render 破綻と判定し broken-render で FAIL (omission 0=clean と取り違えない)。
  perl -0777 -pe 's{</style>}{[data-component="ears-requirement-row"],[data-component="nfr-metric-row"]{display:none!important;}\n</style>}' "$TMP/art.html" > "$TMP/rg2e.html"
  expect_census_fail "RG2-e ★T7 fail-closed (全行 display:none → 可視0 を broken-render で FAIL)" "$TMP/rg2e.html"
fi

# ★folio-wq4: round-7/wq4 ブロックも exit code でゲートする。 旧版は L838 の exit で A1-A138 のみ gate し、
#   round-7 以降の fail (ng) が最終 exit 0 へ漏れる fail-open があった (「検査できた範囲が緑」を exit に正しく反映)。
if [[ "$fail" -ne 0 ]]; then echo "PASS=$pass FAIL=$fail"; echo "RESULT: 取りこぼしあり (round-7/wq4 含む)"; exit 1; fi

if [[ "$gateF_skipped" -eq 1 ]]; then
  echo "RESULT: bash 攻撃を fail-closed で捕捉 (ただし gate F selftest=A34 は renderer 不在で未検査・CI/uv で要実行)"
else
  echo "RESULT: 全攻撃を fail-closed で捕捉"
fi
exit 0
