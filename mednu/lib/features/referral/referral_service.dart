import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ── Referral Config ───────────────────────────────────────
// Only the REFERRER earns. The amount and on/off switch come live from
// Firestore `app_config/referral` {rewardAmount, enabled}; the reward is paid
// when the referred friend's first booking is COMPLETED. The legacy
// `referralConfig/settings` doc is still honoured for the programme-wide
// switch / expiry (the server enforces both when a code is applied).
class ReferralConfig {
  final bool referralEnabled;
  final bool rewardsEnabled;
  final double referrerReward;
  final int maxReferralLimit; // 0 = unlimited
  final String campaignTitle;
  final String campaignMessage;
  final String bannerText;
  final DateTime? offerExpiryDate;

  const ReferralConfig({
    this.referralEnabled = false,
    this.rewardsEnabled = false,
    this.referrerReward = 0.0,
    this.maxReferralLimit = 0,
    this.campaignTitle = 'Refer & Earn',
    this.campaignMessage = 'Invite friends to MedNU.',
    this.bannerText = 'Share MedNU with friends',
    this.offerExpiryDate,
  });

  /// [reward] is `app_config/referral`; [settings] is the legacy
  /// `referralConfig/settings` (optional).
  factory ReferralConfig.fromDocs(
      Map<String, dynamic>? reward, Map<String, dynamic>? settings) {
    final s = settings ?? const <String, dynamic>{};
    final enabled = reward?['enabled'] == true;
    final amount = (reward?['rewardAmount'] as num?)?.toDouble() ?? 0.0;
    return ReferralConfig(
      referralEnabled: enabled && (s['referralEnabled'] as bool? ?? true),
      rewardsEnabled: enabled && amount > 0,
      referrerReward: amount > 0 ? amount : 0.0,
      maxReferralLimit: (s['maxReferralLimit'] as num?)?.toInt() ?? 0,
      campaignTitle: s['campaignTitle'] as String? ?? 'Refer & Earn',
      campaignMessage:
          s['campaignMessage'] as String? ?? 'Invite friends to MedNU.',
      bannerText: s['bannerText'] as String? ?? 'Share MedNU with friends',
      offerExpiryDate: (s['offerExpiryDate'] as Timestamp?)?.toDate(),
    );
  }

  bool get isExpired =>
      offerExpiryDate != null && DateTime.now().isAfter(offerExpiryDate!);

  /// True only when a reward amount can honestly be promised.
  bool get hasActiveReward =>
      referralEnabled && rewardsEnabled && referrerReward > 0 && !isExpired;

  String get referrerRewardFormatted =>
      '₹${referrerReward.toStringAsFixed(0)}';

  /// Headline used everywhere the reward is mentioned.
  String get earnLine => hasActiveReward
      ? 'Earn $referrerRewardFormatted when a friend you refer completes their first booking'
      : 'Referral rewards are not active right now';

  /// Short version for banners / buttons (null when inactive).
  String? get earnShort =>
      hasActiveReward ? 'Earn $referrerRewardFormatted per referral' : null;
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

  const ReferralValidationResult({
    required this.isValid,
    this.referrerName,
    this.error,
  });
}

// ── Referral Service ──────────────────────────────────────
class ReferralService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  DocumentReference get _configRef =>
      _db.collection('referralConfig').doc('settings');

  DocumentReference get _rewardRef =>
      _db.collection('app_config').doc('referral');

  // ── Stream config in realtime (live from Firestore) ───
  Stream<ReferralConfig> configStream() {
    return _rewardRef.snapshots().asyncMap((snap) async {
      Map<String, dynamic>? settings;
      try {
        final s = await _configRef.get();
        settings = s.data() as Map<String, dynamic>?;
      } catch (_) {}
      return ReferralConfig.fromDocs(
          snap.data() as Map<String, dynamic>?, settings);
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
      final settings = configSnap.data() as Map<String, dynamic>?;
      final expiry = (settings?['offerExpiryDate'] as Timestamp?)?.toDate();
      if ((settings?['referralEnabled'] as bool? ?? true) == false ||
          (expiry != null && DateTime.now().isAfter(expiry))) {
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
      );
    } catch (_) {
      return const ReferralValidationResult(
        isValid: false, error: 'Could not verify code. Try again.',
      );
    }
  }

  // ── Apply referral code on new user signup ────────────
  //
  // `users` is owner-readable only, so the code is resolved SERVER-side by the
  // `applyReferralCode` callable: it rejects unknown codes and self-referral,
  // records who referred this user, and creates the referral record. The
  // reward (for the referrer only) is paid automatically by the server once
  // the new user's FIRST booking is completed. Returns true when a referral was recorded; throws on
  // rejection (the caller treats that as non-fatal).
  Future<bool> applyReferralCode({
    required String referralCode,
    required String newUserId,
  }) async {
    final code = referralCode.trim().toUpperCase();
    if (code.isEmpty || newUserId.isEmpty) return false;
    final result = await FirebaseFunctions.instance
        .httpsCallable('applyReferralCode')
        .call({'code': code});
    final data = (result.data as Map?) ?? const {};
    return data['applied'] == true;
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
      // The server re-reads the referral doc, credits both parties and flips
      // the status to 'rewarded' — all in one transaction.
      await _grantReward(doc.id);
    }
  }

  // ── Internal: server-authoritative payout ─────────────────
  //
  // Wallet balances and referralPoints are write-protected from clients by
  // firestore.rules; the `grantReferralReward` callable is the only path that
  // can credit them. It reads the reward amounts off the referral doc itself
  // (capped by live admin config) — nothing about the payout amount is
  // supplied from here. Calling it twice for the same referral is a no-op.
  Future<void> _grantReward(String referralId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('grantReferralReward')
          .call({'referralId': referralId});
    } on FirebaseFunctionsException catch (e) {
      // Non-fatal: the referral record stands and stays 'pending', so the
      // reward can still be granted on a later trigger.
      debugPrint('grantReferralReward failed: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('grantReferralReward failed: $e');
    }
  }

}
