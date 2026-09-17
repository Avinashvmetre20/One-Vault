import 'dart:math';

import '../../../shared/models/models.dart';

enum PasswordStrength { weak, medium, strong }

abstract final class PasswordGenerator {
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const _numbers = '23456789';
  static const _symbols = r'!@#$%^&*()-_=+';
  static const _ambiguous = 'Il1O0';

  static String generate({
    required int length,
    bool upper = true,
    bool lower = true,
    bool numbers = true,
    bool symbols = true,
    bool excludeAmbiguous = true,
  }) {
    final pools = <String>[];
    if (upper) pools.add(_upper);
    if (lower) pools.add(_lower);
    if (numbers) pools.add(_numbers);
    if (symbols) pools.add(_symbols);
    var alphabet = pools.join();
    if (!excludeAmbiguous) alphabet += _ambiguous;
    if (alphabet.isEmpty) alphabet = _lower;

    final random = Random.secure();
    final chars = <String>[];
    for (final pool in pools) {
      chars.add(pool[random.nextInt(pool.length)]);
    }
    while (chars.length < length) {
      chars.add(alphabet[random.nextInt(alphabet.length)]);
    }
    chars.shuffle(random);
    return chars.take(length).join();
  }

  static PasswordStrength strength(String password) {
    if (password.length < 8) return PasswordStrength.weak;
    final lower = password.toLowerCase();
    const weakPatterns = [
      'password',
      '123456',
      'qwerty',
      'letmein',
      '111111',
      'abc123',
    ];
    if (weakPatterns.any(lower.contains)) return PasswordStrength.weak;
    if (_isSequential(password) || _isRepeated(password)) {
      return PasswordStrength.weak;
    }

    var classes = 0;
    if (password.contains(RegExp(r'[A-Z]'))) classes++;
    if (password.contains(RegExp(r'[a-z]'))) classes++;
    if (password.contains(RegExp(r'[0-9]'))) classes++;
    if (password.contains(RegExp(r'[^A-Za-z0-9]'))) classes++;

    if (password.length >= 16 && classes >= 3) return PasswordStrength.strong;
    if (password.length >= 12 && classes >= 3) return PasswordStrength.strong;
    if (password.length >= 10 && classes >= 2) return PasswordStrength.medium;
    return PasswordStrength.weak;
  }

  static String label(PasswordStrength value) => switch (value) {
    PasswordStrength.strong => 'Strong',
    PasswordStrength.medium => 'Medium',
    PasswordStrength.weak => 'Weak',
  };

  static bool _isRepeated(String password) {
    if (password.length < 4) return false;
    return RegExp(r'^(.)\1+$').hasMatch(password);
  }

  static bool _isSequential(String password) {
    const sequences = ['abcdefghijklmnopqrstuvwxyz', '0123456789', 'qwertyuiop'];
    final lower = password.toLowerCase();
    for (final sequence in sequences) {
      for (var i = 0; i <= sequence.length - 4; i++) {
        final chunk = sequence.substring(i, i + 4);
        if (lower.contains(chunk) || lower.contains(chunk.split('').reversed.join())) {
          return true;
        }
      }
    }
    return false;
  }
}

class PasswordHealthSummary {
  const PasswordHealthSummary({
    required this.weak,
    required this.reused,
    required this.old,
    required this.strong,
  });

  final int weak;
  final int reused;
  final int old;
  final int strong;

  factory PasswordHealthSummary.from(List<PasswordItem> items) {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.password] = (counts[item.password] ?? 0) + 1;
    }
    var weak = 0;
    var reused = 0;
    var old = 0;
    var strong = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    for (final item in items) {
      final score = PasswordGenerator.strength(item.password);
      if (score == PasswordStrength.weak) weak++;
      if (score == PasswordStrength.strong) strong++;
      if ((counts[item.password] ?? 0) > 1) reused++;
      if (item.updatedAt.isBefore(cutoff)) old++;
    }
    return PasswordHealthSummary(weak: weak, reused: reused, old: old, strong: strong);
  }
}
