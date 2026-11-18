import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weight_loss_subscription.dart';

/// Reads and drives the prepaid weight-loss plan. Subscriptions are written only
/// by Cloud Functions (capturePayment / bookPlanConsultation / cancelWeightLossPlan).
class WeightLossPlanService {
  WeightLossPlanService._();

  static Stream<List<WeightLossSubscription>> subscriptionsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('nutrition_subscriptions')
        .where('patientId', isEqualTo: uid)
        .snapshots()
        .map((s) {
      final list =
          s.docs.map(WeightLossSubscription.fromFirestore).toList();
      // Active plans first, then by start date (newest first).
      list.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.startDate.compareTo(a.startDate);
      });
      return list;
    });
  }

  /// Books one monthly consultation. Same [idempotencyKey] on retry never books twice.
  static Future<void> bookConsultation({
    required String subscriptionId,
    required String date,
    required String timeSlot,
    required String consultationType,
    required String idempotencyKey,
    int? planIndex,
    String notes = '',
    String healthGoal = 'Weight Loss',
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('bookPlanConsultation')
          .call({
        'subscriptionId': subscriptionId,
        'date': date,
        'timeSlot': timeSlot,
        'consultationType': consultationType,
        'idempotencyKey': idempotencyKey,
        if (planIndex != null) 'planIndex': planIndex,
        'notes': notes,
        'healthGoal': healthGoal,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not book. Please try again.');
    }
  }

  /// Cancels the plan. Returns the refunded amount in rupees.
  static Future<num> cancelPlan(String subscriptionId) async {
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('cancelWeightLossPlan')
          .call({'subscriptionId': subscriptionId});
      return ((r.data as Map?)?['refunded'] as num?) ?? 0;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not cancel the plan. Please try again.');
    }
  }
}

final weightLossSubscriptionsProvider =
    StreamProvider.autoDispose<List<WeightLossSubscription>>(
        (ref) => WeightLossPlanService.subscriptionsStream());
