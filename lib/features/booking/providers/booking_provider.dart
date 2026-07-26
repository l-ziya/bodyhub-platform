import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking_model.dart';
import '../repositories/booking_repository.dart';
import '../repositories/lesson_change_request_repository.dart';

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

final lessonChangeRequestRepositoryProvider =
    Provider<LessonChangeRequestRepository>(
  (ref) => LessonChangeRequestRepository(),
);

final studentBookingsProvider =
    StreamProvider.family<List<BookingModel>, String>((ref, studentId) {
      return ref
          .watch(bookingRepositoryProvider)
          .watchStudentBookings(studentId);
    });
