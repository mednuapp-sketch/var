import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A prescription the patient attached before checkout (from the medicine
/// browsing screen), not yet linked to an order because no order exists yet.
/// Carried forward into the order's initial write at checkout time —
/// `orders`'s firestore.rules only restrict which fields a patient can
/// *update* later, not which fields they can set on *create*, so this needs
/// no separate write path once checkout runs.
class PendingPrescription {
  final String url;
  final String fileType; // 'image' | 'pdf'
  final String fileName;

  const PendingPrescription({
    required this.url,
    required this.fileType,
    required this.fileName,
  });
}

final pendingPrescriptionProvider =
    StateProvider<PendingPrescription?>((ref) => null);
