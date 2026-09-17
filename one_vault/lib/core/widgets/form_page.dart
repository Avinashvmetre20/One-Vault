import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';
import 'app_button.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: AppDimensions.pagePaddingForm,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ...children,
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: submitLabel,
              loading: submitting,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
