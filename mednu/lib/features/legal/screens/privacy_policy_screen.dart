import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Privacy Policy Screen
// ─────────────────────────────────────────────────────────────────────────────

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _contactEmail = 'privacy@mednu.in';
  static const String _lastUpdated   = '1 July 2025';

  static const _sections = [
    _PolicySection(
      number: '1',
      title: 'Information We Collect',
      content:
          'We collect personal information you provide during registration, '
          'such as your name, phone number, and email address. We also collect '
          'health-related information you share when booking services, '
          'device identifiers, location data (with your permission), and usage '
          'analytics to improve the app experience.',
    ),
    _PolicySection(
      number: '2',
      title: 'How We Use Your Information',
      content:
          'Your information is used to provide and personalise healthcare '
          'services, process bookings and payments, communicate appointment '
          'reminders and service updates, improve app functionality, and comply '
          'with legal obligations. We do not sell your data to third parties.',
    ),
    _PolicySection(
      number: '3',
      title: 'Data Sharing & Disclosure',
      content:
          'We may share your information with healthcare providers you book '
          'through MedNU, payment processors, and technology partners who help '
          'us operate the platform — all bound by strict confidentiality '
          'agreements. We may also disclose information when required by law.',
    ),
    _PolicySection(
      number: '4',
      title: 'Data Security',
      content:
          'We implement industry-standard security measures including TLS '
          'encryption in transit, encrypted storage for sensitive data, '
          'role-based access controls, and regular security audits. No method '
          'of transmission over the internet is 100% secure, but we strive to '
          'protect your data using best practices.',
    ),
    _PolicySection(
      number: '5',
      title: 'Cookies & Tracking',
      content:
          'We use cookies and similar tracking technologies to maintain your '
          'session, remember preferences, and understand how you use MedNU. '
          'You can control cookie settings through your device or browser. '
          'Disabling certain cookies may affect app functionality.',
    ),
    _PolicySection(
      number: '6',
      title: 'Your Rights',
      content:
          'You have the right to access, correct, or delete your personal '
          'information at any time. You may also withdraw consent for data '
          'processing, request data portability, or object to certain uses of '
          'your data. To exercise these rights, contact our privacy team at '
          'privacy@mednu.in.',
    ),
    _PolicySection(
      number: '7',
      title: 'Children\'s Privacy',
      content:
          'MedNU is not directed at children under 13 years of age. We do not '
          'knowingly collect personal information from children. If we discover '
          'that a child has provided us with personal data, we will promptly '
          'delete it from our systems.',
    ),
    _PolicySection(
      number: '8',
      title: 'Changes to This Policy',
      content:
          'We may update this Privacy Policy from time to time. When we do, '
          'we will revise the "Last Updated" date and notify you through the '
          'app or via email. Continued use of MedNU after changes constitutes '
          'acceptance of the updated policy.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Hero header
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 200),
            leading: Padding(
              padding: EdgeInsets.all(R.p(context, 8)),
              child: Material(
                color: Colors.white.withValues(alpha: 0.15),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => context.pop(),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: EdgeInsets.all(R.p(context, 8)),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: R.w(context, 18)),
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient),
                child: Stack(
                  children: [
                    Positioned(
                      top: -50, right: -40,
                      child: Container(
                        width: R.w(context, 160), height: R.h(context, 160),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0, left: -20,
                      child: Container(
                        width: R.w(context, 100), height: R.h(context, 100),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            reverse: true,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                        padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 48), R.p(context, 20), R.p(context, 20)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: EdgeInsets.all(R.p(context, 10)),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(R.r(context, 12)),
                              ),
                              child: Icon(
                                  Icons.privacy_tip_rounded,
                                  color: Colors.white, size: R.w(context, 24)),
                            ),
                            SizedBox(height: R.h(context, 12)),
                            const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: R.h(context, 4)),
                            const Text(
                              'Last updated: $_lastUpdated',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white60,
                              ),
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
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Intro card
                _IntroCard(),

                // Table of contents
                const _TableOfContents(sections: _sections),

                // Sections
                ..._sections.map((s) => _SectionCard(section: s)),

                // Contact card
                const _ContactCard(email: _contactEmail),
                SizedBox(height: R.h(context, 40)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Intro card
// ─────────────────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), 0),
      child: Container(
        padding: EdgeInsets.all(R.p(context, 18)),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.security_rounded,
                color: AppColors.primary, size: R.w(context, 32)),
            SizedBox(width: R.w(context, 14)),
            Expanded(
              child: Text(
                'Your privacy matters to us. This policy explains how MedNU '
                'collects, uses, and protects your information.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.appTextSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Table of contents
// ─────────────────────────────────────────────────────────────────────────────

class _TableOfContents extends StatelessWidget {
  final List<_PolicySection> sections;
  const _TableOfContents({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), 0),
      child: Container(
        padding: EdgeInsets.all(R.p(context, 18)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contents',
                style: AppTextStyles.h4
                    .copyWith(color: context.appTextPrimary)),
            SizedBox(height: R.h(context, 12)),
            ...sections.map((s) => Padding(
                  padding: EdgeInsets.only(bottom: R.p(context, 8)),
                  child: Row(
                    children: [
                      Container(
                        width: R.w(context, 22), height: R.h(context, 22),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(R.r(context, 6)),
                        ),
                        child: Center(
                          child: Text(s.number,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ),
                      SizedBox(width: R.w(context, 10)),
                      Expanded(
                        child: Text(s.title,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: context.appTextSecondary)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section card
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final _PolicySection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 14), R.p(context, 16), 0),
      child: Container(
        padding: EdgeInsets.all(R.p(context, 18)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: R.w(context, 34), height: R.h(context, 34),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(R.r(context, 10)),
                  ),
                  child: Center(
                    child: Text(section.number,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        )),
                  ),
                ),
                SizedBox(width: R.w(context, 12)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: R.p(context, 6)),
                    child: Text(section.title,
                        style: AppTextStyles.h4.copyWith(
                            color: context.appTextPrimary)),
                  ),
                ),
              ],
            ),
            SizedBox(height: R.h(context, 12)),
            Text(
              section.content,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.appTextSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Contact card
// ─────────────────────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final String email;
  const _ContactCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), 0),
      child: Container(
        padding: EdgeInsets.all(R.p(context, 20)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.07),
              AppColors.secondary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Questions?',
                style: AppTextStyles.h4
                    .copyWith(color: context.appTextPrimary)),
            SizedBox(height: R.h(context, 8)),
            Text(
              'If you have questions about this Privacy Policy or how we '
              'handle your data, please reach out to us:',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary, height: 1.5),
            ),
            SizedBox(height: R.h(context, 14)),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('mailto:$email')),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: R.p(context, 14), vertical: R.p(context, 12)),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(R.r(context, 12)),
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_rounded,
                        color: AppColors.primary, size: R.w(context, 20)),
                    SizedBox(width: R.w(context, 10)),
                    Text(email,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        )),
                    const Spacer(),
                    Icon(Icons.open_in_new_rounded,
                        size: R.w(context, 16), color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────

class _PolicySection {
  final String number, title, content;
  const _PolicySection({
    required this.number,
    required this.title,
    required this.content,
  });
}
