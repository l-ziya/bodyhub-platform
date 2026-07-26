import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/student_dashboard_model.dart';
import '../repositories/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository();
});

final studentDashboardProvider =
    FutureProvider<StudentDashboardModel>((ref) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    throw Exception('Kullanıcı oturumu bulunamadı.');
  }

  final repository = ref.read(dashboardRepositoryProvider);

  return repository.getStudentDashboard(user.uid);
});

/// Coach paket hakkını güncellediğinde öğrenci ana ekranının yenilenmesini sağlar.
final studentPackageStreamProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('student_packages')
      .doc(user.uid)
      .snapshots()
      .map((document) => document.data());
});
