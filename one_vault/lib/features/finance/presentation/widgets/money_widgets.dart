import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../data/finance_models.dart';

class MoneyErrorState extends StatelessWidget {
  const MoneyErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Could not load',
      subtitle: message,
      action: FilledButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

class MoneyAmountText extends StatelessWidget {
  const MoneyAmountText({
    super.key,
    required this.paise,
    this.credit = false,
    this.signed = false,
  });

  final int paise;
  final bool credit;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final prefix = signed ? (credit ? '+' : '-') : '';
    final color = signed ? (credit ? AppColors.success : AppColors.danger) : null;
    return Text(
      '$prefix${Formatters.inrPaise(paise.abs())}',
      style: TextStyle(fontWeight: FontWeight.w700, color: color),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.item, this.onTap});

  final MoneyTransaction item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTileCard(
      icon: item.type.isCredit
          ? Icons.south_west
          : item.type.isTransfer
          ? Icons.swap_horiz
          : Icons.north_east,
      title: item.title,
      subtitle: [
        if (item.categoryName != null && item.categoryName!.isNotEmpty) item.categoryName!,
        item.sourceLabel,
      ].where((part) => part.isNotEmpty).join(' · '),
      trailing: MoneyAmountText(
        paise: item.amountPaise,
        credit: item.showsAsCredit,
        signed: !item.type.isTransfer,
      ),
      onTap: onTap,
    );
  }
}
