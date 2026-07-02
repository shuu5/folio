#!/usr/bin/env bash
# folio verify-srs — 生成 SRS プレゼン HTML の *決定的 floor* (taxonomy §5.2: gate A-H + visual-first)。
#
# 生成と検証を分離した独立検証 (consumer が生成物を手編集しても再検証できる)。 入力は (contract, html) のみ
# = manifest 不要 (生成時の注入忠実は verify-fabrication-free --filled が別途担う)。
#
# taxonomy §5.2 への忠実な実装 (gate letter は taxonomy 定義に一致):
#   gate A  MUST 部品存在     : §3 MUST 部品の S5 凍結 required-existence 集合を各 1 個以上 (data-component)
#   gate B  register 整合     : deck-band family ≥1 + dense系 ≥1 + requirement-type-color-tokens + prefers-color-scheme 両モード
#   gate C  RTM 完全性        : 孤立要件 (出所なし) =0 かつ 未検証要件 (受入なし) =0 (RTM 集合一致は verify-fab が担保)
#   gate D  要件 ID 健全性    : 一意 data-req-id (重複0) + 全要件行に priority-badge + 検証手法 (T/A/I/D)
#   gate E  用語被覆          : term-inline (plain-language-term-inline) が glossary から正確に派生 = verify-fab §9 が担保
#   gate F  render 健全性     : render-gate-srs.py (playwright・light/dark × 3 viewport) で low-contrast /
#                               horizontal-overflow / component-overlap を検出。 renderer 在環境で実行し、
#                               不在環境では honest SKIP (PASS と詐称しない・floor 不完全と明示)。
#   gate F2 描画後 content    : render-gate-srs.py --census (gate F の sibling・folio-6jb 縦軸)。 静的 floor を
#           (census)            素通りする render 依存の捏造 (pseudo-content 2b8) / 隠蔽 (描画後 omission 459) を、
#                               contract 由来期待件数 + semantic セレクタ pseudo-content 不変条件で検出。 honest SKIP は gate F と独立。
#                               ★境界 (verification §3.9): gate F2 の全 class は warn 級 backstop (非 blocking)。
#   census-count (blocking arm): 計数部品の source DOM 静的件数 == contract 期待件数 (ears-requirement-row ==
#                               .requirements 数 ∧ nfr-metric-row == .nfr 数 ∧ .plain == .requirements + .nfr・
#                               render を要さない算術照合、 REQ-VER-024 blocking arm)。
#   gate G  内容完全性(no-TBD): MUST 部品の必須スロット非空 (verify-fab --artifact) + placeholder トークン (TBD/未定 等) =0
#   gate H  fidelity meta     : fidelity-sync-meta の 3 項目が *非空白* で埋まる
#   visual-first              : 各章 (footer 除く) に非 prose 部品が ≥1 (字だけの章 =0)
#
# ★機械/LLM 検証境界 (verification §3.9・REQ-VER-024/027/028 = SSoT): blocking arm = gate A–E,G,H + visual-first +
#   census-count (+ gate F render 健全性 = REQ-VER-025)。 静的 hidden-render ban 群 (script/template/nested-context/
#   inline-only/scroll-pseudo/list-marker) と visual-deception ban (unicode/bidi-override)・gate F2 render census の
#   全 class は fabrication-free-by-construction (rules §12) で構成上排除済の脅威を再検査する warn 級 backstop
#   (非 blocking・honest-bug の実捕捉は warn 報告で維持)。 捏造の意味権威は ceiling gate J・可読性は gate I。
#
# ★floor 通過しても GREEN を宣言しない: ceiling=PENDING を返す (taxonomy §5.1「floor 単独 GREEN 禁止」)。
#   GREEN ⟺ (blocking floor 全通過) AND (ceiling 合格)。 ceiling = persona-walk-srs + fidelity-srs + completeness-critic-srs (S5.2 + mzn.1.2)。
#   exit 0 は「floor PASS」を意味し「GREEN」ではない (caller は exit 0 を GREEN に流用してはならない)。
#
# usage: verify-srs.sh <contract.yaml> <generated.html>
# exit:  0 = blocking arm PASS (ceiling PENDING・warn 級 backstop 指摘は exit を上げない) / 1 = floor FAIL /
#        2 = tool error (入力不正 + 測定系 tool-integrity error 〔gate F2 の T7 render 破綻 等〕 = gate 判定と別軸)

set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VFAB="$SCRIPT_DIR/verify-fabrication-free.sh"
CONTRACT="${1:?usage: verify-srs.sh <contract.yaml> <generated.html>}"
HTML="${2:?usage: verify-srs.sh <contract.yaml> <generated.html>}"
[[ -f "$CONTRACT" && -f "$HTML" ]] || { echo "verify-srs: input not found" >&2; exit 2; }
[[ -f "$VFAB" ]] || { echo "verify-srs: verify-fabrication-free.sh not found" >&2; exit 2; }
command -v yq >/dev/null || { echo "verify-srs: yq required" >&2; exit 2; }

# ---- core 共通層 (q/esc/chk/chk_empty/set_eq/make_body/verify_term_inline)。 chk 整列幅は %-50s ----
# 新依存 lib/verify-common.sh は $VFAB と同じ流儀で fail-closed guard する (欠落/source 失敗を
# false-green に倒さない。 set -e 無しゆえ source rc=1 でも継続し helper が command-not-found 化する)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-srs: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=50; source "$LVC" || { echo "verify-srs: failed to source verify-common.sh" >&2; exit 2; }
fail=0
# ---- warn 級 backstop (verification §3.9 境界・REQ-VER-024/027/028)。 fabrication-free-by-construction
#      (rules §12) で構成上排除済の脅威を再検査する決定的機構は blocking しない — honest-bug の実捕捉は
#      warn 報告で維持し、 意味権威は ceiling (gate I/J) に置く。 warn は exit を上げない (blocking arm と別軸)。
#      測定系 tool-integrity error (gate F2 の T7 render 破綻 等) は warn とも blocking とも別軸で exit 2。 ----
warnN=0; toolerr=0
wchk() { # label expected actual — warn 級 backstop 版 chk (非 blocking・warnN 加算のみ)
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "$1" "$2"
  else printf '  [WARN] %-'"$CHKW"'s expected %s, got %s (warn 級 backstop・非 blocking)\n' "$1" "$2" "$3"; warnN=$((warnN+1)); fi
}
make_body "$HTML"        # body-only ($BODY、 CSS セレクタ混入回避)
has() { local c; c="$(grep -c "data-component=\"$1\"" "$BODY")"; [[ "$c" -ge 1 ]] && echo 1 || echo 0; }

# ---- render census 語彙 SSoT (folio-hef.3)。 起動時に *pack-level yq* で読み (graph-common.sh core reader
#      流用せず = lib/ 無改変)、 件数注入機構の拡張として gate F2 census の probe payload (expect.vocab) へ
#      carry する。 S4 (folio-hef.4) の closure 判定 (描画要素 ↔ 期待要素の全単射) が消費する基盤。 本 slice は
#      配線のみ (bijection 本体は S4)。 fail-closed: 不在/data_components 空は tool error (誤 green に倒さない)。 ----
CENSUS_VOCAB="$SCRIPT_DIR/rolemap/srs.census-vocab.yaml"
[[ -f "$CENSUS_VOCAB" ]] || { echo "verify-srs: census-vocab not found: $CENSUS_VOCAB" >&2; exit 2; }
[[ "$(yq -r '.data_components // [] | length' "$CENSUS_VOCAB" 2>/dev/null)" -ge 1 ]] \
  || { echo "verify-srs: census-vocab の .data_components が空/不正: $CENSUS_VOCAB" >&2; exit 2; }
CENSUS_VOCAB_JSON="$(yq -o=json -I=0 '{"pack": .pack, "data_components": .data_components, "prose_slots": .prose_slots, "recognized_classes": .recognized_classes}' "$CENSUS_VOCAB")" \
  || { echo "verify-srs: census-vocab を JSON 化できない: $CENSUS_VOCAB" >&2; exit 2; }

echo "=========================================================================="
echo "folio verify-srs — 生成 SRS プレゼン floor (taxonomy §5.2 gate A-H + visual-first)"
echo "  html:     $HTML"
echo "  contract: $CONTRACT"
echo "=========================================================================="
echo "--- 構造証明 (行数=contract導出 / gate E 用語被覆=term-inline / RTM 集合一致 / prose 充填) = verify-fabrication-free --artifact ---"
if bash "$VFAB" --artifact "$CONTRACT" "$HTML"; then :; else fail=1; fi

echo
echo "--- gate A: MUST 部品存在 (S5 凍結 required-existence 集合・各 ≥1) ---"
# 凍結集合 = この generator が *完全な SRS contract* に対し決定的に出力する MUST 部品 (taxonomy §3 MUST 行のうち assembler 出力分)。
# 条件付き MUST (interface-spec-table / ui-spec-block 等) と未出力 MUST (revision-history-table 等) は本集合に含めない (MUST-when-applicable)。
GATE_A_MUST=(doc-cover-band requirement-type-color-tokens chapter-deck-band section-lead-callout
  scope-summary-panel actor-stakeholder-table source-trace-origin requirement-matrix-table
  ears-requirement-row priority-badge nfr-hero-metrics nfr-metrics-table acceptance-criteria-checklist
  rtm-collapse constraint-callout glossary-term-table fidelity-sync-meta)
for comp in "${GATE_A_MUST[@]}"; do chk "gate A: $comp 存在" 1 "$(has "$comp")"; done

echo
echo "--- gate B: register 整合 ---"
chk "gate B: deck-band family (chapter-deck-band) ≥1" 1 "$(has chapter-deck-band)"
# dense 系 = 高密度 register (表/グリッド) のいずれか
denseN=0; for d in requirement-matrix-table nfr-metrics-table rtm-grid actor-stakeholder-table; do [[ "$(has "$d")" == 1 ]] && denseN=$((denseN+1)); done
chk "gate B: dense系部品 ≥1" 1 "$([[ "$denseN" -ge 1 ]] && echo 1 || echo 0)"
chk "gate B: requirement-type-color-tokens 参照基底 存在" 1 "$(has requirement-type-color-tokens)"
# dark media 定義 (light=既定)。 CSS コメント擬装 (/* prefers-color-scheme: dark */) を弾くため、 文字列でなく
# @media 規則ブロックの存在を要求 (@media ... prefers-color-scheme: dark)。 BODY は <style> 除去済ゆえ HTML 全体を見る。
chk "gate B: @media(prefers-color-scheme:dark) 規則 (light=既定)" 1 "$(grep -qzP '@media[^{]*prefers-color-scheme:\s*dark' "$HTML" && echo 1 || echo 0)"

echo
echo "--- gate C: RTM 完全性 (孤立0 / 未検証0) ---"
chk "gate C: 孤立要件 (出所なし) == 0" 0 "$(q '[(.requirements + .nfr)[] | select((.trace.backward | length)==0)] | length')"
chk "gate C: 未検証要件 (受入なし) == 0" 0 "$(q '[(.requirements + .nfr)[] | select((.trace.acceptance | length)==0)] | length')"

echo
echo "--- gate D: 要件 ID 健全性 (一意 data-req-id + priority-badge + T/A/I/D) ---"
reqrows="$(grep -c 'data-component="ears-requirement-row"' "$BODY")"
mapfile -t REQIDS < <(grep -oE 'data-req-id="[^"]*"' "$BODY" | sed 's/.*data-req-id="//; s/"$//')
chk "gate D: data-req-id 数 == 要件行数" "$reqrows" "${#REQIDS[@]}"
chk "gate D: data-req-id 重複 == 0" 0 "$(printf '%s\n' "${REQIDS[@]}" | sort | uniq -d | grep -c .)"
chk "gate D: 全要件行に priority-badge" "$reqrows" "$(grep 'data-component="ears-requirement-row"' "$BODY" | grep -c 'data-component="priority-badge"')"
chk "gate D: 全要件行に検証手法 (T/A/I/D) span" "$reqrows" "$(grep 'data-component="ears-requirement-row"' "$BODY" | grep -cE 'class="vmeth">[TAID]<')"
chk "gate D: contract 全要件/NFR の vmethod ∈ {T,A,I,D}" 0 "$(q '[(.requirements + .nfr)[] | select((.vmethod // "") | test("^[TAID]$") | not)] | length')"
# 可視 fid span == 同行 data-req-id (手編集での可視 ID 捏造を検出)
chk "gate D: 可視 fid == data-req-id (id 乖離なし)" 0 "$(perl -ne 'while(/data-component="ears-requirement-row" data-req-id="([^"]*)".*?<span class="fid">([^<]*)<\/span>/g){ print "x\n" if $1 ne $2; }' "$BODY" | wc -l | tr -d ' ')"

echo
echo "--- navigable anchor (folio-lzz: cross-doc deep-link 着地点・案A 裸ミラー) ---"
# referenceable node (要件/NFR/受入) が data-*-id をミラーした navigable id= を出す = arch referrer の
# #FR*/#NFR*/#AC* が実際に着地する前提 (案A)。 id は当該 component 要素から *space-anchored* (' id="') で
# scoped 抽出する (data-req-id / data-slot-id 等の部分一致や body chrome id を巻き込まない)。 set_eq で
# contract node 集合と emission 順一致を要求 = id 脱落 (anchor 不在=404 復活) / 値ミラー不一致 / 偽 id 注入を一括封鎖。
req_nav="$(grep 'data-component="ears-requirement-row"' "$BODY" | grep -oE ' id="[^"]*"' | sed 's/^ id="//; s/"$//')"
set_eq "anchor: 要件 navigable id == contract req id" "$(q '.requirements[].id')" "$req_nav"
nfr_nav="$(grep 'data-component="nfr-metric-row"' "$BODY" | grep -oE ' id="[^"]*"' | sed 's/^ id="//; s/"$//')"
set_eq "anchor: NFR navigable id == contract nfr id" "$(q '.nfr[].id')" "$nfr_nav"
ac_nav="$(grep 'class="ac"' "$BODY" | grep -oE ' id="[^"]*"' | sed 's/^ id="//; s/"$//')"
set_eq "anchor: 受入 navigable id == contract acceptance id" "$(q '.acceptance[].id')" "$ac_nav"
# ★folio-lzz ceiling [必須-1]: navigable id は body 全体で一意 (collision=0)。 上の set_eq は component 行しか見ないため、
#   非 component 要素 (cover 付近の空 <a id="FR2"> 等) へ同 id を注入すると set_eq PASS のまま fragment 解決が tree-order 先頭の
#   偽要素へ着地する fail-open があった (verify-adr の uniqueness を SRS が欠いていた)。 id 属性を *attribute-name 境界* ((?<![\w-])(?i:id) で
#   data-req-id / data-slot-id 〔直前ハイフン〕を除外しつつ、 whitespace と HTML5 self-closing slash 〔<a/id=…〕 区切りの両方を捕捉) かつ
#   *quote/entity/case/unquoted-robust* (count_attr_token と同規律・ceiling round-2 が slash separator を追加封鎖) に全列挙し重複 0 を要求。
allids_dup="$(perl -CSD -0777 -ne 'my $q=chr(39); while (/(?<![\w-])(?i:id)\s*=\s*(?:"([^"]*)"|$q([^$q]*)$q|([^\s>]+))/g){ my $v=defined $1?$1:(defined $2?$2:$3); $v=~s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge; $v=~s/&#(\d+);?/chr($1)/ge; print "$v\n"; }' < "$BODY" | LC_ALL=C sort | LC_ALL=C uniq -d | grep -c .)"
chk "anchor: navigable id は body 全体で一意 (collision=0・quote/entity/case-robust)" 0 "$allids_dup"

echo
echo "--- census-count (REQ-VER-024 blocking arm): 計数部品の source DOM 静的件数 == contract 期待件数 ---"
# 機械/LLM 境界 (verification §3.9) の blocking 件数照合: render を要さない算術照合のみを floor が裁く
# (実描画・可視性の照合は gate F2 render census = warn 級 backstop と ceiling の領分)。 count_attr_token
# (quote 構文・属性名 case・数値文字参照 非依存の occurrence 数え = VFAB 占有 pin r7 と同規律) で数える —
# quoted-literal grep だと unquoted 属性 (browser は描画する) の偽部品 add を見逃すため。 make_body は
# <script> 中身を verbatim 保持するため、 <script> 内へ退避した偽計数部品も excess としてここで数える
# (静的 fail-closed)。 HTML コメント内も verbatim 保持で数える = comment 隠蔽は静的件数を変えず render
# census (warn) の領分という分界に一致。 占有 pin (bur) の将来 de-scope 時も本 arm が同強度で件数照合を継承する。
cc_req="$(count_attr_token "data-component" "ears-requirement-row" < "$BODY")"
cc_nfr="$(count_attr_token "data-component" "nfr-metric-row" < "$BODY")"
cc_plain="$(count_attr_token "class" "plain" < "$BODY")"
CC_REQN="$(q '.requirements | length')"; CC_NFRN="$(q '.nfr | length')"
chk "census-count: ears-requirement-row == contract .requirements 数" "$CC_REQN" "$cc_req"
chk "census-count: nfr-metric-row == contract .nfr 数" "$CC_NFRN" "$cc_nfr"
chk "census-count: .plain == .requirements + .nfr" "$((CC_REQN + CC_NFRN))" "$cc_plain"

echo
echo "--- gate G: 内容完全性 (no-TBD placeholder)。 prose 全充填は --artifact 済 ---"
# placeholder トークンを *本文全体* で語境界マッチ (セル先頭に限らず prose 中段の TBD も捕捉)。
# 語境界 = 前後が letter/number (\p{L}\p{N}) でない位置。 これで「TODOリスト管理」「未定義」「XXXL」等の語内包含は
# 誤検出せず、 任意の句読点・空白・要素境界に接する placeholder のみ捕捉する (allowlist でなく negative 境界 = 網羅的)。
ghits="$(perl -CSD -Mutf8 -0777 -ne 'my $c = () = /(?<![\p{L}\p{N}])(TBD|TODO|FIXME|TBA|TBC|XXX|未定|未記入|要追記|要確認)(?![\p{L}\p{N}])/gi; print $c;' < "$BODY")"
chk "gate G: placeholder トークン (TBD/未定 等・語境界) == 0" 0 "$ghits"

echo
echo "--- gate H: fidelity-sync-meta (機械SSoT/検証状態=厳密一致・生成=timestamp 非空) ---"
chk "gate H: sync-meta 部品 存在" 1 "$(has fidelity-sync-meta)"
# ★ds8 ceiling round-2: footer (fidelity-sync-meta) の sync-meta div を *ブロックごと* 捕捉し、全タグ除去後の可視テキストが
#   固定テンプレ (機械SSoT=basename / 生成=timestamp / 検証状態=固定2状態) と厳密一致を要求する。 値 (<b> 内) のみ照合だと
#   </b> 外・</div> 前への可視追記 (偽『全 gate GREEN・出荷承認』等) が死角になる fail-open だった (round-1 の value-only 照合の穴)。
#   block-scoped で value-tamper + </b>外追記 + sibling div + 欠落 を一括封鎖 (cross-doc echo の可視テキスト厳密一致と同規律を footer へ)。
#   生成 (timestamp) のみ非決定的ゆえ \d{4}-\d\d-\d\d \d\d:\d\d の placeholder で許容、 残り (basename/区切り/検証状態) は厳密一致。
gH_ssot_e="$(esc "${CONTRACT##*/}")"
gH_bad="$(SSOT="$gH_ssot_e" \
  STPRE='structure ✓ fabrication-free / prose 未充填 (opus 待ち)' \
  STPOST='structure ✓ fabrication-free / prose ✓ 充填済 (fidelity ceiling → S5 対象)' \
  perl -CSD -Mutf8 -0777 -ne '
  my $ssot=$ENV{SSOT}; utf8::decode($ssot);
  my $pre=$ENV{STPRE}; utf8::decode($pre); my $post=$ENV{STPOST}; utf8::decode($post);
  my @bad; my $n=0;
  while (/<div>機械SSoT:(.*?)<\/div>/gs) {
    my $in=$1; $n++;
    push @bad,"sync-meta:NESTED" if $in=~/<div\b/;
    my $vis="機械SSoT:".$in; $vis=~s/<[^>]+>//g;
    unless ($vis=~/^機械SSoT: \Q$ssot\E &middot; 生成: \d{4}-\d\d-\d\d \d\d:\d\d &middot; 検証状態: (.*)$/) { push @bad,"sync-meta:VIS"; next; }
    my $state=$1; push @bad,"検証状態\x{2260}固定2状態" if ($state ne $pre && $state ne $post);
  }
  push @bad,"sync-meta:count=$n" if $n!=1;
  print join(" ", @bad);
' < "$BODY")"
chk_empty "gate H: sync-meta 可視テキスト == テンプレ (basename/ts/固定2状態・</b>外追記封鎖)" "$gH_bad"

echo
echo "--- visual-first: 各章 (footer 除く) に非 prose 部品 ≥1 ---"
vf="$(perl -0777 -ne '
  s{<footer\b.*?</footer>}{}gs;   # footer (fidelity-sync-meta) を章セグメントから除外
  my @seg = split(/(?=<section data-component="chapter-deck-band")/, $_); shift @seg;
  my $bad=0;
  for my $s (@seg) {
    my $has=0;
    while ($s =~ /data-component="([^"]+)"/g) {
      my $c=$1; next if $c eq "chapter-deck-band" || $c eq "plain-language-term-inline" || $c eq "priority-badge";
      $has=1; last;
    }
    $bad++ unless $has;
  }
  print $bad;
' "$BODY")"
chk "visual-first: 字だけの章 (非prose部品なし) == 0" 0 "$vf"

echo
echo "--- script-ban (warn 級 backstop・非 blocking): SRS HTML は <script> ゼロ (4gz render-time DOM-swap / 459 script-container OMISSION の静的検出) ---"
# SRS は <script> を一切 emit しない (verified)。 ゆえに任意の <script> は捏造コンテナ = (a) 検証通過後に
# innerHTML/insertAdjacentHTML で genuine な要件/承認/章を捏造差替えする render-time DOM-swap (folio-4gz)、
# (b) 必須要素を <script> で包み静的 grep を素通しつつブラウザ非描画にする OMISSION (folio-459 script-container)。
# render を要さず pack-additive 静的 invariant (この doc-type の HTML は <script>==0) で原理封鎖する
# (render census でなく静的 floor・render ゼロコスト・script-free 5 pack 共通の fab-free invariant の SRS 適用)。
# raw $HTML を case-insensitive・タグ境界 (\b) で count (head/body 双方を被覆・make_body の body-only view に依存しない)。
scriptN="$(perl -0777 -ne 'my $n = () = /<script\b/gi; print $n+0;' "$HTML")"
wchk "script-ban: <script> 出現 == 0 (4gz/459-script 静的検出)" 0 "$scriptN"

echo
echo "--- template-ban (warn 級 backstop・非 blocking): SRS HTML は <template> ゼロ (FF5 declarative shadow DOM census-blindness の静的検出・folio-hef S1) ---"
# <template shadowrootmode> は parse 時に declarative shadow DOM を生成し、 shadow tree 内に注入した偽要件が
# 描画されつつ document.querySelectorAll (census) も host.textContent (fidelity ceiling) も shadow 境界を貫通
# しない両盲点を作る (round2 FF5 e10)。 SRS は <template> を一切 emit しない (verified: ec-checkout / clinic とも 0)
# ゆえ、 script-ban と同型の pack-additive 静的 invariant (この doc-type の HTML は <template>==0) で render を
# 要さず原理封鎖する。 ★shadowrootmode 属性を狙う narrow regex (/<template[^>]*shadowrootmode/) は negated class
# [^>]* が *クォート属性値内の '>'* (例 <template data-x="a>b" shadowrootmode>) で停止し素通りした (独立 ceiling
# wf_b544a704 が chromium で shadow DOM 生成を実証)。 raw HTML の negated-class quantifier は quoted value 内の
# '>' を考慮できない (ceiling-recursive 教訓) ため、 whole-tag <template> ban に転換する: 全属性レベル回避
# (quoted-'>' / legacy shadowroot 属性名 / 将来の宣言的 shadow 綴り) を一括封鎖し strictly stronger・FP-free。
shadowN="$(perl -0777 -ne 'my $n = () = /<template\b/gi; print $n+0;' "$HTML")"
wchk "template-ban: <template> 出現 == 0 (FF5 declarative shadow DOM 静的検出・whole-tag ban)" 0 "$shadowN"

echo
echo "--- nested-context-ban (warn 級 backstop・非 blocking): SRS HTML は nested browsing context ゼロ (FF5-sibling census-blindness の静的検出・folio-hef S1 ceiling round-2) ---"
# <iframe srcdoc> / <object data=data:text/html> / <embed> / <frame> / <frameset> / <portal> は nested browsing
# context を作り、 その中に注入した偽要件が render 可視だが census (document.querySelectorAll) も fidelity ceiling
# (main-doc textContent) も境界を貫通できない盲点を作る (declarative shadow DOM = <template> と全く同じ脅威クラス・
# 独立 ceiling wf_0900ca71)。 SRS は自己完結 inline HTML ゆえ nested browsing context を一切 emit しない
# (verified: ec-checkout / clinic とも iframe=object=embed=0) = template-ban と同型の pack-additive 静的 invariant。
# \b 境界ゆえ class/属性値の 'object'/'embed' 部分文字列でなく tag 開始のみ照合 (case-insensitive・-0777 slurp)。
nbcN="$(perl -0777 -ne 'my $n = () = /<(?:iframe|object|embed|frame|frameset|portal)\b/gi; print $n+0;' "$HTML")"
wchk "nested-context-ban: <iframe|object|embed|frame|frameset|portal> 出現 == 0 (FF5-sibling census-blindness 静的検出)" 0 "$nbcN"

echo
echo "--- inline-only-ban (warn 級 backstop・非 blocking): SRS HTML は inline-HTML + geometric SVG 以外の hidden-render 機構ゼロ (FF5 census/fidelity 両盲点の doc-type 不変条件検出・folio-hef S1 ceiling round-3・user 案A) ---"
# ★doc-type 不変条件: SRS は自己完結 inline HTML + geometric SVG icon (path/circle/rect 等) のみで構成され、
# 画像サブリソース (<img> / svg <image> / data: URI / background-image:url) ・media (<canvas>/<video>/<audio>) ・
# form control (<input>/<textarea>/<select>/<button>) を一切 emit しない (verified: ec-checkout / clinic とも 0)。
# これらは reader に content を描画するが document.body.textContent にも querySelectorAll にも現れない census/
# fidelity 両盲点を作る (data: 画像に偽要件テキストを base64 で埋め込む等・独立 ceiling wf_4b5bffa2 が実描画実証)。
# template-ban / nested-context-ban と同型の closed-set 静的 invariant (genuine vocabulary の補集合 ban・FP-free・
# strictly stronger)。 exotic な font-substitution 等 reader-facing 字形改竄は floor 射程超ゆえ LLM ceiling backstop。
# <image\b は svg <image> (HTML <img> は <img\b)・\b 境界ゆえ class/属性値の部分文字列でなく tag 開始のみ照合。
# round-3e ceiling: <progress>/<meter> の ::-webkit-progress-bar / ::-webkit-progress-value / ::-webkit-meter-* は background-image を
# 実描画するが getComputedStyle が 'none' を返すため render census が構造的に盲 (pe 拡張 no-op)。 form-associated 要素閉包の欠落補完
# として静的タグ ban へ追加する (genuine SRS は progress/meter=0・verified)。
hrenN="$(perl -0777 -ne 'my $n = () = /<(?:img|image|canvas|video|audio|input|textarea|select|button|progress|meter)\b/gi; print $n+0;' "$HTML")"
wchk "inline-only-ban: <img|image|canvas|video|audio|input|textarea|select|button|progress|meter> 出現 == 0 (FF5 hidden-render 検出)" 0 "$hrenN"
# data: URI は (a) <img|image|video|audio> 等の src/href (上の tag-ban で封鎖済) と (b) CSS url() の両経路で hidden-render する。
# 生 /data:/ grep は脆い: (1) prose の 'metadata:' を誤検出 (FP) (2) HTML char-ref (data&#58;/data&colon;/data&#x3a;) を
# style/属性値に置くと parser が grep の *後* に ':' へ decode し素通る (独立 ceiling wf_3652702e が実描画実証)。ゆえに
# CSS resource sink 自体を狙う: url( が #fragment 内部参照以外 (= scheme 付き外部/data:) を指すものを ban する。
# genuine SRS は url() を一切使わない (verified 0・url(#gradient-id) 内部参照のみ将来許容) ゆえ url(#…) だけ通すのは
# FP-free かつ char-ref 非依存 (url( token と直後の非 '#' は raw HTML に literal で残り decode 不要)。[\x22\x27]=" '。
urlN="$(perl -0777 -ne 'my $n = () = /url\(\s*[\x22\x27]?(?!#)/gi; print $n+0;' "$HTML")"
wchk "inline-only-ban: url(#fragment 以外) 出現 == 0 (FF5 CSS resource sink hidden-render 検出・char-ref robust)" 0 "$urlN"

echo
echo "--- scroll-pseudo-ban (warn 級 backstop・非 blocking): generated-content scroll pseudo ゼロ (::scroll-button / ::scroll-marker / scroll-marker-group・round-3c carve agent 実証) ---"
# ::scroll-button(dir){content:…} / ::scroll-marker{content:…} は CSS generated-content pseudo で偽要件を可視描画するが
# 旧 census は ::before/::after/::marker のみ走査した盲点だった (carve agent: census exit0 で FR99/FR98 が可視・
# fidelity textContent も blind)。 census 側を ::scroll-button(dir)/::scroll-marker 走査へ拡張済 (computed-style ゆえ
# CSS escape も正規化済の render 側 robust 一次防御)。 本静的 ban は render 不在環境向けの literal-spelling backstop
# (genuine SRS は scroll container を一切使わない・verified 0 = script-ban 同型の genuine vocabulary 補集合)。
spseudoN="$(perl -0777 -ne 'my $n = () = /scroll-(?:button|marker)/gi; print $n+0;' "$HTML")"
wchk "scroll-pseudo-ban: scroll-button/scroll-marker(-group) 出現 == 0 (generated-content pseudo 捏造の静的 backstop)" 0 "$spseudoN"

echo
echo "--- list-marker-ban (warn 級 backstop・非 blocking): generated marker テキスト (counter-style / 文字列 list-style) ゼロ (round-3d ceiling・list-marker 新次元の S1 静的検出) ---"
# ::marker テキストは content プロパティを経由せず list-style-type + @counter-style (symbols/prefix/suffix) または
# 文字列リテラル list-style(-type) で生成され、 census (::marker content 走査) も fidelity (textContent) も両盲点する
# (round-3d ceiling agent3 実証: census exit0 で偽要件 li marker が可視描画・textContent blind)。 generated-content pseudo の
# 第3サブシステム (list-marker text generation)。 genuine SRS は list-style:none のみで @counter-style / 文字列 list-style を
# 一切使わない (verified 0) ゆえ、 script-ban 同型の genuine vocabulary 補集合 静的 invariant で封鎖する (標準キーワード
# none/disc/decimal 等は引用符を含まず素通る = FP-free・将来 genuine が実リストを使う時は標準 keyword allowlist で対応)。
# 機構非依存の構造閉包は cluster-2 (folio-hef.4 全描画テキスト ↔ contract 全単射) が担い、 本静的 ban はその前の安価封鎖。
lmN="$(perl -0777 -ne 'my $n = () = /\@counter-style\b/gi; my $m = () = /list-style(?:-type)?\s*:\s*[^;}"\x27]*["\x27]/gi; print $n+$m+0;' "$HTML")"
wchk "list-marker-ban: @counter-style / 文字列 list-style(-type) 出現 == 0 (generated marker 捏造の静的検出)" 0 "$lmN"

echo
echo "--- visual-deception unicode ban (warn 級 backstop・非 blocking): bidi-override / zero-width ゼロ (次元B・ws4o6ywe5 / folio-cpf 由来) ---"
# 機械生成 SRS は bidi-override (U+202A-202E / U+2066-2069) も zero-width・BOM (U+200B-200D / U+2060 / U+FEFF) も
# 一切 emit しない (verified: ec-checkout / clinic とも 0)。 これらは render してはじめて効く視覚破壊 = .resp/.tgt を
# 視覚反転 (bidi RLO) / 可視テキストを zero-width で消去する捏造で、 DOM textContent の *論理順序* を保つため
# fidelity ceiling すら見逃す (ws4o6ywe5 次元B)。 source/DOM に居る時点で静的・決定的に捕捉できる (render 不要)
# ゆえ floor で封鎖する。 z-order occlusion (不透明 overlay) は render 依存ゆえ floor 射程外 (folio-cpf へ carve)。
deceptN="$(perl -CSD -0777 -ne 'my $n = () = /[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200D}\x{2060}\x{FEFF}]/g; print $n+0;' "$HTML")"
wchk "visual-deception unicode (bidi-override/zero-width) == 0 (次元B 視覚破壊検出)" 0 "$deceptN"
# ── static-ban と FF4 (render-time positive allowlist) の codepoint 所掌分界 (folio-hef.2 監査補正 M-D point 2) ──
# 本 static unicode-ban (= epic 語彙の「gate K」) は bidi-override と zero-width/BOM *のみ* を whole-doc・render 不要で
# 弾く no-render backstop。 字幅ありインク0 の blank glyph (U+2800 Braille / U+3164 Hangul filler 等)・filler
# (U+115F/FFA0)・取り消し線 overlay (U+0334-0338 = tilde/stroke/solidus overlay) は **本 ban に追加しない**。
# それらは probe-srs.js FF4 (render-time の .plain codepoint positive allowlist) が *allowlist の補集合* として
# 網羅捕捉する (gate F2/census 経由)。 ★ここへ blank/filler/overlay を逐次追加すると blocklist drift (= β 違反・
# partial-enumeration の罠) を再導入する。 .plain の字種完全性は FF4 が render path で担い、 本 static-ban は
# whole-doc の bidi/zero-width no-render backstop に留めること。 ink 計測 (FF3) は base にインクが無い blank glyph を、
# FF4 codepoint allowlist は base にインクが乗る overlay を、 それぞれ render-time で捕捉する (両者は probe-srs.js)。

echo
echo "--- bidi-override-ban (warn 級 backstop・非 blocking): <bdo> / CSS unicode-bidi override ゼロ (round-3e ceiling・制御 codepoint 無しの視覚反転を検出) ---"
# <bdo dir=rtl> と CSS unicode-bidi:bidi-override|isolate-override は制御 codepoint (U+202x) 無しで視覚反転を実現し上の
# unicode ban を回避する (round-3e ceiling 実証: 'るす否拒に常をし戻い払' 反転・logical textContent 保持で fidelity blind)。
# 次元B 静的 ban と同型の機構漏れ。 genuine SRS は <bdo>=0 / source CSS unicode-bidi override=0 (verified)。 ★computed
# unicode-bidi:isolate は table/tr/td の UA 既定値ゆえ computed でなく *source CSS* の override リテラルと <bdo> 要素のみを ban する。
bdoN="$(perl -0777 -ne 'my $n = () = /<bdo\b/gi; my $m = () = /unicode-bidi\s*:\s*[^;}]*\b(?:bidi-override|isolate-override)/gi; print $n+$m+0;' "$HTML")"
wchk "bidi-override-ban: <bdo> / unicode-bidi:(bidi|isolate)-override 出現 == 0 (制御 codepoint 無し視覚反転検出)" 0 "$bdoN"

echo
echo "--- gate F: render 健全性 (playwright: low-contrast / horizontal-overflow / component-overlap) ---"
# gate F = render-gate-srs.py (light/dark × 3 viewport)。 重い playwright 検査ゆえ renderer 在環境で
# のみ実行し、 不在環境では honest SKIP (floor 不完全と明示・PASS と詐称しない)。 bash-only の高速 floor
# が要るとき (敵対スイート等) は SRS_SKIP_RENDER=1 で明示的に外す。 gateF = pass | fail | skip。
RENDER_GATE="$SCRIPT_DIR/render-gate-srs.py"
# render skip 判定 + RUNNER 検出を gate F / census で共有する (重複検出を避ける)。 SRS_SKIP_RENDER=1
# (敵対 bash floor) / render-gate-srs.py 不在 / playwright 不在 はいずれも honest SKIP (PASS 詐称しない)。
RENDER_SKIP=""; RUNNER=""
if [[ "${SRS_SKIP_RENDER:-0}" == "1" ]]; then
  RENDER_SKIP="SRS_SKIP_RENDER=1 — bash floor のみ。 render-gate-srs.py を別途実行せよ"
elif [[ ! -f "$RENDER_GATE" ]]; then
  RENDER_SKIP="render-gate-srs.py 不在"
else
  if python3 -c "import playwright" >/dev/null 2>&1; then RUNNER="python3"
  elif command -v uv >/dev/null 2>&1; then RUNNER="uv run --with playwright==1.60.0 python"
  elif [[ -x "$HOME/.local/bin/uv" ]]; then RUNNER="$HOME/.local/bin/uv run --with playwright==1.60.0 python"
  fi
  [[ -z "$RUNNER" ]] && RENDER_SKIP="playwright renderer 不在 — CI または uv 環境で render-gate-srs.py を実行"
fi

gateF="skip"
if [[ -n "$RENDER_SKIP" ]]; then
  echo "  [SKIP] gate F ($RENDER_SKIP)"
else
  echo "  render-gate-srs.py を実行 ($RUNNER)..."
  if $RUNNER "$RENDER_GATE" "$HTML" 2>&1 | sed 's/^/    /'; then gateF="pass"; else gateF="fail"; fail=1; fi
fi

echo
echo "--- gate F2 (census): 描画後 content-fidelity (pseudo-content 捏造 2b8 / 描画後 omission 459) — warn 級 backstop (非 blocking・§3.9) ---"
# gate F の sibling gate (folio-6jb 縦軸)。 gate F が「見えるが崩れている」を見るのに対し、 census は
# 「契約上あるべき内容が描画後に存在するか・偽の内容が注入されていないか」を見る。 静的 floor (make_body は
# <style> 空化 / comment verbatim 保持) を素通りする render 依存の捏造 (2b8 = ::after content) と隠蔽
# (459 = comment/display:none で非描画) を、 実 render で contract 由来期待件数と semantic セレクタの
# pseudo-content 不変条件に照合する。 期待件数は contract から導出 (論点5: probe は schema 非依存・件数のみ注入)。
# honest-SKIP は gate F と独立に報告する (gate identity 分離・論点4)。
# ★境界 (verification §3.9・REQ-VER-027): gate F2 の全 class は warn 級 backstop — census finding (exit 1) は
#   warn に写像し blocking しない (捏造の意味権威は ceiling gate J・可読性は gate I)。 blocking の部品件数照合は
#   census-count arm (上記・source DOM 静的件数) が render を要さず担う。 T7 render 破綻 (exit 2) は測定系
#   tool-integrity error として gate 判定と別軸で verify-srs 自体の exit 2 に伝播する (測定不能 ≠ clean)。
#   exit は crc (計算済み決定トークン) からのみ導出し、 probe の data 補間出力を grep しない。
gateCensus="skip"
# plain は .plain (平易説明) sub-slot の期待件数 = 各 FR/NFR 行に 1 つ = requirements + nfr (contract-anchor)。
# census の DOM 自己参照 (plains.length) を廃し caller から注入する (ws4o6ywe5 B4: 全削除/改名/template 退避を封鎖)。
# 期待件数は census-count arm と同じ contract 導出値 (CC_REQN/CC_NFRN) を共有する。
CENSUS_EXPECT="ears-requirement-row=${CC_REQN},nfr-metric-row=${CC_NFRN},plain=$((CC_REQN + CC_NFRN))"
if [[ -n "$RENDER_SKIP" ]]; then
  echo "  [SKIP] gate F2/census ($RENDER_SKIP)"
else
  echo "  render-gate-srs.py --census --expect '$CENSUS_EXPECT' --vocab <census-vocab> を実行 ($RUNNER)..."
  # --vocab = census 語彙 SSoT (folio-hef.3)。 件数注入 (--expect) の拡張として probe へ closure 語彙を carry
  #   する (S4 bijection の基盤・本 slice では probe は受領のみ)。
  cout="$($RUNNER "$RENDER_GATE" --census --expect "$CENSUS_EXPECT" --vocab "$CENSUS_VOCAB_JSON" "$HTML" 2>&1)"; crc=$?
  printf '%s\n' "$cout" | sed 's/^/    /'
  case "$crc" in
    0) gateCensus="pass" ;;
    1) gateCensus="warn"; warnN=$((warnN+1))
       echo "  [WARN] gate F2/census finding (warn 級 backstop・非 blocking — 意味権威は ceiling gate I/J・verification §3.9)" ;;
    *) gateCensus="toolerror"; toolerr=1
       echo "  [ERROR] gate F2/census 測定系 tool-integrity error (T7 render 破綻 等・exit $crc) — gate 判定と別軸で非零 exit (§3.9)" ;;
  esac
fi

echo
echo "=========================================================================="
# exit 導出 (§3.9 境界): blocking arm (gate A-E,G,H + visual-first + census-count + gate F) の fail が exit 1、
# warn 級 backstop 指摘 (warnN) は exit を上げない、 測定系 tool-integrity error (toolerr) は blocking FAIL が
# 無いときのみ exit 2 で伝播する (blocking FAIL の決定的 verdict は測定破綻と独立に信頼できるため優先)。
[[ "$warnN" -gt 0 ]] && echo "WARN: warn 級 backstop 指摘 $warnN 件 (非 blocking・§3.9 境界 — 意味権威は ceiling gate I/J。 honest-bug の可能性があるため生成器 bug としては調査対象)"
if [[ "$fail" -eq 0 ]]; then
  if [[ "$toolerr" -ne 0 ]]; then
    echo "RESULT: 測定系 tool-integrity error (gate F2 の T7 render 破綻 等) — blocking arm は FAIL していないが測定不能を clean と詐称しない (exit 2)"
    exit 2
  fi
  if [[ "$gateF" == "pass" && "$gateCensus" == "pass" ]]; then
    echo "RESULT: floor PASS (blocking arm: gate A-F + visual-first + census-count / warn 級 backstop 指摘 $warnN 件) — ただし CEILING=PENDING (*GREEN ではない*)"
  else
    echo "RESULT: floor PASS (blocking arm: gate A-E,G,H + visual-first + census-count / render gate: gateF=$gateF census=$gateCensus) — ただし CEILING=PENDING (*GREEN ではない*)"
    if [[ "$gateF" == "skip" || "$gateCensus" == "skip" ]]; then
      # 「render gate 未完」は ceiling-precheck.sh の SKIP-masquerade 検出 marker (3 重冗長の 1 つ) — 削らない。
      echo "  ※ render gate 未完 (F=見た目崩れ / F2 census=描画後 content-fidelity の warn 級 backstop が未実行: renderer 不在 or SRS_SKIP_RENDER) — CI/uv 環境で render-gate-srs.py を回すまで floor は不完全。"
    fi
  fi
  echo "  ceiling = persona-walk-srs + fidelity-srs + completeness-critic-srs (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に blocking arm (gate A-E,G,H + visual-first + census-count + gate F) が不合格"
  exit 1
fi
