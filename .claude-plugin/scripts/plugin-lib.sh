# shellcheck shell=bash
# .claude-plugin/scripts/plugin-lib.sh
# folio Phase X3 試作 plugin — hook script 共通ロジック (shared library)
#
# 3 hook script (check-caller-marker.sh / check-path-boundary.sh /
# check-jsonld-lint.sh) が共有する小関数を集約 (Phase 3 DRY refactor)。
# behavior-preserving: 各 script の現行挙動を厳密保持 (sandbox 26/26 PASS 維持)。
#
# === source 専用 (実行しない) =================================================
# このファイルは関数のみ定義し、 top-level で set / exit / cat 等の副作用を
# 持たない (source 時の副作用ゼロ)。 各 hook script は自身の先頭で
# `set -uo pipefail` を宣言した後に source する:
#     source "$(dirname "${BASH_SOURCE[0]}")/plugin-lib.sh"
#
# === exit する関数に注意 ======================================================
# folio_require_jq / folio_require_write_tool / folio_deny は script を終了
# させる (`exit`)。 command substitution `$(...)` 内で呼ぶと subshell だけが
# 終了して script は継続してしまうため、 必ず文 (statement) として呼ぶこと。
# 一方 folio_spec_path / folio_read_payload / folio_json_field は値を stdout
# に返すだけ (exit しない) なので `$(...)` で呼んでよい。
# folio_under_spec_path / folio_is_html は述語 (return 0/1)、 exit は呼び出し
# 側が `|| exit 0` 等で判断する。

# --- spec_path 正規化 ---------------------------------------------------------
# FOLIO_SPEC_PATH (既定 "architecture/spec/") を読み、 末尾 slash 1 個に正規化して
# stdout に返す。 `${:-}` は unset + empty 両対応 (二重 fallback 不要)。
folio_spec_path() {
  local p="${FOLIO_SPEC_PATH:-architecture/spec/}"
  p="${p%/}/"
  printf '%s' "$p"
}

# --- stdin payload 読込 -------------------------------------------------------
# Claude Code hook の JSON payload を stdin から読み stdout に返す。 空文字は
# 許容 (direct test invocation)。 空判定 + exit 0 は呼び出し側で行う (allow-exit
# を script flow に残す方針):
#     payload=$(folio_read_payload); [[ -z "$payload" ]] && exit 0
folio_read_payload() {
  cat 2>/dev/null || true
}

# --- jq 必須 (fail-closed) ----------------------------------------------------
# jq が PATH に無ければ deny (exit 2)。 $1 = 用途説明 (message に埋め込む)。
# 必須依存欠落で gate が bypass されないことを優先 (fail-closed)。
# ※ exit するため文として呼ぶこと。
folio_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "folio: jq not found in PATH (required for $1, fail-closed)" >&2
  exit 2
}

# --- JSON field 抽出 ----------------------------------------------------------
# $1 = payload (JSON 文字列)、 $2 = jq filter。 jq -r で抽出して stdout に返す。
# jq error は握りつぶす (2>/dev/null)。 不在 key は呼び出し側 filter の
# `// empty` で空文字になる想定。
folio_json_field() {
  printf '%s' "$1" | jq -r "$2" 2>/dev/null
}

# --- spec_path 配下判定 (述語) ------------------------------------------------
# $1 = file_path、 $2 = 正規化済 spec_path (末尾 slash 付き)。 file_path が
# spec_path 配下なら return 0、 そうでなければ return 1。
# case の 2 branch は元 script から verbatim 保持 (挙動不変):
#   "$2"*    = 相対 path (例 "architecture/spec/x.html") の prefix 一致
#   *"/$2"*  = "/spec_path/" を含む path、 特に絶対 path
#              (例 "/repo/architecture/spec/x.html") に対応。 Claude Code は hook の
#              file_path を絶対 path 化するため (v2.1.84~) この branch が必須。
# polarity (allow/deny) は呼び出し側が決める:
#     caller-marker:  folio_under_spec_path "$fp" "$sp" || exit 0   # 配下のみ gate
#     path-boundary:  folio_under_spec_path "$fp" "$sp" && exit 0   # 配下なら allow
folio_under_spec_path() {
  case "$1" in
    "$2"*|*"/$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- .html 拡張子判定 (述語) --------------------------------------------------
# $1 = file_path。 .html なら return 0、 そうでなければ return 1。
folio_is_html() {
  case "$1" in
    *.html) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Write tool 限定 gate (fail-closed) ---------------------------------------
# $1 = tool_name。 path-boundary / jsonld-lint 共通の前段 gate:
#   - tool_name 空 (不正 payload) → deny (exit 2、 fail-closed)
#   - tool_name が Write 以外    → 対象外として allow (exit 0)
#   - Write                      → return 0 (継続)
# ※ exit する (0 or 2) ため文として呼ぶこと。
# 注: caller-marker は Edit|Write|NotebookEdit を独自 case で扱い、 空 tool_name を
#     allow する (現行挙動)。 この非一貫の統一は別 Issue 化 (本 refactor では厳密保持)。
folio_require_write_tool() {
  if [[ -z "$1" ]]; then
    echo "folio: tool_name missing from hook payload (fail-closed)" >&2
    exit 2
  fi
  [[ "$1" == "Write" ]] || exit 0
}

# --- deny 出力 + exit 2 -------------------------------------------------------
# 各引数を 1 行ずつ stderr に出力して exit 2。 PreToolUse では deny、 PostToolUse
# では violation 通知。 ※ exit するため文として呼ぶこと。
folio_deny() {
  printf '%s\n' "$@" >&2
  exit 2
}

# --- JSON-LD 構造 check (共有: per-file hook + batch validate) -----------------
# $1 = 抽出済 JSON-LD block 文字列。 relations.html §3.2 の構造規範を順に check:
#   (1) JSON well-formed (jq parse)
#   (2) 必須 key (@context / @id / @type) 存在
#   (3) @context == object 形式 (旧 string 形式は不可、 空 {} は object なので可)
# clean なら return 0 (無出力)、 違反なら最初の 1 件の reason を stdout に出力して
# return 1 (short-circuit = check-jsonld-lint.sh の現行挙動を厳密保持)。 file path /
# reference 等の文脈は caller が付す (hook は deny message に、 validate は report に)。
# 依存: jq (caller が folio_require_jq 済の前提)。 exit しない (値を返すだけ)。
# ADR-0020 §2.4 DRY: check-jsonld-lint.sh と bin/folio validate が本関数を共用する。
folio_jsonld_structural_check() {
  local block="$1" missing="" key ctx_type
  if ! printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
    printf 'JSON-LD block parse failed (invalid JSON)'
    return 1
  fi
  for key in '@context' '@id' '@type'; do
    if ! printf '%s' "$block" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
      missing="${missing:+$missing, }$key"
    fi
  done
  if [[ -n "$missing" ]]; then
    printf 'required keys missing: %s' "$missing"
    return 1
  fi
  ctx_type=$(printf '%s' "$block" | jq -r '."@context" | type' 2>/dev/null)
  if [[ "$ctx_type" != "object" ]]; then
    printf '@context must be object (new pattern), got %s' "$ctx_type"
    return 1
  fi
  return 0
}

# --- HOW-outside content gate: P-11 4-primitive 検出 (共有: tier2 PreToolUse hook + tier3 validate) ---
# engine 設計 §10 論点⑤⑦ (HOW-outside content gate) floor-2 の検出パターン SSoT。 B5-II が
# bin/folio validate gate (r) に実装した P-11 4-enum 検出を、 B5-III の tier2 content gate hook
# (check-content-boundary.sh = shaping advisory) と共用するため本 lib に集約する (jsonld 構造 check と
# 同じ DRY pattern、 ADR-0020 §2.4)。 validate (tier3 = guarantee) も本関数を呼び behavior-preserving。
#
# $1 = mask 済 visible text (caller が folio_mask_prose + tag 除去で生成)。 P-11 4-primitive を保守的
# 構文検出し "category\ttoken" 行を未 sort で stdout に出す (caller が LC_ALL=C sort -u + 整形)。
#   (1) env-var-value   : 大文字 env-var 名 (>=3) に =値 (NAME=value の具体値、 bare 名は対象外)
#   (2) binary-path     : system binary dir 配下の絶対 path (相対 path 誤検出を境界で抑止)
#   (3) os-command      : 破壊的/OS 固有コマンドのコマンド形 (flag/arg 付き)
#   (4) tool-invocation : 既知 CLI tool 名 + flag 形 (bare 言及でなくコマンド形のみ)
# 「明示 primitive の有無」 は構文判定 (意味判定でない) ゆえ ADR-0028 の精度懸念に当たらない (§10⑤)。
# 検出パターンは bin/folio folio_check_how_primitives の floor-2 と byte-identical に保つ (SSoT = 本関数)。
folio_how_primitive_scan() {
  local text="$1"
  # (1) env var の具体値: 大文字 env-var 名 (>=3 文字) に = と値 (典型 env value 文字に限定 = CJK/括弧で境界) が続く。
  printf '%s\n' "$text" | grep -oE '\b[A-Z][A-Z0-9_]{2,}=[A-Za-z0-9_./:@%+-]+' 2>/dev/null | sed 's/^/env-var-value\t/'
  # (2) binary path: 既知 system binary dir 配下の絶対 path (境界前置文字で相対 path 誤検出を抑止)。
  printf '%s\n' "$text" | grep -oE '(^|[^[:alnum:]_./-])/(usr/local/s?bin|usr/s?bin|s?bin)/[A-Za-z0-9._-]+' 2>/dev/null \
    | grep -oE '/(usr/local/s?bin|usr/s?bin|s?bin)/[A-Za-z0-9._-]+' | sed 's/^/binary-path\t/'
  # (3) OS-specific command: 高シグナルな破壊的/OS 固有コマンドのコマンド形 (flag/arg 付き)。
  printf '%s\n' "$text" | grep -oE '\b(rm -[rf]+|sudo |chmod [0-7ugoa]|chown |apt-get |apt install|brew install|systemctl |kill -9|pkill |mkdir -p|kill-server)' 2>/dev/null | sed 's/^/os-command\t/'
  # (4) 明示 tool 起動: 既知 CLI tool 名 + flag 形 (bare 言及でなくコマンド形のみ。 保守的)。
  printf '%s\n' "$text" | grep -oE '\b(jq|yq|awk|sed|grep|tmux|pnpm|npm|git|node|playwright|docker|kubectl|curl|wget|flock) +-{1,2}[A-Za-z]' 2>/dev/null | sed 's/^/tool-invocation\t/'
}

# --- HOW-outside content gate: prose mask (tier2 hook 専用、 advisory) ---
# spec 本文の可視 prose のみを残し code/pre/script/style/chrome/aside.machine-readable を mask する。
# bin/folio folio_prose_only (tier3 validate の authoritative masker) と同一アルゴリズムを保持し、
# tier2 hook の P-11 検出が tier3 floor-2 と一致するようにする (advisory ⊆ guarantee)。 bin/folio 側は
# inventory/prime が plugin-lib 非依存のため移譲できず (line 1672 設計意図)、 本 lib に同期コピーを置く
# (drift 時は bin/folio folio_prose_only が SSoT)。 引数: $1 = HTML body 文字列。
folio_mask_prose() {
  printf '%s\n' "$1" | awk '
    function mask_inline_code(s,   i,c,n,out){
      n=length(s); out=""
      for(i=1;i<=n;i++){
        c=substr(s,i,1)
        if(incode){ out=out " "; if(c==">" && substr(s,i-6,7)=="</code>") incode=0; continue }
        if(c=="<" && substr(s,i,5)=="<code" && (substr(s,i+5,1)==" " || substr(s,i+5,1)==">")){ incode=1; out=out " "; continue }
        out=out c
      }
      return out
    }
    BEGIN{ skip=0; incode=0; chrome=0 }
    /<!--[[:space:]]*folio:chrome-(top|toc|bottom)[[:space:]]*-->/{chrome=1}
    /<(pre|script|style)[ >]/{skip++}
    /<aside class="machine-readable"/{skip++}
    skip==0 && chrome==0 { print mask_inline_code($0) }
    /<!--[[:space:]]*\/folio:chrome-(top|toc|bottom)[[:space:]]*-->/{chrome=0}
    /<\/(pre|script|style|aside)>/{if(skip>0)skip--}
  '
}
