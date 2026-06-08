import 'package:url_launcher/url_launcher.dart';

class MapsLauncher {
  /// Opens Google Maps at the given coordinates.
  static Future<void> openLocation(double lat, double lng,
      {String? label}) async {
    final q = label != null
        ? Uri.encodeComponent(label)
        : '$lat,$lng';
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng&query_place_id=$q');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Opens Google Maps navigation to the given coordinates.
  static Future<void> navigateTo(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Opens Google Maps showing both origin and destination.
  static Future<void> navigateFromTo({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&origin=$fromLat,$fromLng'
        '&destination=$toLat,$toLng'
        '&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
