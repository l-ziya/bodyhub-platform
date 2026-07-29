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
  collection,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
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

const context = (uid, claims = {}) =>
  testEnv.authenticatedContext(uid, claims).firestore();
const coachContext = (uid) => context(uid, { role: 'coach' });
const adminContext = (uid) => context(uid, { role: 'admin' });
const claimlessContext = (uid) => context(uid);
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
  await assertFails(deleteDoc(userRef(coachContext('coach-a'), 'student-a')));
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

testAfterFix('claimed coach retains existing coach permissions and self profile updates', async () => {
  await seed('users/coach-a', {
    uid: 'coach-a',
    fullName: 'Coach A',
    role: 'coach',
    status: 'active',
    createdAt: serverTimestamp(),
  });
  await seed('student_profiles/student-a', { status: 'pending' });
  const coachDb = coachContext('coach-a');
  await assertSucceeds(updateDoc(doc(coachDb, 'student_profiles', 'student-a'), {
    status: 'active',
    coachId: 'coach-a',
  }));
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

testAfterFix('coach approval assigns only their own coachId and cannot overwrite an assignment', async (t) => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/coach-b', { uid: 'coach-b', role: 'coach' });
  await seed('student_profiles/student-a', { status: 'pending' });
  await assertFails(updateDoc(doc(coachContext('coach-a'), 'student_profiles', 'student-a'), {
    status: 'active', coachId: 'coach-b',
  }));
  await assertSucceeds(updateDoc(doc(coachContext('coach-a'), 'student_profiles', 'student-a'), {
    status: 'active', coachId: 'coach-a',
  }));
  await t.test('existing coachId cannot be changed', async () => {
    await assertFails(updateDoc(doc(coachContext('coach-b'), 'student_profiles', 'student-a'), {
      coachId: 'coach-b',
    }));
  });
});

testAfterFix('student cannot change or remove their coachId', async (t) => {
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  const ref = doc(context('student-a'), 'student_profiles', 'student-a');
  await t.test('change', async () => assertFails(updateDoc(ref, { coachId: 'coach-b' })));
  await t.test('remove', async () => assertFails(updateDoc(ref, { coachId: deleteField() })));
});

testAfterFix('student booking requires an active profile with its assigned coachId', async (t) => {
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  const booking = (coachId) => setDoc(doc(context('student-a'), 'bookings', `booking-${coachId || 'none'}`), {
    studentId: 'student-a', coachId, status: 'pending',
  });
  await t.test('matching coachId succeeds', async () => assertSucceeds(booking('coach-a')));
  await t.test('different coachId fails', async () => assertFails(booking('coach-b')));
});

testAfterFix('pending or unassigned student cannot create a booking', async (t) => {
  await seed('student_profiles/student-a', { status: 'pending', coachId: 'coach-a' });
  await t.test('pending', async () => assertFails(setDoc(doc(context('student-a'), 'bookings', 'pending'), {
    studentId: 'student-a', coachId: 'coach-a', status: 'pending',
  })));
  await testEnv.clearFirestore();
  await seed('student_profiles/student-a', { status: 'active' });
  await t.test('unassigned', async () => assertFails(setDoc(doc(context('student-a'), 'bookings', 'unassigned'), {
    studentId: 'student-a', coachId: '', status: 'pending',
  })));
});

testAfterFix('coach can only create lessons with their own coachId', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  await assertSucceeds(setDoc(doc(coachContext('coach-a'), 'lessons', 'lesson-a'), {
    studentId: 'student-a', coachId: 'coach-a',
  }));
  await assertFails(setDoc(doc(coachContext('coach-a'), 'lessons', 'lesson-b'), {
    studentId: 'student-a', coachId: 'coach-b',
  }));
});

testAfterFix('coach can update only a students sport fields', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  await assertSucceeds(
    updateDoc(userRef(coachContext('coach-a'), 'student-a'), {
      sportId: 'fitness',
      sportName: 'Fitness',
      updatedAt: serverTimestamp(),
    }),
  );
});

testAfterFix('coach cannot change sensitive or unrelated student users fields', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  const coachDb = coachContext('coach-a');
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
  const coachDb = coachContext('coach-a');
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

const when = (minutes = 0) => Timestamp.fromMillis(1_900_000_000_000 + minutes * 60_000);

async function seedRelationship() {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/coach-b', { uid: 'coach-b', role: 'coach' });
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  await seed('student_profiles/student-b', { status: 'active', coachId: 'coach-b' });
}

const bookingData = (overrides = {}) => ({
  studentId: 'student-a',
  coachId: 'coach-a',
  scheduledAt: when(),
  status: 'pending',
  ...overrides,
});

const lessonData = (overrides = {}) => ({
  studentId: 'student-a',
  coachId: 'coach-a',
  bookingId: 'booking-a',
  startTime: when(),
  endTime: when(50),
  status: 'scheduled',
  ...overrides,
});

const slotData = (overrides = {}) => ({
  bookingId: 'booking-a',
  lessonId: '',
  coachId: 'coach-a',
  studentId: 'student-a',
  resourceType: 'coach',
  resourceId: 'coach-a',
  blockStart: when(),
  scheduledAt: when(),
  endTime: when(50),
  status: 'pending',
  ...overrides,
});

testAfterFix('coach collection queries require token role and ownership constraints', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
  await seed('lessons/lesson-a', lessonData());
  await seed('lesson_change_requests/change-a', {
    studentId: 'student-a', coachId: 'coach-a', lessonId: 'lesson-a', type: 'reschedule', status: 'pending', createdAt: when(), updatedAt: when(),
  });
  await seed('package_requests/package-a', {
    studentId: 'student-a', coachId: 'coach-a', packageId: 'package-a', status: 'pending', requestedAt: when(), updatedAt: when(),
  });
  await seed('student_profiles/pending-unassigned', { status: 'pending' });
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const admin = adminContext('admin-a');
  const claimlessCoachMetadata = claimlessContext('coach-a');
  const studentA = context('student-a');

  await t.test('unconstrained dashboard and notification queries fail', async () => {
    await assertFails(getDocs(collection(coachA, 'bookings')));
    await assertFails(getDocs(collection(coachA, 'lesson_change_requests')));
    await assertFails(getDocs(collection(coachA, 'package_requests')));
    await assertFails(getDocs(query(
      collection(coachA, 'lesson_change_requests'), where('status', '==', 'pending'),
    )));
    await assertFails(getDocs(query(
      collection(coachA, 'package_requests'), where('status', '==', 'pending'),
    )));
  });

  await t.test('pending onboarding is visible only to coach or admin claims', async () => {
    await assertSucceeds(getDocs(query(
      collection(coachA, 'student_profiles'), where('status', '==', 'pending'),
    )));
    await assertSucceeds(getDocs(query(
      collection(admin, 'student_profiles'), where('status', '==', 'pending'),
    )));
    await assertFails(getDocs(query(
      collection(studentA, 'student_profiles'), where('status', '==', 'pending'),
    )));
  });

  await t.test('ownership-constrained coach queries succeed', async () => {
    await assertSucceeds(getDocs(query(
      collection(coachA, 'bookings'),
      where('coachId', '==', 'coach-a'),
    )));
    await assertSucceeds(getDocs(query(
      collection(coachA, 'package_requests'),
      where('coachId', '==', 'coach-a'),
      where('status', '==', 'pending'),
    )));
    await assertSucceeds(getDocs(query(
      collection(coachA, 'lesson_change_requests'),
      where('coachId', '==', 'coach-a'),
      where('status', '==', 'pending'),
    )));
  });

  await t.test('wrong ownership filters and Firestore role metadata do not grant access', async () => {
    await assertFails(getDocs(query(
      collection(coachB, 'bookings'),
      where('coachId', '==', 'coach-a'),
    )));
    await assertFails(getDocs(query(
      collection(coachB, 'package_requests'),
      where('coachId', '==', 'coach-a'),
      where('status', '==', 'pending'),
    )));
    await assertFails(getDocs(query(
      collection(coachB, 'lesson_change_requests'),
      where('coachId', '==', 'coach-a'),
      where('status', '==', 'pending'),
    )));
    await assertFails(getDocs(query(
      collection(claimlessCoachMetadata, 'bookings'),
      where('coachId', '==', 'coach-a'),
    )));
    await assertFails(getDocs(query(
      collection(claimlessCoachMetadata, 'student_profiles'),
      where('status', '==', 'pending'),
    )));
  });
});

testAfterFix('booking ownership prevents student identity, coach, and status escalation', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  const studentDb = context('student-a');
  await t.test('student may cancel only their own booking', async () => {
    await assertSucceeds(updateDoc(doc(studentDb, 'bookings', 'booking-a'), {
      status: 'cancelled', updatedAt: serverTimestamp(),
    }));
  });
  await testEnv.clearFirestore();
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await t.test('student cannot change booking ownership or promote status', async () => {
    await assertFails(updateDoc(doc(studentDb, 'bookings', 'booking-a'), { coachId: 'coach-b' }));
    await assertFails(updateDoc(doc(studentDb, 'bookings', 'booking-a'), { studentId: 'student-b' }));
    await assertFails(updateDoc(doc(studentDb, 'bookings', 'booking-a'), { status: 'confirmed' }));
  });
});

testAfterFix('coach can mutate only bookings and lessons they own', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
  await seed('lessons/lesson-a', lessonData());
  await seed('lessons/lesson-b', lessonData({ studentId: 'student-b', coachId: 'coach-b', bookingId: 'booking-b' }));
  const coachA = coachContext('coach-a');
  await t.test('own records succeed', async () => {
    await assertSucceeds(updateDoc(doc(coachA, 'bookings', 'booking-a'), { status: 'confirmed' }));
    await assertSucceeds(updateDoc(doc(coachA, 'lessons', 'lesson-a'), { status: 'completed' }));
  });
  await t.test('foreign records fail', async () => {
    await seedRelationship();
    await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
    await seed('lessons/lesson-b', lessonData({ studentId: 'student-b', coachId: 'coach-b', bookingId: 'booking-b' }));
    await assertFails(updateDoc(doc(coachA, 'bookings', 'booking-b'), { status: 'confirmed' }));
    await assertFails(deleteDoc(doc(coachA, 'lessons', 'lesson-b')));
  });
});

testAfterFix('slot rules permit valid own booking locks and reject forged locks', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  const coachA = coachContext('coach-a');
  const studentA = context('student-a');
  await t.test('coach can create both deterministic resource slots for own booking', async () => {
    await assertSucceeds(setDoc(doc(coachA, 'booking_slots', 'coach_coach-a_1900000000000'), slotData()));
    await assertSucceeds(setDoc(doc(coachA, 'booking_slots', 'student_student-a_1900000000000'), slotData({ resourceType: 'student', resourceId: 'student-a' })));
  });
  await t.test('coach cannot create a slot for another coach booking', async () => {
    await assertFails(setDoc(doc(coachA, 'booking_slots', 'coach_coach-b_1900000000000'), slotData({
      bookingId: 'booking-b', studentId: 'student-b', coachId: 'coach-b', resourceId: 'coach-b',
    })));
  });
  await t.test('student can create a valid own booking slot but cannot forge the interval or identity', async () => {
    await seedRelationship();
    await seed('bookings/booking-a', bookingData());
    await assertSucceeds(setDoc(doc(studentA, 'booking_slots', 'coach_coach-a_1900000600000'), slotData({ blockStart: when(10) })));
    await assertFails(setDoc(doc(studentA, 'booking_slots', 'coach_coach-a_1900000000001'), slotData({ blockStart: when(70) })));
    await assertFails(setDoc(doc(studentA, 'booking_slots', 'coach_coach-a_1900000000002'), slotData({ studentId: 'student-b' })));
  });
});

testAfterFix('slot updates and deletes cannot transfer or remove another booking lock', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
  await seed('booking_slots/coach_coach-a_1900000000000', slotData());
  await seed('booking_slots/coach_coach-b_1900000000000', slotData({
    bookingId: 'booking-b', studentId: 'student-b', coachId: 'coach-b', resourceId: 'coach-b',
  }));
  const coachA = coachContext('coach-a');
  await t.test('identity transfer fails', async () => {
    await assertFails(updateDoc(doc(coachA, 'booking_slots', 'coach_coach-a_1900000000000'), { bookingId: 'booking-b' }));
  });
  await t.test('foreign delete fails', async () => {
    await seedRelationship();
    await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
    await seed('booking_slots/coach_coach-b_1900000000000', slotData({
      bookingId: 'booking-b', studentId: 'student-b', coachId: 'coach-b', resourceId: 'coach-b',
    }));
    await assertFails(deleteDoc(doc(coachA, 'booking_slots', 'coach_coach-b_1900000000000')));
  });
});

testAfterFix('coach slot reads are limited to the slot and booking owner', async (t) => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await seed('bookings/booking-b', bookingData({ studentId: 'student-b', coachId: 'coach-b' }));
  await seed('booking_slots/coach_coach-a_1900000000000', slotData());
  await seed('booking_slots/coach_coach-b_1900000000000', slotData({
    bookingId: 'booking-b', studentId: 'student-b', coachId: 'coach-b', resourceId: 'coach-b',
  }));
  const coachA = coachContext('coach-a');
  await t.test('own slot document can be read and another coach slot cannot', async () => {
    await assertSucceeds(getDoc(doc(coachA, 'booking_slots', 'coach_coach-a_1900000000000')));
    await assertFails(getDoc(doc(coachA, 'booking_slots', 'coach_coach-b_1900000000000')));
  });
  await t.test('unscoped collection query is denied', async () => {
    await seedRelationship();
    await seed('bookings/booking-a', bookingData());
    await seed('booking_slots/coach_coach-a_1900000000000', slotData());
    await assertSucceeds(getDocs(query(
      collection(coachA, 'booking_slots'),
      where('coachId', '==', 'coach-a'),
    )));
    await assertFails(getDocs(collection(coachA, 'booking_slots')));
  });
});

testAfterFix('coach plans and notes require both assigned student and document coach ownership', async (t) => {
  const managedData = (overrides = {}) => ({
    studentId: 'student-a', coachId: 'coach-a', updatedAt: when(), ...overrides,
  });
  async function seedManagedContent() {
    await seedRelationship();
    await seed('nutrition_plans/nutrition-a', managedData());
    await seed('nutrition_plans/nutrition-b', managedData({ studentId: 'student-b', coachId: 'coach-b' }));
    await seed('exercise_programs/exercise-a', managedData());
    await seed('exercise_programs/exercise-b', managedData({ studentId: 'student-b', coachId: 'coach-b' }));
    await seed('coach_notes/lesson-a', managedData({ lessonId: 'lesson-a' }));
    await seed('coach_notes/lesson-b', managedData({ lessonId: 'lesson-b', studentId: 'student-b', coachId: 'coach-b' }));
  }
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const studentA = context('student-a');
  const ownedCollections = [
    ['nutrition_plans', 'nutrition-a', 'nutrition-b'],
    ['exercise_programs', 'exercise-a', 'exercise-b'],
    ['coach_notes', 'lesson-a', 'lesson-b'],
  ];
  await t.test('related coach reads own documents through the scoped query', async () => {
    await seedManagedContent();
    for (const [name, ownId] of ownedCollections) {
      await assertSucceeds(getDoc(doc(coachA, name, ownId)));
      await assertSucceeds(getDocs(query(
        collection(coachA, name),
        where('studentId', '==', 'student-a'),
        where('coachId', '==', 'coach-a'),
      )));
    }
  });
  await t.test('unrelated coach cannot read, write, or query another coach data', async () => {
    await seedManagedContent();
    for (const [name, ownId] of ownedCollections) {
      await assertFails(getDoc(doc(coachB, name, ownId)));
      await assertFails(updateDoc(doc(coachB, name, ownId), { updatedAt: serverTimestamp() }));
      await assertFails(getDocs(collection(coachB, name)));
    }
    await assertFails(setDoc(doc(coachB, 'nutrition_plans', 'nutrition-for-student-a'), {
      ...managedData({ coachId: 'coach-b' }),
    }));
  });
  await t.test('student keeps read-only access to their own managed documents', async () => {
    await seedManagedContent();
    await assertSucceeds(getDoc(doc(studentA, 'nutrition_plans', 'nutrition-a')));
    await assertSucceeds(getDoc(doc(studentA, 'exercise_programs', 'exercise-a')));
    await assertSucceeds(getDoc(doc(studentA, 'coach_notes', 'lesson-a')));
    await assertFails(updateDoc(doc(studentA, 'nutrition_plans', 'nutrition-a'), { title: 'Forged' }));
  });
});

testAfterFix('package requests enforce pending creation and coach-owned transitions', async (t) => {
  await seedRelationship();
  const studentA = context('student-a');
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const request = (overrides = {}) => ({
    studentId: 'student-a', sportId: 'fitness', packageId: 'package-a', packageName: 'Monthly',
    coachId: 'coach-a', status: 'pending', requestedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
  });
  await t.test('student creates only own pending request', async () => {
    await assertSucceeds(setDoc(doc(studentA, 'package_requests', 'request-a'), request()));
    await assertFails(setDoc(doc(studentA, 'package_requests', 'request-b'), request({ status: 'approved' })));
    await assertFails(setDoc(doc(studentA, 'package_requests', 'request-c'), request({ coachId: 'coach-b' })));
    await assertFails(setDoc(doc(studentA, 'package_requests', 'request-d'), request({ coachId: null })));
  });
  await testEnv.clearFirestore();
  await seedRelationship();
  await seed('package_requests/request-a', request());
  await t.test('own coach may approve or edit pending and approved package fields', async () => {
    await assertSucceeds(updateDoc(doc(coachA, 'package_requests', 'request-a'), { status: 'approved', coachId: 'coach-a', reviewedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(coachA, 'package_requests', 'request-a'), { packageId: 'package-b', packageName: 'Annual' }));
    await seed('package_requests/request-reject', request());
    await assertSucceeds(updateDoc(doc(coachA, 'package_requests', 'request-reject'), { status: 'rejected', coachId: 'coach-a', reviewedAt: serverTimestamp() }));
  });
  await t.test('foreign coach and invalid reversal fail', async () => {
    await seedRelationship();
    await seed('package_requests/request-a', request({ status: 'approved', coachId: 'coach-a' }));
    await assertFails(updateDoc(doc(coachB, 'package_requests', 'request-a'), { status: 'approved' }));
    await assertFails(updateDoc(doc(coachA, 'package_requests', 'request-a'), { status: 'pending' }));
  });
});

testAfterFix('profile, package, availability, and lesson-request ownership is coach-scoped', async (t) => {
  await seedRelationship();
  await seed('student_packages/student-a', { studentId: 'student-a', totalLessons: 8, usedLessons: 0, remainingLessons: 8, paymentStatus: 'pending' });
  await seed('availabilities/student-a_1', { studentId: 'student-a', dayOfWeek: 1, dayName: 'Monday', startTime: '10:00', endTime: '11:00', active: true, createdAt: when() });
  await seed('lessons/lesson-a', lessonData());
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const studentA = context('student-a');
  await t.test('student cannot alter package counters or protected profile fields', async () => {
    await assertFails(updateDoc(doc(studentA, 'student_packages', 'student-a'), { remainingLessons: 99 }));
    await assertFails(updateDoc(doc(studentA, 'student_profiles', 'student-a'), { coachId: 'coach-b' }));
  });
  await t.test('related coach can update package/profile/availability, unrelated coach cannot', async () => {
    await seedRelationship();
    await seed('student_packages/student-a', { studentId: 'student-a', totalLessons: 8, usedLessons: 0, remainingLessons: 8, paymentStatus: 'pending' });
    await seed('availabilities/student-a_1', { studentId: 'student-a', dayOfWeek: 1, dayName: 'Monday', startTime: '10:00', endTime: '11:00', active: true, createdAt: when() });
    await assertSucceeds(updateDoc(doc(coachA, 'student_packages', 'student-a'), { remainingLessons: 7 }));
    await assertSucceeds(updateDoc(doc(coachA, 'student_profiles', 'student-a'), { packageId: 'package-a', status: 'active' }));
    await assertSucceeds(updateDoc(doc(coachA, 'availabilities', 'student-a_1'), { startTime: '11:00' }));
    await assertFails(updateDoc(doc(coachB, 'student_packages', 'student-a'), { remainingLessons: 1 }));
    await assertFails(deleteDoc(doc(coachB, 'availabilities', 'student-a_1')));
  });
  await t.test('student availability and lesson requests retain ownership boundaries', async () => {
    await seedRelationship();
    await seed('availabilities/student-a_1', { studentId: 'student-a', dayOfWeek: 1, dayName: 'Monday', startTime: '10:00', endTime: '11:00', active: true, createdAt: when() });
    await seed('lessons/lesson-a', lessonData());
    await assertFails(updateDoc(doc(studentA, 'availabilities', 'student-a_1'), { studentId: 'student-b' }));
    await assertSucceeds(setDoc(doc(studentA, 'lesson_change_requests', 'change-a'), {
      studentId: 'student-a', coachId: 'coach-a', lessonId: 'lesson-a', type: 'reschedule', reason: 'Need another time', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(studentA, 'lesson_change_requests', 'change-wrong-coach'), {
      studentId: 'student-a', coachId: 'coach-b', lessonId: 'lesson-a', type: 'reschedule', reason: 'Need another time', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(coachA, 'lesson_change_requests', 'change-a'), { status: 'approved', coachId: 'coach-a', reviewedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(coachA, 'lesson_change_requests', 'change-a')));
    await seed('lesson_change_requests/change-b', {
      studentId: 'student-a', lessonId: 'lesson-a', type: 'reschedule', reason: 'Need another time', status: 'pending', createdAt: when(), updatedAt: when(),
    });
    await assertFails(updateDoc(doc(coachB, 'lesson_change_requests', 'change-b'), { status: 'rejected' }));
    await assertFails(deleteDoc(doc(coachB, 'lesson_change_requests', 'change-b')));
  });
});

testAfterFix('student-created ownership fields must match the active profile and lesson', async (t) => {
  await seedRelationship();
  await seed('lessons/lesson-a', lessonData());
  const studentA = context('student-a');
  const availability = (overrides = {}) => ({
    studentId: 'student-a', coachId: 'coach-a', dayOfWeek: 1,
    dayName: 'Monday', startTime: '10:00', endTime: '11:00', active: true,
    createdAt: when(), ...overrides,
  });
  await t.test('availability uses the profile coachId', async () => {
    await assertSucceeds(setDoc(doc(studentA, 'availabilities', 'student-a_1'), availability()));
    await assertFails(setDoc(doc(studentA, 'availabilities', 'student-a_2'), availability({ coachId: 'coach-b' })));
    await assertFails(updateDoc(doc(studentA, 'availabilities', 'student-a_1'), { coachId: 'coach-b' }));
  });
  await t.test('student and coach cannot transfer persisted ownership', async () => {
    await seed('package_requests/owned-package', {
      studentId: 'student-a', coachId: 'coach-a', status: 'pending',
      sportId: 'fitness', packageId: 'package-a', packageName: 'Monthly',
    });
    await seed('student_packages/student-a', {
      studentId: 'student-a', coachId: 'coach-a', remainingLessons: 8,
    });
    await assertFails(updateDoc(doc(studentA, 'package_requests', 'owned-package'), { coachId: 'coach-b' }));
    await assertFails(updateDoc(doc(coachContext('coach-a'), 'student_packages', 'student-a'), { coachId: 'coach-b' }));
    await seed('lesson_change_requests/owned-change', {
      studentId: 'student-a', coachId: 'coach-a', lessonId: 'lesson-a',
      type: 'reschedule', reason: 'Need another time', status: 'pending',
    });
    await assertFails(updateDoc(doc(studentA, 'lesson_change_requests', 'owned-change'), { coachId: 'coach-b' }));
  });
});
