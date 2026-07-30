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
  CustomClaimRoleManager,
  createAdminContext,
  parseArgs,
} = require('../../tool/manage_custom_claim_roles');

const projectId = 'bodyhub-claim-role-tests';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!authHost || !firestoreHost) {
  throw new Error('FIREBASE_AUTH_EMULATOR_HOST and FIRESTORE_EMULATOR_HOST are required.');
}

const app = admin.initializeApp({ projectId }, 'custom-claim-role-tests');
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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'bodyhub-claim-role-tests-'));
}

function manager() {
  return new CustomClaimRoleManager({
    auth,
    db,
    projectId,
    operator: 'integration-test',
    environment: 'emulator',
    outputDir: outputDirectory(),
  });
}

async function user(uid, roles = [], metadata = true) {
  const normalizedRoles = roles || [];
  const email = `${uid}@example.test`;
  await auth.createUser({ uid, email });
  if (normalizedRoles.length > 0) await auth.setCustomUserClaims(uid, {
    roles: Object.fromEntries(normalizedRoles.map((role) => [role, true])),
  });
  if (metadata) await db.collection('users').doc(uid).set({
    uid,
    ...(normalizedRoles.length > 0 ? { role: normalizedRoles.includes('admin') ? 'admin' : normalizedRoles[0] } : {}),
  });
  return { uid, email };
}

function auditEntries(instance) {
  return fs.readFileSync(instance.audit.path, 'utf8')
    .trim()
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

test.beforeEach(async () => clear());
test.after(() => app.delete());

test('set-role preserves unrelated claims and synchronizes metadata', async () => {
  await user('coach-a');
  await auth.setCustomUserClaims('coach-a', { tenant: 'north' });
  const instance = manager();
  const result = await instance.changeRole({
    command: 'set-role', uid: 'coach-a', role: 'coach', apply: true,
  });
  const updated = await auth.getUser('coach-a');
  assert.equal(result.result, 'applied');
  assert.deepEqual(updated.customClaims, { tenant: 'north', roles: { coach: true } });
  assert.equal((await db.doc('users/coach-a').get()).get('role'), 'coach');
  const entries = auditEntries(instance);
  assert.equal(entries.at(-1).result, 'applied');
  assert.equal(entries.at(-1).operator, 'integration-test');
  assert.equal(entries.at(-1).projectId, projectId);
});

test('remove-role preserves unrelated claims and removes metadata role', async () => {
  await user('coach-a', ['coach']);
  await auth.setCustomUserClaims('coach-a', { roles: { coach: true }, tenant: 'north' });
  const instance = manager();
  const result = await instance.changeRole({ command: 'remove-role', uid: 'coach-a', apply: true });
  assert.equal(result.result, 'applied');
  assert.deepEqual((await auth.getUser('coach-a')).customClaims, { tenant: 'north' });
  assert.equal((await db.doc('users/coach-a').get()).get('role'), undefined);
});

test('dry-run is the default safety behavior and does not mutate claims or metadata', async () => {
  await user('coach-a');
  const instance = manager();
  const result = await instance.changeRole({
    command: 'set-role', uid: 'coach-a', role: 'coach', apply: false,
  });
  assert.equal(result.result, 'dry_run');
  assert.equal((await auth.getUser('coach-a')).customClaims, undefined);
  assert.equal((await db.doc('users/coach-a').get()).get('role'), undefined);
  assert.equal(auditEntries(instance).at(-1).result, 'dry_run');
});

test('invalid roles are rejected before any operation is attempted', () => {
  assert.throws(
    () => parseArgs(['set-role', '--uid', 'coach-a', '--role', 'owner', '--project-id', projectId]),
    /student, coach, or admin/,
  );
});

test('emulator and production contexts cannot be mixed accidentally', () => {
  assert.throws(
    () => createAdminContext({ emulator: true, projectId: 'body-hub-10745', serviceAccount: null }),
    /cannot use the production project ID/,
  );
  assert.throws(
    () => createAdminContext({ emulator: false, projectId, serviceAccount: null }),
    /refuses emulator environment variables/,
  );
});

test('metadata absence is reported as partial failure after a successful claim write', async () => {
  await user('coach-a', null, false);
  const instance = manager();
  const result = await instance.changeRole({
    command: 'set-role', uid: 'coach-a', role: 'coach', apply: true,
  });
  assert.equal(result.result, 'partial_failure');
  assert.equal(result.metadataResult, 'metadata_missing');
  assert.deepEqual((await auth.getUser('coach-a')).customClaims.roles, { coach: true });
  assert.equal((await db.doc('users/coach-a').get()).exists, false);
  assert.equal(auditEntries(instance).at(-1).result, 'partial_failure');
});

test('the final admin cannot be removed or demoted', async () => {
  await user('admin-a', ['admin']);
  const instance = manager();
  const result = await instance.changeRole({ command: 'remove-role', uid: 'admin-a', apply: true });
  assert.equal(result.result, 'blocked_last_admin');
  assert.deepEqual((await auth.getUser('admin-a')).customClaims.roles, { admin: true });
  assert.equal((await db.doc('users/admin-a').get()).get('role'), 'admin');
  assert.equal(auditEntries(instance).at(-1).result, 'blocked_last_admin');
});

test('set-role is idempotent after claims and metadata are already synchronized', async () => {
  await user('coach-a');
  const instance = manager();
  const first = await instance.changeRole({ command: 'set-role', uid: 'coach-a', role: 'coach', apply: true });
  const second = await instance.changeRole({ command: 'set-role', uid: 'coach-a', role: 'coach', apply: true });
  assert.equal(first.result, 'applied');
  assert.equal(second.result, 'noop');
});

test('set-role adds a second canonical role without replacing the first', async () => {
  await user('coach-admin', ['coach']);
  const instance = manager();
  const result = await instance.changeRole({
    command: 'set-role', uid: 'coach-admin', role: 'admin', apply: true,
  });
  assert.equal(result.result, 'applied');
  assert.deepEqual((await auth.getUser('coach-admin')).customClaims.roles, {
    admin: true,
    coach: true,
  });
  assert.equal((await db.doc('users/coach-admin').get()).get('role'), 'admin');
});

test('show-role and list-privileged-users read claims without mutating them', async () => {
  const coach = await user('coach-a', ['coach']);
  await user('student-a');
  const instance = manager();
  const shown = await instance.showRole({ email: coach.email });
  const privileged = await instance.listPrivilegedUsers();
  assert.equal(shown.currentRole, 'coach');
  assert.deepEqual(shown.currentRoles, ['coach']);
  assert.equal(shown.metadataRole, 'coach');
  assert.deepEqual(privileged.map((entry) => entry.uid), ['coach-a']);
});
