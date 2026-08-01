const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  runTransaction,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const projectId = 'bodyhub-daily-schedule-grid-poc';
let testEnv;

const coachId = 'coach-a';
const studentId = 'student-a';
const dayKey = '2026-08-03';
const slotKeys = ['s054', 's055', 's056', 's057', 's058'];
const laterSlotKeys = ['s060', 's061', 's062', 's063', 's064'];

const roles = { roles: { coach: true } };
const coachDb = () => testEnv.authenticatedContext(coachId, roles).firestore();

const session = (overrides = {}) => ({
  studentId,
  coachId,
  bookingRequestId: 'request-a',
  scheduleTimeZone: 'Europe/Istanbul',
  dayKey,
  startSlotIndex: 54,
  durationBlocks: 5,
  slotKeys,
  ...overrides,
});

const emptySchedule = (ownerId) => ({
  ownerId,
  dayKey,
  scheduleTimeZone: 'Europe/Istanbul',
  sessionId: '',
  slots: {},
});

const scheduleFor = (ownerId, sessionId, keys) => ({
  ...emptySchedule(ownerId),
  sessionId,
  slots: Object.fromEntries(keys.map((key) => [key, sessionId])),
});

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), path), data);
  });
}

async function seedBase() {
  await seed('poc_booking_requests/request-a', {
    studentId, coachId, dayKey, startSlotIndex: 54, status: 'pending',
  });
  await seed(`poc_coach_schedules/${coachId}/days/${dayKey}`, emptySchedule(coachId));
  await seed(`poc_student_schedules/${studentId}/days/${dayKey}`, emptySchedule(studentId));
}

async function approve(db, payload = session()) {
  return runTransaction(db, async (tx) => {
    const request = doc(db, 'poc_booking_requests', payload.bookingRequestId);
    const sessionRef = doc(db, 'poc_sessions', 'session-a');
    const coachDay = doc(db, 'poc_coach_schedules', coachId, 'days', dayKey);
    const studentDay = doc(db, 'poc_student_schedules', studentId, 'days', dayKey);
    await tx.get(request);
    await tx.get(coachDay);
    await tx.get(studentDay);
    tx.update(request, { status: 'approved' });
    tx.set(sessionRef, payload);
    tx.set(coachDay, scheduleFor(coachId, 'session-a', payload.slotKeys));
    tx.set(studentDay, scheduleFor(studentId, 'session-a', payload.slotKeys));
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync('test/firestore/daily_schedule_grid_poc.rules', 'utf8') },
  });
});

afterEach(async () => testEnv.clearFirestore());
after(async () => testEnv.cleanup());

test('POC accepts an atomic request, Session, Coach-day and Student-day write', async () => {
  await seedBase();
  await assertSucceeds(approve(coachDb()));
});

test('POC rejects a schedule update without a matching Session transaction', async () => {
  await seedBase();
  await assertFails(updateDoc(
    doc(coachDb(), 'poc_coach_schedules', coachId, 'days', dayKey),
    scheduleFor(coachId, 'session-a', slotKeys),
  ));
});

test('POC rejects fewer than five altered slot keys', async () => {
  await seedBase();
  await assertFails(approve(coachDb(), session({ slotKeys: slotKeys.slice(0, 4) })));
});

test('POC rejects more than five altered slot keys', async () => {
  await seedBase();
  await assertFails(approve(coachDb(), session({ slotKeys: [...slotKeys, 's059'] })));
});

test('negative proof: Rules cannot bind integer startSlotIndex to map slot keys', async () => {
  await seedBase();
  // The displayed coordinate is 09:00 (54), but all schedule keys are 10:00.
  // This succeeds under the strongest generic map-diff relation the language
  // can express, proving the frozen integer-to-map-key invariant is missing.
  await assertSucceeds(approve(coachDb(), session({ slotKeys: laterSlotKeys })));
});
