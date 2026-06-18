#!/usr/bin/env bash
# folio 文書規律エンジン core (B2 / folio-5ua) — verify 共通ライブラリ (fabrication-free 規律ヘルパ)
#
# rule-of-three の core 抽出 (research/document-discipline-engine-design.html §7):
# fabrication-free 規律 (chk / chk_empty / set_eq / 行数=contract 導出 / escape / fail-closed) と
# 2-gate 型の verify 足回りは doc-type 非依存 = core。 verify-fabrication-free.sh (SRS-pack) /
# verify-adr.sh (ADR-pack) / verify-srs.sh (SRS floor) が source する。 pack 固有の検査
# (RTM 集合 / cross-doc 照会解決 / ADR verdict 整合 等) は各 verify に残す。
#
# 前提 (source 側の責務):
#   - 冒頭で `set -uo pipefail` と `shopt -u patsub_replacement` 済 (esc の ${v//&/..} を守る)。
#   - $CONTRACT (contract path) を設定済 (q が参照)。 $fail を 0 で初期化済 (chk 系が立てる)。
#   - chk 系の整列幅は $CHKW で決まる (既定 48。 各 verify は元の幅に合わせて設定: fab=44/adr=48/srs=50)。
#   - make_body 後は $BODY (style 除去 body-only view) が使える。

# patsub_replacement (bash 5.2+) は esc() の ${v//&/..} を壊す。 source 側が忘れても lib 自身で無効化し堅牢化。
shopt -u patsub_replacement 2>/dev/null || true
CHKW="${CHKW:-48}"

q() { yq -r "$1" "$CONTRACT"; }
# assemble / inject-prose と同一の escape 規律 (注入忠実・term-inline 照合に使う)。
esc() { local s="${1-}"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; printf '%s' "$s"; }

chk() { # label expected actual
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "$1" "$2"
  else printf '  [FAIL] %-'"$CHKW"'s expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}
chk_empty() { # label value(空であるべき)
  if [[ -z "$2" ]]; then printf '  [OK]   %-'"$CHKW"'s\n' "$1"
  else printf '  [FAIL] %-'"$CHKW"'s 重複: %s\n' "$1" "$2"; fail=1; fi
}
set_eq() { # label expected-multiline actual-multiline
  if [[ "$2" == "$3" ]]; then printf '  [OK]   %-'"$CHKW"'s %s\n' "$1" "識別"
  else
    printf '  [FAIL] %-'"$CHKW"'s\n' "$1"
    echo "    --- contract のみ (脱落) ---"; comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    echo "    --- HTML のみ (捏造) ---";     comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
    fail=1
  fi
}

# inline srs.css の [data-component="..."] セレクタが body 要素 grep に混入するため、
# <style> ブロックを除去した body-only ビューで数える ($BODY をグローバルに設定し EXIT で掃除)。
make_body() { # $1 = html path
  BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
  sed '/<style>/,/<\/style>/d' "$1" > "$BODY"
}

# ---- plain-language-term-inline (glossary 派生ビュー、 ADR-0042 §2.2 A) の fidelity + 用語被覆 ----
# バッジ構造: <span class="term" data-component="plain-language-term-inline" data-term="TE">PLAIN</span>
# 照合は assemble と同じ esc() 済みで行う (esc 非対称による偽 FAIL を避ける)。 markable フィールドは
# pack 固有ゆえ呼出側が yq 式で渡す ($1)。 被覆 set_eq のラベルも pack 別ゆえ $2 で受ける。
# (a) fidelity: data-term ∈ glossary かつ 併記 == その語の plain_short / (b) uniqueness: 各 data-term 1 回 /
# (c) 用語被覆: マーク data-term 集合 == markable に出現する glossary 語 (assemble と *同一の語境界規律* で再導出)。
verify_term_inline() { # $1 = markable フィールドの yq 式  $2 = 被覆 set_eq ラベル
  local markable_expr="$1" cov_label="$2"
  declare -A GPLAIN GALL GASCII
  while IFS=$'\t' read -r gterm gplain; do
    [[ -n "$gterm" ]] || continue
    [[ -n "$gplain" && "$gplain" != "null" ]] || gplain="$gterm"
    gte="$(esc "$gterm")"; GALL[$gte]=1; GPLAIN[$gte]="$(esc "$gplain")"
    a=1; case "$gterm" in *[!\ -~]*) a=0 ;; esac; GASCII[$gte]="$a"   # assemble と同じ ascii 判定
  done < <(q '.glossary[] | [.term, (.plain_short // "")] | @tsv')
  mapfile -t MARKS < <(grep -oE '<span class="term" data-component="plain-language-term-inline" data-term="[^"]*">[^<]*</span>' "$BODY")
  local tfail=0; declare -A TSEEN
  local m dt ct
  for m in "${MARKS[@]}"; do
    dt="$(printf '%s' "$m" | sed -E 's/.*data-term="([^"]*)".*/\1/')"
    ct="$(printf '%s' "$m" | sed -E 's#.*">([^<]*)</span>#\1#')"
    [[ -n "${GALL[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が glossary に無い (捏造)"; tfail=1; fail=1; }
    [[ -z "${GALL[$dt]:-}" || "$ct" == "${GPLAIN[$dt]}" ]] || { echo "  [FAIL] term-inline '$dt' 併記が plain_short と不一致 (期待 '${GPLAIN[$dt]}' 実 '$ct')"; tfail=1; fail=1; }
    [[ -z "${TSEEN[$dt]:-}" ]] || { echo "  [FAIL] term-inline data-term '$dt' が重複マーク"; tfail=1; fail=1; }
    TSEEN[$dt]=1
  done
  [[ "$tfail" -eq 0 ]] && printf '  [OK]   %-'"$CHKW"'s %s\n' "term-inline 派生・一意 (data-term∈glossary・併記==plain_short)" "${#MARKS[@]}"
  # (c) 用語被覆: ascii=英数境界 / CJK=漢字非隣接 (perl -CSD) で assemble と同一の語境界規律。
  local MKF GF2 gte exp_marks act_marks
  MKF="$(mktemp)"; GF2="$(mktemp)"
  esc "$(q "$markable_expr")" > "$MKF"
  for gte in "${!GALL[@]}"; do printf '%s\t%s\n' "$gte" "${GASCII[$gte]}"; done > "$GF2"
  exp_marks="$(MKF="$MKF" GF2="$GF2" perl -CSD -e '
    local $/; open(my $mf,"<",$ENV{MKF}) or die; my $m=<$mf>; close $mf; $m="" unless defined $m;
    my @out;
    { local $/="\n"; open(my $gf,"<",$ENV{GF2}) or die;
      while (my $l=<$gf>){ chomp $l; next unless length $l; my ($te,$a)=split(/\t/,$l,2);
        my $pat=($a eq "1")?qr/(?<![A-Za-z0-9])\Q$te\E(?![A-Za-z0-9])/:qr/(?<!\p{Han})\Q$te\E(?!\p{Han})/;
        push @out,$te if $m=~$pat; } close $gf; }
    print "$_\n" for sort @out;
  ')"
  rm -f "$MKF" "$GF2"
  act_marks="$(printf '%s\n' "${MARKS[@]}" | grep . | sed -E 's/.*data-term="([^"]*)".*/\1/' | sort -u)"
  set_eq "$cov_label" "$exp_marks" "$act_marks"
}

# ---- cross-doc 照会解決の共通スケルトン (rule-of-three: verify-adr §3 ∩ verify-research §3、 ds8 で core 昇格) ----
# B3 までは verify-adr.sh (justifies→SRS) と verify-research.sh (leads_to→ADR) に *同型の解決ブロックが重複*
# していた (照会先 contract 実在 / doc_id 一致 / count anchor / SET 一致 / dangling / 空値ガード / role allowlist /
#  (key,role) ペア SET 一致 の 8 検査)。 これは doc-type 非依存 = core。 pack 固有 (research の outcome.resolved_by・
# (ap-id,leads_to) ペア・可視チップ厳密一致・within-doc 順序・cover-meta / ADR の verdict 整合・supersession/principle・
# 可視 echo 厳密一致) は各 verify に残す (= core/pack 境界。 「新 doc-type に持ち込んで改変が要らない」= core)。
#
# ★空値ガード (|edges| == |非空 edges|) を core に入れて *両 pack へ無料で配る* のが ds8 の核:
#   comm -23 は空行を空 missing に畳むため dangling 判定が空文字列キーを素通す fail-open (research round-5 ceiling 発見)。
#   research は verify 側に持っていたが ADR は欠いていた (= 横展開で塞ぐ穴。 empty-value バグは assemble 側でも実在)。
#
# 抽象ロール allowlist は両 pack 文字列完全一致 = core 定数 (照会 graph のロール語彙・B0 论点2 終端解決)。
CROSS_DOC_ROLE_ALLOWLIST='claim|rationale|exploration|principle|verification|implementation'

# verify_cross_doc_refs — named-flag で受ける (12 引数の位置依存は誤順 = silent fail-open ゆえ flag で防ぐ)。
# 必須: --label-prefix --target-label --target-abs --key-attr --role-attr --keys-expr --count-expr
#       --nonempty-count-expr --pair-expr --target-ids-expr --contract-docid-expr --target-docid-expr
# 任意: --target-rel (不在メッセージ用)。 expr は呼出側 pack から *逐語で* 渡す (合成しない = 非破壊の証明を直截に保つ)。
# chk/chk_empty/set_eq が立てる $fail と $BODY/$CONTRACT/q (source 側責務) をそのまま使う。
verify_cross_doc_refs() {
  local label_prefix="" target_label="" target_abs="" target_rel="" key_attr="" role_attr=""
  local keys_expr="" count_expr="" nonempty_count_expr="" pair_expr="" target_ids_expr=""
  local contract_docid_expr="" target_docid_expr=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label-prefix)         label_prefix="$2";        shift 2 ;;
      --target-label)         target_label="$2";        shift 2 ;;
      --target-abs)           target_abs="$2";          shift 2 ;;
      --target-rel)           target_rel="$2";          shift 2 ;;
      --key-attr)             key_attr="$2";            shift 2 ;;
      --role-attr)            role_attr="$2";           shift 2 ;;
      --keys-expr)            keys_expr="$2";           shift 2 ;;
      --count-expr)           count_expr="$2";          shift 2 ;;
      --nonempty-count-expr)  nonempty_count_expr="$2"; shift 2 ;;
      --pair-expr)            pair_expr="$2";           shift 2 ;;
      --target-ids-expr)      target_ids_expr="$2";     shift 2 ;;
      --contract-docid-expr)  contract_docid_expr="$2"; shift 2 ;;
      --target-docid-expr)    target_docid_expr="$2";   shift 2 ;;
      *) echo "  [FAIL] verify_cross_doc_refs: 未知の引数 '$1'"; fail=1; return 1 ;;
    esac
  done
  # 必須パラメータ欠落は fail-closed (空 expr で検査を false-green に倒さない = この issue の主題そのもの)。
  local _p _missing=""
  for _p in label_prefix target_label target_abs key_attr role_attr keys_expr count_expr \
            nonempty_count_expr pair_expr target_ids_expr contract_docid_expr target_docid_expr; do
    [[ -n "${!_p}" ]] || _missing+=" --${_p//_/-}"
  done
  [[ -z "$_missing" ]] || { echo "  [FAIL] verify_cross_doc_refs: 必須パラメータ欠落:$_missing"; fail=1; return 1; }

  local prefix="$label_prefix"
  # (existence) 照会先 contract 実在 (fail-closed・不在なら以降は走らせない = 元の if/else 構造を保存)
  if [[ ! -f "$target_abs" ]]; then
    printf '  [FAIL] %-'"$CHKW"'s 参照先 %s contract 不在: %s\n' "${prefix}: 照会先 ${target_label} contract 実在" "$target_label" "${target_rel:-$target_abs}"; fail=1
    return 1
  fi
  printf '  [OK]   %-'"$CHKW"'s %s\n' "${prefix}: 照会先 ${target_label} contract 実在" "${target_rel:-$target_abs}"
  # (c) doc_id 一致 (contract 側 docid フィールド == target 側 docid フィールド)
  chk "${prefix}: doc_id == ${target_label} contract" "$(yq -r "$target_docid_expr" "$target_abs")" "$(q "$contract_docid_expr")"
  # (a) count anchor: |edges| == HTML の data-<keyAttr>= 出現数 (set_eq は sort -u で重複を潰す → 重複注入は count で捕捉)
  chk "${prefix}: count == |edges|" "$(q "$count_expr")" "$(grep -o "${key_attr}=" "$BODY" | wc -l | tr -d ' ')"
  # (a) SET 一致: contract key 集合 == HTML data-<keyAttr> 集合 (捏造 0 + 脱落 0)
  local exp_k act_k
  exp_k="$(q "$keys_expr" | sort -u)"
  act_k="$(grep -oE "${key_attr}=\"[^\"]+\"" "$BODY" | sed "s/.*${key_attr}=\"//; s/\"\$//" | sort -u)"
  set_eq "${prefix}: key SET (contract == HTML)" "$exp_k" "$act_k"
  # (b) dangling 照会 0: contract key が参照先 ID に実在
  local dangling
  dangling="$(comm -23 <(q "$keys_expr" | sort -u) <(yq -r "$target_ids_expr" "$target_abs" | sort -u))"
  chk_empty "${prefix}: dangling 照会 (${target_label} に無い key)" "$(printf '%s' "$dangling" | tr '\n' ' ' | sed 's/ *$//')"
  # (i') ★空値ガード (core の核): comm -23 が空行を空 missing に畳む fail-open を塞ぐ。 contract key 全件非空を明示要求
  #      (空照会キー = option/要件 に繋がらない壊れた前方/後方参照。 assemble validate と対称・両 pack 共通)。
  chk "${prefix}: key 全て非空 (空照会キー禁止)" "$(q "$count_expr")" "$(q "$nonempty_count_expr")"
  # (d) role allowlist (HTML 側 data-<roleAttr> ⊆ 抽象ロール allowlist)
  local badrole
  badrole="$(grep -oE "${role_attr}=\"[^\"]+\"" "$BODY" | sed "s/.*${role_attr}=\"//; s/\"\$//" | sort -u \
    | grep -vxE "$CROSS_DOC_ROLE_ALLOWLIST" | tr '\n' ' ')"
  chk_empty "${prefix}: 照会 role が抽象 allowlist 内" "$badrole"
  # (d') (key,role) ペア SET 一致: allowlist 内別 role への改竄 = 照会 graph の意味偽装を捕捉 (role allowlist だけでは fail-open)
  local exp_kr act_kr
  exp_kr="$(q "$pair_expr" | sort -u)"
  act_kr="$(grep -oE "${key_attr}=\"[^\"]+\" ${role_attr}=\"[^\"]+\"" "$BODY" \
    | sed -E "s/${key_attr}=\"([^\"]+)\" ${role_attr}=\"([^\"]+)\"/\1\t\2/" | sort -u)"
  set_eq "${prefix}: (key,role) ペア (contract == HTML)" "$exp_kr" "$act_kr"
  return 0
}
