---
name: folio-verify
description: 生成された SRS プレゼン pack (generated.html + contract.yaml) の ceiling 検証を回す唯一の正規 entry point。folio-architect Phase F と同型の main-session orchestrator (skill→subagent 一段=nesting 制約下で唯一配布可能な形) で、floor(verify-srs)→precheck→anchors→3 lens 並列 spawn (fidelity-srs ∥ persona-walk-srs ∥ completeness-critic-srs)→dedup→Pass2 finding-refuter→severity remap→LLM verdict 合成→ceiling-commit-check (機械の default-block gate)→3 バンド verdict card + 5-state (STALE / FLOOR-FAIL / CEILING-FAIL / READY / GREEN) を出し、--accept で人間が fail-closed に toppling する。findings は synth 鵜呑みせず各 lens 返り値を raw 一次監査する。user が明示的に起動する (disable-model-invocation)。
disable-model-invocation: true
---

# folio-verify SKILL — SRS ceiling 検証 orchestrator

> **応答言語**: 本 SKILL の出力 (verdict card・状態・要約・user 向けメッセージ) は **user の使用言語** (default = global CLAUDE.md = 日本語) で行う。folio canonical 用語 (`floor` / `ceiling` / `contract` / `anchor manifest` / `data-slot-id` / `EARS` / `RTM` / `upheld` / `refuted` / `uncertain` / `PENDING` / `ESCALATE` / 5-state 名等) は英語のまま維持する。

生成 SRS プレゼン HTML の完全性判定は **floor (機械) + ceiling (意味) の二層**で、`GREEN ⟺ (floor 全通過) AND (ceiling 合格)`。本 SKILL は ceiling 側を回す常設 orchestrator。floor が決定的に測れない「捏造 / 読みやすさ / 意味的完全性」を、独立コンテキストの LLM reviewer に判定させ、その構造化 verdict を **数える / 束ねる** だけで裁定へ渡す。

> **貫く原則 (最重要・全判断の根拠)**: 機械は自由文の「意味」を判定しない。各 reviewer が自分の構造化 verdict (JSON block) を emit し、skill はそれを **数える / 束ねる / enum remap する** だけ。skill が prose を決定的パースして severity/verdict を抽出するのは folio-mzn が排除すべき当のアンチパターン → **禁止**。列挙値の機械変換 (severity enum remap)・件数集計・順序担保は機械 OK (partial-enumeration trap の回避 = 自由文の意味検証を決定的プログラムで解くな)。

## 本 SKILL は SKILL のまま (subagent 化しない)

Pass1 の 3 lens と Pass2 の finding-refuter を **並列 spawn する側は main-session でなければならない** (subagent は subagent を spawn できない = nesting 制約)。よって本 SKILL は folio-architect と同じく SKILL のまま置き、`disable-model-invocation: true` で Claude が検証を予期して自動起動する事故を防ぐ。起動は user が明示的に `/folio-verify <generated.html> <contract.yaml>` で行う。

## folio CLI の解決 (consumer / self-host 両対応)

本 SKILL は folio CLI を **canonical bin path** `~/.claude/plugins/folio/.claude-plugin/bin/folio` で呼ぶ (consumer project でも folio self-host でも同じ bin に解決する canonical layout・folio-architect と同型)。見つからない場合は `command -v folio` を fallback とし、どちらも無ければ consumer に install を案内して abort (fail-closed)。以降、`folio verify-srs` / `folio ceiling-precheck` / `folio ceiling-anchors` / `folio ceiling-commit-check` はこの canonical path 経由で呼ぶ (bare `folio` や repo-relative path は consumer cwd で解決しないため禁止)。

## 入力

- `<generated.html>` — 判定対象の生成 SRS プレゼン HTML (generator が assemble + inject-prose で産出した派生成果物)。
- `<contract.yaml>` — 機械 SSoT (canonical)。ceiling の全 intent anchor はここに接地する。

pack は現状 **SRS のみ** (`folio ceiling-anchors` が SRS 専用・rule-of-three)。ADR/research/spec/principle への一般化は後続。

---

## FLOW (folio-architect Phase F 同型・main-session orchestrator・skill→subagent 一段)

各ステップを **順に** 実行する。ceiling は floor の後にしか回さない (起動順序不変条件を機械 = precheck で担保)。

### 1. floor + precheck (起動順序不変条件)

```bash
FLOOR="$(~/.claude/plugins/folio/.claude-plugin/bin/folio verify-srs <generated.html> <contract.yaml>)"; floor_rc=$?
```

`verify-srs` は floor (taxonomy §5.2 gate A-H + visual-first)。exit 0 = floor PASS (stdout に `RESULT: floor PASS` + `CEILING=PENDING`) / 1 = floor FAIL / 2 = tool error。捕捉した stdout をそのまま `ceiling-precheck` へ渡す:

```bash
printf '%s' "$FLOOR" | ~/.claude/plugins/folio/.claude-plugin/bin/folio ceiling-precheck; pc_rc=$?
```

- `pc_rc==1` (floor FAIL / floor PASS+PENDING を検出できず) → 状態 **FLOOR-FAIL** で停止 (ceiling へ進まない)。
- `pc_rc==3` (SKIP masquerade = floor PASS を宣言したが gate SKIP あり = floor 不完全) → 状態 **FLOOR-FAIL** で停止 (honest-SKIP ≠ PENDING・renderer 在環境で floor を完成させてから再検証)。
- `pc_rc==2` (tool error) → tool error として停止 (誤 GREEN に倒さない)。
- `pc_rc==0` (真の CEILING=PENDING) → ceiling を続行。以降 `floor:"PENDING"` を commit-check 入力へ carry する。

> precheck は文字列痕跡の照合だけ (意味判定なし)。floor の advisory PENDING を **偽装 (honest-SKIP)** から守る fail-closed gate であり、これを踏まないと「floor 不完全なのに ceiling GREEN」の masquerade が通る。

### 2. anchors (verify-laundering 一次防壁)

```bash
ANCHORS="$(~/.claude/plugins/folio/.claude-plugin/bin/folio ceiling-anchors <contract.yaml>)"; an_rc=$?
```

`ceiling-anchors` は contract の各 prose slot を SSoT source に対応づけた **anchor manifest** (JSON: `{doc_type, contract, anchors:[{slot, ssot_path, ssot_value}]}`) を stdout へ出す。exit 0 = 成功 / 2 = tool error (入力不在 / doc_type 非対応 / 構造不正)。exit 2 は tool error として停止する。

この manifest を **completeness-critic-srs (Pass1) と finding-refuter (Pass2) に必須入力**として渡す (両者は location→contract の解決を manifest で行う)。`fidelity-srs` は自前の slot↔SSoT 表 (fidelity-srs.md §2) で、`persona-walk-srs` は北極星で直接 anchor するため manifest を要さない (contract + HTML を渡す・manifest を渡しても無害だが依存しない)。いずれの lens も **期待集合を生成 HTML の DOM から作らず contract(SSoT) から取る** ことが要 — さもなくば「生成器が落とした要素は期待集合からも消える = 永遠に検出できない」verify-laundering になる。

### 3. Pass1 — 3 lens 並列 spawn

**Agent tool を 1 メッセージ内で 3 呼び出し**して以下の 3 lens を同時に (並列に) spawn する (3 つの Agent tool 呼び出しを同一 response にまとめる = 並列実行・folio-architect Phase F と同型):

| scoped name | gate | 軸 | severity 語彙 |
|-------------|------|----|--------------|
| `folio:fidelity-srs` | gate J | 捏造 / 脱落 / 誇張 / drift (prose ↔ contract) | critical / high / medium / low (canonical) |
| `folio:persona-walk-srs` | gate I | 非エンジニア読書体験 (何が要件か / なぜ / どう検証) | blocker / major / minor / polish (native) |
| `folio:completeness-critic-srs` | 第 3 lens | 意味的完全性 (実質空 / 的外れ / 意味カバレッジ欠落) | critical / high / medium / low (canonical) |

各 lens へ **{生成 HTML, contract.yaml}** を渡す (+ `completeness-critic-srs` には **anchor manifest** も必須入力として渡す・§2)。`fidelity-srs` / `persona-walk-srs` は manifest を要さない (§2)。3 lens は read-only (自ら Edit しない) ため並列で安全に走る。model は各 agent frontmatter の `opus`。

各 lens の返り値末尾の **機械可読 JSON block を読む** (`{"agent":..,"findings":[{"id","severity","axis","location"}],"summary":{..}}`)。prose の finding 記述ではなく **JSON block を一次ソース**にする (prose 決定的パースは禁止・貫く原則)。ただし synth を鵜呑みにせず、各 lens の raw 返り値 (JSON + prose evidence) を skill が直読して一次監査する。

**`ran_lenses` の決定 (fail-closed)**: JSON block を正常に emit して **完走した lens だけ**を `ran_lenses` に入れる。lens が死ぬ / spawn 失敗 / JSON block を出さない → その lens を `ran_lenses` から**除外**する。すると commit-check が machinery≠clean (`ran ⊉ expected`) を検出して **BLOCKED** に倒れる = fail-closed。欠けた lens を skill が推測で補完してはならない。

> **expected_lenses の SSoT 注記**: SRS pack の ceiling reviewer 集合は **3 lens** (`fidelity-srs` = gate J + `persona-walk-srs` = gate I + `completeness-critic-srs` = gate K)。ceiling 翼数の SSoT (taxonomy §5.3 + `verify-srs.sh`:24) は folio-mzn.1.4 landing で **2→3 翼 amend 済** (gate I/J/K)。本 SKILL はこの 3 lens を expected に配線する。

### 4. dedup (lens 横断・保守的)

lens 間で同一観察が別型で二重発火しうる (completeness の「off-target = 被覆ゼロ」と fidelity の「drift = 対象取り違え」は isolated reviewer には境界が曖昧・両方から valid に上がりうる)。commit-check は flat な findings を default-block 判定するだけで内容 dedup しないため、skill が commit-check へ渡す前に **lens 横断で保守的に意味 dedup** する (同一 `location` + 同一観察のみ・keep 寄り)。

> **★ dedup は safety-load-bearing でない (MUST 明記)**: この dedup は verdict-card の可読性のためであり、**重複を残しても over-BLOCK になるだけで false-GREEN は不能** (重複 finding は commit-check をより厳しく block 方向にしか効かない)。よって迷ったら **keep** する。**real finding を落としうる aggressive dedup を足してはならない** — 「似ているから」で別 location / 別観察の finding を畳むと真の欠陥を消して false-GREEN を作る。dedup は同一 location + 同一観察の literal な重複だけに限る。

### 5. Pass2 — finding-refuter で敵対的 refute

Pass1 findings のうち **GREEN を反転しうる severity のみ**を抽出する (lens 別 severity 語彙で規定・下表)。GREEN を止めない下位 severity (fidelity/completeness の medium/low・persona-walk の minor/polish) は Pass2 から除外する (記録には留める)。

| Pass1 lens | GREEN を反転しうる = Pass2 対象 | GREEN を止めない = 非対象 |
|---|---|---|
| `fidelity-srs` / `completeness-critic-srs` | **critical / high** | medium / low |
| `persona-walk-srs` | **blocker / major** | minor / polish |

> **★ literal 文字列で絞るな**: `critical/high` という fidelity 側の文字列だけで literal に絞ると persona-walk の `blocker/major` (= ceiling 片翼 gate I の GREEN 反転) が 1 件も選ばれず素通りする (fail-open)。必ず上表の **lens 別対応**で選ぶ。`blocker` は gate I が二値で断ずる北極星 miss ゆえ fidelity の critical/high と**同格**で必ず Pass2 に載る。

抽出した各 finding に **{finding, lens, axis, contract.yaml, 生成 HTML, anchor manifest}** を付けて `folio:finding-refuter` を spawn する (1 finding = 1 spawn が基本形・同一 pack の複数 finding をまとめて渡してもよい)。refuter は finding の **axis で判定 anchor を分岐**する (`agents/finding-refuter.md` §4 axis 別 anchor):

- **fidelity 軸** (`fidelity-srs` / `completeness-critic-srs` 由来) → SSoT (contract) を intent anchor に SSoT↔HTML を突合。
- **readability 軸** (`persona-walk-srs` 由来) → anchor は SSoT でなく**北極星** (非エンジニアが頑張れば読めるか) で HTML を persona 読み直し。

各 finding の出所 lens / axis を refuter へ渡し、正しい anchor を選ばせること (fidelity 軸を北極星で見ると SSoT 逸脱を見逃し、readability 軸を SSoT 突合で見ると gate I の北極星 miss を洗浄する)。refuter は verdict `upheld` / `refuted` / `uncertain` を返す (refute bias = 中立 evidence-based・裏付けが取れたときだけ refute・判断不能は uncertain として fail-closed)。verdict を finding にマージする。

> **★ verdict 欠落の扱い (commit-check が構造的に fail-closed 化・folio-6p0)**: `ceiling-commit-check` は「verdict==refuted / 明示 medium・low」**以外を全て block** する default-block ゆえ、GREEN 反転帯 (critical/high/blocker/major) の finding で refuter が verdict を返し損ねても (spawn 失敗等)、その finding は refuted でない → **BLOCKED** に倒れる (旧 `ceiling-adjudicate` の `select(upheld|uncertain)` 黙殺穴を構造的に封鎖・silent drop しない)。帯未満 (medium/low) の finding は verdict に依らず非 block ゆえ既定 verdict を要さない。**★literal な verdict 既定付与に頼らず、commit-check の default-block が「未検証 = refuted でない = block」を保証する**。

### 6. severity canonicalize (enum remap)

commit-check は canonical severity `{critical, high, medium, low}` で block 帯 (critical/high = refuted 必須) / 非 block 帯 (medium/low) を判定する。`persona-walk-srs` の native 語彙を canonical へ **enum remap** する:

```
blocker → critical    major → high    minor → medium    polish → low
```

`fidelity-srs` / `completeness-critic-srs` は既に canonical ゆえ remap 不要。**★この map は commit-check の帯判定に load-bearing**: `blocker→critical` / `major→high` で「北極星 miss」が GREEN 反転帯 (refuted 必須) に入り、`minor→medium` / `polish→low` で下位 severity が非 block 帯 (medium/low) に正しく入る (remap しないと `minor`/`polish` が非正準 severity 扱いになり commit-check が over-block する)。remap は列挙値の機械変換 = 機械 OK (severity を skill が推定/再判定するのではなく、agent が付けた native ラベルを 1:1 で対応づけるだけ・counting=機械 / labeling=LLM の境界を保存)。

### 7. normalized findings JSON 組成

commit-check 入力 schema を組む (下記 §8 ceiling-commit-check が読む schema):

```json
{"expected_lenses":["fidelity-srs","persona-walk-srs","completeness-critic-srs"],
 "ran_lenses":["<実際に完走した lens>"],
 "floor":"PENDING",
 "findings":[{"id":"F1","agent":"fidelity-srs","severity":"<canonical>","verdict":"upheld|refuted|uncertain"}]}
```

- `expected_lenses` = SRS pack の reviewer 集合 (§3 注記・3 lens 固定)。
- `ran_lenses` = 実際に spawn/完走した lens (§3 fail-closed)。
- `floor` = precheck が真 PENDING を確認したので `"PENDING"` (step 1)。
- `findings` = dedup 後・severity canonicalize 後・verdict マージ後の全 finding。**refuted も含めてよい** (commit-check は refuted を「clear 済」として非 block 扱いにする)。

### 8. verdict 合成 (LLM) + commit-check (機械の default-block gate)

**★境界 (最重要・folio-6p0)**: 機械は verdict を**裁定しない**。open-ended な LLM ラベル (severity/verdict) を決定的プログラムで裁定へ写像すると partial-enumeration trap に陥り false-GREEN を生む (旧 `ceiling-adjudicate` は uncertain-high・非正準 verdict・verdict 欠落 の 3 度 fail-open した)。よって裁定を 2 つに分離する:

**(a) verdict 合成 = 本 SKILL (LLM orchestrator) の判断**。全 lens の findings + refuter verdicts を **raw で一次監査**し、「どの finding が GREEN を止めるか (未 refute の critical/high/blocker/major)」「clearly-broken (FAIL 相当) か human-judgment 待ち (ESCALATE 相当) か」を**意味で判断**して verdict card の narrative を組む (§9)。この判断は決定的プログラムでなく LLM が行う (確信は ensemble + 敵対 refute から来る・thesis「別建ての決定的安全網を後付けしない」)。

**(b) commit-check = 機械の単一 default-block 保証** (LLM 合成 (a) が緩んでも GREEN を通さない hard gate):

```bash
printf '%s' "$NORMALIZED" | ~/.claude/plugins/folio/.claude-plugin/bin/folio ceiling-commit-check; commit_rc=$?
```

stdout `COMMIT=OK|BLOCKED` + blocking finding 列挙。exit **0=OK / 1=BLOCKED / 2=tool error**。COMMIT=OK の条件は「machinery-clean (expected⊆ran ∧ floor=PENDING) ∧ 全 GREEN 反転帯 finding が verdict==refuted」。**refuted / 明示 medium・low 以外は全て block** ゆえ、uncertain-high も 非正準 verdict も verdict 欠落も全て BLOCKED に倒れる (悪いケース列挙でなく良いケースの普遍要求 = 穴が原理的に開かない)。

> **★fail-closed (絶対)**: `commit_rc != 0` (BLOCKED も tool error も) は一律「**GREEN 不可**」として扱う (機械故障を GREEN に倒さない)。LLM 合成 (a) は commit-check (b) を **override できない** — `commit_rc != 0` なら card がどう narrate しようと READY/GREEN にしてはならない。機械が守るのはこの 1 点 (default-block) のみで、verdict の意味的裁定は (a) の LLM が担う。

### 9. verdict card (3 バンド + 5-state)

**3 バンド**で提示する: **floor** (verify-srs + precheck の結果) / **ceiling** (LLM 合成 narrative + commit-check の `COMMIT=OK/BLOCKED` + 各 lens findings 要約) / **人間** (--accept の要否と可否)。そのうえで **5-state** のいずれかを確定する:

- **STALE** — verify-state 記録あり & 現在の html/contract の hash が記録と相違 (staleness = 検証後に成果物が変わった)。
- **FLOOR-FAIL** — precheck が exit 1/3 (floor 未通過 / SKIP masquerade)。ceiling に進んでいない。
- **CEILING-FAIL** — **commit-check が BLOCKED (`commit_rc != 0`)**。未 refute の GREEN 反転帯 finding が残る / machinery≠clean / tool error のいずれか。LLM 合成 (§8a) が「clearly-broken (FAIL 相当)」か「human-judgment 待ち (ESCALATE 相当)」かを narrate し、blocking finding と欠けた machinery を card に明示する (GREEN にはできない)。
- **READY (承認待ち)** — **commit-check が OK (`commit_rc == 0`)** かつ未 `--accept`。人間の toppling 待ち。
- **GREEN (承認済)** — 人間が `--accept` 済 (`by user@time` を記録)。

> **★fail-closed の要 (旧 adjudicate exit-2 穴の封鎖)**: state は commit-check の **exit code** で決める。`commit_rc==0` のみ READY、それ以外 (1=BLOCKED / 2=tool error) は全て CEILING-FAIL。「BLOCKED でも tool error でもない=READY」という default-READY 解釈をしてはならない (機械故障を GREEN に倒す fail-open)。ESCALATE/FAIL の区別は LLM narrative の UX であって、機械 gate は OK/BLOCKED の二値。

### 10. --accept (人間 toppling・fail-closed)

`--accept` は **commit-check を再走し `commit_rc == 0` (COMMIT=OK) のときだけ**許可する (state=READY 相当):

```bash
printf '%s' "$NORMALIZED" | ~/.claude/plugins/folio/.claude-plugin/bin/folio ceiling-commit-check; commit_rc=$?
# commit_rc==0 のときだけ GREEN を許可。それ以外 (1=BLOCKED / 2=tool error) は一律拒否 (fail-closed・override 不可)。
```

拒否時は commit-check の `blocking(...)` 行 (どの finding が block したか) を示して GREEN にしない。成功時のみ verify-state を **GREEN (承認済 by user@time)** で書き込む。これが本 SKILL の fail-closed な肝 — 未 refute の GREEN 反転帯 finding (critical/high/blocker/major の upheld・uncertain・非正準・欠落 verdict) を人間が「まあいい」で GREEN に倒す事故を、**機械の default-block コミット述語で構造的に防ぐ** (LLM 判断でも人間判断でも override 不可)。

### 11. verify-state 永続

検証結果を `.folio/verify-state/<pack>.json` に記録する (runtime state ゆえ `.folio/` = 既に `.gitignore` 済・inventory.json と同様に VCS 追跡しない)。記録項目:

```
{html, contract, html_hash, contract_hash, commit_status, findings_summary,
 state, accepted_by, accepted_at}
```

staleness (STALE state) 判定は **現 hash vs 記録 hash** の比較で行う (html/contract が検証後に変われば記録は無効化)。

### 12. loop-until-dry (seen-set)

ceiling は複数 round 回してよい (skeleton は最大 2 round)。各 round で Pass1 lens が上げた finding を **seen-set** で消し込み、**新規 finding が出なくなったら停止**する。1 round でも可だが、見落としを構造的に詰める **loop-until-dry を intended pattern** とする (seen-set の dedup 基準は「上げた finding 全体」であって「confirmed のみ」ではない = refuter に棄却された finding を毎 round 蒸し返して収束しない事故を避ける)。

---

## cell-quality 自己 gate (worker が自分でやる・close はしない)

- 本 SKILL frontmatter が `name: folio-verify` かつ `disable-model-invocation: true` であること。
- 4 subcommand (`verify-srs` / `ceiling-anchors` / `ceiling-precheck` / `ceiling-commit-check`) と 4 agent (`fidelity-srs` / `persona-walk-srs` / `completeness-critic-srs` / `finding-refuter`) を参照していること。
- 必須規約が明文化されていること: severity enum map / dedup 非 load-bearing 注記 / verdict 欠落=commit-check default-block で block (literal 既定付与に頼らない) / fail-closed --accept (commit_rc==0 のときだけ許可) / 5-state 名 5 つ。
- 完了したら gate-pending ラベルを付け、self-report (何を作った/どのファイル/未解決) を bd notes に書く。**自己 close 禁止** (close は admin が gate+merge 後)。

## 制約・注記

- 本 SKILL は `disable-model-invocation: true`。user が明示的に `/folio-verify` で起動する。
- 本 SKILL は **SKILL のまま (subagent 化しない)** — Pass1 の 3 lens と Pass2 の refuter を spawn する orchestrator は main-session 必須 (nesting 制約)。
- Pass1 lens (fidelity-srs / persona-walk-srs / completeness-critic-srs) と Pass2 (finding-refuter) は全て **read-only** — findings/verdicts を返すだけで自ら Edit しない。修正が要る場合は本 SKILL の外 (生成器の manifest 修正 / contract 見直し) で行う。
- floor が測る構造 (部品存在・RTM 集合一致・no-TBD 等) を ceiling は再検査しない (verify-laundering 禁止: 「floor が緑だから正当」を finding 棄却の根拠にしない)。
- pack は SRS のみ (`ceiling-anchors` が SRS 専用)。他 doc-type への一般化は後続 cell。

## 参照

- floor / ceiling helper: `.claude-plugin/design-system/generator/{verify-srs,ceiling-precheck,ceiling-anchors,ceiling-commit-check}.sh` (schema の SSoT・重複コピペせず file を読む)
- dispatch: `.claude-plugin/bin/folio` (subcommand: verify-srs / ceiling-anchors / ceiling-precheck / ceiling-commit-check)
- Pass1 lens: `agents/{fidelity-srs,persona-walk-srs,completeness-critic-srs}.md` (出力 JSON block・severity 語彙)
- Pass2 refuter: `agents/finding-refuter.md` (§1 GREEN 反転帯対応表 / §4 axis 別 anchor / §5 verdict JSON)
- 雛形: `skills/folio-architect/SKILL.md` (disable-model-invocation・canonical bin path・Phase F 並列 spawn)
- SRS taxonomy: `architecture/research/srs-component-taxonomy.html` §5.1 (判定式 `GREEN ⟺ floor AND ceiling`) / §5.3 (gate I/J/K)
