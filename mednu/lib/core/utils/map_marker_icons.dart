import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Map markers drawn in code, so no image assets need shipping. Used for the
/// ambulance on both live-tracking maps; the marker is rotated by the vehicle's
/// heading, so the icon is drawn symmetric about its centre with a small
/// chevron on top that shows which way it is facing.
class MapMarkerIcons {
  MapMarkerIcons._();

  static final Map<int, BitmapDescriptor> _cache = {};

  /// A round ambulance badge (white medical cross on [color]) with a heading
  /// chevron. Cached per colour.
  static Future<BitmapDescriptor> ambulance({Color color = const Color(0xFFC62828)}) async {
    final key = color.toARGB32();
    final cached = _cache[key];
    if (cached != null) return cached;

    const px = 3.0; // render at 3x, tell the map the logical width below
    const logical = 56.0;
    const size = logical * px;
    const c = Offset(size / 2, size / 2);
    const r = size * 0.30;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Soft shadow + white ring + coloured disc.
    canvas.drawCircle(c.translate(0, 3), r + 6, Paint()..color = Colors.black.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(c, r + 6, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()..color = color);

    // Medical cross.
    final cross = Paint()..color = Colors.white;
    const arm = r * 0.30;
    const len = r * 0.95;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: len, height: arm), const Radius.circular(3)), cross);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: arm, height: len), const Radius.circular(3)), cross);

    // Heading chevron, pointing up (north) before the marker is rotated.
    final tipY = c.dy - r - 6 - 2;
    final chevron = Path()
      ..moveTo(c.dx, tipY - 10)
      ..lineTo(c.dx - 12, tipY + 6)
      ..lineTo(c.dx, tipY + 1)
      ..lineTo(c.dx + 12, tipY + 6)
      ..close();
    canvas.drawPath(chevron, Paint()..color = color);
    canvas.drawPath(chevron, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: logical);
    _cache[key] = icon;
    return icon;
  }

  /// Great-circle bearing in degrees from [a] to [b] (0 = north). Used to
  /// orient the marker when the device reports no heading yet.
  static double bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
