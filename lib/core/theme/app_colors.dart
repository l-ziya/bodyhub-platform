import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  // BODY HUB ana marka renkleri
  static const Color primary = Color(0xFF079CE5);
  static const Color primaryDark = Color(0xFF0069B4);
  static const Color primaryLight = Color(0xFF4CC9FF);

  // İkincil vurgu renkleri
  static const Color accent = Color(0xFF00C2FF);
  static const Color navy = Color(0xFF082A46);

  // Arka plan renkleri
  static const Color background = Color(0xFFF4F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFEAF5FC);

  // Yazı renkleri
  static const Color textPrimary = Color(0xFF172033);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textLight = Color(0xFFFFFFFF);

  // Kenarlık ve ayırıcılar
  static const Color border = Color(0xFFDCE7F0);
  static const Color divider = Color(0xFFE7EEF5);

  // Durum renkleri
  static const Color success = Color(0xFF22A06B);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFE5484D);
  static const Color info = Color(0xFF2589D8);

  // Devre dışı durumlar
  static const Color disabled = Color(0xFFB8C4D0);
  static const Color disabledBackground = Color(0xFFE7EDF3);

  // Gölgeler
  static const Color shadow = Color(0x1A172033);

  // Ana sayfa üst bölümünde kullanacağımız geçiş
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primaryDark,
      primary,
      primaryLight,
    ],
  );

  // Açık mavi kart geçişi
  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE6F6FF),
      Color(0xFFF8FCFF),
    ],
  );
}