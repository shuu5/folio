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
#   gate G  内容完全性(no-TBD): MUST 部品の必須スロット非空 (verify-fab --artifact) + placeholder トークン (TBD/未定 等) =0
#   gate H  fidelity meta     : fidelity-sync-meta の 3 項目が *非空白* で埋まる
#   visual-first              : 各章 (footer 除く) に非 prose 部品が ≥1 (字だけの章 =0)
#
# ★floor 通過しても GREEN を宣言しない: ceiling=PENDING を返す (taxonomy §5.1「floor 単独 GREEN 禁止」)。
#   GREEN ⟺ (floor 全通過) AND (ceiling 合格)。 ceiling = persona-walk-srs + fidelity-srs (S5.2)。
#   exit 0 は「floor PASS」を意味し「GREEN」ではない (caller は exit 0 を GREEN に流用してはならない)。
#
# usage: verify-srs.sh <contract.yaml> <generated.html>
# exit:  0 = floor PASS (ceiling PENDING) / 1 = floor FAIL / 2 = tool error

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
make_body "$HTML"        # body-only ($BODY、 CSS セレクタ混入回避)
has() { local c; c="$(grep -c "data-component=\"$1\"" "$BODY")"; [[ "$c" -ge 1 ]] && echo 1 || echo 0; }

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
echo "--- script-ban: SRS HTML は <script> ゼロ (4gz render-time DOM-swap / 459 script-container OMISSION を静的封鎖) ---"
# SRS は <script> を一切 emit しない (verified)。 ゆえに任意の <script> は捏造コンテナ = (a) 検証通過後に
# innerHTML/insertAdjacentHTML で genuine な要件/承認/章を捏造差替えする render-time DOM-swap (folio-4gz)、
# (b) 必須要素を <script> で包み静的 grep を素通しつつブラウザ非描画にする OMISSION (folio-459 script-container)。
# render を要さず pack-additive 静的 invariant (この doc-type の HTML は <script>==0) で原理封鎖する
# (render census でなく静的 floor・render ゼロコスト・script-free 5 pack 共通の fab-free invariant の SRS 適用)。
# raw $HTML を case-insensitive・タグ境界 (\b) で count (head/body 双方を被覆・make_body の body-only view に依存しない)。
scriptN="$(perl -0777 -ne 'my $n = () = /<script\b/gi; print $n+0;' "$HTML")"
chk "script-ban: <script> 出現 == 0 (4gz/459-script 静的封鎖)" 0 "$scriptN"

echo
echo "--- visual-deception unicode ban: bidi-override / zero-width ゼロ (次元B・ws4o6ywe5 / folio-cpf 由来の floor 化) ---"
# 機械生成 SRS は bidi-override (U+202A-202E / U+2066-2069) も zero-width・BOM (U+200B-200D / U+2060 / U+FEFF) も
# 一切 emit しない (verified: ec-checkout / clinic とも 0)。 これらは render してはじめて効く視覚破壊 = .resp/.tgt を
# 視覚反転 (bidi RLO) / 可視テキストを zero-width で消去する捏造で、 DOM textContent の *論理順序* を保つため
# fidelity ceiling すら見逃す (ws4o6ywe5 次元B)。 source/DOM に居る時点で静的・決定的に捕捉できる (render 不要)
# ゆえ floor で封鎖する。 z-order occlusion (不透明 overlay) は render 依存ゆえ floor 射程外 (folio-cpf へ carve)。
deceptN="$(perl -CSD -0777 -ne 'my $n = () = /[\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200D}\x{2060}\x{FEFF}]/g; print $n+0;' "$HTML")"
chk "visual-deception unicode (bidi-override/zero-width) == 0 (次元B 視覚破壊封鎖)" 0 "$deceptN"

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
echo "--- gate F2 (census): 描画後 content-fidelity (pseudo-content 捏造 2b8 / 描画後 omission 459) ---"
# gate F の sibling gate (folio-6jb 縦軸)。 gate F が「見えるが崩れている」を見るのに対し、 census は
# 「契約上あるべき内容が描画後に存在するか・偽の内容が注入されていないか」を見る。 静的 floor (make_body は
# <style> 空化 / comment verbatim 保持) を素通りする render 依存の捏造 (2b8 = ::after content) と隠蔽
# (459 = comment/display:none で非描画) を、 実 render で contract 由来期待件数と semantic セレクタの
# pseudo-content 不変条件に照合する。 期待件数は contract から導出 (論点5: probe は schema 非依存・件数のみ注入)。
# honest-SKIP は gate F と独立に報告する (gate identity 分離・論点4)。
gateCensus="skip"
# plain は .plain (平易説明) sub-slot の期待件数 = 各 FR/NFR 行に 1 つ = requirements + nfr (contract-anchor)。
# census の DOM 自己参照 (plains.length) を廃し caller から注入する (ws4o6ywe5 B4: 全削除/改名/template 退避を封鎖)。
CENSUS_REQN="$(q '.requirements | length')"; CENSUS_NFRN="$(q '.nfr | length')"
CENSUS_EXPECT="ears-requirement-row=${CENSUS_REQN},nfr-metric-row=${CENSUS_NFRN},plain=$((CENSUS_REQN + CENSUS_NFRN))"
if [[ -n "$RENDER_SKIP" ]]; then
  echo "  [SKIP] gate F2/census ($RENDER_SKIP)"
else
  echo "  render-gate-srs.py --census --expect '$CENSUS_EXPECT' を実行 ($RUNNER)..."
  if $RUNNER "$RENDER_GATE" --census --expect "$CENSUS_EXPECT" "$HTML" 2>&1 | sed 's/^/    /'; then gateCensus="pass"; else gateCensus="fail"; fail=1; fi
fi

echo
echo "=========================================================================="
if [[ "$fail" -eq 0 ]]; then
  if [[ "$gateF" == "pass" && "$gateCensus" == "pass" ]]; then
    echo "RESULT: floor PASS (gate A-F + census + visual-first) — ただし CEILING=PENDING (*GREEN ではない*)"
  else
    echo "RESULT: floor PASS (gate A-E,G,H + visual-first / render gate 未完: gateF=$gateF census=$gateCensus) — ただし CEILING=PENDING (*GREEN ではない*)"
    echo "  ※ render gate (F=見た目崩れ / census=描画後 content-fidelity) が未実行 (renderer 不在 or SRS_SKIP_RENDER) — CI/uv 環境で render-gate-srs.py を回すまで floor は不完全。"
  fi
  echo "  ceiling = persona-walk-srs + fidelity-srs (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に floor が不合格"
  exit 1
fi
