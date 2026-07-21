import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardData> _pages = [
    const _OnboardData(
      title: 'MedNU\nAlways With You',
      subtitle: 'Connect with doctors, hospitals, and health services for your entire family — anytime, anywhere.',
      gradient: const LinearGradient(
        colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      icon: Icons.medical_services_rounded,
      badge: 'Always With You',
      showBrand: true,
    ),
    const _OnboardData(
      title: 'Find Specialist\nDoctors Near You',
      subtitle: 'Book appointments, consult online or in-person, track your family health — all in one app.',
      gradient: const LinearGradient(
        colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      icon: Icons.people_alt_rounded,
      badge: 'Family Healthcare',
    ),
    const _OnboardData(
      title: 'Get Online\nConsultation',
      subtitle: 'Connect with verified doctors via video call. Get prescriptions, follow-ups, and health tips instantly.',
      gradient: const LinearGradient(
        colors: [Color(0xFF880E4F), Color(0xFFC2185B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      icon: Icons.video_call_rounded,
      badge: 'Online Consultation',
    ),
  ];

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: Column(
        children: [
          // ── Page view ───────────────────────────────
          Expanded(
            flex: 7,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _OnboardPage(data: _pages[i]),
            ),
          ),

          // ── Bottom controls ─────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                28, 20, 28, MediaQuery.of(context).padding.bottom + 28),
            child: Column(
              children: [
                // Dot indicator
                SmoothPageIndicator(
                  controller: _pageController,
                  count: _pages.length,
                  effect: ExpandingDotsEffect(
                    activeDotColor: AppColors.primary,
                    dotColor: AppColors.primary.withValues(alpha:0.2),
                    dotHeight: 8,
                    dotWidth: 8,
                    expansionFactor: 4,
                    spacing: 6,
                  ),
                ),
                const SizedBox(height: 28),

                // Next / Get Started button (gradient)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha:0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < _pages.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _done();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _currentPage < _pages.length - 1 ? 'Next' : 'Get Started',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Skip
                if (_currentPage < _pages.length - 1)
                  TextButton(
                    onPressed: _done,
                    child: Text(
                      'Skip for now',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: context.appTextSecondary,
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
  const _OnboardPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Illustration area
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(gradient: data.gradient),
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: -40,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.05),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    right: 40,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.04),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Brand header — only on first card
                      if (data.showBrand) ...[
                        Text(
                          'MedNU',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Always With You',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 28,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                      ] else ...[
                        // Badge for other pages
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            data.badge,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      // Illustration container
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha:0.15),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              data.icon,
                              size: 76,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Badge below icon on first card
                      if (data.showBrand) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            data.badge,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Text content
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.title, style: AppTextStyles.h1),
              const SizedBox(height: 12),
              Text(
                data.subtitle,
                style: AppTextStyles.bodyMedium.copyWith(height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnboardData {
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final IconData icon;
  final String badge;
  final bool showBrand;

  const _OnboardData({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.badge,
    this.showBrand = false,
  });
}
