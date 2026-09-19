class FinanceException implements Exception {
  const FinanceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

int parsePaise(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  final text = value.toString().trim().replaceAll(',', '');
  final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return 0;
  final sign = match.group(1) == '-' ? -1 : 1;
  final whole = int.parse(match.group(2)!);
  final frac = (match.group(3) ?? '').padRight(2, '0');
  return sign * (whole * 100 + int.parse(frac));
}

String paiseToApi(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

int asInt(dynamic value) => asIntOrNull(value) ?? 0;

DateTime? asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

enum AccountKind { bank, cash }

enum BankAccountType { savings, current, salary, other }

enum CardType { debit, credit }

enum CategoryKind { income, expense, financial }

enum MoneyTxnType {
  expense,
  income,
  transfer,
  refund,
  cardPurchase,
  cardPayment,
  cashWithdrawal,
  cashDeposit,
  adjustment,
}

extension AccountKindLabel on AccountKind {
  String get label => this == AccountKind.cash ? 'Cash' : 'Bank';
  String get api => name;
}

extension BankAccountTypeLabel on BankAccountType {
  String get label => switch (this) {
    BankAccountType.savings => 'Savings',
    BankAccountType.current => 'Current',
    BankAccountType.salary => 'Salary',
    BankAccountType.other => 'Other',
  };
  String get api => name;
}

extension CardTypeLabel on CardType {
  String get label => this == CardType.credit ? 'Credit card' : 'Debit card';
  String get api => name;
}

extension CategoryKindLabel on CategoryKind {
  String get label => switch (this) {
    CategoryKind.income => 'Income',
    CategoryKind.expense => 'Expense',
    CategoryKind.financial => 'Financial',
  };
  String get api => name;
}

extension MoneyTxnTypeLabel on MoneyTxnType {
  String get label => switch (this) {
    MoneyTxnType.expense => 'Expense',
    MoneyTxnType.income => 'Income',
    MoneyTxnType.transfer => 'Transfer',
    MoneyTxnType.refund => 'Refund',
    MoneyTxnType.cardPurchase => 'Card purchase',
    MoneyTxnType.cardPayment => 'Card payment',
    MoneyTxnType.cashWithdrawal => 'ATM withdrawal',
    MoneyTxnType.cashDeposit => 'Cash deposit',
    MoneyTxnType.adjustment => 'Adjustment',
  };

  String get api => switch (this) {
    MoneyTxnType.cardPurchase => 'card_purchase',
    MoneyTxnType.cardPayment => 'card_payment',
    MoneyTxnType.cashWithdrawal => 'cash_withdrawal',
    MoneyTxnType.cashDeposit => 'cash_deposit',
    _ => name,
  };

  bool get isCredit =>
      this == MoneyTxnType.income || this == MoneyTxnType.refund;

  bool get isTransfer =>
      this == MoneyTxnType.transfer ||
      this == MoneyTxnType.cashWithdrawal ||
      this == MoneyTxnType.cashDeposit;
}

AccountKind accountKindFrom(dynamic value) {
  return AccountKind.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => AccountKind.bank,
  );
}

BankAccountType? bankAccountTypeFrom(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return BankAccountType.values.where((item) => item.name == value.toString()).firstOrNull;
}

CardType cardTypeFrom(dynamic value) {
  return CardType.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => CardType.debit,
  );
}

CategoryKind categoryKindFrom(dynamic value) {
  return CategoryKind.values.firstWhere(
    (item) => item.name == value?.toString(),
    orElse: () => CategoryKind.expense,
  );
}

MoneyTxnType moneyTxnTypeFrom(dynamic value) {
  final name = value?.toString().replaceAll('-', '_');
  return MoneyTxnType.values.firstWhere(
    (item) => item.api == name || item.name == name,
    orElse: () => MoneyTxnType.expense,
  );
}

String maskedLastFour(String? lastFour) {
  if (lastFour == null || lastFour.isEmpty) return '';
  return '••••$lastFour';
}

class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    this.institutionName = '',
    required this.kind,
    this.bankAccountType,
    this.lastFourDigits,
    this.openingBalancePaise = 0,
    this.currentBalancePaise = 0,
    this.currency = 'INR',
    this.notes = '',
    this.isActive = true,
    this.monthlyIncomePaise,
    this.monthlyExpensePaise,
    this.monthlyTransfersPaise,
  });

  final int id;
  final String name;
  final String institutionName;
  final AccountKind kind;
  final BankAccountType? bankAccountType;
  final String? lastFourDigits;
  final int openingBalancePaise;
  final int currentBalancePaise;
  final String currency;
  final String notes;
  final bool isActive;
  final int? monthlyIncomePaise;
  final int? monthlyExpensePaise;
  final int? monthlyTransfersPaise;

  String get displayName {
    final masked = maskedLastFour(lastFourDigits);
    return masked.isEmpty ? name : '$name $masked';
  }

  factory MoneyAccount.fromJson(Map<String, dynamic> json) {
    final month = json['thisMonth'] as Map<String, dynamic>?;
    return MoneyAccount(
      id: asInt(json['accountId'] ?? json['id']),
      name: json['name'] as String? ?? '',
      institutionName: json['institutionName'] as String? ?? '',
      kind: accountKindFrom(json['accountKind']),
      bankAccountType: bankAccountTypeFrom(json['bankAccountType']),
      lastFourDigits: json['lastFourDigits'] as String?,
      openingBalancePaise: parsePaise(json['openingBalance']),
      currentBalancePaise: parsePaise(json['currentBalance']),
      currency: json['currency'] as String? ?? 'INR',
      notes: json['notes'] as String? ?? '',
      isActive: json['isActive'] != false,
      monthlyIncomePaise: month == null ? null : parsePaise(month['income']),
      monthlyExpensePaise: month == null ? null : parsePaise(month['expense']),
      monthlyTransfersPaise: month == null ? null : parsePaise(month['transfers']),
    );
  }
}

class MoneyCard {
  const MoneyCard({
    required this.id,
    required this.name,
    required this.cardType,
    this.issuerName = '',
    this.lastFourDigits,
    this.linkedAccountId,
    this.linkedAccountName,
    this.linkedAccountLastFour,
    this.creditLimitPaise,
    this.openingOutstandingPaise = 0,
    this.currentOutstandingPaise = 0,
    this.availableCreditPaise,
    this.statementDay,
    this.dueDay,
    this.minimumDuePaise,
    this.notes = '',
    this.isActive = true,
  });

  final int id;
  final String name;
  final CardType cardType;
  final String issuerName;
  final String? lastFourDigits;
  final int? linkedAccountId;
  final String? linkedAccountName;
  final String? linkedAccountLastFour;
  final int? creditLimitPaise;
  final int openingOutstandingPaise;
  final int currentOutstandingPaise;
  final int? availableCreditPaise;
  final int? statementDay;
  final int? dueDay;
  final int? minimumDuePaise;
  final String notes;
  final bool isActive;

  bool get isCredit => cardType == CardType.credit;

  String get displayName {
    final masked = maskedLastFour(lastFourDigits);
    return masked.isEmpty ? name : '$name $masked';
  }

  factory MoneyCard.fromJson(Map<String, dynamic> json) {
    return MoneyCard(
      id: asInt(json['cardId'] ?? json['id']),
      name: json['name'] as String? ?? '',
      cardType: cardTypeFrom(json['cardType']),
      issuerName: json['issuerName'] as String? ?? '',
      lastFourDigits: json['lastFourDigits'] as String?,
      linkedAccountId: asIntOrNull(json['linkedAccountId']),
      linkedAccountName: json['linkedAccountName'] as String?,
      linkedAccountLastFour: json['linkedAccountLastFour'] as String?,
      creditLimitPaise: json['creditLimit'] == null ? null : parsePaise(json['creditLimit']),
      openingOutstandingPaise: parsePaise(json['openingOutstanding']),
      currentOutstandingPaise: parsePaise(json['currentOutstanding']),
      availableCreditPaise: json['availableCredit'] == null ? null : parsePaise(json['availableCredit']),
      statementDay: asIntOrNull(json['statementDay']),
      dueDay: asIntOrNull(json['dueDay']),
      minimumDuePaise: json['minimumDue'] == null ? null : parsePaise(json['minimumDue']),
      notes: json['notes'] as String? ?? '',
      isActive: json['isActive'] != false,
    );
  }
}

class MoneyCategory {
  const MoneyCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.isSystem = false,
    this.isActive = true,
  });

  final int id;
  final String name;
  final CategoryKind kind;
  final bool isSystem;
  final bool isActive;

  factory MoneyCategory.fromJson(Map<String, dynamic> json) {
    return MoneyCategory(
      id: asInt(json['categoryId'] ?? json['id']),
      name: json['name'] as String? ?? '',
      kind: categoryKindFrom(json['kind']),
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
    );
  }
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.type,
    required this.title,
    required this.amountPaise,
    required this.occurredAt,
    this.merchantName = '',
    this.description = '',
    this.paymentMethod = '',
    this.categoryId,
    this.categoryName,
    this.accountId,
    this.accountName,
    this.accountLastFour,
    this.counterpartyAccountId,
    this.counterpartyAccountName,
    this.counterpartyLastFour,
    this.cardId,
    this.cardName,
    this.cardLastFour,
    this.linkedTransactionId,
  });

  final int id;
  final MoneyTxnType type;
  final String title;
  final int amountPaise;
  final DateTime occurredAt;
  final String merchantName;
  final String description;
  final String paymentMethod;
  final int? categoryId;
  final String? categoryName;
  final int? accountId;
  final String? accountName;
  final String? accountLastFour;
  final int? counterpartyAccountId;
  final String? counterpartyAccountName;
  final String? counterpartyLastFour;
  final int? cardId;
  final String? cardName;
  final String? cardLastFour;
  final int? linkedTransactionId;

  String get sourceLabel {
    if (type.isTransfer) {
      final from = accountName ?? 'Account';
      final to = counterpartyAccountName ?? 'Account';
      return '$from → $to';
    }
    if (cardName != null && cardName!.isNotEmpty) return cardName!;
    if (accountName != null && accountName!.isNotEmpty) {
      final masked = maskedLastFour(accountLastFour);
      return masked.isEmpty ? accountName! : '$accountName $masked';
    }
    return '';
  }

  bool get showsAsCredit => type.isCredit;

  factory MoneyTransaction.fromJson(Map<String, dynamic> json) {
    return MoneyTransaction(
      id: asInt(json['transactionId'] ?? json['id']),
      type: moneyTxnTypeFrom(json['transactionType']),
      title: json['title'] as String? ?? '',
      amountPaise: parsePaise(json['amount']),
      occurredAt: asDateTime(json['occurredAt']) ?? DateTime.now().toUtc(),
      merchantName: json['merchantName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? '',
      categoryId: asIntOrNull(json['categoryId']),
      categoryName: json['categoryName'] as String?,
      accountId: asIntOrNull(json['accountId']),
      accountName: json['accountName'] as String?,
      accountLastFour: json['accountLastFour'] as String?,
      counterpartyAccountId: asIntOrNull(json['counterpartyAccountId']),
      counterpartyAccountName: json['counterpartyAccountName'] as String?,
      counterpartyLastFour: json['counterpartyLastFour'] as String?,
      cardId: asIntOrNull(json['cardId']),
      cardName: json['cardName'] as String?,
      cardLastFour: json['cardLastFour'] as String?,
      linkedTransactionId: asIntOrNull(json['linkedTransactionId']),
    );
  }
}

class MoneyOverview {
  const MoneyOverview({
    this.cashAndBankPaise = 0,
    this.creditCardOutstandingPaise = 0,
    this.netPositionPaise = 0,
    this.monthlyIncomePaise = 0,
    this.monthlyExpensePaise = 0,
    this.monthlyTransfersPaise = 0,
    this.netIncomePaise = 0,
    this.accounts = const [],
    this.creditCards = const [],
    this.recentTransactions = const [],
  });

  final int cashAndBankPaise;
  final int creditCardOutstandingPaise;
  final int netPositionPaise;
  final int monthlyIncomePaise;
  final int monthlyExpensePaise;
  final int monthlyTransfersPaise;
  final int netIncomePaise;
  final List<MoneyAccount> accounts;
  final List<MoneyCard> creditCards;
  final List<MoneyTransaction> recentTransactions;

  factory MoneyOverview.fromJson(Map<String, dynamic> json) {
    return MoneyOverview(
      cashAndBankPaise: parsePaise(json['cashAndBank']),
      creditCardOutstandingPaise: parsePaise(json['creditCardOutstanding']),
      netPositionPaise: parsePaise(json['netPosition']),
      monthlyIncomePaise: parsePaise(json['monthlyIncome']),
      monthlyExpensePaise: parsePaise(json['monthlyExpense']),
      monthlyTransfersPaise: parsePaise(json['monthlyTransfers']),
      netIncomePaise: parsePaise(json['netIncome']),
      accounts: _list(json['accounts'], MoneyAccount.fromJson),
      creditCards: _list(json['creditCards'], MoneyCard.fromJson),
      recentTransactions: _list(json['recentTransactions'], MoneyTransaction.fromJson),
    );
  }
}

class MoneyTxnPage {
  const MoneyTxnPage({required this.items, this.nextCursor, this.hasMore = false});

  final List<MoneyTransaction> items;
  final String? nextCursor;
  final bool hasMore;
}

class MoneyReports {
  const MoneyReports({
    this.categorySpending = const [],
    this.accountSpending = const [],
    this.cardSpending = const [],
    this.monthlyTransfersPaise = 0,
  });

  final List<MoneySpendRow> categorySpending;
  final List<MoneySpendRow> accountSpending;
  final List<MoneyCardSpendRow> cardSpending;
  final int monthlyTransfersPaise;

  factory MoneyReports.fromJson(Map<String, dynamic> json) {
    return MoneyReports(
      categorySpending: _list(json['categorySpending'], (item) {
        return MoneySpendRow(
          id: asInt(item['categoryId']),
          name: item['name'] as String? ?? '',
          amountPaise: parsePaise(item['amount']),
        );
      }),
      accountSpending: _list(json['accountSpending'], (item) {
        return MoneySpendRow(
          id: asInt(item['accountId']),
          name: item['name'] as String? ?? '',
          amountPaise: parsePaise(item['amount']),
        );
      }),
      cardSpending: _list(json['cardSpending'], MoneyCardSpendRow.fromJson),
      monthlyTransfersPaise: parsePaise(json['monthlyTransfers']),
    );
  }
}

class MoneySpendRow {
  const MoneySpendRow({required this.id, required this.name, required this.amountPaise});

  final int id;
  final String name;
  final int amountPaise;
}

class MoneyCardSpendRow {
  const MoneyCardSpendRow({
    required this.id,
    required this.name,
    required this.cardType,
    required this.purchasesPaise,
    required this.paymentsPaise,
  });

  final int id;
  final String name;
  final CardType cardType;
  final int purchasesPaise;
  final int paymentsPaise;

  factory MoneyCardSpendRow.fromJson(Map<String, dynamic> json) {
    return MoneyCardSpendRow(
      id: asInt(json['cardId']),
      name: json['name'] as String? ?? '',
      cardType: cardTypeFrom(json['cardType']),
      purchasesPaise: parsePaise(json['purchases']),
      paymentsPaise: parsePaise(json['payments']),
    );
  }
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => parse(Map<String, dynamic>.from(item)))
      .toList();
}
