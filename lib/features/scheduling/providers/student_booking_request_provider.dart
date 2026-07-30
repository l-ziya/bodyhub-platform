import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/student_booking_request_repository.dart';

/// Provides Student-side V2 booking-request operations without UI coupling.
final studentBookingRequestRepositoryProvider =
    Provider<StudentBookingRequestRepository>(
      (ref) => StudentBookingRequestRepository(),
    );

/// Streams only the authenticated Student's explicitly scoped request list.
final studentBookingRequestsProvider = StreamProvider.autoDispose
    .family<List<BookingRequestRecord>, String>(
      (ref, studentId) => ref
          .watch(studentBookingRequestRepositoryProvider)
          .watchOwnRequests(studentId),
    );
