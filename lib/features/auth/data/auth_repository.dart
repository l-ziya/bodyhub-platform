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
  }) async {
    // Firebase Authentication
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Firestore
    await _firestore.collection('users').doc(credential.user!.uid).set({
      'uid': credential.user!.uid,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}