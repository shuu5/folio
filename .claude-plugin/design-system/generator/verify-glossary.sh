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
#   floor 単独で GREEN にはならず CEILING=PENDING。 glossary 専用 ceiling agent = agents/{persona-walk,fidelity}-glossary.md (folio-3p1)。 orchestrator 配線は folio-mzn S5/S12。

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
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build glossary "$FILLED_MANIFEST"

NTERMS="$(q '.terms | length')"
echo "glossary-pack fabrication-free floor: $HTML"
echo "  contract: $CONTRACT  ($NTERMS 語)"
# ★folio-bur round-6 (ceiling-recursion R5 是正・収束根治): srs の class-token 機械的網羅 idiom を移植。 全 class token・全 data-component が
#   allowlist に属することを quote-robust に強制 = novel-marker (非 canonical class/data-component) 注入を一網打尽に封鎖 (系統的 fail-open の未然封鎖)。
# ★folio-229: domain 区分 (PW-01) + 人間層 usage (PW-02) の新 class を allowlist に追加。
#   domain-heading / glossary-toc / term-domain / term-usage は verify §2c で contract 導出値へ pin する。
GLOSS_CLS="cover-eyebrow cover-meta cover-sub doc doc-glossary doc-type domain-heading en foot ft-grid ft-plain gdef gen-meta glossary-terms glossary-toc grow gword ic lab reader-chip role self sign skip-link stamp summary-card tags term-domain term-entry term-formal term-machine term-name term-plain term-record term-usage term-xrefs txt when who xref"
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
# ★folio-229: domain 区分 (h3 domain-heading) の下に term が入るため term-name は h3→h4 へ降格 (見出し階層維持)。
html_termname="$(perl -0777 -ne 'while (/<h4\b[^>]*\bclass="term-name"[^>]*>(.*?)<\/h4>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視見出し語 (h3 term-name) emission 順" "$(qesc '.terms[].canonical')" "$html_termname"
html_vis_en="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-en="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 en (dd data-term-en テキスト) emission 順" "$(qesc '.terms[].en')" "$html_vis_en"
html_vis_domain="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-domain="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 domain (dd data-term-domain テキスト) emission 順" "$(qesc '.terms[].domain')" "$html_vis_domain"
exp_vis_slug="$(q '.terms[].slug' | while IFS= read -r s; do printf '#term-%s\n' "$s"; done)"
html_vis_slug="$(perl -0777 -ne 'while (/<dd\b[^>]*\bdata-term-slug="[^"]*"[^>]*>(.*?)<\/dd>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "可視 slug-anchor (dd data-term-slug テキスト #term-<slug>) emission 順" "$exp_vis_slug" "$html_vis_slug"

# ---- 2c. domain 区分 (PW-01) + 人間層 usage (PW-02)。 全て contract (domains[] + terms[].domain + xref_gloss) 導出 ----
#   ★domain 別語数・friendly ラベル・usage 文言は magic number/literal でなく SSoT 導出。 発行順 == contract term 順
#     (assemble の連続グループ化不変条件が担保) ゆえ set_eq は contract 順の期待で通る。
# domain-heading 期待 (label + 語数) を bash で導出 (yq の map($g[.]) は mikefarah で単一化する不具合ゆえ assemble と同経路の bash loop)。
exp_domhead="$(
  _nd="$(q '.domains | length')"
  for ((_dj=0; _dj<_nd; _dj++)); do
    _dlb="$(q ".domains[$_dj].label")"; _did="$(q ".domains[$_dj].id")"
    _dcc="$(d="$_did" yq -r '[.terms[] | select(.domain == strenv(d))] | length' "$CONTRACT")"
    printf '%s (%s 語)\n' "$(esc "$_dlb")" "$(esc "$_dcc")"
  done
)"
html_domhead="$(perl -0777 -ne 'while (/<h3\b[^>]*\bclass="domain-heading"[^>]*>(.*?)<\/h3>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
set_eq "domain-heading (friendly label + 語数) emission 順" "$exp_domhead" "$html_domhead"
# term-domain section id = domain-<id> (emission 順)
exp_domid="$(q '.domains[].id' | while IFS= read -r d; do printf 'domain-%s\n' "$d"; done)"
html_domid="$(perl -0777 -ne 'while (/<section\b[^>]*\bclass="term-domain"[^>]*\bid="([^"]+)"[^>]*>/gs){ print "$1\n"; }' < "$BODY")"
set_eq "term-domain id=domain-<id> emission 順" "$exp_domid" "$html_domid"
# TOC (glossary-toc nav 内) の href (#domain-<id>) と link 文言 (== domain-heading) を emission 順で pin。
exp_toc_href="$(q '.domains[].id' | while IFS= read -r d; do printf '#domain-%s\n' "$d"; done)"
html_toc_href="$(perl -0777 -ne 'if (/<nav\b[^>]*\bclass="glossary-toc"[^>]*>(.*?)<\/nav>/s){ my $b=$1; while ($b =~ /<a\b[^>]*\bhref="([^"]*)"[^>]*>/gs){ print "$1\n"; } }' < "$BODY")"
set_eq "TOC href=#domain-<id> emission 順" "$exp_toc_href" "$html_toc_href"
html_toc_text="$(perl -0777 -ne 'if (/<nav\b[^>]*\bclass="glossary-toc"[^>]*>(.*?)<\/nav>/s){ my $b=$1; while ($b =~ /<a\b[^>]*>(.*?)<\/a>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; } }' < "$BODY")"
set_eq "TOC link 文言 == domain-heading emission 順" "$exp_domhead" "$html_toc_text"
# 人間層 term-usage の可視 friendly gloss を contract 導出 (assemble と同経路の bash loop) で *親カード帰属込み* に pin。
#   非エンジニアが機械層 fold を開かず「どの文書で使われるか」に答えられる human 層トークンゆえ捏造を封鎖する。
# ★folio-229 errata (admin gate wf_76141b32・major): 従来は usage 可視テキストを *大域 emission 順* でしか突合せず、
#   「どの語のカードに出るか」(親 term-entry への帰属) を pin しなかった。 usage 行を隣接 term-entry へ relocate する
#   改竄 (大域順・件数・parity 保存) が素通り、 spec カードが出典喪失・ADR カードが他語の出典を詐称する fail-open だった
#   (term-entry↔term-domain nesting 穴の同型・§2c-nesting と同経路で親帰属を束縛して塞ぐ)。
#   (b) tuple 束縛: (data-usage-for=親 canonical, usage text) を contract 順で set_eq (source-id を tuple に含め、
#       relocate + data-usage-for 詐称 = text 不一致 / relocate のみ = 発行順不一致 を集合突合で捕捉)。
exp_usage="$(
  _nt="$(q '.terms | length')"
  for ((_ti=0; _ti<_nt; _ti++)); do
    _cnn="$(q ".terms[$_ti].cross_refs | length")"
    [[ "$_cnn" != "0" ]] || continue
    _canon="$(q ".terms[$_ti].canonical")"
    _u=""; _kk=0
    while [[ $_kk -lt $_cnn ]]; do
      _tt="$(q ".terms[$_ti].cross_refs[$_kk]")"
      _gg="$(t="$_tt" yq -r '.xref_gloss[strenv(t)] // ""' "$CONTRACT")"
      if [[ -z "$_u" ]]; then _u="$(esc "$_gg")"; else _u="$_u、$(esc "$_gg")"; fi
      _kk=$((_kk+1))
    done
    printf '%s\t使われる文書: %s\n' "$(esc "$_canon")" "$_u"
  done
)"
html_usage="$(perl -0777 -ne 'while (/<p\b[^>]*\bclass="term-usage"[^>]*\bdata-usage-for="([^"]*)"[^>]*>(.*?)<\/p>/gs){ my ($f,$t)=($1,$2); $t=~s/[\t\n]/ /g; print "$f\t$t\n"; }' < "$BODY")"
set_eq "人間層 term-usage (data-usage-for, 使われる文書 friendly) tuple emission 順" "$exp_usage" "$html_usage"
#   (a) 構造不変条件 (relocation の主防御・bhe doctrine: blind region を列挙で塞がず「全 usage は必ず card 内在」の肯定形で閉じる)。
#   ★folio-229 errata-2 (admin gate wf_42ff3bdc・green-flip 両 instance 実弾): errata-1 の block-scope 走査は term-entry の
#     *開始位置のみ*で slice を切ったため、 最初の term-entry より前 (TOC / domain-heading 直下) が blind region となり、
#     先頭 term (folio=spec / clinic=診療枠) の usage をそこへ relocate すると大域順保存で (b)tuple・占有・parity を全て素通り、
#     先頭カードが出典喪失した (errata-1 が封鎖したと主張した当の harm)。 列挙でなく肯定形 3 点で閉じる:
#     (i) 各 term-entry block 直下の term-usage 個数 == contract 導出 (cross_refs>0→1 / ==0→0) を data-term keyed で emission 順
#         set_eq (source 喪失・foreign 混入・card 内重複/欠落を一括)。
#     (ii) 文書全体の term-usage 総数 == 全 term-entry slice 内で観測した usage 総数 (orphan = blind region 含めどこに在っても
#         総数不一致で即 FAIL — 「全 usage は必ずいずれかの entry block 内」の肯定的全被覆)。
#     (iii) 各 term-usage の data-usage-for == 親 term-entry の data-term (block 内 foreign 混入の帰属詐称を封鎖)。
usage_scan="$(perl -CSD -0777 -ne '
  my $txt=$_;
  my @e; while ($txt =~ /<section\b[^>]*\bclass="term-entry"[^>]*\bdata-term="([^"]*)"[^>]*>/g) { push @e,[$1,pos($txt)]; }
  my @bad; my $sum=0;
  for (my $i=0;$i<@e;$i++){
    my $s=$e[$i][1]; my $end=($i+1<@e)?$e[$i+1][1]:length($txt);
    my $b=substr($txt,$s,$end-$s); my $n=0;
    while ($b=~/<p\b[^>]*\bclass="term-usage"[^>]*\bdata-usage-for="([^"]*)"[^>]*>/g){ $n++; push @bad,"$1\x{2260}$e[$i][0]" if $1 ne $e[$i][0]; }
    print "CARD\t$e[$i][0]\t$n\n"; $sum+=$n;
  }
  my $g=0; $g++ while $txt=~/<p\b[^>]*\bclass="term-usage"[^>]*>/g;
  print "GTOTAL\t$g\t$sum\n";
  print "BAD\t".join(" ",@bad)."\n";
' < "$BODY")"
# (i) per-card 個数 (data-term, 期待 0/1) emission 順 set_eq
html_cardusage="$(printf '%s\n' "$usage_scan" | sed -n 's/^CARD\t//p')"
exp_cardusage="$(
  _nt="$(q '.terms | length')"
  for ((_ti=0; _ti<_nt; _ti++)); do
    _canon="$(q ".terms[$_ti].canonical")"; _cnn="$(q ".terms[$_ti].cross_refs | length")"
    printf '%s\t%s\n' "$(esc "$_canon")" "$([[ "$_cnn" != "0" ]] && echo 1 || echo 0)"
  done
)"
set_eq "term-usage per-card 個数 (data-term, cross_refs>0?1:0) emission 順" "$exp_cardusage" "$html_cardusage"
# (ii) 総数 == 全 slice 内総数 (blind region / entry 外 orphan を封鎖)
usage_gtot="$(printf '%s\n' "$usage_scan" | sed -n 's/^GTOTAL\t//p' | cut -f1)"
usage_gsum="$(printf '%s\n' "$usage_scan" | sed -n 's/^GTOTAL\t//p' | cut -f2)"
chk "term-usage 総数 == 全 term-entry slice 内 usage 総数 (blind region orphan 封鎖)" "${usage_gtot:-x}" "${usage_gsum:-y}"
# (iii) block 内帰属: data-usage-for == 親 data-term
usage_bind_bad="$(printf '%s\n' "$usage_scan" | sed -n 's/^BAD\t//p')"
chk_empty "term-usage 帰属: data-usage-for == 親 term-entry data-term (foreign-inside relocation 封鎖)" "$usage_bind_bad"

# ---- 2c-nesting: term-entry↔term-domain section の nesting を fail-closed 化 (folio-229 self-review・major) ----
#   上の §2c は domain-heading の文言・順 / data-term-domain の順 / term-entry 総数 を *各々独立に* pin するが、
#   『どの term-entry がどの term-domain section に nest するか』を一切束縛しない。 ゆえに multi-domain で domain 境界の
#   section-open (term-domain + heading) を 1 term ずらす改竄 (term を隣 domain の見出し下へ移す) をしても term-name 順・
#   data-term-domain 順・見出し順・term-entry 総数が保存され全 set_eq を素通り、 engineering 語が『予約業務の言葉』見出し下に
#   render される人間層の虚偽が floor を通過した (単一 domain の folio は内部境界が無く露出不能ゆえ multi-domain 固有の
#   未 pin 穴)。 PW-01 が正すべき当のもの (語を正しい friendly domain 下に置く) ゆえ floor 相当の構造 anchor。
#   (i)  各 term-domain section 直下の term-entry 数 == contract の domain 別語数 (SSoT 導出・emission 順)。
#   (ii) 各 term-entry の data-term-domain == 親 term-domain section の id (domain-<domain>)。
#   domain block は term-domain の *開始* marker で分割する (占有 count_attr_token class term-domain == |domains| が
#   additive/quote 変種の偽 section を別途封鎖済ゆえ、 境界 shift の core anchor は double-quote 開始 marker で足る)。
exp_domnest="$(
  _nd="$(q '.domains | length')"
  for ((_dj=0; _dj<_nd; _dj++)); do
    _did="$(q ".domains[$_dj].id")"
    _dcc="$(d="$_did" yq -r '[.terms[] | select(.domain == strenv(d))] | length' "$CONTRACT")"
    printf 'domain-%s\t%s\n' "$_did" "$_dcc"
  done
)"
html_domnest="$(perl -0777 -ne '
  my $txt=$_; my @d;
  while ($txt =~ /<section\b[^>]*\bclass="term-domain"[^>]*\bid="([^"]+)"[^>]*>/g) { push @d,[$1,pos($txt)]; }
  for (my $i=0;$i<@d;$i++){
    my $s=$d[$i][1]; my $e=($i+1<@d)?$d[$i+1][1]:length($txt);
    my $b=substr($txt,$s,$e-$s); my $n=0; $n++ while $b=~/<section\b[^>]*\bclass="term-entry"/g;
    print "$d[$i][0]\t$n\n";
  }' < "$BODY")"
set_eq "nesting: term-domain section 直下 term-entry 数 == domain 別語数 (境界 shift 封鎖)" "$exp_domnest" "$html_domnest"
domnest_bad="$(perl -CSD -0777 -ne '
  my $txt=$_; my @bad; my @d;
  while ($txt =~ /<section\b[^>]*\bclass="term-domain"[^>]*\bid="([^"]+)"[^>]*>/g) { push @d,[$1,pos($txt)]; }
  for (my $i=0;$i<@d;$i++){
    my $s=$d[$i][1]; my $e=($i+1<@d)?$d[$i+1][1]:length($txt);
    my $b=substr($txt,$s,$e-$s);
    while ($b=~/\bdata-term-domain="([^"]*)"/g){ push @bad,"$d[$i][0]\x{2260}$1" if "domain-$1" ne $d[$i][0]; }
  }
  print join(" ",@bad);' < "$BODY")"
chk_empty "nesting: 各 term-entry の data-term-domain == 親 section domain id (誤 domain 配置封鎖)" "$domnest_bad"

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
#   (a) visible-text-vs-attribute: 各 xref li の可視 "使われる文書: {target}" == "使われる文書: " + data-xref-target (属性 intact のまま可視のみ捏造を封鎖)。
#   ★folio-229: ラベル『定義元:』→『使われる文書:』へ改称 (glossary が canonical 定義の置き場という主張との緊張を解消・PW-02)。
xref_vis_bad="$(perl -CSD -Mutf8 -0777 -ne 'my @bad; while (/<li\b[^>]*\bdata-xref-target="([^"]*)"[^>]*>(.*?)<\/li>/gs){ my ($t,$in)=($1,$2); push @bad,"NESTED:$t" if $in=~/</; push @bad,"$t\x{2260}$in" if $in ne "使われる文書: $t"; } print join(" ",@bad);' < "$BODY")"
chk_empty "cross-doc: xref li 可視 == 使われる文書:{data-xref-target} (可視捏造封鎖)" "$xref_vis_bad"
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
exp_xref_vis="$(q '.terms[].cross_refs[]?' | while IFS= read -r t; do printf '使われる文書: %s\n' "$(esc "$t")"; done)"
chk "cross-doc(robust): term-xrefs li 総数 == |cross_refs| (quote非依存)" "$(q '[.terms[].cross_refs[]?] | length')" "${xref_n:-0}"
chk "cross-doc(robust): term-xrefs ul の非 li 残差 == 0 (非li/裸テキスト混入封鎖)" "0" "${xref_resid:-0}"
set_eq "cross-doc(robust): 可視 li == 使われる文書:{cross_ref} (quote非依存・属性引用形に依存しない可視 pin)" "$exp_xref_vis" "$xref_vis"
# ★folio-bur round-3 (ceiling-recursion R2 是正): 上の robust 列挙は container を <ul class=term-xrefs> に anchor するため
#   <ol class="term-xrefs"> / <div class="term-xrefs"> (別タグだが同 class) や別 class コンテナ (ul.decoy-xrefs) / class 無し <div> に
#   「使われる文書: X」を置く捏造 provenance を素通った (独立 ceiling 実証)。 core_chrome の『想定読者: marker==1』と同型に、
#   *大域* '使われる文書:' 出現数を pin (anchor の class/タグに依らず、 可視 provenance マーカーそのものを数える)。
# ★folio-229: マーカー『使われる文書:』は 2 箇所 = 機械層 li (|cross_refs flat| 個・生 doc-ID) + 人間層 term-usage 行
#   (|cross_refs を持つ term| 個・friendly gloss)。 大域出現数 = 両者の和で pin する (どちらの層の余剰マーカーも封鎖)。
chk "cross-doc: 大域 '使われる文書:' 出現数 == |xref flat| + |usage 行| (anchor 外 provenance 捏造封鎖)" \
  "$(( $(q '[.terms[].cross_refs[]?] | length') + $(q '[.terms[] | select((.cross_refs | length) > 0)] | length') ))" \
  "$(grep -oF '使われる文書:' "$BODY" | wc -l | tr -d ' ')"

# ---- 5b. per-card 完全束縛 (folio-229 errata-3・sweep 収束の終端装置・bhe/mzn.1.5 doctrine) ----
#   ★errata-1/2 は人間層 term-usage を per-card 束縛したが、 §2〜§5 の他 token (term-name h4 / data-term-en/slug/domain /
#     term-formal / JSON-LD @id・name / term-plain data-slot-id / term-xrefs data-xref-target 系列) は *大域 emission 順*
#     でしか contract と突合されず「どのカードに在るか」を pin しなかった。 隣接カード境界を跨ぐ token 移設 (大域順を保存)
#     は全大域検査を素通り、 機械層/人間層双方でカード単位の帰属詐称・出典喪失を許した (round-3 独立 ceiling が term-xrefs
#     li で実弾実証。 sweep で term-name/en/formal/plain も同型脆弱と確認)。
#   ★収束の構造: term-entry カード内に emit される *全* contract 由来 token を data-term (=カードの正準 identity) keyed の
#     完全 tuple にまとめ、 各カードの tuple を contract の当該 term から導出した期待 tuple と emission 順 set_eq する。
#     カード内の *どの* token を隣接/blind へ移しても source カードの tuple field が欠落/不一致し FAIL する = 面の後出し
#     列挙 (round ごとに 1 面ずつ) を「全 token を 1 検査で束縛」の有限不変条件へ畳んで終端させる。
#   tuple 順: data-term \t h4 \t en \t slug \t domain \t formal \t jsonld@id \t jsonld-name \t plain-slot \t xref系列。
#   全 field は esc 済み (assemble と同一規律。 folio inventory の formal に <head> 実在ゆえ esc 必須)。 xref は
#   カード内 data-xref-target を出現順に ',' 連結 (per-card 系列一致 = usage_scan と対称の機械層帰属束縛・round-3 処方(1))。
html_card="$(perl -CSD -0777 -ne '
  my $txt=$_;
  my @e; while ($txt =~ /<section\b[^>]*\bclass="term-entry"[^>]*\bdata-term="([^"]*)"[^>]*>/g) { push @e,[$1,pos($txt)]; }
  for (my $i=0;$i<@e;$i++){
    my $s=$e[$i][1]; my $end=($i+1<@e)?$e[$i+1][1]:length($txt);
    my $b=substr($txt,$s,$end-$s); my $C=$e[$i][0];
    my $h4 = ($b=~/<h4\b[^>]*\bclass="term-name"[^>]*>(.*?)<\/h4>/s) ? $1 : "\x{2205}";
    my $en = ($b=~/\bdata-term-en="([^"]*)"/) ? $1 : "\x{2205}";
    my $sl = ($b=~/\bdata-term-slug="([^"]*)"/) ? $1 : "\x{2205}";
    my $dm = ($b=~/\bdata-term-domain="([^"]*)"/) ? $1 : "\x{2205}";
    my $fm = ($b=~/<dd\b[^>]*\bclass="term-formal"[^>]*>(.*?)<\/dd>/s) ? $1 : "\x{2205}";
    my ($jid,$jnm) = ($b=~/"\@type":"DefinedTerm","\@id":"([^"]+)","name":"([^"]+)"/) ? ($1,$2) : ("\x{2205}","\x{2205}");
    my $ps = ($b=~/<p\b[^>]*\bclass="term-plain"[^>]*\bdata-slot-id="([^"]*)"/) ? $1 : "\x{2205}";
    my @xr; while ($b=~/\bdata-xref-target="([^"]*)"/g){ push @xr,$1; } my $xr=join(",",@xr);
    for my $v ($h4,$fm){ $v=~s/[\t\n]/ /g; }
    print "$C\t$h4\t$en\t$sl\t$dm\t$fm\t$jid\t$jnm\t$ps\t$xr\n";
  }' < "$BODY")"
CARD_SET_ID="$(q '.term_set_id')"; CARD_PREFIX="${CARD_SET_ID%%:*}"
# ★folio-229 errata-4 (certifier 処方): 期待 tuple の生値取得は @tsv でなく string-concat (\t 連結) を使う。
#   @tsv は素の " を CSV 二重引用 (…"" ) するため esc() (…&quot;) と乖離し、 formal_def/en に " を含む正当な将来
#   contract で §5b だけが誤 FAIL する (fail-closed 方向の汎用性回帰)。 string-concat は生値を無加工で返し esc() と整合。
#   全 field は非空 (contract validate 済) ゆえ concat は null エラーにならない。 usage_scan と同じ esc 明示導出。
exp_card="$(q '.terms[] | .canonical + "\t" + .en + "\t" + .slug + "\t" + .domain + "\t" + .formal_def + "\t" + .plain_slot + "\t" + ((.cross_refs // []) | join(","))' \
  | while IFS=$'\t' read -r _c _en _sl _dm _fm _ps _xr; do
      _ce="$(esc "$_c")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s:term/%s\t%s\t%s\t%s\n' \
        "$_ce" "$_ce" "$(esc "$_en")" "$(esc "$_sl")" "$(esc "$_dm")" "$(esc "$_fm")" "$CARD_PREFIX" "$_sl" "$_ce" "$(esc "$_ps")" "$(esc "$_xr")"
    done)"
set_eq "per-card 完全束縛 (data-term keyed: h4/en/slug/domain/formal/jsonld/plain/xref をカードへ pin) emission 順" "$exp_card" "$html_card"
# ★folio-229 errata-4 (must①): term-plain の双子属性 data-slot-id == data-prose-slot を per-element で等値検査。
#   assemble は両者を同値 (plain-<slug>) で emit する。 §5b は data-slot-id のみ per-card 束縛、 §8 は data-prose-slot を
#   注入 keying + read-back に使うため、 2 カード間で data-prose-slot + 本文を対称 swap すると §5b [OK]・§8 [OK] のまま
#   平易定義の帰属詐称が成立した (round-4 独立 ceiling が m-plainswap で実弾実証)。 双子等値を要求して三方塞がり:
#   片方 swap = 等値破れ (本検査) / 両方 swap = §5b (data-slot-id 束縛) / 本文のみ swap = §8 read-back (data-prose-slot keying)。
slotid_neq="$(perl -CSD -0777 -ne 'my @bad; while (/<p\b[^>]*\bclass="term-plain"[^>]*>/g){ my $t=$&; my $si=($t=~/\bdata-slot-id="([^"]*)"/)?$1:"\x{2205}"; my $ps=($t=~/\bdata-prose-slot="([^"]*)"/)?$1:"\x{2205}"; push @bad,"$si\x{2260}$ps" if $si ne $ps; } print join(" ",@bad);' < "$BODY")"
chk_empty "term-plain: data-slot-id == data-prose-slot (双子 keying の対称 swap 封鎖)" "$slotid_neq"

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
html_genmeta="$(perl -0777 -ne 'while (/<p\b[^>]*\bclass="gen-meta"[^>]*>(.*?)<\/p>/gs){ my $t=$1; $t=~s/[\t\n]/ /g; print "$t\n"; }' < "$BODY")"
chk "gen-meta == .footer.gen_meta (可視 contract 値)" "$exp_genmeta" "$html_genmeta"
html_h2count="$(perl -0777 -ne 'while (/<h2\b[^>]*>\s*用語\s*\((\d+)\s*語\)\s*<\/h2>/gs){ print "$1\n"; }' < "$BODY")"
chk "用語数 h2 N == NTERMS (可視 contract 導出)" "$NTERMS" "$html_h2count"

# ---- 7. footer verify-state token (core chrome) ----
# verify_core_chrome は argless (占有 pin 退役後・folio-smby: 旧 $1/$2 = role/en 追加 home 数は消費者無しゆえ無視)。
#   glossary は actor (div.role) も EARS legend en も持たない (= 追加 0) ゆえ従来から引数不要。
verify_core_chrome

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
