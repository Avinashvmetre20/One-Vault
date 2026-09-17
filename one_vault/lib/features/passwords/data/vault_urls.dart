abstract final class VaultUrls {
  static String normalize(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasScheme) return raw;
    return uri.toString();
  }

  static String domain(String input) {
    final uri = launchUri(input);
    var host = uri?.host ?? '';
    if (host.startsWith('www.')) host = host.substring(4);
    return host.toLowerCase();
  }

  static Uri? launchUri(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }
}
