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
  runTransaction,
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

testAfterFix('V2 approval transaction feasibility: fourteen related writes stay inside the Rules access-call budget', async () => {
  await seedRelationship();
  await seed('bookings/booking-a', bookingData());
  await seed('package_requests/package-a', {
    studentId: 'student-a', coachId: 'coach-a', packageId: 'package-a',
    status: 'pending', requestedAt: when(), updatedAt: when(),
  });

  const coachDb = coachContext('coach-a');
  await assertSucceeds(runTransaction(coachDb, async (transaction) => {
    // A transaction read is deliberately completed before any of its writes.
    const booking = await transaction.get(doc(coachDb, 'bookings', 'booking-a'));
    assert.equal(booking.exists(), true);

    // Five Coach and five Student busy-block equivalents, followed by the
    // future Session, Booking Request, Entitlement, and roster equivalents.
    for (var index = 0; index < 5; index += 1) {
      transaction.set(
        doc(coachDb, 'booking_slots', `coach_coach-a_${1900000000000 + index * 600000}`),
        slotData({ blockStart: when(index * 10) }),
      );
      transaction.set(
        doc(coachDb, 'booking_slots', `student_student-a_${1900000000000 + index * 600000}`),
        slotData({
          resourceType: 'student', resourceId: 'student-a', blockStart: when(index * 10),
        }),
      );
    }
    transaction.set(doc(coachDb, 'lessons', 'lesson-feasibility'), lessonData({ bookingId: 'booking-a' }));
    transaction.update(doc(coachDb, 'bookings', 'booking-a'), { updatedAt: when() });
    transaction.set(doc(coachDb, 'student_packages', 'student-a'), {
      studentId: 'student-a', coachId: 'coach-a', packageId: 'package-a',
      remainingLessons: 9,
    });
    transaction.update(doc(coachDb, 'package_requests', 'package-a'), { updatedAt: when() });
  }));
});

const context = (uid, claims = {}) =>
  testEnv.authenticatedContext(uid, claims).firestore();
const rolesClaim = (...roles) => ({
  roles: Object.fromEntries(roles.map((role) => [role, true])),
});
const coachContext = (uid) => context(uid, rolesClaim('coach'));
const adminContext = (uid) => context(uid, rolesClaim('admin'));
const multiRoleContext = (uid) => context(uid, rolesClaim('coach', 'admin'));
const studentClaimContext = (uid) => context(uid, rolesClaim('student'));
const legacyCoachContext = (uid) => context(uid, { role: 'coach' });
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

testAfterFix('claimed coach retains existing coaching permissions and only private self metadata updates', async () => {
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
      fullName: 'Coach A Updated',
      phone: '5552222222',
      locale: 'tr-TR',
      updatedAt: serverTimestamp(),
    }),
  );
});

testAfterFix('canonical role maps are authoritative while the scalar claim remains a temporary fallback', async (t) => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('student_profiles/student-a', { status: 'pending' });

  await t.test('canonical coach claim can manage coaching', async () => {
    await assertSucceeds(updateDoc(doc(coachContext('coach-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'coach-a',
    }));
  });

  await testEnv.clearFirestore();
  await seed('student_profiles/student-a', { status: 'pending' });
  await t.test('admin and combined coach/admin claims can manage coaching', async () => {
    await assertSucceeds(updateDoc(doc(adminContext('admin-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'admin-a',
    }));
    await testEnv.clearFirestore();
    await seed('student_profiles/student-a', { status: 'pending' });
    await assertSucceeds(updateDoc(doc(multiRoleContext('owner-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'owner-a',
    }));
  });

  await testEnv.clearFirestore();
  await seed('student_profiles/student-a', { status: 'pending' });
  await t.test('legacy scalar coach stays compatible during the transition', async () => {
    await assertSucceeds(updateDoc(doc(legacyCoachContext('legacy-coach'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'legacy-coach',
    }));
  });

  await testEnv.clearFirestore();
  await seed('users/metadata-coach', { uid: 'metadata-coach', role: 'coach' });
  await seed('student_profiles/student-a', { status: 'pending' });
  await t.test('student-only and claimless identities cannot gain coach access from users metadata', async () => {
    await assertFails(updateDoc(doc(studentClaimContext('student-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'student-a',
    }));
    await assertFails(updateDoc(doc(claimlessContext('metadata-coach'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'metadata-coach',
    }));
  });
});

testAfterFix('a refreshed canonical-claim token is required before Coach access succeeds', async (t) => {
  await t.test('claimless token is denied', async () => {
    await seed('student_profiles/student-a', { status: 'pending' });
    await assertFails(updateDoc(doc(claimlessContext('coach-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'coach-a',
    }));
  });
  await t.test('a new token carrying canonical coach claim succeeds', async () => {
    await seed('student_profiles/student-a', { status: 'pending' });
    await assertSucceeds(updateDoc(doc(coachContext('coach-a'), 'student_profiles', 'student-a'), {
      status: 'active', coachId: 'coach-a',
    }));
  });
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

testAfterFix('coach cannot mutate a related Students private users metadata', async () => {
  await seed('users/coach-a', { uid: 'coach-a', role: 'coach' });
  await seed('users/student-a', studentUser());
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  await assertFails(
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

testAfterFix('users metadata is private to self or a directly assigned Coach', async (t) => {
  await seed('users/student-a', studentUser());
  await seed('users/student-b', studentUser({ uid: 'student-b' }));
  await seed('student_profiles/student-a', { status: 'active', coachId: 'coach-a' });
  await seed('student_profiles/student-b', { status: 'active', coachId: 'coach-b' });
  const coachA = coachContext('coach-a');
  await t.test('assigned direct document read succeeds', async () => {
    await assertSucceeds(getDoc(userRef(coachA, 'student-a')));
  });
  await t.test('foreign direct document read and global query fail', async () => {
    await assertFails(getDoc(userRef(coachA, 'student-b')));
    await assertFails(getDocs(collection(coachA, 'users')));
  });
  await t.test('users role metadata does not refresh authorization', async () => {
    await seed('users/metadata-coach', { uid: 'metadata-coach', role: 'coach' });
    await assertFails(getDoc(userRef(claimlessContext('metadata-coach'), 'student-a')));
  });
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

testAfterFix('V2 sports and public coach discovery profiles retain trusted ownership boundaries', async (t) => {
  const coachProfile = (overrides = {}) => ({
    displayName: 'Coach A', active: true, bookingEnabled: true,
    specialtyIds: ['tennis'], bio: 'Public bio', photoUrl: '',
    createdAt: when(), createdBy: 'provisioner-a',
    updatedAt: when(), updatedBy: 'provisioner-a', schemaVersion: 2,
    ...overrides,
  });
  const seedSports = () => seed('sports/tennis', {
    name: 'Tennis', active: true, sortOrder: 10,
    createdAt: when(), createdBy: 'provisioner-a', updatedAt: when(),
    updatedBy: 'provisioner-a', schemaVersion: 2,
  });
  const seedDiscoveryProfiles = async () => {
    await seed('coach_profiles/coach-a', coachProfile());
    await seed('coach_profiles/coach-b', coachProfile({
      displayName: 'Coach B', specialtyIds: ['fitness'],
    }));
    await seed('coach_profiles/coach-inactive', coachProfile({
      displayName: 'Inactive Coach', active: false,
    }));
    await seed('coach_profiles/coach-hidden', coachProfile({
      displayName: 'Hidden Coach', bookingEnabled: false,
    }));
  };

  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const studentA = studentClaimContext('student-a');
  const discoveryQuery = () => query(
    collection(studentA, 'coach_profiles'),
    where('specialtyIds', 'array-contains', 'tennis'),
    where('active', '==', true),
    where('bookingEnabled', '==', true),
  );

  await t.test('authenticated Student can read active sports but no client can write them', async () => {
    await seedSports();
    await assertSucceeds(getDocs(query(
      collection(studentA, 'sports'), where('active', '==', true),
    )));
    await assertFails(setDoc(doc(studentA, 'sports', 'fitness'), { name: 'Fitness' }));
    await assertFails(updateDoc(doc(coachA, 'sports', 'tennis'), { name: 'Changed' }));
  });

  await t.test('Coach can edit only own allowed public profile fields', async () => {
    await seedDiscoveryProfiles();
    await assertSucceeds(updateDoc(doc(coachA, 'coach_profiles', 'coach-a'), {
      displayName: 'Coach A Updated', bio: 'Updated bio', photoUrl: 'https://example.test/a.png',
      specialtyIds: ['tennis', 'fitness'], updatedAt: when(), updatedBy: 'coach-a',
    }));
    await assertFails(updateDoc(doc(coachA, 'coach_profiles', 'coach-a'), {
      active: false,
    }));
    await assertFails(updateDoc(doc(coachA, 'coach_profiles', 'coach-a'), {
      bookingEnabled: false,
    }));
    await assertFails(updateDoc(doc(coachA, 'coach_profiles', 'coach-a'), {
      schemaVersion: 3,
    }));
    await assertFails(updateDoc(doc(coachB, 'coach_profiles', 'coach-a'), {
      bio: 'Foreign update', updatedAt: when(), updatedBy: 'coach-b',
    }));
    await assertFails(updateDoc(doc(studentA, 'coach_profiles', 'coach-a'), {
      bio: 'Student update', updatedAt: when(), updatedBy: 'student-a',
    }));
  });

  await t.test('discovery query returns only active matching booking-enabled Coaches', async () => {
    await seedDiscoveryProfiles();
    const result = await getDocs(discoveryQuery());
    assert.deepEqual(result.docs.map((item) => item.id), ['coach-a']);
  });

  await t.test('users role metadata does not authorize coach profile edits', async () => {
    await seed('users/metadata-coach', { uid: 'metadata-coach', role: 'coach' });
    await seed('coach_profiles/metadata-coach', coachProfile({
      createdBy: 'provisioner-a', updatedBy: 'provisioner-a',
    }));
    await assertFails(updateDoc(doc(claimlessContext('metadata-coach'), 'coach_profiles', 'metadata-coach'), {
      bio: 'Unauthorized', updatedAt: when(), updatedBy: 'metadata-coach',
    }));
  });

  await t.test('legacy scalar coach claim remains compatible with profile editing', async () => {
    await seed('coach_profiles/legacy-coach', coachProfile());
    await assertSucceeds(updateDoc(doc(legacyCoachContext('legacy-coach'), 'coach_profiles', 'legacy-coach'), {
      bio: 'Legacy compatible', updatedAt: when(), updatedBy: 'legacy-coach',
    }));
  });
});

testAfterFix('V2 Coach schedule availability is self-owned and coordinate-safe', async (t) => {
  const slotPath = (coachId, dayKey = '2026-08-03', slotId = '0900') =>
    ['coach_schedule_slots', coachId, 'days', dayKey, 'slots', slotId];
  const availability = (overrides = {}) => ({
    active: true,
    schemaVersion: 2,
    ...overrides,
  });

  const seedActiveTemplate = () => seed('schedule_slot_templates/0900', {
    slotId: '0900', sequence: 1, active: true, schemaVersion: 2,
  });

  await t.test('Coach can create, read, and close only an own canonical slot', async () => {
    await seedActiveTemplate();
    const coachA = coachContext('coach-a');
    const reference = doc(coachA, ...slotPath('coach-a'));
    await assertSucceeds(setDoc(reference, availability()));
    await assertSucceeds(getDoc(reference));
    await assertSucceeds(updateDoc(reference, { active: false }));
  });

  await t.test('cross-Coach, Student, invalid coordinate, and extra fields fail', async () => {
    await seedActiveTemplate();
    const coachA = coachContext('coach-a');
    const coachB = coachContext('coach-b');
    const student = studentClaimContext('student-a');
    const ownReference = doc(coachA, ...slotPath('coach-a'));
    await assertSucceeds(setDoc(ownReference, availability()));
    await assertFails(updateDoc(
      doc(coachB, ...slotPath('coach-a')),
      { active: false },
    ));
    await assertFails(setDoc(
      doc(student, ...slotPath('coach-a')),
      availability(),
    ));
    await assertFails(setDoc(
      doc(coachA, ...slotPath('coach-a', '2026-8-03')),
      availability(),
    ));
    await assertFails(setDoc(
      doc(coachA, ...slotPath('coach-a', '2026-08-03', '0910')),
      availability(),
    ));
    await assertFails(setDoc(
      doc(coachA, ...slotPath('coach-a', '2026-08-03', '1000')),
      availability({ note: 'forged field' }),
    ));
  });

  await t.test('schema and coordinate records cannot be rewritten or deleted', async () => {
    await seedActiveTemplate();
    const coachA = coachContext('coach-a');
    const reference = doc(coachA, ...slotPath('coach-a'));
    await assertSucceeds(setDoc(reference, availability()));
    await assertFails(updateDoc(reference, { schemaVersion: 3 }));
    await assertFails(updateDoc(reference, { note: 'forged field' }));
    await assertFails(deleteDoc(reference));
  });

  await t.test('an inactive trusted template prevents new or reactivated availability', async () => {
    await seed('schedule_slot_templates/1000', {
      slotId: '1000', sequence: 2, active: false, schemaVersion: 2,
    });
    const coachA = coachContext('coach-a');
    const reference = doc(coachA, ...slotPath('coach-a', '2026-08-03', '1000'));
    await assertFails(setDoc(reference, availability()));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), ...slotPath('coach-a', '2026-08-03', '1000')), availability({ active: false }));
    });
    await assertFails(updateDoc(reference, { active: true }));
  });
});

testAfterFix('V2 Student availability discovery is scoped to active Coach/day slots', async (t) => {
  const slotPath = (coachId, dayKey = '2026-08-03', slotId = '0900') =>
    ['coach_schedule_slots', coachId, 'days', dayKey, 'slots', slotId];
  const availability = (active) => ({ active, schemaVersion: 2 });

  const seedDay = () => testEnv.withSecurityRulesDisabled(async (admin) => {
    const firestore = admin.firestore();
    await setDoc(doc(firestore, ...slotPath('coach-a', '2026-08-03', '0900')), availability(true));
    await setDoc(doc(firestore, ...slotPath('coach-a', '2026-08-03', '1000')), availability(false));
    await setDoc(doc(firestore, ...slotPath('coach-b', '2026-08-03', '0900')), availability(true));
    await setDoc(doc(firestore, ...slotPath('coach-a', '2026-8-03', '0900')), availability(true));
  });

  const student = studentClaimContext('student-a');
  const coachA = coachContext('coach-a');
  const claimless = claimlessContext('visitor-a');
  const ownDay = collection(student, ...slotPath('coach-a').slice(0, -1));

  await t.test('Student receives only active slots from the selected Coach/day', async () => {
    await seedDay();
    const active = await assertSucceeds(getDoc(
      doc(student, ...slotPath('coach-a', '2026-08-03', '0900')),
    ));
    assert.equal(active.id, '0900');
    await assertFails(getDocs(ownDay));
    await assertFails(getDoc(doc(student, ...slotPath('coach-a', '2026-08-03', '1000'))));
    await assertFails(getDoc(doc(student, ...slotPath('coach-a', '2026-8-03', '0900'))));
  });

  await t.test('Coach retains own-day read access while unauthenticated claims do not', async () => {
    await seedDay();
    await assertSucceeds(getDocs(collection(coachA, ...slotPath('coach-a').slice(0, -1))));
    await assertFails(getDoc(
      doc(claimless, ...slotPath('coach-a', '2026-08-03', '0900')),
    ));
  });

  await t.test('Student cannot write availability or read a non-canonical private path', async () => {
    await seedDay();
    await assertFails(setDoc(
      doc(student, ...slotPath('coach-a', '2026-08-04', '0900')),
      availability(true),
    ));
    await assertFails(getDocs(query(
      collection(student, ...slotPath('coach-a', '2026-8-03').slice(0, -1)),
      where('active', '==', true),
    )));
  });
});

testAfterFix('V2 booking requests keep pending intent separate from scheduling', async (t) => {
  const requestPath = (id = 'request-a') => ['booking_requests', id];
  const requestData = (overrides = {}) => ({
    studentId: 'student-a', coachId: 'coach-a', sportId: 'tennis',
    dayKey: '2026-08-03', slotId: '0900', status: 'pending',
    schemaVersion: 2, createdAt: serverTimestamp(), createdBy: 'student-a',
    updatedAt: serverTimestamp(), updatedBy: 'student-a',
    ...overrides,
  });
  const persistedRequest = (overrides = {}) => ({
    ...requestData(overrides), createdAt: when(), updatedAt: when(),
  });
  const seedPrerequisites = async ({ templateActive = true, availabilityActive = true } = {}) => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      await setDoc(doc(firestore, 'sports', 'tennis'), {
        active: true, schemaVersion: 2,
      });
      await setDoc(doc(firestore, 'coach_profiles', 'coach-a'), {
        active: true, bookingEnabled: true, specialtyIds: ['tennis'], schemaVersion: 2,
      });
      await setDoc(doc(firestore, 'schedule_slot_templates', '0900'), {
        slotId: '0900', sequence: 1, active: templateActive, schemaVersion: 2,
      });
      await setDoc(doc(firestore,
        'coach_schedule_slots', 'coach-a', 'days', '2026-08-03', 'slots', '0900',
      ), { active: availabilityActive, schemaVersion: 2 });
    });
  };
  const studentA = studentClaimContext('student-a');
  const studentB = studentClaimContext('student-b');
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');

  await t.test('Student creates only own pending intent and no Session, lock, or entitlement', async () => {
    await seedPrerequisites();
    await assertSucceeds(setDoc(doc(studentA, ...requestPath()), requestData()));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      assert.equal((await getDocs(collection(firestore, 'sessions'))).size, 0);
      assert.equal((await getDocs(collection(firestore, 'coach_busy_blocks'))).size, 0);
      assert.equal((await getDocs(collection(firestore, 'student_busy_blocks'))).size, 0);
      assert.equal((await getDocs(collection(firestore, 'student_entitlements'))).size, 0);
    });
  });

  await t.test('create requires active availability, template, and canonical fields', async () => {
    await seedPrerequisites({ availabilityActive: false });
    await assertFails(setDoc(doc(studentA, ...requestPath()), requestData()));
    await testEnv.clearFirestore();
    await seedPrerequisites({ templateActive: false });
    await assertFails(setDoc(doc(studentA, ...requestPath()), requestData()));
    await testEnv.clearFirestore();
    await seedPrerequisites();
    await assertFails(setDoc(doc(studentA, ...requestPath()), requestData({ dayKey: '2026-8-03' })));
    await assertFails(setDoc(doc(studentA, ...requestPath()), requestData({ slotId: '0910' })));
    await assertFails(setDoc(doc(studentA, ...requestPath()), requestData({ note: 'forged' })));
  });

  await t.test('cross-Student create and invalid lifecycle values are denied', async () => {
    await seedPrerequisites();
    await assertFails(setDoc(doc(studentB, ...requestPath()), requestData()));
    await assertFails(setDoc(doc(studentA, ...requestPath('request-approved')), requestData({ status: 'approved' })));
    await assertFails(setDoc(doc(studentA, ...requestPath('request-rejected')), requestData({ status: 'rejected' })));
  });

  await t.test('Student may only withdraw own pending request', async () => {
    await seed('booking_requests/request-a', persistedRequest());
    await assertSucceeds(updateDoc(doc(studentA, ...requestPath()), {
      status: 'withdrawn', updatedAt: serverTimestamp(), updatedBy: 'student-a',
    }));
    await assertFails(updateDoc(doc(studentA, ...requestPath()), {
      status: 'rejected', updatedAt: serverTimestamp(), updatedBy: 'student-a',
    }));
  });

  await t.test('Coach may only reject own pending request', async () => {
    await seed('booking_requests/request-a', persistedRequest());
    await assertSucceeds(updateDoc(doc(coachA, ...requestPath()), {
      status: 'rejected', updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    }));
    await seed('booking_requests/request-b', persistedRequest());
    await assertFails(updateDoc(doc(coachB, ...requestPath('request-b')), {
      status: 'rejected', updatedAt: serverTimestamp(), updatedBy: 'coach-b',
    }));
    await seed('booking_requests/request-c', persistedRequest());
    await assertFails(updateDoc(doc(coachA, ...requestPath('request-c')), {
      status: 'withdrawn', updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    }));
  });

  await t.test('immutable coordinates, approval, foreign updates, and delete are denied', async () => {
    await seed('booking_requests/request-a', persistedRequest());
    await assertFails(updateDoc(doc(studentA, ...requestPath()), {
      dayKey: '2026-08-04', updatedAt: serverTimestamp(), updatedBy: 'student-a',
    }));
    await assertFails(updateDoc(doc(coachA, ...requestPath()), {
      status: 'approved', updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    }));
    await assertFails(updateDoc(doc(studentB, ...requestPath()), {
      status: 'withdrawn', updatedAt: serverTimestamp(), updatedBy: 'student-b',
    }));
    await assertFails(deleteDoc(doc(studentA, ...requestPath())));
    await assertFails(deleteDoc(doc(coachA, ...requestPath())));
  });

  await t.test('scoped Student and Coach repository query shapes are permitted', async () => {
    await seed('booking_requests/request-a', persistedRequest());
    await assertSucceeds(getDocs(query(
      collection(studentA, 'booking_requests'), where('studentId', '==', 'student-a'),
    )));
    await assertSucceeds(getDocs(query(
      collection(coachA, 'booking_requests'),
      where('coachId', '==', 'coach-a'), where('status', '==', 'pending'),
    )));
    await assertFails(getDocs(collection(studentA, 'booking_requests')));
    await assertFails(getDocs(collection(coachB, 'booking_requests')));
  });
});

testAfterFix('V2 Coach approval atomically creates one Session and two reservation coordinates', async (t) => {
  const dayKey = '2026-08-03';
  const slotId = '0900';
  const seedApprovalPrerequisites = async (requestId, studentId = 'student-a') => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      await setDoc(doc(firestore, 'schedule_slot_templates', slotId), {
        slotId, sequence: 1, active: true, schemaVersion: 2,
      });
      await setDoc(doc(
        firestore, 'coach_schedule_slots', 'coach-a', 'days', dayKey, 'slots', slotId,
      ), { active: true, schemaVersion: 2 });
      await setDoc(doc(firestore, 'student_entitlements', studentId), {
        studentId, packageId: 'package-tennis', sportId: 'tennis',
        packageType: 'tenSession', totalSessions: 10, remainingSessions: 10,
        validityDays: 42, status: 'active', schemaVersion: 2,
        createdAt: when(), createdBy: 'coach-a', updatedAt: when(), updatedBy: 'coach-a',
      });
      await setDoc(doc(firestore, 'booking_requests', requestId), {
        studentId, coachId: 'coach-a', sportId: 'tennis', dayKey, slotId,
        status: 'pending', schemaVersion: 2,
        createdAt: when(), createdBy: studentId,
        updatedAt: when(), updatedBy: studentId,
      });
    });
  };
  const approve = (db, requestId, studentId = 'student-a') => runTransaction(db, async (tx) => {
    const requestRef = doc(db, 'booking_requests', requestId);
    const sessionRef = doc(db, 'sessions', requestId);
    const coachSlotRef = doc(
      db, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', slotId,
    );
    const studentSlotRef = doc(
      db, 'student_session_slots', studentId, 'days', dayKey, 'slots', slotId,
    );
    const entitlementRef = doc(db, 'student_entitlements', studentId);
    const rosterRef = doc(db, 'coaches', 'coach-a', 'students', studentId);
    const availabilityRef = doc(
      db, 'coach_schedule_slots', 'coach-a', 'days', dayKey, 'slots', slotId,
    );
    const [request, availability] = await Promise.all([
      tx.get(requestRef), tx.get(availabilityRef),
    ]);
    if (!request.exists() || !availability.data().active) {
      throw new Error('unavailable');
    }
    const audit = { schemaVersion: 2, createdAt: serverTimestamp(), createdBy: 'coach-a' };
    tx.update(requestRef, {
      status: 'approved', sessionId: requestId,
      updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    });
    tx.set(sessionRef, {
      bookingRequestId: requestId, studentId, coachId: 'coach-a', sportId: 'tennis',
      dayKey, slotId, entitlementId: studentId, status: 'scheduled', ...audit,
      updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    });
    tx.set(coachSlotRef, {
      sessionId: requestId, bookingRequestId: requestId, ownerId: 'coach-a',
      counterpartId: studentId, ...audit,
    });
    tx.set(studentSlotRef, {
      sessionId: requestId, bookingRequestId: requestId, ownerId: studentId,
      counterpartId: 'coach-a', ...audit,
    });
    tx.update(entitlementRef, {
      remainingSessions: 9, lastConsumedSessionId: requestId,
      updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    });
    tx.set(rosterRef, {
      coachId: 'coach-a', studentId, bookingRequestId: requestId,
      ...audit,
    });
  });
  const coachA = coachContext('coach-a');
  const coachB = coachContext('coach-b');
  const studentA = studentClaimContext('student-a');

  await t.test('matching full transaction succeeds and persists the complete graph', async () => {
    await testEnv.clearFirestore();
    await seedApprovalPrerequisites('request-a');
    await assertSucceeds(approve(coachA, 'request-a'));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      assert.equal((await getDoc(doc(firestore, 'booking_requests', 'request-a'))).data().status, 'approved');
      assert.equal((await getDoc(doc(firestore, 'sessions', 'request-a'))).data().bookingRequestId, 'request-a');
      assert.equal((await getDoc(doc(firestore, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', slotId))).data().sessionId, 'request-a');
      assert.equal((await getDoc(doc(firestore, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', slotId))).data().sessionId, 'request-a');
    });
  });

  await t.test('Student, foreign Coach, and partial approval writes are denied', async () => {
    await testEnv.clearFirestore();
    await seedApprovalPrerequisites('request-a');
    await assertFails(approve(studentA, 'request-a'));
    await assertFails(approve(coachB, 'request-a'));
    await assertFails(setDoc(doc(coachA, 'sessions', 'request-a'), {
      bookingRequestId: 'request-a', studentId: 'student-a', coachId: 'coach-a',
      sportId: 'tennis', dayKey, slotId, entitlementId: 'student-a', status: 'scheduled', schemaVersion: 2,
      createdAt: serverTimestamp(), createdBy: 'coach-a',
      updatedAt: serverTimestamp(), updatedBy: 'coach-a',
    }));
  });

  await t.test('competing approval keeps the loser entirely unmodified', async () => {
    await testEnv.clearFirestore();
    await seedApprovalPrerequisites('request-a', 'student-a');
    await seedApprovalPrerequisites('request-b', 'student-b');
    const outcomes = await Promise.allSettled([
      approve(coachA, 'request-a', 'student-a'),
      approve(coachA, 'request-b', 'student-b'),
    ]);
    assert.equal(outcomes.filter((result) => result.status === 'fulfilled').length, 1);
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      const requests = await Promise.all([
        getDoc(doc(firestore, 'booking_requests', 'request-a')),
        getDoc(doc(firestore, 'booking_requests', 'request-b')),
      ]);
      assert.equal(requests.filter((snapshot) => snapshot.data().status === 'approved').length, 1);
      assert.equal(requests.filter((snapshot) => snapshot.data().status === 'pending').length, 1);
      assert.equal((await getDocs(collection(firestore, 'sessions'))).size, 1);
    });
  });

  await t.test('Coach cancellation and normal approval leave only a complete final reservation state', async () => {
    await testEnv.clearFirestore();
    await seedApprovalPrerequisites('request-a', 'student-a');
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      const audit = { schemaVersion: 2, createdAt: when(), createdBy: 'coach-a', updatedAt: when(), updatedBy: 'coach-a' };
      await setDoc(doc(firestore, 'sessions', 'cancel-source'), {
        bookingRequestId: 'legacy-source', studentId: 'student-a', coachId: 'coach-a', sportId: 'tennis',
        dayKey, slotId, entitlementId: 'student-a', status: 'scheduled', ...audit,
      });
      await setDoc(doc(firestore, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', slotId), {
        sessionId: 'cancel-source', bookingRequestId: 'legacy-source', ownerId: 'coach-a', counterpartId: 'student-a', ...audit,
      });
      await setDoc(doc(firestore, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', slotId), {
        sessionId: 'cancel-source', bookingRequestId: 'legacy-source', ownerId: 'student-a', counterpartId: 'coach-a', ...audit,
      });
    });
    const cancel = runTransaction(coachA, async (tx) => {
      const source = doc(coachA, 'sessions', 'cancel-source');
      await tx.get(source);
      tx.update(source, { status: 'coach_cancelled', updatedAt: serverTimestamp(), updatedBy: 'coach-a' });
      tx.delete(doc(coachA, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', slotId));
      tx.delete(doc(coachA, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', slotId));
    });
    await Promise.allSettled([cancel, approve(coachA, 'request-a')]);
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const firestore = admin.firestore();
      const request = await getDoc(doc(firestore, 'booking_requests', 'request-a'));
      const approved = request.data().status === 'approved';
      const replacement = await getDoc(doc(firestore, 'sessions', 'request-a'));
      const coachSlot = await getDoc(doc(firestore, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', slotId));
      const studentSlot = await getDoc(doc(firestore, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', slotId));
      assert.equal(replacement.exists(), approved);
      assert.equal(coachSlot.exists(), approved);
      assert.equal(studentSlot.exists(), approved);
      assert.equal((await getDoc(doc(firestore, 'student_entitlements', 'student-a'))).data().remainingSessions, approved ? 9 : 10);
    });
  });
});

testAfterFix('V2 entitlement activation is roster-scoped and catalogue-backed', async (t) => {
  const seed = async (active = true) => testEnv.withSecurityRulesDisabled(async (admin) => {
    const firestore = admin.firestore();
    await setDoc(doc(firestore, 'coaches', 'coach-a', 'students', 'student-a'), {
      coachId: 'coach-a', studentId: 'student-a', bookingRequestId: 'request-a',
      schemaVersion: 2, createdAt: when(), createdBy: 'coach-a',
    });
    await setDoc(doc(firestore, 'package_catalog', 'package-tennis'), {
      packageId: 'package-tennis', sportId: 'tennis', packageType: 'tenSession',
      totalSessions: 10, validityDays: 42, active, schemaVersion: 2,
    });
  });
  const activation = {
    studentId: 'student-a', packageId: 'package-tennis', sportId: 'tennis',
    packageType: 'tenSession', totalSessions: 10, remainingSessions: 10,
    validityDays: 42, status: 'active', schemaVersion: 2,
    createdAt: serverTimestamp(), createdBy: 'coach-a',
    updatedAt: serverTimestamp(), updatedBy: 'coach-a',
  };
  await t.test('own roster Coach can activate exactly the active catalogue contract', async () => {
    await testEnv.clearFirestore(); await seed();
    await assertSucceeds(setDoc(doc(coachContext('coach-a'), 'student_entitlements', 'student-a'), activation));
  });
  await t.test('foreign Coach, Student, inactive catalogue, and inflated count are denied', async () => {
    await testEnv.clearFirestore(); await seed();
    await assertFails(setDoc(doc(coachContext('coach-b'), 'student_entitlements', 'student-a'), activation));
    await assertFails(setDoc(doc(studentClaimContext('student-a'), 'student_entitlements', 'student-a'), activation));
    await assertFails(setDoc(doc(coachContext('coach-a'), 'student_entitlements', 'student-a'), {
      ...activation, totalSessions: 11, remainingSessions: 11,
    }));
    await testEnv.clearFirestore(); await seed(false);
    await assertFails(setDoc(doc(coachContext('coach-a'), 'student_entitlements', 'student-a'), activation));
  });
});

testAfterFix('V2 cancellation and coach-only make-up preserve entitlement ownership', async (t) => {
  const dayKey = '2026-08-03';
  const seedSession = async (status = 'scheduled') => testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    const audit = { schemaVersion: 2, createdAt: when(), createdBy: 'coach-a', updatedAt: when(), updatedBy: 'coach-a' };
    await setDoc(doc(db, 'schedule_slot_templates', '1000'), { slotId: '1000', sequence: 2, active: true, schemaVersion: 2 });
    await setDoc(doc(db, 'coach_schedule_slots', 'coach-a', 'days', dayKey, 'slots', '1000'), { active: true, schemaVersion: 2 });
    await setDoc(doc(db, 'coaches', 'coach-a', 'students', 'student-a'), { coachId: 'coach-a', studentId: 'student-a', bookingRequestId: 'request-a', schemaVersion: 2, createdAt: when(), createdBy: 'coach-a' });
    await setDoc(doc(db, 'student_entitlements', 'student-a'), { studentId: 'student-a', packageId: 'package-a', sportId: 'tennis', packageType: 'tenSession', totalSessions: 10, remainingSessions: 9, validityDays: 42, status: 'active', ...audit });
    await setDoc(doc(db, 'sessions', 'source-a'), { bookingRequestId: 'request-a', studentId: 'student-a', coachId: 'coach-a', sportId: 'tennis', dayKey, slotId: '0900', entitlementId: 'student-a', status, ...audit });
    await setDoc(doc(db, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', '0900'), { sessionId: 'source-a', bookingRequestId: 'request-a', ownerId: 'coach-a', counterpartId: 'student-a', schemaVersion: 2, createdAt: when(), createdBy: 'coach-a' });
    await setDoc(doc(db, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', '0900'), { sessionId: 'source-a', bookingRequestId: 'request-a', ownerId: 'student-a', counterpartId: 'coach-a', schemaVersion: 2, createdAt: when(), createdBy: 'coach-a' });
  });
  const cancel = (db, status, actor = 'coach-a') => runTransaction(db, async (tx) => {
    const source = doc(db, 'sessions', 'source-a');
    tx.update(source, { status, updatedAt: serverTimestamp(), updatedBy: actor });
    tx.delete(doc(db, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', '0900'));
    tx.delete(doc(db, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', '0900'));
  });
  await t.test('Coach cancel releases reservations without refunding entitlement', async () => {
    await seedSession();
    await assertSucceeds(cancel(coachContext('coach-a'), 'coach_cancelled'));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      assert.equal((await getDoc(doc(db, 'sessions', 'source-a'))).data().status, 'coach_cancelled');
      assert.equal((await getDoc(doc(db, 'student_entitlements', 'student-a'))).data().remainingSessions, 9);
      assert.equal((await getDoc(doc(db, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', '0900'))).exists(), false);
    });
  });
  await t.test('Student and foreign Coach cannot cancel; Admin can mark system cancellation', async () => {
    await seedSession();
    await assertFails(cancel(studentClaimContext('student-a'), 'coach_cancelled'));
    await assertFails(cancel(coachContext('coach-b'), 'coach_cancelled'));
    await assertSucceeds(cancel(adminContext('admin-a'), 'system_cancelled', 'admin-a'));
  });
  await t.test('only one make-up may atomically link a cancelled source without entitlement mutation', async () => {
    await seedSession('coach_cancelled');
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      await deleteDoc(doc(db, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', '0900'));
      await deleteDoc(doc(db, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', '0900'));
    });
    const coachA = coachContext('coach-a');
    const makeUp = (id, options = {}) => runTransaction(coachA, async (tx) => {
      const source = doc(coachA, 'sessions', 'source-a');
      await tx.get(source);
      const audit = { schemaVersion: 2, createdAt: serverTimestamp(), createdBy: 'coach-a', updatedAt: serverTimestamp(), updatedBy: 'coach-a' };
      tx.set(doc(coachA, 'sessions', id), { bookingRequestId: 'request-a', studentId: 'student-a', coachId: 'coach-a', sportId: 'tennis', dayKey, slotId: '1000', entitlementId: 'student-a', sourceSessionId: 'source-a', status: 'scheduled', ...audit });
      if (!options.skipCoachReservation) tx.set(doc(coachA, 'coach_session_slots', 'coach-a', 'days', dayKey, 'slots', '1000'), { sessionId: id, bookingRequestId: 'request-a', ownerId: 'coach-a', counterpartId: 'student-a', schemaVersion: 2, createdAt: serverTimestamp(), createdBy: 'coach-a' });
      if (!options.skipStudentReservation) tx.set(doc(coachA, 'student_session_slots', 'student-a', 'days', dayKey, 'slots', '1000'), { sessionId: id, bookingRequestId: 'request-a', ownerId: 'student-a', counterpartId: 'coach-a', schemaVersion: 2, createdAt: serverTimestamp(), createdBy: 'coach-a' });
      if (!options.skipSourceUpdate) tx.update(source, { makeUpSessionId: id, updatedAt: serverTimestamp(), updatedBy: 'coach-a' });
      if (options.mutateEntitlement) tx.update(doc(coachA, 'student_entitlements', 'student-a'), options.mutateEntitlement);
    });
    await assertFails(makeUp('missing-coach', { skipCoachReservation: true }));
    await assertFails(makeUp('missing-student', { skipStudentReservation: true }));
    await assertFails(makeUp('missing-source-update', { skipSourceUpdate: true }));
    await assertFails(makeUp('mutates-entitlement', { mutateEntitlement: { remainingSessions: 8, updatedAt: serverTimestamp(), updatedBy: 'coach-a', lastConsumedSessionId: 'mutates-entitlement' } }));
    const race = await Promise.allSettled([makeUp('makeup-a'), makeUp('makeup-b')]);
    assert.equal(race.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal(race.filter((result) => result.status === 'rejected').length, 1);
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      assert.equal((await getDoc(doc(db, 'student_entitlements', 'student-a'))).data().remainingSessions, 9);
      assert.equal((await getDocs(collection(db, 'sessions'))).size, 2);
      const source = (await getDoc(doc(db, 'sessions', 'source-a'))).data();
      const sourceId = source.makeUpSessionId;
      assert.equal(typeof sourceId, 'string');
    });
    await assertFails(updateDoc(doc(coachA, 'sessions', 'source-a'), { makeUpSessionId: deleteField(), updatedAt: serverTimestamp(), updatedBy: 'coach-a' }));
    await assertFails(updateDoc(doc(coachA, 'sessions', 'source-a'), { makeUpSessionId: 'relinked', updatedAt: serverTimestamp(), updatedBy: 'coach-a' }));
  });
});

testAfterFix('unreleased V2 sources remain default-deny for every client claim', async (t) => {
  const paths = [
    'schedule_slot_templates/0900',
    'sessions/session-a',
    'coach_busy_blocks/coach-a_1900000000000',
    'student_busy_blocks/student-a_1900000000000',
    'session_change_requests/change-a',
    'coach_availability/availability-a',
    'notifications/notification-a',
    'payment_records/payment-a',
  ];
  const clients = [studentClaimContext('student-a'), coachContext('coach-a'), adminContext('admin-a')];
  for (const client of clients) {
    await t.test(`claim ${client.app.name} cannot read or write unreleased V2 sources`, async () => {
      for (const item of paths) {
        const reference = doc(client, ...item.split('/'));
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { schemaVersion: 2 }));
      }
    });
  }
});
