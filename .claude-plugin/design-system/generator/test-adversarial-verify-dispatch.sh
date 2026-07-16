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
assert_exit            "C2 未配線 type(vision) → exit 2"     2 $FOLIO verify --type vision "$TMP/x.html" "$TMP/x.yaml"
assert_stderr_contains "C2 未配線 type → 'not yet wired'"    "not yet wired" $FOLIO verify --type vision "$TMP/x.html" "$TMP/x.yaml"
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

MK="$TMP/mk.adr.yaml"
# per-shape mutation-kill: ADR の options/glossary という新 structural shape を壊し fail-closed 転落を実証。
cp "$ADR_C" "$MK"; yq -i '.options = []' "$MK"
assert_exit "A1 MK options=[] → 空 manifest fail-open 封鎖 (exit2)" 2 $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.options[0].id = null' "$MK"
assert_exit "A2 MK option id=null → opt-id guard FAIL (exit2)" 2 $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.options[0].id = ""' "$MK"
assert_exit "A3 MK option id=空文字 → opt-id guard FAIL (exit2)" 2 $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.glossary += [{"term":"満枠","en":"f2","plain_short":"別","def":"重複語。"}]' "$MK"
assert_exit "A4 MK term 重複 → slot 一意 guard FAIL (exit2)" 2 $FOLIO ceiling-anchors "$MK"
# ★decision-rationale が消費する context/drivers の per-shape MK (finding round-1 #2)。 count 0==0 で floor を
#   素通る構造的に空虚な ADR を ceiling-anchors 側で fail-closed に落とす (decision-rationale の hollow 化封鎖)。
cp "$ADR_C" "$MK"; yq -i '.context = []' "$MK"
assert_exit "A5 MK context=[] → context空 guard FAIL (exit2・decision-rationale hollow 封鎖)" 2 $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i '.drivers = []' "$MK"
assert_exit "A6 MK drivers=[] → drivers空 guard FAIL (exit2・decision-rationale hollow 封鎖)" 2 $FOLIO ceiling-anchors "$MK"
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
assert_exit "A9 MK 全 option pros/cons=[] → pros/cons全空 guard FAIL (exit2・decision-rationale hollow 封鎖)" 2 $FOLIO ceiling-anchors "$MK"
# ★M1 受け入れ条件: 単一 option の pros/cons 欠落は legit (比較根拠は他 option で継続) = exit0 を維持する (over-block 防止)。
cp "$ADR_C" "$MK"; yq -i '.options[0].pros = [] | .options[0].cons = []' "$MK"
assert_exit "A10 MK 単一 option pros/cons=[] (legit) → exit0 維持 (per-option 必須にしない)" 0 $FOLIO ceiling-anchors "$MK"
# ★round-2 S1: consequences (chapter-lead-05) / supersession+principle (chapter-lead-06) の同型 hollow anchor を
#   合算非空 guard が撃つ (M1 と root-cause 同一・固定ラベル恒真非空の class ごと封鎖)。
cp "$ADR_C" "$MK"; yq -i '.consequences.positive = [] | .consequences.negative = []' "$MK"
assert_exit "A11 MK consequences 全空 → consequences全空 guard FAIL (exit2・chapter-lead-05 hollow 封鎖)" 2 $FOLIO ceiling-anchors "$MK"
cp "$ADR_C" "$MK"; yq -i 'del(.supersession.status) | del(.principle.text)' "$MK"
assert_exit "A12 MK supersession.status+principle.text 両空 → supersession+principle全空 guard FAIL (exit2・chapter-lead-06 hollow 封鎖)" 2 $FOLIO ceiling-anchors "$MK"

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

echo "== 結果: PASS=$pass FAIL=$fail =="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
