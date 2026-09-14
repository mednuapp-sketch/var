import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../models/app_role.dart';
import '../providers/role_providers.dart';
import 'wallet_models.dart';
import 'wallet_repository.dart';

/// Role-aware: each role gets its own implementation of the same
/// [WalletRepository] interface, so every wallet UI widget stays
/// role-agnostic. Doctor/lab/pharmacy/ambulance/caregiver/nutritionist/
/// hospital are on the real Payment Distribution & Settlement Engine
/// (functions/index.js) via [SettlementWalletRepository] — nutritionist
/// settles via onNutritionAppointmentSettlement, hospital via
/// onHospitalAppointmentCreated/onHospitalAppointmentStatusChange /
/// onHospitalBillPaymentVerified, both writing the same
/// provider_wallets/{uid} + wallet_ledger docs everyone else does.
/// Physiotherapist/Counsellor are ALSO full settlement-engine participants
/// on the backend (see onPhysioSessionStatusChange/
/// onCounsellingSessionStatusChange calling _transitionPaymentToEligible)
/// but use [SettlementWithLegacyWalletRepository] instead of the plain one —
/// it merges in their legacy physio_transactions/counselling_transactions
/// ledger so session history recorded before real payments went live
/// doesn't disappear from their Earnings screen (see that class's own doc
/// comment for the full reasoning). Nutritionist/hospital never had an
/// equivalent legacy ledger, so they don't need the merge.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final role = ref.watch(roleEngineProvider).activeRole;
  switch (role) {
    case AppRole.doctor:
    case AppRole.lab:
    case AppRole.pharmacy:
    case AppRole.ambulance:
    case AppRole.caregiver:
    case AppRole.nutritionist:
      return SettlementWalletRepository();
    case AppRole.hospital:
      return HospitalWalletRepository();
    case AppRole.physiotherapist:
      return SettlementWithLegacyWalletRepository(
        legacyCollection: 'physio_transactions',
        legacyProviderIdField: 'physiotherapistId',
      );
    case AppRole.counsellor:
      return SettlementWithLegacyWalletRepository(
        legacyCollection: 'counselling_transactions',
        legacyProviderIdField: 'counsellorId',
      );
    case AppRole.admin:
      return DoctorAppointmentWalletRepository();
  }
});

// Not autoDispose: this is watched by a widget (SharedWalletSummaryCard) that
// sits under screens with their own frequent setState calls (e.g. the
// dashboard's online/offline toggle) — a brief tree perturbation from an
// unrelated ancestor rebuild was enough to drop this provider's last
// listener, autoDispose it, and restart the stream from `loading` on the
// very next rebuild, flashing the wallet card back to its loading state.
final walletSummaryProvider = StreamProvider<WalletSummary>((ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return Stream.value(WalletSummary.empty());
  return ref.watch(walletRepositoryProvider).streamSummary(uid);
});

/// Convenience derived provider for screens that only need the transaction
/// list (e.g. a "recent activity" section) without re-deriving loading/error
/// handling themselves.
final walletTransactionsProvider =
    Provider<AsyncValue<List<WalletTransaction>>>((ref) {
  return ref.watch(walletSummaryProvider).whenData((s) => s.transactions);
});
