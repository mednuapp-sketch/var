import 'package:cloud_firestore/cloud_firestore.dart';
import 'banner_model.dart';

class BannerRepository {
  final FirebaseFirestore _db;

  BannerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Sorts by the admin-set `order` (ascending, lowest first) with ties
  /// broken by newest first. Sorting happens client-side rather than via
  /// Firestore `orderBy('order')` because older banner docs predate that
  /// field — an index-based orderBy would silently drop them from the
  /// results instead of defaulting to 0.
  List<BannerModel> _sortActiveBanners(List<BannerModel> banners) {
    final sorted = banners.where((banner) => banner.isActive).toList();
    sorted.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  /// Live-streamed so an admin enabling/disabling/reordering a banner
  /// reaches an already-open home screen immediately — this used to be a
  /// one-shot `.get()`, so a change only ever showed up on the next cold
  /// load of this provider. Errors are left to propagate as an `AsyncError`
  /// (same convention as every other `.snapshots()`-backed repository in
  /// this app) rather than silently swallowed, unlike the old Future-based
  /// methods this replaces.
  Stream<List<BannerModel>> streamActiveBanners() {
    return _db
        .collection('banners')
        .where('isEnabled', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => _sortActiveBanners(snap.docs.map(BannerModel.fromFirestore).toList()));
  }

  /// The highest-priority currently-active banner (lowest `order`), live.
  Stream<BannerModel?> streamActiveBanner() {
    return streamActiveBanners().map((banners) => banners.isEmpty ? null : banners.first);
  }
}
