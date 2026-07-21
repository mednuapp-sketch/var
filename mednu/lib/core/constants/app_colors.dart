import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary Palette ────────────────────────────────────
  static const Color primary       = Color(0xFFC2185B);   // Deep Pink
  static const Color primaryLight  = Color(0xFFE91E8C);
  static const Color primaryDark   = Color(0xFF880E4F);
  static const Color primaryBright = Color(0xFFFF2272);   // Vivid pink for dark mode glows

  static const Color secondary     = Color(0xFF7B1FA2);   // Purple
  static const Color secondaryLight= Color(0xFF9C27B0);
  static const Color secondaryDark = Color(0xFF4A148C);

  // ── Accent ────────────────────────────────────────────
  static const Color accent        = Color(0xFF00897B);   // Teal
  static const Color accentLight   = Color(0xFF4DB6AC);

  // ── Background (light mode) ───────────────────────────
  static const Color background    = Color(0xFFF7F4F8);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceVariant= Color(0xFFFCF8FD);

  // ── Dark Mode Palette — "Midnight Pro" ────────────────
  // Deep navy-black layered surfaces (not flat gray)
  static const Color darkBase          = Color(0xFF060C18); // True base — midnight navy
  static const Color darkSurface       = Color(0xFF0D1525); // Slightly elevated surface
  static const Color darkCard          = Color(0xFF111E33); // Card level
  static const Color darkCardElevated  = Color(0xFF172540); // Modals, sheets, popovers
  static const Color darkBorder        = Color(0x12FFFFFF); // Subtle white 7%
  static const Color darkBorderMedium  = Color(0x1AFFFFFF); // White 10%
  static const Color darkBorderAccent  = Color(0x33C2185B); // Pink-tinted 20%

  // Glow colors for dark mode shadows
  static const Color primaryGlowDark   = Color(0x40C2185B); // Pink glow 25%
  static const Color primaryGlowStrong = Color(0x60C2185B); // Pink glow 38%
  static const Color accentGlowDark    = Color(0x3300897B); // Teal glow 20%

  // ── Gradient ──────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient heroBannerGradient = LinearGradient(
    colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Service Card Gradients ─────────────────────────────
  static const LinearGradient emergencyGrad   = LinearGradient(colors: [Color(0xFFEF5350), Color(0xFFB71C1C)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient appointmentGrad = LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF1565C0)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient medicineGrad    = LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient consultGrad     = LinearGradient(colors: [Color(0xFFAB47BC), Color(0xFF6A1B9A)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient diagnosticGrad  = LinearGradient(colors: [Color(0xFF26C6DA), Color(0xFF0097A7)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient labTestGrad     = LinearGradient(colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient careAssistGrad  = LinearGradient(colors: [Color(0xFFFFA726), Color(0xFFE65100)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient ambulanceGrad   = LinearGradient(colors: [Color(0xFFEF5350), Color(0xFF880E4F)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient physioGrad      = LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF0D47A1)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient nutritionGrad   = LinearGradient(colors: [Color(0xFF9CCC65), Color(0xFF33691E)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient counselGrad     = LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF311B92)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient equipmentGrad   = LinearGradient(colors: [Color(0xFF78909C), Color(0xFF263238)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient caregiverGrad   = LinearGradient(colors: [Color(0xFFEC407A), Color(0xFF880E4F)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient pregnancyGrad   = LinearGradient(colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)], begin: Alignment.topLeft, end: Alignment.bottomRight);

  // ── Status ────────────────────────────────────────────
  static const Color success  = Color(0xFF2E7D32);
  static const Color warning  = Color(0xFFF57F17);
  static const Color error    = Color(0xFFC62828);
  static const Color info     = Color(0xFF1565C0);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF616161);
  static const Color textHint      = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Border & Divider ──────────────────────────────────
  static const Color border   = Color(0xFFE0E0E0);
  static const Color divider  = Color(0xFFF5F5F5);

  // ── Shadow ────────────────────────────────────────────
  static const Color shadow   = Color(0x1AC2185B);
}

// ─────────────────────────────────────────────────────────
// Theme-aware color access — use these instead of the raw
// AppColors.* constants above (which are light-mode only)
// whenever a widget needs to look correct in dark mode too.
// Values mirror exactly what AppTheme.darkTheme/lightTheme
// already define for each role.
// ─────────────────────────────────────────────────────────
extension AppColorsContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Scaffold / page background.
  Color get appBackground => Theme.of(this).scaffoldBackgroundColor;

  /// Card / elevated container background.
  Color get appSurface =>
      Theme.of(this).cardTheme.color ?? Theme.of(this).colorScheme.surface;

  /// Primary text color.
  Color get appTextPrimary => Theme.of(this).colorScheme.onSurface;

  /// Secondary / muted text color.
  Color get appTextSecondary =>
      isDarkMode ? const Color(0xFFB0BEC5) : AppColors.textSecondary;

  /// Hint / tertiary text color.
  Color get appTextHint =>
      isDarkMode ? const Color(0xFF7D8FAD) : AppColors.textHint;

  /// Divider color.
  Color get appDivider => Theme.of(this).dividerColor;

  /// Border color.
  Color get appBorder =>
      isDarkMode ? AppColors.darkBorderMedium : AppColors.border;
}
