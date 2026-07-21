#!/usr/bin/env bash
# test-adversarial-relations-census.sh — 政策 A (folio-uryh / ADR-0053 §2.6 relations arm) の敵対 test。
#
# verify-relations.sh §10b の ★凍結 census (spec-origin/relations.frozen-census.txt) が「両側 contract 由来」の
# §4/§5/§11 と ★独立な anchor として効いていることを red→green で固定する。 test-adversarial-spec.sh (rules) /
# test-adversarial-verification.sh の census 群と同型 fork。
#
#   (a) CEN 群     = per-shape mutation-kill (各 census arm が実弾で [FAIL] に落ちる)。
#   (b) CEN-rel 群 = ★relations 固有 3 軸 (spec-machine-list / li.mli / grow) の per-shape MK。
#                    契約 folio-uryh の hard acceptance「再抽出 vacuous-green backstop」の非空撃ち証明。
#                    ★shape は 4 クラス: 素の drop (CEN-rel1/2/3) と ★laundering 3 種 — comment 復元
#                    (CEN-rel*L) / inert <template> 復元 (CEN-rel2T) / ★重複属性 decoy (CEN-rel*D = HTML
#                    Standard の first-wins を突く属性 semantics クラス)。 ★非計上の経路が互いに別ゆえ
#                    1 クラスの実弾は他クラスの穴を証明しない (per-shape MK 規律)。
#   (c) M-SELFCMP  = RELATIONS_ORIGIN_HTML=mutated の ★自己比較でも census が生きる (ORIG 非消費の証明)。
#                    ★laundering 版を含む (自己比較 × laundering の ★同時沈黙 が最悪形ゆえ per-shape に撃つ)。
#   (d) SNAPPIN    = snapshot 完全性 + census 不在の fail-closed + census mutate で arm 発火
#                    + ★heal provenance の tracked pin (SNAPPIN-4 本文捏造 0 / SNAPPIN-5 再実行可能性)。
#   (e) COLLAPSE   = extractor collapse で contract と生成物が ★同時退行しても census が捕捉する。
#   (f) XARM/LIVEPIN = 3 関数 (strip_inert/census_dump/h_inline) の cross-arm byte-identity と
#                    「census が HTML_LIVE を消費しない」topology の tracked pin。
#                    ★relations arm は当該 python 3 関数の ★第 3 の copy ゆえ、 片 arm ドリフトを撃つ XARM が
#                    無いと relations copy だけが腐っても既存 suite (verify-spec vs verify-verification) は緑のまま。
#   (g) CIWIRE     = ★ci.yml 結線の tracked pin (relations 6 arm が blocking / floor step と base arm への
#                    独立 oracle 明示注入)。 ★env 欠落は「緑のまま teeth が消える」silent fail-open ゆえ撃つ。
#
# ★relations 非該当軸 (jq -S census / JSON-LD folio:stakeholders) の MK は ★作らない (census arm ごと不在 =
#   空撃ち MK 禁止・relations.frozen-census.txt header 参照)。
# ★0 値軸 (delta / escape literal / table-cell / caption) は ★注入方向 (0→1) で撃つ (減らせない軸を
#   「MK が書けないから」と撤去すると当該領域への捏造混入が無被覆になる)。
#
# ★reason 照合は [FAIL] 行 anchor + fixed-string の 2 段: census chk ラベルは [OK] 行にも出るため、 素の
#   substring 照合は「別 gate の巻き添え FAIL + 当該 census は [OK]」を緑と誤判定する (false-pass)。
#
# usage: test-adversarial-relations-census.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-relations.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-relations.sh"
BASE="$SCRIPT_DIR/contract/folio-relations.spec.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-relations.prose.yaml"
SNAP="$SCRIPT_DIR/spec-origin/relations.origin.html"
CENSUS="$SCRIPT_DIR/spec-origin/relations.frozen-census.txt"
# ★SNAPPIN 用 transient verify copy: census file path を差し替えた verify-relations を ★SCRIPT_DIR 直下 に置く
#   (tmp へ copy すると SCRIPT_DIR が動き lib/ 解決に失敗して exit 2 = 「arm 不在」と区別できない偽 RED になる)。
PIN_VER="$SCRIPT_DIR/.census-pin-verify-relations.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$PIN_VER"' EXIT
pass=0; fail=0
# repro-build arm / gate F (playwright) は bulk case では honest skip (arm 未 skip は assemble 再 build で timeout)。
export SKIP_REPRO="${SKIP_REPRO:-1}"
export SKIP_RENDER="${SKIP_RENDER:-1}"
declare -a SEEN_IDS=()
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); SEEN_IDS+=("${1%% *}"); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); SEEN_IDS+=("${1%% *}"); }

for f in "$ASM" "$INJ" "$VER" "$BASE" "$BASE_PROSE" "$SNAP" "$CENSUS"; do
  [[ -f "$f" ]] || { echo "FATAL: 前提 file 不在: $f" >&2; exit 2; }
done

# 健全 baseline を一度生成 (assemble + inject。 fix/build は census 軸に影響しない = 実測確認済ゆえ不要)。
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗" >&2; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗" >&2; exit 2; }

echo "relations census/collapse adversarial (政策A・folio-uryh):"

# ============================================================================
# (a) CEN 群 — 各 census arm の per-shape mutation-kill
# ============================================================================
cen_mut() { # label perl-expr reason
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/cen.html"
  if diff -q "$TMP/base-filled.html" "$TMP/cen.html" >/dev/null; then
    ng "$1 (mutation が生成物を変えていない = ★空撃ち。 selector が実 DOM と不一致の疑い)"; return
  fi
  # ★ORIG は healed snapshot を明示注入する (CI の landed-canonical arm と ★同一構成)。 既定 ORIG は pre-flip
  #   live canonical ゆえ §11 が常時 RED になり、 rc!=0 が恒真化して teeth が reason grep だけに痩せる。
  local out rc; out="$(RELATIONS_ORIGIN_HTML="$SNAP" bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then ok "$1"
  else ng "$1 (exit=$rc / [FAIL] 行に census reason '$3' 不発 = 当該 census arm 無効化の回帰)"; fi
}

# --- navigable id census (count / SET / D-* 混入 / 重複) ---
cen_mut "CEN-id1 ★navigable id 1 個剥奪 (30→29) → census navigable id 総数 FAIL" \
  's# id="s6-refs"##' "census navigable id: 総数"
cen_mut "CEN-id2 ★id rename (req-rel-001→RENAMED・count 30 保存) → census id-rename SET FAIL (count census は素通る)" \
  's#id="req-rel-001"#id="req-rel-RENAMED"#' "census id-rename SET"
cen_mut "CEN-id3 ★生成物への D-* id 混入 (delta 印の anchor 集合汚染) を fail-closed 検査が捕捉" \
  's{(<span class="term")}{<span id="D-FAKE-1"></span>${1}}' "D-* id == 0"
cen_mut "CEN-id4 ★既存 id の複製注入 (unique 30 保存・anchor hijack) を重複 chk が FAIL" \
  's{(<body[^>]*>)}{${1}<div id="s6-refs"></div>}' "census navigable id: 重複 0"

# --- rich 資産 occurrence (per-shape: a.xref / span.term / delta は DOM 形状が別クラス) ---
cen_mut "CEN-rich1 ★a.xref 1 個剥奪 (8→7) → census rich a.xref FAIL" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
cen_mut "CEN-rich2 ★span.term 1 個剥奪 (5→4) → census rich span.term FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
# ★relations の frozen delta は 0 ゆえ ★注入方向 (0→1) で撃つ (減らせない軸の teeth)。
cen_mut "CEN-rich3 ★ins.delta 注入 (0→1) → census rich ins|del.delta FAIL (注入方向 teeth)" \
  's{(<body[^>]*>)}{${1}<ins class="delta" data-delta-id="D-FAKE-2">zz</ins>}' "census rich: ins|del.delta"
cen_mut "CEN-rich4 ★delta-id 注入 → census delta-id SET 余剰 FAIL (空 SET の注入方向 teeth)" \
  's{(<body[^>]*>)}{${1}<del class="delta" data-delta-id="D-FAKE-3">zz</del>}' "census delta-id SET: 余剰"

# --- escape / double-escape (frozen 0 軸ゆえ全て注入方向) ---
# ★注入 anchor は <td> の text node (relations は人間層 prose block が ★0 本 = spec-prose selector が不在。
#   census の escape literal 軸は ★text node 限定計数ゆえ属性値でなく本文へ置く必要がある)。
cen_mut "CEN-esc1 ★td 本文へ &lt;a class=\"xref\" literal 注入 (0→1) → census escape FAIL" \
  's#(<td>)#${1}\&lt;a class="xref"#' "census escape"
cen_mut "CEN-esc2 ★人間層 <code> を二重 escape (&lt;code 0→1) → census double-escape &lt;code FAIL" \
  's#(<pre data-component="spec-code">)<code>#${1}\&lt;code\&gt;#' "census double-escape: &lt;code"
cen_mut "CEN-esc3 ★td 本文へ &lt;span literal 注入 (0→1) → census double-escape &lt;span FAIL" \
  's#(<td>)#${1}\&lt;span#' "census double-escape: &lt;span"

# --- generic inline (code/span) の人間層 region 別 occurrence ---
cen_mut "CEN-gen1 ★pre 内 human <code> wrapper 剥奪 (rest 3→2) → census generic <code> rest FAIL" \
  's#(<pre data-component="spec-code">)<code>(.*?)</code>#${1}${2}#s' "census generic: 人間層 <code> rest"
cen_mut "CEN-gen2 ★td へ <code> 注入 (table-cell 0→1) → census generic <code> table-cell FAIL (注入方向 teeth)" \
  's#(<td>)#${1}<code>ZZINJ</code>#' "census generic: 人間層 <code> table-cell"
cen_mut "CEN-gen3 ★figcaption へ <code> 注入 (caption 0→1) → census generic <code> caption FAIL (注入方向 teeth)" \
  's#(<figcaption>)#${1}<code>ZZINJ</code>#' "census generic: 人間層 <code> caption"
cen_mut "CEN-gen4 ★td へ <span> 注入 (table-cell 0→1) → census generic <span> table-cell FAIL (注入方向 teeth)" \
  's#(<td>)#${1}<span>ZZINJ</span>#' "census generic: 人間層 <span> table-cell"
cen_mut "CEN-gen5 ★figcaption へ <span> 注入 (caption 0→1) → census generic <span> caption FAIL (注入方向 teeth)" \
  's#(<figcaption>)#${1}<span>ZZINJ</span>#' "census generic: 人間層 <span> caption"

# ============================================================================
# (b) CEN-rel 群 — ★relations 固有 3 軸 (再抽出 vacuous-green backstop) の per-shape MK。
#   契約 folio-uryh の hard acceptance「非空撃ちは『1 項 drop → floor FAIL』の per-shape MK で pin」の実弾。
#   ★3 軸は DOM 構造クラスが別 (ul 容器 / li 項目 / div 語) ゆえ 1 本の実弾では他 2 本の穴を証明しない。
# ============================================================================
cen_mut "CEN-rel1 ★spec-machine-list 1 本 drop (6→5) → frozen floor spec-machine-list FAIL" \
  's#<ul data-component="spec-machine-list"#<ul data-component="ZZDROP"#' "frozen floor: spec-machine-list"
cen_mut "CEN-rel2 ★li.mli 1 項 drop (25→24) → frozen floor li.mli FAIL (★再抽出で消える手起こし項の backstop)" \
  's#<li class="mli">#<li class="ZZDROP">#' "frozen floor: li.mli"
cen_mut "CEN-rel3 ★grow 1 本 drop (20→19) → frozen floor grow FAIL" \
  's#<div class="grow">#<div class="ZZDROP">#' "frozen floor: grow"

# --- ★laundering shape の per-shape MK (folio-uryh 自己点検 ceiling major fix) ---
#   ★drop 単独 shape (CEN-rel1/2/3) は「剥奪 + 同一 literal をコメントで復元」という ★別クラス の穴を pin しない。
#   初版の (b) 軸は raw-byte grep で $BODY を舐めており (make_body は HTML コメントを逐語温存する)、 live 要素を
#   1 個剥奪しつつ同 token のコメントを 1 個注入すると 3 軸とも凍結値へ復元でき [OK] のまま素通った (実測)。
#   到達性は (a) 軸と同一 vector (contract.machine_blocks[].html は raw passthrough)。 現行実装は実 HTML parser の
#   element 軸計数ゆえ閉じているが、 ★raw-byte 計数への回帰を撃つ実弾が無いと同じ穴が再び開く。
#   ★3 軸とも撃つ (DOM 構造クラスが別 = 1 本の実弾は他 2 本の穴を証明しない・per-shape MK 規律)。
cen_mut "CEN-rel1L ★spec-machine-list 1 本 drop + 同 literal をコメントで復元 → frozen floor FAIL (comment laundering 封鎖)" \
  's#<ul data-component="spec-machine-list"#<ul data-component="ZZDROP"><!-- <ul data-component="spec-machine-list" -->#' \
  "frozen floor: spec-machine-list"
cen_mut "CEN-rel2L ★li.mli 1 項 drop + 同 literal をコメントで復元 → frozen floor FAIL (comment laundering 封鎖)" \
  's#<li class="mli">#<li class="ZZDROP"><!-- <li class="mli"> -->#' "frozen floor: li.mli"
cen_mut "CEN-rel3L ★grow 1 本 drop + 同 literal をコメントで復元 → frozen floor FAIL (comment laundering 封鎖)" \
  's#<div class="grow">#<div class="ZZDROP"><!-- <div class="grow"> -->#' "frozen floor: grow"
# ★inert subtree 経由の同型 laundering (<template> は browser が描画しない = live 資産でない)。 comment 版とは
#   parser 上の非計上経路が別ゆえ ★別 shape として撃つ (census_dump の INERT 規律と同型)。
cen_mut "CEN-rel2T ★li.mli 1 項 drop + <template> 内へ同 element を復元 → frozen floor FAIL (inert laundering 封鎖)" \
  's#<li class="mli">#<li class="ZZDROP"><template><li class="mli"></li></template>#' "frozen floor: li.mli"
# --- ★属性 semantics クラスの laundering (folio-uryh 自己点検 ceiling major fix) ---
#   HTML Standard の ★重複属性 = first-wins (2 つ目以降は parse error として破棄) を突く shape。
#   `<li class="ZZ" class="mli">` は browser では class="ZZ" = mli 資産 ★でない のに、 floor_census が
#   dict(attrs) (last-wins) だと mli として計上する。 ★実測: live 1 項 drop + 本 decoy 1 個注入で 3 軸とも
#   凍結値へ復元でき gate 全体が rc=0 / [FAIL] 0 行 / RESULT: filled PASS になった。
#   ★comment (CEN-rel*L) / inert (CEN-rel2T) とは ★非計上の経路が別 (parser は decoy を実要素として見るが
#   属性の解釈で外れる) ゆえ ★別 shape として撃つ。 3 軸とも撃つ (ul 容器 / li 項目 / div 語で DOM 構造クラスが
#   別 = 1 本の実弾は他 2 本の穴を証明しない・per-shape MK 規律)。
cen_mut "CEN-rel1D ★spec-machine-list 1 本 drop + 重複属性 decoy で復元 → frozen floor FAIL (属性 laundering 封鎖)" \
  's#<ul data-component="spec-machine-list"#<ul data-component="ZZDROP"></ul><ul data-component="ZZ" data-component="spec-machine-list"#' \
  "frozen floor: spec-machine-list"
cen_mut "CEN-rel2D ★li.mli 1 項 drop + 重複属性 decoy で復元 → frozen floor FAIL (属性 laundering 封鎖)" \
  's#<li class="mli">#<li class="ZZDROP"></li><li class="ZZ" class="mli">#' "frozen floor: li.mli"
cen_mut "CEN-rel3D ★grow 1 本 drop + 重複属性 decoy で復元 → frozen floor FAIL (属性 laundering 封鎖)" \
  's#<div class="grow">#<div class="ZZDROP"></div><div class="ZZ" class="grow">#' "frozen floor: grow"

# --- 空撃ち検査 (恒真 FAIL の封鎖): 無改変 baseline が上記 census 群で FAIL しないこと ---
#   これが無いと verify が何を食わせても FAIL する状態でも CEN 群は全て緑になる。
if RELATIONS_ORIGIN_HTML="$SNAP" bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" >/dev/null 2>&1; then
  ok "CEN-z ★空撃ち検査: 無改変 baseline は verify PASS = CEN 群の FAIL は mutation 由来"
else
  ng "CEN-z 無改変 baseline が verify FAIL (恒真 FAIL ゆえ CEN 群が無意味。 環境要因を切り分けること)"
fi

# ============================================================================
# (c) M-SELFCMP — 本番自己比較 MK: RELATIONS_ORIGIN_HTML=mutated でも frozen census が依然 FAIL する。
#   政策 A の核心 — folio-6vox flip 後は canonical が生成物へ置換され ORIG==生成物 になる。 相対 parity なら
#   c_xref(ORIG)==c_xref(HTML)==7 で vacuous PASS したが、 frozen 8 vs 生成物 7 で FAIL する (ORIG 非消費の実証)。
# ============================================================================
selfcmp_mut() { # label perl-expr reason
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/selfcmp.html"
  if diff -q "$TMP/base-filled.html" "$TMP/selfcmp.html" >/dev/null; then
    ng "M-SELFCMP $1 (mutation 空撃ち)"; return
  fi
  local out rc; out="$(RELATIONS_ORIGIN_HTML="$TMP/selfcmp.html" bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/selfcmp.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then ok "M-SELFCMP $1"
  else ng "M-SELFCMP $1 (RELATIONS_ORIGIN_HTML=mutated 自己比較で census が [FAIL] 行に無い rc=$rc / reason '$3' 不発 = 相対 parity 恒真化の回帰)"; fi
}
selfcmp_mut "★a.xref 1 個剥奪 + ORIG=mutated でも frozen census FAIL (自己比較恒真化の封鎖)" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
selfcmp_mut "★span.term 1 個剥奪 + ORIG=mutated でも frozen census FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
selfcmp_mut "★li.mli 1 項 drop + ORIG=mutated でも frozen floor FAIL (relations 固有軸の自己比較封鎖)" \
  's#<li class="mli">#<li class="ZZDROP">#' "frozen floor: li.mli"
# ★自己比較位相 (= flip 後に ORIGIN 明示注入が外れた既定位相) での ★laundering shape。 初版の raw-byte 計数では
#   この位相で ★gate 全体が rc=0 / [FAIL] 0 行 になった (§11 が自己比較で vacuous PASS し、 (b) 軸も laundering で
#   復元されるため唯一の backstop が同時に沈黙する = 最悪形)。 drop 単独の上記 case では本クラスを pin しない。
selfcmp_mut "★li.mli 1 項 drop + コメント復元 + ORIG=mutated でも frozen floor FAIL (自己比較 × laundering の同時沈黙 封鎖)" \
  's#<li class="mli">#<li class="ZZDROP"><!-- <li class="mli"> -->#' "frozen floor: li.mli"
# ★最悪形その 2: 自己比較位相 × ★属性 semantics laundering。 floor_census が last-wins だった間、 この組合せは
#   gate 全体を rc=0 / RESULT: filled PASS にした (§11 は自己比較で沈黙し、 (b) 軸は decoy で復元される)。
#   comment 版とは非計上経路が別ゆえ別 shape として撃つ (per-shape MK 規律)。
selfcmp_mut "★li.mli 1 項 drop + 重複属性 decoy 復元 + ORIG=mutated でも frozen floor FAIL (自己比較 × 属性 laundering 封鎖)" \
  's#<li class="mli">#<li class="ZZDROP"></li><li class="ZZ" class="mli">#' "frozen floor: li.mli"

# ============================================================================
# (d) SNAPPIN — snapshot 完全性 + census fail-closed の tracked 恒久 pin
# ============================================================================
# SNAPPIN-1: snapshot の sha256 が census header の宣言値と一致 (COLLAPSE 群が re-extract 元として消費する
#   snapshot の完全性 pin。 post-flip canonical 等へ差し替えられると COLLAPSE-2 は緑のまま teeth だけ腐る)。
decl_sha="$(grep -oE '[0-9a-f]{64}' "$CENSUS" | sed -n '2p')"
act_sha="$(sha256sum "$SNAP" | cut -d' ' -f1)"
if [[ -n "$decl_sha" && "$decl_sha" == "$act_sha" ]]; then
  ok "SNAPPIN-1 ★snapshot sha256 == census header 宣言値 ($act_sha)"
else
  ng "SNAPPIN-1 ★snapshot 完全性 pin 不成立 (宣言 '${decl_sha:-<none>}' / 実 $act_sha = COLLAPSE 前提の腐敗)"
fi

# SNAPPIN-2: 凍結 census 不在 → exit 2 fail-closed (silent skip の封鎖)。
sed -E 's#(FROZEN_CENSUS=")[^"]*(")#\1/nonexistent/relations.frozen-census.txt\2#' "$VER" > "$PIN_VER"
if diff -q "$VER" "$PIN_VER" >/dev/null; then
  ng "SNAPPIN-2 ★census path 差し替えが空撃ち (FROZEN_CENSUS の記法変化の疑い)"
else
  p2_out="$(RELATIONS_ORIGIN_HTML="$SNAP" bash "$PIN_VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; p2_rc=$?
  if [[ $p2_rc -eq 2 ]] && printf '%s\n' "$p2_out" | grep -qF '★凍結 census 不在'; then
    ok "SNAPPIN-2 ★凍結 census 不在で exit 2 fail-closed (理由 anchor 一致・照合不能を素通さない)"
  else
    ng "SNAPPIN-2 ★census 不在が fail-closed でない (rc=$p2_rc / 理由不一致 = fail-open 回帰)"
  fi
fi

# SNAPPIN-3: 凍結 census の値 mutate → §10b census 消費 arm が [FAIL] (arm 実在の red→green pin)。
sed -E 's/^FZ_XREF=8$/FZ_XREF=999/' "$CENSUS" > "$TMP/census-mut.txt"
sed -E "s#(FROZEN_CENSUS=\")[^\"]*(\")#\1$TMP/census-mut.txt\2#" "$VER" > "$PIN_VER"
if diff -q "$CENSUS" "$TMP/census-mut.txt" >/dev/null || diff -q "$VER" "$PIN_VER" >/dev/null; then
  ng "SNAPPIN-3 ★census mutate / path 差し替えが空撃ち"
else
  p3_out="$(RELATIONS_ORIGIN_HTML="$SNAP" bash "$PIN_VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; p3_rc=$?
  if [[ $p3_rc -ne 0 ]] && printf '%s\n' "$p3_out" | grep -F 'census rich: a.xref' | grep -qF '[FAIL]'; then
    ok "SNAPPIN-3 ★凍結 census 値 mutate で §10b arm が [FAIL] (arm が census を実消費している証明)"
  else
    ng "SNAPPIN-3 ★census mutate が arm に届かない (rc=$p3_rc = §10b が census を消費していない回帰)"
  fi
fi
rm -f "$PIN_VER"

# ----------------------------------------------------------------------------
# SNAPPIN-4/5 — ★heal provenance の tracked 恒久 pin (folio-uryh 自己点検 ceiling major fix)
#   ★問題: relations.origin.heal.py の header は tracked code 内で (a)「再実行可能な形で repo へ pin」
#   (b)「本文テキスト 1 byte 不変 という不変条件を selftest が機械 assert する」と ★宣言 していたが、 その
#   selftest は cell-local な ★untracked file であり land で消える = shipped 状態で当該コメントが ★偽 になる。
#   これは folio-7wbn ceiling が同型で defect 認定し「恒久 regression の所在は本 suite ゆえ移植する」と裁定した
#   クラス。 ★relations は rules と違い snapshot が canonical の逐語 copy ではなく ★11 変換の派生物 である初の
#   ケースゆえ、 fabrication-free の tracked pin の必要度は rules より高い。
#   ★SNAPPIN-1 (sha256 == census header 宣言値) は「snapshot が差し替わっていない」ことしか撃たず、
#   「snapshot が ★pre-flip canonical + heal で genuine に導出されたか」「本文捏造 0 か」は撃たない。
#   ★pre-flip canonical は base 4c6a3a5b (origin/main の ancestor = 恒久 reachable) から git show で取り、
#   ★その sha256 を literal pin する (取得元の同一性を history 参照だけに委ねない)。
CANON_SHA_PIN="a578ca7a68e62f53331978979fb86e78e24f13825cb5818efdebb61c3fc56ed1"
CANON_PRE="$TMP/canon-preflip.html"
if ! git -C "$SCRIPT_DIR" show "4c6a3a5b177d4e6044a94837be6d327c7db2cbfb:design-intent/spec/relations.html" > "$CANON_PRE" 2>/dev/null \
   || [[ ! -s "$CANON_PRE" ]]; then
  # ★fail-closed: 取得不能は「検証できない」であって「健全」ではない (shallow clone 等は fetch-depth:0 で解消すること)。
  ng "SNAPPIN-4 ★pre-flip canonical を取得できない (base 4c6a3a5b・fetch-depth:0 前提。 照合不能を素通さない)"
  ng "SNAPPIN-5 ★同上により heal 再現性を検証不能"
else
  canon_sha="$(sha256sum "$CANON_PRE" | cut -d' ' -f1)"
  if [[ "$canon_sha" != "$CANON_SHA_PIN" ]]; then
    ng "SNAPPIN-4 ★pre-flip canonical の sha256 不一致 (宣言 $CANON_SHA_PIN / 実 $canon_sha = 取得元の同一性喪失)"
    ng "SNAPPIN-5 ★同上により heal 再現性を検証不能"
  else
    # SNAPPIN-4: ★本文捏造 0 — snapshot の text node 集合が pre-flip canonical と ★双方向 一致 (extra 0 / missing 0)。
    #   heal が触ってよいのは属性付与 (T1) / 容器タグ形 (T2) / h4 逐語の純追加 (T3) のみでテキスト payload は原本逐語、
    #   という heal.py の宣言不変条件を ★tracked に 機械 assert する (片方向の部分集合検査では脱落方向が無被覆)。
    s4_out="$(python3 - "$CANON_PRE" "$SNAP" 2>&1 <<'PYEOF'
import re, sys, html
def texts(p):
    s = open(p, encoding='utf-8').read()
    s = re.sub(r'<(script|style)\b.*?</\1>', ' ', s, flags=re.S)
    out = set()
    for t in re.split(r'<[^>]*>', s):
        t = re.sub(r'\s+', ' ', html.unescape(t)).strip()
        if t: out.add(t)
    return out
c, o = texts(sys.argv[1]), texts(sys.argv[2])
# ★空撃ち封鎖: 抽出が空なら集合一致は自明成立ゆえ下限を課す。
if len(c) < 100 or len(o) < 100:
    print('DEGENERATE canonical=%d snapshot=%d' % (len(c), len(o))); sys.exit(1)
extra, missing = o - c, c - o
if extra or missing:
    print('EXTRA=%s MISSING=%s' % (list(extra)[:2], list(missing)[:2])); sys.exit(1)
print('OK text-node 双方向一致 (canonical=%d / snapshot=%d)' % (len(c), len(o)))
PYEOF
)"
    if [[ $? -eq 0 ]]; then
      ok "SNAPPIN-4 ★本文捏造 0: snapshot の text node は pre-flip canonical と双方向一致 ($(printf '%s' "$s4_out" | grep -oE 'canonical=[0-9]+'))"
    else
      ng "SNAPPIN-4 ★本文捏造 / 脱落 を検出 (heal が本文を書き換えた疑い): $s4_out"
    fi
    # SNAPPIN-5: ★provenance の再実行可能性 — heal.py を repo 内容だけ から再実行し committed snapshot と byte 一致。
    #   gen-units は ★本 suite が自前で再導出する (verify-relations.sh §11 RIGHT 抽出子と同一 semantics)。 これで
    #   「provenance を repo 内容だけでは再実行できない (抽出子が untracked selftest 内の perl 再実装にしか無い)」
    #   という heal.py header の宣言と実体の乖離を閉じる。
    HEAL_PY="$SCRIPT_DIR/spec-origin/relations.origin.heal.py"
    perl -CSD -0777 -e '
      local $/; open(my $fh,"<:encoding(UTF-8)",$ARGV[0]) or die; my $B=<$fh>; close $fh;
      sub norm { my ($s)=@_; $s//=""; $s=~s/\s+/ /g; $s=~s/^\s+//; $s=~s/\s+$//; return $s; }
      my @u; my $p=0; my $len=length($B);
      while ($p<$len) {
        my %c;
        if (substr($B,$p)=~/<p\b[^>]*\sdata-component="spec-machine-prose"[^>]*>/)  { $c{prose}=$p+$-[0]; }
        if (substr($B,$p)=~/<aside data-component="spec-machine-note" data-audience="machine">/) { $c{note}=$p+$-[0]; }
        if (substr($B,$p)=~/<li class="mli">/) { $c{li}=$p+$-[0]; }
        last unless %c;
        my ($k)=sort { $c{$a}<=>$c{$b} } keys %c; my $at=$c{$k};
        if ($k eq "prose") { substr($B,$at)=~/<p\b[^>]*\sdata-component="spec-machine-prose"[^>]*>(.*?)<\/p>/s; push @u,"prose\t".norm($1); $p=$at+$+[0]; }
        elsif ($k eq "note") { substr($B,$at)=~/<aside data-component="spec-machine-note" data-audience="machine">(.*?)<\/aside>/s; push @u,"note\t".norm($1); $p=$at+$+[0]; }
        else { substr($B,$at)=~/<li class="mli">(.*?)<\/li>/s; push @u,"li\t".norm($1); $p=$at+$+[0]; }
      }
      print "$_\n" for @u;
    ' "$TMP/base-filled.html" > "$TMP/gen-units.txt"
    gu_n="$(grep -c . "$TMP/gen-units.txt" || true)"
    if [[ ! -f "$HEAL_PY" ]]; then
      ng "SNAPPIN-5 ★heal script 不在 (provenance 記録の喪失): $HEAL_PY"
    elif [[ "${gu_n:-0}" -lt 30 ]]; then
      # ★空撃ち封鎖: gen-units が痩せると heal は入力不足で別物を吐く = 「差分あり」で落ちるが理由が誤診されるため別建てで撃つ。
      ng "SNAPPIN-5 ★gen-units 再導出が痩せている ($gu_n 行・期待 30 以上 = 抽出子が実 DOM と不一致)"
    elif python3 "$HEAL_PY" "$CANON_PRE" "$TMP/gen-units.txt" "$TMP/reheal.html" >/dev/null 2>&1 \
         && cmp -s "$TMP/reheal.html" "$SNAP"; then
      ok "SNAPPIN-5 ★heal 再実行 (pre-flip canonical + 再導出 gen-units $gu_n 行) が committed snapshot と byte 一致 (provenance 再現性)"
    else
      ng "SNAPPIN-5 ★heal 再実行が snapshot と byte 一致しない (provenance 記録が実体と乖離 = 再実行可能性の主張が偽)"
    fi
  fi
fi

# ============================================================================
# (e) COLLAPSE — extractor-collapse 敵対 test
#   extract-relations-spec.sh の ★inner_norm() (機械層 raw 逐語 capture) を関数レベルでタグ除去へ collapse し、
#   ★snapshot (spec-origin/relations.origin.html = flip 前 canonical + heal) から re-extract → collapsed
#   contract → assemble → collapsed 生成物。
#   ★狙い: ① ★post-flip 条件 (ORIG==生成物 の自己比較) で §11 round-trip が vacuous PASS する ことを実演し、
#     ② ★同一 run で frozen census (§10b) が collapsed 生成物を ★独立 anchor として FAIL させることを red→green 固定。
#     ③ 独立 oracle (healed snapshot) を与えれば §11 自身も collapse を割ることを確認する (二重の網)。
#   ★★rules 版との非対称 (fork 素朴写像の罠): rules の §11 LEFT は ★contract 由来 (政策A で re-home 済) ゆえ
#     contract==生成物 で自動的に vacuous 化する。 一方 ★relations の §11 LEFT は ★原本 HTML 由来 (ORIG を読む)
#     ゆえ、 vacuous 条件は contract==生成物 ではなく ★ORIG==生成物 (= folio-6vox flip 後に canonical が生成物へ
#     置換される本番条件)。 rules 版の構成をそのまま写すと ①が「§11 は健全に割れた」で FAIL する (実測)。
#   ★rules は richplain() が collapse 標的だが relations extractor に richplain は ★存在しない (実体は
#     inner_norm)。 存在しない sub 名を決め打ちすると空撃ち FAIL になるため実体を撃つ。
#   ★原本 no-touch: extract-relations-spec.sh は改変せず tmp copy を mutate する。 出力先も $TMP のみで、
#     tracked な contract/ へは 1 byte も書かない (契約 (c)「契約 refresh 目的の再走行禁止」= bwif fence を守る)。
#   ★assemble の epoch 固定 (RICH_FIELD_MIN 等の pin) は ★assemble-relations.sh に当該定数が不在 ゆえ写さない
#     (空撃ち sed 禁止・rules 側の同注記と同じ規律)。
# ============================================================================
COLLAPSE_EXTRACT="$SCRIPT_DIR/../../scripts/extract-relations-spec.sh"
if [[ ! -f "$COLLAPSE_EXTRACT" ]]; then
  ng "COLLAPSE ★前提喪失 (extractor 不在): $COLLAPSE_EXTRACT"
else
  # inner_norm() の lexical $s copy にタグ除去を注入 (関数レベル collapse・read-only $1 arg を壊さない)。
  perl -0777 -pe 's{(sub inner_norm \{\n  my \(\$s\) = \@_; \$s //= "";)}{$1\n  \$s =~ s/<[^>]*>//g;}' \
    "$COLLAPSE_EXTRACT" > "$TMP/extract-collapsed.sh"
  if diff -q "$COLLAPSE_EXTRACT" "$TMP/extract-collapsed.sh" >/dev/null; then
    ng "COLLAPSE-0 ★inner_norm()→タグ除去 collapse mutate が空撃ち (inner_norm sub の記法変化の疑い)"
  else
    ok "COLLAPSE-0 ★inner_norm()→タグ除去 collapse mutate が適用された (関数レベル)"
    bash "$TMP/extract-collapsed.sh" "$SNAP" > "$TMP/collapsed.yaml" 2>/dev/null
    if [[ -s "$TMP/collapsed.yaml" ]] && bash "$ASM" "$TMP/collapsed.yaml" "$TMP/collapsed.html" >/dev/null 2>&1; then
      cx_g="$(perl -CSD -0777 -ne 'my $n=0; while (/<a\b([^>]*)>/g){ my $a=$1; $n++ if $a =~ /class="(?:[^"]*\s)?xref/; } print $n;' "$TMP/collapsed.html")"
      # ★post-flip 条件を模す run: ORIG=collapsed 生成物 (= flip 後 canonical が生成物へ置換された状態)。
      #   ①②はこの ★同一 run から読む (「§11 は緑なのに census が赤」を 1 実行で示すのが本 test の核心)。
      col_out="$(RELATIONS_ORIGIN_HTML="$TMP/collapsed.html" bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; col_rc=$?
      # ① ORIG==生成物 の自己比較で §11 round-trip が vacuous PASS (両側同時退行で緑)。
      rt_line="$(printf '%s\n' "$col_out" | grep -F 'round-trip' | grep -F '機械層' | head -1)"
      if printf '%s' "$rt_line" | grep -qF '[OK]'; then
        ok "COLLAPSE-1 ★§11 round-trip の vacuous PASS を実演 (ORIG==生成物 の自己比較・collapsed a.xref=$cx_g < frozen 8)"
      else
        ng "COLLAPSE-1 ★vacuous PASS の実演に失敗 (§11 が [OK] でない = 自己比較が恒真化していない)"
        echo "      [debug] §11: ${rt_line:-<none>}" >&2
      fi
      # ② ★同一 run で frozen census が collapsed 生成物を FAIL させる (§11 が緑でも独立 anchor が捕捉)。
      if [[ $col_rc -ne 0 ]] && printf '%s\n' "$col_out" | grep -F 'census rich: a.xref' | grep -qF '[FAIL]'; then
        ok "COLLAPSE-2 ★§11 vacuous PASS と ★同一 run で frozen census が collapse を FAIL (政策A の核心)"
      else
        ng "COLLAPSE-2 ★frozen census が collapse を捕捉できず (rc=$col_rc・vacuous PASS 未封鎖 = 政策A 失効)"
      fi
      # ③ 独立 oracle (healed snapshot) を与えた run: §11 自身も collapse を割る (二重の網の確認)。
      sc_out="$(RELATIONS_ORIGIN_HTML="$SNAP" bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; sc_rc=$?
      sc_rt="$(printf '%s\n' "$sc_out" | grep -F '機械層' | grep -F '[FAIL]' | head -1)"
      if [[ $sc_rc -ne 0 ]] && [[ -n "$sc_rt" ]] && printf '%s\n' "$sc_out" | grep -F 'census rich: a.xref' | grep -qF '[FAIL]'; then
        ok "COLLAPSE-3 ★独立 oracle (healed snapshot) では §11 も census も FAIL (二重の網)"
      else
        ng "COLLAPSE-3 ★独立 oracle で網が片方欠けた (rc=$sc_rc / §11 FAIL 行='${sc_rt:-<none>}')"
      fi
    else
      ng "COLLAPSE ★collapsed contract の re-extract / assemble に失敗 (genuine 再生成不能)"
    fi
  fi
fi

# ============================================================================
# (f) XARM / LIVEPIN — 3 関数の cross-arm byte-identity と census subject topology の tracked pin
#   ★verify-relations.sh は strip_inert / census_dump / h_inline の ★第 3 の copy。 既存 XARM
#   (test-adversarial-spec.sh) は verify-spec vs verify-verification の 2 arm しか比べないため、
#   relations copy だけが腐っても既存 suite は緑のまま = 本 arm が唯一の検知点。
#   ★恒真 PASS 封鎖: 抽出結果が空 / 3 関数揃わないと「diff が empty」は自明に成立するため、
#   (a) 両 arm の抽出が非空、 (b) 抽出できた関数が 3 本、 を ★別 assert として撃つ。
# ============================================================================
xarm_extract() { # file fnname
  awk -v fn="$2" 'index($0,fn"() { python3")==1{f=1} f{print} f&&/^}$/{exit}' "$1"
}
xarm_n=0
for xfn in strip_inert census_dump h_inline; do
  xarm_extract "$SCRIPT_DIR/verify-relations.sh" "$xfn" > "$TMP/xarm-r.$xfn"
  xarm_extract "$SCRIPT_DIR/verify-spec.sh"      "$xfn" > "$TMP/xarm-s.$xfn"
  if [[ ! -s "$TMP/xarm-r.$xfn" || ! -s "$TMP/xarm-s.$xfn" ]]; then
    ng "XARM-$xfn ★抽出が空 (抽出子が実装と不一致 = 検査の恒真化)"
    continue
  fi
  xarm_n=$((xarm_n+1))
  if diff -q "$TMP/xarm-r.$xfn" "$TMP/xarm-s.$xfn" >/dev/null; then
    ok "XARM-$xfn ★relations arm == spec arm byte-identical ($(wc -l < "$TMP/xarm-r.$xfn") 行)"
  else
    ng "XARM-$xfn ★relations arm が spec arm と乖離 (cross-arm 非対称の新設): $(diff "$TMP/xarm-r.$xfn" "$TMP/xarm-s.$xfn" | head -3 | tr '\n' ' ')"
  fi
done
if [[ "$xarm_n" -eq 3 ]]; then
  ok "XARM-count ★3 関数すべてを両 arm から抽出できた (関数消失/改名による恒真 PASS の封鎖)"
else
  ng "XARM-count ★抽出できた関数が $xarm_n 本 (期待 3 = 検査対象が痩せている)"
fi

# LIVEPIN: 「census subject は RAW $HTML のみ・HTML_LIVE は ★どの census も消費しない」topology の pin。
#   strip_inert は bogus comment のオフセット誤算という fail-open を持つため、 census subject の ★一部 でも
#   HTML_LIVE へ戻すと当該経路が再開通する。 producer 残置と RAW 側期待本数を対で assert し空撃ちを弾く。
l_consume="$(grep -cF -e 'census_dump "$HTML_LIVE"' -e 'h_inline "$HTML_LIVE"' "$VER")"
l_mktemp="$(grep -cF 'HTML_LIVE="$(mktemp)"' "$VER")"
l_prod="$(grep -cF 'strip_inert "$HTML" > "$HTML_LIVE"' "$VER")"
l_cd="$(grep -cF 'census_dump "$HTML"' "$VER")"
l_hi="$(grep -cF 'h_inline "$HTML"' "$VER")"
if [[ "$l_consume" -ne 0 ]]; then
  ng "LIVEPIN ★census が HTML_LIVE を消費している ($l_consume 件・部分再配線 = bogus comment fail-open の再開通)"
elif [[ "$l_mktemp" -ne 1 || "$l_prod" -ne 1 ]]; then
  ng "LIVEPIN ★producer 行が期待形と不一致 (mktemp=$l_mktemp / strip_inert=$l_prod・期待 1/1 = 検査の恒真化)"
elif [[ "$l_cd" -ne 1 || "$l_hi" -ne 6 ]]; then
  ng "LIVEPIN ★RAW \$HTML の census subject 本数が期待外 (census_dump=$l_cd 期待 1 / h_inline=$l_hi 期待 6)"
else
  ok "LIVEPIN ★census subject は RAW \$HTML のみ (消費 0 / producer 存置 1+1 / RAW 消費 1+6)"
fi

# ============================================================================
# (g) CIWIRE — ★ci.yml 結線の tracked pin (folio-uryh 自己点検 ceiling major fix)
#   ★問題: §11 の既定 ORIG は ★live landed canonical ゆえ、 folio-6vox flip 後は landed == 生成物 となり
#   §11 は ★自己比較へ退化する (この vacuity は COLLAPSE-1 が同 suite 内で実測 pin 済)。 非 vacuous 化は
#   ci.yml の floor step が RELATIONS_ORIGIN_HTML を明示注入することだけが担保している。
#   ★非対称 (これが危険な理由): 同 step の SKIP_REPRO / SKIP_RENDER が欠落すると CI は ★RED になり自己顕在化
#   するのに対し、 RELATIONS_ORIGIN_HTML の欠落は ★緑のまま teeth だけが消える (silent fail-open)。
#   ★従前この結線を撃つ検査は cell-local な untracked selftest にしか無く、 land で消えた = 「保護されている」
#   という verify/ci コメントが shipped 状態で偽になる (folio-7wbn ceiling が defect 認定した同型クラス)。
#   ★恒久 regression の所在は本 suite ゆえここへ移植する。
#   ★恒真 PASS 封鎖: 「該当 step が 1 件以上見つかる」を ★別 assert にする (step 消失 / 改名で「missing 無し」が
#   自明に成立する空撃ちを弾く)。
CI_YML="$SCRIPT_DIR/../../../.github/workflows/ci.yml"
if [[ ! -f "$CI_YML" ]]; then
  ng "CIWIRE-0 ★ci.yml 不在 (結線 pin 前提の喪失): $CI_YML"
  ng "CIWIRE-1 ★前提喪失により未評価"
  ng "CIWIRE-2 ★前提喪失により未評価"
else
  ci_out="$(python3 - "$CI_YML" 2>&1 <<'PYEOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
# ★step は ★job 文脈つき で集める (flat 収集だと 6 arm を「実行されない job」へ移設しただけで素通る)。
tri = [(jn, j, s) for jn, j in (d.get('jobs') or {}).items() for s in (j.get('steps') or [])]
rel = [(jn, j, s) for jn, j, s in tri if 'relations' in ((s.get('name') or '') + (s.get('run') or ''))]
# ★空撃ち封鎖: relations step が 1 件も無ければ以降の「missing 無し」は自明成立ゆえ別 assert で落とす。
print('NSTEP=%d' % len(rel))
# ★arm が属する job 名を ★診断用に出す (現状 render-gate + verify の 2 job に跨るのは正常)。 ★これは assert では
#   なく報告値: gating の封鎖は下記 gated 判定が ★step ごとに job 文脈込みで 撃つ (job 移設は移設先 job の
#   if / continue-on-error として捕捉される)。 宣言を実能力より広く書かないこと。
jobs_of_rel = sorted({jn for jn, _, _ in rel})
print('JOBS=%s' % ','.join(jobs_of_rel))
runs = '\n'.join(s.get('run') or '' for _, _, s in rel)
want = ['verify-relations-drift.sh', 'test-adversarial-relations-drift.sh',
        'test-adversarial-relations-census.sh', 'census-guard.sh relations',
        'verify-relations.sh --artifact', 'test-adversarial-relations.sh']
missing = [w for w in want if w not in runs]
if missing: print('MISSING=%s' % ','.join(missing))
# ★soft 化 (continue-on-error) は latent-red-rot = fail-open ゆえ blocking 性も撃つ。
soft = [(s.get('name') or '?') for _, _, s in rel if s.get('continue-on-error')]
if soft: print('SOFT=%s' % ' | '.join(soft))
# ★dormant 化 (folio-uryh 自己点検 ceiling major fix)。 契約と ci.yml コメントは soft 化 ★と★ dormant 化 の
#   ★両方 を却下するが、 初版は continue-on-error しか見ず「`if: false` を 1 行足す」「条件付き job / job-level
#   continue-on-error の job へ 6 arm を移設する」のいずれでも ★緑のまま teeth が消えた (= 本 suite が F2 として
#   自ら定義した silent fail-open と同一クラスの残穴)。 step / job の ★両層 の gating を 1 本の判定で撃つ。
gated = []
for jn, j, s in rel:
    why = []
    if s.get('if') is not None: why.append('step-if')
    if j.get('if') is not None: why.append('job-if')
    if j.get('continue-on-error'): why.append('job-soft')
    if why: gated.append('%s[%s]:%s' % (jn, s.get('name') or '?', '+'.join(why)))
if gated: print('GATED=%s' % ' | '.join(gated))
# ★floor step の env 明示注入 (silent fail-open の本体)。
floor = [s for _, _, s in rel if 'verify-relations.sh --artifact' in (s.get('run') or '')]
if not floor: print('NOFLOOR=1')
else:
    r = floor[0].get('run') or ''
    lack = [t for t in ('SKIP_REPRO=1', 'SKIP_RENDER=1',
                        'RELATIONS_ORIGIN_HTML=.claude-plugin/design-system/generator/spec-origin/relations.origin.html')
            if t not in r]
    if lack: print('FLOORLACK=%s' % ','.join(lack))
# ★base 敵対 suite step も独立 oracle 注入が要る (既定 ORIG は flip 後 自己比較で P1/P2 が恒真 PASS 化)。
basearm = [s for _, _, s in rel if 'test-adversarial-relations.sh' in (s.get('run') or '')]
if not basearm: print('NOBASEARM=1')
elif 'RELATIONS_ORIGIN_HTML=' not in (basearm[0].get('run') or ''): print('BASEARMLACK=1')
PYEOF
)"; ci_rc=$?
  n_step="$(printf '%s\n' "$ci_out" | sed -n 's/^NSTEP=//p')"
  if [[ "$ci_rc" -ne 0 ]]; then
    ng "CIWIRE-0 ★ci.yml の parse に失敗 (検査の恒真化・fail-closed): $(printf '%s' "$ci_out" | tail -2 | tr '\n' ' ')"
    ng "CIWIRE-1 ★parse 失敗により未評価"
    ng "CIWIRE-2 ★parse 失敗により未評価"
  else
    if [[ -n "$n_step" && "$n_step" -ge 6 ]]; then
      ok "CIWIRE-0 ★ci.yml に relations step が $n_step 件存在 (空撃ち封鎖・期待 6 以上)"
    else
      ng "CIWIRE-0 ★relations step が ${n_step:-0} 件 (期待 6 以上 = step 消失/改名で以降の検査が恒真 PASS 化する)"
    fi
    w_bad="$(printf '%s\n' "$ci_out" | grep -E '^(MISSING|SOFT|GATED|NOFLOOR|NOBASEARM)=' | tr '\n' ' ')"
    if [[ -z "$w_bad" ]]; then
      ok "CIWIRE-1 ★relations 6 arm が ★blocking で配線済 (step/job の continue-on-error 無し ★かつ step/job の if 条件無し = soft 化 ★と★ dormant 化 の両方を封鎖・base 敵対 suite 含む) [job: $(printf '%s\n' "$ci_out" | sed -n 's/^JOBS=//p')]"
    else
      ng "CIWIRE-1 ★relations arm の blocking 配線が不完全 (soft 化 / dormant 化 = 緑のまま teeth が消える): $w_bad"
    fi
    e_bad="$(printf '%s\n' "$ci_out" | grep -E '^(FLOORLACK|BASEARMLACK)=' | tr '\n' ' ')"
    if [[ -z "$e_bad" ]]; then
      ok "CIWIRE-2 ★floor step に SKIP_REPRO/SKIP_RENDER/RELATIONS_ORIGIN_HTML 明示注入 + base arm にも独立 oracle 注入 (§11 自己比較退化の封鎖)"
    else
      ng "CIWIRE-2 ★env 明示注入の欠落 = ★緑のまま teeth が消える silent fail-open: $e_bad"
    fi
  fi
fi

# ============================================================================
# CASEPIN — 宣言集合との突合 (silent skip / case 削除の検出)。
#   ★実行された case の先頭 token 集合が宣言集合と ★完全一致 することを撃つ (件数だけの pin は
#   「別 case が 2 回走る」等の入替を素通すため集合で撃つ)。
# ============================================================================
DECLARED="CEN-id1 CEN-id2 CEN-id3 CEN-id4 CEN-rich1 CEN-rich2 CEN-rich3 CEN-rich4 \
CEN-esc1 CEN-esc2 CEN-esc3 CEN-gen1 CEN-gen2 CEN-gen3 CEN-gen4 CEN-gen5 \
CEN-rel1 CEN-rel2 CEN-rel3 CEN-rel1L CEN-rel2L CEN-rel3L CEN-rel2T \
CEN-rel1D CEN-rel2D CEN-rel3D \
CEN-z M-SELFCMP M-SELFCMP M-SELFCMP M-SELFCMP M-SELFCMP \
SNAPPIN-1 SNAPPIN-2 SNAPPIN-3 SNAPPIN-4 SNAPPIN-5 \
COLLAPSE-0 COLLAPSE-1 COLLAPSE-2 COLLAPSE-3 \
XARM-strip_inert XARM-census_dump XARM-h_inline XARM-count LIVEPIN \
CIWIRE-0 CIWIRE-1 CIWIRE-2"
exp_sorted="$(printf '%s\n' $DECLARED | LC_ALL=C sort)"
act_sorted="$(printf '%s\n' "${SEEN_IDS[@]}" | LC_ALL=C sort)"
echo "  ----"
if [[ "$exp_sorted" != "$act_sorted" ]]; then
  echo "  [FAIL] CASEPIN: 実行 case 集合が宣言と不一致 (silent skip / case 削除 / 入替の疑い)"
  echo "    --- 宣言のみ (未実行) ---"; LC_ALL=C comm -23 <(printf '%s\n' "$exp_sorted") <(printf '%s\n' "$act_sorted") | sed 's/^/      /'
  echo "    --- 実行のみ (未宣言) ---"; LC_ALL=C comm -13 <(printf '%s\n' "$exp_sorted") <(printf '%s\n' "$act_sorted") | sed 's/^/      /'
  fail=$((fail+1))
fi
printf '  relations census/collapse 敵対: %d PASS / %d FAIL (計 %d)\n' "$pass" "$fail" "$((pass+fail))"
[[ "$fail" -eq 0 ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
