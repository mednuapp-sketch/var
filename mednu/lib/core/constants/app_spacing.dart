import 'package:flutter/material.dart';
import '../utils/r.dart';

/// Universal spacing standard for MedNU screens.
///
/// Every value here is derived from [R] so spacing scales consistently
/// across small phones, large phones, and tablets. Use these instead of
/// hardcoded EdgeInsets/SizedBox numbers so every screen feels identical.
class AppSpacing {
  AppSpacing._();

  // ── Hero / SliverAppBar header (icon + title + subtitle, no bottom widget) ──
  /// Standard expanded height for a simple icon/title/subtitle hero header.
  static double headerHeight(BuildContext c) => R.h(c, 160);

  /// Standard header content padding — clears the back button/status bar at
  /// the top and leaves breathing room at the bottom.
  static EdgeInsets headerPadding(BuildContext c) => EdgeInsets.fromLTRB(
        R.p(c, 20),
        R.p(c, 48),
        R.p(c, 20),
        R.p(c, 16),
      );

  /// Same as [headerPadding] but with no bottom padding, for headers that
  /// have a bottom widget (e.g. a TabBar) directly beneath them.
  static EdgeInsets headerPaddingWithBottomWidget(BuildContext c) =>
      EdgeInsets.fromLTRB(R.p(c, 20), R.p(c, 48), R.p(c, 20), 0);

  static double headerIconSize(BuildContext c) => R.w(c, 36);
  static double headerIconGap(BuildContext c) => R.h(c, 8);

  // ── Page-level content ───────────────────────────────────────────────────
  /// Standard outer padding for a page's scrollable content.
  static EdgeInsets page(BuildContext c) => EdgeInsets.all(R.p(c, 20));

  static EdgeInsets pageHorizontal(BuildContext c) =>
      EdgeInsets.symmetric(horizontal: R.p(c, 20));

  /// Gap between major sections on a page.
  static double sectionGap(BuildContext c) => R.h(c, 20);

  /// Gap between cards/items in a list.
  static double cardGap(BuildContext c) => R.h(c, 12);

  static double cardPadding(BuildContext c) => R.p(c, 16);

  static double cardRadius(BuildContext c) => R.r(c, 18);
}
