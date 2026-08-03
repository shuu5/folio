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

# ============================================================================
# ★CT1〜CT31 — ★containment (章化の実質) の ★arm ごと per-shape mutation-kill。
#   verify-relations.sh の containment 節 (開口隣接 / region 占有 / 1 段内側 / 3 レベル完全子数束縛) は
#   ★生成物の改竄で落ちる arm ゆえ、 ★各 arm に「その arm が [FAIL] 理由を担う」実弾を 1 本以上 与える
#   (arm を消すと本 suite が赤くなる = mutation-kill)。 ★全て fired-guard 付き (shape drift による空撃ちを検出)。
#   ★per-shape 規律 (jyfh / r8k): 1 instance の実弾は ★構造差のある instance の穴を証明しない — wrapper 2 章
#   (payload = ref-grid / glossary-term-table) と契約章 (payload = 章要旨 callout) は ★別クラス ゆえ別実弾で撃つ。
#   ★reason anchor は ★章名込み の label へ当てる (章非特定の語だと別章の巻き添え FAIL でも満たされ per-shape の
#   主張が pin されない)。
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
# CT2. ★chapbody だけの押し出し — 章帯は wrapper 内に ★残したまま 本文 (chapbody / ref-grid / chip 13) を外へ出す。
#   CT1 と ★別 shape: 開口隣接 pin は band が隣接したままなので ★PASS し、 region 占有 pin ★だけ が発火する
#   (= 2 段の pin が互いの巻き添えでなく ★独立に teeth を持つ ことの per-shape 実証)。
cp "$TMP/base-filled.html" "$TMP/ct2.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}</section>\n<div class="chapbody">#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct2.html" \
  || ng "CT2 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT2 ★章本文 (chapbody) だけの押し出しを containment region 占有 pin が捕捉 (band 隣接は保持)" "$TMP/ct2.html" "章 'forward-refs' region 内の chapbody == 1"
# CT3. ★用語集 wrapper の hollow 化 — CT1 と ★別 shape で撃つ: 包む payload が ref-grid でなく
#   glossary-term-table / .grow 20 行であり、 region 占有 pin の対象 marker が構造として別クラス。
cp "$TMP/base-filled.html" "$TMP/ct3.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="glossary-terms">\n#<section id="glossary-terms"></section>\n#; $n += s#</section>\n</div>\n<footer#</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct3.html" \
  || ng "CT3 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT3 ★用語集 wrapper の hollow 化を containment が捕捉 (別 payload shape)" "$TMP/ct3.html" "'glossary-terms' の開口直後に"
# CT4. ★band tint の逐値付け替え — 開口隣接 pin の ★識別成分 (どの章の帯か) だけ を崩す。 band は隣接したまま・
#   件数も不変ゆえ、 tint 逐値を pin していなければ ★全 gate 緑 (PRESENTATION_WRAPPER_BAND_TINTS の存在理由の実証)。
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
cp "$TMP/base-filled.html" "$TMP/ct6.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-violet"><span class="num">)7#${1}9#; END { exit($n==1?0:9) }' "$TMP/ct6.html" \
  || ng "CT6 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT6 ★band §番号の逐値書換を開口隣接 pin が捕捉 (節同一性成分)" "$TMP/ct6.html" "'forward-refs' の開口直後に"
# CT7. ★over-containment — forward-refs の閉じタグを外し glossary-terms を ★入れ子 にする (assembler の
#   printf </section> 1 行脱落と同 shape)。 押し出しの ★逆向き ゆえ region 占有の ★上限側 (== 1) だけ が発火する。
cp "$TMP/base-filled.html" "$TMP/ct7.html"
perl -0777 -i -pe 'our $n; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; $n += s#</section>\n</div>\n<footer#</section>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct7.html" \
  || ng "CT7 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT7 ★wrapper の入れ子化 (over-containment) を region 占有の上限側が捕捉" "$TMP/ct7.html" "章 'forward-refs' region 内の章帯 == 1"
# CT8. ★契約章の hollow 化 — 同一 DOM shape (band 1 + chapbody 1) を持つのは提示層 wrapper 2 本だけではない。
#   containment を 2 id の手書き列挙に留めると残り 7 章が無防備 (partial-enumeration trap) ゆえ、 契約章側にも実弾を置く。
cp "$TMP/base-filled.html" "$TMP/ct8.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-folio-vocab" class="normative">\n#<section id="s2-folio-vocab" class="normative"></section>\n#; $n += s#</section>\n<section id="s3-jsonld" class="normative">#<section id="s3-jsonld" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct8.html" \
  || ng "CT8 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT8 ★契約章 (s2-folio-vocab) の hollow 化を containment が捕捉 (2 id 列挙では届かない残り 7 章)" "$TMP/ct8.html" "'s2-folio-vocab' の開口直後に"
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
# CT11. ★hollow container (ref-grid) — container を即閉じし chip 13 を container の ★外 (chapbody 直下) へ出す。
#   「container の開きタグが在る」は「chip がその中に在る」を意味しない (2 段内側の再演)。
cp "$TMP/base-filled.html" "$TMP/ct11.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"></div>\n#; $n += s#</div>\n</div>\n</section>\n<section id="glossary-terms">#</div>\n</section>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$TMP/ct11.html" \
  || ng "CT11 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT11 ★hollow ref-grid (chip 13 を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/ct11.html" "前方照会 chip の ★全数"
# CT12. ★hollow container (glossary-term-table) — CT11 と ★別構造クラス (payload が chip でなく .grow 20 行)。
cp "$TMP/base-filled.html" "$TMP/ct12.html"
perl -0777 -i -pe 'our $n; $n += s#<div data-component="glossary-term-table">\n#<div data-component="glossary-term-table"></div>\n#; $n += s#</div>\n</div>\n</section>\n</div>\n<footer#</div>\n</section>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$TMP/ct12.html" \
  || ng "CT12 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT12 ★hollow glossary-term-table (.grow 20 を器の外へ) を payload 占有 pin が単独で捕捉" "$TMP/ct12.html" "用語集 行 (.grow) の ★全数"
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
# CT20. ★契約章の band tint 付け替え — 契約章 7 本の tint 逐値 pin (源 = contract sections[].tint) を ★単独で 撃つ。
#   §番号は変えないので §番号成分では落ちない = tint 成分 ★単独 の teeth を isolate する。
cp "$TMP/base-filled.html" "$TMP/ct20.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">\n<section data-component="chapter-deck-band" class="tint-)violet(")#${1}ok${2}#; END { exit($n==1?0:9) }' "$TMP/ct20.html" \
  || ng "CT20 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT20 ★契約章 (s2-folio-vocab) の band tint 付け替えを tint 逐値 pin が単独で捕捉" "$TMP/ct20.html" "'s2-folio-vocab' の開口直後に"
# CT21. ★器の重複 — 正規の ref-grid は ★中身ごと 正しい位置に残したまま、 文書の別位置に ★2 個目の ref-grid を
#   足す。 per-章 arm (chapbody 内に 1 個 / chip 全数が器の中) は ★全て PASS のままで、 2 個目の器は以後の改竄で
#   payload の ★逃げ場 として使える (漏出先の先置き)。 捕捉は ★文書総数 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/ct21.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref-grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$TMP/ct21.html" \
  || ng "CT21 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT21 ★payload container の重複 (漏出先の先置き) を文書総数 pin が単独で捕捉" "$TMP/ct21.html" "ref-grid が ★文書全体で 1 個"
# ★comment 終端の HTML5 非同型 (範型 A)。 `-->` 一本終端の実装は、 実 parser が ★早く 終端する形
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
# ★RAWTEXT 終了タグの ★要素名境界 (範型 C)。 `</name[^>]*>` は `</textareax>` にも一致して早期終了し、 以降の
#   擬似タグを実タグとして数える。 ★region を ★伸ばす 向き (開きタグ密輸) で撃つ = over-slice の実害形。
cp "$TMP/base-filled.html" "$TMP/ct25.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea></textareax><section><textarea></textarea>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct25.html" \
  || ng "CT25 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT25 ★RAWTEXT 終了タグの要素名境界 (</textareax>) を突く region 伸長を containment が捕捉" "$TMP/ct25.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# ★foreign content (範型 D)。 svg / math subtree 内の要素は HTML 名前空間ではないので章の深さに数えてはならない。
#   ★genuine 生成物に svg アイコンが多数実在する ため「現れないから拒否」では閉じられず subtree 追跡が要る。
cp "$TMP/base-filled.html" "$TMP/ct26.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<svg><section></svg>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$TMP/ct26.html" \
  || ng "CT26 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT26 ★foreign content (svg subtree) 内の擬似タグによる region 伸長を containment が捕捉" "$TMP/ct26.html" "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個"
# CT27. ★契約章の 1 段内側 — 契約章 7 本は chapbody を空にして章本文を sibling へ押し出す改竄が素通る形。
#   ★wrapper 側 (CT9) と ★別実弾 で撃つ = 器の種類が別クラス (章要旨 callout vs ref-grid)。
#   ★タグ均衡を保つため 2 置換 (開口直後で閉じる + 元の chapbody 閉じを除去) を fired-guard で ★両方要求する。
cp "$TMP/base-filled.html" "$TMP/ct27.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n<div class="chapbody">)\n(<div data-component="section-essence-callout">)#${1}</div>\n${2}#; $n += s#</div>\n</section>\n<section id="s3-jsonld" class="normative">#</section>\n<section id="s3-jsonld" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct27.html" \
  || ng "CT27 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT27 ★契約章 (s2-folio-vocab) の chapbody 空化 + 章本文 sibling 押し出しを 1 段内側 pin が捕捉" "$TMP/ct27.html" "章要旨 callout が章 's2-folio-vocab' の chapbody 内に 1 個"
# CT28. ★章本文の relocation ★クラス — CT27 (chapbody 完全空化) は ★1 instance にすぎない。 章要旨 callout は
#   chapbody 内に ★残したまま、 それ以降の章本文 (subhead / table / details) だけを chapbody の外へ押し出す shape は、
#   callout 由来の 1 段内側 pin (cbadj / cont / docct) を ★全て PASS させたまま素通る。
#   捕捉は「章の直下は 章帯 + chapbody の 2 子だけ」の構造 pin ★単独。
cp "$TMP/base-filled.html" "$TMP/ct28.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)#${1}</div>\n#s; $n += s#</div>\n</section>\n<section id="s3-jsonld" class="normative">#</section>\n<section id="s3-jsonld" class="normative">#; END { exit($n==2?0:9) }' "$TMP/ct28.html" \
  || ng "CT28 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT28 ★章要旨を残した章本文の relocation (block 粒度) を章直下 2 子の構造 pin が捕捉" "$TMP/ct28.html" "章 's2-folio-vocab' の直下は 章帯 + chapbody の 2 子だけ"
# CT29. ★relocation クラスの ★もう一方の向き — 章本文の押し出し先を ★章直下の sibling でなく ★章帯 (band) の
#   ★中 にする。 章直下は band + chapbody のままなので kids pin (CT28) は ★2 を保ったまま PASS し、 1 段内側
#   pin も callout が chapbody 内に残るため全て PASS する。 捕捉は band の直下 4 子固定
#   (共有 CORE lib/common.sh band() = num/kicker/h2/lead) ★単独。
cp "$TMP/base-filled.html" "$TMP/ct29.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">\n<section data-component="chapter-deck-band"[^\n]*?)(</section>\n)(<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)(.*?)(</div>\n</section>\n<section id="s3-jsonld" class="normative">)#${1}${4}${2}${3}${5}#s; END { exit($n==1?0:9) }' "$TMP/ct29.html" \
  || ng "CT29 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT29 ★章本文の band subtree への退避 (kids を 2 に保つ向き) を band 4 子固定が捕捉" "$TMP/ct29.html" "章 's2-folio-vocab' の章帯の直下は num/kicker/h2/lead の 4 子だけ"
# CT30 / CT31. ★document 順を ★保つ relocation 2 形 — 章直下 (kids) / band 直下 (bkids) を固定しても、
#   ★他の probe 値を一切動かさずに 素通る形が残る。
#   CT30 (β) = 章本文を ★別章の chapbody へ移送 (donor 章が空章化し中身が受け側の下に付く)。
#   CT31 (γ) = 章本文を ★同章の machine-fold (details) の中へ退避。
#   捕捉は chapbody 直下の ★契約由来 完全子列 ★単独 (β は donor の列が縮み・γ は fold へ吸い込まれた分だけ列が縮む)。
cp "$TMP/base-filled.html" "$TMP/ct30.html"
perl -0777 -i -pe 'our $n;
if (s#(<section id="s2-folio-vocab" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)((?:.(?!</div>\n</section>\n<section id="s3-jsonld" class="normative">))*.)(\n</div>\n</section>\n<section id="s3-jsonld" class="normative">)#${1}${3}#s) {
  our $moved = $2; $n++;
  $n++ if s#(<section id="s3-jsonld" class="normative">.*?<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*\n)#${1}$moved\n#s;
}
END { exit($n==2?0:9) }' "$TMP/ct30.html" \
  || ng "CT30 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT30 ★章本文の別章 chapbody への移送 (document 順保存) を契約由来 完全子列が捕捉" "$TMP/ct30.html" "章 's2-folio-vocab' の chapbody 直下は 契約由来の完全子列"
cp "$TMP/base-filled.html" "$TMP/ct31.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">.*?)(<div data-component="spec-subhead">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct31.html" \
  || ng "CT31 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT31 ★章本文の machine-fold 内への退避 (document 順保存) を契約由来 完全子列が捕捉" "$TMP/ct31.html" "章 's2-folio-vocab' の chapbody 直下は 契約由来の完全子列"
# CT32. ★void 要素による ★計数マスク (errata: 3 レベル完全子数束縛の fail-open)。 深さ 1 の計数は ★同名深さ計数 ゆえ、
#   depth-1 に ★対応閉じタグを持たない 要素 (`<br>` / `<hr>` / `<img>` …) が 1 個現れると その時点で走査が
#   ★打ち切られる。 攻撃者は 「章本文 block を 1 個 chapbody の外 (章直下の sibling) へ出し、 抜けた分の位置に
#   void を 1 個挿す」 だけで kids / cbkids を ★期待値ちょうどに保てる — 封鎖前は この 2 置換 + void 2 個 で
#   ★rc=0 / 0 FAIL (containment 9 arm 全緑) を実測した。 現在は打ち切りを err (`unclosed-child-*`) へ倒す
#   fail-closed で捕捉する。 ★CT16 と ★別 shape: CT16 は 自己閉じ構文 (`<div/>`) の ★拒否 で、 本 shape は
#   ★正当な HTML (void 要素) を使った ★計数の打ち切り であり、 CT16 を消しても本 shape は err で落ちる関係にない
#   (両者は同じ err arm の ★別 vector)。 ★fired-guard は 3 置換 (block 摘出 / 器の外への再配置 + void / band 直後 void) を要求する。
cp "$TMP/base-filled.html" "$TMP/ct32.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div data-component="spec-subhead"><h3 id="s2-2-naming-rules">.*?</div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s3-jsonld" class="normative">)#${1} . "<br>\n</div>\n" . $mv . ${2}#e;
$n += s#(<section id="s2-folio-vocab" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<br>\n#;
END { exit($n==3?0:9) }' "$TMP/ct32.html" \
  || ng "CT32 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT32 ★void 要素 2 個による深さ 1 計数の打ち切り (章本文 relocation のマスク) を tokenizer が fail-closed" "$TMP/ct32.html" "containment tokenizer の構造診断"
# ★CT33〜CT37 — ★foreign content (svg / math) と ★属性 tokenize の parser-differential (errata: containment 9 arm が
#   ★1 行で全 bypass される fail-open の封鎖)。 ★4 shape を別実弾で撃つ: (a) foreign root を depth-1 の ★filler に
#   使う計数マスク / (b) foreign 内の ★any-other-end-tag による外側 section の閉鎖 / (c) foreign 内の ★breakout
#   開始タグによる器の重複 / (d) foreign 包みによる ★人間層 block の章外 relocation。 いずれも ★別の parser 規則を
#   突く ので 1 本の実弾は他 3 つの穴を証明しない。 加えて (e) unquoted 属性値の char class 差 = ★幽霊 marker。
# CT33. ★foreign root を depth-1 の filler にする ★計数マスク — 章本文 block を 1 個 machine-fold へ退避させ
#   (CT31 と同じ向き)、 抜けた位置へ ★`<svg><path/></svg>` (genuine と同形・breakout タグを含まない) を挿す。
#   foreign root を ★深さ 1 の子として 1 計上する と cbkids は期待値ちょうどに戻る ため ★完全子数束縛では
#   原理的に見分けられない (実測: depth-1 err を抜いた copy では ★220 OK / 0 FAIL)。 逆に root を計上しないと
#   CT37 の向き (svg 包みで章外へ出す形) が素通る — ★両方向を閉じるのは 計上 + depth-1 err の ★対 のみ。
cp "$TMP/base-filled.html" "$TMP/ct33.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">.*?)(<div data-component="spec-subhead">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}<svg viewBox="0 0 24 24"><path d="M4 4h16"/></svg>\n${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct33.html" \
  || ng "CT33 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT33 ★foreign root (svg) を depth-1 filler にした完全子数マスクを tokenizer が fail-closed" "$TMP/ct33.html" "containment tokenizer の構造診断"
# CT34. ★any other end tag による foreign からの breakout — `<svg></section></svg>` は 実 HTML5 parser では
#   stack を遡って ★外側の HTML section を閉じる (HTML5 tree construction "in foreign content" の任意終了タグ規則)
#   ため、 章本文 ★全部 が章の外へ出る = CT2 / CT9 が捕捉すると主張している relocation クラスそのもの。
#   subtree を丸ごと読み飛ばす実装では ★不可視 で rc=0 / 0 FAIL だった (実測 verified)。
cp "$TMP/base-filled.html" "$TMP/ct34.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<svg></section></svg>\n#; END { exit($n==1?0:9) }' "$TMP/ct34.html" \
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
#   ★計上しない 実装では kids / cbkids が一切動かず rc=0 / 0 FAIL だった (実測 verified)。 ★CT35 と別 shape:
#   CT35 は「器を増やす」向き、 本 shape は「本文を器の外へ出す」向き (捕捉は breakout 開始タグ規則)。
cp "$TMP/base-filled.html" "$TMP/ct37.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div data-component="spec-subhead"><h3 id="s2-2-naming-rules">.*?</div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s3-jsonld" class="normative">)#${1} . "<div></div>\n</div>\n<svg>" . $mv . "</svg>\n" . ${2}#e;
END { exit($n==2?0:9) }' "$TMP/ct37.html" \
  || ng "CT37 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT37 ★svg 包みによる人間層 block の章外 relocation (filler で子数を保つ形) を tokenizer が fail-closed" "$TMP/ct37.html" "containment tokenizer の構造診断"
# ★CT38 / CT39 — ★filler 置換による relocation (errata: 「完全子数」束縛が ★数 だけ を束縛し ★identity を
#   束縛しなかった fail-open の封鎖)。 CT30 / CT31 は ★filler 無し の 1 instance にすぎず、 抜けた位置へ
#   ★空 <div> を 1 個 挿すだけで 章直下 (kids) / band 直下 (bkids) / chapbody 直下 (cbkids) の ★どの子数も
#   動かないまま block 退避が成立した (封鎖前 実測: rc=0 / 220 OK / 0 FAIL)。 現在は chapbody 直下を
#   ★marker 列 (要素名 + data-component/class の ★逐値・順序) で束縛するので、 filler は無印 (`div:-`) として
#   列に現れ 期待列と割れる。 ★2 shape を別実弾で撃つ: 退避先が (CT38) ★同章の machine-fold の中 =
#   ★既定非表示の <details> へ人間層見出しが消える形 / (CT39) ★兄弟 block (div.tbl-wrap) の subtree の中。
#   ★どちらも 文書全体の component census (spec-subhead == Σ subhead blocks) は ★保たれる (削除でなく移動)
#   ため census 側では捕まらない = ★列 pin ★単独 の teeth。
cp "$TMP/base-filled.html" "$TMP/ct38.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-folio-vocab" class="normative">.*?)(<div data-component="spec-subhead">[^\n]*\n)(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#${1}<div></div>\n${3}${2}#s; END { exit($n==1?0:9) }' "$TMP/ct38.html" \
  || ng "CT38 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT38 ★filler 付き machine-fold 退避 (子数を保つ relocation) を契約由来 完全子列が捕捉" "$TMP/ct38.html" "章 's2-folio-vocab' の chapbody 直下は 契約由来の完全子列"
cp "$TMP/base-filled.html" "$TMP/ct39.html"
perl -0777 -i -pe 'our ($n, $mv);
if (s#(<section id="s2-folio-vocab" class="normative">.*?)(<div data-component="spec-subhead">[^\n]*\n)(<details data-component="spec-machine-fold")#${1}<div></div>\n${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s2-folio-vocab" class="normative">.*?<div class="tbl-wrap">)#${1} . $mv#se;
END { exit($n==2?0:9) }' "$TMP/ct39.html" \
  || ng "CT39 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT39 ★filler 付き兄弟 block (tbl-wrap) subtree 退避を契約由来 完全子列が捕捉" "$TMP/ct39.html" "章 's2-folio-vocab' の chapbody 直下は 契約由来の完全子列"
# CT40. ★属性値の文字参照 (errata: 「解決しないのは常に fail-closed 側」という ★方向分析の誤り の封鎖)。
#   `class="ref&#45;grid"` は 実 DOM (convert_charrefs) では `.ref-grid` ゆえ 器が ★2 個 になるが、 文字参照を
#   解決しない probe は これを ★数え落とす。 期待値が「== 1」の ★上限型 arm (docct) では 数え落とし =
#   ★追加された容器が invisible ゆえ ★silent PASS へ倒れた (封鎖前 実測: rc=0 / 0 FAIL)。 現在は属性値の
#   文字参照を解決して 文書総数 pin が loud に落とす。 ★CT21 と別 shape: CT21 は marker を ★逐値のまま 増やす形、
#   本 shape は marker を ★参照で綴って probe の目から隠す 形 (捕捉する arm は同じでも 突く非同型が別)。
cp "$TMP/base-filled.html" "$TMP/ct40.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref&\#45;grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$TMP/ct40.html" \
  || ng "CT40 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT40 ★文字参照で綴った marker (class=\"ref&#45;grid\") による器の重複を属性値 charref 解決が捕捉" "$TMP/ct40.html" "ref-grid が ★文書全体で 1 個"
# CT41. ★attribute-name state の parser-differential = ★幽霊 marker の ★第 2 vector (errata: CT36 が塞いだのは
#   ★値 state だけ で ★名前 state は開いたままだった)。 `<div a""class="ref-grid">` の実 DOM 属性は
#   `a""class="ref-grid"` の ★1 本だけ (HTML5 の attribute-name state は `"` を ★名前文字 として取り込む) ゆえ
#   ★class 属性は存在しない のに、 raw タグ文字列を「どこからでも」属性名 regex で走査する実装は 文字列途中の
#   `class="ref-grid"` を拾って ★実 DOM に無い marker を数えた (封鎖前 実測: 1 置換で rc=0 / 0 FAIL 全緑)。
#   現在は タグ名直後から name/value state を ★順に消費する ので class は見つからず、 器の実在 arm が loud に落ちる。
cp "$TMP/base-filled.html" "$TMP/ct41.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div a""class="ref-grid">#; END { exit($n==1?0:9) }' "$TMP/ct41.html" \
  || ng "CT41 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT41 ★attribute-name state への quote 混入 (幽霊 marker 第 2 vector) を逐次属性 parser が捕捉" "$TMP/ct41.html" "ref-grid が章 'forward-refs' の chapbody 内に 1 個"
# CT42. ★タグ境界の quote 走査 (errata 3・開示済み残差 ① の封鎖) — CT36 / CT41 が塞いだのは ★属性値の読み取り
#   ($attr) 側 であって、 ★タグの終端位置 を決める走査は別コードで state を持っていなかった。 実 parser では
#   `=` を伴わない `"` は ★属性名文字 でタグは閉じず、 その後の最初の `>` が終端する ので、 genuine タグへ
#   ` x=1 "></section>"` を 1 個足すだけで 実 DOM では ★そこで章が閉じ chapbody / chip 13 が章の外へ出る のに、
#   state 無し走査は `</section>` を ★quote の中 と見なして region を元の閉じタグまで伸ばし ★containment 9 arm が
#   全て期待値どおり になった (封鎖前 実測: rc=0 / 220 OK / 0 FAIL = ★1 行 bypass)。 現在はタグ境界を HTML5 の
#   attribute-name / value state に同型化したので 実 DOM と同じ位置で終端し、 章内に取り残された chapbody が
#   ★深さ 1 の未閉じ子 (unclosed-child-div) として err に立つ。 ★CT16 / CT32-35 / CT37 と ★別 shape:
#   それらは 自己閉じ構文 / void / foreign の各規則を突く形で、 本 shape は ★属性 state を突いて ★実在する
#   閉じタグを隠す 形 (tokenizer の state 機を消すと本 case ★だけ が緑へ戻る = per-shape MK)。
cp "$TMP/base-filled.html" "$TMP/ct42.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div class="ref-grid" x=1 "></section>">#; END { exit($n==1?0:9) }' "$TMP/ct42.html" \
  || ng "CT42 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT42 ★タグ境界 quote 走査の state 非同型による閉じタグ隠蔽 (1 行 bypass) を tokenizer が捕捉" "$TMP/ct42.html" "containment tokenizer の構造診断"
# ★CT43〜CT45 — ★block wrapper の中身 の帰属 (admin gate round-1 blocking / errata-1 の per-shape 封鎖)。
#   ★根本原因: chapbody 直下の marker 列 (cbkids) は「器がそこに在る」までしか言わず ★器の中身 を束縛しない。
#   かつ [table]=div.tbl-wrap / [requirements]=div.rq-list は ★wrapper class 自身の 文書 census を持たない
#   (census は内側の spec-table / ears-requirement-row を数える) ため、 ★空の器を filler に残して 中身を
#   machine-fold (既定折り畳み) へ移す形が ★全 arm 素通り だった。 ★封鎖前 (commit d4a6ef3) の実測は
#   3 shape とも rc=0 / 220 OK / 0 FAIL = ★clean baseline と完全一致 (arm skip ではなく全素通り)。
#   ★3 shape を別実弾で撃つ: 器の class (rq-list / tbl-wrap) と 逃がし方 (器ごと / 中身だけ) が別クラスで、
#   1 本の実弾は他 2 つの穴を証明しない (per-shape 規律 = jyfh / r8k)。
# CT43. (A) ★rq-list ごと machine-fold へ + 空 rq-list filler — EARS 規範要件 4 本が ★既定折り畳みへ silent 退避 する形。
cp "$TMP/base-filled.html" "$TMP/ct43.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="rq-list">\n(.*?)\n</div>\n(<details data-component="spec-machine-fold"[^\n]*\n<summary>[^\n]*\n<div class="machine-body">\n)#<div class="rq-list"></div>\n${2}<div class="rq-list">\n${1}\n</div>\n#s; END { exit($n==1?0:9) }' "$TMP/ct43.html" \
  || ng "CT43 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT43 ★rq-list ごと machine-fold へ退避 + 空 filler (規範要件の silent 折り畳み) を器中身の占有 pin が捕捉" "$TMP/ct43.html" "EARS 要件 row の ★器ごとの個数列 が章 's5-bidirectional' の 要件リストの器 (div.rq-list) 群"
# CT44. (B) ★tbl-wrap ごと machine-fold へ + 空 tbl-wrap filler — ★器の文書総数 pin が単独で担う向き
#   (中身は器ごと移るので「器の中の payload」も落ちるが、 ★reason anchor は文書 census 側に取り 器自身の
#   census 欠落こそが root cause だったことを pin する)。
cp "$TMP/base-filled.html" "$TMP/ct44.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s2-folio-vocab" class="normative">.*?)(<div class="tbl-wrap">.*?</table></div>\n)#${1}<div class="tbl-wrap"></div>\n#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s2-folio-vocab" class="normative">.*?<div class="machine-body">\n)#${1}$mv#s;
END { exit($n==2?0:9) }' "$TMP/ct44.html" \
  || ng "CT44 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT44 ★tbl-wrap ごと machine-fold へ退避 + 空 filler を器自身の文書 census が捕捉" "$TMP/ct44.html" "表の器 (div.tbl-wrap) が ★文書全体で"
# CT45. (C) ★器は据置で 中身の table だけ machine-fold へ (hollow wrapper 残置) — 器の個数も文書総数も
#   ★一切動かない ので ★器中身の占有 pin ★単独 が唯一の FAIL 源 (実測 FAIL 1 件 = 完全 isolation)。
#   ★CT11 / CT12 の hollow container 原理が ★契約章の block wrapper に未適用 だった穴。
cp "$TMP/base-filled.html" "$TMP/ct45.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s2-folio-vocab" class="normative">.*?<div class="tbl-wrap">)(<table data-component="spec-table">.*?</table>)(</div>\n)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s2-folio-vocab" class="normative">.*?<div class="machine-body">\n)#${1}$mv\n#s;
END { exit($n==2?0:9) }' "$TMP/ct45.html" \
  || ng "CT45 mutation が発火せず (shape drift = 空撃ち)"
expect_vfilled_fail "CT45 ★hollow block wrapper (tbl-wrap 据置で中の table だけ fold へ) を器中身の占有 pin が単独で捕捉" "$TMP/ct45.html" "表 (spec-table) の ★器ごとの個数列 が章 's2-folio-vocab' の 表の器 (div.tbl-wrap) 群"
# ★CT46 / CT47 — ★同章内の 器 → 器 payload 再配分 (errata-2・admin gate round-2 blocking = shape D / D2)。
#   ★根本原因: errata-1 の器中身 pin は 章単位の ★合計 (depth-1 全器の加算) だったため、 同一章に同型の器が
#   ★2 本以上 ある章で「1 本目へ寄せて 2 本目を空の器として残す」再配分が ★合計不変 で素通った
#   (封鎖前 = commit 7d754c7 の実測: 2 instance とも rc=0 / 228 OK / 0 FAIL = ★clean baseline と 1 arm も違わない。
#   可視には §1.2 の表が空になり §1.1 の見出し下へ誤帰属する破損が起きるのに無検査だった)。
#   ★現在は 期待値を ★器ごとの個数列 (document 順・contract の per-block 導出) にしたので 列の逐値差で落ちる。
#   ★2 instance を別実弾で撃つ: 器 3 本の章 (s1) と 器 5 本の章 (s4) は ★列長が異なり、 1 本の実弾は
#   他方の穴を証明しない (器 1 本の章は 合計 == 器単位 ゆえ本 shape に免疫 = 撃つ意味が無い)。
for _ctd in "CT46:s1-w3c-vocab:s1 (器 3 本)" "CT47:s4-inventory:s4 (器 5 本)"; do
  _ctid="${_ctd%%:*}"; _ctrest="${_ctd#*:}"; _ctsec="${_ctrest%%:*}"; _ctlbl="${_ctrest#*:}"
  cp "$TMP/base-filled.html" "$TMP/${_ctid}.html"
  CTSEC="$_ctsec" perl -0777 -i -pe 'our $n; our $mv; my $S = $ENV{CTSEC};
if (s#(<section id="\Q$S\E" class="normative">.*?<div class="tbl-wrap">.*?</tbody></table></div>\n.*?<div class="tbl-wrap">)(<table data-component="spec-table">.*?</tbody></table>)(</div>\n)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="\Q$S\E" class="normative">.*?<div class="tbl-wrap"><table data-component="spec-table">.*?</tbody></table>)(</div>\n)#${1}$mv${2}#s;
END { exit($n==2?0:9) }' "$TMP/${_ctid}.html" \
    || ng "$_ctid mutation が発火せず (shape drift = 空撃ち)"
  expect_vfilled_fail "$_ctid ★同章内の 器 → 器 payload 再配分 ($_ctlbl・2 本目を空の器として残す) を器ごとの個数列が捕捉" \
    "$TMP/${_ctid}.html" "表 (spec-table) の ★器ごとの個数列 が章 '$_ctsec' の 表の器 (div.tbl-wrap) 群"
done

# === MECHPIN. ★containment 検査機構の健全性 arm の ★tracked 静的 pin (範型 test-adversarial-verification.sh と同型) ===
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
# ★errata-1: 期待値は 章 row (11 値) に加え ★block wrapper row (2 値) を含む導出形になった。 pattern も同時に
#   更新する (片方だけ更新すると本 pin が ★恒偽 = 常に ng へ倒れ、 arm 消失の検出力を失う)。
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
