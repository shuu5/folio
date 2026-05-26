# folio e2e integration runbook

folio plugin を **ひとまとまりの道具** として実シナリオで使い、想定通り動くかを観察する手順書。
verification.html §4.1 Step 2 (worktree integration) / REQ-VER-009 の試作実装。
S-A〜S-E は Track 0 の Edit/Write walk。S-F は Track 2 追加 (SessionStart context injection、REQ-VER-012 / ADR-0007、fresh-session 起動観察)。S-G は Track X4-D 追加 (folio-architect 7-Phase + Phase F 3-agent review、REQ-VER-016 / ADR-0027、plugin reload 後の fresh session で walk)。S-H〜S-J は Track X4-E 追加 (CLI lifecycle 統合 = init→validate / edit→fix→validate / inventory・prime、REQ-VER-009 傘下 = init:014 / validate:013 / fix:015 / inventory:010 / prime:012、bash-CLI ゆえ hook/agent load 非依存 = **session 非依存で本 session でも walk 可**)。

agent (あなた) がこの runbook を読み、**実際の Edit/Write tool で操作** して live load 済 plugin の
hook を発火させ、観察を記録する。sandbox 単体テスト (`../scenarios/` + `runner.sh`) とは別物
(あちらは mock payload を `echo | bash`、こちらは実 tool 操作)。

## 一次 assertion = file 作成有無

PreToolUse の deny は transcript に確実には現れない (research §2.6 / Issue #39344)。一方
file system 上の作成/不在は決定的に観察できる。したがって各シナリオの**一次 assertion は
「対象 file が作成されたか否か」** とし、`ls` / `test -f` で確認する。

| hook 種別 | 期待 | file への影響 |
|-----------|------|--------------|
| PreToolUse deny (exit 2) | tool 自体がブロック | file **不在** |
| PostToolUse notify (exit 2) | tool は実行済、通知のみ | file **存在** + stderr 通知 |
| allow (exit 0) | 通過 | file 存在、通知なし |

二次 assertion として、tool 結果に現れる deny/notify message も記録する (出れば bonus、
出なくても file 状態で判定可能)。

**CLI scenario (S-H〜S-J) の assertion は別系統**: hook を発火させない bash-CLI ゆえ、一次
assertion は file 作成有無でなく **exit code + chained state** (init→validate clean / validate
RED→fix→validate GREEN / inventory 件数・prime digest 形式)。これは sandbox cli-golden
(REQ-VER-011) と同種の exit/output 判定だが、fixture でなく**実 disk 上の temp consumer project
/ live repo で lifecycle を chain する**点が統合 (§4.1 Step 2 worktree integration) たる所以。

## 前提

- folio plugin が load 済の session (`~/.claude/plugins/folio` symlink + cld auto discovery)。
- worktree 内で実行。probe file は walk 後に**全削除**。
- marker file `.folio/architect-active` は `.gitignore` 済。walk 後は必ず `rm -f`。
- walk 前後で sandbox 43/43 PASS を維持 (`rm -f .folio/architect-active` 後に runner 実行、11 scenario file)。

## marker 機構 (caller-marker hook)

`architecture/spec/` 配下の Edit/Write は caller-marker hook で gate される。次のどちらかで allow:
- env var `FOLIO_ARCHITECT_CONTEXT=folio-architect` (cld 起動時 set、session 内変更不可)
- marker file `.folio/architect-active` 存在 (mid-session で `touch`/`rm`、folio-architect SKILL が使う方式)

set: `mkdir -p .folio && touch .folio/architect-active` / unset: `rm -f .folio/architect-active`

---

## S-A — happy-path (★最重要: 道具として spec を書けるか)

**目的**: marker を set すれば 4 hook を通り抜けて正規 spec を書ける、を実証する。

**操作**:
1. `mkdir -p .folio && touch .folio/architect-active` (marker set)
2. `architecture/spec/e2e-probe.html` を Write。content は object 形式 JSON-LD
   (`@context` object + `@id` + `@type`) + `<meta name="folio-doc-type" content="spec">` 付き。

**期待観察**:
- file **作成される** (caller-marker は marker で allow / path-boundary は spec_path 配下で allow /
  jsonld-lint は object @context で allow)。← **これが happy-path の核心**。
- readme-index notify が出る (specs/README.html に e2e-probe.html 未掲載のため、PostToolUse exit 2)。
- jsonld-lint は通知**しない** (object 形式で valid)。

**後始末**: `rm -f .folio/architect-active` → `rm -f architecture/spec/e2e-probe.html`

---

## S-B — guardrail (誤りを捕まえる)

### B1: marker 無しで spec 編集 → deny

**操作**: marker UNSET (`rm -f .folio/architect-active`) の状態で `architecture/spec/e2e-b1.html` を Write。

**期待観察**: file **不在** (caller-marker が PreToolUse deny)。← live hook の決定的確認点。

### B2: spec_path 外で spec を作成 → deny

**操作**: marker SET で `architecture/random-e2e/e2e-b2.html` を Write。
content に `<meta name="folio-doc-type" content="spec">` 付き (spec_path 外)。

**期待観察**: file **不在** (caller-marker は spec_path 外なので非 gate=通過、path-boundary が
spec content + spec_path 外を検出して PreToolUse deny)。

### B3: string 形式 @context で spec 作成 → notify

**操作**: marker SET で `architecture/spec/e2e-b3.html` を Write。
content の JSON-LD `@context` を string 形式 (`"@context": "https://schema.org/"`) にする。

**期待観察**: file **作成される** + jsonld-lint notify (PostToolUse exit 2、@context must be object)。
readme-index notify も併発する (未掲載のため) — 主 assertion は jsonld-lint notify。

### B4: valid だが README 未掲載で spec 作成 → notify

**操作**: marker SET で `architecture/spec/e2e-b4.html` を Write。
content は valid な object JSON-LD だが specs/README.html に未掲載。

**期待観察**: file **作成される** + readme-index notify (PostToolUse exit 2)。
jsonld-lint は通知しない (valid object)。

**S-B 後始末**: `rm -f .folio/architect-active architecture/spec/e2e-b3.html architecture/spec/e2e-b4.html`
+ `rm -rf architecture/random-e2e/`

---

## S-C — false-positive (gate 対象外は誤作動しない)

**目的**: spec_path 外 / 非 spec は gate されない、を実証する (過剰 deny がない)。

**操作** (marker UNSET):
1. C1: `architecture/random-e2e/e2e-c1.html` を Write (plain HTML、folio-doc-type=spec **無し**)。
2. C2: `README.md` (markdown、spec_path 外) を Edit。

**期待観察**:
- C1: file **作成される** (caller-marker 非 gate / path-boundary は spec 非該当で通過 /
  jsonld-lint は JSON-LD block 無しで通過 / readme-index は cluster に README.html 無しで通過)。
- C2: Edit **allow** (caller-marker は spec_path 外なので非 gate。markdown は path-boundary/
  jsonld/readme の matcher=.html 対象外)。

**後始末**: `rm -rf architecture/random-e2e/` + `git checkout -- README.md`

---

## S-D — CLI (skeleton 動作確認)

**操作**:
1. `bash .claude-plugin/bin/folio version`
2. `bash .claude-plugin/bin/folio help`

**期待観察**: 両者 exit 0 + 出力あり (version 文字列 / help テキスト)。unknown subcommand は exit 1。

**注 (X4-E 更新)**: 本 S-D は skeleton (version/help) の確認に留める。init/validate/fix/inventory/prime
は X4-A/X4-B + validate/inventory/prime 実装で**本実装済**となり、その lifecycle 統合は **S-H〜S-J で walk** する
(2026-05-24 の `observations.json` S-D は当時の skeleton snapshot = `0.4.2-draft`・「未実装」記述ゆえ historical、
現行 CLI は S-H〜S-J / `observations-cli.json` を正とする)。

---

## S-E — marker-ux (手動 set→edit→unset フロー)

**目的**: folio-architect SKILL は `disable-model-invocation: true` のため agent 自動起動不可。
手動 marker フローが成立するかを観察する。

**観察**:
- set→edit→unset フローの成立は **S-A で実証される** (set 後に spec が書け、unset 後は…)。
- E1 (unset 復帰確認): S-A/S-B の marker SET 群の後、`rm -f .folio/architect-active` してから
  `architecture/spec/e2e-e.html` を Write → file **不在** (deny 復帰)。marker 残留による fail-open が
  ないことを実証する (SKILL Step 3「unset を怠ると fail-open」の裏取り)。
- SKILL 経由の正規 UX (user が `/folio-architect` で起動 → marker 自動 set/unset) は
  `disable-model-invocation: true` のため agent からは起動できない。これは user が手動で
  `/folio-architect` する **Phase X4+ で追加検証**、と記録する。

**後始末**: `rm -f .folio/architect-active` (E1 で既に unset 済)。e2e-e.html は deny で不在。

---

## S-F — SessionStart context injection (★Track 2: 道具が architect に文脈を渡すか / REQ-VER-012 / ADR-0007)

**目的**: folio の signature 機能 — fresh session 起動時に SessionStart hook が Tier 1 inventory digest を
context に注入するか実観察する。S-A〜S-E (Edit/Write 操作) とは別 method = **fresh session 起動の観察**。

**前提**: folio plugin が load される環境 (`~/.claude/plugins/folio` symlink + cld auto discovery)。
SessionStart hook は session 起動時にのみ発火するため既存 session では観察不可 → **fresh session (spawn) 必須**。

**操作**:
1. folio repo を cwd に fresh cld session を spawn (`cld-spawn --cd <folio repo>`)。
2. spawn の prompt で「起動時 context に folio inventory digest が注入されているか、編集せず観察のみ報告せよ」と指示。
3. spawn の応答を capture。

**期待観察**: spawn が初期 context に Tier 1 digest を受領 = 先頭 `# folio inventory digest — Tier 1` +
spec 件数 + 各エントリ (`## <@id-path>` / title / doc-type·status / summary) を引用できる。
= SessionStart hook → inject-inventory.sh → folio prime stdout → context 注入の full chain が動作。

**注**: SessionStart は matcher 省略で startup/resume/clear/compact 全 source 発火。本 S-F は **startup source** を検証。
compact source (post-compaction 再注入) は 2026-05-25 の実 /compact で **検証済** (S-F-compact、observations-sessionstart.json、ADR-0007 §2.1 を e2e-verified に格上げ、ADR-0017 §2.4)。
PreCompact hook は stdout 非注入のため ADR-0007 amend (2026-05-25) で除去済。

**後始末**: spawn window を kill (read-only 観察、commit/編集なし)。golden は `baselines/reference/observations-sessionstart.json`。

---

## S-G — folio-architect 7-Phase + Phase F 3-agent review (★X4-D: ADR-0027 / REQ-VER-016 (b))

**目的**: `/folio-architect` 起動で 7-Phase orchestration が回り、**Phase F で 3 review agent (`folio:spec-review-ears` / `folio:spec-review-vocabulary` / `folio:spec-review-ssot`) が並列 spawn** され、seed した既知 violation を flag することを観察する (REQ-VER-016 (b) e2e、非決定的ゆえ一次 assertion = **検出有無**)。S-A〜S-F (hook 発火) とは別 method = **SKILL orchestration + subagent 並列 spawn の観察**。

**前提**:
- folio plugin が load 済で、**X4-D の 3 agent (`agents/spec-review-*.md`) + 7-Phase 昇格 SKILL が load されている**こと。agent/SKILL を追加・編集した直後の session では未 load ゆえ → **plugin reload 後の fresh session 必須** (本 worktree で実装した直後の session では観察不可)。
- folio-architect は `disable-model-invocation: true` ゆえ **user が手動で `/folio-architect` 起動**する (agent 自動起動不可)。

**操作**:
1. marker SET (`mkdir -p .folio && touch .folio/architect-active`) で seed spec `architecture/spec/e2e-x4d-seed.html` を Write。**既知 violation 3 種**を仕込む:
   - **EARS 欠落** (ears 軸): 規範要件 `<p class="ears">` を置くが `data-ears-pattern` 属性 or `<span class="ears-shall">SHALL</span>` を欠落させる。
   - **forbidden synonym** (vocabulary 軸): 同一 entity を複数呼称で混在 (例 同じ marker を "caller marker" / "caller-marker" / "marker flag" と書き分ける)。
   - **domain 越境** (ssot 軸): spec 本文に WHY rationale (「〜と決めた経緯」) や HOW (具体 script snippet / CLI 構文) を混入 (P-7 / P-11 違反)。
2. `/folio-architect` を起動し「`architecture/spec/e2e-x4d-seed.html` を review せよ」と指示 → Phase F まで進ませる。
3. Phase F で 3 review agent が **1 メッセージで並列 spawn** され、構造化 findings (severity / location / 違反 rule / 修正提案) を返すのを観察。

**期待観察** (一次 = 検出有無):
- `folio:spec-review-ears` が **EARS 欠落**を finding (severity 付き) で flag。
- `folio:spec-review-vocabulary` が **forbidden synonym** を flag。
- `folio:spec-review-ssot` が **domain 越境**を flag。
- 3 agent が並列 (同一 response で同時) に spawn される。
- LLM 非決定的ゆえ finding 文言は golden 比較せず、**該当 violation 3 種それぞれが少なくとも 1 つの agent に検出されたか否か**を assertion とする (REQ-VER-016 (b))。

**注**: 実 live walk は **plugin reload (3 agent + 昇格 SKILL の load) を要すため別 fresh session (merge 後)** で実施する。本 runbook 整備時点では手順 + 期待 observation を定義し、golden observation (`baselines/reference/observations-architect.json`) は walk 後に埋める **placeholder**。structural 検証 (REQ-VER-016 (a)) は live load 非依存で `../scenarios/agent-structure.yaml` (`kind: agent-structural`) が決定的に PASS 済。

**後始末**: `rm -f .folio/architect-active architecture/spec/e2e-x4d-seed.html`。golden = `baselines/reference/observations-architect.json`。

---

## S-H — CLI lifecycle 統合: init → validate (★X4-E: 道具として consumer project を産み validate clean か)

**目的**: `folio init` が新規 consumer canonical layout を scaffold し、生成 skeleton が `folio validate` で
**out-of-the-box clean** であることを実 disk 上で実証する (REQ-VER-014 の核心)。sandbox `init-scaffold.yaml`
が golden 比較 (isolated fixture) なのに対し、本 S-H は temp consumer project への **live lifecycle 統合**
(§4.1 Step 2 = test project + 検証)。

**前提**: bash-CLI ゆえ hook/agent load 非依存 = **session 非依存** (S-F/S-G と違い fresh session 不要、本 session で walk 可)。

**操作** (すべて bash):
1. `TMP=$(mktemp -d)` で temp consumer project root を作る。
2. `bash .claude-plugin/bin/folio init "$TMP"` → exit code + scaffold tree を観察。
3. `bash .claude-plugin/bin/folio validate --root "$TMP/architecture"` → exit code + 3-gate 結果を観察。

**期待観察**:
- init **exit 0** + `folio.config.yaml` + `architecture/spec/{README,constitution,overview}.html` +
  `architecture/{decisions,research}/README.html` (計 6 file) を create + 「existing files preserved」message。
- validate **exit 0 clean** (files checked: 5、3-gate すべて OK)。consumer の `constitution.html` は通常
  conforming JSON-LD ゆえ scan 対象 (folio 自身の `FolioConstitution` schema scan 除外とは別物 = consumer starter は普通の spec)。

**後始末**: `rm -rf "$TMP"`。golden = `baselines/reference/observations-cli.json`。

---

## S-I — CLI lifecycle 統合: detect ↔ remediate (★X4-E: validate↔fix の往復が live で閉じるか)

**目的**: forward 関係を片側だけ持つ spec graph を `folio validate` が **broken-reverse violation (exit 1)** で検出し、
`folio fix` が reverse を materialize して clean (exit 0) に戻す **detect↔remediate ペア** が live で閉じることを
実証する (REQ-VER-015 / ADR-0025)。sandbox `fix-bidirectional.yaml` の fixture 検証に対し、本 S-I は S-H の
temp project 上で edit→validate→fix→validate を **chain** する統合 walk。

**前提**: S-H の temp project を clean 状態から再利用。spec mutation は **bash で行う** (Edit/Write tool だと
path-boundary hook が `folio-doc-type=spec` を gate しうる。hook は bash を対象としない = 正規の fixture mutation 経路)。

**操作** (すべて bash、S-H の `$TMP` 上):
1. `overview.html` の JSON-LD に forward `dc:references → ./constitution.html` を sed 注入 (reverse `dc:isReferencedBy` は付けない)。
2. `folio validate --root "$TMP/architecture"` → broken-reverse RED。
3. `folio fix --root "$TMP/architecture"` → reverse materialize。
4. `folio validate` 再走 → clean。
5. `folio fix` 再走 → 冪等 no-op。

**期待観察**:
- (2) validate **exit 1** + `[FAIL] broken-reverse` + report (`spec/overview.html [broken-reverse] dc:references ->
  spec/constitution.html (target missing reverse dc:isReferencedBy ...)`)、relations checked +1。
- (3) fix **exit 0** + `+1 reverse @id spec/constitution.html` + constitution.html に `dc:isReferencedBy → ./overview.html` materialize。
- (4) validate **exit 0 clean** (3-gate OK、relations checked に reverse +1)。
- (5) fix **exit 0** + 「already complete: graph is bidirectional (0 reverse relations added)」、再 validate exit 0 (冪等性)。

**後始末**: `rm -rf "$TMP"`。golden = `baselines/reference/observations-cli.json`。

---

## S-J — CLI read-only: inventory + prime (★X4-E: live repo の digest 生成)

**目的**: `folio inventory` が live repo の spec graph を走査して `inventory.json` を生成し、`folio prime` が
Tier 1 digest を stdout に出すことを実証する (REQ-VER-010 / REQ-VER-012)。sandbox `inventory-gen.yaml` /
`prime-digest.yaml` の golden 比較に対し、本 S-J は **live repo 上の直接 invocation** 観察 (S-F は SessionStart
経由の context 注入を被覆、S-J は CLI 直接呼び出しを被覆)。

**前提**: live folio repo (cwd = repo root)。read-only (`inventory.json` は gitignored 生成物)。

**操作** (bash):
1. `bash .claude-plugin/bin/folio inventory` → exit code + spec 件数を観察。
2. `bash .claude-plugin/bin/folio prime` → exit code + Tier 1 digest 先頭を観察。
   注: `prime | head` は SIGPIPE で exit 141 になるため、真の exit は `prime >/dev/null; echo $?` で別取りする。

**期待観察**:
- inventory **exit 0** + 「wrote inventory.json (26 specs)」 + `inventory.json` の `.specs|length == 26` / `.folioVersion == "0.5.0-draft"`。
- prime **exit 0** (head パイプなし) + 先頭 `# folio inventory digest — Tier 1` + `# 26 specs · folio 0.5.0-draft` +
  per-spec エントリ (`## <path>` / title / doc-type·status / summary)。

**後始末**: なし (read-only、`inventory.json` は gitignored)。golden = `baselines/reference/observations-cli.json`。

---

## 完了チェックリスト

- [ ] 5 シナリオ (S-A〜S-E) を実際に walk し観察を記録した
- [ ] 各観察を `baselines/reference/observations.json` に golden として記録した
- [ ] (X4-D) S-G を **plugin reload 後の fresh session** で walk し `baselines/reference/observations-architect.json` を埋めた
- [ ] (X4-E) S-H〜S-J を **本 session で walk** (bash-CLI = session 非依存) し `baselines/reference/observations-cli.json` を埋めた
- [ ] probe file を全削除した (`architecture/spec/e2e-*.html` / `architecture/random-e2e/` / `architecture/spec/e2e-x4d-seed.html`、README.md 復元)
- [ ] temp consumer project を全削除した (`rm -rf /tmp/folio-e2e-consumer-*`、S-H/S-I)
- [ ] marker file を unset した (`rm -f .folio/architect-active`)
- [ ] sandbox 43/43 PASS を維持した (11 scenario file、marker cleanup 後に runner 実行)
