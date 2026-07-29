import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student_profile_model.dart';

class StudentProfileRepository {
  StudentProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> saveStudentProfile(StudentProfileModel profile) async {
    await _firestore
        .collection('student_profiles')
        .doc(profile.uid)
        .set(profile.toFirestore(), SetOptions(merge: true));
  }

  Future<StudentProfileModel?> getStudentProfile(String uid) async {
    final doc = await _firestore.collection('student_profiles').doc(uid).get();

    if (!doc.exists) {
      return null;
    }

    return StudentProfileModel.fromFirestore(doc.id, doc.data()!);
  }

  Future<void> updateSportAndPackage({
    required String uid,
    required String sportId,
    required String packageId,
    required String packageName,
  }) async {
    final profileReference = _firestore.collection('student_profiles').doc(uid);
    final requestReference = _firestore.collection('package_requests').doc(uid);

    await _firestore.runTransaction((transaction) async {
      final profile = await transaction.get(profileReference);
      final request = await transaction.get(requestReference);
      if (!profile.exists) {
        throw StateError('Öğrenci profili bulunamadı.');
      }
      final profileData = profile.data() ?? const <String, dynamic>{};
      final coachId = profileData['coachId'] as String? ?? '';
      if (profileData['status'] != 'active' || coachId.trim().isEmpty) {
        throw StateError('Paket talebi için aktif bir koç ataması gerekli.');
      }
      if (request.exists) {
        final requestData = request.data() ?? const <String, dynamic>{};
        final requestStudentId = requestData['studentId'] as String? ?? '';
        final requestCoachId = requestData['coachId'] as String? ?? '';
        if ((requestStudentId.isNotEmpty && requestStudentId != uid) ||
            (requestCoachId.isNotEmpty && requestCoachId != coachId)) {
          throw StateError('Paket talebi koç atamasıyla eşleşmiyor.');
        }
      }

      transaction.set(requestReference, {
        'studentId': uid,
        'coachId': coachId,
        'sportId': sportId,
        'packageId': packageId,
        'packageName': packageName,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Stream<StudentProfileModel?> watchStudentProfile(String uid) {
    return _firestore.collection('student_profiles').doc(uid).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      return StudentProfileModel.fromFirestore(doc.id, doc.data()!);
    });
  }

  /// Profil bilgilerini günceller
  Future<void> updateProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
    required String gender,
  }) async {
    await _firestore.collection('student_profiles').doc(uid).set({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'gender': gender,
    }, SetOptions(merge: true));
  }
}
