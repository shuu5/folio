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
perl -0777 -pe 's#(<tr data-component="nfr-metric-row"><td><span class="nid">)NFR1(</span>)#${1}NFRX${2}#' "$TMP/good.html" > "$TMP/g_nnid.html"
expect_verify_fail "A49 nfr 表 nid 捏造を 7f(i) が捕捉" "$BASE" "$TMP/g_nnid.html"
# A50. ★要件行 *内* の priority ラベル改竄 (legend の静的 badge でなく row-scope) → §7f(h)
perl -0777 -pe 's#(data-req-id="FR1".*?priority-badge">)必須(</span> <span class="vmeth">)#${1}任意${2}#s' "$TMP/good.html" > "$TMP/g_prio.html"
expect_verify_fail "A50 要件行内 priority ラベル改竄を 7f(h) が捕捉 (legend と非混線)" "$BASE" "$TMP/g_prio.html"
# A51. 要件行 vmethod 改竄 (T→D・両方 valid letter ゆえ gate D 集合検査を貫通) → §7f(h) 順序値突合
perl -0777 -pe 's#(data-req-id="FR1".*?<span class="vmeth">)T(</span>)#${1}D${2}#s' "$TMP/good.html" > "$TMP/g_vm.html"
expect_verify_fail "A51 要件行 vmethod 改竄 (T→D) を 7f(h) が捕捉" "$BASE" "$TMP/g_vm.html"
# A52. nfr 区分 (category) 改竄 → §7f(i)
perl -0777 -pe 's#(nfr-metric-row"><td><span class="nid">NFR1</span></td><td>)性能(</td>)#${1}捏造区分${2}#' "$TMP/good.html" > "$TMP/g_cat.html"
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

echo
echo "PASS=$pass FAIL=$fail"
if [[ "$fail" -ne 0 ]]; then echo "RESULT: 取りこぼしあり"; exit 1; fi
if [[ "$gateF_skipped" -eq 1 ]]; then
  echo "RESULT: bash 攻撃を fail-closed で捕捉 (ただし gate F selftest=A34 は renderer 不在で未検査・CI/uv で要実行)"
else
  echo "RESULT: 全攻撃を fail-closed で捕捉"
fi
exit 0
