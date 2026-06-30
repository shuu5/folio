#!/usr/bin/env bash
# folio engine — SRS render census 語彙 整合 gate (folio-hef.3)
#
# 『assemble-srs.sh + lib/common.sh が emit する data-component / data-prose-slot token』 == 『srs.census-vocab.yaml
# の data_components / prose_slots』 を bijection assert する deterministic CI floor。 ズレ (新部品追加・部品改名・
# 部品削除で語彙未更新) を hard FAIL = 赤にし、 census closure 語彙 (S4/S5 の基盤) の鮮度を機械強制する。
#
# 抽出は assemble-srs.sh (SRS-pack 固有 emitter) + lib/common.sh (core chrome emitter) の *両 file* を走査する
# (SRS grep だけだと doc-cover-band / chapter-deck-band / glossary-term-table / fidelity-sync-meta /
#  approval-block / plain-language-term-inline の core chrome が漏れる)。 lib/common.sh は perl 文字列内で
# `data-component=\"...\"` と backslash-escape するため、 抽出 regex は `=\\?"` で escape 形も拾う。
#
# bijection (emit == vocab) を取る理由: 「emit ⊆ vocab」(新部品で語彙更新強制) に加え「vocab ⊆ emit」
# (部品削除/改名で stale vocab 残存を捕捉) も assert し、 SSoT を双方向で鮮度保証する。 graph 系 (rolemap /
# verify-graph.sh) には一切触れない (本 gate は census-vocab pack 資産のみを対象・M-A 非破壊)。
#
# usage: verify-census-vocab.sh [--vocab-file <path>] [--gen-dir <dir>]
#   既定 vocab = <gen-dir>/rolemap/srs.census-vocab.yaml、 gen-dir = <script のあるディレクトリ>。
# exit: 0 = 整合 (PASS) / 1 = ズレ (FAIL) / 2 = tool error
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN_DIR="$SCRIPT_DIR"
VOCAB_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vocab-file) VOCAB_FILE="$2"; shift 2 ;;
    --gen-dir)    GEN_DIR="$2";    shift 2 ;;
    *) echo "verify-census-vocab: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$VOCAB_FILE" ]] || VOCAB_FILE="$GEN_DIR/rolemap/srs.census-vocab.yaml"

command -v yq  >/dev/null || { echo "verify-census-vocab: yq required"  >&2; exit 2; }
command -v grep >/dev/null || { echo "verify-census-vocab: grep required" >&2; exit 2; }
ASSEMBLE="$GEN_DIR/assemble-srs.sh"
COMMON="$GEN_DIR/lib/common.sh"
for f in "$VOCAB_FILE" "$ASSEMBLE" "$COMMON"; do
  [[ -f "$f" ]] || { echo "verify-census-vocab: 入力不在: $f" >&2; exit 2; }
done

# emit 抽出 (両 file・escape 形両対応・閉じ引用符まで full token・sort -u)。
# ★full token 捕捉 (folio-hef.3 ceiling): 旧 [a-z][a-z-]* は digit/大文字 suffix で token を
#   途中切断し、「既存 vocab token + 数字」(例 doc-cover-band2) で新部品を命名すると切断後が
#   既存 vocab と一致して bijection が silent PASS する穴があった。閉じ引用符 (or escape backslash)
#   まで full に取り、列挙でなく完全捕捉する (partial-enumeration trap 回避・engine doctrine)。
emit_tokens() { # $1 = 属性名 (data-component | data-prose-slot)
  grep -ohP "$1"'=\\?"\K[^"\\]+' "$ASSEMBLE" "$COMMON" | LC_ALL=C sort -u
}
# vocab list 抽出 (yq・sort -u)。 list 欠落/空は空文字列 = 後段の bijection が fail に倒す。
vocab_list() { # $1 = yq path (.data_components | .prose_slots)
  yq -r "$1 // [] | .[]" "$VOCAB_FILE" 2>/dev/null | grep -v '^$' | LC_ALL=C sort -u
}

fail=0
# bijection 検査: emit と vocab の対称差を列挙。 emit∖vocab = 語彙未更新 (新/改名部品)、 vocab∖emit = stale 語彙。
check_bijection() { # $1 = ラベル  $2 = 属性名  $3 = yq path
  local label="$1" attr="$2" path="$3" emit vocab missing stale
  emit="$(emit_tokens "$attr")"
  vocab="$(vocab_list "$path")"
  local ne nv
  ne="$(printf '%s\n' "$emit"  | grep -c . || true)"
  nv="$(printf '%s\n' "$vocab" | grep -c . || true)"
  # fail-closed: 片方でも空 (抽出/読込破綻) は整合と取り違えない。
  if [[ "$ne" -eq 0 ]]; then echo "  [FAIL] $label: emit token 抽出 0 件 (assemble/common 走査破綻?)"; fail=1; return; fi
  if [[ "$nv" -eq 0 ]]; then echo "  [FAIL] $label: vocab list 0 件 ($VOCAB_FILE の $path 欠落/空?)"; fail=1; return; fi
  missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$emit") <(printf '%s\n' "$vocab") | grep -v '^$' || true)"
  stale="$(  LC_ALL=C comm -13 <(printf '%s\n' "$emit") <(printf '%s\n' "$vocab") | grep -v '^$' || true)"
  if [[ -n "$missing" ]]; then
    echo "  [FAIL] $label: emit にあるが vocab に無い (語彙更新が必要・新部品/改名): $(printf '%s' "$missing" | tr '\n' ' ')"; fail=1
  fi
  if [[ -n "$stale" ]]; then
    echo "  [FAIL] $label: vocab にあるが emit に無い (stale 語彙・部品削除/改名): $(printf '%s' "$stale" | tr '\n' ' ')"; fail=1
  fi
  [[ -z "$missing" && -z "$stale" ]] && echo "  [OK]   $label: emit == vocab ($ne 件 bijection)"
}

echo "=========================================================================="
echo "folio verify-census-vocab — render census 語彙 整合 gate (emit == census-vocab)"
echo "  vocab:    $VOCAB_FILE"
echo "  emit src: assemble-srs.sh + lib/common.sh"
echo "=========================================================================="
check_bijection "data-component" "data-component" ".data_components"
check_bijection "data-prose-slot" "data-prose-slot" ".prose_slots"

echo "  ----"
if [[ "$fail" -ne 0 ]]; then
  echo "  RESULT: FAIL — census-vocab が emit 集合とズレ (語彙を更新せよ)"
  exit 1
fi
echo "  RESULT: PASS — census-vocab は emit 集合と bijection (語彙鮮度 OK)"
exit 0
