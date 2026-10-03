import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';

Future<void> openUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Opens the MedNU app if it is installed, otherwise the store listing.
/// On Android Chrome an `intent://` URL launches the app through its `mednu://`
/// scheme and falls back to Play Store when the app is missing. Other platforms
/// go straight to the store.
Future<void> openAppOrStore() async {
  if (kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final fallback = Uri.encodeComponent(AppConstants.playStoreUrl);
    final intent = 'intent://open#Intent;scheme=mednu;package=com.mednu.mednu;'
        'S.browser_fallback_url=$fallback;end';
    await launchUrl(Uri.parse(intent), webOnlyWindowName: '_self');
    return;
  }
  await openUrl(AppConstants.playStoreUrl);
}
