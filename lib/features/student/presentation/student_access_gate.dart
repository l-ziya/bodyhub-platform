import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/login_screen.dart';
import '../../students/providers/current_student_provider.dart';
import 'student_home_screen.dart';

class StudentAccessGate extends ConsumerWidget {
  const StudentAccessGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentStudentStreamProvider);

    return profileAsync.when(
      loading: () => const _AccessLoadingScreen(),
      error: (_, _) => _ApprovalStatusScreen(
        title: 'Profil bilgisi yüklenemedi',
        description: 'Lütfen bağlantınızı kontrol edip tekrar deneyin.',
        icon: Icons.error_outline_rounded,
      ),
      data: (profile) {
        if (profile?.status == 'active') return const StudentHomeScreen();

        final isRejected = profile?.status == 'rejected';
        return _ApprovalStatusScreen(
          title: isRejected ? 'Başvurunuz onaylanmadı' : 'Koç onayı bekleniyor',
          description: isRejected
              ? 'Başvurunuzla ilgili bilgi almak için BODY HUB ile iletişime geçin.'
              : 'Koç onayından sonra paket ve rezervasyon özelliklerini kullanabilirsiniz.',
          icon: isRejected
              ? Icons.highlight_off_rounded
              : Icons.pending_actions_rounded,
        );
      },
    );
  }
}

class _AccessLoadingScreen extends StatelessWidget {
  const _AccessLoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class _ApprovalStatusScreen extends StatelessWidget {
  const _ApprovalStatusScreen({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(description, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Çıkış yap'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
