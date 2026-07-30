import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/student_schedule_slot_discovery_repository.dart';

/// Immutable, scoped query key for V2 Student availability discovery.
class StudentScheduleSlotDiscoveryQuery {
  /// Creates a discovery key for one Coach and one canonical local day.
  StudentScheduleSlotDiscoveryQuery({
    required String coachId,
    required String dayKey,
  }) : coachId = _requireCoachId(coachId),
       dayKey = BodyHubSchedulingContract.requireDayKey(dayKey);

  /// Selected Coach Auth UID.
  final String coachId;

  /// Selected canonical `YYYY-MM-DD` day coordinate.
  final String dayKey;

  @override
  bool operator ==(Object other) =>
      other is StudentScheduleSlotDiscoveryQuery &&
      other.coachId == coachId &&
      other.dayKey == dayKey;

  @override
  int get hashCode => Object.hash(coachId, dayKey);

  static String _requireCoachId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'coachId', 'must not be empty');
    }
    return normalized;
  }
}

/// Provides the scoped V2 availability discovery repository.
final studentScheduleSlotDiscoveryRepositoryProvider =
    Provider<StudentScheduleSlotDiscoveryRepository>(
      (ref) => StudentScheduleSlotDiscoveryRepository(),
    );

/// Reads active canonical slots for one explicitly selected Coach and day.
final studentActiveScheduleSlotsProvider = FutureProvider.autoDispose
    .family<
      List<CoachScheduleSlotAvailabilityRecord>,
      StudentScheduleSlotDiscoveryQuery
    >(
      (ref, query) => ref
          .watch(studentScheduleSlotDiscoveryRepositoryProvider)
          .getActiveSlots(coachId: query.coachId, dayKey: query.dayKey),
    );
