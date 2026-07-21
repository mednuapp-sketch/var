import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/r.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  int? _expandedFaqIndex;

  // ── FAQ Data ──────────────────────────────────────────────────────────────

  static const _faqSections = [
    _FaqSection(
      title: 'General',
      icon: Icons.info_outline_rounded,
      color: Color(0xFF1565C0),
      faqs: [
        _Faq(
          q: 'What is MedNU?',
          a: 'MedNU is a comprehensive healthcare platform that connects you with doctors, hospitals, pharmacies, and medical services — all in one app. From video consultations to medicine delivery, MedNU makes healthcare accessible for your whole family.',
        ),
        _Faq(
          q: 'How do I add family members?',
          a: 'Go to Profile → Family Management → tap the "+" button. Add their name, relationship, date of birth, and gender. You can manage health records for each member separately.',
        ),
        _Faq(
          q: 'Is my health data secure?',
          a: 'Yes. MedNU uses end-to-end encryption and follows HIPAA-compliant data practices. Your health information is never shared with third parties without your explicit consent.',
        ),
        _Faq(
          q: 'How do I change my language?',
          a: 'Go to Settings → Appearance → Language. Select from English, Telugu, or Hindi. The app will instantly update to your selected language.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Appointments',
      icon: Icons.calendar_today_rounded,
      color: Color(0xFFC2185B),
      faqs: [
        _Faq(
          q: 'How do I book a doctor appointment?',
          a: 'Go to Home → Tap "Appointment" or browse doctors. Select a doctor, choose a date and time slot, then tap "Book Appointment". You will receive a confirmation notification.',
        ),
        _Faq(
          q: 'How do I cancel an appointment?',
          a: 'Go to "My Appointments" (bottom nav), find your booked appointment, and tap the cancel button. Cancellations made 2+ hours before the appointment are fully refunded.',
        ),
        _Faq(
          q: 'How does video consultation work?',
          a: 'Tap "Consult" on the home screen. Select a doctor who is online, tap "Quick Connect" for an instant video call, or schedule a session for a later time. You need a stable internet connection.',
        ),
        _Faq(
          q: 'Can I reschedule an appointment?',
          a: 'Yes. Go to My Appointments, select the appointment, and tap "Reschedule". Choose a new time slot. Rescheduling is free if done more than 2 hours before the original appointment.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Payments',
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF2E7D32),
      faqs: [
        _Faq(
          q: 'What payment methods are accepted?',
          a: 'MedNU accepts UPI, credit/debit cards, net banking, and MedNU Wallet. You can add money to your wallet via the Wallet screen for faster checkouts.',
        ),
        _Faq(
          q: 'How do I get a refund?',
          a: 'Refunds are processed within 5–7 business days for cancelled appointments (>2 hours notice). For technical failures, full refunds are issued within 24 hours. Contact support@mednu.in for help.',
        ),
        _Faq(
          q: 'Is the MedNU Wallet safe?',
          a: 'Yes. Your wallet is secured with your MPIN and all transactions are encrypted. Wallet credits are non-transferable and expire after 12 months of account inactivity.',
        ),
        _Faq(
          q: 'How do I add money to my wallet?',
          a: 'Go to Wallet → Add Money. Enter the amount, choose your preferred payment method, and confirm. Money is credited instantly to your MedNU Wallet.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Technical',
      icon: Icons.settings_rounded,
      color: Color(0xFF7B1FA2),
      faqs: [
        _Faq(
          q: 'How do I track my medicine order?',
          a: 'After placing a medicine order, you will be redirected to the tracking screen automatically. You can also find active orders in "My Bookings". The screen shows real-time location and ETA.',
        ),
        _Faq(
          q: 'The app is not loading. What should I do?',
          a: 'Try the following: (1) Check your internet connection. (2) Force-close the app and reopen. (3) Clear the app cache from Settings. (4) Update to the latest version. If the issue persists, contact support.',
        ),
        _Faq(
          q: 'How do I reset my MPIN?',
          a: 'Go to Settings → Security → Change MPIN. You will need to verify your phone number via OTP before setting a new MPIN.',
        ),
        _Faq(
          q: 'How do I delete my account?',
          a: 'Go to Profile → Settings → Account → Delete Account. Note: Account deletion is permanent. All your data will be removed within 30 days as per our Privacy Policy.',
        ),
      ],
    ),
  ];

  List<(int sectionIdx, int faqIdx, _Faq faq)> get _filteredFaqs {
    if (_query.isEmpty) return [];
    final results = <(int, int, _Faq)>[];
    final q = _query.toLowerCase();
    for (var si = 0; si < _faqSections.length; si++) {
      final section = _faqSections[si];
      for (var fi = 0; fi < section.faqs.length; fi++) {
        final faq = section.faqs[fi];
        if (faq.q.toLowerCase().contains(q) || faq.a.toLowerCase().contains(q)) {
          results.add((si, fi, faq));
        }
      }
    }
    return results;
  }

  // ── URL Launchers ─────────────────────────────────────────────────────────

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mednu.in',
      queryParameters: {
        'subject': 'MedNU App Support',
        'body': 'Hi MedNU Support Team,\n\nI need help with:\n\n',
      },
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchPhone() async {
    final uri = Uri(scheme: 'tel', path: '+919000000000');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp() async {
    final uri = Uri.parse(
        'https://wa.me/919000000000?text=Hi%20MedNu%20Support,%20I%20need%20help%20with');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 170),
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 56),
                          R.p(context, 20), R.p(context, 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(R.p(context, 10)),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(R.r(context, 12)),
                            ),
                            child: Icon(Icons.support_agent_rounded, color: Colors.white, size: R.w(context, 28)),
                          ),
                          SizedBox(height: R.h(context, 10)),
                          const Text(
                            'Help & Support',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 22,
                              fontWeight: FontWeight.w800, color: Colors.white,
                            ),
                          ),
                          const Text(
                            'We\'re here to help you 24/7',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              color: Colors.white70,
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
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(R.p(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Contact Cards
          _buildContactRow(context),
          SizedBox(height: R.h(context, 16)),

          // Support Hours
          _buildSupportHours(context),
          SizedBox(height: R.h(context, 20)),

          // Search Bar
          _buildSearchBar(context),
          SizedBox(height: R.h(context, 16)),

          // FAQ Content
          if (_query.isNotEmpty) _buildSearchResults(context) else _buildFaqSections(context),

          SizedBox(height: R.h(context, 20)),

          // Submit Ticket
          _buildSubmitTicketCard(context),
          SizedBox(height: R.h(context, 32)),
        ],
      ),
    );
  }

  Widget _buildContactRow(BuildContext context) {
    return Row(
      children: [
        _QuickContactCard(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          color: const Color(0xFF2E7D32),
          onTap: _launchWhatsApp,
        ),
        SizedBox(width: R.w(context, 10)),
        _QuickContactCard(
          icon: Icons.phone_rounded,
          label: 'Call Us',
          color: const Color(0xFF1565C0),
          onTap: _launchPhone,
        ),
        SizedBox(width: R.w(context, 10)),
        _QuickContactCard(
          icon: Icons.email_rounded,
          label: 'Email',
          color: AppColors.primary,
          onTap: _launchEmail,
        ),
      ],
    );
  }

  Widget _buildSupportHours(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(R.p(context, 14)),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.r(context, 12)),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time_filled_rounded, color: const Color(0xFF1565C0), size: R.w(context, 20)),
          SizedBox(width: R.w(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Support Hours',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w700, color: Color(0xFF1565C0),
                  ),
                ),
                SizedBox(height: R.h(context, 2)),
                Text(
                  'Mon–Sat: 8 AM – 10 PM  •  Sun: 9 AM – 6 PM',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() {
        _query = v;
        _expandedFaqIndex = null;
      }),
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search FAQs...',
        hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: context.appTextHint),
        prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
        filled: true,
        fillColor: context.appSurface,
        contentPadding: EdgeInsets.symmetric(vertical: R.p(context, 14), horizontal: R.p(context, 16)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.r(context, 12)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.r(context, 12)),
          borderSide: BorderSide(color: context.appBorder.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.r(context, 12)),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear_rounded, color: context.appTextHint, size: R.w(context, 20)),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _expandedFaqIndex = null;
                  });
                },
              )
            : null,
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final results = _filteredFaqs;
    if (results.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: R.p(context, 32)),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: R.w(context, 48), color: context.appTextHint),
              SizedBox(height: R.h(context, 12)),
              Text(
                'No results for "$_query"',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w600, color: context.appTextPrimary,
                ),
              ),
              SizedBox(height: R.h(context, 6)),
              Text(
                'Try different keywords or contact our support team.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: R.p(context, 12)),
          child: Text(
            '${results.length} result${results.length == 1 ? '' : 's'} for "$_query"',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w600, color: context.appTextSecondary,
            ),
          ),
        ),
        ...results.asMap().entries.map((e) {
          final idx = e.key;
          final (si, _, faq) = e.value;
          final section = _faqSections[si];
          return _FaqTile(
            faq: faq,
            isExpanded: _expandedFaqIndex == idx,
            accentColor: section.color,
            onTap: () => setState(() => _expandedFaqIndex = _expandedFaqIndex == idx ? null : idx),
          );
        }),
      ],
    );
  }

  Widget _buildFaqSections(BuildContext context) {
    // Use a unique index offset per section so _expandedFaqIndex is globally unique
    int globalIdx = 0;
    final sections = <Widget>[];

    for (final section in _faqSections) {
      final startIdx = globalIdx;
      sections.add(_buildSectionHeader(context, section));
      sections.add(SizedBox(height: R.h(context, 10)));
      for (var i = 0; i < section.faqs.length; i++) {
        final idx = startIdx + i;
        sections.add(
          _FaqTile(
            faq: section.faqs[i],
            isExpanded: _expandedFaqIndex == idx,
            accentColor: section.color,
            onTap: () => setState(() => _expandedFaqIndex = _expandedFaqIndex == idx ? null : idx),
          ),
        );
        globalIdx++;
      }
      sections.add(SizedBox(height: R.h(context, 16)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  Widget _buildSectionHeader(BuildContext context, _FaqSection section) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(R.p(context, 7)),
          decoration: BoxDecoration(
            color: section.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(R.r(context, 8)),
          ),
          child: Icon(section.icon, color: section.color, size: R.w(context, 16)),
        ),
        SizedBox(width: R.w(context, 10)),
        Text(
          section.title,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 14,
            fontWeight: FontWeight.w700, color: section.color,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitTicketCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(R.r(context, 16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.support_agent_rounded, color: Colors.white, size: R.w(context, 36)),
          SizedBox(height: R.h(context, 10)),
          const Text(
            'Still need help?',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 17,
              fontWeight: FontWeight.w700, color: Colors.white,
            ),
          ),
          SizedBox(height: R.h(context, 6)),
          const Text(
            'Our support team responds within 30 minutes during business hours.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: R.h(context, 16)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _launchWhatsApp,
                  icon: Icon(Icons.chat_rounded, size: R.w(context, 16)),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 10))),
                    padding: EdgeInsets.symmetric(vertical: R.p(context, 12)),
                    textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(width: R.w(context, 10)),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _launchEmail,
                  icon: Icon(Icons.email_rounded, size: R.w(context, 16)),
                  label: const Text('Email Us'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 10))),
                    padding: EdgeInsets.symmetric(vertical: R.p(context, 12)),
                    textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Data Models ───────────────────────────────────────────────────────────────

class _Faq {
  final String q, a;
  const _Faq({required this.q, required this.a});
}

class _FaqSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Faq> faqs;
  const _FaqSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.faqs,
  });
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _QuickContactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickContactCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: R.p(context, 14)),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(R.r(context, 12)),
              border: Border.all(color: context.appBorder.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: R.w(context, 40),
                  height: R.h(context, 40),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: R.w(context, 20)),
                ),
                SizedBox(height: R.h(context, 6)),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  final bool isExpanded;
  final Color accentColor;
  final VoidCallback onTap;

  const _FaqTile({
    required this.faq,
    required this.isExpanded,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: R.p(context, 8)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 12)),
        border: Border.all(
          color: isExpanded ? accentColor.withValues(alpha: 0.4) : context.appBorder.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(R.r(context, 12)),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(R.p(context, 14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: R.w(context, 26),
                    height: R.h(context, 26),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        'Q',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w800, color: accentColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: R.w(context, 10)),
                  Expanded(
                    child: Text(
                      faq.q,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: context.appTextPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: R.w(context, 8)),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: context.appTextHint,
                    size: R.w(context, 20),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, indent: 50, color: accentColor.withValues(alpha: 0.15)),
            Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 50), R.p(context, 10), R.p(context, 14), R.p(context, 14)),
              child: Text(
                faq.a,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: context.appTextSecondary, height: 1.65,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
