import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../features/passwords/data/autofill_bridge.dart';
import '../../../../features/passwords/data/vault_storage.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/mpin_storage.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final security = state.security;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: AppDimensions.pagePaddingForm,
        children: [
          ListTile(
            title: const Text('Change MPIN'),
            subtitle: const Text('4-digit lock stored only on this phone'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.pinSetup),
          ),
          SwitchListTile(
            title: const Text('Unlock with fingerprint'),
            subtitle: const Text('Use fingerprint instead of MPIN'),
            value: state.biometricUnlockEnabled,
            onChanged: (value) async {
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
          SwitchListTile(
            title: const Text('Hide sensitive data'),
            subtitle: const Text('Mask PAN, Aadhaar, and other IDs'),
            value: security.hideSensitiveData,
            onChanged: (value) {
              state.updateSecurity(security.copyWith(hideSensitiveData: value));
            },
          ),
          SwitchListTile(
            title: const Text('Biometric vault unlock'),
            subtitle: const Text('Use fingerprint or face after the vault is unlocked once'),
            value: state.vault.biometricEnabled,
            onChanged: (value) async {
              if (value && !state.vault.isUnlocked) {
                showAppSnack(context, 'Unlock the vault first');
                return;
              }
              await state.vault.setBiometricEnabled(value);
              if (!context.mounted) return;
              showAppSnack(
                context,
                value ? 'Biometric unlock enabled' : 'Biometric unlock disabled',
              );
            },
          ),
          ListTile(
            title: const Text('Vault auto-lock'),
            subtitle: Text(state.vault.autoLock.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showModalBottomSheet<VaultAutoLock>(
                context: context,
                builder: (context) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in VaultAutoLock.values)
                      ListTile(
                        title: Text(option.label),
                        selected: option == state.vault.autoLock,
                        onTap: () => Navigator.pop(context, option),
                      ),
                  ],
                ),
              );
              if (selected == null) return;
              await state.vault.setAutoLock(selected);
            },
          ),
          ListTile(
            title: const Text('Replace Google Password Manager'),
            subtitle: const Text('Two settings are required: Android Autofill + Chrome Autofill'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.autofillSetup),
          ),
        ],
      ),
    );
  }
}

class AutofillSetupScreen extends StatefulWidget {
  const AutofillSetupScreen({super.key});

  @override
  State<AutofillSetupScreen> createState() => _AutofillSetupScreenState();
}

class _AutofillSetupScreenState extends State<AutofillSetupScreen> with WidgetsBindingObserver {
  bool _androidEnabled = false;
  bool _chromeEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final android = await AutofillBridge.isEnabled();
    final chrome = await AutofillBridge.isChromeThirdParty();
    if (!mounted) return;
    setState(() {
      _androidEnabled = android;
      _chromeEnabled = chrome;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autofill setup')),
      body: ListView(
        padding: AppDimensions.pagePaddingForm,
        children: [
          Text(
            'Chrome still shows Google Password Manager until BOTH steps are done.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _StepCard(
            number: '1',
            title: 'Set OneVault as Android Autofill',
            done: _androidEnabled,
            body:
                'Phone Settings → Passwords, passkeys & accounts → Preferred service → OneVault',
            actionLabel: _androidEnabled ? 'Change Android Autofill' : 'Open Android Autofill settings',
            onPressed: () => AutofillBridge.openSettings(),
          ),
          const SizedBox(height: 12),
          _StepCard(
            number: '2',
            title: 'Tell Chrome to use another service',
            done: _chromeEnabled,
            body:
                'Chrome → Settings → Autofill services → Autofill using another service → Restart Chrome.\n\nUntil this is on, Chrome will keep showing “Save password? Google Password Manager”.',
            actionLabel: _chromeEnabled ? 'Open Chrome Autofill settings' : 'Open Chrome Autofill settings',
            onPressed: () => AutofillBridge.openChromeSettings(),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_androidEnabled && _chromeEnabled)
            const Text('Both steps are on. Log in on LeetCode again and OneVault should ask to save.')
          else
            const Text('Google’s save bubble will keep appearing until step 2 is completed.'),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.done,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
  });

  final String number;
  final String title;
  final bool done;
  final String body;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done ? Colors.green : Theme.of(context).colorScheme.primary,
                  child: Text(
                    done ? '✓' : number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
