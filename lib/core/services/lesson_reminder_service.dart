import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/lessons/models/lesson_model.dart';
import '../../features/lessons/repositories/lesson_repository.dart';

class LessonReminderService {
  LessonReminderService._();

  static final LessonReminderService instance = LessonReminderService._();

  static const _channelId = 'lesson_reminders';
  static const _channelName = 'Ders hatırlatmaları';
  static const _channelDescription =
      'Yaklaşan BODY HUB dersleri için hatırlatmalar';

  final _notifications = FlutterLocalNotificationsPlugin();
  final _lessonRepository = LessonRepository();

  StreamSubscription<List<LessonModel>>? _lessonSubscription;
  String? _studentId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  Future<void> startForStudent(String studentId) async {
    if (studentId.trim().isEmpty) return;
    await initialize();
    if (_studentId == studentId && _lessonSubscription != null) return;

    await _lessonSubscription?.cancel();
    _studentId = studentId;
    _lessonSubscription = _lessonRepository
        .watchUpcomingLessons(studentId)
        .listen(
          (lessons) => unawaited(_scheduleReminders(lessons)),
          onError: (_, _) {},
        );
  }

  Future<void> _scheduleReminders(List<LessonModel> lessons) async {
    final now = DateTime.now();
    await _notifications.cancelAll();

    for (final lesson in lessons) {
      if (lesson.status != 'scheduled' || !lesson.startTime.isAfter(now)) {
        continue;
      }

      await _scheduleReminder(
        lesson: lesson,
        notificationId: _notificationId(lesson.id, 24),
        reminderTime: lesson.startTime.subtract(const Duration(hours: 24)),
        title: 'Dersine 24 saat kaldı',
        body: _reminderBody(lesson),
      );
      await _scheduleReminder(
        lesson: lesson,
        notificationId: _notificationId(lesson.id, 1),
        reminderTime: lesson.startTime.subtract(const Duration(hours: 1)),
        title: 'Dersin 1 saat sonra başlıyor',
        body: _reminderBody(lesson),
      );
    }
  }

  Future<void> _scheduleReminder({
    required LessonModel lesson,
    required int notificationId,
    required DateTime reminderTime,
    required String title,
    required String body,
  }) async {
    if (!reminderTime.isAfter(DateTime.now())) return;

    await _notifications.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: lesson.id,
    );
  }

  String _reminderBody(LessonModel lesson) {
    final time =
        '${lesson.startTime.hour.toString().padLeft(2, '0')}:${lesson.startTime.minute.toString().padLeft(2, '0')}';
    final location = lesson.location.trim().isEmpty
        ? ''
        : ' • ${lesson.location}';
    return '${lesson.sportName} dersi saat $time$location';
  }

  int _notificationId(String lessonId, int reminderHour) {
    var hash = 2166136261;
    for (final unit in lessonId.codeUnits) {
      hash = (hash ^ unit) * 16777619;
      hash &= 0x7fffffff;
    }
    return (hash + reminderHour) & 0x7fffffff;
  }
}
