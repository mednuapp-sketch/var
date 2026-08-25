import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _version = 'v1.0.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 220),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: R.h(context, 20)),
                      Container(
                        width: R.w(context, 80), height: R.h(context, 80),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(R.r(context, 22)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(R.r(context, 22)),
                          child: Image.asset(
                            'assets/icons/mednu_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      SizedBox(height: R.h(context, 12)),
                      const Text('MedNU', style: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                      SizedBox(height: R.h(context, 4)),
                      const Text('Your Family Healthcare Partner', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                      SizedBox(height: R.h(context, 4)),
                      if (_version.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 4)),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(R.r(context, 12)),
                          ),
                          child: Text(_version, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                        ),
                    ],
                  ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(R.p(context, 16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Mission
                const _SectionCard(
                  icon: Icons.favorite_rounded,
                  color: AppColors.primary,
                  title: 'Our Mission',
                  content: 'MedNU is on a mission to make quality healthcare accessible, affordable, and convenient for every Indian family. We connect patients with doctors, hospitals, pharmacies, and medical services — all in one place.',
                ),

                SizedBox(height: R.h(context, 16)),

                // Stats
                Container(
                  padding: EdgeInsets.all(R.p(context, 18)),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF5C6BC0)]),
                    borderRadius: BorderRadius.circular(R.r(context, 18)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _Stat('50K+', 'Patients'),
                    _StatDivider(),
                    _Stat('500+', 'Doctors'),
                    _StatDivider(),
                    _Stat('100+', 'Hospitals'),
                    _StatDivider(),
                    _Stat('4.8★', 'Rating'),
                  ]),
                ),

                SizedBox(height: R.h(context, 20)),

                // Company info
                const _SectionCard(
                  icon: Icons.business_rounded,
                  color: Color(0xFF1565C0),
                  title: 'Company',
                  content: 'MedNU Healthcare Services Private Limited\n'
                      'Registered in India under the Companies Act, 2013',
                ),

                SizedBox(height: R.h(context, 16)),

                // Contact
                const _SectionHeader('Contact Us', Icons.contact_mail_rounded, Color(0xFFE65100)),
                SizedBox(height: R.h(context, 12)),
                _ContactRow(Icons.email_rounded, 'support@mednu.in', () async {
                  final uri = Uri(scheme: 'mailto', path: 'support@mednu.in');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                }),
                SizedBox(height: R.h(context, 8)),
                _ContactRow(Icons.phone_rounded, '+91 99999 99999', () async {
                  final uri = Uri(scheme: 'tel', path: '+919999999999');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                }),
                SizedBox(height: R.h(context, 8)),
                _ContactRow(Icons.language_rounded, 'www.mednu.in', () async {
                  final uri = Uri.parse('https://www.mednu.in');
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }),

                SizedBox(height: R.h(context, 20)),

                // Legal
                const _SectionHeader('Legal', Icons.gavel_rounded, Color(0xFF37474F)),
                SizedBox(height: R.h(context, 12)),
                _LegalTile('Privacy Policy', () => context.push(AppRoutes.privacyPolicy)),
                SizedBox(height: R.h(context, 8)),
                _LegalTile('Terms of Service', () => context.push(AppRoutes.termsOfService)),
                SizedBox(height: R.h(context, 8)),
                _LegalTile('Medical Disclaimer', () {
                  showDialog(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 20))),
                      title: const Text('Medical Disclaimer',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                      content: const SingleChildScrollView(
                        child: Text(
                          'The information provided in MedNU is for general informational and educational purposes only. '
                          'It is not intended as a substitute for professional medical advice, diagnosis, or treatment.\n\n'
                          'Always seek the advice of your physician or other qualified health provider with any questions '
                          'you may have regarding a medical condition. Never disregard professional medical advice or delay '
                          'in seeking it because of something you have read in this app.\n\n'
                          'In case of a medical emergency, call your doctor or emergency services immediately.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.6),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Close',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                }),

                SizedBox(height: R.h(context, 24)),

                // Copyright
                Center(
                  child: Column(children: [
                    const Icon(Icons.favorite_rounded, size: 18, color: AppColors.primary),
                    SizedBox(height: R.h(context, 8)),
                    Text(
                      '© 2024–2026 MedNU Healthcare Services Pvt. Ltd.\nAll rights reserved.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(color: context.appTextHint, height: 1.6),
                    ),
                  ]),
                ),
                SizedBox(height: R.h(context, 32)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String content;
  const _SectionCard({required this.icon, required this.color, required this.title, required this.content});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(R.p(context, 16)),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(R.r(context, 16)),
      border: Border.all(color: context.appBorder),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: R.w(context, 32), height: R.h(context, 32), decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(R.r(context, 10))),
            child: Icon(icon, color: color, size: R.w(context, 17))),
        SizedBox(width: R.w(context, 10)),
        Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]),
      SizedBox(height: R.h(context, 12)),
      Text(content, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextSecondary, height: 1.6)),
    ]),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: R.w(context, 28), height: R.h(context, 28), decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(R.r(context, 8))),
        child: Icon(icon, size: R.w(context, 15), color: color)),
    SizedBox(width: R.w(context, 8)),
    Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
  ]);
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.white60)),
  ]);
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) => Container(width: R.w(context, 1), height: R.h(context, 36), color: Colors.white24);
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _ContactRow(this.icon, this.text, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.all(R.p(context, 12)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 12)),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: R.w(context, 18)),
        SizedBox(width: R.w(context, 12)),
        Text(text, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
        const Spacer(),
        Icon(Icons.arrow_forward_ios_rounded, size: R.w(context, 12), color: context.appTextHint),
      ]),
    ),
  );
}

class _LegalTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const _LegalTile(this.title, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.all(R.p(context, 12)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 12)),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(children: [
        Icon(Icons.article_outlined, color: context.appTextSecondary, size: R.w(context, 18)),
        SizedBox(width: R.w(context, 12)),
        Text(title, style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary)),
        const Spacer(),
        Icon(Icons.chevron_right_rounded, size: R.w(context, 18), color: context.appTextHint),
      ]),
    ),
  );
}
