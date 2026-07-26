import 'package:cloud_firestore/cloud_firestore.dart';

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
