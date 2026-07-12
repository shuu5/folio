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

# =========================================================================
# folio-nsa heuristic robustness 回帰 pin (① meta.suite / ③ 全角畳み込み / ④ field-aware / ② 内訳)
# 各機構は「新機構あり→期待挙動 / なし→旧挙動」の対で discriminator を成立させる (mutation-kill 同型)。
# =========================================================================
# WARN セクション (RESULT より上) に doc_id ペア (順不同) の HIGH/DUP があるか。
nsa_detected() { local w; w="$(sed -n '1,/^  ----/p' <<<"$1")"; grep -Eq "\[(HIGH|DUP)\].*($2.*$3|$3.*$2)" <<<"$w"; }
# 最小 SRS を書く: $1 dir $2 base $3 doc_id $4 suite(空=無) $5 field(goals|cond|constraint) $6 text
nsa_srs() {
  local dir="$1" fn="$2" did="$3" su="$4" fld="$5" tx="$6"
  { echo "meta:"; echo "  doc_id: $did"; echo "  title: \"SRS $did\"";
    [[ -n "$su" ]] && echo "  suite: \"$su\"";
    echo "goals:";
    if [[ "$fld" == goals ]]; then echo "  - headline: \"目標\""; echo "    desc: \"$tx\"";
    else echo "  - headline: \"見出し 無関係 AAA\""; echo "    desc: \"目標説明 無関係フィラー BBB。\""; fi
    echo "requirements:"; echo "  - id: FR-1"; echo "    ears:";
    if [[ "$fld" == cond ]]; then echo "      condition: \"$tx\"";
    else echo "      condition: \"システム起動時 無関係フィラー CCC。\""; fi
    echo "      response: \"受付画面を表示 無関係フィラー DDD。\"";
    echo "constraints:";
    if [[ "$fld" == constraint ]]; then echo "  - text: \"$tx\"";
    else echo "  - text: \"制約 無関係フィラー EEE。\""; fi
  } > "$dir/$fn.srs.yaml"
}
nsa_prin() { # $1 dir $2 base $3 doc_id $4 suite(空=無) $5 statement
  local dir="$1" fn="$2" did="$3" su="$4" st="$5"
  { echo "meta:"; echo "  doc_id: $did"; echo "  title: \"憲章 $did\"";
    [[ -n "$su" ]] && echo "  suite: \"$su\"";
    echo "principles:"; echo "  - id: P-1"; echo "    heading: \"禁止\""; echo "    statement: \"$st\"";
    echo "  - id: P-2"; echo "    heading: \"権限\""; echo "    statement: \"無関係の原則 FFF 独立文。\"";
  } > "$dir/$fn.principle.yaml"
}
NSA_DUP='同じ診療枠に 2 人の患者を重ねて受け付けてしまい、 来院した患者を待たせたり門前で断ったりする事故を決して起こさない。'
NSA_FWH='予約 API は毎分 100 回まで、 決済 API は毎分 30 回まで、 返金 API は毎分 10 回まで呼び出せる。 上限超過は HTTP 429 を返す。'
NSA_FWF='予約 ＡＰＩ は毎分 １００ 回まで、 決済 ＡＰＩ は毎分 ３０ 回まで、 返金 ＡＰＩ は毎分 １０ 回まで呼び出せる。 上限超過は ＨＴＴＰ ４２９ を返す。'
NSA_C1='受付が予約を確定しようとしたとき、 対象の診療枠がすでに埋まっている場合は、'
NSA_C2='受付が予約を確定しようとしたとき、 対象の診療枠が別の患者で埋まっているならば、'
# ④ recall 保存ペア (near-verbatim・J≈0.82 = [EARS_COND_J,1.0) 帯)。 引上げ後もなお検出=recall 非劣化。
NSA_RC1='受付が予約を確定しようとしたとき、 対象の診療枠がすでに別の患者で埋まっていて予約を受け付けられない場合は、 その旨を画面に表示して受付を中止する。'
NSA_RC2='受付が予約を確定しようとしたとき、 対象の診療枠がすでに別の患者で埋まっていて予約を受け付けられない場合には、 その旨を画面に表示し受付を中止する。'

# ① meta.suite FN(有): 命名差 (clinicgov vs clinic) を meta.suite で同一 suite 化 → 検出。
#   ★この FN(有) は下の FN(無) の liveness guard も兼ねる (同一 DUP・suite 揃えで検出=fixture live 証明・MUST-2)。
D="$(mktemp -d)"; nsa_srs "$D" "clinic-req" "SRS-CQ" "cg" goals "$NSA_DUP"; nsa_prin "$D" "clinicgov-c" "PRIN-CG" "cg" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if nsa_detected "$out" "SRS-CQ" "PRIN-CG"; then ok "① meta.suite FN(有)+liveness: 命名差を同一 suite 化し逐語重複を検出 (fixture live)"
else bad "① meta.suite FN(有): 検出されるべき逐語重複が出ない"; fi
rm -rf "$D"
# ① meta.suite FN(無): suite 無し + prefix 差 → 未比較 = 非検出 (上の FN(有) が同 DUP で検出ゆえ vacuous でない)。
D="$(mktemp -d)"; nsa_srs "$D" "clinic-req" "SRS-CQ" "" goals "$NSA_DUP"; nsa_prin "$D" "clinicgov-c" "PRIN-CG" "" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if ! nsa_detected "$out" "SRS-CQ" "PRIN-CG"; then ok "① meta.suite FN(無): prefix 差では未比較=非検出 (meta.suite が検出の因)"
else bad "① meta.suite FN(無): prefix 差なのに検出された"; fi
rm -rf "$D"
# ① meta.suite FP(liveness): 同 acme docs を suite 揃えると検出 (fixture live 証明・MUST-2 vacuous PASS 封鎖)。
D="$(mktemp -d)"; nsa_srs "$D" "acme-a" "SRS-PA" "same" goals "$NSA_DUP"; nsa_prin "$D" "acme-b" "PRIN-PB" "same" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if nsa_detected "$out" "SRS-PA" "PRIN-PB"; then ok "① meta.suite FP(liveness): 同 docs を suite 揃えると検出 (fixture live)"
else bad "① meta.suite FP(liveness): suite 揃えても検出されない (fixture 不発)"; fi
rm -rf "$D"
# ① meta.suite FP(差): org prefix 共有 (acme) でも suite 差で分離 → 非検出。
D="$(mktemp -d)"; nsa_srs "$D" "acme-a" "SRS-PA" "pa" goals "$NSA_DUP"; nsa_prin "$D" "acme-b" "PRIN-PB" "pb" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if ! nsa_detected "$out" "SRS-PA" "PRIN-PB"; then ok "① meta.suite FP(差): 同 prefix でも suite 差で別 project を分離し誤検出しない"
else bad "① meta.suite FP(差): 別 suite なのに誤検出"; fi
rm -rf "$D"
# ③ 全角→半角畳み込み: 全角 ASCII near-verbatim を検出 (fold 前 J<0.40=FN)。
D="$(mktemp -d)"; nsa_srs "$D" "fw-d" "SRS-FW" "fw" goals "$NSA_FWH"; nsa_prin "$D" "fw-n" "PRIN-FW" "fw" "$NSA_FWF"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if nsa_detected "$out" "SRS-FW" "PRIN-FW"; then ok "③ 全角畳み込み: 全角↔半角 near-verbatim を NFKC 畳み込みで検出 (FN 解消)"
else bad "③ 全角畳み込み: 全角↔半角 near-verbatim が検出されない"; fi
rm -rf "$D"
# ④ field-aware (treatment): ears.condition の mid-J (≈0.52) 定型句衝突は抑制 = 非検出。
D="$(mktemp -d)"; nsa_srs "$D" "t4-s" "SRS-T4" "t4" cond "$NSA_C1"; nsa_prin "$D" "t4-p" "PRIN-T4" "t4" "$NSA_C2"
out="$("$LINT" --contract-dir "$D" 2>&1)"
# 比較ペア候補>=1 を前置 (MUST-2: fixture 不発の vacuous PASS 封鎖 — 抑制と 0 比較を分離)。
if grep -Eq '比較ペア候補=[1-9]' <<<"$out"; then ok "④ ears(liveness): fixture が >=1 ペアを比較 (vacuous PASS 封鎖)"
else bad "④ ears(liveness): 比較ペア候補=0 (fixture 不発・非検出 assert が vacuous)"; fi
if ! nsa_detected "$out" "SRS-T4" "PRIN-T4"; then ok "④ field-aware(ears): EARS condition mid-J 定型句衝突を閾値引上げで抑制"
else bad "④ field-aware(ears): ears.condition mid-J が抑制されず検出"; fi
rm -rf "$D"
# ④ field-aware (control): 同一 mid-J を非 ears field に置くと通常閾値で検出 (field-aware が load-bearing)。
D="$(mktemp -d)"; nsa_srs "$D" "t4-s" "SRS-T4" "t4" constraint "$NSA_C1"; nsa_prin "$D" "t4-p" "PRIN-T4" "t4" "$NSA_C2"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if nsa_detected "$out" "SRS-T4" "PRIN-T4"; then ok "④ field-aware(非ears): 同一 mid-J を非 ears field に置くと通常閾値で検出"
else bad "④ field-aware(非ears): 非 ears field の mid-J が検出されない"; fi
rm -rf "$D"
# ④ field-aware (recall): near-verbatim (J>=0.65) を ears.condition に置くと引上げ後もなお検出 = recall 非劣化。
D="$(mktemp -d)"; nsa_srs "$D" "rc-s" "SRS-RC" "rc" cond "$NSA_RC1"; nsa_prin "$D" "rc-p" "PRIN-RC" "rc" "$NSA_RC2"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if nsa_detected "$out" "SRS-RC" "PRIN-RC"; then ok "④ field-aware(recall): near-verbatim ears.condition 重複は引上げ後もなお検出 (EARS_COND_J>=1.0 mutation を kill)"
else bad "④ field-aware(recall): near-verbatim ears.condition 重複が検出されない (recall 劣化)"; fi
rm -rf "$D"
# ④ field-aware (max セマンティクス): --warn-j 0.90 --high-j 0.95 override 時、 ears ペア (J≈0.82) は
#   eff_warn=max(0.90,0.65)=0.90 かつ is_high=0 (0.82<0.95) ゆえ非検出。 置換実装 (eff_warn=0.65 固定) なら WARN 帯で
#   誤検出する = ears だけ敏感化する intent 反転を kill する discriminator (--high-j 0.95 で独立 HIGH の surface を除外)。
D="$(mktemp -d)"; nsa_srs "$D" "mx-s" "SRS-MX" "mx" cond "$NSA_RC1"; nsa_prin "$D" "mx-p" "PRIN-MX" "mx" "$NSA_RC2"
# 比較ペア候補>=1 を前置 (MUST-2: fixture 不発の vacuous PASS 封鎖 — 抑制と 0 比較を分離)。
out="$("$LINT" --contract-dir "$D" --warn-j 0.90 --high-j 0.95 2>&1)"
if grep -Eq '比較ペア候補=[1-9]' <<<"$out"; then ok "④ max(liveness): fixture が >=1 ペアを比較 (vacuous PASS 封鎖)"
else bad "④ max(liveness): 比較ペア候補=0 (fixture 不発・以降の非検出 assert は vacuous)"; fi
if ! nsa_detected "$out" "SRS-MX" "PRIN-MX"; then ok "④ field-aware(max): --warn-j 0.90/--high-j 0.95 で ears 閾値も >=0.90 を保つ (置換実装の intent 反転を kill)"
else bad "④ field-aware(max): --warn-j 0.90 なのに ears ペアが 0.65 固定で誤検出 (max セマンティクス失効)"; fi
rm -rf "$D"
# ★MUST-1 (fail-open pin): field-aware 緩和が strict gate を弱めない — undeclared ears (J≈0.52) を
#   --strict --high-j 0.50 で回すと HIGH 独立計上により exit=1 (HIGH を eff_warn に nest する実装なら 0.52<0.65 に
#   gate され exit=0 転落 = fail-open)。 この assert は独立化を外す mutation で FAIL 転落する discriminator。
D="$(mktemp -d)"; nsa_srs "$D" "h1-s" "SRS-H1" "h1" cond "$NSA_C1"; nsa_prin "$D" "h1-p" "PRIN-H1" "h1" "$NSA_C2"
"$LINT" --contract-dir "$D" --strict --high-j 0.50 >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 1 ]]; then ok "④ MUST-1(fail-open): undeclared ears HIGH は field-aware 緩和と独立に --strict exit=1 (HIGH 独立化)"
else bad "④ MUST-1(fail-open): ears HIGH が eff_warn に gate され exit=$rc に転落 (fail-open・HIGH 独立化が失効)"; fi
rm -rf "$D"
# ★SHOULD-1 (partial-tag footgun): 同 filename prefix で tagged/untagged 混在 → fail-loud WARN。
D="$(mktemp -d)"; nsa_srs "$D" "clinic-a" "SRS-PT1" "clinicgrp" goals "$NSA_DUP"; nsa_prin "$D" "clinic-b" "PRIN-PT2" "" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if grep -q 'partial meta.suite tagging' <<<"$out" && grep -q 'prefix=clinic' <<<"$out"; then ok "SHOULD-1: 同 prefix で tagged/untagged 混在を fail-loud WARN (意図せぬ suite 分割の footgun)"
else bad "SHOULD-1: partial-tag が WARN されない"; fi
rm -rf "$D"
# SHOULD-1(対照): 全 explicit で値のみ異なる (意図的分離) は WARN しない (FP fix 正用途の false-positive 封鎖)。
D="$(mktemp -d)"; nsa_srs "$D" "acme-a" "SRS-PT3" "pa" goals "$NSA_DUP"; nsa_prin "$D" "acme-b" "PRIN-PT4" "pb" "$NSA_DUP"
out="$("$LINT" --contract-dir "$D" 2>&1)"
if ! grep -q 'partial meta.suite tagging' <<<"$out"; then ok "SHOULD-1(対照): 全 explicit の意図的分離は partial-tag WARN しない (FP fix 正用途)"
else bad "SHOULD-1(対照): 意図的分離が誤って partial-tag WARN された"; fi
rm -rf "$D"
# ② declared 内訳 breakdown: summary が J band 内訳を提示する (実 corpus)。
out="$("$LINT" 2>&1)"
if grep -Eq 'declared echo=[0-9]+ \[J=1\.0:[0-9]+ / HIGH:[0-9]+ / WARN帯:[0-9]+ / 弱:[0-9]+\]' <<<"$out"; then
  ok "② 内訳: declared echo が J band 内訳で提示される (J=1.0 と弱一致を畳まない)"
else bad "② 内訳: declared echo の J band 内訳が出ていない"; fi
# ② --show-declared J 降順: echo の J= 列が単調非増加。
jseq="$("$LINT" --show-declared 2>&1 | sed -n '/declared echoes/,/^  ----/p' | grep -oE 'J=[0-9]+\.[0-9]+' | sed 's/J=//')"
if [[ -n "$jseq" ]] && LC_ALL=C sort -c -rn <<<"$jseq" 2>/dev/null; then
  ok "② J降順: --show-declared の echo が J 降順"
else bad "② J降順: --show-declared の echo が J 降順でない"; fi

# ★MUST-3 (case 総数 pin): case 脱落の silent 化を封鎖 (旧 copy が 15/15 で緑を返した実証あり)。
#   本 assert 自身の直前までの total を期待値と照合する (増減時は脱落調査 or 期待値更新)。
EXPECT_TOTAL_BEFORE_PIN=31
if [[ "$total" -eq "$EXPECT_TOTAL_BEFORE_PIN" ]]; then ok "MUST-3: 実行 case 総数 == 期待値 $EXPECT_TOTAL_BEFORE_PIN (case 脱落の silent 化を封鎖)"
else bad "MUST-3: case 総数 $total != 期待 $EXPECT_TOTAL_BEFORE_PIN (case が増減・脱落調査 or 期待値更新)"; fi

echo "  ----"
printf '  cross-doc-dup 敵対: %d/%d PASS\n' "$pass" "$total"
[[ "$pass" -eq "$total" ]] || { echo "  RESULT: FAIL"; exit 1; }
echo "  RESULT: PASS"
exit 0
