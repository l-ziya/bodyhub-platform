import 'package:cloud_firestore/cloud_firestore.dart';

import '../../availability/models/availability_model.dart';
import '../models/booking_model.dart';

class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bookings {
    return _firestore.collection('bookings');
  }

  Stream<List<BookingModel>> watchStudentBookings(String studentId) {
    if (studentId.trim().isEmpty) {
      throw ArgumentError.value(studentId, 'studentId', 'Boş olamaz.');
    }

    return _bookings.where('studentId', isEqualTo: studentId).snapshots().map((
      snapshot,
    ) {
      final bookings = snapshot.docs
          .map(BookingModel.fromFirestore)
          .toList(growable: false);

      bookings.sort(
        (first, second) => first.scheduledAt.compareTo(second.scheduledAt),
      );

      return bookings;
    });
  }

  Future<void> createBooking({
    required String studentId,
    required String sportName,
    required String packageName,
    required DateTime scheduledAt,
    required String notes,
  }) async {
    if (studentId.trim().isEmpty) {
      throw ArgumentError.value(studentId, 'studentId', 'Boş olamaz.');
    }

    if (!scheduledAt.isAfter(DateTime.now())) {
      throw ArgumentError.value(
        scheduledAt,
        'scheduledAt',
        'Geçmiş bir tarih seçilemez.',
      );
    }

    final existingBookings = await _bookings
        .where('studentId', isEqualTo: studentId)
        .get();
    final hasConflict = existingBookings.docs
        .map(BookingModel.fromFirestore)
        .any(
          (booking) =>
              booking.scheduledAt == scheduledAt &&
              (booking.status == 'pending' || booking.status == 'confirmed'),
        );

    if (hasConflict) {
      throw StateError('Bu tarih ve saat için zaten aktif bir talep var.');
    }

    await _bookings.add({
      'studentId': studentId,
      'sportName': sportName,
      'packageName': packageName,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'status': 'pending',
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> createWeeklyReservations({
    required String studentId,
    required String sportName,
    required String packageName,
    required List<AvailabilityModel> weeklySlots,
    required bool isMonthlyPackage,
  }) async {
    if (studentId.trim().isEmpty || weeklySlots.isEmpty) {
      throw ArgumentError('Öğrenci ve en az bir haftalık rezervasyon gerekli.');
    }

    final existingSnapshot = await _bookings
        .where('studentId', isEqualTo: studentId)
        .get();
    final existingBookings = existingSnapshot.docs
        .map(BookingModel.fromFirestore)
        .where(
          (booking) =>
              booking.status == 'pending' ||
              booking.status == 'confirmed' ||
              booking.status == 'accepted',
        )
        .toList();

    final batch = _firestore.batch();
    var createdCount = 0;
    final now = DateTime.now();
    final recurringGroupId =
        '${studentId}_${now.year}${now.month.toString().padLeft(2, '0')}';
    for (final slot in weeklySlots) {
      final occurrences = isMonthlyPackage
          ? _monthlyOccurrences(slot, now)
          : List.generate(4, (week) => _nextOccurrence(slot, now, week));
      for (final scheduledAt in occurrences) {
        final hasConflict = existingBookings.any(
          (booking) => booking.scheduledAt == scheduledAt,
        );
        if (hasConflict) continue;

        final reference = _bookings.doc();
        batch.set(reference, {
          'studentId': studentId,
          'sportName': sportName,
          'packageName': packageName,
          'scheduledAt': Timestamp.fromDate(scheduledAt),
          'status': 'pending',
          'notes': 'Haftalık rezervasyon talebi',
          'recurringType': 'weekly',
          'recurringGroupId': recurringGroupId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        createdCount++;
      }
    }

    if (createdCount > 0) await batch.commit();
    return createdCount;
  }

  DateTime _nextOccurrence(
    AvailabilityModel slot,
    DateTime now,
    int weekOffset,
  ) {
    final timeParts = slot.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final daysUntil = (slot.dayOfWeek - now.weekday + 7) % 7;
    var date = DateTime(now.year, now.month, now.day + daysUntil, hour, minute);
    if (!date.isAfter(now)) date = date.add(const Duration(days: 7));
    return date.add(Duration(days: weekOffset * 7));
  }

  List<DateTime> _monthlyOccurrences(AvailabilityModel slot, DateTime now) {
    final periodStart = now.day == 1
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, now.month + 1, 1);
    final periodEnd = DateTime(periodStart.year, periodStart.month + 1, 0);
    final timeParts = slot.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final firstOffset = (slot.dayOfWeek - periodStart.weekday + 7) % 7;
    var date = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day + firstOffset,
      hour,
      minute,
    );
    final dates = <DateTime>[];
    while (!date.isAfter(periodEnd)) {
      if (date.isAfter(now)) dates.add(date);
      date = date.add(const Duration(days: 7));
    }
    return dates;
  }

  Future<void> cancelBooking(String bookingId) async {
    if (bookingId.trim().isEmpty) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Boş olamaz.');
    }

    await _bookings.doc(bookingId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
