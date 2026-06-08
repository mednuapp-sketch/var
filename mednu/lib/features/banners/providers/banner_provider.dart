import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/banner_model.dart';
import '../data/banner_repository.dart';

final bannerRepositoryProvider = Provider<BannerRepository>((ref) {
  return BannerRepository();
});

/// Fetches the currently active promotional banner once per provider lifetime.
/// Returns null if no active banner exists or on any network error.
final activeBannerProvider = FutureProvider<BannerModel?>((ref) async {
  return ref.read(bannerRepositoryProvider).fetchActiveBanner();
});
