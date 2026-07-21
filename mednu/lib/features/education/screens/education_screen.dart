import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/r.dart';
import '../services/ai_tips_service.dart';

// ── Article data model ────────────────────────────────────────────────────────

class _Article {
  final String id;
  final String title;
  final String category;
  final String readTime;
  final String author;
  final IconData icon;
  final Color color;
  final String views;
  final String date;
  final bool isFeatured;
  final bool isBookmarked;

  const _Article({
    required this.id,
    required this.title,
    required this.category,
    required this.readTime,
    required this.author,
    required this.icon,
    required this.color,
    required this.views,
    required this.date,
    this.isFeatured = false,
    this.isBookmarked = false,
  });

  _Article copyWith({bool? isBookmarked}) => _Article(
        id: id,
        title: title,
        category: category,
        readTime: readTime,
        author: author,
        icon: icon,
        color: color,
        views: views,
        date: date,
        isFeatured: isFeatured,
        isBookmarked: isBookmarked ?? this.isBookmarked,
      );
}

// ── Category config ───────────────────────────────────────────────────────────

class _CategoryConfig {
  final String name;
  final IconData icon;
  final Color color;
  const _CategoryConfig({required this.name, required this.icon, required this.color});
}

// ── Education Screen ──────────────────────────────────────────────────────────

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  final _aiService = AiTipsService();

  static const _accentIndigo = Color(0xFF3F51B5);

  final List<_CategoryConfig> _categoryConfigs = const [
    _CategoryConfig(name: 'All', icon: Icons.apps_rounded, color: Color(0xFF3F51B5)),
    _CategoryConfig(name: 'Heart Health', icon: Icons.favorite_rounded, color: Color(0xFFC2185B)),
    _CategoryConfig(name: 'Diabetes', icon: Icons.bloodtype_rounded, color: Color(0xFFB71C1C)),
    _CategoryConfig(name: 'Pregnancy', icon: Icons.pregnant_woman_rounded, color: Color(0xFFE91E8C)),
    _CategoryConfig(name: 'Nutrition', icon: Icons.restaurant_rounded, color: Color(0xFF2E7D32)),
    _CategoryConfig(name: 'Mental Health', icon: Icons.psychology_rounded, color: Color(0xFF7B1FA2)),
    _CategoryConfig(name: 'Fitness', icon: Icons.fitness_center_rounded, color: Color(0xFF1565C0)),
  ];

  late List<_Article> _articles;

  @override
  void initState() {
    super.initState();
    _articles = _buildArticles();
    _simulateLoading();
  }

  List<_Article> _buildArticles() => [
        const _Article(
          id: 'a1',
          title: 'Complete Guide to Heart Health in 2025',
          category: 'Heart Health',
          readTime: '8 min read',
          author: 'Dr. Priya Mehta',
          icon: Icons.favorite_rounded,
          color: Color(0xFFC2185B),
          views: '32.1K',
          date: 'Jun 20',
          isFeatured: true,
        ),
        const _Article(
          id: 'a2',
          title: 'How to Manage Diabetes with Diet',
          category: 'Diabetes',
          readTime: '5 min read',
          author: 'Dr. Arjun Reddy',
          icon: Icons.bloodtype_rounded,
          color: Color(0xFFB71C1C),
          views: '12.4K',
          date: 'Jun 18',
        ),
        const _Article(
          id: 'a3',
          title: '10 Signs of Vitamin Deficiency',
          category: 'Nutrition',
          readTime: '4 min read',
          author: 'Dr. Sunita Rao',
          icon: Icons.restaurant_rounded,
          color: Color(0xFF2E7D32),
          views: '8.2K',
          date: 'Jun 15',
          isBookmarked: true,
        ),
        const _Article(
          id: 'a4',
          title: 'Managing Stress in Modern Life',
          category: 'Mental Health',
          readTime: '6 min read',
          author: 'Dr. Ananya Singh',
          icon: Icons.psychology_rounded,
          color: Color(0xFF7B1FA2),
          views: '15.1K',
          date: 'Jun 12',
        ),
        const _Article(
          id: 'a5',
          title: 'Pregnancy: What to Expect Week by Week',
          category: 'Pregnancy',
          readTime: '9 min read',
          author: 'Dr. Kavitha Nair',
          icon: Icons.pregnant_woman_rounded,
          color: Color(0xFFE91E8C),
          views: '20.3K',
          date: 'Jun 10',
          isBookmarked: true,
        ),
        const _Article(
          id: 'a6',
          title: 'Understanding Blood Pressure',
          category: 'Heart Health',
          readTime: '3 min read',
          author: 'Dr. Vikram Shah',
          icon: Icons.monitor_heart_rounded,
          color: Color(0xFFB71C1C),
          views: '11.2K',
          date: 'Jun 8',
        ),
        const _Article(
          id: 'a7',
          title: 'Benefits of Walking 30 Minutes Daily',
          category: 'Fitness',
          readTime: '3 min read',
          author: 'Dr. Ravi Kumar',
          icon: Icons.directions_walk_rounded,
          color: Color(0xFF1565C0),
          views: '18.9K',
          date: 'Jun 5',
        ),
        const _Article(
          id: 'a8',
          title: 'Best Foods for Mental Wellness',
          category: 'Mental Health',
          readTime: '5 min read',
          author: 'Dr. Ananya Singh',
          icon: Icons.spa_rounded,
          color: Color(0xFF7B1FA2),
          views: '9.7K',
          date: 'Jun 3',
        ),
        const _Article(
          id: 'a9',
          title: 'Diabetic-Friendly Meal Planning',
          category: 'Diabetes',
          readTime: '7 min read',
          author: 'Dr. Arjun Reddy',
          icon: Icons.restaurant_menu_rounded,
          color: Color(0xFFB71C1C),
          views: '14.5K',
          date: 'May 30',
          isBookmarked: true,
        ),
        const _Article(
          id: 'a10',
          title: 'Yoga for Beginners: A Complete Guide',
          category: 'Fitness',
          readTime: '6 min read',
          author: 'Dr. Ravi Kumar',
          icon: Icons.self_improvement_rounded,
          color: Color(0xFF1565C0),
          views: '22.0K',
          date: 'May 28',
        ),
      ];

  Future<void> _simulateLoading() async {
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) setState(() => _isLoading = false);
  }

  List<_Article> get _featured =>
      _articles.where((a) => a.isFeatured).toList();

  List<_Article> get _bookmarked =>
      _articles.where((a) => a.isBookmarked).toList();

  List<_Article> get _filtered {
    var list = _selectedCategory == 'All'
        ? _articles.where((a) => !a.isFeatured).toList()
        : _articles
            .where((a) => a.category == _selectedCategory && !a.isFeatured)
            .toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((a) =>
              a.title.toLowerCase().contains(q) ||
              a.category.toLowerCase().contains(q) ||
              a.author.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  void _toggleBookmark(String id) {
    setState(() {
      final idx = _articles.indexWhere((a) => a.id == id);
      if (idx != -1) {
        _articles[idx] =
            _articles[idx].copyWith(isBookmarked: !_articles[idx].isBookmarked);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
            backgroundColor: _accentIndigo,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_rounded, color: Colors.white70),
                onPressed: () {
                  // Scroll to bookmarks
                },
                tooltip: 'Saved Articles',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF3F51B5), Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20, right: -20,
                      child: Container(
                        width: R.w(context, 110), height: R.h(context, 110),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10, left: -30,
                      child: Container(
                        width: R.w(context, 80), height: R.h(context, 80),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: AppSpacing.headerPadding(context),
                                child: Row(
                                  children: [
                                    Container(
                                      width: R.w(context, 44), height: R.h(context, 44),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                                      ),
                                      child: Icon(Icons.menu_book_rounded,
                                          color: Colors.white, size: R.w(context, 24)),
                                    ),
                                    SizedBox(width: R.w(context, 12)),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Health Education',
                                            style: AppTextStyles.h2
                                                .copyWith(color: Colors.white)),
                                        Text('Learn about health & wellness',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(color: Colors.white70)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _isLoading
                ? _LoadingShimmer()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search bar
                      Padding(
                        padding: EdgeInsets.fromLTRB(R.p(context, 16),
                            R.p(context, 16), R.p(context, 16), 0),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.trim()),
                          decoration: InputDecoration(
                            hintText: 'Search health topics, doctors...',
                            hintStyle: AppTextStyles.bodySmall
                                .copyWith(color: context.appTextHint),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: context.appTextHint),
                            filled: true,
                            fillColor: context.appSurface,
                            contentPadding: EdgeInsets.symmetric(
                                vertical: R.p(context, 14)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 14)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 14)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 14)),
                              borderSide: BorderSide(
                                  color: _accentIndigo.withValues(alpha: 0.35),
                                  width: 1.5),
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded,
                                        color: context.appTextHint),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),

                      // Category chips
                      SizedBox(height: R.h(context, 14)),
                      SizedBox(
                        height: R.h(context, 40),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                              horizontal: R.p(context, 16)),
                          itemCount: _categoryConfigs.length,
                          itemBuilder: (_, i) {
                            final cfg = _categoryConfigs[i];
                            final sel = _selectedCategory == cfg.name;
                            return GestureDetector(
                              onTap: () => setState(
                                  () => _selectedCategory = cfg.name),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: EdgeInsets.only(right: R.p(context, 8)),
                                padding: EdgeInsets.symmetric(
                                    horizontal: R.p(context, 14), vertical: 0),
                                decoration: BoxDecoration(
                                  color: sel ? cfg.color : context.appSurface,
                                  borderRadius: BorderRadius.circular(R.r(context, 20)),
                                  border: Border.all(
                                    color: sel ? cfg.color : context.appBorder,
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                            color: cfg.color
                                                .withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(cfg.icon,
                                        size: 13,
                                        color: sel
                                            ? Colors.white
                                            : cfg.color),
                                    SizedBox(width: R.w(context, 5)),
                                    Text(
                                      cfg.name,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: sel
                                            ? Colors.white
                                            : context.appTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      SizedBox(height: R.h(context, 16)),

                      // Search empty state
                      if (_searchQuery.isNotEmpty && _filtered.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: R.p(context, 24)),
                          child: AppEmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No results',
                            message: 'No articles found for "$_searchQuery".',
                            iconColor: _accentIndigo,
                            actionLabel: 'Clear',
                            onAction: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        )
                      else ...[
                        // Featured hero card
                        if (_searchQuery.isEmpty &&
                            _selectedCategory == 'All') ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(R.p(context, 16), 0,
                                R.p(context, 16), R.p(context, 16)),
                            child: _FeaturedCard(
                              article: _featured.first,
                              onTap: () =>
                                  _openArticle(context, _featured.first),
                              onBookmark: () =>
                                  _toggleBookmark(_featured.first.id),
                            ),
                          ),
                        ],

                        // Articles section header
                        Padding(
                          padding: EdgeInsets.fromLTRB(R.p(context, 16), 0,
                              R.p(context, 16), R.p(context, 10)),
                          child: Row(
                            children: [
                              Text(
                                _selectedCategory == 'All'
                                    ? 'All Articles'
                                    : _selectedCategory,
                                style: AppTextStyles.h4,
                              ),
                              SizedBox(width: R.w(context, 8)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: R.p(context, 8),
                                    vertical: R.p(context, 2)),
                                decoration: BoxDecoration(
                                  color: _accentIndigo.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(R.r(context, 12)),
                                ),
                                child: Text(
                                  '${_filtered.length}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _accentIndigo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Articles list
                        if (_filtered.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: R.p(context, 8)),
                            child: AppEmptyState(
                              icon: Icons.article_outlined,
                              title: 'No Articles Found',
                              message: 'No articles in this category yet.',
                              iconColor: _accentIndigo,
                            ),
                          )
                        else
                          ..._filtered.asMap().entries.map((e) =>
                              FadeInSlide(
                                delay: Duration(milliseconds: e.key * 50),
                                child: _ArticleCard(
                                  article: e.value,
                                  onTap: () =>
                                      _openArticle(context, e.value),
                                  onBookmark: () =>
                                      _toggleBookmark(e.value.id),
                                ),
                              )),

                        // Bookmarked section
                        if (_searchQuery.isEmpty &&
                            _selectedCategory == 'All' &&
                            _bookmarked.isNotEmpty) ...[
                          SizedBox(height: R.h(context, 8)),
                          Padding(
                            padding: EdgeInsets.fromLTRB(R.p(context, 16),
                                R.p(context, 8), R.p(context, 16), R.p(context, 10)),
                            child: Row(
                              children: [
                                const Icon(Icons.bookmark_rounded,
                                    color: Color(0xFFF57F17), size: 18),
                                SizedBox(width: R.w(context, 8)),
                                Text('Saved Articles',
                                    style: AppTextStyles.h4),
                                SizedBox(width: R.w(context, 8)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: R.p(context, 8),
                                      vertical: R.p(context, 2)),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(R.r(context, 12)),
                                  ),
                                  child: Text(
                                    '${_bookmarked.length}',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF57F17),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._bookmarked.map((article) => _ArticleCard(
                                article: article,
                                onTap: () =>
                                    _openArticle(context, article),
                                onBookmark: () =>
                                    _toggleBookmark(article.id),
                              )),
                        ],

                        SizedBox(height: R.h(context, 48)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openArticle(BuildContext context, _Article article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ArticleSheet(article: article, aiService: _aiService),
    );
  }
}

// ── Loading Shimmer ───────────────────────────────────────────────────────────

class _LoadingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: EdgeInsets.all(R.p(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: double.infinity, height: 48, radius: 14),
            SizedBox(height: R.h(context, 16)),
            Row(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: EdgeInsets.only(right: R.p(context, 8)),
                  child: SkeletonBox(width: 80, height: 36, radius: 20),
                ),
              ),
            ),
            SizedBox(height: R.h(context, 16)),
            const SkeletonBox(width: double.infinity, height: 170, radius: 20),
            SizedBox(height: R.h(context, 16)),
            ...List.generate(
              3,
              (_) => Padding(
                padding: EdgeInsets.only(bottom: R.p(context, 12)),
                child: SkeletonBox(width: double.infinity, height: 88, radius: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Featured Card ─────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final _Article article;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  const _FeaturedCard({
    required this.article,
    required this.onTap,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              article.color,
              article.color.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(R.r(context, 22)),
          boxShadow: [
            BoxShadow(
              color: article.color.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background deco
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              right: 16, bottom: -10,
              child: Icon(article.icon,
                  size: 90, color: Colors.white.withValues(alpha: 0.08)),
            ),

            Padding(
              padding: EdgeInsets.all(R.p(context, 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(R.r(context, 8)),
                        ),
                        child: const Text(
                          'FEATURED',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onBookmark,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(R.r(context, 10)),
                          ),
                          child: Icon(
                            article.isBookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: R.h(context, 12)),

                  // Category chip
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: R.p(context, 8), vertical: R.p(context, 3)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(R.r(context, 6)),
                    ),
                    child: Text(
                      article.category.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  SizedBox(height: R.h(context, 8)),

                  Text(
                    article.title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: R.h(context, 6)),
                  Text(
                    'Discover the latest health trends and science-backed tips for a longer, healthier life.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: R.h(context, 14)),

                  Row(
                    children: [
                      // Author avatar placeholder
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded,
                            size: 14, color: Colors.white70),
                      ),
                      SizedBox(width: R.w(context, 6)),
                      Expanded(
                        child: Text(
                          article.author,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: Colors.white60),
                      SizedBox(width: R.w(context, 3)),
                      Text(article.readTime,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white60)),
                      SizedBox(width: R.w(context, 12)),
                      ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: article.color,
                          minimumSize: const Size(88, 32),
                          elevation: 0,
                          padding: EdgeInsets.symmetric(horizontal: R.p(context, 12)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 10))),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Read Now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Article Card ──────────────────────────────────────────────────────────────

class _ArticleCard extends StatelessWidget {
  final _Article article;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  const _ArticleCard({
    required this.article,
    required this.onTap,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 18)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail with colored box
            Container(
              width: 72, height: 88,
              decoration: BoxDecoration(
                color: article.color.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(article.icon, color: article.color, size: 30),
                  SizedBox(height: R.h(context, 4)),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: R.p(context, 4), vertical: R.p(context, 2)),
                    decoration: BoxDecoration(
                      color: article.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(R.r(context, 4)),
                    ),
                    child: Text(
                      article.category.split(' ').first,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: article.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(R.p(context, 12), R.p(context, 12),
                    R.p(context, 8), R.p(context, 12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: AppTextStyles.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: R.h(context, 5)),
                    // Author
                    Row(
                      children: [
                        Icon(Icons.person_rounded,
                            size: 11, color: context.appTextHint),
                        SizedBox(width: R.w(context, 3)),
                        Expanded(
                          child: Text(
                            article.author,
                            style: AppTextStyles.bodySmall.copyWith(
                                color: context.appTextSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.h(context, 6)),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 11, color: context.appTextHint),
                        SizedBox(width: R.w(context, 3)),
                        Text(article.readTime,
                            style: AppTextStyles.caption),
                        const Spacer(),
                        Text(article.date,
                            style: AppTextStyles.caption
                                .copyWith(color: context.appTextHint)),
                        SizedBox(width: R.w(context, 6)),
                        // Views
                        Icon(Icons.remove_red_eye_outlined,
                            size: 11, color: context.appTextHint),
                        SizedBox(width: R.w(context, 2)),
                        Text(article.views, style: AppTextStyles.caption.copyWith(color: context.appTextHint)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bookmark column
            Padding(
              padding: EdgeInsets.only(right: R.p(context, 12)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  GestureDetector(
                    onTap: onBookmark,
                    child: Icon(
                      article.isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20,
                      color: article.isBookmarked
                          ? const Color(0xFFF57F17)
                          : context.appTextHint,
                    ),
                  ),
                  SizedBox(height: R.h(context, 16)),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 13, color: context.appTextHint),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Article Detail Sheet ──────────────────────────────────────────────────────

class _ArticleSheet extends StatefulWidget {
  final _Article article;
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
      final content = await widget.aiService.askQuestion(
        'Write a detailed, practical health article (about 250 words) on the topic: '
        '"${widget.article.title}". Category: ${widget.article.category}. '
        'Use simple language. Include 3–5 key tips formatted as bullet points. '
        'End with a reminder to consult a doctor for personalised advice. No markdown headers.',
      );
      if (mounted) setState(() { _content = content; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _content = null; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.article.color;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: EdgeInsets.only(top: R.p(context, 12)),
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(R.r(context, 2)),
              ),
            ),
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 10),
                  R.p(context, 12), 0),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: R.p(context, 8), vertical: R.p(context, 3)),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(R.r(context, 6)),
                    ),
                    child: Text(widget.article.category,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                  SizedBox(width: R.w(context, 8)),
                  Icon(Icons.access_time_rounded,
                      size: 12, color: context.appTextHint),
                  SizedBox(width: R.w(context, 3)),
                  Text(widget.article.readTime,
                      style: AppTextStyles.bodySmall),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: context.appTextHint),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 4),
                    R.p(context, 20), R.p(context, 32)),
                children: [
                  // Hero area
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.15),
                          color.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(R.r(context, 18)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(widget.article.icon,
                            size: 72, color: color.withValues(alpha: 0.25)),
                        Icon(widget.article.icon, size: 52, color: color),
                      ],
                    ),
                  ),
                  SizedBox(height: R.h(context, 16)),
                  Text(widget.article.title, style: AppTextStyles.h3),
                  SizedBox(height: R.h(context, 8)),
                  Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person_rounded,
                            size: 14, color: color),
                      ),
                      SizedBox(width: R.w(context, 8)),
                      Text(widget.article.author,
                          style: AppTextStyles.bodySmall.copyWith(
                              color: context.appTextSecondary,
                              fontWeight: FontWeight.w500)),
                      SizedBox(width: R.w(context, 12)),
                      Icon(Icons.remove_red_eye_outlined,
                          size: 12, color: context.appTextHint),
                      SizedBox(width: R.w(context, 3)),
                      Text(widget.article.views,
                          style: AppTextStyles.caption),
                      SizedBox(width: R.w(context, 12)),
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: context.appTextHint),
                      SizedBox(width: R.w(context, 3)),
                      Text(widget.article.date,
                          style: AppTextStyles.caption),
                    ],
                  ),
                  SizedBox(height: R.h(context, 20)),
                  // Article content
                  if (_loading)
                    AppShimmer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(
                          6,
                          (i) => Padding(
                            padding: EdgeInsets.only(bottom: R.p(context, 10)),
                            child: SkeletonBox(
                                width: i == 5 ? 200 : double.infinity,
                                height: 14),
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      _content ?? 'Content unavailable. Please try again.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: context.appTextSecondary,
                        height: 1.75,
                      ),
                    ),
                  SizedBox(height: R.h(context, 20)),
                  // Disclaimer
                  Container(
                    padding: EdgeInsets.all(R.p(context, 14)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(R.r(context, 12)),
                      border: Border.all(
                          color: const Color(0xFFFBC02D)
                              .withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 16, color: Color(0xFFF57F17)),
                        SizedBox(width: R.w(context, 8)),
                        const Expanded(
                          child: Text(
                            'This article is for educational purposes only. Always consult a qualified healthcare professional for medical advice.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Color(0xFFE65100),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
