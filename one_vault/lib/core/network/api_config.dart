import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    if (kIsWeb) return 'http://localhost:3000';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Real phone over USB/wireless adb. Requires: adb reverse tcp:3000 tcp:3000
        // Emulator instead: --dart-define=API_BASE_URL=http://10.0.2.2:3000
        return 'http://127.0.0.1:3000';
      default:
        return 'http://localhost:3000';
    }
  }
}
