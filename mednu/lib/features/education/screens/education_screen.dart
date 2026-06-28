import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../services/ai_tips_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});
  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _aiService = AiTipsService();

  final List<String> _categories = [
    'All', 'Nutrition', 'Mental Health', 'Heart', 'Diabetes', 'Women', 'Child Care'
  ];

  final List<Map<String, dynamic>> _articles = [
    {'title': 'How to Manage Diabetes with Diet', 'category': 'Diabetes', 'readTime': '5 min read', 'icon': Icons.bloodtype_rounded, 'color': const Color(0xFFB71C1C), 'views': '12.4K'},
    {'title': '10 Signs of Vitamin Deficiency', 'category': 'Nutrition', 'readTime': '4 min read', 'icon': Icons.restaurant_rounded, 'color': const Color(0xFF2E7D32), 'views': '8.2K'},
    {'title': 'Managing Stress in Modern Life', 'category': 'Mental Health', 'readTime': '6 min read', 'icon': Icons.psychology_rounded, 'color': const Color(0xFF7B1FA2), 'views': '15.1K'},
    {'title': 'Heart Healthy Foods You Must Eat', 'category': 'Heart', 'readTime': '5 min read', 'icon': Icons.favorite_rounded, 'color': const Color(0xFFC2185B), 'views': '9.7K'},
    {'title': 'Pregnancy: What to Expect', 'category': 'Women', 'readTime': '8 min read', 'icon': Icons.pregnant_woman_rounded, 'color': const Color(0xFFE91E8C), 'views': '20.3K'},
    {'title': 'Vaccination Schedule for Children', 'category': 'Child Care', 'readTime': '4 min read', 'icon': Icons.child_care_rounded, 'color': const Color(0xFFE65100), 'views': '7.5K'},
    {'title': 'Understanding Blood Pressure', 'category': 'Heart', 'readTime': '3 min read', 'icon': Icons.monitor_heart_rounded, 'color': const Color(0xFFB71C1C), 'views': '11.2K'},
    {'title': 'Benefits of Walking 30 Minutes Daily', 'category': 'Nutrition', 'readTime': '3 min read', 'icon': Icons.directions_walk_rounded, 'color': const Color(0xFF1565C0), 'views': '18.9K'},
  ];

  List<Map<String, dynamic>> get _filtered {
    var list = _selectedCategory == 'All'
        ? _articles
        : _articles.where((a) => a['category'] == _selectedCategory).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) => (a['title'] as String).toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
                    colors: [Color(0xFF1A237E), Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.menu_book_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Health Education', style: AppTextStyles.onPrimaryH2),
                      Text('Learn about health & wellness', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search health topics...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppColors.textHint),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Featured article
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF5C6BC0)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('FEATURED', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 10),
                    const Text('Complete Guide to Healthy Living in 2025', style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 8),
                    const Text('Discover the latest health trends and science-backed tips for a longer, healthier life.', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Icon(Icons.access_time_rounded, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      const Text('10 min read', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => _openArticle(context, {
                          'title': 'Complete Guide to Healthy Living in 2025',
                          'category': 'Nutrition',
                          'readTime': '10 min read',
                          'icon': Icons.health_and_safety_rounded,
                          'color': const Color(0xFF1A237E),
                          'views': '32.1K',
                        }),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A237E),
                          minimumSize: const Size(80, 34),
                        ),
                        child: const Text('Read Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ]),
                ),

                // Categories
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (_, i) {
                      final selected = _selectedCategory == _categories[i];
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCategory = _categories[i]);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF1A237E) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? const Color(0xFF1A237E) : AppColors.border),
                          ),
                          child: Center(
                            child: Text(
                              _categories[i],
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Articles
                if (_filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: AppEmptyState(
                      icon: Icons.article_outlined,
                      title: 'No Articles Found',
                      message: 'Try a different search term or category.',
                      iconColor: Color(0xFF1A237E),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text('${_filtered.length} Article${_filtered.length == 1 ? '' : 's'}', style: AppTextStyles.h4),
                  ),
                  ..._filtered.map((article) => GestureDetector(
                    onTap: () => _openArticle(context, article),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: (article['color'] as Color).withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(article['icon'] as IconData, color: article['color'] as Color, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(article['title'] as String, style: AppTextStyles.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (article['color'] as Color).withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(article['category'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: article['color'] as Color)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
                            const SizedBox(width: 3),
                            Text(article['readTime'] as String, style: AppTextStyles.caption),
                            const Spacer(),
                            const Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textHint),
                            const SizedBox(width: 3),
                            Text(article['views'] as String, style: AppTextStyles.caption),
                          ]),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textHint),
                      ]),
                    ),
                  )),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openArticle(BuildContext context, Map<String, dynamic> article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ArticleSheet(article: article, aiService: _aiService),
    );
  }

}

// ── Article Detail Sheet ──────────────────────────────────
class _ArticleSheet extends StatefulWidget {
  final Map<String, dynamic> article;
  final AiTipsService aiService;
  const _ArticleSheet({required this.article, required this.aiService});

  @override
  State<_ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends State<_ArticleSheet> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final title = widget.article['title'] as String;
      final cat = widget.article['category'] as String;
      final content = await widget.aiService.askQuestion(
        'Write a detailed, practical health article (about 250 words) on the topic: "$title". '
        'Category: $cat. Use simple language. Include 3–5 key tips formatted as bullet points. '
        'End with a reminder to consult a doctor for personalised advice. No markdown headers.',
      );
      if (mounted) setState(() { _content = content; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _content = null; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.article['color'] as Color;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.all(20), children: [
              Container(
                height: 160,
                decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(16)),
                child: Center(child: Icon(widget.article['icon'] as IconData, size: 64, color: color)),
              ),
              const SizedBox(height: 16),
              Text(widget.article['title'] as String, style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(widget.article['category'] as String,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                ),
                const SizedBox(width: 10),
                Text(widget.article['readTime'] as String, style: AppTextStyles.bodySmall),
                const SizedBox(width: 10),
                const Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textHint),
                const SizedBox(width: 3),
                Text(widget.article['views'] as String? ?? '', style: AppTextStyles.caption),
              ]),
              const SizedBox(height: 20),
              if (_loading) ...[
                ...List.generate(4, (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(width: double.infinity, height: 16, radius: 8))),
              ] else
                Text(
                  _content ?? 'Content unavailable. Please try again.',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary, height: 1.7),
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFBC02D).withValues(alpha:0.4)),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFF57F17)),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'This article is for educational purposes only. Always consult a qualified healthcare professional for medical advice.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFFE65100), height: 1.5),
                  )),
                ]),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ]),
      ),
    );
  }
}

