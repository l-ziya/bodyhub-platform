import 'package:cloud_firestore/cloud_firestore.dart';

class AvailabilityModel {
  final String id;
  final String studentId;
  final int dayOfWeek;
  final String dayName;
  final String startTime;
  final String endTime;
  final bool active;
  final DateTime createdAt;

  const AvailabilityModel({
    required this.id,
    required this.studentId,
    required this.dayOfWeek,
    required this.dayName,
    required this.startTime,
    required this.endTime,
    required this.active,
    required this.createdAt,
  });

  factory AvailabilityModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};

    return AvailabilityModel(
      id: document.id,
      studentId: data['studentId'] ?? '',
      dayOfWeek: data['dayOfWeek'] ?? 1,
      dayName: data['dayName'] ?? '',
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      active: data['active'] ?? true,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'dayOfWeek': dayOfWeek,
      'dayName': dayName,
      'startTime': startTime,
      'endTime': endTime,
      'active': active,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  AvailabilityModel copyWith({
    String? id,
    String? studentId,
    int? dayOfWeek,
    String? dayName,
    String? startTime,
    String? endTime,
    bool? active,
    DateTime? createdAt,
  }) {
    return AvailabilityModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      dayName: dayName ?? this.dayName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}