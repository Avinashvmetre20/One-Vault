import 'dart:async';

import 'package:flutter/services.dart';

abstract final class ClipboardGuard {
  static Timer? _timer;
  static String? _copied;

  static Future<void> copySecret(String value, {Duration ttl = const Duration(seconds: 30)}) async {
    await Clipboard.setData(ClipboardData(text: value));
    _copied = value;
    _timer?.cancel();
    _timer = Timer(ttl, () async {
      final current = await Clipboard.getData('text/plain');
      if (current?.text == _copied) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _copied = null;
    });
  }
}
