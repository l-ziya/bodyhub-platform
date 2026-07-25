import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/package_model.dart';

class PackageRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<PackageModel>> getPackagesBySport(String sportId) async {
    final snapshot = await _firestore
        .collection('packages')
        .where('sportId', isEqualTo: sportId)
        .where('active', isEqualTo: true)
        .get();

    return snapshot.docs
        .map(
          (doc) => PackageModel.fromFirestore(
            doc.id,
            doc.data(),
          ),
        )
        .toList();
  }
}