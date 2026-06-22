#!/usr/bin/env bash
# folio engine B5-I (folio-p4o) — 照会 graph 終端完備検証 (verify-graph.sh) 敵対回帰テスト
#
# verify-graph.sh の fail-closed gate が以下を捕捉することを回帰確認する:
#   - rolemap floor pin (edge.role == rolemap[node.type]) を *どちら側の改竄でも* (二重担保) FAIL
#   - SRS の exploration 不在 (forbidden_roles) を corpus scan で実証し密輸を FAIL
#   - dangling 照会 (graph 不在 node 先) / rolemap roles allowlist 逸脱 / rolemap 不在 / doc_id 欠落・重複 を FAIL
#   - 孤立 (ADR-less SRS / inline principle 喪失) は warn = exit 0 (advisory・FAIL でない)
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

# H0. happy path: exit 0 / 終端完備=5 / FLOOR-OK
#   B6 (folio-8ct) で spec-pack (FOLIO-RULES → constitution・principle_edge) を corpus へ追加し終端完備=4→5 に増えた。
D="$(mktmp)"
if run "$D" && [[ "$RUNOUT" == *"終端完備=5 孤立(warn)=1"* && "$RUNOUT" == *"RESULT: FLOOR-OK"* ]]; then
  ok "H0 happy path (終端完備=5 / 孤立=1 / FLOOR-OK / exit 0)"
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

# W1. 孤立は warn (exit 0): inline principle 喪失で clinic 鎖が連鎖孤立しても FAIL でない。
#     総数 (孤立=4) だけでなく *どの鎖が孤立したか* (ADR/research/SRS-CLINIC 3 鎖 + 既存 EC) を個別 substring で
#     固定する (minor#2: 総数照合だけだと corpus 増減で false-pass・別経路で総数 4 の改竄を見逃しうる)。
D="$(mktmp)"; yq -i '.principle.id = ""' "$D/contract/clinic-double-booking.adr.yaml"
if run "$D" && [[ "$RUNOUT" == *"孤立(warn)=4"* \
   && "$RUNOUT" == *"孤立: ADR-CLINIC-0001"* && "$RUNOUT" == *"孤立: RES-CLINIC-0001"* \
   && "$RUNOUT" == *"孤立: SRS-CLINIC-APPT"* && "$RUNOUT" == *"孤立: SRS-EC-CHECKOUT"* ]]; then
  ok "W1 inline principle 喪失 → clinic 3 鎖 + EC が個別に孤立 warn (exit 0)"
else ng "W1 不一致 (rc=$? / 末尾: $(printf '%s' "$RUNOUT" | tail -3 | tr '\n' '|'))"; fi

# W2. 孤立 warn の代表: ADR-less な EC SRS は孤立 warn (happy path でも常時)
D="$(mktmp)"
expect_pass_warn "W2 ADR-less EC SRS は孤立 warn (exit 0)" "$D" "孤立: SRS-EC-CHECKOUT"

# W3. external-ref warn: folio-self の inbound 系統と amended_by 系統が *両方* emit され、 contract外 warn で
#     advisory (exit 0) になることを固定する (nit#5: substring 'contract外' だけでは両系統 emission を区別できない)。
D="$(mktmp)"
if run "$D" && [[ "$RUNOUT" == *"inbound 照会元"* && "$RUNOUT" == *"amended_by 改訂来歴"* && "$RUNOUT" == *"contract外"* ]]; then
  ok "W3 external-ref = inbound/amended_by 両系統 emit・contract外 warn (exit 0)"
else ng "W3 不一致 (rc=$? / 末尾: $(printf '%s' "$RUNOUT" | tail -3 | tr '\n' '|'))"; fi

echo "----"
echo "graph adversarial: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
