#!/usr/bin/env bash
# test-adversarial-changelog.sh — changelog-pack floor の敵対検査 (verify-changelog.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-changelog.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (worker brief): semver 順序改竄・version-keyed 構造改竄・偽 FR/ADR 照会 (dangling)・(ref,role) 意味偽装・
#   per-item relocation・最新版ハイライトの負の主張 (0 件→非0) 偽装・可視 echo 改竄を *全捕捉* (per-shape MK)。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-changelog.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-changelog.changelog.yaml"
MANIFEST="$HERE/prose/clinic-changelog.changelog.prose.yaml"
ASSEMBLE="$HERE/assemble-changelog.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-changelog.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm / gate F (playwright) は bulk case では honest skip (10分/suite を維持)。 conformance pin は末尾で明示解除。
export SKIP_REPRO="${SKIP_REPRO:-1}"
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

# baseline sanity
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- 件数 / 構造マーカー ---
expect_fail "changelog-entry マーカー削除 (件数)" "$(mut 1 's{<div data-component="changelog-entry" id="ver-1.2.0">}{<div data-component="changelog-XXX" id="ver-1.2.0">}')"
expect_fail "changelog-item マーカー削除 (件数)"  "$(mut 2 's{<li data-component="changelog-item" id="cl-C3">}{<li data-component="changelog-XXX" id="cl-C3">}')"
expect_fail "trace-row 削除 (件数)"               "$(mut 3 's{<tr data-component="trace-row"><td class="trc-id"><a href="#cl-C3">.*?</tr>\n}{}s')"

# --- ★semver 降順の決定的順序 (本 pack の核) ---
expect_fail "version バッジ捏造 (順序 pin)"        "$(mut 4 's{<span class="cl-ver-badge">v1.2.0</span>}{<span class="cl-ver-badge">v9.9.9</span>}')"
expect_fail "version バッジ入替 (v1.2.0↔v1.1.0・semver 昇順化)" "$(mut 5 's{<span class="cl-ver-badge">v1.2.0</span>}{<span class="cl-ver-badge">__SW__</span>}; s{<span class="cl-ver-badge">v1.1.0</span>}{<span class="cl-ver-badge">v1.2.0</span>}; s{<span class="cl-ver-badge">__SW__</span>}{<span class="cl-ver-badge">v1.1.0</span>}')"
expect_fail "version 日付 捏造"                    "$(mut 6 's{<span class="cl-ver-date">2026-06-20</span>}{<span class="cl-ver-date">2099-01-01</span>}')"

# --- ★最新版ハイライトの件数 (正の主張 + 負の主張「0 件」) ---
expect_fail "★ハイライト 0 件→非0 偽装 (負の主張 flip・変更 0→5)" "$(mut 7 's{(<span class="hl-count chg"><span class="hlc-label">変更</span><span class="hlc-n">)0}{${1}5}')"
expect_fail "ハイライト 件数 捏造 (修正 1→9)"       "$(mut 8 's{(<span class="hl-count fix"><span class="hlc-label">修正</span><span class="hlc-n">)1}{${1}9}')"
expect_fail "ハイライト hl-ver 捏造"                "$(mut 9 's{<span class="hl-ver">v1.2.0</span>}{<span class="hl-ver">v0.0.1</span>}')"

# --- ★cross-doc 後方照会の改竄 (本 pack の核) ---
expect_fail "偽 SRS 照会 (dangling・FR99)"          "$(mut 10 's{data-cl-srs-ref="FR3" data-cl-srs-role="claim"><span class="xref-code">FR3</span>}{data-cl-srs-ref="FR99" data-cl-srs-role="claim"><span class="xref-code">FR99</span>}')"
expect_fail "偽 ADR 照会 (dangling・ADR-FAKE)"      "$(mut 11 's{data-cl-adr-ref="ADR-CLINIC-0001" data-cl-adr-role="rationale"><span class="xref-code">ADR-CLINIC-0001</span>}{data-cl-adr-ref="ADR-FAKE" data-cl-adr-role="rationale"><span class="xref-code">ADR-FAKE</span>}')"
expect_fail "照会 role 意味偽装 (claim→rationale)"  "$(mut 12 's{data-cl-srs-ref="FR3" data-cl-srs-role="claim"}{data-cl-srs-ref="FR3" data-cl-srs-role="rationale"}')"
expect_fail "SRS 照会 ref 削除 (count mismatch)"    "$(mut 13 's{<a class="cl-ref" href="clinic-appointment.srs.html#FR3" data-cl-srs-ref="FR3" data-cl-srs-role="claim"><span class="xref-code">FR3</span><span class="cl-ref-label" data-srs-label-ref="FR3">[^<]*</span></a>}{}')"
expect_fail "xref-code 可視 vs attr desync"         "$(mut 14 's{(data-cl-srs-ref="FR3" data-cl-srs-role="claim"><span class="xref-code">)FR3(</span>)}{${1}FRX${2}}')"

# --- ★per-item card-keyed 束縛 (relocation・attr swap で global set 不変) ---
expect_fail "★card 間 SRS ref attr 入替 (C3↔C8・global set 不変) → card-keyed で捕捉" "$(mut 15 's{(id="cl-C3">.*?)data-cl-srs-ref="FR3"(.*?id="cl-C8">.*?)data-cl-srs-ref="FR2"}{${1}data-cl-srs-ref="FR2"${2}data-cl-srs-ref="FR3"}s')"
# ★item を別 category へ relocation (C4 を security→fixed へ移動・id 出現順不変) → 構造束縛のみが捕捉
expect_fail "★item 別 category relocation (C4 sec→fix・id順不変) → 構造束縛で捕捉" "$(mut 16 's{(id="cl-C3">.*?</li>\n)(</ul></div>\n<div class="cl-cat sec"><div class="cl-cat-head"><span class="cl-cat-label">セキュリティ</span></div>\n<ul class="cl-items">\n)(<li data-component="changelog-item" id="cl-C4">.*?</li>\n)}{${1}${3}${2}}s')"

# --- ★href 遷移先 fidelity ---
expect_fail "SRS href anchor swap (#FR3→#FR99・attr 温存)" "$(mut 17 's{(<a class="cl-ref" href="clinic-appointment.srs.html)#FR3(" data-cl-srs-ref="FR3")}{${1}#FR99${2}}')"
expect_fail "SRS href 外部 host swap"               "$(mut 18 's{<a class="cl-ref" href="clinic-appointment.srs.html#FR3"}{<a class="cl-ref" href="https://evil.example#FR3"}')"
expect_fail "ADR href swap (#decision→#evil)"       "$(mut 19 's{(<a class="cl-ref" href="clinic-double-booking.adr.html)#decision(" data-cl-adr-ref)}{${1}#evil${2}}')"

# --- ★照会ラベル併記 fidelity ---
expect_fail "SRS ラベル捏造 (非 SRS 由来)"          "$(mut 20 's{<span class="cl-ref-label" data-srs-label-ref="FR3">競合拒否</span>}{<span class="cl-ref-label" data-srs-label-ref="FR3">でたらめ機能</span>}')"
expect_fail "SRS ラベル swap (FR3→FR2 の正規ラベル)" "$(mut 21 's{<span class="cl-ref-label" data-srs-label-ref="FR3">競合拒否</span>}{<span class="cl-ref-label" data-srs-label-ref="FR3">予約受付</span>}')"
expect_fail "ADR ラベル title 捏造 (retitle drift・live-mirror 等値)" "$(mut 22 's{ADR: 同じ診療枠への二重予約を、 アプリ側の確認でなく}{ADR: 捏造された参照先タイトルで}')"

# --- ★可視テキスト fidelity (card-keyed) ---
expect_fail "item text 捏造 (数値改竄)"             "$(mut 23 's{まれに 2 件とも確定してしまう}{まれに 999 件とも確定してしまう}')"
expect_fail "cl-id 可視捏造"                        "$(mut 24 's{<span class="cl-id">C3</span>}{<span class="cl-id">CXX</span>}')"

# --- ★trace 表 fidelity ---
expect_fail "trace 区分捏造 (修正→でたらめ)"        "$(mut 25 's{<td class="trc-cat">修正</td>}{<td class="trc-cat">でたらめ区分</td>}')"
expect_fail "trace 版捏造"                          "$(mut 26 's{<td class="trc-ver">v1.2.0</td>}{<td class="trc-ver">v0.0.0</td>}')"
expect_fail "trace code 捏造 (可視==href anchor)"    "$(mut 27 's{(<a class="trc-code trc-req" href="clinic-appointment.srs.html#FR3">)FR3(</a>)}{${1}FRX${2}}')"
expect_fail "trace trc-id リンク swap (#cl-C3→#cl-C9)" "$(mut 28 's{<td class="trc-id"><a href="#cl-C3">C3</a>}{<td class="trc-id"><a href="#cl-C9">C3</a>}')"

# --- ★静的 chrome ラベル ---
expect_fail "band h2 見出し捏造"                    "$(mut 29 's{新しい版から順に、 追加・変更・修正を並べる}{でたらめな見出し}')"
expect_fail "cl-ref-k swap (なぜ→要件)"             "$(mut 30 's{(<div class="cl-ref-row why"><span class="cl-ref-k">)なぜ}{${1}要件}')"
expect_fail "cl-cat-label 捏造 (未知 category label)" "$(mut 31 's{<span class="cl-cat-label">修正</span>}{<span class="cl-cat-label">でっちあげ</span>}')"
expect_fail "trace thead 列ヘッダ捏造"              "$(mut 32 's{<th>区分</th>}{<th>FAKE列</th>}')"
expect_fail "trace phantom 行注入 (承認詐称)"       "$(mut 33 's{(<tr data-component="trace-row"><td class="trc-id"><a href="#cl-C2">)}{<tr><td class="trc-id">偽</td><td class="trc-ver">v9</td><td class="trc-cat">承認</td><td class="trc-ref">全件承認済み</td></tr>${1}}')"
expect_fail "trace tfoot 注入 (承認詐称)"           "$(mut 34 's{(</table>)}{<tfoot><tr><td>承認済みとみなす</td></tr></tfoot>${1}}')"

# --- ★cross-doc 可視 echo / cover-meta / core chrome / term-inline / prose ---
expect_fail "cover ref-chip srs_doc_id 捏造"        "$(mut 35 's{(data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"
expect_fail "cover-meta 収録捏造"                   "$(mut 36 's{(<span class="k">収録</span><span class="v">)[^<]+}{${1}999 版}')"
expect_fail "cover-meta 版捏造 (収録との分離確認)"   "$(mut 37 's{(<span class="k">版</span><span class="v">)[^<]+}{${1}v9.9}')"
expect_fail "approval who 捏造 (core-chrome)"       "$(mut 38 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"            "$(mut 39 's{data-term="満枠">空きなし}{data-term="GHOST">空きなし}')"
expect_fail "prose 注入改竄 (注入忠実)"             "$(mut 40 's{(data-slot-id="plain-C3">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                          "$(mut 41 's{(data-slot-id="plain-C3">)[^<]+(</p>)}{${1}${2}}')"
expect_fail "highlight prose 注入改竄"              "$(mut 42 's{(data-slot-id="latest-highlight">)[^<]+}{${1}改竄ハイライト}')"

# --- ★双子属性 per-edge 等値 (valid-pair relocation・anchor 温存で集合一致を素通りする shape・ceiling 8ptq 実証) ---
expect_fail "★ラベル双子属性 relocation (item: anchor FR3 温存・label を FR2 valid-pair へ)" "$(mut 43 's{<span class="cl-ref-label" data-srs-label-ref="FR3">競合拒否</span>}{<span class="cl-ref-label" data-srs-label-ref="FR2">予約受付</span>}')"
expect_fail "★ラベル双子属性 relocation (trace: 同 shape)" "$(mut 44 's{<span class="trc-label" data-srs-label-ref="FR3">競合拒否</span>}{<span class="trc-label" data-srs-label-ref="FR2">予約受付</span>}')"

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
echo "--- repro-build conformance (verify_repro_build・folio-3d23 B3): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" changelog "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
