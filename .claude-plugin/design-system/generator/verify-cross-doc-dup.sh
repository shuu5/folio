#!/usr/bin/env bash
# folio 文書規律エンジン (folio-c5r.1) — cross-doc content 重複検出 lint (suite-level・advisory)
#
# yzv 決定④ の機構化。 engine = 確実な生成器 + 機械的検出 (floor・冪等)。 判断 (doc-type 要否) は
# engine に作り込まず人間 (事後・ceiling)。 本 lint は「判断材料 (字句重複) を可視化するだけ」で
# 必要性を判断しない。 ★検出 clean は「字句重複が見つからなかった」であって doc-type が適切である
# 証明ではない (engine「floor 緑 ≠ 完成」教訓を doc-type 要否判断へ適用)。
#
# 検出対象 = contract YAML の content-leaf 散文 (生成 HTML ではない = SSoT 直比較・chrome ノイズ回避)。
# 機構 (3 段):
#   (1) 抽出: 各 contract から pack 別 CONTENT_LEAVES map の field を (doc_id, pack, label, text) レコード化。
#       glossary def / cross_doc chrome / 共有終端 principle.text / NFR 数値密 field は map 不掲載 = 除外 (precision)。
#   (2) 類似: 同一 suite (instance 名 prefix) 内で doc_id が異なる全レコードペアを 文字 k-gram shingle の
#       Jaccard(J) で採点 (perl -CSD で UTF-8 char 単位・LC_ALL=C 集合演算との衝突を回避)。 J は長さ正規化済で
#       「2 文書がどれだけ同一か」を測り内容重複の信号になる。 ★containment(C) は併記のみで判定に使わない —
#       実測上、 長文 spec 同士は共通語彙だけで C が高く出て「内容重複」と「語彙重複」を分離できないため (§calibration)。
#       別プロジェクト (別 suite prefix: clinic / ec / folio) は比較しない (boilerplate 共有は重複でない)。
#   (3) graph 認識: rolemap edge の target_docid_expr から declared doc-pair 集合を構築 (verify-graph.sh と同一の
#       edge 定義を再利用しドリフト回避)。 字句重複ペアが declared なら「設計意図の引継ぎ」= informational、
#       undeclared なら actionable WARN。 ゼロ生成 constitution は SRS への edge を持たない → undeclared → 検出 (demo)。
#
# ★limitation (設計境界・honest): 本 lint は字句 (連続 substring) 重複のみ検出する。 語を総入れ替えした
#   意味的 paraphrase (共通 substring を持たない言い換え) は J≈0・C≈0 で構造上検出しない。 意味レベルの
#   重複/要否判断は人間 ceiling が backstop (これ自体が engine 哲学「検出機構も bounded」の lint 内再帰)。
#
# 用法: verify-cross-doc-dup.sh [--contract-dir <dir>] [--rolemap-dir <dir>] [--strict] [--show-declared]
#                              [--warn-j <f>] [--high-j <f>]
#   既定 contract-dir = <script>/contract、 rolemap-dir = <script>/rolemap。
#   既定 = advisory (exit 0)。 --strict は undeclared HIGH (J>=high-j) が 1 件以上で exit 1 (ローカル gate 向け・CI 非配線)。
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_DIR="$SCRIPT_DIR/contract"
ROLEMAP_DIR="$SCRIPT_DIR/rolemap"
STRICT=0
SHOW_DECLARED=0
# 閾値 (clean corpus 誤検出 0 で実測キャリブレーション・§floor)。 検出信号 = J(Jaccard)。 WARN = J>=WARN_J、 HIGH = J>=HIGH_J。
# ★C(containment) は WARN 判定に使わず文脈として併記のみ (実測: 長文 spec 同士は共通語彙だけで C=0.6 に達し、
#   C は「内容重複」と「語彙重複」を分離できない。 J は長さ正規化済で「2 文書がどれだけ同一か」を測り重複の正しい信号になる)。
# ★閾値の限界 (honest・README §「閾値の限界」): 現 corpus の undeclared 最大 J≈0.274 (TC↔ARCH の正当な話題重複)。
#   WARN_J=0.40 はその上で誤検出 0 だが margin≈0.13 と薄い。 **near-verbatim restatement のみ J>=0.4 に達し**、 意味を
#   保った中程度 restatement の多くは J≈0.23-0.27 で noise 帯に沈み J 閾値では分離不能 (下げると正当な話題重複を誤検出)。
#   巧妙な restate は人間 ceiling が backstop。 「誤検出 0」は各 suite が SRS 1 本ずつの現 corpus 由来の限定実測。
WARN_J=0.40
HIGH_J=0.65
KGRAM=4          # 文字 n-gram 長 (k=3 は短 term 過敏・k=5 は restatement 取りこぼし・k=4 が均衡点)
MINLEN=8         # 正規化長 < MINLEN 文字の field は比較対象外 (短 enum/ID のノイズ排除)
PREFILTER=0.15   # perl が emit する下限 (max(J,C) >= PREFILTER のペアのみ・出力量制御)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract-dir) CONTRACT_DIR="$2"; shift 2 ;;
    --rolemap-dir)  ROLEMAP_DIR="$2";  shift 2 ;;
    --strict)       STRICT=1; shift ;;
    --show-declared) SHOW_DECLARED=1; shift ;;
    --warn-j)       WARN_J="$2"; shift 2 ;;
    --high-j)       HIGH_J="$2"; shift 2 ;;
    *) echo "verify-cross-doc-dup: 未知の引数 '$1'" >&2; exit 2 ;;
  esac
done

command -v yq   >/dev/null || { echo "verify-cross-doc-dup: yq required" >&2; exit 2; }
command -v perl >/dev/null || { echo "verify-cross-doc-dup: perl required" >&2; exit 2; }
# core reader (graph_pack_of) を fail-closed guard で source (欠落/失敗を false-green に倒さない)。
GC="$SCRIPT_DIR/lib/graph-common.sh"
[[ -f "$GC" ]] || { echo "verify-cross-doc-dup: lib/graph-common.sh not found" >&2; exit 2; }
source "$GC" || { echo "verify-cross-doc-dup: failed to source graph-common.sh" >&2; exit 2; }

[[ -d "$CONTRACT_DIR" ]] || { echo "verify-cross-doc-dup: contract-dir 不在: $CONTRACT_DIR" >&2; exit 2; }
[[ -d "$ROLEMAP_DIR"  ]] || { echo "verify-cross-doc-dup: rolemap-dir 不在: $ROLEMAP_DIR" >&2; exit 2; }

# ===== CONTENT_LEAVES map (pack → "label|yq-expr" 改行区切り) =====
# ここに掲載した field のみ重複検出対象。 不掲載 = 除外 (glossary def / cross_doc chrome / 共有終端
# principle.text / NFR 数値密 = precision のため意図的に不掲載)。 新 doc-type 追加時は本 map を更新する
# (未掲載 pack は下の unknown-pack ガードが fail-loud WARN で更新漏れを検出)。
declare -A LEAVES
LEAVES[srs]='goals[].headline|.goals[].headline
goals[].desc|.goals[].desc
scope.in[]|.scope.in[]
scope.out[]|.scope.out[]
actors[].role|.actors[].role
upper_needs[].need|.upper_needs[].need
requirements[].ears.condition|.requirements[].ears.condition
requirements[].ears.response|.requirements[].ears.response
acceptance[].criterion|.acceptance[].criterion
constraints[].text|.constraints[].text'
LEAVES[adr]='context[].summary|.context[].summary
context[].detail|.context[].detail
drivers[].driver|.drivers[].driver
options[].summary|.options[].summary
options[].pros[]|.options[].pros[]
options[].cons[]|.options[].cons[]
decision.statement|.decision.statement
decision.justifies[].note|.decision.justifies[].note
consequences.positive[].text|.consequences.positive[].text
consequences.negative[].text|.consequences.negative[].text
supersession.note|.supersession.note'
LEAVES[research]='question.summary|.question.summary
question.in_scope[]|.question.in_scope[]
question.out_scope[]|.question.out_scope[]
findings[].summary|.findings[].summary
findings[].detail|.findings[].detail
approaches[].summary|.approaches[].summary
approaches[].assessment|.approaches[].assessment
open_questions[].text|.open_questions[].text
outcome.note|.outcome.note'
LEAVES[principle]='principles[].heading|.principles[].heading
principles[].statement|.principles[].statement
versioning.rules[].condition|.versioning.rules[].condition
versioning.note|.versioning.note
amendment.steps[]|.amendment.steps[]'
LEAVES[arch]='context.problem|.context.problem
strategy[].plain|.strategy[].plain
strategy[].rationale|.strategy[].rationale
components[].responsibility|.components[].responsibility
components[].separation_reason|.components[].separation_reason
runtime.flows[].summary|.runtime.flows[].summary
runtime.flows[].steps[]|.runtime.flows[].steps[]
decisions[].summary|.decisions[].summary
quality[].plain|.quality[].plain
risks[].risk|.risks[].risk
risks[].impact|.risks[].impact
risks[].mitigation|.risks[].mitigation'
LEAVES[spec]='sections[].essence|.sections[].essence
sections[].blocks[].text|.sections[].blocks[].text
sections[].blocks[].items[]|.sections[].blocks[].items[]
sections[].blocks[].essence|.sections[].blocks[].essence
requirements[].essence|.requirements[].essence
requirements[].statement|.requirements[].statement'
LEAVES[testcases]='test_cases[].title|.test_cases[].title
test_cases[].precondition|.test_cases[].precondition
test_cases[].steps[]|.test_cases[].steps[]
test_cases[].expected|.test_cases[].expected
scope.in[]|.scope.in[]
scope.out[]|.scope.out[]'
# glossary = 比較対象なし (用語 def は SSoT コピーで全 pack に複製 = 構造上の全一致ゆえ除外)。
LEAVES[glossary]=''

mapfile -t CONTRACTS < <(find "$CONTRACT_DIR" -maxdepth 1 -name '*.yaml' | sort)
[[ "${#CONTRACTS[@]}" -gt 0 ]] || { echo "verify-cross-doc-dup: contract 0 件: $CONTRACT_DIR" >&2; exit 2; }

records_file="$(mktemp)"; declared_file="$(mktemp)"; perlout_file="$(mktemp)"
cleanup() { rm -f "$records_file" "$declared_file" "$perlout_file"; }
trap cleanup EXIT

UNKNOWN_PACKS=()
SKIPPED_DOCS=()    # doc_id 欠落/不正 YAML でスキップした contract (fail-loud coverage = 「検査できた範囲が緑」担保)
declare -A DOCPACK DOCSEEN
ndocs=0

for CONTRACT in "${CONTRACTS[@]}"; do
  pack="$(graph_pack_of "$CONTRACT")"
  did="$(yq -r '.meta.doc_id // ""' "$CONTRACT" 2>/dev/null)"
  # ★fail-loud coverage (F10 と対称): doc_id 欠落/不正 YAML で doc を silent drop しつつ clean を返すと
  #   「検査できた範囲が緑」を「全部緑」と誤読させる。 スキップを可視化し coverage を honest にする。
  if [[ -z "$did" || "$did" == "null" ]]; then SKIPPED_DOCS+=("${CONTRACT##*/}"); continue; fi
  [[ -z "${DOCSEEN[$did]:-}" ]] || continue   # doc_id 重複は verify-graph が別途 FAIL・ここでは初回のみ
  DOCSEEN[$did]=1; DOCPACK[$did]="$pack"; ndocs=$((ndocs+1))

  # suite prefix = instance 名 (<instance>.<pack>.yaml) の最初の '-' 区切り segment。
  # 別プロジェクトの doc (clinic vs ec vs folio) を比較しない = lint の射程は単一 suite 内 cross-doc。
  base="${CONTRACT##*/}"; instance="${base%.yaml}"; instance="${instance%.*}"
  prefix="${instance%%-*}"

  # unknown-pack ガード (F10): CONTENT_LEAVES に未登録 (空でも未宣言) の pack は silent false-negative 源。
  if [[ -z "${LEAVES[$pack]+set}" ]]; then
    UNKNOWN_PACKS+=("$pack ($did)")
  fi

  # content-leaf 抽出 → records (doc_id \t pack \t label \t text)。 多値 expr は 1 値 1 レコード。
  leafspec="${LEAVES[$pack]:-}"
  if [[ -n "$leafspec" ]]; then
    while IFS='|' read -r label expr; do
      [[ -n "$label" && -n "$expr" ]] || continue
      while IFS= read -r val; do
        [[ -n "$val" && "$val" != "null" ]] || continue
        val="${val//$'\t'/ }"   # tab を空白化 (TSV 保全)
        printf '%s\t%s\t%s\t%s\t%s\n' "$prefix" "$did" "$pack" "$label" "$val" >> "$records_file"
      done < <(yq -r "$expr" "$CONTRACT" 2>/dev/null)
    done <<< "$leafspec"
  fi

  # declared doc-pair: rolemap edge の target_docid_expr を評価 (verify-graph.sh と同一 edge 定義)。
  rolemap="$ROLEMAP_DIR/$pack.rolemap.yaml"
  if [[ -f "$rolemap" ]]; then
    necnt="$(yq -r '.edges // [] | length' "$rolemap" 2>/dev/null)"
    [[ "$necnt" =~ ^[0-9]+$ ]] || necnt=0
    for ((i=0; i<necnt; i++)); do
      texpr="$(yq -r ".edges[$i].target_docid_expr // \"\"" "$rolemap" 2>/dev/null)"
      [[ -n "$texpr" && "$texpr" != "null" ]] || continue
      while IFS= read -r tgt; do
        [[ -n "$tgt" && "$tgt" != "null" ]] || continue
        # 無向ペアを LC_ALL=C ソート順で正規化 (declared 集合は対称)。
        if [[ "$did" < "$tgt" ]]; then printf '%s\t%s\n' "$did" "$tgt" >> "$declared_file"
        else printf '%s\t%s\n' "$tgt" "$did" >> "$declared_file"; fi
      done < <(yq -r "$texpr" "$CONTRACT" 2>/dev/null)
    done
  fi
done

# declared 集合を一意化。
LC_ALL=C sort -u "$declared_file" -o "$declared_file"

# ===== perl 類似度計算 (UTF-8 char-aware・shingle/J/C・declared 分類) =====
# 出力 (tab 区切り): J C inter nshort bucket docA labelA docB labelB headA headB
#   inter = |A∩B| shingle 数、 nshort = min(|A|,|B|) shingle 数 (C-WARN ガードを bash 側で適用するため)。
perl - "$records_file" "$declared_file" "$KGRAM" "$MINLEN" "$PREFILTER" > "$perlout_file" <<'PERL'
use strict; use warnings;
use utf8;
binmode(STDOUT, ':encoding(UTF-8)');
my ($rec_path, $decl_path, $K, $MINLEN, $PREFILTER) = @ARGV;

# 正規化 (決定的・順序固定): 隅付き/全角括弧 → 数字非隣接スペース除去。 句読点 。、 は文境界として保持。
sub norm {
  my ($s) = @_;
  $s =~ s/[「」『』]//g;
  $s =~ tr/（）/()/;
  $s =~ s/\s+/ /g;
  $s =~ s/(?<![0-9０-９]) (?![0-9０-９])//g;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}
sub shingles {
  my ($s) = @_;
  my @c = split //, $s;
  my %set;
  return (\%set, scalar(@c)) if @c < $K;
  for my $i (0 .. $#c - $K + 1) { $set{ join('', @c[$i .. $i+$K-1]) } = 1; }
  return (\%set, scalar(@c));
}

# declared 無向ペア集合 (key = "docLo\tdocHi")。
my %declared;
if (open(my $df, '<:encoding(UTF-8)', $decl_path)) {
  while (my $l = <$df>) { chomp $l; $declared{$l} = 1 if length $l; }
  close $df;
}

# records 読み込み + shingle 化 (MINLEN 未満は除外)。 col: prefix, docid, pack, label, text。
my (@prefix, @docid, @pack, @label, @text, @sh);
open(my $rf, '<:encoding(UTF-8)', $rec_path) or exit 0;
while (my $l = <$rf>) {
  chomp $l;
  my ($pf, $d, $p, $lb, $t) = split /\t/, $l, 5;
  next unless defined $t;
  my $n = norm($t);
  my ($set, $len) = shingles($n);
  next if $len < $MINLEN;            # 短 field 除外
  next if scalar(keys %$set) == 0;
  push @prefix, $pf; push @docid, $d; push @pack, $p; push @label, $lb; push @text, $t;
  push @sh, $set;
}
close $rf;

my $N = scalar @docid;
for (my $a = 0; $a < $N; $a++) {
  for (my $b = $a + 1; $b < $N; $b++) {
    next if $docid[$a] eq $docid[$b];      # 同一 doc 内は比較しない (cross-doc が射程)
    next if $prefix[$a] ne $prefix[$b];    # 別 suite (別プロジェクト) は比較しない
    my ($sa, $sb) = ($sh[$a], $sh[$b]);
    my ($na, $nb) = (scalar keys %$sa, scalar keys %$sb);
    my $inter = 0;
    if ($na <= $nb) { for my $g (keys %$sa) { $inter++ if $sb->{$g}; } }
    else            { for my $g (keys %$sb) { $inter++ if $sa->{$g}; } }
    next if $inter == 0;
    my $union = $na + $nb - $inter;
    my $J = $union ? $inter / $union : 0;
    my $min = $na < $nb ? $na : $nb;
    my $C = $min ? $inter / $min : 0;
    my $mx = $J > $C ? $J : $C;
    next if $mx < $PREFILTER;
    # declared 判定 (無向)。
    my ($lo, $hi) = $docid[$a] lt $docid[$b] ? ($docid[$a], $docid[$b]) : ($docid[$b], $docid[$a]);
    my $bucket = $declared{"$lo\t$hi"} ? 'declared' : 'undeclared';
    # head スニペット (先頭 40 字・char 単位)。
    my $ha = substr($text[$a], 0, 40); my $hb = substr($text[$b], 0, 40);
    $ha =~ s/\t/ /g; $hb =~ s/\t/ /g;
    printf "%.3f\t%.3f\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
      $J, $C, $inter, $min, $bucket, $docid[$a], $label[$a], $docid[$b], $label[$b], $ha, $hb;
  }
}
PERL

# ===== bash: 閾値適用 + 整形 + exit code =====
# float 比較 helper (awk・perl 出力は %.3f 固定小数ゆえ awk で安全)。
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }

# perl 出力を決定的順 (docA,labelA,docB,labelB) でソート (col6=docA col7=labelA col8=docB col9=labelB)。
LC_ALL=C sort -t$'\t' -k6,6 -k7,7 -k8,8 -k9,9 "$perlout_file" -o "$perlout_file"

# debug affordance (calibration 用・本番出力には影響しない): DUP_DUMP_RAW にパス指定で perl 生出力 (J C inter
# nshort bucket docA labelA docB labelB headA headB) をコピーする。
[[ -n "${DUP_DUMP_RAW:-}" ]] && cp "$perlout_file" "$DUP_DUMP_RAW"

declare -i n_warn=0 n_high=0 n_declared=0 n_pairs=0
WARN_LINES=(); DECL_LINES=()
while IFS=$'\t' read -r J C inter nshort bucket docA labelA docB labelB headA headB; do
  [[ -n "$J" ]] || continue
  n_pairs=$((n_pairs+1))
  if [[ "$bucket" == "declared" ]]; then
    n_declared=$((n_declared+1))
    DECL_LINES+=("  [echo] $docA:$labelA ⇔ $docB:$labelB   J=$J C=$C   (cross_doc graph で説明済)")
    continue
  fi
  # undeclared WARN 判定 = J>=WARN_J のみ (C は文脈併記・判定外。 §header の理由)。
  if ge "$J" "$WARN_J"; then
    n_warn=$((n_warn+1))
    sev="DUP"
    if ge "$J" "$HIGH_J"; then sev="HIGH"; n_high=$((n_high+1)); fi
    WARN_LINES+=("  [$sev]  $docA:$labelA ⇔ $docB:$labelB   J=$J C=$C   (undeclared)")
    WARN_LINES+=("         A: $headA")
    WARN_LINES+=("         B: $headB")
  fi
done < "$perlout_file"

n_compared_docs=$ndocs
echo "cross-doc 重複検出 lint — corpus: $CONTRACT_DIR (${n_compared_docs} docs)"
if [[ "${#SKIPPED_DOCS[@]}" -gt 0 ]]; then
  echo "  [WARN] doc_id 欠落/不正 YAML でスキップした contract (この範囲は未検査・clean を全緑と読まない):"
  printf '         - %s\n' "${SKIPPED_DOCS[@]}"
fi
if [[ "${#UNKNOWN_PACKS[@]}" -gt 0 ]]; then
  echo "  [WARN] CONTENT_LEAVES 未登録 pack (silent false-negative 源・map 更新要):"
  printf '         - %s\n' "${UNKNOWN_PACKS[@]}"
fi
if [[ "${#WARN_LINES[@]}" -gt 0 ]]; then
  printf '%s\n' "${WARN_LINES[@]}"
else
  echo "  (undeclared 字句重複なし)"
fi
if [[ "$SHOW_DECLARED" -eq 1 && "${#DECL_LINES[@]}" -gt 0 ]]; then
  echo "  --- declared echoes (cross_doc graph で説明済・非フラグ) ---"
  printf '%s\n' "${DECL_LINES[@]}"
fi
echo "  ----"
printf '  undeclared 重複=%d (うち HIGH=%d) / declared echo=%d / 比較ペア候補=%d\n' \
  "$n_warn" "$n_high" "$n_declared" "$n_pairs"
echo "  RESULT: ADVISORY — undeclared 字句重複 ${n_warn} 件 (0 件 = 字句重複なし)"
echo "  NOTE: 重複検出は判断材料。 clean ≠ doc-type が適切の証明 (engine「floor 緑 ≠ 完成」)。"
echo "        doc-type 要否の最終判断は人間 (ceiling・事後)。 検出条件は J(4-gram Jaccard)>=${WARN_J} の一点ゆえ、"
echo "        意味を保った中程度 restatement (J 低) や語入替 paraphrase は構造上見逃す (header の limitation 参照)。"
echo "        declared echo は doc-pair 粒度で抑制ゆえ edge が説明しない逐語重複も非表示 (--show-declared で確認)。"
echo "  CEILING=HUMAN-JUDGMENT (この lint は必要性を判断しない)"

if [[ "$STRICT" -eq 1 && "$n_high" -gt 0 ]]; then
  exit 1
fi
exit 0
