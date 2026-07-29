import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bodyhub_student/features/availability/models/availability_model.dart';
import 'package:bodyhub_student/features/availability/repositories/availability_repository.dart';
import 'package:bodyhub_student/features/booking/repositories/lesson_change_request_repository.dart';
import 'package:bodyhub_student/features/students/data/student_profile_repository.dart';

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
  defaultValue: 'bodyhub-student-repository-tests',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Student coach ownership propagation transactions', () {
    late _FirestoreEmulatorHarness harness;

    setUpAll(() async {
      if (!_enabled) {
        throw StateError('Firestore Emulator tests are not enabled.');
      }
      harness = await _FirestoreEmulatorHarness.connect();
    });
    setUp(() async => harness.clear());

    testWidgets('creates lesson requests only from the active profile coach', (
      tester,
    ) async {
      await harness.seed({
        'student_profiles/student-a': {
          'status': 'active',
          'coachId': 'coach-a',
        },
        'lessons/lesson-a': {'studentId': 'student-a', 'coachId': 'coach-a'},
      });

      await LessonChangeRequestRepository(
        firestore: harness.firestore,
      ).createRequest(
        studentId: 'student-a',
        lessonId: 'lesson-a',
        type: 'reschedule',
        reason: 'Later please',
      );

      final request = await harness.firestore
          .collection('lesson_change_requests')
          .get();
      expect(request.docs, hasLength(1));
      expect(request.docs.single.data()['coachId'], 'coach-a');
    });

    testWidgets(
      'rolls back a lesson request when profile and lesson disagree',
      (tester) async {
        await harness.seed({
          'student_profiles/student-a': {
            'status': 'active',
            'coachId': 'coach-a',
          },
          'lessons/lesson-a': {'studentId': 'student-a', 'coachId': 'coach-b'},
        });

        await expectLater(
          LessonChangeRequestRepository(
            firestore: harness.firestore,
          ).createRequest(
            studentId: 'student-a',
            lessonId: 'lesson-a',
            type: 'reschedule',
            reason: 'Later please',
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          (await harness.firestore.collection('lesson_change_requests').get())
              .docs,
          isEmpty,
        );
      },
    );

    testWidgets(
      'writes profile-derived ownership to package requests and availability',
      (tester) async {
        await harness.seed({
          'student_profiles/student-a': {
            'status': 'active',
            'coachId': 'coach-a',
          },
        });
        final profileRepository = StudentProfileRepository(
          firestore: harness.firestore,
        );

        await profileRepository.updateSportAndPackage(
          uid: 'student-a',
          sportId: 'fitness',
          packageId: 'package-a',
          packageName: 'Monthly',
        );
        await AvailabilityRepository(
          firestore: harness.firestore,
        ).replaceStudentAvailabilities(
          studentId: 'student-a',
          availabilities: [
            AvailabilityModel(
              id: 'student-a_1',
              studentId: 'student-a',
              dayOfWeek: DateTime.monday,
              dayName: 'Monday',
              startTime: '10:00',
              endTime: '11:00',
              active: true,
              createdAt: DateTime.now(),
            ),
          ],
        );

        expect(
          (await harness.firestore
                  .collection('package_requests')
                  .doc('student-a')
                  .get())
              .data()?['coachId'],
          'coach-a',
        );
        expect(
          (await harness.firestore
                  .collection('availabilities')
                  .doc('student-a_1')
                  .get())
              .data()?['coachId'],
          'coach-a',
        );
      },
    );
  });
}

class _FirestoreEmulatorHarness {
  _FirestoreEmulatorHarness._(this.firestore);

  final FirebaseFirestore firestore;

  static Future<_FirestoreEmulatorHarness> connect() async {
    final app = await Firebase.initializeApp(
      name: 'student-coach-ownership-tests',
      options: const FirebaseOptions(
        apiKey: 'repository-test-key',
        appId: '1:000000000000:android:student-ownership-tests',
        messagingSenderId: '000000000000',
        projectId: _projectId,
      ),
    );
    final firestore = FirebaseFirestore.instanceFor(app: app);
    firestore.useFirestoreEmulator(_host, _port);
    return _FirestoreEmulatorHarness._(firestore);
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
        final body = await utf8.decoder.bind(response).join();
        throw StateError('Could not clear Firestore Emulator: $body');
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
