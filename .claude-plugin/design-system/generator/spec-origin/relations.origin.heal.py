#!/usr/bin/env python3
# relations.origin.heal.py — spec-origin/relations.origin.html の ★逐語 provenance 記録 (folio-uryh Leg W)。
#
# ★これは bootstrap 記録であって gate ではない。 どの verify / 敵対 suite からも呼ばれない (実行経路ゼロ)。
#   lwhz の「sed provenance 型で逐語記録」と同じ役割を担い、 snapshot が ★どの入力から どの変換で 生成されたかを
#   再実行可能な形で repo へ pin する (散文の手順書は再現性を持たないため script 形で記録する)。
#
# ■ なぜ heal が要るか (契約 = folio-uryh「landed-canonical arm の非 vacuous 化」)
#   verify-relations.sh §11 (原本↔生成物 機械層 round-trip) の ORIG 既定は ★live landed canonical。 folio-6vox の
#   flip が着地すると landed == 生成物 になるため、 §11 は ★自己比較 に退化し extractor collapse に対して恒真 PASS
#   する。 これを塞ぐ独立 oracle が本 snapshot = 「flip ★前 の canonical」。
#   ただし pre-flip canonical をそのまま oracle にすると §11 は ★永久 RED になる: folio-0qz9 の contract 完全化が
#   body の list 6 本 (25 項) + 見出し等を machine_blocks へ逐語 port したため、 生成物の機械層 (38 unit) に対し
#   pre-flip canonical の機械層は 8 unit (aside note のみ) しかない (実測・脱落方向は 0)。
#   ゆえに snapshot へ「post-flip 追加 machine block」を反映する = heal。
#
# ■ ★heal の不変条件 (これを破ると oracle の独立性が失われる)
#   ★本文テキストを 1 byte も書き換えない。 heal が触るのは (a) audience 属性の付与 と (b) ★容器タグの形 だけで、
#   テキスト payload は常に pre-flip canonical の逐語である。 すなわち「どの block を機械層とするか」の割当は
#   contract 由来 (0qz9 の port 判断) だが、 ★中身は原本由来 — §11 が守る性質 (脱落 / 捏造 / 二重 escape / 順序
#   入替 / cross-section 誤帰属) の検出力は保たれる。
#   ★この不変条件の ★tracked な機械 assert 所在 (= CI blocking で恒久に発火する):
#     test-adversarial-relations-census.sh の ★SNAPPIN-4 (本文捏造 0 = snapshot の text node 集合が pre-flip
#       canonical と ★双方向 一致・extra 0 / missing 0) と ★SNAPPIN-5 (★再実行可能性 = 本 script を repo 内容
#       だけから再走行し committed snapshot と ★byte 一致)。 gen-units は同 suite が §11 RIGHT 抽出子と同一
#       semantics で自前再導出するため、 ★外部入力なしで provenance を再現できる。
#   ★注記 (folio-uryh 自己点検 ceiling major fix): 従前ここには「selftest が機械 assert する」と書いていたが、
#     その selftest は cell-local な ★untracked file であり land で消える = shipped 状態で本コメントが ★偽 に
#     なっていた (folio-7wbn ceiling が同型で defect 認定したクラス)。 恒久 regression の所在は上記 suite。
#
# ■ 変換クラス (3 種・それぞれ独立に監査可能。 ★fuzzy な一括置換をしない)
#   T1 属性付与のみ (7 要素 = <p> 3 + <ul> 4):
#       正規化 inner text が生成物の機械層 unit と一致する <p> / <ul> へ ` data-audience="machine"` を挿入する。
#       ★挿入文字列はこの 1 種のみ。 テキストは不変。
#   T2 容器正規化 <ol> → <ul> (2 要素):
#       port は順序リスト 2 本を machine list として表現したが、 §11 の LEFT 抽出子は <ul ... data-audience="machine">
#       しか見ないため <ol> のままでは原理的に拾えない。 開始/終了タグ名のみを ul へ揃え audience 属性を付ける。
#       ★<li> は 1 byte も触らない (内容逐語)。
#   T3 見出し由来 prose の ★追加 (2 要素):
#       port は <h4 id="s4-4-{1,2}-*">…</h4> を機械層 prose (<strong>見出し語</strong>) として表現した。 §11 LEFT は
#       <h4> を見ないため、 ★h4 を温存したまま 直後へ <p data-audience="machine"><strong>{h4 inner 逐語}</strong></p>
#       を挿入する (rewrite でなく ★純追加 = canonical byte を破壊しない最小変換)。
#
# ■ 入力 / 出力 (再実行手順)
#   $ python3 spec-origin/relations.origin.heal.py \
#       design-intent/spec/relations.html <gen-units.txt> spec-origin/relations.origin.html
#   <gen-units.txt> = 生成物の機械層 unit 列 (verify-relations.sh §11 の RIGHT 抽出子と同一 semantics・"type\ttext")。
#   ★入力 canonical は folio-6vox flip ★前 の design-intent/spec/relations.html (base 4c6a3a5b / 51924 byte)。
#   flip 後にこの script を live canonical へ再実行してはならない (生成物を oracle にすると自己比較へ退化する)。
import re, sys

canon_path, gen_units_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
H = open(canon_path, encoding='utf-8').read()

def norm(s):
    return re.sub(r'\s+', ' ', s or '').strip()

want_prose, want_li = set(), set()
for line in open(gen_units_path, encoding='utf-8'):
    line = line.rstrip('\n')
    if not line:
        continue
    k, _, v = line.partition('\t')
    if k == 'prose':
        want_prose.add(v)
    elif k == 'li':
        want_li.add(v)

AUD = ' data-audience="machine"'
edits = []   # (start, end, replacement, cls) — 元 span を replacement へ差し替える (後ろから適用)

# ---- T1: <p> / <ul> への属性付与のみ ----
for m in re.finditer(r'<p\b([^>]*)>(.*?)</p>', H, re.S):
    if 'data-audience' in m.group(1):
        continue                       # pre-flip から機械層/人間層が明示済の要素は触らない
    if norm(m.group(2)) in want_prose:
        ins = m.start(1) + len(m.group(1))
        edits.append((ins, ins, AUD, 'T1-p'))
for m in re.finditer(r'<ul\b([^>]*)>(.*?)</ul>', H, re.S):
    if 'data-audience' in m.group(1):
        continue
    items = [norm(x) for x in re.findall(r'<li\b[^>]*>(.*?)</li>', m.group(2), re.S)]
    if items and all(i in want_li for i in items):
        ins = m.start(1) + len(m.group(1))
        edits.append((ins, ins, AUD, 'T1-ul'))

# ---- T2: <ol> → <ul data-audience="machine"> (容器タグのみ・<li> 逐語) ----
for m in re.finditer(r'<ol\b([^>]*)>(.*?)</ol>', H, re.S):
    items = [norm(x) for x in re.findall(r'<li\b[^>]*>(.*?)</li>', m.group(2), re.S)]
    if items and all(i in want_li for i in items):
        edits.append((m.start(), m.end(),
                      '<ul%s%s>%s</ul>' % (m.group(1), AUD, m.group(2)), 'T2-ol2ul'))

# ---- T3: <h4> 由来 machine prose の純追加 (h4 は温存) ----
for m in re.finditer(r'<h4\b[^>]*>(.*?)</h4>', H, re.S):
    inner = norm(m.group(1))
    if ('<strong>%s</strong>' % inner) in want_prose:
        edits.append((m.end(), m.end(),
                      '\n<p%s><strong>%s</strong></p>' % (AUD, m.group(1)), 'T3-h4prose'))

# ---- 一意性 / 完全性 assert (fail-closed) ----
spans = sorted((s, e) for s, e, _, _ in edits)
for i in range(1, len(spans)):
    if spans[i][0] < spans[i - 1][1]:
        sys.stderr.write('heal: 変換 span が重複 (曖昧一致・fail-closed)\n'); sys.exit(3)

out = H
for s, e, rep, _cls in sorted(edits, key=lambda x: -x[0]):
    out = out[:s] + rep + out[e:]
open(out_path, 'w', encoding='utf-8').write(out)

cnt = {}
for _s, _e, _r, cls in edits:
    cnt[cls] = cnt.get(cls, 0) + 1
sys.stderr.write('heal: %s (計 %d 変換)\n' % (', '.join('%s=%d' % kv for kv in sorted(cnt.items())), len(edits)))
