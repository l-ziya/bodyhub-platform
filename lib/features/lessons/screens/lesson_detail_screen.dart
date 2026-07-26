import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/lesson_model.dart';

class LessonDetailScreen extends StatelessWidget {
  const LessonDetailScreen({
    super.key,
    required this.lesson,
  });

  final LessonModel lesson;

  @override
  Widget build(BuildContext context) {
    final duration = lesson.endTime.difference(lesson.startTime).inMinutes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ders Detayı'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          _HeaderCard(lesson: lesson),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Ders Bilgileri',
            children: [
              _DetailRow(
                icon: Icons.calendar_month_rounded,
                label: 'Tarih',
                value: DateFormat(
                  'dd MMMM yyyy, EEEE',
                  'tr_TR',
                ).format(lesson.startTime),
              ),
              _DetailRow(
                icon: Icons.schedule_rounded,
                label: 'Saat',
                value:
                    '${DateFormat('HH:mm').format(lesson.startTime)} - '
                    '${DateFormat('HH:mm').format(lesson.endTime)}',
              ),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Süre',
                value: '$duration dakika',
              ),
              _DetailRow(
                icon: Icons.confirmation_number_outlined,
                label: 'Ders No',
                value: '${lesson.lessonNumber}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Antrenman Bilgileri',
            children: [
              _DetailRow(
                icon: Icons.person_rounded,
                label: 'Antrenör',
                value: lesson.coachName,
              ),
              _DetailRow(
                icon: Icons.location_on_rounded,
                label: 'Konum',
                value: lesson.location,
              ),
              _DetailRow(
                icon: Icons.inventory_2_outlined,
                label: 'Paket',
                value: lesson.packageName,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Durum',
            children: [
              _StatusRow(
                icon: Icons.flag_rounded,
                label: 'Ders Durumu',
                value: _lessonStatusText(lesson.status),
                color: _lessonStatusColor(lesson.status),
              ),
              _StatusRow(
                icon: Icons.fact_check_rounded,
                label: 'Yoklama',
                value: _attendanceText(lesson.attendanceStatus),
                color: _attendanceColor(lesson.attendanceStatus),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _lessonStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'Tamamlandı';
      case 'cancelled':
        return 'İptal Edildi';
      case 'makeup':
        return 'Telafi Dersi';
      case 'scheduled':
      default:
        return 'Planlandı';
    }
  }

  static Color _lessonStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'makeup':
        return AppColors.warning;
      case 'scheduled':
      default:
        return AppColors.primary;
    }
  }

  static String _attendanceText(String status) {
    switch (status) {
      case 'present':
        return 'Katıldı';
      case 'absent':
        return 'Katılmadı';
      case 'late':
        return 'Geç Katıldı';
      case 'pending':
      default:
        return 'Bekliyor';
    }
  }

  static Color _attendanceColor(String status) {
    switch (status) {
      case 'present':
        return AppColors.success;
      case 'absent':
        return AppColors.error;
      case 'late':
        return AppColors.warning;
      case 'pending':
      default:
        return AppColors.textSecondary;
    }
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.lesson,
  });

  final LessonModel lesson;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.softGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _sportIcon(lesson.sportIcon),
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.sportName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  lesson.packageName,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _sportIcon(String sportIcon) {
    switch (sportIcon) {
      case 'tennis':
        return Icons.sports_tennis_rounded;
      case 'fitness':
        return Icons.fitness_center_rounded;
      case 'athletic':
        return Icons.directions_run_rounded;
      case 'swimming':
        return Icons.pool_rounded;
      case 'pilates':
        return Icons.self_improvement_rounded;
      default:
        return Icons.sports_rounded;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 21,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
