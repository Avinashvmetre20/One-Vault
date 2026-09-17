import 'package:flutter_timezone/flutter_timezone.dart';

abstract final class DeviceTimeZone {
  static const fallback = 'Asia/Kolkata';
  static String current = fallback;

  static Future<void> init() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final name = info.identifier.trim();
      if (name.isNotEmpty) current = name;
    } catch (_) {
      current = fallback;
    }
  }
}
