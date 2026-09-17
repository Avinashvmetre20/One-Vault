import 'package:flutter/material.dart';

class AppFilterChips<T> extends StatelessWidget {
  const AppFilterChips({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.allLabel = 'All',
  });

  final T? value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(allLabel),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          ...options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(labelOf(option)),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
