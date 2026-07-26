import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class WelcomeCard extends StatelessWidget {
  final String studentName;
  final String studentId;
  final String gender;
  final VoidCallback onNutritionTap;
  final VoidCallback onExerciseTap;
  final String? subtitle;

  const WelcomeCard({
    super.key,
    required this.studentName,
    required this.studentId,
    required this.gender,
    required this.onNutritionTap,
    required this.onExerciseTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isFemale = gender.trim().toLowerCase() == 'female';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isFemale
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFB84E75), Color(0xFFE195AC)],
              )
            : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -35,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 25,
            bottom: -45,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.fitness_center_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Merhaba,',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle ??
                              'Bugün kendini geliştirmek için harika bir gün.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'BUGÜNÜN MİNİ HEDEFLERİ',
                style: TextStyle(
                  color: Color(0xFFDBF4FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: _PlanMiniGoal(
                      studentId: studentId,
                      collection: 'nutrition_plans',
                      icon: Icons.restaurant_menu_rounded,
                      label: 'Beslenme',
                      onTap: onNutritionTap,
                      valueFor: (plan) {
                        final calories = plan['dailyCalories'];
                        return calories == null || calories.toString().isEmpty
                            ? 'Plan bekliyor'
                            : '${calories.toString()} kcal hedef';
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PlanMiniGoal(
                      studentId: studentId,
                      collection: 'exercise_programs',
                      icon: Icons.directions_run_rounded,
                      label: 'Egzersiz',
                      onTap: onExerciseTap,
                      valueFor: (program) {
                        final title = program['title']?.toString().trim() ?? '';
                        return title.isEmpty ? 'Plan hazır' : title;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanMiniGoal extends StatelessWidget {
  const _PlanMiniGoal({
    required this.studentId,
    required this.collection,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.valueFor,
  });

  final String studentId;
  final String collection;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String Function(Map<String, dynamic>) valueFor;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection(collection)
        .where('studentId', isEqualTo: studentId)
        .snapshots(),
    builder: (context, snapshot) {
      final plans = snapshot.data?.docs.toList() ?? []
        ..sort((first, second) {
          final firstDate =
              (first.data()['updatedAt'] as Timestamp?)?.toDate() ??
              DateTime(0);
          final secondDate =
              (second.data()['updatedAt'] as Timestamp?)?.toDate() ??
              DateTime(0);
          return secondDate.compareTo(firstDate);
        });
      final value = plans.isEmpty
          ? 'Plan bekliyor'
          : valueFor(plans.first.data());

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: const Color(0xFFDBF4FF)),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
