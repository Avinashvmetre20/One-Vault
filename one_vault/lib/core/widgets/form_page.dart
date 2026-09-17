import 'package:flutter/material.dart';

class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.submitting = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + bottomInset),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ...children,
            const SizedBox(height: 24),
            FilledButton(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(submitLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
