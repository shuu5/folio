#!/usr/bin/env bash
# folio srs-ceiling-oracle — fixture builder (dev-time・folio-mzn.1.5 S11)。
#
# 目的: ceiling (LLM ensemble) の differential oracle 用に、golden (清浄) + 欠陥注入 3 種の
# 生成 SRS プレゼン fixture を決定的に組む。欠陥は全て **prose slot の意味層** に注入する —
# floor (verify-srs) は構造・件数・逐語 (contract 由来 text) しか見ないため全 fixture が
# floor PASS になり、欠陥の検出責務が ceiling (gate I/J/K) だけに載る = ceiling 版 test-adversarial。
#
# 欠陥 3 種 (bd folio-mzn.1.5 DESCRIPTION の 3 class に対応):
#   fab-rationale : 捏造 rationale — contract に無い承認事実・挙動を rationale-FR2 に主張 (gate J fidelity)
#   vacuous-plain : 欠落 slot の意味版 — plain-FR1 を非空だが意味的に空の文へ (gate K completeness / gate I)
#   omission-lead : 意味的 omission — 機能要件章 lead (chapter-lead-04) を FR1 のみ被覆へ縮退 (gate K / gate J)
#
# 期待 verdict の SSoT は expected.json (本 script と同 dir)。
# usage: build-fixtures.sh <outdir>
# exit: 0 = 全 fixture 生成 + 静的 floor (SRS_SKIP_RENDER) PASS 確認済 / 1 = fail

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${1:?usage: build-fixtures.sh <outdir>}"
CONTRACT="$GEN/contract/ec-checkout.srs.yaml"
PROSE="$GEN/prose/ec-checkout.prose.yaml"
mkdir -p "$OUT"

echo "=== srs-ceiling-oracle fixtures を build ($OUT) ==="
bash "$GEN/assemble-srs.sh" "$CONTRACT" "$OUT/.asm.html" >/dev/null 2>&1 || { echo "assemble 失敗" >&2; exit 1; }

# ★manifest-backed fixture (構造不変条件・folio-3d23 ceiling round-3 で HTML 直接 mutate shim から転換):
#   欠陥は prose manifest (YAML) 側へ注入し、fixture は必ず「自分の manifest から assemble+inject で
#   決定的に再 build 可能」に保つ。これにより repro-build arm (REQ-VER-030・prose-sensitive) を
#   全 consumer (本 builder / workflow.js runtime / prose-conduit の /folio-verify) が既定 ON のまま
#   正直に通る — SKIP_REPRO はどの consumer にも不要 (「opus が悪い prose を書いた生成物」の忠実な模擬)。
#   検証時の prose 解決は REPRO_PROSE=<outdir>/<fixture>.prose.yaml (規約解決は原本 manifest を掴むため)。
# 置換文は (a) 非空 (gate G prose 充填) (b) placeholder トークン (TBD/未定/要確認 等) を含まない
# (c) 計数部品・contract 由来逐語に触れない — の 3 条件で floor 透過を保つ。
mutate_manifest() { # $1=fixture名 $2=slot-id $3=新テキスト
  [[ "$(SLOT="$2" yq '.slots | has(strenv(SLOT))' "$PROSE")" == "true" ]] \
    || { echo "mutate_manifest $1: slot $2 が原本 manifest に不在" >&2; exit 1; }
  SLOT="$2" NEWTEXT="$3" yq '.slots[strenv(SLOT)] = strenv(NEWTEXT)' "$PROSE" > "$OUT/$1.prose.yaml" \
    || { echo "mutate_manifest $1 失敗" >&2; exit 1; }
  # fail-closed: 置換が実際に成立し原本と異なる値であること (0 置換の silent 素通り防止)
  [[ "$(SLOT="$2" yq -r '.slots[strenv(SLOT)]' "$OUT/$1.prose.yaml")" == "$3" ]] \
    || { echo "mutate_manifest $1: slot $2 置換不成立" >&2; exit 1; }
  [[ "$(SLOT="$2" yq -r '.slots[strenv(SLOT)]' "$PROSE")" != "$3" ]] \
    || { echo "mutate_manifest $1: 原本と同一値 (欠陥注入になっていない)" >&2; exit 1; }
  bash "$GEN/inject-prose.sh" "$OUT/$1.prose.yaml" "$OUT/.asm.html" "$OUT/$1.html" >/dev/null 2>&1 \
    || { echo "inject ($1) 失敗" >&2; exit 1; }
}

# 0. golden — 清浄: 原本 manifest のまま (manifest copy を同梱し 4 fixture の解決手順を統一)。
cp "$PROSE" "$OUT/golden.prose.yaml"
bash "$GEN/inject-prose.sh" "$OUT/golden.prose.yaml" "$OUT/.asm.html" "$OUT/golden.html" >/dev/null 2>&1 || { echo "inject 失敗" >&2; exit 1; }

# 1. fab-rationale — 捏造: FR2 (二重課金防止) の rationale に contract に無い承認事実と挙動を主張。
mutate_manifest "fab-rationale" "rationale-FR2" \
  "本要件は 2025 年 3 月の取締役会で全会一致により正式承認済みです。また決済が失敗した場合もシステムが自動的に後払い決済へ切り替えるため、注文は必ず成立します。"

# 2. vacuous-plain — 意味的に空: FR1 の平易説明を「説明になっていない非空文」へ。
mutate_manifest "vacuous-plain" "plain-FR1" \
  "この要件は本システムにおける要件のひとつであり、定義されたとおりに動作することを定めるものです。"

# 3. omission-lead — 意味カバレッジ欠落: 機能要件章 (FR1〜FR6) の lead を FR1 だけの章と主張。
mutate_manifest "omission-lead" "chapter-lead-04" \
  "この章では在庫の確保についてだけ定めます。注文確定時に商品の在庫を押さえること、それがこの章の唯一の内容です。"
rm -f "$OUT/.asm.html"

# 静的 floor 透過の fail-closed 確認 (render は oracle 実行時に full floor で担保)。repro-build arm は
# 既定 ON のまま各 fixture 自身の manifest (REPRO_PROSE) で通す = manifest-backed 不変条件の実地検証を兼ねる。
fail=0
for f in golden fab-rationale vacuous-plain omission-lead; do
  if REPRO_PROSE="$OUT/$f.prose.yaml" SRS_SKIP_RENDER=1 bash "$GEN/verify-srs.sh" "$CONTRACT" "$OUT/$f.html" >/dev/null 2>&1; then
    echo "  [OK]   $f.html — 静的 floor PASS (欠陥は ceiling の領分に載っている)"
  else
    echo "  [FAIL] $f.html — 静的 floor FAIL (欠陥注入が floor に漏れた/壊した)"; fail=1
  fi
done
[[ "$fail" -eq 0 ]] && echo "RESULT: fixtures 4 本 生成完了 (期待 verdict は expected.json)" || echo "RESULT: fixture 生成 FAIL"
exit "$fail"
