const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, getDoc, runTransaction, setDoc } = require('firebase/firestore');

const projectId = 'bodyhub-d59-availability-gate-poc';
const defaultDayKey = '2026-08-03';
const defaultSlotId = '0900';
let testEnv;

const coachDb = (coachId) => testEnv.authenticatedContext(coachId, {
  roles: { coach: true },
}).firestore();

const requestData = ({ requestId, coachId, studentId, dayKey = defaultDayKey, slotId = defaultSlotId }) => ({
  requestId, coachId, studentId, dayKey, slotId, status: 'pending',
});

const availabilityData = ({ coachId, dayKey = defaultDayKey, slotId = defaultSlotId }) => ({
  coachId, dayKey, slotId, active: true,
});

const sessionData = ({ sessionId, requestId, coachId, studentId, dayKey, slotId }) => ({
  sessionId,
  bookingRequestId: requestId,
  coachId,
  studentId,
  dayKey,
  slotId,
  status: 'scheduled',
  scheduleTimeZone: 'Europe/Istanbul',
});

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), path), data);
  });
}

async function seedBase({
  coachId = 'coach-a', studentId = 'student-a', requestId = 'request-a',
  dayKey = defaultDayKey, slotId = defaultSlotId, seedAvailability = true,
} = {}) {
  await seed(`poc_d59_slot_templates/${slotId}`, {
    slotId, sequence: 1, active: true, schemaVersion: 2,
  });
  if (seedAvailability) {
    await seed(
      `poc_d59_coach_availability/${coachId}/days/${dayKey}/slots/${slotId}`,
      availabilityData({ coachId, dayKey, slotId }),
    );
  }
  await seed(`poc_d59_booking_requests/${requestId}`, requestData({
    requestId, coachId, studentId, dayKey, slotId,
  }));
  await seed(`poc_d59_coach_slots/${coachId}/days/${dayKey}/slots/${slotId}`, {
    coachId, dayKey, slotId, state: 'available', sessionId: '',
  });
}

async function approve({
  coachId = 'coach-a', studentId = 'student-a', requestId = 'request-a',
  sessionId = 'session-a', dayKey = defaultDayKey, slotId = defaultSlotId,
} = {}) {
  const db = coachDb(coachId);
  return runTransaction(db, async (tx) => {
    const requestRef = doc(db, 'poc_d59_booking_requests', requestId);
    const coachSlotRef = doc(db, 'poc_d59_coach_slots', coachId, 'days', dayKey, 'slots', slotId);
    const studentSlotRef = doc(db, 'poc_d59_student_slots', studentId, 'days', dayKey, 'slots', slotId);
    const sessionRef = doc(db, 'poc_d59_sessions', sessionId);
    const request = await tx.get(requestRef);
    const coachSlot = await tx.get(coachSlotRef);
    const studentSlot = await tx.get(studentSlotRef);
    if (!request.exists() || !coachSlot.exists() || studentSlot.exists()) {
      throw new Error('slot unavailable');
    }
    tx.update(requestRef, { status: 'approved', sessionId });
    tx.update(coachSlotRef, { state: 'reserved', sessionId });
    tx.set(studentSlotRef, { sessionId, coachId, studentId, dayKey, slotId });
    tx.set(sessionRef, sessionData({ sessionId, requestId, coachId, studentId, dayKey, slotId }));
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync('test/firestore/availability_gated_hourly_slot_poc.rules', 'utf8'),
    },
  });
});

afterEach(async () => testEnv.clearFirestore());
after(async () => testEnv.cleanup());

test('approval succeeds without schedule_days when exact Coach availability exists', async () => {
  await seedBase();
  await assertSucceeds(approve());
});

test('approval is denied when the canonical Coach availability coordinate is absent', async () => {
  await seedBase({ seedAvailability: false });
  await assertFails(approve());
});

test('mismatched availability dayKey cannot authorize an approval', async () => {
  await seedBase({ seedAvailability: false });
  await seed(
    'poc_d59_coach_availability/coach-a/days/2026-08-04/slots/0900',
    availabilityData({ coachId: 'coach-a', dayKey: '2026-08-04' }),
  );
  await assertFails(approve());
});

test('an alternate non-canonical dayKey representation is rejected', async () => {
  const dayKey = '2026-8-03';
  await seedBase({ dayKey });
  await assertFails(approve({ dayKey }));
});

test('syntactically invalid calendar day is a distinct data-quality value, not a collision bypass', async () => {
  const dayKey = '2026-02-31';
  await seedBase({ dayKey });
  await assertSucceeds(approve({ dayKey }));
  const db = coachDb('coach-a');
  const session = await getDoc(doc(db, 'poc_d59_sessions', 'session-a'));
  assert.equal(session.data().dayKey, dayKey);
});

test('a different Coach and Student can use the same dayKey and slotId', async () => {
  await seedBase({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a' });
  await seedBase({ coachId: 'coach-b', studentId: 'student-b', requestId: 'request-b' });
  await assertSucceeds(approve({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a' }));
  await assertSucceeds(approve({ coachId: 'coach-b', studentId: 'student-b', requestId: 'request-b', sessionId: 'session-b' }));
});

test('one Coach cannot approve the same availability coordinate twice', async () => {
  await seedBase({ requestId: 'request-a', studentId: 'student-a' });
  await seed('poc_d59_booking_requests/request-b', requestData({
    requestId: 'request-b', coachId: 'coach-a', studentId: 'student-b',
  }));
  await assertSucceeds(approve({ requestId: 'request-a', studentId: 'student-a' }));
  await assertFails(approve({ requestId: 'request-b', studentId: 'student-b', sessionId: 'session-b' }));
});
