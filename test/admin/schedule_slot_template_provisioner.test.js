const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  CANONICAL_TEMPLATES,
  parseArgs,
  sameTemplate,
} = require('../../tool/provision_schedule_slot_templates');

test('canonical hourly template set is exactly the frozen thirteen slot IDs', () => {
  assert.deepEqual(CANONICAL_TEMPLATES.map((template) => template.slotId), [
    '0800', '0900', '1000', '1100', '1200', '1300', '1400',
    '1500', '1600', '1700', '1800', '1900', '2000',
  ]);
  assert.deepEqual(CANONICAL_TEMPLATES.map((template) => template.sequence),
    Array.from({ length: 13 }, (_, index) => index));
  assert.deepEqual(
    Object.keys(CANONICAL_TEMPLATES[0]).sort(),
    ['active', 'schemaVersion', 'sequence', 'slotId'],
  );
});

test('template comparison is idempotent and rejects unexpected content', () => {
  const expected = CANONICAL_TEMPLATES[1];
  assert.equal(sameTemplate({ ...expected }, expected), true);
  assert.equal(sameTemplate({ ...expected, active: false }, expected), false);
  assert.equal(sameTemplate({ ...expected, note: 'unexpected' }, expected), false);
});

test('provisioning remains dry-run unless --apply is explicit', () => {
  const dryRun = parseArgs(['--project-id', 'demo-project']);
  assert.equal(dryRun.apply, false);
  assert.throws(
    () => parseArgs(['--project-id', 'demo-project', '--apply']),
    /--apply requires --operator/,
  );
  const apply = parseArgs([
    '--project-id', 'demo-project', '--apply', '--operator', 'release-operator',
  ]);
  assert.equal(apply.apply, true);
});
