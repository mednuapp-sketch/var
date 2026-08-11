import 'package:flutter/material.dart';

/// A stylized road-grid pattern standing in for a real map — this module
/// is UI-first (see brief: no heavy backend/map SDK wiring yet). Painted
/// rather than an asset so it scales cleanly to any screen size.
class MockMapBackground extends StatelessWidget {
  final Color tint;
  const MockMapBackground({super.key, this.tint = const Color(0xFFEFF3F6)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapGridPainter(tint: tint),
      child: const SizedBox.expand(),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  final Color tint;
  const _MapGridPainter({required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tint);

    final minorRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    final majorRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 7;

    for (double x = 0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorRoad);
    }
    for (double y = 0; y < size.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorRoad);
    }
    canvas.drawLine(Offset(size.width * 0.28, 0), Offset(size.width * 0.28, size.height), majorRoad);
    canvas.drawLine(Offset(0, size.height * 0.42), Offset(size.width, size.height * 0.42), majorRoad);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), majorRoad);
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) => oldDelegate.tint != tint;
}
