import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/login_screen.dart';
import '../../availability/presentation/availability_screen.dart';
import '../../booking/presentation/booking_screen.dart';
import '../../dashboard/models/student_dashboard_model.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'student_profile_screen.dart';
import 'widgets/info_card.dart';
import 'widgets/quick_action_card.dart';
import 'widgets/stats_card.dart';
import 'widgets/welcome_card.dart';
import '../../lessons/screens/student_lessons_screen.dart';
import '../../sports/presentation/sport_selection_screen.dart';
import '../../students/providers/current_student_provider.dart';
import 'student_package_screen.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(currentStudentStreamProvider, (previous, next) {
      final previousProfile = previous?.value;
      final currentProfile = next.value;
      if (previousProfile == null || currentProfile == null) return;

      if (previousProfile.packageId != currentProfile.packageId ||
          previousProfile.sportId != currentProfile.sportId ||
          previousProfile.status != currentProfile.status) {
        ref.invalidate(studentDashboardProvider);
      }
    });

    final dashboardAsync = ref.watch(studentDashboardProvider);

    return Scaffold(
      drawer: dashboardAsync.maybeWhen(
        data: (dashboard) => _StudentDrawer(
          studentName: dashboard.fullName,
          sportName: dashboard.sportName,
          packageName: dashboard.packageName,
          onProfile: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentProfileScreen(dashboard: dashboard),
              ),
            );
          },
          onLogout: () async {
            await _showLogoutDialog(context: context, ref: ref);
          },
        ),
        orElse: () => _StudentDrawer(
          studentName: 'Sporcu',
          sportName: 'BODY HUB',
          packageName: 'Student',
          onProfile: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profil bilgileri yükleniyor.')),
            );
          },
          onLogout: () async {
            await _showLogoutDialog(context: context, ref: ref);
          },
        ),
      ),
      endDrawer: dashboardAsync.maybeWhen(
        data: (dashboard) => _QuickActionsDrawer(dashboard: dashboard),
        orElse: () => null,
      ),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 72,
        title: Image.asset(
          'assets/images/body_hub_logo.png',
          height: 134,
          fit: BoxFit.contain,
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Hızlı İşlemler',
              color: Colors.white,
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.grid_view_rounded, size: 25),
            ),
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
          content: const Text('Hesabından çıkış yapmak istediğine emin misin?'),
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
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Çıkış yapılamadı: $error')));
    }
  }
}

class _QuickActionsDrawer extends StatelessWidget {
  const _QuickActionsDrawer({required this.dashboard});

  final StudentDashboardModel dashboard;

  @override
  Widget build(BuildContext context) => Drawer(
        width: MediaQuery.of(context).size.width * .88,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Icon(Icons.grid_view_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Hızlı İşlemler', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 20),
              QuickActionCard(
                icon: Icons.schedule_rounded,
                title: 'Haftalık Rezervasyon',
                subtitle: 'Gün ve saatlerini planla',
                iconColor: AppColors.success,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvailabilityScreen())),
              ),
              const SizedBox(height: 12),
              QuickActionCard(
                icon: Icons.add_circle_outline_rounded,
                title: 'Ders Rezervasyonu',
                subtitle: 'Tek ders talebi oluştur',
                iconColor: AppColors.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingScreen(dashboard: dashboard))),
              ),
              const SizedBox(height: 12),
              QuickActionCard(
                icon: Icons.calendar_month_rounded,
                title: 'Derslerim',
                subtitle: 'Takvim ve ders detayları',
                iconColor: AppColors.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentLessonsScreen(studentId: dashboard.studentId))),
              ),
              const SizedBox(height: 12),
              QuickActionCard(
                icon: Icons.add_card_rounded,
                title: 'Paket Seç',
                subtitle: 'Yeni paket talebi oluştur',
                iconColor: AppColors.success,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SportSelectionScreen())),
              ),
              const SizedBox(height: 12),
              QuickActionCard(
                icon: Icons.inventory_2_outlined,
                title: 'Paketim',
                subtitle: 'Paket kullanımını görüntüle',
                iconColor: AppColors.info,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentPackageScreen(dashboard: dashboard))),
              ),
              const SizedBox(height: 12),
              QuickActionCard(
                icon: Icons.person_outline_rounded,
                title: 'Profilim',
                subtitle: 'Kişisel bilgilerini düzenle',
                iconColor: AppColors.warning,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentProfileScreen(dashboard: dashboard))),
              ),
            ],
          ),
        ),
      );
}

class _StudentDrawer extends StatelessWidget {
  final String studentName;
  final String sportName;
  final String packageName;
  final VoidCallback onProfile;
  final Future<void> Function() onLogout;

  const _StudentDrawer({
    required this.studentName,
    required this.sportName,
    required this.packageName,
    required this.onProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    void closeDrawer() {
      Navigator.of(context).pop();
    }

    void showMessage(String message) {
      closeDrawer();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    final displayName = studentName.trim().isEmpty
        ? 'Sporcu'
        : studentName.trim();
    final displaySport = sportName.trim().isEmpty
        ? 'Branş belirtilmedi'
        : sportName.trim();
    final displayPackage = packageName.trim().isEmpty
        ? 'Paket belirtilmedi'
        : packageName.trim();

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.78,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 106,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(color: AppColors.navy),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 82,
                    child: Image.asset(
                      'assets/images/body_hub_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$displaySport • $displayPackage',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _DrawerMenuItem(
              icon: Icons.home_rounded,
              title: 'Ana Sayfa',
              onTap: closeDrawer,
            ),
            _DrawerMenuItem(
              icon: Icons.person_outline_rounded,
              title: 'Profil',
              onTap: () {
                closeDrawer();
                onProfile();
              },
            ),
            _DrawerMenuItem(
              icon: Icons.settings_outlined,
              title: 'Ayarlar',
              onTap: () {
                showMessage('Ayarlar ekranı hazırlanıyor.');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.support_agent_rounded,
              title: 'İletişim',
              onTap: () {
                showMessage('İletişim ekranı hazırlanıyor.');
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            _DrawerMenuItem(
              icon: Icons.logout_rounded,
              title: 'Çıkış Yap',
              iconColor: AppColors.error,
              textColor: AppColors.error,
              onTap: () async {
                closeDrawer();

                await Future<void>.delayed(const Duration(milliseconds: 150));

                await onLogout();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
      leading: Icon(icon, color: iconColor ?? AppColors.primary),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: (textColor ?? AppColors.textSecondary).withValues(alpha: 0.65),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final StudentDashboardModel dashboard;
  final Future<void> Function() onRefresh;

  const _DashboardContent({required this.dashboard, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final firstName = _getFirstName(dashboard.fullName);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          WelcomeCard(studentName: firstName),
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
          const _SectionTitle(title: 'Özet', icon: Icons.insights_rounded),
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
                        ? '${dashboard.remainingLessons} / ${dashboard.totalLessons}'
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
            _NextLessonDetailCard(dashboard: dashboard),
          ],
          const SizedBox(height: 24),
          if (Theme.of(context).platform == TargetPlatform.fuchsia) ...[
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
                MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.add_circle_outline_rounded,
            title: 'Ders Rezervasyonu',
            subtitle: 'Uygun tarih ve saat için ders talebi oluştur',
            iconColor: AppColors.primary,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookingScreen(dashboard: dashboard),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      StudentLessonsScreen(studentId: dashboard.studentId),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          QuickActionCard(
            icon: Icons.add_card_rounded,
            title: 'Paket Seç',
            subtitle: 'Branşını ve paketini seçerek koç onayına gönder',
            iconColor: AppColors.success,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SportSelectionScreen(),
                ),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentPackageScreen(dashboard: dashboard),
                ),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentProfileScreen(dashboard: dashboard),
                ),
              );
            },
          ),
          ],
          const SizedBox(height: 28),
          const _MotivationCard(),
        ],
      ),
    );
  }

  static String _getFirstName(String fullName) {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) return 'Sporcu';
    return trimmedName.split(RegExp(r'\s+')).first;
  }

  static IconData _getSportIcon(String sportName) {
    final normalizedSport = sportName.toLowerCase();
    if (normalizedSport.contains('tenis')) return Icons.sports_tennis_rounded;
    if (normalizedSport.contains('fitness') ||
        normalizedSport.contains('kuvvet')) {
      return Icons.fitness_center_rounded;
    }
    if (normalizedSport.contains('yüzme')) return Icons.pool_rounded;
    if (normalizedSport.contains('futbol')) return Icons.sports_soccer_rounded;
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
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

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
          child: Icon(icon, color: AppColors.primary, size: 19),
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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
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

  const _NextLessonDetailCard({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final lessonDate = dashboard.nextLessonDate!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(color: AppColors.textSecondary),
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
          Icon(Icons.bolt_rounded, color: AppColors.primaryLight, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Başarı, her gün tekrarlanan küçük ve doğru adımların sonucudur.',
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
              border: Border.all(color: AppColors.border),
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

  const _DashboardErrorView({required this.error, required this.onRetry});

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
