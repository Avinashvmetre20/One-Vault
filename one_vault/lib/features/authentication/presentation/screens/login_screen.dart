import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../data/auth_models.dart';
import '../../../../shared/helpers/snack.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      showAppSnack(context, 'Email and password are required');
      return;
    }

    setState(() => _loading = true);
    try {
      await AppScope.of(context).login(email: email, password: password);
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
      title: 'Welcome back',
      subtitle: 'Sign in to access your vault.',
      children: [
        AuthTextField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _password,
          label: 'Password',
          obscureText: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
        ),
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Log in',
          loading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        AuthFooter(
          prompt: "Don't have an account?",
          actionLabel: 'Register',
          onPressed: _loading ? null : () => context.go(AppRoutes.register),
        ),
      ],
    );
  }
}
