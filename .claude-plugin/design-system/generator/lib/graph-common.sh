#!/usr/bin/env bash
# folio 文書規律エンジン core (B5-I / folio-p4o) — 照会 graph (抽象ロール graph) の reader ライブラリ
#
# engine doc §10③④ + §3 (照会 = 抽象ロール graph) を実機構化する core リーダー。 pack ごとの
# rolemap (node-type → 抽象ロール写像) を読み、 独立 script verify-graph.sh が
#   (1) floor: scope 内 edge.role == rolemap[node.type] を pin (co-author + enforce・二重担保)
#   (2) graph: principle 終端への到達可能性 (reachability)
# を組み立てるのに使う *純データ reader*。
#
# ★additive 新規 core file: 既存 core 関数 (common.sh / verify-common.sh の verify_cross_doc_refs /
#   inject-prose 等) は byte-identity 非回帰 (engine doc §10.1「core は additive 拡張のみ」)。 graph traversal
#   自体は verify-graph.sh (独立 script) に置き既存 core に持ち込まない (§10④)。 reader は doc-type 非依存ゆえ
#   core に置き、 B6 (folio 自身の横断 graph) へ転用できるよう設計する (§10.2 B6 前払い)。
#
# 前提 (source 側の責務): yq (mikefarah v4) が PATH に在ること。

# 抽象ロール allowlist = 照会 graph のロール語彙 (engine doc §3 表)。 verify-common.sh の
# CROSS_DOC_ROLE_ALLOWLIST と同一語彙だが、 graph 系を verify-common 非依存に単独起動できるよう本 file でも保持する
# (2 箇所定義は語彙 SSoT の重複 = drift 源だが、 値が完全一致する定数ゆえ verify-graph.sh が両 lib を source した際の
#  整合は graph_role_vocab_consistent で機械照合し fail-closed にする)。
GRAPH_ROLE_ALLOWLIST='claim|rationale|exploration|principle|verification|implementation'

# graph_pack_of <contract-path> → pack 名 (srs|adr|research|principle)。
# contract 命名規約 = <instance>.<pack>.yaml ゆえ末尾 .yaml を剥いだ最終 . 区切りが pack。
graph_pack_of() {
  local base="${1##*/}"; base="${base%.yaml}"
  printf '%s' "${base##*.}"
}

# rolemap_role_for <rolemap-file> <node-type> → 抽象ロール (stdout) / fail-closed。
# roles[node-type] が不在・空・"null" なら 非 0 を返し stdout は空 (= 未定義 node-type を false-green に倒さない)。
rolemap_role_for() {
  local r
  # mikefarah yq は jq の --arg 非対応 ゆえ env var を strenv() で注入 (node-type を key lookup)。
  r="$(GRAPH_NT="$2" yq -r '.roles[strenv(GRAPH_NT)] // ""' "$1" 2>/dev/null)" || return 1
  [[ -n "$r" && "$r" != "null" ]] || return 1
  printf '%s' "$r"
}

# rolemap_roles_invalid <rolemap-file> → allowlist 外の role 値を改行区切りで出力 (空 = 健全)。
# rolemap が宣言する全 node intrinsic role が抽象 allowlist に収まることの sanity (rolemap 改竄で
# 未知 role を撒く経路を封鎖)。 roles 不在なら空 (= 健全) を返す。
rolemap_roles_invalid() {
  yq -r '.roles // {} | to_entries | .[].value' "$1" 2>/dev/null \
    | grep -vxE "$GRAPH_ROLE_ALLOWLIST" | grep -v '^$' || true
}

# graph_role_vocab_consistent → 0 if GRAPH_ROLE_ALLOWLIST == CROSS_DOC_ROLE_ALLOWLIST (両 lib source 時のみ意味を持つ)。
# CROSS_DOC_ROLE_ALLOWLIST 未定義 (verify-common.sh 未 source) なら 0 (照合対象なし = vacuously consistent)。
graph_role_vocab_consistent() {
  [[ -z "${CROSS_DOC_ROLE_ALLOWLIST:-}" ]] && return 0
  [[ "$GRAPH_ROLE_ALLOWLIST" == "$CROSS_DOC_ROLE_ALLOWLIST" ]]
}
