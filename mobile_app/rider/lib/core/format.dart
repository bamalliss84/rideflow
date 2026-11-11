import 'package:intl/intl.dart';

import 'app_settings.dart';

/// Integer minor units -> "1,500 ر.ي". Latin digits everywhere (unambiguous amounts and phone numbers, same convention
/// as the admin portal). The operator's symbol for its own currency (D051), the code for any other.
String formatMoney(int? minor, String currency, int minorUnits) {
  if (minor == null) return '—';
  final value = minor / _pow10(minorUnits);
  final digits = value == value.roundToDouble() ? 0 : minorUnits;
  final f = NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: digits);
  return '${f.format(value)} ${currentSettings.region.symbolFor(currency)}'.trim();
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
String formatTime(DateTime? d) => d == null ? '—' : DateFormat('HH:mm', 'en').format(d);
String formatDate(DateTime? d) => d == null ? '—' : DateFormat('yyyy/MM/dd', 'en').format(d);

/// Metres in the operator's unit (D051): km and m, or mi and ft.
String formatDistance(int? meters) {
  if (meters == null) return '—';
  if (currentSettings.region.distanceUnit == 'mi') {
    final miles = meters / 1609.344;
    return miles >= 0.1 ? '${miles.toStringAsFixed(1)} mi' : '${(meters * 3.28084).round()} ft';
  }
  return meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
