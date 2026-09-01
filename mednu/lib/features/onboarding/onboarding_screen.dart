import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/r.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_OnboardData> _pages = [
    _OnboardData(
      badge: 'Always With You',
      title: 'Always With\nYou',
      subtitle:
          'Connect with doctors, hospitals, and health services for your entire family — anytime, anywhere.',
      gradient: LinearGradient(
        colors: [AppColors.primary, AppColors.secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      illustrationAsset: 'assets/icons/onboarding-care.svg',
    ),
    _OnboardData(
      badge: 'Family Healthcare',
      title: 'Find Specialist\nDoctors Near You',
      subtitle:
          'Book appointments, consult online or in-person, track your family health — all in one app.',
      gradient: LinearGradient(
        colors: [AppColors.secondary, AppColors.secondaryDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      illustrationAsset: 'assets/icons/onboarding-doctor-pin.svg',
    ),
    _OnboardData(
      badge: 'Online Consultation',
      title: 'Get Online\nConsultation',
      subtitle:
          'Connect with verified doctors via video call. Get prescriptions, follow-ups, and health tips instantly.',
      gradient: LinearGradient(
        colors: [AppColors.primaryDark, AppColors.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      illustrationAsset: 'assets/icons/onboarding-video-call.svg',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  void _next() {
    if (_isLastPage) {
      _done();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 6,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) => _OnboardPage(
                    data: _pages[i],
                    step: i + 1,
                    totalSteps: _pages.length,
                  ),
                ),
              ),

              // ── Persistent bottom controls ─────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  R.p(context, 28),
                  R.p(context, 18),
                  R.p(context, 28),
                  MediaQuery.of(context).padding.bottom + R.p(context, 24),
                ),
                decoration: BoxDecoration(color: context.appSurface),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SmoothPageIndicator(
                      controller: _pageController,
                      count: _pages.length,
                      effect: ExpandingDotsEffect(
                        activeDotColor: context.appPrimary,
                        dotColor: context.appPrimary.withValues(alpha: 0.18),
                        dotHeight: R.h(context, 7),
                        dotWidth: R.w(context, 7),
                        expansionFactor: 4,
                        spacing: R.p(context, 6),
                      ),
                    ),
                    SizedBox(height: R.p(context, 24)),
                    SizedBox(
                      width: double.infinity,
                      height: R.h(context, 56),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(R.r(context, 16)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 16)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLastPage ? 'Get Started' : 'Next',
                                style: AppTextStyles.button.copyWith(
                                  fontSize: R.sp(context, 15),
                                ),
                              ),
                              SizedBox(width: R.p(context, 8)),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: R.w(context, 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Persistent top brand + skip row ─────────────
          Positioned(
            top: topInset + R.p(context, 14),
            left: R.p(context, 20),
            right: R.p(context, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_hospital_rounded,
                        color: Colors.white, size: R.w(context, 18)),
                    SizedBox(width: R.p(context, 6)),
                    Text(
                      'MedNU',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: R.sp(context, 15),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _isLastPage ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _isLastPage,
                    child: TextButton(
                      onPressed: _done,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        padding: EdgeInsets.symmetric(
                          horizontal: R.p(context, 16),
                          vertical: R.p(context, 8),
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        'Skip',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontSize: R.sp(context, 13),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final _OnboardData data;
  final int step;
  final int totalSteps;

  const _OnboardPage({
    required this.data,
    required this.step,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(gradient: data.gradient),
            child: SafeArea(
              bottom: false,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft glow orbs — replaces the flat translucent circles
                  Positioned(
                    top: -60,
                    right: -50,
                    child: _GlowOrb(size: R.w(context, 220)),
                  ),
                  Positioned(
                    bottom: R.h(context, 10),
                    left: -R.w(context, 70),
                    child: _GlowOrb(size: R.w(context, 160)),
                  ),

                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: R.p(context, 16),
                            vertical: R.p(context, 7),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(R.r(context, 20)),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            data.badge,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: R.sp(context, 12),
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        SizedBox(height: R.p(context, 30)),
                        _GlassIconBadge(asset: data.illustrationAsset),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Lifted content sheet ─────────────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            R.p(context, 28),
            R.p(context, 26),
            R.p(context, 28),
            R.p(context, 4),
          ),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(R.r(context, 32)),
              topRight: Radius.circular(R.r(context, 32)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STEP 0$step OF $totalSteps',
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.appPrimary,
                  fontSize: R.sp(context, 11),
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(height: R.p(context, 10)),
              Text(
                data.title,
                style: AppTextStyles.h1.copyWith(
                  fontSize: R.sp(context, 26),
                  color: context.appTextPrimary,
                ),
              ),
              SizedBox(height: R.p(context, 10)),
              Text(
                data.subtitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: R.sp(context, 14),
                  height: 1.6,
                  color: context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  const _GlowOrb({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _GlassIconBadge extends StatelessWidget {
  final String asset;
  const _GlassIconBadge({required this.asset});

  @override
  Widget build(BuildContext context) {
    final outer = R.w(context, 176);
    final inner = R.w(context, 108);

    return Container(
      width: outer,
      height: outer,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: inner,
          height: inner,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.16),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.22),
                blurRadius: 24,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(R.p(context, 14)),
            child: SvgPicture.asset(asset),
          ),
        ),
      ),
    );
  }
}

class _OnboardData {
  final String badge;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final String illustrationAsset;

  const _OnboardData({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.illustrationAsset,
  });
}
