const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, getDoc, runTransaction, setDoc } = require('firebase/firestore');

const projectId = 'bodyhub-hourly-slot-poc';
const dayKey = '2026-08-03';
const slotId = '0900';
let testEnv;

const coachDb = (coachId) => testEnv.authenticatedContext(coachId, {
  roles: { coach: true },
}).firestore();

const requestData = ({ requestId, coachId, studentId, chosenSlotId = slotId }) => ({
  requestId, coachId, studentId, dayKey, slotId: chosenSlotId, status: 'pending',
});

const sessionData = ({ sessionId, requestId, coachId, studentId, chosenSlotId = slotId, serviceDurationMinutes = 50 }) => ({
  sessionId, bookingRequestId: requestId, coachId, studentId, dayKey,
  slotId: chosenSlotId, scheduleTimeZone: 'Europe/Istanbul',
  serviceDurationMinutes, status: 'scheduled',
});

const coachSlot = ({ coachId, chosenSlotId = slotId }) => ({
  coachId, dayKey, slotId: chosenSlotId, state: 'available', sessionId: '',
});

const studentSlot = ({ sessionId, coachId, studentId, chosenSlotId = slotId }) => ({
  sessionId, coachId, studentId, dayKey, slotId: chosenSlotId,
});

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), path), data);
  });
}

async function seedBase({ coachId = 'coach-a', studentId = 'student-a', requestId = 'request-a' } = {}) {
  await seed(`poc_schedule_slot_templates/${slotId}`, {
    slotId, reservationMinutes: 60, serviceDurationMinutes: 50, active: true,
  });
  await seed(`poc_schedule_days/${dayKey}`, {
    dayKey, working: true, scheduleTimeZone: 'Europe/Istanbul',
  });
  await seed(`poc_hourly_booking_requests/${requestId}`, requestData({ requestId, coachId, studentId }));
  await seed(`poc_hourly_coach_slots/${coachId}/days/${dayKey}/slots/${slotId}`, coachSlot({ coachId }));
}

async function approve({
  coachId = 'coach-a', studentId = 'student-a', requestId = 'request-a',
  sessionId = 'session-a', chosenSlotId = slotId, serviceDurationMinutes = 50,
  forceWriteDespiteAvailability = false,
} = {}) {
  const db = coachDb(coachId);
  return runTransaction(db, async (tx) => {
    const requestRef = doc(db, 'poc_hourly_booking_requests', requestId);
    const coachSlotRef = doc(db, 'poc_hourly_coach_slots', coachId, 'days', dayKey, 'slots', chosenSlotId);
    const studentSlotRef = doc(db, 'poc_hourly_student_slots', studentId, 'days', dayKey, 'slots', chosenSlotId);
    const sessionRef = doc(db, 'poc_hourly_sessions', sessionId);
    const request = await tx.get(requestRef);
    const coach = await tx.get(coachSlotRef);
    const student = await tx.get(studentSlotRef);
    if (!request.exists() || !coach.exists() || (student.exists() && !forceWriteDespiteAvailability)) {
      throw new Error('slot unavailable');
    }
    tx.update(requestRef, { status: 'approved', sessionId });
    tx.update(coachSlotRef, { state: 'reserved', sessionId });
    tx.set(studentSlotRef, studentSlot({ sessionId, coachId, studentId, chosenSlotId }));
    tx.set(sessionRef, sessionData({ sessionId, requestId, coachId, studentId, chosenSlotId, serviceDurationMinutes }));
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync('test/firestore/hourly_slot_coordination_poc.rules', 'utf8') },
  });
});

afterEach(async () => testEnv.clearFirestore());
after(async () => testEnv.cleanup());

test('atomic approval reserves one canonical Coach and Student hourly slot', async () => {
  await seedBase();
  await assertSucceeds(approve());
});

test('a Coach slot cannot be approved twice', async () => {
  await seedBase();
  await assertSucceeds(approve());
  await seed('poc_hourly_booking_requests/request-b', requestData({ requestId: 'request-b', coachId: 'coach-a', studentId: 'student-b' }));
  await assertFails(approve({ requestId: 'request-b', studentId: 'student-b', sessionId: 'session-b' }));
});

test('two concurrent approvals for one Coach slot yield exactly one winner', async () => {
  await seedBase({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a' });
  await seed('poc_hourly_booking_requests/request-b', requestData({
    requestId: 'request-b', coachId: 'coach-a', studentId: 'student-b',
  }));

  const results = await Promise.allSettled([
    approve({ requestId: 'request-a', studentId: 'student-a', sessionId: 'session-a' }),
    approve({ requestId: 'request-b', studentId: 'student-b', sessionId: 'session-b' }),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
});

test('a Student cannot reserve the same canonical slot with another Coach', async () => {
  await seedBase({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a' });
  await seedBase({ coachId: 'coach-b', studentId: 'student-a', requestId: 'request-b' });
  await assertSucceeds(approve({ coachId: 'coach-a', requestId: 'request-a', sessionId: 'session-a' }));
  await assertFails(approve({
    coachId: 'coach-b', requestId: 'request-b', sessionId: 'session-b',
    forceWriteDespiteAvailability: true,
  }));
});

test('different Coach and Student pairs can reserve the same canonical hour', async () => {
  await seedBase({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a' });
  await seedBase({ coachId: 'coach-b', studentId: 'student-b', requestId: 'request-b' });
  await assertSucceeds(approve({ coachId: 'coach-a', studentId: 'student-a', requestId: 'request-a', sessionId: 'session-a' }));
  await assertSucceeds(approve({ coachId: 'coach-b', studentId: 'student-b', requestId: 'request-b', sessionId: 'session-b' }));
});

test('a direct Coach slot reservation without the linked approval is denied', async () => {
  await seedBase();
  const db = coachDb('coach-a');
  await assertFails(setDoc(
    doc(db, 'poc_hourly_coach_slots', 'coach-a', 'days', dayKey, 'slots', slotId),
    { ...coachSlot({ coachId: 'coach-a' }), state: 'reserved', sessionId: 'forged' },
  ));
});

test('an unknown slot template cannot produce a Session', async () => {
  await seedBase();
  await seed('poc_hourly_booking_requests/request-b', requestData({
    requestId: 'request-b', coachId: 'coach-a', studentId: 'student-b', chosenSlotId: '0910',
  }));
  await seed(`poc_hourly_coach_slots/coach-a/days/${dayKey}/slots/0910`, coachSlot({
    coachId: 'coach-a', chosenSlotId: '0910',
  }));
  await assertFails(approve({ requestId: 'request-b', studentId: 'student-b', sessionId: 'session-b', chosenSlotId: '0910' }));
});

test('failed approval leaves the request and Coach slot unchanged', async () => {
  await seedBase();
  await assertFails(approve({ serviceDurationMinutes: 60 }));
  const db = coachDb('coach-a');
  const request = await getDoc(doc(db, 'poc_hourly_booking_requests', 'request-a'));
  const slot = await getDoc(doc(db, 'poc_hourly_coach_slots', 'coach-a', 'days', dayKey, 'slots', slotId));
  assert.equal(request.data().status, 'pending');
  assert.equal(slot.data().state, 'available');
});
