#!/usr/bin/env bash
# folio engine B1 (folio-bwc) — ADR-pack fabrication-free + cross-doc 照会 proof (instance#2)
#
# 生成 ADR HTML の *構造* が入力 ADR contract から完全に導出されたことを機械検証する。
# verify-fabrication-free.sh (SRS-pack) と同型の規律を ADR-pack schema へ適用:
#   - 行数 (context / drivers / options / consequences pos+neg / glossary / approval) が contract 要素数と一致。
#   - id 一意性 (context / drivers / options / consequences)。
#   - ★cross-doc 照会 (本 pack の核): decision.justifies の要件集合が
#       (a) HTML の data-justifies-req 集合と *集合一致* (捏造 0 + 脱落 0) + count anchor で |justifies| と一致
#           (set_eq は sort -u で重複を潰すため、 既存 edge の重複注入は count とペアにして捕捉)、
#       (b) 参照先 SRS contract の要件 ID に *実在* (dangling 照会 0)、
#       (c) cross_doc.srs_doc_id == SRS contract .meta.doc_id、
#       (d) data-justifies-role が抽象ロール allowlist 内 (claim/rationale/exploration/principle/verification/implementation)、
#       (d') (req,role) ペア集合が contract と *集合一致* (allowlist 内別 role への改竄 = 照会 graph 意味偽装を捕捉)。
#   - verdict 整合 (chosen ちょうど 1 + decision.chosen 一致 + (opt-id,verdict) ペアが contract と集合一致
#       = count 保存型のバッジ付け替え〔採用カード偽装〕を捕捉 + (verdict,可視ラベル) 整合
#       = class は正のまま human-visible 文字だけ改竄する偽装を捕捉)。
#   - supersession / principle (emit する終端章の fabrication-free): adr-supersession/adr-principle 各 1 件 +
#       principle.id / supersession.status / supersedes / superseded_by が contract 導出と一致。
#   - escape 健全性 (<lt; 等の化け 0 / >null< 漏れ 0)。
#   - prose スロット: 既定=全空 (pre-fill) / --filled <manifest>=全充填 + 注入忠実 / --artifact=全充填のみ。
#   - term-inline (plain-language-term-inline) の fidelity + 用語被覆 (assemble-adr と同一語境界規律)。
#
# usage: verify-adr.sh [--filled <manifest.yaml> | --artifact] <adr-contract.yaml> <generated.html>
# exit:  0 = PASS / 1 = FAIL / 2 = tool error

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILLED_MANIFEST=""; ARTIFACT=""
if [[ "${1:-}" == "--filled" ]]; then FILLED_MANIFEST="${2:?--filled requires <manifest.yaml>}"; shift 2
elif [[ "${1:-}" == "--artifact" ]]; then ARTIFACT=1; shift; fi
CONTRACT="${1:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-adr.sh [--filled <manifest> | --artifact] <adr-contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-adr: input not found" >&2; exit 2; }
[[ -z "$FILLED_MANIFEST" || -f "$FILLED_MANIFEST" ]] || { echo "verify-adr: manifest not found: $FILLED_MANIFEST" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-adr: yq required" >&2; exit 2; }

CONTRACT_DIR="$(cd "$(dirname "$CONTRACT")" && pwd)"
# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-48s ----
# 新依存 lib/verify-common.sh を fail-closed guard する (欠落/source 失敗を false-green に倒さない。
# set -e 無しゆえ source rc=1 でも継続し helper が command-not-found 化する)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-adr: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=48; source "$LVC" || { echo "verify-adr: failed to source verify-common.sh" >&2; exit 2; }
fail=0
make_body "$HTML"      # body-only ($BODY、 inline CSS の data-component 混入回避)

echo "ADR-pack fabrication-free + cross-doc 照会 proof: $HTML"
echo "  contract: $CONTRACT"

# 1. 行数 (data-component / class 行マーカーで table-scoped、 id 命名非依存)
chk "context rows == |context|"           "$(q '.context | length')"                 "$(grep -c 'data-component="adr-context-row"' "$BODY")"
chk "driver rows == |drivers|"            "$(q '.drivers | length')"                 "$(grep -c 'data-component="adr-driver-row"' "$BODY")"
chk "option cards == |options|"          "$(q '.options | length')"                 "$(grep -c 'data-component="adr-option-card"' "$BODY")"
chk "consequence(pos) == |positive|"     "$(q '.consequences.positive | length')"   "$(grep -c 'data-component="adr-consequence-pos"' "$BODY")"
chk "consequence(neg) == |negative|"     "$(q '.consequences.negative | length')"   "$(grep -c 'data-component="adr-consequence-neg"' "$BODY")"
chk "glossary == |glossary|"             "$(q '.glossary | length')"                "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"             "$(q '.approval | length')"                "$(grep -c 'class="sign"' "$BODY")"

# 2. id 一意性
chk_empty "context id 一意"     "$(q '.context[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "driver id 一意"      "$(q '.drivers[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "option id 一意"      "$(q '.options[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "consequence id 一意" "$(q '(.consequences.positive + .consequences.negative)[].id' | sort | uniq -d | tr '\n' ' ')"

# 3. ★cross-doc 照会 (本 pack の核)
SRS_REL="$(q '.cross_doc.srs_contract')"; SRS_ABS="${CONTRACT_DIR}/${SRS_REL}"
# 共通スケルトン (照会先実在/doc_id/count/SET/dangling/★空値ガード/role allowlist/(key,role)ペア) は ds8 で core 昇格。
# ★空値ガード (key 全件非空) は helper が両 pack へ無料配布する = ADR が従来欠いていた fail-open 穴を ds8 で塞ぐ
#   (empty-value バグは assemble-adr validate でも実在を修正済・本 verify 側は helper が二重に担保)。
verify_cross_doc_refs \
  --label-prefix "cross-doc" --target-label "SRS" \
  --target-abs "$SRS_ABS" --target-rel "$SRS_REL" \
  --key-attr "data-justifies-req" --role-attr "data-justifies-role" \
  --keys-expr '.decision.justifies[].req' \
  --count-expr '.decision.justifies | length' \
  --nonempty-count-expr '[.decision.justifies[] | select((.req // "") != "")] | length' \
  --pair-expr '.decision.justifies[] | [.req, .role] | @tsv' \
  --target-ids-expr '(.requirements[].id, .nfr[].id)' \
  --contract-docid-expr '.cross_doc.srs_doc_id' \
  --target-docid-expr '.meta.doc_id'

# 3b. ★Part 2b: ADR cross-doc 可視 echo の堅牢検証 (research round-2/4 ceiling template を ADR の 3 可視 echo へ横展開)。
#   非エンジニアが実際に読むのは attr でなく *可視テキスト*。 attr 突合 (上の helper) だけでは可視文字の偽装が素通る fail-open。
#   各 echo ブロックは固定個数 (ブロックごと削除すると while が回らず @bad 空で素通る fail-open を count anchor で塞ぐ)。
chk "cross-doc: ref-chip ブロック == 1"          "1" "$(grep -c 'data-component="cross-doc-ref-chip"' "$BODY")"
chk "cross-doc: justify-tgt ブロック == 1"        "1" "$(grep -c 'class="justify-tgt"' "$BODY")"
# ★ds8 ceiling: jh 見出し (assemble-adr emit の第4の可視 cross-doc echo・srs_doc_id を可視補間) も突合する。
#   Part 2b が ref-chip/justify-tgt/justify-req の 3 echo のみを列挙し jh を見落としていた = 機械的完全性照合 (全可視 echo の enumeration) の漏れ。
chk "cross-doc: jh 見出しブロック == 1"           "1" "$(grep -c 'class="jh"' "$BODY")"
chk "cross-doc: justify-req span == |justifies|" "$(q '.decision.justifies | length')" "$(grep -c 'class="justify-req"' "$BODY")"
srs_id_e="$(esc "$(q '.cross_doc.srs_doc_id')")"
srs_join_e="$(esc "$(q '[.decision.justifies[].req] | join("・")')")"
srs_title_e="$(esc "$(q '.cross_doc.srs_title')")"
# ★可視テキスト厳密一致 (round-4 不動点 + ds8 ceiling 深化): 各 echo の全タグ除去後の可視テキストが固定テンプレ+id(+title) と完全一致を要求。
#   ★while-regex は *marker-keyed* (<(\w+)\b ... marker ...>(.*?)</\1>) = data-component/class マーカーを担持する任意 wrapper タグを捕捉する。
#   tag 固定 (<div>/<p>) だと wrapper-tag swap (<div>→<span> や <pX> 注入) で while がスキップし可視検査を逃れる fail-open があった
#   (ds8 ceiling 検出・B3 research にも潜在=「可視テキスト厳密一致」の不動点が wrapper-tag 選択で兄弟経路を残していた)。 marker-only count anchor (上) と
#   marker-keyed while で selector パリティを取り、 swap・別タグ注入・第2<b>・平文併記・タグ併記・削除 を一括封鎖する。
#   ref-chip は <b> ちょうど 2 本 (srs_doc_id, join(req,・))・jh と justify-tgt は <b> 無し平文・justify-req は attr==可視。
adr_echo_bad="$(EXP="$srs_id_e" JOIN="$srs_join_e" TITLE="$srs_title_e" perl -CSD -Mutf8 -0777 -ne '
  my $exp=$ENV{EXP}; utf8::decode($exp); my $join=$ENV{JOIN}; utf8::decode($join); my $title=$ENV{TITLE}; utf8::decode($title);
  my @bad;
  # (h) 表紙 cross-doc-ref-chip: <b> ちょうど 2 本 (b1=srs_doc_id / b2=join(req,・))・可視テキスト厳密一致
  #     (先頭の ICO_USER svg は全タグ除去で消えるが直後の半角空白は可視テキストに残る = テンプレ先頭に空白)。
  while (/<(\w+)\b[^>]*\bdata-component="cross-doc-ref-chip"[^>]*>(.*?)<\/\1>/gs) {
    my $in=$2; my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=2){push @bad,"ref-chip:".scalar(@bs)."B"; next}
    push @bad,"ref-chip:b1\x{2260}$bs[0]" if $bs[0] ne $exp;
    push @bad,"ref-chip:b2\x{2260}$bs[1]" if $bs[1] ne $join;
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"ref-chip:VIS" if $vis ne " 正当化する要件: $exp の $join";
  }
  # (i) jh 見出し (ds8 ceiling 是正・第4の可視 cross-doc echo): <b> 無し平文・可視テキスト全体が固定テンプレと一致。
  while (/<(\w+)\b[^>]*\bclass="jh"[^>]*>(.*?)<\/\1>/gs) {
    my $in=$2; my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"jh:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"jh:VIS" if $vis ne "この判断が正当化する要件 (cross-doc 照会 \x{2192} $exp)";
  }
  # (j) 照会先 footnote justify-tgt: <b> 無し・平文ゆえ可視テキスト全体が固定テンプレと一致
  while (/<(\w+)\b[^>]*\bclass="justify-tgt"[^>]*>(.*?)<\/\1>/gs) {
    my $in=$2; my @bs=$in=~/<b>([^<]*)<\/b>/g;
    if (@bs!=0){push @bad,"justify-tgt:".scalar(@bs)."B"; next}
    my $vis=$in; $vis=~s/<[^>]+>//g; push @bad,"justify-tgt:VIS" if $vis ne "照会先: $exp \x{2014} $title";
  }
  # (k) within-doc 可視 req == data-justifies-req (attr-vs-visible 厳密一致。 可視 req だけ改竄し attr 温存を封鎖。
  #     marker-keyed: class="justify-req" を担持する任意タグを捕捉・justify-req span 内は req id のみ = [^<]* で安全に抽出)。
  while (/<(\w+)\b[^>]*\bclass="justify-req"[^>]*\bdata-justifies-req="([^"]*)"[^>]*>([^<]*)<\/\1>/gs) {
    my ($attr,$vis)=($2,$3); push @bad,"justify-req:$attr\x{2260}$vis" if $vis ne $attr;
  }
  print join(" ", @bad);
' "$BODY")"
chk_empty "cross-doc: 可視 echo == テンプレ+id(+title)・req attr==可視 (marker-keyed・swap/平文/タグ併記封鎖)" "$adr_echo_bad"

# 4. verdict 整合 (chosen ちょうど 1 + decision.chosen 一致)
chk "verdict=chosen はちょうど 1 件" "1" "$(q '[.options[] | select(.verdict=="chosen")] | length')"
chk "decision.chosen == verdict=chosen option" "$(q '[.options[] | select(.verdict=="chosen")][0].id // "MISSING"')" "$(q '.decision.chosen')"
# HTML 側: opt-verdict.chosen の数 (可視 verdict 捏造検出)
chk "HTML chosen バッジ == 1" "1" "$(grep -oE 'class="opt-verdict chosen"' "$BODY" | wc -l | tr -d ' ')"
# ★(opt-id, verdict) ペア一致: どの card が chosen/rejected/deferred かを contract と突合
#   (count 保存型のバッジ付け替え = 採用カードの偽装を捕捉。 総数 1 だけでは fail-open)。
exp_ov="$(q '.options[] | [.id, .verdict] | @tsv' | sort -u)"
act_ov="$(grep -oE '<span class="opt-id">[^<]+</span><span class="opt-name">.*</span><span class="opt-verdict [a-z]+"' "$BODY" \
  | sed -E 's#<span class="opt-id">([^<]+)</span>.*<span class="opt-verdict ([a-z]+)"#\1\t\2#' | sort -u)"
set_eq "HTML (opt-id, verdict) ペア (contract == HTML)" "$exp_ov" "$act_ov"
# ★(verdict, 可視ラベル) ペア一致: バッジの human-visible 文字 (採用/不採用/保留) が verdict と整合する
#   (非エンジニアが実際に読むのは class でなく可視文字。 class は正のまま可視ラベルだけ改竄する偽装は
#    上の (opt-id,verdict) class 突合を素通り = fail-open。 VERDICT_LABEL 相当を突合して捕捉する)。
exp_vl="$(printf 'chosen\t採用\nrejected\t不採用\ndeferred\t保留\n' | sort)"
act_vl="$(grep -oE '<span class="opt-verdict [a-z]+">[^<]*</span>' "$BODY" \
  | sed -E 's#<span class="opt-verdict ([a-z]+)">([^<]*)</span>#\1\t\2#' | sort -u)"
# HTML に出た各 verdict class が正しい可視ラベルを持つことを要求 (HTML 側 ⊆ 期待マップ)。
bad_vl="$(comm -13 <(printf '%s\n' "$exp_vl") <(printf '%s\n' "$act_vl") | tr '\t' '=' | tr '\n' ' ' | sed 's/ *$//')"
chk_empty "HTML verdict バッジの可視ラベルが verdict と整合" "$bad_vl"

# 4b. supersession / principle (assembler が emit する終端章。 fabrication-free を emit 全章へ拡張)
#     これらが構造検証外だと principle.id 改竄・supersession.status 偽装・supersedes 捏造が fail-open になる
#     (SRS-pack の verify-fabrication-free と「同型」を謳う以上、 emit する全章は contract 導出を証明する)。
chk "adr-supersession ブロック == 1"       "1" "$(grep -c 'data-component="adr-supersession"' "$BODY")"
chk "adr-principle ブロック == 1"          "1" "$(grep -c 'data-component="adr-principle"' "$BODY")"
# (b) principle.id == contract .principle.id (照会終端の identity 偽装を捕捉)
act_prin="$(grep -oE '<p class="prin-id">[^<]*</p>' "$BODY" | sed -E 's#.*— ([^<]*)</p>#\1#')"
chk "principle.id == contract .principle.id" "$(esc "$(q '.principle.id')")" "$act_prin"
# (c) supersession.status == contract .supersession.status (改訂状態の偽装を捕捉)
act_ss="$(grep -oE '<p class="ss-row"><span class="ss-k">改訂状態</span>[^<]*</p>' "$BODY" | sed -E 's#.*改訂状態</span>([^<]*)</p>#\1#')"
chk "supersession.status == contract .status" "$(esc "$(q '.supersession.status')")" "$act_ss"
# (d) supersedes / superseded_by の内容一致 (捏造リンクを捕捉。 空は assembler の「なし」sentinel と突合)
sup_n="$(q '.supersession.supersedes | length')"; superby_n="$(q '.supersession.superseded_by | length')"
exp_sup="$([[ "$sup_n" -gt 0 ]] && q '.supersession.supersedes | join(", ")' || echo "なし (新規)")"
exp_superby="$([[ "$superby_n" -gt 0 ]] && q '.supersession.superseded_by | join(", ")' || echo "なし (現行)")"
act_sup="$(grep -oE '<p class="ss-row"><span class="ss-k">置き換える ADR</span>[^<]*</p>' "$BODY" | sed -E 's#.*ADR</span>([^<]*)</p>#\1#')"
act_superby="$(grep -oE '<p class="ss-row"><span class="ss-k">置き換えられた</span>[^<]*</p>' "$BODY" | sed -E 's#.*置き換えられた</span>([^<]*)</p>#\1#')"
chk "supersession.supersedes == contract"     "$(esc "$exp_sup")"    "$act_sup"
chk "supersession.superseded_by == contract"  "$(esc "$exp_superby")" "$act_superby"

# 5. escape 健全性
chk "back-ref 化け entity なし (<lt; 等)" "0" "$(grep -oE '<(lt|gt|quot);' "$BODY" | wc -l | tr -d ' ')"
chk "null セル漏れなし" "0" "$(grep -oE '>null<' "$BODY" | wc -l | tr -d ' ')"

# 6. prose スロット (perl で要素単位判定)
slots="$(grep -oE 'data-prose-slot=' "$BODY" | wc -l | tr -d ' ')"
filled="$(perl -0777 -ne 'my $c=0; while (/<([a-zA-Z]+)\b[^>]*\bdata-prose-slot="[^"]*"[^>]*>(.*?)<\/\1>/gs){ my $i=$2; $i=~s/\s+//g; $c++ if length($i); } print $c;' "$BODY")"
if [[ "$slots" -gt 0 ]]; then printf '  [OK]   %-48s %s\n' "prose スロット存在" "$slots"; else printf '  [FAIL] %-48s\n' "prose スロットが無い"; fail=1; fi

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
    printf '  [OK]   %-48s %s\n' "全スロット注入忠実 (内容==escape済 manifest)" "$(grep -c . "$exp")"
  else
    printf '  [FAIL] %-48s\n' "注入不一致 (slot-id 集合差 or 内容改竄)"
    echo "    --- manifest 期待のみ ---"; comm -23 "$exp" "$act" | sed 's/^/      /'
    echo "    --- HTML 実体のみ ---";     comm -13 "$exp" "$act" | sed 's/^/      /'
    fail=1
  fi
  rm -f "$exp" "$act"
fi

# 7. plain-language-term-inline fidelity + 用語被覆 (assemble-adr と同一語境界規律)。
#    実装は core (verify-common.sh の verify_term_inline)。 markable フィールド集合は ADR-pack 固有ゆえ
#    ここで yq 式を渡す (★この yq リストは assemble-adr の mark_terms 呼出先と二重保守。 detect↔remediate parity)。
verify_term_inline \
  '.context[].summary, .context[].detail, .drivers[].driver, .options[].name, .options[].summary, .options[].pros[], .options[].cons[], .decision.statement, .decision.justifies[].note, .consequences.positive[].text, .consequences.negative[].text, .supersession.note, .principle.text, .principle.note' \
  "term-inline 被覆 (マーク == markable 出現 glossary 語)"

echo
if [[ "$fail" -eq 0 ]]; then
  if [[ -n "$ARTIFACT" ]]; then echo "RESULT: artifact PASS (構造 fabrication-free + cross-doc 照会解決 + term-inline + prose 全充填)"
  elif [[ -n "$FILLED_MANIFEST" ]]; then echo "RESULT: filled PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 注入忠実)"
  else echo "RESULT: fabrication-free PASS (構造 contract 完全導出・捏造 0 + cross-doc 照会解決 + prose 空)"; fi
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
