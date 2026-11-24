export const meta = {
  name: 'port-to-nika',
  description: 'Port many workflow files (n8n JSON, Agent Builder exports, shell or Python scripts) to checked .nika files, one agent per file, with a parity report',
  phases: ['Find', 'Port', 'Report'],
}

// args: { dir?: string, pattern?: string } — where to look and what to port.
const dir = (args && args.dir) || '.'
const pattern = (args && args.pattern) || 'workflow exports and automation scripts'

phase('Find')
const found = await agent(
  `List the files under ${dir} that describe an automation to port: ${pattern}. ` +
    'Skip dependencies, build output and anything already ending in .nika. Return relative paths only.',
  {
    schema: {
      type: 'object',
      required: ['files'],
      properties: { files: { type: 'array', items: { type: 'string' } } },
    },
  },
)

phase('Port')
const ports = await pipeline(found.files, file =>
  agent(
    `Port ${file} to a Nika workflow. Load the nika-migration skill first. ` +
      'Write the result beside the source as <name>.nika, keep permits to what the steps really touch, ' +
      'then run `nika check <name>.nika --native-strict --json` and repair until `clean` is true or three rounds have passed. ' +
      'Do not run it: porting ends at a clean check, and running stays the user\'s choice through /nika:run. Report honestly what could not be ported (a loop with an open condition, a chat interface, a remote connector).',
    {
      label: file,
      schema: {
        type: 'object',
        required: ['source', 'nika_file', 'clean', 'not_ported'],
        properties: {
          source: { type: 'string' },
          nika_file: { type: 'string' },
          clean: { type: 'boolean' },
          remaining_findings: { type: 'array', items: { type: 'string' } },
          not_ported: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  ),
)

phase('Report')
const done = ports.filter(Boolean)
const clean = done.filter(p => p.clean)
log(`${clean.length} of ${found.files.length} files ported and clean`)
return {
  found: found.files.length,
  ported_clean: clean.map(p => p.nika_file),
  needs_work: done.filter(p => !p.clean).map(p => ({ file: p.source, findings: p.remaining_findings || [] })),
  not_ported: done.filter(p => p.not_ported.length).map(p => ({ file: p.source, parts: p.not_ported })),
  agents_that_gave_no_result: found.files.length - done.length,
}
