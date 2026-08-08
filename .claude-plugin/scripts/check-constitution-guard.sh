#!/usr/bin/env bash
# .claude-plugin/scripts/check-constitution-guard.sh
# PreToolUse hook: canonical constitution (head JSON-LD の @type == FolioConstitution) への
# tool 層直接編集 (Edit / Write / NotebookEdit) を deny する。
# folio-qojv 決定 7 (ii) の実装 (cell = folio-v6tv、 8dkl wave)。
#
# stdin: Claude Code 提供 hook JSON payload (tool_name + tool_input)
# stdout: 無音
# stderr: deny 時に reason を出力
# exit: 0 = allow, 2 = deny (REQ-VER-006: exit code 中心 assertion)
#
# === tier: 本 hook は tier-2 shaping であり guarantee ではない =================
# 覆うのは tool 層 (PreToolUse matcher = Edit|Write|NotebookEdit) の直接編集のみ。 bash 経路
# (generator pipeline = assemble-principle → inject-prose → verify-principle、 手打ちの sed / perl 等)
# は PreToolUse に到達しないため構造的に対象外 = 設計上の既知非対称である。 したがって
# **authoritative gate は CI / drift gate** (landed canonical == fresh 再生成の byte 束縛) であり、
# 本 hook はそこへ至る前の shaping (誤爆的な直接編集を正規路へ寄せる) に限る。 本 script が緑でも
# 「改竄封鎖済」 「機械 guard で保証」 とは主張できない。
#
# === 述語: on-disk head JSON-LD の @type ======================================
# 判定は file 名でも path 単独でもなく、 **実 file の head JSON-LD の @type == FolioConstitution**。
# bin/folio が 5 site で使う既存判別子 (folio_build_entry / folio_is_scan_target /
# folio_nav_is_self_root / validate loop / chrome self 判定) と同一基準を再利用し、 新述語を発明しない。
# ゆえに consumer の conforming constitution (@type schema:TechArticle) は同名 constitution.html でも
# allow され、 file 不在 (greenfield materialize) も allow される。
# 抽出 idiom は bin/folio folio_extract_head_jsonld と同形 (SSoT = bin/folio。 plugin-lib.sh は本 cell の
# 成果物集合外ゆえ共有関数化せず同形コピーを置く。 drift 時は bin/folio が SSoT)。
# payload の tool_input.content には依存しない — 実機の Edit payload は content を持たないため。
#
# === allow escape を持たない ==================================================
# marker env / marker file / flag による allow 分岐は **意図的に実装しない**。 agent が自己発行できる
# token を gate の前提にすると caller-marker より弱い gate になるため。 正規の編集経路は
# contract YAML → generator pipeline であって 「marker を立ててから .html を直接書く」 ではない。
#
# === 過渡期ハザード (flip 前) ================================================
# folio-pa93 の flip が land するまで、 landed canonical (design-intent/spec/constitution.html) は
# **手書きの SSoT** であり generator pipeline の出力とは byte 一致しない (実測: pipeline 出力 88,339 bytes
# vs landed 22,748 bytes・landed に meta generator 0 hit)。 かつ landed 内容を束縛する CI gate は未存在。
# したがって deny を受けた agent が 「再生成すればよい」 と読んで pipeline 出力で canonical を上書きすると、
# 手書き SSoT を破壊する。 deny message は再生成の正規路を案内すると同時に、 **flip 前の上書き禁止** を
# 明示する (deny hint の warn 行)。 上書きの可否判断は flip cell (folio-pa93) の user 承認事項である。
#
# === fail 方針 ================================================================
# jq 不在は deny (fail-closed、 既存 hook 3 本と同方針)。 head JSON-LD 不在 / parse 不能 / @type 不一致は
# allow (constitution であることを積極的に示せない file を tier-2 shaping で塞がない)。
# 空 payload / 空 tool_name / file_path 欠落も allow — check-caller-marker.sh の現行挙動 (空 tool_name を
# case *) で allow) に合わせた非対称であり、 fail-closed なのは jq 依存欠落だけである点を明記しておく
# (path-boundary / jsonld-lint が使う folio_require_write_tool の 空→deny とは意図的に非一貫)。
# 実機 NotebookEdit の payload key は notebook_path であり本 script は file_path のみを読むため、
# NotebookEdit 経路は実質 allow になる (.ipynb は constitution canonical に到達しないため実害なし)。
#
# 環境変数:
#   FOLIO_SPEC_PATH  既定 "design-intent/spec/" — 前提条件 (spec_path 配下のみ検査)。 素朴 prefix 一致は
#                    使わず plugin-lib.sh の folio_under_spec_path (相対 + 絶対の 2 branch) を使う。
#                    fixture tree (tests/fixtures/**/spec/constitution.html) の編集を巻き込まないための
#                    scope 限定であり、 決定 7 (iii) 「適用範囲は constitution 限定」 と整合する。

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh" \
  || { echo "folio: cannot load plugin-lib.sh (fail-closed)" >&2; exit 2; }

SPEC_PATH=$(folio_spec_path)

# --- head JSON-LD 抽出 (bin/folio folio_extract_head_jsonld と同形) ---
# </head> より前の <script type="application/ld+json"> block の中身を stdout に返す。
constitution_guard_head_jsonld() {
  awk '
    /<\/head>/ { exit }
    capturing && /<\/script>/ { exit }
    capturing { print }
    /<script[^>]*type="application\/ld\+json"/ { capturing = 1 }
  ' "$1" 2>/dev/null
}

# stdin payload (空文字許容 = direct test invocation)
payload=$(folio_read_payload)
[[ -z "$payload" ]] && exit 0

# tool_name / file_path 抽出 (jq 必須、 fail-closed)
folio_require_jq "constitution guard"
tool_name=$(folio_json_field "$payload" '.tool_name // empty')
file_path=$(folio_json_field "$payload" '.tool_input.file_path // empty')

# matcher 外の tool は通過 (hooks.json matcher で絞り込み済の想定だが念のため)
case "$tool_name" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

# 前提条件: spec_path 配下でない file は対象外 (fixture tree 等を巻き込まない)
[[ -z "$file_path" ]] && exit 0
folio_under_spec_path "$file_path" "$SPEC_PATH" || exit 0

# file 不在 = greenfield materialize → allow (陰性対照)
[[ -f "$file_path" ]] || exit 0

# 述語: on-disk head JSON-LD の @type
block=$(constitution_guard_head_jsonld "$file_path")
[[ -z "$block" ]] && exit 0
doc_type=$(printf '%s' "$block" | jq -r '."@type" // empty' 2>/dev/null)
[[ "$doc_type" == "FolioConstitution" ]] || exit 0

folio_deny \
  "folio constitution guard: direct tool-layer edit of the canonical constitution is denied" \
  "  file: ${file_path}" \
  "  reason: head JSON-LD @type == FolioConstitution (canonical of principle-pack、 名前非依存の判別)" \
  "  hint: 編集起点は contract YAML (.claude-plugin/design-system/generator/contract/folio-constitution.principle.yaml)" \
  "  hint: 再生成の正規路は generator pipeline (assemble-principle → inject-prose → verify-principle)" \
  "  warn: flip (folio-pa93) 前は canonical が手書き SSoT である — deny を再生成で回避して canonical を上書きしない (上書き判断は flip cell の user 承認事項)" \
  "  note: 本 hook は tier-2 shaping であり guarantee ではない — authoritative gate は CI / drift gate (bash 経路は覆わない)" \
  "  reference: folio-qojv 決定 7 (ii) / design-intent/spec/constitution.html は P-10 の改正手続きに従う"
