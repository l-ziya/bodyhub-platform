import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/services/lesson_reminder_service.dart';
import 'firebase_options.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

bool _showingStartupFailure = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _showStartupFailure(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _showStartupFailure(error, stackTrace);
    return true;
  };

  try {
    await initializeDateFormatting('tr_TR');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await LessonReminderService.instance.initialize();

    runApp(const ProviderScope(child: BodyHubApp()));
  } catch (error, stackTrace) {
    _showStartupFailure(error, stackTrace);
  }
}

void _showStartupFailure(Object error, StackTrace? stackTrace) {
  debugPrint('BODY HUB başlatma hatası: $error');
  debugPrintStack(stackTrace: stackTrace);
  if (_showingStartupFailure) return;
  _showingStartupFailure = true;
  runApp(_StartupFailureApp(message: error.toString()));
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 46,
                      color: Color(0xFF0069B4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'BODY HUB başlatılamadı',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bağlantı hazırlanırken bir sorun oluştu. Sayfayı yenileyin veya kısa süre sonra tekrar deneyin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class BodyHubApp extends StatelessWidget {
  const BodyHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BODY HUB',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
