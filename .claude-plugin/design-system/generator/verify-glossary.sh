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
# ★folio-bur round-6 (ceiling-recursion R5 是正・収束根治): srs の class-token 機械的網羅 idiom を移植。 全 class token・全 data-component が
#   allowlist に属することを quote-robust に強制 = novel-marker (非 canonical class/data-component) 注入を一網打尽に封鎖 (系統的 fail-open の未然封鎖)。
GLOSS_CLS="cover-eyebrow cover-meta cover-sub doc doc-glossary doc-type en foot ft-grid gdef gen-meta glossary-terms grow gword ic lab reader-chip role self sign skip-link stamp summary-card tags term-entry term-formal term-machine term-name term-plain term-record term-xrefs txt when who xref"
unknown_cls="$(class_tokens < "$BODY" | tr ' ' '\n' | grep . | sort -u | grep -vxF -f <(printf '%s\n' $GLOSS_CLS) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "class-token 機械的網羅: 全 token が allowlist (novel marker 注入封鎖・folio-bur r6)" "$unknown_cls"
GLOSS_DC="approval-block doc-cover-band fidelity-sync-meta glossary-term-table"
unknown_dc="$(attr_values 'data-component' < "$BODY" | grep . | sort -u | grep -vxF -f <(printf '%s\n' $GLOSS_DC) | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "data-component 機械的網羅: 全 dc が allowlist (novel data-component 注入封鎖・folio-bur r6)" "$unknown_dc"

# ---- 1. 件数 = contract 導出 ----
n_entry="$(count_attr_token 'class' 'term-entry' < "$BODY")"
chk "term-entry 数 = contract 語数" "$NTERMS" "$n_entry"

# ---- 2. term fidelity (emission 順突合: canonical / en / slug / domain / formal_def) ----
set_eq "canonical(data-term) emission 順" "$(q '.terms[].canonical')" "$(attr_values 'data-term' < "$BODY")"
set_eq "機械 en(data-term-en) emission 順"  "$(q '.terms[].en')"        "$(attr_values 'data-term-en' < "$BODY")"
set_eq "機械 slug(data-term-slug) emission 順" "$(q '.terms[].slug')"   "$(attr_values 'data-term-slug' < "$BODY")"
set_eq "機械 domain(data-term-domain) emission 順" "$(q '.terms[].domain')" "$(attr_values 'data-term-domain' < "$BODY")"

# ★folio-bur round-6 (ceiling-recursion R5 是正): round-5 が占有 idiom を term-name/gen-meta へ適用したが最 load-bearing な兄弟
#   term-formal (.terms[].formal_def=用語の権威ある正式定義) を取りこぼし、 set_eq は class="term-formal" double-quote 固定抽出のみ・
#   占有 anchor 皆無ゆえ 4 変種 (single-quote/unquoted/multi-class/大文字) の偽 dd が全て survive した (独立 ceiling 実証・blocker)。
#   term-name と同型に quote-robust 占有で封鎖 (uniform sweep の機械的完遂)。
chk "占有: term-formal == NTERMS (single-quote/unquoted/multi-class/大文字 偽定義 decoy 封鎖・folio-bur r6)" "$NTERMS" "$(count_attr_token class term-formal < "$BODY")"
html_formal="$(perl -0777 -ne 'while (/<dd\b[^>]*\bclass="term-formal"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "正式定義 (term-formal) emission 順" "$(qesc '.terms[].formal_def')" "$html_formal"

# ---- 2b. 可視 human 層テキスト (machine 属性の双子・dual-audience の人間側) ----
#   §2 は data-term* *属性値* を bind する。 だが assemble は各 canonical/en/slug/domain を
#   *可視テキストとしても* 二重 emit する (<h3 class="term-name">canon / <dd>en / <dd>#term-slug / <dd>domain)。
#   属性のみ bind すると可視テキスト単独の改竄 (属性 intact のまま見出し語を捏造) が floor を素通りする
#   fail-open になる。 用語集の *主たる人間向けトークン* は表示見出し語ゆえ、 可視側も emission 順で contract へ pin する。
# ★folio-bur round-5 (ceiling-recursion R4 是正): 下の set_eq は class="term-name" を double-quote 固定で抽出し占有数 anchor が無いため、
#   single-quote マーカー decoy <h3 class='term-name'>偽用語GHOST</h3> を追記すると抽出を逃れ set_eq は genuine 33 のまま PASS、
#   用語集の主たる人間向けトークン (見出し語) が捏造され floor を素通った (独立 ceiling 実証・major)。 round-2 確立の占有 idiom を本トークンへ展開。
chk "占有: term-name == NTERMS (single-quote 見出し decoy 封鎖・folio-bur r5)" "$NTERMS" "$(count_attr_token class term-name < "$BODY")"
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
# ★folio-bur: 可視 echo 層の封鎖 (data-xref-target 属性は上で contract pin 済だが可視テキスト/孤立 li は未検査だった)。
#   (a) visible-text-vs-attribute: 各 xref li の可視 "定義元: {target}" == "定義元: " + data-xref-target (属性 intact のまま可視のみ捏造を封鎖)。
xref_vis_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @bad; while (/<li\b[^>]*\bdata-xref-target="([^"]*)"[^>]*>(.*?)<\/li>/gs){ my ($t,$in)=($1,$2); push @bad,"NESTED:$t" if $in=~/</; push @bad,"$t\x{2260}$in" if $in ne "定義元: $t"; } print join(" ",@bad);' < "$BODY")"
chk_empty "cross-doc: xref li 可視 == 定義元:{data-xref-target} (可視捏造封鎖)" "$xref_vis_bad"
#   (b) orphan-or-count: term-xrefs <ul> 内の <li> 総数 == |cross_refs| (属性なし孤立 li の挿入を封鎖)。
xref_li_total="$(perl -0777 -ne 'my $n=0; while (/<ul class="term-xrefs">(.*?)<\/ul>/gs){ my $b=$1; $n++ while $b=~/<li\b/g; } print $n;' < "$BODY")"
chk "cross-doc: term-xrefs 内 <li> 総数 == |cross_refs| (孤立 li 封鎖)" "$(q '[.terms[].cross_refs[]?] | length')" "$xref_li_total"
# ★folio-bur round-2 (ceiling-recursion 是正): 上の Pin A/B は double-quote 固定ゆえ (i) data-xref-target を single-quote/unquoted 化
#   した可視捏造 (ii) single-quote 兄弟 ul の孤立 li (iii) ul 内の非 li タグ・裸テキスト混入 を素通る (独立 ceiling 実証)。
#   quote-robust に全 term-xrefs ul を列挙 (class トークン parse) し、 可視 set_eq + 残差 whitespace-only + li 総数を一括検査
#   (dty: marker-keyed + 機械的完全列挙 + quote-robust helper)。
xref_robust="$(perl -CSD -0777 -e '
  my $q=chr(39); my $txt=<STDIN>; $txt="" unless defined $txt;
  my @vis; my $n=0; my $resid=0;
  while ($txt =~ /<ul\b([^>]*)>(.*?)<\/ul>/gs) {
    my ($a,$inner)=($1,$2);
    my $cls=""; if ($a =~ /\bclass\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/){ $cls=defined $1?$1:(defined $2?$2:$3); }
    $cls=~s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $cls=~s/&#(\d+);/chr($1)/ge;
    next unless grep { lc($_) eq "term-xrefs" } split(/\s+/,$cls);
    while ($inner =~ /<li\b[^>]*>(.*?)<\/li>/gs){ my $v=$1; push @vis, ($v=~/</ ? "NESTED:$v" : $v); $n++; }
    (my $r=$inner)=~s/<li\b[^>]*>.*?<\/li>//gs; $resid++ if $r=~/\S/;
  }
  print "N=$n\nRESID=$resid\n"; print "VIS\t$_\n" for @vis;
' < "$BODY")"
xref_n="$(printf '%s\n' "$xref_robust" | sed -n 's/^N=//p')"
xref_resid="$(printf '%s\n' "$xref_robust" | sed -n 's/^RESID=//p')"
xref_vis="$(printf '%s\n' "$xref_robust" | sed -n 's/^VIS\t//p')"
exp_xref_vis="$(q '.terms[].cross_refs[]?' | while IFS= read -r t; do printf '定義元: %s\n' "$(esc "$t")"; done)"
chk "cross-doc(robust): term-xrefs li 総数 == |cross_refs| (quote非依存)" "$(q '[.terms[].cross_refs[]?] | length')" "${xref_n:-0}"
chk "cross-doc(robust): term-xrefs ul の非 li 残差 == 0 (非li/裸テキスト混入封鎖)" "0" "${xref_resid:-0}"
set_eq "cross-doc(robust): 可視 li == 定義元:{cross_ref} (quote非依存・属性引用形に依存しない可視 pin)" "$exp_xref_vis" "$xref_vis"
# ★folio-bur round-3 (ceiling-recursion R2 是正): 上の robust 列挙は container を <ul class=term-xrefs> に anchor するため
#   <ol class="term-xrefs"> / <div class="term-xrefs"> (別タグだが同 class) や別 class コンテナ (ul.decoy-xrefs) / class 無し <div> に
#   「定義元: X」を置く捏造 provenance を素通った (独立 ceiling 実証)。 core_chrome の『想定読者: marker==1』と同型に、
#   *大域* '定義元:' 出現数 == |cross_refs| を pin (anchor の class/タグに依らず、 可視 provenance マーカーそのものを数える)。
chk "cross-doc: 大域 '定義元:' 出現数 == |cross_refs| (anchor 外 provenance 捏造封鎖)" "$(q '[.terms[].cross_refs[]?] | length')" "$(grep -oF '定義元:' "$BODY" | wc -l | tr -d ' ')"

# ---- 6. cover-meta KV (label;value emission 順) ----
exp_meta="$(yq -r '.cover.meta[] | .label + " ; " + .value' "$CONTRACT")"
# ★folio-bur round-3 (ceiling-recursion R2 是正): round-2 は最初の cover-meta dl だけ突合 (if・/g 無し) ゆえ 2 個目の
#   <dl class="cover-meta"> に捏造 KV を足すと素通った (独立 ceiling 実証)。 while//g で全 cover-meta dl の KV を突合列へ含め、
#   さらに dl 数 == 1 を quote-robust 占有数で pin (空の 2 個目 decoy も封鎖)。 gen-meta/term-xrefs と同じ /g 規律へ整合。
chk "cover-meta dl 数 == 1 (2個目 dl decoy 封鎖)" "1" "$(count_attr_token class cover-meta < "$BODY")"
# ★folio-bur round-4 (ceiling-recursion R3 是正): round-3 は dl 占有数を case-robust な count_attr_token で測ったが、 KV 内容を測る
#   内部 dt/dd 抽出は小文字タグ固定のままで、 genuine dl 内へ <DT>機密度</DT><DD>最高機密-FAKE</DD> (大文字タグ) を入れると
#   抽出されず html_meta に乗らず set_eq を素通った (browser は <DT>/<DD> を同一描画・独立 ceiling 実証)。 dt/dd を case 非依存化。
html_meta="$(perl -0777 -ne 'while (/<dl\b[^>]*\bclass="cover-meta"[^>]*>(.*?)<\/dl>/gs){ my $b=$1; while ($b =~ /<(?i:dt)[^>]*>(.*?)<\/(?i:dt)>\s*<(?i:dd)[^>]*>(.*?)<\/(?i:dd)>/gs){ print "$1 ; $2\n"; } }' < "$BODY")"
set_eq "cover-meta KV emission 順" "$exp_meta" "$html_meta"

# ---- 6b. 可視 contract 由来トークン (glossary-pack 固有 emit・継承パターン外) ----
#   gen-meta (<p class="gen-meta">) と用語数 h2 (<h2>用語 (N 語)</h2>) は本 pack が新規に emit する
#   可視 contract 由来トークンだが §1〜7 のどの突合にも bind されていなかった = fabrication-free 不変の穴
#   (属性 intact・件数別 pin のまま可視値だけ捏造して floor を素通る fail-open)。 ここで両者を contract 値へ pin する。
#   gen-meta 値は assemble と *同一の* fallback 式 (.footer.gen_meta // "folio design-system generator") で導出し、
#   h2 の N は NTERMS (= term-entry 数・件数別 pin と同一 SSoT) と突合する (cosmetic desync も封鎖)。
exp_genmeta="$(esc "$(q '.footer.gen_meta // "folio design-system generator"')")"
# ★folio-bur round-5 (ceiling-recursion R4 是正): gen-meta も double-quote 固定 chk + 占有 anchor 無しゆえ single-quote decoy
#   <p class='gen-meta'>FABRICATED</p> が footer 生成メタを偽装でき素通った (独立 ceiling 実証・minor)。 term-name と同型に占有で封鎖。
chk "占有: gen-meta == 1 (single-quote footer decoy 封鎖・folio-bur r5)" "1" "$(count_attr_token class gen-meta < "$BODY")"
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


# ===== folio-bur round-7: occupancy-from-contract 完全性 (真の不動点・membership≠occupancy) =====
# round-6 enumeration は novel marker を封鎖したが、 allowlist *内* の canonical chrome token を借りた
# additive 注入は占有 pin が無ければ素通る (ceiling: membership≠occupancy は直交防御)。 全 allowlist token に
# occupancy pin を付け additive 借用 family を構造封鎖する。 残る count 保存 value-swap は ceiling 領域 (正直な境界)。
# (a) display-state guard: genuine は inline display:none/visibility:hidden/hidden 属性を一切出さない (全 pack baseline=0)。
#     genuine を隠し fake を見せる二重攻撃の隠蔽半分ゆえ不在を要求 (aria-hidden は装飾で genuine も使うため対象外)。
chk_empty "占有(r7): inline display:none/visibility:hidden 不在 (隠蔽攻撃封鎖)" \
  "$(grep -oiE 'style="[^"]*(display[[:space:]]*:[[:space:]]*none|visibility[[:space:]]*:[[:space:]]*hidden)' "$BODY" | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "占有(r7): hidden 属性 不在 (隠蔽攻撃封鎖)" \
  "$(grep -oiE '<[a-z][a-z0-9-]*[^>]*[[:space:]]hidden([[:space:]>=])' "$BODY" | tr '\n' ' ' | sed 's/ *$//')"
# (d) occupancy-from-contract: 各 allowlist token の occupancy == contract 導出個数 (grouped loop)。
EXP=1; for t in doc doc-glossary foot ft-grid glossary-terms ic lab skip-link summary-card tags txt; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP=1; for t in doc-cover-band fidelity-sync-meta; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP=1; for t in approval-block glossary-term-table; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token data-component "$t" < $BODY)"; done
EXP="$(q '.terms | length')"; for t in term-machine term-plain term-record; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '[.terms[] | select((.cross_refs | length) > 0)] | length')"; for t in term-xrefs; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
EXP="$(q '[.approval[] | select(.stamp != "承認済")] | length')"; for t in self; do chk "占有(r7) $t==$EXP" "$EXP" "$(count_attr_token class "$t" < $BODY)"; done
# (e) term-inline 占有: bare <span class="term"> 注入を封鎖 (class term == data-component plain-language-term-inline・
#     構造化 badge は verify_term_inline が glossary 突合済)。
chk "占有(r7): term == plain-language-term-inline (bare .term 注入封鎖)" \
  "$(count_attr_token data-component plain-language-term-inline < "$BODY")" "$(count_attr_token class term < "$BODY")"
# ===== folio-bur round-7 ここまで =====

echo ""
if [[ "$fail" == "0" ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + term/機械レコード/照会 fidelity + prose 全充填) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
