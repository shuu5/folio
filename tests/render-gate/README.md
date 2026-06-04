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
| **ceiling** | **本 gate (playwright、 CI)** | **folio dogfood (CI-only)** | **flowchart の cluster/node/label 幾何 overlap (下記 3 class)** |

ceiling は browser 依存ゆえ consumer の `folio validate` には入れない。 folio 自身の CI で dogfood する。

## 検出する overlap (probe.js)

1. **cluster-label-multiline** — subgraph タイトルの高さ > 30px (単行 ~24px / 多行 ~48px)。 図5 の class。
2. **label-over-foreign-node** / **cluster-label-over-node** — text label が自分以外の node 矩形と
   面積比 > 0.15 で交差 (text-over-block overlap)。 clean corpus 15 図 (blocking 13 + advisory 2) で誤検出 0 を実測。
3. **node-over-node** — node 同士が面積比 > 0.30 で重なる layout collision (入れ子 cluster は除外)。

threshold は conservative。 detector(1) の height は font-size 駆動で行数に比例するため font 差に頑健。
面積比 detector(2)(3) は text 幅依存だが、 mermaid dagre layout が node box を label 幅に合わせ
self-normalize するため threshold を跨ぎにくい (摂動試験でも frac 不変)。 決定性は **vendored mermaid
+ pinned playwright + pinned font (CI が `fonts-noto-cjk` を install)** の三重 pin で担保する。

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

gate 自身の「まだ欠陥を捕捉できる」ことを `--selftest` が `fixtures/` で証明する:

- `fixtures/multiline-subgraph.html` (BAD、 多行 subgraph タイトル) → **必ず overlap 検出**
- `fixtures/single-line-subgraph.html` (GOOD、 単行タイトル) → **必ず clean かつ render 成功**

GOOD ケースも svg が render されたこと (svgCount >= 期待数) を assert する — 「壊れて何も render しない」を
「clean」と取り違えない。 mermaid / chromium 版を上げて幾何が変わり selftest が落ちれば drift の signal。

## 限界 (未対応の overlap class)

- **非 flowchart 図**: sequenceDiagram / stateDiagram 等は `.node` / `.cluster` を出さず、 probe は構造的に
  vacuous (常に clean)。 現 corpus は全て flowchart/graph ゆえ無害だが、 将来 folio が他型の図を足すと
  silent pass する (→ 型判定 warning は follow-up)。
- **横溢れ / viewport clip**: 単行でも長すぎる label が枠 / svg 右端を溢れて clip される欠陥は、 別 node
  矩形と交差しなければ未検出 (4 つ目の detector は follow-up)。 REQ-VER-021 が「ceiling の領分」と書く
  この class を本 ceiling はまだ完全には満たさない。
- **display:none の図**: 折り畳まれた `<details>` 内など 0 サイズの図は幾何が測れず対象外 (folio の図は
  全て `<figure class="diagram">` 直下で常時 render ゆえ現状は無関係)。
- **selftest の被覆**: 現 fixture は detector(1)+(2) を踏むが detector(3) node-over-node と非 flowchart の
  vacuous 検出は未被覆 (follow-up で fixture 追加)。

## blocking の前提 (repo 設定)

job が赤でも物理的に merge を止めるには、 GitHub の branch protection / ruleset で render-gate を
**required status check** に登録する必要がある (ci.yml だけでは強制化されない)。

二層の正式 decision 記録は ADR-0037 (retrospective、 別 PR)。
