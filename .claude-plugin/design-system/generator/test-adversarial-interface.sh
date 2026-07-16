#!/usr/bin/env bash
# test-adversarial-interface.sh — interface-pack floor の敵対検査 (verify-interface.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-interface.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (floor 三本柱): ① 照会グラフ (偽 FR・role 偽装・count・per-card relocation・可視コード捏造・href deep-link 分類) /
#   ② navigable id アンカー (削除/改名) / ③ census-count (件数・空 block red pin) / band 数詞 (abort + HTML fidelity) /
#   op-error-chip (fragment/relocation/ec-code) / ent-chip (dangling/href/name/relocation) / 可視テキスト捏造 /
#   direction 反転 / cross-doc 可視 echo (×2 doc_id) / core chrome / CJK 空白 / prose 注入 / binding 予約 /
#   floor 単独 GREEN 禁止 / repro-build conformance を *全捕捉*。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-interface.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-appointment.interface.yaml"
MANIFEST="$HERE/prose/clinic-appointment.interface.prose.yaml"
ASSEMBLE="$HERE/assemble-interface.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-interface.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm (verify_repro_build) は verify-*.sh 既定 ON。 bulk case は honest skip で速度維持し、 conformance pin (末尾) だけ arm ON 実走。
export SKIP_REPRO="${SKIP_REPRO:-1}"
# gate F (playwright visual・folio-vuf A) も floor-adversarial では skip (重い render を外す・SKIP_REPRO と同型)。
export SKIP_RENDER="${SKIP_RENDER:-1}"
source "$HERE/lib/test-repro-pins.sh"
expect_fail() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
mut() { local n="$1" prog="$2"; local m="$TMP/m$n.html"; perl -0777 -pe "$prog" "$GOOD" > "$m"; printf '%s' "$m"; }
# expect_abort <label> <contract.yaml> [expected_stderr_substring] — assemble 段の contract fail-closed (folio-bhe)。
expect_abort() {
  local label="$1" c="$2" want="${3:-}" out rc
  total=$((total+1))
  out="$("$ASSEMBLE" "$c" 2>&1 >/dev/null)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  [SLIP] $label — assemble が abort せず生成した (exit 0)"
  elif [[ -n "$want" && "$out" != *"$want"* ]]; then
    echo "  [SLIP] $label — abort したが理由が想定外 (期待 '$want' / 実: $(printf '%s' "$out" | tail -1))"
  else
    echo "  [OK]   $label — 生成前 abort"; pass=$((pass+1))
  fi
}
# expect_vfail_contract <label> <contract.yaml> <html> [fail-substr] — 改竄 contract を verify へ渡し FAIL を要求 (verify 側独立 pin)。
expect_vfail_contract() {
  local label="$1" c="$2" html="$3" want="${4:-}" out rc
  total=$((total+1))
  out="$("$VERIFY" --filled "$MANIFEST" "$c" "$html" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  [SLIP] $label — verify が通過させた (exit 0)"
  elif [[ -n "$want" && "$out" != *"$want"* ]]; then
    echo "  [SLIP] $label — FAIL したが理由が想定外 (期待 '$want')"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
# if_base <dst.yaml> — contract を TMP へコピーし、 cross_doc が相対参照する SRS / datamodel contract も同じ dir へコピーする
#   (assemble-interface のパス解決は CONTRACT_DIR 相対の素朴連結 = 兄弟配置が前提)。
if_base() {
  local d; d="$(dirname "$1")"
  cp "$CONTRACT" "$1"
  cp "$HERE/contract/clinic-appointment.srs.yaml" "$d/"
  cp "$HERE/contract/clinic-appointment.datamodel.yaml" "$d/"
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi
total=$((total+1))
if_base "$TMP/base-sanity.yaml"
if "$ASSEMBLE" "$TMP/base-sanity.yaml" >/dev/null 2>&1; then
  echo "  [OK]   baseline if_base コピーは assemble PASS"; pass=$((pass+1))
else
  echo "  [SLIP] if_base コピーが assemble FAIL (helper 前提崩壊)"; fi

# --- ③ census-count (件数) ---
expect_fail "operation-card マーカー削除 (census)"    "$(mut 1 's{<article data-component="operation-card" id="op-check-availability">}{<article data-component="operation-XXX" id="op-check-availability">}')"
expect_fail "op-io-row マーカー削除 (census)"          "$(mut 2 's{<div data-component="op-io-row"><div class="io-cell req">}{<div data-component="op-io-XXX"><div class="io-cell req">}')"
expect_fail "error-card マーカー削除 (census)"         "$(mut 3 's{<article data-component="error-card" id="error-E-OUT">}{<article data-component="error-XXX" id="error-E-OUT">}')"
expect_fail "external-row マーカー削除 (census)"       "$(mut 4 's{<article data-component="external-row" class="dir-in" id="ext-fetch-calendar">}{<article data-component="external-XXX" class="dir-in" id="ext-fetch-calendar">}')"
expect_fail "cross-cutting-card マーカー削除 (census)" "$(mut 5 's{<div data-component="cross-cutting-card" id="cc-CC-2">}{<div data-component="cc-XXX" id="cc-CC-2">}')"
expect_fail "op-error-chip マーカー削除 (census)"      "$(mut 6 's{<a class="op-error-chip" data-component="op-error-chip" href="#error-E-MISMATCH">}{<a class="op-error-chip" data-component="op-error-XXX" href="#error-E-MISMATCH">}')"
expect_fail "ent-chip マーカー削除 (census)"           "$(mut 7 's{<a class="ent-chip" href="clinic-appointment.datamodel.html#entity-reminder-notification">}{<a class="ent-XXX" href="clinic-appointment.datamodel.html#entity-reminder-notification">}')"
# ★census red pin: 空 operation-card block を追加注入 (件数 5→6・id anchor も崩す)
expect_fail "census red pin: 偽 operation-card block 追加注入" "$(mut 8 's{</div>\n<footer}{<article data-component="operation-card" id="op-fake"></article></div>\n<footer}')"

# --- ③b band 見出し (folio-bhe: instance hardcode 封鎖 + 数詞 fabrication) ---
if_base "$TMP/bh1.yaml"; yq -i 'del(.chapters.operations_band)' "$TMP/bh1.yaml"
expect_abort "BH1 ★chapters.operations_band 欠落を abort" "$TMP/bh1.yaml" "chapters.operations_band 欠落"
if_base "$TMP/bh2.yaml"; yq -i 'del(.chapters.errors_band)' "$TMP/bh2.yaml"
expect_abort "BH2 ★chapters.errors_band 欠落を abort" "$TMP/bh2.yaml" "chapters.errors_band 欠落"
if_base "$TMP/bh2b.yaml"; yq -i 'del(.chapters.external_band)' "$TMP/bh2b.yaml"
expect_abort "BH2b ★chapters.external_band 欠落を abort" "$TMP/bh2b.yaml" "chapters.external_band 欠落"
if_base "$TMP/bh3.yaml"; yq -i '.chapters.operations_band = "6 つの操作で受け付ける"' "$TMP/bh3.yaml"
expect_abort "BH3 ★operations_band 数詞 6≠実件数 5 を abort (件数 fabrication)" "$TMP/bh3.yaml" "実件数 5 と不一致"
if_base "$TMP/bh4.yaml"; yq -i '.chapters.operations_band = "５ つの操作で受け付ける"' "$TMP/bh4.yaml"
expect_abort "BH4 ★operations_band 全角数字 (数詞照合回避) を abort" "$TMP/bh4.yaml" "全角数字"
if_base "$TMP/bh5.yaml"; yq -i '.chapters.operations_band = "五 つの操作で受け付ける"' "$TMP/bh5.yaml"
expect_abort "BH5 ★operations_band 漢数字 (ASCII 照合回避) を数詞必須で abort" "$TMP/bh5.yaml" "ASCII 数字の件数"
if_base "$TMP/bh6.yaml"; yq -i '.chapters.errors_band = "5 通りの断り方を約束する"' "$TMP/bh6.yaml"
expect_abort "BH6 ★errors_band 数詞 5≠実件数 4 を abort" "$TMP/bh6.yaml" "実件数 4 と不一致"
if_base "$TMP/bh6b.yaml"; yq -i '.chapters.external_band = "3 つの外部連携で外とつながる"' "$TMP/bh6b.yaml"
expect_abort "BH6b ★external_band 数詞 3≠実件数 2 を abort" "$TMP/bh6b.yaml" "実件数 2 と不一致"
# HTML band h2 改竄 (contract は正) → verify FAIL
expect_fail "BH7 ★HTML band h2 件数改竄 (5→6 つの操作)" "$(mut 9 's{<h2>5 つの操作で受け付ける}{<h2>6 つの操作で受け付ける}')"
expect_fail "BH8 ★HTML band h2 pack 固定文言改竄 (横断→会計の決まり)" "$(mut 10 's{<h2>どの操作にも共通してかかる決まり</h2>}{<h2>どの会計にも共通してかかる決まり</h2>}')"
# verify 側独立数詞 pin (両側辻褄合わせ)
if_base "$TMP/bh9.yaml"; yq -i '.chapters.operations_band = "6 つの操作で受け付ける"' "$TMP/bh9.yaml"
expect_vfail_contract "BH9 ★両側辻褄合わせ (contract+HTML=6) を verify 独立数詞 pin で捕捉" "$TMP/bh9.yaml" \
  "$(mut 11 's{<h2>5 つの操作で受け付ける}{<h2>6 つの操作で受け付ける}')" "expected 5, got 6"
# verify 側 非 ASCII 拒否の肯定形ブランチを独立 pin (representation-evasion・assemble を経ない --filled 直検では
# assemble 側 BH5 abort が走らず verify 側が唯一の防御 = BH10 datamodel と同型)
if_base "$TMP/bh10.yaml"; yq -i '.chapters.operations_band = "五 つの操作で受け付ける"' "$TMP/bh10.yaml"
expect_vfail_contract "BH10 ★両側辻褄合わせ (contract+HTML=漢数字 五) を verify 側 ASCII 必須肯定形で捕捉" "$TMP/bh10.yaml" \
  "$(mut 12 's{<h2>5 つの操作で受け付ける}{<h2>五 つの操作で受け付ける}')" "ASCII 数詞なし"

# --- ★binding 予約席 (案A・非 null → 生成前 abort) ---
if_base "$TMP/bind.yaml"; yq -i '.binding = "http/json"' "$TMP/bind.yaml"
expect_abort "BIND ★binding non-null を生成前 abort (fail-closed 予約)" "$TMP/bind.yaml" "binding が non-null"
# verify 側予約席も独立 pin (両側 pin・band 数詞の assemble/verify 二重化と同型・ceiling round-1 処方)
if_base "$TMP/bindv.yaml"; yq -i '.binding = "http/json"' "$TMP/bindv.yaml"
expect_vfail_contract "BINDV ★binding non-null を verify 側予約席 pin でも捕捉" "$TMP/bindv.yaml" "$GOOD" "got http/json"

# --- ★per-op noerror relocation (件数保存ゆえ count-only 層を素通し・per-op 束縛が単独で捕捉。 SKIP_REPRO=1 前提・ceiling round-1 処方) ---
# op-noerror span を cancel-appointment (errors 0) から request-appointment (errors 3) へ移設 (件数 2 保持)。
#   「断り 3 種ある操作に『断りなし』を表示」= 境界の中核捏造を per-op noerror 束縛が単独で FAIL させる。
expect_fail "op-noerror relocation (cancel→request へ移設・件数 2 保持)" "$(mut 92 'my ($no)=/(<span class="op-noerror">.*?<\/span>)/s; s{(\bid="op-cancel-appointment">.*?<span class="slot-lab">断られ方</span>)\Q$no\E}{$1}s; s{(\bid="op-request-appointment">.*?<span class="slot-lab">断られ方</span>)}{$1$no}s;')"

# --- ② navigable id アンカー ---
expect_fail "operation anchor 改名 (op-check-in→op-FAKE)"  "$(mut 13 's{id="op-check-in"}{id="op-FAKE"}')"
expect_fail "error anchor 削除"                            "$(mut 14 's{ id="error-E-FULL"}{}')"
expect_fail "external anchor 改名"                         "$(mut 15 's{id="ext-send-reminder"}{id="ext-XXX"}')"
expect_fail "cross-cutting anchor 改名"                    "$(mut 16 's{id="cc-CC-1"}{id="cc-XXX"}')"
expect_fail "principle terminal anchor 改名"               "$(mut 17 's{id="principle-PRIN-HONEST-BOUNDARY"}{id="principle-FAKE"}')"

# --- ① 照会グラフ (cross-doc 前方照会の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 20 's{data-if-ref="FR7" data-if-role="claim"}{data-if-ref="FR99" data-if-role="claim"}')"
expect_fail "SRS role 意味偽装 (claim→rationale)"    "$(mut 21 's{data-if-ref="FR3" data-if-role="claim"}{data-if-ref="FR3" data-if-role="rationale"}')"
expect_fail "SRS ref 削除 (count mismatch)"           "$(mut 22 's{<a class="srs-badge" href="clinic-appointment.srs.html#FR2" data-if-ref="FR2" data-if-role="claim">FR2</a>}{}')"
# per-card relocation (op 間で FR1↔FR7 を check-availability↔check-in・global set/count/pair 不変ゆえ per-card のみ捕捉)
expect_fail "card 間 ref relocation (check-availability FR1 ↔ check-in FR7)" "$(mut 23 's{href="clinic-appointment.srs.html#FR1" data-if-ref="FR1" data-if-role="claim">FR1</a>}{__SWP__}g; s{href="clinic-appointment.srs.html#FR7" data-if-ref="FR7" data-if-role="claim">FR7</a>}{href="clinic-appointment.srs.html#FR1" data-if-ref="FR1" data-if-role="claim">FR1</a>}g; s{__SWP__}{href="clinic-appointment.srs.html#FR7" data-if-ref="FR7" data-if-role="claim">FR7</a>}g')"
# 可視コード捏造 (data-if-ref intact・可視だけ捏造)
expect_fail "可視 srs-badge コード捏造 (FR4→FR99・data-if-ref intact)" "$(mut 24 's{data-if-ref="FR4" data-if-role="claim">FR4</a>}{data-if-ref="FR4" data-if-role="claim">FR99</a>}')"
# href deep-link 改竄 (fragment swap・data-if-ref intact)
expect_fail "href anchor swap (#FR2→#FR99・data-if-ref=FR2 intact)"   "$(mut 25 's{href="clinic-appointment.srs.html#FR2" data-if-ref="FR2"}{href="clinic-appointment.srs.html#FR99" data-if-ref="FR2"}')"
expect_fail "href 外部 host 注入 (SRS→https://evil・属性 intact)"      "$(mut 26 's{href="clinic-appointment.srs.html#FR1" data-if-ref="FR1"}{href="https://evil.example#FR1" data-if-ref="FR1"}')"
# ★CON/AC deep-link 分類の敵対: CON1 badge に fragment #CON1 を持たせる (文書単位規約違反) → href set 不一致
expect_fail "CON1 badge に fragment 付与 (文書単位規約違反・deep-link 分類 pin)" "$(mut 27 's{<a class="srs-badge" href="clinic-appointment.srs.html" title="[^"]*" data-if-ref="CON1"}{<a class="srs-badge" href="clinic-appointment.srs.html#CON1" data-if-ref="CON1"}g')"
# ★FR badge から fragment を除去 (文書単位化・FR は fragment 必須) → href set 不一致
expect_fail "FR2 badge の fragment 除去 (FR は fragment 必須・deep-link 分類 pin)" "$(mut 28 's{href="clinic-appointment.srs.html#FR2" data-if-ref="FR2"}{href="clinic-appointment.srs.html" data-if-ref="FR2"}')"

# --- ★op-error-chip (§2→§3 内部アンカー) ---
expect_fail "op-error-chip fragment 改竄 (#error-E-FULL→#error-E-XXX・dangling)" "$(mut 30 's{href="#error-E-FULL">満枠 <span class="ec-code">E-FULL}{href="#error-E-XXX">満枠 <span class="ec-code">E-FULL}')"
expect_fail "op-error-chip 可視 ec-code 捏造 (E-FULL→E-XXX・href intact)" "$(mut 31 's{href="#error-E-FULL">満枠 <span class="ec-code">E-FULL</span>}{href="#error-E-FULL">満枠 <span class="ec-code">E-XXX</span>}')"
# op 間 chip relocation: request-appointment の E-FULL chip を change-appointment へ移す (件数保存) → per-op 束縛が捕捉。
# request(E-FULL,E-OUT,E-CONSENT) と change(E-FULL,E-OUT) で E-CONSENT を change へ増設 + request から除去 (Σ=6 保存)。
expect_fail "op 間 error-chip relocation (E-CONSENT を request→change・Σ 保存)" "$(mut 32 's{<a class="op-error-chip" data-component="op-error-chip" href="#error-E-CONSENT">同意なし <span class="ec-code">E-CONSENT</span></a></div>\n<div class="opc-slot"><span class="slot-lab">使う情報</span><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-patient">患者}{</div>\n<div class="opc-slot"><span class="slot-lab">使う情報</span><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-patient">患者}; s{<a class="op-error-chip" data-component="op-error-chip" href="#error-E-OUT">枠の外 <span class="ec-code">E-OUT</span></a></div>\n<div class="opc-slot"><span class="slot-lab">使う情報</span><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-appointment">予約 <span class="en">appointment</span></a><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-appointment-slot">診療枠 <span class="en">appointment-slot</span></a></div>\n<div class="opc-slot refs-row"><span class="refs-lab">照会 \(SRS\)</span><a class="srs-badge" href="clinic-appointment.srs.html#FR5" data-if-ref="FR5" data-if-role="claim">FR5</a></div>\n<p class="opc-plain" data-prose-slot="plain" data-slot-id="plain-change-appointment">}{<a class="op-error-chip" data-component="op-error-chip" href="#error-E-OUT">枠の外 <span class="ec-code">E-OUT</span></a><a class="op-error-chip" data-component="op-error-chip" href="#error-E-CONSENT">同意なし <span class="ec-code">E-CONSENT</span></a></div>\n<div class="opc-slot"><span class="slot-lab">使う情報</span><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-appointment">予約 <span class="en">appointment</span></a><a class="ent-chip" href="clinic-appointment.datamodel.html#entity-appointment-slot">診療枠 <span class="en">appointment-slot</span></a></div>\n<div class="opc-slot refs-row"><span class="refs-lab">照会 (SRS)</span><a class="srs-badge" href="clinic-appointment.srs.html#FR5" data-if-ref="FR5" data-if-role="claim">FR5</a></div>\n<p class="opc-plain" data-prose-slot="plain" data-slot-id="plain-change-appointment">}')"

# --- ★ent-chip (uses.entities → datamodel entity への presentational deep-link) ---
expect_fail "ent-chip 偽 entity (dangling・datamodel に無い entity-ghost)" "$(mut 33 's{href="clinic-appointment.datamodel.html#entity-patient">患者 <span class="en">patient}{href="clinic-appointment.datamodel.html#entity-ghost">患者 <span class="en">ghost}')"
expect_fail "ent-chip href base swap (datamodel→外部 host・fragment intact)" "$(mut 34 's{href="clinic-appointment.datamodel.html#entity-appointment-slot">診療枠}{href="https://evil.example#entity-appointment-slot">診療枠}g')"
expect_fail "ent-chip 可視 name 捏造 (診療枠→捏造名・id/en intact)" "$(mut 35 's{#entity-clinic-calendar">診療カレンダー <span class="en">clinic-calendar}{#entity-clinic-calendar">捏造カレンダー <span class="en">clinic-calendar}')"
expect_fail "ent-chip 可視 en 捏造 (appointment-slot→捏造・fragment intact)" "$(mut 36 's{#entity-appointment-slot">診療枠 <span class="en">appointment-slot</span>}{#entity-appointment-slot">診療枠 <span class="en">XXX</span>}')"

# --- cross-doc 可視 echo (表紙 ref-chip・×2 doc_id) ---
expect_fail "ref-chip srs_doc_id 捏造" "$(mut 40 's{<b>SRS-CLINIC-APPT</b>の要件}{<b>FAKE-SRS</b>の要件}')"
expect_fail "ref-chip datamodel_doc_id 捏造" "$(mut 41 's{<b>DM-CLINIC-APPT</b>の情報}{<b>FAKE-DM</b>の情報}')"

# --- 可視テキスト fidelity (属性 intact のまま可視だけ捏造) ---
expect_fail "opc-name 捏造"        "$(mut 50 's{<span class="opc-name">空きを尋ねる</span>}{<span class="opc-name">捏造操作</span>}')"
expect_fail "opc-actor 捏造"       "$(mut 51 's{<span class="a-lab">使う人</span>患者・受付スタッフ</span>}{<span class="a-lab">使う人</span>でたらめな人</span>}')"
expect_fail "io-val request 捏造"  "$(mut 52 's{<span class="io-val">希望する日時の範囲</span>}{<span class="io-val">でたらめな入力</span>}')"
expect_fail "io-val response 捏造" "$(mut 53 's{変更後の予約 \(元の枠は空きに戻る\)}{でたらめな出力}')"
expect_fail "erc-name 捏造"        "$(mut 54 's{<span class="erc-name">満枠</span>}{<span class="erc-name">捏造エラー</span>}')"
expect_fail "erc-when 捏造"        "$(mut 55 's{すでに埋まった枠に申し込もうとした}{でたらめな状況}')"
expect_fail "erc-promise 捏造"     "$(mut 56 's{受け付けず、 受診できる日時を案内する}{でたらめな断り}')"
expect_fail "exr-name 捏造"        "$(mut 57 's{<span class="exr-name">リマインドを送る</span>}{<span class="exr-name">捏造連携</span>}')"
expect_fail "exr-partner 捏造"     "$(mut 58 's{<span class="p-lab">相手</span>通知サービス</span>}{<span class="p-lab">相手</span>でたらめな相手</span>}')"
expect_fail "exr-promise 捏造"     "$(mut 59 's{診療枠と休診日は必ず診療カレンダーから受け取り}{でたらめな約束で受け取り}')"
expect_fail "exr-dir 反転 (out→in・class intact)" "$(mut 60 's{<span class="exr-dir out"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7M8 7h9v9"/></svg>送る \(out\)</span>}{<span class="exr-dir out"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7M8 7h9v9"/></svg>受け取る (in)</span>}')"
expect_fail "ccc-rule 捏造"        "$(mut 61 's{患者情報は同意を得たあとにだけ受け取り、 目的の外に使わない。}{でたらめな横断規則。}')"
expect_fail "principle pt-text 捏造" "$(mut 62 's{迷ったら隠さず断る側に倒す。}{迷ったら黙って受ける。}')"
expect_fail "context problem 捏造" "$(mut 63 's{窓口の約束が曖昧だと}{窓口の約束は完璧なので}')"
expect_fail "scope_note 捏造"      "$(mut 64 's{この文書は「窓口の約束 \(何を渡すと何が起き、 どう断られるか\)」だけを決める。}{この文書は全部を決める。}')"

# --- ★per-external 方向 relocation (out↔in を順序保存で入替・class 件数保存ゆえ per-external 束縛が単独で捕捉) ---
# send-reminder(dir-out) と fetch-calendar(dir-in) の class を入替える (dir-out/dir-in 各 1 件保存)。
expect_fail "方向 relocation (send-reminder↔fetch-calendar dir class 入替・件数保存)" "$(mut 65 's{<article data-component="external-row" class="dir-out" id="ext-send-reminder">}{<article data-component="external-row" class="dir-XX" id="ext-send-reminder">}; s{<article data-component="external-row" class="dir-in" id="ext-fetch-calendar">}{<article data-component="external-row" class="dir-out" id="ext-fetch-calendar">}; s{<article data-component="external-row" class="dir-XX" id="ext-send-reminder">}{<article data-component="external-row" class="dir-in" id="ext-send-reminder">}')"

# --- 横展開: CJK inline 強調の空白規律 ---
# CC-2 rule は term マークが付かない (操作 の初出は CC-1 で消費済) ゆえ literal が HTML に intact。 CJK+空白+<b> を注入。
expect_fail "CJK 隣接の <b> 前空白 注入"  "$(mut 70 's{<p class="ccc-rule">患者情報は同意}{<p class="ccc-rule">患者情報 <b>は</b>同意}')"

# --- cover-meta / core chrome ---
expect_fail "cover-meta 構成 捏造"           "$(mut 80 's{(<span class="k">構成</span><span class="v">)[^<]+}{${1}捏造構成}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 81 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "glossary def 捏造 (core-chrome)" "$(mut 82 's{窓口に頼める 1 つのお願いの単位。 何を渡すと何が返るかを 1 つずつ約束する。}{でたらめな定義。}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 90 's{(data-slot-id="plain-check-availability">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 91 's{(data-slot-id="cover-summary">)[^<]+(</p>)}{${1}${2}}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
# ★bare token grep にしない (folio-vxpc errata): verify-*.sh の統一 sentinel は「GREEN ではない」と *否定*
#   するために GREEN の語を含む。 bare `grep -q 'GREEN'` はその否定文にも lexical 衝突して恒真 [SLIP] となり、
#   本 suite が exit 1 へ飽和して **他の全 assert が exit-code 判定から不可視になる** (番人喪失 = fail-open)。
#   assert の意図「floor 単独 GREEN 禁止」は不変のまま、 GREEN を *主張* する行の検出へ精密化する (緩和ではない)。
#   精密化が番人を殺していないことは直下 2 本 (捏造の陽性対照 / 否定文の陰性対照) が実弾で pin する。
GREEN_CLAIM='RESULT:[^—]*GREEN|GREEN 認定|全 gate.*GREEN'
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -qE "$GREEN_CLAIM"; then
  echo "  [SLIP] verify が GREEN を主張 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 主張なし・CEILING=PENDING を強制"; pass=$((pass+1)); fi
# 陽性対照: 精密化しても本物の GREEN 捏造は殺せる (殺せないなら精密化でなく番人の喪失)。
total=$((total+1))
if printf '%s' "RESULT: GREEN (全 gate 通過)" | grep -qE "$GREEN_CLAIM"; then
  echo "  [OK]   MK 陽性対照: 本物の 'RESULT: GREEN' 捏造は今も主張パターンで殺せる"; pass=$((pass+1))
else
  echo "  [SLIP] MK 陽性対照 破れ: 主張パターンが 'RESULT: GREEN' 捏造を見逃す (緩和が番人を殺した)"; fi
# 陰性対照: 現行 sentinel の否定文を主張と誤検出しない (誤検出するなら上の番人は恒真 SLIP = 元の衝突の再生産)。
total=$((total+1))
if printf '%s' "RESULT: floor PASS (mode=artifact) — ただし CEILING=PENDING (*GREEN ではない*)" | grep -qE "$GREEN_CLAIM"; then
  echo "  [SLIP] MK 陰性対照 破れ: sentinel の否定文を主張と誤検出 (lexical 衝突の再生産)"
else
  echo "  [OK]   MK 陰性対照: sentinel の「GREEN ではない」否定文は主張と誤検出されない"; pass=$((pass+1)); fi

echo ""
echo "--- repro-build conformance (verify_repro_build): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" interface "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
