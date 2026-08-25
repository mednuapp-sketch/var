/// Centralized MedNu form validation.
///
/// Every validator returns `null` when valid, or a short, human-readable
/// error string suitable for direct display beside the field. Never expose
/// technical error text (exceptions, codes) through these messages.
class Validators {
  Validators._();

  // ── Phone (India) ───────────────────────────────────────
  static final _indianMobile = RegExp(r'^[6-9]\d{9}$');

  /// Strips a leading `+91`/`91` prefix and any spaces/dashes before
  /// validating, so both `9876543210` and `+91 98765 43210` are accepted.
  static String normalizePhone(String raw) {
    var v = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (v.startsWith('+91')) v = v.substring(3);
    if (v.startsWith('91') && v.length == 12) v = v.substring(2);
    return v;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your mobile number';
    final v = normalizePhone(value);
    if (!RegExp(r'^\d+$').hasMatch(v)) return 'Mobile number can only contain digits';
    if (v.length < 10) return 'Mobile number must be 10 digits';
    if (v.length > 10) return 'Mobile number must be 10 digits';
    if (!_indianMobile.hasMatch(v)) return 'Enter a valid mobile number';
    return null;
  }

  // ── OTP ──────────────────────────────────────────────────
  static String? otp(String? value, {int length = 6}) {
    if (value == null || value.isEmpty) return 'Enter the OTP';
    if (!RegExp(r'^\d+$').hasMatch(value)) return 'OTP can only contain digits';
    if (value.length != length) return 'Enter the $length-digit OTP';
    return null;
  }

  // ── Email ────────────────────────────────────────────────
  static final _email = RegExp(r'^[\w.+-]+@[a-zA-Z\d-]+\.[a-zA-Z]{2,}$');

  static String? email(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Enter your email address' : null;
    }
    if (!_email.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  // ── Password ─────────────────────────────────────────────
  static String? password(String? value, {int minLength = 8}) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < minLength) return 'Password must be at least $minLength characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Password must contain letters and numbers';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  // ── Name ─────────────────────────────────────────────────
  static final _name = RegExp(r"^[a-zA-Z][a-zA-Z.\s]{1,59}$");

  static String? name(String? value, {String label = 'Name'}) {
    if (value == null || value.trim().isEmpty) return 'Enter your ${label.toLowerCase()}';
    final v = value.trim();
    if (v.length < 2) return '$label is too short';
    if (v.length > 60) return '$label is too long';
    if (!_name.hasMatch(v)) return 'Enter a valid $label';
    return null;
  }

  // ── Date of Birth / Age ─────────────────────────────────
  static String? dateOfBirth(DateTime? value, {int minAge = 0, int maxAge = 120}) {
    if (value == null) return 'Select date of birth';
    final now = DateTime.now();
    if (value.isAfter(now)) return 'Date of birth cannot be in the future';
    final hadBirthdayThisYear = now.month > value.month ||
        (now.month == value.month && now.day >= value.day);
    final age = now.year - value.year - (hadBirthdayThisYear ? 0 : 1);
    if (age < minAge) return 'Must be at least $minAge years old';
    if (age > maxAge) return 'Enter a valid date of birth';
    return null;
  }

  // ── Money ────────────────────────────────────────────────
  static String? money(String? value, {double min = 0, double? max, bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Enter an amount' : null;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid amount';
    if (parsed < min) return 'Amount cannot be less than ₹${min.toStringAsFixed(0)}';
    if (max != null && parsed > max) return 'Amount cannot exceed ₹${max.toStringAsFixed(0)}';
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) {
      return 'Enter an amount with up to 2 decimal places';
    }
    return null;
  }

  // ── Appointment / Availability slot ─────────────────────
  /// Returns an error if [start] is not strictly before [end].
  static String? timeRange(DateTime start, DateTime end) {
    if (!start.isBefore(end)) return 'Start time must be before end time';
    return null;
  }

  /// Returns an error if [slot] overlaps any range in [existing].
  static String? noOverlap(
    DateTime slotStart,
    DateTime slotEnd,
    Iterable<(DateTime, DateTime)> existing,
  ) {
    for (final (s, e) in existing) {
      if (slotStart.isBefore(e) && s.isBefore(slotEnd)) {
        return 'This overlaps an existing schedule';
      }
    }
    return null;
  }

  static String? futureDateTime(DateTime? value, {String what = 'appointment'}) {
    if (value == null) return 'Select a date and time';
    if (value.isBefore(DateTime.now())) return 'Cannot select a past time for this $what';
    return null;
  }

  // ── Vehicle (ambulance onboarding) ──────────────────────
  static final _vehicleNumber =
      RegExp(r'^[A-Z]{2}\s?\d{1,2}\s?[A-Z]{1,3}\s?\d{4}$');

  static String? vehicleNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter the vehicle registration number';
    final v = value.trim().toUpperCase();
    if (!_vehicleNumber.hasMatch(v)) return 'Enter a valid vehicle registration number';
    return null;
  }

  static String? documentExpiry(DateTime? value, {String label = 'Document'}) {
    if (value == null) return 'Select $label expiry date';
    if (value.isBefore(DateTime.now())) return '$label has expired — upload a valid document';
    return null;
  }

  // ── File upload ──────────────────────────────────────────
  static String? fileSize(int bytes, {int maxMb = 10}) {
    final maxBytes = maxMb * 1024 * 1024;
    if (bytes > maxBytes) return 'File must be smaller than ${maxMb}MB';
    return null;
  }

  static String? fileType(String extension, List<String> allowed) {
    final ext = extension.toLowerCase().replaceFirst('.', '');
    if (!allowed.map((e) => e.toLowerCase()).contains(ext)) {
      return 'Allowed file types: ${allowed.join(', ')}';
    }
    return null;
  }

  /// Turns a raw exception/error object into a short, non-technical message.
  /// Use at every network/Firebase call site instead of surfacing e.toString().
  static String friendlyError(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('permission-denied')) {
      return "You don't have permission to do that.";
    }
    if (s.contains('network') || s.contains('socket') || s.contains('timeout')) {
      return 'Check your internet connection and try again.';
    }
    if (s.contains('not-found')) {
      return 'The requested item could not be found.';
    }
    if (s.contains('already-exists')) {
      return 'This already exists.';
    }
    return 'Something went wrong. Please try again.';
  }
}
