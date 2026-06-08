import 'package:flutter/material.dart';

class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'Poppins';

  // No color set on base styles — they inherit from DefaultTextStyle so they
  // automatically adapt between light (dark text) and dark (white text) themes.

  static const TextStyle display = TextStyle(
    fontFamily: _fontFamily, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: _fontFamily, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: _fontFamily, fontSize: 20, fontWeight: FontWeight.w700,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: _fontFamily, fontSize: 18, fontWeight: FontWeight.w600,
  );
  static const TextStyle h4 = TextStyle(
    fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w400, height: 1.5,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w400, height: 1.5,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily, fontSize: 11, fontWeight: FontWeight.w400, height: 1.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
  );
  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5,
  );
  static const TextStyle labelSmall = TextStyle(
    fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily, fontSize: 11, fontWeight: FontWeight.w400,
  );

  // Always white — used on gradient/colored surfaces only.
  static const TextStyle button = TextStyle(
    fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w700,
    color: Colors.white, letterSpacing: 0.3,
  );
  static const TextStyle onPrimaryH2 = TextStyle(
    fontFamily: _fontFamily, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
  );
  static const TextStyle onPrimaryBody = TextStyle(
    fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70,
  );
}
