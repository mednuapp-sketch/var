import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Referral Config ───────────────────────────────────────
class ReferralConfig {
  final bool referralEnabled;
  final bool rewardsEnabled;
  final double referrerReward;
  final double referredReward;
  final String rewardTriggerCondition;
  final int maxReferralLimit; // 0 = unlimited
  final String campaignTitle;
  final String campaignMessage;
  final String bannerText;
  final DateTime? offerExpiryDate;

  const ReferralConfig({
    this.referralEnabled = true,
    this.rewardsEnabled = true,
    this.referrerReward = 50.0,
    this.referredReward = 25.0,
    this.rewardTriggerCondition = 'on_signup',
    this.maxReferralLimit = 0,
    this.campaignTitle = 'Refer & Earn',
    this.campaignMessage = 'Invite friends to MedNU and earn rewards!',
    this.bannerText = 'Share & earn per referral',
    this.offerExpiryDate,
  });

  factory ReferralConfig.fromMap(Map<String, dynamic> data) {
    return ReferralConfig(
      referralEnabled: data['referralEnabled'] as bool? ?? true,
      rewardsEnabled: data['rewardsEnabled'] as bool? ?? true,
      referrerReward: (data['referrerReward'] as num?)?.toDouble() ?? 50.0,
      referredReward: (data['referredReward'] as num?)?.toDouble() ?? 25.0,
      rewardTriggerCondition:
          data['rewardTriggerCondition'] as String? ?? 'on_signup',
      maxReferralLimit: (data['maxReferralLimit'] as num?)?.toInt() ?? 0,
      campaignTitle: data['campaignTitle'] as String? ?? 'Refer & Earn',
      campaignMessage: data['campaignMessage'] as String? ??
          'Invite friends to MedNU and earn rewards!',
      bannerText:
          data['bannerText'] as String? ?? 'Share & earn per referral',
      offerExpiryDate:
          (data['offerExpiryDate'] as Timestamp?)?.toDate(),
    );
  }

  bool get isExpired =>
      offerExpiryDate != null && DateTime.now().isAfter(offerExpiryDate!);

  String get referrerRewardFormatted =>
      '₹${referrerReward.toStringAsFixed(0)}';

  String get referredRewardFormatted =>
      '₹${referredReward.toStringAsFixed(0)}';
}

// ── Referral Record ───────────────────────────────────────
class ReferralRecord {
  final String id;
  final String referredUserId;
  final String referralCode;
  final String status; // 'pending' | 'rewarded'
  final double referrerRewardAmount;
  final double referredRewardAmount;
  final String triggerCondition;
  final DateTime createdAt;
  final DateTime? rewardedAt;

  const ReferralRecord({
    required this.id,
    required this.referredUserId,
    required this.referralCode,
    required this.status,
    required this.referrerRewardAmount,
    required this.referredRewardAmount,
    required this.triggerCondition,
    required this.createdAt,
    this.rewardedAt,
  });

  factory ReferralRecord.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ReferralRecord(
      id: doc.id,
      referredUserId: d['referredUserId'] as String? ?? '',
      referralCode: d['referralCode'] as String? ?? '',
      status: d['status'] as String? ?? 'pending',
      referrerRewardAmount:
          (d['referrerRewardAmount'] as num?)?.toDouble() ?? 0.0,
      referredRewardAmount:
          (d['referredRewardAmount'] as num?)?.toDouble() ?? 0.0,
      triggerCondition: d['triggerCondition'] as String? ?? 'on_signup',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rewardedAt: (d['rewardedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isRewarded => status == 'rewarded';
}

// ── Referral validation result ─────────────────────────────
class ReferralValidationResult {
  final bool isValid;
  final String? referrerName;
  final String? error;
  // Reward amounts pulled live from admin referralConfig
  final double referredReward;
  final double referrerReward;

  const ReferralValidationResult({
    required this.isValid,
    this.referrerName,
    this.error,
    this.referredReward = 0.0,
    this.referrerReward = 0.0,
  });

  String get referredRewardFormatted  => '₹${referredReward.toStringAsFixed(0)}';
  String get referrerRewardFormatted  => '₹${referrerReward.toStringAsFixed(0)}';
}

// ── Referral Service ──────────────────────────────────────
class ReferralService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  DocumentReference get _configRef =>
      _db.collection('referralConfig').doc('settings');

  // ── Stream config in realtime ─────────────────────────
  Stream<ReferralConfig> configStream() {
    return _configRef.snapshots().map((snap) {
      if (!snap.exists) return const ReferralConfig();
      return ReferralConfig.fromMap(snap.data() as Map<String, dynamic>);
    });
  }

  // ── Stream current user's referral history ────────────
  Stream<List<ReferralRecord>> myReferralsStream() {
    if (_uid.isEmpty) return Stream.value([]);
    return _db
        .collection('referrals')
        .where('referrerId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ReferralRecord.fromDoc).toList());
  }

  // ── Stream referral stats for current user ────────────
  Stream<Map<String, dynamic>> myStatsStream() {
    if (_uid.isEmpty) return Stream.value({'total': 0, 'rewarded': 0, 'pending': 0, 'earned': 0.0});
    return _db
        .collection('referrals')
        .where('referrerId', isEqualTo: _uid)
        .snapshots()
        .map((snap) {
      int total = snap.size;
      int rewarded = 0;
      int pending = 0;
      double earned = 0.0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['status'] == 'rewarded') {
          rewarded++;
          earned += (d['referrerRewardAmount'] as num?)?.toDouble() ?? 0.0;
        } else {
          pending++;
        }
      }
      return {'total': total, 'rewarded': rewarded, 'pending': pending, 'earned': earned};
    });
  }

  // ── Validate code realtime (for register screen) ─────
  Future<ReferralValidationResult> validateReferralCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      return const ReferralValidationResult(isValid: false);
    }
    if (_uid.isNotEmpty && trimmed == _uid.substring(0, trimmed.length.clamp(1, _uid.length.clamp(1, 8)))) {
      return const ReferralValidationResult(
        isValid: false, error: 'You cannot use your own referral code.',
      );
    }
    try {
      final configSnap = await _configRef.get();
      final config = configSnap.exists
          ? ReferralConfig.fromMap(configSnap.data() as Map<String, dynamic>)
          : const ReferralConfig();
      if (!config.referralEnabled || config.isExpired) {
        return const ReferralValidationResult(
          isValid: false, error: 'Referral program is currently inactive.',
        );
      }
      final query = await _db
          .collection('users')
          .where('referralCode', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        return const ReferralValidationResult(
          isValid: false, error: 'Invalid referral code.',
        );
      }
      final name = query.docs.first.data()['name'] as String? ?? 'a friend';
      return ReferralValidationResult(
        isValid: true,
        referrerName: name,
        referredReward: config.referredReward,
        referrerReward: config.referrerReward,
      );
    } catch (_) {
      return const ReferralValidationResult(
        isValid: false, error: 'Could not verify code. Try again.',
      );
    }
  }

  // ── Apply referral code on new user signup ────────────
  Future<bool> applyReferralCode({
    required String referralCode,
    required String newUserId,
  }) async {
    final code = referralCode.trim().toUpperCase();
    if (code.isEmpty || newUserId.isEmpty) return false;

    final configSnap = await _configRef.get();
    final config = configSnap.exists
        ? ReferralConfig.fromMap(configSnap.data() as Map<String, dynamic>)
        : const ReferralConfig();

    if (!config.referralEnabled || config.isExpired) return false;

    // Find referrer
    final query = await _db
        .collection('users')
        .where('referralCode', isEqualTo: code)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return false;

    final referrerId = query.docs.first.id;
    if (referrerId == newUserId) return false;

    // Ensure new user hasn't already been referred
    final alreadyReferred = await _db
        .collection('referrals')
        .where('referredUserId', isEqualTo: newUserId)
        .limit(1)
        .get();
    if (alreadyReferred.docs.isNotEmpty) return false;

    // Check max referral limit per referrer
    if (config.maxReferralLimit > 0) {
      final count = await _db
          .collection('referrals')
          .where('referrerId', isEqualTo: referrerId)
          .where('status', whereIn: ['rewarded', 'pending'])
          .get();
      if (count.size >= config.maxReferralLimit) return false;
    }

    final isOnSignup = config.rewardTriggerCondition == 'on_signup';
    final referralRef = _db.collection('referrals').doc();

    await referralRef.set({
      'referrerId': referrerId,
      'referrerName': query.docs.first.data()['name'] ?? '',
      'referredUserId': newUserId,
      'referralCode': code,
      'status': isOnSignup ? 'rewarded' : 'pending',
      'referrerRewardAmount': config.referrerReward,
      'referredRewardAmount': config.referredReward,
      'triggerCondition': config.rewardTriggerCondition,
      'createdAt': FieldValue.serverTimestamp(),
      'rewardedAt': isOnSignup ? FieldValue.serverTimestamp() : null,
    });

    if (isOnSignup && config.rewardsEnabled) {
      await _creditRewards(
        referrerId: referrerId,
        newUserId: newUserId,
        referrerReward: config.referrerReward,
        referredReward: config.referredReward,
      );
    }

    return true;
  }

  // ── Trigger reward for non-signup conditions ──────────
  Future<void> triggerReferralReward(String triggerCondition) async {
    if (_uid.isEmpty) return;
    final pending = await _db
        .collection('referrals')
        .where('referredUserId', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending')
        .where('triggerCondition', isEqualTo: triggerCondition)
        .get();
    if (pending.docs.isEmpty) return;

    for (final doc in pending.docs) {
      final d = doc.data();
      await _creditRewards(
        referrerId: d['referrerId'] as String? ?? '',
        newUserId: _uid,
        referrerReward: (d['referrerRewardAmount'] as num?)?.toDouble() ?? 0.0,
        referredReward: (d['referredRewardAmount'] as num?)?.toDouble() ?? 0.0,
      );
      await doc.reference.update({
        'status': 'rewarded',
        'rewardedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Internal: credit wallet for both parties ──────────
  Future<void> _creditRewards({
    required String referrerId,
    required String newUserId,
    required double referrerReward,
    required double referredReward,
  }) async {
    if (referrerId.isEmpty || newUserId.isEmpty) return;
    final batch = _db.batch();

    if (referrerReward > 0) {
      final ref = _db.collection('users').doc(referrerId);
      batch.update(ref, {
        'mednuMoneyBalance': FieldValue.increment(referrerReward),
        'referralPoints': FieldValue.increment(1),
      });
      batch.set(ref.collection('transactions').doc(), {
        'title': 'Referral Bonus',
        'amount': referrerReward,
        'type': 'credit',
        'category': 'referral',
        'walletType': 'mednu_money',
        'description': 'Your friend joined using your referral code',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (referredReward > 0) {
      final ref = _db.collection('users').doc(newUserId);
      batch.update(ref, {
        'mednuMoneyBalance': FieldValue.increment(referredReward),
      });
      batch.set(ref.collection('transactions').doc(), {
        'title': 'Welcome Bonus',
        'amount': referredReward,
        'type': 'credit',
        'category': 'referral',
        'walletType': 'mednu_money',
        'description': 'Joined via referral code — use as MedNU Money for bookings',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // ── In-app notifications ──────────────────────────
    final now = FieldValue.serverTimestamp();
    if (referrerReward > 0 && referrerId.isNotEmpty) {
      await _db
          .collection('patient_notifications')
          .doc(referrerId)
          .collection('items')
          .add({
        'type': 'referral_reward',
        'title': 'Referral Reward Earned! 🎉',
        'body':
            'You earned ₹${referrerReward.toStringAsFixed(0)} MedNU Money because a friend joined MedNU using your referral code. Use it for your next booking!',
        'createdAt': now,
        'deliverAt': now,
        'isRead': false,
        'data': {'ctaRoute': '/referral', 'screen': 'referral'},
      });
    }
    if (referredReward > 0 && newUserId.isNotEmpty) {
      await _db
          .collection('patient_notifications')
          .doc(newUserId)
          .collection('items')
          .add({
        'type': 'welcome_bonus',
        'title': 'Welcome Bonus Added! 🎁',
        'body':
            '₹${referredReward.toStringAsFixed(0)} MedNU Money has been added as a welcome gift! Use it for any MedNU booking.',
        'createdAt': now,
        'deliverAt': now,
        'isRead': false,
        'data': {'ctaRoute': '/wallet', 'screen': 'wallet'},
      });
    }
  }
}
