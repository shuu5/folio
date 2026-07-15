#!/usr/bin/env bash
# switchover-harness.sh — folio spec の staging→flip 切替機構 (folio-nnqh / folio-8dkl Phase 1)
#
# folio 自身の canonical spec を「手書き」から「機械 SSoT 生成」へ flip する際の安全網。 flip は
# canonical HTML を破壊的に置換するため、 置換前に staging (別 dir) で full validate/build を回し
# 「grade が落ちない・graph から脱落しない」ことを fail-closed で確かめてから land する。 Phase 2
# (folio-tco6 系 flip cell) が本 harness を前提に land する順序制約 (本 bead が tco6 を blocks)。
#
# 設計原則:
#   - **canonical 非汚染**: 全 validate/build は staging(mktemp)配下の --root にのみ実行。 canonical
#     (worktree 実体の design-intent/) への build は index.html 上書き = 汚染ゆえ sh_assert_staging_root
#     で abort する。
#   - **staging = git archive HEAD**: tracked 全体 (repo-root の CLAUDE.md/common.css/README.md/tests/
#     群 + sibling .claude-plugin/design-system/generator) を materialize する。 design-intent + sibling
#     generator だけの bare copy は README.html の ../../CLAUDE.md 参照が link-rot し validate exit 1
#     (実測)・gate (s) spec-contract-pairing が silent SKIP になる (採不可)。 .git/.worktrees は
#     git archive が構造排除する。
#   - **--root は design-intent 空間を直接指す**: bin/folio の scan base は design-intent 直下 (spec/
#     decisions/ research/)。 staging では <staging>/design-intent を --root に渡すと in-place と同一の
#     全[OK]・files/relations 数を再現する (実測: 59/568・exit 0)。 gate (s) は <root>/../.claude-plugin
#     /design-system/generator の実在で発火するため、 sibling generator を欠く staging では gate 行が
#     完全消失する (bin/folio 2256-2261: contract_seen=0 は [SKIP] すら出さず行を出さない)。
#
# 本 file は **sourceable な純関数ライブラリ + 薄い CLI dispatch** の 2 層。 selftest-folio-nnqh.local.sh
# と test-graph-emit.sh は本 file を source して sh_* 関数を直接 unit-test する。 FAIL トークンは全て
# 'SWH-*-FAIL' prefix で、 folio validate 出力・[OK] 行には決して現れない FAIL 行専有トークン (pin の
# reason substring 判別力を担保・jyfh 恒真封鎖)。 gate の PASS/FAIL は計算済み決定トークン (return code)
# から導出し、 data 補間出力を grep して exit を導かない。
set -uo pipefail

SWH_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# bin/folio は .claude-plugin/bin/folio、 本 script は .claude-plugin/scripts/ = ../bin/folio。
FOLIO="${FOLIO:-$SWH_HERE/../bin/folio}"

# ============================================================================
# 純関数ライブラリ (sourceable)
# ============================================================================

# sh_stage_repo <src_worktree> <dest_dir>
#   worktree HEAD を git archive で dest へ materialize (tracked 全体・.git/.worktrees 構造排除)。
sh_stage_repo() {
  local src="$1" dest="$2"
  git -C "$src" archive HEAD | tar -x -C "$dest"
}

# sh_assert_staging_root <root_abs> <forbidden_worktree_abs>
#   canonical guard: build/validate の --root が worktree 実体配下なら abort (canonical 汚染防止)。
#   return 0 = staging として安全 / return 1 = canonical 実体を指しており危険。
sh_assert_staging_root() {
  local root="$1" fw="$2" rr fr
  rr="$(realpath -m -- "$root")"
  fr="$(realpath -m -- "$fw")"
  if [[ "$rr" == "$fr" || "$rr" == "$fr"/* ]]; then
    printf 'SWH-CANONICAL-GUARD abort: root %s が worktree %s 配下 (canonical 実体への build/validate = 汚染)\n' "$rr" "$fr" >&2
    return 1
  fi
  return 0
}

# sh_extract_gate_set <validate_out_file>
#   validate 出力から gate 行を "name<TAB>label" へ正規化 (先頭 2-space + 4 status 厳密一致)。
#   name = [STATUS] 直後〜末尾 parenthetical 手前、 label = OK/SKIP/WARN/FAIL。 LC_ALL=C sort -u で集合化。
sh_extract_gate_set() {
  awk '
    /^  \[(OK|SKIP|WARN|FAIL)\] / {
      label=$0; sub(/^  \[/,"",label); sub(/\].*/,"",label)
      name=$0;  sub(/^  \[(OK|SKIP|WARN|FAIL)\] /,"",name); sub(/ \(.*/,"",name)
      print name "\t" label
    }
  ' "$1" | LC_ALL=C sort -u
}

# sh_assert_gate_parity <baseline_validate_out> <staging_validate_out>
#   gate 名→label のキー付き集合を双方向 set-equality で突合。 gate 行の消失 (spec-contract-pairing の
#   contract_seen=0 完全消失) と label flip (OK->SKIP) を FAIL。 抽出集合が既知 gate 'internal
#   link-integrity' を含まない (regex ドリフト/空集合) 場合は PASS でなく FAIL (fail-closed・jyfh 恒真封鎖)。
#   return 0 = 一致 / return 1 = 不一致 or existence 破れ。
sh_assert_gate_parity() {
  local base_out="$1" stg_out="$2" base_set stg_set d
  base_set="$(sh_extract_gate_set "$base_out")"
  stg_set="$(sh_extract_gate_set "$stg_out")"
  # existence assert (fail-closed): baseline 集合が陽性対照 gate 名を含むこと。 空集合==空集合 の恒真 PASS を封鎖。
  if ! printf '%s\n' "$base_set" | cut -f1 | grep -qxF 'internal link-integrity'; then
    printf 'SWH-PARITY-FAIL existence: baseline gate 集合が陽性対照 gate '\''internal link-integrity'\'' を欠く (regex ドリフト/空集合・fail-closed)\n'
    return 1
  fi
  if d="$(diff <(printf '%s\n' "$base_set") <(printf '%s\n' "$stg_set"))"; then
    printf 'SWH-PARITY-OK gate 集合一致\n'
    return 0
  fi
  printf 'SWH-PARITY-FAIL gate-set-mismatch:\n%s\n' "$d"
  # baseline に在り staging で absent の gate 名を FAIL 行専有トークンで列挙 (reason substring 判別力)。
  comm -23 <(printf '%s\n' "$base_set") <(printf '%s\n' "$stg_set") | while IFS=$'\t' read -r n l; do
    [[ -z "$n" ]] && continue
    printf 'SWH-PARITY-FAIL missing-in-staging: %s (baseline=%s)\n' "$n" "$l"
  done
  return 1
}

# sh_extract_counts <validate_out_file>
#   "files checked: N · relations checked: M" → "N M" (無ければ何も出さない)。
sh_extract_counts() {
  sed -nE 's/^files checked: ([0-9]+) · relations checked: ([0-9]+).*/\1 \2/p' "$1" | head -1
}

# sh_assert_nondecreasing <base_out> <base_exit> <stg_out> <stg_exit>
#   staging の files/relations が baseline を下回らないこと。 baseline validate は exit 0 必須 (fail-closed)。
#   4 数値が全て抽出でき数値であることを先に assert し、 欠落/非数値は無条件 FAIL (空 skip 禁止)。
#   staging exit は別軸で捕捉 (info)。 return 0 = 非減少 / return 1 = 減少 or 抽出不能 or baseline dirty。
sh_assert_nondecreasing() {
  local base_out="$1" base_exit="$2" stg_out="$3" stg_exit="$4"
  if [[ "$base_exit" != "0" ]]; then
    printf 'SWH-NONDEC-FAIL baseline-dirty: baseline validate exit=%s (clean baseline 必須・count 読取前に gate)\n' "$base_exit"
    return 1
  fi
  local bc sc bf bfr sf sfr
  bc="$(sh_extract_counts "$base_out")"
  sc="$(sh_extract_counts "$stg_out")"
  bf="${bc%% *}"; bfr="${bc##* }"; sf="${sc%% *}"; sfr="${sc##* }"
  if ! [[ "$bf" =~ ^[0-9]+$ && "$bfr" =~ ^[0-9]+$ && "$sf" =~ ^[0-9]+$ && "$sfr" =~ ^[0-9]+$ ]]; then
    printf 'SWH-NONDEC-FAIL nonnumeric: files/relations 数値抽出不能 (baseline='\''%s'\'' staging='\''%s'\''・fail-closed)\n' "$bc" "$sc"
    return 1
  fi
  local stg_note=""
  [[ "$stg_exit" != "0" ]] && stg_note=" [staging validate exit=$stg_exit]"
  if (( sf < bf )) || (( sfr < bfr )); then
    printf 'SWH-NONDEC-FAIL decrease: files %d->%d relations %d->%d (非減少 違反)%s\n' "$bf" "$sf" "$bfr" "$sfr" "$stg_note"
    return 1
  fi
  printf 'SWH-NONDEC-OK files %d>=%d relations %d>=%d%s\n' "$sf" "$bf" "$sfr" "$bfr" "$stg_note"
  return 0
}

# sh_head_graph_present <contract_yaml>
#   contract に head_graph block が実在するか (yq has)。 core_emit_graph_head の戻り値/出力に依存せず
#   contract を独立に読む (lib/common.sh:113 の || return 0 silent no-emit に defer しない)。
sh_head_graph_present() {
  [[ "$(yq -r 'has("head_graph")' "$1" 2>/dev/null)" == "true" ]]
}

# sh_is_exempt <landing_path> <spec_path_abs>
#   flip 着地先 realpath が spec_path 配下かで head_graph 要件の exempt を判定する単体述語。
#   spec_path 配下 = in-scan = not-exempt (return 1)、 配下でない = out-of-scan = exempt (return 0)。
#   realpath -m ゆえ不在 path (未生成の flip target) も決定的に解決。
sh_is_exempt() {
  local landing="$1" spec_abs="$2" lr sr
  lr="$(realpath -m -- "$landing")"
  sr="$(realpath -m -- "$spec_abs")"
  if [[ "$lr" == "$sr" || "$lr" == "$sr"/* ]]; then
    return 1   # spec_path 配下 = in-scan = not-exempt
  fi
  return 0     # 配下でない = out-of-scan = exempt
}

# sh_assert_head_graph_hardfail <contract_yaml> <landing_path> <spec_path_abs>
#   flip 対象 contract 1 本を独立評価: in-scan (not-exempt) かつ head_graph を欠けば FAIL。 out-of-scan は
#   exempt で PASS、 in-scan でも head_graph 実在なら PASS。 corpus 走査せず flip target 1 本に scope する
#   (grandfathered 既存 spec の head_graph 不在で false-RED しない)。 return 0 = 通過 / return 1 = hard-fail。
sh_assert_head_graph_hardfail() {
  local contract="$1" landing="$2" spec_abs="$3"
  if sh_is_exempt "$landing" "$spec_abs"; then
    printf 'SWH-HARDFAIL-OK exempt: 着地 %s は spec_path 配下でない (out-of-scan・head_graph 不要)\n' "$landing"
    return 0
  fi
  if sh_head_graph_present "$contract"; then
    printf 'SWH-HARDFAIL-OK present: %s に head_graph 実在 (in-scan flip 可)\n' "$contract"
    return 0
  fi
  printf 'SWH-HARDFAIL head_graph-missing: in-scan flip target %s (着地 %s) が head_graph を欠く (core_emit_graph_head silent no-emit = graph 脱落)\n' "$contract" "$landing"
  return 1
}

# sh_assert_golden_diff <dirA> <dirB> [<allowlist_ere>]
#   2 つの build 出力 dir を再帰 diff し、 allowlist_ere (timestamp 等の許容 diff・決定トークン) に
#   マッチする行を除外した残余を有限クラスへ分類し default-block 判定する (収集に留めず fail-closed gate 化)。
#   中立 = diff の構造行 (diff -r header / hunk 位置 / --- / 空行) のみ。content 行差 (^[<>] )・file-set 差
#   (^Only in )・binary 差 (^Binary files )・未知クラス (\ No newline 等) は全て FAIL — 有意形の
#   positive-enumeration は列挙外 shape を素通しする partial-enum trap ゆえ採らない。
#   allowlist は content 行 (^[<>] ) にのみ効かせ、 Only in / Binary 行は消さない (誤許容封鎖)。
#   allowlist ERE は使用前検証 + フィルタ grep の exit>=2 検査 (TOOLERR→PASS 封鎖)。
#   existence 前提: 両 dir 実在必須 (build 失敗で出力 dir 不在 = graph 脱落を素通しさせない)。 diff の
#   exit code も参照し 2(trouble・I/O エラー) は無条件 FAIL とし、 stderr テキストを success 誤読しない。
#   return 0 = 許容内 / return 1 = 残余 diff・file 増減・binary 差・dir 不在・diff エラー。
sh_assert_golden_diff() {
  local a="$1" b="$2" allow="${3:-}" d rc residual errf
  # existence assert (fail-closed): 両 dir 実在 (build 失敗で dir 不在 → PASS を封鎖)。
  if [[ ! -d "$a" || ! -d "$b" ]]; then
    printf 'SWH-GOLDEN-FAIL missing-dir: build 出力 dir 不在 (a=%s[%s] b=%s[%s]・fail-closed)\n' \
      "$a" "$([[ -d "$a" ]] && echo yes || echo no)" "$b" "$([[ -d "$b" ]] && echo yes || echo no)"
    return 1
  fi
  errf="$(mktemp)"
  d="$(diff -r "$a" "$b" 2>"$errf")"; rc=$?
  # diff exit: 0=一致 / 1=差分 / >1=trouble(I/O エラー等)。 trouble は無条件 FAIL (エラーの success 誤読封鎖)。
  if (( rc > 1 )); then
    printf 'SWH-GOLDEN-FAIL diff-error: diff -r が exit=%d で異常終了 (I/O エラー等・fail-closed): %s\n' "$rc" "$(cat "$errf")"
    rm -f "$errf"
    return 1
  fi
  rm -f "$errf"
  if (( rc == 0 )); then
    printf 'SWH-GOLDEN-OK build 出力完全一致\n'
    return 0
  fi
  # rc==1: 残余判定。 allowlist は content 行 (^[<>] ) にのみ効かせ、 file-set 差 / binary 差は消さない。
  # allowlist ERE は使用前に検証する (malformed ERE で grep が exit>=2 + 空 stdout になると残余が空に
  # 化けて PASS する TOOLERR→PASS を封鎖 = SWH-01)。空入力 grep は valid なら exit 1・malformed なら >=2。
  if [[ -n "$allow" ]]; then
    grep -E "($allow)" </dev/null >/dev/null 2>&1
    rc=$?
    if (( rc >= 2 )); then
      printf 'SWH-GOLDEN-FAIL allowlist-regex-error: allowlist ERE が不正 (検証 grep exit=%d・fail-closed): %s\n' "$rc" "$allow"
      return 1
    fi
    residual="$(printf '%s\n' "$d" | grep -vE "^[<>] .*($allow)")"
    rc=$?
    if (( rc >= 2 )); then
      printf 'SWH-GOLDEN-FAIL allowlist-filter-error: allowlist フィルタ grep が exit=%d で異常終了 (fail-closed)\n' "$rc"
      return 1
    fi
  else
    residual="$d"
  fi
  # 残余行を有限クラスへ分類する default-block (SWH-02 封鎖): 中立 = diff の構造行 (diff -r header /
  # hunk 位置 NcN 等 / separator --- / 空行) のみ。content(allowlist 非該当)・Only in・Binary files・
  # および未知クラス (\ No newline 等) は全て FAIL — 「有意な形」の positive-enumeration (旧 3 prefix)
  # は列挙外 shape を素通しする partial-enum trap ゆえ廃止 (mzn.1 default-block と同型)。
  local bad
  bad="$(printf '%s\n' "$residual" | grep -vE '^(diff -r |[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$|---$|$)')"
  rc=$?
  if (( rc >= 2 )); then
    printf 'SWH-GOLDEN-FAIL classify-error: 分類 grep が exit=%d で異常終了 (fail-closed)\n' "$rc"
    return 1
  fi
  if [[ -n "$bad" ]]; then
    printf 'SWH-GOLDEN-FAIL residual-diff (allowlist 除外後・default-block):\n%s\n' "$bad"
    return 1
  fi
  printf 'SWH-GOLDEN-OK allowlist 内 diff のみ (timestamp 等)\n'
  return 0
}

# sh_materialize_and_validate <worktree> <stage_parent_dir> <out_prefix> [drop_generator(0|1)]
#   staging を materialize し (drop_generator=1 で sibling generator を除去 = 欠陥 staging)、 canonical
#   guard を通し、 <staging>/design-intent を --root に validate 実行。 <out_prefix>.txt に validate 出力・
#   <out_prefix>.exit に validate exit code を書き、 staging の design-intent root を stdout に echo する。
#   guard 破れ (canonical 実体) は return 2 (task error)。
sh_materialize_and_validate() {
  local wt="$1" sp="$2" op="$3" drop="${4:-0}" stg root
  stg="$sp/stg"; mkdir -p "$stg"
  sh_stage_repo "$wt" "$stg"
  [[ "$drop" == "1" ]] && rm -rf "$stg/.claude-plugin/design-system/generator"
  root="$stg/design-intent"
  sh_assert_staging_root "$root" "$wt" || return 2
  "$FOLIO" validate --root "$root" > "$op.txt" 2>&1
  echo "$?" > "$op.exit"
  echo "$root"
}

# sh_materialize_and_build <worktree> <stage_parent_dir> [drop_generator(0|1)]
#   staging を materialize し canonical guard を通し build --root。 build した design-intent root を echo。
#   guard 破れは return 2。
sh_materialize_and_build() {
  local wt="$1" sp="$2" drop="${3:-0}" stg root
  stg="$sp/stg"; mkdir -p "$stg"
  sh_stage_repo "$wt" "$stg"
  [[ "$drop" == "1" ]] && rm -rf "$stg/.claude-plugin/design-system/generator"
  root="$stg/design-intent"
  sh_assert_staging_root "$root" "$wt" || return 2
  "$FOLIO" build --root "$root" >/dev/null 2>&1
  echo "$root"
}

# ============================================================================
# CLI dispatch (source 時は起動しない・Phase 2 flip cell / 手動確認用の薄い入口)
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    gate-parity)        sh_assert_gate_parity "$@" ;;
    gate-nondecreasing) sh_assert_nondecreasing "$@" ;;
    gate-head-graph)    sh_assert_head_graph_hardfail "$@" ;;
    gate-golden)        sh_assert_golden_diff "$@" ;;
    is-exempt)          if sh_is_exempt "$@"; then echo exempt; exit 0; else echo not-exempt; exit 1; fi ;;
    stage-validate)     sh_materialize_and_validate "$@" ;;
    stage-build)        sh_materialize_and_build "$@" ;;
    *)
      cat >&2 <<'USAGE'
usage: switchover-harness.sh <subcommand> ...
  gate-parity        <baseline_validate_out> <staging_validate_out>
  gate-nondecreasing <base_out> <base_exit> <stg_out> <stg_exit>
  gate-head-graph    <contract_yaml> <landing_path> <spec_path_abs>
  gate-golden        <dirA> <dirB> [<allowlist_ere>]
  is-exempt          <landing_path> <spec_path_abs>
  stage-validate     <worktree> <stage_parent_dir> <out_prefix> [drop_generator(0|1)]
  stage-build        <worktree> <stage_parent_dir> [drop_generator(0|1)]
USAGE
      exit 64 ;;
  esac
fi
