# render-gate — render-safety ceiling (playwright 視覚 render gate)

mermaid 図を実ブラウザ (headless chromium) で render し、 render **後** の DOM 幾何から
**flowchart の text-block overlap** を検出する verification 層。 二層 render-safety の **ceiling**。

## なぜ要るか — pure-bash floor の死角

`folio validate` の **render-safety** gate (REQ-VER-021、 `architecture/spec/verification.html`) は
pure-bash で動くため render 後の DOM 幾何を見れない。 そのため「既知の overlap-prone パターン
(`<pre class="mermaid">` 内の subgraph 多行タイトル)」を static pattern-lint するに留まる (floor)。

実際の視覚欠陥 — 図5 の「7 並列固定」が枠/ノードに重なる — は render しないと存在しない幾何で、
過去の mermaid 問題 (#121 / #123) も全て人間の目視で発見されていた。 本 gate は実ブラウザ render を
行い `getBoundingClientRect` で flowchart の cluster/node/label 幾何 overlap を検出する **ceiling**。

| 層 | 機構 | 配布 | 捕捉範囲 |
|---|---|---|---|
| floor | `folio validate` render-safety (bash、 REQ-VER-021) | 全 consumer | 既知パターン (subgraph 多行タイトル) |
| **ceiling** | **本 gate (playwright、 CI)** | **folio dogfood (CI-only)** | **flowchart の cluster/node/label 幾何 overlap + clip (下記 4 class、 REQ-VER-022)** |

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

## 使い方

local quick-start (uv、 pip/venv 不要で最短)。 chromium を一度 install すれば ephemeral 環境で走る:

```bash
uv run --with playwright==1.60.0 python -m playwright install chromium  # 初回のみ (browser DL、 ~/.cache に共有)
uv run --with playwright==1.60.0 python tests/render-gate/check.py --selftest  # 検出力の自己検証
uv run --with playwright==1.60.0 python tests/render-gate/check.py             # 全 spec sweep
```

pip 環境がある場合 (CI も同手順、 font は CI が別途 pin):

```bash
# 依存 (初回のみ):
python3 -m pip install -r tests/render-gate/requirements.txt
python3 -m playwright install --with-deps chromium

# 全 spec を sweep (overlap / render 不足が 1 件でもあれば exit 1):
python3 tests/render-gate/check.py

# detector の検出力を fixture で自己検証 (mermaid/chromium 版 drift への回帰ガード):
python3 tests/render-gate/check.py --selftest

# 外部 http server を使う (未指定なら自前で空きポートに起動)。 server は REPO_ROOT を配信すること
# (fixture/spec が ../../../architecture/assets/mermaid.min.js を参照するため、 root がずれると 404):
python3 tests/render-gate/check.py --base-url http://127.0.0.1:8777
```

`check.py` は `architecture/spec/*.html` のうち実 `<pre class="mermaid">` を含むものを自動 discover する
(prose 内の escaped 言及・HTML コメント内は対象外)。 対象一覧を手で持たないため figure の増減に追従する。

## self-test (検出力の floor-proof)

gate 自身の「まだ欠陥を捕捉できる」ことを `--selftest` が `fixtures/` (8 case) で証明する。 判定は
**violation kind の完全一致** — 「何かに flag された」でなく「意図した detector だけが発火した」を
検証する (subset 判定だと positive fixture 上の予期せぬ誤発火が masking される)。 随伴発火も期待集合に
明記して許容集合を閉じる:

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

detector(2)(3)(4) の単独欠陥は mermaid (dagre) が通常生成しないため、 mermaid 出力と同じ class 構造の
合成 SVG を直置きして detector arm 自体を回帰固定する。 GOOD/vacuous/uncalibrated ケースも svg が render
されたこと (svgCount >= 期待数) を assert する — 「壊れて何も render しない」を「clean」と取り違えない。
mermaid / chromium 版を上げて幾何が変わり selftest が落ちれば drift の signal。

## 限界 (未対応の class)

- **非 flowchart 図の幾何**: vacuous (sequence 等) / uncalibrated (state 等) warning で可視化はするが、
  これらの図型に較正した overlap detector は持たない (専用較正は将来 folio が他型の図を実際に採用した
  時点で追加)。
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
