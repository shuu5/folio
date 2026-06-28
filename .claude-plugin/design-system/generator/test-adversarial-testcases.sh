#!/usr/bin/env bash
# test-adversarial-testcases.sh — test-cases-pack floor の敵対検査 (verify-testcases.sh が改竄を block するか)
# 各ケース: 正常生成物 (assemble → inject-prose) を 1 箇所改竄 → verify-testcases.sh が exit 1 (FAIL) を返すことを確認。
# fail-closed: 改竄が verify を *通過* したら (exit 0) テスト失敗 (= floor の穴)。
#
# 主眼 (worker brief): trace 改竄・偽 FR/AC 参照 (dangling)・捏造手順・(ref,role) 意味偽装・可視 echo 改竄を *全捕捉*。
# 改竄は byte モード perl (-0777 -pe・日本語リテラルは UTF-8 byte として file の byte と一致) で行う。
#
# usage: test-adversarial-testcases.sh
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$HERE/contract/clinic-appointment.testcases.yaml"
MANIFEST="$HERE/prose/clinic-appointment.testcases.prose.yaml"
ASSEMBLE="$HERE/assemble-testcases.sh"
INJECT="$HERE/inject-prose.sh"
VERIFY="$HERE/verify-testcases.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/good.html"

"$ASSEMBLE" "$CONTRACT" > "$TMP/raw.html"
"$INJECT" "$MANIFEST" "$TMP/raw.html" "$GOOD"

pass=0; total=0
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

# baseline sanity: 正常生成物は PASS すべき
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" >/dev/null 2>&1; then
  echo "  [OK]   baseline 正常生成物は PASS"; pass=$((pass+1))
else
  echo "  [SLIP] baseline が FAIL した (テスト前提崩壊)"; fi

# --- 件数 / 構造 ---
expect_fail "testcase-card マーカー削除 (件数)" "$(mut 1 's{<div data-component="testcase-card" id="tc-TC1">}{<div data-component="testcase-XXX" id="tc-TC1">}')"
expect_fail "rtm-row 削除 (件数 + RTM 脱落)"    "$(mut 2 's{<tr data-component="rtm-row">.*?</tr>\n}{}s')"

# --- 可視 card テキスト fidelity (属性 intact のまま可視だけ改竄・捏造ケース) ---
expect_fail "tc-id 可視捏造"                  "$(mut 3 's{<span class="tc-id">TC1</span>}{<span class="tc-id">TCX</span>}')"
expect_fail "tc-title 可視捏造"               "$(mut 4 's{(<h3 class="tc-title">)[^<]+}{${1}捏造タイトル}')"
# ★tc-trace-tgt 照会ラベル title (live-mirror・folio-c5r.13) を捏造 → 「SRS: 参照先 .meta.title」等値で FAIL (retitle drift 検出)。
expect_fail "tc-trace-tgt 照会ラベル title 捏造 (live-mirror 等値・c5r.13)" "$(mut 60 's{(<p class="tc-trace-tgt">[^<]*SRS: )[^<]+}{${1}捏造された参照先タイトル}')"
expect_fail "tc-kind 可視ラベル捏造"          "$(mut 5 's{(<span class="tc-kind normal">)[^<]+}{${1}でたらめ}')"
expect_fail "tc-kind class 改竄 (label/class 不整合)" "$(mut 6 's{<span class="tc-kind normal">正常系}{<span class="tc-kind abnormal">正常系}')"
expect_fail "tc-prio class 改竄 (must→should)" "$(mut 7 's{<span class="tc-prio must">必須</span>}{<span class="tc-prio should">必須</span>}')"
expect_fail "tc-prio ラベル捏造"             "$(mut 8 's{(<span class="tc-prio must">)[^<]+}{${1}最優先}')"

# --- 捏造手順 (前提・操作・期待結果の可視テキスト改竄) ---
expect_fail "precondition 捏造手順"          "$(mut 9 's{残りが 2 人ぶん空いている}{残りが 999 人ぶん空いている}')"
expect_fail "expected 捏造結果"              "$(mut 10 's{空き枠が「残り 2」}{空き枠が「残り 99」}')"
expect_fail "step 捏造操作"                  "$(mut 11 's{患者が日時を選び、 その枠の空きを問い合わせる}{捏造した操作手順}')"

# --- scope-summary-panel (試すこと/試さないこと) 改竄 ---
expect_fail "scope.in 項目捏造 (rewrite)"    "$(mut 28 's{空き枠の確認・予約受付・競合時の確定・診療時間外の拒否}{でたらめな捏造スコープ}')"
expect_fail "scope.out 項目捏造 (rewrite)"   "$(mut 29 's{診察内容・カルテ・会計・診療報酬の正しさ}{でたらめな除外スコープ}')"
expect_fail "scope.in 項目削除 (件数脱落)"   "$(mut 30 's{<li><span class="b">[^<]*</span>受付時の本人確認の差し戻し[^<]*</li>\n}{}s')"

# --- ★三段 trace / cross-doc 照会の改竄 (本 pack の核) ---
expect_fail "偽 FR 参照 (dangling・SRS に無い FR99)" "$(mut 12 's{data-trace-ref="FR1" data-trace-role="claim">FR1}{data-trace-ref="FR99" data-trace-role="claim">FR99}')"
expect_fail "trace role 意味偽装 (claim→verification)" "$(mut 13 's{data-trace-ref="FR1" data-trace-role="claim"}{data-trace-ref="FR1" data-trace-role="verification"}')"
expect_fail "trace ref 削除 (count mismatch)" "$(mut 14 's{<a class="tc-ref" href="clinic-appointment.srs.html#FR1" data-trace-ref="FR1" data-trace-role="claim">FR1</a>}{}')"
expect_fail "tc-ref 可視 vs attr desync"      "$(mut 15 's{(data-trace-ref="FR1" data-trace-role="claim">)FR1(</a>)}{${1}FRX${2}}')"
expect_fail "RTM FR code 改竄"                "$(mut 16 's{<a class="rtm-code" href="clinic-appointment.srs.html#FR1">FR1</a>}{<a class="rtm-code" href="clinic-appointment.srs.html#FR1">FR-FAKE</a>}')"
# ★folio-c5r.9 cross-doc href 遷移先 fidelity 敵対 (arch gate 1h 同型)。
expect_fail "tc-ref href anchor swap (#FR1→#FR99・attr 温存)"  "$(mut 40 's{(<a class="tc-ref" href="clinic-appointment.srs.html)#FR1(" data-trace-ref="FR1")}{${1}#FR99${2}}')"
expect_fail "tc-ref href filename swap (外部 host)"            "$(mut 41 's{<a class="tc-ref" href="clinic-appointment.srs.html#FR1"}{<a class="tc-ref" href="https://evil.example#FR1"}')"
expect_fail "tc-ref href 剥奪 (span 退行・押せないリンク)"      "$(mut 42 's{<a class="tc-ref" href="clinic-appointment.srs.html#FR1" (data-trace-ref="FR1" data-trace-role="claim">FR1)</a>}{<span class="tc-ref" ${1}</span>}')"
expect_fail "rtm-code href anchor swap (可視FR1・href#FR2)"    "$(mut 43 's{<a class="rtm-code" href="clinic-appointment.srs.html#FR1">FR1</a>}{<a class="rtm-code" href="clinic-appointment.srs.html#FR2">FR1</a>}')"
# ★per-card trace pin (card-keyed) の regression: card 間で FR/AC を入替える (RTM 無改竄)。 global key SET・
#   (key,role) ペア SET・count・RTM は全て不変ゆえ 3/3c は素通る。 3d (per-card 三つ組) のみが捕捉する。
expect_fail "card 間 FR 入替 (TC1↔TC8・RTM 無改竄)" "$(mut 26 's{(id="tc-TC1">.*?)data-trace-ref="FR1" data-trace-role="claim">FR1(</a>)}{${1}data-trace-ref="FR3" data-trace-role="claim">FR3${2}}s; s{(id="tc-TC8">.*?)data-trace-ref="FR3" data-trace-role="claim">FR3(</a>)}{${1}data-trace-ref="FR1" data-trace-role="claim">FR1${2}}s')"
expect_fail "card 間 AC 入替 (TC4↔TC5・RTM 無改竄)" "$(mut 27 's{(id="tc-TC4">.*?)data-trace-ref="AC4" data-trace-role="verification">AC4(</a>)}{${1}data-trace-ref="AC5" data-trace-role="verification">AC5${2}}s; s{(id="tc-TC5">.*?)data-trace-ref="AC5" data-trace-role="verification">AC5(</a>)}{${1}data-trace-ref="AC4" data-trace-role="verification">AC4${2}}s')"

# --- ★FR/AC 平易ラベル併記の fidelity (persona ceiling 是正・SRS 由来でないラベルを封鎖) ---
# card trace の併記ラベルを捏造 (data-label-ref intact のまま可視ラベルだけ非 SRS 値へ)
expect_fail "card ラベル捏造 (非 SRS 由来)"   "$(mut 31 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{<span class="tc-ref-label" data-label-ref="FR1">でたらめ機能</span>}')"
# FR1 のラベルを別 FR(FR2)の正規ラベルへ swap (SRS には在るが ref↔label の対応が誤り)
expect_fail "card ラベル swap (FR1↔FR2 ラベル)" "$(mut 32 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{<span class="tc-ref-label" data-label-ref="FR1">予約受付</span>}')"
# RTM の併記ラベルを捏造
expect_fail "RTM ラベル捏造 (非 SRS 由来)"     "$(mut 33 's{<span class="rtm-label" data-label-ref="FR1">空き確認</span>}{<span class="rtm-label" data-label-ref="FR1">捏造RTMラベル</span>}')"
# card ラベル要素を削除 (件数脱落)
expect_fail "card ラベル削除 (件数)"           "$(mut 34 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{}')"
# cover ref-chip の機能名要約を部分捏造 (b2 の先頭ラベルだけ非 SRS 値へ)
expect_fail "cover 機能名要約 部分捏造"        "$(mut 35 's{(data-component="cross-doc-ref-chip">.*?の要件 <b>)空き確認}{${1}捏造機能}s')"

# --- cross-doc 可視 echo (表紙 ref-chip / trace 見出し・照会先) 改竄 ---
expect_fail "cover ref-chip srs_doc_id 捏造" "$(mut 17 's{(<div class="reader-chip" data-component="cross-doc-ref-chip">.*?<b>)SRS-CLINIC-APPT(</b>)}{${1}FAKE-SRS${2}}s')"
expect_fail "cover ref-chip FR join 捏造"    "$(mut 18 's{(data-component="cross-doc-ref-chip">.*?の要件 <b>)[^<]+}{${1}FR1だけ}s')"
expect_fail "tc-trace-h テンプレ改竄"        "$(mut 19 's{検証する要件と確かめ方}{でたらめな見出し}')"
expect_fail "tc-trace-tgt 照会先改竄"        "$(mut 20 's{照会先: SRS-CLINIC-APPT}{照会先: FAKE-SRS}')"

# --- core chrome / cover-meta / term-inline / escape ---
expect_fail "cover-meta 件数捏造"            "$(mut 21 's{(<span class="k">件数</span><span class="v">)[^<]+}{${1}999件}')"
expect_fail "approval who 捏造 (core-chrome)" "$(mut 22 's{(<span class="who">)山田 理恵}{${1}偽名}')"
expect_fail "term-inline data-term 捏造"      "$(mut 23 's{data-term="診療枠">予約できる時間帯}{data-term="GHOST">予約できる時間帯}')"

# --- prose 注入 (filled) ---
expect_fail "prose 注入改竄 (注入忠実)"      "$(mut 24 's{(data-prose-slot="plain" data-slot-id="plain-TC1">)[^<]+}{${1}改竄プローズ}')"
expect_fail "prose 未充填"                   "$(mut 25 's{(data-slot-id="plain-TC1">)[^<]+(</p>)}{${1}${2}}')"

# --- ★folio-bur: 静的テンプレ chrome ラベルの可視捏造 (visible-text-vs-attribute "other" 型・verify 1a-bur pin) ---
expect_fail "scope 節 h3 意味反転 (✓試すこと→—試さないこと)" "$(mut 70 's{<h3>✓ 試すこと</h3>}{<h3>— 試さないこと</h3>}')"
expect_fail "tc-trace-label 捏造 (検証する要件→捏造ラベル)"  "$(mut 71 's{(<span class="tc-trace-label">)検証する要件(</span>)}{${1}捏造ラベル${2}}g')"
expect_fail "tc-step-k '操作' ラベル捏造"                    "$(mut 72 's{(<span class="tc-step-k">)操作(</span>)}{${1}捏造操作${2}}g')"
expect_fail "RTM thead 列ヘッダ捏造 (検証する要件→FAKE)"     "$(mut 73 's{(<th>)検証する要件(</th>)}{${1}FAKE確認列${2}}')"
# ★folio-bur round-2 (ceiling-recursion): 件数/固定値 chk の射程外を突く 4 bypass を 位置束縛 + 機械的完全列挙で捕捉。
expect_fail "★tc-trace-label を verify⇄confirm 行で swap (件数保存) → 行 role 束縛で捕捉" "$(mut 74 's{tc-trace-label">検証する要件}{tc-trace-label">__S__}g; s{tc-trace-label">確かめる受入基準}{tc-trace-label">検証する要件}g; s{tc-trace-label">__S__}{tc-trace-label">確かめる受入基準}g')"
expect_fail "★属性付き 5 列目 <th class=rtm-extra> 追加 → <th 総数==4 で捕捉" "$(mut 75 's{(<th>確かめる受入基準</th>)}{${1}<th class="rtm-extra">影の承認列</th>}')"
expect_fail "★既知 3 種外の tc-step-k 注入 (件数保存) → 総数+集合で捕捉" "$(mut 76 's{(<ol class="tc-step-list">)}{<div class="tc-step"><span class="tc-step-k">前提条件の補足</span><span class="tc-step-v">捏造</span></div>${1}}')"
expect_fail "★scope に余分 h3 注入 → scol 内 h3 総数==2 で捕捉" "$(mut 77 's{(<div class="scol in"><h3>✓ 試すこと</h3>)}{${1}<h3>⚠捏造警告</h3>}')"
# mut 78-81 ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 fix 自体の残存 fail-open。
#   (78) 大文字 <TH> 5 列目 (case-sensitive count の盲点) (79) 大文字 <H3> scope 注入 (同根)
#   (80) precondition を隣接 card へ relocation (global 順保存ゆえ 4e flatten 素通り) → 4g card-keyed で捕捉
#   (81) 操作 step を隣接 card へ relocation (global 順保存ゆえ 4f flatten 素通り) → 4g card-keyed で捕捉
expect_fail "★大文字 <TH> 5 列目追加 (case 盲点) → <th 総数 case 非依存 count で捕捉" "$(mut 78 's{(<th>確かめる受入基準</th>)}{${1}<TH>影の承認列</TH>}')"
expect_fail "★大文字 <H3> scope 注入 (case 盲点) → scol 内 h3 総数 case 非依存 count で捕捉" "$(mut 79 's{(<div class="scol in"><h3>✓ 試すこと</h3>)}{${1}<H3>⚠捏造警告</H3>}')"
expect_fail "★precondition を隣接 card へ relocation (global順保存) → 4g card-keyed で捕捉" "$(mut 80 's{(<div class="tc-step tc-pre"><span class="tc-step-k">前提</span><span class="tc-step-v">.*?</span></div>)(.*?<div data-component="testcase-card" id="tc-TC2">)}{$2$1}s')"
expect_fail "★操作 step を隣接 card へ relocation (global順保存) → 4g card-keyed で捕捉" "$(mut 81 's{(<li>システムが診(?:(?!</li>).)*</li>)(.*?<ol class="tc-step-list">)}{$2$1}s')"
# mut 82-86 ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 fix 自体の残存 fail-open。
#   (82) thead に <td>5列目 (th タグ keyed の死角) → thead 内 td==0 で捕捉
#   (83) scol *外* の h3 / (84) scol 内 early-termination h3 → 大域 h3 census (NTC+2) で捕捉
#   (85) tc-ref-label の FR↔機能名 誤対応 (global set の射程外) → card-keyed (ref,label) で捕捉
#   (86) §5 cover-meta single-quote KV → quote-robust k 占有数で捕捉
expect_fail "★thead に <td> 5列目注入 (th タグ keyed 死角) → thead 内 td==0 で捕捉" "$(mut 82 's{(<th>確かめる受入基準</th>)}{${1}<td>影の承認列</td>}')"
expect_fail "★scol 外 (任意位置) の捏造 h3 → 大域 h3 census で捕捉" "$(mut 83 's{(</body>)}{<h3>⚠ 重要: この一覧は参考用です</h3>${1}}')"
expect_fail "★scol 内 early-termination h3 (空div で (.*?)</div> 早期終端) → 大域 h3 census で捕捉" "$(mut 84 's{(<div class="scol in"><h3>✓ 試すこと</h3>)}{${1}<div></div><h3>⚠ 捏造見出し</h3>}')"
expect_fail "★tc-ref-label FR↔機能名 誤対応 (FR1→FR2/予約受付) → card-keyed (ref,label) で捕捉" "$(mut 85 's{<span class="tc-ref-label" data-label-ref="FR1">空き確認</span>}{<span class="tc-ref-label" data-label-ref="FR2">予約受付</span>}')"
expect_fail "★§5 cover-meta single-quote KV decoy → quote-robust k 占有数で捕捉" "$(mut 86 's{(<span class="k">種別</span>)}{<span class='"'"'k'"'"'>承認</span><span class='"'"'v'"'"'>未承認のまま公開</span>${1}}')"
# mut 87-90 ★folio-bur round-5 (ceiling-recursion R4 是正): round-4 の thead pin (裸 perl literal/case-sensitive/first-match) 自体の
#   残存 fail-open 3 vector + cover-meta k 占有のみで v 非対称の穴。
#   (87) 大文字 <THEAD> opener (case 死角) / (88) 空 <thead></thead> prepend (first-match 死角) / (89) <thead > 空白属性 (literal 死角)
#       → いずれも捏造 5列目「影の承認列」を thead に注入・case/attr-robust 全 thead global 列挙 + thead 開タグ占有で捕捉
#   (90) k を伴わない単独 <span class="v"> 注入 (k 占有のみの非対称死角) → v 占有数で捕捉
expect_fail "★大文字 <THEAD> opener (case 死角) + td 5列目 → case-robust thead 内 td==0 で捕捉" "$(mut 87 's{<thead><tr>(.*?)</tr></thead>}{<THEAD><tr>${1}<td>影の承認列</td></tr></thead>}s')"
expect_fail "★空 <thead></thead> prepend (first-match 死角) + td 5列目 → thead 開タグ占有==1 で捕捉" "$(mut 88 's{(data-component="testcase-rtm">)<thead><tr>(.*?)</tr></thead>}{${1}<thead></thead><thead><tr>${2}<td>影の承認列</td></tr></thead>}s')"
expect_fail "★<thead > 空白属性 (literal 死角) + td 5列目 → attr-robust thead 内 td==0 で捕捉" "$(mut 89 's{<thead><tr>(.*?)</tr></thead>}{<thead ><tr>${1}<td>影の承認列</td></tr></thead>}s')"
expect_fail "★k 無し単独 <span class=v> 注入 (k 占有のみの非対称死角) → v 占有数で捕捉" "$(mut 90 's{(<span class="k">版</span><span class="v">[^<]*</span>)}{${1}<span class="v">未承認のまま公開</span>}')"
# mut 91-95 ★folio-bur round-6 (ceiling-recursion R5 是正): round-3→5 が thead のみ固めた RTM の tbody 行/セル完全性・別table・tfoot/caption の未 pin。
expect_fail "★data-component 無し styled 偽 <tr>『全件承認済み』→ RTM <tr> 総数==1+NTC で捕捉" "$(mut 91 's{(<tr data-component="rtm-row"><td class="rtm-tc">TC1</td>)}{<tr><td class="rtm-tc">偽行</td><td class="rtm-kind">承認</td><td class="rtm-fr">全FR</td><td class="rtm-ac">全件承認済み</td></tr>${1}}')"
expect_fail "★rtm-row 内余剰 <td>『影の承認列』(novel class rtm-extra) → RTM <td> 総数==4×NTC + enumeration で捕捉" "$(mut 92 's{(<td class="rtm-tc">TC1</td>)}{${1}<td class="rtm-extra">影の承認列: 未承認</td>}')"
expect_fail "★別 <table>『承認状態/全件承認済み』偽承認表 → table 占有==1 で捕捉" "$(mut 93 's{(</body>)}{<table><tbody><tr><td>承認状態</td><td>全件承認済み(捏造)</td></tr></tbody></table>${1}}')"
expect_fail "★<tfoot>『承認済みとみなす』注入 → RTM <tfoot>==0 で捕捉" "$(mut 94 's{(</table>)}{<tfoot><tr><td>注: 承認済みとみなす</td></tr></tfoot>${1}}')"
expect_fail "★<caption>『承認済み: 全テスト合格』注入 → RTM <caption>==0 で捕捉" "$(mut 95 's{(<table data-component="testcase-rtm">)}{${1}<caption>承認済み: 全テスト合格</caption>}')"

# --- floor 単独 GREEN 禁止 (CEILING=PENDING 強制) ---
total=$((total+1))
if "$VERIFY" --filled "$MANIFEST" "$CONTRACT" "$GOOD" 2>/dev/null | grep -q 'GREEN'; then
  echo "  [SLIP] verify が GREEN を出力 (CEILING=PENDING でなければならない)"
else
  echo "  [OK]   GREEN 不在・CEILING=PENDING を強制"; pass=$((pass+1)); fi


# ===== folio-bur round-7 回帰: occupancy-from-contract 完全性 / enumeration 横展開 / display-state guard =====
expect_fail "R7-tc-a ★approval-block 偽承認 wrapper (ceiling 残余) を占有==1 で捕捉" "$(mut 701 's{</body>}{<div data-component=\"approval-block\">本テスト仕様は全項目承認済み(捏造)</div></body>}')"
expect_fail "R7-tc-b ★summary-card additive を占有==1 で捕捉" "$(mut 702 's{</body>}{<div class=\"summary-card\">偽サマリ(捏造)</div></body>}')"
expect_fail "R7-tc-c ★lab additive を占有==1 で捕捉" "$(mut 703 's{</body>}{<div class=\"lab\">偽(捏造)</div></body>}')"
expect_fail "R7-tc-d ★bare term を term==plain-language-term-inline で捕捉" "$(mut 704 's{</body>}{<span class=\"term\">偽バッジ(捏造)</span></body>}')"
expect_fail "R7-tc-e ★display:none 隠蔽を display-state guard で捕捉" "$(mut 705 's{</body>}{<p style=\"display:none\">隠蔽(捏造)</p></body>}')"

echo ""
echo "adversarial: $pass/$total passed"
[[ "$pass" == "$total" ]] || exit 1
echo "ALL PASS"
exit 0
