import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/mpin_storage.dart';
import '../widgets/mpin_pad.dart';

class MpinUnlockScreen extends StatefulWidget {
  const MpinUnlockScreen({super.key});

  @override
  State<MpinUnlockScreen> createState() => _MpinUnlockScreenState();
}

class _MpinUnlockScreenState extends State<MpinUnlockScreen> {
  String _pin = '';
  bool _busy = false;
  bool _error = false;
  String? _message;
  bool _didPromptBiometric = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPromptBiometric) return;
    _didPromptBiometric = true;
    final state = AppScope.of(context);
    if (state.biometricUnlockEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _biometric();
      });
    }
  }

  Future<void> _append(String digit) async {
    if (_busy || _pin.length >= MpinStorage.pinLength) return;
    setState(() {
      _pin += digit;
      _error = false;
      _message = null;
    });
    if (_pin.length == MpinStorage.pinLength) {
      await _submit();
    }
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
      _message = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final state = AppScope.of(context);
    final unlocked = await state.unlockMpin(_pin);
    if (!mounted) return;
    if (unlocked) return;
    final left = state.mpinAttemptsLeft;
    setState(() {
      _busy = false;
      _pin = '';
      _error = true;
      _message = left <= 0
          ? 'Too many attempts. Sign in again.'
          : 'Wrong MPIN. $left attempt${left == 1 ? '' : 's'} left.';
    });
  }

  Future<void> _biometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final unlocked = await AppScope.of(context).unlockWithBiometric();
    if (!mounted) return;
    if (unlocked) return;
    setState(() {
      _busy = false;
      _message = 'Use MPIN to unlock';
    });
  }

  Future<void> _forgot() async {
    final confirmed = await showAppConfirm(
      context,
      title: 'Use password instead?',
      message: 'This signs you out. You can sign in with email and password, then set or keep using MPIN.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !mounted) return;
    await AppScope.of(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final name = state.sessionUser?.name ?? 'there';
    return PopScope(
      canPop: false,
      child: MpinScaffold(
        title: 'Enter MPIN',
        subtitle: 'Welcome back, $name',
        filled: _pin.length,
        error: _error,
        message: _message,
        enabled: !_busy,
        onDigit: _append,
        onBackspace: _backspace,
        onBiometric: state.biometricUnlockEnabled && !_busy ? _biometric : null,
        footer: TextButton(
          onPressed: _busy ? null : _forgot,
          child: const Text('Forgot MPIN? Use password'),
        ),
      ),
    );
  }
}

class MpinSetupScreen extends StatefulWidget {
  const MpinSetupScreen({super.key});

  @override
  State<MpinSetupScreen> createState() => _MpinSetupScreenState();
}

class _MpinSetupScreenState extends State<MpinSetupScreen> {
  String _pin = '';
  String? _first;
  String? _confirmedPin;
  bool _busy = false;
  bool _error = false;
  String? _message;

  bool get _confirming => _first != null;
  bool get _offerFingerprint => _confirmedPin != null;

  Future<void> _append(String digit) async {
    if (_busy || _pin.length >= MpinStorage.pinLength) return;
    setState(() {
      _pin += digit;
      _error = false;
      _message = null;
    });
    if (_pin.length < MpinStorage.pinLength) return;
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _message = 'Re-enter the same MPIN';
      });
      return;
    }
    await _save();
  }

  void _backspace() {
    if (_busy) return;
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = false;
      });
      return;
    }
    if (_confirming) {
      setState(() {
        _first = null;
        _error = false;
        _message = null;
      });
    }
  }

  Future<void> _save() async {
    if (_pin != _first) {
      setState(() {
        _first = null;
        _pin = '';
        _error = true;
        _message = 'MPINs did not match. Try again.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final state = AppScope.of(context);
      if (await state.canUseAppBiometric()) {
        setState(() {
          _busy = false;
          _confirmedPin = _pin;
        });
        return;
      }
      await state.setupMpin(_pin);
    } on MpinException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _first = null;
        _pin = '';
        _error = true;
        _message = error.message;
      });
    }
  }

  Future<void> _enableFingerprint() async {
    if (_confirmedPin == null || _busy) return;
    setState(() => _busy = true);
    final state = AppScope.of(context);
    final ok = await state.promptAppBiometric(
      'Confirm your fingerprint to enable quick unlock',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      showAppSnack(context, 'Fingerprint not verified. Try again or skip.');
      return;
    }
    try {
      await state.setupMpin(_confirmedPin!, enableBiometric: true);
    } on MpinException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    }
  }

  Future<void> _skipFingerprint() async {
    if (_confirmedPin == null || _busy) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).setupMpin(_confirmedPin!);
    } on MpinException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_offerFingerprint) {
      return PopScope(
        canPop: false,
        child: _FingerprintSetupView(
          busy: _busy,
          onEnable: _enableFingerprint,
          onSkip: _skipFingerprint,
        ),
      );
    }
    return PopScope(
      canPop: false,
      child: MpinScaffold(
        title: _confirming ? 'Confirm MPIN' : 'Set MPIN',
        subtitle: _confirming
            ? 'Enter the same 4-digit MPIN again'
            : 'Create a 4-digit MPIN to unlock the app next time',
        filled: _pin.length,
        error: _error,
        message: _message,
        enabled: !_busy,
        onDigit: _append,
        onBackspace: _backspace,
      ),
    );
  }
}

class ChangeMpinScreen extends StatefulWidget {
  const ChangeMpinScreen({super.key});

  @override
  State<ChangeMpinScreen> createState() => _ChangeMpinScreenState();
}

class _ChangeMpinScreenState extends State<ChangeMpinScreen> {
  String _pin = '';
  String? _current;
  String? _next;
  bool _busy = false;
  bool _error = false;
  String? _message;

  String get _title {
    if (_current == null) return 'Current MPIN';
    if (_next == null) return 'New MPIN';
    return 'Confirm MPIN';
  }

  String get _subtitle {
    if (_current == null) return 'Enter your current 4-digit MPIN';
    if (_next == null) return 'Choose a new 4-digit MPIN';
    return 'Re-enter the new MPIN';
  }

  Future<void> _append(String digit) async {
    if (_busy || _pin.length >= MpinStorage.pinLength) return;
    setState(() {
      _pin += digit;
      _error = false;
      _message = null;
    });
    if (_pin.length < MpinStorage.pinLength) return;

    if (_current == null) {
      setState(() {
        _current = _pin;
        _pin = '';
      });
      return;
    }
    if (_next == null) {
      setState(() {
        _next = _pin;
        _pin = '';
      });
      return;
    }
    await _save();
  }

  void _backspace() {
    if (_busy) return;
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_next != null) {
      setState(() => _next = null);
    } else if (_current != null) {
      setState(() => _current = null);
    }
  }

  Future<void> _save() async {
    if (_pin != _next) {
      setState(() {
        _next = null;
        _pin = '';
        _error = true;
        _message = 'New MPINs did not match. Try again.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.of(context).changeMpin(
        currentPin: _current!,
        nextPin: _next!,
      );
      if (!mounted) return;
      showAppSnack(context, 'MPIN updated');
      Navigator.pop(context);
    } on MpinException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _current = null;
        _next = null;
        _pin = '';
        _error = true;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return MpinScaffold(
      appBar: AppBar(title: const Text('Change MPIN')),
      title: _title,
      subtitle: _subtitle,
      filled: _pin.length,
      error: _error,
      message: _message,
      enabled: !_busy,
      onDigit: _append,
      onBackspace: _backspace,
      extra: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.fingerprint),
        title: const Text('Unlock with fingerprint'),
        subtitle: const Text('Use fingerprint instead of MPIN'),
        value: state.biometricUnlockEnabled,
        onChanged: _busy
            ? null
            : (value) async {
                try {
                  await state.setAppBiometricEnabled(value);
                  if (!context.mounted) return;
                  showAppSnack(
                    context,
                    value ? 'Fingerprint unlock enabled' : 'Fingerprint unlock disabled',
                  );
                } on MpinException catch (error) {
                  if (!context.mounted) return;
                  showAppSnack(context, error.message);
                }
              },
      ),
    );
  }
}

class _FingerprintSetupView extends StatelessWidget {
  const _FingerprintSetupView({
    required this.busy,
    required this.onEnable,
    required this.onSkip,
  });

  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppDimensions.pagePaddingAuth,
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.wash(context),
                ),
                child: const Icon(Icons.fingerprint, size: 36, color: AppColors.primary),
              ),
              AppDimensions.sectionGap,
              Text(
                'Unlock with fingerprint',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use your fingerprint next time instead of entering MPIN. You can still use MPIN anytime.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted(context),
                  height: 1.4,
                ),
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Enable fingerprint',
                icon: Icons.fingerprint,
                loading: busy,
                onPressed: busy ? null : onEnable,
              ),
              TextButton(
                onPressed: busy ? null : onSkip,
                child: const Text('Maybe later'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

