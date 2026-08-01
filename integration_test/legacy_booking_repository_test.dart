import 'dart:io';

import 'package:bodyhub_student/features/booking/repositories/booking_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _enabled = bool.fromEnvironment('RUN_FIRESTORE_EMULATOR_TESTS');
const _host = String.fromEnvironment(
  'FIRESTORE_EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);
const _port = int.fromEnvironment(
  'FIRESTORE_EMULATOR_PORT',
  defaultValue: 8080,
);
const _projectId = String.fromEnvironment(
  'FIRESTORE_EMULATOR_PROJECT_ID',
  defaultValue: 'bodyhub-legacy-booking-tests',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('legacy Student booking repository', () {
    late _LegacyHarness harness;
    late BookingRepository repository;
    final scheduledAt = DateTime.now()
        .add(const Duration(days: 2))
        .copyWith(
          hour: 10,
          minute: 0,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );

    setUpAll(() async {
      if (!_enabled) throw StateError('Firestore Emulator tests are disabled.');
      harness = await _LegacyHarness.connect();
    });
    setUp(() async {
      await harness.clear();
      repository = BookingRepository(firestore: harness.firestore);
    });

    test(
      'uses the active profile Coach for booking and both slot owners',
      () async {
        await harness.seed({
          'student_profiles/student-a': {
            'status': 'active',
            'coachId': 'coach-a',
          },
        });

        await repository.createBooking(
          studentId: 'student-a',
          sportName: 'Tennis',
          packageName: 'Legacy',
          scheduledAt: scheduledAt,
          notes: '',
        );

        final booking =
            (await harness.firestore.collection('bookings').get()).docs.single;
        expect(booking.data()['coachId'], 'coach-a');
        final slots = await harness.firestore.collection('booking_slots').get();
        expect(slots.docs, hasLength(10));
        expect(
          slots.docs.where((slot) => slot.data()['resourceType'] == 'coach'),
          hasLength(5),
        );
        expect(
          slots.docs.where((slot) => slot.data()['resourceType'] == 'student'),
          hasLength(5),
        );
        expect(
          slots.docs.every((slot) => slot.data()['bookingId'] == booking.id),
          isTrue,
        );
        expect(
          slots.docs.every((slot) => slot.data()['coachId'] == 'coach-a'),
          isTrue,
        );
      },
    );

    test(
      'rejects missing or inactive profile ownership without writes',
      () async {
        await harness.seed({
          'student_profiles/student-a': {
            'status': 'pending',
            'coachId': 'coach-a',
          },
        });
        await expectLater(
          repository.createBooking(
            studentId: 'student-a',
            sportName: 'Tennis',
            packageName: 'Legacy',
            scheduledAt: scheduledAt,
            notes: '',
          ),
          throwsA(isA<Object>()),
        );
        expect(
          (await harness.firestore.collection('bookings').get()).docs,
          isEmpty,
        );
        expect(
          (await harness.firestore.collection('booking_slots').get()).docs,
          isEmpty,
        );
      },
    );

    test('collision rolls back a second legacy booking', () async {
      await harness.seed({
        'student_profiles/student-a': {
          'status': 'active',
          'coachId': 'coach-a',
        },
      });
      await repository.createBooking(
        studentId: 'student-a',
        sportName: 'Tennis',
        packageName: 'Legacy',
        scheduledAt: scheduledAt,
        notes: '',
      );
      final bookingId =
          (await harness.firestore.collection('bookings').get()).docs.single.id;
      await expectLater(
        repository.createBooking(
          studentId: 'student-a',
          sportName: 'Tennis',
          packageName: 'Legacy',
          scheduledAt: scheduledAt,
          notes: '',
        ),
        throwsA(isA<Object>()),
      );
      expect(
        (await harness.firestore.collection('bookings').get()).docs,
        hasLength(1),
      );
    });

    test('cancellation removes only its deterministic legacy slots', () async {
      await harness.seed({
        'student_profiles/student-a': {
          'status': 'active',
          'coachId': 'coach-a',
        },
      });
      await repository.createBooking(
        studentId: 'student-a',
        sportName: 'Tennis',
        packageName: 'Legacy',
        scheduledAt: scheduledAt,
        notes: '',
      );
      final bookingId =
          (await harness.firestore.collection('bookings').get()).docs.single.id;
      await repository.cancelBooking(bookingId);
      expect(
        (await harness.firestore.collection('bookings').doc(bookingId).get())
            .data()?['status'],
        'cancelled',
      );
      expect(
        (await harness.firestore.collection('booking_slots').get()).docs,
        isEmpty,
      );
    });
  });
}

class _LegacyHarness {
  _LegacyHarness._(this.firestore);

  final FirebaseFirestore firestore;

  static Future<_LegacyHarness> connect() async {
    final app = await Firebase.initializeApp(
      name: 'legacy-booking-tests',
      options: const FirebaseOptions(
        apiKey: 'repository-test-key',
        appId: '1:000000000000:android:legacy-booking-tests',
        messagingSenderId: '000000000000',
        projectId: _projectId,
      ),
    );
    final firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.useFirestoreEmulator(_host, _port);
    return _LegacyHarness._(firestore);
  }

  Future<void> clear() async {
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(
        Uri.http(
          '$_host:$_port',
          '/emulator/v1/projects/$_projectId/databases/(default)/documents',
        ),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Could not clear Firestore Emulator.');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> seed(Map<String, Map<String, Object?>> documents) async {
    final batch = firestore.batch();
    for (final entry in documents.entries) {
      batch.set(firestore.doc(entry.key), entry.value);
    }
    await batch.commit();
  }
}
