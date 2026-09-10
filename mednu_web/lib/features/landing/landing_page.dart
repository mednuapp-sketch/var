import 'package:flutter/material.dart';
import 'widgets/navbar.dart';
import 'widgets/hero_section.dart';
import 'widgets/stats_bar_section.dart';
import 'widgets/how_it_works_section.dart';
import 'widgets/services_section.dart';
import 'widgets/doctors_section.dart';
import 'widgets/hospitals_section.dart';
import 'widgets/why_mednu_section.dart';
import 'widgets/health_articles_section.dart';
import 'widgets/testimonials_section.dart';
import 'widgets/download_app_section.dart';
import 'widgets/footer.dart';

class LandingPage extends StatefulWidget {
  final VoidCallback onLoginTap;
  const LandingPage({super.key, required this.onLoginTap});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scroll = ScrollController();

  final GlobalKey _heroKey        = GlobalKey();
  final GlobalKey _servicesKey    = GlobalKey();
  final GlobalKey _howItWorksKey  = GlobalKey();
  final GlobalKey _doctorsKey     = GlobalKey();
  final GlobalKey _aboutKey       = GlobalKey();
  final GlobalKey _contactKey     = GlobalKey();

  // Ordered list matching page layout — used for scroll detection
  late final List<(String, GlobalKey)> _sectionOrder = [
    ('Home',         _heroKey),
    ('How It Works', _howItWorksKey),
    ('Services',     _servicesKey),
    ('Doctors',      _doctorsKey),
    ('About Us',     _aboutKey),
    ('Contact',      _contactKey),
  ];

  String _activeSection = 'Home';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    _detectActiveSection();
  }

  void _detectActiveSection() {
    if (!mounted) return;
    const threshold = 220.0; // px from top — just below navbar (70px) + buffer

    String detected = 'Home';
    for (final (name, key) in _sectionOrder) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      // Global Y position of the section's top edge on screen
      final topY = box.localToGlobal(Offset.zero).dy;
      if (topY <= threshold) detected = name;
    }

    if (detected != _activeSection) {
      setState(() => _activeSection = detected);
    }
  }

  void _scrollToSection(String item) async {
    // Optimistically update active immediately on click
    if (_activeSection != item) setState(() => _activeSection = item);

    if (item == 'Home') {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      return;
    }

    final keyMap = <String, GlobalKey>{
      'Services':     _servicesKey,
      'How It Works': _howItWorksKey,
      'Doctors':      _doctorsKey,
      'About Us':     _aboutKey,
      'Contact':      _contactKey,
    };

    final key = keyMap[item];
    if (key?.currentContext == null) return;

    // Sections far down this long sliver list can report stale/estimated
    // geometry until Flutter has actually laid them out near the viewport
    // once — that's what caused a click to land one section off and need a
    // second click to correct. A zero-duration jump first forces a real
    // layout pass at the target, then the visible animated scroll runs
    // against fresh, accurate geometry.
    await Scrollable.ensureVisible(
      key!.currentContext!,
      duration: Duration.zero,
      alignment: 0.0,
    );
    if (!mounted) return;
    final settledCtx = key.currentContext;
    if (settledCtx == null) return;
    await Scrollable.ensureVisible(
      settledCtx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _NavbarDelegate(
              onLoginTap: widget.onLoginTap,
              scrollController: _scroll,
              onNavTap: _scrollToSection,
              activeSection: _activeSection,
            ),
          ),

          SliverToBoxAdapter(
            key: _heroKey,
            child: HeroSection(onGetStarted: widget.onLoginTap),
          ),

          const SliverToBoxAdapter(child: StatsBarSection()),

          SliverToBoxAdapter(
            key: _howItWorksKey,
            child: const HowItWorksSection(),
          ),

          SliverToBoxAdapter(
            key: _servicesKey,
            child: const ServicesSection(),
          ),

          SliverToBoxAdapter(
            key: _doctorsKey,
            child: const DoctorsSection(),
          ),

          const SliverToBoxAdapter(child: HospitalsSection()),

          SliverToBoxAdapter(
            key: _aboutKey,
            child: const WhyMednuSection(),
          ),

          const SliverToBoxAdapter(child: HealthArticlesSection()),
          const SliverToBoxAdapter(child: TestimonialsSection()),
          const SliverToBoxAdapter(child: DownloadAppSection()),

          SliverToBoxAdapter(
            key: _contactKey,
            child: WebFooter(onNavTap: _scrollToSection),
          ),
        ],
      ),
    );
  }
}

// ─── Navbar Delegate ──────────────────────────────────────────────────────────

class _NavbarDelegate extends SliverPersistentHeaderDelegate {
  const _NavbarDelegate({
    required this.onLoginTap,
    required this.scrollController,
    required this.onNavTap,
    required this.activeSection,
  });

  final VoidCallback onLoginTap;
  final ScrollController scrollController;
  final void Function(String) onNavTap;
  final String activeSection;

  static const double _height = 70.0;

  @override double get minExtent => _height;
  @override double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return WebNavbar(
      scrollController: scrollController,
      onLoginTap: onLoginTap,
      onNavTap: onNavTap,
      activeSection: activeSection,
    );
  }

  @override
  bool shouldRebuild(covariant _NavbarDelegate old) =>
      old.onLoginTap != onLoginTap ||
      old.onNavTap != onNavTap ||
      old.activeSection != activeSection;
}
