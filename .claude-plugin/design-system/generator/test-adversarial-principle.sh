#!/usr/bin/env bash
# folio engine B4 (folio-igv) — principle-pack 敵対回帰テスト (instance#4)
#
# principle-pack の fail-closed gate (assemble-principle validate abort / verify-principle FAIL / inject abort) が
# 構造捏造・★前方照会注入 (終端不変条件)・★silent change (baseline-diff)・★phantom inbound 照会・amended_by 改竄・
# tier 改竄・cover/term/prose 改竄・core chrome 改竄 を捕捉することを回帰確認する。
# SRS/ADR/research の test-adversarial-*.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
# ★abort 系は stderr 理由を検証し「別原因の誤 abort」= false-pass を弾く (S4 の A1 否定検証 false-pass 教訓)。
# ★verify FAIL 系は理由 substring を検証し「想定 gate 以外の巻き添え FAIL」での false-pass を弾く。
# ★dty/mk9 不動点規律: chrome decoy は python landed-assert で改竄着地を強制。
#
# usage: test-adversarial-principle.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-principle.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-principle.sh"
BASE="$SCRIPT_DIR/contract/folio-constitution.principle.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-constitution.principle.prose.yaml"
# 実在 decisions dir の絶対パス (mutated contract を $TMP に置くと相対 decisions_dir が解決しないため絶対化)。
DEC_ABS="$(cd "$SCRIPT_DIR/contract/$(yq -r '.decisions_dir' "$BASE")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

# expect_abort: assemble-principle が exit!=0 で abort し stderr に想定理由 ($3) を含む。
expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
# verify が FAIL し、 出力に理由 substring ($4 任意) を含むことを要求 (巻き添え FAIL の false-pass を弾く)。
expect_vfilled_fail() { # label html [reason]
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (--filled verify が PASS した)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (FAIL したが理由が想定外。 期待 '$3')"; return; fi
  ok "$1"
}
expect_vprefill_fail() { # label contract html [reason]
  local out rc; out="$(bash "$VER" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (pre-fill verify が PASS した)"; return; fi
  if [[ -n "${4:-}" && "$out" != *"$4"* ]]; then ng "$1 (FAIL したが理由が想定外。 期待 '$4')"; return; fi
  ok "$1"
}
expect_vprefill_pass() { # label contract html
  if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi
}
expect_inject_abort() { if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi; }

# 絶対 decisions_dir を焼いた mutated contract を作る (相対 decisions_dir は $TMP から解決しないため)。
bd_base() { cp "$BASE" "$1"; REL="$DEC_ABS" yq -i '.decisions_dir = strenv(REL)' "$1"; }
# ★baseline-diff 用: golden は verify が *basename* で SCRIPT_DIR/baselines/ から解決するため、 mutated contract も
#   canonical basename (folio-constitution.principle.yaml) でなければ committed golden に当たらない (= 別名だと
#   「golden 不在」FAIL となり silent-change 検出を *検証できていない* false-pass になる)。 tag 別サブdir に canonical 名で置く。
bd_canon() { local d="$TMP/$1"; mkdir -p "$d"; local f="$d/folio-constitution.principle.yaml"; cp "$BASE" "$f"; REL="$DEC_ABS" yq -i '.decisions_dir = strenv(REL)' "$f"; printf '%s' "$f"; }

# 健全 baseline を一度生成 (HTML 改竄系の元)
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }

echo "principle-pack adversarial regression (fail-closed expected):"

# === assemble-principle validate (生成前 fail-closed) ===

# A1. ★前方照会注入 (principle に leads_to 追加) → 終端不変条件 違反で abort
cp "$BASE" "$TMP/a1.yaml"; yq -i '(.principles[] | select(.id=="P-1")).leads_to = "ADR-CLINIC-0001"' "$TMP/a1.yaml"
expect_abort "A1 ★principle へ前方照会 (leads_to) 注入を終端不変条件で abort" "$TMP/a1.yaml" "許可外キー"

# A2. ★top-level に前方照会 section (cross_doc) 追加 → abort
cp "$BASE" "$TMP/a2.yaml"; yq -i '.cross_doc = {"adr_contract":"x.yaml"}' "$TMP/a2.yaml"
expect_abort "A2 ★top-level 前方照会 section (cross_doc) を abort" "$TMP/a2.yaml" "前方照会 section"

# A3. ★phantom inbound (inbound.ref が存在しない P-99) → abort
cp "$BASE" "$TMP/a3.yaml"; yq -i '.inbound[0].ref = "P-99"' "$TMP/a3.yaml"
expect_abort "A3 ★phantom inbound (P-99 を指す) を生成前 abort" "$TMP/a3.yaml" "phantom"

# A4. inbound 未知 role → abort
cp "$BASE" "$TMP/a4.yaml"; yq -i '.inbound[0].role = "wild-role"' "$TMP/a4.yaml"
expect_abort "A4 inbound 未知 role を abort" "$TMP/a4.yaml" "未知の inbound role"

# A5. inbound 空 ref → abort
cp "$BASE" "$TMP/a5.yaml"; yq -i '.inbound[0].ref = ""' "$TMP/a5.yaml"
expect_abort "A5 ★空 inbound ref を生成前 abort" "$TMP/a5.yaml" "空 ref"

# A6. principle id 重複 → abort
cp "$BASE" "$TMP/a6.yaml"; yq -i '.principles[1].id = "P-1"' "$TMP/a6.yaml"
expect_abort "A6 principle id 重複を abort" "$TMP/a6.yaml" "id 重複"

# A7. 未知 tier → abort
cp "$BASE" "$TMP/a7.yaml"; yq -i '.principles[0].tier = "Maybe"' "$TMP/a7.yaml"
expect_abort "A7 未知の tier を abort" "$TMP/a7.yaml" "未知の tier"

# A8. ★偽 ADR (amended_by が実在しない ADR-9999) → 実在確認 abort (decisions_dir 絶対化で解決させ理由を分離)
bd_base "$TMP/a8.yaml"; yq -i '(.principles[] | select(.id=="P-1")).amended_by = [{"adr":"ADR-9999","date":"2026-01-01","approved_by":"x"}]' "$TMP/a8.yaml"
expect_abort "A8 ★amended_by の偽 ADR (実在しない) を生成前 abort" "$TMP/a8.yaml" "実在しない"

# A9. 値に改行 (@tsv 列ずれの源) → abort
cp "$BASE" "$TMP/a9.yaml"; yq -i '.principles[0].statement = "line1" + "\n" + "line2"' "$TMP/a9.yaml"
expect_abort "A9 改行を含む値を abort" "$TMP/a9.yaml" "tab/改行"

# A10. glossary 部分文字列ペア → abort
cp "$BASE" "$TMP/a10.yaml"; yq -i '.glossary += [{"term":"drif","en":"x","plain_short":"y","def":"z。"}]' "$TMP/a10.yaml"
expect_abort "A10 glossary 部分文字列ペア (drif ⊂ drift) を abort" "$TMP/a10.yaml" "部分文字列"

# === ★baseline-diff gate (silent change の機械的排除・doc_type:constitution) ===
# mutated contract から HTML を再生成 → 他 gate は通り baseline-diff のみが捕捉する (golden は committed に解決)。

# BD1. ★silent change: P-1 statement 改竄 (amended_by 無・版 bump 無) → baseline-diff FAIL
f="$(bd_canon bd1)"; yq -i '(.principles[] | select(.id=="P-1")).statement += " 黙って足された一文。"' "$f"
bash "$ASM" "$f" "$TMP/bd1.html" >/dev/null 2>&1 || ng "BD1 setup (asm 失敗)"
expect_vprefill_fail "BD1 ★silent change (statement 改竄・amended_by/版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd1.html" "silent change"

# BD2. ★tier 改竄: P-1 Always→Never (amended_by 無・版 bump 無) → baseline-diff FAIL
f="$(bd_canon bd2)"; yq -i '(.principles[] | select(.id=="P-1")).tier = "Never"' "$f"
bash "$ASM" "$f" "$TMP/bd2.html" >/dev/null 2>&1 || ng "BD2 setup (asm 失敗)"
expect_vprefill_fail "BD2 ★tier 改竄 (Always→Never・amended_by/版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd2.html" "silent change"

# BD3. ★版 bump 欠落: P-1 statement 改竄 + 新 amended_by (実在 ADR-0021) だが版据置 → baseline-diff FAIL
f="$(bd_canon bd3)"
yq -i '(.principles[] | select(.id=="P-1")).statement += " 版を上げ忘れた改訂。"' "$f"
yq -i '(.principles[] | select(.id=="P-1")).amended_by = [{"adr":"ADR-0021","date":"2026-06-20","approved_by":"x"}]' "$f"
bash "$ASM" "$f" "$TMP/bd3.html" >/dev/null 2>&1 || ng "BD3 setup (asm 失敗)"
expect_vprefill_fail "BD3 ★版 bump 欠落 (statement 改竄+新 amended_by 有・版据置) を baseline-diff が捕捉" "$f" "$TMP/bd3.html" "silent change"

# BD4. ★新規 amended_by 欠落: P-2 statement 改竄 + 版 bump 有 だが既存 ADR-0021 のみ (この変更の新規照会無) → baseline-diff FAIL
f="$(bd_canon bd4)"
yq -i '.meta.version = "0.7.0-draft"' "$f"
yq -i '(.principles[] | select(.id=="P-2")).statement += " 既存 amended_by を使い回した改訂。"' "$f"
bash "$ASM" "$f" "$TMP/bd4.html" >/dev/null 2>&1 || ng "BD4 setup (asm 失敗)"
expect_vprefill_fail "BD4 ★新規 amended_by 欠落 (版bump 有・既存 ADR 使い回し) を baseline-diff が捕捉" "$f" "$TMP/bd4.html" "silent change"

# BD5. ★principle 追加: P-15 を amended_by/版bump 無で追加 → baseline-diff FAIL
f="$(bd_canon bd5)"
yq -i '.principles += [{"id":"P-15","heading":"捏造原則","statement":"これは黙って足された原則です。","tier":"Always"}]' "$f"
bash "$ASM" "$f" "$TMP/bd5.html" >/dev/null 2>&1 || ng "BD5 setup (asm 失敗)"
expect_vprefill_fail "BD5 ★principle 追加 (amended_by/版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd5.html" "silent change"

# BD6. ★principle 削除: P-12 を版bump 無で削除 → baseline-diff FAIL
f="$(bd_canon bd6)"; yq -i 'del(.principles[] | select(.id=="P-12"))' "$f"
bash "$ASM" "$f" "$TMP/bd6.html" >/dev/null 2>&1 || ng "BD6 setup (asm 失敗)"
expect_vprefill_fail "BD6 ★principle 削除 (版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd6.html" "silent change"

# BD7. ★正当な改訂は PASS (false-positive 防止): P-9 statement 改竄 + 版 bump + 新 amended_by (実在 ADR-0021)
f="$(bd_canon bd7)"
yq -i '.meta.version = "0.7.0-draft"' "$f"
yq -i '(.principles[] | select(.id=="P-9")).statement += " 正規手続きで改訂した一文。"' "$f"
yq -i '(.principles[] | select(.id=="P-9")).amended_by = [{"adr":"ADR-0021","date":"2026-06-20","approved_by":"user"}]' "$f"
bash "$ASM" "$f" "$TMP/bd7.html" >/dev/null 2>&1 || ng "BD7 setup (asm 失敗)"
expect_vprefill_pass "BD7 ★正当な改訂 (statement 改竄+版bump+新 実在 amended_by) は baseline-diff PASS" "$f" "$TMP/bd7.html"

# === ★cell-quality errata 回帰 (confirmed findings の fail-open を封鎖したことを固定) ===

# BD8. ★critical: doc_type flip で baseline-diff/inbound gate を bypass する経路 → assemble 段で abort + verify 段で FAIL。
f="$(bd_canon bd8)"; yq -i '.meta.doc_type = "principle-doc"' "$f"
expect_abort "BD8 ★doc_type flip を assemble が abort (生成段で gate bypass 封鎖)" "$f" "doc_type"
# verify 段: doc_type を flip した contract + 健全 HTML → doc_type chk が FAIL (gate silent skip でなく hard FAIL)。
f2="$(bd_canon bd8v)"; yq -i '.meta.doc_type = "principle-doc"' "$f2"
expect_vprefill_fail "BD8v ★doc_type flip を verify が hard FAIL (gate bypass 不可)" "$f2" "$TMP/base.html" "doc_type == constitution"

# BD9. ★major: heading のみの silent change (statement/tier/版/amended_by 不変) → baseline-diff FAIL (heading も sha 被覆)。
f="$(bd_canon bd9)"; yq -i '(.principles[] | select(.id=="P-1")).heading = "黙って書き換えた見出し"' "$f"
bash "$ASM" "$f" "$TMP/bd9.html" >/dev/null 2>&1 || ng "BD9 setup (asm 失敗)"
expect_vprefill_fail "BD9 ★heading-only silent change を baseline-diff が捕捉 (heading sha 被覆)" "$f" "$TMP/bd9.html" "silent change"

# BD10. ★major: 既存 amended_by の silent 消去 (P-2 の ADR-0021 を削除・statement/tier/版 不変) → baseline-diff FAIL (adrs 列比較)。
f="$(bd_canon bd10)"; yq -i 'del(.principles[] | select(.id=="P-2") | .amended_by)' "$f"
bash "$ASM" "$f" "$TMP/bd10.html" >/dev/null 2>&1 || ng "BD10 setup (asm 失敗)"
expect_vprefill_fail "BD10 ★amended_by の silent 消去を baseline-diff が捕捉 (adrs 列比較)" "$f" "$TMP/bd10.html" "silent change"

# BD11. ★minor: version downgrade を「版 bump」と誤認しない (statement 改竄+新 amended_by 有・版 DOWN) → baseline-diff FAIL。
f="$(bd_canon bd11)"
yq -i '.meta.version = "0.5.0-draft"' "$f"
yq -i '(.principles[] | select(.id=="P-1")).statement += " downgrade 版で通そうとした改訂。"' "$f"
yq -i '(.principles[] | select(.id=="P-1")).amended_by = [{"adr":"ADR-0021","date":"2026-06-20","approved_by":"x"}]' "$f"
bash "$ASM" "$f" "$TMP/bd11.html" >/dev/null 2>&1 || ng "BD11 setup (asm 失敗)"
expect_vprefill_fail "BD11 ★version downgrade を版bump と誤認せず baseline-diff が捕捉" "$f" "$TMP/bd11.html" "silent change"

# A11. ★minor (false-positive 防止): empty amended_by:[] は「改訂来歴なし」として整合 (assemble 成功 + verify PASS・false-FAIL なし)。
f="$(bd_canon a11)"; yq -i '(.principles[] | select(.id=="P-1")).amended_by = []' "$f"
bash "$ASM" "$f" "$TMP/a11.html" >/dev/null 2>&1 || ng "A11 setup (asm 失敗・empty amended_by を誤って reject)"
expect_vprefill_pass "A11 ★empty amended_by:[] を改訂来歴なしとして整合 (false-FAIL なし)" "$f" "$TMP/a11.html"

# === ①終端強制 (HTML 改竄・生成後 fail-closed) ===
# T1. HTML に前方照会 chip を注入 → 終端 gate FAIL
cp "$TMP/base-filled.html" "$TMP/t1.html"
perl -0777 -i -pe 's#(<div class="ib-grid">)#<span data-component="cross-doc-leads-chip" data-leads-to="ADR-X" data-leads-role="claim">x</span>$1#' "$TMP/t1.html"
expect_vfilled_fail "T1 ★HTML への前方照会 chip 注入を終端 gate が捕捉" "$TMP/t1.html" "終端"

# === ③inbound (HTML 改竄) ===
# IB1. inbound ref 改竄 (P-1→P-99・phantom) → inbound dangling/SET FAIL
cp "$TMP/base-filled.html" "$TMP/ib1.html"
perl -0777 -i -pe 's#(data-inbound-ref=)"P-1"#${1}"P-99"#' "$TMP/ib1.html"
expect_vfilled_fail "IB1 ★inbound ref 改竄 (P-99 phantom) を inbound gate が捕捉" "$TMP/ib1.html" "inbound"

# IB2. inbound 可視 <b> のみ改竄 (attr 正) → ib-ref 可視 FAIL
cp "$TMP/base-filled.html" "$TMP/ib2.html"
perl -0777 -i -pe 's#(data-inbound-ref="P-1"[^>]*>.*?<b>)P-1(</b>)#${1}P-99${2}#s' "$TMP/ib2.html"
expect_vfilled_fail "IB2 ★inbound 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/ib2.html" "ib-ref 可視"

# IB3. inbound chip 重複注入 (SET 不変・count anchor) → inbound count FAIL
cp "$TMP/base-filled.html" "$TMP/ib3.html"
perl -0777 -i -pe 's#(<div data-component="principle-inbound-chip" data-inbound-ref="P-1".*?</div>)#$1$1#s' "$TMP/ib3.html"
expect_vfilled_fail "IB3 ★inbound chip 重複注入 (SET 不変) を count anchor で捕捉" "$TMP/ib3.html" "inbound"

# IB4. inbound role を allowlist 外へ改竄 → role allowlist FAIL
cp "$TMP/base-filled.html" "$TMP/ib4.html"
perl -0777 -i -pe 's#(data-inbound-ref="P-1" data-inbound-role=)"rationale"#${1}"wild"#' "$TMP/ib4.html"
expect_vfilled_fail "IB4 ★inbound role allowlist 外改竄を捕捉" "$TMP/ib4.html" "allowlist"

# IB5. inbound role を allowlist 内別 role へ改竄 → (key,role) ペア FAIL
cp "$TMP/base-filled.html" "$TMP/ib5.html"
perl -0777 -i -pe 's#(data-inbound-ref="P-1" data-inbound-role=)"rationale"#${1}"verification"#' "$TMP/ib5.html"
expect_vfilled_fail "IB5 ★inbound role allowlist 内別 role 改竄を (key,role) ペアで捕捉" "$TMP/ib5.html" "ペア"

# === fabrication-free (HTML 改竄) ===
# F1. principle-row を 1 枚削除 (先頭行を次行直前まで除去) → 行数 FAIL
cp "$TMP/base-filled.html" "$TMP/f1.html"
perl -0777 -i -pe 's#<div data-component="principle-row" class="tier-always">.*?(?=<div data-component="principle-row")##s' "$TMP/f1.html"
expect_vfilled_fail "F1 principle-row 削除を行数 gate が捕捉" "$TMP/f1.html" "principle rows"

# F2. 可視 pid 改竄 (P-1→P-99) → within-doc FAIL
cp "$TMP/base-filled.html" "$TMP/f2.html"
perl -0777 -i -pe 's#<span class="pid">P-1</span>#<span class="pid">P-99</span>#' "$TMP/f2.html"
expect_vfilled_fail "F2 ★可視 pid 改竄を within-doc で捕捉" "$TMP/f2.html" "可視 pid"

# F3. 可視 heading 改竄 → within-doc heading FAIL
cp "$TMP/base-filled.html" "$TMP/f3.html"
perl -0777 -i -pe 's#<h3 class="ph">spec は未来理想の anchor である</h3>#<h3 class="ph">詐欺の見出し</h3>#' "$TMP/f3.html"
expect_vfilled_fail "F3 ★可視 heading 改竄を within-doc で捕捉" "$TMP/f3.html" "heading"

# F4. tier badge ラベル改竄 → tier badge FAIL
cp "$TMP/base-filled.html" "$TMP/f4.html"
perl -0777 -i -pe 's#(<span data-component="principle-tier-badge" class="tier-always">)いつも守る \(例外なし\)#${1}詐欺ラベル#' "$TMP/f4.html"
expect_vfilled_fail "F4 ★tier badge ラベル改竄を tier fidelity で捕捉" "$TMP/f4.html" "tier badge"

# F5. tier badge class 改竄 → tier badge class FAIL
cp "$TMP/base-filled.html" "$TMP/f5.html"
perl -0777 -i -pe 's#<span data-component="principle-tier-badge" class="tier-always">いつも守る#<span data-component="principle-tier-badge" class="tier-never">いつも守る#' "$TMP/f5.html"
expect_vfilled_fail "F5 ★tier badge class 改竄を tier class fidelity で捕捉" "$TMP/f5.html" "tier badge: class"

# F6. row class 改竄 → row class FAIL
cp "$TMP/base-filled.html" "$TMP/f6.html"
perl -0777 -i -pe 's#<div data-component="principle-row" class="tier-always">#<div data-component="principle-row" class="tier-never">#' "$TMP/f6.html"
expect_vfilled_fail "F6 ★row class 改竄を row class fidelity で捕捉" "$TMP/f6.html" "row: class"

# F7. statement 可視テキスト改竄 (badge-strip vis) → statement fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/f7.html"
perl -0777 -i -pe 's#到達すべき設計の最終形#捏造された目標#' "$TMP/f7.html"
expect_vfilled_fail "F7 ★statement 可視テキスト改竄を badge-strip 突合で捕捉" "$TMP/f7.html" "statement"

# F8. amended-adr 属性改竄 → amendment set/count FAIL
cp "$TMP/base-filled.html" "$TMP/f8.html"
perl -0777 -i -pe 's#data-amended-adr="ADR-0038"#data-amended-adr="ADR-FORGED"#' "$TMP/f8.html"
expect_vfilled_fail "F8 ★amended-adr 属性改竄を amendment 集合で捕捉" "$TMP/f8.html" "amendment"

# F9. amended 可視 <b> のみ改竄 (attr 正) → am-row 可視 FAIL
cp "$TMP/base-filled.html" "$TMP/f9.html"
perl -0777 -i -pe 's#(data-amended-adr="ADR-0038"><b>)ADR-0038(</b>)#${1}ADR-FORGED${2}#' "$TMP/f9.html"
expect_vfilled_fail "F9 ★amended 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "am-row 可視"

# F10. cover-meta 原則数捏造 → cover-meta FAIL
cp "$TMP/base-filled.html" "$TMP/f10.html"
perl -0777 -i -pe 's#(<span class="k">原則の総数</span><span class="v">)14 件#${1}99 件#' "$TMP/f10.html"
expect_vfilled_fail "F10 ★cover-meta 原則数捏造を再導出で捕捉" "$TMP/f10.html" "cover-meta 原則の総数"

# F11. cover-meta tier 内訳捏造 → cover-meta tier FAIL
cp "$TMP/base-filled.html" "$TMP/f11.html"
perl -0777 -i -pe 's#(tier 内訳</span><span class="v">)Always 9#${1}Always 99#' "$TMP/f11.html"
expect_vfilled_fail "F11 ★cover-meta tier 内訳捏造を再導出で捕捉" "$TMP/f11.html" "cover-meta tier"

# F12. prose スロットの内容改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/f12.html"
perl -0777 -i -pe 's#(data-slot-id="cover-summary">)[^<]*#${1}改竄された散文#' "$TMP/f12.html"
expect_vfilled_fail "F12 prose 改竄 (注入忠実) を verify が捕捉" "$TMP/f12.html" "注入"

# F13. term-inline の併記を誤った plain_short へ改竄 → fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/f13.html"
perl -0777 -i -pe 's#(data-term="drift">)[^<]*#${1}でたらめ#' "$TMP/f13.html"
expect_vfilled_fail "F13 term-inline 併記改竄を fidelity が捕捉" "$TMP/f13.html" "term-inline"

# F14. versioning bump 列改竄 → versioning fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/f14.html"
perl -0777 -i -pe 's#<td class="vp-bump">MAJOR</td>#<td class="vp-bump">TINY</td>#' "$TMP/f14.html"
expect_vfilled_fail "F14 ★versioning bump 改竄を fidelity で捕捉" "$TMP/f14.html" "versioning: bump"

# F15. amendment step 改竄 → amendment steps fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/f15.html"
perl -0777 -i -pe 's#(<li>)user 承認を取得 \(P-10\)#${1}承認は不要#' "$TMP/f15.html"
expect_vfilled_fail "F15 ★amendment step 改竄を fidelity で捕捉" "$TMP/f15.html" "amendment: steps"

# F-bur-{a..c} ★folio-bur: inbound 照会元/role + amendment 来歴の可視テキスト捏造 (属性/件数 intact のまま可視のみ改竄)
cp "$TMP/base-filled.html" "$TMP/fbura.html"
perl -0777 -i -pe 's#(<span class="ib-from">)[^<]+#${1}FORGED-SOURCE#g' "$TMP/fbura.html"
expect_vfilled_fail "F-bur-a ★ib-from (照会元・属性なし) 可視捏造を可視==.inbound[].from で捕捉" "$TMP/fbura.html" "ib-from"
cp "$TMP/base-filled.html" "$TMP/fburb.html"
perl -0777 -i -pe 's#(<span class="ib-role">)[^<]+#${1}FORGED-ROLE#g' "$TMP/fburb.html"
expect_vfilled_fail "F-bur-b ★ib-role 可視捏造を可視==.inbound[].role で捕捉" "$TMP/fburb.html" "ib-role"
cp "$TMP/base-filled.html" "$TMP/fburc.html"
perl -0777 -i -pe 's#(<span class="am-meta">)[^<]+#${1}(9999-99-99 FORGED)#g' "$TMP/fburc.html"
expect_vfilled_fail "F-bur-c ★am-meta (改訂日付·承認者) 可視捏造を可視==(date·approved_by) で捕捉" "$TMP/fburc.html" "am-meta"
# F-bur-r2 ★folio-bur round-2 (ceiling-recursion): comment-hidden decoy (single-quote forged 可視 + double-quote 正値をコメント退避)
#   を quote-robust 占有数パリティで捕捉 (count_attr_token はコメント内 genuine + 可視 forged を両方数え +1 → FAIL)。
cp "$TMP/base-filled.html" "$TMP/fburr2.html"
perl -0777 -i -pe "s{<span class=\"ib-from\">ADR-0021</span>}{<span class='ib-from'>FORGED元</span><!--<span class=\"ib-from\">ADR-0021</span>-->}" "$TMP/fburr2.html"
expect_vfilled_fail "F-bur-r2 ★ib-from comment-hidden decoy を ib-from 占有数パリティで捕捉" "$TMP/fburr2.html" "占有: ib-from"
# F-bur-r3-{a..c} ★folio-bur round-3 (ceiling-recursion R2 是正): comment-hidden の *classless* 変種。
#   forgery が marker class を一切持たず (occupancy +1 しない) genuine を `<!--...-->` へ退避する手口は round-2 占有数パリティを
#   素通る (decoy が class 無ゆえ count されず、可視 grep は comment 内 genuine を読む)。BODY_NC (comment 除去 body) で
#   再導出すると comment 内 genuine が消え、可視 act 欠落 + 占有数 -1 の両方で FAIL に倒れる。
cp "$TMP/base-filled.html" "$TMP/fburr3a.html"
perl -0777 -i -pe 's{<span class="ib-from">([^<]*)</span>}{<span style="font-weight:700">CLASSLESS偽元</span><!--<span class="ib-from">$1</span>-->} if !$d++' "$TMP/fburr3a.html"
expect_vfilled_fail "F-bur-r3-a ★ib-from classless comment-hidden を BODY_NC 再導出で捕捉" "$TMP/fburr3a.html" "ib-from"
cp "$TMP/base-filled.html" "$TMP/fburr3b.html"
perl -0777 -i -pe 's{<span class="ib-role">([^<]*)</span>}{<span style="color:var(--violet)">implementation偽</span><!--<span class="ib-role">$1</span>-->} if !$d++' "$TMP/fburr3b.html"
expect_vfilled_fail "F-bur-r3-b ★ib-role classless comment-hidden を BODY_NC 再導出で捕捉" "$TMP/fburr3b.html" "ib-role"
cp "$TMP/base-filled.html" "$TMP/fburr3c.html"
perl -0777 -i -pe 's{<span class="am-meta">([^<]*)</span>}{<span style="font-weight:600;color:var(--ink-faint)">(9999-99-99 · FORGED捏造)</span><!--<span class="am-meta">$1</span>-->} if !$d++' "$TMP/fburr3c.html"
expect_vfilled_fail "F-bur-r3-c ★am-meta classless comment-hidden を BODY_NC 再導出で捕捉" "$TMP/fburr3c.html" "am-meta"

# F16. ★HTML 注入の escape 健全性 (生 markup が構造へ漏れない・false-positive 防止)。 abs decisions_dir で asm を通す。
bd_base "$TMP/f16.yaml"; yq -i '(.principles[] | select(.id=="P-1")).statement = "<script>alert(1)</script>危険"' "$TMP/f16.yaml"
bash "$ASM" "$TMP/f16.yaml" "$TMP/f16.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/f16.html"; then ng "F16 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/f16.html"; then ok "F16 HTML 注入を正規 entity に escape"
else ng "F16 正規 entity &lt;script&gt; が出ていない"; fi

# === core 共通 chrome (cover-head/approval/glossary) の floor 突合 (verify_core_chrome・folio-mk9) ===
# (a) 値改竄 = python landed-assert で着地を強制 / (b) decoy 注入 = 占有数パリティ。
chrome_tamper_fail() { # label needle replacement
  if python3 -c "
d=open('$TMP/base-filled.html').read()
o='''$2'''; assert o in d, 'needle not found'
open('$TMP/chrome.html','w').write(d.replace(o,'''$3''',1))
" 2>/dev/null; then expect_vfilled_fail "$1" "$TMP/chrome.html" "core-chrome"; else ng "$1 setup 失敗"; fi
}
chrome_decoy_fail() { # label decoy_html (</h1> 直後へ注入)
  if python3 -c "
d=open('$TMP/base-filled.html').read()
o='</h1>'; assert o in d, 'anchor not found'
open('$TMP/chromed.html','w').write(d.replace(o,o+'''$2''',1))
" 2>/dev/null; then expect_vfilled_fail "$1" "$TMP/chromed.html" "core-chrome"; else ng "$1 setup 失敗"; fi
}
chrome_tamper_fail "C1 ★cover eyebrow_left 改竄を core-chrome で捕捉" '<span class="doc-type">不変原則 (Constitution)</span>' '<span class="doc-type">詐欺ラベル</span>'
chrome_tamper_fail "C2 ★cover title (h1) 改竄を core-chrome で捕捉" '<h1>folio constitution — 14 の不変原則</h1>' '<h1>詐欺タイトル</h1>'
chrome_tamper_fail "C3 ★approval who 改竄を core-chrome で捕捉" '<span class="who">user (shuu5)</span>' '<span class="who">詐欺 太郎</span>'
chrome_tamper_fail "C4 ★glossary def 改竄を core-chrome で捕捉" '<div class="gdef">どこからもリンクされていない文書。 たどり着けないため folio では 0 を強制する。</div>' '<div class="gdef">詐欺定義</div>'
chrome_decoy_fail "C5 ★doc-type 大文字化 decoy を占有数で捕捉" '<span class="DOC-TYPE">詐欺の文書種</span>'
chrome_decoy_fail "C6 ★想定読者 *無し* の偽 reader-chip decoy を anchor 占有数で捕捉" '<div class="reader-chip"> 詐欺の追加チップ</div>'

# === inject fail-closed ===
# J1. manifest から 1 スロット削除 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/j1.prose.yaml"; yq -i 'del(.slots.["cover-summary"])' "$TMP/j1.prose.yaml"
expect_inject_abort "J1 manifest 欠落スロットを inject が abort" "$TMP/j1.prose.yaml" "$TMP/base.html"

# J2. manifest に orphan キー追加 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/j2.prose.yaml"; yq -i '.slots.["ghost-slot"] = "幽霊"' "$TMP/j2.prose.yaml"
expect_inject_abort "J2 manifest orphan キーを inject が abort" "$TMP/j2.prose.yaml" "$TMP/base.html"

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_vprefill_pass "P1 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"


# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
cp "$TMP/base-filled.html" "$TMP/r7p1.html"; perl -0777 -i -pe 's{</body>}{<p class="prin-evil-novel">偽の原則(novel class 捏造)</p></body>}' "$TMP/r7p1.html"
expect_vfilled_fail "R7-prin-a ★novel class を class enumeration で捕捉" "$TMP/r7p1.html"
cp "$TMP/base-filled.html" "$TMP/r7p2.html"; perl -0777 -i -pe 's{</body>}{<div data-component="adr-option-card">foreign dc(捏造)</div></body>}' "$TMP/r7p2.html"
expect_vfilled_fail "R7-prin-b ★foreign dc を dc enumeration で捕捉" "$TMP/r7p2.html"
cp "$TMP/base-filled.html" "$TMP/r7p3.html"; perl -0777 -i -pe 's{</body>}{<span class="tier-always">偽の tier バッジ(捏造)</span></body>}' "$TMP/r7p3.html"
expect_vfilled_fail "R7-prin-c ★tier-always additive を占有で捕捉 (不変段階の偽帰属)" "$TMP/r7p3.html"
cp "$TMP/base-filled.html" "$TMP/r7p4.html"; perl -0777 -i -pe 's{</body>}{<div class="lab">偽(捏造)</div></body>}' "$TMP/r7p4.html"
expect_vfilled_fail "R7-prin-d ★lab additive を占有==1 で捕捉" "$TMP/r7p4.html"
cp "$TMP/base-filled.html" "$TMP/r7p5.html"; perl -0777 -i -pe 's{</body>}{<p style="display:none">隠蔽(捏造)</p></body>}' "$TMP/r7p5.html"
expect_vfilled_fail "R7-prin-e ★display:none 隠蔽を display-state guard で捕捉" "$TMP/r7p5.html"

echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
