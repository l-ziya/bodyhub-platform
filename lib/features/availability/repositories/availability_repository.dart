import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/availability_model.dart';

class AvailabilityRepository {
  AvailabilityRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection {
    return _firestore.collection('availabilities');
  }

  /// Öğrencinin uygunluklarını bir kez getirir.
  Future<List<AvailabilityModel>> getStudentAvailabilities(
    String studentId,
  ) async {
    final snapshot = await _collection
        .where('studentId', isEqualTo: studentId)
        .get();

    final availabilities = snapshot.docs
        .map(AvailabilityModel.fromFirestore)
        .toList();

    availabilities.sort(
      (first, second) => first.dayOfWeek.compareTo(second.dayOfWeek),
    );

    return availabilities;
  }

  /// Öğrencinin uygunluklarını canlı olarak takip eder.
  Stream<List<AvailabilityModel>> watchStudentAvailabilities(String studentId) {
    return _collection.where('studentId', isEqualTo: studentId).snapshots().map(
      (snapshot) {
        final availabilities = snapshot.docs
            .map(AvailabilityModel.fromFirestore)
            .toList();

        availabilities.sort(
          (first, second) => first.dayOfWeek.compareTo(second.dayOfWeek),
        );

        return availabilities;
      },
    );
  }

  /// Eski uygunlukları kaldırır ve yeni seçimleri kaydeder.
  ///
  /// Böylece Kaydet butonuna tekrar basıldığında aynı kayıtlar çoğalmaz.
  Future<void> replaceStudentAvailabilities({
    required String studentId,
    required List<AvailabilityModel> availabilities,
  }) async {
    _validateAvailabilities(
      studentId: studentId,
      availabilities: availabilities,
    );

    final results = await Future.wait([
      _firestore.collection('student_profiles').doc(studentId).get(),
      _collection.where('studentId', isEqualTo: studentId).get(),
    ]);
    final profile = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final oldSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    if (!profile.exists) {
      throw StateError('Öğrenci profili bulunamadı.');
    }
    final profileData = profile.data() ?? const <String, dynamic>{};
    final coachId = profileData['coachId'] as String? ?? '';
    if (profileData['status'] != 'active' || coachId.trim().isEmpty) {
      throw StateError('Uygunluk kaydı için aktif bir koç ataması gerekli.');
    }

    final batch = _firestore.batch();

    // Öğrencinin önceki uygunluklarını sil.
    for (final document in oldSnapshot.docs) {
      batch.delete(document.reference);
    }

    // Yeni uygunlukları, gün başına tek belge olacak şekilde kaydet.
    for (final availability in availabilities) {
      final documentId = '${availability.studentId}_${availability.dayOfWeek}';

      final documentReference = _collection.doc(documentId);

      batch.set(documentReference, {
        ...availability.toFirestore(),
        'coachId': coachId,
      });
    }

    await batch.commit();
  }

  void _validateAvailabilities({
    required String studentId,
    required List<AvailabilityModel> availabilities,
  }) {
    if (studentId.trim().isEmpty) {
      throw ArgumentError.value(studentId, 'studentId', 'Boş olamaz.');
    }

    final days = <int>{};
    for (final availability in availabilities) {
      if (availability.studentId != studentId) {
        throw ArgumentError('Her uygunluk kaydı aynı öğrenciye ait olmalı.');
      }

      if (availability.dayOfWeek < DateTime.monday ||
          availability.dayOfWeek > DateTime.sunday ||
          !days.add(availability.dayOfWeek)) {
        throw ArgumentError(
          'Her gün için yalnızca bir uygunluk kaydı olabilir.',
        );
      }

      final start = _timeInMinutes(availability.startTime);
      final end = _timeInMinutes(availability.endTime);
      if (start == null || end == null || start >= end) {
        throw ArgumentError('Geçerli bir başlangıç ve bitiş saati seçilmeli.');
      }
    }
  }

  int? _timeInMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }

    return hour * 60 + minute;
  }

  Future<void> deleteAvailability(String id) async {
    await _collection.doc(id).delete();
  }

  Future<void> deleteStudentAvailabilities(String studentId) async {
    final snapshot = await _collection
        .where('studentId', isEqualTo: studentId)
        .get();

    final batch = _firestore.batch();

    for (final document in snapshot.docs) {
      batch.delete(document.reference);
    }

    await batch.commit();
  }
}
