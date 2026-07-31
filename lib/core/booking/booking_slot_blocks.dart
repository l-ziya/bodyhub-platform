import 'package:cloud_firestore/cloud_firestore.dart';

/// Smallest deterministic resource lock used by reservation integrity.
const bookingSlotBlockDuration = Duration(minutes: 10);

List<DateTime> calculateBookingSlotBlocks({
  required DateTime startTime,
  required DateTime endTime,
}) {
  if (!endTime.isAfter(startTime)) {
    throw ArgumentError.value(endTime, 'endTime', 'Must be after startTime.');
  }
  final minute =
      startTime.minute -
      (startTime.minute % bookingSlotBlockDuration.inMinutes);
  final firstBlock = DateTime(
    startTime.year,
    startTime.month,
    startTime.day,
    startTime.hour,
    minute,
  );
  final blocks = <DateTime>[];
  for (
    var block = firstBlock;
    block.isBefore(endTime);
    block = block.add(bookingSlotBlockDuration)
  ) {
    blocks.add(block);
  }
  return blocks;
}

String coachSlotDocumentId(String coachId, DateTime blockStart) =>
    'coach_${coachId}_${blockStart.millisecondsSinceEpoch}';

String studentSlotDocumentId(String studentId, DateTime blockStart) =>
    'student_${studentId}_${blockStart.millisecondsSinceEpoch}';

Map<String, dynamic> bookingSlotData({
  required String resourceType,
  required String resourceId,
  required String bookingId,
  required String lessonId,
  required String coachId,
  required String studentId,
  required DateTime blockStart,
  required DateTime scheduledAt,
  required DateTime endTime,
  required String status,
}) => {
  'bookingId': bookingId,
  'lessonId': lessonId,
  'coachId': coachId,
  'studentId': studentId,
  'resourceType': resourceType,
  'resourceId': resourceId,
  'blockStart': Timestamp.fromDate(blockStart),
  'scheduledAt': Timestamp.fromDate(scheduledAt),
  'endTime': Timestamp.fromDate(endTime),
  'status': status,
  'createdAt': FieldValue.serverTimestamp(),
  'updatedAt': FieldValue.serverTimestamp(),
};
