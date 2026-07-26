import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/availability_model.dart';
import '../providers/availability_provider.dart';

class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() =>
      _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  final List<String> timeSlots = [
    '08:00 - 09:00',
    '09:00 - 10:00',
    '10:00 - 11:00',
    '11:00 - 12:00',
    '12:00 - 13:00',
    '13:00 - 14:00',
    '14:00 - 15:00',
    '15:00 - 16:00',
    '16:00 - 17:00',
    '17:00 - 18:00',
    '18:00 - 19:00',
    '19:00 - 20:00',
    '20:00 - 21:00',
  ];

  final List<_DayAvailability> days = [
    _DayAvailability(
      dayOfWeek: 1,
      dayName: 'Pazartesi',
    ),
    _DayAvailability(
      dayOfWeek: 2,
      dayName: 'Salı',
    ),
    _DayAvailability(
      dayOfWeek: 3,
      dayName: 'Çarşamba',
    ),
    _DayAvailability(
      dayOfWeek: 4,
      dayName: 'Perşembe',
    ),
    _DayAvailability(
      dayOfWeek: 5,
      dayName: 'Cuma',
    ),
    _DayAvailability(
      dayOfWeek: 6,
      dayName: 'Cumartesi',
    ),
    _DayAvailability(
      dayOfWeek: 7,
      dayName: 'Pazar',
    ),
  ];

  bool isLoading = true;
  bool isSaving = false;
  bool hasExistingData = false;

  @override
  void initState() {
    super.initState();
    loadAvailabilities();
  }

  Future<void> loadAvailabilities() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      return;
    }

    try {
      final repository = ref.read(
        availabilityRepositoryProvider,
      );

      final savedAvailabilities =
          await repository.getStudentAvailabilities(
        user.uid,
      );

      for (final saved in savedAvailabilities) {
        final dayIndex = days.indexWhere(
          (day) => day.dayOfWeek == saved.dayOfWeek,
        );

        if (dayIndex == -1) {
          continue;
        }

        final savedTimeSlot =
            '${saved.startTime} - ${saved.endTime}';

        if (timeSlots.contains(savedTimeSlot)) {
          days[dayIndex].selectedTimeSlot = savedTimeSlot;
        }
      }

      if (!mounted) return;

      setState(() {
        hasExistingData = savedAvailabilities.isNotEmpty;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Uygunluk bilgileri yüklenemedi: $error',
          ),
        ),
      );
    }
  }

  Future<void> saveAvailabilities() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kullanıcı oturumu bulunamadı.',
          ),
        ),
      );
      return;
    }

    final selectedDays = days
        .where(
          (day) => day.selectedTimeSlot != null,
        )
        .toList();

    if (selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'En az bir gün ve saat aralığı seçmelisin.',
          ),
        ),
      );
      return;
    }

    final wasExistingData = hasExistingData;

    setState(() {
      isSaving = true;
    });

    try {
      final repository = ref.read(
        availabilityRepositoryProvider,
      );

      final availabilities = selectedDays.map((day) {
        final timeSlot = day.selectedTimeSlot!;
        final times = timeSlot.split(' - ');

        return AvailabilityModel(
          id: '',
          studentId: user.uid,
          dayOfWeek: day.dayOfWeek,
          dayName: day.dayName,
          startTime: times[0],
          endTime: times[1],
          active: true,
          createdAt: DateTime.now(),
        );
      }).toList();

      await repository.replaceStudentAvailabilities(
        studentId: user.uid,
        availabilities: availabilities,
      );

      if (!mounted) return;

      setState(() {
        hasExistingData = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasExistingData
                ? 'Uygunluk bilgilerin güncellendi.'
                : 'Uygunluk bilgilerin kaydedildi.',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kayıt sırasında hata oluştu: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Uygun Olduğum Günler',
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      4,
                    ),
                    child: Text(
                      'Her gün için yalnızca bir saat aralığı seçebilirsin.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: days.length,
                      separatorBuilder: (
                        context,
                        index,
                      ) {
                        return const SizedBox(
                          height: 12,
                        );
                      },
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final day = days[index];

                        return Card(
                          child: ExpansionTile(
                            leading: Icon(
                              day.selectedTimeSlot == null
                                  ? Icons
                                      .calendar_today_outlined
                                  : Icons.check_circle,
                              color:
                                  day.selectedTimeSlot == null
                                      ? Colors.grey
                                      : Colors.green,
                            ),
                            title: Text(
                              day.dayName,
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              day.selectedTimeSlot ??
                                  'Saat seçilmedi',
                            ),
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                child: Column(
                                  children: [
                                    RadioGroup<String?>(
                                      groupValue:
                                          day.selectedTimeSlot,
                                      onChanged: (value) {
                                        setState(() {
                                          day.selectedTimeSlot =
                                              value;
                                        });
                                      },
                                      child: Column(
                                        children:
                                            timeSlots.map(
                                          (timeSlot) {
                                            return RadioListTile<
                                                String?>(
                                              contentPadding:
                                                  EdgeInsets
                                                      .zero,
                                              title: Text(
                                                timeSlot,
                                              ),
                                              value: timeSlot,
                                            );
                                          },
                                        ).toList(),
                                      ),
                                    ),
                                    if (day.selectedTimeSlot !=
                                        null)
                                      Align(
                                        alignment:
                                            Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              day.selectedTimeSlot =
                                                  null;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.close,
                                          ),
                                          label: const Text(
                                            'Seçimi kaldır',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : saveAvailabilities,
                        child: isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                hasExistingData
                                    ? 'Güncelle'
                                    : 'Kaydet',
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DayAvailability {
  final int dayOfWeek;
  final String dayName;
  String? selectedTimeSlot;

  _DayAvailability({
    required this.dayOfWeek,
    required this.dayName,
  });
}