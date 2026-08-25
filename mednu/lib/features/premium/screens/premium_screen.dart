import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PremiumScreen — MedNU Premium subscription
// ─────────────────────────────────────────────────────────────────────────────

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with SingleTickerProviderStateMixin {
  String _selectedPlan = 'yearly';
  bool _loading = false;
  late final AnimationController _shimmerCtrl;

  // ── Plan data ────────────────────────────────────────────
  static const _plans = [
    _Plan(
      id: 'monthly',
      title: 'Monthly',
      price: '₹299',
      perMonth: '₹299/mo',
      period: '/month',
      badge: null,
      savings: null,
    ),
    _Plan(
      id: 'quarterly',
      title: 'Quarterly',
      price: '₹749',
      perMonth: '₹250/mo',
      period: '/3 months',
      badge: 'POPULAR',
      savings: 'Save 16%',
    ),
    _Plan(
      id: 'yearly',
      title: 'Annual',
      price: '₹2,499',
      perMonth: '₹208/mo',
      period: '/year',
      badge: 'BEST VALUE',
      savings: 'Save 30%',
    ),
  ];

  // ── Feature list ─────────────────────────────────────────
  static const _benefits = [
    _Benefit(
      icon: Icons.video_call_rounded,
      title: 'Unlimited Consultations',
      desc: 'Connect with doctors anytime, unlimited times',
      premium: true,
    ),
    _Benefit(
      icon: Icons.bolt_rounded,
      title: 'Priority Booking',
      desc: 'Get appointment slots 2 hours before free users',
      premium: true,
    ),
    _Benefit(
      icon: Icons.hd_rounded,
      title: 'HD Video Calls',
      desc: 'Crystal-clear video for every consultation',
      premium: true,
    ),
    _Benefit(
      icon: Icons.notifications_active_rounded,
      title: 'Smart Medicine Reminders',
      desc: 'AI-powered reminders that adapt to your schedule',
      premium: true,
    ),
    _Benefit(
      icon: Icons.family_restroom_rounded,
      title: 'Family Health Vault',
      desc: 'Manage health records for up to 5 family members',
      premium: true,
    ),
    _Benefit(
      icon: Icons.local_shipping_rounded,
      title: 'Free Pharmacy Delivery',
      desc: 'No delivery charges on all medicine orders',
      premium: true,
    ),
    _Benefit(
      icon: Icons.science_rounded,
      title: 'Discounted Lab Tests',
      desc: 'Up to 30% off on all diagnostic tests',
      premium: true,
    ),
    _Benefit(
      icon: Icons.headset_mic_rounded,
      title: '24/7 Priority Support',
      desc: 'Dedicated support line for premium members',
      premium: true,
    ),
    _Benefit(
      icon: Icons.folder_rounded,
      title: 'Health Records Storage',
      desc: 'Unlimited secure document storage',
      premium: false,
    ),
    _Benefit(
      icon: Icons.analytics_rounded,
      title: 'Health Analytics',
      desc: 'Detailed insights on your health trends',
      premium: false,
    ),
  ];

  // ── Comparison table rows ─────────────────────────────────
  static const _compareRows = [
    _CompareRow('Doctor consultations', 'Limited', 'Unlimited'),
    _CompareRow('Booking priority', 'Standard', 'Priority +2h'),
    _CompareRow('Video call quality', 'SD', 'HD'),
    _CompareRow('Family members', '1', 'Up to 5'),
    _CompareRow('Pharmacy delivery', '₹49 charge', 'FREE'),
    _CompareRow('Lab test discount', 'None', 'Up to 30%'),
    _CompareRow('Medicine reminders', 'Basic', 'AI-powered'),
    _CompareRow('Support', 'Standard', '24/7 Priority'),
  ];

  // ── Testimonials ─────────────────────────────────────────
  static const _testimonials = [
    _Testimonial(
      name: 'Priya Sharma',
      location: 'Mumbai',
      rating: 5,
      text:
          'MedNU Premium changed how my family manages health. Unlimited consultations saved us thousands!',
      initials: 'PS',
    ),
    _Testimonial(
      name: 'Rajesh Kumar',
      location: 'Bangalore',
      rating: 5,
      text:
          'Priority booking is a game-changer. I get appointments in minutes instead of waiting days.',
      initials: 'RK',
    ),
    _Testimonial(
      name: 'Anita Nair',
      location: 'Chennai',
      rating: 5,
      text:
          'The family vault is brilliant. All our health records in one place — so convenient!',
      initials: 'AN',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _subscribe() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Colors.black),
            SizedBox(width: 10),
            Text(
              'Welcome to MedNU Premium!',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFD700),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String get _ctaLabel {
    if (_selectedPlan == 'monthly') return 'Start Free Trial — ₹299/mo';
    return 'Start Free Trial — ₹2,499/yr';
  }

  String get _billingLine {
    if (_selectedPlan == 'monthly') {
      return '₹299 billed monthly • Cancel anytime';
    }
    return '₹2,499 billed yearly • Cancel anytime • Save ₹1,089';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0619),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero SliverAppBar ──────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 360,
            backgroundColor: const Color(0xFF0D0619),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.1),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => context.pop(),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeroSection(loading: _loading),
            ),
          ),

          // ── White card body ────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F4F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 28),

                  // ── Plan selector ──────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Choose Your Plan',
                            style: AppTextStyles.h3),
                        const SizedBox(height: 4),
                        const Text(
                          '7-day free trial on all plans',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: _plans
                              .map(
                                (plan) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        right: plan.id != _plans.last.id
                                            ? 10
                                            : 0),
                                    child: _PlanCard(
                                      plan: plan,
                                      selected: _selectedPlan == plan.id,
                                      onTap: () => setState(
                                          () => _selectedPlan = plan.id),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Benefits ───────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("What You Get", style: AppTextStyles.h3),
                        const SizedBox(height: 4),
                        Text(
                          'Everything you need for complete family care',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: context.appTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._benefits.map((b) => _BenefitRow(benefit: b)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Comparison table ───────────────────
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Free vs Premium', style: AppTextStyles.h3),
                        SizedBox(height: 16),
                        _ComparisonTable(rows: _compareRows),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Testimonials ───────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text('What Members Say',
                            style: AppTextStyles.h3),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _testimonials.length,
                          itemBuilder: (context, index) => Padding(
                            padding: EdgeInsets.only(
                              right: index < _testimonials.length - 1 ? 14 : 0,
                            ),
                            child: _TestimonialCard(
                                testimonial: _testimonials[index]),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // ── Subscribe CTA card ─────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SubscribeCTA(
                      billingLine: _billingLine,
                      ctaLabel: _ctaLabel,
                      loading: _loading,
                      onTap: _subscribe,
                    ),
                  ),

                  const SizedBox(height: 16),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 12, color: context.appTextHint),
                        const SizedBox(width: 5),
                        Text(
                          '100% Secure · Powered by Razorpay · SSL Encrypted',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: context.appTextHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data models (const)
// ─────────────────────────────────────────────────────────────────────────────

class _Plan {
  final String id, title, price, perMonth, period;
  final String? badge, savings;
  const _Plan({
    required this.id,
    required this.title,
    required this.price,
    required this.perMonth,
    required this.period,
    this.badge,
    this.savings,
  });
}

class _Benefit {
  final IconData icon;
  final String title, desc;
  final bool premium;
  const _Benefit({
    required this.icon,
    required this.title,
    required this.desc,
    required this.premium,
  });
}

class _CompareRow {
  final String feature, free, premium;
  const _CompareRow(this.feature, this.free, this.premium);
}

class _Testimonial {
  final String name, location, text, initials;
  final int rating;
  const _Testimonial({
    required this.name,
    required this.location,
    required this.text,
    required this.initials,
    required this.rating,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero Section
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final bool loading;
  const _HeroSection({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D0619), Color(0xFF2A0845), Color(0xFF1A0533)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD700).withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: 20, left: -40,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                  // Crown icon
                  Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 18),

                  // Headline
                  const Text(
                    'Unlock Premium',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  const Text(
                    'Complete healthcare, unlimited access\nfor you and your entire family',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.white60,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  // Benefit chips row
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _HeroChip(label: 'Unlimited Consults'),
                      _HeroChip(label: 'Family Coverage'),
                      _HeroChip(label: 'Free Delivery'),
                      _HeroChip(label: 'Priority Booking'),
                    ],
                  ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: Color(0xFFFFD700), size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Plan Card
// ─────────────────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF1A0533), Color(0xFF4A1068)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : context.appSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                : context.appBorder,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF633058).withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge
            if (plan.badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.badge!,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
              )
            else
              const SizedBox(height: 26),

            // Title
            Text(
              plan.title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 6),

            // Price
            Text(
              plan.price,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color:
                    selected ? const Color(0xFFFFD700) : AppColors.primary,
              ),
            ),
            Text(
              plan.period,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: selected ? Colors.white54 : context.appTextHint,
              ),
            ),

            if (plan.savings != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.savings!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],

            // Per month equivalent
            const SizedBox(height: 6),
            Text(
              plan.perMonth,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: selected ? Colors.white54 : context.appTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Benefit row
// ─────────────────────────────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final _Benefit benefit;
  const _BenefitRow({required this.benefit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: benefit.premium
                  ? const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    )
                  : null,
              color: benefit.premium ? null : context.appBorder,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(benefit.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(benefit.title,
                          style: AppTextStyles.labelLarge,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (!benefit.premium) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'FREE',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(benefit.desc, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.check_circle_rounded,
            color: benefit.premium
                ? const Color(0xFFFFD700)
                : AppColors.accent,
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Comparison Table
// ─────────────────────────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  final List<_CompareRow> rows;
  const _ComparisonTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A0533), Color(0xFF4A1068)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Feature',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'Free',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFFFFD700), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Premium',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Rows
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final isLast = i == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                color: i.isEven ? context.appSurface : const Color(0xFFFAF5FF),
                borderRadius: isLast
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(17))
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.feature,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: context.appTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          row.free,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: context.appTextSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          row.premium,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF633058),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Testimonial Card
// ─────────────────────────────────────────────────────────────────────────────

class _TestimonialCard extends StatelessWidget {
  final _Testimonial testimonial;
  const _TestimonialCard({required this.testimonial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stars
          Row(
            children: List.generate(
              testimonial.rating,
              (_) => const Icon(Icons.star_rounded,
                  color: Color(0xFFFFD700), size: 14),
            ),
          ),
          const SizedBox(height: 10),
          // Quote
          Expanded(
            child: Text(
              '"${testimonial.text}"',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: context.appTextPrimary,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 4,
            ),
          ),
          const SizedBox(height: 12),
          // Author
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    testimonial.initials,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testimonial.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      testimonial.location,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: context.appTextHint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.verified_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Subscribe CTA
// ─────────────────────────────────────────────────────────────────────────────

class _SubscribeCTA extends StatelessWidget {
  final String billingLine, ctaLabel;
  final bool loading;
  final VoidCallback onTap;
  const _SubscribeCTA({
    required this.billingLine,
    required this.ctaLabel,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0533), Color(0xFF4A1068)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF633058).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Highlights row
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CTABadge(icon: Icons.verified_rounded, label: '7-day free trial'),
              SizedBox(width: 16),
              _CTABadge(icon: Icons.cancel_rounded, label: 'Cancel anytime'),
            ],
          ),
          const SizedBox(height: 16),

          // Billing info
          Text(
            billingLine,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.white60,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // CTA Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: loading ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    const Color(0xFFFFD700).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.black54),
                      ),
                    )
                  : Text(
                      ctaLabel,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CTABadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CTABadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 14),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
