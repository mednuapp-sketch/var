import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../models/app_role.dart';
import '../providers/role_providers.dart';
import 'wallet_models.dart';
import 'wallet_repository.dart';

/// Role-aware: each role gets its own ledger-backed (or, for Doctor today,
/// aggregation-backed) implementation of the same [WalletRepository]
/// interface, so every wallet UI widget stays role-agnostic.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final role = ref.watch(roleEngineProvider).activeRole;
  switch (role) {
    case AppRole.lab:
      return LabTransactionWalletRepository();
    case AppRole.pharmacy:
      return PharmacyTransactionWalletRepository();
    case AppRole.ambulance:
      return AmbulanceTransactionWalletRepository();
    case AppRole.caregiver:
      return CaregiverTransactionWalletRepository();
    case AppRole.doctor:
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
