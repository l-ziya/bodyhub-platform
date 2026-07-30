import 'dart:io';

import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bodyhub_student/features/scheduling/data/student_booking_request_repository.dart';
import 'package:bodyhub_student/features/scheduling/data/student_schedule_slot_discovery_repository.dart';

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
  defaultValue: 'bodyhub-student-v2-request-tests',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('V2 Student scheduling repositories', () {
    late _Harness harness;

    setUpAll(() async {
      if (!_enabled) throw StateError('Firestore Emulator tests are disabled.');
      harness = await _Harness.connect();
    });
    setUp(() => harness.clear());

    testWidgets('returns only active canonical availability coordinates', (
      tester,
    ) async {
      await harness.seed({
        BodyHubPaths.coachScheduleSlot('coach-a', '2026-08-03', '0900'): {
          'active': true,
          'schemaVersion': 2,
        },
        BodyHubPaths.coachScheduleSlot('coach-a', '2026-08-03', '1000'): {
          'active': false,
          'schemaVersion': 2,
        },
      });
      final slots = await StudentScheduleSlotDiscoveryRepository(
        firestore: harness.firestore,
      ).getActiveSlots(coachId: 'coach-a', dayKey: '2026-08-03');

      expect(slots.map((item) => item.slotId), ['0900']);
      expect(slots.single.active, isTrue);
    });

    testWidgets(
      'creates and withdraws an intent without scheduling side effects',
      (tester) async {
        final repository = StudentBookingRequestRepository(
          firestore: harness.firestore,
        );
        final request = await repository.createPendingRequest(
          studentId: 'student-a',
          coachId: 'coach-a',
          sportId: 'tennis',
          dayKey: '2026-08-03',
          slotId: '0900',
        );

        final stored = await harness.firestore
            .collection(BodyHubPaths.bookingRequests)
            .doc(request.id)
            .get();
        expect(
          stored.data()!.keys,
          containsAll(<String>[
            'studentId',
            'coachId',
            'sportId',
            'dayKey',
            'slotId',
            'status',
            'schemaVersion',
            'createdAt',
            'createdBy',
            'updatedAt',
            'updatedBy',
          ]),
        );
        expect(stored.data()!.containsKey('durationMinutes'), isFalse);
        expect(stored.data()!.containsKey('startAt'), isFalse);
        expect(
          (await harness.firestore.collection(BodyHubPaths.sessions).get())
              .docs,
          isEmpty,
        );
        expect(
          (await harness.firestore
                  .collection(BodyHubPaths.studentEntitlements)
                  .get())
              .docs,
          isEmpty,
        );

        await repository.withdrawPendingRequest(
          requestId: request.id,
          studentId: 'student-a',
        );
        expect(
          (await stored.reference.get()).data()?[BodyHubFields.status],
          BookingRequestStatus.withdrawn.wireName,
        );
      },
    );
  });
}

class _Harness {
  _Harness._(this.firestore);

  final FirebaseFirestore firestore;

  static Future<_Harness> connect() async {
    final app = await Firebase.initializeApp(
      name: 'student-v2-request-tests',
      options: const FirebaseOptions(
        apiKey: 'repository-test-key',
        appId: '1:000000000000:android:student-v2-request-tests',
        messagingSenderId: '000000000000',
        projectId: _projectId,
      ),
    );
    final firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.useFirestoreEmulator(_host, _port);
    return _Harness._(firestore);
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
