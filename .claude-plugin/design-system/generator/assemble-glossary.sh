#!/usr/bin/env bash
# assemble-glossary.sh — folio glossary-pack (instance #1, folio self-host) deterministic assembler
# doc_type: glossary (canonical vocabulary)。 機械 SSoT = contract/folio-glossary.glossary.yaml
# (architecture/vocabulary.yaml + architecture/glossary.html 由来、 read-only source)。
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
[[ -f "$CONTRACT" ]] || { echo "assemble-glossary: contract not found: $CONTRACT" >&2; exit 1; }
command -v yq >/dev/null || { echo "assemble-glossary: yq required" >&2; exit 1; }

DOC_ID="$(q '.doc_id')"
TITLE="$(q '.title')"
VERSION="$(q '.version')"
DOC_TYPE="$(q '.doc_type')"
SET_ID="$(q '.term_set_id')"
SET_NAME="$(q '.term_set_name')"
NTERMS="$(yq -r '.terms | length' "$CONTRACT")"
core_validate_strings "assemble-glossary head" "$DOC_ID" "$TITLE" "$DOC_TYPE" "$SET_ID" "$SET_NAME"

jsonld_safe() { # $1 = value : JSON/script を壊す文字が無いことを fail-closed で確認
  case "$1" in
    *'"'*|*'\'*|*'<'*|*'>'*|*'&'*) echo "assemble-glossary: JSON-LD 不適合文字: $1" >&2; exit 1 ;;
  esac
}

emit_head() {
  printf '<!DOCTYPE html>\n<html lang="ja" data-doc-id="%s" data-doc-type="%s">\n' "$(esc "$DOC_ID")" "$(esc "$DOC_TYPE")"
  printf '<head>\n<meta charset="UTF-8">\n<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
  printf '<title>%s</title>\n<link rel="stylesheet" href="srs.css">\n' "$(esc "$TITLE")"
  jsonld_safe "$SET_ID"; jsonld_safe "$SET_NAME"
  printf '<script type="application/ld+json">\n'
  printf '{"@context":"https://schema.org/","@type":"DefinedTermSet","@id":"%s","name":"%s"}\n' "$SET_ID" "$SET_NAME"
  printf '</script>\n</head>\n'
  printf '<body>\n<main class="doc" data-doc-id="%s">\n' "$(esc "$DOC_ID")"
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
  core_emit_cover_head "この用語集が約束すること (1 文サマリ)"
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

emit_terms() {
  printf '<section class="glossary-terms" id="main" data-audience="human">\n'
  printf '  <h2>用語 (%s 語)</h2>\n' "$(esc "$NTERMS")"
  local i canon en slug domain formal plain_slot
  for ((i=0;i<NTERMS;i++)); do
    canon="$(q ".terms[$i].canonical")"
    en="$(q ".terms[$i].en")"
    slug="$(q ".terms[$i].slug")"
    domain="$(q ".terms[$i].domain")"
    formal="$(q ".terms[$i].formal_def")"
    plain_slot="$(q ".terms[$i].plain_slot")"
    core_validate_strings "assemble-glossary term[$i]" "$canon" "$en" "$slug" "$domain" "$formal" "$plain_slot"
    jsonld_safe "$canon"; jsonld_safe "$slug"
    printf '  <section class="term-entry" id="term-%s" data-audience="human" data-term="%s">\n' "$(esc "$slug")" "$(esc "$canon")"
    printf '    <h3 class="term-name">%s</h3>\n' "$(esc "$canon")"
    printf '    <p class="term-plain" data-slot-id="%s" data-prose-slot="%s"></p>\n' "$(esc "$plain_slot")" "$(esc "$plain_slot")"
    printf '    <details class="term-machine" data-audience="machine">\n'
    printf '      <summary>機械層 — 構造化 term レコード</summary>\n'
    printf '      <dl class="term-record">\n'
    printf '        <dt>canonical (en)</dt><dd data-term-en="%s">%s</dd>\n' "$(esc "$en")" "$(esc "$en")"
    printf '        <dt>slug / anchor</dt><dd data-term-slug="%s">#term-%s</dd>\n' "$(esc "$slug")" "$(esc "$slug")"
    printf '        <dt>domain</dt><dd data-term-domain="%s">%s</dd>\n' "$(esc "$domain")" "$(esc "$domain")"
    printf '        <dt>正式定義</dt><dd class="term-formal">%s</dd>\n' "$(esc "$formal")"
    printf '      </dl>\n'
    printf '      <script type="application/ld+json">{"@context":"https://schema.org/","@type":"DefinedTerm","@id":"%s:term/%s","name":"%s","inDefinedTermSet":"%s"}</script>\n' \
      "${SET_ID%%:*}" "$slug" "$canon" "$SET_ID"
    local cn; cn="$(yq -r ".terms[$i].cross_refs | length" "$CONTRACT")"
    if [[ "$cn" != "0" ]]; then
      printf '      <ul class="term-xrefs">\n'
      local k tgt
      for ((k=0;k<cn;k++)); do
        tgt="$(q ".terms[$i].cross_refs[$k]")"
        printf '        <li data-xref-target="%s" data-xref-rel="glossary-anchor">定義元: %s</li>\n' "$(esc "$tgt")" "$(esc "$tgt")"
      done
      printf '      </ul>\n'
    fi
    printf '    </details>\n'
    printf '  </section>\n'
  done
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
