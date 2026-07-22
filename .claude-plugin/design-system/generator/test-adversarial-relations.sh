#!/usr/bin/env bash
# folio engine tr0 (folio-hd0) — spec-pack 敵対回帰テスト (relations dual-audience self-host・spec-pack fork)
#
# ★spec-pack fork (test-adversarial-spec.sh から fork)。 対象を relations.html 由来の contract/prose・
#   生成スクリプト (assemble-relations / verify-relations) へ差し替え、 敵対の改竄ターゲットを relations 固有の
#   要件 (REQ-REL-001..004)・section・table/code/subhead・照会 (P-x / ADR)・機械層 (★全て note = aside) に合わせた。
#   ★relations の機械層は 8 note (aside) のみ (prose=0 / list=0) = spec-pack rules (prose 含む) と異なる。
#   ゆえ M-series は spec-machine-note を狙う (prose/list 専用敵対は relations では non-applicable)。
#
# relations fork の fail-closed gate (assemble-relations validate abort / verify-relations FAIL / inject abort) が
# 構造捏造・★silent drop (未対応 block type)・要件/section/block/照会 fidelity 改竄・doc_type flip・
# core chrome 改竄・prose 改竄・機械層 round-trip 改竄 を捕捉することを回帰確認する。
# ★abort 系は stderr 理由を検証し「別原因の誤 abort」= false-pass を弾く。
# ★verify FAIL 系は理由 substring を検証し「想定 gate 以外の巻き添え FAIL」での false-pass を弾く。
#
# usage: test-adversarial-relations.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-relations.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-relations.sh"
BASE="$SCRIPT_DIR/contract/folio-relations.spec.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-relations.prose.yaml"
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

echo "spec-pack (relations fork) adversarial regression (fail-closed expected):"

# === assemble-relations validate (生成前 fail-closed) ===
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

# A9. ★要件の二重配置 (block ids に同一 id を 2 回) → abort。 relations の requirements block は s5 の 1 個のみゆえ、
#     同 block 内に REQ-REL-001 を重複追加して行数二重カウントを誘発する (sort|uniq -d が検出)。
cp "$BASE" "$TMP/a9.yaml"
yq -i '(.sections[] | select(.id=="s5") | .blocks[] | select(.type=="requirements")).ids += ["REQ-REL-001"]' "$TMP/a9.yaml"
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

# A17. ★section class の allowlist 外値 (folio-jmz1): normative/informative 以外は section wrapper へ stray class を
#      注入する fail-open ゆえ逐値判定で abort する (A15 tint と対称・CLASS_OK closed 2 値)。
cp "$BASE" "$TMP/a17.yaml"; yq -i '.sections[0].class = "rainbow"' "$TMP/a17.yaml"
expect_abort "A17 ★未知の section class を abort (CSS allowlist 外)" "$TMP/a17.yaml" "未知の section class"

# A18. ★section class の word-split bypass (folio-jmz1): "normative informative" は IFS split すれば個々が allowlist を
#      pass する fail-open だが、 逐値判定 (IFS= read -r で行全体を 1 値) で full 文字列を 1 件として abort する (A15 と対称)。
cp "$BASE" "$TMP/a18.yaml"; yq -i '.sections[0].class = "normative informative"' "$TMP/a18.yaml"
expect_abort "A18 ★section class 空白 split bypass を逐値判定で abort" "$TMP/a18.yaml" "未知の section class"

# === fabrication-free (HTML 改竄・生成後 fail-closed) ===
# F1. ★要件 row を 1 枚削除 → 行数 FAIL (REQ-REL-001 を REQ-REL-002 直前まで削除)。
cp "$TMP/base-filled.html" "$TMP/f1.html"
perl -0777 -i -pe 's#<div data-component="ears-requirement-row"[^>]*>.*?(?=<div data-component="ears-requirement-row"|</div>\s*</div>\s*<section)##s' "$TMP/f1.html"
expect_vfilled_fail "F1 要件 row 削除を行数 gate が捕捉" "$TMP/f1.html" "ears-requirement-row"

# F2. ★可視 rid 改竄 (attr 正) → 要件タプル vis FAIL
cp "$TMP/base-filled.html" "$TMP/f2.html"
perl -0777 -i -pe 's#(data-req-id="REQ-REL-001"[^>]*>\s*<div class="rq-head"><span class="rid">)REQ-REL-001#${1}REQ-FAKE#' "$TMP/f2.html"
expect_vfilled_fail "F2 ★可視 rid 改竄 (attr 正) を要件タプルで捕捉" "$TMP/f2.html" "要件"

# F3. ★要件 statement 改竄 → 要件タプル FAIL
cp "$TMP/base-filled.html" "$TMP/f3.html"
perl -0777 -i -pe 's#(<p class="rq-stmt">REQ-REL-001:)#${1} 捏造された一文。#' "$TMP/f3.html"
expect_vfilled_fail "F3 ★要件 statement 改竄を要件タプルで捕捉" "$TMP/f3.html" "要件タプル"

# F4. ★要件 essence 改竄 → 要件タプル FAIL
cp "$TMP/base-filled.html" "$TMP/f4.html"
perl -0777 -i -pe 's#<p class="rq-essence">各 spec は該当する forward#<p class="rq-essence">捏造された essence・各 spec は該当する forward#' "$TMP/f4.html"
expect_vfilled_fail "F4 ★要件 essence 改竄を要件タプルで捕捉" "$TMP/f4.html" "要件タプル"

# F5. ★EARS badge label 改竄 → 要件タプル FAIL (REQ-REL-002 = event-driven/trigger/event 応答 の label を別型へ)。
cp "$TMP/base-filled.html" "$TMP/f5.html"
perl -0777 -i -pe 's#(data-req-id="REQ-REL-002"[^>]*>.*?<span data-component="ears-badge" class="trigger">)event 応答#${1}無条件不変条件#s' "$TMP/f5.html"
expect_vfilled_fail "F5 ★EARS badge label 改竄を要件タプルで捕捉" "$TMP/f5.html" "要件タプル"

# F6. ★section heading 改竄 → section heading FAIL
cp "$TMP/base-filled.html" "$TMP/f6.html"
perl -0777 -i -pe 's#<h2>§1\. W3C Standard Vocabulary</h2>#<h2>§1. 捏造見出し</h2>#' "$TMP/f6.html"
expect_vfilled_fail "F6 ★section heading 改竄を捕捉" "$TMP/f6.html" "section 可視 heading"

# F7. ★section essence 改竄 → section essence FAIL (先頭 section essence に捏造を前置)。
cp "$TMP/base-filled.html" "$TMP/f7.html"
perl -0777 -i -pe 's#(<div data-component="section-essence-callout"><p class="sec-se">)#${1}捏造改竄 #' "$TMP/f7.html"
expect_vfilled_fail "F7 ★section essence 改竄を捕捉" "$TMP/f7.html" "section essence"

# F8. ★reference token 改竄 → references SET FAIL
cp "$TMP/base-filled.html" "$TMP/f8.html"
perl -0777 -i -pe 's#data-ref-token="P-1"#data-ref-token="P-999"#' "$TMP/f8.html"
expect_vfilled_fail "F8 ★reference token 改竄を SET で捕捉" "$TMP/f8.html" "references: token SET"

# F9. ★reference 可視 <b> のみ改竄 (attr 正) → (token,doc,role) vis FAIL
cp "$TMP/base-filled.html" "$TMP/f9.html"
perl -0777 -i -pe 's#(data-ref-token="P-1"[^>]*><span class="rf-token"><b>)P-1(</b>)#${1}P-FAKE${2}#' "$TMP/f9.html"
# ★ADR-0054 lockstep: chip 突合の label が (token,doc,role) → (token,doc,role,title) へ拡張されたため reason substring を再同期。
expect_vfilled_fail "F9 ★reference 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "references: (token,doc,role,title)"

# F10. ★reference role を allowlist 内別 role へ改竄 → (token,doc,role) FAIL
cp "$TMP/base-filled.html" "$TMP/f10.html"
perl -0777 -i -pe 's#(data-ref-token="P-1" data-ref-role=)"implementation"#${1}"verification"#' "$TMP/f10.html"
expect_vfilled_fail "F10 ★reference role 改竄 (allowlist 内別 role) を (token,role) で捕捉" "$TMP/f10.html" "references"

# F11. ★table セル改竄 → td 列 FAIL (inventory field 表の "ISO 8601" セル)。
cp "$TMP/base-filled.html" "$TMP/f11.html"
perl -0777 -i -pe 's#<td>ISO 8601</td>#<td>捏造ISO</td>#' "$TMP/f11.html"
expect_vfilled_fail "F11 ★table セル改竄を td 列で捕捉" "$TMP/f11.html" "table td"

# F12. ★code 行改竄 → code 行列 FAIL (inventory schema URL の code 例)。
cp "$TMP/base-filled.html" "$TMP/f12.html"
perl -0777 -i -pe 's#folio\.dev/inventory/v1\.json#folio.dev/inventory/CAPTURED.json#' "$TMP/f12.html"
expect_vfilled_fail "F12 ★code 行改竄を code 行列で捕捉" "$TMP/f12.html" "code 行列"

# F13. ★subhead heading 改竄 → subhead 列 FAIL (perl regex の @ 補間を避け §5.1 を狙う)。
# ★folio-0x0k: §5.1 subhead は id="s5-1-pattern" が付いた形へ shape 変化ゆえ撃ち直す (id は温存し heading だけ改竄) + fired-guard。
cp "$TMP/base-filled.html" "$TMP/f13.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subhead"><h3 id="s5-1-pattern">)§5\.1 双方向 dual の対象関係#${1}§5.1 捏造#s; END { exit($n?0:9) }' "$TMP/f13.html" \
  || ng "F13 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F13 ★subhead heading 改竄を捕捉" "$TMP/f13.html" "subhead heading"

# === folio-0x0k pre-flip: navigable anchor (section / subhead / requirement id) の per-shape MK ===
# ★per-shape で撃つ理由: section anchor (章包み <section id>) / subhead anchor (<h3 id>) / 要件 anchor (row id=) は
#   DOM 形状が別クラスゆえ個別 [FAIL] を pin する (1 instance の実弾は構造差のある instance の穴を証明しない・exit code 相乗り回避)。
# ANC1. ★section anchor 全剥奪 → section anchor 列 FAIL (corpus inbound #s5-3-ears 等が解決不能)。
cp "$TMP/base-filled.html" "$TMP/anc1.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="[^"]*"[^>]*>\n##g; END { exit($n?0:9) }' "$TMP/anc1.html" \
  || ng "ANC1 section anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC1 ★section anchor 全剥奪を section anchor 列が捕捉" "$TMP/anc1.html" "section anchor"
# ANC2. ★section anchor id 改竄 (値 drift) → section anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc2.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id=")s2-folio-vocab#${1}s2-TAMPERED#; END { exit($n?0:9) }' "$TMP/anc2.html" \
  || ng "ANC2 section anchor tamper mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC2 ★section anchor id 改竄を section anchor 列が捕捉" "$TMP/anc2.html" "section anchor"
# ANC3. ★subhead anchor 剥奪 (anchored subhead の id 脱落) → subhead anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc3.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subhead"><h3) id="s1-1-dcterms"#${1}#; END { exit($n?0:9) }' "$TMP/anc3.html" \
  || ng "ANC3 subhead anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC3 ★subhead anchor 剥奪を subhead anchor 列が捕捉" "$TMP/anc3.html" "subhead anchor"
# ANC4. ★陽性対照: 契約の 1 anchor 削除 → 当該 emit が fail-closed exit1 (assemble abort)。
cp "$BASE" "$TMP/anc4.yaml"; yq -i '(.sections[] | select(.id=="s2")) |= del(.anchor)' "$TMP/anc4.yaml"
expect_abort "ANC4 ★契約 section anchor 削除を assemble fail-closed abort (navigable id 不在)" "$TMP/anc4.yaml" "navigable id) が空"
# ANC5. ★陰性対照: anchor 大文字化 (link 解決 FAIL) → section anchor 列 FAIL (契約 lowercase と値不一致)。
cp "$TMP/base-filled.html" "$TMP/anc5.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id=")s2-folio-vocab("[^>]*>)#${1}S2-FOLIO-VOCAB${2}#; END { exit($n?0:9) }' "$TMP/anc5.html" \
  || ng "ANC5 section anchor uppercase mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC5 ★section anchor 大文字化 (link 解決 FAIL) を section anchor 列が捕捉" "$TMP/anc5.html" "section anchor"
# ANC6. ★要件 anchor (row id=) 剥奪 → 要件タプル FAIL。 ★3 shape 目 = 要件 row の id= (section/subhead とは別の
#   code path = tuple 埋込)。 id= 脱落で verify tuple regex (row opener に id="…" を literal 要求) が当該 row を取りこぼし件数/タプル不一致。
cp "$TMP/base-filled.html" "$TMP/anc6.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row") id="req-rel-001"#${1}#; END { exit($n?0:9) }' "$TMP/anc6.html" \
  || ng "ANC6 要件 anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC6 ★要件 anchor (row id=) 剥奪を要件タプルが捕捉" "$TMP/anc6.html" "要件タプル"
# ANC7. ★要件 anchor id 改竄 (値 drift) → 要件タプル FAIL。 row は regex match を保つ (id="…" 在) が anchor 列値が契約と不一致
#   = id= が data-req-id の *追加* であり値も突合対象であることを pin (剥奪でなく値の per-shape kill)。
cp "$TMP/base-filled.html" "$TMP/anc7.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row" id=")req-rel-001"#${1}req-rel-TAMPERED"#; END { exit($n?0:9) }' "$TMP/anc7.html" \
  || ng "ANC7 要件 anchor tamper mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC7 ★要件 anchor id 改竄を要件タプルが捕捉" "$TMP/anc7.html" "要件タプル"
# ANC8. ★陽性対照: 契約の要件 anchor 削除 → emit が fail-closed exit1 (assemble abort)。 全要件 anchor 保有 = hard fail-closed。
cp "$BASE" "$TMP/anc8.yaml"; yq -i 'del(.requirements[0].anchor)' "$TMP/anc8.yaml"
expect_abort "ANC8 ★契約 要件 anchor 削除を assemble fail-closed abort (navigable id 不在)" "$TMP/anc8.yaml" "navigable id) が空"

# === folio-jmz1: section.class (normative/informative wrapper) の per-shape MK ===
# ★per-shape で撃つ理由: 1 instance の実弾は *構造差のある* instance の穴を証明しない。 informative strip / normative strip /
#   count-preserving swap / 契約 field 削除 (emit 属性省略経路) / per-class count 保存の swap-pair は別クラスゆえ個別 [FAIL] を
#   pin する。 逐値 class 列 (position 層 i) と census floor (層 ii) の二層を各々 *独立に* isolate する: MK-d は census を唯一の
#   FAIL 源に (position 0/0 恒真)、 MK-e は position を唯一の FAIL 源に (census PASS) する対称配置。 全 MK は fired-guard 付き
#   (shape drift = 空撃ちを検出)。 ★relations 固有値: normative 5 (s1..s5) / informative 2 (s0/s6) — rules fork の 11/1 流用禁止。
# MK-a. ★s0 informative strip → informative census == 2 FAIL (class 属性のみ剥奪・id 温存)。
cp "$TMP/base-filled.html" "$TMP/mka.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s0-reader-guide") class="informative">#${1}>#; END { exit($n?0:9) }' "$TMP/mka.html" \
  || ng "MK-a s0 informative strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-a ★s0 informative strip を informative census floor が捕捉" "$TMP/mka.html" "informative census"
# MK-b. ★normative 1 本 (s1) strip → normative census == 5 FAIL (class 属性のみ剥奪・id 温存)。
cp "$TMP/base-filled.html" "$TMP/mkb.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s1-w3c-vocab") class="normative">#${1}>#; END { exit($n?0:9) }' "$TMP/mkb.html" \
  || ng "MK-b s1 normative strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-b ★normative 1 本 (s1) strip を normative census floor が捕捉" "$TMP/mkb.html" "normative census"
# MK-c. ★count-preserving swap (s0 informative→normative) → 総数 7 は保存されるが per-class census が破れる
#   (informative 2→1 / normative 5→6) + 逐値 class 列も FAIL。 件数保存の swap を per-class census + 逐値が殺す。
cp "$TMP/base-filled.html" "$TMP/mkc.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s0-reader-guide" class=")informative(">)#${1}normative${2}#; END { exit($n?0:9) }' "$TMP/mkc.html" \
  || ng "MK-c s0 informative→normative swap mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-c ★count-preserving swap (s0 informative→normative) を informative census + 逐値 class 列が捕捉" "$TMP/mkc.html" "informative census"
# MK-d. ★契約 s0 class 削除 → 再生成 (emit 属性省略経路) → census floor が捕捉。 ★position (逐値 class 列) は
#   mutated 契約 vs mutated HTML が空==空で 0/0 恒真 PASS するため、 census (契約非依存 hardcode) が唯一の FAIL 源
#   = census が load-bearing であることを isolate する (契約 field 削除の 0/0 恒真封鎖の実弾)。
cp "$BASE" "$TMP/mkd.yaml"; yq -i 'del(.sections[0].class)' "$TMP/mkd.yaml"
bash "$ASM" "$TMP/mkd.yaml" "$TMP/mkd.html" >/dev/null 2>&1 || ng "MK-d assemble 失敗 (emit 属性省略経路が壊れた)"
# 補助 positive control: mutated 契約 vs mutated HTML の class 列は自己整合 (position 0/0 PASS) を明示確認。
mkd_exp="$(yq -r '.sections[].class // ""' "$TMP/mkd.yaml")"
mkd_act="$(perl -CSD -0777 -ne 'while (/<section id="[^"]*"([^>]*)>/g){ my $a=$1; if ($a=~/\bclass="([^"]*)"/){ print "$1\n" } else { print "\n" } }' "$TMP/mkd.html")"
[[ "$mkd_exp" == "$mkd_act" ]] && ok "MK-d 補助 ★position class 列は mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)" || ng "MK-d 補助 ★position が自己整合せず (census 単独 isolation の前提崩れ)"
expect_vprefill_fail "MK-d ★契約 s0 class 削除→再生成 (emit 属性省略経路) を census floor が捕捉 (position は 0/0 恒真 PASS)" "$TMP/mkd.yaml" "$TMP/mkd.html" "informative census"
# MK-e. ★per-class count を保存する swap-pair (s0 informative→normative + s1 normative→informative) → normative 5 / informative 2
#   は不変ゆえ census (層 ii) は PASS し続けるが、 逐値 class 列 (層 i・position) が s0/s1 の位置で契約順とズレて FAIL する。
#   ★これは census では原理的に捕えられない唯一の mutation クラス = position 層が census とは独立に load-bearing であることを
#   isolate する (MK-d の census 単独 isolation と対称)。 ★swap 対の要件は informative↔normative の *対* であること
#   (per-class count = relations では 5/2 を保存し census を PASS させるため)。 rules fork の実弾 (s0-reader-guide ↔
#   s2-directory) は同要件を 11/1 で満たすが、 anchor id `s2-directory` が relations に存在しないため literal 流用は
#   できない。 relations では s0-reader-guide(informative) ↔ s1-w3c-vocab(normative) を採る。
cp "$TMP/base-filled.html" "$TMP/mke.html"
perl -0777 -i -pe 'our ($f0,$f1); $f0 += s#(<section id="s0-reader-guide" class=")informative(">)#${1}normative${2}#; $f1 += s#(<section id="s1-w3c-vocab" class=")normative(">)#${1}informative${2}#; END { exit(($f0 && $f1)?0:9) }' "$TMP/mke.html" \
  || ng "MK-e s0↔s1 count-preserving class swap-pair mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-e ★count-preserving swap-pair (s0 informative→normative + s1 normative→informative) を逐値 class 列 (position) が捕捉 (census は PASS・position 単独 isolation)" "$TMP/mke.html" "section class 列"

# === folio-0x0k errata E1: subsubhead (h4) = 第 4 anchor shape の per-shape MK (relations §4.4.1-3) ===
# ANC9. ★subsubhead (h4) anchor strip → subsubhead anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc9.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subsubhead"><h4) id="s4-4-1-scan"#${1}#; END { exit($n?0:9) }' "$TMP/anc9.html" \
  || ng "ANC9 subsubhead anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC9 ★subsubhead (h4) anchor 剥奪を subsubhead anchor 列が捕捉" "$TMP/anc9.html" "subsubhead anchor"
# ANC10. ★陽性対照: 契約の subsubhead anchor 削除 → assemble fail-closed abort。
cp "$BASE" "$TMP/anc10.yaml"; yq -i '(.sections[].blocks[] | select(.type=="subsubhead")) |= del(.anchor)' "$TMP/anc10.yaml"
expect_abort "ANC10 ★契約 subsubhead anchor 削除を assemble fail-closed abort (navigable id 不在)" "$TMP/anc10.yaml" "navigable id) が空"
# ANC11. ★陰性対照: subsubhead anchor 大文字化 (link 解決 FAIL) → subsubhead anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc11.html"
perl -0777 -i -pe 'our $n; $n += s#(<h4 id=")s4-4-1-scan(">)#${1}S4-4-1-SCAN${2}#; END { exit($n?0:9) }' "$TMP/anc11.html" \
  || ng "ANC11 subsubhead anchor uppercase mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC11 ★subsubhead anchor 大文字化 (link 解決 FAIL) を subsubhead anchor 列が捕捉" "$TMP/anc11.html" "subsubhead anchor"

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
perl -0777 -i -pe 's#<h1>folio relations — spec 間の関係性表現規約</h1>#<h1>詐欺タイトル</h1>#' "$TMP/f16.html"
expect_vfilled_fail "F16 ★core chrome (h1) 改竄を core-chrome で捕捉" "$TMP/f16.html" "core-chrome"

# F17. ★prose スロット内容改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/f17.html"
perl -0777 -i -pe 's#(data-slot-id="cover-summary">)[^<]*#${1}改竄された散文#' "$TMP/f17.html"
expect_vfilled_fail "F17 prose 改竄 (注入忠実) を verify が捕捉" "$TMP/f17.html" "注入"

# F18. ★HTML 注入の escape 健全性 (生 markup が構造へ漏れない・false-positive 防止)。
cp "$BASE" "$TMP/f18.yaml"; yq -i '.requirements[0].essence = "<script>alert(1)</script>危険"' "$TMP/f18.yaml"
bash "$ASM" "$TMP/f18.yaml" "$TMP/f18.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/f18.html"; then ng "F18 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/f18.html"; then ok "F18 HTML 注入を正規 entity に escape"
else ng "F18 正規 entity &lt;script&gt; が出ていない"; fi

# === kicker 列 fidelity (folio-l93・決定的フィールド→floor) ===
# F19. ★§番号 swap: §4↔§5 の kicker を入れ替え → 順序突合 FAIL (ZZSWAPZZ は doc に出ない安全な placeholder)。
cp "$TMP/base-filled.html" "$TMP/f19.html"
perl -0777 -i -pe 's#§4 / inventory#ZZSWAPZZ#; s#§5 / 双方向参照#§4 / inventory#; s#ZZSWAPZZ#§5 / 双方向参照#' "$TMP/f19.html"
expect_vfilled_fail "F19 ★kicker §番号 swap (§4↔§5) を kicker 列突合が捕捉" "$TMP/f19.html" "kicker"

# F20. ★topic 取り違え: §3 の kicker トピックを別章 (§5 双方向参照) のものへ → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f20.html"
perl -0777 -i -pe 's#§3 / JSON-LD#§3 / 双方向参照#' "$TMP/f20.html"
expect_vfilled_fail "F20 ★kicker topic 取り違え (§3 JSON-LD→双方向参照) を捕捉" "$TMP/f20.html" "kicker"

# F21. ★heading の §N との不整合: §5 の kicker を §9 へ (heading は「§5. Bidirectional Reference」) → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f21.html"
perl -0777 -i -pe 's#§5 / 双方向参照#§9 / 双方向参照#' "$TMP/f21.html"
expect_vfilled_fail "F21 ★kicker §N が heading §N と不整合 (§5→§9・heading §5) を捕捉" "$TMP/f21.html" "kicker"

# F22. ★静的 band kicker (references) の drift → 末尾 2 件も期待列に含むため FAIL ("(前方)" は perl regex で \( \) escape)。
cp "$TMP/base-filled.html" "$TMP/f22.html"
perl -0777 -i -pe 's#この規約が参照する文書 / 照会 \(前方\)#詐欺照会ラベル#' "$TMP/f22.html"
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

# === 4wz: emit_glossary 空中間 en (core lib/common.sh・relations assembler 経由で exercise) ===
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
# ★relations の機械層は 8 note (aside) のみ (prose=0 / list=0)。 M-series は spec-machine-note を狙う。
# M1. ★機械層 note テキスト改竄 → 原本↔生成物 round-trip FAIL (件数不変・テキスト差のみ = round-trip 単独検出)。
cp "$TMP/base-filled.html" "$TMP/m1.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine">)#${1}ZZNOTETAMPERZZ #' "$TMP/m1.html"
expect_vfilled_fail "M1 ★機械層 note 改竄を原本↔生成物 round-trip が捕捉" "$TMP/m1.html" "原本↔生成物 機械層"

# M2. ★機械層 note 脱落 (silent drop) → 件数 + round-trip FAIL。
cp "$TMP/base-filled.html" "$TMP/m2.html"
perl -0777 -i -pe 's#<aside data-component="spec-machine-note" data-audience="machine">.*?</aside>\n##s' "$TMP/m2.html"
expect_vfilled_fail "M2 ★機械層 note 脱落を件数+round-trip が捕捉" "$TMP/m2.html" "spec-machine-note"

# M3. ★機械層 note 捏造 (原本に無い block を add) → 件数 + round-trip FAIL (生成物のみ)。
cp "$TMP/base-filled.html" "$TMP/m3.html"
perl -0777 -i -pe 's#(<div class="machine-body">\n)#${1}<aside data-component="spec-machine-note" data-audience="machine">捏造された機械層</aside>\n#' "$TMP/m3.html"
expect_vfilled_fail "M3 ★機械層 note 捏造を round-trip (生成物のみ) が捕捉" "$TMP/m3.html" "原本↔生成物 機械層"

# M5. ★data-audience 値域違反 (machine→robot) → REQ-DA-STRUCT-3 FAIL (P-5 closed 2 値)。
cp "$TMP/base-filled.html" "$TMP/m5.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" )data-audience="machine"#${1}data-audience="robot"#' "$TMP/m5.html"
expect_vfilled_fail "M5 ★data-audience 値域違反 (robot) を REQ-DA-STRUCT-3 が捕捉" "$TMP/m5.html" "REQ-DA-STRUCT-3"

# M6. ★machine 部に aria-hidden → REQ-DA-STRUCT-4 FAIL (AI/AT からの normative 不可視化禁止)。
cp "$TMP/base-filled.html" "$TMP/m6.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine")>#${1} aria-hidden="true">#' "$TMP/m6.html"
expect_vfilled_fail "M6 ★machine 部の aria-hidden を REQ-DA-STRUCT-4 が捕捉" "$TMP/m6.html" "REQ-DA-STRUCT-4"

# M7. ★要件 container の data-audience="human" 剥奪 → tuple + REQ-DA-STRUCT-1 FAIL (孤立 human container 検出)。
# ★folio-0x0k: row opener に id="<navigable id>" が入った形へ shape が変わったため撃ち直す + fired-guard (空撃ち vacuous-green 封鎖)。
cp "$TMP/base-filled.html" "$TMP/m7.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row" id="[^"]*" data-req-id="[^"]*" data-ears-pattern="[^"]*") data-audience="human">#${1}>#g; END { exit($n?0:9) }' "$TMP/m7.html" \
  || ng "M7 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "M7 ★要件 container の data-audience=human 剥奪を REQ-DA-STRUCT-1 が捕捉" "$TMP/m7.html" "REQ-DA-STRUCT-1"

# M8. ★未対応 machine block type (silent drop 禁止・contract abort) → assemble fail-closed。
cp "$BASE" "$TMP/m8.yaml"; yq -i '.sections[1].machine_blocks += [{"type":"diagram","html":"x"}]' "$TMP/m8.yaml"
expect_abort "M8 ★未対応 machine block type を fail-closed abort (silent drop 禁止)" "$TMP/m8.yaml" "未対応 machine block type"

# M9. ★machine_preamble の未対応 type → assemble abort (relations の preamble は空だが += で生成され検査される)。
cp "$BASE" "$TMP/m9.yaml"; yq -i '.machine_preamble += [{"type":"video","html":"x"}]' "$TMP/m9.yaml"
expect_abort "M9 ★machine_preamble の未対応 type を fail-closed abort" "$TMP/m9.yaml" "未対応 machine block type"

# M10. ★機械層 note の二重 escape (live <code> が &lt;code&gt; 化) → round-trip FAIL (原本テキストと差)。
#   s3 note 専有の <code>&lt;head&gt;</code> (機械層のみに live で出現) を二重 escape する。
cp "$TMP/base-filled.html" "$TMP/m10.html"
perl -0777 -i -pe 's#<code>&lt;head&gt;</code>#&lt;code&gt;&lt;head&gt;&lt;/code&gt;#' "$TMP/m10.html"
expect_vfilled_fail "M10 ★機械層 note の二重 escape を round-trip が捕捉" "$TMP/m10.html" "原本↔生成物 機械層"

# M11. ★機械層 note 順序入替 (先頭 2 note を swap・件数/集合不変・順序のみ差) → 順序付き round-trip FAIL。
#   集合一致では素通っていた = §11 を順序付きに強化した major fix の red→green pin (人間層 §4/§5 と対称)。
cp "$TMP/base-filled.html" "$TMP/m11.html"
perl -0777 -i -e '
  local $/; my $H=<>;
  my @m; while ($H=~/(<aside data-component="spec-machine-note" data-audience="machine">.*?<\/aside>)/gs){ push @m,$1; last if @m>=2; }
  my ($a,$b)=($m[0],$m[1]);
  $H=~s/\Q$a\E/__M11A__/; $H=~s/\Q$b\E/__M11B__/; $H=~s/__M11A__/$b/; $H=~s/__M11B__/$a/;
  print $H;
' "$TMP/m11.html"
expect_vfilled_fail "M11 ★機械層 note 順序入替を順序付き round-trip が捕捉" "$TMP/m11.html" "原本↔生成物 機械層"

# M12. ★cross-section 誤帰属 (ある fold の machine note を別 fold の machine-body へ移動・件数/集合不変・document 順のみ差)
#   → 順序付き round-trip FAIL。 集合一致では section 帰属を検証できず素通っていた (major fix の red→green pin)。
cp "$TMP/base-filled.html" "$TMP/m12.html"
perl -0777 -i -e '
  local $/; my $H=<>;
  $H=~/(<aside data-component="spec-machine-note" data-audience="machine">.*?<\/aside>\n)/s; my $blk=$1;
  $H=~s/\Q$blk\E//;
  my @pos; while ($H=~/<div class="machine-body">\n/g){ push @pos,$+[0]; }
  my $ins=$pos[-1]; $H=substr($H,0,$ins).$blk.substr($H,$ins);
  print $H;
' "$TMP/m12.html"
expect_vfilled_fail "M12 ★cross-section 誤帰属を順序付き round-trip が捕捉" "$TMP/m12.html" "原本↔生成物 機械層"

# M15. ★原本不在 fail-closed pin (verify-relations §11 = 機械層 contract で原本 relations.html 不在なら FAIL)。
#   RELATIONS_ORIGIN_HTML で存在しない path を指し、 round-trip 照合不能を *素通さず* FAIL することを red→green で固定する。
#   ★これが無いと将来 path 解決 (SCRIPT_DIR 相対) が壊れても緑のまま = round-trip が silent skip する回帰を検出できない。
#   健全 baseline (P2 で PASS) を入力にし、 原本 path だけを破壊して fail-closed branch を確実に踏ませる
#   (= 別 gate の巻き添え FAIL でなく「原本不在」理由を substring 検証して false-pass を弾く)。
m15_out="$(RELATIONS_ORIGIN_HTML=/nonexistent/relations.html bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; m15_rc=$?
if [[ $m15_rc -eq 0 ]]; then
  ng "M15 ★原本不在 fail-closed (verify が PASS した = fail-open 回帰)"
elif [[ "$m15_out" != *"原本不在"* ]]; then
  ng "M15 ★原本不在 fail-closed (FAIL したが理由が想定外。 期待 '原本不在')"
else
  ok "M15 ★原本不在を verify-relations §11 が fail-closed FAIL (照合不能を素通さない)"
fi

# ============================================================================
# === ADR-0054 (flip 済 spec 提示層の標準形・folio-q7l7 Cell R) の per-shape mutation-kill (PR 群) ===
#   ★per-shape で撃つ理由: 章帯番号 / 静的 band heading / 章 wrapper / chip 一行タイトル / role 平易語 /
#     優先度バッジ / 平易行 / fold ラベル / 空 subsection 要約 / 一次参照 は ★DOM 形状が別クラス ゆえ、
#     1 instance の実弾は構造差のある instance の穴を証明しない (jyfh/r8k の per-shape 規律)。
#   ★★new field は ★all-or-none optional (extractor 再抽出物でも assemble できる互換性のため) ゆえ、
#     「契約から一括削除 → 再生成」で逐値突合が ★0/0 恒真 PASS する。 その ★唯一の FAIL 源 = 契約非依存
#     census を ★isolate する MK (MK-d と同型) を各軸に ★対で 置く (逐値 MK と census MK の 2 本立て)。
#   ★全 MK に fired-guard を付す (shape drift による空撃ちを検出)。
# ★★宣言能力 == 実能力 の開示: assemble-relations.sh の band_num() が持つ「core band() shape drift で
#   §番号書換が no-op なら abort」の fail-loud は、 共有 lib/common.sh の mutation を要するため ★本 suite の
#   per-shape MK では撃っていない (verify 側 PR1 = .num 列突合が同クラスの結果を捕捉する)。
# ============================================================================
# PR1. ★章帯番号を連番 (01) へ戻す退行 → band .num 列 FAIL (§番号一致 = ADR-0054 §2.2 / R11)。
cp "$TMP/base-filled.html" "$TMP/pr1.html"
perl -0777 -i -pe 'our $n; $n += s#<span class="num">0</span>#<span class="num">01</span>#; END { exit($n?0:9) }' "$TMP/pr1.html" \
  || ng "PR1 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR1 ★章帯番号の連番戻し (§番号 → 01) を band .num 列が捕捉" "$TMP/pr1.html" "band .num 列"
# PR2. ★静的 band heading を旧「検証へ前方照会する」へ戻す (R5 over-promise 再発) → heading 列 FAIL。
#   ★旧版の heading 列突合は head -n NSEC で静的 2 band を見ておらず、 この退行は ★無警備 だった (本 MK が新 teeth の実弾)。
cp "$TMP/base-filled.html" "$TMP/pr2.html"
perl -0777 -i -pe 'our $n; $n += s#<h2>§7\. 上位文書への前方照会 — 原則と決定記録へつながる</h2>#<h2>relations は照会の終端ではない — 原則・ADR・検証へ前方照会する</h2>#; END { exit($n?0:9) }' "$TMP/pr2.html" \
  || ng "PR2 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR2 ★静的 band heading の over-promise 復活 (§7) を heading 列が捕捉" "$TMP/pr2.html" "section 可視 heading 列"
# PR3. ★前方照会章の wrapper section 剥奪 (章化の喪失 = 目次から辿れない旧状態への退行) → section anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/pr3.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n##; END { exit($n?0:9) }' "$TMP/pr3.html" \
  || ng "PR3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3 ★前方照会章の wrapper 剥奪 (章化喪失) を section anchor 列が捕捉" "$TMP/pr3.html" "section anchor 列"
# PR4. ★wrapper への class 侵食 (normative/informative census 5/2 を汚す) → wrapper 陽性 assert + census FAIL。
cp "$TMP/base-filled.html" "$TMP/pr4.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">#<section id="forward-refs" class="normative">#; END { exit($n?0:9) }' "$TMP/pr4.html" \
  || ng "PR4 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4 ★提示層 wrapper への class 侵食を陽性 assert が捕捉 (census 汚染の封鎖)" "$TMP/pr4.html" "class 無しで実在"
# PR5. ★census id allowlist の default-block 維持 (admin 裁定 C2): wrapper 2 literal ★以外 の新 id は従来どおり FAIL する。
#   allowlist を「提示層由来なら何でも除外」へ緩める退行を撃つ (肯定形 allowlist であることの実弾)。
cp "$TMP/base-filled.html" "$TMP/pr5.html"
perl -0777 -i -pe 'our $n; $n += s#</h1>#</h1><span id="zz-new-anchor"></span>#; END { exit($n?0:9) }' "$TMP/pr5.html" \
  || ng "PR5 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR5 ★wrapper 以外の新 id は id census が従来どおり FAIL (肯定形 allowlist の default-block)" "$TMP/pr5.html" "census navigable id"
# PR6. ★chip 一行タイトル (rf-gloss) の値改竄 → chip タプル FAIL (contract title の逐語 echo が破れる)。
cp "$TMP/base-filled.html" "$TMP/pr6.html"
perl -0777 -i -pe 'our $n; $n += s#(<span class="rf-gloss">)spec は未来理想の anchor である#${1}捏造された一行タイトル#; END { exit($n?0:9) }' "$TMP/pr6.html" \
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
  ok "PR7 ★契約 title 一括削除を契約非依存 census (rf-gloss == 13) が捕捉 (0/0 恒真封鎖)"
else ng "PR7 ★census が title 一括削除を捕捉できず (rc=$pr7_rc = 0/0 恒真 PASS の再開通)"; fi
# PR8. ★role 可視ラベルの英語生表示への退行 (attr は不変) → chip タプル FAIL (平易語 map の逐値突合)。
cp "$TMP/base-filled.html" "$TMP/pr8.html"
perl -0777 -i -pe 'our $n; $n += s#(<span class="rf-role">)この規約が実装する原則#${1}implementation#g; END { exit($n?0:9) }' "$TMP/pr8.html" \
  || ng "PR8 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR8 ★role 可視ラベルの英語生表示への退行を chip タプルが捕捉 (attr は機械 token 保持)" "$TMP/pr8.html" "references: (token,doc,role,title)"
# PR9. ★優先度バッジの label↔level 詐称 (must の行に「推奨」) → label↔level 束縛 FAIL。 ★ラベルは prose slot ゆえ
#   contract と直接突合できない — closed allowlist の逐値束縛が唯一の teeth (件数だけ数える検査では素通る形)。
cp "$TMP/base-filled.html" "$TMP/pr9.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-rel-001">)必須#${1}推奨#; END { exit($n?0:9) }' "$TMP/pr9.html" \
  || ng "PR9 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR9 ★優先度バッジの label↔level 詐称 (must 行に「推奨」) を allowlist 逐値束縛が捕捉" "$TMP/pr9.html" "label↔level 逐値束縛"
# PR10. ★per-row 束縛 (relocation クラス): 別 row の slot-id を持ってくる (件数保存) → 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr10.html"
perl -0777 -i -pe 'our $n; $n += s#data-slot-id="prio-req-rel-001"#data-slot-id="prio-req-rel-002"#; END { exit($n?0:9) }' "$TMP/pr10.html" \
  || ng "PR10 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR10 ★優先度バッジ slot の per-row 束縛 (別 row の slot-id・件数保存) を要件タプルが捕捉" "$TMP/pr10.html" "要件タプル"
# PR11. ★平易行 (rq-plain) を 1 row 分削除 → 契約非依存 census + 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr11.html"
perl -0777 -i -pe 'our $n; $n += s#<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span><span data-prose-slot="plain" data-slot-id="plain-req-rel-001">[^<]*</span></p>\n##; END { exit($n?0:9) }' "$TMP/pr11.html" \
  || ng "PR11 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11 ★平易行 1 row 削除を契約非依存 census (rq-plain == 4) が捕捉" "$TMP/pr11.html" "census: rq-plain"
# PR12. ★契約 requirements[].priority 一括削除 → 再生成 → 逐値タプルは自己整合 (0/0 恒真) し census が唯一の FAIL 源。
cp "$BASE" "$TMP/pr12.yaml"; yq -i 'del(.requirements[].priority)' "$TMP/pr12.yaml"
bash "$ASM" "$TMP/pr12.yaml" "$TMP/pr12.html" >/dev/null 2>&1 || ng "PR12 assemble 失敗 (priority 無し contract の後方互換経路が壊れた)"
pr12_out="$(bash "$VER" "$TMP/pr12.yaml" "$TMP/pr12.html" 2>&1)"; pr12_rc=$?
if printf '%s\n' "$pr12_out" | grep -F '要件タプル (id/pattern/class/label/essence/statement) 順序突合' | grep -qF '[OK]'; then
  ok "PR12 補助 ★要件タプルは mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR12 補助 ★要件タプルが自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr12_rc -ne 0 ]] && printf '%s\n' "$pr12_out" | grep -F 'census: rq-prio' | grep -qF '[FAIL]'; then
  ok "PR12 ★契約 priority 一括削除を契約非依存 census (rq-prio == 4) が捕捉 (0/0 恒真封鎖)"
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
# PR15. ★空 subsection の人間層 1 行要約を 1 件削除 → essence 列 + census FAIL (見出しだけの節が復活する退行)。
cp "$TMP/base-filled.html" "$TMP/pr15.html"
perl -0777 -i -pe 'our $n; $n += s#(<h4 id="s4-4-1-scan">§4.4.1 Scan target directories</h4>)<p class="sub-se">[^<]*</p>#${1}#; END { exit($n?0:9) }' "$TMP/pr15.html" \
  || ng "PR15 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR15 ★空 subsection の 1 行要約 削除を subsubhead essence 列が捕捉" "$TMP/pr15.html" "subsubhead essence 列"
# PR16. ★契約 subsubhead essence 一括削除 → 再生成 → 逐値は 0/0 恒真、 census が唯一の FAIL 源。
cp "$BASE" "$TMP/pr16.yaml"; yq -i '(.sections[].blocks[]? | select(.type=="subsubhead")) |= del(.essence)' "$TMP/pr16.yaml"
bash "$ASM" "$TMP/pr16.yaml" "$TMP/pr16.html" >/dev/null 2>&1 || ng "PR16 assemble 失敗 (essence 無し subsubhead の経路が壊れた)"
pr16_out="$(bash "$VER" "$TMP/pr16.yaml" "$TMP/pr16.html" 2>&1)"; pr16_rc=$?
if printf '%s\n' "$pr16_out" | grep -F 'subsubhead essence 列' | grep -qF '[OK]'; then
  ok "PR16 補助 ★subsubhead essence 逐値は mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR16 補助 ★subsubhead essence 逐値が自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr16_rc -ne 0 ]] && printf '%s\n' "$pr16_out" | grep -F 'census: subsubhead の人間層 1 行要約' | grep -qF '[FAIL]'; then
  ok "PR16 ★契約 essence 一括削除を契約非依存 census (sub-se == 2) が捕捉 (0/0 恒真封鎖)"
else ng "PR16 ★census が essence 一括削除を捕捉できず (rc=$pr16_rc = 0/0 恒真 PASS の再開通)"; fi
# PR17. ★一次参照 (ref-primary) の値改竄 (href + label) → ref-primary 突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/pr17.html"
perl -0777 -i -pe 'our $n; $n += s#<a href="https://www\.w3\.org/TR/prov-o/">W3C PROV-O</a>#<a href="https://evil.example/">捏造 PROV-O</a>#; END { exit($n?0:9) }' "$TMP/pr17.html" \
  || ng "PR17 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR17 ★一次参照の href/label 改竄を ref-primary 突合が捕捉" "$TMP/pr17.html" "ref-primary (href,label,note)"
# PR18. ★契約 ref-primary block 一括削除 → 再生成 → 逐値は 0/0 恒真、 census が唯一の FAIL 源
#   (= 一次参照が人間層から丸ごと消える rw finding 3 の再発を唯一捕捉する)。
cp "$BASE" "$TMP/pr18.yaml"; yq -i '(.sections[] | select(.id=="s6")).blocks = []' "$TMP/pr18.yaml"
bash "$ASM" "$TMP/pr18.yaml" "$TMP/pr18.html" >/dev/null 2>&1 || ng "PR18 assemble 失敗"
pr18_out="$(bash "$VER" "$TMP/pr18.yaml" "$TMP/pr18.html" 2>&1)"; pr18_rc=$?
if printf '%s\n' "$pr18_out" | grep -F 'ref-primary (href,label,note)' | grep -qF '[OK]'; then
  ok "PR18 補助 ★ref-primary 逐値は mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR18 補助 ★ref-primary 逐値が自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr18_rc -ne 0 ]] && printf '%s\n' "$pr18_out" | grep -F 'census: ref-primary 項目占有' | grep -qF '[FAIL]'; then
  ok "PR18 ★契約 ref-primary 一括削除を契約非依存 census (== 4) が捕捉 (0/0 恒真封鎖)"
else ng "PR18 ★census が ref-primary 一括削除を捕捉できず (rc=$pr18_rc = 0/0 恒真 PASS の再開通)"; fi
# PR19. ★一次参照を機械層 fold へ退避し直す relocation (件数・値・順序は保存 = census と逐値突合は PASS)
#   → 「fold の外に在る」scope 検査が唯一の FAIL 源 (rw finding 3「実リストが機械層限定」への逆戻り)。
cp "$TMP/base-filled.html" "$TMP/pr19.html"
perl -0777 -i -e '
  local $/; my $H=<>;
  $H=~/(<ul class="ref-primary" data-component="spec-ref-primary">.*?<\/ul>\n)/s; my $blk=$1;
  exit(9) unless defined $blk;
  $H=~s/\Q$blk\E//;
  my @pos; while ($H=~/<div class="machine-body">\n/g){ push @pos,$+[0]; }
  exit(9) unless @pos;
  my $ins=$pos[-1]; $H=substr($H,0,$ins).$blk.substr($H,$ins);
  print $H;
' "$TMP/pr19.html" || ng "PR19 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR19 ★一次参照の機械層 fold への退避 (件数/値保存 relocation) を fold-scope 検査が捕捉" "$TMP/pr19.html" "ref-primary は折りたたみ (details 一般) の外"
# PR20. ★priority allowlist 外 → assemble fail-closed abort。
cp "$BASE" "$TMP/pr20.yaml"; yq -i '.requirements[0].priority = "maybe"' "$TMP/pr20.yaml"
expect_abort "PR20 ★未知の priority を abort (must|should の closed allowlist)" "$TMP/pr20.yaml" "未知の priority"
# PR21. ★priority の部分欠落 (all-or-none 違反) → assemble abort (半端形 = badge が有ったり無かったりを封鎖)。
cp "$BASE" "$TMP/pr21.yaml"; yq -i 'del(.requirements[0].priority)' "$TMP/pr21.yaml"
expect_abort "PR21 ★priority の部分欠落を abort (all-or-none)" "$TMP/pr21.yaml" "priority の部分欠落"
# PR22. ★references[].title の部分欠落 (all-or-none 違反) → assemble abort。
cp "$BASE" "$TMP/pr22.yaml"; yq -i 'del(.references[0].title)' "$TMP/pr22.yaml"
expect_abort "PR22 ★references[].title の部分欠落を abort (all-or-none)" "$TMP/pr22.yaml" "title の部分欠落"
# PR23. ★ref-primary item の空 href → assemble abort (壊れた一次参照の封鎖)。
cp "$BASE" "$TMP/pr23.yaml"; yq -i '(.sections[].blocks[]? | select(.type=="ref-primary")).items[0].href = ""' "$TMP/pr23.yaml"
expect_abort "PR23 ★ref-primary item の空 href を abort" "$TMP/pr23.yaml" "空 href/label"
# PR24. ★priority の word-split bypass ("must should") → 逐値判定で abort (A14/A15/A16 と対称)。
cp "$BASE" "$TMP/pr24.yaml"; yq -i '.requirements[0].priority = "must should"' "$TMP/pr24.yaml"
expect_abort "PR24 ★priority 空白 split bypass を逐値判定で abort" "$TMP/pr24.yaml" "未知の priority"

# --- folio-q7l7 self-review 由来の残穴封鎖 MK (major-2 / major-3) ---
# PR25. ★band .num の「§番号一致」束縛が ★両側 hardcode の同意 でないことの実弾 (self-review major-2)。
#   旧版は期待列を `seq 0 NSEC+1` で作り assembler も num=CHAPN-1 で同じ仮定を独立に持っていたため、 ★見出しの
#   §番号だけを動かすと帯 (3) と h2 (§9) の可視不整合が生じても rc=0 で素通った (実測 verified)。 期待列を
#   heading 由来へ変えた now は同じ mutation が band .num 列で落ちる。 ★heading 列自体は mutated contract と
#   自己整合する (契約 = 期待の SSoT ゆえ) — 唯一の FAIL 源が band .num 列であることが本 MK の isolation。
cp "$BASE" "$TMP/pr25.yaml"; yq -i '.sections[3].heading = "§9. JSON-LD Schema in <head>"' "$TMP/pr25.yaml"
bash "$ASM" "$TMP/pr25.yaml" "$TMP/pr25.html" >/dev/null 2>&1 || ng "PR25 assemble 失敗 (mutation が生成経路を壊した = MK 前提崩れ)"
pr25_out="$(bash "$VER" "$TMP/pr25.yaml" "$TMP/pr25.html" 2>&1)"; pr25_rc=$?
if printf '%s\n' "$pr25_out" | grep -F 'section 可視 heading 列' | grep -qF '[OK]'; then
  ok "PR25 補助 ★heading 列は mutated 契約と自己整合 (band .num 列が唯一の FAIL 源 = isolation)"
else ng "PR25 補助 ★heading 列が自己整合せず (band .num 列単独 isolation の前提崩れ)"; fi
if [[ $pr25_rc -ne 0 ]] && printf '%s\n' "$pr25_out" | grep -F '[FAIL]' | grep -qF 'band .num 列'; then
  ok "PR25 ★契約 heading の §番号だけの差し替え (帯 3 / h2 §9 の可視不整合) を band .num 列が捕捉 (heading 由来の期待列)"
else ng "PR25 ★band .num 列が heading §番号 drift を捕捉できず (rc=$pr25_rc = 両側 hardcode 同意の fail-open 再開通)"; fi
# PR26. ★label↔level 束縛の ★負の主張ラベル 漏れ (self-review major-3 / ehar クラス)。 旧版は canonical 語幹の
#   ★前方一致 だったため「必須」→「必須ではない」で意味が反転しても語幹で始まるゆえ ★素通った (実測 verified:
#   rc=0 / [FAIL] 0)。 closed allowlist の逐値突合へ変えた now は落ちる。
cp "$TMP/base-filled.html" "$TMP/pr26.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-rel-001">)必須(</span>)#${1}必須ではない${2}#; END { exit($n?0:9) }' "$TMP/pr26.html" \
  || ng "PR26 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR26 ★優先度ラベルの否定接尾 (must 行に「必須ではない」) を closed allowlist 逐値突合が捕捉" "$TMP/pr26.html" "label↔level 逐値束縛"

# --- folio-q7l7 self-review 第 2 巡 由来の残穴封鎖 MK (major-1 / major-2) ---
# PR27. ★level↔statement 束縛 (契約内不変条件・self-review major-1)。 旧版は priority を ★根 として突合するだけで
#   contract 自身が statement と矛盾する level を宣言しても ★全 gate を素通った (実測 verified: REQ-REL-001 の
#   priority を should へ反転 + prose ラベルを「推奨・現在」へ同期 → 再生成 → rc=0 / [FAIL] 0)。 ★2 arm で撃つ
#   (detect↔remediate parity): (a) build 時 fail-closed (assemble) / (b) 検出 (verify) の ★単独 isolation。
# PR27a. ★契約の priority だけを反転 (statement は SHALL のまま) → assemble abort。
cp "$BASE" "$TMP/pr27a.yaml"; yq -i '.requirements[0].priority = "should"' "$TMP/pr27a.yaml"
expect_abort "PR27a ★priority↔statement の矛盾 (SHALL 要件に should) を build 時 abort" "$TMP/pr27a.yaml" "modal verb が矛盾"
# PR27b. ★verify 側の単独 isolation: 生成物・契約・prose manifest を ★全て自己整合 に保ったまま statement の modal verb
#   だけを反転する (contract の SHOULD → SHALL + 生成物の同一 statement 文字列を同期)。 assembler は今や abort するため
#   ★健全 contract で先に生成してから contract/HTML を対で改竄する (★契約 basename は footer 機械SSoT と一致必須ゆえ
#   生成にも同名 copy を使う)。 要件タプル・label↔level・census は ★全て自己整合 で PASS = 新 chk が唯一の FAIL 源。
cp "$BASE" "$TMP/pr27.yaml"
bash "$ASM" "$TMP/pr27.yaml" "$TMP/pr27.pre.html" >/dev/null 2>&1 || ng "PR27b assemble 失敗 (MK 前提崩れ)"
bash "$INJ" "$BASE_PROSE" "$TMP/pr27.pre.html" "$TMP/pr27.html" >/dev/null 2>&1 || ng "PR27b inject 失敗 (MK 前提崩れ)"
yq -i '.requirements[2].statement = (.requirements[2].statement | sub("SHOULD"; "SHALL"))' "$TMP/pr27.yaml"
perl -0777 -i -pe 'our $n; $n += s#reverse relations SHOULD be written#reverse relations SHALL be written#; END { exit($n?0:9) }' "$TMP/pr27.html" \
  || ng "PR27b mutation が発火せず (shape drift = 空撃ち)"
pr27_out="$(bash "$VER" --filled "$BASE_PROSE" "$TMP/pr27.yaml" "$TMP/pr27.html" 2>&1)"; pr27_rc=$?
if printf '%s\n' "$pr27_out" | grep -F '要件タプル' | grep -qF '[OK]'; then
  ok "PR27b 補助 ★要件タプルは mutated 契約と自己整合 (契約内不変 chk が唯一の FAIL 源 = isolation)"
else ng "PR27b 補助 ★要件タプルが自己整合せず (単独 isolation の前提崩れ)"; fi
if [[ $pr27_rc -ne 0 ]] && printf '%s\n' "$pr27_out" | grep -F '[FAIL]' | grep -qF '契約内不変: priority == statement'; then
  ok "PR27b ★statement の modal verb 反転 (should 宣言 × SHALL 条文) を契約内不変 chk が捕捉"
else ng "PR27b ★契約内不変 chk が level↔statement 矛盾を捕捉できず (rc=$pr27_rc = contract 全盲の再開通)"; fi
# PR28. ★一次参照を generic <details> で包む隠蔽 (件数・値・順序は保存 / 機械層 fold ではない) — self-review major-2。
#   旧版の scope 検査は `<details data-component="spec-machine-fold">` ★のみ を列挙していたため素通った (実測 verified)。
#   PR19 (machine-body への relocation) とは ★DOM 形状が別クラス ゆえ per-shape で撃つ (jyfh/r8k の規律)。
cp "$TMP/base-filled.html" "$TMP/pr28.html"
perl -0777 -i -pe 'our $n; $n += s#(<ul class="ref-primary" data-component="spec-ref-primary">.*?</ul>)#<details><summary>参考</summary>${1}</details>#s; END { exit($n?0:9) }' "$TMP/pr28.html" \
  || ng "PR28 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR28 ★一次参照の generic <details> 隠蔽 (機械層 fold でない折りたたみ) を fold-scope 検査が捕捉" "$TMP/pr28.html" "ref-primary は折りたたみ (details 一般) の外"
# PR29. ★一次参照の ul へ隠蔽属性 (style="display:none") を付す shape — 折りたたみではなく ★属性 による既定表示からの
#   除去。 fold-scope 検査は素通る (details ではない) ため ★開始タグの逐語 pin が唯一の FAIL 源 = per-shape isolation。
cp "$TMP/base-filled.html" "$TMP/pr29.html"
perl -0777 -i -pe 'our $n; $n += s#<ul class="ref-primary" data-component="spec-ref-primary">#<ul class="ref-primary" data-component="spec-ref-primary" style="display:none">#; END { exit($n?0:9) }' "$TMP/pr29.html" \
  || ng "PR29 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR29 ★一次参照 ul への隠蔽属性付与 (style=display:none) を開始タグ逐語 pin が捕捉" "$TMP/pr29.html" "ul 開始タグは逐語 canonical"
# PR30. ★一次参照を ★入れ子 <details> で包む隠蔽 — PR28 と同じ「折りたたみへの退避」だが ★DOM 形状が別 (外側 details の
#   中に別 details が ★先行 する)。 旧述語は `<details...>(.*?)</details>` の ★非貪欲ペア regex だったため走査域が内側の
#   </details> で閉じ、 その後ろの rpi を 0 件と数える ★parser-differential fail-open だった (実測 verified: rc=0 /
#   [FAIL] 0 件・ul は無改変ゆえ逐語 pin も PASS = floor 全緑)。 per-shape 規律 (jyfh/r8k) で PR28 とは別建てに撃つ。
cp "$TMP/base-filled.html" "$TMP/pr30.html"
perl -0777 -i -pe 'our $n; $n += s#(<ul class="ref-primary" data-component="spec-ref-primary">.*?</ul>)#<details><summary>参考</summary><details><summary>inner</summary>x</details>${1}</details>#s; END { exit($n?0:9) }' "$TMP/pr30.html" \
  || ng "PR30 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR30 ★一次参照の入れ子 <details> 隠蔽 (非貪欲ペア regex の fail-open) を深さ追跡の fold-scope 検査が捕捉" "$TMP/pr30.html" "ref-primary は折りたたみ (details 一般) の外"

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

if repro_pins "$VER" relations "$BASE" "$BASE_PROSE" "$ASM" "$INJ" --filled "$BASE_PROSE"; then ok "repro-build conformance (a-d) 全 pass"; else ng "repro-build conformance (a-d) 逸脱"; fi
echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
