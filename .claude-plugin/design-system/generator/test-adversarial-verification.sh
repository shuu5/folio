#!/usr/bin/env bash
# folio engine tr0 (folio-nxp) — spec-pack 敵対回帰テストの FORK (doc-type=spec / verification self-host)
#
# ★test-adversarial-spec.sh (rules 用) の FORK。 verification 固有 anchor (REQ-VER-* / §section / P-13 等) へ差し替え、
#   verification 固有の機械層 demoted (ADR-0040 降格分) の改竄敵対 (F12=text 改竄 / M16=block 削除) を追加。
# spec-pack の fail-closed gate (assemble-verification validate abort / verify-verification FAIL / inject abort) が
# 構造捏造・★silent drop (未対応 block type)・要件/section/block/照会 fidelity 改竄・doc_type flip・
# core chrome 改竄・prose 改竄・★機械層 demoted 改竄 を捕捉することを回帰確認する。
# SRS/ADR/research/principle/rules の test-adversarial-*.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
# ★abort 系は stderr 理由を検証し「別原因の誤 abort」= false-pass を弾く。
# ★verify FAIL 系は理由 substring を検証し「想定 gate 以外の巻き添え FAIL」での false-pass を弾く。
#
# usage: test-adversarial-verification.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-verification.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-verification.sh"
BASE="$SCRIPT_DIR/contract/folio-verification.spec.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-verification.prose.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
# repro-build arm (verify_repro_build・folio-3d23) は verify-*.sh 既定 ON。 bulk case は honest skip で 10 分/suite を維持し
# (arm 未 skip は assemble 再 build で timeout)、 conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
export SKIP_REPRO="${SKIP_REPRO:-1}"
# gate F (playwright visual) は floor-adversarial では skip (重い render を外す・SKIP_REPRO と同型)。 B 段
# (folio-jyfh) で mermaid も render 対象になったが、 bash floor では従来通り skip し CI 側で実 render する。
export SKIP_RENDER="${SKIP_RENDER:-1}"
source "$SCRIPT_DIR/lib/test-repro-pins.sh"
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
expect_vfilled_fail() { # label html [reason]
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (--filled verify が PASS した)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (FAIL したが理由が想定外。 期待 '$3')"; return; fi
  ok "$1"
}
expect_vprefill_fail() { # label contract html [reason]
  local out rc; out="$(bash "$VER" "$2" "$3" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (pre-fill verify が PASS した)"; return; fi
  if [[ -n "${4:-}" && "$out" != *"$4"* ]]; then ng "$1 (FAIL したが理由が想定外。 期待 '$4')"; return; fi
  ok "$1"
}
expect_vprefill_pass() { # label contract html
  if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi
}
expect_vfilled_pass() { # label html
  if bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" >/dev/null 2>&1; then ok "$1"; else ng "$1 (--filled verify FAIL)"; fi
}
expect_inject_abort() { if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi; }

# 健全 baseline を一度生成。
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }

echo "spec-pack adversarial regression (fail-closed expected):"

# === assemble-spec validate (生成前 fail-closed) ===
# A1. doc_type flip → abort (gate bypass 封鎖)
cp "$BASE" "$TMP/a1.yaml"; yq -i '.meta.doc_type = "spec-doc"' "$TMP/a1.yaml"
expect_abort "A1 ★doc_type flip を abort (gate bypass 封鎖)" "$TMP/a1.yaml" "doc_type は spec 必須"

# A2. ★未対応 block type (silent drop 禁止) → abort
cp "$BASE" "$TMP/a2.yaml"; yq -i '.sections[0].blocks += [{"type":"video","src":"x"}]' "$TMP/a2.yaml"
expect_abort "A2 ★未対応 block type を fail-closed abort (silent drop 禁止)" "$TMP/a2.yaml" "未対応 block type"

# A3. 未知 EARS pattern → abort
cp "$BASE" "$TMP/a3.yaml"; yq -i '.requirements[0].ears_pattern = "maybe-driven"' "$TMP/a3.yaml"
expect_abort "A3 未知 EARS pattern を abort" "$TMP/a3.yaml" "未知の EARS pattern"

# A4. 未知 section tint → abort
cp "$BASE" "$TMP/a4.yaml"; yq -i '.sections[0].tint = "rainbow"' "$TMP/a4.yaml"
expect_abort "A4 未知 section tint を abort" "$TMP/a4.yaml" "未知の section tint"

# A5. 要件 id 重複 → abort
cp "$BASE" "$TMP/a5.yaml"; yq -i '.requirements[1].id = (.requirements[0].id)' "$TMP/a5.yaml"
expect_abort "A5 要件 id 重複を abort" "$TMP/a5.yaml" "要件 id 重複"

# A6. section id 重複 → abort
cp "$BASE" "$TMP/a6.yaml"; yq -i '.sections[1].id = (.sections[0].id)' "$TMP/a6.yaml"
expect_abort "A6 section id 重複を abort" "$TMP/a6.yaml" "section id 重複"

# A7. ★孤立要件 (どの block にも配置されない) → abort
cp "$BASE" "$TMP/a7.yaml"; yq -i '.requirements += [{"id":"REQ-ORPHAN-1","ears_pattern":"ubiquitous","essence":"孤立","statement":"x"}]' "$TMP/a7.yaml"
expect_abort "A7 ★配置先 block の無い孤立要件を abort" "$TMP/a7.yaml" "孤立要件"

# A8. ★存在しない要件を block が参照 → abort
cp "$BASE" "$TMP/a8.yaml"; yq -i '(.sections[] | select(.blocks[]? | .type=="requirements") | .blocks[] | select(.type=="requirements")).ids += ["REQ-GHOST-9"]' "$TMP/a8.yaml"
expect_abort "A8 ★未定義要件を参照する requirements block を abort" "$TMP/a8.yaml" "未定義の要件を参照"

# A9. ★要件の二重配置 (2 block で同一 id) → abort。 s3 に置かれた REQ-VER-001 を s4 の requirements block (REQ-VER-005) にも追加。
cp "$BASE" "$TMP/a9.yaml"
yq -i '(.sections[] | select(.id=="s4") | .blocks[] | select(.type=="requirements")).ids += ["REQ-VER-001"]' "$TMP/a9.yaml"
expect_abort "A9 ★要件の二重配置を abort (行数二重カウント防止)" "$TMP/a9.yaml" "重複配置"

# A10. 未知 reference role → abort
cp "$BASE" "$TMP/a10.yaml"; yq -i '.references[0].role = "wild"' "$TMP/a10.yaml"
expect_abort "A10 未知 reference role を abort" "$TMP/a10.yaml" "未知の reference role"

# A11. ★空 reference token → abort
cp "$BASE" "$TMP/a11.yaml"; yq -i '.references[0].token = ""' "$TMP/a11.yaml"
expect_abort "A11 ★空 reference token を abort" "$TMP/a11.yaml" "空 token"

# A12. graph principle_edge role allowlist 外 → abort
cp "$BASE" "$TMP/a12.yaml"; yq -i '.graph.principle_edge.role = "wild"' "$TMP/a12.yaml"
expect_abort "A12 graph principle_edge role allowlist 外を abort" "$TMP/a12.yaml" "principle_edge.role が allowlist 外"

# A13. 値に改行 (@tsv 列ずれ源) → abort
cp "$BASE" "$TMP/a13.yaml"; yq -i '.requirements[0].essence = "line1" + "\n" + "line2"' "$TMP/a13.yaml"
expect_abort "A13 改行を含む値を abort" "$TMP/a13.yaml" "tab/改行"

# A14. ★EARS allowlist の word-split bypass: 空白区切りの allowlist token 並び "ubiquitous unwanted" は
#      IFS split で個々が allowlist を pass する fail-open だった。 逐値判定で full 文字列を 1 件として abort する。
cp "$BASE" "$TMP/a14.yaml"; yq -i '.requirements[0].ears_pattern = "ubiquitous unwanted"' "$TMP/a14.yaml"
expect_abort "A14 ★EARS 空白 split bypass (allowlist token 並び) を逐値判定で abort" "$TMP/a14.yaml" "未知の EARS pattern"

# A15. ★section tint の word-split bypass: "brand violet" は IFS split で brand/violet 双方 TINT_OK を pass し
#      band の class へ stray token violet を注入する fail-open だった。 逐値判定で full 文字列を 1 件として abort する。
cp "$BASE" "$TMP/a15.yaml"; yq -i '.sections[0].tint = "brand violet"' "$TMP/a15.yaml"
expect_abort "A15 ★tint 空白 split bypass (allowlist token 並び) を逐値判定で abort" "$TMP/a15.yaml" "未知の section tint"

# A16. ★references role の word-split bypass: "claim rationale" は IFS split で claim/rationale 双方 ROLE_OK を pass し
#      data-ref-role へ stray multi-token を注入する fail-open だった (A14/A15 と同型)。 逐値判定で full 文字列を 1 件として abort する。
cp "$BASE" "$TMP/a16.yaml"; yq -i '.references[0].role = "claim rationale"' "$TMP/a16.yaml"
expect_abort "A16 ★references role 空白 split bypass (allowlist token 並び) を逐値判定で abort" "$TMP/a16.yaml" "未知の reference role"

# A17. ★meta.stakeholders の型退行 (array → scalar string) を abort (folio-aduv 0-c)。
#   ★contract 経由で CORE の出力を壊すクラス: lib/common.sh core_emit_graph_head は .meta.stakeholders を JSON-LD の
#   "folio:stakeholders" へ *そのまま* 転記するため、 scalar を入れると canonical の array が string へ型退行する
#   (CORE を 1 byte も触らずに CORE 出力が壊れる = fence HIGH-2 の意図違反)。 既存 gate は全て素通りした (実測):
#   jsonld-lint は folio:stakeholders を型検査対象外と明記、 inventory は非 array を捨て meta split fallback で
#   同じ配列を作り直して drift を隠蔽、 §11 前方 edge 突合も本 key を見ない。 ゆえ契約段で型を fail-closed に pin する。
cp "$BASE" "$TMP/a17.yaml"; yq -i '.meta.stakeholders = "Developer, AI Agent, External Reviewer"' "$TMP/a17.yaml"
expect_abort "A17 ★meta.stakeholders の scalar 退行を abort (CORE JSON-LD の array→string 型退行封鎖)" "$TMP/a17.yaml" "stakeholders は array 必須"

# === fabrication-free (HTML 改竄・生成後 fail-closed) ===
# F1. ★要件 row を 1 枚削除 → 行数 FAIL
cp "$TMP/base-filled.html" "$TMP/f1.html"
perl -0777 -i -pe 's#<div data-component="ears-requirement-row"[^>]*>.*?(?=<div data-component="ears-requirement-row"|</div>\s*</div>\s*<section)##s' "$TMP/f1.html"
expect_vfilled_fail "F1 要件 row 削除を行数 gate が捕捉" "$TMP/f1.html" "ears-requirement-row"

# F2. ★可視 rid 改竄 (attr 正) → 要件タプル vis FAIL
cp "$TMP/base-filled.html" "$TMP/f2.html"
perl -0777 -i -pe 's#(data-req-id="REQ-VER-001"[^>]*>\s*<div class="rq-head"><span class="rid">)REQ-VER-001#${1}REQ-FAKE#' "$TMP/f2.html"
expect_vfilled_fail "F2 ★可視 rid 改竄 (attr 正) を要件タプルで捕捉" "$TMP/f2.html" "要件"

# F3. ★要件 statement 改竄 → 要件タプル FAIL
# ★folio-aduv: statement は rich raw emit になり可視形が <span class="ears-id">REQ-VER-001</span>: … へ変わった。
#   旧 mutation (<p class="rq-stmt">REQ-VER-001:) は no-op 化し「改竄していないのに PASS」= 空撃ちになる。
#   per-shape で新 shape へ撃ち直す (mutation-kill 維持)。 ★fired 検査つき: 置換 0 件なら ng (空撃ちの再発を封じる)。
cp "$TMP/base-filled.html" "$TMP/f3.html"
perl -0777 -i -pe 'our $n; $n += s#(<p class="rq-stmt"><span class="ears-id">REQ-VER-001</span>:)#${1} 捏造された一文。#; END { exit($n?0:9) }' "$TMP/f3.html" \
  || ng "F3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F3 ★要件 statement 改竄を要件タプルで捕捉" "$TMP/f3.html" "要件タプル"

# F4. ★要件 essence 改竄 → 要件タプル FAIL
# ★folio-aduv: essence も rich raw (<code>tests/scenarios/</code> が live tag) ゆえ旧 literal は no-op 化。 新 shape へ撃ち直す。
cp "$TMP/base-filled.html" "$TMP/f4.html"
perl -0777 -i -pe 'our $n; $n += s#<p class="rq-essence">検証 scenario は#<p class="rq-essence">捏造された essence・検証 scenario は#; END { exit($n?0:9) }' "$TMP/f4.html" \
  || ng "F4 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F4 ★要件 essence 改竄を要件タプルで捕捉" "$TMP/f4.html" "要件タプル"

# F5. ★EARS badge label 改竄 → 要件タプル FAIL (REQ-VER-007 = unwanted = forbid badge "異常応答")
cp "$TMP/base-filled.html" "$TMP/f5.html"
perl -0777 -i -pe 's#(data-req-id="REQ-VER-007"[^>]*>.*?<span data-component="ears-badge" class="forbid">)異常応答#${1}無条件不変条件#s' "$TMP/f5.html"
expect_vfilled_fail "F5 ★EARS badge label 改竄を要件タプルで捕捉" "$TMP/f5.html" "要件タプル"

# F6. ★section heading 改竄 → section heading FAIL
cp "$TMP/base-filled.html" "$TMP/f6.html"
perl -0777 -i -pe 's#<h2>§6\. References</h2>#<h2>§6. 捏造見出し</h2>#' "$TMP/f6.html"
expect_vfilled_fail "F6 ★section heading 改竄を捕捉" "$TMP/f6.html" "section 可視 heading"

# F7. ★section essence 改竄 → section essence FAIL (先頭 section essence に捏造を前置)。
cp "$TMP/base-filled.html" "$TMP/f7.html"
perl -0777 -i -pe 's#(<div data-component="section-essence-callout"><p class="sec-se">)#${1}捏造改竄 #' "$TMP/f7.html"
expect_vfilled_fail "F7 ★section essence 改竄を捕捉" "$TMP/f7.html" "section essence"

# F8. ★reference token 改竄 → references SET FAIL (P-13 = verification の前方照会 token)
cp "$TMP/base-filled.html" "$TMP/f8.html"
perl -0777 -i -pe 's#data-ref-token="P-13"#data-ref-token="P-999"#' "$TMP/f8.html"
expect_vfilled_fail "F8 ★reference token 改竄を SET で捕捉" "$TMP/f8.html" "references: token SET"

# F9. ★reference 可視 <b> のみ改竄 (attr 正) → (token,doc,role) vis FAIL
cp "$TMP/base-filled.html" "$TMP/f9.html"
perl -0777 -i -pe 's#(data-ref-token="P-13"[^>]*><span class="rf-token"><b>)P-13(</b>)#${1}P-FAKE${2}#' "$TMP/f9.html"
expect_vfilled_fail "F9 ★reference 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "references: (token,doc,role)"

# F10. ★reference role を allowlist 内別 role へ改竄 → (token,doc,role) FAIL (P-13 implementation→verification)
cp "$TMP/base-filled.html" "$TMP/f10.html"
perl -0777 -i -pe 's#(data-ref-token="P-13" data-ref-role=)"implementation"#${1}"verification"#' "$TMP/f10.html"
expect_vfilled_fail "F10 ★reference role 改竄 (allowlist 内別 role) を (token,role) で捕捉" "$TMP/f10.html" "references"

# F11. ★block prose 可視テキスト改竄 → prose 列 FAIL (s12 等の prose があれば。無ければ table 改竄で代替)
cp "$TMP/base-filled.html" "$TMP/f11.html"
perl -0777 -i -pe 's#<td>Ubiquitous</td>#<td>捏造Ubiquitous</td>#' "$TMP/f11.html"
expect_vfilled_fail "F11 ★table セル改竄を td 列で捕捉" "$TMP/f11.html" "table td"

# F12. ★機械層 demoted (verification 固有・ADR-0040 降格分) text 改竄 → 原本↔生成物 round-trip FAIL。
#      verification は human-layer code block を持たず (全 <pre><code> は demoted 内 = 機械層) ゆえ rules の code-行 改竄 (旧 F12) を demoted 改竄へ置換。
cp "$TMP/base-filled.html" "$TMP/f12.html"
perl -0777 -i -pe 's#(<div data-component="spec-machine-demoted" data-audience="machine">)#${1}ZZDEMOTEDTAMPERZZ #' "$TMP/f12.html"
expect_vfilled_fail "F12 ★機械層 demoted text 改竄を原本↔生成物 round-trip が捕捉" "$TMP/f12.html" "原本↔生成物 機械層"

# F13. ★subhead heading 改竄 → subhead 列 FAIL
# ★folio-aduv: h3 に fine section anchor (id=) が付いた形へ shape が変わったため撃ち直す (id は温存し heading だけ改竄)。
cp "$TMP/base-filled.html" "$TMP/f13.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subhead"><h3 id="[^"]*">)§3\.2 YAML schema#${1}§3.2 捏造#s; END { exit($n?0:9) }' "$TMP/f13.html" \
  || ng "F13 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F13 ★subhead heading 改竄を捕捉" "$TMP/f13.html" "subhead heading"

# F14. ★mermaid source 行改竄 → mermaid source FAIL
cp "$TMP/base-filled.html" "$TMP/f14.html"
perl -0777 -i -pe 's#flowchart TB#flowchart CAPTURED#' "$TMP/f14.html"
expect_vfilled_fail "F14 ★mermaid source 行改竄を捕捉" "$TMP/f14.html" "mermaid source"

# F15. ★cover-meta 章数捏造 → cover-meta FAIL
cp "$TMP/base-filled.html" "$TMP/f15.html"
perl -0777 -i -pe 's#(<span class="k">章の数</span><span class="v">)\d+ 章#${1}99 章#' "$TMP/f15.html"
expect_vfilled_fail "F15 ★cover-meta 章数捏造を再導出で捕捉" "$TMP/f15.html" "cover-meta 章の数"

# F16. ★core chrome (cover title h1) 改竄 → core-chrome FAIL
cp "$TMP/base-filled.html" "$TMP/f16.html"
perl -0777 -i -pe 's#<h1>folio verification — sandbox verification framework spec</h1>#<h1>詐欺タイトル</h1>#' "$TMP/f16.html"
expect_vfilled_fail "F16 ★core chrome (h1) 改竄を core-chrome で捕捉" "$TMP/f16.html" "core-chrome"

# F17. ★prose スロット内容改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/f17.html"
perl -0777 -i -pe 's#(data-slot-id="cover-summary">)[^<]*#${1}改竄された散文#' "$TMP/f17.html"
expect_vfilled_fail "F17 prose 改竄 (注入忠実) を verify が捕捉" "$TMP/f17.html" "注入"

# F18. ★HTML 注入の遮断 (生 markup が構造へ漏れない)。
# ★folio-aduv で保証形が変わった: 人間層 rich field は inline HTML を逐語保持し RAW emit する (xref/term/delta/<code> 復元の手段)
#   ため、 旧「無差別 esc() して &lt;script&gt; と *表示* する」保証は成立しない。 代わりに validate_rich_inline の
#   ★allowlist fail-closed abort が引き継ぐ = escape して出すのでなく *生成そのものを拒否* する (旧より強い保証)。
#   ゆえ期待を「entity へ escape」→「assemble abort」へ移す (assert の削除ではなく、 より強い assert への置換)。
cp "$BASE" "$TMP/f18.yaml"; yq -i '.requirements[0].essence = "<script>alert(1)</script>危険"' "$TMP/f18.yaml"
expect_abort "F18 ★rich field への <script> 注入を allowlist fail-closed abort" "$TMP/f18.yaml" "allowlist 外"
# F18b. ★event handler 属性の注入も abort (allowlist 内タグ <span> に紛れ込む形 = tag 名検査だけでは抜ける穴)。
cp "$BASE" "$TMP/f18b.yaml"; yq -i '.requirements[0].essence = "<span onclick=\"alert(1)\">危険</span>"' "$TMP/f18b.yaml"
expect_abort "F18b ★rich field への event handler 属性注入を abort" "$TMP/f18b.yaml" "event handler"
# F18c. ★生成物に生 <script> が出ていないことの直接 pin (abort 経路が壊れても本 assert が残る = 二重化)。
if grep -q '<script>alert' "$TMP/base-filled.html"; then ng "F18c 生成物に生 <script> 混入"; else ok "F18c 生成物に生 <script> 混入なし"; fi
# F18d. ★entity 符号化した URL scheme の注入も abort (per-shape・F18/F18b が撃たない構造クラス)。
#   ★これを撃たないと F18/F18b の緑は「偽の保証」になる: <a> は tag allowlist 内・on*= も無いため、 literal 部分文字列
#   一致の scheme 検査だけでは 3 検査すべてを擦り抜けて live な javascript: link が RAW emit される (実弾で確認した回帰)。
#   browser は属性値の character reference を decode してから scheme を解釈するので、 検査も decode 後に行わねばならない。
#   符号化の *形ごと* に 1 本ずつ撃つ (10 進 / 16 進 / 多重符号化 / 制御文字割り込み / 非 allowlist scheme)。
f18d_shape() { # label essence-payload
  cp "$BASE" "$TMP/f18d.yaml"; yq -i ".requirements[0].essence = \"$2\"" "$TMP/f18d.yaml"
  expect_abort "F18d $1" "$TMP/f18d.yaml" "URL-ALLOWLIST-VIOLATION"
}
f18d_shape "★10 進 entity 符号化 scheme (&#106;avascript:) を abort" '<a href=\"&#106;avascript:alert(1)\">click</a>'
f18d_shape "★16 進 entity 符号化 scheme (&#x6a;avascript:) を abort"  '<a href=\"&#x6a;avascript:alert(1)\">click</a>'
f18d_shape "★多重符号化 (&amp;#106;avascript:) を abort"              '<a href=\"&amp;#106;avascript:alert(1)\">click</a>'
f18d_shape "★制御文字割り込み (java&Tab;script:) を abort"            '<a href=\"java&Tab;script:alert(1)\">click</a>'
f18d_shape "★data: URL を abort (肯定 allowlist ゆえ scheme 列挙に依らず落ちる)" '<a href=\"data:text/html,xx\">click</a>'
# F18e. ★空撃ち検査: 上記 abort が「毒とは無関係に常に落ちている」のでないことを pin する。
#   素の契約 (毒なし) は abort *しない* こと = allowlist が正当な href (#frag / 相対 .html / .md) を通す証明。
#   これが無いと validate_rich_inline が全 contract を一律 reject していても F18d は緑になる (恒真 abort の見逃し)。
if bash "$ASM" "$BASE" "$TMP/f18e.html" >/dev/null 2>&1; then ok "F18e ★空撃ち検査: 素の契約 (毒なし) は abort しない = URL allowlist は恒真 reject でない"
else ng "F18e 素の契約が abort した (URL allowlist が正当 href を弾いている = 恒真 abort ゆえ F18d 群が無意味)"; fi

# F18f. ★★quoting/区切りの *形* ごとの per-shape mutation-kill (F18d が撃たない ★別の構造クラス)。
#   ★なぜ要るか: F18d は符号化 (entity) の形を per-shape 化したが、 撃った payload は全て ★double-quote + 空白正常形
#   だった。 mutation-kill は DOM 構造クラスごとに撃つ規律ゆえ、 1 形 (double-quote) の緑は ★構造差のある形
#   (single / unquoted / 空白欠落 / quote 内 >) の穴を証明しない。 実際 naive regex 版はこの 4 形すべてに fail-open で、
#   実 browser (html5lib 突合) は 4 形すべてを ★LIVE と解釈した = 86/86 全緑のまま live な javascript:/on*= を RAW emit していた。
#   ★payload は strenv で渡す: yq の \" escape 経路では ★real な single quote を注入できず (\x27 が literal 化して
#   別物を撃つ = 空撃ち)、 テストが緑でも当該 shape を検査していない偽の被覆になる (本 group 作成時に実測)。
f18f_shape() { # label payload expected_reason_token
  cp "$BASE" "$TMP/f18f.yaml"
  payload="$2" yq -i '.requirements[0].essence = strenv(payload)' "$TMP/f18f.yaml"
  expect_abort "F18f $1" "$TMP/f18f.yaml" "$3"
}
# B1: HTML5 の after-attribute-value-quoted state は非空白を missing-whitespace-between-attributes として *回復* し
#     onclick を属性化する。 strict grammar は回復せず落とす (fail-closed residue)。
f18f_shape "★属性間の空白欠落 (href=\"#x\"onclick=…) を abort" '<a href="#x"onclick="alert(1)">c</a>' "MALFORMED-MARKUP"
# B2/B3: 値の quoting 形に依らず URL 検査へ入ること。
f18f_shape "★single-quote 値の javascript: を abort" "<a href='javascript:alert(1)'>c</a>" "URL-ALLOWLIST-VIOLATION"
f18f_shape "★unquoted 値の javascript: を abort"     '<a href=javascript:alert(1)>c</a>'     "URL-ALLOWLIST-VIOLATION"
# B4: quote 内の ">" で属性列が早期終端せず、 後続の href が検査対象に残ること。
f18f_shape "★quote 内 > の後続 href を abort (早期終端しない)" '<a title=">" href="javascript:alert(1)">c</a>' "URL-ALLOWLIST-VIOLATION"
# 符号化 × quoting の直交合成 (両 per-shape 軸が同時に効くこと)。
f18f_shape "★single-quote × entity 符号化 scheme を abort" "<a href='&#106;avascript:alert(1)'>c</a>" "URL-ALLOWLIST-VIOLATION"
# ★属性名 allowlist は *形* に依らず落ちる (\s 依存 heuristic を廃した証明)。
f18f_shape "★single-quote の on*= を属性名 allowlist で abort" "<span onclick='alert(1)'>x</span>" "event handler attribute"
# ★未列挙 sink も属性名 allowlist で一律に落ちる (否定列挙なら取りこぼす形)。
f18f_shape "★style 属性 (未列挙 sink) を abort" '<span style="color:red">x</span>' "ATTR-NAME-NOT-ALLOWED"
# ★tokenize しきれない形は理由を問わず落とす (未知の parser-differential を通さない側へ倒す)。
f18f_shape "★eof-in-tag (未終端 tag) を abort" '<a href="#x"' "MALFORMED-MARKUP"
f18f_shape "★comment 内への隠蔽を abort"       '<!--<a href=javascript:alert(1)>-->x' "MALFORMED-MARKUP"

# === F18g. ★guard 自身の ★喪失を撃つ (per-shape mutation-kill・fail-open クラスの封鎖) ===
# ★なぜ要るか: 本 fork は 8 箇所の emit site で esc() を外し RAW emit 化し、 その代替保護を
#   validate_rich_inline の allowlist abort ★一本に集約した。 ゆえ guard が「何も検査しない状態」へ落ちると
#   注入防御が ★丸ごと消える。 F18/F18b/F18d/F18f 群は guard が *生きている* ことを撃つが、 それらは
#   guard 自身の ★喪失に対しては ★恒真 (guard が空撃ちでも payload が無ければ緑) ゆえ本 F18g が要る。
# ★旧実装の穴 (実測): PASS/FAIL を $bad の空文字列性だけで決めていたため rich_field_values の query が drift すると
#   「検査対象 0 件 → bad なし → return 0 = PASS」で guard が何も覆わないまま緑になった。 RICH_FIELD_MIN の
#   被覆量 assert がそれを塞ぐ。 本 F18g はその塞ぎが ★実際に効くことを実弾で pin する。
# ★GUARDLESS は SCRIPT_DIR 直下に置く MUST: assembler は SCRIPT_DIR 経由で lib/common.sh を source するため、
#   他所へ置くと ★lib 解決に失敗して rc=1 になる (= guard が撃った abort と ★見分けが付かない偽の緑。 実測で踏んだ)。
#   TMP の外ゆえ EXIT trap へ ★明示的に載せる (途中 kill で untracked の残骸を repo に残さない)。
GUARDLESS="$SCRIPT_DIR/.f18g-guardless.sh"
trap 'rm -rf "$TMP"; rm -f "$GUARDLESS"' EXIT
sed 's/\.sections\[\]\.essence,/.sectionsTYPO[].essence,/' "$ASM" > "$GUARDLESS"
if diff -q "$ASM" "$GUARDLESS" >/dev/null; then
  ng "F18g mutation が assembler を変えていない = ★空撃ち (rich_field_values の query 形が変わった疑い)"
else
  # (a) 検査対象が痩せた事実そのものを abort する (query drift = 抽出規約の破綻)。
  g_out="$(bash "$GUARDLESS" "$BASE" "$TMP/f18g.html" 2>&1)"; g_rc=$?
  if [[ $g_rc -ne 0 && "$g_out" == *"検査対象が"* ]]; then
    ok "F18g ★rich_field_values の query drift を被覆量 assert が捕捉 (guard 喪失の検出)"
  else
    ng "F18g ★query drift が素通り (rc=$g_rc) = guard 喪失に恒真 PASS (fail-open)"
  fi
  # (b) ★teeth: guard を殺した assembler へ <script> 注入契約を食わせても ★生成させない。
  #   drift した field (.sections[].essence) の値は tokenizer の検査対象から外れるため、 被覆量 assert が
  #   無ければ payload は ★そのまま RAW emit される。 abort することが RAW emit 無防備化の封鎖証明になる。
  # ★rc≠0 「だけ」で緑にしてはならない (実測で踏んだ罠): assembler を SCRIPT_DIR 外へ置くと lib/common.sh の
  #   解決に失敗して ★同じ rc=1 を返す。 すなわち「abort した」は ★guard が撃った証明にならず、 tool error でも
  #   緑になる = 別クラスの恒真 PASS。 ゆえ ★理由 token (被覆量 assert) と ★payload の不在を併せて課す。
  rm -f "$TMP/f18g2.html"
  cp "$BASE" "$TMP/f18g.yaml"
  payload='<script>alert(1)</script>' yq -i '.sections[0].essence = strenv(payload)' "$TMP/f18g.yaml"
  g_out="$(bash "$GUARDLESS" "$TMP/f18g.yaml" "$TMP/f18g2.html" 2>&1)"; g_rc=$?
  if [[ $g_rc -eq 0 ]]; then
    ng "F18g ★guard 喪失時に <script> 注入が素通りし生成された (fail-open = RAW emit が無防備)"
  elif [[ "$g_out" != *"検査対象が"* ]]; then
    ng "F18g ★abort したが理由が被覆量 assert でない (tool error 等での ★見せかけの緑。 stderr 末尾: $(printf '%s' "$g_out" | tail -1))"
  elif grep -q '<script>alert(1)</script>' "$TMP/f18g2.html" 2>/dev/null; then
    ng "F18g ★abort したが生成物に payload が残留している (部分書き出しでの露出)"
  else
    ok "F18g ★guard を殺した assembler でも <script> 注入契約は被覆量 assert で abort し payload 不在 (RAW emit の無防備化を封鎖)"
  fi
fi
rm -f "$GUARDLESS"

# === F19. ★navigable id / head meta / rich 資産の喪失を verify が捕捉する (folio-aduv 0-a/0-c/0-d の per-shape mutation-kill) ===
# ★なぜ per-shape に分けるか: 1 instance の実弾は *構造差のある* instance の穴を証明しない。 section anchor (章包み
#   <section id> 要素) / head meta (<meta> tag) / rich 資産 (a.xref / span.term / ins.delta) は DOM 形状が別クラスゆえ
#   1 本ずつ撃つ。
# ★これらが無いと、 生成物から資産が丸ごと消えても gate は baseline と同一の FAIL 件数を出す (= 喪失に vacuous PASS)。
#   実際 mutation-kill 実弾で: emit_pack_head_meta 呼出を落とすと meta 7→3 本、 章 anchor emit 行を落とすと
#   section id 7→0 本になるのに、 いずれも新規 FAIL ゼロだった (本 F19 群と verify 側 gate の追加で封鎖)。
f19_mut() { # label perl-expr [reason]
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/f19.html"
  if ! diff -q "$TMP/base-filled.html" "$TMP/f19.html" >/dev/null; then
    expect_vfilled_fail "F19 $1" "$TMP/f19.html" "${3:-}"
  else
    ng "F19 $1 (mutation が生成物を変えていない = 空撃ち。 selector が実 DOM と不一致の疑い)"
  fi
}
f19_mut "★section anchor 全剥奪 を捕捉 (corpus inbound #s1-contract 等が解決不能)" \
  's#<section id="[^"]*">\n##g' "section anchor"
f19_mut "★section anchor id 改竄 を捕捉 (脱落だけでなく値の drift も)" \
  's#(<section id=")s1-contract#${1}s1-TAMPERED#' "section anchor"
f19_mut "★head meta (folio-stakeholders) 剥奪 を捕捉" \
  's#<meta name="folio-stakeholders"[^>]*>\n##' "folio-stakeholders"
f19_mut "★head meta (folio-layer) 値改竄 を捕捉" \
  's#(<meta name="folio-layer" content=")[^"]*#${1}TAMPERED#' "folio-layer"
f19_mut "★rich: a.xref 1 個剥奪 を ORACLE parity が捕捉" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "a.xref"
f19_mut "★rich: span.term 1 個剥奪 を ORACLE parity が捕捉" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "span.term"
f19_mut "★rich: ins.delta 1 個剥奪 を ORACLE parity が捕捉" \
  's#<ins class="delta"[^>]*>(.*?)</ins>#$1#s' "delta"
f19_mut "★0-e: jq -S を text ごと削除 を PRESERVE assert が捕捉 (how-outside は緑のままでも落ちること)" \
  's#<code>jq -S</code>##' "jq -S"
# F19z. ★空撃ち検査 (恒真 FAIL の封鎖): 無改変の baseline は上記 gate 群で FAIL しないこと。
#   これが無いと verify が何を食わせても FAIL する状態でも F19 群は全て緑になる。
if bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" >/dev/null 2>&1; then
  ok "F19z ★空撃ち検査: 無改変 baseline は verify PASS = F19 群の FAIL は mutation 由来"
else
  ng "F19z 無改変 baseline が verify FAIL (恒真 FAIL ゆえ F19 群が無意味。 環境要因 gate F 等を切り分けること)"
fi

# === kicker 列 fidelity (folio-l93・決定的フィールド→floor) ===
# 17n 独立 ceiling (wf_1ffcdb7c HIGH) が炙った floor gap: band() が <span class="kicker"> で可視 emit する
# §N/トピック ラベルは sections[].kicker 由来の決定的フィールドだが verify-spec が未突合だった。 §番号 swap /
# topic 取り違え / heading の §N との drift / 静的 band kicker drift を kicker 列突合が FAIL することを lock。
# F19. ★§番号 swap: §4↔§5 の kicker を入れ替え → 順序突合 FAIL (ZZSWAPZZ は doc に出ない安全な placeholder)。
cp "$TMP/base-filled.html" "$TMP/f19.html"
perl -0777 -i -pe 's#§4 / 実装段階#ZZSWAPZZ#; s#§5 / 未解決#§4 / 実装段階#; s#ZZSWAPZZ#§5 / 未解決#' "$TMP/f19.html"
expect_vfilled_fail "F19 ★kicker §番号 swap (§4↔§5) を kicker 列突合が捕捉" "$TMP/f19.html" "kicker"

# F20. ★topic 取り違え: §3 の kicker トピックを別章 (§2 検証範囲) のものへ → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f20.html"
perl -0777 -i -pe 's#§3 / EARS 要件#§3 / 検証範囲#' "$TMP/f20.html"
expect_vfilled_fail "F20 ★kicker topic 取り違え (§3 EARS 要件→検証範囲) を捕捉" "$TMP/f20.html" "kicker"

# F21. ★heading の §N との不整合: §2 の kicker を §6 へ (heading は「§2. Verification Scope」) → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f21.html"
perl -0777 -i -pe 's#§2 / 検証範囲#§6 / 検証範囲#' "$TMP/f21.html"
expect_vfilled_fail "F21 ★kicker §N が heading §N と不整合 (§2→§6・heading §2) を捕捉" "$TMP/f21.html" "kicker"

# F22. ★静的 band kicker (references) の drift → 末尾 2 件も期待列に含むため FAIL ("(前方)" は perl regex で \( \) escape)。
cp "$TMP/base-filled.html" "$TMP/f22.html"
perl -0777 -i -pe 's#この仕様が参照する文書 / 照会 \(前方\)#詐欺照会ラベル#' "$TMP/f22.html"
expect_vfilled_fail "F22 ★静的 band kicker (references) drift を捕捉" "$TMP/f22.html" "kicker"

# === folio-2jr: EARS 凡例 (静的 key・badge 色 ↔ §6 用途 label の対応表) ===
# F23. ★凡例 label drift (凡例 item のみ改竄・要件 badge は不変) → ears-legend label 列 FAIL。
#      data-component=ears-legend-item を狙い撃つ (要件 badge=ears-badge には触れない = 凡例単独の drift を捕捉)。
cp "$TMP/base-filled.html" "$TMP/f23.html"
perl -0777 -i -pe 's#(data-component="ears-legend-item" class="forbid">)異常応答#${1}詐欺ラベル#' "$TMP/f23.html"
expect_vfilled_fail "F23 ★EARS 凡例 label drift を捕捉" "$TMP/f23.html" "ears-legend label"

# F24. ★凡例 item 削除 → ears-legend-item == 5 件数 FAIL (5 型欠落 = 凡例の不完全)。
cp "$TMP/base-filled.html" "$TMP/f24.html"
perl -0777 -i -pe 's#<span data-component="ears-legend-item" class="forbid">異常応答</span>##' "$TMP/f24.html"
expect_vfilled_fail "F24 ★EARS 凡例 item 削除を件数で捕捉" "$TMP/f24.html" "ears-legend-item"

# F25. ★凡例「いつ守るか」(el-when) 改竄 → el-when 列 FAIL (persona-walk major-1 の平易説明が drift しないことを lock)。
cp "$TMP/base-filled.html" "$TMP/f25.html"
perl -0777 -i -pe 's#<span class="el-when">異常が起きた時</span>#<span class="el-when">詐欺説明</span>#' "$TMP/f25.html"
expect_vfilled_fail "F25 ★EARS 凡例 el-when drift を捕捉" "$TMP/f25.html" "el-when"

# === 4wz: emit_glossary 空中間 en (core lib/common.sh・spec assembler 経由で exercise) ===
# G1. ★空 en の glossary entry で def が en バッジへ畳まれない (folio-4wz)。 旧 IFS=$'\t' read は空中間 en
#     (term\t\tdef) を畳み def を en へ混入させた (term/空en/def → term/def/空)。 manual split が 3 列を正しく分離する。
cp "$BASE" "$TMP/g1.yaml"
yq -i '.glossary += [{"term":"ZZZEMPTYEN","en":"","def":"空en検証用の定義文"}]' "$TMP/g1.yaml"
bash "$ASM" "$TMP/g1.yaml" "$TMP/g1.html" >/dev/null 2>&1
if grep -qF '<div class="gword">ZZZEMPTYEN</div><div class="gdef">空en検証用の定義文</div>' "$TMP/g1.html" \
   && ! grep -qF '<span class="en">空en検証用の定義文</span>' "$TMP/g1.html"; then
  ok "G1 ★空 en glossary entry で def が gdef に残り en へ畳まれない (folio-4wz)"
else
  ng "G1 ★空 en glossary で def が en へ混入 (4wz 未修正 = 中間フィールド畳み)"
fi

# === inject fail-closed ===
# J1. manifest から 1 スロット削除 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/j1.prose.yaml"; yq -i 'del(.slots.["cover-summary"])' "$TMP/j1.prose.yaml"
expect_inject_abort "J1 manifest 欠落スロットを inject が abort" "$TMP/j1.prose.yaml" "$TMP/base.html"
# J2. manifest に orphan キー追加 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/j2.prose.yaml"; yq -i '.slots.["ghost-slot"] = "幽霊"' "$TMP/j2.prose.yaml"
expect_inject_abort "J2 manifest orphan キーを inject が abort" "$TMP/j2.prose.yaml" "$TMP/base.html"

# === w1f cell-2: 機械層 (machine free-prose dual-audience) round-trip + REQ-DA-STRUCT ===
# M1. ★機械層 prose テキスト改竄 → 原本↔生成物 round-trip FAIL (件数不変・テキスト差のみ = round-trip 単独検出)。
cp "$TMP/base-filled.html" "$TMP/m1.html"
perl -0777 -i -pe 's#(<p data-component="spec-machine-prose" data-audience="machine">)#${1}ZZTAMPERZZ #' "$TMP/m1.html"
expect_vfilled_fail "M1 ★機械層 prose 改竄を原本↔生成物 round-trip が捕捉" "$TMP/m1.html" "原本↔生成物 機械層"

# M2. ★機械層 prose 脱落 (silent drop) → 件数 + round-trip FAIL。
cp "$TMP/base-filled.html" "$TMP/m2.html"
perl -0777 -i -pe 's#<p data-component="spec-machine-prose" data-audience="machine">.*?</p>\n##s' "$TMP/m2.html"
expect_vfilled_fail "M2 ★機械層 prose 脱落を件数+round-trip が捕捉" "$TMP/m2.html" "spec-machine-prose"

# M3. ★機械層 prose 捏造 (原本に無い block を add) → 件数 + round-trip FAIL (生成物のみ)。
cp "$TMP/base-filled.html" "$TMP/m3.html"
perl -0777 -i -pe 's#(<div class="machine-body">\n)#${1}<p data-component="spec-machine-prose" data-audience="machine">捏造された機械層</p>\n#' "$TMP/m3.html"
expect_vfilled_fail "M3 ★機械層 prose 捏造を round-trip (生成物のみ) が捕捉" "$TMP/m3.html" "原本↔生成物 機械層"

# M4. ★機械層 list item (mli) 脱落 → mli 件数 + round-trip FAIL。
cp "$TMP/base-filled.html" "$TMP/m4.html"
perl -0777 -i -pe 's#<li class="mli">.*?</li>\n##s' "$TMP/m4.html"
expect_vfilled_fail "M4 ★機械層 list item 脱落を件数+round-trip が捕捉" "$TMP/m4.html" "machine li"

# M5. ★data-audience 値域違反 (machine→robot) → REQ-DA-STRUCT-3 FAIL (P-5 closed 2 値)。
cp "$TMP/base-filled.html" "$TMP/m5.html"
perl -0777 -i -pe 's#(<p data-component="spec-machine-prose" )data-audience="machine"#${1}data-audience="robot"#' "$TMP/m5.html"
expect_vfilled_fail "M5 ★data-audience 値域違反 (robot) を REQ-DA-STRUCT-3 が捕捉" "$TMP/m5.html" "REQ-DA-STRUCT-3"

# M6. ★machine 部に aria-hidden → REQ-DA-STRUCT-4 FAIL (AI/AT からの normative 不可視化禁止)。
cp "$TMP/base-filled.html" "$TMP/m6.html"
perl -0777 -i -pe 's#(<p data-component="spec-machine-prose" data-audience="machine")>#${1} aria-hidden="true">#' "$TMP/m6.html"
expect_vfilled_fail "M6 ★machine 部の aria-hidden を REQ-DA-STRUCT-4 が捕捉" "$TMP/m6.html" "REQ-DA-STRUCT-4"

# M7. ★要件 container の data-audience="human" 剥奪 → tuple + REQ-DA-STRUCT-1 FAIL (孤立 human container 検出)。
# ★folio-aduv: row opener に id="<navigable id>" が入った形へ shape が変わったため撃ち直す。
cp "$TMP/base-filled.html" "$TMP/m7.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row" id="[^"]*" data-req-id="[^"]*" data-ears-pattern="[^"]*") data-audience="human">#${1}>#g; END { exit($n?0:9) }' "$TMP/m7.html" \
  || ng "M7 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "M7 ★要件 container の data-audience=human 剥奪を REQ-DA-STRUCT-1 が捕捉" "$TMP/m7.html" "REQ-DA-STRUCT-1"

# M8. ★未対応 machine block type (silent drop 禁止・contract abort) → assemble fail-closed。
cp "$BASE" "$TMP/m8.yaml"; yq -i '.sections[0].machine_blocks += [{"type":"diagram","html":"x"}]' "$TMP/m8.yaml"
expect_abort "M8 ★未対応 machine block type を fail-closed abort (silent drop 禁止)" "$TMP/m8.yaml" "未対応 machine block type"

# M9. ★machine_preamble の未対応 type → assemble abort。
cp "$BASE" "$TMP/m9.yaml"; yq -i '.machine_preamble += [{"type":"video","html":"x"}]' "$TMP/m9.yaml"
expect_abort "M9 ★machine_preamble の未対応 type を fail-closed abort" "$TMP/m9.yaml" "未対応 machine block type"

# M10. ★機械層 (note) の二重 escape (live <a href が &lt;a href 化) → round-trip FAIL (原本テキストと差)。
#   ★verification 固有調整: verification の機械層 prose は先頭 inline tag が <code> でない (<a>/<strong>) ため rules M10 の <code> 前提では不発。
#   機械層 note は必ず <a href を含む (ADR 参照リンク) ため note の最初の <a href を二重 escape して round-trip 検出を固定する。
cp "$TMP/base-filled.html" "$TMP/m10.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine">.*?)<a href=#${1}&lt;a href=#s' "$TMP/m10.html"
expect_vfilled_fail "M10 ★機械層の二重 escape を round-trip が捕捉" "$TMP/m10.html" "原本↔生成物 機械層"

# M11. ★機械層 block 順序入替 (隣接 prose 2 件を swap・件数/集合不変・順序のみ差) → 順序付き round-trip FAIL。
#   旧版 (集合一致) では素通っていた = §11 を順序付きに強化した major fix の red→green pin (人間層 §4/§5 と対称)。
cp "$TMP/base-filled.html" "$TMP/m11.html"
perl -0777 -i -e '
  local $/; my $H=<>;
  my @m; while ($H=~/(<p data-component="spec-machine-prose" data-audience="machine">.*?<\/p>)/gs){ push @m,$1; last if @m>=2; }
  my ($a,$b)=($m[0],$m[1]);
  $H=~s/\Q$a\E/__M11A__/; $H=~s/\Q$b\E/__M11B__/; $H=~s/__M11A__/$b/; $H=~s/__M11B__/$a/;
  print $H;
' "$TMP/m11.html"
expect_vfilled_fail "M11 ★機械層 block 順序入替を順序付き round-trip が捕捉" "$TMP/m11.html" "原本↔生成物 機械層"

# M12. ★cross-section 誤帰属 (ある fold の machine prose を別 fold の machine-body へ移動・件数/集合不変・document 順のみ差)
#   → 順序付き round-trip FAIL。 集合一致では section 帰属を検証できず素通っていた (major fix の red→green pin)。
cp "$TMP/base-filled.html" "$TMP/m12.html"
perl -0777 -i -e '
  local $/; my $H=<>;
  $H=~/(<p data-component="spec-machine-prose" data-audience="machine">.*?<\/p>\n)/s; my $blk=$1;
  $H=~s/\Q$blk\E//;
  my @pos; while ($H=~/<div class="machine-body">\n/g){ push @pos,$+[0]; }
  my $ins=$pos[-1]; $H=substr($H,0,$ins).$blk.substr($H,$ins);
  print $H;
' "$TMP/m12.html"
expect_vfilled_fail "M12 ★cross-section 誤帰属を順序付き round-trip が捕捉" "$TMP/m12.html" "原本↔生成物 機械層"

# M13. ★機械層 note (aside) テキスト改竄 → 原本↔生成物 round-trip FAIL (件数不変・最複雑 modality の content fidelity pin)。
#   note は nested <p>・<span class=term>・<a> を含む最も構造複雑な block 種ゆえ専用の改竄敵対が要る (prose M1 と対称)。
cp "$TMP/base-filled.html" "$TMP/m13.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine">)#${1}ZZNOTETAMPERZZ #' "$TMP/m13.html"
expect_vfilled_fail "M13 ★機械層 note 改竄を原本↔生成物 round-trip が捕捉" "$TMP/m13.html" "原本↔生成物 機械層"

# M14. ★機械層 note 脱落 (silent drop) → spec-machine-note 件数 + round-trip FAIL (prose M2 と対称)。
cp "$TMP/base-filled.html" "$TMP/m14.html"
perl -0777 -i -pe 's#<aside data-component="spec-machine-note" data-audience="machine">.*?</aside>\n##s' "$TMP/m14.html"
expect_vfilled_fail "M14 ★機械層 note 脱落を件数+round-trip が捕捉" "$TMP/m14.html" "spec-machine-note"

# M15. ★原本不在 fail-closed pin (verify-spec §11 L310-311 = 機械層 contract で原本 rules.html 不在なら FAIL)。
#   SPEC_ORIGIN_HTML で存在しない path を指し、 round-trip 照合不能を *素通さず* FAIL することを red→green で固定する。
#   ★これが無いと将来 path 解決 (SCRIPT_DIR 相対) が壊れても緑のまま = round-trip が silent skip する回帰を検出できない。
#   健全 baseline (P2 で PASS) を入力にし、 原本 path だけを破壊して fail-closed branch を確実に踏ませる
#   (= 別 gate の巻き添え FAIL でなく「原本不在」理由を substring 検証して false-pass を弾く)。
m15_out="$(SPEC_ORIGIN_HTML=/nonexistent/rules.html bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; m15_rc=$?
if [[ $m15_rc -eq 0 ]]; then
  ng "M15 ★原本不在 fail-closed (verify が PASS した = fail-open 回帰)"
elif [[ "$m15_out" != *"原本不在"* ]]; then
  ng "M15 ★原本不在 fail-closed (FAIL したが理由が想定外。 期待 '原本不在')"
else
  ok "M15 ★原本不在を verify-verification §11 が fail-closed FAIL (照合不能を素通さない)"
fi

# M16. ★機械層 demoted (verification 固有) block 脱落 (silent drop) → spec-machine-demoted 件数 + round-trip FAIL (prose M2 / note M14 と対称)。
#   生成物 demoted wrapper は inner に nested div を持たない (原本 div.demoted inner = p/ul/pre のみ) ゆえ非貪欲 .*?</div> で 1 件削除。
cp "$TMP/base-filled.html" "$TMP/m16.html"
perl -0777 -i -pe 's#<div data-component="spec-machine-demoted" data-audience="machine">.*?</div>\n##s' "$TMP/m16.html"
expect_vfilled_fail "M16 ★機械層 demoted block 脱落を件数+round-trip が捕捉" "$TMP/m16.html" "spec-machine-demoted"

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_vprefill_pass "P1 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"
expect_vfilled_pass  "P2 健全 baseline は --filled verify PASS" "$TMP/base-filled.html"

echo
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
# ===== census-count blocking arm conformance seed (folio-jmmk): 容器 block / machine 部品件数の source DOM 静的照合 =====
# 空 data-component タグ注入で件数 +1 (excess) にし census-count arm が [FAIL] census-count: <token> で blocking 捕捉する
# ことを固定。 空 block ゆえ内容の順序値 chk (list items / code lines / cell / round-trip / fold) は素通り = census-count arm が
# 唯一 anchor (sweep 分類表 folio-3d23【B2 占有pin sweep 成果物】)。 帰属 [FAIL] 行は census-count arm を外した mutant で消え
# = mutation-kill (占有 pin de-scope 後の継承先 aliveness 固定)。 [FAIL] 行限定判定で reason 判別力を確保 ([OK] 行の label 混入排除)。
cc_seed() { # label token
  perl -0777 -pe 's{</h1>}{"</h1><span data-component=\"'"$2"'\"></span>"}e if !$d++' "$TMP/base-filled.html" > "$TMP/ccseed-$2.html"
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/ccseed-$2.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F '[FAIL]' | grep -qF "census-count: $2"; then ok "$1"
  else ng "$1 (exit=$rc / [FAIL] census-count: $2 不発火)"; fi
}
cc_seed "CC-list ★空 spec-list-block 追加 (順序値素通り) を census-count arm が捕捉" spec-list-block
cc_seed "CC-code ★空 spec-code 追加 を census-count arm が捕捉" spec-code
cc_seed "CC-table ★空 spec-table 追加 を census-count arm が捕捉" spec-table
cc_seed "CC-mlist ★空 spec-machine-list 追加 を census-count arm が捕捉" spec-machine-list
cc_seed "CC-mfold ★空 spec-machine-fold 追加 (fold 再グルーピング近似) を census-count arm が捕捉" spec-machine-fold

if repro_pins "$VER" verification "$BASE" "$BASE_PROSE" "$ASM" "$INJ" --filled "$BASE_PROSE"; then ok "repro-build conformance (a-d) 全 pass"; else ng "repro-build conformance (a-d) 逸脱"; fi
echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
