const { readFileSync } = require('node:fs');
const { after, afterEach, before, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteField,
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const projectId = 'bodyhub-rules-test';
const expectRoleExploit = process.env.EXPECT_ROLE_EXPLOIT === 'true';
const testAfterFix = expectRoleExploit ? test.skip : test;
let testEnv;

const studentUser = (overrides = {}) => ({
  uid: 'student-a',
  fullName: 'Student A',
  phone: '5550000000',
  email: 'student-a@example.test',
  gender: 'female',
  status: 'pending',
  createdAt: serverTimestamp(),
  ...overrides,
});

const context = (uid) => testEnv.authenticatedContext(uid).firestore();
const userRef = (db, uid) => doc(db, 'users', uid);

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (adminContext) => {
    await setDoc(doc(adminContext.firestore(), path), data);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

testAfterFix('unauthenticated user cannot create a users document', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(setDoc(userRef(db, 'student-a'), studentUser()));
});

testAfterFix('student can create their own users document with registration fields', async () => {
  await assertSucceeds(
    setDoc(userRef(context('student-a'), 'student-a'), studentUser()),
  );
});

test('current-rules exploit proof: student can create role coach only before the fix', async () => {
  const write = setDoc(
    userRef(context('student-a'), 'student-a'),
    studentUser({ role: 'coach' }),
  );
  if (expectRoleExploit) {
    await assertSucceeds(write);
  } else {
    await assertFails(write);
  }
});

testAfterFix('student cannot create role admin', async () => {
  await assertFails(
    setDoc(userRef(context('student-a'), 'student-a'), studentUser({ role: 'admin' })),
  );
});

testAfterFix('student cannot create arbitrary fields', async () => {
  await assertFails(
    setDoc(
      userRef(context('student-a'), 'student-a'),
      studentUser({ arbitraryField: true }),
    ),
  );
});

testAfterFix('student can update normal profile fields', async () => {
  await seed('users/student-a', studentUser());
  await assertSucceeds(
    updateDoc(userRef(context('student-a'), 'student-a'), {
      fullName: 'Updated Student',
      phone: '5551111111',
      updatedAt: serverTimestamp(),
    }),
  );
});

testAfterFix('student cannot add, change, or remove role', async (t) => {
  await seed('users/student-a', studentUser());
  await t.test('add role', async () => {
    await assertFails(
      updateDoc(userRef(context('student-a'), 'student-a'), { role: 'coach' }),
    );
  });
  await t.test('change role', async () => {
    await testEnv.clearFirestore();
    await seed('users/student-a', studentUser({ role: 'student' }));
    await assertFails(
      updateDoc(userRef(context('student-a'), 'student-a'), { role: 'coach' }),
    );
  });
  await t.test('remove role', async () => {
    await testEnv.clearFirestore();
    await seed('users/student-a', studentUser({ role: 'student' }));
    await assertFails(
      updateDoc(userRef(context('student-a'), 'student-a'), {
        role: deleteField(),
      }),
    );
  });
});

testAfterFix('student cannot change sensitive users fields', async () => {
  await seed('users/student-a', studentUser());
  const db = context('student-a');
  await assertFails(updateDoc(userRef(db, 'student-a'), { uid: 'other-user' }));
  await assertFails(updateDoc(userRef(db, 'student-a'), { status: 'active' }));
  await assertFails(
    updateDoc(userRef(db, 'student-a'), { email: 'changed@example.test' }),
  );
  await assertFails(
    updateDoc(userRef(db, 'student-a'), { createdAt: serverTimestamp() }),
  );
  await assertFails(updateDoc(userRef(db, 'student-a'), { packageId: 'monthly' }));
});

testAfterFix('Flutter clients cannot delete users documents', async () => {
  await seed('users/student-a', studentUser());
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await assertFails(deleteDoc(userRef(context('student-a'), 'student-a')));
  await assertFails(deleteDoc(userRef(context('coach-a'), 'student-a')));
});

testAfterFix('student cannot update another users document', async () => {
  await seed('users/student-b', studentUser({ uid: 'student-b' }));
  await assertFails(
    updateDoc(userRef(context('student-a'), 'student-b'), {
      fullName: 'Unauthorized update',
    }),
  );
});

testAfterFix('roleless user cannot perform a coach-only lesson write', async () => {
  await seed('users/student-a', studentUser());
  await assertFails(
    setDoc(doc(context('student-a'), 'lessons', 'lesson-1'), {
      studentId: 'student-a',
    }),
  );
});

testAfterFix('seeded coach retains existing coach permissions and self profile updates', async () => {
  await seed('users/coach-a', {
    uid: 'coach-a',
    fullName: 'Coach A',
    role: 'coach',
    status: 'active',
    createdAt: serverTimestamp(),
  });
  await seed('student_profiles/student-a', { status: 'pending' });
  const coachDb = context('coach-a');
  await assertSucceeds(
    updateDoc(doc(coachDb, 'student_profiles', 'student-a'), {
      status: 'active',
    }),
  );
  await assertSucceeds(
    updateDoc(userRef(coachDb, 'coach-a'), {
      name: 'Coach A Updated',
      phone: '5552222222',
      specialty: 'Fitness',
      bio: 'Profile update',
      coachSettings: { lessonNotifications: true },
      updatedAt: serverTimestamp(),
    }),
  );
});

testAfterFix('coach can update only a students sport fields', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  await assertSucceeds(
    updateDoc(userRef(context('coach-a'), 'student-a'), {
      sportId: 'fitness',
      sportName: 'Fitness',
      updatedAt: serverTimestamp(),
    }),
  );
});

testAfterFix('coach cannot change sensitive or unrelated student users fields', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  const coachDb = context('coach-a');
  await assertFails(
    updateDoc(userRef(coachDb, 'student-a'), { fullName: 'Unauthorized' }),
  );
  await assertFails(
    updateDoc(userRef(coachDb, 'student-a'), { email: 'changed@example.test' }),
  );
  await assertFails(updateDoc(userRef(coachDb, 'student-a'), { uid: 'other-user' }));
  await assertFails(updateDoc(userRef(coachDb, 'student-a'), { status: 'active' }));
  await assertFails(
    updateDoc(userRef(coachDb, 'student-a'), { createdAt: serverTimestamp() }),
  );
  await assertFails(updateDoc(userRef(coachDb, 'student-a'), { packageId: 'monthly' }));
});

testAfterFix('coach cannot add, change, or remove another users role', async (t) => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  const coachDb = context('coach-a');
  await t.test('add role', async () => {
    await assertFails(updateDoc(userRef(coachDb, 'student-a'), { role: 'coach' }));
  });
  await t.test('change role', async () => {
    await testEnv.clearFirestore();
    await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
    await seed('users/student-a', studentUser({ role: 'student' }));
    await assertFails(updateDoc(userRef(coachDb, 'student-a'), { role: 'admin' }));
  });
  await t.test('remove role', async () => {
    await testEnv.clearFirestore();
    await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
    await seed('users/student-a', studentUser({ role: 'student' }));
    await assertFails(
      updateDoc(userRef(coachDb, 'student-a'), { role: deleteField() }),
    );
  });
});

testAfterFix('normal student cannot execute coach-only booking, lesson, package, or student operations', async () => {
  await seed('users/student-a', studentUser());
  await seed('student_profiles/student-a', { status: 'active' });
  const db = context('student-a');
  await assertFails(setDoc(doc(db, 'lessons', 'lesson-1'), { studentId: 'student-a' }));
  await assertFails(setDoc(doc(db, 'student_packages', 'student-a'), { studentId: 'student-a' }));
  await assertFails(updateDoc(doc(db, 'student_profiles', 'student-b'), { status: 'active' }));
  await assertFails(
    setDoc(doc(db, 'bookings', 'booking-1'), { studentId: 'student-b' }),
  );
});

testAfterFix('rules test environment is isolated from production', async () => {
  const db = context('student-a');
  await assertSucceeds(setDoc(userRef(db, 'student-a'), studentUser()));
  const snapshot = await getDoc(userRef(db, 'student-a'));
  assert.equal(snapshot.data().uid, 'student-a');
});
