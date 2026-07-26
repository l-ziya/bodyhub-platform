import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ignore_for_file: curly_braces_in_flow_control_structures

import '../../../core/theme/app_colors.dart';
import '../../availability/models/availability_model.dart';
import '../../availability/providers/availability_provider.dart';
import '../../dashboard/models/student_dashboard_model.dart';
import '../models/booking_model.dart';
import '../providers/booking_provider.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.dashboard});

  final StudentDashboardModel dashboard;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  final _notesController = TextEditingController();
  late DateTime _selectedDate;
  bool _isSubmitting = false;

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

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  AvailabilityModel? _availabilityForDate(
    List<AvailabilityModel> availabilities,
  ) {
    for (final availability in availabilities) {
      if (availability.active &&
          availability.dayOfWeek == _selectedDate.weekday) {
        return availability;
      }
    }
    return null;
  }

  DateTime? _scheduledAt(AvailabilityModel availability) {
    final parts = availability.startTime.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour,
      minute,
    );
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('tr', 'TR'),
    );
    if (selected != null && mounted) setState(() => _selectedDate = selected);
  }

  Future<void> _submit(AvailabilityModel availability) async {
    if (!widget.dashboard.hasRemainingLessons) {
      _message('Rezervasyon için kullanılabilir dersiniz yok.');
      return;
    }

    final scheduledAt = _scheduledAt(availability);
    if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now())) {
      _message('Lütfen gelecekteki uygun bir gün seçin.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .createBooking(
            studentId: widget.dashboard.studentId,
            sportName: widget.dashboard.sportName,
            packageName: widget.dashboard.packageName,
            scheduledAt: scheduledAt,
            notes: _notesController.text,
          );
      _notesController.clear();
      if (mounted) _message('Rezervasyon talebiniz alındı.');
    } catch (_) {
      if (mounted)
        _message('Rezervasyon oluşturulamadı. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancel(BookingModel booking) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Talebi iptal et'),
        content: const Text(
          'Bu rezervasyon talebini iptal etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('İptal et'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(booking.id);
      if (mounted) _message('Rezervasyon talebiniz iptal edildi.');
    } catch (_) {
      if (mounted) _message('Talep iptal edilemedi. Lütfen tekrar deneyin.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final availabilityAsync = ref.watch(
      studentAvailabilitiesProvider(widget.dashboard.studentId),
    );
    final availability = _availabilityForDate(
      availabilityAsync.value ?? const <AvailabilityModel>[],
    );
    final bookings = ref.watch(
      studentBookingsProvider(widget.dashboard.studentId),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ders Rezervasyonu')),
      body: SafeArea(
        child: Column(
          children: [
            _BookingForm(
              date: _selectedDate,
              availability: availability,
              isLoading: availabilityAsync.isLoading,
              hasRemainingLessons: widget.dashboard.hasRemainingLessons,
              remainingLessons: widget.dashboard.remainingLessons,
              notesController: _notesController,
              isSubmitting: _isSubmitting,
              onDateTap: _selectDate,
              onSubmit: availability == null
                  ? null
                  : () => _submit(availability),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Rezervasyon Taleplerim',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: bookings.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const _BookingsMessage(
                  'Rezervasyon talepleri yüklenemedi.',
                ),
                data: (items) =>
                    _BookingList(bookings: items, onCancel: _cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingForm extends StatelessWidget {
  const _BookingForm({
    required this.date,
    required this.availability,
    required this.isLoading,
    required this.hasRemainingLessons,
    required this.remainingLessons,
    required this.notesController,
    required this.isSubmitting,
    required this.onDateTap,
    required this.onSubmit,
  });

  final DateTime date;
  final AvailabilityModel? availability;
  final bool isLoading;
  final bool hasRemainingLessons;
  final int remainingLessons;
  final TextEditingController notesController;
  final bool isSubmitting;
  final VoidCallback onDateTap;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final time = isLoading
        ? 'Yükleniyor'
        : availability == null
        ? 'Uygunluk yok'
        : '${availability!.startTime} - ${availability!.endTime}';
    final help = !hasRemainingLessons
        ? 'Rezervasyon için kullanılabilir dersiniz bulunmuyor.'
        : availability == null
        ? 'Seçilen gün için kayıtlı uygunluğunuz bulunmuyor.'
        : 'Kalan $remainingLessons dersiniz için uygunluk saatinizde talep oluşturun.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            help,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DetailTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Tarih',
                  value: _dateText(date),
                  onTap: onDateTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailTile(
                  icon: Icons.access_time_rounded,
                  label: 'Uygun saat',
                  value: time,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            maxLength: 250,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Not (isteğe bağlı)',
              alignLabelWithHint: true,
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: isSubmitting || !hasRemainingLessons ? null : onSubmit,
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                isSubmitting ? 'Gönderiliyor...' : 'Rezervasyon talebi oluştur',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceSoft,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BookingList extends StatelessWidget {
  const _BookingList({required this.bookings, required this.onCancel});
  final List<BookingModel> bookings;
  final ValueChanged<BookingModel> onCancel;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty)
      return const _BookingsMessage('Henüz bir rezervasyon talebiniz yok.');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: bookings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _BookingCard(
        booking: bookings[index],
        onCancel: () => onCancel(bookings[index]),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onCancel});
  final BookingModel booking;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = _status(booking.status);
    final date = booking.scheduledAt;
    final time =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.$2, color: status.$3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  time,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                status.$1,
                style: TextStyle(
                  color: status.$3,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (booking.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              booking.notes,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (booking.canBeCancelled)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Talebi iptal et'),
              ),
            ),
        ],
      ),
    );
  }

  static (String, IconData, Color) _status(String value) {
    return switch (value) {
      'confirmed' => (
        'Onaylandı',
        Icons.check_circle_outline_rounded,
        AppColors.success,
      ),
      'cancelled' => (
        'İptal edildi',
        Icons.cancel_outlined,
        AppColors.textSecondary,
      ),
      'rejected' => (
        'Reddedildi',
        Icons.error_outline_rounded,
        AppColors.error,
      ),
      _ => ('Onay bekliyor', Icons.hourglass_top_rounded, AppColors.warning),
    };
  }
}

class _BookingsMessage extends StatelessWidget {
  const _BookingsMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
