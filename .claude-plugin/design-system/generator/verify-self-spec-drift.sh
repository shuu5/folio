#!/usr/bin/env bash
# verify-self-spec-drift.sh — in-scan generated-canonical drift gate (folio-mkwc = 8dkl self-spec flip・instance#5)
#
# design-intent/spec/folio-self-spec.html は folio-mkwc の flip で「手書き canonical」から
# 「spec-pack fork (assemble-self-spec.sh) の生成物」へ切り替わった。 floor (verify-self-spec.sh) は
# 「contract ↔ 生成物」の相対突合ゆえ ★両側同時退行 に全盲で、 受入 oracle (self-spec-text-sweep.py) は
# ★pre-flip origin snapshot を anchor にするため ★flip 後に landed が静かに動いた ことは見ない
# (oracle の subject は pre-build 生成物・anchor は凍結 snapshot = landed 次元が両者の外側に残る)。
# ★本 gate だけが「landed canonical == fresh 再生成」を byte で束縛する = landed 次元の唯一の防壁。
#
# ★何を守るか (peer 4 本 = rules / relations / verification / srs-verification と同型):
#   - canonical の ★手編集 (契約 N7)。 errata の 8→9 も含め、 生成物へ直接手を入れる形は本 gate で即赤。
#   - ★style payload (inline <style> の CSS ブロック) の改竄。 floor の占有 pin にも census にも当たらず、
#     repro-build arm は in-scan flip では SKIP_REPRO=1 が必須 (folio-z7ba・ci.yml) ゆえ ★素通る 面。
#     ★本 gate の byte 比較だけがここを撃つ (敵対 suite に inline CSS 1 byte 改変の実弾を置いた)。
#   - contract / prose / assembler を変えたのに canonical を再生成し忘れる ★同期漏れ。
#
# ★fresh は full-repo staging で assemble → inject → fix --root → build --root を通す:
#   landed は folio fix (reverse @id materialize) → folio build (chrome inject) を経た状態ゆえ、
#   2-script (assemble+inject) だけの fresh と比べると chrome / reverse-@id 分が ★常時 false-drift になる
#   (レシピ = verify-relations-drift.sh:11-17 / verify-rules-drift.sh と逐語同型)。
#
# fail-closed 原則 (恒真 PASS / skip 化を全面禁止):
#   - 入力 (assemble/inject/contract/prose/canonical/folio/srs.css) は絶対 path + [[ -f ]] 存在ガード。
#     いずれか不在は即 exit 非零 (PASS / skip 化しない)。
#   - fresh は毎回新規 mktemp の full-repo staging へ (stale / 前回残骸 / cp canonical の pre-seed 禁止)。
#   - 再生成 precondition: assemble exit 0 / inject exit 0 / fix exit 0 / build exit 0 / fresh 非空 /
#     構造マーカー / 下限サイズ を順に assert。「再生成できなかった」は FAIL (skip も恒真 PASS も禁止)。
#   - ★物理指紋 assert (M8): ★self-spec 固有の ★非恒真 マーカーを採る。 ★rules 版を丸写ししない —
#     rules 版 clause(3) の data-component="ears-requirement-row" は self-spec 生成物では ★raw 13 hit が
#     ★全て inline CSS のセレクタ で body 内 DOM は 0 hit (要件 0 件の pack) ゆえ、 そのまま移植すると
#     ★恒真 PASS な clause になる (実測: raw 13 / body 0)。 採る 6 clause と ★弁別力 (landed / origin snapshot):
#       (1) 行頭 <style> 実在                              … 1 / 0
#       (2) 行頭 <link> stylesheet ★不在                    … 0 / 1  (旧 hand-authored は common.css link を持つ)
#       (3) generator meta の ★逐語 (self-spec fork 署名)    … 1 / 0  (consumer chrome 述語の検出鍵でもある)
#       (4) class="machine-fold" 実在 (機械層 trailing-fold) … 7 / 0  (qojv 決定 3 の生成物固有 shape)
#       (5) section id="s0-reader-guide" 実在                … 1 / 1  (anchor rot の検出・弁別でなく健全性)
#       (6) 行頭 <!-- folio:chrome-bottom --> 実在           … 1 / 1  (folio build 通過の構造証明)
#     各 clause の非 vacuous 性は committed な test-adversarial-self-spec-drift.sh が ★per-shape MK で pin する
#     (1 instance の実弾は構造差のある clause の穴を証明しない = jyfh / r8k の per-shape 原則)。
#   - timestamp normalize は footer「生成: <b>YYYY-MM-DD HH:MM</b>」に ★厳密 scope。 裸日付の全域置換や
#     行単位削除はしない (content date / SSoT 名 / 検証状態 / tags を潰さない)。 normalize 出力の
#     ★非空 assert を継承する (perl 失敗で両側が空になり diff 一致 = 恒真 PASS する唯一の無ガード経路の封鎖)。
#
# repo-root は cwd 非依存で確定 (TOOLERR-as-PASS 封鎖): script-relative を primary とし、
# git rev-parse --show-toplevel と一致すれば追認 (不一致でも script-relative を採用・git 外でも動く)。
#
# usage: verify-self-spec-drift.sh [--canon <path>]
#   --canon <path>  検査対象 canonical を上書き (既定 = <root>/design-intent/spec/folio-self-spec.html)。
#                   adversarial test が mutant / 旧 shape file を食わせるための escape hatch。
#   exit 0   = PASS (canonical == fresh, normalize 後 byte 一致 + 物理指紋一致)
#   exit 1   = FAIL (drift 検出 or 指紋破れ or 前提崩れ) — 理由 (drift した値を含む) を stderr へ
#   exit 2   = 未知引数 (0/1/2 の分離)
#
# 設計主体: folio-mkwc worker cell (Leg A)。 CI 配線も同 cell (M9・self-spec arm 直下へ追記)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

fail() { echo "verify-self-spec-drift: FAIL: $*" >&2; exit 1; }

# ---- repo-root を cwd 非依存で確定 (script-relative primary) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# generator → design-system → .claude-plugin → repo-root (3 つ上)
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if GIT_TOP="$(cd "$ROOT" && git rev-parse --show-toplevel 2>/dev/null)"; then
  [[ "$GIT_TOP" == "$ROOT" ]] || echo "verify-self-spec-drift: warn: git-top($GIT_TOP) != script-relative($ROOT); script-relative を採用" >&2
fi

GEN="$ROOT/.claude-plugin/design-system/generator"
ASSEMBLE="$GEN/assemble-self-spec.sh"
INJECT="$GEN/inject-prose.sh"
CONTRACT="$GEN/contract/folio-self-spec.spec.yaml"
PROSE="$GEN/prose/folio-self-spec.prose.yaml"
CANON="$ROOT/design-intent/spec/folio-self-spec.html"
CSS="$ROOT/.claude-plugin/design-system/srs.css"
FOLIO="$ROOT/.claude-plugin/bin/folio"

# ---- 引数 (--canon override) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --canon) CANON="$2"; shift 2 ;;
    *) echo "verify-self-spec-drift: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

# ---- 入力を絶対 path + 存在ガード (不在は即 FAIL・skip 化厳禁) ----
for f in "$ASSEMBLE" "$INJECT" "$CONTRACT" "$PROSE" "$CANON" "$CSS" "$FOLIO"; do
  [[ -f "$f" ]] || fail "入力不在 (存在ガード): $f"
done

# ---- 物理指紋 assert (M8・self-spec 固有の ★非恒真 6 clause) ----
# (1) inline <style> block (生成 pack は自己完結・外部 stylesheet を読まない)
grep -qE '^<style>' "$CANON" || fail "物理指紋(1): inline <style> block が無い ($CANON) — 生成 pack shape でない"
# (2) 行頭 <link> stylesheet が無い (旧 hand-authored canonical は <link href="../../common.css"> を head col-0 に持つ。
#     style ブロック内 CSS コメントの common.css 言及は行頭 <link でないので誤検出しない)
if grep -qE '^<link\b' "$CANON"; then
  fail "物理指紋(2): 行頭 <link> 要素を検出 ($CANON) — 外部 stylesheet 読込 = 旧 hand-authored shape (common.css link 温存)"
fi
# (3) generator meta の ★逐語 (self-spec fork 署名 = consumer chrome 述語 folio_chrome_is_generated_spec の検出鍵)
grep -qF '<meta name="generator" content="folio spec-pack assembler — self-spec fork' "$CANON" \
  || fail "物理指紋(3): generator meta の self-spec fork 署名が無い ($CANON) — 別 pack の産物 / 手書き原本の疑い"
# (4) 機械層 trailing-fold shape (qojv 決定 3・生成物固有。 手書き原本は details/summary の別 shape)
grep -qF 'class="machine-fold"' "$CANON" \
  || fail "物理指紋(4): class=\"machine-fold\" 不在 ($CANON) — 機械層 trailing-fold shape でない"
# (5) self-spec の章 anchor (§0) の実在 (anchor 一括 rot の検出)
grep -qF 'id="s0-reader-guide"' "$CANON" \
  || fail "物理指紋(5): section anchor id=\"s0-reader-guide\" 不在 ($CANON) — 章 anchor の rot"
# (6) folio build 通過の構造証明 (chrome marker 領域・行頭完全一致)。 landed は fix→build 済であることが前提で、
#     未 build の生成物をそのまま canonical に置く形 (chrome 欠落 land) を指紋段で落とす。
grep -qE '^<!--[[:space:]]*folio:chrome-bottom[[:space:]]*-->$' "$CANON" \
  || fail "物理指紋(6): chrome marker <!-- folio:chrome-bottom --> 不在 ($CANON) — folio build 未通過の land"

# ---- normalize: footer「生成: <b>TS</b>」の timestamp 部分文字列だけを固定トークンへ ----
# 接頭辞「生成: <b>」+ YYYY-MM-DD HH:MM +「</b>」に厳密 scope。他の裸日付 (版日付/承認/起票) は
# この prefix を持たないので不変。同一 footer 行の SSoT 名・検証状態・tags も不変。
normalize() {
  perl -pe 's{生成: <b>\d{4}-\d{2}-\d{2} \d{2}:\d{2}</b>}{生成: <b>\@\@SELFSPEC-DRIFT-GATE-TS\@\@</b>}g'
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
"$SGEN/assemble-self-spec.sh" "$SGEN/contract/folio-self-spec.spec.yaml" "$STG/asm.html" >/dev/null 2>"$WORK/aerr" \
  || fail "assemble 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/aerr")"
"$SGEN/inject-prose.sh" "$SGEN/prose/folio-self-spec.prose.yaml" "$STG/asm.html" "$STG/design-intent/spec/folio-self-spec.html" >/dev/null 2>"$WORK/ierr" \
  || fail "inject 失敗 (再生成不能): $(tr '\n' ' ' < "$WORK/ierr")"
# in-scan 固有: reverse @id materialize → chrome inject。 canonical guard は staging (mktemp) ゆえ通る。
( cd "$STG" && "$STG/.claude-plugin/bin/folio" fix --root design-intent >/dev/null 2>"$WORK/ferr" ) \
  || fail "folio fix 失敗 (reverse materialize 不能): $(tr '\n' ' ' < "$WORK/ferr")"
( cd "$STG" && "$STG/.claude-plugin/bin/folio" build --root design-intent >/dev/null 2>"$WORK/berr" ) \
  || fail "folio build 失敗 (chrome inject 不能): $(tr '\n' ' ' < "$WORK/berr")"

FRESH="$STG/design-intent/spec/folio-self-spec.html"

# ---- 再生成 precondition (fail-closed) ----
[[ -s "$FRESH" ]] || fail "fresh 空 (再生成不能)"
head -1 "$FRESH" | grep -qi '<!DOCTYPE html>' || fail "fresh に DOCTYPE 無し (構造マーカー欠如)"
grep -qF 'class="machine-fold"' "$FRESH" \
  || fail "fresh に構造マーカー class=\"machine-fold\" 無し"
fsz="$(wc -c < "$FRESH")"
[[ "$fsz" -ge 140000 ]] || fail "fresh サイズ $fsz < 下限 140000 (再生成崩れ)"

# ---- normalize 後 byte 比較 (1 byte drift でも FAIL) ----
normalize < "$CANON" > "$WORK/canon.norm"
normalize < "$FRESH" > "$WORK/fresh.norm"
# ★恒真 PASS 封鎖 (lwhz admin fixup 由来・独立 ceiling 処方): normalize (perl) が失敗すると両出力が
#   空になり diff 一致 = 恒真 PASS する唯一の無ガード pipeline だった。非空 assert で fail-closed 化。
[[ -s "$WORK/canon.norm" && -s "$WORK/fresh.norm" ]] || fail "normalize 出力が空 (perl 失敗の疑い・恒真 PASS 封鎖)"
if ! diff -q "$WORK/canon.norm" "$WORK/fresh.norm" >/dev/null; then
  {
    echo "verify-self-spec-drift: FAIL: design-intent/spec/folio-self-spec.html が fresh 再生成と drift (生成 timestamp 正規化後も byte 不一致):"
    echo "--- 差分 (< canonical / > fresh, 先頭 60 行) ---"
    diff "$WORK/canon.norm" "$WORK/fresh.norm" | head -60
  } >&2
  exit 1
fi

echo "verify-self-spec-drift: PASS: design-intent/spec/folio-self-spec.html == fresh 再生成 (assemble-self-spec + inject-prose + fix + build full pipeline・生成 timestamp 正規化後 byte 一致・物理指紋 6 clause 一致)"
