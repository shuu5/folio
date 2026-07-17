#!/usr/bin/env bash
# folio engine (folio-og3g) — spec-pack 要件層 recapture parity gate の敵対回帰テスト。
#
# gate 自体の正しさを検査する: (a) recall = recapture 追随漏れ (原本にあるのに contract に無い)・
# contract 捏造 (原本 anchor 不在)・分類漏れ・selector rot を FAIL に落とす、 (b) precision = clean corpus を
# 誤検出しない、 (c) exit-code 規約 (0/1/2)。 FAIL 系 pin は FAIL 行にしか出ない値 (id 名指し等・c5r.2 基準)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-recapture-parity.sh"
SRC_CONTRACT="$SCRIPT_DIR/contract"
SRC_SPEC="$(cd "$SCRIPT_DIR/../../.." && pwd)/design-intent/spec"
[[ -x "$GATE" ]] || { echo "FATAL: gate not executable: $GATE" >&2; exit 2; }
command -v yq >/dev/null || { echo "FATAL: yq required" >&2; exit 2; }

pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad() { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

# temp corpus: contract dir と spec dir を対で作る (gate は両方を照合するため)
fresh() { # $1=変数名 prefix。 CD_<p>/SD_<p> に path を格納
  local d1 d2; d1="$(mktemp -d)"; d2="$(mktemp -d)"
  cp "$SRC_CONTRACT"/*.yaml "$d1"/
  cp "$SRC_SPEC"/rules.html "$SRC_SPEC"/verification.html "$SRC_SPEC"/relations.html "$d2"/
  CD="$d1"; SD="$d2"
}
run_gate() { "$GATE" --contract-dir "$CD" --spec-dir "$SD" 2>&1; }
expect_fail() { # $1=label $2=substring
  local out rc; out="$(run_gate)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -F -- "$2" <<<"$out" | grep -q '\[FAIL\]'; then ok "$1"
  else bad "$1 (rc=$rc / substring '$2' の FAIL 行なし)"; fi
}

echo "== recapture parity gate 敵対回帰 =="

# --- R0 baseline: clean corpus → exit 0 + 照合数 pin ---
# ★意図的 count pin (vacuous-green 防止): 原本/contract の要件増減・spec contract 追加で dirty。
#   lineage: 2026-07-05 (folio-og3g 初版) = 3 contract / 66 id (relations 4 + rules 26 + verification 36
#   〔REQ-VER 29 + REQ-NAV 7・og3g recapture 追随後〕)。 更新時は gate 実出力から転記し、 件数を
#   原本 anchor grep と contract yq で独立再導出して確認すること。
#   lineage: 2026-07-06 (folio-mzn.3 Phase A) = 3 contract / 65 id (relations 4 + rules 26 + verification 35
#   〔REQ-VER 28 + REQ-NAV 7・REQ-VER-027/028 退役 + REQ-VER-030 構成同一性 新設〕。 独立再導出: 原本 anchor 35 == contract yq 35)。
#   lineage: 2026-07-15 (folio-6lsu verification 再抽出・07m 分割追随) = 3 contract / 60 id (relations 4 + rules 26 + verification 30
#   〔REQ-VER 23 + REQ-NAV 7〕)。 folio-07m (7b47574) の spec 分割で REQ-VER-024/025/026/029/030 が原本 verification.html →
#   srs-verification.html へ移動したことへの contract 追随ゆえの *縮小* (35→30)。 独立再導出: 原本 anchor grep
#   (verification.html の details.spec-row) 30 == contract yq (.requirements[].id) 30。
#   lineage: 2026-07-17 (folio-lwhz flip・admin fixup) = 3 contract / 60 id 不変。★flip 後の verification.html は
#   div.ears-requirement-row shape の生成物 — 独立再導出は shape union grep で行う (verification =
#   div.ears-requirement-row id 30 / rules 26 + relations 4 = details.spec-row)。details 前提の旧手順は
#   verification に対して 0 件を返すので使わない (F6 union 拡張と同じ per-file shape 対応)。
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q '照合: contract 3 本 / id 60 件' <<<"$out"; then
  ok "R0 baseline: clean corpus → exit 0 + 3 contract / 60 id pin"
else bad "R0 baseline: 期待 pin と不一致 (rc=$rc・corpus 成長なら lineage 手順で pin 更新)"; fi

# --- R1 recapture 追随漏れ: contract から record を 1 本落とす → missing-in-contract ---
# ★mut 対象は原本 verification.html に anchor が *実在* する id でなければ del が no-op になり mut が効かない
#   (folio-6lsu: 旧 mut 対象 REQ-VER-029 は 07m 分割で srs-verification.html へ移動済ゆえ no-op 化 = 張り替え。
#    no-op は gate を PASS させ expect_fail が FAIL するため本 suite は fail-closed で検知した = SLIP 教訓の実証)。
fresh
yq -i 'del(.requirements[] | select(.id == "REQ-VER-023"))' "$CD/folio-verification.spec.yaml"
expect_fail "R1 追随漏れ: contract から REQ-VER-023 削除 → FAIL" "missing-in-contract: 原本 record 'REQ-VER-023'"
rm -rf "$CD" "$SD"

# --- R2 contract 捏造: 原本に無い record を contract へ注入 → missing-in-genbun ---
fresh
yq -i '.requirements += [{"id": "REQ-VER-099", "ears_pattern": "ubiquitous", "essence": "x", "statement": "y"}]' "$CD/folio-verification.spec.yaml"
expect_fail "R2 捏造: 原本 anchor 不在の REQ-VER-099 注入 → FAIL" "missing-in-genbun: contract record 'REQ-VER-099'"
rm -rf "$CD" "$SD"

# --- R3 分類漏れ: 未登録の *.spec.yaml → default-block FAIL ---
fresh
printf 'doc_type: spec\nrequirements:\n  - { id: "REQ-ZZZ-001", ears_pattern: "ubiquitous", essence: "x", statement: "y" }\n' > "$CD/zzz-new.spec.yaml"
expect_fail "R3 sweep: 未登録 spec contract → FAIL" "unregistered-contract: 未登録の spec contract: zzz-new.spec.yaml"
rm -rf "$CD" "$SD"

# --- R4 registry rot: 登録済 contract の消失 → fail-loud ---
fresh
rm "$CD/folio-relations.spec.yaml"
expect_fail "R4 registry-missing-file: 登録済 contract 消失 → FAIL" "registry-missing-file: 登録済 spec contract 不在: folio-relations.spec.yaml"
rm -rf "$CD" "$SD"

# --- R5 原本消失 → fail-loud (照合不能を素通さない) ---
fresh
rm "$SD/relations.html"
expect_fail "R5 genbun-missing: 原本消失 → FAIL" "genbun-missing: 原本 spec 不在: relations.html"
rm -rf "$CD" "$SD"

# --- R6 contract 内 id 重複 → 集合照合の一意性崩壊で FAIL ---
fresh
yq -i '.requirements += [{"id": "REQ-REL-001", "ears_pattern": "ubiquitous", "essence": "x", "statement": "y"}]' "$CD/folio-relations.spec.yaml"
expect_fail "R6 dup-id: contract 内 id 重複 → FAIL" "dup-id: contract 内 id 重複 'REQ-REL-001'"
rm -rf "$CD" "$SD"

# --- R6b 原本側 anchor 重複 → dup-anchor FAIL (ceiling wf_17b5181e blocking の処方・dup-id の双子) ---
# 原本に同一 id の spec-row anchor が 2 本あると sort -u の集合照合では畳まれて素通る — dup-anchor guard
# だけが原本側 silent corruption を捕捉するため、その分岐に red pin を張る。
fresh
printf '<details class="spec-row" id="req-rel-001"></details>\n' >> "$SD/relations.html"
expect_fail "R6b dup-anchor: 原本 anchor 重複 → FAIL" "dup-anchor: 原本 anchor 重複 'REQ-REL-001'"
rm -rf "$CD" "$SD"

# --- R7 selector rot (details.spec-row shape): 原本の spec-row class を潰す → zero-anchors (vacuous green 拒否) ---
fresh
perl -i -pe 's/class="spec-row"/class="spec-row-rotted"/g' "$SD/relations.html"
expect_fail "R7 zero-anchors: 原本 anchor 全滅 → FAIL (vacuous green 拒否)" "zero-anchors: 原本に要件 anchor が 0 本 (relations.html)"
rm -rf "$CD" "$SD"

# --- R7b selector rot (ears-requirement-row shape): 生成物 verification.html の data-component を潰す → zero-anchors ---
# ★per-shape MK (folio-lwhz F6): R7 は details.spec-row shape (relations 手書き原本) の全滅を pin する。
#   F6 で union 追加した shape 2 (div.ears-requirement-row = verification flip 生成物) の抽出が rot したとき
#   verification が全滅することは、shape 2 を直接潰す別 mutant で撃たないと証明できない (1 shape の実弾は
#   構造差のある shape の穴を証明しない・per-shape 原則)。data-component token を rot させ 30→0 を確認。
fresh
perl -i -pe 's/data-component="ears-requirement-row"/data-component="ears-requirement-row-rotted"/g' "$SD/verification.html"
expect_fail "R7b zero-anchors (ears-requirement-row shape): 生成物 verification anchor 全滅 → FAIL" "zero-anchors: 原本に要件 anchor が 0 本 (verification.html)"
rm -rf "$CD" "$SD"

# --- R8 malformed: requirements 節が配列でない → FAIL ---
fresh
yq -i '.requirements = "broken"' "$CD/folio-relations.spec.yaml"
expect_fail "R8 malformed-requirements: 非配列 requirements → FAIL" "malformed-requirements: requirements 節が配列でない (string): folio-relations.spec.yaml"
rm -rf "$CD" "$SD"

# --- R8b 変形入力: YAML 構文破壊 → yaml-parse-error FAIL (silent skip させない) ---
fresh
printf '{{{invalid yaml\n' > "$CD/folio-relations.spec.yaml"
expect_fail "R8b yaml-parse-error: 構文破壊 contract → FAIL" "yaml-parse-error: folio-relations.spec.yaml"
rm -rf "$CD" "$SD"

# --- R8c 変形入力: requirements に非 object 要素 (id 抽出不能) → FAIL ---
fresh
yq -i '.requirements += ["stray-string"]' "$CD/folio-relations.spec.yaml"
expect_fail "R8c malformed-requirements: 非 object record → FAIL" "malformed-requirements: id 空 or 非 object record in folio-relations.spec.yaml"
rm -rf "$CD" "$SD"

# --- R9 起動エラー: 未知引数 → exit 2 ---
"$GATE" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "R9 startup: 未知引数 → exit 2"
else bad "R9 startup: 未知引数が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  recapture-parity 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
