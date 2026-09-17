import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../data/mpin_storage.dart';

class MpinScaffold extends StatelessWidget {
  const MpinScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onDigit,
    required this.onBackspace,
    this.error = false,
    this.message,
    this.enabled = true,
    this.footer,
    this.appBar,
    this.onBiometric,
    this.extra,
  });

  final String title;
  final String subtitle;
  final int filled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool error;
  final String? message;
  final bool enabled;
  final Widget? footer;
  final PreferredSizeWidget? appBar;
  final VoidCallback? onBiometric;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pad = AppDimensions.horizontalPadding(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final midGap = height * 0.10;
            final bottomGap = height * 0.05;
            final keypadHeight = height * 0.40;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Column(
                children: [
                  const Spacer(),
                  if (appBar == null) ...[
                    const _BrandMark(),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PinSlots(filled: filled, error: error),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 20,
                    child: Text(
                      message ?? '',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: error ? AppColors.danger : AppColors.muted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (extra != null) extra!,
                  SizedBox(height: midGap),
                  SizedBox(
                    height: keypadHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: _MpinKeypad(
                            onDigit: onDigit,
                            onBackspace: onBackspace,
                            enabled: enabled,
                            onBiometric: onBiometric,
                          ),
                        ),
                        if (footer != null) footer!,
                      ],
                    ),
                  ),
                  SizedBox(height: bottomGap),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
    );
  }
}

class _PinSlots extends StatelessWidget {
  const _PinSlots({required this.filled, required this.error});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final active = error ? AppColors.danger : AppColors.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < MpinStorage.pinLength; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 46,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: Border.all(
                color: i < filled || error ? active : AppColors.line(context),
                width: i < filled || error ? 1.6 : 1,
              ),
            ),
            child: i < filled
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

class _MpinKeypad extends StatelessWidget {
  const _MpinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.enabled,
    this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  final VoidCallback? onBiometric;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['bio', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const vGap = 18.0;
        final keyHeight = (constraints.maxHeight - vGap * 3) / 4;
        if (keyHeight <= 0) return const SizedBox.shrink();
        final keyWidth = math.min(
          (constraints.maxWidth - 32) / 3,
          keyHeight * 1.28,
        );
        final hGap = math.max(
          20.0,
          (constraints.maxWidth - keyWidth * 3) / 4,
        );
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < _rows.length; r++) ...[
                if (r > 0) const SizedBox(height: vGap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var c = 0; c < _rows[r].length; c++) ...[
                      if (c > 0) SizedBox(width: hGap),
                      SizedBox(
                        width: keyWidth,
                        height: keyHeight,
                        child: _Key(
                          label: _rows[r][c] == 'bio' || _rows[r][c] == 'back'
                              ? null
                              : _rows[r][c],
                          icon: _rows[r][c] == 'back'
                              ? Icons.backspace_outlined
                              : _rows[r][c] == 'bio' && onBiometric != null
                              ? Icons.fingerprint
                              : null,
                          enabled: enabled,
                          onTap: _rows[r][c] == 'back'
                              ? onBackspace
                              : _rows[r][c] == 'bio'
                              ? onBiometric
                              : () => onDigit(_rows[r][c]),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.enabled,
    this.onTap,
  });

  final String? label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null && icon == null && (label == null || label!.isEmpty)) {
      return const SizedBox.expand();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: !enabled || onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Center(
          child: icon != null
              ? Icon(icon, color: AppColors.primary, size: 26)
              : Text(
                  label ?? '',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
