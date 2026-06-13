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
  final _aiService = AiTipsService();
  String? _aiTip;
  bool _tipLoading = false;

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

  List<Map<String, dynamic>> get _filtered => _selectedCategory == 'All'
      ? _articles
      : _articles.where((a) => a['category'] == _selectedCategory).toList();

  @override
  void initState() {
    super.initState();
    // Show static fallback instantly, then replace with AI response
    _aiTip = AiTipsService.fallbackFor(_selectedCategory);
    _fetchTip();
  }

  Future<void> _fetchTip() async {
    setState(() => _tipLoading = true);
    final tip = await _aiService.getDailyTip(_selectedCategory);
    if (mounted) setState(() { _aiTip = tip; _tipLoading = false; });
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
                    decoration: InputDecoration(
                      hintText: 'Search health topics...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // ── AI Health Tip Card ──────────────────────────
                _AiTipCard(
                  tip: _aiTip,
                  isLoading: _tipLoading,
                  category: _selectedCategory,
                  onRefresh: _fetchTip,
                  onAskAi: () => _showAskAiSheet(context),
                ),

                const SizedBox(height: 16),

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
                          _fetchTip();
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('${_filtered.length} Articles', style: AppTextStyles.h4),
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

  void _showAskAiSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AskAiSheet(aiService: _aiService),
    );
  }
}

// ── AI Health Tip Card ────────────────────────────────────
class _AiTipCard extends StatelessWidget {
  final String? tip;
  final bool isLoading;
  final String category;
  final VoidCallback onRefresh;
  final VoidCallback onAskAi;

  const _AiTipCard({
    required this.tip,
    required this.isLoading,
    required this.category,
    required this.onRefresh,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B1FA2).withValues(alpha:0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                SizedBox(width: 5),
                Text('AI Health Tip', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
            const Spacer(),
            if (category != 'All')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(category, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70)),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isLoading ? null : onRefresh,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.15), borderRadius: BorderRadius.circular(8)),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // Tip content
          if (isLoading)
            Column(children: [
              _shimmerLine(1.0),
              const SizedBox(height: 6),
              _shimmerLine(0.85),
              const SizedBox(height: 6),
              _shimmerLine(0.6),
            ])
          else
            Text(
              tip ?? 'Tap refresh to get a health tip.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white, height: 1.55),
            ),

          const SizedBox(height: 16),

          // Ask AI button
          GestureDetector(
            onTap: onAskAi,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.chat_rounded, color: Color(0xFF7B1FA2), size: 16),
                SizedBox(width: 7),
                Text('Ask AI a Health Question', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _shimmerLine(double widthFactor) {
    return LayoutBuilder(builder: (_, constraints) => Container(
      width: constraints.maxWidth * widthFactor,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.25),
        borderRadius: BorderRadius.circular(6),
      ),
    ));
  }
}

// ── Ask AI Bottom Sheet ───────────────────────────────────
class _AskAiSheet extends StatefulWidget {
  final AiTipsService aiService;
  const _AskAiSheet({required this.aiService});

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = false;

  final List<Map<String, String>> _messages = [];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final answer = await widget.aiService.askQuestion(question);
    if (mounted) {
      setState(() {
        _messages.add({'role': 'ai', 'text': answer});
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        // Handle
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 4), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Health Assistant', style: AppTextStyles.labelLarge),
              Text('Ask any health question', style: AppTextStyles.bodySmall),
            ]),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
            ),
          ]),
        ),
        const Divider(height: 1),

        // Chat area
        Expanded(
          child: _messages.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return _typingIndicator();
                    final msg = _messages[i];
                    return _ChatBubble(
                      text: msg['text']!,
                      isUser: msg['role'] == 'user',
                    );
                  },
                ),
        ),

        // Disclaimer
        Container(
          color: const Color(0xFFF3E5F5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF7B1FA2)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'For educational purposes only. Always consult a doctor.',
                style: AppTextStyles.caption.copyWith(color: const Color(0xFF7B1FA2)),
              ),
            ),
          ]),
        ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Ask a health question...',
                  hintStyle: AppTextStyles.bodySmall,
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), shape: BoxShape.circle),
          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 34),
        ),
        const SizedBox(height: 16),
        Text('Ask me anything about health!', style: AppTextStyles.labelLarge),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Try: "How much water should I drink daily?" or "Tips for better sleep"',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), shape: BoxShape.circle),
          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 16),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [
            _Dot(delay: 0),
            SizedBox(width: 4),
            _Dot(delay: 150),
            SizedBox(width: 4),
            _Dot(delay: 300),
          ]),
        ),
      ]),
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
    final title = widget.article['title'] as String;
    final cat = widget.article['category'] as String;
    final content = await widget.aiService.askQuestion(
      'Write a detailed, practical health article (about 250 words) on the topic: "$title". '
      'Category: $cat. Use simple language. Include 3–5 key tips formatted as bullet points. '
      'End with a reminder to consult a doctor for personalised advice. No markdown headers.',
    );
    if (mounted) setState(() { _content = content; _loading = false; });
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

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF7B1FA2) : const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(widget.delay / 600, 1.0, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF7B1FA2), shape: BoxShape.circle)),
    );
  }
}
