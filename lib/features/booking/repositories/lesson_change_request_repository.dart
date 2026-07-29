import 'package:cloud_firestore/cloud_firestore.dart';

class LessonChangeRequestRepository {
  LessonChangeRequestRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> createRequest({
    required String studentId,
    required String lessonId,
    required String type,
    required String reason,
    DateTime? requestedTime,
  }) async {
    final requestReference = _firestore
        .collection('lesson_change_requests')
        .doc();
    final profileReference = _firestore
        .collection('student_profiles')
        .doc(studentId);
    final lessonReference = _firestore.collection('lessons').doc(lessonId);

    await _firestore.runTransaction((transaction) async {
      final profile = await transaction.get(profileReference);
      final lesson = await transaction.get(lessonReference);
      if (!profile.exists) {
        throw StateError('Öğrenci profili bulunamadı.');
      }
      final profileData = profile.data() ?? const <String, dynamic>{};
      final coachId = profileData['coachId'] as String? ?? '';
      if (profileData['status'] != 'active' || coachId.trim().isEmpty) {
        throw StateError('Aktif bir koç ataması gerekli.');
      }
      if (!lesson.exists) {
        throw StateError('Ders bulunamadı.');
      }
      final lessonData = lesson.data() ?? const <String, dynamic>{};
      if (lessonData['studentId'] != studentId ||
          lessonData['coachId'] != coachId) {
        throw StateError('Ders koç atamasıyla eşleşmiyor.');
      }

      transaction.set(requestReference, {
        'studentId': studentId,
        'coachId': coachId,
        'lessonId': lessonId,
        'type': type,
        'reason': reason.trim(),
        'requestedTime': requestedTime == null
            ? null
            : Timestamp.fromDate(requestedTime),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateRequest({
    required String requestId,
    required String type,
    required String reason,
    DateTime? requestedTime,
  }) {
    return _firestore
        .collection('lesson_change_requests')
        .doc(requestId)
        .update({
          'type': type,
          'reason': reason.trim(),
          'requestedTime': requestedTime == null
              ? null
              : Timestamp.fromDate(requestedTime),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> cancelRequest(String requestId) =>
      _firestore.collection('lesson_change_requests').doc(requestId).delete();
}
