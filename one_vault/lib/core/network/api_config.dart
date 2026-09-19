import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const productionUrl = 'https://one-vault-wgdu.onrender.com';
  static const _port = 3000;
  static const loopbackUrl = 'http://127.0.0.1:$_port';
  static const lanUrl = 'http://192.168.0.116:$_port';
  static const emulatorUrl = 'http://10.0.2.2:$_port';
  static const _fromEnv = String.fromEnvironment('API_BASE_URL');
  static String? _resolved;

  static String get baseUrl {
    if (_resolved != null) return _resolved!;
    if (_fromEnv.isNotEmpty) return _fromEnv;
    if (kReleaseMode) return productionUrl;
    return loopbackUrl;
  }

  static List<String> get candidateUrls {
    if (kReleaseMode || _fromEnv.isNotEmpty) return [baseUrl];
    return const [
      loopbackUrl,
      lanUrl,
      emulatorUrl,
      'http://localhost:$_port',
    ];
  }

  static void use(String url) => _resolved = url;
}
