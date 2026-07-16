#!/usr/bin/env bash
# assemble-glossary.sh — folio glossary-pack (instance #1, folio self-host) deterministic assembler
# doc_type: glossary (canonical vocabulary)。 機械 SSoT = contract/folio-glossary.glossary.yaml
# (design-intent/vocabulary.yaml + design-intent/glossary.html 由来、 read-only source)。
#
# 設計:
#   - 全 visible token は contract YAML 由来 (fabrication-free)。 plain 定義のみ prose スロットで後注入。
#   - 各 term は dual-audience: human 層 (term-name + plain 定義 prose スロット) +
#     machine 層 (<details data-audience="machine">: 構造化レコード en/slug/domain/formal_def +
#     JSON-LD schema:DefinedTerm + cross-doc anchor data-xref-target)。
#   - prose スロット (cover-summary / plain-<slug>) は data-slot-id + data-prose-slot 空要素で emit。
#   - core (lib/common.sh + inject-prose.sh) は無改変流用。
#
# usage: assemble-glossary.sh [contract.yaml] > out.html
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

CONTRACT="${1:-$HERE/contract/folio-glossary.glossary.yaml}"
CSS="$HERE/../srs.css"
[[ -f "$CONTRACT" ]] || { echo "assemble-glossary: contract not found: $CONTRACT" >&2; exit 1; }
[[ -f "$CSS" ]] || { echo "assemble-glossary: srs.css not found: $CSS" >&2; exit 1; }
# ★空/切り詰め CSS の封鎖 (folio-zpvv self-review finding#1)。 `-f` は存在しか見ず 0 byte を通すため、
#   未スタイル page (<style></style>) が pack の全 precondition (DOCTYPE / folio-generated marker /
#   class="term-name" / サイズ下限) を素通りし committed を上書きしうる。 上書きが起きた瞬間
#   committed==fresh となり nav-regen-drift が恒真 PASS 化する (silent revert = drift の恒久的不可視化)。
#   撤去した verify-asset-sync.sh の「下限 100 byte」precondition (= その MK5「両方を空 file 化 → rc=2」)
#   をここへ移管し、 inline 化で唯一の番人となった本 guard を fail-closed に保つ。
css_sz=$(wc -c < "$CSS")
[[ "$css_sz" -ge 100 ]] || { echo "assemble-glossary: srs.css が空/切り詰め (${css_sz} byte < 下限 100) — 未スタイル page の emit を封鎖 (fail-closed)" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-glossary: yq required" >&2; exit 1; }

DOC_ID="$(q '.doc_id')"
TITLE="$(q '.title')"
VERSION="$(q '.version')"
DOC_TYPE="$(q '.doc_type')"
SET_ID="$(q '.term_set_id')"
SET_NAME="$(q '.term_set_name')"
NTERMS="$(yq -r '.terms | length' "$CONTRACT")"
core_validate_strings "assemble-glossary head" "$DOC_ID" "$TITLE" "$DOC_TYPE" "$SET_ID" "$SET_NAME"

# ---- canonical_page (条件 emit・ADR-0052 build-orchestrates-pack / folio-wg2l) ----
# 本 block を持つ contract の出力のみ folio scanner 互換 head を emit する (folio canonical page 宣言)。
# 無条件 hardcode は demo suite (clinic) の成果物に虚偽の「folio build 生成物」marker を付け、 folio
# build/validate の marker keystone を汚染するため禁止 (fence「clinic 汚染防止」)。
# 部分指定 (一部 field だけ) は head が半端になるため fail-closed (全 field 必須 or block 全欠)。
CANON_ID="$(yq -r '.canonical_page.id // ""' "$CONTRACT")"
CANON_GEN="$(yq -r '.canonical_page.generated_by // ""' "$CONTRACT")"
CANON_DTYPE="$(yq -r '.canonical_page.doc_type // ""' "$CONTRACT")"
CANON_STATUS="$(yq -r '.canonical_page.status // ""' "$CONTRACT")"
CANON_PAGE=0
if [[ -n "$CANON_ID$CANON_GEN$CANON_DTYPE$CANON_STATUS" ]]; then
  [[ -n "$CANON_ID" && -n "$CANON_GEN" && -n "$CANON_DTYPE" && -n "$CANON_STATUS" ]] \
    || { echo "assemble-glossary: canonical_page は id/generated_by/doc_type/status の全指定が必須 (部分指定は head が半端になる・fail-closed)" >&2; exit 1; }
  core_validate_strings "assemble-glossary canonical_page" "$CANON_ID" "$CANON_GEN" "$CANON_DTYPE" "$CANON_STATUS"
  CANON_PAGE=1
fi

jsonld_safe() { # $1 = value : JSON/script を壊す文字が無いことを fail-closed で確認
  case "$1" in
    *'"'*|*'\'*|*'<'*|*'>'*|*'&'*) echo "assemble-glossary: JSON-LD 不適合文字: $1" >&2; exit 1 ;;
  esac
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="%s">\n' "$(esc "$DOC_ID")" "$(esc "$DOC_TYPE")"
  printf '<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
  # ★canonical page の folio scanner 互換 meta (条件 emit)。 folio-generated marker は folio build --check /
  #   folio validate nav-regen-drift の keystone = 欠落すると両 gate が沈黙 skip して恒真 PASS になる
  #   (fence「marker vacuous-green 封鎖」)。 folio_extract_meta は grep -oP の厳密書式ゆえ属性順・空白を変えない。
  if [[ "$CANON_PAGE" -eq 1 ]]; then
    printf '<meta name="folio-doc-type" content="%s">\n' "$(esc "$CANON_DTYPE")"
    printf '<meta name="folio-generated" content="%s">\n' "$(esc "$CANON_GEN")"
    printf '<meta name="folio-status" content="%s">\n' "$(esc "$CANON_STATUS")"
  fi
  # ★srs.css は inline (他 15 pack と同方式・自己完結)。 外部 <link> は配信 root に copy を要求し、 その
  #   copy は page の byte 比較の外側ゆえ canonical-drift / nav-regen-drift が原理的に検出できず、 専用の
  #   同期 gate を唯一の番人として要した (folio-zpvv で撤去)。 inline なら CSS が本 page の byte に入るため
  #   drift 面そのものが消滅し、 nav-regen-drift の byte 検査へ守りが畳み込まれる。
  printf '<title>%s</title>\n<style>\n' "$(esc "$TITLE")"
  cat "$CSS"
  printf '\n</style>\n'
  jsonld_safe "$SET_ID"; jsonld_safe "$SET_NAME"
  # DefinedTermSet の @id: canonical page では design-intent 相対 path (素朴 emit 版の head と同じ page 識別)、
  # それ以外は term_set_id (IRI)。 各 term の inDefinedTermSet も同値を指す (set 識別の内部整合を保つ)。
  local set_iri="$SET_ID"
  if [[ "$CANON_PAGE" -eq 1 ]]; then jsonld_safe "$CANON_ID"; set_iri="$CANON_ID"; fi
  printf '<script type="application/ld+json">\n'
  printf '{"@context":"https://schema.org/","@type":"DefinedTermSet","@id":"%s","name":"%s"}\n' "$set_iri" "$SET_NAME"
  printf '</script>\n</head>\n'
  printf '<body>\n<main class="doc" data-doc-id="%s">\n' "$(esc "$DOC_ID")"
}

# DefinedTermSet の IRI (各 term の inDefinedTermSet 用)。 emit_head の set_iri と同一導出。
set_iri_value() {
  if [[ "$CANON_PAGE" -eq 1 ]]; then printf '%s' "$CANON_ID"; else printf '%s' "$SET_ID"; fi
}

emit_nav() {
  printf '<!-- folio:chrome-skiplink -->\n'
  printf '<a class="skip-link" href="#main">本文へスキップ</a>\n'
  printf '<!-- /folio:chrome-skiplink -->\n'
}

# cover を 1 モデルに統一: core cover-head/_tail (.meta.* + cover-summary slot) を骨格にし、
# 重複 eyebrow/h1/subtitle/summary-slot は持たず、 bespoke は cover-meta dl (.cover.meta[]) のみ。
# verify_core_chrome (core cover-head) と verify-glossary §6 (.cover.meta dl) の両方を満たす形。
emit_cover_band() {
  # ★folio-229 PW-04: ラベル『(1 文サマリ)』は cover-summary prose が複数文ゆえ不整合だった。 sentence-count を
  #   主張しない『(要旨)』へ緩和 (prose 側は多文の情報量を保持)。 summary-card lab は verify 非突合の静的 chrome。
  core_emit_cover_head "この用語集が約束すること (要旨)"
  printf '  <dl class="cover-meta">\n'
  local mn; mn="$(yq -r '.cover.meta | length' "$CONTRACT")"
  local j label value
  for ((j=0;j<mn;j++)); do
    label="$(q ".cover.meta[$j].label")"
    value="$(q ".cover.meta[$j].value")"
    printf '    <dt>%s</dt><dd>%s</dd>\n' "$(esc "$label")" "$(esc "$value")"
  done
  printf '  </dl>\n'
  core_emit_approval_block
  core_emit_cover_tail
}

# emit_terms — 用語本文を domain 区分 (PW-01) + 人間層 usage 行 (PW-02) 付きで発行する (folio-229)。
# ★人間層の道標: 全 term をフラット列でなく domain (予約業務/実現方式/確かめ方…) 別 section へ分割し、
#   friendly ラベルの見出し (domain-heading) + TOC (glossary-toc) で「自分の業務語 vs ソフト内部語」を判別可能にする。
#   単一 domain (folio) でも 3 domain (clinic) でも同一 code path (単一なら 1 section + 1 TOC entry で成立)。
# ★件数は magic number 禁止 (folio-bhe): domain 別語数は必ず terms から数え (DOM_COUNTS)、 見出し/TOC/verify とも
#   同一 SSoT (domains[] + terms[].domain) から導出する。
# ★USAGE_LABEL: 旧『定義元:』は「glossary が canonical 定義の置き場」という主張と緊張したため『使われる文書:』へ改称。
#   人間層 term-usage は friendly gloss (xref_gloss)、 機械層 li は生 doc-ID (data-xref-target) の dual-audience 対。
emit_terms() {
  local USAGE_LABEL="使われる文書"
  # ---- domains SSoT 読取り + 不変条件検査 (発行前・fail-closed) ----
  local ndom; ndom="$(yq -r '.domains | length' "$CONTRACT")"
  [[ "$ndom" =~ ^[0-9]+$ && "$ndom" -ge 1 ]] || { echo "assemble-glossary: .domains 欠落/空 (>=1 必須)" >&2; exit 1; }
  local di
  local -a DOM_IDS DOM_LABELS DOM_COUNTS
  local -A DOM_IDX
  for ((di=0;di<ndom;di++)); do
    DOM_IDS[$di]="$(q ".domains[$di].id")"; DOM_LABELS[$di]="$(q ".domains[$di].label")"
    core_validate_strings "assemble-glossary domain[$di]" "${DOM_IDS[$di]}" "${DOM_LABELS[$di]}"
    DOM_COUNTS[$di]="$(d="${DOM_IDS[$di]}" yq -r '[.terms[] | select(.domain == strenv(d))] | length' "$CONTRACT")"
    [[ "${DOM_COUNTS[$di]}" != "0" ]] || { echo "assemble-glossary: domain '${DOM_IDS[$di]}' に term 無し (空 domain 禁止)" >&2; exit 1; }
    DOM_IDX[${DOM_IDS[$di]}]=$di
  done
  # 不変条件: 全 terms[].domain が domains[] に属し、 domains 順に連続グループ化されている
  #   (=> outer 発行順 == contract term 順 == term 系 set_eq の期待 (contract 順) が不変で通る)。
  local -a TDOM; mapfile -t TDOM < <(q '.terms[].domain')
  local _prev="" _d j; local -A _closed _seen
  for ((j=0;j<${#TDOM[@]};j++)); do
    _d="${TDOM[$j]}"
    [[ -n "${DOM_IDX[$_d]:-}" ]] || { echo "assemble-glossary: term[$j] domain '$_d' が .domains[] に無い" >&2; exit 1; }
    if [[ "$_d" != "$_prev" ]]; then
      [[ -z "${_closed[$_d]:-}" ]] || { echo "assemble-glossary: domain '$_d' が非連続 (terms は domains 順に連続グループ化必須)" >&2; exit 1; }
      [[ -n "$_prev" ]] && _closed[$_prev]=1
      _prev="$_d"; _seen[$_d]=1
    fi
  done
  for ((di=0;di<ndom;di++)); do
    [[ -n "${_seen[${DOM_IDS[$di]}]:-}" ]] || { echo "assemble-glossary: domain '${DOM_IDS[$di]}' が terms に出現せず (domains 宣言と不整合)" >&2; exit 1; }
  done

  # ---- 発行 ----
  printf '<section class="glossary-terms" id="main" data-audience="human">\n'
  printf '  <h2>用語 (%s 語)</h2>\n' "$(esc "$NTERMS")"
  # TOC (索引・PW-01): 各 domain 区分へジャンプする signpost。 リンク文言は domain-heading と同一 (label + 語数)。
  printf '  <nav class="glossary-toc" data-audience="human" aria-label="用語ドメイン索引">\n    <ul>\n'
  for ((di=0;di<ndom;di++)); do
    printf '      <li><a href="#domain-%s">%s (%s 語)</a></li>\n' "$(esc "${DOM_IDS[$di]}")" "$(esc "${DOM_LABELS[$di]}")" "$(esc "${DOM_COUNTS[$di]}")"
  done
  printf '    </ul>\n  </nav>\n'

  local i canon en slug domain formal plain_slot cn prev_dom=""
  for ((i=0;i<NTERMS;i++)); do
    canon="$(q ".terms[$i].canonical")"
    en="$(q ".terms[$i].en")"
    slug="$(q ".terms[$i].slug")"
    domain="$(q ".terms[$i].domain")"
    formal="$(q ".terms[$i].formal_def")"
    plain_slot="$(q ".terms[$i].plain_slot")"
    core_validate_strings "assemble-glossary term[$i]" "$canon" "$en" "$slug" "$domain" "$formal" "$plain_slot"
    # ---- 必須 field の欠落 assert (folio-wg2l self-review finding#1・fail-closed) ----
    # ★q() は `yq -r` 素通しで既定値を持たないため、 *欠落キーはリテラル "null"* を返す (空文字ではない)。
    #   core_validate_strings は tab/改行しか見ず非空ゆえ通過するので、 欠落した term は全て同一定数へ潰れる:
    #   slug ならば全欠落 term が id="term-null" へ衝突して in-page anchor が壊れる (実弾で 2 本重複を再現)。
    #   canonical/en/domain/formal_def も同様に「null」という虚偽の可視 token として出荷されるため、 同 idiom で弾く
    #   (canonical_page の「部分指定は fail-closed」と同型: 半端な入力を黙って埋めない)。
    local _f _v
    for _f in canonical:"$canon" en:"$en" slug:"$slug" domain:"$domain" formal_def:"$formal"; do
      _v="${_f#*:}"
      if [[ -z "$_v" || "$_v" == "null" ]]; then
        echo "assemble-glossary: terms[$i].${_f%%:*} が空/未指定 (yq は欠落キーをリテラル \"null\" として返すため、 そのまま emit すると term-null 衝突・虚偽 token になる。 contract に明示せよ・fail-closed)" >&2
        exit 1
      fi
    done
    jsonld_safe "$canon"; jsonld_safe "$slug"
    # domain 境界: 新 domain の section を開き (前 domain を閉じ)、 friendly 見出しを render
    if [[ "$domain" != "$prev_dom" ]]; then
      [[ -n "$prev_dom" ]] && printf '  </section>\n'
      di="${DOM_IDX[$domain]}"
      printf '  <section class="term-domain" id="domain-%s" data-audience="human">\n' "$(esc "$domain")"
      printf '    <h3 class="domain-heading">%s (%s 語)</h3>\n' "$(esc "${DOM_LABELS[$di]}")" "$(esc "${DOM_COUNTS[$di]}")"
      prev_dom="$domain"
    fi
    printf '    <section class="term-entry" id="term-%s" data-audience="human" data-term="%s">\n' "$(esc "$slug")" "$(esc "$canon")"
    printf '      <h4 class="term-name">%s</h4>\n' "$(esc "$canon")"
    printf '      <p class="term-plain" data-slot-id="%s" data-prose-slot="%s"></p>\n' "$(esc "$plain_slot")" "$(esc "$plain_slot")"
    cn="$(yq -r ".terms[$i].cross_refs | length" "$CONTRACT")"
    # 人間層 term-usage (PW-02): この語が使われる文書を friendly gloss で。 非エンジニアが機械層 fold を開かずに
    #   「どの文書で使われるか」に答えられる。 gloss は xref_gloss (全 token 網羅・欠落は fail-closed)。
    if [[ "$cn" != "0" ]]; then
      local usage="" k tgt gloss
      for ((k=0;k<cn;k++)); do
        tgt="$(q ".terms[$i].cross_refs[$k]")"
        gloss="$(t="$tgt" yq -r '.xref_gloss[strenv(t)] // ""' "$CONTRACT")"
        [[ -n "$gloss" && "$gloss" != "null" ]] || { echo "assemble-glossary: xref_gloss に '$tgt' の friendly ラベル無し (term[$i]・fail-closed)" >&2; exit 1; }
        if [[ -z "$usage" ]]; then usage="$(esc "$gloss")"; else usage="$usage、$(esc "$gloss")"; fi
      done
      # ★folio-229 errata: data-usage-for=親 canonical (= 親 term-entry の data-term)。 usage 行を隣接カードへ
      #   relocate する改竄 (大域順保存) を verify §2c-usage-binding が親帰属で fail-closed 化する構造 anchor。
      printf '      <p class="term-usage" data-audience="human" data-usage-for="%s">%s: %s</p>\n' "$(esc "$canon")" "$USAGE_LABEL" "$usage"
    fi
    printf '      <details class="term-machine" data-audience="machine">\n'
    printf '        <summary>機械層 — 構造化 term レコード</summary>\n'
    printf '        <dl class="term-record">\n'
    printf '          <dt>canonical (en)</dt><dd data-term-en="%s">%s</dd>\n' "$(esc "$en")" "$(esc "$en")"
    printf '          <dt>slug / anchor</dt><dd data-term-slug="%s">#term-%s</dd>\n' "$(esc "$slug")" "$(esc "$slug")"
    printf '          <dt>domain</dt><dd data-term-domain="%s">%s</dd>\n' "$(esc "$domain")" "$(esc "$domain")"
    printf '          <dt>正式定義</dt><dd class="term-formal">%s</dd>\n' "$(esc "$formal")"
    printf '        </dl>\n'
    printf '        <script type="application/ld+json">{"@context":"https://schema.org/","@type":"DefinedTerm","@id":"%s:term/%s","name":"%s","inDefinedTermSet":"%s"}</script>\n' \
      "${SET_ID%%:*}" "$slug" "$canon" "$(set_iri_value)"
    if [[ "$cn" != "0" ]]; then
      printf '        <ul class="term-xrefs">\n'
      local k2 tgt2
      for ((k2=0;k2<cn;k2++)); do
        tgt2="$(q ".terms[$i].cross_refs[$k2]")"
        printf '          <li data-xref-target="%s" data-xref-rel="glossary-anchor">%s: %s</li>\n' "$(esc "$tgt2")" "$USAGE_LABEL" "$(esc "$tgt2")"
      done
      printf '        </ul>\n'
    fi
    printf '      </details>\n'
    printf '    </section>\n'
  done
  [[ -n "$prev_dom" ]] && printf '  </section>\n'
  printf '</section>\n'
}

# chrome glossary-term-table (core emit_glossary)。 terms[] が主題語、 こちらは用語集ページ自体の
# 構造 (dual-audience / 機械層) を読み解く doc-mechanics 補助語 (verify_core_chrome §3 が突合)。
emit_doc_glossary() {
  printf '<section class="doc-glossary" data-audience="human">\n'
  printf '  <h2>この用語集ページを読むための語</h2>\n'
  emit_glossary
  printf '</section>\n'
}

# footer は core_emit_footer に glossary-pack 別のタグ列を渡す (本文 SSoT 行は共通)。
# ★instance タグは hardcode せず contract (.footer.instance_tag) から取る (folio-c5r.3 ceiling
#   BLK-FOOTER-INSTANCE-TAG: instance#1 リテラルの hardcode は 2nd instance の成果物に虚偽の出自を
#   表示し gen-meta と自己矛盾した)。欠落時の既定は instance 非依存の中立句 (虚偽番号を出さない)。
emit_footer_band() {
  local genmeta itag
  genmeta="$(q '.footer.gen_meta // "folio design-system generator"')"
  itag="$(q '.footer.instance_tag // "dual-audience canonical vocabulary"')"
  core_emit_footer "<span>folio design system</span><span>glossary-pack</span><span>$(esc "$itag")</span><span>canonical-name SSoT + dual-audience term</span>"
  printf '<p class="gen-meta">%s</p>\n' "$(esc "$genmeta")"
}

main() {
  emit_head
  emit_nav
  emit_cover_band
  emit_terms
  emit_doc_glossary
  emit_footer_band
  printf '</main>\n</body>\n</html>\n'
}

main "$@"
