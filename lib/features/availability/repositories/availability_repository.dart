import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/availability_model.dart';

class AvailabilityRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  Stream<List<AvailabilityModel>> watchStudentAvailabilities(
    String studentId,
  ) {
    return _collection
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      final availabilities = snapshot.docs
          .map(AvailabilityModel.fromFirestore)
          .toList();

      availabilities.sort(
        (first, second) => first.dayOfWeek.compareTo(second.dayOfWeek),
      );

      return availabilities;
    });
  }

  /// Eski uygunlukları kaldırır ve yeni seçimleri kaydeder.
  ///
  /// Böylece Kaydet butonuna tekrar basıldığında aynı kayıtlar çoğalmaz.
  Future<void> replaceStudentAvailabilities({
    required String studentId,
    required List<AvailabilityModel> availabilities,
  }) async {
    final oldSnapshot = await _collection
        .where('studentId', isEqualTo: studentId)
        .get();

    final batch = _firestore.batch();

    // Öğrencinin önceki uygunluklarını sil.
    for (final document in oldSnapshot.docs) {
      batch.delete(document.reference);
    }

    // Yeni uygunlukları, gün başına tek belge olacak şekilde kaydet.
    for (final availability in availabilities) {
      final documentId =
          '${availability.studentId}_${availability.dayOfWeek}';

      final documentReference = _collection.doc(documentId);

      batch.set(
        documentReference,
        availability.toFirestore(),
      );
    }

    await batch.commit();
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