import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';

/// Firestore mapping for the immutable V2 Sport catalogue contract.
class SportModel extends SportRecord {
  const SportModel({
    required super.id,
    required super.name,
    required super.active,
    required super.sortOrder,
  });

  factory SportModel.fromFirestore(String id, Map<String, dynamic> data) {
    return SportModel(
      id: id,
      name: data[BodyHubFields.name] as String? ?? '',
      active: data[BodyHubFields.active] as bool? ?? false,
      sortOrder: data[BodyHubFields.sortOrder] as int? ?? 0,
    );
  }
}
