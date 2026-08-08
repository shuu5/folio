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
# ★folio-lq12 S4(B): 忠実抽出の機械証明で使う 凍結 census と canonical (§L / §S4(B) の両方が参照するため冒頭で定義)。
#   ★env 上書き口を ★意図的に置かない: 既存 pack の SPEC_ORIGIN_HTML / RELATIONS_ORIGIN_HTML は snapshot の
#   差替えを test が要求するため env 化されているが、 本 arm の canonical は ★P-10 で frozen な唯一の原本 であり、
#   env で差し替えられる口は「別ファイルを canonical と偽って通す」bypass 経路そのものになる。 test 側は
#   verify の copy に対する path 差替え (FROZEN_CENSUS の sed 置換・LQ-C1/C2/C3) で必要な実弾を撃てている。
FROZEN_CENSUS="$SCRIPT_DIR/spec-origin/constitution.frozen-census.txt"
CANONICAL_SRC="$SCRIPT_DIR/../../../design-intent/spec/constitution.html"
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
# ★repro-build byte-identity gate (verification §3.9 REQ-VER-030 blocking arm・folio-3d23・占有 pin 群の構造終端後継)。
verify_repro_build principle "$FILLED_MANIFEST"

# ★folio-bur round-3 (ceiling-recursion R3): comment-hidden classless forgery 封鎖。
#   round-2 の comment-hidden 対策は decoy 自身が marker class を担持する亜種だけを占有数パリティで捕捉したが、
#   genuine を `<!--...-->` へ退避し marker class 無しの可視 decoy を描く classless 変種が素通った (独立 ceiling R2 実証)。
#   HTML comment を除去した body で可視 grep + 占有数を再導出すれば、comment 内 genuine は消え (act/count が欠落) FAIL に倒れる。
#   pack-level (core make_body は無改変・byte-identity 維持)。am-meta / ib-from / ib-role の 3 pin で使用。
BODY_NC="$(mktemp)"; trap 'rm -f "$BODY" "$BODY_NC"' EXIT
perl -0777 -pe 's/<!--.*?-->//gs' "$BODY" > "$BODY_NC"

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
# ★folio-lq12: 「body 全体の <li> を数える」旧形は節骨格の導入で ★恒真化した (§1 核心 list 4 + §7 Citations 10 が
#   同一文書に入り 5 → 19)。 amendment 由来の li を class="amp-step" で識別する ★class-scoped 形へ厳格化する
#   (緩和ではなく narrowing = 他由来の li が増えても amendment の件数検査が壊れない)。 併せて「amp-step 以外の
#   li は raw blob 由来ちょうど N 本」を下の raw blob echo arm が占有数で挟む。
chk "amendment steps == |steps| (class-scoped)" "$(q '.amendment.steps | length')"  "$(grep -oE '<li class="amp-step">' "$BODY" | wc -l | tr -d ' ')"
chk "glossary == |glossary|"           "$(q '.glossary | length')"    "$(grep -c 'class="grow"' "$BODY")"
chk "approval == |approval|"           "$(q '.approval | length')"    "$(grep -c 'class="sign"' "$BODY")"

echo
echo "--- census-count (blocking arm・folio-jmmk): 来歴部品の source DOM 静的件数 == contract 期待件数 ---"
# 機械/LLM 境界 (verification §3.9) の render 非依存 blocking 件数照合。 count_attr_token (quote 構文・属性名 case・数値
# 文字参照 非依存の occurrence 数え = SRS 499ab7b census-count arm と同規律) で principle-amendment-history トークン件数を
# 数え、 期待値は contract から自己導出 (DOM 非参照・contract-anchor)。 am-meta 順序値 chk は Σ|amended_by| 基数 (改訂 ADR 総数)
# を守るが amended principle *数* (= history block 数) を守る第 1 層が無い (sweep 分類表 = folio-3d23【B2 占有pin sweep
# 成果物】の唯一 anchor)。 本 arm は占有 pin de-scope (Phase C) 後も同強度で件数照合を継承する static 後継。
chk "census-count: principle-amendment-history == |amended|" "$(q '[.principles[] | select((.amended_by // []) | length > 0)] | length')" "$(count_attr_token data-component principle-amendment-history < "$BODY")"

# 1b. ★core 共通 chrome (cover-head/approval/glossary の値突合 + 占有数パリティ・folio-mk9)。
verify_core_chrome

# ===== folio-lffq: emit 3 点 (head meta / head JSON-LD / navigable p-N anchor) の floor =====
# ★本 3 群を追加する前、 verify-principle.sh には head / meta / JSON-LD の assert が 0 件だった (実測)。
#   ゆえ「実装しただけ」では 3 emit 点は 1 本も検査されておらず、 assembler の emit 呼出を 1 行落としても
#   FAIL 件数は baseline と完全一致する (= 喪失に vacuous PASS)。 verify-verification.sh:152-181 の範型を移植する。

# 1c. ★(A) head meta 5 本 (CORE 3 = doc-type/status/version + pack 2 = layer/stakeholders) の contract 由来値突合。
#   ★双方向 chk (捏造も喪失も捕捉): contract に値が在れば逐字存在を要求し、 無ければ生成物にも不在を要求する。
#   ★総数 pin: per-meta chk は「知っている 5 本」しか見ないため、 未知 meta の捏造混入を数で挟む
#     (canonical constitution.html:6-10 実測 = 5 本。 canonical に無い folio-glossary-automark /
#      folio-xref-completeness は contract に値を置かない = 生成物にも出ないことを空側の chk が要求する)。
verify_head_meta() {
  local key tag exp act pair
  for pair in 'doc_type:folio-doc-type' 'status:folio-status' 'version:folio-version' \
              'layer:folio-layer' 'stakeholders:folio-stakeholders' \
              'glossary_automark:folio-glossary-automark' 'xref_completeness:folio-xref-completeness'; do
    key="${pair%%:*}"; tag="${pair##*:}"
    if [[ "$key" == "stakeholders" ]]; then exp="$(q '(.meta.stakeholders // []) | join(", ")')"
    else exp="$(q ".meta.$key // \"\"")"; fi
    [[ "$exp" == "null" ]] && exp=""
    act="$(T="$tag" perl -CSD -0777 -ne 'BEGIN{$t=$ENV{T}} while (/<meta name="\Q$t\E" content="([^"]*)">/g){ print "$1\n"; }' "$HTML")"
    if [[ -n "$exp" ]]; then
      chk "head meta $tag == contract .meta.$key" "$(esc "$exp")" "$act"
    else
      chk "head meta $tag 不在 (contract 側も空 = 捏造禁止)" "" "$act"
    fi
  done
  chk "folio-* head meta 総数 == 5 (CORE 3 + pack 2)" "5" \
    "$(grep -o '<meta name="folio-[^"]*"' "$HTML" | wc -l | tr -d ' ')"
}
verify_head_meta

# 1d. ★(B) head JSON-LD の @type == FolioConstitution。
#   ★parse 不能 / block 0 件は FAIL (skip 禁止): bin/folio の 5 site (127 inventory / 436 is_scan_target /
#   617 fix Pass1 / 2429 validate 主 loop / 4511 nav_is_self_root) は JSON-LD が *無い* 場合も *parse 不能* な
#   場合も「@type 不一致」と同じ枝へ落ちる = 除外 4 site の観測結果は JSON-LD 皆無のときと区別できない。
#   ゆえ「inventory / validate に出ない」を単独 DoD にできず、 ここで block の実在と型を直接 pin する。
#   ★bin/folio:27-34 と同じく *head 内の最初の* ld+json block だけを見る (2 本目は dead emit ゆえ数で塞ぐ)。
#   ★errata-2 M5 (admin gate round-2 ■B・parser-differential = 既知 r8k クラス): 抽出述語を consumer の *逐語複製* へ置換。
#     旧実装は head slurp + 非貪欲 regex の「構造的」抽出で、 consumer folio_extract_head_jsonld (bin/folio:27-34) の
#     *行単位* 走査 (開始タグ行そのものは print しない) と非等価だった。 ld+json 本文を開始タグと同じ 1 行へ畳む mutant は
#     @type / @id / block 数 のいずれも genuine と同値のまま consumer 側の抽出結果だけを壊す (capturing が開始タグ行の
#     *末尾* で立つため、 consumer は JSON 本文を 1 byte も掴めず ★次行以降の head 内容 を掴んで </head> で exit する)。
#     ★errata-2 追補 round-4 (事実訂正): 旧記述は「consumer 側だけを *空へ* 落とし」と書いていたが実測と異なる —
#       本 contract の生成物では抽出結果は空でなく ★後続の <meta name="folio-layer"…> / <meta name="folio-stakeholders"…>
#       2 行 (= JSON として不正) になる。 ゆえ落ちる枝も「block 不在」ではなく ★「jq parse 不能」枝である。
#       (どちらの枝でも bin/folio の 5 site は同じく「@type 不一致」へ倒れるため結論は変わらないが、 機構の記述が
#        事実と異なると後続 cell が誤った前提で arm を組むため訂正する = M8 と同一様式)。 なお head の末尾に ld+json が
#       置かれた pack では抽出結果が真に空にもなりうる = 空/非空 のどちらでも壊れることが本 mutant の本質。
#     結果として verify rc=0 のまま folio validate の cluster-reachability が [FAIL]→[WARN] へ反転する
#     (= scan 除外 4 site と self-root 検出の前提が無言で消える)。 assembler 経路の実弾 (lib/common.sh:135 printf の
#     改行 1 個除去) でも再現するため、 verify が判定に使う値そのものを consumer と同一述語で取る。
jsonld_head_consumer() { # ★bin/folio:27-34 の逐語複製 (規則の順序・条件を 1 byte も変えない)
  awk '
    /<\/head>/ { exit }
    capturing && /<\/script>/ { exit }
    capturing { print }
    /<script[^>]*type="application\/ld\+json"/ { capturing = 1 }
  ' "$1"
}
# 旧・構造抽出 (head slurp + 非貪欲 regex)。 判定には使わず *2 述語の差分検出* のためだけに残す。
jsonld_head_struct() {
  perl -0777 -ne '
    my ($head) = /<head\b[^>]*>(.*?)<\/head>/s;
    $head = "" unless defined $head;
    if ($head =~ /<script[^>]*type="application\/ld\+json"[^>]*>(.*?)<\/script>/s) { print $1; }
  ' "$1"
}
jsonld_head="$(jsonld_head_consumer "$HTML")"
# ★2 述語の出力一致 pin: 構造抽出と consumer 抽出が食い違った瞬間に FAIL へ倒す (どちらが「正しい」かに依らず
#   parser-differential の *存在* 自体を禁止する = r8k クラスの構造終端)。
#   ★空白を除いて比較する: genuine の差分は開始タグ直後の改行 1 個だけ (perl は含み awk は含まない・worker 実測)。
#     ★errata-2 追補 round-4 (事実訂正): 旧記述は安全性の根拠を「■B の 1 行畳み mutant は awk 側が *空* に落ちる
#       (空 vs JSON 本文の差)」と書いていたが実測と異なる。 実際の awk 側出力は ★後続の <meta> 2 行 である。
#       正しい根拠は「空白を除いても ★両辺のトークン列が別物 (JSON 本文 vs meta タグ列) として残る」ことであり、
#       空白正規化が消せるのは *改行/インデントだけ* ゆえ本 mutant の検出力は落ちない (実測: 本 arm が [FAIL])。
#       もし将来 mutant が「空白だけが違う」形に退化したら、 それは consumer/構造の両抽出が同一 JSON を掴んでいる
#       ということであり consumer は壊れていない = 見逃しではない。
chk "head JSON-LD: 抽出述語 == consumer 述語 (bin/folio:27-34) の出力一致" \
  "$(printf '%s' "$(jsonld_head_struct "$HTML")" | tr -d '[:space:]')" \
  "$(printf '%s' "$jsonld_head" | tr -d '[:space:]')"
chk "head JSON-LD block 数 == 1 (2 本目は bin/folio:27-34 が読まない dead emit)" "1" \
  "$(perl -0777 -ne 'my ($h)=/<head\b[^>]*>(.*?)<\/head>/s; $h="" unless defined $h; my $c=0; $c++ while $h =~ /<script[^>]*type="application\/ld\+json"[^>]*>/g; print $c;' "$HTML")"
if [[ -z "$jsonld_head" ]]; then
  printf '  [FAIL] %-'"$CHKW"'s\n' "head JSON-LD: block 不在 (@type 判定不能 = scan 除外/self-root の前提が消える)"; fail=1
elif ! printf '%s' "$jsonld_head" | jq -e . >/dev/null 2>&1; then
  printf '  [FAIL] %-'"$CHKW"'s\n' "head JSON-LD: jq parse 不能 (bin/folio の 5 site が全て @type 不一致枝へ落ちる)"; fail=1
else
  chk "head JSON-LD: @type == FolioConstitution" "FolioConstitution" \
    "$(printf '%s' "$jsonld_head" | jq -r '."@type" // "(@type 無し)"')"
  chk "head JSON-LD: @id == contract .head_graph.id" "$(q '.head_graph.id')" \
    "$(printf '%s' "$jsonld_head" | jq -r '."@id" // "(@id 無し)"')"
  # ★前方関係 0 本 (照会終端 不変条件の head 面・assemble validate と detect↔remediate parity)。
  chk "head JSON-LD: 前方関係キー 0 本 (principle は照会終端)" "0" \
    "$(printf '%s' "$jsonld_head" | jq -r '[keys[] | select(. == "dc:isPartOf" or . == "dc:references" or . == "folio:depends-on" or . == "folio:extends")] | length')"
  # ★folio:stakeholders は array 型を維持 (contract scalar → string 型退行の fail-open は assemble が abort するが、
  #   生成物側でも型を pin して post-build 改変を捕捉する)。
  chk "head JSON-LD: folio:stakeholders は array" "array" \
    "$(printf '%s' "$jsonld_head" | jq -r '."folio:stakeholders" | type')"
fi

# 1e. ★(C) navigable id (p-N anchor) の厳密集合一致 — 欠落 0 / 余剰 0。
#   ★errata-1 M2 (admin gate B2・parser-differential = 既知 r8k クラス): 旧実装は byte 近似の
#     grep -oP '\sid="\K…' / lookbehind '(?<=[\s"])id="' を使っており、 (a) 行頭の id 属性 (直前に \s も " も
#     無い) と (b) 大文字 ID= が census から不可視なのに consumer (folio_anchor_exists の grep -F substring /
#     HTML parser の属性名 case-insensitive) からは可視 = forged id での hijack が rc=0 で素通った (admin 実測 3 mutant)。
#     ゆえ census は lib/verify-common.sh の count_attr_token / attr_values と *同型* の属性 parse へ置換する
#     (lib は 16 pack 共有 + 本 cell の scope 外ゆえ触らず、 pack-local に同型実装を置く)。
#   ★boundary caveat: 属性名 id は data-slot-id / data-inbound-ref 等の *接尾* にも現れる。 \b は '-' の直後で
#     成立してしまい data-slot-id="p-1" を id 属性として誤認するため、 直前 1 文字が [-A-Za-z0-9_:] *でない*
#     ことを明示的に要求する (= 属性名の真の先頭のみ)。 行頭 (直前文字なし) も正当な境界として受ける。
#   ★期待値は contract の P-N を tr で小文字化した決定的導出値 (contract の .anchor 手書き値へ defer しない)。
#     .anchor 自身の正しさは下の chk が id 由来期待値と突き合わせる (contract 側 drift の独立 pin)。
# id_attr_values — stdin HTML から属性 id の値を quote 構文 (double / single / unquoted)・属性名 case・
#   数値文字参照 非依存に 1 行ずつ出力 (attr_values 同型・pack-local)。
#   ★single-quote 文字は perl 側で \x27 として書く (shell の '"'"' 連結や $q 変数に頼ると、 単一引用符で括った
#     perl プログラム中の $q が *shell* 変数として空展開され regex が壊れる = 実際に census 0 件へ転んだ)。
id_attr_values() {
  perl -CSD -0777 -e '
    my $txt=<STDIN>; $txt="" unless defined $txt;
    while ($txt =~ /(?<![-A-Za-z0-9_:])(?i:id)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))/g) {
      my $v = defined $1 ? $1 : (defined $2 ? $2 : $3);
      $v =~ s/&#[xX]([0-9a-fA-F]+);?/chr(hex($1))/ge;
      $v =~ s/&#([0-9]+);?/chr($1)/ge;
      $v =~ s/[\t\n]+/ /g;
      print "$v\n";
    }
  '
}
# id_attr_lines — 真の id 属性が現れる *行番号* を 1 行ずつ出力 (行粒度束縛用・同一境界述語)。
id_attr_lines() {
  perl -CSD -ne '
    print "$.\n" if /(?<![-A-Za-z0-9_:])(?i:id)\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s>]+)/;
  '
}
#   ★errata-2 M4 (admin gate round-2 ■A・B1/B2/B3 の残穴): 本 census 群と下の essence 群の入力を $BODY から
#     ★生ファイル ($HTML) へ切り替える。 $BODY は make_body (lib/verify-common.sh:115-160) が <style> 本文を
#     *空化* した写像であり、 consumer 2 述語 (folio_xref_essence bin/folio:1468-1472 / folio_anchor_exists :1423-1427)
#     は生ファイルを行走査する。 ゆえ <style> 本文へ decoy strong / forged id を置くと floor は全緑 (rc=0 / FAIL 0) の
#     まま essence 乗っ取り・gate (h) 偽解決が成立した (admin ceiling の実弾再現)。 HTML comment 内 decoy は $BODY が
#     保存するため既存 arm が捕捉しており、 盲点は CSS 本文に限定されていた。
#     ★安全性 (生ファイルで偽 FAIL しないこと) は実測で確認済: genuine 生 HTML の 厳密 id 属性 census = 14 ちょうど /
#       <style> 433 行の中に id 様トークン 0 / head 内 <strong> 0 (= 生へ広げても余剰は 1 件も入らない)。
#     ★repro-build は同一 assembler の再生成ゆえ assembler 側の emit 退行 (emit_principle_css = 本 cell の編集面) に
#       構造的に盲目 (AN-H8 と同一論拠) = 生ファイル走査だけが観測面。
# ★folio-lq12: 期待 id 集合は ★contract から決定的に導出する 3 系の和 — lc(principles[].id) 14 +
#   sections[].anchor 8 + sections[].subsections[].anchor 3 = 25 (canonical constitution の navigable anchor 総数)。
#   ★literal を verify に焼かない (件数も集合も contract 導出)。 ★「契約に無い id は 1 本も許さない」の強度は
#   非減少 (集合が 3 系の和へ広がるだけで、 和の外は従来どおり 1 本も許さない = 下の余剰 0 arm が同一集合で撃つ)。
exp_pn_anchor="$(q '.principles[].id' | tr '[:upper:]' '[:lower:]')"
exp_sec_anchor="$(q '.sections[].anchor')"
exp_sub_anchor="$(q '.sections[].subsections[]?.anchor')"
exp_anchor="$(printf '%s\n%s\n%s\n' "$exp_pn_anchor" "$exp_sec_anchor" "$exp_sub_anchor" | grep . | LC_ALL=C sort)"
exp_anchor_n="$(( $(q '.principles | length') + $(q '.sections | length') + $(q '[.sections[].subsections[]?] | length') ))"
act_anchor="$(id_attr_values < "$HTML" | LC_ALL=C sort)"
set_eq "anchor: 生成物の厳密 id 集合 == lc(principles.id) ∪ section ∪ subsection" "$exp_anchor" "$act_anchor"
chk "anchor: 件数 == |principles|+|sections|+|subsections| (重複 0)" "$exp_anchor_n" \
  "$(id_attr_values < "$HTML" | grep -c .)"
chk "p-N anchor: contract .anchor == lc(.id) (contract 側 drift)" \
  "$(q '.principles[].id' | tr '[:upper:]' '[:lower:]')" "$(q '.principles[].anchor')"
# ★余剰 0 の最強形: body 中の *全* id 属性 (quote 構文・属性名 case 非依存) が p-N 14 個ちょうどであること。
#   置換前は data-slot-id への substring 誤一致を lookbehind [\s"] で避けていたが、 その副作用が上記 (a)(b) の
#   死角だった。 属性名の真の先頭を要求する形なら誤一致も死角も同時に消える。
chk "anchor: body 中の全 id 属性 == 契約 3 系の和のみ (余剰 id 0)" "$exp_anchor" \
  "$(id_attr_values < "$HTML" | LC_ALL=C sort)"
# ★canonical 形以外の quote / case で書かれた id が 0 本 (consumer 間の非対称を封鎖)。
#   folio_anchor_exists (bin/folio:1426) は id='..' も真とするが bin/folio:2308 (objectGraph) は double-quote
#   しか見ない。 大文字 ID= も HTML parser では有効だが両 consumer には不可視 = 片方だけが真になる非対称を潰す。
chk "p-N anchor: 非 canonical 形 id 属性 0 本 (single-quote / unquoted / 大文字)" "0" \
  "$(perl -CSD -0777 -ne 'my $c=0;
     while (/(?<![-A-Za-z0-9_:])(?i:id)\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s>]+)/g) {
       my $whole=$&; $c++ unless $whole =~ /^id="[^"]*"$/;
     } print $c;' "$HTML")"
# ★errata-2 M6 (admin gate round-2 ■C): consumer の *substring 可視面* census を独立 arm として増設する。
#   上の census 群は「属性名の真の先頭」を要求する = HTML として真に id 属性であるものだけを数える。 だが consumer 2 本は
#   属性境界を一切見ない substring 述語である:
#     folio_anchor_exists (bin/folio:1423-1427) = grep -qF 'id="p-N"' / folio_xref_essence (:1468-1472) = index($0,"id=\"p-N\"")
#   ゆえ *接尾* 属性 (data-ref-id= / xid= 等) へ p-N を書くだけで、 厳密 census からは不可視のまま consumer からは可視に
#   なる (admin 実弾: 1 行の forged id で pre-fill / --filled とも rc=0 のまま gate (h) 偽解決 + essence 乗っ取りが成立)。
#   ★処方 M6 の逐語形「substring 値集合に lc(principles[].id) 以外 0 本」は、 そのままでは *健全生成物で恒真 FAIL* になる:
#     genuine な data-slot-id="plain-P-N" / ="cover-summary" / ="chapter-lead-NN" 等 24 本が substring 面に現れるため
#     (worker 実測)。 ゆえ処方の *意図* (= consumer 可視面での forged anchor の封鎖) を保存したまま narrow するが、
#     ★narrow の軸を 2 本に分けて張る (errata-2 追補・admin gate round-3 の critical 1 + major 2 を受けた是正):
#       arm-1 = 「値の形」軸: p-N 形の値の *多重集合* 一致 (余剰 p-N + 既存 p-N の接尾複製 を撃つ)。
#       arm-2 = 「属性名」軸: 接尾 id 属性の名前 allowlist (= prose slot 由来の data-slot-id のみ・余剰 0)。
#     arm-1 だけでは *非 p-N 値* の接尾 forged (data-x-id="s2-forged" 等) がどの観測面にも入らず gate (h) 偽解決が
#     rc=0 で成立した (round-3 実弾)。 属性名軸を独立に張ることで、 値の形に依らず接尾面そのものを閉じる。
#     ★「2 本」は M6 (substring 可視面) の narrow 軸の数である。 下に足す arm-3 (「<style> 本文」) は M4 系 =
#       *配置面* ($BODY 不可視域) の封鎖ゆえ本 narrow の軸には数えない (round-4 追補)。
#
#   ★arm-1 の抽出は「任意値を掴んでから ^p-[0-9]+$ で filter」ではなく ★p-N 値を *直接* 要求する (round-3 critical)。
#     旧形 /id\s*=\s*(?:"([^"]*)"|'([^']*)')/g は値を貪欲に取るため、 値の末尾/先頭が id= を含む decoy 属性があると
#     閉じ quote を「開始 quote」として消費して以降の真の出現を mask した (perl の //g は非重複走査ゆえ pos が
#     target の開始 quote の後ろへ進む)。 実弾 2 形が rc=0 で通っていた:
#       (a) quote-desync   <div data-x-id=" data-y-id="p-99">  → 掴む値は " data-y-id=" (p-N 形でないので記録もされない)
#       (b) 値末尾 id=      <div data-x="xid=" data-ref-id="p-99"> → 同上
#     p-N を直接要求する形なら「値が p-N でない限りそもそも match しない」= 先行 match が target を飲み込めず
#     desync が *構造的に* 消える (partial-enumeration でなく不変条件による終端)。 検出力は旧形の狭義 superset
#     (genuine 14 のまま偽 FAIL なし / 既存 MK AN-H16-H18 は 15 で不変 / 上記 (a)(b) を新たに捕捉・worker 実測)。
id_substr_pN() { # stdin HTML → consumer 可視 literal id="p-N" / id='p-N' の出現を 1 行ずつ (属性名接尾を含む)
  perl -CSD -0777 -e '
    my $txt=<STDIN>; $txt="" unless defined $txt;
    while ($txt =~ /id\s*=\s*(?:"(p-[0-9]+)"|\x27(p-[0-9]+)\x27)/g) {
      print((defined $1 ? $1 : $2), "\n");
    }
  '
}
# ★folio-lq12: 本 arm の期待値は ★lc(principles[].id) のまま (id_substr_pN は値の形を p-N に限る述語ゆえ、
#   節 anchor s0-… を含む和集合と突合すると恒真 FAIL になる)。 節 anchor 側の consumer 可視面は下の
#   「接尾 id 属性 allowlist」arm (値の形に依らず属性名軸で閉じる) と 全 id census が担う。
chk "p-N anchor: consumer 可視面 (substring) の p-N 多重集合 == lc(principles[].id)" \
  "$(printf '%s\n' "$exp_pn_anchor" | LC_ALL=C sort)" "$(id_substr_pN < "$HTML" | LC_ALL=C sort)"
# ★arm-2 (属性名軸): consumer の substring 面に現れる *接尾* id 属性 (= 属性名の真の先頭でない id= 出現) は
#   genuine では prose slot の data-slot-id ちょうど 24 本だけであり、 それ以外は 1 本も無い (worker 実測 —
#   base / filled とも接尾 id 属性名は data-slot-id のみ)。 ゆえ「余剰 0」を直接要求できる。
#   ★allowlist は属性名だけでなく ★prose slot との隣接 (data-prose-slot="…" の直後) まで要求する: 名前だけの
#     allowlist にすると <div data-slot-id="s2-forged"> を足すだけで穴が *移設* されるため (fix が新たな
#     fail-open を作らないことの構造保証)。 assembler の emit 形 (lib/common.sh:163,175 / assemble-principle.sh:306,338,346)
#     は全て data-prose-slot="X" data-slot-id="Y" の隣接ゆえ genuine は 0 で通る。
#   ★残る面 (虚偽の被覆表示をしないための明示・★errata-2 追補 round-4 で ★配置別の実測へ是正):
#     <div data-prose-slot="p" data-slot-id="s2-forged"> のような *対で* 捏造する形は本 arm (allowlist 例外) を通る。
#     旧コメントは「--filled mode では §11 の slot-id 集合突合 (manifest 突合) が捕捉する」と *配置に依らない* 形で
#     書いていたが、 実測では偽である (round-4 major)。 §11 (下の prose スロット節) は $BODY を読み make_body は
#     <style> 本文を空化するため、 同じ対を <style> 内へ置くと --filled でも rc=0 / [FAIL] 0 で素通った
#     (consumer folio_anchor_exists は生ファイル grep ゆえ id="s2-forged" を解決 = gate (h) 偽解決)。 配置別の実体:
#       - body 直下 / HTML comment 内: $BODY が保存するため --filled は §11 が「注入不一致」で捕捉 (実測 rc=1)。
#         pre-fill は *中身つき* なら「prose スロットは全て空」が捕捉するが、 *空の* 対は素通る (実測 rc=0)。
#       - <style> 本文: §11 は pre-fill / --filled の ★両モードとも観測面外。 ゆえ下の arm-3 (「<style> 本文」) が
#         独立に担う (この面を §11 に帰属させるのは虚偽の被覆表示 = 6b459e7 で自ら是正したクラスの再発)。
#     ★errata-3 M11 (round-3 major+minor 同根) で ★mode × 配置の実測表へ再是正する。 旧記述は mode を
#       pre-fill / --filled の 2 つしか数えておらず、 ★--artifact (usage 上の正式第 3 mode・他 pack では CI が landed
#       成果物へ使う) を残余分析から丸ごと落としていた。 §11 の --artifact 分岐は manifest 突合を ★走らせない ため、
#       body/comment 置きの対は「中身の有無」にも「既存 slot-id の rename」にも依らず §11 の観測面外になる
#       (worker 実弾・陽性対照付き: genuine filled を --artifact に渡すと rc=0 = 検体が正しいことを先に固定した上で、
#        中身つき pair / 既存 slot-id rename / <style> 隠蔽 のいずれも --artifact rc=0 で素通った)。
#     ▼ allowlist 例外 (data-prose-slot 隣接の対) の残余 — ★errata-4 M14 で ★mode ごとの「集合」へ書き分け。
#       ★errata-3 の書き方の誤り (本 errata で撤回): 「pre-fill 残余 ＋ --artifact ではこれに加えて…」という
#         ★加算形 で書いていたが実測と異なる。 pre-fill 残余に含まれる『空の対』は ★--artifact では §11 の
#         「prose スロットは全て充填 (空=0)」が捕捉する (rc=1・expected 25, got 24) ため加算にならない。
#         また pre-fill 残余には『既存 slot-id の rename』も含まれていた (errata-3 の列挙漏れ)。
#       ★worker 実測 (陽性対照付き・genuine は 3 mode とも rc=0 を先に固定した上で・検体は body 直下):
#         検体＼mode        pre-fill      --filled                --artifact
#         空の対            rc=0 素通り    rc=1 (注入不一致+充填)   rc=1 (「全て充填」が捕捉)
#         中身つき対        rc=1 (全て空)  rc=1 (注入不一致)        rc=0 素通り
#         既存 slot-id 改名  rc=0 素通り    rc=1 (注入不一致)        rc=0 素通り
#       ゆえ mode ごとの残余集合は:
#         pre-fill  残余 = { 空の対, 既存 slot-id の rename }
#         --filled  残余 = { }  (§11 の manifest 突合が全て捕捉)
#         --artifact 残余 = { 中身つき対, 既存 slot-id の rename }
#       ★errata-5 M16 (round-5 blocking root B) で ★配置別に量化して是正 (errata-4 の括弧註は 2 配置を一括りに
#         「3 mode とも §11 観測面外」と書いていたが、 これが真なのは片方だけ = 実測と乖離していた):
#         (i) make_body の ★空化領域 (<style> 本文): $BODY から消えるため 3 mode とも §11 は観測面外 →
#             ★arm-3a (差分形) が単独で担う。
#         (ii) ★comment 内 <style> テキスト: make_body は comment を verbatim 保存するので $BODY に ★現れる =
#             §11 の観測面 ★内 である。 実測 (worker): 空の対を置くと --filled / --artifact とも §11 の
#             「prose スロットは全て充填 (空=0)」が [FAIL] で捕捉する (rc=1)。 ゆえ arm-3b が ★追加で 閉じるのは
#             「§11 が落とさない組合せ」であり、 かつ close が ★literal </style> の場合に限る (構文形ゆえ)。
#             (test-adversarial-principle.sh の AN-H31/H32 註の記述が正で、 errata-4 の本註が誤りだった =
#              2 file 間の矛盾を本 errata で解消した。)
#       (p-N 値は mode にも属性名にも配置にも依らず arm-1 が捕捉するため、 残余はいずれも ★非 p-N 値に限られる。)
#     ★残余の帰属 (errata-4 M14 で是正): --artifact の 2 残余 (中身つき対 / rename) の根は folio-lq12 (節 anchor) でも
#       bin/folio 側述語でもなく、 ★§11 の --artifact 分岐が manifest を保持しない という構造にある (mode 設計上
#       --artifact は manifest を受け取らないため、 slot-id 集合の期待値を持てない)。 閉じ手は contract 導出の
#       期待集合と突合する形 (案 B 相当) になるが、 それは ★本処方 scope 外 と admin が明示裁定している (採らない)。
#       別 bead 化の提案は bd 申送り #2 (「--artifact mode の被覆非対称」・未起票・別 bead 推奨) として記録済み。
#       pre-fill 残余 (空の対 / rename) は folio-lq12 (節 anchor の contract 構造化) と bin/folio 側 substring 述語の
#       厳密化 (別 bead 申送り済) の領分。
#   ★上の「全 id census (余剰 id 0)」は 接尾属性を *原理的に* 見ない (lookbehind で属性名の真の先頭を要求する
#     = 正しい HTML 判定)。 ゆえ接尾面を担う arm は本 arm ただ 1 本であり、 「全 id census が別途担う」は誤り。
#   ★errata-3 M10 (round-3 major・実弾再現済): allowlist 側 alternative は ★case-exact (小文字 literal 固定) にする。
#     旧実装は regex 全体が /gi ゆえ allowlist 側も case-insensitive で、 <div DATA-PROSE-SLOT="x"
#     data-slot-id="s2-forged"> (allowlist 部分だけ大文字・接尾 id は小文字 = ★consumer から可視) が allowlist に
#     一致して余剰計数 0 → pre-fill / --artifact とも rc=0 で素通った (worker 独立再現: consumer grep -qF
#     'id="s2-forged"' = TRUE / 現行 count=0 / case-exact 化で count=1)。 §11 backstop は case-sensitive ゆえ
#     この shape に不発 = 「allowlist が backstop より緩い」非対称が穴の本体だった。
#     ★接尾 id 属性側 ([-A-Za-z0-9_:]+id) は /i のまま残す (大文字 ID= 等を数えるため = fail-closed 側)。
#     assembler は小文字しか emit しない (lib/common.sh:163,175 / assemble-principle.sh:306,338,346) ので
#     case-exact 化で genuine が落ちることはない (worker 実測: base / filled とも count=0)。
chk "p-N anchor: consumer substring 面の接尾 id 属性は prose slot 由来のみ (余剰 0)" "0" \
  "$(perl -CSD -0777 -ne '
     my $t=$_; my $c=0;
     while ($t =~ /(?:(?-i:data-prose-slot="[^"]*"\s+data-slot-id)|([-A-Za-z0-9_:]+id))\s*=\s*(?:"|\x27)/gi) {
       $c++ if defined $1;
     }
     print $c;' "$HTML")"
# ★arm-3 (配置面軸・errata-2 追補 round-4 major → ★errata-3 M9 で *領域 regex を廃し blinding 関数へ束縛* する形へ置換)。
#   ★round-3 critical (実弾再現済): 旧実装は領域を自前 regex m{<style[^>]*>(.*?)</style>}gsi で *再モデル* していたが、
#     make_body (lib/verify-common.sh:130-146) は close タグの junk が空白のみなら genuine 受理する
#     (`if ($junk =~ /\S/) { $fail = ... }` = `</style >` は合法扱いで本文を空化する)。 ゆえ `</style >` (空白 1 個) に
#     すると arm 側 regex だけが 0 match に落ち、 chk は「0 == 0」で ★恒真 PASS。 $BODY 基準の全 arm は空化ゆえ盲、
#     consumer は生ファイル grep で解決 = gate (h) 偽解決が pre-fill / --filled とも rc=0・[FAIL] 0 で成立した
#     (worker 独立再現: `</style >` + CSS コメント内 pair 形 payload → arm-3 count=0 / rc=0 / FAIL 0 / consumer TRUE)。
#   ★教訓 (partial-enumeration からの脱出): 「どの領域が隠蔽面か」を verify 側で *モデルし直す* 限り、 blinding を行う
#     関数 (make_body) の tolerance と verify の regex の差が新しい隠蔽面を生み続ける (whack-a-mole)。 ゆえ領域を
#     数え直すのをやめ、 ★blinding 関数そのものの出力へ束縛する: consumer 可視 id= 出現数を $HTML と $BODY
#     (= make_body の出力そのもの) の両方で数え、 ★差 0 を要求する。 make_body が空化する領域は close 書式にも
#     領域種別にも依らず *定義上すべて* この差に現れる (将来 make_body が別領域を空化するようになっても自動追随)。
#   ★偽 FAIL しないこと (genuine で両辺一致) は worker 実測: base.html = 38/38 / base-filled.html = 38/38。
#     (make_body は style 本文のみを落とし script は verbatim 保持・comment も保存するため genuine では差が出ない)。
#   ★make_body が fail-closed した場合は $BODY が空になり本 arm も差で落ちる (二重の fail-closed・矛盾しない)。
#   ★mode 非依存: $HTML / $BODY はどちらも mode に依らず作られるため pre-fill / --filled / ★--artifact の 3 mode
#     すべてで発火する (§11 の manifest 突合は --filled でしか走らない = 非対称。 対 MK は AN-H28 / AN-H30)。
id_visible_count() { # $1 = file → consumer 可視 (quote 付き) id= 出現数
  perl -CSD -0777 -ne 'my $c=0; $c++ while /id\s*=\s*(?:"|\x27)/gi; print $c;' "$1"
}
chk "p-N anchor: consumer 可視 id= 出現数が \$HTML == \$BODY (make_body 不可視域への隠蔽封鎖)" \
  "$(id_visible_count "$HTML")" "$(id_visible_count "$BODY")"
# ★arm-3b (構文領域軸・errata-4 M12 で ★復活・併置): 構文的な <style>…</style> テキスト領域の中の consumer 可視 id=。
#   ★errata-3 の誤り (本 errata で撤回): 上の差分 arm を入れた際、 旧 arm (本 arm) を「より広く引き継いだ」と註して
#     ★削除した。 これは superset 主張として偽であり、 実体は ★incomparable である (round-4 blocking):
#       - HTML comment は make_body が ★verbatim 保存する ため、 comment の中に <style>…</style> テキストを書き
#         その中へ pair を隠すと $HTML と $BODY の count が ★等しくなり 差分 arm は盲になる。
#       - 一方 本 arm は「<style> という文字列で切った領域」を見るため comment 内表記でも数える。
#     ★worker 独立再現 (round-4 実弾と一致): comment 内 <style> テキスト中の pair は consumer から可視
#       (grep -qF 'id="s2-forged"' = TRUE) でありながら、 差分 arm のみの実装では 中身つき対が --artifact rc=0 /
#       空の対が pre-fill rc=0 で素通った (= 407d7b0 比の ★検出退行)。 本 arm を戻すと どちらも count=1 で FAIL。
#   ★ゆえ 2 本は「置換」ではなく ★併置 する (検出力を単調増加させる・役割分担):
#       arm-3a (差分形)  = make_body が ★空化する領域 を close 書式 tolerance ごと追随して塞ぐ (領域名に非依存)。
#       arm-3b (構文形)  = ★構文的 <style> テキスト領域 を塞ぐ (comment 内表記を含む・close は literal 固定)。
#     どちらも他方の被覆に含まれない (comment 内 <style> は 3b のみ / `</style >` 変種は 3a のみ = 実測)。
#   ★errata-5 M16 (3) — ★合成 shape の残余開示 (2 arm とも観測面外・admin 裁定により ★閉じずに開示する):
#     comment 内 <style> テキスト ★× 非 canonical close (例 `</style >`) を重ねると、
#       - arm-3b は close が literal でないため 0 match (盲)、
#       - arm-3a は comment が verbatim 保存されるため $HTML == $BODY で差 0 (盲) =
#     ★2 本とも観測面外になり、 残るのは §11 だけである。 ゆえに残余は §11 の被覆と同じ ★mode × 中身 の構造を取る。
#     ★worker 実測 (consumer 可視 = grep -qF 'id="s2-forged"' TRUE を両検体で確認済):
#       合成 × 空の対      : pre-fill ★rc=0 (残余) / --filled rc=1 / --artifact rc=1   (§11 の充填 arm が捕捉)
#       合成 × 中身つき対  : pre-fill rc=1 / --filled rc=1 / --artifact ★rc=0 (残余)
#     ★処方の文言との差異 (実測を優先して書いた): 処方 M16(3) は「3 mode とも残余」と表現しているが、
#       ★同一検体が 3 mode すべてで残余になるわけではない (上表のとおり mode ごとに残余となる検体が入れ替わる)。
#       「2 arm とも観測面外」「各 mode に残余検体が存在する」は実測どおりで、 露出の大きさは既知残余クラス
#       (body 直下の allowlist 例外残余) と等価 = admin 裁定の前提は変わらない。
#     ★閉じない理由 (admin 裁定): arm-3b の close tolerance を寛容化すると §4c 検体Y の pin (arm-3b は
#       `</style >` に盲であること) が反転し whack-a-mole が再発する。 露出が批准済み残余クラスと等価ゆえ
#       ★開示で足りる。 bd 申送りへ「合成 shape (comment 内 <style> テキスト × 非 canonical close)」を追加済み。
#   ★genuine で偽 FAIL しないこと: base.html = 0 / base-filled.html = 0 (worker 再実測・genuine の <style> は
#     CSS 宣言のみで属性セレクタ [id="…"] すら持たない)。
chk "p-N anchor: <style> テキスト領域中の consumer 可視 id= 出現 0 (構文領域・comment 内表記を含む)" "0" \
  "$(perl -CSD -0777 -ne '
     my $t=$_; my $c=0;
     while ($t =~ m{<style[^>]*>(.*?)</style>}gsi) {
       my $s=$1; $c++ while $s =~ /id\s*=\s*(?:"|\x27)/gi;
     }
     print $c;' "$HTML")"
# ★以下は 2 本の arm が共通で塞ぐ面についての記述 (round-4 実弾の出典):
#   M4 で census / essence 群の入力は生ファイルへ切替えたが、 §11 (prose スロット) をはじめ $BODY 基準のまま残る節が
#   あり、 make_body が空化する領域 (現行実装では <style> 本文) が「どの $BODY 基準 arm からも見えないが consumer の
#   生ファイル grep からは見える」非対称面として残っていた (round-4 実弾: /* <div data-prose-slot="x"
#   data-slot-id="s2-forged">…</div> */ を <style> 内へ置くと pre-fill / --filled とも rc=0・[FAIL] 0 のまま
#   consumer grep -qF 'id="s2-forged"' が真 = gate (h) 偽解決)。 上の差分 arm はこの面を *領域名に言及せずに* 閉じる。
# ★essence source の行粒度束縛 (errata-1 M2): id="p-N" を含む行の集合が、 canonical な h3 形の行集合と
#   *完全一致* すること。 consumer (bin/folio:1468-1472) は行単位で essence を引くため、 id が正規形以外の行
#   (別容器・行頭 id・複数 id 同居) に現れた瞬間に essence の source 行が verify の想定とずれる。
#   ★行番号の抽出は id_attr_lines (census と同一境界述語) で行う。 grep -n 'id=' | grep -v 'data-…id=' 形は
#     *行内容* filter ゆえ「真の id と data-slot-id が同居する行」を丸ごと落とす (本リポの既知 gotcha)。
#   ★errata-2 M4: 両辺とも生ファイル基準にする (片辺だけ $BODY にすると make_body が <style> 本文を空化した分だけ
#     行番号が系統的にずれ、 比較そのものが成立しない)。
# ★folio-lq12: id を担う shape が 3 種になった (p-N の h3 / 節の <section id class> / 小節の <section id>)。
#   ★単一 regex へ潰さず ★per-shape の和 で束縛する (潰すと shape 間の穴 — 例: 節 anchor を h3 形で書けば
#   通る / 小節 anchor に class を足せば通る — が復活する)。 各 shape の ★件数も contract から個別に pin する。
pn_lines="$(grep -nE '<h3 class="ph" id="p-[0-9]+"><strong>' "$HTML" | cut -d: -f1)"
sec_lines="$(grep -nE '<section id="[a-z0-9-]+" class="(normative|informative)">' "$HTML" | cut -d: -f1)"
sub_lines="$(grep -nE '<section id="[a-z0-9-]+">' "$HTML" | cut -d: -f1)"
chk "anchor shape: p-N h3 行数 == |principles|"           "$(q '.principles | length')"                  "$(printf '%s\n' "$pn_lines" | grep -c . || true)"
chk "anchor shape: 節 <section id class> 行数 == |sections|" "$(q '.sections | length')"                    "$(printf '%s\n' "$sec_lines" | grep -c . || true)"
chk "anchor shape: 小節 <section id> 行数 == |subsections|"  "$(q '[.sections[].subsections[]?] | length')"  "$(printf '%s\n' "$sub_lines" | grep -c . || true)"
chk "anchor: id 行集合 == 3 shape の行集合の和 (essence source 行粒度)" \
  "$(printf '%s\n%s\n%s\n' "$pn_lines" "$sec_lines" "$sub_lines" | grep . | LC_ALL=C sort -n)" \
  "$(id_attr_lines < "$HTML" | LC_ALL=C sort -n)"

echo
echo "--- ★folio-lq12: 節骨格 (sections) + rich 運搬 (raw blob / mermaid / ai-rationale) の floor ---"
# tier-grouped (= assembler の emit 順 Always→Ask-first→Never) で principles の field を吐く helper。
# ★folio-lq12: 定義位置を §4 から ★ここへ前倒し した (下の ai-rationale arm が先に使うため)。 定義内容は不変。
tg_field() { local t; for t in Always Ask-first Never; do q '.principles[] | select(.tier=="'"$t"'") | '"$1"; done; }
# ★assemble-principle.sh は top-level 未知キーを拒否しない (禁止は cross_doc / outcome の 2 本のみ) ため、
#   contract に sections を足して ★emit を忘れても 無音で floor PASS しうる。 ゆえ本節は 双方向の等号
#   (contract→HTML の脱落 / HTML→contract の捏造 を ★両方) で束縛する。 片側包含は恒真化するので使わない。

# L1. 節骨格 — anchor / class / 順序 の双方向等号。
# ★行頭/行末 anchor を ★置かない: 行末に別要素が続く形 (…"></section></body> 等) の forged section が
#   shape arm から不可視になり、 「余剰 id census だけが撃つ」非対称を作るため (検出力は単調増加側に取る)。
act_sec_ids="$(grep -oE '<section id="[a-z0-9-]+" class="(normative|informative)">' "$HTML" | sed -E 's#<section id="([^"]*)".*#\1#')"
act_sec_cls="$(grep -oE '<section id="[a-z0-9-]+" class="(normative|informative)">' "$HTML" | sed -E 's#.*class="([^"]*)">#\1#')"
act_sub_ids="$(grep -oE '<section id="[a-z0-9-]+">' "$HTML" | sed -E 's#<section id="([^"]*)">#\1#')"
chk "sections: 節 id 列 == contract sections[].anchor (順序・双方向)" "$(q '.sections[].anchor')" "$act_sec_ids"
chk "sections: 節 class 列 == contract sections[].class (順序・双方向)" "$(q '.sections[].class')" "$act_sec_cls"
chk "sections: 小節 id 列 == contract subsections[].anchor (順序・双方向)" "$(q '.sections[].subsections[]?.anchor')" "$act_sub_ids"
set_eq "sections: 節 anchor 集合 == contract (脱落 0 / 捏造 0)" \
  "$(q '.sections[].anchor' | LC_ALL=C sort)" "$(printf '%s\n' "$act_sec_ids" | grep . | LC_ALL=C sort || true)"
set_eq "sections: 小節 anchor 集合 == contract (脱落 0 / 捏造 0)" \
  "$(q '.sections[].subsections[]?.anchor' | LC_ALL=C sort)" "$(printf '%s\n' "$act_sub_ids" | grep . | LC_ALL=C sort || true)"
# ★class は closed allowlist の 2 値のみ (未知 class の節が出れば上の 3 arm が同時に FAIL する形にしてあるが、
#   「class 属性を落とした節」は正規表現に一致せず 節 id 列が短くなる = 脱落として FAIL に倒れる)。
chk_empty "sections: contract class allowlist 外 0 (normative|informative)" \
  "$(q '.sections[].class' | grep -vxE 'normative|informative' | tr '\n' ' ')"

# L2. 文書前文 (preamble_html) の逐語 echo (RAW emit ゆえ byte 一致・容器はちょうど 1 個)。
chk "preamble: 容器 == 1" "1" "$(grep -c 'data-component="constitution-preamble"' "$BODY")"
# ★位置 arm (errata-1 E3(b)): 容器数と出現回数だけでは preamble を footer 直前へ ★移設 する改竄が rc=0 で
#   素通る (canonical では §0 の直前 = 全 section より前 にある前文ゆえ、 位置が意味の一部)。
chk "preamble: 最初の節より前に出現 (位置・canonical と同じ前文位置)" "before" \
  "$(perl -0777 -ne 'my $p = index($_, "data-component=\"constitution-preamble\""); my $s = index($_, "<section id=\""); print(($p >= 0 && $s >= 0 && $p < $s) ? "before" : "after-or-missing");' "$BODY")"
chk "preamble: 逐語 blob の出現 == 1 (RAW echo)" "1" \
  "$(V="$(q '.preamble_html')" perl -0777 -ne 'BEGIN{$v=$ENV{V}} my $c=0; $c++ while /\Q$v\E/g; print $c;' "$BODY")"

# L3. raw blob の逐語 echo (各 blob が ★ちょうど 1 回・脱落も重複も FAIL)。
# ★節ごとの ★容器等号 arm (admin gate errata-1 E3・blocking): 旧形は「各 blob が本文のどこかに 1 回出る」
#   + 「所属節が正しい」だけを見ていたため、 (a) 契約に無い p / aside / 素テキストの ★捏造追加 (b) preamble の
#   ★位置移設 (c) 節内 blocks の ★順序入替 が いずれも rc=0 で素通った (admin 実弾 3 本で実証)。
#   ゆえ ★節の rich 容器の inner を「当該節 blocks を contract 順に連結した文字列」と ★byte 等号 で突合する
#   (器序数束縛 errata-5 型)。 片側包含 (「含まれていれば OK」) は恒真化するので使わない。
#   ★mermaid は emit 形 (figure/pre/figcaption) を contract から再構成して連結する = 生成物を参照しない。
n_sec="$(q '.sections | length')"
# 生成物側: 各 section-body 容器の inner を、 その容器の ★所属節 とともに取り出す。
act_bodies="$(perl -CSD -0777 -ne '
  my $t=$_; my $cur="";
  while ($t =~ m{(<section id="([a-z0-9-]+)"(?: class="[^"]*")?>)|(<div data-component="constitution-section-body">\n(.*?)</div>\n)}gs) {
    if (defined $2) { $cur=$2 }
    elsif (defined $4) { my $inner=$4; $inner =~ s/\n/\x01/g; print "$cur\t$inner\n"; }
  }' "$BODY")"
sec_body_bad=""
for ((si_=0; si_<n_sec; si_++)); do
  anc_="$(q ".sections[$si_].anchor")"; nb_="$(q ".sections[$si_].blocks // [] | length")"
  exp_body=""
  for ((bi_=0; bi_<nb_; bi_++)); do
    case "$(q ".sections[$si_].blocks[$bi_].type")" in
      raw) exp_body+="$(q ".sections[$si_].blocks[$bi_].html")"$'\n' ;;
      mermaid)
        exp_body+='<figure data-component="principle-diagram" class="diagram"><pre class="mermaid">'
        first_=1
        while IFS= read -r l_; do [[ "$first_" -eq 1 ]] && first_=0 || exp_body+=$'\n'; exp_body+="$(esc "$l_")"; done \
          < <(q ".sections[$si_].blocks[$bi_].source_lines[]")
        exp_body+='</pre><figcaption>'"$(esc "$(q ".sections[$si_].blocks[$bi_].caption")")"'</figcaption></figure>'$'\n' ;;
    esac
  done
  [[ -n "$exp_body" ]] || continue
  act_body="$(awk -F'\t' -v a="$anc_" '$1==a { print $2 }' <<<"$act_bodies" | tr '\001' '\n')"
  [[ "$(printf '%s' "$exp_body")" == "$(printf '%s' "$act_body")" ]] || sec_body_bad+=" $anc_"
done
chk_empty "raw blob: 各節の rich 容器 inner == contract blocks の連結 (byte 等号・脱落/重複/捏造/順序/relocation を一括終端)" "$sec_body_bad"
chk "raw blob: 容器 (section-body) == rich を持つ節数" \
  "$(q '[.sections[] | select([.blocks[] | select(.type=="raw" or .type=="mermaid")] | length > 0)] | length')" \
  "$(grep -c 'data-component="constitution-section-body"' "$BODY")"
# ★占有数 pin: amp-step 以外の <li> は ★raw blob 由来ちょうど N 本 (raw blob に含まれる <li> の総数)。
#   これで「raw blob の外に li を捏造で足す」経路を数で挟む (§1 核心 list / §7 Citations の面)。
chk "raw blob: 非 amp-step の li 本数 == raw blob 内 li 総数" \
  "$(q '[.sections[].blocks[]? | select(.type=="raw") | .html] | join("")' | grep -o '<li>' | wc -l | tr -d ' ')" \
  "$(( $(grep -o '<li' "$BODY" | wc -l | tr -d ' ') - $(grep -o '<li class="amp-step">' "$BODY" | wc -l | tr -d ' ') ))"

# ★ai-rationale の所属原則 束縛 (relocation 封鎖): aside の出現行より前で最も近い p-N h3 が、 その rationale を
#   宣言した原則であることを要求する (件数・値列は原則をまたぐ入替えに対して不変ゆえ単独では素通る)。
owner_principle_of_line() { # $1 = 行番号 → その行より前で最も近い p-N h3 の anchor
  awk -v L="$1" '
    /<h3 class="ph" id="p-[0-9]+">/ {
      if (NR < L) { match($0, /id="p-[0-9]+"/); a = substr($0, RSTART+4, RLENGTH-5) }
    }
    END { print a }' "$BODY"
}
rat_owner_bad=""
while IFS= read -r _pid; do
  [[ -n "$_pid" ]] || continue
  _lc="$(printf '%s' "$_pid" | tr '[:upper:]' '[:lower:]')"
  _n="$(q '.principles[] | select(.id=="'"$_pid"'") | (.amended_by // []) | length')"
  for ((_k=0; _k<_n; _k++)); do
    [[ "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'] | has("rationale")')" == "true" ]] || continue
    _t="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'].rationale')")"
    _ln="$(grep -nF -- ">${_t}</aside>" "$BODY" | head -1 | cut -d: -f1)"
    _own="$(owner_principle_of_line "${_ln:-0}")"
    [[ "$_own" == "$_lc" ]] || rat_owner_bad+=" ${_pid}→${_own:-<なし>}"
  done
  if [[ "$(q '.principles[] | select(.id=="'"$_pid"'") | has("rationale_note")')" == "true" ]]; then
    _t="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .rationale_note.text')")"
    _ln="$(grep -nF -- ">${_t}</aside>" "$BODY" | head -1 | cut -d: -f1)"
    _own="$(owner_principle_of_line "${_ln:-0}")"
    [[ "$_own" == "$_lc" ]] || rat_owner_bad+=" ${_pid}(note)→${_own:-<なし>}"
  fi
done < <(tg_field '.id')
chk_empty "ai-rationale: 各 aside の所属原則 == contract 宣言原則 (relocation 封鎖)" "$rat_owner_bad"

# L4. mermaid (typed block) — 件数 / DSL round-trip / figcaption / vendor / init。
n_mer="$(q '[.sections[]?.blocks[]? | select(.type=="mermaid")] | length')"
chk "mermaid: figure 数 == |mermaid blocks|" "$n_mer" "$(grep -c 'data-component="principle-diagram"' "$BODY")"
chk "mermaid: pre.mermaid 数 == |mermaid blocks|" "$n_mer" "$(grep -c '<pre class="mermaid">' "$BODY")"
exp_mer=""; exp_mcap=""
for ((si_=0; si_<n_sec; si_++)); do
  nb_="$(q ".sections[$si_].blocks // [] | length")"
  for ((bi_=0; bi_<nb_; bi_++)); do
    [[ "$(q ".sections[$si_].blocks[$bi_].type")" == "mermaid" ]] || continue
    while IFS= read -r l_; do exp_mer+="$(esc "$l_")"$'\n'; done < <(q ".sections[$si_].blocks[$bi_].source_lines[]")
    exp_mer+='@@@'$'\n'
    exp_mcap+="$(esc "$(q ".sections[$si_].blocks[$bi_].caption")")"$'\n'
  done
done
# ★両辺とも末尾改行を落として比較する ($( ) は末尾改行を剥がすため、 期待側だけ生の変数を渡すと恒真 FAIL)。
chk "mermaid: DSL round-trip == esc(source_lines) (図ごと・順序)" "$(printf '%s' "$exp_mer")" \
  "$(perl -CSD -0777 -ne 'while (m{<pre class="mermaid">(.*?)</pre>}gs){ print "$1\n\@\@\@\n"; }' "$BODY")"
chk "mermaid: figcaption 列 == esc(caption) (順序)" "$(printf '%s' "$exp_mcap")" \
  "$(perl -CSD -0777 -ne 'while (m{<figure data-component="principle-diagram" class="diagram">.*?<figcaption>(.*?)</figcaption></figure>}gs){ print "$1\n"; }' "$BODY")"
# ★vendor 参照 path の literal pin (canonical constitution.html:24 と同形の ../assets/)。
#   ★gate F は HTML の親 dir を配信 root にするため assets/ と ../assets/ を区別できない = gate F green を
#     本 path の正しさの根拠に ★引用しない。 ゆえ静的 literal をここで直接 pin する。
chk "mermaid: vendor script == ../assets/mermaid.min.js (図>0 のとき 1 本)" \
  "$([[ "$n_mer" -gt 0 ]] && echo 1 || echo 0)" \
  "$(grep -cF '<script src="../assets/mermaid.min.js" defer></script>' "$HTML")"
chk "mermaid: vendor script 総数 == 期待 (assets/ 形などの別 path 0 本)" \
  "$([[ "$n_mer" -gt 0 ]] && echo 1 || echo 0)" \
  "$(grep -cE '<script src="[^"]*mermaid[^"]*"' "$HTML")"
chk "mermaid: initialize == 1 (図>0 のとき・図ゼロなら 0)" \
  "$([[ "$n_mer" -gt 0 ]] && echo 1 || echo 0)" "$(grep -c 'mermaid.initialize({' "$HTML")"

# L5. ai-rationale (canonical の <aside class="ai-rationale" hidden …> 相当) — 件数 / 既定非表示 / 値。
n_rat="$(( $(q '[.principles[].amended_by[]? | select(has("rationale"))] | length') + $(q '[.principles[] | select(has("rationale_note"))] | length') ))"
chk "ai-rationale: 件数 == Σ(amended_by.rationale) + |rationale_note|" "$n_rat" \
  "$(grep -c 'data-component="principle-ai-rationale"' "$BODY")"
# ★hidden 属性 == 件数 (生成物は common.css を link しないため、 既定非表示は ★hidden 属性の UA 既定に依存する。
#   hidden を落とすと rationale が全て可視化して人間層の読書体験が壊れる = P-14 面の退行ゆえ本数で pin する)。
chk "ai-rationale: hidden 属性 == 件数 (既定非表示・可視化退行の封鎖)" "$n_rat" \
  "$(grep -c 'data-component="principle-ai-rationale" class="ai-rationale" hidden ' "$BODY")"
# ★期待値を ★@tsv で作らない (cell-quality round-1 confirmed): yq の @tsv は値に " を含む field を CSV quote
#   する (全体を "…" で括り内部の " を "" へ倍化) ため、 P-2 の rationale が 6 文字の捏造つきで期待値にも
#   実測値にも同時に入り ★両側同時退行で vacuous PASS していた。 index 指定の単値取得で両側とも素の値を取る。
exp_rat=""
while IFS= read -r _pid; do
  [[ -n "$_pid" ]] || continue
  _n="$(q '.principles[] | select(.id=="'"$_pid"'") | (.amended_by // []) | length')"
  for ((_k=0; _k<_n; _k++)); do
    [[ "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'] | has("rationale")')" == "true" ]] || continue
    exp_rat+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'].adr')")"$'\t'
    exp_rat+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'].date')")"$'\t'
    exp_rat+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'].approved_by')")"$'\t'
    exp_rat+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .amended_by['"$_k"'].rationale')")"$'\n'
  done
done < <(tg_field '.id')
chk "ai-rationale: 改訂来歴形 (adr,date,by,text) == contract (tier順・@tsv 非経由)" \
  "$(printf '%s' "$exp_rat")" \
  "$(perl -CSD -0777 -ne 'while (/<aside data-component="principle-ai-rationale" class="ai-rationale" hidden data-decision="([^"]*)" data-adr="([^"]*)" data-decision-by="([^"]*)">(.*?)<\/aside>/gs){ print "$2\t$1\t$3\t$4\n"; }' "$BODY")"
exp_rnote=""
while IFS= read -r _pid; do
  [[ -n "$_pid" ]] || continue
  [[ "$(q '.principles[] | select(.id=="'"$_pid"'") | has("rationale_note")')" == "true" ]] || continue
  exp_rnote+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .rationale_note.for')")"$'\t'
  exp_rnote+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .rationale_note.decided')")"$'\t'
  exp_rnote+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .rationale_note.text')")"$'\n'
done < <(tg_field '.id')
chk "ai-rationale: 補足形 (for,decided,text) == contract rationale_note (tier順・@tsv 非経由)" \
  "$(printf '%s' "$exp_rnote")" \
  "$(perl -CSD -0777 -ne 'while (/<aside data-component="principle-ai-rationale" class="ai-rationale" hidden data-rationale-for="([^"]*)" data-decided="([^"]*)">(.*?)<\/aside>/gs){ print "$1\t$2\t$3\n"; }' "$BODY")"
# ★独立 oracle (両側同時退行の封鎖): 上の 2 arm は「contract 由来の期待」対「生成物」の相対突合ゆえ、 抽出経路が
#   両側で同時に壊れると vacuous PASS しうる (実際 @tsv 経路で起きた)。 ★凍結 census (canonical 由来の literal)
#   の RATIONALE 行の値が、 生成物の aside 本文へ esc しただけの形で ★literal 出現することを直接要求する。
if [[ -f "$FROZEN_CENSUS" ]]; then
  rat_miss=""
  while IFS=$'\t' read -r _t _rid _rtext; do
    [[ "$_t" == "RATIONALE" ]] || continue
    grep -qF ">$(esc "$_rtext")</aside>" "$BODY" || rat_miss+=" $_rid"
  done < <(grep -P '^RATIONALE\t' "$FROZEN_CENSUS")
  chk_empty "ai-rationale: 凍結 census の本文が生成物へ literal 出現 (相対突合の外側 oracle)" "$rat_miss"
fi

echo
echo "--- ★folio-lq12 S4(B): 忠実抽出の機械証明 (凍結 census × canonical byte 包含) ---"
# ★oracle ゼロの是正。 constitution 用 extractor は存在せず (extract-* 5 本は他 spec 用・かつ header に
#   「人間レビュー前提 DRAFT」と明記)、 canonical 突合の byte gate (verify-canonical-drift.sh 等) は flip 後
#   専用ゆえ本 pack では起動しない。 census-guard.sh も KNOWN_SPECS 固定で principle contract を受けない。
#   ゆえ admin 裁定で ★(B) frozen census + byte 包含 arm を採る (ADR-0053 policy A・self-spec.frozen-census.txt 先例同型)。
# ★2 本の独立 oracle:
#   (1) 凍結 literal (spec-origin/constitution.frozen-census.txt) ⟷ contract 導出タプルの逐語一致
#       — contract 側の手書き drift を捕捉する。 census は contract からも生成物からも導出しない。
#   (2) 凍結 literal の各逐語値が ★canonical に byte 包含されること — canonical 側の drift を捕捉する。
#   ★正規化は 改行と各行の先頭空白の除去のみ (語句正規化を禁止)。
# (FROZEN_CENSUS / CANONICAL_SRC の定義は本 file 冒頭へ前倒し済 — §L の rationale literal arm が先に使うため。)
# contract から census と ★同形・同順 のタプル列を導出する (census 側の並びが SSoT)。
census_from_contract() {
  local i j nb nsub anc
  printf 'COUNT\tsection\t%s\n'    "$(q '.sections | length')"
  printf 'COUNT\tsubsection\t%s\n' "$(q '[.sections[].subsections[]?] | length')"
  printf 'COUNT\tblob\t%s\n'       "$(q '[.sections[].blocks[]? | select(.type=="raw")] | length')"
  printf 'COUNT\tmermaid\t%s\n'    "$(q '[.sections[].blocks[]? | select(.type=="mermaid")] | length')"
  printf 'COUNT\trationale\t%s\n'  "$(( $(q '[.principles[].amended_by[]? | select(has("rationale"))] | length') + $(q '[.principles[] | select(has("rationale_note"))] | length') ))"
  printf 'VERSION\t%s\n' "$(q '.meta.version')"
  printf 'STATUS\t%s\n'  "$(q '.meta.status')"
  printf 'PREAMBLE\t%s\n' "$(q '.preamble_html')"
  local n; n="$(q '.sections | length')"
  for ((i=0; i<n; i++)); do
    printf 'SECTION\t%s\t%s\t%s\t%s\n' "$((i+1))" "$(q ".sections[$i].anchor")" "$(q ".sections[$i].class")" "$(q ".sections[$i].heading")"
  done
  local sn=0
  for ((i=0; i<n; i++)); do
    nsub="$(q ".sections[$i].subsections // [] | length")"
    for ((j=0; j<nsub; j++)); do
      sn=$((sn+1)); printf 'SUBSECTION\t%s\t%s\t%s\n' "$sn" "$(q ".sections[$i].subsections[$j].anchor")" "$(q ".sections[$i].subsections[$j].heading")"
    done
  done
  for ((i=0; i<n; i++)); do
    anc="$(q ".sections[$i].anchor")"; nb="$(q ".sections[$i].blocks // [] | length")"
    for ((j=0; j<nb; j++)); do
      case "$(q ".sections[$i].blocks[$j].type")" in
        raw) printf 'BLOB\t%s\t%s\t%s\n' "$anc" "$j" "$(q ".sections[$i].blocks[$j].html")" ;;
        mermaid)
          printf 'MCAPTION\t%s\t%s\t%s\n' "$anc" "$j" "$(q ".sections[$i].blocks[$j].caption")"
          local li=0 l
          while IFS= read -r l; do li=$((li+1)); printf 'MERMAID\t%s\t%s\t%02d\t%s\n' "$anc" "$j" "$li" "$l"; done < <(q ".sections[$i].blocks[$j].source_lines[]")
          ;;
      esac
    done
  done
  q '.principles[] | .id as $pid | (.amended_by // [])[] | select(has("rationale")) | "RATIONALE\t" + $pid + "\t" + .rationale'
  q '.principles[] | select(has("rationale_note")) | "RATIONALE\t" + .id + "\t" + .rationale_note.text'
}
if [[ ! -f "$FROZEN_CENSUS" ]]; then
  printf '  [FAIL] %-'"$CHKW"'s %s\n' "frozen census 不在 (忠実抽出の機械証明が無被覆)" "$FROZEN_CENSUS"; fail=1
else
  chk "census: contract 導出タプル == 凍結 literal (contract 側 drift)" \
    "$(grep -v '^#' "$FROZEN_CENSUS" | grep -v '^[[:space:]]*$')" "$(census_from_contract)"
  # ★(e) 無主地帯 = doc-header の版 meta は cover が担う。 その値の逐語一致を凍結 literal で束縛する。
  chk "census: contract .meta.version == 凍結 literal" \
    "$(grep -P '^VERSION\t' "$FROZEN_CENSUS" | cut -f2)" "$(q '.meta.version')"
  chk "census: contract .meta.status == 凍結 literal" \
    "$(grep -P '^STATUS\t' "$FROZEN_CENSUS" | cut -f2)" "$(q '.meta.status')"
  if [[ ! -f "$CANONICAL_SRC" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s %s\n' "canonical 不在 (byte 包含 arm が実行不能)" "$CANONICAL_SRC"; fail=1
  else
    # ★flip 後 (canonical が本 pack の生成物へ置換された後) は本 arm が両側同時退行しうる = 独立 anchor では
    #   なくなる。 その事実を ★明示表示 する (黙って弱い arm を [OK] と表示するのは虚偽の被覆表示)。 census 側
    #   (1) は凍結 literal ゆえ flip 後も独立 anchor として有効。
    if grep -qF 'content="folio principle-pack assembler' "$CANONICAL_SRC"; then
      echo "  [NOTE] canonical は本 pack の生成物 (flip 済) — byte 包含 arm は両側同時退行しうるため独立 anchor ではない。凍結 census (1) が単独 anchor。"
    fi
    # ★検査本体と件数を ★同一 invocation から取る (admin gate errata-1 E1・blocking):
    #   旧形は canon_checked を ★別 perl で census file を数え直すだけだったため、 検査本体の dispatch を
    #   全潰し ({ next }) にしても件数は 59 のまま [OK] に落ちる ★恒真 arm だった (admin 実弾で実証済)。
    #   ゆえ「実際に index() 比較を実行した回数」を END で emit させ、 それを突合する。 census file を
    #   ★別 invocation / grep で再カウントする構造は禁止 (再カウントは検査の実施を証明しない)。
    canon_out="$(CANON="$CANONICAL_SRC" perl -ne '
      BEGIN { open(my $f,"<",$ENV{CANON}) or die "canon open"; local $/; my $c=<$f>; close $f;
              $c =~ s/^[ \t]+//mg; $c =~ s/\n//g; our $C=$c; our $n=0; }
      next if /^#/ || /^[ \t]*$/;
      chomp; my @f=split(/\t/,$_,-1); my $t=shift @f; my ($v,$k);
      if    ($t eq "PREAMBLE")   { $v=$f[0]; $k="preamble" }
      elsif ($t eq "SECTION")    { $v=$f[3]; $k="section:$f[1]" }
      elsif ($t eq "SUBSECTION") { $v=$f[2]; $k="subsection:$f[1]" }
      elsif ($t eq "BLOB")       { $v=$f[2]; $k="blob:$f[0]#$f[1]" }
      elsif ($t eq "MCAPTION")   { $v=$f[2]; $k="mcaption:$f[0]#$f[1]" }
      elsif ($t eq "MERMAID")    { $v=$f[3]; $k="mermaid:$f[0]#$f[1]L$f[2]" }
      elsif ($t eq "RATIONALE")  { $v=$f[1]; $k="rationale:$f[0]" }
      else { next }
      $v =~ s/^[ \t]+//;
      $n++;                                   # ★比較を実行した回数 (dispatch を痩せさせると必ず減る)
      print "MISS\t$k\n" unless index($C,$v) >= 0;
      END { print "CHECKED\t$n\n" }
    ' "$FROZEN_CENSUS")"; canon_rc=$?
    # ★tool error fail-open の封鎖: perl が途中で死ぬと出力が空 (= miss なし) になり chk_empty が無音 PASS する。
    #   exit status を先に判定し、 非 0 は「照合不能」として FAIL に倒す。
    if [[ $canon_rc -ne 0 ]]; then
      printf '  [FAIL] %-'"$CHKW"'s (perl exit %s)\n' "census: byte 包含の照合が異常終了 (照合不能 = fail-closed)" "$canon_rc"; fail=1
    fi
    canon_miss="$(sed -n 's/^MISS\t//p' <<<"$canon_out" | tr '\n' ' ')"
    canon_checked="$(sed -n 's/^CHECKED\t//p' <<<"$canon_out")"
    chk_empty "census: 全逐語値が canonical に byte 包含 (改行+先頭空白のみ正規化)" "$canon_miss"
    chk "census: 検査本体が実行した比較回数 == 凍結 census の値行数 (恒真封鎖)" \
      "$(grep -v '^#' "$FROZEN_CENSUS" | grep -Pc '^(PREAMBLE|SECTION|SUBSECTION|BLOB|MCAPTION|MERMAID|RATIONALE)\t')" \
      "${canon_checked:-(CHECKED 行なし)}"
  fi
fi

# 2. id 一意性 + tier allowlist 再導出
chk_empty "principle id 一意"  "$(q '.principles[].id' | sort | uniq -d | tr '\n' ' ')"
chk_empty "tier allowlist {Always,Ask-first,Never}" "$(q '.principles[].tier' | grep -vxE 'Always|Ask-first|Never' | tr '\n' ' ')"

# 3. ★①終端強制: principle は照会終端ゆえ前方照会 chip を持たない (inbound = data-inbound-* は受ける照会ゆえ別物・許可)。
chk "終端: HTML に前方照会 chip 無し (leads_to/justifies/resolved_by/cross-doc-*)" "0" \
  "$(grep -cE 'data-leads-to=|data-justifies|data-resolved-by=|cross-doc-leads-chip|cross-doc-ref-chip' "$BODY")"

# 4. within-doc 可視 id / heading 順序 (assembler の emit 順 = tier-grouped: Always→Ask-first→Never・各 tier 内は contract 配列順)。
#    ★contract 配列が tier 順でなくても assembler に一致させる (順序検証 robustness)。 tier 改竄は §13 baseline-diff が単独で捕捉。
# (tg_field の定義は folio-lq12 で §L へ前倒し済 — ここでは使うだけ。)
exp_pid="$(tg_field '.id')"
exp_heading="$(tg_field '.heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
chk "within-doc: 可視 pid 列 == principles(tier順).id" \
  "$exp_pid" \
  "$(grep -oE '<span class="pid">[^<]*</span>' "$BODY" | sed -E 's#<span class="pid">([^<]*)</span>#\1#')"
# ★folio-lffq: h3.ph は navigable id (id="p-N") を担い、 中身は canonical と同形の <strong>P-N: heading</strong>。
#   可視 heading は strong の中から取り出す (opener の literal を id 込み形へ更新 = 下の隣接 chk と対で緩めない)。
chk "within-doc: 可視 heading 列 == principles(tier順).heading" \
  "$exp_heading" \
  "$(perl -CSD -0777 -ne 'while (/<h3 class="ph" id="p-[0-9]+"><strong>([^<]*)<\/strong><\/h3>/g){ my $t=$1; $t =~ s/^P-[0-9]+: //; print "$t\n"; }' "$BODY")"
# pid→heading 隣接 (id span 直後に heading が来る = 後置平文偽 id を捕捉)。
# ★opener literal に id="p-N" を含めたまま数える (緩めない): pid span と h3 の *隣接* が崩れると count が
#   |principles| を下回り FAIL に倒れる (pattern 厳格化方向ゆえ id を足しても検出力は落ちない)。
#   本 arm の帰属付き MK = AN-H9 (pid span と h3 の間へ要素を差し込む改竄)。 後置平文偽 id (`P-1` を素のテキストで
#   後ろに置く手口) は *別 arm* (可視 pid 列) が KILL する (MK=AN-H7・帰属 reason も「可視 pid」)。
#   ★2 つを 1 つの MK が撃っているかのように書かない (虚偽の被覆表示は本リポの既知 blocking クラス)。
chk "within-doc: pid→ph 隣接 == |principles|" "$(q '.principles | length')" \
  "$(grep -oE '<span class="pid">[^<]*</span><h3 class="ph" id="p-[0-9]+">' "$BODY" | wc -l | tr -d ' ')"
# ★per-row 束縛 (relocation クラスの構造終端): 上の隣接 chk は *件数* しか見ないため、 row 間で id 属性だけを
#   入れ替える改竄 (p-1↔p-2 swap) は id 集合・件数・全 id census・可視 pid 列・可視 heading 列・strong 全文列の
#   すべてが不変のまま素通る (assembler 側の emit 退行でも repro-build は同一 assembler の再生成ゆえ構造的に盲目)。
#   実害: folio_xref_essence (bin/folio:1468-1472) は「id="p-N" を含む *行* の最初の strong」を返すため、 xref
#   tooltip の SSoT と inbound #p-N の着地先が原則単位で入れ替わる = 本 pack が塞いだはずの無言の死が再び開く。
#   ゆえ pid 値 ↔ id 値を tier 順の *対* で突合する (集合でも件数でもなく per-row 対応そのものを束縛する)。
exp_pid_anchor="$(tg_field '.id' | while IFS= read -r v; do [[ -n "$v" ]] || continue; \
  printf '%s\t%s\n' "$(esc "$v")" "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"; done)"
chk "within-doc: pid↔id 対 == (id, lc(id)) 列 (relocation 封鎖)" "$exp_pid_anchor" \
  "$(grep -oE '<span class="pid">[^<]*</span><h3 class="ph" id="p-[0-9]+">' "$BODY" \
     | sed -E 's#<span class="pid">([^<]*)</span><h3 class="ph" id="(p-[0-9]+)">#\1\t\2#')"
# ★可視 strong 全文 == "P-N: heading" (canonical constitution.html の <strong>P-N: TITLE</strong> と同形)。
#   heading 単独の chk (上) は strong 内の P-N: 前置を剥がしてから比較するため、 前置 id の *偽装* (P-1 の行に
#   <strong>P-99: …</strong>) を見逃す。 前置 id を含む全文で束縛する。
#   ★errata-1 M1: 本 chk は *h3 内* strong の per-row pin であって consumer 述語の pin ではない
#     (h3 に anchor するため p-head 行の *より前方* に置かれた decoy strong を見ない)。 consumer 述語そのものは
#     直下の「essence: consumer 述語複製」arm が担う。 2 つを 1 つが兼ねるかのように書かない (虚偽の被覆表示の禁)。
exp_strong="$(tg_field '.id + ": " + .heading' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
chk "within-doc: h3 strong 全文 == 「P-N: heading」(tier順)" "$exp_strong" \
  "$(grep -oE '<h3 class="ph" id="p-[0-9]+"><strong>[^<]*</strong></h3>' "$BODY" | sed -E 's#.*<strong>([^<]*)</strong>.*#\1#')"

# ★errata-1 M1 (admin gate B1+B3・parser-differential = 既知 r8k クラス): consumer 述語の *逐語複製* arm。
#   bin/folio:1468-1472 の folio_xref_essence は「id="p-N" を *含む行* の **最初の** <strong>…</strong>」を取り、
#   先頭の ^[A-Z]+-[0-9]+:[[:space:]]* を剥がした文字列を essence として返す。 上の h3 anchored な chk は
#   <h3 …><strong> という *位置* に縛られるため、 同じ p-head 行の pid span より前に decoy strong を挿し込むと
#   consumer は decoy を読むのに floor は全 OK のまま通る (essence 乗っ取り・admin 実測)。
#   ゆえ「consumer が実際に返す値」を同一 awk で再現し、 contract の .heading (HTML は escape 済ゆえ esc 適用) と
#   14/14 の byte 一致 + 空 0 件を要求する。 ★bin/folio は 1 byte も触らない (述語をこちら側へ複製するだけ)。
#   ★errata-2 M4: 走査対象を $BODY から ★生ファイル ($HTML) へ切替。 consumer は生ファイルを行走査するため、
#     make_body が空化する <style> 本文へ decoy strong を置くと $BODY 基準では見えず floor 全緑のまま essence が
#     乗っ取られた (admin ceiling 実弾)。 安全性は実測済 (genuine の <style> 433 行に strong / id 様トークン 0)。
essence_consumer() { # $1 = lc(id) → consumer と同一述語で essence を stdout
  awk -v id="$1" 'index($0,"id=\"" id "\"")>0 {
      if (match($0,/<strong>[^<]*<\/strong>/)) { print substr($0,RSTART+8,RLENGTH-17); exit }
    }' "$HTML" | sed -E 's/^[A-Z]+-[0-9]+:[[:space:]]*//'
}
exp_ess=""; act_ess=""; ess_empty=0
while IFS= read -r _pid; do
  [[ -n "$_pid" ]] || continue
  _lc="$(printf '%s' "$_pid" | tr '[:upper:]' '[:lower:]')"
  _got="$(essence_consumer "$_lc")"
  [[ -n "$_got" ]] || ess_empty=$((ess_empty+1))
  exp_ess+="$(esc "$(q '.principles[] | select(.id=="'"$_pid"'") | .heading')")"$'\n'
  act_ess+="${_got}"$'\n'
done < <(tg_field '.id')
chk "essence: consumer 述語複製 (id 行の最初の strong) == esc(.heading) 14/14" "$exp_ess" "$act_ess"
chk "essence: 空 essence 0 件 (gate (i) の無言 skip 経路を封鎖)" "0" "$ess_empty"
# ★p-head 行あたりの strong 出現数 == 1: consumer は「最初の strong」しか見ないため、 2 個目以降を足す改竄は
#   値の比較だけでは検出しきれない形が残る (前方 decoy は上の複製 arm が、 後方 decoy はこの本数 pin が撃つ)。
#   ★errata-2 M4: 本 arm も生ファイル基準 (上と同一論拠 = consumer は生を読む)。
chk "essence: p-head 行あたり strong 出現数 == 1 (前方/後方 decoy の封鎖)" \
  "$(q '.principles | length')" \
  "$(grep -E '<div class="p-head">' "$HTML" | grep -o '<strong>' | wc -l | tr -d ' ')"

# 4b. ★band 見出し fidelity (folio-c5r.2): tier/amendment の band h2 は contract .chapters.* 由来
#     (instance#4 焼き込み見出しが 2nd instance に偽件数を表示する hardcode の封鎖・c5r.3 footer と同根)。
#     versioning/inbound/glossary の h2 は pack 不変文言を pin (assembler drift 検出)。
BAND_H2S="$(grep 'data-component="chapter-deck-band"' "$BODY" | sed -E 's#.*<h2>([^<]*)</h2>.*#\1#')"
# 章帯の kicker (= canonical 節見出しを逐語で載せる面)。 ico() の svg を挟むため svg 終端以降を取る。
BAND_KICKERS="$(perl -CSD -0777 -ne 'while (/<span class="kicker">.*?<\/svg>\s*(.*?)<\/span>/gs){ print "$1\n"; }' "$BODY")"
# ★folio-lq12: 位置 index の literal 付替 (band_h2_at 1..7 → 1..13) を ★禁止 する (c5r.2 の「instance 固有値を
#   code に焼かない」と同根)。 期待列そのものを contract から決定的に導出し、 列として突合する。
#   ★h2 (友好見出し) の出所は 3 系: sections[].chapter_heading / chapters.<chapters_key> / pack 不変文言 2 本。
#   ★kicker (canonical 節見出し) の出所は 2 系: sections[].heading・subsections[].heading / pack 不変文言 2 本。
#   ★band の emit 順は build() の構造 (節配列順・§2 の中に tier 小節・末尾に inbound/用語集) と一致する。
PACK_BAND_H2=("原則は照会の終端 — 受ける照会だけをここに示す" "本文に出てくる専門語のやさしい説明")
PACK_BAND_KICKER=("この憲法を参照する文書 / inbound" "用語集 / この文書で使う専門語")
derive_expected_bands() { # $1 = h2|kicker
  local i n k ck nsub j
  n="$(q '.sections | length')"
  for ((i=0; i<n; i++)); do
    if [[ "$1" == "h2" ]]; then
      k="$(q ".sections[$i].chapter_heading // \"\"")"
      [[ -n "$k" && "$k" != "null" ]] || k="$(q ".chapters.$(q ".sections[$i].chapters_key")")"
    else
      k="$(q ".sections[$i].heading")"
    fi
    esc "$k"; printf '\n'
    nsub="$(q ".sections[$i].subsections // [] | length")"
    for ((j=0; j<nsub; j++)); do
      if [[ "$1" == "h2" ]]; then
        case "$(q ".sections[$i].subsections[$j].tier")" in
          Always)    ck=always ;;
          Ask-first) ck=ask_first ;;
          *)         ck=never ;;
        esac
        k="$(q ".chapters.${ck}")"
      else
        k="$(q ".sections[$i].subsections[$j].heading")"
      fi
      esc "$k"; printf '\n'
    done
  done
  if [[ "$1" == "h2" ]]; then printf '%s\n' "${PACK_BAND_H2[@]}"; else printf '%s\n' "${PACK_BAND_KICKER[@]}"; fi
}
chk "band h2 列 == contract 導出 (章順・literal index なし)"     "$(derive_expected_bands h2)"     "$BAND_H2S"
chk "band kicker 列 == canonical 節見出し (章順・逐語)"          "$(derive_expected_bands kicker)" "$BAND_KICKERS"
chk "band 章数 == |sections| + |subsections| + pack 固定 2"      \
  "$(( $(q '.sections | length') + $(q '[.sections[].subsections[]?] | length') + 2 ))" \
  "$(printf '%s\n' "$BAND_H2S" | grep -c . || true)"
# ★数詞 == 派生実件数 (件数は machine floor の領分・verification §3.9)。 HTML h2 == contract は上で一致済ゆえ
#   contract 側の値で判定する (assemble-principle validate と detect↔remediate parity)。
#   ★ASCII 半角の「N 原則 / N ステップ」を必須とする肯定形 (c5r.2 ceiling round1): 数詞なし = 不合格に倒す
#   (漢数字「九 原則」等の回避表記は「必須数詞なし」で一律 FAIL・回避表記の blocklist 列挙をしない)。
band_numchk() { # $1=label $2=heading-text $3=unit-literal $4=expected-count
  local n; n="$(grep -oE "[0-9]+[[:space:]]*$3" <<<"$2" | grep -oE '[0-9]+' | head -1 || true)"
  chk "$1" "$4" "${n:-(ASCII 数詞なし=半角必須)}"
}
# 全角数字は数詞照合を素通りする表記ゆえ chapters 値では禁止 (assemble と parity・照合回避封鎖)。
# (★bracket 式 [０-９] は C locale で multibyte を byte 分解し誤 match するため、 明示 alternation で locale 非依存に)
chk "band 数詞: chapters.* に全角数字なし" "0" \
  "$(q '[.chapters.always, .chapters.ask_first, .chapters.never, .chapters.amendment] | join("\n")' | grep -cE '０|１|２|３|４|５|６|７|８|９' || true)"
band_numchk "band 数詞: chapters.always「N 原則」== Always 実件数"       "$(q '.chapters.always')"    '原則'     "$(q '[.principles[] | select(.tier=="Always")] | length')"
band_numchk "band 数詞: chapters.ask_first「N 原則」== Ask-first 実件数" "$(q '.chapters.ask_first')" '原則'     "$(q '[.principles[] | select(.tier=="Ask-first")] | length')"
band_numchk "band 数詞: chapters.never「N 原則」== Never 実件数"         "$(q '.chapters.never')"     '原則'     "$(q '[.principles[] | select(.tier=="Never")] | length')"
band_numchk "band 数詞: chapters.amendment「N ステップ」== steps 実件数" "$(q '.chapters.amendment')" 'ステップ' "$(q '.amendment.steps | length')"

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
# ★folio-bur: am-meta 可視テキスト (改訂日付 · 承認者) == contract 再導出 (tier 順)。 data-amended-adr/可視 <b> は pin 済だが
#   am-meta (日付・承認者) は未検査ゆえ「(9999-99-99 · FORGED)」等の改訂来歴捏造が素通った (folio-bur audit 実証)。
exp_am_bur="$(tg_field '(.amended_by // [])[] | "(" + .date + " · " + .approved_by + ")"' | while IFS= read -r v; do esc "$v"; printf '\n'; done)"
act_am_bur="$(grep -oE '<span class="am-meta">[^<]*</span>' "$BODY_NC" | sed -E 's#<span class="am-meta">([^<]*)</span>#\1#')"
chk "within-doc: 可視 am-meta == (date · approved_by) (tier順)" "$exp_am_bur" "$act_am_bur"
# ★folio-bur round-2 (ceiling-recursion 是正): 上の可視 chk は double-quote 固定 grep ゆえ comment-hidden decoy
#   (`<span class='am-meta'>FORGED</span><!--<span class="am-meta">CORRECT</span>-->`) で素通る (独立 ceiling 実証)。
#   quote-robust 占有数パリティ (count_attr_token は comment 内 genuine + 可視 forged を両方数え +1 で FAIL に倒す)。

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
  "$(grep -oE '<li class="amp-step">[^<]*</li>' "$BODY" | sed -E 's#<li class="amp-step">([^<]*)</li>#\1#')"

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
    # ★folio-bur: 照会元/role の可視テキスト echo (visible-text-vs-attribute・chip emit = .inbound[] 配列順)。
    #   (a) ib-from: 照会元 — *対応属性が無く* 可視層が唯一の検証点ゆえ contract .inbound[].from へ直接束縛 (HIGH)。
    chk "within-doc: 可視 ib-from == .inbound[].from (順序)" "$(qesc '.inbound[].from')" "$(grep -oE '<span class="ib-from">[^<]*</span>' "$BODY_NC" | sed -E 's#<span class="ib-from">([^<]*)</span>#\1#')"
    #   (b) ib-role: 可視 role — data-inbound-role は verify_cross_doc_refs で contract pin 済ゆえ 可視==contract.role で transitively 封鎖。
    chk "within-doc: 可視 ib-role == .inbound[].role (順序)" "$(q '.inbound[].role')" "$(grep -oE '<span class="ib-role">[^<]*</span>' "$BODY_NC" | sed -E 's#<span class="ib-role">([^<]*)</span>#\1#')"
    # ★folio-bur round-2 (ceiling-recursion 是正): ib-from/ib-role の可視 chk も double-quote 固定ゆえ comment-hidden/single-quote
    #   decoy で素通る (独立 ceiling 実証)。 quote-robust 占有数パリティで decoy の +1 を捕捉 (ib-from は対応属性が無く唯一の検証点ゆえ特に重要)。
  fi
fi



echo
# ---- gate F: render 健全性 (visual) cross-pack 展開 (folio-vuf A・helper=render_gate_f)。
#      生成 HTML を light/dark × 3 viewport で render-gate。 fail-closed (violation/crash = $fail=1・T7 guard 維持)。
#      ★folio-lq12 訂正: 旧コメントの「mermaid 検出時は honest SKIP (B 段へ defer)」は ★stale で偽 —
#        B 段 (folio-jyfh) で実 render へ変更済で、 lib/verify-common.sh:584-587 が mermaid を検出したら
#        vendor を配信 root へ staging し SVG settle polling 込みで ★実 render する (SKIP しない)。
#        本 pack は folio-lq12 で図 2 枚を持つようになったため、 この記述の誤りは実害に直結する。 ----
render_gate_f "$HTML" "PRINCIPLE_SKIP_RENDER"

if [[ "$fail" -eq 0 ]]; then
  bd_note=""; [[ "$DOC_TYPE" == "constitution" ]] && bd_note=" + 終端 + baseline-diff + inbound"
  # mode 別詳細 (旧 reason 語 artifact/filled/fabrication-free を substring 保全)。
  if [[ -n "$ARTIFACT" ]]; then mode_detail="mode=artifact: 構造 fabrication-free + term-inline + prose 全充填${bd_note}"
  elif [[ -n "$FILLED_MANIFEST" ]]; then mode_detail="mode=filled: 構造 contract 完全導出・捏造 0 + prose 注入忠実${bd_note}"
  else mode_detail="mode=fabrication-free: 構造 contract 完全導出・捏造 0 + prose 空${bd_note}"; fi
  # ceiling-precheck sentinel を verify-adr.sh:398 同型で統一 emit (folio-vxpc)。 ceiling-precheck.sh は doc-type
  # 非依存の文字列照合 = 'RESULT: floor PASS' ∧ 'CEILING=PENDING' を要求する (旧 'RESULT: artifact PASS' は mode 語が
  # floor 語でなく照合に落ちた)。 gate 全通過時のみ CEILING=PENDING を advisory 宣言 (floor 単独 GREEN 禁止)。
  # render honest-SKIP は render_gate_f の '[SKIP] gate F' が ceiling-precheck を SKIP-masquerade(exit3) に
  # 落とす = PENDING と区別する (捏造印字は禁止 = SKIP-masquerade 再輸入)。
  echo "RESULT: floor PASS ($mode_detail) — ただし CEILING=PENDING (*GREEN ではない*)"
  # 'render gate 未完' marker (ceiling-precheck.sh の 3-fold SKIP marker の 1 本・load-bearing ゆえ削らない)。
  if [[ "${PRINCIPLE_SKIP_RENDER:-0}" == "1" || "${SKIP_RENDER:-0}" == "1" ]]; then
    echo "  ※ render gate 未完 (F=見た目崩れ が未実行: PRINCIPLE_SKIP_RENDER/SKIP_RENDER) — CI/uv 環境で render を回すまで floor は不完全。"
  fi
  echo "  ceiling = persona-walk-principle + fidelity-principle (agents/、 LLM review)。 floor 単独で GREEN を宣言しない。"
  echo "  taxonomy §5.1: GREEN ⟺ floor 全通過 ∧ ceiling 合格。 exit 0 は floor PASS であって GREEN ではない。"
  exit 0
else
  echo "RESULT: floor FAIL — ceiling 以前に blocking arm (構造/prose/term-inline/gate F) が不合格"
  exit 1
fi
