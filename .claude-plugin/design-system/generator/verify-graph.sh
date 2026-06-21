#!/usr/bin/env bash
# folio engine B5-I (folio-p4o) — 照会 graph 終端完備検証 (rolemap floor + reachability)
#
# engine doc §10③④⑦ の実機構。 独立 script (既存 core 不変・graph traversal を core に持ち込まない §10④)。
# contract/ を glob し 2 段で検証する:
#   (1) rolemap floor (scope = 各 contract): edge.role == rolemap[node.type] を pin (co-author + enforce・二重担保)、
#       rolemap roles ⊆ 抽象 allowlist、 SRS exploration 不在 scan (forbidden_roles)。  → 違反 = hard FAIL
#   (2) graph reachability (global): contract glob → edge union → principle 終端への到達可能性を
#       {終端完備 / 孤立 = warn / external-ref = warn} に展開。 dangling 照会 (graph 不在 node 先) = hard FAIL。
#       amended_by は来歴 meta-edge ゆえ reachability から除外 (rolemap external.meta=true)。
#
# 決定的 → floor (CI hard = guarantee)・意味的 → ceiling (advisory) の二分 (engine doc §10⑦):
#   graph 構造は有限ゆえ floor が *例外的に exhaustive* (folio の「floor は検査できた範囲だけ green」が当てはまらない稀領域)。
#   照会 note / role の *真正性* は意味判定ゆえ ceiling = 既存 fidelity-* lens に委ねる (本 script の射程外)。
# 孤立 = warn は engine doc 確定 (follow-up: ADR-less 孤立 SRS の warn→block 昇格 policy)。 exit code:
#   floor 違反 / dangling 有 → 1。 warn のみ (孤立 / external-ref) → 0 (advisory)。
#
# 用法: verify-graph.sh [--contract-dir <dir>] [--rolemap-dir <dir>]
#   既定 contract-dir = <script>/contract、 rolemap-dir = <script>/rolemap。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$SCRIPT_DIR/contract"
ROLEMAP_DIR="$SCRIPT_DIR/rolemap"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract-dir) CONTRACT_DIR="$2"; shift 2 ;;
    --rolemap-dir)  ROLEMAP_DIR="$2";  shift 2 ;;
    *) echo "verify-graph: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

# 照会 edge を本来持たない (片方向/終端) pack の allowlist。 これ以外の pack は edges を
# 必ず 1 件以上宣言しなければならない (期待値駆動の floor 武装解除ガード):
#   srs      = 片方向 (照会される側・前方照会なし)
#   principle = 照会 graph 終端 (前方照会なし)
# adr (backward justifies) / research (forward leads_to) は edges 必須。 rolemap 側で edges を
# 空に/削除すると necnt=0 で pin ループが 0 回 = corpus edge 無検査になり「二重担保」が無言で解除される。
# その構造的 floor 解除を hard FAIL にする (G2 が roles[] 値改竄を捕捉するのに対し、 本ガードは edges 宣言除去を捕捉)。
GRAPH_EDGELESS_PACKS='srs|principle'

command -v yq >/dev/null || { echo "verify-graph: yq required" >&2; exit 2; }
# core reader (additive 新規 core file) を fail-closed guard (欠落/source 失敗を false-green に倒さない)。
GC="$SCRIPT_DIR/lib/graph-common.sh"
[[ -f "$GC" ]] || { echo "verify-graph: lib/graph-common.sh not found" >&2; exit 2; }
source "$GC" || { echo "verify-graph: failed to source graph-common.sh" >&2; exit 2; }
# chk/chk_empty 整形 + $fail を共用 (既存 core 不変・source のみ)。
LVC="$SCRIPT_DIR/lib/verify-common.sh"
[[ -f "$LVC" ]] || { echo "verify-graph: lib/verify-common.sh not found" >&2; exit 2; }
CHKW=58; source "$LVC" || { echo "verify-graph: failed to source verify-common.sh" >&2; exit 2; }

fail=0
declare -i nwarn=0
WARNS=()
warnmsg() { WARNS+=("$1"); nwarn+=1; }

# 語彙 SSoT 整合 (両 lib source 時のみ): graph allowlist == cross-doc allowlist を fail-closed で照合。
graph_role_vocab_consistent || { echo "  [FAIL] role allowlist 語彙が graph-common と verify-common で不一致 (drift)"; fail=1; }

[[ -d "$CONTRACT_DIR" ]] || { echo "verify-graph: contract-dir 不在: $CONTRACT_DIR" >&2; exit 2; }
[[ -d "$ROLEMAP_DIR"  ]] || { echo "verify-graph: rolemap-dir 不在: $ROLEMAP_DIR" >&2; exit 2; }
mapfile -t CONTRACTS < <(find "$CONTRACT_DIR" -maxdepth 1 -name '*.yaml' | sort)
[[ "${#CONTRACTS[@]}" -gt 0 ]] || { echo "verify-graph: contract 0 件: $CONTRACT_DIR" >&2; exit 2; }

echo "照会 graph 終端完備検証 (rolemap floor + reachability): $CONTRACT_DIR"

declare -A ISDOC DOCPACK TERMINAL
DOCIDS=()           # 決定的順 (sort 済 contract 由来) の doc_id 列
EDGES=()            # "src|dst|direction|cbase|from_node" (graph reachability 用・dst は doc_id か terminal id)
EXTREFS=()          # external-ref warn 行

# ===== pass 1: rolemap floor + node/terminal/edge 収集 (scope = 各 contract) =====
for CONTRACT in "${CONTRACTS[@]}"; do
  cbase="${CONTRACT##*/}"
  pack="$(graph_pack_of "$CONTRACT")"
  rolemap="$ROLEMAP_DIR/$pack.rolemap.yaml"
  if [[ ! -f "$rolemap" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s rolemap 不在: %s\n' "$cbase ($pack)" "$rolemap"; fail=1; continue
  fi
  did="$(yq -r '.meta.doc_id // ""' "$CONTRACT")"
  if [[ -z "$did" || "$did" == "null" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s .meta.doc_id 欠落\n' "$cbase"; fail=1; continue
  fi
  if [[ -n "${ISDOC[$did]:-}" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s doc_id 重複: %s\n' "$cbase" "$did"; fail=1; continue
  fi
  ISDOC[$did]=1; DOCPACK[$did]="$pack"; DOCIDS+=("$did")

  # (sanity) rolemap roles ⊆ 抽象 allowlist
  bad="$(rolemap_roles_invalid "$rolemap" | tr '\n' ' ' | sed 's/ *$//')"
  chk_empty "$cbase: rolemap roles ⊆ 抽象 allowlist" "$bad"

  # (floor) edges: edge.role == roles[from_node] を pin (二重担保: rolemap 宣言 ∩ corpus edge)
  necnt="$(yq -r '.edges // [] | length' "$rolemap")"
  # (floor) edges 武装解除ガード: edge を本来持つ pack (allowlist 外) で edges が空/削除 = pin が無検査になる
  # 構造的 floor 解除。 期待値 (この pack は edge を持つべきか否か) と宣言実態 (necnt>0?) の不一致を hard FAIL。
  # 期待 = present/absent を string 化し既存 chk で照合 (新 helper 不要 = core byte-identity 維持)。
  if printf '%s' "$pack" | grep -qxE "$GRAPH_EDGELESS_PACKS"; then
    chk "$cbase: edgeless pack ($pack) は edges 宣言なし (片方向/終端)" "edges:absent" \
      "$([[ "$necnt" -gt 0 ]] && echo "edges:present" || echo "edges:absent")"
  else
    chk "$cbase: edge-bearing pack ($pack) は edges を 1 件以上宣言 (floor 武装解除ガード)" "edges:present" \
      "$([[ "$necnt" -gt 0 ]] && echo "edges:present" || echo "edges:absent")"
  fi
  for ((i=0; i<necnt; i++)); do
    fn="$(yq -r ".edges[$i].from_node" "$rolemap")"
    rexpr="$(yq -r ".edges[$i].role_expr" "$rolemap")"
    cexpr="$(yq -r ".edges[$i].count_expr" "$rolemap")"
    texpr="$(yq -r ".edges[$i].target_docid_expr" "$rolemap")"
    dir="$(yq -r ".edges[$i].direction" "$rolemap")"
    if ! exp="$(rolemap_role_for "$rolemap" "$fn")"; then
      printf '  [FAIL] %-'"$CHKW"'s rolemap roles[%s] 未定義 (edge from_node)\n' "$cbase" "$fn"; fail=1; continue
    fi
    printf '%s' "$exp" | grep -qxE "$GRAPH_ROLE_ALLOWLIST" \
      || { printf '  [FAIL] %-'"$CHKW"'s edge 期待 role %s が allowlist 外\n' "$cbase" "$exp"; fail=1; }
    [[ "$dir" == "forward" || "$dir" == "backward" ]] \
      || { printf '  [FAIL] %-'"$CHKW"'s edge[%s] direction 不正: %s\n' "$cbase" "$fn" "$dir"; fail=1; }
    declared_cnt="$(yq -r "$cexpr" "$CONTRACT")"
    mapfile -t eroles < <(yq -r "$rexpr" "$CONTRACT")
    tgt="$(yq -r "$texpr" "$CONTRACT")"
    chk "$cbase: edge[$fn] role 件数 == |edges|" "$declared_cnt" "${#eroles[@]}"
    # ★vacuum ガード (folio-p4o cell-quality minor #3 = 武装解除の兄弟ベクタ): rolemap の role_expr/count_expr を
    #   *協調的に* vacuous (存在しない path) へ書き換えると declared_cnt=0 かつ |eroles|=0 で件数が一致し、 pin が
    #   0 回照合 = corpus role-swap が素通る (G11 の edges 削除と同クラスの fail-open・別ベクタ)。 照会先 doc_id
    #   (target_docid_expr) は別 expr ゆえ vacuum の巻き添えにならず有効なまま残る。 「有効な照会先があるのに
    #   edge 0 件」= role/count expr の vacuum 署名ゆえ hard FAIL (target 有効 ⟹ declared_cnt が正整数 を pin)。
    #   declared_cnt が null/非数値 (cexpr 自体の vacuum) も正整数でないゆえ false で捕捉する。
    if [[ -n "$tgt" && "$tgt" != "null" ]]; then
      chk "$cbase: edge[$fn] 有効照会先 ⟹ role/count expr 非vacuum (declared_cnt 正整数)" "true" \
        "$([[ "$declared_cnt" =~ ^[1-9][0-9]*$ ]] && echo true || echo false)"
    fi
    mism=""
    for rr in "${eroles[@]}"; do [[ "$rr" == "$exp" ]] || mism+=" '$rr'"; done
    chk_empty "$cbase: edge[$fn] role 全件 == rolemap[$fn]=$exp (pin)" "${mism# }"
    # graph edge 収集 (dangling は pass 2)。 target doc_id は edge ごとに 1 つ (cross_doc.*_doc_id)。
    if [[ -z "$tgt" || "$tgt" == "null" ]]; then
      printf '  [FAIL] %-'"$CHKW"'s edge[%s] 照会先 doc_id が空\n' "$cbase" "$fn"; fail=1
    else
      EDGES+=("$did|$tgt|$dir|$cbase|$fn")
    fi
  done

  # (floor) forbidden_roles: この pack に存在してはならない role を scan で実証 (rolemap 宣言 ∩ corpus 不在)。
  mapfile -t forb < <(yq -r '.forbidden_roles // [] | .[]' "$rolemap")
  for fr in "${forb[@]}"; do
    [[ -n "$fr" ]] || continue
    # (a) rolemap 自身が forbidden role を roles に持たない (宣言整合)。
    rmhit="$(yq -r '.roles // {} | to_entries | .[].value' "$rolemap" | grep -xc "$fr" || true)"
    chk "$cbase: rolemap に forbidden role '$fr' 不在" "0" "$rmhit"
    # (b) corpus 側: forbidden role が contract のどこにも現れない (cross-doc edge / 任意 .role 値)。
    #     SRS は cross-doc edge を持たない (片方向) ゆえ corpus 全域から '..role: exploration' 相当を scan。
    chit="$(yq -r '.. | select(tag == "!!map") | .role? // ""' "$CONTRACT" 2>/dev/null | grep -xc "$fr" || true)"
    chk "$cbase: corpus に forbidden role '$fr' 不在 (scan 実証)" "0" "$chit"
  done

  # (graph) terminal node 収集 + doc→terminal edge。
  tid_expr="$(yq -r '.terminal.id_expr // ""' "$rolemap")"
  if [[ -n "$tid_expr" && "$tid_expr" != "null" ]]; then
    tid="$(yq -r "$tid_expr" "$CONTRACT")"
    if [[ -n "$tid" && "$tid" != "null" ]]; then
      TERMINAL[$tid]=1
      # constitution は doc 自身が終端 (tid==did) ゆえ self-edge は張らない。 ADR inline は doc→終端 edge。
      [[ "$tid" == "$did" ]] || EDGES+=("$did|$tid|forward|$cbase|terminal")
    else
      warnmsg "$cbase: terminal.id ($tid_expr) が空 — この doc は照会終端を持たない (孤立化しうる)"
    fi
  fi

  # (graph) external-ref (contract外 folio-self) 収集 = warn。 reachability には使わない (受ける/来歴照会)。
  next="$(yq -r '.external // [] | length' "$rolemap")"
  for ((j=0; j<next; j++)); do
    edesc="$(yq -r ".external[$j].desc" "$rolemap")"
    erexpr="$(yq -r ".external[$j].ref_expr" "$rolemap")"
    while IFS= read -r ref; do
      [[ -n "$ref" && "$ref" != "null" ]] || continue
      EXTREFS+=("$cbase: $edesc → $ref (contract外・B6 で実在/reverse 解決)")
    done < <(yq -r "$erexpr" "$CONTRACT" 2>/dev/null)
  done
done

# ===== pass 2: dangling 検査 + reachability adjacency 構築 =====
declare -A ADJ
for e in "${EDGES[@]}"; do
  IFS='|' read -r src tgt dir cb fn <<< "$e"
  if [[ -z "${ISDOC[$tgt]:-}" && -z "${TERMINAL[$tgt]:-}" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s dangling 照会: edge[%s] 先 %s が graph に不在\n' "$cb" "$fn" "$tgt"; fail=1; continue
  fi
  if [[ "$dir" == "backward" ]]; then
    ADJ[$tgt]="${ADJ[$tgt]:-} $src"   # toward-terminal = 逆 (tgt → src)
  else
    ADJ[$src]="${ADJ[$src]:-} $tgt"   # toward-terminal = 順 (src → tgt)
  fi
done

# reaches_terminal <node> : node から toward-terminal edge を辿り TERMINAL に到達できれば 0。
reaches_terminal() {
  local start="$1" cur nb; local -A seen; local -a queue=("$start")
  while [[ "${#queue[@]}" -gt 0 ]]; do
    cur="${queue[0]}"; queue=("${queue[@]:1}")
    [[ -z "${seen[$cur]:-}" ]] || continue
    seen[$cur]=1
    [[ -z "${TERMINAL[$cur]:-}" ]] || return 0
    for nb in ${ADJ[$cur]:-}; do [[ -n "${seen[$nb]:-}" ]] || queue+=("$nb"); done
  done
  return 1
}

# ===== reachability 展開 ({終端完備 / 孤立=warn}) =====
declare -i ncomplete=0 nisolated=0
for did in "${DOCIDS[@]}"; do
  if reaches_terminal "$did"; then
    printf '  [OK]   %-'"$CHKW"'s 終端完備\n' "終端到達: $did (${DOCPACK[$did]})"
    ncomplete+=1
  else
    warnmsg "孤立: $did (${DOCPACK[$did]}) — principle 終端へ到達不能"
    nisolated+=1
  fi
done

# ===== warn 出力 (external-ref を sort -u で重複畳み・孤立/terminal warn と合算) =====
if [[ "${#EXTREFS[@]}" -gt 0 ]]; then
  while IFS= read -r line; do warnmsg "$line"; done < <(printf '%s\n' "${EXTREFS[@]}" | sort -u)
fi
if [[ "${#WARNS[@]}" -gt 0 ]]; then
  printf '%s\n' "${WARNS[@]}" | sort | while IFS= read -r w; do printf '  [WARN] %s\n' "$w"; done
fi

echo "  ----"
printf '  終端完備=%d 孤立(warn)=%d warn合計=%d\n' "$ncomplete" "$nisolated" "$nwarn"
if [[ "$fail" -ne 0 ]]; then
  echo "  RESULT: FAIL (floor 違反 / dangling)"
  exit 1
fi
echo "  RESULT: FLOOR-OK (warn は advisory・graph ceiling = 既存 fidelity-* lens の射程)"
exit 0
