import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

InputDecoration appFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  int? maxLines,
  int? maxLength,
}) {
  final radius = BorderRadius.circular(AppDimensions.radiusMd);
  final fill = AppColors.card(context);
  final line = AppColors.line(context);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    alignLabelWithHint: maxLines != null && maxLines > 1,
    counterText: maxLength == null ? '' : null,
    filled: true,
    fillColor: fill,
    labelStyle: TextStyle(color: AppColors.muted(context)),
    hintStyle: TextStyle(color: AppColors.muted(context)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    ),
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.onSubmitted,
    this.onChanged,
    this.obscureText = false,
    this.enabled = true,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: obscureText ? 1 : maxLines,
      minLines: maxLines > 1 ? maxLines : 1,
      maxLength: maxLength,
      obscureText: obscureText,
      enabled: enabled,
      autofillHints: autofillHints,
      textInputAction: textInputAction ??
          (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: appFieldDecoration(
        context,
        label: label,
        hint: hint,
        maxLines: maxLines,
        maxLength: maxLength,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final selected = items.any((item) => item.value == value) ? value : null;
    final muted = AppColors.muted(context);
    return InputDecorator(
      decoration: appFieldDecoration(context, label: label, hint: hint),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: selected,
          dropdownColor: AppColors.card(context),
          hint: Text(hint ?? 'Select', style: TextStyle(color: muted)),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card(context),
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InputDecorator(
          decoration: appFieldDecoration(
            context,
            label: label,
            suffixIcon: Icon(icon, color: AppColors.primary),
          ),
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
