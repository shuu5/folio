# REQ-VER-031 draft + census re-freeze / canonical regen 手順 (folio-7n17 Leg A → admin land step)

> ★worker cell folio-7n17 (Leg A) が生成した **ready-to-apply draft**。 worktree は【現行 base (id 55) で
> 完全に self-consistent】(contract = canonical = frozen census = 55・selftest GREEN) に保つため、 本 REQ の
> contract 挿入 + census re-freeze + canonical regen (folio build) + golden accept は【admin の land step】で適用する。
>
> **なぜ worker cell で適用しないか (scope 判断の根拠)**:
> 1. **canonical regen = corpus-wide `folio build`** (chrome + JSON-LD backlinks を design-intent 全体へ再生成)。
>    これは verification.html の **3-way regen 競合点** (bxpm が prevnext:1186 を同時改変) で、 fence が
>    「7n17 は srpz land 後 main へ rebase してから folio build」と **admin land 順序へ sequencing** している。
>    worker cell (pre-rebase base) で folio build を走らせると bxpm と衝突し admin が rebase 後に redo する
>    大 blast-radius churn になる。
> 2. **REQ-VER-031 の normative text は user-facing** で ADR-0053 と結合。 fence Leg B は ADR-0053 に
>    「Phase F ceiling → user 文案提示 → land」を課す。 REQ text も同じ review を経てから canonical + golden へ
>    baked すべき (un-ceilined text を先に焼くと ceiling 後に redo)。
>
> したがって本 REQ は draft として提示し、 admin が (ceiling → user 承認 → rebase → 適用 → build → golden) の
> land step で焼く。 arm (実防御) は本 cell で完結し 55 で self-consistent に land する。

---

## 1. REQ-VER-031 contract 挿入 (folio-verification.spec.yaml)

`requirements:` 配下へ以下を追加 (末尾・REQ-VER-030 は srs-verification 所有ゆえ verification.html contract には無く、
本 contract の既存最大は REQ-VER-023。 政策 A の done-condition を新設):

```yaml
  - id: REQ-VER-031
    anchor: req-ver-031
    ears_pattern: ubiquitous
    essence: "flip 済 spec の生成物機械層 fidelity は、 canonical/生成物から導出しない凍結 literal census + contract 対 round-trip + extractor-collapse 敵対 test の三本柱で検証する (snapshot oracle は bootstrap 1 回証明へ退役・ADR-0053)。"
    statement: "folio verification framework は、 flip 済 spec (機械 SSoT 生成の canonical) の生成物が機械層資産を lossless に運ぶことを、 (a) 凍結 literal census (期待値を canonical/artifact/生成物から導出せず生成物 HTML を subject に突合) (b) contract の machine-block から再構成した round-trip (c) extractor 退行 (rich→plain collapse) を撃つ敵対 test の三本柱で検証する MUST。 snapshot oracle との相対 parity は flip 後 ORIG==生成物 で自己比較恒真化するため用いない (ADR-0053)。"
```

★配置 block (2 分岐・**navigable id 増分が異なるので census 目標値が分岐する**・errata-1 must-3):
`REQ-VER-031` は必ず requirements block へ配置する (assemble validate が「孤立要件」を abort する)。 選択肢は 2 つ:

- **分岐 A: 既存 requirements block へ追加** (例: §3.9 srs-done-condition の block の ids に `REQ-VER-031` を足す)。
  新 navigable id は **req-ver-031 の 1 本のみ** = **55 → 56**。 新 subhead を作らないため subhead anchor は増えない。
- **分岐 B: 新 subhead §3.10 を新設** (§3.9 近傍に「§3.10 flip fidelity done-condition」subhead + その requirements block)。
  新 navigable id は **subhead anchor (例 s3-10-*) + req-ver-031 の 2 本** = **55 → 57**。 subhead は `anchor` field を持つため
  navigable id に計上される (verify §3 subhead anchor 列 + §10b id census の両方に効く)。

★**census 目標値は選んだ分岐で決まる** (分岐 A = 56 / 分岐 B = 57)。 §2 の FZ_ID_COUNT / id set 更新はこの分岐値に従う
(旧 draft は分岐 B を推奨しつつ §2 を 56 固定にしていた矛盾 = admin land で id census 自己 RED = false-BLOCKED。errata-1 で是正)。
可読性 (§3.9 と別 subhead で done-condition を独立提示) を採るなら分岐 B、 census 増分最小 (id +1) を採るなら分岐 A。 admin 裁定。

★essence/statement は **rich raw** (xref link を含めてよい) だが、 census 定数への影響を admin が予測できるよう、
上記 draft は xref link を **含めない** plain 寄り text にした (census delta を navigable id 増分のみに抑える意図)。
ceiling で xref/term/code を足す場合は §2 の再測定 one-liner で該当 FZ_* 定数も更新する。

## 2. census re-freeze 手順 (canonical regen 後)

REQ-VER-031 挿入 + canonical regen (§3) 後、 生成物の id 数が **選んだ分岐値** (分岐 A=56 / 分岐 B=57) になるため
凍結 census を re-freeze する。 **目標値を固定せず、 再生成 canonical から実測して差分だけ更新する** (実測 = 唯一の真値):

```bash
cd .claude-plugin/design-system/generator
CANON="../../../design-intent/spec/verification.html"   # regen 後の canonical (分岐 A=56 / 分岐 B=57 本の id)
# 1) 新 navigable id set + 件数を再測定し frozen-census.txt の #BEGIN_ID_SET と FZ_ID_COUNT を実測値へ更新
ids_of_html() { perl -CSD -0777 -ne 'while (/<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g){ my $at=$2; while ($at =~ /(?:^|\s)id="([^"]*)"/g){ print "$1\n"; } }' "$1" | LC_ALL=C sort -u; }
ids_of_html "$CANON" | tee /tmp/new-id-set.txt | wc -l    # → FZ_ID_COUNT (分岐 A=56 / 分岐 B=57 を実測確認)
# 2) rich 資産 (xref/term/delta) を再測定し、 REQ 挿入で変わった分だけ FZ_XREF/FZ_TERM/FZ_DELTA を更新
#    (essence/statement を plain 寄りにすれば不変 = 31/27/5 のまま。 rich を足したら下記実測値へ)
c_xref()  { perl -CSD -0777 -ne 'my $n=0; while (/<a\b([^>]*)>/g){ my $a=$1; $n++ if $a =~ /(?:^|\s)class="(?:[^"]*\s)?xref(?:\s[^"]*)?"/; } print "$n\n";' "$1"; }
c_term()  { perl -CSD -0777 -ne 'my $n=()=(/<span class="term"[^>]*\sdata-term="/g); print "$n\n";' "$1"; }
c_delta() { perl -CSD -0777 -ne 'my $n=()=(/<(?:ins|del)\b[^>]*\bclass="delta"[^>]*\sdata-delta-id="/g); print "$n\n";' "$1"; }
echo "FZ_XREF=$(c_xref "$CANON") FZ_TERM=$(c_term "$CANON") FZ_DELTA=$(c_delta "$CANON")"   # frozen-census.txt へ反映
#    (必要なら esc_xref/code region/span region/jqs/JSON-LD も verify-verification.sh の census helper と同式で再測定)
# 3) provenance_contract_sha256 を新 contract の sha256 へ更新:
sha256sum contract/folio-verification.spec.yaml   # → verification.frozen-census.txt の provenance header へ
# 4) frozen-census.txt: FZ_ID_COUNT=<実測> (分岐 A=56/B=57)、 #BEGIN_ID_SET を /tmp/new-id-set.txt で置換、
#    FZ_XREF/FZ_TERM/FZ_DELTA 等を上記実測値へ、 #BEGIN_DELTA_SET は delta-id 不変なら据置
```

★数字上書き防壁 (census-guard.sh) は census 変更 ⟺ contract 変更の連結を要求するため、 census re-freeze は
必ず REQ 挿入 (contract 変更) と同一 commit で行う (naked census bump は census-guard が FAIL)。
provenance_contract_sha256 の更新を忘れると census-guard (1) が FAIL する。

## 3. canonical regen (folio build・admin land step・rebase 後)

REQ-VER-031 挿入後、 canonical verification.html を再生成する (fence: srpz land 後 rebase → build):

```bash
G=.claude-plugin/design-system/generator
bash $G/assemble-verification.sh $G/contract/folio-verification.spec.yaml design-intent/spec/verification.html.stage
bash $G/inject-prose.sh $G/prose/folio-verification.prose.yaml design-intent/spec/verification.html.stage design-intent/spec/verification.html
folio fix     # automark (data-term 注入)
folio build   # chrome + JSON-LD backlinks (dc:isReferencedBy) + index/nav 再生成
```

★逆順/interleave 禁止: canonical id が 55→56 (分岐 A) or 55→57 (分岐 B) に増えたのに census 未更新なら baseline 自己 RED = 偽 BLOCKED。
順序 = ① REQ 挿入 (contract・分岐 A/B 選択) → ② census re-freeze (実測値 56/57 へ・§2) → ③ canonical regen → ④ golden accept。
「arm 改修後なら H2 非発火」は arm land 後にのみ成立する条件付き主張。

## 3b. 政策A 恒久防御の CI (または hook) 配線 (admin land step・必須)

★**このステップを欠くと cell close 後に政策A の中核防御が消える** (finding2)。 現状 CI (`.github/workflows/ci.yml`)
で走る verification gate は **-drift 変種のみ** (`verify-verification-drift.sh` の byte 比較 + `test-adversarial-verification-drift.sh`)。
本 diff が追加/改修した恒久防御 (a)(c) の実体 —— verify-verification.sh §10b **frozen census arm**・
test-adversarial-verification.sh の **COLLAPSE / M-SELFCMP / F19 census 群**・**census-guard.sh** —— は **どれも ci.yml から
呼ばれていない** (grep 実測 = 0 参照)。 唯一の常設呼出しは cell-ephemeral な selftest-folio-7n17.local.sh (cell close で消える)。

★**drift gate では代替不能**: extractor-collapse は fresh 再生成も同様に collapse し byte 一致で PASS するため、
`verify-verification-drift.sh` は構造的に collapse を捕捉できない。 両側同時退行 (vacuous PASS) を捕捉する唯一の装置が
census arm / COLLAPSE test であり、 それが CI 非配線のままだと land 後に政策A の中核防御が無効化する。

admin は land step で以下を `ci.yml` の verification-gate job (F8 drift gate 群の隣) へ **blocking 配線**する:

```yaml
      # 政策A 恒久防御 (a)(c) の常設配線 (ADR-0053 / folio-7n17)。 drift gate が捕捉できない
      # 両側同時退行 (extractor-collapse の vacuous PASS) を frozen census + COLLAPSE 敵対 test で block する。
      - name: verification census/collapse 敵対回帰 (§10b frozen census arm + COLLAPSE + M-SELFCMP + F19 census 群)
        run: .claude-plugin/design-system/generator/test-adversarial-verification.sh
      # 数字上書き防壁: frozen census の裸の値変更 (契約変更を伴わない census bump = 退行 launder) を
      # base-ref coupling で block する。 base-ref は PR base の sha を渡す (push イベントは before sha)。
      - name: census-guard (数字上書き防壁・census 値変更 ⟺ contract 変更 coupling)
        run: .claude-plugin/design-system/generator/census-guard.sh "${{ github.event.pull_request.base.sha || github.event.before }}"
```

★注意点:
- `test-adversarial-verification.sh` は `SKIP_REPRO=1 SKIP_RENDER=1` の bash floor で ~10 分/suite。 CI では repro/render
  を CI 側の別 job (F6 recapture-parity 等) が担うため floor 実走で足りる (selftest と同型)。
- `census-guard.sh` の base-ref は **必ず PR base の sha** (merge-base 相当) を渡す (finding2)。 base-ref 省略時は
  coupling(2) を skip し provenance 整合(1) のみになる = 裸の census bump を捕捉できない。 shallow clone だと base sha が
  fetch されていない場合があるため、 checkout step に `fetch-depth: 0` (または base sha の明示 fetch) を確認する。
- CI 編集 (ci.yml) は **worker cell では scope-out** (受入(2)) ゆえ worker は ci.yml を触らない。 本配線は **admin 領分**
  (ADR-0053 §2.6/§3)。 admin が rebase 後の land step でここへ落とす。

## 4. golden accept

canonical 変更で inventory/prime golden が drift する (status/summary/doc-type flip と同型)。
`folio build` 後に inventory.json + prime golden を再受入 (status-flip-dirties-golden の教訓: flip commit に
golden 再生成を同梱)。

---

## worker cell が本 cell で完結させた分 (55 で self-consistent・selftest GREEN)

- verify-verification.sh §10b 凍結 literal census + §11 contract round-trip re-home
- test-adversarial-verification.sh F19 per-shape / M-SELFCMP (本番自己比較) / COLLAPSE (extractor-collapse)
- census-guard.sh (数字上書き防壁)
- spec-origin/verification.frozen-census.txt (凍結 census・id 55)
- ADR-0053 draft (drafts/ADR-0053-snapshot-oracle-evolution-policy.draft.html)
- selftest-folio-7n17.local.sh (fail-closed・snapshot hash pin + 非消費 assert + census-guard + 全 arm + 敵対 suite)
