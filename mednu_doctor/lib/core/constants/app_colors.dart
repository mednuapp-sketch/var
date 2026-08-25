import 'package:flutter/material.dart';

/// MedNu brand color system (light mode).
///
/// Usage rule: white/light surfaces dominate (~75%), plum brand colors are
/// used for structure and emphasis (~20%), gradients/accent orange are used
/// sparingly for hierarchy only (~5-10%). Never stack multiple gradients on
/// one screen.
///
/// Contrast rule baked in throughout: [accent] (bright orange) is never used
/// as text on a light background — it fails WCAG contrast there. Use
/// [accentText] (a darker, type-safe shade of the same hue) for any text/
/// icon-label use of the accent color; reserve raw [accent] for solid
/// fills, dots, and icon glyphs only.
///
/// Token values are structured to match a documented light/dark brand
/// system 1:1 by name, even though this app is light-mode only today — a
/// future dark-mode pass can wire these into a ThemeExtension without
/// renaming anything call sites already depend on.
class AppColors {
  AppColors._();

  // ── Primary (MedNu Wine / Plum) ─────────────────────────
  // Text/links/icon strokes/active borders — never a filled background.
  static const Color primary       = Color(0xFF522546);
  // Kept for existing gradient usages elsewhere in the app (hero banners,
  // earnings gradient) — not part of the new token spec, but still relied
  // on by call sites and visually compatible with it.
  static const Color primaryLight  = Color(0xFFA36BAC);
  static const Color primaryDark   = Color(0xFF33172C);
  // Filled buttons/chips (Book Appointment, Confirm, active filters) —
  // always paired with textOnPrimary so contrast stays safe. Same value as
  // [primary] in light mode by design; kept as a distinct token because a
  // future dark mode fixes this one while [primary] shifts lighter.
  static const Color primarySolid  = Color(0xFF522546);
  // Wash background behind icons/badges (department badge, default
  // book-button background) — replaces ad-hoc alpha-blended primary tints.
  static const Color primarySoft   = Color(0xFFEFE1EC);

  static const Color secondary     = Color(0xFF633058);
  static const Color secondaryLight= Color(0xFF7A4270);
  static const Color secondaryDark = Color(0xFF3F1F38);

  // ── Accent (use sparingly: live indicators, priority, highlights) ──────
  static const Color accent        = Color(0xFFF9943B);
  static const Color accentLight   = Color(0xFFFCB578);
  static const Color accentDark    = Color(0xFFD97620);
  // Contrast-safe stand-in for [accent] whenever the color is used as text
  // (e.g. an emergency banner phone number) rather than a fill/dot/icon.
  static const Color accentText    = Color(0xFF8B4513);

  // ── Neutrals (hue-biased toward the plum, not generic grey) ────────────
  static const Color background    = Color(0xFFF7F4F6);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceVariant= Color(0xFFF1E7EE);
  static const Color border        = Color(0xFFE4D9E1);
  static const Color divider       = Color(0xFFE4D9E1);

  // ── Gradients (use deliberately, not decoratively) ─────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient heroBannerGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient onlineGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient earningGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Hero visual gradient: teal → teal-solid → near-black plum, used behind
  /// large hero illustrations/headers. Pair with [heroGlowOverlay] for the
  /// soft radial highlight the design spec calls for.
  static const LinearGradient heroVisualGradient = LinearGradient(
    colors: [primary, primarySolid, Color(0xFF24101F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color heroGlowOverlay = Color(0x8CA36BAC); // rgba(163,107,172,0.55)

  /// Emergency banner gradient (dark plum → red) — fixed, does not vary by
  /// theme since it always sits on its own dark surface.
  static const LinearGradient emergencyBannerGradient = LinearGradient(
    colors: [Color(0xFF24101F), Color(0xFF522546), Color(0xFF3A1712)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color emergencyBannerText = Color(0xFFF8F0F6);

  // ── Footer (fixed, theme-invariant) ─────────────────────
  static const Color footerBackground = Color(0xFF1C0F19);
  static const Color footerAccent     = Color(0xFFC494CD); // heading/wordmark
  static const Color footerBodyText   = Color(0xFFC7AFC0);

  // ── Semantic status — independent of brand, same meaning everywhere ────
  // (bed/wait/doctor status: available, on-break, at-capacity, in-progress,
  // off-duty). Prefer these four over the legacy success/warning/error/info
  // aliases below for new status UI; the aliases stay for existing call
  // sites and now resolve to the same values.
  static const Color good    = Color(0xFF1E8E5A);
  static const Color goodBg  = Color(0xFFE3F5EC);
  static const Color warn    = Color(0xFFB9720B);
  static const Color warnBg  = Color(0xFFFBF0DC);
  static const Color crit    = Color(0xFFC0392B);
  static const Color critBg  = Color(0xFFFCE8E6);
  static const Color statusInfo   = Color(0xFF2C6CA8);
  static const Color statusInfoBg = Color(0xFFE5EFF8);
  static const Color neutral   = Color(0xFF64726F);
  static const Color neutralBg = Color(0xFFEDF0EF);

  // ── Status (legacy names — kept for existing call sites) ───────────────
  static const Color success  = good;
  static const Color successBg= goodBg;
  static const Color warning  = warn;
  static const Color warningBg= warnBg;
  static const Color error    = crit;
  static const Color errorBg  = critBg;
  static const Color info     = statusInfo;
  static const Color infoBg   = statusInfoBg;

  // ── Online / Offline (all roles) ──────────────────────
  static const Color online   = good;
  static const Color offline  = neutral;

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF33172C); // = ink
  static const Color textSecondary = Color(0xFF7A6472); // = ink-soft
  static const Color textHint      = Color(0xFF9C8A96);
  static const Color textOnPrimary = Color(0xFFF8F0F6);

  // ── Shadow ────────────────────────────────────────────
  static const Color shadow   = Color(0x14522546);

  /// Returns the standard background tint + foreground pair for a status
  /// keyword, so status visuals stay identical across every screen.
  /// Combine with an icon — never rely on color alone (see design system §67).
  static (Color bg, Color fg) statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'available':
      case 'accepted':
      case 'completed':
      case 'verified':
      case 'online':
      case 'delivered':
      case 'collected':
      case 'in stock':
        return (successBg, success);
      case 'pending':
      case 'in progress':
      case 'preparing':
      case 'connecting':
      case 'out for delivery':
      case 'low stock':
        return (warningBg, warning);
      case 'cancelled':
      case 'rejected':
      case 'expired':
      case 'failed':
      case 'out of stock':
      case 'offline':
        return (errorBg, error);
      default:
        return (infoBg, info);
    }
  }
}
