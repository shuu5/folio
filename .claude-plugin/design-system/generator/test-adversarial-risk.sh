#!/usr/bin/env bash
# test-adversarial-risk.sh — risk-register-pack floor の敵対検査 (verify-risk.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-risk.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼: ★severity 決定的導出の改竄 (card バッジ/matrix セル/tally)・trace 改竄・偽 FR/NFR 参照 (dangling)・
#   捏造 statement/mitigation・card 間 relocation・可視 echo 改竄・per-table phantom 行/セル注入を *全捕捉*。
# 加えて ★assemble 段の contract fail-closed (expect_abort): headline「severity を contract に持たせない=捏造
#   原理不可」を直接 pin し、 dangling ref・未知 likelihood/impact/status・dup id・空/0 件 trace ref・
#   SRS doc_id 不一致 / SRS contract 不在 も生成前 abort で被覆する (verify では検査されない validate() 補償被覆)。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-risk.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-risk.risk.yaml"
MANIFEST="$HERE/prose/clinic-risk.risk.prose.yaml"
ASSEMBLE="$HERE/assemble-risk.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-risk.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
# repro-build arm (verify_repro_build) / gate F (playwright) は bulk case で honest skip (10 分/suite 維持)。
# conformance pin (末尾) だけ SKIP_REPRO= 明示解除で arm ON 実走する。
export SKIP_REPRO="${SKIP_REPRO:-1}"
export SKIP_RENDER="${SKIP_RENDER:-1}"
source "$HERE/lib/test-repro-pins.sh"
# expect_fail <label> <mutated.html> — verify が exit 1 (FAIL) を返すべき
expect_fail() {
  local label="$1" html="$2"
  total=$((total+1))
  if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$html" >/dev/null 2>&1; then
    echo "  [SLIP] $label — verify が改竄を通過させた (exit 0)"
  else
    echo "  [OK]   $label — block (exit 非0)"; pass=$((pass+1))
  fi
}
# mut <case-num> <perl-prog> — GOOD を 1 箇所改竄して $TMP/m<N>.html を作り path を返す
mut() { local n="$1" prog="$2"; local m="$TMP/m$n.html"; perl -0777 -pe "$prog" "$GOOD" > "$m"; printf '%s' "$m"; }
# expect_abort <label> <contract.yaml> [expected_stderr_substring] — assemble 段の contract fail-closed。
#   本 pack の headline (severity を contract に *持たせない* = 捏造原理不可) を担保するのは assemble-risk.sh の
#   validate() のみ。 verify-risk.sh は severity を再導出するだけで contract の severity field 有無・dangling・
#   未知 enum・dup id・空 ref は検査しない (severity 付き contract を渡しても assembler は無視して同一 HTML を
#   吐くため verify 素通し) = 補償被覆なし。 ゆえ mutation→verify-block 型 (expect_fail) では被覆できず、
#   bad contract→生成前 abort 型で pin する (arch 敵対の expect_abort と同型・folio-wdv0 self-review 是正)。
#   abort 系の reason substring は stderr の guard 固有語で判定可 (verify FAIL 系 pin とは別・c5r.2 実証)。
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
# risk_base <dst.yaml> — risk contract を TMP へコピーし、 cross_doc が相対参照する SRS contract も同じ dir へ
#   コピーする (assemble-risk の srs_contract 解決は CONTRACT_DIR 相対の素朴連結 = 兄弟配置が前提)。 コピー先で
#   SRS 参照が巻き添え failure し expect_abort が「mutation 以外の理由」で偽 [OK] 化するのを防ぐ (arch_base 同旨)。
risk_base() {
  local d; d="$(dirname "$1")"
  cp "$CONTRACT" "$1"
  cp "$HERE/contract/clinic-appointment.srs.yaml" "$d/"
}

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- ★assemble 段 contract fail-closed (headline: severity 捏造原理不可 + dangling/未知 enum/dup/空 ref/SRS 終端) ---
#   本 pack の中核 claim を担保するのは validate() だけ (verify は severity 再導出のみで contract の
#   severity field・dangling・enum・dup・空 ref を検査しない)。 ゆえ bad contract→生成前 abort 型で pin する。
# baseline: risk_base コピー (無改竄) は assemble PASS すべき (崩れると以降の expect_abort が全 false-pass)
total=$((total+1))
risk_base "$TMP/base-sanity.yaml"
if "$ASSEMBLE" "$TMP/base-sanity.yaml" >/dev/null 2>&1; then
  echo "  [OK]   baseline risk_base コピーは assemble PASS"; pass=$((pass+1))
else
  echo "  [SLIP] risk_base コピーが assemble FAIL (helper 前提崩壊)"; fi
# ★AB1 headline pin: contract に severity field 混入 → 生成前 abort (severity は決定的導出ゆえ contract 禁止)
risk_base "$TMP/ab-sev.yaml"; yq -i '.risks[0].severity = "high"' "$TMP/ab-sev.yaml"
expect_abort "★AB1 severity field 混入を生成前 abort (headline: 捏造原理不可の直接 pin)" "$TMP/ab-sev.yaml" "severity フィールドが存在"
# AB2 dangling ref (SRS 集合外の FR99) → 生成前 abort
risk_base "$TMP/ab-dang.yaml"; yq -i '.risks[0].trace.refs = ["FR99"]' "$TMP/ab-dang.yaml"
expect_abort "AB2 dangling ref (FR99・SRS 集合外) を生成前 abort" "$TMP/ab-dang.yaml" "SRS に実在しない: FR99"
# AB3 未知 likelihood → 生成前 abort
risk_base "$TMP/ab-lk.yaml"; yq -i '.risks[0].likelihood = "X"' "$TMP/ab-lk.yaml"
expect_abort "AB3 未知 likelihood (X) を生成前 abort" "$TMP/ab-lk.yaml" "未知の likelihood: X"
# AB4 未知 impact → 生成前 abort
risk_base "$TMP/ab-im.yaml"; yq -i '.risks[0].impact = "X"' "$TMP/ab-im.yaml"
expect_abort "AB4 未知 impact (X) を生成前 abort" "$TMP/ab-im.yaml" "未知の impact: X"
# AB5 未知 status → 生成前 abort
risk_base "$TMP/ab-st.yaml"; yq -i '.risks[0].status = "bogus"' "$TMP/ab-st.yaml"
expect_abort "AB5 未知 status (bogus) を生成前 abort" "$TMP/ab-st.yaml" "未知の status: bogus"
# AB6 risks id 重複 → 生成前 abort
risk_base "$TMP/ab-dup.yaml"; yq -i '.risks[1].id = "RSK-001"' "$TMP/ab-dup.yaml"
expect_abort "AB6 risks id 重複 (RSK-001) を生成前 abort" "$TMP/ab-dup.yaml" "risks id 重複: RSK-001"
# AB7 空/null trace ref → 生成前 abort (comm -23 が空行を畳んで素通すのを明示拒否)
risk_base "$TMP/ab-eref.yaml"; yq -i '.risks[0].trace.refs = ["FR2", ""]' "$TMP/ab-eref.yaml"
expect_abort "AB7 空 trace ref を生成前 abort (壊れた前方参照)" "$TMP/ab-eref.yaml" "空 ref"
# AB8 trace.refs 0 件 → 生成前 abort (cross-doc 照会不成立)
risk_base "$TMP/ab-noref.yaml"; yq -i '.risks[0].trace.refs = []' "$TMP/ab-noref.yaml"
expect_abort "AB8 trace.refs 0 件を生成前 abort (cross-doc 照会不成立)" "$TMP/ab-noref.yaml" "trace.refs 空の risk"
# AB9 srs_doc_id 不一致 → 生成前 abort (照会先 SRS の doc_id と齟齬)
risk_base "$TMP/ab-docid.yaml"; yq -i '.cross_doc.srs_doc_id = "SRS-WRONG"' "$TMP/ab-docid.yaml"
expect_abort "AB9 srs_doc_id 不一致 (SRS-WRONG) を生成前 abort" "$TMP/ab-docid.yaml" "SRS contract の doc_id"
# AB10 srs_contract 不在 → 生成前 abort (照会先 SRS 不在)
risk_base "$TMP/ab-nosrs.yaml"; yq -i '.cross_doc.srs_contract = "no-such.srs.yaml"' "$TMP/ab-nosrs.yaml"
expect_abort "AB10 srs_contract 不在を生成前 abort (照会先 SRS 不在)" "$TMP/ab-nosrs.yaml" "照会先 SRS 不在"

# --- 件数 / 構造 ---
expect_fail "risk-card マーカー削除 (件数)" "$(mut 1 's{<div data-component="risk-card" id="rsk-RSK-001">}{<div data-component="risk-XXX" id="rsk-RSK-001">}')"
expect_fail "rtm-row 削除 (件数 + RTM 脱落)"  "$(mut 2 's{<tr data-component="rtm-row">.*?</tr>\n}{}s')"

# --- 可視 card テキスト fidelity (属性 intact のまま可視だけ改竄・捏造) ---
expect_fail "rk-id 可視捏造"          "$(mut 3 's{<span class="rk-id">RSK-001</span>}{<span class="rk-id">RSK-XXX</span>}')"
expect_fail "rk-title 可視捏造"       "$(mut 4 's{(<h3 class="rk-title">)[^<]+}{${1}捏造タイトル}')"
expect_fail "rk-owner 可視捏造"       "$(mut 5 's{(<span class="rk-owner-v">)開発リード}{${1}偽担当}')"
expect_fail "rk-status class 改竄 (mitigating→accepted)" "$(mut 6 's{<span class="rk-status mitigating">対応中}{<span class="rk-status accepted">対応中}')"
expect_fail "rk-status ラベル捏造"    "$(mut 7 's{(<span class="rk-status mitigating">)対応中}{${1}でたらめ}')"
expect_fail "likelihood ラベル捏造 (card-keyed)" "$(mut 8 's{(<span class="rk-level rk-lk">起こりやすさ <b>)中(</b>)}{${1}高${2}}')"

# --- ★severity 決定的導出の改竄 (本 pack の核) ---
expect_fail "★card rk-sev ラベル捏造 (高→低)"        "$(mut 9 's{(<span class="rk-sev high" data-sev-cell="MH">)高}{${1}低}')"
expect_fail "★card rk-sev class 改竄 (high→low)"     "$(mut 10 's{<span class="rk-sev high" data-sev-cell="MH">高}{<span class="rk-sev low" data-sev-cell="MH">高}')"
expect_fail "★card data-sev-cell 改竄 (MH→LL)"       "$(mut 11 's{<span class="rk-sev high" data-sev-cell="MH">高}{<span class="rk-sev high" data-sev-cell="LL">高}')"
expect_fail "★matrix セル件数 捏造 (MH 2→9)"          "$(mut 12 's{<td class="sm-cell high" data-cell="MH"><b class="sm-n">2</b>}{<td class="sm-cell high" data-cell="MH"><b class="sm-n">9</b>}')"
expect_fail "★matrix セル sevclass 改竄 (high→low)"   "$(mut 13 's{<td class="sm-cell high" data-cell="MH">}{<td class="sm-cell low" data-cell="MH">}')"
expect_fail "★tally 件数 捏造 (高 2→9)"               "$(mut 14 's{深刻度 高: <b>2</b>}{深刻度 高: <b>9</b>}')"
expect_fail "★tally band 改竄 (data-band high→low)"   "$(mut 15 's{<span class="sm-tally high" data-band="high">深刻度 高:}{<span class="sm-tally high" data-band="low">深刻度 高:}')"

# --- 捏造 statement / mitigation ---
expect_fail "statement 捏造 (地の文改竄)"  "$(mut 16 's{残り 1 枠に複数の患者がほぼ同時に申し込むと}{捏造した前提}')"
expect_fail "mitigation 捏造 (対策改竄)"    "$(mut 17 's{予約確定を 1 枠 1 件の排他処理にし}{捏造した対策}')"

# --- ★card 群 emission 順 (severity 順) の改竄 ---
expect_fail "★card 順序 swap (RSK-001↔RSK-008・severity 順崩し)" "$(mut 18 's{(<div data-component="risk-card" id="rsk-RSK-001">.*?)(<div data-component="risk-card" id="rsk-RSK-008">.*?)(<div data-component="risk-card" id="rsk-RSK-004">)}{$2$1$3}s')"

# --- ★cross-doc 前方照会 / trace の改竄 ---
expect_fail "偽 ref 参照 (dangling・SRS に無い FR99)" "$(mut 19 's{data-trace-ref="FR2" data-trace-role="claim">FR2}{data-trace-ref="FR99" data-trace-role="claim">FR99}')"
expect_fail "trace role 意味偽装 (claim→verification)" "$(mut 20 's{data-trace-ref="FR2" data-trace-role="claim"}{data-trace-ref="FR2" data-trace-role="verification"}')"
expect_fail "trace ref 削除 (count mismatch)" "$(mut 21 's{<a class="rk-ref" href="clinic-appointment.srs.html#FR2" data-trace-ref="FR2" data-trace-role="claim">FR2</a>}{}')"
expect_fail "rk-ref 可視 vs attr desync"      "$(mut 22 's{(data-trace-ref="FR2" data-trace-role="claim">)FR2(</a>)}{${1}FRX${2}}')"
expect_fail "RTM code 改竄"                    "$(mut 23 's{<a class="rrtm-code" href="clinic-appointment.srs.html#FR2">FR2</a>}{<a class="rrtm-code" href="clinic-appointment.srs.html#FR2">FR-FAKE</a>}')"
# ★card 間 ref 入替 (RSK-001 FR2 ↔ RSK-008 NFR4・RTM 無改竄)。 global set・count・(ref,role) ペア・RTM は不変ゆえ per-card pin のみが捕捉。
expect_fail "★card 間 ref 入替 (RSK-001↔RSK-008・RTM 無改竄)" "$(mut 24 's{(id="rsk-RSK-001">.*?)data-trace-ref="FR2" data-trace-role="claim">FR2(</a>)}{${1}data-trace-ref="NFR4" data-trace-role="claim">NFR4${2}}s; s{(id="rsk-RSK-008">.*?)data-trace-ref="NFR4" data-trace-role="claim">NFR4(</a>)}{${1}data-trace-ref="FR2" data-trace-role="claim">FR2${2}}s')"

# --- ★FR/NFR 平易ラベル併記の fidelity ---
expect_fail "card ラベル捏造 (非 SRS 由来)"   "$(mut 25 's{<span class="rk-ref-label" data-label-ref="FR2">予約受付</span>}{<span class="rk-ref-label" data-label-ref="FR2">でたらめ機能</span>}')"
expect_fail "card ラベル swap (FR2↔FR3 ラベル)" "$(mut 26 's{<span class="rk-ref-label" data-label-ref="FR2">予約受付</span>}{<span class="rk-ref-label" data-label-ref="FR2">競合拒否</span>}')"
expect_fail "RTM ラベル捏造 (非 SRS 由来)"     "$(mut 27 's{<span class="rrtm-label" data-label-ref="FR2">予約受付</span>}{<span class="rrtm-label" data-label-ref="FR2">捏造RTMラベル</span>}')"
expect_fail "card ラベル削除 (件数)"           "$(mut 28 's{<span class="rk-ref-label" data-label-ref="FR2">予約受付</span>}{}')"
expect_fail "cover 機能名要約 部分捏造"        "$(mut 29 's{(data-component="cross-doc-ref-chip">.*?の要件 <b>)予約受付}{${1}捏造機能}s')"

# --- cross-doc 可視 echo (表紙 ref-chip / trace 見出し・照会先) 改竄 ---
expect_fail "cover ref-chip srs_doc_id 捏造" "$(mut 30 's{(<div class="reader-chip" data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"
expect_fail "rk-trace-h テンプレ改竄"        "$(mut 31 's{脅かす要件 \(cross-doc}{でたらめ見出し \(cross-doc}')"
expect_fail "rk-trace-tgt 照会先改竄"        "$(mut 32 's{照会先: SRS-CLINIC-APPT}{照会先: FAKE-SRS}')"

# --- cross-doc href 遷移先 fidelity ---
expect_fail "rk-ref href anchor swap (#FR2→#FR99・attr 温存)"  "$(mut 33 's{(<a class="rk-ref" href="clinic-appointment.srs.html)#FR2(" data-trace-ref="FR2")}{${1}#FR99${2}}')"
expect_fail "rk-ref href filename swap (外部 host)"            "$(mut 34 's{<a class="rk-ref" href="clinic-appointment.srs.html#FR2"}{<a class="rk-ref" href="https://evil.example#FR2"}')"
expect_fail "rk-ref href 剥奪 (span 退行・押せないリンク)"      "$(mut 35 's{<a class="rk-ref" href="clinic-appointment.srs.html#FR2" (data-trace-ref="FR2" data-trace-role="claim">FR2)</a>}{<span class="rk-ref" ${1}</span>}')"
expect_fail "rrtm-code href anchor swap (可視FR2・href#FR3)"   "$(mut 36 's{<a class="rrtm-code" href="clinic-appointment.srs.html#FR2">FR2</a>}{<a class="rrtm-code" href="clinic-appointment.srs.html#FR3">FR2</a>}')"

# --- 静的テンプレ chrome ラベルの可視捏造 (visible-text-vs-attribute "other" 型) ---
expect_fail "matrix thead 列ヘッダ捏造"      "$(mut 37 's{<th class="sm-corner">起こりやすさ \\ 影響</th>}{<th class="sm-corner">FAKE列</th>}')"
expect_fail "matrix 行ヘッダ捏造"            "$(mut 38 's{<th class="sm-row">起こりやすさ 高</th>}{<th class="sm-row">FAKE行</th>}')"
expect_fail "RTM thead 列ヘッダ捏造 (脅かす要件→FAKE)" "$(mut 39 's{<th>脅かす要件</th>}{<th>FAKE確認列</th>}')"
expect_fail "rk-mit-k '対策' ラベル捏造 (件数割れ)"    "$(mut 40 's{<span class="rk-mit-k">対策</span>}{<span class="rk-mit-k">FAKE</span>}')"
expect_fail "rk-owner-k '担当' ラベル捏造 (件数割れ)"  "$(mut 41 's{<span class="rk-owner-k">担当</span>}{<span class="rk-owner-k">FAKE</span>}')"

# --- ★per-table 構造完全性 (phantom 行/セル/別 table/tfoot/caption 注入封鎖) ---
expect_fail "★data-component 無し styled 偽 rtm-row 注入 → RTM tr 総数で捕捉" "$(mut 42 's{(<tr data-component="rtm-row"><td class="rrtm-id">RSK-001</td>)}{<tr><td class="rrtm-id">偽行</td><td class="rrtm-sev">承認</td><td class="rrtm-status">承認済</td><td class="rrtm-refs">全件承認済み</td></tr>${1}}')"
expect_fail "★RTM 行に余剰 td 注入 → RTM td 総数で捕捉"       "$(mut 43 's{(<td class="rrtm-id">RSK-001</td>)}{${1}<td class="rrtm-status">影の承認列</td>}')"
expect_fail "★<tfoot>『承認済とみなす』注入 → tfoot==0 で捕捉"  "$(mut 44 's{(</table>)}{<tfoot><tr><td>注: 承認済とみなす</td></tr></tfoot>${1}}')"
expect_fail "★<caption>『承認済: 全リスク対応済』注入 → caption==0 で捕捉" "$(mut 45 's{(<table data-component="risk-rtm">)}{${1}<caption>承認済: 全リスク対応済</caption>}')"
expect_fail "★別 <table> 注入 → table 総数==2 + allowlist で捕捉" "$(mut 46 's{(</body>)}{<table data-component="severity-matrix"><tr><td class="sm-cell low" data-cell="LL"><b class="sm-n">0</b><span class="sm-lv">低</span></td></tr></table>${1}}')"

# --- core chrome / cover-meta / term-inline / escape ---
expect_fail "cover-meta 件数捏造"            "$(mut 47 's{(<span class="k">件数</span><span class="v">)[^<]+}{${1}999件}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 48 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"      "$(mut 49 's{data-term="診療枠">予約できる時間帯}{data-term="GHOST">予約できる時間帯}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 50 's{(data-prose-slot="plain" data-slot-id="plain-RSK-001">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 51 's{(data-slot-id="plain-RSK-001">)[^<]+(</p>)}{${1}${2}}')"

# --- novel class/data-component 注入 (機械的網羅で封鎖) ---
expect_fail "novel data-component 注入"      "$(mut 52 's{(</body>)}{<div data-component="fake-approval">全承認済</div>${1}}')"
expect_fail "novel class token 注入"         "$(mut 53 's{(<div class="rk-grid">)}{<div class="fake-banner">全リスク解決済</div>${1}}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi

echo ""
echo "--- repro-build conformance (verify_repro_build): (a)EOF追記→BYTE-DIFF (b)時刻のみ差→[OK] (c)入力欠落→exit2 (d)非ts footer改竄→BYTE-DIFF ---"
total=$((total+1)); if repro_pins "$VERIFY" risk "$CONTRACT" "$MANIFEST" "$ASSEMBLE" "$INJECT" --filled "$MANIFEST"; then pass=$((pass+1)); echo "  [PASS] repro-build conformance (a-d)"; else echo "  [FAIL] repro-build conformance (a-d)"; fi
echo
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
