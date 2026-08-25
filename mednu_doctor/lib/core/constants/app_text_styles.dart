import 'package:flutter/material.dart';
import 'app_colors.dart';

/// MedNu typography scale, built on Inter.
///
/// `google_fonts` registers the "Inter" family at runtime the first time
/// [AppTheme] builds `ThemeData.fontFamily` (see app_theme.dart) — once
/// registered, plain `fontFamily: 'Inter'` TextStyles resolve to it too,
/// which is what lets every style below stay `static const` and usable in
/// const widget trees throughout the app.
class AppTextStyles {
  AppTextStyles._();

  static const String _font = 'Inter';

  static const display = TextStyle(fontFamily: _font, fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4);
  static const h1 = TextStyle(fontFamily: _font, fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.3);
  static const h2 = TextStyle(fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2);
  static const h3 = TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const h4 = TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const sectionTitle = TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.1);

  static const bodyLarge = TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.4);
  static const body = TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.4);
  /// Alias of [body] kept for existing call sites.
  static const bodyMedium = body;
  static const bodySmall = TextStyle(fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.35);

  static const caption = TextStyle(fontFamily: _font, fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textHint);

  static const labelLarge = TextStyle(fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const labelMedium = TextStyle(fontFamily: _font, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const labelSmall = TextStyle(fontFamily: _font, fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary);

  static const button = TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.2);

  /// Large numeric emphasis — stat cards, earnings, counts.
  static const statistic = TextStyle(fontFamily: _font, fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3);
  static const statisticLabel = TextStyle(fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary);

  static const onPrimaryH2 = TextStyle(fontFamily: _font, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white);
  static const onPrimaryBody = TextStyle(fontFamily: _font, fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70);
}
