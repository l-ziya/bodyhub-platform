const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const { assertFails, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { deleteDoc, doc, getDoc, setDoc, updateDoc } = require('firebase/firestore');

let testEnv;
const template = {
  slotId: '0900', sequence: 1, active: true, schemaVersion: 2,
};

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'bodyhub-slot-template-immutability-poc',
    firestore: { rules: readFileSync('test/firestore/slot_template_immutability_poc.rules', 'utf8') },
  });
});

afterEach(async () => testEnv.clearFirestore());
after(async () => testEnv.cleanup());

test('every client claim is denied template create, update, and delete', async () => {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'schedule_slot_templates', '0900'), template);
  });
  const clients = [
    testEnv.unauthenticatedContext().firestore(),
    testEnv.authenticatedContext('student-a', { roles: { student: true } }).firestore(),
    testEnv.authenticatedContext('coach-a', { roles: { coach: true } }).firestore(),
    testEnv.authenticatedContext('admin-a', { roles: { admin: true } }).firestore(),
  ];
  for (const db of clients) {
    const reference = doc(db, 'schedule_slot_templates', '0900');
    await assertFails(setDoc(reference, template));
    await assertFails(updateDoc(reference, { active: false }));
    await assertFails(deleteDoc(reference));
  }
});

test('the canonical Coach schedule slot path is valid without materialized parent documents', async () => {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    const slot = doc(
      db,
      'coach_schedule_slots', 'coach-a', 'days', '2026-08-03', 'slots', '0900',
    );
    await setDoc(slot, { coachId: 'coach-a', dayKey: '2026-08-03', slotId: '0900' });
    const coachRoot = await getDoc(doc(db, 'coach_schedule_slots', 'coach-a'));
    const day = await getDoc(doc(db, 'coach_schedule_slots', 'coach-a', 'days', '2026-08-03'));
    const storedSlot = await getDoc(slot);
    assert.equal(coachRoot.exists(), false);
    assert.equal(day.exists(), false);
    assert.equal(storedSlot.exists(), true);
  });

  const coach = testEnv.authenticatedContext('coach-a', { roles: { coach: true } }).firestore();
  await assertFails(setDoc(
    doc(coach, 'schedule_slot_templates', '0900'),
    template,
  ));
});
