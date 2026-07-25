import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/student_profile_repository.dart';

final studentProfileRepositoryProvider =
    Provider<StudentProfileRepository>((ref) {
  return StudentProfileRepository();
});