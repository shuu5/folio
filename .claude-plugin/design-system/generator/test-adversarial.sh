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
# repro-build arm (verify_repro_build・folio-3d23) は verify-*.sh 既定 ON。 bulk case は honest skip で 10 分/suite を維持
# (arm 未 skip は assemble 再 build で timeout 実測)、 conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
export SKIP_REPRO="${SKIP_REPRO:-1}"
source "$SCRIPT_DIR/lib/test-repro-pins.sh"
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
# ★repro-build conformance (folio-3d23 B3) は render 非依存ゆえ、 render-gate 依存の A34 早期 exit (renderer 不在で
#   FAIL→中間 gate exit) より *前* に置き、 renderer 有無に関係なく必ず走らせる (verify-srs 経路で arm を実走)。
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
if repro_pins "$SRS" srs "$BASE" "$BASE_PROSE" "$ASM" "$INJ"; then ok "repro-build conformance (a-d) 全 pass"; else ng "repro-build conformance (a-d) 逸脱"; fi
# gate A-E,G,H (bash) の fail-closed を検査する arm ゆえ重い gate F (playwright) は SRS_SKIP_RENDER で外す
# (gate F の回帰は末尾の render-gate-srs --selftest arm が別途担う)。
expect_srs_pass() { if SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (floor FAIL)"; fi; }
expect_srs_fail() { if SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" >/dev/null 2>&1; then ng "$1 (floor PASS した)"; else ok "$1"; fi; }

# === 数値文字参照 decode 変種 red pin (folio-5u3k・reason-gated・srs floor) ===
# lib/verify-common.sh の decode widen が entity 偽装 class を可視 token へ decode し占有検査が捕捉することを pin。
# 素の rc!=0 pin は novelty scan が decode 幅と無関係に赤くするため、vcount who 側 FAIL 行を対で掴む (c5r.2 基準)。
# (U3K1-3 が anchor する vcount who は第 1 層の件数照合として存続。U3K4 = reader-chip 占有 pin は folio-smby で退役済。)
u3k_srs_pin() { # label decoy_html expected_fail_substring
  cp "$TMP/good.html" "$TMP/u3ksrs.html"
  DECOY="$2" perl -0777 -i -pe 's{</h1>}{"</h1>" . $ENV{DECOY}}e' "$TMP/u3ksrs.html"
  local out rc; out="$(SRS_SKIP_RENDER=1 bash "$SRS" "$BASE" "$TMP/u3ksrs.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (verify PASS = entity 偽装 class が素通り)"; return; fi
  if grep -F -- "$3" <<<"$out" | grep -q '\[FAIL\]'; then ok "$1"; else ng "$1 (FAIL は別理由 = 占有 decode 不発が novelty に masking されている)"; fi
}
u3k_srs_pin "U3K1 ★大文字 16進 entity class (&#X77;ho → who) を占有 vcount who が decode 捕捉" '<span class="&#X77;ho">x</span>' 'vcount who'
u3k_srs_pin "U3K2 ★semicolon-less 16進 entity class (&#x77ho → who) を占有 vcount who が decode 捕捉" '<span class="&#x77ho">x</span>' 'vcount who'
u3k_srs_pin "U3K3 ★semicolon-less 10進 entity class (&#119ho → who) を占有 vcount who が decode 捕捉" '<span class="&#119ho">x</span>' 'vcount who'
# 〔folio-mzn.3〕機械/LLM 境界 (verification §3.9): 静的 hidden-render ban 群 + visual-deception ban は
# warn 級 backstop (非 blocking)。 seed は「detector が [WARN] で発火する」+「blocking しない (exit 0)」の
# 両方を assert する。 fake 計数部品を注入する seed は census-count blocking arm も同時に発火するため
# expect_srs_warn_and_fail で「warn 発火 + blocking FAIL」を assert する (多層防御の固定)。
expect_srs_warn() { # label contract html warn-pattern (exit 0 かつ [WARN] 行に pattern)
  local out rc; out="$(SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]] && printf '%s\n' "$out" | grep -F '[WARN]' | grep -q "$4"; then ok "$1"
  elif [[ $rc -ne 0 ]]; then ng "$1 (warn 級のはずが exit $rc = blocking)"
  else ng "$1 ([WARN] $4 が発火しない)"; fi
}
expect_srs_warn_and_fail() { # label contract html warn-pattern (warn 発火 かつ blocking FAIL = exit!=0)
  local out rc; out="$(SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F '[WARN]' | grep -q "$4"; then ok "$1"
  elif [[ $rc -eq 0 ]]; then ng "$1 (blocking FAIL しない)"
  else ng "$1 ([WARN] $4 が発火しない)"; fi
}
expect_srs_fail_at() { # label contract html fail-pattern (exit!=0 かつ [FAIL] 行に pattern = 検出の出所を固定)
  local out rc; out="$(SRS_SKIP_RENDER=1 bash "$SRS" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F '[FAIL]' | grep -q "$4"; then ok "$1"
  else ng "$1 (exit=$rc / [FAIL] $4 不発火)"; fi
}
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
# A28f. ★i6f9: 属性なしの偽 sibling <div>機械SSoT:...</div> を footer へ注入 — canonical 捕捉は
#       data-audience 付き div に絞られたため count 検査だけでは漏れる (ds8 sibling 封鎖の再開通 hole)。
#       token 総数 pin (機械SSoT / 検証状態 が body 全体でちょうど 1 回) がタグ形状非依存で捕捉。
sed 's#</footer>#<div>機械SSoT: <b>fake-origin.yaml</b> (偽の出所表示)</div></footer>#' "$TMP/art.html" > "$TMP/fakesibling.html"
expect_srs_fail "A28f ★属性なし偽 sibling 機械SSoT div を token 総数 pin で捕捉" "$BASE" "$TMP/fakesibling.html"
# A28g. ★i6f9: 偽 sibling の token を数値文字参照で偽装 (&#x6a5f;械SSoT = 描画は 機械SSoT) — literal count を
#       素通るため decode 面で数える (count_attr_token の entity-decode 規律を token pin へ適用)。
sed 's#</footer>#<div>\&\#x6a5f;械SSoT: <b>fake-origin.yaml</b> (偽の出所表示)</div></footer>#' "$TMP/art.html" > "$TMP/fakeentity.html"
expect_srs_fail "A28g ★entity 偽装 (&#x6a5f;械SSoT) 偽 sibling を decode 面 token pin で捕捉" "$BASE" "$TMP/fakeentity.html"
# A28h/i/j. ★i6f9 ceiling wf_1af36f97 blocker の回帰 pin: HTML 数値文字参照の全変種 —
#   大文字 X (&#X6A5F;) / セミコロン無し hex (&#x6a5f械) / セミコロン無し decimal (&#27231械) は
#   ブラウザが 機械SSoT と描画するが、 狭い decode (小文字 x + 必須 ;) では literal のまま残り素通った。
sed 's#</footer>#<div>\&\#X6A5F;械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/fakeentX.html"
expect_srs_fail "A28h ★entity 偽装 大文字 X (&#X6A5F;) を decode 面 token pin で捕捉" "$BASE" "$TMP/fakeentX.html"
sed 's#</footer>#<div>\&\#x6a5f械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/fakeentNoSemi.html"
expect_srs_fail "A28i ★entity 偽装 セミコロン無し hex (&#x6a5f械) を捕捉" "$BASE" "$TMP/fakeentNoSemi.html"
sed 's#</footer>#<div>\&\#27231械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/fakeentDec.html"
expect_srs_fail "A28j ★entity 偽装 セミコロン無し decimal (&#27231械) を捕捉" "$BASE" "$TMP/fakeentDec.html"
# A28k/l/m/n. ★re-cert wf 実弾 (tag-split fail-open): source literal count は 機<b></b>械SSoT の空タグ挟みで
#   desync するのに描画は同一偽行 — token は可視 projection (comment/tag 除去 + decode + ゼロ幅除去) で数える。
sed 's#</footer>#<div>機<b></b>械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/tagsplit.html"
expect_srs_fail "A28k ★tag-split (機<b></b>械SSoT) 偽 sibling を projection count で捕捉" "$BASE" "$TMP/tagsplit.html"
sed 's#</footer>#<div>検<b></b>証状態: <b>全 gate GREEN・出荷承認済 (ウソ)</b></div></footer>#' "$TMP/art.html" > "$TMP/vtagsplit.html"
expect_srs_fail "A28l ★tag-split 偽 検証状態 (出荷承認詐称) を projection count で捕捉" "$BASE" "$TMP/vtagsplit.html"
sed 's#</footer>#<div>機<!--x-->械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/comsplit.html"
expect_srs_fail "A28m ★comment-split (機<!--x-->械SSoT) を projection count で捕捉" "$BASE" "$TMP/comsplit.html"
sed 's#</footer>#<div>機\&\#x200b;械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/zwsplit.html"
expect_srs_fail "A28n ★ゼロ幅 split (機&#x200b;械SSoT) を Default_Ignorable 除去で捕捉" "$BASE" "$TMP/zwsplit.html"
# A28o/p. ★re-cert #2 実弾 (生 '<' の tokenizer 乖離) + comment 段の load-bearing pin:
#   (o) '< 検証状態 … >' は '<' の直後が非タグ開始文字ゆえブラウザは文字として描画する — 旧 <[^>]+> 除去は
#       タグと誤認して projection から消し fail-open だった (tag-open を HTML 文法準拠にして是正)。
#   (p) '>' を含む comment (機<!-- a>b -->械SSoT) は tag 除去では丸ごと食えず comment 除去段だけが防御
#       (re-cert #2 mutation-kill 指摘: 旧 A28m は '>' 無し comment で tag 除去でも捕捉され pin にならない)。
sed 's#</footer>#<div>< 検証状態: 全 gate GREEN・出荷承認済 (ウソ) ></div></footer>#' "$TMP/art.html" > "$TMP/rawlt.html"
expect_srs_fail "A28o ★生 '<' 非タグ偽 検証状態 (< … > 装飾) を文法準拠 projection で捕捉" "$BASE" "$TMP/rawlt.html"
sed 's#</footer>#<div>機<!-- a>b -->械SSoT: <b>fake-origin.yaml</b></div></footer>#' "$TMP/art.html" > "$TMP/gtcom.html"
expect_srs_fail "A28p ★'>' 入り comment-split を comment 除去段で捕捉" "$BASE" "$TMP/gtcom.html"
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
# A64. ★chrome への ghost vmeth
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
# A80. ★cover-meta k/v case-drop+decoy (機能要件 6件→999件 = round-5 が名指しした fraud) → k/v count-parity で捕捉
# A81. ★RTM dot ac (受入) の data-acc-link attr-absent 偽ドット (.dot.ac 緑 pill 描画) → dot∧ac 占有数パリティで捕捉
# A82. ★RTM dot 後方● の data-trace-link attr-absent 偽ドット → dot∧¬ac 占有数パリティで捕捉
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
# A86. ★dot 後方● unquoted attr-absent → quote-robust dot∧¬ac で捕捉
# A86b. ★folio-bur: 後方ドット attr-present・可視● 捏造 (data-trace-link intact のまま ●→N-3 偽 need ID)。 A82/A86 は attr-absent
#   偽ドットを件数で捕捉するが、 attr/class/件数 intact のまま span 内可視テキストだけ捏造する fail-open は別物 (visible-text-vs-attribute)。
#   (j3) 可視==● 固定記号 pin で封鎖 (acc ドット j2 と対称)。
# A86c/d ★folio-bur round-2 (ceiling-recursion): j3 span-inner の射程外を突く 2 bypass を full-cell remainder + ● glyph パリティで捕捉。
# A86e/f/g ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 fix 自体の残存 fail-open。
#   (e) confusable ⚫(U+26AB) を空セルへ (grep -o '●' は exact U+25CF のみ数え占有数を欺く) → RTM partition 不変条件 (j3c) で捕捉
#   (f) 裸テキスト need-ID を空セルへ (グリフ占有数の射程外) → RTM partition 不変条件 (j3c) で捕捉
#   (g) scope バレットから ● を略奪し comment へ退避 (global ● 数保存) → per-source ● パリティ (j3d) で捕捉
body_tamper_fail "A86g ★scope バレット ● を略奪し comment 退避 (global ● 保存) → per-source ● パリティで捕捉" '<span class="b">●</span>' '<span class="b"></span><!--●-->'
# A86h/i/j ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 j3c/j 自体の残存 fail-open。
#   (h) 表タグを single-quote 化し anchor を外して partition を vacuous-pass させ ⚫ を空セルへ → quote-robust 列挙で捕捉
#   (i) 2 個目 <table class="rtm"> を追記 (first-match の射程外) → table.rtm 占有==1 で捕捉
#   (j) <th id="z"> 属性付き偽要件行を注入 (literal <tr><th> anchor の射程外) → attr 許容 row-heading 突合で捕捉
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
# (b) decoy 注入 (残存の第 1 層 = vcount who / 想定読者値突合が捕捉。一般の decoy クラスは repro-build byte-identity が構造終端・folio-smby)
chrome_decoy_fail "A123 ★sign 行 大文字化 decoy (偽承認行) を vcount who 件数照合で捕捉" '<div class="SIGN"><span class="role">詐欺</span><span class="who">x</span><span class="when">y</span><span class="stamp">z</span></div>'
chrome_decoy_fail "A126 ★who entity-encoded decoy (&#119;ho) を文字参照 decode 込み vcount who で捕捉" '<span class="&#119;ho">詐欺の承認者</span>'
chrome_decoy_fail "A129 ★想定読者 marker decoy (偽 reader-chip) を想定読者 値突合で捕捉" '<div class="reader-chip"> 想定読者: 詐欺の第二読者</div>'
# A130 ★marker *無し* の偽 reader-chip decoy (`class="reader-chip">` anchor 一致だが "想定読者:" 無し) を構造 anchor 占有数で捕捉。
#       marker count に keyed した A129 では捕捉できない fail-open を anchor 占有数パリティ (genuine == 1) で塞いだ回帰 (folio-mk9 self-review)。
# A130b ★ref-chip *構文形* の偽 reader-chip decoy (`class="reader-chip" role="note">…` = 閉じ引用後に空白+任意属性) を占有数パリティで捕捉。
#        A130 の anchor grep (`class="reader-chip">` = > 直後) は > 直後でないため不一致・marker count も "想定読者:" 無しで不一致ゆえ素通る fail-open を
#        (class reader-chip 占有) − (data-component cross-doc-ref-chip 占有) == 1 で塞いだ回帰 (folio-mk9 self-review round-3)。
# A130c ★ref-chip と *同一構文* (class="reader-chip" data-component="cross-doc-ref-chip") を持つ additive decoy に偽『想定読者:』text を載せた攻撃。
#        旧 差分式 `(class reader-chip 占有) − (cross-doc-ref-chip 占有)` は被減数 (+1)・減数 (+1) が同タグ上で同時に増えて差 1 のまま不変ゆえ素通った
#        (folio-mk9 self-review round-4 が SRS full verify exit 0 で実証)。 element-level genuine count + global『想定読者:』marker count==1 で塞いだ回帰。
# A130d ★ref-chip 同一構文 (class="reader-chip" data-component="cross-doc-ref-chip") で marker を *持たない* 任意 text の additive decoy。
#        element-level genuine count は ref-chip 側へ分類し count を増やさず・global『想定読者:』marker も marker 無しゆえ不変 = SRS で素通る fail-open
#        (folio-mk9 self-review round-5)。 SRS は cross_doc を持たず ref-chip 不在ゆえ reader-chip class 総数 == 1 (§7b'') で捏造 ref-chip box を封鎖した回帰。
# A130e ★A130d の single-quote data-component 変種 (quote-robust count_attr_token が classify) も封鎖。
# A130f ★属性値内 > で count_genuine の tag-splitter を断片化した genuine-style decoy (folio-mk9 self-review round-6・FO-2)。
#        SRS は §7b'' の reader-chip 総数==1 (count_attr_token 全文走査=>-attr 非依存) で既に封鎖。 tag-splitter 堅牢化 + 総数 bind の二層回帰。
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
# A133 ★partition: round-4 outer (.*?)</table> は入れ子 <table></table> で early-term (ds8 nested-same-tag 機構の <table> 再発) → truncation 後の捏造セル未 partition。nested-table-reject で捕捉。
# A134 ★partition: stray </table> (開タグ無し) で outer (.*?)</table> を早期終端させ後続セルを未 partition 化する経路を table 開閉タグ平衡で捕捉。
# A135-A138 ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 fix 自体の残存 sibling fail-open (§7g scol 未 region-recon / act_rtmh th-only 死角 / EXEMPT 静的 chrome 占有欠如)。
# A135 ★§7g scol: 2 個目 scol-in block (偽 in-scope 宣言) を first-match `if` 死角へ注入 → scol 占有==2 + region-recon で捕捉
if python3 -c "
d=open('$TMP/good.html').read()
o='<div class=\"scol out\">'; assert o in d
open('$TMP/g_scol2.html','w').write(d.replace(o,'<div class=\"scol in\"><ul><li>偽: 全顧客の個人情報を無断で第三者に販売する</li></ul></div>'+o,1))
" 2>/dev/null; then expect_verify_fail "A135 ★§7g 2個目 scol-in 偽 in-scope 宣言を scol 占有+region-recon で捕捉" "$BASE" "$TMP/g_scol2.html"; else ng "A135 setup 失敗"; fi
# A136 ★act_rtmh: td 無し <th> 単独 phantom 行 (rtm tbody・class lt は EXEMPT) → rtm <tr> 占有で捕捉
# A137 ★EXEMPT 静的 chrome: duplicate <p class=lab> 偽ラベル → lab 占有==1 で捕捉
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

# ===== folio-wq4 回帰: make_body substrate (style co-located) + occupancy global pin (blocker 1+3) =====
# blocker 1: 旧 make_body (sed '/<style>/,/</style>/d' 行範囲削除) は <style> 同居行の実 DOM 捏造を巻き込み消去し
#   verify を偽 PASS させた。 新 make_body (perl 中身空化) は捏造を $BODY に surface させ既存/新 occupancy が捕捉する。
perl -0777 -pe 's{</body>}{<p><style>.wq4{color:red}</style><span class="aid">捏造AC(style同居)</span></p></body>}' "$TMP/good.html" > "$TMP/wq4a.html"
expect_verify_fail "WQ4-a ★<style>同居行の偽 aid を make_body 中身空化で surface→aid 占有が捕捉 (旧 sed 行範囲削除は素通り)" "$BASE" "$TMP/wq4a.html"

# ===== folio-wq4 fix round 1 (独立 ceiling 発見の parser-differential): make_body を HTML tokenizer 忠実な =====
# state machine に変更し、 非描画領域 (comment/style/script) へ捏造をくるんで $BODY から消す smuggle を一括封鎖。
perl -0777 -pe 's{<div data-component="approval-block">}{<style>HIDE<div data-component="approval-block">}' "$TMP/good.html" > "$TMP/wq4f3.html"
expect_verify_fail "WQ4-f3 ★未閉じ <style> の RAWTEXT 隠蔽 (approval 以降を browser が隠す) を floor 欠落検出で捕捉" "$BASE" "$TMP/wq4f3.html"

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
# (この doc-type の HTML は <script>==0) で検出する。 〔mzn.3〕境界 (§3.9) 下で静的 ban 群は warn 級 backstop
# (非 blocking) ゆえ expect_srs_warn (detector 発火 + exit 0)。 fake 計数部品を伴う seed は census-count blocking
# arm が同時に発火するため expect_srs_warn_and_fail (多層防御)。
sed 's#</body>#<script>document.querySelector(".who").textContent="偽の取締役会が承認";</script></body>#' "$TMP/art.html" > "$TMP/rg1a.html"
expect_srs_warn "RG1-a ★注入 <script> (render-time DOM-swap container=4gz) を script-ban が warn 検出 (非 blocking)" "$BASE" "$TMP/rg1a.html" "script-ban"
# 459 script-container: 必須要素を <script type=template> で包むと静的 grep を素通しつつ browser 非描画。
# script-ban warn + <script> 内 fake ears-requirement-row を census-count が excess として blocking 捕捉 (make_body は script 中身を保持)。
sed 's#<body>#<body><script type="text/template"><tr data-component="ears-requirement-row" data-req-id="FR99">隠した要件</tr></script>#' "$TMP/art.html" > "$TMP/rg1b.html"
expect_srs_warn_and_fail "RG1-b ★<script> コンテナ内 fake 要件行 (459-script) = script-ban warn + census-count blocking" "$BASE" "$TMP/rg1b.html" "script-ban"
# case-robust: 大文字 <SCRIPT> も タグ境界 (\b) + case-insensitive で捕捉。
sed 's#</body>#<SCRIPT>void 0;</SCRIPT></body>#' "$TMP/art.html" > "$TMP/rg1c.html"
expect_srs_warn "RG1-c ★大文字 <SCRIPT> (case-robust) を script-ban が warn 検出 (非 blocking)" "$BASE" "$TMP/rg1c.html" "script-ban"

# ===== folio-6jb 次元B (ws4o6ywe5): visual-deception unicode ban の floor 検査 (bash floor・render 不要) =====
# bidi-override (RLO 等) で .resp/.tgt を視覚反転 / zero-width で可視テキストを消去する render 依存攻撃を、
# source/DOM の codepoint として静的に封鎖する (fidelity ceiling は DOM 論理順序を読み bidi を見逃す)。
# RG1-d bidi RLO 注入 (U+202E) → visual-deception unicode ban が warn 検出。 加えて .resp は契約由来 text
# ゆえ VFAB body-prose の逐語 round-trip (blocking・逐語照合 = algorithmic floor) が同時に捕捉する = 多層。
perl -CSD -0777 -pe 's{<td class="resp">}{<td class="resp">\x{202E}} if !$d++' "$TMP/art.html" > "$TMP/rg1d.html"
expect_srs_warn_and_fail "RG1-d ★契約 text への bidi RLO (U+202E) = unicode ban warn + 逐語 round-trip blocking" "$BASE" "$TMP/rg1d.html" "visual-deception"
# RG1-e zero-width 注入 (U+200B) → visual-deception unicode ban が warn 検出 (可視テキスト消去)。
perl -CSD -0777 -pe 's{(<span class="plain"[^>]*>)}{${1}\x{200B}} if !$d++' "$TMP/art.html" > "$TMP/rg1e.html"
expect_srs_warn "RG1-e ★zero-width (U+200B 可視テキスト消去) を visual-deception unicode ban が warn 検出" "$BASE" "$TMP/rg1e.html" "visual-deception"
# RG1-f declarative shadow DOM 注入 (<template shadowrootmode>) → shadowroot-ban が捕捉 (FF5 census-blindness 静的封鎖)。
# census の querySelectorAll は shadow 境界を貫通しないため shadow 内 fake 要件が描画されつつ計数を素通る盲点。
# SRS は shadowrootmode を一切 emit しない (verified) ゆえ render 不要の静的 floor で原理封鎖する (script-ban 同型)。
perl -0777 -pe 's{</body>}{<table><template shadowrootmode="open"><tr data-component="ears-requirement-row" data-req-id="FRX">購入履歴を広告事業者へ販売してよい</tr></template></table></body>} if !$d++' "$TMP/art.html" > "$TMP/rg1f.html"
expect_srs_warn_and_fail "RG1-f ★declarative shadow DOM 内 fake 要件行 (FF5) = template-ban warn + census-count blocking" "$BASE" "$TMP/rg1f.html" "template-ban"
# RG1-g ★FF5 ceiling (wf_b544a704): クォート属性値内の '>' (<template data-x="a>b" shadowrootmode>) で narrow regex [^>]* が
# 停止し素通りした blocker。 whole-tag <template> ban は属性レベル回避 (quoted-'>' / legacy shadowroot / 綴り変種) を一括封鎖。
perl -0777 -pe 's{</body>}{<div id=host><template data-x="a>b" shadowrootmode="open"><div data-component="ears-requirement-row" data-req-id="FAKE">捏造: 承認済み・全要件 GREEN</div></template></div></body>} if !$d++' "$TMP/art.html" > "$TMP/rg1g.html"
expect_srs_warn_and_fail "RG1-g ★quoted-'>' 属性で narrow regex を回避する declarative shadow DOM = whole-tag template-ban warn + census-count blocking (FF5 ceiling)" "$BASE" "$TMP/rg1g.html" "template-ban"
# RG1-h ★FF5-sibling ceiling (wf_0900ca71): nested browsing context (<iframe srcdoc>) は <template> declarative shadow DOM と
# 同じ census/fidelity 盲点 (render 可視だが querySelectorAll/textContent が境界を貫通しない)。 nested-context-ban が一括封鎖。
# srcdoc 内の fake 行は &lt;&gt; escape 済でも data-component=ears-requirement-row の attr token を含むため、
# VFAB 占有 pin (r7・quote 非依存の robust token count) が件数超過で blocking 捕捉する = 多層 (件数照合 = blocking floor)。
perl -0777 -pe 's{</body>}{<iframe srcdoc="&lt;div data-component=ears-requirement-row data-req-id=FAKE&gt;捏造: 全要件 GREEN&lt;/div&gt;"></iframe></body>} if !$d++' "$TMP/art.html" > "$TMP/rg1h.html"
expect_srs_warn_and_fail "RG1-h ★nested browsing context 内 fake 行 (<iframe srcdoc>) = nested-context-ban warn + 占有 pin blocking (FF5-sibling ceiling)" "$BASE" "$TMP/rg1h.html" "nested-context-ban"
# RG1-i ★FF5 ceiling round-3 (wf_4b5bffa2): data: 画像サブリソース (<img src=data:image/svg...text>) は偽要件を描画しつつ
# body.textContent に現れない census/fidelity 両盲点。 inline-only-ban (<img + data:) が doc-type 不変条件で封鎖。
perl -0777 -pe 's{</body>}{<img src="data:image/svg+xml,%3Csvg%3E%3Ctext%3E偽要件FR-99%3C/text%3E%3C/svg%3E" style="max-width:100%">} if !$d++' "$TMP/art.html" > "$TMP/rg1i.html"
expect_srs_warn "RG1-i ★data: 画像サブリソース (<img src=data:>) による hidden-render を inline-only-ban が warn 検出 (FF5 ceiling round-3)" "$BASE" "$TMP/rg1i.html" "inline-only-ban"
# RG1-j ★FF5 ceiling round-3: form control (<input value>) は value を描画しつつ textContent に含まれない。 inline-only-ban が warn 検出。
perl -0777 -pe 's{</body>}{<input type="text" readonly value="FAKE 偽要件 全GREEN">} if !$d++' "$TMP/art.html" > "$TMP/rg1j.html"
expect_srs_warn "RG1-j ★form control (<input value>) の DOM-text 不可視 render を inline-only-ban が warn 検出 (FF5 ceiling round-3)" "$BASE" "$TMP/rg1j.html" "inline-only-ban"
# RG1-k ★FF5 ceiling round-3b (wf_3652702e): data: ban の char-ref bypass (data&#58;/data&colon; を style attr に置くと
# HTML parser が生 /data:/ grep の *後* に ':' へ decode し素通り)。 url(#fragment 以外) ban が url( token 直後の非 '#' で
# char-ref 非依存に捕捉 (url( と直後の 'd' は raw HTML に literal)。
perl -0777 -pe 's{</body>}{<div style="background:url(data&#58;image/svg+xml,%3Csvg%3E%3Ctext%3E偽要件FR99%3C/text%3E%3C/svg%3E) no-repeat;width:340px;height:44px"></div></body>} if !$d++' "$TMP/art.html" > "$TMP/rg1k.html"
expect_srs_warn "RG1-k ★char-ref encoded data: (background:url(data&#58;)) を url(#fragment以外) ban が warn 検出 (FF5 ceiling round-3b)" "$BASE" "$TMP/rg1k.html" "url(#fragment 以外"
# RG1-l ★round-3c (wf_534bb2c7): generated-content scroll pseudo (::scroll-button/::scroll-marker) は偽要件を可視描画するが
# 旧 census は ::before/::after/::marker のみ走査し fidelity textContent も blind だった (carve agent 実証)。 census 側を
# scroll-pseudo 走査へ拡張済 (computed-style spelling-agnostic な render 側一次防御)。 静的 scroll-pseudo-ban が literal
# spelling を render 不在環境でも backstop で捕捉する (script-ban 同型の genuine vocabulary 補集合・FP-free)。
perl -0777 -pe 's{</style>}{.sc{overflow-x:auto}.sc::scroll-button(right){content:"偽要件FR99 不正な権限昇格"}\n</style>}' "$TMP/art.html" > "$TMP/rg1l.html"
expect_srs_warn "RG1-l ★generated-content ::scroll-button を scroll-pseudo-ban (静的 backstop) が warn 検出 (round-3c)" "$BASE" "$TMP/rg1l.html" "scroll-pseudo-ban"
# RG1-m ★round-3d (wf_6e852552): list-marker テキストは content を経由せず @counter-style + list-style-type で ::marker に
# 生成され census/fidelity を両盲点する (新次元)。 @counter-style を list-marker-ban が静的封鎖。
perl -0777 -pe 's{</style>}{\@counter-style frx{system:cyclic;symbols:"FR99 偽の追加要件 不正な権限昇格"} li.atkm{display:list-item;list-style-type:frx}\n</style>}' "$TMP/art.html" > "$TMP/rg1m.html"
expect_srs_warn "RG1-m ★@counter-style generated marker 捏造 (list-marker 新次元) を list-marker-ban が warn 検出 (round-3d)" "$BASE" "$TMP/rg1m.html" "list-marker-ban"
# RG1-n ★round-3d: @counter-style 不要の簡易変種 = 文字列リテラル list-style-type で ::marker に偽テキスト生成。
perl -0777 -pe 's{</style>}{li.atkn{display:list-item;list-style-type:"FR98 偽: 管理者バイパス "}\n</style>}' "$TMP/art.html" > "$TMP/rg1n.html"
expect_srs_warn "RG1-n ★文字列 list-style-type generated marker (list-marker 新次元・簡易変種) を list-marker-ban が warn 検出 (round-3d)" "$BASE" "$TMP/rg1n.html" "list-marker-ban"
# RG1-o〜p ★round-3e (wf_27813514): <progress>/<meter> の ::-webkit-progress-* は background-image を実描画するが getComputedStyle が
# 'none' を返し render census が盲 (pe 拡張 no-op)。 form-associated 要素閉包の欠落補完として inline-only-ban タグ集合に追加。
perl -0777 -pe 's{</body>}{<progress value="0.55" max="1"></progress></body>}' "$TMP/art.html" > "$TMP/rg1o.html"
expect_srs_warn "RG1-o ★<progress> (::-webkit-progress-* image-sink・census 構造盲) を inline-only-ban が warn 検出 (round-3e)" "$BASE" "$TMP/rg1o.html" "inline-only-ban"
perl -0777 -pe 's{</body>}{<meter value="0.5"></meter></body>}' "$TMP/art.html" > "$TMP/rg1p.html"
expect_srs_warn "RG1-p ★<meter> (form-associated・::-webkit-meter-* image-sink) を inline-only-ban が warn 検出 (round-3e)" "$BASE" "$TMP/rg1p.html" "inline-only-ban"
# RG1-q〜r ★round-3e: <bdo dir=rtl> / CSS unicode-bidi:override は制御 codepoint 無しで視覚反転し次元B unicode ban を回避。
perl -0777 -pe 's{</body>}{<bdo dir="rtl">払い戻しを常に拒否する</bdo></body>}' "$TMP/art.html" > "$TMP/rg1q.html"
expect_srs_warn "RG1-q ★<bdo dir=rtl> 視覚反転 (制御 codepoint 無し) を bidi-override-ban が warn 検出 (round-3e)" "$BASE" "$TMP/rg1q.html" "bidi-override-ban"
perl -0777 -pe 's{</style>}{.atkbidi{unicode-bidi:bidi-override;direction:rtl}\n</style>}' "$TMP/art.html" > "$TMP/rg1r.html"
expect_srs_warn "RG1-r ★CSS unicode-bidi:bidi-override 視覚反転を bidi-override-ban が warn 検出 (round-3e)" "$BASE" "$TMP/rg1r.html" "bidi-override-ban"

# ===== folio-mzn.3 census-count blocking arm (REQ-VER-024): source DOM 静的件数 ↔ contract 期待件数 =====
# 境界 (§3.9) の blocking 件数照合 (render 不要)。 件数不一致を omission/excess 両方向とも fail-closed で
# exit 1 に倒し、 [FAIL] 行の census-count 帰属も assert する (検出の出所を固定)。 conformance seed は
# REQ-VER-024 の「census-count は件数不一致 fixture の fail-closed seed で固定する」に対応。
# CC-a omission: genuine 要件行 1 本を丸ごと削除 (source 件数 < contract 期待)。
perl -0777 -pe 's{<tr[^>]*data-component="ears-requirement-row"[^>]*>.*?</tr>}{}s' "$TMP/art.html" > "$TMP/cca.html"
expect_srs_fail_at "CC-a ★要件行の source 削除 (件数 omission) を census-count arm が fail-closed で捕捉" "$BASE" "$TMP/cca.html" "census-count"
# CC-b excess: genuine 要件行 1 本を複製 (source 件数 > contract 期待・件数水増しの静的層)。
perl -0777 -pe 's{(<tr[^>]*data-component="ears-requirement-row"[^>]*>.*?</tr>)}{$1$1}s' "$TMP/art.html" > "$TMP/ccb.html"
expect_srs_fail_at "CC-b ★要件行の複製 (件数 excess) を census-count arm が捕捉" "$BASE" "$TMP/ccb.html" "census-count"
# CC-c .plain 縮退: 平易説明 span の class 改名で source 件数を 1 減 (他の blocking 検査に依存しない純 census-count seed)。
perl -0777 -pe 's{class="plain"}{class="plainx"} if !$d++' "$TMP/art.html" > "$TMP/ccc.html"
expect_srs_fail_at "CC-c ★.plain class 改名 (.plain 件数不一致) を census-count arm が捕捉" "$BASE" "$TMP/ccc.html" "census-count"


# ★folio-wq4: round-7/wq4 ブロックも exit code でゲートする。 旧版は L838 の exit で A1-A138 のみ gate し、
#   round-7 以降の fail (ng) が最終 exit 0 へ漏れる fail-open があった (「検査できた範囲が緑」を exit に正しく反映)。
if [[ "$fail" -ne 0 ]]; then echo "PASS=$pass FAIL=$fail"; echo "RESULT: 取りこぼしあり (round-7/wq4 含む)"; exit 1; fi

if [[ "$gateF_skipped" -eq 1 ]]; then
  echo "RESULT: bash 攻撃を fail-closed で捕捉 (ただし gate F selftest=A34 は renderer 不在で未検査・CI/uv で要実行)"
else
  echo "RESULT: 全攻撃を fail-closed で捕捉"
fi
exit 0
