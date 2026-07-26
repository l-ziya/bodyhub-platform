import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/package_provider.dart';
import '../../students/providers/student_profile_provider.dart';
import '../../student/presentation/student_home_screen.dart';

class PackageSelectionScreen extends ConsumerStatefulWidget {
  final String sportId;

  const PackageSelectionScreen({
    super.key,
    required this.sportId,
  });

  @override
  ConsumerState<PackageSelectionScreen> createState() =>
      _PackageSelectionScreenState();
}

class _PackageSelectionScreenState
    extends ConsumerState<PackageSelectionScreen> {
  String? selectedPackage;
  bool isSaving = false;

  Future<void> savePackage() async {
    if (selectedPackage == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Oturum bulunamadı. Lütfen tekrar giriş yapın.",
          ),
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await ref
          .read(studentProfileRepositoryProvider)
          .updateSportAndPackage(
            uid: user.uid,
            sportId: widget.sportId,
            packageId: selectedPackage!,
          );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const StudentHomeScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Kayıt sırasında hata oluştu: $e",
          ),
        ),
      );

      setState(() {
        isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(
      packagesProvider(widget.sportId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paket Seç"),
        centerTitle: true,
      ),
      body: packagesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),

        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              "Paketler yüklenirken hata oluştu:\n$error",
              textAlign: TextAlign.center,
            ),
          ),
        ),

        data: (packages) {
          if (packages.isEmpty) {
            return const Center(
              child: Text(
                "Bu branş için aktif paket bulunamadı.",
                textAlign: TextAlign.center,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  "Paketini Seç",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "İhtiyacına uygun paketi seçerek devam et.",
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 30),

                Expanded(
                  child: ListView.builder(
                    itemCount: packages.length,
                    itemBuilder: (context, index) {
                      final package = packages[index];

                      final isSelected =
                          selectedPackage == package.id;

                      return GestureDetector(
                        onTap: isSaving
                            ? null
                            : () {
                                setState(() {
                                  selectedPackage = package.id;
                                });
                              },

                        child: Card(
                          elevation: isSelected ? 8 : 2,
                          color: isSelected
                              ? Colors.green.shade100
                              : Colors.white,
                          margin: const EdgeInsets.only(
                            bottom: 16,
                          ),

                          child: Padding(
                            padding: const EdgeInsets.all(20),

                            child: Row(
                              children: [
                                Icon(
                                  package.lessonLimit == 10
                                      ? Icons.confirmation_number
                                      : Icons.calendar_month,
                                  color: Colors.green,
                                  size: 45,
                                ),

                                const SizedBox(width: 20),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        package.name,
                                        style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      Text(
                                        "${package.lessonLimit} ders hakkı",
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        "${package.durationDays} gün kullanım süresi",
                                      ),

                                      if (package.weeklyLimit > 0) ...[
                                        const SizedBox(height: 4),

                                        Text(
                                          "Haftada maksimum "
                                          "${package.weeklyLimit} ders",
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 30,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  height: 55,

                  child: ElevatedButton(
                    onPressed:
                        selectedPackage == null || isSaving
                            ? null
                            : savePackage,

                    child: isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Devam Et",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}