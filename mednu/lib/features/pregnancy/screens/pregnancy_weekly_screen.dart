import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

// --- Helpers ------------------------------------------------------------------

int _trimesterOf(int week) {
  if (week <= 13) return 1;
  if (week <= 26) return 2;
  return 3;
}

String _trimesterLabel(int week) {
  if (week <= 13) return '1st Trimester';
  if (week <= 26) return '2nd Trimester';
  return '3rd Trimester';
}

String _fruitEmoji(int week) {
  const map = {
    4: '??', 5: '??', 6: '??', 7: '??', 8: '??', 9: '??',
    10: '??', 11: '??', 12: '??', 13: '??', 14: '??', 15: '??',
    16: '??', 17: '??', 18: '??', 19: '??', 20: '??', 21: '??',
    22: '??', 23: '??', 24: '??', 25: '??', 26: '??', 27: '??',
    28: '??', 29: '??', 30: '??', 31: '??', 32: '??', 33: '??',
    34: '??', 35: '??', 36: '??', 37: '??', 38: '??', 39: '??', 40: '??',
  };
  final keys = map.keys.toList()..sort();
  String emoji = '??';
  for (final k in keys) { if (k <= week) emoji = map[k]!; }
  return emoji;
}

List<Color> _heroGradient(int week) {
  final t = _trimesterOf(week);
  if (t == 1) return const [Color(0xFF7B1FA2), Color(0xFFC2185B)];
  if (t == 2) return const [Color(0xFF1565C0), Color(0xFF0097A7)];
  return const [Color(0xFFC2185B), Color(0xFFE65100)];
}

// --- Screen -------------------------------------------------------------------

class PregnancyWeeklyScreen extends ConsumerStatefulWidget {
  const PregnancyWeeklyScreen({super.key});

  @override
  ConsumerState<PregnancyWeeklyScreen> createState() => _PregnancyWeeklyScreenState();
}

class _PregnancyWeeklyScreenState extends ConsumerState<PregnancyWeeklyScreen>
    with TickerProviderStateMixin {
  late TabController _tab;
  late int _selectedWeek;
  late ScrollController _weekScroll;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    final profile = ref.read(pregnancyProvider).profile;
    _selectedWeek = profile?.currentWeek.clamp(1, 40) ?? 1;
    _weekScroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToWeek(_selectedWeek));
  }

  void _scrollToWeek(int week) {
    final offset = (week - 1) * 54.0 - 40;
    if (_weekScroll.hasClients) {
      _weekScroll.animateTo(
        offset.clamp(0, _weekScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectWeek(int week) {
    HapticFeedback.selectionClick();
    setState(() => _selectedWeek = week);
    _scrollToWeek(week);
  }

  void _prevWeek() { if (_selectedWeek > 1) _selectWeek(_selectedWeek - 1); }
  void _nextWeek() { if (_selectedWeek < 40) _selectWeek(_selectedWeek + 1); }

  @override
  void dispose() {
    _tab.dispose();
    _weekScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekData = getWeekData(_selectedWeek);
    final gradient = _heroGradient(_selectedWeek);
    final currentWeek = ref.watch(pregnancyProvider).profile?.currentWeek ?? 0;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly Guide', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
            Text('Week $_selectedWeek � ${_trimesterLabel(_selectedWeek)}',
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: context.appTextHint,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: AppTextStyles.labelMedium,
            unselectedLabelStyle: AppTextStyles.bodySmall,
            tabs: const [
              Tab(
                child: Text('Baby',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Tab(
                child: Text('Nutrition',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Tab(
                child: Text('Symptoms',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Tab(
                child: Text('Tips',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _WeekSelectorStrip(
            selectedWeek: _selectedWeek,
            currentWeek: currentWeek,
            scrollController: _weekScroll,
            onSelect: _selectWeek,
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _BabyTab(weekData: weekData, gradient: gradient, selectedWeek: _selectedWeek, onPrev: _prevWeek, onNext: _nextWeek),
                _NutritionTab(weekData: weekData),
                _SymptomsTab(weekData: weekData),
                _TipsTab(weekData: weekData, gradient: gradient),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Week Selector Strip ------------------------------------------------------

class _WeekSelectorStrip extends StatelessWidget {
  final int selectedWeek;
  final int currentWeek;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;
  const _WeekSelectorStrip({
    required this.selectedWeek, required this.currentWeek,
    required this.scrollController, required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: context.appSurface,
    height: 64,
    child: ListView.builder(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 40,
      itemBuilder: (context, i) {
        final week = i + 1;
        final isSelected = week == selectedWeek;
        final isCurrent = week == currentWeek;
        final gradient = _heroGradient(week);

        return GestureDetector(
          onTap: () => onSelect(week),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 6),
            width: 48,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: isSelected ? null : (isCurrent ? gradient.first.withValues(alpha: 0.08) : context.appBackground),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: isSelected ? gradient.first : (isCurrent ? gradient.first.withValues(alpha: 0.4) : context.appBorder),
                width: isSelected ? 0 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: gradient.first.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'W$week',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : (isCurrent ? gradient.first : context.appTextSecondary),
                  ),
                ),
                if (isCurrent && !isSelected)
                  Container(width: 4, height: 4,
                      decoration: BoxDecoration(color: gradient.first, shape: BoxShape.circle)),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// --- Baby Tab -----------------------------------------------------------------

class _BabyTab extends StatelessWidget {
  final WeeklyPregnancyData weekData;
  final List<Color> gradient;
  final int selectedWeek;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _BabyTab({required this.weekData, required this.gradient, required this.selectedWeek, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(
      children: [
        // Hero baby card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: gradient.last.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(
            children: [
              Text(_fruitEmoji(selectedWeek), style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 6),
              Text(weekData.babySizeComparison,
                  style: AppTextStyles.h1.copyWith(color: Colors.white)),
              Text('About the size of a ${weekData.babySizeComparison.toLowerCase()}',
                  style: AppTextStyles.onPrimaryBody),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatPill('??', weekData.babyLength, 'Length'),
                  _StatPill('??', weekData.babyWeight, 'Weight'),
                  _StatPill('??', 'Week $selectedWeek', 'Pregnancy'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _TrimesterMilestoneCard(week: selectedWeek),
        const SizedBox(height: 12),

        _InfoCard(
          icon: Icons.child_care_rounded,
          title: 'Baby Development',
          content: weekData.development,
          color: gradient.first,
        ),
        const SizedBox(height: 12),

        _InfoCard(
          icon: Icons.pregnant_woman_rounded,
          title: 'Your Body This Week',
          content: weekData.motherChanges,
          color: AppColors.primary,
        ),
        const SizedBox(height: 20),

        // Prev / Next navigation
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: selectedWeek > 1 ? onPrev : null,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text('Week ${selectedWeek - 1}', style: AppTextStyles.labelMedium),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: selectedWeek < 40 ? onNext : null,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
              label: Text('Week ${selectedWeek + 1}',
                  style: AppTextStyles.labelMedium.copyWith(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ],
    ),
  );
}

class _StatPill extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatPill(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text('$emoji $value', style: AppTextStyles.labelMedium.copyWith(color: Colors.white)),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: Colors.white70)),
      ],
    ),
  );
}

// --- Trimester Milestone Card -------------------------------------------------

class _TrimesterMilestoneCard extends StatelessWidget {
  final int week;
  const _TrimesterMilestoneCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final trimester = _trimesterOf(week);
    final triStart = trimester == 1 ? 1 : trimester == 2 ? 14 : 27;
    final triEnd = trimester == 1 ? 13 : trimester == 2 ? 26 : 40;
    final progress = ((week - triStart) / (triEnd - triStart)).clamp(0.0, 1.0);
    final gradient = _heroGradient(week);
    final color = gradient.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_trimesterLabel(week),
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white)),
            ),
            const Spacer(),
            Text('Week $triStart�$triEnd',
                style: AppTextStyles.bodySmall.copyWith(color: color)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Week $triStart', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              Text('${(progress * 100).toInt()}% complete',
                  style: AppTextStyles.bodySmall.copyWith(color: color, fontWeight: FontWeight.w600)),
              Text('Week $triEnd', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Info Card ----------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final Color color;
  const _InfoCard({required this.icon, required this.title, required this.content, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.1)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTextStyles.labelLarge.copyWith(color: color))),
        ]),
        const SizedBox(height: 10),
        Text(content, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.7)),
      ],
    ),
  );
}

// --- Nutrition Tab ------------------------------------------------------------

class _NutritionTab extends StatelessWidget {
  final WeeklyPregnancyData weekData;
  const _NutritionTab({required this.weekData});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF1F8E9), Color(0xFFDCEDC8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('??', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nutrition Focus',
                        style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32))),
                    const SizedBox(height: 4),
                    Text(weekData.nutritionTip,
                        style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF1B5E20), height: 1.6)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TagListCard(
          icon: Icons.check_circle_rounded,
          title: 'Foods to Eat',
          emoji: '?',
          items: weekData.foodsToEat,
          tagColor: const Color(0xFF2E7D32),
          bgColor: const Color(0xFFF1F8E9),
        ),
        const SizedBox(height: 12),
        _TagListCard(
          icon: Icons.cancel_rounded,
          title: 'Foods to Avoid',
          emoji: '?',
          items: weekData.foodsToAvoid,
          tagColor: const Color(0xFFEF5350),
          bgColor: const Color(0xFFFFEBEE),
        ),
        const SizedBox(height: 12),
        _TagListCard(
          icon: Icons.science_rounded,
          title: 'Key Nutrients',
          emoji: '??',
          items: weekData.keyNutrients,
          tagColor: AppColors.secondary,
          bgColor: const Color(0xFFF3E5F5),
        ),
      ],
    ),
  );
}

class _TagListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String emoji;
  final List<String> items;
  final Color tagColor;
  final Color bgColor;
  const _TagListCard({required this.icon, required this.title, required this.emoji,
      required this.items, required this.tagColor, required this.bgColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: tagColor, size: 15),
          const SizedBox(width: 6),
          Text('$emoji $title', style: AppTextStyles.labelMedium.copyWith(color: tagColor)),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tagColor.withValues(alpha: 0.25)),
            ),
            child: Text(item,
                style: AppTextStyles.labelSmall.copyWith(color: tagColor)),
          )).toList(),
        ),
      ],
    ),
  );
}

// --- Symptoms Tab -------------------------------------------------------------

class _SymptomsTab extends StatelessWidget {
  final WeeklyPregnancyData weekData;
  const _SymptomsTab({required this.weekData});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('??', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These are common symptoms for this week. Contact your doctor if symptoms are severe or unusual.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFFE65100), height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (weekData.commonSymptoms.isEmpty)
          const _EmptyState(emoji: '??', message: 'No common symptoms listed for this week.')
        else
          ...weekData.commonSymptoms.asMap().entries.map((e) => _SymptomTile(symptom: e.value, index: e.key)),
      ],
    ),
  );
}

class _SymptomTile extends StatelessWidget {
  final String symptom;
  final int index;
  const _SymptomTile({required this.symptom, required this.index});

  @override
  Widget build(BuildContext context) {
    const colors = [
      AppColors.primary, AppColors.secondary, Color(0xFF1565C0),
      Color(0xFF0097A7), AppColors.success, Color(0xFFE65100),
    ];
    final color = colors[index % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(symptom, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary))),
          Icon(Icons.info_outline_rounded, color: context.appTextHint, size: 16),
        ],
      ),
    );
  }
}

// --- Tips Tab -----------------------------------------------------------------

class _TipsTab extends StatelessWidget {
  final WeeklyPregnancyData weekData;
  final List<Color> gradient;
  const _TipsTab({required this.weekData, required this.gradient});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(
      children: [
        _TipCard(emoji: '??', title: 'Tip of the Week', content: weekData.weeklyTip, gradient: gradient),
        const SizedBox(height: 12),
        _TipCard(emoji: '??', title: 'Your Body', content: weekData.motherChanges,
            gradient: const [Color(0xFFC2185B), Color(0xFFFF6B9D)]),
        const SizedBox(height: 12),
        _TipCard(emoji: '??', title: 'Nutrition', content: weekData.nutritionTip,
            gradient: const [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
        const SizedBox(height: 16),
        _KeyDatesCard(),
      ],
    ),
  );
}

class _TipCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String content;
  final List<Color> gradient;
  const _TipCard({required this.emoji, required this.title, required this.content, required this.gradient});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: gradient.first.withValues(alpha: 0.2)),
      boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelLarge.copyWith(color: gradient.first)),
              const SizedBox(height: 6),
              Text(content, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.7)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KeyDatesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Text('???', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Key Pregnancy Milestones',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        ...const [
          ('Week 1�12', '1st Trimester', '??'),
          ('Week 8�10', 'Heartbeat Detected', '??'),
          ('Week 12', 'First Trimester Ends', '??'),
          ('Week 20', 'Anatomy Scan', '??'),
          ('Week 28', '3rd Trimester Begins', '??'),
          ('Week 40', 'Due Date', '??'),
        ].map((m) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text(m.$3, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(m.$1, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.$2, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary))),
          ]),
        )),
      ],
    ),
  );
}

// --- Empty State --------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String message;
  const _EmptyState({required this.emoji, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(message,
              style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
