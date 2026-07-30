'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');

const projectId = 'bodyhub-busy-lock-tests';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost) throw new Error('FIRESTORE_EMULATOR_HOST is required.');

const app = admin.initializeApp({ projectId }, 'busy-lock-transaction-harness');
const db = getFirestore(app);
const start = new Date('2030-01-01T09:00:00.000Z');

function blockStarts(sessionStart = start) {
  return Array.from({ length: 5 }, (_, index) =>
    new Date(sessionStart.getTime() + index * 10 * 60 * 1000));
}

function id(ownerId, blockStart) {
  return `${ownerId}_${blockStart.getTime()}`;
}

function refs(collectionName, ownerId, sessionStart = start) {
  return blockStarts(sessionStart).map((blockStart) =>
    db.collection(collectionName).doc(id(ownerId, blockStart)));
}

async function clear() {
  const response = await fetch(
    `http://${firestoreHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.equal(response.status, 200);
}

async function reserve({ sessionId, coachId, studentId, sessionStart = start, failAfterReads = false }) {
  const coachRefs = refs('coach_busy_blocks', coachId, sessionStart);
  const studentRefs = refs('student_busy_blocks', studentId, sessionStart);
  await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all([...coachRefs, ...studentRefs].map((reference) => transaction.get(reference)));
    if (snapshots.some((snapshot) => snapshot.exists)) {
      throw new Error('busy_lock_collision');
    }
    if (failAfterReads) throw new Error('intentional_rollback');
    [...coachRefs, ...studentRefs].forEach((reference, index) => {
      transaction.create(reference, {
        ownerId: index < 5 ? coachId : studentId,
        sessionId,
        startAt: sessionStart,
        blockStart: blockStarts(sessionStart)[index % 5],
        blockIndex: index % 5,
        schemaVersion: 2,
      });
    });
  });
}

async function count(collectionName) {
  return (await db.collection(collectionName).get()).size;
}

test.beforeEach(async () => clear());
test.after(() => app.delete());

test('one confirmed 50-minute Session reserves exactly five Coach and five Student locks', async () => {
  await reserve({ sessionId: 'session-a', coachId: 'coach-a', studentId: 'student-a' });
  assert.equal(await count('coach_busy_blocks'), 5);
  assert.equal(await count('student_busy_blocks'), 5);
  assert.equal((await db.doc('coach_busy_blocks/coach-a_1893488400000').get()).get('sessionId'), 'session-a');
  assert.equal((await db.doc('student_busy_blocks/student-a_1893488400000').get()).get('blockIndex'), 0);
});

test('Coach or Student collisions reject atomically without overwriting another Session', async () => {
  await reserve({ sessionId: 'session-a', coachId: 'coach-a', studentId: 'student-a' });
  await assert.rejects(
    reserve({ sessionId: 'session-b', coachId: 'coach-a', studentId: 'student-b' }),
    /busy_lock_collision/,
  );
  await assert.rejects(
    reserve({ sessionId: 'session-c', coachId: 'coach-b', studentId: 'student-a' }),
    /busy_lock_collision/,
  );
  assert.equal(await count('coach_busy_blocks'), 5);
  assert.equal(await count('student_busy_blocks'), 5);
  assert.equal((await db.doc('coach_busy_blocks/coach-a_1893488400000').get()).get('sessionId'), 'session-a');
});

test('different Coach and Student pairs can reserve the same time, while rollback leaves no partial locks', async () => {
  await reserve({ sessionId: 'session-a', coachId: 'coach-a', studentId: 'student-a' });
  await reserve({ sessionId: 'session-b', coachId: 'coach-b', studentId: 'student-b' });
  assert.equal(await count('coach_busy_blocks'), 10);
  assert.equal(await count('student_busy_blocks'), 10);
  await assert.rejects(
    reserve({ sessionId: 'session-c', coachId: 'coach-c', studentId: 'student-c', failAfterReads: true }),
    /intentional_rollback/,
  );
  assert.equal((await db.doc('coach_busy_blocks/coach-c_1893488400000').get()).exists, false);
  assert.equal((await db.doc('student_busy_blocks/student-c_1893488400000').get()).exists, false);
});
