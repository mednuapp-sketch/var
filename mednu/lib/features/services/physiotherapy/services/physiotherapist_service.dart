import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/physiotherapist_model.dart';

/// Read-only access to the public `physiotherapists` catalogue. Specialty
/// values are free-typed by the physiotherapist at registration (no fixed
/// enum, unlike doctor specialties), so — like `NutritionService`'s
/// specialization filter — matching against a curated filter chip is done as
/// a case-insensitive substring check client-side rather than an exact
/// server-side query.
class PhysiotherapistService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<PhysiotherapistModel>> physiotherapistsStream() {
    return _db
        .collection('physiotherapists')
        .where('isAvailable', isEqualTo: true)
        .orderBy('rating', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PhysiotherapistModel.fromFirestore(d)).toList());
  }

  static Stream<PhysiotherapistModel?> physiotherapistStream(String id) {
    return _db
        .collection('physiotherapists')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? PhysiotherapistModel.fromFirestore(d) : null);
  }
}
