import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../dashboard/models/student_dashboard_model.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../students/providers/current_student_provider.dart';
import 'student_edit_profile_screen.dart';

class StudentProfileScreen extends ConsumerWidget {
  final StudentDashboardModel dashboard;

  const StudentProfileScreen({super.key, required this.dashboard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final profile = ref.watch(currentStudentProvider).value;
    final fullName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName
        : dashboard.fullName;
    final email = _displayValue(
      profile?.email ?? user?.email,
      'E-posta bilgisi bulunamadı',
    );
    final phone = _displayValue(
      profile?.phone ?? user?.phoneNumber,
      'Telefon bilgisi eklenmedi',
    );
    final gender = _genderLabel(profile?.gender ?? dashboard.gender);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profilim',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          _ProfileHeader(
            fullName: fullName,
            sportName: dashboard.sportName,
            packageName: dashboard.packageName,
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Kişisel Bilgiler',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 12),
          _ProfileInfoCard(
            children: [
              _ProfileInfoRow(
                icon: Icons.badge_outlined,
                title: 'Ad Soyad',
                value: fullName,
              ),
              const _CardDivider(),
              _ProfileInfoRow(
                icon: Icons.mail_outline_rounded,
                title: 'E-posta',
                value: email,
              ),
              const _CardDivider(),
              _ProfileInfoRow(
                icon: Icons.phone_outlined,
                title: 'Telefon',
                value: phone,
              ),
              const _CardDivider(),
              _ProfileInfoRow(
                icon: Icons.wc_rounded,
                title: 'Cinsiyet',
                value: gender,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Spor ve Paket Bilgileri',
            icon: Icons.sports_rounded,
          ),
          const SizedBox(height: 12),
          _ProfileInfoCard(
            children: [
              _ProfileInfoRow(
                icon: _getSportIcon(dashboard.sportName),
                title: 'Branş',
                value: dashboard.sportName,
              ),
              const _CardDivider(),
              _ProfileInfoRow(
                icon: Icons.inventory_2_outlined,
                title: 'Paket',
                value: dashboard.packageName,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Ders Özeti',
            icon: Icons.insights_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LessonStatCard(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Toplam',
                  value: dashboard.totalLessons.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LessonStatCard(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Kullanılan',
                  value: dashboard.usedLessons.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LessonStatCard(
                  icon: Icons.event_available_rounded,
                  title: 'Kalan',
                  value: dashboard.remainingLessons.toString(),
                ),
              ),
            ],
          ),
          if (dashboard.hasPackage) ...[
            const SizedBox(height: 16),
            _PackageProgressCard(dashboard: dashboard),
          ],
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StudentEditProfileScreen(dashboard: dashboard),
                  ),
                );

                if (!context.mounted) return;

                if (updated == true) {
                  ref.invalidate(currentStudentProvider);
                  ref.invalidate(studentDashboardProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profiliniz güncellendi.')),
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text(
                'Profili Düzenle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _displayValue(String? value, String fallback) {
    final trimmedValue = value?.trim() ?? '';
    return trimmedValue.isEmpty ? fallback : trimmedValue;
  }

  static String _genderLabel(String value) => switch (value) {
    'female' => 'Kadın',
    'male' => 'Erkek',
    'unspecified' => 'Belirtmek istemiyorum',
    _ => 'Belirtilmedi',
  };

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
}

class _ProfileHeader extends StatelessWidget {
  final String fullName;
  final String sportName;
  final String packageName;

  const _ProfileHeader({
    required this.fullName,
    required this.sportName,
    required this.packageName,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = fullName.trim().isEmpty ? 'Sporcu' : fullName.trim();
    final initials = _getInitials(displayName);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${sportName.trim()} • ${packageName.trim()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
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

  static String _getInitials(String fullName) {
    final words = fullName
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return 'BH';
    }

    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }

    return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'
        .toUpperCase();
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

class _ProfileInfoCard extends StatelessWidget {
  final List<Widget> children;

  const _ProfileInfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 76,
      endIndent: 18,
      color: AppColors.border,
    );
  }
}

class _LessonStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _LessonStatCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageProgressCard extends StatelessWidget {
  final StudentDashboardModel dashboard;

  const _PackageProgressCard({required this.dashboard});

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
                '${dashboard.remainingLessons} ders kaldı',
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
              value: dashboard.usageProgress,
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
                'Kullanılan: ${dashboard.usedLessons}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'Toplam: ${dashboard.totalLessons}',
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
