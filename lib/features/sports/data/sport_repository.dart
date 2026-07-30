import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';

import '../models/sport_model.dart';

class SportRepository {
  SportRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<SportModel>> getSports() async {
    final snapshot = await _firestore
        .collection(BodyHubPaths.sports)
        .where(BodyHubFields.active, isEqualTo: true)
        .orderBy(BodyHubFields.sortOrder)
        .get();

    return snapshot.docs
        .map((doc) => SportModel.fromFirestore(doc.id, doc.data()))
        .toList();
  }
}
