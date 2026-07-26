import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/availability_model.dart';
import '../repositories/availability_repository.dart';

final availabilityRepositoryProvider = Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository();
});

final studentAvailabilitiesProvider =
    StreamProvider.family<List<AvailabilityModel>, String>((ref, studentId) {
      return ref
          .watch(availabilityRepositoryProvider)
          .watchStudentAvailabilities(studentId);
    });
