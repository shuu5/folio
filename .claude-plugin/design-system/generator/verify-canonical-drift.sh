#!/usr/bin/env bash
# verify-canonical-drift.sh — out-of-scan generated-canonical drift gate (folio-u7oc / instance#1 = vision)
#
# design-intent/ 配下には generator パイプラインの生成物でありながら inventory node でない
# (= folio validate の gate(m) nav-regen-drift の被覆外) out-of-scan canonical がある。
# 例: design-intent/vision.html は curated 導線のみで inventory に載らないが、実体は
# assemble-vision.sh + inject-prose.sh の full-pipeline 生成物。ソース (contract/prose/srs.css) が
# 更新されても canonical が silent に取り残される drift が起こりうる (10 日 silent drift の再発防止)。
#
# 本 gate は「canonical == fresh(full-pipeline 再生成)」を *生成 timestamp 正規化後* に byte 比較し、
# 差分が 1 byte でもあれば fail-closed で FAIL する。nav-regen-drift の out-of-scan 版。
#
# fail-closed 原則 (恒真 PASS/skip 化を全面禁止):
#   - 6 入力 (assemble/inject/contract/prose/canonical/srs.css) は絶対 path + [[ -f ]] 存在ガード。
#     いずれか不在は即 exit 非零 (PASS/skip 化しない)。
#   - fresh は毎回新規 mktemp へ full-pipeline 出力 (stale/前回残骸/cp canonical の pre-seed 禁止)。
#   - 再生成 precondition: assemble exit 0 / inject exit 0 / fresh 非空 / 構造マーカー を順に assert。
#     「再生成できなかった」は FAIL (skip も恒真 PASS も禁止)。
#   - 比較右辺は full pipeline 固定 (assemble 単発は footer「prose 未充填」差で常時 false-drift)。
#   - timestamp normalize は footer「生成: <b>YYYY-MM-DD HH:MM</b>」に厳密 scope。裸日付の全域置換や
#     行単位削除はしない (content date / SSoT 名 / 検証状態 / tags を潰さない)。
#
# repo-root は cwd 非依存で確定 (TOOLERR-as-PASS 封鎖): script-relative を primary とし、
# git rev-parse --show-toplevel と一致すれば追認 (不一致でも script-relative を採用・git 外でも動く)。
#
# usage: verify-canonical-drift.sh
#   exit 0   = PASS (canonical == fresh, normalize 後 byte 一致)
#   exit 非零 = FAIL (drift 検出 or 前提崩れ) — 理由 (drift した値を含む) を stderr へ
#
# 設計主体: folio-u7oc worker cell。CI 配線は admin Leg B (本 script は ci.yml を触らない)。

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

fail() { echo "verify-canonical-drift: FAIL: $*" >&2; exit 1; }

# ---- repo-root を cwd 非依存で確定 (script-relative primary) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# generator → design-system → .claude-plugin → repo-root (3 つ上)
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# git rev-parse と一致すれば追認 (git 外/失敗でも script-relative を採用)
if GIT_TOP="$(cd "$ROOT" && git rev-parse --show-toplevel 2>/dev/null)"; then
  [[ "$GIT_TOP" == "$ROOT" ]] || echo "verify-canonical-drift: warn: git-top($GIT_TOP) != script-relative($ROOT); script-relative を採用" >&2
fi

GEN="$ROOT/.claude-plugin/design-system/generator"
ASSEMBLE="$GEN/assemble-vision.sh"
INJECT="$GEN/inject-prose.sh"
CONTRACT="$GEN/contract/folio-vision.vision.yaml"
PROSE="$GEN/prose/folio-vision.prose.yaml"
CANON="$ROOT/design-intent/vision.html"
CSS="$ROOT/.claude-plugin/design-system/srs.css"

# ---- 6 入力を絶対 path + 存在ガード (不在は即 FAIL・skip 化厳禁) ----
for f in "$ASSEMBLE" "$INJECT" "$CONTRACT" "$PROSE" "$CANON" "$CSS"; do
  [[ -f "$f" ]] || fail "入力不在 (存在ガード): $f"
done

# ---- normalize: footer「生成: <b>TS</b>」の timestamp 部分文字列だけを固定トークンへ ----
# 接頭辞「生成: <b>」+ YYYY-MM-DD HH:MM +「</b>」に厳密 scope。他の裸日付 (版日付/承認/起票) は
# この prefix を持たないので不変。同一 footer 行の SSoT 名・検証状態・tags も不変。
normalize() {
  perl -pe 's{生成: <b>\d{4}-\d{2}-\d{2} \d{2}:\d{2}</b>}{生成: <b>\@\@CANONICAL-DRIFT-GATE-TS\@\@</b>}g'
}

# ---- fresh を新規 mktemp へ full-pipeline 生成 (stale/pre-seed 禁止) ----
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
"$ASSEMBLE" "$CONTRACT" "$WORK/assembled.html" >/dev/null 2>"$WORK/aerr" \
  || fail "assemble 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/aerr")"
"$INJECT" "$PROSE" "$WORK/assembled.html" "$WORK/fresh.html" >/dev/null 2>"$WORK/ierr" \
  || fail "inject 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/ierr")"

# ---- 再生成 precondition (fail-closed) ----
[[ -s "$WORK/fresh.html" ]] || fail "fresh 空 (再生成不能)"
head -1 "$WORK/fresh.html" | grep -qi '<!DOCTYPE html>' || fail "fresh に DOCTYPE 無し (構造マーカー欠如)"
grep -q 'data-component="fidelity-sync-meta"' "$WORK/fresh.html" \
  || fail "fresh に構造マーカー data-component=\"fidelity-sync-meta\" 無し"
# 下限サイズ (space-only の恒真化を弾く・canonical 実測 ~58KB の半分を floor)
fsz="$(wc -c < "$WORK/fresh.html")"
[[ "$fsz" -ge 20000 ]] || fail "fresh サイズ $fsz < 下限 20000 (再生成崩れ)"

# ---- normalize 後 byte 比較 (1 byte drift でも FAIL) ----
normalize < "$CANON"        > "$WORK/canon.norm"
normalize < "$WORK/fresh.html" > "$WORK/fresh.norm"
if ! diff -q "$WORK/canon.norm" "$WORK/fresh.norm" >/dev/null; then
  {
    echo "verify-canonical-drift: FAIL: design-intent/vision.html が fresh 再生成と drift (生成 timestamp 正規化後も byte 不一致):"
    echo "--- 差分 (< canonical / > fresh, 先頭 60 行) ---"
    diff "$WORK/canon.norm" "$WORK/fresh.norm" | head -60
  } >&2
  exit 1
fi

echo "verify-canonical-drift: PASS: design-intent/vision.html == fresh 再生成 (assemble-vision + inject-prose full pipeline・生成 timestamp 正規化後 byte 一致)"
