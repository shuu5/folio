#!/usr/bin/env bash
# folio engine (folio-c5r.1) — cross-doc 重複検出 lint の敵対回帰テスト。
#
# lint 自体の正しさを検査する: (a) recall = planted 字句重複 (constitution が SRS goal を restate) を検出する、
# (b) precision = 正当な共有 (original principle / glossary def コピー / declared echo / 別 suite boilerplate) を
# 誤検出しない、 (c) exit-code = --strict が undeclared HIGH で exit 1・clean で exit 0。
#
# ★lint は advisory (重複を見つけても build を fail させない=判断は人間) ゆえ、 検査は exit-code でなく
#   *出力 substring* で recall/precision を判定する (test-adversarial-graph.sh の expect_pass_warn と同型)。
# temp corpus を cp で作り contract を植え/改竄して lint を走らせる。 mutation の delimiter は s{}{} (日本語/# 衝突回避)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SCRIPT_DIR/verify-cross-doc-dup.sh"
SRC_CONTRACT="$SCRIPT_DIR/contract"
[[ -x "$LINT" ]] || { echo "FATAL: lint not executable: $LINT" >&2; exit 2; }

pass=0; total=0
ok()   { total=$((total+1)); pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad()  { total=$((total+1)); printf '  [FAIL] %s\n' "$1"; }

# 新しい temp corpus (clean contract コピー) を作り path を echo。
fresh_corpus() { local d; d="$(mktemp -d)"; cp "$SRC_CONTRACT"/*.yaml "$d"/; printf '%s' "$d"; }

# clinic 憲章 (principle pack・prefix=clinic・edge なし=terminal) を corpus に植える。 $2 = P-1 statement。
plant_clinic_constitution() {
  local dir="$1" p1stmt="$2"
  cat > "$dir/clinic-governance.principle.yaml" <<YAML
meta:
  doc_id: PRIN-CLINIC-GOV
  title: クリニック予約システム憲章
principles:
  - id: P-1
    heading: 二重予約の禁止
    statement: $p1stmt
  - id: P-2
    heading: 職員の最終権限
    statement: 自動処理が判断に迷うときは、 受付職員が最終的に予約の可否を決める権限を持つ。
versioning:
  note: この憲章の改訂は院長承認を要する。
amendment:
  steps:
    - 改訂案を院内会議に提出する。
YAML
}

GOAL1='同じ診療枠に 2 人を入れてしまい、 来院した患者を待たせたり断ったりしない。'

echo "== cross-doc 重複検出 lint 敵対回帰 =="

# --- baseline: clean corpus は undeclared 0 ---
out="$("$LINT" 2>&1)"; rc=$?
if grep -q 'undeclared 重複=0' <<<"$out" && [[ "$rc" -eq 0 ]]; then
  ok "baseline: clean corpus → undeclared 0 / exit 0"
else bad "baseline: clean corpus が undeclared 0 / exit 0 でない (前提崩壊)"; fi

# --- recall #1: 憲章が GOAL1 を verbatim restate → HIGH undeclared 検出 ---
D="$(fresh_corpus)"; plant_clinic_constitution "$D" "$GOAL1"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if grep -Eq '\[HIGH\].*SRS-CLINIC-APPT.*PRIN-CLINIC-GOV|\[HIGH\].*PRIN-CLINIC-GOV.*SRS-CLINIC-APPT' <<<"$out"; then
  ok "recall verbatim: 憲章 P-1 (GOAL1 直写し) を HIGH undeclared 検出"
else bad "recall verbatim: GOAL1 直写し restate が検出されない"; fi
rm -rf "$D"

# --- recall #2: 憲章が GOAL1 を reworded restate (語尾改変) → undeclared 検出 (J>=WARN_J) ---
D="$(fresh_corpus)"
plant_clinic_constitution "$D" '同じ診療枠に 2 人を入れてしまうことを防ぎ、 来院した患者を待たせたり断ったりしないようにする。'
out="$("$LINT" --contract-dir "$D" 2>&1)"
if grep -Eq '\[(HIGH|DUP)\].*(SRS-CLINIC-APPT.*PRIN-CLINIC-GOV|PRIN-CLINIC-GOV.*SRS-CLINIC-APPT)' <<<"$out"; then
  ok "recall reworded: 語尾改変 restate も undeclared 検出"
else bad "recall reworded: 語尾改変 restate が検出されない (J 閾値が厳しすぎ)"; fi
rm -rf "$D"

# --- precision #1: 憲章の original principle (P-2 職員権限) は誤検出しない ---
D="$(fresh_corpus)"; plant_clinic_constitution "$D" "$GOAL1"
out="$("$LINT" --contract-dir "$D" 2>&1)"
# WARN セクション (RESULT 行より上) に P-2 由来の語が現れないこと。 P-2 statement「最終的に予約の可否」が WARN に無い。
warnsec="$(sed -n '1,/^  ----/p' <<<"$out")"
if ! grep -q '最終的に予約の可否を決める' <<<"$warnsec"; then
  ok "precision original: original principle (P-2) は WARN に出ない"
else bad "precision original: original principle が誤検出された"; fi
rm -rf "$D"

# --- precision #2: declared echo (research AP ⇔ ADR OPT・J=1.0) は undeclared WARN に出ない ---
out="$("$LINT" 2>&1)"
warnsec="$(sed -n '1,/^  ----/p' <<<"$out")"
# clean corpus の declared echo (research↔adr) が undeclared WARN 行に現れない (declared バケット送り)。
if ! grep -Eq '\[(HIGH|DUP)\].*(RES-CLINIC-0001.*ADR-CLINIC|ADR-CLINIC.*RES-CLINIC-0001)' <<<"$warnsec"; then
  ok "precision declared: research↔ADR の高一致 echo は undeclared WARN に出ない (graph で説明済)"
else bad "precision declared: declared echo が undeclared 誤検出された"; fi
# declared echo 件数が >0 であること (Stage 2 が機能している証跡)。
if grep -Eq 'declared echo=[1-9][0-9]*' <<<"$out"; then
  ok "precision declared: declared echo が informational バケットに分類されている (>0)"
else bad "precision declared: declared echo が 0 (Stage 2 が機能していない疑い)"; fi

# --- precision #3: glossary def コピー (全 pack 同一テキスト) は field 除外で誤検出しない ---
# baseline で undeclared 0 = glossary 全一致が flag されていない (field 除外の実証)。 個別確認として
# glossary 由来の「同じ枠に 2 人以上を入れてしまう事故」が WARN に出ないこと。
warnsec="$(sed -n '1,/^  ----/p' <<<"$out")"
if ! grep -q '同じ枠に 2 人以上を入れてしまう事故' <<<"$warnsec"; then
  ok "precision glossary: glossary def コピー (全 pack 一致) は WARN に出ない (field 除外)"
else bad "precision glossary: glossary def が誤検出された"; fi

# --- precision #4: 別 suite (clinic vs ec) の boilerplate 共有は比較しない ---
# clean corpus に SRS-CLINIC constraints ⇔ SRS-EC constraints (J=0.519) が存在するが別 prefix ゆえ未比較。
if ! grep -Eq '\[(HIGH|DUP)\].*(SRS-CLINIC-APPT.*SRS-EC-CHECKOUT|SRS-EC-CHECKOUT.*SRS-CLINIC-APPT)' <<<"$out"; then
  ok "precision cross-suite: 別プロジェクト (clinic vs ec) の boilerplate は比較されない"
else bad "precision cross-suite: 別 suite ペアが誤検出された (suite グルーピング失効)"; fi

# --- exit-code #1: --strict + planted HIGH → exit 1 ---
D="$(fresh_corpus)"; plant_clinic_constitution "$D" "$GOAL1"
"$LINT" --contract-dir "$D" --strict >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 1 ]]; then ok "exit-code: --strict + undeclared HIGH → exit 1"
else bad "exit-code: --strict + HIGH が exit 1 でない (rc=$rc)"; fi
rm -rf "$D"

# --- exit-code #2: --strict + clean corpus → exit 0 ---
"$LINT" --strict >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 0 ]]; then ok "exit-code: --strict + clean → exit 0"
else bad "exit-code: --strict + clean が exit 0 でない (rc=$rc)"; fi

# --- exit-code #3: 既定 (advisory) + planted HIGH → exit 0 (判断しない) ---
D="$(fresh_corpus)"; plant_clinic_constitution "$D" "$GOAL1"
"$LINT" --contract-dir "$D" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 0 ]]; then ok "exit-code: 既定 advisory は HIGH でも exit 0 (verdict にしない)"
else bad "exit-code: 既定 advisory が exit 0 でない (rc=$rc)"; fi
rm -rf "$D"

# --- F10: CONTENT_LEAVES 未登録 pack を fail-loud WARN ---
D="$(fresh_corpus)"
cat > "$D/clinic-mystery.zzz.yaml" <<'YAML'
meta:
  doc_id: ZZZ-CLINIC-MYSTERY
  title: 未知 doc-type
YAML
out="$("$LINT" --contract-dir "$D" 2>&1)"
if grep -q 'CONTENT_LEAVES 未登録 pack' <<<"$out" && grep -q 'zzz' <<<"$out"; then
  ok "F10: 未登録 pack (zzz) を fail-loud WARN (silent false-negative 防止)"
else bad "F10: 未登録 pack が警告されない"; fi
rm -rf "$D"

# --- negative-recall (設計境界の invariant pin): 意味を保った *重度 reword* (J≈0) は意図的に見逃す ---
# ★これは limitation (README/header) を機械担保し、 将来 WARN_J を下げて docs が偽になる drift を防ぐ。
# 重度 reword の restate は noise 帯に沈み J 閾値では分離不能 = 本 lint の構造的天井 (人間 ceiling が backstop)。
D="$(fresh_corpus)"
plant_clinic_constitution "$D" '一つの診察時間帯に複数の患者を重ねて受け付けることを避け、 患者に待ち時間や来院後の断りが生じないようにする。'
out="$("$LINT" --contract-dir "$D" 2>&1)"
warnsec="$(sed -n '1,/^  ----/p' <<<"$out")"
if ! grep -Eq '\[(HIGH|DUP)\].*(SRS-CLINIC-APPT.*PRIN-CLINIC-GOV|PRIN-CLINIC-GOV.*SRS-CLINIC-APPT)' <<<"$warnsec"; then
  ok "negative-recall: 重度 reword (J≈0) の restate は *意図的に* 見逃す (limitation の invariant・人間 ceiling 領分)"
else bad "negative-recall: 重度 reword が検出された (閾値 drift か・docs limitation と不整合)"; fi
rm -rf "$D"

# --- coverage (#7): doc_id 欠落 contract は silent drop でなく fail-loud WARN ---
D="$(fresh_corpus)"
cat > "$D/clinic-broken.srs.yaml" <<'YAML'
meta:
  title: doc_id 欠落 (壊れた contract)
goals:
  - headline: x
    desc: 同じ診療枠に 2 人を入れてしまい、 来院した患者を待たせたり断ったりしない。
YAML
out="$("$LINT" --contract-dir "$D" 2>&1)"
if grep -q 'doc_id 欠落/不正 YAML でスキップ' <<<"$out" && grep -q 'clinic-broken.srs.yaml' <<<"$out"; then
  ok "coverage: doc_id 欠落 contract を fail-loud WARN (clean を全緑と誤読させない・「検査できた範囲が緑」担保)"
else bad "coverage: doc_id 欠落 contract が silent drop された (clean 誤読リスク)"; fi
rm -rf "$D"

# --- 起動エラー: 未知引数 → exit 2 ---
"$LINT" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "startup: 未知引数 → exit 2"
else bad "startup: 未知引数が exit 2 でない (rc=$rc)"; fi

echo "  ----"
printf '  cross-doc-dup 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
