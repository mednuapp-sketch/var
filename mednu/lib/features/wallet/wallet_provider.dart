import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_service.dart';

final walletServiceProvider = Provider<WalletService>((ref) => WalletService());

final walletBalanceProvider = StreamProvider<double>((ref) {
  return ref.watch(walletServiceProvider).balanceStream();
});

final walletReferralPointsProvider = StreamProvider<int>((ref) {
  return ref.watch(walletServiceProvider).referralPointsStream();
});

final walletTransactionsProvider = StreamProvider<List<WalletTransaction>>((ref) {
  return ref.watch(walletServiceProvider).transactionsStream();
});
