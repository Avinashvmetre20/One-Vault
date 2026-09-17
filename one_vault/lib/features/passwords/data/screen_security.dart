import 'package:flutter/services.dart';

abstract final class ScreenSecurity {
  static const _channel = MethodChannel('onevault/screen_security');

  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', secure);
    } catch (_) {}
  }
}
