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
echo "PASS=$pass FAIL=$fail"
if [[ "$fail" -ne 0 ]]; then echo "RESULT: 取りこぼしあり"; exit 1; fi
if [[ "$gateF_skipped" -eq 1 ]]; then
  echo "RESULT: bash 攻撃を fail-closed で捕捉 (ただし gate F selftest=A34 は renderer 不在で未検査・CI/uv で要実行)"
else
  echo "RESULT: 全攻撃を fail-closed で捕捉"
fi
exit 0
