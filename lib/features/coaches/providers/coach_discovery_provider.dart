import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coach_discovery_repository.dart';
import '../models/coach_profile_model.dart';

/// Provides isolated V2 Coach discovery without changing the V1 booking flow.
final coachDiscoveryRepositoryProvider = Provider<CoachDiscoveryRepository>(
  (ref) => CoachDiscoveryRepository(),
);

/// Lists public active Coaches that can teach the selected stable Sport ID.
final discoverableCoachesProvider =
    FutureProvider.family<List<CoachProfileModel>, String>((ref, sportId) {
      return ref
          .watch(coachDiscoveryRepositoryProvider)
          .getDiscoverableCoaches(sportId);
    });
