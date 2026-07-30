import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';

/// Immutable Firestore mapping for a public V2 Coach discovery profile.
class CoachProfileModel extends CoachProfileRecord {
  CoachProfileModel({
    required super.coachId,
    required super.displayName,
    required super.active,
    required super.bookingEnabled,
    required super.specialtyIds,
    required super.bio,
    required super.photoUrl,
  });

  factory CoachProfileModel.fromFirestore(
    String coachId,
    Map<String, dynamic> data,
  ) {
    final rawSpecialties = data[BodyHubFields.specialtyIds];
    return CoachProfileModel(
      coachId: coachId,
      displayName: data[BodyHubFields.displayName] as String? ?? '',
      active: data[BodyHubFields.active] as bool? ?? false,
      bookingEnabled: data[BodyHubFields.bookingEnabled] as bool? ?? false,
      specialtyIds: rawSpecialties is Iterable
          ? rawSpecialties.whereType<String>()
          : const <String>[],
      bio: data[BodyHubFields.bio] as String? ?? '',
      photoUrl: data[BodyHubFields.photoUrl] as String? ?? '',
    );
  }
}
