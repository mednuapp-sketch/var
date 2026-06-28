import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_service.dart';

final walletServiceProvider = Provider<WalletService>((ref) => WalletService());

final walletBalanceProvider = StreamProvider<double>((ref) {
  return ref.watch(walletServiceProvider).balanceStream();
});

final mednuMoneyBalanceProvider = StreamProvider<double>((ref) {
  return ref.watch(walletServiceProvider).mednuMoneyBalanceStream();
});

final walletReferralPointsProvider = StreamProvider<int>((ref) {
  return ref.watch(walletServiceProvider).referralPointsStream();
});

final walletTransactionsProvider = StreamProvider<List<WalletTransaction>>((ref) {
  return ref.watch(walletServiceProvider).transactionsStream();
});

final mednuMoneyTransactionsProvider = StreamProvider<List<WalletTransaction>>((ref) {
  return ref.watch(walletServiceProvider).mednuMoneyTransactionsStream();
});
