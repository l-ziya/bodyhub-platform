import 'package:bodyhub_domain_contract/bodyhub_domain_contract.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coaches/models/coach_profile_model.dart';
import '../../coaches/providers/coach_discovery_provider.dart';
import '../../sports/models/sport_model.dart';
import '../../sports/providers/sport_provider.dart';
import '../providers/student_booking_request_provider.dart';
import '../providers/student_schedule_slot_discovery_provider.dart';

/// Isolated V2 booking-intent entry point.
///
/// This screen does not replace the V1 booking flow. Sending an intent neither
/// reserves a slot nor creates a Session; D-7 owns any future approval flow.
class V2BookingRequestScreen extends ConsumerStatefulWidget {
  const V2BookingRequestScreen({super.key});

  @override
  ConsumerState<V2BookingRequestScreen> createState() =>
      _V2BookingRequestScreenState();
}

class _V2BookingRequestScreenState
    extends ConsumerState<V2BookingRequestScreen> {
  late DateTime _selectedDate;
  SportModel? _selectedSport;
  CoachProfileModel? _selectedCoach;
  String? _selectedSlotId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
  }

  String get _dayKey => BodyHubSchedulingContract.formatDayKey(_selectedDate);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('tr', 'TR'),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedDate = selected;
        _selectedSlotId = null;
      });
    }
  }

  Future<void> _submit() async {
    final studentId = FirebaseAuth.instance.currentUser?.uid;
    final sport = _selectedSport;
    final coach = _selectedCoach;
    final slotId = _selectedSlotId;
    if (studentId == null || sport == null || coach == null || slotId == null) {
      _showMessage('Lütfen branş, koç, gün ve saat seçin.');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(studentBookingRequestRepositoryProvider)
          .createPendingRequest(
            studentId: studentId,
            coachId: coach.coachId,
            sportId: sport.id,
            dayKey: _dayKey,
            slotId: slotId,
          );
      ref.invalidate(studentBookingRequestsProvider(studentId));
      if (mounted) {
        _showMessage(
          'Talep gönderildi. Henüz onaylanmadı ve ders rezervasyonu oluşmadı.',
        );
        setState(() => _selectedSlotId = null);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Talep gönderilemedi. Lütfen uygunluğu tekrar kontrol edin.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final sports = ref.watch(sportsProvider);
    final studentId = FirebaseAuth.instance.currentUser?.uid;
    final coaches = _selectedSport == null
        ? null
        : ref.watch(discoverableCoachesProvider(_selectedSport!.id));
    final slots = _selectedCoach == null
        ? null
        : ref.watch(
            studentActiveScheduleSlotsProvider(
              StudentScheduleSlotDiscoveryQuery(
                coachId: _selectedCoach!.coachId,
                dayKey: _dayKey,
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Rezervasyon Talebi (V2)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const V2BookingRequestNotice(),
          const SizedBox(height: 16),
          sports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text('Branşlar yüklenemedi: $error'),
            data: (items) => _SportPicker(
              sports: items,
              selected: _selectedSport,
              onChanged: (sport) => setState(() {
                _selectedSport = sport;
                _selectedCoach = null;
                _selectedSlotId = null;
              }),
            ),
          ),
          if (coaches != null) ...[
            const SizedBox(height: 16),
            coaches.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Text('Koçlar yüklenemedi: $error'),
              data: (items) => _CoachPicker(
                coaches: items,
                selected: _selectedCoach,
                onChanged: (coach) => setState(() {
                  _selectedCoach = coach;
                  _selectedSlotId = null;
                }),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Gün: $_dayKey'),
          ),
          if (slots != null) ...[
            const SizedBox(height: 16),
            slots.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  const Text('Uygun saatler yüklenemedi.'),
              data: (items) => _SlotPicker(
                slots: items.map((item) => item.slotId).toList(growable: false),
                selectedSlotId: _selectedSlotId,
                onChanged: (slotId) => setState(() => _selectedSlotId = slotId),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting || _selectedSlotId == null ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Talep gönder'),
          ),
          const SizedBox(height: 28),
          if (studentId != null) _OwnRequests(studentId: studentId),
        ],
      ),
    );
  }
}

/// Explains that a V2 booking request is not yet a confirmed reservation.
class V2BookingRequestNotice extends StatelessWidget {
  const V2BookingRequestNotice({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Koç onayı gerekir',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'Talep gönderildi. Henüz onaylanmadı ve ders rezervasyonu oluşmadı.',
          ),
          SizedBox(height: 6),
          Text('Derslerin uygulama süresi 50 dakikadır.'),
        ],
      ),
    ),
  );
}

class _SportPicker extends StatelessWidget {
  const _SportPicker({
    required this.sports,
    required this.selected,
    required this.onChanged,
  });

  final List<SportModel> sports;
  final SportModel? selected;
  final ValueChanged<SportModel?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: selected?.id,
    decoration: const InputDecoration(labelText: 'Branş'),
    items: sports
        .map(
          (sport) => DropdownMenuItem(value: sport.id, child: Text(sport.name)),
        )
        .toList(growable: false),
    onChanged: (id) => onChanged(_findSport(sports, id)),
  );

  static SportModel? _findSport(List<SportModel> sports, String? id) {
    for (final sport in sports) {
      if (sport.id == id) return sport;
    }
    return null;
  }
}

class _CoachPicker extends StatelessWidget {
  const _CoachPicker({
    required this.coaches,
    required this.selected,
    required this.onChanged,
  });

  final List<CoachProfileModel> coaches;
  final CoachProfileModel? selected;
  final ValueChanged<CoachProfileModel?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: selected?.coachId,
    decoration: const InputDecoration(labelText: 'Koç'),
    items: coaches
        .map(
          (coach) => DropdownMenuItem(
            value: coach.coachId,
            child: Text(coach.displayName),
          ),
        )
        .toList(growable: false),
    onChanged: (id) => onChanged(_findCoach(coaches, id)),
  );

  static CoachProfileModel? _findCoach(
    List<CoachProfileModel> coaches,
    String? id,
  ) {
    for (final coach in coaches) {
      if (coach.coachId == id) return coach;
    }
    return null;
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({
    required this.slots,
    required this.selectedSlotId,
    required this.onChanged,
  });

  final List<String> slots;
  final String? selectedSlotId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const Text('Seçilen gün için açık saat bulunmuyor.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Açık saatler',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slots
              .map(
                (slotId) => ChoiceChip(
                  label: Text(
                    BodyHubSchedulingContract.formatSlotLabel(slotId),
                  ),
                  selected: selectedSlotId == slotId,
                  onSelected: (_) => onChanged(slotId),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _OwnRequests extends ConsumerWidget {
  const _OwnRequests({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(studentBookingRequestsProvider(studentId));
    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Text('Talepler yüklenemedi.'),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Taleplerim', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('Henüz V2 rezervasyon talebiniz yok.')
          else
            ...items.map(
              (request) => Card(
                child: ListTile(
                  title: Text(
                    '${request.sportId} · ${request.dayKey} · ${BodyHubSchedulingContract.formatSlotLabel(request.slotId)}',
                  ),
                  subtitle: Text('Durum: ${request.status.wireName}'),
                  trailing: request.status == BookingRequestStatus.pending
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(studentBookingRequestRepositoryProvider)
                                  .withdrawPendingRequest(
                                    requestId: request.id,
                                    studentId: studentId,
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Talep geri çekildi.'),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Talep geri çekilemedi.'),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Geri çek'),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
