/*
 * folio render-safety probe — in-browser 幾何 detector (ceiling 層)。
 *
 * mermaid が render した後の DOM 幾何から **flowchart の text-block overlap** を検出する。
 * folio validate (pure-bash floor、 REQ-VER-021) は render 後の DOM を見れないため
 * 「既知パターン (subgraph 多行タイトル)」しか static lint できないが、 本 probe は
 * 実ブラウザ render 後の getBoundingClientRect で以下 4 class を幾何検出する:
 *   (1) 多行 cluster-label (subgraph タイトルの縦 overflow)
 *   (2) label-over-foreign-node / cluster-label-over-node (text が自分以外の node 矩形と交差)
 *   (3) node-over-node (layout collision)
 *   (4) content-clipped (要素が svg 可視範囲を溢れて clip される — svg overflow は既定 hidden)
 * 幾何検査の対象は flowchart/graph の .cluster/.node/label に限る。 coverage は 2 段で報告する:
 *   - vacuous      = .node/.cluster を持たず幾何検査が構造的に空振り (sequenceDiagram 等)
 *   - uncalibrated = .node は持つが図型 (aria-roledescription) が flowchart/graph でない
 *                    (stateDiagram 等 — 幾何は測れるが threshold は flowchart で較正したもの)
 * いずれも caller (check.py) が warning 可視化する (silent pass にしない)。 注意: stateDiagram は
 * .node を「出す」ため、 .node 有無だけでは flowchart と区別できない (図型判定が必要)。
 *
 * Playwright の page.evaluate() から `__folioRenderProbe()` として呼ぶ。
 * 戻り値: { svgCount, diagrams: [{ idx, id, caption, type, vacuous, uncalibrated, violations: [{kind, text, ...}] }] }
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

  return { svgCount: svgs.length, diagrams };
};
