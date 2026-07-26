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
  }) {
    return _firestore.collection('lesson_change_requests').add({
      'studentId': studentId,
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
  }

  Future<void> updateRequest({
    required String requestId,
    required String type,
    required String reason,
    DateTime? requestedTime,
  }) {
    return _firestore.collection('lesson_change_requests').doc(requestId).update({
      'type': type,
      'reason': reason.trim(),
      'requestedTime': requestedTime == null ? null : Timestamp.fromDate(requestedTime),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelRequest(String requestId) =>
      _firestore.collection('lesson_change_requests').doc(requestId).delete();
}
