import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student_dashboard_model.dart';

class DashboardRepository {
  DashboardRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _studentProfiles {
    return _firestore.collection('student_profiles');
  }

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> get _sports {
    return _firestore.collection('sports');
  }

  CollectionReference<Map<String, dynamic>> get _packages {
    return _firestore.collection('packages');
  }

  CollectionReference<Map<String, dynamic>> get _studentPackages {
    return _firestore.collection('student_packages');
  }

  CollectionReference<Map<String, dynamic>> get _lessons {
    return _firestore.collection('lessons');
  }

  Future<StudentDashboardModel> getStudentDashboard(
    String studentId,
  ) async {
    /*
     * İsim student_profiles belgesinden bağımsız olarak
     * users koleksiyonundan okunur.
     */
    final fullName = await _getStudentFullName(
      studentId: studentId,
      profileData: const <String, dynamic>{},
    );

    final profileDocument = await _findStudentProfile(studentId);

    /*
     * Öğrenci profili silinmişse isim yine gösterilir.
     * Branş ve paket bilgileri varsayılan değerlerle döner.
     */
    if (profileDocument == null || !profileDocument.exists) {
      return StudentDashboardModel(
        studentId: studentId,
        fullName: fullName,
        sportName: 'Branş seçilmedi',
        packageName: 'Paket seçilmedi',
        totalLessons: 0,
        usedLessons: 0,
        remainingLessons: 0,
        nextLessonDate: null,
        nextLessonBranch: null,
        nextLessonLocation: null,
      );
    }

    final profileData =
        profileDocument.data() ?? const <String, dynamic>{};

    /*
     * Profil belgesinde isim varsa öncelikli olarak onu,
     * yoksa users koleksiyonundaki ismi kullanır.
     */
    final resolvedFullName = await _getStudentFullName(
      studentId: studentId,
      profileData: profileData,
    );

    final sportId = _readString(
      profileData,
      const [
        'sportId',
        'selectedSportId',
        'branchId',
      ],
    );

    final profileSportName = _readString(
      profileData,
      const [
        'sportName',
        'selectedSportName',
        'branchName',
        'sport',
        'branch',
      ],
    );

    final packageId = _readString(
      profileData,
      const [
        'packageId',
        'selectedPackageId',
      ],
    );

    final profilePackageName = _readString(
      profileData,
      const [
        'packageName',
        'selectedPackageName',
        'package',
      ],
    );

    final sportName = await _getSportName(
      sportId: sportId,
      fallbackName: profileSportName,
    );

    final packageInformation = await _getPackageInformation(
      studentId: studentId,
      profilePackageId: packageId,
      fallbackPackageName: profilePackageName,
    );

    final nextLessonInformation = await _getNextLesson(
      studentId,
    );

    return StudentDashboardModel(
      studentId: studentId,
      fullName: resolvedFullName,
      sportName: sportName,
      packageName: packageInformation.packageName,
      totalLessons: packageInformation.totalLessons,
      usedLessons: packageInformation.usedLessons,
      remainingLessons: packageInformation.remainingLessons,
      nextLessonDate: nextLessonInformation?.date,
      nextLessonBranch: nextLessonInformation?.branch,
      nextLessonLocation: nextLessonInformation?.location,
    );
  }

  Future<String> _getStudentFullName({
    required String studentId,
    required Map<String, dynamic> profileData,
  }) async {
    final profileName = _readString(
      profileData,
      const [
        'fullName',
        'nameSurname',
        'studentName',
        'displayName',
        'name',
      ],
    );

    if (profileName.isNotEmpty) {
      return profileName;
    }

    /*
     * users belgesinin belge ID'si Firebase Authentication UID ile aynıysa
     * doğrudan belge okunur.
     */
    final directUserDocument = await _users.doc(studentId).get();

    if (directUserDocument.exists) {
      final userData = directUserDocument.data();

      if (userData != null) {
        final fullName = _readFullName(userData);

        if (fullName.isNotEmpty) {
          return fullName;
        }
      }
    }

    /*
     * Belge ID'si farklı oluşturulmuşsa uid alanı üzerinden aranır.
     */
    final uidQuery = await _users
        .where('uid', isEqualTo: studentId)
        .limit(1)
        .get();

    if (uidQuery.docs.isNotEmpty) {
      final fullName = _readFullName(
        uidQuery.docs.first.data(),
      );

      if (fullName.isNotEmpty) {
        return fullName;
      }
    }

    final userIdQuery = await _users
        .where('userId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (userIdQuery.docs.isNotEmpty) {
      final fullName = _readFullName(
        userIdQuery.docs.first.data(),
      );

      if (fullName.isNotEmpty) {
        return fullName;
      }
    }

    return 'Öğrenci';
  }

  String _readFullName(Map<String, dynamic> data) {
    final fullName = _readString(
      data,
      const [
        'fullName',
        'nameSurname',
        'studentName',
        'displayName',
      ],
    );

    if (fullName.isNotEmpty) {
      return fullName;
    }

    final firstName = _readString(
      data,
      const [
        'firstName',
        'name',
      ],
    );

    final lastName = _readString(
      data,
      const [
        'lastName',
        'surname',
      ],
    );

    return '$firstName $lastName'.trim();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findStudentProfile(
    String studentId,
  ) async {
    final directDocument = await _studentProfiles.doc(studentId).get();

    if (directDocument.exists) {
      return directDocument;
    }

    final studentIdQuery = await _studentProfiles
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (studentIdQuery.docs.isNotEmpty) {
      return studentIdQuery.docs.first;
    }

    final userIdQuery = await _studentProfiles
        .where('userId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (userIdQuery.docs.isNotEmpty) {
      return userIdQuery.docs.first;
    }

    final uidQuery = await _studentProfiles
        .where('uid', isEqualTo: studentId)
        .limit(1)
        .get();

    if (uidQuery.docs.isNotEmpty) {
      return uidQuery.docs.first;
    }

    return null;
  }

  Future<String> _getSportName({
    required String sportId,
    required String fallbackName,
  }) async {
    if (sportId.isEmpty) {
      return fallbackName.isEmpty
          ? 'Branş seçilmedi'
          : fallbackName;
    }

    final sportDocument = await _sports.doc(sportId).get();

    if (!sportDocument.exists) {
      return fallbackName.isEmpty
          ? 'Branş seçilmedi'
          : fallbackName;
    }

    final data = sportDocument.data();

    if (data == null) {
      return fallbackName.isEmpty
          ? 'Branş seçilmedi'
          : fallbackName;
    }

    return _readString(
      data,
      const [
        'name',
        'sportName',
        'title',
        'branchName',
      ],
      fallback: fallbackName.isEmpty
          ? 'Branş seçilmedi'
          : fallbackName,
    );
  }

  Future<_PackageInformation> _getPackageInformation({
    required String studentId,
    required String profilePackageId,
    required String fallbackPackageName,
  }) async {
    final studentPackage = await _findStudentPackage(studentId);

    if (studentPackage != null && studentPackage.exists) {
      final studentPackageData = studentPackage.data();

      if (studentPackageData != null) {
        final studentPackageId = _readString(
          studentPackageData,
          const [
            'packageId',
            'selectedPackageId',
          ],
          fallback: profilePackageId,
        );

        final packageNameFromStudentPackage = _readString(
          studentPackageData,
          const [
            'packageName',
            'selectedPackageName',
          ],
          fallback: fallbackPackageName,
        );

        final totalLessons = _readInt(
          studentPackageData,
          const [
            'totalLessons',
            'lessonCount',
            'totalLessonCount',
          ],
        );

        final usedLessons = _readInt(
          studentPackageData,
          const [
            'usedLessons',
            'usedLessonCount',
            'completedLessons',
          ],
        );

        final storedRemainingLessons = _readNullableInt(
          studentPackageData,
          const [
            'remainingLessons',
            'remainingLessonCount',
          ],
        );

        final packageName = await _getPackageName(
          packageId: studentPackageId,
          fallbackName: packageNameFromStudentPackage,
        );

        final packageTotalLessons = totalLessons > 0
            ? totalLessons
            : await _getPackageTotalLessons(studentPackageId);

        final calculatedRemaining =
            (packageTotalLessons - usedLessons)
                .clamp(0, packageTotalLessons)
                .toInt();

        return _PackageInformation(
          packageName: packageName,
          totalLessons: packageTotalLessons,
          usedLessons: usedLessons,
          remainingLessons:
              storedRemainingLessons ?? calculatedRemaining,
        );
      }
    }

    final packageName = await _getPackageName(
      packageId: profilePackageId,
      fallbackName: fallbackPackageName,
    );

    final totalLessons = await _getPackageTotalLessons(
      profilePackageId,
    );

    return _PackageInformation(
      packageName: packageName,
      totalLessons: totalLessons,
      usedLessons: 0,
      remainingLessons: totalLessons,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findStudentPackage(
    String studentId,
  ) async {
    final directDocument = await _studentPackages.doc(studentId).get();

    if (directDocument.exists) {
      return directDocument;
    }

    final studentIdQuery = await _studentPackages
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (studentIdQuery.docs.isNotEmpty) {
      return studentIdQuery.docs.first;
    }

    final userIdQuery = await _studentPackages
        .where('userId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (userIdQuery.docs.isNotEmpty) {
      return userIdQuery.docs.first;
    }

    final uidQuery = await _studentPackages
        .where('uid', isEqualTo: studentId)
        .limit(1)
        .get();

    if (uidQuery.docs.isNotEmpty) {
      return uidQuery.docs.first;
    }

    return null;
  }

  Future<String> _getPackageName({
    required String packageId,
    required String fallbackName,
  }) async {
    if (packageId.isEmpty) {
      return fallbackName.isEmpty
          ? 'Paket seçilmedi'
          : fallbackName;
    }

    final packageDocument = await _packages.doc(packageId).get();

    if (!packageDocument.exists) {
      return fallbackName.isEmpty
          ? 'Paket seçilmedi'
          : fallbackName;
    }

    final data = packageDocument.data();

    if (data == null) {
      return fallbackName.isEmpty
          ? 'Paket seçilmedi'
          : fallbackName;
    }

    return _readString(
      data,
      const [
        'name',
        'packageName',
        'title',
      ],
      fallback: fallbackName.isEmpty
          ? 'Paket seçilmedi'
          : fallbackName,
    );
  }

  Future<int> _getPackageTotalLessons(String packageId) async {
    if (packageId.isEmpty) {
      return 0;
    }

    final packageDocument = await _packages.doc(packageId).get();

    if (!packageDocument.exists) {
      return 0;
    }

    final data = packageDocument.data();

    if (data == null) {
      return 0;
    }

    return _readInt(
      data,
      const [
        'totalLessons',
        'lessonCount',
        'totalLessonCount',
        'maxLessons',
      ],
    );
  }

  Future<_NextLessonInformation?> _getNextLesson(
    String studentId,
  ) async {
    final now = Timestamp.fromDate(DateTime.now());

    try {
      final snapshot = await _lessons
          .where('studentId', isEqualTo: studentId)
          .where('lessonDate', isGreaterThanOrEqualTo: now)
          .orderBy('lessonDate')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return _mapNextLesson(
        snapshot.docs.first.data(),
      );
    } catch (_) {
      /*
       * Lessons koleksiyonu veya gerekli Firestore index'i
       * henüz yoksa Dashboard açılmaya devam eder.
       */
      return null;
    }
  }

  _NextLessonInformation? _mapNextLesson(
    Map<String, dynamic> data,
  ) {
    final date = _readDateTime(
      data,
      const [
        'lessonDate',
        'startDate',
        'startTime',
        'date',
      ],
    );

    if (date == null) {
      return null;
    }

    return _NextLessonInformation(
      date: date,
      branch: _readString(
        data,
        const [
          'sportName',
          'branchName',
          'branch',
        ],
      ),
      location: _readString(
        data,
        const [
          'location',
          'court',
          'place',
        ],
      ),
    );
  }

  String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return fallback;
  }

  int _readInt(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    return _readNullableInt(data, keys) ?? 0;
  }

  int? _readNullableInt(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value is String) {
        final parsedValue = int.tryParse(value);

        if (parsedValue != null) {
          return parsedValue;
        }
      }
    }

    return null;
  }

  DateTime? _readDateTime(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String) {
        final parsedValue = DateTime.tryParse(value);

        if (parsedValue != null) {
          return parsedValue;
        }
      }
    }

    return null;
  }
}

class _PackageInformation {
  final String packageName;
  final int totalLessons;
  final int usedLessons;
  final int remainingLessons;

  const _PackageInformation({
    required this.packageName,
    required this.totalLessons,
    required this.usedLessons,
    required this.remainingLessons,
  });
}

class _NextLessonInformation {
  final DateTime date;
  final String branch;
  final String location;

  const _NextLessonInformation({
    required this.date,
    required this.branch,
    required this.location,
  });
}