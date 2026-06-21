#!/usr/bin/env bash
# .claude-plugin/scripts/check-content-boundary.sh
# PreToolUse hook (tier-2 content gate): spec_path 配下の spec を編集する際、 本文に platform 固有
# HOW (P-11 4-primitive) を裸書きしていないか content 境界を検査し、 検出時に advisory を出す。
# engine 設計 §4 (HOW を外側へ・enforcement は 3-tier) の tier-2 = PreToolUse 編集 gate (shaping)。
# B5-III 実装 (engine doc §10 論点⑥)。
#
# ★advisory (非ブロッキング)= shaping であり guarantee ではない:
#   §4 tier-3 (CI floor ∧ ceiling) が唯一の guarantee。 hook は vim 直編集・opt-in・コストで保証に
#   ならないため、 本 gate は編集を deny せず (exit 0)、 検出を stderr に advisory として出すに留める
#   (staged rollout = soft-warn。 §10⑤: 実測後に新 ADR で CI hard gate 化)。 authoritative な検出は
#   tier-3 = bin/folio validate gate (r) HOW-outside content gate (B5-II)。 本 gate と tier-3 は
#   plugin-lib.sh folio_how_primitive_scan / folio_mask_prose を共用し検出が一致する (advisory ⊆ guarantee)。
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input.{file_path, content})
# stdout: 無音
# stderr: HOW-outside primitive 検出時に advisory を出力 (clean なら無音)
# exit: 0 = allow (常に。 advisory = 非ブロッキング)、 2 = tool error (jq 欠落 / payload 不正、 fail-closed)
#
# 判定:
#   - Write tool のみ (Edit は new_string 部分編集ゆえ全文 content を持たず本 gate の射程外。 path-boundary と対称)
#   - file_path が .html
#   - file_path が spec_path (既定 architecture/spec/) 配下 (= WHAT domain。 decisions/research は一次資料層で対象外)
#   - content を folio_mask_prose で prose 化 → folio_how_primitive_scan で P-11 4-primitive 検出
#   → 検出あり: advisory を stderr に出して exit 0 (非ブロッキング shaping)
#   → 検出なし: 無音 exit 0
#
# 環境変数:
#   FOLIO_SPEC_PATH  既定 "architecture/spec/"
#
# 共通ロジックは plugin-lib.sh に集約 (path-boundary / jsonld-lint と同型の DRY)。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

SPEC_PATH=$(folio_spec_path)

payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

folio_require_jq "content boundary check"

tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')
content=$(folio_json_field "$payload" '.tool_input.content // empty')

# tool_name 空 → fail-closed、 Write 以外は対象外として通過 (path-boundary / jsonld-lint と同基準)
folio_require_write_tool "$tool_name"

# .html 以外 / spec_path 配下でない (= WHAT domain でない) は対象外
folio_is_html "$file_path" || exit 0
folio_under_spec_path "$file_path" "$SPEC_PATH" || exit 0

# prose mask (code/pre/chrome/aside 除去) → 残存 tag を space 化 → P-11 4-primitive 検出 (tier-3 floor-2 と同一手順)
text=$(folio_mask_prose "$content" | sed -E 's/<[^>]+>/ /g')
findings=$(folio_how_primitive_scan "$text" | LC_ALL=C sort -u)

# 検出なし = 無音通過
[[ -z "$findings" ]] && exit 0

# advisory (非ブロッキング): 検出を stderr に出して exit 0。 deny しない (tier-2 = shaping)。
{
  echo "folio content-boundary (advisory): spec 本文に platform 固有 HOW (P-11 primitive) を検出 (engine §4 tier-2 / P-11)"
  echo "  file: ${file_path}"
  printf '%s\n' "$findings" | while IFS=$'\t' read -r cat tok; do
    [[ -z "$cat" || -z "$tok" ]] && continue
    echo "  - P-11 primitive (${cat}): \"${tok}\" — design-intent 本文に HOW を埋めず implementation harness / AI-agent instruction file へ隔離し照会リンクで繋ぐ"
  done
  echo "  note: advisory (非ブロッキング)。 authoritative gate = folio validate gate (r) how-outside (CI floor)。"
} >&2
exit 0
