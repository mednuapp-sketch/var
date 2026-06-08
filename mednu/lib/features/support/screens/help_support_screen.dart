import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  int? _expandedIndex;

  static const _faqs = [
    {
      'q': 'How do I book a doctor appointment?',
      'a': 'Go to Home → Tap "Appointment" or browse doctors. Select a doctor, choose a date and time slot, then tap "Book Appointment". You will receive a confirmation notification.',
    },
    {
      'q': 'How do I order medicines?',
      'a': 'Tap "Medicine" on the home screen. Browse or search for medicines, add to cart, and proceed to checkout. Medicines will be delivered to your saved address within 2–4 hours.',
    },
    {
      'q': 'How do I request an ambulance?',
      'a': 'Tap "Ambulance" on the home screen. Choose the ambulance type (Basic, ALS, or ICU), confirm your GPS location, and tap "Request Ambulance Now". You will be connected immediately.',
    },
    {
      'q': 'How does video consultation work?',
      'a': 'Tap "Consult" on the home screen. Select a doctor who is online, tap "Quick Connect" for instant video call, or schedule a session for a later time. You need a stable internet connection.',
    },
    {
      'q': 'How do I track my order?',
      'a': 'After placing a medicine order, you will be redirected to the tracking screen automatically. You can also find active orders in "My Bookings". The screen shows real-time location and ETA.',
    },
    {
      'q': 'How do I cancel an appointment?',
      'a': 'Go to "My Appointments" (bottom nav), find your booked appointment, and tap the cancel button. Cancellations made 2+ hours before the appointment are fully refunded.',
    },
    {
      'q': 'Is my health data secure?',
      'a': 'Yes. MedNu uses end-to-end encryption and follows HIPAA-compliant data practices. Your health information is never shared with third parties without your explicit consent.',
    },
    {
      'q': 'How do I add family members?',
      'a': 'Go to Profile → Family Management → tap the "+" button. Add their name, relationship, date of birth, and gender. You can manage health records for each member separately.',
    },
    {
      'q': 'How do I change my language?',
      'a': 'Go to Settings → Appearance → Language. Select from English, Telugu, or Hindi. The app will instantly update to your selected language.',
    },
    {
      'q': 'What payment methods are accepted?',
      'a': 'MedNu accepts UPI, credit/debit cards, net banking, and MedNu Wallet. You can add money to your wallet via the Wallet screen for faster checkouts.',
    },
  ];

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _faqs.cast();
    return _faqs
        .cast<Map<String, dynamic>>()
        .where((f) =>
            (f['q'] as String).toLowerCase().contains(_query.toLowerCase()) ||
            (f['a'] as String).toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mednu.in',
      queryParameters: {'subject': 'MedNu App Support', 'body': 'Hi MedNu Support Team,\n\nI need help with:\n\n'},
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchPhone() async {
    final uri = Uri(scheme: 'tel', path: '+919000000000');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp() async {
    final uri = Uri.parse('https://wa.me/919000000000?text=Hi%20MedNu%20Support,%20I%20need%20help%20with');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.help_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Help & Support', style: AppTextStyles.onPrimaryH2),
                      Text('We\'re here to help you 24/7', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Contact options
                Row(children: [
                  _ContactCard(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: const Color(0xFF2E7D32),
                    onTap: _launchWhatsApp,
                  ),
                  const SizedBox(width: 10),
                  _ContactCard(
                    icon: Icons.phone_rounded,
                    label: 'Call Us',
                    color: const Color(0xFF1565C0),
                    onTap: _launchPhone,
                  ),
                  const SizedBox(width: 10),
                  _ContactCard(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    color: const Color(0xFFE65100),
                    onTap: _launchEmail,
                  ),
                ]),

                const SizedBox(height: 20),

                // Operating hours
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.access_time_rounded, color: Color(0xFF1565C0), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Support Hours', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
                        const SizedBox(height: 2),
                        Text('Mon–Sat: 8 AM – 10 PM  •  Sun: 9 AM – 6 PM', style: AppTextStyles.bodySmall),
                        Text('Emergency medical helpline: 24/7', style: AppTextStyles.caption.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 20),

                // Search FAQs
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() { _query = v; _expandedIndex = null; }),
                  decoration: InputDecoration(
                    hintText: 'Search FAQs...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppColors.textHint),
                            onPressed: () { _searchController.clear(); setState(() { _query = ''; }); },
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 16),

                Row(children: [
                  const Text('Frequently Asked Questions', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_filtered.length} items', style: AppTextStyles.caption.copyWith(color: const Color(0xFFE65100), fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 12),

                if (_filtered.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text('No results for "$_query"', style: AppTextStyles.h4),
                        const SizedBox(height: 6),
                        Text('Try different keywords or contact support', style: AppTextStyles.bodySmall),
                      ]),
                    ),
                  )
                else
                  ...List.generate(_filtered.length, (i) {
                    final faq = _filtered[i];
                    final isExpanded = _expandedIndex == i;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isExpanded ? const Color(0xFFE65100).withOpacity(0.4) : AppColors.divider,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _expandedIndex = isExpanded ? null : i),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65100).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text('Q', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFE65100))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(faq['q'] as String,
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textHint,
                              ),
                            ]),
                          ),
                        ),
                        if (isExpanded) ...[
                          const Divider(height: 1, indent: 52),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(52, 10, 14, 14),
                            child: Text(
                              faq['a'] as String,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, height: 1.6),
                            ),
                          ),
                        ],
                      ]),
                    );
                  }),

                const SizedBox(height: 20),

                // Still need help?
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(children: [
                    const Icon(Icons.support_agent_rounded, color: Colors.white, size: 32),
                    const SizedBox(height: 10),
                    const Text('Still need help?', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 6),
                    const Text('Our support team responds within 30 minutes during business hours.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _launchEmail,
                      icon: const Icon(Icons.email_rounded, size: 16),
                      label: const Text('Email Support'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFE65100),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    ),
  );
}
