abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');
  static const productionUrl = 'https://one-vault-wgdu.onrender.com';

  static String get baseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    return productionUrl;
  }
}
