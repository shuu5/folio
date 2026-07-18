#!/usr/bin/env bash
# folio 文書規律エンジン (folio-og3g) — spec-pack 要件層 recapture parity gate (cross-layer lint・fail-closed)
#
# 原本 spec HTML (design-intent/spec/*.html・folio-architect が管理する hand-authored SSoT) の要件 record
# anchor (<details class="spec-row" id="req-...">) と、 spec-pack contract の requirements[].id の
# **集合一致** を検査する。 folio-og3g の実測: nufl recapture 後に原本は REQ-VER-027/028/029 を持つが
# contract は 026 で打ち止め = contract から presentation を再生成すると要件 3 本が原本比で欠落していた。
# この「原本↔contract の要件層 drift」を検査する gate が皆無だった穴の機構化。
#
# 検査は id 集合の一致のみ = machine/LLM 境界の機械側 (集合/件数照合・意味判定なし)。 集合一致は
# 裁定済み最小形「anchor 数 == 件数」を包含する同コストの強化 (renumber drift も捕捉・欠落 id を名指し報告)。
# ★record *内容* (essence/statement の逐語一致) は本 gate の scope 外 — 内容 fidelity は
#   verify-verification §11 round-trip (machine prose) + ceiling (fidelity-spec) の領分。
#
# ★fail-closed 設計 (dvsk と同 idiom):
#   - RECAPTURE_REGISTRY が spec-pack contract の分類 SSoT (default-block)。 contract/*.spec.yaml の
#     未登録は FAIL (新 spec contract は原本の明示紐付けなしに素通りできない)。
#   - 原本 anchor 0 本 = selector rot / 構造変更として FAIL (vacuous green 防止)。
#   - anchor 抽出は attribute 順序非依存の perl parse (genuine-shape・bhe 教訓)。
#   - exit は計算済み決定トークン ($fail) のみから導出。
#
# scope 注記: sweep 対象は contract/*.spec.yaml (doc_type=spec = 原本から recapture される唯一の pack)。
# srs/adr 等の requirements は contract 自身が SSoT (原本を持たない) ため対象外。
#
# 実行: admin gate funnel (原本 spec or spec contract 変更の land 前) + test-adversarial-recapture-parity.sh。
# 用法: verify-recapture-parity.sh [--contract-dir <dir>] [--spec-dir <dir>]
# exit: 0 = 全緑 / 1 = parity 違反・分類漏れ / 2 = 構成エラー (依存欠落・dir 不在・未知引数)
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$SCRIPT_DIR/contract"
SPEC_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/design-intent/spec"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract-dir) CONTRACT_DIR="$2"; shift 2 ;;
    --spec-dir)     SPEC_DIR="$2"; shift 2 ;;
    *) echo "verify-recapture-parity: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

command -v yq >/dev/null || { echo "verify-recapture-parity: yq required" >&2; exit 2; }
command -v jq >/dev/null || { echo "verify-recapture-parity: jq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-recapture-parity: perl required" >&2; exit 2; }
[[ -d "$CONTRACT_DIR" ]] || { echo "verify-recapture-parity: contract-dir 不在: $CONTRACT_DIR" >&2; exit 2; }
[[ -d "$SPEC_DIR" ]] || { echo "verify-recapture-parity: spec-dir 不在: $SPEC_DIR" >&2; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
pfail() { printf '  [FAIL] %s\n' "$1"; fail=1; file_fail=1; }

# ===== RECAPTURE_REGISTRY (批准済み紐付けの SSoT・default-block) =====
# 書式: <spec contract file>|<原本 spec HTML (SPEC_DIR 相対)>。 行頭 # はコメント。
# 新しい *.spec.yaml は登録 (原本の明示紐付け) なしでは FAIL する。
RECAPTURE_REGISTRY='
folio-rules.spec.yaml|rules.html
folio-verification.spec.yaml|verification.html
folio-relations.spec.yaml|relations.html
folio-srs-verification.spec.yaml|srs-verification.html
'

declare -A R_SRC
while IFS='|' read -r rf rs; do
  [[ -z "$rf" || "$rf" == \#* ]] && continue
  R_SRC[$rf]="$rs"
done <<< "$RECAPTURE_REGISTRY"

echo "== spec-pack 要件層 recapture parity gate (folio-og3g) =="

# ===== 1. registry rot (登録済 contract の実在 = fail-loud) =====
for rf in "${!R_SRC[@]}"; do
  file_fail=0
  [[ -f "$CONTRACT_DIR/$rf" ]] || pfail "registry-missing-file: 登録済 spec contract 不在: $rf"
done

# ===== 2. sweep + per-contract 集合照合 (contract/*.spec.yaml 全数分類) =====
n_checked=0; n_ids=0
for path in "$CONTRACT_DIR"/*.spec.yaml; do
  [[ -e "$path" ]] || continue
  base="$(basename "$path")"
  file_fail=0
  if [[ -z "${R_SRC[$base]:-}" ]]; then
    pfail "unregistered-contract: 未登録の spec contract: $base (RECAPTURE_REGISTRY へ原本を明示紐付けして登録)"
    continue
  fi
  src="$SPEC_DIR/${R_SRC[$base]}"
  if [[ ! -f "$src" ]]; then
    pfail "genbun-missing: 原本 spec 不在: ${R_SRC[$base]} (contract=$base)"; continue
  fi
  # contract 側 id 列 (非配列 requirements は malformed)
  yq -o=json '.' "$path" > "$TMP/c.json" 2>/dev/null || { pfail "yaml-parse-error: $base"; continue; }
  rtype="$(jq -r '.requirements | if . == null then "null" else type end' "$TMP/c.json")"
  if [[ "$rtype" != "array" ]]; then
    pfail "malformed-requirements: requirements 節が配列でない ($rtype): $base"; continue
  fi
  jq -r '.requirements[] | if type == "object" then ((.id // "") | tostring) else "" end' "$TMP/c.json" > "$TMP/cids"
  if grep -q '^$' "$TMP/cids"; then pfail "malformed-requirements: id 空 or 非 object record in $base"; continue; fi
  # 原本側 anchor 列 (attribute 順序非依存 parse・小文字 anchor を大文字 id へ正規化)
  # ★per-file union の 2 shape (folio-lwhz F6・replace 厳禁 = 一方消すと他方 file が zero-anchors)。
  #   shape 1: <details class="spec-row" id="req-..."> = hand-authored 原本 (rules.html 26 / relations.html 4)。
  #     class は token 完全一致 (空白 split して eq)。 \bspec-row\b の regex 判定は "spec-row-rotted" 等の
  #     派生 class にも部分一致してしまう (- が語境界・bhe genuine-shape 教訓の再演を R7 が捕捉)。
  #   shape 2: <div data-component="ears-requirement-row" id="req-..."> = contract 生成物 (verification.html
  #     flip 後・30 anchor)。 data-component は token 完全一致。 ★<tr data-component="ears-requirement-row">
  #     (SRS pack の dense-table 行・同名別部品) は <div\b 限定ゆえ拾わない (bin/folio:893 と同弁別)。
  perl -CSD -0777 -ne '
    while (/<details\b([^>]*)>/g) {
      my $a = $1;
      my ($cv) = $a =~ /\bclass\s*=\s*"([^"]*)"/; next unless defined $cv;
      next unless grep { $_ eq "spec-row" } split /\s+/, $cv;
      my ($id) = $a =~ /\bid\s*=\s*"(req-[a-z0-9-]+)"/; print "$id\n" if defined $id;
    }
    while (/<div\b([^>]*)>/g) {
      my $a = $1;
      my ($dc) = $a =~ /\bdata-component\s*=\s*"([^"]*)"/; next unless defined $dc;
      next unless $dc eq "ears-requirement-row";
      my ($id) = $a =~ /\bid\s*=\s*"(req-[a-z0-9-]+)"/; print "$id\n" if defined $id;
    }' "$src" | tr '[:lower:]' '[:upper:]' > "$TMP/aids"
  if [[ ! -s "$TMP/aids" ]]; then
    pfail "zero-anchors: 原本に要件 anchor が 0 本 (${R_SRC[$base]}) — selector rot か構造変更 (vacuous green 拒否)"; continue
  fi
  # 両側の重複 = 集合照合の一意性が壊れる
  while IFS= read -r d; do [[ -n "$d" ]] && pfail "dup-id: contract 内 id 重複 '$d' in $base"; done < <(sort "$TMP/cids" | uniq -d)
  while IFS= read -r d; do [[ -n "$d" ]] && pfail "dup-anchor: 原本 anchor 重複 '$d' in ${R_SRC[$base]}"; done < <(sort "$TMP/aids" | uniq -d)
  # 集合一致 (双方向差分を名指しで報告)
  sort -u "$TMP/cids" > "$TMP/cs"; sort -u "$TMP/aids" > "$TMP/as"
  while IFS= read -r d; do [[ -n "$d" ]] && pfail "missing-in-contract: 原本 record '$d' が contract 不在 in $base (recapture 追随漏れ)"; done < <(comm -13 "$TMP/cs" "$TMP/as")
  while IFS= read -r d; do [[ -n "$d" ]] && pfail "missing-in-genbun: contract record '$d' の原本 anchor 不在 in ${R_SRC[$base]} (捏造 or 原本撤去の未追随)"; done < <(comm -23 "$TMP/cs" "$TMP/as")
  n_checked=$((n_checked+1)); cn="$(wc -l < "$TMP/cs")"; n_ids=$((n_ids+cn))
  [[ "$file_fail" == "0" ]] && printf '  [OK]   parity: %s ↔ %s (%d id 集合一致)\n' "$base" "${R_SRC[$base]}" "$cn"
done

echo ""
echo "  照合: contract $n_checked 本 / id $n_ids 件"
if [[ "$fail" == "0" ]]; then
  echo "RESULT: recapture-parity PASS (原本 spec anchor 集合 = contract requirements 集合)"
  exit 0
else echo "RESULT: FAIL"; exit 1; fi
