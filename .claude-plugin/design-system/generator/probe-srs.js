/*
 * folio SRS render-gate probe — 生成 SRS プレゼン HTML の in-browser 幾何 + 色 detector (gate F)。
 *
 * taxonomy §5.2 gate F (render 健全性) の SRS 版。 既存 folio render-gate (tests/render-gate、 mermaid
 * flowchart 専用) とは別系統で、 生成 SRS プレゼンに固有の 4 class を render 後の DOM から検出する:
 *   (1) horizontal-overflow — 本文が viewport を溢れ document 全体に意図しない横スクロール
 *       (probe.js (5) と同一ロジック・同一定数値 H_OVERFLOW_TOL を複製。 drift は test-adversarial A35 が検知)
 *   (2) component-overlap   — data-component block が「別の」 data-component と矩形交差 (絶対配置・
 *       負 margin 等の崩れ。 probe.js (6) の overlap-frac 定数値 0.15 を複製、 A35 で drift 検知)
 *   (2b) clipped-content    — overflow-x:hidden/clip な要素が中身を横に溢れ、 読めない上に scroll も
 *       できない (狭幅で dense table が列潰れ → wrap が clip する mobile-clip 盲点。 folio-276 #2)。
 *       (1) は overflow 非 visible 祖先を「内部 scroll」と除外するため clip された中身を素通りする。
 *   (3) low-contrast        — text と実効背景の WCAG コントラスト比が AA 未満 (S3 で手検出した
 *       dark-contrast 崩壊型を gate 化)。 caller が light / dark 両 color-scheme で本 probe を呼ぶ。
 *
 * 決定性: 生成 SRS は CSS を inline 同梱 (assemble-srs.sh) し自己完結ゆえ font 以外の外部依存がない。
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

  /* === (2b) clipped-content (mobile-clip) — overflow-x:hidden/clip な要素が中身を横に溢れさせ、
     読めない上に scroll もできない盲点を捕捉する (folio-276 #2)。 狭幅 (375-390px) で dense table を
     内包する .tbl-wrap 等が列を潰し clip する型。 horizontal-overflow (1) は overflow 非 visible の祖先を
     「内部 scroll で document へ伝播しない」と見なし除外するため、 clip された中身は document overflow に
     ならず (1) を素通りする (= mobile-clip 盲点)。 overflow-x:auto/scroll (= 横スクロールで到達可能) は
     健全ゆえ対象外 — hidden/clip で *到達不能に切り落とされた* 中身だけが欠陥。 === */
  const CLIP_TOL = H_OVERFLOW_TOL; // 横 clip の許容 px。 H_OVERFLOW_TOL を直接参照し drift 不能にする
                                   // (別リテラルだと A35 drift 検査の対象外で「同値」コメントが静かに腐る)
  const CLIP_MAX_CULPRITS = 5;
  const clipCands = [];
  for (const el of (document.body ? document.body.querySelectorAll('*') : [])) {
    if (!visible(el)) continue;
    const ox = getComputedStyle(el).overflowX;
    if (ox !== 'hidden' && ox !== 'clip') continue;      // auto/scroll は到達可能ゆえ健全
    const over = el.scrollWidth - el.clientWidth;         // clip された中身の溢れ量 (clientWidth=内容ボックス幅)
    if (over <= CLIP_TOL) continue;
    if (area(rect(el)) < 16) continue;
    clipCands.push({ el, over });
  }
  // clip 要素が別の clip 要素に入れ子なら最外だけ報告 (二重計上回避、 (1) と同形)
  const topClip = clipCands.filter((c) => !clipCands.some((o) => o !== c && o.el.contains(c.el)));
  topClip.sort((a, b) => b.over - a.over).slice(0, CLIP_MAX_CULPRITS).forEach((c) => {
    violations.push({ kind: 'clipped-content', text: `<${c.el.tagName.toLowerCase()}> ${snippet(c.el)}`, clipPx: Math.round(c.over) });
  });
  if (topClip.length > CLIP_MAX_CULPRITS) {
    violations.push({ kind: 'clipped-content', text: `(他 ${topClip.length - CLIP_MAX_CULPRITS} 要素)`, clipPx: 0 });
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

/*
 * folio SRS render census probe — gate F (visual 健全性) の *sibling gate*。
 * gate F が「見えるが崩れている」を見るのに対し、 本 census は「契約上あるべき内容が描画後に存在するか・
 * 描画後に偽の内容が注入されていないか」= **描画後 content-fidelity** を見る (folio-6jb 縦軸)。
 * folio-wq4 final ceiling が carve した 2 render 依存 vector を封鎖する:
 *   (2b8) pseudo-content-fabrication — 任意要素に ::before/::after の content で *偽テキストを注入* する捏造。
 *         静的 grep (make_body は <style> を空化) を素通りし、 render してはじめて見える。 **inverse-allowlist**:
 *         body 全要素の ::before/::after を走査し、 genuine chrome の小 allowlist (3 値・両 fixture×両 scheme で
 *         監査確定) に厳密一致しない非空 content を捏造とみなす (集合の補集合=捏造)。 固定 semantic 集合の reverse
 *         -assert は corpus-disjoint で contract-bearing class を取りこぼしたため廃した (独立 ceiling wxnjdmjk9)。
 *         空/空白 content は描画されず無害ゆえ許容。 attr() 動的注入も render が解決した値を見るので捕捉する。
 *   (459)  census-omission/excess — 必須要素 (要件行/NFR 行) を comment/style 等で包み静的 grep を通しつつ
 *         **ブラウザ非描画**にする OMISSION。 描画後の *実描画* element 数 (checkVisibility ∧ area>16 ∧ clip 祖先
 *         なし = clip-path/transform/子崩壊も捕捉) を contract 由来期待件数と照合し、 可視<期待 を omission、
 *         可視>期待 を excess とする。 加えて .plain (平易説明) は static-present==描画可視 を要求する (sub-slot
 *         omission)。 **被覆の honest scope**: prefers-color-scheme と検査 3 viewport 幅 (375/768/1280) の軸のみ
 *         走査する。 他軸の条件付き隠蔽 (@media print/orientation/その他幅・off-screen position・filter/mask) は
 *         射程超ゆえ carve 済 (bd folio-cpf〔folio-4a4 css-hiding 系〕 + LLM ceiling backstop)。 font-size:0 は
 *         visibleTextArea の最小可読高 floor (絶対 4px) が被覆ゆえ carve でない (round-3c)。
 *
 * 期待件数は caller (verify-srs.sh) が contract から導出し JSON で注入する (probe は contract schema 非依存・
 * 論点5 決定)。 戻り値: { totalExpected, totalVisible, violations: [{kind, ...}] }。
 *   - totalVisible==0 && totalExpected>0 は census-omission で必ず FAIL に倒れる (T7 fail-closed: render 破綻と
 *     genuine omission を caller が区別して報告する。 描画されていない=「clean」と取り違えない)。
 *
 * @param expectJson  JSON 文字列 { counts: { "<data-component>": <int>, ... } } (pseudo 列挙は inverse-allowlist 化で不要)
 */
window.__folioSrsRenderCensus = function (expectJson) {
  const expect = JSON.parse(expectJson);
  const snippet = (el) => ((el && el.textContent) || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  const violations = [];

  /* === (2b8) pseudo-content-fabrication — inverse-allowlist (独立 ceiling wxnjdmjk9 + ws4o6ywe5 強化) ===
     body 全要素 + body/html 自身の ::before/::after/::marker を走査し、 genuine chrome の小 allowlist に厳密一致
     しない非空 content を捏造とみなす (集合の補集合=捏造・MEMORY「機械的完全性照合」)。 固定 semantic 集合の反転
     assert (旧 7-set) は contract-bearing class を取りこぼしたため inverse-allowlist 化済。 さらに ws4o6ywe5 で
     ::marker (display:list-item で任意要素に付く) と body::before/html::before ('body *' は body 自身を含まない) の
     射程漏れを塞ぐ。 genuine chrome pseudo は 3 値のみ。 空/空白 content は描画されず無害ゆえ許容。 */
  const CHROME_PSEUDO = [
    { sel: '.plain', pe: '::before', content: 'やさしく言うと ' },
    { sel: '.why', pe: '::before', content: '↳ なぜ要る' },
    { sel: 'summary', pe: '::after', content: 'クリックで開閉' },
  ];
  const dequote = (s) => s.replace(/^"([\s\S]*)"$/, '$1').replace(/^'([\s\S]*)'$/, '$1');
  const pseudoScan = [document.documentElement, document.body, ...document.querySelectorAll('body *')].filter(Boolean);
  for (const el of pseudoScan) {
    for (const pe of ['::before', '::after', '::marker']) {
      const raw = getComputedStyle(el, pe).content;
      if (!raw || raw === 'none' || raw === 'normal') continue;
      const val = dequote(raw);
      if (val.trim() === '') continue; // 空/空白文字列 = 描画されない = 無害
      const ok = CHROME_PSEUDO.some((w) => w.pe === pe && el.matches(w.sel) && val === w.content);
      if (!ok) {
        const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
        violations.push({ kind: 'pseudo-content-fabrication', text: `${el.tagName.toLowerCase()}${cls}${pe} 「${snippet(el)}」 に content=${raw}`, pseudo: pe, content: raw });
      }
    }
  }

  /* === (round-3c wf_534bb2c7) generated-content scroll pseudo-elements — ::scroll-button(dir) / ::scroll-marker ===
     これら generated-content pseudo は content を持ち偽要件を可視描画するが、 上の pseudoScan は ::before/::after/
     ::marker のみ走査した射程穴 (carve agent 実証: census exit0 で FR99/FR98 が可視・fidelity textContent も blind)。
     genuine SRS は scroll container を一切使わない (verified) ゆえ、 これら scroll pseudo の非空 content を捏造とみなす
     (genuine vocabulary 補集合)。 ::scroll-button は functional ゆえ direction 全変種を走査し 1 要素 1 件に dedup。
     computed-style 走査ゆえ CSS escape も spelling-agnostic に正規化済で robust (verify-srs.sh 静的 ban の render 側補完)。 */
  const SCROLL_BTN_DIRS = ['up', 'down', 'left', 'right', 'block-start', 'block-end', 'inline-start', 'inline-end'];
  const flagScrollPseudo = (el, pe, raw) => {
    if (!raw || raw === 'none' || raw === 'normal' || dequote(raw).trim() === '') return false;
    const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
    violations.push({ kind: 'pseudo-content-fabrication', text: `${el.tagName.toLowerCase()}${cls}${pe} 「${snippet(el)}」 に content=${raw}`, pseudo: pe, content: raw });
    return true;
  };
  for (const el of pseudoScan) {
    try { flagScrollPseudo(el, '::scroll-marker', getComputedStyle(el, '::scroll-marker').content); } catch (e) { /* pseudo 非対応 browser */ }
    for (const d of SCROLL_BTN_DIRS) {
      let raw; try { raw = getComputedStyle(el, `::scroll-button(${d})`).content; } catch (e) { continue; }
      if (flagScrollPseudo(el, `::scroll-button(${d})`, raw)) break; // 同一要素の direction quirk 重複を回避
    }
  }

  /* === (round-3f wf_27813514) list-marker census — list-style-type 由来の generated marker 偽テキスト ===
     ::marker テキストは content でなく list-style-type + @counter-style (symbols/prefix/suffix) / 文字列リテラルで生成され、
     静的 list-marker-ban は var() 間接化 (list-style-type:var(--x)) と CSS escape (@counter-\73 tyle) で回避された (ceiling 実証)。
     chromium は computed-style で両者を解決するため render 側で getComputedStyle(el).listStyleType を spelling-agnostic に走査し、
     marker を描画する list-item で (a) 引用符付き文字列値 or (b) 標準キーワード allowlist 外の ident (= @counter-style 参照) を
     捏造 marker とみなす (image-sink/scroll-pseudo と同型・folio-wq4 教訓: literal ban でなく computed 正規化値で閉じる)。
     genuine SRS の computed listStyleType は {disc, none} のみ (verified) ゆえ FP-free。 静的 ban は render 不在 backstop。 */
  const STD_LIST_STYLE = new Set(['none', 'disc', 'circle', 'square', 'decimal', 'decimal-leading-zero',
    'lower-roman', 'upper-roman', 'lower-alpha', 'upper-alpha', 'lower-latin', 'upper-latin', 'lower-greek',
    'armenian', 'georgian', 'cjk-decimal', 'cjk-ideographic', 'hebrew', 'hiragana', 'hiragana-iroha',
    'katakana', 'katakana-iroha', 'arabic-indic', 'thai', 'devanagari', 'korean-hangul-formal',
    'disclosure-open', 'disclosure-closed']);
  for (const el of pseudoScan) {
    let lcs; try { lcs = getComputedStyle(el); } catch (e) { continue; }
    if (!/list-item/.test(lcs.display || '')) continue; // marker を実描画する list-item のみ (list-style-type は継承するが marker box は list-item のみ)
    const lst = (lcs.listStyleType || '').trim();
    if (!lst || lst === 'none') continue;
    if (/^["']/.test(lst) || !STD_LIST_STYLE.has(lst.toLowerCase())) { // 引用符付き文字列 or 標準キーワード外 ident (= @counter-style 参照)
      const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
      violations.push({ kind: 'list-marker-fabrication', text: `${el.tagName.toLowerCase()}${cls} に非標準 list-style-type=${lst} (generated marker 捏造)`, listStyleType: lst });
    }
  }

  /* === (round-3g wf_20e96424) @counter-style CSSOM census — allowlist builtin 名 override を escape-robust に捕捉 ===
     上の list-marker census は allowlist 帰属を信頼するが、 @counter-style は allowlist builtin 名 (lower-roman 等) を再定義し
     computed list-style-type を allowlist 名のまま偽 marker を描画できる (ceiling 実証)・escaped @counter-\73 tyle は静的 ban も回避。
     genuine SRS は @counter-style を一切使わない (CSSCounterStyleRule=0・verified) ゆえ CSSOM 上の CSSCounterStyleRule の *存在自体*
     を捏造とみなす (静的 @counter-style ban の render 側 escape-robust mirror・CSSOM は escape を解決済)。 */
  const collectCounterStyle = (rules, out) => {
    for (const r of rules) {
      if (r.type === 11 || (r.constructor && r.constructor.name === 'CSSCounterStyleRule')) out.push(r);
      else if (r.cssRules) { try { collectCounterStyle(r.cssRules, out); } catch (e) { /* @import cross-origin 等 */ } }
    }
  };
  try {
    const csr = [];
    for (const ss of document.styleSheets) { try { collectCounterStyle(ss.cssRules, csr); } catch (e) { /* cross-origin sheet */ } }
    for (const r of csr) violations.push({ kind: 'list-marker-fabrication', text: `@counter-style ${r.name || '?'} 定義 (allowlist builtin override で偽 marker・CSSOM census)`, counterStyle: r.name });
  } catch (e) { /* CSSOM 非対応 */ }

  /* === (round-3g wf_20e96424) bidi-override render census — computed unicode-bidi で escape-robust に視覚反転を捕捉 ===
     静的 bidi-override-ban (verify-srs.sh) は source literal grep ゆえ CSS escape (\62 idi-override) で回避された (ceiling 実証・
     image-sink で学んだ parser-differential を bidi で再発)。 chromium は computed unicode-bidi へ escape を解決するため render 側で
     spelling-agnostic に走査し、 'override' を含む値 (bidi-override / isolate-override) を視覚反転捏造とみなす。 genuine の computed
     unicode-bidi は {normal, isolate} のみ (override=0・verified・isolate≠override ゆえ table UA 既定を誤検出しない) で FP-free。 */
  for (const el of pseudoScan) {
    let ub; try { ub = getComputedStyle(el).unicodeBidi; } catch (e) { continue; }
    if (ub && /override/.test(ub)) {
      const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
      violations.push({ kind: 'bidi-override-fabrication', text: `${el.tagName.toLowerCase()}${cls} に unicode-bidi=${ub} (制御 codepoint 無し視覚反転)`, unicodeBidi: ub });
    }
  }

  /* === (FF1) own-element content-fabrication (folio-hef S1) — 要素自身の content で replaced-element 捏造 ===
     pseudo (::before/::after/::marker) でなく *要素自身* に content:url(...) を当てると replaced element 化し
     偽 SVG/画像として描画される (glossary/acceptance 等を消して偽内容を捏造・round2 FF1 e1/e2)。 上の pseudo
     走査は getComputedStyle(el, pe) のみで要素自身の content を読まない射程穴。 genuine SRS は regular element の
     content を normal/none 以外に設定しない (srs.css verified: 全 content: は ::before/::after pseudo) =
     positive invariant「要素自身の content ∈ {normal, none}」の補集合を捏造とみなす (β: 構造的不変条件)。 */
  for (const el of pseudoScan) {
    const own = getComputedStyle(el).content;
    if (!own || own === 'none' || own === 'normal') continue;
    if (dequote(own).trim() === '') continue; // 空 content は描画されない = 無害
    const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
    violations.push({ kind: 'own-content-fabrication', text: `${el.tagName.toLowerCase()}${cls} 自身に content=${own} (replaced-element 捏造)`, content: own });
  }

  /* === (FF5 folio-hef S1・round-3c wf_534bb2c7) computed-style image-sink census — spelling-agnostic ===
     静的 url-ban (verify-srs.sh) は CSS-escape (\75 rl) / image-set() bare-string / 無数の綴りで回避される
     (partial-enum・folio-wq4 parser-differential 教訓)。 chromium は全綴りを computed-style で canonical
     url("data:...") へ正規化済 (実機確認: \75 rl→url(data:) / image-set→image-set(url(data:)))。 ゆえ render 側で
     image 系計算値プロパティ (要素 + ::before/::after) の url() を spelling-agnostic に走査し、 target が
     same-document #fragment 以外 (data:/外部/別 doc) を捏造 image sink とみなす (β: 構造的不変条件の補集合)。
     genuine SRS は image url()=0 (srs.css verified)・url(#gradient) は same-doc fragment 判定で allow。
     mask-image は folio-cpf carve (occlusion 系)・content は own-content/pseudo arm で被覆ゆえ対象外。 */
  const IMG_PROPS = ['backgroundImage', 'borderImageSource', 'listStyleImage'];
  // computed-style は url() を常に "..." 引用形へ正規化する (image-set / CSS escape も同様)。 引用内の data: URL は
  // SVG の xmlns='...' 等で ' や " を含むため、 素朴な [^"')]* は早期終端する。 引用/非引用 3 形を escape 込みで抽出する。
  const urlTokens = (v) => {
    const out = [];
    const re = /url\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^)\s]*))\s*\)/g;
    let m;
    while ((m = re.exec(v))) out.push(m[1] !== undefined ? m[1] : (m[2] !== undefined ? m[2] : m[3]));
    return out;
  };
  const sameDocFrag = (raw) => { try { const u = new URL(raw, document.baseURI); return u.hash !== '' && u.href.split('#')[0] === new URL(document.baseURI).href.split('#')[0]; } catch (e) { return false; } };
  // (round-3d wf_6e852552) ::first-line / ::first-letter も background-image / border-image / list-style-image を実描画する
  // (ceiling 実証: ::first-letter{padding:0 470px;background:\75 rl(data:SVG)} で偽要件を背景描画・census/url-ban 両盲点)。
  // 旧 [null,::before,::after] の射程外ゆえ pe 集合へ追加 (::backdrop も防御的に・genuine ec/clinic は 0 件=FP-free)。
  for (const el of pseudoScan) {
    for (const pe of [null, '::before', '::after', '::first-line', '::first-letter', '::backdrop']) {
      let cs; try { cs = getComputedStyle(el, pe); } catch (e) { continue; }
      for (const prop of IMG_PROPS) {
        const v = cs[prop];
        if (!v || v === 'none') continue;
        for (const tok of urlTokens(v)) {
          if (!tok || sameDocFrag(tok)) continue;
          const cls = el.className && typeof el.className === 'string' ? '.' + el.className.trim().replace(/\s+/g, '.') : '';
          violations.push({ kind: 'image-sink-fabrication', text: `${el.tagName.toLowerCase()}${cls}${pe || ''} の ${prop} に外部/data: image sink url(${tok.slice(0, 40)}…) (image-sink 捏造)`, prop, content: v });
        }
      }
    }
  }

  /* === (FF1 time-axis・独立 ceiling wf_b544a704) content を animation で時刻遅延フリップする捏造 — *直接 content-keyframe のみ* ===
     content を時刻 0 で normal、 animation-delay 後に url() へ step フリップする直接 content-keyframe animation を、
     走る animation の keyframes が content を normal/none 以外へ触れば flag する (genuine SRS は content を animate
     しない・srs.css verified = positive invariant の補集合)。 Animation.finish() は content end 値を適用しない
     (chromium 実機検証済) ため keyframe を *構造的*に検査する。 ★保証範囲は「直接 content-keyframe animation」に限る:
     content を @container style-query / カスタムプロパティで gate し gate 値を transition / infinite-keyframe で時刻
     駆動すると content が keyframe に現れず本検査を素通る (round-2 ceiling wf_0900ca71 e6/e7・実描画確認済)。 この
     CSS-gated 時間軸 reveal と interaction-state gated (:target/:hover/:checked) reveal は behavioral 多時刻 sampling
     でも収束しない partial-enum 境界ゆえ floor 射程外として carve (REQ-VER-027 + folio-cpf・LLM ceiling =
     persona-walk-srs / fidelity-srs backstop・user 判断 2026-06-30)。 */
  let docAnims;
  try { docAnims = document.getAnimations(); } catch (e) { docAnims = []; }
  for (const a of docAnims) {
    let kfs;
    try { kfs = a.effect && a.effect.getKeyframes ? a.effect.getKeyframes() : []; } catch (e) { kfs = []; }
    const hit = kfs.some((k) => k && typeof k.content === 'string' && k.content !== 'normal' && k.content !== 'none' && dequote(k.content).trim() !== '');
    if (hit) {
      const tgt = a.effect && a.effect.target;
      const cls = tgt && tgt.className && typeof tgt.className === 'string' ? '.' + tgt.className.trim().replace(/\s+/g, '.') : '';
      const tag = tgt && tgt.tagName ? tgt.tagName.toLowerCase() : '?';
      violations.push({ kind: 'own-content-fabrication', text: `${tag}${cls} に content を時刻フリップする animation (時間 reveal 捏造)`, content: 'animated-content' });
    }
  }

  /* === 実描画判定 helper (独立 ceiling wxnjdmjk9 + ws4o6ywe5 強化) ===
     checkVisibility は display:none/visibility/opacity===0/content-visibility のみモデル化し、 clip-path /
     transform:scale(0) / 子要素 display:none 行崩壊 / overflow:hidden 祖先クリップ / 微小高さ overflow / near-zero
     opacity を見ない。 これらを補い「読者に描画されない要素」を omission に倒す。 残る off-screen position /
     非検査軸 @media / filter・mask / z-order occlusion (不透明 overlay) は floor 射程超 (bd folio-cpf〔folio-4a4
     css-hiding 系〕) ゆえ carve + LLM ceiling (persona-walk-srs) backstop。 font-size:0 は visibleTextArea の最小
     可読高 floor (絶対 4px) が被覆ゆえ carve でない (round-3c 検証: census-omission 発火)。 */
  const checkVis = (el) =>
    typeof el.checkVisibility === 'function'
      ? el.checkVisibility({ visibilityProperty: true, checkVisibilityCSS: true, opacityProperty: true, checkOpacity: true })
      : true;
  const clipPathHidden = (el) => { // 祖先/自身のいずれかに clip-path/clip があれば paint されない (inset(100%) 等)
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.clipPath && cs.clipPath !== 'none') return true;
      if (cs.clip && cs.clip !== 'auto') return true;
    }
    return false;
  };
  // bounding rect を overflow:hidden/clip 祖先の rect と交差した可視面積 (transform:scale(0)=元 rect 0 も含む)。
  // (FF2 folio-hef S1) contain:paint/strict/content 祖先も descendant の paint を border-box にクリップするため
  // overflow:hidden と同様に交差源に含める (height:0+overflow:visible+contain:paint で layout は自然サイズのまま
  // paint だけ 0px に潰す round2 FF2 e3 を封鎖。 genuine SRS は contain を使わない・verified)。
  const visibleArea = (el) => {
    const r = el.getBoundingClientRect();
    let l = r.left, t = r.top, rt = r.right, b = r.bottom;
    for (let e = el.parentElement; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      const ov = (cs.overflow || '') + (cs.overflowX || '') + (cs.overflowY || '');
      const containsPaint = /\b(paint|strict|content)\b/.test(cs.contain || '');
      if (/hidden|clip/.test(ov) || containsPaint) {
        const er = e.getBoundingClientRect();
        l = Math.max(l, er.left); t = Math.max(t, er.top); rt = Math.min(rt, er.right); b = Math.min(b, er.bottom);
      }
    }
    return Math.max(0, rt - l) * Math.max(0, b - t);
  };
  // 自己 overflow:hidden/clip で *縦* content (scrollHeight) が box (clientHeight) の半分超を切り捨てる (微小高さ行)。
  // 縦に限定するのは横 overflow:hidden + text-overflow:ellipsis が genuine の正当パターンゆえ (誤検出回避)。
  const selfContentClipped = (el) => {
    const cs = getComputedStyle(el);
    const ov = (cs.overflowY || '') + (cs.overflow || '');
    if (!/hidden|clip/.test(ov)) return false;
    return el.scrollHeight > el.clientHeight + 4 && el.clientHeight < el.scrollHeight * 0.5;
  };
  // (FF2 folio-hef S1・独立 ceiling wf_b544a704 + round-2 wf_0900ca71 + round-3b wf_3652702e) counted 要素の *実描画テキスト面積*。
  // 各テキスト node の fragment rect (Range.getClientRects) を、 その text node の祖先連鎖 (el 含む・text→el 降下連鎖) 上の
  // 全 clip 機構 (overflow:hidden/clip + contain:paint/strict/content の box 交差 + clip-path/clip 不可視化 + 連鎖 opacity 積
  // < MIN_OPACITY) を畳み込んだ可視面積の総和。 これで self-clip (round-1)・子孫 wrapper の clip/opacity (round-2/3b
  // descendant-scope: el の祖先しか見ない visibleArea/clipPathHidden/effOpacity の射程外)・union 膨張 (per-fragment 加算で
  // box 内 decoy fragment のみ算入) を一括測定する。 ≤16 = テキストが読者に paint されない = omission。 box 内に収まる
  // genuine は full text area で非該当・横 ellipsis 等は先頭 fragment が box 内ゆえ面積 >16。
  // ★floor 射程外 carve: (a) decoy を box 内に残し genuine を押し出す content *置換* (「見えるが正文でない」) は fidelity
  //   ceiling (gate J) 領分。 (b) -webkit-text-fill-color:transparent 等の *ink 抹消* (rect は出るが字形 ink ゼロ) は
  //   geometric な本測定の射程外で ink 計測 (S2 相当・gate F low-contrast) の領分 (REQ-VER-027 carve・round-3b)。
  const visibleTextArea = (el) => {
    let walker;
    try { walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null); }
    catch (e) { return Infinity; } // 走査不能なら omission に倒さない (fail-open でなく既存 arm に委ねる)
    let total = 0;
    const charRects = []; // (round-3g) readable 文字の clipped bbox を element 全体で収集し union-vs-sum で inter-glyph 重畳を検出
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (!n.nodeValue || !n.nodeValue.trim()) continue;
      // (round-3b/3c) 子孫 visibility:hidden/collapse は layout(rect)を持つが非 paint。 checkVis(el)/effOpacity は el の
      // 祖先しか見ず子孫の visibility を捕捉できない。 visibility は継承ゆえ text の親要素 computed が実効値 (最寄り setter)。
      const pe = n.parentElement;
      if (pe && /hidden|collapse/.test(getComputedStyle(pe).visibility)) continue;
      const clips = [];
      let opChain = 1, clipHiddenChain = false;
      for (let a = n.parentElement; a; a = a.parentElement) {
        const cs = getComputedStyle(a);
        const ov = (cs.overflow || '') + (cs.overflowX || '') + (cs.overflowY || '');
        if (/hidden|clip/.test(ov) || /\b(paint|strict|content)\b/.test(cs.contain || '')) clips.push(a.getBoundingClientRect());
        // (round-3b wf_3652702e) 子孫 wrapper の clip-path/clip・near-zero opacity も text を不可視化する。 el の祖先しか
        // 見ない clipPathHidden/effOpacity の射程外 (text→el の *降下* 連鎖) ゆえ text node 単位に本ループで評価する。
        if ((cs.clipPath && cs.clipPath !== 'none') || (cs.clip && cs.clip !== 'auto')) clipHiddenChain = true;
        const op = parseFloat(cs.opacity); if (!isNaN(op)) opChain *= op;
      }
      if (clipHiddenChain || opChain < MIN_OPACITY) continue; // この text node は clip-path/clip or 実効 opacity 不足で不可視
      // (round-3c wf_534bb2c7 / round-3f wf_27813514) 最小可読 *高* floor: post-clip 可視高が fontSize×0.5 未満の fragment は
      // 面積に算入しない。 transform:scaleY(tiny) で潰す / 子孫 overflow 微小 band を omission に倒す (旧 area-only 閾値の射程穴・
      // round-3f で 0.4→0.5 へ bump し強い scaleY 縦潰しを捕捉)。 ★fragment 高は line-height 依存ゆえ scaleY ~0.33 超は minH 直上に
      // 残る degraded-partial 残差 (部分可読・minor) = best-effort tier 許容。 floor は fontSize 相対ゆえ sub/sup・縮小バッジ
      // (~0.7-0.85em) を誤検出しない (font-size:0 は絶対 floor 4px が捕捉)。
      const fs = pe ? (parseFloat(getComputedStyle(pe).fontSize) || 16) : 16;
      const minH = Math.max(4, fs * 0.5);
      let rects;
      try { const rg = document.createRange(); rg.selectNodeContents(n); rects = rg.getClientRects(); }
      catch (e) { continue; }
      let nodeArea = 0;
      for (const r of rects) {
        let l = r.left, t = r.top, rt = r.right, b = r.bottom;
        for (const c of clips) { l = Math.max(l, c.left); t = Math.max(t, c.top); rt = Math.min(rt, c.right); b = Math.min(b, c.bottom); }
        const vw = Math.max(0, rt - l), vh = Math.max(0, b - t);
        if (vh < minH) continue; // 縦潰し (scaleY / 微小 band) で読めない fragment は非算入
        nodeArea += vw * vh;
      }
      // (round-3f wf_27813514) per-glyph 可読 advance floor: 旧 node-average 横密度は word-spacing で空白幅を膨張させると
      // 平均が閾値非依存に持ち上がり内容 glyph の重畳 (ink-soup) を素通した (ceiling Attack E)・単一閾値では CJK 潰し
      // (advance 2.9px) と genuine latin (density 0.61) を分離不能だった (Attack B)。 ゆえ *各 non-ws 文字* の advance を
      // Range で 1 字ずつ測り (空白は分母から除外し平均 gaming を封鎖)、 advance < fontSize×MIN_ADV または 高 < minH を
      // 非可読とみなし、 過半が非可読なら node 全体を非算入する。 per-char ゆえ CJK 重畳も latin と独立に弾く。 genuine は
      // 全 non-ws 字が advance ≥~0.5fs (latin)・≥~0.9fs (CJK)・句読点 ~0.25fs で閾値 (CJK 0.5fs / latin 0.12fs) を上回り FP-free。
      const txt = n.nodeValue;
      let readable = 0, nonWs = 0;
      for (let i = 0; i < txt.length; i++) {
        if (!txt[i].trim()) continue; // 空白は分母から除外 (word-spacing 平均 gaming 封鎖)
        nonWs++;
        try {
          const cr = document.createRange(); cr.setStart(n, i); cr.setEnd(n, i + 1);
          let cw = 0, ch = 0, bl = Infinity, bt = Infinity, br = -Infinity, bb = -Infinity;
          for (const rr of cr.getClientRects()) {
            let l = rr.left, t = rr.top, rt = rr.right, b = rr.bottom;
            for (const c of clips) { l = Math.max(l, c.left); t = Math.max(t, c.top); rt = Math.min(rt, c.right); b = Math.min(b, c.bottom); }
            const w = Math.max(0, rt - l), h = Math.max(0, b - t);
            cw = Math.max(cw, w); ch = Math.max(ch, h);
            if (w > 0 && h > 0) { bl = Math.min(bl, l); bt = Math.min(bt, t); br = Math.max(br, rt); bb = Math.max(bb, b); }
          }
          const isCJK = /[　-ヿ㐀-䶿一-鿿豈-﫿＀-￯]/.test(txt[i]);
          if (cw >= fs * (isCJK ? CJK_MIN_ADV : LATIN_MIN_ADV) && ch >= minH) { readable++; if (br > bl) charRects.push([bl, bt, br, bb]); }
        } catch (e) { /* Range 不能字は skip */ }
      }
      if (nonWs > 0 && readable < nonWs * 0.5) continue; // 過半の文字が advance/高さ 不足 = 潰し → node 非算入
      total += nodeArea;
    }
    // (round-3g wf_20e96424) inter-glyph 重畳検査: per-glyph advance floor は各文字を *孤立して* 測るため、 本文を 1 文字ずつ
    // span 分割し margin/position で全グリフを同一帯に重畳すると (各字 natural advance を保つ) 素通る ink-blob を見逃した (ceiling 実証)。
    // element 全体の readable 文字 bbox を grid raster し union(被覆面積) と sum(per-char 面積) を比較、 union < sum×0.5 = 重畳 crush
    // として非可読に倒す。 genuine は tile 配置で union/sum≈1.05 (僅かな grid 丸めで sum 超)・攻撃重畳は ~0.14 で大 margin・多行 prose も
    // y 帯が分かれ union≈sum ゆえ FP-free (実測)。
    if (charRects.length > 1) {
      let sumA = 0; const G = 3, cells = new Set();
      for (const [l, t, r, b] of charRects) {
        sumA += Math.max(0, r - l) * Math.max(0, b - t);
        for (let x = Math.floor(l / G); x <= Math.floor((r - 0.01) / G); x++)
          for (let y = Math.floor(t / G); y <= Math.floor((b - 0.01) / G); y++) cells.add(x + ',' + y);
      }
      if (sumA > 0 && cells.size * G * G < sumA * 0.5) return 0; // inter-glyph 重畳 = 読者非可読 = omission
    }
    return total;
  };
  // 祖先連鎖の実効 opacity (near-zero = 実質不可視・checkOpacity の opacity===0 境界を補う)
  const effOpacity = (el) => {
    let o = 1;
    for (let e = el; e; e = e.parentElement) {
      const op = parseFloat(getComputedStyle(e).opacity);
      if (!isNaN(op)) o *= op;
    }
    return o;
  };
  const MIN_OPACITY = 0.1; // これ未満は実質不可視 (genuine 契約内容は不透明)
  // 各文字の可視 advance 下限 (×fontSize)。 CJK は複雑 stroke ゆえ半角幅未満で融合し非可読 (Attack B: -0.80em=0.2fs を弾く)・
  // latin/記号は単純形ゆえ低くても可読 (句読点 ~0.25fs)。 script 別閾値で「非可読 CJK」と「genuine 細 latin」の分離不能を解消。
  const CJK_MIN_ADV = 0.5, LATIN_MIN_ADV = 0.12;
  const rendered = (el) =>
    checkVis(el) && !clipPathHidden(el) && visibleArea(el) > 16 && effOpacity(el) >= MIN_OPACITY && !selfContentClipped(el) && visibleTextArea(el) > 16;
  const ZW = /[\u200B-\u200D\u2060\uFEFF]/g; // zero-width / BOM (.plain 空テキスト偽装の strip)

  /* === (FF3+FF4 folio-hef.2) .plain (gate I 看板 = 非エンジニア向け平易説明) の可読性 census ===
     S1 までの .plain census は「rendered() ∧ ZW strip 後 trim 非空」で在否を見たが二つの穴が残った:
       (FF3) 字幅ありインク0 の blank glyph (U+2800 Braille / U+3164 Hangul filler 等) は trim() が
             whitespace と見なさず「非空」を素通りするが、 読者には何も描画されない (= 実質 omission)。
             → 非空 heuristic を **ink 計測** へ一般化する。 文字を pinned font (noto-cjk) で canvas に描き
             1 pixel でも alpha>0 が無ければ ink=0 = 不可視とみなす (parseColor と同じ canvas 技法を流用)。
       (FF4) 取り消し線 overlay (U+0336 COMBINING LONG STROKE OVERLAY 等) は base 文字に重なり base には
             ink があるため ink 計測では捕捉できない。 blank/filler/zero-width/非 corpus-script 文字も含め
             「.plain に出現してよい文字」は本来 SRS corpus の実 script に閉じる。 → render-time の
             **positive allowlist** (corpus 実 script = ASCII + 和文 [かな/漢字/和文句読点] + 欧文約物/矢印/全角 ASCII + 正当結合文字) の
             **補集合**を捏造とみなす。 監査補正 M-D 厳守: \p{M} (開集合=β 違反) に手を伸ばさず *閉集合*を
             列挙し「それ以外を弾く」。 正当な結合文字 (NFD アクセント U+0300-0333/0339-036F・結合濁点
             U+3099/309A) は allowlist に含め false-positive にしない。 判読不能化する overlay (U+0334-0338 =
             tilde/short-stroke/long-stroke/short-solidus/long-solidus overlay) だけを allowlist から carve する。

     ── static unicode-ban (verify-srs.sh) と FF4 (render-time positive) の codepoint 所掌分界 (M-D point 2) ──
       static-ban = verify-srs.sh の "visual-deception unicode ban" + "bidi-override-ban" (source-grep・whole-doc・
                 render 不要)。 bidi-override (U+202A-202E/2066-2069・<bdo>・unicode-bidi:*override) と
                 zero-width/BOM (U+200B-200D/2060/FEFF) *のみ* を弾く no-render backstop。 blank glyph
                 (U+2800/3164)・filler (U+115F/FFA0)・取り消し線 overlay (U+0334-0338) は **含まない**。
       FF4       = renderer 在時の .plain 完全 closure。 allowlist の補集合ゆえ static-ban が漏らす
                 blank/filler/overlay + 非 corpus-script 文字を全て捕捉する (render-time・positive)。 .plain では
                 zero-width も allowlist 外ゆえ FF4 でも二重に捕捉される (defense-in-depth)。
       ∴ blank/filler/overlay 等の新ベクタを **static-ban へ逐次追加しない** (blocklist drift = β 違反)。 .plain は
         FF4 の補集合が render path で被覆する。 static-ban は whole-doc の bidi/zero-width no-render backstop に
         留める (epic 語彙の「gate K」= この static unicode-ban を指す)。
     ── 射程外 carve (本 slice の floor 範囲外・LLM ceiling / 専用 follow-up backstop) ──
       (a) 正当結合文字の多重 stacking (Zalgo) で判読不能化する density 攻撃 (各 codepoint は allowlist 内ゆえ
           本 codepoint allowlist では捕捉不能・count/density gate の領分)。 (b) .plain 以外の slot
           (ears-requirement-row 等) の字種健全性 (REQ-ID/英語術語で codepoint 集合が広く別 allowlist が要る)。 */
  // 任意文字を pinned font で canvas 描画し ink (alpha>0 pixel) の有無を返す (FF3)。 glyph の ink 有無は
  // font-size 非依存ゆえ固定 32px で測る (size 由来の非決定を排除・glyph coverage は family で固定)。
  const _inkCv = document.createElement('canvas');
  const _inkCtx = _inkCv.getContext('2d', { willReadFrequently: true });
  const charHasInk = (ch, family) => {
    const S = 48;
    _inkCv.width = S; _inkCv.height = S;
    _inkCtx.clearRect(0, 0, S, S);
    _inkCtx.font = '32px ' + (family || 'sans-serif');
    _inkCtx.textBaseline = 'middle';
    _inkCtx.fillStyle = '#000';
    _inkCtx.fillText(ch, 2, S / 2);
    const d = _inkCtx.getImageData(0, 0, S, S).data;
    for (let i = 3; i < d.length; i += 4) if (d[i] !== 0) return true;
    return false;
  };
  // 文字列に 1 つでも ink を持つ非空白文字があるか (FF3)。 genuine prose は先頭文字で即 true。
  const textHasInk = (text, family) => {
    for (const ch of text) { if (!ch.trim()) continue; if (charHasInk(ch, family)) return true; }
    return false;
  };
  // 判読不能化する overlay 結合文字 (合字に重なる取り消し線系)。 NFD アクセント等の正当結合文字とは別物ゆえ carve。
  const isOverlayMark = (cp) => cp >= 0x0334 && cp <= 0x0338; // tilde/short-stroke/long-stroke/short-solidus/long-solidus overlay
  // .plain に出現してよい文字の closed allowlist (corpus 実 script + 正当結合文字、 M-D point 1)。 補集合=捏造。
  const plainCharAllowed = (cp) =>
    cp === 0x09 || cp === 0x0A || cp === 0x0D ||                       // tab / LF / CR
    (cp >= 0x20 && cp <= 0x7E) ||                                      // ASCII printable
    ((cp >= 0x0300 && cp <= 0x036F) && !isOverlayMark(cp)) ||          // 結合分音記号 (NFD アクセント) 除 overlay
    (cp >= 0x2010 && cp <= 0x2027) ||                                  // General Punct 可視部 (— U+2014 / … U+2026 / 各種引用符・bullet・leader)
    (cp >= 0x2030 && cp <= 0x205E) ||                                  // General Punct 可視部 続き (‰/prime/guillemet/※ U+203B 等)。 zero-width(200B-200D)/bidi(202A-202E,2066-2069)/各種 space は range 外=補集合で捕捉 (defense-in-depth)
    (cp >= 0x2190 && cp <= 0x21FF) ||                                  // Arrows (→ U+2192 / ↔ U+2194・全て可視 glyph)
    (cp >= 0x3000 && cp <= 0x303F) ||                                  // CJK 記号・句読点 (、。「」・ 等)
    (cp >= 0x3040 && cp <= 0x309F) ||                                  // ひらがな (結合濁点 U+3099/309A 含む)
    (cp >= 0x30A0 && cp <= 0x30FF) ||                                  // カタカナ (ー 含む)
    (cp >= 0x3400 && cp <= 0x4DBF) ||                                  // CJK 拡張 A (稀用漢字・防御的)
    (cp >= 0x4E00 && cp <= 0x9FFF) ||                                  // CJK 統合漢字
    (cp >= 0xF900 && cp <= 0xFAFF) ||                                  // CJK 互換漢字
    (cp >= 0xFF01 && cp <= 0xFF60);                                    // 全角 ASCII 変種/全角括弧 (！？％（） 等)。 halfwidth hangul filler U+FFA0 は range 外で carve

  /* === (459) census-omission/excess — *実描画* 件数 == contract 由来期待件数 === */
  let totalExpected = 0, totalVisible = 0;
  for (const sel of Object.keys(expect.counts || {})) {
    const exp = expect.counts[sel];
    totalExpected += exp;
    const all = [...document.querySelectorAll(`[data-component="${sel}"]`)];
    const vis = all.filter(rendered).length;
    totalVisible += vis;
    if (vis !== exp) {
      violations.push({
        kind: vis < exp ? 'census-omission' : 'census-excess',
        text: `${sel}: 実描画 ${vis} 件 / 期待 ${exp} 件 (DOM ${all.length} 件)`,
        sel, visible: vis, expected: exp, total: all.length,
      });
    }
  }

  /* === distinct req-id (folio-459 ws4o6ywe5 C2-duplicate-row) — 同 id 行コピーで件数を水増しする捏造を封鎖 ===
     count-equality は「どの id か」を問わないため、 全行 FR1 コピー (6=期待) が素通りした。 rendered 行の
     data-req-id が distinct かつ期待件数一致を要求する。 */
  const REQ = 'ears-requirement-row';
  if (expect.counts && typeof expect.counts[REQ] === 'number') {
    const ids = [...document.querySelectorAll(`[data-component="${REQ}"]`)].filter(rendered).map((r) => r.getAttribute('data-req-id') || '');
    const distinct = new Set(ids).size;
    if (distinct !== expect.counts[REQ]) {
      violations.push({ kind: 'census-omission', text: `${REQ}: distinct data-req-id ${distinct} 件 / 期待 ${expect.counts[REQ]} 件 — 重複 ID 水増し`, sel: REQ, visible: distinct, expected: expect.counts[REQ] });
    }
  }

  /* === sub-slot omission — 平易説明 (.plain・非エンジニア向け北極星 prose) ===
     旧版は DOM 自己参照 (plains.length) で期待件数を採り、 全削除/改名/template 退避で plains.length=0→検査 skip、
     部分改名で 6==6 自己無矛盾を許した (ws4o6ywe5)。 修正: 期待件数を contract から caller 注入 (expect.plainCount)、
     各 .plain は行と同じ rendered() ∧ 非空 rendered text (zero-width strip) を要求する。 */
  if (typeof expect.plainCount === 'number') {
    const plains = [...document.querySelectorAll('.plain')];
    // (FF3) 非空 heuristic を ink 計測へ一般化: rendered ∧ ZW strip 後非空 ∧ **ink>0** の .plain のみ計上。
    // blank glyph (U+2800/U+3164) は trim 非空でも ink=0 ゆえ脱落し census-omission に倒れる。
    const plainOk = plains.filter((el) => {
      if (!rendered(el)) return false;
      const txt = el.textContent.replace(ZW, '');
      if (txt.trim() === '') return false;
      return textHasInk(txt, getComputedStyle(el).fontFamily);
    }).length;
    if (plainOk !== expect.plainCount) {
      violations.push({ kind: plainOk < expect.plainCount ? 'census-omission' : 'census-excess', text: `.plain (平易説明): 実描画+ink 非空 ${plainOk} 件 / 期待 ${expect.plainCount} 件 (DOM ${plains.length} 件) — 非エンジニア向け prose の隠蔽/消去/blank-glyph 化`, sel: '.plain', visible: plainOk, expected: expect.plainCount, total: plains.length });
    }
  }

  /* === (FF4 folio-hef.2) .plain codepoint allowlist — overlay/blank/filler/非script を render-time 補集合で弾く ===
     ink 計測 (FF3) で捕捉できない base 重畳 overlay (U+0336 等) と、 blank/filler/zero-width/非 corpus-script 文字を
     codepoint allowlist の補集合で弾く。 plainCount 注入の有無に関わらず描画 .plain を走査する (在否でなく字種の健全性)。 */
  for (const el of document.querySelectorAll('.plain')) {
    if (!rendered(el)) continue; // 非描画 .plain は上の census-omission が扱う
    const bad = new Set();
    for (const ch of el.textContent) { const cp = ch.codePointAt(0); if (!plainCharAllowed(cp)) bad.add(cp); }
    if (bad.size) {
      const list = [...bad].slice(0, 8).map((c) => 'U+' + c.toString(16).toUpperCase().padStart(4, '0')).join(',');
      violations.push({ kind: 'plain-charclass-fabrication', text: `.plain「${snippet(el)}」 に allowlist 外 codepoint (${list}) — overlay/blank/filler 等で判読不能化`, sel: '.plain', codepoints: list });
    }
  }

  return { totalExpected, totalVisible, violations };
};

// page.evaluate(PROBE_JS) の *完了値* が関数 (= 直前の window 代入式の値) だと playwright がそれを
// 「呼ぶべき関数」と見なし arg=null で自動 call してしまう (census は JSON.parse(null)→null で crash)。
// 完了値を undefined に固定し、 本ファイル評価は probe 定義だけに留める (caller が __folioSrs* を明示 call する)。
void 0;
