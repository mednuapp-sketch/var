import 'package:flutter/material.dart';

/// Responsive sizing utility.
///
/// All sizes are relative to a 390 dp reference width (iPhone 14 / Pixel 7).
/// Clamps keep the app legible on screens from ~320 dp to tablets at ~768 dp.
///
/// Usage:
///   R.sp(context, 14)   → responsive font size
///   R.w(context, 52)    → responsive widget width / height
///   R.p(context, 16)    → responsive padding / margin / spacing
///   R.r(context, 14)    → responsive border radius
///   R.isTablet(context) → true when width > 600 dp
class R {
  R._();

  static const double _ref = 390.0;

  static double _sw(BuildContext ctx) => MediaQuery.sizeOf(ctx).width;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Responsive font size.  Narrow clamp keeps text readable without overflow.
  static double sp(BuildContext ctx, double size) =>
      size * (_sw(ctx) / _ref).clamp(0.85, 1.10);

  /// Responsive widget width / icon / avatar size.
  static double w(BuildContext ctx, double size) =>
      size * (_sw(ctx) / _ref).clamp(0.80, 1.20);

  /// Responsive height (same scale as width for uniform feel).
  static double h(BuildContext ctx, double size) =>
      size * (_sw(ctx) / _ref).clamp(0.80, 1.20);

  /// Responsive padding / margin / gap.
  static double p(BuildContext ctx, double size) =>
      size * (_sw(ctx) / _ref).clamp(0.80, 1.20);

  /// Responsive border radius.
  static double r(BuildContext ctx, double size) =>
      size * (_sw(ctx) / _ref).clamp(0.80, 1.20);

  /// True when the screen is wide enough to be considered a tablet.
  static bool isTablet(BuildContext ctx) => _sw(ctx) > 600;

  /// True when the screen is narrower than a typical small phone.
  static bool isSmall(BuildContext ctx) => _sw(ctx) < 360;
}
