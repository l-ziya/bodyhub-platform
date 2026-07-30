import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Owns Student-side V2 booking-request intent operations.
///
/// This repository never creates a Session, reservation lock, entitlement
/// mutation, or approval state. A request is limited to pending, withdrawn,
/// and rejected during D-6.
class StudentBookingRequestRepository {
  StudentBookingRequestRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Creates one pending audit request without reserving any scheduling slot.
  Future<BookingRequestRecord> createPendingRequest({
    required String studentId,
    required String coachId,
    required String sportId,
    required String dayKey,
    required String slotId,
  }) async {
    final normalizedStudentId = _requireId(studentId, 'studentId');
    final reference = _requests.doc();
    final request = BookingRequestRecord(
      id: reference.id,
      studentId: normalizedStudentId,
      coachId: _requireId(coachId, 'coachId'),
      sportId: _requireId(sportId, 'sportId'),
      dayKey: dayKey,
      slotId: slotId,
      status: BookingRequestStatus.pending,
      schemaVersion: BodyHubSchema.version,
      createdBy: normalizedStudentId,
      updatedBy: normalizedStudentId,
    );
    await reference.set(<String, Object?>{
      ...request.toMap(),
      BodyHubFields.createdAt: FieldValue.serverTimestamp(),
      BodyHubFields.updatedAt: FieldValue.serverTimestamp(),
    });
    return request;
  }

  /// Watches only one Student's own V2 booking-request records.
  Stream<List<BookingRequestRecord>> watchOwnRequests(String studentId) {
    final normalizedStudentId = _requireId(studentId, 'studentId');
    return _requests
        .where(BodyHubFields.studentId, isEqualTo: normalizedStudentId)
        .snapshots()
        .map(
          (snapshot) =>
              _sorted(snapshot.docs.map(_mapDocument).toList(growable: false)),
        );
  }

  /// Withdraws only a pending request that belongs to [studentId].
  Future<void> withdrawPendingRequest({
    required String requestId,
    required String studentId,
  }) => _requests
      .doc(_requireId(requestId, 'requestId'))
      .update(<String, Object?>{
        BodyHubFields.status: BookingRequestStatus.withdrawn.wireName,
        BodyHubFields.updatedAt: FieldValue.serverTimestamp(),
        BodyHubFields.updatedBy: _requireId(studentId, 'studentId'),
      });

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(BodyHubPaths.bookingRequests);

  static List<BookingRequestRecord> _sorted(List<BookingRequestRecord> input) {
    input.sort(
      (left, right) =>
          (right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
    );
    return input;
  }

  static BookingRequestRecord _mapDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => BookingRequestRecord.fromMap(
    id: document.id,
    data: document.data()!,
    createdAt: (document.data()?[BodyHubFields.createdAt] as Timestamp?)
        ?.toDate(),
    updatedAt: (document.data()?[BodyHubFields.updatedAt] as Timestamp?)
        ?.toDate(),
  );

  static String _requireId(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}
