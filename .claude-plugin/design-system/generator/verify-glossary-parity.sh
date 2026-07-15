#!/usr/bin/env bash
# folio 文書規律エンジン (folio-dvsk) — glossary en parity gate (cross-contract lint・fail-closed)
#
# folio-51bb 裁定 B の保全 gate: suite の glossary contract .terms[] (canonical, en) が英語表記 (en) の
# **唯一の正本 (SSoT)** であり、 source contract の glossary 節 (term, en) は SSoT と逐語一致しなければ
# ならない。 検査は集合所属 + 文字列一致のみ = machine/LLM 境界の機械側 (意味判定なし・partial-enum なし)。
# 51bb ceiling (wf_469061a2) の info finding「source 側 en は表示専用扱いで drift 無防備」の機構化。
#
# ★fail-closed 設計 (qvv 第 6 実証 = 緩和には scope gate を束ねる):
#   - PARITY_REGISTRY が全 contract の分類 SSoT (default-block)。 非空 glossary 節を持つ未登録 contract は
#     FAIL (完結性 sweep: 新 contract は登録 = mode の明示批准を経ないと素通りできない)。
#   - mode は per-file 明示。 intersect (SSoT 外のページ固有語を許す緩和) は登録行単位でしか効かない
#     (pack/suite 一括の緩和は置かない)。
#   - SSoT 自身の anchor 完全性も検査 (canonical/en 空・canonical 重複 = 突合の土台崩壊で FAIL)。
#   - exit は計算済み決定トークン ($fail) のみから導出 (data 補間出力の grep 禁止・mzn.1 教訓)。
#
# mode:
#   full      = membership (全語 SSoT 収録) + en 逐語一致。 clinic suite (glossary contract ヘッダが
#               「source 5 contract の union 25 terms」と宣言 = union 不変条件の保全を兼ねる) と、
#               全語収録が実測成立している folio spec 3 本 (2026-07-05 実測: 全 63 語 SSoT 収録・en 一致)。
#   intersect = SSoT 収録語のみ en 逐語一致。 SSoT 外のページ固有語 (例: folio-constitution の
#               declarative / drift / 単一の真実源 / orphan) は anchor 不在 = 検査対象外 (local と数えて
#               報告のみ)。 glossary contract 自身の chrome 用語帯 (ページの仕組みを説く語) も self 突合でここ。
#   exempt    = suite 内に glossary SSoT が存在しない (理由必須)。
#
# ★vocab-projection 節 (folio-9inj → ADR-0052 で転換): design-intent/vocabulary.yaml は glossary SSoT
#   contract の terms[] からの **生成 projection** (project-vocabulary.sh の全域関数: canonical/domain/
#   definition←formal_def)。 vocabulary.yaml は folio fix の tooltip populate 等が読む runtime SSoT ゆえ
#   撤去できないが、 folio-9inj 当時の「手動同鏡 (人間規律で二重保持)」は機械導出へ置換された。
#   本節は「committed == fresh projection」を whole-file byte 比較で機械強制する (default-block:
#   VOCAB_REGISTRY 未登録の glossary SSoT は FAIL = 新 suite が黙って projection なしで増えない)。
#   byte 一致は旧検査 (canonical 集合一致 + 定義逐語一致) を構造的に含意する上位集合で、 加えて header・
#   語順・domain・整形の drift も捕捉する。 検査は byte 比較のみ (意味判定なし = 機械側)。
#   ★registry rot (逆向き検査): VOCAB_REGISTRY に登録した SSoT が PARITY_REGISTRY から参照されなくなると
#     SSOT_SEEN から消え、 projection 検査が「0 本」で静かに蒸発する (計数恒真 PASS)。 よって (a) 登録済 SSoT が
#     未検査なら FAIL、 (b) 非 exempt 登録があるのに検査 0 本なら FAIL とする (緩和が別軸を巻き込む fail-open の封鎖)。
#
# ★def-parity 節 (folio-9inj ceiling): 定義文字列は glossary SSoT contract の formal_def / vocabulary.yaml の
#   definition だけでなく、 source contract の glossary[].def にも byte 複製される (spec HTML の inline
#   data-tooltip は 原本 HTML ↔ vocabulary.yaml を folio validate が、 原本 HTML ↔ contract prose を
#   verify-spec §11 round-trip が連鎖 pin する)。 source の glossary[].def はどの gate にも束縛されておらず
#   片側 drift が素通りしていた (実弾実証) ため、 DEF_REGISTRY で per-file に strict (SSoT 収録語の def は
#   SSoT formal_def と逐語一致) / local (ページ固有の平易 def を採る批准・理由 MUST) を明示分類し、 strict の
#   逐語一致を機械強制する (default-block: 未登録 = FAIL)。
#
# 実行: admin gate funnel (contract 変更の land 前) + test-adversarial-glossary-parity.sh。 ci.yml deterministic
# floor に blocking 配線済 (folio-9inj・suite も同梱配線) ゆえ ADR-0052 の projection stale gate も同配線を継承する。
# HTML は読まない (contract↔contract、 および contract↔vocabulary.yaml = どちらも機械可読 YAML)。
#
# 用法: verify-glossary-parity.sh [--contract-dir <dir>] [--repo-root <dir>]
#   --repo-root は vocab-projection の突合先 (design-intent/vocabulary.yaml 等) の解決 base。 既定 = generator の
#   3 つ上 (repo root)。 敵対テストが projection 検査自体を mutation-kill するための注入点。
# exit: 0 = 全緑 / 1 = parity 違反・分類漏れ・anchor 崩壊・vocab projection stale / 2 = 構成エラー
#       (SSoT 不在・projection 先 不在/parse 不能・projection script 不在・依存欠落・未知引数)
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$SCRIPT_DIR/contract"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract-dir) CONTRACT_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    *) echo "verify-glossary-parity: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

command -v yq >/dev/null || { echo "verify-glossary-parity: yq required" >&2; exit 2; }
command -v jq >/dev/null || { echo "verify-glossary-parity: jq required" >&2; exit 2; }
[[ -d "$CONTRACT_DIR" ]] || { echo "verify-glossary-parity: contract-dir 不在: $CONTRACT_DIR" >&2; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
pfail() { printf '  [FAIL] %s\n' "$1"; fail=1; file_fail=1; }

# ===== PARITY_REGISTRY (批准済み分類の SSoT・default-block) =====
# 書式: <contract file>|<mode>|<SSoT glossary contract | exempt 理由>。 行頭 # はコメント。
# 新しい contract に非空 glossary 節を足すと未登録 FAIL する (登録 = mode の明示批准。 intersect 追加は
# 「その file のページ固有語を anchor 外として許す」緩和の批准を意味する — 一括緩和は置かない)。
PARITY_REGISTRY='
# --- clinic suite (SSoT = clinic-appointment.glossary.yaml。 union 宣言ゆえ source は full) ---
clinic-appointment.srs.yaml|full|clinic-appointment.glossary.yaml
clinic-appointment.testcases.yaml|full|clinic-appointment.glossary.yaml
clinic-architecture.arch.yaml|full|clinic-appointment.glossary.yaml
clinic-double-booking.adr.yaml|full|clinic-appointment.glossary.yaml
clinic-double-booking.research.yaml|full|clinic-appointment.glossary.yaml
clinic-appointment.vision.yaml|full|clinic-appointment.glossary.yaml
# changelog は changelog メタ語彙 (変更履歴/リリース/版/セマンティックバージョニング/非推奨/競合) を持つ = clinic ドメイン union SSoT の
# 対象外ゆえ intersect (SSoT 収録語〔診療枠/満枠/リマインド通知/本人確認〕のみ en 逐語一致・ページ固有語は検査対象外・folio-8ptq)。
clinic-changelog.changelog.yaml|intersect|clinic-appointment.glossary.yaml
# roadmap は roadmap メタ語彙 (ロードマップ/マイルストーン/優先度) を持つ = clinic ドメイン union SSoT の
# 対象外ゆえ intersect (SSoT 収録語〔診療枠/満枠/本人確認/リマインド通知〕のみ en 逐語一致・ページ固有語は検査対象外・folio-8cha)。
clinic-roadmap.roadmap.yaml|intersect|clinic-appointment.glossary.yaml
# data-model は data-modeling メタ語彙 (エンティティ/ER 図/不変条件/識別子/区分/参照) を持つ = clinic ドメイン union SSoT の
# 対象外ゆえ intersect (SSoT 収録語のみ en 逐語一致・ページ固有語は検査対象外・folio-1q8o)。
clinic-appointment.datamodel.yaml|intersect|clinic-appointment.glossary.yaml
# interface は interface メタ語彙 (操作/境界/エラーカタログ/外部連携/横断の決まり) を持つ = clinic ドメイン union SSoT の
# 対象外ゆえ intersect (SSoT 収録語のみ en 逐語一致・ページ固有語は検査対象外・en 突合想定 0・folio-ehar)。
clinic-appointment.interface.yaml|intersect|clinic-appointment.glossary.yaml
clinic-risk.risk.yaml|intersect|clinic-appointment.glossary.yaml
clinic-appointment.glossary.yaml|intersect|clinic-appointment.glossary.yaml
# --- folio suite (SSoT = folio-glossary.glossary.yaml。 rules/verification 2 本は全語収録の実測成立ゆえ full) ---
folio-rules.spec.yaml|full|folio-glossary.glossary.yaml
folio-verification.spec.yaml|full|folio-glossary.glossary.yaml
# relations は文書主題が外部標準語彙 (JSON-LD / dcterms / schema.org / PROV-O 等) ゆえ、 それら主題語は
# folio canonical vocabulary (SSoT) ではなくページ固有語。 folio-49x (gate I major) で主題語を glossary へ収録し
# 非エンジニアが引けるようにした結果、 SSoT 外語を含むため intersect へ (SSoT 収録の folio 語 11 は en 逐語一致を継続、
# 外部主題語のみ anchor 外として exempt = 緩和は非 SSoT 語に scope 限定)。full の根拠「全語収録の実測成立」は主題語収録で失効。
folio-relations.spec.yaml|intersect|folio-glossary.glossary.yaml
folio-constitution.principle.yaml|intersect|folio-glossary.glossary.yaml
folio-vision.vision.yaml|intersect|folio-glossary.glossary.yaml
folio-glossary.glossary.yaml|intersect|folio-glossary.glossary.yaml
# --- suite 内に glossary SSoT が無い contract (理由必須) ---
ec-checkout.srs.yaml|exempt|ec suite に glossary SSoT なし (glossary doc 追加時に full 登録へ)
'

declare -A R_MODE R_SSOT
while IFS='|' read -r rf rm rs; do
  [[ -z "$rf" || "$rf" == \#* ]] && continue
  R_MODE[$rf]="$rm"; R_SSOT[$rf]="$rs"
done <<< "$PARITY_REGISTRY"

# ===== VOCAB_REGISTRY (glossary SSoT contract → 生成 projection 先 vocabulary.yaml・default-block) =====
# 書式: <glossary SSoT contract>|<repo-root 相対の vocabulary path | exempt>|<理由/注記 (exempt は MUST)>
# PARITY_REGISTRY が参照する全 glossary SSoT はここに分類必須 (未登録 = FAIL)。 新 suite が projection なしで
# 黙って増えるのを防ぐ完結性 sweep (mode の明示批准と同型)。
VOCAB_REGISTRY='
folio-glossary.glossary.yaml|design-intent/vocabulary.yaml|folio 本体: contract = 唯一の edit-SSoT (ADR-0052)・vocabulary.yaml = project-vocabulary.sh の生成 projection (folio fix の tooltip populate 等が読む runtime SSoT)。 生成物ゆえ byte-stale 検査必須
clinic-appointment.glossary.yaml|exempt|clinic は generator demo suite (vocabulary.yaml consumer を持たない = tooltip populate 対象外ゆえ projection 先なし)
'
declare -A V_PATH V_NOTE
n_vocab_active=0
while IFS='|' read -r vf vp vn; do
  [[ -z "$vf" || "$vf" == \#* ]] && continue
  V_PATH[$vf]="$vp"; V_NOTE[$vf]="$vn"
  [[ "$vp" != "exempt" ]] && n_vocab_active=$((n_vocab_active+1))
done <<< "$VOCAB_REGISTRY"

# ===== DEF_REGISTRY (source contract の glossary[].def の扱い・default-block・folio-9inj ceiling) =====
# 書式: <contract file>|<strict | local>|<注記 (local は理由 MUST)>
#   strict = SSoT 収録語 (present==1) の def は SSoT の formal_def と逐語一致 MUST (定義の複製先を pin)。
#   local  = 同語でもページ固有の平易 def を採る批准 (理由 MUST)。 SSoT 逐語一致は課さない。
# PARITY_REGISTRY の非 exempt 全 file はここに分類必須 (未登録 = FAIL = 新 contract が無 gate で増えない)。
DEF_REGISTRY='
clinic-appointment.srs.yaml|strict|
clinic-appointment.testcases.yaml|strict|
clinic-architecture.arch.yaml|strict|
clinic-double-booking.adr.yaml|strict|
clinic-double-booking.research.yaml|strict|
clinic-appointment.vision.yaml|strict|
clinic-changelog.changelog.yaml|strict|
clinic-appointment.datamodel.yaml|strict|
clinic-appointment.interface.yaml|strict|
clinic-risk.risk.yaml|strict|
clinic-roadmap.roadmap.yaml|strict|
clinic-appointment.glossary.yaml|strict|
folio-rules.spec.yaml|strict|
folio-verification.spec.yaml|strict|
folio-relations.spec.yaml|strict|
folio-vision.vision.yaml|strict|
# constitution は非エンジニア読者向けに同語をページ文脈の平易語で定義する doc (例: canonical name =
# 「一つの概念に対して使う、 ただ一つの正式な呼び名」)。 en は SSoT 逐語一致を継続し def のみ local。
folio-constitution.principle.yaml|local|平易定義を採る principle doc (SSoT 逐語 def は読者層に不適・en 突合は継続)
# glossary contract 自身の chrome 用語帯 (ページの仕組みを説く語) は同語でもページ固有の平易 def を採る
# (self 突合ゆえ formal_def との逐語一致を課すと人間層の説明が機械層 def に潰される)。
folio-glossary.glossary.yaml|local|glossary 自身の chrome 用語帯 = ページの仕組みを説く平易 def (機械層 formal_def とは別役割)
'
declare -A D_MODE D_NOTE
while IFS='|' read -r df dm dn; do
  [[ -z "$df" || "$df" == \#* ]] && continue
  D_MODE[$df]="$dm"; D_NOTE[$df]="$dn"
done <<< "$DEF_REGISTRY"

echo "== glossary en parity gate (folio-dvsk・51bb 裁定 B 保全) =="

# ===== 1. SSoT anchor 完全性 (突合の土台。 崩壊 = FAIL / 不在 = exit 2) =====
declare -A SSOT_SEEN
for rf in "${!R_MODE[@]}"; do
  [[ "${R_MODE[$rf]}" == "exempt" ]] && continue
  SSOT_SEEN[${R_SSOT[$rf]}]=1
done
for s in "${!SSOT_SEEN[@]}"; do
  sp="$CONTRACT_DIR/$s"
  [[ -f "$sp" ]] || { echo "verify-glossary-parity: SSoT contract 不在: $s" >&2; exit 2; }
  yq -o=json '.' "$sp" > "$TMP/ssot-$s.json" 2>/dev/null \
    || { echo "verify-glossary-parity: SSoT parse 失敗: $s" >&2; exit 2; }
  file_fail=0
  # canonical / en の空・C0 制御文字 (改行/tab 等)・非 object = anchor 自体が壊れている (fail-closed)。
  # ★制御文字拒否は肯定形 invariant (core_validate_strings の tab/改行拒否と同型): 改行は行指向処理の
  #   record framing を割る攻撃面 (ceiling wf_40306116 実弾) ゆえクラスごと閉塞する。
  nbad="$(jq -r '[.terms // [] | .[] | select((type != "object") or (((.canonical // "") | tostring) == "") or (((.en // "") | tostring) == "") or (((((.canonical // "") | tostring) + ((.en // "") | tostring)) | explode | map(select(. < 32)) | length) > 0))] | length' "$TMP/ssot-$s.json")"
  [[ "$nbad" == "0" ]] || pfail "ssot-malformed: canonical/en 空・制御文字 or 非 object entry $nbad 件 in $s"
  # canonical 重複 = 同語に en が 2 通り定義しうる (from_entries の last-win で黙って上書きされる前に FAIL)
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    pfail "ssot-dup canonical='$d' in $s (同語の en 定義が一意でない)"
  done < <(jq -r '.terms // [] | .[] | (.canonical // "") | tostring' "$TMP/ssot-$s.json" | sort | uniq -d)
  # canonical → en の突合 map
  jq '[.terms // [] | .[] | select(type == "object") | {key: ((.canonical // "") | tostring), value: ((.en // "") | tostring)}] | from_entries' \
    "$TMP/ssot-$s.json" > "$TMP/map-$s.json"
  # canonical → formal_def の突合 map (def-parity 節が strict file の glossary[].def を逐語 pin する)
  jq '[.terms // [] | .[] | select(type == "object") | {key: ((.canonical // "") | tostring), value: ((.formal_def // "") | tostring)}] | from_entries' \
    "$TMP/ssot-$s.json" > "$TMP/defmap-$s.json"
  [[ "$file_fail" == "0" ]] && printf '  [OK]   anchor: %s (%s 語)\n' "$s" "$(jq 'length' "$TMP/map-$s.json")"
done

# ===== 1b. vocab-projection (glossary SSoT contract → vocabulary.yaml の生成 projection stale 検査・ADR-0052) =====
# 不変条件: committed vocabulary.yaml == fresh projection (project-vocabulary.sh の出力) が **whole-file byte 一致**。
#
# ★folio-9inj の「手動同鏡 (集合完全一致 + 定義逐語一致)」を *包摂して置換* する: vocabulary.yaml は
#   contract.terms[] からの全域 projection になった (ADR-0052) ため、 byte 一致は canonical 集合一致 +
#   definition 逐語一致を **構造的に含意する** (旧検査の上位集合)。 加えて旧検査が見なかった面 —
#   header 文言・語順・domain・YAML 整形の drift — も同時に捕捉する。 意味判定なし = byte 比較のみ (機械側)。
#
# ★非循環 (folio-wg2l Leg 0 ②・「gate が自分の種で自分を検査する」恒真化の封鎖):
#   (a) header は project-vocabulary.sh 内のリテラル定数。 committed から読み戻さない (読むと header 改竄が
#       fresh 側へも伝播して byte 比較が恒真 PASS 化する)。
#   (b) 比較は committed ($REPO_ROOT 由来) vs fresh projection (実 contract 由来・毎回新規生成・pre-seed 禁止)。
#       projection vs contract にしない (それは projection の自己無矛盾を見るだけで committed を検査しない)。
#   (c) normalize しない (整形の正解は script の出力そのもの。 quote 剥ぎ・空白畳みは drift masking)。
# ★byte 比較の前に precondition を assert する (「再生成できなかった」を差分なし = PASS に化けさせない)。
n_mirror=0
PROJECT_SCRIPT="$SCRIPT_DIR/project-vocabulary.sh"
for s in "${!SSOT_SEEN[@]}"; do
  vp="${V_PATH[$s]:-}"
  if [[ -z "$vp" ]]; then
    file_fail=0
    pfail "unregistered-vocab-projection: glossary SSoT '$s' が VOCAB_REGISTRY 未登録 (projection 先 vocabulary.yaml か exempt 理由を明示批准して登録)"
    continue
  fi
  if [[ "$vp" == "exempt" ]]; then
    file_fail=0
    if [[ -z "${V_NOTE[$s]:-}" ]]; then pfail "vocab-projection-exempt-noreason: '$s' の exempt に理由が無い"; continue; fi
    printf '  [OK]   vocab-projection exempt: %s — %s\n' "$s" "${V_NOTE[$s]}"
    continue
  fi
  vfile="$REPO_ROOT/$vp"
  [[ -f "$vfile" ]] || { echo "verify-glossary-parity: vocab projection 先が不在: $vfile" >&2; exit 2; }
  [[ -x "$PROJECT_SCRIPT" ]] || { echo "verify-glossary-parity: projection script 不在/非実行可: $PROJECT_SCRIPT" >&2; exit 2; }
  file_fail=0

  # ---- fresh projection を毎回新規 file へ生成 (stale/前回残骸/cp committed の pre-seed 禁止) ----
  fresh="$TMP/fresh-$s.yaml"
  rm -f "$fresh"
  if ! "$PROJECT_SCRIPT" --contract "$CONTRACT_DIR/$s" --out "$fresh" >/dev/null 2>"$TMP/perr-$s"; then
    pfail "vocab-projection-unrunnable: '$s' からの projection 生成に失敗 (再生成不能 = FAIL・skip 化しない): $(tr '\n' ' ' < "$TMP/perr-$s")"
    continue
  fi

  # ---- precondition (byte 比較前・fail-closed): 非空 / 構造マーカー / 下限サイズ / yq parse / 語数一致 ----
  #      語数の期待値は contract 由来で導出する (magic number を置かない = corpus 成長で latent 赤にならない)。
  pperr=""
  [[ -s "$fresh" ]] || pperr="projection 出力が空"
  [[ -z "$pperr" ]] && { grep -qx 'terms:' "$fresh" || pperr="projection 出力に構造マーカー 'terms:' が無い"; }
  if [[ -z "$pperr" ]]; then
    fsz="$(wc -c < "$fresh")"
    [[ "$fsz" -ge 2000 ]] || pperr="projection 出力 ${fsz} byte < 下限 2000 (空/半端な出力の恒真化封鎖)"
  fi
  if [[ -z "$pperr" ]]; then
    nfresh="$(yq -r '.terms | length' "$fresh" 2>/dev/null)" || pperr="projection 出力が yq で parse 不能"
  fi
  if [[ -z "$pperr" ]]; then
    ncon="$(jq -r '.terms // [] | length' "$TMP/ssot-$s.json")"
    if [[ "$nfresh" != "$ncon" ]]; then pperr="projection 語数 $nfresh != contract 語数 $ncon (導出の全域性が崩れた)"
    elif ! [[ "$nfresh" =~ ^[0-9]+$ ]] || [[ "$nfresh" -lt 1 ]]; then pperr="projection 語数が 0/不正 ('$nfresh') = vacuous な byte 一致を許さない"; fi
  fi
  if [[ -z "$pperr" ]]; then
    # committed 側も同じ土台 assert (committed が空/壊れなら byte 比較の意味が無い = 恒真化の入口)
    yq -r '.terms | length' "$vfile" >/dev/null 2>&1 || pperr="committed $vp が yq で parse 不能"
  fi
  if [[ -n "$pperr" ]]; then
    pfail "vocab-projection-precondition: '$s' → $vp: $pperr"
    continue
  fi

  # ---- whole-file byte 比較 (header 1 字・definition 1 字の改竄も FAIL) ----
  if ! cmp -s "$fresh" "$vfile"; then
    pfail "vocab-projection-stale: $vp が contract '$s' からの fresh projection と byte 不一致 (vocabulary.yaml は生成物: 手編集したか再生成漏れ。 contract 側を編集して project-vocabulary.sh --out $vp で再生成し同一 commit で land する)"
    # 差分の所在を surface (判定は上の byte 比較が担い、 ここは診断のみ・先頭 20 行)
    while IFS= read -r dl; do
      [[ -z "$dl" ]] && continue
      printf '         %s\n' "$dl"
    done < <(diff "$vfile" "$fresh" | head -20)
  fi
  if [[ "$file_fail" == "0" ]]; then
    n_mirror=$((n_mirror+1))
    printf '  [OK]   vocab-projection: %s → %s (%s 語・committed == fresh projection の whole-file byte 一致)\n' \
      "$s" "$vp" "$nfresh"
  fi
done

# ===== 1c. vocab-registry rot (逆向き検査: 登録した projection ペアが実際に検査されたか・恒真 PASS の封鎖) =====
# PARITY_REGISTRY 側の 1 行編集 (SSoT 列の差し替え / 全行 exempt 化) だけで SSOT_SEEN から glossary SSoT が
# 消え、 vocab projection 検査が「0 本」で黙って蒸発しうる (計数恒真 PASS)。 登録済 SSoT の未検査を FAIL にする。
file_fail=0
for vf in "${!V_PATH[@]}"; do
  [[ -n "${SSOT_SEEN[$vf]:-}" ]] || \
    pfail "vocab-registry-rot: 登録済 projection SSoT '$vf' が未検査 (PARITY_REGISTRY から参照が消えた = projection 検査の蒸発)"
done
if [[ "$n_vocab_active" -gt 0 && "$n_mirror" == "0" ]]; then
  pfail "vocab-projection-vacuous: 非 exempt の projection 登録が $n_vocab_active 件あるのに vocab projection 検査 0 本 (恒真 PASS)"
fi

# ===== 2. registry rot (登録済 file の実在 = fail-loud) =====
for rf in "${!R_MODE[@]}"; do
  [[ -f "$CONTRACT_DIR/$rf" ]] || pfail "registry-missing-file: 登録済 contract 不在: $rf"
done
# DEF_REGISTRY rot: 登録済 file が PARITY_REGISTRY の非 exempt に居ない = 死んだ登録 (検査されない)
for df in "${!D_MODE[@]}"; do
  if [[ -z "${R_MODE[$df]:-}" || "${R_MODE[$df]}" == "exempt" ]]; then
    pfail "def-registry-rot: DEF_REGISTRY 登録の '$df' が PARITY_REGISTRY の非 exempt に不在 (def 検査が走らない死に登録)"
  fi
  if [[ "${D_MODE[$df]}" != "strict" && "${D_MODE[$df]}" != "local" ]]; then
    pfail "def-registry-badmode: '$df' の def mode が strict/local でない ('${D_MODE[$df]}')"
  fi
  if [[ "${D_MODE[$df]}" == "local" && -z "${D_NOTE[$df]:-}" ]]; then
    pfail "def-local-noreason: '$df' の local 批准に理由が無い"
  fi
done

# ===== 3. sweep + per-file parity (contract/*.yaml 全数分類 = 完結性 sweep) =====
n_full=0; n_intersect=0; n_exempt=0; n_unreg_empty=0; terms_checked=0; n_local=0; defs_checked=0
for path in "$CONTRACT_DIR"/*.yaml; do
  [[ -e "$path" ]] || continue
  base="$(basename "$path")"
  file_fail=0
  if [[ -n "${R_MODE[$base]:-}" ]]; then
    mode="${R_MODE[$base]}"
    if [[ "$mode" == "exempt" ]]; then
      n_exempt=$((n_exempt+1))
      printf '  [OK]   exempt: %s — %s\n' "$base" "${R_SSOT[$base]}"
      continue
    fi
    ssot="${R_SSOT[$base]}"
    def_mode="${D_MODE[$base]:-}"
    if [[ -z "$def_mode" ]]; then
      pfail "def-unregistered: '$base' が DEF_REGISTRY 未登録 (glossary[].def の扱いを strict/local で明示批准して登録)"
    fi
    yq -o=json '.' "$path" > "$TMP/src.json" 2>/dev/null \
      || { pfail "yaml-parse-error: $base"; continue; }
    gtype="$(jq -r '.glossary | if . == null then "null" else type end' "$TMP/src.json")"
    if [[ "$gtype" != "array" && "$gtype" != "null" ]]; then
      pfail "malformed-glossary: glossary 節が配列でない ($gtype): $base"; continue
    fi
    # ★C0 制御文字 (改行/tab 等) を含む term/en は malformed (肯定形 invariant・SSoT 側と同基準)。
    #   改行入り値は行指向 record を分割し、intersect で drift が local へ silent 再分類される fail-open を
    #   作った (ceiling wf_40306116 が実弾捕捉・V14 回帰 pin)。下の NUL framing と二段で閉塞する。
    nctl="$(jq '[.glossary // [] | .[] | select(type == "object") | select(((((.term // "") | tostring) + ((.en // "") | tostring)) | explode | map(select(. < 32)) | length) > 0)] | length' "$TMP/src.json")"
    [[ "$nctl" == "0" ]] || pfail "malformed-entry: term/en に制御文字 (C0) $nctl 件 in $base"
    # source 内の term 重複 = 同語の en が 2 通り書けてしまう (parity の一意性が壊れる)
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      pfail "source-dup term='$d' in $base"
    done < <(jq -r '.glossary // [] | .[] | if type == "object" then ((.term // "") | tostring) else "" end' "$TMP/src.json" | grep -v '^$' | sort | uniq -d)
    # (term, en) ↔ SSoT (canonical, en) 突合。 ★field 区切り = US (\x1f): tab は whitespace IFS ゆえ
    # 空フィールド (en="" 等) が read で潰れて誤分類する (V11 回帰 pin)。 ★record 区切り = NUL (-d ''):
    # 改行区切りだと値中の埋め込み改行が record を分割し、intersect で drift が local へ silent 再分類
    # される fail-open になる (ceiling wf_40306116 実弾・V14 回帰 pin)。 US/NUL とも YAML 値に出現不能。
    checked=0; local_cnt=0; def_checked=0
    while IFS=$'\x1f' read -r -d '' term en present ssot_en def ssot_def; do
      if [[ -z "$term" ]]; then pfail "malformed-entry: term 空 or 非 object entry in $base"; continue; fi
      # ★present の domain 検査: jq が emit する正値は "0"/"1" のみ。それ以外 = 抽出異常 (jq 死の
      #   sentinel record / 万一の frame 破れ) を clean 扱いしない (machinery 失敗 ≠ 緑・mzn.1 教訓)。
      if [[ "$present" != "0" && "$present" != "1" ]]; then
        pfail "record-frame-error: present 値が 0/1 でない ('$present') term='$term' in $base"; continue
      fi
      if [[ "$present" == "1" ]]; then
        checked=$((checked+1))
        if [[ -z "$en" ]]; then pfail "malformed-entry: en 空 term='$term' in $base"
        elif [[ "$en" != "$ssot_en" ]]; then
          pfail "en-drift term='$term' in $base: source='$en' / ssot='$ssot_en' ($ssot)"
        fi
        # ★def-parity (strict のみ): SSoT 収録語の def は SSoT formal_def と逐語一致 (定義の 5 番目の複製を pin)。
        #   空 def / 空 formal_def は「一致」が vacuous に成立するため個別に FAIL (恒真 PASS の封鎖)。
        if [[ "$def_mode" == "strict" ]]; then
          def_checked=$((def_checked+1))
          if [[ -z "$def" ]]; then pfail "glossary-def-empty term='$term' in $base (strict は def 必須)"
          elif [[ -z "$ssot_def" ]]; then
            pfail "ssot-def-empty term='$term' in $ssot (SSoT formal_def 空 = def 逐語一致が vacuous)"
          elif [[ "$def" != "$ssot_def" ]]; then
            pfail "glossary-def-drift term='$term' in $base: source=$(printf '%q' "$def") / ssot=$(printf '%q' "$ssot_def") ($ssot)"
          fi
        fi
      else
        if [[ "$mode" == "full" ]]; then
          pfail "ssot-missing term='$term' in $base ($ssot 未収録・full mode は全語収録が不変条件)"
        else local_cnt=$((local_cnt+1)); fi
      fi
    done < <(jq -j --slurpfile ssot "$TMP/map-$ssot.json" --slurpfile sdef "$TMP/defmap-$ssot.json" '
      .glossary // [] | .[] as $g | ($g | if type == "object" then . else {} end) as $o
      | (($o.term // "") | tostring) as $t | (($o.en // "") | tostring) as $e
      | (($o.def // "") | tostring) as $d
      | ([$t, $e, (if ($ssot[0] | has($t)) then "1" else "0" end), ($ssot[0][$t] // ""), $d, ($sdef[0][$t] // "")] | join("\u001f")) + "\u0000"' "$TMP/src.json" || printf 'jq-extract-error\x1f\x1f!\x1f\x1f\x1f\x00')
    terms_checked=$((terms_checked+checked)); n_local=$((n_local+local_cnt)); defs_checked=$((defs_checked+def_checked))
    if [[ "$mode" == "full" ]]; then n_full=$((n_full+1)); else n_intersect=$((n_intersect+1)); fi
    [[ "$file_fail" == "0" ]] && printf '  [OK]   parity(%s/def:%s): %s (en 突合 %d 語 / def 逐語 %d 語 / anchor 外 local %d 語)\n' "$mode" "${def_mode:-未登録}" "$base" "$checked" "$def_checked" "$local_cnt"
  else
    # 未登録 contract: 非空 (or 非配列) glossary 節 = default-block (分類漏れを素通りさせない)
    glen="$(yq -o=json '.' "$path" 2>/dev/null | jq -r '.glossary | if . == null then 0 elif type == "array" then length else -1 end' 2>/dev/null || echo -1)"
    if [[ "$glen" == "0" ]]; then
      n_unreg_empty=$((n_unreg_empty+1))
      printf '  [OK]   未登録 (glossary 空): %s\n' "$base"
    else
      pfail "unregistered-contract: 非空 glossary 節を持つ未登録 contract: $base (PARITY_REGISTRY へ mode を明示批准して登録)"
    fi
  fi
done

echo ""
echo "  分類: full=$n_full intersect=$n_intersect exempt=$n_exempt 未登録空=$n_unreg_empty / vocab projection $n_mirror 本 / en 突合 $terms_checked 語・anchor 外 local $n_local 語・def 逐語 $defs_checked 語"
if [[ "$fail" == "0" ]]; then
  echo "RESULT: glossary-parity PASS (source (term,en) = glossary SSoT (canonical,en) 逐語一致・strict file の def 逐語一致・分類完結・vocab projection byte 一致)"
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
