#!/usr/bin/env bash
# verify-asset-sync.sh — 配信 root に置いた静的 asset copy ≡ 源泉 の byte 同期 gate (folio-wg2l E)
#
# 生成 canonical page のうち外部 stylesheet を <link> 参照するもの (glossary-pack) は、 配信 root
# (= page の親 dir) に asset の実体が要る。 folio-wg2l Leg 0 ① は option 1 (design-intent/srs.css へ
# 配置・pack の href 無改変) を採ったが、 **放置された copy は源泉から drift する** — それは単なる
# 重複でなく実害を生む: render-gate は配信 root の copy を読んで contrast/幾何を検査するため、
# copy が stale だと「古い token で緑」という vacuous-green を作り、 WCAG token drift クラスを
# 再生産する (Leg 0 ① が同期 gate の併設を必須とした理由)。
#
# 本 gate は登録された (copy, 源泉) 対を **whole-file byte 比較** する。 意味判定なし = 機械側。
#
# ★fail-closed 設計:
#   - REGISTRY が分類の SSoT (default-block)。 対の追加は登録 = 明示批准を要する。
#   - copy / 源泉 のいずれか不在は exit 2 (構成エラー・PASS/skip 化しない)。
#   - 空 file は byte 一致が vacuous に成立するため precondition で弾く (下限サイズ)。
#   - exit は計算済み決定トークン ($fail) のみから導出する。
#
# usage: verify-asset-sync.sh [--repo-root <dir>]
#   --repo-root は対の解決 base。 既定 = generator の 3 つ上 (repo root)。 敵対テストが本 gate 自身を
#   mutation-kill するための注入点 (verify-glossary-parity.sh と同 idiom)。
# exit: 0 = 全対 byte 一致 / 1 = drift / 2 = 構成エラー (対の不在・precondition 崩れ・未知引数)
#
# 設計主体: folio-wg2l worker cell (Leg A)。 ci.yml の deterministic floor へ配線済
# (verify-canonical-drift.sh / verify-glossary-parity.sh と同格)。 配線しない限り gate は inert で
# 再発防止にならない (ci.yml canonical-drift step の Leg B 要件と同じ doctrine) ため、 gate 本体・検出力 MK
# (test-adversarial-asset-sync.sh)・CI 配線の 3 点を同一 diff で land させる。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || { echo "verify-asset-sync: --repo-root に引数が無い" >&2; exit 2; }; REPO_ROOT="$2"; shift 2 ;;
    *) echo "verify-asset-sync: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

# ===== REGISTRY (配信 copy → 源泉・default-block) =====
# 書式: <repo-root 相対の copy>|<repo-root 相対の源泉>|<理由/注記>
# 新しい配信 copy を足すときはここへ登録する (未登録の copy は本 gate の被覆外 = 黙って drift する)。
REGISTRY='
design-intent/srs.css|.claude-plugin/design-system/srs.css|glossary-pack が <link rel="stylesheet" href="srs.css"> で外部参照する配信 root の実体 (folio-wg2l Leg 0 ① option 1)。 render-gate は配信 root の copy を読むため stale だと古い token で緑になる (WCAG token drift の再生産)
'

fail=0
pfail() { printf '  [FAIL] %s\n' "$1"; fail=1; }

echo "== asset sync gate (配信 copy ≡ 源泉 の byte 同期・folio-wg2l E) =="

n_pair=0
while IFS='|' read -r copy src note; do
  [[ -z "$copy" || "$copy" == \#* ]] && continue
  cpath="$REPO_ROOT/$copy"
  spath="$REPO_ROOT/$src"
  # 不在は exit 2 (構成エラー): 「対が無いから緑」を作らない
  [[ -f "$cpath" ]] || { echo "verify-asset-sync: 配信 copy 不在: $cpath" >&2; exit 2; }
  [[ -f "$spath" ]] || { echo "verify-asset-sync: 源泉 不在: $spath" >&2; exit 2; }
  # precondition: 空 file 同士は byte 一致が vacuous に成立する (両方空 = 「同期済」と報告してしまう)
  csz="$(wc -c < "$cpath")"; ssz="$(wc -c < "$spath")"
  if [[ "$ssz" -lt 100 || "$csz" -lt 100 ]]; then
    echo "verify-asset-sync: 対のサイズが下限 100 byte 未満 (copy=${csz} / 源泉=${ssz}) — vacuous な byte 一致を許さない: $copy" >&2
    exit 2
  fi
  n_pair=$((n_pair+1))
  if cmp -s "$cpath" "$spath"; then
    printf '  [OK]   %s == %s (%s byte)\n' "$copy" "$src" "$csz"
  else
    pfail "asset-sync-drift: $copy が源泉 $src と byte 不一致 (配信 copy は生成物: 源泉を編集して \`cp $src $copy\` で再同期し同一 commit で land する)"
    diff <(od -c "$spath") <(od -c "$cpath") 2>/dev/null | head -6 | while IFS= read -r dl; do printf '         %s\n' "$dl"; done
  fi
done <<< "$REGISTRY"

# 登録 0 本 = 検査の蒸発 (REGISTRY を空にすれば緑になる恒真 PASS 経路) を封鎖する
if [[ "$n_pair" -eq 0 ]]; then
  echo "verify-asset-sync: 登録対が 0 本 (REGISTRY の蒸発 = 恒真 PASS)" >&2
  exit 2
fi

echo ""
if [[ "$fail" == "0" ]]; then
  echo "RESULT: asset-sync PASS (${n_pair} 対・配信 copy == 源泉 の whole-file byte 一致)"
  exit 0
else
  echo "RESULT: FAIL"
  exit 1
fi
