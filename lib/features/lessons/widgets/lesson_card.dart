import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lesson_model.dart';

class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.lesson, this.onTap});

  final LessonModel lesson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children:[
                          CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(_sportIcon(), color: cs.primary),
                          ),
                          const SizedBox(width:12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                              Text(lesson.sportName,style: const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
                              Text(lesson.packageName),
                            ],
                          )),
                          Chip(
                            backgroundColor: _statusColor(),
                            label: Text(_statusText(),style: const TextStyle(color: Colors.white)),
                          )
                        ]),
                        const Divider(height:28),
                        _row(Icons.calendar_month_rounded, DateFormat('dd MMMM yyyy','tr_TR').format(lesson.startTime)),
                        const SizedBox(height:10),
                        _row(Icons.schedule_rounded,'${DateFormat('HH:mm').format(lesson.startTime)} - ${DateFormat('HH:mm').format(lesson.endTime)}'),
                        const SizedBox(height:10),
                        _row(Icons.person_rounded, lesson.coachName),
                        const SizedBox(height:10),
                        _row(Icons.location_on_rounded, lesson.location),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon,String text)=>Row(children:[Icon(icon,size:20),const SizedBox(width:10),Expanded(child:Text(text))]);

  Color _statusColor(){
    switch(lesson.status){
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'makeup': return Colors.orange;
      default: return const Color(0xFF1EA7FF);
    }
  }

  String _statusText(){
    switch(lesson.status){
      case 'completed': return 'Tamamlandı';
      case 'cancelled': return 'İptal';
      case 'makeup': return 'Telafi';
      default: return 'Planlandı';
    }
  }

  IconData _sportIcon(){
    switch(lesson.sportIcon){
      case 'tennis': return Icons.sports_tennis_rounded;
      case 'fitness': return Icons.fitness_center_rounded;
      case 'athletic': return Icons.directions_run_rounded;
      case 'swimming': return Icons.pool_rounded;
      case 'pilates': return Icons.self_improvement_rounded;
      default: return Icons.sports_rounded;
    }
  }
}
