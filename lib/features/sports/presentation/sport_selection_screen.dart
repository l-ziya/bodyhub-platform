import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sport_provider.dart';

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
        color: isSelected ? Colors.green.shade100 : Colors.white,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            sportCard(
              title: "Tenis",
              subtitle: "Teknik • Taktik • Performans",
              icon: Icons.sports_tennis,
              value: "tennis",
            ),
            sportCard(
              title: "Fitness",
              subtitle: "Kas • Güç • Kondisyon",
              icon: Icons.fitness_center,
              value: "fitness",
            ),
            sportCard(
              title: "Atletik Performans",
              subtitle: "Hız • Çeviklik • Patlayıcı Güç",
              icon: Icons.directions_run,
              value: "athletic",
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: selectedSport == null ? null : () {},
                child: const Text("Devam Et"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}