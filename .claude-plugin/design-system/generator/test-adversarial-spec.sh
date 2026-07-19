#!/usr/bin/env bash
# folio engine B6 (folio-8ct) — spec-pack 敵対回帰テスト (instance#5 / self-dogfood)
#
# spec-pack の fail-closed gate (assemble-spec validate abort / verify-spec FAIL / inject abort) が
# 構造捏造・★silent drop (未対応 block type)・要件/section/block/照会 fidelity 改竄・doc_type flip・
# core chrome 改竄・prose 改竄 を捕捉することを回帰確認する。
# SRS/ADR/research/principle の test-adversarial-*.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
# ★abort 系は stderr 理由を検証し「別原因の誤 abort」= false-pass を弾く。
# ★verify FAIL 系は理由 substring を検証し「想定 gate 以外の巻き添え FAIL」での false-pass を弾く。
#
# usage: test-adversarial-spec.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-spec.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-spec.sh"
BASE="$SCRIPT_DIR/contract/folio-rules.spec.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/folio-rules.prose.yaml"
# ★COLLAPSE 用 epoch 固定 assembler (folio-7wbn): lib/ 解決のため ★SCRIPT_DIR 直下に置く transient (tracked 化しない)。
#   EXIT trap で必ず掃除する (残骸を worktree へ持ち込まない)。
EPOCH_ASM="$SCRIPT_DIR/.collapse-epoch-asm-spec.sh"
# ★SNAPPIN 用 transient verify copy (folio-7wbn ceiling fix): census file path を差し替えた verify-spec を
#   ★SCRIPT_DIR 直下に置く (tmp へ copy すると SCRIPT_DIR が動き lib/ 解決に失敗して exit 2 = 「arm 不在」と
#   区別できない偽 RED になる)。 EXIT trap で必ず掃除する。
PIN_VER="$SCRIPT_DIR/.census-pin-verify-spec.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$EPOCH_ASM" "$PIN_VER"' EXIT
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
cp "$BASE" "$TMP/a1.yaml"; yq -i '.meta.doc_type = "rules-doc"' "$TMP/a1.yaml"
expect_abort "A1 ★doc_type flip を abort (gate bypass 封鎖)" "$TMP/a1.yaml" "doc_type は rules 必須"

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

# A9. ★要件の二重配置 (2 block で同一 id) → abort。 s10 に置かれた REQ-CM-001 を s9 の requirements block にも追加。
cp "$BASE" "$TMP/a9.yaml"
yq -i '(.sections[] | select(.id=="s9") | .blocks[] | select(.type=="requirements")).ids += ["REQ-CM-001"]' "$TMP/a9.yaml"
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

# A17. ★section class の allowlist 外値 (folio-5dad): normative/informative 以外は section wrapper へ stray class を
#      注入する fail-open ゆえ逐値判定で abort する (A4 tint と対称・CLASS_OK closed 2 値)。
cp "$BASE" "$TMP/a17.yaml"; yq -i '.sections[0].class = "rainbow"' "$TMP/a17.yaml"
expect_abort "A17 ★未知の section class を abort (CSS allowlist 外)" "$TMP/a17.yaml" "未知の section class"

# A18. ★section class の word-split bypass (folio-5dad): "normative informative" は IFS split すれば個々が allowlist を
#      pass する fail-open だが、 逐値判定 (IFS= read -r で行全体を 1 値) で full 文字列を 1 件として abort する (A15 と対称)。
cp "$BASE" "$TMP/a18.yaml"; yq -i '.sections[0].class = "normative informative"' "$TMP/a18.yaml"
expect_abort "A18 ★section class 空白 split bypass を逐値判定で abort" "$TMP/a18.yaml" "未知の section class"

# === fabrication-free (HTML 改竄・生成後 fail-closed) ===
# F1. ★要件 row を 1 枚削除 → 行数 FAIL
cp "$TMP/base-filled.html" "$TMP/f1.html"
perl -0777 -i -pe 's#<div data-component="ears-requirement-row"[^>]*>.*?(?=<div data-component="ears-requirement-row"|</div>\s*</div>\s*<section)##s' "$TMP/f1.html"
expect_vfilled_fail "F1 要件 row 削除を行数 gate が捕捉" "$TMP/f1.html" "ears-requirement-row"

# F2. ★可視 rid 改竄 (attr 正) → 要件タプル vis FAIL
cp "$TMP/base-filled.html" "$TMP/f2.html"
perl -0777 -i -pe 's#(data-req-id="REQ-CM-001"[^>]*>\s*<div class="rq-head"><span class="rid">)REQ-CM-001#${1}REQ-FAKE#' "$TMP/f2.html"
expect_vfilled_fail "F2 ★可視 rid 改竄 (attr 正) を要件タプルで捕捉" "$TMP/f2.html" "要件"

# F3. ★要件 statement 改竄 → 要件タプル FAIL
cp "$TMP/base-filled.html" "$TMP/f3.html"
perl -0777 -i -pe 's#(<p class="rq-stmt">REQ-CM-001:)#${1} 捏造された一文。#' "$TMP/f3.html"
expect_vfilled_fail "F3 ★要件 statement 改竄を要件タプルで捕捉" "$TMP/f3.html" "要件タプル"

# F4. ★要件 essence 改竄 → 要件タプル FAIL
cp "$TMP/base-filled.html" "$TMP/f4.html"
perl -0777 -i -pe 's#<p class="rq-essence">caller marker env var が不在#<p class="rq-essence">捏造された essence・不在#' "$TMP/f4.html"
expect_vfilled_fail "F4 ★要件 essence 改竄を要件タプルで捕捉" "$TMP/f4.html" "要件タプル"

# F5. ★EARS badge label 改竄 → 要件タプル FAIL
cp "$TMP/base-filled.html" "$TMP/f5.html"
perl -0777 -i -pe 's#(data-req-id="REQ-CM-003"[^>]*>.*?<span data-component="ears-badge" class="forbid">)異常応答#${1}無条件不変条件#s' "$TMP/f5.html"
expect_vfilled_fail "F5 ★EARS badge label 改竄を要件タプルで捕捉" "$TMP/f5.html" "要件タプル"

# F6. ★section heading 改竄 → section heading FAIL
cp "$TMP/base-filled.html" "$TMP/f6.html"
perl -0777 -i -pe 's#<h2>§6\. EARS Notation Markup</h2>#<h2>§6. 捏造見出し</h2>#' "$TMP/f6.html"
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
expect_vfilled_fail "F9 ★reference 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "references: (token,doc,role)"

# F10. ★reference role を allowlist 内別 role へ改竄 → (token,doc,role) FAIL
cp "$TMP/base-filled.html" "$TMP/f10.html"
perl -0777 -i -pe 's#(data-ref-token="P-1" data-ref-role=)"implementation"#${1}"verification"#' "$TMP/f10.html"
expect_vfilled_fail "F10 ★reference role 改竄 (allowlist 内別 role) を (token,role) で捕捉" "$TMP/f10.html" "references"

# F11. ★block prose 可視テキスト改竄 → prose 列 FAIL (s12 等の prose があれば。無ければ table 改竄で代替)
cp "$TMP/base-filled.html" "$TMP/f11.html"
perl -0777 -i -pe 's#<td>Ubiquitous</td>#<td>捏造Ubiquitous</td>#' "$TMP/f11.html"
expect_vfilled_fail "F11 ★table セル改竄を td 列で捕捉" "$TMP/f11.html" "table td"

# F12. ★code 行改竄 → code 行列 FAIL
cp "$TMP/base-filled.html" "$TMP/f12.html"
perl -0777 -i -pe 's#&lt;meta charset=&quot;UTF-8&quot;&gt;#&lt;meta charset=&quot;CAPTURED&quot;&gt;#' "$TMP/f12.html"
expect_vfilled_fail "F12 ★code 行改竄を code 行列で捕捉" "$TMP/f12.html" "code 行列"

# F13. ★subhead heading 改竄 → subhead 列 FAIL
# ★folio-0x0k: §9.1 subhead は id="s9-1-markup" が付いた形へ shape 変化ゆえ撃ち直す (id は温存し heading だけ改竄) + fired-guard。
cp "$TMP/base-filled.html" "$TMP/f13.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subhead"><h3 id="s9-1-markup">)§9\.1 markup 規約#${1}§9.1 捏造#s; END { exit($n?0:9) }' "$TMP/f13.html" \
  || ng "F13 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F13 ★subhead heading 改竄を捕捉" "$TMP/f13.html" "subhead heading"

# === folio-0x0k pre-flip: navigable anchor (section / subhead / requirement id) の per-shape MK ===
# ★per-shape で撃つ理由: 1 instance の実弾は *構造差のある* instance の穴を証明しない。 section anchor (章包み <section id>) /
#   subhead anchor (<h3 id>) / 要件 anchor (row id=) は DOM 形状が別クラスゆえ個別 [FAIL] を pin する (exit code 相乗り回避)。
# ANC1. ★section anchor 全剥奪 → section anchor 列 FAIL (corpus inbound #s2-directory 等が解決不能)。
cp "$TMP/base-filled.html" "$TMP/anc1.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="[^"]*"[^>]*>\n##g; END { exit($n?0:9) }' "$TMP/anc1.html" \
  || ng "ANC1 section anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC1 ★section anchor 全剥奪を section anchor 列が捕捉" "$TMP/anc1.html" "section anchor"
# ANC2. ★section anchor id 改竄 (値 drift) → section anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc2.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id=")s2-directory#${1}s2-TAMPERED#; END { exit($n?0:9) }' "$TMP/anc2.html" \
  || ng "ANC2 section anchor tamper mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC2 ★section anchor id 改竄を section anchor 列が捕捉" "$TMP/anc2.html" "section anchor"
# ANC3. ★subhead anchor 剥奪 (anchored subhead の id 脱落) → subhead anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/anc3.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="spec-subhead"><h3) id="s9-1-markup"#${1}#; END { exit($n?0:9) }' "$TMP/anc3.html" \
  || ng "ANC3 subhead anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC3 ★subhead anchor 剥奪を subhead anchor 列が捕捉" "$TMP/anc3.html" "subhead anchor"
# ANC4. ★陽性対照: 契約の 1 anchor 削除 → 当該 emit が fail-closed exit1 (assemble abort)。
cp "$BASE" "$TMP/anc4.yaml"; yq -i '(.sections[] | select(.id=="s2")) |= del(.anchor)' "$TMP/anc4.yaml"
expect_abort "ANC4 ★契約 section anchor 削除を assemble fail-closed abort (navigable id 不在)" "$TMP/anc4.yaml" "navigable id) が空"
# ANC5. ★陰性対照: anchor 大文字化 (link 解決 FAIL) → section anchor 列 FAIL (契約 lowercase と値不一致)。
cp "$TMP/base-filled.html" "$TMP/anc5.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id=")s2-directory("[^>]*>)#${1}S2-DIRECTORY${2}#; END { exit($n?0:9) }' "$TMP/anc5.html" \
  || ng "ANC5 section anchor uppercase mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC5 ★section anchor 大文字化 (link 解決 FAIL) を section anchor 列が捕捉" "$TMP/anc5.html" "section anchor"
# ANC6. ★要件 anchor (row id=) 剥奪 → 要件タプル FAIL。 ★3 shape 目 = 要件 row の id= (section/subhead とは別の
#   code path = tuple 埋込)。 id= 脱落で verify tuple regex (row opener に id="…" を literal 要求) が当該 row を取りこぼし件数/タプル不一致。
cp "$TMP/base-filled.html" "$TMP/anc6.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row") id="req-da-struct-1"#${1}#; END { exit($n?0:9) }' "$TMP/anc6.html" \
  || ng "ANC6 要件 anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC6 ★要件 anchor (row id=) 剥奪を要件タプルが捕捉" "$TMP/anc6.html" "要件タプル"
# ANC7. ★要件 anchor id 改竄 (値 drift) → 要件タプル FAIL。 row は regex match を保つ (id="…" 在) が anchor 列値が契約と不一致
#   = id= が data-req-id の *追加* であり値も突合対象であることを pin (剥奪でなく値の per-shape kill)。
cp "$TMP/base-filled.html" "$TMP/anc7.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="ears-requirement-row" id=")req-da-struct-1"#${1}req-da-struct-TAMPERED"#; END { exit($n?0:9) }' "$TMP/anc7.html" \
  || ng "ANC7 要件 anchor tamper mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC7 ★要件 anchor id 改竄を要件タプルが捕捉" "$TMP/anc7.html" "要件タプル"
# ANC8. ★陽性対照: 契約の要件 anchor 削除 → emit が fail-closed exit1 (assemble abort)。 全要件 anchor 保有 = hard fail-closed。
cp "$BASE" "$TMP/anc8.yaml"; yq -i 'del(.requirements[0].anchor)' "$TMP/anc8.yaml"
expect_abort "ANC8 ★契約 要件 anchor 削除を assemble fail-closed abort (navigable id 不在)" "$TMP/anc8.yaml" "navigable id) が空"

# === folio-0x0k errata E2: p-anchor (機械層 prose s3-vocab-schema) の self-anchor 整合 MK ===
# ANC12. ★機械層 prose id strip → self-anchor 整合 FAIL (同一文書内 href="#s3-vocab-schema" が解決不能になる)。
cp "$TMP/base-filled.html" "$TMP/anc12.html"
perl -0777 -i -pe 'our $n; $n += s#(<p) id="s3-vocab-schema"( data-component="spec-machine-prose")#${1}${2}#; END { exit($n?0:9) }' "$TMP/anc12.html" \
  || ng "ANC12 p-anchor strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "ANC12 ★p-anchor (機械層 prose id) 剥奪を self-anchor 整合 が捕捉" "$TMP/anc12.html" "self-anchor 整合"

# === folio-5dad: section.class (§4.4 normative/informative wrapper) の per-shape MK ===
# ★per-shape で撃つ理由: 1 instance の実弾は *構造差のある* instance の穴を証明しない。 informative strip / normative strip /
#   count-preserving swap / 契約 field 削除 (emit 属性省略経路) / per-class count 保存の swap-pair は別クラスゆえ個別 [FAIL] を
#   pin する。 逐値 class 列 (position 層 i) と census floor (層 ii) の二層を各々 *独立に* isolate する: MK-d は census を唯一の
#   FAIL 源に (position 0/0 恒真)、 MK-e は position を唯一の FAIL 源に (census PASS) する対称配置。 全 MK は fired-guard 付き
#   (shape drift = 空撃ちを検出)。
# MK-a. ★s0 informative strip → informative census == 1 FAIL (class 属性のみ剥奪・id 温存)。
cp "$TMP/base-filled.html" "$TMP/mka.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s0-reader-guide") class="informative">#${1}>#; END { exit($n?0:9) }' "$TMP/mka.html" \
  || ng "MK-a s0 informative strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-a ★s0 informative strip を informative census floor が捕捉" "$TMP/mka.html" "informative census"
# MK-b. ★normative 1 本 (s2) strip → normative census == 11 FAIL (class 属性のみ剥奪・id 温存)。
cp "$TMP/base-filled.html" "$TMP/mkb.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory") class="normative">#${1}>#; END { exit($n?0:9) }' "$TMP/mkb.html" \
  || ng "MK-b s2 normative strip mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-b ★normative 1 本 (s2) strip を normative census floor が捕捉" "$TMP/mkb.html" "normative census"
# MK-c. ★count-preserving swap (s0 informative→normative) → 総数 12 は保存されるが per-class census が破れる
#   (informative 1→0 / normative 11→12) + 逐値 class 列も FAIL。 件数保存の swap を per-class census + 逐値が殺す。
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
# MK-e. ★per-class count を保存する swap-pair (s0 informative→normative + s2 normative→informative) → normative 11 / informative 1
#   は不変ゆえ census (層 ii) は PASS し続けるが、 逐値 class 列 (層 i・position) が s0/s2 の位置で契約順とズレて FAIL する。
#   ★これは census では原理的に捕えられない唯一の mutation クラス = position 層が census とは独立に load-bearing であることを
#   isolate する (MK-d の census 単独 isolation と対称)。 position check が万一 wildcard/count-only へ regress すれば
#   (folio-bur verify-spec:73-79 の wildcard 素通り bug の再演) 本 case が空撃ちで抜ける = self-test が退行を検出する。
cp "$TMP/base-filled.html" "$TMP/mke.html"
perl -0777 -i -pe 'our ($f0,$f2); $f0 += s#(<section id="s0-reader-guide" class=")informative(">)#${1}normative${2}#; $f2 += s#(<section id="s2-directory" class=")normative(">)#${1}informative${2}#; END { exit(($f0 && $f2)?0:9) }' "$TMP/mke.html" \
  || ng "MK-e s0↔s2 count-preserving class swap-pair mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "MK-e ★count-preserving swap-pair (s0 informative→normative + s2 normative→informative) を逐値 class 列 (position) が捕捉 (census は PASS・position 単独 isolation)" "$TMP/mke.html" "section class 列"

# === folio-a405: raw xref graft の per-shape MK (essence/caption/figcaption/td の 4 形) ===
# ★per-shape で撃つ理由: raw 経路 (essence_rich/caption_rich/cells_rich) の allowlist abort・xref drop・href 改竄 (tag-strip
#   退化封鎖)・位置固定・esc 既定非回帰を、 4 形ごとに独立 isolate する。 1 instance の実弾は構造差のある instance の穴を証明しない。
# --- assemble tokenizer abort (contract mutation → validate_rich_inline が生成前 fail-closed・silent esc fallback 禁止) ---
# RX1. ★essence_rich field に allowlist 外 tag (div) → tokenizer abort。
cp "$BASE" "$TMP/rx1.yaml"; yq -i '(.sections[] | select(.id=="s2")).essence = "raw test <div>bad</div>"' "$TMP/rx1.yaml"
expect_abort "RX1 ★essence_rich field の allowlist 外 tag (div) を tokenizer abort" "$TMP/rx1.yaml" "allowlist 外の markup"
# RX2. ★essence_rich field に href 無し <a> → abort (raw field の a は href 必須・href 無し例示 a の誤混入封鎖・folio-a405 追加検査)。
cp "$BASE" "$TMP/rx2.yaml"; yq -i '(.sections[] | select(.id=="s2")).essence = "raw test <a>no-href</a>"' "$TMP/rx2.yaml"
expect_abort "RX2 ★essence_rich field の href 無し <a> を tokenizer abort (anchor-without-href)" "$TMP/rx2.yaml" "allowlist 外の markup"
# RX3. ★caption_rich field に on*= 属性 → abort (event handler・quoting 形に依らず属性名 allowlist で落ちる)。
cp "$BASE" "$TMP/rx3.yaml"; yq -i '(.sections[].blocks[]? | select(.caption_rich==true) | .caption) |= "raw <span onclick=\"x\">y</span>"' "$TMP/rx3.yaml"
expect_abort "RX3 ★caption_rich field の on*= 属性を tokenizer abort (event handler)" "$TMP/rx3.yaml" "allowlist 外の markup"
# --- verify FAIL: xref drop / href 改竄 (tag-strip 退化封鎖) を 4 形で per-shape ---
# RX4. ★essence xref (P-13 §2 sec-se) drop → human 層 census 10 で FAIL (essence shape)。
cp "$TMP/base-filled.html" "$TMP/rx4.html"
perl -0777 -i -pe 'our $n; $n += s{<a class="xref" href="\./constitution\.html#p-13"[^>]*>P-13</a>}{P-13}g; END { exit($n?0:9) }' "$TMP/rx4.html" \
  || ng "RX4 P-13 drop mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX4 ★essence xref (P-13) drop を human 層 xref census が捕捉" "$TMP/rx4.html" "human 層 xref census"
# RX5. ★caption xref (ADR-0034 §9.1) href 改竄 → table caption 逐語突合 FAIL (tag-strip 退化なら href 差を無視し PASS = 禁止)。
cp "$TMP/base-filled.html" "$TMP/rx5.html"
perl -0777 -i -pe 'our $n; $n += s{(<a class="xref" href=")\.\./decisions/ADR-0034-object-term-xref-system\.html(")}{${1}../decisions/ADR-9999-fake.html${2}}g; END { exit($n?0:9) }' "$TMP/rx5.html" \
  || ng "RX5 ADR-0034 href 改竄 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX5 ★caption xref (ADR-0034) href 改竄を table caption 逐語突合が捕捉 (tag-strip 退化封鎖)" "$TMP/rx5.html" "table caption 列"
# RX6. ★figcaption xref (ADR-0028 §10.2) href 改竄 → mermaid figcaption 逐語突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/rx6.html"
perl -0777 -i -pe 'our $n; $n += s{(<a class="xref" href=")\.\./decisions/ADR-0028-prose-gate-mechanization\.html(")}{${1}../decisions/ADR-9999-fake.html${2}}g; END { exit($n?0:9) }' "$TMP/rx6.html" \
  || ng "RX6 ADR-0028 href 改竄 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX6 ★figcaption xref (ADR-0028) href 改竄を mermaid figcaption 逐語突合が捕捉 (tag-strip 退化封鎖)" "$TMP/rx6.html" "mermaid figcaption 列"
# RX7. ★td xref (P-6 §10.2 7-gate cell) href 改竄 → table td 逐語突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/rx7.html"
perl -0777 -i -pe 'our $n; $n += s{(<a class="xref" href=")\./constitution\.html#p-6(")}{${1}./constitution.html#p-99${2}}g; END { exit($n?0:9) }' "$TMP/rx7.html" \
  || ng "RX7 P-6 href 改竄 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX7 ★td xref (P-6) href 改竄を table td 逐語突合が捕捉 (tag-strip 退化封鎖)" "$TMP/rx7.html" "table td 列"
# RX8. ★essence 位置固定 isolate: sec-se 内 P-13 の前に別 inline (code) を挿入 → census 11 は維持されるが位置固定 arm が FAIL
#   (別 field 重複 graft / sec-se 内位置ズレを census とは独立に捕捉する対称)。
cp "$TMP/base-filled.html" "$TMP/rx8.html"
perl -0777 -i -pe 'our $n; $n += s{(<section id="s2-directory".*?<p class="sec-se">)([^<]*<a class="xref" href="\./constitution\.html#p-13")}{${1}<code>x</code>${2}}s; END { exit($n?0:9) }' "$TMP/rx8.html" \
  || ng "RX8 §2 sec-se P-13 前 inline 挿入 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX8 ★essence per-section 位置固定: §2 sec-se 内 P-13 前への inline 挿入 (census 維持) を位置固定 arm が捕捉" "$TMP/rx8.html" "位置固定"
# --- esc 既定の非回帰 (raw は per-field opt-in・raw 未宣言 field は esc 経路のまま) ---
# RX9. ★raw 未宣言 field (heading) に HTML 注入 → 生成物で生 <b> でなく &lt;b&gt; に esc される (raw 経路が heading へ漏れない)。
cp "$BASE" "$TMP/rx9.yaml"; yq -i '(.sections[] | select(.id=="s2")).heading = "H <b>raw</b>"' "$TMP/rx9.yaml"
bash "$ASM" "$TMP/rx9.yaml" "$TMP/rx9.html" >/dev/null 2>&1 || ng "RX9 assemble 失敗 (esc 経路が壊れた)"
if grep -qF '&lt;b&gt;raw&lt;/b&gt;' "$TMP/rx9.html" && ! grep -qF '<b>raw</b>' "$TMP/rx9.html"; then
  ok "RX9 ★esc 既定の非回帰: raw 未宣言 field (heading) の HTML は esc される (raw 漏れ無し)"
else
  ng "RX9 ★heading の HTML が esc されず raw 漏れ (esc 既定が破れた = raw 経路の per-field opt-in 違反)"
fi
# RX10. ★RICH_FIELD_MIN 恒真 PASS 封鎖 floor の非回帰: 全 rich flag を剥がすと rich_field_values が空振りし検査対象 0<33 →
#   validate_rich_inline の被覆量下限割れで abort (floor 自身が壊れて 0 件検査を恒真 PASS する退行を封鎖・sweep 表/収束装置の
#   独立監査 = 0/0 恒真封鎖 doctrine)。 tokenizer bad の有無でなく「何件検査したか」を撃つ唯一の MK (RX1-9 は全て非空検査ゆえ floor 非駆動)。
cp "$BASE" "$TMP/rx10.yaml"
yq -i 'del(.sections[].essence_rich) | del(.sections[].blocks[]?.essence_rich) | del(.sections[].blocks[]?.caption_rich) | del(.sections[].blocks[]?.cells_rich)' "$TMP/rx10.yaml"
expect_abort "RX10 ★RICH_FIELD_MIN floor: 全 rich flag 剥離で検査対象 0<33 → 被覆量下限割れ abort (恒真 PASS 封鎖の非回帰)" "$TMP/rx10.yaml" "検査対象が"
# === folio-a405 errata-1 追加 MK (must-1 protocol-relative bypass / must-2 sub-se per-shape) ===
# RX11. ★href_ok protocol-relative bypass 封鎖 (must-1): raw field の href に // 始まり (protocol-relative) を入れると
#   fix 後の href_ok (path 先頭 / 抜き class) が URL-ALLOWLIST-VIOLATION で abort する (旧 char-class は // を ALLOW する fail-open)。
cp "$BASE" "$TMP/rx11.yaml"; yq -i '(.sections[] | select(.id=="s2")).essence = "x <a class=\"xref\" href=\"//evil.com/x.html\">bad</a>"' "$TMP/rx11.yaml"
expect_abort "RX11 ★protocol-relative href (//evil.com/x.html) を href_ok URL allowlist が abort (fail-open 封鎖)" "$TMP/rx11.yaml" "allowlist 外の markup"
# RX12. ★sub-se shape の href 改竄 (must-2a): §4.5 sub-se の REQ-VER-021 href-only 改竄 → 「subhead essence 列」逐語突合 arm が
#   FAIL (sec-se とは別 DOM shape=<p class="sub-se">・別 regex SUBHEAD_RE $3 ゆえ sec-se の RX5-7 では証明されない独立 kill)。
cp "$TMP/base-filled.html" "$TMP/rx12.html"
perl -0777 -i -pe 'our $n; $n += s{(<p class="sub-se">.*?<a class="xref" href=")\./verification\.html#req-ver-021(")}{${1}./verification.html#req-ver-999${2}}gs; END { exit($n?0:9) }' "$TMP/rx12.html" \
  || ng "RX12 §4.5 sub-se REQ-VER-021 href 改竄 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX12 ★sub-se xref (REQ-VER-021) href 改竄を subhead essence 列 逐語突合が捕捉 (sec-se と別 shape の独立 kill・tag-strip 退化封鎖)" "$TMP/rx12.html" "subhead essence 列"
# RX13. ★sub-se position の inline 挿入 (must-2b): §4 section + §4.5 sub-se 限定で P-8 前に inline (code) 挿入 → §4 位置固定 arm
#   FAIL (sec-se の RX8 と chk 共有だが sub-se 側からの独立 kill を証明・should-3 の tight 化が無いと素通りする)。
cp "$TMP/base-filled.html" "$TMP/rx13.html"
perl -0777 -i -pe 'our $n; $n += s{(<section id="s4-format".*?<p class="sub-se">)([^<]*<a class="xref" href="\./constitution\.html#p-8")}{${1}<code>x</code>${2}}s; END { exit($n?0:9) }' "$TMP/rx13.html" \
  || ng "RX13 §4.5 sub-se P-8 前 inline 挿入 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "RX13 ★sub-se position: §4.5 sub-se 内 P-8 前への inline 挿入を §4 位置固定 arm が捕捉 (sub-se 側独立 kill)" "$TMP/rx13.html" "位置固定"

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
perl -0777 -i -pe 's#<h1>folio rules — Layer 1 consumer universal rules</h1>#<h1>詐欺タイトル</h1>#' "$TMP/f16.html"
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
# 17n 独立 ceiling (wf_1ffcdb7c HIGH) が炙った floor gap: band() が <span class="kicker"> で可視 emit する
# §N/トピック ラベルは sections[].kicker 由来の決定的フィールドだが verify-spec が未突合だった。 §番号 swap /
# topic 取り違え / heading の §N との drift / 静的 band kicker drift を kicker 列突合が FAIL することを lock。
# F19. ★§番号 swap: §5↔§6 の kicker を入れ替え → 順序突合 FAIL (ZZSWAPZZ は doc に出ない安全な placeholder)。
cp "$TMP/base-filled.html" "$TMP/f19.html"
perl -0777 -i -pe 's#§5 / delta marker#ZZSWAPZZ#; s#§6 / EARS 記法#§5 / delta marker#; s#ZZSWAPZZ#§6 / EARS 記法#' "$TMP/f19.html"
expect_vfilled_fail "F19 ★kicker §番号 swap (§5↔§6) を kicker 列突合が捕捉" "$TMP/f19.html" "kicker"

# F20. ★topic 取り違え: §3 の kicker トピックを別章 (§2 ディレクトリ) のものへ → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f20.html"
perl -0777 -i -pe 's#§3 / 命名#§3 / ディレクトリ#' "$TMP/f20.html"
expect_vfilled_fail "F20 ★kicker topic 取り違え (§3 命名→ディレクトリ) を捕捉" "$TMP/f20.html" "kicker"

# F21. ★heading の §N との不整合: §6 の kicker を §9 へ (heading は「§6. EARS Notation Markup」) → 順序突合 FAIL。
cp "$TMP/base-filled.html" "$TMP/f21.html"
perl -0777 -i -pe 's#§6 / EARS 記法#§9 / EARS 記法#' "$TMP/f21.html"
expect_vfilled_fail "F21 ★kicker §N が heading §N と不整合 (§6→§9・heading §6) を捕捉" "$TMP/f21.html" "kicker"

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
# M1. ★機械層 prose テキスト改竄 → contract↔生成物 round-trip FAIL (件数不変・テキスト差のみ = round-trip 単独検出)。
cp "$TMP/base-filled.html" "$TMP/m1.html"
perl -0777 -i -pe 's#(<p data-component="spec-machine-prose" data-audience="machine">)#${1}ZZTAMPERZZ #' "$TMP/m1.html"
expect_vfilled_fail "M1 ★機械層 prose 改竄を contract↔生成物 round-trip が捕捉" "$TMP/m1.html" "機械層 不一致"

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
# ★folio-0x0k: row opener に id="<navigable id>" が入った形へ shape が変わったため撃ち直す + fired-guard (現版は guard 欠落で空撃ち vacuous-green)。
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

# M10. ★機械層 prose の二重 escape (live <code> が &lt;code&gt; 化) → round-trip FAIL (原本テキストと差)。
cp "$TMP/base-filled.html" "$TMP/m10.html"
perl -0777 -i -pe 's#(<p data-component="spec-machine-prose" data-audience="machine">[^<]*)<code>#${1}&lt;code&gt;#' "$TMP/m10.html"
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

# M13. ★機械層 note (aside) テキスト改竄 → contract↔生成物 round-trip FAIL (件数不変・最複雑 modality の content fidelity pin)。
#   note は nested <p>・<span class=term>・<a> を含む最も構造複雑な block 種ゆえ専用の改竄敵対が要る (prose M1 と対称)。
cp "$TMP/base-filled.html" "$TMP/m13.html"
perl -0777 -i -pe 's#(<aside data-component="spec-machine-note" data-audience="machine">)#${1}ZZNOTETAMPERZZ #' "$TMP/m13.html"
expect_vfilled_fail "M13 ★機械層 note 改竄を contract↔生成物 round-trip が捕捉" "$TMP/m13.html" "機械層 不一致"

# M14. ★機械層 note 脱落 (silent drop) → spec-machine-note 件数 + round-trip FAIL (prose M2 と対称)。
cp "$TMP/base-filled.html" "$TMP/m14.html"
perl -0777 -i -pe 's#<aside data-component="spec-machine-note" data-audience="machine">.*?</aside>\n##s' "$TMP/m14.html"
expect_vfilled_fail "M14 ★機械層 note 脱落を件数+round-trip が捕捉" "$TMP/m14.html" "spec-machine-note"

# M-bur-{a,b} ★folio-bur: machine fold summary の可視 echo 捏造 (fold 件数 intact のまま summary ラベル/per-fold 件数のみ改竄)
cp "$TMP/base-filled.html" "$TMP/mbura.html"
perl -0777 -i -pe 's#(<span class="mf-label">)§6\. EARS Notation Markup の地の文・運用説明・rationale#${1}§99. 捏造見出し の地の文・運用説明・rationale#' "$TMP/mbura.html"
expect_vfilled_fail "M-bur-a ★mf-label (fold summary heading) 捏造を順序突合で捕捉" "$TMP/mbura.html" "mf-label"
cp "$TMP/base-filled.html" "$TMP/mburb.html"
perl -0777 -i -pe 's#(<span class="mf-count">)12 件(</span>)#${1}99 件${2}#' "$TMP/mburb.html"
expect_vfilled_fail "M-bur-b ★mf-count (per-fold 件数) 捏造を順序突合で捕捉" "$TMP/mburb.html" "mf-count"
# M-bur-r2 ★folio-bur round-2 (ceiling-recursion): comment-hidden decoy (single-quote forged 可視 + double-quote 正値をコメント退避)
#   を quote-robust 占有数パリティで捕捉。
cp "$TMP/base-filled.html" "$TMP/mburr2.html"
perl -0777 -i -pe "s{<span class=\"mf-count\">12 件</span>}{<span class='mf-count'>99 件</span><!--<span class=\"mf-count\">12 件</span>-->}" "$TMP/mburr2.html"
# M-bur-r3-{a..d} ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 fix 自体の残存 fail-open。
#   (a) band h2 書換え (head -n NSEC 切詰の射程外) (b) NSEC 超位置への h2 注入 (総件数 pin 欠如)
#   (c) sec-se hide-twin (single-quote decoy・占有数パリティ未適用) (d) kicker hide-twin (同根)
cp "$TMP/base-filled.html" "$TMP/mburr3a.html"
perl -0777 -i -pe "s{<h2>rules は照会の終端ではない — 原則・ADR・検証へ前方照会する</h2>}{<h2>FABRICATED_BAND_H2_詐欺</h2>}" "$TMP/mburr3a.html"
expect_vfilled_fail "M-bur-r3-a ★band h2 書換えを静的 band リテラル突合で捕捉" "$TMP/mburr3a.html" "heading 列"
cp "$TMP/base-filled.html" "$TMP/mburr3b.html"
perl -0777 -i -pe "s{</body>}{<h2>§NEW 緊急告知 本規約は無効 (捏造)</h2></body>}" "$TMP/mburr3b.html"
expect_vfilled_fail "M-bur-r3-b ★NSEC 超 h2 注入を総 h2 件数 pin で捕捉" "$TMP/mburr3b.html" "h2 総数"
cp "$TMP/base-filled.html" "$TMP/mburr3c.html"
perl -0777 -i -pe "s{(<p class=\"sec-se\">)}{<p class='sec-se'>DECOY_捏造要約</p>\${1}}" "$TMP/mburr3c.html"
cp "$TMP/base-filled.html" "$TMP/mburr3d.html"
perl -0777 -i -pe "s{(<span class=\"kicker\">)}{<span class='kicker'>§99 詐欺トピック (捏造)</span>\${1}}" "$TMP/mburr3d.html"
# M-bur-r4-{a..c} ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 占有数パリティの未横展開兄弟 (el-when / ears-legend-item /
#   cover-meta KV) への single-quote + comment-hidden hide-twin。 EARS 意味論凡例・表紙統計値の捏造を quote-robust 占有数で封鎖。
cp "$TMP/base-filled.html" "$TMP/mburr4a.html"
perl -0777 -i -pe "s#(<span class=\"el-when\">)([^<]*)(</span>)#<span class='el-when'>常に守らなくてよい(捏造)</span><!--\${1}\${2}\${3}-->#" "$TMP/mburr4a.html"
cp "$TMP/base-filled.html" "$TMP/mburr4b.html"
perl -0777 -i -pe "s#(<span data-component=\"ears-legend-item\" class=\"always\">)([^<]*)(</span>)#<span data-component='ears-legend-item' class='always'>異常時だけ守る(捏造)</span><!--\${1}\${2}\${3}-->#" "$TMP/mburr4b.html"
cp "$TMP/base-filled.html" "$TMP/mburr4c.html"
perl -0777 -i -pe "s#<span class=\"k\">章の数</span><span class=\"v\">([^<]*)</span>#<span class=\"k\">章の数</span><span class='v'>99 章(捏造)</span><!--<span class=\"k\">章の数</span><span class=\"v\">\$1</span>-->#" "$TMP/mburr4c.html"
# M-bur-r5-a ★folio-bur round-5 (ceiling-recursion R4 是正・new-category): round-4 occupancy/label pin は凡例バッジの *色クラス*
#   (EARS_CLASS[pattern] 由来の決定的フィールド) を未検証で、 class="always"→"forbid" 等で EARS型→色 対応を反転/均一化でき
#   occupancy 5/label 順を保ったまま素通った (独立 ceiling 実証)。 凡例色を要件バッジ色と内部整合させる色クラス列 pin で封鎖。
cp "$TMP/base-filled.html" "$TMP/mburr5a.html"
perl -0777 -i -pe 's{(<span data-component="ears-legend-item" class=")always(">)}{${1}forbid${2}}' "$TMP/mburr5a.html"
expect_vfilled_fail "M-bur-r5-a ★ears-legend 色クラス swap (always→forbid・occupancy/label intact) を色クラス列 pin で捕捉" "$TMP/mburr5a.html" "ears-legend 色クラス"
# M-bur-r6-{a..d} ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 が §5 block-content へ未到達だった占有数パリティを subhead/table/code/mermaid に追加。
#   count_attr_token は comment 内も数えるゆえ hide-twin (commented genuine) も additive decoy も占有 inflate で捕捉 (genuine spec の本文 comment は 0)。
cp "$TMP/base-filled.html" "$TMP/mburr6a.html"
perl -0777 -i -pe "s{(</body>)}{<div data-component='spec-subhead'><h3>FAKE-HEADING</h3><p class='sub-se'>FAKE</p></div>\${1}}" "$TMP/mburr6a.html"
cp "$TMP/base-filled.html" "$TMP/mburr6b.html"
perl -0777 -i -pe "s{(</body>)}{<pre data-component='spec-code'><code>FAKE-CODE</code></pre>\${1}}" "$TMP/mburr6b.html"
cp "$TMP/base-filled.html" "$TMP/mburr6c.html"
perl -0777 -i -pe "s{(<table data-component=\"spec-table\">)}{<!--<table data-component=\"spec-table\"></table>-->\${1}}" "$TMP/mburr6c.html"
cp "$TMP/base-filled.html" "$TMP/mburr6d.html"
perl -0777 -i -pe "s{(</body>)}{<figure data-component='spec-diagram'><figcaption>FAKE-FIGCAP</figcaption></figure>\${1}}" "$TMP/mburr6d.html"

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
  ok "M15 ★原本不在を verify-spec §11 が fail-closed FAIL (照合不能を素通さない)"
fi

# ============================================================================
# === 政策 A (folio-7wbn / ADR-0053 §2.6 rules arm) の敵対 test 3 群 ===
#   verify-spec.sh §10b の ★凍結 census (spec-origin/rules.frozen-census.txt) が「両側 contract 由来」の
#   §4/§5/§11 と独立な anchor として効いていることを red→green で固定する。
#   (a) CEN 群   = per-shape mutation-kill (各 census arm が実弾で [FAIL] に落ちる)。
#   (b) M-SELFCMP = SPEC_ORIGIN_HTML=mutated の ★自己比較でも census が生きる (ORIG 非消費の証明)。
#   (c) COLLAPSE  = extractor collapse で contract と生成物が ★同時退行しても census が捕捉する。
#   ★rules 非該当軸 (jq -S / JSON-LD folio:stakeholders) の MK は ★作らない (census arm ごと不在 = 空撃ち MK 禁止)。
# ============================================================================
# ★reason 照合は [FAIL] 行 anchor + fixed-string 2 段: census chk ラベルは [OK] 行にも出るため、 素の substring
#   照合では「別 gate の巻き添え FAIL + 当該 census は [OK]」を緑と誤判定する (false-pass)。
cen_mut() { # label perl-expr reason
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/cen.html"
  if diff -q "$TMP/base-filled.html" "$TMP/cen.html" >/dev/null; then
    ng "$1 (mutation が生成物を変えていない = ★空撃ち。 selector が実 DOM と不一致の疑い)"; return
  fi
  local out rc; out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then ok "$1"
  else ng "$1 (exit=$rc / [FAIL] 行に census reason '$3' 不発 = 当該 census arm 無効化の回帰)"; fi
}
# --- navigable id census (count / SET / D-* 混入) ---
cen_mut "CEN-id1 ★navigable id 1 個剥奪 (58→57) → census navigable id 総数 FAIL" \
  's# id="s5-delta"##' "census navigable id: 総数"
cen_mut "CEN-id2 ★id rename (req-ci-001→RENAMED・count 58 保存) → census id-rename SET FAIL (count census は素通る)" \
  's#id="req-ci-001"#id="req-ci-RENAMED"#' "census id-rename SET"
cen_mut "CEN-id3 ★生成物への D-* id 混入 (delta 印の anchor 集合汚染) を fail-closed 検査が捕捉" \
  's{(<span class="term")}{<span id="D-FAKE-1"></span>${1}}' "D-* id == 0"
# ★CEN-id4 (folio-7wbn 3 巡目 ceiling major fix): id の ★重複 は count / SET census が共に dedup 後を見るため
#   unique 58 を保存したまま素通っていた shape (実測 rc=0 / [FAIL] 行ゼロ)。 文書順 first-match の fragment 解決ゆえ
#   本文より前の空 複製 anchor は当該 id への全 xref を hijack する。 per-shape MK (剥奪 / rename / D-* 混入 に続く第 4 形状)。
cen_mut "CEN-id4 ★既存 id の複製注入 (unique 58 保存・anchor hijack) を重複 chk が FAIL" \
  's{(<body[^>]*>)}{${1}<div id="s5-delta"></div>}' "census navigable id: 重複 0"
# --- rich 資産 occurrence (per-shape: a.xref / span.term / ins.delta は DOM 形状が別クラス) ---
cen_mut "CEN-rich1 ★a.xref 1 個剥奪 (26→25) → census rich a.xref FAIL" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
cen_mut "CEN-rich2 ★span.term 1 個剥奪 (18→17) → census rich span.term FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
cen_mut "CEN-rich3 ★ins.delta 1 個剥奪 (1→0) → census rich ins|del.delta FAIL" \
  's#<ins class="delta"[^>]*>(.*?)</ins>#$1#s' "census rich: ins|del.delta"
cen_mut "CEN-rich4 ★delta-id rename (D-2026-05-28-001→D-RENAMED・count 1 保存) → census delta-id SET FAIL" \
  's#data-delta-id="D-2026-05-28-001"#data-delta-id="D-RENAMED"#g' "census delta-id SET"
# --- escape / double-escape ---
cen_mut "CEN-esc1 ★散文中の &lt;a class=\"xref\" literal 1 個潰し (1→0) → census escape FAIL" \
  's#&lt;a class="xref"#\&lt;a class="ZZDROP"#' "census escape"
cen_mut "CEN-esc2 ★人間層 <code> を二重 escape (&lt;code 0→1) → census double-escape &lt;code FAIL" \
  's#<code>([^<]*)</code>#\&lt;code\&gt;$1\&lt;/code\&gt;#' "census double-escape: &lt;code"
cen_mut "CEN-esc3 ★td 内 live <span> を二重 escape (&lt;span 19→20) → census double-escape &lt;span FAIL" \
  's#(<a class="cov-req"[^>]*>)<span\b([^>]*)>(.*?)</span>#${1}\&lt;span$2\&gt;$3\&lt;/span\&gt;#s' "census double-escape: &lt;span"
# --- generic inline (code/span) の人間層 region 別 occurrence ---
# ★rules の frozen 値は table-cell / caption が 0 ゆえ、 これらは ★注入 (0→1) 方向で撃つ (減らせない軸を
#   「MK が書けないから」と撤去すると人間層 table/caption への捏造 inline 混入が無被覆になる)。
cen_mut "CEN-gen1 ★pre 内 human <code> wrapper 剥奪 (rest 9→8) → census generic <code> rest FAIL" \
  's#(<pre[^>]*>)<code>(.*?)</code>#${1}${2}#s' "census generic: 人間層 <code> rest"
cen_mut "CEN-gen2 ★td へ <code> 注入 (table-cell 0→1) → census generic <code> table-cell FAIL (注入方向 teeth)" \
  's#(<td>)#${1}<code>ZZINJ</code>#' "census generic: 人間層 <code> table-cell"
cen_mut "CEN-gen3 ★figcaption へ <code> 注入 (caption 0→1) → census generic <code> caption FAIL (注入方向 teeth)" \
  's#(<figcaption>)#${1}<code>ZZINJ</code>#' "census generic: 人間層 <code> caption"
cen_mut "CEN-gen4 ★td 内 <span> wrapper 剥奪 (table-cell 7→6) → census generic <span> table-cell FAIL" \
  's#(<a class="cov-req"[^>]*>)<span\b[^>]*>(.*?)</span>#${1}${2}#s' "census generic: 人間層 <span> table-cell"
cen_mut "CEN-gen5 ★figcaption へ <span> 注入 (caption 0→1) → census generic <span> caption FAIL (注入方向 teeth)" \
  's#(<figcaption>)#${1}<span>ZZINJ</span>#' "census generic: 人間層 <span> caption"
# --- 空撃ち検査 (恒真 FAIL の封鎖): 無改変 baseline が上記 census 群で FAIL しないこと ---
#   これが無いと verify が何を食わせても FAIL する状態でも CEN 群は全て緑になる。
if bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" >/dev/null 2>&1; then
  ok "CEN-z ★空撃ち検査: 無改変 baseline は verify PASS = CEN 群の FAIL は mutation 由来"
else
  ng "CEN-z 無改変 baseline が verify FAIL (恒真 FAIL ゆえ CEN 群が無意味。 環境要因を切り分けること)"
fi

# === M-SELFCMP. ★本番自己比較 MK: SPEC_ORIGIN_HTML=mutated_html でも frozen census が依然 FAIL する ===
#   政策 A の核心 — 旧「相対 parity」なら c_xref(ORIG)==c_xref(HTML)==25 で vacuous PASS したが、
#   frozen 26 vs 生成物 25 で FAIL する。 flip 後に canonical が生成物へ置換され ORIG==生成物 になる本番条件を
#   SPEC_ORIGIN_HTML=mutated で模す (ORIG 非消費の実証)。
selfcmp_mut() { # label perl-expr reason
  perl -0777 -pe "$2" "$TMP/base-filled.html" > "$TMP/selfcmp.html"
  if diff -q "$TMP/base-filled.html" "$TMP/selfcmp.html" >/dev/null; then
    ng "M-SELFCMP $1 (mutation 空撃ち)"; return
  fi
  local out rc; out="$(SPEC_ORIGIN_HTML="$TMP/selfcmp.html" bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/selfcmp.html" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && printf '%s\n' "$out" | grep -F -- "$3" | grep -qF -- '[FAIL]'; then ok "M-SELFCMP $1"
  else ng "M-SELFCMP $1 (SPEC_ORIGIN_HTML=mutated 自己比較で census が [FAIL] 行に無い rc=$rc / reason '$3' 不発 = 相対 parity 恒真化の回帰)"; fi
}
selfcmp_mut "★a.xref 1 個剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census FAIL (自己比較恒真化の封鎖)" \
  's#<a class="xref"[^>]*>(.*?)</a>#$1#s' "census rich: a.xref"
selfcmp_mut "★span.term 1 個剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census FAIL" \
  's#<span class="term" data-term="[^"]*"[^>]*>(.*?)</span>#$1#s' "census rich: span.term"
selfcmp_mut "★pre 内 human <code> wrapper 剥奪 + SPEC_ORIGIN_HTML=mutated でも frozen census generic FAIL" \
  's#(<pre[^>]*>)<code>(.*?)</code>#${1}${2}#s' "census generic: 人間層 <code> rest"

# === CEN-cmt. ★HTML コメント laundering (parser-differential) の封鎖 ===
#   census の regex counter が ★コメント内のタグ様文字列 を live として数えると、 政策A の【唯一の独立 anchor】が
#   edit-SSoT (contract.machine_blocks[].html は raw 出力) 側から水増しできてしまう:
#     live a.xref を 1 個失っても `<!-- <a class="xref"></a> -->` を 1 個足せば凍結 26 へ復元でき COLLAPSE-2 が破れる。
#   ★両方向 (deflate laundering / inflate false-FAIL) を撃つ: 数え漏らしと数え過ぎは別の失効モード。
CEN_DECOY='<!-- decoy: <a class="xref" href="#x">z</a> <span class="term" data-term="z">z</span> <ins class="delta" data-delta-id="D-ZZ-1">z</ins> <code>z</code> <div id="ZZDECOY"></div> &lt;a class="xref" &lt;code &lt;span -->'
# (1) deflate: live 1 個剥奪 + コメント decoy 1 個で凍結値へ「復元」しても census は FAIL し続けること。
cen_mut "CEN-cmt1 ★a.xref 剥奪 + コメント decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_DECOY}" "census rich: a.xref"
cen_mut "CEN-cmt2 ★span.term 剥奪 + コメント decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_DECOY}" "census rich: span.term"
# (2) inflate: 正当な HTML コメント (タグ様文字列を含む) を足しただけでは ★§10b census 群 が動かないこと。
#   ★assert は verify 全体の PASS ではなく ★census 行 ([FAIL] 直後のラベルが "census " で始まる = §10b 固有) に
#   絞る: 同 decoy は §10b 外の arm (self-anchor 整合 / human 層 xref floor) を落とすが、 それらは本 finding の
#   対象外かつ ★fail-closed 方向 (偽 FAIL) の別欠陥ゆえ本 case で conflate しない (別 bead へ handoff)。
perl -0777 -pe "s{(<body[^>]*>)}{\$1$CEN_DECOY}" "$TMP/base-filled.html" > "$TMP/cen-cmt3.html"
if diff -q "$TMP/base-filled.html" "$TMP/cen-cmt3.html" >/dev/null; then
  ng "CEN-cmt3 ★decoy 注入が空撃ち (<body> opener の記法変化の疑い)"
else
  c3_out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen-cmt3.html" 2>&1)"
  c3_bad="$(printf '%s\n' "$c3_out" | grep -E '^[[:space:]]*\[FAIL\][[:space:]]+census ' | head -3)"
  c3_okn="$(printf '%s\n' "$c3_out" | grep -cE '^[[:space:]]*\[OK\][[:space:]]+census ')"
  if [[ -z "$c3_bad" && "$c3_okn" -ge 10 ]]; then
    ok "CEN-cmt3 ★コメント内タグ様文字列は §10b census を inflate しない (census 行 $c3_okn 本すべて [OK]・偽 FAIL 封鎖)"
  else
    ng "CEN-cmt3 ★コメント注入で census が動いた (census 行を live 計数 = parser-differential 回帰 / [OK] 数 $c3_okn): $c3_bad"
  fi
fi

# === CEN-attr. ★属性値 laundering (parser-differential の残余) の封鎖 ===
#   CEN-cmt が塞いだのは comment / script / style ★本体 のみで、 ★属性値 は raw byte として残る。 census 計数が
#   naive regex なら「単引用符属性の中に書いたタグ様文字列」を live 要素として数えるため、 CEN-cmt と ★同一クラス の
#   laundering が開いたままになる (folio-7wbn 2 巡目 ceiling major):
#     `<div data-launder='<a class="xref" href="#z">z</a>'>`         → a.xref を +1 (凍結 26 を復元)
#     `<div data-launder='<section id="s5-delta"></section>'>`       → id count 58 と id SET を ★同時に 復元 (CEN-id1/id2 が破れる)
#   到達性は CEN-cmt と同じ (contract.machine_blocks[].html は raw 出力・extractor は原本 inner HTML を逐語 capture)。
#   ★両方向 (deflate laundering / inflate false-FAIL) を撃つ。 ★id 軸を必ず含める (count + SET の同時復元が最悪形)。
CEN_ATTR_DECOY="<div data-launder='<a class=\"xref\" href=\"#z\">z</a> <span class=\"term\" data-term=\"z\">z</span> <ins class=\"delta\" data-delta-id=\"D-ZZ-1\">z</ins> <section id=\"s5-delta\"></section> <section id=\"req-ci-001\"></section> <code>z</code> <span>z</span>'></div>"
# (1) deflate: live 1 個剥奪 + ★属性 decoy で凍結値へ「復元」しても census は FAIL し続けること。
cen_mut "CEN-attr1 ★a.xref 剥奪 + 単引用符属性 decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census rich: a.xref"
cen_mut "CEN-attr2 ★span.term 剥奪 + 属性 decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census rich: span.term"
cen_mut "CEN-attr3 ★id 剥奪 (58→57) + 属性 decoy で count 復元を狙う laundering を census 総数が FAIL" \
  "s{ id=\"s5-delta\"}{}; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census navigable id: 総数"
cen_mut "CEN-attr4 ★id rename + 属性 decoy で SET 復元を狙う laundering を census id-rename SET が FAIL" \
  "s{id=\"req-ci-001\"}{id=\"req-ci-RENAMED\"}; s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "census id-rename SET"
# (2) inflate: 正当な単引用符属性 (タグ様文字列を含む) を足しただけでは ★§10b census 群 が動かないこと。
#   ★assert は CEN-cmt3 と同型に census 行のみへ絞る (§10b 外の arm の巻き添えは本 finding の対象外)。
perl -0777 -pe "s{(<body[^>]*>)}{\$1$CEN_ATTR_DECOY}" "$TMP/base-filled.html" > "$TMP/cen-attr5.html"
if diff -q "$TMP/base-filled.html" "$TMP/cen-attr5.html" >/dev/null; then
  ng "CEN-attr5 ★decoy 注入が空撃ち (<body> opener の記法変化の疑い)"
else
  a5_out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen-attr5.html" 2>&1)"
  a5_bad="$(printf '%s\n' "$a5_out" | grep -E '^[[:space:]]*\[FAIL\][[:space:]]+census ' | head -3)"
  a5_okn="$(printf '%s\n' "$a5_out" | grep -cE '^[[:space:]]*\[OK\][[:space:]]+census ')"
  if [[ -z "$a5_bad" && "$a5_okn" -ge 10 ]]; then
    ok "CEN-attr5 ★属性値内タグ様文字列は §10b census を inflate しない (census 行 $a5_okn 本すべて [OK]・偽 FAIL 封鎖)"
  else
    ng "CEN-attr5 ★属性 decoy で census が動いた (属性値を live 計数 = parser-differential 回帰 / [OK] 数 $a5_okn): $a5_bad"
  fi
fi

# === CEN-tpl. ★非描画 subtree (<template>) laundering の封鎖 ===
#   CEN-cmt (comment) / CEN-attr (属性値) と ★同一クラス の第 3 vector (folio-7wbn 3 巡目 ceiling major)。
#   <template> の内容は browser が描画しない = live 資産でないのに census が数えていたため、 live な a.xref を
#   1 個失っても `<template><a class="xref">z</a></template>` を 1 個足すだけで凍結 26 が [OK] へ ★復元 され、
#   COLLAPSE-2 が守る性質 (両側同時退行を独立 anchor が捕捉する) が同じ手で破れた (実測再現済 → 修正済)。
#   ★element 軸 (a.xref / span.term / id) と ★text 軸 (escape literal) の両方に decoy を積み、 ★両方向 を撃つ。
CEN_TPL_DECOY='<template><a class="xref" href="#z">z</a><span class="term" data-term="z">z</span><ins class="delta" data-delta-id="D-ZZ-1">z</ins><section id="s5-delta"></section><section id="req-ci-001"></section><code>z</code><span>z</span>&lt;a class="xref" &lt;code &lt;span</template>'
# (1) deflate: live 1 個剥奪 + <template> decoy で凍結値へ「復元」しても census は FAIL し続けること。
cen_mut "CEN-tpl1 ★a.xref 剥奪 + <template> decoy による凍結値復元 (laundering) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census rich: a.xref"
cen_mut "CEN-tpl2 ★span.term 剥奪 + <template> decoy laundering を census が FAIL" \
  "s{<span class=\"term\" data-term=\"[^\"]*\"[^>]*>(.*?)</span>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census rich: span.term"
cen_mut "CEN-tpl3 ★id 剥奪 (58→57) + <template> decoy で count 復元を狙う laundering を census 総数が FAIL" \
  "s{ id=\"s5-delta\"}{}; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census navigable id: 総数"
cen_mut "CEN-tpl4 ★人間層 <code> 剥奪 + <template> decoy laundering を census generic が FAIL (h_inline 側の同 vector)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "census generic: 人間層 <code> rest"
# (2) inflate: 正当な <template> を足しただけでは ★§10b census 群 が動かないこと (偽 FAIL 封鎖・CEN-cmt3/attr5 と同型)。
perl -0777 -pe "s{(<body[^>]*>)}{\$1$CEN_TPL_DECOY}" "$TMP/base-filled.html" > "$TMP/cen-tpl5.html"
if diff -q "$TMP/base-filled.html" "$TMP/cen-tpl5.html" >/dev/null; then
  ng "CEN-tpl5 ★decoy 注入が空撃ち (<body> opener の記法変化の疑い)"
else
  t5_out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/cen-tpl5.html" 2>&1)"
  t5_bad="$(printf '%s\n' "$t5_out" | grep -E '^[[:space:]]*\[FAIL\][[:space:]]+census ' | head -3)"
  t5_okn="$(printf '%s\n' "$t5_out" | grep -cE '^[[:space:]]*\[OK\][[:space:]]+census ')"
  if [[ -z "$t5_bad" && "$t5_okn" -ge 10 ]]; then
    ok "CEN-tpl5 ★<template> 内の資産/タグ様文字列は §10b census を inflate しない (census 行 $t5_okn 本すべて [OK])"
  else
    ng "CEN-tpl5 ★<template> decoy で census が動いた (非描画 subtree を live 計数 = 回帰 / [OK] 数 $t5_okn): $t5_bad"
  fi
fi

# === SNAPPIN. ★snapshot 完全性 + census fail-closed の ★tracked 恒久 pin (folio-7wbn ceiling fix) ===
#   これらは以前 cell-local な untracked selftest にしか無く、 land 後に消える = 「保護されている」という
#   verify-spec.sh のコメントが shipped 状態で偽になっていた。 恒久 regression の所在は本 suite ゆえ移植する。
#   ★実態開示 (folio-7wbn 2 巡目 ceiling): 本 suite は現状 ★CI 未配線 (.github/workflows/ci.yml に
#   test-adversarial-spec.sh の step が無い・verification 側 test-adversarial-verification.sh とは非対称)。
#   よって本 SNAPPIN 群 / CEN 群 / M-SELFCMP / COLLAPSE は tracked だが ★自動実行されない (committed but dormant)。
#   ★★加えて (3 巡目 ceiling major): 検査対象である ★verify-spec.sh 本体にも CI 到達経路が無い
#   (ci.yml に step 無し / `folio validate` は呼ばない / `folio verify --type spec` は capability-registry の
#    `spec: wired: false` で fail-closed 拒否)。 ゆえに Leg B の必要配線は ★3 点 = (1) `census-guard.sh rules <base>`
#   の per-spec step / (2) 本 suite の step / (3) spec doc-type の wired 化 または verify-spec.sh の直接 CI step。
#   CI 配線は folio-7wbn Leg B (admin・ci.yml / capability-registry.yaml は本 cell の禁止面) で追加予定 —
#   それまでは手動実行時のみ発火する。 ★Leg B 完了までは本 arm を「保護確立」と扱わないこと。
SNAP_PIN="$SCRIPT_DIR/spec-origin/rules.origin.html"
CENSUS_PIN="$SCRIPT_DIR/spec-origin/rules.frozen-census.txt"
if [[ ! -f "$SNAP_PIN" || ! -f "$CENSUS_PIN" ]]; then
  ng "SNAPPIN ★前提喪失 (snapshot / census 不在): $SNAP_PIN / $CENSUS_PIN"
else
  # SNAPPIN-1: snapshot の sha256 が census header の宣言値と一致 (COLLAPSE 群が re-extract 元として消費する
  #   snapshot の完全性 pin。 post-flip canonical 等へ差し替えられると COLLAPSE-2 は緑のまま teeth だけ腐る)。
  decl_sha="$(grep -oE 'sha256 [0-9a-f]{64}' "$CENSUS_PIN" | head -1 | awk '{print $2}')"
  act_sha="$(sha256sum "$SNAP_PIN" | cut -d' ' -f1)"
  if [[ -n "$decl_sha" && "$decl_sha" == "$act_sha" ]]; then
    ok "SNAPPIN-1 ★snapshot sha256 == census header 宣言値 ($act_sha)"
  else
    ng "SNAPPIN-1 ★snapshot 完全性 pin 不成立 (宣言 '${decl_sha:-<none>}' / 実 $act_sha = COLLAPSE 前提の腐敗)"
  fi
  # SNAPPIN-2: 凍結 census 不在 → exit 2 fail-closed (silent skip の封鎖)。
  perl -0777 -pe 's{\$SCRIPT_DIR/spec-origin/rules\.frozen-census\.txt}{/nonexistent/rules.frozen-census.txt}' \
    "$VER" > "$PIN_VER"; chmod +x "$PIN_VER"
  if ! grep -qF '/nonexistent/rules.frozen-census.txt' "$PIN_VER"; then
    ng "SNAPPIN-2 ★census path 差し替えが空撃ち (FROZEN_CENSUS の記法変化の疑い)"
  else
    p2_out="$(bash "$PIN_VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; p2_rc=$?
    if [[ $p2_rc -eq 2 ]] && printf '%s\n' "$p2_out" | grep -qF '凍結 census 不在'; then
      ok "SNAPPIN-2 ★凍結 census 不在で exit 2 fail-closed (理由 anchor 一致・照合不能を素通さない)"
    else
      ng "SNAPPIN-2 ★census 不在が fail-closed でない (rc=$p2_rc / 理由不一致 = fail-open 回帰)"
    fi
  fi
  # SNAPPIN-3: 凍結 census の値 mutate → §10b census 消費 arm が [FAIL] (arm 実在の red→green pin)。
  #   ★tracked census を in-place で触らない (worktree 汚染回避): mutate copy を tmp に置き PIN_VER の path を向ける。
  sed -E 's/^FZ_XREF=[0-9]+$/FZ_XREF=99/' "$CENSUS_PIN" > "$TMP/census.mut.txt"
  perl -0777 -pe "s{\\\$SCRIPT_DIR/spec-origin/rules\\.frozen-census\\.txt}{$TMP/census.mut.txt}" "$VER" > "$PIN_VER"
  chmod +x "$PIN_VER"
  if ! grep -q '^FZ_XREF=99$' "$TMP/census.mut.txt" || ! grep -qF "$TMP/census.mut.txt" "$PIN_VER"; then
    ng "SNAPPIN-3 ★census mutate / path 差し替えが空撃ち"
  else
    p3_out="$(bash "$PIN_VER" --filled "$BASE_PROSE" "$BASE" "$TMP/base-filled.html" 2>&1)"; p3_rc=$?
    if [[ $p3_rc -ne 0 ]] && printf '%s\n' "$p3_out" | grep -F -- 'census rich: a.xref' | grep -qF -- '[FAIL]'; then
      ok "SNAPPIN-3 ★凍結 census 値 mutate (FZ_XREF→99) を §10b arm が [FAIL] 検出 (census 消費 arm 実在)"
    else
      ng "SNAPPIN-3 ★census 消費 arm 不在/無効 (rc=$p3_rc = 政策A anchor の false-green)"
    fi
  fi
  rm -f "$PIN_VER"
fi

# === COLLAPSE. ★extractor-collapse 敵対 test ===
# extract-rules-spec.sh の人間層 richplain() を関数レベルで plain() 相当へ collapse し、 ★extractor の pre-flip
# source (spec-origin/rules.origin.html = 現行 canonical は flip 済 = 生成物形ゆえ extractor の設計対象でない)
# から re-extract → collapsed contract → epoch 固定 assembler で assemble → collapsed 生成物。
# ★狙い: ① contract==生成物 の §4 + §11 round-trip が vacuous PASS する (両側同時退行で緑) ことを実演し、
#   ② frozen census (§10b) が collapsed 生成物を ★独立 anchor として FAIL させることを red→green 固定。
# ★rich 減少 assert だけの相対 parity (17==17 恒真) は禁止 — frozen literal (26) で撃つ。
# ★原本 no-touch: extract-rules-spec.sh は改変せず tmp copy を mutate する。
COLLAPSE_EXTRACT="$SCRIPT_DIR/../../scripts/extract-rules-spec.sh"
COLLAPSE_SNAP="$SCRIPT_DIR/spec-origin/rules.origin.html"
if [[ ! -f "$COLLAPSE_EXTRACT" || ! -f "$COLLAPSE_SNAP" ]]; then
  ng "COLLAPSE ★前提喪失 (extractor / snapshot 不在): $COLLAPSE_EXTRACT / $COLLAPSE_SNAP"
else
  # richplain() の lexical $s copy にタグ除去を注入 (関数レベル collapse・read-only $1 arg を壊さない)。
  #   ★"sub rich" 決め打ちは rules extractor に該当実体が無く空撃ち FAIL になる — 実体は "sub richplain" (my $probe=$s; を含む本体)。
  perl -0777 -pe 's{(sub richplain \{\n  my \(\$s\) = \@_; \$s //= "";)}{$1\n  \$s =~ s/<[^>]*>//g;}' \
    "$COLLAPSE_EXTRACT" > "$TMP/extract-collapsed.sh"
  if diff -q "$COLLAPSE_EXTRACT" "$TMP/extract-collapsed.sh" >/dev/null; then
    ng "COLLAPSE-0 ★richplain()→plain() collapse mutate が空撃ち (richplain sub の記法変化の疑い)"
  else
    ok "COLLAPSE-0 ★richplain()→plain() collapse mutate が適用された (関数レベル)"
    bash "$TMP/extract-collapsed.sh" "$COLLAPSE_SNAP" > "$TMP/collapsed.yaml" 2>/dev/null
    # ★epoch 固定 assembler: collapsed.yaml は凍結 snapshot の re-extract ゆえ rich field 件数は凍結 epoch 実測
    #   (33) を持つ。 live assembler の RICH_FIELD_MIN は現行契約の成長へ追随更新される (assembler 内規) ため、
    #   現行値のまま snapshot epoch の contract を assemble すると被覆量 assert が将来 構造発火する。 snapshot は
    #   非追随ゆえ epoch 定数は ★永久安定 — test-local copy の MIN だけを epoch 値へ pin する (本番 assembler の
    #   fail-closed は ★不変・本 test の検査対象は census (下流) であって MIN ではない)。
    #   ★MACHINE_FIELD_MIN / demoted / dl の pin は rules assembler に当該定数・型が不在ゆえ写さない (空撃ち sed 禁止)。
    sed -E -e 's/^RICH_FIELD_MIN=[0-9]+$/RICH_FIELD_MIN=33/' "$ASM" > "$EPOCH_ASM"
    if ! grep -q '^RICH_FIELD_MIN=33$' "$EPOCH_ASM"; then
      ng "COLLAPSE ★epoch assembler の MIN pin が不成立 (sed 空撃ち = 定数記法の変化疑い)"
    elif bash "$EPOCH_ASM" "$TMP/collapsed.yaml" "$TMP/collapsed.html" >/dev/null 2>&1; then
      cx_g="$(perl -CSD -0777 -ne 'my $n=0; while (/<a\b([^>]*)>/g){ my $a=$1; $n++ if $a =~ /class="(?:[^"]*\s)?xref/; } print $n;' "$TMP/collapsed.html")"
      col_out="$(bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; col_rc=$?
      # ① contract==生成物 vacuous PASS: 要件タプル (§4) と round-trip (§11) が [OK] (両側同時退行で緑)。
      tup_line="$(printf '%s\n' "$col_out" | grep -F '要件タプル' | head -1)"
      rt_line="$(printf '%s\n' "$col_out" | grep -F 'round-trip' | grep -F '機械層' | head -1)"
      if printf '%s' "$tup_line" | grep -qF '[OK]' && printf '%s' "$rt_line" | grep -qF '[OK]'; then
        ok "COLLAPSE-1 ★§4 要件タプル + §11 round-trip の vacuous PASS を実演 (contract==生成物・collapsed a.xref=$cx_g < frozen 26)"
      else
        ng "COLLAPSE-1 ★vacuous PASS の実演に失敗 (§4/§11 が [OK] でない = collapse が contract-vs-生成物 を割った)"
        echo "      [debug] §4: ${tup_line:-<none>}" >&2
        echo "      [debug] §11: ${rt_line:-<none>}" >&2
      fi
      # ② frozen census が collapsed 生成物を FAIL させる (独立 anchor・rich 減少 17<26)。
      if [[ $col_rc -ne 0 ]] && printf '%s\n' "$col_out" | grep -F 'census rich: a.xref' | grep -qF '[FAIL]'; then
        ok "COLLAPSE-2 ★frozen census が collapse を FAIL (§4/§11 vacuous PASS を独立 anchor が捕捉)"
      else
        ng "COLLAPSE-2 ★frozen census が collapse を捕捉できず (rc=$col_rc・vacuous PASS 未封鎖 = 政策A 失効)"
      fi
      # ③ 本番自己比較を模す: SPEC_ORIGIN_HTML=collapsed でも census が生きる (ORIG==生成物 でも frozen で FAIL)。
      sc_out="$(SPEC_ORIGIN_HTML="$TMP/collapsed.html" bash "$VER" "$TMP/collapsed.yaml" "$TMP/collapsed.html" 2>&1)"; sc_rc=$?
      if [[ $sc_rc -ne 0 ]] && printf '%s\n' "$sc_out" | grep -F 'census rich: a.xref' | grep -qF '[FAIL]'; then
        ok "COLLAPSE-3 ★SPEC_ORIGIN_HTML=collapsed の自己比較でも frozen census FAIL (ORIG 非消費の実証)"
      else
        ng "COLLAPSE-3 ★自己比較で census FAIL せず (rc=$sc_rc = census が ORIG を消費している回帰)"
      fi
    else
      ng "COLLAPSE ★collapsed contract の assemble に失敗 (genuine 再生成不能)"
    fi
  fi
fi

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_vprefill_pass "P1 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"
expect_vfilled_pass  "P2 健全 baseline は --filled verify PASS" "$TMP/base-filled.html"


# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
cp "$TMP/base-filled.html" "$TMP/r7s1.html"; perl -0777 -i -pe 's{</body>}{<div data-component="constraint-callout" class="rq-stmt">偽の制約(foreign marker 捏造)</div></body>}' "$TMP/r7s1.html"
cp "$TMP/base-filled.html" "$TMP/r7s2.html"; perl -0777 -i -pe 's{</body>}{<div class="spec-evil-novel">偽(novel marker 捏造)</div></body>}' "$TMP/r7s2.html"
cp "$TMP/base-filled.html" "$TMP/r7s3.html"; perl -0777 -i -pe 's{</body>}{<div data-component="constraint-callout">偽制約</div><div style="display:none">genuine 隠蔽</div></body>}' "$TMP/r7s3.html"
cp "$TMP/base-filled.html" "$TMP/r7s4.html"; perl -0777 -i -pe 's{</body>}{<div class="lab">偽ラベル(捏造)</div></body>}' "$TMP/r7s4.html"
cp "$TMP/base-filled.html" "$TMP/r7s5.html"; perl -0777 -i -pe 's{</body>}{<code><span class="rid">DECOY</span></code></body>}' "$TMP/r7s5.html"
cp "$TMP/base-filled.html" "$TMP/r7s6.html"; perl -0777 -i -pe 's{</body>}{<div data-component="approval-block">偽承認(捏造)</div></body>}' "$TMP/r7s6.html"

# === 数値文字参照 decode 変種 red pin (folio-5u3k・reason-gated) ===
# lib/verify-common.sh の decode widen (大文字 &#X / semicolon-less hex / semicolon-less decimal) が
# entity 偽装 class を可視 token へ decode し **占有検査** が捕捉することを pin する。
# 素の rc!=0 pin は novelty scan (class-token 機械的網羅) が decode 幅と無関係に suite を赤くするため
# green-before-and-after で masking される — 占有側の FAIL 行 ([FAIL] + label) を対で掴む (c5r.2 基準)。
# mutation-kill: 該当 helper の widen だけ narrow へ戻すと novelty (L44 decode 済) も占有も静か
# = verify PASS に転じて本 pin が赤くなる (selftest-folio-5u3k が unit 単位で全 4 site を kill)。
u3k_entity_pin() { # label decoy_html expected_fail_substring
  cp "$TMP/base.html" "$TMP/u3k.html"
  DECOY="$2" perl -0777 -i -pe 's{</h1>}{"</h1>" . $ENV{DECOY}}e' "$TMP/u3k.html"
  local out rc; out="$(bash "$VER" "$BASE" "$TMP/u3k.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (verify PASS = entity 偽装 class が素通り)"; return; fi
  if grep -F -- "$3" <<<"$out" | grep -q '\[FAIL\]'; then ok "$1"; else ng "$1 (FAIL は別理由 = 占有 decode 不発が novelty に masking されている)"; fi
}
u3k_entity_pin "U3K1 ★大文字 16進 entity class (&#X77;ho → who) を占有 vcount who が decode 捕捉" '<span class="&#X77;ho">x</span>' 'vcount who'
u3k_entity_pin "U3K2 ★semicolon-less 16進 entity class (&#x77ho → who) を占有 vcount who が decode 捕捉" '<span class="&#x77ho">x</span>' 'vcount who'
u3k_entity_pin "U3K3 ★semicolon-less 10進 entity class (&#119ho → who) を占有 vcount who が decode 捕捉" '<span class="&#119ho">x</span>' 'vcount who'

echo
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
# ===== census-count blocking arm conformance seed (folio-jmmk): 容器 block / machine list 部品件数の source DOM 静的照合 =====
# 空 data-component タグ注入で件数 +1 (excess) にし census-count arm が [FAIL] census-count: <token> で blocking 捕捉する
# ことを固定。 空 block ゆえ内容の順序値 chk (list items / code lines / cell / round-trip) は素通り = census-count arm が唯一
# anchor (sweep 分類表 folio-3d23【B2 占有pin sweep 成果物】)。 帰属 [FAIL] 行は census-count arm を外した mutant で消え
# = mutation-kill。 spec-machine-fold は verify-spec の mf-label/mf-count 順序値 chk が並存 (冗長=非対象) ゆえ seed も張らない。
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

if repro_pins "$VER" spec "$BASE" "$BASE_PROSE" "$ASM" "$INJ" --filled "$BASE_PROSE"; then ok "repro-build conformance (a-d) 全 pass"; else ng "repro-build conformance (a-d) 逸脱"; fi
echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
