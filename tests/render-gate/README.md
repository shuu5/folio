# render-gate — render-safety ceiling (playwright 視覚 render gate)

corpus 全 page (repo-root index.html + architecture/**/*.html) を実ブラウザ (headless chromium) で
**3 viewport (375 / 768 / 1280)** で render し、 render **後** の DOM 幾何から **mermaid flowchart の
text-block overlap** と **chrome 崩れ** (意図しない横スクロール / nav と本文の重なり、 ADR-0039 §2.8)
を検出する verification 層。 二層 render-safety の **ceiling**。

## なぜ要るか — pure-bash floor の死角

`folio validate` の **render-safety** gate (REQ-VER-021、 `architecture/spec/verification.html`) は
pure-bash で動くため render 後の DOM 幾何を見れない。 そのため「既知の overlap-prone パターン
(`<pre class="mermaid">` 内の subgraph 多行タイトル)」を static pattern-lint するに留まる (floor)。

実際の視覚欠陥 — 図5 の「7 並列固定」が枠/ノードに重なる — は render しないと存在しない幾何で、
過去の mermaid 問題 (#121 / #123) も全て人間の目視で発見されていた。 本 gate は実ブラウザ render を
行い `getBoundingClientRect` で flowchart の cluster/node/label 幾何 overlap を検出する **ceiling**。

| 層 | 機構 | 配布 | 捕捉範囲 |
|---|---|---|---|
| floor | `folio validate` render-safety (bash、 REQ-VER-021) + readability-floor (REQ-VER-023) | 全 consumer | 既知パターン (subgraph 多行タイトル / viewport meta 等の static lint) |
| **ceiling** | **本 gate (playwright、 CI)** | **folio dogfood (CI-only)** | **flowchart の cluster/node/label 幾何 overlap + clip (4 class) + chrome 幾何 (2 class)、 3 viewport (REQ-VER-022)** |

ceiling は browser 依存ゆえ consumer の `folio validate` には入れない。 folio 自身の CI で dogfood する。
spec trace は `architecture/spec/verification.html` の REQ-VER-022 (floor は REQ-VER-021)。

## 検出する欠陥 class (probe.js)

1. **cluster-label-multiline** — subgraph タイトルの intrinsic 高さ > 30px (単行 ~24px / 多行 ~48px)。 図5 の class。
2. **label-over-foreign-node** / **cluster-label-over-node** — text label が自分以外の node 矩形と
   面積比 > 0.15 で交差 (text-over-block overlap)。 clean corpus 15 図 (blocking 13 + advisory 2) で誤検出 0 を実測。
3. **node-over-node** — node 同士が面積比 > 0.30 で重なる layout collision (入れ子 cluster は除外)。
4. **content-clipped** — 要素が svg 可視範囲の外へはみ出す (svg overflow は既定 hidden で視覚上 clip =
   読めない)。 wide 図の `<pre>` 横スクロール (#121) は svg 自体が広がるため対象外 — svg の内側に
   収まらない要素だけを欠陥とする。 許容 2px (sub-pixel ずれ無視)。 clean corpus で誤検出 0 を実測。
5. **horizontal-overflow** (chrome 幾何 arm) — 本文が viewport を溢れ document 全体に**意図しない**
   横スクロールが発生 (`scrollWidth > clientWidth + 2px`)。 意図された scroll container
   (overflow-x:auto の wide `<pre>`、 #121) は中身を内部で scroll し document に寄与しないため
   鳴らない。 culprit (viewport 右端を越える最も外側の要素、 clip/scroll 祖先なし) を最大 5 件特定して
   報告する (特定できなくても document 溢れ自体を fail-visible に報告)。 viewport 依存 — 主に 375/768
   で発現する。 導入時の実測で **wide `<table>` (display:table は scroll container 化できない)** と
   **非 hover tooltip の phantom layout (visibility:hidden は scrollable overflow に寄与)** の
   実欠陥 95 件を検出し、 common.css 側で修正した (`@media (max-width:988px)` の table block 化 +
   tooltip の display:none 化)。
6. **nav-over-content** (chrome 幾何 arm) — nav landmark と本文 block の矩形交差 (面積比 > 0.15)。
   通常 flow の隣接 block は矩形が交差しないため、 chrome 注入の位置計算事故・absolute 化の崩れで
   のみ鳴る。 **Chromium は closed `<details>` の中身 (rendering skip) にも非 0 の phantom rect を
   返す**ため、 probe は `checkVisibility()` で非描画要素を除外する (これを欠くと spec-row fold
   だらけの実 corpus で大量誤検出する — clean fixture が回帰ガード)。

加えて、 coverage の穴を 2 種の warning で可視化する (fail にはしないが silent pass にもしない):

- `[warn] vacuous-coverage` — `.node`/`.cluster` を持たず幾何検査が構造的に空振りする図型 (sequenceDiagram 等)。
- `[warn] uncalibrated-coverage` — **`.node` は出すが flowchart でない図型 (stateDiagram 等)**。 構造
  (.node 有無) だけでは flowchart と区別できないため図型 (aria-roledescription) で判定する。 幾何は
  測るが threshold が flowchart 較正のため「検査済」とは言えない。

threshold は conservative。 detector(1) の height は font-size 駆動で行数に比例するため font 差に頑健、
かつ svg の viewBox→rendered **縦比 (scaleY)** で除して **intrinsic px に正規化** する (`useMaxWidth:true`
で svg が縮小 render されても閾値が scale に引きずられない。 mermaid は uniform scale で render するため
縦横比は同値。 `useMaxWidth:false` の現 corpus は scale=1 で従来挙動と同一)。 面積比 detector(2)(3) は
比率ゆえ元から scale 不変。 text 幅依存だが、 mermaid dagre layout が node box を label 幅に合わせ
self-normalize するため threshold を跨ぎにくい (摂動試験でも frac 不変)。 detector(4) の許容 2px は
rendered px (視覚上の clip 量) であり (1) の intrinsic 正規化とは意図的に非対称。 決定性は **vendored
mermaid + pinned playwright + pinned font (CI が `fonts-noto-cjk` を install)** の三重 pin で担保する。

## viewport と screenshot (ADR-0039 §2.8)

- sweep は **375×667 (mobile) / 768×1024 (tablet) / 1280×900 (desktop)** の 3 viewport で全 page を
  render する。 chrome 崩れは narrow viewport でのみ発現することが多い — 既存 mermaid detector を
  multi-viewport で回す「だけ」では捕れないため、 chrome 幾何 2 arm (上記 5/6) の新設が本体
  (ADR-0039 §2.8 が「回すだけ」を明示却下)。
- `--screenshot-dir <dir>` を渡すと全 page × 全 viewport の full-page screenshot を保存する。
  CI が artifact 化して人間 review の補助に充てる。 **golden 比較はしない** (pixel golden は
  brittle — 幾何 detector + 人間の目の二層で代替、 ADR-0039 §2.8)。

## 完全性 (fail-closed)

render が間に合わず図数が不足したまま probe すると、 存在する svg しか見ず「0 overlap = clean」に
化けうる (false-clean = 見逃し)。 これを防ぐため:

- probe は固定待ちでなく **「svg 本数 >= 期待図数」を polling** してから測る。
- 各ファイルの期待図数 (= 実 `<pre class="mermaid">` 数、 HTML コメント内は除外) と実 render 数を照合し、
  **不足は overlap と同様に exit 1 (fail) に倒す**。 見逃しでなく失敗にする。

## constitution は advisory (non-blocking)

`constitution.html` は編集禁止の不変資産 (CLAUDE.md §2、 amendment は P-10 で user 承認必須)。 blocking
gate で overlap を検出しても救済不能 (frozen deadlock) になるため、 **advisory (表示のみ・exit に非影響)**
で扱う。 floor (`folio validate`) が `@type==FolioConstitution` を scan 除外するのと同じ carve-out
(doc 自身の @type で判定。 constitution を mention するだけの README/relations は blocking のまま)。

**frozen ADR は chrome arm でも blocking のまま** — chrome 崩れ (横 overflow / nav 重なり) の是正経路は
共有資産 (`common.css` / chrome 注入) 側にあり、 frozen 本文を編集せずに直せるため deadlock にならない
(導入時の実例: frozen ADR 群の wide table 溢れを common.css の media query だけで解消した)。 frozen 本文
そのものに固有の幾何欠陥が出て CSS/chrome で救済できない事態が実際に起きたら、 その時点で carve-out
拡張を判断する (premature に広げると corpus の大半 (ADR 32 本) が gate から抜ける)。

## 使い方

local quick-start (uv、 pip/venv 不要で最短)。 chromium を一度 install すれば ephemeral 環境で走る:

```bash
uv run --with playwright==1.60.0 python -m playwright install chromium  # 初回のみ (browser DL、 ~/.cache に共有)
uv run --with playwright==1.60.0 python tests/render-gate/check.py --selftest  # 検出力の自己検証
uv run --with playwright==1.60.0 python tests/render-gate/check.py             # 全 corpus × 3 viewport sweep
```

pip 環境がある場合 (CI も同手順、 font は CI が別途 pin):

```bash
# 依存 (初回のみ):
python3 -m pip install -r tests/render-gate/requirements.txt
python3 -m playwright install --with-deps chromium

# 全 corpus を 3 viewport で sweep (overlap / chrome 崩れ / render 不足が 1 件でもあれば exit 1):
python3 tests/render-gate/check.py

# detector の検出力を fixture で自己検証 (mermaid/chromium 版 drift への回帰ガード):
python3 tests/render-gate/check.py --selftest

# 全 page × viewport の full-page screenshot を保存 (CI artifact 用、 golden ではない):
python3 tests/render-gate/check.py --screenshot-dir /tmp/render-shots

# 外部 http server を使う (未指定なら自前で空きポートに起動)。 server は REPO_ROOT を配信すること
# (fixture/spec が ../../../architecture/assets/mermaid.min.js を参照するため、 root がずれると 404):
python3 tests/render-gate/check.py --base-url http://127.0.0.1:8777
```

`check.py` は repo-root `index.html` + `architecture/**/*.html` の全 page を自動 discover する
(chrome 幾何は全 page が対象)。 mermaid の期待図数は実 `<pre class="mermaid">` 数 (prose 内の
escaped 言及・HTML コメント内は対象外) — 対象一覧を手で持たないため page / figure の増減に追従する。

## self-test (検出力の floor-proof)

gate 自身の「まだ欠陥を捕捉できる」ことを `--selftest` が `fixtures/` (13 case) で証明する。 判定は
**violation kind の完全一致** — 「何かに flag された」でなく「意図した detector だけが発火した」を
検証する (subset 判定だと positive fixture 上の予期せぬ誤発火が masking される)。 kind 集合は
mermaid arm (diagrams) と chrome arm (page) の和。 随伴発火も期待集合に明記して許容集合を閉じる:

- `fixtures/multiline-subgraph.html` (BAD、 実 mermaid) → **cluster-label-multiline + 随伴 cluster-label-over-node** (detector 1+2)
- `fixtures/single-line-subgraph.html` (GOOD、 実 mermaid) → **必ず clean かつ render 成功**
- `fixtures/scaled-multiline-subgraph.html` (BAD、 実 mermaid、 useMaxWidth:true + 150px 容器で scale~0.5) →
  **縮小 render でも cluster-label-multiline 検出** = scale 正規化の回帰ガード (正規化を壊す mutation が
  この case で FAIL することを実証済)
- `fixtures/nonflowchart-vacuous.html` (sequence、 実 mermaid) → **必ず clean かつ vacuous 報告**
- `fixtures/state-uncalibrated.html` (stateDiagram、 実 mermaid) → **必ず clean かつ uncalibrated 報告**
  (state は `.node` を「出す」ため、 図型判定なしでは flowchart 扱いになる誤分類への回帰ガード)
- `fixtures/node-overlap.html` (BAD、 合成 SVG) → **必ず node-over-node 検出** (detector 3)
- `fixtures/clipped-content.html` (BAD、 合成 SVG) → **必ず content-clipped 検出** (detector 4)
- `fixtures/label-over-node.html` (BAD、 合成 SVG) → **必ず label-over-foreign-node 検出** (detector 2 単独 arm)
- `fixtures/chrome-h-overflow.html` (BAD、 合成 page) → **375px で必ず horizontal-overflow 検出**
  (detector 5)、 かつ **同一 fixture が 768px では clean** — この対が viewport plumbing 自体の
  回帰ガードを兼ねる (幅が効いていなければどちらかが落ちる)
- `fixtures/chrome-scroll-container.html` (GOOD、 合成 page) → **375px でも必ず clean** — 意図された
  scroll container (#121 の wide `<pre>` パターン) を detector(5) が誤検出しないことの固定
- `fixtures/chrome-nav-overlap.html` (BAD、 合成 page) → **必ず nav-over-content 検出** (detector 6、
  absolute 化した nav が本文に被さる形)
- `fixtures/chrome-clean.html` (GOOD、 合成 page) → **375px でも必ず clean** — 実 chrome 構造
  (breadcrumb + audience-toggle + 本文 + prevnext) の normal flow 隣接と、 **closed `<details>` の
  phantom rect** (checkVisibility() で除外しないと誤検出する、 実証済 false positive) の回帰ガード

detector(2)(3)(4) の単独欠陥は mermaid (dagre) が通常生成しないため、 mermaid 出力と同じ class 構造の
合成 SVG を直置きして detector arm 自体を回帰固定する。 detector(5)(6) も同様に合成 page で固定する。
GOOD/vacuous/uncalibrated ケースも svg が render されたこと (svgCount >= 期待数) を assert する —
「壊れて何も render しない」を「clean」と取り違えない。
mermaid / chromium 版を上げて幾何が変わり selftest が落ちれば drift の signal。

## 限界 (未対応の class)

- **非 flowchart 図の幾何**: vacuous (sequence 等) / uncalibrated (state 等) warning で可視化はするが、
  これらの図型に較正した overlap detector は持たない (専用較正は将来 folio が他型の図を実際に採用した
  時点で追加)。
- **interaction 後の幾何**: chrome arm は load 直後の静的幾何のみを測る。 hover/focus で現れる box
  (tooltip 等) や details open 後・audience toggle 切替後の幾何は対象外 — 右端の term を hover した
  瞬間の transient な横スクロールは検出しない (§9.3 viewport-clip 許容の範疇)。
- **「読める」の最終判定**: 幾何が clean でも読みにくい page はある — persona-based readability
  review (lens) + user の実機 walk が上層 (rules §11.4、 ADR-0039 §2.8)。 screenshot artifact は
  その補助。
- **cluster 枠内の視覚溢れ**: label が svg の内側には収まるが所属 cluster の枠だけを視覚的に溢れる形は、
  別 node と交差 (detector 2) も svg clip (detector 4) もしなければ未検出。
- **display:none の図**: 折り畳まれた `<details>` 内など 0 サイズの図は幾何が測れず対象外 (folio の図は
  全て `<figure class="diagram">` 直下で常時 render ゆえ現状は無関係)。
- **極端な縮小 render での clip 量**: detector(4) は rendered px で測るため、 大きく縮小された図では
  intrinsic 上の大きなはみ出しが視覚上数 px となり許容内に収まりうる (「読めるか」は rendered で決まる
  という欠陥定義に沿った conservative 側の挙動)。

## blocking の前提 (repo 設定)

job が赤でも物理的に merge を止めるには、 GitHub の branch protection / ruleset で render-gate を
**required status check** に登録する必要がある (ci.yml だけでは強制化されない)。

二層の正式 decision 記録は `architecture/decisions/ADR-0037-render-safety-ceiling.html`。
