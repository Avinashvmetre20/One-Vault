import 'package:flutter/material.dart';

class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'Save',
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSubmit;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            ...children,
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}
