import 'package:flutter/services.dart';

import '../../../shared/models/models.dart';

abstract final class AutofillBridge {
  static const _channel = MethodChannel('onevault/autofill');

  static Future<List<Map<String, String>>> pendingSaves() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('pendingSaves');
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map)
            {
              for (final item in entry.entries)
                item.key.toString(): item.value?.toString() ?? '',
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> syncCredentials(List<PasswordItem> items) async {
    try {
      await _channel.invokeMethod(
        'syncCredentials',
        [
          for (final item in items)
            {
              'id': item.id,
              'title': item.title,
              'username': item.username,
              'password': item.password,
              'domain': item.domain,
              'website': item.website,
            },
        ],
      );
    } catch (_) {}
  }

  static Future<void> clearCredentials() async {
    try {
      await _channel.invokeMethod('clearCredentials');
    } catch (_) {}
  }

  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<bool> isChromeThirdParty() async {
    try {
      return await _channel.invokeMethod<bool>('isChromeThirdParty') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openChromeSettings() async {
    try {
      await _channel.invokeMethod('openChromeSettings');
    } catch (_) {}
  }
}
