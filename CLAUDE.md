# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 twill (`~/projects/local-projects/twill/`) / scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `scratch/constitution.html` — folio の 12 不変原則。 **不変資産、 編集禁止**。
- Phase X3 着手中: `scratch/decisions/ADR-0003-plugin-architecture.html` + `scratch/specs/verification.html` (試作 plugin 実装の規範)。

## 2. 編集禁止 (MUST NOT)

現在 folio は試作段階。 以下は **触らない / 作らない**:

- **`scratch/constitution.html`** — 不変資産、 特別枠。 Amendment は user 承認必須 (P-10)。 cross-ref 含め原則として触らない。
- **`scratch/decisions/` 配下** — 既存 ADR は frozen (historical record)。 新規起票は user 承認必須。
- **`architecture/` dir** — **作らない、 dir 自体を存在させない**。 Phase X4+ に user 主導で作成予定。

## 3. 編集可 (試作段階のブラッシュアップ対象)

- **`scratch/specs/` 配下** — `rules.html` / `folio-self-spec.html` / `relations.html` / `verification.html` は試作の進行に応じて自由に改訂する。
- **`scratch/research/` 配下** — user 要望 + 業界調査の集約場所、 自由形式 HTML。
- **`scratch/verification/` 配下** — Phase X3 sandbox verification framework (scenarios / fixtures / baselines / runner.sh)、 ADR-0013 + verification.html。
- **`.claude-plugin/` 配下** — Phase X3 試作 plugin 本体 (ADR-0003 minimal scope: 1 skill + 4 hook + 6 script + 1 CLI)。 完成形 binding 隔離先 (P-11)。
- **`scratch/` 直下に新規 file / dir 作成** — 思考 memo / 一時 work / prototype 等は柔軟に。

## 4. 作業場所

試作・調査・要望整理は `scratch/`、 plugin 本体実装は `.claude-plugin/` で行う (Phase X3 着手後)。

- `scratch/` は folio rule に縛られない **工事用の一時的な箱**。
- `.claude-plugin/` は P-11 binding 隔離先 (HOW を spec から隔離)。
- 完成後 (Phase X4+) に正式 location 移植予定、 `scratch/` は撤去候補。

## 5. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `.claude-plugin/` 配下は HOW のため bash / json / md 等を許容 (P-11 隔離)。
- `scratch/verification/scenarios/` は YAML (verification.html §3.2 schema)。

## 6. Directory Layout

```
folio/
├── README.md / CLAUDE.md / common.css   root meta + style (永続)
├── scratch/                              作業場所 (試作・調査・実装試行)
│   ├── constitution.html                 (不変、 編集禁止、 特別枠)
│   ├── specs/                            (ブラッシュアップ可)
│   ├── decisions/                        (既存 ADR frozen、 新規は user 承認)
│   ├── research/                         (要望 + 業界調査、 自由形式)
│   ├── verification/                     (Phase X3 sandbox verification、 ADR-0013)
│   │   ├── scenarios/                    use case 別 YAML
│   │   ├── fixtures/                     テストデータ
│   │   ├── baselines/{reference,local}/  golden (VCS) vs 実行生成 (.gitignore)
│   │   └── runner.sh                     軽量 bash runner
│   └── assets/                           (mermaid vendor 等)
└── .claude-plugin/                       Phase X3 試作 plugin 本体 (ADR-0003)
    ├── plugin.json                       manifest
    ├── hooks/hooks.json                  hook 宣言
    ├── scripts/                          hook 実装 + CI script (試作中)
    ├── skills/                           folio-architect (Phase X3 後段)
    └── bin/folio                         CLI skeleton
```

`architecture/` は **存在しない**。 完成形 (Phase X4+) では `.claude-plugin/` + 移植先 `architecture/` の役割分担に移行 (P-12)。 Phase X3 着手段階では `.claude-plugin/` のみ実装、 `architecture/` は作らない。
