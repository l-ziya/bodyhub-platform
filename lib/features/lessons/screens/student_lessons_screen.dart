import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lesson_model.dart';
import '../providers/lessons_provider.dart';
import '../widgets/lesson_card.dart';
import 'lesson_detail_screen.dart';
import 'student_lesson_calendar_screen.dart';

class StudentLessonsScreen extends ConsumerStatefulWidget {
  const StudentLessonsScreen({
    super.key,
    required this.studentId,
  });

  final String studentId;

  @override
  ConsumerState<StudentLessonsScreen> createState() =>
      _StudentLessonsScreenState();
}

class _StudentLessonsScreenState
    extends ConsumerState<StudentLessonsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(upcomingLessonsProvider(widget.studentId));
    ref.invalidate(pastLessonsProvider(widget.studentId));

    await Future.wait([
      ref.read(upcomingLessonsProvider(widget.studentId).future),
      ref.read(pastLessonsProvider(widget.studentId).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = ref.watch(
      upcomingLessonsProvider(widget.studentId),
    );
    final past = ref.watch(
      pastLessonsProvider(widget.studentId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Derslerim'),
        actions: [
          IconButton(
            tooltip: 'Ders Takvimi',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentLessonCalendarScreen(
                    studentId: widget.studentId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Yaklaşan'),
            Tab(text: 'Geçmiş'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: TabBarView(
          controller: _controller,
          children: [
            _lessonList(upcoming),
            _lessonList(past),
          ],
        ),
      ),
    );
  }

  Widget _lessonList(
    AsyncValue<List<LessonModel>> value,
  ) {
    return value.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stackTrace) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.error_outline_rounded,
            size: 54,
          ),
          const SizedBox(height: 16),
          Text(
            'Dersler yüklenemedi.\n$error',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      data: (lessons) {
        if (lessons.isEmpty) {
          return const _EmptyLessonsView();
        }

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            top: 12,
            bottom: 24,
          ),
          itemCount: lessons.length,
          itemBuilder: (context, index) {
            final lesson = lessons[index];

            return LessonCard(
              lesson: lesson,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LessonDetailScreen(
                      lesson: lesson,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyLessonsView extends StatelessWidget {
  const _EmptyLessonsView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(
          Icons.event_busy_rounded,
          size: 58,
        ),
        SizedBox(height: 16),
        Text(
          'Gösterilecek ders bulunamadı.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
