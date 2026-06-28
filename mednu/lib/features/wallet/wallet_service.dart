import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<void> addMoney(double amount) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_userRef);
      final current = _parseBalance(snap);
      tx.set(
        _userRef,
        {'walletBalance': current + amount},
        SetOptions(merge: true),
      );
      final txDoc = _txRef.doc();
      tx.set(
        txDoc,
        WalletTransaction(
          id: txDoc.id,
          title: 'Money Added',
          amount: amount,
          type: 'credit',
          category: 'add_money',
          timestamp: DateTime.now(),
        ).toMap(),
      );
    });
  }

  Future<void> deductPayment({
    required double amount,
    required String title,
    String category = 'payment',
    String? description,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_userRef);
      final current = _parseBalance(snap);
      if (current < amount) throw Exception('Insufficient wallet balance');
      tx.set(
        _userRef,
        {'walletBalance': current - amount},
        SetOptions(merge: true),
      );
      final txDoc = _txRef.doc();
      tx.set(
        txDoc,
        WalletTransaction(
          id: txDoc.id,
          title: title,
          amount: amount,
          type: 'debit',
          category: category,
          description: description,
          timestamp: DateTime.now(),
        ).toMap(),
      );
    });
  }

  Future<void> addCredit({
    required double amount,
    required String title,
    required String category,
    String? description,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_userRef);
      final current = _parseBalance(snap);
      tx.set(
        _userRef,
        {'walletBalance': current + amount},
        SetOptions(merge: true),
      );
      final txDoc = _txRef.doc();
      tx.set(
        txDoc,
        WalletTransaction(
          id: txDoc.id,
          title: title,
          amount: amount,
          type: 'credit',
          category: category,
          description: description,
          timestamp: DateTime.now(),
        ).toMap(),
      );
    });
  }

  Future<void> addMednuMoney({
    required double amount,
    required String title,
    required String category,
    String? description,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_userRef);
      final current = _parseMednuMoneyBalance(snap);
      tx.set(
        _userRef,
        {'mednuMoneyBalance': current + amount},
        SetOptions(merge: true),
      );
      final txDoc = _txRef.doc();
      tx.set(
        txDoc,
        WalletTransaction(
          id: txDoc.id,
          title: title,
          amount: amount,
          type: 'credit',
          category: category,
          description: description,
          timestamp: DateTime.now(),
          walletType: 'mednu_money',
        ).toMap(),
      );
    });
  }

  Future<void> deductMednuMoney({
    required double amount,
    required String title,
    String category = 'payment',
    String? description,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_userRef);
      final current = _parseMednuMoneyBalance(snap);
      if (current < amount) throw Exception('Insufficient MedNu Money balance');
      tx.set(
        _userRef,
        {'mednuMoneyBalance': current - amount},
        SetOptions(merge: true),
      );
      final txDoc = _txRef.doc();
      tx.set(
        txDoc,
        WalletTransaction(
          id: txDoc.id,
          title: title,
          amount: amount,
          type: 'debit',
          category: category,
          description: description,
          timestamp: DateTime.now(),
          walletType: 'mednu_money',
        ).toMap(),
      );
    });
  }

  Future<void> transferToUser({
    required String recipientPhone,
    required double amount,
  }) async {
    if (_uid.isEmpty) throw Exception('Not authenticated');
    if (amount <= 0) throw Exception('Amount must be positive');

    final query = await _db
        .collection('users')
        .where('phone', isEqualTo: recipientPhone)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw Exception('No MedNu account found with this phone number');
    }
    final recipientRef = query.docs.first.reference;
    if (recipientRef.id == _uid) {
      throw Exception('Cannot transfer to your own wallet');
    }

    await _db.runTransaction((tx) async {
      final senderSnap = await tx.get(_userRef);
      final current = _parseBalance(senderSnap);
      if (current < amount) throw Exception('Insufficient wallet balance');

      tx.set(_userRef, {'walletBalance': current - amount},
          SetOptions(merge: true));
      final senderTxDoc = _txRef.doc();
      tx.set(
        senderTxDoc,
        WalletTransaction(
          id: senderTxDoc.id,
          title: 'Transfer Sent',
          amount: amount,
          type: 'debit',
          category: 'transfer',
          description: 'To: $recipientPhone',
          timestamp: DateTime.now(),
        ).toMap(),
      );

      final recipientSnap = await tx.get(recipientRef);
      final recipientBalance = _parseBalance(recipientSnap);
      tx.set(recipientRef, {'walletBalance': recipientBalance + amount},
          SetOptions(merge: true));
      final recipientTxDoc = recipientRef.collection('transactions').doc();
      final senderLabel = _auth.currentUser?.phoneNumber ??
          _auth.currentUser?.email ??
          'a MedNu user';
      tx.set(
        recipientTxDoc,
        WalletTransaction(
          id: recipientTxDoc.id,
          title: 'Transfer Received',
          amount: amount,
          type: 'credit',
          category: 'transfer',
          description: 'From: $senderLabel',
          timestamp: DateTime.now(),
        ).toMap(),
      );
    });
  }

  double _parseBalance(DocumentSnapshot snap) {
    if (!snap.exists) return 0.0;
    final data = snap.data() as Map<String, dynamic>?;
    final raw = data?['walletBalance'];
    if (raw is num) return raw.toDouble();
    return 0.0;
  }

  double _parseMednuMoneyBalance(DocumentSnapshot snap) {
    if (!snap.exists) return 0.0;
    final data = snap.data() as Map<String, dynamic>?;
    final raw = data?['mednuMoneyBalance'];
    if (raw is num) return raw.toDouble();
    return 0.0;
  }
}
