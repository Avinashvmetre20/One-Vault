import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../data/auth_models.dart';
import '../../../../shared/helpers/snack.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;

    if (name.length < 2) {
      showAppSnack(context, 'Name must be at least 2 characters');
      return;
    }
    if (email.isEmpty) {
      showAppSnack(context, 'A valid email is required');
      return;
    }
    if (password.length < 6) {
      showAppSnack(context, 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      showAppSnack(context, 'Passwords do not match');
      return;
    }

    setState(() => _loading = true);
    try {
      await AppScope.of(context).register(
        name: name,
        email: email,
        password: password,
        phone: phone.isEmpty ? null : phone,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Register to start using OneVault.',
      children: [
        AuthTextField(
          controller: _name,
          label: 'Full name',
          keyboardType: TextInputType.name,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _phone,
          label: 'Phone (optional)',
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _password,
          label: 'Password',
          obscureText: _obscurePassword,
          onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _confirm,
          label: 'Confirm password',
          obscureText: _obscureConfirm,
          onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Create account',
          loading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        AuthFooter(
          prompt: 'Already have an account?',
          actionLabel: 'Log in',
          onPressed: _loading ? null : () => context.go(AppRoutes.login),
        ),
      ],
    );
  }
}
