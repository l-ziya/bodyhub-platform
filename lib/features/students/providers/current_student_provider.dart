import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/student_profile_repository.dart';
import '../models/student_profile_model.dart';
import 'student_profile_provider.dart';

final currentStudentProvider =
    FutureProvider<StudentProfileModel?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return null;
  }

  return ref
      .read(studentProfileRepositoryProvider)
      .getStudentProfile(user.uid);
});