import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary      = Color(0xFFC2185B);
  static const Color primaryLight = Color(0xFFE91E8C);
  static const Color primaryDark  = Color(0xFF880E4F);

  static const Color secondary     = Color(0xFF7B1FA2);
  static const Color secondaryLight= Color(0xFF9C27B0);
  static const Color secondaryDark = Color(0xFF4A148C);

  static const Color accent      = Color(0xFF00897B);
  static const Color accentLight = Color(0xFF4DB6AC);

  static const Color background     = Color(0xFFF7F4F8);
  static const Color surface        = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFFCF8FD);

  static const Color textPrimary   = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF616161);
  static const Color textHint      = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border  = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFF5F5F5);
  static const Color shadow  = Color(0x1AC2185B);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
  static const Color error   = Color(0xFFC62828);
  static const Color info    = Color(0xFF1565C0);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFFFF0F5), Color(0xFFF3E8FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF1A1A2E), Color(0xFF2D1B4E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration get primaryBoxDecoration => const BoxDecoration(
    gradient: primaryGradient,
  );

  static List<Color> get serviceCardColors => [
    const Color(0xFFFF6B9D),
    const Color(0xFF7B61FF),
    const Color(0xFF00BFA5),
    const Color(0xFFFF8A50),
    const Color(0xFF42A5F5),
    const Color(0xFFAB47BC),
    const Color(0xFF66BB6A),
    const Color(0xFFEF5350),
    const Color(0xFF26C6DA),
    const Color(0xFFFFA726),
    const Color(0xFF78909C),
    const Color(0xFFEC407A),
  ];
}
