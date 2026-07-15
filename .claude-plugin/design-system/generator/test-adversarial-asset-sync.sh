#!/usr/bin/env bash
# test-adversarial-asset-sync.sh — verify-asset-sync.sh 自身の検出力 floor-proof (folio-wg2l E)
#
# 配信 root の静的 asset copy (design-intent/srs.css) ≡ 源泉 (.claude-plugin/design-system/srs.css) の
# byte 同期 gate が、 「何も見ずに緑を返す」実装へ退行していないことを mutation-kill で実証する。
# pure bash + cmp (render 非依存) ゆえ CI deterministic floor 適格。 exit 0 = 全 pass / 非 0 = fail-closed。
#
# ★本 suite の存在理由 (folio-wg2l self-review round2 finding#1/#3/#4/#5): gate の検出力実弾は当初 worker の
#   untracked な local self-test (S11a/S11b) にしか無く、 worktree 撤去で呼出点ごと消える = gate 本体だけが
#   tree に残り誰も検出力を保証しない状態だった。 姉妹 gate の確立慣習
#   (verify-glossary-parity.sh ↔ test-adversarial-glossary-parity.sh) どおり tracked + CI 配線する。
#
#   P1  無改竄の実 repo → PASS (肯定実証: 現に両 copy が同期している)
#   MK1 配信 copy を 1 byte drift → rc=1 + asset-sync-drift (本 gate の主目的)
#   MK2 源泉側を 1 byte drift → rc=1 (向きに依らず検出する = 片側だけ見る実装の封鎖)
#   MK3 配信 copy 不在 → rc=2 (「対が無いから緑」の封鎖)
#   MK4 源泉 不在 → rc=2 (同上)
#   MK5 両方を空 file 化 → rc=2 (空==空 の vacuous な byte 一致の封鎖)
#   MK6 REGISTRY 蒸発 (登録 0 本) → rc=2 (検査そのものの蒸発 = 恒真 PASS 経路の封鎖)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/verify-asset-sync.sh"
REPO="$(cd "$HERE/../../.." && pwd)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }

# 実 repo と同じ相対 layout の mini-repo を建てる (gate は --repo-root で対を解決する)
mk_repo() {
  local d="$1"
  mkdir -p "$d/design-intent" "$d/.claude-plugin/design-system"
  cp "$REPO/design-intent/srs.css" "$d/design-intent/srs.css"
  cp "$REPO/.claude-plugin/design-system/srs.css" "$d/.claude-plugin/design-system/srs.css"
}

echo "== test-adversarial-asset-sync (verify-asset-sync.sh の検出力 floor-proof) =="

# ---- P1: 無改竄の実 repo → PASS ----------------------------------------------
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'RESULT: asset-sync PASS' <<<"$out"; then
  ok "P1 無改竄の実 repo: design-intent/srs.css == design-system/srs.css (gate PASS)"
else
  bad "P1 実 repo で asset-sync gate が FAIL (rc=$rc) — 放置 copy = WCAG token drift クラスの再生産: $out"
fi

# ---- MK1: 配信 copy を 1 byte drift → rc=1 ------------------------------------
D="$WORK/mk1"; mk_repo "$D"
printf '/*QZX*/' >> "$D/design-intent/srs.css"
out="$("$GATE" --repo-root "$D" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'asset-sync-drift' <<<"$out"; then
  ok "MK1 配信 copy の 1 byte drift → rc=1 + asset-sync-drift"
else
  bad "MK1 gate が配信 copy の drift を検出しない (rc=$rc = 恒真 PASS): $out"
fi

# ---- MK2: 源泉側を 1 byte drift → rc=1 (向き非依存) ---------------------------
D="$WORK/mk2"; mk_repo "$D"
printf '/*QZX*/' >> "$D/.claude-plugin/design-system/srs.css"
out="$("$GATE" --repo-root "$D" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'asset-sync-drift' <<<"$out"; then
  ok "MK2 源泉側の 1 byte drift → rc=1 (片側だけ見る実装なら割れる)"
else
  bad "MK2 gate が源泉側の drift を検出しない (rc=$rc): $out"
fi

# ---- MK3: 配信 copy 不在 → rc=2 -----------------------------------------------
D="$WORK/mk3"; mk_repo "$D"; rm -f "$D/design-intent/srs.css"
out="$("$GATE" --repo-root "$D" 2>&1)"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '配信 copy 不在' <<<"$out"; then
  ok "MK3 配信 copy 不在 → rc=2 (「対が無いから緑」を作らない)"
else
  bad "MK3 配信 copy 不在が構成エラーにならない (rc=$rc): $out"
fi

# ---- MK4: 源泉 不在 → rc=2 -----------------------------------------------------
D="$WORK/mk4"; mk_repo "$D"; rm -f "$D/.claude-plugin/design-system/srs.css"
out="$("$GATE" --repo-root "$D" 2>&1)"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '源泉 不在' <<<"$out"; then
  ok "MK4 源泉 不在 → rc=2"
else
  bad "MK4 源泉 不在が構成エラーにならない (rc=$rc): $out"
fi

# ---- MK5: 両方 空 file → rc=2 (vacuous な byte 一致の封鎖) --------------------
D="$WORK/mk5"; mk_repo "$D"
: > "$D/design-intent/srs.css"; : > "$D/.claude-plugin/design-system/srs.css"
out="$("$GATE" --repo-root "$D" 2>&1)"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -q '下限 100 byte 未満' <<<"$out"; then
  ok "MK5 両方 空 file → rc=2 (空==空 の vacuous な一致を PASS にしない)"
else
  bad "MK5 空 file 同士が vacuous に PASS する (rc=$rc): $out"
fi

# ---- MK6: REGISTRY 蒸発 → rc=2 -------------------------------------------------
# gate 本体を mutation して「登録対 0 本」にしたコピーを走らせる (検査そのものの蒸発 = 恒真 PASS 経路)
D="$WORK/mk6"; mk_repo "$D"
MUT="$WORK/verify-asset-sync.mutant.sh"
perl -0pe "s/^REGISTRY='\n.*?\n'\$/REGISTRY='\n'/ms" "$GATE" > "$MUT"
chmod +x "$MUT"
if grep -qE '^design-intent/srs\.css\|' "$MUT"; then
  bad "MK6 setup: REGISTRY の蒸発 mutation が未適用 (MK 空撃ち)"
else
  out="$("$MUT" --repo-root "$D" 2>&1)"; rc=$?
  if [[ "$rc" -eq 2 ]] && grep -q 'REGISTRY の蒸発' <<<"$out"; then
    ok "MK6 REGISTRY 蒸発 (登録 0 本) → rc=2 (検査の蒸発を恒真 PASS にしない)"
  else
    bad "MK6 REGISTRY を空にすると gate が緑を返す (rc=$rc): $out"
  fi
fi

echo ""
echo "test-adversarial-asset-sync: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
