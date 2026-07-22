#!/usr/bin/env bash
# folio engine tr0 (folio-hd0) — spec-pack 決定的 assembler (relations dual-audience self-host・spec-pack fork)
#
# ★spec-pack fork (assemble-spec.sh から fork・共有 core/lib 無改変)。 doc_type=spec (relations.html) へ guard を差し替えただけ。
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
# usage: assemble-relations.sh <relations-contract.yaml> [out.html]

set -euo pipefail
# bash 5.2+ 既定 ON の patsub_replacement は esc() の ${v//pat/repl} を壊す (< → <lt;)。無効化。
shopt -u patsub_replacement 2>/dev/null || true
CONTRACT="${1:?usage: assemble-relations.sh <relations-contract.yaml> [out.html]}"
OUT="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSS="$SCRIPT_DIR/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-relations: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-relations: srs.css not found: $CSS" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-relations: yq required" >&2; exit 1; }

# ---- core 共通層 (q/esc/ico/band/cover骨格/glossary/footer/finalize) ----
# B2 (folio-5ua): SRS/ADR/research/principle-pack と共通の idiom は lib/common.sh から source。 本 file は spec-pack 固有
# (sections/blocks emitter / requirements(EARS) / references(非終端 照会)) を残す。
# ★term-inline (mark_terms) は spec-pack では不使用 = rules の用語は plain_short(やさしい言い換え) を持たないため
#   (glossary は term + def のみ・rules.html の span.term[data-tooltip] 由来)。 ゆえ core_init_term_inline は呼ばない。
source "$SCRIPT_DIR/lib/common.sh"

# EARS pattern (canonical = rules.html の data-ears-pattern 値) → 表示 class / label (verify-relations.sh と二重保守 = detect↔remediate parity)。
# ★label = rules.html §6 / contract ears-table の「用途」列 SSoT に一致させる (folio-2jr: 旧 禁止/機能 は §6 異常応答/機能オプション と
#   semantic drift していた — unwanted は「禁止」でなく異常時の振る舞い、 optional は機能の有無条件。 view を SSoT から導出し drift 根絶)。
declare -A EARS_CLASS=( [ubiquitous]=always [event-driven]=trigger [state-driven]=state [unwanted]=forbid [optional]=option )
declare -A EARS_LABEL=( [ubiquitous]=無条件不変条件 [event-driven]="event 応答" [state-driven]=状態継続中 [unwanted]=異常応答 [optional]=機能オプション )
# EARS 凡例の「いつ守るか」平易説明 (folio-2jr persona-walk major-1: 凡例 label は専門語ゆえ非エンジニアに意味が自明でない →
#   各型に平易タイミング語を併記。 §6 章リード prose の言い換え (常に/きっかけ/状態の間/機能/異常時) と方向一致・verify-relations と二重保守=parity)。
declare -A EARS_WHEN=( [ubiquitous]=常に守る [event-driven]=きっかけがある時 [state-driven]=状態が続く間 [unwanted]=異常が起きた時 [optional]=機能を使う時 )
# 抽象ロール (B0 论点2 照会 graph)。 references (前方照会) の role allowlist。 verify-common.sh の CROSS_DOC_ROLE_ALLOWLIST と一致。
declare -A ROLE_OK=( [claim]=1 [rationale]=1 [exploration]=1 [principle]=1 [verification]=1 [implementation]=1 )
# ★role の平易語 map (ADR-0054 §2.2「role ラベルは平易語 (implementation = この規約が実装する原則 / rationale = そう決めた理由の記録) で表示する」)。
#   ★attr (data-ref-role) は ★機械 token を保持し、 可視ラベルのみ map を適用する (機械層 token の意味を落とさず人間層だけ平易化)。
#   verify-relations.sh と二重保守 = detect↔remediate parity。 map に無い role は emit 時 hard error (silent 英語生表示を封鎖)。
declare -A ROLE_PLAIN=(
  [implementation]="この規約が実装する原則" [rationale]="そう決めた理由の記録" [claim]="この文書が満たすと主張する要件"
  [exploration]="探索の記録" [principle]="拠って立つ原則" [verification]="どう確かめるかの仕様"
)
# ★RFC-2119 優先度 (ADR-0054 §2.2「RFC-2119 優先度の平易バッジ (必須 / 推奨)」)。 contract requirements[].priority の
#   closed allowlist → 表示 class / 平易語の canonical 語幹。 verify-relations.sh と二重保守 = detect↔remediate parity。
#   ★badge の可視ラベルは prose slot (人間層 edit-SSoT) が持つが、 その値は本 allowlist の ★有限集合 に属さねば
#   ならない (verify が label↔level を ★逐値突合 = must の行に「推奨…」や「必須ではない」と書く label 詐称を封鎖)。
#   ★前方一致でなく逐値集合である理由: 否定接尾 (「必須ではない」) は語幹で始まるため prefix 判定を素通りする
#   (folio-q7l7 self-review major-3 / ehar クラス = 負の主張ラベルへの束縛漏れ)。
#   ★集合の拡張には prose manifest / 本 allowlist / verify-relations.sh の同名配列の三点同時更新が必要 (fail-closed)。
declare -A PRIO_OK=( [must]=1 [should]=1 )
declare -A PRIO_LABEL_OK=( [must]="必須|必須・将来" [should]="推奨・現在" )
# ★静的 band (前方照会 / 用語集) の heading ★本文 (§番号を ★除いた 部分)。 R5 (検証 over-promise 解消:
#   旧 heading は「原則・ADR・検証へ前方照会する」と述べるが REQ-VER チップは 0 件 = 実在しない照会種別の約束)。
#   verify-relations.sh の STATIC_HEADING_TAILS と二重保守 = detect↔remediate parity。
# ★§番号は literal 固定せず contract の最終 section 見出しから ★導出 する (derive_static_band_headings)。
#   literal 固定だと contract に section を 1 本足したとき帯番号 (NSEC/NSEC+1) と見出し文字列 (§7/§8) が
#   ★無言でずれる (folio-q7l7 self-review major-2)。
STATIC_BAND_HEADING_TAILS=("上位文書への前方照会 — 原則と決定記録へつながる" "本文に出てくる専門語のやさしい説明")
STATIC_BAND_HEADINGS=()
# ★提示層 wrapper section の id (admin 裁定 C2 = 番号なし canonical token に固定)。 ADR-0054 §2.2 の不変条件は
#   「section id を持つ章であること」で §7/§8 は帯表示の例示ゆえ id に番号を入れない (spec 横断で安定)。
#   ★class は付けない (normative/informative census を不変に保つ)。 verify-relations.sh の同名配列と二重保守。
PRESENTATION_WRAPPER_IDS=("forward-refs" "glossary-terms")
# ★機械層 fold / 要件 normative fold の平易ラベル (ADR-0054 §2.2「machine fold のラベルは平易語 (機械向けの詳細 =
#   原文そのまま) とする」 + 「精密 normative は『正確な条文 (機械向けの厳密な書き方)』として折りたたみ表示する」)。
#   verify-relations.sh と二重保守 = detect↔remediate parity。
RQ_NORM_SUMMARY="正確な条文（機械向けの厳密な書き方）"
MF_KICKER="機械向けの詳細（原文そのまま）"
# CSS tint allowlist (section.tint / band)。
declare -A TINT_OK=( [brand]=1 [violet]=1 [warn]=1 [info]=1 [ok]=1 [bad]=1 )
# section.class allowlist (section.normative / section.informative wrapper・folio-jmz1)。 closed 2 値・fail-closed
#   (normative/informative の 2 択・空値は属性省略ゆえ許容)。 canonical relations.html の class を生成側で保持する。
declare -A CLASS_OK=( [normative]=1 [informative]=1 )
# 対応 block type (これ以外 = silent drop の疑い → fail-closed abort)。
BLOCK_TYPE_ALLOW='prose|note|list|code|table|mermaid|subhead|subsubhead|requirements|ref-primary'
# ★機械層 (w1f cell-2 / ADR-0045) 対応 block type。 cell-1 schema = data-audience="machine" 自由文 (p→prose / aside→note / ul→list)。
#   これ以外は silent drop の疑い → fail-closed abort (人間層 BLOCK_TYPE_ALLOW と対称)。
MACHINE_BLOCK_TYPE_ALLOW='prose|note|list'

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

# ---- fail-closed contract validation (普遍規律 = core_validate_strings、 spec 固有 = doc_type/EARS/role/tint/block/集合) ----
validate() {
  local errs=0 d p si bi nsec nblk btype nmb mbi mbtype npre pi pbtype
  core_validate_strings "assemble-relations" || errs=1
  # ★doc_type 束縛 (fail-open 封鎖): 本 fork は spec (relations.html) 専用 assembler。 doc_type が spec 以外なら abort。
  [[ "$(q '.meta.doc_type')" == "spec" ]] || { echo "assemble-relations: ★meta.doc_type は spec 必須 (relations fork は spec 専用・doc_type flip で gate bypass 不可)" >&2; errs=1; }
  # 要件 id 一意性
  d="$(q '.requirements[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-relations: 要件 id 重複: $d" >&2; errs=1; }
  # section id 一意性
  d="$(q '.sections[].id' | sort | uniq -d)"; [[ -z "$d" ]] || { echo "assemble-relations: section id 重複: $d" >&2; errs=1; }
  # EARS pattern allowlist (★逐値判定: word-split に依存させない。 "ubiquitous unwanted" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する)。
  while IFS= read -r p; do [[ -v EARS_CLASS[$p] ]] || { echo "assemble-relations: 未知の EARS pattern: $p (ubiquitous|event-driven|state-driven|unwanted|optional)" >&2; errs=1; }; done < <(q '.requirements[].ears_pattern')
  # section tint allowlist (★逐値判定: 同上。 "brand violet" 等が band の class 属性へ stray token を注入する fail-open を封鎖)。
  while IFS= read -r p; do [[ -v TINT_OK[$p] ]] || { echo "assemble-relations: 未知の section tint (CSS allowlist 外): $p" >&2; errs=1; }; done < <(q '.sections[].tint')
  # ★section class allowlist (★逐値判定: tint と対称。 "normative informative" 等の空白入り値が section wrapper の class へ
  #  stray token を注入する fail-open を封鎖)。 空値 (// "" で空行化) は属性省略ゆえ許容し、 非空値のみ closed 2 値を照合する。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v CLASS_OK[$p] ]] || { echo "assemble-relations: 未知の section class (CSS allowlist 外): $p (normative|informative)" >&2; errs=1; }; done < <(q '.sections[].class // ""')
  # ★block type allowlist (silent drop 禁止・fail-closed): 未対応 block type は捨てず abort する。
  nsec="$(q '.sections | length')"
  for ((si=0; si<nsec; si++)); do
    nblk="$(q ".sections[$si].blocks // [] | length")"
    for ((bi=0; bi<nblk; bi++)); do
      btype="$(q ".sections[$si].blocks[$bi].type")"
      printf '%s' "$btype" | grep -qxE "$BLOCK_TYPE_ALLOW" \
        || { echo "assemble-relations: ★未対応 block type '$btype' (section[$si] block[$bi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
    done
    # ★機械層 block type allowlist (w1f cell-2): sections[].machine_blocks の type も逐値検査 (silent drop 禁止)。
    nmb="$(q ".sections[$si].machine_blocks // [] | length")"
    for ((mbi=0; mbi<nmb; mbi++)); do
      mbtype="$(q ".sections[$si].machine_blocks[$mbi].type")"
      printf '%s' "$mbtype" | grep -qxE "$MACHINE_BLOCK_TYPE_ALLOW" \
        || { echo "assemble-relations: ★未対応 machine block type '$mbtype' (section[$si] machine_blocks[$mbi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
    done
  done
  # ★文書前文 machine_preamble の type も逐値検査。
  npre="$(q '.machine_preamble // [] | length')"
  for ((pi=0; pi<npre; pi++)); do
    pbtype="$(q ".machine_preamble[$pi].type")"
    printf '%s' "$pbtype" | grep -qxE "$MACHINE_BLOCK_TYPE_ALLOW" \
      || { echo "assemble-relations: ★未対応 machine block type '$pbtype' (machine_preamble[$pi]・silent drop 禁止・fail-closed)" >&2; errs=1; }
  done
  # ★要件 ↔ requirements block の集合一致 (孤立要件・二重参照・存在しない要件参照を生成前に拒否)。
  #   block で参照する全 id ⊆ requirements[].id (存在しない要件参照を拒否)
  d="$(comm -23 <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u) <(q '.requirements[].id' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-relations: requirements block が未定義の要件を参照: $d" >&2; errs=1; }
  #   requirements[].id ⊆ block 参照集合 (どこにも配置されない孤立要件を拒否)
  d="$(comm -23 <(q '.requirements[].id' | sort -u) <(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort -u))"
  [[ -z "$d" ]] || { echo "assemble-relations: 配置先 block の無い孤立要件: $d" >&2; errs=1; }
  #   要件 id は block 全体で 1 回だけ参照 (二重配置を拒否 = 行数二重カウント防止)
  d="$(q '[.sections[].blocks[]? | select(.type=="requirements") | .ids[]] | .[]' | sort | uniq -d)"
  [[ -z "$d" ]] || { echo "assemble-relations: 要件が複数 block に重複配置: $d" >&2; errs=1; }
  # references role allowlist + 空 token 禁止
  # ★逐値判定 (EARS/tint と対称): word-split/glob に依存させない。 "claim rationale" 等の空白入り値が
  #  IFS split で個々の allowlist token へ分かれて素通りする fail-open を封鎖。 値そのものを 1 件ずつ照合する。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v ROLE_OK[$p] ]] || { echo "assemble-relations: 未知の reference role: $p (claim|rationale|exploration|principle|verification|implementation)" >&2; errs=1; }; done < <(q '.references[]?.role')
  if [[ "$(q 'has("references")')" == "true" ]]; then
    local n_ref n_refne n_title
    n_ref="$(q '.references | length')"; n_refne="$(q '[.references[] | select((.token // "") != "")] | length')"
    [[ "$n_ref" == "$n_refne" ]] || { echo "assemble-relations: ★references に空 token ($n_refne/$n_ref 件・空照会 token は壊れた前方照会ゆえ禁止)" >&2; errs=1; }
    # ★references[].title は ★all-or-none (ADR-0054 §2.2 一行タイトル併記)。 全件が非空 title を持つか 1 件も持たないかの
    #   2 択で、 ★部分欠落は fail-closed (chip ごとに gloss が有ったり無かったりする silent 半端形を禁止)。
    #   title 皆無の contract (extractor 再抽出物 等) は rf-gloss を emit しない旧形として通す — その 0/0 恒真 PASS は
    #   verify-relations.sh の契約非依存 census floor (rf-gloss == 13) が封鎖する。
    n_title="$(q '[.references[] | select((.title // "") != "")] | length')"
    [[ "$n_title" -eq 0 || "$n_title" -eq "$n_ref" ]] \
      || { echo "assemble-relations: ★references[].title の部分欠落 ($n_title/$n_ref 件・all-or-none 必須: 全件に一行タイトルを付すか 1 件も付さないか)" >&2; errs=1; }
  fi
  # ★requirements[].priority (RFC-2119 優先度バッジ) — references[].title と同型の all-or-none + closed allowlist。
  local n_req n_prio
  n_req="$(q '.requirements | length')"; n_prio="$(q '[.requirements[] | select((.priority // "") != "")] | length')"
  [[ "$n_prio" -eq 0 || "$n_prio" -eq "$n_req" ]] \
    || { echo "assemble-relations: ★requirements[].priority の部分欠落 ($n_prio/$n_req 件・all-or-none 必須)" >&2; errs=1; }
  # ★逐値判定 (EARS/tint/role と対称): 空白区切りの allowlist token 並びが IFS split で素通る fail-open を封鎖。
  while IFS= read -r p; do [[ -z "$p" ]] && continue; [[ -v PRIO_OK[$p] ]] || { echo "assemble-relations: 未知の priority: $p (must|should)" >&2; errs=1; }; done < <(q '.requirements[].priority // ""')
  # ★契約内不変条件: priority (宣言) == statement の RFC-2119 modal verb 由来 level (導出)。 folio-q7l7 self-review major-1。
  #   ★これが無いと contract 自身が statement と矛盾する level を宣言でき、 生成物・floor・drift の ★全 gate を素通る
  #   (priority を根とする突合は contract に対して ★自己整合 / drift は contract から再生成する byte 比較ゆえ ★全盲)。
  #   contract は「statement の SHALL/MUST → must / SHOULD → should」を ★決定的な導出規則 として明文化しているので、
  #   ここで build 時 fail-closed にする (verify-relations.sh の (iii) と ★二重保守 = detect↔remediate parity)。
  # ★導出規則 (RFC-2119 は ★大文字 のみ規範キーワード): SHALL|MUST があり SHOULD 無し → must / SHOULD があり
  #   SHALL|MUST 無し → should。 両方 / 皆無 は AMBIGUOUS-BOTH / NO-MODAL として ★不一致扱い (fail-closed)。
  local rq_id rq_prio rq_der
  while IFS= read -r rq_id; do
    [[ -n "$rq_id" ]] || continue
    rq_prio="$(q '.requirements[] | select(.id=="'"$rq_id"'") | .priority // ""')"
    [[ -n "$rq_prio" && "$rq_prio" != "null" ]] || continue
    rq_der="$(q '.requirements[] | select(.id=="'"$rq_id"'") | .statement' | perl -0777 -ne '
        my $m = /\b(?:SHALL|MUST)\b/ ? 1 : 0; my $s = /\bSHOULD\b/ ? 1 : 0;
        print $m && !$s ? "must" : ($s && !$m ? "should" : ($m ? "AMBIGUOUS-BOTH" : "NO-MODAL"));')"
    [[ "$rq_prio" == "$rq_der" ]] \
      || { echo "assemble-relations: ★priority と statement の RFC-2119 modal verb が矛盾: $rq_id (宣言 $rq_prio / statement 由来 $rq_der)" >&2; errs=1; }
  done < <(q '.requirements[].id')
  # ★ref-primary block の item field 健全性 (空 href / 空 label は壊れた一次参照ゆえ禁止・fail-closed)。
  local nrp nrpne
  nrp="$(q '[.sections[].blocks[]? | select(.type=="ref-primary") | .items[]] | length')"
  nrpne="$(q '[.sections[].blocks[]? | select(.type=="ref-primary") | .items[] | select(((.href // "") != "") and ((.label // "") != ""))] | length')"
  [[ "$nrp" == "$nrpne" ]] || { echo "assemble-relations: ★ref-primary item に空 href/label ($nrpne/$nrp 件・壊れた一次参照ゆえ禁止)" >&2; errs=1; }
  # ★graph.principle_edge (rules→constitution 終端 edge・非終端 照会の graph 接続)。
  if [[ "$(q '.graph | has("principle_edge")')" == "true" ]]; then
    p="$(q '.graph.principle_edge.role')"; [[ -v ROLE_OK[$p] ]] || { echo "assemble-relations: graph.principle_edge.role が allowlist 外: $p" >&2; errs=1; }
    d="$(q '.graph.principle_edge.target_doc_id')"; [[ -n "$d" && "$d" != "null" ]] || { echo "assemble-relations: graph.principle_edge.target_doc_id が空" >&2; errs=1; }
  fi
  [[ "$errs" -eq 0 ]] || { echo "assemble-relations: contract validation FAILED (fail-closed)" >&2; exit 1; }
}

# ---- ★静的 2 band の見出し §番号を contract から導出する (folio-q7l7 self-review major-2) ----
# 最終 section 見出しの §N の ★次 / ★次々 を静的 band (前方照会 / 用語集) の §番号とする。
# ★fail-closed: §N 形でない見出しがあれば abort (番号導出不能を silent に literal へ落とさない)。
derive_static_band_headings() {
  local last_h last_n
  last_h="$(q '.sections[].heading' | tail -n 1)"
  # ★-Mutf8 必須: -CSD は入力を decode するが ★program source の literal は decode しない — 「§」を素の byte のまま
  #   書くと decode 済み入力と一致せず ★常に 0 match (= fail-closed 側へ倒れて全 build が落ちる) になる。
  last_n="$(printf '%s' "$last_h" | perl -CSD -Mutf8 -ne 'print "$1" if /^§(\d+)\./')"
  [[ -n "$last_n" ]] || {
    echo "assemble-relations: ★最終 section の heading が §N 形でない (静的 band 番号を導出できない・fail-closed): $last_h" >&2
    exit 1
  }
  STATIC_BAND_HEADINGS=(
    "§$((last_n + 1)). ${STATIC_BAND_HEADING_TAILS[0]}"
    "§$((last_n + 2)). ${STATIC_BAND_HEADING_TAILS[1]}"
  )
}

# band / band_end (chapter-deck-band) は lib/common.sh (core) を使う。
# ---- ★章帯の巨大番号を節番号へ一致させる pack-local wrapper (ADR-0054 §2.2 / R11) ----
# core band() は文書内 ★連番 (.num = 01, 02, …) を emit するが、 relations の章は §0 始まりゆえ節番号と 1 ずれる
# (01↔§0 … 07↔§6)。 これが「変な目次」の主因の 1 つ (deck-band 連番と h2 の §N が別体系に見える)。
# ★共有 lib/common.sh の band() 本体は ★触らない (16 pack 共有ゆえ改変は doc-pack golden + gate F を巻き添える)。
#   pack-local に「core が emit した .num の値だけ」を §番号へ書き換える (帯の markup 生成は core が唯一の SSoT のまま)。
# ★data-slot-id="chapter-lead-NN" (prose manifest の key) は ★連番のまま = 書き換えない (slot 契約不変)。
# ★subshell 禁止: band() は core の CHAPN を進めるため $(band …) で捕まえると連番が進まない (slot-id が全て 01 になる)。
#   リダイレクトは subshell を作らないので tmp file 経由で捕まえる。
# ★fail-loud: 置換が no-op なら abort (core band() の shape drift を silent no-op = 番号ズレ温存にしない)。
band_num() { # tint kicker heading icon_inner
  local seq num t
  t="$(mktemp)"
  band "$1" "$2" "$3" "$4" > "$t"
  printf -v seq '%02d' "$CHAPN"      # 直前の band() が emit した連番 (core が進めた値)
  num=$((CHAPN - 1))                 # relations の章は §0 始まり = 連番 - 1
  sed "s|<span class=\"num\">$seq</span>|<span class=\"num\">$num</span>|" "$t" > "$t.n"
  if cmp -s "$t" "$t.n"; then
    rm -f "$t" "$t.n"
    echo "assemble-relations: ★band .num の §番号書換が no-op (core band() の shape drift・fail-closed)" >&2; exit 1
  fi
  cat "$t.n"; rm -f "$t" "$t.n"
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
[data-component="spec-subsubhead"]{margin:10px 0 4px}
[data-component="spec-subsubhead"] h4{margin:0;font-size:13px;font-weight:700;color:var(--ink-soft)}
/* ★空 subsection の人間層 1 行要約 (ADR-0054 §2.2)。 subhead の .sub-se と同形にして見た目を揃える。 */
[data-component="spec-subsubhead"] .sub-se{margin:4px 0 0;font-size:12.5px;line-height:1.65;color:var(--ink-soft);background:var(--paper-2);border-radius:7px;padding:6px 11px}
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
/* ★「やさしく言うと」平易行 + RFC-2119 優先度バッジ (ADR-0054 §2.2・pw-spec MINOR-1)。 色 token は srs.css 準拠。 */
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
/* ★一次参照 (外部 URL) の人間層可視リスト (ADR-0054 §2.2 / rw finding 3)。 */
ul[data-component="spec-ref-primary"]{margin:8px 0 0;padding-left:4px;list-style:none;display:flex;flex-direction:column;gap:5px}
ul[data-component="spec-ref-primary"] .rpi{position:relative;padding-left:18px;font-size:13px;line-height:1.7;color:var(--ink)}
ul[data-component="spec-ref-primary"] .rpi::before{content:"\2197";position:absolute;left:0;color:var(--brand);font-size:11px;top:3px}
ul[data-component="spec-ref-primary"] .rp-note{color:var(--ink-soft);font-size:12.5px}
/* ★chrome-less 化 (ADR-0054 §2.1・Cell 0 = bin/folio が注入する部品) の見た目を pack 側で所有する。
   生成 spec は common.css を読まない (pack inline style が提示層 SSoT) ため、 skip-link の hidden-until-focus と
   下部 locator の体裁はここで与える (Cell 0 開示 #2)。 */
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
@media print{[data-component="spec-machine-fold"]{display:none}}
CSS
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja">\n<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta name="generator" content="folio spec-pack assembler (relations fork / folio-hd0) — deterministic structure, prose slots unfilled">\n'
  printf '<title>%s</title>\n<style>\n' "$(esc "$1")"
  cat "$CSS"
  emit_spec_css
  printf '\n</style>\n'
  # 図 (mermaid) がある doc にだけ vendor を head に1回 load (defer・図ゼロなら何も出さない)。 ../assets/mermaid.min.js を参照。
  [[ "${HAS_MERMAID:-0}" -gt 0 ]] && printf '<script src="../assets/mermaid.min.js" defer></script>\n'
  core_emit_graph_head
  printf '</head>\n<body>\n'
}

emit_cover() {
  core_emit_cover_head "この spec が約束すること (1 文サマリ)"
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
  cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
  printf '<div class="tbl-wrap"><table data-component="spec-table">'
  [[ -n "$cap" && "$cap" != "null" ]] && printf '<caption>%s</caption>' "$(esc "$cap")"
  printf '<thead><tr>'
  while IFS= read -r h; do printf '<th>%s</th>' "$(esc "$h")"; done < <(q ".sections[$si].blocks[$bi].headers[]")
  printf '</tr></thead><tbody>\n'
  nrow="$(q ".sections[$si].blocks[$bi].rows | length")"
  for ((ri=0; ri<nrow; ri++)); do
    printf '<tr>'
    while IFS= read -r c; do printf '<td>%s</td>' "$(esc "$c")"; done < <(q ".sections[$si].blocks[$bi].rows[$ri][]")
    printf '</tr>\n'
  done
  printf '</tbody></table></div>\n'
}
emit_mermaid() {
  local si="$1" bi="$2" cap
  # ★render target = <pre class="mermaid"> (head の mermaid.min.js が SVG 描画する) + raw DSL を逐語保持 (round-trip 維持)。
  #   旧 <pre class="mermaid-src"> は raw DSL を露出するだけで描画されず gate I blocker (図の約束と実体が乖離) だった。
  printf '<figure data-component="spec-diagram" class="diagram"><pre class="mermaid">'
  local first=1
  while IFS= read -r line; do [[ "$first" -eq 1 ]] && first=0 || printf '\n'; printf '%s' "$(esc "$line")"; done < <(q ".sections[$si].blocks[$bi].source_lines[]")
  printf '</pre>'
  # figcaption: contract の caption を優先。 空なら DSL 内の accDescr → accTitle を fallback 抽出 (gate I が figcaption 空を指摘・両者とも SSoT 由来)。
  cap="$(q ".sections[$si].blocks[$bi].caption // \"\"")"
  if [[ -z "$cap" ]]; then
    cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accDescr:[[:space:]]*//p' | head -1)"
    [[ -z "$cap" ]] && cap="$(q ".sections[$si].blocks[$bi].source_lines[]" | sed -n 's/^[[:space:]]*accTitle:[[:space:]]*//p' | head -1)"
  fi
  printf '<figcaption>%s</figcaption></figure>\n' "$(esc "$cap")"
}
emit_subhead() {
  # ★navigable anchor (folio-0x0k pre-flip): 原本 h3 の実 id (fine section anchor) を h3 へ刻む = corpus inbound の解決先。
  #   ★assemble-spec.sh の emit_subhead と ★対称 (両系統同一変更)。 relations は原本 16 h3 が全て id 保有だが、 rules fork の
  #   §4.1-4.4 (原本 id 不在) と同じ ★条件付き emit を共有する: 非空なら <h3 id="…">、 空なら <h3> (原本に無い id を捏造しない)。
  #   silent id-loss の fail-closed は verify-relations の「subhead anchor 列」突合が担う。
  local anchor h3open
  anchor="$(q ".sections[$1].blocks[$2].anchor // \"\"")"
  if [[ -n "$anchor" && "$anchor" != "null" ]]; then h3open="<h3 id=\"$(esc "$anchor")\">"; else h3open="<h3>"; fi
  printf '<div data-component="spec-subhead">%s%s</h3><p class="sub-se">%s</p></div>\n' \
    "$h3open" "$(esc "$(q ".sections[$1].blocks[$2].heading")")" "$(esc "$(q ".sections[$1].blocks[$2].essence")")"
}
# 1 h4 sub-subhead を emit (folio-0x0k errata E1・relations §4.4.1-3 = 第 4 anchor クラス)。 原本 <h4 id="s4-4-N-*"> の実 id を刻む。
#   ★全 subsubhead entry が anchor 保有 (原本 h4 4 本中 id 有 3 本のみを extractor が subsubhead 化・:503 の id-less 例見出しは
#   prose 経路へ fallthrough し subsubhead 化しない = errata E4) = hard fail-closed guard (subhead と異なり空を許さない)。 essence は持たない。
emit_subsubhead() {
  local anchor ess
  anchor="$(q ".sections[$1].blocks[$2].anchor // \"\"")"
  [[ -n "$anchor" && "$anchor" != "null" ]] || { echo "assemble-relations: ★subsubhead (section[$1] block[$2]) の anchor (navigable id) が空 (corpus inbound #s4-4-1-scan 等の解決先を失う・fail-closed)" >&2; exit 1; }
  # ★essence (ADR-0054 §2.2「既定 (人間層) 表示で本文ゼロの見出しを作らない」): 人間層 block を持たない subsubhead に
  #   1 行要約を併記する。 subhead と ★同じ .sub-se 形 (見た目も揃える) で div の ★内側 に置く。 optional ゆえ
  #   非空のときだけ emit する (原本に無い要約を捏造しない・空 essence で空の <p> を作らない)。
  ess="$(q ".sections[$1].blocks[$2].essence // \"\"")"
  if [[ -n "$ess" && "$ess" != "null" ]]; then
    printf '<div data-component="spec-subsubhead"><h4 id="%s">%s</h4><p class="sub-se">%s</p></div>\n' \
      "$(esc "$anchor")" "$(esc "$(q ".sections[$1].blocks[$2].heading")")" "$(esc "$ess")"
  else
    printf '<div data-component="spec-subsubhead"><h4 id="%s">%s</h4></div>\n' \
      "$(esc "$anchor")" "$(esc "$(q ".sections[$1].blocks[$2].heading")")"
  fi
}
# ★一次参照 (外部 URL) の人間層可視リスト (ADR-0054 §2.2 / rw finding 3)。 人間層 emit_list は item を esc() するため
#   <a href> を書けない (contract header の確定裁定) — ゆえ href / label / note を ★別 field で受ける専用 emitter を持つ。
#   各 field は個別に esc してから注入する (fab-free by construction: 生 markup は構造へ漏れない)。
#   ★a に class="xref" は付けない (a.xref census = 原本由来 8 件を動かさない)。
emit_ref_primary() {
  local si="$1" bi="$2" n i href label note
  n="$(q ".sections[$si].blocks[$bi].items | length")"
  printf '<ul class="ref-primary" data-component="spec-ref-primary">\n'
  for ((i=0; i<n; i++)); do
    href="$(q ".sections[$si].blocks[$bi].items[$i].href")"
    label="$(q ".sections[$si].blocks[$bi].items[$i].label")"
    note="$(q ".sections[$si].blocks[$bi].items[$i].note // \"\"")"
    printf '<li class="rpi"><a href="%s">%s</a> <span class="rp-note">%s</span></li>\n' \
      "$(esc "$href")" "$(esc "$label")" "$(esc "$note")"
  done
  printf '</ul>\n'
}
# 1 要件 row を emit ($1 = 要件 id)。
emit_requirement_row() {
  local id="$1" pat essence stmt class label anchor prio prio_badge
  pat="$(q '.requirements[] | select(.id=="'"$id"'") | .ears_pattern')"
  essence="$(q '.requirements[] | select(.id=="'"$id"'") | .essence')"
  stmt="$(q '.requirements[] | select(.id=="'"$id"'") | .statement')"
  # ★navigable anchor (folio-0x0k pre-flip): 原本 <details class="spec-row" id="req-rel-*"> の実 id を row へ刻む (assemble-spec と対称)。
  #   corpus inbound (relations.html#req-rel-001 等) の解決先。 data-req-id (大文字 SSoT) への *追加* であり置換ではない。 全要件 anchor 保有 = hard fail-closed。
  anchor="$(q '.requirements[] | select(.id=="'"$id"'") | .anchor // ""')"
  [[ -n "$anchor" && "$anchor" != "null" ]] || { echo "assemble-relations: ★要件 $id の anchor (navigable id) が空 (corpus inbound の解決先を失う・fail-closed)" >&2; exit 1; }
  # validate() が ears_pattern を allowlist 逐値判定済 = ここは到達不能であるべき。 :-unknown silent fallback でなく
  # hard error 化し、 万一 validate を擦り抜けた未知 pattern が無スタイル class="unknown" badge として silent emit されるのを封鎖。
  [[ -v EARS_CLASS[$pat] ]] || { echo "assemble-relations: ★到達不能: emit 時に未知 EARS pattern '$pat' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
  class="${EARS_CLASS[$pat]}"; label="${EARS_LABEL[$pat]}"
  # ★canonical dual-audience requirement (w1f cell-2 / ADR-0045 論点2): row = human container (data-audience="human")、
  #   normative fold = machine 部 (data-audience="machine")。 REQ-DA-STRUCT-1 (human→machine 子孫) / -2 (id 整合) /
  #   -4 (machine 部 aria-hidden 無し) / -5 (EARS-pattern 整合) を *生成物* へ適用する (floor 射程拡大)。
  #   ★適合は verify-relations §10 が *相当* に enforce する。 canonical な bin/folio folio_check_dual_audience は
  #   要件 container を <(section|details) data-audience="human"> で key するため、 本 row は <div> ゆえ未被覆
  #   (生成物は /tmp 生成で folio validate 非対象)。 canonical container form (section/details) への寄せ・
  #   validate-gate 被覆は follow-up (folio-tr0 置換/drift gate) 領分。
  # ★RFC-2119 優先度バッジ (ADR-0054 §2.2)。 class は contract の closed allowlist 値から決定的に導く。 可視ラベルは
  #   prose slot (空で emit → inject-prose が manifest から充填) ゆえ ここでは ★空要素 を置く。 priority を持たない
  #   contract では バッジごと emit しない (all-or-none は validate 済・0/0 恒真は verify の census floor が封鎖)。
  prio="$(q '.requirements[] | select(.id=="'"$id"'") | .priority // ""')"
  prio_badge=""
  if [[ -n "$prio" && "$prio" != "null" ]]; then
    [[ -v PRIO_OK[$prio] ]] || { echo "assemble-relations: ★到達不能: emit 時に未知 priority '$prio' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
    prio_badge="$(printf '<span class="rq-prio rq-prio-%s" data-prose-slot="priority" data-slot-id="prio-%s"></span>' "$prio" "$(esc "$anchor")")"
  fi
  printf '<div data-component="ears-requirement-row" id="%s" data-req-id="%s" data-ears-pattern="%s" data-audience="human">\n' "$(esc "$anchor")" "$(esc "$id")" "$(esc "$pat")"
  printf '<div class="rq-head"><span class="rid">%s</span>%s<span data-component="ears-badge" class="%s">%s</span></div>\n' "$(esc "$id")" "$prio_badge" "$class" "$(esc "$label")"
  printf '<p class="rq-essence">%s</p>\n' "$(esc "$essence")"
  # ★「やさしく言うと」平易行 (ADR-0054 §2.2)。 本文は prose slot (人間層 edit-SSoT = prose manifest・ADR-0052 §2.4) で、
  #   assembler は ★空要素だけ を決定的に置く (要件 essence/normative は contract SSoT のまま不変 = 平易行は ★純追加)。
  printf '<p class="rq-plain"><span class="rq-plain-k">やさしく言うと</span><span data-prose-slot="plain" data-slot-id="plain-%s"></span></p>\n' "$(esc "$anchor")"
  printf '<details class="rq-norm" data-audience="machine"><summary>%s</summary><p class="rq-stmt">%s</p></details>\n' "$(esc "$RQ_NORM_SUMMARY")" "$(esc "$stmt")"
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
    prose) # ★folio-0x0k errata E2: anchor 保有機械層 prose は <p id="…"> で emit (assemble-spec と対称・relations の機械 p は id 無しゆえ常に else 枝)。
           local manc; manc="$(q "$base.anchor // \"\"")"
           if [[ -n "$manc" && "$manc" != "null" ]]; then
             printf '<p id="%s" data-component="spec-machine-prose" data-audience="machine">%s</p>\n' "$(esc "$manc")" "$(q "$base.html")"
           else
             printf '<p data-component="spec-machine-prose" data-audience="machine">%s</p>\n' "$(q "$base.html")"
           fi ;;
    note)  printf '<aside data-component="spec-machine-note" data-audience="machine">%s</aside>\n' "$(q "$base.html")" ;;
    list)  printf '<ul data-component="spec-machine-list" data-audience="machine">\n'
           while IFS= read -r it; do printf '<li class="mli">%s</li>\n' "$it"; done < <(q "$base.items[]")
           printf '</ul>\n' ;;
    *) echo "assemble-relations: ★到達不能: emit 時に未対応 machine block type '$mt' ($base・validate を擦り抜けた・fail-closed)" >&2; exit 1 ;;
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
      subsubhead)   emit_subsubhead "$si" "$bi" ;;
      requirements) emit_requirements "$si" "$bi" ;;
      ref-primary)  emit_ref_primary "$si" "$bi" ;;
      *) echo "assemble-relations: ★未対応 block type '$btype' (silent drop 禁止・fail-closed)" >&2; exit 1 ;;
    esac
  done
}

emit_section() {
  local si="$1" tint kicker heading essence icon anchor cls
  tint="$(q ".sections[$si].tint")"
  kicker="$(q ".sections[$si].kicker")"
  heading="$(q ".sections[$si].heading")"
  essence="$(q ".sections[$si].essence")"
  icon="${SECT_ICONS[$(( si % ${#SECT_ICONS[@]} ))]}"
  # ★top-level section anchor (folio-0x0k pre-flip): 原本 <section id="s1-w3c-vocab"> の実 id を章頭へ刻む (assemble-spec と対称)。
  #   ★band() = CORE 不触ゆえ pack-level で章全体を anchor 付き <section> で包む。 全 section anchor 保有 = hard fail-closed。
  anchor="$(q ".sections[$si].anchor // \"\"")"
  [[ -n "$anchor" && "$anchor" != "null" ]] || { echo "assemble-relations: ★section[$si] の anchor (navigable id) が空 (corpus inbound の解決先を失う・fail-closed)" >&2; exit 1; }
  # ★section.class (folio-jmz1): canonical relations.html の section.normative / section.informative wrapper を生成側で保持する。
  #   contract 値は validate() で CLASS_OK (closed 2 値) 照合済ゆえ esc 不要 (直接埋込)。 空値 (contract 非保有) は属性を省略する。
  cls="$(q ".sections[$si].class // \"\"")"
  if [[ -n "$cls" && "$cls" != "null" ]]; then
    printf '<section id="%s" class="%s">\n' "$(esc "$anchor")" "$cls"
  else
    printf '<section id="%s">\n' "$(esc "$anchor")"
  fi
  band_num "$tint" "$kicker" "$heading" "$icon"
  printf '<div data-component="section-essence-callout"><p class="sec-se">%s</p></div>\n' "$(esc "$essence")"
  emit_blocks "$si"
  # ★機械層 (w1f cell-2): この章の data-audience="machine" 自由文を fold で既定非表示・人間層 (essence/blocks) の後に置く。
  emit_machine_fold ".sections[$si].machine_blocks" "$heading の地の文・運用説明・rationale"
  band_end
  # ★anchor 付き <section> を閉じる (band_end = chapbody の </div> の ★外側)。
  printf '</section>\n'
}

# references = 非終端 照会 (前方・他文書へ)。 token/doc/role を固定属性で刻む (verify-relations が echo 厳密一致で突合)。
emit_references() {
  printf '<div class="ref-grid">\n'
  # ★IFS= read で 1 行受け手動 tab split (emit_glossary/folio-4wz と同型): 空 title (title 無し contract) が
  #   IFS-whitespace の tab 畳みで列を潰すのを防ぐ (@tsv は常に 4 列 = 3 tab)。
  q '.references[] | [.token, .doc, .role, (.title // "")] | @tsv' | while IFS= read -r line; do
    token="${line%%$'\t'*}"; rest="${line#*$'\t'}"
    doc="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
    role="${rest%%$'\t'*}"; title="${rest#*$'\t'}"
    [[ -n "$token" ]] || continue
    # ★role の可視ラベルだけ平易語 map を適用 (attr data-ref-role は ★機械 token を保持)。 map 外 role は hard error
    #   (validate の ROLE_OK と同一 key 集合ゆえ到達不能であるべき・silent な英語生表示 fallback を封鎖)。
    [[ -v ROLE_PLAIN[$role] ]] || { echo "assemble-relations: ★到達不能: emit 時に平易語 map 外の role '$role' (validate を擦り抜けた・fail-closed)" >&2; exit 1; }
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
# data-component=ears-legend-item は ears-badge とは別 (verify-relations の ears-badge==|requirements| カウントに干渉させない)。
emit_ears_legend() {
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
  core_emit_footer '<span>folio design system</span><span>spec-pack (relations fork)</span><span>folio engine tr0 (folio-hd0)</span><span>EARS 章立て + 非終端 照会</span>'
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
  #   ため「章としての到達可能性」を持たなかった (pw-spec MAJOR-1: 目次から辿れない章の根本原因)。 section id 付きの
  #   章として包む。 ★id は番号なし canonical token (PRESENTATION_WRAPPER_IDS)・★class は付けない (census 不変)。
  # 非終端 照会 (前方 references) band。 ★heading は実在する照会種別のみを約束する (R5: 旧「原則・ADR・検証へ」は
  #   REQ-VER チップ 0 件の over-promise だった)。
  printf '<section id="%s">\n' "$(esc "${PRESENTATION_WRAPPER_IDS[0]}")"
  band_num violet "この規約が参照する文書 / 照会 (前方)" "${STATIC_BAND_HEADINGS[0]}" "$ICO_ARROW"
  emit_references
  band_end
  printf '</section>\n'
  # 用語集 band (core glossary)。
  printf '<section id="%s">\n' "$(esc "${PRESENTATION_WRAPPER_IDS[1]}")"
  band_num brand "用語集 / この文書で使う専門語" "${STATIC_BAND_HEADINGS[1]}" "$ICO_TAG"
  emit_glossary
  band_end
  printf '</section>\n'
  printf '</div>\n'
  emit_footer
  emit_mermaid_script
  printf '</body>\n</html>\n'
}

validate
core_finalize "assemble-relations"
