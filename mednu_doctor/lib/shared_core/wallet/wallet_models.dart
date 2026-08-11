enum WalletTransactionType { credit, debit }

class WalletTransaction {
  final String id;
  final String title;
  final String subtitle;
  final num amount;
  final WalletTransactionType type;
  final DateTime date;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    required this.date,
  });
}

class WalletSummary {
  final num balance;
  final num pendingAmount;
  final String currency;
  final List<WalletTransaction> transactions;

  const WalletSummary({
    required this.balance,
    required this.pendingAmount,
    required this.currency,
    required this.transactions,
  });

  factory WalletSummary.empty() => const WalletSummary(
        balance: 0,
        pendingAmount: 0,
        currency: 'INR',
        transactions: [],
      );

  bool get isEmpty => transactions.isEmpty;
}
