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
#   2026-07-15 (folio-6lsu verification 再抽出・07m 分割追随の帰結) = 19 contract (分類不変 8/10/1)・en 突合 132 語 (folio-verification が 28→27 語: 'invariant' は 07m 分割で srs-verification.html へ移動し原本 verification.html に data-term 不在 = 再抽出で正当に drop・pyus の rules 再抽出と同型の corpus *縮小*)・anchor 外 local 44 語 (不変)。
#   2026-07-19 (folio-bxpm srs-verification flip・admin ceiling fixup) = 20 contract (full 9 / intersect 10 / exempt 1)・en 突合 146 語 (132 + srs-verification の 14 語: 全語 canonical 収録の実測成立ゆえ full/strict = rules/verification と同根拠。 6lsu で verification から正当 drop した 'invariant' の受け皿が本 contract に収録され lineage が閉じる)・anchor 外 local 44 語 (不変)。独立再導出: 14 = yq '.glossary | length' folio-srs-verification.spec.yaml。
out="$("$GATE" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'full=9 intersect=10 exempt=1 未登録空=0' <<<"$out" \
   && grep -q 'en 突合 146 語・anchor 外 local 44 語' <<<"$out"; then
  ok "V0 baseline: clean corpus → exit 0 + 分類 20 本 (9/10/1) + 146/44 語 pin"
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

# --- V16〜V20 vocab-projection 節 (folio-9inj → ADR-0052 で転換): design-intent/vocabulary.yaml は glossary
#     contract からの生成 projection ゆえ「committed == fresh projection の whole-file byte 一致」を機械強制する。
#     旧「手動同鏡 (集合一致 + 定義逐語一致)」の検出力は byte 一致が構造的に包摂するため、 V17/V18/V19 は
#     撤去せず新 gate の FAIL substring (vocab-projection-stale) へ re-point する (改竄クラス — definition 片側編集 /
#     term 削除 / term 追加 — は個別に pin し続ける)。 gate 自身を mutation-kill するため --repo-root で偽 root を
#     注入し vocabulary.yaml のコピーを改竄する (real vocab は不可触)。
REAL_VOCAB="$(cd "$SCRIPT_DIR/../../.." && pwd)/design-intent/vocabulary.yaml"
[[ -f "$REAL_VOCAB" ]] || { echo "FATAL: vocabulary.yaml not found: $REAL_VOCAB" >&2; exit 2; }
fresh_root() { local d; d="$(mktemp -d)"; mkdir -p "$d/design-intent"; cp "$REAL_VOCAB" "$d/design-intent/vocabulary.yaml"; printf '%s' "$d"; }
# expect_fail_root / expect_pass_root — 既定 contract-dir + 注入 root で走らせる
expect_fail_root() {
  local label="$1" root="$2" sub="$3" out rc
  out="$("$GATE" --repo-root "$root" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -F -- "$sub" <<<"$out" | grep -q '\[FAIL\]'; then ok "$label"
  else bad "$label (rc=$rc / substring '$sub' の FAIL 行なし)"; fi
}

# V16 precision: 未改竄の vocab コピー → exit 0 (誤検出しない)
R="$(fresh_root)"
out="$("$GATE" --repo-root "$R" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == *"vocab projection 1 本"* ]]; then ok "V16 precision: clean vocab projection → exit 0 (projection 1 本)"
else bad "V16 precision: clean vocab projection が exit 0 でない (rc=$rc)"; fi
rm -rf "$R"

# V17 vocab-def-drift: vocabulary.yaml 側の definition を 1 字ずらす → FAIL (片側編集の封鎖 = 本節の主目的)
R="$(fresh_root)"
yq -i '(.terms[] | select(.canonical == "SSoT") | .definition) = "改竄された定義XQZ"' "$R/design-intent/vocabulary.yaml"
expect_fail_root "V17 vocab-def-drift: vocab 側 definition の片側編集 (terms subtree の 1 字改竄) → FAIL" "$R" "vocab-projection-stale"
rm -rf "$R"

# V18 vocab-projection-stale (term 削除クラス): vocab から term を削除 → FAIL (projection は contract の全語を出すため byte 不一致)
R="$(fresh_root)"
yq -i 'del(.terms[] | select(.canonical == "dual-audience"))' "$R/design-intent/vocabulary.yaml"
expect_fail_root "V18 vocab-projection-missing: vocab から term 削除 → FAIL" "$R" "vocab-projection-stale"
rm -rf "$R"

# V19 vocab-projection-stale (term 追加クラス): vocab に contract 未収録語を追加 → FAIL (folio-7ts2 の vocab⊃contract drift の回帰 pin)
R="$(fresh_root)"
yq -i '.terms += [{"canonical": "野良語XQZ", "domain": "folio-closed", "definition": "contract に無い語"}]' "$R/design-intent/vocabulary.yaml"
expect_fail_root "V19 vocab-projection-extra: vocab のみに存在する語 → FAIL (vocab⊃contract drift)" "$R" "vocab-projection-stale"
rm -rf "$R"

# V20 vocab mirror 不在 → exit 2 (緑に化けない・構成エラー)
R="$(mktemp -d)"
"$GATE" --repo-root "$R" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "V20 vocab-projection-absent: projection 先 vocabulary.yaml 不在 → exit 2"
else bad "V20 vocab-projection-absent: exit 2 でない (rc=$rc)"; fi
rm -rf "$R"

# V21 unregistered-vocab-projection: VOCAB_REGISTRY 未登録の glossary SSoT は素通りしない (完結性 sweep)。
#     gate の registry は script 内 SSoT ゆえ、 script を複製して registry 行を落とし挙動を pin する。
D="$(mktemp -d)"
G2="$D/gate.sh"
grep -v '^folio-glossary\.glossary\.yaml|design-intent/vocabulary\.yaml|' "$GATE" > "$G2"
chmod +x "$G2"
cp "$SCRIPT_DIR/project-vocabulary.sh" "$D/project-vocabulary.sh"
out="$("$G2" --contract-dir "$SRC_CONTRACT" --repo-root "$(cd "$SCRIPT_DIR/../../.." && pwd)" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -F -- "unregistered-vocab-projection: glossary SSoT 'folio-glossary.glossary.yaml'" <<<"$out" | grep -q '\[FAIL\]'; then
  ok "V21 sweep: VOCAB_REGISTRY 未登録の glossary SSoT → FAIL (default-block)"
else bad "V21 sweep: 未登録 glossary SSoT が FAIL にならない (rc=$rc)"; fi
rm -rf "$D"

# --- V22〜V25 def-parity 節 + vocab-registry rot (folio-9inj ceiling): 定義文字列の 5 番目の複製
#     (source contract の glossary[].def) の逐語 pin と、 同鏡検査の「0 本で恒真 PASS」経路の封鎖。

# V22 vocab-registry-rot: PARITY_REGISTRY 側から glossary SSoT の参照が消えると projection 検査が SSOT_SEEN から
#     蒸発し「vocab projection 0 本」で緑になりうる。 逆向き検査 (登録済 SSoT の未検査 = FAIL) を pin する。
#     ★mutation regex は registry の file 名形状と結合している: [a-z-] はハイフン入り contract 名
#       (folio-srs-verification 等) も strip するための widen (folio-bxpm で [a-z] のままだと新行が mutation を
#       生き残り SSoT 参照が消えず rot 非発火 = MK 空撃ち)。 registry へ名前形状の新しい行を足したら本 regex を同期する。
D="$(mktemp -d)"; G2="$D/gate.sh"
grep -v '^folio-[a-z-]*\.\(spec\|principle\|vision\|glossary\)\.yaml|[a-z]*|folio-glossary\.glossary\.yaml$' "$GATE" > "$G2"
chmod +x "$G2"
cp "$SCRIPT_DIR/project-vocabulary.sh" "$D/project-vocabulary.sh"
out="$("$G2" --contract-dir "$SRC_CONTRACT" --repo-root "$(cd "$SCRIPT_DIR/../../.." && pwd)" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -F -- "vocab-registry-rot: 登録済 projection SSoT 'folio-glossary.glossary.yaml' が未検査" <<<"$out" | grep -q '\[FAIL\]'; then
  ok "V22 rot: PARITY_REGISTRY から projection SSoT の参照が消える → FAIL (projection 検査の蒸発 = 恒真 PASS の封鎖)"
else bad "V22 rot: projection 検査が黙って蒸発した (rc=$rc)"; fi
rm -rf "$D"

# --- V26〜V28 (ADR-0052 / folio-wg2l 新設): projection stale gate 固有の恒真化経路を封鎖する MK。
#     ★per-shape: V17 は terms subtree (definition 1 字) を撃つ。 header は *非 terms 領域* = 別の DOM/構造
#       クラスゆえ V26 で別弾を撃つ (1 instance の実弾は構造差 instance の穴を証明しない)。
#       V26 は同時に「header を committed から読む循環実装」の MK でもある: もし gate が header を committed
#       から読んで fresh 側へ写していれば、 header 改竄は両側に伝播して byte 一致 = 恒真 PASS になり V26 が落ちる。

# V26 header 改竄: 生成物 warning header を 1 字ずらす → FAIL (循環 header なら緑に化ける = 本 MK が割る)
R="$(fresh_root)"
perl -i -pe 's/このファイルは生成物です/このファイルは生成物ですXQZ/ if $. < 5' "$R/design-intent/vocabulary.yaml"
grep -q 'このファイルは生成物ですXQZ' "$R/design-intent/vocabulary.yaml" \
  || bad "V26 setup: header 改竄が適用されていない (MK が空撃ちになる)"
expect_fail_root "V26 header-drift: 生成 header の 1 字改竄 → FAIL (循環 header 実装なら恒真 PASS になる経路の封鎖)" "$R" "vocab-projection-stale"
rm -rf "$R"

# V27 projection script 不在 → exit 2 (「projection を実行できない」を緑に化けさせない)
D="$(mktemp -d)"; G2="$D/gate.sh"
cp "$GATE" "$G2"; chmod +x "$G2"        # project-vocabulary.sh を伴わない dir へ複製 = SCRIPT_DIR 相対で不在
"$G2" --contract-dir "$SRC_CONTRACT" --repo-root "$(cd "$SCRIPT_DIR/../../.." && pwd)" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "V27 projection-script-absent: projection script 不在 → exit 2 (構成エラー・緑に化けない)"
else bad "V27 projection-script-absent: exit 2 でない (rc=$rc)"; fi
rm -rf "$D"

# V28 projection が空出力 → FAIL (precondition。 空 fresh と committed を比べて「差分なし」で緑にしない)
D="$(mktemp -d)"; G2="$D/gate.sh"
cp "$GATE" "$G2"; chmod +x "$G2"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/project-vocabulary.sh"; chmod +x "$D/project-vocabulary.sh"
out="$("$G2" --contract-dir "$SRC_CONTRACT" --repo-root "$(cd "$SCRIPT_DIR/../../.." && pwd)" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -F -- "vocab-projection-precondition" <<<"$out" | grep -q '\[FAIL\]'; then
  ok "V28 projection-empty: projection が空出力 → FAIL (precondition・恒真 PASS の封鎖)"
else bad "V28 projection-empty: 空出力が FAIL にならない (rc=$rc)"; fi
rm -rf "$D"

# V23 glossary-def-drift: source contract (folio-rules) の SSoT 収録語 def を 1 字ずらす → FAIL
#     (定義文字列は spec contract の glossary[].def にも byte 複製される = 5 番目の複製の片側編集封鎖)
D="$(fresh_corpus)"
MUT='改竄された定義XQZ' yq -i '(.glossary[] | select(.term == "SSoT") | .def) = strenv(MUT)' "$D/folio-rules.spec.yaml"
expect_fail "V23 def-drift(source): spec contract の SSoT 収録語 def の片側編集 → FAIL" "$D" "glossary-def-drift term='SSoT' in folio-rules.spec.yaml"
rm -rf "$D"

# V24 def-unregistered: DEF_REGISTRY 未登録の source contract は素通りしない (default-block sweep)
#     ★gate 複製 MK は projection script (SCRIPT_DIR 相対の hard 依存) を伴わせる: 伴わないと本 MK が
#       「def 未登録の FAIL」でなく「projection script 不在の exit 2」を測ってしまい、 検査軸がすり替わる
#       (script 不在 → exit 2 自体は V27 が専用に pin する)。
D="$(mktemp -d)"; G2="$D/gate.sh"
grep -v '^folio-rules\.spec\.yaml|strict|$' "$GATE" > "$G2"
chmod +x "$G2"
cp "$SCRIPT_DIR/project-vocabulary.sh" "$D/project-vocabulary.sh"
out="$("$G2" --contract-dir "$SRC_CONTRACT" --repo-root "$(cd "$SCRIPT_DIR/../../.." && pwd)" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -F -- "def-unregistered: 'folio-rules.spec.yaml'" <<<"$out" | grep -q '\[FAIL\]'; then
  ok "V24 sweep: DEF_REGISTRY 未登録の source contract → FAIL (default-block)"
else bad "V24 sweep: 未登録 source contract の def が無検査で素通り (rc=$rc)"; fi
rm -rf "$D"

# V25 precision(local): local 批准 file (folio-constitution = 平易 def を採る) の def 改変は FAIL にしない
#     (緩和の scope が def のみ・登録行単位であることの pin。 en 突合は継続する)
D="$(fresh_corpus)"
MUT='ページ固有の平易な言い換えXQZ' yq -i '(.glossary[] | select(.term == "canonical name") | .def) = strenv(MUT)' "$D/folio-constitution.principle.yaml"
expect_pass "V25 precision(local): local 批准 file の def 改変は誤検出しない (緩和は登録行 scope)" "$D"
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
