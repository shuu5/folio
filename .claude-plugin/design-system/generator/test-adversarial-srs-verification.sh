#!/usr/bin/env bash
# test-adversarial-srs-verification.sh — verify-srs-verification.sh (ADR-0054 §2.2 提示層 floor) の敵対回帰テスト。
# folio-o01k (Cell S)。 姉妹 = test-adversarial-srs-verification-drift.sh (drift gate 用) と対称。
#
# ★gate 自身の ★非 vacuous 性 を committed な per-shape mutation-kill で pin する。 目的は 3 つ:
#   (a) precision (陽性対照): healthy artifact / pre-fill → exit 0 かつ [FAIL] 0 行 (clean を誤検出しない)。
#       ★OK 行数の逐値 pin も置く — arm が ★静かに消えた (assert 削除 / selector rot で 0-match 化) 退行は
#       「FAIL が出ない」形で現れるため、 FAIL 0 だけでは検出できない (vacuous-green の主経路)。
#   (b) per-shape MK: ★DOM 構造クラスごとに 1 mutant。 1 instance の実弾は構造差のある instance の穴を
#       証明しない (jyfh / r8k クラス)。 各 mutant は ★当該 arm のラベル固有 substring が [FAIL] 行に出ることまで pin
#       (「どこかが赤くなった」で満足すると別 arm の巻き添え発火を「撃てた」と誤認する)。
#   (c) ★should 分岐の合成 mutant: srs-verification の landed contract は ★5/5 が must (SHOULD 出現 0) ゆえ
#       should 側の allowlist / 導出分岐は ★実データでは永久未発火 = 「should も被覆」と実データ由来で書くのは偽証跡。
#       contract / prose を合成改変した fixture で ★明示的に撃つ (陽性対照 = should が通る / 陰性 = 詐称が落ちる)。
#
# ★★MK 被覆の実態開示 (errata-1 E-7 / errata-2 F-3・silent 欠落禁止)。
# ★集計規律 (これを決めないと同じ実測から違う結論が出る・errata-2 F-3(c)):
#   (1) kill として数えるのは ★当該 arm が単独で赤くなった run だけ。 ★fail-closed run (bogus comment /
#       unknown-container 等で live view を空にした run) では ★ほぼ全 arm が巻き添えで赤くなるため、
#       そこでの [FAIL] は ★kill に数えない (数えると「撃てていない arm」が撃てたように見える = vacuous kill)。
#       実際 errata-1 時点の「非描画退避なし: spec-machine-fold」は ★巻き添えのみ で genuine kill 0 だった。
#   (2) contract 合成でしか撃てない arm (契約内不変 = priority vs statement) は ★HTML mutant だけの集計では
#       未着弾に見える。 MKS-1/MKS-2 が撃っているので kill 済として数えるが、 ★集計対象を明示しないと結論が変わる。
# ★現状 (errata-3 G-1 適用後の ★規律準拠 再測): ★全 arm が genuine kill 済 = ★MK 未着弾 0 本。
#   ★errata-2 で書いた「back-ref 化け entity なし は構造的に単独発火不能 (subsumed)」は ★誤り だった
#   (独立 verifier が実弾 2 形で反証・errata-3 G-1)。 機序は MK7-4c/4d のコメントに記した —
#   ★mutant の置き場所 (コメント内 / RAWTEXT 内 / 地の文) で経路が変わる ことを見落としていた。
# ★headline の arm 数は ★焼き込まず 機械照合する (errata-3 G-2・案 α)。 F-5 で「件数焼込みは stale 化する」と
#   裁定しながら headline だけ数値を残して ★3 度目の drift を出した ため、 数値を ★下の HEADLINE_ARMS へ 1 箇所に
#   集約し、 EXPECTED_OK_ARTIFACT との一致を ★suite 自身が assert する (ずれたら赤 = silent drift 不能)。
#   errata-1 時点の headline「0 本 (54/54)」は ★false record だった — 独立再測は 53/54 で、
#   「forward-refs wrapper に class 属性が無い」arm が per-instance 未着弾のままヘッダ脚注と矛盾していた。
#   本 commit で (a) fold comment 包み MK (genuine kill 化) と (b) forward-refs への class 付与 MK を追加し、
#   ★headline を実測と一致させた (脚注で言い訳せず ★撃つ 側を採った)。
# ★この開示自体が stale 化しないよう、 arm を足したときは上記規律で kill map を取り直して本注記を更新すること。
# ★arm 見出しコメントに ★MK 本数を焼かない (errata-2 F-5・E-8 と同クラス): 数値は MK を 1 本足すたび静かに
#   stale 化し false record になる (実際 arm T「4 本」実 5 / arm 7「6 本」実 7 の drift が出た)。
#   ★件数の SSoT は ★実行時の PASS 行 と EXPECTED_OK_* の逐値 pin であり、 見出しには ★何を撃つか (shape の質) を書く。
#
# fixture は healthy な contract + prose から ★hermetic に合成する (git-rev 非依存)。
# ★FAIL 系 pin は [FAIL] 行にしか出ない ★arm ラベル固有 substring で確認する (恒真 grep 回避)。
#   ★行頭 anchor '^ *\[FAIL\]' を使う: verify の [OK] 行にも label 文字列は現れるため substring だけでは
#   ★PASS 行を FAIL と読み違える (集計 grep の label-substring 罠)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-srs-verification.sh"
ASSEMBLE="$SCRIPT_DIR/assemble-srs-verification.sh"
INJECT="$SCRIPT_DIR/inject-prose.sh"
CONTRACT="$SCRIPT_DIR/contract/folio-srs-verification.spec.yaml"
PROSE="$SCRIPT_DIR/prose/folio-srs-verification.prose.yaml"
for f in "$GATE" "$ASSEMBLE" "$INJECT"; do
  [[ -x "$f" ]] || { echo "FATAL: not executable: $f" >&2; exit 2; }
done
for f in "$CONTRACT" "$PROSE"; do
  [[ -f "$f" ]] || { echo "FATAL: not found: $f" >&2; exit 2; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad() { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

# ★healthy artifact / pre-fill を 1 度だけ合成 (以降の mutant はここから派生)。
"$ASSEMBLE" "$CONTRACT" "$WORK/healthy-prefill.html" >/dev/null 2>&1 \
  || { echo "FATAL: assemble 失敗 (fixture 合成不能)" >&2; exit 2; }
"$INJECT" "$PROSE" "$WORK/healthy-prefill.html" "$WORK/healthy.html" >/dev/null 2>&1 \
  || { echo "FATAL: inject 失敗 (fixture 合成不能)" >&2; exit 2; }
HEALTHY="$WORK/healthy.html"

# ★arm 総数の逐値 pin (vacuous-green 封鎖)。 arm を足したら ★ここも更新する = lockstep。
EXPECTED_OK_ARTIFACT=57
EXPECTED_OK_PREFILL=54
# ★ヘッダ headline が主張する「全 genuine kill 済 arm 数」。 ★EXPECTED_OK_ARTIFACT と ★同値でなければならない
#   (未着弾 0 = 全 arm が kill 済 = arm 総数と一致する)。 下の H7 が機械照合し、 片方だけ動かすと ★赤くなる。
HEADLINE_ARMS=57

# gate を走らせ (label, rc, out) を返すヘルパ。
run_gate() { # $1=html $2...=extra args (先頭に --artifact 等)
  local html="$1"; shift
  "$GATE" "$@" "$CONTRACT" "$html" 2>&1
}
# mutant が ★当該 arm の [FAIL] を出すことを pin。
# ★★genuineness guard を ★helper 冒頭に一括で置く (errata-1 E-4)。 空 / 破損 fixture でも verify は ★ほぼ全 arm を
#   FAIL させるため、 各 MK の pin substring が [FAIL] に出てしまい ★偽 [PASS] になる (「撃てていないのに撃てた」)。
#   ★初版は arm 0 の一部と MK7-2/7-3 にしか個別 guard が無く 24 本が無 guard だった = 本 suite 自身が
#   「mutant 合成失敗は偽 PASS を生む」と宣言しながらの ★部分適用 (宣言能力 > 実能力)。 helper 一括なら
#   ★全 MK に自動で効き、 将来追加される MK も最初から守られる (個別追記の漏れが構造的に起きない)。
#   (1) 非空       — 合成コマンドが syntax error 等で空ファイルを吐いた形 (実際に踏んだ罠)
#   (2) healthy と差分あり — 置換が 1 つも当たらなかった no-op 変異 (= healthy を検査しているだけ)
#   ★どちらも FATAL で ★suite ごと止める (bad にして続行すると「他が緑だから良し」と読まれうる)。
expect_fail() { # $1=label $2=html $3=arm ラベル固有 substring $4...=gate args
  local label="$1" html="$2" sub="$3"; shift 3
  local out rc
  [[ -s "$html" ]] || { echo "FATAL: mutant fixture が空 ($label / $html) — 合成失敗を偽 PASS にしない" >&2; exit 2; }
  if cmp -s "$HEALTHY" "$html"; then
    echo "FATAL: mutant fixture が healthy と同一 ($label / $html) — no-op 変異を偽 PASS にしない" >&2; exit 2
  fi
  out="$("$GATE" "$@" "$CONTRACT" "$html" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qE '^ *\[FAIL\]' <<<"$out" && grep -E '^ *\[FAIL\]' <<<"$out" | grep -qF -- "$sub"; then
    ok "$label"
  else
    bad "$label (rc=$rc / [FAIL] 行に '$sub' が無い)"
  fi
}
# contract / prose を合成改変した fixture で gate を走らせる (should 分岐用)。
run_synth() { # $1=contract $2=prose $3=outdir → stdout に gate 出力・rc を返す
  local c="$1" p="$2" d="$3"
  mkdir -p "$d"
  "$ASSEMBLE" "$c" "$d/a.html" >/dev/null 2>&1 || { echo "SYNTH-ASSEMBLE-FAILED"; return 9; }
  "$INJECT" "$p" "$d/a.html" "$d/f.html" >/dev/null 2>&1 || { echo "SYNTH-INJECT-FAILED"; return 9; }
  "$GATE" --artifact "$c" "$d/f.html" 2>&1
}

echo "== verify-srs-verification (ADR-0054 §2.2 提示層 floor) 敵対回帰 — folio-o01k / Cell S =="

# ---------------------------------------------------------------------------
# H. 陽性対照 (precision) + ★arm 数の逐値 pin
# ---------------------------------------------------------------------------
out="$(run_gate "$HEALTHY" --artifact)"; rc=$?
n_ok="$(grep -cE '^ *\[OK\]' <<<"$out")"; n_fail="$(grep -cE '^ *\[FAIL\]' <<<"$out")"
if [[ "$rc" -eq 0 && "$n_fail" -eq 0 && "$n_ok" -eq "$EXPECTED_OK_ARTIFACT" ]]; then
  ok "H1 precision: healthy artifact → exit 0 / FAIL 0 / OK $EXPECTED_OK_ARTIFACT (arm 数 pin)"
else
  bad "H1 precision: rc=$rc OK=$n_ok (期待 $EXPECTED_OK_ARTIFACT) FAIL=$n_fail"
fi
out="$(run_gate "$WORK/healthy-prefill.html")"; rc=$?
n_ok="$(grep -cE '^ *\[OK\]' <<<"$out")"; n_fail="$(grep -cE '^ *\[FAIL\]' <<<"$out")"
if [[ "$rc" -eq 0 && "$n_fail" -eq 0 && "$n_ok" -eq "$EXPECTED_OK_PREFILL" ]]; then
  ok "H2 precision: pre-fill (slot 空) → exit 0 / FAIL 0 / OK $EXPECTED_OK_PREFILL (mode 分岐 pin)"
else
  bad "H2 precision: rc=$rc OK=$n_ok (期待 $EXPECTED_OK_PREFILL) FAIL=$n_fail"
fi
# ★CEILING=PENDING を返す (floor 単独 GREEN の禁止・二層 invariant)。
if grep -qF 'CEILING=PENDING' <<<"$(run_gate "$HEALTHY" --artifact)"; then
  ok "H3 二層 invariant: floor PASS 時に CEILING=PENDING を返す (floor 単独 GREEN 禁止)"
else bad "H3 二層 invariant: CEILING=PENDING が出ない"; fi
# ★out-of-scope の実態開示が出力に在る (silent 欠落 = 「範型踏襲済」の誤報告を封鎖)。
if grep -qF 'containment=folio-3zr4' <<<"$(run_gate "$HEALTHY" --artifact)"; then
  ok "H4 実態開示: out-of-scope (containment / 機械層 round-trip / census) を出力で開示"
else bad "H4 実態開示: out-of-scope 開示行が無い"; fi
# ★H5/H6 mode 縮退の ★開示 pin (silent skip 封鎖・独立 ceiling 指摘)。 --artifact を落とすと中身系 3 arm が
#   無言 skip されて なお exit 0 / RESULT PASS を返すため、 ★実行 mode がログ本文に残ることを機械 pin する。
#   ★充填済 artifact を --artifact 無しで渡すと OK が ★3 本減る ことも逐値で押さえる (縮退幅の pin)。
out_a="$(run_gate "$HEALTHY" --artifact)"; out_p="$(run_gate "$HEALTHY")"
if grep -qF 'MODE: mode=artifact' <<<"$out_a" && grep -qF 'MODE: mode=pre-fill' <<<"$out_p"; then
  ok "H5 mode 開示: RESULT 直前に実行 mode 行が出る (--artifact の有無で逐値に切替わる)"
else bad "H5 mode 開示: MODE 行が出ない or mode が切替わらない"; fi
n_a="$(grep -cE '^ *\[OK\]' <<<"$out_a")"; n_p="$(grep -cE '^ *\[OK\]' <<<"$out_p")"
if [[ "$((n_a - n_p))" -eq 3 ]] && grep -qF '中身系 3 arm を skip' <<<"$out_p"; then
  ok "H6 mode 縮退幅: --artifact 落ちで OK が 3 減り、縮退が本文に明示される ($n_a → $n_p)"
else bad "H6 mode 縮退幅: 期待 3 減 / 実測 $((n_a - n_p)) (or 縮退の明示なし)"; fi
# ★H7 headline 整合 (errata-3 G-2・案 α): ヘッダが主張する arm 数と実 arm 数 (EXPECTED_OK_ARTIFACT) の一致。
#   ★同じ drift が 3 度出たため「書いた数を機械が読む」形にした — 片方だけ更新すると ★ここで赤くなる。
if [[ "$HEADLINE_ARMS" -eq "$EXPECTED_OK_ARTIFACT" ]]; then
  ok "H7 headline 整合: ヘッダ主張 arm 数 == 実 arm 数 ($HEADLINE_ARMS・未着弾 0 の含意)"
else bad "H7 headline 整合: ヘッダ $HEADLINE_ARMS != 実 arm 数 $EXPECTED_OK_ARTIFACT (headline が stale)"; fi

# ---------------------------------------------------------------------------
# arm 0. ★hiding クラス (非描画領域への退避) — 容器軸 (comment / RAWTEXT / bogus / template) × 対象軸 (chip / row / 章)
#         + allowlist 外タグ 7 種 + allowlist 内 RCDATA (title) + 陽性対照 1 (件数は実行時 PASS 行が SSoT)
# ---------------------------------------------------------------------------
# ★このクラスは Cell S 初版で ★丸ごと欠けていた (独立 ceiling が実測): make_body はコメントを verbatim・
#   <script> の中身を opaque 保持する設計ゆえ、 提示層要素を <!-- --> / <script> で包むだけで全 arm が
#   rc=0 / [FAIL] 0 で素通った (= gate の本来目的の迂回)。 削除 / 空化 / 逐語改竄 / relocation / 並べ替えの
#   既存 MK 群は「文字列が消える or 変わる」形しか撃たないため、 このクラスを ★1 本も検出しなかった。
# ★per-shape で撃つ: 包む対象の DOM 構造 (inline chip / 要件 row = block / wrapper 章まるごと) と
#   包む容器 (comment / RAWTEXT script / bogus comment / template) の ★両軸 を分けて 1 instance ずつ。
echo "  -- arm 0 (非描画領域への退避 = hiding クラス) --"
# shape(a): ★inline chip を HTML コメントで包む (件数は raw では保存されるため naive 計数では捕捉不能)
perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<!-- $1 -->}s' "$HEALTHY" > "$WORK/a0-chip-cmt.html"
grep -qF '<!-- <div data-component="cross-doc-ref-chip"' "$WORK/a0-chip-cmt.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-chip-cmt)" >&2; exit 2; }
expect_fail "MK0-1 shape(chip を <!-- --> で隠蔽) → 非描画退避 negative pin FAIL" "$WORK/a0-chip-cmt.html" \
  '非描画退避なし: data-component="cross-doc-ref-chip"' --artifact
expect_fail "MK0-2 shape(同上) → live view 由来の chip 件数 FAIL (census 側も落ちる二重化)" "$WORK/a0-chip-cmt.html" \
  'cross-doc-ref-chip == |references|' --artifact
# shape(b): ★要件 row を丸ごとコメントで包む (平易行 / 優先度バッジごと不可視化)
perl -0pe 's{(<div data-component="ears-requirement-row" id="req-ver-026".*?</details>\n</div>)}{<!-- $1 -->}s' "$HEALTHY" > "$WORK/a0-row-cmt.html"
grep -qF '<!-- <div data-component="ears-requirement-row"' "$WORK/a0-row-cmt.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-row-cmt)" >&2; exit 2; }
expect_fail "MK0-3 shape(要件 row を <!-- --> で隠蔽) → 非描画退避 negative pin FAIL" "$WORK/a0-row-cmt.html" \
  '非描画退避なし: data-component="ears-requirement-row"' --artifact
# shape(c): ★wrapper 章まるごと (band + chip 10 件) をコメントで包む = 章の完全消失
perl -0pe 's{(<section id="forward-refs">.*?</section>\n)}{<!-- $1 -->}s' "$HEALTHY" > "$WORK/a0-sec-cmt.html"
grep -qF '<!-- <section id="forward-refs">' "$WORK/a0-sec-cmt.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-sec-cmt)" >&2; exit 2; }
expect_fail "MK0-4 shape(wrapper 章まるごと <!-- --> で隠蔽) → 非描画退避 negative pin FAIL" "$WORK/a0-sec-cmt.html" \
  '非描画退避なし: <section id="forward-refs">' --artifact
# shape(c2): ★機械層 fold をコメントで包む (errata-2 F-3)。 この退避 arm はこれまで ★genuine kill 0 だった —
#   赤くなっていたのは全て ★fail-closed run (bogus comment / template / unknown-container で live view を空にした run)
#   の ★巻き添え で、 fold 自体を隠す実弾が 1 本も無かった (vacuous kill)。 fold は <details> ゆえ chip / row / 章とは
#   ★別の DOM 構造クラス で、 per-shape 原則上も独立の実弾が要る。
perl -0pe 's{(<details data-component="spec-machine-fold".*?</details>)}{<!-- $1 -->}s' "$HEALTHY" > "$WORK/a0-fold-cmt.html"
grep -qF '<!-- <details data-component="spec-machine-fold"' "$WORK/a0-fold-cmt.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-fold-cmt)" >&2; exit 2; }
expect_fail "MK0-4b shape(機械層 fold を <!-- --> で隠蔽) → 非描画退避 negative pin FAIL (genuine kill)" "$WORK/a0-fold-cmt.html" \
  '非描画退避なし: data-component="spec-machine-fold"' --artifact
# ★fail-closed の巻き添えでなく ★当該 arm 単独で赤い ことを pin (vacuous kill との弁別)。
out="$(run_gate "$WORK/a0-fold-cmt.html" --artifact)"
if ! grep -qF 'make_body_live fail-closed' <<<"$out"; then
  ok "MK0-4c 弁別: fold comment 包みは fail-closed を経由せず ★genuine に赤い (巻き添え kill でない)"
else bad "MK0-4c 弁別: fail-closed 経由 = 巻き添え kill (当該 arm の teeth を証明できていない)"; fi
# shape(d): ★RAWTEXT (<script type="text/plain">) で包む — make_body は script の中身を opaque 保持するため
#   コメントとは ★別経路 の隠蔽になる (容器軸の per-shape)。
perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<script type="text/plain">$1</script>}s' "$HEALTHY" > "$WORK/a0-chip-scr.html"
grep -qF '<script type="text/plain"><div data-component="cross-doc-ref-chip"' "$WORK/a0-chip-scr.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-chip-scr)" >&2; exit 2; }
expect_fail "MK0-5 shape(chip を <script> で隠蔽) → 非描画退避 negative pin FAIL" "$WORK/a0-chip-scr.html" \
  '非描画退避なし: data-component="cross-doc-ref-chip"' --artifact
# shape(e): ★HTML5 bogus comment `<!x>` — 姉妹 strip_inert が ★オフセット誤算で fail-open になった実クラス
#   (folio-gt4s)。 本 gate は parse し直さず ★存在自体を fail-closed にする (partial-enumeration trap 回避)。
perl -0pe 's{(<div data-component="cross-doc-ref-chip")}{<!x>$1}' "$HEALTHY" > "$WORK/a0-bogus.html"
expect_fail "MK0-6 shape(bogus comment <!x> 注入) → live view fail-closed" "$WORK/a0-bogus.html" \
  'make_body_live fail-closed' --artifact
# shape(f): ★<template> (inert DocumentFragment) — assembler / chrome とも実測 0 件 = allowlist 外ゆえ赤になる。
perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<template>$1</template>}s' "$HEALTHY" > "$WORK/a0-tpl.html"
grep -qF '<template><div data-component="cross-doc-ref-chip"' "$WORK/a0-tpl.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-tpl)" >&2; exit 2; }
expect_fail "MK0-7 shape(<template> で隠蔽) → live view fail-closed" "$WORK/a0-tpl.html" \
  'make_body_live fail-closed' --artifact
# shape(g): ★closed tag allowlist の per-container 実弾 (errata-1 E-2)。 初版の「inert 容器 5 種を名指し列挙」は
#   partial-enum trap で、 独立 ceiling が iframe / textarea / xmp / noembed / noframes (RAWTEXT/RCDATA) と
#   datalist (UA display:none) の ★6 容器で素通りを実証した (html5lib DOM 実測 chip=10→9 = 実際に消える)。
#   ★容器を追わず ★allowlist 外を全部拒否 する補集合閉包へ転換したので、 ★各容器を 1 instance ずつ per-shape で撃つ
#   (1 容器の実弾は別容器の穴を証明しない = jyfh / r8k クラス)。
#   ★noscript も含める: 「inert に倒した」のではなく ★assembler も chrome も emit しない = allowlist 外 という
#   理由で落ちることを pin する (folio-7wbn 批准裁定と矛盾しない — 非描画とは主張していない)。
for _c in iframe textarea xmp noembed noframes datalist noscript; do
  C="$_c" perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<$ENV{C}>$1</$ENV{C}>}s' "$HEALTHY" > "$WORK/a0-tag-$_c.html"
  grep -qF "<$_c><div data-component=\"cross-doc-ref-chip\"" "$WORK/a0-tag-$_c.html" \
    || { echo "FATAL: mutant 合成失敗 (a0-tag-$_c)" >&2; exit 2; }
  expect_fail "MK0-8/$_c shape(<$_c> で chip を隠蔽) → unknown-container fail-closed" "$WORK/a0-tag-$_c.html" \
    "unknown-container:$_c" --artifact
done
# shape(h): ★allowlist ★内 のタグ自身が隠蔽容器になる形 (errata-2 F-2)。 <title> は HTML5 の RCDATA かつ
#   UA display:none で、 assembler が head に emit する ★正当な allowlist メンバー でありながら body で使うと
#   中身が描画されない (html5lib DOM 実測 chip 10→9)。 allowlist 判定 ★だけ では素通ったため RAWTEXT 空化分岐
#   (script/style と同列) へ入れて閉塞した。 ★「allowlist は それ自体では閉じない」ことの実弾。
perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<title>$1</title>}s' "$HEALTHY" > "$WORK/a0-title.html"
grep -qF '<title><div data-component="cross-doc-ref-chip"' "$WORK/a0-title.html" \
  || { echo "FATAL: mutant 合成失敗 (a0-title)" >&2; exit 2; }
expect_fail "MK0-8/title shape(<title> = allowlist 内 RCDATA で隠蔽) → 非描画退避 negative pin FAIL" "$WORK/a0-title.html" \
  '非描画退避なし: data-component="cross-doc-ref-chip"' --artifact
expect_fail "MK0-8/title-b shape(同上) → live view 由来の chip 件数 FAIL (空化の二重化)" "$WORK/a0-title.html" \
  'cross-doc-ref-chip == |references|' --artifact
# ★陽性対照 (allowlist が ★広すぎない ことの証明): allowlist 内タグ (<span>) で包んだだけでは ★赤にならない
#   — allowlist 判定が「何でも赤」に退化していないことを撃つ (fail-closed の過剰適用 = 偽 FAIL 量産の封鎖)。
perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{<span>$1</span>}s' "$HEALTHY" > "$WORK/a0-tag-ok.html"
out="$(run_gate "$WORK/a0-tag-ok.html" --artifact)"; rc=$?
if [[ "$rc" -eq 0 ]] && ! grep -qF 'unknown-container' <<<"$out"; then
  ok "MK0-9 陽性対照(allowlist 内 <span> で包む) → unknown-container を出さない (allowlist の過剰適用封鎖)"
else bad "MK0-9 陽性対照: allowlist 内タグで赤くなった (rc=$rc) = 判定が「何でも赤」に退化"; fi

# ---------------------------------------------------------------------------
# arm A. ★捏造追加 (同一行 append) — 対象軸 (chip / row / band / fold) × 陽性 + chip・row は陰性対照 (別行) を対で
# ---------------------------------------------------------------------------
# ★このクラスも Cell S の errata-1 前まで ★丸ごと素通っていた (独立 ceiling 実弾): census が grep -c = ★行計数
#   だったため「既存要素と ★同一行 に捏造要素を append」しても件数が動かず rc=0 / FAIL 0。 html5lib DOM 実測では
#   chip=11 / row=6 = ★捏造要素は実際に描画される (見えない欠陥ではなく可視の捏造)。
# ★陰性対照を必ず対で置く: 同じ捏造を ★別行 に置いた mutant も FAIL することを確認して初めて
#   「行計数 ★だけ が原因だった」と isolate できる (対照が無いと『元から落ちていた』のか区別できない)。
# ★occurrence 計数化 (E-1(a)) + residue 検査 (E-1(b)) の ★両方 を撃つ per-shape。
echo "  -- arm A (捏造追加・同一行 append = 行計数 fail-open) --"
# shape(a): 裸 ID の捏造 chip を P-13 chip と ★同一行 へ append
FAB_CHIP='<div data-component="cross-doc-ref-chip" data-ref-token="ADR-9999" data-ref-role="rationale"><span class="rf-token"><b>ADR-9999</b></span><span class="rf-arrow">→</span><span class="rf-doc">decisions/</span><span class="rf-role">そう決めた理由の記録</span></div>'
C="$FAB_CHIP" perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{$1$ENV{C}}s' "$HEALTHY" > "$WORK/aA-chip-same.html"
grep -qF 'ADR-9999' "$WORK/aA-chip-same.html" || { echo "FATAL: mutant 合成失敗 (aA-chip-same)" >&2; exit 2; }
expect_fail "MKA-1 shape(捏造 chip を同一行 append) → chip 件数 FAIL (occurrence 計数)" "$WORK/aA-chip-same.html" \
  'cross-doc-ref-chip == |references|' --artifact
# ★residue は ★shape 外 の捏造にこそ効く arm ゆえ、 別 fixture で撃つ (上の捏造 chip は ★厳密 shape に
#   ★準拠 して作ってあるため厳密列挙にも数えられ residue は等しくなる = 件数 arm 側が唯一の検出器)。
#   ★裸 ID だけの半端な chip (rf-role span 等を欠く) は厳密列挙から漏れるため、 residue が無ければ ★黙殺される。
FAB_CHIP_MALFORMED='<div data-component="cross-doc-ref-chip" data-ref-token="ADR-9999" data-ref-role="rationale"><span class="rf-token"><b>ADR-9999</b></span></div>'
C="$FAB_CHIP_MALFORMED" perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{$1$ENV{C}}s' "$HEALTHY" > "$WORK/aA-chip-malformed.html"
grep -qF 'ADR-9999' "$WORK/aA-chip-malformed.html" || { echo "FATAL: mutant 合成失敗 (aA-chip-malformed)" >&2; exit 2; }
expect_fail "MKA-2 shape(shape 外 chip を同一行 append) → residue 検査 FAIL (黙殺封鎖)" "$WORK/aA-chip-malformed.html" \
  'residue: chip marker 出現数' --artifact
# ★陰性対照: 同じ捏造を ★別行 に置く (改行付き)。 行計数時代も FAIL していた形 = 対照として両方赤を確認する。
C="$FAB_CHIP" perl -0pe 's{(<div data-component="cross-doc-ref-chip" data-ref-token="P-13".*?</div>)}{$1\n$ENV{C}}s' "$HEALTHY" > "$WORK/aA-chip-nl.html"
expect_fail "MKA-3 陰性対照(捏造 chip を別行) → 同じく chip 件数 FAIL (行/出現の差を isolate)" "$WORK/aA-chip-nl.html" \
  'cross-doc-ref-chip == |references|' --artifact
# shape(b): 1 行完結の捏造 ★要件 row を既存 row の開きタグ前へ挿入 (同一行 append 形)
FAB_ROW='<div data-component="ears-requirement-row" id="req-ver-999" data-req-id="REQ-VER-999" data-ears-pattern="ubiquitous" data-audience="human"><div class="rq-head"><span class="rid">REQ-VER-999</span></div></div>'
R="$FAB_ROW" perl -0pe 's{(<div data-component="ears-requirement-row" id="req-ver-024")}{$ENV{R}$1}' "$HEALTHY" > "$WORK/aA-row-same.html"
grep -qF 'req-ver-999' "$WORK/aA-row-same.html" || { echo "FATAL: mutant 合成失敗 (aA-row-same)" >&2; exit 2; }
expect_fail "MKA-4 shape(捏造 row を同一行 append) → row 件数 FAIL (occurrence 計数)" "$WORK/aA-row-same.html" \
  'census: ears-requirement-row ==' --artifact
expect_fail "MKA-5 shape(同上) → residue 検査 FAIL (shape 外 row の黙殺封鎖)" "$WORK/aA-row-same.html" \
  'residue: row marker 出現数' --artifact
R="$FAB_ROW" perl -0pe 's{(<div data-component="ears-requirement-row" id="req-ver-024")}{$ENV{R}\n$1}' "$HEALTHY" > "$WORK/aA-row-nl.html"
expect_fail "MKA-6 陰性対照(捏造 row を別行) → 同じく row 件数 FAIL" "$WORK/aA-row-nl.html" \
  'census: ears-requirement-row ==' --artifact
# shape(c): 捏造 ★band を同一行 append (章帯の件数 arm)
FAB_BAND='<section data-component="chapter-deck-band" class="band info"><h2>§9. 捏造章</h2></section>'
B="$FAB_BAND" perl -0pe 's{(<section data-component="chapter-deck-band")}{$ENV{B}$1}' "$HEALTHY" > "$WORK/aA-band-same.html"
grep -qF '捏造章' "$WORK/aA-band-same.html" || { echo "FATAL: mutant 合成失敗 (aA-band-same)" >&2; exit 2; }
expect_fail "MKA-7 shape(捏造 band を同一行 append) → band 件数 FAIL (occurrence 計数)" "$WORK/aA-band-same.html" \
  'chapter-deck-band == sections + 2' --artifact
# shape(d): 捏造 ★machine fold を同一行 append (fold の契約非依存 census)
FAB_FOLD='<details data-component="spec-machine-fold" class="machine-fold"><summary><span class="mf-kicker">機械向けの詳細（原文そのまま）</span></summary></details>'
F="$FAB_FOLD" perl -0pe 's{(<details data-component="spec-machine-fold")}{$ENV{F}$1}' "$HEALTHY" > "$WORK/aA-fold-same.html"
grep -qF '<details data-component="spec-machine-fold" class="machine-fold"><summary><span class="mf-kicker">' "$WORK/aA-fold-same.html" \
  || { echo "FATAL: mutant 合成失敗 (aA-fold-same)" >&2; exit 2; }
expect_fail "MKA-8 shape(捏造 fold を同一行 append) → 契約非依存 fold census FAIL" "$WORK/aA-fold-same.html" \
  'census: 機械層 fold 数 ==' --artifact

# ---------------------------------------------------------------------------
# arm 1. 章帯 §番号一致 — .num 値差替 / .num 空化 / band 器の脱落
# ---------------------------------------------------------------------------
echo "  -- arm 1 (章帯 §番号) --"
# shape(a): .num の値だけを差し替える (件数保存 = 数え上げ arm では捕捉できない形)
perl -0pe 's{<span class="num">3</span>}{<span class="num">9</span>}' "$HEALTHY" > "$WORK/a1-num.html"
expect_fail "MK1-1 shape(.num 値差替 §3→§9) → 節番号列 FAIL" "$WORK/a1-num.html" \
  'band .num 列 == 見出しの節番号' --artifact
# shape(b): .num を空化 (assembler の代入形 guard / band_num 数値 guard を擦り抜けた defective artifact の代理)
perl -0pe 's{<span class="num">3</span>}{<span class="num"></span>}' "$HEALTHY" > "$WORK/a1-empty.html"
expect_fail "MK1-2 shape(.num 空化) → 空 num の defective artifact FAIL" "$WORK/a1-empty.html" \
  '.num は全て数値' --artifact
# shape(c): band 器自体の脱落 (静的 band の章化が落ちた形)
# ★selector は ★<section 開きタグ に固定する: 素の data-component="chapter-deck-band" は inline <style> の CSS
#   selector 行にも現れ、 その ★最初の 1 件を潰しても make_body が <style> を畳むため BODY は無傷 = ★mutant が
#   効かず gate が緑のまま (= 偽 PASS)。 mutant の subject も verify と同じ「畳んだ後の本文」に揃える (追補 9 の
#   parser-differential クラスの再演防止)。
perl -0pe 's{<section data-component="chapter-deck-band"}{<section data-component="chapter-deck-band-rotted"}' "$HEALTHY" > "$WORK/a1-band.html"
expect_fail "MK1-3 shape(band token rot 1 件) → band 件数 FAIL" "$WORK/a1-band.html" \
  'chapter-deck-band == sections + 2' --artifact

# ---------------------------------------------------------------------------
# arm 2. wrapper 章化 + tint / kicker / 見出し逐語 — id 改名 / class 付与 (2 wrapper) / 開口隣接 tint 付替 /
#         kicker 書換 / 静的見出しの 2 種版退行 / 順序入替 / 本文 band tint 付替
# ---------------------------------------------------------------------------
echo "  -- arm 2 (wrapper 章化 / band 属性) --"
# shape(a): wrapper id の改名 (章化そのものの喪失)
perl -0pe 's{<section id="forward-refs">}{<section id="fwd-refs">}' "$HEALTHY" > "$WORK/a2-id.html"
expect_fail "MK2-1 shape(wrapper id 改名) → wrapper 実在 FAIL" "$WORK/a2-id.html" \
  '提示層 wrapper <section id="forward-refs"> が 1 個' --artifact
# shape(b): wrapper への class 付与 (normative/informative census を動かす形)
perl -0pe 's{<section id="glossary-terms">}{<section id="glossary-terms" class="informative">}' "$HEALTHY" > "$WORK/a2-class.html"
expect_fail "MK2-2 shape(wrapper に class 付与) → census 不変 FAIL" "$WORK/a2-class.html" \
  "提示層 wrapper 'glossary-terms' に class 属性が無い" --artifact
# ★per-instance の対 (errata-2 F-3(b)): 上は glossary-terms 側のみで forward-refs 側が ★未着弾 だった。
#   同一コード路の別データゆえ per-shape 原則は満たすが、 ヘッダ headline を「全 arm 着弾」と書く以上
#   ★per-instance でも撃つ (headline と脚注の矛盾を残さない = admin 処方 (b) の「撃つ」側を採用)。
perl -0pe 's{<section id="forward-refs">}{<section id="forward-refs" class="informative">}' "$HEALTHY" > "$WORK/a2-class-fr.html"
grep -qF '<section id="forward-refs" class="informative">' "$WORK/a2-class-fr.html" \
  || { echo "FATAL: mutant 合成失敗 (a2-class-fr)" >&2; exit 2; }
expect_fail "MK2-2b shape(forward-refs へ class 付与・per-instance 対) → census 不変 FAIL" "$WORK/a2-class-fr.html" \
  "提示層 wrapper 'forward-refs' に class 属性が無い" --artifact
# shape(c): 開口直後の band を ★別章の tint に付け替える (「隣に何らかの band が在る」だけの弱い pin なら素通る形)
perl -0pe 's{(<section id="forward-refs">\s*<section data-component="chapter-deck-band" class="[^"]*?)\bviolet\b}{$1brand}' "$HEALTHY" > "$WORK/a2-tint.html"
expect_fail "MK2-3 shape(開口隣接 band の tint 付替) → 開口隣接 pin FAIL" "$WORK/a2-tint.html" \
  "wrapper 'forward-refs' の開口直後に tint=violet" --artifact
# shape(d): 静的 band の kicker 書換
perl -0pe 's{用語集 / この文書で使う専門語}{用語の一覧}' "$HEALTHY" > "$WORK/a2-kick.html"
expect_fail "MK2-4 shape(静的 band kicker 書換) → kicker 列 FAIL" "$WORK/a2-kick.html" \
  'band kicker 列 ==' --artifact
# shape(e): ★見出しを Cell R/V の 2 種版へ退行させる (実在する照会 2 件 = role=verification を落とす虚偽見出し)。
#   ★この誤りを撃つ機械 gate は Cell S 以前に 0 本だった (fidelity ceiling と user walk だけが検出器だった)。
perl -0pe 's{上位文書への前方照会 — 原則・決定記録・検証仕様へつながる}{上位文書への前方照会 — 原則と決定記録へつながる}' "$HEALTHY" > "$WORK/a2-head.html"
expect_fail "MK2-5 shape(静的見出しを 2 種版へ退行 = 照会種別の虚偽) → h2 見出し列 FAIL" "$WORK/a2-head.html" \
  'h2 見出し列 ==' --artifact
# shape(e2): ★本文 band の tint 付替 (errata-1 E-5)。 kicker も heading も ★変えない ため、 tint 列 arm が
#   無ければ ★どの arm にも掛からない (wrapper 2 本は開口隣接 pin が tint を見るが本文 5 章は無 pin だった)。
perl -0pe 's{(<section data-component="chapter-deck-band" class=")tint-violet("><span class="num">2</span>)}{$1tint-bad$2}' "$HEALTHY" > "$WORK/a2-tintbody.html"
grep -qF 'class="tint-bad"><span class="num">2</span>' "$WORK/a2-tintbody.html" \
  || { echo "FATAL: mutant 合成失敗 (a2-tintbody)" >&2; exit 2; }
expect_fail "MK2-5b shape(本文 §2 band の tint 付替 violet→bad) → tint 列 FAIL" "$WORK/a2-tintbody.html" \
  'band tint 列 ==' --artifact
# shape(f): wrapper 2 本の順序入替 (id 集合は保存 = 集合 assert では捕捉できない形)
perl -0pe 's{(<section id="forward-refs">)}{<section id="glossary-terms">}; s{(<section id="glossary-terms">)(?!.*<section id="glossary-terms">)}{<section id="forward-refs">}s' "$HEALTHY" > "$WORK/a2-order.html"
expect_fail "MK2-6 shape(wrapper 順序入替・集合保存) → anchor 列 FAIL" "$WORK/a2-order.html" \
  'section anchor 列 ==' --artifact

# ---------------------------------------------------------------------------
# arm 3. chip tuple + rf-gloss — gloss 逐語改竄 / gloss 削除 / gloss 空化 / role 可視の英語生表示退行 / 可視 token 捏造
# ---------------------------------------------------------------------------
echo "  -- arm 3 (chip tuple / rf-gloss) --"
# shape(a): rf-gloss の逐語改竄 (contract echo からの乖離)
perl -0pe 's{<span class="rf-gloss">検証と追跡可能性 \(Verification &amp; Traceability\)</span>}{<span class="rf-gloss">検証のこと</span>}' "$HEALTHY" > "$WORK/a3-gloss.html"
expect_fail "MK3-1 shape(rf-gloss 逐語改竄) → chip tuple FAIL" "$WORK/a3-gloss.html" \
  'references: (token,doc,role,title) 順序突合' --artifact
# shape(b): rf-gloss span を 1 件削除 (件数が減る形)
perl -0pe 's{<span class="rf-gloss">検証と追跡可能性 \(Verification &amp; Traceability\)</span>}{}' "$HEALTHY" > "$WORK/a3-drop.html"
expect_fail "MK3-2 shape(rf-gloss 1 件削除) → 契約非依存 census FAIL" "$WORK/a3-drop.html" \
  'census: rf-gloss (照会先の一行タイトル) 占有' --artifact
# shape(c): rf-gloss を ★空要素化 (件数は保存 = census では捕捉できない半端形)
perl -0pe 's{<span class="rf-gloss">検証と追跡可能性 \(Verification &amp; Traceability\)</span>}{<span class="rf-gloss"></span>}' "$HEALTHY" > "$WORK/a3-empty.html"
expect_fail "MK3-3 shape(rf-gloss 空化・件数保存) → per-chip 非空 FAIL" "$WORK/a3-empty.html" \
  'rf-gloss: 全 chip で一行タイトルが非空' --artifact
# shape(d): role 可視ラベルを ★英語生表示へ退行 (平易化の巻き戻し・attr は不変ゆえ attr 突合だけでは盲)
perl -0pe 's{<span class="rf-role">この規約が実装する原則</span>}{<span class="rf-role">implementation</span>}' "$HEALTHY" > "$WORK/a3-role.html"
expect_fail "MK3-4 shape(role 可視を英語生表示へ退行) → chip tuple FAIL" "$WORK/a3-role.html" \
  'references: (token,doc,role,title) 順序突合' --artifact
# shape(e): attr token と可視 <b> の不一致 (可視 ID 捏造)
perl -0pe 's{<span class="rf-token"><b>P-13</b></span>}{<span class="rf-token"><b>P-99</b></span>}' "$HEALTHY" > "$WORK/a3-vis.html"
expect_fail "MK3-5 shape(可視 token 捏造) → chip tuple FAIL (TOKEN-VIS)" "$WORK/a3-vis.html" \
  'references: (token,doc,role,title) 順序突合' --artifact

# ---------------------------------------------------------------------------
# arm 4. 優先度バッジ — label 詐称 / 否定接尾 (ehar) / slot-id relocation / バッジ削除 / ラベル空化 (should 合成は後段)
# ---------------------------------------------------------------------------
echo "  -- arm 4 (優先度バッジ) --"
# shape(a): must の行に「推奨・現在」= level と label の乖離 (詐称)
perl -0pe 's{(data-slot-id="prio-req-ver-024">)必須(</span>)}{$1推奨・現在$2}' "$HEALTHY" > "$WORK/a4-lie.html"
expect_fail "MK4-1 shape(must 行に「推奨・現在」) → allowlist 逐値 FAIL" "$WORK/a4-lie.html" \
  'rq-prio: (level, 可視ラベル∈allowlist) 列' --artifact
# shape(b): ★否定接尾 (ehar クラス)。 ★前方一致判定なら「必須」で始まるため素通る形。
perl -0pe 's{(data-slot-id="prio-req-ver-024">)必須(</span>)}{$1必須ではない$2}' "$HEALTHY" > "$WORK/a4-neg.html"
expect_fail "MK4-2 shape(否定接尾「必須ではない」= ehar) → allowlist 逐値 FAIL" "$WORK/a4-neg.html" \
  'rq-prio: (level, 可視ラベル∈allowlist) 列' --artifact
# shape(c): ★relocation (件数保存): 2 row の prio slot-id を入れ替える
perl -0pe 's{prio-req-ver-024}{prio-XXTMP}; s{prio-req-ver-025}{prio-req-ver-024}; s{prio-XXTMP}{prio-req-ver-025}' "$HEALTHY" > "$WORK/a4-reloc.html"
expect_fail "MK4-3 shape(prio slot-id relocation・件数保存) → (level, slot-id) 列 FAIL" "$WORK/a4-reloc.html" \
  'rq-prio: (level, slot-id) 列' --artifact
# shape(d): バッジ 1 件を丸ごと削除
perl -0pe 's{<span class="rq-prio rq-prio-must" data-prose-slot="priority" data-slot-id="prio-req-ver-026">[^<]*</span>}{}' "$HEALTHY" > "$WORK/a4-drop.html"
expect_fail "MK4-4 shape(バッジ 1 件削除) → 契約非依存 census FAIL" "$WORK/a4-drop.html" \
  'census: rq-prio バッジ占有' --artifact
# shape(e): 空ラベル (件数保存の半端形)
perl -0pe 's{(data-slot-id="prio-req-ver-029">)必須(</span>)}{$1$2}' "$HEALTHY" > "$WORK/a4-blank.html"
expect_fail "MK4-5 shape(ラベル空化・件数保存) → per-row 非空 FAIL" "$WORK/a4-blank.html" \
  'rq-prio: 全 row で優先度ラベルが非空' --artifact

# ---------------------------------------------------------------------------
# arm 5. 平易行 — slot-id relocation / 本文空化 / container rot
# ---------------------------------------------------------------------------
echo "  -- arm 5 (平易行) --"
perl -0pe 's{plain-req-ver-029}{plain-XXTMP}; s{plain-req-ver-030}{plain-req-ver-029}; s{plain-XXTMP}{plain-req-ver-030}' "$HEALTHY" > "$WORK/a5-reloc.html"
expect_fail "MK5-1 shape(plain slot-id relocation・件数保存) → slot-id 列 FAIL" "$WORK/a5-reloc.html" \
  'rq-plain: slot-id 列' --artifact
perl -0pe 's{(<span data-prose-slot="plain" data-slot-id="plain-req-ver-024">)[^<]*(</span>)}{$1$2}' "$HEALTHY" > "$WORK/a5-empty.html"
expect_fail "MK5-2 shape(平易行 空化・件数保存) → per-row 非空 FAIL" "$WORK/a5-empty.html" \
  'rq-plain: 全 row で平易行が非空' --artifact
perl -0pe 's{<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span>}{<p class="rq-plain-rotted"><span class="rq-plain-k">やさしく言うと</span>}' "$HEALTHY" > "$WORK/a5-drop.html"
expect_fail "MK5-3 shape(平易行 container rot 1 件) → 契約非依存 census FAIL" "$WORK/a5-drop.html" \
  'census: rq-plain 平易行占有' --artifact

# ---------------------------------------------------------------------------
# arm 6. fold ラベル平易化 — 2 shape (mf-kicker / rq-norm summary) × 2 軸 (全数一致 / 旧ラベル残存 negative pin)
# ---------------------------------------------------------------------------
echo "  -- arm 6 (fold ラベル平易化) --"
# shape(a): mf-kicker を ★1 件だけ 旧ラベルへ (部分退行 = 全数一致 pin でのみ捕捉できる形)
perl -0pe 's{<span class="mf-kicker">機械向けの詳細（原文そのまま）</span>}{<span class="mf-kicker">機械層 (machine-readable)</span>}' "$HEALTHY" > "$WORK/a6-mf.html"
expect_fail "MK6-1 shape(mf-kicker 1 件だけ旧ラベルへ) → 全 fold 一致 FAIL" "$WORK/a6-mf.html" \
  'machine fold の mf-kicker 平易ラベル' --artifact
expect_fail "MK6-2 shape(同上) → 旧ラベル残存 negative pin FAIL" "$WORK/a6-mf.html" \
  '旧ラベル『機械層 (machine-readable)』残存' --artifact
# shape(b): 要件 normative fold の summary を 1 件だけ旧ラベルへ
perl -0pe 's{<summary>正確な条文（機械向けの厳密な書き方）</summary>}{<summary>normative (machine)</summary>}' "$HEALTHY" > "$WORK/a6-rq.html"
expect_fail "MK6-3 shape(rq-norm summary 1 件だけ旧ラベルへ) → |requirements| 一致 FAIL" "$WORK/a6-rq.html" \
  '要件 normative fold の summary 平易ラベル' --artifact
expect_fail "MK6-4 shape(同上) → 旧ラベル残存 negative pin FAIL" "$WORK/a6-rq.html" \
  '旧ラベル『normative (machine)』残存' --artifact

# ---------------------------------------------------------------------------
# arm 7. 要件 row 構造 anchor + 提示層 census — row 内並べ替え / pack 所有 CSS 3 宣言の rot / 同一行 2 個目追記 /
#         化け entity 注入 (+ CSS コメント化と subsumption の実態開示 pin)
# ---------------------------------------------------------------------------
echo "  -- arm 7 (row 構造 anchor / pack 所有 CSS) --"
# shape(a): row 内の block 並べ替え (平易行を normative fold の ★後ろ へ移す = 件数は全保存)
perl -0pe 's{(<p class="rq-plain">.*?</p>\n)(<details class="rq-norm" data-audience="machine">.*?</details>\n)}{$2$1}s' "$HEALTHY" > "$WORK/a7-order.html"
expect_fail "MK7-1 shape(row 内 block 並べ替え・件数保存) → row 構造 anchor FAIL" "$WORK/a7-order.html" \
  '要件 row 構造 anchor 列' --artifact
# shape(b): chrome-less 化で pack が所有する CSS の脱落 (skip-link が常時可視へ退行)
# ★行モード (-pe) + '/' 区切りを使う: -0pe の '{}' 区切りに '{' を含む置換文字列 (CSS 宣言) を書くと perl が
#   ★nesting を数えて replacement が閉じず syntax error → 出力が ★空ファイル になる。 空 fixture は全 arm が
#   落ちるため「撃てた」ように ★見える (= mutant を撃てていないのに PASS する偽陽性) — 実測で踏んだ罠。
# ★3 宣言を ★per-shape で 1 本ずつ撃つ (errata-1 E-3): 初版は :focus と .doc-locator の 2 本だけで、
#   ★hidden-until-focus の実体である ★基底規則 .skip-link{…} を撃つ mutant が無かった (= 無 pin を暴けなかった)。
#   ★1 宣言の実弾は他宣言の穴を証明しない (per-shape 原則)。
perl -pe 's/^\.skip-link\{/.skip-link-rotted\{/' "$HEALTHY" > "$WORK/a7-skipbase.html"
[[ -s "$WORK/a7-skipbase.html" ]] || { echo "FATAL: mutant 合成失敗 (a7-skipbase)" >&2; exit 2; }
expect_fail "MK7-2a shape(.skip-link 基底規則 rot = 常時可視化) → pack 所有 CSS FAIL" "$WORK/a7-skipbase.html" \
  'pack inline CSS: .skip-link{' --artifact
perl -pe 's/^\.skip-link:focus\{/.skip-link-rotted:focus\{/' "$HEALTHY" > "$WORK/a7-skip.html"
[[ -s "$WORK/a7-skip.html" ]] || { echo "FATAL: mutant 合成失敗 (a7-skip)" >&2; exit 2; }
expect_fail "MK7-2b shape(.skip-link:focus 宣言脱落 = focus しても出ない) → pack 所有 CSS FAIL" "$WORK/a7-skip.html" \
  'pack inline CSS: .skip-link:focus{' --artifact
perl -pe 's/^\.doc-locator\{/.doc-locator-rotted\{/' "$HEALTHY" > "$WORK/a7-loc.html"
[[ -s "$WORK/a7-loc.html" ]] || { echo "FATAL: mutant 合成失敗 (a7-loc)" >&2; exit 2; }
expect_fail "MK7-3 shape(.doc-locator 宣言脱落) → pack 所有 CSS FAIL" "$WORK/a7-loc.html" \
  'pack inline CSS: .doc-locator{' --artifact
# ★同一行 2 個目の追記 (errata-2 F-4): CSS は ★後勝ち ゆえ基底規則の直後に無効化宣言を並べると
#   「宣言は在るのに効いていない」形になる。 行計数 pin は 1 のまま素通った (実弾 CONFIRMED) ため
#   非 anchor の ★出現回数 == 1 pin を対で置いた。 その teeth を撃つ。
awk '{ if ($0 ~ /^\.skip-link\{/) print $0 ".skip-link{position:static;left:0}"; else print $0 }' "$HEALTHY" > "$WORK/a7-css-dup.html"
grep -qF '.skip-link{position:static;left:0}' "$WORK/a7-css-dup.html" \
  || { echo "FATAL: mutant 合成失敗 (a7-css-dup)" >&2; exit 2; }
expect_fail "MK7-3c shape(.skip-link 宣言を同一行に 2 個目追記 = 後勝ち上書き) → 出現回数 pin FAIL" "$WORK/a7-css-dup.html" \
  "pack inline CSS: '.skip-link{' の出現回数 == 1" --artifact
# ★実態開示の pin (errata-1 E-3 [should] 判断の裏取り): CSS コメント化 (/* … */) による無効化は ★塞いでいない。
#   「塞いだつもり」の false record を防ぐため、 ★素通ることを ★機械で pin する (将来 CSS 構文解析を入れて
#   塞いだ時点でこの pin が赤くなり、 実態開示の更新を強制する = 開示と実装の lockstep)。
#   ★mutant は ★宣言行を触らない ブロックコメント形にする: 宣言行自体をコメントで囲む形 (/* .skip-link{…} */) は
#   ★行頭 anchor が外れて 上の pin が赤くなる (実走で確認) — 素通るのは ★前後の行に /* … */ を挿し込み
#   宣言行を byte 単位で ★温存 する形。 これが生 grep の実限界であり、 pin すべき正しい mutant。
perl -pe 's{^(\.skip-link\{)}{/*\n$1}; s{^(\.doc-locator\{.*)$}{$1\n*/}' "$HEALTHY" > "$WORK/a7-css-cmt.html"
grep -qxF '/*' "$WORK/a7-css-cmt.html" || { echo "FATAL: mutant 合成失敗 (a7-css-cmt: 開きコメント無し)" >&2; exit 2; }
grep -qxF '*/' "$WORK/a7-css-cmt.html" || { echo "FATAL: mutant 合成失敗 (a7-css-cmt: 閉じコメント無し)" >&2; exit 2; }
grep -qE '^\.skip-link\{' "$WORK/a7-css-cmt.html" || { echo "FATAL: mutant 合成失敗 (a7-css-cmt: 宣言行が温存されていない)" >&2; exit 2; }
out="$(run_gate "$WORK/a7-css-cmt.html" --artifact)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "MK7-3b 実態開示 pin: CSS コメント化は ★素通る (生 grep の限界・封鎖は admin へ移譲。塞いだら本 pin が赤くなる)"
else bad "MK7-3b 実態開示 pin: CSS コメント化が赤くなった = 実態開示 (塞いでいない) が stale (rc=$rc)"; fi
# shape(c): escape 化け entity の注入 (patsub_replacement が &lt; を <lt; へ壊す型・平易行 / 一行タイトルの新経路で最も出やすい)。
#   ★「<lt;>」形にするのは make_body を ★通す ため: 素の「<lt;」は次の '>' までを 1 タグとして走査され、 その内側に
#   raw '<' が入ると make_body が fail-closed で BODY を空にしてしまい、 ★escape arm でなく make_body 段で落ちる
#   (= 撃ちたい arm を撃てていない mutant になる)。
perl -0pe 's{</body>}{<p><lt;></p></body>}' "$HEALTHY" > "$WORK/a7-esc.html"
expect_fail "MK7-4 shape(化け entity 注入) → escape 健全性 FAIL" "$WORK/a7-esc.html" \
  'back-ref 化け entity なし' --artifact
# ★subsumption の実態 pin (errata-2 F-3 の集計規律を自分に適用した結果の開示)。 errata-1 E-2 で closed tag
#   allowlist を入れて以降、 化け entity (<lt; / <gt; / <quot;) の ★タグ名 (lt/gt/quot) は必ず allowlist 外になるため、
#   本 mutant は ★常に make_body_live の fail-closed を先に踏む。 つまり escape arm の kill は ★巻き添え であり、
#   規律 (1)「fail-closed run の [FAIL] は kill に数えない」を適用すると ★genuine kill は作れない。
#   ★arm を消すのではなく (allowlist が緩んだ将来に単独の teeth が要る) ★subsume されている事実を機械 pin する:
#   もし将来この mutant が fail-closed を経由しなくなったら本 pin が赤くなり、 ヘッダの未着弾列挙の更新を強制する。
out="$(run_gate "$WORK/a7-esc.html" --artifact)"
if grep -qF 'make_body_live fail-closed: unknown-container:lt' <<<"$out"; then
  ok "MK7-4b ★この mutant (<lt;>) は allowlist arm に先に捕まる (mutant 個別の性質・arm の普遍性ではない)"
else bad "MK7-4b: <lt;> mutant が fail-closed を経由しなくなった (機序が変わった — MK0-4c の anchor も要確認)"; fi
# ★MK7-4c: escape arm の ★単独 genuine kill (errata-3 G-1)。 errata-2 で書いた「escape arm は構造的に単独発火
#   不能 (subsumed)」は ★誤り だった (独立 verifier が反証・実弾 2 形)。 機序: make_body_live は ★コメント本体を
#   丸ごと落とす ため、 コメント内の <lt; は ★tokenize されず unknown-container にならない。 一方 escape arm は
#   ★生 $BODY を grep する (make_body はコメントを verbatim 保持する) ので、 fail-closed を経由せず ★単独で発火する。
#   ★私の誤りの所在: 「escape arm の subject は $BODY_LIVE」と暗黙に仮定していた (実際は $BODY)。 mutant の
#   ★置き場所 (コメント内 / RAWTEXT 内 / 地の文) で経路が変わることを見落としていた。
perl -0pe 's{</body>}{<!-- <lt; --></body>}' "$HEALTHY" > "$WORK/a7-esc-solo.html"
grep -qF '<!-- <lt; -->' "$WORK/a7-esc-solo.html" || { echo "FATAL: mutant 合成失敗 (a7-esc-solo)" >&2; exit 2; }
expect_fail "MK7-4c shape(コメント内へ化け entity 注入) → escape arm が ★単独 genuine kill" "$WORK/a7-esc-solo.html" \
  'back-ref 化け entity なし' --artifact
# ★単独性の弁別 pin: fail-closed を ★経由しない こと (= 巻き添えでない genuine kill であること) を撃つ。
out="$(run_gate "$WORK/a7-esc-solo.html" --artifact)"
if ! grep -qF 'make_body_live fail-closed' <<<"$out"; then
  ok "MK7-4d 弁別: コメント内注入は fail-closed を経由せず escape arm ★のみ が赤い (genuine kill)"
else bad "MK7-4d 弁別: fail-closed 経由 = 巻き添え kill (単独 teeth を証明できていない)"; fi

# ---------------------------------------------------------------------------
# S. ★should 分岐の合成 mutant (landed corpus では ★永久未発火 = 実データ由来の被覆主張は偽証跡)
# ---------------------------------------------------------------------------
echo "  -- should 分岐 (合成 mutant) --"
# S1: contract の priority だけ should へ書換 (statement は SHALL のまま) → 契約内不変が落ちる。
#     ★これが「contract 自身が statement と矛盾する level を宣言する」型の唯一の検出器。
perl -0pe 's{(anchor: "req-ver-024"\n    )priority: "must"}{$1priority: "should"}' "$CONTRACT" > "$WORK/c-s1.yaml"
if grep -q 'priority: "should"' "$WORK/c-s1.yaml"; then
  # ★assembler 側の同判定 (validate) が先に落とすため build 自体が失敗する = fail-closed の実証。
  if ! "$ASSEMBLE" "$WORK/c-s1.yaml" "$WORK/s1.html" >"$WORK/s1.err" 2>&1 \
     && grep -qF 'priority と statement の RFC-2119 modal verb が矛盾' "$WORK/s1.err"; then
    ok "MKS-1 合成(priority だけ should) → assembler validate が build 前に fail-closed"
  else bad "MKS-1 合成(priority だけ should) が assembler で落ちない"; fi
  # gate 側でも独立に落ちること (assembler を迂回して artifact を作られた場合の二重化)。
  out="$("$GATE" --artifact "$WORK/c-s1.yaml" "$HEALTHY" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -E '^ *\[FAIL\]' <<<"$out" | grep -qF '契約内不変: priority == statement の RFC-2119 modal verb 由来 level'; then
    ok "MKS-2 合成(同上) → gate 側でも契約内不変 FAIL (assembler 迂回の二重化)"
  else bad "MKS-2 合成(同上) が gate で落ちない (rc=$rc)"; fi
else bad "MKS-1/2 fixture 合成失敗 (contract の priority 置換が効いていない)"; fi

# S2: ★完全合成 = statement の規範キーワードも SHOULD へ倒し prose ラベルも should 側 allowlist 値へ。
#     → should 分岐が ★正しく PASS する ★陽性対照 (allowlist から should entry を削る退行を捕捉する)。
perl -0pe '
  s{(anchor: "req-ver-024"\n    )priority: "must"}{$1priority: "should"};
  s{^(    statement: "<span class=\\"ears-id\\">REQ-VER-024.*)$}{ my $l=$1; $l =~ s/\bSHALL\b/SHOULD/g; $l =~ s/\bMUST\b/SHOULD/g; $l }me;
' "$CONTRACT" > "$WORK/c-s2.yaml"
perl -0pe 's{(prio-req-ver-024: ")必須(")}{$1推奨・現在$2}' "$PROSE" > "$WORK/p-s2.yaml"
out="$(run_synth "$WORK/c-s2.yaml" "$WORK/p-s2.yaml" "$WORK/s2")"; rc=$?
n_fail="$(grep -cE '^ *\[FAIL\]' <<<"$out")"
if [[ "$rc" -eq 0 && "$n_fail" -eq 0 ]] && grep -qF 'should	IN-ALLOWLIST' <<<"$out"; then
  ok "MKS-3 合成(should 一貫) → 陽性対照 PASS (should 分岐が生きている・allowlist 縮小の guard)"
else bad "MKS-3 合成(should 一貫) が PASS しない (rc=$rc FAIL=$n_fail) — should 分岐の退行かも"; fi

# S3: S2 の一貫 fixture で ★ラベルだけ must 側 (「必須」) にする → should 行の must ラベル詐称が落ちる。
#   ★fixture は healthy prose を ★そのまま 使う (prio-req-ver-024 は「必須」= must 側ラベル)。 contract 側だけが
#   should 一貫 (c-s2) なので「should の行に must ラベル」の乖離になる。 ★以前ここに置いていた perl 行は
#   恒等置換 + 入力が CONTRACT (prose slot は存在しない) + 出力 /dev/null の ★三重に無効な dead code で、
#   「fixture を合成している」ように見えて実際は何もしていなかった (独立 ceiling 指摘・偽の作業表示)。
cp "$PROSE" "$WORK/p-s3.yaml"
grep -qF 'prio-req-ver-024: "必須"' "$WORK/p-s3.yaml" \
  || { echo "FATAL: MKS-4 fixture 前提崩れ (prose の prio-req-ver-024 が「必須」でない)" >&2; exit 2; }
out="$(run_synth "$WORK/c-s2.yaml" "$WORK/p-s3.yaml" "$WORK/s3")"; rc=$?
# ★pin を ★逐値化 (errata-1 E-6): arm ラベルだけの pin は「その arm が ★何らかの理由で 赤い」しか言わず、
#   ★どの詐称を捕まえたか を確かめていない (別の乖離で赤くても PASS してしまう)。 gate が出す判定値
#   'NOT-IN-ALLOWLIST:<ラベル>' まで逐値で要求する (ラベル実体が診断に出ることも同時に pin)。
#   ★2 段 pin にする: (1) 当該 arm が [FAIL] 行に出ている (どの arm が撃たれたか) かつ
#   (2) 判定値 'NOT-IN-ALLOWLIST:<ラベル>' が ★出力全体に在る (何を捕まえたか)。
#   ★(2) を [FAIL] 行に限定できない理由: chk の actual は ★多行 (level\tverdict の列) で、 chk は 1 行目だけを
#   "got …" に載せ 2 行目以降は ★裸の行 として出る (実走で確認)。 [FAIL] 行だけを見ると常に取り落とす。
if [[ "$rc" -ne 0 ]] \
   && grep -E '^ *\[FAIL\]' <<<"$out" | grep -qF 'rq-prio: (level, 可視ラベル∈allowlist) 列' \
   && grep -qF 'NOT-IN-ALLOWLIST:必須' <<<"$out"; then
  ok "MKS-4 合成(should 行に「必須」ラベル) → 当該 arm FAIL + NOT-IN-ALLOWLIST:必須 を逐値確認"
else bad "MKS-4 合成(should 行に「必須」) が当該 arm + 'NOT-IN-ALLOWLIST:必須' で落ちない (rc=$rc)"; fi

# S4: S2 の一貫 fixture で ★否定接尾 (「推奨ではない」) → 前方一致判定なら素通る形を撃つ。
perl -0pe 's{(prio-req-ver-024: ")必須(")}{$1推奨ではない$2}' "$PROSE" > "$WORK/p-s4.yaml"
# ★前提 guard (errata-1 E-6・MKS-4 と同型の非対称を解消): 置換が当たらなければ p-s4 は healthy と同じ
#   「必須」のままで、 撃っているのは ★MKS-4 と同じ形 (must ラベル詐称) に ★縮退 する — それでも同じ arm が
#   赤くなるため ★偽 PASS になる。 変異の実在を FATAL guard で確かめてから撃つ。
grep -qF 'prio-req-ver-024: "推奨ではない"' "$WORK/p-s4.yaml" \
  || { echo "FATAL: MKS-5 fixture 合成失敗 (否定接尾への置換が当たっていない = MKS-4 へ縮退)" >&2; exit 2; }
out="$(run_synth "$WORK/c-s2.yaml" "$WORK/p-s4.yaml" "$WORK/s4")"; rc=$?
if [[ "$rc" -ne 0 ]] \
   && grep -E '^ *\[FAIL\]' <<<"$out" | grep -qF 'rq-prio: (level, 可視ラベル∈allowlist) 列' \
   && grep -qF 'NOT-IN-ALLOWLIST:推奨ではない' <<<"$out"; then
  ok "MKS-5 合成(否定接尾「推奨ではない」= ehar) → 当該 arm FAIL + NOT-IN-ALLOWLIST:推奨ではない を逐値確認"
else bad "MKS-5 合成(否定接尾) が当該 arm + 'NOT-IN-ALLOWLIST:推奨ではない' で落ちない (rc=$rc)"; fi

# ---------------------------------------------------------------------------
# arm T. ★MK 未着弾 arm の teeth 実弾 (errata-1 E-7) — 静的 band §番号 2 arm (contract 合成) / role allowlist 外 /
#         >null< 注入 / 可視 rid 偽造 (VIS-MISMATCH)
# ---------------------------------------------------------------------------
# ★kill map 実測で「一度も [FAIL] を出さない arm」= teeth が未証明の arm。 non-vacuous を主張する以上、
#   ★どの arm も 1 度は赤くできる ことを実弾で示す (示せないものは suite ヘッダに未被覆として明示列挙する)。
echo "  -- arm T (MK 未着弾 arm の teeth 実弾) --"
# (a) ★静的 band §番号 2 arm (§5 / §6) — 契約非依存 pin ゆえ ★contract 側の §番号を動かして撃つ。
#     静的 band の §番号は「最終 section の §N の次 / 次々」として ★導出 されるので、 最終 section の heading を
#     §4 → §7 にすると導出解が §8 / §9 になり、 実測 literal (§5 / §6) と食い違って両 pin が落ちる。
#     ★section 追加でなく ★heading の付替 にするのは、 contract の他 field (anchor 列 / prose slot 集合) を
#     動かさず ★狙った 2 arm だけを撃つため (巻き添え発火だと teeth の帰属が曖昧になる)。
perl -0pe 's{heading: "§4\. References"}{heading: "§7. References"}' "$CONTRACT" > "$WORK/c-sec.yaml"
grep -qF 'heading: "§7. References"' "$WORK/c-sec.yaml" \
  || { echo "FATAL: mutant 合成失敗 (c-sec: 最終 section heading の付替が当たっていない)" >&2; exit 2; }
"$ASSEMBLE" "$WORK/c-sec.yaml" "$WORK/tsec-a.html" >/dev/null 2>&1
[[ -s "$WORK/tsec-a.html" ]] || { echo "FATAL: mutant 合成失敗 (c-sec: assemble が出力を作れない)" >&2; exit 2; }
out2="$("$GATE" "$WORK/c-sec.yaml" "$WORK/tsec-a.html" 2>&1)"; rc2=$?
if [[ "$rc2" -ne 0 ]] && grep -E '^ *\[FAIL\]' <<<"$out2" | grep -qF '静的 band §番号 (前方照会)'; then
  ok "MKT-1 合成(最終 section を §4→§7) → 静的 band §番号 (前方照会) の契約非依存 pin FAIL"
else bad "MKT-1 静的 band §番号 (前方照会) が撃てない (rc=$rc2)"; fi
if [[ "$rc2" -ne 0 ]] && grep -E '^ *\[FAIL\]' <<<"$out2" | grep -qF '静的 band §番号 (用語集)'; then
  ok "MKT-2 合成(同上) → 静的 band §番号 (用語集) の契約非依存 pin FAIL"
else bad "MKT-2 静的 band §番号 (用語集) が撃てない (rc=$rc2)"; fi
# (b) ★references role 抽象 allowlist — data-ref-role を allowlist 外 token へ書換える。
perl -0pe 's{data-ref-role="rationale"}{data-ref-role="bogus-role"}' "$HEALTHY" > "$WORK/t-role.html"
grep -qF 'data-ref-role="bogus-role"' "$WORK/t-role.html" || { echo "FATAL: mutant 合成失敗 (t-role)" >&2; exit 2; }
expect_fail "MKT-3 shape(data-ref-role を allowlist 外へ) → role 抽象 allowlist FAIL" "$WORK/t-role.html" \
  'references: role が抽象 allowlist 内' --artifact
# (c) ★null セル漏れ — '>null<' を注入 (contract の欠損値が素通って可視化する形の代理)。
perl -0pe 's{(<p class="rq-essence">)}{$1>null<}' "$HEALTHY" > "$WORK/t-null.html"
grep -qF '>null<' "$WORK/t-null.html" || { echo "FATAL: mutant 合成失敗 (t-null)" >&2; exit 2; }
expect_fail "MKT-4 shape('>null<' 注入) → null セル漏れ arm FAIL" "$WORK/t-null.html" \
  'null セル漏れなし' --artifact
# (d) ★可視 rid の偽造 (VIS-MISMATCH 分岐) — attr は据置き ★可視テキストだけ を別 ID にする。
#     row 構造 anchor の tuple 側で VIS-MISMATCH として弾かれることを撃つ (attr-vs-visible の非対称 pin)。
perl -0pe 's{(<span class="rid">)REQ-VER-024(</span>)}{$1REQ-VER-999$2}' "$HEALTHY" > "$WORK/t-vis.html"
grep -qF '<span class="rid">REQ-VER-999</span>' "$WORK/t-vis.html" || { echo "FATAL: mutant 合成失敗 (t-vis)" >&2; exit 2; }
expect_fail "MKT-5 shape(可視 rid だけ偽造) → row 構造 anchor で VIS-MISMATCH FAIL" "$WORK/t-vis.html" \
  '要件 row 構造 anchor 列' --artifact

# ---------------------------------------------------------------------------
# E. exit-code 規約 (0 / 1 / 2 の分離)
# ---------------------------------------------------------------------------
echo "  -- exit-code 規約 --"
"$GATE" --artifact "$WORK/no-such-contract.yaml" "$HEALTHY" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "E1 exit 規約: contract 不在 → exit 2 (tool error)"
else bad "E1 exit 規約: contract 不在が exit 2 でない (rc=$rc)"; fi
"$GATE" --artifact "$CONTRACT" "$WORK/no-such.html" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "E2 exit 規約: html 不在 → exit 2 (tool error)"
else bad "E2 exit 規約: html 不在が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  srs-verification 提示層 floor 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
