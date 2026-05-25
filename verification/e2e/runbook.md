# folio e2e integration runbook

folio plugin を **ひとまとまりの道具** として実シナリオで使い、想定通り動くかを観察する手順書。
verification.html §4.1 Step 2 (worktree integration) / REQ-VER-009 の試作実装。
S-A〜S-E は Track 0 の Edit/Write walk。S-F は Track 2 追加 (SessionStart context injection、REQ-VER-012 / ADR-0007、fresh-session 起動観察)。

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

## 前提

- folio plugin が load 済の session (`~/.claude/plugins/folio` symlink + cld auto discovery)。
- worktree 内で実行。probe file は walk 後に**全削除**。
- marker file `.folio/architect-active` は `.gitignore` 済。walk 後は必ず `rm -f`。
- walk 前後で sandbox 36/36 PASS を維持 (`rm -f .folio/architect-active` 後に runner 実行)。

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

**期待観察**: 両者 exit 0 + 出力あり (version 文字列 / help テキスト)。
init/validate 等の本実装は Phase X3 試作では未実装 (unknown subcommand は exit 1)。

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

## 完了チェックリスト

- [ ] 5 シナリオ (S-A〜S-E) を実際に walk し観察を記録した
- [ ] 各観察を `baselines/reference/observations.json` に golden として記録した
- [ ] probe file を全削除した (`architecture/spec/e2e-*.html` / `architecture/random-e2e/`、README.md 復元)
- [ ] marker file を unset した (`rm -f .folio/architect-active`)
- [ ] sandbox 36/36 PASS を維持した (marker cleanup 後に runner 実行)
