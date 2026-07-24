import 'package:flutter/material.dart';

void main() {
  runApp(const BodyHubApp());
}

class BodyHubApp extends StatelessWidget {
  const BodyHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BODY HUB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          "BODY HUB",
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}