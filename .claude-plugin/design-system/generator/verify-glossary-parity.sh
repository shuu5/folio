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
# 実行: admin gate funnel (contract 変更の land 前) + test-adversarial-glossary-parity.sh。 CI 非配線
# (ローカル gate・verify-cross-doc-dup と同格の cross-contract lint)。 HTML は読まない (contract↔contract)。
#
# 用法: verify-glossary-parity.sh [--contract-dir <dir>]
# exit: 0 = 全緑 / 1 = parity 違反・分類漏れ・anchor 崩壊 / 2 = 構成エラー (SSoT 不在・依存欠落・未知引数)
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$SCRIPT_DIR/contract"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract-dir) CONTRACT_DIR="$2"; shift 2 ;;
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
  [[ "$file_fail" == "0" ]] && printf '  [OK]   anchor: %s (%s 語)\n' "$s" "$(jq 'length' "$TMP/map-$s.json")"
done

# ===== 2. registry rot (登録済 file の実在 = fail-loud) =====
for rf in "${!R_MODE[@]}"; do
  [[ -f "$CONTRACT_DIR/$rf" ]] || pfail "registry-missing-file: 登録済 contract 不在: $rf"
done

# ===== 3. sweep + per-file parity (contract/*.yaml 全数分類 = 完結性 sweep) =====
n_full=0; n_intersect=0; n_exempt=0; n_unreg_empty=0; terms_checked=0; n_local=0
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
    checked=0; local_cnt=0
    while IFS=$'\x1f' read -r -d '' term en present ssot_en; do
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
      else
        if [[ "$mode" == "full" ]]; then
          pfail "ssot-missing term='$term' in $base ($ssot 未収録・full mode は全語収録が不変条件)"
        else local_cnt=$((local_cnt+1)); fi
      fi
    done < <(jq -j --slurpfile ssot "$TMP/map-$ssot.json" '
      .glossary // [] | .[] as $g | ($g | if type == "object" then . else {} end) as $o
      | (($o.term // "") | tostring) as $t | (($o.en // "") | tostring) as $e
      | ([$t, $e, (if ($ssot[0] | has($t)) then "1" else "0" end), ($ssot[0][$t] // "")] | join("\u001f")) + "\u0000"' "$TMP/src.json" || printf 'jq-extract-error\x1f\x1f!\x1f\x00')
    terms_checked=$((terms_checked+checked)); n_local=$((n_local+local_cnt))
    if [[ "$mode" == "full" ]]; then n_full=$((n_full+1)); else n_intersect=$((n_intersect+1)); fi
    [[ "$file_fail" == "0" ]] && printf '  [OK]   parity(%s): %s (en 突合 %d 語 / anchor 外 local %d 語)\n' "$mode" "$base" "$checked" "$local_cnt"
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
echo "  分類: full=$n_full intersect=$n_intersect exempt=$n_exempt 未登録空=$n_unreg_empty / en 突合 $terms_checked 語・anchor 外 local $n_local 語"
if [[ "$fail" == "0" ]]; then
  echo "RESULT: glossary-parity PASS (source (term,en) = glossary SSoT (canonical,en) 逐語一致・分類完結)"
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
