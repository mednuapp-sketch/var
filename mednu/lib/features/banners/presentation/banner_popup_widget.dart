import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/banner_model.dart';
import '../../../core/constants/app_colors.dart';

class BannerPopupWidget extends StatelessWidget {
  final BannerModel banner;
  const BannerPopupWidget({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasContent =
        banner.title != null || banner.description != null || banner.ctaText != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 48,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BannerImage(banner: banner),
                  if (hasContent) _BannerContent(banner: banner),
                  if (!hasContent) const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerImage extends StatelessWidget {
  final BannerModel banner;
  const _BannerImage({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(24),
            bottom: (banner.title == null &&
                    banner.description == null &&
                    banner.ctaText == null)
                ? const Radius.circular(24)
                : Radius.zero,
          ),
          child: CachedNetworkImage(
            imageUrl: banner.imageUrl,
            width: double.infinity,
            fit: BoxFit.cover,
            memCacheHeight: 640,
            placeholder: (_, __) => Container(
              height: 220,
              color: AppColors.primaryLight,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 220,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
              ),
              child: const Center(
                child: Icon(Icons.image_rounded, color: Colors.white60, size: 56),
              ),
            ),
          ),
        ),
        // Close button
        Positioned(
          top: 10,
          right: 10,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.42),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerContent extends StatelessWidget {
  final BannerModel banner;
  const _BannerContent({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner.title != null)
            Text(
              banner.title!,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (banner.description != null) ...[
            const SizedBox(height: 5),
            Text(
              banner.description!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                height: 1.5,
              ),
            ),
          ],
          if (banner.ctaText != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _handleCtaTap(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(
                  banner.ctaText!,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
          if (banner.ctaText == null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleCtaTap(BuildContext context) {
    // Save references before popping
    final router = GoRouter.of(context);
    final url = banner.ctaUrl;
    Navigator.of(context).pop();

    if (url == null || url.isEmpty) return;

    if (url.startsWith('/')) {
      router.go(url);
    } else {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}

/// Shows the banner popup with a scale+fade entrance animation.
Future<void> showBannerPopup(BuildContext context, BannerModel banner) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss banner',
    barrierColor: Colors.black.withOpacity(0.65),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => BannerPopupWidget(banner: banner),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
