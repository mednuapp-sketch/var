import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

// ─────────────────────────────────────────────────────────────
// Smooth slide-right + fade transition — used on every platform
// ─────────────────────────────────────────────────────────────
class _SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(
        parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    final slide = Tween<Offset>(
            begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));
    final secondarySlide = Tween<Offset>(
            begin: Offset.zero, end: const Offset(-0.04, 0))
        .animate(CurvedAnimation(
            parent: secondaryAnimation, curve: Curves.easeInCubic));
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: SlideTransition(position: secondarySlide, child: child),
      ),
    );
  }
}

const _transitions = PageTransitionsTheme(builders: {
  TargetPlatform.android: _SmoothPageTransitionsBuilder(),
  TargetPlatform.iOS:     _SmoothPageTransitionsBuilder(),
  TargetPlatform.linux:   _SmoothPageTransitionsBuilder(),
  TargetPlatform.windows: _SmoothPageTransitionsBuilder(),
  TargetPlatform.macOS:   _SmoothPageTransitionsBuilder(),
});

class AppTheme {
  AppTheme._();

  // ─────────────────────────────────────────────────────────
  // DARK THEME — "Midnight Pro"
  // Deep navy-black base · Layered surfaces · Vivid glows
  // ─────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const bg      = AppColors.darkBase;          // #1C0F19
    const surface = AppColors.darkSurface;       // #2A1523
    const card    = AppColors.darkCard;          // #2A1523
    const elevated= AppColors.darkCardElevated;  // #33192C
    const border  = AppColors.darkBorder;        // border 20%
    const borderM = AppColors.darkBorderMedium;  // #4A2A40
    const ink     = AppColors.textPrimaryDark;   // #F3E8EF
    const inkSoft = AppColors.textSecondaryDark; // #C7AFC0

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      pageTransitionsTheme: _transitions,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: AppColors.primaryDark,
        primaryContainer: AppColors.primaryDark,
        onPrimaryContainer: ink,
        secondary: AppColors.secondary,
        onSecondary: ink,
        secondaryContainer: AppColors.secondaryDark,
        onSecondaryContainer: ink,
        tertiary: AppColors.accentLight,
        onTertiary: AppColors.primaryDark,
        tertiaryContainer: AppColors.accent,
        onTertiaryContainer: ink,
        error: AppColors.errorDark,
        onError: AppColors.primaryDark,
        errorContainer: Color(0xFF7F0000),
        onErrorContainer: ink,
        surface: surface,
        onSurface: ink,
        surfaceContainerHighest: card,
        onSurfaceVariant: inkSoft,
        outline: borderM,
        outlineVariant: border,
        shadow: Colors.black,
        scrim: Colors.black87,
        inverseSurface: ink,
        onInverseSurface: AppColors.primaryDark,
        inversePrimary: AppColors.primary,
        surfaceTint: AppColors.primaryLight,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: 'Poppins',

      // ── Text ────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge:   TextStyle(fontFamily: 'Poppins', color: ink),
        displayMedium:  TextStyle(fontFamily: 'Poppins', color: ink),
        displaySmall:   TextStyle(fontFamily: 'Poppins', color: ink),
        headlineLarge:  TextStyle(fontFamily: 'Poppins', color: ink),
        headlineMedium: TextStyle(fontFamily: 'Poppins', color: ink),
        headlineSmall:  TextStyle(fontFamily: 'Poppins', color: ink),
        titleLarge:     TextStyle(fontFamily: 'Poppins', color: ink),
        titleMedium:    TextStyle(fontFamily: 'Poppins', color: ink),
        titleSmall:     TextStyle(fontFamily: 'Poppins', color: ink),
        bodyLarge:      TextStyle(fontFamily: 'Poppins', color: ink),
        bodyMedium:     TextStyle(fontFamily: 'Poppins', color: inkSoft),
        bodySmall:      TextStyle(fontFamily: 'Poppins', color: inkSoft),
        labelLarge:     TextStyle(fontFamily: 'Poppins', color: ink),
        labelMedium:    TextStyle(fontFamily: 'Poppins', color: inkSoft),
        labelSmall:     TextStyle(fontFamily: 'Poppins', color: inkSoft),
      ),

      // ── AppBar ──────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.darkSurface,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: ink),
        actionsIconTheme: IconThemeData(color: ink),
        shape: Border(bottom: BorderSide(color: border, width: 1)),
      ),

      // ── ElevatedButton — gradient pill ──────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(AppColors.textOnPrimary),
          shadowColor: WidgetStateProperty.all(AppColors.primaryGlowStrong),
          elevation: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? 0 : 8),
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          textStyle: WidgetStateProperty.all(AppTextStyles.button),
          minimumSize: WidgetStateProperty.all(const Size(double.infinity, 52)),
          overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha:0.08)),
        ),
      ),

      // ── OutlinedButton ──────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBright,
          side: const BorderSide(color: AppColors.primaryBright, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTextStyles.button.copyWith(color: AppColors.primaryBright),
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: AppColors.primaryBright.withValues(alpha:0.08),
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
          borderSide: const BorderSide(color: AppColors.primaryBright, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.errorDark),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.errorDark, width: 1.8),
        ),
        hintStyle: const TextStyle(
            fontFamily: 'Poppins', color: inkSoft, fontSize: 13),
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', color: inkSoft),
        prefixIconColor: inkSoft,
        suffixIconColor: inkSoft,
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
        selectedItemColor: AppColors.primaryBright,
        unselectedItemColor: inkSoft,
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
        selectedColor: AppColors.primaryBright.withValues(alpha:0.20),
        disabledColor: card,
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: ink,
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
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: ink),
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
            color: ink),
        contentTextStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, color: inkSoft),
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
            s.contains(WidgetState.selected) ? AppColors.textOnPrimary : inkSoft),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.primaryBright
                : AppColors.darkBorderMedium),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── ListTile ────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: inkSoft,
        textColor: ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ── Progress Indicator ──────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryBright,
        linearTrackColor: border,
        circularTrackColor: border,
      ),

      // ── Tab Bar ─────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primaryBright,
        unselectedLabelColor: inkSoft,
        labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(color: AppColors.primaryBright, width: 2.5),
          borderRadius: BorderRadius.circular(2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: WidgetStateProperty.all(
            AppColors.primaryBright.withValues(alpha:0.08)),
      ),

      // ── Icon ────────────────────────────────────────────
      iconTheme: const IconThemeData(color: inkSoft),
      primaryIconTheme: const IconThemeData(color: ink),

      // ── Floating Action Button ───────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      // ── PopupMenu ───────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 12,
        textStyle: const TextStyle(fontFamily: 'Poppins', color: ink, fontSize: 13),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // LIGHT THEME
  // ─────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _transitions,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: AppColors.textOnPrimary,
        onTertiary: AppColors.textOnPrimary,
        onSurface: AppColors.textPrimary,
        shadow: AppColors.primary,
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
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha:0.4),
          elevation: 6,
          shadowColor: AppColors.primary.withValues(alpha:0.45),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTextStyles.button,
          minimumSize: const Size(double.infinity, 52),
          overlayColor: Colors.white.withValues(alpha:0.10),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed) ? 2 : 6),
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
        elevation: 3,
        shadowColor: AppColors.primary.withValues(alpha:0.14),
        surfaceTintColor: Colors.transparent,
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
        selectedColor: AppColors.primary.withValues(alpha:0.15),
        labelStyle: AppTextStyles.labelSmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 0,
        pressElevation: 1,
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
        foregroundColor: AppColors.textOnPrimary,
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
