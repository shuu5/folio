# CLAUDE.md — folio Project Instructions

## 0. Identity (MUST)

- cwd は `~/projects/local-projects/folio/` で始まること。
- これは **folio** (META FRAMEWORK)。 twill (`~/projects/local-projects/twill/`) / scribe / 他 Layer 1 project と混同したら作業前に user に確認すること。

## 1. 必読

- `scratch/constitution.html` — folio の 12 不変原則。 **不変資産、 編集禁止**。

## 2. 編集禁止 (MUST NOT)

現在 folio は試作段階。 以下は **触らない / 作らない**:

- **`scratch/constitution.html`** — 不変資産、 特別枠。 Amendment は user 承認必須 (P-10)。 cross-ref 含め原則として触らない。
- **`scratch/decisions/` 配下** — 既存 ADR は frozen (historical record)。 新規起票は user 承認必須。
- **`architecture/` dir** — **作らない、 dir 自体を存在させない**。 Phase X3 で plugin 完成後に user 主導で作成予定。

## 3. 編集可 (試作段階のブラッシュアップ対象)

- **`scratch/specs/` 配下** — `rules.html` / `folio-self-spec.html` は試作の進行に応じて自由に改訂する。
- **`scratch/research/` 配下** — user 要望 + 業界調査の集約場所、 自由形式 HTML。
- **`scratch/` 直下に新規 file / dir 作成** — 思考 memo / 一時 work / prototype 等は柔軟に。

## 4. 作業場所

試作・調査・要望整理・実装試行は **すべて `scratch/`** で行う。

- `scratch/` は folio rule に縛られない **工事用の一時的な箱**。
- 完成後 (Phase X3) に正式 location (`architecture/`) に移植、 scratch は撤去予定。

## 5. Format

- spec / ADR / constitution は **HTML** で記述する (P-2)。
- Markdown 例外: `README.md`, `CLAUDE.md`, YAML config (`*.yaml`)。
- `scratch/` 内は基本 HTML、 ただし思考 memo / 一時 work は柔軟に。

## 6. Directory Layout

```
folio/
├── README.md / CLAUDE.md / common.css   root meta + style (永続)
├── scratch/                              作業場所 (試作・調査・実装試行)
│   ├── constitution.html                 (不変、 編集禁止、 特別枠)
│   ├── specs/                            (rules.html + folio-self-spec.html、 ブラッシュアップ可)
│   ├── decisions/                        (既存 ADR frozen、 新規は user 承認)
│   ├── research/                         (要望 + 業界調査、 自由形式)
│   └── assets/                           (mermaid vendor 等)
└── .claude-plugin/                       plugin harness placeholder (触らない)
```

`architecture/` は **存在しない**。 scratch/ が完成した後 (Phase X3) に user 主導で作成予定。 今は触らない、 **作らない**。
