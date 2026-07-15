#!/usr/bin/env bash
# project-vocabulary.sh — glossary contract (edit-SSoT) → design-intent/vocabulary.yaml (生成 projection)
#
# ADR-0052 の SSoT 再指定: contract YAML = 機械層 edit-SSoT / vocabulary.yaml = その **生成 projection**
# (runtime SSoT)。 folio-9inj で置いた「手動同鏡・片側編集禁止」は人間規律に依存する二重保持だったため、
# 機械導出 + stale gate へ転換する (導出は drift を構造的に不可能にする — DITA/literate の prior art と同型)。
#
# 全域関数 (contract.terms[] → vocab.terms[]・36 語で成立実測):
#   canonical  ← .terms[].canonical
#   domain     ← .terms[].domain
#   definition ← .terms[].formal_def
#
# ★header は本 script 内のリテラル定数 (VOCAB_HEADER) としてハードコードする (folio-wg2l Leg 0 ②)。
#   committed vocabulary.yaml から header を読み戻して再出力すると「committed を種にして committed を
#   検査する」循環になり、 header 改竄が projection にも伝播して byte 比較が恒真 PASS 化する。
#
# ★出力整形は yq -o=yaml -P 固定 (quote 剥ぎ・空白畳み等の後段正規化を挟まない)。 stale gate は
#   normalize せず whole-file byte 比較するため、 整形は「script が出す形」が唯一の正解になる
#   (committed は本 script の出力そのもので生成し直して commit する = byte 一致を construction で保証)。
#
# usage: project-vocabulary.sh [--contract <path>] [--out <path>]
#   既定 contract = <generator>/contract/folio-glossary.glossary.yaml
#   既定 out      = /dev/stdout (stale gate は毎回新規 mktemp へ出力して committed と byte 比較する)
# exit: 0 = 生成成功 / 2 = 構成エラー (依存欠落・contract 不在/parse 不能・anchor 崩壊)
#
# 設計主体: folio-wg2l worker cell (Leg A)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

die() { echo "project-vocabulary: $*" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/contract/folio-glossary.glossary.yaml"
OUT="/dev/stdout"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract) [[ $# -ge 2 ]] || die "--contract に引数が無い"; CONTRACT="$2"; shift 2 ;;
    --out)      [[ $# -ge 2 ]] || die "--out に引数が無い";      OUT="$2";      shift 2 ;;
    *) die "未知の引数 '$1' (usage: project-vocabulary.sh [--contract <path>] [--out <path>])" ;;
  esac
done

command -v yq >/dev/null 2>&1 || die "yq required (fail-closed)"
command -v jq >/dev/null 2>&1 || die "jq required (fail-closed)"
[[ -f "$CONTRACT" ]] || die "contract 不在: $CONTRACT"

# ---- 固定 header template (リテラル定数・committed から読まない = 循環禁止) ----
# 本文は「生成物 warning + 再生成手順 + 導出規則 + 機械強制 + 消費点 + schema 規約」。 手書き時代の
# rationale のうち projection で失われる inline コメントは (a) 語彙運用に効くもの = ここへ、
# (b) 語ごとの編集判断に効くもの = contract 側の YAML コメントへ、 と分けて移設済 (folio-wg2l)。
read -r -d '' VOCAB_HEADER <<'HEADER' || true
# folio canonical vocabulary (glossary runtime SSoT)
# ★★ このファイルは生成物です。 手編集しないでください (次の再生成で失われます)。 ★★
#
# edit-SSoT (ここを編集する): .claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml
# 生成 script              : .claude-plugin/design-system/generator/project-vocabulary.sh
# 再生成                   : .claude-plugin/design-system/generator/project-vocabulary.sh \
#                              --out design-intent/vocabulary.yaml
#
# ADR-0052 (SSoT 再指定): 本 file は glossary contract の terms[] からの **生成 projection**。
#   旧 folio-9inj の「手動同鏡・片側編集禁止」(人間規律に依存する二重保持) から機械導出へ転換した。
#   導出規則 (全域関数):
#     canonical  ← contract .terms[].canonical
#     domain     ← contract .terms[].domain
#     definition ← contract .terms[].formal_def
#   語の追加・削除・定義改訂は **contract 側だけ** を編集し、 本 file を再生成して同一 commit で land する。
#
# 機械強制: verify-glossary-parity.sh の vocab-projection 節が「committed == fresh projection」を
#   whole-file byte 比較する (header 1 字・definition 1 字の改竄も FAIL)。 同 script は ci.yml の
#   deterministic floor に blocking 配線済ゆえ、 手編集 / 再生成漏れ (stale) は merge block される。
#
# 消費点 (本 file を runtime SSoT として読む機構):
#   - folio fix     : spec HTML の <span class="term" data-term="X"> へ data-tooltip = definition を materialize
#                     (auto-mark + populate、 REQ-GLOSS-001/002)
#   - folio validate: glossary gate (resolve + tooltip-consistency) / xref-tooltip-consistency
#   - folio build   : Layer 1 consumer root の glossary.html を内部 emitter で derive (ADR-0036)。
#                     ★folio 自身 (self-host root) の glossary.html は contract → pack pipeline
#                     (assemble-glossary.sh + inject-prose.sh) 委譲で生成するため本 file 由来ではない
#                     (build-orchestrates-pack、 ADR-0052)。
#
# schema 規約 (rules §3 / ADR-0034 §2.8 / ADR-0036):
#   - domain = folio-closed | consumer (ADR-0036 §2.2 partition)。 folio-closed = folio 所有・固定ゆえ
#     folio が canonical 定義を ship し consumer は plugin-resident の本 file から derive/auto-mark で
#     受け取る ($CLAUDE_PLUGIN_ROOT)。 consumer = consumer 所有・folio 解説不能。 folio 自身の vocab は
#     全て folio-closed。
#   - definition は単一行 (tooltip 機構は改行を扱わない)。 HTML 特殊文字 (& < > ") は folio fix が
#     attribute-escape して data-tooltip に格納する。
#   - definition に生の > / < を書かない (矢印は → / 比較は文章で表現): scan 系の tag 除去 (<[^>]*>) が
#     属性内の生 > でタグ境界を誤認する latent を avoid する不変条件 (ef4 slice B ceiling)。 contract 側で守る。
#
# forbidden は意図的に載せない (vocabulary gate REQ-CI-013 の誤検出 risk を避ける = #110 D2)。
#   ★"architecture" の forbidden 機械化は ADR-0048 rename 後も不可 (folio-7c4 再評価 2026-07-12 で census
#   確定): REQ-CI-013 は grep -F 部分一致ゆえ (a) 複合語 canonical (architecture-description /
#   architecture-nav-derive 等) を誤検出し、 (b) frozen ADR 約 30 本 + superseded research の歴史 prose に
#   裸出現が数百残る (P-10 で書換不能 = 恒久 RED・gate (d) に per-file waiver 機構なし)。 多義 (1 名 = 3
#   entity) の解消は P-5 forbidden (1 entity = 複数名 用) ではなく、 各 entity へ別 canonical 完全形を
#   宣言する語レベル整理で行う (architecture-description / design-intent space / Layer Architecture・
#   folio-c5r.7)。 概念用法 (arc42 / constitution §1 引用 / Architecture Decision Records) は ADR-0048 §5
#   どおり正当に存続する。
HEADER

# ---- contract anchor 完全性 (projection の土台。 崩壊は exit 2 = 空/半端な出力を出さない) ----
CJSON="$(mktemp)"; trap 'rm -f "$CJSON"' EXIT
yq -o=json '.' "$CONTRACT" > "$CJSON" 2>/dev/null || die "contract parse 失敗: $CONTRACT"

nterms="$(jq -r '.terms // [] | length' "$CJSON")"
[[ "$nterms" =~ ^[0-9]+$ ]] || die "terms 件数の取得に失敗: $CONTRACT"
[[ "$nterms" -ge 1 ]] || die "contract の terms[] が空 (projection の土台が無い): $CONTRACT"

# 非 object / canonical・domain・formal_def の空 / C0 制御文字 = anchor 崩壊 (verify-glossary-parity の
# ssot-malformed と同基準。 空 definition を projection へ通すと vocab 消費側が黙って壊れる)。
nbad="$(jq -r '[.terms // [] | .[]
  | select((type != "object")
      or (((.canonical  // "") | tostring) == "")
      or (((.domain     // "") | tostring) == "")
      or (((.formal_def // "") | tostring) == "")
      or ((((( .canonical // "") | tostring) + ((.domain // "") | tostring) + ((.formal_def // "") | tostring))
           | explode | map(select(. < 32)) | length) > 0))] | length' "$CJSON")"
[[ "$nbad" == "0" ]] || die "contract anchor 崩壊: canonical/domain/formal_def が空 or 制御文字 or 非 object の term $nbad 件 ($CONTRACT)"

dup="$(jq -r '.terms // [] | .[] | (.canonical // "") | tostring' "$CJSON" | LC_ALL=C sort | LC_ALL=C uniq -d)"
[[ -z "$dup" ]] || die "contract canonical 重複 (projection が last-win で語を落とす): $(printf '%s' "$dup" | tr '\n' ' ')"

# ---- projection 本体 (yq -o=yaml -P 固定・後段正規化なし) ----
BODY="$(mktemp)"; trap 'rm -f "$CJSON" "$BODY"' EXIT
yq -o=yaml -P '{"terms": [.terms[] | {"canonical": .canonical, "domain": .domain, "definition": .formal_def}]}' \
  "$CONTRACT" > "$BODY" 2>/dev/null || die "projection の yq 変換に失敗: $CONTRACT"
[[ -s "$BODY" ]] || die "projection 出力が空 (再生成不能)"

# 出力 precondition (fail-closed): 構造マーカー + 語数の往復一致。 「projection は走ったが中身が壊れた」を
# 素通りさせない (空/半端な出力で committed を上書きすると stale gate が恒真 PASS 化する)。
head -1 "$BODY" | grep -qx 'terms:' || die "projection 出力に構造マーカー 'terms:' が無い (先頭行崩れ)"
nout="$(yq -r '.terms | length' "$BODY" 2>/dev/null)" || die "projection 出力が yq で再 parse 不能"
[[ "$nout" == "$nterms" ]] || die "projection 語数不一致: contract $nterms 語 / 出力 $nout 語 (導出の全域性が崩れた)"

# ---- header + body を out へ (temp→mv = 途中失敗で committed を半端に壊さない) ----
TMPOUT="$(mktemp)"; trap 'rm -f "$CJSON" "$BODY" "$TMPOUT"' EXIT
printf '%s\n' "$VOCAB_HEADER" > "$TMPOUT"
cat "$BODY" >> "$TMPOUT"

if [[ "$OUT" == "/dev/stdout" ]]; then
  cat "$TMPOUT"
else
  mv "$TMPOUT" "$OUT" || die "書込失敗: $OUT"
  echo "project-vocabulary: wrote $OUT (${nterms} 語・contract=$(basename "$CONTRACT"))" >&2
fi
