import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/feedback_service.dart';

/// Opens an order/visit address in the device's Maps app so a partner can
/// navigate to it. Tries the native `geo:` handler first, then falls back to a
/// Google Maps web link, which any browser can open.
Future<void> openAddressInMaps(BuildContext context, String address) async {
  final query = address.trim();
  if (query.isEmpty) return;

  final candidates = <Uri>[
    Uri(scheme: 'geo', host: '0,0', queryParameters: {'q': query}),
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}),
  ];

  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // ACTIVITY_NOT_FOUND etc. — try the next option.
    }
  }
  if (context.mounted) {
    FeedbackService.showError(context, 'Could not open Maps on this device.');
  }
}
