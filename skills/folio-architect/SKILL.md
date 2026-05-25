---
name: folio-architect
description: folio spec edit の正規 author entry point。architecture/spec/ 配下の spec HTML を編集する前に必ず呼び出し、caller marker を set してから編集し、完了後に unset する。folio-self-spec.html §7.1 Phase E の最小実装。
disable-model-invocation: true
---

# folio-architect SKILL

folio spec edit の**唯一の正規 author entry point**（folio-self-spec.html §7.1 の 7-Phase PR Cycle Phase E に相当する最小実装）。

`architecture/spec/` 配下の spec HTML は caller-marker hook で gate されており、本 SKILL 経由で **caller marker file を set** しないと Edit/Write が deny される。本 SKILL を使わずに spec を編集しようとすると hook が止める。

## marker 機構（hybrid: env OR file）

caller-marker hook (`.claude-plugin/scripts/check-caller-marker.sh`) は次のどちらかで spec 編集を allow する:
- env var `FOLIO_ARCHITECT_CONTEXT=folio-architect`（cld 起動時に set する方式。session 開始後は変更不可）
- marker file `.folio/architect-active` の存在（本 SKILL が mid-session で touch/rm する方式）

env は実行中の hook に伝播しないため、**session 内での正規 spec 編集には file marker を使う**。`.folio/` は `.gitignore` 済。

## 手順（MUST）

### Step 1: marker を set

```bash
mkdir -p .folio && touch .folio/architect-active
```

これ以降、`architecture/spec/` 配下の Edit/Write が caller-marker hook で allow される。

### Step 2: spec を編集

通常の Edit / Write tool で `architecture/spec/` 配下の spec HTML を編集する。編集内容は本 SKILL 呼び出し時の指示（または進行中タスク）に従う。

- path-boundary / jsonld-lint hook は別途有効なので、新規 spec は spec_path 配下に置き、JSON-LD は object 形式 `@context` にすること。
- README index に未掲載の新 spec は readme-index hook が notify する → cluster README の §2 inventory にも追記する。

### Step 3: marker を unset（MUST、エラー時も優先実行）

```bash
rm -f .folio/architect-active
```

spec 編集が完了したら**必ず**削除する。これを怠ると marker が残留し、以後の非意図的な spec 編集が通過してしまう（fail-open リスク）。エラーや中断時も cleanup を優先する。

## セルフチェック

```bash
# marker 状態確認
test -f .folio/architect-active && echo "SET (spec 編集可)" || echo "UNSET (spec 編集は deny される)"
```

- [ ] Step 1 で marker を set したか
- [ ] spec 編集が `architecture/spec/` 配下に収まっているか（spec_path 外は path-boundary が deny）
- [ ] Step 3 で marker を削除したか

## stale marker の cleanup

異常終了等で `.folio/architect-active` が残留した場合、明示的に削除する:

```bash
rm -f .folio/architect-active
```

## 制約・注記

- 本 SKILL は `disable-model-invocation: true`。user が明示的に `/folio-architect` で起動する（Claude が spec 編集を予期して自動起動し、marker を即 set/unset してしまう事故を防ぐ）。
- これは Phase X3 試作の**最小版**。完成形は folio-self-spec.html §7.1 の full 7-Phase PR Cycle（spec-explorer / spec-architect / 6 review specialist 連携）。
- marker file path は env `FOLIO_MARKER_FILE` で override 可（hook と整合、default `.folio/architect-active`）。

## 参照

- folio-self-spec.html §7.1（7-Phase PR Cycle）/ §7.3（caller marker flow）/ §7.4（5-Layer Defense）
- rules.html §10.1（REQ-CM-001〜003）
- .claude-plugin/scripts/check-caller-marker.sh（hybrid enforcement logic）
