import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sport_model.dart';

class SportRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<SportModel>> getSports() async {
    final snapshot = await _firestore
        .collection('sports')
        .where('active', isEqualTo: true)
        .get();

    return snapshot.docs
        .map(
          (doc) => SportModel.fromFirestore(
            doc.id,
            doc.data(),
          ),
        )
        .toList();
  }
}