import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    {
      'q': 'How do I go online to accept consultations?',
      'a': 'On the Home tab, toggle the Online/Offline switch. GPS must be enabled for patients to find you.',
    },
    {
      'q': 'How are earnings calculated?',
      'a': 'Earnings are calculated based on your consultation fee for each completed appointment. Payouts are processed weekly every Monday.',
    },
    {
      'q': 'What happens if I miss an incoming call?',
      'a': 'If you do not accept within 30 seconds, the request is automatically declined and the patient is notified to try again.',
    },
    {
      'q': 'How do I update my availability schedule?',
      'a': 'Go to Profile → Availability Schedule. Set your working days and hours, then tap Save.',
    },
    {
      'q': 'How long does document verification take?',
      'a': 'Medical document verification typically takes 24–48 business hours. You will receive an SMS and in-app notification once approved.',
    },
    {
      'q': 'Can patients see my location?',
      'a': 'Patients can see your approximate area (within 10 km) when you are online. Your exact address is never shared.',
    },
  ];

  Future<void> _launchPhone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: '+911800MEDHELP');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showFallback(context, 'Helpline', '+91 1800-MED-HELP');
      }
    } catch (_) {
      _showFallback(context, 'Helpline', '+91 1800-MED-HELP');
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'doctors@mednu.in',
      queryParameters: {
        'subject': 'Doctor Support Request - MedNu Doctor App',
        'body':
            'Hi MedNu Support Team,\n\nI need help with:\n\n[Describe your issue here]\n\nThank you.',
      },
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showFallback(context, 'Email Support', 'doctors@mednu.in');
      }
    } catch (_) {
      _showFallback(context, 'Email Support', 'doctors@mednu.in');
    }
  }

  void _showFallback(BuildContext context, String title, String contact) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 22),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No compatible app found. Please contact us directly:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                contact,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF880E4F),
                      Color(0xFFC2185B),
                      Color(0xFF7B1FA2)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.18),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withValues(alpha:0.3),
                                    width: 1.5),
                              ),
                              child: const Icon(Icons.support_agent_rounded,
                                  color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Help & Support',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '24/7 doctor support available',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Quick contact
                Text('Contact Us', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                _ContactCard(
                  icon: Icons.phone_rounded,
                  color: AppColors.success,
                  title: 'Doctor Helpline',
                  subtitle: '+91 1800-MED-HELP',
                  onTap: () => _launchPhone(context),
                ),
                const SizedBox(height: 8),
                _ContactCard(
                  icon: Icons.email_rounded,
                  color: AppColors.info,
                  title: 'Email Support',
                  subtitle: 'doctors@mednu.in',
                  onTap: () => _launchEmail(context),
                ),
                const SizedBox(height: 8),
                _ContactCard(
                  icon: Icons.chat_bubble_rounded,
                  color: AppColors.secondary,
                  title: 'Live Chat',
                  subtitle: 'Average response: 5 minutes',
                  onTap: () => context.push(AppRoutes.liveChat),
                ),
                const SizedBox(height: 24),

                // FAQs
                Text('Frequently Asked Questions', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                ...List.generate(
                  _faqs.length,
                  (i) => _FaqTile(
                    question: _faqs[i]['q']!,
                    answer: _faqs[i]['a']!,
                  ),
                ),
                const SizedBox(height: 24),

                // Report issue
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha:0.05),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.error.withValues(alpha:0.2)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.bug_report_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Text('Report a Problem',
                              style: AppTextStyles.labelLarge
                                  .copyWith(color: AppColors.error)),
                        ]),
                        const SizedBox(height: 8),
                        const Text(
                          'Experiencing a technical issue? Let us know and we\'ll fix it fast.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Send Report'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error),
                            onPressed: () =>
                                context.push(AppRoutes.reportProblem),
                          ),
                        ),
                      ]),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: AppTextStyles.labelLarge),
                  Text(subtitle, style: AppTextStyles.bodySmall),
                ])),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha:0.5)),
          ]),
        ),
      );
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _expanded
                  ? AppColors.primary.withValues(alpha:0.3)
                  : AppColors.divider),
        ),
        child: Column(children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.1),
                      shape: BoxShape.circle),
                  child: const Center(
                      child: Text('?',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              fontSize: 14))),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.question, style: AppTextStyles.labelLarge)),
                Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.primary),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(54, 0, 14, 14),
              child: Text(widget.answer,
                  style: AppTextStyles.bodySmall.copyWith(height: 1.6)),
            ),
        ]),
      );
}
