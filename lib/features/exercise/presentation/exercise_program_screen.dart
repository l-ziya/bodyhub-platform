import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ExerciseProgramScreen extends StatelessWidget {
  const ExerciseProgramScreen({super.key, required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Egzersiz Programım')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('exercise_programs')
              .where('studentId', isEqualTo: studentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Egzersiz programı yüklenemedi.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final programs = snapshot.data!.docs.toList()
              ..sort((first, second) {
                final firstDate = (first.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                final secondDate = (second.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
                return secondDate.compareTo(firstDate);
              });
            if (programs.isEmpty) return const _NoExerciseProgram();
            return _ExerciseProgramContent(program: programs.first.data());
          },
        ),
      );
}

class _NoExerciseProgram extends StatelessWidget {
  const _NoExerciseProgram();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text('Henüz egzersiz programın yok.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Coach’un program oluşturduğunda burada görüntülenecek.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _ExerciseProgramContent extends StatelessWidget {
  const _ExerciseProgramContent({required this.program});

  final Map<String, dynamic> program;

  String _value(String key, {String fallback = '-'}) => program[key]?.toString() ?? fallback;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.fitness_center_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(_value('title', fallback: 'Kişisel Egzersiz Programı'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Haftalık Program', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_value('weeklyPlan', fallback: 'Program detayı eklenmedi.'), style: const TextStyle(height: 1.5)))),
          const SizedBox(height: 16),
          Text('Coach Notu', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_value('notes', fallback: 'Bu program için henüz not eklenmedi.')))),
        ],
      );
}
