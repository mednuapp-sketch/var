import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  String _selectedPlan = 'yearly';

  final List<Map<String, dynamic>> _plans = [
    {
      'id': 'monthly',
      'title': 'Monthly',
      'price': '₹299',
      'period': '/month',
      'savings': null,
      'badge': null,
    },
    {
      'id': 'quarterly',
      'title': 'Quarterly',
      'price': '₹699',
      'period': '/3 months',
      'savings': 'Save 22%',
      'badge': 'POPULAR',
    },
    {
      'id': 'yearly',
      'title': 'Yearly',
      'price': '₹1999',
      'period': '/year',
      'savings': 'Save 44%',
      'badge': 'BEST VALUE',
    },
  ];

  final List<Map<String, dynamic>> _features = [
    {'icon': Icons.video_call_rounded, 'title': 'Unlimited Video Consultations', 'desc': 'Consult any doctor anytime, unlimited times', 'free': false},
    {'icon': Icons.speed_rounded, 'title': 'Priority Booking', 'desc': 'Get appointment slots 2 hours before others', 'free': false},
    {'icon': Icons.family_restroom_rounded, 'title': 'Family Coverage', 'desc': 'Cover upto 5 family members', 'free': false},
    {'icon': Icons.local_shipping_rounded, 'title': 'Free Medicine Delivery', 'desc': 'No delivery charges on all orders', 'free': false},
    {'icon': Icons.science_rounded, 'title': 'Discounted Lab Tests', 'desc': 'Upto 30% off on all diagnostic tests', 'free': false},
    {'icon': Icons.folder_rounded, 'title': 'Health Records Storage', 'desc': 'Unlimited secure document storage', 'free': true},
    {'icon': Icons.notifications_rounded, 'title': 'Smart Health Reminders', 'desc': 'AI-powered personalized health alerts', 'free': true},
    {'icon': Icons.headset_mic_rounded, 'title': '24/7 Priority Support', 'desc': 'Dedicated support line for premium members', 'free': false},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0533),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF1A0533),
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF4A1068)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha:0.4), blurRadius: 20, spreadRadius: 5)],
                        ),
                        child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 16),
                      const Text('MedNU Premium', style: TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                      const Text('Healthcare without limits', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white60)),
                    ],
                  ),
                ),
              ),
            ),
            expandedHeight: 240,
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plans
                    Text('Choose Your Plan', style: AppTextStyles.h3),
                    const SizedBox(height: 16),
                    ...(_plans.map((plan) {
                      final selected = _selectedPlan == plan['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedPlan = plan['id'] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: selected ? const LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF4A1068)]) : null,
                            color: selected ? null : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selected ? const Color(0xFF7B1FA2) : AppColors.border, width: selected ? 2 : 1),
                            boxShadow: selected ? [BoxShadow(color: const Color(0xFF7B1FA2).withValues(alpha:0.2), blurRadius: 12, offset: const Offset(0, 4))] : null,
                          ),
                          child: Row(children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: selected ? Colors.white : AppColors.border, width: 2),
                                color: selected ? const Color(0xFFFFD700) : Colors.transparent,
                              ),
                              child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(plan['title'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textPrimary)),
                                if (plan['badge'] != null) ...[
                                  const SizedBox(width: 8),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(6)), child: Text(plan['badge'] as String, style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black))),
                                ],
                              ]),
                              if (plan['savings'] != null)
                                Text(plan['savings'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: selected ? Colors.white60 : AppColors.accent)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(plan['price'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: selected ? const Color(0xFFFFD700) : AppColors.primary)),
                              Text(plan['period'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: selected ? Colors.white60 : AppColors.textHint)),
                            ]),
                          ]),
                        ),
                      );
                    })),

                    const SizedBox(height: 24),

                    // Features
                    Text('What You Get', style: AppTextStyles.h3),
                    const SizedBox(height: 16),
                    ...(_features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            gradient: f['free'] as bool ? null : const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                            color: f['free'] as bool ? AppColors.divider : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(f['icon'] as IconData, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(f['title'] as String, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis)),
                            if (f['free'] as bool) ...[
                              const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.accent.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)), child: const Text('FREE', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accent))),
                            ],
                          ]),
                          Text(f['desc'] as String, style: AppTextStyles.bodySmall),
                        ])),
                        Icon(Icons.check_circle_rounded, color: f['free'] as bool ? AppColors.accent : const Color(0xFFFFD700), size: 20),
                      ]),
                    ))),

                    const SizedBox(height: 24),

                    // Subscribe button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF4A1068)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(children: [
                        Text(
                          _selectedPlan == 'monthly' ? '₹299/month' : _selectedPlan == 'quarterly' ? '₹233/month (billed ₹699)' : '₹167/month (billed ₹1999)',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFFFD700)),
                        ),
                        const SizedBox(height: 4),
                        const Text('Cancel anytime • No hidden charges', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white60)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: const Text('Welcome to MedNU Premium! 🎉'), backgroundColor: const Color(0xFFFFD700), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                            child: const Text('Subscribe Now', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 16),
                    Center(child: Text('Secure payment via Razorpay • SSL Encrypted', style: AppTextStyles.caption.copyWith(color: AppColors.textHint))),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}