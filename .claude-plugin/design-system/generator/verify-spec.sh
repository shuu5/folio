#!/usr/bin/env bash
# folio engine B6 (folio-8ct) — spec-pack fabrication-free + 非終端 照会 floor (instance#5 / self-dogfood)
#
# 生成 spec (rules) HTML の *構造* が入力 spec contract から完全に導出されたことを機械検証する floor gate。
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
# usage: verify-spec.sh [--filled <manifest.yaml> | --artifact] <spec-contract.yaml> <generated.html>
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
CONTRACT="${1:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-spec.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-spec: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-spec: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-spec: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-spec: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_core_chrome) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-spec: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-spec: failed to source verify-common.sh" >&2; exit 2; }

# EARS pattern → class / label (assemble-spec.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table「用途」列 SSoT に一致 (folio-2jr drift 是正)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1・assemble-spec と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )
# ============================================================================
# ★ADR-0054 (提示層標準形) lockstep 定数群 — assemble-spec.sh と ★二重保守 (detect↔remediate parity)。
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
# ★集合の拡張には prose manifest / 本 allowlist / assemble-spec.sh の同名配列の ★三点同時更新 が必要 (fail-closed)。
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 ★§番号は literal 固定せず contract の
#   最終 section 見出しから ★導出 する (下記 STATIC_HEADINGS 組み立て)。 assemble-spec.sh と二重保守。
STATIC_HEADING_TAILS=("上位文書への前方照会 — 原則・決定記録・検証仕様へつながる" "本文に出てくる専門語のやさしい説明")
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token 2 つに固定)。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★各 wrapper が包む章帯の tint (assemble-spec.sh build() の band_num 実引数 violet / brand と ★二重保守)。
#   containment の「開口隣接 literal pin」で band の ★同一性 (どの章の帯か) まで逐値要求するために持つ
#   (tint を持たないと「隣に *何らかの* band が在る」しか言えず、 別章 band の付け替えが素通る)。
#   ★契約章 12 本の tint 源は ★contract の sections[].tint ゆえ本配列は wrapper 2 章 ★専用 (両者の長さ一致は
#   駆動表組み立て直前で機械 assert する = 添字 [0]/[1] 前提の lockstep 破れを fail-closed で撃つ)。
PRESENTATION_WRAPPER_BAND_TINTS=("violet" "brand")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2)。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# ★契約非依存 census floor の期待値 (★rules 固有・0/0 恒真封鎖)。 新 field (references[].title /
#   requirements[].priority) と subhead essence は ★all-or-none / optional ゆえ、 契約から一括削除すると
#   「契約側も生成物側も空」で逐値突合が ★0/0 恒真 PASS する。 section class census (11/1) と同型に、
#   生成物の占有数を ★数値 hardcode で pin して封鎖する (relations/verification fork へ literal 流用禁止)。
FZC_RF_GLOSS=36      # 前方照会チップの一行タイトル = |references|
FZC_RQ_PRIO=26       # RFC-2119 優先度バッジ = |requirements|
FZC_RQ_PLAIN=26      # 「やさしく言うと」平易行 = |requirements|
FZC_SUBHEAD_SE=23    # 人間層 1 行要約 (.sub-se) を ★非空 で持つ subhead 数 = |subhead blocks| (空 subsection 0)

fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build spec "$FILLED_MANIFEST"

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
  echo "verify-spec: ★contract sections[].heading に §N 形でない見出しがある (番号導出不能・fail-closed)" >&2
  echo "  headings: $(q '.sections[].heading' | tr '\n' '|')" >&2
  exit 2
fi
SEC_LAST_NUM="$(printf '%s\n' "$SEC_NUMS" | tail -n 1)"
# 静的 2 band (前方照会 / 用語集) は最終 section の §番号の ★次 / ★次々。
STATIC_NUMS=("$((SEC_LAST_NUM + 1))" "$((SEC_LAST_NUM + 2))")
STATIC_HEADINGS=("§${STATIC_NUMS[0]}. ${STATIC_HEADING_TAILS[0]}" "§${STATIC_NUMS[1]}. ${STATIC_HEADING_TAILS[1]}")

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)。
#    chapter-deck-band = section 数 + 2 (references band + glossary band)。
chk "chapter-deck-band == sections + 2"   "$((NSEC + 2))"                  "$(grep -c 'data-component="chapter-deck-band"' "$BODY")"
chk "section-essence-callout == sections" "$NSEC"                          "$(grep -c 'data-component="section-essence-callout"' "$BODY")"
chk "ears-requirement-row == |requirements|" "$NREQ"                       "$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
chk "ears-badge == |requirements|"        "$NREQ"                          "$(grep -c 'data-component="ears-badge"' "$BODY")"
# ★EARS 凡例 (folio-2jr・静的 key): 1 個・5 item・label は EARS_LABEL (= rules.html §6 用途 SSoT) と §6 行順で一致 (assemble-spec と二重保守=parity)。
chk "ears-legend == 1"                    "1"                              "$(grep -o 'data-component="ears-legend"' "$BODY" | wc -l)"
chk "ears-legend-item == 5"               "5"                              "$(grep -o 'data-component="ears-legend-item"' "$BODY" | wc -l)"
# ★folio-bur round-4 (ceiling-recursion R3 是正): 上の count/label列 は double-quote 固定ゆえ single-quote data-component decoy +
#   comment-hidden genuine で EARS 凡例 (意味論) を反転捏造でき素通った (独立 ceiling 実証)。 sec-se/kicker 同型に quote-robust 占有数で封鎖。
exp_legend="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_LABEL[$p]}"; printf '\n'; done)"
act_legend="$(perl -CSD -0777 -ne 'while (/<span data-component="ears-legend-item" class="[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend label 列 == EARS_LABEL (§6 用途 順)" "$exp_legend" "$act_legend"
# ★folio-bur round-5 (ceiling-recursion R4 是正): 上の label 列突合は抽出 regex で class を `class="[^"]*"` ワイルドカードにし
#   色クラス (always/trigger/state/option/forbid=EARS_CLASS[pattern] 由来の決定的フィールド) を drop していた。 要件バッジ (ears-badge) の
#   色は §4 tuple で EARS_CLASS[pat] 突合済なのに、 凡例 (=色の意味の唯一の説明・gate-I 非エンジニア可読の要) の色↔EARS型 対応のみ未検証で、
#   class="always"→"forbid" 等で凡例を任意に反転/均一化でき occupancy/label 順を保ったまま素通った (独立 ceiling 実証・new-category major)。
#   凡例色クラスを EARS_CLASS[pattern] へ §6 順で pin (要件バッジ色との内部整合を保証)。
exp_legend_cls="$(for p in ubiquitous event-driven state-driven optional unwanted; do echo "${EARS_CLASS[$p]}"; done)"
act_legend_cls="$(perl -CSD -0777 -ne 'while (/<span data-component="ears-legend-item" class="([^"]*)">/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend 色クラス列 == EARS_CLASS (§6順・色↔EARS型 反転/均一化封鎖・folio-bur r5)" "$exp_legend_cls" "$act_legend_cls"
# ★凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1): 5 件・EARS_WHEN と §6 順で一致。
chk "ears-legend el-when == 5"            "5"                              "$(grep -o 'class="el-when"' "$BODY" | wc -l)"
# ★folio-bur round-4 (ceiling-recursion R3 是正): el-when (『いつ守るか』平易説明) も double-quote 固定ゆえ single-quote/comment-hidden
#   decoy で『常に守らなくてよい』等の反転が素通った (独立 ceiling 実証)。 quote-robust 占有数で封鎖 (gate-I 北極星=非エンジニア可読の保全)。
exp_when="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_WHEN[$p]}"; printf '\n'; done)"
act_when="$(perl -CSD -0777 -ne 'while (/<span class="el-when">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend el-when 列 == EARS_WHEN (順序)" "$exp_when" "$act_when"
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

# 2. id 一意性 + doc_type
chk_empty "要件 id 一意"     "$(q '.requirements[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "section id 一意"  "$(q '.sections[].id' | sort | uniq -d | tr '\n' ' ')"
chk "doc_type == rules"      "rules" "$(q '.meta.doc_type')"

# 3. section fidelity: 可視 heading 列 (全 NSEC+2 個の h2) == sections[].heading + 静的 band 2 件 (順序) / essence 列 == sections[].essence (順序)。
# ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 まで heading 列は head -n NSEC で先頭 NSEC 個の h2 のみ突合し、
#   末尾 2 band の h2 (references / glossary band) を取りこぼし・総 h2 件数 pin も無く、 band h2 の任意書換え + NSEC 超位置への
#   新規 h2 無制限注入が素通った (独立 ceiling 実証)。 kicker (STATIC_KICKERS) と同型に band h2 を静的リテラルで突合列へ含め、
#   さらに総 h2 件数 == NSEC+2 を case 非依存 count で pin (大文字 <H2> 注入も封鎖)。
# ★ADR-0054 lockstep: 静的 band h2 は「§N. <本文>」形になり、 §N は ★contract 見出しから導出する
#   (旧 literal「rules は照会の終端ではない — 原則・ADR・検証へ前方照会する」は R5 と同クラスの over-promise
#   = 実在しない照会種別の約束でもあった。 rules の実在種別は P-x / ADR / REQ-VER の 3 種)。
STATIC_BAND_H2=("${STATIC_HEADINGS[@]}")
exp_sh="$( { q '.sections[].heading'; printf '%s\n' "${STATIC_BAND_H2[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_sh="$(grep -oE '<h2>[^<]*</h2>' "$BODY" | sed -E 's#<h2>([^<]*)</h2>#\1#')"
chk "section 可視 heading 列 == sections[].heading + 静的 band 2 件 (順序)" "$exp_sh" "$act_sh"
chk "h2 総数 == NSEC+2 (band h2 切詰・大文字注入の盲点是正)" "$((NSEC+2))" "$(grep -oiE '<h2\b' "$BODY" | wc -l | tr -d ' ')"
# ★章帯の巨大番号 == 見出しの節番号 (ADR-0054 §2.2)。 core band() は連番 (01..14) を emit するが、 pack-local
#   wrapper が §番号へ書き換える。 旧版は .num を ★一切 pin していなかったため番号体系の drift が全 gate を素通った。
# ★期待列は hardcode の連番でなく ★見出し自身から導出 した SEC_NUMS + STATIC_NUMS。 これにより「.num と h2 の §N が
#   食い違う」不整合が ★両側 hardcode の同意 に依らず構造的に落ちる。 ★rules は §1 欠番 = 連番と一致しないため
#   「連番 - 1」型の算術 pin では原理的に表現できない (heading 由来がここでは唯一の正しい anchor)。
chk "band .num 列 == 見出しの節番号 (heading 由来・連番でない・ADR-0054 §2.2)" \
  "$(printf '%s\n' "$SEC_NUMS"; printf '%s\n' "${STATIC_NUMS[@]}")" \
  "$(grep -oE '<span class="num">[^<]*</span>' "$BODY" | sed -E 's#<span class="num">([^<]*)</span>#\1#')"
# ★folio-a405: essence_rich=true の section は RAW emit ゆえ raw 逐語 (markup 込み) で突合、 plain は既存 esc。
#   actual は sec-se innerHTML を (.*?) で raw 抽出し expected と ★逐語一致させる (tag-strip 退化 = markup-blind へ退化させない:
#   href/tooltip 改竄は raw 不一致で FAIL・plain field への tag 混入も expected(tag 無し) と不一致で FAIL ゆえ [^<]* の厳格さを保つ)。
exp_se="$(q '.sections[] | ((.essence_rich // false | tostring) + "\t" + .essence)' | while IFS=$'\t' read -r rich v; do
  if [[ "$rich" == "true" ]]; then printf '%s\n' "$v"; else esc "$v"; printf '\n'; fi
done)"
act_se="$(perl -CSD -0777 -ne 'while (/<div data-component="section-essence-callout"><p class="sec-se">(.*?)<\/p><\/div>/gs){ print "$1\n"; }' "$BODY")"
chk "section essence 列 == sections[].essence (順序・rich=raw逐語/plain=esc)" "$exp_se" "$act_se"
# ★kicker 列 fidelity (folio-l93): band() が可視 emit する <span class="kicker"> の §N/トピック ラベルは
#   sections[].kicker 由来の *決定的フィールド* ゆえ doctrine 上 floor (heading/essence と同列の section fidelity)。
#   未突合だと §番号 swap・トピック取り違え・heading の §N との drift が全 gate (floor/persona-walk/fidelity) を素通った (17n ceiling HIGH)。
#   全 NSEC+2 band の kicker を document 順で突合: 先頭 NSEC = sections[].kicker / 末尾 2 = references・glossary band の
#   静的リテラル (assemble-spec.sh build() と二重保守 = detect↔remediate parity)。 静的 2 件も期待列へ含め band 並び替え・
#   静的ラベル drift も lock する (heading は head -n NSEC で section のみだが kicker は全 band を被覆)。
#   抽出: <span class="kicker"><svg ...>…</svg> {esc kicker}</span> の svg 後の可視テキスト ([^<]* = esc 済ゆえ安全)。
STATIC_KICKERS=("この規約が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
exp_kicker="$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_kicker="$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "section kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" "$exp_kicker" "$act_kicker"
# ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 は占有数パリティ (count_attr_token) を mf-label/mf-count のみに適用し、
#   構造的に同一の hide-twin 脆弱性を持つ section 可視コンポーネント (sec-se / kicker) へ未適用だった → genuine を display:none で隠し
#   single-quote class の decoy で捏造要約/§ラベルを描く hide-twin が素通った (独立 ceiling 実証・decoy が class 担持ゆえ folio-4a4 と異なり
#   count_attr_token で捕捉可能)。 sec-se/kicker も占有数パリティで pin (content 突合 + 占有数の二層)。

# ★top-level section anchor 列 (folio-0x0k pre-flip): 原本 <section id="s2-directory"> の実 id を章包み <section id> で再現。
#   要件 anchor (tuple 同梱) / subhead anchor (SUBHEAD_RE) と並ぶ ★3 クラス目の navigable id。 全 section が anchor 保有ゆえ
#   ここは strict (optional でない): 生成物の <section id="…"> 列を document 順で契約 sections[].anchor と突合する
#   (assembler の章包み emit を落とすと section id が消え corpus inbound #s2-directory 等が解決不能 = 件数/順序 FAIL)。
# ★ADR-0054 lockstep: 前方照会 / 用語集を section id 付きの章で包む決定 (admin 裁定 C2) により、 生成物の
#   <section id> 列は「contract sections[].anchor + ★末尾固定 2 wrapper」になる。 wrapper id は番号なし canonical token。
chk "section anchor 列 == sections[].anchor + 提示層 wrapper 2 件 (順序)" \
  "$( { q '.sections[].anchor'; printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<section id="([^"]*)"[^>]*>/g){ print "$1\n"; }' "$BODY")"

# ★section class 列 fidelity (folio-5dad): canonical rules.html §4.4 の section.normative / section.informative wrapper を
#   生成側で保持する (旧版は落としていた欠落を解消)。 class は §10.2 二層 (floor/ceiling) の視覚識別を担う決定的フィールド。
# (i) ★position-sensitive 逐値: 生成物の <section id="…" class="…"> の class 値列を document 順で抽出し、 契約
#   sections[].class 値列 (順序) と逐値一致させる (count/集合/wildcard 禁止・folio-bur verify-spec:73-79 の wildcard 素通り是正)。
#   ★class を持たない section は空値 (契約 // "") として突合列へ含める (yq の // は per-element = 12 行を保つ・実測)。
#   抽出は section wrapper (id 先・class 後) 限定: band の <section data-component ...>(id 無し) と §4.4 escaped 例
#   (&lt;section …&gt;) は <section id=" prefix を持たないゆえ交絡しない。
chk "section class 列 == sections[].class (順序・逐値)" \
  "$(q '.sections[].class // ""')" \
  "$(perl -CSD -0777 -ne 'while (/<section id="[^"]*"([^>]*)>/g){ my $a=$1; if ($a=~/\bclass="([^"]*)"/){ print "$1\n" } else { print "\n" } }' "$BODY")"
# (ii) ★契約非依存 census floor (folio-5dad・0/0 恒真封鎖): 契約 class field 一括削除で (i) の逐値突合は空列==空列で
#   恒真 PASS するため、 生成物の section wrapper class 占有を数値 hardcode で pin する (folio rules 生成出力 = top-level
#   section 12 本 = normative 11 [s2..s12] + informative 1 [s0])。 STATIC_BAND_H2 / STATIC_KICKERS と同じ rules 専用 literal。
#   census grep は '<section id="[^"]*" class="…">' で (a) band の class="tint-*"(id 無し) (b) §4.4 escaped 例
#   (&lt;section class="normative"&gt; = <section id=" prefix 不在) (c) 要件 rq-norm / data-* 属性 を除外する
#   (生 grep class="normative" は escaped 例・rq-norm で過大計数ゆえ禁止)。
chk "section class=normative census == 11 (契約非依存 floor・0/0 恒真封鎖)" "11" \
  "$(grep -oE '<section id="[^"]*" class="normative">' "$BODY" | wc -l | tr -d ' ')"
chk "section class=informative census == 1 (契約非依存 floor・0/0 恒真封鎖)" "1" \
  "$(grep -oE '<section id="[^"]*" class="informative">' "$BODY" | wc -l | tr -d ' ')"
# ★提示層 wrapper (ADR-0054 §2.2 の章化) の陽性 assert 2 本 — (a) 実在すること (章化が落ちれば section anchor 列も
#   FAIL するが、 census の id allowlist 除外が ★空振りしていない ことをここでも独立に固定する)、 (b) class を
#   ★持たないこと (normative/informative census 11/1 へ侵食させない)。 assemble-spec.sh と二重保守。
for _w in "${PRESENTATION_WRAPPER_IDS[@]}"; do
  chk "提示層 wrapper <section id=\"$_w\"> が class 無しで実在 (章化 + census 非侵食)" "1" \
    "$(grep -oE "<section id=\"$_w\">" "$BODY" | wc -l | tr -d ' ')"
done

# ★★章 (契約章 + 提示層 wrapper) の ★containment (章化の ★実質) — 上の陽性 assert (a)(b) と section anchor 列は
#   ★開きタグの実在 しか見ない。 ゆえに <section id="forward-refs"></section> と即閉じ、 band / chapbody /
#   ref-grid を章の ★外 へ押し出す ★hollow section 改竄が ★タグ均衡を保ったまま 全 gate を素通る
#   (★本 pack でも実弾再現済: 開きタグ即閉じ + 対応閉じタグ削除で rc=0 / 0 FAIL)。 章化 (ADR-0054 §2.2) が
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
#   生成物実測への after-the-fact 合わせ (恒真化) にならない。 ★契約章 12 本にも同じ (i)(ii)(iii) を課す
#   (2 id の手書き列挙に留めると同一 DOM shape を持つ残り 12 章が無防備 = partial-enumeration trap。 駆動は contract の section census)。
# ★★rules 固有の構造差 3 点は ★いずれも契約由来導出で吸収される (literal 焼込みをしない): (a) §番号が
#   ★非連番 (§1 欠番 = §0 / §2..§12) — 期待 §番号は contract の heading から導出した SEC_NUMS / 静的 2 band は
#   SEC_LAST_NUM+1・+2 (= §13 / §14) ゆえ「連番 - 1」型の算術 pin では表せない差を構造的に吸収する。
#   (b) s10-mandatory の tint = bad — tint 期待値は contract の sections[].tint を ★そのまま 読むため値域の
#   拡張に非依存。 (c) 契約章が class="normative" / class="informative" の ★2 形 を持つ — containment は
#   section を ★id 属性 だけで同定する (class は見ない) ため 2 形の共存は駆動表へ影響しない。
# ★per-shape mutation-kill (test-adversarial-spec.sh・★全 arm が 1 つ以上の実弾で anchor される):
#   CT1 hollow wrapper / CT2 chapbody だけの押し出し (band 隣接は保持 = 開口隣接 pin は PASS のまま region 側だけ
#   発火) / CT3 用語集 wrapper の hollow 化 (payload 別構造クラス) / CT4 band tint の逐値付け替え (開口隣接 pin の
#   ★識別成分 = tint を単独で撃つ) / CT5 開口への異物挿入 (同 pin の ★位置成分) / CT6 band §番号の逐値書換
#   (同 pin の ★節同一性成分) / CT7 over-containment (wrapper の入れ子化 = region 占有の ★上限側) / CT8 契約章の
#   hollow 化 (2 id 列挙では届かない残り 12 章) / CT9 chapbody 空化 + payload を sibling へ (1 段内側の帰属) /
#   CT10 chapbody 開口への異物挿入 / CT11 hollow ref-grid / CT12 hollow glossary-term-table (payload 2 クラスを
#   ★別実弾 で撃つ) / CT13 コメント密輸 / CT14 script 密輸 / CT15 属性値内 生 `>` 密輸 / CT16 div の自己閉じ構文 /
#   CT17 bogus comment / CT18 escapable RAWTEXT / CT19 ハイフン要素名 / CT20 契約章 band tint 付け替え /
#   CT21 payload container の重複 / CT22 comment end bang (`--!>`) / CT23 abrupt-closing comment (`<!-->`) /
#   CT24 `<!--->` (comment 終端分岐 2 の単独 teeth) / CT25 RAWTEXT 終了タグの要素名境界 (`</textareax>`) /
#   CT26 foreign content (svg subtree) / CT27 契約章の chapbody 空化 + 章本文 sibling 押し出し / CT28 章要旨を
#   残した章本文の relocation (★block 粒度・章直下 2 子の構造 pin) / CT29 章本文の ★band subtree への退避
#   (kids を 2 に保つ向き) / CT30 章本文の ★別章 chapbody への移送 / CT31 章本文の ★machine-fold 内への退避
#   (後 2 者は ★document 順を保ち 他の probe 値を一切動かさない形) / CT38 ★filler 付き machine-fold 退避 /
#   CT39 ★filler 付き兄弟 block (tbl-wrap) subtree 退避 (後 2 者は ★空 <div> 1 個の filler で ★どのレベルの
#   子数も動かさない形 = 「数だけ束縛して identity を束縛しない」errata の per-shape 封鎖) / CT40 ★文字参照で
#   綴った marker (`class="ref&#45;grid"`) による器の重複 (上限型 == arm での silent PASS の封鎖) /
#   CT41 ★attribute-name state への quote 混入 (幽霊 marker の第 2 vector・CT36 は値 state のみ塞ぐ) /
#   CT42 ★タグ境界 quote 走査の state 非同型による ★実在する閉じタグの隠蔽 (`<div class="ref-grid" x=1 "></section>">`
#   の ★1 行で containment 9 arm を全 bypass する形) /
#   CT43 / CT44 / CT45 ★block wrapper の中身の逃がし (rq-list ごと fold へ + 空 filler / tbl-wrap ごと fold へ +
#   空 filler / tbl-wrap 据置で中の table だけ fold へ = 規範要件や表が ★既定折り畳みへ silent 退避 する形) /
#   CT46 / CT47 ★同章内の 器 → 器 payload 再配分 (器 2 本以上の章で 1 本目へ寄せ 2 本目を空の器に = 章合計 pin の
#   構造的死角。 ★rules では 表の器 2 本の s9-xref / 要件リストの器 4 本の s10-mandatory で ★実弾が構成できる —
#   dispatch fence の前提「同型器 2 本以上の章 = 0 件」は本 pack の contract 実測と食い違うため ★実弾を置いた) /
#   CT32 ★void 要素 2 個による ★深さ 1 計数の打ち切り (章本文 relocation のマスク) / CT33 ★foreign root を
#   depth-1 filler にした完全子数マスク / CT34 ★foreign 内の any-other-end-tag (`<svg></section></svg>` =
#   実 parser は外側 section を閉じる) / CT35 ★foreign 内の breakout 開始タグ (svg 内 div.ref-grid = 実 DOM では
#   器が 2 個) / CT37 ★svg 包みによる人間層 block の章外 relocation (CT33/34/35/37 は「foreign subtree を丸ごと
#   読み飛ばす」実装が containment 9 arm を ★1 行で全 bypass させるクラス) / CT36 ★unquoted 属性値への quote 混入
#   (実 DOM に無い ★幽霊 marker を属性逐値一致が数える形・cont / docct / cbadj / pay / tint に横断で効く primitive)
#   — ★kill map (arm → CT) は本 pack の敵対 suite で ★実測して 対応付ける (Leg B の CT 番号への lockstep は無い)。
# ★★「全 arm が実弾で anchor される」の ★射程 (宣言 == 実能力): 上の主張が掛かるのは ★生成物 (artifact) の
#   改竄で落ちる arm だけ である。 ★検査機構そのものの健全性 arm — 「駆動表が全章を覆う」「probe が全章分の
#   実測を出力」 — は artifact をどう改竄しても落ちず (script 改変でしか落ちない)、 敵対 suite の構造上
#   per-shape MK を持てない。 これらは test-adversarial-spec.sh の ★MECHPIN 節 (tracked 静的 pin) が
#   arm の実在と期待値の導出形を押さえる = ★MK 対象外だが担保はリポに残る。
#
# ★★実態開示 (scope・c5r.2 回避表記封鎖の規律): 本 containment pin が閉じるのは ★人間層 (chapbody 直下) の
#   ★block 粒度 relocation クラス で、 かつ ★下の 4 前提 (chk 群直上に逐語) が成り立つ範囲に限る。
#   ★前提 (0) = 「depth-1 marker が文書 census か 器中身 pin のどちらかで個数拘束される」は ★構造上の要 である:
#   rules contract の block type 5 種のうち [table]=div.tbl-wrap / [requirements]=div.rq-list の 2 型は
#   ★wrapper class 自身の文書 census を持たない (census が数えるのは ★内側 の spec-table / ears-requirement-row)
#   ため、 器中身の占有 pin と器自身の文書 census が無いと「空の器を filler に残し中身を machine-fold へ移す」
#   3 shape が ★全 arm 素通り する (Leg B = relations で実測された errata-1 クラス。 本 pack は marker↔census
#   突合を ★実装前に 行い、 census 対を持たない 2 型を最初から BLOCK_WRAPPER_SPEC へ登録して閉じている)。
#   ★射程外 1 = ★機械層 (machine_blocks) の cross-fold 移動 — machine_blocks を
#   ★document 順を保ったまま 別 section の machine-body へ移す形は ★未検査 である (3 レベル pin は fold の内側へ
#   届かず chapbody 直下から見れば fold は 1 要素のまま・機械層 round-trip も順序変化しか見ない)。 ★受け皿 = folio-e706。
#   ★射程外 2 = ★sub-block 粒度 (block の ★内部 のテキスト・要素の移動) — 機械層は逐語 round-trip、 人間層は
#   prose slot 充填 + fidelity ceiling の領分。 「あらゆる relocation を閉じた」とは書かない (宣言 == 実能力)。
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
#   (quote が値を開くのは `=` の直後だけ) 認識して 決定し、 要素名は ★ハイフン込みで 1 語 として取る。
#   占有数も 生テキスト grep でなく ★tokenize 済タグの属性 逐値一致 で数える (属性値に marker 文字列を
#   紛れ込ませた計数水増しの封鎖)。 ★宣言の射程: 属性の走査は タグ名直後から ★attribute-name state →
#   attribute-value state を ★順に消費する 逐次形であり、 ★名前 state は `"` / `\x27` / `<` を ★名前文字として
#   取り込む (HTML5 同型)。 これで 「実 DOM に無い marker を probe が拾う」★幽霊 marker クラス は ★値 state
#   (unquoted 値の char class = `[^\s>]+`・CT36) と ★名前 state (`<div a""class="ref-grid">`・CT41) の
#   ★両方 で塞がる。 ★文字参照 も ★解決する (数値 + 名前付き 6 種・表に無い名前付きは err = fail-closed)。
#   ★undercount を「probe が数え落とす向き = 常に fail-closed 側」と ★一般化してはならない — 期待値が
#   ★上限型 == の arm (docct) では 数え落とし = ★silent PASS である (Leg B で実測 verified・本 pack の CT40 が
#   同 shape を撃つ)。 方向は ★arm の期待値の型に依存する。
#   ★★宣言の射程 (== 実能力): これは「HTML5 parser の ★完全実装」ではない — 本 tokenizer が同型化しているのは
#   ★region 切り出しに効く状態 (上記) + ★属性 name/value state + ★属性値の文字参照 に限られ、 挿入位置補正
#   (in-body insertion mode の implied end tag / foster parenting 等) は ★モデルしていない。
#   それらに依存する差分が将来見つかりうる前提で、
#   genuine assembler が emit しない shape (未閉じ / div・section の自己閉じ構文) は ★err で拒否する
#   fail-closed を併用する (arms race を全面 parser 実装へ広げず、 ★穴が開いたら loud に落ちる 側へ倒す)。
# ★★移植元と ★依存の所在 (false record を作らない): 本 probe は ★範型 verify-verification.sh からの直接
#   移植ではなく、 ★verify-relations.sh (Leg B・folio-3zr4.1 land 済) の probe 一式 — すなわち範型に ★無い
#   7 つの fail-closed を含む形 — を移植元に取っている: (g) タグ境界の attribute state 同型化 + 引用値直後の
#   fail-closed (CT42) (a) count_kids の打ち切りを err (`unclosed-child-*`) へ倒す (CT32) (b) foreign content の
#   stack 追跡 + depth-1 計上 (`foreign-breakout-*` / `foreign-at-depth1-*`・CT33-35/37) (c) $attr の unquoted 値
#   char class 同型化 (CT36) (d) $attr の ★逐次消費化 = attribute-name state 同型 (CT41) (e) 属性値の
#   ★文字参照解決 + 表外参照の err (`unresolved-charref-*`・CT40) (f) chapbody 直下を ★数 でなく ★marker 列 で
#   束縛 (filler 置換 relocation・CT38 / CT39)。 ★裏返しの事実 も開示する: 範型 verify-verification.sh には
#   これらが ★無い ので、 CT32 / CT33-37 / CT38-42 が突く fail-open は ★範型側に残っている。 範型の実態開示
#   コメント (verify-verification.sh:292-301) は 移植 leg の land により段階的に ★stale 化する が、 範型は
#   本 leg の fence で ★1 byte も触れない — ★是正の受け皿 = Leg Z (folio-3zr4.4・admin 単独 commit)。
#   ★開示済み残差 ② — foreign content (svg / math) の ★中 の非同型。 現実装は subtree を ★本体と同じタグ走査で
#   追い、 breakout 開始タグ (%FOREIGN_BREAKOUT) と stack に無い終了タグ を err にするので、 3 vector
#   (svg 内 `</section>` / svg 内 div.ref-grid / svg 包みの章外 relocation) と、 root 計上が ★逆に開けてしまう
#   depth-1 filler マスク (`foreign-at-depth1-*` で対に封鎖) は塞がっている。 ★残るのは 「実 parser が foreign を
#   抜ける 規則のうち 本実装がモデルしていないもの」 = (i) SVG script / MathML annotation-xml の integration
#   point (中身が HTML 名前空間に戻る文脈) (ii) 文字参照 (iii) font の属性条件 (本実装は ★属性を見ずに
#   breakout 扱い = fail-closed 側へ寄せた過剰)。 ★genuine 生成物の svg subtree は path / circle 等の
#   自己閉じのみ (本 pack 実測) ゆえ これらは現時点で ★到達しない が、 「閉じた」ではなく「この範囲で閉じた」と読むこと。
#   ★到達不能な残差の開示 (依存の所在): 属性値内に生 `<` を置く shape は ★上流の make_body が fail-closed で
#   拒否する (raw-lt-in-tag) ため 本走査には到達しない。 ここは「認識しているから安全」ではなく「上流で落ちるから
#   到達しない」であり、 make_body の当該 guard を緩めると ★本走査の前提が崩れる。
#   ★同 (count_kids の打ち切り): count_kids は ★同名深さ計数 ゆえ void 要素が depth-1 に現れると計数がそこで
#   打ち切られる。 これを ★silent に打ち切ると「章本文 block を 1 個 chapbody の外へ出し、 抜けた分の位置に
#   void を 1 個挿す」だけで 3 レベルの完全子数束縛が ★全て素通る。 現在は打ち切りを ★err
#   (`unclosed-child-<要素名>`) へ倒す fail-closed で封鎖している (per-shape MK = CT32)。
#   ★残差の開示: 「void が 0 件だから安全」ではなく「void が現れたら ★loud に落ちる」であり、 depth-1 に
#   void を持つ genuine shape が将来生じたら本 arm は false FAIL 側へ倒れる (その時は要素表の導入が要る)。
# ★★lockstep 相手の開示 (二重保守の所在): 本 pin が依存する DOM marker のうち
#   `data-component="chapter-deck-band"` / `<span class="num">` / `<div class="chapbody">` は ★共有 CORE
#   lib/common.sh の band() / band_end() が emit する形であり、 pack-local な assemble-spec.sh ではない。
#   ★CORE 側でこれらの marker 名が変わると本 pin は (tokenizer が属性一致で数えるため) ★静かに 0 件になり得る
#   — その退行は「駆動表が全章を覆う」「probe が全章分を出力」の 2 arm では捕まらず、 章ごとの adj/band/cb が
#   同時に 0 へ落ちる形で ★loud に FAIL する (16 pack 共有ゆえ CORE 改変は本 cell scope 外 = 検出できれば足りる)。
#   属性値そのもの (tint-<値> / §番号) の lockstep 源は contract (sections[].tint / 見出し §N) と
#   PRESENTATION_WRAPPER_BAND_TINTS。
# ---- containment probe: $BODY を 1 度だけ tokenize し、 章ごとの containment 実測値を KV で返す ----
#   入力 PROBE_SPEC = 1 行 1 章の TSV: id \t §num \t tint(空=不問) \t container 属性 \t 値 \t payload 属性 \t 値
#   出力 = "<id>|<key>=<値>" 行 (found/adj/band/cb/cbadj/cont/pay/docct/kids/bkids/cbkids) + "*|err=<tokenizer 診断>"。
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
      # ★要素名は HTML5 のカスタム要素 (ハイフン入り) を ★1 語として取る。 `[a-zA-Z0-9]*` で切ると `<section-foo>` の
      #   要素名を "section" と誤認し、 実 DOM では別要素のものを ★章の深さに数える (over-slice の 3 本目の vector)。
      if ($win =~ m{^<(/?)([a-zA-Z][a-zA-Z0-9-]*)}) {
        my $cl = $1; my $nm = lc $2;
        # ★タグ境界も HTML5 の tokenizer state に ★同型 に取る (errata 3・本 cell で封鎖): 旧実装は state を
        #   持たず `=` を伴わない `"` も ★quote 開始 として扱ったため、 genuine タグへ ` x=1 "></section>"` を
        #   1 個足すだけで 実 DOM ではそこで閉じる `</section>` を ★quote の中 に隠せた (containment 9 arm の
        #   ★1 行 bypass・Leg B = relations で実測 verified = 封鎖前 rc=0 / 0 FAIL)。 実 parser では before/after-attribute-name
        #   state の `"` は ★属性名文字 (parse error だがタグは閉じない) ゆえ、 その後の最初の `>` が終端する。
        #   state: 0 = attribute-name 側 / 1 = before attribute value (直前が `=`) / 2 = double-quoted value /
        #   3 = single-quoted value / 4 = unquoted value / 5 = after-attribute-value(quoted)。
        #   ★quote が値を開くのは ★state 1 だけ。 unquoted 値中の `"` も ★値の一部 (char class `[^\s>]`) ゆえ
        #   quote を開かない — 下の $attr の ★逐次消費 と同じ規律 (二重保守・CT36 / CT41 と同じ state 観)。
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
        #   見たら err (fail-closed) へ倒す。 per-shape MK = CT34 / CT35。
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
    #   解決する = ★過剰解決 (幽霊 marker) 側へ倒れるため。 per-shape MK = CT40。
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
      #   CT36 が塞いだのは ★attribute-value-unquoted state だけ で、 ★名前 state は開いたままだった。
      #   ★逐次消費なら 名前 state で `"` を名前へ取り込む ので 幽霊 marker クラス自体が閉じる。
      #   per-shape MK = CT36 (値 state) / CT41 (名前 state)。
      # ★unquoted 値の char class も HTML5 の ★attribute-value-unquoted state と同型 (空白 / `>` のみが終端。
      #   `/` は ★値に含まれる) に取る。
      my ($raw, $k) = @_;
      my $s = $raw;
      $s =~ s{^</?[a-zA-Z][a-zA-Z0-9-]*}{} or return undef;
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
          #   depth-1 には void 要素が 0 件 (実測) ゆえ false FAIL は出ない。 per-shape MK = CT32。
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
              #   章 / band / chapbody の深さ 1 には 0 件 (実測) ゆえ、 現れたら loud に落とす。 per-shape MK = CT33。
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
          #   per-shape MK = CT30 / CT31 (数の向き) / CT38 / CT39 (filler 置換の向き)。
          my $cbk2 = $first->($r0, $r1, "div", "class", "chapbody");
          if ($cbk2 >= 0) { my ($q0, $q1) = $region->($cbk2); my @sg = (); $count_kids->($q0, $q1, \@sg); $cbkids = join(",", @sg) }
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
    # ---- XSPEC: ★章 × ★追加の器 (人間層 block の wrapper) の payload 占有 + 器の ★文書総数 ----
    #   入力 PROBE_XSPEC = 1 行 1 (章, 器) の TSV:
    #     key \t section id \t 器要素名 \t 器属性 \t 器値 \t payload 要素名 \t payload 属性 \t payload 値
    #   出力 = "<key>|xcont=<chapbody ★直下 の器数>" / "<key>|xpay=<その器群の ★中 の payload 総数>" /
    #          "<key>|xdoc=<器の ★文書全体 の個数>"。
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
# ★章 census (契約章 12 + 提示層 wrapper 2) を ★1 本の駆動表 にまとめる。 tint 逐値は ★全 14 章に課す —
#   契約章の tint 源は ★contract の sections[].tint (band の class="tint-<値>" と 1:1 対応)、 提示層 wrapper の
#   2 章は assembler literal と二重保守の PRESENTATION_WRAPPER_BAND_TINTS。 持てる逐値を放棄しない (per-shape MK = CT20)。
#   1 段内側 (iii) は ★全 14 章が持つ — wrapper 2 章は payload container (ref-grid / glossary-term-table) と
#   payload 全数、 契約章 12 本は ★章要旨 callout (assembler が chapbody 開口直後に必ず emit する部品) を器に取る。
# ★★chk は ★arm ごとに 1 行 (章ごとに別行へ展開しない): mutation-kill は「その chk 行を消すと敵対 suite が
#   赤くなるか」で測るので、 同じ検査を章別に複製すると per-shape MK が章の数だけ必要になり実効被覆が落ちる。
mapfile -t _SEC_ANCHORS < <(q '.sections[].anchor')
mapfile -t _SEC_NUMLIST < <(printf '%s\n' "$SEC_NUMS")
mapfile -t _SEC_TINTS < <(q '.sections[].tint')
# ★fail-closed: contract の tint が 1 つでも欠けたら「tint 不問」へ ★暗黙に degrade させない (欠落を静かに
#   許すと契約側の tint 削除で本 arm が恒真化する = 0/0 恒真 pin と同じ vacuous-green クラス)。
[[ "${#_SEC_TINTS[@]}" -eq "${#_SEC_ANCHORS[@]}" ]] || { echo "verify-spec: ★contract sections[].tint の件数が anchor と不一致 (${#_SEC_TINTS[@]} != ${#_SEC_ANCHORS[@]}・tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
_CT_ID=(); _CT_NUM=(); _CT_TINT=(); _CT_CA=(); _CT_CV=(); _CT_PA=(); _CT_PV=(); _CT_CLBL=(); _CT_PLBL=(); _CT_PEXP=(); _CT_CEXP=(); _CT_CBEXP=()
# ★contract の block type → chapbody 直下に emit される ★depth-1 marker (要素名 + data-component / class) の対応表。
#   源 = assemble-spec.sh の emit_blocks 分岐 (1 block = ★1 つの depth-1 要素) ゆえ ★二重保守 (lockstep 相手の
#   開示は下の実態開示を参照)。 ★列 (順序つき逐値) で束縛するために「何個か」でなく「何が来るか」を持つ。
#   ★contract に新 type が入って本表に無ければ ★exit 1 (silent skip = 期待値の暗黙短縮 を作らない)。
#   ★本表の鍵集合は assemble-spec.sh emit_blocks の case 分岐 ★8 型と 1:1 (relations fork が持つ subsubhead /
#   ref-primary は assemble-spec.sh に分岐が無い = 登録しない。 契約へ入れば assembler 側が先に
#   「★未対応 block type」で abort し、 仮に assembler が対応しても本表の欠落で exit 1 = 二重の fail-closed)。
declare -A CHAPBODY_KID_MARK=(
  [prose]="p:spec-prose"          [note]="div:spec-note"         [list]="ul:spec-list-block"
  [code]="pre:spec-code"          [table]="div:tbl-wrap"         [mermaid]="figure:spec-diagram"
  [subhead]="div:spec-subhead"    [requirements]="div:rq-list"
)
# ★契約章 12 本の 1 段内側 (iii) は ★章要旨 callout を器に取る。 assemble-spec.sh の emit_section が
#   chapbody 開口の ★直後に必ず 1 個 emit する部品ゆえ、 期待値 (隣接 1 / chapbody 内 1 個 / 文書総数 == NSEC) は
#   ★assembler と contract から決定的に導ける。 これが無いと契約章は「chapbody を空にして章本文を sibling へ
#   押し出す」改竄が 0 FAIL で素通る。
for _k in "${!_SEC_ANCHORS[@]}"; do
  [[ -n "${_SEC_TINTS[$_k]}" && "${_SEC_TINTS[$_k]}" != "null" ]] || { echo "verify-spec: ★contract sections[$_k].tint が空 (tint 逐値 pin の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _CT_ID+=("$(esc "${_SEC_ANCHORS[$_k]}")"); _CT_NUM+=("${_SEC_NUMLIST[$_k]}"); _CT_TINT+=("${_SEC_TINTS[$_k]}")
  _CT_CA+=("data-component"); _CT_CV+=("section-essence-callout"); _CT_PA+=(""); _CT_PV+=("")
  _CT_CLBL+=("章要旨 callout"); _CT_PLBL+=(""); _CT_PEXP+=(""); _CT_CEXP+=("$NSEC")
  # ★chapbody 直下の ★完全子数 を contract から決定的に導く: 章要旨 callout 1 + blocks 各 1 +
  #   machine_blocks があれば fold 1 (assemble-spec.sh の emit_blocks は 1 block = ★1 つの depth-1 要素、
  #   emit_machine_fold は details 1 個)。 ★marker を持たない地の文も contract 上は 1 block ゆえ 1 要素で数えられる。
  #   最小でも 2 (callout + fold) になり ★0/0 恒真にならない。
  _nb="$(q ".sections[$_k].blocks // [] | length")"; _nm="$(q ".sections[$_k].machine_blocks // [] | length")"
  [[ "$_nb" =~ ^[0-9]+$ && "$_nm" =~ ^[0-9]+$ ]] || { echo "verify-spec: ★sections[$_k] の blocks / machine_blocks 件数を導出できない (cbkids 期待値の trust anchor 欠落・fail-closed)" >&2; exit 1; }
  _sig="div:section-essence-callout"; _cnt=0
  while IFS= read -r _bt; do
    [[ -n "$_bt" ]] || continue
    _bm="${CHAPBODY_KID_MARK[$_bt]:-}"
    [[ -n "$_bm" ]] || { echo "verify-spec: ★sections[$_k] の block type '$_bt' が CHAPBODY_KID_MARK に無い (chapbody 完全子列の導出不能・silent skip 禁止・fail-closed)" >&2; exit 1; }
    _sig+=",$_bm"; _cnt=$(( _cnt + 1 ))
  done < <(q ".sections[$_k].blocks // [] | .[].type")
  # ★導出の完全性 (silent drop 封鎖): 列へ積んだ block 数が contract の blocks 件数と一致すること。 一致しないと
  #   期待値が ★実測へ寄る 側 (短い列) へ静かに degrade しうる。
  [[ "$_cnt" -eq "$_nb" ]] || { echo "verify-spec: ★sections[$_k] の block type 列 ($_cnt 件) が blocks 件数 ($_nb) と不一致 (chapbody 完全子列の trust anchor 破れ・fail-closed)" >&2; exit 1; }
  [[ "$_nm" -eq 0 ]] || _sig+=",details:spec-machine-fold"
  _CT_CBEXP+=("$_sig")
done
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[0]}")"); _CT_NUM+=("${STATIC_NUMS[0]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[0]}")
_CT_CA+=("class"); _CT_CV+=("ref-grid"); _CT_PA+=("data-component"); _CT_PV+=("cross-doc-ref-chip")
_CT_CLBL+=("ref-grid"); _CT_PLBL+=("前方照会 chip"); _CT_PEXP+=("$(q '.references | length')"); _CT_CEXP+=("1"); _CT_CBEXP+=("div:ref-grid")
_CT_ID+=("$(esc "${PRESENTATION_WRAPPER_IDS[1]}")"); _CT_NUM+=("${STATIC_NUMS[1]}"); _CT_TINT+=("${PRESENTATION_WRAPPER_BAND_TINTS[1]}")
_CT_CA+=("data-component"); _CT_CV+=("glossary-term-table"); _CT_PA+=("class"); _CT_PV+=("grow")
_CT_CLBL+=("glossary-term-table"); _CT_PLBL+=("用語集 行 (.grow)"); _CT_PEXP+=("$(q '.glossary | length')"); _CT_CEXP+=("1"); _CT_CBEXP+=("div:glossary-term-table")
# ============================================================================
# ★errata-1 (admin gate round-1 blocking): ★block wrapper の中身 の帰属 pin。
#   ★根本原因: 上の chapbody 直下 marker 列 (cbkids) は「何が来るか」を束縛するが ★器の中身 は束縛せず、
#   さらに [table]=div.tbl-wrap / [requirements]=div.rq-list の 2 marker は ★wrapper class 自身の 文書 census を
#   ★持たない (census が数えるのは ★内側 の spec-table / ears-requirement-row)。 ゆえに旧 pin 群は
#   「空の wrapper を正規位置に filler として残し、 中身を machine-fold へ移す」形を ★全て素通していた
#   (Leg B = relations 実測 3 shape・rc=0 / OK 数 baseline 完全一致 = arm skip ではなく ★全素通り。
#   ★本 pack は marker↔census 突合を ★実装前に 機械実行し、 census 対を持たない 2 型 (table / requirements) を
#   最初から BLOCK_WRAPPER_SPEC へ登録している — 同 3 shape の per-shape MK も本 pack の敵対 suite で ★実弾で 撃つ)。
# ★CENSUS_BACKED_MARK = 「器だけ残して中身を逃がす」余地を持たない と宣言する data-component token の逐値集合。
#   ★★errata-4 (admin gate round-1 blocking B1 の是正): 免除の真の根拠は「payload が ★marker に anchor された
#   内容 arm で束縛されている」こと (marker が leaf = 器を成さない) であって「marker が文書 census を持つ」こと
#   ★ではない — 器型 marker では census は器の実在しか拘束せず、 器据置 + payload の fold 退避が ★全 arm 素通り
#   していた (spec-diagram で実弾実証 = 過大宣言)。 ★★errata-5 (round-2 B1p / A-1): anchored 化だけでは ★同型
#   器間の payload 移送 (器を hollow に残し中身を隣の同型器内へ・総数不変・doc 順保存) が平坦連結 byte 不変で
#   素通るため、 複数行 / 複数子 payload の 4 arm (mermaid caption / mermaid source / list / code) へ ★器序数
#   束縛 (期待側 = contract block 序数・実測側 = 器の出現序数を両辺に付加) を追加した。 本集合の全 member の
#   束縛担体: spec-prose / spec-note = marker 込み regex の ★要素単位 内容突合 (corpus 0 件ゆえ実弾未実証・
#   regex が shape-strict の deduced = A-5 開示)、 spec-code = marker 込み regex + ★器序数 (旧宣言「内容突合」は
#   帰属誤り — 器間移送の実閉塞は frozen census 側だった = A-1 是正・per-shape MK = CT52)、 spec-subhead =
#   SUBHEAD_RE (要素単位・器間移送は内容 arm 4 本が捕捉 = 実弾確認済)、 spec-diagram = ★figure 内側限定 +
#   器序数 (errata-4/5・per-shape MK = CT49/CT51)、 spec-list-block = ★ul 内側限定 + 器序数 (contract 0 件の
#   latent を構造是正・実弾構成不能は開示 = A-4)。 occurrence census (errata-3) は ★同一行 filler relocation
#   を塞ぐ ★追加の占有層 であって免除の単独根拠ではない。 depth-1 marker が この集合に ★属さない block type は
#   「器だけ残して中身を逃がす」余地を持つため ★BLOCK_WRAPPER_SPEC の登録を 必須 とする (下の fail-closed)。
#   ★これが partial-enumeration の封鎖: 将来 census 非対応の marker を持つ block type が contract に入ると
#   ★列挙漏れではなく exit 1 で落ちる (「2 本だけ手当てした」で終わらせない)。
#   ★★errata-3 (self-review round-1 blocking・宣言 > 実能力 の是正): 旧版はこの集合を「上の『1. 行数』節が
#   ★文書全体で 個数を数えている token」と定義していたが、 同節の census は ★grep -c = 行単位 であり
#   ★同一行 に marker 付き空 filler を置く形を ★数えない (実弾 verified — 下の β-1 開示に逐語)。 ゆえ
#   ★免除の根拠を ★occurrence 単位 census へ ★一致 させ、 本集合の ★全 member に対して census-count 節が
#   count_attr_token 版 census arm を ★機械生成 する (宣言と arm の lockstep を ★コメントでなく生成で 担保)。
#   ★この生成は marker → block type を CHAPBODY_KID_MARK の ★逆写像 で解くので、 census arm を作れない
#   marker (relations fork の spec-subsubhead / spec-ref-primary のように 本 pack の CHAPBODY_KID_MARK に
#   対応 type を持たないもの) を登録すると ★exit 1 で落ちる — 「census が在る」という ★偽の根拠 で
#   BLOCK_WRAPPER_SPEC 登録義務を免除する ★空文化 が、 コメント上の禁止でなく ★機械で 塞がれる。
declare -A CENSUS_BACKED_MARK=(
  [spec-prose]=1 [spec-note]=1 [spec-list-block]=1 [spec-code]=1 [spec-diagram]=1
  [spec-subhead]=1
)
# ★block wrapper → (器要素名|器属性|器値|payload 要素名|payload 属性|payload 値)。 源 = assemble-spec.sh の
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
  || { echo "verify-spec: ★BLOCK_WRAPPER_TYPES と BLOCK_WRAPPER_SPEC の件数不一致 (lockstep 破れ・fail-closed)" >&2; exit 1; }
for _wt in "${BLOCK_WRAPPER_TYPES[@]}"; do
  [[ -v BLOCK_WRAPPER_SPEC[$_wt] && -v BLOCK_WRAPPER_CLBL[$_wt] && -v BLOCK_WRAPPER_PLBL[$_wt] ]] \
    || { echo "verify-spec: ★BLOCK_WRAPPER_* に型 '$_wt' の定義が欠けている (fail-closed)" >&2; exit 1; }
done
# ★fail-closed: contract に実在する block type のうち depth-1 marker が census 非対応のものは
#   BLOCK_WRAPPER_SPEC に ★登録必須 (登録漏れ = 器の中身が無検査のまま素通る = 本 errata の再発)。
# ★★guard 入力の非空 / 件数 assert (errata-2 should・vacuous guard の封鎖): 下のループは q() が ★空を返すと
#   ★1 度も回らず ★恒真 PASS する (yq 失敗 / contract shape 変化 / 誤 query のいずれでも同じ形で黙る)。
#   ゆえ ★先に配列へ取り、 (a) 非空 (b) 件数が contract の unique 件数と一致 を機械 assert してから回す
#   (負の主張「未登録 type は無い」に ★存在 anchor を対で置く = ehar クラス)。
mapfile -t _BT_ALL < <(q '[.sections[].blocks[]?.type] | unique | .[]')
_BT_N="$(q '[.sections[].blocks[]?.type] | unique | length')"
[[ "${#_BT_ALL[@]}" -gt 0 ]] \
  || { echo "verify-spec: ★contract の block type 列挙が空 (partial-enum guard が恒真化する・fail-closed)" >&2; exit 1; }
[[ "$_BT_N" =~ ^[0-9]+$ && "${#_BT_ALL[@]}" -eq "$_BT_N" ]] \
  || { echo "verify-spec: ★block type 列挙の件数不一致 (${#_BT_ALL[@]} != ${_BT_N}・guard 入力の trust anchor 破れ・fail-closed)" >&2; exit 1; }
for _bt in "${_BT_ALL[@]}"; do
  [[ -n "$_bt" ]] || { echo "verify-spec: ★空の block type が列挙に混入 (fail-closed)" >&2; exit 1; }
  _bm="${CHAPBODY_KID_MARK[$_bt]:-}"; _bmk="${_bm#*:}"
  [[ -n "$_bm" ]] || { echo "verify-spec: ★block type '$_bt' が CHAPBODY_KID_MARK に無い (fail-closed)" >&2; exit 1; }
  [[ -v CENSUS_BACKED_MARK[$_bmk] || -v BLOCK_WRAPPER_SPEC[$_bt] ]] \
    || { echo "verify-spec: ★block type '$_bt' の depth-1 marker '$_bmk' は文書 census を持たず BLOCK_WRAPPER_SPEC 未登録 (器の中身が無検査・fail-closed)" >&2; exit 1; }
done
_XC_KEY=(); _XC_ROW=(); _XC_CLBL=(); _XC_PLBL=(); _XC_SEC=(); _XC_CEXP=(); _XC_PEXP=(); _XC_DEXP=()
for _wt in "${BLOCK_WRAPPER_TYPES[@]}"; do
  IFS='|' read -r _wcn _wca _wcv _wpn _wpa _wpv <<< "${BLOCK_WRAPPER_SPEC[$_wt]}"
  _wtot="$(q "[.sections[].blocks[]? | select(.type==\"$_wt\")] | length")"
  [[ "$_wtot" =~ ^[0-9]+$ ]] || { echo "verify-spec: ★block type '$_wt' の総数を導出できない (fail-closed)" >&2; exit 1; }
  # (1) ★器の文書総数 row (section に一致しない id を渡すので xpay は 0 = chk しない・xdoc だけ使う)。
  #   ★契約に 0 件の型では row を作らない — 「器 0 個」を pin しても ★0/0 恒真 になり teeth を持たないため
  #   (「検査している」と読めるのに実弾で撃てない arm を新設しない・恒常 3)。
  if [[ "$_wtot" -gt 0 ]]; then
    _XC_KEY+=("doc:$_wt"); _XC_ROW+=("doc:$_wt"$'\t'$'\t'"$_wcn"$'\t'"$_wca"$'\t'"$_wcv"$'\t'"$_wpn"$'\t'"$_wpa"$'\t'"$_wpv")
    _XC_CLBL+=("${BLOCK_WRAPPER_CLBL[$_wt]}"); _XC_PLBL+=("${BLOCK_WRAPPER_PLBL[$_wt]}"); _XC_SEC+=("")
    _XC_CEXP+=(""); _XC_PEXP+=(""); _XC_DEXP+=("$_wtot")
  fi
  # (2) ★章ごとの 器の個数 + 器の中の payload 総数 (0/0 恒真封鎖のため ★該当 block を持つ章だけ 行を作る)。
  _wrows=0
  for _k in "${!_SEC_ANCHORS[@]}"; do
    _wn="$(q "[.sections[$_k].blocks[]? | select(.type==\"$_wt\")] | length")"
    [[ "$_wn" =~ ^[0-9]+$ ]] || { echo "verify-spec: ★sections[$_k] の '$_wt' 件数を導出できない (fail-closed)" >&2; exit 1; }
    [[ "$_wn" -gt 0 ]] || continue
    # ★errata-2: payload 期待値は ★器ごとの列 (document 順) — 章合計にしない。 合計だと ★同章内の
    #   器 → 器 再配分 (1 本目へ寄せて 2 本目を空の器として残す) が合計不変で素通る (実測 shape D/D2)。
    #   table = 器 1 個につき table 1 個 ゆえ "1,1,…" (器数分) / requirements = block ごとの ids 数の列。
    _wp=""
    if [[ "$_wt" == "requirements" ]]; then
      while IFS= read -r _il; do
        [[ -n "$_il" ]] || continue
        [[ "$_il" =~ ^[0-9]+$ && "$_il" -gt 0 ]] || { echo "verify-spec: ★sections[$_k] の requirements block の ids 数を導出できない/0: '$_il' (0/0 恒真回避の前提破れ・fail-closed)" >&2; exit 1; }
        _wp+="${_wp:+,}$_il"
      done < <(q ".sections[$_k].blocks[]? | select(.type==\"requirements\") | (.ids | length)")
    else
      for ((_ci=0; _ci<_wn; _ci++)); do _wp+="${_wp:+,}1"; done
    fi
    # ★列の要素数 == 器数 (silent 短縮の封鎖: 期待列が実測へ寄る側へ黙って縮むのを防ぐ)。
    #   ★変数名は _wpn (payload 要素名) と衝突させない — 衝突させると probe へ渡す要素名が数値へ化け
    #   payload が全章 0 になる (実装中に踏んだ実害・fail-closed 側だが原因が読めない形で総崩れする)。
    _wpcnt="$(awk -F, '{print NF}' <<< "$_wp")"
    [[ "$_wpcnt" -eq "$_wn" ]] || { echo "verify-spec: ★sections[$_k] の '$_wt' 期待列 ($_wpcnt 要素) が器数 ($_wn) と不一致 (器ごと期待値の trust anchor 破れ・fail-closed)" >&2; exit 1; }
    _a="$(esc "${_SEC_ANCHORS[$_k]}")"
    _XC_KEY+=("$_a:$_wt"); _XC_ROW+=("$_a:$_wt"$'\t'"$_a"$'\t'"$_wcn"$'\t'"$_wca"$'\t'"$_wcv"$'\t'"$_wpn"$'\t'"$_wpa"$'\t'"$_wpv")
    _XC_CLBL+=("${BLOCK_WRAPPER_CLBL[$_wt]}"); _XC_PLBL+=("${BLOCK_WRAPPER_PLBL[$_wt]}"); _XC_SEC+=("$_a")
    _XC_CEXP+=("$_wn"); _XC_PEXP+=("$_wp"); _XC_DEXP+=("")
    _wrows=$(( _wrows + 1 ))
  done
  # ★fail-closed: 契約に該当 block が在るのに章 row が 1 本も立たない = 駆動表の silent 空振り。
  [[ "$_wtot" -eq 0 || "$_wrows" -gt 0 ]] \
    || { echo "verify-spec: ★block type '$_wt' は契約に $_wtot 件在るのに章 row が 0 本 (駆動表の空振り・fail-closed)" >&2; exit 1; }
done
_PROBE_SPEC=""
for _k in "${!_CT_ID[@]}"; do
  _PROBE_SPEC+="${_CT_ID[$_k]}"$'\t'"${_CT_NUM[$_k]}"$'\t'"${_CT_TINT[$_k]}"$'\t'"${_CT_CA[$_k]}"$'\t'"${_CT_CV[$_k]}"$'\t'"${_CT_PA[$_k]}"$'\t'"${_CT_PV[$_k]}"$'\n'
done
_PROBE_XSPEC=""
for _k in "${!_XC_ROW[@]}"; do _PROBE_XSPEC+="${_XC_ROW[$_k]}"$'\n'; done
_CPROBE="$(PROBE_SPEC="$_PROBE_SPEC" PROBE_XSPEC="$_PROBE_XSPEC" containment_probe)"
_cp() { printf '%s\n' "$_CPROBE" | awk -F'|' -v i="$1" -v k="$2" '$1==i { p=index($2,"="); if (substr($2,1,p-1)==k) { print substr($2,p+1); exit } }'; }
# ★★駆動表の完全性 (partial-enumeration の封鎖): 章 census が ★全章 (contract sections + 提示層 wrapper) を
#   覆っていること・wrapper の id 配列と tint 配列が ★同じ長さ であることを ★機械で 固定する。 添字 [0]/[1] で
#   組み立てているため、 wrapper を 1 本増やして駆動表への追記を忘れると その章だけ containment が ★silent に
#   未検査 になる (「検査している」と読めるのに実際は素通り = vacuous-green クラス)。
[[ "${#PRESENTATION_WRAPPER_IDS[@]}" -eq "${#PRESENTATION_WRAPPER_BAND_TINTS[@]}" ]] \
  || { echo "verify-spec: ★PRESENTATION_WRAPPER_IDS と PRESENTATION_WRAPPER_BAND_TINTS の長さ不一致 (lockstep 破れ・fail-closed)" >&2; exit 1; }
chk "containment 駆動表が全章を覆う (contract sections + 提示層 wrapper・被覆漏れ封鎖)" \
  "$((NSEC + ${#PRESENTATION_WRAPPER_IDS[@]}))" "${#_CT_ID[@]}"
# ★tokenizer の fail-closed 診断 (空でなければ 生成物が genuine な HTML 構造を破っている = 下の全 chk も総崩れする)。
#   per-shape MK は CT16 (div の自己閉じ構文) / CT32 (void 要素による深さ 1 計数の打ち切り) /
#   CT33 (depth-1 の foreign root) / CT34 (foreign の any-other-end-tag) / CT35・CT37 (foreign の breakout 開始タグ)
#   — ★同じ err arm の ★別 vector ゆえ 1 本の実弾は他の穴を証明しない (per-shape 規律 = jyfh / r8k)。
# ★★負の主張には ★存在 anchor を対で置く (ehar クラス): 本 arm は「err が空であること」を主張するが、 probe が
#   ★何も出力しない (関数改名 / 実行失敗 / PROBE_SPEC 空) 場合も空になり ★恒真 PASS する。 probe の出力行数を
#   ★章数から導出した期待値 で pin し、 「検査が走っていない」を「異常なし」と読まない。
chk "containment probe が全章分の実測を出力 (probe 無出力での vacuous PASS 封鎖)" \
  "$(( ${#_CT_ID[@]} * 11 + ${#_XC_KEY[@]} * 2 + 1 ))" "$(printf '%s\n' "$_CPROBE" | grep -c .)"
chk "containment tokenizer の構造診断 (未閉じ / 自己閉じ div,section / 深さ 1 の未閉じ子 / foreign の breakout・depth-1 出現 = 非 genuine shape)" "" "$(_cp '*' err)"
for _k in "${!_CT_ID[@]}"; do
  _s="${_CT_ID[$_k]}"; _tn=""; [[ -z "${_CT_TINT[$_k]}" ]] || _tn=" (tint-${_CT_TINT[$_k]})"
  chk "章 '$_s' の開口直後に §${_CT_NUM[$_k]} 章帯$_tn が隣接 (hollow section 封鎖・開口隣接 pin)" "1" "$(_cp "$_s" adj)"
  chk "章 '$_s' region 内の章帯 == 1 (欠落 / 他章 band の紛れ込み封鎖)" "1" "$(_cp "$_s" band)"
  chk "章 '$_s' region 内の chapbody == 1 (章本文の ★器 の帰属・欠落 / 重複封鎖)" "1" "$(_cp "$_s" cb)"
  # ★★3 レベルの束縛 (章直下 == 2 子 / band 直下 == 4 子 / chapbody 直下 == 契約由来の ★完全子列) が
  #   封鎖するのは ★人間層 (chapbody 直下) の block 粒度 relocation クラス である — 人間層 block を
  #   どこへ動かしても (sibling へ / band の中へ / 別章の chapbody へ / 同章の fold の中へ / 兄弟 block の
  #   subtree の中へ) 章直下・band 直下の ★子数 か chapbody 直下の ★marker 列 が必ず変わる — ★ただし
  #   「block を ★器ごと / ★中身だけ 動かして 空の器を filler として正規位置に残す」形は 列も子数も動かさない
  #   ため ★列 pin だけでは閉じない。 これは下の ★器中身の占有 pin (errata-1) と ★対 で初めて閉じる。
  #   ★★errata (「数」→「列」・宣言 > 実能力 の是正): 旧実装は 3 レベルとも ★子の個数 だけ を束縛しており、
  #   ★どの子か を束縛していなかった。 ゆえに下の 3 前提を ★一切破らない 反例が構成できた — 抜けた位置へ
  #   ★空 <div> を 1 個 filler として挿すと fold 内 / 兄弟 subtree 内への block 退避が ★どのレベルの子数も
  #   動かさず 素通る (Leg B = relations で実測 verified: rc=0 / 0 FAIL・人間層見出しが ★既定非表示の <details> へ
  #   消える形を含む)。 現在は chapbody 直下を ★marker 列 (要素名 + data-component/class の逐値・順序) で
  #   束縛して 無印 filler (`div:-`) を列差で撃つ (CT38 / CT39)。
  #   ★★残差 ③ の開示 (列が束縛するのは ★block の種類の列 であり ★どの block か ではない): (α) ★同種 block
  #   同士の入れ替え (例: 隣接する prose 2 本の順序交換) は列が同一ゆえ ★素通る — 可視テキストの逐値・順序は
  #   prose 側 arm / fidelity ceiling の領分であり 本 pin の射程ではない。 (β) ★marker を持つ空 filler は
  #   ★2 通りに分かれる — ここが admin gate round-1 blocking の ★false record だった箇所である:
  #   (β-1) ★marker 自身が文書 census を持つ type (spec-subhead / spec-diagram / spec-prose / spec-note …) の
  #   ★実閉塞の担い手は marker に anchor された内容 arm (器内限定抽出・退避で内容列が割れる) であり、 occurrence
  #   census は ★同一行 filler relocation を塞ぐ追加層である — ★★errata-4 帰属是正: 旧記述「列 pin と census の
  #   対で閉じる」は ★閉じている member についても帰属が誤り (hollow 実弾で FAIL するのは内容 arm 側・census は
  #   marker 据置なら鳴らない)。 対にできる census は ★occurrence 単位 だけ である点は errata-3 のとおり。
  #   ★★errata-3 (self-review round-1 blocking・宣言 > 実能力 の是正): 旧版はこの閉塞を「1. 行数」節の census
  #   に帰属させていたが、 同節は ★grep -c = 行単位 の数え であり ★同一行 に置かれた marker 付き filler を
  #   ★数えない。 ★実弾 verified: s4-format の §4.4 subhead を machine-fold へ退避させ、 抜けた位置の filler を
  #   §4.3 subhead と ★同一行 に置いた mutant を --filled verify すると rc=1 だが FAIL は ★内容順序 arm
  #   (subhead anchor 列 / heading 列 / essence 列) の ★3 本だけ で、 census arm 『spec-subhead == Σ subhead
  #   blocks』も cbkids 列 pin も ★PASS だった (= 旧開示は ★閉塞の帰属が誤り)。 ★現 corpus では内容順序 arm が
  #   backstop するため ★live fail-open ではない が、 partial-enum guard の免除条件が「★行単位 census の実在」で
  #   足りてしまうと 将来 同型 block が隣接した時点で ★silent に穴が開く (guard の空文化)。 ★現在は
  #   census-count 節が CENSUS_BACKED_MARK の ★全 member について count_attr_token (★occurrence 単位) の census を
  #   ★機械生成 し、 免除条件と実 arm を ★生成で lockstep させる (per-shape MK = CT48。 行単位 arm は
  #   ★削らず additive で二層に残す)。 (β-2) ★marker が wrapper class で 文書 census を持たない type
  #   ([table]=div.tbl-wrap / [requirements]=div.rq-list) は ★census が存在しない ため、 旧版は
  #   「列 pin と census の対で閉じる」と ★一律に 宣言していたが 実際には ★全 arm 素通り だった
  #   (Leg B 実測 3 shape・rc=0 / 0 FAIL = clean と完全一致: rq-list ごと fold へ + 空 filler /
  #   tbl-wrap ごと fold へ + 空 filler / tbl-wrap 据置で中の table だけ fold へ)。 ★現在は
  #   ★器中身の占有 pin と ★器自身の文書 census (器の個数 == contract 由来) を新設して封鎖している
  #   (per-shape MK = CT43 / CT44 / CT45)。 ★どの block type が
  #   どちらに属するかは CENSUS_BACKED_MARK / BLOCK_WRAPPER_SPEC が ★逐値で 宣言し、 census も wrapper spec も
  #   持たない type が contract に入ったら ★exit 1 で落ちる (列挙漏れを「気づかない」から「落ちる」へ)。
  #   ★★errata-2 (「章合計」→「器ごとの列」・admin gate round-2 blocking): 器中身の占有 pin は当初
  #   ★章単位の合計 (depth-1 全器の加算) だった。 合計は ★同章内の 器 → 器 再配分 に対して ★不変 なので、
  #   同型の器が ★2 本以上 ある章 (★rules contract では 表の器 2 本の s9-xref / 要件リストの器 2 本の s9-xref・
  #   4 本の s10-mandatory = contract 実測。 dispatch fence の前提「同型器 2 本以上の章 = 0 件」は本 pack では
  #   ★成り立たない ため実弾を置いた) で「1 本目へ寄せて 2 本目を空の器として
  #   残す」形が ★全 arm 素通り した (Leg B 実測 2 instance: rc=0 / 0 FAIL = ★clean と 1 arm も違わない。
  #   可視には 2 本目の器の表 / 要件が空になり 1 本目の見出し下へ誤帰属する破損が起きる)。 ★現在は期待値を
  #   ★器ごとの個数列 (document 順・contract の per-block 導出 = table は器 1 個につき 1 / requirements は
  #   block ごとの ids 数) にし、 列の ★逐値一致 で束縛する (per-shape MK = CT46 / CT47)。 ★列長が器数を
  #   含意する ため 器の欠落・増殖もこの 1 本で落ちる (器数だけを見る arm は MK を持てないので新設しない)。
  #   ★器 1 本の章は 合計 == 器単位 ゆえ本 shape に構成上 免疫 (撃つ実弾が作れない) — 実弾は 表の器 2 本の s9-xref と
  #   要件リストの器 4 本の s10-mandatory に置く (CT46 / CT47)。
  #   ★この範囲では クラス閉塞が成立する — ただし成立は ★4 つの前提に
  #   依存する と ★明示 する (宣言 == 実能力): (0) 深さ 1 marker の payload が ★marker-anchored 内容 arm +
  #   occurrence census (census-backed 型) か ★器ごとの個数列 pin (wrapper 型) の どちらかで拘束される こと
  #   (上の β-2・errata-1 で新設 / errata-2 で ★章合計から器単位へ是正 / errata-3 で ★行単位 census を根拠に
  #   しない よう occurrence census を機械生成 / errata-4 で ★census 単独根拠の過大宣言を是正し抽出を anchored 化・
  #   未登録 type は fail-closed)。 (1) 深さ 1 の計数が ★打ち切られない こと — void 要素を
  #   depth-1 へ挿す計数マスクは err (`unclosed-child-*`) で fail-closed する (CT32)。 (2) region 切り出しが
  #   ★実 DOM と一致する こと — 旧実装はタグ境界の quote 走査が attribute-value state 限定でなく
  #   `<div class="ref-grid" x=1 "></section>">` 形の閉じタグ隠蔽が ★素通った (実弾 verified) が、 現在は
  #   attribute state 同型化 + 引用値直後の fail-closed で封鎖済 (CT42・上の ★移植元と依存の所在 節)。 ★範型側は未封鎖
  #   (base-pinned の継承・arm drift の所在は同節に開示)。 (3) ★foreign content (svg / math) が
  #   ★実 DOM と同型に 数えられる こと — 旧実装は subtree を丸ごと読み飛ばし foreign root を ★0 子として
  #   扱ったため 「人間層 block を svg で包んで chapbody の外へ出す」形が ★どのレベルの子数も動かさず 素通った
  #   (errata・実測 verified)。 現在は root を ★1 子として計上 し、 depth-1 に foreign root が現れたら
  #   `foreign-at-depth1-*` で fail-closed (計上だけだと ★逆向き の filler マスクが開くため 両者は ★対)、
  #   subtree 内の breakout も err にする (CT33 / CT34 / CT35 / CT37)。 残差は上の ★開示済み残差 ② のとおり。
  #   ゆえ「あらゆる block relocation を閉じた」ではなく ★「上記 4 前提 + 残差 ③(α) の下で」閉じた と読むこと。
  #   射程外 2 種 (機械層 cross-fold 移動 / sub-block 粒度) は上の実態開示のとおり。
  #   ★lockstep 相手の追加開示: chapbody 直下の marker 列は CHAPBODY_KID_MARK (block type → depth-1 marker) を
  #   源に持ち、 その値の SSOT は ★assemble-spec.sh の emit_blocks 分岐 である (pack-local・二重保守)。
  #   assembler 側で marker を変えると本 arm は ★列不一致で loud に FAIL する (silent degrade しない)。
  #   contract に ★未知の block type が入った場合は 期待列を組む前に ★exit 1 (silent skip = 期待値の暗黙短縮 を作らない)。
  chk "章 '$_s' の直下は 章帯 + chapbody の 2 子だけ (章本文の sibling への relocation 封鎖)" "2" "$(_cp "$_s" kids)"
  chk "章 '$_s' の章帯の直下は num/kicker/h2/lead の 4 子だけ (band subtree への退避封鎖)" "4" "$(_cp "$_s" bkids)"
  chk "章 '$_s' の chapbody 直下は 契約由来の完全子列 (別章移送 / fold 退避 / filler 置換の封鎖)" "${_CT_CBEXP[$_k]}" "$(_cp "$_s" cbkids)"
  [[ -n "${_CT_CA[$_k]}" ]] || continue
  chk "章 '$_s' の chapbody 開口直後に ${_CT_CLBL[$_k]} が隣接 (1 段内側の開口隣接 pin)" "1" "$(_cp "$_s" cbadj)"
  chk "${_CT_CLBL[$_k]} が章 '$_s' の chapbody 内に 1 個 (器の外への押し出し封鎖)" "1" "$(_cp "$_s" cont)"
  chk "${_CT_CLBL[$_k]} が ★文書全体で ${_CT_CEXP[$_k]} 個 (器の重複 = payload / 章本文の逃げ場を消す)" "${_CT_CEXP[$_k]}" "$(_cp "$_s" docct)"
  [[ -n "${_CT_PA[$_k]}" ]] || continue
  chk "${_CT_PLBL[$_k]} の ★全数 が章 '$_s' の ${_CT_CLBL[$_k]} 内 (hollow container 封鎖・漏出 0)" "${_CT_PEXP[$_k]}" "$(_cp "$_s" pay)"
done
# ★errata-1: ★block wrapper の中身 の帰属 (admin gate round-1 blocking の封鎖)。 chapbody 直下の marker 列は
#   「器がそこに在る」までしか言わない — 器の ★中身 と 器の ★文書総数 を contract 由来で束縛して
#   「空の器を filler に残し中身を machine-fold へ移す」クラスを閉じる。 per-shape MK = CT43 (A) / CT44 (B) / CT45 (C)。
for _k in "${!_XC_KEY[@]}"; do
  _xk="${_XC_KEY[$_k]}"
  if [[ -n "${_XC_DEXP[$_k]}" ]]; then
    chk "${_XC_CLBL[$_k]} が ★文書全体で ${_XC_DEXP[$_k]} 個 (器自身の文書 census・器ごと別所へ移す形の封鎖)" "${_XC_DEXP[$_k]}" "$(_cp "$_xk" xdoc)"
    continue
  fi
  chk "${_XC_PLBL[$_k]} の ★器ごとの個数列 が章 '${_XC_SEC[$_k]}' の ${_XC_CLBL[$_k]} 群 (chapbody 直下・document 順) と契約由来で一致 (hollow / fold 退避 / ★器間 再配分の封鎖)" "${_XC_PEXP[$_k]}" "$(_cp "$_xk" xpayseq)"
done

# ★folio-0x0k errata E2: self-anchor 整合 — 生成物内の全 href="#x" が同一文書内 id="x" へ解決する (broken self-anchor 封鎖)。
#   canonical 突合の盲点 (contract 突合だけでは href/id の同時欠落・id 単独欠落を見逃す) を閉じる恒久 backstop。 p-anchor s3-vocab-schema
#   (機械層 prose の self-anchor) や section/subhead/subsubhead anchor の drop を href 側から二重に pin する。
#   ★navigable id 抽出は実タグの id 属性のみ (data-req-id / data-delta-id 等の data-* は除外)。
self_href="$(grep -oE 'href="#[^"]+"' "$BODY" | sed 's/href="#//; s/"$//' | LC_ALL=C sort -u)"
self_ids="$(perl -CSD -0777 -ne 'while (/<[a-zA-Z][a-zA-Z0-9]*\b([^>]*)>/g){ my $a=$1; while ($a=~/(?:^|\s)id="([^"]*)"/g){ print "$1\n"; } }' "$BODY" | LC_ALL=C sort -u)"
chk_empty "self-anchor 整合: 全 href=\"#x\" が同一文書内 id へ解決 (broken self-anchor 0)" \
  "$(comm -23 <(printf '%s\n' "$self_href" | grep -v '^$') <(printf '%s\n' "$self_ids" | grep -v '^$') | grep -v '^$' | tr '\n' ' ')"

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
  # ★navigable anchor (folio-0x0k pre-flip): 生成物 row の id= (小文字 req-*) を tuple に *同梱* し「id= が data-req-id (大文字 SSoT)
  #   の置換でなく追加である」ことを 1 本の突合で pin する (両方が同時に等しくなければ FAIL)。 全要件 anchor 保有 = fail-closed。
  anc="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anc" && "$anc" != "null" ]] || { echo "verify-spec: ★contract 要件 $id の anchor が空 (navigable id 不在・fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; }
  # ★contract 由来 pattern が allowlist 外なら expected タプルを :-unknown で組まず fail-closed (assemble validate と parity)。
  # silent な class="unknown" 同士の偽一致 (双辺で同じ fallback を引いて tuple PASS する fail-open) を封鎖。
  if ! [[ -v EARS_CLASS[$pat] ]]; then echo "verify-spec: ★contract 要件 $id の EARS pattern が allowlist 外: $pat (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
  # ★ADR-0054 lockstep: RFC-2119 優先度バッジ class (rq-prio-<level>) + prio/plain の ★per-row slot-id を tuple へ同梱する。
  #   slot-id は要件 anchor から決定的に導く (prio-<anchor> / plain-<anchor>) ため、 ★別 row のバッジ / 平易行を
  #   持ってくる relocation クラス (件数保存) が tuple 突合で FAIL する = per-row 完全束縛。
  #   priority を持たない contract (all-or-none の「無い」側) では badge 自体が emit されないため期待も空にする。
  prio="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
  if [[ -n "$prio" && "$prio" != "null" ]]; then
    if ! [[ -v PRIO_LABEL_OK[$prio] ]]; then echo "verify-spec: ★contract 要件 $id の priority が allowlist 外: $prio (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
    prio_cell="rq-prio rq-prio-$prio\tprio-$(esc "$anc")"
  else
    prio_cell="-\t-"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%b\t%s\t%s\t%s\n' "$(esc "$anc")" "$(esc "$id")" "$(esc "$pat")" "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$prio_cell" "$(esc "$ess")" "plain-$(esc "$anc")" "$(esc "$stmt")"
done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]') > "$EXPF"
RQNS="$RQ_NORM_SUMMARY" RQPK="やさしく言うと" perl -CSD -0777 -ne '
  # ★perl -CSD は ★入力ストリームだけ を UTF-8 decode し %ENV / program text は ★byte のまま。 非 ASCII literal を
  #   regex へ直書きすると decode 済 subject と噛み合わず ★恒常 0-match (= tuple 実体が空 → 常時 FAIL) になる。
  #   env 経由で渡し decode_utf8 してから quotemeta する。
  use Encode qw(decode_utf8);
  # ★canonical dual-audience form (w1f cell-2): row opener に data-audience="human"、 rq-norm に data-audience="machine" を
  #   literal で要求し structured-regex に組み込む (= REQ-DA-STRUCT-1/-4 の構造 anchor を tuple 突合に同梱・属性 drop は row 脱落→件数 FAIL)。
  # ★folio-0x0k: row opener に id="<小文字 navigable id>" を literal 要求 (anchor 脱落 = row 脱落 → 件数 FAIL = fail-closed)。
  # ★ADR-0054: rq-prio バッジ (optional = priority 無し contract では不在) と rq-plain 行 (常在) を ★構造 anchor として
  #   regex へ組み込む。 平易行の ★中身 は prose slot ゆえ tuple では突合せず (mode 依存)、 ★slot-id の per-row 束縛のみ pin する。
  # ★rq-norm の summary は平易ラベルを literal 要求 (旧版は [^<]* の wildcard で ★無警備 だった)。
  my $S=quotemeta(decode_utf8($ENV{RQNS})); my $K=quotemeta(decode_utf8($ENV{RQPK}));
  while (/<div data-component="ears-requirement-row" id="([^"]*)" data-req-id="([^"]*)" data-ears-pattern="([^"]*)" data-audience="human">\s*<div class="rq-head"><span class="rid">([^<]*)<\/span>(?:<span class="([^"]*)" data-prose-slot="priority" data-slot-id="([^"]*)">[^<]*<\/span>)?<span data-component="ears-badge" class="([^"]*)">([^<]*)<\/span><\/div>\s*<p class="rq-essence">([^<]*)<\/p>\s*<p class="rq-plain"><span class="rq-plain-k">$K<\/span><span data-prose-slot="plain" data-slot-id="([^"]*)">[^<]*<\/span><\/p>\s*<details class="rq-norm" data-audience="machine"><summary>$S<\/summary><p class="rq-stmt">([^<]*)<\/p><\/details>/g) {
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

# 4b. ★ADR-0054 §2.2: RFC-2119 優先度バッジ / 「やさしく言うと」平易行 の per-row 束縛と契約非依存 census。
#   ★3 層で撃つ:
#     (i) 契約非依存 census — 生成物の占有数を ★数値 hardcode で pin。 新 field は all-or-none optional ゆえ
#         契約から一括削除すると tuple の期待/実体が同時に空になり ★0/0 恒真 PASS する。 その唯一の FAIL 源。
#     (ii) label↔level 束縛 — バッジの ★可視ラベルは prose slot (人間層 edit-SSoT) が持つため floor は内容を
#         contract と直接突合できない。 代わりに level ごとの ★closed allowlist (PRIO_LABEL_OK) で ★逐値突合 し、
#         level と label が乖離した詐称 (must の行に「推奨」/ must の行に「必須ではない」) を封鎖する。
#     (iii) ★level↔statement 束縛 (契約内不変条件) — (i)(ii) は ★contract の priority を ★根 として突合するため、
#         contract 自身が statement と矛盾する level を宣言していると ★全 gate を素通る。 drift gate は contract から
#         再生成する byte 比較ゆえ contract 側の誤りには ★全盲。 contract は「statement の最初の規範キーワードが
#         level を決める」を ★決定的な導出規則 として明文化しているので機械層で閉じる (宣言能力 == 実能力)。
chk "census: rq-prio バッジ占有 == $FZC_RQ_PRIO (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PRIO" \
  "$(grep -oE '<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">' "$BODY" | wc -l | tr -d ' ')"
chk "census: rq-plain 平易行占有 == $FZC_RQ_PLAIN (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PLAIN" \
  "$(grep -oE '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span>' "$BODY" | wc -l | tr -d ' ')"
# (iii) priority (宣言) vs statement 由来 level (導出) の逐行突合。 ★mode 非依存 (contract だけを読む) ゆえ
#   ARTIFACT/FILLED guard の ★外 に置く。 assemble-spec.sh validate() にも同判定を置き build 時 fail-closed にしている。
# ★導出規則 (assemble-spec.sh と逐語同一・first-modal-wins): statement 中で ★最初に 現れる規範キーワードが level を決める。
#   SHALL|MUST が先 → must / SHOULD のみ → should / SHOULD が先で SHALL|MUST が後 → AMBIGUOUS-BOTH (fail-closed) /
#   皆無 → NO-MODAL (fail-closed)。 ★非対称にする理由 = 封鎖したい詐称 (実体 MUST を should と宣言) は必ず先頭の
#   SHALL|MUST から must が導出されて不一致 FAIL になるため、 緩和は危険でない方向 (主節 MUST + 従属節 SHOULD) に限られる。
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
# (ii) level ごとの期待列 (contract 順) vs 生成物の (class, 可視ラベル) 列。 pre-fill mode (slot 空) では
#      ラベルが空ゆえ ★束縛は適用しない (空 slot は §9 の「全て空」検査が担う)。 filled/artifact のみで撃つ。
if [[ -n "$ARTIFACT" || -n "$FILLED_MANIFEST" ]]; then
  exp_prio="$(while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      p="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
      [[ -n "$p" && "$p" != "null" ]] || continue
      printf '%s\tIN-ALLOWLIST\n' "$p"
    done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))"
  # 生成物側: class 末尾の level と可視ラベルを取り出し、 level ごとの ★closed allowlist に ★逐値 で属するかを判定する。
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
      }' "$BODY")"
  chk "rq-prio: (level, 可視ラベル∈allowlist) 列 == contract priority (順序・label↔level 逐値束縛)" "$exp_prio" "$act_prio"
  # 平易行の ★per-row 非空 (fence: per-row 非空 floor assert)。 §9 の slot 検査は文書全体の集計ゆえ、 どの row の
  #   どの slot が空かを特定しない — row ごとに rq-plain slot の中身が非空であることを直接数える。
  chk "rq-plain: 全 row で平易行が非空 (per-row 非空 floor)" "$NREQ" \
    "$(perl -CSD -0777 -ne 'my $n=0; while (/<span data-prose-slot="plain" data-slot-id="[^"]*">([^<]*)<\/span>/g){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY")"
  chk "rq-prio: 全 row で優先度ラベルが非空 (per-row 非空 floor)" "$FZC_RQ_PRIO" \
    "$(perl -CSD -0777 -ne 'my $n=0; while (/<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">([^<]*)<\/span>/g){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY")"
fi

# 5. block 内容 fidelity (順序突合・silent drop / 値改竄を捕捉)。 全 leaf は esc 済ゆえ [^<]* / perl で安全。
# prose
chk "prose 可視テキスト列 == prose blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="prose") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<p data-component="spec-prose">([^<]*)<\/p>/g){ print "$1\n"; }' "$BODY")"
# note
chk "note 可視テキスト列 == note blocks.text (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="note") | .text' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<div data-component="spec-note"><p>([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
# list 項目 (★errata-4: ul[data-component=spec-list-block] 内側限定へ anchored 化 — 文書横断 grep は器据置の
#   payload 退避に盲目。 contract 0 件の latent を構造是正・A4)
chk "list 項目列 == list blocks.items (順序・器序数束縛)" \
  "$(_ln="$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"; for ((_li=1; _li<=_ln; _li++)); do q "[.sections[].blocks[]? | select(.type==\"list\")][$((_li-1))].items[]" | while IFS= read -r v; do printf '%s\t' "$_li"; esc "$v"; printf '\n'; done; done)" \
  "$(perl -CSD -0777 -ne 'my $i=0; while (/<ul data-component="spec-list-block"[^>]*>(.*?)<\/ul>/gs){ $i++; my $f=$1; while ($f =~ /<li class="lbi">([^<]*)<\/li>/gs){ print "$i\t$1\n"; } }' "$BODY")"
# ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 の uniform sweep は count_attr_token を chrome/legend/cover-meta/fold へ適用したが
#   §5 block-content (subhead/table/code/mermaid) へ未到達で、 同一行 hide-twin (single-quote 可視 decoy + double-quote commented genuine) を
#   content 検査 (double-quote/bare-tag) も占有 (不在) も素通った (独立 ceiling 実証・4 blocker)。 §5 各 component に占有数パリティを追加:
#   count_attr_token は comment 内も数えるゆえ commented genuine が count を inflate し hide-twin を捕捉、 additive decoy も同時に封鎖
#   (genuine spec の本文に HTML comment は 0 個ゆえ comment-hidden 自体が tamper 信号)。 README:418 rtm-summary 先例と同型の二層 (占有 + 値突合)。
# subhead anchor + heading + essence
# ★folio-0x0k pre-flip: h3 に id="<fine section anchor>" を刻む形へ shape 変化。 ★rules は §4.1-4.4 のように原本 id 不在の h3 が
#   実在ゆえ id= は ★optional group (?: id="([^"]*)")? とし、 anchor 空 (§4.1-4.4) と非空を同一 regex で拾う。 本来 anchor を持つ
#   subhead が id を落とす silent id-loss は ★anchor 列突合が捕捉 = fail-closed。 heading/essence は esc 経路 (spec は plain 契約値)。
# ★folio-a405: essence 部を [^<]* → (.*?) へ (§4.5 subhead essence は P-8/REQ-VER-021 xref を raw 保持ゆえ [^<]* が破断し
#   regex 全体が §4.5 に不一致 = anchor/heading 列まで巻き込み FAIL していた)。 heading・anchor は plain 維持 ([^<]*/[^"]* 据置き)。
SUBHEAD_RE='<div data-component="spec-subhead"><h3(?: id="([^"]*)")?>([^<]*)<\/h3><p class="sub-se">(.*?)<\/p><\/div>'
chk "subhead anchor 列 == subhead blocks.anchor (順序・§4.1-4.4 は原本 id 不在で空)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | (.anchor // "")' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/gs){ my $a=defined($1)?$1:""; print "$a\n"; }' "$BODY")"
chk "subhead heading 列 == subhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/gs){ print "$2\n"; }' "$BODY")"
# ★folio-a405: essence_rich=true の subhead は raw 逐語 (markup 込み) 突合、 plain は既存 esc (§4.5 の P-8/REQ-VER-021 保存)。
chk "subhead essence 列 == subhead blocks.essence (順序・rich=raw逐語/plain=esc)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | ((.essence_rich // false | tostring) + "\t" + .essence)' | while IFS=$'\t' read -r rich v; do
     if [[ "$rich" == "true" ]]; then printf '%s\n' "$v"; else esc "$v"; printf '\n'; fi; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/gs){ print "$3\n"; }' "$BODY")"
# ★ADR-0054 §2.2「既定 (人間層) 表示で本文ゼロの見出しを作らない」の契約非依存 census (0/0 恒真封鎖)。
#   rules は §4.2/§4.3/§4.4/§10.2/§11.4 の 5 subsection が essence 空 = 見出しだけの空 subsection だった。
#   ★上の逐値突合は contract から essence を一括削除すると「空 == 空」で恒真 PASS する — 生成物側で
#   ★非空 の .sub-se を持つ subhead 数を数値 hardcode で pin し、 空 subsection への退行を単独で捕捉する。
#   (assemble-spec.sh validate() の subhead essence 全件非空 assert と detect↔remediate parity。)
chk "census: 非空の subhead 1 行要約 == $FZC_SUBHEAD_SE (空 subsection 封鎖・契約非依存 floor)" "$FZC_SUBHEAD_SE" \
  "$(perl -CSD -0777 -ne 'my $n=0; while (/<div data-component="spec-subhead"><h3(?: id="[^"]*")?>[^<]*<\/h3><p class="sub-se">(.*?)<\/p><\/div>/gs){ my $t=$1; $t=~s/\s+//g; $n++ if length($t); } print $n;' "$BODY")"
# table caption / header / cell (全 spec-table 横断・順序)
# ★folio-a405: caption_rich=true の table caption は raw 逐語突合、 plain は既存 esc (§9.1 ADR-0034 / §11.1 ADR-0039)。
#   actual は caption innerHTML を (.*?) で raw 抽出し逐語一致 (tag-strip 退化させない)。 tab 終端 (caption 空) は grep で除外。
chk "table caption 列 == table blocks.caption (順序・rich=raw逐語/plain=esc)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | ((.caption_rich // false | tostring) + "\t" + (.caption // ""))' | grep -v '	$' | while IFS=$'\t' read -r rich v; do
     if [[ "$rich" == "true" ]]; then printf '%s\n' "$v"; else esc "$v"; printf '\n'; fi; done)" \
  "$(perl -CSD -0777 -ne 'while (/<table data-component="spec-table"><caption>(.*?)<\/caption>/gs){ print "$1\n"; }' "$BODY")"
chk "table th 列 == table blocks.headers (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .headers[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<th>[^<]*</th>' "$BODY" | sed -E 's#<th>([^<]*)</th>#\1#')"
# ★folio-a405: cells_rich=true の table (7-gate) の td は raw 逐語突合 (cov-req/xref 保存)、 plain は既存 esc。 各 cell に
#   block の cells_rich flag を tab prefix し per-cell 判定。 actual は td innerHTML を (.*?) で raw 抽出し逐語一致。
chk "table td 列 == table blocks.rows cells (順序・rich=raw逐語/plain=esc)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | (.cells_rich // false) as $cr | .rows[][] | (($cr | tostring) + "\t" + .)' | while IFS=$'\t' read -r rich v; do
     if [[ "$rich" == "true" ]]; then printf '%s\n' "$v"; else esc "$v"; printf '\n'; fi; done)" \
  "$(perl -CSD -0777 -ne 'while (/<td>(.*?)<\/td>/gs){ print "$1\n"; }' "$BODY")"
# mermaid caption + source lines
# ★★errata-4 (B1): figcaption / source の抽出を ★figure[data-component=spec-diagram] 内側限定 へ anchored 化。
#   文書横断抽出は「器据置 + payload の machine-fold 退避」で抽出列が不変のまま ★全 arm 素通り していた
#   (hollow figure 実弾・rc=0/277 OK)。 clean artifact では両抽出は等価 (payload は全て器内に実在) = 回帰なし。
#   per-shape MK = CT49 (hollow figure)。 list 項目 (上) も同根で ul 内側限定へ。
#   ★★errata-5 (round-2 B1p): anchored 化だけでは ★同型器間の payload 移送 (器を hollow に残し中身を隣の
#   figure 内へ・総数不変・doc 順保存) が平坦連結 byte 不変で素通る (実弾 rc=0/277 OK) — 期待側 = contract
#   block 序数 / 実測側 = 器の出現序数を ★両辺に付加 し、 あらゆる器間移送で序数列が割れる形へ (MK = CT51)。
# ★folio-a405: caption_rich=true の figcaption は raw 逐語突合 (§10.2 ADR-0028)、 plain は既存 esc。
chk "mermaid figcaption 列 == mermaid blocks.caption (順序・rich=raw逐語/plain=esc・器序数束縛)" \
  "$(_di=0; while IFS=$'\t' read -r rich v; do _di=$((_di+1)); [[ -n "$v" ]] || continue; printf '%s\t' "$_di"; if [[ "$rich" == "true" ]]; then printf '%s\n' "$v"; else esc "$v"; printf '\n'; fi; done < <(q '.sections[].blocks[]? | select(.type=="mermaid") | ((.caption_rich // false | tostring) + "\t" + (.caption // ""))'))" \
  "$(perl -CSD -0777 -ne 'my $i=0; while (/<figure data-component="spec-diagram"[^>]*>(.*?)<\/figure>/gs){ $i++; my $f=$1; while ($f =~ /<figcaption>(.*?)<\/figcaption>/gs){ print "$i\t$1\n"; } }' "$BODY")"
chk "mermaid source 行列 == mermaid blocks.source_lines (順序・器序数束縛)" \
  "$(_dn="$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')"; for ((_di=1; _di<=_dn; _di++)); do q "[.sections[].blocks[]? | select(.type==\"mermaid\")][$((_di-1))].source_lines[]" | while IFS= read -r v; do printf '%s\t' "$_di"; esc "$v"; printf '\n'; done; done)" \
  "$(perl -CSD -0777 -ne 'my $i=0; while (/<figure data-component="spec-diagram"[^>]*>(.*?)<\/figure>/gs){ $i++; my $f=$1; while ($f =~ /<pre class="mermaid">(.*?)<\/pre>/gs){ my $b=$1; print "$i\t$_\n" for split(/\n/,$b,-1); } }' "$BODY")"
# code 行 (全 spec-code 横断・順序。 ★errata-5: 器序数束縛 — 旧形は行の平坦連結ゆえ 器間移送 (pre を hollow に
#   残し行を隣の code へ融合) が列不変で素通り、 実閉塞は frozen census (corpus 固有 literal) に依存していた =
#   round-2 A-1 の帰属誤りを構造是正。 per-shape MK = CT52)
chk "code 行列 == code blocks.lines (順序・器序数束縛)" \
  "$(_cn="$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"; for ((_ci=1; _ci<=_cn; _ci++)); do q "[.sections[].blocks[]? | select(.type==\"code\")][$((_ci-1))].lines[]" | while IFS= read -r v; do printf '%s\t' "$_ci"; esc "$v"; printf '\n'; done; done)" \
  "$(perl -CSD -0777 -ne 'my $i=0; while (/<pre data-component="spec-code"><code>(.*?)<\/code><\/pre>/gs){ $i++; my $b=$1; print "$i\t$_\n" for split(/\n/,$b,-1); }' "$BODY")"

# ★folio-a405: grafted human 層 xref の DOM 位置 assert (11 本が machine fold/body の *外* に render される構造 pin =
#   form-strict edge の担体 <a class="xref"> が人間層 DOM に生きていることを機械保証)。 ★DOM 構造マスク: data-audience="machine"
#   を持つ details/p/aside/ul/div を -0777 slurp で内側ごとマスク (grep/行 heuristic でなく複数行を跨ぐ祖先鎖判定の近似)。
#   残る human 領域に 11 本の graft href が存在するか (per-href) + 総数 census を pin。 expected は contract 由来固定の href
#   literal (canonical を真値源にしない = d7bq flip 後の self-reference vacuous 防止)。
XREF_HUMAN_FLOOR=11   # ★section-class census (11/1) と別名・別 grep・contract 非依存 hardcode。 §2 P-13 + §4.5 P-8/REQ-VER-021 + §9.1 ADR-0034 + §10.2 ADR-0028 + §11.1 ADR-0039 + 7-gate P-6/P-4/P-3/P-11/P-5 = 11。
# ★folio-a405: mask→census→per-href を perl -0777 で BODY 直接に 1 パス完結する (72KB 級 UTF-8 body を shell 変数へ $()
#   キャプチャ→grep する経路は実測で非決定 count を出した = 巨大 UTF-8 コマンド置換の不安定性ゆえ perl 内で閉じ、 出力は
#   小さい "miss:census" だけ返す)。 DOM 構造マスク: data-audience="machine" を持つ details/p/aside/ul/div を内側ごとマスク
#   (grep/行 heuristic でなく複数行を跨ぐ祖先鎖判定の近似)。 href literal は contract 由来固定 (canonical を真値源にしない =
#   d7bq flip 後の self-reference vacuous 防止)。 census floor は section-class census 11/1 とは別軸の独立 floor (0/0 恒真封鎖)。
xref_human_res="$(perl -CSD -0777 -e '
  local $/; my $b = <>;
  1 while $b =~ s{<(details|p|aside|ul|div)\b[^>]*\sdata-audience="machine"[^>]*>.*?</\1>}{}gs;
  my @want = ("./constitution.html#p-13","./constitution.html#p-8","./verification.html#req-ver-021",
              "../decisions/ADR-0034-object-term-xref-system.html","../decisions/ADR-0028-prose-gate-mechanization.html",
              "../decisions/ADR-0039-presentation-template-layer.html",
              "./constitution.html#p-6","./constitution.html#p-4","./constitution.html#p-3","./constitution.html#p-11","./constitution.html#p-5");
  my $census = 0; $census++ while $b =~ /<a class="xref"/g;
  my $miss = 0;
  for my $h (@want) { my $needle = "<a class=\"xref\" href=\"$h\""; $miss++ unless index($b, $needle) >= 0; }
  print "$miss:$census";
' "$BODY")"
xref_human_miss="${xref_human_res%%:*}"
xref_human_census="${xref_human_res##*:}"
chk "grafted xref 11 本が human 層 (machine fold/body 外) に全存在 (DOM 構造マスク後・per-href)" "0" "$xref_human_miss"
chk "human 層 xref census == $XREF_HUMAN_FLOOR (別名 floor・contract 非依存・0/0 恒真封鎖)" "$XREF_HUMAN_FLOOR" "$xref_human_census"
# ★essence 3 本 (P-13/P-8/REQ-VER-021) は ★該当 section 内の sec-se/sub-se に render される per-section 位置固定 (別 field/別
#   section への重複 graft = FAIL)。 section id (s2-directory / s4-format) を anchor に含め、 「任意 sec-se に P-13 があれば PASS」
#   の緩い判定を封鎖する (別 section の sec-se が無傷なら PASS してしまう穴を塞ぐ・folio-a405 RX8 が isolate)。
ess_xref_pos=1
perl -CSD -0777 -ne 'exit(($_ =~ /<section id="s2-directory"[^>]*>.*?<p class="sec-se">[^<]*<a class="xref" href="\.\/constitution\.html#p-13"/s) ? 0 : 1)' "$BODY" || ess_xref_pos=0
# ★folio-a405 errata-1 (should-3): §2 sec-se ([^<]* tight) と対称の tight 形へ。 sub-se 内 P-8→REQ-VER-021 の間を [^<]*</a>[^<]*
#   で厳密化し、 .*? /s の段落跨ぎ緩さ (xref 前への inline 挿入を吸収し RX13 を素通りさせる) を封鎖する。 P-8 が sub-se の最初の
#   tag・その </a> 後テキスト・REQ-VER-021 開始 を連続で pin (§4.1-4.4 の p-8 無し sub-se は前半 .*? がバックトラックで跨ぐ)。
perl -CSD -0777 -ne 'exit(($_ =~ /<section id="s4-format"[^>]*>.*?<p class="sub-se">[^<]*<a class="xref" href="\.\/constitution\.html#p-8"[^<]*<\/a>[^<]*<a class="xref" href="\.\/verification\.html#req-ver-021"/s) ? 0 : 1)' "$BODY" || ess_xref_pos=0
chk "essence 3 本 (P-13 §2 sec-se / P-8+REQ-VER-021 §4 sub-se) が該当 section 内 render (per-section 位置固定・別 field graft 封鎖)" "1" "$ess_xref_pos"

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
# ★契約非依存 census (0/0 恒真封鎖): references[].title を contract から一括削除すると上記突合は「両側 title 空」で
#   恒真 PASS する。 chip の一行タイトル占有を数値 hardcode で pin する (rules 固有値・他 fork へ流用禁止)。
chk "census: rf-gloss (照会先の一行タイトル) 占有 == $FZC_RF_GLOSS (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RF_GLOSS" \
  "$(grep -oE '<span class="rf-gloss">' "$BODY" | wc -l | tr -d ' ')"

# 7. cover-meta 4 KV 再導出突合。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 章の数 == |sections|章"   "$NSEC 章"               "$(printf '%s\n' "$meta_kv" | grep -F '章の数' | head -1 | cut -f2)"
chk "cover-meta 規範要件 == |requirements|件" "$NREQ 件 (EARS)"      "$(printf '%s\n' "$meta_kv" | grep -F '規範要件' | head -1 | cut -f2)"
chk "cover-meta 用語 == |glossary|語"     "$(q '.glossary | length') 語" "$(printf '%s\n' "$meta_kv" | grep -F '用語' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date"          "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4"             "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"
# ★folio-bur round-4 (ceiling-recursion R3 是正): meta_kv / 総数==4 は double-quote 固定ゆえ single-quote KV decoy + comment-hidden
#   genuine で contract 由来統計 (章の数/規範要件/用語/版) を floor 通過で捏造でき素通った (floor-confirmed・独立 ceiling 実証)。
#   research/adr/testcases (l') と同型に quote-robust count_attr_token で KEY span を数える。

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
SEC_WITH_MB="$(q '[.sections[] | select((.machine_blocks // []) | length > 0)] | length')"
EXP_FOLD="$SEC_WITH_MB"; [[ "$NPRE" -gt 0 ]] && EXP_FOLD="$((SEC_WITH_MB + 1))"
chk "spec-machine-prose == Σ machine prose"  "$MB_PROSE" "$(grep -c 'data-component="spec-machine-prose"' "$BODY")"
chk "spec-machine-note == Σ machine note"    "$MB_NOTE"  "$(grep -c 'data-component="spec-machine-note"' "$BODY")"
chk "spec-machine-list == Σ machine list"    "$MB_LIST"  "$(grep -c 'data-component="spec-machine-list"' "$BODY")"
chk "machine li (mli) == Σ machine list items" "$MB_LI"  "$(grep -c 'class="mli"' "$BODY")"
chk "spec-machine-fold == sections(mb) + preamble" "$EXP_FOLD" "$(grep -c 'data-component="spec-machine-fold"' "$BODY")"
# ★ADR-0054 §2.2 lockstep: machine fold の kicker は ★平易語 (旧「機械層 (machine-readable)」= 非エンジニアに不読)。
#   全 fold が同一 literal を持つ (件数 == fold 数) ことを撃つ = 一部だけ旧ラベルへ戻る drift も捕捉する。
chk "machine fold の mf-kicker 平易ラベル == 全 fold ($EXP_FOLD 件・ADR-0054 §2.2)" "$EXP_FOLD" \
  "$(grep -oF "<span class=\"mf-kicker\">$(esc "$MF_KICKER")</span>" "$BODY" | wc -l | tr -d ' ')"
# ★同上: 要件 normative fold の summary 平易ラベル。 §4 tuple regex も literal 要求しているが、 tuple は
#   ★contract 由来 row のみを見る — ここでは文書全体の占有数で撃ち、 二重に固定する。
chk "要件 normative fold の summary 平易ラベル == |requirements| (ADR-0054 §2.2)" "$NREQ" \
  "$(grep -oF "<summary>$(esc "$RQ_NORM_SUMMARY")</summary>" "$BODY" | wc -l | tr -d ' ')"

echo
echo "--- census-count (blocking arm・folio-jmmk): 容器 block / machine list 部品の source DOM 静的件数 == contract 期待件数 ---"
# 機械/LLM 境界 (verification §3.9) の render 非依存 blocking 件数照合。 count_attr_token (quote 構文・属性名 case・数値
# 文字参照 非依存の occurrence 数え = SRS 499ab7b census-count arm と同規律) で data-component トークン件数を数え、 期待値は
# contract から自己導出 (DOM 非参照・contract-anchor)。 内容の順序値 chk (list=items / code=lines / table=cell / machine
# round-trip) は容器 block の *境界/個数* を 1:1 で守らない (空 block 追加・block 分割/併合が順序値を素通る) ため占有 pin
# (folio-bur) が唯一 anchor。 本 arm は占有 pin de-scope (Phase C) 後も同強度で件数照合を継承する static 後継 (sweep 分類表
# = folio-3d23【B2 占有pin sweep 成果物】の第 1 層無し唯一 anchor)。 spec-machine-fold は下記 mf-label/mf-count 順序値 chk が
# fold 件数を並存して守る (第 1 層あり=冗長) ため census-count arm 対象外 (sweep 表の唯一 anchor 判定に従う)。
chk "census-count: spec-list-block == |list blocks|"            "$(q '[.sections[].blocks[]? | select(.type=="list")] | length')"   "$(count_attr_token data-component spec-list-block < "$BODY")"
chk "census-count: spec-code == |code blocks|"                  "$(q '[.sections[].blocks[]? | select(.type=="code")] | length')"   "$(count_attr_token data-component spec-code < "$BODY")"
chk "census-count: spec-table == |table blocks|"                "$(q '[.sections[].blocks[]? | select(.type=="table")] | length')"  "$(count_attr_token data-component spec-table < "$BODY")"
chk "census-count: spec-machine-list == |machine list blocks|"  "$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | map(select(.type=="list")) | length')" "$(count_attr_token data-component spec-machine-list < "$BODY")"

# ★★errata-3 (self-review round-1 blocking・β-1 の false record 是正): containment の partial-enum guard は
#   depth-1 marker が CENSUS_BACKED_MARK に属することを ★BLOCK_WRAPPER_SPEC 登録義務の免除根拠 にしている。
#   その根拠は ★occurrence 単位 census でなければ成立しない — 「1. 行数」節の census は ★grep -c = 行単位 で、
#   ★同一行 に置いた marker 付き空 filler を ★数えない (実弾 verified: §4.4 subhead を machine-fold へ退避させ
#   filler を §4.3 subhead と同一行に置いた mutant で 当該 census arm は ★PASS のままだった)。 ゆえ
#   ★CENSUS_BACKED_MARK の 全 member について occurrence 単位 census を ★機械生成 し、 宣言と arm を
#   ★生成で lockstep させる (免除条件 == 実 arm。 上の census-count 4 本 / 行単位 arm は ★削らず additive)。
#   ★marker → block type は CHAPBODY_KID_MARK の ★逆写像 で決定的に解く (対応 type を持たない marker を
#   登録したら exit 1 = 「census が在る」偽根拠での免除を機械で封鎖)。 ★contract 件数 0 の型でも arm を出す —
#   実測側は ★文書の実占有 ゆえ「marker 付き filler を 1 個増やす」形が 0 vs 1 で落ちる (0/0 恒真ではない・
#   敵対 suite の CC-list seed と同型・tracked 実弾 = CT50)。 per-shape MK = CT48 (★family 単位 = 本生成 loop
#   全体の担い手)。 ★A1 開示 (errata-4): 生成 arm のうち spec-code / spec-list-block の 2 本は既存 census-count
#   arm (上) と期待/実測式が等価の ★意図的冗長 (一様生成が lockstep 成立の前提ゆえ member を間引かない)。
#   当該 2 本の arm 単独 MK は reason-anchor 基準では構成可能 (round-2 実測・A-2 是正) だが、 家系の担い手と
#   しては family 単位 (CT48/CT50) を正とする — 実効的な新規 teeth は prose / note / diagram / subhead の 4 本。
declare -A _MARK2TYPE=()
for _m2t in "${!CHAPBODY_KID_MARK[@]}"; do
  _m2k="${CHAPBODY_KID_MARK[$_m2t]#*:}"
  [[ -z "${_MARK2TYPE[$_m2k]:-}" ]] \
    || { echo "verify-spec: ★depth-1 marker '$_m2k' が複数の block type に対応 (逆写像が一意でない・occurrence census の帰属が決まらない・fail-closed)" >&2; exit 1; }
  _MARK2TYPE[$_m2k]="$_m2t"
done
_OCC_N=0
while IFS= read -r _cbm; do
  [[ -n "$_cbm" ]] || { echo "verify-spec: ★CENSUS_BACKED_MARK に空 marker が混入 (fail-closed)" >&2; exit 1; }
  _cbt="${_MARK2TYPE[$_cbm]:-}"
  [[ -n "$_cbt" ]] \
    || { echo "verify-spec: ★CENSUS_BACKED_MARK の marker '$_cbm' に対応する block type が CHAPBODY_KID_MARK に無い (occurrence census を生成できない = 免除根拠の trust anchor 破れ・fail-closed)" >&2; exit 1; }
  _cbe="$(q "[.sections[].blocks[]? | select(.type==\"$_cbt\")] | length")"
  [[ "$_cbe" =~ ^[0-9]+$ ]] \
    || { echo "verify-spec: ★block type '$_cbt' の contract 件数を導出できない (occurrence census の期待値 trust anchor 欠落・fail-closed)" >&2; exit 1; }
  chk "census-count(occurrence): $_cbm == |$_cbt blocks| (行単位 census が数えない ★同一行 filler の封鎖)" "$_cbe" "$(count_attr_token data-component "$_cbm" < "$BODY")"
  _OCC_N=$((_OCC_N + 1))
done < <(printf '%s\n' "${!CENSUS_BACKED_MARK[@]}" | LC_ALL=C sort)
# ★生成数の lockstep (arm が 1 本も出ない / 一部だけ出る形での ★恒真化 封鎖)。 ★errata-4 文言是正 (A3): 空の
#   連想配列でも printf は空行を 1 本吐くため上のループは ★1 周し、 空 marker guard (上) で exit 1 する —
#   「0 周回で恒真 PASS」ではない (実能力は宣言より厳しい側)。 本 assert は上流 2 guard を同時に外した場合の
#   ★第 3 の防衛線 (dead code ではない・実弾確認済。 その経路で実際に発火する連言は件数不一致側 = A-3 是正)。
[[ "$_OCC_N" -eq "${#CENSUS_BACKED_MARK[@]}" && "$_OCC_N" -gt 0 ]] \
  || { echo "verify-spec: ★occurrence census arm の生成数 ($_OCC_N) が CENSUS_BACKED_MARK 件数 (${#CENSUS_BACKED_MARK[@]}) と不一致 / 0 (免除条件と実 arm の lockstep 破れ・fail-closed)" >&2; exit 1; }

# ★folio-bur: machine fold summary の可視 echo (mf-label heading / mf-count per-fold 件数)。 fold 件数 (EXP_FOLD) は
#   上で pin 済だが、 各 fold の summary ラベル (heading echo) と per-fold 件数は contract へ未束縛で、 §N heading の捏造・
#   per-fold 件数の捏造が素通った (folio-bur audit 実証の 2 穴・visible-text-vs-attribute / orphan-or-count)。
# (a) mf-label: preamble 固定ラベル + mb>0 section の "{heading} の地の文・運用説明・rationale" (document 順)。
exp_ml_bur="$( { [[ "$NPRE" -gt 0 ]] && echo "文書前文 (この規約集の位置づけ)"; q '.sections[] | select((.machine_blocks // []) | length > 0) | .heading' | while IFS= read -r h; do printf '%s の地の文・運用説明・rationale\n' "$h"; done; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_ml_bur="$(grep -oE '<span class="mf-label">[^<]*</span>' "$BODY" | sed -E 's#<span class="mf-label">([^<]*)</span>#\1#')"
chk "machine fold: mf-label 列 == preamble固定 + section(mb).heading+suffix (順序)" "$exp_ml_bur" "$act_ml_bur"
# (b) mf-count: preamble 件数 + 各 mb>0 section の machine_blocks 件数 (document 順・"N 件")。
exp_mc_bur="$( { [[ "$NPRE" -gt 0 ]] && echo "$NPRE 件"; q '.sections[] | (.machine_blocks // []) | length' | while read -r n; do [[ "$n" -gt 0 ]] && echo "$n 件"; done; } )"
act_mc_bur="$(grep -oE '<span class="mf-count">[^<]*</span>' "$BODY" | sed -E 's#<span class="mf-count">([^<]*)</span>#\1#')"
chk "machine fold: mf-count 列 == preamble + section(mb) per-fold 件数 (順序)" "$exp_mc_bur" "$act_mc_bur"
# ★folio-bur round-2 (ceiling-recursion 是正): 上の可視 chk は double-quote 固定 grep ゆえ genuine を display:none で隠し
#   single-quote/extra-attr の可視 decoy を描く hide-twin で素通る (独立 ceiling 実証)。 mf-label/mf-count は対応属性の無い
#   可視専用 chrome ゆえ占有数パリティ層が必須。 count_attr_token で全 quote 形を数え decoy の +1 を捕捉 (二層目)。

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
#     ★政策 A (folio-7wbn / ADR-0053 §2.6 rules arm): LEFT を snapshot でも live canonical でもなく
#     ★contract.machine_preamble[] + sections[].machine_blocks[] (74 block = prose46/note18/list10) から再構成する。
#     旧版は原本 (既定 = live canonical design-intent/spec/rules.html) を直 grep して LEFT にしていたが、
#     folio-d7bq flip 後は canonical == 生成物 ゆえ ★自己比較恒真化する。 政策 A では LEFT を edit-SSoT
#     (contract) 由来へ re-home した。 RIGHT は生成物の機械層。
#     ★demoted / dl 分岐は移植しない (rules contract に当該 type 不在 = 空撃ち arm を作らない)。
#     双方向 (完全性 = contract の全機械層が生成物に / no-fabrication = 生成物の機械層が全て contract に) を照合する。
#     ★順序付き (集合でない): 両側を sort せず document 順の配列のまま diff する (人間層 §4/§5 と対称)。
#       - 順序保存: 機械層 block の document 順を enforce → 同型 block の入替を捕捉。
#       - section 帰属: machine_blocks[] は section ごとに連続して emit される (build()/emit_section) ため、
#         ある block を別 section の fold へ移すと document 順が contract 順とずれる → cross-section 誤帰属も検出。
#     ★本 arm が守るのは assembler バグ (生成物が contract から乖離): silent drop / 順序入替 / cross-section 誤帰属 /
#       二重 escape。 ★両側 contract 由来ゆえ ★両側同時退行 (extractor collapse) では vacuous PASS しうる →
#       §10b 凍結 census + extractor-collapse 敵対 test (test-adversarial-spec.sh COLLAPSE 群) が塞ぐ。
# ============================================================================
NMB_TOTAL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | length')"
# ★ORIG (snapshot) = 政策 A で census / round-trip の【非消費】へ転換 (bootstrap 記録として残置)。 §10b / §11 の
#   存在 fail-closed pin (照合不能 silent skip の回帰 pin・M15) のみが ORIG を参照する (内容不読)。 既定を live
#   canonical から snapshot へ redirect した (canonical は flip 済 = 生成物ゆえ原本 anchor たりえない)。 snapshot の
#   provenance (folio-d7bq flip commit a86ec1f の親) = `git show 1744d9f:design-intent/spec/rules.html`。
#   snapshot は改変禁止 — 保護の所在は ★tracked な test-adversarial-spec.sh の SNAPPIN 群 (sha256 == census header
#   宣言値 / census 不在の exit 2 fail-closed / census 値 mutate で arm 発火) にある (cell-local selftest は land 後に
#   消えるため所在たりえない)。 ★ただし現状 test-adversarial-spec.sh は ★CI 未配線 (.github/workflows/ci.yml に step
#   が無い = tracked だが自動実行経路ゼロ = committed but dormant)。 CI 配線は folio-7wbn Leg B (admin・ci.yml は
#   本 cell の禁止面) で追加予定であり、 それまで本 pin は ★手動実行時のみ 発火する。
#   ★★さらに (folio-7wbn 3 巡目 ceiling major): ★本 script (verify-spec.sh) 自体にも自動実行経路が無い。
#   ci.yml に verify-spec.sh を走らせる step が一切無く (gate F sweep の `gate rules ...` は assemble → inject →
#   render-gate-srs.py で floor を呼ばない)、 `folio validate` は 18-gate の link/jsonld floor で本 script を呼ばず、
#   統一 dispatch `folio verify --type spec` は capability-registry.yaml の `spec: wired: false` により fail-closed で
#   拒否される。 よって §10b 凍結 census arm と §11 round-trip は shipped 状態で ★稼働ゼロ であり、 Leg B の必要配線は
#   ★3 点 = (1) per-spec census-guard step (`census-guard.sh rules <base>`) / (2) test-adversarial-spec.sh step /
#   (3) spec doc-type の wired 化 または verify-spec.sh の直接 CI step。 (1)(2) だけでは本 script が動かないため
#   census arm は依然発火しない — Leg B の scope をこの 3 点で見積もること (詳細は rules.frozen-census.txt ★実態開示)。
ORIG="${SPEC_ORIGIN_HTML:-$SCRIPT_DIR/spec-origin/rules.origin.html}"

# ============================================================================
# 10b. ★literal census arm (folio-7wbn 政策 A・snapshot oracle bootstrap 退役後の恒久防御 (a))。
#   ★なぜ独立 anchor が要るか: §4/§5 の rich 突合と §11 round-trip は全て「contract vs 生成物」で ★両側同時退行で
#     vacuous PASS する (extractor が richplain() → plain() 相当へ戻ると contract も生成物も同時に rich を失う)。
#     凍結 literal census は両側と独立ゆえ、 collapse しても frozen 26 vs 生成物 17 で FAIL する
#     (test-adversarial-spec.sh の COLLAPSE 群 / 本番自己比較 MK が red→green で実証)。
#   ★expected = canonical / artifact / 生成物から【導出しない】凍結 literal (spec-origin/rules.frozen-census.txt)、
#     measured = ★生成物 HTML (verify の subject)。 ORIG は census を【消費しない】 (下記存在 pin のみ)。
#   ★rules 非該当軸 (jq -S census 2 本 / JSON-LD folio:stakeholders) は arm ごと除去した (移植でなく削除・
#     census file header 参照)。 対応する mutation-kill も test-adversarial-spec.sh に作らない (空撃ち MK 禁止)。
# ============================================================================
# 凍結 census 読み取り (frozen literal SSoT・source せず grep で読む = tab / bracket / quote 安全)。
FROZEN_CENSUS="$SCRIPT_DIR/spec-origin/rules.frozen-census.txt"
[[ -f "$FROZEN_CENSUS" ]] || { echo "verify-spec: ★凍結 census 不在 (政策A anchor 喪失・fail-closed): $FROZEN_CENSUS" >&2; exit 2; }
fz()     { grep -m1 "^$1=" "$FROZEN_CENSUS" | sed "s/^$1=//"; }                                  # scalar
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
# ★★【隔離中・census は本 view を消費しない】(folio-gt4s ceiling major fix・verification arm と対称)。
#   strip_inert には ★bogus comment のオフセット誤算 という fail-open 欠陥がある: handle_comment は cut 終端を
#   `s + len(data) + 7` (= `<!--` 4 byte + `-->` 3 byte の決め打ち) で算出するが、 Python html.parser は
#   ★bogus comment `<!x>` (実長 4 byte) に対しても handle_comment(data='x') を発火するため、 計算長 8 で
#   ★直後の live 4 byte を過剰削除する。 実測: `A<!x><template><code>z</code></template>B`
#   → `Aplate><code>z</code></template>B` で <template> 開始タグが破壊され ★中身が live 化する。
#   ゆえに本 view を census subject にすると、 `<!x>` を 4 byte 前置するだけで <template> inert 除外が破れ、
#   (1) inflate (decoy 注入で凍結値が動く) と (2) deflate/laundering (live 資産を剥奪しても凍結値へ「復元」できる)
#   の ★両方向 が再開通する = 政策 A の【唯一の独立 anchor】の fail-open (実測再現済・CEN-tpl6/7/8 が pin)。
#   ★修正方針 (呼び先のみ是正): census_dump / h_inline は ★共に実 HTML parser であり、 comment / script / style を
#   非計数・<template> を除外 ★済 ゆえ、 strip_inert 前処理は「二重の帯」ではなく ★実際には唯一の穴 だった。
#   よって census subject を RAW $HTML へ戻す (実測: clean rules.html で RAW == LIVE == 凍結
#   xref 26 / term 18 / delta 1 / id 58 / esc 1 = 完全一致ゆえ ★正当な資産の計数には無影響)。
#   ★関数本体 (strip_inert) は契約 (a) の両 arm byte-identical 逐語移植ゆえ ★改変しない (片 arm のみの本体改変は
#   cross-arm 非対称の新設。 呼び先の切替は本体を触らずに穴を塞ぐ・両 arm 同時に適用済)。
#   ★本 view は構造 parity 維持のため生成のみ残置し ★どの census も消費しない。 再配線するなら先に本体を直すこと。
HTML_LIVE="$(mktemp)"
strip_inert "$HTML" > "$HTML_LIVE" || { echo "verify-spec: ★census live view 生成に失敗 (fail-closed): $HTML" >&2; exit 2; }
[[ -s "$HTML_LIVE" ]] || { echo "verify-spec: ★census live view が空 (fail-closed): $HTML" >&2; exit 2; }

# ★census 計数 helper (census subject = 生成物 HTML の ★RAW byte / ORIG は非消費・上記隔離注記を参照)。
#   ★実 HTML parser の 1 walk で全軸を出す (attribute laundering 封鎖・上記 ★★参照):
#     - element 軸 (id / a.xref / span.term / ins|del.delta / delta-id) は starttag の ★attrs から数える
#       (属性値の中に書かれたタグ様文字列は attrs の ★値 でしかなく、 要素として計上されえない)。
#     - escape literal 軸 (&lt;a class="xref" / &lt;code / &lt;span) は ★text node のみ から数える
#       (entityref / charref を元記法へ復元して連結。 属性値・comment・script/style 本文は非計数)。
#   出力形式: `KEY=n` 行 → `#IDS` 節 (navigable id) → `#DIDS` 節 (delta-id)。
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

# ★ORACLE 存在 pin (bootstrap 記録・fail-closed。 照合不能 silent skip の回帰 pin・M15・非消費)。 snapshot は census を消費しないが、
#   SPEC_ORIGIN_HTML を存在しない path へ向けて gate を silent skip する逃げ道は塞ぐ (存在検査のみ・内容不読)。
if [[ ! -f "$ORIG" ]]; then
  printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (照合不能・fail-closed)\n' "ORACLE 存在 pin (bootstrap 記録)" "$ORIG"; fail=1
fi

# --- (a) literal census: expected = 凍結 literal / subject = 生成物 HTML (ORIG 非消費) ---
# ★census 実測は parser walk 1 回に集約する (計数方式の混在 = parser-differential の温床ゆえ single-source)。
CEN_DUMP="$(mktemp)"
census_dump "$HTML" > "$CEN_DUMP" || { echo "verify-spec: ★census parser walk に失敗 (fail-closed): $HTML" >&2; exit 2; }
grep -q '^C_XREF=' "$CEN_DUMP" || { echo "verify-spec: ★census parser walk の出力が不正 (fail-closed): $HTML" >&2; exit 2; }
cen()  { grep -m1 "^$1=" "$CEN_DUMP" | sed "s/^$1=//"; }
cen_ids()  { sed -n '/^#IDS$/,/^#DIDS$/p' "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
cen_dids() { sed -n '/^#DIDS$/,$p'        "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
# navigable id census (count + rename SET)。
g_ids_all="$(mktemp)"; cen_ids > "$g_ids_all"
# D-* (delta 印) は navigable id へ混入禁止 (fail-closed・生成物側で撃つ)。
chk "census navigable id: 生成物の D-* id == 0 (delta 印 anchor 混入を fail-closed に)" "0" "$(grep -c '^D-' "$g_ids_all" || true)"
# ★★提示層 wrapper id の census 除外 (admin 裁定 C2・ADR-0054 §2.2)。 前方照会 / 用語集を section id 付きの章に
#   する決定は navigable id を +2 するが、 これは ★提示層 chrome の追加 であって原本由来 anchor ではない。 凍結
#   census (FZ_ID_COUNT / ID_SET) は原本 anchor の防壁として ★不変に保ち、 この 2 literal ★だけ を肯定形
#   allowlist で除外する (★default-block 維持 = 他の新 id は従来どおり count / SET 双方で FAIL する)。
#   ★空振り封鎖: 除外した id が生成物に ★実在すること を陽性 assert する (実在しない id を除外し続けて
#   allowlist が形骸化する / 章化が落ちても除外だけ残る、 の両方を封鎖)。 §3 の section anchor 列とも二重。
for _w in "${PRESENTATION_WRAPPER_IDS[@]}"; do
  chk "census: 除外対象の提示層 wrapper id '$_w' が生成物に実在 (allowlist 空振り封鎖)" "1" "$(grep -cxF "$_w" "$g_ids_all")"
done
g_ids="$(mktemp)"; grep -vxF -f <(printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}") "$g_ids_all" > "$g_ids"
# ★count census (frozen literal・subject=生成物・提示層 wrapper 除外後)。
chk "census navigable id: 総数 (提示層 wrapper 除く) == 凍結 $(fz FZ_ID_COUNT)" "$(fz FZ_ID_COUNT)" "$(grep -c . "$g_ids")"
# ★重複 0 の構造的不変条件 (folio-7wbn 3 巡目 ceiling major fix)。 count / SET census は共に dedup 後の unique 集合を
#   見るため ★既存 id の複製注入 (unique 58 保存) を原理的に検出できない。 文書順 first-match の fragment 解決ゆえ
#   複製は anchor hijack を起こす。 凍結 literal でなく「unique == 総出現」で撃つ (census file 無改訂)。
#   ★除外前の全 id 集合で撃つ (提示層 wrapper id の複製注入も同じ hijack を起こすため allowlist の外に置かない)。
chk "census navigable id: 重複 0 (unique == 総出現・anchor hijack 封鎖)" "$(cen ID_TOTAL)" "$(grep -c . "$g_ids_all")"
# ★id-rename SET census: count 保存 substitution (58==58) を見逃さないよう凍結 SET と comm。
FZ_IDS="$(mktemp)"; fz_set ID_SET | LC_ALL=C sort -u > "$FZ_IDS"
chk_empty "census id-rename SET: 生成物にあり凍結 SET に無い余剰 0 (rename / 捏造)" "$(LC_ALL=C comm -13 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
chk_empty "census id-rename SET: 凍結 SET にあり生成物に無い欠落 0 (rename / 脱落)" "$(LC_ALL=C comm -23 "$FZ_IDS" "$g_ids" | tr '\n' ' ')"
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
chk_empty "census delta-id SET: 欠落 0 (凍結 SET 対)" "$(LC_ALL=C comm -23 "$FZ_DID" "$G_DID" | tr '\n' ' ')"
rm -f "$G_DID" "$FZ_DID"
# escape 済 literal 'a class="xref"' (過剰 linkify 禁止・subject=生成物・★text node 限定計数)。
chk "census escape: 'a class=\"xref\"' literal == 凍結 $(fz FZ_ESC_XREF)" "$(fz FZ_ESC_XREF)" "$(cen ESC_XREF)"
# generic inline (code/span) の人間層 region 別 occurrence (frozen・subject=生成物・region 相殺封鎖のため総和も撃つ)。
#   ★0 の軸 (table-cell / caption) も存置する: 「減らせない」代わりに ★注入 (0→1) を撃つ teeth があり、 撤去すると
#   人間層 table/caption への捏造 inline 混入が無被覆になる (F19 群も注入方向の MK で pin 済 = 空撃ちでない)。
chk "census generic: 人間層 <code> table-cell == 凍結 $(fz FZ_CODE_TABLE_CELL)" "$(fz FZ_CODE_TABLE_CELL)" "$(h_inline "$HTML" code table-cell)"
chk "census generic: 人間層 <code> caption == 凍結 $(fz FZ_CODE_CAPTION)"       "$(fz FZ_CODE_CAPTION)"    "$(h_inline "$HTML" code caption)"
chk "census generic: 人間層 <code> rest == 凍結 $(fz FZ_CODE_REST)"            "$(fz FZ_CODE_REST)"       "$(h_inline "$HTML" code rest)"
chk "census generic: 人間層 <code> 総数 == 凍結 $(fz FZ_CODE_TOTAL) (region 相殺封鎖)" "$(fz FZ_CODE_TOTAL)" "$(h_inline "$HTML" code human)"
chk "census generic: 人間層 <span> table-cell == 凍結 $(fz FZ_SPAN_TABLE_CELL)" "$(fz FZ_SPAN_TABLE_CELL)" "$(h_inline "$HTML" span table-cell)"
chk "census generic: 人間層 <span> caption == 凍結 $(fz FZ_SPAN_CAPTION)"       "$(fz FZ_SPAN_CAPTION)"    "$(h_inline "$HTML" span caption)"
# double-escape 直接検出 (frozen・subject=生成物・★text node 限定計数)。
chk "census double-escape: &lt;code literal == 凍結 $(fz FZ_ESC_CODE)" "$(fz FZ_ESC_CODE)" "$(cen ESC_CODE)"
chk "census double-escape: &lt;span literal == 凍結 $(fz FZ_ESC_SPAN) (散文中の正当 literal)" "$(fz FZ_ESC_SPAN)" "$(cen ESC_SPAN)"
rm -f "$HTML_LIVE" "$CEN_DUMP"

if [[ "$NMB_TOTAL" -gt 0 ]]; then
  # ★ORACLE 存在 pin (bootstrap 記録・fail-closed。 照合不能 silent skip の回帰 pin・M15・非消費)。 §11 LEFT は政策 A で
  #   contract 由来へ re-home したため ORIG を消費しないが、 SPEC_ORIGIN_HTML=/nonexistent による silent skip の
  #   逃げ道は §10b と対称に塞ぐ (存在検査のみ・内容不読)。
  if [[ ! -f "$ORIG" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (照合不能・fail-closed)\n' "機械層 round-trip 存在 pin" "$ORIG"; fail=1
  fi
  command -v jq >/dev/null || { echo "verify-spec: jq required (§11 contract round-trip)" >&2; exit 2; }
  LF="$(mktemp)"; RF="$(mktemp)"
    # LEFT: ★政策 A (folio-7wbn)。 snapshot / live canonical でなく contract.machine_preamble[] +
    #   sections[].machine_blocks[] (74 block) から document 順に再構成する。 contract の html field は
    #   extract-rules-spec.sh の inner_norm 済 (空白畳み + trim) ゆえ RIGHT の norm 出力と 1:1 で突合する。
    #   list は items[] を li 単位へ展開 (RIGHT の <li class="mli"> と対称)。
    #   ★sort しない (document 順を保存) = 順序付き突合 (人間層 §4/§5 と対称)。
    yq -o=json '[.machine_preamble[]?, .sections[].machine_blocks[]?]' "$CONTRACT" | jq -r '.[] |
      if .type=="list" then (.items[] | "li\t"+.)
      elif .type=="prose" then "prose\t"+.html
      elif .type=="note" then "note\t"+.html
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
        # ★folio-0x0k errata E2: prose opener は id="…" 属性を挟みうる (機械層 self-anchor s3-vocab-schema) ため
        #   exact-match でなく [^>]* を挟む柔軟形にする (LEFT 抽出 line 413 と同型・id 介在で脱落する false-FAIL を封鎖)。
        if (substr($B,$p)=~/<p\b[^>]*\sdata-component="spec-machine-prose"[^>]*>/)  { $c{prose}=$p+$-[0]; }
        if (substr($B,$p)=~/<aside data-component="spec-machine-note" data-audience="machine">/) { $c{note}=$p+$-[0]; }
        if (substr($B,$p)=~/<li class="mli">/) { $c{li}=$p+$-[0]; }
        last unless %c;
        my ($k)=sort { $c{$a}<=>$c{$b} } keys %c; my $at=$c{$k};
        if ($k eq "prose") { substr($B,$at)=~/<p\b[^>]*\sdata-component="spec-machine-prose"[^>]*>(.*?)<\/p>/s; push @u,"prose\t".norm($1); $p=$at+$+[0]; }
        elsif ($k eq "note") { substr($B,$at)=~/<aside data-component="spec-machine-note" data-audience="machine">(.*?)<\/aside>/s; push @u,"note\t".norm($1); $p=$at+$+[0]; }
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
#      含む生成 HTML (rules は ../assets/mermaid.min.js 参照だが serve root では /assets/ に正規化解決) を
#      light/dark × 3 viewport で render-gate し、 SVG settle polling (最大 15s) で非同期 render を待つ。 vendor
#      は render_gate_f が staging。 fail-closed (violation/crash/settle 不足 = $fail=1)。 SKIP_RENDER=1 で SKIP。 ----
render_gate_f "$HTML" "SPEC_SKIP_RENDER"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 要件/section/block/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
