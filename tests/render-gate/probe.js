/*
 * folio render-safety probe — in-browser 幾何 detector (ceiling 層)。
 *
 * mermaid が render した後の DOM 幾何から **flowchart の text-block overlap** を検出する。
 * folio validate (pure-bash floor、 REQ-VER-021) は render 後の DOM を見れないため
 * 「既知パターン (subgraph 多行タイトル)」しか static lint できないが、 本 probe は
 * 実ブラウザ render 後の getBoundingClientRect で以下 3 class を幾何検出する:
 *   (1) 多行 cluster-label (subgraph タイトルの縦 overflow)
 *   (2) label-over-foreign-node / cluster-label-over-node (text が自分以外の node 矩形と交差)
 *   (3) node-over-node (layout collision)
 * 対象は flowchart/graph の .cluster/.node/label 幾何に限る。 非 flowchart 図 (sequence/state 等は
 * .node/.cluster を出さず vacuous)・横溢れ (label が枠/viewport を右に溢れる clip) は **未対応**。
 *
 * Playwright の page.evaluate() から `__folioRenderProbe()` として呼ぶ。
 * 戻り値: { svgCount, diagrams: [{ idx, id, caption, violations: [{kind, text, ...}] }] }
 *
 * threshold は conservative。 detector(1) の height は font-size 駆動で font 差に頑健。 面積比 detector
 * (2)(3) は text 幅依存だが mermaid dagre layout が node box を label に合わせ self-normalize するため
 * conservative threshold を跨ぎにくい。 CI は font も pin する (ci.yml fonts-noto-cjk) ことで text shaping
 * も固定する。 vendored mermaid + pinned playwright + pinned font で render を決定的にする。
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

    /* (1) 多行 cluster-label — subgraph タイトルの縦 overflow (図5 で実際に起きた class)。 */
    [...svg.querySelectorAll('.cluster')].forEach((cl) => {
      const lab = cl.querySelector('.cluster-label, foreignObject');
      if (!lab) return;
      const h = rect(lab).height;
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

    return { idx, id, caption, violations };
  });

  return { svgCount: svgs.length, diagrams };
};
