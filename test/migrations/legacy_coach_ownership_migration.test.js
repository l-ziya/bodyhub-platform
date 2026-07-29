'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const {
  LegacyCoachOwnershipMigrator,
  rollbackMigration,
} = require('../../tool/migrate_legacy_coach_ownership');

const projectId = 'bodyhub-legacy-coach-migration-tests';
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is required for migration tests.');

const app = admin.initializeApp({ projectId }, 'legacy-coach-migration-tests');
const db = getFirestore(app);

async function clear() {
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.equal(response.status, 200);
}

async function seed(documents) {
  const batch = db.batch();
  for (const [documentPath, data] of Object.entries(documents)) batch.set(db.doc(documentPath), data);
  await batch.commit();
}

function outputDirectory() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'bodyhub-coach-id-migration-'));
}

async function migrate(overrides = {}) {
  const migrator = new LegacyCoachOwnershipMigrator(db, {
    projectId,
    outputDir: outputDirectory(),
    errorThreshold: 1,
    ...overrides,
  });
  const summary = await migrator.run();
  return { migrator, summary };
}

test.beforeEach(async () => clear());
test.after(() => app.delete());

test('safely backfills a legacy booking and writes the required reports', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'bookings/booking-a': { studentId: 'student-a', status: 'pending' },
  });
  const { migrator, summary } = await migrate({ mode: 'apply' });
  assert.equal((await db.doc('bookings/booking-a').get()).get('coachId'), 'coach-a');
  assert.equal(summary.updated, 1);
  for (const name of ['records.jsonl', 'records.csv', 'rollback.jsonl', 'summary.json', 'checkpoint.json']) {
    assert.equal(fs.existsSync(path.join(migrator.runDirectory, name)), true, name);
  }
  const persistedSummary = JSON.parse(fs.readFileSync(path.join(migrator.runDirectory, 'summary.json')));
  assert.equal(persistedSummary.migrationVersion, 'legacy-coach-ownership-v1');
  assert.equal(persistedSummary.projectId, projectId);
});

test('leaves correct existing ownership untouched and reports conflicts', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'bookings/correct': { studentId: 'student-a', coachId: 'coach-a' },
    'bookings/conflict': { studentId: 'student-a', coachId: 'coach-b' },
  });
  const { summary } = await migrate({ mode: 'apply' });
  assert.equal((await db.doc('bookings/correct').get()).get('coachId'), 'coach-a');
  assert.equal((await db.doc('bookings/conflict').get()).get('coachId'), 'coach-b');
  assert.equal(summary.alreadyCorrect, 1);
  assert.equal(summary.conflicts, 1);
});

test('skips missing, unassigned, and pending student profiles', async () => {
  await seed({
    'bookings/no-profile': { studentId: 'missing' },
    'student_profiles/no-coach': { status: 'active' },
    'bookings/no-coach': { studentId: 'no-coach' },
    'student_profiles/pending': { status: 'pending', coachId: 'coach-a' },
    'bookings/pending': { studentId: 'pending' },
  });
  const { summary } = await migrate({ mode: 'apply' });
  assert.equal(summary.skipped, 3);
  for (const id of ['no-profile', 'no-coach', 'pending']) {
    assert.equal((await db.doc(`bookings/${id}`).get()).get('coachId'), undefined);
  }
});

test('requires a matching source lesson before backfilling lesson requests', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'lessons/lesson-b': { studentId: 'student-a', coachId: 'coach-b' },
    'lesson_change_requests/request-a': { studentId: 'student-a', lessonId: 'lesson-b', status: 'pending' },
  });
  const { summary } = await migrate({ mode: 'apply' });
  assert.equal(summary.conflicts, 1);
  assert.equal((await db.doc('lesson_change_requests/request-a').get()).get('coachId'), undefined);
});

test('reports student_packages document ID and studentId mismatches for manual review', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'student_packages/student-a': { studentId: 'student-b', status: 'active' },
  });
  const { summary } = await migrate({ mode: 'apply' });
  assert.equal(summary.conflicts, 1);
  assert.equal((await db.doc('student_packages/student-a').get()).get('coachId'), undefined);
});

test('treats a concurrent update as a precondition failure and does not overwrite it', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'availabilities/availability-a': { studentId: 'student-a', active: true },
  });
  const { summary } = await migrate({
    mode: 'apply',
    beforeWrite: async (doc) => doc.ref.update({ coachId: 'coach-concurrent' }),
  });
  assert.equal(summary.failed, 1);
  assert.equal((await db.doc('availabilities/availability-a').get()).get('coachId'), 'coach-concurrent');
});

test('is idempotent on a second run', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'package_requests/request-a': { studentId: 'student-a', status: 'pending' },
  });
  await migrate({ mode: 'apply' });
  const { summary } = await migrate({ mode: 'apply' });
  assert.equal(summary.updated, 0);
  assert.equal(summary.alreadyCorrect, 1);
});

test('continues from a saved checkpoint only when explicitly resumed', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'student_profiles/student-b': { status: 'active', coachId: 'coach-b' },
    'bookings/booking-a': { studentId: 'student-a' },
    'bookings/booking-b': { studentId: 'student-b' },
  });
  const first = await migrate({ mode: 'apply', pageSize: 1, limit: 1 });
  assert.equal((await db.doc('bookings/booking-a').get()).get('coachId'), 'coach-a');
  assert.equal((await db.doc('bookings/booking-b').get()).get('coachId'), undefined);
  const resumed = new LegacyCoachOwnershipMigrator(db, {
    projectId,
    outputDir: path.dirname(first.migrator.runDirectory),
    runId: path.basename(first.migrator.runDirectory),
    runDirectory: first.migrator.runDirectory,
    mode: 'apply', pageSize: 1, errorThreshold: 1, resume: true,
  });
  await resumed.run();
  assert.equal((await db.doc('bookings/booking-b').get()).get('coachId'), 'coach-b');
});

test('rolls back only unchanged migration writes', async () => {
  await seed({
    'student_profiles/student-a': { status: 'active', coachId: 'coach-a' },
    'student_profiles/student-b': { status: 'active', coachId: 'coach-b' },
    'bookings/rollback-safe': { studentId: 'student-a' },
    'bookings/rollback-conflict': { studentId: 'student-b' },
  });
  const { migrator } = await migrate({ mode: 'apply' });
  await db.doc('bookings/rollback-conflict').update({ coachId: 'manual-coach' });
  const result = await rollbackMigration(db, { rollback: migrator.runDirectory, outputDir: path.dirname(migrator.runDirectory) });
  assert.equal(result.rolledBack, 1);
  assert.equal(result.skipped, 1);
  assert.equal((await db.doc('bookings/rollback-safe').get()).get('coachId'), undefined);
  assert.equal((await db.doc('bookings/rollback-conflict').get()).get('coachId'), 'manual-coach');
});
