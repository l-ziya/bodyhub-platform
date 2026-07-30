import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/coach_profile_model.dart';

/// Reads only public, booking-enabled Coach profiles for future V2 discovery.
class CoachDiscoveryRepository {
  CoachDiscoveryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<CoachProfileModel>> getDiscoverableCoaches(String sportId) async {
    final normalizedSportId = sportId.trim();
    if (normalizedSportId.isEmpty) return const <CoachProfileModel>[];

    final snapshot = await _firestore
        .collection(BodyHubPaths.coachProfiles)
        .where(BodyHubFields.specialtyIds, arrayContains: normalizedSportId)
        .where(BodyHubFields.active, isEqualTo: true)
        .where(BodyHubFields.bookingEnabled, isEqualTo: true)
        .get();

    final coaches = snapshot.docs
        .map(
          (document) =>
              CoachProfileModel.fromFirestore(document.id, document.data()),
        )
        .toList(growable: false);
    coaches.sort(
      (left, right) => left.displayName.compareTo(right.displayName),
    );
    return coaches;
  }
}
