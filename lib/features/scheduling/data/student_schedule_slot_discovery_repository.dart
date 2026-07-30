import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads only active V2 availability gates for one selected Coach and day.
///
/// This repository deliberately never queries a root collection, collection
/// group, or an unscoped Coach schedule. It reads the frozen, bounded set of
/// 13 canonical document paths because Rules must deny inactive documents.
/// Availability is only a future booking business gate; it is not a reservation
/// or Session.
class StudentScheduleSlotDiscoveryRepository {
  StudentScheduleSlotDiscoveryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Reads bookable canonical slots for exactly one Coach and one day.
  ///
  /// A direct-document fan-out is intentional: it is capped at 13 canonical
  /// IDs, keeps the query path fully scoped, and lets Rules reject inactive
  /// documents rather than relying on UI filtering for access control.
  Future<List<CoachScheduleSlotAvailabilityRecord>> getActiveSlots({
    required String coachId,
    required String dayKey,
  }) async {
    final normalizedCoachId = _requireCoachId(coachId);
    final normalizedDayKey = BodyHubSchedulingContract.requireDayKey(dayKey);
    final slots = await Future.wait(
      BodyHubSchedulingContract.slotIds.map((slotId) async {
        try {
          final document = await _slotCollection(
            normalizedCoachId,
            normalizedDayKey,
          ).doc(slotId).get();
          if (!document.exists) return null;
          final record = CoachScheduleSlotAvailabilityRecord.fromMap(
            coachId: normalizedCoachId,
            dayKey: normalizedDayKey,
            slotId: document.id,
            data: document.data()!,
          );
          return record.active ? record : null;
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') return null;
          rethrow;
        }
      }),
    );
    return slots.whereType<CoachScheduleSlotAvailabilityRecord>().toList(
      growable: false,
    );
  }

  CollectionReference<Map<String, dynamic>> _slotCollection(
    String coachId,
    String dayKey,
  ) => _firestore
      .collection(BodyHubPaths.coachScheduleSlots)
      .doc(coachId)
      .collection('days')
      .doc(dayKey)
      .collection('slots');

  static String _requireCoachId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'coachId', 'must not be empty');
    }
    return normalized;
  }
}
