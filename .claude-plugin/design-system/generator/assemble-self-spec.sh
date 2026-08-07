#!/usr/bin/env bash
# folio engine (folio-cuom) — spec-pack 決定的 assembler の FORK (doc-type=spec / folio-self-spec self-host)
#
# ★assemble-verification.sh の FORK (8dkl self-spec flip の bootstrap = Leg A)。 共有 core (lib/) 無改変。
#   base に verification を選ぶ理由: assemble-spec.sh (rules 用) は head の folio-* meta を 4 本しか運ばず
#   (emit_pack_head_meta 相当を持たない)、 self-spec canonical の 7 本 (doc-type/layer/version/glossary-automark/
#   status/stakeholders/xref-completeness) を再現できない。 verification fork は追加 4 meta emit を既に持つ。
# ★self-spec 固有差分 (fork 元との delta・全て ★実測駆動):
#   (1) ★要件 0 件 — EARS 凡例を ★conditional 化 (|requirements| == 0 なら emit しない)。 要件 row / badge /
#       normative fold / 優先度バッジ は元より 0 件になる (emitter は残置 = 将来 要件が入れば動く)。
#   (2) ★meta identity 全面差し替え + ★doc_id literal guard (M3) — doc_type == spec は 4 契約が共有し識別力ゼロ。
#   (3) ★照会種別 4 種 (原則 P-x / 決定記録 ADR / 規約要件 rules REQ-* / 検証仕様 REQ-VER) — 静的 band 見出しを
#       ★実在種別ちょうど に合わせる (over-promise も under-promise もしない)。
#   (4) ★count 定数 (RICH_FIELD_MIN / MACHINE_FIELD_MIN と型別内訳) は base 値を ★複写せず self-spec contract から
#       ★実測再導出 (M6)。 複写は空撃ち floor = fail-open。
# 入力 spec contract (YAML) → 人間プレゼン HTML (srs.css inline、 自己完結)。
# SRS (assemble-srs.sh) / ADR (assemble-adr.sh) / research (assemble-research.sh) / principle (assemble-principle.sh)
# と *同型* の機構を spec-pack schema (sections / requirements(EARS) / references(非終端 照会) / glossary) へ適用する:
#   - 内容・構造は contract から決定的組立。 元データに無い section・要件・照会・block を生成できない (fab-free by construction)。
#   - 全自由記述値は HTML escape してから注入。 id 重複・tab/改行・未知 EARS/role・集合外参照・★未対応 block type は
#     validate() が **fail-closed** で生成前に拒否 (silent drop 禁止)。
#   - prose スロット (cover-summary / 章リード chapter-lead-NN) は *空* で出力し ③ inject-prose.sh が充填。
#   - 内容 (section essence / 要件 essence・normative / 照会 / 用語) は全て contract = SSoT。 opus は読みの足場 prose のみ。
#
# ★rules の hallmark (principle 終端 / SRS RTM の *中間*): EARS 章立て規範文 + **非終端 照会** (前方 references を持つ)。
#   references[] は他文書 (constitution P-x / ADR / verification REQ-VER) への前方照会 = rolemap edge + external-ref で
#   graph に接続する (verify-graph.sh)。 inbound は受ける側 (principle pack が宣言済)。
#
# ★B6 の合格条件 = lib/ (core) を 1 バイトも変えず純粋 pack として挿さること (rule-of-three の B6 完成サイン)。
# inject-prose.sh も SRS/ADR/research/principle と無改変共用 (data-slot-id ベースで pack 非依存)。
#
# usage: assemble-spec.sh <spec-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-spec.sh <spec-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-spec: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-spec: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-spec: yq required" >&2; exit 1; }

# ---- core 共通層 (q/esc/ico/band/cover骨格/glossary/footer/finalize) ----
# B2 (folio-5ua): SRS/ADR/research/principle-pack と共通の idiom は lib/common.sh から source。 本 file は spec-pack 固有
# (sections/blocks emitter / requirements(EARS) / references(非終端 照会)) を残す。
# ★term-inline (mark_terms) は spec-pack では不使用 = rules の用語は plain_short(やさしい言い換え) を持たないため
#   (glossary は term + def のみ・rules.html の span.term[data-tooltip] 由来)。 ゆえ core_init_term_inline は呼ばない。
source "$SCRIPT_DIR/lib/common.sh"

# EARS pattern (canonical = rules.html の data-ears-pattern 値) → 表示 class / label (verify-spec.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table の「用途」列 SSoT に一致させる (folio-2jr: 旧 禁止/機能 は §6 異常応答/機能オプション と
#   semantic drift していた — unwanted は「禁止」でなく異常時の振る舞い、 optional は機能の有無条件。 view を SSoT から導出し drift 根絶)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1: 凡例 label は専門語ゆえ非エンジニアに意味が自明でない →
#   各型に平易タイミング語を併記。 §6 章リード prose の言い換え (常に/きっかけ/状態の間/機能/異常時) と方向一致・verify-spec と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )
# 抽象ロール (B0 论点2 照会 graph)。 references (前方照会) の role allowlist。 verify-common.sh の CROSS_DOC_ROLE_ALLOWLIST と一致。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
# ============================================================================
# ★ADR-0054 (flip 済 spec 提示層の標準形) lockstep 定数群 — verify-self-spec.sh と ★二重保守 (detect↔remediate parity)。
#   範型 = Cell R (assemble-relations.sh @ 88b3918) / Cell U (assemble-spec.sh @ 5ed89f3)。 verification の §番号は
#   §0..§6 の ★連番 だが、 帯番号は Cell U と同じく ★見出しから導出 する (下記 heading_secnum) — 連番算術に依らず
#   「.num == 見出しの §N」を ★見出し自身を trust anchor として構造束縛するため (両側 hardcode の同意に依らない)。
# ============================================================================
# ★role の平易語 map (ADR-0054 §2.2「role ラベルは平易語で表示する」)。 ★attr (data-ref-role) は ★機械 token を保持し、
#   可視ラベルのみ map を適用する。 map に無い role は emit 時 hard error (silent 英語生表示を封鎖)。
#   ★Cell R/U と ★逐語同一 (4 spec 横断で 1 entity = 1 canonical name・再発明禁止)。
declare -A ROLE_PLAIN=(
  [implementation]="この規約が実装する原則" [rationale]="そう決めた理由の記録" [claim]="この文書が満たすと主張する要件"
  [exploration]="探索の記録" [principle]="拠って立つ原則" [verification]="どう確かめるかの仕様"
)
# ★RFC-2119 優先度 (ADR-0054 §2.2「RFC-2119 優先度の平易バッジ (必須 / 推奨)」)。 contract requirements[].priority の
#   closed allowlist → 表示 class / 平易語の canonical 語幹。 verify-self-spec.sh と二重保守 = detect↔remediate parity。
#   ★badge の可視ラベルは prose slot (人間層 edit-SSoT) が持つが、 その値は本 allowlist の ★有限集合 に属さねば
#   ならない (verify が label↔level を ★逐値突合 = must の行に「推奨…」や「必須ではない」と書く label 詐称を封鎖)。
#   ★前方一致でなく逐値集合である理由: 否定接尾 (「必須ではない」) は語幹で始まるため prefix 判定を素通りする
#   (Cell R self-review major-3 / ehar クラス = 負の主張ラベルへの束縛漏れ)。
#   ★集合の拡張には prose manifest / 本 allowlist / verify-self-spec.sh の同名配列の三点同時更新が必要 (fail-closed)。
declare -A PRIO_OK=( [must]=1 [should]=1 )
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 verify-self-spec.sh の STATIC_HEADING_TAILS と
#   二重保守。 ★見出しは ★実在する照会種別のみを約束する (ADR-0054 §2.2 over-promise 禁止)。 self-spec の references は
#   ★4 種 が実在する (fork 元 verification の 2 種・rules の 3 種と異なる = 逐語流用でなく ★実測導出。 実測:
#   role=implementation 8 (constitution P-x) + role=rationale 16 (decisions/) + role=claim 8 (rules.html#req-*)
#   + role=verification 1 (verification.html#req-ver-001) = 33)。
# ★§番号は literal 固定せず contract の最終 section 見出しから ★導出 する (derive_static_band_headings)。
STATIC_BAND_HEADING_TAILS=("上位文書への前方照会 — 原則・決定記録・規約要件・検証仕様へつながる" "本文に出てくる専門語のやさしい説明")
STATIC_BAND_HEADINGS=()
STATIC_BAND_NUMS=()
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token に固定・4 spec 横断で同一)。
#   ★class は付けない (normative/informative census を不変に保つ)。 verify-self-spec.sh の同名配列と二重保守。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2・wave 恒常 2)。 verify-self-spec.sh と二重保守。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# CSS tint allowlist (section.tint / band)。
declare -A TINT_OK=( [brand]=1 [violet]=1 [warn]=1 [info]=1 [ok]=1 [bad]=1 )
# 対応 block type (これ以外 = silent drop の疑い → fail-closed abort)。
BLOCK_TYPE_ALLOW='prose|note|list|code|table|mermaid|subhead|requirements'
# ★人間層 rich field の inline tag allowlist (folio-aduv)。
#   rich field (essence / statement / table cell / caption) は inline HTML を *逐語* 保持し assembler が RAW emit する
#   (= xref link / term tooltip / delta marker / <code> mask の復元手段)。 raw emit ゆえ 旧 esc() による無差別 escape が
#   担っていた「契約由来の生 markup が構造へ漏れない」保護が効かなくなる。 そこで escape の代わりに
#   ★allowlist の fail-closed abort で置き換える (escape より *強い* 保証: <script> 等は escape して表示するのでなく
#   生成そのものを拒否する)。 allowlist = canonical verification.html の人間層 rich field に実在する inline 要素
#   (実測: code 376 / span 164 / a 140 / strong 61 / ins 4 / del 1) + 同類の非実行 inline 要素のみ。
#   block/実行系 (script/style/iframe/form/p/div/pre …) は人間層 rich field に現れてはならない (現れたら構造破壊か注入)。
RICH_INLINE_ALLOW='a|span|code|strong|em|b|i|ins|del|sub|sup|abbr|br|kbd|samp|var|small|q|cite|time|wbr'
# ★機械層 (w1f cell-2 / ADR-0045) 対応 block type。 cell-1 schema = data-audience="machine" 自由文 (p→prose / aside→note / ul→list)。
#   ★tr0 (verification): div.demoted (ADR-0040 機械層降格分・<p>/<ul>/<pre><code> 内包) を demoted として追加。
#   ★folio-aduv: dl (dl.doc-meta = 文書前文の機械層 定義リスト) を追加。 cell-1 の死角で silent drop されていた分。
#   これ以外は silent drop の疑い → fail-closed abort (人間層 BLOCK_TYPE_ALLOW と対称)。
MACHINE_BLOCK_TYPE_ALLOW='prose|note|list|demoted|dl'

# ---- icon SVG (spec-pack 固有 + 共用。 section index で循環選択する静的デザイン資産・contract 由来でない) ----
ICO_GUIDE='<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
ICO_DIR='<path d="M3 7a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'
ICO_TAG='<path d="M20.6 13.4 13 21l-9-9V4h8z"/><circle cx="7.5" cy="7.5" r="1.2"/>'
ICO_CODE='<path d="M16 18l6-6-6-6"/><path d="M8 6l-6 6 6 6"/>'
ICO_DELTA='<path d="M12 3l9 16H3z"/>'
ICO_EARS='<path d="M4 12h4l3 8 4-16 3 8h2"/>'
ICO_LAYERS='<path d="M12 2 2 7l10 5 10-5z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>'
ICO_SCRIPT='<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>'
ICO_LINK='<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>'
ICO_GAVEL='<path d="M14 13l-7 7"/><path d="M5 12l7-7 5 5-7 7z"/><path d="M16 3l5 5"/>'
ICO_EYE='<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>'
ICO_GRID='<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>'
ICO_ARROW='<path d="M5 12h14M12 5l7 7-7 7"/>'
SECT_ICONS=("$ICO_GUIDE" "$ICO_DIR" "$ICO_TAG" "$ICO_CODE" "$ICO_DELTA" "$ICO_EARS" "$ICO_LAYERS" "$ICO_SCRIPT" "$ICO_LINK" "$ICO_GAVEL" "$ICO_EYE" "$ICO_GRID")

# ★rich field の全値を document 順に吐く (validate / 監査で 1 箇所に集約 = 対象漏れの二重保守を防ぐ)。
rich_field_values() {
  q '[ .sections[].essence,
       (.sections[].blocks[]? | select(.type=="subhead") | .essence),
       (.sections[].blocks[]? | select(.type=="table") | (.caption // "")),
       (.sections[].blocks[]? | select(.type=="table") | .headers[]),
       (.sections[].blocks[]? | select(.type=="table") | .rows[][]),
       (.sections[].blocks[]? | select(.type=="mermaid") | (.caption // "")),
       .requirements[].essence,
       .requirements[].statement ] | .[]'
}

# ★人間層 rich field の inline 健全性 (fail-closed)。 RICH_INLINE_ALLOW 外のタグ・event handler 属性・危険 URL を
#   1 つでも見つけたら生成前に abort する (旧 esc() 経路が担っていた注入保護の後継・escape でなく拒否)。
#
# ★URL 検査は「entity decode 後の *肯定* allowlist」で行う (literal 'javascript:' の部分文字列一致では *ない*)。
#   理由 (実弾で確認済の fail-open): browser は HTML 属性値の character reference を decode してから scheme を
#   解釈するため href="&#106;avascript:alert(1)" は live な javascript: link として成立する。 literal 一致の
#   /javascript:/i は これを素通しし、 <a> は tag allowlist 内・on*= も無いので 3 検査すべてを擦り抜けた
#   (= 旧 esc() 経路の方が強い分岐が残る = 「escape より強い保証」の宣言に反する回帰)。
#   ★否定列挙 (javascript:/data:/vbscript: … を弾く) は partial-enumeration trap ゆえ採らない。 契約実測の href は
#   fragment (#…) / 相対 *.html / 相対 *.md の 3 形のみなので、 その肯定列挙で fail-closed にできる。
#   新しい URL 形が正当に必要になったら本 allowlist を *意図的に* 広げること (静かに通さない)。
#
# ★★検査本体は「naive regex で危険形を探す」のでなく「★厳密 tokenizer で属性列を読み、 肯定 allowlist に
#   合致しないものを全て落とす」形にする (partial-enumeration からの構造的脱出)。
#   naive regex 版が実 browser parser と乖離して live な注入を通した実証 4 形 (html5lib 突合済):
#     B1 <a href="#x"onclick="alert(1)">  … /\son[a-zA-Z]+=/ は on の前に \s を要求するが、 HTML5 の
#        after-attribute-value-quoted state は非空白を missing-whitespace-between-attributes として ★回復し
#        before-attribute-name へ reconsume するため onclick は属性として成立する (parser は LIVE と読む)。
#     B2 <a href=%sjavascript:…%s>  (single-quote) … 値抽出が "([^"]*)" 固定ゆえ URL 検査に ★一度も入らない。
#     B3 <a href=javascript:…>      (unquoted)     … 同上。
#     B4 <a title=">" href="javascript:…">          … ([^>]*)> が ★quote 内の > で早期終端し href が属性列の外へ落ちる。
#   いずれも tag は allowlist 内 (a) ゆえ tag 検査を通過し、 3 検査すべてを擦り抜けた = 改修前 esc() より弱い後退。
#   ★対策の骨子 (列挙をやめて構造で閉じる):
#     (1) 値の 3 形 (double / single / unquoted) を明示的に扱い、 ★quote 内の > で終端しない tokenizer で読む。
#     (2) ★属性名の肯定 allowlist を課す → on*= は「allowlist 外の属性名」として ★形に依らず一律に落ち、
#         \s 依存 heuristic を廃止できる (B1 が構造的に閉じる)。 style/srcset 等の未列挙 sink も同時に閉じる。
#     (3) URL 検査は tokenizer が返した ★全 URL 属性値へ quoting 形に依らず適用する (B2/B3/B4 が閉じる)。
#     (4) ★fail-closed residue: 属性列を strict grammar で完全に tokenize しきれなければ理由を問わず abort。
#         未知の parser-differential を「通す」でなく「落とす」側へ倒す (これが列挙からの脱出の要)。
# ★属性名 allowlist は契約実測 (7 種: class 224 / href 140 / data-tooltip 42 / data-term 18 / data-delta-id 5 /
#   data-delta-date 4 / data-delta-superseded-by 1) + inert な id/title/datetime/lang/dir。 いずれも script 実行・
#   外部 fetch の sink を持たない。 ★style / srcset / on* 等の sink は *意図的に* 含めない (広げるなら明示的に)。
RICH_ATTR_ALLOW='class|href|id|title|datetime|lang|dir|data-tooltip|data-term|data-delta-id|data-delta-date|data-delta-superseded-by'
RICH_HREF_ALLOW_DESC='#fragment / 相対 *.html(#frag) / 相対 *.md(#frag) / https://'
# ★検査対象の実測下限 (現契約 = 337 値)。 rich_field_values の query drift / 抽出規約の破綻で ★検査対象そのものが
#   痩せたら (0 件はもちろん ★過少も) それ自体を FAIL にするための pin。 契約が正当に育って下限を超えたら
#   ★意図的に上げること (静かに下げない = 緩和は常に明示的な行為であること)。
# ★「下限」であって総数固定でない理由: 契約の成長 (rich field の追加) は正当ゆえ通す。 塞ぎたいのは ★減少方向
#   (= 被覆の喪失) だけである。
# ★instance 固有値の扱い (汎化 fence): 本 file は verification 専用 fork (validate() の doc_type==spec 束縛を参照)
#   ゆえ、 本定数は ★その fork の実測値。 同型を d7bq/bxpm へ波及させる際は ★機構 (被覆量 assert) をそのまま持ち、
#   値だけ各 pack の実測へ差し替えること (機構を落として値だけ移すと恒真 PASS が復活する)。
# ★M6 (folio-cuom): base (verification=352) を ★複写せず self-spec contract から ★実測再導出 した値。
#   導出 = 下の RICH_FIELD_TYPE_MINS の総和 (7 + 13 + 6 + 24 + 124 + 9 + 0 + 0 = 183) で、 同じ集合の別表現。
#   ★複写は「契約より大きい下限 = 恒真 FAIL」か「契約より小さい下限 = 空撃ち floor (fail-open)」のどちらかになる。
RICH_FIELD_MIN=183
# ★型別の実測下限 (folio-eccf S5・RICH_FIELD_MIN の count-only 残余の解消)。 "min:::label:::query" の 3 つ組。
# ★なぜ総数下限だけでは足りないか (総数は ★型間の相殺を見逃す):
#   RICH_FIELD_MIN は「総数が減ったら FAIL」しか言えない。 契約が正当に育って table-rows が 114→124 になった後に
#   sect-essence (7 値) の query が drift すると 総数は 343 ≥ 337 ゆえ ★緑のまま 7 値が無検査になる。
#   すなわち ★被覆の喪失が契約の成長に紛れて隠れる。 ゆえ ★型ごとに下限を持ち、 型単位の減少を個別に撃つ。
# ★実測 (現契約 = self-spec): 7 + 13 + 6 + 24 + 124 + 9 + 0 + 0 = 183 = RICH_FIELD_MIN (総数と内訳は同じ集合の別表現)。
# ★req-essence / req-statement が 0 なのは ★実測の事実 (self-spec は EARS 要件を 1 件も持たない)。 下限 0 は
#   単独では teeth を持たないが、 ★下の総和恒等式が「この型が 0 である」ことを ★総数側と束縛する ため無意味ではない
#   (0 を「無い」と誤魔化さず実測のまま置く = SSoT 規律。 将来 要件が入れば恒等式が破れて更新を強制する)。
# ★table-caption 6 / mermaid-caption 9 の非対称は実測どおり: canonical の 6 表は <caption> を持たず (契約は空文字列を
#   6 本持つ)、 9 図は全て figcaption を持つ。 「空文字列も 1 値として数える」のが本表の計数規約 (rich_field_values と同一)。
# ★二重保守の封鎖 (この表と rich_field_values は同じ集合を ★別記法で列挙する = drift しうる):
#   ゆえ validate_rich_inline で ★sum(型別) == rich_field_values の総行数 を ★恒等式として課す。
#   drift すれば恒等式が破れて abort する = 表と本体の一致を ★機械が保証する (人間の規律に依存しない)。
#   ★query 記法に注意: 本表の .sections[].essence は ★末尾カンマを持たない (rich_field_values 側とは別記法)。
#   これは偶然ではない: test-adversarial の F18g は assembler 中の `.sections[].essence,` (★カンマ込み) を sed で
#   drift させて guard 喪失を撃つため、 本表が同形だと ★両方が同時に mutate されて F18g の意味が変わる。
RICH_FIELD_TYPE_MINS=(
  '7:::sect-essence:::.sections[].essence'
  '13:::subhead-essence:::[.sections[].blocks[]? | select(.type=="subhead") | .essence] | .[]'
  '6:::table-caption:::[.sections[].blocks[]? | select(.type=="table") | (.caption // "")] | .[]'
  '24:::table-headers:::[.sections[].blocks[]? | select(.type=="table") | .headers[]] | .[]'
  '124:::table-rows:::[.sections[].blocks[]? | select(.type=="table") | .rows[][]] | .[]'
  '9:::mermaid-caption:::[.sections[].blocks[]? | select(.type=="mermaid") | (.caption // "")] | .[]'
  '0:::req-essence:::.requirements[].essence'
  '0:::req-statement:::.requirements[].statement'
)
# ★人間層の絶対 URL scheme allowlist (perl regex 片・下の $href_ok へ env 経由で埋まる)。
#   ★https のみ (http:// は不可) = 改修前の literal と同値。 実測: 人間層 rich field の href 140 件は
#   ★全て相対/fragment で絶対 URL は 0 件ゆえ、 本 scheme を狭く保っても現契約は通る (F18e 空撃ちが pin)。
RICH_HREF_SCHEME='https'

# ---- ★機械層 (machine free-prose) rich field の sanitization (folio-eccf S1・人間層との ★fail-closed 対称化) ----
# ★何を「対称」にするか (誤読すると全機械層が恒真 abort する):
#   対称にするのは ★fail-closed 規律 (tokenizer で読み emit 前に abort する) であって ★allowlist の同一ではない。
#   機械層 (ADR-0045 dual-audience の canonical form) は ★block 構造要素を正当に内包するため
#   (実測: p18 / div6 / dt6 / dd6 / ul2 / li6 / pre2)、 人間層 RICH_INLINE_ALLOW (inline 限定) を流用すると
#   ★素の canonical 契約が abort する (恒真 abort = 生成不能)。 逆に人間層 allowlist を block まで広げるのは
#   人間層を fail-open 化する退行 (人間層 rich field に block が現れたら構造破壊か注入である、 が現行の設計)。
#   ゆえ ★層ごとに別 allowlist・別抽出関数・別下限を持ち、 ★tokenizer 本体だけを共用する。
# ★allowlist は canonical contract の ★実測タグ集合を SSoT に決める (想像列挙禁止)。
#   実測 (machine_preamble + sections[].machine_blocks の html/items): a62 strong29 code27 p18 span11 li6 dt6 div6 dd6 ul2 pre2。
#   = 人間層 inline 集合の superset として block 群 (p|div|dl|dt|dd|ul|ol|li|pre|aside) を足した形で覆える。
#   dl/ol/aside は現 field 内に実在しない (dl/aside は emitter 側の wrapper・ol は ul の同型 sibling) が、
#   ★block 群として一体で許可する (mandate 明示)。 script|style|iframe|object|embed|form|input|button|link|meta は
#   ★意図的に不在 = 現れたら fail-closed abort する。
MACHINE_RICH_ALLOW="${RICH_INLINE_ALLOW}|p|div|dl|dt|dd|ul|ol|li|pre|aside"
# ★属性名は人間層と同一で足りる (実測: href62 / class17 / data-tooltip15 / data-term9 = 人間層 allowlist の部分集合)。
#   ★別名で束縛する理由: 将来 機械層に固有属性が要ったとき ★人間層を巻き添えで広げない (緩和の scope を層に閉じる)。
MACHINE_ATTR_ALLOW="$RICH_ATTR_ALLOW"
# ★機械層の絶対 URL scheme: ★http も許可する。 人間層 (https のみ) からの ★意図的な差分であり、 根拠は canonical 実測
#   = 機械層 href 62 件の内訳は 相対/fragment 51 + https 10 + ★http 1 (http://requirekit.ai/… = 原本 §参考文献の外部出典)。
#   ★https のみに絞ると素の canonical が abort する (= 恒真 abort) ため、 実測を SSoT に http を明示許可する。
#   ★これは注入面の緩和ではない: 危険 scheme (javascript:/data:/vbscript: …) は ★肯定 allowlist の構造上
#   列挙に依らず一律に落ちる (否定列挙をしていないので http 追加が他 scheme を開くことはない)。
MACHINE_HREF_SCHEME='https?'
MACHINE_HREF_ALLOW_DESC='#fragment / 相対 *.html(#frag) / 相対 *.md(#frag) / http(s)://'
# ★機械層 field の実測下限 (現契約 = 38 値)。 人間層 RICH_FIELD_MIN=183 とは ★別物・★merge 禁止
#   (合算すると両方の pin が壊れ、 かつ層別 allowlist の適用先が混ざる)。 意味論は RICH_FIELD_MIN と同じ「下限」で、
#   ★減少方向 (被覆の喪失) だけを塞ぐ。
# ★M6 (folio-cuom): base (verification=34) を ★複写せず self-spec contract から ★実測再導出。
#   導出 = 下の MACHINE_FIELD_TYPE_MINS の総和 (1 + 0 + 31 + 6 = 38)。
MACHINE_FIELD_MIN=38
# ★機械層の ★型別 (= 抽出分岐別) 実測下限。 人間層 RICH_FIELD_TYPE_MINS と ★同型の機構・★別の定数束 (merge 禁止)。
# ★なぜ総数下限 (34) だけでは足りないか — 同一 diff の S5 が人間層で ★既に証明した穴と ★同型ゆえ:
#   MACHINE_FIELD_MIN=38 は ★たまたま現総数と一致している ので、 今日は任意分岐の drift が総数減で捕捉される。
#   しかし契約が正当に育って machine_blocks が 1 値増えた瞬間 (総数 39)、 machine_preamble 分岐の query が
#   drift しても 37+1 = 38 ≥ 38 ゆえ ★総数 assert は緑のまま で、 preamble 1 値の RAW emit が ★無検査になる。
#   = 被覆の喪失が契約の成長に紛れて隠れる (S5 の 337/360 と厳密に同じ機序)。 ゆえ ★分岐ごとに下限を持つ。
# ★実測 (現契約 = self-spec): 1 + 0 + 31 + 6 = 38 = MACHINE_FIELD_MIN (総数と内訳は同じ集合の別表現)。
#   ★preamble-items が 0 なのは ★実測の事実 (現 machine_preamble に type=list が無い)。 下限 0 は単独では teeth を
#   持たないが、 ★下の総和恒等式が「この分岐が 0 である」ことを ★総数側と束縛する ため無意味ではない
#   (0 を「無い」と誤魔化さず ★実測のまま置くのが SSoT 規律。 将来 list が入れば恒等式が破れて更新を強制する)。
# ★二重保守の封鎖: 本表と machine_field_values は ★同じ集合を別記法で列挙する = drift しうる。 ゆえ
#   validate_machine_inline で ★sum(分岐) == machine_field_values の総行数 を ★恒等式として課す (人間層と同型)。
# ★query 記法に注意 (人間層 RICH_FIELD_TYPE_MINS と同じ理由): 本表は pipe 周りを ★空白なし で書き、
#   machine_field_values 側 (★空白込み) と ★意図的に別記法にする。 guard 喪失 mutation-kill (敵対 M17b/M17c・
#   selftest S1-c) は machine_field_values 側の ★空白込み 記法を sed で drift させるため、 本表が同形だと
#   ★表と本体が同時に mutate されて mutation-kill の意味が変わる (恒等式が破れず穴が残る)。
#   ★本 comment に mutation の ★対象 literal を書いてはならない: sed は comment にも当たるため、 literal を
#   書くと machine_field_values の記法が変わっても comment 側が一致して ★空撃ち検査 (diff -q) が誤って
#   「mutation 発火」と読む (= 空撃ち検出が壊れる)。 ゆえ記法差は ★散文で述べ literal は置かない。
MACHINE_FIELD_TYPE_MINS=(
  '1:::preamble-html:::.machine_preamble[]?|select(.type != "list")|.html'
  '0:::preamble-items:::.machine_preamble[]?|select(.type == "list")|.items[]'
  '31:::block-html:::.sections[].machine_blocks[]?|select(.type != "list")|.html'
  '6:::block-items:::.sections[].machine_blocks[]?|select(.type == "list")|.items[]'
)
# ★機械層 raw-emit field の全値を吐く (emit_machine_block の raw emit 経路と ★1:1 対応させる)。
#   emit 側: prose/note/demoted/dl は .html を、 list は .items[] を ★RAW emit する。 ゆえ検査対象も同じ 2 経路。
machine_field_values() {
  q '[ (.machine_preamble[]? | select(.type != "list") | .html),
       (.machine_preamble[]? | select(.type == "list") | .items[]),
       (.sections[].machine_blocks[]? | select(.type != "list") | .html),
       (.sections[].machine_blocks[]? | select(.type == "list") | .items[]) ] | .[]'
}

# ---- ★tokenizer 本体: 人間層 / 機械層が ★共用する唯一の実体 (parser-differential の二重保守を禁じる) ----
# ★共用する理由: 上記 4 形 (B1-B4) の parser-differential 封鎖は ★層に依らない性質ゆえ、 層ごとに写経すると
#   片方だけが退行する (実際 機械層は本 S1 まで ★検査ゼロだった = 非対称の残余)。 層差は env だけで表現する:
#     ALLOW = tag allowlist / ATTRALLOW = 属性名 allowlist / SCHEMEALLOW = 絶対 URL の scheme (perl regex 片)。
RICH_TOKENIZE_PL='
    BEGIN {
      our %bad; our $re = qr/^(?:$ENV{ALLOW})$/i; our $attr_re = qr/^(?:$ENV{ATTRALLOW})$/i;
      # URL を載せうる属性 (allowlist 内に現れたら decode 後 href_ok を課す)。
      our $url_attr = qr/^(?:href|src|xlink:href|formaction|action)$/i;
      # character reference decode (数値 10/16 進 + 主要名前付き)。 URL scheme 判定の *前* に必ず通す。
      sub decode_refs {
        my ($s) = @_; $s //= "";
        $s =~ s/&#x([0-9a-fA-F]+);?/chr(hex($1))/ge;
        $s =~ s/&#(\d+);?/chr($1)/ge;
        my %n = ("amp"=>"&","lt"=>"<","gt"=>">","quot"=>"\"","apos"=>"\x27","Tab"=>"\t","NewLine"=>"\n","colon"=>":","sol"=>"/");
        $s =~ s/&([a-zA-Z]+);?/exists $n{$1} ? $n{$1} : "&$1;"/ge;
        # decode は冪等になるまで回す (多重符号化 &amp;#106; → &#106; → j を取り逃さない)。
        return $s;
      }
      sub decode_full {
        my ($s) = @_; my $prev = "";
        for (1..5) { last if $s eq $prev; $prev = $s; $s = decode_refs($s); }
        return $s;
      }
      # 肯定 allowlist: 制御文字・空白を除去した decode 後 URL が下記のいずれかに *完全一致* すること。
      our $href_ok = qr{^(?:
            \#[^\s]*                                   # 同一文書 fragment
          | (?:\.{1,2}/)*[A-Za-z0-9._/-]+\.html(?:\#[^\s]*)?   # 相対 .html (+fragment)
          | (?:\.{1,2}/)*[A-Za-z0-9._/-]+\.md(?:\#[^\s]*)?     # 相対 .md   (+fragment)
          | (?:$ENV{SCHEMEALLOW})://[A-Za-z0-9._~:/?\#\[\]@!$&\x27()*+,;=%-]+   # scheme allowlist (layer 別 env)
        )$}x;
    }
    # ---- ★strict tokenizer: 実 HTML parser の tag/属性 grammar を明示的に辿る (naive regex の parser-differential 封鎖) ----
    # ★perl 側 message は ★ASCII のみ: -CSD は STDOUT を :utf8 にするが、 script 中の日本語リテラルは
    #   use utf8 が無い限り byte 列として扱われ ★二重符号化して化ける (実測)。 日本語の説明は bash 側の
    #   echo が持ち、 perl は機械可読な ASCII token だけを返す (test の理由文字列照合も本 token に合わせる)。
    my $s = $_; my $n = length($s); my $i = 0;
    while ($i < $n) {
      # 次の "<" まではテキスト。 HTML5 と同じく "<" + 非英字 (例: "a < b") は tag 開始でなく literal text。
      my $lt = index($s, "<", $i);
      last if $lt < 0;
      my $rest = substr($s, $lt);
      # ★markup declaration / PI (<!-- … --> / <!DOCTYPE> / <?…>) は契約に存在しない。 comment 内へ毒を隠す
      #   経路を残さないため tokenize せず ★一律 abort (fail-closed residue)。
      if ($rest =~ /^<[!?]/) { $bad{"<! or <? (MALFORMED-MARKUP; declaration/comment not allowed in rich field)"}++; last; }
      unless ($rest =~ /^<(\/?)([a-zA-Z][a-zA-Z0-9]*)/) { $i = $lt + 1; next; }   # literal "<" として読み飛ばす
      my ($close, $tag) = ($1, $2);
      $bad{"<$tag> (TAG-NOT-ALLOWED)"}++ unless $tag =~ $re;
      $i = $lt + 1 + length($close) + length($tag);
      # ---- 属性列を strict grammar で読む ----
      # ★属性の直前には空白が MUST。 HTML5 は欠落を回復して属性化する (B1) が、 我々は回復せず落とす。
      while (1) {
        my $ws = 0;
        while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; $ws = 1; }
        # ★fail-closed residue: tag が ">" で閉じないまま値が尽きた (eof-in-tag)。 実 browser は tag を破棄するので
        #   inert ではあるが、 「strict grammar で完全に tokenize しきれない形は理由を問わず落とす」規律を優先する
        #   (未知の parser-differential を通さない側へ倒す = 列挙からの脱出の要)。
        if ($i >= $n) { $bad{"<$tag> (MALFORMED-MARKUP; eof-in-tag = unterminated tag)"}++; last; }
        my $c = substr($s, $i, 1);
        if ($c eq ">") { $i++; last; }
        if ($c eq "/" && substr($s, $i + 1, 1) eq ">") { $i += 2; last; }
        if ($close) { $bad{"</$tag> (MALFORMED-MARKUP; attributes on end tag)"}++; last; }
        unless ($ws) {
          # 例: <a href="#x"onclick="alert(1)"> … HTML5 は onclick を属性として ★成立させる (parser 実測)。
          $bad{"<$tag> (MALFORMED-MARKUP; missing-whitespace-between-attributes)"}++; last;
        }
        unless (substr($s, $i) =~ /^([a-zA-Z_:][-a-zA-Z0-9_:.]*)/) {
          $bad{"<$tag> (MALFORMED-MARKUP; unreadable attr name: " . substr($s, $i, 12) . ")"}++; last;
        }
        my $name = $1; $i += length($name);
        while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; }
        my ($has_val, $raw) = (0, "");
        if (substr($s, $i, 1) eq "=") {
          $i++;
          while ($i < $n && substr($s, $i, 1) =~ /\s/) { $i++; }
          my $r = substr($s, $i);
          # ★値の 3 形を明示的に扱う。 quote 内の ">" では ★終端しない (B4)。
          if    ($r =~ /^"([^"]*)"/)            { $raw = $1; $i += length($1) + 2; $has_val = 1; }
          elsif ($r =~ /^\x27([^\x27]*)\x27/)   { $raw = $1; $i += length($1) + 2; $has_val = 1; }
          elsif ($r =~ /^([^\s"\x27>`=<]+)/)    { $raw = $1; $i += length($1);     $has_val = 1; }
          else { $bad{"$name= (MALFORMED-MARKUP; unreadable attr value: " . substr($r, 0, 12) . ")"}++; last; }
        }
        # ★属性名の肯定 allowlist: on*= は「形」でなく「名前」で落ちる (B1 の \s 依存 heuristic が不要になる)。
        unless ($name =~ $attr_re) {
          my $why = ($name =~ /^on/i) ? "event handler attribute" : "ATTR-NAME-NOT-ALLOWED";
          $bad{"$name= ($why)"}++; next;
        }
        next unless $has_val && $name =~ $url_attr;
        my $u = decode_full($raw);
        $u =~ s/[\x00-\x20\x7f]//g;   # 制御文字/空白の混入で scheme を割る回避を封じる
        next if $u =~ $href_ok;
        $bad{"$name=\"$raw\" (URL-ALLOWLIST-VIOLATION; decoded: $u)"}++;
      }
    }
    END { print join("; ", map { "$_ x$bad{$_}" } sort keys %bad) if %bad; }
'

validate_rich_inline() {
  local bad vals n rc
  vals="$(mktemp)"
  # ★(a) pipeline の exit status を ★自前で検査する (fail-open 封鎖):
  #   caller は `validate_rich_inline || errs=1` (= || リスト) で呼ぶため、 関数本体では set -e が ★無効化される。
  #   ゆえ rich_field_values (yq) が落ちても $bad は空文字列になり、 空文字列性だけを見る判定は ★無条件 PASS する
  #   (最小再現で確認済: validate() が errs=0 のまま CLEAN を報告した)。 status を明示判定して abort する。
  if ! rich_field_values > "$vals"; then
    rm -f "$vals"
    echo "assemble-self-spec: ★rich field の抽出に失敗 (yq 非 0 exit・検査不能ゆえ fail-closed)" >&2
    return 1
  fi
  # ★(b) 被覆量の fail-closed assert (gate 喪失への ★恒真 PASS 封鎖):
  #   本 guard の PASS/FAIL を $bad の空文字列性だけで決めると、 rich_field_values が ★空を返した瞬間に
  #   「検査対象 0 件 → bad なし → PASS」となり、 8 箇所の RAW emit site を覆う ★唯一の注入防御が
  #   何も検査しないまま緑になる (= 本 diff が esc() を外した代償として集約した保護の喪失)。
  #   実証: 検査対象 query を .sectionsTYPO[].essence へ drift させると bad=[] で return 0 = PASS だった。
  #   ゆえ「bad が無いこと」だけでなく ★「何件検査したか」を assert する。
  n="$(wc -l < "$vals" | tr -d ' ')"
  if [[ "$n" -lt "$RICH_FIELD_MIN" ]]; then
    rm -f "$vals"
    echo "assemble-self-spec: ★rich field の検査対象が $n 件 (期待下限 $RICH_FIELD_MIN)。 rich_field_values の" >&2
    echo "  query drift か抽出規約の破綻により ★注入防御が無被覆 (検査対象 0/過少での恒真 PASS を封鎖)。" >&2
    echo "  契約が正当に育った場合に限り RICH_FIELD_MIN を ★意図的に更新すること。" >&2
    return 1
  fi
  # ★(b2) 型別 内訳の下限 assert (folio-eccf S5)。 総数 assert の ★後ろ に置く MUST:
  #   総数が痩せる drift は ★総数 assert の理由 (「検査対象が」) で落ちる規約が既に F18g の pin になっており、
  #   本 assert を前に出すと同じ drift が別理由で落ちて F18g の理由照合が壊れる (= 既存 pin の意味を変えない)。
  local spec tmin tlabel tquery tn sum=0
  for spec in "${RICH_FIELD_TYPE_MINS[@]}"; do
    tmin="${spec%%:::*}"; spec="${spec#*:::}"; tlabel="${spec%%:::*}"; tquery="${spec#*:::}"
    if ! tn="$(q "[ $tquery ] | .[]" 2>/dev/null | wc -l | tr -d ' ')"; then
      rm -f "$vals"
      echo "assemble-self-spec: ★rich field 型別 '$tlabel' の抽出に失敗 (検査不能ゆえ fail-closed)" >&2
      return 1
    fi
    sum=$((sum + tn))
    if [[ "$tn" -lt "$tmin" ]]; then
      rm -f "$vals"
      echo "assemble-self-spec: ★rich field 型別 '$tlabel' が $tn 件 (期待下限 $tmin)。 型単位で被覆が痩せている" >&2
      echo "  (総数 $n は下限 $RICH_FIELD_MIN を満たしていても ★型間の相殺で喪失が隠れる。 それを撃つのが本 assert)。" >&2
      echo "  契約が正当に育った場合に限り RICH_FIELD_TYPE_MINS を ★意図的に更新すること。" >&2
      return 1
    fi
  done
  # ★(b3) 恒等式: 型別の総和 == rich_field_values の総行数 (folio-eccf S5)。
  #   RICH_FIELD_TYPE_MINS と rich_field_values は ★同じ field 集合を別記法で列挙する = 二重保守ゆえ drift しうる。
  #   本恒等式が破れる = 両者が ★違う集合を見ている ということであり、 どちらが正しいかに依らず ★検査の土台が
  #   壊れている。 ゆえ理由を問わず fail-closed (「片方だけが drift しても総数は下限を満たしうる」穴の構造的封鎖)。
  if [[ "$sum" -ne "$n" ]]; then
    rm -f "$vals"
    echo "assemble-self-spec: ★rich field の型別 総和 $sum が総行数 $n と不一致 (RICH_FIELD_TYPE_MINS と" >&2
    echo "  rich_field_values が ★別の集合を列挙している = 二重保守の drift。 検査の土台が壊れているゆえ fail-closed)。" >&2
    return 1
  fi
  bad="$(ALLOW="$RICH_INLINE_ALLOW" ATTRALLOW="$RICH_ATTR_ALLOW" SCHEMEALLOW="$RICH_HREF_SCHEME" \
         perl -CSD -ne "$RICH_TOKENIZE_PL" < "$vals")"; rc=$?
  rm -f "$vals"
  # ★(c) tokenizer 自身の異常終了も fail-closed (同じく set -e が効かないため自前判定)。
  [[ $rc -eq 0 ]] || { echo "assemble-self-spec: ★rich field の tokenize に失敗 (perl 非 0 exit・検査不能ゆえ fail-closed)" >&2; return 1; }
  [[ -z "$bad" ]] && return 0
  echo "assemble-self-spec: ★人間層 rich field に allowlist 外の markup: $bad" >&2
  echo "  (rich field = essence / statement / table cell / caption。 RAW emit ゆえ inline 非実行要素のみ許可: $RICH_INLINE_ALLOW)" >&2
  echo "  (属性名も肯定 allowlist: $RICH_ATTR_ALLOW。 on*= / style / srcset 等は quoting 形に依らず落ちる)" >&2
  echo "  (URL は entity decode 後の肯定 allowlist 判定: $RICH_HREF_ALLOW_DESC)" >&2
  echo "  (MALFORMED-MARKUP = strict grammar で tokenize しきれない形。 未知の parser-differential は通さず落とす)" >&2
  return 1
}

# ★機械層 rich field の inline 健全性 (folio-eccf S1・validate_rich_inline と ★同一 tokenizer / 別 allowlist)。
#   ★なぜ要るか (改修前の非対称): emit_machine_block は .html / .items[] を ★RAW emit する (esc 厳禁 = 逐語 round-trip の
#   ための設計) のに、 人間層と違い ★生成前の sanitization を持たなかった。 すなわち機械層 field への注入は
#   「verify が後から気づく」だけで ★生成そのものは通っていた (人間層 = 生成時 abort との非対称)。
#   ★verify 後付けの post-check では対称にならない: verify を回さない経路 (assemble 単体呼出し) が素通りするうえ、
#   「毒入り生成物が一度 file として存在する」こと自体を許す。 ゆえ ★人間層と同じ emit 前 fail-closed abort に揃える。
# ★構造は validate_rich_inline と ★意図的に同型 (fail-closed 3 点: 抽出失敗 / 被覆量下限 / tokenizer 異常終了)。
#   ここを共通関数へ畳まないのは、 層ごとに ★理由文言と定数束を分離したままにするため (F18 群の substring 一致点を
#   人間層に固定し、 機械層の緩和が人間層へ scope-leak しないようにする)。
validate_machine_inline() {
  local bad vals n rc
  vals="$(mktemp)"
  # ★(a) 抽出失敗を fail-closed (caller が `|| errs=1` で呼ぶため set -e は無効 = 自前判定が要る)。
  if ! machine_field_values > "$vals"; then
    rm -f "$vals"
    echo "assemble-self-spec: ★機械層 field の抽出に失敗 (yq 非 0 exit・検査不能ゆえ fail-closed)" >&2
    return 1
  fi
  # ★(b) 被覆量の下限 assert (guard 喪失への恒真 PASS 封鎖・人間層 RICH_FIELD_MIN と同型の teeth)。
  #   machine_field_values の query が drift すると「検査対象 0 件 → bad なし → PASS」で機械層 RAW emit が
  #   ★無防備のまま緑になる。 ★件数を assert して初めて guard の生存が証明される。
  n="$(wc -l < "$vals" | tr -d ' ')"
  if [[ "$n" -lt "$MACHINE_FIELD_MIN" ]]; then
    rm -f "$vals"
    echo "assemble-self-spec: ★機械層 field の検査対象が $n 件 (期待下限 $MACHINE_FIELD_MIN)。 machine_field_values の" >&2
    echo "  query drift か抽出規約の破綻により ★機械層の注入防御が無被覆 (検査対象 0/過少での恒真 PASS を封鎖)。" >&2
    echo "  契約が正当に育った場合に限り MACHINE_FIELD_MIN を ★意図的に更新すること。" >&2
    return 1
  fi
  # ★(b2) 分岐別 内訳の下限 assert (人間層 (b2) と同型・別定数束)。 総数 assert の ★後ろ に置く MUST:
  #   総数が痩せる drift は ★総数 assert の理由 (「機械層 field の検査対象が」) で落ちる規約が 敵対 M17b/M17c と
  #   selftest S1-c の理由照合 pin になっており、 本 assert を前に出すと同じ drift が別理由で落ちて pin が壊れる。
  local mspec tmin tlabel tquery tn msum=0
  for mspec in "${MACHINE_FIELD_TYPE_MINS[@]}"; do
    tmin="${mspec%%:::*}"; mspec="${mspec#*:::}"; tlabel="${mspec%%:::*}"; tquery="${mspec#*:::}"
    if ! tn="$(q "[ $tquery ] | .[]" 2>/dev/null | wc -l | tr -d ' ')"; then
      rm -f "$vals"
      echo "assemble-self-spec: ★機械層 field 分岐 '$tlabel' の抽出に失敗 (検査不能ゆえ fail-closed)" >&2
      return 1
    fi
    msum=$((msum + tn))
    if [[ "$tn" -lt "$tmin" ]]; then
      rm -f "$vals"
      echo "assemble-self-spec: ★機械層 field 分岐 '$tlabel' が $tn 件 (期待下限 $tmin)。 分岐単位で被覆が痩せている" >&2
      echo "  (総数 $n は下限 $MACHINE_FIELD_MIN を満たしていても ★分岐間の相殺で喪失が隠れる。 それを撃つのが本 assert)。" >&2
      echo "  契約が正当に育った場合に限り MACHINE_FIELD_TYPE_MINS を ★意図的に更新すること。" >&2
      return 1
    fi
  done
  # ★(b3) 恒等式: 分岐別の総和 == machine_field_values の総行数 (人間層 (b3) と同型・別定数束)。
  #   ★本恒等式が MACHINE_FIELD_MIN の count-only 残余を閉じる本体: 契約が育って総数が下限を上回った後に
  #   machine_field_values の ★1 分岐だけ が drift すると、 総数 assert も 分岐別下限 (本表は別 query ゆえ無傷) も
  #   ★両方緑のまま その分岐が無検査になる。 恒等式だけが「本体と表が違う集合を見ている」を検出する。
  if [[ "$msum" -ne "$n" ]]; then
    rm -f "$vals"
    echo "assemble-self-spec: ★機械層 field の分岐別 総和 $msum が総行数 $n と不一致 (MACHINE_FIELD_TYPE_MINS と" >&2
    echo "  machine_field_values が ★別の集合を列挙している = 二重保守の drift。 検査の土台が壊れているゆえ fail-closed)。" >&2
    return 1
  fi
  bad="$(ALLOW="$MACHINE_RICH_ALLOW" ATTRALLOW="$MACHINE_ATTR_ALLOW" SCHEMEALLOW="$MACHINE_HREF_SCHEME" \
         perl -CSD -ne "$RICH_TOKENIZE_PL" < "$vals")"; rc=$?
  rm -f "$vals"
  # ★(c) tokenizer 自身の異常終了も fail-closed。
  [[ $rc -eq 0 ]] || { echo "assemble-self-spec: ★機械層 field の tokenize に失敗 (perl 非 0 exit・検査不能ゆえ fail-closed)" >&2; return 1; }
  [[ -z "$bad" ]] && return 0
  echo "assemble-self-spec: ★機械層 field に allowlist 外の markup: $bad" >&2
  echo "  (機械層 field = machine_preamble / sections[].machine_blocks の html・items。 RAW emit ゆえ allowlist: $MACHINE_RICH_ALLOW)" >&2
  echo "  (属性名も肯定 allowlist: $MACHINE_ATTR_ALLOW。 on*= / style / srcset 等は quoting 形に依らず落ちる)" >&2
  echo "  (URL は entity decode 後の肯定 allowlist 判定: $MACHINE_HREF_ALLOW_DESC)" >&2
  echo "  (MALFORMED-MARKUP = strict grammar で tokenize しきれない形。 未知の parser-differential は通さず落とす)" >&2
  return 1
}

# ---- fail-closed contract validation (普遍規律 = core_validate_strings、 spec 固有 = doc_type/EARS/role/tint/block/集合) ----
validate() {
  local errs=0 d p si bi nsec nblk btype nmb mbi mbtype npre pi pbtype
  core_validate_strings "assemble-spec" || errs=1
  validate_rich_inline || errs=1
  # ★機械層も ★emit 前に同じ fail-closed 規律で通す (folio-eccf S1)。 人間層と ★対称の位置 (validate 内) に置くのが要点:
  #   emit 後 / verify 側の post-check では「毒入り生成物が一度存在する」ことを許し非対称が残る。
  validate_machine_inline || errs=1
  # ★doc_type 束縛 (fail-open 封鎖): 本 fork は doc-type=spec 専用 assembler。 doc_type が spec 以外なら abort。
  [[ "$(q '.meta.doc_type')" == "spec" ]] || { echo "assemble-self-spec: ★meta.doc_type は spec 必須 (doc_type flip で gate bypass 不可)" >&2; errs=1; }
  # ★★M3 (folio-cuom): doc_id literal guard。 doc_type == spec は ★4 契約 (rules / relations / verification /
  #   srs-verification) + 本 self-spec が ★共有 しており ★識別力ゼロ — doc_type だけでは「他 pack の contract を
  #   本 fork へ食わせる」誤用を 1 つも止められない (定数群・静的見出し・count 下限が全て self-spec 実測ゆえ、
  #   他契約を食うと ★別 doc の内容が self-spec の shape で出る)。 doc_id を ★逐値 literal で束縛して入口を閉じる。
  #   ★fail-closed: 空 / 別値 / 欠落のいずれも abort (= qojv 決定 2「verify literal」の cuom 側実体・対の
  #   guard が verify-self-spec.sh の入口にも 1 本ある)。
  [[ "$(q '.meta.doc_id')" == "FOLIO-SELF-SPEC" ]] || { echo "assemble-self-spec: ★meta.doc_id は FOLIO-SELF-SPEC 必須 (実際: '$(q '.meta.doc_id')')。 本 fork は self-spec 専用 — 定数群 (RICH_FIELD_MIN / 静的見出し / 照会種別) が self-spec 実測ゆえ他 pack contract を食わせてはならない" >&2; errs=1; }
  # 要件 id 一意性
  d="$(q '.requirements[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-spec: 要件 id 重複: $d" >&2; errs=1; }
  # section id 一意性
  d="$(q '.sections[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-spec: section id 重複: $d" >&2; errs=1; }
  # EARS pattern allowlist (★逐値判定: word-split に依存させない。 "ubiquitous unwanted" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する)。
  while IFS= read -r p; do [[ -v EARS_CLASS[$p] ]] || { echo "assemble-spec: 未知の EARS pattern: $p (ubiquitous|event-driven|state-driven|unwanted|optional)" >&2; errs=1; }; done < <(q '.requirements[].ears_pattern')
  # section tint allowlist (★逐値判定: 同上。 "brand violet" 等が band の class 属性へ stray token を注入する fail-open を封鎖)。
  while IFS= read -r p; do [[ -v TINT_OK[$p] ]] || { echo "assemble-spec: 未知の section tint (CSS allowlist 外): $p" >&2; errs=1; }; done < <(q '.sections[].tint')
  # ★block type allowlist (silent drop 禁止・fail-closed): 未対応 block type は捨てず abort する。
  nsec="$(q '.sections | length')"
  for ((si=0; si<nsec; si++)); do
    nblk="$(q ".sections[$si].blocks // [] | length")"
    for ((bi=0; bi<nblk; bi++)); do
      btype="$(q ".sections[$si].blocks[$bi].type")"
      printf '%s' "$btype" | grep -qxE "$BLOCK_TYPE_ALLOW" \
        || { echo "assemble-spec: ★未対応 block type '$btype' (section[$si] block[$bi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
    done
    # ★機械層 block type allowlist (w1f cell-2): sections[].machine_blocks の type も逐値検査 (silent drop 禁止)。
    nmb="$(q ".sections[$si].machine_blocks // [] | length")"
    for ((mbi=0; mbi<nmb; mbi++)); do
      mbtype="$(q ".sections[$si].machine_blocks[$mbi].type")"
      printf '%s' "$mbtype" | grep -qxE "$MACHINE_BLOCK_TYPE_ALLOW" \
        || { echo "assemble-spec: ★未対応 machine block type '$mbtype' (section[$si] machine_blocks[$mbi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
    done
  done
  # ★文書前文 machine_preamble の type も逐値検査。
  npre="$(q '.machine_preamble // [] | length')"
  for ((pi=0; pi<npre; pi++)); do
    pbtype="$(q ".machine_preamble[$pi].type")"
    printf '%s' "$pbtype" | grep -qxE "$MACHINE_BLOCK_TYPE_ALLOW" \
      || { echo "assemble-spec: ★未対応 machine block type '$pbtype' (machine_preamble[$pi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
  done
  # ★要件 ↔ requirements block の集合一致 (孤立要件・二重参照・存在しない要件参照を生成前に拒否)。
  #   block で参照する全 id ⊆ requirements[].id (存在しない要件参照を拒否)
  d="$(comm -23 <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u) <(q '.requirements[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-spec: requirements block が未定義の要件を参照: $d" >&2; errs=1; }
  #   requirements[].id ⊆ block 参照集合 (どこにも配置されない孤立要件を拒否)
  d="$(comm -23 <(q '.requirements[].id' | sort -u) <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-spec: 配置先 block の無い孤立要件: $d" >&2; errs=1; }
  #   要件 id は block 全体で 1 回だけ参照 (二重配置を拒否 = 行数二重カウント防止)
  d="$(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort | uniq -d)"
  [[ -z "$d" ]] || { echo "assemble-spec: 要件が複数 block に重複配置: $d" >&2; errs=1; }
  # references role allowlist + 空 token 禁止
  # ★逐値判定 (EARS/tint と対称): word-split/glob に依存させない。 "claim rationale" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v ROLE_OK[$p] ]] || { echo "assemble-spec: 未知の reference role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done < <(q '.references[]?.role')
  if [[ "$(q 'has("references")')" == "true" ]]; then
    local n_ref n_refne n_title
    n_ref="$(q '.references | length')"; n_refne="$(q '[.references[] | select((.token // "") != "")] | length')"
    [[ "$n_ref" == "$n_refne" ]] || { echo "assemble-spec: ★references に空 token ($n_refne/$n_ref 件・空照会 token は壊れた前方照会ゆえ禁止)" >&2; errs=1; }
    # ★references[].title (ADR-0054 §2.2 一行タイトル併記) は ★all-or-none。 全件が非空 title を持つか 1 件も持たないかの
    #   2 択で、 ★部分欠落は fail-closed (chip ごとに gloss が有ったり無かったりする silent 半端形を禁止)。
    #   title 皆無の contract (extractor 再抽出物 等) は rf-gloss を emit しない旧形として通す — その 0/0 恒真 PASS は
    #   verify-self-spec.sh の契約非依存 census floor (rf-gloss == 30) が封鎖する。
    n_title="$(q '[.references[] | select((.title // "") != "")] | length')"
    [[ "$n_title" -eq 0 || "$n_title" -eq "$n_ref" ]] \
      || { echo "assemble-spec: ★references[].title の部分欠落 ($n_title/$n_ref 件・all-or-none 必須: 全件に一行タイトルを付すか 1 件も付さないか)" >&2; errs=1; }
  fi
  # ★requirements[].priority (RFC-2119 優先度バッジ) — references[].title と同型の all-or-none + closed allowlist。
  local n_req n_prio
  n_req="$(q '.requirements | length')"; n_prio="$(q '[.requirements[] | select((.priority // "") != "")] | length')"
  [[ "$n_prio" -eq 0 || "$n_prio" -eq "$n_req" ]] \
    || { echo "assemble-spec: ★requirements[].priority の部分欠落 ($n_prio/$n_req 件・all-or-none 必須)" >&2; errs=1; }
  # ★逐値判定 (EARS/tint/role と対称): 空白区切りの allowlist token 並びが IFS split で素通る fail-open を封鎖。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v PRIO_OK[$p] ]] || { echo "assemble-spec: 未知の priority: $p (must|should)" >&2; errs=1; }; done < <(q '.requirements[].priority // ""')
  # ★契約内不変条件: priority (宣言) == statement の RFC-2119 modal verb 由来 level (導出)。 Cell R self-review major-1。
  #   ★これが無いと contract 自身が statement と矛盾する level を宣言でき、 生成物・floor・drift の ★全 gate を素通る
  #   (priority を根とする突合は contract に対して ★自己整合 / drift は contract から再生成する byte 比較ゆえ ★全盲)。
  #   verify-self-spec.sh の (iii) と ★二重保守 = detect↔remediate parity。
  # ★導出規則 (RFC-2119 は ★大文字 のみ規範キーワード) — ★wave 恒常 1 (folio-n57u) が定める Cell U 版 first-modal-wins:
  #     statement 中で ★最初に 現れる規範キーワードが当該要件の level を決める。
  #     - SHALL|MUST が SHOULD より ★先 → must (後続の SHOULD は ★従属節 = 委譲先の助言・付随注記)。
  #     - SHOULD のみ → should。 SHALL|MUST のみ → must。
  #     - SHOULD が ★先 で SHALL|MUST が後 → AMBIGUOUS-BOTH (fail-closed)。 皆無 → NO-MODAL (fail-closed)。
  #   ★Cell R 版 (assemble-relations.sh の「両方あれば即 AMBIGUOUS」) を写してはならない: verification の
  #     REQ-VER-005 (「… MUST 実装する。 Step 2 / Step 3 は段階追加 (SHOULD / MAY)。」= MUST 先行 + SHOULD 後続) が
  #     AMBIGUOUS-BOTH で build 不能になる (wave 恒常 1 の明文)。
  #   ★非対称にする理由: 封鎖したい詐称は「実体が MUST の要件を should と宣言する」方向で、 その形は
  #     ★必ず先頭の SHALL|MUST から must が導出されて宣言 should と不一致になり FAIL する (緩めていない)。
  local rq_id rq_prio rq_der
  while IFS= read -r rq_id; do
    [[ -n "$rq_id" ]] || continue
    rq_prio="$(q '.requirements[] | select(.id=="'"$rq_id"'") | .priority // ""')"
    [[ -n "$rq_prio" && "$rq_prio" != "null" ]] || continue
    rq_der="$(q '.requirements[] | select(.id=="'"$rq_id"'") | .statement' | perl -0777 -ne '
        my $m = /\b(?:SHALL|MUST)\b/ ? $-[0] : -1; my $s = /\bSHOULD\b/ ? $-[0] : -1;
        print $m < 0 && $s < 0 ? "NO-MODAL"
            : ($m >= 0 && $s < 0 ? "must"
            : ($s >= 0 && $m < 0 ? "should"
            : ($m < $s ? "must" : "AMBIGUOUS-BOTH")));')"
    [[ "$rq_prio" == "$rq_der" ]] \
      || { echo "assemble-spec: ★priority と statement の RFC-2119 modal verb が矛盾: $rq_id (宣言 $rq_prio / statement 由来 $rq_der)" >&2; errs=1; }
  done < <(q '.requirements[].id')
  # ★graph.principle_edge (rules→constitution 終端 edge・非終端 照会の graph 接続)。
  if [[ "$(q '.graph | has("principle_edge")')" == "true" ]]; then
    p="$(q '.graph.principle_edge.role')"; [[ -v ROLE_OK[$p] ]] || { echo "assemble-spec: graph.principle_edge.role が allowlist 外: $p" >&2; errs=1; }
    d="$(q '.graph.principle_edge.target_doc_id')"; [[ -n "$d" && "$d" != "null" ]] || { echo "assemble-spec: graph.principle_edge.target_doc_id が空" >&2; errs=1; }
  fi
  [[ "$errs" -eq 0 ]] || { echo "assemble-spec: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- ★節番号 (§N) の導出 (ADR-0054 §2.2 / 章帯の巨大番号を節番号へ一致させる前段) ----
# ★verification の §番号は §0..§6 の連番だが、 節番号は ★見出し自身 (contract sections[].heading の「§N.」) を
#   trust anchor にして 1 本ずつ導出する (Cell U と同型)。 連番算術 (num = CHAPN - 1) にしないのは、 見出しと
#   帯番号が食い違っても算術側は気づけない (両側が同じ仮定に合意しているだけになる) ため。
# ★fail-closed: §N 形でない heading があれば abort (番号導出不能を silent に連番へ落とさない)。
# ★-Mutf8 必須: -CSD は入力を decode するが ★program source の literal は decode しない — 「§」を素の byte のまま
#   書くと decode 済み入力と一致せず ★常に 0 match (= fail-closed 側へ倒れて全 build が落ちる) になる。
heading_secnum() { # $1 = heading
  local n
  n="$(printf '%s' "$1" | perl -CSD -Mutf8 -ne 'print "$1" if /^§(\d+)\./')"
  [[ -n "$n" ]] || { echo "assemble-self-spec: ★heading が §N 形でない (節番号を導出できない・fail-closed): $1" >&2; exit 1; }
  printf '%s' "$n"
}
# ---- ★静的 2 band (前方照会 / 用語集) の見出し・番号を contract から導出する ----
# 最終 section 見出しの §N の ★次 / ★次々 を静的 band の §番号とする (literal 固定だと contract に section を
# 1 本足したとき帯番号と見出し文字列が ★無言でずれる)。
derive_static_band_headings() {
  local last_h last_n
  last_h="$(q '.sections[].heading' | tail -n 1)"
  last_n="$(heading_secnum "$last_h")"
  STATIC_BAND_NUMS=("$((last_n + 1))" "$((last_n + 2))")
  STATIC_BAND_HEADINGS=(
    "§${STATIC_BAND_NUMS[0]}. ${STATIC_BAND_HEADING_TAILS[0]}"
    "§${STATIC_BAND_NUMS[1]}. ${STATIC_BAND_HEADING_TAILS[1]}"
  )
}

# band / band_end (chapter-deck-band) は lib/common.sh (core) を使う。
# ---- ★章帯の巨大番号を節番号へ一致させる pack-local wrapper (ADR-0054 §2.2) ----
# core band() は文書内 ★連番 (.num = 01, 02, …) を emit する。 ★共有 lib/common.sh の band() 本体は ★触らない
#   (16 pack 共有ゆえ改変は doc-pack golden + gate F を巻き添える・運用条項 追補 1)。
#   pack-local に「core が emit した .num の値だけ」を §番号へ書き換える (帯の markup 生成は core が唯一の SSoT のまま)。
# ★data-slot-id="chapter-lead-NN" (prose manifest の key) は ★連番のまま = 書き換えない (slot 契約不変)。
# ★subshell 禁止: band() は core の CHAPN を進めるため $(band …) で捕まえると連番が進まない (slot-id が全て 01 になる)。
#   リダイレクトは subshell を作らないので tmp file 経由で捕まえる。
# ★fail-loud: core band() が emit するはずの連番 span が ★見つからなければ abort (shape drift の silent 温存を封鎖)。
#   ★「置換が no-op か」で判定してはならない: 節番号が連番の 2 桁表記と一致する章では正当な置換が byte 同一になり
#   no-op 判定が ★偽 abort を起こす (Cell U が rules §10 で踏んだ罠)。
band_num() { # num tint kicker heading icon_inner
  local num="$1" seq t
  # ★二重化 (呼出側の代入形 guard と対): 非数値・空の節番号が渡ったら band_num 自身が abort する。
  #   band_num は main shell で動くため exit が確実に効く (呼出経路の形に依存しない最終防波堤)。
  [[ "$num" =~ ^[0-9]+$ ]] || { echo "assemble-self-spec: ★band_num に非数値の節番号 ('$num') が渡された (節番号を導出できない・fail-closed)" >&2; exit 1; }
  shift
  t="$(mktemp)"
  band "$1" "$2" "$3" "$4" > "$t"
  printf -v seq '%02d' "$CHAPN"      # 直前の band() が emit した連番 (core が進めた値)
  grep -qF "<span class=\"num\">$seq</span>" "$t" \
    || { rm -f "$t"; echo "assemble-self-spec: ★band の連番 .num ($seq) が emit に見当たらない (core band() の shape drift・fail-closed)" >&2; exit 1; }
  sed "s|<span class=\"num\">$seq</span>|<span class=\"num\">$num</span>|" "$t"
  rm -f "$t"
}

# ---- spec-pack 固有 CSS (srs.css token を流用。 dark は token 経由で自動追従) ----
emit_spec_css() {
  cat <<'CSS'
/* ===== spec-pack 固有部品 (folio-8ct / instance#5)。 srs.css の token を流用 ===== */
[data-component="section-essence-callout"]{border:1px solid var(--brand-line,var(--line));border-left:3px solid var(--brand);border-radius:10px;padding:11px 15px;background:var(--brand-tint);margin:4px 0 12px}
[data-component="section-essence-callout"] .sec-se{margin:0;font-size:13.5px;line-height:1.7;color:var(--ink)}
[data-component="spec-subhead"]{margin:14px 0 6px}
[data-component="spec-subhead"] h3{margin:0 0 3px;font-size:14.5px;font-weight:800;color:var(--ink)}
[data-component="spec-subhead"] .sub-se{margin:0;font-size:12.5px;line-height:1.65;color:var(--ink-soft);background:var(--paper-2);border-radius:7px;padding:6px 11px}
[data-component="spec-prose"]{margin:8px 0;font-size:13px;line-height:1.75;color:var(--ink-soft)}
[data-component="spec-note"]{border:1px solid var(--info-line);border-left:3px solid var(--info);border-radius:9px;padding:9px 14px;background:var(--info-tint);margin:8px 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
[data-component="spec-note"] p{margin:0}
ul[data-component="spec-list-block"]{margin:8px 0;padding-left:4px;list-style:none;display:flex;flex-direction:column;gap:5px}
ul[data-component="spec-list-block"] .lbi{position:relative;padding-left:18px;font-size:13px;line-height:1.7;color:var(--ink-soft)}
ul[data-component="spec-list-block"] .lbi::before{content:"●";position:absolute;left:0;color:var(--brand);font-size:9px;top:5px}
pre[data-component="spec-code"]{background:var(--paper-2);border:1px solid var(--line);border-radius:9px;padding:11px 14px;overflow-x:auto;font-size:12px;line-height:1.6;margin:8px 0}
pre[data-component="spec-code"] code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--ink);white-space:pre}
[data-component="spec-table"]{width:100%;border-collapse:collapse;font-size:12.5px;margin:2px 0}
[data-component="spec-table"] caption{caption-side:top;text-align:left;font-size:11.5px;color:var(--ink-faint);padding:0 0 5px;font-weight:700}
[data-component="spec-table"] th{text-align:left;padding:6px 10px;background:var(--brand-tint);border:1px solid var(--line);font-size:11.5px;letter-spacing:.02em;color:var(--ink-soft)}
[data-component="spec-table"] td{padding:6px 10px;border:1px solid var(--line);line-height:1.6;color:var(--ink)}
figure[data-component="spec-diagram"]{margin:10px 0;border:1px solid var(--line);border-radius:10px;background:var(--paper-2);overflow:hidden}
figure[data-component="spec-diagram"] .mermaid{margin:0;padding:12px 15px;overflow-x:auto;text-align:center}
figure[data-component="spec-diagram"] .mermaid:not([data-processed]){font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;line-height:1.55;white-space:pre;text-align:left;color:var(--ink-soft);background:var(--paper-2)}
figure[data-component="spec-diagram"] figcaption{padding:7px 15px;font-size:11.5px;color:var(--ink-faint);border-top:1px dashed var(--line);background:var(--paper)}
.rq-list{display:flex;flex-direction:column;gap:10px;margin:8px 0}
[data-component="ears-requirement-row"]{border:1px solid var(--line);border-left:3px solid var(--brand);border-radius:11px;padding:11px 14px;background:var(--paper);box-shadow:var(--shadow)}
[data-component="ears-requirement-row"] .rq-head{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-bottom:5px}
[data-component="ears-requirement-row"] .rid{font-weight:800;font-size:12px;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:6px;padding:2px 9px;letter-spacing:.02em}
[data-component="ears-badge"],[data-component="ears-legend-item"]{display:inline-flex;align-items:center;font-size:11px;font-weight:800;letter-spacing:.03em;border-radius:999px;padding:2px 11px;white-space:nowrap}
[data-component="ears-badge"]{margin-left:auto}
[data-component="ears-badge"].always,[data-component="ears-legend-item"].always{color:var(--brand);background:var(--brand-tint);border:1px solid var(--line)}
[data-component="ears-badge"].trigger,[data-component="ears-legend-item"].trigger{color:var(--info);background:var(--info-tint);border:1px solid var(--info-line)}
[data-component="ears-badge"].state,[data-component="ears-legend-item"].state{color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line)}
[data-component="ears-badge"].forbid,[data-component="ears-legend-item"].forbid{color:var(--bad);background:var(--bad-tint);border:1px solid var(--bad-line)}
[data-component="ears-badge"].option,[data-component="ears-legend-item"].option{color:var(--ok);background:var(--ok-tint);border:1px solid var(--ok-line)}
[data-component="ears-legend"]{display:flex;align-items:center;flex-wrap:wrap;gap:8px 14px;margin:14px 0 4px;padding:11px 14px;border:1px solid var(--line);border-radius:11px;background:var(--paper-2)}
[data-component="ears-legend"] .el-cap{font-size:11px;font-weight:800;letter-spacing:.04em;color:var(--ink-faint);text-transform:uppercase;margin-right:2px}
[data-component="ears-legend"] .el-item{display:inline-flex;align-items:center;gap:6px}
[data-component="ears-legend"] .el-when{font-size:11.5px;color:var(--ink-soft)}
[data-component="ears-requirement-row"] .rq-essence{margin:0 0 7px;font-size:13.5px;line-height:1.7;color:var(--ink)}
/* ★「やさしく言うと」平易行 + RFC-2119 優先度バッジ (ADR-0054 §2.2)。 色 token は srs.css 準拠 (Cell R/U と同形)。 */
[data-component="ears-requirement-row"] .rq-plain{margin:6px 0 8px;padding:8px 12px;background:var(--paper-2);border-left:3px solid var(--violet);border-radius:8px;font-size:12.5px;line-height:1.7;color:var(--ink)}
/* ★キーは既存 badge と同じ tint 系 (色 = var(--violet) / 地 = var(--violet-tint)) にする。 mockup の
   「濃紫地に白抜き」を token 化すると dark theme (--violet が明るい藤色) で白文字が contrast 2.2 まで落ち
   gate F の low-contrast になる — ears-badge .state と同じ組で両テーマ AA を確保する。 */
[data-component="ears-requirement-row"] .rq-plain-k{display:inline-block;color:var(--violet);background:var(--violet-tint);border:1px solid var(--violet-line);border-radius:6px;padding:1px 9px;margin-right:8px;font-size:11px;font-weight:800;white-space:nowrap}
[data-component="ears-requirement-row"] .rq-prio{border-radius:6px;padding:1px 9px;font-size:11px;font-weight:800;white-space:nowrap;border:1px solid transparent}
[data-component="ears-requirement-row"] .rq-prio-must{color:var(--bad);background:var(--bad-tint);border-color:var(--bad-line)}
[data-component="ears-requirement-row"] .rq-prio-should{color:var(--warn);background:var(--warn-tint);border-color:var(--warn-line)}
[data-component="ears-requirement-row"] .rq-norm{font-size:12px;border-top:1px dashed var(--line);padding-top:6px}
[data-component="ears-requirement-row"] .rq-norm summary{cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.04em;color:var(--ink-faint);text-transform:uppercase}
[data-component="ears-requirement-row"] .rq-stmt{margin:6px 0 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
.ref-grid{display:flex;flex-direction:column;gap:8px;margin:8px 0}
[data-component="cross-doc-ref-chip"]{display:flex;gap:9px;align-items:center;flex-wrap:wrap;border:1px solid var(--violet-line);border-left:3px solid var(--violet);border-radius:10px;padding:8px 13px;background:var(--violet-tint);font-size:12.5px}
[data-component="cross-doc-ref-chip"] .rf-token{font-weight:800;color:var(--violet)}
[data-component="cross-doc-ref-chip"] .rf-arrow{color:var(--violet);font-weight:800}
[data-component="cross-doc-ref-chip"] .rf-doc{font-weight:700;color:var(--ink)}
[data-component="cross-doc-ref-chip"] .rf-role{margin-left:auto;font-size:11px;font-weight:700;color:var(--brand);background:var(--brand-tint);border:1px solid var(--line);border-radius:999px;padding:1px 10px;white-space:nowrap}
/* ★照会先の一行タイトル (ADR-0054 §2.2「裸 ID を出さない」)。 flex-basis 100% で token 行の下へ回り込ませる。 */
[data-component="cross-doc-ref-chip"] .rf-gloss{flex:0 0 100%;font-size:12px;line-height:1.6;color:var(--ink-soft)}
/* ★chrome-less 化 (ADR-0054 §2.1・Cell 0 = bin/folio が注入する部品) の見た目を pack 側で所有する。
   生成 spec は common.css を読まない (pack inline style が提示層 SSoT) ため、 skip-link の hidden-until-focus と
   下部 locator の体裁はここで与える (Cell 0 開示 #2・Cell R/U と同一 declaration)。 */
.skip-link{position:absolute;left:-9999px;top:auto;width:1px;height:1px;overflow:hidden}
.skip-link:focus{position:fixed;left:12px;top:12px;width:auto;height:auto;z-index:100;background:var(--paper);color:var(--ink);border:1px solid var(--line);border-radius:8px;padding:8px 14px;box-shadow:var(--shadow)}
.doc-locator{margin:28px 0 6px;font-size:12.5px;color:var(--ink-faint);border-top:1px solid var(--line);padding-top:10px}
/* ===== 機械層 (machine free-prose) — w1f cell-2 / ADR-0045 =====
   data-audience="machine" の自由文を native <details> fold で *既定非表示* (collapsed) + *トグル表示* (native disclosure)。
   no-JS で動作 (§12 自己完結) し rules.html §11.3/§11.5 の機械層挙動 (機械層=無制限の原稿・既定で畳む) に整合する。
   人間層 (章 essence / 可視 block) は fold の外で既定表示を保つ。 機械層は subdued な見た目で二次情報であることを示す。 */
[data-component="spec-machine-fold"]{margin:12px 0 4px;border:1px dashed var(--line);border-radius:10px;background:var(--paper-2)}
[data-component="spec-machine-fold"] > summary{cursor:pointer;list-style:none;display:flex;align-items:center;gap:9px;flex-wrap:wrap;padding:8px 14px;font-size:11.5px;color:var(--ink-faint)}
[data-component="spec-machine-fold"] > summary::-webkit-details-marker{display:none}
[data-component="spec-machine-fold"] > summary::before{content:"▸";color:var(--ink-faint);font-size:10px;transition:transform .15s}
[data-component="spec-machine-fold"][open] > summary::before{transform:rotate(90deg)}
[data-component="spec-machine-fold"] .mf-kicker{font-weight:800;letter-spacing:.04em;text-transform:uppercase;color:var(--ink-soft)}
[data-component="spec-machine-fold"] .mf-label{color:var(--ink-soft)}
[data-component="spec-machine-fold"] .mf-count{margin-left:auto;font-weight:700;color:var(--ink-faint);background:var(--paper);border:1px solid var(--line);border-radius:999px;padding:1px 9px;white-space:nowrap}
[data-component="spec-machine-fold"] .machine-body{padding:4px 15px 12px;border-top:1px dashed var(--line)}
[data-component="spec-machine-prose"]{margin:8px 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
[data-component="spec-machine-note"]{display:block;margin:8px 0;border-left:3px solid var(--info-line);padding:2px 0 2px 12px;font-size:12px;line-height:1.65;color:var(--ink-soft)}
[data-component="spec-machine-note"] p{margin:0}
ul[data-component="spec-machine-list"]{margin:8px 0;padding-left:4px;list-style:none;display:flex;flex-direction:column;gap:5px}
ul[data-component="spec-machine-list"] .mli{position:relative;padding-left:18px;font-size:12.5px;line-height:1.65;color:var(--ink-soft)}
ul[data-component="spec-machine-list"] .mli::before{content:"\2014";position:absolute;left:0;color:var(--ink-faint);top:0}
[data-component="spec-machine-fold"] code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.92em;background:var(--paper);border:1px solid var(--line);border-radius:4px;padding:0 4px}
/* demoted (tr0 / verification・ADR-0040 機械層降格分): inner の <p>/<ul>/<pre><code> を逐語 raw emit。 inner_norm で改行は畳まれるため pre は折返し表示。 */
[data-component="spec-machine-demoted"]{margin:8px 0;font-size:12.5px;line-height:1.7;color:var(--ink-soft)}
[data-component="spec-machine-demoted"] p{margin:6px 0}
[data-component="spec-machine-demoted"] ul{margin:6px 0;padding-left:20px}
[data-component="spec-machine-demoted"] li{margin:3px 0}
[data-component="spec-machine-demoted"] pre{background:var(--paper);border:1px solid var(--line);border-radius:7px;padding:9px 12px;overflow-x:auto;font-size:11.5px;line-height:1.55;white-space:pre-wrap;word-break:break-word;margin:6px 0}
[data-component="spec-machine-demoted"] pre code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:none;border:0;padding:0}
@media print{[data-component="spec-machine-fold"]{display:none}}

/* ===== canonical rich component (folio-aduv 0-d)。 common.css → srs.css token へ写像した pack-local 移植 =====
 * ★なぜ要るか: 0-d で人間層 rich 資産 (a.xref / span.term + data-tooltip / ins|del.delta / coverage matrix の
 *   badge--req・cov-req・req__ears・ears-* ) を canonical から ★RAW emit で全復元した。 しかし canonical
 *   verification.html はこれらの規則を <link href="../../common.css"> で外部から読んでおり、 生成 pack は
 *   単一 HTML へ inline <style> を焼く自己完結形ゆえ common.css を読まない。 移植しないと DOM だけ復元され
 *   ★視覚/機能は復元されない (実測: body に 290+ occurrence・inline style に該当規則 0)。
 *   とくに data-tooltip 66 は ::after 規則が無いと *死に属性* になる (canonical では hover の主 payload)。
 * ★.term の上書きが要る理由: srs.css:52 の .term は同名 *別コンポーネント* (plain-language-term-inline =
 *   専門語のやさしい併記 pill: display:inline-block / border-radius:999px / white-space:nowrap)。 canonical の
 *   .term (dotted underline + cursor:help + tooltip box) とは別物ゆえ、 移植しないと 27 の glossary term が
 *   ★別コンポーネントとして誤描画される。 本 pack は canonical 意味論を採るので後勝ち (source 順で srs.css の後に
 *   emit される = 同特異度なら本規則が勝つ) で pill 化 property を明示的に戻す。
 * ★CORE 不触・pack-local: emit_spec_css() は verification fork 専用ゆえ他 15 pack の artifact byte 回帰ゼロ。
 * ★token 写像: --folio-brand→--brand / --folio-text-secondary→--ink-soft / --folio-text-primary→--ink /
 *   --folio-surface-normal→--paper / --folio-border-strong→--line / --folio-success→--ok / --folio-danger→--bad。
 *   srs.css token 経由ゆえ dark も自動追従する (srs.css の token 定義が両モードを持つ)。
 */
/* --- Class A xref (ADR-0034): 点線下線 + brand 色。 canonical と同形 --- */
a.xref{color:var(--brand);text-decoration:underline dotted;text-underline-offset:2px;text-decoration-thickness:1px;letter-spacing:normal;font-feature-settings:normal}
a.xref:hover{text-decoration-style:solid;text-decoration-thickness:2px}
/* --- glossary term (ADR-0034 §2.8 / ADR-0036): 用語マーカー = help cursor + 控えめ dotted。
 *     ★srs.css の同名 pill を打ち消す (display/padding/margin/radius/bg/font を canonical 意味論へ戻す) --- */
.term{display:inline;font-size:inherit;font-weight:inherit;line-height:inherit;padding:0;margin-left:0;vertical-align:baseline;background:none;border:0;border-radius:0;white-space:normal;border-bottom:1px dotted var(--ink-soft);cursor:help}
/* --- CSS-only tooltip box (JS 不要・data-tooltip 属性供給)。 xref / term で共用 --- */
a.xref[data-tooltip],.term[data-tooltip]{position:relative}
a.xref[data-tooltip]::after,.term[data-tooltip]::after{content:attr(data-tooltip);position:absolute;left:0;bottom:calc(100% + .5rem);z-index:50;width:max-content;max-width:min(28rem,80vw);padding:.5rem .75rem;background:var(--paper);color:var(--ink);border:1px solid var(--line);border-radius:10px;box-shadow:var(--shadow-lg,0 8px 24px rgba(0,0,0,.18));font-size:12.5px;font-weight:400;line-height:1.5;letter-spacing:normal;font-feature-settings:normal;text-align:left;text-decoration:none;white-space:normal;
  /* ★display:none で非描画 (visibility:hidden だと layout に残り、 右端の term から viewport 外へ伸びた box が
     document の overflow に寄与して page 全体へ常時横スクロールを生む = canonical が render-gate で踏んだ実欠陥)。 */
  display:none;opacity:0;transition:opacity .12s ease-out;pointer-events:none}
a.xref[data-tooltip]:hover::after,a.xref[data-tooltip]:focus-visible::after,.term[data-tooltip]:hover::after,.term[data-tooltip]:focus-visible::after{display:block;opacity:1}
@starting-style{a.xref[data-tooltip]:hover::after,a.xref[data-tooltip]:focus-visible::after,.term[data-tooltip]:hover::after,.term[data-tooltip]:focus-visible::after{opacity:0}}
/* --- delta marker (ins/del + data-delta-id を ::before で可視化) --- */
ins.delta,del.delta{display:inline;padding:1px 6px;border-radius:5px;text-decoration:none;letter-spacing:normal;font-feature-settings:normal}
ins.delta{background:var(--ok-tint);border-left:2px solid var(--ok-line)}
del.delta{background:var(--bad-tint);border-left:2px solid var(--bad-line);text-decoration:line-through}
ins.delta::before{content:"+" attr(data-delta-id) " ";font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.78em;color:var(--ok);margin-right:.25rem}
del.delta::before{content:"-" attr(data-delta-id) " ";font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.78em;color:var(--bad);margin-right:.25rem}
/* --- coverage matrix の要件 badge / link (canonical §12 表) --- */
.badge{display:inline-block;padding:1px 9px;border-radius:999px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.72em;font-weight:600;line-height:1.7;letter-spacing:.02em;vertical-align:middle;border:1px solid transparent}
.badge--req{background:var(--brand-tint);color:var(--brand);border-color:var(--brand-line,var(--line))}
a.cov-req{text-decoration:none}
a.cov-req:hover .badge--req,a.cov-req:focus-visible .badge--req{outline:2px solid var(--brand);outline-offset:1px;filter:brightness(1.08)}
/* --- EARS pattern pill (canonical §12 表の req__ears--*) --- */
.req__ears{display:inline-block;padding:1px 9px;border-radius:999px;font-size:.7em;font-weight:700;letter-spacing:.04em;text-transform:uppercase;border:1px solid transparent;font-feature-settings:"palt"}
.req__ears--ubiquitous{background:var(--paper-3,var(--paper-2));color:var(--ink-soft);border-color:var(--line)}
.req__ears--event{background:var(--brand-tint);color:var(--brand);border-color:var(--brand-line,var(--line))}
.req__ears--state{background:var(--ok-tint);color:var(--ok);border-color:var(--ok-line)}
.req__ears--unwanted{background:var(--warn-tint);color:var(--warn);border-color:var(--warn-line)}
.req__ears--optional{background:var(--violet-tint);color:var(--violet);border-color:var(--violet-line)}
/* --- EARS 文の inline 強調 (canonical 要件文中の id / SHALL / when 節) --- */
.ears-id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85em;font-weight:600;color:var(--brand);margin-right:.5rem}
.ears-when{font-style:italic;color:var(--ink-soft)}
/* ★--bad (= canonical --folio-normative) を使う。 ★--brand-deep を使ってはならない: srs.css:378 が明記する通り
 *   --brand-deep は「構造ヘッダ/フッタの *塗り* 専用」 token (dark でも暗色を維持し白文字を載せる前提) で、
 *   既存用法は全て background:var(--brand-deep); color:#fff。 これを地色 (--paper) 上の *文字色* に使うと
 *   dark で contrast 1.54 (--paper-2 上 1.38) = WCAG AA 4.5 の 1/3 で ★不可視になる (light は 13.23 ゆえ
 *   light だけ見ていると気づけない dark 専用の崩れ)。 canonical common.css:319-322 も .ears-shall は
 *   --folio-normative (#b22323 / dark #ef7a7a = danger 赤) で、 色相ごと --brand-deep とは別物。
 *   本 pack の写像表 (--folio-danger→--bad) に従うと --bad が両モードで canonical と ★byte 一致する
 *   (light #b22323 / dark #ef7a7a・dark contrast 5.8 で AA 充足)。
 * ★gate F は本件を捕捉できない: 生成物の live な .ears-shall は全て閉じた <details class="rq-norm"> 内にあり、
 *   probe-srs.js が visible() + area>=16 で filter するため評価対象に入らない (= 恒真 PASS)。
 *   ゆえ本 pair の contrast は selftest 側で token 値から静的に計算して pin する (gate F 緑は無証明領域)。 */
.ears-shall{font-weight:600;color:var(--bad);text-transform:uppercase}
CSS
}

# ---- pack 固有 folio-* head meta (folio-aduv 0-c) ----
# ★CORE (lib/common.sh core_emit_graph_head) は doc-type / status / version の 3 本固定で、 全 pack (16) 共有ゆえ編集禁止 (B6)。
#   canonical verification.html はさらに folio-layer / folio-glossary-automark / folio-stakeholders /
#   folio-xref-completeness を持つ (実測 = 計 7 本)。 欠けると inventory/automark/xref-completeness の opt-in signal が
#   生成物で失われる (flip 後に gate が keystone skip へ落ちる = 無検査の silent 化)。 ゆえ pack-level で contract.meta 由来 emit する
#   (glossary pack の per-pack emit と同型・CORE 不触)。 値が無ければ tag ごと省略 = canonical に無い meta を捏造しない (SHOULD 準拠)。
emit_pack_head_meta() {
  local layer automark stake xrefc
  layer="$(q '.meta.layer // ""')"
  automark="$(q '.meta.glossary_automark // ""')"
  # ★stakeholders は contract 側が YAML sequence (canonical JSON-LD の array と同型・CORE の型退行封鎖)。
  #   meta tag の content は canonical 逐語 1 行 ("Developer, AI Agent, External Reviewer") が SSoT ゆえ join して復元する。
  #   ★scalar が来たら abort する (fail-closed): 素で join すると string を 1 要素扱いで通してしまい、 CORE 側 JSON-LD の
  #   型退行 (array→string) を pack-level では検出できないまま素通しになる。 型そのものを契約 gate で pin する。
  local stake_type
  stake_type="$(q '.meta.stakeholders | type')"
  [[ "$stake_type" == "!!seq" || "$stake_type" == "!!null" ]] \
    || { echo "assemble-self-spec: ★meta.stakeholders は array 必須 (実際: $stake_type)。 scalar は CORE の JSON-LD folio:stakeholders を canonical の array から string へ型退行させる (jsonld-lint / inventory / fedges のいずれも捕捉しない fail-open)" >&2; exit 1; }
  stake="$(q '(.meta.stakeholders // []) | join(", ")')"
  xrefc="$(q '.meta.xref_completeness // ""')"
  [[ -n "$layer"    && "$layer"    != "null" ]] && printf '<meta name="folio-layer" content="%s">\n' "$(esc "$layer")"
  [[ -n "$automark" && "$automark" != "null" ]] && printf '<meta name="folio-glossary-automark" content="%s">\n' "$(esc "$automark")"
  [[ -n "$stake"    && "$stake"    != "null" ]] && printf '<meta name="folio-stakeholders" content="%s">\n' "$(esc "$stake")"
  [[ -n "$xrefc"    && "$xrefc"    != "null" ]] && printf '<meta name="folio-xref-completeness" content="%s">\n' "$(esc "$xrefc")"
  return 0
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio spec-pack assembler — self-spec fork (folio-cuom / 8dkl Leg A) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_spec_css
  printf '\n</style>\n'
  # 図 (mermaid) がある doc にだけ vendor を head に1回 load (defer・図ゼロなら何も出さない)。 ../assets/mermaid.min.js を参照。
  [[ "${HAS_MERMAID:-0}" -gt 0 ]] && printf '<script src="../assets/mermaid.min.js" defer></script>\n'
  core_emit_graph_head
  emit_pack_head_meta
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "この仕様が約束すること (1 文サマリ)"
  local nsec nreq ngl
  nsec="$(q '.sections | length')"; nreq="$(q '.requirements | length')"; ngl="$(q '.glossary | length')"
  printf '<div class="cover-meta"><span class="m"><span class="k">章の数</span><span class="v">%s 章</span></span><span class="m"><span class="k">規範要件</span><span class="v">%s 件 (EARS)</span></span><span class="m"><span class="k">用語</span><span class="v">%s 語</span></span><span class="m"><span class="k">版</span><span class="v">v%s / %s</span></span></div>\n' \
    "$nsec" "$nreq" "$ngl" "$(esc "$(q '.meta.version')")" "$(esc "$(q '.meta.date')")"
  core_emit_approval_block
  core_emit_cover_tail
}

# ---- block emitter (section[$si].blocks[$bi]) ----
emit_prose() { printf '<p data-component="spec-prose">%s</p>\n' "$(esc "$(q ".sections[$1].blocks[$2].text")")"; }
emit_note()  { printf '<div data-component="spec-note"><p>%s</p></div>\n' "$(esc "$(q ".sections[$1].blocks[$2].text")")"; }
emit_list() {
  printf '<ul data-component="spec-list-block">\n'
  while IFS= read -r item; do [[ -n "$item" ]] && printf '<li class="lbi">%s</li>\n' "$(esc "$item")"; done < <(q ".sections[$1].blocks[$2].items[]")
  printf '</ul>\n'
}
emit_code() {
  printf '<pre data-component="spec-code"><code>'
  local first=1
  while IFS= read -r line; do [[ "$first" -eq 1 ]] && first=0 || printf '\n'; printf '%s' "$(esc "$line")"; done < <(q ".sections[$1].blocks[$2].lines[]")
  printf '</code></pre>\n'
}
emit_table() {
  local si="$1" bi="$2" cap nrow ri c
  # ★caption / th / td は ★RAW emit (rich 契約値・esc 厳禁)。 esc すると原本 table の a.xref 13 / <code> 41 /
  #   <strong> 11 が &lt;a…&gt; へ化けて可視本文に literal escape が露出する (double-escape)。
  cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
  printf '<div class="tbl-wrap"><table data-component="spec-table">'
  [[ -n "$cap" && "$cap" != "null" ]] && printf '<caption>%s</caption>' "$cap"
  printf '<thead><tr>'
  while IFS= read -r h; do printf '<th>%s</th>' "$h"; done < <(q ".sections[$si].blocks[$bi].headers[]")
  printf '</tr></thead><tbody>\n'
  nrow="$(q ".sections[$si].blocks[$bi].rows | length")"
  for ((ri=0; ri<nrow; ri++)); do
    printf '<tr>'
    while IFS= read -r c; do printf '<td>%s</td>' "$c"; done < <(q ".sections[$si].blocks[$bi].rows[$ri][]")
    printf '</tr>\n'
  done
  printf '</tbody></table></div>\n'
}
# ★esc_mermaid (folio-cuom errata-1 M1): mermaid DSL 行の escape 規律。 esc() で ★全部 escape した後、
#   ★<b> / </b> の 2 literal ★だけ を raw へ戻す。
#   ★なぜ raw で戻すか: canonical mermaid は subgraph ラベルに <b>…</b> を ★live タグ で 9 組 (18 tag) 持つ。
#     escape したままだと 生成物の <pre> 内には &lt;b&gt; という ★文字列 が入り、 canonical の live タグと
#     byte で別物になる (= flip 時に原本と差が残る・受入 oracle D7 の悉皆 text sweep が未分類差分として露出する)。
#     mermaid vendor は innerHTML → entityDecode → 描画 ゆえ escape でも ★描画は一致 するが、 本 pack が守るのは
#     ★原本忠実性 (lossless flip) であって描画の等価性ではない。 ゆえ canonical と ★同じ live タグ で出す。
#   ★注入面を開かない: 戻すのは属性を持たない裸の 2 literal のみ (<b onmouseover=…> は esc された姿のまま残る)。
#     加えて extractor 側 pre_inline guard が「mermaid pre 内の ★出現 literal ⊆ {<b>, </b>, <br> / <br/> / <br />}」
#     「'<' / '>' へ decode される entity (named / numeric とも) 0 件」を fail-loud で課す
#     (contract へ入る前段の閉集合。 ★literal 単位 = 属性付き `<b class=…>` / 大文字 `<B>` も ★非該当で止まる
#      — 下流の mask / 変換 述語が完全 literal であることと粒度を揃えてある)。
#   ★対の detect: verify-self-spec.sh の同名 helper が期待側を同規律で作る (detect↔remediate parity・
#     片側だけ変えると「mermaid source 行列」chk が FAIL する)。
esc_mermaid() {
  local s; s="$(esc "${1-}")"
  s="${s//&lt;b&gt;/<b>}"; s="${s//&lt;\/b&gt;/<\/b>}"
  printf '%s' "$s"
}
emit_mermaid() {
  local si="$1" bi="$2" cap
  # ★render target = <pre class="mermaid"> (head の mermaid.min.js が SVG 描画する) + raw DSL を逐語保持 (round-trip 維持)。
  #   旧 <pre class="mermaid-src"> は raw DSL を露出するだけで描画されず gate I blocker (図の約束と実体が乖離) だった。
  printf '<figure data-component="spec-diagram" class="diagram"><pre class="mermaid">'
  local first=1
  while IFS= read -r line; do [[ "$first" -eq 1 ]] && first=0 || printf '\n'; printf '%s' "$(esc_mermaid "$line")"; done < <(q ".sections[$si].blocks[$bi].source_lines[]")
  printf '</pre>'
  # figcaption: contract の caption を優先。 空なら DSL 内の accDescr → accTitle を fallback 抽出 (gate I が figcaption 空を指摘・両者とも SSoT 由来)。
  # ★caption の由来で escape 規律が分かれる (folio-aduv):
  #   - contract caption = rich 契約値 (原本 figcaption 逐語・<code> 2 + span.term 1 を内包) ゆえ ★RAW emit。
  #   - DSL fallback (accDescr/accTitle) = mermaid source の *素テキスト* (preline 済 = tag 除去 + entity decode 後) ゆえ
  #     ★esc 必須。 raw で出すと DSL 中の < が生タグとして混入し HTML を壊す。 両者を同一変数で混ぜて一括 esc/raw すると
  #     どちらかが必ず壊れるため、 由来を保持して分岐する。
  cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
  if [[ -n "$cap" && "$cap" != "null" ]]; then
    printf '<figcaption>%s</figcaption></figure>\n' "$cap"
  else
    cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accDescr:[[:space:]]*//p' | head -1)"
    [[ -z "$cap" ]] && cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accTitle:[[:space:]]*//p' | head -1)"
    printf '<figcaption>%s</figcaption></figure>\n' "$(esc "$cap")"
  fi
}
# ★subhead: heading = esc (原本 h3 は inline tag 0 = plain 契約値) / essence = ★RAW (rich 契約値・esc 厳禁)。
#   anchor (原本 h3 の実 id) があれば h3 へ id= を刻む = corpus の fine section anchor 宛て inbound の解決先。
# ★★folio-cuom: 「anchor ★キーの不在」と「anchor が ★明示的な空文字列」を ★区別する (fork 元は両者を同一視して
#   一律 abort していた)。 self-spec canonical は h3 13 本のうち ★3 本 (§8.1 / §8.2 / §8.3) が ★id 属性を持たない
#   (実測) ため、 fork 元の規律をそのまま当てると ★素の canonical が生成不能 (恒真 abort) になる。
#   一方で規律を単純に外すと 「anchor を失った subhead が無言で id 無し h3 として出る」 fail-open が復活する。
#   ★構造的な分離: 抽出器は anchor キーを ★常に emit する (id が無ければ空文字列) ため、
#     - キーが ★無い / null      → 契約の破損 or 抽出規約の drift → ★abort (fail-closed・従来どおり)
#     - キーが ★有り値が空文字列 → canonical に id が ★無い ことの ★明示宣言 → id 無し h3 を emit (canonical 一致)
#   ★対の floor: verify-self-spec.sh は (a) id 付き h3 数 == 契約の非空 anchor 数、 (b) id 無し h3 数 == 契約の
#   空 anchor 数、 (c) ★契約非依存の census pin (FZC_SUBHEAD_ANCHORED) の 3 本で、 空文字列化による
#   「anchor の静かな消失」 (契約側も生成物側も空 = 0/0 恒真) を封鎖する。
emit_subhead() {
  local anchor has_anchor
  has_anchor="$(q ".sections[$1].blocks[$2] | has(\"anchor\")")"
  [[ "$has_anchor" == "true" ]] || { echo "assemble-self-spec: ★subhead (section[$1] block[$2]) に anchor キーが無い (抽出規約 drift・fail-closed)" >&2; exit 1; }
  anchor="$(q ".sections[$1].blocks[$2].anchor")"
  [[ "$anchor" != "null" ]] || { echo "assemble-self-spec: ★subhead (section[$1] block[$2]) の anchor が null (空文字列と区別できる形で宣言すること・fail-closed)" >&2; exit 1; }
  if [[ -n "$anchor" ]]; then
    printf '<div data-component="spec-subhead"><h3 id="%s">%s</h3><p class="sub-se">%s</p></div>\n' \
      "$(esc "$anchor")" "$(esc "$(q ".sections[$1].blocks[$2].heading")")" "$(q ".sections[$1].blocks[$2].essence")"
  else
    # ★canonical に id が無い subhead (実測 3 本)。 id 属性を ★捏造しない (navigable id 集合を原本と一致させる)。
    printf '<div data-component="spec-subhead"><h3>%s</h3><p class="sub-se">%s</p></div>\n' \
      "$(esc "$(q ".sections[$1].blocks[$2].heading")")" "$(q ".sections[$1].blocks[$2].essence")"
  fi
}
# 1 要件 row を emit ($1 = 要件 id)。
emit_requirement_row() {
  local id="$1" pat essence stmt class label anchor prio prio_badge
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  essence="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # ★navigable anchor (folio-aduv 0-a): 原本 <details class="spec-row" id="req-ver-001"> の実 id を row へ刻む。
  #   corpus inbound (#req-ver-* / #req-nav-*) の解決先。 ★これは data-req-id (大文字 SSoT) と .rid 可視 text への
  #   *追加* であり *置換ではない* (test-adversarial-verification.sh L143/158/219/324 が大文字 data-req-id を pin)。
  anchor="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anchor" && "$anchor" != "null" ]] || { echo "assemble-self-spec: ★要件 $id の anchor (navigable id) が空 (corpus inbound の解決先を失う・fail-closed)" >&2; exit 1; }
  # validate() が ears_pattern を allowlist 逐値判定済 = ここは到達不能であるべき。 :-unknown silent fallback でなく
  # hard error 化し、 万一 validate を擦り抜けた未知 pattern が無スタイル class="unknown" badge として silent emit されるのを封鎖。
  [[ -v EARS_CLASS[$pat] ]] || { echo "assemble-spec: ★到達不能: emit 時に未知 EARS pattern '$pat' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
  class="${EARS_CLASS[$pat]}"; label="${EARS_LABEL[$pat]}"
  # ★canonical dual-audience requirement (w1f cell-2 / ADR-0045 論点2): row = human container (data-audience="human")、
  #   normative fold = machine 部 (data-audience="machine")。 REQ-DA-STRUCT-1 (human→machine 子孫) / -2 (id 整合) /
  #   -4 (machine 部 aria-hidden 無し) / -5 (EARS-pattern 整合) を *生成物* へ適用する (floor 射程拡大)。
  #   ★適合は verify-spec §10 が *相当* に enforce する。 canonical な bin/folio folio_check_dual_audience は
  #   要件 container を <(section|details) data-audience="human"> で key するため、 本 row は <div> ゆえ未被覆
  #   (生成物は /tmp 生成で folio validate 非対象)。 canonical container form (section/details) への寄せ・
  #   validate-gate 被覆は follow-up (folio-tr0 置換/drift gate) 領分。
  # ★RFC-2119 優先度バッジ (ADR-0054 §2.2)。 class は contract の closed allowlist 値から決定的に導く。 可視ラベルは
  #   prose slot (空で emit → inject-prose が manifest から充填) ゆえ ここでは ★空要素 を置く。 priority を持たない
  #   contract では バッジごと emit しない (all-or-none は validate 済・0/0 恒真は verify の census floor が封鎖)。
  prio="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
  prio_badge=""
  if [[ -n "$prio" && "$prio" != "null" ]]; then
    [[ -v PRIO_OK[$prio] ]] || { echo "assemble-self-spec: ★到達不能: emit 時に未知 priority '$prio' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
    prio_badge="$(printf '<span class="rq-prio rq-prio-%s" data-prose-slot="priority" data-slot-id="prio-%s"></span>' "$prio" "$(esc "$anchor")")"
  fi
  printf '<div data-component="ears-requirement-row" id="%s" data-req-id="%s" data-ears-pattern="%s" data-audience="human">\n' "$(esc "$anchor")" "$(esc "$id")" "$(esc "$pat")"
  printf '<div class="rq-head"><span class="rid">%s</span>%s<span data-component="ears-badge" class="%s">%s</span></div>\n' "$(esc "$id")" "$prio_badge" "$class" "$(esc "$label")"
  # ★essence / statement は ★RAW emit (rich 契約値・esc 厳禁)。 esc すると原本の a.xref / span.term / ins|del.delta /
  #   <code> が literal escape へ化ける。 特に statement の <code>jq -S</code> が剥がれると 裸の jq -S が可視 prose に落ち
  #   folio_prose_only の code mask を外れて [how-outside] P-11 primitive を踏む (0-e = PRESERVE + mask をこの raw 経路で担保)。
  printf '<p class="rq-essence">%s</p>\n' "$essence"
  # ★「やさしく言うと」平易行 (ADR-0054 §2.2)。 本文は prose slot (人間層 edit-SSoT = prose manifest・ADR-0052 §2.4) で、
  #   assembler は ★空要素だけ を決定的に置く (要件 essence/normative は contract SSoT のまま不変 = 平易行は ★純追加)。
  #   ★著述規律 (V確定3): 平易行は plain text + <a> (class=xref 無し) のみ = span.term / 人間層 <code> を新規に
  #   生やさない (全 FZ census scalar 不変の実証形)。 本規律は prose manifest 側の著述で守る (assembler は空要素のみ置く)。
  printf '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span><span data-prose-slot="plain" data-slot-id="plain-%s"></span></p>\n' "$(esc "$anchor")"
  printf '<details class="rq-norm" data-audience="machine"><summary>%s</summary><p class="rq-stmt">%s</p></details>\n' "$(esc "$RQ_NORM_SUMMARY")" "$stmt"
  printf '</div>\n'
}
emit_requirements() {
  printf '<div class="rq-list">\n'
  while IFS= read -r id; do [[ -n "$id" ]] && emit_requirement_row "$id"; done < <(q ".sections[$1].blocks[$2].ids[]")
  printf '</div>\n'
}

# ---- 機械層 (machine free-prose) emitter (w1f cell-2 / ADR-0045) ----
# ★★最重要 gotcha: machine_blocks.html / items は cell-1 が逐語 capture した *生 HTML* (inner_norm 済 = 単一行)。
#   ゆえ **RAW emit (esc 厳禁)**。 esc を通すと <span class="term"> → &lt;span class=&quot;term&quot;> に壊れる
#   (人間層 emitter は esc 経路ゆえ machine_blocks 専用に raw 経路を分ける)。 canonical form = data-audience="machine"
#   (rules §7/§11.5・REQ-DA-STRUCT-1..5 が *生成物* に適用される)。 p→prose / aside→note / ul→list。
emit_machine_block() { # $1 = block への yq path (e.g. ".machine_preamble[0]" / ".sections[$si].machine_blocks[$bi]")
  local base="$1" mt
  mt="$(q "$base.type")"
  case "$mt" in
    prose) printf '<p data-component="spec-machine-prose" data-audience="machine">%s</p>\n' "$(q "$base.html")" ;;
    note)  printf '<aside data-component="spec-machine-note" data-audience="machine">%s</aside>\n' "$(q "$base.html")" ;;
    list)  printf '<ul data-component="spec-machine-list" data-audience="machine">\n'
           while IFS= read -r it; do printf '<li class="mli">%s</li>\n' "$it"; done < <(q "$base.items[]")
           printf '</ul>\n' ;;
    # ★demoted (tr0 / verification): ADR-0040 機械層降格分 (<p>/<ul>/<pre><code> 内包) を *逐語* raw emit。
    #   inner は cell-1 が inner_norm 済 = 単一行 raw HTML。 RAW emit (esc 厳禁) ＝ 原本 div.demoted inner と round-trip 一致。
    demoted) printf '<div data-component="spec-machine-demoted" data-audience="machine">%s</div>\n' "$(q "$base.html")" ;;
    # ★dl (folio-aduv): 原本 <dl class="doc-meta" data-audience="machine"> の inner (<div><dt>/<dd></div> 列) を逐語 raw emit。
    dl) printf '<dl data-component="spec-machine-dl" data-audience="machine">%s</dl>\n' "$(q "$base.html")" ;;
    *) echo "assemble-self-spec: ★到達不能: emit 時に未対応 machine block type '$mt' ($base・validate を擦り抜けた・fail-closed)" >&2; exit 1 ;;
  esac
}

# 機械層 fold (native <details> = 既定非表示 [collapsed] + トグル [native disclosure]・no-JS。 rules §11.3/§11.5 の機械層挙動に整合)。
#   $1 = machine block 配列の yq path / $2 = summary ラベル。 配列が空なら何も emit しない (孤立 fold 防止)。
#   ★data-audience は *内側の各 block* が持つ (71 件)。 fold wrapper 自体は audience 中立 chrome (data-component で識別)。
emit_machine_fold() {
  local arr="$1" summary="$2" n i
  n="$(q "$arr // [] | length")"
  [[ "$n" -gt 0 ]] || return 0
  printf '<details data-component="spec-machine-fold" class="machine-fold">\n'
  printf '<summary><span class="mf-kicker">%s</span> <span class="mf-label">%s</span> <span class="mf-count">%s 件</span></summary>\n' "$(esc "$MF_KICKER")" "$(esc "$summary")" "$n"
  printf '<div class="machine-body">\n'
  for ((i=0; i<n; i++)); do emit_machine_block "$arr[$i]"; done
  printf '</div>\n</details>\n'
}

emit_blocks() {
  local si="$1" nblk bi btype
  nblk="$(q ".sections[$si].blocks // [] | length")"
  for ((bi=0; bi<nblk; bi++)); do
    btype="$(q ".sections[$si].blocks[$bi].type")"
    case "$btype" in
      prose)        emit_prose "$si" "$bi" ;;
      note)         emit_note "$si" "$bi" ;;
      list)         emit_list "$si" "$bi" ;;
      code)         emit_code "$si" "$bi" ;;
      table)        emit_table "$si" "$bi" ;;
      mermaid)      emit_mermaid "$si" "$bi" ;;
      subhead)      emit_subhead "$si" "$bi" ;;
      requirements) emit_requirements "$si" "$bi" ;;
      *) echo "assemble-spec: ★未対応 block type '$btype' (silent drop 禁止・fail-closed)" >&2; exit 1 ;;
    esac
  done
}

emit_section() {
  local si="$1" tint kicker heading essence icon anchor
  tint="$(q ".sections[$si].tint")"
  kicker="$(q ".sections[$si].kicker")"
  heading="$(q ".sections[$si].heading")"
  essence="$(q ".sections[$si].essence")"
  icon="${SECT_ICONS[$(( si % ${#SECT_ICONS[@]} ))]}"
  # ★top-level section anchor (folio-aduv 0-a): 原本 <section id="s1-contract"> の実 id を章頭へ刻む。
  #   ★band() は lib/common.sh = CORE (16 pack 波及) ゆえ 1 byte も触れない (fence)。 band が開く
  #   <section data-component="chapter-deck-band"> へ id を足せないため、 pack-level で ★章全体を
  #   anchor 付き <section> で ★包む (canonical の実構造 <section id="s1-contract" class="normative"> と同形)。
  #
  # ★anchor を「band 直前の <span id> sibling」で置いてはならない (実測で確認済の fail-open):
  #   fragment 解決 (browser) は id を持つ任意要素で成立するが、 ★同じ構造のもう一人の消費者である
  #   bin/folio の folio_chrome_toc_rows は h2/h3 の TOC target を (a) 見出し自身の id → (b) 最近接の
  #   ★外側 <section id="…"> の 2 段 fallback でしか解決しない。 band が開く <section> は id を持たず h2 にも
  #   id が無いため tgt="" となり ★行ごと drop される (span は section でも h2 でもないので参照されない)。
  #   実測: canonical toc_rows 25 行 (lvl2=7 / lvl3=18) に対し span 形の生成物は 18 行 (★lvl2=0) で、
  #   章見出し 7 本 (s0-reader-guide … s6-references) が全滅した。 波及は 2 点:
  #     (1) canonical は <!-- folio:chrome-toc --> に 25 entry を焼いており、 flip 後の folio build 再生成で
  #         25→18 = ページ内目次から章 entry が全消滅する。
  #     (2) folio_chrome_skip_target は toc_rows 先頭行を採るため skip-link の行き先が
  #         #s0-reader-guide → #s1-1-concepts へ静かに移動する (a11y 経路の回帰)。
  #   ★id 属性の *集合* 一致 (55==55) は ★構造一致を証明しない (集合 assert は span でも緑になる) —
  #   本件がその実証ゆえ、 self-test は (lvl, target) 列の逐字一致を id 集合とは ★独立に撃つこと。
  #   ★<section> 包みは CORE 不触のまま canonical 構造へ ★接近する (toc_rows の depth 追跡上、
  #   外側 sid=s1-contract → 内側 band section (sid="") → h2 が外側へ fallback して正しく解決する)。
  anchor="$(q ".sections[$si].anchor // \"\"")"
  [[ -n "$anchor" && "$anchor" != "null" ]] || { echo "assemble-self-spec: ★section[$si] の anchor (navigable id) が空 (corpus inbound の解決先を失う・fail-closed)" >&2; exit 1; }
  printf '<section id="%s">\n' "$(esc "$anchor")"
  # ★ADR-0054 §2.2: 章帯の巨大番号を ★見出しの節番号 と一致させる (core band() の連番でない)。
  # ★★引数位置のコマンド置換にしない: bash は set -euo pipefail 下でも「引数中の $( ) の失敗」を親コマンドの
  #   成否へ反映しないため、 heading_secnum の exit 1 は置換用 subshell で飲まれ、 空 num が band_num へ渡って
  #   <span class="num"></span> の defective artifact が rc=0 で出る (= 宣言 fail-closed の空文化)。
  #   ★代入形なら set -e が効く。 意図を残すため || exit 1 も明示する。
  local secnum; secnum="$(heading_secnum "$heading")" || exit 1
  band_num "$secnum" "$tint" "$kicker" "$heading" "$icon"
  # ★essence は ★RAW emit (rich 契約値・esc 厳禁)。
  printf '<div data-component="section-essence-callout"><p class="sec-se">%s</p></div>\n' "$essence"
  emit_blocks "$si"
  # ★機械層 (w1f cell-2): この章の data-audience="machine" 自由文を fold で既定非表示・人間層 (essence/blocks) の後に置く。
  emit_machine_fold ".sections[$si].machine_blocks" "$heading の地の文・運用説明・rationale"
  band_end
  # ★anchor 付き <section> を閉じる (band_end = chapbody の </div> の ★外側)。
  printf '</section>\n'
}

# references = 非終端 照会 (前方・他文書へ)。 token/doc/role を固定属性で刻む (verify-spec が echo 厳密一致で突合)。
emit_references() {
  printf '<div class="ref-grid">\n'
  # ★IFS= read で 1 行受け手動 tab split: 空 title (title 無し contract) が IFS-whitespace の tab 畳みで列を
  #   潰すのを防ぐ (@tsv は常に 4 列 = 3 tab)。
  q '.references[] | [.token, .doc, .role, (.title // "")] | @tsv' | while IFS= read -r line; do
    token="${line%%$'\t'*}"; rest="${line#*$'\t'}"
    doc="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
    role="${rest%%$'\t'*}"; title="${rest#*$'\t'}"
    [[ -n "$token" ]] || continue
    # ★role の可視ラベルだけ平易語 map を適用 (attr data-ref-role は ★機械 token を保持)。 map 外 role は hard error
    #   (validate の ROLE_OK と同一 key 集合ゆえ到達不能であるべき・silent な英語生表示 fallback を封鎖)。
    [[ -v ROLE_PLAIN[$role] ]] || { echo "assemble-self-spec: ★到達不能: emit 時に平易語 map 外の role '$role' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
    # ★rf-gloss = 照会先の一行タイトル (contract references[].title の ★逐語 echo)。 title 無し contract では emit しない。
    gloss=""
    [[ -n "$title" ]] && gloss="$(printf '<span class="rf-gloss">%s</span>' "$(esc "$title")")"
    printf '<div data-component="cross-doc-ref-chip" data-ref-token="%s" data-ref-role="%s"><span class="rf-token"><b>%s</b></span><span class="rf-arrow">\xe2\x86\x92</span><span class="rf-doc">%s</span><span class="rf-role">%s</span>%s</div>\n' \
      "$(esc "$token")" "$(esc "$role")" "$(esc "$token")" "$(esc "$doc")" "$(esc "${ROLE_PLAIN[$role]}")" "$gloss"
  done
  printf '</div>\n'
}

# emit_glossary (glossary-term-table) は lib/common.sh (core) を使う。

# EARS 凡例 (静的 key・色分け badge と §6「用途」label の対応を 1 度だけ提示・folio-2jr)。 cover 直後に emit。
# 5 pattern を rules.html §6 table 行順で列挙。 label は EARS_LABEL (= §6 用途 SSoT)・色 class は EARS_CLASS。
# data-component=ears-legend-item は ears-badge とは別 (verify-spec の ears-badge==|requirements| カウントに干渉させない)。
#
# ★★conditional 化 (folio-cuom ■1(7) / 契約 fence の「死機構は fork 内 conditional 化」)。
#   ★対象は ★EARS legend ★のみ (references band は self-spec でも live ゆえ ★触らない — trim すると
#   emit_references / FZC_RF_GLOSS 突合 / 照会 graph が同時に落ちる)。
#   ★なぜ conditional か: 凡例は「この文書に出てくる規範要件の型の見取り図」であり、 要件 0 件の文書に出すと
#   ★読者に存在しない要件を約束する (over-promise) 上、 生成物に「EARS 5 型」だけが浮いた死領域として残る。
#   ★なぜ ★削除 でなく conditional か: 本 fork の emitter 群 (要件 row / badge / normative fold / 優先度バッジ) は
#   全て残置してあり、 将来 self-spec contract に要件が入れば ★そのまま動く。 凡例だけを消すと その日に
#   ★凡例なしで要件が出る 非対称が生まれる。 「0 件なら出さない・1 件でも有れば出す」が唯一の無矛盾な規律。
#   ★verify 側 (verify-self-spec.sh) は同じ条件式を ★二重保守 で持ち、 期待値 (legend 0 or 1 / legend-item 0 or 5) を
#   contract の |requirements| から ★導出 する (両側 hardcode の合意でなく contract を trust anchor にする)。
emit_ears_legend() {
  # ★fail-closed 側に倒す条件: |requirements| == 0 のときだけ ★出さない。 それ以外 (1 件以上) は必ず出す。
  [[ "$(q '.requirements | length')" -gt 0 ]] || return 0
  printf '<div data-component="ears-legend"><span class="el-cap">EARS 5 型 (規範要件の種類)</span>'
  local pat
  for pat in ubiquitous event-driven state-driven optional unwanted; do
    # 各型 = 色 badge (§6 用途 label) + 平易な「いつ守るか」(persona-walk major-1)。
    printf '<span class="el-item"><span data-component="ears-legend-item" class="%s">%s</span><span class="el-when">%s</span></span>' \
      "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$(esc "${EARS_WHEN[$pat]}")"
  done
  printf '</div>\n'
}

# footer は core_emit_footer に spec-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
emit_footer() {
  core_emit_footer '<span>folio design system</span><span>spec-pack (self-spec fork)</span><span>folio engine</span><span>章立て + 非終端 照会 (4 種) + 機械層 trailing-fold</span>'
}

# 図がある doc にだけ mermaid.initialize を1回 emit (原本 relations.html を mirror: startOnLoad:false + DOMContentLoaded run・base theme・横スクロール図 keyboard-focus 化)。
#   ★契約は startOnLoad:true と記すが、 原本が verified に動く startOnLoad:false + mermaid.run() を優先 (defer load 後の確実な run)。 figure ゼロなら何も出さない。
emit_mermaid_script() {
  [[ "${HAS_MERMAID:-0}" -gt 0 ]] || return 0
  cat <<'MJS'
<script>
window.addEventListener('DOMContentLoaded', async () => {
  if (!window.mermaid) return;
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'antiscript',
    theme: 'base',
    flowchart: { useMaxWidth: false },
    themeVariables: {
      primaryColor: '#2a4d6e',
      primaryTextColor: '#ffffff',
      lineColor: '#2a4d6e',
      secondaryColor: '#5ac8b8',
      edgeLabelBackground: '#15324a',
      tertiaryColor: '#f5f8fa'
    }
  });
  try { await mermaid.run(); } catch (e) {}
  document.querySelectorAll('figure.diagram > pre.mermaid').forEach((p) => {
    if (p.scrollWidth > p.clientWidth + 1) {
      p.tabIndex = 0;
      p.setAttribute('role', 'region');
      const t = p.querySelector('svg title');
      if (t && t.textContent) p.setAttribute('aria-label', t.textContent + ' (横スクロール可能な図)');
    }
  });
});
</script>
MJS
}
build() {
  local nsec si
  # 図 (mermaid block) が1つ以上ある doc にだけ mermaid vendor + initialize を1回 emit (図ゼロなら script 無し)。 emit_head/foot が参照。
  HAS_MERMAID="$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')"
  emit_head "$(q '.meta.title')"
  printf '<div class="page" data-component="requirement-type-color-tokens">\n'
  emit_cover
  emit_ears_legend
  # ★機械層 文書前文 (w1f cell-2): section 外の data-audience="machine" 前文を fold で既定非表示・cover/legend の後・§1 の前に置く。
  emit_machine_fold ".machine_preamble" "文書前文 (この規約集の位置づけ)"
  nsec="$(q '.sections | length')"
  derive_static_band_headings
  for ((si=0; si<nsec; si++)); do emit_section "$si"; done
  # ★前方照会 / 用語集の ★章化 (ADR-0054 §2.2 + admin 裁定 C2)。 従来この 2 band は section で包まれず bare band() だった
  #   ため「章としての到達可能性」を持たなかった。 section id 付きの章として包む。
  #   ★id は番号なし canonical token (PRESENTATION_WRAPPER_IDS)・★class は付けない (census 不変)。
  # 非終端 照会 (前方 references) band。 ★heading は実在する照会種別のみを約束する (verification は P-x / ADR の 2 種)。
  printf '<section id="%s">\n' "$(esc "${PRESENTATION_WRAPPER_IDS[0]}")"
  band_num "${STATIC_BAND_NUMS[0]}" violet "この仕様が参照する文書 / 照会 (前方)" "${STATIC_BAND_HEADINGS[0]}" "$ICO_ARROW"
  emit_references
  band_end
  printf '</section>\n'
  # 用語集 band (core glossary)。
  printf '<section id="%s">\n' "$(esc "${PRESENTATION_WRAPPER_IDS[1]}")"
  band_num "${STATIC_BAND_NUMS[1]}" brand "用語集 / この文書で使う専門語" "${STATIC_BAND_HEADINGS[1]}" "$ICO_TAG"
  emit_glossary
  band_end
  printf '</section>\n'
  printf '</div>\n'
  emit_footer
  emit_mermaid_script
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-spec"
