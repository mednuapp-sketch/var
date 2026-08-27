import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'wallet_models.dart';

/// Abstraction the Shared Core wallet providers depend on, so a real
/// ledger-backed implementation (balance + `walletTransactions` collection,
/// per the platform architecture) can be dropped in later for any role
/// without changing a single UI widget.
abstract class WalletRepository {
  Stream<WalletSummary> streamSummary(String uid);
}

/// Today's only implementation. There is no `wallet`/`transactions`
/// collection in this codebase yet — "earnings" is a client-side
/// aggregation over `appointments.fee`, exactly like
/// `features/earnings/screens/doctor_earnings_screen.dart` already does.
/// This class reads the *same* fields that screen reads
/// (`doctorId`, `status`, `fee`, `patientName`, `createdAt`) and changes
/// nothing about that collection or its schema — it's a second reader, not
/// a schema change.
class DoctorAppointmentWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  DoctorAppointmentWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('appointments')
        .where('doctorId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      num pending = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final status = d['status'] as String? ?? '';
        final fee = (d['fee'] as num?) ?? 0;
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        if (status == 'completed') {
          balance += fee;
          transactions.add(WalletTransaction(
            id: doc.id,
            title: 'Consultation — $patientName',
            subtitle: 'Completed',
            amount: fee,
            type: WalletTransactionType.credit,
            date: createdAt,
          ));
        } else if (status == 'upcoming' ||
            status == 'scheduled' ||
            status == 'confirmed' ||
            status == 'booked') {
          pending += fee;
        }
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: pending,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Payment Distribution & Settlement Engine implementation (see
/// functions/index.js) — one real-time, ledger-backed repository shared by
/// every vertical the engine covers (doctor, lab, pharmacy, ambulance,
/// caregiver; see [walletRepositoryProvider]). Reads `provider_wallets/{uid}`
/// for live balance figures and `wallet_ledger` (filtered to this provider's
/// own entries) for transaction history — the exact same two collections
/// the admin Settlement Dashboard reads, so a provider's numbers can never
/// drift from what admin sees. Replaces the old per-vertical
/// `*TransactionWalletRepository` classes below, which read the legacy
/// `lab_transactions`/`pharmacy_transactions`/`ambulance_transactions`/
/// `caregiver_transactions` collections directly (still written for
/// historical/back-compat reasons, but no longer the settlement source of
/// truth — see the settlement engine's doc comment in functions/index.js).
///
/// Both Firestore listeners are merged manually (no rxdart dependency) —
/// either one updating re-emits a fresh [WalletSummary] built from whichever
/// data has arrived so far, so the UI never has to wait for both to load
/// before showing anything.
class SettlementWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  SettlementWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    late final StreamController<WalletSummary> controller;
    StreamSubscription? walletSub;
    StreamSubscription? ledgerSub;
    DateTime? nextPayoutDate;

    Map<String, dynamic>? walletData;
    List<WalletTransaction> transactions = const [];

    Future<void> loadNextPayoutDate() async {
      try {
        final cfg = await _db.collection('settlement_config').doc('global').get();
        final frequency = cfg.data()?['frequency'] as String? ?? 'daily';
        final now = DateTime.now();
        switch (frequency) {
          case 'daily':
            nextPayoutDate = DateTime(now.year, now.month, now.day + 1);
            break;
          case 'weekly':
            nextPayoutDate = now.add(Duration(days: 8 - now.weekday));
            break;
          case 'monthly':
            nextPayoutDate = DateTime(now.month == 12 ? now.year + 1 : now.year, now.month == 12 ? 1 : now.month + 1, 1);
            break;
          default: // 'manual' — admin-triggered, no fixed schedule
            nextPayoutDate = null;
        }
      } catch (_) {
        nextPayoutDate = null;
      }
    }

    void emit() {
      if (controller.isClosed) return;
      final balance = (walletData?['availableBalance'] as num?) ?? 0;
      final pending = (walletData?['pendingEarnings'] as num?) ?? 0;
      final paidThisMonth = (walletData?['paidThisMonth'] as num?) ?? 0;
      controller.add(WalletSummary(
        balance: balance,
        pendingAmount: pending,
        currency: 'INR',
        transactions: transactions,
        paidThisMonth: paidThisMonth,
        nextPayoutDate: nextPayoutDate,
      ));
    }

    controller = StreamController<WalletSummary>.broadcast(
      onListen: () async {
        await loadNextPayoutDate();
        walletSub = _db.collection('provider_wallets').doc(uid).snapshots().listen((snap) {
          walletData = snap.data();
          emit();
        }, onError: (_) {});
        ledgerSub = _db
            .collection('wallet_ledger')
            .where('uid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots()
            .listen((snap) {
          transactions = snap.docs.map(_toTransaction).toList();
          emit();
        }, onError: (_) {});
      },
      onCancel: () {
        walletSub?.cancel();
        ledgerSub?.cancel();
      },
    );

    return controller.stream;
  }

  WalletTransaction _toTransaction(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final amount = (d['amount'] as num?) ?? 0;
    final category = d['category'] as String? ?? '';
    final title = d['title'] as String? ??
        (category == 'provider_settlement' ? 'Settlement Paid' : 'Earnings');
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return WalletTransaction(
      id: doc.id,
      title: title,
      subtitle: category == 'provider_settlement' ? 'Paid out' : 'Pending settlement',
      amount: amount,
      type: d['type'] == 'debit' ? WalletTransactionType.debit : WalletTransactionType.credit,
      date: createdAt,
    );
  }
}

/// Lab & Diagnostics implementation — legacy direct read of the immutable
/// `lab_transactions` ledger (see `functions/index.js`,
/// `onDiagnosticBookingStatusChange`). Superseded by
/// [SettlementWalletRepository] above for the wallet screen; kept here for
/// any other code still reading it directly.
class LabTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  LabTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('lab_transactions')
        .where('labId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final testName = d['testName'] as String? ?? 'Diagnostic Test';
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: '$testName — $patientName',
          subtitle: 'Completed',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Ambulance implementation — backed by the real, immutable
/// `ambulance_transactions` ledger (see `functions/index.js`,
/// `onAmbulanceRequestStatusChange`), which is the only writer. Same shape
/// as [LabTransactionWalletRepository]: `balance` is the sum of ledger rows,
/// not a derived snapshot of operational records.
class AmbulanceTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  AmbulanceTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('ambulance_transactions')
        .where('ambulanceId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: 'Ambulance trip — $patientName',
          subtitle: 'Completed',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Caregiver implementation — backed by the real, immutable
/// `caregiver_transactions` ledger (see `functions/index.js`,
/// `onCaregiverVisitStatusChange`), which is the only writer.
class CaregiverTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  CaregiverTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('caregiver_transactions')
        .where('caregiverId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: 'Home visit — $patientName',
          subtitle: 'Completed',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Pharmacy & Medical Equipment implementation — backed by the real,
/// immutable `pharmacy_transactions` ledger (see `functions/index.js`,
/// `onPharmacyOrderStatusChange`), which is the only writer. Same shape as
/// [LabTransactionWalletRepository]: `balance` is the sum of ledger rows.
class PharmacyTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  PharmacyTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('pharmacy_transactions')
        .where('pharmacyId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final orderType = d['orderType'] as String? ?? 'medicine';
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: '${orderType == 'equipment' ? 'Equipment order' : 'Medicine order'} — $patientName',
          subtitle: 'Delivered',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Physiotherapy implementation — backed by the real, immutable
/// `physio_transactions` ledger (see `functions/index.js`,
/// `onPhysioSessionStatusChange`), which is the only writer. Same shape as
/// [LabTransactionWalletRepository].
class PhysioTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  PhysioTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('physio_transactions')
        .where('physiotherapistId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: 'Physiotherapy session — $patientName',
          subtitle: 'Completed',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Counselling implementation — backed by the real, immutable
/// `counselling_transactions` ledger (see `functions/index.js`,
/// `onCounsellingSessionStatusChange`), which is the only writer. Same shape
/// as [LabTransactionWalletRepository].
class CounsellingTransactionWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  CounsellingTransactionWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('counselling_transactions')
        .where('counsellorId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = (d['amount'] as num?) ?? 0;
        final patientName = d['patientName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        balance += amount;
        transactions.add(WalletTransaction(
          id: doc.id,
          title: 'Counselling session — $patientName',
          subtitle: 'Completed',
          amount: amount,
          type: WalletTransactionType.credit,
          date: createdAt,
        ));
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: 0,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}

/// Nutrition implementation — unlike every ledger-backed repository above,
/// there is no Cloud Function mirror for Nutrition (see functions/index.js's
/// "Nutrition partner access" note — nutrition_appointments is written
/// directly by the patient app with no intermediate collection). "Earnings"
/// is therefore a client-side aggregation over `nutrition_appointments.fee`,
/// exactly like [DoctorAppointmentWalletRepository] aggregates over
/// `appointments.fee` — a second reader, not a schema change.
class NutritionAppointmentWalletRepository implements WalletRepository {
  final FirebaseFirestore _db;

  NutritionAppointmentWalletRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<WalletSummary> streamSummary(String uid) {
    return _db
        .collection('nutrition_appointments')
        .where('nutritionistId', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      num balance = 0;
      num pending = 0;
      final transactions = <WalletTransaction>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final status = d['status'] as String? ?? '';
        final fee = (d['fee'] as num?) ?? 0;
        final patientName = d['userName'] as String? ?? 'Patient';
        final createdAt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        if (status == 'completed') {
          balance += fee;
          transactions.add(WalletTransaction(
            id: doc.id,
            title: 'Nutrition session — $patientName',
            subtitle: 'Completed',
            amount: fee,
            type: WalletTransactionType.credit,
            date: createdAt,
          ));
        } else if (status == 'pending' || status == 'confirmed') {
          pending += fee;
        }
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return WalletSummary(
        balance: balance,
        pendingAmount: pending,
        currency: 'INR',
        transactions: transactions,
      );
    });
  }
}
