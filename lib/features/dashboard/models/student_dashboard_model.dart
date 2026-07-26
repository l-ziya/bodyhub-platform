class StudentDashboardModel {
  final String studentId;
  final String fullName;
  final String sportName;
  final String packageName;
  final int totalLessons;
  final int usedLessons;
  final int remainingLessons;
  final DateTime? nextLessonDate;
  final String? nextLessonBranch;
  final String? nextLessonLocation;

  const StudentDashboardModel({
    required this.studentId,
    required this.fullName,
    required this.sportName,
    required this.packageName,
    required this.totalLessons,
    required this.usedLessons,
    required this.remainingLessons,
    this.nextLessonDate,
    this.nextLessonBranch,
    this.nextLessonLocation,
  });

  factory StudentDashboardModel.empty({
    required String studentId,
  }) {
    return StudentDashboardModel(
      studentId: studentId,
      fullName: 'Öğrenci',
      sportName: 'Branş seçilmedi',
      packageName: 'Paket seçilmedi',
      totalLessons: 0,
      usedLessons: 0,
      remainingLessons: 0,
      nextLessonDate: null,
      nextLessonBranch: null,
      nextLessonLocation: null,
    );
  }

  StudentDashboardModel copyWith({
    String? studentId,
    String? fullName,
    String? sportName,
    String? packageName,
    int? totalLessons,
    int? usedLessons,
    int? remainingLessons,
    DateTime? nextLessonDate,
    String? nextLessonBranch,
    String? nextLessonLocation,
    bool clearNextLessonDate = false,
    bool clearNextLessonBranch = false,
    bool clearNextLessonLocation = false,
  }) {
    return StudentDashboardModel(
      studentId: studentId ?? this.studentId,
      fullName: fullName ?? this.fullName,
      sportName: sportName ?? this.sportName,
      packageName: packageName ?? this.packageName,
      totalLessons: totalLessons ?? this.totalLessons,
      usedLessons: usedLessons ?? this.usedLessons,
      remainingLessons: remainingLessons ?? this.remainingLessons,
      nextLessonDate: clearNextLessonDate
          ? null
          : nextLessonDate ?? this.nextLessonDate,
      nextLessonBranch: clearNextLessonBranch
          ? null
          : nextLessonBranch ?? this.nextLessonBranch,
      nextLessonLocation: clearNextLessonLocation
          ? null
          : nextLessonLocation ?? this.nextLessonLocation,
    );
  }

  bool get hasPackage => totalLessons > 0;

  bool get hasRemainingLessons => remainingLessons > 0;

  bool get hasNextLesson => nextLessonDate != null;

  double get usageProgress {
    if (totalLessons <= 0) {
      return 0;
    }

    final progress = usedLessons / totalLessons;

    return progress.clamp(0.0, 1.0);
  }
}