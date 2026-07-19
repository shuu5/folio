#!/usr/bin/env bash
# test-adversarial-rules-drift.sh — folio-d7bq F8 drift gate (verify-rules-drift.sh)
# の敵対回帰テスト。 姉妹 gate の test-adversarial-verification-drift.sh と対称に、 committed な
# per-shape mutation-kill を repo へ pin し gate の非 vacuous 性 (fail-closed の genuineness) を守る。
#
# gate 自体の正しさを検査する:
#   (a) precision: healthy canonical → exit 0 PASS (clean corpus を誤検出しない)。
#   (b) 物理指紋段 per-shape MK: fingerprint 4 clause を各 1 mutant で *独立* に撃つ。
#       1 instance (旧 canonical 全体) の実弾は構造差のある clause の穴を証明しない — per-shape 原則
#       (jyfh/r8k)。 各 clause の rot (assert 削除・selector rot) を FAIL 行の clause 固有メッセージで pin。
#       これが旧 hand-authored shape (common.css <link>・details.spec-row・hand-authored anchor) を DONE 不可化する砦。
#   (c) drift 段 MK: 物理指紋を保ったまま本文 byte を改竄 → byte-drift FAIL (指紋段でなく比較段で落ちる)。
#       指紋段を通過してもなお silent prose drift を捕まえることを、 指紋メッセージ *不在* も併せて pin。
#   (d) exit-code 規約: 未知引数 → exit 2 (0/1/2 の分離)。
#
# fixture は healthy canonical から hermetic に合成する (git-rev 非依存・commit 増加/history rewrite に不変)。
# FAIL 系 pin は FAIL 行にしか出ない clause 固有値で確認する (c5r.2 基準・恒真 grep 回避)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-rules-drift.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CANON="$ROOT/design-intent/spec/rules.html"
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

echo "== rules drift gate 敵対回帰 (F8・folio-d7bq) =="

# --- H0 precision: healthy canonical → exit 0 + PASS 行 (clean corpus を誤検出しない) ---
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -qF 'PASS: design-intent/spec/rules.html == fresh 再生成' <<<"$out"; then
  ok "H0 precision: healthy canonical → exit 0 + PASS pin"
else bad "H0 precision: healthy が exit0 PASS でない (rc=$rc)"; fi

# --- MK1 fingerprint clause(1): inline <style> 欠 → 物理指紋 FAIL ---
# 生成 pack は自己完結 inline <style>。 行頭 <style> を潰すと clause(1) が genuine に落ちることを pin。
perl -pe 's{^<style>}{<style-rotted>}' "$CANON" > "$WORK/mk1.html"
expect_fp_fail "MK1 clause(1): 行頭 <style> 消失 → 物理指紋 FAIL" "$WORK/mk1.html" \
  '物理指紋: inline <style> block が無い'

# --- MK2 fingerprint clause(2): 行頭 <link> stylesheet 出現 → 物理指紋 FAIL ---
# 旧 hand-authored canonical の共通署名 (head col-0 の <link href="../../common.css">) を再注入。
# <style> は温存するため clause(1) を通過し、 clause(2) が genuine に落ちる。
perl -pe 'print "<link rel=\"stylesheet\" href=\"../../common.css\">\n" if $. == 3' "$CANON" > "$WORK/mk2.html"
expect_fp_fail "MK2 clause(2): 行頭 <link> 再注入 (旧 common.css shape) → 物理指紋 FAIL" "$WORK/mk2.html" \
  '物理指紋: 行頭 <link> 要素を検出'

# --- MK3 fingerprint clause(3): ears-requirement-row shape rot → 物理指紋 FAIL ---
# 生成物の要件 row token を潰す (旧 details.spec-row shape へ退行させる代理)。 selector rot を pin。
perl -pe 's/data-component="ears-requirement-row"/data-component="ears-requirement-row-rotted"/g' "$CANON" > "$WORK/mk3.html"
expect_fp_fail "MK3 clause(3): ears-requirement-row token rot → 物理指紋 FAIL" "$WORK/mk3.html" \
  '物理指紋: data-component="ears-requirement-row" 不在'

# --- MK4 fingerprint clause(4): rules anchor (req-*/section s*) 消失 → 物理指紋 FAIL ---
# rules は req-ver 0 本ゆえ指紋(4)は「req-(ci|cm|da|gloss|xref|adr)-* もしくは section s*-*」の OR。
# 旧 hand-authored 大文字 id 署名へ退行させ両 grep を落とす (OR ゆえ両方 rot が必要)。
perl -pe 's/id="req-(ci|cm|da|gloss|xref|adr)-/id="REQ-$1-/g; s/id="s([0-9])/id="S$1/g' "$CANON" > "$WORK/mk4.html"
expect_fp_fail "MK4 clause(4): rules anchor (req-*/section s*) 消失 → 物理指紋 FAIL" "$WORK/mk4.html" \
  '物理指紋: rules anchor'

# --- MK5 drift 段: 物理指紋を保った本文 byte 改竄 → byte-drift FAIL (指紋段でない) ---
# 4 clause を全て温存 (<style>/no <link>/ears-row/rules anchor) しつつ本文にコメントを注入。
# 指紋段を通過してなお fresh 再生成との byte 差を捕捉すること、 かつ 指紋メッセージ *不在* を pin。
perl -0pe 's{</body>}{<!-- DRIFT-GATE-MK-SABOTAGE --></body>}' "$CANON" > "$WORK/mk5.html"
out="$("$GATE" --canon "$WORK/mk5.html" 2>&1)"; rc=$?
# positive anchor は drift FAIL 分岐 (verify-rules-drift.sh:138) 唯一の固有トークン 'byte 不一致' の
# fixed-string 単独 (c5r.2 anchor 規律)。'drift' は fail() prefix 'verify-rules-drift:' で全行恒真ゆえ使わない。
if [[ "$rc" -ne 0 ]] && grep -qF 'byte 不一致' <<<"$out" && ! grep -qF '物理指紋' <<<"$out"; then
  ok "MK5 drift: 指紋保持で本文 byte 改竄 → byte-drift FAIL (指紋段でない)"
else bad "MK5 drift: byte-drift を捕捉せず or 指紋段で誤発火 (rc=$rc)"; fi

# --- MK6 exit-code 規約: 未知引数 → exit 2 ---
"$GATE" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "MK6 startup: 未知引数 → exit 2"
else bad "MK6 startup: 未知引数が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  rules-drift 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
