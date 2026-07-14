#!/usr/bin/env bash
# folio engine (folio-dvsk) — glossary en parity gate の敵対回帰テスト。
#
# gate 自体の正しさを検査する: (a) recall = en drift / SSoT 未収録 / 分類漏れ / anchor 崩壊を FAIL に落とす、
# (b) precision = clean corpus と「anchor 不在の local 語」(intersect の批准済み緩和) を誤検出しない、
# (c) fail-closed = SSoT 不在・非配列 glossary・空 en 等の変形入力が緑に化けない、 (d) exit-code 規約 (0/1/2)。
#
# ★FAIL 系 pin の reason substring は FAIL 行にしか出ない値 (mutation sentinel "XQZ" 等) を使う
#   (c5r.2 教訓: chk label は [OK] 行にも出て判別力ゼロ)。 合否は exit-code + substring の両建て。
# temp corpus を cp で作り yq -i で改竄して gate を走らせる。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-glossary-parity.sh"
SRC_CONTRACT="$SCRIPT_DIR/contract"
[[ -x "$GATE" ]] || { echo "FATAL: gate not executable: $GATE" >&2; exit 2; }
command -v yq >/dev/null || { echo "FATAL: yq required" >&2; exit 2; }

pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad() { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

fresh_corpus() { local d; d="$(mktemp -d)"; cp "$SRC_CONTRACT"/*.yaml "$d"/; printf '%s' "$d"; }

# expect_fail <label> <corpus> <substring> — exit 1 かつ FAIL 行に substring
expect_fail() {
  local label="$1" dir="$2" sub="$3" out rc
  out="$("$GATE" --contract-dir "$dir" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -F -- "$sub" <<<"$out" | grep -q '\[FAIL\]'; then ok "$label"
  else bad "$label (rc=$rc / substring '$sub' の FAIL 行なし)"; fi
}
# expect_pass <label> <corpus> [<substring>] — exit 0 (substring 指定時は出力に必須)
expect_pass() {
  local label="$1" dir="$2" sub="${3:-}" out rc
  out="$("$GATE" --contract-dir "$dir" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 && ( -z "$sub" || "$out" == *"$sub"* ) ]]; then ok "$label"
  else bad "$label (rc=$rc)"; fi
}

echo "== glossary en parity gate 敵対回帰 =="

# --- V0 baseline: clean corpus → exit 0 + 分類/件数 pin ---
# ★意図的 count pin (vacuous-green 防止・status-flip 教訓と同型): corpus 成長 (contract 追加・glossary 語の
#   増減・registry 改訂) で dirty になる。 更新時は verify-glossary-parity.sh の実出力から転記し、 分類数を
#   registry 行数・語数を contract 実データから独立再導出して確認すること。
#   lineage: 2026-07-05 (folio-dvsk 初版) = 14 contract (full 9 / intersect 4 / exempt 1)・en 突合 116 語・
#   anchor 外 local 9 語 (clinic glossary chrome 3 + folio-constitution 4 + folio-glossary chrome 2)。
#   2026-07-07 (folio-1q8o data-model-pack) = 15 contract (full 9 / intersect 5 / exempt 1)・en 突合 116 語 (不変)・
#   anchor 外 local 15 語 (+ datamodel の data-modeling メタ語 6: エンティティ/ER 図/不変条件/識別子/区分/参照 = clinic union SSoT 外)。
#   2026-07-07 (folio-ehar interface-pack) = 16 contract (full 9 / intersect 6 / exempt 1)・en 突合 116 語 (不変)・
#   anchor 外 local 20 語 (+ interface のメタ語 5: 操作/境界 (インターフェース)/エラーカタログ/外部連携/横断の決まり = clinic union SSoT 外・en 突合 0)。
#   2026-07-12 (folio-49x) relations を full→intersect 再分類 = 16 contract (full 8 / intersect 7 / exempt 1)・en 突合 116 語・anchor 外 local 29 語 (+ relations 主題語 9)。※本 V0 pin の同期は 2026-07-14 (wdv0 land) まで漏れており latent 赤だった (pin drift)。
#   2026-07-14 (folio-wdv0 risk-register-pack) = 17 contract (full 8 / intersect 8 / exempt 1)・en 突合 124 語・anchor 外 local 35 語 (clinic-risk は union 外の新 source ゆえ intersect = datamodel/interface と同型)。
#   2026-07-14 (folio-8ptq changelog-pack) = 18 contract (full 8 / intersect 9 / exempt 1)・en 突合 128 語 (+ changelog の clinic union 語 4)・anchor 外 local 41 語 (+ changelog メタ語 6 = clinic union SSoT 外・intersect = risk/datamodel/interface と同型)。
#   2026-07-14 (folio-pyus rules 再抽出・folio-7ts2 3 語収録の帰結) = 18 contract (分類不変 8/9/1)・en 突合 129 語 (folio-rules に 'design-intent space' 追加 25→26 語・anchor は 7ts2 で収録済ゆえ突合 +1)・anchor 外 local 41 語 (不変)。
#   2026-07-14 (folio-8cha roadmap-pack・pyus 129/41 基準へ merged tree 実測で再同期) = 19 contract (full 8 / intersect 10 / exempt 1)・en 突合 133 語 (129 + roadmap の clinic union 語 4: 診療枠/満枠/本人確認/リマインド通知)・anchor 外 local 44 語 (+ roadmap メタ語 3: ロードマップ/マイルストーン/優先度 = clinic union SSoT 外・intersect = changelog/risk/datamodel/interface と同型)。
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'full=8 intersect=10 exempt=1 未登録空=0' <<<"$out" \
   && grep -q 'en 突合 133 語・anchor 外 local 44 語' <<<"$out"; then
  ok "V0 baseline: clean corpus → exit 0 + 分類 19 本 (8/10/1) + 133/44 語 pin"
else bad "V0 baseline: clean corpus が期待 pin と不一致 (rc=$rc・corpus 成長なら pin を lineage 手順で更新)"; fi

# --- V1 en-drift (full mode): source の en を SSoT からずらす → FAIL ---
D="$(fresh_corpus)"
yq -i '(.glossary[] | select(.term == "診療枠") | .en) = "appointment slotXQZ"' "$D/clinic-appointment.srs.yaml"
expect_fail "V1 en-drift(full): clinic srs 診療枠 en 改竄 → FAIL" "$D" "appointment slotXQZ"
rm -rf "$D"

# --- V2 ssot-missing (full mode): SSoT 未収録の新語を source に注入 → FAIL (union 不変条件) ---
D="$(fresh_corpus)"
yq -i '.glossary += [{"term": "怪しい新語", "en": "sus term", "plain_short": "x", "def": "y"}]' "$D/clinic-appointment.testcases.yaml"
expect_fail "V2 ssot-missing(full): SSoT 未収録語の注入 → FAIL" "$D" "ssot-missing term='怪しい新語'"
rm -rf "$D"

# --- V3 en-drift (intersect mode): SSoT 収録語は intersect でも en 逐語一致必須 ---
D="$(fresh_corpus)"
yq -i '(.glossary[] | select(.term == "dual-audience") | .en) = "dual-audienceXQZ"' "$D/folio-glossary.glossary.yaml"
expect_fail "V3 en-drift(intersect): folio-glossary chrome dual-audience 改竄 → FAIL" "$D" "dual-audienceXQZ"
rm -rf "$D"

# --- V4 intersect の anchor 外 local 語は検査対象外 (批准済み緩和の honest 境界・誤検出しない) ---
D="$(fresh_corpus)"
yq -i '(.glossary[] | select(.term == "declarative") | .en) = "declarativeXQZ"' "$D/folio-constitution.principle.yaml"
expect_pass "V4 precision: constitution local 語 (SSoT anchor 不在) の変更は検査対象外 → exit 0" "$D"
rm -rf "$D"

# --- V5 未登録 contract の非空 glossary → default-block FAIL (完結性 sweep) ---
D="$(fresh_corpus)"
cat > "$D/zzz-new-suite.srs.yaml" <<'YAML'
doc_type: srs
meta:
  doc_id: SRS-ZZZ
glossary:
  - { term: 野良用語, en: stray term, plain_short: x, def: y }
YAML
expect_fail "V5 sweep: 非空 glossary の未登録 contract → FAIL" "$D" "unregistered-contract: 非空 glossary 節を持つ未登録 contract: zzz-new-suite.srs.yaml"
rm -rf "$D"

# --- V6 未登録でも glossary 空なら OK (害の発生点で捕捉する設計・未登録空 counter に載る) ---
D="$(fresh_corpus)"
printf 'doc_type: srs\nglossary: []\n' > "$D/zzz-empty.srs.yaml"
expect_pass "V6 sweep: 未登録 + glossary 空 → exit 0 (未登録空=1)" "$D" "未登録空=1"
rm -rf "$D"

# --- V7 SSoT anchor 崩壊: canonical 重複 (同語に en 2 通り) → FAIL ---
D="$(fresh_corpus)"
yq -i '.terms += [{"canonical": "診療枠", "en": "duplicated slotXQZ", "slug": "dup-slot", "domain": "clinic-domain", "formal_def": "dup"}]' "$D/clinic-appointment.glossary.yaml"
expect_fail "V7 ssot-dup: SSoT canonical 重複 → FAIL" "$D" "ssot-dup canonical='診療枠'"
rm -rf "$D"

# --- V8 registry rot: 登録済 contract の消失 → fail-loud ---
D="$(fresh_corpus)"
rm "$D/clinic-double-booking.research.yaml"
expect_fail "V8 registry-missing-file: 登録済 contract 消失 → FAIL" "$D" "registry-missing-file: 登録済 contract 不在: clinic-double-booking.research.yaml"
rm -rf "$D"

# --- V9 SSoT contract 自体の消失 → exit 2 (構成エラー・緑に化けない) ---
D="$(fresh_corpus)"
rm "$D/clinic-appointment.glossary.yaml"
"$GATE" --contract-dir "$D" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "V9 ssot-absent: SSoT 消失 → exit 2"
else bad "V9 ssot-absent: SSoT 消失が exit 2 でない (rc=$rc)"; fi
rm -rf "$D"

# --- V10 変形入力: glossary 節が配列でない → FAIL (silent skip させない) ---
D="$(fresh_corpus)"
yq -i '.glossary = "not an array"' "$D/clinic-double-booking.adr.yaml"
expect_fail "V10 malformed-glossary: 非配列 glossary → FAIL" "$D" "malformed-glossary: glossary 節が配列でない (string): clinic-double-booking.adr.yaml"
rm -rf "$D"

# --- V11 変形入力: SSoT 収録語の en 空 → FAIL (空値は一致でも不一致でもなく malformed) ---
D="$(fresh_corpus)"
yq -i '(.glossary[] | select(.term == "満枠") | .en) = ""' "$D/clinic-architecture.arch.yaml"
expect_fail "V11 malformed-entry: en 空 → FAIL" "$D" "malformed-entry: en 空 term='満枠'"
rm -rf "$D"

# --- V12 source 内 term 重複 → FAIL (en が同値でも一意性崩壊) ---
D="$(fresh_corpus)"
yq -i '.glossary += [{"term": "ダブルブッキング", "en": "double booking", "plain_short": "二重予約", "def": "dup"}]' "$D/clinic-appointment.srs.yaml"
expect_fail "V12 source-dup: source 内 term 重複 → FAIL" "$D" "source-dup term='ダブルブッキング'"
rm -rf "$D"

# --- V14 (ceiling wf_40306116 実弾の回帰 pin): intersect の SSoT 収録語 en に埋め込み改行 drift → FAIL ---
# 旧実装は改行で record が分割され present が欠落、drift が local へ silent 再分類され PASS していた
# (fail-open)。現実装は C0 制御文字の肯定形拒否 + NUL record framing の二段で閉塞。
D="$(fresh_corpus)"
MUT=$'dual-audienceXQZ\nsecondline' yq -i '(.glossary[] | select(.term == "dual-audience") | .en) = strenv(MUT)' "$D/folio-glossary.glossary.yaml"
expect_fail "V14 ctl-reject(intersect): SSoT 収録語 en の埋め込み改行 drift → FAIL" "$D" "malformed-entry: term/en に制御文字"
rm -rf "$D"

# --- V15 SSoT 側の埋め込み改行 (anchor 崩壊) → FAIL ---
D="$(fresh_corpus)"
MUT=$'fully bookedXQZ\ntail' yq -i '(.terms[] | select(.canonical == "満枠") | .en) = strenv(MUT)' "$D/clinic-appointment.glossary.yaml"
expect_fail "V15 ctl-reject(ssot): SSoT en の埋め込み改行 → FAIL" "$D" "ssot-malformed"
rm -rf "$D"

# --- V13 起動エラー: 未知引数 → exit 2 ---
"$GATE" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "V13 startup: 未知引数 → exit 2"
else bad "V13 startup: 未知引数が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  glossary-parity 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
