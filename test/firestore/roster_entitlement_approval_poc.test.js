const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, getDoc, increment, runTransaction, serverTimestamp, setDoc } = require('firebase/firestore');

let env;
const requestId = 'request-a';
const coachId = 'coach-a';
const studentId = 'student-a';

const coachDb = () => env.authenticatedContext(coachId, { roles: { coach: true } }).firestore();
const requestRef = (db) => doc(db, 'poc_d8_requests', requestId);
const rosterRef = (db) => doc(db, 'poc_d8_coaches', coachId, 'students', studentId);
const entitlementRef = (db) => doc(db, 'poc_d8_entitlements', studentId);
const sessionRef = (db) => doc(db, 'poc_d8_sessions', requestId);

async function seed(remainingSessions = 1) {
  await env.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(requestRef(db), { coachId, studentId, status: 'pending' });
    await setDoc(entitlementRef(db), { studentId, remainingSessions, sessionId: '', updatedBy: '', updatedAt: new Date() });
  });
}

async function approve(db) {
  return runTransaction(db, async (tx) => {
    const request = await tx.get(requestRef(db));
    if (!request.exists()) {
      throw new Error('missing request');
    }
    tx.set(rosterRef(db), { coachId, studentId, bookingRequestId: requestId, createdAt: serverTimestamp(), createdBy: coachId, schemaVersion: 2 });
    tx.update(entitlementRef(db), { remainingSessions: increment(-1), sessionId: requestId, updatedBy: coachId, updatedAt: serverTimestamp() });
    tx.set(sessionRef(db), { sessionId: requestId, coachId, studentId });
    tx.update(requestRef(db), { status: 'approved', sessionId: requestId });
  });
}

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'bodyhub-d8-roster-poc', firestore: { rules: readFileSync('test/firestore/roster_entitlement_approval_poc.rules', 'utf8') } });
});
afterEach(async () => env.clearFirestore());
after(async () => env.cleanup());

test('one pending request can establish one roster inside approval', async () => {
  await seed(1);
  await assertSucceeds(approve(coachDb()));
});

test('two concurrent approvals for the same request leave one roster', async () => {
  await seed(1);
  const outcomes = await Promise.allSettled([approve(coachDb()), approve(coachDb())]);
  assert.equal(outcomes.filter((outcome) => outcome.status === 'fulfilled').length, 1);
});

test('a second roster create from the same request is denied', async () => {
  await seed(1);
  await assertSucceeds(approve(coachDb()));
  await assertFails(setDoc(rosterRef(coachDb()), { coachId, studentId, bookingRequestId: requestId, createdAt: serverTimestamp(), createdBy: coachId, schemaVersion: 2 }));
});

test('insufficient entitlement leaves no roster, Session, or request transition', async () => {
  await seed(0);
  await assertFails(approve(coachDb()));
  await env.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    assert.equal((await getDoc(rosterRef(db))).exists(), false);
    assert.equal((await getDoc(sessionRef(db))).exists(), false);
    assert.equal((await getDoc(requestRef(db))).data().status, 'pending');
  });
});
