import 'package:intl/intl.dart';

/// Integer minor units -> "1,500 YER". Latin digits everywhere (unambiguous amounts and phone numbers,
/// same convention as the admin portal); the currency code avoids symbol ambiguity.
String formatMoney(int? minor, String currency, int minorUnits) {
  if (minor == null) return '—';
  final value = minor / _pow10(minorUnits);
  final digits = value == value.roundToDouble() ? 0 : minorUnits;
  final f = NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: digits);
  return '${f.format(value)} $currency'.trim();
}

/// Minor units -> plain decimal for inputs (150000 with 2 units -> "1500").
String minorToInput(int minor, int minorUnits) {
  final value = minor / _pow10(minorUnits);
  return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(minorUnits);
}

/// Plain decimal input -> minor units; null when empty, invalid or not positive.
int? inputToMinor(String text, int minorUnits) {
  final value = double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));
  if (value == null || value <= 0) return null;
  return (value * _pow10(minorUnits)).round();
}

String formatDateTime(DateTime? d) => d == null ? '—' : DateFormat('yyyy/MM/dd HH:mm', 'en').format(d);
String formatDate(DateTime? d) => d == null ? '—' : DateFormat('yyyy/MM/dd', 'en').format(d);

String formatDistance(int? meters) => meters == null ? '—' : (meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m');

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
