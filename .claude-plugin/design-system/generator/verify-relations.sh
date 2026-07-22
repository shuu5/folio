#!/usr/bin/env bash
# folio engine tr0 (folio-hd0) — spec-pack fabrication-free + 非終端 照会 floor (relations dual-audience self-host・spec-pack fork)
#
# ★spec-pack fork (verify-spec.sh から fork・共有 core/lib 無改変)。 doc_type=spec + 原本=relations.html へ差し替えただけ。
# 生成 spec (relations) HTML の *構造* が入力 spec contract から完全に導出されたことを機械検証する floor gate。
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
# usage: verify-relations.sh [--filled <manifest.yaml> | --artifact] <relations-contract.yaml> <generated.html>
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
CONTRACT="${1:?usage: verify-relations.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-relations.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-relations: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-relations: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-relations: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-relations: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_core_chrome) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-relations: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=54; source "$LVC" || { echo "verify-relations: failed to source verify-common.sh" >&2; exit 2; }

# EARS pattern → class / label (assemble-relations.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table「用途」列 SSoT に一致 (folio-2jr drift 是正)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1・assemble-relations と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )
# ============================================================================
# ★ADR-0054 (提示層標準形) lockstep 定数群 — assemble-relations.sh と ★二重保守 (detect↔remediate parity)。
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
#   prose slot が持つため、 floor は「level ごとに許される可視ラベルの ★有限集合」に属するかを逐値突合する
#   (label↔level 詐称の封鎖)。 現行 prose manifest の全値 = must:{必須, 必須・将来} / should:{推奨・現在} の 3 値。
# ★前方一致 (語幹で始まる) は使わない (folio-q7l7 self-review major-3 / ehar): 「必須ではない」のような ★否定接尾 が
#   語幹で始まるため prefix 判定を素通りし、 level と意味が反転したまま全 gate を通る (実測 verified)。
# ★集合の拡張には prose manifest / 本 allowlist / assemble-relations.sh の同名配列の ★三点同時更新 が必要 (fail-closed)。
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 従来 heading 列突合は先頭 NSEC 個
#   (= contract section) しか見ておらず静的 2 band の見出しは ★無警備 だった (R5 の over-promise 見出しが gate を
#   素通っていた原因)。 kicker 列と同型に末尾 2 件も期待列へ含める。
#   ★§番号は literal 固定せず contract の最終 section 見出しから ★導出 する (下記 STATIC_HEADINGS 組み立て)。
#   literal 固定だと contract に section を 1 本足したとき帯番号 (NSEC/NSEC+1) と見出し文字列 (§7/§8) が
#   ★無言でずれる (folio-q7l7 self-review major-2)。
STATIC_HEADING_TAILS=("上位文書への前方照会 — 原則と決定記録へつながる" "本文に出てくる専門語のやさしい説明")
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token 2 つに固定)。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2)。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# ★契約非依存 census floor の期待値 (relations 固有・0/0 恒真封鎖)。 新 field (references[].title /
#   requirements[].priority) と新 block (ref-primary) / subsubhead essence は ★all-or-none optional ゆえ、
#   契約から一括削除すると「契約側も生成物側も空」で逐値突合が ★0/0 恒真 PASS する。 section class census (5/2) と
#   同型に、 生成物の占有数を ★数値 hardcode で pin して封鎖する (rules/verification fork へ literal 流用禁止 = relations 固有値)。
FZC_RF_GLOSS=13      # 前方照会チップの一行タイトル = |references|
FZC_RQ_PRIO=4        # RFC-2119 優先度バッジ = |requirements|
FZC_RQ_PLAIN=4       # 「やさしく言うと」平易行 = |requirements|
FZC_REF_PRIMARY=4    # §6 一次参照 (人間層) の項目数
FZC_SUBSUB_SE=2      # 人間層 1 行要約を持つ subsubhead 数 (§4.4.1 / §4.4.2・§4.4.3 は表を持つため対象外)

fail=0
make_body "$HTML"
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build relations "$FILLED_MANIFEST"

echo "spec-pack fabrication-free + 非終端 照会 floor: $HTML"
echo "  contract: $CONTRACT"

NSEC="$(q '.sections | length')"
NREQ="$(q '.requirements | length')"

# ★節番号 (§N) を contract sections[].heading から ★導出 する (folio-q7l7 self-review major-2)。
#   band の巨大番号 (.num) 期待列を `seq 0 NSEC+1` の hardcode で作ると、 assembler 側の num=CHAPN-1 と
#   ★両側が同じ仮定に合意しているだけ になり、 実際の見出し (h2 の「§N.」) と .num が食い違っても検出できない
#   (実測: contract sections[3].heading を「§9. …」へ書き換えて再生成すると帯 3 / h2 §9 の可視不整合が生じるが
#    verify-relations.sh --artifact は rc=0 / [FAIL] 0 で素通った)。 見出し自身を trust anchor にして構造束縛する。
# ★fail-closed: §N を持たない heading が 1 本でもあれば abort (0 件マッチの恒真化を防ぐ)。
# ★-Mutf8 必須: -CSD は入力を decode するが ★program source の literal は decode しない — 「§」を素の byte のまま
#   書くと decode 済み入力と一致せず ★常に 0 match = 全 heading が NO-SECTION-NUMBER となり誤 abort する。
SEC_NUMS="$(q '.sections[].heading' | perl -CSD -Mutf8 -ne 'chomp; if (/^§(\d+)\./) { print "$1\n" } else { print "NO-SECTION-NUMBER\n" }')"
if [[ -z "$SEC_NUMS" ]] || printf '%s\n' "$SEC_NUMS" | grep -q 'NO-SECTION-NUMBER'; then
  echo "verify-relations: ★contract sections[].heading に §N 形でない見出しがある (番号導出不能・fail-closed)" >&2
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
# ★EARS 凡例 (folio-2jr・静的 key): 1 個・5 item・label は EARS_LABEL (= rules.html §6 用途 SSoT) と §6 行順で一致 (assemble-relations と二重保守=parity)。
chk "ears-legend == 1"                    "1"                              "$(grep -o 'data-component="ears-legend"' "$BODY" | wc -l)"
chk "ears-legend-item == 5"               "5"                              "$(grep -o 'data-component="ears-legend-item"' "$BODY" | wc -l)"
exp_legend="$(for p in ubiquitous event-driven state-driven optional unwanted; do esc "${EARS_LABEL[$p]}"; printf '\n'; done)"
act_legend="$(perl -CSD -0777 -ne 'while (/<span data-component="ears-legend-item" class="[^"]*">([^<]*)<\/span>/g){ print "$1\n"; }' "$BODY")"
chk "ears-legend label 列 == EARS_LABEL (§6 用途 順)" "$exp_legend" "$act_legend"
# ★凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1): 5 件・EARS_WHEN と §6 順で一致。
chk "ears-legend el-when == 5"            "5"                              "$(grep -o 'class="el-when"' "$BODY" | wc -l)"
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
chk "spec-subsubhead == Σ subsubhead blocks" "$(q '[.sections[].blocks[]? | select(.type=="subsubhead")] | length')" "$(grep -c 'data-component="spec-subsubhead"' "$BODY")"
chk "spec-ref-primary == Σ ref-primary blocks" "$(q '[.sections[].blocks[]? | select(.type=="ref-primary")] | length')" "$(grep -c 'data-component="spec-ref-primary"' "$BODY")"
chk "ref-primary 項目 (rpi) == Σ ref-primary items" "$(q '[.sections[].blocks[]? | select(.type=="ref-primary") | .items[]] | length')" "$(grep -c 'class="rpi"' "$BODY")"

# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# 2. id 一意性 + doc_type
chk_empty "要件 id 一意"     "$(q '.requirements[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "section id 一意"  "$(q '.sections[].id' | sort | uniq -d | tr '\n' ' ')"
chk "doc_type == spec"       "spec" "$(q '.meta.doc_type')"

# 3. section fidelity: 可視 heading 列 (先頭 NSEC 個の h2) == sections[].heading (順序) / essence 列 == sections[].essence (順序)。
# ★ADR-0054 lockstep: 期待列へ静的 band 2 件を ★末尾固定 で含める (kicker 列と同型)。 旧版は head -n NSEC で
#   section 分しか見ず、 静的 band の h2 (前方照会 / 用語集) が ★無警備 だった — R5 の「検証へ前方照会する」
#   over-promise 見出し (REQ-VER チップ 0 件) はこの穴を通っていた。 全 NSEC+2 h2 を document 順で突合する。
exp_sh="$( { q '.sections[].heading'; printf '%s\n' "${STATIC_HEADINGS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_sh="$(grep -oE '<h2>[^<]*</h2>' "$BODY" | sed -E 's#<h2>([^<]*)</h2>#\1#')"
chk "section 可視 heading 列 == sections[].heading + 静的 band 2 件 (順序)" "$exp_sh" "$act_sh"
# ★章帯の巨大番号 == 見出しの節番号 (ADR-0054 §2.2 / R11)。 core band() は連番 (01..09) を emit するが、
#   pack-local wrapper が §番号へ書き換える。 旧版は .num を ★一切 pin していなかった (「件数のみ pin・値は非 pin」
#   = dossier ②) ため番号体系の drift が全 gate を素通った。
# ★期待列は hardcode の連番でなく ★見出し自身から導出 した SEC_NUMS + STATIC_NUMS (folio-q7l7 self-review major-2)。
#   これにより「.num と h2 の §N が食い違う」不整合が ★両側 hardcode の同意 に依らず構造的に落ちる
#   (封鎖できるのは「01 → 0 形」の 1 shape だけ、 という旧版の宣言過大を解消)。
chk "band .num 列 == 見出しの節番号 (heading 由来・連番でない・ADR-0054 §2.2)" \
  "$(printf '%s\n' "$SEC_NUMS"; printf '%s\n' "${STATIC_NUMS[@]}")" \
  "$(grep -oE '<span class="num">[^<]*</span>' "$BODY" | sed -E 's#<span class="num">([^<]*)</span>#\1#')"
exp_se="$(q '.sections[].essence' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_se="$(perl -CSD -0777 -ne 'while (/<div data-component="section-essence-callout"><p class="sec-se">([^<]*)<\/p><\/div>/g){ print "$1\n"; }' "$BODY")"
chk "section essence 列 == sections[].essence (順序)" "$exp_se" "$act_se"
# ★kicker 列 fidelity (folio-l93): band() が可視 emit する <span class="kicker"> の §N/トピック ラベルは
#   sections[].kicker 由来の *決定的フィールド* ゆえ doctrine 上 floor (heading/essence と同列の section fidelity)。
#   未突合だと §番号 swap・トピック取り違え・heading の §N との drift が全 gate (floor/persona-walk/fidelity) を素通った (17n ceiling HIGH)。
#   全 NSEC+2 band の kicker を document 順で突合: 先頭 NSEC = sections[].kicker / 末尾 2 = references・glossary band の
#   静的リテラル (assemble-relations.sh build() と二重保守 = detect↔remediate parity)。 静的 2 件も期待列へ含め band 並び替え・
#   静的ラベル drift も lock する (heading は head -n NSEC で section のみだが kicker は全 band を被覆)。
#   抽出: <span class="kicker"><svg ...>…</svg> {esc kicker}</span> の svg 後の可視テキスト ([^<]* = esc 済ゆえ安全)。
STATIC_KICKERS=("この規約が参照する文書 / 照会 (前方)" "用語集 / この文書で使う専門語")
exp_kicker="$( { q '.sections[].kicker'; printf '%s\n' "${STATIC_KICKERS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_kicker="$(perl -CSD -0777 -ne 'while (/<span class="kicker"><svg class="ico"[^>]*>.*?<\/svg> ([^<]*)<\/span>/gs){ print "$1\n"; }' "$BODY")"
chk "section kicker 列 == sections[].kicker + 静的 band 2 件 (順序)" "$exp_kicker" "$act_kicker"

# ★top-level section anchor 列 (folio-0x0k pre-flip): 原本 <section id="s1-w3c-vocab"> の実 id を章包み <section id> で再現。
#   全 section が anchor 保有ゆえ strict: 生成物の <section id="…"> 列を document 順で契約 sections[].anchor と突合する
#   (assembler の章包み emit を落とすと section id が消え corpus inbound #s5-3-ears 等が解決不能 = 件数/順序 FAIL)。
# ★ADR-0054 lockstep: 前方照会 / 用語集を section id 付きの章で包む決定 (admin 裁定 C2) により、 生成物の
#   <section id> 列は「contract sections[].anchor + ★末尾固定 2 wrapper」になる。 wrapper id は番号なし canonical token。
chk "section anchor 列 == sections[].anchor + 提示層 wrapper 2 件 (順序)" \
  "$( { q '.sections[].anchor'; printf '%s\n' "${PRESENTATION_WRAPPER_IDS[@]}"; } | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<section id="([^"]*)"[^>]*>/g){ print "$1\n"; }' "$BODY")"

# ★section class 列 fidelity (folio-jmz1・5dad 同型): canonical relations.html の section.normative / section.informative
#   wrapper を生成側で保持する (旧版は silent drop していた欠落を解消)。
# (i) ★position-sensitive 逐値: 生成物の <section id="…" class="…"> の class 値列を document 順で抽出し、 契約
#   sections[].class 値列 (順序) と逐値一致させる (count/集合/wildcard 禁止)。
#   ★class を持たない section は空値 (契約 // "") として突合列へ含める (yq の // は per-element = 7 行を保つ)。
#   抽出は section wrapper (id 先・class 後) 限定: band の <section data-component ...>(id 無し) は
#   <section id=" prefix を持たないゆえ交絡しない。
#   ★ADR-0054 lockstep: 提示層 wrapper 2 件は ★class を持たない (normative/informative census を不変に保つ admin 裁定 C2)。
#   期待列は contract の 7 値のまま — wrapper は空値ゆえ ★末尾の空行として現れ、 command substitution が両辺で等しく
#   刈るため列は一致する。 wrapper に class が生えれば actual に非空の 8 行目が現れて FAIL する (census 侵食の封鎖)。
#   ★ただし「空行が刈られる」ことに依存した検査は読み手に恒真と誤読されうるため、 直後に ★wrapper class 不在 を
#   独立の陽性 assert で撃つ (下記) — 本列突合と二重に固定する。
chk "section class 列 == sections[].class (順序・逐値)" \
  "$(q '.sections[].class // ""')" \
  "$(perl -CSD -0777 -ne 'while (/<section id="[^"]*"([^>]*)>/g){ my $a=$1; if ($a=~/\bclass="([^"]*)"/){ print "$1\n" } else { print "\n" } }' "$BODY")"
# (ii) ★契約非依存 census floor (folio-jmz1・0/0 恒真封鎖): 契約 class field 一括削除で (i) の逐値突合は空列==空列で
#   恒真 PASS するため、 生成物の section wrapper class 占有を数値 hardcode で pin する (folio relations 生成出力 = top-level
#   section 7 本 = normative 5 [s1..s5] + informative 2 [s0/s6])。 ★rules fork の 11/1 とは別値 (relations 固有値・流用禁止)。
#   census grep は '<section id="[^"]*" class="…">' で (a) band の class="tint-*"(id 無し) (b) aside 機械層の
#   class="informative" (c) rq-norm summary 等の生 normative を除外する (canonical 生 grep 実測 2026-07-20: informative 13 件
#   [grep -o 'class="informative"']・normative 9 件 [grep -o 'class="[^"]*normative[^"]*"'・spec-normative 4 件込み] へ膨張
#   ゆえ導出源に使わず、anchored 形で 5/2 へ絞る)。
chk "section class=normative census == 5 (契約非依存 floor・0/0 恒真封鎖)" "5" \
  "$(grep -oE '<section id="[^"]*" class="normative">' "$BODY" | wc -l | tr -d ' ')"
chk "section class=informative census == 2 (契約非依存 floor・0/0 恒真封鎖)" "2" \
  "$(grep -oE '<section id="[^"]*" class="informative">' "$BODY" | wc -l | tr -d ' ')"
# ★提示層 wrapper (ADR-0054 §2.2 の章化) の陽性 assert 2 本 — (a) 実在すること (章化が落ちれば section anchor 列も
#   FAIL するが、 census の id allowlist 除外が ★空振りしていない ことをここでも独立に固定する)、 (b) class を
#   ★持たないこと (normative/informative census 5/2 へ侵食させない)。 assemble-relations.sh と二重保守。
for _w in "${PRESENTATION_WRAPPER_IDS[@]}"; do
  chk "提示層 wrapper <section id=\"$_w\"> が class 無しで実在 (章化 + census 非侵食)" "1" \
    "$(grep -oE "<section id=\"$_w\">" "$BODY" | wc -l | tr -d ' ')"
done

# ★folio-0x0k errata E2: self-anchor 整合 — 生成物内の全 href="#x" が同一文書内 id="x" へ解決する (broken self-anchor 封鎖)。
#   canonical 突合の盲点を閉じる恒久 backstop (E1 subsubhead anchor / E2 p-anchor / section/subhead anchor の drop を href 側から二重 pin)。
#   ★navigable id 抽出は実タグの id 属性のみ (data-* は除外)。
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
  # ★navigable anchor (folio-0x0k pre-flip): 生成物 row の id= (小文字 req-rel-*) を tuple に *同梱* し「id= が data-req-id (大文字 SSoT)
  #   の置換でなく追加である」ことを 1 本の突合で pin する。 全要件 anchor 保有 = fail-closed。
  anc="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anc" && "$anc" != "null" ]] || { echo "verify-relations: ★contract 要件 $id の anchor が空 (navigable id 不在・fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; }
  # ★contract 由来 pattern が allowlist 外なら expected タプルを :-unknown で組まず fail-closed (assemble validate と parity)。
  # silent な class="unknown" 同士の偽一致 (双辺で同じ fallback を引いて tuple PASS する fail-open) を封鎖。
  if ! [[ -v EARS_CLASS[$pat] ]]; then echo "verify-relations: ★contract 要件 $id の EARS pattern が allowlist 外: $pat (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
  # ★ADR-0054 lockstep: RFC-2119 優先度バッジ class (rq-prio-<level>) + prio/plain の ★per-row slot-id を tuple へ同梱する。
  #   slot-id は要件 anchor から決定的に導く (prio-<anchor> / plain-<anchor>) ため、 ★別 row のバッジ / 平易行を
  #   持ってくる relocation クラス (件数保存) が tuple 突合で FAIL する = per-row 完全束縛。
  #   priority を持たない contract (all-or-none の「無い」側) では badge 自体が emit されないため期待も空にする。
  prio="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
  if [[ -n "$prio" && "$prio" != "null" ]]; then
    if ! [[ -v PRIO_LABEL_OK[$prio] ]]; then echo "verify-relations: ★contract 要件 $id の priority が allowlist 外: $prio (fail-closed)" >&2; rm -f "$EXPF" "$ACTF"; exit 1; fi
    prio_cell="rq-prio rq-prio-$prio\tprio-$(esc "$anc")"
  else
    prio_cell="-\t-"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%b\t%s\t%s\t%s\n' "$(esc "$anc")" "$(esc "$id")" "$(esc "$pat")" "${EARS_CLASS[$pat]}" "$(esc "${EARS_LABEL[$pat]}")" "$prio_cell" "$(esc "$ess")" "plain-$(esc "$anc")" "$(esc "$stmt")"
done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]') > "$EXPF"
RQNS="$RQ_NORM_SUMMARY" RQPK="やさしく言うと" perl -CSD -0777 -ne '
  # ★perl -CSD は ★入力ストリームだけ を UTF-8 decode し %ENV / program text は ★byte のまま。 非 ASCII literal を
  #   regex へ直書きすると decode 済 subject と噛み合わず ★恒常 0-match (= tuple 実体が空 → 常時 FAIL) になる。
  #   env 経由で渡し decode_utf8 してから quotemeta する (既存 SR/GMAP 群が ASCII 限定で回避していた罠の一般形)。
  use Encode qw(decode_utf8);
  # ★canonical dual-audience form (w1f cell-2): row opener に data-audience="human"、 rq-norm に data-audience="machine" を
  #   literal で要求し structured-regex に組み込む (= REQ-DA-STRUCT-1/-4 の構造 anchor を tuple 突合に同梱・属性 drop は row 脱落→件数 FAIL)。
  # ★folio-0x0k: row opener に id="<小文字 navigable id>" を literal 要求 (anchor 脱落 = row 脱落 → 件数 FAIL = fail-closed)。
  # ★ADR-0054: rq-prio バッジ (optional = priority 無し contract では不在) と rq-plain 行 (常在) を ★構造 anchor として
  #   regex へ組み込む。 平易行の ★中身 は prose slot ゆえ tuple では突合せず (mode 依存)、 ★slot-id の per-row 束縛のみ pin する
  #   (内容の非空 / 注入忠実 は §9 の prose slot 群が、 label↔level 束縛は下記 per-row 突合が担う)。
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
#   ★2 層で撃つ (section class の position + census と同型):
#     (i) 契約非依存 census — 生成物の占有数を ★数値 hardcode で pin。 新 field は all-or-none optional ゆえ
#         契約から一括削除すると tuple の期待/実体が同時に空になり ★0/0 恒真 PASS する。 その唯一の FAIL 源。
#     (ii) label↔level 束縛 — バッジの ★可視ラベルは prose slot (人間層 edit-SSoT) が持つため floor は内容を
#         contract と直接突合できない。 代わりに level ごとの ★closed allowlist (PRIO_LABEL_OK) で ★逐値突合 し、
#         level と label が乖離した詐称 (must の行に「推奨」/ must の行に「必須ではない」) を封鎖する。
#         ★prose 側だけを見る検査は contract を消費しないため、 (i) と独立に load-bearing。
#     (iii) ★level↔statement 束縛 (契約内不変条件) — (i)(ii) は ★contract の priority を ★根 として突合するため、
#         contract 自身が statement と矛盾する level を宣言していると ★全 gate を素通る (実測 verified: REQ-REL-001 の
#         priority を should へ反転 + prose ラベルを「推奨・現在」へ同期 → 再生成 → rc=0 / [FAIL] 0 で SHALL 要件が
#         「推奨」と表示される)。 drift gate は contract から再生成する byte 比較ゆえ contract 側の誤りには ★全盲。
#         contract は自ら「statement の SHALL/MUST → must / SHOULD → should」を ★決定的な導出規則 として明文化して
#         いる = algorithmic に判定可能ゆえ、 機械層で閉じる (宣言能力 == 実能力・fidelity ceiling へ委ねる自由文でない)。
chk "census: rq-prio バッジ占有 == $FZC_RQ_PRIO (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PRIO" \
  "$(grep -oE '<span class="rq-prio rq-prio-[a-z]+" data-prose-slot="priority" data-slot-id="[^"]*">' "$BODY" | wc -l | tr -d ' ')"
chk "census: rq-plain 平易行占有 == $FZC_RQ_PLAIN (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RQ_PLAIN" \
  "$(grep -oE '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span>' "$BODY" | wc -l | tr -d ' ')"
# (iii) priority (宣言) vs statement 由来 level (導出) の逐行突合。 ★mode 非依存 (contract だけを読む = HTML の
#   充填状態に依らない) ゆえ ARTIFACT/FILLED guard の ★外 に置く。 assemble-relations.sh validate() にも同判定を
#   置き build 時 fail-closed にしている (detect↔remediate parity)。
# ★導出規則 (RFC-2119 は ★大文字 のみ規範キーワード): SHALL|MUST があり SHOULD が無い → must / SHOULD があり
#   SHALL|MUST が無い → should。 両方 (AMBIGUOUS-BOTH) / 皆無 (NO-MODAL) は ★fail-closed で不一致扱い = FAIL。
# ★priority を持たない要件は対象外 (all-or-none の「無い」側 = 旧形 contract 互換)。 その 0/0 恒真は上記
#   契約非依存 census (rq-prio == $FZC_RQ_PRIO) が単独で封鎖する (rf-gloss title と同型の 2 本立て)。
ps_exp=""; ps_act=""
while IFS= read -r ps_id; do
  [[ -n "$ps_id" ]] || continue
  ps_p="$(q '.requirements[] | select(.id=="'"$ps_id"'") | .priority // ""')"
  [[ -n "$ps_p" && "$ps_p" != "null" ]] || continue
  ps_d="$(q '.requirements[] | select(.id=="'"$ps_id"'") | .statement' | perl -0777 -ne '
      my $m = /\b(?:SHALL|MUST)\b/ ? 1 : 0; my $s = /\bSHOULD\b/ ? 1 : 0;
      print $m && !$s ? "must" : ($s && !$m ? "should" : ($m ? "AMBIGUOUS-BOTH" : "NO-MODAL"));')"
  ps_exp+="$ps_id"$'\t'"$ps_p"$'\n'
  ps_act+="$ps_id"$'\t'"$ps_d"$'\n'
done < <(q '.requirements[].id')
chk "契約内不変: priority == statement の RFC-2119 modal verb 由来 level" "$ps_exp" "$ps_act"
# (ii) level ごとの期待語幹列 (contract 順) vs 生成物の (class, 可視ラベル) 列。 pre-fill mode (slot 空) では
#      ラベルが空ゆえ ★束縛は適用しない (空 slot は §9 の「全て空」検査が担う)。 filled/artifact のみで撃つ。
if [[ -n "$ARTIFACT" || -n "$FILLED_MANIFEST" ]]; then
  exp_prio="$(while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      p="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
      [[ -n "$p" && "$p" != "null" ]] || continue
      printf '%s\tIN-ALLOWLIST\n' "$p"
    done < <(q '.sections[].blocks[]? | select(.type=="requirements") | .ids[]'))"
  # 生成物側: class 末尾の level と可視ラベルを取り出し、 level ごとの ★closed allowlist に ★逐値 で属するかを判定する。
  # ★前方一致 (語幹で始まる) を使わない (folio-q7l7 self-review major-3 / ehar クラスの負の主張ラベル漏れ):
  #   prefix 判定だと語幹の後ろに否定・限定を付けた「必須ではない」が語幹で始まるため ★素通り し、 level と意味が
  #   反転したまま全 gate を通る (実測: landed canonical の prio-req-rel-001 を「必須ではない」に改竄 → rc=0 / [FAIL] 0)。
  #   allowlist 外は ★生ラベル を出して FAIL させる。
  act_prio="$(P_MUST="${PRIO_LABEL_OK[must]}" P_SHOULD="${PRIO_LABEL_OK[should]}" perl -CSD -0777 -ne '
      # ★-CSD は %ENV を decode しない (上記 tuple 突合の注記と同じ罠) — allowlist は decode してから比較する。
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
# list 項目
chk "list 項目列 == list blocks.items (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="list") | .items[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<li class="lbi">[^<]*</li>' "$BODY" | sed -E 's#<li class="lbi">([^<]*)</li>#\1#')"
# subhead anchor + heading + essence
# ★folio-0x0k pre-flip: h3 に id="<fine section anchor>" を刻む形へ shape 変化。 assemble-spec fork と ★対称の optional-id 形
#   (?: id="([^"]*)")? を用いる (relations は原本 16 h3 全て id 保有だが rules fork の §4.1-4.4 と同一 regex を共有)。 anchor 脱落は anchor 列突合が捕捉 = fail-closed。
SUBHEAD_RE='<div data-component="spec-subhead"><h3(?: id="([^"]*)")?>([^<]*)<\/h3><p class="sub-se">([^<]*)<\/p><\/div>'
chk "subhead anchor 列 == subhead blocks.anchor (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | (.anchor // "")' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ my $a=defined($1)?$1:""; print "$a\n"; }' "$BODY")"
chk "subhead heading 列 == subhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$2\n"; }' "$BODY")"
chk "subhead essence 列 == subhead blocks.essence (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subhead") | .essence' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBHEAD_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$3\n"; }' "$BODY")"
# ★folio-0x0k errata E1: subsubhead (h4) anchor + heading 列 (relations §4.4.1-3 = 第 4 anchor クラス)。 全 subsubhead が anchor 保有 = strict <h4 id="…">。
#   anchor 脱落 = 件数/順序 FAIL = fail-closed (corpus inbound relations.html#s4-4-1-scan 等 生きた 4 link の解決先)。
# ★ADR-0054 §2.2 lockstep: 空 subsection へ人間層 1 行要約 (.sub-se) を併記する形へ shape 変化。 essence は optional
#   (§4.4.3 は直後に表を持つため不要) ゆえ ★optional group (?:<p class="sub-se">…</p>)? で両形を受け、 essence 列突合で
#   有無と値の両方を contract と逐値一致させる (subhead の optional-id 形と同型)。
SUBSUB_RE='<div data-component="spec-subsubhead"><h4 id="([^"]*)">([^<]*)<\/h4>(?:<p class="sub-se">([^<]*)<\/p>)?<\/div>'
chk "subsubhead anchor 列 == subsubhead blocks.anchor (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subsubhead") | .anchor' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBSUB_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$1\n"; }' "$BODY")"
chk "subsubhead heading 列 == subsubhead blocks.heading (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="subsubhead") | .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBSUB_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ print "$2\n"; }' "$BODY")"
chk "subsubhead essence 列 == subsubhead blocks.essence (順序・空可)" \
  "$(q '.sections[].blocks[]? | select(.type=="subsubhead") | (.essence // "")' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(SR="$SUBSUB_RE" perl -CSD -0777 -ne 'my $re=$ENV{SR}; while (/$re/g){ my $e=defined($3)?$3:""; print "$e\n"; }' "$BODY")"
# ★契約非依存 census (0/0 恒真封鎖): essence を contract から一括削除すると上記逐値突合は空==空で恒真 PASS する。
#   人間層 1 行要約を持つ subsubhead の占有数を数値 hardcode で pin する (section class census と同型)。
chk "census: subsubhead の人間層 1 行要約 == $FZC_SUBSUB_SE (契約非依存 floor・0/0 恒真封鎖)" "$FZC_SUBSUB_SE" \
  "$(grep -oE '<div data-component="spec-subsubhead"><h4 id="[^"]*">[^<]*</h4><p class="sub-se">' "$BODY" | wc -l | tr -d ' ')"
# table caption / header / cell (全 spec-table 横断・順序)
chk "table caption 列 == table blocks.caption (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | (.caption // "")' | grep -v '^$' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(perl -CSD -0777 -ne 'while (/<table data-component="spec-table"><caption>([^<]*)<\/caption>/g){ print "$1\n"; }' "$BODY")"
chk "table th 列 == table blocks.headers (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .headers[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<th>[^<]*</th>' "$BODY" | sed -E 's#<th>([^<]*)</th>#\1#')"
chk "table td 列 == table blocks.rows cells (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="table") | .rows[][]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
  "$(grep -oE '<td>[^<]*</td>' "$BODY" | sed -E 's#<td>([^<]*)</td>#\1#')"
# mermaid caption + source lines
# figcaption は emit_mermaid と同じ fallback (caption → accDescr → accTitle・いずれも SSoT=mermaid block 由来) で導出されるため、 検証側も同 fallback で expected を組む (97z 後の空 caption 対応)。
_exp_figcaps() {
  local ns si nb bi cap
  ns="$(q '.sections | length')"
  for ((si=0; si<ns; si++)); do
    nb="$(q ".sections[$si].blocks | length" 2>/dev/null)"; [[ "$nb" =~ ^[0-9]+$ ]] || nb=0
    for ((bi=0; bi<nb; bi++)); do
      [[ "$(q ".sections[$si].blocks[$bi].type")" == "mermaid" ]] || continue
      cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
      if [[ -z "$cap" ]]; then
        cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accDescr:[[:space:]]*//p' | head -1)"
        [[ -z "$cap" ]] && cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accTitle:[[:space:]]*//p' | head -1)"
      fi
      esc "$cap"; printf '\n'
    done
  done
}
chk "mermaid figcaption 列 == caption/accDescr/accTitle fallback (順序・SSoT 由来・捏造なし)" \
  "$(_exp_figcaps)" \
  "$(perl -CSD -0777 -ne 'while (/<figcaption>([^<]*)<\/figcaption>/g){ print "$1\n"; }' "$BODY")"
chk "mermaid source 行列 == mermaid blocks.source_lines (順序)" \
  "$(q '.sections[].blocks[]? | select(.type=="mermaid") | .source_lines[]' | while IFS= read -r v; do esc "$v"; printf '\n'; done)" \
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
       [[ -n "$line" ]] || continue   # ★yq の 0 件 match は空行 1 本 (ref-primary 側の注記と同型)
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
#   恒真 PASS する。 chip の一行タイトル占有を数値 hardcode で pin する (relations 固有値・他 fork へ流用禁止)。
chk "census: rf-gloss (照会先の一行タイトル) 占有 == $FZC_RF_GLOSS (契約非依存 floor・0/0 恒真封鎖)" "$FZC_RF_GLOSS" \
  "$(grep -oE '<span class="rf-gloss">' "$BODY" | wc -l | tr -d ' ')"

# 6b. ★一次参照 (人間層 ul.ref-primary) fidelity — ADR-0054 §2.2 / rw finding 3。
chk "ref-primary (href,label,note) 順序突合" \
  "$(q '.sections[].blocks[]? | select(.type=="ref-primary") | .items[] | [.href, .label, (.note // "")] | @tsv' | while IFS= read -r line; do
       # ★空行 skip: yq は 0 件 match でも空行 1 本を出すため、 guard 無しだと期待側が「タブ 2 個の 1 行」になり
       #   実体 (0 行) と不一致 = ★偽 FAIL する (block 一括削除時に census による単独 isolation が壊れる)。
       [[ -n "$line" ]] || continue
       h="${line%%$'\t'*}"; rest="${line#*$'\t'}"; l="${rest%%$'\t'*}"; nt="${rest#*$'\t'}"
       printf '%s\t%s\t%s\n' "$(esc "$h")" "$(esc "$l")" "$(esc "$nt")"
     done)" \
  "$(perl -CSD -0777 -ne 'while (/<li class="rpi"><a href="([^"]*)">([^<]*)<\/a> <span class="rp-note">([^<]*)<\/span><\/li>/g){ print "$1\t$2\t$3\n"; }' "$BODY")"
chk "census: ref-primary 項目占有 == $FZC_REF_PRIMARY (契約非依存 floor・0/0 恒真封鎖)" "$FZC_REF_PRIMARY" \
  "$(grep -oE '<li class="rpi"><a href="' "$BODY" | wc -l | tr -d ' ')"
# ★一次参照は ★既定表示の人間層 に在ること (= rw finding 3「一次参照が既定の人間層表示から消える」の再発を撃つ)。
#   ★検査述語は「機械層 fold の中に無い」でなく「★既定表示から隠されていない」という ★構造的不変条件 で持つ
#   (folio-q7l7 self-review major-2)。 旧版は `<details data-component="spec-machine-fold">` ★のみ を列挙していたため
#   隣接する隠蔽 shape に ★fail-open だった (実測 verified: (a) ul.ref-primary を generic <details><summary>参考</summary>
#   で包む / (b) ul に style="display:none" を付す — どちらも [FAIL] 0 件で PASS した)。 partial-enumeration trap
#   (機構を列挙する) を 2 本の構造 assert で閉じる:
#     (1) ★fold 種別を問わず 折りたたみ (<details> 一般) の中に rpi が 0 件。
#     (2) ul の ★開始タグを逐語 pin (属性追加型の隠蔽 = style / hidden / aria-hidden は逐語一致しなくなり落ちる)。
#   ★(1) の述語は ★深さ (nesting depth) 追跡の逐次 token 走査 で持つ。 旧版は `<details...>(.*?)</details>` の
#   ★非貪欲ペア regex だったため、 外側 details の中に別の details が ★先行 すると内側の </details> で走査域が閉じ、
#   その後ろの rpi を一切数えない ★parser-differential fail-open だった (実測 verified: 入れ子 details 包みで rc=0 /
#   [FAIL] 0 件。 = PR19/PR28/PR29 と同じ「既定表示からの除去」クラスの ★第 4 shape が素通る)。 naive tag 走査を
#   実 DOM semantics (開始/終了の対応 = 深さ) へ寄せる是正 (r8k 前例)。 敵対実弾 = PR30。
#   ★走査対象は make_body の $BODY (= <style> 中身は空化済ゆえ inline CSS の `/* … <details …> … */` は混入しない)。
#   comment / <script> 中身は $BODY に verbatim 残るため、 そこに ★literal な details タグ文字列 を仕込む形は深さに
#   混入しうる — これは本 chk 固有でなく $BODY を読む全 floor chk 共通の境界 (genuine shape の機械強制 = make_body
#   の fail-closed scanner が担当・verify-common.sh 冒頭の設計注記)。
#   ★宣言能力 == 実能力 の開示: ul より ★上位 の祖先要素に隠蔽属性を付す shape (親 div の display:none 等) は本 floor の
#   対象外 = 実 render を見る gate F / ceiling の担当 (bash floor は DOM 祖先解決を持たないため撃てない)。
chk "ref-primary は折りたたみ (details 一般) の外 == 0 件が fold 内" "0" \
  "$(perl -CSD -0777 -ne 'my ($d,$n)=(0,0); while (/(<details\b[^>]*>|<\/details>|<li class="rpi">)/g){ my $t=$1; if ($t =~ m{^</}) { $d-- if $d>0 } elsif ($t =~ /^<details/) { $d++ } else { $n++ if $d>0 } } print $n;' "$BODY")"
chk "ref-primary の ul 開始タグは逐語 canonical (隠蔽属性の付与を封鎖)" "1" \
  "$(grep -oF '<ul class="ref-primary" data-component="spec-ref-primary">' "$BODY" | wc -l | tr -d ' ')"

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
# 10b. ★literal census arm (folio-uryh 政策 A・ADR-0053 §2.6 relations arm)。
#   ★なぜ独立 anchor が要るか: §4/§5 の rich 突合と §11 round-trip は全て「contract (もしくは原本) vs 生成物」で、
#     ★両側同時退行で vacuous PASS しうる。 特に relations では contract 再抽出 (extract-relations-spec.sh の
#     full 再走行) が ★手起こし 25 項を silent 削除すると同時に §11 を red→green へ反転させる (緑化が喪失の
#     隠蔽になる最悪形・bwif fence)。 凍結 literal census は両側と独立ゆえ、 collapse しても frozen 対 生成物 で FAIL する。
#   ★expected = canonical / artifact / 生成物から【導出しない】凍結 literal (spec-origin/relations.frozen-census.txt)、
#     measured = ★生成物 HTML (verify の subject)。 ORIG は census を【消費しない】 (下記存在 pin のみ)。
#   ★relations 非該当軸 (jq -S census 2 本 / JSON-LD folio:stakeholders) は arm ごと除去した (移植でなく削除・
#     census file header 参照)。 対応する mutation-kill も敵対 suite に作らない (空撃ち MK 禁止)。
#   ★配置注記: 本 arm は §11 の ★直前 に置く (verify-spec.sh の 10b と同位置)。 ORIG は §11 と ★同一式 で
#     再導出する — 既存行 (§11 の ORIG 代入) を 1 byte も触らずに存在 pin を張るため (両者とも同じ env var を
#     読むので値の乖離はありえない・idempotent な再代入)。
# ============================================================================
ORIG="${RELATIONS_ORIGIN_HTML:-$SCRIPT_DIR/../../../design-intent/spec/relations.html}"
# 凍結 census 読み取り (frozen literal SSoT・source せず grep で読む = tab / bracket / quote 安全)。
FROZEN_CENSUS="$SCRIPT_DIR/spec-origin/relations.frozen-census.txt"
[[ -f "$FROZEN_CENSUS" ]] || { echo "verify-relations: ★凍結 census 不在 (政策A anchor 喪失・fail-closed): $FROZEN_CENSUS" >&2; exit 2; }
fz()     { grep -m1 "^$1=" "$FROZEN_CENSUS" | sed "s/^$1=//"; }                                  # scalar
fz_set() { sed -n "/#BEGIN_$1/,/#END_$1/p" "$FROZEN_CENSUS" | grep -vE '^#'; }                    # id / delta set
# ★inert region 除去 (folio-7wbn ceiling major fix・parser-differential 封鎖)。
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
strip_inert "$HTML" > "$HTML_LIVE" || { echo "verify-relations: ★census live view 生成に失敗 (fail-closed): $HTML" >&2; exit 2; }
[[ -s "$HTML_LIVE" ]] || { echo "verify-relations: ★census live view が空 (fail-closed): $HTML" >&2; exit 2; }

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
#   RELATIONS_ORIGIN_HTML を存在しない path へ向けて gate を silent skip する逃げ道は塞ぐ (存在検査のみ・内容不読)。
if [[ ! -f "$ORIG" ]]; then
  printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (照合不能・fail-closed)\n' "ORACLE 存在 pin (bootstrap 記録)" "$ORIG"; fail=1
fi

# --- (a) literal census: expected = 凍結 literal / subject = 生成物 HTML (ORIG 非消費) ---
# ★census 実測は parser walk 1 回に集約する (計数方式の混在 = parser-differential の温床ゆえ single-source)。
CEN_DUMP="$(mktemp)"
census_dump "$HTML" > "$CEN_DUMP" || { echo "verify-relations: ★census parser walk に失敗 (fail-closed): $HTML" >&2; exit 2; }
grep -q '^C_XREF=' "$CEN_DUMP" || { echo "verify-relations: ★census parser walk の出力が不正 (fail-closed): $HTML" >&2; exit 2; }
cen()  { grep -m1 "^$1=" "$CEN_DUMP" | sed "s/^$1=//"; }
cen_ids()  { sed -n '/^#IDS$/,/^#DIDS$/p' "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
cen_dids() { sed -n '/^#DIDS$/,$p'        "$CEN_DUMP" | grep -v '^#' | LC_ALL=C sort -u; }
# navigable id census (count + rename SET)。
g_ids_all="$(mktemp)"; cen_ids > "$g_ids_all"
# D-* (delta 印) は navigable id へ混入禁止 (fail-closed・生成物側で撃つ)。
chk "census navigable id: 生成物の D-* id == 0 (delta 印 anchor 混入を fail-closed に)" "0" "$(grep -c '^D-' "$g_ids_all" || true)"
# ★重複 0 の構造的不変条件 (folio-7wbn 3 巡目 ceiling major fix)。 count / SET census は共に dedup 後の unique 集合を
#   見るため ★既存 id の複製注入 (unique 58 保存) を原理的に検出できない。 文書順 first-match の fragment 解決ゆえ
#   複製は anchor hijack を起こす。 凍結 literal でなく「unique == 総出現」で撃つ (census file 無改訂)。
#   ★除外前の全 id 集合で撃つ (提示層 wrapper id の複製注入も同じ hijack を起こすため allowlist の外に置かない)。
chk "census navigable id: 重複 0 (unique == 総出現・anchor hijack 封鎖)" "$(cen ID_TOTAL)" "$(grep -c . "$g_ids_all")"
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
# --- (b) ★relations 固有 frozen floor 3 軸 (再抽出 vacuous-green backstop・契約 hard acceptance) ---
#   ★既存の :347/:348/:362/:78/:297 は ★contract-vs-body の自己整合 ゆえ両側同時 collapse に vacuous で
#   backstop にならない。 full 再抽出 (extract-relations-spec.sh 再走行) は手起こし 25 項を消しつつ §11 を
#   green へ反転させるため、 契約非依存の凍結 literal で ★存在 を pin する (drift gate でなく floor 側に置く
#   理由 = drift gate は pre-flip に物理指紋段で abort し live な pre-flip 窓を守れないため)。
#   ★3 軸とも ★要素 anchored 計数 (naive substring は inline <style> の CSS 属性 selector を拾う。 実測:
#   spec-machine-list は naive 9 / 要素 anchored 6 で ★膨張する = :142 コメントの anchored 規律と同型の罠)。
#   ★非空撃ちの証明: 「1 項 drop → floor FAIL」を敵対 suite の per-shape MK が実弾で pin する。
#
#   ★★計数方式 (folio-uryh 自己点検 ceiling major fix・intra-arm parser-differential の解消)。
#   初版は `grep -oE '<li class="mli">' "$BODY"` の ★naive raw-byte 計数だった。 $BODY を作る make_body は
#   style/script 本体は除去するが ★HTML コメントを逐語温存する ため、 コメント本文中のタグ様文字列が live 要素
#   として計上された。 ★実測: live な <li class="mli"> を 1 個 ZZDROP 化しつつ `<!-- <li class="mli"> -->` を
#   1 個注入すると 3 軸とも凍結値へ「復元」でき [OK] のまま素通った (3 軸で同型・到達性は contract の
#   machine_blocks[].html が raw passthrough ゆえ (a) 軸と ★同一 vector)。 これは (a) 軸が census_dump を実
#   HTML parser へ寄せて閉塞したのと ★同一クラスの laundering であり、 「同一 arm 内で計数方式を揃える」規律
#   (:415 付近) に反する ★arm 内 parser-differential の再導入だった。 (b) 軸は「再抽出 collapse 時の唯一の
#   backstop」と本 file 自身が宣言する軸ゆえ、 宣言能力 > 実能力 の fail-open にあたる。
#   ★是正: 実 HTML parser (html.parser) の walk で ★element 軸 として数える (下記 floor_census)。 comment /
#   属性値 / script/style 本体 / <template> ほか inert subtree は構造的に非計上ゆえ laundering は原理的に閉じる。
#   ★ただし parser 化だけでは閉じない残穴が 1 つあった (自己点検 ceiling major fix): 属性 dict の構築が
#   dict(attrs) = last-wins だと `<li class="ZZ" class="mli">` を計上してしまう (browser は first-wins で
#   class="ZZ" と読む = mli 資産でない)。 ★属性 semantics クラス の laundering ゆえ comment (CEN-rel*L) /
#   inert (CEN-rel2T) の MK では pin されない。 handle_starttag は first-wins ループで構築する (下記)。
#   subject も $BODY でなく (a) 軸と同じ ★RAW $HTML へ揃える (LIVEPIN の topology 宣言と整合)。
#   ★census_dump 本体は改変しない (XARM の cross-arm byte-identity が割れる = 片 arm ドリフトの新設)。 本 walk
#   は (b) 軸専用の ★局所 helper として新設し、 INERT 集合の導出だけを census_dump と同型に保つ。
#   ★per-shape MK: CEN-rel1/2/3 (素の drop) に加え CEN-rel1L/2L/3L (drop + 同 literal コメント復元) と
#   M-SELFCMP の laundering 版が敵対 suite で実弾 pin する (laundering shape は drop 単独 MK では pin されない)。
floor_census() { python3 - "$1" <<'PYEOF'
from html.parser import HTMLParser
import sys
VOID={'br','img','meta','link','input','hr','wbr','source','col','area','base','embed','param','track'}
# ★inert 集合は census_dump と ★同一 導出 (非描画 subtree は live 資産でないため計数しない)。
RAWTEXT_INERT = (set(HTMLParser.CDATA_CONTENT_ELEMENTS)
                 | {'xmp','iframe','noembed','noframes','textarea','title'})
INERT = {'template'} | RAWTEXT_INERT
class F(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack=[]; self.n={'MACHINE_LIST':0,'MLI':0,'GROW':0}
    def _inert(self):
        return any(t in INERT for t,_ in self.stack)
    def handle_starttag(self, tag, attrs):
        # ★重複属性は ★first-wins (folio-uryh 自己点検 ceiling major fix・census_dump / h_inline と同一規約)。
        #   HTML Standard では 2 つ目以降の同名属性は parse error として ★破棄 される (最初が勝つ)。 dict(attrs)
        #   は last-wins ゆえ `<li class="ZZ" class="mli">` を browser は mli 資産と ★見ない のに floor_census は
        #   mli として計上し、 live 資産 1 個剥奪 → 重複属性 decoy 1 個注入 で凍結値へ復元できた (実測: 3 軸とも
        #   [OK] のまま rc=0 / RESULT: filled PASS)。 これは (b) 軸が「再抽出 collapse 時の唯一の backstop」と
        #   宣言する能力を下回る fail-open であり、 :415 付近の「同一 arm 内で計数方式を揃える」規律に反する
        #   ★arm 内 parser-differential の再導入だった (h_inline が folio-7st6 で是正した穴と ★同一クラス)。
        #   ★per-shape MK: CEN-rel1D/2D/3D + M-SELFCMP の重複属性版が敵対 suite で実弾 pin する。
        d={}
        for k,v in attrs:
            if k not in d: d[k] = v if v is not None else ''
        if not self._inert():
            # ★attrs 経由の構造判定ゆえ属性値中のタグ様文字列は計上されえない。 class は空白区切り token 一致。
            cls=(d.get('class') or '').split()
            if tag=='ul' and d.get('data-component')=='spec-machine-list': self.n['MACHINE_LIST']+=1
            if tag=='li' and 'mli' in cls: self.n['MLI']+=1
            if tag=='div' and 'grow' in cls: self.n['GROW']+=1
        if tag not in VOID: self.stack.append((tag,d))
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag in RAWTEXT_INERT: self.set_cdata_mode(tag)
        if tag not in INERT and self.stack and self.stack[-1][0]==tag: self.stack.pop()
    def handle_endtag(self, tag):
        # ★inert subtree は scope 境界 (census_dump と同型・stray end tag で inert が外れない)。
        m=-1
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0] in INERT: m=i; break
        lo = 0 if m<0 else (m if tag in INERT else m+1)
        for i in range(len(self.stack)-1,lo-1,-1):
            if self.stack[i][0]==tag: del self.stack[i:]; break
f=F(); f.feed(open(sys.argv[1],encoding='utf-8').read())
for k in ('MACHINE_LIST','MLI','GROW'): print("%s=%d" % (k, f.n[k]))
PYEOF
}
FLOOR_DUMP="$(mktemp)"
floor_census "$HTML" > "$FLOOR_DUMP" || { echo "verify-relations: ★frozen floor parser walk に失敗 (fail-closed): $HTML" >&2; exit 2; }
grep -q '^MACHINE_LIST=' "$FLOOR_DUMP" || { echo "verify-relations: ★frozen floor parser walk の出力が不正 (fail-closed): $HTML" >&2; exit 2; }
flr() { grep -m1 "^$1=" "$FLOOR_DUMP" | sed "s/^$1=//"; }
chk "frozen floor: spec-machine-list 要素 census == 凍結 $(fz FZ_MACHINE_LIST) (要素 anchored・再抽出 backstop)" \
  "$(fz FZ_MACHINE_LIST)" "$(flr MACHINE_LIST)"
chk "frozen floor: li.mli 要素 census == 凍結 $(fz FZ_MLI) (要素 anchored・再抽出 backstop)" \
  "$(fz FZ_MLI)" "$(flr MLI)"
chk "frozen floor: grow 要素 census == 凍結 $(fz FZ_GROW) (要素 anchored・再抽出 backstop)" \
  "$(fz FZ_GROW)" "$(flr GROW)"
rm -f "$FLOOR_DUMP"
# ============================================================================
# 11. ★原本↔生成物 機械層テキスト 双方向 *順序付き* 一致 (round-trip fidelity)。
#     原本 (design-intent/spec/relations.html) を *直 grep して生成 path から独立に* 再抽出し、 生成物の機械層と
#     双方向 (完全性 = 原本の全機械層が生成物に / no-fabrication = 生成物の機械層が全て原本に) を照合する。
#     ★順序付き (集合でない): 両側を sort せず document 順の配列のまま diff する (人間層 §4/§5 と対称)。
#       - 原本順保存 (契約 description 受入): 機械層 block の document 順を enforce → 同型 block の入替を捕捉。
#       - section 帰属: machine_blocks[] は section ごとに連続して emit される (build()/emit_section) ため、
#         ある block を別 section の fold へ移すと document 順が原本順とずれる → cross-section 誤帰属も検出。
#       (旧版は両側 LC_ALL=C sort した集合一致で、 順序入替・cross-section 移動を素通していた=major fix。)
#     ★fail-open しない: 機械層を持つ contract で原本不在なら FAIL (照合不能を素通さない)。
#     二重 escape (生 < → &lt;) は原本テキストと差が出るため本照合が確定検出する (§10 raw-emit より厳密)。
# ============================================================================
NMB_TOTAL="$(q '[.machine_preamble[]?, .sections[].machine_blocks[]?] | length')"
ORIG="${RELATIONS_ORIGIN_HTML:-$SCRIPT_DIR/../../../design-intent/spec/relations.html}"
if [[ "$NMB_TOTAL" -gt 0 ]]; then
  if [[ ! -f "$ORIG" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s 原本不在: %s (機械層 contract だが照合不能・fail-closed)\n' "原本↔生成物 機械層集合一致" "$ORIG"; fail=1
  else
    LF="$(mktemp)"; RF="$(mktemp)"
    # LEFT: 原本の live data-audience="machine" 自由文 (<p>→prose / <aside>→note / <ul>→li 単位) を document 順に再抽出 + inner_norm。
    #   live tag (実 <) のみゆえ escape 済例示 (&lt;p) を除外。 spec-normative の <div> は p/aside/ul でないため対象外 (= 26 EARS 除外)。
    #   ★sort しない (document 順を保存) = 順序付き突合 (人間層 §4/§5 と対称)。
    perl -CSD -0777 -e '
      local $/; open(my $fh,"<:encoding(UTF-8)",$ARGV[0]) or die; my $H=<$fh>; close $fh;
      sub norm { my ($s)=@_; $s//=""; $s=~s/\s+/ /g; $s=~s/^\s+//; $s=~s/\s+$//; return $s; }
      my @u; my $p=0; my $len=length($H);
      while ($p<$len) {
        my %c;
        if (substr($H,$p)=~/<p\b[^>]*\sdata-audience="machine"[^>]*>/)    { $c{prose}=$p+$-[0]; }
        if (substr($H,$p)=~/<aside\b[^>]*\sdata-audience="machine"[^>]*>/) { $c{note}=$p+$-[0]; }
        if (substr($H,$p)=~/<ul\b[^>]*\sdata-audience="machine"[^>]*>/)    { $c{list}=$p+$-[0]; }
        last unless %c;
        my ($k)=sort { $c{$a}<=>$c{$b} } keys %c; my $at=$c{$k};
        if ($k eq "prose") { substr($H,$at)=~/<p\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/p>/s; push @u,"prose\t".norm($1); $p=$at+$+[0]; }
        elsif ($k eq "note") { substr($H,$at)=~/<aside\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/aside>/s; push @u,"note\t".norm($1); $p=$at+$+[0]; }
        else { substr($H,$at)=~/<ul\b[^>]*\sdata-audience="machine"[^>]*>(.*?)<\/ul>/s; my $in=$1; my $e=$at+$+[0];
               while ($in=~/<li\b[^>]*>(.*?)<\/li>/gs){ push @u,"li\t".norm($1); } $p=$e; }
      }
      print "$_\n" for @u;
    ' "$ORIG" > "$LF"
    # RIGHT: 生成物の機械層 block を document 順に再抽出 + inner_norm。 prose/note/li は fold 内で交互に出現しうるため、
    #   型ごとに別 pass で集めず *位置走査* で混在順序を保存する (LEFT と同型・順序付き突合のため必須)。
    #   mli は machine list 専有 class・spec-machine-{prose,note} は machine 専有 component ゆえ live tag のみ抽出。
    perl -CSD -0777 -e '
      local $/; open(my $fh,"<:encoding(UTF-8)",$ARGV[0]) or die; my $B=<$fh>; close $fh;
      sub norm { my ($s)=@_; $s//=""; $s=~s/\s+/ /g; $s=~s/^\s+//; $s=~s/\s+$//; return $s; }
      my @u; my $p=0; my $len=length($B);
      while ($p<$len) {
        my %c;
        # ★folio-0x0k errata E2: prose opener は id="…" 属性を挟みうるため exact-match でなく [^>]* を挟む柔軟形 (assemble-spec と対称・id 介在 false-FAIL 封鎖)。
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
      printf '  [OK]   %-'"$CHKW"'s %s\n' "原本↔生成物 機械層 双方向 順序付き一致 (round-trip)" "$(grep -c . "$LF")"
    else
      printf '  [FAIL] %-'"$CHKW"'s\n' "原本↔生成物 機械層 不一致 (脱落 / 捏造 / 二重 escape / 改竄 / 順序入替 / cross-section 誤帰属)"
      echo "    --- 順序付き diff (< 原本 / > 生成物) ---"; diff "$LF" "$RF" | sed 's/^/      /' | head -20
      echo "    --- 原本のみ (生成物に脱落) ---"; LC_ALL=C comm -23 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
      echo "    --- 生成物のみ (原本に無い = 捏造/改竄) ---"; LC_ALL=C comm -13 <(LC_ALL=C sort "$LF") <(LC_ALL=C sort "$RF") | sed 's/^/      /' | head -10
      fail=1
    fi
    rm -f "$LF" "$RF"
  fi
fi

echo
# ---- gate F: render 健全性 (visual) mermaid pack 展開 (folio-jyfh B 段・helper=render_gate_f)。 mermaid 図を
#      含む生成 HTML (../assets/mermaid.min.js 参照は serve root で /assets/ に正規化解決) を light/dark × 3
#      viewport で render-gate し、 SVG settle polling (最大 15s) で非同期 render を待つ。 vendor は render_gate_f
#      が staging。 fail-closed (violation/crash/settle 不足 = $fail=1)。 SKIP_RENDER=1 で bash floor は SKIP。 ----
render_gate_f "$HTML" "RELATIONS_SKIP_RENDER"
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + 要件/section/block/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
