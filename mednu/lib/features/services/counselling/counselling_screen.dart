import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';

class CounsellingScreen extends StatefulWidget {
  const CounsellingScreen({super.key});

  @override
  State<CounsellingScreen> createState() => _CounsellingScreenState();
}

class _CounsellingScreenState extends State<CounsellingScreen> {
  String? _selectedType;
  String? _selectedMood;
  int _selectedDuration = 30;

  // Base price is for a 30-minute session; other durations scale off it.
  static const _basePrice = 299;
  static const _durations = [15, 30, 45, 60];

  int _priceForDuration(int minutes) => ((_basePrice * minutes) / 30).round();

  // Mood → recommended therapy specialty mapping.
  // Only Low, Anxious and Angry get a session recommendation; Great/Okay show none.
  static const _moodRecommendation = {
    'low':     'Depression & Anxiety',
    'anxious': 'Depression & Anxiety',
    'angry':   'Stress Management',
  };

  final _moods = [
    {'emoji': '😊', 'label': 'Great',   'value': 'great',   'color': const Color(0xFF2E7D32)},
    {'emoji': '😐', 'label': 'Okay',    'value': 'okay',    'color': const Color(0xFF1565C0)},
    {'emoji': '😔', 'label': 'Low',     'value': 'low',     'color': const Color(0xFF7B1FA2)},
    {'emoji': '😰', 'label': 'Anxious', 'value': 'anxious', 'color': const Color(0xFFE65100)},
    {'emoji': '😡', 'label': 'Angry',   'value': 'angry',   'color': const Color(0xFFB71C1C)},
  ];

  final _types = [
    {'title': 'Depression & Anxiety', 'icon': Icons.psychology_rounded,      'color': const Color(0xFF7B1FA2), 'specialty': 'Psychiatry'},
    {'title': 'Stress Management',    'icon': Icons.self_improvement_rounded, 'color': const Color(0xFF1565C0), 'specialty': 'Psychology'},
    {'title': 'Relationship Therapy', 'icon': Icons.favorite_rounded,         'color': const Color(0xFFC2185B), 'specialty': 'Counselling'},
    {'title': 'Child & Teen Therapy', 'icon': Icons.child_care_rounded,       'color': const Color(0xFF2E7D32), 'specialty': 'Pediatric Psychiatry'},
    {'title': 'Addiction Recovery',   'icon': Icons.healing_rounded,          'color': const Color(0xFFE65100), 'specialty': 'Psychiatry'},
    {'title': 'Grief Therapy',        'icon': Icons.spa_rounded,              'color': const Color(0xFF37474F), 'specialty': 'Counselling'},
  ];

  void _bookTherapist() {
    final specialty = Uri.encodeComponent(_selectedType ?? 'Psychiatry');
    context.push('${AppRoutes.doctors}?type=therapist&specialty=$specialty&duration=$_selectedDuration');
  }

  void _selectType(Map<String, dynamic> t) {
    setState(() => _selectedType = t['specialty'] as String);
    _showBookingSheet(t);
  }

  void _talkNow() {
    context.push('${AppRoutes.consultation}?specialty=${Uri.encodeComponent('Psychiatry')}');
  }

  String? get _recommendedTitle {
    if (_selectedMood == null) return null;
    return _moodRecommendation[_selectedMood];
  }

  void _showBookingSheet(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: (t['color'] as Color).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(t['icon'] as IconData, color: t['color'] as Color, size: 32),
          ),
          const SizedBox(height: 16),
          Text(t['title'] as String, style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Find certified therapists specialising in ${t['title']}',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ── Session duration selector ───────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Session Duration', style: AppTextStyles.labelLarge),
          ),
          const SizedBox(height: 10),
          Row(
            children: _durations.map((mins) {
              final sel = _selectedDuration == mins;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setSheetState(() => setState(() => _selectedDuration = mins)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? (t['color'] as Color).withValues(alpha: 0.1) : context.appBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? t['color'] as Color : context.appBorder,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Column(children: [
                      Text(
                        '$mins min',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? t['color'] as Color : context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${_priceForDuration(mins)}',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w500,
                          color: sel ? (t['color'] as Color).withValues(alpha: 0.8) : context.appTextHint,
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // ── Recommendation banner ───────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Longer sessions are recommended for better results',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('${AppRoutes.doctors}?type=therapist&specialty=${t['specialty']}&duration=$_selectedDuration');
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: const Text('Schedule Session'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  foregroundColor: t['color'] as Color,
                  side: BorderSide(color: t['color'] as Color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.consultation);
                },
                icon: const Icon(Icons.video_call_rounded, size: 16),
                label: const Text('Video Session'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: t['color'] as Color,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            'Certified therapists • Fully confidential • Billed by session length',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
        ]),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: AppSpacing.headerPadding(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.psychology_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                Text('Therapy and Counselling', style: AppTextStyles.onPrimaryH2),
                                Text('Confidential mental health support', style: AppTextStyles.onPrimaryBody),
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
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.page(context),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── A. "Talk to Someone Now" prominent button ──────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _talkNow,
                    icon: const Icon(Icons.support_agent_rounded, size: 20),
                    label: const Text('Talk to Someone Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                      elevation: 3,
                      shadowColor: const Color(0xFF7B1FA2).withValues(alpha: 0.4),
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.sectionGap(context)),

                // ── D. Confidential banner ──────────────────────────────────
                Container(
                  padding: EdgeInsets.all(R.p(context, 14)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00695C).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(R.r(context, 14)),
                    border: Border.all(color: const Color(0xFF00695C).withValues(alpha: 0.25)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.lock_rounded, color: Color(0xFF00695C), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All sessions are 100% confidential. Your privacy is protected.',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          color: Color(0xFF00695C), fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: AppSpacing.sectionGap(context)),

                // Session info row
                Row(children: [
                  _InfoChip(Icons.verified_rounded, 'Certified', const Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  _InfoChip(Icons.video_call_rounded, 'Video/Chat', const Color(0xFFE65100)),
                ]),
                SizedBox(height: AppSpacing.sectionGap(context)),

                // ── A. Mood check section ───────────────────────────────────
                Text('How are you feeling today?', style: AppTextStyles.h4),
                const SizedBox(height: 4),
                Text(
                  'We\'ll personalise your therapy recommendation',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextHint),
                ),
                SizedBox(height: R.h(context, 12)),
                Row(
                  children: _moods.map((m) => Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedMood = m['value'] as String);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMood == m['value']
                              ? (m['color'] as Color).withValues(alpha: 0.12)
                              : context.appSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedMood == m['value']
                                ? m['color'] as Color
                                : context.appBorder,
                            width: _selectedMood == m['value'] ? 2 : 1,
                          ),
                          boxShadow: _selectedMood == m['value']
                              ? [BoxShadow(color: (m['color'] as Color).withValues(alpha: 0.15), blurRadius: 8)]
                              : null,
                        ),
                        child: Column(children: [
                          Text(m['emoji'] as String, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(
                            m['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w600,
                              color: _selectedMood == m['value']
                                  ? m['color'] as Color
                                  : context.appTextSecondary,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  )).toList(),
                ),

                // Mood-personalised recommendation banner
                if (_selectedMood != null && _recommendedTitle != null) ...[
                  SizedBox(height: R.h(context, 12)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 10)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(R.r(context, 12)),
                      border: Border.all(color: const Color(0xFF7B1FA2).withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Based on your mood, we recommend: $_recommendedTitle',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500,
                            color: Color(0xFF7B1FA2),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],

                SizedBox(height: AppSpacing.sectionGap(context)),
                Text('I need help with...', style: AppTextStyles.h4),
                SizedBox(height: R.h(context, 12)),

                // ── Therapy type grid ──────────────────────────────────────
                staticGrid(
                  crossAxisCount: 2,
                  aspectRatio: 1.35,
                  crossAxisSpacing: R.p(context, 12),
                  mainAxisSpacing: R.p(context, 12),
                  children: _types.map((t) {
                    final isSelected = _selectedType == t['specialty'];
                    final isRecommended = _recommendedTitle == t['title'];
                    return GestureDetector(
                      onTap: () => _selectType(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.all(R.p(context, 14)),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (t['color'] as Color).withValues(alpha: 0.08)
                              : context.appSurface,
                          borderRadius: BorderRadius.circular(R.r(context, 16)),
                          border: Border.all(
                            color: isSelected
                                ? t['color'] as Color
                                : isRecommended
                                    ? (t['color'] as Color).withValues(alpha: 0.5)
                                    : context.appBorder,
                            width: isSelected || isRecommended ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: (t['color'] as Color).withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (isRecommended && !isSelected)
                            Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (t['color'] as Color).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Recommended',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 8, fontWeight: FontWeight.w700, color: t['color'] as Color),
                                ),
                              ),
                            ),
                          Icon(t['icon'] as IconData, color: t['color'] as Color, size: 30),
                          const SizedBox(height: 6),
                          Text(
                            t['title'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                              color: isSelected ? t['color'] as Color : context.appTextPrimary,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: AppSpacing.sectionGap(context)),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _bookTherapist,
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Find a Therapist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                SizedBox(height: R.h(context, 40)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    ]),
  );
}
