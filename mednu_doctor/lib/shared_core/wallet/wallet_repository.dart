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

/// Lab & Diagnostics implementation — backed by the real, immutable
/// `lab_transactions` ledger (see `functions/index.js`,
/// `onDiagnosticBookingStatusChange`), which is the only writer. Unlike
/// [DoctorAppointmentWalletRepository]'s client-side aggregation, this is a
/// true ledger read: `balance` is the sum of ledger rows, not a derived
/// snapshot of operational records.
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
