#!/usr/bin/env bash
# folio engine B4 (folio-igv) — principle-pack fabrication-free + 終端 + baseline-diff + inbound proof (instance#4)
#
# 生成 principle HTML の *構造* が入力 principle contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS) / verify-adr.sh (ADR) / verify-research.sh (research) と同型の規律を
# principle-pack schema (principles / versioning / amendment / inbound) へ適用し、 さらに principle 固有の
# 3 つの gate を加える:
#   - ★①終端強制: principle は照会の終端ゆえ HTML に前方照会 chip (leads_to/justifies/resolved_by/cross-doc-*) を持たない。
#   - ★②baseline-diff gate (doc_type:constitution のみ): principles の committed golden と diff し、
#       宣言文 (statement) / tier / 増減 の変化には必ず (新規 amended_by → 実在 ADR) + (版 bump) を要求 = silent change を機械的に不可能化。
#   - ★③inbound fail-closed (doc_type:constitution のみ): inbound.ref が principles[].id に実在 (phantom 照会捕捉) を
#       core の verify_cross_doc_refs を *target=self* で再利用して確かめる (照会終端 node の局所整合・graph 横断は B5)。
# 加えて floor: 行数=contract導出 / id 一意 / 可視 pid・heading 順序 / tier badge fidelity / statement fidelity (badge-strip) /
#   amendment 来歴 fidelity / cover-meta 再導出 / escape 健全 / prose スロット (3 mode) / term-inline / core 共通 chrome。
#
# usage: verify-principle.sh [--filled <manifest.yaml> | --artifact | --write-baseline] <principle-contract.yaml> <generated.html>
#        --write-baseline は HTML 不要 (golden を現 contract から生成し exit)。
# exit:  0 = PASS / 1 = FAIL / 2 = tool error
#
# ★★floor / ceiling 境界 (two-gate モデル・S5.1)。 本 floor が担うのは *構造アンカー + 決定的フィールド値* の contract 突合
#   (id / 件数 / tier / statement (決定的・badge-strip 後の可視テキスト) / amendment 来歴 / inbound / baseline-diff)。
#   prose スロット (cover-summary / chapter-lead / plain-Px / versioning-plain / amendment-plain) の *内容真正性* は
#   floor の対象外 = ceiling (fidelity-principle 相当 agent・persona-walk-principle)。 floor 単独で GREEN にはならず
#   CEILING=PENDING (taxonomy §5.1)。 principle-pack 専用 ceiling agent の制度化は follow-up (admin が別 bd 起票)。

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""; WRITE_BASELINE=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift
elif [[ "${1:-}" == "--write-baseline" ]]; then WRITE_BASELINE=1; shift; fi
CONTRACT="${1:?usage: verify-principle.sh [--filled <manifest> | --artifact | --write-baseline] <contract.yaml> [html]}"
[[ -f "$CONTRACT" ]] || { echo "verify-principle: contract not found: $CONTRACT" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-principle: yq required" >&2; exit 2; }
CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"

# ---- core 共通層 (q/esc/qesc/chk/chk_empty/set_eq/make_body/verify_term_inline/verify_core_chrome/verify_cross_doc_refs) ----
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-principle: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=52; source "$LVC" || { echo "verify-principle: failed to source verify-common.sh" >&2; exit 2; }

# tier 表示ラベル/class (assemble-principle.sh と二重保守 = detect↔remediate parity)。
declare -A TIER_LABEL=( [Always]="いつも守る (例外なし)" [Ask-first]="変える前に確認" [Never]="絶対にやらない" )
declare -A TIER_CLASS=( [Always]="tier-always" [Ask-first]="tier-askfirst" [Never]="tier-never" )

# baseline golden パス (contract basename 由来) と decisions dir (amended_by 実在確認用)。
BASE_NAME="$(basename "$CONTRACT")"; BASE_NAME="${BASE_NAME%.yaml}"
BASELINE_FILE="$SCRIPT_DIR/baselines/${BASE_NAME}.golden"
DECISIONS_ABS=""
if [[ "$(q 'has("decisions_dir")')" == "true" ]]; then
  _dd="$(q '.decisions_dir')"
  if [[ "$_dd" == /* ]]; then DECISIONS_ABS="$(cd "$_dd" 2>/dev/null && pwd || true)"
  else DECISIONS_ABS="$(cd "$CONTRACT_DIR/$_dd" 2>/dev/null && pwd || true)"; fi
fi

# ---- baseline (principles の正規化スナップショット) ----
# 1 行 = <id>\t<tier>\t<sha256(heading + LF + statement)>\t<amended_adrs sorted csv>。 先頭に #VERSION\t<version>。
# ★sha は heading も被覆する (cell-quality major: heading-only silent change が gate を素通る穴を塞ぐ・
#   heading は原則の一部ゆえ宣言文と同格に baseline-diff の追跡対象)。
emit_baseline() {
  printf '#VERSION\t%s\n' "$(q '.meta.version')"
  local pid tier head stmt sha adrs
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    tier="$(q '.principles[] | select(.id=="'"$pid"'") | .tier')"
    head="$(q '.principles[] | select(.id=="'"$pid"'") | .heading')"
    stmt="$(q '.principles[] | select(.id=="'"$pid"'") | .statement')"
    sha="$(printf '%s\n%s' "$head" "$stmt" | sha256sum | cut -d' ' -f1)"
    adrs="$(q '.principles[] | select(.id=="'"$pid"'") | (.amended_by // []) | .[].adr' | sort | paste -sd, -)"
    printf '%s\t%s\t%s\t%s\n' "$pid" "$tier" "$sha" "$adrs"
  done < <(q '.principles[].id')
}

# --write-baseline: golden を現 contract から生成して exit (人間が原則変更を承認したとき更新する正規路)。
if [[ -n "$WRITE_BASELINE" ]]; then
  mkdir -p "$(dirname "$BASELINE_FILE")"
  emit_baseline > "$BASELINE_FILE"
  echo "verify-principle: wrote baseline golden -> $BASELINE_FILE" >&2
  exit 0
fi

HTML="${2:?usage: verify-principle.sh [...] <contract.yaml> <generated.html>}"
[[ -f "$HTML" ]] || { echo "verify-principle: html not found: $HTML" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-principle: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }

fail=0
make_body "$HTML"

# adr_exists — ADR が decisions dir に実在するか (baseline-diff の新規 amended_by 実在確認)。
adr_exists() { local adr="$1"; [[ -n "$DECISIONS_ABS" && -d "$DECISIONS_ABS" ]] || return 1; compgen -G "${DECISIONS_ABS}/${adr}-*.html" >/dev/null 2>&1; }

echo "principle-pack fabrication-free + 終端 + baseline-diff + inbound proof: $HTML"
echo "  contract: $CONTRACT"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "principle rows == |principles|"   "$(q '.principles | length')"  "$(grep -c 'data-component="principle-row"' "$BODY")"
chk "tier badges == |principles|"      "$(q '.principles | length')"  "$(grep -c 'data-component="principle-tier-badge"' "$BODY")"
chk "amendment-history == |amended|"   "$(q '[.principles[] | select((.amended_by // []) | length > 0)] | length')" "$(grep -c 'data-component="principle-amendment-history"' "$BODY")"
chk "inbound chips == |inbound|"       "$(q '.inbound | length')"     "$(grep -c 'data-component="principle-inbound-chip"' "$BODY")"
chk "versioning policy table == 1"     "1"                            "$(grep -c 'data-component="versioning-policy-table"' "$BODY")"
chk "amendment procedure == 1"         "1"                            "$(grep -c 'data-component="amendment-procedure-steps"' "$BODY")"
chk "versioning rules == |rules|"      "$(q '.versioning.rules | length')" "$(grep -c 'class="vp-bump"' "$BODY")"
chk "amendment steps == |steps|"       "$(q '.amendment.steps | length')"  "$(grep -oE '<li>' "$BODY" | wc -l | tr -d ' ')"
chk "glossary == |glossary|"           "$(q '.glossary | length')"    "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"           "$(q '.approval | length')"    "$(grep -c 'class="sign"' "$BODY")"
# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# 2. id 一意性 + tier allowlist 再導出
chk_empty "principle id 一意"  "$(q '.principles[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "tier allowlist {Always,Ask-first,Never}" "$(q '.principles[].tier' | grep -vxE 'Always|Ask-first|Never' | tr '\n' ' ')"

# 3. ★①終端強制: principle は照会終端ゆえ前方照会 chip を持たない (inbound = data-inbound-* は受ける照会ゆえ別物・許可)。
chk "終端: HTML に前方照会 chip 無し (leads_to/justifies/resolved_by/cross-doc-*)" "0" \
  "$(grep -cE 'data-leads-to=|data-justifies|data-resolved-by=|cross-doc-leads-chip|cross-doc-ref-chip' "$BODY")"

# 4. within-doc 可視 id / heading 順序 (assembler の emit 順 = tier-grouped: Always→Ask-first→Never・各 tier 内は contract 配列順)。
#    ★contract 配列が tier 順でなくても assembler に一致させる (順序検証 robustness)。 tier 改竄は §13 baseline-diff が単独で捕捉。
tg_field() { local t; for t in Always Ask-first Never; do q '.principles[] | select(.tier=="'"$t"'") | '"$1"; done; }
exp_pid="$(tg_field '.id')"
exp_heading="$(tg_field '.heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
chk "within-doc: 可視 pid 列 == principles(tier順).id" \
  "$exp_pid" \
  "$(grep -oE '<span class="pid">[^<]*</span>' "$BODY" | sed -E 's#<span class="pid">([^<]*)</span>#\1#')"
chk "within-doc: 可視 heading 列 == principles(tier順).heading" \
  "$exp_heading" \
  "$(grep -oE '<h3 class="ph">[^<]*</h3>' "$BODY" | sed -E 's#<h3 class="ph">([^<]*)</h3>#\1#')"
# pid→heading 隣接 (id span 直後に heading が来る = 後置平文偽 id を捕捉)。
chk "within-doc: pid→ph 隣接 == |principles|" "$(q '.principles | length')" \
  "$(grep -oE '<span class="pid">[^<]*</span><h3 class="ph">' "$BODY" | wc -l | tr -d ' ')"

# 5. ★tier badge fidelity: 可視 tier ラベル列 + badge class 列が contract tier 写像と順序一致 (controlled value・tier-grouped)。
exp_tlabel="$(tg_field '.tier' | while IFS= read -r t; do [[ -n "$t" ]] && printf '%s\n' "$(esc "${TIER_LABEL[$t]:-$t}")"; done)"
act_tlabel="$(grep -oE '<span data-component="principle-tier-badge"[^>]*>[^<]*</span>' "$BODY" | sed -E 's#.*>([^<]*)</span>#\1#')"
chk "tier badge: 可視ラベル列 == tier 写像 (順序)" "$exp_tlabel" "$act_tlabel"
exp_tclass="$(tg_field '.tier' | while IFS= read -r t; do [[ -n "$t" ]] && printf '%s\n' "${TIER_CLASS[$t]:-tier-unknown}"; done)"
act_tclass="$(grep -oE '<span data-component="principle-tier-badge" class="[^"]*"' "$BODY" | sed -E 's#.*class="([^"]*)"#\1#')"
chk "tier badge: class 列 == tier 写像 (順序)" "$exp_tclass" "$act_tclass"
# row class も tier 写像と一致 (row の border 色 tier 改竄を捕捉)。
act_rowclass="$(grep -oE '<div data-component="principle-row" class="[^"]*"' "$BODY" | sed -E 's#.*class="([^"]*)"#\1#')"
chk "principle-row: class 列 == tier 写像 (順序)" "$exp_tclass" "$act_rowclass"

# 6. ★statement fidelity (決定的・badge-strip 後の可視テキスト == esc(contract statement) を順序突合)。
#    mark_terms は語の *直後* に term バッジを挿入する (語自体は残る) ゆえ、 legit double-quote 形の term バッジを strip すると
#    可視テキストは esc(statement) に一致する (dty §7g と同型)。 esc 済ゆえ pst 内に生 </p> は無く (.*?)</p> は安全。
chk "statement rows (p.pst) == |principles|" "$(q '.principles | length')" "$(grep -c '<p class="pst">' "$BODY")"
exp_st="$(tg_field '.statement' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_st="$(perl -CSD -0777 -ne '
  while (/<p class="pst">(.*?)<\/p>/gs) {
    my $t=$1;
    $t =~ s{<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>}{}g;
    print "$t\n";
  }
' "$BODY")"
set_eq "statement: badge-strip 可視テキスト == esc(contract) (順序)" "$exp_st" "$act_st"

# 7. ★amendment 来歴 fidelity: data-amended-adr 集合/件数 + 可視 <b> == attr。
chk "amendment: data-amended-adr 件数 == Σ|amended_by|" \
  "$(q '[.principles[].amended_by[]?] | length')" "$(grep -o 'data-amended-adr=' "$BODY" | wc -l | tr -d ' ')"
exp_adr="$(q '.principles[].amended_by[]?.adr' | sort)"
act_adr="$(grep -oE 'data-amended-adr="[^"]+"' "$BODY" | sed 's/.*data-amended-adr="//; s/"$//' | sort)"
set_eq "amendment: data-amended-adr 集合 == contract amended_by.adr" "$exp_adr" "$act_adr"
# 可視 <b> id == data-amended-adr (am-row 内・属性正で可視のみ改竄する経路を捕捉)。
am_vis_bad="$(perl -CSD -0777 -ne '
  my @bad;
  while (/<span class="am-row"[^>]*\bdata-amended-adr="([^"]*)"[^>]*>(.*?)<\/span>/gs) {
    my ($adr,$in)=($1,$2);
    my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=1){ push @bad,"$adr:".scalar(@bs)."B"; next }
    push @bad,"$adr:b\x{2260}$bs[0]" if $bs[0] ne $adr;
  }
  print join(" ",@bad);
' "$BODY")"
chk_empty "amendment: am-row 可視 <b> == data-amended-adr" "$am_vis_bad"

# 8. versioning / amendment セクションの決定的フィールド値 fidelity。
chk "versioning: basis == contract" "$(esc "$(q '.versioning.basis')")" \
  "$(grep -oE '<p class="vp-basis">準拠: <b>[^<]*</b></p>' "$BODY" | sed -E 's#.*<b>([^<]*)</b>.*#\1#')"
chk "versioning: bump 列 == .versioning.rules[].bump (順序)" "$(qesc '.versioning.rules[].bump')" \
  "$(grep -oE '<td class="vp-bump">[^<]*</td>' "$BODY" | sed -E 's#<td class="vp-bump">([^<]*)</td>#\1#')"
chk "versioning: condition 列 == .versioning.rules[].condition (順序)" "$(qesc '.versioning.rules[].condition')" \
  "$(grep -oE '<td class="vp-cond">[^<]*</td>' "$BODY" | sed -E 's#<td class="vp-cond">([^<]*)</td>#\1#')"
chk "versioning: note == contract" "$(esc "$(q '.versioning.note')")" \
  "$(grep -oE '<p class="vp-note">[^<]*</p>' "$BODY" | sed -E 's#<p class="vp-note">([^<]*)</p>#\1#')"
chk "amendment: steps 列 == .amendment.steps (順序)" "$(qesc '.amendment.steps[]')" \
  "$(grep -oE '<li>[^<]*</li>' "$BODY" | sed -E 's#<li>([^<]*)</li>#\1#')"

# 9. ★表紙 cover-meta 4 KV の決定的再導出突合 (research の l' と同型)。
meta_kv="$(perl -CSD -0777 -ne 'while (/<span class="k">([^<]*)<\/span><span class="v">([^<]*)<\/span>/g){ print "$1\t$2\n"; }' "$BODY")"
chk "cover-meta 原則の総数 == |principles|件" "$(q '.principles | length') 件" "$(printf '%s\n' "$meta_kv" | grep -F '原則の総数' | head -1 | cut -f2)"
exp_tier_break="Always $(q '[.principles[] | select(.tier=="Always")] | length') / Ask-first $(q '[.principles[] | select(.tier=="Ask-first")] | length') / Never $(q '[.principles[] | select(.tier=="Never")] | length')"
chk "cover-meta tier 内訳 == 再導出" "$exp_tier_break" "$(printf '%s\n' "$meta_kv" | grep -F 'tier 内訳' | head -1 | cut -f2)"
chk "cover-meta 改訂来歴 == |amended|件" "$(q '[.principles[] | select((.amended_by // []) | length > 0)] | length') 件" "$(printf '%s\n' "$meta_kv" | grep -F '改訂来歴' | head -1 | cut -f2)"
chk "cover-meta 版 == vX / date" "v$(q '.meta.version') / $(q '.meta.date')" "$(printf '%s\n' "$meta_kv" | grep -F '版' | head -1 | cut -f2)"
chk "cover-meta KV 総数 == 4" "4" "$(printf '%s\n' "$meta_kv" | grep -c .)"

# 10. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 11. prose スロット (perl で要素単位判定・3 mode)
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

# 12. term-inline fidelity + 用語被覆 (markable = principles[].statement のみ・assemble と二重保守)。
verify_term_inline '.principles[].statement' "term-inline 被覆 (マーク == statement 出現 glossary 語)"

# ===== doc_type:constitution 専用 gate (②baseline-diff / ③inbound) =====
DOC_TYPE="$(q '.meta.doc_type')"
# ★doc_type fail-closed (cell-quality critical): principle-pack は constitution 専用。 baseline-diff / inbound gate は
#   どちらも doc_type:constitution で起動するため、 doc_type を constitution 以外へ flip すると両 gate が silent skip され
#   原則 statement/tier の silent change が verify PASS で素通る fail-open があった。 非 constitution を hard FAIL にして
#   flip による gate bypass を封鎖する (assemble-principle.sh validate も生成段で doc_type==constitution を必須化)。
chk "doc_type == constitution (flip で baseline-diff/inbound gate を bypass 不可)" "constitution" "$DOC_TYPE"
if [[ "$DOC_TYPE" == "constitution" ]]; then
  # 13. ★②baseline-diff gate: golden と diff し、 宣言文/tier/増減の変化に amended_by→実在ADR + 版bump を強制。
  if [[ ! -f "$BASELINE_FILE" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s %s\n' "baseline-diff: golden 不在 (--write-baseline で生成)" "$BASELINE_FILE"; fail=1
  else
    declare -A G_TIER G_SHA G_ADR C_TIER C_SHA C_ADR SEEN_ID
    g_version=""; c_version="$(q '.meta.version')"
    while IFS=$'\t' read -r id tier sha adrs; do
      [[ "$id" == "#VERSION" ]] && { g_version="$tier"; continue; }
      [[ -n "$id" ]] || continue; G_TIER[$id]="$tier"; G_SHA[$id]="$sha"; G_ADR[$id]="$adrs"; SEEN_ID[$id]=1
    done < "$BASELINE_FILE"
    while IFS=$'\t' read -r id tier sha adrs; do
      [[ "$id" == "#VERSION" ]] && continue
      [[ -n "$id" ]] || continue; C_TIER[$id]="$tier"; C_SHA[$id]="$sha"; C_ADR[$id]="$adrs"; SEEN_ID[$id]=1
    done < <(emit_baseline)
    # ★版 bump 判定 (cell-quality minor): 単なる文字列差分でなく g→c が「前進」(sort -V で c が後) を要求し
    #   downgrade / 同値 / garbage を「版 bump」と誤認しない。
    version_bumped=0
    if [[ "$c_version" != "$g_version" ]]; then
      _later="$(printf '%s\n%s\n' "$g_version" "$c_version" | sort -V | tail -1)"
      [[ "$_later" == "$c_version" ]] && version_bumped=1
    fi
    changed=0; bd_viol=""
    # 変化した principle に「golden に無い新規 amended_by」かつ「実在 ADR」が 1 つ以上あるか。
    has_new_real_amend() { # $1=id $2=golden_adr_csv
      local id="$1" g="$2" a
      while IFS= read -r a; do
        [[ -n "$a" ]] || continue
        if [[ ",$g," != *",$a,"* ]]; then adr_exists "$a" && return 0; fi
      done < <(q '.principles[] | select(.id=="'"$id"'") | (.amended_by // []) | .[].adr')
      return 1
    }
    for id in "${!SEEN_ID[@]}"; do
      local_in_g=0; local_in_c=0
      [[ -n "${G_TIER[$id]+x}" ]] && local_in_g=1
      [[ -n "${C_TIER[$id]+x}" ]] && local_in_c=1
      if [[ $local_in_g -eq 1 && $local_in_c -eq 0 ]]; then
        changed=1; [[ $version_bumped -eq 1 ]] || bd_viol+=" $id(削除:版bump無)"
      elif [[ $local_in_g -eq 0 && $local_in_c -eq 1 ]]; then
        changed=1; [[ $version_bumped -eq 1 ]] || bd_viol+=" $id(追加:版bump無)"
        has_new_real_amend "$id" "" || bd_viol+=" $id(追加:新規amended_by→実在ADR無)"
      elif [[ "${G_SHA[$id]}" != "${C_SHA[$id]}" || "${G_TIER[$id]}" != "${C_TIER[$id]}" || "${G_ADR[$id]}" != "${C_ADR[$id]}" ]]; then
        # ★宣言文(heading+statement の sha)/tier/amended_by(adrs) のいずれの変化も「変更」= 正当化必須 (cell-quality major:
        #   adrs 列を比較しないと既存 amended_by の silent 消去/書換が素通る穴を塞ぐ)。
        changed=1; [[ $version_bumped -eq 1 ]] || bd_viol+=" $id(変更:版bump無)"
        has_new_real_amend "$id" "${G_ADR[$id]}" || bd_viol+=" $id(変更/来歴改竄:新規amended_by→実在ADR無)"
      fi
    done
    if [[ -n "$bd_viol" ]]; then
      printf '  [FAIL] %-'"$CHKW"'s%s\n' "baseline-diff: silent change (正当化なき宣言文/tier/増減)" "$bd_viol"; fail=1
    elif [[ $changed -eq 0 ]]; then
      printf '  [OK]   %-'"$CHKW"'s v%s\n' "baseline-diff: golden と一致 (silent change なし)" "$c_version"
    else
      printf '  [OK]   %-'"$CHKW"'s v%s→v%s\n' "baseline-diff: 変化は全て amended_by→実在ADR+版bump 済" "$g_version" "$c_version"
    fi
  fi

  # 14. ★③inbound fail-closed: verify_cross_doc_refs を target=self で再利用 (inbound.ref が principles[].id に実在)。
  if [[ "$(q 'has("inbound")')" == "true" ]]; then
    verify_cross_doc_refs \
      --label-prefix "inbound" --target-label "principles(self)" \
      --target-abs "$CONTRACT" \
      --key-attr "data-inbound-ref" --role-attr "data-inbound-role" \
      --keys-expr '.inbound[].ref' \
      --count-expr '.inbound | length' \
      --nonempty-count-expr '[.inbound[] | select((.ref // "") != "")] | length' \
      --pair-expr '.inbound[] | [.ref, .role] | @tsv' \
      --target-ids-expr '.principles[].id' \
      --contract-docid-expr '.meta.doc_id' \
      --target-docid-expr '.meta.doc_id'
    # 可視 <b> id == data-inbound-ref (ib-ref 内・属性正で可視のみ改竄する経路を捕捉)。
    ib_vis_bad="$(perl -CSD -0777 -ne '
      my @bad;
      while (/<div class="ib-grid">/g){}  # no-op anchor
      while (/<div data-component="principle-inbound-chip"[^>]*\bdata-inbound-ref="([^"]*)"[^>]*>(.*?)<\/div>/gs) {
        my ($ref,$in)=($1,$2);
        my @bs=$in=~/<b>([^<]*)<\/b>/g;
        if (@bs!=1){ push @bad,"$ref:".scalar(@bs)."B"; next }
        push @bad,"$ref:b\x{2260}$bs[0]" if $bs[0] ne $ref;
      }
      print join(" ",@bad);
    ' "$BODY")"
    chk_empty "inbound: ib-ref 可視 <b> == data-inbound-ref" "$ib_vis_bad"
  fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  bd_note=""; [[ "$DOC_TYPE" == "constitution" ]] && bd_note=" + 終端 + baseline-diff + inbound"
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + term-inline + prose 全充填${bd_note}) — CEILING=PENDING"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + prose 注入忠実${bd_note}) — CEILING=PENDING"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + prose 空${bd_note}) — CEILING=PENDING"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
