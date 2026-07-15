#!/usr/bin/env bash
# test-graph-emit.sh — spec-graph JSON-LD emit keystone の敵対回帰 (folio-u7y2 / 8dkl 前提)
#
# 生成 page を spec-graph (inventory/validate/fix + folio build chrome) に参加させる機構を、
# 肯定実証 + per-shape mutation-kill (4 class) で pin する。 pure bash (render-gate 非依存ゆえ
# uv/playwright 不要) = CI/host 双方で常時走る恒久 regression guard。 exit 0 = 全 pass / 非 0 = fail-closed。
#
#   L (lib emit)      core_emit_graph_head が JSON-LD + folio-* meta を emit・後方互換 (head_graph 無し=無出力)
#                     契約 4 前方関係 (isPartOf/references/depends-on/extends) を全て pin
#   L2 (mermaid配線)  mermaid-shape assembler (relations 等・挿入形が非 mermaid と異なる) で JSON-LD が
#                     mermaid vendor 行と head 内で共存する 2 構造クラス目を per-shape 被覆
#   P (肯定/scan到達) 生成 page を scan 配下に置き folio inventory が実際に拾う (silent-skip されない)
#   R (逆グラフ)      folio fix が dc:isReferencedBy を corpus 走査で導出 (per-doc SSoT に持たない)
#   C (chrome 共存)   folio build が nav (breadcrumb/skip) を注入・doc-cover-band と共存 (置換しない)
#   MK1 emit 欠落     head_graph 無し → inventory silent-skip = vacuous-green (本 issue の動機)
#   MK2 JSON-LD 改竄  → validate [FAIL] jsonld structural + inventory WARN-skip
#   MK3 chrome drift  → build --check 非 0
#   MK4 逆グラフ drift → validate [FAIL] broken-reverse
#   MK6 flip hard-fail  switchover-harness の head_graph hard-fail 述語を per-shape (srs/relations) で撃つ:
#                       in-scan flip target が head_graph 欠落 → FAIL / head_graph 付与 → PASS 陽性対照 /
#                       out-of-scan 着地 → exempt PASS 陰性対照 / grandfathered 存在下でも target 1 本 scope
#                       (corpus 走査 mutant 捕捉)。 FAIL 検出は FAIL 行専有 substring で exit 非依存 (folio-nnqh)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOLIO="$HERE/../../bin/folio"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { if grep -qE "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1"; fi; }        # file にパターン有
nhas() { if grep -qE "$2" "$3" 2>/dev/null; then bad "$1"; else ok "$1"; fi; }        # file にパターン無
jqok() { if jq -e "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }       # jq 真
njqok(){ if jq -e "$2" "$3" >/dev/null 2>&1; then bad "$1"; else ok "$1"; fi; }       # jq 偽

# --- fixture contract: 既存 srs に head_graph + meta.doc_type/status を足す (契約 4 前方関係 part_of/
#     references/depends_on/extends を全て宣言し emit を pin。 全 target は corpus 内 README を指し
#     link-integrity/broken-reverse を green に保つ = fix が depended-by/extended-by も導出する) ---
FXC="$WORK/fx.srs.yaml"
cp "$HERE/contract/clinic-appointment.srs.yaml" "$FXC"
yq -i '.meta.doc_type = "srs" | .meta.status = "active"' "$FXC"
cat >> "$FXC" <<'YAML'

head_graph:
  id: ./clinic-appointment.srs.html
  part_of: [./README.html]
  references: [./README.html]
  depends_on: [./README.html]
  extends: [./README.html]
YAML

echo "--- L: lib emit (JSON-LD + folio-* meta) + 後方互換 ---"
SRS="$WORK/gen.html"; "$HERE/assemble-srs.sh" "$FXC" "$SRS" 2>/dev/null
HEAD="$WORK/head"; awk '/<\/head>/{exit}{print}' "$SRS" > "$HEAD"
BLK="$WORK/blk.json"; awk '/<\/head>/{exit} c&&/<\/script>/{exit} c{print} /<script[^>]*application\/ld\+json/{c=1}' "$SRS" > "$BLK"
has  "L head に JSON-LD script"              'application/ld\+json'  "$HEAD"
has  "L folio-doc-type meta"                 '<meta name="folio-doc-type" content="srs">'    "$HEAD"
has  "L folio-status meta"                   '<meta name="folio-status" content="active">'   "$HEAD"
has  "L folio-version meta"                  '<meta name="folio-version"'                    "$HEAD"
jqok "L JSON-LD valid"                        '.'                                    "$BLK"
jqok "L @id 正しい"                           '.["@id"]=="./clinic-appointment.srs.html"'     "$BLK"
jqok "L @type == schema:TechArticle"          '.["@type"]=="schema:TechArticle"'    "$BLK"
jqok "L dc:isPartOf 前方関係 emit"            '.["dc:isPartOf"][0]["@id"]=="./README.html"'   "$BLK"
jqok "L dc:references 前方関係 emit"          '.["dc:references"][0]["@id"]=="./README.html"' "$BLK"
jqok "L folio:depends-on 前方関係 emit"       '.["folio:depends-on"][0]["@id"]=="./README.html"' "$BLK"
jqok "L folio:extends 前方関係 emit"          '.["folio:extends"][0]["@id"]=="./README.html"'    "$BLK"
njqok "L 逆グラフを emit しない (fix 導出)"    'has("dc:isReferencedBy")'            "$BLK"
has  "L fix awk anchor @type 行頭形"          '^  "@type": '                        "$BLK"
has  "L fix awk anchor key-[ 行末形"          '^  "dc:references": \[$'              "$BLK"
BASE="$WORK/base.html"; "$HERE/assemble-srs.sh" "$HERE/contract/clinic-appointment.srs.yaml" "$BASE" 2>/dev/null
BHEAD="$WORK/bhead"; awk '/<\/head>/{exit}{print}' "$BASE" > "$BHEAD"
nhas "L 後方互換 (head_graph 無し → JSON-LD 無出力)" 'application/ld\+json'          "$BHEAD"
# 空リスト省略: part_of: [] を宣言した contract は dc:isPartOf key を emit しない (空配列で emit しない)
EFXC="$WORK/fx-empty.srs.yaml"; cp "$HERE/contract/clinic-appointment.srs.yaml" "$EFXC"
printf '\nhead_graph:\n  id: ./x.html\n  part_of: []\n  references: [./README.html]\n' >> "$EFXC"
ESRS="$WORK/gen-empty.html"; "$HERE/assemble-srs.sh" "$EFXC" "$ESRS" 2>/dev/null
EBLK="$WORK/eblk.json"; awk '/<\/head>/{exit} c&&/<\/script>/{exit} c{print} /<script[^>]*application\/ld\+json/{c=1}' "$ESRS" > "$EBLK"
njqok "L 空リスト (part_of: []) は key ごと省略 (空配列 emit しない)" 'has("dc:isPartOf")' "$EBLK"
jqok  "L 非空リスト (references) は emit される"                     'has("dc:references")' "$EBLK"

echo "--- L2: mermaid-shape assembler の配線 (2 構造クラス目・JSON-LD が mermaid vendor と head 内で共存) ---"
# 挿入形は 2 種: (a) 非 mermaid 9 本 = </style> 直後 (assemble-srs 等・上の L で被覆)、
# (b) mermaid-shape 3 本 (relations/spec/verification) = mermaid vendor 行の後・</head> 直前。
# L は (a) しか起動しないため、 代表 mermaid pack (relations) を head_graph 付きで起動し (b) を per-shape 被覆する。
MFXC="$WORK/fx.spec.yaml"; cp "$HERE/contract/folio-relations.spec.yaml" "$MFXC"
cat >> "$MFXC" <<'YAML'

head_graph:
  id: ./relations.html
  part_of: [./README.html]
  references: [./constitution.html]
YAML
MREL="$WORK/gen-relations.html"; "$HERE/assemble-relations.sh" "$MFXC" "$MREL" 2>/dev/null
MHEAD="$WORK/mhead"; awk '/<\/head>/{exit}{print}' "$MREL" > "$MHEAD"
MBLK="$WORK/mblk.json"; awk '/<\/head>/{exit} c&&/<\/script>/{exit} c{print} /<script[^>]*application\/ld\+json/{c=1}' "$MREL" > "$MBLK"
has  "L2 mermaid vendor が head に load"       'mermaid\.min\.js'          "$MHEAD"
has  "L2 JSON-LD が head 内に共存 (mermaid と両立)" 'application/ld\+json'      "$MHEAD"
has  "L2 folio-doc-type meta (mermaid-shape)"  '<meta name="folio-doc-type" content="spec">' "$MHEAD"
jqok "L2 JSON-LD valid (mermaid-shape)"        '.'                          "$MBLK"
jqok "L2 @id 正しい (mermaid-shape)"           '.["@id"]=="./relations.html"' "$MBLK"
# JSON-LD が mermaid vendor 行より後・</head> 内 (mermaid script が head を早期に閉じない = 共存順)
MV=$(grep -n 'mermaid\.min\.js' "$MHEAD" | head -1 | cut -d: -f1)
MJ=$(grep -n 'application/ld+json' "$MHEAD" | head -1 | cut -d: -f1)
if [[ -n "$MV" && -n "$MJ" && "$MV" -lt "$MJ" ]]; then ok "L2 JSON-LD が mermaid vendor 行より後 (共存順)"; else bad "L2 JSON-LD が mermaid vendor 行より後 (共存順)"; fi

# --- scan corpus (spec/ に生成 SRS + README) ---
FX="$WORK/corpus"; mkdir -p "$FX/spec" "$FX/decisions" "$FX/research"
cp "$SRS" "$FX/spec/clinic-appointment.srs.html"
# README の head JSON-LD は multi-line 形 (folio_materialize_reverse の awk anchor 要件: 単一行は
# 挿入不能で fail-closed = #89。 emit 済み生成 page も multi-line ゆえ real-world 形)。
cat > "$FX/spec/README.html" <<'EOF'
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script type="application/ld+json">
{
  "@context": { "dc": "http://purl.org/dc/terms/", "schema": "https://schema.org/", "folio": "https://folio.dev/spec/v1/" },
  "@id": "./README.html",
  "@type": "schema:TechArticle",
  "dc:title": "readme"
}
</script></head><body><header data-component="doc-cover-band"><h1>README</h1></header>
<section id="s1"><h2 id="s1h">概要</h2><p class="section-essence">概要。</p></section></body></html>
EOF

echo "--- P: 肯定実証 (inventory が生成 page を拾う = scan 到達) ---"
"$FOLIO" inventory --root "$FX" >/dev/null 2>&1
INV="$WORK/inventory.json"
if [[ -f "$INV" ]]; then ok "P inventory.json 生成"; else bad "P inventory.json 生成"; fi
jqok "P 生成 SRS が inventory に載る" '[.specs[]["@id"]] | index("spec/clinic-appointment.srs.html")' "$INV"
jqok "P doc-type=srs 反映"           '.specs[]|select(.["@id"]=="spec/clinic-appointment.srs.html")|.["doc-type"]=="srs"' "$INV"

echo "--- R: 逆グラフ導出 (folio fix) ---"
nhas "R fix 前 README に逆グラフ無し" 'isReferencedBy' "$FX/spec/README.html"
"$FOLIO" fix --root "$FX" >/dev/null 2>&1
RMH="$WORK/rmh"; awk '/<\/head>/{exit}{print}' "$FX/spec/README.html" > "$RMH"
has "R fix 後 README に dc:isReferencedBy"   'dc:isReferencedBy'          "$RMH"
has "R 逆グラフが生成 SRS を指す"            'clinic-appointment\.srs\.html' "$RMH"
FIX2="$WORK/fix2"; "$FOLIO" fix --root "$FX" > "$FIX2" 2>&1
has "R fix idempotent (already complete)"    'already complete'          "$FIX2"

echo "--- C: chrome 注入 + doc-cover-band 共存 (folio build) ---"
"$FOLIO" build --root "$FX" >/dev/null 2>&1
SRSF="$FX/spec/clinic-appointment.srs.html"
has "C chrome-top marker 注入"                '<!-- folio:chrome-top -->'          "$SRSF"
has "C breadcrumb nav 注入"                   'class="breadcrumb"'                 "$SRSF"
has "C skip-link 注入"                        'skip'                               "$SRSF"
has "C doc-cover-band 帯が共存 (置換されない)" '<header data-component="doc-cover-band"' "$SRSF"
CT=$(grep -n 'folio:chrome-top' "$SRSF" | head -1 | cut -d: -f1)
CB=$(grep -n '<header data-component="doc-cover-band"' "$SRSF" | head -1 | cut -d: -f1)
if [[ -n "$CT" && -n "$CB" && "$CT" -lt "$CB" ]]; then ok "C chrome-top が帯より前 (移動層/提示層 共存順)"; else bad "C chrome-top が帯より前 (移動層/提示層 共存順)"; fi
VO="$WORK/vo"; "$FOLIO" validate --root "$FX" > "$VO" 2>&1 || true
has "C validate jsonld structural OK"   '\[OK\] jsonld structural'       "$VO"
has "C validate broken-reverse OK"      '\[OK\] broken-reverse'          "$VO"
has "C validate link-integrity OK"      '\[OK\] internal link-integrity' "$VO"

echo "--- MK1: emit 欠落 → inventory silent-skip (vacuous-green) ---"
# corpus を 1 階層ネスト (root=case/corpus) し、 inventory の出力先 dirname(root)/inventory.json を
# case dir に分離する (admin ceiling round-1: root=$WORK/mk1 直渡しだと出力は $WORK/inventory.json で
# assertion の $M1/inventory.json は不在 → jq exit=2 を njqok が PASS 誤読 = 恒真 PASS)。
# 存在 assert + 陽性対照 (README が載る) で「実データを読んでいる」ことを構造的に pin する。
M1="$WORK/mk1/corpus"; mkdir -p "$M1/spec" "$M1/decisions" "$M1/research"
"$HERE/assemble-srs.sh" "$HERE/contract/clinic-appointment.srs.yaml" "$M1/spec/no-graph.srs.html" 2>/dev/null
cp "$FX/spec/README.html" "$M1/spec/README.html"
"$FOLIO" inventory --root "$M1" >/dev/null 2>&1
M1INV="$WORK/mk1/inventory.json"
if [[ -f "$M1INV" ]]; then ok "MK1 inventory.json が case dir に生成"; else bad "MK1 inventory.json が case dir に生成"; fi
jqok  "MK1 陽性対照: README は inventory に載る (実データ読取の証拠)" '[.specs[]["@id"]] | index("spec/README.html")' "$M1INV"
njqok "MK1 emit 無し page は inventory に載らない (silent-skip)" '[.specs[]["@id"]] | index("spec/no-graph.srs.html")' "$M1INV"

echo "--- MK2: JSON-LD 改竄 → validate FAIL + inventory WARN-skip ---"
M2="$WORK/mk2"; cp -r "$FX" "$M2"
perl -0777 -i -pe 's{"\@id": "\./clinic-appointment\.srs\.html",}{"\@id": ".\/clinic-appointment.srs.html,}' "$M2/spec/clinic-appointment.srs.html"
M2V="$WORK/m2v"; "$FOLIO" validate --root "$M2" > "$M2V" 2>&1 || true
has "MK2 validate [FAIL] jsonld structural" '\[FAIL\] jsonld structural' "$M2V"
M2I="$WORK/m2i"; "$FOLIO" inventory --root "$M2" > "$M2I" 2>&1 || true
has "MK2 inventory WARN-skip"               'parse error, skipping'      "$M2I"

echo "--- MK3: chrome drift → build --check 非 0 ---"
M3="$WORK/mk3"; cp -r "$FX" "$M3"
perl -0777 -i -pe 's{class="breadcrumb"}{class="breadcrumb-TAMPERED"}' "$M3/spec/clinic-appointment.srs.html"
if "$FOLIO" build --check --root "$M3" >/dev/null 2>&1; then bad "MK3 build --check が chrome drift を検出"; else ok "MK3 build --check が chrome drift を検出"; fi

echo "--- MK4: 逆グラフ drift → validate broken-reverse FAIL ---"
M4="$WORK/mk4"; cp -r "$FX" "$M4"
perl -0777 -i -pe 's{\s*"dc:isReferencedBy": \[\s*\{ "\@id": "\./clinic-appointment\.srs\.html" \}\s*\],?}{}' "$M4/spec/README.html"
M4V="$WORK/m4v"; "$FOLIO" validate --root "$M4" > "$M4V" 2>&1 || true
has "MK4 validate [FAIL] broken-reverse"    '\[FAIL\] broken-reverse'    "$M4V"

echo "--- MK5: hostile 自由記述値 (</script>) が script breakout しない ---"
# dc:title / folio:stakeholders は semi-trusted 著者入力。 '</script>' を含む値が escape 無しで
# script ブロックへ入ると HTML パーサが script 要素を早期に閉じ後続を live markup 化する
# (breakout / HTML injection)。 core_emit_graph_head は '<' を JSON エスケープ '<' に置換して封鎖する。
HFXC="$WORK/fx.hostile.srs.yaml"; cp "$HERE/contract/clinic-appointment.srs.yaml" "$HFXC"
yq -i '.meta.title = "Clinic </script><img src=x onerror=alert(1)>" | .meta.stakeholders = "</script><svg onload=alert(2)>"' "$HFXC"
cat >> "$HFXC" <<'YAML'

head_graph:
  id: ./hostile.srs.html
  part_of: [./README.html]
YAML
HSRS="$WORK/gen-hostile.html"; "$HERE/assemble-srs.sh" "$HFXC" "$HSRS" 2>/dev/null
HHEAD="$WORK/hhead"; awk '/<\/head>/{exit}{print}' "$HSRS" > "$HHEAD"
# BLK 抽出は最初の </script> で exit する。 breakout していれば注入 </script> で途中切断され invalid JSON になる。
HBLK="$WORK/hblk.json"; awk '/<\/head>/{exit} c&&/<\/script>/{exit} c{print} /<script[^>]*application\/ld\+json/{c=1}' "$HSRS" > "$HBLK"
jqok "MK5 hostile title でも JSON-LD block が valid (breakout で途中切断されない)" '.' "$HBLK"
jqok "MK5 title が完全復元 (</script> 込み・< は < に戻り意味不変)"          '.["dc:title"]=="Clinic </script><img src=x onerror=alert(1)>"' "$HBLK"
jqok "MK5 stakeholders も完全復元 (意味不変)"                                    '.["folio:stakeholders"]=="</script><svg onload=alert(2)>"' "$HBLK"
has  "MK5 < が \\u003c にエスケープ (breakout 封鎖)"                             '\\u003c/script>' "$HBLK"
nhas "MK5 head に live </script><img injection 無し (script 早期クローズ無し)"    '</script><img'   "$HHEAD"

echo "--- MK6: flip 時 head_graph hard-fail (switchover-harness per-shape・in-scan 限定) ---"
# switchover-harness (folio-nnqh Leg A) の head_graph hard-fail 述語を per-shape で撃つ。 harness は
# contract を独立に yq 評価し (core_emit_graph_head:113 の || return 0 silent no-emit に defer しない)、
# in-scan flip target が head_graph を欠けば FAIL。 FAIL 検出は FAIL 行専有 substring
# (SWH-HARDFAIL head_graph-missing) で行い exit code に依存しない (jyfh/MK1 規律)。 harness 実走の存在
# assert も置く。 fixture は既存 contract の copy に head_graph を append する既存パターンに限定し、 実
# contract への head_graph 投入 (folio-tco6 職掌) は一切行わない。
HARNESS="$HERE/../../scripts/switchover-harness.sh"
if [[ -f "$HARNESS" ]]; then ok "MK6 switchover-harness 実在"; else bad "MK6 switchover-harness 実在"; fi
MK6SPEC="$WORK/mk6/design-intent/spec"; mkdir -p "$MK6SPEC"
MK6SPEC_ABS="$(realpath -m "$MK6SPEC")"
# fixture 対: head_graph 欠落 と head_graph 付与 (append) を srs (非mermaid) / relations (mermaid) 両
# shape で用意する (per-shape DOM 構造クラス被覆)。 absent 側 fixture は live contract を copy し
# head_graph を明示除去 (del) して decouple する: 実 contract に head_graph が land されても
# (folio-tco6 の職掌 = folio-relations.spec.yaml は一級の flip target) MK6 の『欠落→hard-fail』実弾が
# 実 contract の head_graph 有無に依存せず安定する (forward-coupling regression 封鎖)。 生成直後に
# head_graph 不在を yq has で existence-assert (fail-closed・decouple 破れを PASS させない)。
SRS_SRC="$HERE/contract/clinic-appointment.srs.yaml"
REL_SRC="$HERE/contract/folio-relations.spec.yaml"
SRS_NOHG="$WORK/mk6-srs-nohg.yaml"; cp "$SRS_SRC" "$SRS_NOHG"; yq -i 'del(.head_graph)' "$SRS_NOHG"
if [[ "$(yq -r 'has("head_graph")' "$SRS_NOHG" 2>/dev/null)" == "false" ]]; then ok "MK6 srs-nohg fixture が head_graph 不在 (decouple 済)"; else bad "MK6 srs-nohg fixture が head_graph 不在 (decouple 済)"; fi
REL_NOHG="$WORK/mk6-rel-nohg.yaml"; cp "$REL_SRC" "$REL_NOHG"; yq -i 'del(.head_graph)' "$REL_NOHG"
if [[ "$(yq -r 'has("head_graph")' "$REL_NOHG" 2>/dev/null)" == "false" ]]; then ok "MK6 rel-nohg fixture が head_graph 不在 (decouple 済)"; else bad "MK6 rel-nohg fixture が head_graph 不在 (decouple 済)"; fi
# present 側 fixture: decouple 済 absent fixture (head_graph 無しを保証済) に head_graph を append
# (live copy への二重 append で duplicate key を生む risk を回避)。
SRS_HG="$WORK/mk6-srs-hg.yaml"; cp "$SRS_NOHG" "$SRS_HG"; printf '\nhead_graph:\n  id: ./clinic.srs.html\n  part_of: [./README.html]\n' >> "$SRS_HG"
REL_HG="$WORK/mk6-rel-hg.yaml"; cp "$REL_NOHG" "$REL_HG"; printf '\nhead_graph:\n  id: ./relations.html\n  part_of: [./README.html]\n' >> "$REL_HG"
run_hf() { bash "$HARNESS" gate-head-graph "$1" "$2" "$3" 2>&1; }   # 出力を stdout 集約 (exit 非依存判定)
# (1) srs head_graph 欠落 × in-scan 着地 → hard-fail (非mermaid shape・実弾) + harness 実走 存在 assert
O6="$(run_hf "$SRS_NOHG" "$MK6SPEC/clinic.srs.html" "$MK6SPEC_ABS")"
if [[ -n "$O6" ]]; then ok "MK6 harness 実走 (出力あり)"; else bad "MK6 harness 実走 (出力あり)"; fi
if grep -q 'SWH-HARDFAIL head_graph-missing' <<<"$O6"; then ok "MK6 srs head_graph 欠落 in-scan → hard-fail (非mermaid)"; else bad "MK6 srs head_graph 欠落 in-scan → hard-fail (非mermaid)"; fi
# (2) srs head_graph 付与 × in-scan → PASS (陽性対照)
O6="$(run_hf "$SRS_HG" "$MK6SPEC/clinic.srs.html" "$MK6SPEC_ABS")"
if grep -q 'SWH-HARDFAIL-OK present' <<<"$O6"; then ok "MK6 srs head_graph 付与 in-scan → PASS (陽性対照)"; else bad "MK6 srs head_graph 付与 in-scan → PASS (陽性対照)"; fi
# (3) relations head_graph 欠落 × in-scan → hard-fail (mermaid shape・per-shape 実弾)
O6="$(run_hf "$REL_NOHG" "$MK6SPEC/relations.html" "$MK6SPEC_ABS")"
if grep -q 'SWH-HARDFAIL head_graph-missing' <<<"$O6"; then ok "MK6 relations head_graph 欠落 in-scan → hard-fail (mermaid・per-shape)"; else bad "MK6 relations head_graph 欠落 in-scan → hard-fail (mermaid・per-shape)"; fi
# (4) relations head_graph 付与 × in-scan → PASS (per-shape 陽性対照)
O6="$(run_hf "$REL_HG" "$MK6SPEC/relations.html" "$MK6SPEC_ABS")"
if grep -q 'SWH-HARDFAIL-OK present' <<<"$O6"; then ok "MK6 relations head_graph 付与 in-scan → PASS (per-shape 陽性対照)"; else bad "MK6 relations head_graph 付与 in-scan → PASS (per-shape 陽性対照)"; fi
# (5) 陰性対照: head_graph 欠落でも out-of-scan (design-intent 直下) 着地は exempt PASS
O6="$(run_hf "$SRS_NOHG" "$WORK/mk6/design-intent/vision.html" "$MK6SPEC_ABS")"
if grep -q 'SWH-HARDFAIL-OK exempt' <<<"$O6"; then ok "MK6 head_graph 欠落でも out-of-scan 着地は exempt (陰性対照)"; else bad "MK6 head_graph 欠落でも out-of-scan 着地は exempt (陰性対照)"; fi
# (6) 陰性対照 (corpus 走査 mutant 捕捉): head_graph 欠落 page を spec dir に物理配置しても、 述語は flip
#     target 1 本のみ評価し corpus 走査しない。 head_graph 保持 target は grandfathered page の head_graph
#     不在に関わらず PASS。 述語を spec/ 全走査へ広げる mutant はここで false-RED し捕捉される。
"$HERE/assemble-srs.sh" "$SRS_NOHG" "$MK6SPEC/grandfathered-nohg.html" 2>/dev/null
# fixture 存在 assert (fail-closed): assemble-srs.sh が silent 失敗すると offending page が corpus に
# 置かれず、 corpus-走査 mutant の実弾が不在のまま item(6) が vacuous PASS する (jyfh 系恒真罠)。 生成
# ファイル非空を必須化し、 実弾不在を PASS させない。
if [[ -s "$MK6SPEC/grandfathered-nohg.html" ]]; then ok "MK6 grandfathered fixture 生成 (corpus 走査 mutant 実弾存在)"; else bad "MK6 grandfathered fixture 生成 (corpus 走査 mutant 実弾存在)"; fi
O6="$(run_hf "$SRS_HG" "$MK6SPEC/clinic.srs.html" "$MK6SPEC_ABS")"
if grep -q 'SWH-HARDFAIL head_graph-missing' <<<"$O6"; then bad "MK6 target-scope: grandfathered page 存在下でも head_graph 保持 target 非発火 (corpus 走査 mutant 捕捉)"; else ok "MK6 target-scope: grandfathered page 存在下でも head_graph 保持 target 非発火 (corpus 走査 mutant 捕捉)"; fi

echo ""
echo "test-graph-emit: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
