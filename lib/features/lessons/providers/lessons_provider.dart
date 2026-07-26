import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lesson_model.dart';
import '../repositories/lesson_repository.dart';

/// Repository
final lessonRepositoryProvider = Provider<LessonRepository>(
  (ref) => LessonRepository(),
);

/// Yaklaşan dersler
final upcomingLessonsProvider = FutureProvider.family<
    List<LessonModel>, String>(
  (ref, studentId) async {
    final repository = ref.watch(
      lessonRepositoryProvider,
    );

    return repository.getUpcomingLessons(
      studentId,
    );
  },
);

/// Geçmiş dersler
final pastLessonsProvider = FutureProvider.family<
    List<LessonModel>, String>(
  (ref, studentId) async {
    final repository = ref.watch(
      lessonRepositoryProvider,
    );

    return repository.getPastLessons(
      studentId,
    );
  },
);

/// Tek ders
final lessonProvider = FutureProvider.family<
    LessonModel?, String>(
  (ref, lessonId) async {
    final repository = ref.watch(
      lessonRepositoryProvider,
    );

    return repository.getLesson(
      lessonId,
    );
  },
);