import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'referral_service.dart';

final referralServiceProvider = Provider<ReferralService>(
  (_) => ReferralService(),
);

final referralConfigProvider = StreamProvider<ReferralConfig>((ref) {
  return ref.watch(referralServiceProvider).configStream();
});

final referralHistoryProvider = StreamProvider<List<ReferralRecord>>((ref) {
  return ref.watch(referralServiceProvider).myReferralsStream();
});

final referralStatsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return ref.watch(referralServiceProvider).myStatsStream();
});
