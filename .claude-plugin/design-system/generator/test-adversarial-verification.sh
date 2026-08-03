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
# ★SEEN_IDS = 実行された case の先頭 token (CASEPIN が宣言集合と突合し silent skip を検出する)
declare -a SEEN_IDS=()
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); SEEN_IDS+=("${1%% *}"); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); SEEN_IDS+=("${1%% *}"); }

expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
expect_vfilled_fail() { # label html [reason]
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$2" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (--filled verify が PASS した)"; return; fi
  # ★reason 照合は [FAIL] 行 anchor (errata-1 must-1)。 census chk ラベルは [OK] 行にも常時出力される (frozen census は
  #   PASS 時も件数を表示) ため、 単純 substring 一致だと census クラスで恒真 (巻き添え FAIL guard が inert) になる。
  #   COLLAPSE-2/3・cc_seed と同じ [FAIL] 行限定へ統一する。 reason は括弧/ドット等の regex metachar を含みうるため
  #   -E でなく fixed-string 2 段 (該当 reason を含む行のうち [FAIL] を含む行が在るか) で anchor する (regex-safe)。
  if [[ -n "${3:-}" ]] && ! printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then
    ng "$1 (FAIL したが理由が [FAIL] 行に無い。 期待 '$3' を [FAIL] 行で)"; return
  fi
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
# ★ADR-0054 lockstep: chip 突合の label が (token,doc,role) → (token,doc,role,title) へ拡張されたため reason substring を再同期。
expect_vfilled_fail "F9 ★reference 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "references: (token,doc,role,title)"

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
expect_vfilled_fail "F12 ★機械層 demoted text 改竄を原本↔生成物 round-trip が捕捉" "$TMP/f12.html" "機械層 不一致"

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
EPOCH_ASM="$SCRIPT_DIR/.collapse-epoch-asm.sh"   # COLLAPSE 用 epoch 固定 assembler (SCRIPT_DIR 配置 = lib 解決・COLLAPSE 節参照)
trap 'rm -rf "$TMP"; rm -f "$GUARDLESS" "$EPOCH_ASM"' EXIT
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

# === M17. ★★機械層 (machine free-prose) field への注入を ★生成前に fail-closed abort する (folio-eccf S1) ===
# ★なぜ F18 群と ★別に要るか (F18 群は機械層を ★一切撃っていない): F18/F18b/F18d/F18f/F18g の的は全て
#   ★人間層 (.requirements[].essence / .sections[].essence) であり、 機械層 (machine_preamble / machine_blocks) の
#   RAW emit 経路は ★別関数 (validate_machine_inline) / ★別 allowlist (MACHINE_RICH_ALLOW) / ★別抽出
#   (machine_field_values) / ★別下限 (MACHINE_FIELD_MIN) で守られる ★独立の防御である。 ゆえ F18 群が 全緑でも
#   validate_machine_inline を ★丸ごと削除して suite は緑のまま になる (= tracked な恒久被覆が 0 = 保護の非対称)。
#   本 M17 群がその非対称を閉じる: 人間層 F18 群と ★同じ検出力を 機械層に対して tracked に固定する。
# ★空撃ち negative control は F18e が兼ねる: F18e は ★素の契約 (毒なし) が abort しないことを撃ち、 素の契約は
#   validate() 内で validate_machine_inline も ★必ず通る ゆえ、 機械層 allowlist の恒真 abort も F18e が弾く
#   (機械層 allowlist が block 群を落とすと 素の canonical が abort し F18e が赤くなる = 恒真 abort の検出)。
# ★per-shape に分ける理由 (F18d/F18f と同じ規律): dl / note / demoted / list は ★DOM 構造クラスが異なり、
#   1 instance の実弾は 構造差のある instance の穴を ★証明しない。 payload も tag / 属性 / URL の 3 クラスへ直交させる。
m17_shape() { # label yq-path payload expected_reason_token
  cp "$BASE" "$TMP/m17.yaml"
  payload="$3" yq -i "$2 = strenv(payload)" "$TMP/m17.yaml"
  # ★(a) mutation 発火検査: 契約が ★実際に変わったか。 これが無いと path が実 schema と不一致でも (yq が黙って
  #   no-op しても) 「abort しなかった」ではなく「毒を入れていない契約が通った」を撃つ ★空撃ちに退化する。
  if diff -q "$BASE" "$TMP/m17.yaml" >/dev/null; then
    ng "M17 $1 (mutation が契約を変えていない = ★空撃ち。 path が実 schema と不一致)"; return
  fi
  local out rc; out="$(bash "$ASM" "$TMP/m17.yaml" "$TMP/m17.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "M17 $1 (★abort せず生成された = 機械層 RAW emit が無防備)"; return; fi
  # ★理由を ★機械層 guard の文言で照合する MUST: rc≠0 だけで緑にすると、 人間層 guard の巻き添え abort や
  #   tool error (lib 解決失敗等) でも緑になり ★機械層を検査した証明にならない (F18g で踏んだ罠と同型)。
  if [[ "$out" != *"機械層 field に allowlist 外の markup"* ]]; then
    ng "M17 $1 (abort したが理由が ★機械層 guard でない = 別原因の誤 abort。 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return
  fi
  if [[ "$out" != *"$4"* ]]; then ng "M17 $1 (abort 理由 token が想定外。 期待 '$4')"; return; fi
  if [[ -f "$TMP/m17.html" ]] && grep -q 'alert(1)' "$TMP/m17.html" 2>/dev/null; then
    ng "M17 $1 (abort したが生成物に payload が残留 = 部分書き出しでの露出)"; return
  fi
  ok "M17 $1"
}
# dl (machine_preamble[0]) / note (machine_preamble[1]) / demoted (sections[1].machine_blocks[1]) = ★実測 path (.html 経路)。
for m17s in "dl:.machine_preamble[0].html" "note:.machine_preamble[1].html" "demoted:.sections[1].machine_blocks[1].html"; do
  m17_nm="${m17s%%:*}"; m17_pt="${m17s#*:}"
  m17_shape "★$m17_nm への <script> 注入を機械層 allowlist で abort"        "$m17_pt" '<script>alert(1)</script>'           "TAG-NOT-ALLOWED"
  m17_shape "★$m17_nm への event handler 属性注入を abort"                  "$m17_pt" '<div onerror="alert(1)">x</div>'     "event handler attribute"
  m17_shape "★$m17_nm への javascript: URL 注入を abort"                    "$m17_pt" '<a href="javascript:alert(1)">x</a>' "URL-ALLOWLIST-VIOLATION"
done
# ★list は ★別の抽出経路 (.items[] であって .html でない) = 構造クラスが異なるため独立に撃つ。
m17_shape "★list(.items[] 経路) への <script> 注入を abort" '.sections[5].machine_blocks[1].items[0]' '<script>alert(1)</script>' "TAG-NOT-ALLOWED"

# === M17b/M17c. ★機械層 guard 自身の ★喪失を ★分岐ごとに 撃つ (F18g の機械層版・per-shape mutation-kill) ===
# ★なぜ分岐ごとか: machine_field_values は ★4 分岐の union (preamble.html / preamble.items[] / blocks.html /
#   blocks.items[]) であり、 1 分岐の drift を撃った緑は ★他分岐の穴を証明しない (F18d/F18f と同じ per-shape 規律)。
# ★何が守るか: 分岐 drift → 検査対象が痩せる → MACHINE_FIELD_MIN の被覆量 assert が abort する。 本 case は
#   その塞ぎが ★実際に効くことを実弾で pin する (guard 喪失クラスの fail-open 封鎖)。
M17_GUARDLESS="$SCRIPT_DIR/.m17-guardless.sh"
trap 'rm -rf "$TMP"; rm -f "$GUARDLESS" "$M17_GUARDLESS"' EXIT
m17_guard_loss() { # label sed-expr
  # ★GUARDLESS は SCRIPT_DIR 直下に置く MUST (F18g と同じ理由: lib/common.sh の解決失敗が rc=1 で誤緑になる)。
  sed "$2" "$ASM" > "$M17_GUARDLESS"
  if diff -q "$ASM" "$M17_GUARDLESS" >/dev/null; then
    ng "$1 (mutation が assembler を変えていない = ★空撃ち。 machine_field_values の query 形が変わった疑い)"; return
  fi
  local g_out g_rc
  # (a) 検査対象が痩せた事実そのものを abort する (query drift = 抽出規約の破綻)。
  g_out="$(bash "$M17_GUARDLESS" "$BASE" "$TMP/m17g.html" 2>&1)"; g_rc=$?
  if [[ $g_rc -ne 0 && "$g_out" == *"機械層 field の検査対象が"* ]]; then
    ok "$1 (a) ★query drift を MACHINE_FIELD_MIN の被覆量 assert が捕捉 (guard 喪失の検出)"
  else
    ng "$1 (a) ★query drift が素通り (rc=$g_rc) = guard 喪失に恒真 PASS (fail-open)"
  fi
  # (b) ★teeth: guard を殺した assembler へ 機械層注入契約を食わせても ★生成させない。
  #   ★rc≠0 「だけ」で緑にしない (F18g で踏んだ罠): ★理由 token と ★payload 不在を併せて課す。
  rm -f "$TMP/m17g2.html"
  cp "$BASE" "$TMP/m17g.yaml"
  payload='<script>alert(1)</script>' yq -i '.machine_preamble[0].html = strenv(payload)' "$TMP/m17g.yaml"
  g_out="$(bash "$M17_GUARDLESS" "$TMP/m17g.yaml" "$TMP/m17g2.html" 2>&1)"; g_rc=$?
  if [[ $g_rc -eq 0 ]]; then
    ng "$1 (b) ★guard 喪失時に機械層 <script> 注入が素通りし生成された (fail-open = RAW emit が無防備)"
  elif [[ "$g_out" != *"機械層 field の検査対象が"* ]]; then
    ng "$1 (b) ★abort したが理由が被覆量 assert でない (tool error 等での ★見せかけの緑。 stderr 末尾: $(printf '%s' "$g_out" | tail -1))"
  elif grep -q '<script>alert(1)</script>' "$TMP/m17g2.html" 2>/dev/null; then
    ng "$1 (b) ★abort したが生成物に payload が残留している"
  else
    ok "$1 (b) ★guard を殺した assembler でも機械層注入は被覆量 assert で abort し payload 不在 (RAW emit 無防備化の封鎖)"
  fi
  rm -f "$M17_GUARDLESS"
}
m17_guard_loss "M17b ★machine_preamble 分岐の guard 喪失" 's/\.machine_preamble\[\]? | select/.machine_preambleTYPO[]? | select/g'
m17_guard_loss "M17c ★machine_blocks 分岐の guard 喪失"   's/\.sections\[\]\.machine_blocks\[\]? | select/.sectionsTYPO[].machine_blocks[]? | select/g'

# === M17d. ★機械層 被覆の ★分岐別 内訳と総和恒等式 (folio-eccf S5 の機械層版・count-only 残余の封鎖) ===
# ★なぜ MACHINE_FIELD_MIN (総数下限) だけでは足りないか: 現 MIN=34 は ★たまたま現総数と一致している ため
#   今日は任意分岐の drift が総数減で捕捉される。 しかし契約が正当に育って総数が 34 を上回った後は、
#   ★1 分岐が drift しても総数は下限を満たしたまま で その分岐が ★無検査になる (人間層 S5 の 337/360 と同機序)。
#   MACHINE_FIELD_TYPE_MINS + 総和恒等式がそれを塞ぐ。 本 case はその塞ぎが ★実際に効くことを実弾で pin する。
# ★実弾の作り方: 分岐別下限を ★0 へ無力化した上で 表側 query だけを drift させる。 こうすると
#   (i) 総数 34 は下限 34 を満たし、 (ii) 分岐別下限も 0 ゆえ通り、 ★総和恒等式だけ が破れる = 恒等式を名指しで撃つ。
M17_IDENT="$SCRIPT_DIR/.m17-ident.sh"
trap 'rm -rf "$TMP"; rm -f "$GUARDLESS" "$M17_GUARDLESS" "$M17_IDENT"' EXIT
sed "s/'20:::block-html:::\.sections\[\]\.machine_blocks/'0:::block-html:::.sectionsTYPO[].machine_blocks/" "$ASM" > "$M17_IDENT"
if diff -q "$ASM" "$M17_IDENT" >/dev/null; then
  ng "M17d mutation が assembler を変えていない = ★空撃ち (MACHINE_FIELD_TYPE_MINS の記法が変わった疑い)"
else
  m17d_out="$(bash "$M17_IDENT" "$BASE" "$TMP/m17d.html" 2>&1)"; m17d_rc=$?
  if [[ $m17d_rc -ne 0 && "$m17d_out" == *"機械層 field の分岐別 総和"* ]]; then
    ok "M17d ★表と machine_field_values の drift を総和恒等式が捕捉 (総数下限が緑のままでも落ちる)"
  else
    ng "M17d ★分岐 drift が素通り (rc=$m17d_rc) = 総和恒等式が不発 (count-only 残余が残っている)"
  fi
fi
rm -f "$M17_IDENT"

# === M18. ★S2 の ORACLE generic inline / double-escape assert に ★tracked な teeth を与える (folio-eccf S2) ===
# ★なぜ要るか (M17 と ★同一クラスの非対称): S2 は verify-verification.sh (tracked) へ assert を足したが、
#   その assert が ★効いていること を撃つ case が tracked suite に無いと、 誰かが assert を消しても suite は
#   ★緑のまま になる (untracked な worker selftest は cell 終了で消えるため恒久被覆にならない)。
#   S1 には M17 群がその被覆を与えたので、 ★S2 にも同型に与えて非対称を残さない。
# ★MK として成立する理由: expect_vfilled_fail は ★理由 substring を照合する。 ゆえ S2 の assert を削除すると
#   出力から当該 substring が消えて ★本 case が赤くなる (別 gate が巻き添えで赤くしても substring 照合は通らない)。
# ★変異 = 人間可視領域 (table cell) の live <code> を ★二重 escape する (raw emit 経路が壊れた時の実形)。
#   実測: table-cell 41→13 / 人間層 122→94 / &lt;code literal 0→28 = live 減と literal 増の ★両側で挟まる。
#   ★<td> 直後の code を狙う MUST: 素の「最初の <code>」は ★機械層 (data-audience=machine) に在り、
#   人間層 assert は発火しない (= 空撃ち。 実測で確認)。
f19_mut_reason() { # label perl-expr reason  (F19 と同型だが理由照合を必須にする)
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/m18.html"
  if diff -q "$TMP/base-filled.html" "$TMP/m18.html" >/dev/null; then
    ng "$1 (mutation が生成物を変えていない = ★空撃ち。 selector が実 DOM と不一致の疑い)"
  else
    expect_vfilled_fail "$1" "$TMP/m18.html" "$3"
  fi
}
# ★政策 A (folio-7n17): S2 の ORACLE assert は census へ改称された (「census generic」/「census double-escape」・
#   subject=生成物・frozen literal)。 reason substring も新 label へ追随する (改称後も teeth が効くことを pin)。
f19_mut_reason "M18 ★table cell の live <code> 二重 escape を census generic が捕捉 (occurrence 減)" \
  's#(<td[^>]*>)<code>([^<]*)</code>#${1}&lt;code&gt;${2}&lt;/code&gt;#g' \
  "census generic"
f19_mut_reason "M18b ★同変異を census double-escape が literal 増の側から捕捉 (両側で挟む)" \
  's#(<td[^>]*>)<code>([^<]*)</code>#${1}&lt;code&gt;${2}&lt;/code&gt;#g' \
  "census double-escape"

# === M19. ★S6 の D-* fail-closed 検査に ★tracked な teeth を与える (folio-eccf S6) ===
# ★旧形 (`| grep -v '^D-'`) は D-* id を ★両側から黙って落とす silent filter で、 canonical に正当な id="D-…" が
#   入ると 真の総数を ★過少報告 したまま欠落 assert も素通りした (narrow fail-open)。 S6 は filter を撤去し
#   「D-* が現れたら理由を問わず FAIL」へ転換した。 本 case はその検査が ★効いていることを tracked に pin する。
# ★理由 substring ("D-* id == 0") を課すので、 S6 の assert を消すと ★本 case が赤くなる (余剰 assert が
#   巻き添えで赤くしても substring は一致しない = 別 gate による ★見せかけの緑を弾く)。
f19_mut_reason "M19 ★生成物への D-* id 混入 (delta 印の anchor 集合汚染) を fail-closed 検査が捕捉" \
  's{(<span class="term")}{<span id="D-FAKE-1"></span>${1}}' \
  "D-* id == 0"

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
# ★政策 A per-shape 張替 (folio-7n17 deliverable 3/4): 旧「ORACLE parity」依存を frozen census (subject=生成物・
#   凍結 literal) へ張り替える。 各 shape で「変異 → どの census chk が FAIL 転落するか」を各行に明記し、 1 shape で
#   全代表しない (jyfh/r8k)。 剥奪すると生成物側 occurrence が frozen literal を下回り census が FAIL する
#   (相対 parity 依存でないため SPEC_ORIGIN_HTML=mutated の自己比較でも生きる = 下記 M-SELFCMP 群が別途 pin)。
f19_mut "★rich: a.xref 1 個剥奪 → census rich a.xref (31→30) FAIL" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
f19_mut "★rich: span.term 1 個剥奪 → census rich span.term (27→26) FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
f19_mut "★rich: ins.delta 1 個剥奪 → census rich ins|del.delta (5→4) FAIL" \
  's#<ins class="delta"[^>]*>(.*?)</ins>#$1#s' "census rich: ins|del.delta"
f19_mut "★0-e: jq -S を text ごと削除 → census jq-S (PRESERVE assert・how-outside 緑でも落ちる) FAIL" \
  's#<code>jq -S</code>##' "census jq-S"
# ★generic inline (code/span) の人間層 table-cell occurrence 剥奪 (M18 二重 escape と別の「純減」経路)。
f19_mut "★generic: 人間層 <code> table-cell 1 個の <code> wrapper 剥奪 → census generic <code> table-cell (41→40) FAIL" \
  's#(<td[^>]*>[^<]*)<code>([^<]*)</code>#${1}${2}#' "census generic: 人間層 <code> table-cell"
f19_mut "★generic: 人間層 <span> table-cell 1 個の span wrapper 剥奪 → census generic <span> table-cell (58→57) FAIL" \
  's#(<td[^>]*>)<span\b[^>]*>(.*?)</span>#${1}${2}#s' "census generic: 人間層 <span> table-cell"
# ★errata-1 must-2: per-shape 穴 4 領域の teeth (M18 は code table-cell しか撃たない・[FAIL] 行限定 reason で該当 census
#   chk が実弾で落ちることを per-mut で pin する)。 各 reason は census chk ラベルの一意 substring で [FAIL] 行 anchor。
# (a) FZ_ESC_XREF: 散文中の escape 済 literal '&lt;a class="xref"' を 1 個潰す (3→2) → census escape が FAIL。
f19_mut "★escape: &lt;a class=\"xref\" literal 1 個潰し (3→2) → census escape FAIL" \
  's#&lt;a class="xref"#\&lt;a class="ZZDROP"#' "census escape"
# (b) FZ_ESC_SPAN: 人間層 td の live <span> を 1 個二重 escape → &lt;span literal 増 (2→3) → census double-escape &lt;span が FAIL。
f19_mut "★double-escape: td の live <span> を二重 escape (&lt;span 2→3) → census double-escape &lt;span FAIL" \
  's#(<td[^>]*>)<span\b([^>]*)>(.*?)</span>#${1}\&lt;span$2\&gt;$3\&lt;/span\&gt;#s' "census double-escape: &lt;span"
# (c) generic <code> caption 領域: figcaption 内の <code> を 1 個剥奪 (2→1) → census generic <code> caption が FAIL。
f19_mut "★generic: figcaption の <code> wrapper 剥奪 (caption 2→1) → census generic <code> caption FAIL" \
  's#(<figcaption>.*?)<code>([^<]*)</code>#${1}${2}#s' "census generic: 人間層 <code> caption"
# (d) generic <code> rest 領域: rq-essence 内の <code> を 1 個剥奪 (79→78) → census generic <code> rest が FAIL。
f19_mut "★generic: rq-essence の <code> wrapper 剥奪 (rest 79→78) → census generic <code> rest FAIL" \
  's#(class="rq-essence">[^<]*)<code>([^<]*)</code>#${1}${2}#' "census generic: 人間層 <code> rest"
# (e) generic <span> caption 領域: figcaption 内の <span> を 1 個剥奪 (1→0) → census generic <span> caption が FAIL。
f19_mut "★generic: figcaption の <span> wrapper 剥奪 (caption 1→0) → census generic <span> caption FAIL" \
  's#(<figcaption>.*?)<span\b[^>]*>(.*?)</span>#${1}${2}#s' "census generic: 人間層 <span> caption"
# ★JSON-LD folio:stakeholders の array→string 型退行 → census JSON-LD (型退行封鎖) FAIL。
f19_mut "★JSON-LD: folio:stakeholders array→string 型退行 → census JSON-LD FAIL (型退行封鎖)" \
  's#"folio:stakeholders": \[[^\]]*\]#"folio:stakeholders": "Developer, AI Agent, External Reviewer"#' "census JSON-LD"
# ★id-rename (count 保存 substitution・deliverable 5): count は 55==55 で素通るが SET census が捕捉。
f19_mut "★id-rename: req-ver-001→req-ver-RENAMED (count 55 保存) → census id-rename SET FAIL (count census は素通る)" \
  's#id="req-ver-001"#id="req-ver-RENAMED"#' "census id-rename SET"
# ★delta-id rename (count 保存 substitution・deliverable 5・SET arm の teeth): id-rename SET (navigable) と対称に、
#   delta-id SET census が「件数不変で delta-id を改名した」退行クラス (SET arm を新設した当の理由) を捕捉することを
#   per-shape で pin する (jyfh/r8k: ins.delta 剥奪の count 減だけでは SET arm の count 保存 teeth を証明しない)。
#   D-2026-05-27-001 (4 occurrence) を別値へ rename → count は 5==5 で素通るが SET が 余剰/欠落 で FAIL。
f19_mut "★delta-id rename: D-2026-05-27-001→D-RENAMED (count 5 保存) → census delta-id SET FAIL (count census は素通る)" \
  's#data-delta-id="D-2026-05-27-001"#data-delta-id="D-RENAMED"#g' "census delta-id SET"
# ★machine-block round-trip: 生成物の spec-machine-prose に語を注入 → contract と乖離 → round-trip FAIL。
f19_mut "★machine-block: spec-machine-prose に語注入 → contract↔生成物 round-trip FAIL (assembler 乖離検出)" \
  's#(<p data-component="spec-machine-prose" data-audience="machine">)#${1}ZZTAMPERZZ #' "機械層 不一致"
# F19z. ★空撃ち検査 (恒真 FAIL の封鎖): 無改変の baseline は上記 gate 群で FAIL しないこと。
#   これが無いと verify が何を食わせても FAIL する状態でも F19 群は全て緑になる。
if bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" >/dev/null 2>&1; then
  ok "F19z ★空撃ち検査: 無改変 baseline は verify PASS = F19 群の FAIL は mutation 由来"
else
  ng "F19z 無改変 baseline が verify FAIL (恒真 FAIL ゆえ F19 群が無意味。 環境要因 gate F 等を切り分けること)"
fi

# === M-SELFCMP. ★本番自己比較 MK (folio-7n17 deliverable 4): SPEC_ORIGIN_HTML=mutated_html でも frozen census が
#   依然 FAIL する (ORIG==生成物 の自己比較でも census が生きる証明)。 政策 A の核心 — 旧相対 parity なら
#   c_xref(ORIG)==c_xref(HTML)==30 で vacuous PASS したが、 frozen 31 vs 生成物 30 で FAIL する。
#   flip 後に canonical が生成物へ置換され ORIG==生成物 になる本番条件を SPEC_ORIGIN_HTML=mutated で模す。 ===
selfcmp_mut() { # label perl-expr reason
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/selfcmp.html"
  if diff -q "$TMP/base-filled.html" "$TMP/selfcmp.html" >/dev/null; then
    ng "M-SELFCMP $1 (mutation 空撃ち)"; return
  fi
  local out rc; out="$(SPEC_ORIGIN_HTML="$TMP/selfcmp.html" bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/selfcmp.html" 2>&1)"; rc=$?
  # ★reason 照合は [FAIL] 行 anchor (errata-1 must-1): census chk ラベルは [OK] 行にも出るため fixed-string 2 段で anchor。
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then ok "M-SELFCMP $1"
  else ng "M-SELFCMP $1 (SPEC_ORIGIN_HTML=mutated 自己比較で census が [FAIL] 行に無い rc=$rc / reason '$3' 不発 = 相対 parity 恒真化の回帰)"; fi
}
selfcmp_mut "★a.xref 1 個剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census FAIL (自己比較恒真化の封鎖)" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
selfcmp_mut "★span.term 1 個剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
selfcmp_mut "★人間層 <code> table-cell wrapper 剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census generic FAIL" \
  's#(<td[^>]*>[^<]*)<code>([^<]*)</code>#${1}${2}#' "census generic: 人間層 <code> table-cell"

# === CEN-{cmt,attr,tpl} / CEN-id4. ★parser-differential laundering 3 vector + id 重複 の封鎖 (folio-7st6) ===
#   ★rules arm (folio-7wbn / verify-spec.sh §10b + test-adversarial-spec.sh CEN 群) で是正された parser-differential
#   が verification 側 counter に ★残存していた非対称の解消。 §10b の census counter を naive regex から実 HTML
#   parser の 1 walk (census_dump) へ寄せたので、 その teeth を per-shape mutation-kill で tracked に pin する。
#   ★per-shape に分ける理由 (jyfh/r8k): comment 本体 / 属性値 / 非描画 subtree は DOM 形状が別クラスゆえ、
#   1 instance の実弾は構造差のある instance の穴を証明しない。
#   ★両方向を撃つ: (1) deflate = live 資産 1 個剥奪 + decoy で凍結値へ「復元」しても census が FAIL し続けること
#   (laundering 封鎖)、 (2) inflate = 正当な decoy を足しただけでは census が動かないこと (偽 FAIL 封鎖)。
#   ★decoy の id / delta-id は verification 実 census shape (req-ver-* / s6-references / D-2026-05-27-*) を使う
#   (rules の req-ci-001 / s5-delta を写経すると生成物に存在せず SET 復元を狙う teeth が空撃ちになる)。
#   ★reason 照合は f19_mut_reason ([FAIL] 行 anchor + fixed-string 2 段) へ翻案する: census ラベルは [OK] 行にも
#   出るため素朴 substring では「別 gate の巻き添え FAIL + 当該 census は [OK]」を緑と誤判定する (恒真 = vacuous-green)。

# --- CEN-cmt. ★HTML コメント laundering ---
#   live な a.xref を 1 個失っても `<!-- <a class="xref"></a> -->` を 1 個足せば凍結 31 へ復元でき、 政策 A の
#   【唯一の独立 anchor】が edit-SSoT 側 (contract.machine_blocks[].html は raw 出力) から水増しできてしまう。
CEN_DECOY='<!-- decoy: <a class="xref" href="#x">z</a> <span class="term" data-term="z">z</span> <ins class="delta" data-delta-id="D-ZZ-1">z</ins> <code>z</code> <div id="ZZDECOY"></div> &lt;a class="xref" &lt;code &lt;span -->'
f19_mut_reason "CEN-cmt1 ★a.xref 剥奪 + コメント decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-cmt2 ★span.term 剥奪 + コメント decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_DECOY}" "census rich: span.term"

# ★inflate assert の共通形 (CEN-cmt3 / attr5 / tpl5)。 assert は verify 全体の PASS ではなく ★census 行だけに絞る:
#   同 decoy は §10b 外の arm (self-anchor 整合 / 人間層 xref floor 等) を落としうるが、 それは本 finding の対象外
#   かつ fail-closed 方向の別欠陥ゆえ conflate しない。 ★[OK] census 行の下限を課すのは「census arm 群が実際に走った」
#   ことの pin (silent skip なら [OK] 0 本で緑になる = 恒真 PASS の封鎖)。 現行 §10b は census 22 本。
cen_inflate() { # label decoy
  # ★第 3 引数 = 注入 anchor (既定 <body> opener)。 CEN-head 群は <head> へ注入するため必要
  #   (既存 case は全て <body> opener 固定で、 head vector が ★構造的に無被覆 だった)。
  local lbl="$1" decoy="$2" anchor="${3:-<body[^>]*>}" out bad okn miss lab
  perl -0777 -pe "s{($anchor)}{\$1$decoy}" "$TMP/base-filled.html" > "$TMP/cen-inflate.html"
  if diff -q "$TMP/base-filled.html" "$TMP/cen-inflate.html" >/dev/null; then
    ng "$lbl ★decoy 注入が空撃ち (注入 anchor '$anchor' が実 DOM と不一致の疑い)"; return
  fi
  out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen-inflate.html" 2>&1)"
  bad="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*\[FAIL\][[:space:]]+census ' | head -3)"
  okn="$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*\[OK\][[:space:]]+census ')"
  # ★行数下限だけでは inflate 方向の恒真 PASS を防げない: 主 assert は「census の [FAIL] 行が無いこと」ゆえ
  #   census 検査が ★丸ごと消えても FAIL 0 本 = PASS になる。 旧下限 10 は実測 19 本 (rules) / 22 本 (verification)
  #   に対して緩すぎ、 消失を許す 9 本の中に本 helper の case (CEN-tplsc2 / tplsc4 / dupattr2) が ★実際に依存する
  #   h_inline generic 軸が丸ごと入っていた = 守るべき軸を失った状態でも PASS しえた。
  #   ゆえに (1) 実測値まで下限を上げ、 かつ (2) ★依存軸のラベルが [OK] 行として実在すること を fixed-string で撃つ。
  #   ★(2) が本体: 行数は census 増減でドリフトするが、 ラベル存在は「この case が何に依存しているか」を直接 pin する。
  #   ★[OK] 行へ anchor してから照合する 2 段構え (census ラベルは [FAIL] 行にも出るため素朴 substring は恒真)。
  miss=""
  for lab in 'census rich: a.xref' 'census generic: 人間層 <code> rest' 'census generic: 人間層 <code> 総数' 'census generic: 人間層 <span> table-cell'; do
    printf '%s\n' "$out" | grep -E '^[[:space:]]*\[OK\][[:space:]]+census ' | grep -qF -- "$lab" || miss="$miss [$lab]"
  done
  if [[ -z "$bad" && -z "$miss" && "$okn" -ge 22 ]]; then
    ok "$lbl (census 行 $okn 本すべて [OK]・依存軸 4 本実在・偽 FAIL 封鎖)"
  else
    ng "$lbl ★decoy で census が動いた/依存軸が消えた (inert 領域を live 計数 = parser-differential 回帰 / [OK] 数 $okn / 依存軸欠落:$miss): $bad"
  fi
}

# ★mutation 後に census が ★動かないこと を撃つ helper (folio-ahn3・admin 裁定 round-1 (a))。
#   cen_inflate と判定は同型 (census [FAIL] 行が無い + 依存軸 4 本が [OK] 実在 + [OK] census 行下限) だが、
#   ★注入のみ でなく ★剥奪 + 注入 の perl expr を取る点が違う (「剥奪分が ★live 資産で正当に復元される」
#   ground truth 整合を pin するため)。 ★恒真 PASS 封鎖が本体: 主 assert が「[FAIL] 行が無いこと」ゆえ
#   census 検査が丸ごと消えても成立してしまう — 依存軸の [OK] 実在と行数下限を ★対で 課して塞ぐ。
cen_mut_pass() { # label perl-expr
  local lbl="$1" out bad okn miss lab
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/cen-mutpass.html"
  if diff -q "$TMP/base-filled.html" "$TMP/cen-mutpass.html" >/dev/null; then
    ng "$lbl (mutation が生成物を変えていない = ★空撃ち。 selector が実 DOM と不一致の疑い)"; return
  fi
  out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen-mutpass.html" 2>&1)"
  bad="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*\[FAIL\][[:space:]]+census ' | head -3)"
  okn="$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*\[OK\][[:space:]]+census ')"
  miss=""
  for lab in 'census rich: a.xref' 'census generic: 人間層 <code> rest' 'census generic: 人間層 <code> 総数' 'census generic: 人間層 <span> table-cell'; do
    printf '%s\n' "$out" | grep -E '^[[:space:]]*\[OK\][[:space:]]+census ' | grep -qF -- "$lab" || miss="$miss [$lab]"
  done
  if [[ -z "$bad" && -z "$miss" && "$okn" -ge 22 ]]; then
    ok "$lbl (census 行 $okn 本すべて [OK]・依存軸 4 本実在)"
  else
    ng "$lbl ★census が動いた/依存軸が消えた ([OK] 数 $okn / 依存軸欠落:$miss): $bad"
  fi
}

cen_inflate "CEN-cmt3 ★コメント内タグ様文字列は §10b census を inflate しない" "$CEN_DECOY"

# --- CEN-attr. ★属性値 laundering (comment / script / style 本体を除いても raw byte として残る残余) ---
#   naive regex counter は単引用符属性の中のタグ様文字列を live 要素として数える。 ★id 軸を必ず含める
#   (`<section id="req-ver-001">` を属性値に置くと count 総数と SET を ★同時に 復元でき最悪形になる)。
#   ★escape literal も必ず含める (folio-7st6 ceiling major fix): 本 port は escape 軸 (ESC_XREF/ESC_CODE/ESC_SPAN) の
#   計数意味を「全文 raw regex」から「census_dump の ★text node 限定」へ変更した = 属性値の `&lt;code` 等は
#   ★今回から非計数 になった新しい封鎖クラス。 decoy に含めないと CEN-attr5 の inflate が escape 軸を ★一切踏まない。
CEN_ATTR_DECOY="<div data-launder='<a class=\"xref\" href=\"#z\">z</a> <span class=\"term\" data-term=\"z\">z</span> <ins class=\"delta\" data-delta-id=\"D-ZZ-1\">z</ins> <section id=\"s6-references\"></section> <section id=\"req-ver-001\"></section> <code>z</code> <span>z</span> &lt;a class=\"xref\" &lt;code &lt;span'></div>"
f19_mut_reason "CEN-attr1 ★a.xref 剥奪 + 単引用符属性 decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-attr2 ★span.term 剥奪 + 属性 decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census rich: span.term"
f19_mut_reason "CEN-attr3 ★id 剥奪 (57→56) + 属性 decoy で count 復元を狙う laundering を census 総数が FAIL" \
  "s{ id=\"s6-references\"}{}; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census navigable id: 総数"
f19_mut_reason "CEN-attr4 ★id rename + 属性 decoy で SET 復元を狙う laundering を census id-rename SET が FAIL" \
  "s{id=\"req-ver-001\"}{id=\"req-ver-RENAMED\"}; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census id-rename SET"
cen_inflate "CEN-attr5 ★属性値内タグ様文字列は §10b census を inflate しない" "$CEN_ATTR_DECOY"

# --- CEN-tpl. ★非描画 subtree (<template>) laundering ---
#   <template> の内容は browser が描画しない (inert DocumentFragment) = live 資産でないのに census が数えていた。
#   ★element 軸 (a.xref / span.term / id) と ★text/inline 軸 (h_inline の human <code>) の ★両方 を撃つ
#   (片方だけ直すと h_inline 側に同一 vector の穴が残る = CEN-tpl4 が当の pin)。
CEN_TPL_DECOY='<template><a class="xref" href="#z">z</a><span class="term" data-term="z">z</span><ins class="delta" data-delta-id="D-ZZ-1">z</ins><section id="s6-references"></section><section id="req-ver-001"></section><code>z</code><span>z</span>&lt;a class="xref" &lt;code &lt;span</template>'
f19_mut_reason "CEN-tpl1 ★a.xref 剥奪 + <template> decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-tpl2 ★span.term 剥奪 + <template> decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census rich: span.term"
f19_mut_reason "CEN-tpl3 ★id 剥奪 (57→56) + <template> decoy で count 復元を狙う laundering を census 総数が FAIL" \
  "s{ id=\"s6-references\"}{}; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census navigable id: 総数"
f19_mut_reason "CEN-tpl4 ★人間層 <code> 剥奪 + <template> decoy laundering を census generic が FAIL (h_inline 側の同 vector)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-tpl5 ★<template> 内の資産/タグ様文字列は §10b census を inflate しない" "$CEN_TPL_DECOY"

# --- CEN-tpl6/7. ★bogus comment 前置による <template> inert 除外の破壊 (folio-7st6 ceiling major) ---
#   ★4 byte で per-shape MK 群が全滅した実例の pin。 census subject を strip_inert の出力 (live view) に置いた版では、
#   strip_inert の handle_comment が cut 終端を `s + len(data) + 7` (`<!--` 4 + `-->` 3 の決め打ち) で算出する一方、
#   Python html.parser は ★bogus comment `<!x>` (実長 4 byte) にも handle_comment(data='x') を発火するため、
#   計算長 8 で ★直後の live 4 byte を過剰削除した。 結果 `<!x><template>` → `plate>` となり ★<template> 開始タグが
#   破壊されて中身が live 化し、 CEN-tpl1..5 が封鎖したはずの laundering クラスが ★丸ごと再開通していた (実測再現済)。
#   ★対策は census subject を RAW $HTML へ戻すこと (census_dump / h_inline は共に実 HTML parser で comment /
#   script / style を非計数・<template> を除外済ゆえ strip_inert 前処理は不要どころか ★唯一の穴 だった)。
#   ★両方向を撃つ: tpl6 = inflate (前置しても census は動かない) / tpl7 = deflate (前置しても復元は封鎖され続ける)。
#   ★4 byte を足すだけで CEN-tpl1 の実弾が空砲化したので、 tpl7 は「同 mutation から `<!x>` を外した control でも
#   FAIL する」ことに依存せず ★`<!x>` 付きの側 が FAIL することを直接 assert する (control は CEN-tpl1 が担当)。
CEN_BOGUS_TPL_DECOY="<!x>$CEN_TPL_DECOY"
cen_inflate 'CEN-tpl6 ★bogus comment <!x> 前置でも <template> 内は §10b census を inflate しない' "$CEN_BOGUS_TPL_DECOY"
f19_mut_reason "CEN-tpl7 ★a.xref 剥奪 + <!x> 前置 <template> decoy による凍結値復元 (inert 除外の 4 byte 破壊) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_BOGUS_TPL_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-tpl8 ★人間層 <code> 剥奪 + <!x> 前置 <template> decoy laundering を census generic が FAIL (h_inline 側の同 vector)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_BOGUS_TPL_DECOY}" "census generic: 人間層 <code> rest"

# --- CEN-id4. ★id 重複 (unique 保存・anchor hijack) ---
#   count census も SET census も共に ★dedup 後 の unique 集合を見るため、 既存 id の複製注入は unique 57 を保存した
#   まま原理的に検出できなかった。 HTML の fragment 解決は文書順 first-match ゆえ、 本文より前に空の複製 anchor を
#   置くと当該 id を指す全 xref がその空要素へ hijack され navigation が壊れる。 ★凍結 literal を増やさず
#   「unique == 総出現」の構造的不変条件で撃つ (census file / provenance sha 無改訂)。
f19_mut_reason "CEN-id4 ★既存 id の複製注入 (unique 57 保存・anchor hijack) を重複 chk が FAIL" \
  's{(<body[^>]*>)}{${1}<div id="s6-references"></div>}' "census navigable id: 重複 0"

# --- CEN-esc. ★escape literal 軸 (ESC_XREF / ESC_SPAN) の deflate/laundering (folio-7st6 ceiling major) ---
#   本 port は escape 軸の計数意味を「全文 raw regex (perl -0777 /&lt;code/g)」から「census_dump の ★text node 限定」へ
#   ★変更した (契約 b)。 つまり comment / 属性値 / <template> 内の `&lt;code` は今回から ★非計数 = 新たに閉じた
#   laundering クラスである。 ところが既存 teeth は f19_mut の素の増減のみで、 ★攻撃形そのものである deflate-復元
#   方向 (live literal を 1 個潰し inert decoy で凍結値へ戻す) が全 shape で 0 本だった。 handle_data /
#   handle_entityref / handle_charref の `not self.inert()` や text 限定判定を将来緩めても suite が緑のままになるため、
#   ★per-shape (cmt / tpl / attr) × deflate で tracked に pin する (element 軸の CEN-cmt/attr/tpl と同 doctrine)。
#   ★ESC_CODE は凍結 0 ゆえ deflate 不能 (0 未満にできない) = inflate 側 (CEN-cmt3 / attr5 / tpl5) が唯一の teeth。
f19_mut_reason "CEN-esc1 ★&lt;a class=\"xref\" literal 1 個潰し + ★コメント decoy で凍結値復元を狙う laundering を census escape が FAIL" \
  "s{&lt;a class=\"xref\"}{&lt;a class=\"ZZDROP\"}; s{(<body[^>]*>)}{\$1$CEN_DECOY}" "census escape"
f19_mut_reason "CEN-esc2 ★同 literal 潰し + ★<template> decoy による復元を census escape が FAIL" \
  "s{&lt;a class=\"xref\"}{&lt;a class=\"ZZDROP\"}; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census escape"
f19_mut_reason "CEN-esc3 ★&lt;span literal 1 個潰し + ★属性値 decoy による復元を census double-escape が FAIL" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census double-escape: &lt;span"

# --- CEN-dupattr. ★重複属性 last-wins による data-audience laundering (folio-7st6 ceiling major) ---
#   HTML Standard では重複属性は ★最初 が勝つ (2 つ目以降は parse error として破棄) ため
#   `<div data-audience="machine" data-audience="human">` を browser は ★機械層 と解釈する。 h_inline が
#   `dict(attrs)` (= last-wins) だと ★人間層 として計上し、 「live な人間層 <code> を 1 個剥奪 → 重複属性で
#   偽の人間層資産を 1 個注入」で凍結値へ復元できた (CEN-tpl4 / M18 が守る性質が同一クラスの手で破れる)。
#   census_dump は既に first-wins ゆえ ★同一 walk 内の非対称 だった。 両方向を撃つ。
CEN_DUPATTR_DECOY='<div data-audience="machine" data-audience="human"><code>z</code></div>'
f19_mut_reason "CEN-dupattr1 ★人間層 <code> 剥奪 + 重複属性 (machine→human 上書き) decoy による復元を census generic が FAIL" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_DUPATTR_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-dupattr2 ★重複属性 data-audience の ★最初 (machine) が勝ち §10b census を inflate しない" "$CEN_DUPATTR_DECOY"

# --- CEN-tplsc. ★自己閉じ形 <template/> による inert 除外の 1 byte 迂回 (folio-7st6 ceiling major) ---
#   Python html.parser は `<template/>` に対し handle_starttag ではなく ★handle_startendtag を発火する。
#   h_inline は本 hook を override しておらず base 既定 (starttag→endtag) が走るため push 直後に pop され、
#   ★inert 区間にならなかった = `/` 1 文字で CEN-tpl4/8 の per-shape MK が全滅していた (実測再現済)。
#   HTML Standard では ★非 void 要素の trailing solidus は無視され `<template/>` は template を ★開く (中身は inert)。
#   ★element 軸 (census_dump) の同一迂回は ★folio-gt4s で両 arm 同時に是正済 (handle_startendtag で
#   INERT_SUBTREE のみ push する最小形)。 element 軸と text/inline 軸は別実装ゆえ ★両軸を per-shape で撃つ (片軸は残穴)。
#   ★push を template のみ に絞る最小形が要件: `not in VOID` 相当だと canonical の自己閉じ SVG (`<path/>` 等) が
#   閉じられず stack を汚染し region / inert 判定を壊す (別クラスの誤計数)。 ★その回帰のうち CEN-tplsc4 が
#   実際に撃てるのは ★text/inline 軸 のみ (element 軸は naive 形にしても差が出ず ★恒真 PASS だった = errata-1
#   MUST-6)。 element 軸の最小形要件は ★MINFORM 節の静的 fixed-string pin が担う。
CEN_TPLSC_DECOY='<template/><code>z</code></template>'
CEN_TPLSC_EL_DECOY='<template/><a class="xref" href="#z">z</a><span class="term" data-term="z">z</span><ins class="delta" data-delta-id="D-ZZ-1">z</ins><section id="s6-references"></section><section id="req-ver-001"></section><code>z</code><span>z</span>&lt;a class="xref" &lt;code &lt;span</template>'
f19_mut_reason "CEN-tplsc1 ★人間層 <code> 剥奪 + ★自己閉じ <template/> decoy による復元を census generic が FAIL (text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_TPLSC_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-tplsc2 ★自己閉じ <template/> 内の資産/タグ様文字列は §10b census を inflate しない (両軸)" "$CEN_TPLSC_EL_DECOY"
f19_mut_reason "CEN-tplsc3 ★a.xref 剥奪 + ★自己閉じ <template/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPLSC_EL_DECOY}" "census rich: a.xref"
# ★最小形 (push を INERT_SUBTREE のみ に絞る) の ★実弾 pin: template ★以外 の自己閉じ要素まで push すると
#   stack が閉じられず、 後続の inert 判定 (element 軸) と region 判定 (text/inline 軸) が巻き添えで壊れる。
#   ★decoy は「汚染 stack が回収されず、 かつ汚染区間内に計数対象が居る」形でないと ★恒真 PASS になる:
#   旧 decoy `<svg><path/><circle/><rect/></svg>` は (a) `</svg>` が `del self.stack[i:]` で汚染を ★即回収 し、
#   (b) 汚染区間に計数対象が 1 個も無いため、 naive 形 (`not in VOID` 相当) と最小形の出力が ★完全同一 だった
#   (実測: 両 arm とも rc 0 / census [FAIL] 0 = 何も pin していない vacuous-green ゆえ差し替えた)。
#   ★現 decoy は red→green を ★両 arm・両軸 で実弾実証済 (naive 形注入で下記が動く / 最小形では全軸不動):
#     element 軸     = `<span/>` が push されたまま残り `</span>` が ★template ごと stack を巻き取る
#                      (del self.stack[i:]) → template 内 a.xref が live 化 → C_XREF 26→27 (verification arm 31→32)。
#     text/inline 軸 = `<td/>` が push されたまま残り、 以降の人間層 <code> が全て table-cell へ誤 region 化
#                      → code rest 9→0 / table-cell 0→10 (verification arm 79→0 / 43→123)。
#   inflate 方向で撃つ (最小形なら census は 1 軸も動かない = 動いたら NG)。
cen_inflate "CEN-tplsc4 ★template 以外の自己閉じ要素は stack を汚染せず §10b census を偽 FAIL させない (★text/inline 軸のみ・element 軸の最小形要件は MINFORM が静的に pin)" \
  '<td/><span/><template></span><a class="xref" href="#z">z</a><code>z</code></template>'

# --- CEN-head. ★<head> 内容も census の視野に入る (folio-gt4s errata-1 MUST-1 の anti-regression pin・3 軸) ---
#   本 cell は一度 census_dump / h_inline へ「<body> 開始タグまで非計数」の inbody scoping を新設したが、
#   ★それは base で機能していた防壁を殺す live fail-open だった: HTML5 の insertion mode では <head> 内の
#   flow content は body へ移送され ★実際に描画される。 html.parser は insertion mode を持たないため
#   <body> latch は「描画されるのに census が数えない」= ★攻撃者専用の隠し場所 を新設していた。
#   実測 (同一 head mutant): inbody 版 = exit0 / FAIL 0 で ★素通り、 base 8d4eeda 版と errata 是正版 = 共に
#   4 本 FAIL で ★検出。 ゆえに inbody scoping を撤去し base 挙動 (文書全体 subject) へ回帰した。
#   ★本群は「head が blind spot でないこと」を ★inflate 方向 で撃つ (head へ資産を置けば census が動く)。
#   将来また head scoping が入ると本群が赤くなる = 回帰の tracked 検出器。
#   ★「head へ live 資産を注入して剥奪分を復元する」形は ★MK にしない: 注入資産は実際に描画される live
#   資産ゆえ復元は正当であり、 head 固有の脆弱性ではなく frozen count 一般の限界 (admin 裁定)。
#   ★element / escape / text-inline の 3 軸は別実装ゆえ per-shape で撃つ (片軸だけでは残穴)。
f19_mut_reason "CEN-head1 ★<head> への既存 id 複製注入を census が検出 (★element 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1<div id=\"req-ver-001\"></div>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-head2 ★<head> への escape literal 注入を census が検出 (★escape 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1&lt;span }" "census double-escape: &lt;span"
f19_mut_reason "CEN-head3 ★<head> への人間層 <code> 注入を census が検出 (★text/inline 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1<code>z</code>}" "census generic: 人間層 <code> rest"

# --- CEN-tplesc. ★stray end tag による inert subtree の巻き取り (folio-gt4s ceiling 2 巡目 major fix・両軸) ---
#   handle_endtag の素朴な `del self.stack[i:]` は ★祖先 に一致する end tag でも template を巻き取って外すため、
#   `<template></div>...</template>` のように ★不一致 end tag を 1 本置くだけで inert 区間が解除され、
#   中身 (browser では ★非描画) が live 計上された。 HTML5 の in-template 挿入モードでは不一致 end tag は
#   parse error として ★無視 され template は開いたまま。 ★element 軸 / text 軸 / 自己閉じ形 を per-shape で撃つ。
CEN_TPLESC_DECOY='<div data-audience="machine"><template></div><a class="xref" href="#z">z</a><code>z</code></template></div>'
CEN_TPLESC_SC_DECOY='<div data-audience="machine"><template/></div><a class="xref" href="#z">z</a><code>z</code></template></div>'
f19_mut_reason "CEN-tplesc1 ★a.xref 剥奪 + stray </div> で <template> を巻き取る decoy の凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPLESC_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-tplesc2 ★人間層 <code> 剥奪 + 同 decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_TPLESC_DECOY}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-tplesc3 ★自己閉じ <template/> + stray </div> 形 (別 shape) の element 軸復元を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPLESC_SC_DECOY}" "census rich: a.xref"
cen_inflate "CEN-tplesc4 ★stray end tag 入り <template> は §10b census を inflate しない (偽 FAIL 封鎖・両軸)" "$CEN_TPLESC_DECOY"

# --- CEN-scsc. ★自己閉じ <script/> による raw text 区間の live 計上 (folio-gt4s ceiling 2 巡目 major fix・両軸) ---
#   通常形 <script> は html.parser の CDATA mode が中身をタグとして emit しないため実害が無かったが、
#   ★自己閉じ形 `<script/>` は handle_startendtag 発火ゆえ CDATA mode に入らず、 browser が `</script>` まで
#   raw text (= ★非描画) 扱いする区間を census が live 計上していた (`/` 1 文字の迂回・CEN-tplsc と同一クラス)。
#   ★canonical に自己閉じ script/style は 0 件 (grep verified) ゆえ是正の副作用なし。 両軸を per-shape で撃つ。
CEN_SCSC_EL_DECOY='<div data-audience="machine"><script/><a class="xref" href="#z">z</a></script></div>'
CEN_SCSC_TX_DECOY='<script/><code>z</code></script>'
f19_mut_reason "CEN-scsc1 ★a.xref 剥奪 + 自己閉じ <script/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_SCSC_EL_DECOY}" "census rich: a.xref"
f19_mut_reason "CEN-scsc2 ★人間層 <code> 剥奪 + 自己閉じ <script/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1$CEN_SCSC_TX_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-scsc3 ★自己閉じ <script/> 区間は §10b census を inflate しない (偽 FAIL 封鎖・element 軸)" "$CEN_SCSC_EL_DECOY"


# --- CEN-rt. ★raw text / RCDATA 要素の ★自己閉じ形 による inert 迂回 (folio-gt4s errata-1 MUST-3・両軸) ---
#   INERT を {'template','script','style'} と ★手書き列挙 した版は partial-enumeration trap だった:
#   textarea / title / xmp / iframe / noembed / noframes の自己閉じで ★同一クラスが再開通した (実測)。
#   是正は集合を ★parser 自身から導出すること (HTMLParser.CDATA_CONTENT_ELEMENTS | RCDATA_CONTENT_ELEMENTS):
#   parser の認識と census の inert 判定が構造的に同期し、 列挙漏れが原理的に生じない。
#   ★本群は「導出集合が痩せたら赤くなる」検出器。 ★1 tag の実弾は別 tag の穴を証明しない ゆえ ★全 tag ×
#   element 軸 / text-inline 軸 を per-shape で撃つ (deflate = 剥奪 + decoy 復元が封鎖され続けること)。
f19_mut_reason "CEN-rt-script-el ★a.xref 剥奪 + 自己閉じ <script/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><script/><a class=\"xref\" href=\"#z\">z</a></script></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-style-el ★a.xref 剥奪 + 自己閉じ <style/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><style/><a class=\"xref\" href=\"#z\">z</a></style></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-xmp-el ★a.xref 剥奪 + 自己閉じ <xmp/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><xmp/><a class=\"xref\" href=\"#z\">z</a></xmp></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-iframe-el ★a.xref 剥奪 + 自己閉じ <iframe/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><iframe/><a class=\"xref\" href=\"#z\">z</a></iframe></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-noembed-el ★a.xref 剥奪 + 自己閉じ <noembed/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><noembed/><a class=\"xref\" href=\"#z\">z</a></noembed></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-noframes-el ★a.xref 剥奪 + 自己閉じ <noframes/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><noframes/><a class=\"xref\" href=\"#z\">z</a></noframes></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-textarea-el ★a.xref 剥奪 + 自己閉じ <textarea/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><textarea/><a class=\"xref\" href=\"#z\">z</a></textarea></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-title-el ★a.xref 剥奪 + 自己閉じ <title/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><title/><a class=\"xref\" href=\"#z\">z</a></title></div>}" "census rich: a.xref"
f19_mut_reason "CEN-rt-script-tx ★人間層 <code> 剥奪 + 自己閉じ <script/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<script/><code>z</code></script>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-style-tx ★人間層 <code> 剥奪 + 自己閉じ <style/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<style/><code>z</code></style>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-xmp-tx ★人間層 <code> 剥奪 + 自己閉じ <xmp/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<xmp/><code>z</code></xmp>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-iframe-tx ★人間層 <code> 剥奪 + 自己閉じ <iframe/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<iframe/><code>z</code></iframe>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-noembed-tx ★人間層 <code> 剥奪 + 自己閉じ <noembed/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<noembed/><code>z</code></noembed>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-noframes-tx ★人間層 <code> 剥奪 + 自己閉じ <noframes/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<noframes/><code>z</code></noframes>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-textarea-tx ★人間層 <code> 剥奪 + 自己閉じ <textarea/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<textarea/><code>z</code></textarea>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rt-title-tx ★人間層 <code> 剥奪 + 自己閉じ <title/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<title/><code>z</code></title>}" "census generic: 人間層 <code> rest"

# --- CEN-nest. ★入れ子 inert を ★外から 閉じる stray end tag (folio-gt4s errata-1 MUST-4・両軸) ---
#   ★★本群の捕捉範囲 (宣言能力 == 実能力・errata-2 MUST-B / ★folio-ahn3 で ★HTML 名前空間の当該形を閉塞・
#   ★foreign content 経由は ★未閉塞):
#     ★捕れる = element 系 inert (template) の scope 境界 / 正しく閉じた入れ子 inert /
#               指定 2 shape (<template><script/></template> / <template><textarea/></template>) —
#               CEN-nest1/2/3/5 で per-shape に実弾 pin 済。 ★逆順 shape (<script/><template></script>) は
#               folio-ahn3 の是正で ★捕捉対象から外れた (後続は ground truth どおり live ゆえ live 資産による
#               復元は正当)。 CEN-nest4 は ★期待反転 で保持され (admin 裁定 2026-07-21)、 「後続が live 計上
#               される」ground truth 整合を pin する ★生きた MK として残る。
#     ★閉塞済 (folio-ahn3・★HTML 名前空間 に限る) = RAWTEXT 系 inert (script/style/xmp/iframe/noembed/noframes/
#               textarea/title) を ★自己閉じで開いた後に別の inert 開始タグを挟み ★末尾で閉じ直す 形。 かつては
#               挟んだ区間が census の ★有界な盲点 になっていた (8 タグ × 両軸で同型・base 8d4eeda からの
#               pre-existing)。 ★是正済: handle_startendtag が RAWTEXT 系へ set_cdata_mode を与えるため区間内の
#               タグは emit されず (= 挟めない)、 自分の end tag が inert を正しく閉じる。 ★CEN-rawnest 群
#               (8 タグ × element / text-inline / escape literal の 3 軸) が per-shape に実弾 pin する。
#     ★未閉塞 (★同族・foreign content 経由・★live fail-open) = `<svg>` / `<math>` 内の ★自己閉じ RAWTEXT
#               (例 `<svg><script/></svg>…</script>`)。 foreign content では自己閉じが ★正規に閉じる ため実
#               browser は raw text を開かないが、 census は set_cdata_mode を ★名前空間非依存 に与えるため raw
#               区間を開いてしまい、 末尾 stray end tag で閉じ直せる (実測: INJ 非計数 / ESC_SPAN=0 の一方で
#               tail は計上 = ★他 census 値は無傷 の同族 bounded blind spot・両 arm 同型・★base c55bac6 でも
#               同一挙動 = pre-existing)。 名前空間追跡を要する parser semantics の再設計ゆえ folio-ahn3 の
#               契約外 = ★folio-3z10 として ★起票済 (admin 裁定 2026-07-21・本 cell では触らない)。
#               ★本群は当該クラスを ★撃っていない (過大宣言をしない)。
#   inert scope 境界の探索下限を「end tag 名が inert でないとき」だけ導出していた版は、 inert 名の end tag が
#   ★入れ子 inert を外から閉じられた: `<template><script/></template>` で <script/> が開いた raw text 区間ごと
#   解除され、 後続が live 計上された (実測: 凍結値復元が成立)。 HTML5 では raw text 内の `</template>` は
#   ★ただの文字列 ゆえ script も template も閉じない。
#   是正は探索下限を ★最内 inert 位置から無条件に 導出すること (inert 名の end tag は最内 inert 自身のみを
#   閉じうる)。 ★入れ子の組み合わせは構造が別クラスゆえ per-shape で撃つ。
f19_mut_reason "CEN-nest1 ★a.xref 剥奪 + <template><script/></template> による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<template><script/></template><a class=\"xref\" href=\"#z\">z</a>}" "census rich: a.xref"
f19_mut_reason "CEN-nest2 ★人間層 <code> 剥奪 + 同 vector による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(class=\"rq-essence\">[^<]*)<code>([^<]*)</code>}{\${1}\${2}}; s{(<body[^>]*>)}{\$1<template><script/></template><code>z</code>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-nest3 ★内側 tag 違い <template><textarea/></template> 形 (別 shape) の element 軸復元を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<template><textarea/></template><a class=\"xref\" href=\"#z\">z</a>}" "census rich: a.xref"
#   ★★CEN-nest4 は ★期待反転 で保持 (admin 裁定 2026-07-21・folio-ahn3)。 folio-ahn3 が RAWTEXT 系 inert の
#   自己閉じ経路へ CDATA mode を与えたことで、 本 shape (`<script/><template></script>X`) の X は HTML5 の
#   ground truth どおり ★live (`</script>` が raw text を閉じる) になった。 admin が uv + html5lib で独立に
#   ground truth を取得し (後続 a.xref の ancestors = [html, body] = 実描画)、 worker 差戻し主張と一致を確認
#   した上で「退役ではなく ★期待反転 で保持」と裁定 (fix 後の正挙動を pin する ★生きた MK として価値が残る)。
#   ★旧期待 (census が FAIL する) は ★folio-ahn3 が塞いだ盲点そのものに依存していた: base では後続が inert 化
#   して a.xref=0 へ落ちるため「復元を検出した」ように見えていた。 是正後は剥奪分を ★live 資産で復元する形 =
#   既 admin 裁定「注入資産が実描画される復元は ★正当 ゆえ MK にしない」(CEN-head 節) と同じクラスへ移る。
#   ★新期待 = census が ★動かないこと + ★依存軸の [OK] 実在 (恒真 PASS 封鎖)。 base c55bac6 では赤・是正後は緑
#   = genuine red→green ゆえ、 盲点が再開通すれば本 case が ★赤で気付ける (回帰検出器として生き続ける)。
cen_mut_pass "CEN-nest4 ★入れ子順 逆 <script/><template></script> 形 — </script> 相当の end tag が raw text を閉じ後続が ★live 計上 される (ground truth 整合・admin 裁定 2026-07-21 で期待反転)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<script/><template></script><a class=\"xref\" href=\"#z\">z</a>}"
# ★inflate 方向は ★正しく閉じた 入れ子 inert で撃つ。 ★閉じない形 (<template><script/></template>) を
#   inflate case に使ってはならない: 自己閉じ <script/> は HTML5 で raw text を開き `</template>` は
#   ★ただの文字列 ゆえ script も template も閉じず、 ★以降の文書全体が正当に inert 化する (census 0 = 実測)。
#   これは browser 準拠の ★正しい 挙動であり偽 FAIL ではない。 ゆえに「動かないはず」と主張する形は
#   ★誤った pin になる。
#   ★訂正 (errata-2 MUST-A・実測で偽だった旧記述の是正): 「攻撃者が使えば全 census が 0 へ落ちて即 FAIL
#   = fail-closed」とは ★言えない。 攻撃者は末尾で `</template></script>` と ★閉じ直せる ため、 挟んだ区間
#   だけを census の盲点にして ★他の census 値を無傷 に保てる (= 有界な盲点。 実測: canonical <body> 直後へ
#   `<script/><template></script><div id="INJECTED-HIJACK">…</div></template></script>` を注入すると
#   両 arm exit0 / FAIL 0 で、 注入区間の id / 人間層 code / escape literal が ★いずれも非計数)。
#   当該クラスは base 8d4eeda から存在した ★pre-existing な穴で、 ★folio-ahn3 が ★HTML 名前空間の当該形 を
#   閉塞した (handle_startendtag へ set_cdata_mode を追加)。 ★本 suite は ★HTML 名前空間形 を ★CEN-rawnest 群で
#   捕れる ——ただし ★1 点を宣言から除く (宣言能力 == 実能力): ★foreign content 経由 (`<svg>/<math>` 内の
#   自己閉じ RAWTEXT) の同族形は ★未閉塞 (live fail-open・base c55bac6 からの pre-existing・★folio-3z10 として
#   起票済)。 なお ★CEN-nest4 は本是正により ★期待反転 で保持されている (admin 裁定 2026-07-21・上記 注記)。
cen_inflate "CEN-nest5 ★正しく閉じた入れ子 inert (<template><script></script>...</template>) は §10b census を inflate しない (偽 FAIL 封鎖)" \
  '<template><script>z</script><code>z</code><a class="xref" href="#z">z</a><span>z</span>&lt;code &lt;span</template>'


# --- CEN-rawnest. ★RAWTEXT 系 inert の ★自己閉じ + inert 挟み + 末尾閉じ直し による ★有界な盲点 (folio-ahn3) ---
#   ★攻撃形: `<script/><template></script>PAYLOAD</template></script>`。 HTML5 では `<script/>` が raw text を
#   開き `<template>` は ★ただの文字列、 `</script>` が raw text を閉じるため ★PAYLOAD は live (実描画)。
#   是正前の census は `<template>` を ★実タグとして stack へ積んでいたため `</script>` が最内 inert に阻まれて
#   自分を閉じられず、 PAYLOAD が非計数になっていた。 しかも末尾 `</template></script>` で inert を ★閉じ直せる
#   ため ★他の census 値は無傷 = 全 census 0 へ落ちる fail-closed ではなく ★攻撃者専用の隠し場所 だった
#   (実測: 両 arm exit0 / FAIL 0 で素通り・base 8d4eeda からの pre-existing)。
#   ★是正 = handle_startendtag が RAWTEXT 系へ set_cdata_mode を与える (両 arm・census_dump / h_inline)。
#   ★本群は ★inflate (注入) 方向 で撃つ: 盲点へ live 資産を置けば census が ★動く こと。 「盲点だから
#   数えない」のが穴ゆえ、 剥奪 + 復元形では撃てない (盲点内の資産は復元にも使えない)。
#   ★1 tag の実弾は別 tag の穴を証明しない ゆえ ★CDATA 6 + RCDATA 2 の 8 タグ × ★element / text-inline /
#   escape literal の 3 軸 を per-shape で撃つ (両 arm)。 producer 側は SETCDATA 存在 pin が対で押さえる。

f19_mut_reason "CEN-rawnest-script-el ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script><div id=\"req-ver-001\"></div></template></script>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-script-tx ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script><code>z</code></template></script>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-script-esc ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script>&lt;span </template></script>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-style-el ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style><div id=\"req-ver-001\"></div></template></style>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-style-tx ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style><code>z</code></template></style>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-style-esc ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style>&lt;span </template></style>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-xmp-el ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp><div id=\"req-ver-001\"></div></template></xmp>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-xmp-tx ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp><code>z</code></template></xmp>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-xmp-esc ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp>&lt;span </template></xmp>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-iframe-el ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe><div id=\"req-ver-001\"></div></template></iframe>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-iframe-tx ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe><code>z</code></template></iframe>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-iframe-esc ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe>&lt;span </template></iframe>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-noembed-el ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed><div id=\"req-ver-001\"></div></template></noembed>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-noembed-tx ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed><code>z</code></template></noembed>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-noembed-esc ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed>&lt;span </template></noembed>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-noframes-el ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes><div id=\"req-ver-001\"></div></template></noframes>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-noframes-tx ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes><code>z</code></template></noframes>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-noframes-esc ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes>&lt;span </template></noframes>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-textarea-el ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea><div id=\"req-ver-001\"></div></template></textarea>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-textarea-tx ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea><code>z</code></template></textarea>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-textarea-esc ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea>&lt;span </template></textarea>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-rawnest-title-el ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title><div id=\"req-ver-001\"></div></template></title>}" "census navigable id: 重複 0"
f19_mut_reason "CEN-rawnest-title-tx ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title><code>z</code></template></title>}" "census generic: 人間層 <code> rest"
f19_mut_reason "CEN-rawnest-title-esc ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title>&lt;span </template></title>}" "census double-escape: &lt;span"

# === COLLAPSE. ★extractor-collapse 敵対 test (folio-7n17 deliverable 4) ===
# extract-verification-spec.sh の人間層 rich() を関数レベルで plain() 相当へ collapse し、 ★extractor の
# pre-flip source (spec-origin/verification.origin.html = 現行 canonical は flip 済で ears-requirement-row 形ゆえ
# extractor が理解できない・snapshot が extractor の設計対象 form) から re-extract → collapsed contract →
# in-place generator で assemble → collapsed 生成物。 ★狙い: ① contract==生成物 の §4/§5 + round-trip vacuous
# PASS (両側同時退行で緑) を実演し、 ② frozen census (§10b) が collapsed 生成物を独立 anchor として FAIL させる
# ことを red→green 固定。 ★rich 減少 assert だけの相対 parity (6==6 恒真) は禁止 — frozen literal で撃つ。
# ★full-repo staging で genuine 再生成 (cp -r は親 dir 資産欠落で不可・real generator を in-place 実行)。
COLLAPSE_EXTRACT="$SCRIPT_DIR/../../scripts/extract-verification-spec.sh"
COLLAPSE_SNAP="$SCRIPT_DIR/spec-origin/verification.origin.html"
if [[ ! -f "$COLLAPSE_EXTRACT" || ! -f "$COLLAPSE_SNAP" ]]; then
  ng "COLLAPSE ★前提喪失 (extractor / snapshot 不在): $COLLAPSE_EXTRACT / $COLLAPSE_SNAP"
else
  # rich() の lexical $s copy にタグ除去を注入 (関数レベル collapse・read-only $1 arg を壊さない)。
  perl -0777 -pe 's{(sub rich \{\n  my \(\$s\) = \@_; \$s //= "";)}{$1\n  \$s =~ s/<[^>]*>//g;}' \
    "$COLLAPSE_EXTRACT" > "$TMP/extract-collapsed.sh"
  if diff -q "$COLLAPSE_EXTRACT" "$TMP/extract-collapsed.sh" >/dev/null; then
    ng "COLLAPSE-0 ★rich()→plain() collapse mutate が空撃ち (rich sub の記法変化の疑い)"
  else
    ok "COLLAPSE-0 ★rich()→plain() collapse mutate が適用された (関数レベル)"
    bash "$TMP/extract-collapsed.sh" "$COLLAPSE_SNAP" > "$TMP/collapsed.yaml" 2>/dev/null
    # ★epoch 固定 assembler: collapsed.yaml は凍結 snapshot (55-id epoch) の re-extract ゆえ rich/machine field
    #   件数は凍結 epoch 実測 (rich 337 = 7+18+7+24+220+1+30+30 / machine 34 = 3+0+20+11) を持つ。 live assembler の
    #   RICH_FIELD_MIN / *_TYPE_MINS は現行契約の成長へ追随更新される (assembler 内規) ため、 現行値のまま snapshot
    #   epoch の contract を assemble すると被覆量 assert (b1)/(b2) が構造発火する (契約成長の初回 = folio-7n17 Leg B
    #   の REQ-VER-031 追加で顕在化)。 snapshot は非追随 (ADR-0053 §2.5・案 B 却下) ゆえ epoch 定数は★永久安定 —
    #   test-local copy の MIN 群だけを epoch 値へ pin する (本番 assembler の fail-closed は★不変・本 test の検査
    #   対象は census (下流) であって MIN ではない・GUARDLESS と同じ SCRIPT_DIR 配置 + EXIT trap 掃除)。
    sed -E \
      -e 's/^RICH_FIELD_MIN=[0-9]+$/RICH_FIELD_MIN=337/' \
      -e 's/^MACHINE_FIELD_MIN=[0-9]+$/MACHINE_FIELD_MIN=34/' \
      -e 's/^(  .)[0-9]+(:::sect-essence)/\17\2/' \
      -e 's/^(  .)[0-9]+(:::subhead-essence)/\118\2/' \
      -e 's/^(  .)[0-9]+(:::table-caption)/\17\2/' \
      -e 's/^(  .)[0-9]+(:::table-headers)/\124\2/' \
      -e 's/^(  .)[0-9]+(:::table-rows)/\1220\2/' \
      -e 's/^(  .)[0-9]+(:::mermaid-caption)/\11\2/' \
      -e 's/^(  .)[0-9]+(:::req-essence)/\130\2/' \
      -e 's/^(  .)[0-9]+(:::req-statement)/\130\2/' \
      -e 's/^(  .)[0-9]+(:::preamble-html)/\13\2/' \
      -e 's/^(  .)[0-9]+(:::preamble-items)/\10\2/' \
      -e 's/^(  .)[0-9]+(:::block-html)/\120\2/' \
      -e 's/^(  .)[0-9]+(:::block-items)/\111\2/' \
      "$ASM" > "$EPOCH_ASM"
    if ! grep -q '^RICH_FIELD_MIN=337$' "$EPOCH_ASM" || ! grep -q "18:::subhead-essence" "$EPOCH_ASM" \
       || ! grep -q "220:::table-rows" "$EPOCH_ASM"; then
      ng "COLLAPSE ★epoch assembler の MIN pin が不成立 (sed 空撃ち = 定数記法の変化疑い)"
    elif bash "$EPOCH_ASM" "$TMP/collapsed.yaml" "$TMP/collapsed.html" >/dev/null 2>&1; then
      cx_g="$(perl -CSD -0777 -ne 'my $n=0; while (/<a\b([^>]*)>/g){ my $a=$1; $n++ if $a =~ /class="(?:[^"]*\s)?xref/; } print $n;' "$TMP/collapsed.html")"
      # collapsed verify を回し ① §4/§5 vacuous PASS と ② frozen census FAIL を同一 run で確認する。
      #   ★heavy suite 下の subprocess 一過性ヒッカプ (yq|jq pipe 等) に対し fail-closed かつ resilient にするため、
      #     出力が incomplete (RESULT 行 or census a.xref 行を欠く) なら最大 2 回まで retry する (genuine な §4/§11 破断は
      #     両試行で再現し retry では緑化しない = 真の regression は依然 fail-closed)。
      col_out=""; col_rc=1
      for _attempt in 1 2; do
        col_out="$(bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; col_rc=$?
        if printf '%s\n' "$col_out" | grep -qF 'census rich: a.xref' && printf '%s\n' "$col_out" | grep -qF '要件タプル'; then break; fi
      done
      # ① contract==生成物 vacuous PASS: 要件タプル (§4) と round-trip (§11) が [OK] (両側同時退行で緑)。
      #   line-based robust grep (grep -E の [^\n] 曖昧性を回避): 該当行を抽出し [OK] を含むか判定。
      tup_line="$(printf '%s\n' "$col_out" | grep -F '要件タプル' | head -1)"
      rt_line="$(printf '%s\n' "$col_out" | grep -F 'round-trip' | grep -F '機械層' | head -1)"
      if printf '%s' "$tup_line" | grep -qF '[OK]' && printf '%s' "$rt_line" | grep -qF '[OK]'; then
        ok "COLLAPSE-1 ★§4 要件タプル + §11 round-trip の vacuous PASS を実演 (contract==生成物・collapsed a.xref=$cx_g < frozen 31)"
      else
        ng "COLLAPSE-1 ★vacuous PASS の実演に失敗 (§4/§11 が [OK] でない = collapse が contract-vs-生成物 を割った)"
        printf '%s\n' "$col_out" > "$SCRIPT_DIR/../../../.folio-7n17-tmp/collapse-col-out.log" 2>/dev/null || true
        echo "      [debug] §4: ${tup_line:-<none>}" >&2
        echo "      [debug] §11: ${rt_line:-<none>}" >&2
      fi
      # ② frozen census が collapsed 生成物を FAIL させる (独立 anchor・rich 減少 6<31)。
      if [[ $col_rc -ne 0 ]] && printf '%s\n' "$col_out" | grep -qE '\[FAIL\][^\n]*census rich: a.xref'; then
        ok "COLLAPSE-2 ★frozen census が collapse を FAIL (§4/§11 vacuous PASS を独立 anchor が捕捉・rich 減少 6<31)"
      else
        ng "COLLAPSE-2 ★frozen census が collapse を捕捉できず (rc=$col_rc・vacuous PASS 未封鎖 = 政策A 失効)"
      fi
      # ③ 本番自己比較を模す: SPEC_ORIGIN_HTML=collapsed でも census が生きる (ORIG==生成物 でも frozen で FAIL)。
      sc_out="$(SPEC_ORIGIN_HTML="$TMP/collapsed.html" bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; sc_rc=$?
      if [[ $sc_rc -ne 0 ]] && printf '%s\n' "$sc_out" | grep -qE '\[FAIL\][^\n]*census rich: a.xref'; then
        ok "COLLAPSE-3 ★SPEC_ORIGIN_HTML=collapsed の自己比較でも frozen census FAIL (ORIG 非消費の実証)"
      else
        ng "COLLAPSE-3 ★自己比較で census FAIL せず (rc=$sc_rc = census が ORIG を消費している回帰)"
      fi
    else
      ng "COLLAPSE ★collapsed contract の assemble に失敗 (genuine 再生成不能)"
    fi
  fi
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
expect_vfilled_fail "M1 ★機械層 prose 改竄を原本↔生成物 round-trip が捕捉" "$TMP/m1.html" "機械層 不一致"

# M2. ★機械層 prose 脱落 (silent drop) → 件数 + round-trip FAIL。
cp "$TMP/base-filled.html" "$TMP/m2.html"
perl -0777 -i -pe 's#<p data-component="spec-machine-prose" data-audience="machine">.*?</p>\n##s' "$TMP/m2.html"
expect_vfilled_fail "M2 ★機械層 prose 脱落を件数+round-trip が捕捉" "$TMP/m2.html" "spec-machine-prose"

# M3. ★機械層 prose 捏造 (原本に無い block を add) → 件数 + round-trip FAIL (生成物のみ)。
cp "$TMP/base-filled.html" "$TMP/m3.html"
perl -0777 -i -pe 's#(<div class="machine-body">\n)#${1}<p data-component="spec-machine-prose" data-audience="machine">捏造された機械層</p>\n#' "$TMP/m3.html"
expect_vfilled_fail "M3 ★機械層 prose 捏造を round-trip (生成物のみ) が捕捉" "$TMP/m3.html" "機械層 不一致"

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
expect_vfilled_fail "M10 ★機械層の二重 escape を round-trip が捕捉" "$TMP/m10.html" "機械層 不一致"

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
expect_vfilled_fail "M11 ★機械層 block 順序入替を順序付き round-trip が捕捉" "$TMP/m11.html" "機械層 不一致"

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
expect_vfilled_fail "M12 ★cross-section 誤帰属を順序付き round-trip が捕捉" "$TMP/m12.html" "機械層 不一致"

# M13. ★機械層 note (aside) テキスト改竄 → 原本↔生成物 round-trip FAIL (件数不変・最複雑 modality の content fidelity pin)。
#   note は nested <p>・<span class=term>・<a> を含む最も構造複雑な block 種ゆえ専用の改竄敵対が要る (prose M1 と対称)。
cp "$TMP/base-filled.html" "$TMP/m13.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine">)#${1}ZZNOTETAMPERZZ #' "$TMP/m13.html"
expect_vfilled_fail "M13 ★機械層 note 改竄を原本↔生成物 round-trip が捕捉" "$TMP/m13.html" "機械層 不一致"

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

# ============================================================================
# === ADR-0054 (flip 済 spec 提示層の標準形・folio-9m1h Cell V) の per-shape mutation-kill (PR 群) ===
#   ★per-shape で撃つ理由: 章帯番号 / 静的 band heading / 章 wrapper / chip 一行タイトル / role 平易語 /
#     優先度バッジ / 平易行 / fold ラベル / 空 subsection 要約 は ★DOM 形状が別クラス ゆえ、
#     1 instance の実弾は構造差のある instance の穴を証明しない (jyfh/r8k の per-shape 規律)。
#   ★★new field は ★all-or-none optional (extractor 再抽出物でも assemble できる互換性のため) ゆえ、
#     「契約から一括削除 → 再生成」で逐値突合が ★0/0 恒真 PASS する。 その ★唯一の FAIL 源 = 契約非依存
#     census を ★isolate する MK を各軸に ★対で 置く (逐値 MK と census MK の 2 本立て)。
#   ★全 MK に fired-guard を付す (shape drift による空撃ちを検出)。
#   ★★宣言能力 == 実能力 の開示 (1): assemble-verification.sh の band_num() が持つ「core band() の連番 span が
#     見当たらなければ abort」の fail-loud は、 共有 lib/common.sh の mutation を要するため ★本 suite の
#     per-shape MK では撃っていない (verify 側 PR1 = .num 列突合が同クラスの結果を捕捉する)。
#   ★★宣言能力 == 実能力 の開示 (2): verification は ★ref-primary (References の一次参照を人間層へ可視化) を
#     ★実装していない (relations 固有 arm・V確定5b で 0 件許容)。 ゆえに Cell R の一次参照 MK 群に相当する
#     case は ★存在しない (空撃ち MK も 0/0 恒真 pin も作らない)。
# ============================================================================
# PR1. ★章帯番号を連番 (01) へ戻す退行 → band .num 列 FAIL (§番号一致 = ADR-0054 §2.2)。
cp "$TMP/base-filled.html" "$TMP/pr1.html"
perl -0777 -i -pe 'our $n; $n += s#<span class="num">0</span>#<span class="num">01</span>#; END { exit($n?0:9) }' "$TMP/pr1.html" \
  || ng "PR1 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR1 ★章帯番号の連番戻し (§番号 → 01) を band .num 列が捕捉" "$TMP/pr1.html" "band .num 列"
# PR2. ★静的 band heading を旧 over-promise 文言へ戻す → heading 列 FAIL。
#   ★旧 heading は §番号を持たない形で、 §番号一致と heading 逐値の両方を破る。
cp "$TMP/base-filled.html" "$TMP/pr2.html"
perl -0777 -i -pe 'our $n; $n += s#<h2>§7\. 上位文書への前方照会 — 原則と決定記録へつながる</h2>#<h2>verification は照会の終端ではない — 原則 (constitution) や決定記録 (ADR) へ前方照会する</h2>#; END { exit($n?0:9) }' "$TMP/pr2.html" \
  || ng "PR2 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR2 ★静的 band heading の旧 over-promise 復活 (§7) を heading 列が捕捉" "$TMP/pr2.html" "section 可視 heading 列"
# PR2b. ★NSEC 超位置への h2 無制限注入 (旧 head -n NSEC 切詰の射程外だった盲点) → h2 総数 pin が捕捉。
cp "$TMP/base-filled.html" "$TMP/pr2b.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<h2>§NEW 緊急告知 本仕様は無効 (捏造)</h2></body>#; END { exit($n?0:9) }' "$TMP/pr2b.html" \
  || ng "PR2b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR2b ★NSEC 超位置への h2 注入を h2 総数 pin が捕捉" "$TMP/pr2b.html" "h2 総数"
# PR3. ★前方照会章の wrapper section 剥奪 (章化の喪失 = 目次から辿れない旧状態への退行) → section anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/pr3.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n##; END { exit($n?0:9) }' "$TMP/pr3.html" \
  || ng "PR3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3 ★前方照会章の wrapper 剥奪 (章化喪失) を section anchor 列が捕捉" "$TMP/pr3.html" "section anchor 列"
# PR3b. ★contract 由来 section への class 注入 → section anchor 列 FAIL (厳格 selector の teeth を pin)。
#   PR4 は ★提示層 wrapper 限定 の陽性 assert を撃つが、 contract 由来 7 section は wrapper assert の射程外で
#   section anchor 列だけが守る。 selector を範型の `[^>]*` 緩和形へ写すと ここが素通る (補償 arm 不在) ため
#   per-shape で別途 pin する (wrapper shape != contract section shape)。
cp "$TMP/base-filled.html" "$TMP/pr3b.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-scope">#<section id="s2-scope" class="normative">#; END { exit($n?0:9) }' "$TMP/pr3b.html" \
  || ng "PR3b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3b ★contract section への class 注入を section anchor 列が捕捉 (緩和 selector 封鎖)" "$TMP/pr3b.html" "section anchor 列"
# PR3c. ★contract 由来 section への data-audience="machine" 注入 = ★1 章まるごと人間層から消す content-suppression。
#   class 注入 (PR3b) と別 shape で撃つ: 属性名が異なると緩和 selector の穴も別経路で開くため (per-shape 規律)。
#   census (rf-gloss/rq-prio/rq-plain/sub-se)・h2 総数 pin・band .num 列・要件タプル・id census はいずれも発火しない
#   (s2-scope は <code> を持たないので generic census の巻き添えも無い) = section anchor 列が唯一の防壁。
cp "$TMP/base-filled.html" "$TMP/pr3c.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-scope">#<section id="s2-scope" data-audience="machine" hidden>#; END { exit($n?0:9) }' "$TMP/pr3c.html" \
  || ng "PR3c mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3c ★contract section の人間層抑止 (data-audience 注入) を section anchor 列が捕捉" "$TMP/pr3c.html" "section anchor 列"
# PR3d. ★hollow wrapper — wrapper 開きタグを ★即閉じ し、 章帯 / chapbody / ref-grid を wrapper の ★外 へ押し出す。
#   ★タグ均衡は保たれる (対応閉じタグも同時に除去する) ため、 tag balance 系・件数 census・section anchor 列・
#   wrapper 陽性 assert (実在 + class 無し) は ★全て素通る。 「id を持つ section が在る」ことだけを見る assert 群は
#   章化の ★実質 (中身がその章に属すること) を守れない、 というのが本 shape の主張 (cell-quality round-2 blocking B3)。
#   ★fired-guard は ★2 置換 とも要求する (対応閉じタグ除去が空振りすると単なるタグ不均衡 HTML になり、 別 arm の
#   巻き添え FAIL で ★理由の異なる false-pass を作るため)。 捕捉は containment の ★開口隣接 pin。
cp "$TMP/base-filled.html" "$TMP/pr3d.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n#<section id="forward-refs"></section>\n#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3d.html" \
  || ng "PR3d mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3d ★hollow wrapper (章帯ごと外へ押し出し) を containment 開口隣接 pin が捕捉" "$TMP/pr3d.html" "'forward-refs' の開口直後に"
# PR3e. ★chapbody だけの押し出し — 章帯は wrapper 内に ★残したまま 本文 (chapbody / ref-grid / chip 30) を外へ出す。
#   PR3d と ★別 shape: 開口隣接 pin は band が隣接したままなので ★PASS し、 region 占有 pin ★だけ が発火する
#   (= 2 段の pin が互いの巻き添えでなく ★独立に teeth を持つ ことの per-shape 実証。 実弾で確認済)。
cp "$TMP/base-filled.html" "$TMP/pr3e.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}</section>\n<div class="chapbody">#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3e.html" \
  || ng "PR3e mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3e ★章本文 (chapbody) だけの押し出しを containment region 占有 pin が捕捉 (band 隣接は保持)" "$TMP/pr3e.html" "章 'forward-refs' region 内の chapbody == 1"
# PR3f. ★用語集 wrapper の hollow 化 — forward-refs (PR3d) と ★別 shape で撃つ: 包む payload が ref-grid でなく
#   glossary-term-table / .grow 27 行であり、 region 占有 pin の対象 marker が構造として別クラス。
#   1 wrapper での実弾は他方の wrapper の穴を証明しない (per-shape mutation-kill 規律)。
cp "$TMP/base-filled.html" "$TMP/pr3f.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="glossary-terms">\n#<section id="glossary-terms"></section>\n#; $n += s#</section>\n</div>\n#</div>\n#; END { exit($n==2?0:9) }' "$TMP/pr3f.html" \
  || ng "PR3f mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3f ★用語集 wrapper の hollow 化を containment が捕捉 (別 payload shape)" "$TMP/pr3f.html" "'glossary-terms' の開口直後に"
# ============================================================================
# ★PR3g〜PR3s — containment の ★arm ごと per-shape mutation-kill (cell-quality round-3)。
#   PR3d/e/f だけでは 開口隣接 pin と region chapbody pin しか ★理由文字列で anchor されず、 他 arm は
#   ★削除しても suite が緑のまま だった (= 実効被覆の欠落)。 以下は containment の ★各 arm に対し
#   「その arm が [FAIL] 理由を担う」実弾を 1 本以上 与える。 ★全て fired-guard 付き (空撃ち禁止)。
#   ★expect_vfilled_fail の理由照合は fixed-string の [FAIL] 行 anchor ゆえ、 巻き添え FAIL があっても
#   「その arm が消えたら赤くなる」性質 (= mutation-kill) は保たれる。
# ============================================================================
# PR3g. ★band tint の逐値付け替え — 開口隣接 pin の ★識別成分 (どの章の帯か) だけ を崩す。 band は隣接したまま・
#   件数も不変ゆえ、 tint 逐値を pin していなければ ★全 gate 緑 (PRESENTATION_WRAPPER_BAND_TINTS の存在理由の実証)。
cp "$TMP/base-filled.html" "$TMP/pr3g.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-)violet(">)#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/pr3g.html" \
  || ng "PR3g mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3g ★別章 band への付け替え (tint 逐値) を開口隣接 pin が単独で捕捉" "$TMP/pr3g.html" "'forward-refs' の開口直後に"
# PR3h. ★開口への異物挿入 — band は残り tint も §番号も正しいが、 wrapper 開口と band の ★間 に別要素が入る。
#   PR3g (属性の同一性) と別成分 = ★位置 (直後性) を撃つ。
cp "$TMP/base-filled.html" "$TMP/pr3h.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n)#${1}<p class="decoy">x</p>\n#; END { exit($n==1?0:9) }' "$TMP/pr3h.html" \
  || ng "PR3h mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3h ★開口と章帯の間への異物挿入を開口隣接 pin が単独で捕捉 (位置成分)" "$TMP/pr3h.html" "'forward-refs' の開口直後に"
# PR3s. ★band §番号の逐値書換 — 開口隣接 pin の ★第 3 成分 (どの節の帯か)。 tint (PR3g) / 位置 (PR3h) と別成分ゆえ
#   別実弾で撃つ (band .num 列 arm も巻き添えで発火するが、 理由 anchor は containment 側に取る)。
cp "$TMP/base-filled.html" "$TMP/pr3s.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-violet"><span class="num">)7#${1}9#; END { exit($n==1?0:9) }' "$TMP/pr3s.html" \
  || ng "PR3s mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3s ★band §番号の逐値書換を開口隣接 pin が捕捉 (節同一性成分)" "$TMP/pr3s.html" "'forward-refs' の開口直後に"
# PR3i. ★over-containment — forward-refs の閉じタグを外し glossary-terms を ★入れ子 にする (assembler の
#   printf </section> 1 行脱落と同 shape)。 押し出しの ★逆向き ゆえ region 占有の ★上限側 (== 1) だけ が発火する。
cp "$TMP/base-filled.html" "$TMP/pr3i.html"
perl -0777 -i -pe 'our $n; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; $n += s#</section>\n</div>\n<footer#</section>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/pr3i.html" \
  || ng "PR3i mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3i ★wrapper の入れ子化 (over-containment) を region 占有の上限側が捕捉" "$TMP/pr3i.html" "章 'forward-refs' region 内の章帯 == 1"
# PR3j. ★契約章の hollow 化 — 同一 DOM shape (band 1 + chapbody 1) を持つのは提示層 wrapper 2 本だけではない。
#   containment を 2 id の手書き列挙に留めると残り 7 章が無防備 (partial-enumeration trap) ゆえ、 契約章側にも実弾を置く。
cp "$TMP/base-filled.html" "$TMP/pr3j.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-scope">\n#<section id="s2-scope"></section>\n#; $n += s#</section>\n<section id="s3-ears">#<section id="s3-ears">#; END { exit($n==2?0:9) }' "$TMP/pr3j.html" \
  || ng "PR3j mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3j ★契約章 (s2-scope) の hollow 化を containment が捕捉 (2 id 列挙では届かない残り 7 章)" "$TMP/pr3j.html" "'s2-scope' の開口直後に"
# PR3k. ★1 段内側の hollow 化 (chapbody) — chapbody を空で閉じ payload を chapbody の ★sibling (章の中・器の外) へ出す。
#   B3 の defect 原理は ★階層ごとに 再演するので、 wrapper 階層の pin だけでは素通る shape。
cp "$TMP/base-filled.html" "$TMP/pr3k.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="chapbody">\n<div class="ref-grid">#<div class="chapbody"></div>\n<div class="ref-grid">#; $n += s#</div>\n</div>\n</section>\n<section id="glossary-terms">#</div>\n</section>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3k.html" \
  || ng "PR3k mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3k ★chapbody 空化 + payload を器の外へ (1 段内側の hollow 化) を containment が捕捉" "$TMP/pr3k.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# PR3l. ★chapbody 開口への異物挿入 — 1 段内側の ★開口隣接 pin (位置成分) を単独で撃つ。
cp "$TMP/base-filled.html" "$TMP/pr3l.html"
perl -0777 -i -pe 'our $n; $n += s#(<div class="chapbody">\n)(<div class="ref-grid">)#${1}<p class="decoy">x</p>\n${2}#; END { exit($n==1?0:9) }' "$TMP/pr3l.html" \
  || ng "PR3l mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3l ★chapbody 開口と payload container の間への異物挿入を 1 段内側の開口隣接 pin が捕捉" "$TMP/pr3l.html" "の chapbody 開口直後に ref-grid が隣接"
# PR3m. ★hollow container (ref-grid) — container を即閉じし chip 30 を container の ★外 (chapbody 直下) へ出す。
#   「container の開きタグが在る」は「chip がその中に在る」を意味しない (B3 の原理の 2 段内側)。
cp "$TMP/base-filled.html" "$TMP/pr3m.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"></div>\n#; $n += s#</div>\n</div>\n</section>\n<section id="glossary-terms">#</div>\n</section>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3m.html" \
  || ng "PR3m mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3m ★hollow ref-grid (chip 30 を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/pr3m.html" "前方照会 chip の ★全数"
# PR3n. ★hollow container (glossary-term-table) — PR3m と ★別構造クラス (payload が chip でなく .grow 27 行)。
#   1 container での実弾は他方の container の穴を証明しない (per-shape mutation-kill 規律)。
cp "$TMP/base-filled.html" "$TMP/pr3n.html"
perl -0777 -i -pe 'our $n; $n += s#<div data-component="glossary-term-table">\n#<div data-component="glossary-term-table"></div>\n#; $n += s#</div>\n</div>\n</section>\n</div>\n<footer#</div>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/pr3n.html" \
  || ng "PR3n mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3n ★hollow glossary-term-table (.grow 27 を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/pr3n.html" "用語集 行 (.grow) の ★全数"
# ---- PR3o/PR3p/PR3q: ★parser-differential (r8k / folio-wq4 再発クラス) の 3 vector ----
#   いずれも 「本物の </section> を band 直後へ入れて章本文を章の ★外 へ出し、 元の閉じタグを ★偽タグ で置換して
#   ★素朴な深さ計数 の帳尻だけ合わせる」 shape。 make_body はコメント / RAWTEXT の中身を verbatim 保持し、
#   属性値内の生 `>` も (raw `<` と違い) fail-closed しないため、 生テキストへの /<\/?section\b[^>]*>/ 走査は
#   region を ★over-slice して containment を丸ごと素通す。 ★fix 前の実測: 3 本とも rc=0 / 0 FAIL (0 件検出)。
#   ★独立 HTML parser (python html.parser) で 3 本とも ref-grid の section 祖先が ★空 = 章の外 を確認済。
#   ★3 vector を別実弾で撃つ: マスク対象が コメント / RAWTEXT / 属性値 の ★3 クラス あり、 1 本の実弾は他 2 つの穴を証明しない。
cp "$TMP/base-filled.html" "$TMP/pr3o.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<!--<section>-->\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3o.html" \
  || ng "PR3o mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3o ★コメント密輸による region over-slice (parser-differential) を containment が捕捉" "$TMP/pr3o.html" "章 'forward-refs' region 内の chapbody == 1"
cp "$TMP/base-filled.html" "$TMP/pr3p.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<script>var s = "<section>";</script>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<script>var e = "</section>";</script>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3p.html" \
  || ng "PR3p mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3p ★script (RAWTEXT) 密輸による region over-slice を containment が捕捉" "$TMP/pr3p.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# ★PR3q の ★閉じ側 だけ コメント vector を使うのは、 属性値内の生 `<` が make_body で ★既に fail-closed される ため
#   (raw-lt-in-tag)。 属性値 vector は ★開き側 にしか存在しない = 装わずに書く。
cp "$TMP/base-filled.html" "$TMP/pr3q.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<p class="decoy" title="x><section>y"></p>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/pr3q.html" \
  || ng "PR3q mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3q ★属性値内の生 '>' 密輸による region over-slice を containment が捕捉" "$TMP/pr3q.html" "前方照会 chip の ★全数"
# PR3r. ★非 genuine shape の fail-closed — div / section の ★自己閉じ構文。 HTML の非 foreign content では `/>` は
#   無視される (= 開きタグ) が、 svg / math の ★foreign content 内では自己閉じが効くため、 深さ計数と実 DOM の差を
#   作る入口になる。 rendering を完全にモデルする arms race へ戻らず、 ★genuine な assembler が emit しない shape を
#   ★拒否する (make_body と同じ規律)。 捕捉は containment tokenizer の構造診断 arm。
cp "$TMP/base-filled.html" "$TMP/pr3r.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"/>\n#; END { exit($n==1?0:9) }' "$TMP/pr3r.html" \
  || ng "PR3r mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3r ★div の自己閉じ構文 (foreign content 差の入口) を tokenizer が fail-closed" "$TMP/pr3r.html" "containment tokenizer の構造診断"
# ★parser-differential の ★残り 3 vector (PR3o/p/q が塞いだ コメント / script / 属性値 の ★外側 に在ったもの)。
#   いずれも ★fix 前は rc=0 / 0 FAIL で素通った実測 shape で、 実 HTML parser では章本文が ★章の外 に居る:
#   PR3t bogus comment (`<! … >`) — 実 parser は `<!--` でない markup declaration も comment として `>` まで捨てるが、
#        素朴実装は 1 文字進めるだけなので中の `<section>` が ★実タグとして深さに乗る。 genuine BODY にも
#        `<!DOCTYPE html>` が実在するため fix は「拒否」でなく ★実 parser と同じ読み飛ばし (拒否だと genuine が総崩れ)。
#   PR3u escapable RAWTEXT (`<textarea>`) — 中身はテキストゆえ `<section>` は要素にならない。 旧実装は script / style
#        しか知らず title / textarea 等が素通しだった。
#   PR3v ハイフン入り要素名 (`<section-x>`) — 実 DOM では section と ★別要素。 要素名を `[a-zA-Z0-9]*` で切ると
#        "section" と誤認して章の深さに数える。
#   ★3 本を別実弾で撃つ (マスク経路が別クラス = 1 本の実弾は他 2 つの穴を証明しない)。 reason anchor は ★章名込み
#   の label へ当てる (章非特定の語だと別章の巻き添え FAIL でも満たされ per-shape の主張が pin されない)。
cp "$TMP/base-filled.html" "$TMP/pr3t.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<! <section> >\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n#<! </section> >\n</div>\n#; END { exit($n==2?0:9) }' "$TMP/pr3t.html" \
  || ng "PR3t mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3t ★bogus comment (<! … >) 密輸による region 付け替えを containment が捕捉" "$TMP/pr3t.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/pr3u.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea><section></textarea>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n#<textarea></section></textarea>\n</div>\n#; END { exit($n==2?0:9) }' "$TMP/pr3u.html" \
  || ng "PR3u mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3u ★escapable RAWTEXT (textarea) 密輸による region 付け替えを containment が捕捉" "$TMP/pr3u.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/pr3v.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<section-x>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n#</section-x>\n</div>\n#; END { exit($n==2?0:9) }' "$TMP/pr3v.html" \
  || ng "PR3v mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3v ★ハイフン入り要素名 (<section-x>) 密輸による region 付け替えを containment が捕捉" "$TMP/pr3v.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# PR3w. ★契約章の band tint 付け替え — 契約章 7 本の tint 逐値 pin (源 = contract sections[].tint) を ★単独で 撃つ。
#   旧実装は「contract は section tint の key を持たない」という ★事実に反する 根拠で契約章を tint 不問にしており、
#   本 shape が rc=0 / 0 FAIL で素通った (実測で反証: tint は 7/7 実在し band の class="tint-<値>" と 1:1)。
#   §番号は変えないので §番号成分では落ちない = tint 成分 ★単独 の teeth を isolate する。
cp "$TMP/base-filled.html" "$TMP/pr3w.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-scope">\n<section data-component="chapter-deck-band" class="tint-)violet(")#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/pr3w.html" \
  || ng "PR3w mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3w ★契約章 (s2-scope) の band tint 付け替えを tint 逐値 pin が単独で捕捉" "$TMP/pr3w.html" "'s2-scope' の開口直後に"
# PR3x. ★器の重複 — 正規の ref-grid は ★中身ごと 正しい位置に残したまま、 文書の別位置に ★2 個目の ref-grid を
#   足す。 per-章 arm (chapbody 内に 1 個 / chip 全数が器の中) は ★全て PASS のままで、 2 個目の器は以後の改竄で
#   payload の ★逃げ場 として使える (漏出先の先置き)。 捕捉は ★文書総数 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/pr3x.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref-grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$TMP/pr3x.html" \
  || ng "PR3x mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3x ★payload container の重複 (漏出先の先置き) を文書総数 pin が単独で捕捉" "$TMP/pr3x.html" "ref-grid が ★文書全体で 1 個"
# ★comment 終端の HTML5 非同型 (admin ceiling round-2 A・実弾 verified)。 `-->` 一本終端の実装は、 実 parser が
#   ★早く 終端する形 (comment end bang / abrupt close) を知らないため、 攻撃者は「実 DOM では章の外に在る
#   閉じタグ」を tokenizer にだけ comment の中身として ★隠せる。 2 vector を別実弾で撃つ (終端規則が別分岐)。
cp "$TMP/base-filled.html" "$TMP/pr3y.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--x--!></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/pr3y.html" \
  || ng "PR3y mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3y ★comment end bang (--!>) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/pr3y.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/pr3z.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/pr3z.html" \
  || ng "PR3z mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3z ★abrupt-closing comment (<!-->) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/pr3z.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★RAWTEXT 終了タグの ★要素名境界 (同 C)。 `</name[^>]*>` は `</textareax>` にも一致して早期終了し、 以降の
#   擬似タグを実タグとして数える。 ★region を ★伸ばす 向き (開きタグ密輸) で撃つ = over-slice の実害形。
cp "$TMP/base-filled.html" "$TMP/pr4a.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea></textareax><section><textarea></textarea>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/pr4a.html" \
  || ng "PR4a mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4a ★RAWTEXT 終了タグの要素名境界 (</textareax>) を突く region 伸長を containment が捕捉" "$TMP/pr4a.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★foreign content (同 D)。 svg / math subtree 内の要素は HTML 名前空間ではないので章の深さに数えてはならない。
#   ★genuine 生成物に svg アイコンが多数実在する ため「現れないから拒否」では閉じられず subtree 追跡が要る。
cp "$TMP/base-filled.html" "$TMP/pr4b.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<svg><section></svg>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/pr4b.html" \
  || ng "PR4b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4b ★foreign content (svg subtree) 内の擬似タグによる region 伸長を containment が捕捉" "$TMP/pr4b.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★契約章の 1 段内側 (同 B)。 契約章 7 本は chapbody を空にして章本文を sibling へ押し出す改竄が 0 FAIL で
#   素通っていた (wrapper 2 章にしか (iii) が無かった)。 ★wrapper 側 (PR3k) と ★別実弾 で撃つ = 器の種類が
#   別クラス (章要旨 callout vs ref-grid) であり、 1 本の実弾は他方の穴を証明しない。
cp "$TMP/base-filled.html" "$TMP/pr4c.html"
#   ★タグ均衡を保つため 2 置換 (開口直後で閉じる + 元の chapbody 閉じを除去) を fired-guard で ★両方要求する。
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-scope">\n<section data-component="chapter-deck-band"[^\n]*</section>\n<div class="chapbody">)\n(<div data-component="section-essence-callout">)#${1}</div>\n${2}#; $n += s#</div>\n</section>\n<section id="s3-ears">#</section>\n<section id="s3-ears">#; END { exit($n==2?0:9) }' "$TMP/pr4c.html" \
  || ng "PR4c mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4c ★契約章 (s2-scope) の chapbody 空化 + 章本文 sibling 押し出しを 1 段内側 pin が捕捉" "$TMP/pr4c.html" "章要旨 callout が章 's2-scope' の chapbody 内に 1 個"
# PR4d. ★章本文の relocation ★クラス — PR4c (chapbody 完全空化) は ★1 instance にすぎない。 章要旨 callout は
#   chapbody 内に ★残したまま、 それ以降の章本文 (subhead / 地の文 / details / table) だけを chapbody の外へ
#   押し出す shape は、 callout 由来の 1 段内側 pin (cbadj / cont / docct) を ★全て PASS させたまま素通った
#   (実弾 verified: rc=0 / 0 FAIL)。 捕捉は「章の直下は 章帯 + chapbody の 2 子だけ」の構造 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/pr4d.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-scope">.*?<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)#${1}</div>\n#s; $n += s#</div>\n</section>\n<section id="s3-ears">#</section>\n<section id="s3-ears">#; END { exit($n==2?0:9) }' "$TMP/pr4d.html" \
  || ng "PR4d mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4d ★章要旨を残した章本文の relocation (block 粒度) を章直下 2 子の構造 pin が捕捉" "$TMP/pr4d.html" "章 's2-scope' の直下は 章帯 + chapbody の 2 子だけ"
# PR4e. ★comment 終端分岐 (2) `<!--->` の ★単独 teeth。 PR3y (`--!>`) / PR3z (`<!-->`) は別分岐を撃つため、
#   この分岐を削っても 2 本は緑のまま = 弱化が silent になる (admin gate round-3 R3-4)。
cp "$TMP/base-filled.html" "$TMP/pr4e.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!---></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/pr4e.html" \
  || ng "PR4e mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4e ★<!---> (comment 終端分岐 2) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/pr4e.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# PR4f. ★relocation クラスの ★もう一方の向き — 章本文の押し出し先を ★章直下の sibling でなく ★章帯 (band) の
#   ★中 にする。 章直下は band + chapbody のままなので kids pin (PR4d) は ★2 を保ったまま PASS し、 1 段内側
#   pin も callout が chapbody 内に残るため全て PASS する (実弾 verified: rc=0 / 0 FAIL で probe 実測値が
#   clean と区別不能だった)。 捕捉は band の直下 4 子固定 (共有 CORE lib/common.sh band() = num/kicker/h2/lead) ★単独。
cp "$TMP/base-filled.html" "$TMP/pr4f.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-scope">\n<section data-component="chapter-deck-band"[^\n]*?)(</section>\n)(<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)(.*?)(</div>\n</section>\n<section id="s3-ears">)#${1}${4}${2}${3}${5}#s; END { exit($n==1?0:9) }' "$TMP/pr4f.html" \
  || ng "PR4f mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4f ★章本文の band subtree への退避 (kids を 2 に保つ向き) を band 4 子固定が捕捉" "$TMP/pr4f.html" "章 's2-scope' の章帯の直下は num/kicker/h2/lead の 4 子だけ"
# PR4g / PR4h. ★document 順を ★保つ relocation 2 形 — 章直下 (kids) / band 直下 (bkids) を固定しても、
#   ★他の probe 値を一切動かさずに 素通る (実弾 verified: 2 形とも rc=0 / 0 FAIL・pre-existing で本 cell が
#   作った穴ではないが、 「両方向で閉じる」の宣言がこれを閉じたと読めるため封鎖する)。
#   PR4g (β) = 章本文を ★別章の chapbody へ移送 (donor 章が空章化し中身が受け側の下に付く)。
#   PR4h (γ) = 章本文を ★同章の machine-fold (details) の中へ退避。
#   捕捉は chapbody 直下の ★契約由来 完全子数 ★単独 (β は donor 減少 + 受け側増加・γ は吸い込み分の減少)。
cp "$TMP/base-filled.html" "$TMP/pr4g.html"
perl -0777 -i -pe 'our $n;
if (s#(<section id="s2-scope">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)((?:.(?!</div>\n</section>\n<section id="s3-ears">))*.)(\n</div>\n</section>\n<section id="s3-ears">)#${1}${3}#s) {
  our $moved = $2; $n++;
  $n++ if s#(<section id="s3-ears">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)#${1}$moved\n#s;
}
END { exit($n==2?0:9) }' "$TMP/pr4g.html" \
  || ng "PR4g mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4g ★章本文の別章 chapbody への移送 (document 順保存) を契約由来 完全子数が捕捉" "$TMP/pr4g.html" "章 's2-scope' の chapbody 直下は 契約由来の完全子数 4"
cp "$TMP/base-filled.html" "$TMP/pr4h.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-scope">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)((?:<div data-component="spec-subhead">[^\n]*\n)+)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/pr4h.html" \
  || ng "PR4h mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4h ★章本文の machine-fold 内への退避 (document 順保存) を契約由来 完全子数が捕捉" "$TMP/pr4h.html" "章 's2-scope' の chapbody 直下は 契約由来の完全子数 4"
# PR4. ★wrapper への class 侵食 → wrapper 陽性 assert が捕捉 (census 汚染の封鎖)。
cp "$TMP/base-filled.html" "$TMP/pr4.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">#<section id="forward-refs" class="normative">#; END { exit($n?0:9) }' "$TMP/pr4.html" \
  || ng "PR4 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4 ★提示層 wrapper への class 侵食を陽性 assert が捕捉 (census 汚染の封鎖)" "$TMP/pr4.html" "class 無しで実在"
# PR5. ★census id allowlist の default-block 維持 (admin 裁定 C2): wrapper 2 literal ★以外 の新 id は従来どおり FAIL する。
cp "$TMP/base-filled.html" "$TMP/pr5.html"
perl -0777 -i -pe 'our $n; $n += s#</h1>#</h1><span id="zz-new-anchor"></span>#; END { exit($n?0:9) }' "$TMP/pr5.html" \
  || ng "PR5 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR5 ★wrapper 以外の新 id は id census が従来どおり FAIL (肯定形 allowlist の default-block)" "$TMP/pr5.html" "census navigable id"
# PR5b. ★allowlist 空振り封鎖: 除外対象 wrapper id が生成物から消えたら陽性 assert が独立に FAIL する
#   (章化が落ちても除外だけ残る = allowlist の形骸化を封鎖)。 ★id 属性のみ剥がし section 要素は残す
#   (PR3 の「wrapper ごと剥奪」とは別 shape = 除外 allowlist 単独の teeth を isolate する)。
cp "$TMP/base-filled.html" "$TMP/pr5b.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="glossary-terms">#<section>#; END { exit($n?0:9) }' "$TMP/pr5b.html" \
  || ng "PR5b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR5b ★除外対象 wrapper id の消失を census 空振り封鎖 assert が捕捉" "$TMP/pr5b.html" "allowlist 空振り封鎖"
# PR6. ★chip 一行タイトル (rf-gloss) の値改竄 → chip タプル FAIL (contract title の逐語 echo が破れる)。
cp "$TMP/base-filled.html" "$TMP/pr6.html"
perl -0777 -i -pe 'our $n; $n += s#(<span class="rf-gloss">)隔離環境 \(sandbox\) で実機検証する枠組みの新設#${1}捏造された一行タイトル#; END { exit($n?0:9) }' "$TMP/pr6.html" \
  || ng "PR6 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR6 ★chip 一行タイトル (rf-gloss) 改竄を chip タプルが捕捉" "$TMP/pr6.html" "references: (token,doc,role,title)"
# PR7. ★契約 references[].title 一括削除 → 再生成 → 逐値 chip タプルは 0/0 恒真 PASS し、 契約非依存 census が唯一の FAIL 源。
cp "$BASE" "$TMP/pr7.yaml"; yq -i 'del(.references[].title)' "$TMP/pr7.yaml"
bash "$ASM" "$TMP/pr7.yaml" "$TMP/pr7.html" >/dev/null 2>&1 || ng "PR7 assemble 失敗 (title 無し contract の後方互換経路が壊れた)"
pr7_out="$(bash "$VER" "$TMP/pr7.yaml" "$TMP/pr7.html" 2>&1)"; pr7_rc=$?
if printf '%s\n' "$pr7_out" | grep -F 'references: (token,doc,role,title)' | grep -qF '[OK]'; then
  ok "PR7 補助 ★chip 逐値タプルは mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR7 補助 ★chip 逐値タプルが自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr7_rc -ne 0 ]] && printf '%s\n' "$pr7_out" | grep -F 'census: rf-gloss' | grep -qF '[FAIL]'; then
  ok "PR7 ★契約 title 一括削除を契約非依存 census (rf-gloss == 30) が捕捉 (0/0 恒真封鎖)"
else ng "PR7 ★census が title 一括削除を捕捉できず (rc=$pr7_rc = 0/0 恒真 PASS の再開通)"; fi
# PR8. ★role 可視ラベルの英語生表示への退行 (attr は不変) → chip タプル FAIL (平易語 map の逐値突合)。
cp "$TMP/base-filled.html" "$TMP/pr8.html"
perl -0777 -i -pe 'our $n; $n += s#(<span class="rf-role">)この規約が実装する原則#${1}implementation#g; END { exit($n?0:9) }' "$TMP/pr8.html" \
  || ng "PR8 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR8 ★role 可視ラベルの英語生表示への退行を chip タプルが捕捉 (attr は機械 token 保持)" "$TMP/pr8.html" "references: (token,doc,role,title)"
# PR9. ★優先度バッジの label↔level 詐称 (must の行に「推奨・現在」) → label↔level 束縛 FAIL。 ★ラベルは prose slot ゆえ
#   contract と直接突合できない — closed allowlist の逐値束縛が唯一の teeth (件数だけ数える検査では素通る形)。
cp "$TMP/base-filled.html" "$TMP/pr9.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-ver-001">)必須(</span>)#${1}推奨・現在${2}#; END { exit($n?0:9) }' "$TMP/pr9.html" \
  || ng "PR9 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR9 ★優先度バッジの label↔level 詐称 (must 行に「推奨・現在」) を allowlist 逐値束縛が捕捉" "$TMP/pr9.html" "label↔level 逐値束縛"
# PR9b. ★負の主張ラベル (ehar クラス): 語幹で始まる ★否定接尾 は前方一致を素通るが逐値集合には属さない。
cp "$TMP/base-filled.html" "$TMP/pr9b.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-ver-002">)必須(</span>)#${1}必須ではない${2}#; END { exit($n?0:9) }' "$TMP/pr9b.html" \
  || ng "PR9b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR9b ★否定接尾ラベル「必須ではない」を closed allowlist の逐値突合が捕捉 (前方一致では素通る形)" "$TMP/pr9b.html" "label↔level 逐値束縛"
# PR10. ★per-row 束縛 (relocation クラス): 別 row の slot-id を持ってくる (件数保存) → 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr10.html"
perl -0777 -i -pe 'our $n; $n += s#data-slot-id="prio-req-ver-001"#data-slot-id="prio-req-ver-002"#; END { exit($n?0:9) }' "$TMP/pr10.html" \
  || ng "PR10 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR10 ★優先度バッジ slot の per-row 束縛 (別 row の slot-id・件数保存) を要件タプルが捕捉" "$TMP/pr10.html" "要件タプル"
# PR10b. ★同じ relocation を平易行 slot でも撃つ (別 DOM 形状 = per-shape 規律)。
cp "$TMP/base-filled.html" "$TMP/pr10b.html"
perl -0777 -i -pe 'our $n; $n += s#data-slot-id="plain-req-ver-001"#data-slot-id="plain-req-ver-002"#; END { exit($n?0:9) }' "$TMP/pr10b.html" \
  || ng "PR10b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR10b ★平易行 slot の per-row 束縛 (別 row の slot-id・件数保存) を要件タプルが捕捉" "$TMP/pr10b.html" "要件タプル"
# PR11. ★平易行 (rq-plain) を 1 row 分削除 → 契約非依存 census + 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr11.html"
perl -0777 -i -pe 'our $n; $n += s#<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span><span data-prose-slot="plain" data-slot-id="plain-req-ver-001">[^<]*</span></p>\n##; END { exit($n?0:9) }' "$TMP/pr11.html" \
  || ng "PR11 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11 ★平易行 1 row 削除を契約非依存 census (rq-plain == 32) が捕捉" "$TMP/pr11.html" "census: rq-plain"
# PR11b. ★平易行の ★空化 (件数保存・per-row 非空 floor の isolation)。 census (占有数) は緑のまま = 非空 arm が唯一の teeth。
cp "$TMP/base-filled.html" "$TMP/pr11b.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="plain-req-ver-003">)[^<]+(</span>)#${1}${2}#; END { exit($n?0:9) }' "$TMP/pr11b.html" \
  || ng "PR11b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11b ★平易行の空化 (件数保存) を per-row 非空 floor が捕捉" "$TMP/pr11b.html" "rq-plain: 全 row で平易行が非空"
# PR11c. ★優先度バッジの ★空化 (PR11b の ★対称形)。 rq-plain 側だけに実弾があり rq-prio 側に無いのは
#   ★非対称な被覆漏れ (同じ per-row 非空 floor なのに片側の弱化だけが silent になる)。 占有数 census は
#   件数保存ゆえ緑のまま = 非空 arm が唯一の teeth。
cp "$TMP/base-filled.html" "$TMP/pr11c.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-ver-003">)[^<]+(</span>)#${1}${2}#; END { exit($n?0:9) }' "$TMP/pr11c.html" \
  || ng "PR11c mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11c ★優先度バッジの空化 (件数保存) を per-row 非空 floor が捕捉" "$TMP/pr11c.html" "rq-prio: 全 row で優先度ラベルが非空"
# PR11d. ★h2 総数 pin の ★大文字成分。 arm は `grep -oiE '<h2\b'` と ★大小無視 で数えており、 コメントも
#   「大文字注入の盲点是正」と主張する。 その成分を ★単独で 撃つ実弾が無いと、 -i を落とす弱化が silent になる
#   (小文字 h2 の注入は PR2b が既に撃っているので ★大文字 shape を別実弾で撃つ = per-shape 規律)。
cp "$TMP/base-filled.html" "$TMP/pr11d.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<H2>§NEW 大文字見出しの捏造</H2></body>#; END { exit($n==1?0:9) }' "$TMP/pr11d.html" \
  || ng "PR11d mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11d ★大文字 <H2> の注入を h2 総数 pin (大小無視) が捕捉" "$TMP/pr11d.html" "h2 総数"
# PR12. ★契約 requirements[].priority 一括削除 → 再生成 → 逐値タプルは自己整合 (0/0 恒真) し census が唯一の FAIL 源。
cp "$BASE" "$TMP/pr12.yaml"; yq -i 'del(.requirements[].priority)' "$TMP/pr12.yaml"
bash "$ASM" "$TMP/pr12.yaml" "$TMP/pr12.html" >/dev/null 2>&1 || ng "PR12 assemble 失敗 (priority 無し contract の後方互換経路が壊れた)"
pr12_out="$(bash "$VER" "$TMP/pr12.yaml" "$TMP/pr12.html" 2>&1)"; pr12_rc=$?
if printf '%s\n' "$pr12_out" | grep -F '要件タプル (id/pattern/class/label/essence/statement) 順序突合' | grep -qF '[OK]'; then
  ok "PR12 補助 ★要件タプルは mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR12 補助 ★要件タプルが自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr12_rc -ne 0 ]] && printf '%s\n' "$pr12_out" | grep -F 'census: rq-prio' | grep -qF '[FAIL]'; then
  ok "PR12 ★契約 priority 一括削除を契約非依存 census (rq-prio == 32) が捕捉 (0/0 恒真封鎖)"
else ng "PR12 ★census が priority 一括削除を捕捉できず (rc=$pr12_rc = 0/0 恒真 PASS の再開通)"; fi
# PR13. ★要件 normative fold の summary を旧英語ラベルへ戻す → summary 平易ラベル pin FAIL。
cp "$TMP/base-filled.html" "$TMP/pr13.html"
perl -0777 -i -pe 'our $n; $n += s#<summary>正確な条文（機械向けの厳密な書き方）</summary>#<summary>normative (machine)</summary>#g; END { exit($n?0:9) }' "$TMP/pr13.html" \
  || ng "PR13 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR13 ★rq-norm summary の英語ラベル退行を平易ラベル pin が捕捉" "$TMP/pr13.html" "summary 平易ラベル"
# PR14. ★machine fold の mf-kicker を旧英語ラベルへ戻す → mf-kicker pin FAIL。
cp "$TMP/base-filled.html" "$TMP/pr14.html"
perl -0777 -i -pe 'our $n; $n += s#<span class="mf-kicker">機械向けの詳細（原文そのまま）</span>#<span class="mf-kicker">機械層 (machine-readable)</span>#g; END { exit($n?0:9) }' "$TMP/pr14.html" \
  || ng "PR14 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR14 ★mf-kicker の英語ラベル退行を平易ラベル pin が捕捉" "$TMP/pr14.html" "mf-kicker 平易ラベル"
# PR14b. ★一部 fold だけ旧ラベルへ戻す部分退行 (件数 pin の teeth = 全 fold 同一 literal の要求)。
cp "$TMP/base-filled.html" "$TMP/pr14b.html"
perl -0777 -i -pe 'our $n; $n += s#<span class="mf-kicker">機械向けの詳細（原文そのまま）</span>#<span class="mf-kicker">機械層 (machine-readable)</span>#; END { exit($n?0:9) }' "$TMP/pr14b.html" \
  || ng "PR14b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR14b ★mf-kicker の ★部分 退行 (1 fold のみ) も件数 pin が捕捉" "$TMP/pr14b.html" "mf-kicker 平易ラベル"
# PR15. ★空 subsection の人間層 1 行要約を 1 件空化 → subhead essence 列 FAIL (見出しだけの節が復活する退行)。
cp "$TMP/base-filled.html" "$TMP/pr15.html"
perl -0777 -i -pe 'our $n; $n += s#(<h3 id="s1-1-concepts">§1\.1 3 concept</h3>)<p class="sub-se">[^<]*</p>#${1}<p class="sub-se"></p>#; END { exit($n?0:9) }' "$TMP/pr15.html" \
  || ng "PR15 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR15 ★空 subsection への退行 (1 行要約の空化) を subhead essence 列が捕捉" "$TMP/pr15.html" "subhead essence 列"
# PR15b. ★同じ退行を ★契約非依存 census が単独で撃てること (HTML 側だけを見る backstop の isolation)。
#   ★逐値突合と census の 2 本が同時に落ちる形ゆえ isolation は「census 側にも [FAIL] が立つ」で示す。
pr15b_out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/pr15.html" 2>&1)"
if printf '%s\n' "$pr15b_out" | grep -F 'census: 非空の subhead 1 行要約' | grep -qF '[FAIL]'; then
  ok "PR15b ★1 行要約の空化を契約非依存 census (非空 sub-se == 19) も独立に捕捉"
else ng "PR15b ★census が空 subsection 退行を捕捉できず (0/0 恒真 PASS の再開通)"; fi
# PR16. ★契約 subhead essence 一括空化 → 再生成 → 逐値 essence 列は「空 == 空」で自己整合し、 契約非依存 census が
#   唯一の FAIL 源 (空 subsection = 本文ゼロの見出しへの全面退行を独立 anchor が撃つ)。
#   ★assembler 側の hard abort は ★採らない: extractor が pre-flip 原本から再抽出する contract は本 cell 以前の
#   essence 状態を持ちうり、 その genuine 再生成が COLLAPSE 群の前提だから (Cell U の同注記と対)。
cp "$BASE" "$TMP/pr16.yaml"; yq -i '(.sections[].blocks[]? | select(.type=="subhead")).essence = ""' "$TMP/pr16.yaml"
bash "$ASM" "$TMP/pr16.yaml" "$TMP/pr16.html" >/dev/null 2>&1 || ng "PR16 assemble 失敗 (essence 空 subhead の後方互換経路が壊れた)"
pr16_out="$(bash "$VER" "$TMP/pr16.yaml" "$TMP/pr16.html" 2>&1)"; pr16_rc=$?
if printf '%s\n' "$pr16_out" | grep -F 'subhead essence 列' | grep -qF '[OK]'; then
  ok "PR16 補助 ★subhead essence 逐値は mutated 契約と自己整合 (census が唯一の FAIL 源)"
else ng "PR16 補助 ★subhead essence 逐値が自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr16_rc -ne 0 ]] && printf '%s\n' "$pr16_out" | grep -F 'census: 非空の subhead 1 行要約' | grep -qF '[FAIL]'; then
  ok "PR16 ★契約 essence 一括空化を契約非依存 census (非空 sub-se == 19) が捕捉"
else ng "PR16 ★census が essence 一括空化を捕捉できず (rc=$pr16_rc)"; fi
# PR17. ★priority allowlist 外 → assemble fail-closed abort。
cp "$BASE" "$TMP/pr17.yaml"; yq -i '.requirements[0].priority = "maybe"' "$TMP/pr17.yaml"
expect_abort "PR17 ★未知の priority を abort (must|should の closed allowlist)" "$TMP/pr17.yaml" "未知の priority"
# PR18. ★priority の部分欠落 (all-or-none 違反) → assemble abort (半端形 = badge が有ったり無かったりを封鎖)。
cp "$BASE" "$TMP/pr18.yaml"; yq -i 'del(.requirements[0].priority)' "$TMP/pr18.yaml"
expect_abort "PR18 ★priority の部分欠落を abort (all-or-none)" "$TMP/pr18.yaml" "priority の部分欠落"
# PR19. ★references[].title の部分欠落 (all-or-none 違反) → assemble abort。
cp "$BASE" "$TMP/pr19.yaml"; yq -i 'del(.references[0].title)' "$TMP/pr19.yaml"
expect_abort "PR19 ★references[].title の部分欠落を abort (all-or-none)" "$TMP/pr19.yaml" "title の部分欠落"
# PR20. ★priority の word-split bypass ("must should") → 逐値判定で abort (A14/A15/A16 と対称)。
cp "$BASE" "$TMP/pr20.yaml"; yq -i '.requirements[0].priority = "must should"' "$TMP/pr20.yaml"
expect_abort "PR20 ★priority 空白 split bypass を逐値判定で abort" "$TMP/pr20.yaml" "未知の priority"
# PR21. ★level↔statement 束縛 (契約内不変条件) の build 時 arm: 契約の priority だけを反転 (statement は SHALL のまま) → abort。
cp "$BASE" "$TMP/pr21.yaml"; yq -i '.requirements[0].priority = "should"' "$TMP/pr21.yaml"
expect_abort "PR21 ★priority↔statement の矛盾 (SHALL 要件に should) を build 時 abort" "$TMP/pr21.yaml" "modal verb が矛盾"
# PR22. ★同束縛の ★verify 側 単独 isolation: 生成物・契約・prose を ★全て自己整合 に保ったまま statement の modal verb
#   だけを反転する (contract の SHALL → SHOULD + 生成物の同一 statement 文字列を同期)。 assembler は今や abort するため
#   ★健全 contract で先に生成してから contract/HTML を対で改竄する (★契約 basename は footer 機械 SSoT と一致必須ゆえ
#   生成にも同名 copy を使う)。 要件タプル・label↔level・census は ★全て自己整合 で PASS = 新 chk が唯一の FAIL 源。
cp "$BASE" "$TMP/pr22.yaml"
bash "$ASM" "$TMP/pr22.yaml" "$TMP/pr22.pre.html" >/dev/null 2>&1 || ng "PR22 assemble 失敗 (MK 前提崩れ)"
bash "$INJ" "$BASE_PROSE" "$TMP/pr22.pre.html" "$TMP/pr22.html" >/dev/null 2>&1 || ng "PR22 inject 失敗 (MK 前提崩れ)"
yq -i '(.requirements[] | select(.id=="REQ-VER-003")).statement = ((.requirements[] | select(.id=="REQ-VER-003")).statement | sub("SHALL</span> specify"; "SHOULD</span> specify"))' "$TMP/pr22.yaml"
perl -0777 -i -pe 'our $n; $n += s#SHALL</span> specify <code>exit_code</code>#SHOULD</span> specify <code>exit_code</code>#; END { exit($n?0:9) }' "$TMP/pr22.html" \
  || ng "PR22 mutation が発火せず (shape drift = 空撃ち)"
pr22_out="$(bash "$VER" --filled "$BASE_PROSE" "$TMP/pr22.yaml" "$TMP/pr22.html" 2>&1)"; pr22_rc=$?
if printf '%s\n' "$pr22_out" | grep -F '要件タプル' | grep -qF '[OK]'; then
  ok "PR22 補助 ★要件タプルは mutated 契約と自己整合 (契約内不変 chk が唯一の FAIL 源 = isolation)"
else ng "PR22 補助 ★要件タプルが自己整合せず (単独 isolation の前提崩れ)"; fi
if [[ $pr22_rc -ne 0 ]] && printf '%s\n' "$pr22_out" | grep -F '[FAIL]' | grep -qF '契約内不変: priority == statement'; then
  ok "PR22 ★statement の modal verb 反転 (must 宣言 × SHOULD 条文) を契約内不変 chk が捕捉"
else ng "PR22 ★契約内不変 chk が level↔statement 矛盾を捕捉できず (rc=$pr22_rc = contract 全盲の再開通)"; fi
# PR23. ★first-modal-wins の ★危険方向 (SHOULD が先・MUST が後 = 弱い宣言で強い条文を包む) が AMBIGUOUS-BOTH で
#   abort すること。 ★wave 恒常 1 が Cell R 版「両方あれば即 AMBIGUOUS」を禁じ Cell U 版 first-modal-wins を wave
#   標準にした際、 緩めた方向が ★主節 MUST + 従属節 SHOULD に限られる (= 詐称に使えない) ことの実弾。
cp "$BASE" "$TMP/pr23.yaml"
yq -i '(.requirements[] | select(.id=="REQ-VER-003")).statement = "REQ-VER-003: Each scenario expect block SHOULD be normalized, and it MUST specify exit_code as the primary assertion."' "$TMP/pr23.yaml"
expect_abort "PR23 ★SHOULD 先行 + MUST 後続 を AMBIGUOUS-BOTH として abort (first-modal-wins の危険方向は fail-closed)" "$TMP/pr23.yaml" "modal verb が矛盾"
# PR23b. ★正当形の非回帰 (緩和の射程 pin): MUST 先行 + SHOULD 後続 (REQ-VER-005 の実在形) は ★abort しない。
#   ★Cell R 版規則を写すと本 case が abort し cell が構造的に完了不能になる (wave 恒常 1 の明文) — その非回帰実弾。
if bash "$ASM" "$BASE" "$TMP/pr23b.html" >/dev/null 2>&1; then
  ok "PR23b ★MUST 先行 + SHOULD 後続 (REQ-VER-005) は first-modal-wins で must と導出され build 可能 (Cell R 版なら abort)"
else ng "PR23b ★健全 contract が abort した (first-modal-wins が Cell R 版へ退行した疑い)"; fi
# PR24. ★heading_secnum の fail-closed abort の ★実弾 (宣言能力 == 実能力 の pin)。 §N 形でない heading を持つ契約 →
#   assemble abort。 ★退行の実態: emit_section が band_num "$(heading_secnum …)" と ★引数位置のコマンド置換 で呼ぶと、
#   bash は set -euo pipefail 下でも置換の失敗を親コマンドの成否に反映しないため exit 1 が subshell で飲まれ、
#   空 num のまま <span class="num"></span> を rc=0 で書き出す (verify 側 backstop 頼みの fail-open)。
#   ★被覆の正確な宣言: abort assert (PR24) 単独が殺せるのは「両層が消えた合流状態」のみ (期待 substring
#   『節番号を導出できない』は第 1 層 (emit_section 代入形) と第 2 層 (band_num 数値 guard) のメッセージに共通)。
#   第 1 層 ★単独 の退行は PR24b の負 assert (『band_num に非数値』が stderr に ★不在 = 第 1 層が band_num 到達前に
#   abort した証拠) が弁別する。
cp "$BASE" "$TMP/pr24.yaml"; yq -i '.sections[2].heading = "NO SECTION NUMBER"' "$TMP/pr24.yaml"
pr24_out="$(bash "$ASM" "$TMP/pr24.yaml" "$TMP/o.html" 2>&1)"; pr24_rc=$?
if [[ $pr24_rc -ne 0 && "$pr24_out" == *"節番号を導出できない"* ]]; then
  ok "PR24 ★§N 形でない heading を abort (節番号導出不能を silent に空 .num へ落とさない)"
else ng "PR24 ★§N 形でない heading を abort (abort されず生成された・または理由が想定外。 rc=$pr24_rc / 末尾: $(printf '%s' "$pr24_out" | tail -1))"; fi
if [[ $pr24_rc -ne 0 && "$pr24_out" == *"heading が §N 形でない"* && "$pr24_out" != *"band_num に非数値"* ]]; then
  ok "PR24b ★第 1 層 (emit_section 代入形) が band_num 到達前に abort (第 1 層メッセージ実在 + 第 2 層メッセージ不在 = 層独立の pin・空撃ちでは緑にならない)"
else ng "PR24b ★第 1 層の退行か空撃ち (rc=$pr24_rc / 第 2 層メッセージへ到達 or 第 1 層メッセージ不在)"; fi

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
# --- CEN-escrt. ★escape literal 軸 (handle_data/entityref/charref) の inert guard を per-shape で撃つ (errata-1 SHOULD-1) ---
#   MUST-1 で head scoping が消えた後も、 escape 軸には ★load-bearing な guard が残る (実測: 3 hook から
#   `not self.inert()` を外すと <template> / 自己閉じ <script/> 内の &lt;span / &lt;code が ★共に 1 へ計上される)。
#   ゆえに「不要」ではなく ★追加が必要 と判断した。 element 軸 (CEN-rt-*-el) / text-inline 軸 (CEN-rt-*-tx) は
#   別実装ゆえ escape 軸の穴を証明しない。 ★全 raw text tag + 入れ子形 を per-shape で撃つ。
f19_mut_reason "CEN-escrt-script ★&lt;span literal 1 個潰し + 自己閉じ <script/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<script/>&lt;span </script>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-style ★&lt;span literal 1 個潰し + 自己閉じ <style/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<style/>&lt;span </style>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-xmp ★&lt;span literal 1 個潰し + 自己閉じ <xmp/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<xmp/>&lt;span </xmp>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-iframe ★&lt;span literal 1 個潰し + 自己閉じ <iframe/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<iframe/>&lt;span </iframe>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-noembed ★&lt;span literal 1 個潰し + 自己閉じ <noembed/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<noembed/>&lt;span </noembed>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-noframes ★&lt;span literal 1 個潰し + 自己閉じ <noframes/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<noframes/>&lt;span </noframes>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-textarea ★&lt;span literal 1 個潰し + 自己閉じ <textarea/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<textarea/>&lt;span </textarea>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-title ★&lt;span literal 1 個潰し + 自己閉じ <title/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<title/>&lt;span </title>}" "census double-escape: &lt;span"
f19_mut_reason "CEN-escrt-nest ★同 literal 潰し + <template><script/></template> 入れ子 decoy による復元を census escape が FAIL" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<template><script/></template>&lt;span }" "census double-escape: &lt;span"

# === MINFORM. ★census_dump.handle_startendtag の ★最小形 (契約固定) の tracked 静的 pin (errata-1 MUST-6) ===
#   CEN-tplsc4 は当初 element 軸の最小形要件も撃つと称していたが ★恒真 PASS だった: census_dump 側を契約禁止の
#   naive 形 (`if tag not in VOID`) にしても全 case が緑のままで、 最小形と naive 形を ★区別できていなかった。
#   element 軸の「push は INERT_SUBTREE のみ」は canonical に自己閉じ SVG が存在して初めて差が出る性質で、
#   MK 実弾では安定に撃てない (差が出ない形を「撃っている」と表示するのが verify-laundering)。
#   ゆえに ★批准済み契約 (最小形逐字温存) は変えず、 pin 側を LIVEPIN 同型の ★静的 fixed-string 照合へ移す。
#   ★恒真化封鎖: 「naive 形が無いこと」(負の主張) だけを撃つと ★hook 消失・改称で黙って成立するため、
#   ★producer 存在 assert (最小形の行が 1 件実在) と ★対で 課す。
#   ★folio-ahn3 lockstep: hook には RAWTEXT 系へ CDATA mode を与える行が ★別行として 併存する (if/elif 統合は
#   最小形を崩すため禁止)。 本 pin は従来どおり ★最小形 push 行 1 件 / naive 形 0 件 のみを見る (併存行は
#   push 条件を変えないため mf_min / mf_naive は不変) — 併存行そのものは ★下段 SETCDATA 節 が per-site に撃つ。
#   ★2 つの pin は別の producer を見ており、 片方だけでは他方の消失を検出できない (MINFORM は set_cdata_mode
#   消失に無反応・SETCDATA は naive 形化に無反応) = ★対で 1 つの網。
for mf in verify-spec.sh verify-verification.sh; do
  mp="$SCRIPT_DIR/$mf"
  mf_hook="$(awk '/^    def handle_startendtag\(self, tag, attrs\):$/{f=1} f{print} f&&/^    def handle_endtag/{exit}' "$mp" | head -40)"
  mf_min="$(printf '%s\n' "$mf_hook" | grep -cF 'if tag in INERT_SUBTREE: self.stack.append(tag)')"
  mf_naive="$(printf '%s\n' "$mf_hook" | grep -cF 'if tag not in VOID')"
  if [[ "$mf_min" -eq 1 && "$mf_naive" -eq 0 ]]; then
    ok "MINFORM-$mf ★handle_startendtag は契約固定の最小形 (INERT_SUBTREE のみ push 1 件 / naive not-in-VOID 0 件)"
  else
    ng "MINFORM-$mf ★最小形が崩れている (最小形行=$mf_min 期待 1 / naive 行=$mf_naive 期待 0 — 前者 0 は hook 消失/改称)"
  fi
done


# === SETCDATA. ★set_cdata_mode 存在 pin (folio-ahn3・MINFORM と ★対) ===
#   RAWTEXT 系 inert の自己閉じ経路へ CDATA mode を与える 1 行は ★MINFORM が撃たない (MINFORM は最小形 push 行と
#   naive 形不在しか見ない)。 この行を誤って削っても MINFORM も CEN-rawnest 以外の全 case も緑のままになりうる
#   = ★silent regression する producer。 ゆえに ★静的 producer 存在 assert を新設し、 ★per-shape MK
#   (CEN-rawnest 群 = 8 タグ × 3 軸 × 両 arm の実弾 red→green) と ★対で 課す (静的 pin 単独 / MK 単独は
#   どちらか一方が恒真化しうる: 静的 pin は「行があるだけ」で効いている証明にならず、 MK は producer が
#   別実装へ差し替わっても表面的に緑になりうる)。
#   ★恒真化封鎖: 抽出が空 / hook 不在なら「1 件」は自明に不成立ゆえ、 抽出の非空も ★別 assert で撃つ
#   (関数改名・hook 消失で検査が黙って無力化するのを防ぐ = 本 suite 自身に対する trust anchor)。
#   ★4 site (verify-spec / verify-verification × census_dump / h_inline) を ★個別に 撃つ: 片 arm・片関数だけの
#   適用は cross-arm / intra-arm 非対称 = 残穴 (XARM gate と多重化した二重の網)。
for scf in verify-spec.sh verify-verification.sh; do
  for scfn in census_dump h_inline; do
    sc_body="$(awk -v fn="$scfn" 'index($0,fn"() { python3")==1{f=1} f{print} f&&/^}$/{exit}' "$SCRIPT_DIR/$scf")"
    sc_hook="$(printf '%s\n' "$sc_body" | awk '/^    def handle_startendtag\(self, tag, attrs\):$/{f=1} f{print} f&&/^    def handle_endtag/{exit}')"
    sc_n="$(printf '%s\n' "$sc_hook" | grep -cF 'set_cdata_mode(tag)')"
    sc_guard="$(printf '%s\n' "$sc_hook" | grep -cF 'def handle_startendtag')"
    if [[ "$sc_n" -eq 1 && "$sc_guard" -eq 1 ]]; then
      ok "SETCDATA-$scf-$scfn ★handle_startendtag に set_cdata_mode(tag) が 1 件実在 (RAWTEXT 系 inert の自己閉じ閉塞)"
    else
      ng "SETCDATA-$scf-$scfn ★set_cdata_mode 行が消えている/抽出不能 (実在=$sc_n 期待 1 / hook 抽出=$sc_guard 期待 1 — 後者 0 は関数改名/hook 消失で検査が無力化)"
    fi
  done
done

# === MECHPIN. ★containment 検査機構の健全性 arm の ★tracked 静的 pin (MINFORM / SETCDATA と同型) ===
#   「駆動表が全章を覆う」「probe が全章分の実測を出力」の 2 arm は ★artifact をどう改竄しても落ちない
#   (script 改変でしか落ちない) ため、 敵対 suite の構造上 per-shape MK を持てない。 その担保を worker の
#   ★untracked な self-test に置くと land 後にリポへ ★残らない ので、 tracked な本 suite で
#   ★arm の実在 と ★期待値が導出形であること を静的に pin する (admin gate round-3 R3-2)。
#   ★恒真化封鎖 (MINFORM 同型・admin gate round-4 R4-3): file 全体の grep (-ge 1 / -q) では、 将来
#   ★コメント等に同じ文字列が 1 つ増えるだけで 成立してしまう (arm 本体が消えても緑)。 ゆえに
#   (a) ★chk 行だけを awk で scope 切り出し (b) ★label と期待値の導出形を ★同一行 に要求 (c) ★==1 の逐値
#   の 3 点で締める (「どこかに文字列が在る」でなく「その arm が導出形の期待値で 1 本だけ在る」)。
#   ★chk は label と期待値が ★行継続 (`\`) で分かれることがあるため、 継続行を ★論理行へ連結してから 抽出する
#   (1 行 awk だと label 行しか取れず「同一行に導出形を要求」が構造的に成立しない = 恒偽になる)。
mech_chk="$(awk '{ cur = $0; if (buf != "") cur = buf cur; if (cur ~ /\\$/) { sub(/\\$/, "", cur); buf = cur; next } buf = ""; print cur }' "$VER" | grep '^chk "')"
mech_cov="$(printf '%s\n' "$mech_chk" | grep -F 'containment 駆動表が全章を覆う' | grep -cF 'NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}')"
mech_prb="$(printf '%s\n' "$mech_chk" | grep -F 'containment probe が全章分の実測を出力' | grep -cE '\$\{#_CT_ID\[@\]\} \* [0-9]+ \+ 1')"
if [[ "$mech_cov" -eq 1 ]]; then
  ok "MECHPIN ★駆動表 被覆 arm が chk 行に 1 本・期待値は contract 由来の導出形 (literal 直書きでない)"
else
  ng "MECHPIN ★駆動表 被覆 arm が chk 行で導出形として 1 本存在しない (実測 $mech_cov 期待 1 — arm 消失 / literal 直書きへの退行 / 複製)"
fi
if [[ "$mech_prb" -eq 1 ]]; then
  ok "MECHPIN ★probe 出力行数 arm が chk 行に 1 本・期待値は章数からの導出形"
else
  ng "MECHPIN ★probe 出力行数 arm が chk 行で導出形として 1 本存在しない (実測 $mech_prb 期待 1)"
fi
# ★producer 存在 assert (負の主張だけにしない): 上の 2 arm は chk 行の集合から数えているので、 その集合が
#   ★空でない ことを別途固定する (awk の抽出パターンが腐れば両 arm とも 0 になり ng へ倒れるが、 抽出自体の
#   健全性を独立に見ておく)。
mech_n="$(printf '%s\n' "$mech_chk" | grep -c .)"
if [[ "$mech_n" -ge 50 ]]; then ok "MECHPIN ★chk 行の抽出が健全 ($mech_n 行・scope 切り出しの producer 存在 assert)"
else ng "MECHPIN ★chk 行の抽出が壊れている ($mech_n 行 — awk パターンの腐りで上の 2 arm が恒偽化する)"; fi

# === CASEPIN. ★宣言済 CEN-* case が ★全て実行されたか の突合 (errata-1 MUST-2・silent skip の fail-closed 検出) ===
#   実害の前例: CEN-head3/head4 は label 内の ★未 escape backtick を bash がコマンド置換と解釈したため
#   ★一度も実行されず、 それでも suite は「170 passed, 0 failed」と GREEN を報告していた
#   (= 本 cell が主題にしている vacuous-green の再発・消失を N passed 形式は検出できない)。
#   ★宣言 (本 script 中の "CEN-<id> literal) と ★実出力 (ok/ng が記録した先頭 token) を集合突合し、
#   宣言されたのに出力されなかった case を fail-closed で撃つ。
casepin_declared="$(grep -oE '"CEN-[A-Za-z0-9-]+' "$0" | sed 's/^"//' | sort -u)"
casepin_seen="$(printf '%s\n' "${SEEN_IDS[@]:-}" | grep -E '^CEN-' | sort -u)"
casepin_missing="$(comm -23 <(printf '%s\n' "$casepin_declared") <(printf '%s\n' "$casepin_seen") | tr '\n' ' ')"
casepin_n="$(printf '%s\n' "$casepin_declared" | grep -c .)"
if [[ -z "${casepin_missing// /}" && "$casepin_n" -ge 30 ]]; then
  ok "CASEPIN ★宣言済 CEN-* case $casepin_n 本が全て実行された (silent skip 0)"
else
  ng "CASEPIN ★宣言済 CEN-* case が実行されていない (宣言 $casepin_n 本・未実行: ${casepin_missing:-なし} — 未 escape backtick 等による silent skip の疑い)"
fi

echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
