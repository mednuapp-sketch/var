import 'package:cloud_firestore/cloud_firestore.dart';
import 'banner_model.dart';

class BannerRepository {
  final FirebaseFirestore _db;

  BannerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Returns every currently-active banner, sorted by the admin-set
  /// `order` (ascending, lowest first) with ties broken by newest first.
  /// Sorting happens client-side rather than via Firestore `orderBy('order')`
  /// because older banner docs predate that field — an index-based orderBy
  /// would silently drop them from the results instead of defaulting to 0.
  Future<List<BannerModel>> _fetchSortedActiveBanners() async {
    final snap = await _db
        .collection('banners')
        .where('isEnabled', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    final banners = snap.docs
        .map(BannerModel.fromFirestore)
        .where((banner) => banner.isActive)
        .toList();

    banners.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return b.createdAt.compareTo(a.createdAt);
    });
    return banners;
  }

  /// Returns the highest-priority currently-active banner (lowest `order`),
  /// or null if none exists.
  Future<BannerModel?> fetchActiveBanner() async {
    try {
      final banners = await _fetchSortedActiveBanners();
      return banners.isEmpty ? null : banners.first;
    } catch (_) {
      return null;
    }
  }

  /// Returns every currently-active banner (for the home carousel), sorted
  /// by admin-set `order`.
  Future<List<BannerModel>> fetchActiveBanners() async {
    try {
      return await _fetchSortedActiveBanners();
    } catch (_) {
      return [];
    }
  }
}
