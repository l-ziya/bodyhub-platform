import 'package:firebase_auth/firebase_auth.dart';
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