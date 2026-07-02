export const meta = {
  name: 'srs-ceiling-oracle',
  description: 'SRS ceiling の differential oracle (dev-time 基準器・folio-mzn.1.5 S11): golden + 欠陥注入 fixture に対し JS 骨格で ceiling pipeline (floor→anchors→3 lens→refuter→commit-check) を走らせ、期待 verdict と detector 帰属を assert する。prose skill (folio-verify) 側の verdict との一致は compare-verdicts.sh が突合する。',
  whenToUse: 'dev-time 専用 (Workflow tool 明示有効化時のみ)。ceiling ensemble の較正 = ceiling 版 test-adversarial を回すとき、または folio-verify SKILL (prose-conduit) の trust gap を bound する differential 比較の JS 参照側を生成するとき。args: { oracleDir: "<abs path to generator/oracle>" }。事前に build-fixtures.sh で out/fixtures を生成しておく。',
  phases: [
    { title: 'Setup', detail: 'expected.json 読込 (期待 verdict SSoT)', model: 'sonnet' },
    { title: 'Floor', detail: 'fixture ごと: verify-srs (full render) + precheck + anchors', model: 'sonnet' },
    { title: 'Ceiling', detail: '3 lens 並列 (fidelity/persona-walk/completeness・opus・schema 強制)', model: 'opus' },
    { title: 'Refute', detail: 'GREEN 反転帯 finding を finding-refuter が敵対検証', model: 'opus' },
    { title: 'Adjudicate', detail: 'JS: remap+正規化 → ceiling-commit-check (機械 default-block)', model: 'sonnet' },
    { title: 'Report', detail: 'expected と assert・reference-verdicts.json を書出し', model: 'sonnet' },
  ],
}

// ─────────────────────────────────────────────────────────────────────────────
// 設計の核 (folio-mzn.1.5・維持すること):
//  (1) JS 骨格が folio-verify SKILL (prose 手順) と同じ pipeline を「決定的な配線」で回す基準器。
//      lens の .catch → ran_lenses 除外 → commit-check machinery≠clean BLOCKED の fail-closed 連鎖は
//      prose 手順より強い担保 = これが differential の参照側たる根拠 (prose-conduit trust gap を bound)。
//  (2) 機械は verdict を裁定しない: severity enum remap (blocker→critical 等の 1:1 対応) と件数・
//      集合の組成のみ JS が行い、GREEN 可否は ceiling-commit-check (default-block 述語) に委ねる。
//  (3) assert は verdict 級 (COMMIT=OK/BLOCKED) + detector 帰属 (期待 lens が GREEN 反転帯の未 refute
//      finding を ≥1 件) — finding の字面一致は求めない (LLM ensemble は非決定的・基準器が測るのは
//      verdict の安定性)。
//  (4) fan-out agent は model 明示 (sonnet=機械的 bash 実行 / opus=lens・refuter)。fable 不使用。
// ─────────────────────────────────────────────────────────────────────────────

// args は object 渡しが正だが、呼出し経路によっては JSON 文字列で届くため両対応 (防御的 parse)。
const ARGS = (typeof args === 'string') ? JSON.parse(args) : (args || {})
const ORACLE = ARGS.oracleDir || null
if (!ORACLE) throw new Error('args.oracleDir (generator/oracle の絶対パス) が必要')
const GEN = ORACLE.replace(/\/oracle\/?$/, '')
const BIN = GEN.replace(/\/design-system\/generator$/, '') + '/bin/folio'
const FIXDIR = `${ORACLE}/out/fixtures`

log(`[srs-ceiling-oracle] 開始 oracleDir=${ORACLE}`)

const MECH_NOTE = `あなたは機械的な実行 agent。指示された bash を dangerouslyDisableSandbox 不要の通常実行で回し、結果を構造化して返すだけ。判断・解釈・修復はしない。`

// ---- Setup: expected.json (期待 verdict SSoT) を読む ----
phase('Setup')
const EXPECTED_SCHEMA = {
  type: 'object', required: ['contract', 'fixtures'],
  properties: {
    contract: { type: 'string' },
    fixtures: { type: 'array', items: { type: 'object', required: ['name', 'expect_commit'], properties: {
      name: { type: 'string' }, expect_commit: { type: 'string', enum: ['OK', 'BLOCKED'] },
      expect_detector: { type: 'array', items: { type: 'string' } }, defect: { type: 'string' } } } },
  },
}
const expected = await agent(
  `${MECH_NOTE}\n${ORACLE}/expected.json を Read し、その内容 (contract / fixtures 配列) をそのまま構造化して返せ。_comment は捨ててよい。`,
  { label: 'setup:expected', phase: 'Setup', model: 'sonnet', effort: 'low', schema: EXPECTED_SCHEMA })
if (!expected) throw new Error('expected.json の読込に失敗')
const CONTRACT = `${GEN}/${expected.contract}`
log(`[srs-ceiling-oracle] fixtures ${expected.fixtures.length} 本・contract=${expected.contract}`)

// ---- lens 定義 (folio-verify SKILL §3 と同一の 3 lens + severity 語彙) ----
const LENSES = [
  { name: 'fidelity-srs', type: 'folio:fidelity-srs', flip: ['critical', 'high'], needsManifest: false },
  { name: 'persona-walk-srs', type: 'folio:persona-walk-srs', flip: ['blocker', 'major'], needsManifest: false },
  { name: 'completeness-critic-srs', type: 'folio:completeness-critic-srs', flip: ['critical', 'high'], needsManifest: true },
]
const REMAP = { blocker: 'critical', major: 'high', minor: 'medium', polish: 'low' } // persona native → canonical (1:1 enum remap)
const LENS_SCHEMA = {
  type: 'object', required: ['agent', 'findings'],
  properties: {
    agent: { type: 'string' },
    findings: { type: 'array', items: { type: 'object', required: ['id', 'severity', 'axis', 'location'], properties: {
      id: { type: 'string' }, severity: { type: 'string' }, axis: { type: 'string' },
      location: { type: 'string' }, note: { type: 'string', description: '観察の一行要約 (refuter への引継ぎ用)' } } } },
  },
}
const VERDICT_SCHEMA = {
  type: 'object', required: ['verdict', 'reasoning'],
  properties: { verdict: { type: 'string', enum: ['upheld', 'refuted', 'uncertain'] }, reasoning: { type: 'string' } },
}
const FLOOR_SCHEMA = {
  type: 'object', required: ['floor_rc', 'pc_rc'],
  properties: {
    floor_rc: { type: 'integer' }, pc_rc: { type: 'integer' },
    anchors_json: { type: 'string', description: 'ceiling-anchors の stdout (JSON 文字列)。失敗時は空文字' },
    note: { type: 'string' } },
}
const COMMIT_SCHEMA = {
  type: 'object', required: ['commit_rc', 'stdout'],
  properties: { commit_rc: { type: 'integer' }, stdout: { type: 'string' } },
}

// ---- fixture ごとの pipeline (barrier 無し・fixture 間は独立に流れる) ----
const results = await pipeline(
  expected.fixtures,

  // stage 1 (Floor): verify-srs full floor (render 込) + precheck + anchors — SKILL step 1-2 と同一。
  fx => agent(`${MECH_NOTE}
以下を順に bash で実行し結果を返せ (folio-verify SKILL step 1-2 と同一手順):
1. FLOOR="$(${BIN} verify-srs ${FIXDIR}/${fx.name}.html ${CONTRACT})"; floor_rc=$?
2. printf '%s' "$FLOOR" | ${BIN} ceiling-precheck; pc_rc=$?
3. ${BIN} ceiling-anchors ${CONTRACT} → stdout を anchors_json として返す (rc!=0 なら空文字)
floor は playwright render 込みで数分かかる。floor_rc / pc_rc / anchors_json を返せ。`,
    { label: `floor:${fx.name}`, phase: 'Floor', model: 'sonnet', schema: FLOOR_SCHEMA }),

  // stage 2 (Ceiling): 真の PENDING なら 3 lens 並列。machinery 失敗は null → ran から除外 (fail-closed)。
  (floor, fx) => {
    if (!floor || floor.pc_rc !== 0) {
      log(`[srs-ceiling-oracle] ${fx.name}: floor が真 PENDING でない (pc_rc=${floor ? floor.pc_rc : 'null'}) — ceiling へ進まない`)
      return { fx, floor, lenses: null }
    }
    const html = `${FIXDIR}/${fx.name}.html`
    return parallel(LENSES.map(L => () =>
      agent(`検証対象の生成 SRS プレゼン: ${html}
機械 SSoT contract: ${CONTRACT}${L.needsManifest ? `
anchor manifest (ceiling-anchors 出力・location→contract 解決に必須):
${floor.anchors_json}` : ''}
あなたの agent 定義のプロトコル通りに検証し、findings を構造化して返せ (清浄なら findings=[])。期待集合は必ず contract(SSoT) から取り、生成 HTML の DOM から作らない (verify-laundering 禁止)。`,
        { label: `lens:${fx.name}:${L.name}`, phase: 'Ceiling', agentType: L.type, model: 'opus', schema: LENS_SCHEMA })
        .then(r => ({ lens: L.name, flip: L.flip, result: r }))
        .catch(() => ({ lens: L.name, flip: L.flip, result: null }))
    )).then(lenses => ({ fx, floor, lenses }))
  },

  // stage 3 (Refute): GREEN 反転帯 (lens 別対応表) の finding を finding-refuter へ。
  (acc) => {
    if (!acc || !acc.lenses) return acc
    const { fx, floor, lenses } = acc
    const flips = []
    for (const L of lenses) {
      if (!L.result) continue
      for (const f of (L.result.findings || [])) {
        if (L.flip.includes(f.severity)) flips.push({ ...f, lens: L.lens })
      }
    }
    log(`[srs-ceiling-oracle] ${fx.name}: GREEN 反転帯 ${flips.length} 件を refute へ`)
    const html = `${FIXDIR}/${fx.name}.html`
    return parallel(flips.map(f => () =>
      agent(`Pass1 finding の敵対的検証 (あなたの agent 定義 §4 の axis 別 anchor に従う):
finding: ${JSON.stringify(f)}
出所 lens: ${f.lens} (axis=${f.axis})
生成 HTML: ${html}
contract (SSoT): ${CONTRACT}
anchor manifest: ${floor.anchors_json}
verdict (upheld/refuted/uncertain) を返せ。`,
        { label: `refute:${fx.name}:${f.lens}:${f.id}`, phase: 'Refute', agentType: 'folio:finding-refuter', model: 'opus', schema: VERDICT_SCHEMA })
        .then(v => ({ key: `${f.lens}:${f.id}`, verdict: v ? v.verdict : null }))
        .catch(() => ({ key: `${f.lens}:${f.id}`, verdict: null }))
    )).then(verdicts => ({ ...acc, verdicts }))
  },

  // stage 4 (Adjudicate): JS で remap+正規化 → ceiling-commit-check (機械 default-block)。
  (acc) => {
    if (!acc || !acc.lenses) return acc
    const { fx, verdicts } = acc
    const vmap = {}
    for (const v of (verdicts || [])) vmap[v.key] = v.verdict
    const ran = acc.lenses.filter(L => L.result).map(L => L.lens)
    const findings = []
    for (const L of acc.lenses) {
      if (!L.result) continue
      for (const f of (L.result.findings || [])) {
        const canonical = REMAP[f.severity] || f.severity
        const entry = { id: `${L.lens}:${f.id}`, agent: L.lens, severity: canonical }
        const v = vmap[`${L.lens}:${f.id}`]
        if (v) entry.verdict = v
        findings.push(entry)
      }
    }
    const normalized = {
      expected_lenses: LENSES.map(L => L.name),
      ran_lenses: ran,
      floor: 'PENDING',
      findings,
    }
    return agent(`${MECH_NOTE}
以下の JSON を一時ファイルに書き (mktemp)、次を実行して commit_rc と stdout を返せ:
  ${BIN} ceiling-commit-check <一時ファイル>; commit_rc=$?
JSON (これをそのまま・一切変更せずファイルへ):
${JSON.stringify(normalized)}`,
      { label: `commit:${fx.name}`, phase: 'Adjudicate', model: 'sonnet', effort: 'low', schema: COMMIT_SCHEMA })
      .then(c => ({ ...acc, normalized, commit: c }))
  }
)

// ---- Report: expected と assert し、reference を書き出す ----
phase('Report')
// bytes 結合 (独立 ceiling wf_3f5ce994 B3): JS アームが検証した fixture/contract の sha256 を perFixture へ
// 埋め、comparator が three-way (reference == 現物 == verify-state) で「両経路が同一 bytes を検証した」を
// fail-closed に担保できるようにする。hash は同一 run 内で計測する (fixtures は build-fixtures.sh 以外に
// 書き手が無く run 中は不変)。hash agent が死んだら 'missing' → comparator が STALE で fail (fail-closed)。
const HASH_SCHEMA = {
  type: 'object', required: ['contract_sha256', 'fixtures'],
  properties: {
    contract_sha256: { type: 'string' },
    fixtures: { type: 'array', items: { type: 'object', required: ['name', 'html_sha256'], properties: { name: { type: 'string' }, html_sha256: { type: 'string' } } } },
  },
}
const hashes = await agent(`${MECH_NOTE}
次のファイルの sha256 を sha256sum で計算し構造化して返せ:
- contract: ${CONTRACT} → contract_sha256
- fixtures (name は拡張子無し basename): ${expected.fixtures.map(f => `${FIXDIR}/${f.name}.html`).join(' , ')}`,
  { label: 'report:hashes', phase: 'Report', model: 'sonnet', effort: 'low', schema: HASH_SCHEMA }).catch(() => null)
const hmap = {}
if (hashes) for (const h of (hashes.fixtures || [])) hmap[h.name] = h.html_sha256
const perFixture = []
let allPass = true
for (let i = 0; i < expected.fixtures.length; i++) {
  const fx = expected.fixtures[i]
  const r = results[i]
  const entry = { fixture: fx.name, expect_commit: fx.expect_commit }
  if (!r || !r.lenses || !r.commit) {
    entry.actual_commit = null
    entry.machinery = !r ? 'pipeline-null' : (!r.lenses ? `floor-not-pending (pc_rc=${r.floor ? r.floor.pc_rc : 'null'})` : 'commit-check-null')
    entry.pass = false
  } else {
    entry.actual_commit = r.commit.commit_rc === 0 ? 'OK' : (r.commit.commit_rc === 1 ? 'BLOCKED' : `TOOL-ERROR(rc=${r.commit.commit_rc})`)
    entry.ran_lenses = r.normalized.ran_lenses
    entry.findings = r.normalized.findings
    let pass = entry.actual_commit === fx.expect_commit
    if (pass && fx.expect_commit === 'BLOCKED' && fx.expect_detector && fx.expect_detector.length) {
      const hit = r.normalized.findings.some(f =>
        fx.expect_detector.includes(f.agent) && ['critical', 'high'].includes(f.severity) && f.verdict !== 'refuted')
      entry.detector_hit = hit
      if (!hit) pass = false
    }
    entry.pass = pass
  }
  entry.html_hash = hmap[fx.name] || 'missing'
  entry.contract_hash = (hashes && hashes.contract_sha256) || 'missing'
  allPass = allPass && entry.pass
  perFixture.push(entry)
  log(`[srs-ceiling-oracle] ${fx.name}: expect=${fx.expect_commit} actual=${entry.actual_commit} → ${entry.pass ? 'PASS' : 'FAIL'}`)
}

// allPass を reference に永続化 (独立 ceiling wf_3161e4a6 B2): comparator が「JS 側の defect-injection
// proof 合格」を fail-closed に検査できるようにする (return 値だけの ephemeral にしない)。
const reference = { oracle: 'srs-ceiling-oracle', contract: expected.contract, allPass, perFixture }
await agent(`${MECH_NOTE}
以下の JSON を ${ORACLE}/out/reference-verdicts.json へそのまま書き込め (mkdir -p 不要・out は既存)。書込み後に cat で内容を確認して "written" と返せ。
${JSON.stringify(reference, null, 2)}`,
  { label: 'report:write-reference', phase: 'Report', model: 'sonnet', effort: 'low' })

log(`[srs-ceiling-oracle] 完了: ${allPass ? '全 fixture PASS (defect-injection proof 成立)' : 'FAIL あり — ceiling 較正のズレか fixture/機構の欠陥'}`)
return { allPass, perFixture }
