import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  /// This PC's Wi-Fi address. Used only if you pass
  /// --dart-define=API_BASE_URL=http://192.168.20.113:3000
  static const lanUrl = 'http://192.168.20.113:3000';

  static String get baseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    if (kIsWeb) return 'http://localhost:3000';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // 10.0.2.2 is the host machine from the Android emulator.
        // 127.0.0.1 on the emulator is the emulator itself, not this PC.
        return 'http://10.0.2.2:3000';
      default:
        return 'http://localhost:3000';
    }
  }
}
