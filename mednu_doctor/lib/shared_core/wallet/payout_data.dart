import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import 'wallet_providers.dart';
import 'wallet_repository.dart';

/// Validators shared by the payout-account form. Regexes follow the backend
/// contract: account 6-20 digits, IFSC ^[A-Z]{4}0[A-Z0-9]{6}$, UPI has '@'.
class PayoutValidators {
  PayoutValidators._();

  static final RegExp accountRe = RegExp(r'^\d{6,20}$');
  static final RegExp ifscRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  static String? holderName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter the account holder name';
    if (s.length < 3) return 'Name looks too short';
    if (s.length > 80) return 'Name is too long';
    return null;
  }

  static String? accountNumber(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your account number';
    if (!accountRe.hasMatch(s)) return 'Account number must be 6 to 20 digits';
    return null;
  }

  static String? confirmAccount(String? v, String original) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Re-enter your account number';
    if (s != original.trim()) return 'Account numbers do not match';
    return null;
  }

  static String? ifsc(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isEmpty) return 'Enter the IFSC code';
    if (!ifscRe.hasMatch(s)) return 'Invalid IFSC (example: HDFC0001234)';
    return null;
  }

  static String? bankName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter the bank name';
    if (s.length > 60) return 'Bank name is too long';
    return null;
  }

  /// Optional.
  static String? upi(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (!s.contains('@') || s.length < 5 || s.contains(' ')) {
      return 'Enter a valid UPI id (example: name@bank)';
    }
    return null;
  }

  static String mask(String number) {
    final s = number.trim();
    if (s.length <= 4) return s;
    return '${'•' * (s.length - 4)}${s.substring(s.length - 4)}';
  }
}

enum PayoutAccountStatus { pending, verified, rejected }

class PayoutAccount {
  final String providerId;
  final String holderName;
  final String accountNumber;
  final String ifsc;
  final String bankName;
  final String upiId;
  final PayoutAccountStatus status;
  final String? rejectReason;

  const PayoutAccount({
    required this.providerId,
    required this.holderName,
    required this.accountNumber,
    required this.ifsc,
    required this.bankName,
    required this.upiId,
    required this.status,
    this.rejectReason,
  });

  bool get isVerified => status == PayoutAccountStatus.verified;
  String get maskedNumber => PayoutValidators.mask(accountNumber);

  factory PayoutAccount.fromMap(String id, Map<String, dynamic> d) {
    final raw = d['status'];
    final status = raw == 'verified'
        ? PayoutAccountStatus.verified
        : raw == 'rejected'
            ? PayoutAccountStatus.rejected
            : PayoutAccountStatus.pending;
    return PayoutAccount(
      providerId: (d['providerId'] as String?) ?? id,
      holderName: (d['holderName'] as String?) ?? '',
      accountNumber: (d['accountNumber'] as String?) ?? '',
      ifsc: (d['ifsc'] as String?) ?? '',
      bankName: (d['bankName'] as String?) ?? '',
      upiId: (d['upiId'] as String?) ?? '',
      status: status,
      rejectReason: d['rejectReason'] as String?,
    );
  }
}

class PayoutConfig {
  final bool enabled;
  final num minAmount;
  const PayoutConfig({this.enabled = true, this.minAmount = 500});
}

class PayoutRequest {
  final String id;
  final String status;
  final num amount;
  final DateTime? requestedAt;
  final String bankName;
  final String maskedAccount;

  const PayoutRequest({
    required this.id,
    required this.status,
    required this.amount,
    required this.requestedAt,
    required this.bankName,
    required this.maskedAccount,
  });

  bool get canCancel => status == 'pending';

  /// Statuses where the request is still being processed (blocks a new one).
  bool get isOpen =>
      status == 'pending' || status == 'approved' || status == 'held';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Requested';
      case 'approved':
        return 'Approved';
      case 'held':
        return 'On hold';
      case 'paid':
        return 'Paid';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Processing';
    }
  }
}

/// The id `provider_wallets`/`settlements`/`payout_accounts` are keyed by
/// for the signed-in account (hospital -> hospitalId, everyone else -> uid).
final payoutProviderIdProvider = FutureProvider<String?>((ref) async {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return null;
  final repo = ref.watch(walletRepositoryProvider);
  if (repo is SettlementWalletRepository) {
    return repo.resolveProviderId(FirebaseFirestore.instance, uid);
  }
  return uid;
});

final payoutAccountProvider = StreamProvider<PayoutAccount?>((ref) async* {
  final id = await ref.watch(payoutProviderIdProvider.future);
  if (id == null) {
    yield null;
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('payout_accounts')
      .doc(id)
      .snapshots()
      .map((s) => s.exists && s.data() != null ? PayoutAccount.fromMap(s.id, s.data()!) : null);
});

final payoutConfigProvider = StreamProvider<PayoutConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('app_config')
      .doc('payouts')
      .snapshots()
      .map((s) {
    final d = s.data();
    final min = d?['minAmount'];
    return PayoutConfig(
      enabled: d?['enabled'] != false,
      minAmount: min is num && min >= 0 ? min : 500,
    );
  });
});

/// Provider's recent partner-requested settlements. Queried by providerId
/// only (no composite index) and sorted client-side.
final payoutRequestsProvider = StreamProvider<List<PayoutRequest>>((ref) async* {
  final id = await ref.watch(payoutProviderIdProvider.future);
  if (id == null) {
    yield const [];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('settlements')
      .where('providerId', isEqualTo: id)
      .snapshots()
      .map((snap) {
    final list = <PayoutRequest>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['requestedByPartner'] != true) continue;
      final snapshot = d['payoutAccountSnapshot'];
      final snap = snapshot is Map ? snapshot : const {};
      list.add(PayoutRequest(
        id: doc.id,
        status: (d['status'] as String?) ?? 'pending',
        amount: (d['totalAmount'] as num?) ?? 0,
        requestedAt: (d['requestedAt'] as Timestamp?)?.toDate(),
        bankName: (snap['bankName'] as String?) ?? '',
        maskedAccount: (snap['accountNumberMasked'] as String?) ?? '',
      ));
    }
    list.sort((a, b) {
      final ad = a.requestedAt?.millisecondsSinceEpoch ?? 0;
      final bd = b.requestedAt?.millisecondsSinceEpoch ?? 0;
      return bd.compareTo(ad);
    });
    return list.take(10).toList();
  });
});

class PayoutService {
  PayoutService._();

  static Future<void> saveAccount({
    required String providerId,
    required String role,
    required String holderName,
    required String accountNumber,
    required String ifsc,
    required String bankName,
    required String upiId,
  }) async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) throw StateError('not-signed-in');
    final data = <String, dynamic>{
      'providerId': providerId,
      'ownerUid': uid,
      'role': role,
      'holderName': holderName.trim(),
      'accountNumber': accountNumber.trim(),
      'ifsc': ifsc.trim().toUpperCase(),
      'bankName': bankName.trim(),
      'upiId': upiId.trim(),
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    };
    await FirebaseFirestore.instance
        .collection('payout_accounts')
        .doc(providerId)
        .set(data);
  }

  /// Returns the requested amount.
  static Future<num> requestPayout() async {
    final res = await FirebaseFunctions.instance.httpsCallable('requestPayout').call(<String, dynamic>{});
    final data = res.data;
    if (data is Map && data['amount'] is num) return data['amount'] as num;
    return 0;
  }

  static Future<void> cancelRequest(String settlementId) async {
    await FirebaseFunctions.instance
        .httpsCallable('cancelPayoutRequest')
        .call(<String, dynamic>{'settlementId': settlementId});
  }

  /// User-friendly text for a callable failure.
  static String friendlyError(Object e) {
    var msg = '';
    var code = '';
    if (e is FirebaseFunctionsException) {
      code = e.code;
      msg = e.message ?? '';
    } else {
      msg = e.toString();
    }
    final m = msg.toLowerCase();
    if (code == 'already-exists') return 'You already have a payout request in progress.';
    if (code == 'not-found') return 'You have no earnings available to pay out yet.';
    if (m.contains('debt') || m.contains('recover') || m.contains('adjust')) {
      return 'Your pending recovery adjustments cover this payout right now.';
    }
    if (m.contains('no eligible') || m.contains('nothing to')) {
      return 'You have no earnings available to pay out yet.';
    }
    if (m.contains('verified') || m.contains('no payout account')) {
      return 'Add and verify your payout account before requesting a payout.';
    }
    if (m.contains('minimum') || m.contains('below')) {
      return 'Your pending earnings are below the minimum payout amount.';
    }
    if (m.contains('open') || m.contains('already')) {
      return 'You already have a payout request in progress.';
    }
    if (m.contains('disabled') || m.contains('not enabled') || m.contains('paused')) {
      return 'Payouts are temporarily unavailable. Please try again later.';
    }
    if (code == 'unauthenticated') return 'Please sign in again and retry.';
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return 'Network problem. Check your connection and try again.';
    }
    if (code == 'permission-denied') return 'You are not allowed to do this.';
    if (code == 'failed-precondition' && msg.isNotEmpty && msg.length < 140) return msg;
    return 'Something went wrong. Please try again.';
  }
}
