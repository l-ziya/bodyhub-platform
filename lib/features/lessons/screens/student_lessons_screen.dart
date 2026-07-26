import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lesson_model.dart';
import '../providers/lessons_provider.dart';
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
            _lessonList(upcoming, completed: false),
            _lessonList(past, completed: true),
          ],
        ),
      ),
    );
  }

  Widget _lessonList(
    AsyncValue<List<LessonModel>> value,
    {required bool completed}
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

        return _LessonCalendarView(
          lessons: lessons,
          completed: completed,
        );
      },
    );
  }
}

class _LessonCalendarView extends StatelessWidget {
  const _LessonCalendarView({
    required this.lessons,
    required this.completed,
  });

  final List<LessonModel> lessons;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final months = <DateTime, List<LessonModel>>{};
    for (final lesson in lessons) {
      final month = DateTime(lesson.startTime.year, lesson.startTime.month);
      months.putIfAbsent(month, () => []).add(lesson);
    }
    final sortedMonths = months.keys.toList()..sort();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: sortedMonths
          .map(
            (month) => _LessonMonthCalendar(
              month: month,
              lessons: months[month]!,
              completed: completed,
            ),
          )
          .toList(),
    );
  }
}

class _LessonMonthCalendar extends StatelessWidget {
  const _LessonMonthCalendar({
    required this.month,
    required this.lessons,
    required this.completed,
  });

  final DateTime month;
  final List<LessonModel> lessons;
  final bool completed;

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  Color _pastLessonColor(LessonModel lesson) => switch (lesson.attendanceStatus) {
        'attended' => Colors.green.withValues(alpha: .16),
        'late' => Colors.orange.withValues(alpha: .18),
        'absent' => Colors.red.withValues(alpha: .14),
        'make_up' => Colors.purple.withValues(alpha: .15),
        _ => Colors.blueGrey.withValues(alpha: .12),
      };

  IconData _pastLessonIcon(LessonModel lesson) => switch (lesson.attendanceStatus) {
        'attended' => Icons.check_circle_rounded,
        'late' => Icons.schedule_rounded,
        'absent' => Icons.person_off_rounded,
        'make_up' => Icons.replay_rounded,
        _ => Icons.help_outline_rounded,
      };

  Color _pastLessonIconColor(LessonModel lesson) => switch (lesson.attendanceStatus) {
        'attended' => Colors.green,
        'late' => Colors.orange.shade800,
        'absent' => Colors.red,
        'make_up' => Colors.purple,
        _ => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<LessonModel>>{};
    for (final lesson in lessons) {
      byDay.putIfAbsent(lesson.startTime.day, () => []).add(lesson);
    }
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = ((firstWeekday - 1 + days + 6) ~/ 7) * 7;

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '${_months[month.month - 1]} ${month.year}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: .82,
              children: List.generate(cells + 7, (index) {
                if (index < 7) return Center(child: Text(_weekdays[index], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)));
                final day = index - 7 - (firstWeekday - 1) + 1;
                if (day < 1 || day > days) return const SizedBox.shrink();
                final dayLessons = byDay[day] ?? const [];
                final primaryLesson = dayLessons.isEmpty ? null : dayLessons.first;
                return InkWell(
                  onTap: dayLessons.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonDetailScreen(lesson: dayLessons.first))),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: dayLessons.isEmpty
                          ? null
                          : completed
                          ? _pastLessonColor(primaryLesson!)
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$day', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (completed && primaryLesson != null)
                          Icon(_pastLessonIcon(primaryLesson), color: _pastLessonIconColor(primaryLesson), size: 16),
                        if (!completed) ...dayLessons.take(2).map((lesson) => Text('${lesson.startTime.hour.toString().padLeft(2, '0')}:${lesson.startTime.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(completed
                ? 'Yeşil: katıldı • Turuncu: geç • Kırmızı: katılmadı • Mor: telafi'
                : 'Dolu günlerde ders saatleri yer alır.'),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LessonsTable extends StatelessWidget {
  const _LessonsTable({required this.lessons});

  final List<LessonModel> lessons;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.primaryContainer,
              ),
              columns: const [
                DataColumn(label: Text('Tarih')),
                DataColumn(label: Text('Saat')),
                DataColumn(label: Text('Branş')),
                DataColumn(label: Text('Paket')),
                DataColumn(label: Text('Durum')),
              ],
              rows: lessons.map((lesson) {
                return DataRow(
                  onSelectChanged: (_) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonDetailScreen(lesson: lesson),
                      ),
                    );
                  },
                  cells: [
                    DataCell(Text(_dateText(lesson.startTime))),
                    DataCell(Text(_timeText(lesson.startTime, lesson.endTime))),
                    DataCell(Text(lesson.sportName)),
                    DataCell(Text(lesson.packageName)),
                    DataCell(_StatusChip(status: lesson.status)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ders detayını görmek için ilgili satıra dokunun.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  static String _timeText(DateTime start, DateTime end) =>
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isScheduled = status == 'scheduled';
    return Chip(
      label: Text(isScheduled ? 'Planlandı' : status),
      visualDensity: VisualDensity.compact,
      backgroundColor: isScheduled
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
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
