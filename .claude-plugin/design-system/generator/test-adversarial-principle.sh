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
# repro-build arm (verify_repro_build・folio-3d23) は verify-*.sh 既定 ON。 bulk case は honest skip で 10 分/suite を維持し
# (arm 未 skip は assemble 再 build で timeout)、 conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
export SKIP_REPRO="${SKIP_REPRO:-1}"
# gate F (playwright visual・folio-vuf A) も floor-adversarial では skip (重い render を外す・SKIP_REPRO と同型)。
export SKIP_RENDER="${SKIP_RENDER:-1}"
source "$SCRIPT_DIR/lib/test-repro-pins.sh"
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
# ★帰属を行頭 [FAIL] へ anchor する厳密版 (folio-lffq)。 expect_vprefill_fail の reason 照合は出力 *全体* の
#   substring ゆえ、 chk が同一 label を [OK] 行にも印字する arm では 「別 arm が落ちた + 本命 arm は [OK]」でも
#   PASS してしまう (vacuous 帰属)。 本 helper は reason を含む行が ^ *[FAIL] であることまで要求する。
expect_vprefill_fail_at() { # label contract html reason(必須)
  local out rc; out="$(bash "$VER" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (pre-fill verify が PASS した)"; return; fi
  if grep -F -- "$4" <<<"$out" | grep -qE '^ *\[FAIL\]'; then ok "$1"
  else
    ng "$1 (FAIL は別 arm の巻き添え = 期待 arm '$4' の [FAIL] 行が無い)"
    # ★診断可能性: 「rc!=0 だが期待 arm が [FAIL] していない」は (a) arm 退行 と (b) tool error / 資源枯渇による
    #   別要因 FAIL を区別できないと再現待ちになる。 実 FAIL 行と TOOLERR 行をその場で残す (一度きりの
    #   環境起因 FAIL を「arm 退行」と誤診しないための証跡)。
    printf '%s\n' "$out" | grep -E '^ *\[(FAIL|TOOLERR)\]' | head -5 | sed 's/^/         /'
  fi
}
expect_vprefill_pass() { # label contract html
  if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi
}
# ★errata-3 M9/M11: --filled / --artifact でも *行頭 [FAIL] anchor* の帰属を要求する厳密版 (expect_vprefill_fail_at と同型)。
#   ★なぜ mode 別に要るか: 本 pack の arm は「$HTML 直読ゆえ mode 非依存」なものと「$BODY / manifest 依存ゆえ
#     --filled でしか走らない」ものが混在する (§11 の manifest 突合は --filled 限定・--artifact 分岐は走らせない)。
#     mode 非依存性は *主張* でなく mode ごとの実弾で pin しなければ、 将来 arm が $BODY 依存へ退行しても
#     pre-fill の MK だけが緑のまま残り気付けない (round-3 M11 が指摘した durable pin の欠落)。
expect_vfilled_fail_at() { # label html reason(必須)
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (--filled verify が PASS した)"; return; fi
  if grep -F -- "$3" <<<"$out" | grep -qE '^ *\[FAIL\]'; then ok "$1"
  else
    ng "$1 (FAIL は別 arm の巻き添え = 期待 arm '$3' の [FAIL] 行が無い)"
    printf '%s\n' "$out" | grep -E '^ *\[(FAIL|TOOLERR)\]' | head -5 | sed 's/^/         /'
  fi
}
expect_vartifact_fail_at() { # label html reason(必須)
  local out rc; out="$(bash "$VER" --artifact "$BASE" "$2" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (--artifact verify が PASS した)"; return; fi
  if grep -F -- "$3" <<<"$out" | grep -qE '^ *\[FAIL\]'; then ok "$1"
  else
    ng "$1 (FAIL は別 arm の巻き添え = 期待 arm '$3' の [FAIL] 行が無い)"
    printf '%s\n' "$out" | grep -E '^ *\[(FAIL|TOOLERR)\]' | head -5 | sed 's/^/         /'
  fi
}
expect_vartifact_pass() { # label html — ★陽性対照 (検体が正しいことの固定)
  if bash "$VER" --artifact "$BASE" "$2" >/dev/null 2>&1; then ok "$1"; else ng "$1 (--artifact verify FAIL = 検体不正)"; fi
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

# === ★chapters band 見出し (folio-c5r.2: instance hardcode 封鎖 + 数詞 fabrication) ===

# CH1. chapters.always 欠落 → abort (band 見出しは contract 必須・neutral default を置かない)
cp "$BASE" "$TMP/ch1.yaml"; yq -i 'del(.chapters.always)' "$TMP/ch1.yaml"
expect_abort "CH1 ★chapters.always 欠落を abort (band 見出しは contract 必須)" "$TMP/ch1.yaml" "chapters.always 欠落"

# CH2. chapters 数詞改竄 (9→8・実件数 9 のまま) → 生成前 abort (件数 fabrication)
cp "$BASE" "$TMP/ch2.yaml"; yq -i '.chapters.always = "例外なく常に守る 8 原則 — folio の土台"' "$TMP/ch2.yaml"
expect_abort "CH2 ★chapters.always 数詞 8≠Always 実件数 9 を生成前 abort (件数 fabrication)" "$TMP/ch2.yaml" "不一致"

# CH3. HTML band h2 改竄 (contract は正) → verify FAIL (band h2 fidelity)
sed 's#例外なく常に守る 9 原則 — folio の土台#例外なく常に守る 9 原則 — folio の礎#' "$TMP/base.html" > "$TMP/ch3.html"
expect_vprefill_fail "CH3 ★HTML band h2 改竄を verify が捕捉 (band h2 fidelity)" "$BASE" "$TMP/ch3.html" "band h2"

# CH4. ★verify 独立数詞 pin: contract 数詞と HTML h2 の両方を 8 に辻褄合わせ → h2 fidelity は一致するが
#      verify 自身の数詞照合 (contract 数詞 == 派生実件数) が assembler へ defer せず独立に捕捉することを pin。
f="$(bd_canon ch4)"; yq -i '.chapters.always = "例外なく常に守る 8 原則 — folio の土台"' "$f"
sed 's#例外なく常に守る 9 原則 — folio の土台#例外なく常に守る 8 原則 — folio の土台#' "$TMP/base.html" > "$TMP/ch4.html"
expect_vprefill_fail "CH4 ★contract+HTML 両側の数詞辻褄合わせを verify 数詞照合が捕捉" "$f" "$TMP/ch4.html" "数詞"

# CH5. ★全角数字回避 (「８ 原則」は ASCII 数詞照合を素通り) → 生成前 abort (表記封鎖)
cp "$BASE" "$TMP/ch5.yaml"; yq -i '.chapters.always = "例外なく常に守る ８ 原則 — folio の土台"' "$TMP/ch5.yaml"
expect_abort "CH5 ★chapters の全角数字 (数詞照合回避) を生成前 abort" "$TMP/ch5.yaml" "全角数字"

# CH6. ★漢数字回避 (「九 原則」は ASCII 数詞照合に掛からない) → ASCII 数詞必須の肯定形が生成前 abort
#      (実件数 9 と意味は一致していても、 照合不能な表記自体を却下 = 回避表記の列挙をしない封鎖)。
#      ★bd_base で decisions_dir を絶対化し、 abort 理由を意図した check に分離 (A8 と同じ理由分離・round2 nit)。
bd_base "$TMP/ch6.yaml"; yq -i '.chapters.always = "例外なく常に守る 九 原則 — folio の土台"' "$TMP/ch6.yaml"
expect_abort "CH6 ★chapters の漢数字数詞 (ASCII 照合回避) を数詞必須で生成前 abort" "$TMP/ch6.yaml" "ASCII 数字の件数"

# CH7. ★amendment「N ステップ」数詞改竄 (4≠steps 実件数 5) → 生成前 abort (原則側 CH2 の amendment 対称 pin)
bd_base "$TMP/ch7.yaml"; yq -i '.chapters.amendment = "変更を ADR と版に必ず残す 4 ステップ"' "$TMP/ch7.yaml"
expect_abort "CH7 ★chapters.amendment 数詞 4≠steps 実件数 5 を生成前 abort" "$TMP/ch7.yaml" "不一致"

# CH8. ★amendment verify 独立数詞 pin (CH4 の amendment 対称): contract+HTML 両側を 4 ステップに辻褄合わせ
#      → h2 fidelity は一致するが verify のステップ数詞照合が独立に捕捉
f="$(bd_canon ch8)"; yq -i '.chapters.amendment = "変更を ADR と版に必ず残す 4 ステップ"' "$f"
sed 's#変更を ADR と版に必ず残す 5 ステップ#変更を ADR と版に必ず残す 4 ステップ#' "$TMP/base.html" > "$TMP/ch8.html"
expect_vprefill_fail "CH8 ★amendment 両側数詞辻褄合わせを verify ステップ数詞照合が捕捉" "$f" "$TMP/ch8.html" "expected 5, got 4"

# CH9. ★漢数字回避の verify 側 pin: contract+HTML 両側を「九 原則」に辻褄合わせ → verify の ASCII 数詞必須が捕捉
f="$(bd_canon ch9)"; yq -i '.chapters.always = "例外なく常に守る 九 原則 — folio の土台"' "$f"
sed 's#例外なく常に守る 9 原則 — folio の土台#例外なく常に守る 九 原則 — folio の土台#' "$TMP/base.html" > "$TMP/ch9.html"
expect_vprefill_fail "CH9 ★漢数字数詞の両側辻褄合わせを verify の ASCII 数詞必須が捕捉" "$f" "$TMP/ch9.html" "ASCII 数詞なし"

# === ★baseline-diff gate (silent change の機械的排除・doc_type:constitution) ===
# mutated contract から HTML を再生成 → 他 gate は通り baseline-diff のみが捕捉する (golden は committed に解決)。

# BD1. ★silent change: P-1 statement 改竄 (amended_by 無・版 bump 無) → baseline-diff FAIL
f="$(bd_canon bd1)"; yq -i '(.principles[] | select(.id=="P-1")).statement += " 黙って足された一文。"' "$f"
bash "$ASM" "$f" "$TMP/bd1.html" >/dev/null 2>&1 || ng "BD1 setup (asm 失敗)"
expect_vprefill_fail "BD1 ★silent change (statement 改竄・amended_by/版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd1.html" "silent change"

# BD2. ★tier 改竄: P-1 Always→Never (amended_by 無・版 bump 無) → baseline-diff FAIL
#      ★攻撃者は band 見出しの数詞も辻褄合わせる (生成段の数詞整合を通過させ、 baseline-diff の単独検出力を検証)。
f="$(bd_canon bd2)"; yq -i '(.principles[] | select(.id=="P-1")).tier = "Never"' "$f"
yq -i '.chapters.always = "例外なく常に守る 8 原則 — folio の土台" | .chapters.never = "踏み越え禁止の 3 原則 — 守りの最後の線"' "$f"
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

# BD5. ★principle 追加: P-15 を amended_by/版bump 無で追加 → baseline-diff FAIL (数詞は辻褄合わせ・BD2 同様)
f="$(bd_canon bd5)"
yq -i '.principles += [{"id":"P-15","anchor":"p-15","heading":"捏造原則","statement":"これは黙って足された原則です。","tier":"Always"}]' "$f"
yq -i '.chapters.always = "例外なく常に守る 10 原則 — folio の土台"' "$f"
bash "$ASM" "$f" "$TMP/bd5.html" >/dev/null 2>&1 || ng "BD5 setup (asm 失敗)"
expect_vprefill_fail "BD5 ★principle 追加 (amended_by/版bump 無) を baseline-diff が捕捉" "$f" "$TMP/bd5.html" "silent change"

# BD6. ★principle 削除: P-12 を版bump 無で削除 → baseline-diff FAIL (数詞は辻褄合わせ・BD2 同様)
f="$(bd_canon bd6)"; yq -i 'del(.principles[] | select(.id=="P-12"))' "$f"
yq -i '.chapters.never = "踏み越え禁止の 1 原則 — 守りの最後の線"' "$f"
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
#     ★folio-lffq: h3.ph は id="p-N" を担い中身が <strong>P-N: heading</strong> になった (裁定 3 = 案 A)。
#     opener literal を新形へ更新 (更新しないと perl が no-op 化し「改竄されていない HTML を verify が PASS した」
#     という false-pass に転ぶ = 本 case の検出力が silent に 0 になる)。
cp "$TMP/base-filled.html" "$TMP/f3.html"
perl -0777 -i -pe 's#<h3 class="ph" id="p-1"><strong>P-1: spec は未来理想の anchor である</strong></h3>#<h3 class="ph" id="p-1"><strong>P-1: 詐欺の見出し</strong></h3>#' "$TMP/f3.html"
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

# ===== ★folio-lffq: emit 3 点 (head JSON-LD / head meta / navigable p-N anchor) の per-shape MK =====
# ★本群を置く理由: 改修前の verify-principle.sh には head / meta / JSON-LD の assert が 0 件で、 emit を足しても
#   「実装しただけ・1 本も検査されていない」状態だった。 各 arm を 1 本ずつ実弾で撃ち、 arm を外すと当該 [FAIL] が
#   消える (= mutation-kill) ことで検出力を固定する。 ★expect_abort / expect_vprefill_fail / expect_vfilled_fail の
#   いずれかで必ず assert する (:361-362 / :419-423 の 6 本のような「mutant を作るだけで assert を呼ばない」dead
#   code の形は模倣しない — あれらは実走 passed に 1 件も計上されていない)。

# --- (1) head_graph / meta 契約の生成前 fail-closed (assemble 段) ---
# HG1. head_graph 欠落 → abort (欠落すると JSON-LD が 1 byte も出ず、 scan 除外も self-root 検出も成立しない。
#      switchover-harness.sh:159-172 の in-scan hard-fail は contract の head_graph を yq で独立に読むため
#      「emit 結果に defer せず」ここで落とすのが正しい層)。
bd_base "$TMP/hg1.yaml"; yq -i 'del(.head_graph)' "$TMP/hg1.yaml"
expect_abort "HG1 ★head_graph 欠落を生成前 abort (spec graph head 参加は constitution 必須)" "$TMP/hg1.yaml" "head_graph 欠落"

# HG2. ★critical: head_graph.type flip (FolioConstitution → schema:TechArticle) → abort。
#      flip すると生成物が bin/folio の 5 site で一斉に意味反転する (inventory/is_scan_target/fix/validate の
#      除外 4 site が包含へ・nav_is_self_root の正の検出が false へ)。 doc_type flip (BD8) の @type 対称。
bd_base "$TMP/hg2.yaml"; yq -i '.head_graph.type = "schema:TechArticle"' "$TMP/hg2.yaml"
expect_abort "HG2 ★head_graph.type flip (@type で scan 除外/self-root が反転) を生成前 abort" "$TMP/hg2.yaml" "FolioConstitution 必須"

# HG3. ★終端不変条件の head 面: head_graph に前方関係 (references) → abort (principle は照会終端ゆえ
#      reverse 材化も検証もされない捏造 edge になる)。 principle-level の許可外キー (A1) の head 対称。
bd_base "$TMP/hg3.yaml"; yq -i '.head_graph.references = ["./rules.html"]' "$TMP/hg3.yaml"
expect_abort "HG3 ★head_graph への前方関係 (references) を終端不変条件で abort" "$TMP/hg3.yaml" "前方関係"

# HG4. ★fail-open 封鎖: meta.stakeholders を scalar 化 → abort。 素で join すると 1 要素扱いで通り、 CORE 側
#      JSON-LD folio:stakeholders が array→string へ型退行する (jsonld-lint / inventory / fedges のいずれも捕捉しない)。
bd_base "$TMP/hg4.yaml"; yq -i '.meta.stakeholders = "Developer, AI Agent, External Reviewer"' "$TMP/hg4.yaml"
expect_abort "HG4 ★meta.stakeholders の scalar 化 (JSON-LD array→string 型退行) を生成前 abort" "$TMP/hg4.yaml" "array 必須"

# AN1. anchor 欠落 → abort (空 anchor = navigable id 無し。 gate (i) は essence 空を無言 skip / gate (h) は
#      anchor 存在しか見ない / prime golden は essence を持たない = 全経路が沈黙するため生成段で落とす)。
bd_base "$TMP/an1.yaml"; yq -i 'del(.principles[0].anchor)' "$TMP/an1.yaml"
expect_abort "AN1 ★anchor 欠落を生成前 abort (navigable id 無しは全経路が沈黙する)" "$TMP/an1.yaml" "anchor が空"

# AN2. anchor の大小文字 drift (p-1 → P-1) → abort。 bin/folio:2308 / folio_xref_essence は小文字 id を
#      前提に解決するため、 大文字 anchor は「gate は通るのに inbound #p-1 が解決しない」無言の死になる。
bd_base "$TMP/an2.yaml"; yq -i '.principles[0].anchor = "P-1"' "$TMP/an2.yaml"
expect_abort "AN2 ★anchor 大小文字 drift (id 小文字化と不一致) を生成前 abort" "$TMP/an2.yaml" "小文字化と不一致"

# AN3. anchor 重複 (P-2 の anchor を p-1 に) → abort。 id は一意でも anchor 手書き重複で同一 id 属性が
#      2 個出れば HTML の id 一意性が壊れ、 #p-1 の解決先が非決定になる。
bd_base "$TMP/an3.yaml"; yq -i '.principles[1].anchor = "p-1"' "$TMP/an3.yaml"
expect_abort "AN3 ★anchor 重複を生成前 abort (同一 id 属性 2 個 = #p-1 の解決先が非決定)" "$TMP/an3.yaml" "anchor 重複"

# --- (2) head meta 5 本 (HTML 改竄・verify 段) ---
# HM1. pack-local meta の値改竄 → head meta 値突合 FAIL。
cp "$TMP/base.html" "$TMP/hm1.html"
perl -0777 -i -pe 's#<meta name="folio-layer" content="core">#<meta name="folio-layer" content="project">#' "$TMP/hm1.html"
expect_vprefill_fail_at "HM1 ★head meta folio-layer 値改竄を contract 突合で捕捉" "$BASE" "$TMP/hm1.html" "head meta folio-layer"

# HM2. CORE meta の値改竄 → head meta 値突合 FAIL (CORE 3 本側の per-shape MK)。
cp "$TMP/base.html" "$TMP/hm2.html"
perl -0777 -i -pe 's#<meta name="folio-doc-type" content="constitution">#<meta name="folio-doc-type" content="principle">#' "$TMP/hm2.html"
expect_vprefill_fail_at "HM2 ★head meta folio-doc-type 値改竄を contract 突合で捕捉" "$BASE" "$TMP/hm2.html" "head meta folio-doc-type"

# HM3. ★喪失 (emit 呼出 1 行落ち相当): folio-stakeholders meta を削除 → 総数 pin (5) が捕捉。
#      per-meta chk も同時に落ちるが、 総数 pin が「知らない本数の増減」を挟む第 2 層であることを固定する。
cp "$TMP/base.html" "$TMP/hm3.html"
perl -0777 -i -pe 's#<meta name="folio-stakeholders" content="[^"]*">\n##' "$TMP/hm3.html"
expect_vprefill_fail_at "HM3 ★head meta 喪失 (stakeholders 削除) を総数 pin が捕捉" "$BASE" "$TMP/hm3.html" "folio-* head meta 総数"

# HM4. ★捏造 (canonical に無い meta の混入): folio-xref-completeness を注入 → 空側 chk が捕捉。
#      この meta は opt-in signal ゆえ捏造されると xref completeness gate が偽って起動する (canonical 非該当)。
cp "$TMP/base.html" "$TMP/hm4.html"
perl -0777 -i -pe 's#(<meta name="folio-layer")#<meta name="folio-xref-completeness" content="enabled">\n$1#' "$TMP/hm4.html"
expect_vprefill_fail_at "HM4 ★canonical に無い head meta の捏造混入を空側 chk が捕捉" "$BASE" "$TMP/hm4.html" "folio-xref-completeness 不在"

# --- (3) head JSON-LD (HTML 改竄・verify 段) ---
# JL1. ★@type flip → bin/folio の 5 site が一斉反転する改竄を @type chk が捕捉。
cp "$TMP/base.html" "$TMP/jl1.html"
# ★perl の s### 内では @ が配列補間される (裸の "@type" は "" に潰れ pattern が no-op 化 = 改竄していない
#   HTML を verify に渡して「PASS した」と報告する false-pass になる)。 JSON-LD を触る mutant は必ず \@ で書く。
perl -0777 -i -pe 's#"\@type": "FolioConstitution"#"\@type": "schema:TechArticle"#' "$TMP/jl1.html"
expect_vprefill_fail_at "JL1 ★JSON-LD @type flip (scan 除外/self-root 反転) を捕捉" "$BASE" "$TMP/jl1.html" "@type == FolioConstitution"

# JL2. ★block 丸ごと削除 → 「block 不在」で FAIL (skip でなく FAIL に倒すことの pin)。
#      bin/folio の除外 4 site は JSON-LD 不在でも @type 不一致と *同じ枝* に落ちるため、 「inventory/validate に
#      出ない」を単独 DoD にすると本 mutant を GREEN で通してしまう。 block の実在を直接 pin する arm が唯一の砦。
cp "$TMP/base.html" "$TMP/jl2.html"
perl -0777 -i -pe 's#<script type="application/ld\+json">.*?</script>\n##s' "$TMP/jl2.html"
expect_vprefill_fail_at "JL2 ★JSON-LD block 削除を「不在=FAIL」で捕捉 (silent skip 禁止)" "$BASE" "$TMP/jl2.html" "block 不在"

# JL3. ★parse 不能化 → 「jq parse 不能」で FAIL (parse error を clean と詐称しない)。
cp "$TMP/base.html" "$TMP/jl3.html"
perl -0777 -i -pe 's#"\@id": "\./constitution\.html",#"\@id": ./constitution.html,#' "$TMP/jl3.html"
expect_vprefill_fail_at "JL3 ★JSON-LD parse 不能化を FAIL で捕捉 (測定不能を clean と詐称しない)" "$BASE" "$TMP/jl3.html" "parse 不能"

# JL4. ★前方関係の注入 (dc:references) → 終端不変条件の head 面 chk が捕捉 (HG3 の生成後対称)。
cp "$TMP/base.html" "$TMP/jl4.html"
perl -0777 -i -pe 's#("\@type": "FolioConstitution",)#$1\n  "dc:references": [ { "\@id": "./rules.html" } ],#' "$TMP/jl4.html"
expect_vprefill_fail_at "JL4 ★JSON-LD への前方関係注入 (捏造 edge) を終端 chk が捕捉" "$BASE" "$TMP/jl4.html" "前方関係キー 0 本"

# JL5. ★folio:stakeholders の型退行 (array→string) を生成物側でも捕捉 (HG4 の生成後対称)。
cp "$TMP/base.html" "$TMP/jl5.html"
perl -0777 -i -pe 's#"folio:stakeholders": \[.*?\]#"folio:stakeholders": "Developer, AI Agent, External Reviewer"#s' "$TMP/jl5.html"
expect_vprefill_fail_at "JL5 ★JSON-LD folio:stakeholders の array→string 型退行を捕捉" "$BASE" "$TMP/jl5.html" "stakeholders は array"

# JL6. ★2 本目の ld+json 注入 (dead emit) → block 数 == 1 arm が単独で捕捉。 bin/folio:27-34 は head 内の
#      *最初の* block しか読まないため、 2 本目に何を書いても他 arm (@type/@id/前方関係/stakeholders 型) は全盲。
#      この arm が唯一の検出面ゆえ per-shape MK で aliveness を固定する (SKIP_REPRO=1 = repro-build も助けない)。
cp "$TMP/base.html" "$TMP/jl6.html"
perl -0777 -i -pe 's#</head>#<script type="application/ld\+json">{"\@id":"./forged.html","\@type":"schema:TechArticle"}</script>\n</head>#' "$TMP/jl6.html"
expect_vprefill_fail_at "JL6 ★2 本目の ld+json (dead emit) を block 数 arm が単独で捕捉" "$BASE" "$TMP/jl6.html" "block 数 == 1"

# JL7. ★@id の付け替え (./constitution.html → ./rules.html) → @id == contract .head_graph.id arm が捕捉。
#      @id は spec graph の node 識別子ゆえ、 倒れると別 doc の node として登録され reverse 材化・除外判定が
#      すべて別 URI へ流れる (@type は正しいまま = @type arm は全盲)。
cp "$TMP/base.html" "$TMP/jl7.html"
perl -0777 -i -pe 's#"\@id": "\./constitution\.html"#"\@id": "./rules.html"#' "$TMP/jl7.html"
expect_vprefill_fail_at "JL7 ★JSON-LD @id 付け替えを contract 突合 arm が捕捉" "$BASE" "$TMP/jl7.html" "@id == contract"

# --- (4) navigable p-N anchor (HTML 改竄・verify 段) ---
# AN-H1. ★負の対照 (裁定 3 が明示要求): id= を data-slot-id= へ差し替えた mutant で当該 arm が FAIL すること。
#        folio_anchor_exists (bin/folio:1426) は substring grep ゆえ data-slot-id="p-1" でも真になる =
#        「anchor はある」と誤答する。 受入述語 (bin/folio:2308 と同一の属性境界 anchor) はここで FAIL に倒れる。
cp "$TMP/base.html" "$TMP/anh1.html"
perl -0777 -i -pe 's#<h3 class="ph" id="p-1">#<h3 class="ph" data-slot-id="p-1">#' "$TMP/anh1.html"
#        ★errata-1 M3: 帰属 reason を *集合一致 arm 一意* の literal へ (旧 "p-N anchor" は 5 arm 共通 prefix で
#        arm を一意に選べず帰属が成立していなかった)。
expect_vprefill_fail_at "AN-H1 ★id→data-slot-id 差し替え (anchor_exists は騙せる) を厳密述語が捕捉" "$BASE" "$TMP/anh1.html" "厳密 id 集合 == lc(principles[].id)"

# AN-H2. ★欠落: p-9 の id を削除 → 集合一致 (欠落 0) が捕捉。 p-9 は design-intent 内 inbound 0 hit ゆえ
#        「inbound から期待集合を逆算する」設計だと silent に落ちる — 期待は contract 由来で立てている pin。
cp "$TMP/base.html" "$TMP/anh2.html"
perl -0777 -i -pe 's# id="p-9"##' "$TMP/anh2.html"
#        ★errata-1 M3: 帰属 reason を *件数 arm 一意* の literal へ (AN-H1 は集合一致 arm・本 case は件数 arm と
#        arm を分けて pin する。 どちらも旧 reason "p-N anchor" では 5 arm 共通で帰属不成立だった)。
expect_vprefill_fail_at "AN-H2 ★p-9 anchor 欠落 (inbound 0 hit ゆえ逆算では沈黙) を件数 arm が捕捉" "$BASE" "$TMP/anh2.html" "件数 == |principles|"

# AN-H3. ★余剰 (p-N 形でない id の混入): 節 anchor 形の偽 id を注入 → 全 id census arm が捕捉する per-shape MK。
#        ★errata-2 M8 (minor-1・事実訂正): 旧コメントは「全 id census arm *だけ* が捕捉する = census arm の単独
#        aliveness」と書いていたが実体と異なる。 実測では本 mutant は ★4 arm を同時に落とす —
#          (1) 厳密 id 集合 == lc(principles[].id) / (2) 件数 == |principles| (重複 0) /
#          (3) body 中の全 id 属性 == p-N のみ (余剰 id 0) / (4) id 行集合 == canonical h3 形の行集合。
#        ゆえ本 MK が固定するのは「census arm 群の単独 aliveness」ではなく「余剰 id 0 arm の帰属付き aliveness」
#        (帰属 reason は arm 一意ゆえ pin としては有効)。 虚偽の被覆表示は本リポの既知 blocking クラス
#        (6b459e7 で自ら是正した形の再発防止) ゆえ、 arm 数を実体どおりに書く。
cp "$TMP/base.html" "$TMP/anh3.html"
perl -0777 -i -pe 's#</body>#<div id="s2-principles">節 anchor の捏造 (lq12 の領分)</div></body>#' "$TMP/anh3.html"
expect_vprefill_fail_at "AN-H3 ★p-N 形でない余剰 id の混入を全 id census arm が捕捉" "$BASE" "$TMP/anh3.html" "余剰 id 0"

# AN-H4. ★single-quote id: folio_anchor_exists は真になるが bin/folio:2308 (objectGraph) は見ない非対称。
cp "$TMP/base.html" "$TMP/anh4.html"
perl -0777 -i -pe "s#</body>#<div id='p-1'>single-quote の偽 anchor</div></body>#" "$TMP/anh4.html"
#        ★errata-1 M2 で当該 arm は「非 canonical 形 id 属性 0 本 (single-quote / unquoted / 大文字)」へ拡張・改名
#        されたため、 帰属 literal を新ラベルへ追随させる (旧 literal のままだと [FAIL] 行に一致せず帰属が消える)。
expect_vprefill_fail_at "AN-H4 ★single-quote id (述語間の非対称) を非 canonical 形 arm が捕捉" "$BASE" "$TMP/anh4.html" "非 canonical 形 id 属性"

# AN-H5. ★strong 剥がし: 可視文字列は不変のまま strong だけを除去 → essence が無言で空になる改竄
#        (bin/folio:1468-1472 は id 行内の strong を要求)。 strong 全文 chk が唯一の観測面。
cp "$TMP/base.html" "$TMP/anh5.html"
perl -0777 -i -pe 's#<strong>(P-1: [^<]*)</strong>#$1#' "$TMP/anh5.html"
expect_vprefill_fail_at "AN-H5 ★strong 剥がし (essence が無言で空になる) を strong 全文 chk が捕捉" "$BASE" "$TMP/anh5.html" "strong 全文"

# AN-H6. ★strong 内の前置 id 偽装 (P-1: → P-99:): heading chk は前置を剥がしてから比較するため素通る。
#        essence の source が別原則を名乗る改竄を strong 全文 chk が単独で捕捉する per-shape MK。
cp "$TMP/base.html" "$TMP/anh6.html"
perl -0777 -i -pe 's#<strong>P-1: #<strong>P-99: #' "$TMP/anh6.html"
expect_vprefill_fail_at "AN-H6 ★strong 前置 id 偽装 (heading chk は素通る) を strong 全文 chk が捕捉" "$BASE" "$TMP/anh6.html" "strong 全文"

# AN-H7. ★後置平文偽 id: opener literal に id="p-N" を含めた後も、 pid span の後置捏造は 可視 pid 列 chk が
#        KILL することを実弾で示す (裁定 3 が要求する「opener を触った後の後置平文偽 id MK の存続確認」)。
cp "$TMP/base.html" "$TMP/anh7.html"
perl -0777 -i -pe 's#</body>#<span class="pid">P-99</span></body>#' "$TMP/anh7.html"
expect_vprefill_fail_at "AN-H7 ★後置平文偽 id (opener 更新後も) を可視 pid 列 chk が KILL" "$BASE" "$TMP/anh7.html" "可視 pid"

# AN-H8. ★relocation (p-1↔p-2 の id swap): 集合・件数・census・可視 pid 列・可視 heading 列・strong 全文列は
#        すべて不変のまま P-1 の行に id="p-2" が乗る。 folio_xref_essence (bin/folio:1468-1472) は id 行内の
#        strong を返すため tooltip SSoT と inbound #p-N の着地先が原則単位で入れ替わる = 本 pack が塞いだはずの
#        無言の死が再び開く。 per-row 対突合 (pid↔id 対) だけが観測面ゆえ実弾で aliveness を固定する。
#        ★assembler 退行 (emit_principle_row の swap) でも repro-build は同一 assembler の再生成ゆえ構造的に盲目。
cp "$TMP/base.html" "$TMP/anh8.html"
perl -0777 -i -pe 's#<h3 class="ph" id="p-1"><strong>P-1: #<h3 class="ph" id="p-2"><strong>P-1: #;
                   s#<h3 class="ph" id="p-2"><strong>P-2: #<h3 class="ph" id="p-1"><strong>P-2: #' "$TMP/anh8.html"
# ★着地 assert: swap が no-op 化すると「改竄していない HTML を verify に渡す」形になる (rc=0 で ng には倒れるが
#   理由が「arm 退行」と誤診される)。 両行の入れ替わりを直接 pin してから撃つ。
if grep -qF '<h3 class="ph" id="p-2"><strong>P-1: ' "$TMP/anh8.html" && grep -qF '<h3 class="ph" id="p-1"><strong>P-2: ' "$TMP/anh8.html"; then
  expect_vprefill_fail_at "AN-H8 ★id relocation (p-1↔p-2 swap) を per-row 対突合が捕捉" "$BASE" "$TMP/anh8.html" "pid↔id 対"
else
  ng "AN-H8 setup (p-1↔p-2 swap mutant が着地していない = MK 不成立)"
fi

# AN-H9. ★pid→ph 隣接 arm の帰属付き MK: pid span と h3 の *間* へ要素を差し込むと隣接 count が 14 → 13 へ落ちる。
#        この arm は「後置平文偽 id」(= AN-H7・帰属先は別 arm の『可視 pid』) とは別クラスを守る。 arm 単独の
#        aliveness を固定しないと、 隣接 opener を緩める退行が無検査で通る (verify-principle.sh:238 の主張の実体化)。
#        ★差し込む decoy は pid でも id でもない中立要素にする (他 arm を巻き添えで落とすと帰属が濁る)。
cp "$TMP/base.html" "$TMP/anh9.html"
perl -0777 -i -pe 's#(<span class="pid">P-1</span>)(<h3 class="ph" id="p-1">)#${1}<span class="sep">·</span>${2}#' "$TMP/anh9.html"
if grep -qF '<span class="sep">·</span><h3 class="ph" id="p-1">' "$TMP/anh9.html"; then
  expect_vprefill_fail_at "AN-H9 ★pid↔h3 の隣接破壊を pid→ph 隣接 arm が捕捉" "$BASE" "$TMP/anh9.html" "pid→ph 隣接"
else
  ng "AN-H9 setup (隣接破壊 mutant が着地していない = MK 不成立)"
fi

# === ★errata-1 (admin gate round-1) の per-shape MK: parser-differential クラス (既知 r8k) ===
# AN-H10 (M1 = B1+B3). ★essence 乗っ取り: p-head 行の pid span より *前* に decoy strong を挿し込む。
#         consumer (bin/folio:1468-1472) は「id="p-N" を含む行の *最初の* strong」を読むため essence が decoy へ
#         倒れるが、 h3 anchored な「strong 全文」chk は h3 内だけを見るので全 OK のまま通る (admin 実測の穴)。
#         consumer 述語を逐語複製した arm だけが観測面ゆえ、 その arm 一意 reason で aliveness を固定する。
cp "$TMP/base.html" "$TMP/anh10.html"
perl -0777 -i -pe 's#(<div class="p-head">)(<span class="pid">P-1</span>)#${1}<strong>P-1: 乗っ取られた要旨</strong>${2}#' "$TMP/anh10.html"
if grep -qF '<div class="p-head"><strong>P-1: 乗っ取られた要旨</strong><span class="pid">P-1</span>' "$TMP/anh10.html"; then
  expect_vprefill_fail_at "AN-H10 ★前方 decoy strong による essence 乗っ取りを consumer 述語複製 arm が捕捉" "$BASE" "$TMP/anh10.html" "consumer 述語複製"
else
  ng "AN-H10 setup (前方 decoy strong が着地していない = MK 不成立)"
fi

# AN-H11 (M2 = B2). ★行頭 id 属性: 旧 census は lookbehind [\s"] / '\sid="' の byte 近似ゆえ、 行の先頭に置かれた
#         id 属性 (直前に \s も " も無い) が census から不可視だった。 consumer 側 folio_anchor_exists は
#         grep -F の substring ゆえ可視 = forged id で hijack できた。 属性境界 parse への置換で塞がる。
cp "$TMP/base.html" "$TMP/anh11.html"
perl -0777 -i -pe 's#</body>#<div>\nid="p-99" forged\n</div></body>#' "$TMP/anh11.html"
if grep -qE '^id="p-99"' "$TMP/anh11.html"; then
  expect_vprefill_fail_at "AN-H11 ★行頭 id 属性 (旧 lookbehind の死角) を属性 parse census が捕捉" "$BASE" "$TMP/anh11.html" "余剰 id 0"
else
  ng "AN-H11 setup (行頭 id が着地していない = MK 不成立)"
fi

# AN-H12 (M2 = B2). ★大文字 ID 属性: HTML の属性名は case-insensitive ゆえ ID="p-99" は実描画で有効な anchor に
#         なるが、 旧 census (小文字固定 grep) からは不可視だった。 属性名 case 非依存 parse への置換で塞がる。
cp "$TMP/base.html" "$TMP/anh12.html"
perl -0777 -i -pe 's#</body>#<div ID="p-99">forged 大文字</div></body>#' "$TMP/anh12.html"
if grep -qF '<div ID="p-99">' "$TMP/anh12.html"; then
  expect_vprefill_fail_at "AN-H12 ★大文字 ID 属性 (旧 census の死角) を case 非依存 parse が捕捉" "$BASE" "$TMP/anh12.html" "非 canonical 形 id 属性"
else
  ng "AN-H12 setup (大文字 ID が着地していない = MK 不成立)"
fi

# === ★errata-2 (admin gate round-2) の per-shape MK: 検証入力の写像差 / 抽出述語差 / 可視面差 ===
# AN-H13 (M4 = ■A). ★<style> 本文へ置いた decoy strong による essence 乗っ取り。
#         $BODY (make_body・lib/verify-common.sh:115-160) は <style> 本文を *空化* する写像ゆえ、 旧実装 ($BODY 基準) では
#         CSS の中に置かれた「id="p-1" を含み <strong> を持つ行」が verify から完全に不可視だった。 consumer
#         (folio_xref_essence bin/folio:1468-1472) は ★生ファイルを行走査する ため CSS 行を先に掴んで essence を返す
#         (= 乗っ取り成立・floor は rc=0 / FAIL 0 の全緑)。 M4 で入力を生ファイルへ切替えたことの実弾 aliveness。
#         ★errata-2 追補 round-4 (同時発火 arm の開示・M8 と同一様式): 本 mutant は現行コード上 ★7 arm を同時に落とす —
#           (1) 厳密 id 集合 == lc(principles[].id) / (2) 件数 == |principles| / (3) 余剰 id 0 /
#           (4) consumer 可視面 (substring) の p-N 多重集合 / (5) <style> 本文 (arm-3) / (6) id 行集合 /
#           (7) essence: consumer 述語複製。 ゆえ本 MK が固定するのは単独 aliveness ではなく
#         「consumer 述語複製 arm の帰属付き aliveness」であり、 帰属 reason が arm 一意ゆえ pin として有効。
cp "$TMP/base.html" "$TMP/anh13.html"
perl -0777 -i -pe 's#(<style[^>]*>)#${1}\n[id="p-1"]\{\} /* <strong>P-1: CSS 経由の乗っ取り</strong> */#' "$TMP/anh13.html"
if grep -qF '[id="p-1"]{} /* <strong>P-1: CSS 経由の乗っ取り</strong> */' "$TMP/anh13.html"; then
  expect_vprefill_fail_at "AN-H13 ★<style> 内 decoy strong による essence 乗っ取りを consumer 述語複製 arm が捕捉" "$BASE" "$TMP/anh13.html" "consumer 述語複製"
else
  ng "AN-H13 setup (style 内 decoy strong が着地していない = MK 不成立)"
fi

# AN-H14 (M4 = ■A). ★<style> 本文へ置いた forged id: 同じく旧 $BODY 基準では不可視だったが、 consumer
#         folio_anchor_exists (bin/folio:1423-1427) は生ファイルへの grep -F substring ゆえ #p-99 が「解決した」と
#         誤答する (gate (h) 偽解決)。 生ファイル基準の census 群が観測面。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは「生ファイル基準の全 id census *だけ* が
#         観測面」と書いていたが実体と異なる。 実測では本 mutant は ★6 arm を同時に落とす —
#           (1) 厳密 id 集合 == lc(principles[].id) / (2) 件数 == |principles| / (3) 余剰 id 0 /
#           (4) consumer 可視面 (substring) の p-N 多重集合 / (5) <style> 本文 (arm-3) / (6) id 行集合。
#         ゆえ本 MK が固定するのは単独 aliveness ではなく「余剰 id 0 arm の帰属付き aliveness」であり、
#         帰属 reason 「余剰 id 0」が arm 一意ゆえ pin として有効 (AN-H3 / AN-H20 / AN-H21 と同じ言い回し)。
cp "$TMP/base.html" "$TMP/anh14.html"
perl -0777 -i -pe 's#(<style[^>]*>)#${1}\n[id="p-99"]\{color:red\}#' "$TMP/anh14.html"
if grep -qF '[id="p-99"]{color:red}' "$TMP/anh14.html"; then
  expect_vprefill_fail_at "AN-H14 ★<style> 内 forged id (gate (h) 偽解決) を生ファイル census が捕捉" "$BASE" "$TMP/anh14.html" "余剰 id 0"
else
  ng "AN-H14 setup (style 内 forged id が着地していない = MK 不成立)"
fi

# AN-H15 (M5 = ■B). ★ld+json を開始タグと同じ 1 行へ畳む: @type / @id / block 数 は genuine と *同値* のままだが、
#         consumer folio_extract_head_jsonld (bin/folio:27-34) は行単位で走り開始タグ行を print しないため JSON 本文を
#         1 byte も掴めず、 bin/folio の 5 site が全て「@type 不一致」枝へ倒れる (folio validate の cluster-reachability が [FAIL]→[WARN]
#         へ反転 = OR1 の 2 値 oracle を @type 不触のまま反転させる)。 旧 verify は head slurp + 非貪欲 regex ゆえ
#         genuine と同じ JSON を掴み rc=0 だった。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは「抽出述語の一致 pin *だけ* が観測面」と
#         書いていたが実体と異なる。 実測では本 mutant は ★2 arm を同時に落とす —
#           (1) 抽出述語 == consumer 述語 (出力一致 pin) / (2) 「jq parse 不能」枝。
#         ★(2) の理由も実測へ訂正する: consumer 述語で取った値は *空ではなく* ★後続の <meta name="folio-layer"…> /
#           <meta name="folio-stakeholders"…> 2 行 (JSON として不正) ゆえ「block 不在」枝ではなく「jq parse 不能」枝に
#           落ちる。 「空へ落ちる」という機構記述は誤り (M8 と同一様式の事実訂正)。
#         ゆえ本 MK が固定するのは単独 aliveness ではなく「一致 pin の帰属付き aliveness」であり、
#         帰属 reason 「抽出述語 == consumer 述語」が arm 一意ゆえ pin として有効。
cp "$TMP/base.html" "$TMP/anh15.html"
perl -0777 -i -pe 's{(<script type="application/ld\+json">)(.*?)(</script>)}{my($o,$b,$c)=($1,$2,$3); $b =~ s/\s*\n\s*/ /g; $b =~ s/^\s+//; "$o$b$c"}se' "$TMP/anh15.html"
# ★着地 assert は -F 基準で書く: 「開始タグの行が閉じタグも含む」= 1 行へ畳まれたこと。 grep -E の '\{' は GNU grep で
#   literal brace として解釈されず NOMATCH に倒れる (実測) ため ERE の中括弧 escape に依存しない形にする。
if grep -qF '</script>' <<< "$(grep -F 'application/ld+json' "$TMP/anh15.html")"; then
  expect_vprefill_fail_at "AN-H15 ★同一行 ld+json (consumer だけが JSON 本文を掴めない) を抽出述語一致 pin が捕捉" "$BASE" "$TMP/anh15.html" "抽出述語 == consumer 述語"
else
  ng "AN-H15 setup (同一行 ld+json が着地していない = MK 不成立)"
fi

# AN-H16 (M6 = ■C). ★data-*-id 接尾への p-N 複製: 厳密 census は「属性名の真の先頭」を要求するため data-ref-id= を
#         id 属性と数えない (正しい)。 だが consumer 2 本は属性境界を見ない substring 述語ゆえ可視 = 既存 anchor の
#         複製で essence source 行を先取りできる。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは「consumer 可視面 (substring) 多重集合 arm
#         *だけ* が観測面」と書いていたが実体と異なる。 実測では本 mutant は ★2 arm を同時に落とす —
#           (1) consumer 可視面 (substring) の p-N 多重集合 (arm-1) / (2) 接尾 id 属性は prose slot 由来のみ (arm-2)。
#         ゆえ本 MK が固定するのは単独 aliveness ではなく「arm-1 の帰属付き aliveness」であり、
#         帰属 reason 「consumer 可視面 (substring)」が arm 一意ゆえ pin として有効。
cp "$TMP/base.html" "$TMP/anh16.html"
perl -0777 -i -pe 's#</body>#<div data-ref-id="p-1">接尾属性による p-1 の複製</div></body>#' "$TMP/anh16.html"
if grep -qF '<div data-ref-id="p-1">' "$TMP/anh16.html"; then
  expect_vprefill_fail_at "AN-H16 ★data-*-id 接尾への p-N 複製を consumer 可視面 census が捕捉" "$BASE" "$TMP/anh16.html" "consumer 可視面 (substring)"
else
  ng "AN-H16 setup (data-*-id 接尾が着地していない = MK 不成立)"
fi

# AN-H17 (M6 = ■C). ★任意接尾 (xid=) への forged p-N: 厳密 census からは不可視 (x が属性名の前置文字ゆえ
#         真の先頭でない)。 admin 実弾と同形。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは「data-* 形でないため prose slot 系 arm の
#         偶発被覆 *すら無く*」と書いていたが実体と異なる。 arm-2 (接尾 id 属性) の述語は属性名を [-A-Za-z0-9_:]+id で
#         取るため xid= も接尾 id 属性として数え、 expected 0 / got 1 で同時に落ちる。 実測 ★2 arm —
#           (1) consumer 可視面 (substring) の p-N 多重集合 (arm-1) / (2) 接尾 id 属性は prose slot 由来のみ (arm-2)。
#         ゆえ本 MK が固定するのは単独 aliveness ではなく「arm-1 の帰属付き aliveness」であり、
#         帰属 reason 「consumer 可視面 (substring)」が arm 一意ゆえ pin として有効。
cp "$TMP/base.html" "$TMP/anh17.html"
perl -0777 -i -pe 's#</body>#<div xid="p-99">任意接尾による forged anchor</div></body>#' "$TMP/anh17.html"
if grep -qF '<div xid="p-99">' "$TMP/anh17.html"; then
  expect_vprefill_fail_at "AN-H17 ★任意接尾 (xid=) の forged p-N を consumer 可視面 census が捕捉" "$BASE" "$TMP/anh17.html" "consumer 可視面 (substring)"
else
  ng "AN-H17 setup (任意接尾 xid= が着地していない = MK 不成立)"
fi

# AN-H18 (M6 = ■C). ★single-quote の接尾複製: folio_anchor_exists は id='..' も真とする (bin/folio:1426 の第 2 grep)。
#         接尾 + single-quote の組合せは厳密 census (真の先頭要求) と 非 canonical 形 arm (同じく厳密 census 由来) の
#         どちらからも不可視。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは「substring 面の多重集合 arm *だけ* が
#         撃てる」と書いていたが実体と異なる。 実測では本 mutant は ★2 arm を同時に落とす —
#           (1) consumer 可視面 (substring) の p-N 多重集合 (arm-1) / (2) 接尾 id 属性は prose slot 由来のみ (arm-2)。
#         ゆえ本 MK が固定するのは単独 aliveness ではなく「arm-1 の帰属付き aliveness」であり、
#         帰属 reason 「consumer 可視面 (substring)」が arm 一意ゆえ pin として有効。
cp "$TMP/base.html" "$TMP/anh18.html"
perl -0777 -i -pe "s#</body>#<div data-x-id='p-3'>single-quote 接尾による p-3 の複製</div></body>#" "$TMP/anh18.html"
if grep -qF "<div data-x-id='p-3'>" "$TMP/anh18.html"; then
  expect_vprefill_fail_at "AN-H18 ★single-quote 接尾の p-N 複製を consumer 可視面 census が捕捉" "$BASE" "$TMP/anh18.html" "consumer 可視面 (substring)"
else
  ng "AN-H18 setup (single-quote 接尾が着地していない = MK 不成立)"
fi

# AN-H19 (M7 = ■D). ★errata-1 で新設した「strong 出現数 == 1」arm の退行 pin (arm は alive だったが敵対 suite の
#         帰属 literal が 0 hit = 退行を検知する pin が無かった)。 h3 の *後* に decoy strong を足すと consumer は
#         「最初の strong」= genuine を読むため値の比較系は全て素通り、 本数 pin だけが落ちる (単一 arm 帰属)。
cp "$TMP/base.html" "$TMP/anh19.html"
perl -0777 -i -pe 's#(<h3 class="ph" id="p-1"><strong>P-1: [^<]*</strong></h3>)#${1}<strong>後方 decoy</strong>#' "$TMP/anh19.html"
if grep -qF '</h3><strong>後方 decoy</strong>' "$TMP/anh19.html"; then
  expect_vprefill_fail_at "AN-H19 ★後方 decoy strong (値比較は全て素通る) を strong 出現数 pin が捕捉" "$BASE" "$TMP/anh19.html" "strong 出現数"
else
  ng "AN-H19 setup (後方 decoy strong が着地していない = MK 不成立)"
fi

# AN-H20 (M7 = ■D). ★errata-1 で新設した「空 essence 0 件」arm の退行 pin。 strong を空文字化すると consumer は
#         空文字を返し、 gate (i) は bin/folio:2574 で essence 空を *無言 skip* (fail-open) する = 無言の死。
#         ★本 mutant は可視文字列も壊すため複数 arm が同時に落ちる (strong 全文 / 可視 heading / consumer 述語複製)。
#         帰属は arm 一意の reason 「空 essence」で取る (expect_vprefill_fail_at が行頭 [FAIL] を anchor する)。
cp "$TMP/base.html" "$TMP/anh20.html"
perl -0777 -i -pe 's#<strong>P-1: [^<]*</strong>#<strong></strong>#' "$TMP/anh20.html"
if grep -qF '<h3 class="ph" id="p-1"><strong></strong></h3>' "$TMP/anh20.html"; then
  expect_vprefill_fail_at "AN-H20 ★strong 空文字化 (gate (i) が無言 skip する形) を空 essence pin が捕捉" "$BASE" "$TMP/anh20.html" "空 essence"
else
  ng "AN-H20 setup (strong 空文字化が着地していない = MK 不成立)"
fi

# AN-H21 (M7 = ■D). ★errata-1 で新設した「id 行集合 == canonical h3 形の行集合 (essence source 行粒度)」arm の退行 pin。
#         id を h3 から親 div (同一行) へ relocate すると、 期待側 (h3 形の行) からは消え 実側 (真の id 属性を持つ行) には
#         残るため行集合が割れる。
#         ★errata-2 追補 round-4 (列挙の事実訂正・M8 と同一様式): 旧コメントは同時発火 arm を 4 本 (可視 heading /
#         strong 全文 / pid→ph 隣接 / pid↔id 対) と列挙していたが実測は ★6 arm — 上記 4 本に加えて
#           (5) essence: p-head 行あたり strong 出現数 == 1 / (6) 本命の p-N anchor: id 行集合 (essence source 行粒度)。
#         帰属は arm 一意の reason 「essence source」で取る (列挙が実体と食い違うと後続 cell が誤った前提を置く)。
cp "$TMP/base.html" "$TMP/anh21.html"
perl -0777 -i -pe 's#(<div class="p-head")(><span class="pid">P-1</span><h3 class="ph") id="p-1"(>)#${1} id="p-1"${2}${3}#' "$TMP/anh21.html"
if grep -qF '<div class="p-head" id="p-1"><span class="pid">P-1</span><h3 class="ph">' "$TMP/anh21.html"; then
  expect_vprefill_fail_at "AN-H21 ★id を h3 から親 div へ relocate (essence source 行が割れる) を行粒度 pin が捕捉" "$BASE" "$TMP/anh21.html" "essence source"
else
  ng "AN-H21 setup (id relocate が着地していない = MK 不成立)"
fi

# === ★errata-2 追補 (admin gate round-3) の per-shape MK: M6 の narrow が残した 2 クラスの実弾 pin ===
# AN-H22 (M6 = ■C / round-3 critical). ★quote-desync 型 forged anchor: 直前の decoy 属性の値が開始 quote を
#         「食う」ことで、 substring census (旧・値を貪欲に取る形) から target を丸ごと隠す shape。
#         旧実装では 掴む値が " data-y-id=" (p-N 形でない) ゆえ記録もされず、 //g の pos が target の開始 quote の
#         後ろへ進んで id="p-99" が完全に不可視だった (verify rc=0・[FAIL] 0 のまま consumer grep -qF は真)。
#         厳密 census も data-x-id / data-y-id を「属性名の真の先頭でない」と正しく除外する。
#         ★errata-2 追補 round-4 (事実訂正・M8 と同一様式): 旧コメントは直前の「全 arm 素通り」と併記する形で
#         「p-N 値を直接要求する形 (現行) *でのみ* 捕捉できる」と書いており、 ★現行 arm 集合に対する主張としては偽。
#         実体は 2 段に分かれる (worker 実測):
#           (a) 現行コードでの発火は ★2 arm — (1) consumer 可視面 (substring) の p-N 多重集合 (arm-1) /
#               (2) 接尾 id 属性は prose slot 由来のみ (arm-2・expected 0 / got 2)。 mutant 自体は arm-2 も落とす。
#           (b) 本 MK が固定するのは arm-1 の ★定式化 である: arm-1 を旧貪欲形 (任意値を掴んでから ^p-[0-9]+$ で
#               filter) へ戻すと本 mutant では arm-1 の [FAIL] 行が消え (arm-2 だけが残る)、
#               expect_vprefill_fail_at の行頭 anchor が ng に転ぶ (実測)。 = 値の形 軸 arm の per-shape aliveness。
cp "$TMP/base.html" "$TMP/anh22.html"
perl -0777 -i -pe 's#</body>#<div data-x-id=" data-y-id="p-99">quote-desync 型 forged anchor</div></body>#' "$TMP/anh22.html"
if grep -qF '<div data-x-id=" data-y-id="p-99">' "$TMP/anh22.html"; then
  expect_vprefill_fail_at "AN-H22 ★quote-desync 型 forged p-N (旧 substring census は非重複走査で見逃す) を可視面 census が捕捉" "$BASE" "$TMP/anh22.html" "consumer 可視面 (substring)"
else
  ng "AN-H22 setup (quote-desync 型 forged anchor が着地していない = MK 不成立)"
fi

# AN-H23 (M6 = ■C / round-3 major). ★値末尾 id= による masking: decoy 属性の *値* が id= で終わることで、 その
#         閉じ quote が「開始 quote」として消費され 以降の真の出現が mask される shape (AN-H22 と発生機序が違う
#         = 属性名側で食うか 値側で食うか)。 shape が違えば 1 instance の実弾は他方の穴を証明しないため別 MK に割る。
cp "$TMP/base.html" "$TMP/anh23.html"
perl -0777 -i -pe 's#</body>#<div data-x="xid=" data-ref-id="p-99">値末尾 id= による masking</div></body>#' "$TMP/anh23.html"
if grep -qF '<div data-x="xid=" data-ref-id="p-99">' "$TMP/anh23.html"; then
  expect_vprefill_fail_at "AN-H23 ★値末尾 id= で後続を mask する forged p-N を可視面 census が捕捉" "$BASE" "$TMP/anh23.html" "consumer 可視面 (substring)"
else
  ng "AN-H23 setup (値末尾 id= 型 masking が着地していない = MK 不成立)"
fi

# AN-H24 (M6 = ■C / round-3 major). ★非 p-N 値 の接尾 forged anchor: 値の形 軸の arm は ^p-[0-9]+$ で捨て、
#         厳密 census は接尾属性を原理的に見ないため、 旧実装では *どの arm の観測面にも入らなかった*
#         (verify rc=0 のまま consumer grep -qF 'id="s2-forged"' が真 = gate (h) 偽解決)。 属性名 軸 arm の aliveness。
cp "$TMP/base.html" "$TMP/anh24.html"
perl -0777 -i -pe 's#</body>#<div data-x-id="s2-forged">非 p-N 値の接尾 forged anchor</div></body>#' "$TMP/anh24.html"
if grep -qF '<div data-x-id="s2-forged">' "$TMP/anh24.html"; then
  expect_vprefill_fail_at "AN-H24 ★非 p-N 値の接尾 forged anchor (data-*-id 形) を接尾 id 属性 allowlist が捕捉" "$BASE" "$TMP/anh24.html" "接尾 id 属性"
else
  ng "AN-H24 setup (非 p-N 接尾 forged が着地していない = MK 不成立)"
fi

# AN-H25 (M6 = ■C / round-3 major). ★同じ非 p-N 値でも data-* 形でない bare 接尾 (xid=) は DOM 構造クラスが違う
#         (hyphen 前置か 素の名前前置か)。 per-shape MK 規律 (jyfh/r8k) に従い AN-H24 とは別 instance で撃つ。
cp "$TMP/base.html" "$TMP/anh25.html"
perl -0777 -i -pe 's#</body>#<div xid="s2-forged">bare 接尾の非 p-N forged anchor</div></body>#' "$TMP/anh25.html"
if grep -qF '<div xid="s2-forged">' "$TMP/anh25.html"; then
  expect_vprefill_fail_at "AN-H25 ★非 p-N 値の bare 接尾 forged anchor (xid= 形) を接尾 id 属性 allowlist が捕捉" "$BASE" "$TMP/anh25.html" "接尾 id 属性"
else
  ng "AN-H25 setup (bare 接尾の非 p-N forged が着地していない = MK 不成立)"
fi

# AN-H26 (M6 = ■C / round-3 fix 自身の fail-open 封鎖). ★属性名 allowlist を「名前だけ」で張ると、 allowlist 済みの
#         data-slot-id を単体で足すだけで穴が *移設* される (fix が新たな fail-open を作る形)。 現行 arm は
#         data-prose-slot との隣接まで要求するため、 prose slot を伴わない孤立 data-slot-id は余剰として落ちる。
cp "$TMP/base.html" "$TMP/anh26.html"
perl -0777 -i -pe 's#</body>#<div data-slot-id="s2-forged">孤立 data-slot-id による allowlist 迂回</div></body>#' "$TMP/anh26.html"
if grep -qF '<div data-slot-id="s2-forged">' "$TMP/anh26.html"; then
  expect_vprefill_fail_at "AN-H26 ★孤立 data-slot-id による allowlist 迂回 (穴の移設) を隣接要求が捕捉" "$BASE" "$TMP/anh26.html" "接尾 id 属性"
else
  ng "AN-H26 setup (孤立 data-slot-id が着地していない = MK 不成立)"
fi

# === ★errata-2 追補 (admin gate round-4) の per-shape MK: $BODY 不可視域 (<style> 本文) への pair 形隠蔽 ===
# AN-H27 (M4/M6 = ■A×■C / round-4 major). ★<style> 本文へ *対で* 置いた forged anchor
#         (data-prose-slot="…" data-slot-id="s2-forged") — arm-2 は prose slot 隣接を allowlist するため通し、
#         arm-1 は値が非 p-N ゆえ不発、 厳密 census は接尾属性を原理的に見ず、 §11 (prose スロット) は $BODY 基準で
#         make_body が <style> 本文を空化するため ★pre-fill / --filled の両モードとも観測面外だった
#         (round-4 実弾: 両モードとも rc=0・[FAIL] 0 のまま consumer grep -qF 'id="s2-forged"' が真 = gate (h) 偽解決)。
#         ★arm-2 の残余開示が「--filled では §11 が捕捉する」と *配置に依らない* 形で書いていた虚偽被覆表示の是正と
#         対になる実弾 pin。 現行は配置面軸の arm-3 (「<style> 本文」) が単独で担う (帰属 reason は arm 一意)。
#         ★genuine CSS として妥当な形 (CSS コメント内) で撃つ: make_body は <style> 本文を parse せず素通しするため
#         fail-closed 検出には掛からず、 「合法な CSS の中に隠す」という実際の攻撃 shape をそのまま再現できる。
cp "$TMP/base.html" "$TMP/anh27.html"
perl -0777 -i -pe 's#(<style[^>]*>)#${1}\n/* <div data-prose-slot="x" data-slot-id="s2-forged">style 本文への pair 形隠蔽</div> */#' "$TMP/anh27.html"
if grep -qF '/* <div data-prose-slot="x" data-slot-id="s2-forged">style 本文への pair 形隠蔽</div> */' "$TMP/anh27.html"; then
  # ★errata-3 M9: arm-3 が「領域 regex」から「$HTML == $BODY 差分」へ置換され arm 名が変わったため、 帰属 literal を
  #   新ラベルへ追随させる (旧 literal のままだと [FAIL] 行に一致せず帰属が消える = errata-1 M3 で踏んだのと同じ罠)。
  expect_vprefill_fail_at "AN-H27 ★<style> 本文への pair 形 forged anchor (§11 が両モード盲) を配置面 arm が捕捉" "$BASE" "$TMP/anh27.html" "consumer 可視 id= 出現数が"
else
  ng "AN-H27 setup (style 本文への pair 形隠蔽が着地していない = MK 不成立)"
fi

# === ★errata-3 追補 (admin ceiling round-3) の per-shape MK: close 書式 tolerance / allowlist case / mode 非依存 ===
# AN-H28 (M9・critical). ★`</style >` 変種 (close タグ内に空白 1 個) での隠蔽。 make_body (lib/verify-common.sh:130-146)
#         は close の junk が空白のみなら genuine 受理して本文を空化するため、 領域を自前 regex `</style>` で再モデル
#         していた旧 arm-3 だけが 0 match に落ち chk が「0 == 0」で ★恒真 PASS になった (pre-fill / --filled とも
#         rc=0・[FAIL] 0 のまま consumer grep -qF 'id="s2-forged"' が真 = gate (h) 偽解決・両 verifier + worker が実弾再現)。
#         現行 arm は領域を数え直さず ★make_body の出力そのもの ($BODY) と $HTML の consumer 可視 id= 出現数の差で
#         見るため、 close 書式に依らず捕捉する。 ★既存 AN-H27 は canonical close 形 (`</style>`) のみを撃つので
#         本 shape の退行を証明しない = 別 MK が要る (虚偽の被覆表示にしないための分離)。
#         ★pre-fill / --filled の ★両モードで撃つ (処方 M9 の明示要求)。
#         ★errata-4 M13: mode loop へ ★artifact を追加する (arm-3a × --artifact の durable pin が無かった)。
#           ★検体は ★base-filled 由来 を使う: pre-fill 生成物 (base.html) を --artifact に渡すと genuine でも
#           「prose スロットは全て充填」arm が落ちるため、 mutant と無関係な FAIL を「捕捉した」と誤読する
#           (AN-H30ctl で焼いた既知の罠・worker が実際に踏んだ)。 ゆえ filled と artifact は同じ _src を使う。
anh28_payload='/* <div data-prose-slot="x" data-slot-id="s2-forged">close 書式 tolerance を突く隠蔽</div> */'
for _m in prefill filled artifact; do
  _src="$TMP/base.html"; [[ "$_m" == "filled" || "$_m" == "artifact" ]] && _src="$TMP/base-filled.html"
  cp "$_src" "$TMP/anh28-$_m.html"
  PAYLOAD="$anh28_payload" perl -0777 -i -pe 's#(<style[^>]*>)#${1}."\n".$ENV{PAYLOAD}#e; s#</style>#</style >#' "$TMP/anh28-$_m.html"
  # ★着地 assert: (a) payload が入っていること (b) close が空白入り形へ変わっていること (c) ★旧 arm-3 の regex が
  #   0 match に落ちる shape であること = 「新 arm でしか撃てない」ことを mutant 側で固定する (MK の意義の pin)。
  _legacy="$(perl -CSD -0777 -ne 'my $t=$_; my $c=0; while ($t =~ m{<style[^>]*>(.*?)</style>}gsi){ my $s=$1; $c++ while $s =~ /id\s*=\s*(?:"|\x27)/gi; } print $c;' "$TMP/anh28-$_m.html")"
  if grep -qF 'id="s2-forged"' "$TMP/anh28-$_m.html" && grep -qF '</style >' "$TMP/anh28-$_m.html" && [[ "$_legacy" == "0" ]]; then
    case "$_m" in
      prefill)  expect_vprefill_fail_at "AN-H28p ★'</style >' 変種での隠蔽 (旧 regex は 0 match で恒真 PASS) を HTML==BODY 差分 arm が捕捉 [pre-fill]" "$BASE" "$TMP/anh28-$_m.html" "consumer 可視 id= 出現数が" ;;
      filled)   expect_vfilled_fail_at "AN-H28f ★'</style >' 変種での隠蔽を HTML==BODY 差分 arm が捕捉 [--filled]" "$TMP/anh28-$_m.html" "consumer 可視 id= 出現数が" ;;
      artifact) expect_vartifact_fail_at "AN-H28a ★'</style >' 変種での隠蔽を HTML==BODY 差分 arm が捕捉 [--artifact] (errata-4 M13)" "$TMP/anh28-$_m.html" "consumer 可視 id= 出現数が" ;;
    esac
  else
    ng "AN-H28$_m setup (payload/close 書式/旧 regex 0-match のいずれかが不成立 = MK 不成立: legacy=$_legacy)"
  fi
done

# AN-H29 (M10・major). ★allowlist 側だけ大文字にした pair (DATA-PROSE-SLOT="x" data-slot-id="s2-forged")。
#         接尾 id 属性は ★小文字のまま ゆえ consumer から可視 (grep -qF 'id="s2-forged"' = 真) だが、 旧実装は
#         regex 全体が /gi で allowlist 側も case-insensitive に一致したため余剰計数 0 → pre-fill / --artifact とも
#         rc=0 で素通った。 §11 backstop は case-sensitive でこの shape に不発 = 「allowlist が backstop より緩い」
#         非対称が穴の本体。 allowlist を case-exact ((?-i:…)) にした現行のみが撃てる。
#         ★大文字/小文字を両方大文字にした変種は consumer からも不可視 (実害なし) ゆえ ★採らない — 本 MK は
#           「consumer 可視でありながら allowlist をすり抜ける」最小 shape を撃つ (worker 実測で弁別)。
cp "$TMP/base.html" "$TMP/anh29.html"
perl -0777 -i -pe 's#</body>#<div DATA-PROSE-SLOT="x" data-slot-id="s2-forged">allowlist の case 非対称を突く</div></body>#' "$TMP/anh29.html"
if grep -qF '<div DATA-PROSE-SLOT="x" data-slot-id="s2-forged">' "$TMP/anh29.html" && grep -qF 'id="s2-forged"' "$TMP/anh29.html"; then
  expect_vprefill_fail_at "AN-H29 ★allowlist 側のみ大文字の pair (consumer 可視) を case-exact allowlist が捕捉" "$BASE" "$TMP/anh29.html" "接尾 id 属性は prose slot 由来のみ"
else
  ng "AN-H29 setup (大文字 allowlist pair が着地していない = MK 不成立)"
fi

# AN-H30 (M11(b)・major). ★--artifact mode で arm が発火することの durable pin。 --artifact は usage 上の正式第 3 mode
#         (他 pack では CI が landed 成果物へ使う) だが、 §11 の --artifact 分岐は manifest 突合を ★走らせない ため、
#         「--filled では §11 が捕捉する」型の被覆に頼る arm は --artifact で無防備になる。 本 pack の arm-1/2/3 は
#         $HTML 直読ゆえ mode 非依存 — その性質を *主張* でなく実弾で固定する (round-3 が指摘した pin 欠落の是正)。
#         ★陽性対照を必ず対で置く: genuine filled を --artifact に渡すと rc=0 であることを先に固定しないと、
#           「mutant を捕捉した」のか「その mode では genuine も落ちる」のか区別できない (worker が実際にこの
#           取り違えを踏んだ: pre-fill 生成物を --artifact に渡すと genuine でも prose 充填 arm が落ちる)。
expect_vartifact_pass "AN-H30ctl ★陽性対照: genuine filled 成果物は --artifact で PASS (検体が正しいことの固定)" "$TMP/base-filled.html"
cp "$TMP/base-filled.html" "$TMP/anh30.html"
perl -0777 -i -pe 's#</body>#<div xid="p-99">--artifact でも撃てることの pin</div></body>#' "$TMP/anh30.html"
if grep -qF '<div xid="p-99">' "$TMP/anh30.html"; then
  expect_vartifact_fail_at "AN-H30 ★接尾 forged id を --artifact でも arm-1 が捕捉 (mode 非依存の durable pin)" "$TMP/anh30.html" "consumer 可視面 (substring)"
else
  ng "AN-H30 setup (--artifact 用 mutant が着地していない = MK 不成立)"
fi

# === ★errata-4 追補 (admin ceiling round-4 blocking M12) の per-shape MK: comment 内 <style> テキスト領域 ===
# AN-H31 / AN-H32. ★HTML comment の中に <style>…</style> テキストを書き、 その中へ pair 形 forged anchor を隠す。
#         make_body は comment を ★verbatim 保存する ため $HTML と $BODY の consumer 可視 id= count が等しくなり、
#         ★arm-3a (差分形) は盲 になる。 一方 arm-3b (構文形・「<style>」という文字列で領域を切る) は comment 内表記でも
#         数えるため捕捉する = 2 arm が ★incomparable であることの実弾 (errata-3 で arm-3b を削除したのは検出退行だった)。
#         ★consumer からは可視 (grep -qF 'id="s2-forged"' = TRUE) ゆえ gate (h) 偽解決が成立する実害 shape。
#         ★2 検体を分ける: 中身つき対は --artifact で (pre-fill/--filled は §11 が別理由で落とすため帰属が濁る)、
#           空の対は pre-fill で (--filled/--artifact は §11 の充填 arm が落とす) 撃つ = arm-3b 単独の観測面を選ぶ。
#         ★errata-5 M15 (round-5 blocking root A・★宣言と実体の乖離の是正): errata-4 の註は「着地 assert に
#           arm-3a 盲 ($HTML == $BODY count 一致) を含める」と宣言していたが ★実装が伴っていなかった —
#           AN-H31 の変数は代入のみで if 条件に使われない dead 変数で、 しかも $BODY 側 count を取らないため
#           使っても宣言どおりの assert にならず、 AN-H32 には計算すら無かった (= 本 cell が繰り返し是正してきた
#           「虚偽の被覆表示」クラスの ★自己再発)。 ゆえ ★宣言でなく実装を採る:
#           両検体の着地 assert に ★arm-3a の帰属 [FAIL] が 0 本 であることの実測を含める。
#           これにより M12 の core (incomparable) の ★方向 B (arm-3a 盲 → arm-3b のみ捕捉) が ★commit 内に
#           durable に固定される (従来は untracked selftest §4c にしか無く cell 終了後に消えていた)。
#           ※方向 A (arm-3b 盲 → arm-3a のみ捕捉) は AN-H28 の _legacy==0 着地 assert が既に commit 内で pin 済み。
a3a_fail_lines() { # $1 = mode (prefill|filled|artifact) / $2 = html → arm-3a 帰属の行頭 [FAIL] 行数
  local out
  case "$1" in
    prefill)  out="$(bash "$VER" "$BASE" "$2" 2>&1)" ;;
    filled)   out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" 2>&1)" ;;
    artifact) out="$(bash "$VER" --artifact "$BASE" "$2" 2>&1)" ;;
  esac
  grep -F -- 'consumer 可視 id= 出現数が' <<<"$out" | grep -cE '^ *\[FAIL\]'
}
anh31_payload='<!-- <style>/* <div data-prose-slot="x" data-slot-id="s2-forged">comment 内 style テキストへの隠蔽</div> */</style> -->'
anh32_payload='<!-- <style>/* <div data-prose-slot="x" data-slot-id="s2-forged"></div> */</style> -->'
cp "$TMP/base-filled.html" "$TMP/anh31.html"
PAYLOAD="$anh31_payload" perl -0777 -i -pe 's#</body>#$ENV{PAYLOAD}."</body>"#e' "$TMP/anh31.html"
_anh31_a3a="$(a3a_fail_lines artifact "$TMP/anh31.html")"
if grep -qF 'id="s2-forged"' "$TMP/anh31.html" && grep -qF '<!-- <style>' "$TMP/anh31.html" && [[ "$_anh31_a3a" == "0" ]]; then
  expect_vartifact_fail_at "AN-H31 ★comment 内 <style> テキストへの pair 隠蔽 (中身つき) を構文領域 arm が捕捉 [--artifact] (arm-3a は盲を実測)" "$TMP/anh31.html" "<style> テキスト領域"
else
  ng "AN-H31 setup (payload 着地 / arm-3a 盲 のいずれかが不成立 = MK 不成立: arm-3a 帰属 FAIL=$_anh31_a3a・期待 0)"
fi
cp "$TMP/base.html" "$TMP/anh32.html"
PAYLOAD="$anh32_payload" perl -0777 -i -pe 's#</body>#$ENV{PAYLOAD}."</body>"#e' "$TMP/anh32.html"
_anh32_a3a="$(a3a_fail_lines prefill "$TMP/anh32.html")"
if grep -qF 'id="s2-forged"' "$TMP/anh32.html" && grep -qF '<!-- <style>' "$TMP/anh32.html" && [[ "$_anh32_a3a" == "0" ]]; then
  expect_vprefill_fail_at "AN-H32 ★comment 内 <style> テキストへの pair 隠蔽 (空の対) を構文領域 arm が捕捉 [pre-fill] (arm-3a は盲を実測)" "$BASE" "$TMP/anh32.html" "<style> テキスト領域"
else
  ng "AN-H32 setup (payload 着地 / arm-3a 盲 のいずれかが不成立 = MK 不成立: arm-3a 帰属 FAIL=$_anh32_a3a・期待 0)"
fi

# AN4. ★contract 側 anchor drift (.principles[0].anchor = p-99) → 「contract .anchor == lc(.id)」arm が捕捉。
#      生成物は正しいまま contract だけが drift する形 (= 次回 build で id が p-99 に転ぶ予告) を verify 段で
#      止める arm の per-shape MK。 ★別名 contract だと golden 不在 FAIL が混ざるため bd_canon (canonical
#      basename) 経由にし、 帰属は expect_vprefill_fail_at (行頭 ^ *[FAIL] anchor) で取る。
f="$(bd_canon an4)"
yq -i '.principles[0].anchor = "p-99"' "$f"
expect_vprefill_fail_at "AN4 ★contract 側 anchor drift (p-99) を lc(.id) 突合 arm が捕捉" "$f" "$TMP/base.html" "contract .anchor == lc(.id)"

# --- (5) ★陽性 oracle: @type=FolioConstitution が実際に *読まれている* ことの観測面 ---
# ★「inventory / validate に constitution が出ない」は単独では vacuous — JSON-LD が 1 byte も読まれていなくても
#   同じ結果になる (bin/folio:127 / :436 / :617 / :2429 は直前行の空 block 判定と *同一枝* に落ちる)。
#   ゆえ @type の正の検出面である folio_nav_is_self_root (bin/folio:4511) を観測する:
#   self-root では cluster-reachability 違反が WARN でなく *FAIL* 側へ振り分けられる (bin/folio:2930-2931)。
#   exit code では判別できない (どちらでも他 gate が exit を支配しうる) ため、 marker 行を golden として pin する。
FOLIO_BIN="$SCRIPT_DIR/../../bin/folio"
oracle_root() { # $1 = root dir, $2 = constitution html source
  local r="$1"; mkdir -p "$r/spec" "$r/decisions" "$r/research"
  cp "$2" "$r/spec/constitution.html"
  # scannable な非 constitution doc (これが無いと cluster が empty 扱いになり dead-end 経路へ到達しない)。
  # ★dc:references で constitution を指す: 除外が効いていれば reverse 不要 ([OK] broken-reverse)、
  #   効いていなければ constitution 側に dc:isReferencedBy が無いので [FAIL] broken-reverse に倒れる
  #   (= bin/folio:436 folio_is_scan_target の除外を *正負 2 値* で観測する第 2 の oracle)。
  cat > "$r/spec/dummy.html" <<'HTML'
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8">
<meta name="folio-doc-type" content="spec"><meta name="folio-status" content="draft"><meta name="folio-version" content="0.1.0">
<title>dummy</title>
<script type="application/ld+json">
{"@context":{"dc":"http://purl.org/dc/terms/"},"@id":"./dummy.html","@type":"schema:TechArticle","dc:title":"dummy","dc:references":[{"@id":"./constitution.html"}]}
</script>
</head><body><p>dummy</p></body></html>
HTML
  # dead-end README (自 cluster 外への <a href> を 1 本も持たない = cluster-reachability 違反 1 本)。
  printf '<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><title>spec README</title></head><body><h1>spec</h1><a href="./dummy.html">dummy</a></body></html>\n' > "$r/spec/README.html"
}
oracle_marker() { # $1 = root dir, $2 = gate 名 → その gate の marker 行を stdout
  ( cd "$1/.." && bash "$FOLIO_BIN" validate --root "$1" 2>&1 ) | grep -E "\[(OK|FAIL|WARN|SKIP)\] $2\$" | head -1 | sed 's/^ *//'
}
rm -rf "$TMP/oroot" "$TMP/oroot_mut"
oracle_root "$TMP/oroot" "$TMP/base.html"
# mutant = 生成物の @type だけを schema:TechArticle へ倒した shadow (self-root 検出が false になる)。
cp "$TMP/base.html" "$TMP/base-nonconst.html"
perl -0777 -i -pe 's#"\@type": "FolioConstitution"#"\@type": "schema:TechArticle"#' "$TMP/base-nonconst.html"
oracle_root "$TMP/oroot_mut" "$TMP/base-nonconst.html"
or_self="$(oracle_marker "$TMP/oroot" cluster-reachability)"
or_mut="$(oracle_marker "$TMP/oroot_mut" cluster-reachability)"
if [[ "$or_self" == "[FAIL] cluster-reachability" && "$or_mut" == "[WARN] cluster-reachability" ]]; then
  ok "OR1 ★陽性 oracle: 生成物が self-root と判定され reachability が WARN でなく FAIL へ倒れる (@type が実際に読まれている)"
else
  ng "OR1 ★陽性 oracle 逸脱 (期待 self='[FAIL] cluster-reachability' / mut='[WARN] cluster-reachability'、 実 self='$or_self' / mut='$or_mut')"
fi
# OR2 は単独では vacuous ゆえ ★必ず OR1 と対で報告する (JSON-LD 未読でも同じ結果になるため)。
or_inv="$( cd "$TMP/oroot/.." && bash "$FOLIO_BIN" inventory --root "$TMP/oroot" >/dev/null 2>&1; jq -r '[.specs[]."@id"] | join(",")' "$TMP/inventory.json" 2>/dev/null )"
if [[ "$or_inv" == "spec/dummy.html" ]]; then
  ok "OR2 ★inventory が constitution の entry を作らない (scan 除外・OR1 と対でのみ有意)"
else
  ng "OR2 ★inventory 除外 逸脱 (期待 'spec/dummy.html' / 実 '$or_inv')"
fi
# OR3 ★第 2 の陽性/陰性対照 (bin/folio:436 folio_is_scan_target)。 dummy.html が dc:references で constitution を
#   指しているため、 除外が効いていれば reverse 不要で [OK] broken-reverse、 効かなければ constitution 側に
#   dc:isReferencedBy が無いので [FAIL] broken-reverse。 OR1 (nav_is_self_root = 正の検出) とは *別の* code site を
#   観測するので、 2 本で「除外 4 site のうち 2 site」+「正の検出 1 site」が実際に @type を読んでいることを示す。
or_rev_self="$(oracle_marker "$TMP/oroot" broken-reverse)"
or_rev_mut="$(oracle_marker "$TMP/oroot_mut" broken-reverse)"
if [[ "$or_rev_self" == "[OK] broken-reverse" && "$or_rev_mut" == "[FAIL] broken-reverse" ]]; then
  ok "OR3 ★folio_is_scan_target の除外が 2 値で観測される (self=[OK] / @type flip=[FAIL] broken-reverse)"
else
  ng "OR3 ★scan-target 除外 逸脱 (期待 self='[OK] broken-reverse' / mut='[FAIL] broken-reverse'、 実 self='$or_rev_self' / mut='$or_rev_mut')"
fi

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
cp "$TMP/base-filled.html" "$TMP/r7p2.html"; perl -0777 -i -pe 's{</body>}{<div data-component="adr-option-card">foreign dc(捏造)</div></body>}' "$TMP/r7p2.html"
cp "$TMP/base-filled.html" "$TMP/r7p3.html"; perl -0777 -i -pe 's{</body>}{<span class="tier-always">偽の tier バッジ(捏造)</span></body>}' "$TMP/r7p3.html"
cp "$TMP/base-filled.html" "$TMP/r7p4.html"; perl -0777 -i -pe 's{</body>}{<div class="lab">偽(捏造)</div></body>}' "$TMP/r7p4.html"
cp "$TMP/base-filled.html" "$TMP/r7p5.html"; perl -0777 -i -pe 's{</body>}{<p style="display:none">隠蔽(捏造)</p></body>}' "$TMP/r7p5.html"

# === 数値文字参照 decode 変種 red pin (folio-5u3k・reason-gated) ===
# lib/verify-common.sh の decode widen (大文字 &#X / semicolon-less hex / semicolon-less decimal) が
# entity 偽装 class を可視 token へ decode し **占有検査** が捕捉することを pin する。
# 素の rc!=0 pin は novelty scan (class-token 機械的網羅) が decode 幅と無関係に suite を赤くするため
# green-before-and-after で masking される — 占有側の FAIL 行 ([FAIL] + label) を対で掴む (c5r.2 基準)。
# mutation-kill: 該当 helper の widen だけ narrow へ戻すと novelty (L44 decode 済) も占有も静か
# = verify PASS に転じて本 pin が赤くなる (selftest-folio-5u3k が unit 単位で全 4 site を kill)。
u3k_entity_pin() { # label decoy_html expected_fail_substring
  cp "$TMP/base.html" "$TMP/u3k.html"
  DECOY="$2" perl -0777 -i -pe 's{</h1>}{"</h1>" . $ENV{DECOY}}e' "$TMP/u3k.html"
  local out rc; out="$(bash "$VER" "$BASE" "$TMP/u3k.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (verify PASS = entity 偽装 class が素通り)"; return; fi
  if grep -F -- "$3" <<<"$out" | grep -q '\[FAIL\]'; then ok "$1"; else ng "$1 (FAIL は別理由 = 占有 decode 不発が novelty に masking されている)"; fi
}
u3k_entity_pin "U3K1 ★大文字 16進 entity class (&#X77;ho → who) を占有 vcount who が decode 捕捉" '<span class="&#X77;ho">x</span>' 'vcount who'
u3k_entity_pin "U3K2 ★semicolon-less 16進 entity class (&#x77ho → who) を占有 vcount who が decode 捕捉" '<span class="&#x77ho">x</span>' 'vcount who'
u3k_entity_pin "U3K3 ★semicolon-less 10進 entity class (&#119ho → who) を占有 vcount who が decode 捕捉" '<span class="&#119ho">x</span>' 'vcount who'

echo
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
# ===== census-count blocking arm conformance seed (folio-jmmk): 来歴部品件数の source DOM 静的照合 =====
# 空 data-component タグ注入で件数 +1 (excess) にし census-count arm が [FAIL] census-count: principle-amendment-history で
# blocking 捕捉することを固定。 am-meta 順序値 chk は Σ|amended_by| 基数を守るが amended principle *数* (= history block 数) を
# 守る第 1 層が無い = census-count arm が唯一 anchor (sweep 分類表 folio-3d23【B2 占有pin sweep 成果物】)。 帰属 [FAIL] 行は
# census-count arm を外した mutant で消え = mutation-kill (占有 pin de-scope 後の継承先 aliveness 固定)。
cc_seed() { # label token
  perl -0777 -pe 's{</h1>}{"</h1><span data-component=\"'"$2"'\"></span>"}e if !$d++' "$TMP/base-filled.html" > "$TMP/ccseed-$2.html"
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/ccseed-$2.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F '[FAIL]' | grep -qF "census-count: $2"; then ok "$1"
  else ng "$1 (exit=$rc / [FAIL] census-count: $2 不発火)"; fi
}
cc_seed "CC-amend ★空 principle-amendment-history 追加 (来歴 block 数不一致) を census-count arm が捕捉" principle-amendment-history

if repro_pins "$VER" principle "$BASE" "$BASE_PROSE" "$ASM" "$INJ" --filled "$BASE_PROSE"; then ok "repro-build conformance (a-d) 全 pass"; else ng "repro-build conformance (a-d) 逸脱"; fi
echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
