#!/usr/bin/env bash
# folio engine — srs-verification pack の ★ADR-0054 §2.2 提示層 shape floor (folio-o01k・Cell S)
#
# ★scope は ★ADR-0054 §2.2 の提示層 shape の pin に ★限定 する (Cell S 契約 追補 1 / 13 = admin 裁定 D1 scope A′)。
#   sibling の verify-verification.sh / verify-spec.sh / verify-relations.sh は「pack 全体の fabrication-free floor」
#   (件数・block fidelity・cover-meta・機械層 round-trip・census・containment …) を担う ★フル verifier だが、
#   本 script は ★その fork ではない — Cell S が新設した提示層 arm だけを持つ ★部分 verifier である。
#
# ★★out-of-scope の ★実態開示 (silent 欠落は「範型踏襲済」の誤報告になる・追補 13)。 以下は本 script が ★検査しない:
#   - containment 3 レベル完全子数束縛 (kids / bkids / cbkids) + HTML5 同型 tokenizer + MECHPIN  → folio-3zr4
#     (現 folio-3zr4 の description は rules / relations 限定ゆえ ★srs 分の追記が要る = admin へ申送り)。
#   - 機械層 cross-fold round-trip (機械層 block の逐語 round-trip)                              → folio-e706
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
echo "  ★scope = 提示層 shape のみ (containment=folio-3zr4 / 機械層 round-trip=folio-e706 / census=folio-vhew は本 script 対象外)"

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
if [[ -z "$SEC_NUMS" ]] || printf '%s\n' "$SEC_NUMS" | grep -q 'NO-SECTION-NUMBER'; then
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
  echo "  ★本 floor は提示層 shape のみを見る。 containment / 機械層 round-trip / frozen census は本 script の対象外 (冒頭の out-of-scope 参照)。"
  exit 0
else
  echo "RESULT: FAIL (ADR-0054 §2.2 提示層 shape の逸脱)"
  exit 1
fi
