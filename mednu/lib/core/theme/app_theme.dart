import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class AppTheme {
  AppTheme._();

  // ─────────────────────────────────────────────────────────
  // DARK THEME — "Midnight Pro"
  // Deep navy-black base · Layered surfaces · Vivid glows
  // ─────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const bg      = AppColors.darkBase;          // #060C18
    const surface = AppColors.darkSurface;       // #0D1525
    const card    = AppColors.darkCard;          // #111E33
    const elevated= AppColors.darkCardElevated;  // #172540
    const border  = AppColors.darkBorder;        // white 7%
    const borderM = AppColors.darkBorderMedium;  // white 10%

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryDark,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryDark,
        onSecondaryContainer: Colors.white,
        tertiary: AppColors.accentLight,
        onTertiary: Colors.white,
        tertiaryContainer: AppColors.accent,
        onTertiaryContainer: Colors.white,
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: const Color(0xFF7F0000),
        onErrorContainer: Colors.white,
        surface: surface,
        onSurface: Colors.white,
        surfaceContainerHighest: card,
        onSurfaceVariant: const Color(0xFFB0BEC5),
        outline: borderM,
        outlineVariant: border,
        shadow: Colors.black,
        scrim: Colors.black87,
        inverseSurface: Colors.white,
        onInverseSurface: Colors.black87,
        inversePrimary: AppColors.primaryLight,
        surfaceTint: AppColors.primary,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: 'Poppins',

      // ── Text ────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge:   TextStyle(fontFamily: 'Poppins', color: Colors.white),
        displayMedium:  TextStyle(fontFamily: 'Poppins', color: Colors.white),
        displaySmall:   TextStyle(fontFamily: 'Poppins', color: Colors.white),
        headlineLarge:  TextStyle(fontFamily: 'Poppins', color: Colors.white),
        headlineMedium: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        headlineSmall:  TextStyle(fontFamily: 'Poppins', color: Colors.white),
        titleLarge:     TextStyle(fontFamily: 'Poppins', color: Colors.white),
        titleMedium:    TextStyle(fontFamily: 'Poppins', color: Colors.white),
        titleSmall:     TextStyle(fontFamily: 'Poppins', color: Colors.white),
        bodyLarge:      TextStyle(fontFamily: 'Poppins', color: Colors.white),
        bodyMedium:     TextStyle(fontFamily: 'Poppins', color: Color(0xFFB0BEC5)),
        bodySmall:      TextStyle(fontFamily: 'Poppins', color: Color(0xFF7D8FAD)),
        labelLarge:     TextStyle(fontFamily: 'Poppins', color: Colors.white),
        labelMedium:    TextStyle(fontFamily: 'Poppins', color: Color(0xFFB0BEC5)),
        labelSmall:     TextStyle(fontFamily: 'Poppins', color: Color(0xFF7D8FAD)),
      ),

      // ── AppBar ──────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0D1525),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        shape: Border(bottom: BorderSide(color: border, width: 1)),
      ),

      // ── ElevatedButton — gradient pill ──────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          shadowColor: WidgetStateProperty.all(AppColors.primaryGlowStrong),
          elevation: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? 0 : 8),
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          textStyle: WidgetStateProperty.all(AppTextStyles.button),
          minimumSize: WidgetStateProperty.all(const Size(double.infinity, 52)),
          overlayColor: WidgetStateProperty.all(Colors.white.withOpacity(0.08)),
        ),
      ),

      // ── OutlinedButton ──────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBright,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTextStyles.button.copyWith(color: AppColors.primaryBright),
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: AppColors.primary.withOpacity(0.06),
        ),
      ),

      // ── TextButton ──────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBright,
          textStyle: AppTextStyles.labelLarge.copyWith(color: AppColors.primaryBright),
        ),
      ),

      // ── InputDecoration ─────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderM),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
        hintStyle: const TextStyle(
            fontFamily: 'Poppins', color: Color(0xFF4A6080), fontSize: 13),
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', color: Color(0xFF7D8FAD)),
        prefixIconColor: const Color(0xFF7D8FAD),
        suffixIconColor: const Color(0xFF7D8FAD),
      ),

      // ── Card ────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
        shadowColor: AppColors.primaryGlowDark,
      ),

      // ── BottomNavigationBar ─────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF4A6080),
        selectedLabelStyle: TextStyle(
            fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // ── Chip ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: AppColors.primary.withOpacity(0.20),
        disabledColor: card,
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: Colors.white,
            fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Divider ─────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),

      // ── SnackBar ────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),

      // ── Dialog ──────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 24,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700,
            color: Colors.white),
        contentTextStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, color: Color(0xFFB0BEC5)),
      ),

      // ── BottomSheet ─────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: elevated,
        modalBackgroundColor: elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 16,
        modalElevation: 16,
      ),

      // ── Switch ──────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF4A6080)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.primary
                : const Color(0xFF1E2D47)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── ListTile ────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: Color(0xFF7D8FAD),
        textColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ── Progress Indicator ──────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: border,
        circularTrackColor: border,
      ),

      // ── Tab Bar ─────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: const Color(0xFF4A6080),
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
          borderRadius: BorderRadius.circular(2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: WidgetStateProperty.all(
            AppColors.primary.withOpacity(0.08)),
      ),

      // ── Icon ────────────────────────────────────────────
      iconTheme: const IconThemeData(color: Color(0xFF7D8FAD)),
      primaryIconTheme: const IconThemeData(color: Colors.white),

      // ── Floating Action Button ───────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // ── PopupMenu ───────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 12,
        textStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // LIGHT THEME
  // ─────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Poppins',

      // ── AppBar ────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
      ),

      // ── ElevatedButton ────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTextStyles.button,
          minimumSize: const Size(double.infinity, 52),
        ),
      ),

      // ── OutlinedButton ────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTextStyles.button.copyWith(color: AppColors.primary),
          minimumSize: const Size(double.infinity, 52),
        ),
      ),

      // ── TextButton ────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
        ),
      ),

      // ── InputDecoration ───────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
        labelStyle: AppTextStyles.labelMedium,
      ),

      // ── Card ──────────────────────────────────────────
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.divider),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── BottomNavigationBar ───────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // ── Chip ──────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primary.withOpacity(0.15),
        labelStyle: AppTextStyles.labelSmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Divider ───────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── SnackBar ──────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Dialog ────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 8,
        titleTextStyle: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),

      // ── BottomSheet ───────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 8,
        modalElevation: 8,
      ),

      // ── Switch ────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.border),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Tab Bar ───────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
          borderRadius: BorderRadius.circular(2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
      ),

      // ── Floating Action Button ─────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // ── PopupMenu ─────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        textStyle: const TextStyle(
            fontFamily: 'Poppins', color: AppColors.textPrimary, fontSize: 13),
      ),
    );
  }
}
