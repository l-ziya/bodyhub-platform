import 'package:cloud_firestore/cloud_firestore.dart';

class LessonModel {
  final String id;

  final String studentId;

  final String coachId;
  final String coachName;

  final String sportId;
  final String sportName;
  final String sportIcon;

  final String packageId;
  final String packageName;

  final int lessonNumber;

  final DateTime startTime;
  final DateTime endTime;

  final String location;

  final String status;
  final String attendanceStatus;

  final String color;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LessonModel({
    required this.id,
    required this.studentId,
    required this.coachId,
    required this.coachName,
    required this.sportId,
    required this.sportName,
    required this.sportIcon,
    required this.packageId,
    required this.packageName,
    required this.lessonNumber,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.status,
    required this.attendanceStatus,
    required this.color,
    this.createdAt,
    this.updatedAt,
  });

  factory LessonModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;

    return LessonModel(
      id: document.id,
      studentId: data['studentId'] ?? '',
      coachId: data['coachId'] ?? '',
      coachName: data['coachName'] ?? '',
      sportId: data['sportId'] ?? '',
      sportName: data['sportName'] ?? '',
      sportIcon: data['sportIcon'] ?? '',
      packageId: data['packageId'] ?? '',
      packageName: data['packageName'] ?? '',
      lessonNumber: data['lessonNumber'] ?? 0,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      location: data['location'] ?? '',
      status: data['status'] ?? 'scheduled',
      attendanceStatus: data['attendanceStatus'] ?? 'pending',
      color: data['color'] ?? 'primary',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'coachId': coachId,
      'coachName': coachName,
      'sportId': sportId,
      'sportName': sportName,
      'sportIcon': sportIcon,
      'packageId': packageId,
      'packageName': packageName,
      'lessonNumber': lessonNumber,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'location': location,
      'status': status,
      'attendanceStatus': attendanceStatus,
      'color': color,
      'createdAt': createdAt == null
          ? null
          : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null
          ? null
          : Timestamp.fromDate(updatedAt!),
    };
  }

  LessonModel copyWith({
    String? id,
    String? studentId,
    String? coachId,
    String? coachName,
    String? sportId,
    String? sportName,
    String? sportIcon,
    String? packageId,
    String? packageName,
    int? lessonNumber,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    String? status,
    String? attendanceStatus,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LessonModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      coachId: coachId ?? this.coachId,
      coachName: coachName ?? this.coachName,
      sportId: sportId ?? this.sportId,
      sportName: sportName ?? this.sportName,
      sportIcon: sportIcon ?? this.sportIcon,
      packageId: packageId ?? this.packageId,
      packageName: packageName ?? this.packageName,
      lessonNumber: lessonNumber ?? this.lessonNumber,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      status: status ?? this.status,
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}