import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ux_widgets.dart';

/// A responsive photo grid with an "Add Photo" tile — used by the Upload
/// Photos screen. `photoPaths` are Firebase Storage download URLs (the
/// visit doc's `photoUrls` array), so tiles render network images with a
/// remove action per tile.
class PhotoGrid extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final int crossAxisCount;

  const PhotoGrid({
    super.key,
    required this.photoPaths,
    required this.onAdd,
    required this.onRemove,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    // A plain Column-of-Rows rather than a shrink-wrapped GridView: this
    // grid always sits inside the Upload Photos screen's outer ListView, and
    // a nested GridView installs a competing drag recognizer that stalls the
    // outer scroll (NeverScrollableScrollPhysics does not prevent that).
    return staticGrid(
      crossAxisCount: crossAxisCount,
      aspectRatio: 1,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final path in photoPaths)
          _PhotoTile(path: path, onRemove: () => onRemove(path)),
        _AddTile(onTap: onAdd),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: const DottedBorderBox(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_a_photo_rounded, color: AppColors.primary, size: 26),
              SizedBox(height: 4),
              Text('Add Photo', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed-look add-tile border, built from a plain dashed CustomPaint
/// rather than a package, matching how the Ambulance module built its own
/// `RouteLine` dashed connector without pulling in a new dependency.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(color: AppColors.primary.withValues(alpha: 0.4)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  const _DashedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final path = Path()..addRRect(rrect);
    final dashed = _dashPath(path, dashLength: 6, gapLength: 4);
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(Path source, {required double dashLength, required double gapLength}) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      var draw = true;
      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        if (draw) {
          dashed.addPath(metric.extractPath(distance, distance + length), Offset.zero);
        }
        distance += length;
        draw = !draw;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) => oldDelegate.color != color;
}

class _PhotoTile extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _PhotoTile({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            path,
            fit: BoxFit.cover,
            // Grid thumbnails are ~1/3 of the screen wide — decode at that
            // size instead of holding full-resolution camera bitmaps in the
            // image cache (a dozen 12 MP photos otherwise blow the cache).
            cacheWidth: (MediaQuery.sizeOf(context).width / 3 *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
            errorBuilder: (context, error, stack) => Container(
              color: AppColors.primary.withValues(alpha: 0.06),
              child: const Center(
                child: Icon(Icons.broken_image_rounded, color: AppColors.textSecondary, size: 20),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
