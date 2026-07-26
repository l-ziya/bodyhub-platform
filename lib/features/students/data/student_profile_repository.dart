import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student_profile_model.dart';

class StudentProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveStudentProfile(
    StudentProfileModel profile,
  ) async {
    await _firestore
        .collection('student_profiles')
        .doc(profile.uid)
        .set(
          profile.toFirestore(),
          SetOptions(merge: true),
        );
  }

  Future<StudentProfileModel?> getStudentProfile(
    String uid,
  ) async {
    final doc = await _firestore
        .collection('student_profiles')
        .doc(uid)
        .get();

    if (!doc.exists) {
      return null;
    }

    return StudentProfileModel.fromFirestore(
      doc.id,
      doc.data()!,
    );
  }

  Future<void> updateSportAndPackage({
    required String uid,
    required String sportId,
    required String packageId,
  }) async {
    await _firestore
        .collection('student_profiles')
        .doc(uid)
        .set(
      {
        'sportId': sportId,
        'packageId': packageId,
        'status': 'active',
      },
      SetOptions(merge: true),
    );
  }

  /// Profil bilgilerini günceller
  Future<void> updateProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
  }) async {
    await _firestore
        .collection('student_profiles')
        .doc(uid)
        .set(
      {
        'fullName': fullName,
        'phone': phone,
        'email': email,
      },
      SetOptions(merge: true),
    );
  }
}