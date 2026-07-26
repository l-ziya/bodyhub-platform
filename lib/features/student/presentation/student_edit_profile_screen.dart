import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/models/student_dashboard_model.dart';
import '../../students/providers/current_student_provider.dart';
import '../../students/providers/student_profile_provider.dart';

class StudentEditProfileScreen extends ConsumerStatefulWidget {
  final StudentDashboardModel dashboard;

  const StudentEditProfileScreen({super.key, required this.dashboard});

  @override
  ConsumerState<StudentEditProfileScreen> createState() =>
      _StudentEditProfileScreenState();
}

class _StudentEditProfileScreenState
    extends ConsumerState<StudentEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late String _gender;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final profile = ref.read(currentStudentProvider).value;

    _nameController = TextEditingController(
      text: profile?.fullName ?? widget.dashboard.fullName,
    );
    final user = FirebaseAuth.instance.currentUser;
    _phoneController = TextEditingController(
      text: profile?.phone ?? user?.phoneNumber ?? '',
    );
    _emailController = TextEditingController(
      text: profile?.email ?? user?.email ?? '',
    );
    _gender = profile?.gender ?? widget.dashboard.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      await ref
          .read(studentProfileRepositoryProvider)
          .updateProfile(
            uid: user.uid,
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            gender: _gender,
          );

      ref.invalidate(currentStudentProvider);

      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profili Düzenle')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Ad Soyad gerekli' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (v) => v == null || !v.contains('@')
                  ? 'Geçerli e-posta girin'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _gender.isEmpty ? null : _gender,
              decoration: const InputDecoration(
                labelText: 'Cinsiyet',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              hint: const Text('Seçim yapın'),
              items: const [
                DropdownMenuItem(value: 'female', child: Text('Kadın')),
                DropdownMenuItem(value: 'male', child: Text('Erkek')),
                DropdownMenuItem(
                  value: 'unspecified',
                  child: Text('Belirtmek istemiyorum'),
                ),
              ],
              onChanged: (value) => setState(() => _gender = value ?? ''),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
