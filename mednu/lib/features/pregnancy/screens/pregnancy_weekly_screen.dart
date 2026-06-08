import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyWeeklyScreen extends ConsumerStatefulWidget {
  const PregnancyWeeklyScreen({super.key});

  @override
  ConsumerState<PregnancyWeeklyScreen> createState() =>
      _PregnancyWeeklyScreenState();
}

class _PregnancyWeeklyScreenState extends ConsumerState<PregnancyWeeklyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _selectedWeek = 1;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(pregnancyProvider).profile;
      if (profile != null) {
        setState(() => _selectedWeek = profile.currentWeek);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekData = getWeekData(_selectedWeek);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Weekly Development',
                style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
            Text('Week $_selectedWeek of 40',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Baby'),
            Tab(text: 'Nutrition'),
            Tab(text: 'Symptoms'),
            Tab(text: 'Tips'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildWeekSelector(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildBabyTab(weekData),
                _buildNutritionTab(weekData),
                _buildSymptomsTab(weekData),
                _buildTipsTab(weekData),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() => Container(
    color: Colors.white,
    height: 64,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 40,
      itemBuilder: (context, i) {
        final week = i + 1;
        final selected = week == _selectedWeek;
        return GestureDetector(
          onTap: () => setState(() => _selectedWeek = week),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 6),
            width: 44,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : const Color(0xFFF7F4F8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('W$week',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _buildBabyTab(WeeklyPregnancyData data) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        // Hero card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(_fruitEmoji(data.week), style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 8),
              Text(data.babySizeComparison,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              Text('About the size of a ${data.babySizeComparison.toLowerCase()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _babyStatPill('📏', data.babyLength, 'Length'),
                  _babyStatPill('⚖️', data.babyWeight, 'Weight'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.child_care_rounded,
          title: 'Development This Week',
          content: data.development,
          color: const Color(0xFF7B1FA2),
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.pregnant_woman_rounded,
          title: 'Your Body This Week',
          content: data.motherChanges,
          color: AppColors.primary,
        ),
      ],
    ),
  );

  Widget _babyStatPill(String emoji, String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text('$emoji $value',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    ),
  );

  Widget _buildNutritionTab(WeeklyPregnancyData data) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        // Nutrition tip
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF66BB6A).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Text('🥗', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nutrition Tip',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                    const SizedBox(height: 4),
                    Text(data.nutritionTip,
                        style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF1B5E20))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _listCard(
          icon: Icons.check_circle_outline_rounded,
          title: 'Foods to Eat ✅',
          items: data.foodsToEat,
          iconColor: const Color(0xFF66BB6A),
          bgColor: const Color(0xFFF1F8E9),
        ),
        const SizedBox(height: 12),
        _listCard(
          icon: Icons.cancel_outlined,
          title: 'Foods to Avoid ❌',
          items: data.foodsToAvoid,
          iconColor: const Color(0xFFEF5350),
          bgColor: const Color(0xFFFFEBEE),
        ),
        const SizedBox(height: 12),
        _listCard(
          icon: Icons.science_rounded,
          title: 'Key Nutrients 💊',
          items: data.keyNutrients,
          iconColor: const Color(0xFF7B1FA2),
          bgColor: const Color(0xFFF3E5F5),
        ),
      ],
    ),
  );

  Widget _buildSymptomsTab(WeeklyPregnancyData data) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFA726).withOpacity(0.3)),
          ),
          child: Row(
            children: const [
              Text('⚠️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These are common symptoms for this week. Contact your doctor if symptoms are severe.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE65100), height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...data.commonSymptoms.map((s) => _symptomTile(s)),
      ],
    ),
  );

  Widget _symptomTile(String symptom) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
    ),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Text(symptom, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  Widget _buildTipsTab(WeeklyPregnancyData data) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        _tipCard('💡', 'This Week\'s Tip', data.weeklyTip, const Color(0xFF42A5F5)),
        const SizedBox(height: 12),
        _tipCard('🌙', 'Your Body', data.motherChanges, AppColors.primary),
        const SizedBox(height: 12),
        _tipCard('🥗', 'Nutrition Focus', data.nutritionTip, const Color(0xFF66BB6A)),
      ],
    ),
  );

  Widget _tipCard(String emoji, String title, String content, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.2)),
      boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 6),
              Text(content, style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            Text(content, style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary)),
          ],
        ),
      );

  Widget _listCard({
    required IconData icon,
    required String title,
    required List<String> items,
    required Color iconColor,
    required Color bgColor,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: iconColor, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: iconColor.withOpacity(0.2)),
                ),
                child: Text(item, style: TextStyle(fontSize: 11, color: iconColor, fontWeight: FontWeight.w500)),
              )).toList(),
            ),
          ],
        ),
      );

  String _fruitEmoji(int week) {
    const emojis = {
      4: '🌱', 5: '🫘', 6: '🌿', 7: '🫐', 8: '🍓', 10: '🍋',
      12: '🍈', 14: '🥝', 16: '🥑', 18: '🫑', 20: '🍌', 22: '🌽',
      24: '🌽', 26: '🥬', 28: '🍆', 30: '🥥', 32: '🎃', 36: '🥗',
      38: '🥦', 40: '🎃',
    };
    final keys = emojis.keys.toList()..sort();
    String emoji = '👶';
    for (final k in keys) {
      if (k <= week) emoji = emojis[k]!;
    }
    return emoji;
  }
}
