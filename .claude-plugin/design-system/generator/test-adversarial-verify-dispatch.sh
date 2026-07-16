#!/usr/bin/env bash
# folio-1kif — verify --type dispatch + ADR ceiling-anchors guard + verify-adr sentinel の敵対回帰テスト
#
# 新 machinery (S1/S5 + errata) の fail-closed 行動契約を commit 済みテストで固定する
# (per-shape mutation-kill + exit-code + 文字列 assert)。 sandbox suite は本 code を被覆しないため
# (verify --type / ceiling-anchors adr / verify-adr sentinel は tests/scenarios の外)、 回帰を
# 捕えるのは本テスト。 folio doctrine: ADR は options/pros-cons という新 structural shape ゆえ
# SRS の実弾では穴を証明できない (per-shape mutation-kill)。
#
# 被覆 (confirmed finding round-1 の提案 a-d):
#   (a) ceiling-anchors adr の per-shape mutation-kill (options空 / opt-id null / opt-id 空文字 / slot 重複)
#       + happy-path が exit0・valid manifest・decision-rationale が S5.2 教訓通り context+drivers+options.pros/cons に接地
#   (b) verify --type adr artifact happy-path が 'RESULT: floor PASS' ∧ 'CEILING=PENDING' を emit し、
#       ceiling-precheck が honest-SKIP を SKIP-masquerade(exit3) に落とす。 FAIL 側は 'RESULT: floor FAIL'。
#   (c) unknown / unwired / --type 欠落 / 不正書式 type → floor 実行前に exit 2 (fail-closed)。 precheck sentinel。
#   (d) verify --type srs が verify-srs と同一 (stdout + exit) = dispatch faithful passthrough の無回帰。
#
# usage: test-adversarial-verify-dispatch.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR"
FOLIO="bash $SCRIPT_DIR/../../bin/folio"
REG="$GEN/capability-registry.yaml"

# floor script の重い arm (render/repro) を外す (env は folio → floor script へ継承される)。
export SKIP_REPRO="${SKIP_REPRO:-1}" SKIP_RENDER="${SKIP_RENDER:-1}" SRS_SKIP_RENDER="${SRS_SKIP_RENDER:-1}"

command -v yq >/dev/null 2>&1 || { echo "FATAL: yq 不在"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq 不在"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

assert_exit() { # <label> <expected_exit> <cmd...>
  local label="$1" want="$2"; shift 2
  local got; "$@" >/dev/null 2>&1; got=$?
  if [[ "$got" == "$want" ]]; then ok "$label (exit=$got)"; else ng "$label (期待 exit=$want / 実 exit=$got)"; fi
}
assert_stderr_contains() { # <label> <substr> <cmd...>
  local label="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>&1 >/dev/null)"
  if [[ "$out" == *"$needle"* ]]; then ok "$label (stderr に '$needle')"; else ng "$label (stderr に '$needle' 無し。 実末尾: $(printf '%s' "$out" | tail -1))"; fi
}
assert_stdout_contains() { # <label> <substr> <cmd...>
  local label="$1" needle="$2"; shift 2
  local out; out="$("$@" 2>/dev/null)"
  if [[ "$out" == *"$needle"* ]]; then ok "$label (stdout に '$needle')"; else ng "$label (stdout に '$needle' 無し)"; fi
}
assert_eq() { if [[ "$2" == "$3" ]]; then ok "$1 ($2)"; else ng "$1 (期待 '$2' / 実 '$3')"; fi; }
# ★assert_mk_kill: mutation-kill 専用 assert (folio-vxpc)。 exit==2 *だけ* を見る MK は、 guard でなく
#   **型検出層の exit2** ("非対応の contract") でも PASS する = 理由不問の恒真 PASS (jyfh/u7y2 クラス)。
#   実際 MK 用 tmp を mk.p.yaml 等の非 canonical suffix で置くと doc_type 検出が先に落ち、 guard を 1 行も
#   実行しないまま「MK が効いた」と読めてしまう (本 cell 実装中に実測した near-miss)。 よって
#   「exit==2 ∧ stderr が *guard 語彙* ∧ stderr が検出層/tool-error 語彙でない」の 3 点で束縛する。
assert_mk_kill() { # <label> <cmd...>
  local label="$1"; shift
  local err rc
  err="$("$@" 2>&1 >/dev/null)"; rc=$?
  if [[ "$rc" != 2 ]]; then ng "$label (期待 exit=2 / 実 exit=$rc)"; return; fi
  # 検出層・tool error の exit2 を guard の exit2 と取り違えない (MK が guard に到達した証明)。
  if [[ "$err" == *"非対応の contract"* ]]; then
    ng "$label (exit2 だが理由が doc_type 検出層 = guard 未到達の恒真 PASS。 MK contract の suffix を確認せよ: $(printf '%s' "$err" | head -1))"; return
  fi
  if [[ "$err" == *"required"* || "$err" == *"not found"* ]]; then
    ng "$label (exit2 だが理由が tool error = guard 未到達: $(printf '%s' "$err" | head -1))"; return
  fi
  # guard 語彙 = ceiling-anchors の fail-closed 3 系統 (件数/hollow 不一致・slot 重複・空 ssot_value)。
  if [[ "$err" == *"anchor 抽出が contract 期待と不一致"* || "$err" == *"slot 重複"* || "$err" == *"空 ssot_value"* ]]; then
    ok "$label (guard 発火: $(printf '%s' "$err" | head -1 | cut -c1-96))"
  else
    ng "$label (exit2 だが guard 語彙に一致せず = 未知の経路: $(printf '%s' "$err" | head -1))"
  fi
}

echo "folio-1kif verify-dispatch adversarial regression (fail-closed expected):"

# 前提: registry 実在 (dispatch の SSoT)
[[ -f "$REG" ]] || { echo "FATAL: capability-registry.yaml 不在: $REG"; exit 2; }

SRS_C="$GEN/contract/ec-checkout.srs.yaml"; SRS_P="$GEN/prose/ec-checkout.prose.yaml"
SRS_RAW="$TMP/srs-raw.html"; SRS_FILLED="$TMP/srs-filled.html"
bash "$GEN/assemble-srs.sh" "$SRS_C" "$SRS_RAW" >/dev/null 2>&1 || { echo "FATAL: assemble-srs 失敗"; exit 2; }
bash "$GEN/inject-prose.sh" "$SRS_P" "$SRS_RAW" "$SRS_FILLED" >/dev/null 2>&1 || { echo "FATAL: inject-prose(srs) 失敗"; exit 2; }
ADR_C="$GEN/contract/clinic-double-booking.adr.yaml"; ADR_P="$GEN/prose/clinic-double-booking.adr.prose.yaml"
ADR_RAW="$TMP/adr-raw.html"; ADR_FILLED="$TMP/adr-filled.html"
bash "$GEN/assemble-adr.sh" "$ADR_C" "$ADR_RAW" >/dev/null 2>&1 || { echo "FATAL: assemble-adr 失敗"; exit 2; }
bash "$GEN/inject-prose.sh" "$ADR_P" "$ADR_RAW" "$ADR_FILLED" >/dev/null 2>&1 || { echo "FATAL: inject-prose(adr) 失敗"; exit 2; }

# ===========================================================================
echo "== (c) dispatch fail-closed: 未知 / 未配線 / --type 欠落 / 不正書式 / precheck sentinel =="
# ===========================================================================
assert_exit            "C1 未知 type → exit 2"              2 $FOLIO verify --type bogus "$TMP/x.html" "$TMP/x.yaml"
assert_stderr_contains "C1 未知 type → 'unknown doc-type'"  "unknown doc-type" $FOLIO verify --type bogus "$TMP/x.html" "$TMP/x.yaml"
# ★C2 番人型の差し替え (folio-vxpc SF-8): vision は本 cell で wire したため未配線 sentinel に使えない。
#   番人を絶やすと「未配線 type を fail-closed で弾く」行動契約が無検査になる (fail-open) ため、 恒久的に
#   未配線の型へ差し替える。 spec 系 3 instance は admin 裁定 D1 で folio-vhew まで unwired 確定ゆえ番人に使える。
#   ★literal 固定でなく registry から「実際に未配線の型」を解決する = 将来 spec を wire した slice で本 assert が
#     赤くなり、 番人の差し替え忘れ (fail-open) を検出する (unwired 型が 0 なら FATAL で落とす)。
UNWIRED="$(yq -r '.doc_types | to_entries | map(select(.value.wired != true)) | .[].key' "$REG" | head -1)"
if [[ -z "$UNWIRED" ]]; then
  ng "C2 未配線 sentinel 型が registry に 1 つも無い (番人喪失 = 未配線 fail-closed が無検査。 恒久 unwired 型を registry へ 1 行足すか bogus 型で番人を再建せよ)"
else
  ok "C2 未配線 sentinel 型を registry から解決: $UNWIRED"
  assert_exit            "C2 未配線 type($UNWIRED) → exit 2"     2 $FOLIO verify --type "$UNWIRED" "$TMP/x.html" "$TMP/x.yaml"
  assert_stderr_contains "C2 未配線 type → 'not yet wired'"    "not yet wired" $FOLIO verify --type "$UNWIRED" "$TMP/x.html" "$TMP/x.yaml"
fi
assert_exit            "C3 --type 欠落 → exit 2"             2 $FOLIO verify "$TMP/x.html" "$TMP/x.yaml"
assert_exit            "C4 不正書式 type(injection) → exit 2" 2 $FOLIO verify --type 'srs;rm' "$TMP/x.html" "$TMP/x.yaml"
assert_stderr_contains "C4 不正書式 type → '不正な doc-type'" "不正な doc-type" $FOLIO verify --type 'srs;rm' "$TMP/x.html" "$TMP/x.yaml"
# precheck sentinel (全型共通・floor 実行前): spec 不在 / contract 不在 → exit 2
assert_exit            "C5 precheck: spec(HTML) 不在 → exit 2" 2 $FOLIO verify --type srs "$TMP/no-such.html" "$SRS_C"
assert_stderr_contains "C5 precheck: spec 不在 → 'precheck'"    "precheck" $FOLIO verify --type srs "$TMP/no-such.html" "$SRS_C"
assert_exit            "C6 precheck: contract 不在 → exit 2"   2 $FOLIO verify --type srs "$SRS_FILLED" "$TMP/no-such.yaml"
assert_stderr_contains "C6 precheck: contract 不在 → 'contract not found'" "contract not found" $FOLIO verify --type srs "$SRS_FILLED" "$TMP/no-such.yaml"

# ===========================================================================
echo "== (b) verify --type adr artifact sentinel: floor PASS + CEILING=PENDING + SKIP-masquerade =="
# ===========================================================================
# happy-path (filled) → exit 0 + RESULT: floor PASS + CEILING=PENDING
assert_exit            "B1 adr filled artifact → floor PASS (exit 0)" 0 $FOLIO verify --type adr "$ADR_FILLED" "$ADR_C"
assert_stdout_contains "B1 adr floor 出力に 'RESULT: floor PASS'" "RESULT: floor PASS" $FOLIO verify --type adr "$ADR_FILLED" "$ADR_C"
assert_stdout_contains "B1 adr floor 出力に 'CEILING=PENDING'"     "CEILING=PENDING"     $FOLIO verify --type adr "$ADR_FILLED" "$ADR_C"
# sentinel chain: adr floor 出力 (render honest-SKIP 併存) を ceiling-precheck へ → honest-SKIP≠PENDING = SKIP-masquerade(exit3)
$FOLIO verify --type adr "$ADR_FILLED" "$ADR_C" 2>&1 | bash "$GEN/ceiling-precheck.sh" >/dev/null 2>&1; pc=$?
assert_eq "B2 adr floor→ceiling-precheck が SKIP-masquerade(exit3) を検出 (honest-SKIP≠PENDING)" "3" "$pc"
# FAIL 側 (pre-fill raw) → exit 1 + RESULT: floor FAIL
assert_exit            "B3 adr pre-fill(raw) artifact → floor FAIL (exit 1)" 1 $FOLIO verify --type adr "$ADR_RAW" "$ADR_C"
assert_stdout_contains "B3 adr FAIL 側に 'RESULT: floor FAIL'" "RESULT: floor FAIL" $FOLIO verify --type adr "$ADR_RAW" "$ADR_C"

# ===========================================================================
echo "== (a) ceiling-anchors adr: happy-path 接地 + per-shape mutation-kill =="
# ===========================================================================
# happy-path: exit0 + valid JSON + doc_type=adr + decision-rationale 接地 (S5.2 教訓) + 空 ssot_value 0 件
$FOLIO ceiling-anchors "$ADR_C" > "$TMP/adr-manifest.json" 2>/dev/null; anrc=$?
assert_eq "A0 adr ceiling-anchors happy exit 0" "0" "$anrc"
jq -e . "$TMP/adr-manifest.json" >/dev/null 2>&1 && ok "A0 adr manifest valid JSON" || ng "A0 adr manifest invalid JSON"
assert_eq "A0 adr manifest doc_type == adr" "adr" "$(jq -r '.doc_type' "$TMP/adr-manifest.json" 2>/dev/null)"
dr_path="$(jq -r '.anchors[] | select(.slot=="decision-rationale") | .ssot_path' "$TMP/adr-manifest.json" 2>/dev/null)"
assert_eq "A0 decision-rationale が context+drivers+options.pros/cons に接地 (decision.statement ではない=S5.2)" \
  "context+drivers+options[].pros/cons" "$dr_path"
empty_val="$(jq -r '[.anchors[] | select((.ssot_value // "") == "")] | length' "$TMP/adr-manifest.json" 2>/dev/null)"
assert_eq "A0 adr manifest に空 ssot_value 0 件 (verify-laundering 逃げ封鎖)" "0" "$empty_val"
# ★被覆不変条件 (folio-vxpc・run_type_suite の a′ と同型を srs/adr にも張り 13 型で揃える): chapter-lead の emit は
#   per-type のハードコード loop ゆえ、 章が 1 本増えて ceiling-anchors 側の更新が漏れると当該 slot の anchor が
#   *emit されない* = 「空 ssot_value 0 件」では撃てない (行が無いものは検査できない)。 reviewer はその slot の
#   SSoT 接地を失い DOM へ fallback する = verify-laundering の silent 再開。 期待集合は prose (SSoT 側) から作る。
for _pair in "adr:$ADR_P:$TMP/adr-manifest.json" "srs:$SRS_P:$TMP/srs-manifest.json"; do
  _t="${_pair%%:*}"; _rest="${_pair#*:}"; _p="${_rest%%:*}"; _m="${_rest#*:}"
  [[ -f "$_m" ]] || $FOLIO ceiling-anchors "$SRS_C" > "$_m" 2>/dev/null
  _a="$(jq -r '.anchors[].slot' "$_m" 2>/dev/null | grep -v '^term-inline:' | LC_ALL=C sort)"
  _ps="$(yq -r '.slots | keys | .[]' "$_p" 2>/dev/null | LC_ALL=C sort)"
  if [[ "$_a" == "$_ps" ]]; then ok "A0 [$_t] anchor slot 集合 == prose slot 集合 (架空 slot 0 / 脱落 0)"; else
    ng "A0 [$_t] slot 集合が不一致 (anchor 側のみ: $(comm -23 <(printf '%s\n' "$_a") <(printf '%s\n' "$_ps") | tr '\n' ' ')/ prose 側のみ: $(comm -13 <(printf '%s\n' "$_a") <(printf '%s\n' "$_ps") | tr '\n' ' '))"; fi
  assert_eq "A0 [$_t] ssot_value に literal null の混入 0" "0" \
    "$(jq -r '.anchors[].ssot_value' "$_m" 2>/dev/null | grep -c 'null')"
done

MK="$TMP/mk.adr.yaml"
# per-shape mutation-kill: ADR の options/glossary という新 structural shape を壊し fail-closed 転落を実証。
cp "$ADR_C" "$MK"; yq -i '.options = []' "$MK"
assert_mk_kill "A1 MK options=[] → 空 manifest fail-open 封鎖 (exit2)" $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.options[0].id = null' "$MK"
assert_mk_kill "A2 MK option id=null → opt-id guard FAIL (exit2)" $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.options[0].id = ""' "$MK"
assert_mk_kill "A3 MK option id=空文字 → opt-id guard FAIL (exit2)" $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.glossary += [{"term":"満枠","en":"f2","plain_short":"別","def":"重複語。"}]' "$MK"
assert_mk_kill "A4 MK term 重複 → slot 一意 guard FAIL (exit2)" $FOLIO ceiling-anchors "$MK"
# ★decision-rationale が消費する context/drivers の per-shape MK (finding round-1 #2)。 count 0==0 で floor を
#   素通る構造的に空虚な ADR を ceiling-anchors 側で fail-closed に落とす (decision-rationale の hollow 化封鎖)。
cp "$ADR_C" "$MK"; yq -i '.context = []' "$MK"
assert_mk_kill "A5 MK context=[] → context空 guard FAIL (exit2・decision-rationale hollow 封鎖)" $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.drivers = []' "$MK"
assert_mk_kill "A6 MK drivers=[] → drivers空 guard FAIL (exit2・decision-rationale hollow 封鎖)" $FOLIO ceiling-anchors "$MK"
# ★構造的不変条件 (empty_val==0 の script 昇格): anchor が空 ssot_value に潰れる shape を撃つ (finding round-1 #1(b))。
#   decision.statement="" → decision-plain が空 ssot_value に潰れる = verify-laundering。 per-shape guard 列挙では
#   捕らえられず、 全 anchor 非空 invariant のみが撃ち落とす。
cp "$ADR_C" "$MK"; yq -i '.decision.statement = ""' "$MK"
assert_exit "A7 MK decision.statement=\"\" → 空 ssot_value invariant FAIL (exit2・anchor 潰れ封鎖)" 2 $FOLIO ceiling-anchors "$MK"
# ★absent-key shape (finding round-1 #1): decision.statement キーを丸ごと del すると bare scalar `q '.decision.statement'`
#   が yq -r で literal "null" を出す。 A7 の空文字列 shape とは構造差 (per-shape mutation-kill) — `// ""` guard +
#   (c) invariant の "null" 拡張の二重防御が撃ち落とすことを pin する (absent-key を "null"(非空) として素通す fail-open 封鎖)。
cp "$ADR_C" "$MK"; yq -i 'del(.decision.statement)' "$MK"
assert_exit "A7b MK del(.decision.statement) → literal \"null\" fail-open 封鎖 (exit2・absent-key shape)" 2 $FOLIO ceiling-anchors "$MK"
# ★pros/cons=null は null-safe (.pros // []) で潰れず grounding を保つ (finding round-1 #1(a))。 単一 option の
#   pros 欠落は構造不正ではない = exit0 かつ decision-rationale が非空 (context+drivers+他 option で接地継続)。
cp "$ADR_C" "$MK"; yq -i '.options[0].pros = null' "$MK"
$FOLIO ceiling-anchors "$MK" > "$TMP/mk-prosnull.json" 2>/dev/null; prc=$?
assert_eq "A8 MK pros=null → null-safe で潰れず exit0 (yq error 回避)" "0" "$prc"
dr_nn="$(jq -r '.anchors[] | select(.slot=="decision-rationale") | .ssot_value' "$TMP/mk-prosnull.json" 2>/dev/null)"
if [[ -n "$dr_nn" ]]; then ok "A8 MK pros=null でも decision-rationale が非空 (context/drivers/他 option で接地継続)"; else ng "A8 MK pros=null で decision-rationale が空に潰れた (null-safe 未効)"; fi

# ★round-2 M1 (MUST): decision-rationale の第 3 grounding 源 = 全 option 合算の pros/cons。 固定ラベル「各案 pros/cons: 」で
#   (c) invariant の列 3 が恒真非空になる計数恒真 PASS (jyfh/u7y2 クラス) を、 全 option 合算非空 guard が撃ち落とす。
#   ★全 option 合算で判定 = 全空のみ exit2 / 単一欠落は legit (A10 で exit0 維持を pin)。
cp "$ADR_C" "$MK"; yq -i '.options[].pros = [] | .options[].cons = []' "$MK"
assert_mk_kill "A9 MK 全 option pros/cons=[] → pros/cons全空 guard FAIL (exit2・decision-rationale hollow 封鎖)" $FOLIO ceiling-anchors "$MK"
# ★M1 受け入れ条件: 単一 option の pros/cons 欠落は legit (比較根拠は他 option で継続) = exit0 を維持する (over-block 防止)。
cp "$ADR_C" "$MK"; yq -i '.options[0].pros = [] | .options[0].cons = []' "$MK"
assert_exit "A10 MK 単一 option pros/cons=[] (legit) → exit0 維持 (per-option 必須にしない)" 0 $FOLIO ceiling-anchors "$MK"
# ★round-2 S1: consequences (chapter-lead-05) / supersession+principle (chapter-lead-06) の同型 hollow anchor を
#   合算非空 guard が撃つ (M1 と root-cause 同一・固定ラベル恒真非空の class ごと封鎖)。
cp "$ADR_C" "$MK"; yq -i '.consequences.positive = [] | .consequences.negative = []' "$MK"
assert_mk_kill "A11 MK consequences 全空 → consequences全空 guard FAIL (exit2・chapter-lead-05 hollow 封鎖)" $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i 'del(.supersession.status) | del(.principle.text)' "$MK"
assert_mk_kill "A12 MK supersession.status+principle.text 両空 → supersession+principle全空 guard FAIL (exit2・chapter-lead-06 hollow 封鎖)" $FOLIO ceiling-anchors "$MK"

# ===========================================================================
echo "== (d) 無回帰: verify --type srs == verify-srs (stdout + exit・faithful passthrough) =="
# ===========================================================================
#   dispatch (verify --type srs H C) と直路 (verify-srs H C) は同一 floor (verify-srs.sh C H) を呼ぶ。
#   同一 html/contract で stdout + exit が byte 一致すれば dispatch は無回帰の thin passthrough。
for pair in "filled:$SRS_FILLED:0" "raw:$SRS_RAW:1"; do
  tag="${pair%%:*}"; rest="${pair#*:}"; hp="${rest%%:*}"; want="${rest#*:}"
  d_out="$($FOLIO verify --type srs "$hp" "$SRS_C" 2>/dev/null)"; d_rc=$?
  s_out="$($FOLIO verify-srs "$hp" "$SRS_C" 2>/dev/null)"; s_rc=$?
  assert_eq "D-$tag verify --type srs の exit が verify-srs と一致" "$s_rc" "$d_rc"
  assert_eq "D-$tag verify --type srs の exit が期待通り" "$want" "$d_rc"
  if [[ "$d_out" == "$s_out" ]]; then ok "D-$tag verify --type srs の stdout が verify-srs と byte 一致 (無回帰)"; else ng "D-$tag stdout drift (dispatch が passthrough でない)"; fi
done
# ceiling-anchors srs の構造無回帰 (DOC_TYPE 分岐追加が SRS path を壊していない)
$FOLIO ceiling-anchors "$SRS_C" > "$TMP/srs-manifest.json" 2>/dev/null; srsrc=$?
assert_eq "D-anchors srs ceiling-anchors exit 0" "0" "$srsrc"
assert_eq "D-anchors srs manifest doc_type == srs" "srs" "$(jq -r '.doc_type' "$TMP/srs-manifest.json" 2>/dev/null)"
jq -e '.anchors | length > 0' "$TMP/srs-manifest.json" >/dev/null 2>&1 && ok "D-anchors srs manifest に anchor 存在" || ng "D-anchors srs manifest が空"
# ★round-2 S3: SRS anchors byte 回帰ゼロを恒久 CI 資産として pin (untracked selftest から移設)。 path 非依存の
#   jq -cS '.anchors' の SHA を固定 = adr per-type authoring が SRS path の出力を 1 byte も変えていないことを保証する。
SRS_ANCHOR_SHA_ec="461166e4f4dae05028fe2eee78f181813b19755f5cfe431361afb39ee426ca6f"
SRS_ANCHOR_SHA_clinic="126474a1c8e16105b633559a69f2c6f3935f582b571c038f90e9b93105ddaf82"
sha_ec="$($FOLIO ceiling-anchors "$SRS_C" 2>/dev/null | jq -cS '.anchors' | sha256sum | cut -c1-64)"
assert_eq "D-byte SRS(ec-checkout) anchors byte 回帰ゼロ (SHA pin)" "$SRS_ANCHOR_SHA_ec" "$sha_ec"
sha_cl="$($FOLIO ceiling-anchors "$GEN/contract/clinic-appointment.srs.yaml" 2>/dev/null | jq -cS '.anchors' | sha256sum | cut -c1-64)"
assert_eq "D-byte SRS(clinic-appointment) anchors byte 回帰ゼロ (SHA pin)" "$SRS_ANCHOR_SHA_clinic" "$sha_cl"

# ===========================================================================
echo "== (E) folio-vxpc: 新 wire 型の per-type acceptance (c′ 誤配線 / b′ false-green / a′ verify-laundering) =="
# ===========================================================================
#   folio-1kif が srs/adr で確立した primitive を残 doc-type へ複製した各型を、 1kif と同じ 3 kill で pin する。
#   ★per-shape mutation-kill の doctrine (1kif header): 型ごとに structural shape が違う (research=approaches/
#     open_questions・risk=risks/severity 導出 等) ため、 ある型の実弾は別型の穴を証明しない。 よって MK は
#     「主コレクション空 / id null / 消費必須フィールド空」を **型ごとの実 shape で**撃ち、 legit shape の exit0 も pin
#     (over-block 防止)。 期待集合は contract(SSoT) から作り生成 HTML の DOM からは作らない (verify-laundering 禁止)。
#
# run_type_suite <type> <assembler> <contract> <prose> <mk_coll> <mk_idnull> <mk_fieldempty> <mk_legit>
#   assembler が out.html 引数を取らず stdout 専用の型 (glossary) は <assembler> に 'STDOUT:<name>' を渡す。
COVERED=()
run_type_suite() {
  local t="$1" asm="$2" cyaml="$3" pyaml="$4" mk_coll="$5" mk_idnull="$6" mk_fieldempty="$7" mk_legit="$8"
  local C="$GEN/contract/$cyaml" P="$GEN/prose/$pyaml"
  # ★MK の一時 contract は **registry の contract_suffix** で命名する (registry key ではない)。
  #   ceiling-anchors の doc_type 検出は basename の suffix を読むため、 key 名で置くと (例: architecture は
  #   key=architecture / suffix=arch) 検出層が先に exit2 に落ち、 guard を 1 行も実行しないまま MK が
  #   「効いた」ように見える恒真 PASS になる (実測で 8 件の偽 PASS を assert_mk_kill が検出した)。
  local sfx; sfx="$(yq -r ".doc_types.\"$t\".contract_suffix" "$REG")"
  local RAW="$TMP/$t.raw.html" FILLED="$TMP/$t.filled.html" MK="$TMP/mk.$sfx.yaml"
  # ★SF-7 閉包の被覆蓄積 (末尾の閉包 assert が registry.wired と突合する)。
  COVERED+=("$t")
  echo "-- [$t] --"
  [[ -f "$C" ]] || { ng "[$t] contract 不在: $C"; return; }
  [[ -f "$P" ]] || { ng "[$t] prose 不在: $P"; return; }
  # finished artifact = assemble + inject-prose (SF-6: floor_mode はこの finished 状態を検査する mode)。
  if [[ "$asm" == STDOUT:* ]]; then
    bash "$GEN/assemble-${asm#STDOUT:}.sh" "$C" > "$RAW" 2>/dev/null || { ng "[$t] assemble 失敗"; return; }
  else
    bash "$GEN/assemble-$asm.sh" "$C" "$RAW" >/dev/null 2>&1 || { ng "[$t] assemble 失敗"; return; }
  fi
  bash "$GEN/inject-prose.sh" "$P" "$RAW" "$FILLED" >/dev/null 2>&1 || { ng "[$t] inject-prose 失敗"; return; }

  # ---- r′ registry lens 解決 (wired / floor_mode 確定値 / 非 SRS=2 lens / agent 実在) ----
  assert_eq "[$t] r′ registry wired==true" "true" "$(yq -r ".doc_types.\"$t\".wired" "$REG")"
  local fm; fm="$(yq -r ".doc_types.\"$t\".floor_mode" "$REG")"
  case "$fm" in default|artifact) ok "[$t] r′ floor_mode 確定値 ($fm)" ;; *) ng "[$t] r′ floor_mode が未確定/未対応 ($fm)" ;; esac
  assert_eq "[$t] r′ ceiling lens 数 == 2 (非 SRS・completeness-critic 新設禁止)" "2" "$(yq -r ".doc_types.\"$t\".ceiling | length" "$REG")"
  local lens; for lens in $(yq -r ".doc_types.\"$t\".ceiling[]" "$REG"); do
    [[ -f "$SCRIPT_DIR/../../../agents/$lens.md" ]] && ok "[$t] r′ ceiling agent 実在: $lens" || ng "[$t] r′ ceiling agent 不在: $lens"
  done

  # ---- c′ 誤配線 kill: dispatch stdout が直路 verify-<type>.sh <floor_mode> C H と byte 一致 ----
  local d_out s_out d_rc s_rc
  local -a flags=(); [[ "$fm" == artifact ]] && flags=(--artifact)
  d_out="$($FOLIO verify --type "$t" "$FILLED" "$C" 2>/dev/null)"; d_rc=$?
  s_out="$(bash "$GEN/$(yq -r ".doc_types.\"$t\".floor" "$REG")" "${flags[@]}" "$C" "$FILLED" 2>/dev/null)"; s_rc=$?
  assert_eq "[$t] c′ dispatch exit == 直路 exit" "$s_rc" "$d_rc"
  assert_eq "[$t] c′ dispatch exit == 0 (finished artifact)" "0" "$d_rc"
  if [[ "$d_out" == "$s_out" ]]; then ok "[$t] c′ dispatch stdout が直路と byte 一致 (誤配線/mode 取り違え kill)"; else ng "[$t] c′ stdout drift (dispatch が passthrough でない or floor_mode 誤り)"; fi

  # ---- b′ false-green kill: sentinel 統一 + FAIL 側 + honest-SKIP≠PENDING ----
  assert_stdout_contains "[$t] b′ floor 出力に 'RESULT: floor PASS'" "RESULT: floor PASS" $FOLIO verify --type "$t" "$FILLED" "$C"
  assert_stdout_contains "[$t] b′ floor 出力に 'CEILING=PENDING'"     "CEILING=PENDING"     $FOLIO verify --type "$t" "$FILLED" "$C"
  assert_exit            "[$t] b′ pre-fill(raw) → floor FAIL (exit 1)" 1 $FOLIO verify --type "$t" "$RAW" "$C"
  assert_stdout_contains "[$t] b′ FAIL 側に 'RESULT: floor FAIL'" "RESULT: floor FAIL" $FOLIO verify --type "$t" "$RAW" "$C"
  local pc; $FOLIO verify --type "$t" "$FILLED" "$C" 2>&1 | bash "$GEN/ceiling-precheck.sh" >/dev/null 2>&1; pc=$?
  assert_eq "[$t] b′ floor→precheck が SKIP-masquerade(exit3) を検出 (honest-SKIP≠PENDING・捏造印字なし)" "3" "$pc"
  # ---- d′ 拡張: floor stdout 契約 = 「GREEN を *主張* しない」の per-type 番人 ----
  # ★欠落だった受入 (SF-10 d′): 従来の d′ は ceiling-anchors 側の回帰 (SHA pin) と registry 側の half-wire しか
  #   撃たず、 本 cell が書き換えたもう一方の面 = verify-*.sh の **floor stdout 契約**の回帰を撃つ assert が
  #   1 つも無かった。 実証: sentinel 統一が commit 済 9 suite の「floor 単独 GREEN 禁止」assert を全て赤にした
  #   回帰が、 self-test 384/384 緑・本 suite exit 0・folio validate clean を全て素通りした (番人不在)。
  #   9 suite 全走は約 10 分超で self-test に重いため、 同じ *意図* を安価な不変条件として per-type に内在化する。
  # ★bare token grep にしない: sentinel は「GREEN ではない」と *否定*するために GREEN の語を含む。 否定文まで
  #   撃つ bare grep は 9 suite が踏んだ lexical 衝突そのもの (緩和ではなく意図準拠への精密化)。
  #   緩和が番人を殺していないことは末尾の MK 2 本 (捏造 kill / 否定文の陰性対照) が実弾で pin する。
  if printf '%s' "$d_out" | grep -qE 'RESULT:[^—]*GREEN|GREEN 認定|全 gate.*GREEN'; then
    ng "[$t] d′ floor stdout 契約: floor が GREEN を *主張* した (floor 単独 GREEN 禁止)"
  else
    ok "[$t] d′ floor stdout 契約: GREEN 主張なし (CEILING=PENDING は b′ が別途強制)"
  fi

  # ---- a′ verify-laundering kill: anchors happy + per-shape MK 3 shape + legit shape の exit0 ----
  local an_rc; $FOLIO ceiling-anchors "$C" > "$TMP/$t-manifest.json" 2>/dev/null; an_rc=$?
  assert_eq "[$t] a′ ceiling-anchors happy exit 0" "0" "$an_rc"
  jq -e . "$TMP/$t-manifest.json" >/dev/null 2>&1 && ok "[$t] a′ manifest valid JSON" || ng "[$t] a′ manifest invalid JSON"
  assert_eq "[$t] a′ manifest doc_type == $t" "$t" "$(jq -r '.doc_type' "$TMP/$t-manifest.json" 2>/dev/null)"
  assert_eq "[$t] a′ manifest に空 ssot_value 0 件 (anchor 潰れ封鎖)" "0" \
    "$(jq -r '[.anchors[] | select((.ssot_value // "") == "")] | length' "$TMP/$t-manifest.json" 2>/dev/null)"
  # ★被覆不変条件 (folio-vxpc): chapter-lead の emit は per-type のハードコード loop (例 research は
  #   `for idx in 0 1 2 3 4 5`) ゆえ、 build()/prose に章が 1 本増えて ceiling-anchors 側の更新が漏れると
  #   (a) 当該 slot の anchor は *emit されない* ので「空 ssot_value 0 件」も assert_no_empty_anchor も撃てず
  #   (行が無いものは検査できない)、 (b) per-type guard は contract 側の件数照合しか見ず chapter-lead の被覆を
  #   見ない。 結果 reviewer はその slot の SSoT 接地を失い DOM へ fallback する = 本 cell が封じている当の
  #   verify-laundering が silent に再開する。 期待集合は **prose manifest (SSoT 側)** から作り生成 HTML の DOM
  #   からは作らない。 term-inline は派生ビューゆえ除外。
  local a_slots p_slots
  a_slots="$(jq -r '.anchors[].slot' "$TMP/$t-manifest.json" 2>/dev/null | grep -v '^term-inline:' | LC_ALL=C sort)"
  p_slots="$(yq -r '.slots | keys | .[]' "$P" 2>/dev/null | LC_ALL=C sort)"
  if [[ "$a_slots" == "$p_slots" ]]; then
    ok "[$t] a′ anchor slot 集合 == prose slot 集合 (架空 slot 0 / 脱落 0)"
  else
    ng "[$t] a′ slot 集合が不一致 (anchor 側のみ: $(comm -23 <(printf '%s\n' "$a_slots") <(printf '%s\n' "$p_slots") | tr '\n' ' ')/ prose 側のみ: $(comm -13 <(printf '%s\n' "$a_slots") <(printf '%s\n' "$p_slots") | tr '\n' ' '))"
  fi
  # ★literal null 混入 0: `// ""` の null 規律が漏れると ssot_value が文字列 "null" になり、 非空ゆえ (c)
  #   invariant を素通りしたまま reviewer へ「SSoT 期待値は null」という偽の接地を渡す。
  assert_eq "[$t] a′ ssot_value に literal null の混入 0" "0" \
    "$(jq -r '.anchors[].ssot_value' "$TMP/$t-manifest.json" 2>/dev/null | grep -c 'null')"
  cp "$C" "$MK"; yq -i "$mk_coll" "$MK"
  assert_mk_kill "[$t] a′ MK 主コレクション空 → 空 manifest fail-open 封鎖 (exit2・guard 到達を stderr で束縛)" $FOLIO ceiling-anchors "$MK"
  cp "$C" "$MK"; yq -i "$mk_idnull" "$MK"
  assert_mk_kill "[$t] a′ MK id=null → slot 一意/id guard FAIL (exit2・guard 到達を stderr で束縛)" $FOLIO ceiling-anchors "$MK"
  cp "$C" "$MK"; yq -i "$mk_fieldempty" "$MK"
  assert_mk_kill "[$t] a′ MK 消費必須フィールド空 → anchor 潰れ/hollow を fail-closed (exit2・guard 到達を stderr で束縛)" $FOLIO ceiling-anchors "$MK"
  cp "$C" "$MK"; yq -i "$mk_legit" "$MK"
  assert_exit "[$t] a′ 単一要素欠落 (legit shape) → exit0 維持 (over-block 防止)" 0 $FOLIO ceiling-anchors "$MK"
}

# research: 主コレクション=approaches / 消費必須=outcome.note (outcome-plain の唯一の接地) / legit=単一案の assessment 欠落
run_type_suite research research clinic-double-booking.research.yaml clinic-double-booking.research.prose.yaml \
  '.approaches = []' '.approaches[0].id = null' '.outcome.note = ""' '.approaches[0].assessment = ""'
# ★research 固有 hallmark: open_questions (「結論しない」の構造的担保 = chapter-lead-04 の唯一 grounding) の
#   hollow 化を撃つ。 汎用 3 shape では捕らえられない型固有 shape ゆえ per-type に足す (per-shape MK doctrine)。
cp "$GEN/contract/clinic-double-booking.research.yaml" "$TMP/mk.research.yaml"
yq -i '.open_questions = []' "$TMP/mk.research.yaml"
assert_mk_kill "[research] a′ MK open_questions=[] → hallmark 毀損 hollow 封鎖 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.research.yaml"
cp "$GEN/contract/clinic-double-booking.research.yaml" "$TMP/mk.research.yaml"
yq -i '.approaches[].assessment = ""' "$TMP/mk.research.yaml"
assert_mk_kill "[research] a′ MK 全案 assessment 空 → 比較根拠 hollow 封鎖 (exit2・全案合算 0 のみ)" $FOLIO ceiling-anchors "$TMP/mk.research.yaml"
# ★shift shape (per-shape MK の shape 欠落だった): 既存 MK は *末尾* フィールド (assessment) 空しか撃たず、
#   **中間** フィールド空を一度も撃たない。 中間空は末尾空と構造差がある — multi-field TSV read だと連続 tab が
#   1 区切りへ畳まれて後続変数が右詰めシフトし、 assessment 本文が summary 位置へ混入した anchor を exit 0 の
#   まま emit する (実測で確認済の fail-open)。 末尾フィールドの実弾では証明できない穴ゆえ per-shape で撃つ。
cp "$GEN/contract/clinic-double-booking.research.yaml" "$TMP/mk.research.yaml"
yq -i '.approaches[0].summary = ""' "$TMP/mk.research.yaml"
assert_mk_kill "[research] a′ MK 中間フィールド空 (summary='') → per-row 束縛 FAIL (exit2・TSV shift による SSoT 誤帰属の封鎖)" $FOLIO ceiling-anchors "$TMP/mk.research.yaml"

# principle: 主コレクション=principles / 消費必須=amendment.steps (chapter-lead-05 + amendment-plain の唯一の接地)
#   legit=単一原則の amended_by 欠落 (14 中 4 本しか持たない = 欠落が正常な shape)
run_type_suite principle principle folio-constitution.principle.yaml folio-constitution.principle.prose.yaml \
  '.principles = []' '.principles[0].id = null' '.amendment.steps = []' 'del(.principles[1].amended_by)'
# ★principle 固有 shape (汎用 3 shape では捕らえられない per-type hollow・per-shape MK doctrine):
#   (1) tier が固定 3 章の band ゆえ、 ある tier が 0 件だとその chapter-lead が固定ラベルだけの hollow になる。
cp "$GEN/contract/folio-constitution.principle.yaml" "$TMP/mk.principle.yaml"
yq -i '.principles[] |= (select(.tier == "Never") | .tier = "Always")' "$TMP/mk.principle.yaml" 2>/dev/null || \
  yq -i '(.principles[] | select(.tier == "Never") | .tier) = "Always"' "$TMP/mk.principle.yaml"
assert_mk_kill "[principle] a′ MK Never tier を全て Always へ → Never空 guard FAIL (exit2・chapter-lead-03 hollow 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.principle.yaml"
#   (2) tier allowlist 外 = tier 体系の崩壊 (どの tier 章にも現れない原則が生じ silent に脱落する)。
cp "$GEN/contract/folio-constitution.principle.yaml" "$TMP/mk.principle.yaml"
yq -i '(.principles[0].tier) = "Sometimes"' "$TMP/mk.principle.yaml"
assert_mk_kill "[principle] a′ MK tier=allowlist 外 → tier 束縛 FAIL (exit2・tier 誤帰属の SSoT 側封鎖)" $FOLIO ceiling-anchors "$TMP/mk.principle.yaml"
#   (3) heading/statement の片欠けは固定 separator ' — ' で恒真非空 = (c) invariant をすり抜ける per-row 潰れ。
cp "$GEN/contract/folio-constitution.principle.yaml" "$TMP/mk.principle.yaml"
yq -i '(.principles[0].statement) = ""' "$TMP/mk.principle.yaml"
assert_mk_kill "[principle] a′ MK statement='' (heading 残) → per-row 束縛 FAIL (exit2・恒真非空 separator 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.principle.yaml"
#   (4) inbound = 終端性 (受ける照会だけ) の唯一の grounding。
cp "$GEN/contract/folio-constitution.principle.yaml" "$TMP/mk.principle.yaml"
yq -i '.inbound = []' "$TMP/mk.principle.yaml"
assert_mk_kill "[principle] a′ MK inbound=[] → 終端性 grounding 喪失 (exit2・chapter-lead-06 hollow 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.principle.yaml"

# vision: 主コレクション=features / 消費必須=principle.narrative (genuine 性=sacrifice-order 判定の SSoT anchor)
#   legit=cross_doc 非宣言 (節ごと opt-in・folio-vision instance は実際に持たない = 不在が正常)
run_type_suite vision vision clinic-appointment.vision.yaml clinic-appointment.vision.prose.yaml \
  '.features = []' '.features[0].id = null' '.principle.narrative = ""' 'del(.cross_doc)'
# ★vision 固有 shape: 可視 slot が cover + chapter-lead 7 本 *のみ* = 全て固定ラベル付き束ね ゆえ (c) invariant が
#   構造的に恒真化する型。 per-field 合算非空 guard がこの型の fail-closed 本体であることを実弾で pin する。
cp "$GEN/contract/clinic-appointment.vision.yaml" "$TMP/mk.vision.yaml"
yq -i '.north_star.narrative = ""' "$TMP/mk.vision.yaml"
assert_mk_kill "[vision] a′ MK north_star.narrative='' → hollow 封鎖 (exit2・(c) は固定ラベルで恒真 PASS ゆえ per-field guard が本体)" $FOLIO ceiling-anchors "$TMP/mk.vision.yaml"
cp "$GEN/contract/clinic-appointment.vision.yaml" "$TMP/mk.vision.yaml"
yq -i '.objectives = [] | .success_criteria.entries = []' "$TMP/mk.vision.yaml"
assert_mk_kill "[vision] a′ MK objectives+success_criteria 両空 → hollow 封鎖 (exit2・for_goal⊆objectives が空集合で恒真化する穴)" $FOLIO ceiling-anchors "$TMP/mk.vision.yaml"
# ★vision の第 2 instance (folio-vision = cross_doc 非宣言) で happy-path exit0 を pin = opt-in 節の over-block 防止。
assert_exit "[vision] a′ 第 2 instance (folio-vision・cross_doc 非宣言) → exit0 維持 (節ごと opt-in を over-block しない)" 0 $FOLIO ceiling-anchors "$GEN/contract/folio-vision.vision.yaml"

# glossary: 主コレクション=terms / 消費必須=terms[0].formal_def (plain-<slug> の唯一の接地) / legit=単一 term 削除
#   ★assembler は stdout 専用 (usage: assemble-glossary.sh [contract] > out.html) ゆえ STDOUT: 指定。
#   ★prose は contract 名と非対称 (clinic-appointment.glossary.yaml ↔ clinic-glossary.prose.yaml)。
run_type_suite glossary STDOUT:glossary clinic-appointment.glossary.yaml clinic-glossary.prose.yaml \
  '.terms = []' '.terms[0].slug = null' '.terms[0].formal_def = ""' 'del(.terms[3])'
# ★glossary 固有 shape (per-shape MK doctrine): index 型ゆえ per-term 束縛が構造の要。
#   (1) plain_slot↔slug の per-card 束縛 (崩れると reviewer が別の語の平易定義を突き合わせる relocation 取り違え)。
cp "$GEN/contract/clinic-appointment.glossary.yaml" "$TMP/mk.glossary.yaml"
yq -i '.terms[0].plain_slot = "plain-WRONG"' "$TMP/mk.glossary.yaml"
assert_mk_kill "[glossary] a′ MK plain_slot≠plain-<slug> → per-card 束縛 FAIL (exit2・relocation 取り違え封鎖)" $FOLIO ceiling-anchors "$TMP/mk.glossary.yaml"
#   (2) term.domain が domains[].id に無い = 分野見出しから落ちる dangling 帰属。
cp "$GEN/contract/clinic-appointment.glossary.yaml" "$TMP/mk.glossary.yaml"
yq -i '.terms[0].domain = "no-such-domain"' "$TMP/mk.glossary.yaml"
assert_mk_kill "[glossary] a′ MK domain dangling → 帰属 guard FAIL (exit2)" $FOLIO ceiling-anchors "$TMP/mk.glossary.yaml"
#   (3) cover-summary は固定 separator ' ｜ ' 連結ゆえ subtitle 空でも恒真非空 = per-field guard が本体。
cp "$GEN/contract/clinic-appointment.glossary.yaml" "$TMP/mk.glossary.yaml"
yq -i '.meta.subtitle = ""' "$TMP/mk.glossary.yaml"
assert_mk_kill "[glossary] a′ MK meta.subtitle='' → cover hollow 封鎖 (exit2・(c) は連結で恒真 PASS)" $FOLIO ceiling-anchors "$TMP/mk.glossary.yaml"
# ★第 2 instance (folio-glossary = canonical_page 有 / 1 domain / cross_refs 空 12 件) の exit0 を pin。
#   instance 差 (domain 数・cross_refs 空) で over-block しないことの実弾 (per-shape MK は 1 instance で証明済としない)。
assert_exit "[glossary] a′ 第 2 instance (folio-glossary・1 domain / cross_refs 空 12 件) → exit0 維持" 0 $FOLIO ceiling-anchors "$GEN/contract/folio-glossary.glossary.yaml"

# architecture: 主コレクション=components / 消費必須=decisions[0].summary / legit=refs.adr 欠落 (AD-2/3/4 が実際に持たない)
run_type_suite architecture arch clinic-architecture.arch.yaml clinic-architecture.arch.prose.yaml \
  '.components = []' '.components[0].id = null' '.decisions[0].summary = ""' 'del(.decisions[0].refs.adr)'
# ★D2 (admin 裁定) の期待値 a′ を両方向で pin: registry key = canonical 'architecture' / contract_suffix = 略記 'arch'。
#   (1) --type architecture が verify-arch.sh へ直路一致することは run_type_suite の c′ が byte 一致で被覆済。
#   (2) suffix 'arch' の contract が **alias 経由で** canonical key 'architecture' に解決されること (検出層の責務)。
assert_eq "[architecture] D2 suffix 'arch' の contract が canonical doc_type 'architecture' へ alias 解決" "architecture" \
  "$($FOLIO ceiling-anchors "$GEN/contract/clinic-architecture.arch.yaml" 2>/dev/null | jq -r '.doc_type')"
assert_eq "[architecture] D2 registry key 'architecture' の floor が略記 suffix の verify-arch.sh を指す" "verify-arch.sh" \
  "$(yq -r '.doc_types.architecture.floor' "$REG")"
assert_eq "[architecture] D2 registry の contract_suffix が略記 'arch' (canonical key と別語彙であることの pin)" "arch" \
  "$(yq -r '.doc_types.architecture.contract_suffix' "$REG")"
# ★architecture 固有 shape: band 見出しの数詞 fidelity の判定材料 (.chapters は 2 キーのみ) と図 caption。
cp "$GEN/contract/clinic-architecture.arch.yaml" "$TMP/mk.arch.yaml"
yq -i '.chapters.components = ""' "$TMP/mk.arch.yaml"
assert_mk_kill "[architecture] a′ MK chapters.components='' → 数詞 fidelity の判定材料喪失 (exit2・floor の数詞照合は best-effort ゆえ ceiling 領分)" $FOLIO ceiling-anchors "$TMP/mk.arch.yaml"
cp "$GEN/contract/clinic-architecture.arch.yaml" "$TMP/mk.arch.yaml"
yq -i '.diagrams = []' "$TMP/mk.arch.yaml"
assert_mk_kill "[architecture] a′ MK diagrams=[] → 図 caption lens の判定材料喪失 (exit2・図↔カタログ対応が検査不能)" $FOLIO ceiling-anchors "$TMP/mk.arch.yaml"
cp "$GEN/contract/clinic-architecture.arch.yaml" "$TMP/mk.arch.yaml"
yq -i '.components[0].kind = "bogus"' "$TMP/mk.arch.yaml"
assert_mk_kill "[architecture] a′ MK component.kind allowlist 外 → kind 束縛 FAIL (exit2・actors と別 allowlist)" $FOLIO ceiling-anchors "$TMP/mk.arch.yaml"
cp "$GEN/contract/clinic-architecture.arch.yaml" "$TMP/mk.arch.yaml"
yq -i '.decisions[].refs.srs = [] | .decisions[].refs.adr = [] | .decisions[].refs.principle = []' "$TMP/mk.arch.yaml"
assert_mk_kill "[architecture] a′ MK 全 decision の refs 空 → 照会 leg hollow 封鎖 (exit2・合算 0 のみ)" $FOLIO ceiling-anchors "$TMP/mk.arch.yaml"

# testcases: 主コレクション=test_cases / 消費必須=test_cases[0].expected / legit=単一 glossary 語の削除
run_type_suite testcases testcases clinic-appointment.testcases.yaml clinic-appointment.testcases.prose.yaml \
  '.test_cases = []' '.test_cases[0].id = null' '.test_cases[0].expected = ""' 'del(.glossary[13])'
# ★testcases 固有 shape: 三段 trace は **per-card 必須** (arch の合算 idiom とは逆・hallmark の構造的担保)。
cp "$GEN/contract/clinic-appointment.testcases.yaml" "$TMP/mk.testcases.yaml"
yq -i '.test_cases[0].trace.confirms = []' "$TMP/mk.testcases.yaml"
assert_mk_kill "[testcases] a′ MK 単一 card の trace.confirms=[] → per-card 束縛 FAIL (exit2・合算では取り落とす片欠け)" $FOLIO ceiling-anchors "$TMP/mk.testcases.yaml"
#   kind は生トークンで出す以上 allowlist 外は内訳から silent に脱落する。
cp "$GEN/contract/clinic-appointment.testcases.yaml" "$TMP/mk.testcases.yaml"
yq -i '.test_cases[0].kind = "bogus"' "$TMP/mk.testcases.yaml"
assert_mk_kill "[testcases] a′ MK kind allowlist 外 → kind 束縛 FAIL (exit2・取り違え lens の SSoT 基準を保つ)" $FOLIO ceiling-anchors "$TMP/mk.testcases.yaml"
#   ★steps は assembler の validate() が非空を検査しない (実測) = anchor 側 per-row 束縛が唯一の fail-closed。
cp "$GEN/contract/clinic-appointment.testcases.yaml" "$TMP/mk.testcases.yaml"
yq -i '.test_cases[0].steps = []' "$TMP/mk.testcases.yaml"
assert_mk_kill "[testcases] a′ MK steps=[] → per-row 束縛 FAIL (exit2・assembler validate も未検査の穴)" $FOLIO ceiling-anchors "$TMP/mk.testcases.yaml"
cp "$GEN/contract/clinic-appointment.testcases.yaml" "$TMP/mk.testcases.yaml"
yq -i '.scope.out = []' "$TMP/mk.testcases.yaml"
assert_mk_kill "[testcases] a′ MK scope.out=[] → 「試さないこと」の grounding 喪失 (exit2・chapter-lead-01 hollow)" $FOLIO ceiling-anchors "$TMP/mk.testcases.yaml"

# datamodel: 主コレクション=entities / 消費必須=entities[0].description / legit=refs.srs 欠落 (practitioner が実際に持たない)
run_type_suite datamodel datamodel clinic-appointment.datamodel.yaml clinic-appointment.datamodel.prose.yaml \
  '.entities = []' '.entities[0].id = null' '.entities[0].description = ""' 'del(.entities[0].refs)'
# ★datamodel 固有 shape:
#   (1) invariant = 文書の中心 (「事故がデータの形として起こらない」宣言)。per-row 不可 (3/5 が legit に持たない) = 合算。
cp "$GEN/contract/clinic-appointment.datamodel.yaml" "$TMP/mk.datamodel.yaml"
yq -i '(.relationships[] | select(has("invariant")) | .invariant) = ""' "$TMP/mk.datamodel.yaml"
assert_mk_kill "[datamodel] a′ MK invariant 全空 → 文書の中心が hollow (exit2・合算 0 のみ・per-row 必須にしない)" $FOLIO ceiling-anchors "$TMP/mk.datamodel.yaml"
#   (2) inline principle (PRIN-DATA-MINIMUM) の genuine 性判定の SSoT anchor。★narrative は無い (vision と非対称)。
cp "$GEN/contract/clinic-appointment.datamodel.yaml" "$TMP/mk.datamodel.yaml"
yq -i '.principle.text = ""' "$TMP/mk.datamodel.yaml"
assert_mk_kill "[datamodel] a′ MK principle.text='' → genuine 性 (B3 graph-filler 弁別) の判定材料喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.datamodel.yaml"
#   (3) ER 図 lens: cardinality 記号写像 (||--o{ 等) は lines[] にしか現れず caption だけでは判定不能。
cp "$GEN/contract/clinic-appointment.datamodel.yaml" "$TMP/mk.datamodel.yaml"
yq -i '.diagrams[0].lines = []' "$TMP/mk.datamodel.yaml"
assert_mk_kill "[datamodel] a′ MK diagrams[0].lines=[] → 図↔カタログ対応 lens の判定材料喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.datamodel.yaml"
cp "$GEN/contract/clinic-appointment.datamodel.yaml" "$TMP/mk.datamodel.yaml"
yq -i '.relationships[0].cardinality = "many-to-many"' "$TMP/mk.datamodel.yaml"
assert_mk_kill "[datamodel] a′ MK cardinality allowlist 外 → 記号写像 lens の基準喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.datamodel.yaml"
cp "$GEN/contract/clinic-appointment.datamodel.yaml" "$TMP/mk.datamodel.yaml"
yq -i '.context.scope_note = ""' "$TMP/mk.datamodel.yaml"
assert_mk_kill "[datamodel] a′ MK context.scope_note='' → 委譲先 (この文書で決めないこと) の grounding 喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.datamodel.yaml"

# interface: 主コレクション=operations / 消費必須=errors[0].promise (文書の中心=正直な断り) / legit=errors[] 空の操作
run_type_suite interface interface clinic-appointment.interface.yaml clinic-appointment.interface.prose.yaml \
  '.operations = []' '.operations[0].id = null' '.errors[0].promise = ""' '.operations[1].errors = []'
# ★interface 固有 shape:
#   (1) 負の主張 (「断りなし」= errors[] 空) が anchor 表から消えていないこと (ehar クラス = 負の主張の束縛漏れ)。
#       空配列を join で空文字に潰すと、「断らない約束の操作に断りを作文した」捏造の判定基準が消える。
NOERR_ANCHOR="$($FOLIO ceiling-anchors "$GEN/contract/clinic-appointment.interface.yaml" 2>/dev/null \
  | jq -r '[.anchors[] | select(.slot | startswith("plain-")) | select(.ssot_value | contains("断りなし"))] | length')"
NOERR_CONTRACT="$(yq -r '[.operations[] | select(((.errors // []) | length) == 0)] | length' "$GEN/contract/clinic-appointment.interface.yaml")"
assert_eq "[interface] a′ 負の主張「断りなし」が anchor に per-op で束縛される (ehar クラス・空配列の潰れ封鎖)" "$NOERR_CONTRACT" "$NOERR_ANCHOR"
#   (2) binding 予約席 (null) が「未確定」として literal 接地される (プロトコル確定仕様として語る捏造の判定材料)。
assert_stdout_contains "[interface] a′ binding 予約席が anchor に literal 接地 (null を素で出さず予約席と明示)" "予約席=未確定" \
  $FOLIO ceiling-anchors "$GEN/contract/clinic-appointment.interface.yaml"
#   (3) direction allowlist (out|in): 意味逆転 = critical lens の判定材料。
cp "$GEN/contract/clinic-appointment.interface.yaml" "$TMP/mk.interface.yaml"
yq -i '.external[0].direction = "sideways"' "$TMP/mk.interface.yaml"
assert_mk_kill "[interface] a′ MK external.direction allowlist 外 → 束縛 FAIL (exit2・out↔in 意味逆転 lens の基準を保つ)" $FOLIO ceiling-anchors "$TMP/mk.interface.yaml"
#   (4) op が参照する error id の dangling (断りの宛先が消える)。
cp "$GEN/contract/clinic-appointment.interface.yaml" "$TMP/mk.interface.yaml"
yq -i '.operations[1].errors = ["E-NO-SUCH"]' "$TMP/mk.interface.yaml"
assert_mk_kill "[interface] a′ MK op→error dangling → 宛先 guard FAIL (exit2)" $FOLIO ceiling-anchors "$TMP/mk.interface.yaml"
#   (5) scope_note = binding 不扱い + 委譲先の唯一の grounding。
cp "$GEN/contract/clinic-appointment.interface.yaml" "$TMP/mk.interface.yaml"
yq -i '.context.scope_note = ""' "$TMP/mk.interface.yaml"
assert_mk_kill "[interface] a′ MK context.scope_note='' → binding 不扱い/委譲先の grounding 喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.interface.yaml"
#   (6) refs.srs は interface では per-row 非空が契約 (arch/datamodel の「空 legit ゆえ合算」を逆向きに写さない)。
cp "$GEN/contract/clinic-appointment.interface.yaml" "$TMP/mk.interface.yaml"
yq -i '.operations[0].refs.srs = []' "$TMP/mk.interface.yaml"
assert_mk_kill "[interface] a′ MK operation.refs.srs=[] → per-row 束縛 FAIL (exit2・型ごとに legit 性が違う)" $FOLIO ceiling-anchors "$TMP/mk.interface.yaml"

# risk: 主コレクション=risks / 消費必須=risks[0].mitigation / legit=単一 glossary 語の削除
run_type_suite risk risk clinic-risk.risk.yaml clinic-risk.risk.prose.yaml \
  '.risks = []' '.risks[0].id = null' '.risks[0].mitigation = ""' 'del(.glossary[13])'
# ★risk 固有 shape:
#   (1) severity は contract に持たない導出値 (likelihood×impact)。anchor は生 L/M/H だけを載せ再計算しない
#       (再計算 = 導出規則の第 2 SSoT でドリフトする / floor が既に card・matrix・tally の導出一致を数値で担保)。
assert_eq "[risk] a′ anchor が severity を再計算しない (生 likelihood/impact のみ接地・導出は floor の領分)" "0" \
  "$($FOLIO ceiling-anchors "$GEN/contract/clinic-risk.risk.yaml" 2>/dev/null | jq -r '[.anchors[] | select(.ssot_value | test("深刻度=(低|中|高)"))] | length')"
#   (2) contract 側に severity が現れたら第 2 SSoT = 捏造経路。
cp "$GEN/contract/clinic-risk.risk.yaml" "$TMP/mk.risk.yaml"
yq -i '.risks[0].severity = "高"' "$TMP/mk.risk.yaml"
assert_mk_kill "[risk] a′ MK contract に severity 出現 → 導出値の第 2 SSoT 封鎖 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.risk.yaml"
#   (3) likelihood/impact allowlist (L|M|H) = severity 導出の入力・status allowlist = 状態バッジ lens の材料。
cp "$GEN/contract/clinic-risk.risk.yaml" "$TMP/mk.risk.yaml"
yq -i '.risks[0].likelihood = "VeryHigh"' "$TMP/mk.risk.yaml"
assert_mk_kill "[risk] a′ MK likelihood allowlist 外 → 導出入力の束縛 FAIL (exit2)" $FOLIO ceiling-anchors "$TMP/mk.risk.yaml"
cp "$GEN/contract/clinic-risk.risk.yaml" "$TMP/mk.risk.yaml"
yq -i '.risks[0].status = "bogus"' "$TMP/mk.risk.yaml"
assert_mk_kill "[risk] a′ MK status allowlist 外 → 状態バッジ lens の基準喪失 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.risk.yaml"
#   (4) trace.refs は risk では per-row 必須 (changelog/roadmap の片側空 legit とは非対称)。
cp "$GEN/contract/clinic-risk.risk.yaml" "$TMP/mk.risk.yaml"
yq -i '.risks[0].trace.refs = []' "$TMP/mk.risk.yaml"
assert_mk_kill "[risk] a′ MK trace.refs=[] → per-row 束縛 FAIL (exit2・脅かす要件の無いリスクは構造不正)" $FOLIO ceiling-anchors "$TMP/mk.risk.yaml"

# changelog: 主コレクション=entries / 消費必須=item text / legit=片側 refs 空 (実測 8/10 が片側空)
run_type_suite changelog changelog clinic-changelog.changelog.yaml clinic-changelog.changelog.prose.yaml \
  '.entries = []' '.entries[0].categories.added[0].id = null' '.entries[0].categories.added[0].text = ""' '.entries[0].categories.added[0].refs.adr = []'
# ★changelog 固有 shape:
#   (1) 負の主張 (「0 件 = この種別は変更なし」) が latest-highlight に 0 込みで全列挙されること (ehar クラス)。
#       0 件区分を省略すると「変更なし」の主張が anchor から消え、prose の作文を判定できなくなる。
CL_HL="$($FOLIO ceiling-anchors "$GEN/contract/clinic-changelog.changelog.yaml" 2>/dev/null | jq -r '.anchors[] | select(.slot=="latest-highlight") | .ssot_value')"
for cat in added changed deprecated removed fixed security; do
  if [[ "$CL_HL" == *"$cat="* ]]; then ok "[changelog] a′ latest-highlight が区分 '$cat' を 0 込みで列挙 (負の主張の束縛)"; else ng "[changelog] a′ latest-highlight に区分 '$cat' が無い (0 件省略 = 負の主張の消失)"; fi
done
#   (2) 区分 allowlist (map のキーが区分・kind フィールドではない)。
cp "$GEN/contract/clinic-changelog.changelog.yaml" "$TMP/mk.changelog.yaml"
yq -i '.entries[0].categories.bogus = [{"id":"CX","text":"x","refs":{"srs":["FR1"]}}]' "$TMP/mk.changelog.yaml"
assert_mk_kill "[changelog] a′ MK categories キーが allowlist 外 → 区分束縛 FAIL (exit2)" $FOLIO ceiling-anchors "$TMP/mk.changelog.yaml"
#   (3) 空 category (キーはあるが item 0) = 負の主張の表現が 2 通りになり束縛が壊れる (0 件はキー省略が規約)。
cp "$GEN/contract/clinic-changelog.changelog.yaml" "$TMP/mk.changelog.yaml"
yq -i '.entries[0].categories.changed = []' "$TMP/mk.changelog.yaml"
assert_mk_kill "[changelog] a′ MK 空 category → 0 件の二重表現封鎖 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.changelog.yaml"
#   (4) refs 両側空 = どの要件のためでも なぜでもない変更 (片側空は legit ゆえ per-row 非空にしない)。
cp "$GEN/contract/clinic-changelog.changelog.yaml" "$TMP/mk.changelog.yaml"
yq -i '.entries[0].categories.added[0].refs.srs = [] | .entries[0].categories.added[0].refs.adr = []' "$TMP/mk.changelog.yaml"
assert_mk_kill "[changelog] a′ MK refs 両側空 → grounding 喪失 (exit2・片側空は legit のまま)" $FOLIO ceiling-anchors "$TMP/mk.changelog.yaml"

# roadmap: 主コレクション=stages / 消費必須=item text / legit=片側 refs 空 (実測 RM2/RM4/RM8)
run_type_suite roadmap roadmap clinic-roadmap.roadmap.yaml clinic-roadmap.roadmap.prose.yaml \
  '.stages = []' '.stages[0].items.must[0].id = null' '.stages[0].items.must[0].text = ""' '.stages[0].items.must[0].refs.vision = []'
# ★roadmap 固有 shape:
#   (1) 負の主張 (「0 件 = この優先度の目標なし」) が nearest-highlight に 0 込みで全列挙されること。
RM_HL="$($FOLIO ceiling-anchors "$GEN/contract/clinic-roadmap.roadmap.yaml" 2>/dev/null | jq -r '.anchors[] | select(.slot=="nearest-highlight") | .ssot_value')"
for prio in must should could; do
  if [[ "$RM_HL" == *"$prio="* ]]; then ok "[roadmap] a′ nearest-highlight が優先度 '$prio' を 0 込みで列挙 (負の主張の束縛)"; else ng "[roadmap] a′ nearest-highlight に優先度 '$prio' が無い (0 件省略 = 負の主張の消失)"; fi
done
#   (2) ★自前 principle 終端の捏造は c5r.11 で不採択 — roadmap は VISION 経由で終端到達する型ゆえ
#       .principle 不在が *正* であり、出現したら graph 充足のための作文終端。
cp "$GEN/contract/clinic-roadmap.roadmap.yaml" "$TMP/mk.roadmap.yaml"
yq -i '.principle = {"id":"PRIN-FAKE","text":"作文終端"}' "$TMP/mk.roadmap.yaml"
assert_mk_kill "[roadmap] a′ MK 自前 principle 出現 → 作文終端封鎖 (exit2・c5r.11 不採択の SSoT 側 pin)" $FOLIO ceiling-anchors "$TMP/mk.roadmap.yaml"
#   (3) seq = 段階順 (近い→遠い) の SSoT。重複すると直近段階の決定が非決定的になる。
cp "$GEN/contract/clinic-roadmap.roadmap.yaml" "$TMP/mk.roadmap.yaml"
yq -i '.stages[1].seq = 1' "$TMP/mk.roadmap.yaml"
assert_mk_kill "[roadmap] a′ MK seq 重複 → 直近段階の決定が非決定的 (exit2)" $FOLIO ceiling-anchors "$TMP/mk.roadmap.yaml"
#   (4) 優先度 allowlist (map のキーが優先度)。
cp "$GEN/contract/clinic-roadmap.roadmap.yaml" "$TMP/mk.roadmap.yaml"
yq -i '.stages[0].items.bogus = [{"id":"RMX","text":"x","refs":{"srs":["FR1"]}}]' "$TMP/mk.roadmap.yaml"
assert_mk_kill "[roadmap] a′ MK items キーが allowlist 外 → 優先度束縛 FAIL (exit2)" $FOLIO ceiling-anchors "$TMP/mk.roadmap.yaml"

# ===========================================================================
echo "== 用語集 chapter-lead の hollow-anchor MK (固定ラベルのみ = 計数恒真 PASS の class 封鎖) =="
# ===========================================================================
# ★SF-5 が per-type authoring の要件に挙げる「固定ラベルで恒真非空になる hollow-anchor class を洗い
#   合算非空 guard + per-shape mutation-kill を同梱」の、 用語集章ぶん。 glossary=[] を与えると当該 chapter-lead は
#   ssot_value が固定ラベル ("用語集: " / "用語: ") だけの **データ接地ゼロ** な anchor になるが、
#   (c) invariant は行が非空ゆえ発火せず、 gloss_expected も `-gt 0` gate 付きの term-inline 件数照合にしか
#   使われないため 0 件が素通りする (計数恒真 PASS = jyfh/u7y2 クラス)。 到達可能性も実測済:
#   assembler は空 glossary を拒否せず用語集 band と slot を無条件 emit するため degenerate 入力ではない。
#   ★shape は各型の **実 contract instance** で撃つ (per-shape MK doctrine)。 対象外の 2 型:
#     - vision   : 設計上 用語集章を持たない (可視 slot は cover + chapter-lead 7 本のみ)。
#     - glossary : glossary が主コレクション = 既に mk_coll ('.terms = []') で被覆済。
for _gp in "research:clinic-double-booking.research.yaml" "principle:folio-constitution.principle.yaml" \
           "architecture:clinic-architecture.arch.yaml" "testcases:clinic-appointment.testcases.yaml" \
           "datamodel:clinic-appointment.datamodel.yaml" "interface:clinic-appointment.interface.yaml" \
           "risk:clinic-risk.risk.yaml" "changelog:clinic-changelog.changelog.yaml" \
           "roadmap:clinic-roadmap.roadmap.yaml"; do
  _t="${_gp%%:*}"; _f="${_gp#*:}"
  # MK 一時 contract は既存どおり **contract_suffix** で命名する (registry key で置くと architecture のように
  # key≠suffix の型で検出層が先に exit2 に落ち guard 未到達の偽 PASS になる)。
  _sfx="$(yq -r ".doc_types.\"$_t\".contract_suffix" "$REG")"
  cp "$GEN/contract/$_f" "$TMP/mk.$_sfx.yaml"
  yq -i '.glossary = []' "$TMP/mk.$_sfx.yaml"
  assert_mk_kill "[$_t] a′ MK glossary=[] → 用語集章が固定ラベルのみの hollow anchor (exit2・計数恒真 PASS 封鎖)" \
    $FOLIO ceiling-anchors "$TMP/mk.$_sfx.yaml"
done

# ===========================================================================
echo "== SF-7 閉包: registry wired 集合 == acceptance 被覆集合 == 検出層 allowlist =="
# ===========================================================================
# ★SF-7 (「registry flip と anchor 分岐は同一 commit で束ね片方だけの land 禁止」) を機械に束縛する。
#   これが無いと run_type_suite の呼出しが hardcoded な列挙のままで、 registry の wired 集合が loop を
#   駆動しない = 「flip したのに acceptance suite が無い型」が緑のまま land する (half-wired fail-open)。
#   今日この half-wire が偶然赤くなるのは C2 が registry から UNWIRED を解決し spec が唯一の未配線型ゆえ
#   空集合→ng になるという *副作用* であって、 被覆閉包の不変条件ではない (15 番目の doc-type が unwired で
#   registry に入った瞬間 C2 は新型を sentinel に拾い、 spec の half-wire は緑で通る)。 C2 の番人 doctrine
#   (「番人を絶やすと行動契約が無検査になる」) を型被覆そのものにも適用する。
wired_set="$(yq -r '.doc_types | to_entries | map(select(.value.wired == true)) | .[].key' "$REG" | LC_ALL=C sort)"
covered_set="$(printf '%s\n' srs adr "${COVERED[@]}" | LC_ALL=C sort)"
if [[ "$wired_set" == "$covered_set" ]]; then
  ok "SF-7 閉包: registry wired 集合 == per-type acceptance 被覆集合 (srs/adr は block (a)/(d) が被覆)"
else
  ng "SF-7 閉包 破れ: registry を flip したのに acceptance suite が無い型がある (half-wired land)。 registry のみ: $(comm -23 <(printf '%s\n' "$wired_set") <(printf '%s\n' "$covered_set") | tr '\n' ' ')/ suite のみ: $(comm -13 <(printf '%s\n' "$wired_set") <(printf '%s\n' "$covered_set") | tr '\n' ' ')"
fi
# ★検出層 allowlist と registry の同期 (double-SSoT の drift 封鎖): registry.contract_suffix と
#   ceiling-anchors の検出層 case 文は同期チェック無しの double-SSoT であり、 SKILL.md §2 の
#   「対応集合は registry と同期」は本 assert が無いと未検証の claim になる。 suffix→canonical 写像を実測で pin
#   (D2 の arch→architecture alias もここで両方向に束縛される)。
for t in $wired_set; do
  sfx="$(yq -r ".doc_types.\"$t\".contract_suffix" "$REG")"
  c="$(ls "$GEN/contract/"*."$sfx".yaml 2>/dev/null | head -1)"
  [[ -n "$c" ]] || { ng "[$t] wired だが contract_suffix '$sfx' の contract 実体が無い"; continue; }
  dt="$($FOLIO ceiling-anchors "$c" 2>/dev/null | jq -r '.doc_type')"
  assert_eq "[$t] 検出層 allowlist が registry.contract_suffix '$sfx' を canonical '$t' へ写像" "$t" "$dt"
done

# ===========================================================================
echo "== per-card 束縛の式インジェクション kill (changelog / roadmap の 2 shape に per-shape 実弾) =="
# ===========================================================================
# ★背景 (fail-open 実弾): 新 11 型のうち 9 型は per-card 値を数値 index で引くためインジェクション不能だが、
#   changelog / roadmap の 2 型だけは contract 由来の id/version を yq 式の **文字列本文へ補間**して再照合して
#   いた (select(.id == "$rmid"))。 この形は細工値で述語を恒真化でき、 「この card の SSoT 期待」として
#   **別 card の内容を連結した** anchor を exit 0 で emit した (= SF-5 が禁ずる verify-laundering / relocation
#   クラスを、 fail-closed であるべき検証機械自身が通す)。 既存 guard は 3 つとも素通りする:
#   (a) assert_slot_unique = slot 名自体は一意、 (b) 件数照合 = id 1 個につき 1 行のまま、
#   (c) assert_no_empty_anchor = 値はむしろ *過剰に非空*。 ゆえに専用の実弾が要る。
# ★oracle は exit ではなく **束縛の濃度** (card marker の出現数): 細工 id は contract に実在する id へ書くため
#   strenv 束縛後も 1 件 hit = exit 0 が正であり、 exit2 を期待すると恒真 PASS になる。 「1 件だけに束縛された
#   か / 全 card が混ざったか」だけが修正の有無を弁別する (修正前=全件連結・修正後=1 件)。
# ★per-shape に 2 発撃つ: changelog(entries[].categories{} map) と roadmap(stages[].items{} map) は DOM 構造が
#   別ゆえ、 1 instance の kill は他方の穴を証明しない (記憶 doctrine: MK は per-shape)。
assert_bind_cardinality() { # <label> <contract> <marker> <id-write-expr>
  local label="$1" src="$2" marker="$3" expr="$4"
  local f="$TMP/inj.$(basename "$src")"
  cp "$src" "$f"
  yq -i "$expr" "$f" || { ng "$label (MK contract の細工に失敗)"; return; }
  local out n
  out="$($FOLIO ceiling-anchors "$f" 2>/dev/null | jq -r --arg m 'or true or' '.anchors[] | select(.slot | contains($m)) | .ssot_value')"
  if [[ -z "$out" ]]; then ng "$label (細工 slot が emit されず = MK 未到達・oracle 不成立)"; return; fi
  n="$(printf '%s' "$out" | grep -o "$marker" | wc -l | tr -d ' ')"
  if [[ "$n" == "1" ]]; then
    ok "$label (束縛濃度=1 = 当該 card のみ・式インジェクション不能)"
  else
    ng "$label (束縛濃度=$n ≠ 1 = 述語が恒真化し別 card が混入した mis-bound anchor を exit 0 で emit)"
  fi
}
# changelog shape: entries[].categories.<区分>[].id を細工 → plain-<id> が全 entry を連結しないこと。
_cl_first="$(yq -r '[(.unreleased // {}), (.entries[])] | .[] | (.categories // {}) | to_entries[] | .value[] | .id' "$GEN/contract/clinic-changelog.changelog.yaml" 2>/dev/null | head -1)"
assert_bind_cardinality "MK-inj changelog: plain-<id> が per-card 束縛 (別 entry 混入 kill)" \
  "$GEN/contract/clinic-changelog.changelog.yaml" '版=' \
  "(.. | select(has(\"id\")) | select(.id == \"$_cl_first\") | .id) = \"$_cl_first\\\" or true or \\\"\""
# roadmap shape: stages[].items.<優先度>[].id を細工 → plain-<id> が全 stage を連結しないこと。
_rm_first="$(yq -r '.stages[] | .items | to_entries[] | .value[] | .id' "$GEN/contract/clinic-roadmap.roadmap.yaml" 2>/dev/null | head -1)"
assert_bind_cardinality "MK-inj roadmap: plain-<id> が per-card 束縛 (別 stage 混入 kill)" \
  "$GEN/contract/clinic-roadmap.roadmap.yaml" '段階=' \
  "(.. | select(has(\"id\")) | select(.id == \"$_rm_first\") | .id) = \"$_rm_first\\\" or true or \\\"\""

# ===========================================================================
echo "== a′ per-shape MK: @tsv 列ずれの tab shape (multi-field read を持つ 3 型) =="
# ===========================================================================
# ★shape 欠落だった (folio-vxpc errata): 上の research shift MK は「空フィールド」shape *だけ* を撃ち、
#   **tab 混入** shape を一度も撃っていなかった。 両者は構造差がある — 空フィールドは連続 tab の畳み込みで
#   左詰めシフトするのに対し、 tab 混入は *区切りが 1 本増える* ことで右詰めシフトする。
# ★なぜ tab が素通りしたか (parser-differential・r8k クラス): mikefarah yq の @tsv は jq と非同型で tab を
#   \t へ escape せず値ごと CSV-quote する。 よって tab は生のまま区切りとして働き read がシフトし、
#   label↔value の per-card 束縛が崩れた anchor を **exit 0 で** emit していた (実測: glossary canonical へ
#   tab 1 個 → `分野:` に en 値・`正式定義:` に domain 値 = reviewer が偽の SSoT 接地を受け取る)。
#   改行 shape は件数照合 plain-slug(26≠25) で fail-closed に倒れるため、 tab shape だけが穴だった
#   (partial-enumeration trap: 2 shape のうち片方だけが塞がっていた)。
# ★per-shape で撃つ: multi-field read は型ごとに field 数が違う (principle=3 / glossary=5 / architecture=2)。
#   1 型の実弾は field 数の違う型の穴を証明しない (jyfh/r8k の per-shape 要件)。 いずれも **中間** フィールドへ
#   注入して右詰めシフトを起こす。
cp "$GEN/contract/folio-constitution.principle.yaml" "$TMP/mk.principle.yaml"
yq -i '.principles[0].heading = "AAA" + ("X"|sub("X";"\t")) + "BBB"' "$TMP/mk.principle.yaml"
assert_mk_kill "[principle] a′ MK 中間フィールドへ tab 注入 (3-field read) → @tsv 列ずれ fail-closed (exit2・statement が heading 位置へ混入する relocation 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.principle.yaml"

cp "$GEN/contract/clinic-appointment.glossary.yaml" "$TMP/mk.glossary.yaml"
yq -i '.terms[0].canonical = "AAA" + ("X"|sub("X";"\t")) + "BBB"' "$TMP/mk.glossary.yaml"
assert_mk_kill "[glossary] a′ MK 中間フィールドへ tab 注入 (5-field read) → @tsv 列ずれ fail-closed (exit2・label↔value の per-card relocation 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.glossary.yaml"

#   architecture の multi-field read は `decisions[].id + .title` (2-field) ゆえ、 その read が実際に消費する
#   field へ撃つ (components[].name へ撃っても guard は鳴るが 2-field read の shape を撃ったことにならない)。
cp "$GEN/contract/clinic-architecture.arch.yaml" "$TMP/mk.arch.yaml"
yq -i '.decisions[0].id = "AAA" + ("X"|sub("X";"\t")) + "BBB"' "$TMP/mk.arch.yaml"
assert_mk_kill "[architecture] a′ MK 中間フィールドへ tab 注入 (2-field read: decisions.id) → @tsv 列ずれ fail-closed (exit2・id 断片が title 位置へ混入する relocation 封鎖)" $FOLIO ceiling-anchors "$TMP/mk.arch.yaml"

# ★陰性対照: guard が over-block していないこと (tab 無しの正常 contract は今も exit0)。 これが無いと上の 3 本は
#   「常に exit2」でも緑になる恒真 MK になりうる。 SRS/adr の SHA pin (下の d′) が byte 不変であることと対で、
#   guard が valid contract の emit path を 1 byte も動かしていないことを示す。
assert_exit "[principle] a′ tab 無し正常 contract は exit0 維持 (guard の over-block 陰性対照)" 0 $FOLIO ceiling-anchors "$GEN/contract/folio-constitution.principle.yaml"

# ===========================================================================
echo "== d′ 拡張の緩和 pin: GREEN 主張パターンの実弾 (捏造 kill / 否定文の陰性対照) =="
# ===========================================================================
# ★run_type_suite の d′ floor stdout 番人は「bare token grep」を「GREEN *主張* パターン」へ精密化している。
#   精密化は緩和の一種であり、 緩和は必ず MK 同梱で「番人を殺していない」ことを実弾で示す (memory doctrine:
#   緩和 scope-leak / nsa)。 陽性 (捏造を殺せる) と陰性 (否定文を誤検出しない) の両対照を置く。
# ★上の緩和 (主張パターンへ狭めたこと) が番人を殺していないことを実弾で pin (memory doctrine: 緩和は
#   必ず MK 同梱。 狭めた結果「本物の GREEN 捏造」を見逃すなら、 それは番人の喪失であって精密化ではない)。
_mk_green_fab="RESULT: GREEN (全 gate 通過)"
if printf '%s' "$_mk_green_fab" | grep -qE 'RESULT:[^—]*GREEN|GREEN 認定|全 gate.*GREEN'; then
  ok "MK 緩和 pin: 本物の 'RESULT: GREEN' 捏造は今も主張パターンで殺せる"
else
  ng "MK 緩和 pin 破れ: 主張パターンが 'RESULT: GREEN' 捏造を見逃す = 緩和が番人を殺した (fail-open)"
fi
# ★対の陰性対照: 現行 sentinel の否定文が主張パターンに *引っかからない* こと (引っかかるなら上の番人は
#   恒真 ng = 9 suite の bare grep と同じ衝突を dispatch 側へ持ち込んだだけになる)。
_mk_green_neg="RESULT: floor PASS (mode=artifact) — ただし CEILING=PENDING (*GREEN ではない*)"
if printf '%s' "$_mk_green_neg" | grep -qE 'RESULT:[^—]*GREEN|GREEN 認定|全 gate.*GREEN'; then
  ng "MK 陰性対照 破れ: sentinel の否定文を主張と誤検出 (lexical 衝突を再生産)"
else
  ok "MK 陰性対照: sentinel の「GREEN ではない」否定文は主張と誤検出されない"
fi

echo "== 結果: PASS=$pass FAIL=$fail =="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
