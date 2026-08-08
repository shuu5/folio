#!/usr/bin/env bash
# test-adversarial-self-spec-drift.sh — folio-mkwc (8dkl self-spec flip) drift gate (verify-self-spec-drift.sh)
# の敵対回帰テスト。 姉妹 gate の test-adversarial-rules-drift.sh / test-adversarial-relations-drift.sh と
# 対称に、 committed な per-shape mutation-kill を repo へ pin し gate の ★非 vacuous 性 (fail-closed の
# genuineness) を守る。
#
# gate 自体の正しさを検査する:
#   (a) precision: healthy canonical → exit 0 PASS (clean corpus を誤検出しない)。
#   (b) ★物理指紋段 per-shape MK: fingerprint ★6 clause を各 1 mutant で ★独立 に撃つ。
#       1 instance (旧 canonical 全体) の実弾は構造差のある clause の穴を証明しない — per-shape 原則
#       (jyfh / r8k)。 各 clause の rot (assert 削除・selector rot) を FAIL 行の ★clause 固有メッセージ で pin。
#       これが旧 hand-authored shape (common.css <link> / 手書き章立て / build 未通過 land) を DONE 不可化する砦。
#   (c) drift 段 MK: 物理指紋を保ったまま本文 byte を改竄 → byte-drift FAIL (指紋段でなく比較段で落ちる)。
#       指紋段を通過してもなお silent prose drift を捕まえることを、 指紋メッセージ ★不在 も併せて pin。
#   (d) ★inline CSS (style payload) MK: floor が撃てない面 を本 gate が撃つことの ★実証。
#       in-scan flip では repro-build arm が SKIP_REPRO=1 必須 (folio-z7ba・ci.yml) ゆえ style payload の
#       改竄は floor の占有 pin にも census にも当たらない — ★本 gate だけがここを守る (契約 D6 の名指し要求)。
#   (e) ★過 strict でない negative control: 生成 timestamp ★だけ の差替は PASS のまま (normalize が
#       効いていることの陽性対照)。 これが無いと「常に赤い gate」でも (b)-(d) が全部緑に見える。
#   (f) exit-code 規約: 未知引数 → exit 2 (0/1/2 の分離)。
#
# fixture は healthy canonical から hermetic に合成する (git-rev 非依存・commit 増加 / history rewrite に不変)。
# FAIL 系 pin は ★FAIL 行にしか出ない clause 固有値 で確認する (c5r.2 基準・恒真 grep 回避)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-self-spec-drift.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CANON="$ROOT/design-intent/spec/folio-self-spec.html"
[[ -x "$GATE" ]]  || { echo "FATAL: gate not executable: $GATE" >&2; exit 2; }
[[ -f "$CANON" ]] || { echo "FATAL: canonical not found: $CANON" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad() { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

# --canon override を食わせ、 非零 exit かつ FAIL 行が clause 固有 substring を含むことを pin
expect_fp_fail() { # $1=label $2=canon-fixture $3=clause 固有 substring
  local out rc; out="$("$GATE" --canon "$2" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF -- "$3" <<<"$out"; then ok "$1"
  else bad "$1 (rc=$rc / clause substring '$3' の FAIL 行なし)"; fi
}
# ★mutation が ★実際に当たった ことを byte 差で確認してから撃つ (空撃ちの sed / perl を PASS と読まない)。
mutated() { # $1=fixture
  if cmp -s "$CANON" "$1"; then return 1; fi
  return 0
}

echo "== self-spec drift gate 敵対回帰 (folio-mkwc・8dkl flip) =="

# --- H0 precision: healthy canonical → exit 0 + PASS 行 (clean corpus を誤検出しない) ---
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -qF 'PASS: design-intent/spec/folio-self-spec.html == fresh 再生成' <<<"$out"; then
  ok "H0 precision: healthy canonical → exit 0 + PASS pin"
else bad "H0 precision: healthy が exit0 PASS でない (rc=$rc)"; fi

# --- MK1 fingerprint clause(1): inline <style> 欠 → 物理指紋 FAIL ---
# 生成 pack は自己完結 inline <style>。 行頭 <style> を潰すと clause(1) が genuine に落ちることを pin。
perl -pe 's{^<style>}{<style-rotted>}' "$CANON" > "$WORK/mk1.html"
if mutated "$WORK/mk1.html"; then
  expect_fp_fail "MK1 clause(1): 行頭 <style> 消失 → 物理指紋 FAIL" "$WORK/mk1.html" \
    '物理指紋(1): inline <style> block が無い'
else bad "MK1 mutation が空撃ち"; fi

# --- MK2 fingerprint clause(2): 行頭 <link> stylesheet 出現 → 物理指紋 FAIL ---
# 旧 hand-authored canonical の共通署名 (head col-0 の <link href="../../common.css">) を再注入。
# <style> は温存するため clause(1) を通過し、 clause(2) が genuine に落ちる。
perl -pe 'print "<link rel=\"stylesheet\" href=\"../../common.css\">\n" if $. == 3' "$CANON" > "$WORK/mk2.html"
if mutated "$WORK/mk2.html"; then
  expect_fp_fail "MK2 clause(2): 行頭 <link> 再注入 (旧 common.css shape) → 物理指紋 FAIL" "$WORK/mk2.html" \
    '物理指紋(2): 行頭 <link> 要素を検出'
else bad "MK2 mutation が空撃ち"; fi

# --- MK3 fingerprint clause(3): generator meta の self-spec fork 署名 rot → 物理指紋 FAIL ---
# ★consumer chrome 述語 (folio_chrome_is_generated_spec) の検出鍵でもある literal。 別 pack の産物 /
# 手書き原本を canonical に据える形を指紋段で落とす。
perl -0pe 's{<meta name="generator" content="folio spec-pack assembler — self-spec fork}{<meta name="generator" content="folio hand-authored page}' \
  "$CANON" > "$WORK/mk3.html"
if mutated "$WORK/mk3.html"; then
  expect_fp_fail "MK3 clause(3): generator meta の self-spec fork 署名 rot → 物理指紋 FAIL" "$WORK/mk3.html" \
    '物理指紋(3): generator meta の self-spec fork 署名が無い'
else bad "MK3 mutation が空撃ち"; fi

# --- MK4 fingerprint clause(4): machine-fold shape rot → 物理指紋 FAIL ---
# qojv 決定 3 の機械層 trailing-fold は生成物固有 shape。 手書き原本の details/summary 形へ退行させる代理。
perl -0pe 's{class="machine-fold"}{class="machine-fold-rotted"}g' "$CANON" > "$WORK/mk4.html"
if mutated "$WORK/mk4.html"; then
  expect_fp_fail "MK4 clause(4): class=\"machine-fold\" token rot → 物理指紋 FAIL" "$WORK/mk4.html" \
    '物理指紋(4): class="machine-fold" 不在'
else bad "MK4 mutation が空撃ち"; fi

# --- MK5 fingerprint clause(5): 章 anchor (s0-reader-guide) 消失 → 物理指紋 FAIL ---
perl -0pe 's{id="s0-reader-guide"}{id="S0-READER-GUIDE"}g' "$CANON" > "$WORK/mk5.html"
if mutated "$WORK/mk5.html"; then
  expect_fp_fail "MK5 clause(5): section anchor id=\"s0-reader-guide\" 消失 → 物理指紋 FAIL" "$WORK/mk5.html" \
    '物理指紋(5): section anchor id="s0-reader-guide" 不在'
else bad "MK5 mutation が空撃ち"; fi

# --- MK6 fingerprint clause(6): chrome marker 消失 (folio build 未通過の land) → 物理指紋 FAIL ---
# 生成物を build を通さずそのまま canonical へ置く形 (chrome 欠落 land) を指紋段で落とすことの実弾。
perl -0pe 's{^<!-- folio:chrome-bottom -->$}{<!-- folio-chrome-bottom-rotted -->}m' "$CANON" > "$WORK/mk6.html"
if mutated "$WORK/mk6.html"; then
  expect_fp_fail "MK6 clause(6): chrome marker 消失 (build 未通過 land) → 物理指紋 FAIL" "$WORK/mk6.html" \
    '物理指紋(6): chrome marker <!-- folio:chrome-bottom --> 不在'
else bad "MK6 mutation が空撃ち"; fi

# --- MK7 drift 段: 物理指紋を保った ★本文 byte 改竄 → byte-drift FAIL (指紋段でない) ---
# 6 clause を全て温存しつつ本文にコメントを注入。 指紋段を通過してなお fresh 再生成との byte 差を捕捉すること、
# かつ 指紋メッセージ ★不在 を pin。
perl -0pe 's{</body>}{<!-- DRIFT-GATE-MK-SABOTAGE --></body>}' "$CANON" > "$WORK/mk7.html"
if mutated "$WORK/mk7.html"; then
  out="$("$GATE" --canon "$WORK/mk7.html" 2>&1)"; rc=$?
  # positive anchor は drift FAIL 分岐 唯一の固有トークン 'byte 不一致' の fixed-string 単独 (c5r.2 anchor 規律)。
  # 'drift' は fail() prefix 'verify-self-spec-drift:' で全行恒真ゆえ使わない。
  if [[ "$rc" -ne 0 ]] && grep -qF 'byte 不一致' <<<"$out" && ! grep -qF '物理指紋' <<<"$out"; then
    ok "MK7 drift: 指紋保持で本文 byte 改竄 → byte-drift FAIL (指紋段でない)"
  else bad "MK7 drift: byte-drift を捕捉せず or 指紋段で誤発火 (rc=$rc)"; fi
else bad "MK7 mutation が空撃ち"; fi

# --- MK8 ★inline CSS (style payload) 1 byte 改変 → byte-drift FAIL ---
# ★契約 D6 の名指し要求: repro-build arm が in-scan flip で SKIP_REPRO=1 必須 (folio-z7ba) ゆえ、
#   style payload は floor の占有 pin にも census にも当たらず ★素通る。 本 gate だけが撃てることの実証。
#   ★<style> block 内の CSS 宣言値を 1 文字だけ変える (指紋 6 clause は全て無傷 = 比較段で落ちる)。
python3 - "$CANON" "$WORK/mk8.html" <<'PYMK8'
import sys, re
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^<style>(.*?)^</style>', src, re.S | re.M)
assert m, 'MK8: inline <style> block が見つからない (fixture 前提の崩れ)'
head, css, tail = src[:m.start(1)], m.group(1), src[m.end(1):]
old = 'letter-spacing:.22em;'
assert css.count(old) >= 1, ('MK8: CSS anchor が無い', css.count(old))
css = css.replace(old, 'letter-spacing:.23em;', 1)   # ★1 byte 相当の宣言値変更 (CSS 内に閉じる)
open(sys.argv[2], 'w', encoding='utf-8').write(head + css + tail)
PYMK8
if mutated "$WORK/mk8.html"; then
  out="$("$GATE" --canon "$WORK/mk8.html" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF 'byte 不一致' <<<"$out" && ! grep -qF '物理指紋' <<<"$out"; then
    ok "MK8 style payload: inline CSS 宣言値を 1 byte 改変 → byte-drift FAIL (floor 素通り面の被覆証明・D6)"
  else bad "MK8 style payload: inline CSS 改変が素通り (rc=$rc = A1 の穴が塞がっていない)"; fi
else bad "MK8 mutation が空撃ち (CSS anchor が当たっていない)"; fi

# --- MK9 ★過 strict でない negative control: 生成 timestamp ★だけ の差替は PASS のまま ---
# normalize が「footer の 生成: <b>TS</b>」に厳密 scope して効いていることの陽性対照。 これが無いと
# 「常に赤い gate」でも MK1-MK8 が全部緑に見える (FAIL 系だけを並べた suite の空洞化)。
perl -pe 's{生成: <b>\d{4}-\d{2}-\d{2} \d{2}:\d{2}</b>}{生成: <b>1999-12-31 23:59</b>}g' "$CANON" > "$WORK/mk9.html"
if mutated "$WORK/mk9.html"; then
  out="$("$GATE" --canon "$WORK/mk9.html" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qF 'PASS: design-intent/spec/folio-self-spec.html == fresh 再生成' <<<"$out"; then
    ok "MK9 negative control: 生成 timestamp のみ差替 → PASS 維持 (normalize が過 strict でない)"
  else bad "MK9 negative control: timestamp 差替で赤くなった (rc=$rc = normalize が効いていない / gate が恒真 FAIL)"; fi
else bad "MK9 mutation が空撃ち (footer timestamp の形が想定外)"; fi

# --- MK10 exit-code 規約: 未知引数 → exit 2 ---
"$GATE" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "MK10 startup: 未知引数 → exit 2"
else bad "MK10 startup: 未知引数が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  self-spec-drift 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
