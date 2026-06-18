import 'package:flutter/material.dart';

enum ScreenSize { mobile, tablet, desktop }

class Responsive {
  static ScreenSize of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 768) return ScreenSize.mobile;
    if (w < 1024) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  static bool isMobile(BuildContext context) => of(context) == ScreenSize.mobile;
  static bool isTablet(BuildContext context) => of(context) == ScreenSize.tablet;
  static bool isDesktop(BuildContext context) => of(context) == ScreenSize.desktop;
  static bool isMobileOrTablet(BuildContext context) => of(context) != ScreenSize.desktop;

  static double maxContentWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w > 1440) return 1320;
    if (w > 1024) return 1140;
    if (w > 768) return 960;
    return w;
  }

  static double horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w > 1440) return (w - 1320) / 2;
    if (w > 1024) return 48;
    if (w > 768) return 32;
    return 20;
  }

  static double sectionPaddingV(BuildContext context) {
    return isMobile(context) ? 56 : 96;
  }

  static int gridCrossAxisCount(BuildContext context, {int desktop = 4, int tablet = 2, int mobile = 2}) {
    switch (of(context)) {
      case ScreenSize.desktop: return desktop;
      case ScreenSize.tablet:  return tablet;
      case ScreenSize.mobile:  return mobile;
    }
  }

  static Widget builder({
    required BuildContext context,
    required Widget Function(BuildContext) mobile,
    Widget Function(BuildContext)? tablet,
    required Widget Function(BuildContext) desktop,
  }) {
    final size = of(context);
    if (size == ScreenSize.mobile) return mobile(context);
    if (size == ScreenSize.tablet) return (tablet ?? desktop)(context);
    return desktop(context);
  }
}

class MaxWidth extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;

  const MaxWidth({super.key, required this.child, this.maxWidth, this.padding});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth ?? Responsive.maxContentWidth(context)),
        padding: padding ?? EdgeInsets.symmetric(
          horizontal: Responsive.horizontalPadding(context),
        ),
        child: child,
      ),
    );
  }
}
