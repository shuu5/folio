/*
 * folio SRS render-gate probe — 生成 SRS プレゼン HTML の in-browser 幾何 + 色 detector (gate F)。
 *
 * taxonomy §5.2 gate F (render 健全性) の SRS 版。 既存 folio render-gate (tests/render-gate、 mermaid
 * flowchart 専用) とは別系統で、 生成 SRS プレゼンに固有の 3 class を render 後の DOM から検出する:
 *   (1) horizontal-overflow — 本文が viewport を溢れ document 全体に意図しない横スクロール
 *       (probe.js (5) と同一ロジック・同一定数値 H_OVERFLOW_TOL を複製。 drift は test-adversarial A35 が検知)
 *   (2) component-overlap   — data-component block が「別の」 data-component と矩形交差 (絶対配置・
 *       負 margin 等の崩れ。 probe.js (6) の overlap-frac 定数値 0.15 を複製、 A35 で drift 検知)
 *   (3) low-contrast        — text と実効背景の WCAG コントラスト比が AA 未満 (S3 で手検出した
 *       dark-contrast 崩壊型を gate 化)。 caller が light / dark 両 color-scheme で本 probe を呼ぶ。
 *
 * 決定性: 生成 SRS は CSS を inline 同梱 (assemble.sh) し自己完結ゆえ font 以外の外部依存がない。
 * CI は font を pin (fonts-noto-cjk) し playwright も pin (requirements.txt) するため layout が固定される。
 *
 * Playwright の page.evaluate() から `__folioSrsRenderProbe()` として呼ぶ。
 * 戻り値: { scheme, textChecked, gradientSkipped, violations: [{kind, ...}] }
 *   - textChecked: contrast を実評価した text 要素数 (0 = render 破綻 = caller が fail-closed に倒す)
 *   - gradientSkipped: 背景が gradient/image で solid 合成不能ゆえ contrast 評価を見送った要素数 (disclosed)
 */
window.__folioSrsRenderProbe = function (scheme) {
  /* === 定数 (probe.js (ADR-0037) の値を複製・現状一致。 drift は test-adversarial A35 が検知) === */
  const H_OVERFLOW_TOL = 2;        // document 横スクロールの許容 px (probe.js (5) と同値)
  const OVERLAP_FRAC = 0.15;       // block 交差面積比 (probe.js (6) NAV_OVERLAP_FRAC と同値)
  const H_OVERFLOW_MAX_CULPRITS = 5;
  /* WCAG 2.1 AA: 通常 text 4.5:1 / 大 text 3.0:1。 大 text = 18pt(=24px) 以上、 または 14pt(=18.66px)
     以上の bold (font-weight>=700)。 SC 1.4.3 の定義に一致。 */
  const AA_NORMAL = 4.5, AA_LARGE = 3.0;
  const LARGE_PX = 24, LARGE_BOLD_PX = 18.66;
  const CONTRAST_MAX_REPORT = 12;  // 同一 (fg,bg) combo は 1 件に dedupe するが、 異なる combo の上限

  /* === 幾何 helper (probe.js と同形) === */
  const rect = (el) => el.getBoundingClientRect();
  const area = (r) => Math.max(0, r.right - r.left) * Math.max(0, r.bottom - r.top);
  const interArea = (a, b) => {
    const w = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
    const h = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
    return w * h;
  };
  const snippet = (el) => ((el && el.textContent) || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  /* 描画されているか (probe.js と同基準): display:none / closed details の skip / visibility:hidden /
     完全透明 (opacity:0、 自身または祖先) を不可視扱い。 減光 (0<opacity<1) は描画されているため対象。 */
  const visible = (el) =>
    typeof el.checkVisibility === 'function'
      ? el.checkVisibility({ visibilityProperty: true, checkVisibilityCSS: true, opacityProperty: true, checkOpacity: true })
      : true;

  /* === 色 helper (WCAG) === */
  // 任意の CSS 色文字列 (rgb/rgba の comma・space・slash 各構文 / hsl / hwb / lab / lch / oklab / oklch /
  // color() / hex / 名前付き / transparent) を **1×1 canvas 経由で sRGB の {r,g,b,a} に解決**する。
  // Chromium は computed 値で modern color space (oklch 等) を rgb 正規化せず関数形のまま保持するため、
  // regex split では (a) oklch 停止色を読めず gradient を image 誤判定して skip / (b) space/slash 構文で
  // NaN→fail-open する穴があった。 canvas は表示と同じ sRGB へ一律解決し WCAG 計算に直接使える。
  const _cv = document.createElement('canvas'); _cv.width = _cv.height = 1;
  const _ctx = _cv.getContext('2d', { willReadFrequently: true });
  const _ccache = new Map();
  const parseColor = (s) => {
    if (!s || s === 'none') return null;
    if (_ccache.has(s)) return _ccache.get(s);
    // 2 sentinel で無効値を判定 (無効な fillStyle 代入は無視され前値が残るため、 黒/白で違えば無効)。
    _ctx.fillStyle = '#000'; _ctx.fillStyle = s; const ok1 = _ctx.fillStyle;
    _ctx.fillStyle = '#fff'; _ctx.fillStyle = s; const ok2 = _ctx.fillStyle;
    if (ok1 !== ok2) { _ccache.set(s, null); return null; }
    _ctx.clearRect(0, 0, 1, 1); _ctx.fillStyle = s; _ctx.fillRect(0, 0, 1, 1);
    const d = _ctx.getImageData(0, 0, 1, 1).data;
    const c = { r: d[0], g: d[1], b: d[2], a: d[3] / 255 };
    _ccache.set(s, c); return c;
  };
  // fg(α付き) を bg(不透明) の上に alpha 合成: out = α·fg + (1-α)·bg。
  const over = (fg, bg) => ({
    r: fg.a * fg.r + (1 - fg.a) * bg.r,
    g: fg.a * fg.g + (1 - fg.a) * bg.g,
    b: fg.a * fg.b + (1 - fg.a) * bg.b,
    a: 1,
  });
  // WCAG 相対輝度。
  const lum = (c) => {
    const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => { const la = lum(a), lb = lum(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05); };

  // CSS background は複数レイヤーを top-level カンマで重ねる (先頭=最前面)。 rgb()/gradient() 内の
  // カンマで割らないよう括弧深度 0 のカンマでのみ分割する。
  const splitLayers = (s) => {
    const out = []; let depth = 0, cur = '';
    for (const ch of s) {
      if (ch === '(') depth++; else if (ch === ')') depth--;
      if (ch === ',' && depth === 0) { out.push(cur); cur = ''; } else cur += ch;
    }
    if (cur.trim()) out.push(cur);
    return out;
  };
  // 1 レイヤー (gradient 文字列) の停止色を抽出。 色関数 (rgb/hsl/hwb/lab/lch/oklab/oklch/color) と hex を
  // 拾い canvas で sRGB 解決する。 色トークンが 1 つも無い (url() image 等) なら空 (= 停止色抽出不能)。
  const layerStops = (layerStr) => {
    const re = /(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\([^)]*\)|#[0-9a-fA-F]{3,8}/gi;
    const out = []; let m;
    while ((m = re.exec(layerStr)) !== null) { const c = parseColor(m[0]); if (c) out.push(c); }
    return out;
  };
  // 半透明 layer 群 (el→上 順・添字小=手前) を base の上に合成する。
  const composite = (base, layers) => { let cur = base; for (let i = layers.length - 1; i >= 0; i--) cur = over(layers[i], cur); return cur; };
  // 候補色が増えすぎたら輝度でソートし *等間隔に* 間引く (両極だけ残すと fg 輝度に最も近い中間候補=
  // worst-case を落とし false-negative になるため、 端点を含めつつ中間も保つ luminance サンプリング)。
  const decimate = (cs, n) => {
    if (cs.length <= n) return cs;
    const s = cs.slice().sort((a, b) => lum(a) - lum(b));
    const out = []; for (let i = 0; i < n; i++) out.push(s[Math.round((i * (s.length - 1)) / (n - 1))]);
    return out;
  };
  /* 実効背景: 要素から祖先へ遡り、 最初の不透明 background-color を底に、 その上の半透明 bg-color を合成
     して text 直下の実効背景色を返す。 gradient/image 背景に当たったら:
       - 各レイヤーの停止色を抽出できれば、 **最下レイヤーを base に上レイヤーを順に alpha 合成** して
         実在しうる背景色の集合 (candidate stops) を作り、 caller が worst-case (最小コントラスト) で判定する。
         これで「暗い勾配の上に薄い白オーバーレイ」を *白背景* と誤認しない (合成して僅かに明るい暗色になる)。
       - 停止色を抽出できない background (url() image 等) を含むレイヤー、 または勾配の下地が更に勾配/image の
         祖先 (base 不定) の場合は {gradient:true} で skip し件数を disclose する。 */
  const effectiveBg = (el) => {
    const semis = []; // el→上 順に積む半透明 bg-color (gradient より手前)
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage && cs.backgroundImage !== 'none') {
        const layers = splitLayers(cs.backgroundImage).map(layerStops); // [top..bottom]、 各=[停止色]
        if (layers.some((l) => l.length === 0)) return { gradient: true }; // 停止色抽出不能 (url image 等) → skip
        let below = { r: 255, g: 255, b: 255, a: 1 }; // 勾配の下の不透明 base
        for (let e2 = e.parentElement; e2; e2 = e2.parentElement) {
          const cs2 = getComputedStyle(e2);
          if (cs2.backgroundImage && cs2.backgroundImage !== 'none') return { gradient: true }; // 入れ子勾配=base 不定 → skip
          const cb = parseColor(cs2.backgroundColor);
          if (cb && cb.a >= 0.999) { below = cb; break; }
        }
        let cands = [below];
        for (let li = layers.length - 1; li >= 0; li--) { // bottom→top に重ねる
          const next = [];
          for (const C of cands) for (const S of layers[li]) next.push(S.a >= 0.999 ? S : over(S, C));
          cands = decimate(next, 64);
        }
        return { stops: cands.map((C) => composite(C, semis)) }; // 手前の半透明 bg-color を最後に載せる
      }
      const c = parseColor(cs.backgroundColor);
      if (c && c.a > 0) {
        if (c.a >= 0.999) return { color: composite(c, semis) };
        semis.push(c);
      }
    }
    return { color: composite({ r: 255, g: 255, b: 255, a: 1 }, semis) }; // canvas 既定 = 白
  };

  const hex = (c) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');

  const violations = [];

  /* === (1) horizontal-overflow (probe.js (5) と同一ロジック) === */
  const de = document.documentElement;
  const docOver = de.scrollWidth - de.clientWidth;
  if (docOver > H_OVERFLOW_TOL) {
    const all = document.body ? document.body.querySelectorAll('*') : [];
    const culprits = [];
    outer: for (const el of all) {
      const r = rect(el);
      if (area(r) < 4 || !visible(el)) continue;
      const over_ = r.right - de.clientWidth;
      if (over_ <= H_OVERFLOW_TOL) continue;
      for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
        if (getComputedStyle(p).overflowX !== 'visible') continue outer; // 内部 scroll/clip は document に伝播しない
      }
      culprits.push({ el, over: over_ });
    }
    const top = culprits.filter((c) => !culprits.some((o) => o !== c && o.el.contains(c.el)));
    if (top.length === 0) {
      violations.push({ kind: 'horizontal-overflow', text: '(culprit 特定不能)', overflowPx: Math.round(docOver) });
    }
    top.sort((a, b) => b.over - a.over).slice(0, H_OVERFLOW_MAX_CULPRITS).forEach((c) => {
      violations.push({ kind: 'horizontal-overflow', text: `<${c.el.tagName.toLowerCase()}> ${snippet(c.el)}`, overflowPx: Math.round(c.over) });
    });
    if (top.length > H_OVERFLOW_MAX_CULPRITS) {
      violations.push({ kind: 'horizontal-overflow', text: `(他 ${top.length - H_OVERFLOW_MAX_CULPRITS} 要素)`, overflowPx: Math.round(docOver) });
    }
  }

  /* === (2) component-overlap — data-component に「別の可視 block」が矩形交差 === */
  /* SRS の構造単位 = data-component。 一方を [data-component]、 他方を *広い block 集合* (probe.js
     nav-over-content と同様に素の div/li も含む — semantic 限定は実証済 false-negative) に取り、
     コンポーネント同士だけでなく **非コンポーネント要素 (装飾オーバーレイ等) がコンポーネントに被る崩れ**
     も捕捉する。 通常 flow では矩形は交差しない (overlap は absolute/fixed・負 margin の崩れでのみ生じる)。
     祖先/子孫 (row⊂table⊂section 等の入れ子) は包含であって欠陥でないため除外。 inline は親 block に
     包含され除外される。 */
  const BLOCK_SEL = 'main, article, header, section, h1, h2, h3, h4, h5, h6, p, ul, ol, li, dl, div, table, pre, figure, blockquote, details, [data-component]';
  const named = (el) => el.getAttribute('data-component') || `<${el.tagName.toLowerCase()}>`;
  const comps = [...document.querySelectorAll('[data-component]')]
    .filter((el) => visible(el)).map((el) => ({ el, r: rect(el) })).filter((x) => area(x.r) >= 16);
  const blocks = [...document.querySelectorAll(BLOCK_SEL)]
    .filter((el) => visible(el)).map((el) => ({ el, r: rect(el) })).filter((x) => area(x.r) >= 16);
  const reportedPairs = new Set();
  for (const a of comps) {
    for (const b of blocks) {
      if (a.el === b.el || a.el.contains(b.el) || b.el.contains(a.el)) continue;
      const frac = interArea(a.r, b.r) / Math.min(area(a.r), area(b.r) || 1);
      if (frac <= OVERLAP_FRAC) continue;
      const pair = [named(a.el) + '|' + snippet(a.el), named(b.el) + '|' + snippet(b.el)].sort().join(' ∩ ');
      if (reportedPairs.has(pair)) continue; // comp×comp は双方向に当たるので dedupe
      reportedPairs.add(pair);
      violations.push({
        kind: 'component-overlap',
        text: `${named(a.el)}「${snippet(a.el)}」 ∩ ${named(b.el)}「${snippet(b.el)}」`,
        frac: +frac.toFixed(2),
      });
    }
  }

  /* === (3) low-contrast — text ↔ 実効背景の WCAG AA === */
  let textChecked = 0, gradientSkipped = 0;
  const seen = new Set(); // (fg|bg|large) combo dedupe — 同一 CSS 由来の反復を 1 件に畳む
  const all = document.body ? document.body.querySelectorAll('*') : [];
  for (const el of all) {
    // 直接の非空白 text node を持つ要素だけ (container の二重計上を避ける)。
    let hasText = false;
    for (const node of el.childNodes) {
      if (node.nodeType === 3 && node.textContent.trim().length) { hasText = true; break; }
    }
    if (!hasText || !visible(el)) continue;
    const r = rect(el);
    if (area(r) < 4) continue;
    const cs = getComputedStyle(el);
    const fg0 = parseColor(cs.color);
    if (!fg0) continue;
    const bgr = effectiveBg(el);
    if (bgr.gradient) { gradientSkipped++; continue; }
    const cands = bgr.stops || [bgr.color];   // gradient なら複数停止色、 solid なら 1 色
    textChecked++;
    const fontPx = parseFloat(cs.fontSize) || 16;
    const bold = (parseInt(cs.fontWeight, 10) || 400) >= 700;
    const large = fontPx >= LARGE_PX || (fontPx >= LARGE_BOLD_PX && bold);
    const need = large ? AA_LARGE : AA_NORMAL;
    // 複数停止色がある場合は **最悪 (最小比) の停止**で判定する (勾配の薄い端でも崩れなければ可)。
    let worstCr = Infinity, worstBg = cands[0];
    for (const bgc of cands) {
      const f = fg0.a < 1 ? over(fg0, bgc) : fg0; // 半透明 text はその背景の上で合成
      const cr = ratio(f, bgc);
      if (cr < worstCr) { worstCr = cr; worstBg = bgc; }
    }
    if (worstCr < need) {
      const fgEff = fg0.a < 1 ? over(fg0, worstBg) : fg0;
      const key = `${hex(fgEff)}|${hex(worstBg)}|${large}`;
      if (seen.has(key)) continue;
      seen.add(key);
      if (seen.size <= CONTRAST_MAX_REPORT) {
        violations.push({
          kind: 'low-contrast', text: snippet(el),
          ratio: +worstCr.toFixed(2), need, fg: hex(fgEff), bg: hex(worstBg),
          size: Math.round(fontPx), large,
        });
      }
    }
  }
  if (seen.size > CONTRAST_MAX_REPORT) {
    violations.push({ kind: 'low-contrast', text: `(他 ${seen.size - CONTRAST_MAX_REPORT} 種の低コントラスト combo)`, ratio: 0, need: AA_NORMAL, fg: '', bg: '' });
  }

  return { scheme, textChecked, gradientSkipped, violations };
};
