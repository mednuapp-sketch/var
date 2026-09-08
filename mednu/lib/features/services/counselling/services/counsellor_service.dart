import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/counsellor_model.dart';

/// Read-only access to the public `counsellors` catalogue. Mirrors
/// `PhysiotherapistService` exactly — specialty values are free-typed by the
/// counsellor at registration (no fixed enum), so matching against a curated
/// filter chip is a case-insensitive substring check client-side rather than
/// an exact server-side query.
class CounsellorService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<CounsellorModel>> counsellorsStream() {
    return _db
        .collection('counsellors')
        .where('isAvailable', isEqualTo: true)
        .orderBy('rating', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => CounsellorModel.fromFirestore(d)).toList());
  }

  static Stream<CounsellorModel?> counsellorStream(String id) {
    return _db
        .collection('counsellors')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? CounsellorModel.fromFirestore(d) : null);
  }
}
