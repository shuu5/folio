#!/usr/bin/env bash
# census-guard.sh — 数字上書き防壁 (folio-7n17 / ADR-0053 政策 A・deliverable 7)。
#
# ★目的 (recursive-ceiling・散文規約では不足): frozen census (spec-origin/verification.frozen-census.txt) の
#   ★裸の数字変更 (契約変更を伴わない census bump = 退行 launder) を fail-closed で弾く。 census は canonical /
#   artifact / 生成物から【導出しない】凍結 literal ゆえ、 「31→30」と書き換えるだけで verify を緑化できてしまう。
#   本 gate は census 値の変更を ★対応する contract 変更に構造的に連結し、 裸の書き換えを FAIL にする。
#
# ★2 層 (どちらも worker cell 内 bash/git で決定的):
#   (1) provenance sha 整合: census header の provenance_contract_sha256 == 現 contract の sha256。
#       contract を変えたのに census を re-freeze しない (provenance 未更新) → FAIL。 逆に、 census を
#       re-freeze するときは必ず provenance sha を現 contract へ書き直す規律を強制する。
#   (2) git-diff coupling (base ref 必須): census file が base から【MODIFIED】(値変更) なのに contract が
#       base から未変更なら FAIL (裸の census bump)。 census が【ADDED】(初回 freeze) の場合は coupling を課さない
#       (初回確立は contract 変更を伴わないのが正常)。 これにより「既存 frozen 値を黙って書き換える」将来の
#       edit を弾く (初回 freeze は素通す)。
#
# ★spec 名引数化 (folio-7wbn / admin 裁定 案X): 単一実装を per-spec 呼出しで使い回す (fork = 二重保守ゆえ不採択)。
#   {census, contract} の ★両方 を per-spec に解決し、 (1) provenance / (2) coupling を ★その spec の census file に
#   対して課す。 片側 spec のみ検査する形は他 spec の naked bump を素通す fail-open ゆえ、 CI は per-spec step で
#   全 spec 分を回す (ci.yml 配線 = admin Leg B)。 registry 粒度の設計 (対象 spec 一覧の自動導出) は別 bead
#   folio-vhew の領分で、 本 script は「引数化 + 既知 spec の解決」の最小汎化に留める。
#
# usage: census-guard.sh [<spec-name>] [<base-ref>]
#   spec-name 省略時は verification (後方互換の既定)。 base-ref 省略時は coupling 検査 (2) を skip し
#   provenance 整合 (1) のみ実施 (git 文脈非依存の最小 gate)。
# exit:  0 = PASS / 1 = FAIL (裸の census 変更 or provenance drift) / 2 = tool/前提エラー
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ★後方互換: 第 1 引数が既知 spec 名でなければ base-ref とみなす (旧 `census-guard.sh <base-ref>` 呼出しを壊さない)。
KNOWN_SPECS=" verification rules "
SPEC="verification"
if [[ -n "${1:-}" && "$KNOWN_SPECS" == *" $1 "* ]]; then SPEC="$1"; shift; fi
CENSUS="$SCRIPT_DIR/spec-origin/$SPEC.frozen-census.txt"
CONTRACT="$SCRIPT_DIR/contract/folio-$SPEC.spec.yaml"
BASE_REF="${1:-}"
echo "census-guard: spec=$SPEC (census=$(basename "$CENSUS") / contract=$(basename "$CONTRACT"))"
[[ -f "$CENSUS" ]]   || { echo "census-guard: frozen census 不在: $CENSUS" >&2; exit 2; }
[[ -f "$CONTRACT" ]] || { echo "census-guard: contract 不在: $CONTRACT" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "census-guard: sha256sum required" >&2; exit 2; }

fail=0

# (1) provenance sha 整合。
declared="$(grep -m1 'provenance_contract_sha256' "$CENSUS" | sed -E 's/.*provenance_contract_sha256[[:space:]]*=[[:space:]]*//' | tr -d ' ')"
actual="$(sha256sum "$CONTRACT" | cut -d' ' -f1)"
if [[ -z "$declared" ]]; then
  echo "  [FAIL] census-guard (1) provenance_contract_sha256 header 不在 (freeze 規律違反)"; fail=1
elif [[ "$declared" != "$actual" ]]; then
  echo "  [FAIL] census-guard (1) provenance sha drift: header=$declared != 現 contract=$actual"
  echo "         → contract を変えたら census を re-freeze し provenance_contract_sha256 を現 contract sha へ更新すること。"
  fail=1
else
  echo "  [OK]   census-guard (1) provenance sha 整合 (census は現 contract に対し freeze 済)"
fi

# (2) git-diff coupling (base ref 指定時のみ)。
if [[ -n "$BASE_REF" ]]; then
  if ! git -C "$SCRIPT_DIR" rev-parse --verify "$BASE_REF^{commit}" >/dev/null 2>&1; then
    echo "  [FAIL] census-guard (2) base-ref 解決不能: $BASE_REF"; fail=1
  else
    # ★pathspec は絶対 path を渡す (git は絶対 pathspec を受理し repo-relative name を返す)。 相対 path を
    #   git -C "$SCRIPT_DIR" に渡すと git は pathspec を CWD(=SCRIPT_DIR)相対へ解決し常に空 → 恒常 vacuous
    #   (coupling 対象外) で naked census bump を素通す fail-open になる (folio-7n17 self-review 実証)。
    status="$(git -C "$SCRIPT_DIR" diff --name-status "$BASE_REF" -- "$CENSUS" | awk '{print $1}' | head -1)"
    contract_changed="$(git -C "$SCRIPT_DIR" diff --name-only "$BASE_REF" -- "$CONTRACT" | grep -c . || true)"
    case "$status" in
      "")   echo "  [OK]   census-guard (2) census file は base から未変更 (coupling 対象外)";;
      A|A*) echo "  [OK]   census-guard (2) census file は ADDED (初回 freeze・coupling 課さない)";;
      M|M*|R*)
        if [[ "$contract_changed" -gt 0 ]]; then
          echo "  [OK]   census-guard (2) census MODIFIED だが contract も変更あり (連結成立)"
        else
          echo "  [FAIL] census-guard (2) ★裸の census 変更: census file が base から MODIFIED なのに contract 未変更"
          echo "         → frozen 値の書き換えは対応する contract 変更を伴うこと (退行 launder 封鎖)。"
          fail=1
        fi;;
      *)    echo "  [FAIL] census-guard (2) 未知の git status: $status"; fail=1;;
    esac
  fi
else
  echo "  [SKIP] census-guard (2) coupling は base-ref 未指定ゆえ skip (provenance 整合のみ)"
fi

# (3) ★未保護 census の loud 開示 (folio-7wbn 3 巡目 ceiling major fix)。
#   本 script は 1 実行につき ★1 spec しか検査しない。 CI が per-spec step 化されるまで (Leg B・ci.yml は
#   folio-7wbn cell の禁止面)、 現行の 1 引数呼出し `census-guard.sh <base-sha>` は第 1 引数が既知 spec 名でないため
#   ★verification へ黙って解決され、 spec-origin/ に増えた他の census file (rules 等) は provenance も coupling も
#   ★一度も評価されない = 数字上書き防壁が届かない fail-open。 「census を足したが guard 呼出しに載せ忘れる」を
#   ★沈黙させない ために、 ディレクトリ走査 (列挙でなく実在 file が SSOT) で今回の検査対象外を必ず名指しする。
#   ★exit code は変えない (fail-closed 化は Leg B 未着地の CI を即赤にするため admin 裁定が前提・恒久形は
#   folio-vhew の registry 導出で「全 census を必ず検査する」形へ寄せる)。
unchecked=()
for f in "$SCRIPT_DIR"/spec-origin/*.frozen-census.txt; do
  [[ -e "$f" ]] || continue
  [[ "$f" == "$CENSUS" ]] && continue
  unchecked+=("$(basename "$f")")
done
if [[ "${#unchecked[@]}" -gt 0 ]]; then
  echo "  [WARN] census-guard (3) ★本実行で未検査の census file が ${#unchecked[@]} 本ある (この実行は spec=$SPEC のみ):" >&2
  for u in "${unchecked[@]}"; do echo "         - $u ← provenance / coupling ★未評価 (裸 bump が素通る)" >&2; done
  echo "         → CI を per-spec step 化し全 census を検査すること (例: census-guard.sh rules <base-sha>)。" >&2
fi

if [[ "$fail" -eq 0 ]]; then echo "census-guard: PASS"; exit 0; else echo "census-guard: FAIL"; exit 1; fi
