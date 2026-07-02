# srs-ceiling-oracle — dev-time differential oracle (folio-mzn.1.5 S11)

ceiling (LLM ensemble) の **基準器**。2 つの役割を持つ:

1. **defect-injection proof (ceiling 版 test-adversarial)** — 意味層にだけ欠陥を注入した fixture
   (floor は全て PASS する) に対し、ceiling pipeline が期待 verdict (COMMIT=OK/BLOCKED) と期待
   detector lens を出すことを assert する。floor の test-adversarial.sh が決定的 gate の検出力を
   固定するのと同型に、こちらは **LLM ceiling の検出力**を固定する。
2. **differential (prose-conduit trust gap の bound)** — 同じ pipeline を (a) JS 骨格 (本 oracle WF・
   `.catch`→machinery≠clean の決定的 fail-closed 配線) と (b) prose skill (`/folio-verify`・shipped)
   の両経路で走らせ、**verdict 級の一致**を突合する。prose 手順が findings/machinery 失敗を
   取りこぼしていないかの唯一の裏取り (trust gap は relocate であって eliminate ではない —
   設計 SSoT `.folio-mzn1-design.md`)。

## dev-time 専用 (shipped しない)

- 本 dir は **Workflow tool が明示有効化されたセッション (ultracode 等) でのみ**回せる。
  shipped 検証経路は `/folio-verify` (skill→subagent 一段) であり、本 oracle はその較正器。
- LLM ensemble は非決定的。oracle が assert するのは **verdict 級** (OK/BLOCKED + detector 帰属)
  であって finding の字面一致ではない。明確な欠陥に対する verdict は安定するべきで、
  ここが揺れるならそれ自体が ceiling 較正のズレという signal (基準器の測定対象)。
- コスト: 1 run = fixture 4 本 × (floor render + 3 opus lens + refuter 数件) ≈ opus agent 15〜20。
  回すのは ceiling agent 群 / SKILL 手順 / commit-check 契約を変えたとき。

## 構成

| file | 役割 |
|---|---|
| `build-fixtures.sh <outdir>` | golden + 欠陥 3 種を決定的に生成 (静的 floor 透過を fail-closed 確認) |
| `expected.json` | 期待 verdict + detector 帰属の SSoT |
| `srs-ceiling-oracle.workflow.js` | JS 基準器 (Workflow tool で実行・参照 verdict を out/ へ書出し) |
| `compare-verdicts.sh` | JS 参照 ↔ prose skill verify-state の決定的突合 (jq + `folio ceiling-commit-check` 再実行による commit/detector の機械再導出・意味判定なし = 件数/集合/hash/rc の機械計算のみ) |
| `out/` | 実行生成物 (fixtures / reference-verdicts.json・VCS 追跡しない) |

欠陥 3 種 (bd folio-mzn.1.5): 捏造 rationale (gate J) / 意味的に空の plain (gate K/I) /
章 lead の意味カバレッジ欠落 (gate K/J)。変異の実体は `build-fixtures.sh` が SSoT。

## 実行手順 (dev-time protocol)

```bash
# 1. fixtures を生成 (決定的・数秒)
bash build-fixtures.sh out/fixtures

# 2. JS 基準器を回す (Workflow tool 有効なセッションで)
#    Workflow({ scriptPath: ".../oracle/srs-ceiling-oracle.workflow.js",
#               args: { oracleDir: "<abs path to this dir>" } })
#    → out/reference-verdicts.json + 返り値 allPass (defect-injection proof)

# 3. prose 側: 同じ fixture 群へ /folio-verify を 1 本ずつ回す (main session)
#    /folio-verify out/fixtures/golden.html ../contract/ec-checkout.srs.yaml   (ほか 3 本も)
#    → .folio/verify-state/*.json に 5-state が残る

# 4. 経路突合 (決定的)
bash compare-verdicts.sh            # exit 0 = 経路一致
```

## 不変条件 (維持すること)

- fixture の欠陥は **prose slot の意味層のみ**に注入する (floor 透過が崩れたら oracle は
  ceiling でなく floor を測ってしまう — build-fixtures.sh が静的 floor PASS を fail-closed 確認)。
- 期待集合は contract (SSoT) から。lens への入力で生成 HTML の DOM を期待集合の源にしない
  (verify-laundering 禁止・`skills/folio-verify/SKILL.md` §2)。
- JS 骨格でも機械は verdict を裁定しない: enum remap + 正規化 + `folio ceiling-commit-check`
  (default-block 述語) のみ。裁定 narrative が要る場面は shipped skill の領分。
- lens/refuter の agent 死亡は `.catch` → `ran_lenses` 除外 → commit-check BLOCKED (machinery≠clean)。
  欠けた lens を補完しない (fail-closed)。
- 本 oracle は read-only (fixture 生成と out/ 書出しのみ)。ceiling agents / SKILL / helper を
  修正したら本 oracle を回し直して較正を確認する (author≠certifier: oracle 自体の変更は
  独立 ceiling でレビューする)。
