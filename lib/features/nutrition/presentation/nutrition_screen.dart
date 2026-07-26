import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key, required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Beslenme Planım')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('nutrition_plans')
              .where('studentId', isEqualTo: studentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Beslenme planı yüklenemedi.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final plans = snapshot.data!.docs.toList()
              ..sort((first, second) {
                final firstDate = (first.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                final secondDate = (second.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                return secondDate.compareTo(firstDate);
              });
            if (plans.isEmpty) {
              return const _NoNutritionPlan();
            }
            return _NutritionPlanContent(plan: plans.first.data());
          },
        ),
      );
}

class _NoNutritionPlan extends StatelessWidget {
  const _NoNutritionPlan();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text('Henüz bir beslenme planın yok.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Coach’un plan oluşturduğunda burada görüntülenecek.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _NutritionPlanContent extends StatelessWidget {
  const _NutritionPlanContent({required this.plan});

  final Map<String, dynamic> plan;

  String _value(String key, {String fallback = '-'}) => plan[key]?.toString() ?? fallback;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(Icons.restaurant_rounded, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_value('title', fallback: 'Beslenme Planı'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _MacroCard(label: 'Kalori', value: '${_value('dailyCalories')} kcal', color: Colors.orange),
                      const SizedBox(width: 8),
                      _MacroCard(label: 'Protein', value: '${_value('protein')} g', color: Colors.blue),
                      const SizedBox(width: 8),
                      _MacroCard(label: 'Karbonhidrat', value: '${_value('carbs')} g', color: Colors.green),
                      const SizedBox(width: 8),
                      _MacroCard(label: 'Yağ', value: '${_value('fat')} g', color: Colors.purple),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Coach Notu', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_value('notes', fallback: 'Bu plan için henüz not eklenmedi.')))),
        ],
      );
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
}
