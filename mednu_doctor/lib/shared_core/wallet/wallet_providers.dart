import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../models/app_role.dart';
import '../providers/role_providers.dart';
import 'wallet_models.dart';
import 'wallet_repository.dart';

/// Role-aware: each role gets its own implementation of the same
/// [WalletRepository] interface, so every wallet UI widget stays
/// role-agnostic. Doctor/lab/pharmacy/ambulance/caregiver are on the real
/// Payment Distribution & Settlement Engine (functions/index.js) via
/// [SettlementWalletRepository] — physiotherapist/counsellor/nutritionist
/// aren't wired into that engine yet (no commission_rules/settlement
/// support for those service types) and keep their existing
/// aggregation/ledger-read repositories until they are.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final role = ref.watch(roleEngineProvider).activeRole;
  switch (role) {
    case AppRole.doctor:
    case AppRole.lab:
    case AppRole.pharmacy:
    case AppRole.ambulance:
    case AppRole.caregiver:
      return SettlementWalletRepository();
    case AppRole.physiotherapist:
      return PhysioTransactionWalletRepository();
    case AppRole.counsellor:
      return CounsellingTransactionWalletRepository();
    case AppRole.nutritionist:
      return NutritionAppointmentWalletRepository();
    case AppRole.admin:
      return DoctorAppointmentWalletRepository();
  }
});

final walletSummaryProvider = StreamProvider.autoDispose<WalletSummary>((ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return Stream.value(WalletSummary.empty());
  return ref.watch(walletRepositoryProvider).streamSummary(uid);
});

/// Convenience derived provider for screens that only need the transaction
/// list (e.g. a "recent activity" section) without re-deriving loading/error
/// handling themselves.
final walletTransactionsProvider =
    Provider.autoDispose<AsyncValue<List<WalletTransaction>>>((ref) {
  return ref.watch(walletSummaryProvider).whenData((s) => s.transactions);
});
