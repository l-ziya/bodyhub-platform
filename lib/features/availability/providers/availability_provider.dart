import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/availability_repository.dart';

final availabilityRepositoryProvider =
    Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository();
});