import 'package:flutter/material.dart';

/// Network image that still renders when the image host sends no CORS headers
/// (Firebase Storage download URLs don't, unless the bucket CORS is configured).
/// Plain decoding fails silently on web in that case; `prefer` falls back to a
/// native <img> element, which doesn't need CORS. Needs explicit dimensions.
class NetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? fallback;

  const NetImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      loadingBuilder: (context, child, progress) => progress == null ? child : (placeholder ?? SizedBox(width: width, height: height)),
      errorBuilder: (context, error, stack) => fallback ?? const SizedBox.shrink(),
    );
  }
}
