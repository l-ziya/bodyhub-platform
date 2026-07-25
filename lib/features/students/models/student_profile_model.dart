class StudentProfileModel {
  final String uid;
  final String fullName;
  final String phone;
  final String email;
  final String sportId;
  final String packageId;
  final String status;

  const StudentProfileModel({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.sportId,
    required this.packageId,
    required this.status,
  });

  factory StudentProfileModel.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) {
    return StudentProfileModel(
      uid: uid,
      fullName: data['fullName'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      sportId: data['sportId'] ?? '',
      packageId: data['packageId'] ?? '',
      status: data['status'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'sportId': sportId,
      'packageId': packageId,
      'status': status,
    };
  }
}