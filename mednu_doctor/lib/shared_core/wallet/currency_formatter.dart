import 'package:intl/intl.dart';

/// Currency formatting for the Shared Core wallet layer.
///
/// This is genuinely new — the existing earnings screen does raw
/// `'₹$amount'` string interpolation. Defaults to INR to match MedNu's
/// current market, with the format configurable per call for future
/// multi-currency support.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static String format(num amount, {String currency = 'INR'}) {
    switch (currency) {
      case 'INR':
      default:
        return _inr.format(amount);
    }
  }
}
