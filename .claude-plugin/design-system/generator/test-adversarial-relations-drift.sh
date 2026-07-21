#!/usr/bin/env bash
# test-adversarial-relations-drift.sh — folio-uryh F8 drift gate (verify-relations-drift.sh) の敵対回帰テスト。
# 姉妹 gate の test-adversarial-rules-drift.sh / test-adversarial-verification-drift.sh と対称に、 committed な
# per-shape mutation-kill を repo へ pin し gate の非 vacuous 性 (fail-closed の genuineness) を守る。
#
# gate 自体の正しさを検査する:
#   (a) precision: healthy canonical → exit 0 PASS (clean corpus を誤検出しない)。
#   (b) 物理指紋段 per-shape MK: fingerprint 4 clause を各 1 mutant で *独立* に撃つ。
#       1 instance (旧 canonical 全体) の実弾は構造差のある clause の穴を証明しない — per-shape 原則 (jyfh/r8k)。
#   (c) ★drift 段 per-shape MK: 物理指紋 4 clause を *全て温存* したまま relations 固有 DOM shape を 1 つずつ
#       改竄し、 byte 比較段で落ちる (= 指紋段で誤発火しない) ことを shape ごとに独立の実弾で pin する。
#       撃つ shape (assemble-relations 生成物での実在を確認済・実測件数):
#         ears-requirement-row (<div data-component=… 4) / cross-doc-ref-chip (<div data-component=… 13) /
#         grow (<div class="grow" 20) / prose-slot (data-prose-slot= 10) / section-anchor (<section id="s…" 26) /
#         spec-machine-list (<ul data-component=… 6) / li.mli (<li class="mli"> 25)。
#       ★ears-requirement-row と section-anchor は指紋段 MK (MK3/MK4) と byte 段 MK (MKB1/MKB5) を ★別立て で撃つ
#       (この 2 shape だけ失敗段が不均一 = 指紋 clause でもあるため。 片段のみだと他段の穴を証明できない)。
#   (d) exit-code 規約: 未知引数 → exit 2 (0/1/2 の分離)。
#
# ★fixture base = ★fresh 生成物 (live canonical を base にしない)。 pre-flip 期の live canonical は hand-authored
#   原本ゆえ H0 が恒 FAIL し、 全 MK は 0-match の vacuous mutation に退化する (contract 技術是正 #1)。 base は本
#   suite が full-repo staging から hermetic に再生成する (git-rev 非依存・commit 増加/history rewrite に不変)。
#
# ★byte-drift 判定は fixed-string 2 段 (contract 技術是正 #3): grep -qF 'byte 不一致' 単独 + ! grep -qF '物理指紋'。
#   positive anchor に 'drift' を使わない — gate 名 verify-relations-drift の fail() prefix が全 FAIL 行に出るため
#   'drift' は恒真 (verification 版 MK5 の 'drift|byte 不一致' は vacuous 実証済)。
#
# ★全 MK に fired-guard (contract 技術是正 #2): 改竄の perl 置換 match 数 > 0 を fail-closed に assert する。
#   母体相違 (selector rot / shape 変更で mutant が base と同一になる) を vacuous mutation として検出する。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-relations-drift.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
[[ -x "$GATE" ]] || { echo "FATAL: gate not executable: $GATE" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad() { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

echo "== relations drift gate 敵対回帰 (F8・folio-uryh) =="

# --- fixture base = fresh 生成物 (full-repo staging・hermetic) ---
# gate 内部と ★同一 pipeline (assemble-relations → inject-prose → folio fix --root → folio build --root)。
# base は「gate が exit 0 PASS を返す唯一の入力」= H0 の subject かつ全 MK の母体。
BSTG="$WORK/base"; mkdir -p "$BSTG"
( cd "$ROOT" && git ls-files -z | tar --null -T - -cf - ) | tar -x -C "$BSTG" 2>/dev/null \
  || { echo "FATAL: base staging 生成失敗 (git ls-files | tar)" >&2; exit 2; }
BGEN="$BSTG/.claude-plugin/design-system/generator"
"$BGEN/assemble-relations.sh" "$BGEN/contract/folio-relations.spec.yaml" "$BSTG/asm.html" >/dev/null 2>&1 \
  || { echo "FATAL: base assemble 失敗" >&2; exit 2; }
"$BGEN/inject-prose.sh" "$BGEN/prose/folio-relations.prose.yaml" "$BSTG/asm.html" "$BSTG/design-intent/spec/relations.html" >/dev/null 2>&1 \
  || { echo "FATAL: base inject 失敗" >&2; exit 2; }
( cd "$BSTG" && "$BSTG/.claude-plugin/bin/folio" fix --root design-intent >/dev/null 2>&1 && \
              "$BSTG/.claude-plugin/bin/folio" build --root design-intent >/dev/null 2>&1 ) \
  || { echo "FATAL: base fix/build 失敗" >&2; exit 2; }
BASE="$WORK/base.html"; cp "$BSTG/design-intent/spec/relations.html" "$BASE"
[[ -s "$BASE" ]] || { echo "FATAL: base fixture が空" >&2; exit 2; }
echo "  (fixture base = fresh 生成物 $(wc -c < "$BASE") byte)"

# --- 改竄 helper: perl 置換を適用し ★命中数 > 0 を fail-closed に assert (vacuous mutation 封鎖) ---
# $1=dst $2=perl 文 ($t を書き換え $N へ命中数を加算)。 母体は常に $BASE。 exit 9 = 0 命中 (fired-guard 発火)。
mutate() {
  local dst="$1" code="$2"
  MUT_CODE="$code" perl -e '
    my ($src,$dst)=@ARGV;
    open(my $i,"<:raw",$src) or die "open src: $!"; my $t=do{local $/;<$i>}; close $i;
    my $N=0;
    eval $ENV{MUT_CODE}; die "mutate eval error: $@" if $@;
    open(my $o,">:raw",$dst) or die "open dst: $!"; print $o $t; close $o;
    exit($N>0 ? 0 : 9);
  ' "$BASE" "$dst"
}

# --canon override を食わせ、 非零 exit かつ FAIL 行が clause 固有 substring を含むことを pin (指紋段用)。
expect_fp_fail() { # $1=label $2=canon-fixture $3=clause 固有 substring
  local out rc; out="$("$GATE" --canon "$2" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF -- "$3" <<<"$out"; then ok "$1"
  else bad "$1 (rc=$rc / clause substring '$3' の FAIL 行なし)"; fi
}

# byte 段 per-shape MK の共通 driver: 改竄 → fired-guard → 指紋 4 clause 温存のまま byte 段で FAIL することを pin。
# ★positive anchor 'byte 不一致' (fixed-string 単独) + ★negative anchor '物理指紋' 不在 の 2 段判定。
expect_byte_fail() { # $1=label $2=fixture 名 $3=perl 改竄文
  local f="$WORK/$2.html" out rc
  if ! mutate "$f" "$3"; then bad "$1 (fired-guard: 改竄が母体に 0 命中 = vacuous mutation)"; return; fi
  out="$("$GATE" --canon "$f" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qF 'byte 不一致' <<<"$out" && ! grep -qF '物理指紋' <<<"$out"; then ok "$1"
  else bad "$1 (rc=$rc / byte-drift 未捕捉 or 指紋段で誤発火)"; fi
}

# --- H0 precision: fresh 生成物 → exit 0 + PASS 行 (clean corpus を誤検出しない) ---
# ★これが成立して初めて全 MK が「healthy から 1 shape 崩した」実弾になる (base が FAIL なら MK は無意味)。
out="$("$GATE" --canon "$BASE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -qF 'PASS: design-intent/spec/relations.html == fresh 再生成' <<<"$out"; then
  ok "H0 precision: fresh 生成物 → exit 0 + PASS pin"
else bad "H0 precision: fresh 生成物が exit0 PASS でない (rc=$rc)"; fi

# ============================================================================
# (b) 物理指紋段 per-shape MK (fingerprint 4 clause を各 1 mutant で独立に撃つ)
# ============================================================================

# --- MK1 fingerprint clause(1): inline <style> 欠 → 物理指紋 FAIL ---
if mutate "$WORK/mk1.html" '$N += ($t =~ s{^<style>}{<style-rotted>}m);'; then
  expect_fp_fail "MK1 clause(1): 行頭 <style> 消失 → 物理指紋 FAIL" "$WORK/mk1.html" \
    '物理指紋: inline <style> block が無い'
else bad "MK1 (fired-guard: 0 命中)"; fi

# --- MK2 fingerprint clause(2): 行頭 <link> stylesheet 出現 → 物理指紋 FAIL ---
# 旧 hand-authored canonical の共通署名 (head col-0 の <link href="../../common.css">) を再注入。
# <style> は温存するため clause(1) を通過し、 clause(2) が genuine に落ちる。
if mutate "$WORK/mk2.html" '$N += ($t =~ s{\n}{\n<link rel="stylesheet" href="../../common.css">\n});'; then
  expect_fp_fail "MK2 clause(2): 行頭 <link> 再注入 (旧 common.css shape) → 物理指紋 FAIL" "$WORK/mk2.html" \
    '物理指紋: 行頭 <link> 要素を検出'
else bad "MK2 (fired-guard: 0 命中)"; fi

# --- MK3 fingerprint clause(3) = ears-requirement-row shape rot → 物理指紋 FAIL ---
# 生成物の要件 row token を潰す (旧 details.spec-row shape へ退行させる代理)。 selector rot を pin。
# ★同 shape の byte 段 MK は MKB1 で別立て (失敗段が不均一なため片段では穴を証明できない)。
if mutate "$WORK/mk3.html" '$N += ($t =~ s{data-component="ears-requirement-row"}{data-component="ears-requirement-row-rotted"}g);'; then
  expect_fp_fail "MK3 clause(3) [ears-requirement-row@指紋段]: token rot → 物理指紋 FAIL" "$WORK/mk3.html" \
    '物理指紋: data-component="ears-requirement-row" 不在'
else bad "MK3 (fired-guard: 0 命中)"; fi

# --- MK4 fingerprint clause(4) = relations anchor (req-rel-* / section s*) 消失 → 物理指紋 FAIL ---
# clause(4) は OR ゆえ ★両系統 を同時に rot しないと落ちない (大文字化で case-sensitive grep を外す)。
# ★同 shape (section-anchor) の byte 段 MK は MKB5 で別立て。
if mutate "$WORK/mk4.html" '$N += ($t =~ s{id="req-rel-}{id="REQ-REL-}g); $N += ($t =~ s{id="s([0-9])}{id="S$1}g);'; then
  expect_fp_fail "MK4 clause(4) [section-anchor@指紋段]: relations anchor 消失 → 物理指紋 FAIL" "$WORK/mk4.html" \
    '物理指紋: relations anchor'
else bad "MK4 (fired-guard: 0 命中)"; fi

# ============================================================================
# (c) drift (byte 比較) 段 per-shape MK — 指紋 4 clause を温存したまま shape を 1 つずつ崩す
# ============================================================================

# --- MK5 drift 段 (shape 非依存): 純粋な追記 → byte-drift FAIL (指紋段でない) ---
# 4 clause を全て温存 (<style>/no <link>/ears-row token/relations anchor) しつつ本文へコメントを注入。
# 指紋段を通過してなお fresh 再生成との byte 差を捕捉することを pin (shape を 1 つも触らない対照)。
expect_byte_fail "MK5 drift: 指紋保持で本文へ純追記 → byte-drift FAIL (指紋段でない)" mk5 \
  '$N += ($t =~ s{</body>}{<!-- DRIFT-GATE-MK-SABOTAGE --></body>});'

# --- MKB1 byte 段 [ears-requirement-row]: row 内の可視 rid を改竄 (token は温存 = 指紋 clause(3) を通す) ---
expect_byte_fail "MKB1 byte [ears-requirement-row]: 要件 row の可視 rid 改竄 → byte-drift FAIL" mkb1 \
  '$N += ($t =~ s{<span class="rid">REQ-REL-001</span>}{<span class="rid">REQ-REL-901</span>});'

# --- MKB2 byte 段 [cross-doc-ref-chip]: chip の可視 doc テキストを改竄 (chip 要素の先頭 1 件のみ) ---
expect_byte_fail "MKB2 byte [cross-doc-ref-chip]: 照会 chip の可視 doc 改竄 → byte-drift FAIL" mkb2 \
  '$N += ($t =~ s{(<div data-component="cross-doc-ref-chip".*?<span class="rf-doc">)([^<]*)}{$1ROTTED-DOC}s);'

# --- MKB3 byte 段 [grow]: glossary band の grow 要素 1 本を rot (指紋 clause は grow を見ないため byte 段で落ちる) ---
expect_byte_fail "MKB3 byte [grow]: glossary grow 要素 1 本を rot → byte-drift FAIL" mkb3 \
  '$N += ($t =~ s{<div class="grow">}{<div class="grow-rotted">});'

# --- MKB4 byte 段 [prose-slot]: prose スロット属性 1 本を rot ---
expect_byte_fail "MKB4 byte [prose-slot]: data-prose-slot 属性 1 本を rot → byte-drift FAIL" mkb4 \
  '$N += ($t =~ s{data-prose-slot="cover-summary"}{data-prose-slot="cover-summary-rotted"});'

# --- MKB5 byte 段 [section-anchor]: section id を 1 本だけ rename (他の id="s…" は残るので clause(4) は通る) ---
expect_byte_fail "MKB5 byte [section-anchor]: section id 1 本を rename → byte-drift FAIL" mkb5 \
  '$N += ($t =~ s{<section id="s6-refs"}{<section id="s6-refs-rotted"});'

# --- MKB6 byte 段 [spec-machine-list]: 機械層 list 要素 1 本を rot ---
expect_byte_fail "MKB6 byte [spec-machine-list]: 機械層 ul 要素 1 本を rot → byte-drift FAIL" mkb6 \
  '$N += ($t =~ s{<ul data-component="spec-machine-list"}{<ul data-component="spec-machine-list-rotted"});'

# --- MKB7 byte 段 [li.mli]: 機械層 li 要素 1 本を rot ---
expect_byte_fail "MKB7 byte [li.mli]: 機械層 li 要素 1 本を rot → byte-drift FAIL" mkb7 \
  '$N += ($t =~ s{<li class="mli">}{<li class="mli-rotted">});'

# ============================================================================
# (d) exit-code 規約
# ============================================================================

# --- MK6 exit-code 規約: 未知引数 → exit 2 ---
"$GATE" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "MK6 startup: 未知引数 → exit 2"
else bad "MK6 startup: 未知引数が exit 2 でない (rc=$rc)"; fi

# ============================================================================
# CASEPIN — case 数の literal pin (silent な case 削除 / 早期 return による teeth 消失を検出)。
# ★14 = H0(1) + 指紋段 MK1..MK4(4) + byte 段 MK5 + MKB1..MKB7(8) + exit 規約 MK6(1)。
#   ★fork 元 rules-drift の「7 本 (H0+MK1..6)」とも「relations shape 種数 (7)」とも ★別値 (混同禁止・contract #6)。
# ============================================================================
CASEPIN=14
echo "  ----"
printf '  relations-drift 敵対: %d/%d PASS\n' "$pass" "$total"
if [[ "$total" -ne "$CASEPIN" ]]; then
  printf '  [FAIL] CASEPIN: 実行 case 数 %d != 期待 %d (case の silent 削除 / 早期 return の疑い)\n' "$total" "$CASEPIN"
  echo "  RESULT: FAIL"; exit 1
fi
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
