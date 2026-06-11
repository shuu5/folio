/*
 * folio render-safety probe — in-browser 幾何 detector (ceiling 層)。
 *
 * mermaid が render した後の DOM 幾何から **flowchart の text-block overlap** を、 加えて
 * page 全体の DOM 幾何から **chrome 崩れ** を検出する。
 * folio validate (pure-bash floor、 REQ-VER-021) は render 後の DOM を見れないため
 * 「既知パターン (subgraph 多行タイトル)」しか static lint できないが、 本 probe は
 * 実ブラウザ render 後の getBoundingClientRect で以下 6 class を幾何検出する:
 *   (1) 多行 cluster-label (subgraph タイトルの縦 overflow)
 *   (2) label-over-foreign-node / cluster-label-over-node (text が自分以外の node 矩形と交差)
 *   (3) node-over-node (layout collision)
 *   (4) content-clipped (要素が svg 可視範囲を溢れて clip される — svg overflow は既定 hidden)
 *   (5) horizontal-overflow — 本文が viewport を溢れ document 全体に意図しない横スクロールが
 *       発生 (chrome 幾何 arm、 viewport 依存 — caller が 375/768/1280 の 3 点で呼ぶ)
 *   (6) nav-over-content — nav landmark と本文 block の矩形重なり (chrome 幾何 arm)
 * 幾何検査の対象は flowchart/graph の .cluster/.node/label に限る。 coverage は 2 段で報告する:
 *   - vacuous      = .node/.cluster を持たず幾何検査が構造的に空振り (sequenceDiagram 等)
 *   - uncalibrated = .node は持つが図型 (aria-roledescription) が flowchart/graph でない
 *                    (stateDiagram 等 — 幾何は測れるが threshold は flowchart で較正したもの)
 * いずれも caller (check.py) が warning 可視化する (silent pass にしない)。 注意: stateDiagram は
 * .node を「出す」ため、 .node 有無だけでは flowchart と区別できない (図型判定が必要)。
 *
 * Playwright の page.evaluate() から `__folioRenderProbe()` として呼ぶ。
 * 戻り値: { svgCount,
 *           diagrams: [{ idx, id, caption, type, vacuous, uncalibrated, violations: [{kind, text, ...}] }],
 *           page: { violations: [{kind, text, ...}] } }   // chrome 幾何 (5)(6) は figure 単位でなく page 単位
 *
 * threshold は conservative。 detector(1) の height は font-size 駆動で font 差に頑健、 かつ svg の
 * viewBox→rendered 比で除して **intrinsic px に正規化** する (useMaxWidth:true で svg が縮小されても
 * 閾値が scale に引きずられない。 useMaxWidth:false (現 corpus) は scale=1 で従来挙動と同一)。 面積比
 * detector (2)(3) は比率ゆえ元から scale 不変。 text 幅依存だが mermaid dagre layout が node box を
 * label に合わせ self-normalize するため conservative threshold を跨ぎにくい。 CI は font も pin する
 * (ci.yml fonts-noto-cjk) ことで text shaping も固定する。 vendored mermaid + pinned playwright +
 * pinned font で render を決定的にする。
 */
window.__folioRenderProbe = function () {
  /* 単行 cluster-label (subgraph タイトル) は実測 ~24px。 多行は ~48px。
     30px を境に多行 = 子ノード/枠への overlap-prone と判定 (signal 巨大ゆえ font 差に頑健)。 */
  const CLUSTER_LABEL_MAX_H = 30;
  /* label と「別の」node rect の交差面積比。 0.15 = 明確な food-on-block overlap のみ拾い、
     罫線が接する程度の grazing は無視。 clean corpus 15 図 (blocking 13 + advisory 2) で誤検出 0 を実測した値。 */
  const OVERLAP_FRAC = 0.15;
  /* node 同士の交差 (layout collision)。 mermaid は通常 node を重ねないため高め。 */
  const NODE_NODE_FRAC = 0.30;
  /* 要素が svg 可視範囲を溢れてよい許容 px (rendered)。 罫線の sub-pixel ずれを無視する。 */
  const CLIP_TOL = 2;

  const rect = (el) => el.getBoundingClientRect();
  const area = (r) => Math.max(0, r.right - r.left) * Math.max(0, r.bottom - r.top);
  const interArea = (a, b) => {
    const w = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
    const h = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
    return w * h;
  };
  const snippet = (el) => ((el && el.textContent) || '').replace(/\s+/g, ' ').trim().slice(0, 40);

  const svgs = [...document.querySelectorAll('figure.diagram svg, pre.mermaid svg, .mermaid svg')];
  const diagrams = svgs.map((svg, idx) => {
    const fig = svg.closest('figure');
    const caption = fig ? snippet(fig.querySelector('figcaption')) : '';
    const id = (fig && fig.id) || '';
    const violations = [];

    /* 図型と coverage: mermaid は svg に aria-roledescription (flowchart-v2 / sequence /
       stateDiagram 等) を付与する。 .node/.cluster 不在 = vacuous (幾何検査が構造的に空振り、
       sequence 等)。 .node はあるが図型が flowchart/graph でない = uncalibrated (stateDiagram は
       .node を出すため構造だけでは flowchart と区別できない — threshold は flowchart 較正ゆえ
       別扱いで warning)。 type 空 (mermaid 外の inline SVG、 selftest 合成 fixture 等) は
       flowchart 相当とみなす。 */
    const type = svg.getAttribute('aria-roledescription') || '';
    const hasGeom = !!(svg.querySelector('.node') || svg.querySelector('.cluster'));
    const flowchartLike = type === '' || /^(flowchart|graph)/.test(type);
    const vacuous = !hasGeom;
    const uncalibrated = hasGeom && !flowchartLike;

    /* scale: useMaxWidth:true 等で svg が viewBox より縮小 render される場合、 rendered px を
       viewBox 座標 (intrinsic px) に正規化して絶対閾値 (CLUSTER_LABEL_MAX_H) の scale 依存を断つ。
       height の正規化なので縦比 (scaleY) を使う — mermaid は width/height を viewBox 比で出力する
       uniform scale ゆえ縦横どちらでも同値だが、 仮に letterbox (scaleX≠scaleY) が起きても縦の量を
       横比で割る誤りを避ける。 viewBox 不在 or 等倍なら scaleY=1 で従来挙動と同一。 */
    const vb = svg.viewBox && svg.viewBox.baseVal;
    const svgR = rect(svg);
    const scaleY = vb && vb.height > 0 && svgR.height > 0 ? svgR.height / vb.height : 1;

    /* (1) 多行 cluster-label — subgraph タイトルの縦 overflow (図5 で実際に起きた class)。 */
    [...svg.querySelectorAll('.cluster')].forEach((cl) => {
      const lab = cl.querySelector('.cluster-label, foreignObject');
      if (!lab) return;
      const h = rect(lab).height / scaleY;
      if (h > CLUSTER_LABEL_MAX_H) {
        violations.push({ kind: 'cluster-label-multiline', text: snippet(lab), height: Math.round(h) });
      }
    });

    /* (2) label が「自分のもの以外の」node rect と交差 — 汎用 text-over-block overlap。
           cluster-label は closest('.node') が null なので自 cluster の子ノードとの交差も拾う。 */
    const labels = [...svg.querySelectorAll('.nodeLabel, .edgeLabel, .cluster-label, text')];
    const nodes = [...svg.querySelectorAll('.node')].map((n) => ({ n, r: rect(n) }));
    labels.forEach((lb) => {
      const lr = rect(lb);
      if (area(lr) < 4) return;
      const own = lb.closest('.node');
      nodes.forEach(({ n, r }) => {
        if (own === n) return;
        const frac = interArea(lr, r) / Math.min(area(lr), area(r) || 1);
        if (frac > OVERLAP_FRAC) {
          const isCluster = !!lb.closest('.cluster-label') || lb.classList.contains('cluster-label');
          violations.push({
            kind: isCluster ? 'cluster-label-over-node' : 'label-over-foreign-node',
            text: snippet(lb),
            frac: +frac.toFixed(2),
          });
        }
      });
    });

    /* (3) node 同士の重なり — layout collision (入れ子 cluster は除外、 高め threshold)。 */
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        const a = nodes[i], b = nodes[j];
        if (a.n.contains(b.n) || b.n.contains(a.n)) continue;
        const frac = interArea(a.r, b.r) / Math.min(area(a.r), area(b.r) || 1);
        if (frac > NODE_NODE_FRAC) {
          violations.push({ kind: 'node-over-node', text: snippet(a.n) + ' ∩ ' + snippet(b.n), frac: +frac.toFixed(2) });
        }
      }
    }

    /* (4) content-clipped — 要素が svg 可視範囲の外へはみ出す (svg overflow は既定 hidden で
           視覚上 clip = 読めない)。 getBoundingClientRect は clip 前の layout 幾何を返すため
           svg 矩形との差で検出できる。 wide 図の <pre> 横スクロール (#121) は svg 自体が広がる
           ので対象外 — svg の内側に収まらない要素だけが欠陥。 注: over と CLIP_TOL は rendered px
           (視覚上の clip 量) であり、 detector(1) の intrinsic 正規化とは意図的に非対称 (「読めるか」は
           rendered で決まる。 縮小 render では intrinsic の大はみ出しも視覚上は小さくなる = conservative)。 */
    [...svg.querySelectorAll('.node, .cluster, .nodeLabel, .edgeLabel, .cluster-label')].forEach((el) => {
      const r = rect(el);
      if (area(r) < 4) return;
      const over = Math.max(
        r.right - svgR.right, svgR.left - r.left,
        r.bottom - svgR.bottom, svgR.top - r.top,
      );
      if (over > CLIP_TOL) {
        violations.push({ kind: 'content-clipped', text: snippet(el), overflowPx: Math.round(over) });
      }
    });

    return { idx, id, caption, type, vacuous, uncalibrated, violations };
  });

  /* ===== chrome 幾何 (page-level、 ADR-0039 §2.8 の 2 arm) =====
     figure 単位でなく page 全体の DOM を検査する。 viewport 依存 (特に (5)) のため caller
     (check.py) が 375 / 768 / 1280 の 3 viewport で本 probe を呼ぶ。 */

  /* document 横スクロールの許容 px。 sub-pixel 丸め + scrollbar 幅の計上差を無視する。 */
  const H_OVERFLOW_TOL = 2;
  /* nav と本文 block の交差面積比。 通常 flow の隣接 block は矩形が交差しない (overlap は
     position:absolute/fixed・負 margin 等の欠陥でのみ生じる) ため、 mermaid arm (2) と同じ
     conservative 0.15 で grazing を無視しつつ実 overlap を拾う。 */
  const NAV_OVERLAP_FRAC = 0.15;
  /* culprit 列挙の上限 (1 culprit が cell/列ごとに増殖して log を埋めるのを防ぐ)。 超過は
     件数付きの残余 entry で可視化する (silent cap にしない)。 */
  const H_OVERFLOW_MAX_CULPRITS = 5;

  const pageViolations = [];
  const de = document.documentElement;
  /* 実際に描画されている要素か。 Chromium は closed <details> の中身 (content-visibility 系で
     rendering skip) にも **非 0 の layout 幾何 (phantom rect) を返す** ため、 rect の面積 filter
     だけでは「見えない要素との交差」を欠陥と誤認する (clean fixture で実証)。 checkVisibility()
     は display:none / closed details の skip / visibility:hidden / opacity:0 (完全透明、 自身
     または祖先) を一括で見る。 減光 (essence の .45 等、 0 < opacity < 1) は対象外のまま —
     描画されており overlap が視覚欠陥になりうるため、 完全透明だけを不可視扱いする。 */
  const visible = (el) =>
    typeof el.checkVisibility === 'function'
      ? el.checkVisibility({ visibilityProperty: true, checkVisibilityCSS: true, opacityProperty: true, checkOpacity: true })
      : true;

  /* (5) horizontal-overflow — document.scrollWidth > clientWidth = 意図しない横スクロール。
     意図された scroll container (overflow-x:auto の wide <pre>、 #121) は中身を内部で
     scroll/clip し document の scrollWidth に寄与しないため、 ここで鳴るのは「意図しない」
     溢れだけ。 culprit = viewport 右端を越える border box を持ち、 かつ祖先に horizontal
     clip/scroll context (overflow-x が visible 以外) を持たない要素。 子は親 culprit に
     包含されがちなので最も外側の要素だけ報告する。 */
  const docOver = de.scrollWidth - de.clientWidth;
  if (docOver > H_OVERFLOW_TOL) {
    const culprits = [];
    const all = document.body ? document.body.querySelectorAll('*') : [];
    outer: for (const el of all) {
      const r = rect(el);
      if (area(r) < 4 || !visible(el)) continue;
      const over = r.right - de.clientWidth;
      if (over <= H_OVERFLOW_TOL) continue;
      for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
        if (getComputedStyle(p).overflowX !== 'visible') continue outer; /* 内部 scroll/clip → document へ伝播しない */
      }
      culprits.push({ el, over });
    }
    const top = culprits.filter((c) => !culprits.some((o) => o !== c && o.el.contains(c.el)));
    if (top.length === 0) {
      /* culprit を特定できなくても document 溢れ自体は欠陥 — 黙って通さない (fail-visible) */
      pageViolations.push({ kind: 'horizontal-overflow', text: '(culprit 特定不能)', overflowPx: Math.round(docOver) });
    }
    top.sort((a, b) => b.over - a.over).slice(0, H_OVERFLOW_MAX_CULPRITS).forEach((c) => {
      pageViolations.push({
        kind: 'horizontal-overflow',
        text: `<${c.el.tagName.toLowerCase()}> ${snippet(c.el)}`,
        overflowPx: Math.round(c.over),
      });
    });
    if (top.length > H_OVERFLOW_MAX_CULPRITS) {
      pageViolations.push({ kind: 'horizontal-overflow', text: `(他 ${top.length - H_OVERFLOW_MAX_CULPRITS} 要素)`, overflowPx: Math.round(docOver) });
    }
  }

  /* (6) nav-over-content — nav landmark が本文 block と矩形交差する (chrome 注入の位置
     計算事故・absolute 化の崩れを捕捉)。 比較対象は nav の外にある本文 block 要素のみ。
     祖先/子孫関係 (main が nav を包含する等) は包含であって overlap 欠陥ではないため除外。 */
  /* div / li も含める — semantic 要素だけだと div 直下テキスト (wrapper card 等) への nav 被りを
     取りこぼす (実証済 false negative)。 inline 要素 (span/a) は祖先 block が拾うため列挙しない。 */
  const CONTENT_SEL = 'main, article, header, section, h1, h2, h3, h4, h5, h6, p, ul, ol, li, dl, div, table, pre, figure, blockquote, details';
  const navRects = [...document.querySelectorAll('nav')]
    .filter((n) => visible(n))
    .map((n) => ({ n, r: rect(n) }))
    .filter((x) => area(x.r) >= 4);
  if (navRects.length) {
    const content = [...document.querySelectorAll(CONTENT_SEL)].filter((el) => !el.closest('nav') && visible(el));
    navRects.forEach(({ n, r }) => {
      content.forEach((c) => {
        if (n.contains(c) || c.contains(n)) return;
        const cr = rect(c);
        if (area(cr) < 4) return;
        const frac = interArea(r, cr) / Math.min(area(r), area(cr) || 1);
        if (frac > NAV_OVERLAP_FRAC) {
          pageViolations.push({
            kind: 'nav-over-content',
            text: `${snippet(n)} ∩ <${c.tagName.toLowerCase()}> ${snippet(c)}`,
            frac: +frac.toFixed(2),
          });
        }
      });
    });
  }

  return { svgCount: svgs.length, diagrams, page: { violations: pageViolations } };
};
