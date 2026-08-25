/// MedNu spacing scale. Always pick from this set — never a raw number.
class AppSpacing {
  AppSpacing._();

  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double xxxl= 32;
  static const double huge= 40;
  static const double giant=48;

  /// Standard page horizontal margin.
  static const double pageMargin = lg;
}

/// MedNu border radius scale.
class AppRadius {
  AppRadius._();

  /// Small controls: chips of a control, checkboxes, tiny icon buttons.
  static const double sm = 8;

  /// Inputs, buttons.
  static const double md = 12;

  /// Cards.
  static const double lg = 16;

  /// Larger containers, dialogs.
  static const double xl = 20;

  /// Hero sections, bottom sheets.
  static const double xxl = 24;

  /// Fully pill-shaped — status chips, filters, tags only.
  static const double pill = 999;
}
