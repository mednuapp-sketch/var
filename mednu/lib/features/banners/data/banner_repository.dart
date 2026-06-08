import 'package:cloud_firestore/cloud_firestore.dart';
import 'banner_model.dart';

class BannerRepository {
  final FirebaseFirestore _db;

  BannerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Returns the first currently-active banner, or null if none exists.
  /// Active = isEnabled true, within optional start/end date window.
  Future<BannerModel?> fetchActiveBanner() async {
    try {
      final snap = await _db
          .collection('banners')
          .where('isEnabled', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      for (final doc in snap.docs) {
        final banner = BannerModel.fromFirestore(doc);
        if (banner.isActive) return banner;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
