import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/login_screen.dart';
import '../../availability/presentation/availability_screen.dart';
import '../../dashboard/models/student_dashboard_model.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'widgets/info_card.dart';
import 'widgets/quick_action_card.dart';
import 'widgets/stats_card.dart';
import 'widgets/welcome_card.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(studentDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BODY HUB',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () {
              ref.invalidate(studentDashboardProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Çıkış Yap',
            onPressed: () async {
              await _showLogoutDialog(
                context: context,
                ref: ref,
              );
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const _DashboardLoadingView(),
        error: (error, stackTrace) {
          return _DashboardErrorView(
            error: error.toString(),
            onRetry: () {
              ref.invalidate(studentDashboardProvider);
            },
          );
        },
        data: (dashboard) {
          return _DashboardContent(
            dashboard: dashboard,
            onRefresh: () async {
              ref.invalidate(studentDashboardProvider);
              await ref.read(studentDashboardProvider.future);
            },
          );
        },
      ),
    );
  }

  Future<void> _showLogoutDialog({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Çıkış Yap'),
          content: const Text(
            'Hesabından çıkış yapmak istediğine emin misin?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Vazgeç'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Çıkış Yap'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    try {
      await FirebaseAuth.instance.signOut();

      ref.invalidate(studentDashboardProvider);

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Çıkış yapılamadı: $error',
          ),
        ),
      );
    }
  }
}

class _DashboardContent extends StatelessWidget {
  final StudentDashboardModel dashboard;
  final Future<void> Function() onRefresh;

  const _DashboardContent({
    required this.dashboard,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = _getFirstName(dashboard.fullName);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          WelcomeCard(
            studentName: firstName,
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Spor Bilgilerim',
            icon: Icons.sports_rounded,
          ),
          const SizedBox(height: 12),
          InfoCard(
            icon: _getSportIcon(dashboard.sportName),
            title: 'Branş',
            value: dashboard.sportName,
          ),
          const SizedBox(height: 12),
          InfoCard(
            icon: Icons.inventory_2_outlined,
            title: 'Paket',
            value: dashboard.packageName,
            iconColor: AppColors.info,
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Özet',
            icon: Icons.insights_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 172,
                  child: StatsCard(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Kalan Ders',
                    value: dashboard.hasPackage
                        ? '${dashboard.remainingLessons} / '
                            '${dashboard.totalLessons}'
                        : 'Paket yok',
                    iconColor: dashboard.hasRemainingLessons
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 172,
                  child: StatsCard(
                    icon: Icons.event_available_rounded,
                    title: 'Sonraki Ders',
                    value: dashboard.hasNextLesson
                        ? _formatLessonDate(dashboard.nextLessonDate!)
                        : 'Henüz planlanmadı',
                    iconColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (dashboard.hasPackage) ...[
            const SizedBox(height: 16),
            _PackageProgressCard(
              totalLessons: dashboard.totalLessons,
              usedLessons: dashboard.usedLessons,
              remainingLessons: dashboard.remainingLessons,
              progress: dashboard.usageProgress,
            ),
          ],
          if (dashboard.hasNextLesson) ...[
            const SizedBox(height: 16),
            _NextLessonDetailCard(
              dashboard: dashboard,
            ),
          ],
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Hızlı İşlemler',
            icon: Icons.grid_view_rounded,
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.schedule_rounded,
            title: 'Uygunluklarım',
            subtitle: 'Haftalık uygun gün ve saatlerini düzenle',
            iconColor: AppColors.success,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AvailabilityScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.calendar_month_rounded,
            title: 'Derslerim',
            subtitle: 'Planlanan ve geçmiş derslerini görüntüle',
            iconColor: AppColors.primary,
            onTap: () {
              _showComingSoon(
                context,
                'Derslerim ekranı hazırlanıyor.',
              );
            },
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.inventory_2_outlined,
            title: 'Paketim',
            subtitle: 'Paket kullanım ve kalan ders bilgilerini gör',
            iconColor: AppColors.info,
            onTap: () {
              _showComingSoon(
                context,
                'Paket detay ekranı hazırlanıyor.',
              );
            },
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.person_outline_rounded,
            title: 'Profilim',
            subtitle: 'Kişisel ve sportif bilgilerini düzenle',
            iconColor: AppColors.warning,
            onTap: () {
              _showComingSoon(
                context,
                'Profil düzenleme ekranı hazırlanıyor.',
              );
            },
          ),
          const SizedBox(height: 28),
          const _MotivationCard(),
        ],
      ),
    );
  }

  static String _getFirstName(String fullName) {
    final trimmedName = fullName.trim();

    if (trimmedName.isEmpty) {
      return 'Sporcu';
    }

    return trimmedName.split(RegExp(r'\s+')).first;
  }

  static IconData _getSportIcon(String sportName) {
    final normalizedSport = sportName.toLowerCase();

    if (normalizedSport.contains('tenis')) {
      return Icons.sports_tennis_rounded;
    }

    if (normalizedSport.contains('fitness') ||
        normalizedSport.contains('kuvvet')) {
      return Icons.fitness_center_rounded;
    }

    if (normalizedSport.contains('yüzme')) {
      return Icons.pool_rounded;
    }

    if (normalizedSport.contains('futbol')) {
      return Icons.sports_soccer_rounded;
    }

    if (normalizedSport.contains('basketbol')) {
      return Icons.sports_basketball_rounded;
    }

    if (normalizedSport.contains('koşu') ||
        normalizedSport.contains('atletik') ||
        normalizedSport.contains('atletizm')) {
      return Icons.directions_run_rounded;
    }

    return Icons.sports_rounded;
  }

  static String _formatLessonDate(DateTime date) {
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

    return '${date.day} ${months[date.month - 1]}\n$hour:$minute';
  }

  static void _showComingSoon(
    BuildContext context,
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _PackageProgressCard extends StatelessWidget {
  final int totalLessons;
  final int usedLessons;
  final int remainingLessons;
  final double progress;

  const _PackageProgressCard({
    required this.totalLessons,
    required this.usedLessons,
    required this.remainingLessons,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.softGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Paket Kullanımı',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$remainingLessons ders kaldı',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Kullanılan: $usedLessons',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'Toplam: $totalLessons',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextLessonDetailCard extends StatelessWidget {
  final StudentDashboardModel dashboard;

  const _NextLessonDetailCard({
    required this.dashboard,
  });

  @override
  Widget build(BuildContext context) {
    final lessonDate = dashboard.nextLessonDate!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yaklaşan Ders',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatFullDate(lessonDate),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dashboard.nextLessonBranch?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    dashboard.nextLessonBranch!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (dashboard.nextLessonLocation?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dashboard.nextLessonLocation!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    const dayNames = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

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

    return '${date.day} ${months[date.month - 1]} '
        '${dayNames[date.weekday - 1]}, $hour:$minute';
  }
}

class _MotivationCard extends StatelessWidget {
  const _MotivationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bolt_rounded,
            color: AppColors.primaryLight,
            size: 28,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Başarı, her gün tekrarlanan küçük ve doğru adımların '
              'sonucudur.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingView extends StatelessWidget {
  const _DashboardLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
            color: AppColors.disabledBackground,
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(
          5,
          (index) => Container(
            height: 92,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
          ),
        ),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }
}

class _DashboardErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _DashboardErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Dashboard yüklenemedi',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}