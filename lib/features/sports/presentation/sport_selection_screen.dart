import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sport_provider.dart';
import '../../packages/presentation/package_selection_screen.dart';

class SportSelectionScreen extends ConsumerStatefulWidget {
  const SportSelectionScreen({super.key});

  @override
  ConsumerState<SportSelectionScreen> createState() =>
      _SportSelectionScreenState();
}

class _SportSelectionScreenState
    extends ConsumerState<SportSelectionScreen> {
  String? selectedSport;

  Widget sportCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final isSelected = selectedSport == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSport = value;
        });
      },
      child: Card(
        elevation: isSelected ? 8 : 2,
        color: isSelected
            ? Colors.green.shade100
            : Colors.white,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                icon,
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
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(subtitle),
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
  }

  @override
  Widget build(BuildContext context) {
    final sportsAsync = ref.watch(sportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Branş Seç"),
        centerTitle: true,
      ),

      body: sportsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),

        error: (error, stack) => Center(
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
          ),
        ),

        data: (sports) {
          return Padding(
            padding: const EdgeInsets.all(16),

            child: Column(
              children: [
                const Text(
                  "Branşını Seç",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "Antrenman yapmak istediğin branşı seç.",
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 25),

                Expanded(
                  child: ListView(
                    children: [
                      ...sports.map((sport) {
                        IconData icon = Icons.sports;
                        String subtitle = "";

                        switch (sport.id) {
                          case "tennis":
                            icon = Icons.sports_tennis;
                            subtitle =
                                "Teknik • Taktik • Performans";
                            break;

                          case "fitness":
                            icon = Icons.fitness_center;
                            subtitle =
                                "Kas • Güç • Kondisyon";
                            break;

                          case "athletic":
                            icon = Icons.directions_run;
                            subtitle =
                                "Hız • Çeviklik • Patlayıcı Güç";
                            break;
                        }

                        return sportCard(
                          title: sport.name,
                          subtitle: subtitle,
                          icon: icon,
                          value: sport.id,
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 55,

                  child: ElevatedButton(
                    onPressed: selectedSport == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PackageSelectionScreen(
                                  sportId: selectedSport!,
                                ),
                              ),
                            );
                          },

                    child: const Text(
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