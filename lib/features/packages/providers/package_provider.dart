import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/package_repository.dart';
import '../models/package_model.dart';

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  return PackageRepository();
});

final packagesProvider =
    FutureProvider.family<List<PackageModel>, String>((ref, sportId) async {
  return ref
      .read(packageRepositoryProvider)
      .getPackagesBySport(sportId);
});