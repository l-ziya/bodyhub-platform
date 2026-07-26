import 'package:cloud_firestore/cloud_firestore.dart';

class BookingModel {
  const BookingModel({
    required this.id,
    required this.studentId,
    required this.sportName,
    required this.packageName,
    required this.scheduledAt,
    required this.status,
    required this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String studentId;
  final String sportName;
  final String packageName;
  final DateTime scheduledAt;
  final String status;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory BookingModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final scheduledAt = data['scheduledAt'];

    return BookingModel(
      id: document.id,
      studentId: data['studentId'] as String? ?? '',
      sportName: data['sportName'] as String? ?? '',
      packageName: data['packageName'] as String? ?? '',
      scheduledAt: scheduledAt is Timestamp
          ? scheduledAt.toDate()
          : DateTime.now(),
      status: data['status'] as String? ?? 'pending',
      notes: data['notes'] as String? ?? '',
      createdAt: _asDateTime(data['createdAt']),
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }

  static DateTime? _asDateTime(Object? value) {
    return value is Timestamp ? value.toDate() : null;
  }

  bool get canBeCancelled => status == 'pending';
}
