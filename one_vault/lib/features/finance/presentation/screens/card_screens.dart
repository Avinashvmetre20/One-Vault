import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';
import '../../data/finance_models.dart';
import '../../data/finance_service.dart';
import '../widgets/money_widgets.dart';
import 'finance_screens.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> with FinanceTickReload {
  List<MoneyCard> _items = [];
  bool _loading = true;
  String? _error;

  FinanceService get _api => AppScope.of(context).finance;

  @override
  Future<void> reloadFinanceData() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final items = await _api.cards();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final debit = _items.where((item) => item.cardType == CardType.debit).toList();
    final credit = _items.where((item) => item.cardType == CardType.credit).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Cards')),
      floatingActionButton: ShellFab(
        heroTag: 'fab-cards',
        tooltip: 'Add card',
        onPressed: () async {
          await context.push(AppRoutes.cardNew);
          if (mounted) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppDimensions.pagePaddingFab,
          children: [
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_error != null)
              MoneyErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.credit_card,
                title: 'No cards added',
                subtitle: 'Add a debit or credit card. Only the last 4 digits are stored.',
                action: FilledButton(
                  onPressed: () => context.push(AppRoutes.cardNew),
                  child: const Text('Add Card'),
                ),
              )
            else ...[
              if (debit.isNotEmpty) ...[
                const SectionTitle(title: 'Debit cards'),
                const SizedBox(height: 8),
                for (final item in debit) _tile(item),
              ],
              if (credit.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionTitle(title: 'Credit cards'),
                const SizedBox(height: 8),
                for (final item in credit) _tile(item),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(MoneyCard item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTileCard(
        icon: Icons.credit_card,
        title: item.name,
        subtitle: item.isCredit
            ? 'Outstanding ${Formatters.inrPaise(item.currentOutstandingPaise)}'
            : (item.linkedAccountName == null ? 'Not linked' : 'Linked: ${item.linkedAccountName}'),
        trailing: item.isCredit && item.availableCreditPaise != null
            ? Text(
                Formatters.inrPaise(item.availableCreditPaise!),
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : Text(maskedLastFour(item.lastFourDigits)),
        onTap: () async {
          await context.push(AppRoutes.cardDetail(item.id));
          if (mounted) _load();
        },
      ),
    );
  }
}

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  MoneyCard? _card;
  List<MoneyTransaction> _recent = [];
  bool _loading = true;
  String? _error;

  FinanceService get _api => AppScope.of(context).finance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.card(widget.id),
        _api.transactions(cardId: widget.id, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _card = results[0] as MoneyCard;
        _recent = (results[1] as MoneyTxnPage).items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return Scaffold(
      appBar: AppBar(
        title: Text(card?.name ?? 'Card'),
        actions: [
          if (card != null)
            IconButton(
              onPressed: () async {
                await context.push(AppRoutes.cardEdit(card.id));
                if (mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? MoneyErrorState(message: _error!, onRetry: _load)
          : card == null
          ? const EmptyState(icon: Icons.credit_card, title: 'Not found', subtitle: 'This card was removed.')
          : ListView(
              padding: AppDimensions.pagePadding,
              children: [
                InfoRow(label: 'Type', value: card.cardType.label),
                if (card.lastFourDigits != null) InfoRow(label: 'Card', value: maskedLastFour(card.lastFourDigits)),
                if (card.linkedAccountName != null) InfoRow(label: 'Linked account', value: card.linkedAccountName!),
                if (card.isCredit) ...[
                  if (card.creditLimitPaise != null)
                    InfoRow(label: 'Credit limit', value: Formatters.inrPaise(card.creditLimitPaise!)),
                  InfoRow(label: 'Outstanding', value: Formatters.inrPaise(card.currentOutstandingPaise)),
                  if (card.availableCreditPaise != null)
                    InfoRow(label: 'Available', value: Formatters.inrPaise(card.availableCreditPaise!)),
                  if (card.statementDay != null) InfoRow(label: 'Statement day', value: '${card.statementDay}'),
                  if (card.dueDay != null) InfoRow(label: 'Payment due day', value: '${card.dueDay}'),
                ],
                const SizedBox(height: 8),
                const SectionTitle(title: 'Recent transactions'),
                const SizedBox(height: 8),
                if (_recent.isEmpty)
                  Text('No card transactions yet.', style: TextStyle(color: AppColors.muted(context)))
                else
                  for (final item in _recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ListTileCard(
                        icon: Icons.receipt_long_outlined,
                        title: item.title,
                        subtitle: item.type.label,
                        trailing: Text(Formatters.inrPaise(item.amountPaise)),
                        onTap: () => context.push(AppRoutes.transactionDetail(item.id)),
                      ),
                    ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showAppConfirm(
                      context,
                      title: 'Archive this card?',
                      message: 'Historical transactions stay. It will no longer appear as a source.',
                      confirmLabel: 'Archive',
                    );
                    if (!confirmed || !mounted) return;
                    try {
                      await _api.archiveCard(card.id);
                      if (!mounted) return;
                      showAppSnack(context, 'Card archived');
                      context.pop();
                    } catch (error) {
                      if (mounted) showAppSnack(context, error.toString());
                    }
                  },
                  child: const Text('Archive', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
    );
  }
}

class CardFormScreen extends StatefulWidget {
  const CardFormScreen({super.key, this.id});

  final int? id;

  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> {
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _lastFour = TextEditingController();
  final _limit = TextEditingController();
  final _outstanding = TextEditingController();
  final _statementDay = TextEditingController();
  final _dueDay = TextEditingController();
  final _notes = TextEditingController();
  CardType _type = CardType.debit;
  int? _linkedAccountId;
  List<MoneyAccount> _accounts = [];
  bool _saving = false;

  FinanceService get _api => AppScope.of(context).finance;
  bool get _isEdit => widget.id != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final accounts = await _api.accounts();
      MoneyCard? existing;
      if (widget.id != null) existing = await _api.card(widget.id!);
      if (!mounted) return;
      setState(() {
        _accounts = accounts.where((item) => item.kind == AccountKind.bank).toList();
        if (existing != null) {
          _name.text = existing.name;
          _issuer.text = existing.issuerName;
          _lastFour.text = existing.lastFourDigits ?? '';
          _type = existing.cardType;
          _linkedAccountId = existing.linkedAccountId;
          if (existing.creditLimitPaise != null) _limit.text = paiseToApi(existing.creditLimitPaise!);
          _outstanding.text = paiseToApi(existing.openingOutstandingPaise);
          if (existing.statementDay != null) _statementDay.text = '${existing.statementDay}';
          if (existing.dueDay != null) _dueDay.text = '${existing.dueDay}';
          _notes.text = existing.notes;
        }
      });
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _lastFour.dispose();
    _limit.dispose();
    _outstanding.dispose();
    _statementDay.dispose();
    _dueDay.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAppSnack(context, 'Card name is required');
      return;
    }
    if (_type == CardType.credit && _limit.text.trim().isEmpty) {
      showAppSnack(context, 'Credit limit is required');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'cardType': _type.api,
        'issuerName': _issuer.text.trim(),
        'lastFourDigits': _lastFour.text.replaceAll(RegExp(r'\D'), ''),
        'linkedAccountId': _linkedAccountId,
        'creditLimit': _type == CardType.credit ? _limit.text.trim() : null,
        'openingOutstanding': _type == CardType.credit ? (_outstanding.text.trim().isEmpty ? '0.00' : _outstanding.text.trim()) : '0.00',
        'statementDay': int.tryParse(_statementDay.text.trim()),
        'dueDay': int.tryParse(_dueDay.text.trim()),
        'notes': _notes.text.trim(),
      };
      if (_isEdit) {
        await _api.updateCard(widget.id!, body);
      } else {
        await _api.createCard(body);
      }
      if (!mounted) return;
      showAppSnack(context, _isEdit ? 'Card updated' : 'Card added');
      context.pop();
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _isEdit ? 'Edit card' : 'Add card',
      submitting: _saving,
      onSubmit: _save,
      children: [
        AppDropdown<CardType>(
          label: 'Card type',
          value: _type,
          items: CardType.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _type = value ?? _type),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _name, label: 'Card name'),
        AppDimensions.fieldGap,
        AppTextField(controller: _issuer, label: 'Issuer / bank'),
        AppDimensions.fieldGap,
        AppTextField(
          controller: _lastFour,
          label: 'Last 4 digits',
          keyboardType: TextInputType.number,
          maxLength: 4,
        ),
        AppDimensions.fieldGap,
        AppDropdown<int>(
          label: _type == CardType.debit ? 'Linked account' : 'Default payment account',
          value: _linkedAccountId,
          hint: 'Optional',
          items: _accounts
              .map((item) => DropdownMenuItem(value: item.id, child: Text(item.displayName)))
              .toList(),
          onChanged: (value) => setState(() => _linkedAccountId = value),
        ),
        if (_type == CardType.credit) ...[
          AppDimensions.fieldGap,
          AppTextField(
            controller: _limit,
            label: 'Credit limit (₹)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          AppDimensions.fieldGap,
          AppTextField(
            controller: _outstanding,
            label: 'Current outstanding (₹)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          AppDimensions.fieldGap,
          AppTextField(controller: _statementDay, label: 'Statement day (1-31)', keyboardType: TextInputType.number),
          AppDimensions.fieldGap,
          AppTextField(controller: _dueDay, label: 'Payment due day (1-31)', keyboardType: TextInputType.number),
        ],
        AppDimensions.fieldGap,
        AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
      ],
    );
  }
}
