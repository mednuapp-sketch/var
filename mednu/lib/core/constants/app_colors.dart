import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary Palette ────────────────────────────────────
  // "Primary solid" per brand spec — fixed across themes, always paired
  // with light text (textOnPrimary). Used for filled buttons/chips.
  static const Color primary       = Color(0xFF522546);   // Brand plum — primary solid
  static const Color primaryLight  = Color(0xFFC494CD);   // Dark-mode "Primary" — links/icons/borders
  static const Color primaryDark   = Color(0xFF33172C);   // Deeper shade for containers/dark glows
  static const Color primaryBright = Color(0xFFC494CD);   // Dark-mode foregrounds (alias of primaryLight)
  static const Color primarySoft       = Color(0xFFEFE1EC); // Light wash behind icons/badges
  static const Color primarySoftDark   = Color(0xFF452038); // Dark wash behind icons/badges

  static const Color secondary     = Color(0xFF633058);   // Brand secondary plum — fixed
  static const Color secondaryLight= Color(0xFFC494CD);
  static const Color secondaryDark = Color(0xFF3D1D36);

  // ── Accent ────────────────────────────────────────────
  static const Color accent        = Color(0xFFF9943B);   // Brand coral/orange (light)
  static const Color accentLight   = Color(0xFFFFA857);   // Brand coral/orange (dark)
  // Text-safe accent — raw `accent` fails WCAG contrast as text on light bg.
  static const Color accentText      = Color(0xFF8B4513);   // Light-mode accent text
  static const Color accentTextDark  = Color(0xFFFFA857);   // Dark-mode accent text (= accentLight)

  // ── Background (light mode) ───────────────────────────
  static const Color background    = Color(0xFFF7F4F6);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceVariant= Color(0xFFF1E7EE);   // Section washes (--surface-tint)

  // ── Dark Mode Palette — brand plum ────────────────────
  static const Color darkBase          = Color(0xFF1C0F19); // Page background
  static const Color darkSurface       = Color(0xFF2A1523); // Cards, inputs
  static const Color darkCard          = Color(0xFF2A1523); // Card level
  static const Color darkCardElevated  = Color(0xFF33192C); // Modals, sheets, popovers
  static const Color darkBorder        = Color(0x334A2A40); // Subtle hairline (20%)
  static const Color darkBorderMedium  = Color(0xFF4A2A40); // Solid hairline (--border dark)
  static const Color darkBorderAccent  = Color(0x33C494CD); // Primary-tinted 20%

  // Glow colors for dark mode shadows
  static const Color primaryGlowDark   = Color(0x40522546); // Plum glow 25%
  static const Color primaryGlowStrong = Color(0x60522546); // Plum glow 38%
  static const Color accentGlowDark    = Color(0x33FFA857); // Coral glow 20%

  // ── Gradient ──────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF522546), Color(0xFF633058)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient heroBannerGradient = LinearGradient(
    colors: [Color(0xFF522546), Color(0xFF522546), Color(0xFF24101F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // Emergency banner — fixed, theme-invariant (dark plum → red).
  static const LinearGradient emergencyBannerGradient = LinearGradient(
    colors: [Color(0xFF24101F), Color(0xFF522546), Color(0xFF3A1712)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color emergencyBannerForeground = Color(0xFFF8F0F6);
  static const Color heroGlowOverlay = Color(0x8CA36BAC); // rgba(163,107,172,0.55)

  // ── Fixed footer (theme-invariant) ─────────────────────
  static const Color footerBackground = Color(0xFF1C0F19);
  static const Color footerAccent     = Color(0xFFC494CD); // heading / wordmark
  static const Color footerBodyText   = Color(0xFFC7AFC0);

  // ── Service Card Gradients ─────────────────────────────
  static const LinearGradient emergencyGrad   = LinearGradient(colors: [Color(0xFFEF5350), Color(0xFFB71C1C)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient appointmentGrad = LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF1565C0)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient medicineGrad    = LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient consultGrad     = LinearGradient(colors: [Color(0xFF522546), Color(0xFF633058)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient diagnosticGrad  = LinearGradient(colors: [Color(0xFF26C6DA), Color(0xFF0097A7)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient labTestGrad     = LinearGradient(colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient careAssistGrad  = LinearGradient(colors: [Color(0xFFFFA726), Color(0xFFE65100)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient ambulanceGrad   = LinearGradient(colors: [Color(0xFFEF5350), Color(0xFF522546)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient physioGrad      = LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF0D47A1)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient nutritionGrad   = LinearGradient(colors: [Color(0xFF9CCC65), Color(0xFF33691E)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient counselGrad     = LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF311B92)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient equipmentGrad   = LinearGradient(colors: [Color(0xFF78909C), Color(0xFF263238)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient caregiverGrad   = LinearGradient(colors: [Color(0xFFA36BAC), Color(0xFF522546)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient pregnancyGrad   = LinearGradient(colors: [Color(0xFF522546), Color(0xFF633058)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const LinearGradient hospitalGrad    = LinearGradient(colors: [Color(0xFF522546), Color(0xFF633058)], begin: Alignment.topLeft, end: Alignment.bottomRight);

  // ── Status (semantic — independent of brand) ───────────
  static const Color success  = Color(0xFF1E8E5A); // --good
  static const Color warning  = Color(0xFFB9720B); // --warn
  static const Color error    = Color(0xFFC0392B); // --crit
  static const Color info     = Color(0xFF2C6CA8); // --info
  static const Color neutralStatus = Color(0xFF64726F); // --neutral

  static const Color successDark = Color(0xFF3FCB86);
  static const Color warningDark = Color(0xFFE7A63D);
  static const Color errorDark   = Color(0xFFF0685A);
  static const Color infoDark    = Color(0xFF6FA3D8);
  static const Color neutralStatusDark = Color(0xFF93A8A2);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF33172C); // --ink (light)
  static const Color textSecondary = Color(0xFF7A6472); // --ink-soft (light)
  static const Color textHint      = Color(0xFFAE96A7);
  static const Color textOnPrimary = Color(0xFFF8F0F6); // Always pairs with primary-solid

  static const Color textPrimaryDark   = Color(0xFFF3E8EF); // --ink (dark)
  static const Color textSecondaryDark = Color(0xFFC7AFC0); // --ink-soft (dark)

  // ── Border & Divider ──────────────────────────────────
  static const Color border   = Color(0xFFE4D9E1);
  static const Color divider  = Color(0xFFEDE3EA);

  // ── Shadow ────────────────────────────────────────────
  static const Color shadow   = Color(0x1A522546);
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
      isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary;

  /// Hint / tertiary text color.
  Color get appTextHint =>
      isDarkMode ? AppColors.textSecondaryDark : AppColors.textHint;

  /// Divider color.
  Color get appDivider => Theme.of(this).dividerColor;

  /// Border color.
  Color get appBorder =>
      isDarkMode ? AppColors.darkBorderMedium : AppColors.border;

  /// Primary "text-on-page-background" use — links, eyebrows, icon strokes,
  /// active nav/filter borders. NOT for filled buttons — use AppColors.primary.
  Color get appPrimary => isDarkMode ? AppColors.primaryLight : AppColors.primary;

  /// Wash background behind icons/badges.
  Color get appPrimarySoft =>
      isDarkMode ? AppColors.primarySoftDark : AppColors.primarySoft;

  /// Accent color, sparingly (live-pulse dot, priority chips, tags).
  Color get appAccent => isDarkMode ? AppColors.accentLight : AppColors.accent;

  /// Accent-safe text color (never render raw accent as text on light bg).
  Color get appAccentText =>
      isDarkMode ? AppColors.accentTextDark : AppColors.accentText;

  /// Section wash background.
  Color get appSurfaceTint =>
      isDarkMode ? AppColors.secondary : AppColors.surfaceVariant;

  Color get appGood => isDarkMode ? AppColors.successDark : AppColors.success;
  Color get appWarn => isDarkMode ? AppColors.warningDark : AppColors.warning;
  Color get appCrit => isDarkMode ? AppColors.errorDark : AppColors.error;
  Color get appInfo => isDarkMode ? AppColors.infoDark : AppColors.info;
  Color get appNeutralStatus =>
      isDarkMode ? AppColors.neutralStatusDark : AppColors.neutralStatus;
}
