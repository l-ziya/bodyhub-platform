class PackageModel {
  final String id;
  final String sportId;
  final String name;
  final int lessonLimit;
  final int durationDays;
  final int weeklyLimit;
  final bool active;

  const PackageModel({
    required this.id,
    required this.sportId,
    required this.name,
    required this.lessonLimit,
    required this.durationDays,
    required this.weeklyLimit,
    required this.active,
  });

  factory PackageModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PackageModel(
      id: id,
      sportId: data['sportId'] ?? '',
      name: data['name'] ?? '',
      lessonLimit: data['lessonLimit'] ?? 0,
      durationDays: data['durationDays'] ?? 0,
      weeklyLimit: data['weeklyLimit'] ?? 0,
      active: data['active'] ?? false,
    );
  }
}