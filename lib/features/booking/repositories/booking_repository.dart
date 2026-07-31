import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/booking/booking_slot_blocks.dart';
import '../../../core/config/lesson_duration.dart';
import '../../availability/models/availability_model.dart';
import '../models/booking_model.dart';

class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection('bookings');

  CollectionReference<Map<String, dynamic>> get _bookingSlots =>
      _firestore.collection('booking_slots');

  Stream<List<BookingModel>> watchStudentBookings(String studentId) {
    if (studentId.trim().isEmpty) {
      throw ArgumentError.value(studentId, 'studentId', 'Cannot be empty.');
    }

    return _bookings.where('studentId', isEqualTo: studentId).snapshots().map((
      snapshot,
    ) {
      final bookings =
          snapshot.docs.map(BookingModel.fromFirestore).toList(growable: false)
            ..sort(
              (first, second) =>
                  first.scheduledAt.compareTo(second.scheduledAt),
            );
      return bookings;
    });
  }

  /// Returns weekly times that are already held by another student.
  Future<Set<String>> getBlockedWeeklyTimeSlots({
    required String studentId,
    DateTime? from,
    DateTime? until,
  }) async {
    final start = from ?? DateTime.now();
    final end = until ?? start.add(const Duration(days: 62));
    final snapshot = await _bookingSlots
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    return snapshot.docs
        .where((document) => document.data()['studentId'] != studentId)
        .map((document) {
          final scheduledAt = (document.data()['scheduledAt'] as Timestamp?)
              ?.toDate();
          if (scheduledAt == null) return null;
          return weeklyTimeKey(
            dayOfWeek: scheduledAt.weekday,
            startTime:
                '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}',
          );
        })
        .whereType<String>()
        .toSet();
  }

  Future<void> createBooking({
    required String studentId,
    required String sportName,
    required String packageName,
    required DateTime scheduledAt,
    required String notes,
  }) async {
    if (studentId.trim().isEmpty || !scheduledAt.isAfter(DateTime.now())) {
      throw ArgumentError('A valid student and future date are required.');
    }

    final bookingReference = _bookings.doc();
    final profileReference = _firestore
        .collection('student_profiles')
        .doc(studentId);
    await _firestore.runTransaction((transaction) async {
      final profile = await transaction.get(profileReference);
      final profileData = profile.data();
      final coachId = profileData?['coachId'] as String?;
      if (!profile.exists ||
          profileData?['status'] != 'active' ||
          coachId == null ||
          coachId.trim().isEmpty) {
        throw StateError(
          'Rezervasyon için aktif bir coach ataması gerekli. Lütfen coachunuzla iletişime geçin.',
        );
      }
      final slotReferences = _slotReferences(
        studentId: studentId,
        coachId: coachId,
        scheduledAt: scheduledAt,
      );
      await _assertSlotsFree(transaction, slotReferences, bookingReference.id);
      transaction.set(bookingReference, {
        'studentId': studentId,
        'coachId': coachId,
        'sportName': sportName,
        'packageName': packageName,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'status': 'pending',
        'notes': notes.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _writeSlots(
        transaction,
        slotReferences,
        bookingId: bookingReference.id,
        studentId: studentId,
        coachId: coachId,
        scheduledAt: scheduledAt,
        status: 'pending',
      );
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
      throw ArgumentError('Student and at least one weekly slot are required.');
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
        .toList(growable: false);

    final now = DateTime.now();
    final recurringGroupId =
        '${studentId}_${now.year}${now.month.toString().padLeft(2, '0')}';
    final requestedDates = <DateTime>[];
    for (final slot in weeklySlots) {
      requestedDates.addAll(
        isMonthlyPackage
            ? _monthlyOccurrences(slot, now)
            : List.generate(4, (week) => _nextOccurrence(slot, now, week)),
      );
    }
    final datesToCreate = requestedDates
        .where(
          (scheduledAt) => !existingBookings.any(
            (booking) => booking.scheduledAt == scheduledAt,
          ),
        )
        .toList(growable: false);
    if (datesToCreate.isEmpty) return 0;

    final profileReference = _firestore
        .collection('student_profiles')
        .doc(studentId);
    await _firestore.runTransaction((transaction) async {
      final profile = await transaction.get(profileReference);
      final profileData = profile.data();
      final coachId = profileData?['coachId'] as String?;
      if (!profile.exists ||
          profileData?['status'] != 'active' ||
          coachId == null ||
          coachId.trim().isEmpty) {
        throw StateError(
          'Rezervasyon için aktif bir coach ataması gerekli. Lütfen coachunuzla iletişime geçin.',
        );
      }
      final slotReferences = <DocumentReference<Map<String, dynamic>>>[];
      for (final scheduledAt in datesToCreate) {
        slotReferences.addAll(
          _slotReferences(
            studentId: studentId,
            coachId: coachId,
            scheduledAt: scheduledAt,
          ),
        );
      }
      await _assertSlotsFree(transaction, slotReferences, '');

      for (final scheduledAt in datesToCreate) {
        final bookingReference = _bookings.doc();
        transaction.set(bookingReference, {
          'studentId': studentId,
          'coachId': coachId,
          'sportName': sportName,
          'packageName': packageName,
          'scheduledAt': Timestamp.fromDate(scheduledAt),
          'status': 'pending',
          'notes': 'Haftalik rezervasyon talebi',
          'recurringType': 'weekly',
          'recurringGroupId': recurringGroupId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _writeSlots(
          transaction,
          _slotReferences(
            studentId: studentId,
            coachId: coachId,
            scheduledAt: scheduledAt,
          ),
          bookingId: bookingReference.id,
          studentId: studentId,
          coachId: coachId,
          scheduledAt: scheduledAt,
          status: 'pending',
        );
      }
    });
    return datesToCreate.length;
  }

  Future<void> cancelBooking(String bookingId) async {
    if (bookingId.trim().isEmpty) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Cannot be empty.');
    }

    final bookingReference = _bookings.doc(bookingId);

    await _firestore.runTransaction((transaction) async {
      final booking = await transaction.get(bookingReference);

      if (!booking.exists) {
        throw StateError('İptal edilecek rezervasyon bulunamadı.');
      }

      final data = booking.data();
      if (data == null) {
        throw StateError('Rezervasyon verisi okunamadı.');
      }

      final scheduledAtValue = data['scheduledAt'];
      final studentId = data['studentId'] as String? ?? '';
      final coachId = data['coachId'] as String? ?? '';

      if (scheduledAtValue is! Timestamp ||
          studentId.trim().isEmpty ||
          coachId.trim().isEmpty) {
        throw StateError('Rezervasyon slot bilgileri eksik veya geçersiz.');
      }

      final scheduledAt = scheduledAtValue.toDate();

      final slotsToDelete = await _deleteSlots(
        transaction,
        _slotReferences(
          studentId: studentId,
          coachId: coachId,
          scheduledAt: scheduledAt,
        ),
        bookingId,
      );

      transaction.update(bookingReference, {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final reference in slotsToDelete) {
        transaction.delete(reference);
      }
    });
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

  static String weeklyTimeKey({
    required int dayOfWeek,
    required String startTime,
  }) => '$dayOfWeek|$startTime';

  List<DocumentReference<Map<String, dynamic>>> _slotReferences({
    required String studentId,
    required String coachId,
    required DateTime scheduledAt,
  }) => [
    for (final block in calculateBookingSlotBlocks(
      startTime: scheduledAt,
      endTime: scheduledAt.add(lessonDuration),
    )) ...[
      _bookingSlots.doc(coachSlotDocumentId(coachId, block)),
      _bookingSlots.doc(studentSlotDocumentId(studentId, block)),
    ],
  ];

  Future<void> _assertSlotsFree(
    Transaction transaction,
    Iterable<DocumentReference<Map<String, dynamic>>> references,
    String bookingId,
  ) async {
    for (final reference in references) {
      final slot = await transaction.get(reference);
      if (slot.exists && slot.data()?['bookingId'] != bookingId) {
        throw StateError('Seçilen zaman aralığı başka bir dersle çakışıyor.');
      }
    }
  }

  void _writeSlots(
    Transaction transaction,
    Iterable<DocumentReference<Map<String, dynamic>>> references, {
    required String bookingId,
    required String studentId,
    required String coachId,
    required DateTime scheduledAt,
    required String status,
  }) {
    for (final reference in references) {
      final coachResource = reference.id.startsWith('coach_');
      final blockStart = DateTime.fromMillisecondsSinceEpoch(
        int.parse(reference.id.split('_').last),
      );
      transaction.set(
        reference,
        bookingSlotData(
          resourceType: coachResource ? 'coach' : 'student',
          resourceId: coachResource ? coachId : studentId,
          bookingId: bookingId,
          lessonId: '',
          coachId: coachId,
          studentId: studentId,
          blockStart: blockStart,
          scheduledAt: scheduledAt,
          endTime: scheduledAt.add(lessonDuration),
          status: status,
        ),
      );
    }
  }

  Future<List<DocumentReference<Map<String, dynamic>>>> _deleteSlots(
    Transaction transaction,
    Iterable<DocumentReference<Map<String, dynamic>>> references,
    String bookingId,
  ) async {
    final slotsToDelete = <DocumentReference<Map<String, dynamic>>>[];

    for (final reference in references) {
      final slot = await transaction.get(reference);
      final slotData = slot.data();

      if (!slot.exists || slotData == null) {
        throw StateError('Rezervasyona ait slotlardan biri bulunamadı. İptal işlemi durduruldu.');
      }

      if (slotData['bookingId'] != bookingId) {
        throw StateError('Rezervasyon slot bütünlüğü doğrulanamadı. İptal işlemi durduruldu.');
      }

      slotsToDelete.add(reference);
    }

    return slotsToDelete;
  }

}
