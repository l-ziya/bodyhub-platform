import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../dashboard/models/student_dashboard_model.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class StudentPackageScreen extends ConsumerWidget {
  const StudentPackageScreen({
    super.key,
    required this.dashboard,
  });

  final StudentDashboardModel dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveDashboard = ref.watch(studentDashboardProvider).value ?? dashboard;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paketim'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: liveDashboard.hasPackage
          ? _PackageContent(dashboard: liveDashboard)
          : const _NoPackageView(),
    );
  }
}

class _PackageContent extends StatelessWidget {
  const _PackageContent({
    required this.dashboard,
  });

  final StudentDashboardModel dashboard;

  @override
  Widget build(BuildContext context) {
    final remainingRatio = dashboard.totalLessons == 0
        ? 0.0
        : dashboard.remainingLessons / dashboard.totalLessons;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: AppColors.softGradient,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: AppColors.primary,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aktif Paket',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dashboard.packageName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dashboard.sportName,
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _SummaryBox(
                      title: 'Toplam',
                      value: '${dashboard.totalLessons}',
                      icon: Icons.confirmation_number_outlined,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryBox(
                      title: 'Kullanılan',
                      value: '${dashboard.usedLessons}',
                      icon: Icons.check_circle_outline_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryBox(
                      title: 'Kalan',
                      value: '${dashboard.remainingLessons}',
                      icon: Icons.hourglass_bottom_rounded,
                      color: dashboard.remainingLessons > 0
                          ? AppColors.primary
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ProgressCard(
          usedLessons: dashboard.usedLessons,
          totalLessons: dashboard.totalLessons,
          usageProgress: dashboard.usageProgress,
          remainingRatio: remainingRatio,
        ),
        const SizedBox(height: 18),
        _InformationCard(
          title: 'Paket Bilgisi',
          rows: [
            _InformationItem(
              icon: Icons.sports_rounded,
              label: 'Branş',
              value: dashboard.sportName,
            ),
            _InformationItem(
              icon: Icons.inventory_2_outlined,
              label: 'Paket',
              value: dashboard.packageName,
            ),
            _InformationItem(
              icon: Icons.event_available_rounded,
              label: 'Sonraki Ders',
              value: dashboard.hasNextLesson
                  ? _formatDate(dashboard.nextLessonDate!)
                  : 'Henüz planlanmadı',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primaryLight,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Paket yenileme ve branş değişikliği işlemleri koç onayıyla '
                  'gerçekleştirilir.',
                  style: TextStyle(
                    color: Colors.white,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
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

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute';
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.usedLessons,
    required this.totalLessons,
    required this.usageProgress,
    required this.remainingRatio,
  });

  final int usedLessons;
  final int totalLessons;
  final double usageProgress;
  final double remainingRatio;

  @override
  Widget build(BuildContext context) {
    final percentage = (usageProgress.clamp(0.0, 1.0) * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paket İlerlemesi',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: usageProgress.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$usedLessons / $totalLessons ders kullanıldı',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '%$percentage',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            remainingRatio > 0
                ? 'Paketinin ${(remainingRatio * 100).round()}% kadarı kaldı.'
                : 'Paketindeki tüm dersler kullanıldı.',
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_InformationItem> rows;

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
          ...rows,
        ],
      ),
    );
  }
}

class _InformationItem extends StatelessWidget {
  const _InformationItem({
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
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 21,
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

class _NoPackageView extends StatelessWidget {
  const _NoPackageView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aktif paket bulunamadı',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Paket ataması yapıldığında paket detayların burada '
              'görüntülenecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
