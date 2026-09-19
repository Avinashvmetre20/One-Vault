import 'package:intl/intl.dart';

abstract final class Formatters {
  static String inr(num amount) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(amount);
  }

  static String inrPaise(int paise) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = NumberFormat.decimalPattern('en_IN').format(abs ~/ 100);
    final remainder = abs % 100;
    final body = remainder == 0 ? rupees : '$rupees.${remainder.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}₹$body';
  }

  static String date(DateTime date, {String pattern = 'dd MMM yyyy'}) {
    return DateFormat(pattern).format(date.toLocal());
  }

  static String dateTime(DateTime date) {
    return DateFormat('dd MMM yyyy, h:mm a').format(date.toLocal());
  }

  static String time(DateTime date) {
    return DateFormat('h:mm a').format(date.toLocal());
  }

  static String weekdayDate(DateTime date) {
    return DateFormat('EEEE, d MMMM yyyy').format(date.toLocal());
  }

  static String maskId(String value, {int visible = 4}) {
    if (value.length <= visible) return value;
    return '${'*' * (value.length - visible)}${value.substring(value.length - visible)}';
  }
}
