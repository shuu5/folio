#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""folio-cuom Leg A — 受入 oracle: canonical folio-self-spec.html ↔ 生成物の ★悉皆 text sweep 差分。

★何を保証するか (契約 D7):
  生成物と canonical の ★可視テキスト を漏れなく突き合わせ、 差分を全件分類して
  「chrome 由来 / trailing-fold 由来 / errata 1 件 / それ以外 0 件」を機械で示す。
  ★それ以外が 1 件でもあれば exit 1 (DONE 不可)。
  動機 = relations DRAFT が body list 6 本を欠落したまま ★自己整合 PASS した事故の再発封鎖。
  floor (verify-self-spec.sh) は「contract ↔ 生成物」しか見ないため ★両側同時退行に全盲 —
  本 oracle だけが canonical (contract の外) を独立 anchor にする。

★分類は「肯定列挙 + ★SSoT 駆動」で行う (散文の hand-list を極力持たない):
  生成物にだけ在ってよい単位は、 その ★出所 (contract の kicker / references / glossary / meta、
  prose manifest の slot 値、 assembler の静的 chrome literal) から ★導出 して照合する。
  ★hand-list を増やすほど「未知の欠落を分類済へ吸わせる」穴が開くため、 導出できるものは導出する。

★granularity: block 境界で区切った ★テキスト単位 (inline tag は連結して 1 単位に保つ)。
  ★存在 (欠落 / 捏造) の検査は ★multiset (順序非依存) で行う — trailing-fold 集約 (機械層 block を章末 fold へ
  移す・qojv 決定 3) は ★順序だけを変える 変換ゆえ、 順序非依存にすると「移動」が差分に出ず ★欠落だけが残る。
  ★順序の帰属 (誤帰属の是正): 「順序は floor 側 (§3/§5 の順序付き逐値突合・§11 の順序付き round-trip) が担う」
  は ★成立しない。 floor は ★contract ↔ 生成物 の相対突合ゆえ、 contract 側で block 順序が入れ替われば
  ★両側が同時に動いて必ず PASS する (本 oracle が塞ぐために作られた「両側同時退行」と同じ構造の穴が
  順序軸に開く)。 実弾で確認済: contract の §3.3/§3.4 subhead を入替 → verify rc=0 / 旧 oracle rc=0。
  ゆえ ★canonical ↔ 生成物 の順序は本 oracle が ★自分で 撃つ (order arm・下記 order_arm):
    - 対象 = ★人間層 単位のみ (chrome 領域と data-audience="machine" 祖先を持つ単位を除外)。
      機械層は trailing-fold で ★正当に 順序が変わるため multiset のままにする (order arm から外す)。
    - 方法 = 両側で ★ちょうど 1 回 出現する共通単位を anchor に採り、 その ★相対順序列 が逐値一致することを課す
      (重複単位は anchor にしない = 曖昧な対応付けで偽 FAIL / 偽 PASS を出さない)。
    - ★機械層内部の順序 と ★anchor にならなかった重複単位の順序 は本 arm でも未検査 = out-of-scope として
      self-report に件数付きで開示する (「悉皆」の宣言能力を実能力より広く読ませない)。

★chrome は ★DOM 領域 で切る (text 述語で切らない):
  canonical の nav.toc / nav.breadcrumb / nav.prevnext / header.doc-header / a.skip-link の subtree を
  ★multiset ごと差し引いてから比較する。 text 述語 (例 「^§\\d」) で切ると TOC 行 17 本と ★本文見出し 20 本が
  同じ述語に当たり、 ★本文見出しの欠落 が TOC 由来として吸われて PASS する (fail-open・実弾で確認済)。
  加えて chrome 領域の件数を ★凍結 literal (CHROME_PIN) で束縛し、 吸収の増減自体を可視化する。
  ★件数 pin だけでは足りない領域がある: header.doc-header は ★文書 identity (h1 = 題字 / .meta 帯 = 副題) を
  担い、 生成物側の同 text は contract meta 由来述語 (cover-title / cover-subtitle) が許可する。 ゆえ
  ★両側とも contract に self-reference し、 title/subtitle の捏造が sweep の比較対象から消える (実弾で確認済)。
  封鎖 = chrome:doc-header 領域の ★値 multiset == {meta.title, meta.subtitle} の等値 assert (下記 main)。

★identity は title/subtitle だけではない (per-shape の残穴封鎖・head meta arm):
  同じ「両側とも contract に self-reference する」構造は ★cover-eyebrow / cover-meta / reader-chip の
  static バケットにも在る。 実弾で確認済: .meta.version / .meta.status / .meta.date / .meta.reader /
  .meta.eyebrow_right のいずれを捏造しても verify rc=0 / 旧 oracle rc=0 で、 生成物は
  「v9.9.9」 を名乗りながら canonical 由来の subtitle 「v1.2.0 · status: stable」 と ★文書内部で矛盾したまま
  両 gate が緑になった。 1 instance (title) の実弾は ★構造差のある instance の穴を証明しない (per-shape MK)。
  封鎖 = canonical の ★head folio-* meta を独立 anchor にして contract .meta を ★逐値等値 で束縛する
  (下記 HEAD_META_BIND / head_meta_arm)。 ★canonical に anchor が実在する軸のみ束縛でき、
  残りは ★束縛不能 として self-report に列挙する (黙って落とすと「悉皆」の誤報告になる):
    - 束縛する   : version / status / layer / glossary_automark / xref_completeness / stakeholders
    - 既知 delta : doc_type (canonical=self-spec / contract=spec = qojv 決定 2 の意図的 swap・値ごと pin)
    - ★束縛不能 : eyebrow_left / eyebrow_right / date / reader (canonical head にも doc-header にも対応
                  anchor が無い)。 reader は canonical folio-stakeholders と ★接頭辞が重なるだけ で
                  byte 等値にならないため、 接頭辞束縛は使わない (それ自体が本 oracle の塞ぐ fail-open 形)。
                  これらは flip (folio-mkwc) で canonical 側に anchor が生えるまで ★未束縛 のまま。

★生成物にだけ在ってよい単位は ★接頭辞 (startswith) や wildcard で許さない:
  接尾部が無束縛だと「その接頭辞さえ持てば canonical に対応物の無い任意テキスト」が分類済へ落ちる
  (実弾で確認済: 「想定読者 …捏造…」/「機械SSoT: …捏造…」/ fold summary の章帰属・件数の付け替え)。
  ゆえ全バケットを ★SSoT 導出の完全一致 (集合 in / 逐値等値) にする。 timestamp のように決定的に導出できない
  部分だけは ★全体 anchor 付き正規表現 で囲い、 可変部を最小 (\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}) に閉じる。

★errata は 「バケットが在る」でなく 「★1 site かつ ★承認済み置換のみ」 で束縛する:
  両側ちょうど 1 単位 + 承認済み部分文字列を 1 回置換したら ★byte 等値、 を課す。
  部分文字列一致だけで許すと、 同じ段落内の ★任意の書き換え が承認済み delta に紛れて吸われる。

usage: self-spec-text-sweep.py <canonical.html> <generated.html> <contract.yaml> <prose.yaml>
exit : 0 = 未分類差分 0 かつ errata ちょうど 1 delta かつ chrome pin 一致 かつ doc-header identity 一致
           かつ head meta identity 一致 かつ 人間層 order arm 一致 かつ ★層帰属 一致 (M2)
           かつ ★照会 (token, role) 集合一致 (M4) かつ ★分類済 bucket 件数 pin 一致 (M5)
           かつ ★mermaid DSL の markup byte 一致 (M8(2))
       1 = それ以外 / 2 = tool error
"""
import sys, re, subprocess
from collections import Counter
from html.parser import HTMLParser

BLOCK = {
    'p', 'div', 'li', 'td', 'th', 'tr', 'table', 'thead', 'tbody', 'caption', 'figcaption',
    'figure', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'section', 'aside', 'details',
    'summary', 'dl', 'dt', 'dd', 'ul', 'ol', 'nav', 'header', 'footer', 'main', 'article',
    'blockquote',
}
# ★inline (span/a/code/br/strong/em) は BLOCK に入れない — 割ると単位が砕けて差分が読めなくなる。
SKIP = {'script', 'style', 'template', 'title'}   # title = head 資産 (本文でない・両側 symmetric に除外)
# ★void element (終了タグを持たない) — 祖先 stack へ push すると閉じられず ★領域が漏れる。
VOID = {'br', 'img', 'meta', 'link', 'input', 'hr', 'wbr', 'source', 'col', 'area',
        'base', 'embed', 'param', 'track'}

# ★chrome 領域 = ★DOM の領域 で定義する (text 正規表現で定義しない)。
#   動機 (fail-open 封鎖): 「^§\d」のような ★text 述語 は canonical の TOC 行 (17 本) と ★本文見出し (20 本) を
#   区別できないため、 ★本文見出しの欠落 を TOC 由来として吸って PASS する (実弾で確認済)。
#   ゆえ分類は「その単位が nav / header.doc-header / footer / a.skip-link の subtree に居たか」で行い、
#   chrome 単位は canonical 側の比較対象から ★multiset ごと差し引く (残りは全て本文 = 欠落が必ず露出する)。
def chrome_root(tag, attrs):
    """chrome 領域の根なら領域ラベル、 そうでなければ None。"""
    cls = (dict(attrs).get('class') or '').split()
    if tag == 'nav':
        for c in ('toc', 'breadcrumb', 'prevnext'):
            if c in cls:
                return 'chrome:' + c
        return 'chrome:nav(other)'
    if tag == 'header' and 'doc-header' in cls:
        return 'chrome:doc-header'
    if tag == 'footer' and 'doc-header' not in cls:
        return 'chrome:footer'
    if tag == 'a' and 'skip-link' in cls:
        return 'chrome:skip-link'
    return None


# ★canonical の chrome 単位数の ★凍結 pin。 述語を直さなくても「吸収の増減」が可視化されるよう
#   ★領域ごとの件数 を literal で束縛する (増えても減っても exit 1)。 実測由来 (2026-08-04)。
CHROME_PIN = {
    'chrome:skip-link': 1,
    'chrome:breadcrumb': 3,
    'chrome:doc-header': 2,
    'chrome:toc': 17,
    'chrome:prevnext': 1,
}

# ★分類済 bucket の ★件数 凍結 pin (folio-cuom errata-1 M5・CHROME_PIN と同型)。
#   ★塞ぐ穴 (独立 ceiling blocking M5): gen_allow の各述語は「値集合 membership」判定ゆえ、 ★既存 bucket に
#     属する text を ★もう 1 個 注入しても「分類済」に吸われて未分類 0 のまま PASS する (件数だけが静かに増える)。
#     実弾では machine_blocks へ <div class="meta"> を注入して consumer (folio inventory summary) を乗っ取れた。
#   ★件数を凍結 literal で束縛すると「吸収の増減」自体が露出する (chrome pin と同じ設計)。
#   ★contract を正当に変えたとき (照会や用語の増減) は本表も同時更新する = ★同期漏れで落ちる 方を選ぶ。
#   実測由来 (2026-08-07・errata-1)。
BUCKET_PIN = {
    'errata:承認済み 1 delta (「8」→「9」・byte 束縛)': 1,
    'generated-only/approval-block': 2,
    'generated-only/band-num+kicker': 9,
    'generated-only/cover-eyebrow': 1,
    'generated-only/cover-meta': 1,
    'generated-only/cover-subtitle': 1,
    'generated-only/cover-summary-label': 1,
    'generated-only/cover-title': 1,
    'generated-only/footer/provenance': 3,
    'generated-only/glossary-row': 48,
    'generated-only/machine-fold-summary(trailing-fold)': 7,
    'generated-only/prose-slot(人間層 edit-SSoT)': 10,
    'generated-only/reader-chip': 1,
    'generated-only/ref-chip': 33,
    'generated-only/static-band-heading': 2,
}

ROLE_PLAIN = {
    'implementation': 'この規約が実装する原則', 'rationale': 'そう決めた理由の記録',
    'claim': 'この文書が満たすと主張する要件', 'exploration': '探索の記録',
    'principle': '拠って立つ原則', 'verification': 'どう確かめるかの仕様',
}

# ★assembler emit の逐値 literal (assemble-self-spec.sh / lib/common.sh と ★二重保守 = detect↔remediate parity)。
#   片側だけ変えると本 oracle が FAIL する — wildcard / 接頭辞で吸うより ★同期漏れで落ちる 方を選ぶ。
MF_KICKER = '機械向けの詳細（原文そのまま）'                 # assemble-self-spec.sh:98
MF_LABEL_SUFFIX = ' の地の文・運用説明・rationale'          # 同:1145 (section fold の summary 実引数)
MF_PREAMBLE_LABEL = '文書前文 (この規約集の位置づけ)'         # 同:1251 (preamble fold の summary 実引数)
READER_PREFIX = '想定読者: '                                # lib/common.sh core_emit_cover_tail
FOOTER_PLAIN = ('このページは、大もとの機械データ (正本) から自動で組み立てられています。'
                '構造は機械が自動で検査し、内容が元データに忠実かは独立のレビューで確かめます。')  # core_emit_footer
# footer の .tags は span のみを子に持つ ★1 単位 (inline 連結)。 assemble-self-spec.sh:1204 の実引数と逐値一致。
FOOTER_TAGS = ('folio design systemspec-pack (self-spec fork)folio engine'
               '章立て + 非終端 照会 (4 種) + 機械層 trailing-fold')
# provenance 行の「検証状態」トークンは ★2 状態のみ (core_emit_footer の初期値 / inject-prose.sh:69 の flip 後)。
PROV_STATES = ('structure ✓ fabrication-free / prose 未充填 (opus 待ち)',
               'structure ✓ fabrication-free / prose ✓ 充填済 (fidelity ceiling → S5 対象)')

META_KEYS = ('title', 'eyebrow_left', 'eyebrow_right', 'subtitle', 'version', 'date', 'reader', 'status')

# ★canonical head の folio-* meta ↔ contract .meta の ★逐値束縛表 (identity 捏造の per-shape 封鎖)。
#   値は「canonical (contract の外) を独立 anchor に、 contract 側の申告値を突き合わせる」向きで assert する。
#   yq 式まで表に持つ (stakeholders は assembler と同じ join を使う = detect↔remediate parity)。
HEAD_META_BIND = {
    'folio-version':            ('version',            '.meta.version // ""'),
    'folio-status':             ('status',             '.meta.status // ""'),
    'folio-layer':              ('layer',              '.meta.layer // ""'),
    'folio-glossary-automark':  ('glossary_automark',  '.meta.glossary_automark // ""'),
    'folio-xref-completeness':  ('xref_completeness',  '.meta.xref_completeness // ""'),
    # assemble-self-spec.sh:emit_pack_head_meta と同じ join (canonical 逐語 1 行が SSoT)。
    'folio-stakeholders':       ('stakeholders',       '(.meta.stakeholders // []) | join(", ")'),
}
# ★既知 delta は「除外」でなく ★値ごと pin する (除外だと軸が丸ごと無検査になる)。
#   doc_type は qojv 決定 2 の意図的 swap (canonical=self-spec / contract=spec)。
HEAD_META_KNOWN_DELTA = {
    'folio-doc-type': ('doc_type', '.meta.doc_type // ""', 'self-spec', 'spec',
                       'qojv 決定 2 の意図的 swap'),
}
# ★canonical に対応 anchor が ★存在しない contract .meta キー — 黙って落とすと「悉皆」の誤報告になるため
#   self-report に ★明示列挙 する (接頭辞が重なるだけの reader を stakeholders へ束縛するのは fail-open)。
HEAD_META_UNBOUND = (
    ('eyebrow_left',  'canonical head / doc-header に対応 anchor 無し'),
    ('eyebrow_right', 'canonical head / doc-header に対応 anchor 無し'),
    ('date',          'canonical head / doc-header に対応 anchor 無し'),
    ('reader',        'canonical folio-stakeholders と接頭辞が重なるのみで byte 等値でない (接頭辞束縛は使わない)'),
)


class T(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.buf, self.out, self.skip = [], [], 0
        self.st = []        # 開いている element の (tag, chrome ラベル or None, 機械層フラグ)
        self.bufc = None    # 現在 buffer 中の text が属する chrome 領域ラベル
        self.bufm = None    # 同・機械層 (data-audience="machine" 祖先) か否か

    def cur_chrome(self):
        for _, c, _ in self.st:   # ★最外の chrome 領域を採る (入れ子 nav でもラベルが一意)
            if c:
                return c
        return None

    def cur_machine(self):
        """★祖先 stack のどこかが data-audience="machine" なら機械層 (order arm の対象外)。"""
        return any(m for _, _, m in self.st)

    def flush(self):
        s = ''.join(self.buf).strip()
        self.buf = []
        c, self.bufc = self.bufc, None
        m, self.bufm = bool(self.bufm), None
        if s:
            self.out.append((s, c, m))

    def handle_starttag(self, tag, attrs):
        if tag in SKIP:
            self.skip += 1
            return
        if tag in BLOCK:
            self.flush()
        if tag == 'br':
            self.buf.append(' ')
        if tag not in VOID:
            self.st.append((tag, chrome_root(tag, attrs),
                            dict(attrs).get('data-audience') == 'machine'))

    def handle_startendtag(self, tag, attrs):
        if tag == 'br':
            self.buf.append(' ')

    def handle_endtag(self, tag):
        if tag in SKIP:
            self.skip = max(0, self.skip - 1)
            return
        if tag in BLOCK:
            self.flush()      # ★pop の ★前 に flush する (</nav> 直前の text は nav の中の text)
        for i in range(len(self.st) - 1, -1, -1):
            if self.st[i][0] == tag:
                del self.st[i:]
                break

    def handle_data(self, data):
        if not self.skip:
            self.buf.append(data)
            if data.strip():
                if self.bufc is None:
                    self.bufc = self.cur_chrome()
                if self.bufm is None:      # ★最初の非空 text の帰属で決める (chrome と同じ規律)
                    self.bufm = self.cur_machine()


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


def units(path):
    """→ [(正規化 text, chrome 領域ラベル or None, 機械層か)]"""
    p = T()
    p.feed(open(path, encoding='utf-8').read())
    p.flush()
    return [(norm(u), c, m) for u, c, m in p.out if norm(u)]


class HeadMeta(HTMLParser):
    """head の <meta name="folio-*" content="…"> を ★HTML parser で拾う。

    ★naive regex で拾わない — 属性順・引用符・self-closing の差で ★parser-differential が生じ、
      「拾えなかった anchor」を「一致した」と読む恒真 PASS になりうる (folio 恒常 gotcha)。
    """
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.meta = {}

    def handle_starttag(self, tag, attrs):
        if tag != 'meta':
            return
        d = dict(attrs)
        name = d.get('name') or ''
        if name.startswith('folio-'):
            self.meta[name] = norm(d.get('content') or '')

    # ★<meta … /> は handle_startendtag に来る (2 経路とも同じ収集をする = 片肺の取りこぼし封鎖)。
    handle_startendtag = handle_starttag


def head_meta(path):
    p = HeadMeta()
    p.feed(open(path, encoding='utf-8').read())
    return p.meta


def yq(expr, path):
    r = subprocess.run(['yq', '-r', expr, path], capture_output=True, text=True)
    if r.returncode != 0:
        print('yq failed: %s\n%s' % (expr, r.stderr), file=sys.stderr)
        sys.exit(2)
    return [l for l in r.stdout.split('\n')]


def strip_tags(s):
    return norm(re.sub(r'<[^>]*>', '', s))


ERRATA_CANON = '§7.2 (完成形 8 specialist agents)'
ERRATA_GEN = '§7.2 (完成形 9 specialist agents)'


def read_meta(contract):
    """contract の meta を 1 度だけ読む (gen_allow と chrome:doc-header の値束縛が同じ SSoT を使う)。"""
    return {k: yq('.meta.%s // ""' % k, contract)[0] for k in META_KEYS}


def build_gen_allow(contract, prose, meta):
    """生成物にだけ在ってよい単位 → (バケット名, 判定器) の列。 可能な限り SSoT から導出する。"""
    kickers = [l for l in yq('.sections[].kicker', contract) if l]
    headings = [l for l in yq('.sections[].heading', contract) if l]
    secnums = [re.match(r'^§(\d+)\.', h).group(1) for h in headings]
    last = int(secnums[-1])
    # 章帯: <span class="num">N</span><span class="kicker">…kicker</span> が inline ゆえ 1 単位に連結される。
    band_units = set('%s %s' % (n, k) for n, k in zip(secnums, kickers))
    band_units |= {'%d %s' % (last + 1, 'この仕様が参照する文書 / 照会 (前方)'),
                   '%d %s' % (last + 2, '用語集 / この文書で使う専門語')}
    static_headings = {'§%d. 上位文書への前方照会 — 原則・決定記録・規約要件・検証仕様へつながる' % (last + 1),
                       '§%d. 本文に出てくる専門語のやさしい説明' % (last + 2)}
    # 前方照会 chip: token → doc role(平易語) が inline 連結で 1 単位。
    toks = [l for l in yq('.references[].token', contract) if l]
    docs = [l for l in yq('.references[].doc', contract) if l]
    roles = [l for l in yq('.references[].role', contract) if l]
    chips = set('%s→%s%s' % (t, d, ROLE_PLAIN[r]) for t, d, r in zip(toks, docs, roles))
    # 用語集 table: 1 行 = <td>term</td><td>en</td><td>def</td> → td は BLOCK ゆえ 3 単位。
    terms = [l for l in yq('.glossary[].term', contract) if l]
    ens = [l for l in yq('.glossary[].en', contract) if l]
    defs = [l for l in yq('.glossary[].def', contract) if l]
    gloss = set(terms) | set(ens) | set(defs) | set(t + e for t, e in zip(terms, ens))
    # prose manifest (人間層 edit-SSoT の新規著述 = canonical に存在しないのが正常)。
    prose_vals = set(l for l in yq('.slots[]', prose) if l)
    # approval 行: <span class="sign"> 内の 4 値が inline 連結で 1 単位になる (行ごとに 1 単位)。
    ap = {f: [l for l in yq('.approval[].%s' % f, contract) if l] for f in ('role', 'who', 'when', 'stamp')}
    app = set(''.join(v) for v in zip(ap['role'], ap['who'], ap['when'], ap['stamp']))
    for f in ('role', 'who', 'when', 'stamp'):
        app |= set(ap[f])
    nsec = len(headings)
    nreq = len([l for l in yq('.requirements[].id // ""', contract) if l])
    ngl = len(terms)
    cm_pairs = [('章の数', '%d 章' % nsec), ('規範要件', '%d 件 (EARS)' % nreq),
                ('用語', '%d 語' % ngl), ('版', 'v%s / %s' % (meta['version'], meta['date']))]
    covermeta = set(k for k, _ in cm_pairs) | set(v for _, v in cm_pairs)
    # cover-meta 帯は 4 KV が inline 連結で ★1 単位になる (div.cover-meta 直下は全て span)。
    covermeta.add(''.join(k + v for k, v in cm_pairs))
    # 機械層 fold summary (trailing-fold)。 ★kicker / label / 件数 の ★3 成分を全て SSoT から導出する。
    #   label = contract heading (+ preamble は静的 literal)、 件数 = per-section |machine_blocks|
    #   (preamble は |machine_preamble|)。 emit は summary 内の 3 span が inline 連結され 1 単位になる。
    #   ★wildcard (r'^…… .* \d+ 件$') では ★章帰属 (mf-label) と ★件数 (mf-count) が無束縛で、
    #     「§1 の fold を §9 帰属へ付替え」「3 件 → 99 件」の捏造が分類済へ落ちた (実弾で確認済・fail-open)。
    #   ★件数 0 の section は fold を emit しない (assembler が孤立 fold を抑止) ため集合からも外す。
    mb_counts = [int(l) for l in yq('.sections[] | (.machine_blocks // []) | length', contract) if l != '']
    if len(mb_counts) != nsec:
        print('fold 件数の導出に失敗: sections=%d / machine_blocks 列=%d' % (nsec, len(mb_counts)), file=sys.stderr)
        sys.exit(2)
    npre = int(yq('.machine_preamble // [] | length', contract)[0] or 0)
    fold_units = set(norm('%s %s%s %d 件' % (MF_KICKER, h, MF_LABEL_SUFFIX, n))
                     for h, n in zip(headings, mb_counts) if n > 0)
    if npre > 0:
        fold_units.add(norm('%s %s %d 件' % (MF_KICKER, MF_PREAMBLE_LABEL, npre)))
    # footer / 生成 provenance。 静的 2 行は逐値集合、 provenance 行は ★timestamp だけを可変にした
    #   ★全体 anchor 付き 正規表現 (機械SSoT 名は contract path から導出・検証状態は 2 状態の closed set)。
    prov_re = re.compile(r'^機械SSoT: %s · 生成: \d{4}-\d{2}-\d{2} \d{2}:\d{2} · 検証状態: (?:%s)$'
                         % (re.escape(contract.rsplit('/', 1)[-1]),
                            '|'.join(re.escape(s) for s in PROV_STATES)))
    footer_literals = {FOOTER_PLAIN, FOOTER_TAGS}
    static = {
        'cover-eyebrow': lambda u: u == '%s %s' % (meta['eyebrow_left'], meta['eyebrow_right']),
        # ★cover の題字 / 副題 は contract meta 由来。 canonical では ★chrome (header.doc-header) が
        #   同じ text を担うため、 chrome を領域で差し引いた後は ★生成物側にだけ残る (SSoT 導出で照合)。
        'cover-title': lambda u: u == meta['title'],
        'cover-subtitle': lambda u: u == meta['subtitle'],
        'cover-summary-label': lambda u: u == 'この仕様が約束すること (1 文サマリ)',
        'approval-block': lambda u: u in app or u == '承認記録' or u == '',
        # ★reader-chip は core_emit_cover_tail の emit 逐値 (「想定読者: 」 + meta.reader) と ★完全一致 のみ。
        #   startswith('想定読者') は接尾部が無束縛で、 「想定読者 まったく別の読者像 (捏造)」が分類済へ
        #   落ちた (実弾で確認済・fail-open)。
        'reader-chip': lambda u: u == norm(READER_PREFIX + meta['reader']),
        'cover-meta': lambda u: u in covermeta,
        'band-num+kicker': lambda u: u in band_units,
        'static-band-heading': lambda u: u in static_headings,
        'ref-chip': lambda u: u in chips,
        'glossary-row': lambda u: u in gloss,
        'prose-slot(人間層 edit-SSoT)': lambda u: u in prose_vals,
        'machine-fold-summary(trailing-fold)': lambda u: u in fold_units,
        # footer / 生成 provenance 行 / 「このページは…」導入行 = ★assembler の静的 chrome (core_emit_footer /
        # core_emit_cover_head)。 canonical (手書き) に対応物が無いのが正常。
        # ★接頭辞判定は使わない — 「機械SSoT: 捏造された別 contract path.yaml」が分類済へ落ちた
        #   (実弾で確認済・fail-open)。 静的 2 行は逐値集合、 timestamp を含む 1 行のみ全体 anchor 正規表現。
        'footer/provenance': lambda u: u in footer_literals or bool(prov_re.match(u)),
    }
    return list(static.items())


# ★canonical にだけ在ってよい ★本文 単位は ★存在しない (chrome は領域で差し引き済・errata は別枠)。
#   ゆえ空リスト = ★本文の欠落は必ず未分類として露出する。 hand-list を足すときは
#   「text 述語で本文クラスを吸わないか」を必ず per-shape の実弾で示すこと (F6/F7/F8 と同じ規律)。
CANON_ALLOW = []


def classify(u, rules):
    for name, pred in rules:
        try:
            if pred(u):
                return name
        except Exception:
            pass
    return None


def head_meta_arm(canon, contract):
    """canonical head の folio-* meta を独立 anchor に contract .meta を逐値束縛する。

    → (ok, 出力行の列)。 ★fail-closed の 3 条件:
       (a) 束縛表の anchor が canonical に ★実在 する (消せば arm が無効化される、を封鎖)
       (b) 値が ★byte 等値 (接頭辞・部分一致は使わない)
       (c) canonical の folio-* meta に ★表外の名前 が出たら FAIL (未対応 anchor を黙って無視しない)
    """
    cm = head_meta(canon)
    lines, ok = [], True
    lines.append('--- canonical head folio-* meta ↔ contract .meta の ★逐値束縛 (identity 捏造の封鎖) ---')
    for anchor in sorted(HEAD_META_BIND):
        key, expr = HEAD_META_BIND[anchor]
        want = norm(yq(expr, contract)[0])
        if anchor not in cm:
            lines.append('  [★anchor 欠落] %s (canonical に実在しない = 束縛が無効化されている)' % anchor)
            ok = False
            continue
        got = cm[anchor]
        hit = (got == want)
        ok = ok and hit
        lines.append('  [%s] %-26s canonical=%r / contract.meta.%s=%r'
                     % ('OK  ' if hit else '★不一致', anchor, got, key, want))
    for anchor in sorted(HEAD_META_KNOWN_DELTA):
        key, expr, exp_canon, exp_contract, why = HEAD_META_KNOWN_DELTA[anchor]
        got = cm.get(anchor)
        want = norm(yq(expr, contract)[0])
        hit = (got == exp_canon and want == exp_contract)
        ok = ok and hit
        lines.append('  [%s] %-26s canonical=%r / contract.meta.%s=%r (既知 delta: %s・値ごと pin)'
                     % ('OK  ' if hit else '★pin 破れ', anchor, got, key, want, why))
    extra = sorted(set(cm) - set(HEAD_META_BIND) - set(HEAD_META_KNOWN_DELTA))
    if extra:
        lines.append('  [★表外 anchor] %s (束縛表に無い canonical head meta = 無検査軸を黙認しない)'
                     % ', '.join(extra))
        ok = False
    lines.append('  [開示] ★束縛不能 な contract .meta (canonical に anchor 無し・黙って落とさない):')
    for key, why in HEAD_META_UNBOUND:
        lines.append('           - .meta.%-14s %s' % (key, why))
    return ok, lines


def order_arm(cun, gun):
    """★人間層 単位の canonical ↔ 生成物 ★順序 突合 (floor は contract 相対ゆえこの軸に全盲)。

    → (ok, 出力行の列)。 anchor = 両側で ★ちょうど 1 回 出現する共通の人間層単位。
      機械層 (data-audience="machine" 祖先) は trailing-fold で ★正当に 順序が変わるため対象外。
    """
    cseq = [u for u, c, m in cun if not c and not m]
    gseq = [u for u, c, m in gun if not c and not m]
    cc, gc = Counter(cseq), Counter(gseq)
    anchors = set(u for u in (set(cc) & set(gc)) if cc[u] == 1 and gc[u] == 1)
    cs = [u for u in cseq if u in anchors]
    gs = [u for u in gseq if u in anchors]
    dup = sorted(u for u in (set(cc) & set(gc)) if u not in anchors)
    lines = ['--- 人間層 block の ★順序 突合 (canonical ↔ 生成物・機械層は trailing-fold ゆえ対象外) ---',
             '  canonical 人間層 = %d 単位 / 生成物 人間層 = %d 単位 / ★順序 anchor = %d 単位'
             % (len(cseq), len(gseq), len(anchors)),
             '  [開示] ★未検査 の順序軸: 機械層内部の順序 (trailing-fold で正当に変わる) / '
             '両側に重複出現し anchor にできなかった共通単位 %d 種' % len(dup)]
    ok = (cs == gs)
    if not ok:
        i = next(k for k in range(min(len(cs), len(gs)) + 1)
                 if k == min(len(cs), len(gs)) or cs[k] != gs[k])
        lines.append('  ★人間層 block の順序が canonical と不一致 (先頭の食い違い = anchor 第 %d 番)' % (i + 1))
        lines.append('    [canonical 位置 %d] %s' % (i + 1, (cs[i] if i < len(cs) else '(無し)')[:200]))
        lines.append('    [生成物   位置 %d] %s' % (i + 1, (gs[i] if i < len(gs) else '(無し)')[:200]))
    return ok, lines


# ★canonical a[href] → 照会 (token, role) の ★導出レシピ (folio-cuom errata-1 M4・HEAD_META_BIND と同型)。
#   ★塞ぐ穴 (独立 ceiling blocking M4): contract .references 33 本は これまで ★contract 自己参照 bucket
#     ('ref-chip' 述語が contract の token/doc/role から作った集合に生成物を照合するだけ) で、 canonical 側の
#     a[href] anchor が ★実在するのに使われていなかった。 ゆえ token 捏造 / role 付替え / 1 本削除 は
#     「contract も生成物も同時に動く」ため floor / oracle とも ★fail-open だった。
#   ★レシピは extract-self-spec-spec.sh:addref (★同 canonical からの抽出側) と ★同一規律 だが、 ここでは
#     ★独立に 再導出して contract と ★集合等値 で突合する (抽出器のバグも contract の手編集も同じ arm で落ちる)。
#   ★token 正規化も抽出側と一致させる: REQ-VER は 3 桁 zero-pad / rules#req-* は uc / ADR は 4 桁そのまま。
REF_RECIPES = (
    ('implementation', r'href="[^"]*constitution\.html#p-(\d+)"',            lambda g: 'P-%s' % g[0]),
    ('verification',   r'href="[^"]*?(?:srs-)?verification\.html#req-ver-(\d+)"', lambda g: 'REQ-VER-%03d' % int(g[0])),
    ('rationale',      r'href="[^"]*decisions/ADR-(\d{4})-[^"]*"',           lambda g: 'ADR-%s' % g[0]),
    ('claim',          r'href="[^"]*rules\.html#(req-[a-z0-9-]+)"',          lambda g: g[0].upper()),
)


def references_arm(canon, contract):
    """canonical の a[href] を独立 anchor に contract .references の (token, role) 集合を束縛する。

    → (ok, 出力行の列)。 fail-closed の 4 条件:
       (a) 各 recipe が canonical で ★1 件以上 hit する (anchor 消失で arm が空振り無効化される、を封鎖)
       (b) canonical 由来集合 == contract 由来集合 (★余剰 = 捏造 / role 付替え、 ★欠落 = 1 本削除)
       (c) recipe に無い role が contract に在れば ★束縛不能 として ★明示列挙 する (黙って無検査にしない)
       (d) 同一 token が contract 内で ★別 role を持つ重複は 集合等値の余剰として露出する
    ★reverse edge (JSON-LD dc:isReferencedBy の @id のみで href を持たない ADR 4 本) は ★契約に持たない規律
      (folio-cuom ■1(8)) ゆえ recipe も href だけ を見る = 意図的に対象外。
    """
    H = open(canon, encoding='utf-8').read()
    lines = ['--- canonical a[href] ↔ contract .references の ★(token, role) 集合等値 (照会の捏造封鎖) ---']
    ok = True
    want, recipe_roles = set(), set()
    for role, pat, norm_tok in REF_RECIPES:
        hits = [norm_tok(m.groups()) for m in re.finditer(pat, H)]
        recipe_roles.add(role)
        if not hits:
            lines.append('  [★anchor 欠落] role=%s の canonical a[href] が 0 件 (束縛が空振りしている)' % role)
            ok = False
        want |= set((t, role) for t in hits)
        lines.append('  [recipe] %-15s canonical distinct = %3d' % (role, len(set(hits))))
    toks = yq('.references[].token', contract)
    roles = yq('.references[].role', contract)
    pairs = [(t, r) for t, r in zip(toks, roles) if t]
    unbound = sorted(set(p for p in pairs if p[1] not in recipe_roles))
    got = set(p for p in pairs if p[1] in recipe_roles)
    extra = sorted(got - want)
    missing = sorted(want - got)
    lines.append('  canonical 由来 = %d 組 / contract (束縛対象) = %d 組 / 束縛不能 = %d 組'
                 % (len(want), len(got), len(unbound)))
    for t, r in extra:
        lines.append('  [★余剰] contract に在り canonical anchor に無い: (%s, %s) = token 捏造 / role 付替え' % (t, r))
    for t, r in missing:
        lines.append('  [★欠落] canonical anchor に在り contract に無い: (%s, %s) = 照会の脱落' % (t, r))
    if extra or missing:
        ok = False
    if unbound:
        lines.append('  [開示] ★束縛不能 (canonical に導出 anchor を持たない role・黙って落とさない):')
        for t, r in unbound:
            lines.append('           - (%s, %s)' % (t, r))
    else:
        lines.append('  [開示] ★束縛不能 な照会は 0 組 (contract の全 role が canonical anchor から導出できる)')
    # ★軸 の開示 (folio-cuom errata-1 M7 / self-gate advisory): 本 arm が束縛するのは ★(token, role) の 2 軸 だけ。
    #   .references[].doc (chip の人間可読な出典表示) は ★canonical 未束縛 のまま = floor も oracle も contract 相対で、
    #   doc の値を捏造しても両 gate は緑になる (M4 以前は 3 軸とも contract 自己参照だったのを 2 軸だけ引き上げた
    #   ★縮小後の残差 であり、 本 cell が作った穴ではない)。 「照会が canonical へ完全束縛された」と次の cell に
    #   読ませないため明示する — 塞ぐなら REF_RECIPES が既に parse している href path から doc を機械導出して
    #   3 つ組へ広げればよい (mkwc への申送り)。
    lines.append('  [開示] ★未束縛 の軸: .references[].doc (出典表示名) は canonical 未束縛 '
                 '= 本 arm は (token, role) の 2 軸のみを束縛する (残差・mkwc 申送り)')
    return ok, lines


def _esc_mermaid(s):
    """assemble-self-spec.sh esc_mermaid() の逐語再実装 (detect↔remediate parity・errata-2 M8(2))。

    esc() で全 escape → `<b>` / `</b>` の 2 literal ★だけ raw へ戻す。 片側だけ変えると本 arm が FAIL する。
    """
    s = s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
    return s.replace('&lt;b&gt;', '<b>').replace('&lt;/b&gt;', '</b>')


def mermaid_markup_arm(canon, gen):
    """canonical の mermaid DSL を ★markup ごと (inline tag の位置込み) 生成物と byte 等値突合する。

    ★塞ぐ穴 (errata-2 M8(2)・ceiling round-2 blocking): pre-inline census は ★件数 しか見ないため、
      ★総数保存の relocation (`<b>` を別の語へ移す) が素通りする。 本 sweep の text 単位比較も
      ★inline tag を落として連結する ため markup の移動に構造的に全盲。 実害は表示層に及ぶ:
      不均衡・誤位置の <b> は html5lib DOM 実測で adoption agency により <pre> の外へ再構築され、
      figcaption / provenance footer まで bold 化した文書が全 gate 緑で出荷された。
    ★独立 anchor 性: expected は ★canonical (contract の外) から導出するため、 contract 側の改竄でも
      extractor / assembler の退行でも ★片側しか動かず 必ず露出する (両側同時退行に強い)。
    ★導出は extractor + assembler の逐語再現 (canonical 実測に基づく):
      (a) `<br\\s*/?>` → 改行 (extractor M2 の mermaid arm)
      (b) 各行 rstrip + tab→space (preline。 canonical 実測: tab 0 / 行末空白 0 ゆえ no-op だが規律として置く)
      (c) 先頭 / 末尾の空行除去 (extractor)
      (d) 各行へ esc_mermaid (assembler)
      ★entity decode (preline の decode_ent) は ★意図的に再現しない — canonical mermaid の entity は
        ★実測 0 件 で、 extractor 側 guard が `<`/`>` へ decode される entity を fail-loud で禁じている。
        現れたら本 arm が byte 差で FAIL する = 未対応入力を黙って通さない (fail-closed 側へ倒す)。
    → (ok, 出力行の列)。 fail-closed の 3 条件: (a) canonical 側 図数 > 0 (b) 図数一致 (c) 各図 byte 等値。
    """
    ch = open(canon, encoding='utf-8').read()
    gh = open(gen, encoding='utf-8').read()
    pat = re.compile(r'<pre class="mermaid">(.*?)</pre>', re.S)
    cs = [m.group(1) for m in pat.finditer(ch)]
    gs = [m.group(1) for m in pat.finditer(gh)]
    lines = ['--- canonical mermaid DSL の ★markup 単位 byte 等値 (件数 census が見ない relocation の封鎖) ---']
    if not cs:
        lines.append('  [★anchor 欠落] canonical に <pre class="mermaid"> が 0 個 (arm が空振りしている)')
        return False, lines
    if len(cs) != len(gs):
        lines.append('  [★図数不一致] canonical=%d / 生成物=%d' % (len(cs), len(gs)))
        return False, lines
    ok, nb = True, 0
    for i, (c, g) in enumerate(zip(cs, gs)):
        body = re.sub(r'<br\s*/?>', '\n', c)
        rows = [l.replace('\t', '    ').rstrip() for l in body.split('\n')]
        while rows and rows[0] == '':
            rows.pop(0)
        while rows and rows[-1] == '':
            rows.pop()
        exp = '\n'.join(_esc_mermaid(l) for l in rows)
        nb += exp.count('<b>')
        if exp == g:
            continue
        ok = False
        el, gl = exp.split('\n'), g.split('\n')
        lines.append('  [★図 %d が byte 不一致] 期待 %d 行 / 実測 %d 行' % (i + 1, len(el), len(gl)))
        for j in range(max(len(el), len(gl))):
            a = el[j] if j < len(el) else '(無し)'
            b = gl[j] if j < len(gl) else '(無し)'
            if a != b:
                lines.append('    行 %d 期待: %s' % (j + 1, a[:180]))
                lines.append('    行 %d 実測: %s' % (j + 1, b[:180]))
                break
    lines.append('  canonical 由来 %d 図 / <b> 組 %d (markup 位置ごと byte 等値・inline tag を落とさない比較)'
                 % (len(cs), nb))
    return ok, lines


def layer_arm(cun, gun):
    """★層帰属 (人間層 / 機械層) の canonical ↔ 生成物 突合 (folio-cuom errata-1 M2)。

    → (ok, 出力行の列)。 ★塞ぐ穴 (独立 ceiling blocking M2): 本 sweep の本体は ★text だけ の multiset ゆえ、
      同じ text が ★人間層 から ★機械層 へ (またはその逆へ) 移っても差分に出ない = ★層帰属に全盲 だった。
      floor (verify-self-spec.sh) は contract ↔ 生成物 の相対突合ゆえ、 contract 側で section essence を
      machine_blocks へ demote すれば ★両側同時に動いて 全緑になる (実測: floor rc=0 / oracle rc=0)。
      dual-audience 文書にとって層帰属は ★内容そのもの (人間層で読めた要旨が畳まれた fold の中へ消える) ゆえ、
      canonical を独立 anchor にする本 oracle が撃つしかない。

    ★対象 = 両側に存在する text ★のみ (生成物固有 unit = cover / band / chip / fold summary 等は canonical に
      対応物が無く gen_allow が分類する。 canonical 固有 = 欠落として未分類に出る)。 ★trailing-fold は
      機械層 block を章末へ移す ★順序 変換であって ★層 は変えない ため、 本 arm では誤検出しない。
    ★canonical 側で同一 text が両層に重複する場合は (text, 層) の Counter 比較がそのまま正しい
      (実測 0 種・重複しても両側の (text, 層) 多重度が一致すれば PASS)。
    """
    cu = Counter((u, m) for u, c, m in cun if not c)     # chrome 差引後の canonical 本文
    gu = Counter((u, m) for u, _, m in gun)
    common = set(u for u, _ in cu) & set(u for u, _ in gu)
    cr = Counter({k: v for k, v in cu.items() if k[0] in common})
    gr = Counter({k: v for k, v in gu.items() if k[0] in common})
    lines = ['--- ★層帰属 (人間層 / 機械層) の突合 (canonical ↔ 生成物・両側に在る text のみ) ---',
             '  共通 text = %d 種 / canonical 側 %d 単位 / 生成物側 %d 単位 (trailing-fold は層不変ゆえ対象外でない)'
             % (len(common), sum(cr.values()), sum(gr.values()))]
    ok = (cr == gr)
    if not ok:
        for k, n in sorted((cr - gr).items())[:10]:
            lines.append('  [★canonical 側のみ] 層=%s ×%d %s' % ('機械' if k[1] else '人間', n, k[0][:180]))
        for k, n in sorted((gr - cr).items())[:10]:
            lines.append('  [★生成物側のみ]   層=%s ×%d %s' % ('機械' if k[1] else '人間', n, k[0][:180]))
    return ok, lines


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    canon, gen, contract, prose = sys.argv[1:5]
    meta = read_meta(contract)
    gen_allow = build_gen_allow(contract, prose, meta)
    cun, gun = units(canon), units(gen)
    # ★canonical を「chrome 領域」と「本文」へ ★DOM 由来 で二分する (text 述語で分けない)。
    chrome_cnt = Counter(c for _, c, _ in cun if c)
    chrome_txt = Counter(u for u, c, _ in cun if c)
    cu_all = Counter(u for u, _, _ in cun)
    cu = cu_all - chrome_txt          # ★本文単位のみ = chrome へ吸わせる余地が構造的に無い
    gu = Counter(u for u, _, _ in gun)
    only_c, only_g = cu - gu, gu - cu

    buckets, unc, ung, err_c, err_g = {}, [], [], [], []
    for u, n in sorted(only_c.items()):
        if ERRATA_CANON in u:
            err_c.extend([u] * n)
            continue
        k = classify(u, CANON_ALLOW)
        (buckets.setdefault('canonical-only/' + k, []).extend([u] * n)) if k else unc.extend([u] * n)
    for u, n in sorted(only_g.items()):
        if ERRATA_GEN in u:
            err_g.extend([u] * n)
            continue
        k = classify(u, gen_allow)
        (buckets.setdefault('generated-only/' + k, []).extend([u] * n)) if k else ung.extend([u] * n)

    # ★errata の構造的 pin: 「バケットが在る」ではなく「★1 site かつ ★承認済み置換のみ」で束縛する。
    #   (a) 両側ちょうど 1 単位 (site が 2 箇所へ増えたら FAIL)、
    #   (b) canonical 単位に承認済み部分文字列を ★1 回だけ 置換したものが生成物単位と ★byte 等値。
    #   これにより「errata 単位の中に承認外 delta が同居する」形が「置換後も一致しない」として落ちる。
    errata_note = ''
    if len(err_c) == 1 and len(err_g) == 1 and err_c[0].count(ERRATA_CANON) == 1 \
            and err_c[0].replace(ERRATA_CANON, ERRATA_GEN, 1) == err_g[0]:
        buckets['errata:承認済み 1 delta (「8」→「9」・byte 束縛)'] = err_c
        errata_ok = True
    else:
        errata_ok = False
        errata_note = ('errata pin 破れ: canonical 側 %d 単位 / 生成物側 %d 単位 '
                       '(期待 1/1 かつ承認済み置換 1 回で byte 一致)' % (len(err_c), len(err_g)))
        unc.extend(err_c)     # ★承認済みと言えない以上 ★未分類 として露出させる (fail-closed)
        ung.extend(err_g)

    print('=== 受入 oracle: 悉皆 text sweep (canonical ↔ 生成物・multiset) ===')
    print('canonical 単位 = %d (本文 %d / chrome %d) / 生成物 単位 = %d / 共通 = %d'
          % (len(cun), sum(cu.values()), sum(chrome_cnt.values()), sum(gu.values()),
             sum((cu & gu).values())))
    print('--- canonical chrome 領域 (DOM 由来・凍結 pin と突合) ---')
    for k in sorted(set(chrome_cnt) | set(CHROME_PIN)):
        print('  [%-46s] %3d 件 (pin %s)' % (k, chrome_cnt.get(k, 0), CHROME_PIN.get(k, '未登録')))
    chrome_ok = dict(chrome_cnt) == CHROME_PIN
    # ★chrome:doc-header だけは ★件数 pin では足りない — 領域内の 2 単位は ★文書 identity (題字 / 副題) であり、
    #   生成物側の同 text は contract meta 由来述語 (cover-title / cover-subtitle) が許可する。 両側とも contract を
    #   参照するため、 meta.title / meta.subtitle の捏造は sweep の比較対象から ★丸ごと消える (実弾で確認済)。
    #   ゆえ canonical (contract の外) の doc-header 実値 == contract meta を ★逐値等値 で束縛する。
    dh_exp = Counter([norm(meta['title']), norm(meta['subtitle'])])
    dh_act = Counter(u for u, c, _ in cun if c == 'chrome:doc-header')
    docheader_ok = dh_act == dh_exp
    print('--- canonical chrome:doc-header の ★値 束縛 (identity 捏造の封鎖) ---')
    for u in sorted(set(dh_exp) | set(dh_act)):
        print('  [contract %d / canonical %d] %s' % (dh_exp.get(u, 0), dh_act.get(u, 0), u[:200]))
    # ★doc-header (title/subtitle) は identity の ★2 shape でしかない — version / status / layer …の
    #   残り shape は canonical head meta を anchor に別 arm で束縛する (per-shape MK)。
    headmeta_ok, headmeta_lines = head_meta_arm(canon, contract)
    for l in headmeta_lines:
        print(l)
    # ★順序軸 (floor が担うという誤帰属を是正した実 arm)。
    order_ok, order_lines = order_arm(cun, gun)
    for l in order_lines:
        print(l)
    # ★層帰属軸 (errata-1 M2: text multiset は層に全盲・両側同時 demote が全緑だった)。
    layer_ok, layer_lines = layer_arm(cun, gun)
    for l in layer_lines:
        print(l)
    # ★照会軸 (errata-1 M4: references が contract 自己参照 bucket で canonical anchor 未使用だった)。
    refs_ok, refs_lines = references_arm(canon, contract)
    for l in refs_lines:
        print(l)
    # ★markup 軸 (errata-2 M8(2): 件数 census は総数保存の relocation に全盲・text sweep は inline tag を落とす)。
    mm_ok, mm_lines = mermaid_markup_arm(canon, gen)
    for l in mm_lines:
        print(l)
    print('--- 分類済 差分 (★件数は凍結 pin と突合・errata-1 M5) ---')
    bucket_cnt = {k: len(v) for k, v in buckets.items()}
    for k in sorted(set(bucket_cnt) | set(BUCKET_PIN)):
        print('  [%-46s] %3d 件 (pin %s)' % (k, bucket_cnt.get(k, 0), BUCKET_PIN.get(k, '★未登録')))
    bucket_ok = bucket_cnt == BUCKET_PIN
    print('--- ★未分類 差分 (0 でなければ DONE 不可) ---')
    print('  canonical にのみ在る = %d 件' % len(unc))
    for u in unc:
        print('    [C-ONLY] ' + u[:400])
    print('  生成物にのみ在る     = %d 件' % len(ung))
    for u in ung:
        print('    [G-ONLY] ' + u[:400])
    ok = not unc and not ung
    if not errata_ok:
        print('  ★' + errata_note)
        ok = False
    if not chrome_ok:
        print('  ★chrome 領域の件数が凍結 pin と不一致 (述語を直さずとも吸収の増減が露出する arm)')
        ok = False
    if not docheader_ok:
        print('  ★chrome:doc-header の値が contract meta と不一致 (文書 identity の捏造・title/subtitle)')
        ok = False
    if not headmeta_ok:
        print('  ★head meta identity が canonical と不一致 (文書 identity の捏造・version/status/… の per-shape)')
        ok = False
    if not order_ok:
        print('  ★人間層 block の順序が canonical と不一致 (contract 側 block 入替の両側同時退行)')
        ok = False
    if not layer_ok:
        print('  ★層帰属 (人間層 / 機械層) が canonical と不一致 (両側同時 demote / promote の両側同時退行)')
        ok = False
    if not refs_ok:
        print('  ★照会 (token, role) が canonical a[href] と不一致 (token 捏造 / role 付替え / 脱落)')
        ok = False
    if not mm_ok:
        print('  ★mermaid DSL の markup が canonical と不一致 (<b> の relocation / 不均衡 / 位置ずれ)')
        ok = False
    if not bucket_ok:
        print('  ★分類済 bucket の件数が凍結 pin と不一致 (既存 bucket への複製注入 / 分類漏れの増減)')
        ok = False
    print('RESULT: ' + ('PASS (未分類差分 0 / errata 1 delta / chrome pin 一致 / doc-header identity 一致 / '
                        'head meta identity 一致 / 人間層 順序 一致 / 層帰属 一致 / 照会 集合一致 / bucket 件数 pin 一致 / '
                        'mermaid markup byte 一致)'
                        if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
