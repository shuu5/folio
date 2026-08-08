#!/usr/bin/env bash
# folio engine — srs-verification pack の ★ADR-0054 §2.2 提示層 shape floor (folio-o01k・Cell S)
#
# ★scope は ★ADR-0054 §2.2 の提示層 shape の pin に ★限定 する (Cell S 契約 追補 1 / 13 = admin 裁定 D1 scope A′)。
#   sibling の verify-verification.sh / verify-spec.sh / verify-relations.sh は「pack 全体の fabrication-free floor」
#   (件数・block fidelity・cover-meta・機械層 round-trip・census・containment …) を担う ★フル verifier だが、
#   本 script は ★その fork ではない — Cell S が新設した提示層 arm だけを持つ ★部分 verifier である。
#
# ★★in-scope の ★追加 (folio-3zr4 Leg C = folio-3zr4.3・下記 arm 2C): containment 3 レベル完全子数束縛
#   (kids / bkids / cbkids) + HTML5 同型 tokenizer + 器中身の帰属 pin を ★移植済 (MECHPIN は tracked 静的 pin
#   ゆえ test-adversarial-srs-verification.sh 側)。 ★閉じたのは ★人間層 (chapbody 直下) の ★block 粒度
#   relocation クラス に限る — 射程・前提・残差の逐語開示は arm 2C の冒頭コメントに置く (ここに要約を二重化
#   すると片方が stale 化するため、 ★所在だけ を示す)。
#
# ★★out-of-scope の ★実態開示 (silent 欠落は「範型踏襲済」の誤報告になる・追補 13)。 以下は本 script が ★検査しない:
#   - 機械層 cross-fold round-trip (機械層 block の逐語 round-trip)                              → folio-e706
#     ★srs-verification には機械層 round-trip arm が ★1 本も無い (sibling pack にある「順序変化だけは見る」層すら
#     持たない) ため、 containment 移植後も ★machine_blocks の cross-fold 移動は無検査 のままである。
#   - frozen census 新設 / census-guard KNOWN_SPECS 拡張 / origin round-trip floor / registry 粒度 → folio-vhew
#     ★srs-verification には frozen census file が ★存在しない (spec-origin/ は origin.html のみ)。 本 cell では
#     ★新設しない: census-guard.sh の KNOWN_SPECS は verification / rules / relations の 3 つのみで未知名は
#     base-ref と解釈され、 ci.yml にも該当 step が無く ★常時 dormant = fail-open な false record になるため。
#   - ★CSS / 属性による不可視化 (display:none / visibility:hidden / hidden 属性 / aria-hidden / 画面外配置 等)。
#     本 script が構造的に扱うのは (i) コメント / RAWTEXT (script・style) の ★中身を落とす ことと、
#     (ii) ★emit しうるタグの closed allowlist (LIVE_TAG_OK) を外れたタグ名の ★存在自体を赤にする ことだけ
#     ($BODY_LIVE・下記 make_body_live)。 style / 属性由来の不可視は render 実測 (render-gate) と
#     ceiling (persona-walk / fidelity) の領分で、 ★本 floor では検出できない。
#     ★初版は inert 容器を 5 種だけ名指し列挙していたが、 独立 ceiling が iframe / textarea / xmp / noembed /
#     noframes / datalist で素通りを実証したため (errata-1 E-2)、 ★容器を追う のをやめて ★補集合側の閉包
#     (allowlist 外は全部拒否) へ転換した。 ここに書かない限り「隠蔽クラスは塞いだ」の誤報告になる。
#   - 件数 fidelity / block 内容 fidelity / cover-meta / 要件 essence・statement の contract 突合
#     → 本 pack では ★verify-srs-verification-drift.sh (canonical == fresh 再生成の byte 一致) が担う。
#     ★ただし drift は「同一 assembler から導出した 2 つを比べる」ため ★assembler 改修 + canonical 再生成の組は
#       常に PASS する = ★提示層の正しさの根拠にはならない (Cell S 契約 追補 2)。 本 script がその穴を埋める。
#
# usage: verify-srs-verification.sh [--artifact] <spec-contract.yaml> <generated.html>
#   --artifact  prose 注入 ★後 の成果物を検査する (平易行 / 優先度ラベルの ★中身 を見る arm が有効化される)。
#               省略時は pre-fill (assembler 直後 = slot 空) 形として中身系 arm を skip する。
# exit: 0 = 提示層 floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★floor / ceiling 境界: 本 floor が見るのは ★構造 anchor と ★決定的フィールド値 の突合のみ。 平易行 (rq-plain) や
#   章リード の ★内容真正性 は floor の対象外 = ceiling (fidelity-* / persona-walk-*) の領分。 floor 単独で GREEN に
#   ならず CEILING=PENDING を返す。
#
# ★★2 つの body view の役割 (実態開示・admin 裁定 srs 条項 (1)。 どちらを subject にするかは arm ごとに違う):
#   - ★$BODY      = lib/verify-common.sh の make_body が作る本文 (コメント本文と <script> 中身は ★verbatim 保持・
#                   畳むのは <style> の中身だけ)。 ★HTML の生の構造 をそのまま持つ view。
#   - ★$BODY_LIVE = $BODY からさらに ★非描画領域 を落とした view (コメントは丸ごと除去 / script・style・title の
#                   中身は空化 / allowlist 外タグ・bogus comment は fail-closed で ★空の view を返す)。
#   ★使い分け: ★census / 列突合 / 逐値 echo など「人間に描画される要素を数える / 突き合わせる」arm は ★$BODY_LIVE
#   (コメントや script に包んだ markup を live と同じく数える hiding fail-open を塞ぐため)。 ★containment (arm 2C)
#   と ★escape 健全性 / 旧ラベル残存の negative pin は ★$BODY (前者は自前の HTML5 同型 tokenizer で非描画容器を
#   実 parser と同型に扱うため live view からの供給を要さず、 かつ $BODY_LIVE の fail-closed 巻き添えが
#   per-shape MK の「単独発火」を証明不能にするため。 後者はコメント内へ退避した化け entity も撃つため)。
#   ★この非対称は ★意図的 である — arm を足すときは subject をどちらにするかを ★明示的に選び、 上の理由に
#   照らして正当化すること (惰性で片方に寄せると hiding クラス か MK 単独性 のどちらかが静かに壊れる)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARTIFACT=""
if [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-srs-verification.sh [--artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-srs-verification.sh [--artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-srs-verification: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-srs-verification: html not found: $HTML" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-srs-verification: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-srs-verification: perl required" >&2; exit 2; }

# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-srs-verification: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=62; source "$LVC" || { echo "verify-srs-verification: failed to source verify-common.sh" >&2; exit 2; }

# ============================================================================
# ★ADR-0054 lockstep 定数群 — assemble-srs-verification.sh と ★二重保守 (detect↔remediate parity)。
#   assembler が emit する平易ラベル / 静的見出し / wrapper id を verify 側でも宣言し ★逐値で突合する
#   (片側だけ変えると FAIL する = 提示層の drift を lockstep で封鎖する)。
# ============================================================================
# ★role の平易語 map。 attr (data-ref-role) は機械 token を保持し ★可視ラベルのみ map 適用 (chip 突合は
#   attr=token / visible=平易語 の ★非対称 を literal に要求する = 可視の英語生表示への退行を捕捉)。
declare -A ROLE_PLAIN=(
  [implementation]="この規約が実装する原則" [rationale]="そう決めた理由の記録" [claim]="この文書が満たすと主張する要件"
  [exploration]="探索の記録" [principle]="拠って立つ原則" [verification]="どう確かめるかの仕様"
)
# ★RFC-2119 優先度 (must|should) → 可視ラベルの ★closed allowlist ('|' 区切りの逐値集合)。 バッジの可視文字列は
#   prose slot が持つため、 floor は「level ごとに許される可視ラベルの ★有限集合」に属するかを逐値突合する。
# ★前方一致 (語幹で始まる) は使わない (ehar クラス): 「必須ではない」のような ★否定接尾 が語幹で始まるため
#   prefix 判定を素通りし level と意味が反転したまま全 gate を通る。
# ★should entry を ★削除しない: srs-verification の contract は現状 must のみ (実測 5/5) だが、 allowlist を
#   実データに合わせて縮小すると将来 contract が should を持ったときの fail-closed が壊れる (Cell U 先例)。
# ★集合の拡張には prose manifest / 本 allowlist / assemble-srs-verification.sh の同名配列の ★三点同時更新 が要る。
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 §番号は literal 固定せず contract の
#   最終 section 見出しから ★導出 する (下記 STATIC_HEADINGS 組み立て)。 assemble-srs-verification.sh と二重保守。
# ★srs-verification の照会種別は 原則 (P-x) / 決定記録 (ADR) / 検証仕様 (REQ-VER → verification.html) の ★3 種
#   (実測: implementation 1 + rationale 7 + verification 2 = 10) ゆえ ★rules と同一逐語 になる。 verification /
#   relations 版の 2 種文言 (「原則と決定記録へつながる」) を写すと ★実在する照会 2 件を落とす虚偽見出しになる。
STATIC_HEADING_TAILS=("上位文書への前方照会 — 原則・決定記録・検証仕様へつながる" "本文に出てくる専門語のやさしい説明")
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token 2 つに固定・4 spec 横断で同一)。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★各 wrapper が包む章帯の tint (assemble-srs-verification.sh build() の band_num 実引数 violet / brand と二重保守)。
#   tint を持たないと「隣に *何らかの* band が在る」しか言えず 別章 band の付け替えが素通る。
PRESENTATION_WRAPPER_BAND_TINTS=("violet" "brand")
# ★静的 band の kicker (同 build() の実引数と二重保守)。
STATIC_KICKERS=("この仕様が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2・wave 恒常 2)。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# ★契約非依存 census floor の期待値 (★srs-verification 固有の ★実測導出値・0/0 恒真封鎖・wave 恒常 3)。
#   新 field (references[].title / requirements[].priority) は ★all-or-none / optional ゆえ contract から一括削除すると
#   「契約側も生成物側も空」で逐値突合が ★0/0 恒真 PASS する。 生成物の占有数を ★数値 hardcode で pin して封鎖する。
# ★★relations (13/4/4/2) / rules (36/26/26/23) / verification (30/31/31/19) の literal 流用は ★禁止。
# ★★census の subject は ★make_body_live 後の $BODY_LIVE である。 landed canonical へ ★素朴に grep すると
#   ★inline <style> の CSS selector 行まで数えてしまい、 実際の要素数より ★多い 値になる (parser-differential)。
#   ★具体値をここに書かない (errata-1 E-8): 上振れ幅は ★pack inline CSS が持つ当該 data-component selector の
#   ★本数に連動して動く ため、 数値を焼くと提示層 CSS を 1 行足すたびに ★静かに stale 化する (実際に本 cell の
#   CSS 追加 = .rq-plain / .rq-plain-k / .rq-prio / .rq-prio-must / .rq-prio-should / .rf-gloss で base 時点の
#   例示値が false record になった)。 ★不変な規律だけを残す: 数値を再導出するときは ★必ず $BODY_LIVE を
#   subject にし、 素の canonical / $BODY へ直接 grep しないこと。
#   ★census / 列突合の subject は ★$BODY ではなく $BODY_LIVE (非描画領域を落とした view・下記)。 $BODY のままだと
#   コメント / script に包んだ markup を live と同じく数える hiding fail-open が開く (実測済・下記 ★なぜ要るか)。
FZC_RF_GLOSS=10      # 前方照会チップの一行タイトル = |references|
FZC_RQ_PRIO=5        # RFC-2119 優先度バッジ = |requirements|
FZC_RQ_PLAIN=5       # 「やさしく言うと」平易行 = |requirements|
FZC_MF_KICKER=5      # 機械層 fold の平易 kicker = machine_preamble(1) + machine_blocks 保有 section 4 本 (s0/s1/s3/s4)
FZC_RQ_NORM=5        # 要件 normative fold の平易 summary = |requirements|
FZC_STATIC_BAND_NUM_LO=5  # 静的 band の §番号 (前方照会) — 最終 section = §4 ゆえ §5
FZC_STATIC_BAND_NUM_HI=6  # 静的 band の §番号 (用語集)   — 同 §6
# ★FZC_SUBHEAD_SE 相当 arm は ★置かない: srs-verification contract の block type 実測は requirements 1 / table 1 のみで
#   subhead / subsubhead は ★0 本。 0 を pin すると 0/0 恒真 chk になり teeth を持たないまま「検査している」と誤読させる。
# ★ref-primary (References の一次参照可視化) arm も ★置かない: relations 固有と verify-verification.sh が明文化済で、
#   srs §4 References の項目は ★全て内部リンク (外部 URL 0 件) ゆえ実装しても 0/0 恒真になる。

fail=0
make_body "$HTML"

# ============================================================================
# ★live view ($BODY_LIVE) — ★非描画領域 (HTML コメント / RAWTEXT の中身) を落とした本文。
# ============================================================================
# ★なぜ要るか (hiding クラスの fail-open・独立 ceiling 実測): lib/verify-common.sh の make_body は
#   ★コメントを verbatim・<script> の中身を opaque 保持する (畳むのは <style> の中身だけ) 設計ゆえ、
#   $BODY への grep / perl 計数は ★コメント内・script 内の markup を live 要素と同じく数える。
#   実測: 実 artifact の chip 1 個 / 要件 row 1 本 / 前方照会 wrapper 章まるごと を <!-- --> で包む、
#   あるいは chip を <script type="text/plain"> で包む — いずれも本 floor の全 arm が rc=0 / [FAIL] 0 で
#   ★素通った。 つまり本 floor は「文字列が存在するか」しか見ておらず「人間に描画されるか」を束縛していなかった
#   (= 本 gate が塞ぐと宣言した穴そのものが空いたまま)。 これは本リポで実証済の既知 fail-open クラス
#   (verify-spec.sh の comment-hidden genuine / naive census counter) の再演である。
# ★drift gate は救いにならない: 追補 2 のとおり assembler 改修 + canonical 再生成の組は常に PASS するため、
#   ★assembler 側が提示層をコメントアウトする形の退行は drift 緑・floor 緑で land しうる。
# ★実装方針 (姉妹 strip_inert を ★移植しない 理由): verify-spec.sh / verify-relations.sh /
#   verify-verification.sh の strip_inert は ★bogus comment `<!x>` のオフセット誤算という fail-open を持ち、
#   そのため 3 arm とも「本 view を ★どの census も消費しない」隔離状態にある (folio-gt4s・LIVEPIN が pin)。
#   隔離中の実装を新 gate の ★消費経路 に引き込むのは、 既知 fail-open の ★再開通 に等しい。 よって本 script は
#   make_body と ★同一の走査規律 (byte 走査 + 未閉じ/不正 close の fail-closed) で live view を作る:
#     - <!-- ... -->            → ★丸ごと落とす (コメント内 markup は live でない)
#     - <script>/<style>/<title> の中身 → ★空化 (開始/終了タグは保存 = 構造は壊さない)
#       ★title を同列に置く理由 (errata-2 F-2): title は HTML5 の ★RCDATA かつ UA display:none で、
#       ★allowlist 内 (assembler が head に emit する正当なタグ) でありながら ★隠蔽容器として使える。
#       body 内で chip を <title> で包むと html5lib DOM 実測 10→9 (人間に見えない) のに、 allowlist 判定だけでは
#       素通った (実弾 CONFIRMED)。 head の実 title は census subject 外ゆえ空化しても副作用は無い (healthy の OK 数不変を実測確認)。
#     - <!DOCTYPE ...>          → 保存 / それ以外の <! ... > (HTML5 bogus comment) → ★fail-closed
#       (bogus comment は browser が非描画にする一方 naive 走査は live として数える = 姉妹の穴と同型。
#        parse して数え直すのでなく ★存在自体を赤にする = partial-enumeration trap を踏まない)
#     - ★上記以外の全タグ → ★closed tag allowlist (LIVE_TAG_OK) の ★肯定判定。 allowlist 外のタグ名が 1 つでも
#       出現したら 'unknown-container' で ★fail-closed。
# ★★closed allowlist にした理由 (errata-1 E-2・独立 ceiling wf_0e9df1ad-e8c が実弾 CONFIRMED):
#   初版は inert 容器を {comment, script, style, template, bogus} の ★5 種だけ 名指し列挙していた。 しかし HTML には
#   他にも非描画容器があり、 iframe / textarea / xmp / noembed / noframes (HTML5 RAWTEXT/RCDATA) や datalist
#   (UA display:none) で chip を包むと ★DOM から消える (html5lib 実測 chip=10→9) のに rc=0 / FAIL 0 で素通った。
#   ★容器を増やして追う のは partial-enumeration trap の再演 (test-adversarial-verification.sh の先例が明記) ゆえ、
#   ★「emit しうるタグ集合」を実体から独立再導出して固定し、 それ以外を全部拒否する ★補集合側の閉包 に転換した。
#   ★注 (folio-7wbn 批准裁定との両立): noscript を「inert に倒す」のではない — assembler も chrome も emit しない
#   ゆえ allowlist 外 = unknown-container で落ちるだけ。 本 gate は noscript を ★非描画と主張しない (「未知容器を
#   拒否する」だけ)。 inert 集合の 4 verifier 横断再裁定は folio-3zr4 の領分 (本 cell は触らない)。
# ★★allowlist は ★それ自体では閉じない (errata-2 F-2 の教訓・silent 欠落封鎖): allowlist ★内 のタグでも
#   ★中身が描画されない種別 (RAWTEXT / RCDATA / UA display:none) は ★隠蔽容器になりうる。 実際 <title> が
#   その唯一の残穴だった。 ★focused re-cert が allowlist 41 タグを ★全数 sweep して閉包を確認済:
#   script / style は既に RAWTEXT 空化で捕捉・★残り 38 タグ (41 − 空化 3 種) は隠蔽不成立・★残穴は title ただ 1 つ
#   (1 member で収束)。 ★38 の内訳: 37 は包んでも gate 緑のまま = 隠蔽不成立 / h2 のみ保守的に赤 (見出し列 arm)。
#   ★★閉包の ★基準 を明示する (errata-3 G-4): ここでいう「隠蔽」は ★構造 oracle = ★DOM 在否 基準である。
#   ★UA 既定の折り畳み (allowlist 内の <details> = spec-machine-fold で包むと Chromium 実測で render 上は
#   不可視だが DOM には在る) や CSS 由来の不可視は ★本基準の外 で、 render-gate / ceiling の領分。
#   pack が <details> を ★正当に emit する以上 cell 内では塞げない設計的緊張であり、 「残穴は title ただ 1 つ」は
#   ★構造基準での主張 である (render 基準では成り立たない)。 inert 集合の横断再裁定は folio-3zr4 の領分。
#   ゆえに現在の閉包は「allowlist 外 = 全拒否」+「allowlist 内の RAWTEXT/RCDATA 3 種 (script/style/title) = 中身空化」
#   の 2 段で成り立つ。 ★allowlist にタグを足すときは「そのタグの中身は描画されるか」を必ず確認すること
#   (描画されないなら空化分岐へも足す — 足さないと allowlist 内の新しい隠蔽容器になる)。
# ★★floor の限界 (実態開示・silent 欠落封鎖): 本 live view が束縛するのは HTML の ★タグ集合と構造的 inert 容器 のみ。
#   CSS / 属性による不可視化 (display:none / visibility:hidden / hidden 属性 / aria-hidden / 画面外配置 /
#   font-size:0 等) は ★本 floor では検出できない — 「描画されるか」の完全判定は render 実測 (render-gate) と
#   ceiling (persona-walk / fidelity) の領分である。 ここに書かない限り「隠蔽クラスは塞いだ」の誤報告になる。
# ★LIVE_TAG_OK = assembler + folio build (chrome) が emit しうるタグ名の ★閉集合 (小文字正規化)。
#   ★導出は ★emit 実体からの独立再測 (worker が本 cell で再実行して確定): landed canonical = 41 種 /
#   assembler+inject 出力 (chrome 前) = 40 種 (nav を欠く = chrome 注入分) で ★後者は前者の部分集合。
#   ゆえに allowlist は landed の 41 種とする (両 mode を同一 allowlist で通す)。
#   ★template はここに ★入れない (assembler も chrome も emit しない = allowlist 外で自然に fail-closed)。
#   ★集合を増やすときは「assembler / chrome が実際に emit するようになったか」を実体で確認してから足す
#   (推測で足すと補集合の閉包が緩む = 本 arm の teeth が消える)。
LIVE_TAG_OK='a|aside|b|body|caption|circle|code|dd|details|div|dl|dt|em|footer|h1|h2|head|header|html|li|link|meta|nav|p|path|pre|script|section|span|strong|style|summary|svg|table|tbody|td|th|thead|title|tr|ul'
make_body_live() { # $1 = 入力 (make_body 済 $BODY)
  BODY_LIVE="$(mktemp)"
  LIVE_ERR="$(mktemp)"   # ★global (local にすると trap EXIT 時に未定義 = set -u で unbound variable)
  # ★trap の本体は ★single quote で括る (errata-2 F-1): double quote だと ★trap 設置時 に展開され、
  #   この時点で 3 変数がまだ空 / 別値なら 'rm -f "" "" ""' が焼き込まれて ★何も消さない trap になる。
  #   実際 errata-1 E-2 の編集でこの形が混入し、 gate 1 走行あたり tmp 3 file (敵対 suite 1 走行で 210 file
  #   / 11M) を leak していた。 single quote なら ★発火時 に展開されるので常に現在値を消す。
  trap 'rm -f "$BODY" "$BODY_LIVE" "$LIVE_ERR"' EXIT
  if ! LIVE_TAG_OK="$LIVE_TAG_OK" perl -e '
    binmode STDIN; binmode STDOUT;
    local $/; my $h = <STDIN>; $h = "" unless defined $h;
    my $o = ""; my $n = length($h); my $i = 0; my $fail = "";
    while ($i < $n && $fail eq "") {
      my $lt = index($h, "<", $i);
      if ($lt < 0) { $o .= substr($h, $i); last; }
      $o .= substr($h, $i, $lt - $i);
      my $rest = substr($h, $lt, 16);
      if (substr($h, $lt, 4) eq "<!--") {
        my $end = index($h, "-->", $lt + 4);
        if ($end < 0) { $fail = "unclosed-comment"; last; }
        $i = $end + 3;                                  # ★コメントは丸ごと落とす (live でない)
      } elsif ($rest =~ /^<!doctype\b/i) {
        my $gt = index($h, ">", $lt);
        if ($gt < 0) { $fail = "unclosed-doctype"; last; }
        $o .= substr($h, $lt, $gt + 1 - $lt); $i = $gt + 1;
      } elsif (substr($h, $lt, 2) eq "<!" || substr($h, $lt, 2) eq "<?") {
        $fail = "bogus-comment"; last;                  # ★HTML5 bogus comment = 非描画 → fail-closed
      } elsif ($rest =~ m{^</?([a-zA-Z][a-zA-Z0-9]*)} && lc($1) !~ /^(?:$ENV{LIVE_TAG_OK})$/) {
        # ★closed tag allowlist (errata-1 E-2): allowlist 外のタグ名は ★1 つでも出たら赤。
        #   inert 容器を名指しで追う partial-enumeration を ★補集合側の閉包 に置換したもの
        #   (iframe / textarea / xmp / noembed / noframes / datalist / noscript … を個別列挙しない)。
        $fail = "unknown-container:" . lc($1); last;
      } elsif ($rest =~ /^<(style|script|title)\b/i) {
        my $kind = lc($1);
        my $gt = index($h, ">", $lt);
        if ($gt < 0) { $fail = "unclosed-opentag-$kind"; last; }
        my $opentag = substr($h, $lt, $gt + 1 - $lt);
        if (index(substr($opentag, 1), "<") >= 0) { $fail = "raw-lt-in-$kind-opentag"; last; }
        $o .= $opentag;
        my $after = $gt + 1; my $tail = substr($h, $after);
        if ($tail =~ m{</\Q$kind\E([^>]*)>}i) {
          my $junk = $1; my $ce = $after + $+[0];
          if ($junk =~ /\S/) { $fail = "malformed-close-$kind"; last; }
          $o .= "</$kind>";                             # ★中身は空化 (RAWTEXT は描画されない)
          $i = $ce;
        } else { $fail = "unclosed-$kind"; last; }
      } elsif ($rest =~ m{^</?[a-zA-Z]}) {
        my $gt = index($h, ">", $lt);
        if ($gt < 0) { $fail = "unclosed-tag"; last; }
        my $tag = substr($h, $lt, $gt + 1 - $lt);
        if (index(substr($tag, 1), "<") >= 0) { $fail = "raw-lt-in-tag"; last; }
        $o .= $tag; $i = $gt + 1;
      } else { $o .= "<"; $i = $lt + 1; }
    }
    if ($fail ne "") { print STDERR "make_body_live fail-closed: $fail\n"; exit 3; }
    print $o;
  ' < "$1" > "$BODY_LIVE" 2>"$LIVE_ERR"; then
    : > "$BODY_LIVE"   # fail-closed: 空 live view で全 census を欠落 FAIL させる
    # ★診断理由を ★[FAIL] 行そのもの へ載せる (errata-1 E-2): 理由 (unknown-container:<tag> 等) を stderr へ
    #   捨てると「何が落ちたか」が読み手にも ★敵対 suite の pin にも届かず、 全隠蔽が同一文言に畳まれる
    #   (どの容器で落ちたか区別できない = per-shape MK が「別 shape の巻き添え」と区別できなくなる)。
    echo "  [FAIL] make_body_live fail-closed: $(tr -d "\n" < "$LIVE_ERR" | sed 's/make_body_live fail-closed: //') (allowlist 外タグ / bogus comment / 未閉じ RAWTEXT 等)"
    fail=1
  fi
}
make_body_live "$BODY"

echo "srs-verification pack — ADR-0054 §2.2 提示層 shape floor: $HTML"
echo "  contract: $CONTRACT"
echo "  ★scope = 提示層 shape + containment (章化の実質・人間層 block 粒度の relocation クラス / folio-3zr4 Leg C で移植済)"
echo "  ★out-of-scope = 機械層 cross-fold round-trip=folio-e706 / frozen census=folio-vhew / CSS・属性由来の不可視 (render-gate + ceiling の領分)"

NSEC="$(q '.sections | length')"
NREQ="$(q '.requirements | length')"
NREF="$(q '.references | length')"

# ---- ★occurrence 計数 (行計数 fail-open の構造封鎖・errata-1 E-1) ----
# ★grep -c は ★行 を数えるため「既存要素と ★同一行 に捏造要素を append」で件数が動かず素通る
#   (独立 ceiling が実弾で実証: 捏造 chip を P-13 chip と同一行へ append → rc=0 / FAIL 0。 陰性対照 = 同じ捏造を
#    ★別行 に置くと expected 10 got 11 で FAIL = 行計数が原因と isolate 済。 html5lib DOM 実測では chip=11 =
#    捏造要素は ★実際に描画される)。 件数系 chk は ★全て 本 helper (出現回数) を通す。
# ★arm 0 の negative pin が既に grep -oF | wc -l 形なので、 規律をそちらへ統一する (片側だけ行計数の非対称を解消)。
occ() { # $1 = 固定文字列 marker / $2 = subject file → 出現回数
  grep -oF -- "$1" "$2" | wc -l | tr -d ' '
}

# ---- 節番号 (§N) を contract sections[].heading から ★導出 する (band .num 突合の trust anchor) ----
# ★期待列を hardcode の連番で作ると assembler 側の導出と ★両側が同じ仮定に合意しているだけ になり、 実際の見出し
#   (h2 の「§N.」) と .num が食い違っても検出できない。 見出し自身を trust anchor にして構造束縛する。
# ★fail-closed: §N を持たない heading が 1 本でもあれば abort (0 件マッチの恒真化を防ぐ)。
# ★-Mutf8 必須: -CSD は入力を decode するが ★program source の literal は decode しない — 「§」を素の byte のまま
#   書くと decode 済み入力と一致せず ★常に 0 match = 全 heading が NO-SECTION-NUMBER となり誤 abort する。
SEC_NUMS="$(q '.sections[].heading' | perl -CSD -Mutf8 -ne 'chomp; if (/^§(\d+)\./) { print "$1\n" } else { print "NO-SECTION-NUMBER\n" }')"
# ★`producer | grep -q` を herestring へ是正 (admin gate errata-1 で敵対 suite 側の同型が ★偽 RED を出した):
#   pipefail 下で `grep -q` が早期 exit すると producer が SIGPIPE 死し pipeline rc=141 になる。 ここは producer が
#   printf の小出力ゆえ実害は出ていない (pipe buffer 内で完結) が、 ★向きが fail-open (guard が偽 → 異常見逃し)
#   である点が敵対 suite 側 (fail-closed 方向の偽 RED) より悪い。 パターンごと排除する。
if [[ -z "$SEC_NUMS" ]] || grep -q 'NO-SECTION-NUMBER' <<< "$SEC_NUMS"; then
  echo "verify-srs-verification: ★contract sections[].heading に §N 形でない見出しがある (番号導出不能・fail-closed)" >&2
  echo "  headings: $(q '.sections[].heading' | tr '\n' '|')" >&2
  exit 2
fi
SEC_LAST_NUM="$(printf '%s\n' "$SEC_NUMS" | tail -n 1)"
# 静的 2 band (前方照会 / 用語集) は最終 section の §番号の ★次 / ★次々。
STATIC_NUMS=("$((SEC_LAST_NUM + 1))" "$((SEC_LAST_NUM + 2))")
STATIC_HEADINGS=("§${STATIC_NUMS[0]}. ${STATIC_HEADING_TAILS[0]}" "§${STATIC_NUMS[1]}. ${STATIC_HEADING_TAILS[1]}")
# ★lockstep 長さ guard: 3 配列 (id / tint / kicker) の長さがずれると以降の zip 突合が ★短い方で静かに切れる。
[[ "${#PRESENTATION_WRAPPER_IDS[@]}" -eq "${#PRESENTATION_WRAPPER_BAND_TINTS[@]}" \
   && "${#PRESENTATION_WRAPPER_IDS[@]}" -eq "${#STATIC_KICKERS[@]}" \
   && "${#PRESENTATION_WRAPPER_IDS[@]}" -eq "${#STATIC_HEADING_TAILS[@]}" ]] \
  || { echo "verify-srs-verification: ★提示層 wrapper の lockstep 配列長が不一致 (id/tint/kicker/heading・fail-closed)" >&2; exit 2; }
# ★静的 band §番号の ★契約非依存 pin (0/0 恒真封鎖の同族): 上の導出は contract の見出しを根とするため、
#   contract から section を足し引きすると期待も実測も同時に動き ★導出の破れを検出できない。 実測 literal で挟む。
chk "静的 band §番号 (前方照会) == $FZC_STATIC_BAND_NUM_LO (契約非依存 pin)" "$FZC_STATIC_BAND_NUM_LO" "${STATIC_NUMS[0]}"
chk "静的 band §番号 (用語集) == $FZC_STATIC_BAND_NUM_HI (契約非依存 pin)"   "$FZC_STATIC_BAND_NUM_HI" "${STATIC_NUMS[1]}"

# ============================================================================
# arm 0. ★提示層 marker が ★非描画領域に退避していない (hiding クラスの negative pin)
# ============================================================================
# 後段の全 census / 列突合は $BODY_LIVE を subject にするため、 コメント / script へ包む隠蔽は ★件数減として
# 既に落ちる。 本 arm はそれを ★単独で読める形 に外出しして「どの marker が隠されたか」を名指しする
# (件数 arm だけだと「削除」と「隠蔽」が同じ診断になり、 退行の原因究明が読み手に委ねられる)。
# ★恒真封鎖: hidden==0 だけを撃つと ★marker が 1 個も無い artifact でも自明に成立する。 live 側の非空を
#   ★同じ chk の中で束ねて要求する (実測: assembler 出力の <!-- は 0 件・<script> は JSON-LD 1 本のみ、
#   landed canonical は folio build の chrome comment 6 個を持つが提示層 marker を内包しないため 0/0 にならない)。
echo
echo "--- arm 0: 提示層 marker の非描画領域 (comment / script) 退避 0 件 ---"
PRESENTATION_MARKERS=(
  'data-component="chapter-deck-band"' 'data-component="cross-doc-ref-chip"'
  'data-component="ears-requirement-row"' 'data-component="spec-machine-fold"'
  '<span class="rf-gloss">' '<span class="rq-prio rq-prio-' '<p class="rq-plain">'
  '<section id="forward-refs">' '<section id="glossary-terms">'
)
for _m in "${PRESENTATION_MARKERS[@]}"; do
  _nraw="$(grep -oF -- "$_m" "$BODY" | wc -l | tr -d ' ')"
  _nlive="$(grep -oF -- "$_m" "$BODY_LIVE" | wc -l | tr -d ' ')"
  _st="hidden=$((_nraw - _nlive))"
  if [[ "$_nlive" -gt 0 ]]; then _st="$_st live-nonzero"; else _st="$_st live-ZERO"; fi
  chk "非描画退避なし: $_m" "hidden=0 live-nonzero" "$_st"
done

# ============================================================================
# arm 1. ★章帯の巨大番号 == 見出しの節番号 (ADR-0054 §2.2)
# ============================================================================
# core band() は文書内 ★連番 (01..07) を emit するが pack-local wrapper (band_num) が §番号へ書き換える。
# 改修前は .num を ★一切 pin していなかったため番号体系の drift が全 gate を素通った。
echo
echo "--- arm 1: 章帯 §番号一致 ---"
chk "chapter-deck-band == sections + 2 (静的 band 2 本)" "$((NSEC + 2))" \
  "$(occ 'data-component="chapter-deck-band"' "$BODY_LIVE")"
chk "band .num 列 == 見出しの節番号 (heading 由来・連番でない)" \
  "$(printf '%s\n' "$SEC_NUMS"; printf '%s\n' "${STATIC_NUMS[@]}")" \
  "$(grep -oE '<span class="num">[^<]*</span>' "$BODY_LIVE" | sed -E 's#<span class="num">([^<]*)</span>#\1#')"
# ★空 .num の defective artifact 封鎖 (assembler の代入形 guard / band_num の数値 guard と対の ★生成物側 pin)。
chk ".num は全て数値 (空 num の defective artifact 封鎖)" "0" \
  "$(grep -oE '<span class="num">[^<]*</span>' "$BODY_LIVE" | grep -cvE '<span class="num">[0-9]+</span>')"

# ============================================================================
# arm 2. ★提示層 wrapper 2 本 (章化) + 静的 band の tint / kicker / 見出し逐語
# ============================================================================
# 前方照会 / 用語集は従来 section で包まれず bare band() だったため「章としての到達可能性」を持たなかった。
# ★id は番号なし canonical token・★class は付けない (normative/informative census を不変に保つ)。
echo
echo "--- arm 2: wrapper 章化 + band tint / kicker / 見出し逐語 ---"
sec_ids="$(grep -oE '^<section id="[^"]*">' "$BODY_LIVE" | sed -E 's#^<section id="([^"]*)">#\1#')"
chk "section anchor 列 == sections[].anchor + wrapper 2 本 (順序)" \
  "$( { q '.sections[].anchor'; printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$sec_ids"
for _i in "${!PRESENTATION_WRAPPER_IDS[@]}"; do
  _w="${PRESENTATION_WRAPPER_IDS[$_i]}"
  # (a) 実在 (章化が落ちれば上の anchor 列も落ちるが、 ★単独でも読める形で撃つ)
  # ★occurrence 計数 (errata-1 E-1): 行計数だと ★同一行に 2 個目の wrapper 開きタグを append しても 1 のまま
  #   素通る。 開きタグの ★出現回数 を数えて重複注入を落とす。
  chk "提示層 wrapper <section id=\"$_w\"> が 1 個" "1" \
    "$(occ "<section id=\"$(esc "$_w")\">" "$BODY_LIVE")"
  # (b) ★class を持たない (census 不変の構造要件・class 付き変種の混入を封鎖)
  chk "提示層 wrapper '$_w' に class 属性が無い (census 不変)" "0" \
    "$(grep -cE "<section id=\"$(esc "$_w")\"[^>]*class=" "$BODY_LIVE")"
  # (c) ★開口隣接 pin: wrapper の直後に ★当該 tint の band が来る (別章 band の付け替え封鎖)
  chk "wrapper '$_w' の開口直後に tint=${PRESENTATION_WRAPPER_BAND_TINTS[$_i]} の band が隣接" "1" \
    "$(W="$(esc "$_w")" T="${PRESENTATION_WRAPPER_BAND_TINTS[$_i]}" perl -CSD -0777 -ne '
        my $w=quotemeta($ENV{W}); my $t=quotemeta($ENV{T});
        my $n=0; $n++ while /<section id="$w">\s*<section data-component="chapter-deck-band" class="[^"]*\b$t\b[^"]*"/g;
        print $n;' "$BODY_LIVE")"
done
# ★band kicker 列 (全 band 横断・document 順)。 先頭 NSEC = sections[].kicker / 末尾 2 = 静的リテラル。
chk "band kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" \
  "$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY_LIVE")"
# ★band tint 列 (errata-1 E-5)。 ★本文 5 章の tint は改修前 ★無 pin だった — wrapper 2 本は「開口隣接 pin」で
#   tint まで逐値要求しているのに、 ★本文 band は kicker / heading しか見ておらず ★色帯の付け替えが素通った
#   (kicker も heading も変えずに tint だけ差し替える形は他のどの arm にも掛からない)。
#   ★期待列は contract .sections[].tint + wrapper 2 本の静的 tint を連結 (kicker 列 chk と同型)。
#   ★生成物側は core band() が emit する class="… tint-<name> …" の tint token を document 順で取る。
chk "band tint 列 == sections[].tint + wrapper 静的 tint 2 件 (順序)" \
  "$( { q '.sections[].tint'; printf '%s\n' "${PRESENTATION_WRAPPER_BAND_TINTS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<section data-component="chapter-deck-band" class="([^"]*)"/g){ my $c=$1; print "$1\n" if $c =~ /\btint-([a-z]+)\b/; }' "$BODY_LIVE")"
# ★h2 見出し列 (section + 静的 band 2 本)。 静的 band の見出しは「§N. <本文>」形で §N は contract 由来導出。
chk "h2 見出し列 == sections[].heading + 静的 band 2 件 (順序)" \
  "$( { q '.sections[].heading'; printf '%s\n' "${STATIC_HEADINGS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<h2>[^<]*</h2>' "$BODY_LIVE" | sed -E 's#<h2>([^<]*)</h2>#\1#')"
# ★総数 pin (上の列突合は先頭一致では切れないが、 大文字 <H2 等の変種注入を数で挟む)。
chk "h2 総数 == NSEC+2 (band h2 切詰・大文字注入の盲点是正)" "$((NSEC+2))" \
  "$(grep -oiE '<h2\b' "$BODY_LIVE" | wc -l | tr -d ' ')"

# ============================================================================
# arm 2C. ★章 (契約章 + 提示層 wrapper) の ★containment — 章化の ★実質 (folio-3zr4 Leg C)
# ============================================================================
# ★上の arm 2 (a)(b) と section anchor 列は ★開きタグの実在 しか見ない。 ゆえに <section id="forward-refs"></section>
#   と即閉じ、 band / chapbody / ref-grid を章の ★外 へ押し出す ★hollow section 改竄が ★タグ均衡を保ったまま
#   全 gate を素通る (★本 pack でも実弾再現済: 契約章 hollow で rc=0 / 0 FAIL)。 章化 (ADR-0054 §2.2) が
#   約束するのは「id を持つ section が在ること」ではなく「その章の中身が ★その章に属すること」ゆえ、
#   帰属を ★入れ子 で pin する。
#   (i) ★開口隣接 pin — 章の開きタグの ★直後 (間に ★異物なし) が「その章の band」(§番号 逐値 + tint 逐値)。
#   (ii) ★region 占有 pin — 章の対応閉じタグまでの region で band == 1 / chapbody == 1 (欠落・重複・他章の紛れ込み)。
#   (iii) ★1 段内側の再帰 — wrapper では さらに chapbody 開口直後が payload container (ref-grid /
#         glossary-term-table) であること、 container が chapbody 内に 1 個、 payload (chip / .grow) の
#         ★全数 が ★container の中 に在ること。 (i)(ii) だけだと「chapbody を空で閉じ payload を sibling へ出す」
#         「container を即閉じし payload を外へ出す」 hollow 化が 1 段 / 2 段 内側で ★そのまま再演する
#         (defect 原理「開きタグが在る は 中身がそこに属する を意味しない」は ★階層ごとに 撃つ必要がある)。
#   ★期待値は contract 由来 (|references| / |glossary| / sections[].anchor / sections[].tint / 見出し由来 §番号) ゆえ、
#   生成物実測への after-the-fact 合わせ (恒真化) にならない。 ★契約章 5 本にも同じ (i)(ii)(iii) を課す
#   (2 id の手書き列挙に留めると同一 DOM shape を持つ残り 5 章が無防備 = partial-enumeration trap。 駆動は contract の section census)。
# ★★srs-verification 固有の構造差: s2-done-condition-req は ★machine_blocks が 0 本 (他 4 章は 1 本) — chapbody 直下の
#   完全子列を組む三項 (machine_blocks>0 なら fold 1 を足す) の ★0 側分岐 が実データで踏まれる 初の pack である。
#   期待列は contract から導出するため literal を焼かずに吸収される (実測確認済)。
#
# ★★★subject は ★$BODY である ($BODY_LIVE ではない・admin 裁定 srs 条項 (1)) — 本 script の他 arm との ★非対称。
#   本 script の census / 列突合はすべて ★$BODY_LIVE (非描画領域を落とした view) を subject に取るが、
#   ★containment だけは 範型と同じ ★$BODY を subject にする。 理由 (load-bearing):
#   (a) make_body_live は allowlist 外タグ / bogus comment / 未閉じ RAWTEXT を見ると ★空の live view を返す
#       fail-closed 設計であり、 その run では ★ほぼ全 arm が巻き添えで赤くなる。 containment の tokenizer 系 arm
#       (自己閉じ div / void による深さ 1 打ち切り / foreign breakout …) の per-shape MK を $BODY_LIVE 上に置くと、
#       「当該 arm が単独で赤くなった」ことを ★示せない — 敵対 suite 自身の集計規律 (test-adversarial-srs-verification.sh
#       冒頭 ★集計規律 (1)「fail-closed run の [FAIL] は kill に数えない」) に ★違反する mutant しか作れなくなる。
#   (b) containment 自身が ★HTML5 同型 tokenizer を内蔵し、 非描画容器 (コメント / RAWTEXT / bogus comment /
#       foreign) を ★実 parser と同型に 扱って region を切り出す。 隠蔽容器への耐性は live view からの供給ではなく
#       ★probe 内部の走査規律で担保される (下記 parser-differential 封鎖)。
#   ★既存の $BODY_LIVE arm 群は ★1 本も置換せず 残置し (fence「既存 arm の保護」)、 containment は ★$BODY 上の
#   ★別節として additive に足す。 ★2 view の役割分担は本 script 冒頭の「2 つの body view の役割」節に開示済。
#
# ★★per-shape mutation-kill (test-adversarial-srs-verification.sh・★全 ★構造クラス が 1 つ以上の実弾で anchor される
#   — ★arm instance 単位ではない。 per-instance の残差 24 本は敵対 suite ヘッダ (a') に逐語開示):
#   ★★本一覧は敵対 suite の ★expect_fail ラベルを実測して再生成した もの (裁定 srs 条項 (2)「追加 arm ごとに
#   per-shape MK + 弁別 + kill map 再測とヘッダ注記更新」)。 ★番号が stale 化しないよう、 敵対 suite の
#   ★MECHPIN 節 に「本 script が言及する MKC 番号の集合 ★== suite の MKC ラベル集合」の静的 pin を置いた
#   (旧番号のまま残す / 新 arm を書き落とす の ★どちらでも 赤くなる = false record の構造封鎖)。
#   MKC-1 契約章の hollow 化 / MKC-2 提示層 wrapper (forward-refs) の hollow 化 / MKC-2b 同 (glossary-terms・
#   payload が chip でなく .grow 行の ★別構造クラス) / MKC-3 開口と章帯の間への異物挿入 (開口隣接 pin の
#   ★位置成分) / MKC-4 wrapper band tint の逐値付け替え (同 pin の ★識別成分・assembler literal 由来) /
#   MKC-4b 契約章 band tint の付け替え (★別 instance = 期待値の源が contract sections[].tint) / MKC-5 band
#   §番号の逐値書換 (同 pin の ★節同一性成分) / MKC-6 章帯の重複注入 (region 占有の上限側) / MKC-7 ★chapbody
#   だけを章の外へ (band 隣接は保持 = region 占有 pin が単独発火する向き) / MKC-8 章要旨を残した章本文の
#   sibling 押し出し (章直下 2 子) / MKC-9 章本文の band subtree への退避 (kids を 2 に保つ向き) /
#   MKC-10 章本文の 別章 chapbody への移送 (document 順を保ち他の probe 値を一切動かさない形) /
#   MKC-11 ★filler 付き machine-fold 退避 (★空 <div> 1 個の filler で ★どのレベルの子数も動かさない形 =
#   「数だけ束縛して identity を束縛しない」errata の per-shape 封鎖) / MKC-12 chapbody 開口と器の間への
#   異物挿入 / MKC-13 契約章 s0 の chapbody 空化 + 章本文 sibling 押し出し (1 段内側の器占有 pin) /
#   MKC-14 payload container の文書内重複 (器の重複 = 逃げ場) / MKC-15 ★hollow ref-grid (chip 全数を器の外へ) /
#   MKC-16 ★hollow glossary-term-table (.grow 全数を器の外へ = MKC-15 と別構造クラス) / MKC-17 コメント密輸 /
#   MKC-18 script (RAWTEXT) 密輸 / MKC-19 属性値内の生 `>` 密輸 / MKC-20 bogus comment (`<! … >`) 密輸 /
#   MKC-21 escapable RAWTEXT (textarea) 密輸 / MKC-22 ハイフン入り要素名 (`<section-x>`) 密輸 /
#   MKC-23 comment end bang (`--!>`) / MKC-24 abrupt-closing comment (`<!-->`) / MKC-25 `<!--->` (comment 終端
#   分岐 2 の単独 teeth) / MKC-26 RAWTEXT 終了タグの要素名境界 (`</textareax>`) / MKC-27 foreign content
#   (svg subtree) 内の擬似タグ / MKC-28 div の自己閉じ構文 / MKC-29 void 要素 2 個による深さ 1 計数の打ち切り /
#   MKC-30 foreign root (svg) を depth-1 filler にした完全子数マスク / MKC-31 foreign 内の any-other-end-tag に
#   よる外側 section 閉鎖 (breakout) / MKC-32 foreign 内の breakout 開始タグによる器の重複 / MKC-33 svg 包みに
#   よる人間層 block の章外 relocation / MKC-34 unquoted 属性値への quote 混入 (★幽霊 marker の ★値 state) /
#   MKC-35 attribute-name state への quote 混入 (同 ★名前 state) / MKC-36 タグ境界 quote 走査の state 非同型に
#   よる ★実在する閉じタグの隠蔽 / MKC-37 文字参照で綴った marker による器の重複 / MKC-38 ★rq-list ごと退避 +
#   空 filler / MKC-39 ★tbl-wrap ごと machine-fold へ退避 + 空 filler (MKC-38/39 が ★器自身の文書 census 側) /
#   MKC-40 ★hollow block wrapper (tbl-wrap 据置で中の table だけ fold へ) / MKC-41 ★hollow rq-list (器据置で
#   中の要件 row だけ callout subtree へ) (MKC-40/41 が ★器中身の占有側) /
#   MKC-42 余剰 class トークン付き marker による器の重複 (★class 照合粒度の parser-differential・docct 側) /
#   MKC-43 同 payload 側 (`class="grow zz"` の捏造行 = pay) / MKC-44 同 XSPEC 経路 (`class="tbl-wrap dup"` = xdoc)
#   — MKC-42/43/44 は ★$val_match の token 粒度化 が封鎖する ★別々の消費経路 — /
#   MKC-45 章要旨 callout の器の重複 (docct の ★N>1 分岐・期待値が contract 章数由来) / MKC-46
#   glossary-term-table の器の重複 (docct の ★data-component 軸 instance) (MKC-45/46 は MKC-14 と同じ
#   「器の重複 = 逃げ場」shape の ★per-instance 未着弾 を解消する実弾) /
#   MKC-22b ★アンダースコア入り要素名 (`<div_x>`) の幽霊タグで機械層 fold を chapbody の外へ移送 (MKC-22 の
#   ハイフンと ★別 char class = tag name state 非同型の取りこぼし側・folio-3zr4.3 self-review) /
#   MKC-47 span 担体の捏造 payload 行 (`<span class="grow">` = 担体要素名の非同型・pay 経路) / MKC-48 同 docct 経路
#   (`<span class="ref-grid">`) / MKC-49 同 xdoc 経路 (`<span class="tbl-wrap">`) — MKC-47/48/49 は ★marker の
#   担体要素名 を fail-closed 固定する対 assert が封鎖する ★別々の消費経路 (MKC-37 / MKC-42-44 と同一 defect
#   family の ★第 4 vector) — / MKC-50 ★hollow 章要旨 callout (器据置で中身 p.sec-se だけ同章 fold へ) /
#   MKC-51 章要旨の ★別章 graft (MKC-50/51 が契約章の ★器中身の占有側 = Leg B errata-1 と同一クラス) /
#   MKC-C1 ★弁別対照 (kill ではなく
#   ★陰性対照 = 上記のうち live view も巻き添えで落とす mutant の kill が genuine であることを isolate する)
#   — ★kill map (arm → MKC) は本 pack の敵対 suite で ★実測して 対応付ける (Leg A / Leg B の CT 番号への
#   lockstep は無い = 番号は ★pack-local)。
# ★★「実弾で anchor される」の ★射程 (宣言 == 実能力・folio-3zr4.3 self-review round-2 で ★narrow):
#   (a) 上の主張が掛かるのは ★生成物 (artifact) の改竄で落ちる arm の ★構造クラス (章 id / §番号 / tint を
#   正規化した label 集合・containment では ★25 クラス = 正規化 27 − 機構健全性 2) であり、 ★全数が「単独発火の実弾」を
#   1 本以上持つ (admin gate errata-1 後の再測。 章帰属 2 クラス 〔sese / mflab〕 は MKC-52 / MKC-53 が撃つ)。
#   (a') ★arm instance 単位では ★未着弾が残る — 集計規律 (1) を機械適用した独立再測で、 artifact 改竄で落ちうる
#   containment arm ★81 本 (★distinct chk label 単位 = arm 2C の OK 行 87 − 機構健全性 2 − docct の同一ラベル 4 重複) のうち
#   ★24 本 (s1-boundary-model の 8 / s4-references の 7 / s3-coverage-rtm の 7 / s2-done-condition-req の 1 /
#   s0-reader-guide の 1) は ★mass-collateral run でしか赤くならない。 具体名と再測手順は敵対 suite ヘッダの
#   (a') に逐語開示 (「全 arm が実弾で anchor される」と instance 単位で読まないこと)。
#   (b) ★検査機構そのものの健全性 arm — 「駆動表が全章を覆う」「probe が全章分の
#   実測を出力」 — は artifact をどう改竄しても落ちず (script 改変でしか落ちない)、 敵対 suite の構造上
#   per-shape MK を持てない。 これらは test-adversarial-srs-verification.sh の ★MECHPIN 節 (tracked 静的 pin) が
#   arm の実在と期待値の導出形を押さえる = ★MK 対象外だが担保はリポに残る。
# ★★実弾を構成できない shape の ★開示 (silent 欠落封鎖): ★同章内の 器 → 器 payload 再配分 (器 2 本以上の章で
#   1 本目へ寄せ 2 本目を空の器として残す形・Leg A/B が実弾で撃った CT46/CT47 相当) は、 srs-verification contract
#   では ★同型の器が 2 本以上ある章が 0 件 (実測: table は s3-coverage-rtm に 1 本・requirements は
#   s2-done-condition-req に 1 本) ゆえ ★構成できない。 期待値を ★器ごとの個数列 (xpayseq) にしてあるので
#   shape 自体は閉じている が、 ★実弾で撃った証拠は無い (deduced)。 「撃った」と書かない。
#
# ★★実態開示 (scope・c5r.2 回避表記封鎖の規律): 本 containment pin が閉じるのは ★人間層 (chapbody 直下) の
#   ★block 粒度 relocation クラス で、 かつ ★下の 4 前提 (chk 群直上に逐語) が成り立つ範囲に限る。
#   ★前提 (0) = 「depth-1 marker が 器中身 pin で個数拘束される」は ★構造上の要 である:
#   srs-verification contract の block type 実測 2 種 ([table]=div.tbl-wrap / [requirements]=div.rq-list) は
#   ★どちらも wrapper class 自身の文書 census を持たない (本 script の census が数えるのは ★内側 の
#   ears-requirement-row であり tbl-wrap / rq-list ではない) ため、 器中身の占有 pin と器自身の文書 census が
#   無いと「空の器を filler に残し中身を machine-fold へ移す」形が ★全 arm 素通り する (Leg B = relations で
#   実測された errata-1 クラス)。 本 pack は marker↔census 突合を ★実装前に 行い、 2 型とも最初から
#   BLOCK_WRAPPER_SPEC へ登録して閉じている。
#   ★射程外 1 = ★機械層 (machine_blocks) の cross-fold 移動 — machine_blocks を ★document 順を保ったまま
#   別 section の machine-body へ移す形は ★未検査 である (3 レベル pin は fold の内側へ届かない)。 加えて
#   ★srs-verification には機械層 round-trip arm 自体が無い (本 script は提示層 shape の部分 verifier) ため、
#   sibling pack にある「順序変化だけは見る」層すら無い。 ★受け皿 = folio-e706。
#   ★射程外 2 = ★sub-block 粒度 (block の ★内部 のテキスト・要素の移動) — prose slot 充填 + fidelity ceiling の
#   領分。 「あらゆる relocation を閉じた」とは書かない (宣言 == 実能力)。
#   ★frozen census は ★引き続き 存在しない (folio-vhew) — 本節では ★新設しない (KNOWN_SPECS 未登録の census arm は
#   常時 dormant な fail-open false record になる・冒頭 out-of-scope に既述)。
#
# ★★parser-differential 封鎖 (r8k / folio-wq4 の再発クラス): region 切り出しを $BODY の ★生テキストへの
#   素朴な /<(\/?)section\b[^>]*>/ 走査で行ってはならない。 make_body は ★コメント本文と <script> 中身を
#   verbatim 保持する (lib/verify-common.sh) ため、 コメント内 / script 内に書いた `<section>` 文字列が
#   ★実要素として深さに加算され、 region が対応閉じタグを越えて ★over-slice する。 また `[^>]*` は引用符を
#   認識しないため、 属性値内の生 `>` (`<p title="x><section>y">`) でも同じ over-slice が起きる。
#   ★いずれも「章本文を章の外へ出したまま rc=0 / 0 FAIL」を再現する shape ゆえ、 走査は ★HTML5 の
#   tokenizer 規則に ★寄せた 走査で行う: コメント終端は HTML5 comment state と同型 (abrupt close / `<!--->` /
#   `-->` と `--!>` の早い方)、 bogus comment / markup declaration は `>` まで無視、 RAWTEXT と escapable
#   RAWTEXT (10 要素) の中身は ★タグとして数えず 終了タグは ★要素名境界 を課す、 foreign content (svg / math)
#   の ★root は 深さ 1 の子として 1 計上し (実 DOM でも root は親の子要素) ★subtree の中身は数えない が
#   ★読み飛ばさずに 走査して 実 parser が foreign を抜ける 2 形 (breakout 開始タグ / any-other-end-tag) を
#   ★err で拒否する、 タグ境界は 引用符を ★HTML5 の attribute-name / attribute-value state に ★同型に
#   (quote が値を開くのは `=` の直後だけ) 認識して 決定し、 要素名は ★HTML5 の tag name state と ★同型 に
#   (終端は tab / LF / FF / CR / space / `/` / `>` の ★7 文字だけ・それ以外は全て名前文字) 取る
#   — ★許容文字を列挙する 旧形 (`[a-zA-Z0-9-]*`) は partial-enumeration で、 `<div_x>` 等が prefix 誤認され
#   fail-open した (folio-3zr4.3 self-review で実弾 verified・per-shape MK = MKC-22 〔ハイフン〕/ MKC-22b 〔`_`〕)。
#   占有数も 生テキスト grep でなく ★tokenize 済タグの属性一致 で数える (属性値に marker 文字列を
#   紛れ込ませた計数水増しの封鎖)。 ★照合粒度は ★属性ごと: ★class は CSS / DOMTokenList と同型に
#   ★空白区切り token 集合のメンバシップ、 それ以外 (id / data-component …) は ★逐値一致 ($val_match)。
#   ★これは folio-3zr4.3 self-review で ★実弾 verified の fail-open の是正である — class を逐値一致で
#   照合していた旧実装では `<div class="ref-grid decoy">` / `<div class="grow zz">` が ★実 DOM では器 /
#   payload そのもの (CSS 適用・人間に描画される) なのに probe から不可視になり、 上限型 == の arm
#   (docct / pay / xdoc) が ★silent PASS した (per-shape MK = MKC-42 / MKC-43)。
#   ★宣言の射程: 属性の走査は タグ名直後から ★attribute-name state →
#   attribute-value state を ★順に消費する 逐次形であり、 ★名前 state は `"` / `\x27` / `<` を ★名前文字として
#   取り込む (HTML5 同型)。 これで 「実 DOM に無い marker を probe が拾う」★幽霊 marker クラス は ★値 state と
#   ★名前 state の ★両方 で塞がる。 ★文字参照 も ★解決する (数値 + 名前付き 6 種・表に無い名前付きは err = fail-closed)。
#   ★undercount を「probe が数え落とす向き = 常に fail-closed 側」と ★一般化してはならない — 期待値が
#   ★上限型 == の arm (docct) では 数え落とし = ★silent PASS である (Leg B で実測 verified)。
#   方向は ★arm の期待値の型に依存する。
#   ★★宣言の射程 (== 実能力): これは「HTML5 parser の ★完全実装」ではない — 本 tokenizer が同型化しているのは
#   ★region 切り出しに効く状態 (上記) + ★属性 name/value state + ★属性値の文字参照 に限られ、 挿入位置補正
#   (in-body insertion mode の implied end tag / foster parenting 等) は ★モデルしていない。
#   それらに依存する差分が将来見つかりうる前提で、
#   genuine assembler が emit しない shape (未閉じ / div・section の自己閉じ構文) は ★err で拒否する
#   fail-closed を併用する (arms race を全面 parser 実装へ広げず、 ★穴が開いたら loud に落ちる 側へ倒す)。
# ★★移植元と ★依存の所在 (false record を作らない): 本 probe は ★範型 verify-verification.sh からの直接
#   移植ではなく、 ★verify-spec.sh (Leg A・folio-3zr4.2 land 済 = ★verify-relations.sh (Leg B) 由来の
#   errata 一式を含む形) の probe を ★逐語 移植したものである。 すなわち範型に ★無い 7 つの fail-closed を
#   含む: (g) タグ境界の attribute state 同型化 + 引用値直後の fail-closed (a) count_kids の打ち切りを err
#   (`unclosed-child-*`) へ倒す (b) foreign content の stack 追跡 + depth-1 計上 (`foreign-breakout-*` /
#   `foreign-at-depth1-*`) (c) $attr の unquoted 値 char class 同型化 (d) $attr の ★逐次消費化 =
#   attribute-name state 同型 (e) 属性値の ★文字参照解決 + 表外参照の err (`unresolved-charref-*`)
#   (f) chapbody 直下を ★数 でなく ★marker 列 で束縛 (filler 置換 relocation)。 ★裏返しの事実 も開示する:
#   範型 verify-verification.sh には これらが ★無い ので、 対応する fail-open は ★範型側に残っている。
#   範型の実態開示コメント (verify-verification.sh:292-301) は 移植 leg の land により段階的に ★stale 化する が、
#   範型は 本 leg の fence で ★1 byte も触れない — ★是正の受け皿 = Leg Z (folio-3zr4.4・admin 単独 commit)。
#   ★開示済み残差 ② — foreign content (svg / math) の ★中 の非同型。 現実装は subtree を ★本体と同じタグ走査で
#   追い、 breakout 開始タグ (%FOREIGN_BREAKOUT) と stack に無い終了タグ を err にするので、 3 vector と、
#   root 計上が ★逆に開けてしまう depth-1 filler マスク (`foreign-at-depth1-*` で対に封鎖) は塞がっている。
#   ★残るのは 「実 parser が foreign を抜ける 規則のうち 本実装がモデルしていないもの」 = (i) SVG script /
#   MathML annotation-xml の integration point (ii) 文字参照 (iii) font の属性条件 (本実装は ★属性を見ずに
#   breakout 扱い = fail-closed 側へ寄せた過剰)。 ★genuine 生成物の svg subtree は path / circle 等の
#   自己閉じのみ (本 pack 実測) ゆえ これらは現時点で ★到達しない が、 「閉じた」ではなく「この範囲で閉じた」と読むこと。
#   ★到達不能な残差の開示 (依存の所在): 属性値内に生 `<` を置く shape は ★上流の make_body が fail-closed で
#   拒否する (raw-lt-in-tag) ため 本走査には到達しない。 ここは「認識しているから安全」ではなく「上流で落ちるから
#   到達しない」であり、 make_body の当該 guard を緩めると ★本走査の前提が崩れる。
#   ★同 (count_kids の打ち切り): count_kids は ★同名深さ計数 ゆえ void 要素が depth-1 に現れると計数がそこで
#   打ち切られる。 これを ★silent に打ち切ると「章本文 block を 1 個 chapbody の外へ出し、 抜けた分の位置に
#   void を 1 個挿す」だけで 3 レベルの完全子数束縛が ★全て素通る。 現在は打ち切りを ★err
#   (`unclosed-child-<要素名>`) へ倒す fail-closed で封鎖している。
#   ★残差の開示 (LOW-20/21 同型): 「void が 0 件だから構成的に安全」ではなく「void が現れたら ★loud に落ちる」
#   であり、 depth-1 に void を持つ genuine shape が将来生じたら本 arm は false FAIL 側へ倒れる
#   (現 artifact の 章 / band / chapbody の depth-1 に void 要素は 0 件 = 実測)。
# ★★lockstep 相手の開示 (二重保守の所在): 本 pin が依存する DOM marker のうち
#   `data-component="chapter-deck-band"` / `<span class="num">` / `<div class="chapbody">` は ★共有 CORE
#   lib/common.sh の band() / band_end() が emit する形であり、 pack-local な assemble-srs-verification.sh ではない。
#   ★CORE 側でこれらの marker 名が変わると本 pin は (tokenizer が属性一致で数えるため) ★静かに 0 件になり得る
#   — その退行は「駆動表が全章を覆う」「probe が全章分を出力」の 2 arm では捕まらず、 章ごとの adj/band/cb が
#   同時に 0 へ落ちる形で ★loud に FAIL する (16 pack 共有ゆえ CORE 改変は本 cell scope 外 = 検出できれば足りる)。
#   属性値そのもの (tint-<値> / §番号) の lockstep 源は contract (sections[].tint / 見出し §N) と
#   PRESENTATION_WRAPPER_BAND_TINTS。
# ---- containment probe: $BODY を 1 度だけ tokenize し、 章ごとの containment 実測値を KV で返す ----
#   入力 PROBE_SPEC = 1 行 1 章の TSV: id \t §num \t tint(空=不問) \t container 属性 \t 値 \t payload 属性 \t 値
#   出力 = "<id>|<key>=<値>" 行 (found/adj/band/cb/cbadj/cont/pay/docct/kids/bkids/cbkids/★sese/★mflab)
#          + "*|err=<tokenizer 診断>"。 ★sese / mflab は ★値 (自由文) を運ぶため '|' / '=' を含みうる —
#          読み出し側 _cp は ★最初の '|' と ★最初の '=' でだけ 分割する (下記)。
#   ★fail-closed: tokenizer が非 genuine 構造 (未閉じタグ / 未閉じコメント / 未閉じ RAWTEXT / 未閉じ foreign /
#   div・section の自己閉じ構文 / foreign subtree からの breakout) を見たら token 列を捨てる → 全章 found=0 と
#   なり下の chk が総崩れ FAIL する。 深さ 1 の未閉じ子 (`unclosed-child-*`) と depth-1 の foreign root
#   (`foreign-at-depth1-*`) は token 列を捨てずに 診断だけ立てる (どちらも err arm が loud に出す)。
containment_probe() { # stdin なし・env PROBE_SPEC / 引数なし
  perl -CSD -0777 -ne '
    my $b = $_; my $n = length($b); my $i = 0; my $err = ""; my @t = ();
    # ★RAWTEXT / escapable RAWTEXT (HTML5): これらの中身は ★テキスト であり、 中の <section> 等は要素にならない。
    #   script / style だけを知っていると title / textarea 等へ入れた擬似タグが ★実タグとして深さに乗り (parser-
    #   differential)、 region が over-slice して containment pin が fail-open する。
    #   ★宣言の射程: plaintext は HTML5 では「以降すべてテキスト」で ★終了タグを持たない 特殊要素であり、
    #   本実装の「`</name>` まで読み飛ばす」処理とは厳密には別である (終端が来なければ err = fail-closed 側へ
    #   倒れる)。 「全 RAWTEXT 系で差が構成的に生じない」とは言えないため、 ここに ★実態を開示して 装わない。
    #   ゆえ、 現れない要素も ★実 parser と同じ挙動 (中身をテキストとして読み飛ばす) で扱えば、 攻撃者がそれらを
    #   注入しても tokenizer と実 DOM の差が ★構成的に生じない (「現れないから拒否」より広く閉じる)。
    #   ★本集合は範型 (verify-verification.sh) からの ★逐語 移植である — inert / LIVE_TAG_OK / %RAWTEXT の
    #   semantics 変更 (手書き拡張を含む) は本 cell の scope 外 (横断裁定の帰属 = folio-1odj)。
    my %RAWTEXT = map { $_ => 1 } qw(script style title textarea xmp iframe noembed noframes noscript plaintext);
    # ★foreign content (svg / math) の ★breakout 開始タグ集合 (HTML5 tree construction "in foreign content" の
    #   開始タグ規則の逐語): これらが foreign subtree の中に現れると 実 parser は ★foreign を抜けて HTML 名前空間へ
    #   戻す (= 中身が実 DOM では HTML 要素として 器の外に出る)。 subtree を丸ごと読み飛ばす実装は これを
    #   ★不可視 にするため、 「svg で包めば containment 9 arm を 1 行で全 bypass できる」 fail-open になる
    #   (実測: `<svg><div class="ref-grid"></div></svg>` で docct が 1 のまま素通る)。 ゆえ ★err で拒否する
    #   (genuine 生成物の svg subtree は path / circle の自己閉じのみ = 本集合と交わらない・実測)。
    #   ★非同型の開示: HTML5 では font は color/face/size 属性を持つときだけ breakout するが、 本実装は
    #   ★属性を見ずに breakout 扱い する (genuine に font は 0 件ゆえ false FAIL は出ない・fail-closed 側へ倒す)。
    my %FOREIGN_BREAKOUT = map { $_ => 1 } qw(b big blockquote body br center code dd div dl dt em embed
      font h1 h2 h3 h4 h5 h6 head hr i img li listing menu meta nobr ol p pre ruby s small span strong
      strike sub sup table tt u ul var);
    my @fs = ();       # ★foreign subtree で開いている要素名 stack (空 = HTML 名前空間)
    while ($i < $n) {
      my $lt = index($b, "<", $i); last if $lt < 0;
      # ★comment の終端は HTML5 の comment state と ★同型 に取る (`-->` 一本終端は非同型)。 実 parser が
      #   ★早く 終端する形を知らないと、 攻撃者は「実 DOM では章の外に在る閉じタグ」を tokenizer にだけ
      #   comment の中身として隠せる。 3 分岐:
      #   (1) `<!-->` = abrupt-closing (直後が `>`) (2) `<!--->` = 直後が `->` (3) 以降は `-->` と `--!>`
      #   (comment end bang) の ★早い方。 未終端は err (fail-closed)。
      if (substr($b, $lt, 4) eq "<!--") {
        my $p = $lt + 4;
        if (substr($b, $p, 1) eq ">") { $i = $p + 1; next }
        if (substr($b, $p, 2) eq "->") { $i = $p + 2; next }
        my $e1 = index($b, "-->", $p);
        my $e2 = index($b, "--!>", $p);
        if ($e1 < 0 && $e2 < 0) { $err = "unclosed-comment"; last }
        if ($e1 < 0 || ($e2 >= 0 && $e2 < $e1)) { $i = $e2 + 4; next }
        $i = $e1 + 3; next;
      }
      my $win = substr($b, $lt, 64);   # 要素名の切り落とし余裕 (最長の HTML 要素名でも十分)
      # ★bogus comment / markup declaration (`<!DOCTYPE …>` / `<!foo>` / `<?xml …>` / `</ >`) — 実 HTML parser は
      #   これらを ★comment として `>` まで捨てる。 素朴に 1 文字進めると中身に書いた `<section>` が ★実タグとして
      #   深さに乗り region が over-slice する。 genuine BODY にも `<!DOCTYPE html>` が実在するため ★err で拒否せず
      #   実 parser と同じ「`>` まで無視」へ寄せる (拒否だと genuine が総崩れする)。
      #   ★未終端 (`>` が来ない) は literal 残置でなく err = fail-closed (下の全 chk が総崩れ FAIL する)。
      if ($win !~ m{^<(?:/?)[a-zA-Z]} && ($win =~ m{^<[!?]} || $win =~ m{^</})) {
        my $e = index($b, ">", $lt + 1);
        if ($e < 0) { $err = "unclosed-bogus-comment"; last }
        $i = $e + 1; next;
      }
      # ★★要素名の終端は HTML5 の ★tag name state と ★同型 に取る (folio-3zr4.3 self-review 是正・実弾 verified):
      #   tag name state が名前を終端するのは ★tab / LF / FF / CR / space / `/` / `>` の 7 文字だけ で、
      #   `_` / `.` / `:` 等は ★名前文字として取り込まれる。 ゆえ ★許容 char class を列挙する 形
      #   (旧実装 `[a-zA-Z][a-zA-Z0-9-]*`) は ★partial-enumeration であり、 列挙から漏れた文字を含む要素名
      #   (`<div_x>` / `</div_x>`) を ★prefix ("div") と誤認して 実 DOM では別要素のものを章の深さに数える。
      #   ★MKC-22 (ハイフン `<section-x>`) が撃っていたのは ★同一 defect family の 1 vector に過ぎず、
      #   アンダースコア等は ★開いたまま だった — 幽霊 `<div_x>` で深さを 1 段稼ぎ 機械層 fold を chapbody の
      #   ★外 へ移送しても rc=0 / 0 FAIL になる fail-open を実弾で再現した (per-shape MK = MKC-22b)。
      #   ゆえ ★終端文字の側を列挙する (= 補集合が名前文字) 形へ揃える — 列挙対象が HTML5 の ★閉じた 7 文字集合に
      #   なるため 取りこぼしが構造的に生じない。 ★$attr 側の要素名 strip (下の逐次消費) は ★同一規律の二重保守
      #   ゆえ ★必ず対で 同じ char class を使う。
      #   ★$win は 64 byte 窓ゆえ 名前がその窓を越えると ★切り詰まる (切り詰め名は開き / 閉じで同一の prefix に
      #   なるため 深さ計数自体は整合するが、 「probe が見る名前」と実 DOM の名前がずれた状態を silent に
      #   通さない)。 ★err (`overlong-tag-name`) で fail-closed する — genuine の最長要素名は 7 文字 (section・実測)。
      if ($win =~ m{^<(/?)([a-zA-Z][^\t\n\f\r />]*)}) {
        my $cl = $1; my $nm = lc $2;
        if (length($win) >= 64 && 1 + length($cl) + length($2) >= length($win)) { $err = "overlong-tag-name"; last }
        # ★タグ境界も HTML5 の tokenizer state に ★同型 に取る (errata 3・本 cell で封鎖): 旧実装は state を
        #   持たず `=` を伴わない `"` も ★quote 開始 として扱ったため、 genuine タグへ ` x=1 "></section>"` を
        #   1 個足すだけで 実 DOM ではそこで閉じる `</section>` を ★quote の中 に隠せた (containment 9 arm の
        #   ★1 行 bypass・Leg B = relations で実測 verified = 封鎖前 rc=0 / 0 FAIL)。 実 parser では before/after-attribute-name
        #   state の `"` は ★属性名文字 (parse error だがタグは閉じない) ゆえ、 その後の最初の `>` が終端する。
        #   state: 0 = attribute-name 側 / 1 = before attribute value (直前が `=`) / 2 = double-quoted value /
        #   3 = single-quoted value / 4 = unquoted value / 5 = after-attribute-value(quoted)。
        #   ★quote が値を開くのは ★state 1 だけ。 unquoted 値中の `"` も ★値の一部 (char class `[^\s>]`) ゆえ
        #   quote を開かない — 下の $attr の ★逐次消費 と同じ規律 (二重保守・MKC-34 / MKC-35 と同じ state 観)。
        #   ★state 5 の fail-closed: 引用値の直後は 空白 / `/` / `>` のみ許す。 HTML5 は それ以外を parse error と
        #   して ★属性名へ 倒すが、 その差を模す代わりに ★genuine assembler が emit しない shape として err にする
        #   (`<div a="1"="x>y">` 形で `>` を隠す 逃げ道 を構成的に塞ぐ = arms race を広げず fail-closed へ倒す)。
        my $j = $lt + 1 + length($cl) + length($2); my $st = 0; my $gt = -1;
        while ($j < $n) {
          my $c = substr($b, $j, 1);
          if ($st == 2) { $st = 5 if $c eq q{"} }
          elsif ($st == 3) { $st = 5 if $c eq "\x27" }
          elsif ($st == 5) {
            if ($c =~ /[\t\n\f\r ]/ || $c eq "/") { $st = 0 }
            elsif ($c eq ">") { $gt = $j; last }
            else { $err = "bogus-after-quoted-value-$nm"; last }
          }
          elsif ($st == 4) {
            if ($c =~ /[\t\n\f\r ]/) { $st = 0 }
            elsif ($c eq ">") { $gt = $j; last }
          }
          elsif ($st == 1) {
            if ($c =~ /[\t\n\f\r ]/) { }
            elsif ($c eq q{"}) { $st = 2 }
            elsif ($c eq "\x27") { $st = 3 }
            elsif ($c eq ">") { $gt = $j; last }
            else { $st = 4 }
          }
          else {
            if ($c eq "=") { $st = 1 }
            elsif ($c eq ">") { $gt = $j; last }
          }
          $j++;
        }
        last if $err ne "";
        if ($gt < 0) { $err = "unclosed-tag-$nm"; last }
        # ★$raw は ★この位置で宣言する — 下の foreign content 分岐 (自己閉じ高速路) と self-closing 拒否の
        #   ★両方が読む (宣言が foreign 分岐より後だと分岐側は未定義の package 変数を読んで恒偽 = 死コードになる)。
        my $raw = substr($b, $lt, $gt + 1 - $lt);
        # ★foreign content (svg / math) subtree の ★中: 中の要素は ★HTML 名前空間の要素ではない ので章の深さに
        #   数えない (= @t へ push しない)。 ただし ★読み飛ばすのでなく 走査する — subtree を丸ごと読み飛ばすと
        #   実 parser が ★foreign を抜ける 2 形 が ★不可視 になり、 containment 9 arm が 1 行で全 bypass される
        #   (errata・実測 verified): (A) ★any other end tag — `<svg></section></svg>` は 実 parser では stack を
        #   遡って ★外側の HTML section を閉じる (章本文が丸ごと章の外へ出る)。 (B) ★breakout 開始タグ —
        #   `<svg><div class="ref-grid"></div></svg>` の div は 実 DOM では HTML 名前空間の実要素になる (器の重複)。
        #   ゆえ subtree 内は ★名前 stack で追い、 (A) stack に無い終了タグ / (B) %FOREIGN_BREAKOUT の開始タグ を
        #   見たら err (fail-closed) へ倒す。 per-shape MK = MKC-31 (A) / MKC-32 (B)。
        if (@fs) {
          if (!$cl) {
            if ($FOREIGN_BREAKOUT{$nm}) { $err = "foreign-breakout-$nm"; last }
            push @fs, $nm unless $raw =~ m{/>$};
            $i = $gt + 1; next;
          }
          my $fx = -1;
          for (my $z = $#fs; $z >= 0; $z--) { if ($fs[$z] eq $nm) { $fx = $z; last } }
          if ($fx < 0) { $err = "foreign-breakout-end-$nm"; last }
          splice(@fs, $fx);
          # ★stack が空 = foreign root の対応閉じタグ。 root は ★実 DOM では 親の子要素そのもの ゆえ
          #   ★開き / 閉じ の 1 対を @t へ入れる (下記 root 分岐と対) — 深さ 1 の子として ★1 計上される。
          push @t, { nm => $nm, cl => 1, s => $lt, e => $gt + 1, raw => $raw } if !@fs;
          $i = $gt + 1; next;
        }
        # ★foreign root (svg / math) の ★開きタグ: root 自身は ★HTML tree 上の子要素 ゆえ @t へ push する。
        #   ★push しないと (旧実装) root は深さ 1 の計数へ ★0 として寄与し、 人間層 block を svg で包んで
        #   chapbody の外へ出す relocation が kids / bkids / cbkids を一切動かさずに素通る (実測 verified)。
        #   ★foreign content では `/>` の自己閉じが ★効く (HTML 名前空間と逆) ので、 自己閉じは その場で 1 対にする。
        #   subtree が閉じない場合は err (fail-closed・ループ後段で判定)。
        if (!$cl && ($nm eq "svg" || $nm eq "math")) {
          push @t, { nm => $nm, cl => 0, s => $lt, e => $gt + 1, raw => $raw };
          if ($raw =~ m{/>$}) { push @t, { nm => $nm, cl => 1, s => $gt + 1, e => $gt + 1, raw => "</$nm>" }; $i = $gt + 1; next }
          @fs = ($nm); $i = $gt + 1; next;
        }
        # ★RAWTEXT の終了タグは ★要素名の境界 を課す (実 parser の appropriate end tag 判定と同型)。
        #   `</\Q$nm\E[^>]*>` は `</textareax>` にも一致して ★早期終了 し、 以降の擬似タグを実タグとして
        #   数えてしまう。 名前の直後は空白 / `/` / `>` のみ許す。
        if (!$cl && $RAWTEXT{$nm}) {
          my $rest = substr($b, $gt + 1);
          if ($rest =~ m{</\Q$nm\E(?=[\t\n\f\r />])[^>]*>}i) { $i = $gt + 1 + $+[0]; next }
          $err = "unclosed-rawtext-$nm"; last;
        }
        # ★fail-closed: region 切り出しに使う div / section の ★自己閉じ 構文を拒否する。 HTML では非 foreign 要素の
        #   `/>` は無視される (= 開きタグ) が、 svg / math の ★foreign content 内では自己閉じが効くため、 深さ計数と
        #   実 DOM の差 (parser-differential) を作れる。 genuine な assembler は `<div/>` / `<section/>` を emit しない。
        if (!$cl && ($nm eq "div" || $nm eq "section") && $raw =~ m{/>$}) { $err = "self-closing-$nm"; last }
        push @t, { nm => $nm, cl => ($cl ? 1 : 0), s => $lt, e => $gt + 1, raw => $raw };
        $i = $gt + 1; next;
      }
      $i = $lt + 1;
    }
    # ★foreign subtree が閉じないまま入力末尾に達した = 非 genuine shape (fail-closed)。
    $err = "unclosed-foreign-$fs[0]" if $err eq "" && @fs;
    @t = () if $err ne "";
    # ★属性値の ★文字参照 を解決する (HTML5 の attribute-value における character reference)。
    #   ★errata (方向分析の是正): 旧コメントは「文字参照を解決しないのは probe が数え ★落とす 向き ゆえ
    #   ★常に fail-closed 側」と書いていたが これは ★誤り である — 期待値が「== 1」の ★上限型 arm (docct =
    #   payload container の文書総数) では、 数え落とし = ★追加された容器が invisible になる ため PASS 側へ
    #   倒れる (Leg B = relations で実測 verified: `</body>` 直前へ `<div class="ref&#45;grid"></div>` を足すと 実 DOM の
    #   `.ref-grid` は 2 個 なのに rc=0 / 0 FAIL で全緑)。 「undercount は常に fail-closed」と ★一般化しては
    #   ならない — 方向は ★arm の期待値の型 (== 逐値 / == 上限) に依存する。 ゆえ開示で済ませず ★解決する。
    #   ★射程: 数値参照 (10 進 / 16 進) と 名前付き 6 種 (amp / lt / gt / quot / apos / nbsp) を ★単一 pass で
    #   解決する (単一 pass ゆえ `&amp;lt;` は `&lt;` の ★文字列 になり 二重解決しない = 実 parser と同型)。
    #   ★表に無い名前付き参照 は ★err (`unresolved-charref-*`) へ倒す fail-closed — 部分表による ★過小解決 を
    #   silent PASS にしない (partial-enumeration trap の封鎖)。 genuine 生成物の属性値に現れる参照は
    #   `&lt;` / `&gt;` のみ (実測・上流 esc() は amp/lt/gt/quot しか emit しない) ゆえ false FAIL は出ない。
    #   ★大小文字は ★区別する (`&AMP;` 等は表に無く err)。 lc で寄せると 実 DOM が解決しない綴りを probe が
    #   解決する = ★過剰解決 (幽霊 marker) 側へ倒れるため。 per-shape MK = MKC-37。
    my %CREF_NAMED = (amp => "&", lt => "<", gt => ">", quot => q{"}, apos => "\x27", nbsp => "\xa0");
    my $cref = sub {
      my ($v) = @_;
      return $v if index($v, "&") < 0;
      $v =~ s{&(?:\#[xX]([0-9a-fA-F]+);|\#([0-9]+);|([a-zA-Z][a-zA-Z0-9]*);)}{
        defined $1 ? chr(hex($1))
        : defined $2 ? chr($2)
        : (exists $CREF_NAMED{$3} ? $CREF_NAMED{$3}
           : do { $err = "unresolved-charref-$3" if $err eq ""; "&$3;" })
      }ge;
      return $v;
    };
    my $attr = sub {   # tokenize 済タグ raw から属性値 (最初の 1 個・HTML5 の duplicate 規則) を引く
      # ★走査は「タグ名の直後から attribute-name state → attribute-value state を ★順に消費する」逐次形に取る。
      #   ★errata (旧実装の fail-open・実測 verified): 旧実装は raw タグ文字列を ★どこからでも 属性名 regex
      #   (`[a-zA-Z_:][-a-zA-Z0-9_:.]*\s*=\s*…`) で /g 走査していた。 HTML5 の ★attribute-name state は
      #   `"` / `\x27` / `<` を (parse error だが) ★名前文字として取り込む ため、 `<div class="ref-grid">` を
      #   `<div a""class="ref-grid">` に置換すると 実 DOM の属性は `a""class="ref-grid"` の 1 本だけ
      #   (= class 属性は ★存在しない) なのに、 旧走査は文字列途中の `class="ref-grid"` を拾って
      #   ★実 DOM に無い marker を数えた (rc=0 / 0 FAIL 全緑 = cont / docct / cbadj / pay が揃って幽霊を数える)。
      #   MKC-34 が塞いだのは ★attribute-value-unquoted state だけ で、 ★名前 state は開いたままだった。
      #   ★逐次消費なら 名前 state で `"` を名前へ取り込む ので 幽霊 marker クラス自体が閉じる。
      #   per-shape MK = MKC-34 (値 state) / MKC-35 (名前 state)。
      # ★unquoted 値の char class も HTML5 の ★attribute-value-unquoted state と同型 (空白 / `>` のみが終端。
      #   `/` は ★値に含まれる) に取る。
      my ($raw, $k) = @_;
      my $s = $raw;
      # ★要素名 strip の char class は ★tokenizer 本体 (上の tag name state 同型化) と ★同一規律の二重保守 —
      #   片方だけ直すと 「本体は `<div_x>` を別要素と見るのに $attr は "div" を剥がして残りを属性名として読む」
      #   ずれが生じる。 ★必ず対で 直すこと (folio-3zr4.3 self-review 是正)。
      $s =~ s{^</?[a-zA-Z][^\t\n\f\r />]*}{} or return undef;
      $s =~ s{>$}{};
      my $len = length $s; my $p = 0;
      while ($p < $len) {
        my $c = substr($s, $p, 1);
        if ($c =~ m{[\t\n\f\r /]}) { $p++; next }          # before attribute name state
        my $an = "";
        if ($c eq "=") { $an = "="; $p++ }                  # 名前先頭の `=` は parse error だが名前に入る
        while ($p < $len) {                                 # attribute name state
          my $d = substr($s, $p, 1);
          last if $d =~ m{[\t\n\f\r /=]};
          $an .= $d; $p++;                                  # `"` / `\x27` / `<` も ★名前文字 として取り込む
        }
        while ($p < $len && substr($s, $p, 1) =~ m{[\t\n\f\r ]}) { $p++ }   # after attribute name state
        my $av = "";
        if ($p < $len && substr($s, $p, 1) eq "=") {
          $p++;
          while ($p < $len && substr($s, $p, 1) =~ m{[\t\n\f\r ]}) { $p++ } # before attribute value state
          my $qc2 = $p < $len ? substr($s, $p, 1) : "";
          if ($qc2 eq q{"} || $qc2 eq "\x27") {
            $p++; my $e = index($s, $qc2, $p);
            if ($e < 0) { $av = substr($s, $p); $p = $len } else { $av = substr($s, $p, $e - $p); $p = $e + 1 }
          } else {
            my $st = $p;
            $p++ while $p < $len && substr($s, $p, 1) !~ m{[\t\n\f\r ]};
            $av = substr($s, $st, $p - $st);
          }
        }
        return $cref->($av) if lc($an) eq $k;               # duplicate 規則 = ★最初の 1 個 が勝つ
      }
      return undef;
    };
    # ★★照合粒度は ★属性ごと に決まる (folio-3zr4.3 self-review 是正・parser-differential の ★第 3 vector):
    #   ★class は HTML5 の DOMTokenList / CSS の class selector と同型に ★空白区切り token 集合 の
    #   ★メンバシップ で判定し、 それ以外の属性 (id / data-component …) は ★逐値一致 で判定する。
    #   ★errata (旧実装の fail-open・実弾 verified): 旧実装は class も ★値の逐値一致 で照合していた。
    #   consumer 述語 (CSS `.ref-grid` / `.grow`・srs.css) は class を ★token 集合 として解釈するため、
    #   `<div class="ref-grid decoy">` / `<div class="grow zz">` は ★実 DOM では 器 / payload そのもの
    #   (CSS も適用され人間に描画される) なのに probe からは ★不可視 になった。 期待値が ★上限型 ==
    #   の arm (docct / pay / xdoc) では 数え落とし = ★silent PASS である (「undercount は常に fail-closed」は
    #   ★誤り — MKC-37 と同じ defect family の ★別 vector)。 実測: 器の重複 (MKC-14 が担保するはずの docct) は
    #   ★1 トークン追加で bypass でき rc=0 / 0 FAIL 全緑だった。
    #   ★粒度が ★属性名から自動で決まる 形にしてある (spec 表に「照合粒度」列を足す代わりの構造的解): 将来
    #   class ベースの器 / payload を BLOCK_WRAPPER_SPEC や _CT_CA/_CT_PA へ足しても ★漏れが起きない。
    #   ★false FAIL は出ない — genuine 生成物で本 probe が引く class 値 (chapbody / num / ref-grid / grow /
    #   tbl-wrap / rq-list / tint-*) は ★全て単一トークン (実測)。 多トークンの genuine class
    #   (rq-prio rq-prio-must / badge badge--req / req__ears req__ears--event) は ★本 probe の照合対象に無い。
    #   per-shape MK = MKC-42 (器側 = ref-grid に余剰トークン) / MKC-43 (payload 側 = grow に余剰トークン)。
    my $val_match = sub {  # 属性値 $a が 期待 $v に一致するか (class のみ token 集合メンバシップ)
      my ($k, $a, $v) = @_;
      return ($a eq $v) ? 1 : 0 if $k ne "class";
      for my $tk (split /[\t\n\f\r ]+/, $a) { return 1 if $tk eq $v }
      return 0;
    };
    my $match = sub {  # 開きタグ かつ 要素名一致 かつ (属性 k の値が v に一致・粒度は $val_match が決める)
      my ($x, $nm, $k, $v) = @_;
      return 0 if $x < 0 || $x > $#t || $t[$x]{cl} || $t[$x]{nm} ne $nm;
      return 1 if !defined $k || $k eq "";
      my $a = $attr->($t[$x]{raw}, $k);
      return (defined $a && $val_match->($k, $a, $v)) ? 1 : 0;
    };
    my $region = sub {  # 開きタグ index → (内側 first, 内側 last)。 同名要素の ★深さ で対応閉じタグを決める
      my ($k) = @_; my $nm = $t[$k]{nm}; my $d = 1;
      for (my $x = $k + 1; $x <= $#t; $x++) {
        next unless $t[$x]{nm} eq $nm;
        $d += $t[$x]{cl} ? -1 : 1;
        return ($k + 1, $x - 1) if $d == 0;
      }
      return (-1, -1);
    };
    my $count = sub { my ($lo, $hi, $nm, $k, $v) = @_; my $c = 0; return 0 if $lo < 0;
      for (my $x = $lo; $x <= $hi; $x++) { $c++ if $match->($x, $nm, $k, $v) } return $c; };
    my $first = sub { my ($lo, $hi, $nm, $k, $v) = @_; return -1 if $lo < 0;
      for (my $x = $lo; $x <= $hi; $x++) { return $x if $match->($x, $nm, $k, $v) } return -1; };
    my $gap_ws = sub { my ($a, $x) = @_; return substr($b, $t[$a]{e}, $t[$x]{s} - $t[$a]{e}) =~ /^\s*$/ ? 1 : 0 };
    # ★開きタグ index → 対応閉じタグ ★直前 までの ★生テキスト (章帰属の逐値束縛用・admin gate errata-1 MUST-1)。
    #   ★構造 (件数 / 列) ではなく ★中身の値 を章へ結び付けるために要る: 章間で ★同型の部品を交換 する改竄は
    #   count も marker 列も ★完全保存 する ため 3 レベル束縛では原理的に見分けられない (下の chk 群直上に逐語)。
    #   ★対応閉じタグが region 内に無い / 要素が空 のときは "" を返す (期待値が非空ゆえ ★fail-closed 側へ倒れる)。
    my $inner = sub {
      my ($k) = @_; return "" if $k < 0 || $k > $#t;
      my $nm = $t[$k]{nm}; my $d = 1;
      for (my $x = $k + 1; $x <= $#t; $x++) {
        next unless $t[$x]{nm} eq $nm;
        $d += $t[$x]{cl} ? -1 : 1;
        return substr($b, $t[$k]{e}, $t[$x]{s} - $t[$k]{e}) if $d == 0;
      }
      return "";
    };
    # ★深さ 1 の子 token index を返す (XSPEC = 章 × 追加の器 用・err 副作用なし)。 本体の count_kids は
    #   marker 列収集と err 立上げを同時に担うため章ループ内に閉じており XSPEC からは呼べない。 走査規則は
    #   ★同一 (同名深さ計数・対応閉じが region 内に無ければ打ち切り) で、 打ち切りの loud 化 (unclosed-child-*)
    #   は同じ region を歩く count_kids 側が ★既に 担うため ここで二重に立てない (err の初出を保つ)。
    #   ★深さ 1 に限る のが本質: 「chapbody region 内のどこか」で数えると ★machine-fold (details) の中 に
    #   移した器も region 内に居るため 退避が素通る (errata-1 の (B) shape がまさにこれ)。
    my $kids_idx = sub {
      my ($lo, $hi) = @_; my @o = (); return @o if $lo < 0;
      my $x = $lo;
      while ($x >= 0 && $x <= $hi) {
        if ($t[$x]{cl}) { $x++; next }
        push @o, $x;
        my $nm2 = $t[$x]{nm}; my $d3 = 1; my $y = $x + 1;
        while ($y <= $hi && $d3 > 0) { if ($t[$y]{nm} eq $nm2) { $d3 += $t[$y]{cl} ? -1 : 1 } $y++ }
        $x = ($d3 == 0) ? $y : $hi + 1;
      }
      return @o;
    };
    # ★★marker の ★担体要素名 の fail-closed 固定 (folio-3zr4.3 self-review 是正・★実弾 3 本 verified):
    #   ★defect: 上の $match は ★開きタグ かつ ★要素名一致 かつ 属性一致 を要求し、 主 loop は器 / payload の
    #   要素名を ★literal "div" に固定している (XSPEC は TSV でパラメタ化)。 一方 ★consumer 述語 は ★要素非依存 —
    #   srs.css の `.grow{display:flex;…}` / `.tbl-wrap{border:…}`・assemble-srs-verification.sh の
    #   `.ref-grid{display:flex;…}` は いずれも ★要素修飾の無い class selector である。 ゆえ marker を ★div 以外の
    #   要素 に載せると、 実 DOM では CSS が適用され ★人間に描画される のに probe からは ★不可視 になり、
    #   期待値が ★上限型 == の arm (pay / docct / xdoc) が ★undercount で silent PASS した (実弾: `<span class="grow">`
    #   の捏造用語行 / `<span class="ref-grid">` の器重複 / `<span class="tbl-wrap">` の器重複 が ★3 本とも
    #   rc=0 / 129 [OK] / 0 [FAIL] = clean run と 1 arm も違わなかった)。 ★MKC-37 (文字参照) / MKC-42-44
    #   (class token 粒度) と ★同一 defect family の ★第 4 vector (照合粒度が consumer 述語より ★狭い 側へずれる)。
    #   ★是正の向き: 要素名を ★捨てる のではなく 「spec が定める要素名 ★以外 に marker が現れたら ★落とす」
    #   側へ倒す (spec-table は `<table>`・その他は `<div>` / `<p>` と ★spec ごとに要素名が違う ため、 要素名を
    #   捨てると別の非同型が入る)。 genuine では ★全 marker が単一要素型 (実測) ゆえ false FAIL は出ない。
    #   ★★被覆する marker 集合 の ★開示 (宣言 == 実能力): (1) PROBE_SPEC の 章 id (section) / 器 / payload
    #   (2) PROBE_XSPEC の 器 / payload (要素名は TSV 由来) (3) 主 loop が要素名固定で数える ★構造 marker 3 種
    #   (div.chapbody / section[data-component=chapter-deck-band] / span.num)。 ★probe が要素名を固定して
    #   数える照合は これで ★全数 (= 上の (1)(2)(3) 以外に要素名固定の count/first/match 消費点は無い)。
    #   ★err へ倒す (chk 行を増やさない) のは、 これが「検査の前提が崩れている」型の診断であり
    #   ★tokenizer 構造診断 arm と同じクラスだから (per-shape MK = MKC-47 / MKC-48 / MKC-49 — 消費経路が
    #   pay / docct / xdoc と別々ゆえ 1 本の実弾は他 2 本の穴を証明しない)。
    {
      my @mk = (["div", "class", "chapbody"], ["section", "data-component", "chapter-deck-band"], ["span", "class", "num"]);
      for my $line (split /\n/, ($ENV{PROBE_SPEC} // "")) {
        next unless length $line;
        my @f = split /\t/, $line, -1;
        push @mk, ["section", "id", $f[0]];
        push @mk, ["div", $f[3], $f[4]];
        push @mk, ["div", $f[5], $f[6]];
      }
      for my $line (split /\n/, ($ENV{PROBE_XSPEC} // "")) {
        next unless length $line;
        my @f = split /\t/, $line, -1;
        push @mk, [$f[2], $f[3], $f[4]];
        push @mk, [$f[5], $f[6], $f[7]];
      }
      my %seen = ();
      for my $m (@mk) {
        my ($en, $k, $v) = @$m;
        next unless defined $en && $en ne "" && defined $k && $k ne "" && defined $v && $v ne "";
        next if $seen{"$en\t$k\t$v"}++;
        my ($c_any, $c_el) = (0, 0);
        for (my $x = 0; $x <= $#t; $x++) {
          next if $t[$x]{cl};
          my $a = $attr->($t[$x]{raw}, $k);
          next unless defined $a && $val_match->($k, $a, $v);
          $c_any++; $c_el++ if $t[$x]{nm} eq $en;
        }
        $err = "marker-on-foreign-element-$k-$v" if $c_any != $c_el && $err eq "";
      }
    }
    for my $line (split /\n/, ($ENV{PROBE_SPEC} // "")) {
      next unless length $line;
      my @f = split /\t/, $line, -1;
      my $id = $f[0]; my $num = $f[1] // ""; my $tint = $f[2] // "";
      my $ca = $f[3] // ""; my $cv = $f[4] // ""; my $pa = $f[5] // ""; my $pv = $f[6] // "";
      my $found = 0; my $wk = -1;
      for (my $x = 0; $x <= $#t; $x++) { if ($match->($x, "section", "id", $id)) { $found++; $wk = $x if $found == 1 } }
      my ($adj, $band, $cb, $cbadj, $cont, $pay, $kids, $bkids, $cbkids) = (0, 0, 0, 0, 0, 0, 0, 0, 0);
      my ($sese, $mflab) = ("", "");
      if ($found == 1) {
        my ($r0, $r1) = $region->($wk);
        if ($r0 >= 0 && $r0 <= $r1) {
          $band = $count->($r0, $r1, "section", "data-component", "chapter-deck-band");
          $cb   = $count->($r0, $r1, "div", "class", "chapbody");
          # ★kids = 章 region 内の ★深さ 1 の子要素数。 assembler の構造規約では章の直下は
          #   「章帯 band」+「chapbody」の ★2 子だけ ゆえ、 章本文 (subhead / 地の文 / table / ref-primary …) を
          #   ★一部でも全部でも chapbody の外 (章直下の sibling) へ出すと 3 子以上になる = その向きは捕捉できる
          #   (★band subtree への退避は bkids・★別章移送 / fold 退避は cbkids の担当 — ★3 レベルで 1 組)
          #   (件数 pin を部品種別ごとに置く形は 0 件の章で 0/0 恒真になり、 かつ地の文のように marker を
          #   持たない本文を覆えない)。
          #   ★★打ち切りは ★silent にしない (errata: void 要素 2 個で 3 レベル完全子数束縛が全て素通る
          #   fail-open の封鎖): 本計数は ★同名深さ計数 ゆえ、 depth-1 の子の対応閉じタグが region 内に
          #   無いと そこで走査を打ち切る。 これを黙って打ち切ると、 攻撃者は「章本文 block を 1 個抜いて
          #   chapbody の外へ出し、 抜けた分の位置に void 要素 (`<br>` / `<hr>` / `<img>` …) を 1 個挿す」
          #   だけで kids / bkids / cbkids を ★期待値ちょうどに保てる (実弾で rc=0 / 0 FAIL を再現した)。
          #   ゆえ打ち切りを ★err へ倒す (fail-closed) — genuine 生成物の 章直下 / band / chapbody の
          #   depth-1 には void 要素が 0 件 (実測) ゆえ false FAIL は出ない。 per-shape MK = MKC-29。
          my $count_kids = sub {   # region (lo..hi) の ★深さ 1 の子要素数 (+ $sig 指定時は ★marker 列 も収集)
            my ($lo, $hi, $sig) = @_; my $c = 0; return 0 if $lo < 0;
            my $x = $lo;
            while ($x >= 0 && $x <= $hi) {
              if ($t[$x]{cl}) { $x++; next }
              $c++;
              # ★marker 列 = 深さ 1 の子の「要素名:識別 marker」を ★document 順に 並べた列。 識別 marker は
              #   data-component を第一とし、 無ければ class、 どちらも無ければ `-` (= 無印) を置く
              #   (assembler は人間層 block を data-component か class のどちらかで必ず刻む — 例外 = 無印は
              #   ★genuine には現れない ゆえ `-` が列に出た時点で期待値と割れて loud に落ちる)。
              if (ref $sig) {
                my $dc = $attr->($t[$x]{raw}, "data-component");
                my $cs = $attr->($t[$x]{raw}, "class");
                push @$sig, $t[$x]{nm} . ":" . (defined $dc && $dc ne "" ? $dc
                                              : (defined $cs && $cs ne "" ? $cs : "-"));
              }
              # ★foreign root (svg / math) が ★深さ 1 に現れたら err (fail-closed)。 root を 1 子として数えるだけ
              #   だと ★逆向きの masking が開く — 章本文 block を 1 個 fold / 別章へ退避させ、 抜けた位置へ
              #   `<svg><path/></svg>` を filler として挿す形は 実 DOM でも子数が保たれる ため ★完全子数束縛では
              #   原理的に見分けられない。 genuine 生成物の svg は span.ic / reader-chip / kicker の ★内側 のみで
              #   章 / band / chapbody の深さ 1 には 0 件 (実測) ゆえ、 現れたら loud に落とす。 per-shape MK = MKC-30。
              if ($t[$x]{nm} eq "svg" || $t[$x]{nm} eq "math") { $err = "foreign-at-depth1-$t[$x]{nm}" if $err eq "" }
              my $nm2 = $t[$x]{nm}; my $d3 = 1; my $y = $x + 1;
              while ($y <= $hi && $d3 > 0) { if ($t[$y]{nm} eq $nm2) { $d3 += $t[$y]{cl} ? -1 : 1 } $y++ }
              if ($d3 == 0) { $x = $y } else { $err = "unclosed-child-$nm2" if $err eq ""; $x = $hi + 1 }
            }
            return $c;
          };
          $kids = $count_kids->($r0, $r1);
          # ★bkids = ★章帯 (band) region 内の深さ 1 の子要素数。 kids pin だけでは relocation クラスが
          #   ★片方向 にしか閉じない — 押し出し先を sibling でなく ★band の中 にすると章直下は
          #   band + chapbody のままで kids=2 を保ち素通る。
          #   共有 CORE lib/common.sh の band() は span.num / span.kicker / h2 / p.lead の ★4 子固定。
          my $bk = $first->($r0, $r1, "section", "data-component", "chapter-deck-band");
          if ($bk >= 0) { my ($b0, $b1) = $region->($bk); $bkids = $count_kids->($b0, $b1) }
          # ★cbkids = ★chapbody region 内の深さ 1 の子の ★marker 列 (逐値・順序つき)。 章直下 (kids) と
          #   band 直下 (bkids) を固定しても ★document 順を保つ relocation は残る — 章本文を (β) ★別章の
          #   chapbody へ移送 する / (γ) ★同章の machine-fold (details) の中へ退避 すると、 両者とも probe の
          #   他の値を ★一切動かさず に素通る。
          #   ★★errata (数 → 列): 旧実装は ★子の個数 だけ を束縛したため ★どの子か を束縛せず、 3 前提を
          #   一切破らない ★反例 が構成できた — 抜けた位置へ ★空 <div> を 1 個 filler として挿すと
          #   (β2) 同章 machine-fold の machine-body 内へ / (γ2) 兄弟 block (div.tbl-wrap) の subtree 内へ の
          #   block 退避が ★どのレベルの子数も動かさず 素通る (Leg B = relations で実測 verified: rc=0 / 0 FAIL。
          #   人間層見出しが ★既定非表示の <details> の中へ消える形 = containment が閉じたと主張していた
          #   relocation クラスそのもの)。 ゆえ ★列 (要素名 + data-component/class marker の ★逐値・順序) で
          #   束縛する: filler は marker が無印 (`-`) ゆえ列が割れ、 退避先で列が縮む donor 側でも割れる。
          #   per-shape MK = MKC-10 (数の向き = 別章 chapbody への移送で列が縮む / 伸びる) /
          #   MKC-11 (filler 置換の向き = 空 <div> filler 付き machine-fold 退避で ★列だけ が割れる)。
          # ★★章帰属の逐値束縛 (admin gate errata-1 MUST-1・★実弾 2 本 verified の fail-open 封鎖):
          #   ★sese  = 章の chapbody 内 ★最初の p.sec-se の ★中身 (契約 sections[].essence の逐語 echo)
          #   ★mflab = 章 region 内 ★最初の span.mf-label の ★中身 (契約 heading 由来の導出ラベル)
          #   ★どちらも ★contract 由来 の期待値と突合するので 0/0 恒真化しない (期待は常に非空)。
          #   ★値は ★1 行 であることを前提に KV 行で運ぶ — 改行 / CR が入ったら ★err で fail-closed する
          #   (silent に潰して比較すると「壊れた値が期待と一致した」形の偽 PASS を作りうるため)。
          my $sk = $first->($r0, $r1, "p", "class", "sec-se");
          $sese  = $sk >= 0 ? $inner->($sk) : "";
          my $mlk = $first->($r0, $r1, "span", "class", "mf-label");
          $mflab = $mlk >= 0 ? $inner->($mlk) : "";
          if ($err eq "" && ($sese =~ /[\r\n]/ || $mflab =~ /[\r\n]/)) { $err = "multiline-chapter-text-$id" }
          my $cbk2 = $first->($r0, $r1, "div", "class", "chapbody");
          if ($cbk2 >= 0) { my ($q0, $q1) = $region->($cbk2); my @sg = (); $count_kids->($q0, $q1, \@sg); $cbkids = join(",", @sg) }
          # (i) 開口隣接: 直後 token が この章の band (tint 逐値・間の text は空白のみ) で、 その中の
          #     <span class="num">§番号</span> が contract 由来の期待値と 逐値一致 すること。
          if ($match->($r0, "section", "data-component", "chapter-deck-band") && $gap_ws->($wk, $r0)
              && ($tint eq "" || do { my $c = $attr->($t[$r0]{raw}, "class"); defined $c && $val_match->("class", $c, "tint-" . $tint) })
              && $match->($r0 + 1, "span", "class", "num")
              && $r0 + 2 <= $r1 && $t[$r0 + 2]{cl} && $t[$r0 + 2]{nm} eq "span") {
            $adj = 1 if substr($b, $t[$r0 + 1]{e}, $t[$r0 + 2]{s} - $t[$r0 + 1]{e}) eq $num;
          }
          # (iii) 1 段内側: chapbody region 内の container 個数 / container 開口隣接 / container region 内の payload 全数。
          my $cbk = $first->($r0, $r1, "div", "class", "chapbody");
          if ($cbk >= 0 && $ca ne "") {
            my ($c0, $c1) = $region->($cbk);
            if ($c0 >= 0 && $c0 <= $c1) {
              $cont = $count->($c0, $c1, "div", $ca, $cv);
              my $ck = $first->($c0, $c1, "div", $ca, $cv);
              if ($ck >= 0) {
                $cbadj = 1 if $ck == $c0 && $gap_ws->($cbk, $ck);
                my ($p0, $p1) = $region->($ck);
                $pay = $count->($p0, $p1, "div", $pa, $pv) if $p0 >= 0 && $p0 <= $p1;
              }
            }
          }
        }
      }
      # ★docct = payload container の ★文書全体 の個数。 「chapbody 内に 1 個」だけでは器の ★重複 を許し、
      #   2 個目の器 (章の外・別章の中) が payload の ★逃げ場 として使える (中身を失った空の器が正規の位置に
      #   残るため上の per-章 arm は全て PASS のまま)。 文書総数と対で押さえて漏出先そのものを消す。
      my $docct = ($ca ne "") ? $count->(0, $#t, "div", $ca, $cv) : 0;
      print "$id|found=$found\n$id|adj=$adj\n$id|band=$band\n$id|cb=$cb\n$id|cbadj=$cbadj\n$id|cont=$cont\n$id|pay=$pay\n$id|docct=$docct\n$id|kids=$kids\n$id|bkids=$bkids\n$id|cbkids=$cbkids\n$id|sese=$sese\n$id|mflab=$mflab\n";
    }
    # ---- XSPEC: ★章 × ★追加の器 (人間層 block の wrapper) の payload 占有 + 器の ★文書総数 ----
    #   入力 PROBE_XSPEC = 1 行 1 (章, 器) の TSV:
    #     key \t section id \t 器要素名 \t 器属性 \t 器値 \t payload 要素名 \t payload 属性 \t payload 値
    #   出力 = "<key>|xpayseq=<chapbody ★直下 の器ごとの payload 数を document 順に並べた ★列 (カンマ区切り)>" /
    #          "<key>|xdoc=<器の ★文書全体 の個数>" の ★2 値 のみ。
    #   ★出力契約コメントの ★是正 (self-review 指摘・false record 封鎖): 移植元 verify-spec.sh:769 は
    #   「xcont=<器数> / xpay=<payload 総数>」と書いているが、 ★実装が print するのは xpayseq / xdoc の 2 値
    #   だけ である (器数の単独出力と payload の章合計は errata-2 で ★器ごとの列 へ置換されて消えた)。
    #   逐語移植でこの stale なコメントごと持ち込んでいたため実装と食い違っていた。 ★移植元側にも同じ
    #   false record が残っている が、 本 leg の fence で verify-spec.sh は不触 = ★admin へ申送り。
    #   ★存在理由 (errata-1 / admin gate round-1 blocking): chapbody 直下の marker 列 (cbkids) は
    #   「何が来るか」を束縛するが ★器の中身 は束縛しない。 かつ [table]=div.tbl-wrap / [requirements]=div.rq-list は
    #   ★wrapper class 自身の文書 census を持たない (census は内側の spec-table / ears-requirement-row を数える)
    #   ため、 ★空の wrapper を filler に残して 中身だけ machine-fold へ移す 3 shape が ★全 arm 素通り だった
    #   (実測 rc=0 / OK 数 baseline 完全一致): (A) rq-list ごと fold へ + 空 rq-list filler / (B) tbl-wrap ごと
    #   fold へ + 空 tbl-wrap filler / (C) tbl-wrap 据置で中の table だけ fold へ (hollow wrapper 残置)。
    #   ★xpay が (A)(C) を、 ★xcont + xdoc の対が (B) の器の移動を、 それぞれ contract 由来の期待値で閉じる。
    for my $line (split /\n/, ($ENV{PROBE_XSPEC} // "")) {
      next unless length $line;
      my @f = split /\t/, $line, -1;
      my $key = $f[0]; my $id = $f[1] // ""; my $cn = $f[2] // ""; my $ca = $f[3] // ""; my $cv = $f[4] // "";
      my $pn = $f[5] // ""; my $pa = $f[6] // ""; my $pv = $f[7] // "";
      my @xseq = ();
      my $found = 0; my $wk = -1;
      for (my $x = 0; $x <= $#t; $x++) { if ($match->($x, "section", "id", $id)) { $found++; $wk = $x if $found == 1 } }
      if ($found == 1) {
        my ($r0, $r1) = $region->($wk);
        my $cbk = ($r0 >= 0 && $r0 <= $r1) ? $first->($r0, $r1, "div", "class", "chapbody") : -1;
        if ($cbk >= 0) {
          my ($q0, $q1) = $region->($cbk);
          if ($q0 >= 0 && $q0 <= $q1) {
            for my $ci ($kids_idx->($q0, $q1)) {
              next unless $match->($ci, $cn, $ca, $cv);
              # ★errata-2: ★器ごと の payload 数を ★document 順の列 として持つ (章合計にしない)。 合計だけだと
              #   ★同章内の 器 → 器 payload 再配分 (1 本目へ寄せて 2 本目を空の器として残す) が ★合計不変 ゆえ
              #   素通る (Leg B 実測 shape D/D2: rc=0 / 0 FAIL = clean と 1 arm も違わない)。 列にすると
              #   器の ★帰属 が per-container で束縛され、 器数の欠落も列長で落ちる。
              my ($p0, $p1) = $region->($ci);
              push @xseq, (($p0 >= 0 && $p0 <= $p1) ? $count->($p0, $p1, $pn, $pa, $pv) : 0);
            }
          }
        }
      }
      my $xpayseq = join(",", @xseq);
      my $xdoc = $count->(0, $#t, $cn, $ca, $cv);
      # ★出力は xpayseq / xdoc の 2 値 (章 row は xpayseq を・doc row は xdoc を chk する)。 ★器の個数 は
      #   ★単独では出さない — chapbody 直下の marker 列 (cbkids) が器の位置と個数を既に束縛しており、 かつ
      #   xpayseq の ★列長 が器数を含意する ため、 個数だけの arm は per-shape MK を持てない (実弾で撃てない
      #   arm を新設しない・fence「新規 arm は MK で 1 本以上 anchor」)。
      print "$key|xpayseq=$xpayseq\n$key|xdoc=$xdoc\n";
    }
    print "*|err=$err\n";
  ' "$BODY"
}
# ★章 census (契約章 5 + 提示層 wrapper 2) を ★1 本の駆動表 にまとめる。 tint 逐値は ★全 7 章に課す —
#   契約章の tint 源は ★contract の sections[].tint (band の class="tint-<値>" と 1:1 対応)、 提示層 wrapper の
#   2 章は assembler literal と二重保守の PRESENTATION_WRAPPER_BAND_TINTS。 持てる逐値を放棄しない。
#   1 段内側 (iii) は ★全 7 章が持つ — wrapper 2 章は payload container (ref-grid / glossary-term-table) と
#   payload 全数、 契約章 5 本は ★章要旨 callout (assembler が chapbody 開口直後に必ず emit する部品) を器に取る。
# ★★chk は ★arm ごとに 1 行 (章ごとに別行へ展開しない): mutation-kill は「その chk 行を消すと敵対 suite が
#   赤くなるか」で測るので、 同じ検査を章別に複製すると per-shape MK が章の数だけ必要になり実効被覆が落ちる。
mapfile -t _SEC_ANCHORS < <(q '.sections[].anchor')
mapfile -t _SEC_NUMLIST < <(printf '%s\n' "$SEC_NUMS")
mapfile -t _SEC_TINTS < <(q '.sections[].tint')
# ★fail-closed: contract の tint が 1 つでも欠けたら「tint 不問」へ ★暗黙に degrade させない (欠落を静かに
#   許すと契約側の tint 削除で本 arm が恒真化する = 0/0 恒真 pin と同じ vacuous-green クラス)。
[[ "${#_SEC_TINTS[@]}" -eq "${#_SEC_ANCHORS[@]}" ]] || { echo "verify-srs-verification: ★contract sections[].tint の件数が anchor と不一致 (${#_SEC_TINTS[@]} != ${#_SEC_ANCHORS[@]}・tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
_CT_ID=(); _CT_NUM=(); _CT_TINT=(); _CT_CA=(); _CT_CV=(); _CT_PA=(); _CT_PV=(); _CT_CLBL=(); _CT_PLBL=(); _CT_PEXP=(); _CT_CEXP=(); _CT_CBEXP=()
# ★章帰属の逐値束縛 (errata-1 MUST-1) の期待値。 _CT_TXT=1 の章 (= contract 章) だけが 2 arm を持つ
#   (提示層 wrapper は callout も fold も持たない = 0/0 恒真 arm を作らないため対象外)。
_CT_SESE=(); _CT_MFLAB=(); _CT_TXT=()
# ★contract の block type → chapbody 直下に emit される ★depth-1 marker (要素名 + data-component / class) の対応表。
#   源 = assemble-srs-verification.sh の emit_blocks 分岐 (1 block = ★1 つの depth-1 要素) ゆえ ★二重保守。
#   ★列 (順序つき逐値) で束縛するために「何個か」でなく「何が来るか」を持つ。
#   ★contract に新 type が入って本表に無ければ ★exit 1 (silent skip = 期待値の暗黙短縮 を作らない)。
#   ★本表の鍵集合は assemble-srs-verification.sh emit_blocks の case 分岐 ★8 型と 1:1 (実測・sibling fork の
#   subsubhead / ref-primary は本 assembler に分岐が無い = 登録しない。 契約へ入れば assembler 側が先に
#   「★未対応 block type」で abort し、 仮に assembler が対応しても本表の欠落で exit 1 = 二重の fail-closed)。
#   ★srs-verification contract の ★実測 type は requirements / table の 2 種のみ (他 6 型は現契約に 0 件) —
#   本表は「契約に入りうる型の写像」であって「今在る型の列挙」ではない (0 件の型に arm を作らない = 0/0 恒真回避)。
declare -A CHAPBODY_KID_MARK=(
  [prose]="p:spec-prose"          [note]="div:spec-note"         [list]="ul:spec-list-block"
  [code]="pre:spec-code"          [table]="div:tbl-wrap"         [mermaid]="figure:spec-diagram"
  [subhead]="div:spec-subhead"    [requirements]="div:rq-list"
)
# ★契約章 5 本の 1 段内側 (iii) は ★章要旨 callout を器に取る。 assemble-srs-verification.sh の emit_section が
#   chapbody 開口の ★直後に必ず 1 個 emit する部品ゆえ、 期待値 (隣接 1 / chapbody 内 1 個 / 文書総数 == NSEC) は
#   ★assembler と contract から決定的に導ける。 これが無いと契約章は「chapbody を空にして章本文を sibling へ
#   押し出す」改竄が 0 FAIL で素通る。
# ★★payload 側 (_CT_PA / _CT_PV) を ★空のままにする 理由 と ★その埋め合わせ (folio-3zr4.3 self-review 是正・
#   実弾 2 形 verified): 契約章の器中身は `<p class="sec-se">` = ★要素名が p であり、 主 loop の $pay は
#   payload 要素名を ★literal "div" に固定している ため ここでは数えられない。 ★空のまま放置すると 契約章 5 本は
#   adj / cont / docct の 3 本しか出ず ★器中身の占有 arm が 1 本も立たない — 「器を空の filler として正規位置に
#   残し 中身だけ逃がす」Leg B errata-1 と ★同一クラス が 5/7 章で開いたままになる (実測: (a) s0 の sec-se を
#   同章 machine-fold の machine-body へ移す 〔人間可視の章要旨が既定折り畳みの中へ消える〕 (b) s0 の sec-se を
#   s1 の callout へ graft 〔別章移送〕 の ★2 形とも rc=0 / OK 129 / FAIL 0 で全 gate 素通りだった)。
#   ★埋め合わせ = ★XSPEC 経路 (器 / payload の要素名が TSV でパラメタ化済) に (契約章 × 章要旨 callout →
#   p.sec-se) の row を ★契約章数だけ 立てる (下の _XC_* 構築の末尾)。 主 loop に payload 要素名 field を足す
#   案もあるが、 XSPEC は ★器ごとの個数列 (xpayseq) で帰属まで束縛する ため封鎖が強い側を採る。
#   per-shape MK = MKC-50 (hollow callout = 中身だけ fold へ) / MKC-51 (別章 graft)。
for _k in "${!_SEC_ANCHORS[@]}"; do
  [[ -n "${_SEC_TINTS[$_k]}" && "${_SEC_TINTS[$_k]}" != "null" ]] || { echo "verify-srs-verification: ★contract sections[$_k].tint が空 (tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _CT_ID+=("$(esc "${_SEC_ANCHORS[$_k]}")"); _CT_NUM+=("${_SEC_NUMLIST[$_k]}"); _CT_TINT+=("${_SEC_TINTS[$_k]}")
  _CT_CA+=("data-component"); _CT_CV+=("section-essence-callout"); _CT_PA+=(""); _CT_PV+=("")
  _CT_CLBL+=("章要旨 callout"); _CT_PLBL+=(""); _CT_PEXP+=(""); _CT_CEXP+=("$NSEC")
  # ★chapbody 直下の ★完全子数 を contract から決定的に導く: 章要旨 callout 1 + blocks 各 1 +
  #   machine_blocks があれば fold 1 (assemble-srs-verification.sh の emit_blocks は 1 block = ★1 つの depth-1
  #   要素、 emit_machine_fold は details 1 個)。
  # ★★srs 固有 (三項 0 側分岐の実データ): s2-done-condition-req は machine_blocks が ★0 本 ゆえ fold を足さない。
  #   ★この章の期待列は 2 要素 (callout + rq-list) = ★0/0 恒真にならない (最小でも callout 1 + 何か 1 = 2)。
  #   ★blocks も machine_blocks も 0 の章が将来現れると期待列は callout 1 本 = 1 要素になるが、 それでも
  #   ★空列ではない ため恒真化しない (空列 vs 非空列の突合は成立する)。
  _nb="$(q ".sections[$_k].blocks // [] | length")"; _nm="$(q ".sections[$_k].machine_blocks // [] | length")"
  [[ "$_nb" =~ ^[0-9]+$ && "$_nm" =~ ^[0-9]+$ ]] || { echo "verify-srs-verification: ★sections[$_k] の blocks / machine_blocks 件数を導出できない (cbkids 期待値の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _sig="div:section-essence-callout"; _cnt=0
  while IFS= read -r _bt; do
    [[ -n "$_bt" ]] || continue
    _bm="${CHAPBODY_KID_MARK[$_bt]:-}"
    [[ -n "$_bm" ]] || { echo "verify-srs-verification: ★sections[$_k] の block type '$_bt' が CHAPBODY_KID_MARK に無い (chapbody 完全子列の導出不能・silent skip 禁止・fail-closed)" >&2; exit 1; }
    _sig+=",$_bm"; _cnt=$(( _cnt + 1 ))
  done < <(q ".sections[$_k].blocks // [] | .[].type")
  # ★導出の完全性 (silent drop 封鎖): 列へ積んだ block 数が contract の blocks 件数と一致すること。 一致しないと
  #   期待値が ★実測へ寄る 側 (短い列) へ静かに degrade しうる。
  [[ "$_cnt" -eq "$_nb" ]] || { echo "verify-srs-verification: ★sections[$_k] の block type 列 ($_cnt 件) が blocks 件数 ($_nb) と不一致 (chapbody 完全子列の trust anchor 破れ・fail-closed)" >&2; exit 1; }
  [[ "$_nm" -eq 0 ]] || _sig+=",details:spec-machine-fold"
  _CT_CBEXP+=("$_sig")
  # ★章要旨本文 = contract sections[].essence の ★逐語 echo (assembler は esc せず raw で emit する = :1103)。
  _ess="$(q ".sections[$_k].essence")"
  [[ -n "$_ess" && "$_ess" != "null" ]] || { echo "verify-srs-verification: ★contract sections[$_k].essence が空 (章帰属 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _CT_SESE+=("$_ess")
  # ★機械層 fold ラベル = esc("<heading> の地の文・運用説明・rationale")。 assembler の emit_machine_fold 実引数
  #   (:1106) と ★二重保守。 machine_blocks が 0 本の章は fold 自体が emit されない ゆえ期待は ★空文字
  #   (= 「その章に fold は無い」の負の主張。 同 arm の他 4 章が非空期待を持つので恒真化しない = ehar 対)。
  if [[ "$_nm" -eq 0 ]]; then _CT_MFLAB+=(""); else
    _hd="$(q ".sections[$_k].heading")"
    [[ -n "$_hd" && "$_hd" != "null" ]] || { echo "verify-srs-verification: ★contract sections[$_k].heading が空 (fold ラベル導出不能・fail-closed)" >&2; exit 1; }
    _CT_MFLAB+=("$(esc "$_hd の地の文・運用説明・rationale")")
  fi
  _CT_TXT+=("1")
done
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[0]}")"); _CT_NUM+=("${STATIC_NUMS[0]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[0]}")
_CT_CA+=("class"); _CT_CV+=("ref-grid"); _CT_PA+=("data-component"); _CT_PV+=("cross-doc-ref-chip")
_CT_CLBL+=("ref-grid"); _CT_PLBL+=("前方照会 chip"); _CT_PEXP+=("$NREF"); _CT_CEXP+=("1"); _CT_CBEXP+=("div:ref-grid")
_CT_SESE+=(""); _CT_MFLAB+=(""); _CT_TXT+=("0")
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[1]}")"); _CT_NUM+=("${STATIC_NUMS[1]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[1]}")
_CT_CA+=("data-component"); _CT_CV+=("glossary-term-table"); _CT_PA+=("class"); _CT_PV+=("grow")
_CT_CLBL+=("glossary-term-table"); _CT_PLBL+=("用語集 行 (.grow)"); _CT_PEXP+=("$(q '.glossary | length')"); _CT_CEXP+=("1"); _CT_CBEXP+=("div:glossary-term-table")
_CT_SESE+=(""); _CT_MFLAB+=(""); _CT_TXT+=("0")
# ============================================================================
# ★block wrapper の中身 の帰属 pin (Leg B errata-1 / Leg A の同型移植)。
#   ★根本原因: 上の chapbody 直下 marker 列 (cbkids) は「何が来るか」を束縛するが ★器の中身 は束縛せず、
#   さらに [table]=div.tbl-wrap / [requirements]=div.rq-list の 2 marker は ★wrapper class 自身の 文書 census を
#   ★持たない。 ゆえ 列 pin だけでは「空の wrapper を正規位置に filler として残し、 中身を machine-fold へ移す」
#   形を ★全て素通す (Leg B = relations 実測 3 shape・rc=0 / OK 数 baseline 完全一致 = arm skip ではなく ★全素通り)。
# ★★srs-verification では ★CENSUS_BACKED_MARK を置かない (sibling fork との ★意図的な非対称・false record 封鎖):
#   sibling の verify-spec.sh / verify-relations.sh は「1. 行数」= ★pack 全体の文書 census 節 を持ち、
#   census が担保する marker (spec-prose / spec-subhead …) を BLOCK_WRAPPER_SPEC 登録義務から ★免除 する。
#   本 script は ★提示層 shape の部分 verifier で そのような文書 census 節を ★持たない ため、 免除の
#   ★根拠自体が存在しない。 空の CENSUS_BACKED_MARK を宣言して「免除機構は在る」と読ませるのは
#   宣言能力 > 実能力の false record ゆえ ★宣言ごと置かず、 下の guard を「contract に実在する block type は
#   ★全て BLOCK_WRAPPER_SPEC 登録必須」へ ★強い側 で固定する (現契約の 2 型はいずれも登録済 = 現に通る)。
#   ★将来 leaf 型 (prose 等) が contract へ入ったら ★exit 1 で落ちる — 「気づかない」ではなく「落ちる」側。
#   その時に免除機構が要るなら ★census 節の新設ごと 設計する話であり、 本 cell では判断しない (admin へ申送り)。
# ★block wrapper → (器要素名|器属性|器値|payload 要素名|payload 属性|payload 値)。 源 = assemble-srs-verification.sh の
#   emit_table / emit_requirements (pack-local・二重保守)。 期待値は ★contract 由来 で導出する (下記)。
declare -A BLOCK_WRAPPER_SPEC=(
  [table]="div|class|tbl-wrap|table|data-component|spec-table"
  [requirements]="div|class|rq-list|div|data-component|ears-requirement-row"
)
declare -A BLOCK_WRAPPER_CLBL=( [table]="表の器 (div.tbl-wrap)" [requirements]="要件リストの器 (div.rq-list)" )
declare -A BLOCK_WRAPPER_PLBL=( [table]="表 (spec-table)" [requirements]="EARS 要件 row" )
# ★順序を持つ型リスト (連想配列の反復順は非決定ゆえ chk の並びを固定するために持つ)。 集合一致は機械 assert。
BLOCK_WRAPPER_TYPES=(table requirements)
[[ "${#BLOCK_WRAPPER_TYPES[@]}" -eq "${#BLOCK_WRAPPER_SPEC[@]}" ]] \
  || { echo "verify-srs-verification: ★BLOCK_WRAPPER_TYPES と BLOCK_WRAPPER_SPEC の件数不一致 (lockstep 破れ・fail-closed)" >&2; exit 1; }
for _wt in "${BLOCK_WRAPPER_TYPES[@]}"; do
  [[ -v BLOCK_WRAPPER_SPEC[$_wt] && -v BLOCK_WRAPPER_CLBL[$_wt] && -v BLOCK_WRAPPER_PLBL[$_wt] ]] \
    || { echo "verify-srs-verification: ★BLOCK_WRAPPER_* に型 '$_wt' の定義が欠けている (fail-closed)" >&2; exit 1; }
done
# ★★guard 入力の非空 / 件数 assert (vacuous guard の封鎖): 下のループは q() が ★空を返すと ★1 度も回らず
#   ★恒真 PASS する (yq 失敗 / contract shape 変化 / 誤 query のいずれでも同じ形で黙る)。 ゆえ ★先に配列へ取り、
#   (a) 非空 (b) 件数が contract の unique 件数と一致 を機械 assert してから回す
#   (負の主張「未登録 type は無い」に ★存在 anchor を対で置く = ehar クラス)。
mapfile -t _BT_ALL < <(q '[.sections[].blocks[]?.type] | unique | .[]')
_BT_N="$(q '[.sections[].blocks[]?.type] | unique | length')"
[[ "${#_BT_ALL[@]}" -gt 0 ]] \
  || { echo "verify-srs-verification: ★contract の block type 列挙が空 (partial-enum guard が恒真化する・fail-closed)" >&2; exit 1; }
[[ "$_BT_N" =~ ^[0-9]+$ && "${#_BT_ALL[@]}" -eq "$_BT_N" ]] \
  || { echo "verify-srs-verification: ★block type 列挙の件数不一致 (${#_BT_ALL[@]} != ${_BT_N}・guard 入力の trust anchor 破れ・fail-closed)" >&2; exit 1; }
for _bt in "${_BT_ALL[@]}"; do
  [[ -n "$_bt" ]] || { echo "verify-srs-verification: ★空の block type が列挙に混入 (fail-closed)" >&2; exit 1; }
  _bm="${CHAPBODY_KID_MARK[$_bt]:-}"
  [[ -n "$_bm" ]] || { echo "verify-srs-verification: ★block type '$_bt' が CHAPBODY_KID_MARK に無い (fail-closed)" >&2; exit 1; }
  [[ -v BLOCK_WRAPPER_SPEC[$_bt] ]] \
    || { echo "verify-srs-verification: ★block type '$_bt' の depth-1 marker '${_bm#*:}' は BLOCK_WRAPPER_SPEC 未登録 (器の中身が無検査・本 script に文書 census 節が無く免除根拠を持てない・fail-closed)" >&2; exit 1; }
done
# ★_XC_CEXP (器の個数の期待値) は ★置かない (self-review 指摘・dead 配列の除去): 器数だけを見る arm は
#   ★per-shape MK を持てない (xpayseq の ★列長 が器数を含意し、 chapbody 直下の marker 列 (cbkids) が器の位置と
#   個数を既に束縛するため、 器数単独の arm を落とす実弾が作れない) ので新設しない — fence「実弾で撃てない arm を
#   新設しない」。 ★配列だけ在って 1 度も読まれない 状態は「器の個数を検査している」と誤読させる宣言 > 実能力 ゆえ
#   ★宣言ごと消す。 ★移植元 verify-spec.sh には同名の dead 配列が残っている が本 leg の fence で不触 = admin へ申送り。
_XC_KEY=(); _XC_ROW=(); _XC_CLBL=(); _XC_PLBL=(); _XC_SEC=(); _XC_PEXP=(); _XC_DEXP=()
for _wt in "${BLOCK_WRAPPER_TYPES[@]}"; do
  IFS='|' read -r _wcn _wca _wcv _wpn _wpa _wpv <<< "${BLOCK_WRAPPER_SPEC[$_wt]}"
  _wtot="$(q "[.sections[].blocks[]? | select(.type==\"$_wt\")] | length")"
  [[ "$_wtot" =~ ^[0-9]+$ ]] || { echo "verify-srs-verification: ★block type '$_wt' の総数を導出できない (fail-closed)" >&2; exit 1; }
  # (1) ★器の文書総数 row (section に一致しない id を渡すので xpay は 0 = chk しない・xdoc だけ使う)。
  #   ★契約に 0 件の型では row を作らない — 「器 0 個」を pin しても ★0/0 恒真 になり teeth を持たないため。
  if [[ "$_wtot" -gt 0 ]]; then
    _XC_KEY+=("doc:$_wt"); _XC_ROW+=("doc:$_wt"$'\t'$'\t'"$_wcn"$'\t'"$_wca"$'\t'"$_wcv"$'\t'"$_wpn"$'\t'"$_wpa"$'\t'"$_wpv")
    _XC_CLBL+=("${BLOCK_WRAPPER_CLBL[$_wt]}"); _XC_PLBL+=("${BLOCK_WRAPPER_PLBL[$_wt]}"); _XC_SEC+=("")
    _XC_PEXP+=(""); _XC_DEXP+=("$_wtot")
  fi
  # (2) ★章ごとの 器の個数 + 器の中の payload 総数 (0/0 恒真封鎖のため ★該当 block を持つ章だけ 行を作る)。
  _wrows=0
  for _k in "${!_SEC_ANCHORS[@]}"; do
    _wn="$(q "[.sections[$_k].blocks[]? | select(.type==\"$_wt\")] | length")"
    [[ "$_wn" =~ ^[0-9]+$ ]] || { echo "verify-srs-verification: ★sections[$_k] の '$_wt' 件数を導出できない (fail-closed)" >&2; exit 1; }
    [[ "$_wn" -gt 0 ]] || continue
    # ★payload 期待値は ★器ごとの列 (document 順) — 章合計にしない。 合計だと ★同章内の 器 → 器 再配分
    #   (1 本目へ寄せて 2 本目を空の器として残す) が合計不変で素通る (Leg B 実測 shape D/D2)。
    #   ★本 pack では器 2 本以上の章が 0 件 ゆえ この shape の ★実弾は構成できない (上の実態開示のとおり) が、
    #   期待値の形は ★列 のままにする (章合計へ退化させると将来 contract が器 2 本を持った瞬間に穴が開く)。
    #   table = 器 1 個につき table 1 個 ゆえ "1,1,…" (器数分) / requirements = block ごとの ids 数の列。
    _wp=""
    if [[ "$_wt" == "requirements" ]]; then
      while IFS= read -r _il; do
        [[ -n "$_il" ]] || continue
        [[ "$_il" =~ ^[0-9]+$ && "$_il" -gt 0 ]] || { echo "verify-srs-verification: ★sections[$_k] の requirements block の ids 数を導出できない/0: '$_il' (0/0 恒真回避の前提破れ・fail-closed)" >&2; exit 1; }
        _wp+="${_wp:+,}$_il"
      done < <(q ".sections[$_k].blocks[]? | select(.type==\"requirements\") | (.ids | length)")
    else
      for ((_ci=0; _ci<_wn; _ci++)); do _wp+="${_wp:+,}1"; done
    fi
    # ★列の要素数 == 器数 (silent 短縮の封鎖: 期待列が実測へ寄る側へ黙って縮むのを防ぐ)。
    #   ★変数名は _wpn (payload 要素名) と衝突させない — 衝突させると probe へ渡す要素名が数値へ化け
    #   payload が全章 0 になる (Leg A が実装中に踏んだ実害・fail-closed 側だが原因が読めない形で総崩れする)。
    _wpcnt="$(awk -F, '{print NF}' <<< "$_wp")"
    [[ "$_wpcnt" -eq "$_wn" ]] || { echo "verify-srs-verification: ★sections[$_k] の '$_wt' 期待列 ($_wpcnt 要素) が器数 ($_wn) と不一致 (器ごと期待値の trust anchor 破れ・fail-closed)" >&2; exit 1; }
    _a="$(esc "${_SEC_ANCHORS[$_k]}")"
    _XC_KEY+=("$_a:$_wt"); _XC_ROW+=("$_a:$_wt"$'\t'"$_a"$'\t'"$_wcn"$'\t'"$_wca"$'\t'"$_wcv"$'\t'"$_wpn"$'\t'"$_wpa"$'\t'"$_wpv")
    _XC_CLBL+=("${BLOCK_WRAPPER_CLBL[$_wt]}"); _XC_PLBL+=("${BLOCK_WRAPPER_PLBL[$_wt]}"); _XC_SEC+=("$_a")
    _XC_PEXP+=("$_wp"); _XC_DEXP+=("")
    _wrows=$(( _wrows + 1 ))
  done
  # ★fail-closed: 契約に該当 block が在るのに章 row が 1 本も立たない = 駆動表の silent 空振り。
  [[ "$_wtot" -eq 0 || "$_wrows" -gt 0 ]] \
    || { echo "verify-srs-verification: ★block type '$_wt' は契約に $_wtot 件在るのに章 row が 0 本 (駆動表の空振り・fail-closed)" >&2; exit 1; }
done
# ★★契約章の ★章要旨 callout の 器中身 (payload) 占有 pin (folio-3zr4.3 self-review 是正・上の _CT_PA 空欄の
#   埋め合わせ)。 器 = div[data-component=section-essence-callout] / payload = p.sec-se。 ★XSPEC 経路 を使うのは
#   payload の要素名が ★p であり 主 loop の div 固定では数えられないため (理由は上に逐語)。
#   ★期待値の導出: row 数 = ★contract の章数 (NSEC) / 各 row の xpayseq = "1" — assemble-srs-verification.sh の
#   emit_section が chapbody 開口直後に callout を ★1 個、 その中に章要旨の `<p class="sec-se">` を ★1 個 emit する
#   (pack-local・二重保守)。 ★器の文書総数 (xdoc) row は ★立てない — 同じ器の docct を主 loop が既に
#   ★== NSEC で pin しており 重複 arm になるため (実弾で撃てない arm を新設しない)。
#   ★0/0 恒真にならない: 期待列 "1" は非空であり、 章が 0 本なら上の tint 件数 assert 群が先に fail-closed する。
for _k in "${!_SEC_ANCHORS[@]}"; do
  _a="$(esc "${_SEC_ANCHORS[$_k]}")"
  _XC_KEY+=("$_a:essence")
  _XC_ROW+=("$_a:essence"$'\t'"$_a"$'\t'"div"$'\t'"data-component"$'\t'"section-essence-callout"$'\t'"p"$'\t'"class"$'\t'"sec-se")
  _XC_CLBL+=("章要旨 callout"); _XC_PLBL+=("章要旨の本文 (p.sec-se)"); _XC_SEC+=("$_a")
  _XC_PEXP+=("1"); _XC_DEXP+=("")
done
# ★fail-closed: 契約章が在るのに essence row が 1 本も立たない = 駆動表の silent 空振り (上の block wrapper と同じ規律)。
[[ "${#_XC_KEY[@]}" -ge "$NSEC" ]] \
  || { echo "verify-srs-verification: ★章要旨 callout の payload row が章数 ($NSEC) に届かない (${#_XC_KEY[@]} 本・駆動表の空振り・fail-closed)" >&2; exit 1; }
_PROBE_SPEC=""
for _k in "${!_CT_ID[@]}"; do
  _PROBE_SPEC+="${_CT_ID[$_k]}"$'\t'"${_CT_NUM[$_k]}"$'\t'"${_CT_TINT[$_k]}"$'\t'"${_CT_CA[$_k]}"$'\t'"${_CT_CV[$_k]}"$'\t'"${_CT_PA[$_k]}"$'\t'"${_CT_PV[$_k]}"$'\n'
done
_PROBE_XSPEC=""
for _k in "${!_XC_ROW[@]}"; do _PROBE_XSPEC+="${_XC_ROW[$_k]}"$'\n'; done
_CPROBE="$(PROBE_SPEC="$_PROBE_SPEC" PROBE_XSPEC="$_PROBE_XSPEC" containment_probe)"
# ★★分割は ★最初の '|' と ★最初の '=' で行う (admin gate errata-1 MUST-1 で追加した sese / mflab の値は
#   ★contract 由来の自由文 ゆえ '|' や '=' を含みうる。 旧実装は awk -F'|' で ★全 '|' を区切り扱いし $2 だけを
#   見ていたため、 値に '|' が入ると ★静かに切り詰まって 期待と一致しなくなる / 逆に一致してしまう)。
_cp() { printf '%s\n' "$_CPROBE" | awk -v i="$1" -v k="$2" '
  { p = index($0, "|"); if (p == 0) next
    if (substr($0, 1, p-1) != i) next
    rest = substr($0, p+1); q = index(rest, "="); if (q == 0) next
    if (substr(rest, 1, q-1) != k) next
    print substr(rest, q+1); exit }'; }
echo
echo "--- arm 2C: containment (章化の実質・3 レベル完全子数束縛 + 器中身の帰属) ---"
# ★★駆動表の完全性 (partial-enumeration の封鎖): 章 census が ★全章 (contract sections + 提示層 wrapper) を
#   覆っていること・wrapper の id 配列と tint 配列が ★同じ長さ であることを ★機械で 固定する。 添字 [0]/[1] で
#   組み立てているため、 wrapper を 1 本増やして駆動表への追記を忘れると その章だけ containment が ★silent に
#   未検査 になる (「検査している」と読めるのに実際は素通り = vacuous-green クラス)。
# ★★ここに ★同じ長さ guard を再掲しない (admin gate errata-1 SHOULD L-3・到達不能 dead guard の撤去):
#   id ⇔ tint の長さ一致は ★上流の lockstep 長さ guard (本 script の「提示層 wrapper の lockstep 配列長が不一致」
#   = STATIC_HEADINGS 組み立て直後) が ★exit 2 で 既に落としている ため、 ここへ到達した時点で ★常に真 =
#   ★実行されない guard だった。 dead guard は「検査している」と読ませて実能力を水増しする (宣言 > 実能力) ので
#   ★撤去し、 唯一の担い手を上流 1 箇所に集約する (二重化したいなら ★上流を強くする 側で行うこと)。
chk "containment 駆動表が全章を覆う (contract sections + 提示層 wrapper・被覆漏れ封鎖)" \
  "$((NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}))" "${#_CT_ID[@]}"
# ★tokenizer の fail-closed 診断 (空でなければ 生成物が genuine な HTML 構造を破っている = 下の全 chk も総崩れする)。
#   per-shape MK は MKC-28 (div の自己閉じ構文) / MKC-29 (void 要素による深さ 1 計数の打ち切り) /
#   MKC-30 (depth-1 の foreign root) / MKC-31 (foreign の any-other-end-tag) / MKC-32 (foreign の breakout
#   開始タグ) / MKC-33 (svg 包みによる章外 relocation) / MKC-47 (span.grow の捏造 payload) / MKC-48
#   (span.ref-grid の器重複) / MKC-49 (span.tbl-wrap の器重複 = XSPEC 経路)
#   — ★同じ err arm の ★別 vector ゆえ 1 本の実弾は他の穴を証明しない (per-shape 規律 = jyfh / r8k)。
# ★★負の主張には ★存在 anchor を対で置く (ehar クラス): 本 arm は「err が空であること」を主張するが、 probe が
#   ★何も出力しない (関数改名 / 実行失敗 / PROBE_SPEC 空) 場合も空になり ★恒真 PASS する。 probe の出力行数を
#   ★章数から導出した期待値 で pin し、 「検査が走っていない」を「異常なし」と読まない。
chk "containment probe が全章分の実測を出力 (probe 無出力での vacuous PASS 封鎖)" \
  "$(( ${#_CT_ID[@]} * 13 + ${#_XC_KEY[@]} * 2 + 1 ))" "$(printf '%s\n' "$_CPROBE" | grep -c .)"
chk "containment tokenizer の構造診断 (未閉じ / 自己閉じ div,section / 深さ 1 の未閉じ子 / foreign の breakout・depth-1 出現 / marker の担体要素名が spec 外 / 要素名の窓超過 = 非 genuine shape)" "" "$(_cp '*' err)"
for _k in "${!_CT_ID[@]}"; do
  _s="${_CT_ID[$_k]}"; _tn=""; [[ -z "${_CT_TINT[$_k]}" ]] || _tn=" (tint-${_CT_TINT[$_k]})"
  chk "章 '$_s' の開口直後に §${_CT_NUM[$_k]} 章帯$_tn が隣接 (hollow section 封鎖・開口隣接 pin)" "1" "$(_cp "$_s" adj)"
  chk "章 '$_s' region 内の章帯 == 1 (欠落 / 他章 band の紛れ込み封鎖)" "1" "$(_cp "$_s" band)"
  chk "章 '$_s' region 内の chapbody == 1 (章本文の ★器 の帰属・欠落 / 重複封鎖)" "1" "$(_cp "$_s" cb)"
  # ★★3 レベルの束縛 (章直下 == 2 子 / band 直下 == 4 子 / chapbody 直下 == 契約由来の ★完全子列) が
  #   封鎖するのは ★人間層 (chapbody 直下) の block 粒度 relocation クラス である — 人間層 block を
  #   ★章内で どこへ動かしても (sibling へ / band の中へ / 別章の chapbody へ / 同章の fold の中へ / 兄弟 block の
  #   subtree の中へ) 章直下・band 直下の ★子数 か chapbody 直下の ★marker 列 が必ず変わる — ★ただし
  #   ★★これは ★構造が変わる 移動に限った主張である (errata-1 MUST-1 の是正・旧記述は全称で ★誤りだった):
  #   ★章間で ★同型の部品を交換 する形 (cbkids 期待列が完全同一な s0 / s1 / s4 の間で fold や p.sec-se を入れ替える)
  #   は ★どのレベルの子数も marker 列も 1 つも動かさない ため、 3 レベル束縛では ★原理的に 見分けられない。
  #   これは上の ★章帰属の逐値束縛 (sese / mflab) が ★別の担体 として閉じる (per-shape MK = MKC-52 / MKC-53)。 — ★ただし
  #   「block を ★器ごと / ★中身だけ 動かして 空の器を filler として正規位置に残す」形は 列も子数も動かさない
  #   ため ★列 pin だけでは閉じない。 これは下の ★器中身の占有 pin と ★対 で初めて閉じる。
  #   ★★残差 ③ の開示 (列が束縛するのは ★block の種類の列 であり ★どの block か ではない): (α) ★同種 block
  #   同士の入れ替え (例: 隣接する同型 block 2 本の順序交換) は列が同一ゆえ ★素通る — 可視テキストの逐値・順序は
  #   本 script の内容 arm / fidelity ceiling の領分であり 本 pin の射程ではない。 ★srs-verification の現契約では
  #   同一章に同型 block が 2 本以上ある章が ★0 件 (実測) ゆえ (α) は ★同一章内では 現 corpus で構成できない が、
  #   ★★「構成不能」と読まないこと (errata-1 MUST-1 の是正): ★章をまたぐ 同型交換は ★構成できる (s0⇄s1 の
  #   fold / 章要旨) — 実弾で rc=0 / 全 OK を再現した。 そちらは ★章帰属の逐値束縛 が閉じており、 列 pin の
  #   射程外である事実は変わらない。
  #   「構成的に安全」ではなく「今のデータでは起きない」と読むこと。 (β) ★marker を持つ空 filler は
  #   本 pack では ★全て BLOCK_WRAPPER_SPEC 側 (器型) に属する — [table]=div.tbl-wrap / [requirements]=div.rq-list は
  #   ★wrapper class 自身の文書 census を持たない ため、 列 pin ★だけ では「空の器を filler に残して中身を
  #   machine-fold へ移す」形が素通る (Leg B 実測 3 shape・rc=0 / 0 FAIL = clean と完全一致)。 ★下の
  #   器中身の占有 pin (xpayseq) と ★器自身の文書 census (xdoc) が対で封鎖する
  #   (per-shape MK = MKC-38・MKC-39 = 器ごと移送 + 空 filler / MKC-40・MKC-41 = 器据置で中身だけ退避)。
  #   ★この範囲では クラス閉塞が成立する — ただし成立は ★4 つの前提に依存する と ★明示 する (宣言 == 実能力):
  #   (0) 深さ 1 marker の payload が ★器ごとの個数列 pin で拘束される こと (本 pack は contract の block type
  #   2 種とも器型ゆえ ★全て この経路。 未登録 type は fail-closed で exit 1)。 (1) 深さ 1 の計数が
  #   ★打ち切られない こと — void 要素を depth-1 へ挿す計数マスクは err (`unclosed-child-*`) で fail-closed
  #   する。 (2) region 切り出しが ★実 DOM と一致する こと — タグ境界の attribute state 同型化 + 引用値直後の
  #   fail-closed で封鎖済 (★範型 verify-verification.sh 側は未封鎖 = 上の ★移植元と依存の所在 節に開示)。
  #   (3) ★foreign content (svg / math) が ★実 DOM と同型に 数えられる こと — root を ★1 子として計上 し、
  #   depth-1 に foreign root が現れたら `foreign-at-depth1-*` で fail-closed (計上だけだと ★逆向き の filler
  #   マスクが開くため 両者は ★対)、 subtree 内の breakout も err にする。 残差は上の ★開示済み残差 ② のとおり。
  #   ゆえ「あらゆる block relocation を閉じた」ではなく ★「上記 4 前提 + 残差 ③(α) の下で」閉じた と読むこと。
  #   射程外 2 種 (機械層 cross-fold 移動 = folio-e706 / sub-block 粒度) は上の実態開示のとおり。
  #   ★lockstep 相手の追加開示: chapbody 直下の marker 列は CHAPBODY_KID_MARK (block type → depth-1 marker) を
  #   源に持ち、 その値の SSOT は ★assemble-srs-verification.sh の emit_blocks 分岐 である (pack-local・二重保守)。
  #   assembler 側で marker を変えると本 arm は ★列不一致で loud に FAIL する (silent degrade しない)。
  #   contract に ★未知の block type が入った場合は 期待列を組む前に ★exit 1 (silent skip = 期待値の暗黙短縮 を作らない)。
  chk "章 '$_s' の直下は 章帯 + chapbody の 2 子だけ (章本文の sibling への relocation 封鎖)" "2" "$(_cp "$_s" kids)"
  chk "章 '$_s' の章帯の直下は num/kicker/h2/lead の 4 子だけ (band subtree への退避封鎖)" "4" "$(_cp "$_s" bkids)"
  chk "章 '$_s' の chapbody 直下は 契約由来の完全子列 (別章移送 / fold 退避 / filler 置換の封鎖)" "${_CT_CBEXP[$_k]}" "$(_cp "$_s" cbkids)"
  # ★★章帰属の ★逐値束縛 (admin gate errata-1 MUST-1・★実弾 2 本で立証された fail-open の封鎖):
  #   ★構造 (件数 / marker 列) は ★章間で同型な部品を交換 しても ★完全に保存される。 srs-verification contract の
  #   s0 / s1 / s4 は blocks:[] + machine_blocks 1 本で cbkids 期待列が ★完全同一 ゆえ、 s0⇄s1 の
  #   ★spec-machine-fold 交換 / ★p.sec-se 交換 は kids / bkids / cbkids / cont / docct / xpayseq を ★1 つも動かさず
  #   rc=0 / 全 OK = clean と ★無差別 になる (本 cell の敵対 suite で MKC-52 / MKC-53 が実弾)。 drift gate でも
  #   代替できない (assembler の off-by-one で fold / 章要旨が隣章に付くクラスは canonical と fresh 再生成が
  #   ★同じ間違いを共有する ため常に PASS する = 本 script が冒頭で自らの存在理由に挙げたクラスそのもの)。
  #   ゆえ ★中身の値 を contract の当該章のフィールドへ結び付ける (構造 pin と ★対 で初めて章帰属が閉じる)。
  #   ★期待値は contract 由来 (essence の逐語 / heading 由来の導出ラベル) ゆえ実測への after-the-fact 合わせにならない。
  if [[ "${_CT_TXT[$_k]}" == "1" ]]; then
    chk "章 '$_s' の 章要旨本文 (p.sec-se) == contract sections[].essence (★章帰属の逐値束縛・章間 同型 swap の封鎖)" \
      "${_CT_SESE[$_k]}" "$(_cp "$_s" sese)"
    chk "章 '$_s' の 機械層 fold ラベル (span.mf-label) == contract heading 由来 (★章帰属の逐値束縛・fold の章間 swap 封鎖)" \
      "${_CT_MFLAB[$_k]}" "$(_cp "$_s" mflab)"
  fi
  [[ -n "${_CT_CA[$_k]}" ]] || continue
  chk "章 '$_s' の chapbody 開口直後に ${_CT_CLBL[$_k]} が隣接 (1 段内側の開口隣接 pin)" "1" "$(_cp "$_s" cbadj)"
  chk "${_CT_CLBL[$_k]} が章 '$_s' の chapbody 内に 1 個 (器の外への押し出し封鎖)" "1" "$(_cp "$_s" cont)"
  chk "${_CT_CLBL[$_k]} が ★文書全体で ${_CT_CEXP[$_k]} 個 (器の重複 = payload / 章本文の逃げ場を消す)" "${_CT_CEXP[$_k]}" "$(_cp "$_s" docct)"
  [[ -n "${_CT_PA[$_k]}" ]] || continue
  chk "${_CT_PLBL[$_k]} の ★全数 が章 '$_s' の ${_CT_CLBL[$_k]} 内 (hollow container 封鎖・漏出 0)" "${_CT_PEXP[$_k]}" "$(_cp "$_s" pay)"
done
# ★block wrapper の中身 の帰属。 chapbody 直下の marker 列は「器がそこに在る」までしか言わない — 器の ★中身 と
#   器の ★文書総数 を contract 由来で束縛して「空の器を filler に残し中身を machine-fold へ移す」クラスを閉じる。
#   per-shape MK = MKC-38 (rq-list ごと退避 + 空 filler) / MKC-39 (tbl-wrap ごと machine-fold へ + 空 filler)
#   — この 2 本が ★器自身の文書 census (xdoc) 側 — / MKC-40 (tbl-wrap 据置で中の table だけ fold へ) /
#   MKC-41 (rq-list 据置で中の要件 row だけ callout subtree へ) — この 2 本が ★器中身の占有 (xpayseq) 側。
for _k in "${!_XC_KEY[@]}"; do
  _xk="${_XC_KEY[$_k]}"
  if [[ -n "${_XC_DEXP[$_k]}" ]]; then
    chk "${_XC_CLBL[$_k]} が ★文書全体で ${_XC_DEXP[$_k]} 個 (器自身の文書 census・器ごと別所へ移す形の封鎖)" "${_XC_DEXP[$_k]}" "$(_cp "$_xk" xdoc)"
    continue
  fi
  chk "${_XC_PLBL[$_k]} の ★器ごとの個数列 が章 '${_XC_SEC[$_k]}' の ${_XC_CLBL[$_k]} 群 (chapbody 直下・document 順) と契約由来で一致 (hollow / fold 退避 / ★同一章内の 器間 再配分の封鎖 — ★章をまたぐ 同型器の交換は本 arm の射程外で、 章帰属の逐値束縛が担う)" "${_XC_PEXP[$_k]}" "$(_cp "$_xk" xpayseq)"
done

# ============================================================================
# arm 3. ★chip tuple + rf-gloss の contract echo 厳密一致
# ============================================================================
# (a) role の可視ラベルは ★平易語 (ROLE_PLAIN) で attr data-ref-role は ★機械 token を保持する = ★非対称を literal 要求。
#     ★可視を突合から外す (「件数だけ数える」等) と平易語の詐称が無警備になるため期待側で map を引いて ★逐値突合する。
# (b) rf-gloss = contract references[].title の ★逐語 echo。 title を持たない contract (all-or-none の「無い」側) では
#     chip に gloss span が無い形を許し (optional group)、 その 0/0 恒真は直後の契約非依存 census が封鎖する。
echo
echo "--- arm 3: chip tuple + rf-gloss 逐語 echo ---"
chk "cross-doc-ref-chip == |references|" "$NREF" "$(occ 'data-component="cross-doc-ref-chip"' "$BODY_LIVE")"
badrole="$(grep -oE 'data-ref-role="[^"]+"' "$BODY_LIVE" | sed 's/.*data-ref-role="//; s/"$//' | sort -u | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
chk_empty "references: role が抽象 allowlist 内" "$badrole"
chk "references: (token,doc,role,title) 順序突合 + 可視 <b>==attr + role 平易語 + rf-gloss 逐語 echo" \
  "$(q '.references[] | [.token, .doc, .role, (.title // "")] | @tsv' | while IFS= read -r line; do
       [[ -n "$line" ]] || continue   # ★yq の 0 件 match は空行 1 本
       t="${line%%$'\t'*}"; rest="${line#*$'\t'}"; d="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"; r="${rest%%$'\t'*}"; ti="${rest#*$'\t'}"
       printf '%s\t%s\t%s\t%s\t%s\n' "$(esc "$t")" "$(esc "$d")" "$(esc "$r")" "$(esc "${ROLE_PLAIN[$r]:-★role 平易語 map 外:$r}")" "$(esc "$ti")"
     done)" \
  "$(perl -CSD -0777 -ne '
    while (/<div data-component="cross-doc-ref-chip" data-ref-token="([^"]*)" data-ref-role="([^"]*)"><span class="rf-token"><b>([^<]*)<\/b><\/span><span class="rf-arrow">[^<]*<\/span><span class="rf-doc">([^<]*)<\/span><span class="rf-role">([^<]*)<\/span>(?:<span class="rf-gloss">([^<]*)<\/span>)?<\/div>/g) {
      my ($tok,$role,$vtok,$doc,$vrole,$gloss)=($1,$2,$3,$4,$5,$6);
      $gloss = defined($gloss) ? $gloss : "";
      if ($tok ne $vtok) { print "TOKEN-VIS:$tok\xe2\x89\xa0$vtok\n"; next; }
      print "$tok\t$doc\t$role\t$vrole\t$gloss\n";
    }
  ' "$BODY_LIVE")"
# ★契約非依存 census (0/0 恒真封鎖): references[].title を contract から一括削除すると上記突合は「両側 title 空」で
#   恒真 PASS する。 chip の一行タイトル占有を数値 hardcode で pin する (srs-verification 固有値・他 fork へ流用禁止)。
chk "census: rf-gloss (照会先の一行タイトル) 占有 == $FZC_RF_GLOSS (契約非依存 floor)" "$FZC_RF_GLOSS" \
  "$(grep -oE '<span class="rf-gloss">' "$BODY_LIVE" | wc -l | tr -d ' ')"
# ★rf-gloss の ★per-chip 非空 (「gloss span は在るが中身が空」の半端形封鎖)。
chk "rf-gloss: 全 chip で一行タイトルが非空 (per-chip 非空 floor)" "$FZC_RF_GLOSS" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<span class="rf-gloss">([^<]*)<\/span>/g){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY_LIVE")"
# ★residue 検査 (errata-1 E-1(b)): 上の tuple 突合は ★厳密 shape に合う chip だけ を列挙し、 合わない chip を
#   ★黙って無視 する。 ゆえに「厳密 shape の 10 個」+「shape 外の捏造 chip」が同居しても tuple は一致 PASS し、
#   件数 census も (同一行 append なら行計数で) 動かない = 二重の fail-open だった。
#   ★marker の ★出現数 == 厳密 shape で列挙できた件数 を要求し、 ★shape 外 marker の存在自体を FAIL にする
#   (「無視する」を構造的に禁じる = 未知形の chip を通さない fail-closed)。
chk "residue: chip marker 出現数 == 厳密 shape で列挙できた chip 数 (shape 外 chip の黙殺封鎖)" \
  "$(occ 'data-component="cross-doc-ref-chip"' "$BODY_LIVE")" \
  "$(perl -CSD -0777 -ne 'my $n=0; $n++ while /<div data-component="cross-doc-ref-chip" data-ref-token="[^"]*" data-ref-role="[^"]*"><span class="rf-token"><b>[^<]*<\/b><\/span><span class="rf-arrow">[^<]*<\/span><span class="rf-doc">[^<]*<\/span><span class="rf-role">[^<]*<\/span>(?:<span class="rf-gloss">[^<]*<\/span>)?<\/div>/g; print $n;' "$BODY_LIVE")"

# ============================================================================
# arm 4. ★rq-prio census + closed allowlist 逐値 + statement 由来 level 一致
# ============================================================================
# ★3 層で撃つ:
#   (i)   契約非依存 census — 生成物の占有数を ★数値 hardcode で pin。 priority は all-or-none optional ゆえ contract
#         から一括削除すると期待/実体が同時に空になり ★0/0 恒真 PASS する。 その唯一の FAIL 源。
#   (ii)  label↔level 束縛 — バッジの ★可視ラベルは prose slot (人間層 edit-SSoT) が持つため floor は内容を contract と
#         直接突合できない。 level ごとの ★closed allowlist で ★逐値突合 し must の行の「推奨…」「必須ではない」を封鎖。
#   (iii) ★level↔statement 束縛 (契約内不変条件) — (i)(ii) は ★contract の priority を根として突合するため contract 自身が
#         statement と矛盾する level を宣言していると ★全 gate を素通る。 drift gate は contract から再生成する byte
#         比較ゆえ contract 側の誤りには ★全盲。 導出規則で機械層に閉じる (宣言能力 == 実能力)。
echo
echo "--- arm 4: 優先度バッジ (census / allowlist 逐値 / statement 由来 level) ---"
chk "census: rq-prio バッジ占有 == $FZC_RQ_PRIO (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PRIO" \
  "$(grep -oE '<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">' "$BODY_LIVE" | wc -l | tr -d ' ')"
# ★per-row 束縛 (relocation クラス封鎖): slot-id は要件 anchor から決定的に導かれる (prio-<anchor>) ため、
#   別 row のバッジを持ってくる件数保存の relocation が ★列突合で FAIL する。
chk "rq-prio: (level, slot-id) 列 == contract (priority, prio-<anchor>) 順" \
  "$(while IFS= read -r id; do
       [[ -n "$id" ]] || continue
       p="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
       [[ -n "$p" && "$p" != "null" ]] || continue
       a="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
       [[ -n "$a" && "$a" != "null" ]] || { echo "verify-srs-verification: ★contract 要件 $id の anchor が空 (fail-closed)" >&2; exit 1; }
       if ! [[ -v PRIO_LABEL_OK[$p] ]]; then echo "verify-srs-verification: ★contract 要件 $id の priority が allowlist 外: $p (fail-closed)" >&2; exit 1; fi
       printf '%s\tprio-%s\n' "$p" "$(esc "$a")"
     done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))" \
  "$(perl -CSD -0777 -ne 'while (/<span class="rq-prio rq-prio-([a-z]+)" data-prose-slot="priority" data-slot-id="([^"]*)">/g){ print "$1\t$2\n"; }' "$BODY_LIVE")"
# (iii) priority (宣言) vs statement 由来 level (導出) の逐行突合。 ★mode 非依存 (contract だけを読む) ゆえ
#   ARTIFACT guard の ★外 に置く。 assemble-srs-verification.sh validate() にも同判定を置き build 時 fail-closed にしている。
# ★導出規則 (assembler と逐語同一・first-modal-wins・wave 恒常 1): statement 中で ★最初に 現れる規範キーワードが
#   level を決める。 SHALL|MUST が先 → must / SHOULD のみ → should / SHOULD が先で SHALL|MUST が後 → AMBIGUOUS-BOTH
#   (fail-closed) / 皆無 → NO-MODAL (fail-closed)。
ps_exp=""; ps_act=""
while IFS= read -r ps_id; do
  [[ -n "$ps_id" ]] || continue
  ps_p="$(q '.requirements[] | select(.id=="'"$ps_id"'") | .priority // ""')"
  [[ -n "$ps_p" && "$ps_p" != "null" ]] || continue
  ps_d="$(q '.requirements[] | select(.id=="'"$ps_id"'") | .statement' | perl -0777 -ne '
      my $m = /\b(?:SHALL|MUST)\b/ ? $-[0] : -1; my $s = /\bSHOULD\b/ ? $-[0] : -1;
      print $m < 0 && $s < 0 ? "NO-MODAL"
          : ($m >= 0 && $s < 0 ? "must"
          : ($s >= 0 && $m < 0 ? "should"
          : ($m < $s ? "must" : "AMBIGUOUS-BOTH")));')"
  ps_exp+="$ps_id"$'\t'"$ps_p"$'\n'
  ps_act+="$ps_id"$'\t'"$ps_d"$'\n'
done < <(q '.requirements[].id')
chk "契約内不変: priority == statement の RFC-2119 modal verb 由来 level" "$ps_exp" "$ps_act"
# (ii) level ごとの closed allowlist 逐値突合。 pre-fill mode (slot 空) ではラベルが空ゆえ ★適用しない。
if [[ -n "$ARTIFACT" ]]; then
  exp_prio="$(while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      p="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
      [[ -n "$p" && "$p" != "null" ]] || continue
      printf '%s\tIN-ALLOWLIST\n' "$p"
    done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))"
  act_prio="$(P_MUST="${PRIO_LABEL_OK[must]}" P_SHOULD="${PRIO_LABEL_OK[should]}" perl -CSD -0777 -ne '
      # ★-CSD は %ENV を decode しない — allowlist は decode してから比較する。
      use Encode qw(decode_utf8);
      my %ok;
      $ok{must}   = { map { $_ => 1 } split /\|/, decode_utf8($ENV{P_MUST}) };
      $ok{should} = { map { $_ => 1 } split /\|/, decode_utf8($ENV{P_SHOULD}) };
      while (/<span class="rq-prio rq-prio-([a-z]+)" data-prose-slot="priority" data-slot-id="[^"]*">([^<]*)<\/span>/g) {
        my ($lv,$lab)=($1,$2);
        my $good = (exists $ok{$lv} && $ok{$lv}{$lab}) ? 1 : 0;
        print "$lv\t" . ($good ? "IN-ALLOWLIST" : "NOT-IN-ALLOWLIST:$lab") . "\n";
      }' "$BODY_LIVE")"
  chk "rq-prio: (level, 可視ラベル∈allowlist) 列 == contract priority (順序・逐値束縛)" "$exp_prio" "$act_prio"
  chk "rq-prio: 全 row で優先度ラベルが非空 (per-row 非空 floor)" "$FZC_RQ_PRIO" \
    "$(perl -CSD -0777 -ne 'my $n=0; while (/<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">([^<]*)<\/span>/g){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY_LIVE")"
fi

# ============================================================================
# arm 5. ★rq-plain census + per-row 非空
# ============================================================================
echo
echo "--- arm 5: 平易行 (census / per-row 束縛 / 非空) ---"
chk "census: rq-plain 平易行占有 == $FZC_RQ_PLAIN (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PLAIN" \
  "$(grep -oE '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span>' "$BODY_LIVE" | wc -l | tr -d ' ')"
# ★per-row 束縛: slot-id (plain-<anchor>) が contract の要件 anchor 列と ★順序一致すること (relocation 封鎖)。
chk "rq-plain: slot-id 列 == contract の plain-<anchor> 順" \
  "$(while IFS= read -r id; do
       [[ -n "$id" ]] || continue
       a="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
       [[ -n "$a" && "$a" != "null" ]] || { echo "verify-srs-verification: ★contract 要件 $id の anchor が空 (fail-closed)" >&2; exit 1; }
       printf 'plain-%s\n' "$(esc "$a")"
     done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))" \
  "$(RQPK="やさしく言うと" perl -CSD -0777 -ne '
      # ★-CSD は ★入力ストリームだけ を decode し ★program text の非 ASCII literal は byte のまま — 直書きすると
      #   decode 済 subject と噛み合わず ★恒常 0-match になる (実測: 直書き版は常に空を返し FAIL していた)。
      use Encode qw(decode_utf8);
      my $K=quotemeta(decode_utf8($ENV{RQPK}));
      while (/<p class="rq-plain"><span class="rq-plain-k">$K<\/span><span data-prose-slot="plain" data-slot-id="([^"]*)">/g){ print "$1\n"; }' "$BODY_LIVE")"
if [[ -n "$ARTIFACT" ]]; then
  # ★per-row 非空 (fence: per-row 非空 floor assert)。 文書全体の集計では「どの row の slot が空か」を特定しない。
  chk "rq-plain: 全 row で平易行が非空 (per-row 非空 floor)" "$FZC_RQ_PLAIN" \
    "$(perl -CSD -0777 -ne 'my $n=0; while (/<span data-prose-slot="plain" data-slot-id="[^"]*">([^<]*)<\/span>/g){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY_LIVE")"
fi

# ============================================================================
# arm 6. ★fold ラベル逐値 + 出現数 pin (rq-norm summary / mf-kicker)
# ============================================================================
# ★平易化前ラベル (「機械層 (machine-readable)」/「normative (machine)」) への退行を ★逐値 と ★件数 の両方で撃つ。
#   件数 pin は「一部だけ旧ラベルへ戻る」部分退行も捕捉する (全数一致を要求するため)。
echo
echo "--- arm 6: fold ラベル平易化 (逐値 + 出現数) ---"
NPRE="$(q '.machine_preamble // [] | length')"
SEC_WITH_MB="$(q '[.sections[] | select((.machine_blocks // []) | length > 0)] | length')"
EXP_FOLD="$SEC_WITH_MB"; [[ "$NPRE" -gt 0 ]] && EXP_FOLD="$((SEC_WITH_MB + 1))"
chk "spec-machine-fold == machine_blocks 保有 section + preamble" "$EXP_FOLD" \
  "$(occ 'data-component="spec-machine-fold"' "$BODY_LIVE")"
# ★契約非依存 pin: 上の EXP_FOLD は contract 由来ゆえ contract ごと machine_blocks を消すと 0==0 の恒真になる。
chk "census: 機械層 fold 数 == $FZC_MF_KICKER (契約非依存 floor)" "$FZC_MF_KICKER" \
  "$(occ 'data-component="spec-machine-fold"' "$BODY_LIVE")"
chk "machine fold の mf-kicker 平易ラベル == 全 fold ($EXP_FOLD 件)" "$EXP_FOLD" \
  "$(grep -oF "<span class=\"mf-kicker\">$(esc "$MF_KICKER")</span>" "$BODY_LIVE" | wc -l | tr -d ' ')"
chk "要件 normative fold の summary 平易ラベル == |requirements| (contract 由来)" "$NREQ" \
  "$(grep -oF "<summary>$(esc "$RQ_NORM_SUMMARY")</summary>" "$BODY_LIVE" | wc -l | tr -d ' ')"
# ★同じ占有を ★契約非依存 の数値 literal でも挟む。 ★上の arm は期待値が $NREQ = ★contract 由来 ゆえ、 contract から
#   requirements を一括削除すると 0 == 0 の ★恒真 PASS になる (mf-kicker 側と同じ 0/0 恒真の穴)。
#   ★FZC_RQ_NORM は ★宣言だけして未使用だった (label 文字列に埋め込んでいたのみ = 宣言能力 > 実能力の false record・
#   独立 ceiling 指摘)。 期待値として ★実消費 することで宣言と実能力を一致させる。
chk "census: 要件 normative fold の平易 summary == $FZC_RQ_NORM (契約非依存 floor)" "$FZC_RQ_NORM" \
  "$(grep -oF "<summary>$(esc "$RQ_NORM_SUMMARY")</summary>" "$BODY_LIVE" | wc -l | tr -d ' ')"
# ★旧ラベル残存 = 0 (negative pin)。 ★上の全数一致 pin と ★独立 に効く: 全数一致は「新ラベルが N 個ある」ことしか
#   言わず、 ★fold 数自体が増えて旧ラベルの fold が追加された形 (N 新 + M 旧) は EXP_FOLD 側も動くため素通りうる。
chk "旧ラベル『機械層 (machine-readable)』残存 == 0" "0" \
  "$(grep -oF '機械層 (machine-readable)' "$BODY" | wc -l | tr -d ' ')"
chk "旧ラベル『normative (machine)』残存 == 0" "0" \
  "$(grep -oF 'normative (machine)' "$BODY" | wc -l | tr -d ' ')"

# ============================================================================
# arm 7. ★契約非依存 census (提示層 shape の占有数まとめ) + 要件 row の構造 anchor
# ============================================================================
# ★要件 row の ★構造 anchor 突合: 平易行 / 優先度バッジ / 平易化 summary を ★1 本の regex に組み込み、
#   row 単位で「head → essence → plain → norm-fold」の並びが崩れていないことを撃つ (block 粒度の並べ替え封鎖)。
echo
echo "--- arm 7: 要件 row 構造 anchor + 提示層 census ---"
chk "census: ears-requirement-row == $NREQ (|requirements|)" "$NREQ" \
  "$(occ 'data-component="ears-requirement-row"' "$BODY_LIVE")"
chk "要件 row 構造 anchor 列 (anchor, req-id, prio-slot, plain-slot) == contract 順" \
  "$(while IFS= read -r id; do
       [[ -n "$id" ]] || continue
       a="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
       [[ -n "$a" && "$a" != "null" ]] || { echo "verify-srs-verification: ★contract 要件 $id の anchor が空 (fail-closed)" >&2; exit 1; }
       printf '%s\t%s\tprio-%s\tplain-%s\n' "$(esc "$a")" "$(esc "$id")" "$(esc "$a")" "$(esc "$a")"
     done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))" \
  "$(RQNS="$RQ_NORM_SUMMARY" RQPK="やさしく言うと" perl -CSD -0777 -ne '
    # ★perl -CSD は ★入力ストリームだけ を UTF-8 decode し %ENV / program text は ★byte のまま。 非 ASCII literal を
    #   regex へ直書きすると decode 済 subject と噛み合わず ★恒常 0-match (= 実体が空 → 常時 FAIL) になる。
    use Encode qw(decode_utf8);
    my $S=quotemeta(decode_utf8($ENV{RQNS})); my $K=quotemeta(decode_utf8($ENV{RQPK}));
    while (/<div data-component="ears-requirement-row" id="([^"]*)" data-req-id="([^"]*)" data-ears-pattern="[^"]*" data-audience="human">\s*<div class="rq-head"><span class="rid">([^<]*)<\/span>(?:<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="([^"]*)">[^<]*<\/span>)?<span data-component="ears-badge" class="[^"]*">[^<]*<\/span><\/div>\s*<p class="rq-essence">.*?<\/p>\s*<p class="rq-plain"><span class="rq-plain-k">$K<\/span><span data-prose-slot="plain" data-slot-id="([^"]*)">[^<]*<\/span><\/p>\s*<details class="rq-norm" data-audience="machine"><summary>$S<\/summary><p class="rq-stmt">.*?<\/p><\/details>/g) {
      my ($anc,$rid,$vrid,$pslot,$plslot)=($1,$2,$3,$4,$5);
      $pslot = defined($pslot) ? $pslot : "-";
      # 可視 rid == data-req-id (attr-vs-visible)
      if ($rid ne $vrid) { print "VIS-MISMATCH:$rid\xe2\x89\xa0$vrid\n"; next; }
      print "$anc\t$rid\t$pslot\t$plslot\n";
    }' "$BODY_LIVE")"
# ★residue 検査 (errata-1 E-1(b)・chip 側と同型): 上の row 突合も ★厳密 shape に合う row だけ を列挙し
#   shape 外 row を ★黙って無視 する。 marker 出現数と列挙数の一致を要求して「捏造 row の同居」を落とす
#   (独立 ceiling 実弾: req-ver-024 の開きタグ前へ 1 行完結の偽 row を挿入 → rc=0 で素通っていた)。
chk "residue: row marker 出現数 == 厳密 shape で列挙できた row 数 (shape 外 row の黙殺封鎖)" \
  "$(occ 'data-component="ears-requirement-row"' "$BODY_LIVE")" \
  "$(RQNS="$RQ_NORM_SUMMARY" RQPK="やさしく言うと" perl -CSD -0777 -ne '
    use Encode qw(decode_utf8);
    my $S=quotemeta(decode_utf8($ENV{RQNS})); my $K=quotemeta(decode_utf8($ENV{RQPK}));
    my $n=0;
    $n++ while /<div data-component="ears-requirement-row" id="[^"]*" data-req-id="[^"]*" data-ears-pattern="[^"]*" data-audience="human">\s*<div class="rq-head"><span class="rid">[^<]*<\/span>(?:<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">[^<]*<\/span>)?<span data-component="ears-badge" class="[^"]*">[^<]*<\/span><\/div>\s*<p class="rq-essence">.*?<\/p>\s*<p class="rq-plain"><span class="rq-plain-k">$K<\/span><span data-prose-slot="plain" data-slot-id="[^"]*">[^<]*<\/span><\/p>\s*<details class="rq-norm" data-audience="machine"><summary>$S<\/summary><p class="rq-stmt">.*?<\/p><\/details>/g;
    print $n;' "$BODY_LIVE")"
# ★chrome-less 化 (ADR-0054 §2.1) で pack が所有することになった提示層 CSS の存在 pin (Cell 0 開示 #2)。
#   ★生成 spec は common.css を読まない ため、 これらが落ちると誰も体裁を与えない。
# ★3 宣言を ★lockstep 配列で回す (errata-1 E-3): 初版は ★:focus と .doc-locator の 2 本しか pin しておらず、
#   ★hidden-until-focus の実体である ★基底規則 .skip-link{position:absolute;left:-9999px;…} が ★無 pin だった。
#   独立 ceiling の実弾 A: 基底規則を削除しても rc=0 / OK50 で素通る = skip-link が ★常時可視 になる退行が無警備。
# ★因果の是正 (errata-1 E-3・旧コメントは過大宣言だった): 症状は ★宣言ごとに違う —
#     基底 .skip-link{...} 脱落      → skip-link が ★常時可視 (画面外退避が効かない)
#     .skip-link:focus{...} 脱落     → focus しても ★出てこない (到達可能性の喪失)
#     .doc-locator{...} 脱落         → 下部 locator が地の文に埋没する
#   旧コメントは「これ (:focus) が落ちると常時可視」と書いており、 ★pin していない基底側の症状を
#   ★pin 済の :focus が守っているかのように読ませていた (宣言能力 > 実能力の false record)。
# ★[should 判断・報告] CSS コメント化 (/* … */) による無効化は ★本 arm では塞いでいない: 生 grep ゆえ
#   宣言行をコメントで囲っても素通る (実弾 B で確認済)。 塞ぐには CSS の構文解析 (コメント除去 + 宣言の
#   ★活性判定) が要り、 それは「inline CSS を parse して有効規則集合を求める」= 提示層 shape の pin を超えた
#   ★CSS セマンティクスの検査になる (追補 13 の scope 限定と、 CSS 由来の不可視は render-gate / ceiling 領分と
#   した本 script 冒頭の実態開示にも抵触する)。 ★最小解 (a)(b)(c) を採り、 コメント化封鎖は ★admin へ移譲する
#   (この limitation を書かずに「CSS 所有分は pin 済」と報告すると false record になるため明記する)。
# ★2 種の pin を対で置く (errata-2 F-4・E-1 の occurrence 規律を CSS 側にも統一):
#   (i)  ★行頭 anchor での ★存在 pin — 宣言が「行頭に 1 本ある」ことを要求 (脱落 / rot を捕捉)。
#   (ii) ★非 anchor の ★出現回数 pin == 1 — 行計数だけだと `.skip-link{legit}.skip-link{evil}` 型の
#        ★同一行追記 が 1 のまま素通る (実弾 CONFIRMED)。 CSS は ★後勝ち ゆえ 2 個目の宣言は
#        基底規則を無効化しうる = 「宣言は在るのに効いていない」形。 ★行頭 anchor 付き occurrence でも
#        行中の 2 個目は数えられないため、 ★anchor 無しの token 出現回数 で挟む。
PACK_CSS_DECLS=(
  '^\.skip-link\{|.skip-link{|.skip-link{…}（基底・画面外退避 = hidden-until-focus の実体。脱落 → ★常時可視）'
  '^\.skip-link:focus\{|.skip-link:focus{|.skip-link:focus{…}（focus 時の可視化。脱落 → ★focus しても出ない）'
  '^\.doc-locator\{|.doc-locator{|.doc-locator{…}（下部 locator の体裁。脱落 → 地の文に埋没）'
)
for _d in "${PACK_CSS_DECLS[@]}"; do
  _re="${_d%%|*}"; _rest="${_d#*|}"; _tok="${_rest%%|*}"; _lbl="${_rest#*|}"
  chk "pack inline CSS: $_lbl" "1" "$(grep -cE "$_re" "$HTML")"
  # ★同一行 2 個目 (後勝ち上書き) の封鎖。 ★.skip-link{ は .skip-link:focus{ の prefix ではない ('{' で終端する
  #   固定文字列ゆえ) — token に '{' を含めることで prefix 誤カウントを構造的に避けている。
  chk "pack inline CSS: '$_tok' の出現回数 == 1 (同一行の後勝ち上書き封鎖)" "1" "$(occ "$_tok" "$HTML")"
done
# ★escape 健全性 (提示層 arm の最小限・化け entity は平易行/一行タイトルの新経路で最も出やすい)。
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# ★mode 縮退の ★開示 (silent skip 封鎖)。 --artifact を落とすと ★中身系 3 arm (rq-prio の allowlist 逐値 /
#   rq-prio の per-row 非空 / rq-plain の per-row 非空) が ★無言で skip され、 それでも exit 0 / RESULT PASS を
#   返す = 「緑のまま teeth だけ減る」経路が開く (独立 ceiling が実測: OK 49 → 46 で rc=0)。
#   ★scope 内の最小解として ★実行 mode と ★skip した arm 数を RESULT に明示する (CI が --artifact を落としても
#   ログ本文に縮退が残る)。 「--artifact 無しで充填済 artifact を渡したら fail-closed にする」mode 自動検出は
#   4 pack 横断の設計変更ゆえ本 cell scope 外 = admin へ移譲 (返却本文の移譲素材)。
if [[ -n "$ARTIFACT" ]]; then
  MODE_LINE="mode=artifact (prose 充填後・中身系 arm を含む全 arm を実行)"
else
  MODE_LINE="mode=pre-fill (slot 空・★中身系 3 arm を skip = teeth 縮退。 充填済 artifact の検査には --artifact が必要)"
fi

echo
echo "MODE: $MODE_LINE"
if [[ "$fail" -eq 0 ]]; then
  echo "RESULT: ADR-0054 §2.2 提示層 floor PASS (CEILING=PENDING — 平易行 / 一行タイトルの ★内容真正性 は ceiling の領分)"
  echo "  ★本 floor が見るのは 提示層 shape + containment (人間層 block 粒度の帰属) まで。 機械層 cross-fold round-trip / frozen census は本 script の対象外 (冒頭の out-of-scope 参照)。"
  exit 0
else
  echo "RESULT: FAIL (ADR-0054 §2.2 提示層 shape の逸脱)"
  exit 1
fi
