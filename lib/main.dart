import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/services/lesson_reminder_service.dart';
import 'firebase_options.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('tr_TR');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LessonReminderService.instance.initialize();

  runApp(const ProviderScope(child: BodyHubApp()));
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
