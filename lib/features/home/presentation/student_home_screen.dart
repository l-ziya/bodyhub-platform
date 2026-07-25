import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../students/providers/current_student_provider.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  String sportName(String sportId) {
    switch (sportId) {
      case 'tennis':
        return 'Tenis';

      case 'fitness':
        return 'Fitness';

      case 'athletic':
        return 'Atletik Performans';

      default:
        return sportId;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("BODY HUB"),
        centerTitle: true,
      ),

      body: studentAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),

        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              "Profil yüklenirken hata oluştu:\n$error",
              textAlign: TextAlign.center,
            ),
          ),
        ),

        data: (student) {
          if (student == null) {
            return const Center(
              child: Text(
                "Öğrenci profili bulunamadı.",
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  "Merhaba, ${student.fullName} 👋",
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  "Antrenmanlarına hazır mısın?",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 30),

                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20),

                    child: Row(
                      children: [
                        const Icon(
                          Icons.sports,
                          size: 50,
                          color: Colors.green,
                        ),

                        const SizedBox(width: 20),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [
                              const Text(
                                "Branşım",
                                style: TextStyle(
                                  color: Colors.grey,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                sportName(student.sportId),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20),

                    child: Row(
                      children: [
                        const Icon(
                          Icons.card_membership,
                          size: 50,
                          color: Colors.green,
                        ),

                        const SizedBox(width: 20),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [
                              const Text(
                                "Paketim",
                                style: TextStyle(
                                  color: Colors.grey,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                student.packageId,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  "Hızlı İşlemler",
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.calendar_month,
                        title: "Derslerim",
                        onTap: () {},
                      ),
                    ),

                    const SizedBox(width: 15),

                    Expanded(
                      child: _ActionCard(
                        icon: Icons.person,
                        title: "Profilim",
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(15),

      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 25,
            horizontal: 10,
          ),

          child: Column(
            children: [
              Icon(
                icon,
                size: 35,
                color: Colors.green,
              ),

              const SizedBox(height: 10),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}