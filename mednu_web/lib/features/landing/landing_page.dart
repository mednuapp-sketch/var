import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
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

  void _scrollToSection(String item) {
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

    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 600),
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
      floatingActionButton: _AiDoctorFab(onTap: widget.onLoginTap),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
            child: const WebFooter(),
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

// ─── Doctor AI Floating Button ────────────────────────────────────────────────

class _AiDoctorFab extends StatefulWidget {
  final VoidCallback onTap;
  const _AiDoctorFab({required this.onTap});

  @override
  State<_AiDoctorFab> createState() => _AiDoctorFabState();
}

class _AiDoctorFabState extends State<_AiDoctorFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(_hovered ? 0.55 : 0.35),
                  blurRadius: _hovered ? 28 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.smart_toy_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Doctor',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )),
                    Text('Ask anything',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white70,
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
