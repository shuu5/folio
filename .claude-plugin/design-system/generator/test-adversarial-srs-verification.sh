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
# ★現状 (errata-3 G-1 適用後の ★規律準拠 再測 + folio-3zr4 Leg C の containment 追加後の再測 +
#   ★folio-3zr4.3 self-review round-2 の ★独立再測 で ★是正 した形):
#   ★★主張の ★射程 を 3 つに割る (割らずに「全 arm kill 済」と書くと ★per-instance で false record になる):
#   (a) ★artifact の改竄で落ちる arm — ★per-shape (DOM 構造クラス) では ★未着弾 0 本。 containment の ★25 構造
#       クラス (章 id / §番号 / tint / 文書総数を正規化した label 集合 27 − 機構健全性 2) は ★全数 が
#       「単独発火の実弾」を 1 本以上持つ (admin gate errata-1 後の再測。 新設した章帰属 2 クラスは MKC-52 / MKC-53)。
#   (a') ★★per-instance では 未着弾が残る (★是正前の本注記はここを「未着弾 0」と書いており false record だった)。
#       ★集計規律 (1) を機械適用した独立再測 (全 gate 実行 134 run の [FAIL] を run 単位で収集し、 ★token 列が
#       捨てられた run 〔= containment tokenizer の構造診断の値が `unclosed-child-*` / `foreign-at-depth1-*` /
#       `marker-on-foreign-element-*` ★以外 = probe が @t を空にする分岐に入った run〕では ★宣言 kill である
#       tokenizer arm ★だけ を数え 残りの巻き添えは捨てる、 で突合) の結果、 ★artifact 改竄で落ちうる
#       containment arm ★81 本 のうち ★24 本 は mass-collateral run でしか赤くならず ★単独発火の実弾を持たない。
#       ★★母数は ★導出形 で書く (手書き literal は stale 化して false record になる — 実際 ★是正前の本注記は
#       母数を 66 と書いており、 XSPEC 4 arm 〔tbl-wrap xdoc / spec-table xpayseq / rq-list xdoc / EARS xpayseq〕が
#       (a') (b) の ★どちらの分類にも入らない 未分類のまま残っていた = trust anchor 完結性 sweep が閉じていなかった。
#       当該 4 arm は MKC-38/39/40/41 が単独捕捉する = ★着弾済 側である):
#         ★母数 = ★arm 2C の OK ★行 数 (= EXPECTED_OK_ARTIFACT のうち arm 2C 分・実測 87・下の MECH_ARM2C_OK が
#         機械 pin) − ★下の (b) の機構健全性 2 本 = 85 行。 ★ただし 数えるのは ★distinct な chk label で、
#         85 行のうち ★docct の 5 行 は ★章 id を含まない同一ラベル (「章要旨 callout が ★文書全体で 5 個 …」) で
#         ★実質 1 assertion のため 1 本に畳む → ★母数 = 81 本 (distinct label 単位)。
#         ★★単位を明示するのはこれが 3 度目の false record 源だったため (行 / label / instance を混ぜると数が動く)。
#         arm を足したら ★この再測ごと やり直す (数値だけの追随は禁止 = 裁定条項 (2))。
#       ★未着弾 24 本の内訳 (章ごと・admin gate errata-1 で章帰属 2 arm を足した後の ★再測値):
#         ・s1-boundary-model の containment 8 arm ★全部 (adj / band==1 / chapbody==1 / kids==2 / bkids==4 /
#           cbkids / cbadj / cont)
#         ・s4-references の 7 arm (band==1 / chapbody==1 / bkids==4 / cbadj / cont / ★章要旨 xpayseq / ★sese
#           — ★adj / cbkids / kids は MKC-10 〔s3→s4 の別章移送〕/ MKC-22b 〔幽霊 <div_x> による fold の chapbody 外
#           移送〕が単独 run で撃っている = 未着弾ではない)
#         ・s3-coverage-rtm の 7 arm (band==1 / chapbody==1 / cbadj / cont / ★章要旨 xpayseq / ★sese / ★mflab)
#         ・s2-done-condition-req の 1 arm (★mflab = 「fold を持たない章」の負の主張側)
#         ・s0-reader-guide の 1 arm (chapbody==1)
#       ★新設した章帰属 2 arm (sese / mflab) は ★s0 / s1 の instance を MKC-52 / MKC-53 が単独で撃つ (per-shape 充足)。
#         残る s2 / s3 / s4 の instance は ★同一構造クラスの別 instance ゆえ (a) の per-shape 主張は保つ。
#       ★これらは ★同一構造クラスの別 instance が撃たれている ため (a) の per-shape 主張は保つが、
#       「全 arm が実弾で anchor される」と ★instance 単位で 読める書き方は ★しない (宣言 == 実能力)。
#   (b) ★検査機構そのものの健全性 arm 2 本 (「containment 駆動表が全章を覆う」「containment probe が全章分の実測を
#       出力」) — artifact をどう改竄しても落ちない (script 改変でしか落ちない) ため ★構造上 per-shape MK を持てない。
#       これらは ★MECHPIN 節 (tracked 静的 pin) が arm の実在と期待値の導出形を押さえる = ★MK 対象外だが担保は残る。
#       ★union (巻き添え込み) で見た未着弾が この 2 本 ★だけ であることも同再測で verified。
#   ★★本再測の ★射程 (未実施の明示): 上の (a') は ★containment arm (subject = $BODY) についての再測である。
#       ★$BODY_LIVE 系 arm 群 への同じ per-instance 再測 (= live view の fail-closed run 〔`make_body_live
#       fail-closed:` が立つ run〕 を除外して数え直す) は ★本 commit では未実施 — そちらの MK 被覆主張は
#       ★union ベースの旧主張のまま である。 「全 arm を per-instance で撃った」と読まないこと。
#   ゆえ「未着弾 0」は ★(a) = per-shape についての主張であり (a') (b) を含まない。 HEADLINE_ARMS は ★arm 総数 の
#   逐値であって「全 arm が MK 済」の含意は ★持たない (下の HEADLINE_ARMS コメントに同旨を焼く)。
# ★★docct (器の重複 = 逃げ場) の per-shape 未着弾は ★本 commit で解消した: 是正前は docct を撃つ実弾が MKC-14
#   (期待値 ★literal 1 の instance) ★1 本だけ で、 ★期待値が contract 章数由来 (N>1) の分岐 と ★data-component 軸の
#   器 は ★同じ攻撃 shape のまま未着弾だった。 MKC-45 (章要旨 callout の 2 個目注入 = N>1 分岐) / MKC-46
#   (glossary-term-table の 2 個目注入) を足して塞いだ。
# ★containment (arm 2C) の MK は ★MKC-* 系で採番する (本 suite 内の独立採番)。 うち 4 本 (MKC-20/21/26/29) は
#   副作用で make_body_live の fail-closed も踏むため、 ★集計規律 (1) の適用を ★MKC-C1 弁別対照 が機械で担保する
#   (live view だけを fail-closed させた対照で containment arm が 1 本も赤くならないことを撃つ = 巻き添えでないと isolate)。
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
#   ★★同クラスの false record が Leg C (containment 追加) で ★再発 した — headline 数値ではなく ★MK 被覆の
#   全称主張 の側で。 是正は ★2 段: (i) per-shape へ narrow + per-instance 残差 24 本の逐語開示 (上の (a')) と
#   (ii) ★撃てる shape には実弾を足す (MKC-45 / MKC-46 = docct の未着弾 shape) — errata-1 と同じく
#   「言い訳せず撃つ」側を優先し、 撃てない残差 (per-instance) だけを開示に落とした。
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
EXPECTED_OK_ARTIFACT=144
EXPECTED_OK_PREFILL=141
# ★ヘッダ headline が主張する ★arm 総数。 ★EXPECTED_OK_ARTIFACT と ★同値でなければならない。 下の H7 が
#   機械照合し、 片方だけ動かすと ★赤くなる。
# ★★含意の ★是正 (folio-3zr4 Leg C・false record 封鎖): 旧コメントは本値を「★全 genuine kill 済 arm 数」と定義し
#   「未着弾 0 = 全 arm が kill 済 = arm 総数と一致する」と書いていた。 containment の追加で ★機構健全性 arm 2 本
#   (駆動表被覆 / probe 出力行数) が入り、 これらは ★構造上 per-shape MK を持てない (MECHPIN が担保) ため
#   旧定義のままだと ★宣言 > 実能力 になる。 ★本値は arm 総数 の逐値であり、 MK 被覆の主張は ★ヘッダの
#   (a)/(a')/(b) 三分 に従う (「(a) artifact 改竄で落ちる arm は ★per-shape で未着弾 0」/「(a') per-instance では
#   containment 24 arm が単独発火の実弾を持たない = 逐語開示」/「(b) 機構健全性 arm 2 本は MECHPIN 担保」)。
HEADLINE_ARMS=144

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
  # ★★`producer | grep -q` を書かない (admin gate errata-1 で ★実際に踏んだ 偽 RED・protocol §2 test-first 節):
  #   `set -o pipefail` 下で 下流の `grep -q` が ★最初の一致で早期 exit すると、 上流 grep が SIGPIPE 死して
  #   pipeline rc=141 になり ★条件が偽 になる。 FAIL 行が多い mutant ほど当たりやすく、 ★探している行が
  #   先頭に来た瞬間に 偽 RED になる (MKC-32 = FAIL 85 行・目的の行が 1 行目 で顕在化した)。
  #   ★方向は常に under-report (撃てているのに「撃てていない」と出る) ゆえ ★見逃しではなく誤停止 を生む。
  #   ★ゆえ 2 段に割る: 先に FAIL 行だけを ★変数へ確定 し、 その herestring に対して grep する (pipe を作らない)。
  local fails
  fails="$(grep -E '^ *\[FAIL\]' <<<"$out")"
  if [[ "$rc" -ne 0 && -n "$fails" ]] && grep -qF -- "$sub" <<<"$fails"; then
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
if grep -qF 'out-of-scope = 機械層 cross-fold round-trip=folio-e706' <<<"$(run_gate "$HEALTHY" --artifact)"; then
  ok "H4 実態開示: out-of-scope (機械層 cross-fold round-trip / frozen census / CSS 由来の不可視) を出力で開示"
else bad "H4 実態開示: out-of-scope 開示行が無い"; fi
# ★H4b ★in-scope 側の開示 pin (Leg C = folio-3zr4.3 で containment を移植した後の ★実態): 旧 H4 は
#   「containment=folio-3zr4 (対象外)」を pin していたが、 移植後にそれを残すと ★実装済の検査を「していない」と
#   宣言する false record になる。 ★開示と実装の lockstep を機械で維持するため in-scope 側も pin する
#   (containment を外したら本 pin が赤くなり、 開示文の更新を強制する)。
if grep -qF 'scope = 提示層 shape + containment' <<<"$(run_gate "$HEALTHY" --artifact)"; then
  ok "H4b 実態開示: in-scope に containment (章化の実質) が含まれることを出力で開示 (移植後の実態と一致)"
else bad "H4b 実態開示: in-scope の containment 開示行が無い (実装と開示の drift)"; fi
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
  ok "H7 headline 整合: ヘッダ主張 arm 数 == 実 arm 数 ($HEADLINE_ARMS・★arm 総数の逐値であって MK 未着弾 0 の含意は持たない)"
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
  mks2_fails="$(grep -E '^ *\[FAIL\]' <<<"$out")"
  if [[ "$rc" -ne 0 ]] && grep -qF '契約内不変: priority == statement の RFC-2119 modal verb 由来 level' <<<"$mks2_fails"; then
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
   && { mks4_fails="$(grep -E '^ *\[FAIL\]' <<<"$out")"; grep -qF 'rq-prio: (level, 可視ラベル∈allowlist) 列' <<<"$mks4_fails"; } \
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
   && { mks5_fails="$(grep -E '^ *\[FAIL\]' <<<"$out")"; grep -qF 'rq-prio: (level, 可視ラベル∈allowlist) 列' <<<"$mks5_fails"; } \
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
mkt_fails="$(grep -E '^ *\[FAIL\]' <<<"$out2")"
if [[ "$rc2" -ne 0 ]] && grep -qF '静的 band §番号 (前方照会)' <<<"$mkt_fails"; then
  ok "MKT-1 合成(最終 section を §4→§7) → 静的 band §番号 (前方照会) の契約非依存 pin FAIL"
else bad "MKT-1 静的 band §番号 (前方照会) が撃てない (rc=$rc2)"; fi
if [[ "$rc2" -ne 0 ]] && grep -qF '静的 band §番号 (用語集)' <<<"$mkt_fails"; then
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
# arm 2C (containment). ★章化の実質 = 帰属の per-shape MK 群 (folio-3zr4 Leg C)
# ---------------------------------------------------------------------------
# ★生成物の改竄で落ちる arm ゆえ、 ★各 arm に「その arm が [FAIL] 理由を担う」実弾を 1 本以上 与える
#   (arm を消すと本 suite が赤くなる = mutation-kill)。 ★全て fired-guard 付き (shape drift による空撃ちを検出)。
# ★per-shape 規律 (jyfh / r8k): 1 instance の実弾は ★構造差のある instance の穴を証明しない — wrapper 2 章
#   (payload = ref-grid / glossary-term-table) と契約章 (payload = 章要旨 callout) は ★別クラス ゆえ別実弾で撃つ。
# ★reason anchor は ★章名込み の label へ当てる (章非特定の語だと別章の巻き添え FAIL でも満たされ per-shape の
#   主張が pin されない)。 ★MKC 番号は ★本 suite 内の独立採番 (Leg A / Leg B の CT 番号への lockstep は無い)。
# ★★containment の subject は ★$BODY (他 arm の $BODY_LIVE と非対称・verify 側 arm 2C の冒頭に理由を逐語開示)。
#   ゆえ tokenizer 系 mutant は ★make_body_live の fail-closed を経由せずに 当該 arm を単独で赤くできる —
#   これは本 suite 冒頭の ★集計規律 (1)「fail-closed run の [FAIL] は kill に数えない」を満たすための設計選択で、
#   $BODY_LIVE を subject にしていたら ★genuine kill を 1 本も作れなかった (裁定 srs 条項 (1) の load-bearing な理由)。
echo "  -- arm 2C (containment = 章化の実質) --"
mkc_fired() { # $1 = ラベル (perl の fired-guard が発火しなかったときは FATAL で suite ごと止める)
  echo "FATAL: $1 mutation が発火せず (shape drift = 空撃ち・偽 PASS を作らない)" >&2; exit 2
}
# --- 開口隣接 pin (i): 位置 / 識別 (tint) / 節同一性 (§番号) の 3 成分を ★別実弾 で撃つ ---
# MKC-1. ★契約章の hollow 化 — 開きタグを即閉じし band / chapbody を章の ★外 へ押し出す。 タグ均衡は保たれる
#   ため section anchor 列・件数 census・wrapper 陽性 assert は ★全て素通る (章化の「実質」だけが壊れる形)。
cp "$HEALTHY" "$WORK/mkc1.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="s2-done-condition-req">\n#<section id="s2-done-condition-req"></section>\n#; $n += s#</section>\n<section id="s3-coverage-rtm">#<section id="s3-coverage-rtm">#; END { exit($n==2?0:9) }' "$WORK/mkc1.html" || mkc_fired MKC-1
expect_fail "MKC-1 shape(契約章 s2 の hollow 化) → containment 開口隣接 pin FAIL" "$WORK/mkc1.html" \
  "章 's2-done-condition-req' の開口直後に" --artifact
# MKC-2. ★提示層 wrapper の hollow 化 — 契約章 (MKC-1) と ★別クラス (payload = chip / 器 = ref-grid)。
cp "$HEALTHY" "$WORK/mkc2.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="forward-refs">\n#<section id="forward-refs"></section>\n#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$WORK/mkc2.html" || mkc_fired MKC-2
expect_fail "MKC-2 shape(wrapper forward-refs の hollow 化) → containment 開口隣接 pin FAIL" "$WORK/mkc2.html" \
  "章 'forward-refs' の開口直後に" --artifact
# MKC-2b. ★用語集 wrapper の hollow 化 — MKC-2 と ★別 instance (payload が chip でなく .grow 行の別構造クラス)。
cp "$HEALTHY" "$WORK/mkc2b.html"
perl -0777 -i -pe 'our $n; $n += s#<section id="glossary-terms">\n#<section id="glossary-terms"></section>\n#; $n += s#</section>\n</div>\n<footer#</div>\n<footer#; END { exit($n==2?0:9) }' "$WORK/mkc2b.html" || mkc_fired MKC-2b
expect_fail "MKC-2b shape(wrapper glossary-terms の hollow 化・別 payload クラス) → 開口隣接 pin FAIL" "$WORK/mkc2b.html" \
  "章 'glossary-terms' の開口直後に" --artifact
# MKC-3. ★開口への異物挿入 (位置成分) — band は残り tint / §番号も正しいが 開口と band の ★間 に別要素が入る。
cp "$HEALTHY" "$WORK/mkc3.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n)#${1}<p class="decoy"></p>\n#; END { exit($n==1?0:9) }' "$WORK/mkc3.html" || mkc_fired MKC-3
expect_fail "MKC-3 shape(開口と章帯の間へ異物挿入) → 開口隣接 pin の位置成分 FAIL" "$WORK/mkc3.html" \
  "章 'forward-refs' の開口直後に" --artifact
# MKC-4. ★band tint の逐値付け替え (識別成分・wrapper 側 = assembler literal 由来 tint)。
cp "$HEALTHY" "$WORK/mkc4.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-)violet(">)#${1}ok${2}#; END { exit($n==1?0:9) }' "$WORK/mkc4.html" || mkc_fired MKC-4
expect_fail "MKC-4 shape(wrapper band の tint 付け替え) → 開口隣接 pin の識別成分 FAIL" "$WORK/mkc4.html" \
  "章 'forward-refs' の開口直後に" --artifact
# MKC-4b. ★契約章 band の tint 付け替え — MKC-4 と ★別 instance (期待値の源が ★contract の sections[].tint)。
#   §番号は動かさないので tint 成分 ★単独 の teeth を isolate する。
cp "$HEALTHY" "$WORK/mkc4b.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s3-coverage-rtm">\n<section data-component="chapter-deck-band" class="tint-)info(">)#${1}ok${2}#; END { exit($n==1?0:9) }' "$WORK/mkc4b.html" || mkc_fired MKC-4b
expect_fail "MKC-4b shape(契約章 s3 band の tint 付け替え・contract 由来 tint) → 開口隣接 pin FAIL" "$WORK/mkc4b.html" \
  "章 's3-coverage-rtm' の開口直後に" --artifact
# MKC-5. ★band §番号の逐値書換 (節同一性成分) — 静的 band の §番号は contract 最終 section から ★導出 される。
cp "$HEALTHY" "$WORK/mkc5.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band" class="tint-violet"><span class="num">)5(</span>)#${1}8${2}#; END { exit($n==1?0:9) }' "$WORK/mkc5.html" || mkc_fired MKC-5
expect_fail "MKC-5 shape(band §番号の逐値書換) → 開口隣接 pin の節同一性成分 FAIL" "$WORK/mkc5.html" \
  "章 'forward-refs' の開口直後に" --artifact
# --- region 占有 pin (ii) ---
# MKC-6. ★band の重複注入 (region 占有の ★上限側) — 「隣に band が在る」だけの弱い pin なら素通る形。
cp "$HEALTHY" "$WORK/mkc6.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<section data-component="chapter-deck-band" class="tint-violet"></section>\n#; END { exit($n==1?0:9) }' "$WORK/mkc6.html" || mkc_fired MKC-6
expect_fail "MKC-6 shape(章帯の重複注入) → region 占有 pin (章帯 == 1) FAIL" "$WORK/mkc6.html" \
  "章 'forward-refs' region 内の章帯 == 1" --artifact
# MKC-7. ★chapbody だけを章の外へ (band 隣接は保持) — 開口隣接 pin は PASS のまま region 占有 pin ★だけ が発火する
#   (= 2 段の pin が互いの巻き添えでなく ★独立に teeth を持つ ことの per-shape 実証)。
cp "$HEALTHY" "$WORK/mkc7.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$WORK/mkc7.html" || mkc_fired MKC-7
expect_fail "MKC-7 shape(chapbody だけを章の外へ・band 隣接は保持) → region 占有 pin が単独で FAIL" "$WORK/mkc7.html" \
  "章 'forward-refs' region 内の chapbody == 1" --artifact
# --- 3 レベル完全子数束縛 (kids / bkids / cbkids) ---
# MKC-8. ★章要旨を残した章本文の sibling 押し出し (block 粒度) — 1 段内側 pin (cbadj / cont / docct) は callout が
#   chapbody 内に残るため ★全て PASS する。 捕捉は「章の直下は 章帯 + chapbody の 2 子だけ」★単独。
cp "$HEALTHY" "$WORK/mkc8.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s3-coverage-rtm">.*?<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)#${1}</div>\n#s; $n += s#</div>\n</section>\n<section id="s4-references">#</section>\n<section id="s4-references">#; END { exit($n==2?0:9) }' "$WORK/mkc8.html" || mkc_fired MKC-8
expect_fail "MKC-8 shape(章要旨を残した章本文の sibling 押し出し) → 章直下 2 子の構造 pin FAIL" "$WORK/mkc8.html" \
  "章 's3-coverage-rtm' の直下は 章帯 + chapbody の 2 子だけ" --artifact
# MKC-9. ★relocation の ★もう一方の向き — 押し出し先を sibling でなく ★章帯 (band) の中 にする。 章直下は
#   band + chapbody のままで kids pin は ★2 を保ち PASS する。 捕捉は band 直下 4 子固定 (共有 CORE band()) ★単独。
cp "$HEALTHY" "$WORK/mkc9.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s3-coverage-rtm">\n<section data-component="chapter-deck-band"[^\n]*?)(</section>\n)(<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)(.*?)(</div>\n</section>\n<section id="s4-references">)#${1}${4}${2}${3}${5}#s; END { exit($n==1?0:9) }' "$WORK/mkc9.html" || mkc_fired MKC-9
expect_fail "MKC-9 shape(章本文の band subtree への退避・kids を 2 に保つ向き) → band 4 子固定 FAIL" "$WORK/mkc9.html" \
  "章 's3-coverage-rtm' の章帯の直下は num/kicker/h2/lead の 4 子だけ" --artifact
# MKC-10. ★document 順を ★保つ relocation (β) — 章本文を ★別章の chapbody へ移送 する。 章直下 / band 直下を
#   固定しても他の probe 値を ★一切動かさず に素通る形。 捕捉は chapbody 直下の ★契約由来 完全子列 ★単独。
cp "$HEALTHY" "$WORK/mkc10.html"
perl -0777 -i -pe 'our $n; our $blk;
if (s#(<div class="tbl-wrap"><table data-component="spec-table">.*?</table></div>\n)##s) { $blk = $1; $n++ }
$n++ if defined $blk && s#(<section id="s4-references">\n<section data-component="chapter-deck-band"[^\n]*</section>\n<div class="chapbody">\n<div data-component="section-essence-callout">.*?</div>\n)#${1}$blk#s;
END { exit($n==2?0:9) }' "$WORK/mkc10.html" || mkc_fired MKC-10
expect_fail "MKC-10 shape(章本文の別章 chapbody への移送・document 順保存) → 契約由来 完全子列 FAIL" "$WORK/mkc10.html" \
  "章 's3-coverage-rtm' の chapbody 直下は 契約由来の完全子列" --artifact
# MKC-11. ★filler 置換 relocation (γ) — 章本文を ★同章の machine-fold (既定非表示の <details>) へ退避させ、
#   抜けた位置へ ★空 <div> を 1 個 挿す。 章直下 / band 直下 / chapbody 直下の ★どの子数も動かない ため
#   「数だけ束縛して identity を束縛しない」実装では ★全 arm 素通り する。 捕捉は ★marker 列 (無印 `div:-`) ★単独。
cp "$HEALTHY" "$WORK/mkc11.html"
perl -0777 -i -pe 'our $n; our $blk;
if (s#<div class="tbl-wrap"><table data-component="spec-table">(.*?)</table></div>\n#<div></div>\n#s) { $blk = "<div class=\"tbl-wrap\"><table data-component=\"spec-table\">$1</table></div>\n"; $n++ }
$n++ if defined $blk && s#(<section id="s3-coverage-rtm">.*?<div class="machine-body">\n)#${1}$blk#s;
END { exit($n==2?0:9) }' "$WORK/mkc11.html" || mkc_fired MKC-11
expect_fail "MKC-11 shape(filler 付き machine-fold 退避・子数を保つ形) → 契約由来 完全子列 FAIL" "$WORK/mkc11.html" \
  "章 's3-coverage-rtm' の chapbody 直下は 契約由来の完全子列" --artifact
# --- 1 段内側 (iii): chapbody 開口隣接 / 器の占有 / 器の文書総数 / payload 全数 ---
# MKC-12. ★chapbody 開口と payload container の間への異物挿入 (1 段内側の位置成分)。
cp "$HEALTHY" "$WORK/mkc12.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">.*?<div class="chapbody">\n)(<div class="ref-grid">)#${1}<p class="decoy"></p>\n${2}#s; END { exit($n==1?0:9) }' "$WORK/mkc12.html" || mkc_fired MKC-12
expect_fail "MKC-12 shape(chapbody 開口と器の間へ異物挿入) → 1 段内側の開口隣接 pin FAIL" "$WORK/mkc12.html" \
  "章 'forward-refs' の chapbody 開口直後に ref-grid が隣接" --artifact
# MKC-13. ★契約章の chapbody 空化 + 章本文 sibling 押し出し — wrapper 側 (MKC-2) と ★別クラス
#   (器 = 章要旨 callout)。 捕捉は「章要旨 callout が chapbody 内に 1 個」。
cp "$HEALTHY" "$WORK/mkc13.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s0-reader-guide">.*?<div class="chapbody">)\n(<div data-component="section-essence-callout">)#${1}</div>\n${2}#s; $n += s#</div>\n</section>\n<section id="s1-boundary-model">#</section>\n<section id="s1-boundary-model">#; END { exit($n==2?0:9) }' "$WORK/mkc13.html" || mkc_fired MKC-13
expect_fail "MKC-13 shape(契約章 s0 の chapbody 空化 + 章本文 sibling 押し出し) → 1 段内側の器占有 pin FAIL" "$WORK/mkc13.html" \
  "章要旨 callout が章 's0-reader-guide' の chapbody 内に 1 個" --artifact
# MKC-14. ★器の重複 (漏出先の先置き) — 正規の ref-grid は中身ごと残したまま文書の別位置に 2 個目を足す。
#   per-章 arm は ★全て PASS のままで、 2 個目の器は以後の改竄で payload の ★逃げ場 になる。 捕捉は文書総数 pin ★単独。
cp "$HEALTHY" "$WORK/mkc14.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref-grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc14.html" || mkc_fired MKC-14
expect_fail "MKC-14 shape(payload container の重複) → 器の文書総数 pin が単独で FAIL" "$WORK/mkc14.html" \
  "ref-grid が ★文書全体で 1 個" --artifact
# MKC-15. ★hollow ref-grid — 器は正規位置に残したまま chip 全数を器の ★外 へ出す。 捕捉は payload 占有 pin ★単独。
cp "$HEALTHY" "$WORK/mkc15.html"
perl -0777 -i -pe 'our $n; $n += s#(<div class="ref-grid">)\n#${1}</div>\n#; $n += s#(<div data-component="cross-doc-ref-chip" data-ref-token="ADR-0033".*?</div>\n)</div>\n#${1}#s; END { exit($n==2?0:9) }' "$WORK/mkc15.html" || mkc_fired MKC-15
expect_fail "MKC-15 shape(hollow ref-grid・chip 全数を器の外へ) → payload 占有 pin が単独で FAIL" "$WORK/mkc15.html" \
  "前方照会 chip の ★全数 が章 'forward-refs' の ref-grid 内" --artifact
# MKC-16. ★hollow glossary-term-table — MKC-15 と ★別構造クラス (payload が chip でなく .grow 行)。
cp "$HEALTHY" "$WORK/mkc16.html"
perl -0777 -i -pe 'our $n; $n += s#(<div data-component="glossary-term-table">)\n#${1}</div>\n#; $n += s#(<div class="grow"><div class="gword">EARS.*?</div></div>\n)</div>\n#${1}#s; END { exit($n==2?0:9) }' "$WORK/mkc16.html" || mkc_fired MKC-16
expect_fail "MKC-16 shape(hollow glossary-term-table・.grow 全数を器の外へ) → payload 占有 pin FAIL" "$WORK/mkc16.html" \
  "用語集 行 (.grow) の ★全数 が章 'glossary-terms' の glossary-term-table 内" --artifact
# --- parser-differential (r8k / folio-wq4 再発クラス) の vector 群 ---
#   いずれも 「本物の </section> を band 直後へ入れて章本文を章の ★外 へ出し、 元の閉じタグを ★偽タグ で置換して
#   ★素朴な深さ計数 の帳尻だけ合わせる」 shape。 make_body はコメント / RAWTEXT の中身を verbatim 保持し、
#   属性値内の生 `>` も (raw `<` と違い) fail-closed しないため、 生テキストへの素朴な section 走査は
#   region を ★over-slice して containment を丸ごと素通す。
#   ★vector を別実弾で撃つ: マスク対象のクラスが違い、 1 本の実弾は他の穴を証明しない (per-shape 規律)。
# MKC-17. ★コメント密輸。
cp "$HEALTHY" "$WORK/mkc17.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<!--<section>-->\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$WORK/mkc17.html" || mkc_fired MKC-17
expect_fail "MKC-17 shape(コメント密輸による region over-slice) → containment が捕捉" "$WORK/mkc17.html" \
  "章 'forward-refs' region 内の chapbody == 1" --artifact
# MKC-18. ★script (RAWTEXT) 密輸 — コメントとは別経路 (make_body は script 中身を opaque 保持する)。
cp "$HEALTHY" "$WORK/mkc18.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<script>var s = "<section>";</script>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<script>var e = "</section>";</script>\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$WORK/mkc18.html" || mkc_fired MKC-18
expect_fail "MKC-18 shape(script RAWTEXT 密輸による region over-slice) → containment が捕捉" "$WORK/mkc18.html" \
  "ref-grid が章 'forward-refs' の chapbody 内に 1 個" --artifact
# MKC-19. ★属性値内の生 '>' 密輸。 ★閉じ側だけ コメント vector を使うのは、 属性値内の生 `<` が make_body で
#   ★既に fail-closed される (raw-lt-in-tag) ため — 属性値 vector は ★開き側にしか存在しない (装わずに書く)。
cp "$HEALTHY" "$WORK/mkc19.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="forward-refs">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<p class="decoy" title="x><section>y"></p>\n</section>\n#; $n += s#</section>\n<section id="glossary-terms">#<!--</section>-->\n<section id="glossary-terms">#; END { exit($n==2?0:9) }' "$WORK/mkc19.html" || mkc_fired MKC-19
expect_fail "MKC-19 shape(属性値内の生 '>' 密輸による region over-slice) → containment が捕捉" "$WORK/mkc19.html" \
  "前方照会 chip の ★全数 が章 'forward-refs' の ref-grid 内" --artifact
# MKC-20. ★bogus comment (`<! … >`) 密輸 — 実 parser は `<!--` でない markup declaration も comment として `>` まで
#   捨てるが、 素朴実装は 1 文字進めるだけなので中の `<section>` が ★実タグとして深さに乗る。
cp "$HEALTHY" "$WORK/mkc20.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<! <section> >\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#<! </section> >\n</div>\n<footer#; END { exit($n==2?0:9) }' "$WORK/mkc20.html" || mkc_fired MKC-20
expect_fail "MKC-20 shape(bogus comment 密輸による region 付け替え) → containment が捕捉" "$WORK/mkc20.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-21. ★escapable RAWTEXT (textarea) 密輸 — script / style しか知らない実装では素通しになる。
cp "$HEALTHY" "$WORK/mkc21.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea><section></textarea>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#<textarea></section></textarea>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$WORK/mkc21.html" || mkc_fired MKC-21
expect_fail "MKC-21 shape(escapable RAWTEXT (textarea) 密輸) → containment が捕捉" "$WORK/mkc21.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-22. ★ハイフン入り要素名 (`<section-x>`) — 実 DOM では section と ★別要素。 要素名を `[a-zA-Z0-9]*` で切ると
#   "section" と誤認して章の深さに数える。
cp "$HEALTHY" "$WORK/mkc22.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<section-x>\n</section>\n<div class="chapbody">#; $n += s#</section>\n</div>\n<footer#</section-x>\n</div>\n<footer#; END { exit($n==2?0:9) }' "$WORK/mkc22.html" || mkc_fired MKC-22
expect_fail "MKC-22 shape(ハイフン入り要素名 <section-x> 密輸) → containment が捕捉" "$WORK/mkc22.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-22b. ★ハイフン ★以外 の名前文字 (`_`) による幽霊タグ (folio-3zr4.3 self-review・実弾 verified)。
#   ★MKC-22 との違い: MKC-22 は ★char class 列挙 (`[a-zA-Z0-9-]*`) に ★含まれる 文字 = 旧実装でも 1 語として
#   取れていた vector。 HTML5 の ★tag name state が名前を終端するのは tab/LF/FF/CR/space / `/` / `>` ★だけ で
#   `_` は ★名前文字 ゆえ、 列挙形の char class は `<div_x>` を prefix "div" と誤認する = ★同一 defect family の
#   ★取りこぼし側。 ★shape: (a) s4 の章要旨 callout の ★内側 (深さ 2) に 閉じない `<div_x>` を 1 個 置き
#   (b) 機械層 fold (details) を chapbody の ★外 (chapbody の sibling) へ移送し (c) その直後に `</div_x>` を置く。
#   実 DOM では `</div>` が div_x ごと callout を閉じ 次の `</div>` が chapbody を閉じる = ★fold が chapbody の外
#   (arm 2C が「封鎖した」と宣言する人間層 block 粒度 relocation そのもの) だが、 prefix 誤認する旧実装では
#   幽霊 div の深さで details が chapbody 内へ吸収され ★rc=0 / OK 129 / FAIL 0 (clean と完全一致) だった。
#   ★深さ 2 に置く のが要点 — 深さ 1 に置くと kids/bkids の子数が動いて別 arm が先に落ちる (この shape は
#   ★どの子数も動かさない)。
cp "$HEALTHY" "$WORK/mkc22b.html"
perl -0777 -i -pe 'our $n;
$n += s#(<section id="s4-references">\n<section data-component="chapter-deck-band"[^\n]*\n<div class="chapbody">\n<div data-component="section-essence-callout">[^\n]*?)</div>\n(<details data-component="spec-machine-fold".*?</details>\n)</div>\n</section>#${1}<div_x></div>\n</div>\n${2}</div_x>\n</section>#s;
END { exit($n==1?0:9) }' "$WORK/mkc22b.html" || mkc_fired MKC-22b
expect_fail "MKC-22b shape(アンダースコア入り要素名 <div_x> の幽霊タグで機械層 fold を chapbody の外へ移送) → tag name state 同型化した要素名走査が捕捉" "$WORK/mkc22b.html" \
  "章 's4-references' の chapbody 直下は 契約由来の完全子列" --artifact
# --- comment 終端の HTML5 非同型 3 分岐 (終端規則が別分岐ゆえ 1 本では他 2 分岐の弱化が silent になる) ---
# MKC-23. ★comment end bang (`--!>`)。
cp "$HEALTHY" "$WORK/mkc23.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--x--!></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$WORK/mkc23.html" || mkc_fired MKC-23
expect_fail "MKC-23 shape(comment end bang (--!>) 密輸による閉じタグ隠蔽) → containment が捕捉" "$WORK/mkc23.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-24. ★abrupt-closing comment (`<!-->`)。
cp "$HEALTHY" "$WORK/mkc24.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!--></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$WORK/mkc24.html" || mkc_fired MKC-24
expect_fail "MKC-24 shape(abrupt-closing comment (<!-->) 密輸)  → containment が捕捉" "$WORK/mkc24.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-25. ★`<!--->` (comment 終端分岐 2 の単独 teeth)。
cp "$HEALTHY" "$WORK/mkc25.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<!---></section><!--y-->\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$WORK/mkc25.html" || mkc_fired MKC-25
expect_fail "MKC-25 shape(<!---> 密輸 = comment 終端分岐 2) → containment が捕捉" "$WORK/mkc25.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-26. ★RAWTEXT 終了タグの ★要素名境界 — `</name[^>]*>` は `</textareax>` にも一致して早期終了し、 以降の
#   擬似タグを実タグとして数える。 ★region を ★伸ばす 向き (開きタグ密輸) で撃つ = over-slice の実害形。
cp "$HEALTHY" "$WORK/mkc26.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<textarea></textareax><section><textarea></textarea>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$WORK/mkc26.html" || mkc_fired MKC-26
expect_fail "MKC-26 shape(RAWTEXT 終了タグの要素名境界 </textareax> を突く region 伸長) → containment が捕捉" "$WORK/mkc26.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# MKC-27. ★foreign content (svg subtree) 内の擬似タグによる region 伸長 — genuine 生成物に svg アイコンが
#   多数実在する ため「現れないから拒否」では閉じられず subtree 追跡が要る。
cp "$HEALTHY" "$WORK/mkc27.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="glossary-terms">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)<div class="chapbody">#${1}<svg><section></svg>\n</section>\n<div class="chapbody">#; END { exit($n==1?0:9) }' "$WORK/mkc27.html" || mkc_fired MKC-27
expect_fail "MKC-27 shape(foreign content (svg subtree) 内の擬似タグ) → containment が捕捉" "$WORK/mkc27.html" \
  "glossary-term-table が章 'glossary-terms' の chapbody 内に 1 個" --artifact
# --- tokenizer の fail-closed 診断 arm を撃つ vector 群 (★同じ err arm の ★別 vector ゆえ per-shape で撃つ) ---
# MKC-28. ★div の自己閉じ構文 — HTML の非 foreign content では `/>` は無視される (= 開きタグ) が、 foreign 内では
#   自己閉じが効くため 深さ計数と実 DOM の差を作る入口になる。 genuine assembler は emit しない shape。
cp "$HEALTHY" "$WORK/mkc28.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">\n#<div class="ref-grid"/>\n#; END { exit($n==1?0:9) }' "$WORK/mkc28.html" || mkc_fired MKC-28
expect_fail "MKC-28 shape(div の自己閉じ構文) → tokenizer 構造診断が fail-closed" "$WORK/mkc28.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-29. ★void 要素による ★深さ 1 計数の打ち切り — 「章本文 block を 1 個 chapbody の外へ出し、 抜けた分の位置に
#   void を 1 個挿す」だけで 3 レベルの完全子数束縛が ★期待値ちょうどに保たれる。 ★MKC-28 と別 shape:
#   MKC-28 は自己閉じ構文の ★拒否、 本 shape は ★正当な HTML (void 要素) を使った ★計数の打ち切り。
cp "$HEALTHY" "$WORK/mkc29.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div class="tbl-wrap"><table data-component="spec-table">.*?</table></div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s4-references">)#${1} . "<br>\n</div>\n" . $mv . ${2}#e;
$n += s#(<section id="s3-coverage-rtm">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<br>\n#;
END { exit($n==3?0:9) }' "$WORK/mkc29.html" || mkc_fired MKC-29
expect_fail "MKC-29 shape(void 要素 2 個による深さ 1 計数の打ち切り = relocation のマスク) → tokenizer が fail-closed" "$WORK/mkc29.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-30. ★foreign root (svg) を depth-1 の filler にする ★計数マスク — 章本文 block を 1 個 machine-fold へ
#   退避させ、 抜けた位置へ `<svg><path/></svg>` (genuine と同形・breakout タグを含まない) を挿す。
#   root を ★1 子として計上 すると cbkids は期待値ちょうどに戻る ため完全子数束縛では原理的に見分けられない。
cp "$HEALTHY" "$WORK/mkc30.html"
perl -0777 -i -pe 'our $n; our $blk;
if (s#<div class="tbl-wrap"><table data-component="spec-table">(.*?)</table></div>\n#<svg viewBox="0 0 24 24"><path d="M4 4h16"/></svg>\n#s) { $blk = "<div class=\"tbl-wrap\"><table data-component=\"spec-table\">$1</table></div>\n"; $n++ }
$n++ if defined $blk && s#(<section id="s3-coverage-rtm">.*?<div class="machine-body">\n)#${1}$blk#s;
END { exit($n==2?0:9) }' "$WORK/mkc30.html" || mkc_fired MKC-30
expect_fail "MKC-30 shape(foreign root (svg) を depth-1 filler にした完全子数マスク) → tokenizer が fail-closed" "$WORK/mkc30.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-31. ★any other end tag による foreign からの breakout — `<svg></section></svg>` は 実 parser では stack を
#   遡って ★外側の HTML section を閉じる (章本文が丸ごと章の外へ出る)。 subtree を丸ごと読み飛ばす実装では ★不可視。
cp "$HEALTHY" "$WORK/mkc31.html"
perl -0777 -i -pe 'our $n; $n += s#(<section id="s2-done-condition-req">\n<section data-component="chapter-deck-band"[^\n]*</section>\n)#${1}<svg></section></svg>\n#; END { exit($n==1?0:9) }' "$WORK/mkc31.html" || mkc_fired MKC-31
expect_fail "MKC-31 shape(foreign 内の any-other-end-tag による外側 section 閉鎖) → tokenizer が fail-closed" "$WORK/mkc31.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-32. ★breakout 開始タグ — `<svg><div class="ref-grid"></div></svg>` の div は 実 DOM では foreign を抜けて
#   ★HTML 名前空間の実要素 になる (器が 2 個 = MKC-14 が消したはずの ★逃げ場 の再出現)。
cp "$HEALTHY" "$WORK/mkc32.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<svg><div class="ref-grid"></div></svg>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc32.html" || mkc_fired MKC-32
expect_fail "MKC-32 shape(foreign 内の breakout 開始タグによる器の重複) → tokenizer が fail-closed" "$WORK/mkc32.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-33. ★svg 包みによる人間層 block の ★章外 relocation — block を chapbody の外 (章直下) へ出して `<svg>…</svg>`
#   で包み、 抜けた分の位置へ空 div を filler として挿す。 foreign root を depth-1 の子として ★計上しない 実装では
#   kids / cbkids が一切動かない。 ★MKC-32 と別 shape (あちらは「器を増やす」向き・本 shape は「本文を外へ出す」向き)。
cp "$HEALTHY" "$WORK/mkc33.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#<div class="tbl-wrap"><table data-component="spec-table">.*?</table></div>\n##s) { $mv = $&; $n++ }
$n++ if defined $mv && s#(</details>\n)</div>\n(</section>\n<section id="s4-references">)#${1} . "<div></div>\n</div>\n<svg>" . $mv . "</svg>\n" . ${2}#e;
END { exit($n==2?0:9) }' "$WORK/mkc33.html" || mkc_fired MKC-33
expect_fail "MKC-33 shape(svg 包みによる人間層 block の章外 relocation・filler で子数を保つ形) → tokenizer が fail-closed" "$WORK/mkc33.html" \
  "containment tokenizer の構造診断" --artifact
# --- 属性 tokenize の parser-differential (★幽霊 marker クラス = 実 DOM に無い marker を probe が数える形) ---
# MKC-34. ★unquoted 属性値の char class 差 (値 state) — `<div foo=bar"z"class="ref-grid">` の実 parser では
#   `"` は ★値に取り込まれ class 属性は ★存在しない のに、 `"` で値を切る実装は 実在しない marker を数える。
cp "$HEALTHY" "$WORK/mkc34.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div foo=bar"z"class="ref-grid">#; END { exit($n==1?0:9) }' "$WORK/mkc34.html" || mkc_fired MKC-34
expect_fail "MKC-34 shape(unquoted 属性値への quote 混入 = 幽霊 marker 値 state) → 属性 tokenize の同型化が捕捉" "$WORK/mkc34.html" \
  "ref-grid が章 'forward-refs' の chapbody 内に 1 個" --artifact
# MKC-35. ★attribute-name state への quote 混入 (幽霊 marker の ★第 2 vector・MKC-34 は値 state のみ塞ぐ) —
#   `<div a""class="ref-grid">` の実 DOM 属性は `a""class="ref-grid"` の ★1 本だけ (name state は `"` を名前文字に
#   取り込む) ゆえ class 属性は存在しない。
cp "$HEALTHY" "$WORK/mkc35.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div a""class="ref-grid">#; END { exit($n==1?0:9) }' "$WORK/mkc35.html" || mkc_fired MKC-35
expect_fail "MKC-35 shape(attribute-name state への quote 混入 = 幽霊 marker 第 2 vector) → 逐次属性 parser が捕捉" "$WORK/mkc35.html" \
  "ref-grid が章 'forward-refs' の chapbody 内に 1 個" --artifact
# MKC-36. ★タグ境界の quote 走査 — MKC-34 / MKC-35 が塞ぐのは ★属性値の読み取り側 であって ★タグ終端位置を決める
#   走査は別コード。 genuine タグへ ` x=1 "></section>"` を 1 個足すだけで 実 DOM ではそこで章が閉じるのに、
#   state 無し走査は `</section>` を ★quote の中 と見なして region を伸ばし ★containment を 1 行で全 bypass する。
cp "$HEALTHY" "$WORK/mkc36.html"
perl -0777 -i -pe 'our $n; $n += s#<div class="ref-grid">#<div class="ref-grid" x=1 "></section>">#; END { exit($n==1?0:9) }' "$WORK/mkc36.html" || mkc_fired MKC-36
expect_fail "MKC-36 shape(タグ境界 quote 走査の state 非同型による閉じタグ隠蔽 = 1 行 bypass) → tokenizer が捕捉" "$WORK/mkc36.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-37. ★属性値の文字参照 — `class="ref&#45;grid"` は 実 DOM (convert_charrefs) では `.ref-grid` ゆえ器が ★2 個 に
#   なるが、 文字参照を解決しない probe は数え落とす。 期待値が「== 1」の ★上限型 arm では 数え落とし =
#   ★silent PASS へ倒れる (「undercount は常に fail-closed」は ★誤り)。 ★MKC-14 と別 shape (marker を参照で綴って隠す形)。
cp "$HEALTHY" "$WORK/mkc37.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref&\#45;grid"></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc37.html" || mkc_fired MKC-37
expect_fail "MKC-37 shape(文字参照で綴った marker による器の重複) → 属性値 charref 解決が捕捉" "$WORK/mkc37.html" \
  "ref-grid が ★文書全体で 1 個" --artifact
# --- ★block wrapper の中身 の帰属 (器だけ残して中身を逃がすクラス) ---
#   ★根本原因: chapbody 直下の marker 列 (cbkids) は「器がそこに在る」までしか言わず ★器の中身 を束縛しない。
#   かつ [table]=div.tbl-wrap / [requirements]=div.rq-list は ★wrapper class 自身の 文書 census を持たない
#   ため、 ★空の器を filler に残して 中身を別所へ移す形が ★全 arm 素通り する。
#   ★4 shape を別実弾で撃つ: 器の class (rq-list / tbl-wrap) × 逃がし方 (器ごと / 中身だけ) の ★2×2。
# MKC-38. (A) ★rq-list ごと 退避 + 空 rq-list filler — EARS 規範要件が正規位置から消える形。 ★srs-verification の
#   s2-done-condition-req は machine_blocks が 0 本 (fold が無い) ため、 退避先は ★同章 chapbody 内の
#   章要旨 callout subtree に取る (「既定折り畳みへ」ではなく「器の中へ」= 同じ ★器ごと退避 クラス)。
cp "$HEALTHY" "$WORK/mkc38.html"
perl -0777 -i -pe 'our $n; our $blk;
if (s#<div class="rq-list">\n(.*?)\n</div>\n(</div>\n</section>\n<section id="s3-coverage-rtm">)#<div class="rq-list"></div>\n${2}#s) { $blk = "<div class=\"rq-list\">\n$1\n</div>\n"; $n++ }
$n++ if defined $blk && s#(<div data-component="section-essence-callout"><p class="sec-se">生成 SRS の done-condition.*?</p>)(</div>\n)#${1}$blk${2}#s;
END { exit($n==2?0:9) }' "$WORK/mkc38.html" || mkc_fired MKC-38
expect_fail "MKC-38 shape(rq-list ごと退避 + 空 filler) → 器自身の文書 census が捕捉" "$WORK/mkc38.html" \
  "要件リストの器 (div.rq-list) が ★文書全体で 1 個" --artifact
# MKC-39. (B) ★tbl-wrap ごと machine-fold へ + 空 tbl-wrap filler — 表が ★既定折り畳みへ silent 退避 する形。
#   reason anchor は ★器自身の文書 census 側 に取り、 器の census 欠落こそが root cause であることを pin する。
cp "$HEALTHY" "$WORK/mkc39.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s3-coverage-rtm">.*?)(<div class="tbl-wrap">.*?</table></div>\n)#${1}<div class="tbl-wrap"></div>\n#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s3-coverage-rtm">.*?<div class="machine-body">\n)#${1}$mv#s;
END { exit($n==2?0:9) }' "$WORK/mkc39.html" || mkc_fired MKC-39
expect_fail "MKC-39 shape(tbl-wrap ごと machine-fold へ退避 + 空 filler) → 器自身の文書 census が捕捉" "$WORK/mkc39.html" \
  "表の器 (div.tbl-wrap) が ★文書全体で 1 個" --artifact
# MKC-40. (C) ★器は据置で 中身の table だけ machine-fold へ (hollow wrapper 残置) — 器の個数も文書総数も
#   ★一切動かない ので ★器中身の占有 pin ★単独 が唯一の FAIL 源。
cp "$HEALTHY" "$WORK/mkc40.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<section id="s3-coverage-rtm">.*?<div class="tbl-wrap">)(<table data-component="spec-table">.*?</table>)(</div>\n)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<section id="s3-coverage-rtm">.*?<div class="machine-body">\n)#${1}$mv\n#s;
END { exit($n==2?0:9) }' "$WORK/mkc40.html" || mkc_fired MKC-40
expect_fail "MKC-40 shape(hollow block wrapper・tbl-wrap 据置で中の table だけ fold へ) → 器中身の占有 pin が単独で捕捉" "$WORK/mkc40.html" \
  "表 (spec-table) の ★器ごとの個数列 が章 's3-coverage-rtm' の 表の器 (div.tbl-wrap) 群" --artifact
# MKC-41. (D) ★器は据置で 中身の要件 row だけ 章要旨 callout subtree へ (hollow rq-list 残置) — MKC-40 と
#   ★別 instance (器 class / payload の構造クラスが別)。 捕捉は要件側の ★器ごとの個数列 ★単独。
cp "$HEALTHY" "$WORK/mkc41.html"
perl -0777 -i -pe 'our $n; our $mv;
if (s#(<div class="rq-list">)\n(.*?)\n(</div>\n</div>\n</section>\n<section id="s3-coverage-rtm">)#${1}${3}#s) { $mv = $2; $n++ }
$n++ if defined $mv && s#(<div data-component="section-essence-callout"><p class="sec-se">生成 SRS の done-condition.*?</p>)(</div>\n)#${1}$mv${2}#s;
END { exit($n==2?0:9) }' "$WORK/mkc41.html" || mkc_fired MKC-41
expect_fail "MKC-41 shape(hollow rq-list・中の要件 row だけ callout subtree へ) → 器中身の占有 pin が単独で捕捉" "$WORK/mkc41.html" \
  "EARS 要件 row の ★器ごとの個数列 が章 's2-done-condition-req' の 要件リストの器 (div.rq-list) 群" --artifact
# --- ★class 属性の照合粒度 (逐値一致 vs CSS の token 意味) の parser-differential ---
#   ★根本原因 (folio-3zr4.3 self-review・実弾 verified): probe は class を ★値の逐値一致 で照合していたが、
#   consumer 述語 (CSS `.ref-grid` / `.grow` / `.tbl-wrap`) は class を ★空白区切り token 集合 として解釈する。
#   ゆえ `class="ref-grid decoy"` は ★実 DOM では器そのもの (CSS 適用・人間に描画される) なのに probe から
#   ★不可視 になり、 期待値が ★上限型 == の arm (docct / pay / xdoc) が ★undercount で silent PASS した
#   (MKC-37 = 文字参照で綴った marker と ★同一 defect family の ★別 vector = r8k / parser-differential クラス)。
#   ★per-shape で 3 本撃つ: 器 (docct・主 loop) / payload (pay・器 region 内) / 器の文書 census (xdoc・XSPEC loop)
#   — 消費経路が別ゆえ 1 本の実弾は他 2 本の穴を証明しない。
# MKC-42. ★器側 (docct) — 文書末尾へ `class="ref-grid decoy"` の 2 個目の器を置く。 ★MKC-14 (逐値 `class="ref-grid"`
#   の重複) と ★別 shape: MKC-14 は逐値一致でも落ちる形、 本 shape は ★1 トークン追加で MKC-14 の pin を bypass する形。
cp "$HEALTHY" "$WORK/mkc42.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="ref-grid decoy"></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc42.html" || mkc_fired MKC-42
expect_fail "MKC-42 shape(余剰 class トークン付き marker による器の重複 = class token 意味の非同型) → class の token 粒度照合が捕捉" "$WORK/mkc42.html" \
  "ref-grid が ★文書全体で 1 個" --artifact
# MKC-43. ★payload 側 (pay) — glossary-term-table の中へ `class="grow zz"` の捏造 1 行を足す。 実 DOM では
#   `.grow` が |glossary|+1 個で CSS も適用され ★人間に描画される 捏造行だが、 逐値一致の probe は数え落とす。
cp "$HEALTHY" "$WORK/mkc43.html"
perl -0777 -i -pe 'our $n;
$n += s#(<div data-component="glossary-term-table">\n)#${1}<div class="grow zz"><div class="gword">FAKE</div><div class="gdef">捏造行</div></div>\n#;
END { exit($n==1?0:9) }' "$WORK/mkc43.html" || mkc_fired MKC-43
expect_fail "MKC-43 shape(余剰 class トークン付き payload 行の捏造挿入) → payload 全数 pin が token 粒度で捕捉" "$WORK/mkc43.html" \
  "用語集 行 (.grow) の ★全数 が章 'glossary-terms' の glossary-term-table 内" --artifact
# MKC-44. ★器の文書 census 側 (xdoc・XSPEC loop = 主 loop と ★別の消費経路) — `class="tbl-wrap dup"` の 2 個目の
#   器を文書末尾へ。 MKC-39 (逐値 `class="tbl-wrap"` の器ごと退避 + 空 filler) が担保しているはずの xdoc を bypass する形。
cp "$HEALTHY" "$WORK/mkc44.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div class="tbl-wrap dup"></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc44.html" || mkc_fired MKC-44
expect_fail "MKC-44 shape(余剰 class トークン付き block wrapper の重複 = XSPEC 経路の同型欠陥) → 器自身の文書 census が token 粒度で捕捉" "$WORK/mkc44.html" \
  "表の器 (div.tbl-wrap) が ★文書全体で 1 個" --artifact
# --- ★docct (器の重複 = 逃げ場) の ★未着弾 shape への実弾 (folio-3zr4.3 self-review・per-instance 未着弾の解消) ---
#   ★動機: docct を撃つ実弾は ★MKC-14 の 1 本だけ で、 期待値が ★literal 1 の instance しか撃っていなかった。
#   docct には ★期待値が contract 由来で N>1 になる分岐 (章要旨 callout == NSEC) と ★別 marker 軸 (data-component
#   で識別する器) があり、 どちらも「器の重複」という ★同じ攻撃 shape が per-instance 未着弾のまま残っていた。
#   ★2 本とも ★class ではなく data-component で識別する器 ゆえ MKC-42/44 (class token 軸) とも別 vector。
# MKC-45. ★N>1 側の分岐 — 章要旨 callout の 2 個目を文書末尾へ置く (期待値は contract の章数から導出される)。
#   ★substring に章数の逐値を焼かない (契約由来の値を suite 側 literal へ流用しない = 導出規律)。
cp "$HEALTHY" "$WORK/mkc45.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div data-component="section-essence-callout"><p class="sec-se">捏造</p></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc45.html" || mkc_fired MKC-45
expect_fail "MKC-45 shape(章要旨 callout の器の重複 = docct の N>1 分岐・期待値が contract 章数由来) → 器の文書総数 pin が捕捉" "$WORK/mkc45.html" \
  "章要旨 callout が ★文書全体で" --artifact
# MKC-46. ★別 marker 軸の instance — glossary-term-table の 2 個目を文書末尾へ (data-component で識別する器の重複)。
cp "$HEALTHY" "$WORK/mkc46.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<div data-component="glossary-term-table"></div>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc46.html" || mkc_fired MKC-46
expect_fail "MKC-46 shape(glossary-term-table の器の重複 = docct の data-component 軸 instance) → 器の文書総数 pin が捕捉" "$WORK/mkc46.html" \
  "glossary-term-table が ★文書全体で 1 個" --artifact
# --- ★marker の ★担体要素名 の非同型 (folio-3zr4.3 self-review・parser-differential の ★第 4 vector) ---
#   ★動機: 器 / payload の照合は ★要素名 (literal "div" / BLOCK_WRAPPER_SPEC の要素名) を必須にしていたが、
#   consumer 述語 は ★要素非依存 である (srs.css の `.grow` / `.tbl-wrap`・assembler の `.ref-grid` は
#   いずれも要素修飾の無い class selector・実測)。 ゆえ marker を ★div 以外の要素 に載せると 実 DOM では
#   CSS が適用され ★人間に描画される のに probe から不可視になり、 期待値が ★上限型 == の arm が
#   ★undercount で silent PASS した (是正前の実測: 下記 3 shape とも rc=0 / OK 129 / FAIL 0 = clean と 1 arm も
#   違わない)。 MKC-37 (文字参照) / MKC-42-44 (class token 粒度) と ★同一 defect family の ★別 vector。
#   ★per-shape で 3 本撃つ — 消費経路が pay (主 loop 器内) / docct (主 loop 文書総数) / xdoc (XSPEC loop) と
#   ★別々 ゆえ 1 本の実弾は他 2 本の穴を証明しない。 kill anchor は ★tokenizer 構造診断 arm (fail-closed 診断)。
# MKC-47. ★payload 側 (pay) — glossary-term-table の中へ `<span class="grow">` の捏造 1 行を足す。
cp "$HEALTHY" "$WORK/mkc47.html"
perl -0777 -i -pe 'our $n;
$n += s#(<div data-component="glossary-term-table">\n)#${1}<span class="grow"><div class="gword">FAKE</div><div class="gdef">捏造行</div></span>\n#;
END { exit($n==1?0:9) }' "$WORK/mkc47.html" || mkc_fired MKC-47
expect_fail "MKC-47 shape(span 担体の捏造 payload 行 = marker 担体要素名の非同型・pay 経路) → 担体要素名の fail-closed 固定が捕捉" "$WORK/mkc47.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-48. ★器側 (docct・主 loop) — `<span class="ref-grid">` の 2 個目の器を文書末尾へ。
cp "$HEALTHY" "$WORK/mkc48.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<span class="ref-grid"></span>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc48.html" || mkc_fired MKC-48
expect_fail "MKC-48 shape(span 担体の器重複 = marker 担体要素名の非同型・docct 経路) → 担体要素名の fail-closed 固定が捕捉" "$WORK/mkc48.html" \
  "containment tokenizer の構造診断" --artifact
# MKC-49. ★器の文書 census 側 (xdoc・XSPEC loop) — `<span class="tbl-wrap">` の 2 個目の器を文書末尾へ。
cp "$HEALTHY" "$WORK/mkc49.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<span class="tbl-wrap"></span>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc49.html" || mkc_fired MKC-49
expect_fail "MKC-49 shape(span 担体の block wrapper 重複 = marker 担体要素名の非同型・xdoc 経路) → 担体要素名の fail-closed 固定が捕捉" "$WORK/mkc49.html" \
  "containment tokenizer の構造診断" --artifact
# --- ★契約章の ★章要旨 callout の 器中身 (payload) 占有 (folio-3zr4.3 self-review・Leg B errata-1 と同一クラス) ---
#   ★動機: 契約章 5 本は器 (section-essence-callout) だけを登録し payload 側が空だったため、 ★器を空の filler として
#   正規位置に残し 中身だけ逃がす 形が 5/7 章で開いていた (是正前の実測: 下記 2 形とも rc=0 / OK 129 / FAIL 0)。
#   ★2 本とも ★同じ arm (xpayseq) を撃つが ★別 shape である: (a) は ★同章内で 器の外 (fold の中) へ落とす形で
#   1 章だけが割れ、 (b) は ★別章の器へ移す形で ★donor / acceptor の 2 章が割れる (合計不変の再配分に対する
#   帰属束縛が効いていることの isolate)。
# MKC-50. ★hollow callout — s0 の章要旨 (p.sec-se) を ★同章 machine-fold の machine-body へ移す
#   (人間可視の章要旨が ★既定折り畳みの中 へ消える形)。
cp "$HEALTHY" "$WORK/mkc50.html"
perl -0777 -i -pe 'our $n; our $p;
if (s#(<section id="s0-reader-guide">.*?<div data-component="section-essence-callout">)(<p class="sec-se">.*?</p>)(</div>)#${1}${3}#s) { $p = $2; $n++ }
$n++ if defined $p && s#(<section id="s0-reader-guide">.*?<div class="machine-body">\n)#${1}$p\n#s;
END { exit($n==2?0:9) }' "$WORK/mkc50.html" || mkc_fired MKC-50
expect_fail "MKC-50 shape(hollow 章要旨 callout = 器据置で中身だけ同章 fold へ) → 器中身の占有 pin が捕捉" "$WORK/mkc50.html" \
  "章要旨の本文 (p.sec-se) の ★器ごとの個数列 が章 's0-reader-guide'" --artifact
# MKC-51. ★別章 graft — s0 の章要旨を s1 の callout へ移す (器はどちらも正規位置のまま・文書総数も不変)。
cp "$HEALTHY" "$WORK/mkc51.html"
perl -0777 -i -pe 'our $n; our $p;
if (s#(<section id="s0-reader-guide">.*?<div data-component="section-essence-callout">)(<p class="sec-se">.*?</p>)(</div>)#${1}${3}#s) { $p = $2; $n++ }
$n++ if defined $p && s#(<section id="s1-boundary-model">.*?<div data-component="section-essence-callout">)#${1}$p#s;
END { exit($n==2?0:9) }' "$WORK/mkc51.html" || mkc_fired MKC-51
expect_fail "MKC-51 shape(章要旨の別章 graft = 器中身の帰属替え) → 器中身の占有 pin が donor 側で捕捉" "$WORK/mkc51.html" \
  "章要旨の本文 (p.sec-se) の ★器ごとの個数列 が章 's0-reader-guide'" --artifact

# --- ★章間 同型 swap (admin gate errata-1 MUST-1・cell-gate false-green-hunt が実弾 2 本で立証した fail-open) ---
# ★shape の要点: srs-verification contract の s0 / s1 / s4 は blocks:[] + machine_blocks 1 本で ★cbkids 期待列が
#   完全同一 ゆえ、 ★章をまたいで 同型の部品を交換すると 3 レベル完全子数束縛 (kids / bkids / cbkids) も
#   器中身 pin (cont / docct / xpayseq) も ★1 つも動かない — 是正前は rc=0 / 134 OK / 0 FAIL で ★clean と無差別 だった。
#   ★drift gate でも代替できない: assembler の off-by-one で fold / 章要旨が隣章に付くクラスは canonical と
#   fresh 再生成が ★同じ間違いを共有する ため常に PASS する (本 gate が冒頭で自らの存在理由に挙げたクラス)。
#   ★是正は ★章帰属の逐値束縛 (p.sec-se ↔ contract essence / span.mf-label ↔ contract heading 由来) で、
#   ★2 shape を別実弾で撃つ (交換する部品の DOM 構造クラスが details と div で別・担体も別 arm)。
echo "  -- arm 2C 追補 (章間 同型 swap = errata-1 MUST-1) --"
# MKC-52. ★s0⇄s1 の 機械層 fold (details) を丸ごと交換 — 構造は完全保存・fold ラベルの章帰属だけが壊れる。
cp "$HEALTHY" "$WORK/mkc52.html"
perl -0777 -i -pe 'our $n; $n += s{(<section id="s0-reader-guide">.*?)(<details data-component="spec-machine-fold".*?</details>\n)(.*?<section id="s1-boundary-model">.*?)(<details data-component="spec-machine-fold".*?</details>\n)}{${1}${4}${3}${2}}s; END { exit($n==1?0:9) }' "$WORK/mkc52.html" || mkc_fired MKC-52
expect_fail "MKC-52 shape(s0⇄s1 の機械層 fold を章間で交換・構造完全保存) → 章帰属の逐値束縛 (mf-label) が捕捉" "$WORK/mkc52.html" \
  "章 's0-reader-guide' の 機械層 fold ラベル (span.mf-label)" --artifact
# MKC-53. ★s0⇄s1 の 章要旨 callout (div) を丸ごと交換 — MKC-52 と ★別構造クラス (details でなく div・担体も別 arm)。
cp "$HEALTHY" "$WORK/mkc53.html"
perl -0777 -i -pe 'our $n; $n += s{(<section id="s0-reader-guide">.*?)(<div data-component="section-essence-callout">.*?</div>\n)(.*?<section id="s1-boundary-model">.*?)(<div data-component="section-essence-callout">.*?</div>\n)}{${1}${4}${3}${2}}s; END { exit($n==1?0:9) }' "$WORK/mkc53.html" || mkc_fired MKC-53
expect_fail "MKC-53 shape(s0⇄s1 の章要旨 callout を章間で交換・構造完全保存) → 章帰属の逐値束縛 (p.sec-se) が捕捉" "$WORK/mkc53.html" \
  "章 's0-reader-guide' の 章要旨本文 (p.sec-se)" --artifact
# ★弁別 (集計規律 (1) の適用): 章間 swap は ★非描画容器を一切持ち込まない ので make_body_live の fail-closed を
#   ★経由しない = 上の 2 kill は巻き添えでなく genuine。 かつ ★構造 arm (cbkids / kids / cont / xpayseq) が
#   ★1 本も赤くならない ことも撃つ — 赤くなるなら「構造では見分けられない」という本 shape の前提自体が崩れており、
#   章帰属 pin の存在理由 (と上の実態開示) が false record になるため。
mkc52_ok=1
for _f in "$WORK/mkc52.html" "$WORK/mkc53.html"; do
  _o="$(run_gate "$_f" --artifact)"
  grep -qF 'make_body_live fail-closed' <<<"$_o" && mkc52_ok=0
  _sf="$(grep -E '^ *\[FAIL\]' <<<"$_o")"
  for _p in 'の chapbody 直下は 契約由来の完全子列' 'の直下は 章帯 + chapbody の 2 子だけ' 'の chapbody 内に 1 個' '★器ごとの個数列' '★文書全体で'; do
    grep -qF -- "$_p" <<<"$_sf" && mkc52_ok=0
  done
done
if [[ "$mkc52_ok" -eq 1 ]]; then
  ok "MKC-52/53 弁別: 章間 swap は fail-closed を経由せず ★構造 arm も 1 本も赤くならない (章帰属 pin ★単独 の genuine kill = 「構造では見分けられない」前提の実証)"
else bad "MKC-52/53 弁別: fail-closed 経由 or 構造 arm が赤い — 巻き添え kill か、本 shape の前提 (構造完全保存) が崩れている"; fi
# ★★err 系 MK の ★err token 実値 pin (admin gate errata-1 SHOULD L-4): 上の err 系 mutant は いずれも
#   「containment tokenizer の構造診断」という ★同一 arm を赤くするため、 arm ラベルだけの pin では
#   ★どの診断分岐を踏んだか を確かめていない (別分岐で赤くても PASS してしまう = 分岐ごとの teeth が未証明)。
#   ゆえ ★診断 token の逐値 を突合する。 ★1 本の chk に畳む のは、 分岐ごとに case を増やすと per-shape MK の
#   本数と二重計上になり arm 数 pin が読みにくくなるため (どれか 1 つでも外れたら赤くなるので teeth は落ちない)。
#   ★token 値は ★実測から取る (推測で書くと「期待どおり赤い」を装う false record になる)。
err_bad=""
while IFS='|' read -r _fx _tok; do
  [[ -n "$_fx" ]] || continue
  _o="$(run_gate "$WORK/$_fx.html" --artifact)"
  _got="$(grep -E '^ *\[FAIL\] *containment tokenizer の構造診断' <<<"$_o" | sed -E 's/.*, got //')"
  [[ "$_got" == "$_tok" ]] || err_bad="$err_bad $_fx(期待 $_tok/実測 ${_got:-なし})"
done <<'ERRMAP'
mkc22|unclosed-child-section-x
mkc27|foreign-at-depth1-svg
mkc28|self-closing-div
mkc29|unclosed-child-br
mkc30|foreign-at-depth1-svg
mkc31|foreign-breakout-end-section
mkc32|foreign-breakout-div
mkc33|foreign-breakout-div
mkc36|unclosed-child-div
mkc47|marker-on-foreign-element-class-grow
mkc48|marker-on-foreign-element-class-ref-grid
mkc49|marker-on-foreign-element-class-tbl-wrap
ERRMAP
if [[ -z "${err_bad// /}" ]]; then
  ok "err token 実値 pin: err 系 12 mutant が ★それぞれ意図した診断分岐 (self-closing / unclosed-child / foreign-at-depth1 / foreign-breakout(-end) / marker-on-foreign-element) を踏む"
else bad "err token 実値 pin: 分岐がずれている →$err_bad (同一 arm の別分岐で赤くなっている = その分岐の teeth が未証明)"; fi
# --- ★弁別対照 (集計規律 (1) の適用・vacuous kill との切り分け) ---
# ★問題: 上の MKC 群のうち ★4 本 (MKC-20 bogus comment / MKC-21 textarea / MKC-26 </textareax> / MKC-29 void <br>)
#   は 副作用として ★make_body_live の fail-closed も踏む (allowlist 外タグ / bogus comment を含むため)。 本 suite の
#   ★集計規律 (1) は「fail-closed run の [FAIL] は kill に数えない」と定めているので、 これらの containment kill が
#   ★巻き添え なのか ★genuine なのか を ★機械で 切り分けないと「撃てていないのに撃てた」を作る。
# ★切り分けの原理: containment (arm 2C) の subject は ★$BODY であり make_body_live の fail-closed で ★空にならない。
#   ゆえ「live view だけを fail-closed させる ★純粋な 対照」を作り、 そこで containment arm が ★1 本も赤くならない
#   ことを撃てば、 上記 4 本の containment FAIL は ★live 側の巻き添えではない と isolate できる (陰性対照)。
# ★対照 mutant: allowlist 外タグ (<br>) を ★章の外 (</body> 直前) に 1 個置く。 live view は unknown-container:br で
#   空になり $BODY_LIVE 系 arm は総崩れするが、 ★章の内側の構造は 1 byte も動いていない。
cp "$HEALTHY" "$WORK/mkc-c1.html"
perl -0777 -i -pe 'our $n; $n += s#</body>#<br>\n</body>#; END { exit($n==1?0:9) }' "$WORK/mkc-c1.html" || mkc_fired MKC-C1
# ★★leak 集合は ★手書き literal 列挙にしない (partial-enumeration trap の封鎖・folio-3zr4.3 self-review 是正)。
#   ★初版は 8 個の substring を手書きしており、 containment の chk ラベル 15 クラスのうち ★4 クラス
#   (region 内の章帯 == 1 / chapbody 開口直後の器隣接 / 器が chapbody 内に 1 個 / payload 全数の器内帰属) が
#   ★列挙から漏れていた。 決定的だったのは ★名指し した MKC-20/21/26 の kill anchor が ★まさにその漏れた
#   cont arm だった こと — 「その arm が巻き添えで赤くなっていないこと」を対照が ★一度も検査していない =
#   名指し対象に対して ★構造的に vacuous な陰性対照だった (実測 leak は 0 だったので結論自体は正しかったが、
#   guard は「今たまたま正しい」だけで $BODY / $BODY_LIVE 境界がずれた将来に false record 側へ倒れる)。
# ★★構造的終端: leak 集合を ★verify script の containment 節 (arm 2C) の chk ラベルから ★機械導出する。
#   (a) `--- arm 2C: containment` 〜 `# arm 3.` の範囲を切り出し、 (b) 行継続を論理行へ連結してから chk 行を取り、
#   (c) ラベル中の ★変数展開部 (`$_s` / `${_CT_CLBL[$_k]}` …) を区切りに分割して ★最長の literal 断片 を
#   anchor にする。 ★containment arm を足すと anchor が ★自動で 対照へ入る (手書き追記の漏れが起きない)。
# ★★恒真化封鎖 (件数 assert を ★対 で置く・ehar クラスの存在 anchor): 抽出が腐れば anchor 0 本 → leak 0 →
#   ★恒真 PASS になる。 ゆえ (1) 導出 anchor 数 ★== containment chk 行数 (全 chk が anchor を産んだこと) と
#   (2) containment chk 行数 ★>= 15 (現行実測ちょうど・floor) を ★producer assert として対に置く。
#   ★floor にして逐値にしないのは、 arm 追加時に anchor が ★自動反映される のが本 fix の主眼であり、
#   逐値だと「正しく反映されたのに赤」になって導出形の意味を殺すため (arm 総数の lockstep は
#   EXPECTED_OK_ARTIFACT / HEADLINE_ARMS / MECH_CHK_MIN の逐値 pin 群が別途担う)。
C1_CONT_CHK_MIN=17
c1_chk="$(awk '/--- arm 2C: containment/{f=1} /^# arm 3\. /{f=0} f' "$GATE" \
  | awk '{ cur = $0; if (buf != "") cur = buf cur; if (cur ~ /\\$/) { sub(/\\$/, "", cur); buf = cur; next } buf = ""; print cur }' \
  | grep -E '^ *chk "')"
c1_nchk="$(printf '%s\n' "$c1_chk" | grep -c '^ *chk "')"
c1_anchors="$(printf '%s\n' "$c1_chk" | perl -CSD -ne '
  next unless /^\s*chk\s+"((?:[^"\\]|\\.)*)"/;
  my $lab = $1;
  my @frag = split /\$\{[^}]*\}|\$\(\([^)]*\)\)|\$[A-Za-z_][A-Za-z0-9_]*/, $lab;
  my $best = ""; for my $f (@frag) { $best = $f if length($f) > length($best) }
  $best =~ s/^\s+//; $best =~ s/\s+$//;
  print "$best\n" if length($best) >= 8;
')"
c1_nanchor="$(printf '%s\n' "$c1_anchors" | grep -c .)"
out="$(run_gate "$WORK/mkc-c1.html" --artifact)"; rc=$?
c1_fails="$(grep -E '^ *\[FAIL\]' <<<"$out")"
c1_leak=0
while IFS= read -r _p; do
  [[ -n "$_p" ]] || continue
  grep -qF -- "$_p" <<<"$c1_fails" && c1_leak=$((c1_leak+1))
done <<<"$c1_anchors"
if [[ "$c1_nchk" -ge "$C1_CONT_CHK_MIN" && "$c1_nanchor" -eq "$c1_nchk" ]]; then
  ok "MKC-C1 leak 集合の producer: containment chk $c1_nchk 行 (>= $C1_CONT_CHK_MIN) から anchor を $c1_nanchor 本 導出 (全 chk が anchor を産んだ = 列挙の恒真化封鎖)"
else bad "MKC-C1 leak 集合の producer: containment chk $c1_nchk 行 (>= $C1_CONT_CHK_MIN 期待) / 導出 anchor $c1_nanchor 本 (chk 行数と同数 期待) — 抽出が腐ると leak 判定が恒真 PASS になる"; fi
# ★★anchor rot の ★陽性対照 (負判定 = 「leak 0」だけにしない・u7y2 クラス): 件数が合っていても、 断片分割が
#   ★実出力に一度も現れない 文字列を産めば その arm の leak 判定は ★恒真 PASS になる (導出しただけで当たらない)。
#   ゆえ ★healthy run の実出力 に全 anchor が ★実際に一致する ことを撃つ — 一致しない anchor は「その arm を
#   検査しているつもりで何も見ていない」を意味するので赤くする。
c1_healthy_out="$(run_gate "$HEALTHY" --artifact)"
c1_rot=0
while IFS= read -r _p; do
  [[ -n "$_p" ]] || continue
  grep -qF -- "$_p" <<<"$c1_healthy_out" || c1_rot=$((c1_rot+1))
done <<<"$c1_anchors"
if [[ "$c1_rot" -eq 0 ]]; then
  ok "MKC-C1 leak anchor の陽性対照: 導出 $c1_nanchor 本 が ★全数 healthy run の実出力行に一致 (当たらない anchor = 恒真 PASS の穴が 0)"
else bad "MKC-C1 leak anchor の陽性対照: $c1_rot 本 が実出力に一致しない (anchor rot — その arm の leak 判定が恒真 PASS になっている)"; fi
if [[ "$rc" -ne 0 ]] && grep -qF 'make_body_live fail-closed: unknown-container:br' <<<"$out" && [[ "$c1_leak" -eq 0 ]]; then
  ok "MKC-C1 弁別対照: live view のみ fail-closed させても containment arm は ★1 本も赤くならない (導出 anchor $c1_nanchor 本 全数で照合・MKC-20/21/26/29 の containment kill は巻き添えでない = genuine)"
else bad "MKC-C1 弁別対照: rc=$rc / containment arm への漏れ $c1_leak 本 (0 期待・導出 anchor $c1_nanchor 本) — 巻き添え kill と genuine kill を切り分けられていない"; fi
# ---------------------------------------------------------------------------
# MECHPIN. ★containment 検査機構の健全性 arm の ★tracked 静的 pin
# ---------------------------------------------------------------------------
#   「駆動表が全章を覆う」「probe が全章分の実測を出力」の 2 arm は ★artifact をどう改竄しても落ちない
#   (script 改変でしか落ちない) ため、 敵対 suite の構造上 per-shape MK を持てない。 その担保を worker の
#   ★untracked な self-test に置くと land 後にリポへ ★残らない ので、 tracked な本 suite で
#   ★arm の実在 と ★期待値が導出形であること を静的に pin する。
#   ★恒真化封鎖: file 全体の grep (-ge 1 / -q) では、 将来 ★コメント等に同じ文字列が 1 つ増えるだけで
#   成立してしまう (arm 本体が消えても緑)。 ゆえに (a) ★chk 行だけを awk で scope 切り出し (b) ★label と
#   期待値の導出形を ★同一行 に要求 (c) ★==1 の逐値 の 3 点で締める。
#   ★chk は label と期待値が ★行継続 (`\`) で分かれることがあるため、 継続行を ★論理行へ連結してから 抽出する
#   (1 行 awk だと label 行しか取れず「同一行に導出形を要求」が構造的に成立しない = 恒偽になる)。
mech_chk="$(awk '{ cur = $0; if (buf != "") cur = buf cur; if (cur ~ /\\$/) { sub(/\\$/, "", cur); buf = cur; next } buf = ""; print cur }' "$GATE" | grep '^chk "')"
mech_cov="$(printf '%s\n' "$mech_chk" | grep -F 'containment 駆動表が全章を覆う' | grep -cF 'NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}')"
mech_prb="$(printf '%s\n' "$mech_chk" | grep -F 'containment probe が全章分の実測を出力' | grep -cE '\$\{#_CT_ID\[@\]\} \* [0-9]+ \+ \$\{#_XC_KEY\[@\]\} \* [0-9]+ \+ 1')"
if [[ "$mech_cov" -eq 1 ]]; then
  ok "MECHPIN ★駆動表 被覆 arm が chk 行に 1 本・期待値は contract 由来の導出形 (literal 直書きでない)"
else
  bad "MECHPIN ★駆動表 被覆 arm が chk 行で導出形として 1 本存在しない (実測 $mech_cov 期待 1 — arm 消失 / literal 直書きへの退行 / 複製)"
fi
if [[ "$mech_prb" -eq 1 ]]; then
  ok "MECHPIN ★probe 出力行数 arm が chk 行に 1 本・期待値は章数からの導出形"
else
  bad "MECHPIN ★probe 出力行数 arm が chk 行で導出形として 1 本存在しない (実測 $mech_prb 期待 1)"
fi
# ★producer 存在 assert (負の主張だけにしない): 上の 2 arm は chk 行の集合から数えているので、 その集合が
#   ★空でない ことを別途固定する (awk の抽出パターンが腐れば両 arm とも 0 になり bad へ倒れるが、 抽出自体の
#   健全性を独立に見ておく)。
# ★★閾値は ★pack ごとに再導出する (Leg C 裁定 srs 条項 (3)・pack 間 literal 流用の禁止): 範型
#   test-adversarial-verification.sh の `-ge 50` は ★verification pack の chk 行 94 本 を前提にした literal で、
#   ★srs-verification の実測は 35 本 (本 commit で containment 分を足した後の値・移植前は 32 本) ゆえ
#   50 を写すと ★恒偽 = 常時 bad になる (silent PASS ではなく ★恒常 RED という別型の false record)。
# ★閾値を ★実測ちょうど (35) に置く理由: producer assert としての teeth を最大化するため。 これより緩い値に
#   すると「chk 行が 1 本消えても緑」= arm の silent 消失を検出できない (vacuous-green の主経路)。
#   ★arm を足したら本値も上げる (lockstep)。 ★worker self-test で「chk 行を 1 本消すと本 arm が bad になる」ことを
#   実弾で踏んでいる (untracked ゆえリポには残らない — その担保が ★この逐値 pin そのもの である)。
# ★★閾値の ★scope を明示する (SHOULD L-1): 本 producer が数えるのは ★行頭 (非インデント) の `chk "` 行 ★だけ で、
#   実測 ★35 本。 verify script の chk 行は ★全 58 本 あり、 差 23 本は ★for ループ / if の中にある ★インデント付き
#   chk (containment の per-章 arm 群など)。 ★数える対象を広げない のは、 この producer assert が守るのは
#   「awk の論理行連結 + 行頭 anchor 抽出が壊れていないか」であって arm 総数ではないから (arm 総数の lockstep は
#   EXPECTED_OK_ARTIFACT / HEADLINE_ARMS / MECH_ARM2C_OK が別途担う)。 単位を書かないと「35 本しか chk が無い」と
#   誤読され、 実 arm 数と食い違う ★3 度目の false record 源になる。
MECH_CHK_MIN=35
mech_n="$(printf '%s\n' "$mech_chk" | grep -c .)"
if [[ "$mech_n" -ge "$MECH_CHK_MIN" ]]; then ok "MECHPIN ★chk 行の抽出が健全 ($mech_n 行 >= $MECH_CHK_MIN・scope 切り出しの producer 存在 assert)"
else bad "MECHPIN ★chk 行の抽出が壊れている ($mech_n 行 < $MECH_CHK_MIN — awk パターンの腐り or arm の silent 消失で上の 2 arm が恒偽化する)"; fi
# ★★arm 2C の ★実 arm 数 の逐値 pin (folio-3zr4.3 self-review 是正・ヘッダ (a') の ★母数 が stale 化するのを封鎖)。
#   ★動機 (実際に踏んだ false record): ヘッダ (a') は「artifact 改竄で落ちうる containment arm ★N 本」を ★手書き
#   literal で書いており、 XSPEC 4 arm を足したときに追随せず ★当該 4 arm が (a')/(b) の ★どちらの分類にも入らない
#   未分類 のまま残った (trust anchor 完結性 sweep が閉じない = 次に arm を足す者が誤った母数を anchor にする)。
#   ★母数は ★arm 2C の OK 数 − 機構健全性 2 の ★導出形 で定義し、 その ★被除数 側 (arm 2C の OK 数) を本 arm が
#   逐値で固定する。 EXPECTED_OK_ARTIFACT (全 arm 総数) だけでは arm 2C ★内訳 の増減が見えない (他 arm と相殺しうる)。
#   ★arm を足したら ここと ヘッダ (a') の ★再測 を同一 commit で行う (数値 bump のみの追随は禁止・裁定 srs 条項 (2))。
MECH_ARM2C_OK=87
mech_arm2c="$(run_gate "$HEALTHY" --artifact | awk '/^--- arm 2C: containment/{f=1;next} /^--- arm 3/{f=0} f' | grep -cE '^ *\[OK\]')"
if [[ "$mech_arm2c" -eq "$MECH_ARM2C_OK" ]]; then
  ok "MECHPIN ★arm 2C の実 arm 数 == $MECH_ARM2C_OK (ヘッダ (a') の母数 = 本値 − 機構健全性 2 = $((MECH_ARM2C_OK - 2)) 本 の導出 anchor)"
else bad "MECHPIN ★arm 2C の実 arm 数が $mech_arm2c (期待 $MECH_ARM2C_OK) — ヘッダ (a') の母数が stale 化している (arm 追加時の再測が未履行 / arm の silent 消失)"; fi
# ★containment の ★駆動表被覆と ★器登録 の宣言集合が ★verify script に実在すること の静的 pin
#   (CHAPBODY_KID_MARK / BLOCK_WRAPPER_SPEC / PRESENTATION_WRAPPER_BAND_TINTS が消えると partial-enum guard が
#   丸ごと消えるが、 生成物は無改竄のままなので敵対 suite の MKC 群では ★捕まらない = MECHPIN の領分)。
# ★★sibling fork との ★非対称 (false record 封鎖): Leg A / Leg B の同 pin は ★CENSUS_BACKED_MARK を含む 4 本 を
#   数えるが、 ★verify-srs-verification.sh は文書 census 節を持たないため ★同宣言を置いていない (置くと
#   「免除機構が在る」と読ませる宣言 > 実能力の false record になる = verify 側 arm 2C に理由を逐語開示)。
#   ゆえ本 pack の期待は ★3 本 であり、 ★4 を写してはならない (pack 間 literal 流用の禁止)。
mech_decl=0
for _d in CHAPBODY_KID_MARK BLOCK_WRAPPER_SPEC PRESENTATION_WRAPPER_BAND_TINTS; do
  grep -qE "^(declare -A )?${_d}=\(" "$GATE" && mech_decl=$((mech_decl+1))
done
if [[ "$mech_decl" -eq 3 ]]; then ok "MECHPIN ★containment の宣言集合 3 本 (CHAPBODY_KID_MARK / BLOCK_WRAPPER_SPEC / PRESENTATION_WRAPPER_BAND_TINTS) が verify に実在"
else bad "MECHPIN ★containment の宣言集合が欠落 (実測 $mech_decl / 期待 3 — partial-enum guard の消失は MKC 群では捕まらない)"; fi
# ★CENSUS_BACKED_MARK を ★置いていない ことの negative pin (上の 3 本 assert と ★対): 将来 sibling から
#   ★惰性で 写し込まれると「免除機構が在る」という false record が復活し、 かつ本 pack には免除の根拠 (文書 census)
#   が無いまま partial-enum guard が ★緩む。 実在したら赤くする (置くなら census 節の新設ごと設計する話)。
if ! grep -qE '^(declare -A )?CENSUS_BACKED_MARK=\(' "$GATE"; then
  ok "MECHPIN ★CENSUS_BACKED_MARK が verify に不在 (免除機構を持たない = 全 block type が BLOCK_WRAPPER_SPEC 登録必須の強い側)"
else bad "MECHPIN ★CENSUS_BACKED_MARK が verify に混入 (本 pack には免除の根拠となる文書 census 節が無い = 宣言 > 実能力)"; fi
# ★★kill map (arm → MKC 番号) の ★実在と完全性 の静的 pin (folio-3zr4.3 self-review 是正・裁定 srs 条項 (2)
#   「追加 arm ごとに … kill map 再測とヘッダ注記更新」の ★機械化)。
#   ★動機 (実際に踏んだ false record): verify 側ヘッダの kill map は arm 追加のたび手で書き替える設計だったため
#   ★実採番と系統的にずれた (宣言 MKC-7 = chapbody の重複注入 / 実 MKC-7 = chapbody だけを章の外へ、 等)。
#   ★機械 gate は緑のまま 人間監査だけが壊れる型 — 読者が MKC-18 を辿ると ★別 shape の mutant に着き、
#   arm の実担保を誤認する。 収束基準「宣言能力 == 実能力 / false record 封鎖」に直接反する。
#   ★双方向の集合一致 で閉じる: (⊆) verify が言及する番号が suite に ★実在 しない = 旧番号の残留、
#   (⊇) suite の MKC ラベルが verify の kill map に ★無い = 新 arm の書き落とし。 ★どちらでも赤くする。
#   ★suite 側の SSOT は ★ラベル先頭の `"MKC-<id> ` (expect_fail / ok / bad に渡す実ラベル) であり、
#   コメント中の言及は数えない (コメントを SSOT にすると「コメントに書けば緑」の恒真経路が開く)。
MECH_SELF="${BASH_SOURCE[0]}"
mech_map_ids="$(grep -oE 'MKC-(C1|[0-9]+[a-z]?)' "$GATE" | LC_ALL=C sort -u)"
mech_suite_ids="$(grep -oE '"MKC-(C1|[0-9]+[a-z]?) ' "$MECH_SELF" | sed -E 's/^"//; s/ $//' | LC_ALL=C sort -u)"
mech_map_n="$(printf '%s\n' "$mech_map_ids" | grep -c .)"
mech_suite_n="$(printf '%s\n' "$mech_suite_ids" | grep -c .)"
mech_stale="$(LC_ALL=C comm -23 <(printf '%s\n' "$mech_map_ids") <(printf '%s\n' "$mech_suite_ids") | grep -c .)"
mech_unmapped="$(LC_ALL=C comm -13 <(printf '%s\n' "$mech_map_ids") <(printf '%s\n' "$mech_suite_ids") | grep -c .)"
# ★producer 存在 assert (負の主張だけにしない): 両集合が空だと差分 0 で ★恒真 PASS する。 現行実測は 55 本
#   (MKC-1〜51 + MKC-2b / MKC-4b / MKC-22b / MKC-C1) — ★floor を実測ちょうどに置き、 arm を減らしたら赤くする。
MECH_MKC_MIN=56
if [[ "$mech_suite_n" -ge "$MECH_MKC_MIN" && "$mech_map_n" -ge "$MECH_MKC_MIN" ]]; then
  ok "MECHPIN ★kill map producer: suite の MKC ラベル $mech_suite_n 本 / verify の言及 $mech_map_n 本 (>= $MECH_MKC_MIN・集合が空での恒真 PASS 封鎖)"
else bad "MECHPIN ★kill map producer: suite $mech_suite_n 本 / verify $mech_map_n 本 (>= $MECH_MKC_MIN 期待) — 抽出の腐り or arm の silent 消失で下の集合一致が恒真化する"; fi
if [[ "$mech_stale" -eq 0 && "$mech_unmapped" -eq 0 ]]; then
  ok "MECHPIN ★kill map 集合一致: verify が言及する MKC 番号 == suite の MKC ラベル ($mech_suite_n 本・旧番号の残留 0 / 新 arm の書き落とし 0)"
else bad "MECHPIN ★kill map 集合一致が破れている (verify にあって suite に無い $mech_stale 本 = 旧番号の残留 / suite にあって verify に無い $mech_unmapped 本 = 新 arm の kill map 未記載) — 裁定 srs 条項 (2) の kill map 再測が未履行"; fi

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
