# folio S4 generator (ADR-0042)

機械 SSoT (構造化された要件レコード) から人間プレゼン HTML を **ハイブリッド生成**する道具。
ADR-0042 §2.1 (生成方式) / §2.2 (A/B 可読化) / §3 (捏造リスク緩和) を実装する。

## パイプライン

```
contract.yaml ─validate→ assemble-srs.sh → HTML(内容=決定的・prose スロット空) ─┐
   (機械SSoT)  (fail-closed) (決定的・捏造不可)                              │  各空スロットは
prose.yaml ─────────────────────────────────────────────────────────────┴→ inject-prose.sh → HTML(充填) → 完成
 (opus 著作・slot-id→散文)              (決定的・escape・fail-closed)             ▲
                                                                                ├ verify-fabrication-free.sh [--filled] で機械証明
                                                                                └ test-adversarial.sh で攻撃の fail-closed を回帰
```

- **① 入力 contract** (`contract/*.srs.yaml`) — assembler が読む構造化 SSoT。
  meta / approval / goals / scope / actors / upper_needs / acceptance(正典集合) / requirements / nfr(hero 付き) /
  constraints / glossary。 要件は id/type/label/ears{pattern,condition,response}/priority/vmethod/trace{backward,acceptance}/rationale_source。
- **② 決定的 assembler** (`assemble-srs.sh`) — contract → catalog 部品準拠 HTML (`srs.css` inline、 自己完結)。
  共通 idiom (q/esc/mark_terms/band/cover骨格/glossary/footer/finalize) は `lib/common.sh` (core) から source (B2 / folio-5ua)。
  - **内容**(要件/NFR/scope/actor/制約/用語/受入/goal/上位ニーズ)は全て contract から決定的に組立。 元データに無い行・列・リンクを生成できない。
  - RTM の ●(backward)/受入(acceptance) は contract 集合から導出。 集合外参照・id 重複・自由記述の tab/改行・未知 EARS/priority/tint は validate() が **fail-closed** で生成前に拒否。
  - 全自由記述値を **HTML escape** (`& < > "` 実体参照化) してから注入 (任意 markup を構造へ通さない)。
  - 検証可能な数値 (件数/トレースリンク/孤立/未検証) は決定的集計し `data-derived` に刻む (opus に書かせない、 §3)。
  - 各 prose スロットは **空** で出力し、 決定的な `data-slot-id` (例 `plain-FR1` / `rationale-FR3` / `chapter-lead-04` / `rtm-summary` / `cover-summary`) を付ける = ③ の注入ターゲット。
- **③ opus prose 充填** = `prose/*.prose.yaml` (manifest) + `inject-prose.sh` (決定的注入)。
  - **opus が書くのは manifest だけ** (slot-id → 散文)。 ADR-0042 §2.1 の opus スロット = 章リード / plain (やさしい言い換え) / **「なぜ要る」根拠** / RTM 平易要約 / 1 文サマリ。
  - **注入は機械的** — `inject-prose.sh` が manifest 値を **HTML escape** して `data-slot-id` 一致スロットへ埋める。 任意 markup は escape され構造を壊せない (fabrication-free を prose 層でも保つ)。
  - **fail-closed**: HTML スロット id 集合と manifest key 集合が完全一致 (未充填=脱落 / 余剰=orphan を両方拒否)。 値の tab/改行・空・注入後の空スロット残存も拒否。
  - rationale は **rationale_source(id 接地)のみが SSoT で散文は opus 生成**ゆえ、 fidelity ceiling(S5)の主対象になる。

## ADR-pack = instance#2 (folio engine B1 / folio-bwc / rule-of-three)

SRS generator の機構を **別 doc-type (ADR / 設計判断記録)** へ適用した二例目。 狙い = SRS-pack ∩ ADR-pack の
共通項を炙り engine core を抽出可能にする (抽出自体は後続別 bd)。 設計記録 = `architecture/research/document-discipline-engine-design.html` (B0 6 論点)。

- **入力 contract** (`contract/clinic-double-booking.adr.yaml`) — ADR-pack schema: meta(adr_status) / approval /
  cross_doc / context / drivers / options(pros/cons/verdict) / decision(chosen+justifies) / consequences(positive/negative) /
  supersession / principle / glossary。
- **決定的 assembler** (`assemble-adr.sh`) — `assemble-srs.sh` と共に `lib/common.sh` (core) を source (B2 / folio-5ua、
  元は assemble.sh を fork したもの)。 cover骨格/glossary/footer/term-inline (mark_terms)/band/esc/finalize は共用 (core)、
  context/drivers/options/decision/consequences/supersession/principle は ADR 固有 emitter。 ADR 固有 CSS は
  srs.css token を流用 (dark は token 経由で自動追従)。
- **★cross-doc 照会 (本 pack の核)** — `decision.justifies[].req` が参照先 SRS contract (`cross_doc.srs_contract`) の
  要件 ID に実在することを assembler validate と `verify-adr.sh` が **二重に fail-closed** で確かめる (dangling 照会 0)。
  B0 论点2 の抽象ロール graph: decision=claim / options=exploration / context→rationale / principle=照会終端。
  生成物では「採用判断」章に FR2/FR3 への justify edge を可視化 (role バッジ + 照会先)。
- **prose injector は SRS と無改変共用** (`inject-prose.sh`) — `data-slot-id` ベースで pack 非依存。
  ★この共通化が rule-of-three の「SRS-pack ∩ ADR-pack = core」を炙る一次証拠。
- **floor** = `verify-adr.sh [--filled <manifest> | --artifact] <adr-contract> <html>` (行数=contract導出 / id 一意 /
  cross-doc 照会解決 / verdict 整合 / escape 健全 / prose 空|充填|注入忠実 / term-inline fidelity+被覆)。
- **2-gate ceiling** = ADR-pack fidelity (機械 SSoT 突合 = verify-adr + fidelity-srs 相当) + persona-walk (非エンジニア可読)。
  ★ADR 専用 ceiling agent (persona-walk-adr / fidelity-adr) の制度化は core 抽出後の follow-up。
- **敵対回帰** = `test-adversarial-adr.sh` (83 ケース・TV5-1〜4 含む: cross-doc dangling/doc_id/不在・role/verdict/status・id 重複・改行・
  glossary 部分文字列・HTML 偽 justify 注入・行数削除・prose 改竄・term 改竄・chosen 捏造・inject 集合不一致・escape・
  ★role 別 role 改竄 (req,role ペア)・★verdict バッジ付け替え (opt-id,verdict ペア)・
  ★既存 justify edge 重複注入 (count anchor)・★verdict 可視ラベルのみ改竄・★principle.id/supersession.status/superseded_by 改竄・
  ★ds8 ceiling round-1〜4 (nested-tag early-match / hyphen-tag swap / cover-meta / cxid / drid / justify-role)・★dty (drg)・
  ★TV5-1〜4 (folio-tv5 = verify_cross_doc_refs の LC_ALL=C 照合統一。 ★これは **latent 防御 hardening で red→green ではない**:
  旧コードは 1 run 内で sort/comm を同一 locale で実行し内部一貫ゆえ mixed-case key でも public path では PASS する。
  TV5-1/2 = 非回帰 smoke / TV5-3 = origin/main 旧版との differential (旧=新=PASS を明示記録) / TV5-4 = fix が pin する
  sort/comm 照合 primitive の red→green))。
  ★abort 系は **stderr 理由を検証**し「別原因の誤 abort」= false-pass を弾く (S4 の A1 否定検証 false-pass 教訓)。

```bash
./assemble-adr.sh contract/clinic-double-booking.adr.yaml asm.html
./inject-prose.sh prose/clinic-double-booking.adr.prose.yaml asm.html filled.html   # ← SRS と同じ injector
./verify-adr.sh --filled prose/clinic-double-booking.adr.prose.yaml contract/clinic-double-booking.adr.yaml filled.html
./test-adversarial-adr.sh
```

## research-pack = instance#3 (folio engine B3 / folio-ar1 / rule-of-three 止め時判定)

SRS/ADR generator の機構を **3 例目の doc-type (research / 調査記録 = 「何を検討したか」doc)** へ適用した三例目。
狙い = **★B2 で抽出した core (`lib/common.sh` + `lib/verify-common.sh`) を 1 バイトも変えず、 純粋 pack として挿さるか**を
実証する (rule-of-three の止め時判定)。 挿されば core 確定 = 抽出完了。 **挿さった = core / pack 境界が実物で確定**
(`git diff --stat lib/` 空 + `inject-prose.sh` 無改変共用 + 既存 SRS/ADR pack 非回帰)。 同一ドメイン (クリニック二重予約防止) で
**research → ADR → SRS の照会トリロジー**を完成させる。

- **入力 contract** (`contract/clinic-double-booking.research.yaml`) — research-pack schema: meta(research_status) / approval /
  cross_doc / question(in/out scope) / findings / approaches(leads_to/role・★verdict なし) / open_questions / outcome / glossary。
  ★構造差 (research の hallmark): **verdict が無い** (探索は決めない) / **open_questions を持つ** (結論しない) /
  cross_doc が **前方参照** (research → ADR)。
- **決定的 assembler** (`assemble-research.sh`) — `assemble-srs.sh` / `assemble-adr.sh` と共に `lib/common.sh` (core) を source。
  cover骨格/glossary/footer/term-inline (mark_terms)/band/esc/finalize は共用 (core)、 question/findings/approaches/open_questions/outcome は
  research 固有 emitter。 research 固有 CSS は srs.css token を流用 (dark は token 経由で自動追従)。
- **★cross-doc 前方照会 (本 pack の核)** — `approaches[].leads_to` が後続 ADR contract (`cross_doc.adr_contract`) の
  `.options[].id` に実在することを assembler validate と `verify-research.sh` が **二重に fail-closed** で確かめる (dangling 0)。
  ADR が SRS 要件 ID を後方照会したのと **同じパターンを別ターゲット (ADR option id) へ適用** = 照会機構が doc-type 非依存に
  再利用できることの実証。 加えて adr_doc_id 一致 / outcome.resolved_by == adr_doc_id (照会終端側) / role 抽象 allowlist /
  (leads_to,role)・(ap-id,leads_to) ペア集合一致 / 可視 id 整合 / count anchor で改竄を多面的に捕捉。
- **prose injector は SRS/ADR と無改変共用** (`inject-prose.sh`) — `data-slot-id` ベースで pack 非依存。
  ★3 例目でも無改変で挿さった = rule-of-three の「core 確定」一次証拠の再現。
- **floor** = `verify-research.sh [--filled <manifest> | --artifact] <research-contract> <html>` (行数=contract導出 / id 一意 /
  cross-doc 前方照会解決 / outcome 整合 / escape 健全 / prose 空|充填|注入忠実 / term-inline fidelity+被覆)。
- **敵対回帰** = `test-adversarial-research.sh` (R1-R25: cross-doc dangling/doc_id/不在・role allowlist 外・resolved_by 不一致・
  research_status・id 重複 (finding/approach/open-question)・改行・glossary 部分文字列・HTML 偽 leads-to 注入・card 削除・
  prose 改竄・term 改竄・★role 別 role 改竄 (leads_to,role ペア)・★edge 付け替え (ap-id,leads_to ペア)・★leads chip 重複 (count anchor)・
  ★可視 id のみ改竄 = `<b>` 保持で中身改竄 (vis 整合)・★`<b>` 欠落 + 可視平文偽 id = R25 (NO-B 検出 + 可視 `<b>` 本数 count anchor)・
  ★outcome resolved-by 改竄・inject 集合不一致・escape)。 ★abort 系は **stderr 理由を検証**し
  「別原因の誤 abort」= false-pass を弾く。 ★R17/R18/R24/R25 は各々 **(ap-id,leads_to) / count / vis (`<b>` 保持改竄) / vis (`<b>` 欠落 = NO-B+本数 count)**
  のみが捕捉する設計 (各 robustness check が冗長でなく必要であることを実証。 vis 整合は全 chip 列挙ゆえ `<b>` マッチ前提の
  fail-open を持たない = cell-quality WF round1 の major 指摘を反映)。
- **cross-doc 解決 helper の core 昇格は ds8 で完了** (B3 では範囲外=候補記録のみだった)。 ADR・research 両 pack の
  cross-doc 解決スケルトン (照会先実在/doc_id/count/SET/dangling/空値ガード/role allowlist/(key,role)ペア) を
  `lib/verify-common.sh` の `verify_cross_doc_refs` へ 1 本化した (詳細は下の「ds8」節)。

```bash
./assemble-research.sh contract/clinic-double-booking.research.yaml asm.html
./inject-prose.sh prose/clinic-double-booking.research.prose.yaml asm.html filled.html   # ← SRS/ADR と同じ injector
./verify-research.sh --filled prose/clinic-double-booking.research.prose.yaml contract/clinic-double-booking.research.yaml filled.html
./test-adversarial-research.sh
```

## principle-pack = instance#4 (folio engine B4 / folio-igv / 照会終端ロールの実 doc-type 化)

SRS/ADR/research generator の機構を **4 例目の doc-type (constitution / 不変原則 = 「照会の終端」doc)** へ適用した四例目。
照会の抽象ロール `principle` (B0 论点2 = 照会終端) を実 doc-type として cover する。 題材 = folio 自身の 14 不変原則を
frozen `architecture/spec/constitution.html` から **read-only で忠実抽出**し、 「engine が folio 原則を再現できる」を
読み比べで実証する (frozen constitution.html は **絶対に編集しない** = P-10。 生成は別ファイル)。

- **入力 contract** (`contract/folio-constitution.principle.yaml`) — principle-pack schema: meta(doc_type:constitution) / approval /
  decisions_dir / principles(id/heading/statement/tier/amended_by) / versioning(s5) / amendment(s6) / inbound / glossary。
  ★構造差 (principle の hallmark): **前方照会を持たない** (照会の終端) / **inbound のみ受ける** / **amended_by = 改訂来歴の別軸 edge** /
  **tier (Always/Ask-first/Never) で原則を 3 群に分類**。
- **決定的 assembler** (`assemble-principle.sh`) — `lib/common.sh` (core) を source。 cover骨格/glossary/footer/term-inline (mark_terms)/band/esc/finalize は共用 (core)、
  principles(tier 3群 emit)/amendment 来歴/versioning 表/amendment 手順/inbound チップは principle 固有 emitter。 固有 CSS は srs.css token を流用。
  ★生成前 fail-closed: **doc_type==constitution 必須** (doc_type flip で verify の gate を bypass する経路を生成段で封鎖) /
  principle に許可外キー (leads_to/justifies 等の前方照会) があれば abort (終端不変条件) / top-level に cross_doc/outcome があれば abort /
  inbound.ref が principles に実在しなければ abort (phantom) / amended_by の ADR が decisions_dir に実在しなければ abort。
- **prose injector は SRS/ADR/research と無改変共用** (`inject-prose.sh`) — `data-slot-id` ベースで pack 非依存。
  ★4 例目でも無改変で挿さった = rule-of-three の「core 確定」一次証拠の再現 (B4 の止め時 MET 確認)。
- **floor** = `verify-principle.sh [--filled <manifest> | --artifact | --write-baseline] <contract> <html>` — 行数=contract導出 / id 一意 /
  可視 pid・heading 順序 (tier-grouped) / tier badge fidelity / statement fidelity (term バッジ strip 後の可視テキスト == esc(contract)) /
  amendment 来歴 fidelity / cover-meta 再導出 / escape 健全 / prose 空|充填|注入忠実 / term-inline。 加えて **principle 固有 3 gate**:
  - **①終端強制**: HTML に前方照会 chip (leads_to/justifies/resolved_by/cross-doc-*) が無いことを確かめる (inbound = data-inbound-* は受ける照会ゆえ別物・許可)。
  - **②baseline-diff gate** (doc_type:constitution のみ・doc_type は assemble/verify 双方で fail-closed 束縛ゆえ flip で skip 不可): principles の
    committed golden (`baselines/folio-constitution.principle.golden` = `id\ttier\tsha256(heading+statement)\tamended_adrs`) と diff し、
    **見出し (heading) / 宣言文 (statement) / tier / 改訂来歴 (amended_by) / 増減 のいずれの変化にも必ず (新規 amended_by → 実在 ADR) + (版 bump) を要求** = silent change を機械的に不可能化。
    版 bump は `sort -V` で前進 (downgrade/同値/garbage を bump と誤認しない)。 golden は `--write-baseline` で生成 (人間が原則変更を承認したときに更新する正規路)。 B0 決定③ guarantee=CI / 決定④ P-10 一般化を機構化。
  - **③inbound fail-closed** (doc_type:constitution のみ): core の `verify_cross_doc_refs` を **target=self** で再利用し、 inbound.ref が
    principles[].id に実在 (dangling 0 = phantom 照会捕捉) / role 抽象 allowlist / (ref,role) ペア集合一致 を確かめる (照会終端 node の局所整合)。
  ★floor 通過は `CEILING=PENDING` (taxonomy §5.1)。 graph 全体の終端完備 (全チェーンが principle で終端) は **B5 (folio-983) へ切出し**。 専用 ceiling agent 制度化は follow-up。
- **敵対回帰** = `test-adversarial-principle.sh` (A1-A10 assemble abort / BD1-BD7 ★baseline-diff (silent change 6 + 正当改訂 PASS 1) /
  ★BD8-BD11+A11 cell-quality errata 回帰 (doc_type flip abort+FAIL / heading-only silent / amended_by 消去 / version downgrade / empty amended_by:[] 整合) /
  T1 終端 / IB1-IB5 inbound / F1-F16 fabrication-free / C1-C6 core chrome / J1-J2 inject = 54 ケース)。 ★abort 系は stderr 理由を検証・verify FAIL 系は理由 substring を検証し false-pass を弾く。
  ★baseline-diff 系は mutated contract を **canonical basename のサブdir** に置き committed golden へ解決させる (別名だと「golden 不在」FAIL で silent-change 検出を検証できない false-pass になる)。

```bash
./assemble-principle.sh contract/folio-constitution.principle.yaml asm.html
./inject-prose.sh prose/folio-constitution.principle.prose.yaml asm.html filled.html   # ← SRS/ADR/research と同じ injector
./verify-principle.sh --filled prose/folio-constitution.principle.prose.yaml contract/folio-constitution.principle.yaml filled.html
./verify-principle.sh --write-baseline contract/folio-constitution.principle.yaml      # ← 原則変更を承認したとき golden を更新
./test-adversarial-principle.sh
```

## spec-pack = instance#5 (folio engine B6 / folio-8ct / self-dogfood endgame)

SRS/ADR/research/principle generator の機構を **5 例目の doc-type (rules / Layer 1 普遍規約 = 「EARS 章立て規範文 + 非終端 照会」doc)** へ適用した五例目。 狙い = **★core (`lib/{common,verify-common,graph-common}.sh` + `inject-prose.sh`) を 1 バイトも変えず純粋 pack として挿さるか**を folio 自身の `architecture/spec/rules.html` で実証する (rule-of-three の **B6 完成サイン** = engine が folio 文書型を再現できる self-dogfood)。 挿さった証拠 = `git diff --stat lib/ inject-prose.sh` 空 + 既存 4 pack 非回帰 + sandbox 40/40 + validate clean。 ★frozen でない `rules.html` は **読むだけで一切編集しない** (非破壊・生成は別ファイル `/tmp/folio-design-samples/b6-spec/`)。

- **入力 contract** (`contract/folio-rules.spec.yaml`) — spec-pack schema: meta(doc_type:rules) / approval / graph(principle_edge) / **machine_preamble** / sections(id/tint/kicker/heading/essence/blocks[]/**machine_blocks[]**) / requirements(id/ears_pattern/essence/statement) / references(非終端 照会) / glossary。 ★機械抽出 DRAFT を `scripts/extract-rules-spec.sh` が起こす (人間レビュー前提)。
  - **block types** (section 内 content・document 順): `prose` / `note`(aside) / `list` / `code`(lines[]・改行回避) / `table`(caption/headers/rows) / `mermaid`(source_lines[]・source-text 表現) / `subhead`(heading/essence) / `requirements`(ids[])。 ★**未対応 block type は silent drop せず fail-closed abort** (no silent caps)。
  - **★機械層 (machine free-prose・w1f cell-2 / ADR-0045)**: `machine_preamble`(section 外の文書前文) + `sections[].machine_blocks[]`(section 内の `data-audience="machine"` 自由文 = rationale/context/運用説明) を cell-1 が逐語 capture (inner HTML 保持・`prose`→`<p>` / `note`→`<aside>` / `list`→`<ul>`)。 cell-2 がこれを **canonical `data-audience="machine"` form で RAW emit** (★二重 escape 厳禁 = `html` は既に生 HTML) し、 要件 fold も `data-audience="machine"` 化する (REQ-DA-STRUCT-1..5 を *生成物* へ適用)。 ★適合は **verify-spec §10 が *相当* に enforce** する — canonical な `folio_check_dual_audience` (bin/folio) は要件 container を `<(section|details) data-audience="human">` で key するため、 生成物の `<div data-component="ears-requirement-row" data-audience="human">` row は未被覆 (生成物は /tmp 生成ゆえ `folio validate` 非対象)。 canonical container form (section/details) への寄せ / validate-gate 被覆は follow-up (folio-tr0) 領分。 機械層 block 種別も `prose|note|list` の allowlist 逐値検査 (silent drop 禁止)。
  - ★構造差 (rules の hallmark): **非終端 照会** (principle 終端 / SRS 片方向 の *中間* = 前方 references を持つ)。 EARS 5-pattern (ubiquitous/event-driven/state-driven/optional/unwanted) の章立て規範文。
- **決定的 assembler** (`assemble-spec.sh`) — `lib/common.sh` (core) を source。 cover骨格/glossary/footer/band/esc/finalize は共用 (core)、 sections/blocks emitter / EARS 要件 row / references(前方照会 chip) は spec 固有 emitter。 固有 CSS は srs.css token を流用。 ★term-inline (mark_terms) は不使用 = rules 用語は plain_short を持たない (glossary は term + def・rules.html の `span.term[data-tooltip]` 由来)。
  - ★生成前 fail-closed: **doc_type==rules 必須** (flip で gate bypass 不可) / 未知 EARS・tint・reference role / 要件 id・section id 重複 / **要件 ↔ requirements block の集合一致** (孤立要件・二重配置・未定義参照) / 空 reference token / graph.principle_edge role allowlist / 未対応 block type。
- **prose injector は SRS/ADR/research/principle と無改変共用** (`inject-prose.sh`) — `data-slot-id` ベースで pack 非依存。 ★**5 例目でも無改変で挿さった = rule-of-three の B6 完成サイン**。 prose スロットは cover-summary + chapter-lead-NN (band 毎) のみ = 捏造面を最小化 (essence/要件/照会は faithful contract data)。
- **floor** = `verify-spec.sh [--filled <manifest> | --artifact] <contract> <html>` — 行数=contract導出 (section/band/要件/ref chip/block 種別) / 要件 fidelity (data-req-id 集合 + (id,pattern,class,label,essence,statement) emission 順タプル) / section heading・essence・kicker 順序 (kicker = §N/トピック band ラベル・決定的フィールド・folio-l93 で floor 化) / block fidelity (prose/note/list/code/table/mermaid/subhead 可視テキスト順序突合) / **非終端 照会 fidelity** (chip echo: token/doc/role count・SET・role allowlist・(token,role) ペア・可視 `<b>`==attr) / core 共通 chrome (verify_core_chrome) / cover-meta 4 KV 再導出 / escape 健全 / prose スロット (3 mode)。 ★**機械層 floor (w1f cell-2 / ADR-0045 論点4)**: 機械層件数 (prose/note/list/li/fold) + **REQ-DA-STRUCT-1..5 適合** (folio_check_dual_audience 相当: -1 human→machine 子孫 / -2 id 整合 / -3 data-audience 値域 / -4 machine 部 aria-hidden 不在 / -5 EARS-pattern 整合) + raw-emit (二重 escape 無し) + **原本↔生成物 機械層 双方向 *順序付き* 一致** (rules.html を直 grep して生成 path 独立に照合・完全性/no-fabrication・fail-closed・★両側を sort せず document 順で diff = 順序入替/cross-section 誤帰属も検出・人間層 §4/§5 と対称)。 ★floor 通過は `CEILING=PENDING` (taxonomy §5.1)。
- **非終端 照会の graph 接続** (`rolemap/spec.rolemap.yaml`) — `graph.principle_edge` (rules→constitution・role=implementation・direction=forward) を verify-graph.sh の rolemap edge が pin し、 reachability で **FOLIO-RULES が FOLIO-CONSTITUTION 終端へ到達** することを実証する。 ★これが principle pack が B5 で external-ref warn として残した「inbound from: rules.html」を graph で閉じる (self-dogfood で rules も終端完備に)。 ADR/verification 前方照会は external-ref warn (B6 では実在/reverse 解決は範囲外)。
- **bootstrap extractor** (`.claude-plugin/scripts/extract-rules-spec.sh`) — `rules.html` を read-only 走査し contract DRAFT を起こす one-shot。 meta / sections(heading+essence) / requirements(spec-row) / glossary(term span dedup) / references(xref) / content blocks(subhead/table/code/mermaid/requirements) を抽出。 ★**w1f cell-1 で skip→capture へ反転**: `data-audience="machine"` の自由文 (45 prose + 16 note + 10 list = 71 block、 文書前文 1 含む) を `machine_preamble` / `sections[].machine_blocks[]` へ逐語 capture し、 capture 件数を stderr に LOG する (no silent caps)。 旧版は「モデル化しなかった件数を LOG」する skip 設計だったが、 機械層 round-trip (full self-host) のため capture へ反転した。
- **敵対回帰** = `test-adversarial-spec.sh` (A1-A16 assemble abort [doc_type flip / 未対応 block type / EARS / tint / id 重複 / 孤立要件 / 未定義参照 / 二重配置 / role / 空 token / graph role / 改行 / EARS 空白 split / tint 空白 split / references role 空白 split] + F1-F18 verify FAIL [要件 row 削除 / 可視 rid / statement / essence / EARS badge / section heading / section essence / ref token SET / ref 可視 `<b>` / ref role / table cell / code 行 / subhead / mermaid source / cover-meta / core chrome / prose 注入 / escape 健全] + F19-F22 kicker drift [§番号 swap / topic 取り違え / heading §N 不整合 / 静的 band kicker drift・folio-l93] + F23-F25 EARS 凡例 [label drift / item 削除 / el-when drift・folio-2jr] + G1 空 en glossary (core emit_glossary・folio-4wz) + **M1-M15 機械層 (w1f cell-2)** [prose 改竄 / prose 脱落 / prose 捏造 / list item 脱落 / data-audience 値域違反=REQ-DA-STRUCT-3 / aria-hidden=REQ-DA-STRUCT-4 / human container 剥奪=REQ-DA-STRUCT-1 / 未対応 machine block type abort×2 / 二重 escape=round-trip / **block 順序入替=順序付き round-trip** / **cross-section 誤帰属=順序付き round-trip** / **note 改竄=round-trip** / **note 脱落=件数+round-trip** / **原本不在 fail-closed=SPEC_ORIGIN_HTML override で §11 fail-open 封鎖を red→green pin**] + J1-J2 inject + P1-P2 健全性 = 61 ケース)。 ★abort 系は stderr 理由を検証・verify FAIL 系は理由 substring を検証し false-pass を弾く。

```bash
.claude-plugin/scripts/extract-rules-spec.sh > contract/folio-rules.spec.yaml   # ← rules.html から contract DRAFT を機械抽出 (LOG は stderr)
./assemble-spec.sh contract/folio-rules.spec.yaml asm.html
./inject-prose.sh prose/folio-rules.prose.yaml asm.html filled.html             # ← SRS/ADR/research/principle と同じ injector
./verify-spec.sh --filled prose/folio-rules.prose.yaml contract/folio-rules.spec.yaml filled.html
./test-adversarial-spec.sh
```

### spec-pack FORK = verification self-host (folio engine tr0 / folio-nxp / doc-type=spec 2例目)

spec-pack (rules) を **doc-type=spec の 2 例目** (`architecture/spec/verification.html`) へ適用した FORK。 狙い = w1f の rules self-host を別 folio 文書型 (spec) へ広げる。 **★共有 core (`lib/*.sh` + `inject-prose.sh`) + 共有 spec-pack スクリプト (`extract-rules-spec.sh` / `assemble-spec.sh` / `verify-spec.sh`) を 1 バイトも触らず、 新ファイルの新設のみで挿す** (FORK = 並列安全・rule-of-three pack 層)。 ★frozen でない `verification.html` は **読むだけで一切編集しない** (非破壊・生成は `/tmp/folio-design-samples/tr0-verif/`)。

- **新ファイル**: `.claude-plugin/scripts/extract-verification-spec.sh` (extractor fork) / `assemble-verification.sh` / `verify-verification.sh` / `test-adversarial-verification.sh` / `contract/folio-verification.spec.yaml` / `prose/folio-verification.prose.yaml`。
- **★verification 固有差分 = 機械層 `demoted`** (rules.html に無い): verification.html は機械層に `<div class="demoted" data-audience="machine">` を 4 箇所持つ (ADR-0040 圧縮の機械層降格分・中身は `<p>`/`<ul>`/`<pre><code>`)。 現 extractor は `<p>/<aside>/<ul>` のみ拾い div は死角ゆえ、 fork は **div.demoted を machine_block `type: demoted` として balanced div で inner を逐語 capture** (round-trip 被覆)。 assemble は `<div data-component="spec-machine-demoted" data-audience="machine">` で RAW emit (二重 escape 厳禁)、 verify は件数 + 双方向 *順序付き* round-trip に demoted を含める。 ★demoted は `<pre><code>` を内包しうるため extractor の section block scan から mask して human-layer code 誤捕捉を防ぐ (machine_blocks は別途 capture ゆえ無損失)。
- **fork 時の rules 前提解除**: assemble/verify の `doc_type==rules` guard → `==spec`、 verify の round-trip 原本 `rules.html` → `verification.html`、 cover/band/footer ラベルを spec 文脈へ。 EARS 5-pattern / 非終端 照会 / 機械層 prose/note/list は rules と同型。 verification は human-layer code block を持たない (全 `<pre><code>` は demoted 内 = 機械層)。
- **floor 通過 = `CEILING=PENDING`** (taxonomy §5.1・floor 単独 GREEN 禁止)。 意味的 fidelity (機械層軸含む) は cell-3 admin が独立 ceiling (fidelity-spec / persona-walk-spec) を `/tmp` 生成物に回す。
- **敵対回帰** = `test-adversarial-verification.sh` (rules 版を verification anchor へ差し替え + verification 固有の demoted 改竄 F12 [text 改竄=round-trip] / M16 [block 脱落=件数+round-trip] を追加 = 62 ケース)。

```bash
.claude-plugin/scripts/extract-verification-spec.sh > contract/folio-verification.spec.yaml   # ← verification.html から DRAFT 機械抽出
./assemble-verification.sh contract/folio-verification.spec.yaml asm.html
./inject-prose.sh prose/folio-verification.prose.yaml asm.html filled.html                    # ← 同じ injector (無改変共用)
./verify-verification.sh --filled prose/folio-verification.prose.yaml contract/folio-verification.spec.yaml filled.html
./test-adversarial-verification.sh
```

## test-cases-pack = instance#6 (folio engine 段階2c / folio-uvt / 三段 trace + cross-doc 前方照会)

SRS/ADR/research/principle/spec/glossary generator の機構を **6 例目の doc-type (test-cases = テストケース仕様 = 「要件 → 受入基準 → テストケース」の三段 trace doc)** へ適用した六例目。 狙い = **★core (`lib/{common,verify-common,graph-common}.sh` + `inject-prose.sh`) を 1 バイトも変えず純粋 pack として挿さるか**を SRS-CLINIC-APPT 検証用 test-cases で実証する (instance#6 = engine が SRS 前方照会の受け手 doc-type を再現する rule-of-three の継続)。 挿さった証拠 = `git diff --stat lib/ inject-prose.sh` 空 + 既存 6 pack 非回帰 + sandbox 41/41 + validate clean。 ★ADR が SRS を後方照会したのと同型に、 test-cases は SRS の **要件 (FR・claim) + 受入基準 (AC・verification)** を *前方照会* する (片方向 cross-doc = test-cases→SRS)。

- **入力 contract** (`contract/clinic-appointment.testcases.yaml`) — test-cases-pack schema: meta(doc_type:test-cases) / approval / **cross_doc**(srs_contract/srs_doc_id/srs_title) / scope(in/out) / **test_cases[]**(id/title/kind/priority/precondition/steps[]/expected/**trace**{verifies[]=FR/confirms[]=AC}) / glossary。 ★三段 trace = 要件(FR・claim) → 受入(AC・verification) → test case。 各 FR/AC は cross_doc.srs_contract の `.requirements[].id` / `.acceptance[].id` に実在すること (fail-closed)。
- **決定的 assembler** (`assemble-testcases.sh`) — `lib/common.sh` (core) を source。 cover骨格/glossary/footer/band/esc/finalize/mark_terms は共用 (core)、 scope-summary-panel / testcase-card (前提・操作・期待結果 + trace chip) / RTM (要件→受入→テスト一覧) は test-cases 固有 emitter。 固有 CSS は srs.css token を流用。 ★cross-doc edge (data-trace-ref/data-trace-role) は card の trace chip にのみ emit (count anchor = card 側)、 RTM は可視 plain (attr 無し)。
  - ★**FR/AC 平易ラベル併記** (非エンジニア可読性・persona ceiling 是正): 裸 FR/AC コードは単体で読めないため、 SRS 由来の機能名/合格条件を `data-label-ref` 要素で *fabrication-free に決定的* 併記する。 FR → `requirements[].label` (機能名「空き確認」)・AC → `acceptance[].criterion` (合格条件) を照会先 `clinic-appointment.srs.yaml` から verbatim 写像 (`REF_LABEL` map・SRS contract は read-only 無編集ゆえ既存 SRS-pack byte-identity 維持)。 card trace 行 (tc-ref + tc-ref-label) / RTM (rtm-code + rtm-label) / cover ref-chip (FR コード列挙でなく機能名要約 join) の 3 箇所に展開。
  - ★生成前 fail-closed: id 重複 / 未知 kind(正常系/異常系/境界値)・priority(must/should) / **trace 片側欠落** (verifies/confirms 空) / 空 trace ref / **cross-doc 終端解決** (SRS contract 実在・srs_doc_id 一致・FR/AC が SRS に実在 = dangling 0) / glossary 部分文字列。
- **prose injector は SRS/ADR/research/principle/spec/glossary と無改変共用** (`inject-prose.sh`) — `data-slot-id` ベースで pack 非依存。 ★**6 例目でも無改変で挿さった = rule-of-three の継続実証**。 prose スロットは cover-summary + chapter-lead-NN (band 毎) + plain-TCx (ケース毎の「何を試すか」) のみ = 捏造面を最小化 (手順/trace は faithful contract data)。
- **floor** = `verify-testcases.sh [--filled <manifest> | --artifact] <contract> <html>` — 件数=contract導出 (testcase-card/rtm-row/prose スロット) / **cross-doc 照会** (core `verify_cross_doc_refs`: 照会先実在・doc_id・count anchor・key SET・dangling・空値ガード・role allowlist・(ref,role) ペア SET) / **cross-doc 可視 echo 厳密一致** (表紙 ref-chip `<b>`×2 = srs_doc_id + FR label join・各 card trace 見出し/照会先・tc-ref 可視==attr = marker-keyed + nested-same-tag reject) / **三段 trace RTM fidelity** (tc,kind,FR-codes,AC-codes を emission 順で pin・rtm-code 抽出) / **per-card trace pin** (各 card の (tc-id,FR/AC,role) 三つ組 = card 間 relocation 封鎖) / **★FR/AC ラベル fidelity** (全 data-label-ref 要素の (ref, 可視ラベル) が SRS 由来 = FR:requirements[].label / AC:acceptance[].criterion と集合一致・捏造/ref↔label swap/非SRS由来を封鎖・件数 tc-ref-label==rtm-label==|edges|) / 各 card 可視 fidelity (id/kind/priority/title/precondition/steps/expected を emission 順・term-inline バッジ除去で contract 突合 = 捏造手順を封鎖) / scope-summary-panel fidelity / core 共通 chrome (verify_core_chrome) / cover-meta 4 KV 再導出 / escape 健全 / prose スロット (3 mode) / term-inline 被覆。 ★floor 通過は `CEILING=PENDING` (taxonomy §5.1・floor 単独 GREEN 禁止)。
- **graph 写像** (`rolemap/testcases.rolemap.yaml`) — `roles.test_cases=verification` / `edges` (test_cases→SRS・direction=backward = ADR→SRS と同型・★`role_expr` は source intrinsic role token `verification` を |edges| 回 emit = floor pin `edge.role==roles[test_cases]` と整合) / `forbidden_roles=[exploration]`。 ★**本 cell の時点で `verify-graph.sh` (CI deterministic floor gate・ci.yml) に完全配線済み**: `verify-graph.sh` は `contract/*.yaml` を無条件 glob し `graph_pack_of` で pack=testcases を導出して同名 rolemap を発見・pass-1 floor pin を *常時* 課す (opt-in registry ではない) ため、 新設 rolemap が floor を通すこと自体が受入条件。 ★pass-2 reachability では SRS が principle 終端未到達ゆえ TC-CLINIC-APPT は孤立 advisory WARN (SRS-EC-CHECKOUT と同型・exit 0 不変)。 **principle 終端まで到達する graph 終端完備化は段階4 (folio-rqj) 領分**。 self-test に `folio verify-graph` FLOOR-OK assert を含め回帰を機械検出する。
- **敵対回帰** = `test-adversarial-testcases.sh` (37 ケース: baseline + 件数 [card/rtm-row 削除] + 可視 card [tc-id/title/kind ラベル/kind class/prio class/prio ラベル] + 捏造手順 [precondition/expected/step] + scope [in/out 項目 rewrite×2 / in 項目削除] + ★三段 trace [偽 FR 参照=dangling / role 意味偽装 claim→verification / trace ref 削除=count / tc-ref 可視 vs attr desync / RTM FR code 改竄 / ★card 間 FR 入替 (TC1↔TC8) / card 間 AC 入替 (TC4↔TC5)＝RTM 無改竄でも per-card pin が捕捉] + **★FR/AC ラベル併記 [card ラベル捏造(非SRS) / card ラベル swap(FR1↔FR2) / RTM ラベル捏造 / card ラベル削除=件数 / cover 機能名要約 部分捏造]** + cross-doc 可視 echo [ref-chip srs_doc_id/FR label join / tc-trace-h / tc-trace-tgt] + core chrome [cover-meta 件数 / approval who / term-inline] + prose [注入改竄 / 未充填] + GREEN 不在)。

```bash
./assemble-testcases.sh contract/clinic-appointment.testcases.yaml asm.html
./inject-prose.sh prose/clinic-appointment.testcases.prose.yaml asm.html filled.html   # ← SRS/ADR/… と同じ injector (無改変共用)
./verify-testcases.sh --filled prose/clinic-appointment.testcases.prose.yaml contract/clinic-appointment.testcases.yaml filled.html
./test-adversarial-testcases.sh
```

## cross-doc deep-link navigability + suite レイアウト規約 (folio-c5r.9 / rqj follow-up)

生成文書一式 (suite) の cross-doc 照会を **実際にクリックできる `<a href>`** にする層 (folio-lzz が target 側の navigable 裸 id を、 本 cell が referrer 側の href を配線)。 単一文書 walk が見ない suite 規模の navigability で、 純 pack 追加 (`lib/` + `inject-prose.sh` 無改変・arch 先例の 3 層を spine へ複製)。

- **suite レイアウト規約 = 全 doc root 平置き (Fork A)**。 全 referrer が **`<filename>.html#<anchor>` の素パス** (referrer 位置非依存の単一規約) を使う。 arch も root へ置き、 旧 `../` ハードコードは撤廃した (referrer 位置で path prefix が分岐する非対称を解消)。 これは生成物 (consumer artifact) の配置規約ゆえ HOW = 本 README が SSoT (folio spec には置かない・P-3/P-11)。
- **referrer 3 層 (arch 先例の複製)**: ① contract `cross_doc` に飛び先 `*_html` フィールド (例 `srs_html: clinic-appointment.srs.html`)。 ② assembler が `<a class="…" href="<*_html>#<anchor>" data-*-ref=…>` を決定的 emit。 anchor は folio-lzz の裸 id (`#FR2`/`#NFR1`/`#AC1`/`#decision`)。 ③ verify が (href, 兄弟 data-*-ref) ペアを contract 派生 href へ束ね set_eq + 件数で fail-closed (anchor swap / filename swap / 外部 host / href 欠落〔span 退行〕封鎖・arch gate 1h 同型)。
- **配線済 referrer**: testcases→SRS (tc-ref / RTM rtm-code = `#FR/#AC`)・ADR→SRS (justify-req = `#FR`)・research→ADR (leads-chip / 表紙 ref-chip / oc-resolved / oc-tgt = **coarse `#decision` 着地**・OPT 単位 anchor は別 follow-up)・arch→SRS/ADR (既存・Fork A で `../` 撤廃)。
- **敵対**: 各 pack の `test-adversarial-*.sh` に href anchor swap / filename swap (外部 host) / href 剥奪 を追加 (★href の `#` と perl `s#…#` デリミタ衝突を避け `{}`/`s{…}{…}` を使う)。

### cross-doc 照会ラベルの title live-mirror (folio-c5r.13)

照会チップが示す参照先 doc の **タイトルを参照先 contract の `.meta.title` から live 導出**し drift-proof 化する層 (c5r.9 が href を、 本 cell が *表示ラベル* を drift-proof 化)。 旧実装は referrer contract の手書き `cross_doc.*_title` (短縮要約) で、 (a) 参照先を改題すると silent に古くなり、 (b) referrer 間で不整合 (同じ ADR を指すのに別文字列・SRS ラベル 3 種) だった。

- **決定 (Option A・user walk)** = 照会ラベルを **`KIND: <参照先 .meta.title>`** 形式に統一 (`ADR: …` / `SRS: …`)。 種別ラベル (ADR/SRS) は assembler 内の静的定数、 title は **参照先 contract の `.meta.title` から live 導出** (arch の `SRS_LABEL[]` mirror と同方式・`validate` 後ゆえ参照先実在は保証済)。 手書き `cross_doc.*_title` は contract から廃止。
- **drift-proof の機序**: build 時に毎回 mirror するため referrer と参照先は常に一致 (両者同時に動く)。 参照先を改題して referrer を再ビルドしないと **stale チップ (= drift)** になるが、 verify が「チップ可視 title == `KIND: ` + 参照先 `.meta.title`」を fail-closed 突合し捕捉する (手書き要約は機械検証不能ゆえ drift-proof には表示を実 title へ寄せるのが必須)。
- **配線済 referrer**: research→ADR (reader-chip / oc-tgt)・testcases→SRS (tc-trace-tgt)・ADR→SRS (justify-tgt)・arch→ADR (decision の `data-adr-label-ref`)。 各 verify は参照先 `*_ABS` を解決し `KIND: <yq .meta.title>` を期待値に。
- **敵対**: 各 pack に照会ラベル title 捏造 (live-mirror 等値で FAIL = retitle drift 検出) を追加 (research/testcases/adr・arch は既存 mut19)。
- ★既知の軽微点: doc_id (例 `ADR-CLINIC-0001`) が既に種別を示すため `ADR: ` 接頭辞は doc_id と軽く重複する (Option B = title のみ への切替は assembler の `KIND: ` 接頭と verify 期待値の 1 箇所変更で可)。

## 照会 graph 終端完備検証 (engine B5-I / folio-p4o)

個々の pack verify (verify-adr/research/principle) は **1 doc の局所** 照会 (justifies/leads_to/inbound) を検証する。
B5-I は **corpus 全体の照会 graph** を見て「全チェーンが principle 終端へ到達するか」を検証する (engine doc §10③④⑦)。
per-pack verify が建物の各部屋の配線を見るのに対し、 こちらは建物全体の到達可能性を見る。

- **rolemap (pack 側 SSoT)** — `rolemap/<pack>.rolemap.yaml` (srs/adr/research/principle)。 engine doc §3 の抽象ロール表
  (claim/rationale/exploration/verification/principle/implementation) へ各 pack の具体 node-type を写像する。
  `roles` (node intrinsic role) / `edges` (前方 cross-doc 照会 = from_node/role_expr/target_docid_expr/direction) /
  `terminal` (照会終端 node の id_expr) / `external` (contract外 folio-self 照会・meta=来歴) / `forbidden_roles` (例: SRS は exploration 不在)。
- **core リーダー (additive)** — `lib/graph-common.sh` (既存 core 関数は byte-identity 非回帰・新規ファイル)。
  `graph_pack_of` (filename→pack) / `rolemap_role_for` (roles[node-type]・fail-closed) / `rolemap_roles_invalid` (allowlist sanity) /
  `GRAPH_ROLE_ALLOWLIST` (verify-common の `CROSS_DOC_ROLE_ALLOWLIST` と語彙一致・`graph_role_vocab_consistent` で機械照合)。
  graph traversal 自体は core に持ち込まず独立 script に置く (§10④)。 reader は doc-type 非依存ゆえ B6 (folio 自身の横断 graph) へ転用可。
- **独立 script** — `verify-graph.sh [--contract-dir <dir>] [--rolemap-dir <dir>]`。 既存 core 不変。 2 段:
  - **(1) rolemap floor (scope=各 contract)** — `edge.role == rolemap[node.type]` を pin (co-author + enforce)。
    rolemap 宣言 ∩ corpus edge の **二重担保** = どちら側の改竄も捕捉する。 SRS の exploration 不在は `forbidden_roles` を
    corpus scan で実証 (rolemap 宣言 ∩ corpus 不在)。 rolemap roles ⊆ 抽象 allowlist の sanity も。 **違反 = hard FAIL**。
    **edges 武装解除ガード** — pin は `rolemap.edges` の宣言を起点に駆動する (necnt=0 ならループ 0 回 = corpus edge 無検査)。
    edge を本来持つ pack (adr=backward / research=forward) で edges を空に/削除すると pin が無言で解除されるため、
    **edge-less pack の allowlist (`srs`/`principle`) 以外は edges を 1 件以上宣言** することを期待値駆動で hard FAIL に固定する
    (G2 が roles[] 値改竄を捕捉するのに対し、 本ガードは edges 宣言除去 = 構造的 floor 解除を捕捉)。
    **vacuum ガード** — `rolemap.edges` を残したまま `role_expr`/`count_expr` を *協調的に* 存在しない path へ書き換えると
    `declared_cnt=0`/`|eroles|=0` で件数が一致し pin が 0 回照合になる (edges 武装解除の兄弟ベクタ)。 照会先 doc_id
    (`target_docid_expr`) は別 expr ゆえ vacuum の巻き添えにならず有効に残るため、 **「有効照会先 ⟹ `declared_cnt` 正整数」**
    を pin して expr vacuum (cexpr 自体の null 化も含む) を捕捉する。
  - **(2) graph reachability (global)** — contract glob → edge union → principle 終端への到達可能性を
    `{終端完備 / 孤立=warn / external-ref=warn}` に展開。 **終端は domain-local principle を許容** (ADR inline `principle:` を
    graph node に昇格 = constitution に不在でも終端)。 **逆方向** (ADR→SRS の justifies) は reachability では SRS→ADR と辿り
    局所の要件 ID 実在は既存 verify-adr が担う (§10④「逆方向=局所」)。 **amended_by は来歴 meta-edge ゆえ reachability から除外**。
    **dangling (graph 不在 node 先) = hard FAIL**。 **孤立 (例: ADR-less な EC SRS) / external-ref (inbound.from・amended_by.adr の
    folio-self 先) = warn** (exit 0・advisory)。 graph 構造は有限ゆえ floor が例外的に exhaustive (§10.1)。
- **graph ceiling** = 照会 note / role の **真正性** は意味判定ゆえ **既存 fidelity-* lens** (fidelity-adr/research/principle) の射程。
  新 agent は不要 (§10⑦)。 CI gate (floor∧ceiling) 統合は **B5-III (folio-hi6)** が担う。

```bash
./verify-graph.sh                                            # 既定 corpus (contract/ + rolemap/) を検証
./verify-graph.sh --contract-dir /tmp/x/contract --rolemap-dir /tmp/x/rolemap   # 別 corpus を指定 (tamper test 等)
```

## cross-doc content 重複検出 lint (folio-c5r.1 / yzv 決定④)

verify-graph が「照会 graph が終端まで繋がるか (構造)」を見るのに対し、 これは「別 doc-type が **同じ内容を字句重複**していないか (内容)」を suite 内で機械検出し、 **doc-type 要否の判断材料を可視化する** advisory lint。 canonical デモ (folio-c5r.2) = clinic に constitution を *あえて* ゼロ生成すると、 その principle が SRS goals を restate した字句重複が検出され、 人間が「この project に constitution は不要」と判断する流れを実証する。

**★哲学 (yzv 決定④・不可侵)**: engine = 確実な生成器 + 機械的検出 (floor・冪等)。 判断 (doc-type 要否) は engine に作り込まず人間 (事後・ceiling)。 lint は判断材料を可視化するだけで判断しない。 **検出 clean は「字句重複が見つからなかった」であって doc-type が適切である証明ではない** (engine「floor 緑 ≠ 完成」を doc-type 要否判断へ適用)。 「判断する engine」は folio の冪等性・確実性を壊す。

- **独立 script** — `verify-cross-doc-dup.sh [--contract-dir <dir>] [--rolemap-dir <dir>] [--strict] [--show-declared]`。 verify-graph と同じ suite-level 層・既存 core 不変 (additive)。 `lib/graph-common.sh` の `graph_pack_of` のみ再利用。 `folio verify-cross-doc-dup` で CLI からも。
- **機構 3 段**:
  - **(1) content-leaf 抽出** — 各 contract から pack 別 `CONTENT_LEAVES` map (script 内連想配列) の field を `(suite-prefix, doc_id, pack, label, text)` レコード化。 比較対象は **contract YAML の content-leaf 散文** (生成 HTML でなく SSoT 直比較・chrome/term-inline バッジのノイズを回避)。 **除外** (precision の核) = glossary def (全 pack に SSoT コピーで複製=全一致)・`cross_doc.*` chrome・共有終端 `principle.text` (PRIN-SAFETY-FIRST)・NFR 数値密 field。 これらは map に **不掲載**にするだけで除外される。
  - **(2) 類似採点** — 同一 **suite prefix** (instance 名 `<instance>.<pack>.yaml` の最初の `-` 区切り = clinic / ec / folio) 内で doc_id が異なる全レコードペアを **文字 4-gram shingle の Jaccard(J)** で採点。 J は長さ正規化済で「2 文書がどれだけ同一か」を測り内容重複の信号になる。 perl `-CSD` で UTF-8 char 単位 (byte 4-gram は破綻・`LC_ALL=C` 集合演算との衝突を回避= folio-wqh と同型の idiom)。 正規化は決定的パイプライン (隅付き/全角括弧除去 → 空白 collapse → 数字非隣接スペース除去 → 句読点保持)。 **別 suite (別プロジェクト) は比較しない** (boilerplate 共有は重複でない)。 ★suite = instance 名の第 1 `-` segment という前提ゆえ、 同一 project の doc は同じ prefix を共有する命名が要る (例 `clinic-*`)。 prefix がずれると同一 suite が未比較化し demo が無言不発しうる・別 project の prefix 衝突で誤比較しうる (→ `meta.suite` タグ化は follow-up)。
  - **(3) graph 認識 (declared/undeclared 分類)** — rolemap edge の `target_docid_expr` から **declared 無向 doc-pair 集合**を構築する (★verify-graph.sh と **同一の edge 定義**を再利用しドリフトを防ぐ・`cross_doc.*` の heuristic 再パースをしない)。 字句重複ペアが declared なら「設計意図の引継ぎ」= informational (非フラグ)、 undeclared なら actionable WARN。 ゼロ生成 constitution は **suite の他文書と cross_doc edge で繋がっていない** (誰も参照しない=inbound なし・自身も前方照会なし=outbound なし) → どの declared ペアにも入らない → undeclared → 検出される (demo 成立)。 ★これは「principle pack だから」ではない (folio の実 constitution は rules 等から inbound edge を受け declared に入る)。 真因は **ゼロ生成された孤立 doc が誰にも参照されない**こと。 declared 分類は「正当 echo (research↔ADR の approach=option は J≈1.0) が真の言い換え重複より字句スコアが高い」という J 単体では分離不能な問題への解でもある。 ★**declared マスクは doc-pair 粒度**ゆえ、 edge が説明しない内容の逐語重複も一律抑制される (高 J の declared echo は `--show-declared` で人間 review 推奨)。
- **★閾値** — WARN = `J >= 0.40`、 HIGH = `J >= 0.65`。 `--warn-j` / `--high-j` で override 可。 **C(containment) は WARN 判定に使わず文脈併記のみ** — 長文 spec 同士は共通語彙だけで C が高く出て「内容重複」と「語彙重複」を分離できないため (= brief 段階の C 主導案を実測で棄却)。
  - **★閾値の限界 (honest)** — 現 corpus の undeclared 最大 J ≈ **0.274** (TC-CLINIC title ⇔ ARCH decision の正当な話題重複)。 WARN_J=0.40 はその上に置き誤検出 0 だが margin は ≈0.13 と薄い。 ★重要: **near-verbatim な restatement のみ J>=0.4 に達する**。 意味を保ったまま語を入れ替えた restatement の多くは J≈0.23-0.27 で **clean ノイズ帯 (〜0.274) に沈み J 閾値では分離不能** (閾値を下げると正当な話題重複を誤検出する)。 ゆえに本 lint が確実に拾うのは「ほぼ逐語の手抜き restate」で、 巧妙な restate は **人間 ceiling が backstop** (検出 clean ≠ 重複なしの証明)。
  - **★「誤検出 0」の射程** — 上記は **各 suite が SRS 1 本ずつの現 corpus 由来の限定実測**。 同一 suite に複数 SRS があり定型 EARS condition 等を共有すると undeclared WARN を生じうる (= 真の重複として正しく出るが、 boilerplate なら人間が無視判断する=哲学どおり)。
- **★設計境界 (limitation・honest)** — 検出条件は **`J(4-gram Jaccard) >= 0.40`** の一点。 ここから外れる重複は構造上見逃す: (a) 語を入れ替えた意味的 paraphrase (J≈0)、 (b) 意味を保った中程度 restatement (J≈0.25 で noise 帯に沈む)、 (c) 短い原則文の一部を逐語コピーしただけ (高 C だが J<0.40)。 つまり「字句が連続一致するか」でなく **J 尺度で線が引かれている**。 意味レベルの重複/要否判断は人間 ceiling が backstop (= engine 哲学「検出機構も bounded・floor 緑 = 検査できた範囲が緑」の lint 内再帰)。 これは bug でなく設計境界ゆえ出力 NOTE + header に明文化する。
- **出力と exit-code** — 既定 advisory: undeclared 重複の有無に関わらず **exit 0** (verdict にしない・`CEILING=HUMAN-JUDGMENT` 行を必ず出す)。 `--strict` 時のみ undeclared HIGH が 1 件以上で exit 1 (ローカル gate 向け・CI 非配線)。 起動エラー (引数不正/yq・perl 欠落/lib source 失敗) = exit 2 (false-green に倒さない)。 出力順は doc_id→label で決定的。
- **新 doc-type 追加時** — `CONTENT_LEAVES` map を更新する。 **未登録 pack は fail-loud WARN** (silent false-negative 源ゆえ map 更新を強制)。
- **敵対回帰** = `test-adversarial-cross-doc-dup.sh` (13 ケース): recall (憲章が SRS goal を verbatim/reworded restate → 検出)・precision (original principle / glossary def コピー / declared echo / 別 suite boilerplate → 誤検出しない)・exit-code (--strict + HIGH=1 / clean=0 / 既定 advisory は HIGH でも 0)・F10 未登録 pack 警告・起動エラー。 ★lint は advisory ゆえ判定は exit-code でなく **出力 substring** で行う。

```bash
./verify-cross-doc-dup.sh                       # 既定 corpus を検出 (advisory・exit 0)
./verify-cross-doc-dup.sh --show-declared        # declared echo (graph で説明済) も列挙
./verify-cross-doc-dup.sh --strict               # undeclared HIGH があれば exit 1 (ローカル gate)
folio verify-cross-doc-dup --contract-dir /tmp/x/contract --rolemap-dir /tmp/x/rolemap   # 別 suite を検出
```

## engine core 抽出 (B2 / folio-5ua / rule-of-three)

SRS-pack (instance#1) ∩ ADR-pack (instance#2) の共通項を **共有ライブラリ層 `lib/`** へ引き上げた非破壊リファクタ
(`architecture/research/document-discipline-engine-design.html` §7 の経験的地図に接地)。 core / pack 境界の基準 =
「その機構を新 doc-type に持ち込んで改変が要るか」 — 改変ゼロ = core、 doc-type 固有 = pack。

- **`lib/common.sh`** (assemble 共通層) — `assemble-srs.sh` / `assemble-adr.sh` が source する core idiom:
  `q` / `esc` / `mark_terms` (+`core_init_term_inline`) / `ico`+共用 icon / `band`/`band_end` /
  `core_validate_strings`・`core_validate_glossary_substring` (普遍規律) / `core_emit_cover_head`・`core_emit_approval_block`・`core_emit_cover_tail` /
  `emit_glossary` / `core_emit_footer` (tags は pack 引数) / `core_finalize`。
- **`lib/verify-common.sh`** (verify 共通層 = fabrication-free 規律ヘルパ) — `verify-fabrication-free.sh` / `verify-adr.sh` /
  `verify-srs.sh` / `verify-research.sh` が source: `q` / `esc` / `chk`・`chk_empty`・`set_eq` (整列幅は `CHKW`) / `make_body` (style 除去 body-only) /
  `verify_term_inline` (term-inline fidelity+被覆。 markable フィールドは pack 引数) /
  **`verify_cross_doc_refs`** (cross-doc 照会解決スケルトン = ADR-pack ∩ research-pack。 ds8 で core 昇格。 下の「ds8」節)。
- **pack 固有 (各 assembler / verify に残す)**: contract schema・section emitter (req-table / option-card / decision-panel 等)・
  RTM 集合・**cross-doc の可視 echo 厳密一致** (ADR ref-chip/justify-tgt/justify-req・research チップ/oc-echo・within-doc 順序・cover-meta)・
  ADR verdict 整合・supersession/principle・gate A-H 詳細。 ★cross-doc 解決の *スケルトン* は core / *可視 echo の厳密一致* は pack。
- **inject-prose.sh は無改変共用** = doc-type 非依存の core (data-slot-id ベース)。 ★この共通化が rule-of-three の
  「SRS-pack ∩ ADR-pack = core」を炙る一次証拠 (§7)。 抽出は非破壊 = 生成 artifact byte 不変・verify 挙動不変・既存 contract schema 不変。

## ds8: cross-doc verify helper の core 昇格 + research 堅牢化の ADR/SRS 横展開

rule-of-three for the helper の決着 + B3 で research が 5 round かけて獲得した fail-open 封鎖の横展開。

- **core 昇格 (`verify_cross_doc_refs`)**: B3 まで verify-adr.sh §3 と verify-research.sh §3 に *同型の cross-doc 解決
  ブロックが重複* (forward cross-doc を持つ ADR/research の 2 pack で同型・SRS は照会の終端ゆえ非該当 = 2 instance からの抽出)。
  doc-type 非依存の **スケルトン 8 検査** (照会先 contract 実在 / doc_id 一致 /
  count anchor / SET 一致 / dangling / **空値ガード** / role allowlist / (key,role) ペア SET 一致) を
  `lib/verify-common.sh` へ 1 本化。 両 pack は named-flag で yq 式を *逐語* 渡す (合成しない = 非破壊の証明を直截に保つ)。
  抽象ロール allowlist は両 pack 文字列完全一致 = core 定数 `CROSS_DOC_ROLE_ALLOWLIST`。
- **★空値ガードの横展開 (= ds8 の核)**: `comm -23` は空行を空 missing に畳むため dangling 判定が空文字列キーを素通す
  fail-open (research round-5 ceiling 発見)。 helper に組み込んで **両 pack へ無料配布**。 ADR は従来この穴を欠いていた
  (verify 側) のを塞いだ。 **assemble-adr.sh validate にも同型の空 req ガード**を追加 (empty-value バグ = 空 req でも
  HTML を生成しうる実バグの修正・生成前 fail-closed)。
- **★可視 echo 厳密一致の ADR 横展開 (Part 2b)**: research の round-2/4 ceiling 結晶 (全 `<b>` 列挙 + 全タグ除去後の
  可視テキスト == 固定テンプレ) を ADR の **4 可視 echo** へ適用 — 表紙 ref-chip (`<b>` ちょうど 2 本 = srs_doc_id, join(req,・)) /
  jh 見出し (`<b>` 無し平文の「正当化する要件 (cross-doc 照会 → srs_doc_id)」) / justify-tgt (`<b>` 無し平文の照会先) /
  justify-row (可視 req == data-justifies-req の attr-vs-visible)。 各ブロックは count anchor で個数も固定。
- **★ds8 ceiling round-1 (admin 独立検証で発見・修正した 4 major fail-open)**:
  - **jh 見出しの列挙漏れ**: Part 2b が当初 ref-chip/justify-tgt/justify-req の 3 echo だけを列挙し jh (第4の可視 cross-doc echo) を
    見落としていた = 機械的完全性照合 (全可視 echo の enumeration) の漏れ。 jh の厳密一致 + count anchor を追加した。
  - **wrapper-tag swap (marker-keyed parity)**: 可視 echo の while-regex が tag 固定 (`<div>`/`<p>`) で count anchor は marker-only =
    selector 非パリティのため、 `<div>→<span>` swap で while がスキップし可視検査を逃れる fail-open があった (ADR・research 両方に潜在)。
    while を **marker-keyed** にして marker-only count とパリティを取った。
  - **gate H の緩い照合**: verify-srs gate H が決定的 2 フィールド (機械SSoT / 検証状態) を「非空のみ」で照合 = 偽 provenance が floor を素通る fail-open。 厳密一致へ。
- **★ds8 ceiling round-2 (round-1 修正自身の兄弟欠陥を再帰検出 = B3「admin は自分の gate 修正を self-certify しない」の実証)**:
  - **nested-same-tag early-match (blocker)**: marker-keyed の `(.*?)</\1>` は非貪欲ゆえ echo 内に空 `<div></div>` を入れ子注入すると内側 close で
    *早期終端* し、 捕捉群はテンプレ厳密一致のまま *捕捉群の外* へ偽 provenance を可視追記できた (全 6 echo を貫く fail-open)。 → 捕捉内容に同名 open タグ
    `<$tag` があれば即 FAIL する **nested-same-tag reject** を全 echo に追加。 B3 の「可視テキスト厳密一致=不動点」が残していた最深の兄弟。
  - **hyphen-tag 取りこぼし (blocker)**: `<(\w+)>` は `<my-tag>` を捕捉せず while がスキップ。 → `<([A-Za-z][\w-]*)>` (HTML 要素名規約) へ広げ count とパリティ。
  - **gate H `</b>` 外平文 (major)**: 値のみ照合だと `</b>` 後・`</div>` 前への可視追記 (偽『全 gate GREEN・出荷承認』) が死角。 → sync-meta div を
    **block-scoped** で全可視テキスト厳密一致 (timestamp のみ placeholder) に昇格。
  - **identity echo の列挙漏れ (major)**: dec-kick (`採用 — chosen`) が未検証・supersession/principle が tag固定 grep で duplicate-decoy に弱かった。
    → dec-kick を marker-keyed 厳密一致・prin-id/ss-row に count anchor。
  - **★two-gate 境界の明確化 (overclaim 是正)**: floor が封じるのは *決定的 echo 要素自体* の改竄 (swap/別タグ/第2<b>/平文・タグ併記/nested 早期終端/削除・重複)。
    echo の *外側* の自由文へ偽 provenance を注入する経路 (marker 無し sibling・自由文中の偽 doc_id 言及) は **prose の正当な doc_id 言及 (例 別 ADR ADR-0041) と
    構造的に区別不能**ゆえ floor で追うと正当 prose を誤 FAIL する = 内容 fidelity ゆえ **ceiling 領域** (fidelity-research / persona-walk)。 round-1 の「一括封鎖」は
    overclaim ゆえ撤回し、 floor は「決定的構造の改竄検出」へ範囲を honest に限定した。
- **SRS 監査 (gate H 是正後)**: SRS-pack は前方 cross-doc を持たない (照会の終端)。 監査した fail-open クラスのうち comm 空値畳み込み
  (backward/acceptance は `set_eq` + count anchor で塞がれ comm は診断のみ) と sample-not-enumeration (`head -1` 依存なし・全 gate は
  count か `/g` 列挙) は **不在** (ceiling が独立に支持)。 gate H の決定的2項目の緩照合のみ実在し ds8 で厳密化した。 自由文内容 fidelity は
  ceiling 領域ゆえ floor で追わない (two-gate 境界厳守)。
- **★ds8 ceiling round-3 (ADR identity echo の parity gap = research にある検査が ADR に無い pre-existing B1 gap)**: round-3 reenumeration が、
  research が within-doc (k') / cover-meta (l') で突合する identity echo を ADR が皆無検証だった parity gap を 3 件検出 →
  (a) 可視 **cxid/drid** 列を `.context[].id`/`.drivers[].id` と順序付き突合 (可視 id 改竄 CTX1→CTX-PHANTOM を封鎖)、
  (b) 表紙 **cover-meta** 4 KV (状態/選択肢/結果/版) を決定的再導出突合 (research (l') と対称)。 opt-name は mark_terms で nested ゆえ対象外。
  ★これは「機械的完全性照合 = assembler の全可視 echo を *列挙* し各々 verify 突合」を ADR-pack 全体へ及ぼした結果 (cross-doc に限らず identity echo も)。
- **★ds8 ceiling round-4 (cross-doc edge の parity 漏れ是正 + SRS floor 完全性の繰延)**:
  - **justify-role 可視==attr (修正済)**: round-2 で可視 req==attr は強制したが role の可視を漏らし allowlist 内 role の可視 swap (claim→rationale・attr は正) が
    素通っていた = cross-doc edge の可視 fidelity parity 漏れ。 → 可視 justify-role 列を `.decision.justifies[].role` と順序突合で封鎖。
  - **★SRS generator の within-doc 決定的フィールド値 floor 完全性 = 専用 follow-up へ繰延 (この ds8 のスコープ外)**: round-4 reenumeration が、 SRS の
    acceptance metric_v/metric_l (合否しきい値)・nfr-hero (cat/big/unit/qual)・goals.headline・actor.name・upper_needs.origin・data-source・ADR drg 等の
    *決定的 (esc 済) 可視フィールド値* が count のみ検証で値改竄が素通る fail-open 群を検出した。 これらは決定的ゆえ floor 検証可能だが、 **SRS 本体 floor の包括的
    フィールド再構築 = pre-existing B0/S4 generator の別 epic** であり ds8 (cross-doc helper + 識別子 echo 横展開) のスコープ外。 fidelity ceiling (agents/fidelity-srs
    = gate J) が独立に内容忠実性を backstop する。 → **専用 follow-up epic に切り出し** (識別子/集約 echo は floor・自由文 content は ceiling という two-gate 境界の、
    フィールド値レベルでの線引きを follow-up で設計する)。
- **非破壊**: 生成 artifact 全 8 種 byte 不変 (footer timestamp 除く・assemble は無改変ゆえ verify 側のみの変更)・昇格でスケルトン非弱化。
  敵対は 4 ラウンドで拡張: **ADR 28→43→48→51→52** (round-1: cross-doc 平文/タグ併記・swap・削除・attr-vs-visible。 round-2: nested-tag early-match /
  hyphen-tag swap / dec-kick / prin-id dup-decoy。 round-3: cover-meta / cxid / drid。 round-4: justify-role 可視==attr)・**research 49→52→54** (wrapper-tag swap +
  nested-tag / hyphen-tag)・**SRS 40→42→43→44** (偽 機械SSoT / 偽 検証状態 / `</b>` 外平文追記 block-scoped / cover-meta 再導出)。 全 fixture verify PASS・validate clean・sandbox 37/37。

## dty: SRS *本体 (body)* の within-doc 決定的フィールド値 完全性 (folio-dty / ds8 round-4 繰延の回収)

ds8 round-4 が繰延した「決定的可視フィールド値が *件数のみ* 検証で値改竄が素通る fail-open 群」を floor 化する。 設計判断は
**決定的値こそ floor (機械検証=決定的・強) で守る** (北極星 = perfect documents・ADR/research が within-doc id を floor 突合済ゆえ SRS 本体も parity)。

- **`verify-fabrication-free.sh` §7e (round-1)**: 順序付き再構築突合 (cxid/drid/cover-meta と同型)。
  goals(id/headline)・actors(key/name+外部バッジ)・upper_needs(id,origin)・rtm 列見出し(id+short)・acceptance(aid=id←links / metric_v/metric_l 合否しきい値)・
  nfr-hero(cat/big/unit/qual 表紙数値)・data-source(=rationale_source 接地メタ・非可視 attr ゆえ集合突合)。
- **`verify-fabrication-free.sh` §7f (round-2 = ★独立 ceiling 完全列挙の反映)**: round-1 は *部分列挙* で、独立 ceiling (wf_5d54fb6b) が
  9 種の fail-open を実弾で看破した (`test-adversarial` 55/55 green は fixture-disjoint の見かけ green だった)。 §7f が row-scope 抽出 + 順序突合で全て塞ぐ:
  - ★**blocker**: 要件 ID 本体 (可視 fid + data-req-id) を contract id と三者一致突合 (consistent rename FR1→FR99 が §7e floor も verify-srs gate D も貫通していた)。
  - 要件行の EARS 種別 (class+可視ラベル)・priority (class+ラベル)・vmethod を 1 タプルで row-scope 突合 (vmeth/prio/ears は legend と class 共有ゆえ ears-requirement-row 内に scope 必須)。
  - nfr 表の nid/category (§7e の source-trace nid と非対称だった穴)・rtm 行ラベル (lbl)・constraint id/label/規制バッジ法令名・actor tint。
- **`verify-adr.sh` (parity)**: drg (driver grounds 可視バッジ) を `.drivers[].grounds` と順序突合 (round-4 minor・drid と同型)。
- **抽出の分類 (ds8 round-4 不動点の適用)**: plain leaf (esc 済 `[^<]*`・nested 不能) = `grep+sed` 順序突合 (wrapper-tag swap は値が抽出列から
  脱落し順序不一致で FAIL・escape 済ゆえ nested-same-tag 早期終端は起こりえない)。 compound (固定 nested = 外部バッジ/u span/metric v·l) や複数フィールドの row = structured-regex
  順序突合。 **marker-keyed+nested-reject の重機構は echo block (テンプレ prose 含む) 専用ゆえ決定的フィールド値には用いない** (過剰 = 偽 FAIL 源)。
  順序リストの厳密一致 (`chk`) は値・順序・件数を同時に被覆する。 EARS_CLASS/EARS_LABEL/PRIO_LABEL は assemble-srs と二重保守 (detect↔remediate parity)。
- **`verify-fabrication-free.sh` §7f marker 占有数パリティ (round-3/4 = ★round-2/3 ceiling 反映)**: round-2 ceiling (wf_997ee765) が §7f(h) の
  非貪欲 `.*?` タプル regex の **decoy 注入** (resp セルへ第2の prio/vmeth 対を入れると末尾の正規対を拾い可視虚偽を素通す) と **fid/nid の件数パリティ欠落**
  (自由文セルへ ghost ID バッジを注入すると素通す) を、 さらに round-3 ceiling (wf_97d52cb2) が **count anchor 自身の兄弟欠陥** を実弾で看破した。
  ds8 不動点 *marker-only count parity* で封鎖し、 round-3〜5 ceiling 反映で **HTML 属性構文 robustness の不動点** へ到達: (a) ★**core `count_attr_token`** =
  属性名・値トークンとも **case 非依存** + **quote 構文非依存** (`"..."`/`'...'`/unquoted/multi-class) + **数値文字参照 decode** (`&#102;id`→fid)。 assembler は小文字 ASCII class のみ
  emit ゆえ single/大文字/entity/multi-class class は全て tamper だが素朴な `grep 'class="fid"'` を素通る → 属性値を空白分割しトークンを lc 完全一致で数える。
  (b) ★**統制値は可視 styling class token** (`.prio/.ears/.vmeth`) を **global ∧ 要件行内 ∧ legend-scope** の三項で binding (class-prio-only ghost / chrome relocation / legend 削除+add の各死角を相互補完)。
  (c) ★**value-internal class の count-parity** (ct/cid/av/nm/grp/lbl/cl/cid2/reg-badge/aid/metric/cat/qual/big/u/origin/k/v/tgt/l/RTM dot は joint-token) — 小文字 grep の
  ordered 値突合は単体では `class="CT"` で偽要素を脱落させ同値 decoy で列保存する case-drop+decoy を素通すため、 占有数パリティを *併設* し偽要素の add を封鎖 (二層)。
  (d) **rtm 行見出し id** (`<tr><th>` は class-less ゆえ `/gi` で偽行を抽出列へ)・**受入ドット可視** (marker-keyed nested-reject = `<b>AC999</b>` ネストでの脱落を封じる)。
  (e) ★**class-token 機械的網羅** (round-6 ceiling 根本 fix): body の全 class token は COUNTED (占有数パリティ済) か EXEMPT (構造/modifier/繰延 prose·chrome) に *機械分類* されねばならず、
  未分類トークン (将来の value class 追加 = vcount allowlist drift) を必ず FAIL し count-parity 追加を強制する = 6 round 通底の partial-enumeration を構造封鎖。 ★occurrence は token 単位。
- **`verify-fabrication-free.sh` round-9 (= ★round-8 ceiling wf_a2a3db7c の反映)**: R8 が dot/novel で達成した「quote-robust helper を *全箇所* 再利用」の不動点を
  **未適用だった兄弟 3 種**を塞ぐ (R8 自身が新規追加した chk が double-quote 固定 inline perl で穴を再導入していた = admin が自分の gate 修正を self-certify しない実例):
  - ★**blocker** rtm-summary 可視 5 数値: R8 の値突合 chk が `<p class="rtm-summary-derived"` で double-quote 固定 + `rtm-summary-derived` を **EXEMPT に残した** (占有数パリティ無し) ため、
    real を無傷に残し `<p class='rtm-summary-derived'>孤立要件 999件</p>` を併置する single-quote decoy が網羅検査も値突合も素通した → **COUNTED へ移し count_attr_token 占有数 == 1** を強制 + 値抽出を 3 分岐 quote-robust 化。
  - 受入ドット可視 id: acc_vis_bad と §5/§6 link 集合が `data-acc-link="..."` で double-quote 固定 → single-quote decoy で可視 id (AC1→AC999) を捏造できた → **core `attr_values`** (count_attr_token の値版・quote-robust) へ載せ替え + acc_vis_bad の data-acc-link を 3 分岐 parse 化。
  - 凡例 chip 可視ラベル: legend-scope が占有数 (2/4/4) のみ縛りラベルテキスト未突合 → きっかけ↔禁止 swap 等が素通した → **(class,label) SET 値突合**を追加 (ears/prio は DTY_*_LABEL から再導出・detect↔remediate parity)。
- **core**: `lib/verify-common.sh` に `qesc` (yq 式の各行を esc して出力する複数行 esc) + `attr_values` (属性値を quote 構文・属性名 case・数値文字参照 非依存に列挙・count_attr_token の値版) を追加 (純追加・両 pack 共用)。
- **★scope 境界 (no silent caps・round-2 ceiling で honest 後退)**: dty は SRS 本体の **識別子・構造・数値・統制値** フィールド (id/fid/data-req-id/EARS/priority/
  vmethod/nid/category/metric/cid2/label/regulation/rtm 見出し+行ラベル/tint/origin/headline/key/name) を順序突合 + marker 占有数パリティで完全列挙・突合する。
  body prose テキスト値は **folio-4cf (§7g) で回収済** (下記)。 残る scope 外 *明示繰延* は:
  - **core 共通 chrome** (cover-head eyebrow/title/subtitle/reader・approval role/who/when/stamp・glossary-term-table term/en/def) — lib/common.sh が全 pack 同一構造で emit
    (ADR/research も同じ count-only gap) ゆえ `verify_core_chrome` 昇格の cross-pack follow-up **bd folio-mk9**。 凡例 en/lt は folio-czo (§7f) で被覆済・glossary 表の en は folio-mk9。
  (ds8 教訓#4: gate funnel が掘り当てた broad pre-existing gap を bolt-on せず追跡 follow-up へ。 識別子/構造/本文 prose は floor・gate J=content fidelity ceiling)。
- **非破壊**: assemble/inject/css 無改変 → 生成 artifact byte-identical (floor 強化は verify 側のみ)。 敵対 **SRS 44→55→66→69→96→102→118** (… + round-9 A88-A93 +
  **folio-4cf/czo A94-A109** [body prose 10 フィールド改竄・scope bullet 無し偽 li・cond single-quote decoy 占有数パリティ・凡例 en/lt ラベル改竄+en 位置 swap・ears.response slot 後ろ text-node 追記])・**ADR 52→53** (A51: drg)。
  全 fixture (EC + clinic) verify PASS (default/--filled/--artifact)・validate clean・sandbox 37/37。

### folio-4cf: SRS body prose テキスト値の floor 突合 (dty round-2 ceiling wf_997ee765 繰延の回収)

dty が「本文 prose ゆえ別カテゴリ」と明示繰延した mark_terms 系自由文フィールドを floor 化する。 全て決定的 (esc + mark_terms) ゆえ
floor 検証可能 — gate J (content fidelity ceiling) の暫定 backstop に依存せず機械で守る (識別子/構造と同じ強度)。

- **`verify-fabrication-free.sh` §7g**: term-inline バッジ (内容は `verify_term_inline` §9 が別途検証) を *legit double-quote 形のみ* strip した
  working body を作り、 各セルの可視テキストを抽出 → `esc(contract値)` と **順序突合** する (mark_terms の語境界ロジックは複製せず plain-text 等価比較)。
  バッジ strip 後は body prose 値に生 `<` が無い (esc 済) ゆえ全セルが `[^<]*` で取れる。 対象 10 フィールド:
  goals.desc (`p.cd`)・scope.in/out (`scol in/out` の全 `<li>`・bullet 無し偽 li も拾う)・actor.role (`div.role`・approval の `span.role` とタグで区別)・
  upper_needs.need (source-trace 2nd td)・ears.condition (`td.cond`)・ears.response (`td.resp` 全体を取り出し prose-slot span を strip した残余・
  slot 前/間/後ろのどこへの text-node 追記も残余不一致で捕捉)・nfr.target (`span.tgt`)・nfr.measure (`td.meas`)・acceptance.criterion (`p.at`)・constraint.text (3rd td・reg-badge 前)。
- **二層 (ds8/dty 不動点の再適用)**: 順序突合は double-quote 抽出ゆえ *値/順序の改竄* と *bullet 無し偽 li の追加* を捕捉。 single-quote/case-drop した
  偽セルの **decoy-add** は §7f vcount 占有数パリティ (`cd/cond/resp/meas/at/role/b` を `count_attr_token` で `|contract|` binding・quote/case 非依存) が封鎖。
  → これら 7 class を **EXEMPT → COUNTED** へ移動 (class-token 機械的網羅と整合)。
- **strip の安全性**: バッジ strip は legit double-quote 形のみ正規化するため、 quote 逸脱/追加した偽バッジは strip されず残って突合 FAIL = tamper は必ず落ちる。
- **folio-czo (同梱)**: 凡例 (emit_legend) の en (When/While/If-Then/Ubiq.) と lt (タイプ:/優先:/検証:) を §7f legend-scope の (class,label) SET に追加し
  R9 主ラベル突合と *対称化* (round-9 までは EXEMPT で未突合だった非対称を解消)。 en は親 ears chip の class と対 (位置 swap も捕捉)・lt は単独ラベル。
  ★en は glossary 表とも class 共有ゆえ legendblk scope で SET 突合 (global vcount 化しない = glossary en は folio-mk9 の領分)・EXEMPT 維持。
- **two-gate 境界 (確定)**: 識別子・構造・数値・統制値 = floor (機械検証・本 issue)。 本文 prose 内容 + opus prose スロット (cover-summary/plain/rationale 等) の
  content fidelity = ceiling (gate J = `agents/fidelity-srs`)。 区別原理は「正当 content と *構造的に区別可能か*」 — 識別子/統制値は区別可能ゆえ floor、 自由 prose は ceiling 寄り。
  legend (emit_legend) は静的デザイン資産 (icon/CSS と同様 contract 由来でない) ゆえ contract-fidelity floor の対象外 (静的テンプレ完全性は別概念)。

## A/B 可読化 (ADR-0042 §2.2)

- **B = 畳む** (`rtm-grid` register): RTM を `<details>` で既定折りたたみ + 空不可の平易要約スロット。 全グリッド DOM 保持 (ゼロ損失)。
- **A = 噛み砕く** (要件本体・NFR): 各行に空不可の **plain (やさしい言い換え) スロット**。 要件行は rationale スロットも持つ。
- **専門語の plain_short 併記** (`plain-language-term-inline` = glossary 派生ビュー): `mark_terms` が contract.glossary の語を
  本文の flowing 読み取り系フィールド (goals.desc / scope / actors.role / upper_needs.need / ears.condition+response /
  nfr.target+measure / acceptance.criterion / constraints.text) の **first-occurrence で 1 回だけ** 検出し、 その直後に
  `glossary.plain_short` (やさしい言い換え) を `.term` バッジで **併記** する (本文の専門語は SSoT ゆえ残す)。 例:
  「在庫引当 ⟨在庫の取り置き⟩」。 タイトル/短い headline/ラベル/glossary 表/RTM セルは対象外。 flowing 出現が無い語
  (EC では 二重課金) は glossary 章で被覆。 ascii 略語 (WMS/PCI DSS) は語境界でのみマッチ。 glossary 語どうしの部分文字列ペアは
  validate が拒否 (ネスト span 防止)。 fidelity = data-term ∈ glossary かつ 併記 == その語の plain_short。

## 使い方

```bash
# ② 構造を決定的に組む (prose スロット空)
./assemble-srs.sh contract/ec-checkout.srs.yaml asm.html
./verify-fabrication-free.sh contract/ec-checkout.srs.yaml asm.html              # pre-fill: 捏造ゼロ + prose 全空 を証明

# ③ opus manifest の散文を決定的に注入 (空スロット → 充填)
./inject-prose.sh prose/ec-checkout.prose.yaml asm.html filled.html
./verify-fabrication-free.sh --filled prose/ec-checkout.prose.yaml contract/ec-checkout.srs.yaml filled.html  # post-fill: 構造捏造ゼロ + prose 全充填 + 注入忠実

# S5: 生成 SRS プレゼンの *成果物 floor* (生成と分離・手編集後も再検証可)。 CLI からも呼べる。
./verify-srs.sh contract/ec-checkout.srs.yaml filled.html                        # gate A-F floor (renderer 在で gate F 自動実行) → ceiling=PENDING
folio verify-srs filled.html contract/ec-checkout.srs.yaml                       # ← bin/folio 経由 (引数順は <html> <contract>)

# gate F (render 健全性) を単体で。 host は pip 不在ゆえ uv 経由 (CI は pip playwright)。
uv run --with playwright==1.60.0 python render-gate-srs.py filled.html           # 実 SRS を light/dark × 3 viewport で検査
uv run --with playwright==1.60.0 python render-gate-srs.py --selftest            # detector の検出力を fixture で自己検証

./test-adversarial.sh                                                            # 96 ケース: assembler + prose + term-inline + verify-srs floor + gate F selftest + ds8 gate H/cover-meta + dty 識別子/構造値 (§7e+§7f+marker count) の回帰
```

## S5 floor: verify-srs (taxonomy §5.2 gate A-H + visual-first)

`verify-srs.sh <contract> <html>` (CLI: `folio verify-srs <html> <contract>`) は生成 SRS プレゼンの **決定的 floor**。
生成と検証を分離した独立検証 (manifest 不要 = 成果物入力)。 **gate letter は taxonomy §5.2 定義に一致**:
- **gate A** MUST 部品存在: S5 凍結 required-existence 集合 (assembler が完全 SRS に対し決定的出力する MUST 部品) を各 ≥1。
- **gate B** register 整合: deck-band ≥1 + dense系 ≥1 + requirement-type-color-tokens + prefers-color-scheme 両モード。
- **gate C** RTM 完全性: 孤立要件 0 / 未検証要件 0 (集合一致は verify-fab が担保)。
- **gate D** 要件 ID 健全性: 一意 `data-req-id` + 全要件行に priority-badge + 検証手法 (T/A/I/D)。
- **gate E** 用語被覆: term-inline が glossary から正確派生 = `verify-fabrication-free --artifact §9` に委譲。
- **gate F** render 健全性: `render-gate-srs.py` (playwright・**light/dark × 3 viewport**) で **low-contrast (WCAG AA) / horizontal-overflow / component-overlap** を検出 (S3 の dark-contrast 崩壊型を gate 化)。 幾何定数は `tests/render-gate/probe.js` (ADR-0037) の値を複製 (drift は A35 が検知)。 **重い playwright ゆえ renderer 在環境で実行・不在は honest SKIP** (PASS と詐称せず floor 不完全と明示)。 `SRS_SKIP_RENDER=1` で bash-only 高速 floor に。
- **gate G** 内容完全性: 必須スロット非空 (--artifact) + placeholder トークン (TBD/未定 等・case-insensitive・日本語含む) =0。
- **gate H** fidelity meta: fidelity-sync-meta の 3 項目が *非空白* で充填。
- **visual-first**: 各章 (footer 除く) に非 prose 部品 ≥1。
- **census-count** (blocking arm・folio-mzn.3): 計数部品の **source DOM 静的件数 == contract 期待件数** (`ears-requirement-row` == `.requirements` 数 ∧ `nfr-metric-row` == `.nfr` 数 ∧ `.plain` == 両者の和・render 不要の算術照合、 REQ-VER-024)。
- ★**機械/LLM 検証境界** (verification §3.9 = SSoT・folio-mzn.2/mzn.3): **blocking arm = gate A–E,G,H + visual-first + census-count (+ gate F)**。 静的 hidden-render ban 群 (script/template/nested-context/inline-only/scroll-pseudo/list-marker) + visual-deception ban (unicode/bidi-override) + **gate F2 render census の全 class は warn 級 backstop (非 blocking・exit を上げない)** — fabrication-free-by-construction (rules §12) で構成上排除済の脅威の再検査ゆえ、 捏造の意味権威は ceiling gate J・可読性は gate I。 gate F2 の **T7 render 破綻は測定系 tool-integrity error として exit 2** (gate 判定と別軸・「omission 0 = clean」と取り違えない)。
- ★**floor 通過でも GREEN を宣言せず `CEILING=PENDING` を返す** (taxonomy §5.1「floor 単独 GREEN 禁止」)。
  GREEN ⟺ floor 全通過 ∧ ceiling (persona-walk-srs + fidelity-srs + completeness-critic-srs) 合格。 **exit 0 は floor PASS であって GREEN ではない**。
  ceiling は **S5.2 で制度化** (`agents/persona-walk-srs` = gate I / `agents/fidelity-srs` = gate J)、 **gate K = `agents/completeness-critic-srs` は folio-mzn.1.2 で追加・folio-mzn.1.4 landing で 2→3 翼 amendment 済**。 敵対回帰 A22-A33 が各 bash gate の fail-closed を、 A34 (= `render-gate-srs.py --selftest`) が gate F detector の検出力を固定。

## 範囲 (S4 リッチ化スライス)

EC 注文確定・決済 SRS を題材に、 **承認済み S3 デザイン (`../example-srs.html`) 相当を機械 SSoT から決定的に組む** ことを実証。
18 部品種を被覆: doc-cover-band(+approval-block) / chapter-deck-band ×9(番号+icon) / section-lead-callout(goals) /
scope-summary-panel / actor-stakeholder-table / source-trace-origin / requirement-matrix-table(+ears-requirement-row) /
nfr-hero-metrics / nfr-metrics-table / acceptance-criteria-checklist / rtm-grid(B 折りたたみ) / constraint-callout /
glossary-term-table / priority-badge / fidelity-sync-meta。

### 承認 example との差分 (「再生成」の正確な意味)
「再生成」= **example と同一 DOM の複製ではなく、 同じ機械 SSoT から ADR-0042 変換を適用した決定的派生**。 既知の差分:
- **prose** — ③ 実装済。 章リード/plain/根拠/RTM 要約/1 文サマリは `prose/ec-checkout.prose.yaml` (opus 著作) を `inject-prose.sh` が注入。
- **RTM 母集合** — 本 contract は FR1–6 + NFR1–4 の 10 行。 example は FR1–4 の簡略 4 行 (contract データ差)。
- **RTM 折りたたみ** — 生成物は §2.2 B で `<details>` 折りたたみ。 example は inline 展開 (意図的 divergence)。

## open-items (後段へ申し送り)

- **新部品の catalog/taxonomy 登録 (→ S6 folio-ctv)**: `rtm-collapse` / `nfr-metric-row` / `source-trace-row` /
  `data-prose-slot="plain"` を catalog.html へ登録し taxonomy §3 + gate G 被覆へ接続。 A/据置 allowlist 凍結。
- **章構成の外部化 (→ 後段 / S7 寄り)**: 章順 / tint / icon / kicker 文 / 章タイトルは現状 assembler `build()` に EC 寄り literal で
  ハードコード。 別ドメイン汎用化には章メタを contract/テンプレートへ外部化する設計が要る (assembler 本体は既に SSoT キー非依存)。
- **S5 2-gate (→ folio-vhy)**: `--filled` verify は注入忠実 + no-TBD を **floor** で保証するが、 prose が SSoT を *正しく要約* するか
  (歪曲/脱落なし) は機械では測れない = **fidelity ceiling** (spec-review-fidelity / persona walk) が S5 の本体。 manifest 著作時の
  ③ ceiling はその先取り。

## 重要 gotcha

- **bash 5.2+ patsub_replacement**: `${v//pat/repl}` の repl 中の生 `&` が「マッチしたテキスト」後方参照になり、
  HTML escape を破壊する (`<` → `<lt;`)。 assemble-srs.sh / assemble-adr.sh / lib/common.sh / inject-prose.sh / verify は冒頭で `shopt -u patsub_replacement` し無効化する。
- **perl `-0777` (slurp) 下の `while(<$fh>)` は `$/` も `$_` も壊す (本セッション 2 度踏んだ)**: `-0777` は `$/` を undef に
  固定するため、 補助ファイル (inject の map / mark_terms の GMAP・LEDGER) を素の `while(<$fh>)` で読むと **ファイル全体を 1 行**
  として読み込む (GMAP なら @g が 1 エントリに潰れ全語を失う)。 加えて inject の注入 perl では `$_`=slurp 済み HTML を暗黙代入で
  破壊し出力が空になる。 補助ファイル読みは必ず **`{ local $/="\n"; ... }` ブロック + lexical 変数** (`while (my $l=<$fh>)`) で囲み、
  STDIN slurp は別途 `local $/; <STDIN>` で行う。
- **once-per-doc の状態は shell 変数でなく *ファイル* で持つ**: `mark_terms` は常に `$(mark_terms ...)` = command-substitution
  subshell で呼ばれるため、 連想配列 (`TERM_MARKED`) への書き込みは親へ伝播しない (`cmd | while` のプロセス置換化だけでは
  直らない — 真の subshell は `$()` の方)。 **LEDGER ファイル**に既マーク語を追記すれば subshell を越えて永続し true once-per-doc になる。
- **語境界判定は assemble と verify で *同一規律* (detect↔remediate parity)**: term-inline の照合は `perl -CSD` (UTF-8 decode)
  で、 ascii 略語は英数境界 `(?<![A-Za-z0-9])\Q..\E(?![A-Za-z0-9])`、 CJK 語は漢字非隣接 `(?<!\p{Han})\Q..\E(?!\p{Han})`
  (在庫引当金 など漢字複合語の内部に gloss を誤付与しない・かな/記号/英数字隣接は許可。 完全な形態素境界ではない軽量近似)。
  **verify §9(c) の被覆再導出も同じ regex** を使う — 片方が substring 照合だと embedded 語で偽 FAIL (ascii) / 誤マーク見逃し
  (CJK false-PASS) が出る。 markable フィールド列は assemble の mark_terms 適用先と verify の yq クエリで二重保守 (要同期)。
- **perl の footer flip は `\x{2713}` でなくリテラル UTF-8 バイトで書く**: byte (Latin-1) モードの perl に wide char を混ぜると
  同一行の日本語 UTF-8 バイトが二重エンコードされ壊れる ("Wide character in print")。 置換文字列に ✓ → を直接書く。
- `srs.css` を inline するため生成 HTML に CSS セレクタ `[data-component="..."]` が含まれる。 grep 検証 (verify・S5 floor) は
  `<style>` ブロックを除去してから数えること。
- 行数カウントは id 命名でなく **`data-component`/class 行マーカー**で table-scoped に数える。
- `@tsv` は値内 tab/改行で列ずれ・phantom 行を生む → validate が fail-closed 拒否。 入れ子 optional sub-field は `// ""` で null 漏れを防ぐ。
- prose 層は **slot-id 集合 == manifest key 集合** を強制 (順序非依存)。 manifest 値の取得は `key=... yq '.slots[strenv(key)]'`
  (キーに `-` を含むため path interpolation でなく strenv)。

## Trace

ADR-0042 / taxonomy `architecture/research/srs-component-taxonomy.html` §3/§5 / design system `../catalog.html` `../srs.css` / 承認 example `../example-srs.html`。
ceiling review 4 ラウンド反映: wf_41fcbde3 (第一スライス: escape 追加 / 改行 phantom / acceptance 無検証 等)、 wf_82c7b956 (リッチ化:
**esc の patsub_replacement 破綻** = 第一スライスで追加した escape が bash 5.2 で無効だった blocker / A1 の否定検証 false-pass /
nfr.hero null 漏れ / RTM 行ラベル欠落 / cover ID レンジ / actor.tint CSS allowlist)、 wf_e20518f2 (③ prose fidelity 4-lens:
**rationale-FR5 の捏造** = FR5(確認メール)→N-1 を埋めるため SSoT に無い因果機構「不安→再注文→二重注文」を新造し
二重注文/二重課金を概念混同した major を 2 lens が独立収束で捕捉 → N-1 literal へ retreat / plain-FR2 の通信再送 scope 混入 /
plain-NFR4 の rationale 逸脱 / plain-FR6「勝手に」の限定ニュアンス / チャージバック未併記) を全反映。
**floor (--filled verify = 注入忠実 + no-TBD) は全 PASS でも prose の捏造は通る** = ADR-0042 二層 done-condition (floor ∧ ceiling) の実証。
