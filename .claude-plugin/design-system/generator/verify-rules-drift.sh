#!/usr/bin/env bash
# verify-rules-drift.sh — in-scan generated-canonical drift gate (folio-d7bq F8・instance#4 = rules)
#
# design-intent/spec/rules.html は inventory node (in-scan) だが、 folio validate の gate(m)
# nav-regen-drift は chrome/nav の drift しか見ず、 本文 (要件 prose / section 地の文 / 機械層) が contract
# から silent に取り残される drift は無警備 (lwhz verification / u7oc vision の in-scan 再演)。 recapture-
# parity は要件 ID 集合のみで prose/section を守らない。 本 gate は「canonical == fresh(full-repo 再生成)」を
# *生成 timestamp 正規化後* に byte 比較し、 差分が 1 byte でもあれば fail-closed で FAIL する。
#
# ★rules は spec-pack (assemble-spec.sh)。 verification 版 (assemble-verification.sh) を複写せず spec-pack
#   scriptを呼ぶ。 rules は in-scan ゆえ landed は folio fix (reverse @id materialize) → folio build (chrome
#   inject) を通した状態。 fresh も full-repo staging で assemble+inject → fix --root → build --root を
#   通して初めて landed と対称になる (2-script では chrome/reverse-@id 分が常時 false-drift)。 reverse-@id
#   は fix が決定的に materialize するため timestamp 以外の追加正規化は不要 (実測 byte 一致・folio-d7bq)。
#
# fail-closed 原則 (恒真 PASS/skip 化を全面禁止):
#   - 入力 (assemble/inject/contract/prose/canonical/folio/srs.css) は絶対 path + [[ -f ]] 存在ガード。
#     いずれか不在は即 exit 非零 (PASS/skip 化しない)。
#   - fresh は毎回新規 mktemp の full-repo staging へ (stale/前回残骸/cp canonical の pre-seed 禁止)。
#     staging = 作業ツリーの tracked 全体 (git ls-files | tar) = fix/build が full-repo graph を見るため。
#   - 再生成 precondition: assemble exit 0 / inject exit 0 / fix exit 0 / build exit 0 / fresh 非空 /
#     構造マーカー / 下限サイズ を順に assert。「再生成できなかった」は FAIL (skip も恒真 PASS も禁止)。
#   - ★物理指紋 assert (canonical が生成物 shape であること = hand-edit 温存を DONE 不可に): inline <style> /
#     行頭 <link> stylesheet 無 / ears-requirement-row shape / rules 要件 id (req-ci|cm|da|gloss|xref|adr)
#     もしくは section sN-* anchor の実在。 旧 canonical (common.css link 形・hand-authored details shape) を
#     食わせると指紋段で FAIL。 この指紋 4 clause + drift 段 + exit 規約の非 vacuous 性は committed な
#     test-adversarial-rules-drift.sh が per-shape MK で pin する (req-ver 依存除去 = rules は req-ver 0 本)。
#   - timestamp normalize は footer「生成: <b>YYYY-MM-DD HH:MM</b>」に厳密 scope。 裸日付の全域置換や
#     行単位削除はしない (content date / SSoT 名 / 検証状態 / tags を潰さない)。
#
# repo-root は cwd 非依存で確定 (TOOLERR-as-PASS 封鎖): script-relative を primary とし、
# git rev-parse --show-toplevel と一致すれば追認 (不一致でも script-relative を採用・git 外でも動く)。
#
# usage: verify-rules-drift.sh [--canon <path>]
#   --canon <path>  検査対象 canonical を上書き (既定 = <root>/design-intent/spec/rules.html)。
#                   adversarial test が旧 shape file を食わせるための escape hatch。
#   exit 0   = PASS (canonical == fresh, normalize 後 byte 一致 + 物理指紋一致)
#   exit 非零 = FAIL (drift 検出 or 指紋破れ or 前提崩れ) — 理由 (drift した値を含む) を stderr へ
#
# 設計主体: folio-d7bq worker cell (Leg A)。 CI 配線は admin Leg B (本 script は ci.yml を触らない)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

fail() { echo "verify-rules-drift: FAIL: $*" >&2; exit 1; }

# ---- repo-root を cwd 非依存で確定 (script-relative primary) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# generator → design-system → .claude-plugin → repo-root (3 つ上)
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if GIT_TOP="$(cd "$ROOT" && git rev-parse --show-toplevel 2>/dev/null)"; then
  [[ "$GIT_TOP" == "$ROOT" ]] || echo "verify-rules-drift: warn: git-top($GIT_TOP) != script-relative($ROOT); script-relative を採用" >&2
fi

GEN="$ROOT/.claude-plugin/design-system/generator"
ASSEMBLE="$GEN/assemble-spec.sh"
INJECT="$GEN/inject-prose.sh"
CONTRACT="$GEN/contract/folio-rules.spec.yaml"
PROSE="$GEN/prose/folio-rules.prose.yaml"
CANON="$ROOT/design-intent/spec/rules.html"
CSS="$ROOT/.claude-plugin/design-system/srs.css"
FOLIO="$ROOT/.claude-plugin/bin/folio"

# ---- 引数 (--canon override) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --canon) CANON="$2"; shift 2 ;;
    *) echo "verify-rules-drift: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

# ---- 入力を絶対 path + 存在ガード (不在は即 FAIL・skip 化厳禁) ----
for f in "$ASSEMBLE" "$INJECT" "$CONTRACT" "$PROSE" "$CANON" "$CSS" "$FOLIO"; do
  [[ -f "$f" ]] || fail "入力不在 (存在ガード): $f"
done

# ---- 物理指紋 assert (canonical が生成物 shape であること・hand-edit 温存の DONE 不可化) ----
# (1) inline <style> block (生成 pack は自己完結・外部 stylesheet を読まない)
grep -qE '^<style>' "$CANON" || fail "物理指紋: inline <style> block が無い ($CANON) — 生成 pack shape でない"
# (2) 行頭 <link> stylesheet が無い (旧 canonical は <link href="../../common.css"> を head col-0 に持つ。
#     style ブロック内 CSS コメントの common.css 言及は行頭 <link でないので誤検出しない)
if grep -qE '^<link\b' "$CANON"; then
  fail "物理指紋: 行頭 <link> 要素を検出 ($CANON) — 外部 stylesheet 読込 = 旧 hand-authored shape (common.css link 温存)"
fi
# (3) ears-requirement-row shape (生成物の要件 row。 手書き原本は <details class="spec-row">)
grep -qE 'data-component="ears-requirement-row"' "$CANON" || fail "物理指紋: data-component=\"ears-requirement-row\" 不在 ($CANON) — 旧 details.spec-row shape の疑い"
# (4) rules 要件 id (req-ci|cm|da|gloss|xref|adr) もしくは section sN-* anchor の実在 (req-ver 依存除去 = rules は req-ver 0 本)
if ! grep -qE 'id="req-(ci|cm|da|gloss|xref|adr)-[0-9]' "$CANON" && ! grep -qE 'id="s[0-9]' "$CANON"; then
  fail "物理指紋: rules anchor (req-ci|cm|da|gloss|xref|adr-* もしくは section s*-*) 不在 ($CANON)"
fi

# ---- normalize: footer「生成: <b>TS</b>」の timestamp 部分文字列だけを固定トークンへ ----
# 接頭辞「生成: <b>」+ YYYY-MM-DD HH:MM +「</b>」に厳密 scope。他の裸日付 (版日付/承認/起票) は
# この prefix を持たないので不変。同一 footer 行の SSoT 名・検証状態・tags も不変。
normalize() {
  perl -pe 's{生成: <b>\d{4}-\d{2}-\d{2} \d{2}:\d{2}</b>}{生成: <b>\@\@RULES-DRIFT-GATE-TS\@\@</b>}g'
}

# ---- fresh を新規 mktemp の full-repo staging へ (作業ツリー tracked 全体・fix/build が full-repo graph を要る) ----
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STG="$WORK/stg"; mkdir -p "$STG"
# git ls-files は tracked path 一覧、 tar は作業ツリーの現内容を読む (HEAD でなく working-tree 状態を反映)。
# untracked dotfile / sandbox の /dev/null char-device は tracked でないので除外される。
( cd "$ROOT" && git ls-files -z | tar --null -T - -cf - ) | tar -x -C "$STG" 2>/dev/null \
  || fail "staging 生成失敗 (git ls-files | tar)"
[[ -d "$STG/design-intent/spec" && -x "$STG/.claude-plugin/bin/folio" ]] \
  || fail "staging 不完全 (design-intent/spec or bin/folio 欠落)"

SGEN="$STG/.claude-plugin/design-system/generator"
"$SGEN/assemble-spec.sh" "$SGEN/contract/folio-rules.spec.yaml" "$STG/asm.html" >/dev/null 2>"$WORK/aerr" \
  || fail "assemble 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/aerr")"
"$SGEN/inject-prose.sh" "$SGEN/prose/folio-rules.prose.yaml" "$STG/asm.html" "$STG/design-intent/spec/rules.html" >/dev/null 2>"$WORK/ierr" \
  || fail "inject 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/ierr")"
# in-scan 固有: reverse @id materialize → chrome inject。 canonical guard は staging (mktemp) ゆえ通る。
( cd "$STG" && "$STG/.claude-plugin/bin/folio" fix --root design-intent >/dev/null 2>"$WORK/ferr" ) \
  || fail "folio fix 失敗 (reverse materialize 不能): $(tr '\n' ' ' < "$WORK/ferr")"
( cd "$STG" && "$STG/.claude-plugin/bin/folio" build --root design-intent >/dev/null 2>"$WORK/berr" ) \
  || fail "folio build 失敗 (chrome inject 不能): $(tr '\n' ' ' < "$WORK/berr")"

FRESH="$STG/design-intent/spec/rules.html"

# ---- 再生成 precondition (fail-closed) ----
[[ -s "$FRESH" ]] || fail "fresh 空 (再生成不能)"
head -1 "$FRESH" | grep -qi '<!DOCTYPE html>' || fail "fresh に DOCTYPE 無し (構造マーカー欠如)"
grep -qE 'data-component="ears-requirement-row"' "$FRESH" \
  || fail "fresh に構造マーカー data-component=\"ears-requirement-row\" 無し"
fsz="$(wc -c < "$FRESH")"
[[ "$fsz" -ge 100000 ]] || fail "fresh サイズ $fsz < 下限 100000 (再生成崩れ)"

# ---- normalize 後 byte 比較 (1 byte drift でも FAIL) ----
normalize < "$CANON" > "$WORK/canon.norm"
normalize < "$FRESH" > "$WORK/fresh.norm"
# ★恒真 PASS 封鎖 (lwhz admin fixup 由来・独立 ceiling 処方): normalize (perl) が失敗すると両出力が
#   空になり diff 一致 = 恒真 PASS する唯一の無ガード pipeline だった。非空 assert で fail-closed 化。
[[ -s "$WORK/canon.norm" && -s "$WORK/fresh.norm" ]] || fail "normalize 出力が空 (perl 失敗の疑い・恒真 PASS 封鎖)"
if ! diff -q "$WORK/canon.norm" "$WORK/fresh.norm" >/dev/null; then
  {
    echo "verify-rules-drift: FAIL: design-intent/spec/rules.html が fresh 再生成と drift (生成 timestamp 正規化後も byte 不一致):"
    echo "--- 差分 (< canonical / > fresh, 先頭 60 行) ---"
    diff "$WORK/canon.norm" "$WORK/fresh.norm" | head -60
  } >&2
  exit 1
fi

echo "verify-rules-drift: PASS: design-intent/spec/rules.html == fresh 再生成 (assemble-spec + inject-prose + fix + build full pipeline・生成 timestamp 正規化後 byte 一致・物理指紋一致)"
