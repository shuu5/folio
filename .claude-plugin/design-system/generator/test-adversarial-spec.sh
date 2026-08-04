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
  # ★reason 照合は [FAIL] 行 anchor (範型 test-adversarial-verification.sh errata-1 must-1 と同型)。 chk ラベルは
  #   ★PASS 時も [OK] 行に出力される ため、 単純 substring 一致だと「別 arm の巻き添え FAIL」でも期待 reason が
  #   [OK] 行で満たされ ★guard が inert になる (per-shape MK の主張が pin されない)。 reason は括弧/ドット等の
  #   regex metachar を含みうるため -E でなく fixed-string 2 段 (該当 reason を含む行のうち [FAIL] 行が在るか) で anchor する。
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
# ★ADR-0054 lockstep: chip 突合の label が (token,doc,role) → (token,doc,role,title) へ拡張されたため reason substring を再同期。
expect_vfilled_fail "F9 ★reference 可視 <b> のみ改竄 (attr 正) を vis 整合で捕捉" "$TMP/f9.html" "references: (token,doc,role,title)"

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
#   ★§N prefix は残す: PR24 で入れた heading_secnum / band_num の fail-closed guard (§N 形でない heading は abort) が
#   先に発火すると本 MK が「esc 検査」でなく「abort 検査」に化けて空撃ちになるため、 検査したい注入だけを heading 末尾へ足す。
cp "$BASE" "$TMP/rx9.yaml"; yq -i '(.sections[] | select(.id=="s2")).heading = "§2. H <b>raw</b>"' "$TMP/rx9.yaml"
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
# ★errata (folio-3zr4.2・expect_vfilled_fail の [FAIL] 行 anchor 化で ★露出した false record の是正):
#   旧 F14 の mutation は ★非 global の `s#flowchart TB#…#` で、 文書内で最初に一致するのは 人間層の
#   <pre class="mermaid"> ではなく ★機械層 aside (data-component="spec-machine-note" / data-audience="machine")
#   の中の <code>flowchart TB</code> だった (実測)。 ゆえに 実際に落ちていた arm は ★機械層 round-trip
#   (「contract↔生成物 機械層 不一致」) で、 本 case が主張する「mermaid source 行列」arm は ★[OK] のまま
#   だった — 旧 guard は ★[OK] 行の substring で満たされ ★inert (人間層 arm に mutation-kill が無かった)。
#   ★是正は additive: F14 を ★人間層 mermaid を狙う形へ向け直し (fired-guard 付き)、 旧形が ★実際に 提供して
#   いた機械層 round-trip の teeth は F14b として ★別 case で残す (teeth を 1 本も減らさない)。
cp "$TMP/base-filled.html" "$TMP/f14.html"
perl -0777 -i -pe 'our $n; $n += s#(<pre class="mermaid">)flowchart TB#${1}flowchart CAPTURED#; END { exit($n==1?0:9) }' "$TMP/f14.html" \
  || ng "F14 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F14 ★人間層 mermaid source 行改竄を捕捉 (mermaid source 行列 arm 単独)" "$TMP/f14.html" "mermaid source 行列"
# F14b. ★機械層 aside 内 <code>flowchart TB</code> の改竄 → ★機械層 round-trip FAIL (旧 F14 が実際に撃っていた向き)。
#   ★F14 と別 shape: 人間層 mermaid の source_lines 突合ではなく ★機械層 自由文の逐語 round-trip が唯一の検出源。
cp "$TMP/base-filled.html" "$TMP/f14b.html"
perl -0777 -i -pe 'our $n; $n += s#(<code>)flowchart TB(</code>)#${1}flowchart CAPTURED${2}#; END { exit($n==1?0:9) }' "$TMP/f14b.html" \
  || ng "F14b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "F14b ★機械層 aside 内 <code>flowchart TB</code> の改竄を機械層 round-trip が捕捉 (旧 F14 の実 teeth)" "$TMP/f14b.html" "機械層 不一致"

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
# ★ADR-0054 lockstep: 静的 band h2 が「§13. 上位文書への前方照会 — …」形へ変わったため mutation 対象 literal を再同期。
#   ★fired-guard を付す (旧 literal のまま残すと ★空撃ち で恒真 PASS になる = 本 FAIL が実際に検出した退行クラス)。
perl -0777 -i -pe 'our $n; $n += s{<h2>§13\. 上位文書への前方照会 — 原則・決定記録・検証仕様へつながる</h2>}{<h2>FABRICATED_BAND_H2_詐欺</h2>}; END { exit($n?0:9) }' "$TMP/mburr3a.html" \
  || ng "M-bur-r3-a mutation が発火せず (shape drift = 空撃ち)"
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

# --- inflate 方向の共通 helper (CEN-cmt3 / CEN-attr5 / CEN-tpl5 のインライン block を関数化・本 arm 実測 19 本) ---
#   ★3 形状 (bogus comment / 重複属性 / 自己閉じ template) の inflate case を手写しすると 1 本でも
#   条件を写し損ねた時点でその shape が ★恒真 PASS (vacuous-green) になるため、 判定を 1 箇所へ寄せる。
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
  if [[ -z "$bad" && -z "$miss" && "$okn" -ge 19 ]]; then
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
  if [[ -z "$bad" && -z "$miss" && "$okn" -ge 19 ]]; then
    ok "$lbl (census 行 $okn 本すべて [OK]・依存軸 4 本実在)"
  else
    ng "$lbl ★census が動いた/依存軸が消えた ([OK] 数 $okn / 依存軸欠落:$miss): $bad"
  fi
}


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
cen_inflate "CEN-cmt3 ★コメント内タグ様文字列は §10b census を inflate しない" "$CEN_DECOY"

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
cen_inflate "CEN-attr5 ★属性値内タグ様文字列は §10b census を inflate しない" "$CEN_ATTR_DECOY"

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
cen_inflate "CEN-tpl5 ★<template> 内の資産/タグ様文字列は §10b census を inflate しない" "$CEN_TPL_DECOY"

# --- CEN-tpl6/7/8. ★bogus comment 前置による <template> inert 除外の破壊 (folio-gt4s・rules arm へ port) ---
#   ★4 byte で per-shape MK 群が全滅した実例の pin。 census subject を strip_inert の出力 (live view) に置いた版では、
#   strip_inert の handle_comment が cut 終端を `s + len(data) + 7` (`<!--` 4 + `-->` 3 の決め打ち) で算出する一方、
#   Python html.parser は ★bogus comment `<!x>` (実長 4 byte) にも handle_comment(data='x') を発火するため、
#   計算長 8 で ★直後の live 4 byte を過剰削除した。 結果 `<!x><template>` → `plate>` となり ★<template> 開始タグが
#   破壊されて中身が live 化し、 CEN-tpl1..5 が封鎖したはずの laundering クラスが ★丸ごと再開通していた
#   (実測: base 8d4eeda では本 mutant が `census rich: a.xref == 凍結 26` を [OK] へ復元 = laundering 成立)。
#   ★対策は census subject を RAW $HTML へ戻すこと (census_dump / h_inline は共に実 HTML parser で comment /
#   script / style を非計数・<template> を除外済ゆえ strip_inert 前処理は不要どころか ★唯一の穴 だった)。
#   ★両方向を撃つ: tpl6 = inflate (前置しても census は動かない) / tpl7,8 = deflate (前置しても復元は封鎖され続ける)。
#   ★4 byte を足すだけで CEN-tpl1 の実弾が空砲化したので、 tpl7/8 は control 比較に依存せず ★`<!x>` 付きの側 が
#   FAIL することを直接 assert する (control は CEN-tpl1/tpl4 が担当)。 element 軸と text 軸を per-shape で撃つ。
CEN_BOGUS_TPL_DECOY="<!x>$CEN_TPL_DECOY"
cen_inflate 'CEN-tpl6 ★bogus comment <!x> 前置でも <template> 内は §10b census を inflate しない' "$CEN_BOGUS_TPL_DECOY"
cen_mut "CEN-tpl7 ★a.xref 剥奪 + <!x> 前置 <template> decoy による凍結値復元 (inert 除外の 4 byte 破壊) を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_BOGUS_TPL_DECOY}" "census rich: a.xref"
cen_mut "CEN-tpl8 ★人間層 <code> 剥奪 + <!x> 前置 <template> decoy laundering を census generic が FAIL (h_inline 側の同 vector)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_BOGUS_TPL_DECOY}" "census generic: 人間層 <code> rest"

# --- CEN-dupattr. ★重複属性 last-wins による data-audience laundering (folio-gt4s・rules arm へ port) ---
#   HTML Standard では重複属性は ★最初 が勝つ (2 つ目以降は parse error として破棄) ため
#   `<div data-audience="machine" data-audience="human">` を browser は ★機械層 と解釈する。 h_inline が
#   `dict(attrs)` (= last-wins) だと ★人間層 として計上し、 「live な人間層 <code> を 1 個剥奪 → 重複属性で
#   偽の人間層資産を 1 個注入」で凍結値へ復元できた (CEN-tpl4 / M18 が守る性質が同一クラスの手で破れる)。
#   census_dump は既に first-wins ゆえ ★同一 walk 内の非対称 だった (実測: 是正前 h_inline=1 / 是正後 0)。 両方向を撃つ。
CEN_DUPATTR_DECOY='<div data-audience="machine" data-audience="human"><code>z</code></div>'
cen_mut "CEN-dupattr1 ★人間層 <code> 剥奪 + 重複属性 (machine→human 上書き) decoy による復元を census generic が FAIL" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_DUPATTR_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-dupattr2 ★重複属性 data-audience の ★最初 (machine) が勝ち §10b census を inflate しない" "$CEN_DUPATTR_DECOY"

# --- CEN-tplsc. ★自己閉じ形 <template/> による inert 除外の 1 byte 迂回 (folio-gt4s・両軸) ---
#   Python html.parser は `<template/>` に対し handle_starttag ではなく ★handle_startendtag を発火する。
#   census_dump / h_inline が本 hook で template を stack へ push しないと inert 区間にならず、
#   ★`/` 1 文字で CEN-tpl 群の per-shape MK が全滅する (実測: base 8d4eeda で `census rich: a.xref` が [OK] 26 へ復元)。
#   HTML Standard では ★非 void 要素の trailing solidus は無視され `<template/>` は template を ★開く (中身は inert)。
#   ★element 軸 (census_dump) と ★text/inline 軸 (h_inline) は別実装ゆえ ★両軸を per-shape で撃つ (片軸は残穴)。
#   ★push を template のみ に絞る最小形が要件: `not in VOID` 相当だと canonical の自己閉じ SVG (`<path/>` 等) が
#   閉じられず stack を汚染し region / inert 判定を壊す (別クラスの誤計数)。 ★その回帰のうち CEN-tplsc4 が
#   実際に撃てるのは ★text/inline 軸 のみ (element 軸は naive 形にしても差が出ず ★恒真 PASS だった = errata-1
#   MUST-6)。 element 軸の最小形要件は ★MINFORM 節の静的 fixed-string pin が担う。
CEN_TPLSC_DECOY='<template/><code>z</code></template>'
CEN_TPLSC_EL_DECOY='<template/><a class="xref" href="#z">z</a><span class="term" data-term="z">z</span><ins class="delta" data-delta-id="D-ZZ-1">z</ins><section id="s5-delta"></section><section id="req-ci-001"></section><code>z</code><span>z</span>&lt;a class="xref" &lt;code &lt;span</template>'
cen_mut "CEN-tplsc1 ★人間層 <code> 剥奪 + ★自己閉じ <template/> decoy による復元を census generic が FAIL (text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_TPLSC_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-tplsc2 ★自己閉じ <template/> 内の資産/タグ様文字列は §10b census を inflate しない (両軸)" "$CEN_TPLSC_EL_DECOY"
cen_mut "CEN-tplsc3 ★a.xref 剥奪 + ★自己閉じ <template/> decoy による凍結値復元を census が FAIL (★element 軸)" \
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
cen_mut "CEN-head1 ★<head> への既存 id 複製注入を census が検出 (★element 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1<div id=\"req-ci-001\"></div>}" "census navigable id: 重複 0"
cen_mut "CEN-head2 ★<head> への escape literal 注入を census が検出 (★escape 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1&lt;span }" "census double-escape: &lt;span"
cen_mut "CEN-head3 ★<head> への人間層 <code> 注入を census が検出 (★text/inline 軸が head を視野に入れている)" \
  "s{(<head[^>]*>)}{\$1<code>z</code>}" "census generic: 人間層 <code> rest"

# --- CEN-tplesc. ★stray end tag による inert subtree の巻き取り (folio-gt4s ceiling 2 巡目 major fix・両軸) ---
#   handle_endtag の素朴な `del self.stack[i:]` は ★祖先 に一致する end tag でも template を巻き取って外すため、
#   `<template></div>...</template>` のように ★不一致 end tag を 1 本置くだけで inert 区間が解除され、
#   中身 (browser では ★非描画) が live 計上された。 HTML5 の in-template 挿入モードでは不一致 end tag は
#   parse error として ★無視 され template は開いたまま。 ★element 軸 / text 軸 / 自己閉じ形 を per-shape で撃つ。
CEN_TPLESC_DECOY='<div data-audience="machine"><template></div><a class="xref" href="#z">z</a><code>z</code></template></div>'
CEN_TPLESC_SC_DECOY='<div data-audience="machine"><template/></div><a class="xref" href="#z">z</a><code>z</code></template></div>'
cen_mut "CEN-tplesc1 ★a.xref 剥奪 + stray </div> で <template> を巻き取る decoy の凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPLESC_DECOY}" "census rich: a.xref"
cen_mut "CEN-tplesc2 ★人間層 <code> 剥奪 + 同 decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_TPLESC_DECOY}" "census generic: 人間層 <code> rest"
cen_mut "CEN-tplesc3 ★自己閉じ <template/> + stray </div> 形 (別 shape) の element 軸復元を census が FAIL" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_TPLESC_SC_DECOY}" "census rich: a.xref"
cen_inflate "CEN-tplesc4 ★stray end tag 入り <template> は §10b census を inflate しない (偽 FAIL 封鎖・両軸)" "$CEN_TPLESC_DECOY"

# --- CEN-scsc. ★自己閉じ <script/> による raw text 区間の live 計上 (folio-gt4s ceiling 2 巡目 major fix・両軸) ---
#   通常形 <script> は html.parser の CDATA mode が中身をタグとして emit しないため実害が無かったが、
#   ★自己閉じ形 `<script/>` は handle_startendtag 発火ゆえ CDATA mode に入らず、 browser が `</script>` まで
#   raw text (= ★非描画) 扱いする区間を census が live 計上していた (`/` 1 文字の迂回・CEN-tplsc と同一クラス)。
#   ★canonical に自己閉じ script/style は 0 件 (grep verified) ゆえ是正の副作用なし。 両軸を per-shape で撃つ。
CEN_SCSC_EL_DECOY='<div data-audience="machine"><script/><a class="xref" href="#z">z</a></script></div>'
CEN_SCSC_TX_DECOY='<script/><code>z</code></script>'
cen_mut "CEN-scsc1 ★a.xref 剥奪 + 自己閉じ <script/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1$CEN_SCSC_EL_DECOY}" "census rich: a.xref"
cen_mut "CEN-scsc2 ★人間層 <code> 剥奪 + 自己閉じ <script/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1$CEN_SCSC_TX_DECOY}" "census generic: 人間層 <code> rest"
cen_inflate "CEN-scsc3 ★自己閉じ <script/> 区間は §10b census を inflate しない (偽 FAIL 封鎖・element 軸)" "$CEN_SCSC_EL_DECOY"


# --- CEN-rt. ★raw text / RCDATA 要素の ★自己閉じ形 による inert 迂回 (folio-gt4s errata-1 MUST-3・両軸) ---
#   INERT を {'template','script','style'} と ★手書き列挙 した版は partial-enumeration trap だった:
#   textarea / title / xmp / iframe / noembed / noframes の自己閉じで ★同一クラスが再開通した (実測)。
#   是正は集合を ★parser 自身から導出すること (HTMLParser.CDATA_CONTENT_ELEMENTS | RCDATA_CONTENT_ELEMENTS):
#   parser の認識と census の inert 判定が構造的に同期し、 列挙漏れが原理的に生じない。
#   ★本群は「導出集合が痩せたら赤くなる」検出器。 ★1 tag の実弾は別 tag の穴を証明しない ゆえ ★全 tag ×
#   element 軸 / text-inline 軸 を per-shape で撃つ (deflate = 剥奪 + decoy 復元が封鎖され続けること)。
cen_mut "CEN-rt-script-el ★a.xref 剥奪 + 自己閉じ <script/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><script/><a class=\"xref\" href=\"#z\">z</a></script></div>}" "census rich: a.xref"
cen_mut "CEN-rt-style-el ★a.xref 剥奪 + 自己閉じ <style/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><style/><a class=\"xref\" href=\"#z\">z</a></style></div>}" "census rich: a.xref"
cen_mut "CEN-rt-xmp-el ★a.xref 剥奪 + 自己閉じ <xmp/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><xmp/><a class=\"xref\" href=\"#z\">z</a></xmp></div>}" "census rich: a.xref"
cen_mut "CEN-rt-iframe-el ★a.xref 剥奪 + 自己閉じ <iframe/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><iframe/><a class=\"xref\" href=\"#z\">z</a></iframe></div>}" "census rich: a.xref"
cen_mut "CEN-rt-noembed-el ★a.xref 剥奪 + 自己閉じ <noembed/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><noembed/><a class=\"xref\" href=\"#z\">z</a></noembed></div>}" "census rich: a.xref"
cen_mut "CEN-rt-noframes-el ★a.xref 剥奪 + 自己閉じ <noframes/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><noframes/><a class=\"xref\" href=\"#z\">z</a></noframes></div>}" "census rich: a.xref"
cen_mut "CEN-rt-textarea-el ★a.xref 剥奪 + 自己閉じ <textarea/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><textarea/><a class=\"xref\" href=\"#z\">z</a></textarea></div>}" "census rich: a.xref"
cen_mut "CEN-rt-title-el ★a.xref 剥奪 + 自己閉じ <title/> decoy による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<div data-audience=\"machine\"><title/><a class=\"xref\" href=\"#z\">z</a></title></div>}" "census rich: a.xref"
cen_mut "CEN-rt-script-tx ★人間層 <code> 剥奪 + 自己閉じ <script/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<script/><code>z</code></script>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-style-tx ★人間層 <code> 剥奪 + 自己閉じ <style/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<style/><code>z</code></style>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-xmp-tx ★人間層 <code> 剥奪 + 自己閉じ <xmp/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<xmp/><code>z</code></xmp>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-iframe-tx ★人間層 <code> 剥奪 + 自己閉じ <iframe/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<iframe/><code>z</code></iframe>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-noembed-tx ★人間層 <code> 剥奪 + 自己閉じ <noembed/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<noembed/><code>z</code></noembed>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-noframes-tx ★人間層 <code> 剥奪 + 自己閉じ <noframes/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<noframes/><code>z</code></noframes>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-textarea-tx ★人間層 <code> 剥奪 + 自己閉じ <textarea/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<textarea/><code>z</code></textarea>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rt-title-tx ★人間層 <code> 剥奪 + 自己閉じ <title/> decoy による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<title/><code>z</code></title>}" "census generic: 人間層 <code> rest"

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
cen_mut "CEN-nest1 ★a.xref 剥奪 + <template><script/></template> による凍結値復元を census が FAIL (★element 軸)" \
  "s{<a class=\"xref\"[^>]*>(.*?)</a>}{\$1}s; s{(<body[^>]*>)}{\$1<template><script/></template><a class=\"xref\" href=\"#z\">z</a>}" "census rich: a.xref"
cen_mut "CEN-nest2 ★人間層 <code> 剥奪 + 同 vector による復元を census generic が FAIL (★text/inline 軸)" \
  "s{(<pre[^>]*>)<code>(.*?)</code>}{\${1}\${2}}s; s{(<body[^>]*>)}{\$1<template><script/></template><code>z</code>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-nest3 ★内側 tag 違い <template><textarea/></template> 形 (別 shape) の element 軸復元を census が FAIL" \
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

cen_mut "CEN-rawnest-script-el ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script><div id=\"req-ci-001\"></div></template></script>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-script-tx ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script><code>z</code></template></script>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-script-esc ★自己閉じ <script/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<script/><template></script>&lt;span </template></script>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-style-el ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style><div id=\"req-ci-001\"></div></template></style>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-style-tx ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style><code>z</code></template></style>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-style-esc ★自己閉じ <style/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<style/><template></style>&lt;span </template></style>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-xmp-el ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp><div id=\"req-ci-001\"></div></template></xmp>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-xmp-tx ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp><code>z</code></template></xmp>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-xmp-esc ★自己閉じ <xmp/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<xmp/><template></xmp>&lt;span </template></xmp>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-iframe-el ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe><div id=\"req-ci-001\"></div></template></iframe>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-iframe-tx ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe><code>z</code></template></iframe>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-iframe-esc ★自己閉じ <iframe/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<iframe/><template></iframe>&lt;span </template></iframe>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-noembed-el ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed><div id=\"req-ci-001\"></div></template></noembed>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-noembed-tx ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed><code>z</code></template></noembed>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-noembed-esc ★自己閉じ <noembed/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<noembed/><template></noembed>&lt;span </template></noembed>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-noframes-el ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes><div id=\"req-ci-001\"></div></template></noframes>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-noframes-tx ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes><code>z</code></template></noframes>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-noframes-esc ★自己閉じ <noframes/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<noframes/><template></noframes>&lt;span </template></noframes>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-textarea-el ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea><div id=\"req-ci-001\"></div></template></textarea>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-textarea-tx ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea><code>z</code></template></textarea>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-textarea-esc ★自己閉じ <textarea/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<textarea/><template></textarea>&lt;span </template></textarea>}" "census double-escape: &lt;span"
cen_mut "CEN-rawnest-title-el ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点への既存 id 複製注入 を census が検出 (★element 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title><div id=\"req-ci-001\"></div></template></title>}" "census navigable id: 重複 0"
cen_mut "CEN-rawnest-title-tx ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点への人間層 <code> 注入 を census が検出 (★text/inline 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title><code>z</code></template></title>}" "census generic: 人間層 <code> rest"
cen_mut "CEN-rawnest-title-esc ★自己閉じ <title/> + <template> 挟み + 末尾閉じ直しの ★盲点へのescape literal 注入 を census が検出 (★escape literal 軸)" \
  "s{(<body[^>]*>)}{\$1<title/><template></title>&lt;span </template></title>}" "census double-escape: &lt;span"

# === XARM. ★3 関数 (strip_inert / census_dump / h_inline) の cross-arm byte-identity ★実行 gate (folio-gt4s ceiling major fix) ===
#   契約 SSOT は「両 arm 逐字同一」を不変量と宣言し、 本 census 群の正当化根拠 (片 arm のみの改変 = cross-arm
#   非対称の新設) もそこに立つ。 しかし従来この不変量の記録は ★コード注記だけ で機械照合が無く、
#   片 arm ドリフト (folio-7st6 が verification arm のみ是正し folio-gt4s が後追い是正した ★実発クラス) を
#   敵対 suite が 1 本も落とさず通していた。 ★注記だけを唯一の記録にしない (回避表記封鎖 = c5r.2)。
#   ★恒真 PASS 封鎖: 抽出結果が空 / 3 関数揃わないと「diff が empty」は ★自明に成立する。 ゆえに
#   (a) 両 arm の抽出が非空、 (b) 抽出できた関数が 3 本、 を ★別 assert として撃つ (関数改名・実装形変更で
#   検査が黙って無力化するのを防ぐ = 本 suite 自身に対する trust anchor)。
xarm_extract() { # file fnname
  awk -v fn="$2" 'index($0,fn"() { python3")==1{f=1} f{print} f&&/^}$/{exit}' "$1"
}
xarm_n=0
for xfn in strip_inert census_dump h_inline; do
  xarm_extract "$SCRIPT_DIR/verify-spec.sh"         "$xfn" > "$TMP/xarm-a.$xfn"
  xarm_extract "$SCRIPT_DIR/verify-verification.sh" "$xfn" > "$TMP/xarm-b.$xfn"
  if [[ ! -s "$TMP/xarm-a.$xfn" || ! -s "$TMP/xarm-b.$xfn" ]]; then
    ng "XARM-$xfn ★抽出が空 (抽出子が実装と不一致 = 検査の恒真化)"
    continue
  fi
  xarm_n=$((xarm_n+1))
  if diff -q "$TMP/xarm-a.$xfn" "$TMP/xarm-b.$xfn" >/dev/null; then
    ok "XARM-$xfn ★両 arm byte-identical ($(wc -l < "$TMP/xarm-a.$xfn") 行)"
  else
    ng "XARM-$xfn ★両 arm で乖離 (cross-arm 非対称の新設): $(diff "$TMP/xarm-a.$xfn" "$TMP/xarm-b.$xfn" | head -3 | tr '\n' ' ')"
  fi
done
if [[ "$xarm_n" -eq 3 ]]; then
  ok "XARM-count ★3 関数すべてを両 arm から抽出できた (関数消失/改名による恒真 PASS の封鎖)"
else
  ng "XARM-count ★抽出できた関数が $xarm_n 本 (期待 3 = 検査対象が痩せている)"
fi

# === LIVEPIN. ★案(a) topology「HTML_LIVE を census が一切消費しない」の ★tracked 恒久 pin (folio-gt4s ceiling 2 巡目) ===
#   契約 SSOT は「消費 site 7/7・partial-switch は fail-open 残存」を明示する: strip_inert は bogus comment の
#   オフセット誤算という fail-open を持つため、 census subject の ★一部 でも HTML_LIVE へ戻すと当該経路が再開通する。
#   ところがこの不変量を機械照合していたのは ★cell-local な untracked selftest だけ で、 land すると消え、
#   verify-*.sh の「★本 view は ★どの census も消費しない」というコメントが shipped 状態で ★唯一の記録 になる
#   (SNAPPIN 節がまさに同じ理由で untracked から移植された前例・回避表記封鎖 = c5r.2)。
#   ★tracked MK (CEN-tpl6/7/8) は census_dump(a.xref) と h_inline(code rest) の 2 軸しか撃たないため、
#   h_inline の残り 4 軸 (code table-cell/caption/総数・span table-cell/caption) を HTML_LIVE へ戻す
#   ★部分再配線 は現行 suite を素通る。 ゆえに配線そのものを fixed-string で pin する。
#   ★恒真 PASS 封鎖: 「消費 0 件」だけを撃つと ★変数名改称・行消失 で黙って成立する。 producer 側の残置
#   (retain-symmetric(S)) と ★RAW $HTML 側の期待本数 を対で assert し、 検査の空撃ちを弾く。
for lf in verify-spec.sh verify-verification.sh; do
  lp="$SCRIPT_DIR/$lf"
  l_consume="$(grep -cF -e 'census_dump "$HTML_LIVE"' -e 'h_inline "$HTML_LIVE"' "$lp")"
  l_mktemp="$(grep -cF 'HTML_LIVE="$(mktemp)"' "$lp")"
  l_prod="$(grep -cF 'strip_inert "$HTML" > "$HTML_LIVE"' "$lp")"
  l_cd="$(grep -cF 'census_dump "$HTML"' "$lp")"
  l_hi="$(grep -cF 'h_inline "$HTML"' "$lp")"
  if [[ "$l_consume" -ne 0 ]]; then
    ng "LIVEPIN-$lf ★census が HTML_LIVE を消費している ($l_consume 件・部分再配線 = bogus comment fail-open の再開通)"
  elif [[ "$l_mktemp" -ne 1 || "$l_prod" -ne 1 ]]; then
    ng "LIVEPIN-$lf ★producer 行が期待形と不一致 (mktemp=$l_mktemp / strip_inert=$l_prod・期待 1/1 = 検査の恒真化)"
  elif [[ "$l_cd" -ne 1 || "$l_hi" -ne 6 ]]; then
    ng "LIVEPIN-$lf ★RAW \$HTML の census subject 本数が期待外 (census_dump=$l_cd 期待 1 / h_inline=$l_hi 期待 6)"
  else
    ok "LIVEPIN-$lf ★census subject は RAW \$HTML のみ (消費 0 / producer 存置 1+1 / RAW 消費 1+6)"
  fi
done

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

# ============================================================================
# === ADR-0054 (flip 済 spec 提示層の標準形・folio-8q7l Cell U) の per-shape mutation-kill (PR 群) ===
#   ★per-shape で撃つ理由: 章帯番号 / 静的 band heading / 章 wrapper / chip 一行タイトル / role 平易語 /
#     優先度バッジ / 平易行 / fold ラベル / 空 subsection 要約 は ★DOM 形状が別クラス ゆえ、
#     1 instance の実弾は構造差のある instance の穴を証明しない (jyfh/r8k の per-shape 規律)。
#   ★★new field は ★all-or-none optional (extractor 再抽出物でも assemble できる互換性のため) ゆえ、
#     「契約から一括削除 → 再生成」で逐値突合が ★0/0 恒真 PASS する。 その ★唯一の FAIL 源 = 契約非依存
#     census を ★isolate する MK を各軸に ★対で 置く (逐値 MK と census MK の 2 本立て)。
#   ★全 MK に fired-guard を付す (shape drift による空撃ちを検出)。
#   ★★宣言能力 == 実能力 の開示 (1): assemble-spec.sh の band_num() が持つ「core band() の連番 span が
#     見当たらなければ abort」の fail-loud は、 共有 lib/common.sh の mutation を要するため ★本 suite の
#     per-shape MK では撃っていない (verify 側 PR1 = .num 列突合が同クラスの結果を捕捉する)。
#   ★★宣言能力 == 実能力 の開示 (2): rules は ★ref-primary (References の一次参照を人間層へ可視化) を
#     ★実装していない — rules には References 章が無く、 外部 URL (WCAG / mermaid docs 等) は normative 本文内の
#     付随引用で「一次参照 set」を成さない (admin 裁定 U補正4(a) = surface 件数は worker 設計判断・0 件も許容)。
#     ゆえに Cell R の PR17/18/19/23/28/29/30 に相当する ★一次参照 MK 群は ★存在しない (空撃ち MK を作らない)。
# ============================================================================
# PR1. ★章帯番号を連番 (01) へ戻す退行 → band .num 列 FAIL (§番号一致 = ADR-0054 §2.2)。
cp "$TMP/base-filled.html" "$TMP/pr1.html"
perl -0777 -i -pe 'our $n; $n += s#<span class="num">0</span>#<span class="num">01</span>#; END { exit($n?0:9) }' "$TMP/pr1.html" \
  || ng "PR1 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR1 ★章帯番号の連番戻し (§番号 → 01) を band .num 列が捕捉" "$TMP/pr1.html" "band .num 列"
# PR2. ★静的 band heading を旧 over-promise 文言へ戻す → heading 列 FAIL。
#   ★旧 heading は「原則・ADR・検証へ前方照会する」と §番号を持たない形で、 §番号一致と heading 逐値の両方を破る。
cp "$TMP/base-filled.html" "$TMP/pr2.html"
perl -0777 -i -pe 'our $n; $n += s#<h2>§13\. 上位文書への前方照会 — 原則・決定記録・検証仕様へつながる</h2>#<h2>rules は照会の終端ではない — 原則・ADR・検証へ前方照会する</h2>#; END { exit($n?0:9) }' "$TMP/pr2.html" \
  || ng "PR2 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR2 ★静的 band heading の旧 over-promise 復活 (§13) を heading 列が捕捉" "$TMP/pr2.html" "section 可視 heading 列"
# PR3. ★前方照会章の wrapper section 剥奪 (章化の喪失 = 目次から辿れない旧状態への退行) → section anchor 列 FAIL。
cp "$TMP/base-filled.html" "$TMP/pr3.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n##; END { exit($n?0:9) }' "$TMP/pr3.html" \
  || ng "PR3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR3 ★前方照会章の wrapper 剥奪 (章化喪失) を section anchor 列が捕捉" "$TMP/pr3.html" "section anchor 列"
# PR4. ★wrapper への class 侵食 (normative/informative census 11/1 を汚す) → wrapper 陽性 assert + census FAIL。
cp "$TMP/base-filled.html" "$TMP/pr4.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">#<section id="forward-refs" class="normative">#; END { exit($n?0:9) }' "$TMP/pr4.html" \
  || ng "PR4 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR4 ★提示層 wrapper への class 侵食を陽性 assert が捕捉 (census 汚染の封鎖)" "$TMP/pr4.html" "class 無しで実在"
# PR5. ★census id allowlist の default-block 維持 (admin 裁定 C2): wrapper 2 literal ★以外 の新 id は従来どおり FAIL する。
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
  ok "PR7 ★契約 title 一括削除を契約非依存 census (rf-gloss == 36) が捕捉 (0/0 恒真封鎖)"
else ng "PR7 ★census が title 一括削除を捕捉できず (rc=$pr7_rc = 0/0 恒真 PASS の再開通)"; fi
# PR8. ★role 可視ラベルの英語生表示への退行 (attr は不変) → chip タプル FAIL (平易語 map の逐値突合)。
cp "$TMP/base-filled.html" "$TMP/pr8.html"
perl -0777 -i -pe 'our $n; $n += s#(<span class="rf-role">)この規約が実装する原則#${1}implementation#g; END { exit($n?0:9) }' "$TMP/pr8.html" \
  || ng "PR8 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR8 ★role 可視ラベルの英語生表示への退行を chip タプルが捕捉 (attr は機械 token 保持)" "$TMP/pr8.html" "references: (token,doc,role,title)"
# PR9. ★優先度バッジの label↔level 詐称 (must の行に「推奨・現在」) → label↔level 束縛 FAIL。 ★ラベルは prose slot ゆえ
#   contract と直接突合できない — closed allowlist の逐値束縛が唯一の teeth (件数だけ数える検査では素通る形)。
cp "$TMP/base-filled.html" "$TMP/pr9.html"
perl -0777 -i -pe 'our $n; $n += s#(data-slot-id="prio-req-da-struct-1">)必須(</span>)#${1}推奨・現在${2}#; END { exit($n?0:9) }' "$TMP/pr9.html" \
  || ng "PR9 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR9 ★優先度バッジの label↔level 詐称 (must 行に「推奨・現在」) を allowlist 逐値束縛が捕捉" "$TMP/pr9.html" "label↔level 逐値束縛"
# PR10. ★per-row 束縛 (relocation クラス): 別 row の slot-id を持ってくる (件数保存) → 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr10.html"
perl -0777 -i -pe 'our $n; $n += s#data-slot-id="prio-req-da-struct-1"#data-slot-id="prio-req-da-struct-2"#; END { exit($n?0:9) }' "$TMP/pr10.html" \
  || ng "PR10 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR10 ★優先度バッジ slot の per-row 束縛 (別 row の slot-id・件数保存) を要件タプルが捕捉" "$TMP/pr10.html" "要件タプル"
# PR11. ★平易行 (rq-plain) を 1 row 分削除 → 契約非依存 census + 要件タプル FAIL。
cp "$TMP/base-filled.html" "$TMP/pr11.html"
perl -0777 -i -pe 'our $n; $n += s#<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span><span data-prose-slot="plain" data-slot-id="plain-req-da-struct-1">[^<]*</span></p>\n##; END { exit($n?0:9) }' "$TMP/pr11.html" \
  || ng "PR11 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR11 ★平易行 1 row 削除を契約非依存 census (rq-plain == 26) が捕捉" "$TMP/pr11.html" "census: rq-plain"
# PR12. ★契約 requirements[].priority 一括削除 → 再生成 → 逐値タプルは自己整合 (0/0 恒真) し census が唯一の FAIL 源。
cp "$BASE" "$TMP/pr12.yaml"; yq -i 'del(.requirements[].priority)' "$TMP/pr12.yaml"
bash "$ASM" "$TMP/pr12.yaml" "$TMP/pr12.html" >/dev/null 2>&1 || ng "PR12 assemble 失敗 (priority 無し contract の後方互換経路が壊れた)"
pr12_out="$(bash "$VER" "$TMP/pr12.yaml" "$TMP/pr12.html" 2>&1)"; pr12_rc=$?
if printf '%s\n' "$pr12_out" | grep -F '要件タプル (id/pattern/class/label/essence/statement) 順序突合' | grep -qF '[OK]'; then
  ok "PR12 補助 ★要件タプルは mutated 契約と自己整合 (0/0 恒真・census が唯一の FAIL 源)"
else ng "PR12 補助 ★要件タプルが自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr12_rc -ne 0 ]] && printf '%s\n' "$pr12_out" | grep -F 'census: rq-prio' | grep -qF '[FAIL]'; then
  ok "PR12 ★契約 priority 一括削除を契約非依存 census (rq-prio == 26) が捕捉 (0/0 恒真封鎖)"
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
# PR15. ★空 subsection の人間層 1 行要約を 1 件削除 → subhead essence 列 + census FAIL (見出しだけの節が復活する退行)。
cp "$TMP/base-filled.html" "$TMP/pr15.html"
perl -0777 -i -pe 'our $n; $n += s#(<h3 id="s10-2">§10\.2 CI Gate Compliance</h3>)<p class="sub-se">[^<]*</p>#${1}<p class="sub-se"></p>#; END { exit($n?0:9) }' "$TMP/pr15.html" \
  || ng "PR15 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "PR15 ★空 subsection への退行 (1 行要約の空化) を subhead essence 列が捕捉" "$TMP/pr15.html" "subhead essence 列"
# PR15b. ★同じ退行を ★契約非依存 census が単独で撃てること (HTML 側だけを見る backstop の isolation)。
#   ★逐値突合と census の 2 本が同時に落ちる形ゆえ isolation は「census 側にも [FAIL] が立つ」で示す。
pr15b_out="$(bash "$VER" --filled "$BASE_PROSE" "$BASE" "$TMP/pr15.html" 2>&1)"
if printf '%s\n' "$pr15b_out" | grep -F 'census: 非空の subhead 1 行要約' | grep -qF '[FAIL]'; then
  ok "PR15b ★1 行要約の空化を契約非依存 census (非空 sub-se == 23) も独立に捕捉"
else ng "PR15b ★census が空 subsection 退行を捕捉できず (0/0 恒真 PASS の再開通)"; fi
# PR16. ★契約 subhead essence 一括空化 → 再生成 → 逐値 essence 列は「空 == 空」で自己整合し、 契約非依存 census が
#   唯一の FAIL 源 (空 subsection = 本文ゼロの見出しへの全面退行を独立 anchor が撃つ)。
#   ★assembler 側の hard abort は ★採らない: extractor が pre-flip 原本から再抽出する contract は本 cell 以前の
#   essence 状態を持ち、 その genuine 再生成が COLLAPSE 群の前提だから (assemble-spec.sh の同注記と対)。
cp "$BASE" "$TMP/pr16.yaml"; yq -i '(.sections[].blocks[]? | select(.type=="subhead")).essence = ""' "$TMP/pr16.yaml"
bash "$ASM" "$TMP/pr16.yaml" "$TMP/pr16.html" >/dev/null 2>&1 || ng "PR16 assemble 失敗 (essence 空 subhead の後方互換経路が壊れた)"
pr16_out="$(bash "$VER" "$TMP/pr16.yaml" "$TMP/pr16.html" 2>&1)"; pr16_rc=$?
if printf '%s\n' "$pr16_out" | grep -F 'subhead essence 列' | grep -qF '[OK]'; then
  ok "PR16 補助 ★subhead essence 逐値は mutated 契約と自己整合 (census が唯一の FAIL 源)"
else ng "PR16 補助 ★subhead essence 逐値が自己整合せず (census 単独 isolation の前提崩れ)"; fi
if [[ $pr16_rc -ne 0 ]] && printf '%s\n' "$pr16_out" | grep -F 'census: 非空の subhead 1 行要約' | grep -qF '[FAIL]'; then
  ok "PR16 ★契約 essence 一括空化を契約非依存 census (非空 sub-se == 23) が捕捉"
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
yq -i '(.requirements[] | select(.id=="REQ-DA-STRUCT-3")).statement = ((.requirements[] | select(.id=="REQ-DA-STRUCT-3")).statement | sub("SHALL be one of"; "SHOULD be one of"))' "$TMP/pr22.yaml"
perl -0777 -i -pe 'our $n; $n += s#every data-audience value SHALL be one of#every data-audience value SHOULD be one of#; END { exit($n?0:9) }' "$TMP/pr22.html" \
  || ng "PR22 mutation が発火せず (shape drift = 空撃ち)"
pr22_out="$(bash "$VER" --filled "$BASE_PROSE" "$TMP/pr22.yaml" "$TMP/pr22.html" 2>&1)"; pr22_rc=$?
if printf '%s\n' "$pr22_out" | grep -F '要件タプル' | grep -qF '[OK]'; then
  ok "PR22 補助 ★要件タプルは mutated 契約と自己整合 (契約内不変 chk が唯一の FAIL 源 = isolation)"
else ng "PR22 補助 ★要件タプルが自己整合せず (単独 isolation の前提崩れ)"; fi
if [[ $pr22_rc -ne 0 ]] && printf '%s\n' "$pr22_out" | grep -F '[FAIL]' | grep -qF '契約内不変: priority == statement'; then
  ok "PR22 ★statement の modal verb 反転 (must 宣言 × SHOULD 条文) を契約内不変 chk が捕捉"
else ng "PR22 ★契約内不変 chk が level↔statement 矛盾を捕捉できず (rc=$pr22_rc = contract 全盲の再開通)"; fi
# PR23. ★first-modal-wins の ★危険方向 (SHOULD が先・MUST が後 = 弱い宣言で強い条文を包む) が AMBIGUOUS-BOTH で
#   abort すること。 ★rules で Cell R の「両方あれば即 AMBIGUOUS」から first-modal-wins へ精密化した際、 緩めた方向が
#   ★主節 MUST + 従属節 SHOULD に限られる (= 詐称に使えない) ことの実弾。
cp "$BASE" "$TMP/pr23.yaml"
yq -i '(.requirements[] | select(.id=="REQ-DA-STRUCT-3")).statement = "REQ-DA-STRUCT-3: A spec SHOULD normalize its values, and every data-audience value MUST be one of machine or human only."' "$TMP/pr23.yaml"
expect_abort "PR23 ★SHOULD 先行 + MUST 後続 を AMBIGUOUS-BOTH として abort (first-modal-wins の危険方向は fail-closed)" "$TMP/pr23.yaml" "modal verb が矛盾"
# PR24. ★heading_secnum の fail-closed abort の ★実弾 (宣言能力 == 実能力 の pin)。 §N 形でない heading を持つ契約 →
#   assemble abort。 ★退行の実態: emit_section が band_num "$(heading_secnum …)" と ★引数位置のコマンド置換 で呼ぶと、
#   bash は set -euo pipefail 下でも置換の失敗を親コマンドの成否に反映しないため exit 1 が subshell で飲まれ、
#   空 num のまま <span class="num"></span> を rc=0 で書き出す (verify 側 backstop 頼みの fail-open)。
#   ★被覆の正確な宣言 (re-cert 実測 2026-07-27): abort assert (PR24) 単独が殺せるのは「両層が消えた合流状態」のみ
#   (期待 substring『節番号を導出できない』は第 1 層 (emit_section 代入形) と第 2 層 (band_num 数値 guard) の
#   メッセージに共通するため)。第 1 層 ★単独 の退行は PR24b の負 assert (『band_num に非数値』が stderr に
#   ★不在 = 第 1 層が band_num 到達前に abort した証拠) が弁別する。第 2 層の単独実効は第 1 層存命中は経路上
#   撃てない — mutant 実測 (代入形だけ退行 → guard が rc=1 で停止) で確認済み (bd folio-8q7l notes)。
cp "$BASE" "$TMP/pr24.yaml"; yq -i '.sections[2].heading = "NO SECTION NUMBER"' "$TMP/pr24.yaml"
pr24_out="$(bash "$ASM" "$TMP/pr24.yaml" "$TMP/o.html" 2>&1)"; pr24_rc=$?
if [[ $pr24_rc -ne 0 && "$pr24_out" == *"節番号を導出できない"* ]]; then
  ok "PR24 ★§N 形でない heading を abort (節番号導出不能を silent に空 .num へ落とさない)"
else ng "PR24 ★§N 形でない heading を abort (abort されず生成された・または理由が想定外。 rc=$pr24_rc / 末尾: $(printf '%s' "$pr24_out" | tail -1))"; fi
if [[ $pr24_rc -ne 0 && "$pr24_out" == *"heading が §N 形でない"* && "$pr24_out" != *"band_num に非数値"* ]]; then
  ok "PR24b ★第 1 層 (emit_section 代入形) が band_num 到達前に abort (第 1 層メッセージ実在 + 第 2 層メッセージ不在 = 層独立の pin・空撃ちでは緑にならない)"
else ng "PR24b ★第 1 層の退行か空撃ち (rc=$pr24_rc / 第 2 層メッセージへ到達 or 第 1 層メッセージ不在)"; fi
# ============================================================================
# ★CT1〜CT52 — ★containment (章化の実質) の ★arm ごと per-shape mutation-kill。
#   verify-spec.sh の containment 節 (開口隣接 / region 占有 / 1 段内側 / 3 レベル束縛 / 器中身の占有) は
#   ★生成物の改竄で落ちる arm ゆえ、 ★各 arm に「その arm が [FAIL] 理由を担う」実弾を 1 本以上 与える
#   (arm を消すと本 suite が赤くなる = mutation-kill)。 ★全て fired-guard 付き (shape drift による空撃ちを検出)。
#   ★per-shape 規律 (jyfh / r8k): 1 instance の実弾は ★構造差のある instance の穴を証明しない — wrapper 2 章
#   (payload = ref-grid / glossary-term-table) と契約章 (payload = 章要旨 callout) は ★別クラス ゆえ別実弾で撃つ。
#   ★reason anchor は ★章名込み の label へ当てる (章非特定の語だと別章の巻き添え FAIL でも満たされ per-shape の
#   主張が pin されない)。 ★CT 番号は本 suite 内の独立採番 (Leg B = relations 側の番号への lockstep は無い)。
# ============================================================================
# CT1. ★hollow wrapper — wrapper 開きタグを ★即閉じ し、 章帯 / chapbody / ref-grid を wrapper の ★外 へ押し出す。
#   ★タグ均衡は保たれる (対応閉じタグも同時に除去する) ため、 件数 census・section anchor 列・wrapper 陽性 assert
#   (実在 + class 無し) は ★全て素通る。 「id を持つ section が在る」ことだけを見る assert 群は章化の ★実質
#   (中身がその章に属すること) を守れない、 というのが本 shape の主張。 捕捉は containment の ★開口隣接 pin。
#   ★fired-guard は ★2 置換 とも要求する (対応閉じタグ除去が空振りすると単なるタグ不均衡 HTML になり、 別 arm の
#   巻き添え FAIL で ★理由の異なる false-pass を作るため)。
cp "$TMP/base-filled.html" "$TMP/ct1.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n#<section id="forward-refs"></section>\n#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct1.html" \
  || ng "CT1 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT1 ★hollow wrapper (章帯ごと外へ押し出し) を containment 開口隣接 pin が捕捉" "$TMP/ct1.html" "'forward-refs' の開口直後に"
# CT2. ★chapbody だけの押し出し — 章帯は wrapper 内に ★残したまま 本文 (chapbody / ref-grid / chip) を外へ出す。
#   CT1 と ★別 shape: 開口隣接 pin は band が隣接したままなので ★PASS し、 region 占有 pin ★だけ が発火する
#   (= 2 段の pin が互いの巻き添えでなく ★独立に teeth を持つ ことの per-shape 実証)。
cp "$TMP/base-filled.html" "$TMP/ct2.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct2.html" \
  || ng "CT2 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT2 ★chapbody だけを章の外へ (band 隣接は保持) を region 占有 pin が単独で捕捉" "$TMP/ct2.html" "章 'forward-refs' region 内の chapbody == 1"
# CT3. ★用語集 wrapper の hollow 化 — CT1 と ★別 instance (payload が chip でなく .grow の別構造クラス)。
cp "$TMP/base-filled.html" "$TMP/ct3.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="glossary-terms">\n#<section id="glossary-terms"></section>\n#; $n += s#</section>\n</div>\n<footer#</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct3.html" \
  || ng "CT3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT3 ★用語集 wrapper の hollow 化 (別 payload クラス) を containment 開口隣接 pin が捕捉" "$TMP/ct3.html" "'glossary-terms' の開口直後に"
# CT4. ★band tint の逐値付け替え — band は隣接したまま ★別章の帯 に差し替える (tint 属性値だけを書換)。
#   開口隣接 pin の ★識別成分 (どの章の帯か) を ★単独で 撃つ (位置成分 = CT5 / 節同一性成分 = CT6 と別実弾)。
cp "$TMP/base-filled.html" "$TMP/ct4.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-)violet(">)#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/ct4.html" \
  || ng "CT4 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT4 ★別章 band への付け替え (tint 逐値) を開口隣接 pin が単独で捕捉" "$TMP/ct4.html" "'forward-refs' の開口直後に"
# CT5. ★開口への異物挿入 — band は残り tint も §番号も正しいが、 wrapper 開口と band の ★間 に別要素が入る。
#   CT4 (属性の同一性) と別成分 = ★位置 (直後性) を撃つ。
cp "$TMP/base-filled.html" "$TMP/ct5.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n)#${1}<p class="decoy">x</p>\n#; END { exit($n==1?0:9) }' "$TMP/ct5.html" \
  || ng "CT5 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT5 ★開口と章帯の間への異物挿入を開口隣接 pin が単独で捕捉 (位置成分)" "$TMP/ct5.html" "'forward-refs' の開口直後に"
# CT6. ★band §番号の逐値書換 — 開口隣接 pin の ★第 3 成分 (どの節の帯か)。 tint (CT4) / 位置 (CT5) と別成分ゆえ
#   別実弾で撃つ (band .num 列 arm も巻き添えで発火するが、 理由 anchor は containment 側に取る)。
#   ★rules は §番号が ★非連番 (§1 欠番 / 静的 band は §13・§14) ゆえ、 本 arm の期待値が ★連番 hardcode でなく
#   ★contract 見出し由来の導出 であることも同時に pin される (13 → 9 の書換は連番仮定では表せない差)。
cp "$TMP/base-filled.html" "$TMP/ct6.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-violet"><span class="num">)13#${1}9#; END { exit($n==1?0:9) }' "$TMP/ct6.html" \
  || ng "CT6 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT6 ★band §番号の逐値書換を開口隣接 pin が捕捉 (節同一性成分・§1 欠番の非連番導出も同時に pin)" "$TMP/ct6.html" "'forward-refs' の開口直後に"
# CT7. ★over-containment — forward-refs の閉じタグを外し glossary-terms を ★入れ子 にする (assembler の
#   printf </section> 1 行脱落と同 shape)。 押し出しの ★逆向き ゆえ region 占有の ★上限側 (== 1) だけ が発火する。
cp "$TMP/base-filled.html" "$TMP/ct7.html"
perl -0777 -i -pe 'our $n; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; $n += s#</section>\n</div>\n<footer#</section>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct7.html" \
  || ng "CT7 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT7 ★wrapper の入れ子化 (over-containment) を region 占有の上限側が捕捉" "$TMP/ct7.html" "章 'forward-refs' region 内の章帯 == 1"
# CT8. ★契約章の hollow 化 — 同一 DOM shape (band 1 + chapbody 1) を持つのは提示層 wrapper 2 本だけではない。
#   containment を 2 id の手書き列挙に留めると残り 12 章が無防備 (partial-enumeration trap) ゆえ、 契約章側にも実弾を置く。
cp "$TMP/base-filled.html" "$TMP/ct8.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-directory" class="normative">\n#<section id="s2-directory" class="normative"></section>\n#; $n += s#</section>\n<section id="s3-naming" class="normative">#<section id="s3-naming" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct8.html" \
  || ng "CT8 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT8 ★契約章 (s2-directory) の hollow 化を containment が捕捉 (2 id 列挙では届かない残り 12 章)" "$TMP/ct8.html" "'s2-directory' の開口直後に"
# CT9. ★1 段内側の hollow 化 (chapbody) — chapbody を空で閉じ payload を chapbody の ★sibling (章の中・器の外) へ出す。
#   hollow 化の defect 原理は ★階層ごとに 再演するので、 wrapper 階層の pin だけでは素通る shape。
cp "$TMP/base-filled.html" "$TMP/ct9.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="chapbody">\n<div class="ref-grid">#<div class="chapbody"></div>\n<div class="ref-grid">#; $n += s#</div>\n</div>\n</section>\n<section id="glossary-terms">#</div>\n</section>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct9.html" \
  || ng "CT9 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT9 ★chapbody 空化 + payload を器の外へ (1 段内側の hollow 化) を containment が捕捉" "$TMP/ct9.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# CT10. ★chapbody 開口への異物挿入 — 1 段内側の ★開口隣接 pin (位置成分) を単独で撃つ。
cp "$TMP/base-filled.html" "$TMP/ct10.html"
perl -0777 -i -pe 'our $n; $n += s#(<div class="chapbody">\n)(<div class="ref-grid">)#${1}<p class="decoy">x</p>\n${2}#; END { exit($n==1?0:9) }' "$TMP/ct10.html" \
  || ng "CT10 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT10 ★chapbody 開口と payload container の間への異物挿入を 1 段内側の開口隣接 pin が捕捉" "$TMP/ct10.html" "の chapbody 開口直後に ref-grid が隣接"
# CT11. ★hollow container (ref-grid) — container を即閉じし chip 全数を container の ★外 (chapbody 直下) へ出す。
#   「container の開きタグが在る」は「chip がその中に在る」を意味しない (2 段内側の再演)。
cp "$TMP/base-filled.html" "$TMP/ct11.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"></div>\n#; $n += s#</div>\n</div>\n</section>\n<section id="glossary-terms">#</div>\n</section>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct11.html" \
  || ng "CT11 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT11 ★hollow ref-grid (chip 全数を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/ct11.html" "前方照会 chip の ★全数"
# CT12. ★hollow container (glossary-term-table) — CT11 と ★別構造クラス (payload が chip でなく .grow 行)。
cp "$TMP/base-filled.html" "$TMP/ct12.html"
perl -0777 -i -pe 'our $n; $n += s#<div data-component="glossary-term-table">\n#<div data-component="glossary-term-table"></div>\n#; $n += s#</div>\n</div>\n</section>\n</div>\n<footer#</div>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct12.html" \
  || ng "CT12 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT12 ★hollow glossary-term-table (.grow を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/ct12.html" "用語集 行 (.grow) の ★全数"
# ---- CT13/CT14/CT15: ★parser-differential (r8k / folio-wq4 再発クラス) の 3 vector ----
#   いずれも 「本物の </section> を band 直後へ入れて章本文を章の ★外 へ出し、 元の閉じタグを ★偽タグ で置換して
#   ★素朴な深さ計数 の帳尻だけ合わせる」 shape。 make_body はコメント / RAWTEXT の中身を verbatim 保持し、
#   属性値内の生 `>` も (raw `<` と違い) fail-closed しないため、 生テキストへの素朴な section 走査は
#   region を ★over-slice して containment を丸ごと素通す。
#   ★3 vector を別実弾で撃つ: マスク対象が コメント / RAWTEXT / 属性値 の ★3 クラス あり、 1 本の実弾は他 2 つの穴を証明しない。
cp "$TMP/base-filled.html" "$TMP/ct13.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<!--<section>-->\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct13.html" \
  || ng "CT13 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT13 ★コメント密輸による region over-slice (parser-differential) を containment が捕捉" "$TMP/ct13.html" "章 'forward-refs' region 内の chapbody == 1"
cp "$TMP/base-filled.html" "$TMP/ct14.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<script>var s = "<section>";</script>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<script>var e = "</section>";</script>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct14.html" \
  || ng "CT14 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT14 ★script (RAWTEXT) 密輸による region over-slice を containment が捕捉" "$TMP/ct14.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# ★CT15 の ★閉じ側 だけ コメント vector を使うのは、 属性値内の生 `<` が make_body で ★既に fail-closed される ため
#   (raw-lt-in-tag)。 属性値 vector は ★開き側 にしか存在しない = 装わずに書く。
cp "$TMP/base-filled.html" "$TMP/ct15.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<p class="decoy" title="x><section>y"></p>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct15.html" \
  || ng "CT15 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT15 ★属性値内の生 '>' 密輸による region over-slice を containment が捕捉" "$TMP/ct15.html" "前方照会 chip の ★全数"
# CT16. ★非 genuine shape の fail-closed — div / section の ★自己閉じ構文。 HTML の非 foreign content では `/>` は
#   無視される (= 開きタグ) が、 svg / math の ★foreign content 内では自己閉じが効くため、 深さ計数と実 DOM の差を
#   作る入口になる。 rendering を完全にモデルする arms race へ戻らず、 ★genuine な assembler が emit しない shape を
#   ★拒否する (make_body と同じ規律)。 捕捉は containment tokenizer の構造診断 arm。
cp "$TMP/base-filled.html" "$TMP/ct16.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"/>\n#; END { exit($n==1?0:9) }' "$TMP/ct16.html" \
  || ng "CT16 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT16 ★div の自己閉じ構文 (foreign content 差の入口) を tokenizer が fail-closed" "$TMP/ct16.html" "containment tokenizer の構造診断"
# ★parser-differential の ★残り 3 vector (CT13/14/15 が塞いだ コメント / script / 属性値 の ★外側 に在ったもの):
#   CT17 bogus comment (`<! … >`) — 実 parser は `<!--` でない markup declaration も comment として `>` まで捨てるが、
#        素朴実装は 1 文字進めるだけなので中の `<section>` が ★実タグとして深さに乗る。 genuine BODY にも
#        `<!DOCTYPE html>` が実在するため fix は「拒否」でなく ★実 parser と同じ読み飛ばし (拒否だと genuine が総崩れ)。
#   CT18 escapable RAWTEXT (`<textarea>`) — 中身はテキストゆえ `<section>` は要素にならない。 script / style
#        しか知らない実装では title / textarea 等が素通しになる。
#   CT19 ハイフン入り要素名 (`<section-x>`) — 実 DOM では section と ★別要素。 要素名を `[a-zA-Z0-9]*` で切ると
#        "section" と誤認して章の深さに数える。
cp "$TMP/base-filled.html" "$TMP/ct17.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<! <section> >\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#<! </section> >\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct17.html" \
  || ng "CT17 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT17 ★bogus comment (<! … >) 密輸による region 付け替えを containment が捕捉" "$TMP/ct17.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/ct18.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea><section></textarea>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#<textarea></section></textarea>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct18.html" \
  || ng "CT18 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT18 ★escapable RAWTEXT (textarea) 密輸による region 付け替えを containment が捕捉" "$TMP/ct18.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/ct19.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<section-x>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#</section-x>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct19.html" \
  || ng "CT19 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT19 ★ハイフン入り要素名 (<section-x>) 密輸による region 付け替えを containment が捕捉" "$TMP/ct19.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# CT20. ★契約章の band tint 付け替え — 契約章 12 本の tint 逐値 pin (源 = contract sections[].tint) を ★単独で 撃つ。
#   §番号は変えないので §番号成分では落ちない = tint 成分 ★単独 の teeth を isolate する。
cp "$TMP/base-filled.html" "$TMP/ct20.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory" class="normative">\n<section data-component="chapter-deck-band" class="tint-)brand(")#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/ct20.html" \
  || ng "CT20 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT20 ★契約章 (s2-directory) の band tint 付け替えを tint 逐値 pin が単独で捕捉" "$TMP/ct20.html" "'s2-directory' の開口直後に"
# CT20b. ★rules 固有 tint (s10-mandatory = bad) の付け替え — CT20 と ★別 instance。 tint 期待値が contract の
#   ★値そのもの を読む (assembler 側 tint 集合の hardcode 列挙でない) ことを、 範型に無い値域で pin する。
cp "$TMP/base-filled.html" "$TMP/ct20b.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s10-mandatory" class="normative">\n<section data-component="chapter-deck-band" class="tint-)bad(")#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/ct20b.html" \
  || ng "CT20b mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT20b ★rules 固有 tint (s10-mandatory = bad) の付け替えを contract 由来 tint 逐値 pin が捕捉" "$TMP/ct20b.html" "'s10-mandatory' の開口直後に"
# CT21. ★器の重複 — 正規の ref-grid は ★中身ごと 正しい位置に残したまま、 文書の別位置に ★2 個目の ref-grid を
#   足す。 per-章 arm (chapbody 内に 1 個 / chip 全数が器の中) は ★全て PASS のままで、 2 個目の器は以後の改竄で
#   payload の ★逃げ場 として使える (漏出先の先置き)。 捕捉は ★文書総数 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/ct21.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref-grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$TMP/ct21.html" \
  || ng "CT21 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT21 ★payload container の重複 (漏出先の先置き) を文書総数 pin が単独で捕捉" "$TMP/ct21.html" "ref-grid が ★文書全体で 1 個"
# ★comment 終端の HTML5 非同型。 `-->` 一本終端の実装は、 実 parser が ★早く 終端する形
#   (comment end bang / abrupt close) を知らないため、 攻撃者は「実 DOM では章の外に在る閉じタグ」を tokenizer に
#   だけ comment の中身として ★隠せる。 3 分岐を ★別実弾 で撃つ (CT22 / CT23 / CT24 = 終端規則が別分岐ゆえ
#   1 本の実弾では他 2 分岐の弱化が silent になる)。
cp "$TMP/base-filled.html" "$TMP/ct22.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--x--!></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct22.html" \
  || ng "CT22 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT22 ★comment end bang (--!>) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/ct22.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/ct23.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct23.html" \
  || ng "CT23 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT23 ★abrupt-closing comment (<!-->) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/ct23.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
cp "$TMP/base-filled.html" "$TMP/ct24.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!---></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct24.html" \
  || ng "CT24 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT24 ★<!---> (comment 終端分岐 2) 密輸による閉じタグ隠蔽を containment が捕捉" "$TMP/ct24.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★RAWTEXT 終了タグの ★要素名境界。 `</name[^>]*>` は `</textareax>` にも一致して早期終了し、 以降の
#   擬似タグを実タグとして数える。 ★region を ★伸ばす 向き (開きタグ密輸) で撃つ = over-slice の実害形。
cp "$TMP/base-filled.html" "$TMP/ct25.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea></textareax><section><textarea></textarea>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct25.html" \
  || ng "CT25 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT25 ★RAWTEXT 終了タグの要素名境界 (</textareax>) を突く region 伸長を containment が捕捉" "$TMP/ct25.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★foreign content。 svg / math subtree 内の要素は HTML 名前空間ではないので章の深さに数えてはならない。
#   ★genuine 生成物に svg アイコンが多数実在する ため「現れないから拒否」では閉じられず subtree 追跡が要る。
cp "$TMP/base-filled.html" "$TMP/ct26.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<svg><section></svg>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct26.html" \
  || ng "CT26 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT26 ★foreign content (svg subtree) 内の擬似タグによる region 伸長を containment が捕捉" "$TMP/ct26.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# CT27. ★契約章の 1 段内側 — 契約章 12 本は chapbody を空にして章本文を sibling へ押し出す改竄が素通る形。
#   ★wrapper 側 (CT9) と ★別実弾 で撃つ = 器の種類が別クラス (章要旨 callout vs ref-grid)。
#   ★タグ均衡を保つため 2 置換 (開口直後で閉じる + 元の chapbody 閉じを除去) を fired-guard で ★両方要求する。
cp "$TMP/base-filled.html" "$TMP/ct27.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n<div class="chapbody">)\n(<div data-component="section-essence-callout">)#${1}</div>\n${2}#; $n += s#</div>\n</section>\n<section id="s3-naming" class="normative">#</section>\n<section id="s3-naming" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct27.html" \
  || ng "CT27 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT27 ★契約章 (s2-directory) の chapbody 空化 + 章本文 sibling 押し出しを 1 段内側 pin が捕捉" "$TMP/ct27.html" "章要旨 callout が章 's2-directory' の chapbody 内に 1 個"
# CT28. ★章本文の relocation ★クラス — CT27 (chapbody 完全空化) は ★1 instance にすぎない。 章要旨 callout は
#   chapbody 内に ★残したまま、 それ以降の章本文 (code / details) だけを chapbody の外へ押し出す shape は、
#   callout 由来の 1 段内側 pin (cbadj / cont / docct) を ★全て PASS させたまま素通る。
#   捕捉は「章の直下は 章帯 + chapbody の 2 子だけ」の構造 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/ct28.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)#${1}</div>\n#s; $n += s#</div>\n</section>\n<section id="s3-naming" class="normative">#</section>\n<section id="s3-naming" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct28.html" \
  || ng "CT28 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT28 ★章要旨を残した章本文の relocation (block 粒度) を章直下 2 子の構造 pin が捕捉" "$TMP/ct28.html" "章 's2-directory' の直下は 章帯 + chapbody の 2 子だけ"
# CT29. ★relocation クラスの ★もう一方の向き — 章本文の押し出し先を ★章直下の sibling でなく ★章帯 (band) の
#   ★中 にする。 章直下は band + chapbody のままなので kids pin (CT28) は ★2 を保ったまま PASS し、 1 段内側
#   pin も callout が chapbody 内に残るため全て PASS する。 捕捉は band の直下 4 子固定
#   (共有 CORE lib/common.sh band() = num/kicker/h2/lead) ★単独。
cp "$TMP/base-filled.html" "$TMP/ct29.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory" class="normative">\n<section data-component="chapter-deck-band"[^\n]*?)(</section>\n)(<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)(.*?)(</div>\n</section>\n<section id="s3-naming" class="normative">)#${1}${4}${2}${3}${5}#s; END { exit($n==1?0:9) }' "$TMP/ct29.html" \
  || ng "CT29 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT29 ★章本文の band subtree への退避 (kids を 2 に保つ向き) を band 4 子固定が捕捉" "$TMP/ct29.html" "章 's2-directory' の章帯の直下は num/kicker/h2/lead の 4 子だけ"
# CT30 / CT31. ★document 順を ★保つ relocation 2 形 — 章直下 (kids) / band 直下 (bkids) を固定しても、
#   ★他の probe 値を一切動かさずに 素通る形が残る。
#   CT30 (β) = 章本文を ★別章の chapbody へ移送 (donor 章が空章化し中身が受け側の下に付く)。
#   CT31 (γ) = 章本文を ★同章の machine-fold (details) の中へ退避。
#   捕捉は chapbody 直下の ★契約由来 完全子列 ★単独 (β は donor の列が縮み・γ は fold へ吸い込まれた分だけ列が縮む)。
cp "$TMP/base-filled.html" "$TMP/ct30.html"
perl -0777 -i -pe 'our $n;
if (s#(<section id="s2-directory" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)((?:.(?!</div>\n</section>\n<section id="s3-naming" class="normative">))*.)(\n</div>\n</section>\n<section id="s3-naming" class="normative">)#${1}${3}#s) {
  our $moved = $2; $n++;
  $n++ if s#(<section id="s3-naming" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)#${1}$moved\n#s;
}
END { exit($n==2?0:9) }' "$TMP/ct30.html" \
  || ng "CT30 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT30 ★章本文の別章 chapbody への移送 (document 順保存) を契約由来 完全子列が捕捉" "$TMP/ct30.html" "章 's2-directory' の chapbody 直下は 契約由来の完全子列"
cp "$TMP/base-filled.html" "$TMP/ct31.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s4-format" class="normative">.*?)(<div data-component="spec-subhead"><h3 id="s4-6-a11y">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct31.html" \
  || ng "CT31 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT31 ★章本文の machine-fold 内への退避 (document 順保存) を契約由来 完全子列が捕捉" "$TMP/ct31.html" "章 's4-format' の chapbody 直下は 契約由来の完全子列"
# CT32. ★void 要素による ★計数マスク。 深さ 1 の計数は ★同名深さ計数 ゆえ、 depth-1 に ★対応閉じタグを持たない
#   要素 (`<br>` / `<hr>` / `<img>` …) が 1 個現れると その時点で走査が ★打ち切られる。 攻撃者は 「章本文 block を
#   1 個 chapbody の外 (章直下の sibling) へ出し、 抜けた分の位置に void を 1 個挿す」 だけで kids / cbkids を
#   ★期待値ちょうどに保てる。 現在は打ち切りを err (`unclosed-child-*`) へ倒す fail-closed で捕捉する。
#   ★CT16 と ★別 shape: CT16 は 自己閉じ構文 (`<div/>`) の ★拒否 で、 本 shape は ★正当な HTML (void 要素) を
#   使った ★計数の打ち切り であり、 CT16 を消しても本 shape は err で落ちる関係にない (同じ err arm の ★別 vector)。
#   ★fired-guard は 3 置換 (block 摘出 / 器の外への再配置 + void / band 直後 void) を要求する。
cp "$TMP/base-filled.html" "$TMP/ct32.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div data-component="spec-subhead"><h3 id="s4-6-a11y">.*?</div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s5-delta" class="normative">)#${1} . "<br>\n</div>\n" . $mv . ${2}#e;
$n += s#(<section id="s4-format" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<br>\n#;
END { exit($n==3?0:9) }' "$TMP/ct32.html" \
  || ng "CT32 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT32 ★void 要素 2 個による深さ 1 計数の打ち切り (章本文 relocation のマスク) を tokenizer が fail-closed" "$TMP/ct32.html" "containment tokenizer の構造診断"
# ★CT33〜CT37 — ★foreign content (svg / math) と ★属性 tokenize の parser-differential。 ★4 shape を別実弾で撃つ:
#   (a) foreign root を depth-1 の ★filler に使う計数マスク / (b) foreign 内の ★any-other-end-tag による外側
#   section の閉鎖 / (c) foreign 内の ★breakout 開始タグによる器の重複 / (d) foreign 包みによる ★人間層 block の
#   章外 relocation。 いずれも ★別の parser 規則を突く ので 1 本の実弾は他 3 つの穴を証明しない。 加えて
#   (e) unquoted 属性値の char class 差 = ★幽霊 marker。
# CT33. ★foreign root を depth-1 の filler にする ★計数マスク — 章本文 block を 1 個 machine-fold へ退避させ
#   (CT31 と同じ向き)、 抜けた位置へ ★`<svg><path/></svg>` (genuine と同形・breakout タグを含まない) を挿す。
#   foreign root を ★深さ 1 の子として 1 計上する と cbkids は期待値ちょうどに戻る ため ★完全子数束縛では
#   原理的に見分けられない。 逆に root を計上しないと CT37 の向き (svg 包みで章外へ出す形) が素通る —
#   ★両方向を閉じるのは 計上 + depth-1 err の ★対 のみ。
cp "$TMP/base-filled.html" "$TMP/ct33.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s4-format" class="normative">.*?)(<div data-component="spec-subhead"><h3 id="s4-6-a11y">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}<svg viewBox="0 0 24 24"><path d="M4 4h16"/></svg>\n${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct33.html" \
  || ng "CT33 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT33 ★foreign root (svg) を depth-1 filler にした完全子数マスクを tokenizer が fail-closed" "$TMP/ct33.html" "containment tokenizer の構造診断"
# CT34. ★any other end tag による foreign からの breakout — `<svg></section></svg>` は 実 HTML5 parser では
#   stack を遡って ★外側の HTML section を閉じる (HTML5 tree construction "in foreign content" の任意終了タグ規則)
#   ため、 章本文 ★全部 が章の外へ出る = CT2 / CT9 が捕捉すると主張している relocation クラスそのもの。
#   subtree を丸ごと読み飛ばす実装では ★不可視 で rc=0 / 0 FAIL になる。
cp "$TMP/base-filled.html" "$TMP/ct34.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-directory" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<svg></section></svg>\n#; END { exit($n==1?0:9) }' "$TMP/ct34.html" \
  || ng "CT34 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT34 ★foreign 内の any-other-end-tag (<svg></section></svg>) による外側 section 閉鎖を tokenizer が fail-closed" "$TMP/ct34.html" "containment tokenizer の構造診断"
# CT35. ★breakout 開始タグ — `<svg><div class="ref-grid"></div></svg>` の div は 実 DOM では foreign を抜けて
#   ★HTML 名前空間の実要素 になる (器が 2 個 = CT21 が消したはずの ★逃げ場 の再出現)。 ★CT26 と別 shape:
#   CT26 は擬似タグを svg の ★外 の深さへ効かせる形、 本 shape は svg の ★中 に置いた実要素が外へ出る形。
cp "$TMP/base-filled.html" "$TMP/ct35.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<svg><div class="ref-grid"></div></svg>\n</body>#; END { exit($n==1?0:9) }' "$TMP/ct35.html" \
  || ng "CT35 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT35 ★foreign 内の breakout 開始タグ (svg 内 div.ref-grid) による器の重複を tokenizer が fail-closed" "$TMP/ct35.html" "containment tokenizer の構造診断"
# CT36. ★unquoted 属性値の char class 差による ★幽霊 marker — `<div foo=bar"z"class="ref-grid">` は 実 parser の
#   attribute-value-unquoted state では `"` を ★値に取り込む ので class 属性は ★存在しない (実 DOM から marker が
#   消える) が、 `"` で値を切る実装は 以降を別属性として拾い ★実在しない class="ref-grid" を数える。
#   ★属性逐値一致で数える全 arm (cont / docct / cbadj / pay / band tint …) に効く汎用 primitive ゆえ別実弾で撃つ。
cp "$TMP/base-filled.html" "$TMP/ct36.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div foo=bar"z"class="ref-grid">#; END { exit($n==1?0:9) }' "$TMP/ct36.html" \
  || ng "CT36 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT36 ★unquoted 属性値への quote 混入 (幽霊 class marker) を属性 tokenize の同型化が捕捉" "$TMP/ct36.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# CT37. ★foreign 包みによる人間層 block の ★章外 relocation — block を chapbody の外 (章直下) へ出して
#   `<svg>…</svg>` で包み、 抜けた分の位置へ空 div を filler として挿す。 foreign root を depth-1 の子として
#   ★計上しない 実装では kids / cbkids が一切動かず rc=0 / 0 FAIL になる。 ★CT35 と別 shape:
#   CT35 は「器を増やす」向き、 本 shape は「本文を器の外へ出す」向き (捕捉は breakout 開始タグ規則)。
cp "$TMP/base-filled.html" "$TMP/ct37.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div data-component="spec-subhead"><h3 id="s4-6-a11y">.*?</div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s5-delta" class="normative">)#${1} . "<div></div>\n</div>\n<svg>" . $mv . "</svg>\n" . ${2}#e;
END { exit($n==2?0:9) }' "$TMP/ct37.html" \
  || ng "CT37 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT37 ★svg 包みによる人間層 block の章外 relocation (filler で子数を保つ形) を tokenizer が fail-closed" "$TMP/ct37.html" "containment tokenizer の構造診断"
# ★CT38 / CT39 — ★filler 置換による relocation (「完全子数」束縛が ★数 だけ を束縛し ★identity を束縛しない
#   fail-open の封鎖)。 CT30 / CT31 は ★filler 無し の 1 instance にすぎず、 抜けた位置へ ★空 <div> を 1 個 挿す
#   だけで 章直下 (kids) / band 直下 (bkids) / chapbody 直下 (cbkids) の ★どの子数も 動かないまま block 退避が
#   成立する。 現在は chapbody 直下を ★marker 列 (要素名 + data-component/class の ★逐値・順序) で束縛するので、
#   filler は無印 (`div:-`) として列に現れ 期待列と割れる。 ★2 shape を別実弾で撃つ: 退避先が (CT38) ★同章の
#   machine-fold の中 = ★既定非表示の <details> へ人間層見出しが消える形 / (CT39) ★兄弟 block (div.tbl-wrap) の
#   subtree の中。 ★どちらも 文書全体の component census (spec-subhead == Σ subhead blocks) は ★保たれる
#   (削除でなく移動) ため census 側では捕まらない = ★列 pin ★単独 の teeth。
cp "$TMP/base-filled.html" "$TMP/ct38.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s4-format" class="normative">.*?)(<div data-component="spec-subhead"><h3 id="s4-6-a11y">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}<div></div>\n${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct38.html" \
  || ng "CT38 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT38 ★filler 付き machine-fold 退避 (子数を保つ relocation) を契約由来 完全子列が捕捉" "$TMP/ct38.html" "章 's4-format' の chapbody 直下は 契約由来の完全子列"
cp "$TMP/base-filled.html" "$TMP/ct39.html"
perl -0777 -i -pe 'our ($n, $mv);
if (s#(<section id="s4-format" class="normative">.*?)(<div data-component="spec-subhead"><h3 id="s4-6-a11y">[^\n]*\n)(<details data-component="spec-machine-fold")#${1}<div></div>\n${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s4-format" class="normative">.*?<div class="tbl-wrap">)#${1} . $mv#se;
END { exit($n==2?0:9) }' "$TMP/ct39.html" \
  || ng "CT39 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT39 ★filler 付き兄弟 block (tbl-wrap) subtree 退避を契約由来 完全子列が捕捉" "$TMP/ct39.html" "章 's4-format' の chapbody 直下は 契約由来の完全子列"
# CT40. ★属性値の文字参照 (「解決しないのは常に fail-closed 側」という ★方向分析の誤り の封鎖)。
#   `class="ref&#45;grid"` は 実 DOM (convert_charrefs) では `.ref-grid` ゆえ 器が ★2 個 になるが、 文字参照を
#   解決しない probe は これを ★数え落とす。 期待値が「== 1」の ★上限型 arm (docct) では 数え落とし =
#   ★追加された容器が invisible ゆえ ★silent PASS へ倒れる。 現在は属性値の文字参照を解決して 文書総数 pin が
#   loud に落とす。 ★CT21 と別 shape: CT21 は marker を ★逐値のまま 増やす形、 本 shape は marker を ★参照で
#   綴って probe の目から隠す 形 (捕捉する arm は同じでも 突く非同型が別)。
cp "$TMP/base-filled.html" "$TMP/ct40.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref&\#45;grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$TMP/ct40.html" \
  || ng "CT40 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT40 ★文字参照で綴った marker (class=\"ref&#45;grid\") による器の重複を属性値 charref 解決が捕捉" "$TMP/ct40.html" "ref-grid が ★文書全体で 1 個"
# CT41. ★attribute-name state の parser-differential = ★幽霊 marker の ★第 2 vector (CT36 が塞ぐのは ★値 state
#   だけ で ★名前 state は別)。 `<div a""class="ref-grid">` の実 DOM 属性は `a""class="ref-grid"` の ★1 本だけ
#   (HTML5 の attribute-name state は `"` を ★名前文字 として取り込む) ゆえ ★class 属性は存在しない のに、
#   raw タグ文字列を「どこからでも」属性名 regex で走査する実装は 文字列途中の `class="ref-grid"` を拾って
#   ★実 DOM に無い marker を数える。 現在は タグ名直後から name/value state を ★順に消費する ので class は
#   見つからず、 器の実在 arm が loud に落ちる。
cp "$TMP/base-filled.html" "$TMP/ct41.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div a""class="ref-grid">#; END { exit($n==1?0:9) }' "$TMP/ct41.html" \
  || ng "CT41 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT41 ★attribute-name state への quote 混入 (幽霊 marker 第 2 vector) を逐次属性 parser が捕捉" "$TMP/ct41.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# CT42. ★タグ境界の quote 走査 — CT36 / CT41 が塞ぐのは ★属性値の読み取り ($attr) 側 であって、 ★タグの終端位置
#   を決める走査は別コード。 実 parser では `=` を伴わない `"` は ★属性名文字 でタグは閉じず、 その後の最初の
#   `>` が終端する ので、 genuine タグへ ` x=1 "></section>"` を 1 個足すだけで 実 DOM では ★そこで章が閉じ
#   chapbody / chip が章の外へ出る のに、 state 無し走査は `</section>` を ★quote の中 と見なして region を
#   元の閉じタグまで伸ばし ★containment 9 arm が全て期待値どおり になる (★1 行 bypass)。 現在はタグ境界を HTML5 の
#   attribute-name / value state に同型化したので 実 DOM と同じ位置で終端し、 章内に取り残された chapbody が
#   ★深さ 1 の未閉じ子 (unclosed-child-div) として err に立つ。 ★CT16 / CT32-35 / CT37 と ★別 shape:
#   それらは 自己閉じ構文 / void / foreign の各規則を突く形で、 本 shape は ★属性 state を突いて ★実在する
#   閉じタグを隠す 形 (tokenizer の state 機を消すと本 case ★だけ が緑へ戻る = per-shape MK)。
cp "$TMP/base-filled.html" "$TMP/ct42.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div class="ref-grid" x=1 "></section>">#; END { exit($n==1?0:9) }' "$TMP/ct42.html" \
  || ng "CT42 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT42 ★タグ境界 quote 走査の state 非同型による閉じタグ隠蔽 (1 行 bypass) を tokenizer が捕捉" "$TMP/ct42.html" "containment tokenizer の構造診断"
# ★CT43〜CT45 — ★block wrapper の中身 の帰属。
#   ★根本原因: chapbody 直下の marker 列 (cbkids) は「器がそこに在る」までしか言わず ★器の中身 を束縛しない。
#   かつ [table]=div.tbl-wrap / [requirements]=div.rq-list は ★wrapper class 自身の 文書 census を持たない
#   (census は内側の spec-table / ears-requirement-row を数える) ため、 ★空の器を filler に残して 中身を
#   machine-fold (既定折り畳み) へ移す形が ★全 arm 素通り する。
#   ★3 shape を別実弾で撃つ: 器の class (rq-list / tbl-wrap) と 逃がし方 (器ごと / 中身だけ) が別クラスで、
#   1 本の実弾は他 2 つの穴を証明しない (per-shape 規律 = jyfh / r8k)。
# CT43. (A) ★rq-list ごと machine-fold へ + 空 rq-list filler — EARS 規範要件が ★既定折り畳みへ silent 退避 する形。
cp "$TMP/base-filled.html" "$TMP/ct43.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s10-mandatory" class="normative">.*)<div class="rq-list">\n(.*?)\n</div>\n(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}<div class="rq-list"></div>\n${3}<div class="rq-list">\n${2}\n</div>\n#s; END { exit($n==1?0:9) }' "$TMP/ct43.html" \
  || ng "CT43 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT43 ★rq-list ごと machine-fold へ退避 + 空 filler (規範要件の silent 折り畳み) を器中身の占有 pin が捕捉" "$TMP/ct43.html" "EARS 要件 row の ★器ごとの個数列 が章 's10-mandatory' の 要件リストの器 (div.rq-list) 群"
# CT44. (B) ★tbl-wrap ごと machine-fold へ + 空 tbl-wrap filler — ★器の文書総数 pin が単独で担う向き
#   (中身は器ごと移るので「器の中の payload」も落ちるが、 ★reason anchor は文書 census 側に取り 器自身の
#   census 欠落こそが root cause であることを pin する)。
cp "$TMP/base-filled.html" "$TMP/ct44.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s4-format" class="normative">.*?)(<div class="tbl-wrap">.*?</table></div>\n)#${1}<div class="tbl-wrap"></div>\n#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s4-format" class="normative">.*?<div class="machine-body">\n)#${1}$mv#s;
END { exit($n==2?0:9) }' "$TMP/ct44.html" \
  || ng "CT44 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT44 ★tbl-wrap ごと machine-fold へ退避 + 空 filler を器自身の文書 census が捕捉" "$TMP/ct44.html" "表の器 (div.tbl-wrap) が ★文書全体で"
# CT45. (C) ★器は据置で 中身の table だけ machine-fold へ (hollow wrapper 残置) — 器の個数も文書総数も
#   ★一切動かない ので ★器中身の占有 pin ★単独 が唯一の FAIL 源。
#   ★CT11 / CT12 の hollow container 原理が ★契約章の block wrapper に未適用 だった穴。
cp "$TMP/base-filled.html" "$TMP/ct45.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s4-format" class="normative">.*?<div class="tbl-wrap">)(<table data-component="spec-table">.*?</table>)(</div>\n)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s4-format" class="normative">.*?<div class="machine-body">\n)#${1}$mv\n#s;
END { exit($n==2?0:9) }' "$TMP/ct45.html" \
  || ng "CT45 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT45 ★hollow block wrapper (tbl-wrap 据置で中の table だけ fold へ) を器中身の占有 pin が単独で捕捉" "$TMP/ct45.html" "表 (spec-table) の ★器ごとの個数列 が章 's4-format' の 表の器 (div.tbl-wrap) 群"
# ★CT46 / CT47 — ★同章内の 器 → 器 payload 再配分 (shape D)。
#   ★根本原因: 器中身の占有 pin を 章単位の ★合計 (depth-1 全器の加算) で置くと、 同一章に同型の器が ★2 本以上
#   ある章で「1 本目へ寄せて 2 本目を空の器として残す」再配分が ★合計不変 で素通る。 ★現在は 期待値を
#   ★器ごとの個数列 (document 順・contract の per-block 導出) にしたので 列の逐値差で落ちる。
#   ★dispatch fence の前提「rules は同型器 2 本以上の章 = 0 件 = shape D は構成不能」は ★contract 実測と
#   食い違う (表の器 2 本 = s9-xref / 要件リストの器 2 本 = s9-xref・4 本 = s10-mandatory)。 ゆえ「構造免疫」
#   と宣言せず ★実弾を 2 本 置く。 ★2 instance は ★payload クラスが別 (table / EARS 要件 row) ゆえ
#   1 本の実弾は他方の穴を証明しない (器 1 本の章は 合計 == 器単位 で本 shape に構成上 免疫)。
# CT46. 表の器 2 本の s9-xref — 2 本目の table を 1 本目へ寄せ、 2 本目を ★空の器 として残す (期待 1,1 → 実 2,0)。
cp "$TMP/base-filled.html" "$TMP/ct46.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s9-xref" class="normative">.*?<div class="tbl-wrap">.*?</tbody></table></div>\n.*?<div class="tbl-wrap">)(<table data-component="spec-table">.*?</tbody></table>)(</div>\n)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s9-xref" class="normative">.*?<div class="tbl-wrap"><table data-component="spec-table">.*?</tbody></table>)(</div>\n)#${1}$mv${2}#s;
END { exit($n==2?0:9) }' "$TMP/ct46.html" \
  || ng "CT46 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT46 ★同章内の 器 → 器 payload 再配分 (s9-xref・表の器 2 本) を器ごとの個数列が捕捉" "$TMP/ct46.html" "表 (spec-table) の ★器ごとの個数列 が章 's9-xref' の 表の器 (div.tbl-wrap) 群"
# CT47. 要件リストの器 4 本の s10-mandatory — 2 本目の EARS 要件 row を 1 本目へ寄せ、 2 本目を ★空の器 として
#   残す (期待 3,1,7,1 → 実 4,0,7,1)。 ★CT46 と ★payload クラスが別 (table でなく ears-requirement-row)。
cp "$TMP/base-filled.html" "$TMP/ct47.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<div data-component="ears-requirement-row" id="req-ci-001".*?\n</div>\n)(</div>\n<div class="tbl-wrap">)#${2}#s) { $mv = $1; $n++ }
$n++ if defined $mv && s#(<div data-component="ears-requirement-row" id="req-cm-003".*?\n</div>\n)#${1}$mv#s;
END { exit($n==2?0:9) }' "$TMP/ct47.html" \
  || ng "CT47 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT47 ★同章内の 器 → 器 payload 再配分 (s10-mandatory・要件リストの器 4 本) を器ごとの個数列が捕捉" "$TMP/ct47.html" "EARS 要件 row の ★器ごとの個数列 が章 's10-mandatory' の 要件リストの器 (div.rq-list) 群"
# CT48. ★β-1 クラス (marker 付き filler を ★同一行 に置く relocation) — CENSUS_BACKED_MARK の免除根拠が
#   ★occurrence 単位 census であることの per-shape MK。 ★CT38 / CT39 と別 shape: あちらの filler は ★無印
#   (`div:-`) ゆえ chapbody 直下の ★marker 列 が割れて落ちるが、 本 shape の filler は ★同型 marker
#   (`div:spec-subhead`) を持つので 列は ★1 byte も変わらない。 唯一の依り所は marker の ★文書 census だが、
#   「1. 行数」節の census は ★grep -c = 行単位 ゆえ filler を ★既存 subhead と同一の物理行 に置くと
#   ★行数が変わらず 素通る (self-review round-1 blocking の ★実弾 = 旧版は census arm も cbkids も PASS で、
#   落ちていたのは開示に書かれていない ★内容順序 arm だけ だった = 閉塞主張の帰属が誤り)。 ★現在は
#   census-count 節が CENSUS_BACKED_MARK 全 member に ★occurrence 単位 census を機械生成するので
#   spec-subhead の占有が 23 → 24 で loud に落ちる。 ★reason anchor は ★実際に落ちる arm (occurrence census)
#   に取る — 内容順序 arm へ anchor すると 本 CT が occurrence census の ★担い手を pin しない。
#   ★fired-guard は 3 置換 (§4.4 subhead 摘出 / §4.3 subhead と同一行への filler 挿入 / machine-fold への退避)。
cp "$TMP/base-filled.html" "$TMP/ct48.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div data-component="spec-subhead"><h3>§4\.4 [^\n]*\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(<div data-component="spec-subhead"><h3>§4\.3 [^\n]*)\n#${1} . "<div data-component=\"spec-subhead\"></div>\n"#se;
$n++ if defined $mv && s#(<section id="s4-format" class="normative">.*?<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1} . $mv#se;
END { exit($n==3?0:9) }' "$TMP/ct48.html" \
  || ng "CT48 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT48 ★同型 marker 付き filler を ★同一行 に置く relocation (行単位 census / 列 pin の同時素通り) を occurrence 単位 census が捕捉" "$TMP/ct48.html" "census-count(occurrence): spec-subhead == |subhead blocks|"
# CT49. ★★errata-4 (admin gate round-1 blocking B1) — hollow figure (器据置・payload だけ machine-fold へ退避)。
#   spec-diagram は marker 自身が census を持つが census は ★器の実在しか拘束しない — 旧抽出 (文書横断) では
#   pre.mermaid + figcaption を fold へ移しても抽出列が不変で ★全 arm 素通り だった (rc=0 / 277 OK 実測 =
#   「余地を持たない」宣言への過大宣言)。 errata-4 で figcaption / source 抽出を ★figure 内側限定 へ anchored 化
#   = 本 shape は mermaid source 行列 arm が捕捉する (figure marker 据置ゆえ occurrence census / cbkids は不変 =
#   ★reason anchor は実際に落ちる内容 arm に取る)。 ★fired-guard は 2 置換 (最初の figure の hollow 化 /
#   payload の machine-body への退避 = 文書内に payload は実在し続ける)。
cp "$TMP/base-filled.html" "$TMP/ct49.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<figure data-component="spec-diagram" class="diagram">(.*?)</figure>#<figure data-component="spec-diagram" class="diagram"></figure>#s) { $mv = $1; $n++ }
$n++ if defined $mv && s#(<div class="machine-body">\n)#${1} . $mv . "\n"#se;
END { exit($n==2?0:9) }' "$TMP/ct49.html" \
  || ng "CT49 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT49 ★hollow figure (器据置・payload を machine-fold へ退避) を figure 内側限定抽出が捕捉 (errata-4)" "$TMP/ct49.html" "mermaid source 行列"
# CT50. ★A2 (MX5) — contract 件数 0 の census-backed 型へ marker 付き filler を 1 個注入 (cbkids に不可視の
#   machine-body 内側)。 occurrence census は ★文書の実占有 を数えるゆえ expected 0, got 1 で落ちる =
#   「0 件型は arm を作らない」向きの将来最適化を tracked 実弾で封鎖 (0/0 恒真でないことの pin・reason anchor は
#   occurrence census arm に取る)。
cp "$TMP/base-filled.html" "$TMP/ct50.html"
perl -0777 -i -pe 'our $n;
$n++ if s#(<div class="machine-body">\n)#${1} . "<p data-component=\"spec-prose\">occ-census-filler</p>\n"#se;
END { exit($n==1?0:9) }' "$TMP/ct50.html" \
  || ng "CT50 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT50 ★0 件 census-backed 型への marker 付き filler 注入を occurrence census が捕捉 (0/0 恒真でない)" "$TMP/ct50.html" "census-count(occurrence): spec-prose"
# CT51. ★★errata-5 (round-2 blocking B1p) — 同型器間の payload 移送 (figure#1 を hollow に残し中身を figure#2
#   内へ・payload 総数不変・doc 順保存)。 anchored 化 (errata-4) だけでは「どれかの figure 内側」しか要求せず
#   平坦連結が byte 不変で ★全 arm 素通り だった (実弾 rc=0/277 OK)。 errata-5 の器序数束縛により、 移送された
#   payload は器序数 2 を帯び 期待側 (block 序数 1) と割れて落ちる。 ★reason anchor は mermaid source 行列
#   (器序数束縛)。 fired-guard は 2 置換 (figure#1 hollow 化 / 中身を次の非 hollow figure 先頭へ挿入)。
cp "$TMP/base-filled.html" "$TMP/ct51.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<figure data-component="spec-diagram" class="diagram">(.*?)</figure>#<figure data-component="spec-diagram" class="diagram"></figure>#s) { $mv = $1; $n++ }
$n++ if defined $mv && s#(<figure data-component="spec-diagram" class="diagram">)(?!</figure>)#${1} . $mv#se;
END { exit($n==2?0:9) }' "$TMP/ct51.html" \
  || ng "CT51 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT51 ★同型器間 payload 移送 (figure hollow 化 + 隣の figure へ融合) を器序数束縛が捕捉 (errata-5)" "$TMP/ct51.html" "mermaid source 行列"
# CT52. ★★errata-5 / A-1 — code の同型器間移送 (pre#1 の code 内容を空にし行を pre#2 の code 先頭へ融合)。
#   旧形の実閉塞は frozen census (corpus 固有 literal) 側で、 宣言担体「code 行列」は行の平坦連結ゆえ素通り
#   だった (round-2 A-1 帰属誤り)。 器序数束縛により code 行列 arm 自身が捕捉する。 fired-guard は 2 置換。
cp "$TMP/base-filled.html" "$TMP/ct52.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<pre data-component="spec-code"><code>)(.*?)(</code></pre>)#${1} . ${3}#se) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<pre data-component="spec-code"><code>)(?!</code>)#${1} . $mv . "\n"#se;
END { exit($n==2?0:9) }' "$TMP/ct52.html" \
  || ng "CT52 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT52 ★code の同型器間移送 (pre hollow 化 + 隣の code へ行融合) を器序数束縛が捕捉 (errata-5 / A-1)" "$TMP/ct52.html" "code 行列"

# === MECHPIN. ★containment 検査機構の健全性 arm の ★tracked 静的 pin ===
#   「駆動表が全章を覆う」「probe が全章分の実測を出力」の 2 arm は ★artifact をどう改竄しても落ちない
#   (script 改変でしか落ちない) ため、 敵対 suite の構造上 per-shape MK を持てない。 その担保を worker の
#   ★untracked な self-test に置くと land 後にリポへ ★残らない ので、 tracked な本 suite で
#   ★arm の実在 と ★期待値が導出形であること を静的に pin する。
#   ★恒真化封鎖: file 全体の grep (-ge 1 / -q) では、 将来 ★コメント等に同じ文字列が 1 つ増えるだけで
#   成立してしまう (arm 本体が消えても緑)。 ゆえに (a) ★chk 行だけを awk で scope 切り出し (b) ★label と
#   期待値の導出形を ★同一行 に要求 (c) ★==1 の逐値 の 3 点で締める。
#   ★chk は label と期待値が ★行継続 (`\`) で分かれることがあるため、 継続行を ★論理行へ連結してから 抽出する
#   (1 行 awk だと label 行しか取れず「同一行に導出形を要求」が構造的に成立しない = 恒偽になる)。
mech_chk="$(awk '{ cur = $0; if (buf != "") cur = buf cur; if (cur ~ /\\$/) { sub(/\\$/, "", cur); buf = cur; next } buf = ""; print cur }' "$VER" | grep '^chk "')"
mech_cov="$(printf '%s\n' "$mech_chk" | grep -F 'containment 駆動表が全章を覆う' | grep -cF 'NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}')"
mech_prb="$(printf '%s\n' "$mech_chk" | grep -F 'containment probe が全章分の実測を出力' | grep -cE '\$\{#_CT_ID\[@\]\} \* [0-9]+ \+ \$\{#_XC_KEY\[@\]\} \* [0-9]+ \+ 1')"
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
# ★containment の ★駆動表被覆と ★器登録 の 2 宣言集合が ★verify script に実在すること の静的 pin
#   (CHAPBODY_KID_MARK / CENSUS_BACKED_MARK / BLOCK_WRAPPER_SPEC が消えると partial-enum guard が丸ごと
#   消えるが、 生成物は無改竄のままなので敵対 suite の CT 群では ★捕まらない = MECHPIN の領分)。
mech_decl=0
for _d in CHAPBODY_KID_MARK CENSUS_BACKED_MARK BLOCK_WRAPPER_SPEC PRESENTATION_WRAPPER_BAND_TINTS; do
  grep -qE "^(declare -A )?${_d}=\(" "$VER" && mech_decl=$((mech_decl+1))
done
if [[ "$mech_decl" -eq 4 ]]; then ok "MECHPIN ★containment の宣言集合 4 本 (CHAPBODY_KID_MARK / CENSUS_BACKED_MARK / BLOCK_WRAPPER_SPEC / PRESENTATION_WRAPPER_BAND_TINTS) が verify に実在"
else ng "MECHPIN ★containment の宣言集合が欠落 (実測 $mech_decl / 期待 4 — partial-enum guard の消失は CT 群では捕まらない)"; fi

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
# --- CEN-escrt. ★escape literal 軸 (handle_data/entityref/charref) の inert guard を per-shape で撃つ (errata-1 SHOULD-1) ---
#   MUST-1 で head scoping が消えた後も、 escape 軸には ★load-bearing な guard が残る (実測: 3 hook から
#   `not self.inert()` を外すと <template> / 自己閉じ <script/> 内の &lt;span / &lt;code が ★共に 1 へ計上される)。
#   ゆえに「不要」ではなく ★追加が必要 と判断した。 element 軸 (CEN-rt-*-el) / text-inline 軸 (CEN-rt-*-tx) は
#   別実装ゆえ escape 軸の穴を証明しない。 ★全 raw text tag + 入れ子形 を per-shape で撃つ。
cen_mut "CEN-escrt-script ★&lt;span literal 1 個潰し + 自己閉じ <script/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<script/>&lt;span </script>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-style ★&lt;span literal 1 個潰し + 自己閉じ <style/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<style/>&lt;span </style>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-xmp ★&lt;span literal 1 個潰し + 自己閉じ <xmp/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<xmp/>&lt;span </xmp>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-iframe ★&lt;span literal 1 個潰し + 自己閉じ <iframe/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<iframe/>&lt;span </iframe>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-noembed ★&lt;span literal 1 個潰し + 自己閉じ <noembed/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<noembed/>&lt;span </noembed>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-noframes ★&lt;span literal 1 個潰し + 自己閉じ <noframes/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<noframes/>&lt;span </noframes>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-textarea ★&lt;span literal 1 個潰し + 自己閉じ <textarea/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<textarea/>&lt;span </textarea>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-title ★&lt;span literal 1 個潰し + 自己閉じ <title/> decoy による復元を census escape が FAIL (★escape literal 軸)" \
  "s{&lt;span}{&lt;ZZSPAN}; s{(<body[^>]*>)}{\$1<title/>&lt;span </title>}" "census double-escape: &lt;span"
cen_mut "CEN-escrt-nest ★同 literal 潰し + <template><script/></template> 入れ子 decoy による復元を census escape が FAIL" \
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
