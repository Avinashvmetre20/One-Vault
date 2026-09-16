import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../shared/helpers/snack.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final security = state.security;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          SwitchListTile(
            title: const Text('App PIN'),
            subtitle: Text(security.pinEnabled ? 'PIN is on' : 'PIN is off'),
            value: security.pinEnabled,
            onChanged: (value) {
              if (value) {
                context.push(AppRoutes.pinSetup);
              } else {
                state.updateSecurity(security.copyWith(pinEnabled: false, pin: ''));
                showAppSnack(context, 'PIN disabled');
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
        ],
      ),
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set PIN')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '4-6 digit PIN'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Confirm PIN'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_pin.text.length < 4 || _pin.text != _confirm.text) {
                showAppSnack(context, 'PINs must match and be at least 4 digits');
                return;
              }
              final state = AppScope.of(context);
              state.updateSecurity(
                state.security.copyWith(pinEnabled: true, pin: _pin.text),
              );
              showAppSnack(context, 'PIN saved');
              context.pop();
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }
}
