import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lesson_model.dart';
import '../providers/lessons_provider.dart';
import '../widgets/lesson_card.dart';
import 'lesson_detail_screen.dart';

class StudentLessonCalendarScreen extends ConsumerStatefulWidget {
  const StudentLessonCalendarScreen({
    super.key,
    required this.studentId,
  });

  final String studentId;

  @override
  ConsumerState<StudentLessonCalendarScreen> createState() =>
      _StudentLessonCalendarScreenState();
}

class _StudentLessonCalendarScreenState
    extends ConsumerState<StudentLessonCalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final upcoming = ref.watch(upcomingLessonsProvider(widget.studentId));
    final past = ref.watch(pastLessonsProvider(widget.studentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ders Takvimi'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
                onDateChanged: (date) {
                  setState(() {
                    _selectedDate = date;
                  });
                },
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _selectedDateTitle(_selectedDate),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _buildLessons(upcoming, past),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(upcomingLessonsProvider(widget.studentId));
    ref.invalidate(pastLessonsProvider(widget.studentId));

    await Future.wait([
      ref.read(upcomingLessonsProvider(widget.studentId).future),
      ref.read(pastLessonsProvider(widget.studentId).future),
    ]);
  }

  Widget _buildLessons(
    AsyncValue<List<LessonModel>> upcoming,
    AsyncValue<List<LessonModel>> past,
  ) {
    if (upcoming.isLoading || past.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (upcoming.hasError || past.hasError) {
      final error = upcoming.error ?? past.error;

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              'Dersler yüklenemedi.\n$error',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final lessons = <LessonModel>[
      ...?upcoming.value,
      ...?past.value,
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));

    final selectedLessons = lessons.where((lesson) {
      return _isSameDay(lesson.startTime, _selectedDate);
    }).toList();

    if (selectedLessons.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 54),
            SizedBox(height: 14),
            Text(
              'Bu tarihte planlanmış ders bulunmuyor.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: selectedLessons.map((lesson) {
        return LessonCard(
          lesson: lesson,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LessonDetailScreen(lesson: lesson),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _selectedDateTitle(DateTime date) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
