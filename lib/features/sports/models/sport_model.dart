class SportModel {
  final String id;
  final String name;
  final bool active;

  const SportModel({
    required this.id,
    required this.name,
    required this.active,
  });

  factory SportModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return SportModel(
      id: id,
      name: data['name'] ?? '',
      active: data['active'] ?? false,
    );
  }
}