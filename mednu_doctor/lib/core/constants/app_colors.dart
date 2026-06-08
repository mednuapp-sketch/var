import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary Palette (Warm & Family — matches mednu app) ──
  static const Color primary       = Color(0xFFC2185B);   // Deep Pink
  static const Color primaryLight  = Color(0xFFE91E8C);
  static const Color primaryDark   = Color(0xFF880E4F);

  static const Color secondary     = Color(0xFF7B1FA2);   // Purple
  static const Color secondaryLight= Color(0xFF9C27B0);
  static const Color secondaryDark = Color(0xFF4A148C);

  // ── Accent ────────────────────────────────────────────
  static const Color accent        = Color(0xFF00897B);   // Teal
  static const Color accentLight   = Color(0xFF4DB6AC);

  // ── Background ────────────────────────────────────────
  static const Color background    = Color(0xFFF7F4F8);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceVariant= Color(0xFFFCF8FD);

  // ── Gradients ─────────────────────────────────────────
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

  static const LinearGradient onlineGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient earningGradient = LinearGradient(
    colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Status ────────────────────────────────────────────
  static const Color success  = Color(0xFF2E7D32);
  static const Color warning  = Color(0xFFF57F17);
  static const Color error    = Color(0xFFC62828);
  static const Color info     = Color(0xFF1565C0);

  // ── Doctor Online / Offline ───────────────────────────
  static const Color online   = Color(0xFF43A047);
  static const Color offline  = Color(0xFF757575);

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
