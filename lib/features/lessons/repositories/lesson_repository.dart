import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/lesson_model.dart';

class LessonRepository {
  LessonRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _lessons =>
      _firestore.collection('lessons');

  Future<List<LessonModel>> getUpcomingLessons(String studentId) async {
    _validateStudentId(studentId);

    final now = Timestamp.fromDate(DateTime.now());

    try {
      debugPrint('Yaklaşan ders sorgusu başladı. studentId: $studentId');

      final snapshot = await _lessons
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'scheduled')
          .where('startTime', isGreaterThanOrEqualTo: now)
          .orderBy('startTime')
          .get()
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Yaklaşan ders sorgusu tamamlandı. Kayıt: ${snapshot.docs.length}',
      );

      return snapshot.docs
          .map(LessonModel.fromFirestore)
          .toList(growable: false);
    } on TimeoutException {
      throw Exception(
        'Firestore yanıt vermedi. İnternet bağlantısını ve Firebase '
        'yapılandırmasını kontrol et.',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Yaklaşan ders Firestore hatası: '
        '${error.code} - ${error.message}\n$stackTrace',
      );

      throw Exception(_firebaseErrorMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Yaklaşan ders beklenmeyen hata: $error\n$stackTrace');
      rethrow;
    }
  }

  Stream<List<LessonModel>> watchUpcomingLessons(String studentId) {
    _validateStudentId(studentId);

    return _lessons
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'scheduled')
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()),
        )
        .orderBy('startTime')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(LessonModel.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<List<LessonModel>> getPastLessons(String studentId) async {
    _validateStudentId(studentId);

    final now = Timestamp.fromDate(DateTime.now());

    try {
      debugPrint('Geçmiş ders sorgusu başladı. studentId: $studentId');

      final snapshot = await _lessons
          .where('studentId', isEqualTo: studentId)
          .where('startTime', isLessThan: now)
          .orderBy('startTime', descending: true)
          .get()
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Geçmiş ders sorgusu tamamlandı. Kayıt: ${snapshot.docs.length}',
      );

      return snapshot.docs
          .map(LessonModel.fromFirestore)
          .toList(growable: false);
    } on TimeoutException {
      throw Exception(
        'Firestore yanıt vermedi. İnternet bağlantısını ve Firebase '
        'yapılandırmasını kontrol et.',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Geçmiş ders Firestore hatası: '
        '${error.code} - ${error.message}\n$stackTrace',
      );

      throw Exception(_firebaseErrorMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Geçmiş ders beklenmeyen hata: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<LessonModel?> getLesson(String lessonId) async {
    if (lessonId.trim().isEmpty) {
      throw ArgumentError('lessonId boş olamaz.');
    }

    try {
      final document = await _lessons
          .doc(lessonId)
          .get()
          .timeout(const Duration(seconds: 15));

      if (!document.exists) {
        return null;
      }

      return LessonModel.fromFirestore(document);
    } on TimeoutException {
      throw Exception('Ders bilgisi alınırken Firestore zaman aşımına uğradı.');
    } on FirebaseException catch (error) {
      throw Exception(_firebaseErrorMessage(error));
    }
  }

  Future<void> updateLessonStatus({
    required String lessonId,
    required String status,
  }) async {
    if (lessonId.trim().isEmpty) {
      throw ArgumentError('lessonId boş olamaz.');
    }

    await _lessons.doc(lessonId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAttendance({
    required String lessonId,
    required String attendanceStatus,
  }) async {
    if (lessonId.trim().isEmpty) {
      throw ArgumentError('lessonId boş olamaz.');
    }

    await _lessons.doc(lessonId).update({
      'attendanceStatus': attendanceStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _validateStudentId(String studentId) {
    if (studentId.trim().isEmpty) {
      throw ArgumentError(
        'studentId boş geldi. Dersler ekranına geçerken öğrenci kimliği '
        'gönderilmelidir.',
      );
    }
  }

  String _firebaseErrorMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firestore erişim izni reddedildi. Security Rules kontrol edilmeli.';
      case 'failed-precondition':
        return 'Bu sorgu için Firestore index gerekiyor. Terminalde verilen '
            'index bağlantısını açıp index oluştur.';
      case 'unavailable':
        return 'Firestore servisine ulaşılamıyor. İnternet bağlantısını kontrol et.';
      default:
        return 'Firestore hatası: ${error.code} - '
            '${error.message ?? 'Bilinmeyen hata'}';
    }
  }
}
