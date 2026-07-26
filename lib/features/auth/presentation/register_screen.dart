import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../../student/presentation/student_access_gate.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String _gender = 'unspecified';

  @override
  void dispose() {
    fullNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    try {
      await ref
          .read(authRepositoryProvider)
          .register(
            fullName: fullNameController.text.trim(),
            phone: phoneController.text.trim(),
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
            gender: _gender,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Kayıt başarılı!")));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StudentAccessGate()),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Kayıt Ol")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: fullNameController,
              decoration: const InputDecoration(labelText: "Ad Soyad"),
            ),
            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(
                labelText: 'Cinsiyet',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'female', child: Text('Kadın')),
                DropdownMenuItem(value: 'male', child: Text('Erkek')),
                DropdownMenuItem(
                  value: 'unspecified',
                  child: Text('Belirtmek istemiyorum'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _gender = value);
              },
            ),
            const SizedBox(height: 15),

            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Telefon"),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "E-posta"),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Şifre"),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _register,
                child: const Text("Kayıt Ol"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
