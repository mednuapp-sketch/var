import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WalletTransaction {
  final String id;
  final String title;
  final double amount;
  final String type; // 'credit' | 'debit'
  final String category;
  final String? description;
  final DateTime timestamp;
  // 'main' = regular wallet, 'mednu_money' = bonus credits (non-withdrawable)
  final String walletType;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    this.description,
    required this.timestamp,
    this.walletType = 'main',
  });

  factory WalletTransaction.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WalletTransaction(
      id: doc.id,
      title: data['title'] as String? ?? 'Transaction',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      type: data['type'] as String? ?? 'debit',
      category: data['category'] as String? ?? 'payment',
      description: data['description'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      walletType: data['walletType'] as String? ?? 'main',
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'amount': amount,
        'type': type,
        'category': category,
        if (description != null) 'description': description,
        'timestamp': FieldValue.serverTimestamp(),
        'walletType': walletType,
      };

  bool get isCredit => type == 'credit';
  bool get isMednuMoney => walletType == 'mednu_money';
}

class WalletService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  DocumentReference get _userRef => _db.collection('users').doc(_uid);
  CollectionReference get _txRef => _userRef.collection('transactions');

  Stream<double> balanceStream() {
    if (_uid.isEmpty) return Stream.value(0.0);
    return _userRef.snapshots().map((snap) {
      if (!snap.exists) return 0.0;
      final data = snap.data() as Map<String, dynamic>?;
      final raw = data?['walletBalance'];
      if (raw is num) return raw.toDouble();
      return 0.0;
    });
  }

  Stream<double> mednuMoneyBalanceStream() {
    if (_uid.isEmpty) return Stream.value(0.0);
    return _userRef.snapshots().map((snap) {
      if (!snap.exists) return 0.0;
      final data = snap.data() as Map<String, dynamic>?;
      final raw = data?['mednuMoneyBalance'];
      if (raw is num) return raw.toDouble();
      return 0.0;
    });
  }

  Stream<List<WalletTransaction>> mednuMoneyTransactionsStream() {
    if (_uid.isEmpty) return Stream.value([]);
    return _txRef
        .where('walletType', isEqualTo: 'mednu_money')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(WalletTransaction.fromDoc).toList());
  }

  Stream<int> referralPointsStream() {
    if (_uid.isEmpty) return Stream.value(0);
    return _userRef.snapshots().map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data() as Map<String, dynamic>?;
      return (data?['referralPoints'] as int?) ?? 0;
    });
  }

  Stream<List<WalletTransaction>> transactionsStream() {
    if (_uid.isEmpty) return Stream.value([]);
    return _txRef
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(WalletTransaction.fromDoc).toList());
  }

  // ── Wallet top-up (Razorpay) ────────────────────────────────────────────
  //
  // Balances are server-authoritative: firestore.rules blocks every client
  // write to walletBalance / mednuMoneyBalance / referralPoints, so money can
  // only enter the wallet through a real, signature-verified gateway payment.
  //
  // Step 1 — create an order. The server records the ordered amount in
  // `razorpay_orders/{order_id}`; that record, not anything this client sends
  // later, decides how much gets credited.
  Future<({String orderId, int amountPaise})> createTopUpOrder(
      double amount) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    final paise = (amount * 100).round();
    if (paise < 100) throw Exception('Minimum top-up is ₹1');
    try {
      final result = await _fns.httpsCallable('createRazorpayOrder').call({
        'amount': paise,
        'currency': 'INR',
        'purpose': 'wallet_topup',
        'receipt': 'topup_${DateTime.now().millisecondsSinceEpoch}',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (
        orderId: data['order_id'] as String,
        amountPaise: (data['amount'] as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not start the top-up. Try again.');
    }
  }

  // Step 2 — hand the Razorpay result back to the server. Verification AND the
  // wallet credit both happen inside `verifyRazorpayPayment`; this client never
  // writes a balance. Safe to retry: the credit is keyed on the payment id.
  Future<bool> confirmTopUp({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final result = await _fns.httpsCallable('verifyRazorpayPayment').call({
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['verified'] == true;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Payment could not be verified.');
    }
  }

  /// Direct crediting no longer exists on the client — it was the exploit.
  /// Top-ups go through [createTopUpOrder] / [confirmTopUp].
  Future<void> addMoney(double amount) async {
    throw UnimplementedError(
      'Wallet credits are server-side only. Use createTopUpOrder/confirmTopUp.',
    );
  }

  // ── Spending ────────────────────────────────────────────────────────────
  //
  // Both debit paths go through the `spendWalletBalance` callable, which
  // re-reads the balance server-side, checks sufficiency, debits and writes
  // both ledgers in one Firestore transaction.
  Future<void> deductPayment({
    required double amount,
    required String title,
    String category = 'payment',
    String? description,
  }) =>
      _spend(
        walletType: 'main',
        amount: amount,
        title: title,
        category: category,
        description: description,
      );

  Future<void> deductMednuMoney({
    required double amount,
    required String title,
    String category = 'payment',
    String? description,
  }) =>
      _spend(
        walletType: 'mednu_money',
        amount: amount,
        title: title,
        category: category,
        description: description,
      );

  Future<void> _spend({
    required String walletType,
    required double amount,
    required String title,
    required String category,
    String? description,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    try {
      await _fns.httpsCallable('spendWalletBalance').call({
        'walletType': walletType,
        'amount': amount,
        'title': title,
        'category': category,
        if (description != null) 'description': description,
      });
    } on FirebaseFunctionsException catch (e) {
      // Preserves the message shape the UI already surfaces, e.g.
      // 'Insufficient wallet balance'.
      throw Exception(e.message ?? 'Could not complete the payment.');
    }
  }

  /// Superseded by the server: wallet credits now originate only from
  /// `verifyRazorpayPayment` (top-ups) and `grantReferralReward` (rewards).
  /// A generic client-callable credit would itself be a self-credit vector.
  Future<void> addCredit({
    required double amount,
    required String title,
    required String category,
    String? description,
  }) async {
    throw UnimplementedError(
      'Use grantReferralReward or verifyRazorpayPayment.',
    );
  }

  /// See [addCredit] — MedNU Money is credited server-side only.
  Future<void> addMednuMoney({
    required double amount,
    required String title,
    required String category,
    String? description,
  }) async {
    throw UnimplementedError(
      'Use grantReferralReward or verifyRazorpayPayment.',
    );
  }

  // ── Peer transfer ───────────────────────────────────────────────────────
  //
  // Recipient lookup, sufficiency check, both balance writes and both ledger
  // entries all happen inside the `transferWalletBalance` callable. The sender
  // label is taken from the verified auth token server-side.
  Future<void> transferToUser({
    required String recipientPhone,
    required double amount,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    try {
      await _fns.httpsCallable('transferWalletBalance').call({
        'recipientPhone': recipientPhone,
        'amount': amount,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Transfer failed. Please try again.');
    }
  }
}
