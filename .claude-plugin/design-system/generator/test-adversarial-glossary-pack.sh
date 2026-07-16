#!/usr/bin/env bash
# test-adversarial-glossary-pack.sh — glossary build→pack 委譲 keystone の敵対回帰 (folio-wg2l)
#
# ADR-0052 の build-orchestrates-pack (folio build が self-host の glossary.html を
# assemble-glossary.sh + inject-prose.sh へ委譲して生成する) を、 肯定実証 + per-shape mutation-kill で pin する。
# pure bash + yq (render-gate 非依存 = uv/playwright 不要) ゆえ CI deterministic floor 適格。
# exit 0 = 全 pass / 非 0 = fail-closed。
#
# ★本 suite の存在理由 (folio-wg2l self-review finding#3): 委譲・marker keystone の実弾は当初 worker の
#   untracked な local self-test にしか無く、 worktree 撤去で消える = 回帰 pin が出荷されない状態だった。
#   folio の確立した慣習 (test-adversarial-glossary-parity.sh / test-graph-emit.sh) どおり tracked + CI 配線する。
# ★per-shape 原則: 1 instance の実弾は構造差 instance の穴を証明しない (jyfh/r8k 教訓)。 glossary には
#   DOM 構造クラスが 2 つある — self-host path = pack pipeline の <h4 class="term-name"> /
#   consumer fallback path = 内部 emitter の <span class="term-name">。 両方に実弾を撃つ。
#
#   P1  committed glossary.html がリッチ版 (h4 + marker + machine 層) = 素朴 emit の取り残し封鎖
#   P2  marker の *条件* emit を per-instance 対照で pin (folio=付く / clinic=付かない: 無条件 hardcode 封鎖)
#   P3  staging rich → folio build → rich 保存 + 同期時 no-write (write-path の silent revert / TS churn 封鎖)
#   P4  inject-prose 決定性 (同一入力 2 回で byte 一致)
#   MK1 self-host path (h4 shape): リッチ glossary 1 語改竄 → nav-regen-drift RED + symdiff に語名
#   MK2 consumer fallback path (span shape): 改竄 → RED + symdiff に語名 (+ keystone 保全の陰性対照)
#   MK3 marker 除去 + 本文改竄 → 沈黙 skip でなく block (validate / build --check の対称性も pin)
#   MK4 slug 欠落 shape → fail-closed (self-review finding#1: 番人と排出器の抽出述語 differential)
#   MK5 排出器側 assert (assemble-glossary.sh) が欠落 field を exit 1 で弾く (二重化)
#   MK6 self-host + glossary contract 不在 → hard-fail (self-review finding#4: 内部 emitter への fallback 封鎖)
#   MK7 perl 不在 PATH でも改竄が RED (self-review finding#2: normalize の共有 fail-open 封鎖)
#   MK8 gate の verdict が ambient env で変わらない (self-review round2 finding#2)
#   MK9 contract の graph.principle_edge / meta.doc_id 欠落 → hard-fail (round3 finding#2: Leg 0 ④ の回帰 pin)
#   MK10 normalize の *過剰* 方向 = 裸日付の drift masking を封鎖 (round3 finding#3・MK7 と対の失敗モード)
#   MK11 self-host 述語の per-shape 実弾 = manifest 削除 / contract dir 削除 / generator dir 削除
#        (round3 finding#1: MK6 は 3 shape 中ただ 1 つの *ガード済み* shape しか撃っていなかった)
#   MK-CSS1/2/3 inline CSS shape = 源泉 srs.css の drift / 不在 / 空 (folio-zpvv self-review finding#1:
#        verify-asset-sync.sh + その 6 MK の撤去で守りを移した先を tracked に実証する。 不在と空は
#        guard から見て別の構造クラスゆえ per-shape に撃つ = 旧 gate の MK3/MK4 と MK5 の対応物)
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOLIO="$HERE/../../bin/folio"
REPO="$(cd "$HERE/../../.." && pwd)"
CON="$HERE/contract/folio-glossary.glossary.yaml"
CLINIC="$HERE/contract/clinic-appointment.glossary.yaml"
PROSE="$HERE/prose/folio-glossary.prose.yaml"
VOCAB="$REPO/design-intent/vocabulary.yaml"
GLOSS="$REPO/design-intent/glossary.html"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }

# 前提崩壊は FAIL (実弾の土台が無いまま全 MK が vacuous PASS するのを封じる)
for f in "$HERE/assemble-glossary.sh" "$HERE/inject-prose.sh" "$CON" "$CLINIC" "$PROSE" "$VOCAB" "$GLOSS" "$FOLIO"; do
  [[ -e "$f" ]] || { echo "test-adversarial-glossary-pack: 前提不在 (土台崩壊・fail-closed): $f" >&2; exit 1; }
done

# self-host staging root を組む (real repo を汚さずに folio build を撃つための最小 mini-repo)。
# ★sibling generator (spec-grandfather.manifest + contract/) を丸ごと持たせて self-host 述語を true にする。
#   design-system/srs.css も要る (assemble-glossary が inline する source・欠くと genuine 生成にならない)。
mk_selfhost() {
  local d="$1"; rm -rf "$d"
  mkdir -p "$d/.claude-plugin/design-system" "$d/design-intent"
  cp -r "$HERE" "$d/.claude-plugin/design-system/generator"
  cp "$HERE/../srs.css" "$d/.claude-plugin/design-system/srs.css"
  cp "$VOCAB" "$d/design-intent/vocabulary.yaml"
  cp "$GLOSS" "$d/design-intent/glossary.html"
}
# consumer root (sibling generator 無し = 内部 emitter の span shape)
mk_consumer() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/design-intent"
  cp "$VOCAB" "$d/design-intent/vocabulary.yaml"
}

# ---------------------------------------------------------------------------
# P1: committed glossary.html は pack pipeline のリッチ dual-audience 版
# ---------------------------------------------------------------------------
if grep -q '<h4 class="term-name">' "$GLOSS" \
   && grep -q '<meta name="folio-generated" content="folio-build">' "$GLOSS" \
   && grep -q 'data-audience="machine"' "$GLOSS"; then
  ok "P1 committed glossary.html = pack pipeline のリッチ版 (h4 + marker + machine 層)"
else
  bad "P1 committed glossary.html がリッチ版でない (素朴 emit のまま = 差替え漏れ)"
fi

# ---------------------------------------------------------------------------
# P2: marker は contract の canonical_page 由来の *条件* emit (per-instance 対照)
#     ★無条件 hardcode だと demo suite (clinic) の成果物に虚偽の「folio build 生成物」marker が付き、
#       folio build/validate の marker keystone を汚染する (fence「clinic 汚染防止」)。
# ---------------------------------------------------------------------------
if "$HERE/assemble-glossary.sh" "$CLINIC" > "$WORK/clinic.html" 2>/dev/null \
   && ! grep -q 'folio-generated' "$WORK/clinic.html"; then
  ok "P2a clinic (canonical_page 非保持) の出力に marker が付かない (demo 汚染なし)"
else
  bad "P2a clinic 出力に marker が付いた or assemble 失敗 (無条件 hardcode = keystone 汚染)"
fi
if "$HERE/assemble-glossary.sh" "$CON" > "$WORK/folio-asm.html" 2>/dev/null \
   && grep -q '<meta name="folio-generated" content="folio-build">' "$WORK/folio-asm.html"; then
  ok "P2b folio (canonical_page 保持) の出力に marker が付く (条件 emit が両方向で成立)"
else
  bad "P2b folio 出力に marker が無い (gate keystone 消失 = 沈黙 skip の恒真 PASS 化)"
fi

# ---------------------------------------------------------------------------
# P3: staging rich → folio build → rich 保存 (silent revert 封鎖) + 同期時 no-write
#     ★P3b は normalize の非空撃ち pin も兼ねる: 生成 timestamp 正規化が効いていなければ footer の
#       `date -u` 差で毎回 byte が変わり no-write が成立しない (= 本 MK が割れる)。
# ---------------------------------------------------------------------------
STG="$WORK/stage"; mk_selfhost "$STG"
before="$(sha256sum "$STG/design-intent/glossary.html" | cut -d' ' -f1)"
"$FOLIO" build --root "$STG/design-intent" >/dev/null 2>&1; brc=$?
after="$(sha256sum "$STG/design-intent/glossary.html" | cut -d' ' -f1)"
if [[ "$brc" -eq 0 ]] && grep -q '<h4 class="term-name">' "$STG/design-intent/glossary.html" \
   && grep -q '<meta name="folio-generated" content="folio-build">' "$STG/design-intent/glossary.html"; then
  ok "P3a staging: rich → folio build → rich 保存 (write-path が素朴へ silent revert しない)"
else
  bad "P3a staging: folio build 後に rich が失われた (rc=$brc = silent revert)"
fi
# ★build 成功を前提に条件づける: build が落ちると glossary は触られず before==after が *成立してしまう*
#   (vacuous PASS)。 「no-write だったから緑」と「走らなかったから緑」を弁別する。
if [[ "$brc" -ne 0 ]]; then
  bad "P3b idempotent write: 前提の folio build が失敗 (rc=$brc) — no-write を検査できない (vacuous 拒否)"
elif [[ "$before" == "$after" ]]; then
  ok "P3b idempotent write: 同期済なら no-write (生成 timestamp 正規化が効いている = churn しない)"
else
  bad "P3b folio build が byte を変えた (TS churn = 毎 build で working tree が dirty 化)"
fi

# ---------------------------------------------------------------------------
# P4: inject-prose 決定性 (同一入力 2 回で byte 一致)
# ---------------------------------------------------------------------------
"$HERE/inject-prose.sh" "$PROSE" "$WORK/folio-asm.html" "$WORK/i1.html" >/dev/null 2>&1
"$HERE/inject-prose.sh" "$PROSE" "$WORK/folio-asm.html" "$WORK/i2.html" >/dev/null 2>&1
if [[ -s "$WORK/i1.html" ]] && cmp -s "$WORK/i1.html" "$WORK/i2.html"; then
  ok "P4 inject-prose 決定性: 同一入力 2 回で byte 一致"
else
  bad "P4 inject-prose が非決定 (byte 不一致 or 空)"
fi

# ---------------------------------------------------------------------------
# MK1: self-host path (h4 shape) の 1 語改竄 → nav-regen-drift RED + symdiff に語名
# ---------------------------------------------------------------------------
sed -i 's|<h4 class="term-name">spec</h4>|<h4 class="term-name">specXQZ</h4>|' "$STG/design-intent/glossary.html"
if ! grep -q 'specXQZ' "$STG/design-intent/glossary.html"; then
  bad "MK1 setup: 改竄が適用されていない (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$STG/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q '\[nav-regen-drift\]' <<<"$out"; then
    ok "MK1a self-host path (h4): リッチ glossary の 1 語改竄 → nav-regen-drift RED"
  else
    bad "MK1a self-host path (h4): 改竄が検出されない (rc=$rc = 恒真 PASS)"
  fi
  if grep -q 'specXQZ' <<<"$out"; then
    ok "MK1b symdiff: 1 語 drift mutant の語名が violation message に出る (h4 抽出が機能)"
  else
    bad "MK1b symdiff: 改竄語名が message に出ない (h4 抽出が span 専用のまま = 診断が黙って空)"
  fi
fi

# ---------------------------------------------------------------------------
# MK3: marker 除去 + 本文改竄 → 沈黙 skip させず block (validate / build --check 対称)
#     ★marker と本文改竄を *同時に* 仕込む: marker だけ消す MK では「本文改竄が隠れる」ことを証明できない。
# ---------------------------------------------------------------------------
cp "$GLOSS" "$STG/design-intent/glossary.html"
sed -i '/<meta name="folio-generated" content="folio-build">/d' "$STG/design-intent/glossary.html"
sed -i 's|<h4 class="term-name">spec</h4>|<h4 class="term-name">HIDDEN</h4>|' "$STG/design-intent/glossary.html"
if grep -q 'folio-generated' "$STG/design-intent/glossary.html" || ! grep -q 'HIDDEN' "$STG/design-intent/glossary.html"; then
  bad "MK3 setup: marker 除去 + 本文改竄が未適用 (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$STG/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'folio-generated marker が無い' <<<"$out"; then
    ok "MK3a marker 除去: self-host で marker 欠落 → block (沈黙 skip = 本文改竄を隠す恒真 PASS の封鎖)"
  else
    bad "MK3a marker 除去が沈黙 skip された (rc=$rc = vacuous green: 本文改竄が隠れる)"
  fi
  out="$("$FOLIO" build --check --root "$STG/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'folio-generated marker が無い' <<<"$out"; then
    ok "MK3b marker 除去: build --check も対称に block (validate と lockstep)"
  else
    bad "MK3b build --check が marker 欠落を見逃す (rc=$rc = validate と非対称)"
  fi
fi

# ---------------------------------------------------------------------------
# MK4 (self-review finding#1): slug 欠落 shape → fail-closed
#     ★「明示重複」shape だけを撃つ MK では取りこぼす別クラス: 番人 (bin/folio) は `// ""` +
#       grep -v '^$' で欠落 slug を捨て、 排出器 (assemble-glossary.sh) の q() は欠落キーで
#       リテラル "null" を返す。 番人が捨てる値集合と排出器が衝突定数 term-null へ写す値集合が
#       正確に一致するため、 欠落 shape だけが素通りして id="term-null" が重複した glossary.html が
#       書き込まれ、 validate/build --check は共に clean を報告していた (実弾で再現済)。
# ---------------------------------------------------------------------------
F1="$WORK/f1"; mk_selfhost "$F1"
F1CON="$F1/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
gl_before="$(sha256sum "$F1/design-intent/glossary.html" | cut -d' ' -f1)"
yq -i 'del(.terms[0].slug)' "$F1CON"
if [[ "$(yq -r '.terms[0].slug // "MISSING"' "$F1CON")" != "MISSING" ]]; then
  bad "MK4 setup: slug 削除が未適用 (MK 空撃ち)"
else
  out="$("$FOLIO" build --root "$F1/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 2 ]] && grep -q 'slug 欠落' <<<"$out"; then
    ok "MK4a slug 欠落 shape: folio build が exit 2 (fail-closed)"
  else
    bad "MK4a slug 欠落 shape: build が hard-fail しない (rc=$rc = term-null 衝突を書き込む経路)"
  fi
  # ★rc だけ見ない: 書込済みの劣化 (term-null 重複) を実弾で確認する
  if [[ "$(sha256sum "$F1/design-intent/glossary.html" | cut -d' ' -f1)" == "$gl_before" ]] \
     && [[ "$(grep -c 'id="term-null"' "$F1/design-intent/glossary.html")" -eq 0 ]]; then
    ok "MK4b slug 欠落 shape: committed glossary.html は byte 不変・term-null 重複が書かれない"
  else
    bad "MK4b slug 欠落 shape: glossary.html が term-null 重複つきで書き換わった (anchor 破壊が land)"
  fi
  out="$("$FOLIO" validate --root "$F1/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'glossary-slug' <<<"$out"; then
    ok "MK4c slug 欠落 shape: validate が [glossary-slug] で RED (明示重複 shape と同じ診断語彙)"
  else
    bad "MK4c slug 欠落 shape: validate が clean を報告 (rc=$rc = 抽出述語 differential の再発)"
  fi
  out="$("$FOLIO" build --check --root "$F1/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]]; then
    ok "MK4d slug 欠落 shape: build --check も RED (3-site lockstep)"
  else
    bad "MK4d slug 欠落 shape: build --check が clean (rc=$rc = validate と非対称)"
  fi
fi
# 陽性対照 (既存の検出できる shape が壊れていないこと): 明示重複 slug → RED
F1B="$WORK/f1b"; mk_selfhost "$F1B"
yq -i '.terms[1].slug = (.terms[0].slug)' "$F1B/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
out="$("$FOLIO" validate --root "$F1B/design-intent" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'glossary-slug' <<<"$out"; then
  ok "MK4e 陽性対照: 明示重複 slug shape は従来どおり [glossary-slug] で RED"
else
  bad "MK4e 陽性対照: 明示重複 slug が検出されない (rc=$rc = 既存 shape の退行)"
fi
# 陰性対照 (偽陽性でないこと): 無改竄 contract → glossary 系 gate は緑
F1C="$WORK/f1c"; mk_selfhost "$F1C"
out="$("$FOLIO" validate --root "$F1C/design-intent" 2>&1)"
if grep -q '\[OK\] glossary' <<<"$out" && ! grep -q 'glossary-slug' <<<"$out"; then
  ok "MK4f 陰性対照: 無改竄 contract は [OK] glossary (slug gate が偽陽性を出さない)"
else
  bad "MK4f 陰性対照: 無改竄 contract が slug gate で誤 RED (偽陽性)"
fi

# ---------------------------------------------------------------------------
# MK5 (self-review finding#1・二重化): 排出器側にも欠落 assert がある
#     ★番人 (bin/folio) だけに置くと、 assemble-glossary.sh を直接叩く他経路 (pack 手動実行・将来の
#       別 orchestrator) で同じ term-null 衝突が復活する。 排出器も単独で fail-closed であること。
# ---------------------------------------------------------------------------
cp "$CON" "$WORK/mk5.yaml"; yq -i 'del(.terms[0].slug)' "$WORK/mk5.yaml"
if "$HERE/assemble-glossary.sh" "$WORK/mk5.yaml" >/dev/null 2>"$WORK/mk5.err"; then
  bad "MK5 排出器: slug 欠落 contract で assemble が成功した (term-null 衝突を emit する)"
elif grep -q 'slug' "$WORK/mk5.err"; then
  ok "MK5 排出器: slug 欠落 contract → assemble-glossary.sh が exit 1 (番人と二重化)"
else
  bad "MK5 排出器: assemble が落ちたが slug 診断でない ($(tr '\n' ' ' < "$WORK/mk5.err"))"
fi

# ---------------------------------------------------------------------------
# MK6 (self-review finding#4): self-host 述語 true のまま glossary contract 除去 → hard-fail
#     ★委譲の前提崩れを内部 emitter へ fallback させると folio build 1 回で rich→素朴の silent revert が
#       起き (61838B/h4×36 → 12036B/span×36)、 以後 committed(素朴)==emit(素朴) で nav-regen-drift が
#       恒真 PASS 化する。 「contract を消せば nav-regen-drift が FAIL するから loud」は *build を
#       走らせない場合にしか成立しない* — violation message 自身が「folio build で再生成」を指示するため、
#       指示どおり remediate した瞬間に証拠が破壊され gate が緑になる。 その modality を本 MK が撃つ。
# ---------------------------------------------------------------------------
F4="$WORK/f4"; mk_selfhost "$F4"
rm -f "$F4/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
g4_before="$(sha256sum "$F4/design-intent/glossary.html" | cut -d' ' -f1)"
out="$("$FOLIO" build --root "$F4/design-intent" 2>&1)"; rc=$?
g4_after="$(sha256sum "$F4/design-intent/glossary.html" | cut -d' ' -f1)"
if [[ "$rc" -eq 2 ]] && grep -q '委譲' <<<"$out"; then
  ok "MK6a contract 不在: self-host で folio build が exit 2 (内部 emitter へ fallback しない)"
else
  bad "MK6a contract 不在: build が hard-fail しない (rc=$rc = 素朴への silent revert 経路)"
fi
if [[ "$g4_before" == "$g4_after" ]] && grep -q '<h4 class="term-name">' "$F4/design-intent/glossary.html"; then
  ok "MK6b contract 不在: committed glossary.html は rich のまま byte 不変 (silent revert 不発)"
else
  bad "MK6b contract 不在: glossary.html が素朴へ書き換わった (rich→素朴の silent revert が実発生)"
fi
out="$("$FOLIO" validate --root "$F4/design-intent" 2>&1)"; rc=$?
# ★judge は violation tag `[nav-regen-drift]` (行内タグ) を撃つ: 素の 'nav-regen-drift' で grep すると
#   status 行「[OK] nav-regen-drift」にも一致し、 fallback mutant (= 素朴へ revert 後 committed==emit で
#   恒真 PASS 化した状態) を PASS と誤判定する = MK 自身が vacuous になる (実際に mutant A で観測した)。
if [[ "$rc" -eq 1 ]] && grep -q '\[nav-regen-drift\]' <<<"$out"; then
  ok "MK6c contract 不在: validate も委譲の前提崩れで block (再生成不能を clean にしない)"
else
  bad "MK6c contract 不在: validate が clean (rc=$rc = 再生成不能の恒真 PASS 化)"
fi

# ---------------------------------------------------------------------------
# MK7 (self-review finding#2): perl 不在でも改竄が RED
#     ★normalize は 3 消費点 (validate nav-regen-drift / build --check / build 書込 path) が共有する
#       単一 helper ゆえ、 実行不能で無出力に倒れると比較の両辺が空 file になり「空==空=差分なし」が
#       成立して 3 site が同時に fail-open する。 実測 (旧 perl 実装 + perl 不在 PATH): nav-regen-drift が
#       改竄を [OK]・build が偽「同期済 (no-write)」を報告した。 sed 化 (宣言 toolchain 内) で塞いだ回帰 pin。
#     ★consumer path を撃つ: 内部 emitter 出力は「生成: <b>」接頭辞を持たず normalize は純 no-op ゆえ、
#       perl 依存は consumer にとって無関係のはずだが、 旧実装ではその失敗が両辺を空にしていた。
# ---------------------------------------------------------------------------
NOPERL="$WORK/noperl-bin"; mkdir -p "$NOPERL"
IFS=: read -ra _pdirs <<< "$PATH"
for _d in "${_pdirs[@]}"; do
  [[ -d "$_d" ]] || continue
  for _f in "$_d"/*; do
    _b="$(basename "$_f")"
    case "$_b" in perl*) continue ;; esac
    [[ -e "$NOPERL/$_b" ]] || ln -sf "$_f" "$NOPERL/$_b" 2>/dev/null
  done
done
if PATH="$NOPERL" command -v perl >/dev/null 2>&1; then
  bad "MK7 setup: perl 不在 PATH の構築に失敗 (perl がまだ見える = MK 空撃ち)"
elif ! PATH="$NOPERL" command -v yq >/dev/null 2>&1 || ! PATH="$NOPERL" command -v jq >/dev/null 2>&1; then
  bad "MK7 setup: perl 不在 PATH に yq/jq が無い (土台崩壊・別要因で RED になり検査軸がすり替わる)"
else
  CNS="$WORK/noperl-consumer"; mk_consumer "$CNS"
  PATH="$NOPERL" "$FOLIO" build --root "$CNS/design-intent" >/dev/null 2>&1
  if ! grep -q '<span class="term-name">' "$CNS/design-intent/glossary.html" 2>/dev/null; then
    bad "MK7 setup: perl 不在で consumer の内部 emitter が生成できない (前提崩壊)"
  else
    sed -i 's|term-name">spec<|term-name">specNOPERL<|' "$CNS/design-intent/glossary.html"
    if ! grep -q 'specNOPERL' "$CNS/design-intent/glossary.html"; then
      bad "MK7 setup: 改竄が適用されていない (MK 空撃ち)"
    else
      out="$(PATH="$NOPERL" "$FOLIO" validate --root "$CNS/design-intent" 2>&1)"
      # ★判定は *当該 signal* を撃つ (rc 全体を見ない): この最小 consumer fixture は index に link が無く
      #   readability-floor で正当に rc=1 になる = 無関係の violation。 rc で判定すると検査軸が
      #   「normalize の fail-open」から「fixture が全 gate 緑か」へすり替わる。
      if grep -q '\[nav-regen-drift\]' <<<"$out" && grep -q 'specNOPERL' <<<"$out"; then
        ok "MK7a perl 不在: consumer の改竄が nav-regen-drift RED (normalize の共有 fail-open が塞がれている)"
      else
        bad "MK7a perl 不在: 改竄が [OK] で素通り (normalize 失敗 → 両辺が空 → 空==空 の恒真 PASS)"
      fi
      out="$(PATH="$NOPERL" "$FOLIO" build --check --root "$CNS/design-intent" 2>&1)"; rc=$?
      if [[ "$rc" -eq 1 ]]; then
        ok "MK7b perl 不在: build --check も RED (validate と lockstep)"
      else
        bad "MK7b perl 不在: build --check が clean (rc=$rc)"
      fi
      out="$(PATH="$NOPERL" "$FOLIO" build --root "$CNS/design-intent" 2>&1)"
      if grep -q 'wrote .*glossary.html' <<<"$out" && ! grep -q 'specNOPERL' "$CNS/design-intent/glossary.html"; then
        ok "MK7c perl 不在: build 書込 path が改竄を再生成 (偽「同期済 (no-write)」を報告しない)"
      else
        bad "MK7c perl 不在: build が改竄を放置 (偽「同期済」= 劣化を no-write で温存)"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# MK2: consumer fallback path (span shape) の改竄 → RED + symdiff に語名
#     + keystone 保全の陰性対照 (self-host の marker 例外が consumer を巻き込んでいないこと)
# ---------------------------------------------------------------------------
CONS="$WORK/consumer"; mk_consumer "$CONS"
"$FOLIO" build --root "$CONS/design-intent" >/dev/null 2>&1
if grep -q '<span class="term-name">' "$CONS/design-intent/glossary.html" 2>/dev/null; then
  ok "MK2a consumer fallback: sibling generator 無し root は内部 emitter (span shape) で生成"
else
  bad "MK2a consumer fallback: 内部 emitter が働かない (consumer が壊れた)"
fi
sed -i 's|<span class="term-name">spec</span>|<span class="term-name">specZZQ</span>|' "$CONS/design-intent/glossary.html"
if ! grep -q 'specZZQ' "$CONS/design-intent/glossary.html"; then
  bad "MK2b setup: 改竄が適用されていない (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$CONS/design-intent" 2>&1)"
  if grep -q '\[nav-regen-drift\]' <<<"$out" && grep -q 'specZZQ' <<<"$out"; then
    ok "MK2b consumer fallback path (span): 改竄 → nav-regen-drift RED + symdiff に語名 (span 抽出が機能)"
  else
    bad "MK2b consumer fallback path (span): 改竄が検出されない/語名が出ない"
  fi
fi
# 陰性対照: consumer の marker 無し glossary は hand-authored = skip のまま (self-host 例外の scope-leak 封鎖)
"$FOLIO" build --root "$CONS/design-intent" >/dev/null 2>&1
sed -i '/<meta name="folio-generated" content="folio-build">/d' "$CONS/design-intent/glossary.html"
if grep -q 'folio-generated' "$CONS/design-intent/glossary.html"; then
  bad "MK2c setup: consumer の marker 除去が未適用 (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$CONS/design-intent" 2>&1)"
  if ! grep -q 'folio-generated marker が無い' <<<"$out" && ! grep -q 'glossary.html.*\[nav-regen-drift\]' <<<"$out"; then
    ok "MK2c keystone 保全: consumer の marker 無し glossary は hand-authored 扱いで skip (self-host 例外が consumer を巻き込まない)"
  else
    bad "MK2c consumer の keystone が壊れた (hand-authored glossary を持つ consumer が誤 block される)"
  fi
fi

# ---------------------------------------------------------------------------
# MK8 (self-review round2 finding#2): gate の verdict は ambient env で変わらない
#     ★裁定の機械化: fence は「self-host 検出 = gate (s) 同一述語 (spec-grandfather.manifest + contract/
#       両実在) を共通 helper へ呼ぶ。 marker 有無・glossary_map 非空・env を self-host 信号に代用するのは
#       裁定違反かつ drift (禁止)」と定める。 旧実装は pack_emit の安全弁に folio_glossary_vocab_path を
#       含み、 同 helper が $CLAUDE_PLUGIN_ROOT/design-intent/vocabulary.yaml を候補に持つため *別 repo* の
#       vocab が解決して弁が発火せず、 in-tree fixture が env の有無で clean ⇄ nav-regen-drift RED に
#       反転した (CI は bare ゆえ緑・Claude Code 下では赤 = gate が env で verdict を変える = gate 不成立)。
#     ★本 MK は tests/runner.sh / ci.yml が bare で走るために踏まれない分岐を、 env を明示注入して撃つ。
# ---------------------------------------------------------------------------
# (a) 陰性対照: sibling generator を持つ (= gate (s) の検査対象ゆえ self-host 判定 true) が glossary を
#     持たない fixture は、 env の有無に依らず glossary の nav-regen-drift を出さない (偽陽性なし)
FX="$REPO/tests/fixtures/spec-contract-pairing-clean"
if [[ ! -f "$FX/.claude-plugin/design-system/generator/spec-grandfather.manifest" ]] \
   || [[ ! -d "$FX/.claude-plugin/design-system/generator/contract" ]]; then
  bad "MK8 setup: fixture が sibling generator を持たない (self-host 判定を踏まず MK 空撃ち): $FX"
elif [[ -f "$FX/design-intent/glossary.html" ]] \
     || [[ -f "$FX/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml" ]]; then
  bad "MK8 setup: fixture が glossary を持ってしまっている (「生成対象が無い root」の実弾でない)"
else
  mk8_fail=0
  for envstate in unset set; do
    if [[ "$envstate" == set ]]; then
      out="$(CLAUDE_PLUGIN_ROOT="$REPO" "$FOLIO" validate --root "$FX/design-intent" 2>&1)"
    else
      out="$(env -u CLAUDE_PLUGIN_ROOT "$FOLIO" validate --root "$FX/design-intent" 2>&1)"
    fi
    if grep -q 'glossary.html.*\[nav-regen-drift\]' <<<"$out"; then
      bad "MK8a env=${envstate}: glossary 不在 fixture が偽 RED (env が verdict を決めている): $(grep 'nav-regen-drift' <<<"$out" | head -1)"
      mk8_fail=1
    fi
  done
  [[ "$mk8_fail" -eq 0 ]] && ok "MK8a 陰性対照: glossary を持たない self-host fixture は env set/unset の双方で偽陽性なし"
fi
# (b) 対称性: 「委譲元の消失」(contract 除去 + rich glossary.html 在り) の hard-fail は env に依らず同一 verdict
F8="$WORK/f8"; mk_selfhost "$F8"
rm -f "$F8/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
out_unset="$(env -u CLAUDE_PLUGIN_ROOT "$FOLIO" build --root "$F8/design-intent" 2>&1)"; rc_unset=$?
mk_selfhost "$F8"
rm -f "$F8/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
out_set="$(CLAUDE_PLUGIN_ROOT="$REPO" "$FOLIO" build --root "$F8/design-intent" 2>&1)"; rc_set=$?
if [[ "$rc_unset" -eq 2 && "$rc_set" -eq 2 ]] && grep -q '委譲' <<<"$out_unset" && grep -q '委譲' <<<"$out_set"; then
  ok "MK8b 対称性: 委譲元の消失は env set/unset の双方で同一 hard-fail (rc=2) — env は self-host 信号でない"
else
  bad "MK8b 対称性: env で verdict が分岐 (unset rc=$rc_unset / set rc=$rc_set)"
fi

# ---------------------------------------------------------------------------
# MK9 (self-review round3 finding#2): 委譲 precondition (contract の graph.principle_edge / meta.doc_id)
#     欠落 → hard-fail。
#     ★per-shape 原則の自己適用 (jyfh/r8k): MK6 は「contract *file* 不在」・MK4/MK5 は「slug 欠落」という
#       別 shape であり、 file 存在検査の実弾は *field 欠落* 検査の穴を証明しない。 実測: precondition
#       block を丸ごと削除した mutant に対し本 suite は 28 passed/0 failed で GREEN 生存し、 worker の
#       untracked local self-test (S10) だけが RED になった = 回帰 pin が出荷されていなかった。
#     ★本 2 field は HTML へ render されず verify-graph.sh が消費する graph メタ: 回帰時の被害は artifact
#       破壊でなく「graph gate の入力が欠けたまま委譲が通る」。 それでも Leg 0 ④ / 契約 (A) の明示要求ゆえ pin。
# ---------------------------------------------------------------------------
for mk9_field in '.graph.principle_edge' '.meta.doc_id'; do
  F9="$WORK/f9$(printf '%s' "$mk9_field" | tr -d './')"; mk_selfhost "$F9"
  yq -i "del(${mk9_field})" "$F9/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml"
  # setup assert: 改竄が実適用された (MK 空撃ち封鎖)
  if [[ -n "$(yq -r "${mk9_field} // \"\"" "$F9/.claude-plugin/design-system/generator/contract/folio-glossary.glossary.yaml")" ]]; then
    bad "MK9 setup: ${mk9_field} の削除が未適用 (MK 空撃ち)"; continue
  fi
  g9_before="$(sha256sum "$F9/design-intent/glossary.html" | cut -d' ' -f1)"
  out="$("$FOLIO" build --root "$F9/design-intent" 2>&1)"; rc=$?
  g9_after="$(sha256sum "$F9/design-intent/glossary.html" | cut -d' ' -f1)"
  if [[ "$rc" -eq 2 ]] && grep -q '委譲の前提' <<<"$out"; then
    ok "MK9a 委譲 precondition: contract の ${mk9_field} 欠落 → folio build が exit 2 (素朴 emitter へ silent fallback しない)"
  else
    bad "MK9a 委譲 precondition: ${mk9_field} 欠落が hard-fail にならない (rc=$rc = silent revert 経路)"
  fi
  if [[ "$g9_before" == "$g9_after" ]] && grep -q '<h4 class="term-name">' "$F9/design-intent/glossary.html"; then
    ok "MK9b 委譲 precondition: ${mk9_field} 欠落時も committed glossary.html は rich のまま byte 不変"
  else
    bad "MK9b 委譲 precondition: ${mk9_field} 欠落で glossary.html が素朴へ書き換わった (silent revert が実発生)"
  fi
done

# ---------------------------------------------------------------------------
# MK10 (self-review round3 finding#3): normalize の *過剰* 方向 = drift masking の封鎖。
#     ★MK7 (直上) と対の失敗モード: MK7 は normalize が「効かない」(両辺が空 file → 空==空 の共有 fail-open)
#       方向を撃つ。 本 MK は normalize が「効きすぎる」(実 drift を飲み込む) 方向を撃つ。 同一 helper
#       (folio_glossary_normalize) の 2 つの失敗モードは別 shape ゆえ、 過小方向の実弾は過剰方向の穴を
#       証明しない (per-shape 原則)。
#     ★fence: normalize の scope は「生成: <b>YYYY-MM-DD HH:MM</b>」の *部分文字列* のみ。 裸日付の全域置換や
#       行削除は版日付/承認日/検証状態を潰す drift masking ゆえ禁止。 実測: 正しい TS 正規化を残したまま
#       `s|[0-9]{4}-[0-9]{2}-[0-9]{2} 生成|@@D@@ 生成|g` を足した「現実的な normalize 拡張」mutant
#       (fence が名指しで禁じた形) に対し、 本 suite は MK10 追加前は 28 passed/0 failed で GREEN 生存した。
#     ★committed の *裸日付* (approval 欄「2026-06-24 生成」) を改竄する: emit 側と食い違うため、 正しい
#       normalize なら nav-regen-drift RED。 正規化が裸日付まで飲み込んでいれば見逃す = 本 MK が割る。
# ---------------------------------------------------------------------------
F10="$WORK/f10"; mk_selfhost "$F10"
sed -i 's/2026-06-24 生成/2026-01-01 生成/' "$F10/design-intent/glossary.html"
# setup assert: 改竄が実適用された (MK 空撃ち封鎖・裸日付が fixture から消えた場合に沈黙 PASS しない)
if cmp -s "$GLOSS" "$F10/design-intent/glossary.html"; then
  bad "MK10 setup: 裸日付 (承認欄) の改竄が未適用 — fixture が想定文字列を持たない (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$F10/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q '\[nav-regen-drift\]' <<<"$out"; then
    ok "MK10 normalize scope: 裸日付 (承認欄) の改竄 → nav-regen-drift RED (正規化が裸日付を潰していない = drift masking なし)"
  else
    bad "MK10 normalize scope: 裸日付の改竄が見逃された (rc=$rc = 正規化が効きすぎ = drift masking)"
  fi
fi

# ---------------------------------------------------------------------------
# MK11 (self-review round3 finding#1): self-host 述語の *部分成立* / 消滅 を per-shape で撃つ。
#     ★MK6 は「述語 true のまま contract file だけ除去」= 3 shape 中ただ 1 つの *ガード済み* shape であり、
#       fallback 封鎖の証明になっていなかった (per-shape 原則の自己適用漏れ)。 述語は
#       `[[ -f spec-grandfather.manifest && -d contract ]]` の AND ゆえ、 *片翼* が欠けると旧実装は
#       return 1 = consumer と同一視し、 dispatcher が pack_emit に到達せず内部 emitter へ fallback した。
#       pack_emit の「委譲元の消失 = return 4」ガードは述語 true でなければ一度も実行されず無効化される。
#       実弾 (旧実装): (a) manifest 削除 / (b) contract/ dir 削除 の双方で folio build が rc=0 のまま
#       61838B/h4×36 → 12036B/span×36 を書込み、 以後 [OK] glossary / [OK] nav-regen-drift /
#       build --check rc=0 = 恒真 PASS 化した。
#     ★shape ごとの封鎖機構が異なるため 3 shape を個別に撃つ:
#       (a)(b) = tri-state 述語 (rc=2 = 前提崩れ) → dispatcher が hard-fail へ写像。
#       (c) generator dir ごと消滅 = 真の consumer と *構造的に区別不能* (述語では塞げない) ため、
#           build 書込 path の anti-downgrade 安全弁 (pack 生成物 h4 を内部 emitter 出力 span で
#           上書きしない) が封鎖する。
#     ★MK6 は述語 true 側の陽性対照として残置 (本 MK と相補)。
# ---------------------------------------------------------------------------
#     ★judge は「rc≠0」で *終わらせない* (本 MK 自身の初版がそれで vacuous だった実測): 述語を AND-only へ
#       戻した mutant でも、 shape (a)(b) は anti-downgrade 安全弁が別経路で拾って rc=2 を返すため
#       「rc≠0 + byte 不変 + --check RED」は 3 shape とも成立し、 mutant が 42 passed/0 failed で生存した。
#       つまり *どの封鎖機構が働いたか* まで判定しないと tri-state を pin できない。 よって shape 別に
#       診断文言を撃ち分け、 加えて gate (s) の「沈黙消滅」封鎖 (MK11d) を独立に assert する
#       (旧実装では manifest 削除で spec-contract-pairing の行が出力から完全消滅した = grep -c 0)。
for mk11_shape in manifest contract-dir generator-dir; do
  F11="$WORK/f11-${mk11_shape}"; mk_selfhost "$F11"
  G11="$F11/.claude-plugin/design-system/generator"
  case "$mk11_shape" in
    manifest)      rm -f  "$G11/spec-grandfather.manifest" ;;
    contract-dir)  rm -rf "$G11/contract" ;;
    generator-dir) rm -rf "$G11" ;;
  esac
  # setup assert: 削除が実適用された (MK 空撃ち封鎖)
  case "$mk11_shape" in
    manifest)      [[ -e "$G11/spec-grandfather.manifest" ]] && { bad "MK11 setup(${mk11_shape}): 削除が未適用 (MK 空撃ち)"; continue; } ;;
    contract-dir)  [[ -e "$G11/contract" ]] && { bad "MK11 setup(${mk11_shape}): 削除が未適用 (MK 空撃ち)"; continue; } ;;
    generator-dir) [[ -e "$G11" ]] && { bad "MK11 setup(${mk11_shape}): 削除が未適用 (MK 空撃ち)"; continue; } ;;
  esac
  # shape 別の *期待される封鎖機構* を文言で pin する:
  #   (a)(b) 片翼欠落 → tri-state 述語 rc=2 → dispatcher の「委譲の前提崩れ」hard-fail
  #   (c) generator dir 消滅 → 述語では区別不能 (正当に consumer 分岐) → 書込直前の anti-downgrade 安全弁
  case "$mk11_shape" in
    generator-dir) mk11_want='劣化書込'; mk11_why='anti-downgrade 安全弁 (述語では consumer と区別不能な shape)' ;;
    *)             mk11_want='委譲の前提'; mk11_why='tri-state 述語 rc=2 → dispatcher hard-fail' ;;
  esac
  g11_before="$(sha256sum "$F11/design-intent/glossary.html" | cut -d' ' -f1)"
  out="$("$FOLIO" build --root "$F11/design-intent" 2>&1)"; rc=$?
  g11_after="$(sha256sum "$F11/design-intent/glossary.html" | cut -d' ' -f1)"
  if [[ "$rc" -eq 2 ]] && grep -q "$mk11_want" <<<"$out"; then
    ok "MK11a(${mk11_shape}): folio build が exit 2 + 期待経路で block — ${mk11_why}"
  else
    bad "MK11a(${mk11_shape}): 期待の封鎖機構で落ちていない (rc=$rc・期待文言「${mk11_want}」不在 = ${mk11_why} が働いていない)"
  fi
  if [[ "$g11_before" == "$g11_after" ]] && grep -q '<h4 class="term-name">' "$F11/design-intent/glossary.html"; then
    ok "MK11b(${mk11_shape}): committed glossary.html は rich のまま byte 不変 (rich→素朴の silent revert 不発)"
  else
    bad "MK11b(${mk11_shape}): glossary.html が素朴へ書き換わった (61838B/h4 → 12036B/span の silent revert が実発生)"
  fi
  # ★build --check も RED (証拠破壊後の恒真 PASS 化を封鎖)
  out="$("$FOLIO" build --check --root "$F11/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    ok "MK11c(${mk11_shape}): build --check も RED (rc=$rc = 再生成不能/drift を clean にしない)"
  else
    bad "MK11c(${mk11_shape}): build --check が clean (rc=0 = 恒真 PASS 化)"
  fi
  # ★MK11d: gate (s) spec-contract-pairing の「沈黙消滅」封鎖 (片翼欠落 shape のみ)。
  #   旧実装は片翼欠落を rc=1 = 非該当 root と同一視し contract_seen=0 のまま報告行ごと消していた。
  #   generator dir 消滅 shape は *真の consumer と同型* ゆえ gate (s) 非該当が正しく、 本 assert の対象外
  #   (ここで violation を要求すると consumer を誤検出する実装を強制してしまう)。
  out="$("$FOLIO" validate --root "$F11/design-intent" 2>&1)"; rc=$?
  if [[ "$mk11_shape" == "generator-dir" ]]; then
    if grep -q '\[spec-contract-pairing\]' <<<"$out"; then
      bad "MK11d(${mk11_shape}): generator dir を持たない root (= consumer と同型) を spec-contract-pairing が誤検出した"
    else
      ok "MK11d(${mk11_shape}) 陰性対照: generator dir 非実在は gate (s) 非該当 (consumer 誤検出なし)"
    fi
  elif [[ "$rc" -eq 1 ]] && grep -q '\[spec-contract-pairing\]' <<<"$out"; then
    ok "MK11d(${mk11_shape}): 片翼欠落で gate (s) が violation を報告 (前提崩れを「非該当 root」として沈黙消滅させない)"
  else
    bad "MK11d(${mk11_shape}): gate (s) の報告行が消滅 (rc=$rc = 前提崩れを非該当 root と同一視 = 沈黙 skip)"
  fi
done

# ---------------------------------------------------------------------------
# MK-CSS1/2 (folio-zpvv self-review finding#1): inline CSS shape の per-shape 実弾。
#     ★背景: glossary-pack は元々 srs.css を <link> 外部参照し、 配信 root (design-intent/ 直下) へ置いた
#       その copy は page の byte 比較の *外側* にあったため canonical-drift / nav-regen-drift が検出できず、 専用の
#       同期 gate (verify-asset-sync.sh) + その検出力 MK 6 本が唯一の番人だった。 folio-zpvv で CSS を
#       inline 化し、 守りを (1) nav-regen-drift の byte 検査への fold-in と (2) assemble-glossary.sh の
#       存在 + サイズ下限 (100 byte) の fail-closed guard の 2 点へ移して同期 gate を撤去した。
#       ★下限は飾りでない: `-f` 単独では 0 byte を通し、 未スタイル page が committed を上書きした瞬間
#       committed==fresh となって (1) の byte 検査ごと汚染される (旧 gate の MK5 が撃っていた shape)。
#     ★per-shape 原則 (jyfh/r8k): 置換後の守りにも実弾を対で tracked 化しないと、 撤去した gate の検出力
#       証明だけが消えて「gate 本体だけが tree に残り誰も検出力を保証しない」状態 (本 suite header が
#       名指しで存在理由に挙げた状態) を別の場所で再生産する。 既存 MK10 が pin するのは「裸日付の改竄 →
#       nav-regen-drift RED」であり、 CSS byte が page に入る本 shape は別の構造クラスゆえ穴を証明しない。
#     ★退行経路: emit_head の `cat "$CSS"` が `2>/dev/null || true` 化される / guard が消される /
#       nav-regen-drift が glossary で SKIP へ倒れる、 のいずれでも守りは沈黙消滅し committed==fresh の
#       恒真 PASS 化が起きる。 MK-CSS1 が (1) を、 MK-CSS2 が (2) を撃つ。
# ---------------------------------------------------------------------------
# MK-CSS1: 源泉 srs.css の 1 byte drift → nav-regen-drift RED (inline fold-in の実証 = 同期 gate 撤去の正当化)
#     ★陰性対照を対で置く (MK-CSS1a): 「改竄 → RED」だけでは *CSS byte が RED の原因* を証明できない。
#       mini-repo が別要因で恒常的に nav-regen-drift RED なら本 MK は ambient RED を記録するだけの
#       vacuous な assert に堕ちる。 無改竄 = [OK] / 改竄 = RED の対で discrimination を pin する。
FC1="$WORK/fcss1"; mk_selfhost "$FC1"
FC1CSS="$FC1/.claude-plugin/design-system/srs.css"
out="$("$FOLIO" validate --root "$FC1/design-intent" 2>&1)"
if grep -q '\[OK\] nav-regen-drift' <<<"$out"; then
  ok "MK-CSS1a 陰性対照: 無改竄 mini-repo は [OK] nav-regen-drift (直後の RED が CSS byte 由来であることの対照)"
else
  bad "MK-CSS1a 陰性対照: 無改竄 mini-repo が既に nav-regen-drift RED (ambient RED = MK-CSS1b が原因を証明できない vacuous な assert に堕ちる)"
fi
css1_before="$(sha256sum "$FC1CSS" | cut -d' ' -f1)"
printf '/*QZX*/' >> "$FC1CSS"
if [[ "$(sha256sum "$FC1CSS" | cut -d' ' -f1)" == "$css1_before" ]]; then
  bad "MK-CSS1 setup: 源泉 srs.css の改竄が未適用 (MK 空撃ち)"
else
  out="$("$FOLIO" validate --root "$FC1/design-intent" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q '\[nav-regen-drift\]' <<<"$out"; then
    ok "MK-CSS1b inline fold-in: 源泉 srs.css の 1 byte drift → nav-regen-drift RED (CSS が page の byte に入り専用同期 gate 無しで検出される)"
  else
    bad "MK-CSS1b inline fold-in: 源泉 CSS の drift が検出されない (rc=$rc = fold-in が壊れ CSS drift 面が無防備 = 同期 gate 撤去の前提が崩壊)"
  fi
fi
# MK-CSS2: 源泉 srs.css 不在 → folio build が hard-fail + committed glossary.html は byte 不変
#     ★rc だけ見ない: guard が消えると assemble が <style></style> 空/欠落の劣化 page を emit し、 それが
#       committed を上書きした瞬間に committed==fresh で恒真 PASS 化する (silent revert クラス)。
FC2="$WORK/fcss2"; mk_selfhost "$FC2"
rm -f "$FC2/.claude-plugin/design-system/srs.css"
if [[ -e "$FC2/.claude-plugin/design-system/srs.css" ]]; then
  bad "MK-CSS2 setup: 源泉 srs.css の削除が未適用 (MK 空撃ち)"
else
  gc2_before="$(sha256sum "$FC2/design-intent/glossary.html" | cut -d' ' -f1)"
  out="$("$FOLIO" build --root "$FC2/design-intent" 2>&1)"; rc=$?
  gc2_after="$(sha256sum "$FC2/design-intent/glossary.html" | cut -d' ' -f1)"
  if [[ "$rc" -eq 2 ]] && grep -q 'srs.css not found' <<<"$out"; then
    ok "MK-CSS2a CSS 不在: folio build が exit 2 + -f guard 固有 message (guard が委譲 hard-fail へ写る)"
  else
    bad "MK-CSS2a CSS 不在: build が hard-fail しない か guard message 不在 (rc=$rc = -f guard 除去が set -e の別 error へ退化する経路を弁別)"
  fi
  if [[ "$gc2_before" == "$gc2_after" ]] && grep -q 'folio human-layer design system' "$FC2/design-intent/glossary.html"; then
    ok "MK-CSS2b CSS 不在: committed glossary.html は inline CSS を保ったまま byte 不変 (素朴 emitter への silent fallback 不発)"
  else
    bad "MK-CSS2b CSS 不在: glossary.html が CSS 欠落版へ書き換わった (silent revert が実発生 → 以後 committed==fresh で恒真 PASS 化)"
  fi
fi
# MK-CSS3: 源泉 srs.css が 0 byte → folio build が hard-fail + committed glossary.html は byte 不変
#     ★per-shape 原則 (jyfh/r8k): 「不在」(MK-CSS2) と「空」は guard から見て別の構造クラス。 `[[ -f ]]` は
#       存在のみを見てサイズを見ないため 0 byte を *通す* — MK-CSS2 だけでは本 shape の穴を証明できない。
#       空 file 下限は撤去した verify-asset-sync.sh が明示的に持っていた precondition (その MK5) であり、
#       inline 化で守りを assemble 側 guard へ移した以上、 実弾も対で移管しないと正味の防御喪失になる。
FC3="$WORK/fcss3"; mk_selfhost "$FC3"
FC3CSS="$FC3/.claude-plugin/design-system/srs.css"
: > "$FC3CSS"
if [[ -s "$FC3CSS" ]]; then
  bad "MK-CSS3 setup: 源泉 srs.css の 0 byte 化が未適用 (MK 空撃ち)"
else
  gc3_before="$(sha256sum "$FC3/design-intent/glossary.html" | cut -d' ' -f1)"
  out="$("$FOLIO" build --root "$FC3/design-intent" 2>&1)"; rc=$?
  gc3_after="$(sha256sum "$FC3/design-intent/glossary.html" | cut -d' ' -f1)"
  if [[ "$rc" -eq 2 ]] && grep -q '空/切り詰め' <<<"$out"; then
    ok "MK-CSS3a CSS 空 (0 byte): folio build が exit 2 + サイズ下限 guard 固有 message (-f 素通しを塞ぐ)"
  else
    bad "MK-CSS3a CSS 空 (0 byte): build が hard-fail しない か guard message 不在 (rc=$rc = <style></style> の未スタイル page が全 precondition を素通りする経路)"
  fi
  if [[ "$gc3_before" == "$gc3_after" ]] && grep -q 'folio human-layer design system' "$FC3/design-intent/glossary.html"; then
    ok "MK-CSS3b CSS 空 (0 byte): committed glossary.html は inline CSS を保ったまま byte 不変 (silent revert 不発)"
  else
    bad "MK-CSS3b CSS 空 (0 byte): glossary.html が CSS 欠落版へ書き換わった (silent revert → committed==fresh で nav-regen-drift が恒真 PASS 化)"
  fi
fi

echo ""
echo "test-adversarial-glossary-pack: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
