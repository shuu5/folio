#!/usr/bin/env bash
# folio engine (folio-cuom) — self-spec pack の敵対回帰 (per-shape mutation-kill)。
#
# ★位置づけ (範型 test-adversarial-verification.sh の ★部分 fork・実態を開示する):
#   範型は verification pack 固有の 115 ケース (demoted 改竄 / 機械層注入 / containment / census laundering …) を持つが、
#   本 script は ★folio-cuom Leg A が ★新規に導入した shape と ★契約 DoD が名指しした MK に ★scope を限定 する。
#   ★out-of-scope の開示 (silent 欠落は「範型踏襲済」の誤報告になる):
#     - containment 3 レベル完全子数束縛 / HTML5 同型 tokenizer の per-shape MK      → 範型 (verification) 側に在り本 fork は未移植
#     - census laundering (template / RAWTEXT 自己閉じ / 属性値 laundering) の per-shape → 同上
#     - 機械層 demoted / dl の改竄 (F12 / M16)                                        → self-spec は demoted 0 / dl 0 ゆえ ★対象不在
#   ★これらは folio-mkwc (flip) / admin Leg B の領分として申し送る。 ここに書かない限り「全クラス被覆」の誤報告になる。
#
# ★本 script が撃つ shape (各 1 発以上の ★実弾 = mutation-kill):
#   A 群 assembler fail-closed (abort)   … doc_id guard (D9) / doc_type / subhead anchor / 型退行
#   B 群 verify FAIL (生成物 mutation)    … head meta (D3) / head_graph (D4) / subhead id / 要件 shape / census
#   C 群 ★陽性対照                        … 要件を注入した contract で要件系 arm が ★動く (M5 の「陽性対照」要求)
#   D 群 extractor fail-loud / silent-drop… @SECORDER 不一致 (M1) / <br> 変換 (M2) / essence 窓 /
#                                          ★errata-1: <b> 逐語保持の喪失 (D5) / 未対応 inline 資産の ★literal 閉集合
#                                          guard (D6a 負の対照 + D6/D6b/D6c/D6d/D6e = 別 tag / 属性付き / 大文字 /
#                                          numeric entity / 閉じ '>' 無しの生 '<' の per-shape 実弾)
#   E 群 collapse                        … rich→plain 退行を凍結 census が撃つ (両側同時退行の唯一の FAIL 源)
#   F 群 errata / 手起こしの存在 pin      … contract に errata 1 site と head_graph が実在する (M7 の commit 前 assert と対)
#     + ★受入 oracle (D7) 自身の per-shape MK … errata 同居 delta (F7) / errata site 増殖 (F8) /
#       本文見出しの欠落 (F9) / chrome 件数 pin (F10) / ★gen_allow 側の tightness (F11..F14 = fold の章帰属・
#       件数 / reader-chip・provenance の接頭辞) / ★文書 identity の捏造 (F15/F16 = meta.title / subtitle・
#       F17/F18 = meta.version / meta.status の ★別 shape) / ★人間層 block の順序 (F19 + 前提 pin F19b)。
#       oracle は canonical を独立 anchor にする唯一の gate ゆえ ★実弾が無いと「悉皆・未分類 0」が
#       宣言能力 > 実能力 になる (F7/F9/F11..F19 は ★いずれも実際に fail-open していた実績クラス)
#     + ★errata-1 追加分: 層帰属 demote (F20 oracle / F20b floor・M2) / 照会の canonical anchor 束縛
#       (F21 token 捏造 / F22 role 付替え / F23 1 本削除・M4) / 既存 marker の複製注入 (F24 class 閉 allowlist /
#       F24b consumer 一次 selector / F25 bucket 件数 pin・M5)
#   G 群 conformance pin                  … repro-build arm ON の baseline (G1) + ★sub-pin (a)-(d) 実走 (G2・M3)
#
# usage: test-adversarial-self-spec.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ASM="$SCRIPT_DIR/assemble-self-spec.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-self-spec.sh"
EXTRACT="$REPO_ROOT/.claude-plugin/scripts/extract-self-spec-spec.sh"
CANON="$REPO_ROOT/design-intent/spec/folio-self-spec.html"
BASE="$SCRIPT_DIR/contract/folio-self-spec.spec.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-self-spec.prose.yaml"
FOREIGN="$SCRIPT_DIR/contract/folio-verification.spec.yaml"
ORACLE="$SCRIPT_DIR/oracle/self-spec-text-sweep.py"
# ★共有 repro-build conformance seed (folio-mzn.3 Phase B / folio-3d23 B3・範型 verification/relations と同型)。
#   G 群で 1 回だけ arm ON 実走する (bulk case は SKIP_REPRO=1 の honest skip)。
source "$SCRIPT_DIR/lib/test-repro-pins.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
# 重い arm は bulk case で honest skip (末尾の conformance pin で 1 回だけ実走する)。
export SKIP_REPRO="${SKIP_REPRO:-1}"
export SELF_SPEC_SKIP_RENDER="${SELF_SPEC_SKIP_RENDER:-1}"
declare -a SEEN=()
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); SEEN+=("${1%% *}"); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); SEEN+=("${1%% *}"); }

# ---- helper (範型と同型: abort/FAIL の ★理由まで照合し「別原因での false-pass」を弾く) ----
expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then
    ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
# ★verify FAIL の理由照合は ★[FAIL] 行 anchor (census 系ラベルは PASS 行にも件数付きで出るため、
#   単純 substring 一致は ★恒真 になり巻き添え guard が inert 化する = 範型 errata-1 must-1 と同じ規律)。
expect_vfail() { # label contract html [reason]
  local out rc; out="$(bash "$VER" --artifact "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (verify が PASS した = mutation が素通り)"; return; fi
  if [[ -n "${4:-}" ]] && ! printf '%s\n' "$out" | grep -F -- "$4" | grep -qF -- '[FAIL]'; then
    ng "$1 (FAIL したが理由が [FAIL] 行に無い。 期待 '$4')"; return; fi
  ok "$1"
}
expect_vpass() { # label contract html
  if bash "$VER" --artifact "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL = 空撃ち)"; fi
}
# ★expect_oracle は ★helper 節で定義する (D 群からも呼ぶため)。 以前は F 群の直前で定義していたため
#   D 群からの呼出しが ★未定義関数 = rc=127 で ★silent no-op になり case が実行されなかった
#   (CASEPIN の「宣言したが実行されていない」が捕捉した = 宣言集合 pin が効いた実例)。
expect_oracle() { # label canonical generated contract expect_rc [reason_substring]
  local out rc; out="$(python3 "$ORACLE" "$2" "$3" "$4" "$BASE_PROSE" 2>&1)"; rc=$?
  if [[ "$rc" -ne "$5" ]]; then ng "$1 (oracle rc=$rc 期待 $5)"; return; fi
  if [[ -n "${6:-}" && "$out" != *"$6"* ]]; then
    ng "$1 (rc は一致したが理由が想定外。 期待 '$6')"; return; fi
  ok "$1"
}
# ★body 限定の occurrence 計数 — inline srs.css は [data-component="…"] セレクタを ★本文と同じ literal で
#   持つため、 素の grep は CSS を数えて ★恒真に近い偽値 を返す (実測: 要件 0 の生成物で row が 14 と出た)。
#   verify 側 (make_body) と同じ規律を test 側でも守る。
body_count() { # $1 = html  $2 = literal
  awk '/<body>/{f=1} f' "$1" | grep -o -- "$2" | wc -l | tr -d ' '
}
# ★<pre> 内の <b> open/close 件数 (errata-2 M8(3) の D7y 前提 pin 用・実 HTML parser で数える)。
pre_b_count() { # $1 = html → "open close"
  python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys
class P(HTMLParser):
    def __init__(s):
        super().__init__(convert_charrefs=True); s.d = 0; s.o = 0; s.c = 0
    def handle_starttag(s, t, a):
        if t == 'pre': s.d += 1
        elif s.d > 0 and t == 'b': s.o += 1
    def handle_startendtag(s, t, a):
        if s.d > 0 and t == 'b': s.o += 1
    def handle_endtag(s, t):
        if t == 'pre' and s.d > 0: s.d -= 1
        elif s.d > 0 and t == 'b': s.c += 1
p = P(); p.feed(open(sys.argv[1], encoding='utf-8').read())
print('%d %d' % (p.o, p.c))
PYEOF
}

# ---- 健全 baseline ----
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }
echo "=== test-adversarial-self-spec (folio-cuom Leg A) ==="
echo "--- 空撃ち対照: 無改竄 baseline は PASS すること (以降の FAIL が mutation 由来だと言えるための前提) ---"
expect_vpass "BASE0 無改竄 baseline が verify PASS (空撃ち封鎖)" "$BASE" "$TMP/base-filled.html"

# ============================================================================
echo "--- A 群: assembler の fail-closed (abort) ---"
# ★A1 = 契約 D9 の実測 (「他 pack の contract を食わせたら abort する」)。 doc_type は 5 契約が共有し
#   識別力ゼロゆえ、 doc_id literal guard ★だけ が本 shape を止める。
expect_abort "A1 他 pack contract (folio-verification) を assemble へ → doc_id guard で abort [D9]" \
  "$FOREIGN" "meta.doc_id は FOLIO-SELF-SPEC 必須"
# ★A2 doc_id を 1 文字変える (誤入力・rename の shape)。
yq '.meta.doc_id = "FOLIO-SELF-SPECX"' "$BASE" > "$TMP/a2.yaml"
expect_abort "A2 doc_id 改竄 → abort" "$TMP/a2.yaml" "meta.doc_id は FOLIO-SELF-SPEC 必須"
# ★A3 doc_type flip (gate bypass の古典 shape)。
yq '.meta.doc_type = "rules"' "$BASE" > "$TMP/a3.yaml"
expect_abort "A3 doc_type flip → abort" "$TMP/a3.yaml" "meta.doc_type は spec 必須"
# ★A4 subhead の anchor ★キー削除 = 抽出規約 drift (空文字列とは別クラス)。
yq 'del(.sections[3].blocks[0].anchor)' "$BASE" > "$TMP/a4.yaml"
expect_abort "A4 subhead anchor キー削除 → abort (空文字列と区別する fail-closed)" "$TMP/a4.yaml" "anchor キーが無い"
# ★A5 subhead の anchor を null (YAML の型退行)。
yq '.sections[3].blocks[0].anchor = null' "$BASE" > "$TMP/a5.yaml"
expect_abort "A5 subhead anchor null → abort" "$TMP/a5.yaml" "anchor が null"
# ★A6 未対応 block type (silent drop 禁止)。
yq '.sections[0].blocks = [{"type":"bogus"}]' "$BASE" > "$TMP/a6.yaml"
expect_abort "A6 未対応 block type → abort (silent drop 禁止)" "$TMP/a6.yaml" "未対応 block type"
# ★A7 stakeholders の scalar 退行 (JSON-LD array→string の型退行・どの既存 gate も捕まえない shape)。
yq '.meta.stakeholders = "Developer, AI Agent"' "$BASE" > "$TMP/a7.yaml"
expect_abort "A7 stakeholders scalar 化 → abort (JSON-LD array 型退行封鎖)" "$TMP/a7.yaml" "array 必須"
# ★A8 機械層へ script 注入 (RAW emit 経路の注入面)。
yq '.sections[0].machine_blocks[0].html = "<p>x</p><script>alert(1)</script>"' "$BASE" > "$TMP/a8.yaml"
expect_abort "A8 機械層 blob へ <script> 注入 → abort (allowlist fail-closed)" "$TMP/a8.yaml" "allowlist 外"
# ★A9 人間層 rich field へ event handler 注入 (属性名 allowlist)。
yq '.sections[0].essence = "<a href=\"#x\" onclick=\"alert(1)\">z</a>"' "$BASE" > "$TMP/a9.yaml"
expect_abort "A9 人間層 rich field へ onclick 注入 → abort (属性名 allowlist)" "$TMP/a9.yaml" "allowlist 外"
# ★A10 requirements の null 退行 (契約 M4 が明示的空配列を要求する理由の実弾)。
yq '.requirements = null' "$BASE" > "$TMP/a10.yaml"
if bash "$ASM" "$TMP/a10.yaml" "$TMP/o.html" >/dev/null 2>&1; then
  # null でも build できてしまう場合は「M4 が守る性質」を verify 側が撃つか確認する。
  if bash "$VER" --artifact "$TMP/a10.yaml" "$TMP/o.html" >/dev/null 2>&1; then
    ng "A10 requirements=null が assemble も verify も素通り (M4 の明示的空配列規律が無防備)"
  else ok "A10 requirements=null は verify が FAIL (M4 規律の後段防壁)"; fi
else ok "A10 requirements=null は assemble が abort (M4 規律の前段防壁)"; fi

# ============================================================================
echo "--- B 群: verify の mutation-kill (生成物 / contract 改竄) ---"
# ★B1 [D3] pack 固有 folio-* meta を ★1 本ずつ 消す (per-shape = 4 shape)。 総数 pin (7) と per-meta chk の
#   両方が撃つ。 ★1 shape だけで済ませない (構造が違う meta の穴は別 instance では証明されない)。
for m in folio-layer folio-glossary-automark folio-stakeholders folio-xref-completeness; do
  sed "0,/<meta name=\"$m\"[^>]*>/s///" "$TMP/base-filled.html" > "$TMP/b1-$m.html"
  expect_vfail "B1 head meta '$m' を 1 本削除 → FAIL [D3]" "$BASE" "$TMP/b1-$m.html" "folio-* head meta 総数 == 7"
done
# ★B1b CORE 側 meta (doc-type) も per-shape で撃つ (pack 側だけ守って CORE 側が無防備、を封鎖)。
sed '0,/<meta name="folio-doc-type"[^>]*>/s///' "$TMP/base-filled.html" > "$TMP/b1-core.html"
expect_vfail "B1b CORE meta 'folio-doc-type' を削除 → FAIL [D3]" "$BASE" "$TMP/b1-core.html" "folio-* head meta 総数 == 7"
# ★B2 [D4] head_graph を落とした contract → 生成物から folio-doc-type meta と JSON-LD が ★両方 消える。
yq 'del(.head_graph)' "$BASE" > "$TMP/b2.yaml"
bash "$ASM" "$TMP/b2.yaml" "$TMP/b2.html" >/dev/null 2>&1
if [[ -s "$TMP/b2.html" ]]; then
  n_ld="$(grep -o 'application/ld+json' "$TMP/b2.html" | wc -l | tr -d ' ')"
  n_dt="$(grep -o '<meta name="folio-doc-type"' "$TMP/b2.html" | wc -l | tr -d ' ')"
  if [[ "$n_ld" -eq 0 && "$n_dt" -eq 0 ]]; then
    ok "B2 head_graph 欠落 → 生成物から JSON-LD と folio-doc-type meta が消える (silent skip の実測) [D4]"
  else ng "B2 head_graph 欠落なのに JSON-LD($n_ld) / doc-type meta($n_dt) が残る (前提が崩れている)"; fi
  bash "$INJ" "$BASE_PROSE" "$TMP/b2.html" "$TMP/b2-filled.html" >/dev/null 2>&1
  expect_vfail "B2b head_graph 欠落 contract の生成物 → verify FAIL [D4]" "$TMP/b2.yaml" "$TMP/b2-filled.html" "folio-* head meta 総数 == 7"
else ng "B2 head_graph 欠落 contract の assemble が失敗 (測定不能)"; fi
# ★B3 subhead の id を 1 本剥がす (id 付き → id 無し)。 anchor 列 / 件数 / census の 3 本が撃つ。
perl -0777 -pe 's/<h3 id="s3-1-core">/<h3>/' "$TMP/base-filled.html" > "$TMP/b3.html"
expect_vfail "B3 subhead id を 1 本剥奪 → FAIL (anchor 列 + 件数 + census)" "$BASE" "$TMP/b3.html" "id 付き h3 数"
# ★B4 id 無し h3 へ id を ★捏造 (逆方向 shape)。 片方向だけ撃つと逆向きの捏造が素通る。
perl -0777 -pe 's/<h3>§8\.1 /<h3 id="s8-1-fake">§8.1 /' "$TMP/base-filled.html" > "$TMP/b4.html"
expect_vfail "B4 id 無し h3 へ id 捏造 → FAIL (逆方向 shape)" "$BASE" "$TMP/b4.html" "id 無し h3 数"
# ★B5 EARS 凡例を注入 (要件 0 件の pack に凡例が湧く shape = conditional 化の逆退行)。
perl -0777 -pe 's{(<div class="page")}{<div data-component="ears-legend"><span class="el-cap">x</span></div>$1}' \
  "$TMP/base-filled.html" > "$TMP/b5.html"
expect_vfail "B5 EARS 凡例を注入 → FAIL (conditional 化の逆退行・M5)" "$BASE" "$TMP/b5.html" "ears-legend =="
# ★B6 rq-prio バッジを注入 (要件 shape の残骸)。
perl -0777 -pe 's{(<div class="page")}{<span class="rq-prio rq-prio-must" data-prose-slot="priority" data-slot-id="prio-x">必須</span>$1}' \
  "$TMP/base-filled.html" > "$TMP/b6.html"
expect_vfail "B6 rq-prio バッジ注入 → FAIL (M5 negative assert)" "$BASE" "$TMP/b6.html" "rq-prio 優先度バッジ"
# ★B7 census: live a.xref を 1 個減らす (rich 資産の目減り)。
perl -0777 -pe 's/<a class="xref"/<a class="xrefX"/' "$TMP/base-filled.html" > "$TMP/b7.html"
expect_vfail "B7 a.xref を 1 個潰す → FAIL (凍結 census)" "$BASE" "$TMP/b7.html" "a.xref occurrence"
# ★B8 census: navigable id の rename (count 保存 substitution)。
perl -0777 -pe 's/<section id="s9-bindings">/<section id="s9-bindingz">/' "$TMP/base-filled.html" > "$TMP/b8.html"
expect_vfail "B8 navigable id を rename → FAIL (id SET census・count 保存でも捕捉)" "$BASE" "$TMP/b8.html" "census id-rename SET"
# ★B9 delta marker 注入 (FZ_DELTA=0 は恒真 pin ではないことの実弾)。
perl -0777 -pe 's{(<div class="page")}{<ins class="delta" data-delta-id="D-2026-01-01-001">x</ins>$1}' \
  "$TMP/base-filled.html" > "$TMP/b9.html"
expect_vfail "B9 delta marker 注入 → FAIL (FZ_DELTA=0 の teeth 実証)" "$BASE" "$TMP/b9.html" "ins|del.delta occurrence"
# ★B10 mermaid 行を 1 行落とす (M2 が入れた ★改行 も含めて逐値突合されることの実弾)。
# ★生成物では " が &quot; へ esc 済ゆえ ★esc 後の形 でマッチさせる (esc 前の形で書くと ★空撃ちになり
#   「mutation が素通った」でなく「mutation が当たっていない」を FAIL と誤読する)。
perl -0777 -pe 's/\n[ ]*L1CONF\[&quot;folio\.config\.yaml&quot;\]//' "$TMP/base-filled.html" > "$TMP/b10.html"
if cmp -s "$TMP/base-filled.html" "$TMP/b10.html"; then ng "B10 mutation が空撃ち (生成物に対象行が無い)"; else
expect_vfail "B10 mermaid source を 1 行削除 → FAIL (source_lines 逐値突合)" "$BASE" "$TMP/b10.html" "mermaid source 行列"; fi
# ★B11 navigable id の ★複製注入 (unique 保存の anchor hijack)。
perl -0777 -pe 's{(<div class="page")}{<div id="s0-reader-guide"></div>$1}' "$TMP/base-filled.html" > "$TMP/b11.html"
expect_vfail "B11 既存 id の複製注入 → FAIL (unique == 総出現の構造的不変条件)" "$BASE" "$TMP/b11.html" "重複 0"

# ============================================================================
echo "--- C 群: ★陽性対照 (M5 の「要件を 1 本注入した fixture で FAIL する陽性対照」) ---"
# ★要件を 1 本持つ contract を作る。 これで (a) 要件系 arm が ★死んでいない (期待値が contract 追随で動く) ことと、
#   (b) base 契約 (要件 0) の期待を当てると FAIL することの ★両方 を示す。
yq '.requirements = [{"id":"REQ-XX-001","anchor":"req-xx-001","ears_pattern":"ubiquitous",
     "essence":"テスト用要件","statement":"system は X を提供する MUST。","priority":"must"}] |
    .sections[0].blocks = [{"type":"requirements","ids":["REQ-XX-001"]}]' "$BASE" > "$TMP/c1.yaml"
if bash "$ASM" "$TMP/c1.yaml" "$TMP/c1.html" >/dev/null 2>&1; then
  n_leg="$(body_count "$TMP/c1.html" 'data-component="ears-legend"')"
  n_row="$(body_count "$TMP/c1.html" 'data-component="ears-requirement-row"')"
  if [[ "$n_leg" -eq 1 && "$n_row" -eq 1 ]]; then
    ok "C1 要件 1 本注入 → EARS 凡例 ($n_leg) と要件 row ($n_row) が ★出る (conditional 化が死機構でないことの陽性対照)"
  else ng "C1 要件を入れても凡例($n_leg)/row($n_row) が出ない (conditional 化が死んでいる)"; fi
  # ★★C1a per-shape 陽性対照 (M5 の「陽性対照を per-shape で付ける」要求)。
  #   ★row 1 発では足りない: rq-prio (span バッジ) / rq-plain (prose-slot 付き p) / rq-norm (details+summary fold) /
  #   ears-badge / data-ears-pattern (★属性) は ★DOM 構造クラスが row とも legend とも異なる ため、
  #   row での 1 発は これらの穴を証明しない (folio 恒常 gotcha = per-shape MK)。 各 shape の ★実在 を個別に数える。
  for pair in 'rq-prio:<span class="rq-prio ' \
              'rq-plain:<p class="rq-plain">' \
              'rq-norm:class="rq-norm" data-audience="machine"' \
              'ears-badge:data-component="ears-badge"' \
              'data-ears-pattern:data-ears-pattern="'; do
    _k="${pair%%:*}"; _lit="${pair#*:}"
    _n="$(body_count "$TMP/c1.html" "$_lit")"
    if [[ "$_n" -eq 1 ]]; then ok "C1a per-shape 陽性対照: 要件 1 本で '$_k' が 1 件 出る"
    else ng "C1a per-shape 陽性対照: '$_k' が $_n 件 (期待 1・shape が死んでいる)"; fi
  done
  # ★base 契約 (要件 0) の期待で verify すると FAIL する = negative assert が恒真でないことの実弾。
  #   ★M5 の negative assert は 6 shape あるので ★shape ごとに 1 発ずつ撃つ (1 ラベルで代表させない)。
  expect_vfail "C1b 要件入り生成物 × 要件 0 の base 契約 → FAIL (M5(a) ears-requirement-row)" \
    "$BASE" "$TMP/c1.html" "ears-requirement-row"
  expect_vfail "C1c 同上 → FAIL (M5(b) rq-prio 優先度バッジ)"        "$BASE" "$TMP/c1.html" "rq-prio 優先度バッジ"
  expect_vfail "C1d 同上 → FAIL (M5(b) rq-plain 平易行)"             "$BASE" "$TMP/c1.html" "rq-plain 平易行"
  expect_vfail "C1e 同上 → FAIL (M5(c) 要件 normative fold rq-norm)" "$BASE" "$TMP/c1.html" "要件 normative fold (rq-norm)"
  expect_vfail "C1f 同上 → FAIL (M5(a) data-ears-pattern 属性)"      "$BASE" "$TMP/c1.html" "data-ears-pattern 属性"
  expect_vfail "C1g 同上 → FAIL (ears-badge == |requirements|)"      "$BASE" "$TMP/c1.html" "ears-badge =="
  # ★★C3 = EARS 凡例 conditional 化の ★陽性対照 (verify-self-spec.sh の legend 節が参照する実体)。
  #   ★要件 1 本 contract を ★その contract 自身で verify する — これで初めて NREQ>0 分岐 (legend 1 / item 5 /
  #   el-when 5 + ★label 列 + ★el-when 列) が ★実走 する。 C1b..C1g は base 契約でしか verify しないため
  #   NREQ>0 分岐が一度も実行されず、 分岐内の破損 (期待値の末尾改行・esc 欠落・正規表現狭窄) を検出できない。
  c3out="$(bash "$VER" --artifact "$TMP/c1.yaml" "$TMP/c1.html" 2>&1)"; c3rc=$?
  if printf '%s\n' "$c3out" | grep -F 'ears-legend label 列' | grep -qF '[OK]' \
     && printf '%s\n' "$c3out" | grep -F 'ears-legend el-when 列' | grep -qF '[OK]' \
     && printf '%s\n' "$c3out" | grep -F 'ears-legend == (NREQ>0 ? 1 : 0)' | grep -qF '[OK]'; then
    ok "C3 EARS-LEGEND-POS: 要件 1 本 contract × 同 contract で NREQ>0 分岐が実走し legend 3 arm が PASS"
  else
    ng "C3 EARS-LEGEND-POS: NREQ>0 分岐の legend arm が PASS しない (verify rc=$c3rc・conditional 化が label/順序 arm を巻き込んだ疑い)"
    printf '%s\n' "$c3out" | grep -E 'ears-legend' | sed 's/^/      /' | head -6
  fi
else ng "C1 要件 1 本注入した contract の assemble が失敗 (陽性対照を測れない)"; fi
# ★C2 references[].title の陽性対照 (rf-gloss が「作れば出る」= 0 が死機構でないことの実証)。
yq '.references = [.references[] | . + {"title":"テスト用一行タイトル"}]' "$BASE" > "$TMP/c2.yaml"
if bash "$ASM" "$TMP/c2.yaml" "$TMP/c2.html" >/dev/null 2>&1; then
  n_g="$(body_count "$TMP/c2.html" '<span class="rf-gloss">')"
  n_r="$(yq -r '.references | length' "$BASE")"
  if [[ "$n_g" -eq "$n_r" ]]; then ok "C2 references[].title 全付与 → rf-gloss が $n_g 件 出る (陽性対照)"
  else ng "C2 title 付与しても rf-gloss が $n_g/$n_r 件しか出ない"; fi
  expect_vfail "C2b title 付き生成物 × title 無し base 契約 → FAIL (rf-gloss 契約導出の teeth)" \
    "$BASE" "$TMP/c2.html" "rf-gloss"
else ng "C2 title 付与 contract の assemble が失敗"; fi

# ============================================================================
echo "--- D 群: extractor の fail-loud / silent-drop 封鎖 (M1 / M2) ---"
# ★D1 [M1] @SECORDER を stale 化 (fork 元の欠陥そのもの = 別 doc の id を hardcode したまま当てる形)。
sed 's/^my @SECORDER = qw(s0-reader-guide s1-architecture/my @SECORDER = qw(s0-reader-guide s1-contract/' \
  "$EXTRACT" > "$TMP/d1.sh"
if ! diff -q "$EXTRACT" "$TMP/d1.sh" >/dev/null; then
  out="$(bash "$TMP/d1.sh" "$CANON" 2>&1 >/dev/null)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"集合が不一致"* ]]; then
    ok "D1 @SECORDER を stale 化 → extractor が fail-loud (silent collapse 封鎖) [M1]"
  else ng "D1 @SECORDER stale でも extractor が rc=$rc で通った (silent collapse が再開通)"; fi
else ng "D1 mutation が空撃ち (sed が当たっていない)"; fi
# ★D2 [M1] 原本側に未知 section を足す (逆方向 shape = 原本が育ったのに SECORDER が追随しない形)。
perl -0777 -pe 's{(<section id="s9-bindings")}{<section id="s99-new"><h2>§99. new</h2></section>$1}' \
  "$CANON" > "$TMP/d2.html"
out="$(bash "$EXTRACT" "$TMP/d2.html" 2>&1 >/dev/null)"; rc=$?
if [[ $rc -ne 0 && "$out" == *"集合が不一致"* ]]; then
  ok "D2 原本に未知 <section id> を追加 → extractor が fail-loud [M1]"
else ng "D2 未知 section が silent drop された (rc=$rc)"; fi
# ★D3 [M2] <br> → 改行 変換を除去した mutant extractor → mermaid 行数が ★73 減る (canonical の <br> 実数)。
#   ★mutation は sed でなく python で行う (perl 正規表現の literal を shell/sed の escape 層に通すと
#   ★当たっていないのに「当たった」と読む空撃ちが起きるため・実測)。 mutate 後に diff で ★発火を確認する。
python3 - "$EXTRACT" "$TMP/d3.sh" <<'PYD3'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
old="      $src =~ s/<br\\s*\\/?>/\\n/g;"
assert src.count(old)==1, ('D3 anchor not unique', src.count(old))
open(sys.argv[2],'w',encoding='utf-8').write(src.replace(old,"      # (mutated: br conversion removed)"))
PYD3
if [[ -s "$TMP/d3.sh" ]] && ! diff -q "$EXTRACT" "$TMP/d3.sh" >/dev/null; then
  bash "$EXTRACT" "$CANON" > "$TMP/d3-base.yaml" 2>/dev/null
  bash "$TMP/d3.sh" "$CANON" > "$TMP/d3-mut.yaml" 2>/dev/null
  nb="$(yq -r '.sections[].blocks[]?|select(.type=="mermaid")|.source_lines[]' "$TMP/d3-base.yaml" | wc -l)"
  nm="$(yq -r '.sections[].blocks[]?|select(.type=="mermaid")|.source_lines[]' "$TMP/d3-mut.yaml" | wc -l)"
  nbr="$(grep -o '<br[[:space:]]*/*>' "$CANON" | wc -l | tr -d ' ')"
  if [[ "$nm" -gt 0 && "$((nb - nm))" -eq "$nbr" ]]; then
    ok "D3 <br> 変換を除去 → mermaid 行数が $((nb-nm)) 減る == canonical の <br> $nbr 個 [M2/D2]"
  else ng "D3 行数 base=$nb mut=$nm 増分 $((nb-nm)) != canonical <br> $nbr"; fi
else ng "D3 mutation が空撃ち (python mutate が当たっていない)"; fi
# ★D4 subhead essence の ★窓 (長さ上限) を復活させた mutant → 長い essence が ★無警告で空になる。
python3 - "$EXTRACT" "$TMP/d4.sh" <<'PYD4'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
old='if (substr($inner,$afterh3) =~ /^'
assert src.count(old)==1, ('D4 anchor not unique', src.count(old))
open(sys.argv[2],'w',encoding='utf-8').write(src.replace(old,'if (substr($inner,$afterh3,600) =~ /^'))
PYD4
if [[ -s "$TMP/d4.sh" ]] && ! diff -q "$EXTRACT" "$TMP/d4.sh" >/dev/null; then
  bash "$TMP/d4.sh" "$CANON" > "$TMP/d4.yaml" 2>/dev/null
  n_empty="$(yq -r '.sections[].blocks[]?|select(.type=="subhead")|.essence' "$TMP/d4.yaml" | grep -c '^$')"
  if [[ "$n_empty" -gt 0 ]]; then
    ok "D4 essence の長さ上限窓を復活 → $n_empty 本が無警告で空になる (窓撤去が silent drop 修正だったことの実証)"
  else ng "D4 窓を戻しても空 essence が出ない (前提が崩れている)"; fi
else ng "D4 mutation が空撃ち (python mutate が当たっていない)"; fi

# ★D5 [M1・errata-1] preline() の <b> 逐語保持 (mask 行) を外した mutant extractor → contract から
#   canonical mermaid の <b> 18 tag が ★無警告で消える。 §4 の「mermaid source 行列」は contract 相対ゆえ
#   ★両側同時に痩せて PASS する — 凍結 census (FZ_PRE_TAGS) ★だけ が独立 anchor として撃つ。
#   ★これが独立 ceiling blocking M1 (未承認の第 2 delta) の per-shape 実弾。
python3 - "$EXTRACT" "$TMP/d5.sh" <<'PYD5'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
old='  $s =~ s/<(\\/?)b>/\\x00$1b\\x01/g;\n'
assert src.count(old)==1, ('D5 anchor not unique', src.count(old))
open(sys.argv[2],'w',encoding='utf-8').write(src.replace(old,'  # (mutated: <b> mask removed = fork 元の無置換除去へ退行)\n'))
PYD5
if [[ -s "$TMP/d5.sh" ]] && ! diff -q "$EXTRACT" "$TMP/d5.sh" >/dev/null; then
  bash "$TMP/d5.sh" "$CANON" > "$TMP/d5-draft.yaml" 2>/dev/null
  # head_graph は DRAFT に無いので base から移植する (<b> 喪失だけを単独変数にする・E1 と同型)。
  yq eval-all 'select(fi==0) * {"head_graph": (select(fi==1) | .head_graph)}' "$TMP/d5-draft.yaml" "$BASE" > "$TMP/d5.yaml" 2>/dev/null \
    || cp "$TMP/d5-draft.yaml" "$TMP/d5.yaml"
  nb_base="$(yq -r '[.sections[].blocks[]?|select(.type=="mermaid")|.source_lines[]]|join("")' "$BASE" | grep -o '<b>' | wc -l | tr -d ' ')"
  nb_mut="$(yq -r '[.sections[].blocks[]?|select(.type=="mermaid")|.source_lines[]]|join("")' "$TMP/d5.yaml" | grep -o '<b>' | wc -l | tr -d ' ')"
  if [[ "$nb_base" -eq 9 && "$nb_mut" -eq 0 ]] && bash "$ASM" "$TMP/d5.yaml" "$TMP/d5.html" >/dev/null 2>&1; then
    bash "$INJ" "$BASE_PROSE" "$TMP/d5.html" "$TMP/d5-filled.html" >/dev/null 2>&1
    expect_vfail "D5 mermaid の <b> 逐語保持を外す → FAIL (凍結 pre-inline census が唯一の FAIL 源) [M1]" \
      "$TMP/d5.yaml" "$TMP/d5-filled.html" "census pre-inline"
  else ng "D5 mutation が空撃ち (base <b> 組=$nb_base / mutant=$nb_mut・または assemble 不能)"; fi
else ng "D5 mutation が空撃ち (python mutate が当たっていない)"; fi
# ★D6 群 [M1] ★未対応 inline 資産 の ★literal 閉集合 guard — canonical 複製の mermaid へ per-shape で注入し、
#   extractor が ★fail-loud で止まる (silent 除去 / 曖昧化 して契約から落とさない) ことを撃つ。
#   ★canonical 原本は不触 (N1) = 複製を mutate する。
# ★per-shape で撃つ理由 (errata-1 self-review 是正): guard の判定は ★tag 名 ではなく ★出現 literal 単位
#   (下流の preline mask / <br> 変換 / <pre><code> 抽出 が いずれも ★完全 literal だから) ゆえ、
#   bare <i> 1 発では ★属性付き / ★大文字 / ★numeric entity の穴を証明できない —
#   これらは tag 名 (lc + 属性無視) 判定では ★実際に素通りしていた shape である (実弾 2 shape で実証済)。
# ★D6a = ★負の対照 (guard が ★恒真 FAIL でない = 無改竄 canonical は通り、 census 母体も実測どおり)。
# ★★期待値は hardcode せず ★凍結 census から組み立てる (errata-2 M9): FZ_PRE_CANON_B / FZ_PRE_CANON_BR は
#   「記録であって pin ではない」inert 値だったが、 本 対照 が唯一の consumer になることで
#   ★drift したら落ちる 値へ変わる (かつ 期待値の二重管理を消す)。 ★fz() と同じ読み方 (行末コメント無しの裸値)。
_fzc="$SCRIPT_DIR/spec-origin/self-spec.frozen-census.txt"
_fz() { grep -m1 "^$1=" "$_fzc" | sed "s/^$1=//"; }
_exp_guard="pre inline 資産 (mermaid・閉集合 guard 通過): b=$(_fz FZ_PRE_CANON_B) br=$(_fz FZ_PRE_CANON_BR)"
out="$(bash "$EXTRACT" "$CANON" 2>&1 >/dev/null)"; rc=$?
if [[ $rc -eq 0 && "$out" == *"$_exp_guard"* ]]; then
  ok "D6a 無改竄 canonical は guard を通過 ($_exp_guard・恒真 FAIL でないことの負の対照) [M1/M9]"
else ng "D6a 無改竄 canonical で guard が発火 or census 母体が想定外 (rc=$rc・期待 '$_exp_guard')"; fi
for shape in 'D6:別 tag (<i>):s{(<pre class="mermaid">)}{$1<i>x</i>}:未対応の inline 資産' \
             'D6b:属性付き <b class="x"> (tag 名判定では素通りしていた):s{(<pre class="mermaid">)}{$1<b class="x">H</b>}:未対応の inline 資産' \
             'D6c:大文字 <B> / <BR> (lc 判定では素通りしていた):s{(<pre class="mermaid">)}{$1<B>x</B><BR>}:未対応の inline 資産' \
             'D6d:numeric entity &#60;b&#62; (named のみ判定では素通りしていた):s{(<pre class="mermaid">)}{$1&#60;b&#62;L&#60;/b&#62;}:decode される entity' \
             'D6e:閉じ > を持たない生 < (残余 net):s{(<pre class="mermaid">.*?)(</pre>)}{$1 <foo$2}s:tag 形'; do
  _c="${shape%%:*}"; _r="${shape#*:}"; _what="${_r%%:*}"; _r="${_r#*:}"; _expr="${_r%%:*}"; _reason="${_r#*:}"
  perl -0777 -pe "$_expr" "$CANON" > "$TMP/$_c.html"
  if ! cmp -s "$CANON" "$TMP/$_c.html"; then
    out="$(bash "$EXTRACT" "$TMP/$_c.html" 2>&1 >/dev/null)"; rc=$?
    if [[ $rc -ne 0 && "$out" == *"$_reason"* ]]; then
      ok "$_c mermaid へ $_what → extractor が fail-loud (literal 閉集合 guard) [M1]"
    else ng "$_c $_what が silent 通過 / 別理由で停止 (rc=$rc)"; fi
  else ng "$_c mutation が空撃ち (canonical 複製に注入点が無い)"; fi
done
# ---- D7x/D7y: ★<b> の ★均衡 と ★位置 (errata-2 M8(3)・件数合算 census が素通りさせた 2 shape) ----
# ★塞ぐ穴: 旧 census は open+close を ★合算 (b=18) していたため、 (x) 不均衡 (`</b>`→`<b>` の入替) も
#   (y) 総数保存の relocation (<b> を別の語へ移す) も ★総数 18 のまま で全 gate を素通りした。
#   実害は表示層に及ぶ — 不均衡な <b> は html5lib DOM 実測で ★adoption agency により <pre> の外へ
#   再構築され、 figcaption / provenance footer まで bold 化した文書が全緑で出荷された (verifier 実弾)。
# ★★mutation は ★contract 側 に打つ (生成物側だけを弄ると §4「mermaid source 行列」の ★contract 相対 chk が
#   先に撃ってしまい、 ceiling が示した ★両側同時退行 クラスの再現にならない = 空撃ち同然の偽 PASS になる)。
#   contract を変えて再 build すれば contract も生成物も ★同時に動く — これが本来の shape。
# ★2 shape は ★別の arm が撃つ (per-shape・どちらか 1 発では他方を証明しない):
#   (x) 不均衡      → floor の open/close 別 census (FZ_PRE_TAGS)。 合算 census では総数保存で素通りした。
#   (y) relocation  → oracle の markup 単位 byte 等値 (mermaid_markup_arm)。 open/close とも保存ゆえ census は無力。
build_from_contract() { # $1 = contract  $2 = 出力 filled html → rc
  bash "$ASM" "$1" "$2.raw" >/dev/null 2>&1 || return 1
  bash "$INJ" "$BASE_PROSE" "$2.raw" "$2" >/dev/null 2>&1
}
# ★D7x = contract の mermaid source 内で `</b>` を `<b>` へ入替 (open+close 総数は保存・★均衡が壊れる)。
python3 - "$BASE" "$TMP/d7x.yaml" <<'PYD7X'
import sys
src = open(sys.argv[1], encoding='utf-8').read()
old = '</b>'
assert src.count(old) >= 1, ('D7x anchor 不在', src.count(old))
i = src.index(old)
open(sys.argv[2], 'w', encoding='utf-8').write(src[:i] + '<b>' + src[i + len(old):])
PYD7X
if [[ -s "$TMP/d7x.yaml" ]] && ! diff -q "$BASE" "$TMP/d7x.yaml" >/dev/null; then
  if build_from_contract "$TMP/d7x.yaml" "$TMP/d7x.html"; then
    if [[ "$(pre_b_count "$TMP/d7x.html")" != "$(pre_b_count "$TMP/base-filled.html")" ]]; then
      expect_vfail "D7x contract で </b>→<b> (総数保存の ★不均衡・両側同時) → floor FAIL (open/close 別 census) [M8]" \
        "$TMP/d7x.yaml" "$TMP/d7x.html" "census pre-inline"
    else ng "D7x mutation が open/close 比を変えていない (shape 不成立)"; fi
  else ng "D7x build が失敗 (測定不能)"; fi
else ng "D7x mutation が空撃ち (python mutate が当たっていない)"; fi
# ★D7y = contract の mermaid source 内で 1 組を ★同じ行の別位置 へ移す (open / close とも 1 個ずつ ★保存)。
#   → 件数 census は ★動かない (D7y-pre がそれを実測 pin する) ため、 markup 単位 byte 等値 ★だけ が撃つ。
python3 - "$BASE" "$TMP/d7y.yaml" <<'PYD7Y'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<b>([^<]+ [^<]+)</b>', src)     # 内部に単語境界を持つ 1 組
assert m, 'D7y anchor not found'
head, rest = m.group(1).split(' ', 1)
moved = '%s <b>%s</b>' % (head, rest)           # 開始位置を 1 語後ろへ = ★位置だけ 変える
out = src[:m.start()] + moved + src[m.end():]
assert out != src
assert out.count('<b>') == src.count('<b>') and out.count('</b>') == src.count('</b>'), 'D7y: 件数が保存されていない'
open(sys.argv[2], 'w', encoding='utf-8').write(out)
PYD7Y
if [[ -s "$TMP/d7y.yaml" ]] && ! diff -q "$BASE" "$TMP/d7y.yaml" >/dev/null; then
  if build_from_contract "$TMP/d7y.yaml" "$TMP/d7y.html"; then
    # ★前提 pin: 件数は ★保存されている (= 件数 census では撃てない shape であることの実測)。
    if [[ "$(pre_b_count "$TMP/d7y.html")" == "$(pre_b_count "$TMP/base-filled.html")" ]]; then
      expect_vpass "D7y-pre 同数 relocation は floor を ★通る (両側同時退行 = markup arm が要る前提の実測 pin)" \
        "$TMP/d7y.yaml" "$TMP/d7y.html"
      expect_oracle "D7y contract で <b> を同数のまま relocation (両側同時) → oracle FAIL (markup byte 等値の teeth) [D7/M8]" \
        "$CANON" "$TMP/d7y.html" "$TMP/d7y.yaml" 1 "mermaid DSL の markup が canonical と不一致"
    else ng "D7y mutation が件数を変えている (relocation でなく増減 = shape 不成立)"; fi
  else ng "D7y build が失敗 (測定不能)"; fi
else ng "D7y mutation が空撃ち (python mutate が当たっていない)"; fi

# ============================================================================
echo "--- E 群: collapse (両側同時退行 = 契約と生成物が同時に痩せる形) ---"
# ★rich() を plain() 相当へ退行させた mutant extractor で contract を作り直すと、 contract ↔ 生成物 の
#   相対突合 (§3/§4/§5) は ★両側とも痩せて 恒真 PASS しうる。 ★凍結 census だけ が独立 anchor として撃つ。
python3 - "$EXTRACT" "$TMP/e1.sh" <<'PY'
import sys,re
src=open(sys.argv[1],encoding='utf-8').read()
# rich() 本体をタグ除去する形へ退行させる (folio-aduv 以前の plain() 相当)。
old='''sub rich {
  my ($s) = @_; $s //= "";
  $s =~ s/\\s+/ /g;'''
new='''sub rich {
  my ($s) = @_; $s //= "";
  $s =~ s/<[^>]*>//g;
  $s =~ s/\\s+/ /g;'''
assert src.count(old)==1, src.count(old)
open(sys.argv[2],'w',encoding='utf-8').write(src.replace(old,new))
PY
bash "$TMP/e1.sh" "$CANON" > "$TMP/e1-draft.yaml" 2>/dev/null
if [[ -s "$TMP/e1-draft.yaml" ]]; then
  # head_graph は DRAFT に無いので base から移植する (collapse だけを単独変数にする)。
  yq eval-all 'select(fi==0) * {"head_graph": (select(fi==1) | .head_graph)}' "$TMP/e1-draft.yaml" "$BASE" > "$TMP/e1.yaml" 2>/dev/null \
    || cp "$TMP/e1-draft.yaml" "$TMP/e1.yaml"
  if bash "$ASM" "$TMP/e1.yaml" "$TMP/e1.html" >/dev/null 2>&1; then
    bash "$INJ" "$BASE_PROSE" "$TMP/e1.html" "$TMP/e1-filled.html" >/dev/null 2>&1
    expect_vfail "E1 rich→plain collapse (契約も生成物も同時に痩せる) → 凍結 census が FAIL" \
      "$TMP/e1.yaml" "$TMP/e1-filled.html" "census rich"
  else ok "E1 rich→plain collapse は assemble が abort (前段で止まる = 同じく fail-closed)"; fi
else ng "E1 collapse mutant extractor が出力しない (測定不能)"; fi

# ============================================================================
echo "--- F 群: 手起こし / errata の存在 pin (M7 の commit 前 assert と対) ---"
if [[ "$(yq -r 'has("head_graph")' "$BASE")" == "true" ]]; then ok "F1 contract に head_graph が実在 [M7]"
else ng "F1 contract の head_graph が消えている (extractor full-overwrite の疑い) [M7]"; fi
if grep -qF '完成形 9 specialist agents' "$BASE"; then ok "F2 contract に errata 適用後 literal 「完成形 9」が実在 [M7/E1]"
else ng "F2 errata literal が消えている [M7/E1]"; fi
# ★YAML コメント行 (^\s*#) を除いて判定する — errata の before/after を記録した ★コメント自身が
#   「完成形 8」を含むため、 素の grep は ★恒真 FAIL になる (記録を残すこと自体が検査を壊してはならない)。
if grep -v '^[[:space:]]*#' "$BASE" | grep -qF '完成形 8 specialist agents'; then
  ng "F3 contract の ★データ行 に errata 適用 ★前 の「完成形 8」が残っている (errata 未適用)"
else ok "F3 contract のデータ行に「完成形 8」が無い (errata 適用済・コメントの before 記録は検査対象外)"; fi
if grep -qF '完成形 8 specialist agents' "$CANON"; then ok "F4 canonical は「完成形 8」のまま (N1 = design-intent/ 不触の実測)"
else ng "F4 canonical が変更されている (N1 違反の疑い)"; fi
# ★F5 references arm (手起こし 2/2) の存在 pin — rules.html#req-* が 8 件で claim role。
n_claim="$(yq -r '[.references[] | select(.role=="claim")] | length' "$BASE")"
if [[ "$n_claim" -eq 8 ]]; then ok "F5 rules.html#req-* 照会 arm が 8 件 (手起こし 2/2 の存在 pin)"
else ng "F5 claim role の照会が $n_claim 件 (期待 8)"; fi

# ---- F6..F10: ★受入 oracle (D7) 自身の mutation-kill ----
# ★動機: oracle は canonical を独立 anchor にする ★唯一 の gate (floor は contract 相対ゆえ contract 側の
#   捏造に構造的に全盲)。 その oracle 自身に per-shape の実弾が 1 本も無いと「悉皆・未分類 0」の宣言が
#   ★宣言能力 > 実能力 になる (実際 errata の部分文字列一致 と chrome の text 述語 で fail-open していた)。
# ★F6 空撃ち対照 — 無改竄なら oracle は PASS する (以降の FAIL が mutation 由来だと言えるための前提)。
expect_oracle "F6 無改竄 baseline で oracle が PASS (空撃ち封鎖) [D7]" \
  "$CANON" "$TMP/base-filled.html" "$BASE" 0 "RESULT: PASS"
# ★F7 errata 単位の ★中 へ承認外 delta を同居させる (部分文字列一致の抜け道 shape)。
#   href は据置で ★可視 text だけ捏造する = floor (contract 相対) には ★原理的に 見えないクラス。
python3 - "$BASE" "$TMP/f7.yaml" <<'PYF7'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
old='ADR-0003</a>、 実機検証 framework は'
assert src.count(old)==1, ('F7 anchor not unique', src.count(old))
open(sys.argv[2],'w',encoding='utf-8').write(src.replace(old,'ADR-9999 (捏造)</a>、 実機検証 framework は'))
PYF7
if [[ -s "$TMP/f7.yaml" ]] && ! diff -q "$BASE" "$TMP/f7.yaml" >/dev/null; then
  bash "$ASM" "$TMP/f7.yaml" "$TMP/f7.html" >/dev/null 2>&1
  bash "$INJ" "$BASE_PROSE" "$TMP/f7.html" "$TMP/f7-filled.html" >/dev/null 2>&1
  expect_oracle "F7 errata 単位の中へ承認外 delta を同居 → oracle FAIL (byte 束縛の teeth) [D7]" \
    "$CANON" "$TMP/f7-filled.html" "$TMP/f7.yaml" 1 "errata pin 破れ"
else ng "F7 mutation が空撃ち (python mutate が当たっていない)"; fi
# ★F8 errata site を 2 箇所へ増やす (「バケットが在る」判定では素通りする shape)。
yq '.sections[0].machine_blocks += [{"type":"note",
    "html":"<p>複製 site: §7.2 (完成形 9 specialist agents) を 2 箇所目へ。</p>"}]' "$BASE" > "$TMP/f8.yaml"
if [[ -s "$TMP/f8.yaml" ]] && ! diff -q "$BASE" "$TMP/f8.yaml" >/dev/null; then
  bash "$ASM" "$TMP/f8.yaml" "$TMP/f8.html" >/dev/null 2>&1
  bash "$INJ" "$BASE_PROSE" "$TMP/f8.html" "$TMP/f8-filled.html" >/dev/null 2>&1
  expect_oracle "F8 errata site を 2 箇所へ増殖 → oracle FAIL (1 site pin の teeth) [D7]" \
    "$CANON" "$TMP/f8-filled.html" "$TMP/f8.yaml" 1 "errata pin 破れ"
else ng "F8 mutation が空撃ち (yq mutate が当たっていない)"; fi
# ★F9 生成物から ★本文見出し の text を丸ごと落とす (text 述語 '^§\d' が TOC 由来として吸っていた shape)。
perl -0777 -pe 's{(<h3[^>]*>)§3\.3 JavaScript governance(</h3>)}{$1$2}' \
  "$TMP/base-filled.html" > "$TMP/f9.html"
if ! cmp -s "$TMP/base-filled.html" "$TMP/f9.html"; then
  expect_oracle "F9 生成物から本文見出し text を削除 → oracle FAIL (chrome 領域駆動分類の teeth) [D7]" \
    "$CANON" "$TMP/f9.html" "$BASE" 1 "[C-ONLY] §3.3 JavaScript governance"
else ng "F9 mutation が空撃ち (生成物に対象見出しが無い)"; fi
# ★F10 canonical 側の chrome を 1 行増やす (凍結 pin CHROME_PIN が恒真でないことの実弾)。
#   ★canonical 原本は不触 (N1) — ★複製 を mutate する。
perl -0777 -pe 's{(<li><a href="#s9-bindings">)}{<li><a href="#s99-bogus">\xc2\xa7 99. bogus</a></li>$1}' \
  "$CANON" > "$TMP/f10.html"
if ! cmp -s "$CANON" "$TMP/f10.html"; then
  expect_oracle "F10 canonical の TOC 行を 1 本増やす → oracle FAIL (chrome 件数 凍結 pin の teeth) [D7]" \
    "$TMP/f10.html" "$TMP/base-filled.html" "$BASE" 1 "chrome 領域の件数が凍結 pin と不一致"
else ng "F10 mutation が空撃ち (canonical 複製に TOC 行が無い)"; fi
# ---- F11..F16: gen_allow (生成物にだけ在ってよい単位) の ★tightness 実弾 ----
# ★動機: F6..F10 は canonical 側の欠落 / errata / chrome 件数しか撃たない。 gen_allow 側の述語が wildcard や
#   ★接頭辞 (startswith) だと「その形さえ持てば canonical に対応物の無い ★任意の捏造」が分類済へ落ち、
#   「未分類 0」が ★宣言能力 > 実能力 になる (実測 fail-open だった 3 クラスを以下で per-shape に撃つ)。
# ★F11 fold summary の ★章帰属 (mf-label) を付け替える — wildcard 述語 '^…… .* \d+ 件$' が吸っていた shape。
perl -0777 -pe 's{<span class="mf-label">§1\. [^<]*</span>}{<span class="mf-label">§9. 別章 の地の文・運用説明・rationale</span>}' \
  "$TMP/base-filled.html" > "$TMP/f11.html"
if ! cmp -s "$TMP/base-filled.html" "$TMP/f11.html"; then
  expect_oracle "F11 fold の章帰属 (mf-label) を付替え → oracle FAIL (fold 単位 SSoT 完全一致の teeth) [D7]" \
    "$CANON" "$TMP/f11.html" "$BASE" 1 "[G-ONLY] 機械向けの詳細（原文そのまま） §9. 別章"
  expect_vfail "F11b 同 mutation → floor も FAIL (mf-label 列の逐値突合)" "$BASE" "$TMP/f11.html" "mf-label 列"
else ng "F11 mutation が空撃ち (生成物に §1 の mf-label が無い)"; fi
# ★F12 fold summary の ★件数 (mf-count) を改竄 — 同じ wildcard が吸っていた 2 つ目の shape (per-shape MK)。
perl -0777 -pe 's{<span class="mf-count">3 件</span>}{<span class="mf-count">99 件</span>}' \
  "$TMP/base-filled.html" > "$TMP/f12.html"
if ! cmp -s "$TMP/base-filled.html" "$TMP/f12.html"; then
  expect_oracle "F12 fold の件数 (mf-count) を改竄 → oracle FAIL (件数も SSoT 導出で束縛) [D7]" \
    "$CANON" "$TMP/f12.html" "$BASE" 1 "rationale 99 件"
  expect_vfail "F12b 同 mutation → floor も FAIL (mf-count 列の逐値突合)" "$BASE" "$TMP/f12.html" "mf-count 列"
else ng "F12 mutation が空撃ち (生成物に mf-count 「3 件」が無い)"; fi
# ★F13 reader-chip の ★接頭辞 だけを持つ捏造段落 — startswith('想定読者') が吸っていた shape。
perl -0777 -pe 's{(<div class="page")}{<p>想定読者 まったく別の読者像 (捏造)</p>$1}' \
  "$TMP/base-filled.html" > "$TMP/f13.html"
if ! cmp -s "$TMP/base-filled.html" "$TMP/f13.html"; then
  expect_oracle "F13 「想定読者」接頭辞を持つ捏造段落を注入 → oracle FAIL (完全一致化の teeth) [D7]" \
    "$CANON" "$TMP/f13.html" "$BASE" 1 "[G-ONLY] 想定読者 まったく別の読者像 (捏造)"
else ng "F13 mutation が空撃ち"; fi
# ★F14 provenance の ★接頭辞 だけを持つ捏造段落 — startswith('機械SSoT: ') が吸っていた shape。
perl -0777 -pe 's{(<div class="page")}{<p>機械SSoT: 捏造された別 contract path.yaml</p>$1}' \
  "$TMP/base-filled.html" > "$TMP/f14.html"
if ! cmp -s "$TMP/base-filled.html" "$TMP/f14.html"; then
  expect_oracle "F14 「機械SSoT: 」接頭辞を持つ捏造段落を注入 → oracle FAIL (逐値集合 + anchor 正規表現) [D7]" \
    "$CANON" "$TMP/f14.html" "$BASE" 1 "[G-ONLY] 機械SSoT: 捏造された別 contract path.yaml"
else ng "F14 mutation が空撃ち"; fi
# ---- F15/F16: 文書 identity (title / subtitle) の捏造 ----
# ★floor は contract 相対 (cover h1 == .meta.title) ゆえ ★原理的に 全盲、 凍結 census も title を持たない。
#   canonical の doc-header は chrome として ★multiset ごと差し引かれる ため、 値束縛が無いと sweep からも消える
#   (実測: verify rc=0 / oracle rc=0 で捏造タイトルが全 gate を素通りした)。 ★canonical を独立 anchor にする
#   本 oracle の doc-header 値 assert が唯一の FAIL 源 = per-shape (title / subtitle) で 2 発撃つ。
for pair in 'F15:title:folio self-spec (捏造タイトル)' \
            'F16:subtitle:v9.9.9 · status: draft · 捏造サブタイトル'; do
  _c="${pair%%:*}"; _rest="${pair#*:}"; _k="${_rest%%:*}"; _v="${_rest#*:}"
  K="$_k" V="$_v" yq '.meta[strenv(K)] = strenv(V)' "$BASE" > "$TMP/$_c.yaml"
  if [[ -s "$TMP/$_c.yaml" ]] && ! diff -q "$BASE" "$TMP/$_c.yaml" >/dev/null; then
    bash "$ASM" "$TMP/$_c.yaml" "$TMP/$_c.html" >/dev/null 2>&1
    bash "$INJ" "$BASE_PROSE" "$TMP/$_c.html" "$TMP/$_c-filled.html" >/dev/null 2>&1
    expect_oracle "$_c meta.$_k を捏造した contract → oracle FAIL (chrome:doc-header の値束縛) [D7/M3]" \
      "$CANON" "$TMP/$_c-filled.html" "$TMP/$_c.yaml" 1 "chrome:doc-header の値が contract meta と不一致"
  else ng "$_c mutation が空撃ち (yq mutate が当たっていない)"; fi
done
# ---- F17/F18: identity の ★残り shape (head meta 軸) の捏造 ----
# ★F15/F16 は doc-header (title / subtitle) ★2 shape しか閉じない。 同じ「両側とも contract に self-reference」
#   構造は cover-meta / cover-eyebrow / reader-chip にも在り、 ★実測で .meta.version / .meta.status を捏造しても
#   verify rc=0 / oracle rc=0 だった (生成物は「v9.9.9」を名乗りつつ subtitle は「v1.2.0 · status: stable」= 文書内部が
#   矛盾したまま両 gate 緑)。 canonical head の folio-version / folio-status を独立 anchor にした値束縛が唯一の
#   FAIL 源 = ★per-shape で 2 発撃つ (1 instance の実弾は構造差のある instance の穴を証明しない)。
for pair in 'F17:version:9.9.9' 'F18:status:draft'; do
  _c="${pair%%:*}"; _rest="${pair#*:}"; _k="${_rest%%:*}"; _v="${_rest#*:}"
  K="$_k" V="$_v" yq '.meta[strenv(K)] = strenv(V)' "$BASE" > "$TMP/$_c.yaml"
  if [[ -s "$TMP/$_c.yaml" ]] && ! diff -q "$BASE" "$TMP/$_c.yaml" >/dev/null; then
    bash "$ASM" "$TMP/$_c.yaml" "$TMP/$_c.html" >/dev/null 2>&1
    bash "$INJ" "$BASE_PROSE" "$TMP/$_c.html" "$TMP/$_c-filled.html" >/dev/null 2>&1
    expect_oracle "$_c meta.$_k を捏造した contract → oracle FAIL (canonical head folio-* meta の値束縛) [D7/M3]" \
      "$CANON" "$TMP/$_c-filled.html" "$TMP/$_c.yaml" 1 "head meta identity が canonical と不一致"
  else ng "$_c mutation が空撃ち (yq mutate が当たっていない)"; fi
done
# ---- F19: 人間層 block の ★順序 (旧 docstring が「floor が担う」と誤帰属していた軸) ----
# ★floor は contract ↔ 生成物 の ★相対 突合ゆえ、 contract 側で block 順序を入れ替えると ★両側が同時に動いて
#   必ず PASS する (oracle が塞ぐために作られた「両側同時退行」と同じ構造の穴が順序軸に開いていた)。
#   実弾: §3.3 / §3.4 の subhead を contract 内で入替 → 生成物の h3 順が canonical と食い違う。
yq '.sections[3].blocks = [.sections[3].blocks[0], .sections[3].blocks[1], .sections[3].blocks[2],
                           .sections[3].blocks[3], .sections[3].blocks[5], .sections[3].blocks[4]]' \
   "$BASE" > "$TMP/f19.yaml"
if [[ -s "$TMP/f19.yaml" ]] && ! diff -q "$BASE" "$TMP/f19.yaml" >/dev/null; then
  bash "$ASM" "$TMP/f19.yaml" "$TMP/f19.html" >/dev/null 2>&1
  bash "$INJ" "$BASE_PROSE" "$TMP/f19.html" "$TMP/f19-filled.html" >/dev/null 2>&1
  expect_oracle "F19 contract 側で §3.3/§3.4 を入替 → oracle FAIL (人間層 order arm の teeth) [D7]" \
    "$CANON" "$TMP/f19-filled.html" "$TMP/f19.yaml" 1 "人間層 block の順序が canonical と不一致"
  # ★F19b 前提 pin: 同 mutation で floor は ★PASS する (= 順序軸を floor に移譲できない根拠の実測)。
  #   ここが将来 FAIL に転じたら floor が順序 teeth を得た合図 = oracle 側 arm の重複を再検討する signal。
  expect_vpass "F19b 同 mutation で floor は PASS (順序を floor へ移譲できない前提の実測 pin)" \
    "$TMP/f19.yaml" "$TMP/f19-filled.html"
else ng "F19 mutation が空撃ち (yq mutate が当たっていない)"; fi
# ---- F20: ★層帰属 (人間層 → 機械層 demote) の ★両側同時退行 (errata-1 M2) ----
# ★塞ぐ穴: sweep 本体は ★text だけ の multiset ゆえ、 章 essence を contract 側で machine_blocks へ ★移す と
#   text は生成物のどこかに在り続ける = ★差分に出ない。 floor も contract 相対ゆえ両側同時に痩せて PASS する。
#   実弾: §0 の essence を空にし、 同じ text を機械層 block として足す (canonical では ★人間層 の要旨)。
yq '.sections[0].machine_blocks += [{"type":"prose","html":("<p>" + .sections[0].essence + "</p>")}]
    | .sections[0].essence = ""' "$BASE" > "$TMP/f20.yaml"
if [[ -s "$TMP/f20.yaml" ]] && ! diff -q "$BASE" "$TMP/f20.yaml" >/dev/null; then
  bash "$ASM" "$TMP/f20.yaml" "$TMP/f20.html" >/dev/null 2>&1
  bash "$INJ" "$BASE_PROSE" "$TMP/f20.html" "$TMP/f20-filled.html" >/dev/null 2>&1
  expect_oracle "F20 章 essence を機械層へ demote (両側同時) → oracle FAIL (層帰属 arm の teeth) [D7/M2]" \
    "$CANON" "$TMP/f20-filled.html" "$TMP/f20.yaml" 1 "層帰属 (人間層 / 機械層) が canonical と不一致"
  # ★F20b 同 mutation を floor 側でも撃つ (契約非依存 pin FZC_SECTION_SE の teeth・oracle と二重化)。
  expect_vfail "F20b 同 mutation → floor も FAIL (非空 section 1 行要約の契約非依存 census)" \
    "$TMP/f20.yaml" "$TMP/f20-filled.html" "非空の section 1 行要約"
else ng "F20 mutation が空撃ち (yq mutate が当たっていない)"; fi
# ---- F21/F22/F23: ★照会 (references) の canonical anchor 束縛 (errata-1 M4) ----
# ★塞ぐ穴: references 33 本は これまで ★contract 自己参照 bucket ('ref-chip' 述語が contract の token/doc/role
#   から集合を作って生成物と照合するだけ) で、 canonical の a[href] anchor が ★実在するのに使われていなかった。
#   ゆえ ★token 捏造 / ★role 付替え / ★1 本削除 は「contract も生成物も同時に動く」ため floor / oracle とも
#   fail-open だった。 ★3 shape は構造が違う (値の書換 / 分類の書換 / 集合の縮小) ため ★per-shape で 3 発撃つ。
for spec in 'F21:token 捏造:(.references[] | select(.token=="ADR-0003") | .token) = "ADR-9999":[★余剰] contract に在り canonical anchor に無い: (ADR-9999, rationale)' \
            'F22:role 付替え:(.references[] | select(.token=="ADR-0003") | .role) = "claim":[★余剰] contract に在り canonical anchor に無い: (ADR-0003, claim)' \
            'F23:1 本削除:del(.references[] | select(.token=="ADR-0003")):[★欠落] canonical anchor に在り contract に無い: (ADR-0003, rationale)'; do
  _c="${spec%%:*}"; _r="${spec#*:}"; _what="${_r%%:*}"; _r="${_r#*:}"; _expr="${_r%%:\[*}"; _reason="[${_r#*:\[}"
  yq "$_expr" "$BASE" > "$TMP/$_c.yaml"
  if [[ -s "$TMP/$_c.yaml" ]] && ! diff -q "$BASE" "$TMP/$_c.yaml" >/dev/null; then
    bash "$ASM" "$TMP/$_c.yaml" "$TMP/$_c.html" >/dev/null 2>&1
    bash "$INJ" "$BASE_PROSE" "$TMP/$_c.html" "$TMP/$_c-filled.html" >/dev/null 2>&1
    expect_oracle "$_c 照会の$_what → oracle FAIL (canonical a[href] 集合等値の teeth) [D7/M4]" \
      "$CANON" "$TMP/$_c-filled.html" "$TMP/$_c.yaml" 1 "$_reason"
  else ng "$_c mutation が空撃ち (yq mutate が当たっていない)"; fi
done

# ---- F24/F25: ★既存 marker の ★複製注入 (consumer 乗っ取り・errata-1 M5) ----
# ★塞ぐ穴: floor の bucket 系 chk も oracle の gen_allow も「値集合 membership」判定ゆえ、 ★既存 marker を
#   もう 1 個 足す 注入を吸収していた。 machine_blocks へ <div class="meta"> を 1 個注入すると consumer
#   (.claude-plugin/bin/folio の folio_extract_summary = raw grep '<div class="meta">') が拾う ★文書 summary を
#   乗っ取れる (= inventory / prime digest という ★派生 SSoT が捏造値に置き換わる end-to-end 経路)。
# ★★payload クラスの区別 (errata-2 M10・旧記述の false record 是正・両クラスとも worker 実測):
#   - ★bucket 吸収 text (例 .glossary[].def の ★逐語) を載せた場合 → D7 の ★未分類 arm は ★発火しない
#     (生成物にのみ在る = 0 件)。 errata-1 以前は floor / repro-build / D7 oracle が ★全緑 のまま乗っ取れた
#     = 「全緑で乗っ取り」が成立するのは ★この payload クラス だけ。 現在は M5 の 3 arm が撃つ。
#   - ★非吸収 text (旧 payload の「v9.9.9 · status: hijacked …」) → D7 の ★既存 未分類 arm が先に撃つ
#     (errata-1 以前でも赤)。 旧コメントの「全緑のまま乗っ取れた」は ★当該 payload については不成立だった。
#   ゆえ F24 の payload を ★吸収形へ差し替え、 記述とコードを一致させる (F24/F24b は payload 非依存で
#   発火するため teeth は失われない)。 F24c が「この payload では未分類 arm が沈黙する」ことを実測 pin する。
_absorb="$(yq -r '.glossary[0].def' "$BASE")"
ABS="$_absorb" yq '.sections[0].machine_blocks += [{"type":"prose",
    "html":("<div class=\"meta\">" + strenv(ABS) + "</div>")}]' "$BASE" > "$TMP/f24.yaml"
if [[ -s "$TMP/f24.yaml" ]] && ! diff -q "$BASE" "$TMP/f24.yaml" >/dev/null; then
  if bash "$ASM" "$TMP/f24.yaml" "$TMP/f24.html" >/dev/null 2>&1; then
    bash "$INJ" "$BASE_PROSE" "$TMP/f24.html" "$TMP/f24-filled.html" >/dev/null 2>&1
    # ★前提 pin: 注入は ★実際に consumer 経路へ届いている (空撃ちでないことを consumer と同じ raw grep で示す)。
    if [[ "$(grep -c '<div class="meta"' "$TMP/f24-filled.html")" -ge 1 ]]; then
      expect_vfail "F24 machine_blocks へ div.meta 注入 → floor FAIL (class-token 閉 allowlist) [M5]" \
        "$TMP/f24.yaml" "$TMP/f24-filled.html" "class-token 機械的網羅"
      expect_vfail "F24b 同 mutation → floor FAIL (consumer 一次 selector の negative assert) [M5]" \
        "$TMP/f24.yaml" "$TMP/f24-filled.html" "consumer 一次 selector"
      # ★F24c [M10] payload クラスの ★実測 pin: 本 payload (bucket 吸収 text) では D7 の ★未分類 arm が
      #   ★沈黙する (= errata-1 以前なら「全緑で乗っ取り」が成立していた payload クラスであることの証拠)。
      #   現在 oracle が赤いのは ★M5 が新設した bucket 件数 pin ★だけ が撃つため。 この 2 点を同時に assert して
      #   「どの arm が実際に守っているか」を記述でなく ★実測 で固定する (false record の再演封鎖)。
      _o="$(python3 "$ORACLE" "$CANON" "$TMP/f24-filled.html" "$TMP/f24.yaml" "$BASE_PROSE" 2>&1)"; _orc=$?
      if [[ "$_orc" -ne 0 ]] \
         && grep -qE '生成物にのみ在る +=  *0 件' <<< "$_o" \
         && grep -qE 'canonical にのみ在る +=  *0 件' <<< "$_o" \
         && grep -qF '分類済 bucket の件数が凍結 pin と不一致' <<< "$_o"; then
        ok "F24c 吸収 payload では D7 未分類 arm は沈黙し bucket 件数 pin だけが撃つ (M5 の teeth 帰属の実測) [M10]"
      else ng "F24c payload クラスの前提が崩れている (oracle rc=$_orc・未分類 0 / bucket pin 発火の同時成立が不成立)"; fi
    else ng "F24 mutation が空撃ち (生成物に div.meta が現れない)"; fi
  else ok "F24 div.meta 注入は assemble が abort (前段で止まる = 同じく fail-closed)"; fi
else ng "F24 mutation が空撃ち (yq mutate が当たっていない)"; fi
# ★F25 ★別 shape の複製注入 — 既存 bucket (reader-chip) と ★同一 text を機械層へ足す。 class token は
#   全て allowlist 内 (= F24 の arm は発火しない) ため、 ★oracle の bucket 件数 凍結 pin ★だけ が撃つ。
RC_TXT="想定読者: $(yq -r '.meta.reader' "$BASE")"
RC="$RC_TXT" yq '.sections[0].machine_blocks += [{"type":"prose","html":("<p>" + strenv(RC) + "</p>")}]' \
  "$BASE" > "$TMP/f25.yaml"
if [[ -s "$TMP/f25.yaml" ]] && ! diff -q "$BASE" "$TMP/f25.yaml" >/dev/null; then
  bash "$ASM" "$TMP/f25.yaml" "$TMP/f25.html" >/dev/null 2>&1
  bash "$INJ" "$BASE_PROSE" "$TMP/f25.html" "$TMP/f25-filled.html" >/dev/null 2>&1
  expect_oracle "F25 既存 bucket (reader-chip) と同一 text を複製注入 → oracle FAIL (bucket 件数 凍結 pin) [D7/M5]" \
    "$CANON" "$TMP/f25-filled.html" "$TMP/f25.yaml" 1 "分類済 bucket の件数が凍結 pin と不一致"
else ng "F25 mutation が空撃ち (yq mutate が当たっていない)"; fi

# ============================================================================
echo "--- G 群: conformance pin (重い arm を 1 回だけ実走・honest skip の空洞化封鎖) ---"
if SKIP_REPRO= bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" >/dev/null 2>&1; then
  ok "G1 repro-build arm ON (SKIP_REPRO 解除) でも baseline が PASS (再 build byte-identity)"
else ng "G1 repro-build arm ON で baseline が FAIL (決定性の破れ)"; fi
# ★G2 [errata-1 M3] repro-build arm の ★sub-pin 実走 (独立 ceiling blocking M3 の対)。
#   ★塞いだ穴: G1 は「arm ON で baseline が PASS する」しか見ておらず、 ★arm 自体を削除しても suite は緑のまま
#   だった (= G 群 repro-build arm に ★実弾 0)。 共有 seed lib/test-repro-pins.sh の 4 sub-pin
#   (a) EOF 1-byte 追記 → BYTE-DIFF / (b) 時刻のみ差替 → [OK] (過 strict でない) /
#   (c) prose 不在 → exit 2 TOOLERR (測定系 error と gate 判定の分離) / (d) 非 ts footer 改竄 → BYTE-DIFF (過緩でない)
#   を 1 回だけ実走する。 (b)+(d) が正規化 regex を両側から挟む = mutation-kill 相当。
#   ★render は走らない (SELF_SPEC_SKIP_RENDER=1 を suite 冒頭で export 済 = gate F 不走)。
if repro_pins "$VER" self-spec "$BASE" "$BASE_PROSE" "$ASM" "$INJ" --filled "$BASE_PROSE"; then
  ok "G2 repro-build conformance (a)-(d) 全 pass [M3]"
else ng "G2 repro-build conformance (a)-(d) 逸脱 [M3]"; fi

# ============================================================================
# ★宣言集合 vs 実行集合 (silent skip 封鎖・範型 CASEPIN と同型)。
DECLARED=(BASE0 A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 B1 B1b B2 B2b B3 B4 B5 B6 B7 B8 B9 B10 B11
          C1 C1a C1b C1c C1d C1e C1f C1g C2 C2b C3 D1 D2 D3 D4 D5 D6 D6a D6b D6c D6d D6e D7x D7y D7y-pre
          E1 F1 F2 F3 F4 F5 F6 F7 F8 F9 F10
          F11 F11b F12 F12b F13 F14 F15 F16 F17 F18 F19 F19b F20 F20b F21 F22 F23 F24 F24b F24c F25 G1 G2)
miss=""
for d in "${DECLARED[@]}"; do
  hit=0; for s in "${SEEN[@]}"; do [[ "$s" == "$d" ]] && hit=1; done
  [[ "$hit" -eq 1 ]] || miss+="$d "
done
# ★B1 は 4 shape を同一 token で回すため SEEN に 4 回入る (宣言は 1)。 欠落だけを見る。
if [[ -n "$miss" ]]; then echo "  [FAIL] CASEPIN 宣言したが実行されていない case: $miss"; fail=$((fail+1));
else echo "  [PASS] CASEPIN 宣言 ${#DECLARED[@]} case が全て実行された (silent skip 封鎖)"; pass=$((pass+1)); fi

echo "=== test-adversarial-self-spec: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
