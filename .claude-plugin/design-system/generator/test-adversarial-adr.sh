#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack 敵対回帰テスト (instance#2)
#
# ADR-pack の fail-closed gate (assemble-adr validate abort / verify-adr FAIL / inject abort) が
# 構造捏造・★cross-doc 照会の dangling/改竄・prose 改竄・term-inline 改竄を捕捉することを回帰確認する。
# SRS-pack の test-adversarial.sh と同型 (敵対の検出力を固定 = ceiling の機械化下限)。
#
# usage: test-adversarial-adr.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASM="$SCRIPT_DIR/assemble-adr.sh"
INJ="$SCRIPT_DIR/inject-prose.sh"
VER="$SCRIPT_DIR/verify-adr.sh"
BASE="$SCRIPT_DIR/contract/clinic-double-booking.adr.yaml"
BASE_PROSE="$SCRIPT_DIR/prose/clinic-double-booking.adr.prose.yaml"
SRS="$SCRIPT_DIR/contract/clinic-appointment.srs.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# ★cross_doc 解決は contract dir 相対。 mutated ADR contract を $TMP に置くため、 照会先 SRS contract も
#   同名で $TMP へ複製する (これをしないと全 abort が「SRS 不在」で起き、 意図した理由を検証できない
#   false-pass になる = S4 の A1 否定検証 false-pass 教訓と同型)。
cp "$SRS" "$TMP/clinic-appointment.srs.yaml"
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

# expect_abort: assemble-adr が exit!=0 で abort し、 かつ stderr に想定理由 ($3) を含むことを要求
# (理由検証で「別原因の誤 abort」= false-pass を弾く)。 mutated contract は $TMP に置く。
expect_abort() { # label contract expected_stderr_substring
  local out rc; out="$(bash "$ASM" "$2" "$TMP/o.html" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then ng "$1 (abort されず生成された)"; return; fi
  if [[ -n "${3:-}" && "$out" != *"$3"* ]]; then ng "$1 (abort したが理由が想定外。 期待 '$3' / 実 stderr 末尾: $(printf '%s' "$out" | tail -1))"; return; fi
  ok "$1"
}
expect_verify_fail() { if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ng "$1 (verify が PASS した)"; else ok "$1"; fi; }
expect_verify_pass() { if bash "$VER" "$2" "$3" >/dev/null 2>&1; then ok "$1"; else ng "$1 (verify FAIL)"; fi; }
expect_verify_fail_filled() { if bash "$VER" --filled "$2" "$3" "$4" >/dev/null 2>&1; then ng "$1 (--filled verify が PASS した)"; else ok "$1"; fi; }
expect_inject_abort() { if bash "$INJ" "$2" "$3" "$TMP/o.html" >/dev/null 2>&1; then ng "$1 (abort されず注入された)"; else ok "$1"; fi; }

# 健全 baseline を一度生成 (HTML 改竄系の元)
bash "$ASM" "$BASE" "$TMP/base.html" >/dev/null 2>&1 || { echo "FATAL: baseline assemble 失敗"; exit 2; }
bash "$INJ" "$BASE_PROSE" "$TMP/base.html" "$TMP/base-filled.html" >/dev/null 2>&1 || { echo "FATAL: baseline inject 失敗"; exit 2; }

echo "ADR-pack adversarial regression (fail-closed expected):"

# === assemble-adr validate (生成前 fail-closed) ===

# A1. ★cross-doc dangling: justifies の req を SRS に無い FR99 に → abort
cp "$BASE" "$TMP/a1.yaml"; yq -i '.decision.justifies[0].req = "FR99"' "$TMP/a1.yaml"
expect_abort "A1 ★cross-doc dangling 照会 (SRS に無い req) を生成前 abort" "$TMP/a1.yaml" "dangling"

# A2. ★cross-doc doc_id 不一致 → abort
cp "$BASE" "$TMP/a2.yaml"; yq -i '.cross_doc.srs_doc_id = "SRS-WRONG"' "$TMP/a2.yaml"
expect_abort "A2 ★cross_doc.srs_doc_id 不一致を abort" "$TMP/a2.yaml" "srs_doc_id"

# A3. ★cross-doc 照会先 contract 不在 → abort
cp "$BASE" "$TMP/a3.yaml"; yq -i '.cross_doc.srs_contract = "nonexistent.srs.yaml"' "$TMP/a3.yaml"
expect_abort "A3 ★照会先 SRS contract 不在を abort" "$TMP/a3.yaml" "見つからない"

# A4. 未知の照会 role (抽象 allowlist 外) → abort
cp "$BASE" "$TMP/a4.yaml"; yq -i '.decision.justifies[0].role = "wild-role"' "$TMP/a4.yaml"
expect_abort "A4 未知の照会 role を abort" "$TMP/a4.yaml" "未知の照会 role"

# A5. verdict=chosen が 2 件 → abort
cp "$BASE" "$TMP/a5.yaml"; yq -i '.options[1].verdict = "chosen"' "$TMP/a5.yaml"
expect_abort "A5 verdict=chosen が複数を abort" "$TMP/a5.yaml" "ちょうど 1 件"

# A6. decision.chosen と verdict=chosen option の不一致 → abort
cp "$BASE" "$TMP/a6.yaml"; yq -i '.decision.chosen = "OPT2"' "$TMP/a6.yaml"
expect_abort "A6 decision.chosen と chosen option 不一致を abort" "$TMP/a6.yaml" "verdict=chosen option"

# A7. decision.chosen が options に無い → abort
cp "$BASE" "$TMP/a7.yaml"; yq -i '.decision.chosen = "OPT-GHOST"' "$TMP/a7.yaml"
expect_abort "A7 decision.chosen が options に無いを abort" "$TMP/a7.yaml" "options に無い"

# A8. 未知の verdict → abort
cp "$BASE" "$TMP/a8.yaml"; yq -i '.options[1].verdict = "maybe"' "$TMP/a8.yaml"
expect_abort "A8 未知の verdict を abort" "$TMP/a8.yaml" "未知の verdict"

# A9. 未知の adr_status → abort
cp "$BASE" "$TMP/a9.yaml"; yq -i '.meta.adr_status = "vibes"' "$TMP/a9.yaml"
expect_abort "A9 未知の adr_status を abort" "$TMP/a9.yaml" "未知の adr_status"

# A10. option id 重複 → abort
cp "$BASE" "$TMP/a10.yaml"; yq -i '.options[1].id = "OPT1"' "$TMP/a10.yaml"
expect_abort "A10 option id 重複を abort" "$TMP/a10.yaml" "option id 重複"

# A11. 値に改行 (@tsv 列ずれの源) → abort
cp "$BASE" "$TMP/a11.yaml"; yq -i '.context[0].detail = "line1" + "\n" + "line2"' "$TMP/a11.yaml"
expect_abort "A11 改行を含む値を abort" "$TMP/a11.yaml" "tab/改行"

# A12. glossary 部分文字列ペア (term-inline ネスト span) → abort
cp "$BASE" "$TMP/a12.yaml"; yq -i '.glossary += [{"term":"ロック","en":"lock","plain_short":"錠","def":"錠の説明。"}]' "$TMP/a12.yaml"
expect_abort "A12 glossary 部分文字列ペア (ロック ⊂ 楽観ロック) を abort" "$TMP/a12.yaml" "部分文字列"

# === HTML 改竄 (生成後 fail-closed = verify-adr) ===

# A13. HTML に偽 data-justifies-req を注入 → verify set 不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/a13.html"
perl -0777 -i -pe 's#(<p class="justify-tgt")#<span data-justifies-req="FR99" data-justifies-role="claim">x</span>$1#' "$TMP/a13.html"
expect_verify_fail_filled "A13 ★HTML への偽 justifies-req 注入を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a13.html"

# A14. option card を 1 枚削除 → 行数不一致 FAIL
cp "$TMP/base-filled.html" "$TMP/a14.html"
perl -0777 -i -pe 's#<div data-component="adr-option-card"[^>]*>.*?</div>\s*</div>##s' "$TMP/a14.html"
expect_verify_fail_filled "A14 option card 削除を行数 gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a14.html"

# A15. prose スロットの内容を改竄 → 注入忠実 FAIL
cp "$TMP/base-filled.html" "$TMP/a15.html"
perl -0777 -i -pe 's#(data-slot-id="decision-rationale">)[^<]*#${1}改竄された根拠#' "$TMP/a15.html"
expect_verify_fail_filled "A15 prose 改竄 (注入忠実) を verify が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a15.html"

# A16. term-inline の併記を誤った plain_short へ改竄 → fidelity FAIL
cp "$TMP/base-filled.html" "$TMP/a16.html"
perl -0777 -i -pe 's#(data-term="ダブルブッキング">)[^<]*#${1}でたらめ#' "$TMP/a16.html"
expect_verify_fail_filled "A16 term-inline 併記改竄を fidelity が捕捉" "$BASE_PROSE" "$BASE" "$TMP/a16.html"

# A17. HTML 改竄: chosen バッジを 2 個に → 可視 verdict 捏造 FAIL
cp "$TMP/base-filled.html" "$TMP/a17.html"
perl -0777 -i -pe 's#class="opt-verdict rejected"#class="opt-verdict chosen"#' "$TMP/a17.html"
expect_verify_fail_filled "A17 可視 chosen バッジ捏造 (2 個) を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a17.html"

# A22. ★HTML 改竄: 照会 role を allowlist 内の別 role へ改竄 (claim→rationale) → (req,role) ペア不一致 FAIL
#      (allowlist 内別 role への偽装は role 数だけでは素通り = fail-open。 ペア集合突合で捕捉する)。
cp "$TMP/base-filled.html" "$TMP/a22.html"
perl -0777 -i -pe 's#(data-justifies-req="FR2" data-justifies-role=)"claim"#${1}"rationale"#' "$TMP/a22.html"
expect_verify_fail_filled "A22 ★照会 role を allowlist 内別 role へ改竄を (req,role) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/a22.html"

# A23. ★HTML 改竄: chosen/rejected バッジを別カードへ付け替え (chosen 総数 1 のまま) → (opt-id,verdict) ペア不一致 FAIL
#      (件数保存型の採用カード偽装は総数==1 だけでは素通り = fail-open。 id↔verdict ペア突合で捕捉する)。
cp "$TMP/base-filled.html" "$TMP/a23.html"
perl -0777 -i -pe 's#(<span class="opt-id">OPT1</span><span class="opt-name">.*?</span><span class="opt-verdict )chosen#${1}rejected#s' "$TMP/a23.html"
perl -0777 -i -pe 's#(<span class="opt-id">OPT2</span><span class="opt-name">.*?</span><span class="opt-verdict )rejected#${1}chosen#s' "$TMP/a23.html"
expect_verify_fail_filled "A23 ★verdict バッジ付け替え (総数不変) を (opt-id,verdict) ペアで捕捉" "$BASE_PROSE" "$BASE" "$TMP/a23.html"

# A24. ★HTML 改竄: 既存 justify edge (FR2 row) を重複注入 (req 集合は不変) → count anchor で FAIL
#      (set_eq は sort -u で重複を潰すため集合不変=fail-open。 count chk とペアで二重 cross-doc 照会を捕捉)。
cp "$TMP/base-filled.html" "$TMP/a24.html"
perl -0777 -i -pe 's#(<div class="justify-row"><a class="justify-req" href="[^"]*" data-justifies-req="FR2".*?</div>)#$1$1#s' "$TMP/a24.html"
expect_verify_fail_filled "A24 ★既存 justify edge の重複注入 (集合不変) を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a24.html"

# ★folio-lzz: navigable anchor (arch referrer の #decision 着地点) の fail-closed。
# ALZZ1. decision panel の navigable id 削除 (arch の cross-doc #decision が 404 復活) → anchor gate が捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz1.html"
perl -0777 -i -pe 's# id="decision"##' "$TMP/alzz1.html"
expect_verify_fail_filled "ALZZ1 ★decision panel navigable id 欠落 (404 復活) を anchor gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz1.html"
# ALZZ2. id="decision" を別要素にも注入 (HTML id collision) → anchor 一意 gate が捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz2.html"
perl -0777 -i -pe 's#(<p class="justify-tgt")#<span id="decision">x</span>$1#' "$TMP/alzz2.html"
expect_verify_fail_filled "ALZZ2 ★id=decision 重複注入 (double-quote collision) を anchor 一意 gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz2.html"
# ALZZ3. ★folio-lzz ceiling [必須-2] 回帰: single-quote decoy (id='decision') → quote-robust uniqueness が捕捉
#        (旧 double-quote リテラル grep は見逃した fail-open)。
cp "$TMP/base-filled.html" "$TMP/alzz3.html"
perl -0777 -i -pe "s{<body>}{<body><div id='decision'>FAKE</div>}" "$TMP/alzz3.html"
expect_verify_fail_filled "ALZZ3 ★id=decision single-quote collision を quote-robust uniqueness で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz3.html"
# ALZZ4. ★数値文字参照 decoy (id="decisio&#110;" = decision) → entity-robust uniqueness が捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz4.html"
perl -0777 -i -pe 's{<body>}{<body><div id="decisio&#110;">FAKE</div>}' "$TMP/alzz4.html"
expect_verify_fail_filled "ALZZ4 ★id=decision 数値文字参照 collision を entity-robust uniqueness で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz4.html"
# ALZZ5. ★大文字 ID 属性 decoy (id 名は case-insensitive・case-robust) → uniqueness が捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz5.html"
perl -0777 -i -pe 's{<body>}{<body><div ID="decision">FAKE</div>}' "$TMP/alzz5.html"
expect_verify_fail_filled "ALZZ5 ★id=decision 大文字 ID 属性 collision を case-robust uniqueness で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz5.html"
# ALZZ6. ★ceiling round-2: HTML5 slash separator collision (<div/id="decision"> は valid な id=decision 要素)。
#   (?<![\w-]) attribute-name 境界が / 区切り decoy を捕捉 (旧 (?<=\s) の取りこぼしを封鎖)。
cp "$TMP/base-filled.html" "$TMP/alzz6.html"
perl -0777 -i -pe 's{<body>}{<body><div/id="decision">FAKE</div>}' "$TMP/alzz6.html"
expect_verify_fail_filled "ALZZ6 ★id=decision slash separator collision を attribute-name 境界 gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz6.html"
# ALZZ7/8. ★ceiling round-3: semicolon-less 数値文字参照 collision (10進 &#110 / 16進 &#x6e = 'n' → decision)。
#   ;? optional terminator decode が ; 無し実体を捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz7.html"
perl -0777 -i -pe 's{<body>}{<body><div id="decisio&#110">FAKE</div>}' "$TMP/alzz7.html"
expect_verify_fail_filled "ALZZ7 ★id=decision semicolon-less 10進実体 collision を entity-robust gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz7.html"
cp "$TMP/base-filled.html" "$TMP/alzz8.html"
perl -0777 -i -pe 's{<body>}{<body><div id="decisio&#x6e">FAKE</div>}' "$TMP/alzz8.html"
expect_verify_fail_filled "ALZZ8 ★id=decision semicolon-less 16進実体 collision を entity-robust gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz8.html"
# ALZZ9/10. ★ceiling round-4: capital-X 16進数値参照 (HTML5 は &#X.. 大文字 X も 16進)。[xX] が捕捉。
cp "$TMP/base-filled.html" "$TMP/alzz9.html"
perl -0777 -i -pe 's{<body>}{<body><div id="decisio&#X6e;">FAKE</div>}' "$TMP/alzz9.html"
expect_verify_fail_filled "ALZZ9 ★id=decision capital-X 16進実体 collision を entity-robust gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz9.html"
cp "$TMP/base-filled.html" "$TMP/alzz10.html"
perl -0777 -i -pe 's{<body>}{<body><div id="&#X64;&#X65;&#X63;&#X69;&#X73;&#X69;&#X6f;&#X6e;">FAKE</div>}' "$TMP/alzz10.html"
expect_verify_fail_filled "ALZZ10 ★id=decision 全 capital-X entity 綴り collision を entity-robust gate が捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzz10.html"

# A25. ★HTML 改竄: verdict バッジの class は正 (chosen) のまま可視ラベルだけ改竄 (採用→不採用) → 可視ラベル整合で FAIL
#      (非エンジニアが読むのは class でなく可視文字。 class 突合だけでは fail-open)。
cp "$TMP/base-filled.html" "$TMP/a25.html"
perl -0777 -i -pe 's#(<span class="opt-verdict chosen">)採用(</span>)#${1}不採用${2}#' "$TMP/a25.html"
expect_verify_fail_filled "A25 ★verdict バッジの可視ラベルのみ改竄 (class は正) を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a25.html"

# A26. ★HTML 改竄: principle.id 改竄 / supersession.status 偽装 / superseded_by 捏造 → 終端章の構造検証で FAIL
#      (assembler が emit する supersession/principle を fabrication-free 対象に拡張)。
cp "$TMP/base-filled.html" "$TMP/a26a.html"; perl -0777 -i -pe 's#PRIN-SAFETY-FIRST#PRIN-FORGED#' "$TMP/a26a.html"
expect_verify_fail_filled "A26a ★principle.id 改竄を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26a.html"
cp "$TMP/base-filled.html" "$TMP/a26b.html"; perl -0777 -i -pe 's#(改訂状態</span>)current#${1}superseded#' "$TMP/a26b.html"
expect_verify_fail_filled "A26b ★supersession.status 偽装を捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26b.html"
cp "$TMP/base-filled.html" "$TMP/a26c.html"; perl -0777 -i -pe 's#(置き換えられた</span>)なし \(現行\)#${1}ADR-Z#' "$TMP/a26c.html"
expect_verify_fail_filled "A26c ★superseded_by 捏造リンクを捕捉" "$BASE_PROSE" "$BASE" "$TMP/a26c.html"

# === ds8: cross-doc helper core 昇格 + research 堅牢化の ADR 横展開 (Part 2a 空値ガード / Part 2b 可視 echo 厳密一致) ===

# A27. ★空 justifies[].req (comm -23 が空行を空 missing に畳む dangling fail-open の兄弟) → 生成前 abort (assemble 側ガード = 実バグ修正)
cp "$BASE" "$TMP/a27.yaml"; yq -i '.decision.justifies[0].req = ""' "$TMP/a27.yaml"
expect_abort "A27 ★空 justifies req (dangling fail-open 兄弟) を生成前 abort" "$TMP/a27.yaml" "空 req"

# A28. ★表紙 ref-chip に平文で偽 id を併記 → 可視テキスト厳密一致で FAIL (research R43/R44 平文併記の ADR 版・attr/<b> は正のまま)
cp "$TMP/base-filled.html" "$TMP/a28.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>FR2・FR3</b>)#${1} 実は FR9#s' "$TMP/a28.html"
expect_verify_fail_filled "A28 ★表紙 ref-chip 平文偽id併記を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a28.html"

# A29. ★表紙 ref-chip に第2 <b> を追加 → <b> ちょうど 2 本要求 (MULTI-B) で FAIL (research R30/R32 追加方向・first-<b> 素通り封鎖)
cp "$TMP/base-filled.html" "$TMP/a29.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>SRS-CLINIC-APPT</b>)#${1} <b>SRS-FAKE</b>#s' "$TMP/a29.html"
expect_verify_fail_filled "A29 ★表紙 ref-chip 第2<b> 追加を <b> 本数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a29.html"

# A30. ★表紙 ref-chip に別タグ <strong> で偽 id を併記 → 全タグ除去後の可視テキスト厳密一致で FAIL (research R38/R39 別タグ注入の ADR 版)
cp "$TMP/base-filled.html" "$TMP/a30.html"
perl -0777 -i -pe 's#(data-component="cross-doc-ref-chip"[^>]*>.*?<b>FR2・FR3</b>)#${1} <strong>FR9</strong>#s' "$TMP/a30.html"
expect_verify_fail_filled "A30 ★表紙 ref-chip <strong> 偽id併記を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a30.html"

# A31. ★表紙 ref-chip の b1<->b2 swap (両 <b> は正規値・位置だけ入替) → 位置別 <b> 突合 (b1==srs_doc_id) で FAIL
cp "$TMP/base-filled.html" "$TMP/a31.html"
perl -0777 -i -pe 's#<b>SRS-CLINIC-APPT</b> の <b>FR2・FR3</b>#<b>FR2・FR3</b> の <b>SRS-CLINIC-APPT</b>#' "$TMP/a31.html"
expect_verify_fail_filled "A31 ★表紙 ref-chip b1<->b2 swap を位置別 <b> 突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a31.html"

# A32. ★照会先 footnote justify-tgt の可視 srs_doc_id を偽 id へ改竄 (<b> 無し平文) → 可視テキスト全体一致で FAIL
cp "$TMP/base-filled.html" "$TMP/a32.html"
perl -0777 -i -pe 's#(class="justify-tgt">照会先: )SRS-CLINIC-APPT#${1}SRS-PHANTOM#' "$TMP/a32.html"
expect_verify_fail_filled "A32 ★justify-tgt 平文 srs_doc_id 改竄を可視テキスト全体一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a32.html"

# A-c5r13. ★justify-tgt 照会ラベル title (live-mirror・folio-c5r.13) を捏造 → 「SRS: 参照先 .meta.title」等値で FAIL。
#   手書き srs_title 廃止後、 チップ title は assembler が参照先 SRS の実 .meta.title から導出する。 参照先改題で
#   build を忘れた stale チップ (= drift) を verify が捕捉することを実証する。
cp "$TMP/base-filled.html" "$TMP/ac5r13.html"
perl -0777 -i -pe 's#(class="justify-tgt">[^<]*SRS: )[^<]+#${1}捏造された参照先タイトル#' "$TMP/ac5r13.html"
expect_verify_fail_filled "A-c5r13 ★justify-tgt 照会ラベル title 捏造を live-mirror 等値で捕捉 (retitle drift)" "$BASE_PROSE" "$BASE" "$TMP/ac5r13.html"

# A-bur-{a..h} ★folio-bur: 可視テキスト echo 捏造 (id/sibling/件数 intact のまま *可視本文* のみ改竄)。verify-adr の folio-bur pin が
#   判断宣言文/原則文/選択肢名・要約/文脈要約/driver・consequence 本文の可視層を contract へ束縛することを実証する。
cp "$TMP/base-filled.html" "$TMP/abura.html"; perl -0777 -i -pe 's#(<p class="dec-state">)[^<]+#${1}FAKE DECISION#' "$TMP/abura.html"
expect_verify_fail_filled "A-bur-a ★dec-state (判断宣言文) 可視捏造を可視==.decision.statement で捕捉" "$BASE_PROSE" "$BASE" "$TMP/abura.html"
cp "$TMP/base-filled.html" "$TMP/aburb.html"; perl -0777 -i -pe 's#(<span class="opt-id">OPT1</span><span class="opt-name">)[^<]+#${1}FAKE OPT#' "$TMP/aburb.html"
expect_verify_fail_filled "A-bur-b ★opt-name 可視捏造を (opt-id,opt-name) 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburb.html"
cp "$TMP/base-filled.html" "$TMP/aburc.html"; perl -0777 -i -pe 's#(<p class="prin-text">)[^<]+#${1}FAKE PRIN#' "$TMP/aburc.html"
expect_verify_fail_filled "A-bur-c ★prin-text (照会終端) 可視捏造を可視==.principle.text で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburc.html"
cp "$TMP/base-filled.html" "$TMP/aburd.html"; perl -0777 -i -pe 's#(<p class="prin-note">)[^<]+#${1}FAKE NOTE#' "$TMP/aburd.html"
expect_verify_fail_filled "A-bur-d ★prin-note 可視捏造を可視==.principle.note で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburd.html"
cp "$TMP/base-filled.html" "$TMP/abure.html"; perl -0777 -i -pe 's#(<p class="cxh">)[^<]+#${1}FAKE CXH#' "$TMP/abure.html"
expect_verify_fail_filled "A-bur-e ★cxh (context summary) 可視捏造を順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/abure.html"
cp "$TMP/base-filled.html" "$TMP/aburf.html"; perl -0777 -i -pe 's#(<p class="opt-sum">)[^<]+#${1}FAKE SUM#' "$TMP/aburf.html"
expect_verify_fail_filled "A-bur-f ★opt-sum 可視捏造を順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburf.html"
cp "$TMP/base-filled.html" "$TMP/aburg.html"; perl -0777 -i -pe 's#(<td class="drid">DR1</td><td>)[^<]+#${1}FAKE DRIVER #' "$TMP/aburg.html"
expect_verify_fail_filled "A-bur-g ★driver 本文 可視捏造を drg 除去後の順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburg.html"
cp "$TMP/base-filled.html" "$TMP/aburh.html"; perl -0777 -i -pe 's#(data-component="adr-consequence-pos"><span class="b">[^<]+</span>)[^<]+#${1}FAKE CSQ#' "$TMP/aburh.html"
expect_verify_fail_filled "A-bur-h ★consequence-pos 本文 可視捏造を件数+内容二層で捕捉 (●span 温存)" "$BASE_PROSE" "$BASE" "$TMP/aburh.html"
# A-bur-r2-{a,b} ★folio-bur round-2 (ceiling-recursion): 可視本文 chk の射程外を突く decoy を quote-robust 占有数パリティで捕捉。
cp "$TMP/base-filled.html" "$TMP/aburr2a.html"; perl -0777 -i -pe 's{(<p class="dec-state">)}{<p class="dec-state">捏造決定(decoy)</p>${1}}' "$TMP/aburr2a.html"
expect_verify_fail_filled "A-bur-r2a ★dec-state 占有 decoy (+1) を count_attr_token 占有数パリティで捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr2a.html"
cp "$TMP/base-filled.html" "$TMP/aburr2b.html"; perl -0777 -i -pe "s{(<li data-component=\"adr-consequence-pos\">)}{<li data-component='adr-consequence-pos'><span class=\"b\">●</span>捏造の良い結果</li>\${1}}" "$TMP/aburr2b.html"
expect_verify_fail_filled "A-bur-r2b ★consequence single-quote decoy を count_attr_token data-component で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr2b.html"
# A-bur-r3-{a..e} ★folio-bur round-3 (ceiling-recursion R2 是正): round-1/2 が positive 兄弟だけ pin し列挙漏れした
#   5 可視サーフェス (negative 結果 / context detail / option pros-cons / justify-note / supersession note) の決定根拠捏造を捕捉。
cp "$TMP/base-filled.html" "$TMP/aburr3a.html"; perl -0777 -i -pe 's#(<li data-component="adr-consequence-neg"><span class="b">[^<]*</span>).*?</li>#${1}このアプローチには欠点もトレードオフも一切存在せず完璧である (虚偽)</li>#s' "$TMP/aburr3a.html"
expect_verify_fail_filled "A-bur-r3-a ★consequence-neg 本文捏造 (トレードオフ消去) を可視+占有で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3a.html"
cp "$TMP/base-filled.html" "$TMP/aburr3b.html"; perl -0777 -i -pe 's#<p class="cxd">.*?</p>#<p class="cxd">この問題は実在せず何の対策も不要である (虚偽の文脈)</p>#s' "$TMP/aburr3b.html"
expect_verify_fail_filled "A-bur-r3-b ★context detail (cxd) 捏造を可視+占有で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3b.html"
cp "$TMP/base-filled.html" "$TMP/aburr3c1.html"; perl -0777 -i -pe 's#(<div class="pros"><h4>\+ 利点</h4><ul>\s*<li>).*?</li>#${1}無限スケール+無コストを同時実現 (虚偽の利点)</li>#s' "$TMP/aburr3c1.html"
expect_verify_fail_filled "A-bur-r3-c1 ★option pros 本文捏造を option-keyed set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3c1.html"
cp "$TMP/base-filled.html" "$TMP/aburr3c2.html"; perl -0777 -i -pe 's#(<div class="pros"><h4>\+ 利点</h4><ul>)#${1}<li>法的リスクをゼロにし監査も自動で完璧通過 (捏造した利点)</li>#' "$TMP/aburr3c2.html"
expect_verify_fail_filled "A-bur-r3-c2 ★option pros 件数追加 (捏造 li) を option-keyed set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3c2.html"
cp "$TMP/base-filled.html" "$TMP/aburr3d.html"; perl -0777 -i -pe 's#(<span class="justify-note">)[^<]+#${1}この要件は実際には別の理由で正当化される (捏造した照会根拠)#' "$TMP/aburr3d.html"
expect_verify_fail_filled "A-bur-r3-d ★justify-note (照会根拠説明文) 捏造を可視+占有で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3d.html"
cp "$TMP/base-filled.html" "$TMP/aburr3e.html"; perl -0777 -i -pe 's#(<p class="ss-row">)本 ADR は現行.*?</p>#${1}この ADR は既に廃止され別案に置き換わった (虚偽の改訂注記)</p>#s' "$TMP/aburr3e.html"
expect_verify_fail_filled "A-bur-r3-e ★supersession note (自由文注記) 捏造を可視で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr3e.html"
# A-bur-r4-{a..e} ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 fix 自体の quote/first-match/occupancy 未完を occupancy で封鎖。
cp "$TMP/base-filled.html" "$TMP/aburr4a.html"; perl -0777 -i -pe "s{(<div class=\"pros\">)}{<div class='pros'><h4>+ 利点</h4><ul><li>無限スケール無コスト(虚偽)</li></ul></div>\${1}}" "$TMP/aburr4a.html"
expect_verify_fail_filled "A-bur-r4-a ★single-quote pros div decoy を pros 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr4a.html"
cp "$TMP/base-filled.html" "$TMP/aburr4b.html"; perl -0777 -i -pe 's{(<div class="pros">)}{<div class="pros"><h4>+ 利点</h4><ul><li>二重pros捏造</li></ul></div>${1}}' "$TMP/aburr4b.html"
expect_verify_fail_filled "A-bur-r4-b ★2個目 double-quote pros div (first-match 射程外) を pros 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr4b.html"
cp "$TMP/base-filled.html" "$TMP/aburr4c.html"; perl -0777 -i -pe "s{(<span class=\"k\">状態</span>)}{<span class='k'>状態</span><span class='v'>廃止(虚偽)</span>\${1}}" "$TMP/aburr4c.html"
expect_verify_fail_filled "A-bur-r4-c ★cover-meta single-quote KV decoy を k 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr4c.html"
cp "$TMP/base-filled.html" "$TMP/aburr4d.html"; perl -0777 -i -pe "s{(</section>)}{<p class='ss-row'>既に廃止され置換済(虚偽)</p>\${1}}" "$TMP/aburr4d.html"
expect_verify_fail_filled "A-bur-r4-d ★ss-row single-quote note decoy を ss-row 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr4d.html"
cp "$TMP/base-filled.html" "$TMP/aburr4e.html"; perl -0777 -i -pe 's{(<span class="ss-k">改訂状態</span>)}{<span class="ss-k">廃止予定日</span>2026-12-31(捏造)${1}}' "$TMP/aburr4e.html"
expect_verify_fail_filled "A-bur-r4-e ★allowlist 外 novel ss-k 行を ss-k 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr4e.html"
# A-bur-r5-{a..f} ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 が pros/cons/k/ss-row/ss-k へ展開した count_attr_token
#   占有 idiom を可視 echo の count anchor (double-quote 固定 grep -c / count anchor 不在) に未展開だった穴。 single-quote/裸 additive decoy
#   で採用判断・偽 cross-doc 照会・phantom 文脈 id/role/req を捏造でき素通った (dec-kick/jh=blocker)。 全 echo を quote-robust 占有へ統一。
cp "$TMP/base-filled.html" "$TMP/aburr5a.html"; perl -0777 -i -pe "s{(<p class=\"dec-kick\">)}{<p class='dec-kick'>採用 — OPT-EVIL（捏造）</p>\${1}}" "$TMP/aburr5a.html"
expect_verify_fail_filled "A-bur-r5-a ★single-quote dec-kick decoy (二重採用見出し=ADR 最 load-bearing) を dec-kick 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5a.html"
cp "$TMP/base-filled.html" "$TMP/aburr5b.html"; perl -0777 -i -pe "s{(<p class=\"jh\">)}{<p class='jh'>この判断が正当化する要件 (cross-doc 照会 → SRS-EVIL)</p>\${1}}" "$TMP/aburr5b.html"
expect_verify_fail_filled "A-bur-r5-b ★single-quote jh decoy (偽 cross-doc provenance) を jh 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5b.html"
cp "$TMP/base-filled.html" "$TMP/aburr5c.html"; perl -0777 -i -pe "s{(<p class=\"justify-tgt\">)}{<p class='justify-tgt'>照会先: SRS-EVIL — SRS: 偽タイトル</p>\${1}}" "$TMP/aburr5c.html"
expect_verify_fail_filled "A-bur-r5-c ★single-quote justify-tgt decoy (偽照会先 footnote) を justify-tgt 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5c.html"
cp "$TMP/base-filled.html" "$TMP/aburr5d.html"; perl -0777 -i -pe "s{(<span class=\"cxid\">)}{<span class='cxid'>CTX-EVIL</span>\${1}}" "$TMP/aburr5d.html"
expect_verify_fail_filled "A-bur-r5-d ★single-quote cxid decoy (phantom 文脈 id) を cxid 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5d.html"
cp "$TMP/base-filled.html" "$TMP/aburr5e.html"; perl -0777 -i -pe "s{(<span class=\"justify-role\">)}{<span class='justify-role'>verification</span>\${1}}" "$TMP/aburr5e.html"
expect_verify_fail_filled "A-bur-r5-e ★single-quote justify-role decoy (偽 cross-doc edge role) を justify-role 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5e.html"
cp "$TMP/base-filled.html" "$TMP/aburr5f.html"; perl -0777 -i -pe "s{(<a class=\"justify-req\")}{<span class='justify-req'>FR-EVIL</span>\${1}}" "$TMP/aburr5f.html"
expect_verify_fail_filled "A-bur-r5-f ★裸 single-quote justify-req span (data 属性無) を justify-req 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr5f.html"
# A-bur-r6-{a..e} ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 sweep が取りこぼした兄弟 echo (prin-id/drg/cover-meta-v) + novel-marker 系統封鎖。
cp "$TMP/base-filled.html" "$TMP/aburr6a.html"; perl -0777 -i -pe "s{(<div data-component=\"adr-principle\">)}{\${1}<p class='prin-id'>照会終端 — PRIN-EVIL（捏造）</p>}" "$TMP/aburr6a.html"
expect_verify_fail_filled "A-bur-r6-a ★single-quote prin-id decoy (照会 graph 終端 identity 捏造) を prin-id 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr6a.html"
cp "$TMP/base-filled.html" "$TMP/aburr6b.html"; perl -0777 -i -pe "s{(</tbody>)}{<span class='drg'>SRS NFR2 / N-9（捏造）</span>\${1}}" "$TMP/aburr6b.html"
expect_verify_fail_filled "A-bur-r6-b ★single-quote drg decoy (偽 grounds linkage) を drg 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr6b.html"
cp "$TMP/base-filled.html" "$TMP/aburr6c.html"; perl -0777 -i -pe 's{(<span class="k">状態</span><span class="v">[^<]*</span>)}{${1}<span class="v">廃止済み（捏造）</span>}' "$TMP/aburr6c.html"
expect_verify_fail_filled "A-bur-r6-c ★k 無し単独 cover-meta v decoy (矛盾状態値) を v 占有数で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr6c.html"
cp "$TMP/base-filled.html" "$TMP/aburr6d.html"; perl -0777 -i -pe "s{(</body>)}{<p class='evil-novel'>偽の採用判断（捏造 novel class）</p>\${1}}" "$TMP/aburr6d.html"
expect_verify_fail_filled "A-bur-r6-d ★novel class 注入を class-token 機械的網羅で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr6d.html"
cp "$TMP/base-filled.html" "$TMP/aburr6e.html"; perl -0777 -i -pe "s{(</body>)}{<div data-component='adr-evil-panel'>偽パネル（捏造 novel data-component）</div>\${1}}" "$TMP/aburr6e.html"
expect_verify_fail_filled "A-bur-r6-e ★novel data-component 注入を data-component 機械的網羅で捕捉" "$BASE_PROSE" "$BASE" "$TMP/aburr6e.html"

# A33. ★justify-tgt をブロックごと削除 → ブロック==1 count anchor で FAIL (while が回らず @bad 空の素通りを塞ぐ・research と同じ規律)
cp "$TMP/base-filled.html" "$TMP/a33.html"
perl -0777 -i -pe 's#<p class="justify-tgt">.*?</p>##s' "$TMP/a33.html"
expect_verify_fail_filled "A33 ★justify-tgt ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a33.html"

# A34. ★justify-row の可視 req を改竄 (data-justifies-req 属性は正) → attr-vs-visible 厳密一致で FAIL
#      (research R24/within-doc (k') の ADR 版。 非エンジニアが読む可視 req だけ捏造し attr 温存する経路を封鎖)。
cp "$TMP/base-filled.html" "$TMP/a34.html"
perl -0777 -i -pe 's#(data-justifies-req="FR2" data-justifies-role="claim">)FR2(</a>)#${1}FR9${2}#' "$TMP/a34.html"
expect_verify_fail_filled "A34 ★justify-row 可視 req 改竄 (attr 正) を attr-vs-visible で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a34.html"

# A35. ★justify-req span を 1 枚削除 → justify-req span == |justifies| count anchor で FAIL (cross-doc count とも二重に捕捉)
cp "$TMP/base-filled.html" "$TMP/a35.html"
perl -0777 -i -pe 's#<a class="justify-req" href="[^"]*" data-justifies-req="FR3".*?</a>##s' "$TMP/a35.html"
expect_verify_fail_filled "A35 ★justify-req span 削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a35.html"

# ★folio-c5r.9 cross-doc href 遷移先 fidelity 敵対 (arch gate 1h 同型・justify-req を <a href> 化)。
# ALZZ-H1. justify-req href anchor swap (#FR2→#FR99・attr/可視 温存) → href set_eq で FAIL
cp "$TMP/base-filled.html" "$TMP/alzzh1.html"
perl -0777 -i -pe 's{(<a class="justify-req" href="clinic-appointment.srs.html)#FR2(" data-justifies-req="FR2")}{${1}#FR99${2}}' "$TMP/alzzh1.html"
expect_verify_fail_filled "ALZZ-H1 ★justify-req href anchor swap (#FR2→#FR99) を href set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzzh1.html"
# ALZZ-H2. justify-req href filename swap (外部 host) → href set_eq で FAIL
cp "$TMP/base-filled.html" "$TMP/alzzh2.html"
perl -0777 -i -pe 's{<a class="justify-req" href="clinic-appointment.srs.html#FR2"}{<a class="justify-req" href="https://evil.example#FR2"}' "$TMP/alzzh2.html"
expect_verify_fail_filled "ALZZ-H2 ★justify-req href filename swap (外部 host) を href set_eq で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzzh2.html"
# ALZZ-H3. justify-req href 剥奪 (span 退行・押せないリンク) → <a href> 件数 anchor で FAIL
cp "$TMP/base-filled.html" "$TMP/alzzh3.html"
perl -0777 -i -pe 's#<a class="justify-req" href="[^"]*" (data-justifies-req="FR2" data-justifies-role="claim">FR2)</a>#<span class="justify-req" ${1}</span>#' "$TMP/alzzh3.html"
expect_verify_fail_filled "ALZZ-H3 ★justify-req href 剥奪 (span 退行) を <a href> 件数 anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/alzzh3.html"

# A36. ★表紙 ref-chip をブロックごと削除 → ブロック==1 count anchor で FAIL (可視テキスト厳密一致は while 空回りで素通る=
#      設計が名指しする fail-open。 88行 count anchor が唯一の guard ゆえ A33/justify-tgt・A35/justify-req と対称に固定する)。
cp "$TMP/base-filled.html" "$TMP/a36.html"
perl -0777 -i -pe 's#<div class="reader-chip" data-component="cross-doc-ref-chip">.*?</div>##s' "$TMP/a36.html"
expect_verify_fail_filled "A36 ★表紙 ref-chip ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a36.html"

# === ds8 ceiling 反映: jh 見出し (第4の可視 cross-doc echo) + wrapper-tag swap (marker-keyed parity) ===

# A37. ★jh 見出しの可視 srs_doc_id を偽 id へ改竄 (tag 維持・<b> 無し平文) → 可視テキスト全体一致で FAIL
#      (ds8 ceiling 検出: Part 2b が jh を列挙し忘れ偽 doc_id が素通っていた = 機械的完全性照合の漏れ是正)。
cp "$TMP/base-filled.html" "$TMP/a37.html"
perl -0777 -i -pe 's#(class="jh">.*?)SRS-CLINIC-APPT#${1}SRS-PHANTOM#s' "$TMP/a37.html"
expect_verify_fail_filled "A37 ★jh 見出し平文 srs_doc_id 改竄を可視テキスト全体一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a37.html"

# A38. ★jh 見出しの wrapper-tag swap (<p>→<div>) + 偽 id → marker-keyed while が任意タグを捕捉して FAIL
#      (tag 固定だと <p> 以外へ swap で while スキップ→可視検査回避の fail-open。 marker-keyed で封鎖)。
cp "$TMP/base-filled.html" "$TMP/a38.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="jh"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</div>"#se' "$TMP/a38.html"
expect_verify_fail_filled "A38 ★jh wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a38.html"

# A39. ★jh 見出しをブロックごと削除 → jh ブロック==1 count anchor で FAIL (while 空回り素通りを塞ぐ・A33/A36 と対称)
cp "$TMP/base-filled.html" "$TMP/a39.html"
perl -0777 -i -pe 's#<p class="jh">.*?</p>##s' "$TMP/a39.html"
expect_verify_fail_filled "A39 ★jh ブロック削除を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a39.html"

# A40. ★表紙 ref-chip の wrapper-tag swap (<div>→<span>) + <b> 内 srs_doc_id 偽装 → marker-keyed while で FAIL
#      (ds8 ceiling major: count anchor は marker-only だが while が tag 固定 = selector 非パリティで swap が可視検査を逃れていた)。
cp "$TMP/base-filled.html" "$TMP/a40.html"
perl -0777 -i -pe 's#<div(\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>)(.*?)</div>#"<span".$1.($2 =~ s{<b>SRS-CLINIC-APPT</b>}{<b>SRS-PHANTOM</b>}r)."</span>"#se' "$TMP/a40.html"
expect_verify_fail_filled "A40 ★ref-chip wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a40.html"

# A41. ★justify-tgt の wrapper-tag swap (<p>→<div>) + 偽 id → marker-keyed while で FAIL
cp "$TMP/base-filled.html" "$TMP/a41.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="justify-tgt"[^>]*>)(.*?)</p>#"<div".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</div>"#se' "$TMP/a41.html"
expect_verify_fail_filled "A41 ★justify-tgt wrapper-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a41.html"

# === ds8 ceiling round-2 反映: nested-same-tag early-match / hyphen-tag / identity echo (dec-kick/prin-id) ===

# A42. ★jh に空 <p></p> を入れ子注入し (.*?) を早期終端 → 捕捉群外に偽 provenance を可視追記 → nested-same-tag reject で FAIL
#      (round-2 blocker: marker-keyed backreference の最深兄弟。 早期終端の痕跡 <p> が捕捉群に残るのを reject する不動点)。
cp "$TMP/base-filled.html" "$TMP/a42.html"
perl -0777 -i -pe 's#(<p class="jh">[^<]*)</p>#${1}<p></p></p> 実は SRS-EVIL が正当化#' "$TMP/a42.html"
expect_verify_fail_filled "A42 ★jh nested-tag early-match+群外偽provenance を nested-reject で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a42.html"

# A43. ★ref-chip に空 <div></div> を入れ子注入し早期終端 → 群外に偽要件を可視追記 → nested-same-tag reject で FAIL
cp "$TMP/base-filled.html" "$TMP/a43.html"
perl -0777 -i -pe 's#(<div class="reader-chip" data-component="cross-doc-ref-chip">.*?)</div>#${1}<div></div></div> 実は SRS-EVIL の正当化要件#s' "$TMP/a43.html"
expect_verify_fail_filled "A43 ★ref-chip nested-tag early-match+群外偽要件 を nested-reject で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a43.html"

# A44. ★justify-tgt の hyphen-tag swap (<p>→<my-tag>) + 偽 id → marker-keyed の [A-Za-z][\w-]* がハイフンタグを捕捉して FAIL
#      (round-2 blocker: \w+ だとハイフンタグを取りこぼし count anchor も backstop にならなかった)。
cp "$TMP/base-filled.html" "$TMP/a44.html"
perl -0777 -i -pe 's#<p(\b[^>]*\bclass="justify-tgt"[^>]*>)(.*?)</p>#"<my-tag".$1.($2 =~ s{SRS-CLINIC-APPT}{SRS-PHANTOM}r)."</my-tag>"#se' "$TMP/a44.html"
expect_verify_fail_filled "A44 ★justify-tgt hyphen-tag swap+偽id を marker-keyed で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a44.html"

# A45. ★dec-kick (採用見出し) の可視 chosen を偽 id へ改竄 → 可視テキスト厳密一致で FAIL (round-2: identity echo の列挙漏れ是正)
cp "$TMP/base-filled.html" "$TMP/a45.html"
perl -0777 -i -pe 's#(<p class="dec-kick">採用 — )[^<]*#${1}OPT-EVIL#' "$TMP/a45.html"
expect_verify_fail_filled "A45 ★dec-kick chosen 改竄を可視テキスト厳密一致で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a45.html"

# A46. ★prin-id を duplicate-decoy (隠し正規 <p> を残し可視偽 <p> を付け足し) → prin-id 行==1 count anchor で FAIL (round-2 major)
cp "$TMP/base-filled.html" "$TMP/a46.html"
perl -0777 -i -pe 's#(<p class="prin-id">[^<]*</p>)#${1}<p class="prin-id">原則 — PRIN-FORGED</p>#' "$TMP/a46.html"
expect_verify_fail_filled "A46 ★prin-id duplicate-decoy を count anchor で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a46.html"

# === ds8 ceiling round-3 反映: ADR identity echo parity (cover-meta / cxid / drid) ===

# A47. ★表紙 cover-meta の 結果 KV を可視改竄 → 決定的再導出突合で FAIL (round-2 まで ADR cover-meta は皆無検証 = research (l') との parity gap)
cp "$TMP/base-filled.html" "$TMP/a47.html"
perl -0777 -i -pe 's#(<span class="k">結果</span><span class="v">)[^<]*#${1}良い 9 / トレードオフ 9#' "$TMP/a47.html"
expect_verify_fail_filled "A47 ★cover-meta 結果 改竄を再導出突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a47.html"

# A48. ★可視 cxid (context id) を改竄 (attr/contract 一意性は不変) → within-doc 順序突合で FAIL (research (k') との parity)
cp "$TMP/base-filled.html" "$TMP/a48.html"
perl -0777 -i -pe 's#(<span class="cxid">)CTX1#${1}CTX-PHANTOM#' "$TMP/a48.html"
expect_verify_fail_filled "A48 ★可視 cxid 改竄を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a48.html"

# A49. ★可視 drid (driver id) を改竄 → within-doc 順序突合で FAIL
cp "$TMP/base-filled.html" "$TMP/a49.html"
perl -0777 -i -pe 's#(class="drid">)DR1#${1}DR-PHANTOM#' "$TMP/a49.html"
expect_verify_fail_filled "A49 ★可視 drid 改竄を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a49.html"

# A50. ★round-4: 可視 justify-role を allowlist 内別 role へ swap (claim→rationale・data-justifies-role attr は正) → within-doc 順序突合で FAIL
#      (round-2 で可視 req==attr は強制したが role の可視を漏らした parity 漏れ = cross-doc edge の可視 fidelity)
cp "$TMP/base-filled.html" "$TMP/a50.html"
perl -0777 -i -pe 's#(<span class="justify-role">)claim#${1}rationale#' "$TMP/a50.html"
expect_verify_fail_filled "A50 ★可視 justify-role swap を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a50.html"

# A51. ★dty (folio-dty): 可視 drg (driver grounds バッジ) を改竄 → within-doc drg 順序突合で FAIL。
#      round-4 で drid (driver id) は突合したが grounds の可視テキストを漏らした fail-open (drid/cxid と同型・SRS 7e と parity)。
cp "$TMP/base-filled.html" "$TMP/a51.html"
perl -0777 -i -pe 's#(<span class="drg">)SRS GOAL 1#${1}捏造の根拠 — 元は#' "$TMP/a51.html"
expect_verify_fail_filled "A51 ★可視 drg (driver grounds) 改竄を within-doc 順序突合で捕捉" "$BASE_PROSE" "$BASE" "$TMP/a51.html"

# === A52-A71: core 共通 chrome (cover-head/approval/glossary) の floor 突合 (folio-mk9・verify_core_chrome) ===
# lib/common.sh が全 pack 同一構造で emit する決定的可視 chrome 値の改竄を verify_core_chrome が FAIL することを回帰確認 (SRS の A110-A129 と parity)。
# (a) 値改竄 = 順序突合が捕捉 / (b) decoy 注入 (大文字化/entity/unquoted/single-quote) = 占有数パリティが捕捉。 python landed-assert で改竄着地を強制。
chrome_tamper_fail() { # label needle replacement
  if python3 -c "
d=open('$TMP/base.html').read()
o='''$2'''; assert o in d, 'needle not found'
open('$TMP/chrome.html','w').write(d.replace(o,'''$3''',1))
" 2>/dev/null; then expect_verify_fail "$1" "$BASE" "$TMP/chrome.html"; else ng "$1 setup 失敗"; fi
}
chrome_decoy_fail() { # label decoy_html (</h1> 直後へ decoy 注入)
  if python3 -c "
d=open('$TMP/base.html').read()
o='</h1>'; assert o in d, 'anchor not found'
open('$TMP/chromed.html','w').write(d.replace(o,o+'''$2''',1))
" 2>/dev/null; then expect_verify_fail "$1" "$BASE" "$TMP/chromed.html"; else ng "$1 setup 失敗"; fi
}
# (a) 値改竄
chrome_tamper_fail "A52 ★cover eyebrow_left 改竄を core-chrome 順序突合で捕捉" '<span class="doc-type">設計判断記録 (ADR)</span>' '<span class="doc-type">詐欺ラベル</span>'
chrome_tamper_fail "A53 ★cover eyebrow_right 改竄を core-chrome 順序突合で捕捉" '<span>クリニック — 二重予約防止</span>' '<span>詐欺の右ラベル</span>'
chrome_tamper_fail "A54 ★cover title (h1) 改竄を core-chrome 順序突合で捕捉" '<h1>同じ診療枠への二重予約を、 アプリ側の確認でなく「枠の取り合いに強い確定方式」で防ぐ</h1>' '<h1>詐欺タイトル</h1>'
chrome_tamper_fail "A55 ★cover subtitle 改竄を core-chrome 順序突合で捕捉" '<p class="cover-sub">複数の患者がほぼ同時に同じ枠を申し込んでも、 確定するのは 1 件だけにする方式を選ぶ</p>' '<p class="cover-sub">詐欺サブタイトル</p>'
chrome_tamper_fail "A56 ★reader (想定読者) 改竄を core-chrome 順序突合で捕捉" '想定読者: クリニックの事業責任者 + 開発リード — 医療コーディングの専門知識は不要 (専門語はやさしい言葉を併記)</div>' '想定読者: 詐欺の読者</div>'
chrome_tamper_fail "A57 ★approval role 改竄を core-chrome 順序突合で捕捉" '<span class="role">承認 (院長)</span>' '<span class="role">詐欺の役職</span>'
chrome_tamper_fail "A58 ★approval who (承認者名) 改竄を core-chrome 順序突合で捕捉" '<span class="who">山田 理恵</span>' '<span class="who">詐欺 太郎</span>'
chrome_tamper_fail "A59 ★approval when (承認日) 改竄を core-chrome 順序突合で捕捉" '<span class="when">2026-06-17 承認</span>' '<span class="when">1999-01-01 承認</span>'
chrome_tamper_fail "A60 ★approval stamp (印) 改竄を core-chrome 順序突合で捕捉" '<span class="stamp">承認済</span>' '<span class="stamp">却下</span>'
chrome_tamper_fail "A61 ★glossary term 改竄を core-chrome 順序突合で捕捉" '<div class="gword">ダブルブッキング<span class="en">' '<div class="gword">詐欺用語<span class="en">'
chrome_tamper_fail "A62 ★glossary en 改竄を core-chrome 順序突合で捕捉" '<span class="en">double booking</span>' '<span class="en">fraud-en</span>'
chrome_tamper_fail "A63 ★glossary def 改竄を core-chrome 順序突合で捕捉" '<div class="gdef">同じ枠に 2 人以上を入れてしまう事故。 来院した患者を待たせたり断ることになる。</div>' '<div class="gdef">詐欺の定義</div>'
# (b) decoy 注入 (占有数パリティが捕捉)
chrome_decoy_fail "A64 ★doc-type 大文字化 decoy を doc-type 占有数で捕捉" '<span class="DOC-TYPE">詐欺の文書種</span>'
chrome_decoy_fail "A65 ★sign 行 大文字化 decoy (偽承認行) を sign 占有数で捕捉" '<div class="SIGN"><span class="role">詐欺</span><span class="who">x</span><span class="when">y</span><span class="stamp">z</span></div>'
chrome_decoy_fail "A66 ★grow 行 大文字化 decoy (偽用語行) を grow 占有数で捕捉" '<div class="GROW"><div class="gword">詐欺</div><div class="gdef">x</div></div>'
chrome_decoy_fail "A67 ★who entity-encoded decoy (&#119;ho) を文字参照 decode 占有数で捕捉" '<span class="&#119;ho">詐欺の承認者</span>'
chrome_decoy_fail "A68 ★stamp unquoted decoy (class=stamp) を quote 非依存 占有数で捕捉" '<span class=stamp>詐欺の印</span>'
chrome_decoy_fail "A69 ★h1 大文字化 decoy (<H1>) を h1 タグ占有数で捕捉" '<H1>詐欺の第二タイトル</H1>'
chrome_decoy_fail "A70 ★想定読者 marker decoy (偽 reader-chip) を marker 占有数 + 値突合で捕捉" '<div class="reader-chip"> 想定読者: 詐欺の第二読者</div>'
# A70b ★marker *無し* の偽 reader-chip decoy (anchor 一致だが "想定読者:" 無し) を構造 anchor 占有数で捕捉 (A70 では漏れる fail-open を塞いだ folio-mk9 self-review 回帰)。
chrome_decoy_fail "A70b ★想定読者 *無し* の偽 reader-chip decoy を anchor 占有数で捕捉" '<div class="reader-chip"> 詐欺の追加チップ</div>'
# A70c ★ref-chip *構文形* の偽 reader-chip decoy (`class="reader-chip" role="note">…` = 閉じ引用後に空白+任意属性) を占有数パリティで捕捉。
#        A70b の anchor grep (`class="reader-chip">` = > 直後) は不一致・marker count も "想定読者:" 無しで不一致ゆえ素通る fail-open を
#        (class reader-chip 占有) − (data-component cross-doc-ref-chip 占有) == 1 で塞いだ回帰 (folio-mk9 self-review round-3)。
chrome_decoy_fail "A70c ★ref-chip 構文形の偽 reader-chip decoy を占有数パリティで捕捉" '<div class="reader-chip" role="note">詐欺の偽 reader-chip…</div>'
# A70d ★ref-chip と *同一構文* (class="reader-chip" data-component="cross-doc-ref-chip") を持つ additive decoy に偽『想定読者:』text を載せた攻撃。
#        旧 差分式 `(class reader-chip 占有) − (cross-doc-ref-chip 占有)` は被減数 (+1)・減数 (+1) が同タグ上で同時に増えて差 1 のまま不変ゆえ素通った
#        (folio-mk9 self-review round-4 が SRS full verify exit 0 で実証)。 element-level genuine count + global『想定読者:』marker count==1 で塞いだ回帰。
chrome_decoy_fail "A70d ★ref-chip 同一構文+偽『想定読者:』additive decoy を要素単位+marker 全体数で捕捉" '<div class="reader-chip" data-component="cross-doc-ref-chip">想定読者: 詐欺の偽読者</div>'
# A70e/f ★ref-chip 構文形 + single-quote/unquoted data-component の偽 ref-chip decoy (folio-mk9 self-review round-6・FO-1)。
#         count_genuine は data-component を quote-robust に読み ref-chip 側へ分類 (genuine 1)・ref-chip ブロック grep は double-quote 固定で見逃す
#         (ref-chip 1)・marker 無し ゆえ素通った fail-open を、 reader-chip class 総数 == 2 (§1b'・quote-robust count_attr_token) で封鎖した回帰。
chrome_decoy_fail "A70e ★single-quote data-component の偽 ref-chip decoy を reader-chip 総数==2 で捕捉" "<div class=\"reader-chip\" data-component='cross-doc-ref-chip'>規制当局承認済（捏造）</div>"
chrome_decoy_fail "A70f ★unquoted data-component の偽 ref-chip decoy を reader-chip 総数==2 で捕捉" '<div class="reader-chip" data-component=cross-doc-ref-chip>法的拘束力契約（捏造）</div>'
# A70g ★属性値内 > で count_genuine の tag-splitter を断片化した genuine-style decoy (folio-mk9 self-review round-6・FO-2)。
#        count_genuine の旧 [^>]* は title 内 > で早期終端し class を取り逃した。 tag-splitter 堅牢化 + reader-chip 総数==2 の二層で封鎖した回帰。
chrome_decoy_fail "A70g ★title内 > で断片化する genuine-style decoy を tag-splitter堅牢化+総数==2 で捕捉" '<div title="x>y" class="reader-chip" role="z">捏造の権威 box</div>'
chrome_tamper_fail "A71 ★glossary en single-quote decoy を grow 行内 en 占有数で捕捉" '<div class="gword">ダブルブッキング<span class="en">double booking</span></div>' "<div class=\"gword\">ダブルブッキング<span class=\"en\">double booking</span><span class='en'>詐欺</span></div>"

# === inject fail-closed ===

# A18. manifest から 1 スロットを削除 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/a18.prose.yaml"; yq -i 'del(.slots.["decision-rationale"])' "$TMP/a18.prose.yaml"
expect_inject_abort "A18 manifest 欠落スロットを inject が abort" "$TMP/a18.prose.yaml" "$TMP/base.html"

# A19. manifest に orphan キー追加 → 集合不一致 abort
cp "$BASE_PROSE" "$TMP/a19.prose.yaml"; yq -i '.slots.["ghost-slot"] = "幽霊"' "$TMP/a19.prose.yaml"
expect_inject_abort "A19 manifest orphan キーを inject が abort" "$TMP/a19.prose.yaml" "$TMP/base.html"

# === 健全性 (false-positive 防止: baseline は PASS であること) ===
expect_verify_pass "A20 健全 baseline は pre-fill verify PASS" "$BASE" "$TMP/base.html"

# A21. HTML 注入の escape 健全性 (生 markup が構造へ漏れない)
cp "$BASE" "$TMP/a21.yaml"; yq -i '.decision.statement = "<script>alert(1)</script>確定する"' "$TMP/a21.yaml"
bash "$ASM" "$TMP/a21.yaml" "$TMP/a21.html" >/dev/null 2>&1
if grep -qE '<script>alert|<(lt|gt|quot);' "$TMP/a21.html"; then ng "A21 escape 破綻 (生 markup か back-ref 化け)"
elif grep -q '&lt;script&gt;alert' "$TMP/a21.html"; then ok "A21 HTML 注入を正規 entity に escape"
else ng "A21 正規 entity &lt;script&gt; が出ていない"; fi

# === folio-tv5: verify_cross_doc_refs の collation 統一 (LC_ALL=C) — ★latent 防御 hardening (red→green ではない) ===
# ★正直な性質付け (l93 self-review で確認): この fix は *latent な防御 hardening* であり TDD の red→green ではない。
#   旧コードは 1 run 内で exp_k/act_k の sort -u も dangling の comm も *全て同一の ambient locale* で実行するため
#   内部一貫しており、 mixed-case key を入れても両辺が同じ照合で並び set_eq の == は常に一致・comm も sort と同照合で
#   整合する。 ゆえに verify-adr の public path 経由では旧コードでも mixed-case key は PASS し、 LC_ALL=C 統一の有無に
#   *依らず* 緑になる (TV5-1/TV5-2 はこの不変を smoke で固定するだけで red→green の証明ではない)。
#   genuine な false FAIL (comm: input is not in sorted order) は sort と comm が *異なる* 照合を使う場合のみ生じる
#   = 旧コードが起こさない条件。 よって:
#     - TV5-1/TV5-2 = mixed-case の非回帰 smoke (旧コードでも緑・fix の red→green 主張はしない)。
#     - TV5-3 = origin/main の旧 verify-common.sh を read-only で取り出した differential。 旧=新=PASS を明示記録し
#              「fix は latent hardening で現行 locale では旧コードも PASS」を assert で固定 (将来 false 主張を防ぐ)。
#     - TV5-4 = fix が pin する collation *primitive* の red→green: un-pinned な sort/comm 照合不整合は genuine に
#              "input is not in sorted order" で error (red)、 LC_ALL=C 統一なら clean (green)。 verify-side の照合規律が
#              機構として効く下限を primitive で固定する (public path では発火しない条件を直接 exercise)。
# C 照合 (F=70 < a=97 → FR2,FR3,ax-low-9) と en_US.UTF-8 照合 (case-insensitive a<f → ax-low-9,FR2,FR3) で並びが逆になる
# mixed-case keys を両辺 (ADR justifies + 参照先 SRS req ids) へ入れる。
cp "$SRS" "$TMP/srs-mixed.srs.yaml"
yq -i '.requirements += [{"id":"ax-low-9"}]' "$TMP/srs-mixed.srs.yaml"
cp "$BASE" "$TMP/tv5.yaml"
yq -i '.cross_doc.srs_contract = "srs-mixed.srs.yaml"' "$TMP/tv5.yaml"
yq -i '.decision.justifies += [{"req":"ax-low-9","role":"claim","note":"collation テスト用の低位 key"}]' "$TMP/tv5.yaml"
bash "$ASM" "$TMP/tv5.yaml" "$TMP/tv5.html" >/dev/null 2>&1
expect_verify_pass "TV5-1 mixed-case cross-doc key (FR*/ax-low-9) で verify PASS (非回帰 smoke・red→green ではない)" "$TMP/tv5.yaml" "$TMP/tv5.html"
# TV5-2. 同 mixed-case を LC_ALL=C 外側環境でも PASS (内部 LC_ALL=C 統一ゆえ外側 locale に依らず一貫・非回帰 smoke)。
if LC_ALL=C bash "$VER" "$TMP/tv5.yaml" "$TMP/tv5.html" >/dev/null 2>&1; then ok "TV5-2 mixed-case key が LC_ALL=C 外側環境でも verify PASS (非回帰 smoke)"; else ng "TV5-2 LC_ALL=C 外側で mixed-case verify FAIL"; fi
# TV5-3. ★differential (origin/main の旧 verify-common.sh vs 現行): 同一 fixture で旧=新=PASS を明示記録する。
#   旧コードを read-only で取り出し、 source 差し替えで同じ verify を回す。 旧でも PASS する = fix が latent hardening で
#   ある証拠 (red→green でなく無害な堅牢化)。 origin/main が取れない環境では SKIP (worktree 外で fetch 不可なら honest skip)。
TV5_OLD="$TMP/verify-common.old.sh"
if git -C "$SCRIPT_DIR" show origin/main:.claude-plugin/design-system/generator/lib/verify-common.sh > "$TV5_OLD" 2>/dev/null && [[ -s "$TV5_OLD" ]]; then
  # 旧 verify-common.sh を read-only で取り出し、 lib + verify-adr.sh だけの最小 swap dir で source 差し替えする。
  # verify は read-only ゆえ fix の有無で artifact (HTML) は byte-identical = 現行 dir で組んだ $TMP/tv5.html を再利用し
  #   旧 verify-common.sh だけで verify を回す (assemble を temp で再走しないので srs.css 等の asset path に依存しない)。
  #   cross_doc は contract ($TMP/tv5.yaml) の dir 相対で解決され srs-mixed.srs.yaml は $TMP に在るため正しく辿れる。
  TV5_GEN="$TMP/gen-old"; mkdir -p "$TV5_GEN"
  cp -r "$SCRIPT_DIR/lib" "$SCRIPT_DIR/verify-adr.sh" "$TV5_GEN/" 2>/dev/null
  cp "$TV5_OLD" "$TV5_GEN/lib/verify-common.sh"
  if bash "$TV5_GEN/verify-adr.sh" "$TMP/tv5.yaml" "$TMP/tv5.html" >/dev/null 2>&1; then
    ok "TV5-3 ★differential: 旧 verify-common.sh (origin/main) も mixed-case key で PASS = fix は latent hardening (red→green ではない・正直に固定)"
  else
    ng "TV5-3 旧 verify-common.sh が mixed-case で FAIL (= genuine red→green であった。 性質付けを red→green へ訂正せよ)"
  fi
else
  ok "TV5-3 (SKIP) origin/main の旧 verify-common.sh を取得できず differential を省略 (worktree 外・fetch 不可な honest skip)"
fi
# TV5-4. ★primitive の red→green: fix が pin する sort/comm 照合規律を直接 exercise。 旧コードは public path で
#   この不整合を起こさない (1 run = 同一 locale) ため verify 経由では発火しないが、 「照合を揃えなければ comm は
#   genuine に壊れる」機構を primitive で固定する。 un-pinned (comm の locale != sort の locale) なら
#   "input is not in sorted order" で error (red)、 LC_ALL=C 統一なら clean (green)。
printf 'FR2\nFR3\nax-low-9\n' > "$TMP/tv5-keys.txt"; printf 'FR2\nFR3\nax-low-9\nZZZ\n' > "$TMP/tv5-keys2.txt"
# ★locale guard (TV5-3 の honest-skip と同型): red 側は en_US.UTF-8 の case-insensitive 照合が LC_ALL=C と食い違うことに
#   依存する。 en_US.UTF-8 未 install の最小環境では glibc が C へ fallback し comm が error せず tv5_unpinned_err が空 →
#   guard が偽 → 本 fix と無関係の false-FAIL になる。 locale 在不在で skip し portability を保つ。
if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
  tv5_unpinned_err="$(LC_ALL=en_US.UTF-8 comm -23 <(LC_ALL=C sort -u "$TMP/tv5-keys.txt") <(LC_ALL=C sort -u "$TMP/tv5-keys2.txt") 2>&1 >/dev/null)"
  tv5_pinned_err="$(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$TMP/tv5-keys.txt") <(LC_ALL=C sort -u "$TMP/tv5-keys2.txt") 2>&1 >/dev/null)"
  if [[ "$tv5_unpinned_err" == *"not in sorted order"* && -z "$tv5_pinned_err" ]]; then
    ok "TV5-4 ★primitive: 照合不整合 (comm!=sort locale) は genuine error・LC_ALL=C 統一は clean (fix の規律機構を固定)"
  else
    ng "TV5-4 ★primitive red→green 不成立 (un-pinned err='$tv5_unpinned_err' / pinned err='$tv5_pinned_err')"
  fi
else
  ok "TV5-4 (SKIP) en_US.UTF-8 locale 不在ゆえ collation-mismatch primitive を exercise 不可 (honest skip・TV5-3 と同型)"
fi


# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
cp "$TMP/base-filled.html" "$TMP/r7a1.html"; perl -0777 -i -pe 's{</body>}{<p class="dec-why">正反対の判断根拠(捏造)</p></body>}' "$TMP/r7a1.html"
expect_verify_fail_filled "R7-adr-a ★dec-why additive (★blocker: 判断の根拠) を dec-why 占有==1 で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a1.html"
cp "$TMP/base-filled.html" "$TMP/r7a2.html"; perl -0777 -i -pe 's{</body>}{<p class="dec-plain">偽の平易な判断(捏造)</p></body>}' "$TMP/r7a2.html"
expect_verify_fail_filled "R7-adr-b ★dec-plain additive (★blocker: 平易な判断=北極星読者の第一面) を dec-plain 占有==1 で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a2.html"
cp "$TMP/base-filled.html" "$TMP/r7a3.html"; perl -0777 -i -pe 's{</body>}{<p class="opt-plain">偽の平易な選択肢(捏造)</p></body>}' "$TMP/r7a3.html"
expect_verify_fail_filled "R7-adr-c ★opt-plain additive を占有==|options| で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a3.html"
cp "$TMP/base-filled.html" "$TMP/r7a4.html"; perl -0777 -i -pe 's{</body>}{<div data-component="testcase-card">foreign dc(捏造)</div></body>}' "$TMP/r7a4.html"
expect_verify_fail_filled "R7-adr-d ★foreign dc を機械的網羅で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a4.html"
cp "$TMP/base-filled.html" "$TMP/r7a5.html"; perl -0777 -i -pe 's{</body>}{<span class="term">偽バッジ(捏造)</span></body>}' "$TMP/r7a5.html"
expect_verify_fail_filled "R7-adr-e ★bare term を term==plain-language-term-inline で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a5.html"
cp "$TMP/base-filled.html" "$TMP/r7a6.html"; perl -0777 -i -pe 's{</body>}{<p style="display:none">genuine 隠蔽(捏造)</p></body>}' "$TMP/r7a6.html"
expect_verify_fail_filled "R7-adr-f ★display:none 隠蔽を display-state guard で捕捉" "$BASE_PROSE" "$BASE" "$TMP/r7a6.html"

# ===== folio-wq4 回帰: make_body substrate + occupancy global pin が non-SRS pack (追加 home 0) でも効く (core ゆえ全 pack) =====
cp "$TMP/base-filled.html" "$TMP/wq4adr1.html"; perl -0777 -i -pe 's{</body>}{<div><style>.x{}</style><span class="role">偽承認者(style同居)</span></div></body>}' "$TMP/wq4adr1.html"
expect_verify_fail_filled "WQ4-adr-a ★<style>同居行の偽 role を make_body 中身空化で surface→global role 占有が捕捉 (旧 sed は素通り)" "$BASE_PROSE" "$BASE" "$TMP/wq4adr1.html"
cp "$TMP/base-filled.html" "$TMP/wq4adr2.html"; perl -0777 -i -pe 's{</body>}{<span class="role">偽承認者(scope外)</span></body>}' "$TMP/wq4adr2.html"
expect_verify_fail_filled "WQ4-adr-b ★行 scope 外の偽 role を global 占有 (==|approval|・追加 0) で捕捉" "$BASE_PROSE" "$BASE" "$TMP/wq4adr2.html"
cp "$TMP/base-filled.html" "$TMP/wq4adr3.html"; perl -0777 -i -pe 's{</body>}{<span class="en">FAKE-EN(scope外)</span></body>}' "$TMP/wq4adr3.html"
expect_verify_fail_filled "WQ4-adr-c ★行 scope 外の偽 en を global 占有 (==|非空 en|・追加 0) で捕捉" "$BASE_PROSE" "$BASE" "$TMP/wq4adr3.html"

echo
echo "adversarial: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]] || exit 1
