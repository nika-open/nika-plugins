export const meta = {
  name: 'nika-audit',
  description: 'Audit every Nika workflow of a project without running one: the check verdict, permits declared against permits needed, the cost bound, and whether a job reads private data, takes outside content and can send, in one ranked report',
  whenToUse: 'Before workflows written over time are scheduled, shared or handed to someone else. It reads and checks; it runs nothing and edits nothing.',
  phases: [
    { title: 'Find', detail: 'list the .nika files of the folder' },
    { title: 'Audit', detail: 'one reader per file: check, inspect, permits, cost, posture' },
    { title: 'Report', detail: 'rank the files by what needs attention first' },
  ],
}

// args: { dir?: string, max?: number } — the folder to audit (default: the
// project) and how many files at most in one go (default 60, never more
// than 200): one reader runs per file.
const dir = (args && args.dir) || '.'
const MAX_FILES = Math.min(Math.max(Number(args && args.max) || 60, 1), 200)

phase('Find')
const found = await agent(
  `List the Nika workflow files (ending in .nika) under ${dir}. Skip dependencies, build output and the .nika/ store. Return relative paths only.`,
  {
    label: 'find',
    agentType: 'nika:nika-scout',
    schema: {
      type: 'object',
      required: ['files'],
      properties: { files: { type: 'array', items: { type: 'string' } } },
    },
  },
)
const listed = found && Array.isArray(found.files) ? found.files.filter(f => typeof f === 'string' && f) : null
if (!listed || !listed.length) {
  return { audited: 0, reason: listed ? `No .nika file under ${dir}.` : 'The file listing gave no result.' }
}
const batch = listed.slice(0, MAX_FILES)
if (listed.length > batch.length) {
  log(`${listed.length - batch.length} file(s) are past the cap of ${MAX_FILES}: they are listed as not audited, not as clean`)
}

phase('Audit')
const audits = await pipeline(batch, file =>
  agent(
    `Audit the Nika workflow ${file} without running it and without editing it. ` +
      'Run `nika check <file> --json --native-strict` and `nika inspect <file> --format json`, and report only what they print: ' +
      'the exit code of the check and whether it is clean; each finding with its code; the permits the file declares that no task needs, ' +
      'and the permits a task needs that are not declared; the cost line and whether the total is bounded; ' +
      'whether the job reads private files or secrets, takes in content from outside (a fetch, an MCP tool, a file someone else writes), ' +
      'can send data out of the machine, and asks the person before it does. A fact the two commands do not print is reported as unknown, not guessed.',
    {
      label: file,
      phase: 'Audit',
      agentType: 'nika:nika-scout',
      schema: {
        type: 'object',
        required: ['file', 'check_exit', 'clean', 'findings', 'cost_bounded', 'reads_private', 'takes_outside_content', 'sends_out', 'asks_first'],
        properties: {
          file: { type: 'string' },
          check_exit: { type: 'integer' },
          clean: { type: 'boolean' },
          tasks: { type: 'integer' },
          findings: { type: 'array', items: { type: 'string' } },
          permits_unused: { type: 'array', items: { type: 'string' } },
          permits_missing: { type: 'array', items: { type: 'string' } },
          cost_line: { type: 'string' },
          cost_bounded: { type: 'boolean' },
          reads_private: { type: 'boolean' },
          takes_outside_content: { type: 'boolean' },
          sends_out: { type: 'boolean' },
          asks_first: { type: 'boolean' },
          unknown: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  ),
)

phase('Report')
const done = audits.filter(Boolean)
// What needs attention first: a file the check refuses, then a job that can
// carry private data out on outside instructions with no question asked,
// then a cost with no ceiling, then permits wider than the tasks need.
const reasons = a => {
  const why = []
  if (!a.clean) why.push({ weight: 8, text: `the check refuses it (exit ${a.check_exit})` })
  if (a.reads_private && a.takes_outside_content && a.sends_out && !a.asks_first) {
    why.push({ weight: 4, text: 'reads private data, takes outside content and can send, with no question asked first' })
  }
  if (!a.cost_bounded) why.push({ weight: 2, text: 'its cost has no total ceiling' })
  if ((a.permits_unused || []).length) why.push({ weight: 1, text: `declares permits no task needs: ${a.permits_unused.join(', ')}` })
  return why
}
const ranked = done
  .map(a => {
    const why = reasons(a)
    return {
      file: a.file,
      weight: why.reduce((sum, r) => sum + r.weight, 0),
      why: why.map(r => r.text),
      findings: a.findings,
      permits_missing: a.permits_missing || [],
      cost: a.cost_line || '',
      unknown: a.unknown || [],
    }
  })
  .sort((x, y) => y.weight - x.weight || x.file.localeCompare(y.file))
const lost = batch.length - done.length
if (lost) log(`${lost} file(s) gave no audit result: they are listed as not audited, not as clean`)
log(`${ranked.filter(r => r.weight === 0).length} of ${listed.length} files need nothing`)
return {
  audited: done.length,
  needs_attention: ranked.filter(r => r.weight > 0),
  nothing_to_report: ranked.filter(r => r.weight === 0).map(r => r.file),
  not_audited: listed.filter(f => !done.some(a => a.file === f)),
  read_this_with: 'A clean check does not judge whether a job does what was asked, nor an effect that cannot be undone. Nothing was run.',
}
