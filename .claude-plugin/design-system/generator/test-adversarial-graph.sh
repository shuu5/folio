#!/usr/bin/env bash
# folio engine B5-I (folio-p4o) — 照会 graph 終端完備検証 (verify-graph.sh) 敵対回帰テスト
#
# verify-graph.sh の fail-closed gate が以下を捕捉することを回帰確認する:
#   - rolemap floor pin (edge.role == rolemap[node.type]) を *どちら側の改竄でも* (二重担保) FAIL
#   - SRS の exploration 不在 (forbidden_roles) を corpus scan で実証し密輸を FAIL
#   - dangling 照会 (graph 不在 node 先) / rolemap roles allowlist 逸脱 / rolemap 不在 / doc_id 欠落・重複 を FAIL
#   - 孤立 = block (folio-ulz 批准 2026-07-03): 未宣言の孤立 (principle 終端へ到達不能・免除宣言なし) は hard FAIL。
#     免除宣言 (meta.terminal_waiver・rationale 必須) 済みは warn 降格 + 可視一覧。 stale 宣言 (終端到達済み) は warn。
#   - external-ref (folio-self inbound/amended_by) は warn = exit 0
# SRS/ADR/research/principle の test-adversarial-*.sh と同型 (敵対の検出力を固定 = ceiling 機械化下限)。
# ★FAIL 系は理由 substring を検証し「想定 gate 以外の巻き添え FAIL」での false-pass を弾く。
#
# usage: test-adversarial-graph.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VG="$SCRIPT_DIR/verify-graph.sh"
command -v yq >/dev/null || { echo "FATAL: yq required"; exit 2; }
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
pass=0; fail=0
ok() { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
ng() { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

# mktmp: contract/ + rolemap/ を新規 temp へ複製し dir パスを返す (lib は実 generator から source)。
n=0
mktmp() { n=$((n+1)); local d="$TMPROOT/c$n"; mkdir -p "$d"; cp -r "$SCRIPT_DIR/contract" "$d/"; cp -r "$SCRIPT_DIR/rolemap" "$d/"; printf '%s' "$d"; }
RUNOUT=""
run() { local d="$1"; shift; RUNOUT="$(bash "$VG" --contract-dir "$d/contract" --rolemap-dir "$d/rolemap" "$@" 2>&1)"; return $?; }
# expect_fail <label> <dir> <reason-substr> [vg-args...]
expect_fail() { local label="$1" d="$2" reason="$3"; shift 3
  if run "$d" "$@"; then ng "$label (FAIL せず exit 0)"; return; fi
  if [[ -n "$reason" && "$RUNOUT" != *"$reason"* ]]; then ng "$label (FAIL したが理由が想定外。 期待 '$reason')"; return; fi
  ok "$label"; }
# expect_pass_warn <label> <dir> <warn-substr>
expect_pass_warn() { local label="$1" d="$2" w="$3"; shift 3
  if ! run "$d" "$@"; then ng "$label (warn のはずが FAIL/exit!=0)"; return; fi
  if [[ -n "$w" && "$RUNOUT" != *"$w"* ]]; then ng "$label (exit 0 だが warn '$w' 不在)"; return; fi
  ok "$label"; }

echo "照会 graph adversarial regression (fail-closed / warn-correct expected):"

# H0. happy path: exit 0 / 終端完備=17 / FLOOR-OK
#   corpus 実値の来歴: B6 (folio-8ct) spec-pack で 4→5、 glossary×2 + testcases + arch + relations/verification spec で
#   5→10 (folio-dls の drift を本 cell で吸収)、 c5r.11 裁定 B2 (test→SRS forward 再写像) で TC-CLINIC-APPT が
#   終端完備化し 10→11・孤立 2→1 (残 = ADR-less な SRS-EC-CHECKOUT のみ)、 c5r.4 (vision-pack) で
#   VISION-CLINIC-APPT が inline principle PRIN-PATIENT-TRUST で終端完備化し 11→12 (vision→SRS backward が SRS へ
#   独立終端路も供給する = W1 参照)。 folio-ulz 批准 (block+免除宣言) で EC は meta.terminal_waiver 宣言済み →
#   免除(warn)=1・孤立(block)=0 が happy path の実値。 folio-qvv (folio-self vision) で VISION-FOLIO が
#   inline principle PRIN-READER-FLOOR により終端完備化し 12→13 (cross_doc 非発火 = 照会 edge なしの初例)。
#   folio-1q8o (data-model-pack) で DM-CLINIC-APPT が自前 inline principle PRIN-DATA-MINIMUM で終端完備化し 13→14
#   (arch/vision と同型の toward-terminal・DM→SRS backward は SRS へ 4 つ目の独立終端路も供給する = W1 参照)。
#   folio-ehar (interface-pack) で IF-CLINIC-APPT が自前 inline principle PRIN-HONEST-BOUNDARY で終端完備化し 14→15
#   (datamodel と同型の toward-terminal・IF→SRS backward は SRS へ 5 つ目の独立終端路も供給する = W1 参照)。
#   folio-wdv0 (risk-register-pack) で RISK-CLINIC-APPT が RISK→SRS backward + toward-terminal で終端完備化し 15→16。
#   folio-8ptq (changelog-pack) で CHANGELOG-CLINIC-APPT が CHANGELOG→{ADR,SRS} backward + toward-terminal で終端完備化し 16→17。
#   folio-8cha (roadmap-pack) で ROADMAP-CLINIC-APPT が ROADMAP→{VISION,SRS} forward (toward-terminal) で VISION 経由 principle 終端到達し 17→18 (自前 principle 終端は持たない = c5r.11・changelog/testcases と同型)。
#   ★「終端到達: TC-CLINIC-APPT」substring は B2 の意味 pin (backward への退行は count と substring の両方で割れる)。
#   ★「免除: SRS-EC-CHECKOUT」substring は免除宣言の可視一覧 pin (silent 化の退行を検出)。
#   ★「非発火 (照会 0 件 + 照会先なし = opt-in cross_doc)」substring は qvv 裁定A の可視 pin (silent skip 化の退行を検出)。
D="$(mktmp)"
if run "$D" && [[ "$RUNOUT" == *"終端完備=18 免除(warn)=1 孤立(block)=0"* && "$RUNOUT" == *"終端到達: TC-CLINIC-APPT"* \
   && "$RUNOUT" == *"終端到達: VISION-FOLIO"* && "$RUNOUT" == *"終端到達: DM-CLINIC-APPT"* && "$RUNOUT" == *"終端到達: IF-CLINIC-APPT"* && "$RUNOUT" == *"終端到達: RISK-CLINIC-APPT"* && "$RUNOUT" == *"終端到達: CHANGELOG-CLINIC-APPT"* && "$RUNOUT" == *"終端到達: ROADMAP-CLINIC-APPT"* && "$RUNOUT" == *"非発火 (照会 0 件 + 照会先なし = opt-in cross_doc)"* \
   && "$RUNOUT" == *"免除: SRS-EC-CHECKOUT"* && "$RUNOUT" == *"RESULT: FLOOR-OK"* ]]; then
  ok "H0 happy path (終端完備=18 / 免除=1 / 孤立=0 / TC+VISION-FOLIO+DM+IF+RISK+CHANGELOG+ROADMAP 終端到達 / 非発火可視 / EC 免除可視 / FLOOR-OK / exit 0)"
else ng "H0 happy path 不一致 (rc=$? / 末尾: $(printf '%s' "$RUNOUT" | tail -2 | tr '\n' '|'))"; fi

# G1. contract 改竄: ADR justifies role を別 allowlist role へ swap → pin FAIL
D="$(mktmp)"; yq -i '.decision.justifies[0].role = "verification"' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G1 ★contract role swap (claim→verification) を pin で FAIL" "$D" "rolemap[decision]=claim (pin)"

# G2. rolemap 改竄: roles[decision] を改竄 → 二重担保で pin FAIL (corpus は claim のまま)
D="$(mktmp)"; yq -i '.roles.decision = "rationale"' "$D/rolemap/adr.rolemap.yaml"
expect_fail "G2 ★rolemap roles[decision] 改竄を二重担保で FAIL" "$D" "(pin)"

# G3. research 改竄: approaches role swap → pin FAIL (pack 横断で同型に効く)
D="$(mktmp)"; yq -i '.approaches[1].role = "claim"' "$D/contract/clinic-double-booking.research.yaml"
expect_fail "G3 ★research approach role swap を pin で FAIL" "$D" "rolemap[approaches]=exploration (pin)"

# G4. forbidden_roles scan: SRS へ exploration node 密輸 → FAIL
D="$(mktmp)"; yq -i '.approaches = [{"id":"AP1","leads_to":"X","role":"exploration"}]' "$D/contract/ec-checkout.srs.yaml"
expect_fail "G4 ★SRS へ exploration 密輸を scan で FAIL" "$D" "forbidden role 'exploration' 不在 (scan 実証)"

# G5. dangling: ADR の照会先 doc_id を不在へ → FAIL
D="$(mktmp)"; yq -i '.cross_doc.srs_doc_id = "SRS-NONEXISTENT"' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G5 ★dangling 照会先 (graph 不在 doc) を FAIL" "$D" "dangling 照会"

# G6. rolemap roles allowlist 逸脱: 未知 role を rolemap へ → FAIL
D="$(mktmp)"; yq -i '.roles.decision = "bogusrole"' "$D/rolemap/adr.rolemap.yaml"
expect_fail "G6 ★rolemap roles 未知値を allowlist sanity で FAIL" "$D" "rolemap roles ⊆ 抽象 allowlist"

# G7. rolemap 不在 → fail-closed FAIL
D="$(mktmp)"; rm -f "$D/rolemap/adr.rolemap.yaml"
expect_fail "G7 ★rolemap 不在を fail-closed で FAIL" "$D" "rolemap 不在"

# G8. doc_id 欠落 → FAIL
D="$(mktmp)"; yq -i 'del(.meta.doc_id)' "$D/contract/ec-checkout.srs.yaml"
expect_fail "G8 ★doc_id 欠落を FAIL" "$D" ".meta.doc_id 欠落"

# G9. doc_id 重複 → FAIL (EC を clinic と同 doc_id に)
D="$(mktmp)"; yq -i '.meta.doc_id = "SRS-CLINIC-APPT"' "$D/contract/ec-checkout.srs.yaml"
expect_fail "G9 ★doc_id 重複を FAIL" "$D" "doc_id 重複"

# G10. 空 role: justifies role を 1 件空に → 件数は一致 (2==2) するが pin (空 != claim) で FAIL
D="$(mktmp)"; yq -i '.decision.justifies[0].role = ""' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G10 ★空 role を pin で FAIL" "$D" "(pin)"

# G14. ★role/count expr 協調 vacuum (minor#3 = 武装解除の兄弟): rolemap の role_expr/count_expr を
#      *両方* 存在しない path へ書き換えると declared_cnt=0/|eroles|=0 で件数一致し pin が 0 回照合になる。
#      照会先 doc_id は別 expr で有効に残るゆえ「有効照会先 ⟹ 非vacuum」ガードが捕捉する。 corpus role も swap して
#      「vacuum で corpus 改竄を隠す複合攻撃」を再現する (G11 の edges 削除と同クラス・別ベクタ)。
D="$(mktmp)"
yq -i '.edges[0].role_expr = ".nope[].role"' "$D/rolemap/adr.rolemap.yaml"
yq -i '.edges[0].count_expr = ".nope | length"' "$D/rolemap/adr.rolemap.yaml"
yq -i '.decision.justifies[0].role = "verification"' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G14 ★role/count expr 協調 vacuum で corpus swap 隠蔽を FAIL" "$D" "非vacuum (declared_cnt 正整数)"

# G15. ★forbidden_roles の rolemap宣言側 (a) (minor#1): srs.rolemap の roles に exploration を宣言 →
#      (a)側 pin (rolemap に forbidden role 不在) で FAIL。 G4 は corpus側 (b) を突くので「二重担保」両面を固定する。
D="$(mktmp)"; yq -i '.roles.requirements = "exploration"' "$D/rolemap/srs.rolemap.yaml"
expect_fail "G15 ★rolemap roles に forbidden exploration 宣言を (a)側 pin で FAIL" "$D" "rolemap に forbidden role 'exploration' 不在"

# G16. ★opt-in cross_doc の片肺 (folio-qvv 裁定A の FAIL 側 pin): 非発火 contract (folio-vision) に照会だけ
#      復活させる (cross_doc なしで refs.srs 1 件) → 「宙に浮いた照会」を graph 層でも FAIL (assemble 層の
#      fail-closed と二重担保。 非発火許容の緩和が片肺まで素通しにしない事を敵対固定)。
D="$(mktmp)"; yq -i '.features[0].refs.srs = ["FR-GHOST"]' "$D/contract/folio-vision.vision.yaml"
expect_fail "G16 ★片肺 contract (照会あり照会先なし) を graph 層で FAIL" "$D" "照会先 doc_id が空"

# G17. ★opt-in scope-leak の pin (ceiling round-1 major の敵対固定): vision 用の非発火許容が ADR へ漏れないこと。
#      ADR を完全非発火化 (justifies 全喪失 + cross_doc 削除) → opt-in 非対象 pack ゆえ graph 層で FAIL。
D="$(mktmp)"; yq -i '.decision.justifies = [] | del(.cross_doc)' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G17 ★ADR 完全非発火化 (opt-in 非対象) を graph 層で FAIL" "$D" "照会先 doc_id が空"

# G18. ★同 scope-leak の arch 面 (decisions の refs 全喪失 + cross_doc 削除・ADR と同 code path だが
#      edge 2 本 (srs/adr) を持つ pack でも allowlist gate が効くことを固定)。
D="$(mktmp)"; yq -i '(.decisions[].refs.srs) = [] | (.decisions[].refs.adr) = [] | del(.cross_doc)' "$D/contract/clinic-architecture.arch.yaml"
expect_fail "G18 ★arch 完全非発火化 (opt-in 非対象) を graph 層で FAIL" "$D" "照会先 doc_id が空"

# G11. ★edges 武装解除: ADR rolemap の edges を削除 → pin が無検査になる構造的 floor 解除を FAIL
D="$(mktmp)"; yq -i 'del(.edges)' "$D/rolemap/adr.rolemap.yaml"
expect_fail "G11 ★ADR rolemap.edges 削除 (floor 武装解除) を FAIL" "$D" "floor 武装解除ガード"

# G12. ★edges 武装解除: research rolemap の edges を空配列に → FAIL (pack 横断で同型に効く)
D="$(mktmp)"; yq -i '.edges = []' "$D/rolemap/research.rolemap.yaml"
expect_fail "G12 ★research rolemap.edges 空 (floor 武装解除) を FAIL" "$D" "floor 武装解除ガード"

# G13. ★二重担保の穴 (本 finding): ADR edges 削除 + corpus role 改竄 を同時に → smuggling を FAIL
#     (G1 の corpus 改竄を G11 の edges 削除で隠蔽する複合攻撃。 武装解除ガードが先に FAIL させる)
D="$(mktmp)"; yq -i 'del(.edges)' "$D/rolemap/adr.rolemap.yaml"
yq -i '.decision.justifies[0].role = "verification"' "$D/contract/clinic-double-booking.adr.yaml"
expect_fail "G13 ★edges 削除で corpus 改竄を隠す複合攻撃を FAIL" "$D" "floor 武装解除ガード"

# W1. 未宣言孤立は block (exit 1): inline principle 喪失で clinic 鎖が連鎖孤立すると hard FAIL (folio-ulz)。
#     総数だけでなく *どの鎖が孤立したか* を個別 substring で固定する (minor#2: 総数照合だけだと corpus 増減で
#     false-pass・別経路で総数一致の改竄を見逃しうる)。
#     ★arch pack が同 id 終端 (PRIN-SAFETY-FIRST) を冗長供給するため ADR 単独の喪失では孤立しない
#       (folio-dls drift の真因)。 ★c5r.4 (vision-pack) 追加で SRS-CLINIC-APPT は vision→SRS backward edge 経由でも
#       vision の inline principle (PRIN-PATIENT-TRUST) に終端到達できる = 3 つ目の独立終端源。
#     ★folio-1q8o (data-model-pack) 追加で DM-CLINIC-APPT の inline principle (PRIN-DATA-MINIMUM) が 4 つ目の独立終端源。
#     ★folio-ehar (interface-pack) 追加で IF-CLINIC-APPT の inline principle (PRIN-HONEST-BOUNDARY) が 5 つ目の独立終端源。
#       IF→SRS backward edge 経由で SRS も IF の終端へ到達できるため、 clinic 鎖の全終端 route を断つには
#       ADR + arch (PRIN-SAFETY-FIRST) + vision (PRIN-PATIENT-TRUST) + datamodel (PRIN-DATA-MINIMUM) + interface (PRIN-HONEST-BOUNDARY) の 5 principle.id を空にする。
#     ★TC-CLINIC-APPT の連鎖孤立 = c5r.11 B2 の意図挙動 pin (SRS が終端未到達なら test も道連れ = 根本原因の表面化)。
#       GLOSSARY-CLINIC-APPT は自前 route (→FOLIO-CONSTITUTION) を持つため孤立しない。
#       EC は免除宣言済みゆえ孤立でなく免除 warn のまま (block は未宣言の 11 鎖のみ (risk は RISK→SRS 経由・changelog は CHANGELOG→{ADR,SRS} 経由・roadmap は ROADMAP→{VISION,SRS} forward 経由で連鎖孤立 = folio-wdv0/folio-8ptq/folio-8cha) = default-block + 明示宣言)。
D="$(mktmp)"; yq -i '.principle.id = ""' "$D/contract/clinic-double-booking.adr.yaml"
yq -i '.principle.id = ""' "$D/contract/clinic-architecture.arch.yaml"
yq -i '.principle.id = ""' "$D/contract/clinic-appointment.vision.yaml"
yq -i '.principle.id = ""' "$D/contract/clinic-appointment.datamodel.yaml"
yq -i '.principle.id = ""' "$D/contract/clinic-appointment.interface.yaml"
if ! run "$D" && [[ "$RUNOUT" == *"孤立(block)=11"* \
   && "$RUNOUT" == *"孤立: ADR-CLINIC-0001"* && "$RUNOUT" == *"孤立: RES-CLINIC-0001"* \
   && "$RUNOUT" == *"孤立: SRS-CLINIC-APPT"* && "$RUNOUT" == *"孤立: ARCH-CLINIC-APPT"* \
   && "$RUNOUT" == *"孤立: TC-CLINIC-APPT"* && "$RUNOUT" == *"孤立: VISION-CLINIC-APPT"* \
   && "$RUNOUT" == *"孤立: DM-CLINIC-APPT"* && "$RUNOUT" == *"孤立: IF-CLINIC-APPT"* && "$RUNOUT" == *"孤立: RISK-CLINIC-APPT"* && "$RUNOUT" == *"孤立: CHANGELOG-CLINIC-APPT"* && "$RUNOUT" == *"孤立: ROADMAP-CLINIC-APPT"* \
   && "$RUNOUT" == *"免除: SRS-EC-CHECKOUT"* && "$RUNOUT" == *"RESULT: FAIL"* ]]; then
  ok "W1 全終端 route 喪失 → 未宣言の clinic 11 鎖 (TC/vision/DM/IF/RISK/CHANGELOG/ROADMAP 連鎖含む) が個別に孤立 block・宣言済み EC は免除 warn (exit 1)"
else ng "W1 不一致 (rc=$? / 末尾: $(printf '%s' "$RUNOUT" | tail -3 | tr '\n' '|'))"; fi

# W2. 免除宣言の代表: ADR-less な EC SRS は terminal_waiver 宣言済みゆえ warn 降格 (happy path でも常時可視)
D="$(mktmp)"
expect_pass_warn "W2 免除宣言済み EC SRS は warn 降格 + 可視一覧 (exit 0)" "$D" "免除: SRS-EC-CHECKOUT"

# U1. ★block 方向の pin (folio-ulz 核心): EC の免除宣言を削除 → 未宣言孤立が hard FAIL (exit 1)。
#     「免除宣言なし」は孤立 FAIL 行にのみ出る値 (substring が想定 gate を一意に指す)。
D="$(mktmp)"; yq -i 'del(.meta.terminal_waiver)' "$D/contract/ec-checkout.srs.yaml"
expect_fail "U1 ★免除宣言なしの孤立 SRS を block (exit 1)" "$D" "孤立: SRS-EC-CHECKOUT"

# U2. ★rationale 必須の fail-closed: 免除宣言の理由が空文字 → 宣言不備 FAIL (実質 advisory 化する空宣言を封鎖)。
D="$(mktmp)"; yq -i '.meta.terminal_waiver = ""' "$D/contract/ec-checkout.srs.yaml"
expect_fail "U2 ★理由なし免除宣言 (空文字) を宣言不備で FAIL" "$D" "免除宣言不備: SRS-EC-CHECKOUT"

# U2b. ★型不正も同経路で fail-closed: 理由が文字列でない (map) → 宣言不備 FAIL。
D="$(mktmp)"; yq -i '.meta.terminal_waiver = {"note": "x"}' "$D/contract/ec-checkout.srs.yaml"
expect_fail "U2b ★非文字列の免除宣言 (map) を宣言不備で FAIL" "$D" "免除宣言不備: SRS-EC-CHECKOUT"

# U2c. ★空白種の回避経路封鎖: 全角スペース U+3000 のみの理由も blank と判定し宣言不備 FAIL
#      (c5r.2 全角数字と同型の回避ベクタ。 NBSP も同経路で除去)。
D="$(mktmp)"; yq -i '.meta.terminal_waiver = "　　"' "$D/contract/ec-checkout.srs.yaml"
expect_fail "U2c ★全角スペースのみの免除宣言を宣言不備で FAIL" "$D" "免除宣言不備: SRS-EC-CHECKOUT"

# U2d. ★NBSP (U+00A0) のみの理由も blank と判定し宣言不備 FAIL (実装が名指しで除去する空白種の pin —
#      claimed capability を敵対固定する)。
D="$(mktmp)"; NB=$' '; yq -i ".meta.terminal_waiver = \"${NB}${NB}\"" "$D/contract/ec-checkout.srs.yaml"
expect_fail "U2d ★NBSP のみの免除宣言を宣言不備で FAIL" "$D" "免除宣言不備: SRS-EC-CHECKOUT"

# U3. ★stale 宣言の正直さ: 終端到達済み doc に waiver を足す → silent 無視せず可視 warn (exit 0)。
D="$(mktmp)"; yq -i '.meta.terminal_waiver = "stale test"' "$D/contract/clinic-appointment.srs.yaml"
expect_pass_warn "U3 ★終端到達済み doc の stale 免除宣言は可視 warn (exit 0)" "$D" "免除宣言が stale: SRS-CLINIC-APPT"

# W3. external-ref warn: folio-self の inbound 系統と amended_by 系統が *両方* emit され、 contract外 warn で
#     advisory (exit 0) になることを固定する (nit#5: substring 'contract外' だけでは両系統 emission を区別できない)。
D="$(mktmp)"
if run "$D" && [[ "$RUNOUT" == *"inbound 照会元"* && "$RUNOUT" == *"amended_by 改訂来歴"* && "$RUNOUT" == *"contract外"* ]]; then
  ok "W3 external-ref = inbound/amended_by 両系統 emit・contract外 warn (exit 0)"
else ng "W3 不一致 (rc=$? / 末尾: $(printf '%s' "$RUNOUT" | tail -3 | tr '\n' '|'))"; fi

echo "----"
echo "graph adversarial: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
