import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String gender,
  }) async {
    // Firebase Authentication
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;
    final batch = _firestore.batch();
    final userData = {
      'uid': uid,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'gender': gender,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };

    batch.set(_firestore.collection('users').doc(uid), userData);
    batch.set(_firestore.collection('student_profiles').doc(uid), userData);
    await batch.commit();
  }
}
