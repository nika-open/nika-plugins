export const meta = {
  name: 'nika-forge',
  description: 'Build one Nika workflow from a plan the person approved: gather the facts, write it phase by phase, review it cold, repair at most twice, report with the check verdict',
  whenToUse: 'After the person approved the plan of a new workflow and the job is long enough to be worth several agents. It asks no question and answers no gate. Its one run is the reviewer\'s rehearsal on the mock model, only when nothing leaves the machine: the tools and the writes of that rehearsal are real. Otherwise the plan is read with a dry run, which executes nothing.',
  phases: [
    { title: 'Design', detail: 'the engine reads the sentence, a scout gathers the facts the design depends on' },
    { title: 'Write', detail: 'the author role builds the file phase by phase, a check after each' },
    { title: 'Review', detail: 'the reviewer role judges the file from the sentence and the path alone, and rehearses it' },
    { title: 'Repair', detail: 'at most two rounds, each finding sent back with its evidence' },
    { title: 'Report', detail: 'path, check exit, counts, the verdict in the reviewer\'s words' },
  ],
}

// args: { intent: string, file?: string, approved?: string }
//   intent    the person's sentence, word for word
//   file      where to write (default: workflows/<kebab-name>.nika)
//   approved  the effects the person approved at the plan gate, as the card
//             printed them. Without it, only what the sentence names is built.
const intent = args && typeof args.intent === 'string' ? args.intent.trim() : ''
if (!intent) {
  return { built: false, reason: 'No sentence given. Pass { intent: "<the person\'s sentence, unchanged>" }.' }
}
const target = (args && args.file) || 'workflows/<kebab-name>.nika'
const approved = (args && args.approved) || 'only the sources, files, hosts and models the sentence names'

const EFFECTS =
  `The person approved these effects and no others: ${approved}. ` +
  'Craft that widens nothing is yours to add: validation of what the job reads, state between runs, dedupe, ' +
  'a bounded fan-out, retry with a marked degraded result, typed schemas with max_tokens, a run report. ' +
  'A new send, host, paid model, seat route, program, MCP server or a write outside their folder is never added: ' +
  'list it under offers, with one line on what it would bring. Never answer a human gate and never create a consent.'

const FACTS = {
  type: 'object',
  required: ['engine_exit', 'pieces', 'questions', 'facts'],
  properties: {
    engine_exit: { type: 'integer' },
    pieces: { type: 'array', items: { type: 'string' } },
    questions: { type: 'array', items: { type: 'string' } },
    facts: { type: 'array', items: { type: 'string' } },
    existing_workflows: { type: 'array', items: { type: 'string' } },
  },
}
const BUILT = {
  type: 'object',
  required: ['file', 'check_exit', 'clean', 'tasks', 'findings_left', 'offers', 'check_verdict'],
  properties: {
    file: { type: 'string' },
    check_exit: { type: 'integer' },
    clean: { type: 'boolean' },
    tasks: { type: 'integer' },
    builtins: { type: 'array', items: { type: 'string' } },
    findings_left: { type: 'array', items: { type: 'string' } },
    offers: { type: 'array', items: { type: 'string' } },
    check_verdict: { type: 'string' },
  },
}
const REVIEW = {
  type: 'object',
  required: ['verdict', 'check_exit', 'words', 'findings', 'not_verified', 'rehearsal'],
  properties: {
    verdict: { type: 'string', enum: ['ship', 'repair', 'rethink'] },
    check_exit: { type: 'integer' },
    tasks: { type: 'integer' },
    words: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['what', 'evidence'],
        properties: { what: { type: 'string' }, evidence: { type: 'string' } },
      },
    },
    not_verified: { type: 'array', items: { type: 'string' } },
    rehearsal: { type: 'string', enum: ['mock', 'dry-run', 'none'] },
    artifacts_parsed: { type: 'array', items: { type: 'string' } },
  },
}

const review = (file, label, group) =>
  agent(
    `Review the Nika workflow at ${file}. The person asked for this, word for word: "${intent}". ` +
      'You are given nothing else on purpose. Take every fact from `nika check <file> --json --native-strict` and ' +
      '`nika inspect <file> --format json`. Rehearse with `nika run <file> --model mock/echo --max-cost-usd 0.10` only when nothing ' +
      'leaves the machine, then open and parse every file the rehearsal wrote; otherwise read the plan with ' +
      '`nika run <file> --dry-run` and say the effects were not exercised. ' +
      'Return ship, repair or rethink, your verdict in two or three sentences of your own, one evidence line per finding, ' +
      'and what you could not verify.',
    { label, phase: group, agentType: 'nika:nika-reviewer', schema: REVIEW },
  )

phase('Design')
const facts = await agent(
  `Gather what a design needs for this request, and design nothing: "${intent}". ` +
    'Run `nika compile --json -- "<the sentence>"` (no model is called and nothing is written) and report its exit code, ' +
    'the pieces it read and every question it marks as required. Then look up what the job depends on: the shape of the ' +
    'files or pages it reads (first lines only), workflows in the project that already do part of it (`nika list`, `*.nika`), ' +
    'and the builtins that fit (`nika catalog --tools`). Each fact is one line with where you read it. Read only; a name you did not see printed is not a fact.',
  { label: 'facts', agentType: 'nika:nika-scout', schema: FACTS },
)
if (!facts) {
  return { built: false, reason: 'The scout gave no result. Nothing was written.' }
}
if (facts.questions.length) {
  log(`${facts.questions.length} question(s) only the person can answer: nothing was written`)
  return { built: false, reason: 'The engine asks questions only the person can answer.', questions: facts.questions, pieces: facts.pieces }
}

phase('Write')
let built = await agent(
  `Write the Nika workflow for this request, unchanged: "${intent}". Target file: ${target}. ` +
    `Facts already gathered, each with its source:\n- ${facts.facts.join('\n- ')}\n` +
    `Pieces the engine read:\n- ${facts.pieces.join('\n- ')}\n` +
    `${EFFECTS} ` +
    'Build phase by phase (gather, normalize, judge, act, report) and run `nika check <file> --json --native-strict` after each phase, ' +
    'repairing what it finds before the next. Do not run the workflow: the reviewer rehearses it. ' +
    'Report the exit code of the last check and quote its verdict.',
  { label: 'author', agentType: 'nika:nika-author', schema: BUILT },
)
if (!built) {
  return { built: false, reason: 'The author gave no result. Look for a half-written file before starting again.', target }
}

phase('Review')
let verdict = await review(built.file, 'review', 'Review')

phase('Repair')
let rounds = 0
while (verdict && verdict.verdict === 'repair' && rounds < 2) {
  rounds += 1
  const repaired = await agent(
    `Repair the Nika workflow at ${built.file}. The person asked for: "${intent}". ` +
      `A reviewer returned these findings, each with its evidence:\n- ${verdict.findings.map(f => `${f.what} (${f.evidence})`).join('\n- ')}\n` +
      `${EFFECTS} Repair each finding, run \`nika check <file> --json --native-strict\` and do not run the workflow. ` +
      'Report the exit code of the last check with its verdict quoted. A finding you leave is named, with the reason.',
    { label: `repair ${rounds}`, phase: 'Repair', agentType: 'nika:nika-author', schema: BUILT },
  )
  if (!repaired) {
    log(`repair round ${rounds} gave no result: the file is as the review found it`)
    break
  }
  built = repaired
  verdict = await review(built.file, `review after repair ${rounds}`, 'Repair')
}

phase('Report')
const disagree = Boolean(verdict) && verdict.check_exit !== built.check_exit
if (disagree) {
  log(`the author reports check exit ${built.check_exit}, the reviewer ${verdict.check_exit}: run the check yourself before handing over`)
}
if (verdict && verdict.verdict === 'repair') {
  log('two repair rounds were used and findings remain: they are listed, not hidden')
}
return {
  built: true,
  file: built.file,
  check_exit: built.check_exit,
  check_verdict: built.check_verdict,
  clean: built.clean,
  tasks: built.tasks,
  builtins: built.builtins || [],
  rehearsal: verdict ? verdict.rehearsal : 'none',
  artifacts_parsed: (verdict && verdict.artifacts_parsed) || [],
  findings_left_by_the_author: built.findings_left,
  review: verdict
    ? { verdict: verdict.verdict, words: verdict.words, findings: verdict.findings, not_verified: verdict.not_verified, check_exit: verdict.check_exit }
    : { verdict: 'none', words: 'The reviewer gave no result: this file was not reviewed.', findings: [], not_verified: [] },
  repair_rounds: rounds,
  check_exits_disagree: disagree,
  offers: built.offers,
  next: 'Run `nika check` on the file yourself, show the person the verdict and the offers, and let them decide on a real run.',
}
