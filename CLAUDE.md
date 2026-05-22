# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 twill (`~/projects/local-projects/twill/`) / scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `scratch/constitution.html` — folio の 12 不変原則。 **不変資産、 編集禁止**。

## 2. 編集禁止 (MUST NOT)

現在 folio は試作段階。 以下は **触らない / 作らない**:

- **`scratch/constitution.html`** — 不変資産。 Amendment は user 承認必須 (P-10)。
- **`scratch/decisions/` 配下** — 既存 ADR は frozen。 新規起票は user 承認必須。
- **`scratch/rules.html` / `scratch/folio-self-spec.html`** — 当面 **編集禁止**。 試作段階では参照不要、 必要なら user が明示指示する。
- **`architecture/` dir** — **作らない、 dir 自体を存在させない**。 Phase X3 で plugin 完成後に user 主導で作成予定。

## 3. 作業場所

試作・調査・要望整理・実装試行は **すべて `scratch/`** で行う。

- `scratch/` は folio rule に縛られない **工事用の一時的な箱**。
- 完成後 (Phase X3) に正式 location (`architecture/`) に移植、 scratch は撤去予定。

## 4. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `scratch/` 内は基本 HTML、 ただし思考 memo / 一時 work は柔軟に。

## 5. Directory Layout

```
folio/
├── README.md / CLAUDE.md / common.css   root meta + style (永続)
├── scratch/                              作業場所 (試作・調査・実装試行)
│   ├── constitution.html                 (不変、 編集禁止)
│   ├── rules.html / folio-self-spec.html (当面編集禁止)
│   ├── decisions/                        (既存 ADR frozen、 新規は user 承認)
│   └── assets/                           (mermaid vendor 等)
└── .claude-plugin/                       plugin harness placeholder (触らない)
```

`architecture/` は **存在しない**。 scratch/ が完成した後 (Phase X3) に user 主導で作成予定。 今は触らない、 **作らない**。
