import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/ux_widgets.dart';

/// Profile avatar with cached network image, initials fallback, and an
/// optional verification badge — reused by the app shell, profile screens,
/// and settings header across every partner role.
class SharedProfileAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  final bool isVerified;
  final Color? ringColor;

  const SharedProfileAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 48,
    this.isVerified = false,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;

    final avatar = hasPhoto
        ? ClipOval(
            child: CachedNetworkImage(
              imageUrl: photoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => SkeletonCircle(size: size),
              errorWidget: (_, __, ___) => AppAvatar(
                name: name,
                size: size,
                color: ringColor,
              ),
            ),
          )
        : AppAvatar(name: name, size: size, color: ringColor);

    if (!isVerified) return avatar;

    final badgeSize = size * 0.32;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.6),
              ),
              child: Icon(
                Icons.verified_rounded,
                size: badgeSize * 0.72,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
