abstract final class ApiConfig {
  static const productionUrl = 'https://one-vault-wgdu.onrender.com';
  static const _port = 3000;
  static const loopbackUrl = 'http://127.0.0.1:$_port';
  static const lanUrl = 'http://192.168.0.116:$_port';
  static const emulatorUrl = 'http://10.0.2.2:$_port';
  static const _fromEnv = String.fromEnvironment('API_BASE_URL');
  static String? _resolved;

  /// USB phone: `adb reverse tcp:3000 tcp:3000` then loopback.
  /// Override with `--dart-define=API_BASE_URL=...`
  static String get baseUrl =>
      _resolved ?? (_fromEnv.isNotEmpty ? _fromEnv : loopbackUrl);

  static List<String> get candidateUrls {
    if (_fromEnv.isNotEmpty) return [_fromEnv];
    return const [
      loopbackUrl,
      lanUrl,
      emulatorUrl,
      'http://localhost:$_port',
    ];
  }

  static void use(String url) => _resolved = url;
}