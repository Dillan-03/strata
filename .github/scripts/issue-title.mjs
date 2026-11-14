export const PREFIXES = ['Feature', 'Bug', 'Chore'];

const VALID = /^\[(Feature|Bug|Chore)\] \S/;

const ALIASES = new Map([
  ['feature', 'Feature'],
  ['feat', 'Feature'],
  ['enhancement', 'Feature'],
  ['bug', 'Bug'],
  ['fix', 'Bug'],
  ['bugfix', 'Bug'],
  ['chore', 'Chore'],
]);

const LOOSE_PREFIX = /^\s*[[(]?\s*([a-z]+)\s*[\])]?\s*[:\-–—]?\s+(.+)$/i;

export function classify(rawTitle) {
  const title = (rawTitle ?? '').trim();

  if (VALID.test(title)) {
    return { valid: true, title };
  }

  const match = title.match(LOOSE_PREFIX);
  if (match) {
    const prefix = ALIASES.get(match[1].toLowerCase());
    const rest = match[2].trim();
    if (prefix && rest.length > 0) {
      return { valid: false, corrected: `[${prefix}] ${rest}`, title };
    }
  }

  return { valid: false, title };
}

export function guidance(title) {
  return [
    `This issue title doesn't follow the required format: \`${title.replace(/`/g, "'")}\``,
    '',
    'Every title must start with exactly one of:',
    '',
    ...PREFIXES.map((prefix) => `- \`[${prefix}] \``),
    '',
    'For example: `[Feature] Implement skills inspector` or `[Bug] Fix duplicate MCP server detection`.',
    'Edit the title and this check will run again.',
  ].join('\n');
}
