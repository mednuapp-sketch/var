import 'package:flutter/material.dart';

/// Mirrors the mednu / mednu_doctor brand palette: one plum family.
class AppColors {
  AppColors._();

  static const Color primary      = Color(0xFF522546); // Brand plum
  static const Color primaryLight = Color(0xFFC494CD);
  static const Color primaryDark  = Color(0xFF33172C);
  static const Color primarySoft  = Color(0xFFEFE1EC); // wash behind icons/badges

  static const Color secondary      = Color(0xFF633058); // same plum family
  static const Color secondaryLight = Color(0xFFC494CD);
  static const Color secondaryDark  = Color(0xFF3D1D36);

  static const Color accent      = Color(0xFF633058);
  static const Color accentLight = Color(0xFFC494CD);

  static const Color background     = Color(0xFFF7F4F6);
  static const Color surface        = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1E7EE);

  static const Color textPrimary   = Color(0xFF33172C);
  static const Color textSecondary = Color(0xFF7A6472);
  static const Color textHint      = Color(0xFF857080);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border  = Color(0xFFE4D9E1);
  static const Color divider = Color(0xFFEDE3EA);
  static const Color shadow  = Color(0x1A522546);

  // Semantic status colors only — never used decoratively.
  static const Color success = Color(0xFF1E8E5A);
  static const Color warning = Color(0xFFB9720B);
  static const Color error   = Color(0xFFC0392B);
  static const Color info    = Color(0xFF522546);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF522546), Color(0xFF633058)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFF7F4F6), Color(0xFFF1E7EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF33172C), Color(0xFF522546)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration get primaryBoxDecoration => const BoxDecoration(
    gradient: primaryGradient,
  );

  /// Card accents: shades of the one plum hue, no rainbow.
  static List<Color> get serviceCardColors => const [
    Color(0xFF522546),
    Color(0xFF633058),
  ];
}
