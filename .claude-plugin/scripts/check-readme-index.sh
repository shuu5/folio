#!/usr/bin/env bash
# .claude-plugin/scripts/check-readme-index.sh
# PostToolUse hook: 新規作成 .html file が同 cluster の README.html index に
# 掲載されているか check し、 未掲載なら staleness を通知する。
#
# Phase X3 試作 minimum (Step 4、 ADR-0003 §2.1「PostToolUse: README update」の試作 slice):
#   - 挙動の型 = option (a) 最小 check 型 (notify、 file 改変なし)。 ADR §2.1/§2.2 の
#     「README index 自動更新」(mutate) は完成形目標で、 試作 slice は staleness 検出に留める
#     (jsonld-lint / path-boundary と同じ check 型で一貫、 副作用ゼロ)。
#   - scope = S1 (README.html を持つ任意 cluster)。 cluster dir に README.html が
#     あり、 新 .html (README 自身を除く) が未掲載なら notify。 index を持たない
#     cluster は対象外 (allow)。
#   - 掲載判定は basename の substring 一致 (試作 minimum)。 §2 inventory table 限定の
#     厳密検査は HTML parse が必要で minimal に反するため見送り (check-jsonld-lint.sh が
#     「単一 block 前提」を試作限界とするのと同方針)。 substring 一致は短い名が長い名に
#     部分一致する false-negative (staleness 見逃し) を許容する (完成形で table-scoped 化)。
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input.{file_path, content})
# stdout: 無音
# stderr: 未掲載時に reason を出力
# exit: 0 = allow, 2 = staleness 通知 (PostToolUse なので tool は実行済、 user 通知用)
#
# 失敗時は fail-closed (jq 不在 / tool_name 空 → exit 2)。
#
# cwd 前提: 相対 file_path は cwd 基準で解決する (実機 Claude Code は file_path を絶対化
#   するため非依存。 sandbox runner は REPO_ROOT を cwd として実行する想定)。
#
# 共通ロジックは plugin-lib.sh に集約 (Phase 3 DRY refactor)。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

folio_require_jq "README index check"

tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')

# tool_name 空 → fail-closed、 Write 以外は対象外として通過
folio_require_write_tool "$tool_name"

# .html 以外通過
folio_is_html "$file_path" || exit 0

base=$(basename "$file_path")
cluster_dir=$(dirname "$file_path")
readme="${cluster_dir}/README.html"

# README.html 自身の Write は index 対象外 (self 参照を強制しない)
[[ "$base" == "README.html" ]] && exit 0

# cluster に index (README.html) が無ければ対象外として通過
[[ -f "$readme" ]] || exit 0

# basename が README に掲載済か判定 (substring 一致、 試作 minimum)。
# grep の exit を区別する: 0 = 掲載済 (allow) / 1 = 未掲載 (staleness 通知) / 2+ = read error。
# README は上の [[ -f ]] で存在確認済だが、 権限等で読めない場合 grep は 2 を返す。 その際は
# 「未掲載」と誤認させず read error として fail-closed deny する (-F 固定文字列なので 2 は
# 正規表現エラーでなく file アクセス失敗を意味する)。
# grep 自身の stderr (例 "Permission denied") は抑制し、 下の制御 message に一本化する。
grep -qF "$base" "$readme" 2>/dev/null
rc=$?
case "$rc" in
  0) exit 0 ;;   # 掲載済 → 通過
  1) : ;;        # 未掲載 → 下の folio_deny へ falls through
  *) folio_deny \
       "folio README index check: cannot read cluster index (fail-closed)" \
       "  index: ${readme}" \
       "  reference: scratch/specs/README.html §2 (cluster index)" ;;
esac

folio_deny \
  "folio README index check: new file not listed in cluster index" \
  "  file: ${file_path}" \
  "  index: ${readme}" \
  "  fix: add an entry for '${base}' to the §2 File Inventory table in ${readme}" \
  "  reference: scratch/specs/README.html §2 (cluster index), scratch/specs/relations.html §4 (inventory)"
