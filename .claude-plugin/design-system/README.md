# folio SRS design system (部品庫)

要件定義書 (SRS) ビジュアル design system の部品庫。機械 SSoT から **人間が読めるプレゼン HTML** を生成する generator (epic c5g / S4) と consumer がここを参照する。

- **設計の WHAT (taxonomy / done-condition)** = `architecture/research/srs-component-taxonomy.html` (ISO/IEC/IEEE 29148:2018 接地、37 部品)。
- **決定 (WHY)** = `architecture/decisions/ADR-0041-human-layer-visual-design-system.html`。
- 本 dir は **HOW 実装** (P-11 部分隔離ゆえ `.claude-plugin/` 配下、CSS/HTML 許容)。

## ファイル

| ファイル | 役割 |
|---|---|
| `srs.css` | design system stylesheet。37 部品を register 別に実装。各部品は `[data-component="<id>"]` で識別 (floor gate A の存在検査対象)。要件型カラートークン + `prefers-color-scheme` 環境追従ダーク両定義。 |
| `catalog.html` | **部品カタログ**。各部品の id / register / 必須度 / 用途 / ライブ実例。generator と人間の参照点。 |
| `example-srs.html` | full SRS 実例 (EC 注文確定・決済)。中核 register の文脈での全体像 = template / proof。 |

## 視覚言語 (ADR-0041)

- **deck帯 × B2高密度**: 章を色帯で開く掴み (deck-band) + 詳細を密表/RTMグリッド/密リストで情報保持 (dense系)。主 register 2 family + 補助 (callout/diagram/badge/glossary/meta)。
- **自己完結**: static HTML + CSS + インライン SVG。no-build・AI 直読・`file://` 動作。generator は `srs.css` を生成物へ inline する想定 (外部依存なし)。
- **テーマ**: 環境追従 (`prefers-color-scheme`)。light/dark 両定義をトークンで持つ。

## 北極星

非エンジニアが頑張れば読める / 専門語にやさしい併記 / 情報を落としすぎない。完全性は floor (機械 A–H) + ceiling (persona walk + fidelity) の二層 done-condition で判定する (taxonomy §5)。

## 後続スライス

- S4 (folio-ruc): generator — 機械 SSoT → 本部品で組んだ人間プレゼン HTML。
- S5 (folio-vhy): 2-gate (floor 機械検査 + persona/fidelity ceiling)。
- S6 (folio-16y): rules 規範化 (部品所有権・dogfood 上位ニーズマップ等、taxonomy §7.2 申し送り)。
