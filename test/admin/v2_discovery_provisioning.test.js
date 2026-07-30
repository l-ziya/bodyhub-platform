'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const admin = require('firebase-admin');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const {
  V2DiscoveryProvisioner,
  normalizedSpecialtyIds,
} = require('../../tool/provision_v2_discovery');

const projectId = 'bodyhub-v2-provisioning-tests';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!authHost || !firestoreHost) {
  throw new Error('FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST are required.');
}

const app = admin.initializeApp({ projectId }, 'v2-discovery-provisioning-tests');
const auth = getAuth(app);
const db = getFirestore(app);

async function clear() {
  const authResponse = await fetch(
    `http://${authHost}/emulator/v1/projects/${projectId}/accounts`,
    { method: 'DELETE' },
  );
  assert.equal(authResponse.status, 200);
  const firestoreResponse = await fetch(
    `http://${firestoreHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  assert.equal(firestoreResponse.status, 200);
}

function outputDirectory() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'bodyhub-v2-provisioning-tests-'));
}

function provisioner() {
  return new V2DiscoveryProvisioner({
    auth,
    db,
    projectId,
    operator: 'integration-test',
    environment: 'emulator',
    outputDir: outputDirectory(),
  });
}

async function coach(uid, claims = { roles: { coach: true } }) {
  await auth.createUser({ uid, email: `${uid}@example.test` });
  await auth.setCustomUserClaims(uid, claims);
}

test.beforeEach(async () => clear());
test.after(() => app.delete());

test('sports provisioning defaults to dry-run and then writes only with apply', async () => {
  const instance = provisioner();
  const input = { sportId: 'athletic_performance', name: 'Athletic Performance', active: true, sortOrder: 20 };
  const preview = await instance.upsertSport(input, { apply: false });
  assert.equal(preview.result, 'dry_run');
  assert.equal((await db.doc('sports/athletic_performance').get()).exists, false);

  const applied = await instance.upsertSport(input, { apply: true });
  const stored = await db.doc('sports/athletic_performance').get();
  assert.equal(applied.result, 'applied');
  assert.equal(stored.get('active'), true);
  assert.equal(stored.get('schemaVersion'), 2);
  assert.equal(stored.get('createdBy'), 'integration-test');
});

test('coach profile provisioning requires a Coach claim and active specialty documents', async () => {
  await coach('coach-a');
  await db.doc('sports/tennis').set({ active: true });
  const instance = provisioner();
  const input = {
    coachId: 'coach-a', displayName: 'Coach A', active: true,
    bookingEnabled: true, specialtyIds: ['tennis'], bio: 'Public', photoUrl: '',
  };
  const result = await instance.upsertCoachProfile(input, { apply: true });
  const profile = await db.doc('coach_profiles/coach-a').get();
  assert.equal(result.result, 'applied');
  assert.deepEqual(profile.get('specialtyIds'), ['tennis']);
  assert.equal(profile.get('createdBy'), 'integration-test');

  await coach('student-a', { roles: { student: true } });
  await assert.rejects(
    instance.upsertCoachProfile({ ...input, coachId: 'student-a' }, { apply: true }),
    /Coach or Admin custom claim/,
  );
  await assert.rejects(
    instance.upsertCoachProfile({ ...input, specialtyIds: ['inactive'] }, { apply: true }),
    /active provisioned sport/,
  );
});

test('specialty identifiers reject duplicates and malformed values before provisioning', () => {
  assert.deepEqual(normalizedSpecialtyIds(['tennis', 'fitness']), ['tennis', 'fitness']);
  assert.throws(() => normalizedSpecialtyIds(['tennis', 'tennis']), /unique stable sport slugs/);
  assert.throws(() => normalizedSpecialtyIds(['bad-id']), /unique stable sport slugs/);
});
