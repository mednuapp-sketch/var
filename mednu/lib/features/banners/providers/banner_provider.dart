import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/banner_model.dart';
import '../data/banner_repository.dart';

final bannerRepositoryProvider = Provider<BannerRepository>((ref) {
  return BannerRepository();
});

/// Live-streams the currently active promotional banner — an admin
/// enabling/disabling it is reflected immediately, no re-fetch needed.
final activeBannerProvider = StreamProvider<BannerModel?>((ref) {
  return ref.watch(bannerRepositoryProvider).streamActiveBanner();
});

/// Live-streams every currently active banner for the home screen's ad
/// carousel.
final activeBannersProvider = StreamProvider<List<BannerModel>>((ref) {
  return ref.watch(bannerRepositoryProvider).streamActiveBanners();
});
