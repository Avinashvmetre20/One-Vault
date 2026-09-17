import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

InputDecoration appFieldDecoration({
  required String label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  int? maxLines,
}) {
  final radius = BorderRadius.circular(AppDimensions.radiusMd);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    alignLabelWithHint: maxLines != null && maxLines > 1,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.border),
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
    this.textInputAction,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : 1,
      textInputAction: textInputAction ??
          (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      decoration: appFieldDecoration(
        label: label,
        hint: hint,
        maxLines: maxLines,
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
    return InputDecorator(
      decoration: appFieldDecoration(label: label, hint: hint),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: selected,
          hint: Text(
            hint ?? 'Select',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade600),
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
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InputDecorator(
          decoration: appFieldDecoration(
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
