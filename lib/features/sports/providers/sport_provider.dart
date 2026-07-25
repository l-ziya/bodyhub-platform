import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sport_repository.dart';
import '../models/sport_model.dart';

final sportRepositoryProvider = Provider<SportRepository>((ref) {
  return SportRepository();
});

final sportsProvider = FutureProvider<List<SportModel>>((ref) async {
  return ref.read(sportRepositoryProvider).getSports();
});