import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../student/presentation/student_home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-posta ve şifre alanlarını doldurun.'),
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const StudentHomeScreen(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Giriş yapılamadı.';

      if (e.code == 'user-not-found') {
        message = 'Bu e-posta ile kayıtlı kullanıcı bulunamadı.';
      } else if (e.code == 'wrong-password') {
        message = 'Şifre hatalı.';
      } else if (e.code == 'invalid-credential') {
        message = 'E-posta veya şifre hatalı.';
      } else if (e.code == 'invalid-email') {
        message = 'Geçerli bir e-posta adresi girin.';
      } else if (e.code == 'user-disabled') {
        message = 'Bu hesap devre dışı bırakılmış.';
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Beklenmeyen bir hata oluştu: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              Image.asset(
                'assets/images/body_hub_logo.png',
                height: 190,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 18),

              const Text(
                'Giriş Yap',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'BODY HUB hesabınla devam et',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 32),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'E-posta',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 18),

              TextField(
                controller: passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!isLoading) {
                    login();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed: isLoading ? null : login,
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Giriş Yap',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                child: const Text(
                  'Hesabın yok mu? Kayıt Ol',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}