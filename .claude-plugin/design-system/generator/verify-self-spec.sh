#!/usr/bin/env bash
# folio engine (folio-cuom) — spec-pack fabrication-free + 非終端 照会 floor の FORK (doc-type=spec / folio-self-spec self-host)
#
# ★verify-verification.sh の FORK (8dkl self-spec flip の bootstrap = Leg A)。 共有 core (lib/) 無改変。
#   base に verification を選ぶ理由 (契約 ■2(e)): containment 一式 (章・wrapper の 3 レベル完全子数束縛 + HTML5 同型
#   tokenizer) / 機械層 round-trip / 凍結 census を ★既に保有する確立形 だから。 verify-spec.sh (rules) を base に
#   すると containment を欠いた fork を新規に生む。
#
# ★★self-spec 固有差分の ★実態開示 (silent な差分は「範型踏襲済」の誤報告になる):
#   (1) ★要件 0 件 — |requirements| 相対の chk は ★恒真 PASS のまま残置しない (契約 M5)。 削除でなく
#       ★NREQ==0 を不変量として pin した negative assert (要件 row / badge / 凡例 / 優先度バッジ / 平易行が
#       生成物に 1 件も出ない) へ ★置換 し、 要件を 1 本注入した fixture で FAIL する ★陽性対照 を
#       test-adversarial-self-spec.sh が per-shape で撃つ。
#   (2) ★EARS 凡例は conditional — |requirements| == 0 なら legend 0 / legend-item 0 が ★期待値。 期待は
#       hardcode でなく ★contract の |requirements| から導出する (両側 hardcode の合意に依らない)。
#   (3) ★subhead の id は 13 本中 ★10 本 のみ (canonical の §8.1/§8.2/§8.3 は h3 に id を持たない・実測)。
#       ゆえ SUBHEAD_RE は id ★任意 形にし、 (a) id 付き数 == 契約の非空 anchor 数 / (b) id 無し数 ==
#       契約の空 anchor 数 / (c) 契約非依存 census pin の 3 本で「anchor の静かな消失」を封鎖する。
#   (4) ★doc_id literal guard を入口に持つ (契約 M3・qojv 決定 2 の「verify literal」) — doc_type==spec は
#       5 契約が共有し識別力ゼロゆえ、 他 pack contract を食わせた誤用を doc_type では 1 つも止められない。
#   (5) ★ORIG (spec-origin/*.origin.html = 手書き版の正式 archive) は ★本 Leg では存在しない。 snapshot 作成は
#       flip cell (folio-mkwc) の職掌 (契約 N2 / ■7) ゆえ、 fork 元の「ORIG 存在 fail-closed pin」は ★移植しない。
#       ★代わりに黙って落とさず本 header と該当箇所で ★不在を明示する (下記 §10b/§11 の注記)。 凍結 census
#       (spec-origin/self-spec.frozen-census.txt) は ★存置 する — こちらは ORIG に依存せず、 両側 contract 由来の
#       vacuous PASS (extractor collapse) を塞ぐ ★唯一の独立 anchor ゆえ落とすと被覆が縮む。
# 生成 spec (verification) HTML の *構造* が入力 spec contract から完全に導出されたことを機械検証する floor gate。
# verify-fabrication-free.sh (SRS) / verify-adr.sh / verify-research.sh / verify-principle.sh と同型の規律を
# spec-pack schema (sections / requirements(EARS) / references(非終端 照会) / glossary) へ適用する:
#   - 行数 = contract 導出 (section / band / 要件 row / ref chip / block 種別ごとの件数)。
#   - 要件 fidelity: data-req-id 集合一致 + (id, ears-pattern, badge class/label, essence, statement) を emission 順で突合。
#   - section fidelity: 可視 heading 列 / essence 列が contract と順序一致。
#   - block fidelity: prose / note / list / code / table / mermaid / subhead の可視テキストを順序突合 (silent drop 検出)。
#   - ★非終端 照会 (references): chip が token/doc/role を faithfully echo (count / SET / role allowlist / (token,role) ペア / 可視 <b>==attr)。
#   - core 共通 chrome (cover-head / approval / glossary) = verify_core_chrome (folio-mk9)。 cover-meta 4 KV 再導出。
#   - escape 健全 / prose スロット (3 mode = pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)。
#
# usage: verify-self-spec.sh [--filled <manifest.yaml> | --artifact] <spec-contract.yaml> <generated.html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate モデル・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合。
#   prose スロット (cover-summary / chapter-lead-NN) の *内容真正性* は floor の対象外 = ceiling (fidelity-* 相当・persona-walk)。
#   floor 単独で GREEN にはならず CEILING=PENDING (taxonomy §5.1)。 spec-pack 専用 ceiling agent の制度化は follow-up (admin 起票)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-self-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-self-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-self-spec: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-self-spec: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-self-spec: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-self-spec: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_core_chrome) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-self-spec: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-self-spec: failed to source verify-common.sh" >&2; exit 2; }

# EARS pattern → class / label (assemble-spec.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table「用途」列 SSoT に一致 (folio-2jr drift 是正)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1・assemble-spec と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )
# ============================================================================
# ★ADR-0054 (提示層標準形) lockstep 定数群 — assemble-self-spec.sh と ★二重保守 (detect↔remediate parity)。
#   assembler が emit する平易ラベル / 静的見出し / wrapper id を verify 側でも宣言し、 ★逐値で突合する
#   (片側だけ変えると FAIL する = 提示層の drift を lockstep で封鎖する)。
# ============================================================================
# ★role の平易語 map。 attr (data-ref-role) は機械 token を保持し、 ★可視ラベルのみ map 適用 (chip 突合は
#   attr=token / visible=平易語 の ★非対称 を literal に要求する = 可視の英語生表示への退行を捕捉)。
declare -A ROLE_PLAIN=(
  [implementation]="この規約が実装する原則" [rationale]="そう決めた理由の記録" [claim]="この文書が満たすと主張する要件"
  [exploration]="探索の記録" [principle]="拠って立つ原則" [verification]="どう確かめるかの仕様"
)
# ★RFC-2119 優先度 (must|should) → 可視ラベルの ★closed allowlist ('|' 区切りの逐値集合)。 バッジの可視文字列は
#   prose slot が持つため、 floor は「level ごとに許される可視ラベルの ★有限集合」に属するかを逐値突合する。
# ★前方一致 (語幹で始まる) は使わない (ehar クラス): 「必須ではない」のような ★否定接尾 が語幹で始まるため
#   prefix 判定を素通りし、 level と意味が反転したまま全 gate を通る。
# ★集合の拡張には prose manifest / 本 allowlist / assemble-self-spec.sh の同名配列の ★三点同時更新 が必要 (fail-closed)。
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 ★§番号は literal 固定せず contract の
#   最終 section 見出しから ★導出 する (下記 STATIC_HEADINGS 組み立て)。 assemble-self-spec.sh と二重保守。
#   ★self-spec の照会種別は ★4 種 (原則 P-x 8 / 決定記録 ADR 16 / 規約要件 rules REQ-* 8 / 検証仕様 REQ-VER 1 = 33)。
#   ★base (verification=2 種) / rules (3 種) の逐語流用は禁止 — 本値は self-spec contract の実測導出。
STATIC_HEADING_TAILS=("上位文書への前方照会 — 原則・決定記録・規約要件・検証仕様へつながる" "本文に出てくる専門語のやさしい説明")
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token 2 つに固定)。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★各 wrapper が包む章帯の tint (assemble-self-spec.sh build() の band_num 実引数 violet / brand と ★二重保守)。
#   containment の「開口隣接 literal pin」で band の ★同一性 (どの章の帯か) まで逐値要求するために持つ
#   (tint を持たないと「隣に *何らかの* band が在る」しか言えず、 別章 band の付け替えが素通る)。
PRESENTATION_WRAPPER_BAND_TINTS=("violet" "brand")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2・wave 恒常 2)。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# ★契約非依存 census floor の期待値 (★verification 固有・0/0 恒真封鎖・wave 恒常 3)。 新 field (references[].title /
#   requirements[].priority) と subhead essence は ★all-or-none / optional ゆえ、 契約から一括削除すると
#   「契約側も生成物側も空」で逐値突合が ★0/0 恒真 PASS する。 生成物の占有数を ★数値 hardcode で pin して封鎖する。
# ★★relations (verify-relations.sh:78-86) / rules (verify-spec.sh:72-75) の literal 流用は ★禁止 — 本値は
#   verification contract の実測から導出したもの (arm 名も spec ごとに異なりうる: relations は subsub / 本 pack は subhead)。
# ★★self-spec 実測 (base の値を ★複写しない — 各値は本 pack の contract / 生成物から実測導出した)。
FZC_SECTION_SE=7        # ★章 レベルの人間層 1 行要約 (.sec-se) を ★非空 で持つ章数 = |sections| (errata-1 M2)
FZC_SUBHEAD_SE=13       # 人間層 1 行要約 (.sub-se) を ★非空 で持つ subhead 数 = |subhead blocks| (空 subsection 0)
FZC_SUBHEAD_ANCHORED=10 # h3 に id を持つ subhead 数 (canonical 実測。 §8.1/§8.2/§8.3 の 3 本は id を持たない)
FZC_SUBHEAD_BARE=3      # h3 に id を持たない subhead 数 (= 13 - 10)。 ★両方を pin して片側だけの増減を挟む。
# ★★以下は base (verification) が持っていたが ★self-spec では 0 になる pin — ★0/0 恒真 pin を置かない (V確定5b)。
#   代わりに ★NREQ==0 / |title|==0 を ★不変量として宣言 し、 negative assert + 陽性対照 (test-adversarial) で撃つ (契約 M5)。
#   FZC_RQ_PRIO / FZC_RQ_PLAIN (要件 32 件前提) → ★該当なし (self-spec は要件 0 件)。 下記 §4b を参照。
#   FZC_RF_GLOSS (references[].title 30 件前提) → ★該当なし。 本 pack の contract は references[].title を
#     ★持たない (extractor は title を起こさず、 33 件の一行タイトルの手起こしは契約 ■2 の成果物集合の外)。
#     ゆえ rf-gloss は 0 件が ★期待値 であり、 それを negative assert + 陽性対照で pin する (0/0 恒真にしない)。
#     ★申送り (admin 起票候補): ADR-0054 §2.2 の「照会チップに一行タイトルを併記」を self-spec でも満たすなら
#     references[].title 33 件の著述が要る (flip cell mkwc か別 cell)。 本 Leg では ★意図的に不実施。
# ★§6 ref-primary (References の一次参照可視化) は ★relations 固有 arm ゆえ本 pack でも実装しない (0 件)。
#   ★0/0 恒真 pin を ★置かない (0 == 0 の恒真 chk は teeth を持たず「検査している」と誤読させるため・V確定5b)。

fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build self-spec "$FILLED_MANIFEST"

echo "spec-pack fabrication-free + 非終端 照会 floor: $HTML"
echo "  contract: $CONTRACT"

NSEC="$(q '.sections | length')"
NREQ="$(q '.requirements | length')"

# ★節番号 (§N) を contract sections[].heading から ★導出 する (ADR-0054 §2.2 の band .num 突合の trust anchor)。
#   band の巨大番号 (.num) 期待列を hardcode で作ると assembler 側の導出と ★両側が同じ仮定に合意しているだけ になり、
#   実際の見出し (h2 の「§N.」) と .num が食い違っても検出できない。 見出し自身を trust anchor にして構造束縛する。
# ★fail-closed: §N を持たない heading が 1 本でもあれば abort (0 件マッチの恒真化を防ぐ)。
# ★-Mutf8 必須: -CSD は入力を decode するが ★program source の literal は decode しない — 「§」を素の byte のまま
#   書くと decode 済み入力と一致せず ★常に 0 match = 全 heading が NO-SECTION-NUMBER となり誤 abort する。
SEC_NUMS="$(q '.sections[].heading' | perl -CSD -Mutf8 -ne 'chomp; if (/^§(\d+)\./) { print "$1\n" } else { print "NO-SECTION-NUMBER\n" }')"
if [[ -z "$SEC_NUMS" ]] || printf '%s\n' "$SEC_NUMS" | grep -q 'NO-SECTION-NUMBER'; then
  echo "verify-self-spec: ★contract sections[].heading に §N 形でない見出しがある (番号導出不能・fail-closed)" >&2
  echo "  headings: $(q '.sections[].heading' | tr '\n' '|')" >&2
  exit 2
fi
SEC_LAST_NUM="$(printf '%s\n' "$SEC_NUMS" | tail -n 1)"
# 静的 2 band (前方照会 / 用語集) は最終 section の §番号の ★次 / ★次々。
STATIC_NUMS=("$((SEC_LAST_NUM + 1))" "$((SEC_LAST_NUM + 2))")
STATIC_HEADINGS=("§${STATIC_NUMS[0]}. ${STATIC_HEADING_TAILS[0]}" "§${STATIC_NUMS[1]}. ${STATIC_HEADING_TAILS[1]}")

# ---- ★0b. class-token の ★閉 allowlist + consumer 一次 selector の negative assert (errata-1 M5) ----
# ★塞ぐ穴 (独立 ceiling blocking M5・end-to-end 実証済): 本 floor の bucket 系 chk は「値集合 membership」
#   (この text が contract 由来の集合に属するか) で判定するため、 ★既存 marker の ★複製注入 を吸収していた。
#   実弾: contract の machine_blocks へ <div class="meta">…</div> を 1 個足すと consumer
#   (.claude-plugin/bin/folio の folio_extract_summary = grep -oP '<div class="meta">\K[^<]*' | head -1) が拾う
#   ★文書 summary を乗っ取れる (inventory / prime digest の派生 SSoT が捏造値に置き換わる)。
# ★★payload クラスで結果が違う (errata-2 M10・旧記述の false record 是正・両クラスとも worker 実測):
#   - ★bucket 吸収 text (例 .glossary[].def の逐語) を載せた場合 → D7 oracle の ★未分類 arm は ★沈黙 し、
#     errata-1 以前は floor / repro-build / D7 oracle が ★全緑 のまま乗っ取れた = 「全緑で乗っ取り」が
#     成立するのは ★この payload クラス のみ。 本 §0b の 2 arm と oracle の bucket 件数 pin が現在の防壁。
#   - ★非吸収 text (「v9.9.9 · status: hijacked …」等) → D7 の ★既存 未分類 arm が ★先に 撃つ (errata-1 以前でも赤)。
#     旧コメントはこの区別を書かず「全緑のまま乗っ取れた」と記していた = 実弾記述の誤り (是正済)。
#     対応する実弾は test-adversarial-self-spec.sh の F24 (吸収 payload へ差し替え済) / F24b / F24c。
# ★(a) class-token 機械的網羅 (7 pack の *_CLS 同型・folio-bur r6 idiom の移植): 生成物 body の ★全 class token が
#   allowlist に属することを quote/case/entity 非依存に強制する = ★novel marker の任意注入を一網打尽に封鎖する。
#   ★56 token は本 pack の生成物 実測 (base pack の literal を複写しない = 空撃ち floor 回避・契約 M6 と同規律)。
SELFSPEC_CLS="chapbody cover-eyebrow cover-meta cover-sub diagram doc-type en foot ft-grid ft-plain gdef grow gword ic ico k kicker lab lead m machine-body machine-fold mermaid mf-count mf-kicker mf-label mli normative-ref num page reader-chip ref-grid rf-arrow rf-doc rf-role rf-token role sec-se self sign stamp sub-se summary-card tags tbl-wrap term tint-brand tint-info tint-ok tint-violet tint-warn txt v when who xref"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $SELFSPEC_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が閉 allowlist (novel marker / 既存 marker 複製の注入封鎖・M5)" "$unknown_cls"
# ★allowlist 側の空振り封鎖: 宣言した token が ★全て 生成物に実在すること (実在しない token を並べて
#   allowlist を膨らませ、 実質何も弾かない集合へ痩せる形を塞ぐ)。
missing_cls="$(printf '%s\n' $SELFSPEC_CLS | sort -u | grep -vxF -f <(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token allowlist の空振り封鎖: 宣言 token は全て生成物に実在 (allowlist 膨張の封鎖)" "$missing_cls"
# ★(b) consumer 一次 selector の ★negative assert (契約非依存 pin)。 生成 spec は ADR-0054 で chrome-less ゆえ
#   <div class="meta"> を ★1 個も持たない が正。 (a) の class 閉集合と ★二重化 する (class 側だけだと、
#   将来 'meta' が正当 token として allowlist へ入った瞬間に この consumer 経路が無防備へ戻る)。
#   ★RAW 出現 で数える (consumer 自身が raw grep ゆえ、 consumer と同じ目で見るのが正しい検出面)。
chk "consumer 一次 selector: '<div class=\"meta\"' の RAW 出現 == 0 (inventory summary 乗っ取り封鎖・M5)" "0" \
  "$(grep -o '<div class="meta"' "$HTML" | wc -l | tr -d ' ')"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)。
#    chapter-deck-band = section 数 + 2 (references band + glossary band)。
chk "chapter-deck-band == sections + 2"   "$((NSEC + 2))"                  "$(grep -c 'data-component="chapter-deck-band"' "$BODY")"
chk "section-essence-callout == sections" "$NSEC"                          "$(grep -c 'data-component="section-essence-callout"' "$BODY")"
chk "ears-requirement-row == |requirements|" "$NREQ"                       "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "ears-badge == |requirements|"        "$NREQ"                          "$(grep -c 'data-component="ears-badge"' "$BODY")"
# ★EARS 凡例 (folio-2jr・静的 key): 1 個・5 item・label は EARS_LABEL (= rules.html §6 用途 SSoT) と §6 行順で一致 (assemble-spec と二重保守=parity)。
# ★★M5 (folio-cuom): EARS 凡例は assemble-self-spec.sh で ★conditional (|requirements| == 0 なら emit しない)。
#   期待値は ★両側 hardcode の合意にせず contract の |requirements| から ★導出 する (assembler と同じ条件式を
#   verify 側でも宣言 = detect↔remediate parity。 片側だけ変えれば FAIL する)。
#   ★self-spec の現契約では NREQ==0 ゆえ 期待は legend 0 / legend-item 0 / el-when 0 — これは ★恒真 PASS ではない:
#   凡例を無条件 emit へ戻す退行は 0 != 1 で FAIL し、 要件を 1 本注入した fixture では 1/5/5 が期待になる
#   (陽性対照 = test-adversarial-self-spec.sh の C3 群 = 要件 1 本 contract を ★その contract 自身で verify し
#    NREQ>0 分岐 (legend 1 / item 5 / el-when 5 + label 列 + el-when 列) が ★実走して PASS することを撃つ)。
EXP_LEGEND=0; EXP_LEGEND_ITEM=0
if [[ "$NREQ" -gt 0 ]]; then EXP_LEGEND=1; EXP_LEGEND_ITEM=5; fi
chk "ears-legend == (NREQ>0 ? 1 : 0)"     "$EXP_LEGEND"      "$(grep -o 'data-component="ears-legend"' "$BODY" | wc -l | tr -d ' ')"
chk "ears-legend-item == (NREQ>0 ? 5 : 0)" "$EXP_LEGEND_ITEM" "$(grep -o 'data-component="ears-legend-item"' "$BODY" | wc -l | tr -d ' ')"
chk "ears-legend el-when == (NREQ>0 ? 5 : 0)" "$EXP_LEGEND_ITEM" "$(grep -o 'class="el-when"' "$BODY" | wc -l | tr -d ' ')"
# ★凡例の ★中身 (label 列 / el-when 列) の逐値突合は NREQ>0 のときだけ意味を持つ (NREQ==0 では両側空 = 恒真)。
#   ★恒真な chk を「検査している」風に並べない ため、 条件付きで ★実行そのものを分岐 する。
if [[ "$NREQ" -gt 0 ]]; then
  # ★★M5 の「conditional 化は legend 系に scope を限定し label / 順序 arm を巻き込まない」要求 (folio-cuom)。
  #   ★以下 4 行は base (verify-verification.sh:128-129 / 134-135) と ★逐語同一 に保つ — conditional 化で
  #   変えてよいのは「この if で囲む」ことだけ。 独自に書き換えると 3 クラスの破損が入る (実弾で確認済):
  #     (a) 期待側を `+= …$'\n'` で組むと ★末尾改行 が残るが、 実測側は command substitution で末尾改行が
  #         ★剥がれる ため NREQ>0 で必ず不一致になる (base は両側とも command substitution ゆえ対称)。
  #     (b) esc を落とすと ラベルに &<> が入った瞬間 HTML escape 済の実測側と不一致になる。
  #     (c) 抽出正規表現を class="[a-z]+" へ狭めると 複数 class / ハイフンを取り落とす。
  exp_legend="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_LABEL[$p]}"; printf '\n'; done)"
  act_legend="$(perl -CSD -0777 -ne 'while (/<span data-component="ears-legend-item" class="[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
  chk "ears-legend label 列 == EARS_LABEL (§6 用途 順)" "$exp_legend" "$act_legend"
  exp_when="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_WHEN[$p]}"; printf '\n'; done)"
  act_when="$(perl -CSD -0777 -ne 'while (/<span class="el-when">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
  chk "ears-legend el-when 列 == EARS_WHEN (順序)" "$exp_when" "$act_when"
fi
chk "cross-doc-ref-chip == |references|"   "$(q '.references | length')"   "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "glossary == |glossary|"              "$(q '.glossary | length')"      "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"              "$(q '.approval | length')"      "$(grep -c 'class="sign"' "$BODY")"
# block 種別ごとの件数 (silent drop / 偽 add を捕捉)。
chk "spec-prose == Σ prose blocks"        "$(q '[.sections[].blocks[]? | select(.type=="prose")] | length')"   "$(grep -c 'data-component="spec-prose"' "$BODY")"
chk "spec-note == Σ note blocks"          "$(q '[.sections[].blocks[]? | select(.type=="note")] | length')"    "$(grep -c 'data-component="spec-note"' "$BODY")"
chk "spec-list-block == Σ list blocks"    "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"    "$(grep -c 'data-component="spec-list-block"' "$BODY")"
chk "list 項目 (lbi) == Σ list items"     "$(q '[.sections[].blocks[]? | select(.type=="list") | .items[]] | length')" "$(grep -c 'class="lbi"' "$BODY")"
chk "spec-code == Σ code blocks"          "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"    "$(grep -c 'data-component="spec-code"' "$BODY")"
chk "spec-table == Σ table blocks"        "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"   "$(grep -c 'data-component="spec-table"' "$BODY")"
chk "spec-diagram == Σ mermaid blocks"    "$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')" "$(grep -c 'data-component="spec-diagram"' "$BODY")"
chk "spec-subhead == Σ subhead blocks"    "$(q '[.sections[].blocks[]? | select(.type=="subhead")] | length')" "$(grep -c 'data-component="spec-subhead"' "$BODY")"

# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# 1c. ★pack 固有 folio-* head meta (folio-aduv 0-c)。 CORE (core_emit_graph_head) が emit する 3 本 (doc-type/status/version)
#   の外側に、 verification.html は folio-layer / folio-glossary-automark / folio-stakeholders / folio-xref-completeness を
#   持つ (canonical 実測 = 計 7 本)。 これらは inventory / automark / xref-completeness の ★opt-in signal ゆえ、 欠けると
#   flip 後に該当 gate が keystone skip へ落ちる = 無検査の silent 化になる。
#   ★mutation-kill 実弾で確認した穴: assembler の emit_pack_head_meta 呼出を 1 行落とすと生成物の folio-* meta が
#   7→3 本へ落ちるのに、 本 script の FAIL 件数は baseline と完全一致だった (= 喪失に vacuous PASS)。 repro-build の
#   BYTE-DIFF も artifact 事後改変しか捕まえず、 contract と生成物が両側で同時に欠ける generator 回帰には無力。
#   ★双方向 chk (捏造も喪失も捕捉): contract に key が在れば逐字存在を要求し、 無ければ生成物にも不在を要求する。
#   ★stakeholders は contract 側が array (canonical JSON-LD と同型) ゆえ meta content は join(", ") で期待を組む。
verify_pack_head_meta() {
  local key tag exp act pair
  for pair in 'layer:folio-layer' 'glossary_automark:folio-glossary-automark' \
              'stakeholders:folio-stakeholders' 'xref_completeness:folio-xref-completeness'; do
    key="${pair%%:*}"; tag="${pair##*:}"
    if [[ "$key" == "stakeholders" ]]; then exp="$(q '(.meta.stakeholders // []) | join(", ")')"
    else exp="$(q ".meta.$key // \"\"")"; fi
    [[ "$exp" == "null" ]] && exp=""
    act="$(T="$tag" perl -CSD -0777 -ne 'BEGIN{$t=$ENV{T}} while (/<meta name="\Q$t\E" content="([^"]*)">/g){ print "$1\n"; }' "$HTML")"
    if [[ -n "$exp" ]]; then
      chk "head meta $tag == contract .meta.$key" "$(esc "$exp")" "$act"
    else
      chk "head meta $tag 不在 (contract 側も空 = 捏造禁止)" "" "$act"
    fi
  done
  # ★folio-* meta の総数 pin: 上の per-meta chk は「知っている 4 本」しか見ないため、 CORE 3 本の喪失や
  #   未知 meta の捏造混入を数で挟む (canonical 実測 = 7 本 = CORE 3 + pack 4)。
  chk "folio-* head meta 総数 == 7 (CORE 3 + pack 4)" "7" \
    "$(grep -o '<meta name="folio-[^"]*"' "$HTML" | wc -l | tr -d ' ')"
}
verify_pack_head_meta

# 2. id 一意性 + doc_type
chk_empty "要件 id 一意"     "$(q '.requirements[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "section id 一意"  "$(q '.sections[].id' | sort | uniq -d | tr '\n' ' ')"
chk "doc_type == spec"       "spec" "$(q '.meta.doc_type')"
# ★★M3 (folio-cuom): doc_id literal guard = qojv 決定 2 の「verify literal」の本 script 側実体。
#   doc_type == spec は ★5 契約 (rules / relations / verification / srs-verification / 本 self-spec) が共有し
#   ★識別力ゼロ — 上の doc_type chk だけでは「他 pack の contract を本 floor へ食わせる」誤用を 1 つも止められない。
#   本 script の期待値群 (FZC_* / 静的見出し / 照会種別 / subhead anchor 比) は全て self-spec 実測ゆえ、 他契約を
#   食うと ★別 doc に対して self-spec の期待を当てる ことになり、 FAIL の意味が読めなくなる (or 偶然緑になる)。
#   ★assemble-self-spec.sh の入口にも ★対の guard が 1 本ある (両端で閉じる)。
chk "doc_id == FOLIO-SELF-SPEC (pack identity literal guard)" "FOLIO-SELF-SPEC" "$(q '.meta.doc_id')"

# 3. section fidelity: 可視 heading 列 == sections[].heading + 静的 band 2 件 (順序) / essence 列 == sections[].essence (順序)。
# ★ADR-0054 lockstep: 旧版は head -n NSEC で ★先頭 NSEC 個しか見ておらず、 末尾 2 band の h2 (references / glossary band)
#   を取りこぼし・総 h2 件数 pin も無かったため、 band h2 の任意書換え + NSEC 超位置への新規 h2 無制限注入が素通った。
#   静的 band h2 は「§N. <本文>」形になり §N は ★contract 見出しから導出する (旧 literal
#   「verification は照会の終端ではない — 原則 (constitution) や決定記録 (ADR) へ前方照会する」は §番号を持たない旧形)。
STATIC_BAND_H2=("${STATIC_HEADINGS[@]}")
exp_sh="$( { q '.sections[].heading'; printf '%s\n' "${STATIC_BAND_H2[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_sh="$(grep -oE '<h2>[^<]*</h2>' "$BODY" | sed -E 's#<h2>([^<]*)</h2>#\1#')"
chk "section 可視 heading 列 == sections[].heading + 静的 band 2 件 (順序)" "$exp_sh" "$act_sh"
chk "h2 総数 == NSEC+2 (band h2 切詰・大文字注入の盲点是正)" "$((NSEC+2))" "$(grep -oiE '<h2\b' "$BODY" | wc -l | tr -d ' ')"
# ★章帯の巨大番号 == 見出しの節番号 (ADR-0054 §2.2)。 core band() は連番 (01..09) を emit するが、 pack-local
#   wrapper が §番号へ書き換える。 旧版は .num を ★一切 pin していなかったため番号体系の drift が全 gate を素通った。
# ★期待列は hardcode の連番でなく ★見出し自身から導出 した SEC_NUMS + STATIC_NUMS。 これにより「.num と h2 の §N が
#   食い違う」不整合が ★両側 hardcode の同意 に依らず構造的に落ちる。
chk "band .num 列 == 見出しの節番号 (heading 由来・連番でない・ADR-0054 §2.2)" \
  "$(printf '%s\n' "$SEC_NUMS"; printf '%s\n' "${STATIC_NUMS[@]}")" \
  "$(grep -oE '<span class="num">[^<]*</span>' "$BODY" | sed -E 's#<span class="num">([^<]*)</span>#\1#')"
# ★rich 契約値 (folio-aduv): essence は inline HTML (a.xref / span.term / <code> …) を逐語で持ち assembler が RAW emit する。
#   ゆえ期待側は esc せず *契約値そのもの*、 実測側は ([^<]*) でなく (.*?) + 固有終端で取る。
#   ★検出力は落ちない: 期待 == 実測の逐字一致は不変で、 escape 由来の化け・脱落・改竄はそのまま diff に出る
#   (esc したままだと raw emit と永久に不一致 = gate が意味を失う。 assert を緩めるのでなく *正しい期待値へ* 移す)。
exp_se="$(q '.sections[].essence')"
act_se="$(perl -CSD -0777 -ne 'while (/<div data-component="section-essence-callout"><p class="sec-se">(.*?)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
chk "section essence 列 == sections[].essence (順序・rich raw)" "$exp_se" "$act_se"
# ★契約非依存 pin (folio-cuom errata-1 M2): ★非空 の .sec-se を持つ章の数を数値 hardcode で撃つ。
#   ★動機: 上の逐値突合は ★contract 相対 ゆえ、 contract 側で section essence を machine_blocks へ ★demote すると
#   「契約も生成物も人間層に essence を持たない」で ★両側同時に痩せて PASS する (実測で floor / oracle とも全緑だった
#   = 独立 ceiling blocking M2)。 oracle 側の層帰属 arm と ★二重化 して floor 単独でも demote を捕捉する。
#   ★subhead 側の同型 pin (FZC_SUBHEAD_SE) と対 — 章レベルが無防備だった非対称の是正。
chk "census: 非空の section 1 行要約 == $FZC_SECTION_SE (章 essence の機械層 demote 封鎖・契約非依存 floor)" "$FZC_SECTION_SE" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="section-essence-callout"><p class="sec-se">(.*?)<\/p><\/div>/gs){ my $t=$1; $t=~s/<[^>]*>//g; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY")"
# ★kicker 列 fidelity (folio-l93): band() が可視 emit する <span class="kicker"> の §N/トピック ラベルは
#   sections[].kicker 由来の *決定的フィールド* ゆえ doctrine 上 floor (heading/essence と同列の section fidelity)。
#   未突合だと §番号 swap・トピック取り違え・heading の §N との drift が全 gate (floor/persona-walk/fidelity) を素通った (17n ceiling HIGH)。
#   全 NSEC+2 band の kicker を document 順で突合: 先頭 NSEC = sections[].kicker / 末尾 2 = references・glossary band の
#   静的リテラル (assemble-spec.sh build() と二重保守 = detect↔remediate parity)。 静的 2 件も期待列へ含め band 並び替え・
#   静的ラベル drift も lock する (heading は head -n NSEC で section のみだが kicker は全 band を被覆)。
#   抽出: <span class="kicker"><svg ...>…</svg> {esc kicker}</span> の svg 後の可視テキスト ([^<]* = esc 済ゆえ安全)。
STATIC_KICKERS=("この仕様が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
exp_kicker="$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_kicker="$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "section kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" "$exp_kicker" "$act_kicker"
# ★top-level section anchor 列 (folio-aduv 0-a)。 要件 anchor (tuple 同梱) / subhead anchor (SUBHEAD_RE) と並ぶ
#   ★3 クラス目の navigable id で、 ここだけ未配線だと非対称な穴になる (mutation-kill 実弾で確認: assembler の
#   章 anchor emit 行を落とすと生成物の section id が 7→0 本へ消え corpus inbound (#s1-contract 等) が
#   解決不能になるのに、 本 script の FAIL 件数は baseline と完全一致 = vacuous PASS だった)。
#   assembler 側の `[[ -n "$anchor" ]] || exit 1` は *契約値が空* の場合しか守らず emit 自体の脱落は守らない。
#   ★selector は emit_section の ★章包み <section id="…"> 形に固定する (旧 <span data-component="spec-section-anchor">
#   sibling 形からの追随)。 span 形は bin/folio の folio_chrome_toc_rows から ★不可視で章 TOC を全喪失させたため
#   canonical と同形の <section> 包みへ是正した (assemble-self-spec.sh emit_section の注記に機序と実測)。
#   band が開く <section data-component="chapter-deck-band"> は id を持たないので本 selector には掛からない。
# ★ADR-0054 lockstep: 前方照会 / 用語集を section id 付きの章で包む決定 (admin 裁定 C2) により、 生成物の
#   <section id> 列は「contract sections[].anchor + ★末尾固定 2 wrapper」になる。 wrapper id は番号なし canonical token。
# ★selector は ★厳格形 `<section id="…">` (属性追加を許さない) で固定する — 範型 verify-relations.sh:197 /
#   verify-spec.sh:212 は `[^>]*` 緩和形だが、 両者は直後に「section の class 値列 == contract sections[].class」の
#   ★対の arm を必ず持ち (relations/rules の canonical は実際に class="normative|informative" を持つ)、 緩和は
#   その対 arm が属性中身を pin することで補償されている。 verification contract は section class key を持たず
#   対の arm が存在しない ため、 緩和だけを写すと ★補償無しの teeth 削除 になる (実弾で確認: contract 章へ
#   `class="normative"` / `data-audience="machine" hidden` を注入しても全 gate 緑 = 1 章まるごと人間層から
#   消す content-suppression が素通る)。 assemble-self-spec.sh は emit_section / wrapper とも属性無しの
#   `<section id="…">` しか emit しない ので厳格形で無改竄 canonical は PASS する (:238 の wrapper 陽性 assert が
#   既に同じ厳格形を要求している = 二重保守の平仄)。 per-shape MK は test-adversarial-verification.sh PR3c。
chk "section anchor 列 == sections[].anchor + 提示層 wrapper 2 件 (順序)" \
  "$( { q '.sections[].anchor'; printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<section id="([^"]*)">/g){ print "$1\n"; }' "$BODY")"
# ★提示層 wrapper (ADR-0054 §2.2 の章化) の陽性 assert 2 本 — (a) 実在すること (章化が落ちれば section anchor 列も
#   FAIL するが、 census の id allowlist 除外が ★空振りしていない ことをここでも独立に固定する)、 (b) class を
#   ★持たないこと (verification contract は section class key を持たないため normative/informative census 自体が
#   無いが、 class 付与は census/構造の別クラス退行ゆえ ★形として封鎖する)。 assemble-self-spec.sh と二重保守。
for _w in "${PRESENTATION_WRAPPER_IDS[@]}"; do
  chk "提示層 wrapper <section id=\"$_w\"> が class 無しで実在 (章化 + census 非侵食)" "1" \
    "$(grep -oE "<section id=\"$_w\">" "$BODY" | wc -l | tr -d ' ')"
done
# ★★章 (契約章 + 提示層 wrapper) の ★containment (章化の ★実質) — 上の陽性 assert (a)(b) と section anchor 列は
#   ★開きタグの実在 しか見ない。 ゆえに <section id="forward-refs"></section> と即閉じ、 band / chapbody /
#   ref-grid を章の ★外 へ押し出す ★hollow section 改竄が ★タグ均衡を保ったまま 全 gate を素通る
#   (実弾再現: 開きタグ即閉じ + 対応閉じタグ削除で rc=0 / 0 FAIL)。 章化 (ADR-0054 §2.2) が約束するのは
#   「id を持つ section が在ること」ではなく「その章の中身が ★その章に属すること」ゆえ、 帰属を ★入れ子 で pin する。
#   (i) ★開口隣接 pin — 章の開きタグの ★直後 (間に ★異物なし) が「その章の band」(§番号 逐値 + wrapper は tint 逐値)。
#   (ii) ★region 占有 pin — 章の対応閉じタグまでの region で band == 1 / chapbody == 1 (欠落・重複・他章の紛れ込み)。
#   (iii) ★1 段内側の再帰 — wrapper では さらに chapbody 開口直後が payload container (ref-grid /
#         glossary-term-table) であること、 container が chapbody 内に 1 個、 payload (chip / .grow) の
#         ★全数 が ★container の中 に在ること。 (i)(ii) だけだと「chapbody を空で閉じ payload を sibling へ出す」
#         「container を即閉じし payload を外へ出す」 hollow 化が 1 段 / 2 段 内側で ★そのまま再演する
#         (B3 の defect 原理「開きタグが在る は 中身がそこに属する を意味しない」は ★階層ごとに 撃つ必要がある)。
#   ★期待値は contract 由来 (|references| / |glossary| / sections[].anchor / 見出し由来 §番号) ゆえ、 生成物実測への
#   after-the-fact 合わせ (恒真化) にならない。 ★契約章 7 本にも同じ (i)(ii) を課す (2 id の手書き列挙に留めると
#   同一 DOM shape を持つ残り 7 章が無防備 = partial-enumeration trap。 駆動は contract の section census)。
# ★per-shape mutation-kill (test-adversarial-verification.sh・★全 arm が 1 つ以上の実弾で anchor される):
#   PR3d hollow wrapper / PR3e chapbody だけの押し出し (band 隣接は保持 = 開口隣接 pin は PASS のまま region 側だけ
#   発火) / PR3f 用語集 wrapper の hollow 化 (payload 別構造クラス) / PR3g band tint の逐値付け替え (開口隣接 pin の
#   ★識別成分 = tint を単独で撃つ) / PR3h 開口への異物挿入 (同 pin の ★位置成分) / PR3i over-containment (wrapper の
#   入れ子化 = region 占有の ★上限側) / PR3j 契約章の hollow 化 (2 id 列挙では届かない残り 7 章) / PR3k chapbody 空化 +
#   payload を sibling へ (1 段内側の帰属) / PR3l chapbody 開口への異物挿入 / PR3m hollow ref-grid / PR3n hollow
#   glossary-term-table (payload 2 クラスを ★別実弾 で撃つ) / PR3t bogus comment / PR3u escapable RAWTEXT /
#   PR3v ハイフン要素名 / PR3w 契約章 band tint 付け替え / PR3x payload container の重複 / PR3o コメント密輸 /
#   PR3p script 密輸 / PR3q 属性値内 生 `>` 密輸 / PR3y comment end bang (`--!>`) / PR3z abrupt-closing comment
#   (`<!-->`) / PR4a RAWTEXT 終了タグの要素名境界 (`</textareax>`) / PR4b foreign content (svg subtree) /
#   PR4c 契約章の chapbody 空化 + 章本文 sibling 押し出し / PR4d 章要旨を残した章本文の relocation
#   (★block 粒度・章直下 2 子の構造 pin) / PR4e `<!--->` (comment 終端分岐 2 の単独 teeth) /
#   PR4f 章本文の ★band subtree への退避 (kids を 2 に保つ向き) / PR4g 章本文の ★別章 chapbody への移送 /
#   PR4h 章本文の ★machine-fold 内への退避 (後 2 者は ★document 順を保ち 他の probe 値を一切動かさない形) /
#   PR11c 優先度バッジの空化 / PR11d 大文字 <H2> の注入
#   — parser-differential 系は ★合計 7 vector で、 ★いずれも 封鎖 ★前 は rc=0 / 0 FAIL で素通った 実測 shape。
# ★★「全 arm が実弾で anchor される」の ★射程 (宣言 == 実能力): 上の主張が掛かるのは ★生成物 (artifact) の
#   改竄で落ちる arm だけ である。 ★検査機構そのものの健全性 arm — 「駆動表が全章を覆う」「probe が全章分の
#   実測を出力」 — は artifact をどう改竄しても落ちず (script 改変でしか落ちない)、 敵対 suite の構造上
#   per-shape MK を持てない。 これらは test-adversarial-verification.sh の ★MECHPIN 節 (tracked 静的 pin・
#   MINFORM / SETCDATA と同型) が arm の実在と期待値の導出形を押さえる = ★MK 対象外だが担保はリポに残る。
#   (worker の self-test は untracked ゆえ land 後に残らない — 担保先を ★committed 側 に置くのが要件。)
#
# ★★実態開示 (scope・c5r.2 回避表記封鎖の規律): 本 containment pin は ★verification arm 限定 である。 同一の
#   提示層 wrapper shape を持つ ★sibling floor = verify-spec.sh (rules) / verify-relations.sh (relations) は
#   wrapper assert が「<section id="forward-refs"> が class 無しで実在」の 1 本だけ で containment を持たず、
#   両者とも CI 配線済 (ci.yml) ながら ★同クラスの hollow wrapper 改竄に対し現状 fail-open のままである。
#   本 cell の scope fence (他 pack の verify-*/assemble-* 不触) ゆえ ★横展開は follow-up (別 issue) で行う
#   — 「ADR-0054 章化は 3 arm 全てで守られている」と読んではならない (宣言能力 == 実能力)。
#   ★trace 先を持たない「後でやる」で終わらせない (片 arm ドリフトの実発クラス = folio-7st6 → folio-gt4s と同型)。
#   ★受け皿 = folio-3zr4 (admin 起票済) — rules / relations への横展開 (提示層 wrapper containment +
#   本 cell で確立した ★3 レベル完全子数束縛 kids / bkids / cbkids) は当該 issue が担う。
#   ★本 cell の worker は bd create 権限を持たない (scribe protocol §3 = graph は admin 所有) ため、 起票自体は
#   admin が行った (worker からの申送りの durable な所在 = bd folio-9m1h notes の DONE 報告)。
#
# ★★parser-differential 封鎖 (r8k / folio-wq4 の再発クラス): region 切り出しを $BODY の ★生テキストへの
#   素朴な /<(\/?)section\b[^>]*>/ 走査で行ってはならない。 make_body は ★コメント本文と <script> 中身を
#   verbatim 保持する (lib/verify-common.sh) ため、 コメント内 / script 内に書いた `<section>` 文字列が
#   ★実要素として深さに加算され、 region が対応閉じタグを越えて ★over-slice する。 また `[^>]*` は引用符を
#   認識しないため、 属性値内の生 `>` (`<p title="x><section>y">`) でも同じ over-slice が起きる。
#   ★いずれも実弾で「章本文を章の外へ出したまま rc=0 / 0 FAIL」を再現した shape ゆえ、 走査は ★HTML5 の
#   tokenizer 規則に ★寄せた 走査で行う: コメント終端は HTML5 comment state と同型 (abrupt close / `<!--->` /
#   `-->` と `--!>` の早い方)、 bogus comment / markup declaration は `>` まで無視、 RAWTEXT と escapable
#   RAWTEXT (10 要素) の中身は ★タグとして数えず 終了タグは ★要素名境界 を課す、 foreign content (svg / math)
#   の subtree は ★丸ごと読み飛ばす (中は HTML 名前空間でない)、 タグ境界は ★引用符を認識して 決定し、
#   要素名は ★ハイフン込みで 1 語 として取る。 占有数も 生テキスト grep でなく ★tokenize 済タグの属性 逐値一致
#   で数える (属性値に marker 文字列を紛れ込ませた計数水増しを構成的に封じる)。
#   ★★宣言の射程 (== 実能力): これは「HTML5 parser の ★完全実装」ではない — 本 tokenizer が同型化しているのは
#   ★region 切り出しに効く状態 (上記) に限られ、 挿入位置補正 (in-body insertion mode の implied end tag /
#   foster parenting 等) や文字参照の解決は ★モデルしていない。 それらに依存する差分が将来見つかりうる前提で、
#   genuine assembler が emit しない shape (未閉じ / div・section の自己閉じ構文) は ★err で拒否する
#   fail-closed を併用する (arms race を全面 parser 実装へ広げず、 ★穴が開いたら loud に落ちる 側へ倒す)。
#   ★到達不能な残差の開示: foreign subtree の走査 (`<(/?)svg…>` の正規表現) は ★引用符を認識しない が、
#   属性値内に生 `<` を置く shape は ★上流の make_body が fail-closed で拒否する (raw-lt-in-tag) ため
#   本走査には到達しない (独立 verifier 実測)。 ここは「認識しているから安全」ではなく「上流で落ちるから
#   到達しない」であり、 make_body の当該 guard を緩めると ★本走査の前提が崩れる (依存の所在を明示する)。
# ★★lockstep 相手の開示 (二重保守の所在): 本 pin が依存する DOM marker のうち
#   `data-component="chapter-deck-band"` / `<span class="num">` / `<div class="chapbody">` は ★共有 CORE
#   lib/common.sh の band() / band_end() が emit する形であり、 pack-local な assemble-self-spec.sh ではない。
#   ★CORE 側でこれらの marker 名が変わると本 pin は (tokenizer が属性一致で数えるため) ★静かに 0 件になり得る
#   — その退行は「駆動表が全章を覆う」「probe が全章分を出力」の 2 arm では捕まらず、 章ごとの adj/band/cb が
#   同時に 0 へ落ちる形で ★loud に FAIL する (16 pack 共有ゆえ CORE 改変は本 cell scope 外 = 検出できれば足りる)。
#   属性値そのもの (tint-<値> / §番号) の lockstep 源は contract (sections[].tint / 見出し §N) と
#   PRESENTATION_WRAPPER_BAND_TINTS。
# ---- containment probe: $BODY を 1 度だけ tokenize し、 章ごとの containment 実測値を KV で返す ----
#   入力 PROBE_SPEC = 1 行 1 章の TSV: id \t §num \t tint(空=不問) \t container 属性 \t 値 \t payload 属性 \t 値
#   出力 = "<id>|<key>=<値>" 行 (found/adj/band/cb/cbadj/cont/pay) + "*|err=<tokenizer 診断>"。
#   ★fail-closed: tokenizer が非 genuine 構造 (未閉じタグ / 未閉じコメント / 未閉じ RAWTEXT / div・section の
#   自己閉じ構文) を見たら token 列を捨てる → 全章 found=0 となり下の chk が総崩れ FAIL する (診断は err arm が出す)。
containment_probe() { # stdin なし・env PROBE_SPEC / 引数なし
  perl -CSD -0777 -ne '
    my $b = $_; my $n = length($b); my $i = 0; my $err = ""; my @t = ();
    # ★RAWTEXT / escapable RAWTEXT (HTML5): これらの中身は ★テキスト であり、 中の <section> 等は要素にならない。
    #   script / style だけを知っていると title / textarea 等へ入れた擬似タグが ★実タグとして深さに乗り (parser-
    #   differential)、 region が over-slice して containment pin が fail-open する。 実測: genuine BODY に在るのは
    #   script 4 / style 1 / title 1 のみ (textarea・xmp・iframe・noembed・noframes・noscript・plaintext は 0 件)
    #   ★宣言の射程: plaintext は HTML5 では「以降すべてテキスト」で ★終了タグを持たない 特殊要素であり、
    #   本実装の「`</name>` まで読み飛ばす」処理とは厳密には別である (終端が来なければ err = fail-closed 側へ
    #   倒れる)。 「全 RAWTEXT 系で差が構成的に生じない」とは言えないため、 ここに ★実態を開示して 装わない。
    #   ゆえ、 現れない要素も ★実 parser と同じ挙動 (中身をテキストとして読み飛ばす) で扱えば、 攻撃者がそれらを
    #   注入しても tokenizer と実 DOM の差が ★構成的に生じない (「現れないから拒否」より広く閉じる)。
    my %RAWTEXT = map { $_ => 1 } qw(script style title textarea xmp iframe noembed noframes noscript plaintext);
    while ($i < $n) {
      my $lt = index($b, "<", $i); last if $lt < 0;
      # ★comment の終端は HTML5 の comment state と ★同型 に取る (`-->` 一本終端は非同型)。 実 parser が
      #   ★早く 終端する形を知らないと、 攻撃者は「実 DOM では章の外に在る閉じタグ」を tokenizer にだけ
      #   comment の中身として隠せる (実弾 verified: `<!--x--!></section><!--y-->` / `<!--></section><!--y-->`
      #   で用語集本文を章の外へ出したまま rc=0 / 0 FAIL)。 3 分岐:
      #   (1) `<!-->` = abrupt-closing (直後が `>`) (2) `<!--->` = 直後が `->` (3) 以降は `-->` と `--!>`
      #   (comment end bang) の ★早い方。 未終端は err (fail-closed・現行どおり)。
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
      #   深さに乗り region が over-slice する (実弾で verified: `<! <section> >` + `<! </section> >` の 2 本で
      #   用語集本文を章の外へ出したまま rc=0 / 0 FAIL = B3 がそのまま再現した)。 genuine BODY にも `<!DOCTYPE html>`
      #   が 1 件実在するため ★err で拒否せず 実 parser と同じ「`>` まで無視」へ寄せる (拒否だと genuine が総崩れする)。
      #   ★未終端 (`>` が来ない) は literal 残置でなく err = fail-closed (下の全 chk が総崩れ FAIL する)。
      if ($win !~ m{^<(?:/?)[a-zA-Z]} && ($win =~ m{^<[!?]} || $win =~ m{^</})) {
        my $e = index($b, ">", $lt + 1);
        if ($e < 0) { $err = "unclosed-bogus-comment"; last }
        $i = $e + 1; next;
      }
      # ★要素名は HTML5 のカスタム要素 (ハイフン入り) を ★1 語として取る。 `[a-zA-Z0-9]*` で切ると `<section-foo>` の
      #   要素名を "section" と誤認し、 実 DOM では別要素のものを ★章の深さに数える (over-slice の 3 本目の vector)。
      if ($win =~ m{^<(/?)([a-zA-Z][a-zA-Z0-9-]*)}) {
        my $cl = $1; my $nm = lc $2;
        my $j = $lt + 1 + length($cl) + length($2); my $qc = ""; my $gt = -1;
        while ($j < $n) {
          my $c = substr($b, $j, 1);
          if ($qc ne "") { $qc = "" if $c eq $qc }
          elsif ($c eq q{"} || $c eq "\x27") { $qc = $c }
          elsif ($c eq ">") { $gt = $j; last }
          $j++;
        }
        if ($gt < 0) { $err = "unclosed-tag-$nm"; last }
        # ★$raw は ★この位置で宣言する — 下の foreign content 分岐 (:自己閉じ高速路) と self-closing 拒否の
        #   ★両方が読む。 旧版は宣言が foreign 分岐より ★後 にあり、 分岐側は未定義の package 変数を読んで
        #   恒偽 = 死コード だった (実挙動は 自己閉じ svg → unclosed-foreign err の fail-closed 側へ落ちており
        #   genuine には 0 件ゆえ穴ではなかったが、 ★コメントの主張と実挙動が食い違う 状態だった)。
        my $raw = substr($b, $lt, $gt + 1 - $lt);
        # ★foreign content (svg / math): 中の要素は ★HTML 名前空間の要素ではない ので章の深さに数えてはならない。
        #   genuine 生成物には svg アイコンが多数実在するため、 subtree を ★実 parser と同型に 読み飛ばす
        #   (実弾 verified: `<svg><section></svg>` で region を伸ばし章本文を章の外へ出したまま rc=0 / 0 FAIL)。
        #   ★foreign content では `/>` の自己閉じが ★効く (HTML 名前空間と逆) ので、 自己閉じは深さに加算しない。
        #   subtree が閉じない場合は err (fail-closed)。
        if (!$cl && ($nm eq "svg" || $nm eq "math")) {
          if ($raw =~ m{/>$}) { $i = $gt + 1; next }
          my $d2 = 1; my $rest2 = substr($b, $gt + 1); my $off = -1;
          while ($rest2 =~ m{<(/?)\Q$nm\E(?=[\t\n\f\r />])[^>]*>}gi) {
            my $hit = $&;
            if ($1 eq "/") { $d2-- } elsif ($hit !~ m{/>$}) { $d2++ }
            if ($d2 == 0) { $off = pos($rest2); last }
          }
          if ($off < 0) { $err = "unclosed-foreign-$nm"; last }
          $i = $gt + 1 + $off; next;
        }
        # ★RAWTEXT の終了タグは ★要素名の境界 を課す (実 parser の appropriate end tag 判定と同型)。
        #   `</\Q$nm\E[^>]*>` は `</textareax>` にも一致して ★早期終了 し、 以降の擬似タグを実タグとして
        #   数えてしまう (実弾 verified: `<textarea></textareax><section><textarea></textarea>` で region を
        #   伸ばし章本文を章の外へ出したまま rc=0 / 0 FAIL)。 名前の直後は空白 / `/` / `>` のみ許す。
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
    @t = () if $err ne "";
    my $attr = sub {   # tokenize 済タグ raw から属性値 (最初の 1 個・HTML5 の duplicate 規則) を引く
      my ($raw, $k) = @_;
      my $s = $raw; $s =~ s{^</?[a-zA-Z][a-zA-Z0-9]*}{}; $s =~ s{/?>$}{};
      while ($s =~ /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s"\x27=<>`]+))/g) {
        my $ak = lc $1; my $av = defined $2 ? $2 : (defined $3 ? $3 : $4);
        return $av if $ak eq $k;
      }
      return undef;
    };
    my $match = sub {  # 開きタグ かつ 要素名一致 かつ (属性 k の値 == v)
      my ($x, $nm, $k, $v) = @_;
      return 0 if $x < 0 || $x > $#t || $t[$x]{cl} || $t[$x]{nm} ne $nm;
      return 1 if !defined $k || $k eq "";
      my $a = $attr->($t[$x]{raw}, $k);
      return (defined $a && $a eq $v) ? 1 : 0;
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
    for my $line (split /\n/, ($ENV{PROBE_SPEC} // "")) {
      next unless length $line;
      my @f = split /\t/, $line, -1;
      my $id = $f[0]; my $num = $f[1] // ""; my $tint = $f[2] // "";
      my $ca = $f[3] // ""; my $cv = $f[4] // ""; my $pa = $f[5] // ""; my $pv = $f[6] // "";
      my $found = 0; my $wk = -1;
      for (my $x = 0; $x <= $#t; $x++) { if ($match->($x, "section", "id", $id)) { $found++; $wk = $x if $found == 1 } }
      my ($adj, $band, $cb, $cbadj, $cont, $pay, $kids, $bkids, $cbkids) = (0, 0, 0, 0, 0, 0, 0, 0, 0);
      if ($found == 1) {
        my ($r0, $r1) = $region->($wk);
        if ($r0 >= 0 && $r0 <= $r1) {
          $band = $count->($r0, $r1, "section", "data-component", "chapter-deck-band");
          $cb   = $count->($r0, $r1, "div", "class", "chapbody");
          # ★kids = 章 region 内の ★深さ 1 の子要素数。 assembler の構造規約では章の直下は
          #   「章帯 band」+「chapbody」の ★2 子だけ ゆえ、 章本文 (subhead / 地の文 / details / table …) を
          #   ★一部でも全部でも chapbody の外 (章直下の sibling) へ出すと 3 子以上になる = その向きは捕捉できる
          #   (★band subtree への退避は bkids・★別章移送 / fold 退避は cbkids の担当 — ★3 レベルで 1 組)
          #   (件数 pin を部品種別ごとに置く形は 0 件の章で 0/0 恒真になり、 かつ地の文のように marker を
          #   持たない本文を覆えない)。 対応閉じが region 内に無ければそこで打ち切る (fail-closed 方向)。
          my $count_kids = sub {   # region (lo..hi) の ★深さ 1 の子要素数
            my ($lo, $hi) = @_; my $c = 0; return 0 if $lo < 0;
            my $x = $lo;
            while ($x >= 0 && $x <= $hi) {
              if ($t[$x]{cl}) { $x++; next }
              $c++;
              my $nm2 = $t[$x]{nm}; my $d3 = 1; my $y = $x + 1;
              while ($y <= $hi && $d3 > 0) { if ($t[$y]{nm} eq $nm2) { $d3 += $t[$y]{cl} ? -1 : 1 } $y++ }
              $x = ($d3 == 0) ? $y : $hi + 1;
            }
            return $c;
          };
          $kids = $count_kids->($r0, $r1);
          # ★bkids = ★章帯 (band) region 内の深さ 1 の子要素数。 kids pin だけでは relocation クラスが
          #   ★片方向 にしか閉じない — 押し出し先を sibling でなく ★band の中 にすると章直下は
          #   band + chapbody のままで kids=2 を保ち素通る (実弾 verified: rc=0 / 0 FAIL)。
          #   共有 CORE lib/common.sh の band() は span.num / span.kicker / h2 / p.lead の ★4 子固定 ゆえ、
          #   band 内へ何かを退避すれば 5 子以上になる (期待値は clean 9 章すべてで実測 4)。
          my $bk = $first->($r0, $r1, "section", "data-component", "chapter-deck-band");
          if ($bk >= 0) { my ($b0, $b1) = $region->($bk); $bkids = $count_kids->($b0, $b1) }
          # ★cbkids = ★chapbody region 内の深さ 1 の子要素数。 章直下 (kids) と band 直下 (bkids) を固定しても
          #   ★document 順を保つ relocation は残る — 章本文を (β) ★別章の chapbody へ移送 する / (γ) ★同章の
          #   machine-fold (details) の中へ退避 する と、 両者とも probe の他の値を ★一切動かさず に素通った
          #   (実弾 verified: rc=0 / 0 FAIL)。 chapbody の ★直下の子数 を contract 由来の完全数で束縛すると、
          #   β は donor 側の減少で・γ は fold へ吸い込まれた分の減少で捕まる (受け側の増加も対で捕捉)。
          my $cbk2 = $first->($r0, $r1, "div", "class", "chapbody");
          if ($cbk2 >= 0) { my ($q0, $q1) = $region->($cbk2); $cbkids = $count_kids->($q0, $q1) }
          # (i) 開口隣接: 直後 token が この章の band (tint 逐値・間の text は空白のみ) で、 その中の
          #     <span class="num">§番号</span> が contract 由来の期待値と 逐値一致 すること。
          if ($match->($r0, "section", "data-component", "chapter-deck-band") && $gap_ws->($wk, $r0)
              && ($tint eq "" || do { my $c = $attr->($t[$r0]{raw}, "class"); defined $c && $c eq "tint-" . $tint })
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
      print "$id|found=$found\n$id|adj=$adj\n$id|band=$band\n$id|cb=$cb\n$id|cbadj=$cbadj\n$id|cont=$cont\n$id|pay=$pay\n$id|docct=$docct\n$id|kids=$kids\n$id|bkids=$bkids\n$id|cbkids=$cbkids\n";
    }
    print "*|err=$err\n";
  ' "$BODY"
}
# ★章 census (契約章 7 + 提示層 wrapper 2) を ★1 本の駆動表 にまとめる。 tint 逐値は ★全 9 章に課す —
#   契約章の tint 源は ★contract の sections[].tint (実測: info/brand/violet/info/warn/ok/brand が 7/7 実在し
#   band の class="tint-<値>" と 1:1 対応)、 提示層 wrapper の 2 章は assembler literal と二重保守の
#   PRESENTATION_WRAPPER_BAND_TINTS。 ★旧注記の「contract は section tint の key を持たない」は ★事実に反しており
#   (実測で反証)、 その誤認により契約章 7 本の band tint 付け替えが rc=0 / 0 FAIL で素通っていた — 持てる逐値を
#   放棄しない (per-shape MK = PR3w)。 1 段内側 (iii) は ★全 9 章が持つ — wrapper 2 章は payload container
#   (ref-grid / glossary-term-table) と payload 全数、 契約章 7 本は ★章要旨 callout (assembler が chapbody 開口
#   直後に必ず emit する部品) を器に取る。
# ★★chk は ★arm ごとに 1 行 (章ごとに別行へ展開しない): mutation-kill は「その chk 行を消すと敵対 suite が
#   赤くなるか」で測るので、 同じ検査を章別に複製すると per-shape MK が章の数だけ必要になり実効被覆が落ちる。
mapfile -t _SEC_ANCHORS < <(q '.sections[].anchor')
mapfile -t _SEC_NUMLIST < <(printf '%s\n' "$SEC_NUMS")
mapfile -t _SEC_TINTS < <(q '.sections[].tint')
# ★fail-closed: contract の tint が 1 つでも欠けたら「tint 不問」へ ★暗黙に degrade させない (欠落を静かに
#   許すと契約側の tint 削除で本 arm が恒真化する = 0/0 恒真 pin と同じ vacuous-green クラス)。
[[ "${#_SEC_TINTS[@]}" -eq "${#_SEC_ANCHORS[@]}" ]] || { echo "verify-self-spec: ★contract sections[].tint の件数が anchor と不一致 (${#_SEC_TINTS[@]} != ${#_SEC_ANCHORS[@]}・tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
_CT_ID=(); _CT_NUM=(); _CT_TINT=(); _CT_CA=(); _CT_CV=(); _CT_PA=(); _CT_PV=(); _CT_CLBL=(); _CT_PLBL=(); _CT_PEXP=(); _CT_CEXP=(); _CT_CBEXP=()
# ★契約章 7 本の 1 段内側 (iii) は ★章要旨 callout を器に取る。 assemble-self-spec.sh の emit_section が
#   chapbody 開口の ★直後に必ず 1 個 emit する部品ゆえ、 期待値 (隣接 1 / chapbody 内 1 個 / 文書総数 == NSEC) は
#   ★assembler と contract から決定的に導ける。 これが無いと契約章は「chapbody を空にして章本文を sibling へ
#   押し出す」改竄が 0 FAIL で素通り、 既存 arm の label「章本文の帰属・押し出し封鎖」が ★過大宣言 になる。
for _k in "${!_SEC_ANCHORS[@]}"; do
  [[ -n "${_SEC_TINTS[$_k]}" && "${_SEC_TINTS[$_k]}" != "null" ]] || { echo "verify-self-spec: ★contract sections[$_k].tint が空 (tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _CT_ID+=("$(esc "${_SEC_ANCHORS[$_k]}")"); _CT_NUM+=("${_SEC_NUMLIST[$_k]}"); _CT_TINT+=("${_SEC_TINTS[$_k]}")
  _CT_CA+=("data-component"); _CT_CV+=("section-essence-callout"); _CT_PA+=(""); _CT_PV+=("")
  _CT_CLBL+=("章要旨 callout"); _CT_PLBL+=(""); _CT_PEXP+=(""); _CT_CEXP+=("$NSEC")
  # ★chapbody 直下の ★完全子数 を contract から決定的に導く: 章要旨 callout 1 + blocks 各 1 +
  #   machine_blocks があれば fold 1。 ★marker を持たない地の文も contract 上は 1 block ゆえ 1 要素で数えられる。
  #   最小でも 2 (callout + fold) になり ★0/0 恒真にならない (実測 s0=2 / s1=5 / s2=4 / s3=21 / s4=7 / s5=7 / s6=2)。
  _nb="$(q ".sections[$_k].blocks // [] | length")"; _nm="$(q ".sections[$_k].machine_blocks // [] | length")"
  [[ "$_nb" =~ ^[0-9]+$ && "$_nm" =~ ^[0-9]+$ ]] || { echo "verify-self-spec: ★sections[$_k] の blocks / machine_blocks 件数を導出できない (cbkids 期待値の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _CT_CBEXP+=("$(( 1 + _nb + ( _nm > 0 ? 1 : 0 ) ))")
done
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[0]}")"); _CT_NUM+=("${STATIC_NUMS[0]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[0]}")
_CT_CA+=("class"); _CT_CV+=("ref-grid"); _CT_PA+=("data-component"); _CT_PV+=("cross-doc-ref-chip")
_CT_CLBL+=("ref-grid"); _CT_PLBL+=("前方照会 chip"); _CT_PEXP+=("$(q '.references | length')"); _CT_CEXP+=("1"); _CT_CBEXP+=("1")
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[1]}")"); _CT_NUM+=("${STATIC_NUMS[1]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[1]}")
_CT_CA+=("data-component"); _CT_CV+=("glossary-term-table"); _CT_PA+=("class"); _CT_PV+=("grow")
_CT_CLBL+=("glossary-term-table"); _CT_PLBL+=("用語集 行 (.grow)"); _CT_PEXP+=("$(q '.glossary | length')"); _CT_CEXP+=("1"); _CT_CBEXP+=("1")
_PROBE_SPEC=""
for _k in "${!_CT_ID[@]}"; do
  _PROBE_SPEC+="${_CT_ID[$_k]}"$'\t'"${_CT_NUM[$_k]}"$'\t'"${_CT_TINT[$_k]}"$'\t'"${_CT_CA[$_k]}"$'\t'"${_CT_CV[$_k]}"$'\t'"${_CT_PA[$_k]}"$'\t'"${_CT_PV[$_k]}"$'\n'
done
_CPROBE="$(PROBE_SPEC="$_PROBE_SPEC" containment_probe)"
_cp() { printf '%s\n' "$_CPROBE" | awk -F'|' -v i="$1" -v k="$2" '$1==i { p=index($2,"="); if (substr($2,1,p-1)==k) { print substr($2,p+1); exit } }'; }
# ★★駆動表の完全性 (partial-enumeration の封鎖): 章 census が ★全章 (contract sections + 提示層 wrapper) を
#   覆っていること・wrapper の id 配列と tint 配列が ★同じ長さ であることを ★機械で 固定する。 添字 [0]/[1] で
#   組み立てているため、 wrapper を 1 本増やして駆動表への追記を忘れると その章だけ containment が ★silent に
#   未検査 になる (「検査している」と読めるのに実際は素通り = vacuous-green クラス)。
[[ "${#PRESENTATION_WRAPPER_IDS[@]}" -eq "${#PRESENTATION_WRAPPER_BAND_TINTS[@]}" ]] \
  || { echo "verify-self-spec: ★PRESENTATION_WRAPPER_IDS と PRESENTATION_WRAPPER_BAND_TINTS の長さ不一致 (lockstep 破れ・fail-closed)" >&2; exit 1; }
chk "containment 駆動表が全章を覆う (contract sections + 提示層 wrapper・被覆漏れ封鎖)" \
  "$((NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}))" "${#_CT_ID[@]}"
# ★tokenizer の fail-closed 診断 (空でなければ 生成物が genuine な HTML 構造を破っている = 下の全 chk も総崩れする)。
#   per-shape MK は PR3r (div の自己閉じ構文)。
# ★★負の主張には ★存在 anchor を対で置く (ehar クラス): 本 arm は「err が空であること」を主張するが、 probe が
#   ★何も出力しない (関数改名 / 実行失敗 / PROBE_SPEC 空) 場合も空になり ★恒真 PASS する。 probe の出力行数を
#   ★章数から導出した期待値 で pin し、 「検査が走っていない」を「異常なし」と読まない。
chk "containment probe が全章分の実測を出力 (probe 無出力での vacuous PASS 封鎖)" \
  "$(( ${#_CT_ID[@]} * 11 + 1 ))" "$(printf '%s\n' "$_CPROBE" | grep -c .)"
chk "containment tokenizer の構造診断 (未閉じ / 自己閉じ div,section = 非 genuine shape)" "" "$(_cp '*' err)"
for _k in "${!_CT_ID[@]}"; do
  _s="${_CT_ID[$_k]}"; _tn=""; [[ -z "${_CT_TINT[$_k]}" ]] || _tn=" (tint-${_CT_TINT[$_k]})"
  chk "章 '$_s' の開口直後に §${_CT_NUM[$_k]} 章帯$_tn が隣接 (hollow section 封鎖・開口隣接 pin)" "1" "$(_cp "$_s" adj)"
  chk "章 '$_s' region 内の章帯 == 1 (欠落 / 他章 band の紛れ込み封鎖)" "1" "$(_cp "$_s" band)"
  chk "章 '$_s' region 内の chapbody == 1 (章本文の ★器 の帰属・欠落 / 重複封鎖)" "1" "$(_cp "$_s" cb)"
  # ★★3 レベルの ★完全子数束縛 (章直下 == 2 / band 直下 == 4 / chapbody 直下 == 契約由来の完全数) が
  #   封鎖するのは ★人間層 (chapbody 直下) の block 粒度 relocation クラス である — 人間層 block を
  #   どこへ動かしても (sibling へ / band の中へ / 別章の chapbody へ / 同章の fold の中へ) いずれかの
  #   レベルの子数が必ず変わるため。 ★この範囲では クラス閉塞が成立する (3 レベル pin + 既存の順序 arm の
  #   合わせ技として独立 verifier が論理列挙 + 実測で確認済)。
  # ★★射程外 1 — ★機械層 (machine_blocks) の cross-fold 移動: machine_blocks を ★document 順を保ったまま
  #   ★別 section の machine-body へ移す形 (単一 block / 連続塊 とも) は ★未検査 である。 3 レベル pin は
  #   ★fold の内側へ届かず (chapbody 直下から見れば fold は 1 要素のまま)、 §11 round-trip も順序変化しか
  #   見ないため、 いずれも発火しない (pre-existing・独立 verifier が実測)。 ★受け皿 = folio-e706
  #   (machine-body 直下の子数 pin = ★4 レベル目 + fold summary 件数突合) — 新レベルの設計ゆえ本 cell では
  #   行わず follow-up へ移譲した (gt4s-census 先例)。
  # ★★射程外 2 — ★sub-block 粒度 (block の ★内部 のテキスト・要素の移動) も別クラス:
  #   機械層は §11 の逐語 round-trip、 人間層は prose slot 充填 + fidelity ceiling の領分である。
  #   「あらゆる relocation を閉じた」とは書かない (宣言 == 実能力)。
  # ★章本文そのものの帰属 (block 粒度 relocation の第 1 レベル): 章の直下は 章帯 + chapbody の ★2 子だけ ゆえ、 chapbody を
  #   残したまま本文 (subhead / 地の文 / details / table …) を ★章直下の sibling へ 出せば 3 子以上になる。
  #   ★部品種別ごとの件数 pin では覆えない — 0 件の章で 0/0 恒真になり、 かつ地の文のように marker を持たない
  #   本文を数えられないため (1 instance でなく shape クラスを閉じるにはこの構造規約が要る)。 per-shape MK = PR4d。
  chk "章 '$_s' の直下は 章帯 + chapbody の 2 子だけ (章本文の sibling への relocation 封鎖)" "2" "$(_cp "$_s" kids)"
  # ★3 レベル束縛の ★第 2 レベル: 押し出し先を sibling でなく ★章帯 (band) の中 にすると章直下は
  #   band + chapbody のままで kids=2 を保ち素通る (実弾 verified: rc=0 / 0 FAIL — 1 ブロック退避でも
  #   章本文まるごと退避でも probe 実測値が clean と区別不能だった)。 kids (第 1) / bkids (第 2) /
  #   cbkids (第 3) の ★3 レベルが揃って 初めて ★人間層 block の relocation クラスが閉じる
  #   (2 レベルでは別章移送・fold 退避が残る = R5-1 で実証)。 期待値 4 の源は ★共有 CORE lib/common.sh の band()
  #   = span.num / span.kicker / h2 / p.lead の 4 子固定 (clean 9 章すべてで実測 4)。 per-shape MK = PR4f。
  chk "章 '$_s' の章帯の直下は num/kicker/h2/lead の 4 子だけ (band subtree への退避封鎖)" "4" "$(_cp "$_s" bkids)"
  # ★3 レベル目 (document 順を ★保つ relocation の封鎖): 章直下 / band 直下 を固定しても、 章本文を
  #   ★別章の chapbody へ移送 (β) / ★同章の machine-fold の中へ退避 (γ) すると他の probe 値は一切動かない
  #   (実弾 verified: 2 形とも rc=0 / 0 FAIL)。 chapbody 直下の ★完全子数 を contract 由来で束縛して閉じる。
  #   per-shape MK = PR4g (β = 別章へ移送) / PR4h (γ = machine-fold へ退避)。
  chk "章 '$_s' の chapbody 直下は 契約由来の完全子数 ${_CT_CBEXP[$_k]} (別章移送 / fold 退避の封鎖)" "${_CT_CBEXP[$_k]}" "$(_cp "$_s" cbkids)"
  [[ -n "${_CT_CA[$_k]}" ]] || continue
  chk "章 '$_s' の chapbody 開口直後に ${_CT_CLBL[$_k]} が隣接 (1 段内側の開口隣接 pin)" "1" "$(_cp "$_s" cbadj)"
  chk "${_CT_CLBL[$_k]} が章 '$_s' の chapbody 内に 1 個 (器の外への押し出し封鎖)" "1" "$(_cp "$_s" cont)"
  chk "${_CT_CLBL[$_k]} が ★文書全体で ${_CT_CEXP[$_k]} 個 (器の重複 = payload / 章本文の逃げ場を消す)" "${_CT_CEXP[$_k]}" "$(_cp "$_s" docct)"
  [[ -n "${_CT_PA[$_k]}" ]] || continue
  chk "${_CT_PLBL[$_k]} の ★全数 が章 '$_s' の ${_CT_CLBL[$_k]} 内 (hollow container 封鎖・漏出 0)" "${_CT_PEXP[$_k]}" "$(_cp "$_s" pay)"
done

# 4. 要件 fidelity: data-req-id 集合一致 + emission 順タプル (id, pattern, class, label, essence, statement) 突合。
exp_rid="$(q '.requirements[].id' | sort -u)"
act_rid="$(grep -oE 'data-req-id="[^"]+"' "$BODY" | sed 's/.*data-req-id="//; s/"$//' | sort -u)"
set_eq "要件 data-req-id 集合 (contract == HTML)" "$exp_rid" "$act_rid"
# emission 順 = sections→blocks(requirements).ids の document 順。
EXPF="$(mktemp)"; ACTF="$(mktemp)"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  ess="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # ★anchor (folio-aduv) = 生成物 row の navigable id (小文字 req-ver-* / req-nav-*)。 tuple に *同梱* して
  #   「id= が data-req-id (大文字) の置換でなく追加である」ことを 1 本の突合で pin する (両方が同時に等しくなければ FAIL)。
  anc="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anc" && "$anc" != "null" ]] || { echo "verify-self-spec: ★contract 要件 $id の anchor が空 (navigable id 不在・fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; }
  # ★contract 由来 pattern が allowlist 外なら expected タプルを :-unknown で組まず fail-closed (assemble validate と parity)。
  # silent な class="unknown" 同士の偽一致 (双辺で同じ fallback を引いて tuple PASS する fail-open) を封鎖。
  if ! [[ -v EARS_CLASS[$pat] ]]; then echo "verify-self-spec: ★contract 要件 $id の EARS pattern が allowlist 外: $pat (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
  # ★ADR-0054 lockstep: RFC-2119 優先度バッジ class (rq-prio-<level>) + prio/plain の ★per-row slot-id を tuple へ同梱する。
  #   slot-id は要件 anchor から決定的に導く (prio-<anchor> / plain-<anchor>) ため、 ★別 row のバッジ / 平易行を
  #   持ってくる relocation クラス (件数保存) が tuple 突合で FAIL する = per-row 完全束縛。
  #   priority を持たない contract (all-or-none の「無い」側) では badge 自体が emit されないため期待も空にする。
  prio="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
  if [[ -n "$prio" && "$prio" != "null" ]]; then
    if ! [[ -v PRIO_LABEL_OK[$prio] ]]; then echo "verify-self-spec: ★contract 要件 $id の priority が allowlist 外: $prio (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
    prio_cell="rq-prio rq-prio-$prio\tprio-$(esc "$anc")"
  else
    prio_cell="-\t-"
  fi
  # ★essence / statement は rich 契約値ゆえ esc しない (assembler の RAW emit と対称)。 id/pat/label は esc 経路のまま。
  printf '%s\t%s\t%s\t%s\t%s\t%b\t%s\t%s\t%s\n' "$(esc "$anc")" "$(esc "$id")" "$(esc "$pat")" "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$prio_cell" "$ess" "plain-$(esc "$anc")" "$stmt"
done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]') > "$EXPF"
RQNS="$RQ_NORM_SUMMARY" RQPK="やさしく言うと" perl -CSD -0777 -ne '
  # ★perl -CSD は ★入力ストリームだけ を UTF-8 decode し %ENV / program text は ★byte のまま。 非 ASCII literal を
  #   regex へ直書きすると decode 済 subject と噛み合わず ★恒常 0-match (= tuple 実体が空 → 常時 FAIL) になる。
  #   env 経由で渡し decode_utf8 してから quotemeta する。
  use Encode qw(decode_utf8);
  # ★canonical dual-audience form (w1f cell-2): row opener に data-audience="human"、 rq-norm に data-audience="machine" を
  #   literal で要求し structured-regex に組み込む (= REQ-DA-STRUCT-1/-4 の構造 anchor を tuple 突合に同梱・属性 drop は row 脱落→件数 FAIL)。
  # ★folio-aduv: row opener に id="<小文字 navigable id>" を literal 要求 (anchor 脱落 = row 脱落 → 件数 FAIL = fail-closed)。
  #   essence / statement は rich raw ゆえ ([^<]*) から (.*?) + 固有終端へ (改行は跨がせない = inner_norm 単一行の暗黙 assert)。
  # ★ADR-0054: rq-prio バッジ (optional = priority 無し contract では不在) と rq-plain 行 (常在) を ★構造 anchor として
  #   regex へ組み込む。 平易行の ★中身 は prose slot ゆえ tuple では突合せず (mode 依存)、 ★slot-id の per-row 束縛のみ pin する。
  # ★rq-norm の summary は平易ラベルを literal 要求 (旧版は [^<]* の wildcard で ★無警備 だった)。
  my $S=quotemeta(decode_utf8($ENV{RQNS})); my $K=quotemeta(decode_utf8($ENV{RQPK}));
  while (/<div data-component="ears-requirement-row" id="([^"]*)" data-req-id="([^"]*)" data-ears-pattern="([^"]*)" data-audience="human">\s*<div class="rq-head"><span class="rid">([^<]*)<\/span>(?:<span class="([^"]*)" data-prose-slot="priority" data-slot-id="([^"]*)">[^<]*<\/span>)?<span data-component="ears-badge" class="([^"]*)">([^<]*)<\/span><\/div>\s*<p class="rq-essence">(.*?)<\/p>\s*<p class="rq-plain"><span class="rq-plain-k">$K<\/span><span data-prose-slot="plain" data-slot-id="([^"]*)">[^<]*<\/span><\/p>\s*<details class="rq-norm" data-audience="machine"><summary>$S<\/summary><p class="rq-stmt">(.*?)<\/p><\/details>/g) {
    my ($anc,$rid,$pat,$vrid,$pcls,$pslot,$cls,$lab,$ess,$plslot,$stmt)=($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);
    $pcls = defined($pcls) ? $pcls : "-"; $pslot = defined($pslot) ? $pslot : "-";
    # 可視 rid == data-req-id (attr-vs-visible)
    if ($rid ne $vrid) { print "VIS-MISMATCH:$rid\xe2\x89\xa0$vrid\n"; next; }
    print "$anc\t$rid\t$pat\t$cls\t$lab\t$pcls\t$pslot\t$ess\t$plslot\t$stmt\n";
  }
' "$BODY" > "$ACTF"
if diff -q "$EXPF" "$ACTF" >/dev/null 2>&1; then
  printf '  [OK]   %-'"$CHKW"'s %s\n' "要件タプル (id/pattern/class/label/essence/statement) 順序突合" "$NREQ"
else
  printf '  [FAIL] %-'"$CHKW"'s\n' "要件タプル不一致 (id/pattern/badge/essence/statement 改竄 or 順序)"
  echo "    --- contract 期待のみ ---"; comm -23 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  echo "    --- HTML 実体のみ ---";     comm -13 <(sort "$EXPF") <(sort "$ACTF") | sed 's/^/      /'
  fail=1
fi
rm -f "$EXPF" "$ACTF"

# 4b. ★★M5 (folio-cuom): base の「RFC-2119 優先度バッジ / 平易行 の per-row 束縛 + 契約非依存 census」群は
#     self-spec (要件 0 件) では ★全て 0/0 の恒真 PASS になる。 恒真 PASS を残すのは「検査している」の誤表示ゆえ、
#     ★削除でも黙認でもなく ★NREQ==0 を不変量として pin した negative assert へ ★置換 する。
#
#     ★negative assert が teeth を持つ理屈: 期待値を「生成物に 0 件」でなく「★contract の NREQ から導出した値」に
#     すること。 NREQ==0 の今日は 0 を要求し、 要件が 1 本でも入れば ★期待が自動で 1 以上へ動く ため、
#     「要件が入ったのに row/badge/平易行 が出ない」退行も同じ 1 本の chk が捕らえる (片側 hardcode でない)。
#     ★陽性対照 (contract へ要件を 1 本注入した fixture でこの群が FAIL すること) は
#     test-adversarial-self-spec.sh の REQ-POS 群が ★per-shape で撃つ (契約 M5 の「陽性対照」要求)。
#
#     ★対象 3 shape (base の 3 arm と 1:1 対応させる = 落とした arm を黙って消さない):
#       (a) ears-requirement-row / ears-badge      … 上の §1 で NREQ 相対に既に突合済 (0 == 0 では ★ない:
#                                                     NREQ から導出ゆえ要件注入で期待が動く)。ここでは shape の
#                                                     ★不在 を独立に撃つ (grep の空振りと区別するため陽性側も持つ)。
#       (b) rq-prio (優先度バッジ) / rq-plain (平易行) … 要件 row の内側にしか出ない部品。
#       (c) 要件 normative fold (rq-norm)              … 同上。
chk "M5(a): ears-requirement-row == NREQ (要件 0 の今日は不在・要件が入れば自動で期待が動く)" "$NREQ" \
  "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "M5(b): rq-prio 優先度バッジ == NREQ (0 件 pin・恒真でなく契約導出)" "$NREQ" \
  "$(grep -oE '<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">' "$BODY" | wc -l | tr -d ' ')"
chk "M5(b): rq-plain 平易行 == NREQ (0 件 pin・恒真でなく契約導出)" "$NREQ" \
  "$(grep -oE '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span>' "$BODY" | wc -l | tr -d ' ')"
chk "M5(c): 要件 normative fold (rq-norm) == NREQ (0 件 pin・恒真でなく契約導出)" "$NREQ" \
  "$(grep -c 'class="rq-norm" data-audience="machine"' "$BODY")"
# ★EARS pattern 属性の ★不在 も撃つ (要件 shape の残骸が別経路で出ていないか)。
chk "M5(a): data-ears-pattern 属性 == NREQ" "$NREQ" \
  "$(grep -o 'data-ears-pattern="' "$BODY" | wc -l | tr -d ' ')"
# ★references[].title (照会チップの一行タイトル) — 本 contract は title を持たない (上の FZC 注記参照)。
#   ★0/0 恒真にしないため期待値を ★contract の非空 title 件数から導出する (title を 1 件でも足せば期待が動く)。
# ★★M5 の「削除して非該当を明示する」側を採った arm の ★開示 (黙って落とすと「範型踏襲済」の誤報告になる):
#   base (verify-verification.sh) が持っていた
#     (a) 「rq-prio: (level, 可視ラベル∈allowlist) 列 == contract priority」
#     (b) 「rq-plain / rq-prio の per-row 非空 floor」
#     (c) 「契約内不変: priority == statement の RFC-2119 modal verb 由来 level」
#   の 3 arm は self-spec (要件 0 件) では ★入力の如何を問わず発火しない ★恒真 chk になる (M5 が禁じた形) ため
#   ★本 fork には移植していない。 ★能力の喪失ではない:
#     - (a)(b) の対象 shape は上の M5(b)/(c) negative assert が「0 件であること」を契約導出で pin し、
#       要件が入った瞬間に期待が動く (陽性対照 = test-adversarial-self-spec.sh C1/C1b)。
#     - (c) と ★同一判定 が assemble-self-spec.sh の validate() に ★build 時 fail-closed として残っている
#       (contract が statement と矛盾する level を宣言したら ★生成前に abort する) ため、 検出力の穴は開かない。
#   ★要件が入る改訂 (self-spec に EARS 要件を持たせる) をするときは (a)(b)(c) を base から ★移植し直すこと。
NREF_TITLE="$(q '[.references[] | select((.title // "") != "")] | length')"
chk "rf-gloss (照会チップ一行タイトル) == contract の非空 title 件数" "$NREF_TITLE" \
  "$(grep -o '<span class="rf-gloss">' "$BODY" | wc -l | tr -d ' ')"

# 5. block 内容 fidelity (順序突合・silent drop / 値改竄を捕捉)。 全 leaf は esc 済ゆえ [^<]* / perl で安全。
# prose
chk "prose 可視テキスト列 == prose blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="prose") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<p data-component="spec-prose">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# note
chk "note 可視テキスト列 == note blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="note") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-note"><p>([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
# list 項目
chk "list 項目列 == list blocks.items (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="list") | .items[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<li class="lbi">[^<]*</li>' "$BODY" | sed -E 's#<li class="lbi">([^<]*)</li>#\1#')"
# subhead anchor + heading + essence
# ★folio-aduv: h3 に id="<fine section anchor>" を literal 要求 (corpus inbound 81 link の解決先)。 heading は plain 契約値 (esc 経路)、
#   essence は rich raw。 3 者を同一 regex から取り 3 本の chk で突合する (anchor 脱落は 3 本とも件数 FAIL = fail-closed)。
# ★★folio-cuom: self-spec canonical の h3 13 本のうち ★3 本 (§8.1/§8.2/§8.3) は ★id 属性を持たない (実測)。
#   ゆえ id を ★任意 (?:...)? にし、 未捕捉のとき $1 を空文字列へ正規化して契約の空 anchor と ★同一視する。
#   ★緩和ではない (teeth を減らさない) ことの担保 = 下記 3 本:
#     (a) anchor 列の逐値突合 (契約の空文字列 ↔ 生成物の id 無し が 1:1 で並ぶ)
#     (b) id 付き / id 無し の ★件数 を契約側の非空 / 空 anchor 件数から導出して pin
#     (c) 契約非依存 census (FZC_SUBHEAD_ANCHORED / FZC_SUBHEAD_BARE) — 契約側から anchor を一括で
#         空文字列化すると (a)(b) は両側同時に動いて恒真 PASS しうるため、 その唯一の FAIL 源として置く。
SUBHEAD_RE='<div data-component="spec-subhead"><h3(?: id="([^"]*)")?>([^<]*)<\/h3><p class="sub-se">(.*?)<\/p><\/div>'
chk "subhead anchor 列 == subhead blocks.anchor (順序・id 無し h3 は空文字列)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .anchor' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ my $a = defined($1) ? $1 : ""; print "$a\n"; }' "$BODY")"
# (b) 件数を契約から導出して pin (id の付け外しが 1 本でも起これば FAIL)。
chk "subhead: id 付き h3 数 == 契約の ★非空 anchor 数" \
  "$(q '[.sections[].blocks[]? | select(.type=="subhead") | select(.anchor != "")] | length')" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3 id="[^"]*">/g){ $n++ } print $n;' "$BODY")"
chk "subhead: id 無し h3 数 == 契約の ★空 anchor 数" \
  "$(q '[.sections[].blocks[]? | select(.type=="subhead") | select(.anchor == "")] | length')" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3>/g){ $n++ } print $n;' "$BODY")"
# (c) 契約非依存 census (両側同時の空文字列化を塞ぐ唯一の FAIL 源)。
chk "census: id 付き subhead == $FZC_SUBHEAD_ANCHORED (契約非依存 floor)" "$FZC_SUBHEAD_ANCHORED" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3 id="[^"]*">/g){ $n++ } print $n;' "$BODY")"
chk "census: id 無し subhead == $FZC_SUBHEAD_BARE (契約非依存 floor)" "$FZC_SUBHEAD_BARE" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3>/g){ $n++ } print $n;' "$BODY")"
chk "subhead heading 列 == subhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$2\n"; }' "$BODY")"
chk "subhead essence 列 == subhead blocks.essence (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .essence')" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$3\n"; }' "$BODY")"
# ★ADR-0054 §2.2「既定 (人間層) 表示で本文ゼロの見出しを作らない」の契約非依存 census (0/0 恒真封鎖)。
#   ★上の逐値突合は contract から essence を一括削除すると「空 == 空」で恒真 PASS する — 生成物側で
#   ★非空 の .sub-se を持つ subhead 数を数値 hardcode で pin し、 空 subsection への退行を単独で捕捉する。
#   ★self-spec の subhead は essence 空 0 件 (実測 13/13 非空) ゆえ期待値 = |subhead blocks|。
#   ★h3 の id は ★任意 (id 無し 3 本を数え落とすと census が静かに 10 へ痩せる) — SUBHEAD_RE と同型の任意化。
chk "census: 非空の subhead 1 行要約 == $FZC_SUBHEAD_SE (空 subsection 封鎖・契約非依存 floor)" "$FZC_SUBHEAD_SE" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3(?: id="[^"]*")?>[^<]*<\/h3><p class="sub-se">(.*?)<\/p><\/div>/gs){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY")"
# table caption / header / cell (全 spec-table 横断・順序)
# ★folio-aduv: caption / th / td は rich 契約値 (原本 table は a.xref 13 / <code> 41 / <strong> 11 を内包) ゆえ
#   期待は esc せず契約値そのもの、 実測は (.*?) + 固有終端。 grep -oE の行内 [^<]* 抽出では tag 入りセルを取り落とす
#   (= 静かに空集合になり得る) ため perl の要素単位抽出へ寄せる。
chk "table caption 列 == table blocks.caption (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | (.caption // "")' | grep -v '^$')" \
  "$(perl -CSD -0777 -ne 'while (/<table data-component="spec-table"><caption>(.*?)<\/caption>/g){ print "$1\n"; }' "$BODY")"
chk "table th 列 == table blocks.headers (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .headers[]')" \
  "$(perl -CSD -0777 -ne 'while (/<th>(.*?)<\/th>/g){ print "$1\n"; }' "$BODY")"
chk "table td 列 == table blocks.rows cells (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .rows[][]')" \
  "$(perl -CSD -0777 -ne 'while (/<td>(.*?)<\/td>/g){ print "$1\n"; }' "$BODY")"
# mermaid caption + source lines
# ★folio-aduv: figcaption も rich 契約値 (原本 figcaption は <code> 2 + span.term 1 を内包 = canonical term 27 番目の在処)。
chk "mermaid figcaption 列 == mermaid blocks.caption (順序・rich raw)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | (.caption // "")' | grep -v '^$')" \
  "$(perl -CSD -0777 -ne 'while (/<figcaption>(.*?)<\/figcaption>/g){ print "$1\n"; }' "$BODY")"
# ★esc_mermaid (folio-cuom errata-1 M1・assemble-self-spec.sh の同名 helper と ★detect↔remediate parity)。
#   canonical mermaid の <b>…</b> (9 組 / 18 tag) は ★live タグ のまま生成物へ出る規律ゆえ、 期待側も同規律で作る。
#   ★片側だけ変えると本 chk が FAIL する = 二重保守を「同期漏れで落ちる」形に閉じる (wildcard で吸わない)。
esc_mermaid() { local s; s="$(esc "${1-}")"; s="${s//&lt;b&gt;/<b>}"; s="${s//&lt;\/b&gt;/<\/b>}"; printf '%s' "$s"; }
chk "mermaid source 行列 == mermaid blocks.source_lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | .source_lines[]' | while IFS= read -r v; do esc_mermaid "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre class="mermaid">(.*?)<\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"
# code 行 (全 spec-code 横断・順序)
chk "code 行列 == code blocks.lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="code") | .lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<pre data-component="spec-code"><code>(.*?)<\/code><\/pre>/gs){ my $b=$1; print "$_\n" for split(/\n/,$b,-1); }' "$BODY")"

# 6. ★非終端 照会 (references) fidelity: chip echo 厳密一致。
NREF="$(q '.references | length')"
# count anchor (data-ref-token= 出現数)
chk "references: count == |references|" "$NREF" "$(grep -o 'data-ref-token=' "$BODY" | wc -l | tr -d ' ')"
# SET 一致 (token)
set_eq "references: token SET (contract == HTML)" \
  "$(q '.references[].token' | sort -u)" \
  "$(grep -oE 'data-ref-token="[^"]+"' "$BODY" | sed 's/.*data-ref-token="//; s/"$//' | sort -u)"
# role allowlist
badrole="$(grep -oE 'data-ref-role="[^"]+"' "$BODY" | sed 's/.*data-ref-role="//; s/"$//' | sort -u | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
chk_empty "references: role が抽象 allowlist 内" "$badrole"
# (token, doc, role, title) タプル順序突合 (可視 doc / role 平易語 / rf-gloss / attr 全部) + 可視 <b>token</b> == attr。
# ★ADR-0054 §2.2 lockstep 2 点:
#   (a) role の可視ラベルは ★平易語 (ROLE_PLAIN) で、 attr data-ref-role は ★機械 token を保持する = ★非対称 を literal 要求する。
#       旧版は「attr == 可視」の対称を要求していた (英語生表示の pin) ため、 平易化は gate 改修を同伴する。
#       ★可視を突合から外す (「件数だけ数える」等) と平易語の詐称が無警備になるため、 期待側で map を引いて ★逐値突合する。
#   (b) rf-gloss = contract references[].title の ★逐語 echo。 title を持たない contract (all-or-none の「無い」側) では
#       chip に gloss span が無い形を許し (optional group)、 その 0/0 恒真は直後の契約非依存 census が封鎖する。
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
  ' "$BODY")"
# ★folio-cuom: base の「rf-gloss 占有 == 数値 hardcode」pin は ★本 pack では持たない — 本 contract は
#   references[].title を ★1 件も持たない ため hardcode すると 0 の恒真 pin になる (V確定5b で禁じられた形)。
#   代替は §4b の「rf-gloss == contract の非空 title 件数」(契約導出ゆえ title を 1 件足せば期待が動く) +
#   test-adversarial-self-spec.sh の RF-GLOSS-POS (title 付き fixture で chip に gloss が出ることの陽性対照)。
#   ★申送りは冒頭 FZC 節に記載 (ADR-0054 §2.2 の一行タイトル併記を満たすなら 33 件の著述が別途要る)。

# 7. cover-meta 4 KV 再導出突合。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 章の数 == |sections|章"   "$NSEC 章"               "$(printf '%s\n' "$meta_kv" | grep -F '章の数' | head -1 | cut -f2)"
chk "cover-meta 規範要件 == |requirements|件" "$NREQ 件 (EARS)"      "$(printf '%s\n' "$meta_kv" | grep -F '規範要件' | head -1 | cut -f2)"
chk "cover-meta 用語 == |glossary|語"     "$(q '.glossary | length') 語" "$(printf '%s\n' "$meta_kv" | grep -F '用語' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"          "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"             "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# 8. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし"                   "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 9. prose スロット (perl で要素単位判定・3 mode)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-'"$CHKW"'s\n' "prose スロットが無い"; fail=1; fi
if [[ -n "$ARTIFACT" ]]; then
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
elif [[ -z "$FILLED_MANIFEST" ]]; then
  chk "prose スロットは全て空 (pre-fill, filled=0)" "0" "$filled"
else
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  exp="$(mktemp)"; act="$(mktemp)"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    printf '%s\t%s\n' "$key" "$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST") | sort > "$exp"
  perl -0777 -ne 'while (/<([a-zA-Z]+)\b[^>]*\bdata-slot-id="([^"]+)"[^>]*>(.*?)<\/\1>/gs){ print "$2\t$3\n"; }' "$BODY" | sort > "$act"
  if diff -q "$exp" "$act" >/dev/null 2>&1; then
    printf '  [OK]   %-'"$CHKW"'s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# ============================================================================
# 10. ★機械層 (machine free-prose) dual-audience floor — w1f cell-2 / ADR-0045。
#     生成物が 71 機械層 block + 要件 fold を canonical data-audience="machine" form で持ち、
#     REQ-DA-STRUCT-1..5 に適合する (folio_check_dual_audience 相当・bin/folio:865)。
# ============================================================================
# 件数 (contract 由来・silent drop / 偽 add を捕捉)。 fold = machine_blocks を持つ section 数 + (preamble 非空 ? 1 : 0)。
NPRE="$(q '.machine_preamble // [] | length')"
MB_PROSE="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="prose")) | length')"
MB_NOTE="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="note")) | length')"
MB_LIST="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | length')"
MB_LI="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | [.[].items[]] | length')"
# ★demoted (tr0 / verification・ADR-0040 機械層降格分): silent drop / 偽 add を件数で捕捉。
MB_DEMOTED="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="demoted")) | length')"
# ★dl (folio-aduv): dl.doc-meta = 旧 cell-1 の死角で silent drop されていた機械層 block。 raw emit 経路を足した以上
#   件数 pin も足す (件数無しだと 脱落/偽 add が §11 round-trip 以外どこにも出ない)。
MB_DL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="dl")) | length')"
SEC_WITH_MB="$(q '[.sections[] | select((.machine_blocks // []) | length > 0)] | length')"
EXP_FOLD="$SEC_WITH_MB"; [[ "$NPRE" -gt 0 ]] && EXP_FOLD="$((SEC_WITH_MB + 1))"
chk "spec-machine-prose == Σ machine prose"  "$MB_PROSE" "$(grep -c 'data-component="spec-machine-prose"' "$BODY")"
chk "spec-machine-note == Σ machine note"    "$MB_NOTE"  "$(grep -c 'data-component="spec-machine-note"' "$BODY")"
chk "spec-machine-list == Σ machine list"    "$MB_LIST"  "$(grep -c 'data-component="spec-machine-list"' "$BODY")"
chk "machine li (mli) == Σ machine list items" "$MB_LI"  "$(grep -c 'class="mli"' "$BODY")"
chk "spec-machine-demoted == Σ machine demoted" "$MB_DEMOTED" "$(grep -c 'data-component="spec-machine-demoted"' "$BODY")"
chk "spec-machine-dl == Σ machine dl"          "$MB_DL"      "$(grep -c 'data-component="spec-machine-dl"' "$BODY")"
chk "spec-machine-fold == sections(mb) + preamble" "$EXP_FOLD" "$(grep -c 'data-component="spec-machine-fold"' "$BODY")"
# ★ADR-0054 §2.2 lockstep: machine fold の kicker は ★平易語 (旧「機械層 (machine-readable)」= 非エンジニアに不読)。
#   全 fold が同一 literal を持つ (件数 == fold 数) ことを撃つ = 一部だけ旧ラベルへ戻る drift も捕捉する。
chk "machine fold の mf-kicker 平易ラベル == 全 fold ($EXP_FOLD 件・ADR-0054 §2.2)" "$EXP_FOLD" \
  "$(grep -oF "<span class=\"mf-kicker\">$(esc "$MF_KICKER")</span>" "$BODY" | wc -l | tr -d ' ')"
# ★★mf-label / mf-count の ★順序付き逐値 突合 (kicker 件数 pin の隣)。
#   ★kicker の件数だけでは fold summary の ★中身 が無束縛 — 「§1 の fold を §9 帰属へ付け替える」
#   「3 件 → 99 件」の捏造が floor も受入 oracle も素通りしていた (実弾で確認済・fail-open)。
#   期待列は ★contract から導出 する (hardcode しない): emit 順 = preamble fold (非空なら先頭・build() の
#   emit_machine_fold ".machine_preamble" が cover/legend 直後) → machine_blocks を ★持つ section の順。
#   label = heading + 固定接尾辞 (assemble-self-spec.sh の summary 実引数と ★二重保守)、 count = |machine_blocks|。
MF_LABEL_SUFFIX=" の地の文・運用説明・rationale"
MF_PREAMBLE_LABEL="文書前文 (この規約集の位置づけ)"
_mfl=(); _mfc=()
if [[ "$NPRE" -gt 0 ]]; then _mfl+=("$(esc "$MF_PREAMBLE_LABEL")"); _mfc+=("$NPRE 件"); fi
while IFS=$'\t' read -r _h _n; do
  [[ -n "$_h" && "${_n:-0}" -gt 0 ]] || continue
  _mfl+=("$(esc "$_h$MF_LABEL_SUFFIX")"); _mfc+=("$_n 件")
done < <(q '.sections[] | [.heading, ((.machine_blocks // []) | length)] | @tsv')
chk "machine fold の mf-label 列 == contract heading 由来 (順序・章帰属の捏造封鎖)" \
  "$( ((${#_mfl[@]})) && printf '%s\n' "${_mfl[@]}" )" \
  "$(perl -CSD -0777 -ne 'while (/<span class="mf-label">(.*?)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "machine fold の mf-count 列 == |machine_blocks| (順序・件数の捏造封鎖)" \
  "$( ((${#_mfc[@]})) && printf '%s\n' "${_mfc[@]}" )" \
  "$(perl -CSD -0777 -ne 'while (/<span class="mf-count">(.*?)<\/span>/gs){ print "$1\n"; }' "$BODY")"
# ★同上: 要件 normative fold の summary 平易ラベル。 §4 tuple regex も literal 要求しているが、 tuple は
#   ★contract 由来 row のみを見る — ここでは文書全体の占有数で撃ち、 二重に固定する。
chk "要件 normative fold の summary 平易ラベル == |requirements| (ADR-0054 §2.2)" "$NREQ" \
  "$(grep -oF "<summary>$(esc "$RQ_NORM_SUMMARY")</summary>" "$BODY" | wc -l | tr -d ' ')"

echo
echo "--- census-count (blocking arm・folio-jmmk): 容器 block / machine 部品の source DOM 静的件数 == contract 期待件数 ---"
# 機械/LLM 境界 (verification §3.9) の render 非依存 blocking 件数照合。 count_attr_token (quote 構文・属性名 case・数値
# 文字参照 非依存の occurrence 数え = SRS 499ab7b census-count arm と同規律) で data-component トークン件数を数え、 期待値は
# contract から自己導出 (DOM 非参照・contract-anchor)。 内容の順序値 chk (list=items / code=lines / table=cell / machine
# round-trip / fold グルーピング) は容器 block の *境界/個数* を 1:1 で守らない (空 block 追加・block 分割/併合・fold 再グルー
# ピングが順序値を素通る) ため占有 pin (folio-bur) が唯一 anchor。 本 arm は占有 pin de-scope (Phase C) 後も同強度で件数
# 照合を継承する static 後継 (sweep 分類表 = folio-3d23【B2 占有pin sweep 成果物】の第 1 層無し唯一 anchor)。
chk "census-count: spec-list-block == |list blocks|"            "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"   "$(count_attr_token data-component spec-list-block < "$BODY")"
chk "census-count: spec-code == |code blocks|"                  "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"   "$(count_attr_token data-component spec-code < "$BODY")"
chk "census-count: spec-table == |table blocks|"                "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"  "$(count_attr_token data-component spec-table < "$BODY")"
chk "census-count: spec-machine-list == |machine list blocks|"  "$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | length')" "$(count_attr_token data-component spec-machine-list < "$BODY")"
chk "census-count: spec-machine-fold == sections(mb) + preamble" "$(q '([.sections[] | select((.machine_blocks // []) | length > 0)] | length) + ([ ((.machine_preamble // []) | length), 1 ] | min)')" "$(count_attr_token data-component spec-machine-fold < "$BODY")"

# REQ-DA-STRUCT-3 (P-5): 全 live data-audience 値 ∈ {machine, human} (escape 済 code 例示は live tag でないので除外)。
bad_da="$(perl -CSD -0777 -ne 'while (/<[a-z]+\b[^>]*\sdata-audience="([^"]*)"/g){ print "$1\n" unless $1 eq "machine" || $1 eq "human"; }' "$BODY" | LC_ALL=C sort -u | tr '\n' ' ')"
chk_empty "REQ-DA-STRUCT-3: data-audience 値域 (machine|human のみ)" "$bad_da"
# REQ-DA-STRUCT-4: machine 部 (data-audience="machine" を持つ live tag) に aria-hidden が無い (AI/AT 不可視化禁止)。
aria_machine="$(perl -CSD -0777 -ne 'while (/<[a-z]+\b([^>]*)>/g){ my $a=$1; print "x\n" if $a=~/\sdata-audience="machine"/ && $a=~/\baria-hidden\b/; }' "$BODY" | wc -l | tr -d ' ')"
chk "REQ-DA-STRUCT-4: machine 部に aria-hidden 不在" "0" "$aria_machine"
# REQ-DA-STRUCT-1: 各 ears-requirement-row (data-audience="human") が data-audience="machine" 子孫 (rq-norm fold) を持つ。
#   tuple 突合 (§4) が row→rq-norm(machine) の構造隣接を literal 要求済 = NREQ tuple PASS が -1 の構造保証。 件数でも二重に固定。
chk "REQ-DA-STRUCT-1: human 要件 container 数 == |requirements|" "$NREQ" "$(grep -c 'data-component="ears-requirement-row" id="[^"]*" data-req-id="[^"]*" data-ears-pattern="[^"]*" data-audience="human"' "$BODY")"
chk "REQ-DA-STRUCT-1: machine fold (rq-norm) 数 == |requirements|" "$NREQ" "$(grep -c 'class="rq-norm" data-audience="machine"' "$BODY")"
# REQ-DA-STRUCT-2 (id 整合) / -5 (EARS-pattern 整合) は §4 要件タプル突合が enforce 済 (data-req-id==rid / class==EARS_CLASS[pattern])。
printf '  [OK]   %-'"$CHKW"'s %s\n' "REQ-DA-STRUCT-2/-5 (id/EARS-pattern 整合) は §4 tuple が enforce" "委譲"

# raw-emit (★二重 escape 検出): 機械層 raw HTML が壊れず emit されたか。 機械層 region に live inline tag が在り (raw 生存)、
#   機械層 fold 内に二重 escape 痕 (&lt;code&gt; 化けた wrapper) が無いことを確認。 厳密 fidelity は §11 round-trip が担う。
#   ★注: 機械層 prose は <code>&lt;p ...&gt;</code> 等の *正当な escape 済 HTML 例示* を含む (原文由来) ため
#   「&lt; が無い」検査はできない (false-positive)。 二重 escape の確定検出は §11 round-trip (原本テキストと差が出る) が担う。
mfold_region="$(perl -CSD -0777 -ne 'while (/<details data-component="spec-machine-fold"[^>]*>(.*?)<\/details>/gs){ print "$1"; }' "$BODY")"
chk "raw-emit: 機械層に live <code> 生存 (raw 生存)" "$([[ "$(printf '%s' "$mfold_region" | grep -c '<code>')" -gt 0 ]] && echo yes || echo no)" "yes"
chk "raw-emit: 機械層に live <a href 生存"          "$([[ "$(printf '%s' "$mfold_region" | grep -c '<a href=')" -gt 0 ]] && echo yes || echo no)" "yes"
chk "raw-emit: 機械層に live <span class=\"term\" 生存" "$([[ "$(printf '%s' "$mfold_region" | grep -c '<span class="term"')" -gt 0 ]] && echo yes || echo no)" "yes"

# ============================================================================
# 11. ★contract↔生成物 機械層テキスト 双方向 *順序付き* 一致 (round-trip fidelity)。
#     ★政策 A (folio-7n17 / ADR-0053): LEFT を snapshot でも live canonical でもなく
#     ★contract.machine_preamble[] + sections[].machine_blocks[] (25 block) から再構成する。
#     旧版は原本 (snapshot ORIG) を直 grep して LEFT にしていたが、 flip 後 ORIG==生成物 で自己比較恒真化する
#     ため、 政策 A では LEFT を edit-SSoT (contract) 由来へ re-home した。 RIGHT は生成物の機械層。
#     ★tr0: p/aside/ul/li に加え div.demoted (ADR-0040 機械層降格分) と dl も対象 (contract type / 生成物 component 対称)。
#     双方向 (完全性 = contract の全機械層が生成物に / no-fabrication = 生成物の機械層が全て contract に) を照合する。
#     ★順序付き (集合でない): 両側を sort せず document 順の配列のまま diff する (人間層 §4/§5 と対称)。
#       - 順序保存: 機械層 block の document 順を enforce → 同型 block の入替を捕捉。
#       - section 帰属: machine_blocks[] は section ごとに連続して emit される (build()/emit_section) ため、
#         ある block を別 section の fold へ移すと document 順が contract 順とずれる → cross-section 誤帰属も検出。
#         ★射程の開示 (admin gate round-5/6・pre-existing・独立 verifier の実測): 本 arm が検出するのは
#         ★document 順が変わる 移動 ★だけ である — ★単一 block でも 順序が保たれる移動なら ★素通る
#         (round-5 の「単一 block なら検出」は不正確だったので実測へ訂正する)。
#         ★人間層 (chapbody 直下) の順保存移動は containment の ★cbkids (chapbody 直下の契約由来 完全子数) が
#         捕らえるため、 本 arm と cbkids の ★対で 閉じる。 一方 ★機械層 (machine_blocks) を別 section の
#         machine-body へ ★順を保ったまま 移す形は ★どちらでも閉じない (cbkids は fold の内側へ届かない) —
#         機械層 fold 間の帰属検査は ★folio-e706 (machine-body 直下子数 pin + fold summary 件数突合) へ移譲。
#         本 cell は round-trip 側の実装を ★不触 とし、 ここに実態を開示するに留める。
#     ★本 arm が守るのは assembler バグ (生成物が contract から乖離): silent drop / 順序入替 / cross-section 誤帰属 /
#       二重 escape。 ★両側 contract 由来ゆえ ★両側同時退行 (extractor collapse) では vacuous PASS しうる →
#       §10b 凍結 census + extractor-collapse 敵対 test が塞ぐ (mandate: (a)(b) は両側 contract 由来ゆえ (c) で塞ぐ)。
# ============================================================================
NMB_TOTAL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | length')"
# ★ORIG (snapshot) = 政策 A で census / round-trip の【非消費】へ転換 (bootstrap 記録として残置)。 §10b / §11 の
#   存在 fail-closed pin (照合不能 silent skip の回帰 pin・M15) のみが ORIG を参照する (内容不読)。 snapshot の
#   provenance (folio-lwhz land) = `git show c705c75:design-intent/spec/verification.html | sed 's|<dd>1\.1\.0</dd>|<dd>1.2.0</dd>|g'`。
#   snapshot は cell 内改変禁止 (selftest が sha256 pin + 非消費 assert で保護・ADR-0053 に去就を記載)。
# ★★folio-cuom (Leg A): ORIG (spec-origin/<pack>.origin.html = ★手書き版の正式 archive = snapshot) は
#   ★本 Leg では存在しない。 snapshot 作成は flip cell (folio-mkwc) の職掌であり、 本 cell の契約 N2 が明示的に
#   禁止している (errata 適用 ★前 の canonical を byte 忠実に取る前提で mkwc へ申し送る = E5)。
#   ゆえ fork 元が持っていた 2 箇所の「ORIG 存在 fail-closed pin」(§10b / §11) は ★移植しない。
#   ★黙って落とさず実態を開示する (silent 欠落は「範型踏襲済」の誤報告になる):
#     - 失うもの = 「SPEC_ORIGIN_HTML を存在しない path へ向けて gate を silent skip する」逃げ道の封鎖。
#       ★ただし本 fork は ORIG を ★1 箇所も参照しない (census も round-trip も政策 A で contract 由来へ re-home 済
#       = ORIG 非消費) ため、 ★その pin が守る対象の gate が存在しない。 pin だけを残すと「存在しない snapshot が
#       無いこと」を毎回 FAIL する ★恒真 FAIL になる。
#     - 失わないもの = 凍結 census (§10b) と機械層 round-trip (§11)。 どちらも ORIG に依存しない。
#   ★mkwc への申送り: snapshot を置いたら本 pin を ★復活させる こと (範型 verification の COLLAPSE 群は
#     pre-flip 再抽出元として ORIG の ★内容を消費する 設計ゆえ、 snapshot 導入時に守備対象が生まれる)。
# ---- ★mkwc への追加申送り (folio-cuom errata-1 M7・独立 ceiling advisory A1 / A3 の durable 記録) ----
#   ★A1 landed-canonical arm の SKIP_REPRO=1 ★継承: flip 後に canonical そのものを subject にする arm は
#     範型から SKIP_REPRO=1 を継承する。 repro-build byte-identity が ★飛ぶ ため、 ★style payload
#     (inline CSS ブロック) の改変は floor の占有 pin にも census にも当たらず ★素通りする (穴の ★継承 であって
#     本 Leg の退行ではない)。 ★flip 時に landed-canonical arm を作るなら repro arm を ★ON で回すこと
#     (本 Leg の G2 = repro_pins が sub-pin (a)-(d) の conformance を既に敷いてある)。
#   ★A3 <meta name="generator" content="folio spec-pack assembler …"> の ★literal が ★未 pin:
#     この literal は consumer 側 chrome 述語 (bin/folio の folio_chrome_is_generated_spec /
#     folio_chrome_pack_alt) の ★唯一の検出鍵 だが、 本 floor は値を pin していない。 drift すると
#     chrome-scope arm と locator 注入が ★silent に no-op へ落ちる (validate は緑のまま)。
#     ★flip で canonical が生成物になる時点から実害面へ入るため、 mkwc で literal pin を敷くこと。
ORIG_ABSENT_BY_CONTRACT=1   # ★Leg A では snapshot 不在が ★正常 (上記注記が SSoT)

# ============================================================================
# 10b. ★literal census arm (folio-7n17 政策 A・snapshot oracle bootstrap 退役後の恒久防御 (a))。
#   ★政策 A への転換 (user 裁定 2026-07-18 / ADR-0053): 旧 arm は ORIG (=snapshot 既定・flip 後 生成物) と
#     HTML の ★相対 parity (c_xref(ORIG) vs c_xref(HTML)) を撃っていたが、 flip 後 ORIG==生成物 で ★自己比較
#     恒真化する (verify-self-spec.sh 旧:461-464 実証)。 政策 A はこれを撤去し、 expected を canonical /
#     artifact / 生成物から【導出しない】★凍結 literal (spec-origin/verification.frozen-census.txt) とし、
#     measured 側を ★生成物 HTML (verify の subject) へ固定する。 ORIG は census を【消費しない】 (下記存在 pin のみ)。
#   ★なぜ独立 anchor が要るか: §4/§5 の rich 突合は全て「contract vs 生成物」で ★両側同時退行で vacuous PASS
#     する (extractor が plain() へ戻ると contract も生成物も同時に rich を失う = mandate HIGH-4)。 凍結 literal
#     census は両側と独立ゆえ、 collapse しても frozen 31 vs 生成物 6 で FAIL する (test-adversarial の collapse
#     test / 本番自己比較 MK が red→green で実証)。
#   ★ORIG 存在 fail-closed pin は【存置】(照合不能 silent skip の回帰 pin・M15)。 snapshot file は bootstrap
#     記録として残置し census は消費しない (非消費 = selftest の非消費 assert + hash pin が cell 内改変を FAIL に)。
# ============================================================================
# 凍結 census 読み取り (frozen literal SSoT・source せず grep で読む = tab / bracket / quote 安全)。
FROZEN_CENSUS="$SCRIPT_DIR/spec-origin/self-spec.frozen-census.txt"
[[ -f "$FROZEN_CENSUS" ]] || { echo "verify-self-spec: ★凍結 census 不在 (政策A anchor 喪失・fail-closed): $FROZEN_CENSUS" >&2; exit 2; }
fz()     { grep -m1 "^$1=" "$FROZEN_CENSUS" | sed "s/^$1=//"; }                                  # scalar
fz_ld()  { grep -m1 "^FZ_STAKEHOLDERS_LD=" "$FROZEN_CENSUS" | sed 's/^FZ_STAKEHOLDERS_LD=//'; }  # 型\t値 (tab 保持)
fz_set() { sed -n "/#BEGIN_$1/,/#END_$1/p" "$FROZEN_CENSUS" | grep -vE '^#'; }                    # id / delta set

# ★inert region 除去 (folio-7wbn ceiling major fix・parser-differential 封鎖)。
#   census の regex counter は raw HTML を素で舐めるため、 ★HTML コメント (<!-- ... -->) と <script>/<style> の
#   text 本体に書かれた「タグ様文字列」を live 要素として数えてしまう。 これは政策A の【唯一の独立 anchor】を
#   edit-SSoT (contract) 側から水増し/目減りさせる laundering 経路になる:
#     - deflate/laundering: live な a.xref を 1 個失っても `<!-- <a class="xref"></a> -->` を 1 個足せば凍結値へ復元でき、
#       COLLAPSE-2 が守る性質 (両側同時退行の捕捉) が破れる。 contract の machine_blocks[].html は raw 出力ゆえ到達可能。
#     - false-FAIL: 機械層 block に正当なコメント (タグ様文字列を含む) を 1 つ書くだけで census が偽 FAIL する。
#   ★同一 arm 内で計数方式を揃える: h_inline は実 HTML parser で subtree 境界を読む (parser-differential 回避) 一方、
#   regex counter だけが naive だった。 そこで ★実 HTML parser (html.parser) で comment / script / style の span を
#   特定し、 その ★raw byte 範囲だけを除去した view を作り、 後段の計数はその view に対して走らせる。
#   (parser を「除去範囲の特定」にのみ使い本文は byte 保存する。)
#   ★★本 view だけでは足りない (folio-7wbn 2 巡目 ceiling major・attribute laundering): comment / script / style を
#   除いても ★属性値 は raw byte として残るため、 naive regex counter は単引用符属性の中のタグ様文字列を live 要素として
#   数えてしまう (例 `<div data-note='<a class="xref" href="#z">z</a>'>` で c_xref が +1 / `data-x='<section id="s5-delta">'`
#   で id census も復元できる = CEN-id1/id2・CEN-rich1/2・COLLAPSE-2 の teeth が同一クラスの手で破れる)。
#   ゆえに ★全 census 計数 (id / a.xref / span.term / ins|del.delta / delta-id / escape literal) を regex から
#   ★実 HTML parser の walk (census_dump) へ寄せた: 属性値は attrs として構造的に読まれ本文計数へ混入しえず、
#   escape literal (&lt;a class="xref" 等) は ★text node 限定 (entity 記法を復元して) 数える。 comment / script /
#   style は parser 段でも非計数。 ★この結果 strip_inert 前処理は冗長となり (計数側が単独で成立する)、 かつ bogus
#   comment のオフセット誤算という fail-open を持つため ★両 arm とも census subject から外してある (folio-gt4s・下記隔離注記)。
strip_inert() { python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys
src = open(sys.argv[1], encoding='utf-8').read()
starts = []; acc = 0
for line in src.splitlines(keepends=True):
    starts.append(acc); acc += len(line)
starts.append(acc)
def off(pos):
    ln, col = pos
    return starts[ln - 1] + col
class S(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False); self.cuts = []; self.raw = None
    def handle_comment(self, data):          # <!-- ... --> = 4 + len + 3 byte
        s = off(self.getpos()); self.cuts.append((s, s + len(data) + 7))
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'): self.raw = tag
    def handle_data(self, data):             # CDATA mode ゆえ raw text と 1:1
        if self.raw:
            s = off(self.getpos()); self.cuts.append((s, s + len(data)))
    def handle_endtag(self, tag):
        if tag == self.raw: self.raw = None
p = S(); p.feed(src); p.close()
out = []; prev = 0
for a, b in p.cuts:
    if a < prev: continue
    out.append(src[prev:a]); prev = b
out.append(src[prev:])
sys.stdout.write(''.join(out))
PYEOF
}
# ★★【隔離中・census は本 view を消費しない】(folio-7st6 ceiling major fix)。
#   strip_inert には ★bogus comment のオフセット誤算 という fail-open 欠陥がある: handle_comment は cut 終端を
#   `s + len(data) + 7` (= `<!--` 4 byte + `-->` 3 byte の決め打ち) で算出するが、 Python html.parser は
#   ★bogus comment `<!x>` (実長 4 byte) に対しても handle_comment(data='x') を発火するため、 計算長 8 で
#   ★直後の live 4 byte を過剰削除する。 実測: `A<!x><template><code>z</code></template>B`
#   → `Aplate><code>z</code></template>B` で <template> 開始タグが破壊され ★中身が live 化する。
#   ゆえに本 view を census subject にすると、 `<!x>` を 4 byte 前置するだけで <template> inert 除外が破れ、
#   (1) inflate (decoy 注入で凍結値が動く) と (2) deflate/laundering (live 資産を剥奪しても凍結値へ「復元」できる)
#   の ★両方向 が再開通する = 政策 A の【唯一の独立 anchor】の fail-open (実測再現済・CEN-tpl6/7 が pin)。
#   ★修正方針 (finding 提案 A = 呼び先のみ是正): census_dump / h_inline は ★共に実 HTML parser であり、
#   comment / script / style を非計数・<template> を除外 ★済 ゆえ、 strip_inert 前処理は「二重の帯」ではなく
#   ★実際には唯一の穴 だった。 よって census subject を RAW $HTML へ戻す (実測: 生 $HTML で 31/57/79 = 凍結一致)。
#   ★関数本体 (strip_inert) は契約 (a) の verify-spec.sh からの byte-identical 逐語移植ゆえ ★改変しない。
#   同一欠陥は rules arm (verify-spec.sh) にも存在したが、 ★folio-gt4s で ★両 arm 同時に 同じ経路 (呼び先のみ
#   RAW $HTML へ切替・本体は無改変) で是正済 = 現在は ★両 arm とも strip_inert を消費しない対称形。
#   ★本注記だけを唯一の記録にしない (回避表記封鎖 = c5r.2・追跡は folio-gt4s / folio-7st6)。
#   ★本 view は構造 parity 維持のため生成のみ残置し ★どの census も消費しない。 再配線するなら先に本体を直すこと。
HTML_LIVE="$(mktemp)"
strip_inert "$HTML" > "$HTML_LIVE" || { echo "verify-self-spec: ★census live view 生成に失敗 (fail-closed): $HTML" >&2; exit 2; }
[[ -s "$HTML_LIVE" ]] || { echo "verify-self-spec: ★census live view が空 (fail-closed): $HTML" >&2; exit 2; }

# ★census 計数 helper (census subject = 生成物 HTML の ★RAW byte / ORIG は非消費・上記隔離注記を参照)。
#   ★実 HTML parser の 1 walk で全軸を出す (attribute laundering 封鎖・上記 ★★参照):
#     - element 軸 (id / a.xref / span.term / ins|del.delta / delta-id) は starttag の ★attrs から数える
#       (属性値の中に書かれたタグ様文字列は attrs の ★値 でしかなく、 要素として計上されえない)。
#     - escape literal 軸 (&lt;a class="xref" / &lt;code / &lt;span) は ★text node のみ から数える
#       (entityref / charref を元記法へ復元して連結。 属性値・comment・script/style 本文は非計数)。
#   出力形式: `KEY=n` 行 → `#IDS` 節 (navigable id) → `#DIDS` 節 (delta-id)。
# ★【是正済・folio-gt4s】自己閉じ形 `<template/>` による element 軸の 1 byte 迂回は handle_startendtag を
#   ★HTML 準拠 (非 void の trailing solidus は無視され template を ★開く) へ寄せて封鎖済:
#   `self._tag(tag, attrs); if tag in INERT_SUBTREE: self.stack.append(tag)` (★両 arm へ逐字同一に適用)。
#   ★push を INERT_SUBTREE のみ に絞るのが要点: `if tag not in VOID` 相当だと canonical の SVG foreign content
#   (`<path/>` 等) が閉じられず stack を汚染し、 region / inert 判定を巻き添えで壊す (別クラスの誤計数)。
#   text/inline 軸 (h_inline) の同一迂回は folio-7st6 で是正済 (下記 h_inline.handle_startendtag)。
#   ★本体へ手を入れる際は ★両 arm 同時 に逐字同一で行う (片 arm のみの改変は cross-arm 非対称の新設)。
census_dump() { python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys, re
VOID={'br','img','meta','link','input','hr','wbr','source','col','area','base','embed','param','track'}
# ★非描画 subtree (folio-7wbn 3 巡目 ceiling major fix): <template> の内容は browser が ★描画しない
#   (inert DocumentFragment) ため「live 資産」ではなく census が数えてはならない。 数えると comment / 属性値と
#   ★同一クラス の laundering 経路が開く: live な a.xref を 1 個失っても
#   `<template><a class="xref" href="#z">z</a></template>` を 1 個足せば凍結 26 へ「復元」でき、
#   COLLAPSE-2 が守る性質 (両側同時退行を独立 anchor が捕捉する) が破れる (実測再現済)。
#   到達性は comment / 属性 vector と同じ (contract.machine_blocks[].html は raw 出力・extractor は原本 inner HTML を
#   逐語 capture)。 ★element 軸 (id / a.xref / span.term / delta) と ★text 軸 (escape literal) の ★両方 を除外する
#   (片方だけだと escape literal 側に同じ穴が残る)。
#   ★noscript は除外しない: scripting 無効時には ★描画される = live たりうるため、 除外すると逆に「正当な資産の
#   数え落とし」= 偽 FAIL / 隠し場所を作る。 除外の対象は「どの条件でも描画されない」template に限る。
#   ★raw text / RCDATA 要素も inert に含める (folio-gt4s errata-1 MUST-3)。 通常形は html.parser の CDATA mode が
#   中身をタグとして emit しないため実害が無かったが、 ★自己閉じ形 `<script/>` `<xmp/>` 等は handle_startendtag
#   発火ゆえ CDATA mode に入らず、 browser が閉じタグまで raw text (= 要素として描画しない) 扱いする区間を
#   census が ★live 計上 していた (実測: 凍結値復元が成立)。
#   ★集合は ★手書き列挙せず parser 自身から導出する (partial-enumeration trap の回避): {'script','style'} だけを
#   手書きした版は textarea / title / xmp / iframe / noembed / noframes の自己閉じで ★同一クラスが再開通した。
#   html.parser が自ら宣言する CDATA / RCDATA 集合を土台にすれば、 parser の認識と census の inert 判定が
#   ★構造的に同期する (parser 側が集合を増やせば census も自動追随し、 列挙漏れが原理的に生じない)。
#   ★noscript は入らない (導出集合に含まれない) = 正しい: scripting 無効時には ★描画される = live たりうるため、
#   除外すると逆に「正当な資産の数え落とし」= 偽 FAIL / 隠し場所を作る (folio-7wbn 裁定を維持)。
#   ★INERT_SUBTREE へ足す形ゆえ handle_startendtag の最小形 (契約固定) を ★逐字そのまま 使える
#   (push 条件が `tag in INERT_SUBTREE` ゆえ全 raw text 要素が同経路で inert 区間になる)。
#   canonical に該当要素の自己閉じは 0 件 (grep verified) ゆえ正当な資産の計数には無影響。
# ★RAWTEXT 系 / element 系の分離 (folio-ahn3)。 両者は「中身を描画しない」点で同じ inert だが ★閉じ方の
#   semantics が違う: RAWTEXT 系 (CDATA / RCDATA) は ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列 —
#   一方 template は通常の element ゆえ入れ子構造を持つ。 集合の ★実体は不変 (INERT_SUBTREE は従来と同一) で、
#   ★自己閉じ経路に CDATA mode を与えるための ★名前付き部分集合 を切り出すだけ (parser 由来導出も従来どおり
#   維持 = 手書き列挙による partial-enumeration trap を再導入しない)。
RAWTEXT_INERT = (set(HTMLParser.CDATA_CONTENT_ELEMENTS)
    | set(getattr(HTMLParser, 'RCDATA_CONTENT_ELEMENTS', ('textarea', 'title'))))
INERT_SUBTREE = {'template'} | RAWTEXT_INERT
class C(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack=[]; self.raw=None; self.ids=[]; self.dids=[]; self.text=[]
        self.n_xref=0; self.n_term=0; self.n_delta=0
    def inert(self):
        return any(t in INERT_SUBTREE for t in self.stack)
    def _tag(self, tag, attrs):
        if self.inert(): return
        d={}
        for k,v in attrs:
            if k not in d: d[k] = v if v is not None else ''
        if d.get('id'): self.ids.append(d['id'])
        cls = d.get('class') or ''
        if tag=='a' and 'xref' in cls.split(): self.n_xref+=1
        if tag=='span' and cls=='term' and 'data-term' in d: self.n_term+=1
        if tag in ('ins','del') and cls=='delta' and 'data-delta-id' in d:
            self.n_delta+=1; self.dids.append(d['data-delta-id'])
    def handle_starttag(self, tag, attrs):
        self._tag(tag, attrs)
        if tag in ('script','style'): self.raw=tag
        if tag not in VOID: self.stack.append(tag)
    def handle_startendtag(self, tag, attrs):
        # ★自己閉じ形 `<template/>` の 1 byte 迂回封鎖 (folio-gt4s・element 軸)。 HTML Standard では非 void 要素の
        #   trailing solidus は無視され `<template/>` は template を ★開く (中身は inert)。 一方 Python html.parser は
        #   本 hook を発火し stack へ push しないため INERT_SUBTREE 判定が効かず、 element 軸だけ 1 文字で
        #   inert 除外を迂回できていた (実測再現済)。 ★push は inert 判定に必要な template のみ に限る:
        #   canonical は SVG foreign content (`<path/>` 等) を持ち、 これらは自己閉じが ★正規 ゆえ無条件に push すると
        #   閉じられず stack を汚染し、 region / inert 判定を巻き添えで壊す (fail-closed でなく ★別クラスの誤計数)。
        # ★RAWTEXT 系は push ★だけ では足りない (folio-ahn3)。 push は「中身を数えない」を作るが、 HTML5 の
        #   raw text 区間は ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列 という semantics を持つ。
        #   push のみだと html.parser は区間内の `<template>` 等を ★実タグとして emit し stack へ積むため、
        #   後続の `</script>` が (最内 inert = template に阻まれ) 自分自身を閉じられず inert が解除されない。
        #   結果 attacker は `<script/><template></script>…</template></script>` で「browser では ★描画される
        #   のに census は数えない」★有界な盲点 (他 census 値は無傷) を 8 タグ × 両軸で作れた (実測・base
        #   8d4eeda からの pre-existing)。 ★是正は parser 自身の CDATA mode を ★自己閉じ経路にも与えること:
        #   set_cdata_mode により区間は handle_data へ流れ (= タグとして emit されない)、 `</script>` が
        #   handle_endtag を発火して inert を ★正しく閉じ、 以降が live 計上へ戻る (ground truth 一致)。
        #   ★push は撤去しない (追加であって置換ではない): set_cdata_mode 単独だと raw 区間の handle_data が
        #   stack 上の inert 不在ゆえ text 軸 (escape literal) を汚染する。 push が inert() を真に保つ。
        self._tag(tag, attrs)
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
        if tag in INERT_SUBTREE: self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag==self.raw: self.raw=None
        # ★inert subtree は ★scope 境界 (folio-gt4s errata-1 MUST-4)。 素朴な `del self.stack[i:]` は ★祖先 に
        #   一致する end tag でも inert を巻き取って外すため、 stray end tag 1 本で inert 区間が解除され中身が
        #   live 計上された。 HTML5 では inert 内の不一致 end tag は無視され (raw text 内なら ★ただの文字列)
        #   inert は開いたまま = 中身は非描画。
        #   ★探索下限は ★最内 inert 位置から ★無条件に 導出する (以前は `tag not in INERT_SUBTREE` のときだけ
        #   導出していたため、 inert 名の end tag が ★入れ子 inert を外から閉じられた:
        #   `<template><script/></template>` で凍結値復元が成立・実測)。 inert 名の end tag は ★最内 inert 自身
        #   のみを閉じうる (lo=m)、 それ以外は最内 inert より ★内側 のみ (lo=m+1)。 inert 不在なら従来どおり全域。
        #   ★★この scope 境界の ★捕捉範囲 (宣言能力 == 実能力・errata-2 MUST-B / ★folio-ahn3 で
        #   ★HTML 名前空間の当該形を閉塞・★foreign content 経由は ★未閉塞):
        #     ★捕れる = element 系 inert (template) の scope 境界 / 正しく閉じた入れ子 inert /
        #               指定 2 shape (<template><script/></template> / <template><textarea/></template>)。
        #               per-shape MK (CEN-nest1/2/3/5) で実弾 pin 済。 ★逆順 shape (<script/><template></script>)
        #               は folio-ahn3 の是正で ★捕捉対象から外れた: `</script>` が raw text を閉じ後続は
        #               ground truth どおり ★live ゆえ、 剥奪分を live 資産で復元する形は ★正当 (既 admin 裁定
        #               「実描画される注入での復元は MK にしない」と同クラス)。 CEN-nest4 は ★期待反転 で保持され
        #               (admin 裁定 2026-07-21)、 「後続が live 計上される」ground truth 整合を pin する。
        #     ★閉塞済 (folio-ahn3・★HTML 名前空間 に限る) = RAWTEXT 系 inert (script/style/xmp/iframe/
        #               noembed/noframes/textarea/title) を ★自己閉じで開いた後に別の inert 開始タグを挟み
        #               ★末尾で閉じ直す 形 (例 `<script/><template></script>…</template></script>`)。 かつては
        #               挟んだ区間の資産が census の ★有界な盲点 になっていた (他の census 値は無傷・8 タグ ×
        #               両軸で同型・実測。 ★base 8d4eeda から存在した pre-existing)。 ★是正済: handle_startendtag
        #               が RAWTEXT 系に set_cdata_mode を与えるため区間内のタグは emit されず (= 挟めない)、
        #               自分の end tag が inert を正しく閉じて以降は live 計上へ戻る。 CEN-rawnest 群が 8 タグ ×
        #               両軸 × 両 arm で per-shape に実弾 pin し、 SETCDATA 存在 pin が producer 側を静的に押さえる。
        #     ★未閉塞 (★同族・foreign content 経由・★live fail-open) = `<svg>` / `<math>` 内の ★自己閉じ RAWTEXT。
        #               foreign content では自己閉じが ★正規に閉じる ため実 browser は raw text を ★開かない が、
        #               本 census は set_cdata_mode を ★名前空間非依存 に与えるため raw 区間を開いてしまい、
        #               attacker は末尾の stray end tag で閉じ直せる。 ★実測 fixture (両 arm 同一結果):
        #                 <html><body><svg><script/></svg><div id="INJ"></div><code>zz</code>&lt;span
        #                 </script><div id="tail"></div></body></html>
        #               → IDS=[tail] のみ (INJ ★非計数) / ESC_SPAN=0 / 人間層 code=0 なのに tail は計上され続ける
        #               = ★他 census 値は無傷 の同族 bounded blind spot。 ground truth (html5lib) では INJ の
        #               ancestor chain = ['html','body','div'] = ★実描画。 同型が `<math><style/></math>…</style>` /
        #               `<svg><textarea/></svg>…</textarea>` でも再現 (CDATA / RCDATA 双方)。
        #               ★base c55bac6 でも同一挙動 = pre-existing (folio-ahn3 の退行ではない)。 fix は名前空間
        #               追跡を要する parser semantics の再設計で本 cell の契約 (3 分岐の逐字温存) の外ゆえ
        #               ★folio-3z10 として ★起票済 (admin 裁定 2026-07-21)。 本 cell は ★宣言を実能力へ縮小する
        #               に留める (「全クラス閉塞」と書けば次の cell が探索を打ち切る = false record ゆえ書かない。
        #               「ついでに塞ぐ」も禁止 = 契約 fence 外)。
        m=-1
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i] in INERT_SUBTREE: m=i; break
        lo = 0 if m<0 else (m if tag in INERT_SUBTREE else m+1)
        for i in range(len(self.stack)-1,lo-1,-1):
            if self.stack[i]==tag: del self.stack[i:]; break
    def handle_data(self, data):
        if not self.raw and not self.inert(): self.text.append(data)
    def handle_entityref(self, name):
        if not self.raw and not self.inert(): self.text.append('&'+name+';')
    def handle_charref(self, name):
        if not self.raw and not self.inert(): self.text.append('&#'+name+';')
p=C(); p.feed(open(sys.argv[1], encoding='utf-8').read()); p.close()
t=''.join(p.text)
print('C_XREF=%d' % p.n_xref)
print('C_TERM=%d' % p.n_term)
print('C_DELTA=%d' % p.n_delta)
print('ESC_XREF=%d' % len(re.findall(r'&lt;a class="xref"', t)))
print('ESC_CODE=%d' % len(re.findall(r'&lt;code', t)))
print('ESC_SPAN=%d' % len(re.findall(r'&lt;span', t)))
# ★ID_TOTAL = dedup ★前 の総出現数 (folio-7wbn 3 巡目 ceiling major fix)。 下段 #IDS 節は set() で dedup するため、
#   ★既存 id の複製注入 (例 <div id="s5-delta"></div> を body 直後へ) は count census (unique 58) でも SET census でも
#   原理的に検出できず verify を rc=0 で素通っていた (実測再現済)。 HTML の fragment 解決は文書順 first-match ゆえ、
#   本文より前へ空の複製 anchor を置くと当該 id を指す全 xref がその空要素へ ★hijack され navigation が壊れる。
#   unique == 総出現 を ★構造的不変条件 として撃つ (凍結 literal を増やさない = census file / provenance sha 無改訂)。
print('ID_TOTAL=%d' % len(p.ids))
print('#IDS')
for i in sorted(set(p.ids)): print(i)
print('#DIDS')
for i in sorted(set(p.dids)): print(i)
PYEOF
}
# generic inline (code/span) の ★人間層 (data-audience="machine" subtree の外) occurrence を region 別に数える。
#   実 HTML parser で ancestor を辿る (naive tag-strip regex は subtree 境界を読めず parser-differential を生む)。
h_inline() { python3 - "$1" "$2" "$3" <<'PYEOF'
from html.parser import HTMLParser
import sys
VOID={'br','img','meta','link','input','hr','wbr','source','col','area','base','embed','param','track'}
# ★非描画 subtree 集合 (census_dump の INERT_SUBTREE と ★同一 導出・folio-gt4s errata-1 MUST-3)。
#   template に加え raw text / RCDATA 要素を含める: 通常形は html.parser の CDATA mode が中身をタグとして
#   emit しないため実害が無かったが、 ★自己閉じ形 `<script/>` `<xmp/>` 等は handle_startendtag 発火ゆえ
#   CDATA mode に入らず、 browser が閉じタグまで raw text (非描画) 扱いする区間の <code> / <span> を
#   ★live 計上 していた (実測: 凍結値復元が成立)。
#   ★手書き列挙せず parser 自身から導出する (partial-enumeration trap の回避): {'script','style'} だけを
#   手書きした版は textarea / title / xmp / iframe / noembed / noframes の自己閉じで同一クラスが再開通した。
#   ★noscript は導出集合に含まれない = 正しい (scripting 無効時に描画されるため除外しない・folio-7wbn 裁定)。
# ★RAWTEXT 系 / element 系の分離 (folio-ahn3・census_dump の RAWTEXT_INERT と ★同一 導出)。 RAWTEXT 系は
#   ★自分の end tag だけ が閉じ間のタグは ★ただの文字列 という semantics を持つため、 自己閉じ経路へ
#   CDATA mode を与える必要がある (下記 handle_startendtag)。 集合の ★実体は不変 (INERT は従来と同一)。
RAWTEXT_INERT = (set(HTMLParser.CDATA_CONTENT_ELEMENTS)
    | set(getattr(HTMLParser, 'RCDATA_CONTENT_ELEMENTS', ('textarea', 'title'))))
INERT = {'template'} | RAWTEXT_INERT
class W(HTMLParser):
    def __init__(self, target, region):
        super().__init__(convert_charrefs=False); self.stack=[]; self.n=0
        self.target=target; self.region=region
    def inert(self):
        return any(t in INERT for t,_ in self.stack)
    def handle_starttag(self, tag, attrs):
        # ★重複属性は ★first-wins (folio-7st6 ceiling major fix)。 HTML Standard では 2 つ目以降の同名属性は
        #   parse error として ★破棄 される (最初が勝つ)。 dict(attrs) は last-wins ゆえ
        #   `<div data-audience="machine" data-audience="human">` を browser は機械層と解釈するのに h_inline は
        #   人間層として計上し、 live 資産 1 個剥奪 → 重複属性で偽の人間層資産 1 個注入 で凍結値へ復元できた
        #   (= CEN-tpl4/M18 が守る性質が同一クラスの手で破れる)。 census_dump は既に first-wins ゆえ
        #   ★同一 walk 内の計数規約を揃える (intra-arm 非対称の解消)。
        d={}
        for k,v in attrs:
            if k not in d: d[k] = v if v is not None else ''
        # ★非描画 subtree 除外 (census_dump と同型・folio-7wbn 3 巡目 ceiling): <template> 内は描画されないため
        #   live inline 資産でない。 除外しないと td/figcaption へ <template><code>z</code></template> を置くだけで
        #   region 別 occurrence を水増しでき、 element 軸を閉じた意味が無くなる (計数方式を arm 内で揃える)。
        if tag==self.target and not self.inert():
            if not any(a.get('data-audience')=='machine' for _,a in self.stack):
                r='rest'
                for t,a in reversed(self.stack):
                    cls=a.get('class') or ''
                    if t in ('td','th'): r='table-cell'; break
                    if t=='figcaption' or 'caption' in cls: r='caption'; break
                if self.region=='human' or self.region==r: self.n+=1
        if tag not in VOID: self.stack.append((tag,d))
    def handle_startendtag(self, tag, attrs):
        # ★自己閉じ形 `<template/>` の 1 byte 迂回封鎖 (folio-7st6 ceiling major fix)。
        #   HTML Standard では ★非 void 要素の trailing solidus は無視され `<template/>` は template を ★開く
        #   (後続内容は browser で描画されない = inert)。 一方 Python html.parser は handle_startendtag を発火し、
        #   base 既定は starttag→endtag を続けて呼ぶため push 直後に pop され ★inert 区間にならなかった。
        #   結果 `<template/>` 1 形で CEN-tpl4/8 が封鎖した laundering クラスが丸ごと再開通していた (実測再現済)。
        #   ★HTML 準拠に合わせ「開始タグとして扱う」へ是正する。 ただし ★開いたままにするのは inert 判定に必要な
        #   template のみ に限る: canonical は SVG foreign content (`<path/>` 16 / `<circle/>` 3) を持ち、 これらは
        #   自己閉じが ★正規 ゆえ無条件に push すると閉じられず stack を汚染し、 後続の region 判定と
        #   data-audience="machine" 判定を巻き添えで壊す (fail-closed でなく ★別クラスの誤計数 になる)。
        # ★RAWTEXT 系は push ★だけ では足りない (folio-ahn3・census_dump と ★同型)。 HTML5 の raw text 区間は
        #   ★自分の end tag だけ が閉じ、 間のタグは ★ただの文字列。 push のみだと区間内の `<template>` 等が
        #   ★実タグとして emit され stack へ積まれ、 後続の `</script>` が最内 inert に阻まれて自分を閉じられず
        #   inert が解除されない → `<script/><template></script>…</template></script>` で「browser では描画される
        #   のに census は数えない」★有界な盲点 が 8 タグ × 両軸に開いていた (実測・base 8d4eeda から pre-existing)。
        #   ★是正は parser 自身の CDATA mode を自己閉じ経路へ与えること (set_cdata_mode)。 ★push は撤去しない
        #   (追加であって置換ではない): 単独適用だと raw 区間が region / machine 判定へ素通りする。
        self.handle_starttag(tag, attrs)
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
        if tag not in INERT and self.stack and self.stack[-1][0] == tag: self.stack.pop()
    def handle_endtag(self, tag):
        # ★inert subtree は ★scope 境界 (census_dump と同型・folio-gt4s errata-1 MUST-4)。 素朴な
        #   `del self.stack[i:]` は ★祖先 に一致する stray end tag でも inert を巻き取って外すため、
        #   stray end tag 1 本で inert 区間が解除され中身が live 計上された。 HTML5 では inert 内の不一致
        #   end tag は無視され (raw text 内なら ★ただの文字列) inert は開いたまま = 非描画。
        #   ★探索下限は ★最内 inert 位置から ★無条件に 導出する (以前は `tag not in INERT` のときだけ導出して
        #   いたため、 inert 名の end tag が ★入れ子 inert を外から閉じられた: `<template><script/></template>`
        #   で凍結値復元が成立・実測)。 inert 名の end tag は ★最内 inert 自身のみを閉じうる (lo=m)、
        #   それ以外は最内 inert より ★内側 のみ (lo=m+1)。 inert 不在なら従来どおり全域。
        #   ★★この scope 境界の ★捕捉範囲 (宣言能力 == 実能力・errata-2 MUST-B / ★folio-ahn3 で
        #   ★HTML 名前空間の当該形を閉塞・★foreign content 経由は ★未閉塞):
        #     ★捕れる = element 系 inert (template) の scope 境界 / 正しく閉じた入れ子 inert /
        #               指定 2 shape (<template><script/></template> / <template><textarea/></template>)。
        #               per-shape MK (CEN-nest1/2/3/5) で実弾 pin 済。 ★逆順 shape (<script/><template></script>)
        #               は folio-ahn3 の是正で ★捕捉対象から外れた: `</script>` が raw text を閉じ後続は
        #               ground truth どおり ★live ゆえ、 剥奪分を live 資産で復元する形は ★正当 (既 admin 裁定
        #               「実描画される注入での復元は MK にしない」と同クラス)。 CEN-nest4 は ★期待反転 で保持され
        #               (admin 裁定 2026-07-21)、 「後続が live 計上される」ground truth 整合を pin する。
        #     ★閉塞済 (folio-ahn3・★HTML 名前空間 に限る) = RAWTEXT 系 inert (script/style/xmp/iframe/
        #               noembed/noframes/textarea/title) を ★自己閉じで開いた後に別の inert 開始タグを挟み
        #               ★末尾で閉じ直す 形 (例 `<script/><template></script>…</template></script>`)。 かつては
        #               挟んだ区間の資産が census の ★有界な盲点 になっていた (他の census 値は無傷・8 タグ ×
        #               両軸で同型・実測。 ★base 8d4eeda から存在した pre-existing)。 ★是正済: handle_startendtag
        #               が RAWTEXT 系に set_cdata_mode を与えるため区間内のタグは emit されず (= 挟めない)、
        #               自分の end tag が inert を正しく閉じて以降は live 計上へ戻る。 CEN-rawnest 群が 8 タグ ×
        #               両軸 × 両 arm で per-shape に実弾 pin し、 SETCDATA 存在 pin が producer 側を静的に押さえる。
        #     ★未閉塞 (★同族・foreign content 経由・★live fail-open) = `<svg>` / `<math>` 内の ★自己閉じ RAWTEXT。
        #               foreign content では自己閉じが ★正規に閉じる ため実 browser は raw text を ★開かない が、
        #               本 census は set_cdata_mode を ★名前空間非依存 に与えるため raw 区間を開いてしまい、
        #               attacker は末尾の stray end tag で閉じ直せる。 ★実測 fixture (両 arm 同一結果):
        #                 <html><body><svg><script/></svg><div id="INJ"></div><code>zz</code>&lt;span
        #                 </script><div id="tail"></div></body></html>
        #               → IDS=[tail] のみ (INJ ★非計数) / ESC_SPAN=0 / 人間層 code=0 なのに tail は計上され続ける
        #               = ★他 census 値は無傷 の同族 bounded blind spot。 ground truth (html5lib) では INJ の
        #               ancestor chain = ['html','body','div'] = ★実描画。 同型が `<math><style/></math>…</style>` /
        #               `<svg><textarea/></svg>…</textarea>` でも再現 (CDATA / RCDATA 双方)。
        #               ★base c55bac6 でも同一挙動 = pre-existing (folio-ahn3 の退行ではない)。 fix は名前空間
        #               追跡を要する parser semantics の再設計で本 cell の契約 (3 分岐の逐字温存) の外ゆえ
        #               ★folio-3z10 として ★起票済 (admin 裁定 2026-07-21)。 本 cell は ★宣言を実能力へ縮小する
        #               に留める (「全クラス閉塞」と書けば次の cell が探索を打ち切る = false record ゆえ書かない。
        #               「ついでに塞ぐ」も禁止 = 契約 fence 外)。
        m=-1
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0] in INERT: m=i; break
        lo = 0 if m<0 else (m if tag in INERT else m+1)
        for i in range(len(self.stack)-1,lo-1,-1):
            if self.stack[i][0]==tag: del self.stack[i:]; break
src=open(sys.argv[1],encoding='utf-8').read()
w=W(sys.argv[2], sys.argv[3]); w.feed(src)
print(w.n)
PYEOF
}
# JSON-LD folio:stakeholders の型+値 (型\t値・生成物 HTML から抽出)。
ld_stake() { perl -CSD -0777 -ne 'my ($j) = /<script type="application\/ld\+json">(.*?)<\/script>/s; print $j if defined $j;' "$1" \
  | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
v = d.get("folio:stakeholders")
print(type(v).__name__ + "\t" + json.dumps(v, ensure_ascii=False, sort_keys=True))'; }

# ★ORACLE 存在 pin は ★本 Leg では持たない (ORIG 不在が正常・冒頭 ORIG_ABSENT_BY_CONTRACT の注記が理由と射程を開示)。
#   ★[SKIP] 行も出さない: 「対象が在るのに飛ばした」と読めてしまうが実際は ★対象が存在しない (snapshot は mkwc の成果物)。

# ★実態開示 (folio-cuom errata-1 M7 / ceiling advisory A2): 本 census は ★live 要素の occurrence を数えるが、
#   consumer 側 の anchor 述語 (bin/folio の folio_chrome_is_generated_spec 等) は ★substring grep ゆえ、
#   本 census の値は「consumer が拾いうる件数」の ★上界ではない (consumer はより広く当たる)。 census が緑でも
#   consumer 経路が無傷とは言えない — consumer 面の封鎖は §0b の negative assert (div.meta) 側が担う。
# --- (a) literal census: expected = 凍結 literal / subject = 生成物 HTML (ORIG 非消費) ---
# ★census 実測は parser walk 1 回に集約する (計数方式の混在 = parser-differential の温床ゆえ single-source)。
CEN_DUMP="$(mktemp)"
census_dump "$HTML" > "$CEN_DUMP" || { echo "verify-self-spec: ★census parser walk に失敗 (fail-closed): $HTML" >&2; exit 2; }
grep -q '^C_XREF=' "$CEN_DUMP" || { echo "verify-self-spec: ★census parser walk の出力が不正 (fail-closed): $HTML" >&2; exit 2; }
cen()  { grep -m1 "^$1=" "$CEN_DUMP" | sed "s/^$1=//"; }
cen_ids()  { sed -n '/^#IDS$/,/^#DIDS$/p' "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
cen_dids() { sed -n '/^#DIDS$/,$p'        "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
# navigable id census (count + rename SET・deliverable 5)。
g_ids_all="$(mktemp)"; cen_ids > "$g_ids_all"
# D-* (delta 印) は navigable id へ混入禁止 (fail-closed・生成物側で撃つ)。
chk "census navigable id: 生成物の D-* id == 0 (delta 印 anchor 混入を fail-closed に)" "0" "$(grep -c '^D-' "$g_ids_all" || true)"
# ★★提示層 wrapper id の census 除外 (admin 裁定 C2・ADR-0054 §2.2)。 前方照会 / 用語集を section id 付きの章に
#   する決定は navigable id を +2 するが、 これは ★提示層 chrome の追加 であって原本由来 anchor ではない。 凍結
#   census (FZ_ID_COUNT / ID_SET) は原本 anchor の防壁として ★不変に保ち、 この 2 literal ★だけ を肯定形
#   allowlist で除外する (★default-block 維持 = 他の新 id は従来どおり count / SET 双方で FAIL する)。
#   ★期待側を ID_TOTAL-2 のような算術へ書き換える緩和は禁止 (別軸の teeth を殺す)。
#   ★空振り封鎖: 除外した id が生成物に ★実在すること を陽性 assert する (実在しない id を除外し続けて
#   allowlist が形骸化する / 章化が落ちても除外だけ残る、 の両方を封鎖)。 §3 の section anchor 列とも二重。
for _w in "${PRESENTATION_WRAPPER_IDS[@]}"; do
  chk "census: 除外対象の提示層 wrapper id '$_w' が生成物に実在 (allowlist 空振り封鎖)" "1" "$(grep -cxF "$_w" "$g_ids_all")"
done
g_ids="$(mktemp)"; grep -vxF -f <(printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}") "$g_ids_all" > "$g_ids"
# ★count census (frozen literal・subject=生成物・提示層 wrapper 除外後)。
chk "census navigable id: 総数 (提示層 wrapper 除く) == 凍結 $(fz FZ_ID_COUNT)" "$(fz FZ_ID_COUNT)" "$(grep -c . "$g_ids")"
# ★重複 0 の構造的不変条件 (folio-7wbn 3 巡目 ceiling major fix の port・folio-7st6)。 count / SET census は共に dedup 後の
#   unique 集合を見るため ★既存 id の複製注入 (unique 57 保存) を原理的に検出できない。 文書順 first-match の fragment
#   解決ゆえ複製は anchor hijack を起こす。 凍結 literal でなく「unique == 総出現」で撃つ (census file 無改訂)。
#   ★除外前の全 id 集合で撃つ (提示層 wrapper id の複製注入も同じ hijack を起こすため allowlist の外に置かない)。
chk "census navigable id: 重複 0 (unique == 総出現・anchor hijack 封鎖)" "$(cen ID_TOTAL)" "$(grep -c . "$g_ids_all")"
# ★id-rename SET census (deliverable 5): count 保存 substitution (55==55) を見逃さないよう凍結 SET と comm。
FZ_IDS="$(mktemp)"; fz_set ID_SET | LC_ALL=C sort -u > "$FZ_IDS"
chk_empty "census id-rename SET: 生成物にあり凍結 SET に無い余剰 0 (rename / 捏造)" "$(LC_ALL=C comm -13 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
chk_empty "census id-rename SET: 凍結 SET にあり生成物に無い欠落 0 (rename / 脱落)" "$(LC_ALL=C comm -23 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
# ★D-* 混入 0 chk は上で g_ids_all に対して撃っている (allowlist 除外の前 = wrapper 経路での混入も被覆)。
rm -f "$g_ids" "$g_ids_all" "$FZ_IDS"
# ★rich 資産 occurrence (frozen literal・subject=生成物)。
chk "census rich: a.xref occurrence == 凍結 $(fz FZ_XREF)"        "$(fz FZ_XREF)"  "$(cen C_XREF)"
chk "census rich: span.term occurrence == 凍結 $(fz FZ_TERM)"     "$(fz FZ_TERM)"  "$(cen C_TERM)"
chk "census rich: ins|del.delta occurrence == 凍結 $(fz FZ_DELTA)" "$(fz FZ_DELTA)" "$(cen C_DELTA)"
# delta-id SET census (frozen・count 保存 rename を見逃さない)。
G_DID="$(mktemp)"; FZ_DID="$(mktemp)"
cen_dids > "$G_DID"
fz_set DELTA_SET | LC_ALL=C sort -u > "$FZ_DID"
chk_empty "census delta-id SET: 余剰 0 (凍結 SET 対)" "$(LC_ALL=C comm -13 "$FZ_DID" "$G_DID" | tr '\n' ' ')"
# ★★「欠落 0」方向の chk は ★削除した (folio-cuom errata-1 M6・独立 ceiling blocking)。
#   理由: 凍結 DELTA_SET は self-spec では ★空集合 (delta 印 0 件) ゆえ comm -23 空 vs 任意 は ★常に空 =
#   ★0/0 恒真 で teeth を持たない。 残置すると「検査している」と誤読させ、 かつ D8 報告 (「恒真は 1 本のみ」) を
#   ★false record にしていた。 ★非該当を明示する 側 (M5 の 2 択のうち削除側) を採る。
#   ★検出力の穴は開かない: 生成物側に delta 印が現れる形は 上の ★余剰方向 (comm -13) と FZ_DELTA=0 の
#   occurrence pin が撃つ (実弾 = B9「delta marker 注入 → FAIL」)。 凍結 SET が ★非空になる日 (canonical が
#   delta 印を持つ日) には 欠落方向を復活させること (そのときは恒真でなくなる)。
rm -f "$G_DID" "$FZ_DID"
# escape 済 literal 'a class="xref"' (過剰 linkify 禁止・subject=生成物・★text node 限定計数)。
chk "census escape: 'a class=\"xref\"' literal == 凍結 $(fz FZ_ESC_XREF)" "$(fz FZ_ESC_XREF)" "$(cen ESC_XREF)"
# generic inline (code/span) の人間層 region 別 occurrence (frozen・subject=生成物・region 相殺封鎖のため総和も撃つ)。
chk "census generic: 人間層 <code> table-cell == 凍結 $(fz FZ_CODE_TABLE_CELL)" "$(fz FZ_CODE_TABLE_CELL)" "$(h_inline "$HTML" code table-cell)"
chk "census generic: 人間層 <code> caption == 凍結 $(fz FZ_CODE_CAPTION)"       "$(fz FZ_CODE_CAPTION)"    "$(h_inline "$HTML" code caption)"
chk "census generic: 人間層 <code> rest == 凍結 $(fz FZ_CODE_REST)"            "$(fz FZ_CODE_REST)"       "$(h_inline "$HTML" code rest)"
chk "census generic: 人間層 <code> 総数 == 凍結 $(fz FZ_CODE_TOTAL) (region 相殺封鎖)" "$(fz FZ_CODE_TOTAL)" "$(h_inline "$HTML" code human)"
chk "census generic: 人間層 <span> table-cell == 凍結 $(fz FZ_SPAN_TABLE_CELL)" "$(fz FZ_SPAN_TABLE_CELL)" "$(h_inline "$HTML" span table-cell)"
chk "census generic: 人間層 <span> caption == 凍結 $(fz FZ_SPAN_CAPTION)"       "$(fz FZ_SPAN_CAPTION)"    "$(h_inline "$HTML" span caption)"
# double-escape 直接検出 (frozen・subject=生成物・★text node 限定計数)。
chk "census double-escape: &lt;code literal == 凍結 $(fz FZ_ESC_CODE)" "$(fz FZ_ESC_CODE)" "$(cen ESC_CODE)"
chk "census double-escape: &lt;span literal == 凍結 $(fz FZ_ESC_SPAN) (散文中の正当 literal)" "$(fz FZ_ESC_SPAN)" "$(cen ESC_SPAN)"
# jq -S PRESERVE + mask (frozen・subject=生成物)。
chk "census jq-S: 'jq -S' 総出現 == 凍結 $(fz FZ_JQS_TOTAL)" "$(fz FZ_JQS_TOTAL)" \
  "$(perl -CSD -0777 -ne 'my $n=()=(/jq -S/g); print $n;' "$HTML")"
chk "census jq-S: masked <code> == 凍結 $(fz FZ_JQS_MASKED) (P-11 primitive 露出なし)" "$(fz FZ_JQS_MASKED)" \
  "$(perl -CSD -0777 -ne 'my $n=()=(/<code>[^<]*jq -S[^<]*<\/code>/g); print $n;' "$HTML")"
# JSON-LD folio:stakeholders 型+値 (frozen literal・subject=生成物・array 型退行封鎖)。
chk "census JSON-LD: folio:stakeholders 型+値 == 凍結 literal (array 退行封鎖)" \
  "$(fz_ld)" "$(ld_stake "$HTML")"
# ---- ★<pre> 内 inline 資産 census (folio-cuom errata-1 M1・frozen literal・subject=生成物) ----
# ★何を守るか: canonical mermaid の <b>…</b> (9 組 = 18 tag) は 意味を持つ強調ゆえ ★live タグ のまま生成物へ運ぶ
#   (extractor preline が逐語保持 → assemble esc_mermaid が raw 復元)。 この経路の どこか 1 段でも壊れると
#   ★無警告で 18 tag が消える (fork 元の欠陥そのもの)。 §4 の「mermaid source 行列」は ★contract 相対 ゆえ
#   両側同時退行 (extractor が落とす → contract も生成物も同時に痩せる) に ★構造的に全盲 — ゆえ ★凍結 literal で撃つ。
# ★閉集合 で撃つ (count だけでなく tag 名集合ごと): 未対応の inline 資産 (<i>/<em>/<sup> …) が canonical へ入って
#   preline に落とされるクラスを、 生成物側からも fail-closed にする (extractor 側 guard との二重化)。
# ★実 HTML parser で数える (naive regex は属性順・自己閉じ・CSS 中の literal で parser-differential を起こす)。
# ★★open / close を ★別 key で数える (folio-cuom errata-2 M8(1)・ceiling round-2 blocking)。
#   ★旧実装は open+close を ★合算 していたため、 ★不均衡 (`</b>` → `<b>` の入替など総数保存の改竄) が
#   b=18 のまま素通りした。 実害は表示層まで及ぶ: html5lib DOM 実測で 不均衡な <b> は ★adoption agency
#   により <pre> の外へ再構築され、 figcaption / provenance footer まで bold 化した文書が ★全 gate 緑で
#   出荷された (verifier 実弾再現)。 open==close の対応は <b> を live タグで運ぶ規律の前提ゆえ、
#   ★合算でなく 別軸で 凍結する (b_open=9 / b_close=9 の 2 値が独立に動けば必ず落ちる)。
#   ★自己閉じ (<b/>) は HTML Standard で ★非 void 要素の trailing solidus が無視され ★open として扱われる
#   ため _open へ数える (close を伴わない open の増加 = 不均衡として落ちる = ground truth 整合)。
pre_inline_census() { # $1 = HTML → "tag_open=N tag_close=N …" (★open/close 別・key 名昇順・空白区切り 1 行)
  python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
from collections import Counter
import sys
class P(HTMLParser):
    def __init__(s):
        super().__init__(convert_charrefs=True); s.d = 0; s.c = Counter()
    def handle_starttag(s, t, a):
        if t == 'pre': s.d += 1
        elif s.d > 0: s.c[t + '_open'] += 1
    def handle_startendtag(s, t, a):
        # ★非 void 要素の自己閉じは HTML では ★開始タグ = _open へ計上 (close は増えない = 不均衡で落ちる)。
        if s.d > 0 and t != 'pre': s.c[t + '_open'] += 1
    def handle_endtag(s, t):
        if t == 'pre' and s.d > 0: s.d -= 1
        elif s.d > 0: s.c[t + '_close'] += 1
p = P(); p.feed(open(sys.argv[1], encoding='utf-8').read())
print(' '.join('%s=%d' % (k, p.c[k]) for k in sorted(p.c)))
PYEOF
}
chk "census pre-inline: <pre> 内 tag 集合+件数 (★open/close 別) == 凍結 $(fz FZ_PRE_TAGS) (<b> 逐語保持 + 均衡の閉集合 pin)" \
  "$(fz FZ_PRE_TAGS)" "$(pre_inline_census "$HTML")"
# ★<br> → 改行 変換 (M2) の生成物側 pin。 変換を外すと 73 行が失われる = 契約非依存の実弾。
chk "census pre-inline: mermaid pre の総行数 == 凍結 $(fz FZ_PRE_MERMAID_LINES) (<br> 73 の改行化 pin)" \
  "$(fz FZ_PRE_MERMAID_LINES)" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<pre class="mermaid">(.*?)<\/pre>/gs){ my @l=split(/\n/,$1,-1); $n+=scalar(@l); } print $n;' "$HTML")"
rm -f "$HTML_LIVE" "$CEN_DUMP"

if [[ "$NMB_TOTAL" -gt 0 ]]; then
  # ★ORACLE 存在 pin は ★本 Leg では持たない (ORIG 不在が正常・冒頭 ORIG_ABSENT_BY_CONTRACT の注記が理由と射程を開示)。
  command -v jq >/dev/null || { echo "verify-self-spec: jq required (§11 contract round-trip)" >&2; exit 2; }
  LF="$(mktemp)"; RF="$(mktemp)"
  # LEFT: ★政策 A (folio-7n17)。 snapshot / live canonical でなく contract.machine_preamble[] +
  #   sections[].machine_blocks[] (25 block) から document 順に再構成する。 contract の html field は
  #   extract-verification-spec.sh の inner_norm 済 (空白畳み + trim) ゆえ RIGHT の norm 出力と 1:1 で突合する
  #   (folio-7n17 で snapshot LEFT とバイト一致を実測)。 list は items[] を li 単位へ展開 (RIGHT の <li class="mli"> と対称)。
  #   ★両側 contract 由来ゆえ両側同時退行で vacuous になりうる → §10b 凍結 census + extractor-collapse test で塞ぐ
  #     (mandate: (a)(b) は両側 contract 由来ゆえ (c) で塞ぐ)。 本 arm が守るのは assembler バグ (生成物が
  #     contract から乖離・silent drop / 順序入替 / cross-section 誤帰属) の検出。
  yq -o=json '[.machine_preamble[]?, .sections[].machine_blocks[]?]' "$CONTRACT" | jq -r '.[] |
    if .type=="list" then (.items[] | "li\t"+.)
    elif .type=="prose" then "prose\t"+.html
    elif .type=="note" then "note\t"+.html
    elif .type=="demoted" then "demoted\t"+.html
    elif .type=="dl" then "dl\t"+.html
    else "UNKNOWN\t"+(.type//"?") end' > "$LF"
  # RIGHT: 生成物の機械層 block を document 順に再抽出 + inner_norm。 prose/note/li は fold 内で交互に出現しうるため、
  #   型ごとに別 pass で集めず *位置走査* で混在順序を保存する (LEFT と同型・順序付き突合のため必須)。
  #   mli は machine list 専有 class・spec-machine-{prose,note} は machine 専有 component ゆえ live tag のみ抽出。
  perl -CSD -0777 -e '
    local $/; open(my $fh,"<:encoding(UTF-8)",$ARGV[0]) or die; my $B=<$fh>; close $fh;
    sub norm { my ($s)=@_; $s//=""; $s=~s/\s+/ /g; $s=~s/^\s+//; $s=~s/\s+$//; return $s; }
    my @u; my $p=0; my $len=length($B);
    while ($p<$len) {
      my %c;
      if (substr($B,$p)=~/<p data-component="spec-machine-prose" data-audience="machine">/)  { $c{prose}=$p+$-[0]; }
      if (substr($B,$p)=~/<aside data-component="spec-machine-note" data-audience="machine">/) { $c{note}=$p+$-[0]; }
      if (substr($B,$p)=~/<li class="mli">/) { $c{li}=$p+$-[0]; }
      # ★demoted (tr0 / verification): 生成物の spec-machine-demoted を balanced div で inner 一括 norm (RIGHT・LEFT と同型)。
      if (substr($B,$p)=~/<div data-component="spec-machine-demoted" data-audience="machine">/) { $c{demoted}=$p+$-[0]; }
      # ★dl (folio-aduv): 生成物の spec-machine-dl inner を norm (RIGHT・LEFT と同型)。
      if (substr($B,$p)=~/<dl data-component="spec-machine-dl" data-audience="machine">/) { $c{dl}=$p+$-[0]; }
      last unless %c;
      my ($k)=sort { $c{$a}<=>$c{$b} } keys %c; my $at=$c{$k};
      if ($k eq "prose") { substr($B,$at)=~/<p data-component="spec-machine-prose" data-audience="machine">(.*?)<\/p>/s; push @u,"prose\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "note") { substr($B,$at)=~/<aside data-component="spec-machine-note" data-audience="machine">(.*?)<\/aside>/s; push @u,"note\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "dl") { substr($B,$at)=~/<dl data-component="spec-machine-dl" data-audience="machine">(.*?)<\/dl>/s; push @u,"dl\t".norm($1); $p=$at+$+[0]; }
      elsif ($k eq "demoted") { my $sub=substr($B,$at); $sub=~/^<div\b[^>]*>/; my $ol=$+[0]; my $d=0; my $eo=length($sub);
             while ($sub=~/(<div\b[^>]*>|<\/div>)/g){ my $t=$1; my $te=pos($sub); if($t=~/^<div/){$d++}else{$d--; if($d==0){$eo=$te;last}} }
             my $w=substr($sub,0,$eo); my $in=substr($w,$ol,length($w)-$ol-length("</div>")); push @u,"demoted\t".norm($in); $p=$at+$eo; }
      else { substr($B,$at)=~/<li class="mli">(.*?)<\/li>/s; push @u,"li\t".norm($1); $p=$at+$+[0]; }
    }
    print "$_\n" for @u;
  ' "$BODY" > "$RF"
  if diff -q "$LF" "$RF" >/dev/null 2>&1; then
    printf '  [OK]   %-'"$CHKW"'s %s\n' "contract↔生成物 機械層 双方向 順序付き一致 (round-trip)" "$(grep -c . "$LF")"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "contract↔生成物 機械層 不一致 (脱落 / 捏造 / 二重 escape / 改竄 / 順序入替 / cross-section 誤帰属)"
    echo "    --- 順序付き diff (< contract / > 生成物) ---"; diff "$LF" "$RF" | sed 's/^/      /' | head -20
    echo "    --- contract のみ (生成物に脱落) ---"; LC_ALL=C comm -23 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
    echo "    --- 生成物のみ (contract に無い = 捏造/改竄) ---"; LC_ALL=C comm -13 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
    fail=1
  fi
  rm -f "$LF" "$RF"
fi

echo
# ---- gate F: render 健全性 (visual) mermaid pack 展開 (folio-jyfh B 段・helper=render_gate_f)。 mermaid 図を
#      含む生成 HTML (../assets/mermaid.min.js 参照は serve root で /assets/ に正規化解決) を light/dark × 3
#      viewport で render-gate し、 SVG settle polling (最大 15s) で非同期 render を待つ。 vendor は render_gate_f
#      が staging。 fail-closed (violation/crash/settle 不足 = $fail=1)。 SKIP_RENDER=1 で bash floor は SKIP。 ----
render_gate_f "$HTML" "SELF_SPEC_SKIP_RENDER"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 要件/section/block/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
