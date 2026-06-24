#!/usr/bin/env bash
# verify-glossary.sh — folio glossary-pack (instance #1) fabrication-free floor verifier
#
# 生成 glossary HTML の *構造* が contract (folio-glossary.glossary.yaml) から完全導出されたことを機械検証する floor gate。
# verify-spec.sh / verify-srs.sh / verify-adr.sh と同型の規律を glossary-pack schema (cover + terms[]) へ適用:
#   - 件数 = contract 導出 (term-entry 数 / prose スロット数)。
#   - term fidelity: canonical(data-term) / en / slug / domain / formal_def を *emission 順* で突合
#     (脱落=set_eq の「contract のみ」/ 捏造=「HTML のみ」/ 並べ替え=順序不一致 を一括検出)。
#   - 機械層 term レコード集合一致: data-term-en / data-term-slug / data-term-domain / JSON-LD DefinedTerm (name/@id)。
#   - human anchor: id="term-<slug>" 集合一致。
#   - cross-doc anchor: data-xref-target 集合一致 (contract cross_refs flatten)。
#   - cover-meta KV / footer verify-state token (verify_core_chrome)。
#   - prose スロット (3 mode = pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実)。
#
# usage: verify-glossary.sh [--filled <manifest.yaml> | --artifact] <contract.yaml> <html>
# exit:  0 = floor PASS (CEILING=PENDING) / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合。
#   plain 定義 (plain-<slug> prose スロット) の *内容真正性* (平易さ・捏造の不在) は floor の対象外 = ceiling。
#   floor 単独で GREEN にはならず CEILING=PENDING。 glossary 専用 ceiling agent は未整備 (admin 起票候補・notes 参照)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-glossary.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
HTML="${2:?usage: verify-glossary.sh [--filled <manifest> | --artifact] <contract.yaml> <html>}"
[[ -f "$CONTRACT" ]] || { echo "verify-glossary: contract not found: $CONTRACT" >&2; exit 2; }
[[ -f "$HTML" ]] || { echo "verify-glossary: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-glossary: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-glossary: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-glossary: perl required" >&2; exit 2; }

LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-glossary: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=56; source "$LVC" || { echo "verify-glossary: failed to source verify-common.sh" >&2; exit 2; }

fail=0
make_body "$HTML"

NTERMS="$(q '.terms | length')"
echo "glossary-pack fabrication-free floor: $HTML"
echo "  contract: $CONTRACT  ($NTERMS 語)"

# ---- 1. 件数 = contract 導出 ----
n_entry="$(count_attr_token 'class' 'term-entry' < "$BODY")"
chk "term-entry 数 = contract 語数" "$NTERMS" "$n_entry"

# ---- 2. term fidelity (emission 順突合: canonical / en / slug / domain / formal_def) ----
set_eq "canonical(data-term) emission 順" "$(q '.terms[].canonical')" "$(attr_values 'data-term' < "$BODY")"
set_eq "機械 en(data-term-en) emission 順"  "$(q '.terms[].en')"        "$(attr_values 'data-term-en' < "$BODY")"
set_eq "機械 slug(data-term-slug) emission 順" "$(q '.terms[].slug')"   "$(attr_values 'data-term-slug' < "$BODY")"
set_eq "機械 domain(data-term-domain) emission 順" "$(q '.terms[].domain')" "$(attr_values 'data-term-domain' < "$BODY")"

html_formal="$(perl -0777 -ne 'while (/<dd\b[^>]*\bclass="term-formal"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "正式定義 (term-formal) emission 順" "$(qesc '.terms[].formal_def')" "$html_formal"

# ---- 2b. 可視 human 層テキスト (machine 属性の双子・dual-audience の人間側) ----
#   §2 は data-term* *属性値* を bind する。 だが assemble は各 canonical/en/slug/domain を
#   *可視テキストとしても* 二重 emit する (<h3 class="term-name">canon / <dd>en / <dd>#term-slug / <dd>domain)。
#   属性のみ bind すると可視テキスト単独の改竄 (属性 intact のまま見出し語を捏造) が floor を素通りする
#   fail-open になる。 用語集の *主たる人間向けトークン* は表示見出し語ゆえ、 可視側も emission 順で contract へ pin する。
html_termname="$(perl -0777 -ne 'while (/<h3\b[^>]*\bclass="term-name"[^>]*>(.*?)<\/h3>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視見出し語 (h3 term-name) emission 順" "$(qesc '.terms[].canonical')" "$html_termname"
html_vis_en="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-en="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 en (dd data-term-en テキスト) emission 順" "$(qesc '.terms[].en')" "$html_vis_en"
html_vis_domain="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-domain="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 domain (dd data-term-domain テキスト) emission 順" "$(qesc '.terms[].domain')" "$html_vis_domain"
exp_vis_slug="$(q '.terms[].slug' | while IFS= read -r s; do printf '#term-%s\n' "$s"; done)"
html_vis_slug="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-slug="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 slug-anchor (dd data-term-slug テキスト #term-<slug>) emission 順" "$exp_vis_slug" "$html_vis_slug"

# ---- 3. human anchor: id="term-<slug>" 集合 (emission 順) ----
exp_anchor="$(q '.terms[].slug' | while IFS= read -r s; do printf 'term-%s\n' "$s"; done)"
html_anchor="$(perl -0777 -ne 'while (/<section\b[^>]*\bclass="term-entry"[^>]*\bid="([^"]+)"[^>]*>/gs){ print "$1\n"; }' < "$BODY")"
set_eq "human anchor id=term-<slug>" "$exp_anchor" "$html_anchor"

# ---- 4. JSON-LD schema:DefinedTerm (name / @id) emission 順 ----
jsonld_name="$(perl -0777 -ne 'while (/"\@type":"DefinedTerm","\@id":"[^"]+","name":"([^"]+)"/gs){ print "$1\n"; }' < "$BODY")"
jsonld_id="$(perl -0777 -ne 'while (/"\@type":"DefinedTerm","\@id":"([^"]+)","name":"[^"]+"/gs){ print "$1\n"; }' < "$BODY")"
SET_ID="$(q '.term_set_id')"; PREFIX="${SET_ID%%:*}"
exp_jsonld_id="$(q '.terms[].slug' | while IFS= read -r s; do printf '%s:term/%s\n' "$PREFIX" "$s"; done)"
set_eq "JSON-LD DefinedTerm name emission 順" "$(q '.terms[].canonical')" "$jsonld_name"
set_eq "JSON-LD DefinedTerm @id emission 順"  "$exp_jsonld_id" "$jsonld_id"

# ---- 5. cross-doc anchor: data-xref-target 集合 (contract terms[].cross_refs flatten・emission 順) ----
exp_xref="$(q '.terms[].cross_refs[]' 2>/dev/null)"
act_xref="$(attr_values 'data-xref-target' < "$BODY")"
set_eq "cross-doc anchor (data-xref-target)" "$exp_xref" "$act_xref"

# ---- 6. cover-meta KV (label;value emission 順) ----
exp_meta="$(yq -r '.cover.meta[] | .label + " ; " + .value' "$CONTRACT")"
html_meta="$(perl -0777 -ne 'if (/<dl\b[^>]*\bclass="cover-meta"[^>]*>(.*?)<\/dl>/s){ my $b=$1; while ($b =~ /<dt[^>]*>(.*?)<\/dt>\s*<dd[^>]*>(.*?)<\/dd>/gs){ print "$1 ; $2\n"; } }' < "$BODY")"
set_eq "cover-meta KV emission 順" "$exp_meta" "$html_meta"

# ---- 6b. 可視 contract 由来トークン (glossary-pack 固有 emit・継承パターン外) ----
#   gen-meta (<p class="gen-meta">) と用語数 h2 (<h2>用語 (N 語)</h2>) は本 pack が新規に emit する
#   可視 contract 由来トークンだが §1〜7 のどの突合にも bind されていなかった = fabrication-free 不変の穴
#   (属性 intact・件数別 pin のまま可視値だけ捏造して floor を素通る fail-open)。 ここで両者を contract 値へ pin する。
#   gen-meta 値は assemble と *同一の* fallback 式 (.footer.gen_meta // "folio design-system generator") で導出し、
#   h2 の N は NTERMS (= term-entry 数・件数別 pin と同一 SSoT) と突合する (cosmetic desync も封鎖)。
exp_genmeta="$(esc "$(q '.footer.gen_meta // "folio design-system generator"')")"
html_genmeta="$(perl -0777 -ne 'while (/<p\b[^>]*\bclass="gen-meta"[^>]*>(.*?)<\/p>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
chk "gen-meta == .footer.gen_meta (可視 contract 値)" "$exp_genmeta" "$html_genmeta"
html_h2count="$(perl -0777 -ne 'while (/<h2\b[^>]*>\s*用語\s*\((\d+)\s*語\)\s*<\/h2>/gs){ print "$1\n"; }' < "$BODY")"
chk "用語数 h2 N == NTERMS (可視 contract 導出)" "$NTERMS" "$html_h2count"

# ---- 7. footer verify-state token (core chrome) ----
verify_core_chrome "footer verify-state token"

# ---- 8. prose スロット mode (pre-fill 全空 / --filled・--artifact 全充填 + 注入忠実) ----
slots=$(( 1 + NTERMS ))
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' < "$BODY")"
if [[ -n "$ARTIFACT" ]]; then
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
elif [[ -n "$FILLED_MANIFEST" ]]; then
  chk "prose スロットは全て充填 (空=0)" "$slots" "$filled"
  inj_fail=0
  while IFS= read -r key; do
    exp_val="$(esc "$(key="$key" yq -r '.slots[strenv(key)]' "$FILLED_MANIFEST")")"
    act_val="$(KEY="$key" perl -0777 -ne 'my $k=$ENV{KEY}; if (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="\Q$k\E"[^>]*>(.*?)<\/\1>/s){ print $2; }' < "$BODY")"
    if [[ "$exp_val" != "$act_val" ]]; then printf '  [FAIL] %-'"$CHKW"'s 注入不一致: %s\n' "prose 注入忠実" "$key"; inj_fail=1; fi
  done < <(yq -r '.slots | keys | .[]' "$FILLED_MANIFEST")
  if [[ "$inj_fail" == "0" ]]; then printf '  [OK]   %-'"$CHKW"'s\n' "prose 注入忠実 (全 slot manifest 一致)"; else fail=1; fi
else
  chk "prose スロットは全て空 (pre-fill, filled=0)" "0" "$filled"
fi

echo ""
if [[ "$fail" == "0" ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + term/機械レコード/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
