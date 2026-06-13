import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../search/search_service.dart';
import '../../../core/widgets/ux_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Global Search Screen
// ─────────────────────────────────────────────────────────────────────────────

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  // State
  String _query = '';
  List<String> _history = [];
  List<Map<String, dynamic>> _firestoreDoctors = [];
  List<SearchResult> _staticResults = [];
  bool _isLoadingFirestore = false;
  String _activeFilter = 'All';

  // Animation
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── History ────────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = prefs.getStringList('mednu_search_history') ?? [];
    });
  }

  Future<void> _saveToHistory(String q) async {
    if (q.trim().length < 2) return;
    final clean = q.trim();
    setState(() {
      _history.remove(clean);
      _history.insert(0, clean);
      if (_history.length > 8) _history = _history.sublist(0, 8);
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('mednu_search_history', _history);
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('mednu_search_history');
  }

  // ── Search Logic ───────────────────────────────────────────────────────────

  void _onChanged(String value) {
    final q = value.trim();
    setState(() {
      _query = q;
      _activeFilter = 'All';
    });

    if (q.length < 2) {
      _debounce?.cancel();
      setState(() {
        _staticResults = [];
        _firestoreDoctors = [];
        _isLoadingFirestore = false;
      });
      return;
    }

    setState(() {
      _staticResults = SearchService.searchStatic(q);
    });

    // Debounced Firestore search
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchFirestoreDoctors(q);
    });
  }

  Future<void> _fetchFirestoreDoctors(String q) async {
    if (!mounted) return;
    setState(() => _isLoadingFirestore = true);
    final results = await SearchService.searchFirestoreDoctors(q);
    if (!mounted) return;
    setState(() {
      _firestoreDoctors = results;
      _isLoadingFirestore = false;
    });
  }

  void _applyQuery(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: q.length));
    _onChanged(q);
  }

  // ── Available filter tabs ──────────────────────────────────────────────────

  List<String> get _availableFilters {
    final filters = <String>['All'];
    if (_firestoreDoctors.isNotEmpty) filters.add('Doctors');
    final hasSpec = _staticResults.any((r) => r.category == SearchCategory.speciality);
    final hasSvc = _staticResults.any((r) =>
        r.category == SearchCategory.service ||
        r.category == SearchCategory.hospital ||
        r.category == SearchCategory.medicine);
    final hasLab = _staticResults.any((r) => r.category == SearchCategory.labTest);
    if (hasSpec) filters.add('Specialities');
    if (hasSvc) filters.add('Services');
    if (hasLab) filters.add('Lab Tests');
    return filters;
  }

  bool get _hasAnyResults =>
      _firestoreDoctors.isNotEmpty || _staticResults.isNotEmpty || _isLoadingFirestore;

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigateResult(BuildContext ctx, SearchResult item) {
    _saveToHistory(_query);
    if (item.extra != null) {
      final specialty = item.extra!['specialty'] as String? ?? '';
      ctx.push(
          '${AppRoutes.doctors}?specialty=${Uri.encodeComponent(specialty)}&mode=filter');
    } else {
      ctx.push(item.route);
    }
  }

  void _navigateDoctor(BuildContext ctx, Map<String, dynamic> doc) {
    _saveToHistory(_query);
    final id = doc['id'] as String? ?? '';
    ctx.push('/doctors/$id');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBase : AppColors.background,
        appBar: _buildAppBar(isDark),
        body: _query.isEmpty
            ? _buildEmptyState(isDark)
            : _hasAnyResults
                ? _buildResults(isDark)
                : _buildNoResults(isDark),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.surface,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyLarge.copyWith(
          color: isDark ? Colors.white : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        onChanged: _onChanged,
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) _saveToHistory(v.trim());
        },
        decoration: InputDecoration(
          hintText: 'Doctors, hospitals, lab tests...',
          border: InputBorder.none,
          hintStyle: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.textHint,
            fontWeight: FontWeight.w400,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.cancel_rounded, size: 18),
                  color: AppColors.textHint,
                  onPressed: () {
                    _ctrl.clear();
                    _onChanged('');
                  },
                )
              : null,
        ),
      ),
      bottom: _query.isNotEmpty && _isLoadingFirestore
          ? PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches
          if (_history.isNotEmpty) ...[
            _EmptySectionHeader(
              label: 'Recent Searches',
              icon: Icons.history_rounded,
              isDark: isDark,
              trailing: TextButton(
                onPressed: _clearHistory,
                child: Text(
                  'Clear',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history
                  .map((h) => _HistoryChip(
                        label: h,
                        isDark: isDark,
                        onTap: () => _applyQuery(h),
                        onDelete: () async {
                          setState(() => _history.remove(h));
                          final prefs =
                              await SharedPreferences.getInstance();
                          prefs.setStringList(
                              'mednu_search_history', _history);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 28),
          ],

          // Trending searches
          _EmptySectionHeader(
            label: 'Trending',
            icon: Icons.trending_up_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SearchService.popularSearches
                .map((t) => _TrendingChip(
                      label: t,
                      isDark: isDark,
                      onTap: () => _applyQuery(t),
                    ))
                .toList(),
          ),
          const SizedBox(height: 28),

          // Quick access grid
          _EmptySectionHeader(
            label: 'Quick Access',
            icon: Icons.grid_view_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: _quickItems
                .map((item) => _QuickAccessTile(
                      item: item,
                      isDark: isDark,
                      onTap: () => _navigateResult(context, item),
                    ))
                .toList(),
          ),
          const SizedBox(height: 28),

          // Browse all
          _EmptySectionHeader(
            label: 'Browse Services',
            icon: Icons.apps_rounded,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _browseItems
                .map((item) => _BrowseChip(
                      item: item,
                      isDark: isDark,
                      onTap: () => _navigateResult(context, item),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  static const _quickItems = [
    SearchResult(
      id: '_q_video',
      title: 'Video Consult',
      subtitle: '',
      route: AppRoutes.consultation,
      icon: Icons.video_call_rounded,
      color: Color(0xFF7B1FA2),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_q_doctors',
      title: 'Find Doctors',
      subtitle: '',
      route: AppRoutes.doctors,
      icon: Icons.medical_services_rounded,
      color: Color(0xFFC2185B),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_q_lab',
      title: 'Lab Tests',
      subtitle: '',
      route: AppRoutes.diagnostics,
      icon: Icons.science_rounded,
      color: Color(0xFF0097A7),
      category: SearchCategory.labTest,
      keywords: [],
    ),
    SearchResult(
      id: '_q_emergency',
      title: 'Emergency',
      subtitle: '',
      route: AppRoutes.emergency,
      icon: Icons.emergency_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.service,
      keywords: [],
    ),
  ];

  static const _browseItems = [
    SearchResult(
      id: '_b_ambulance',
      title: 'Ambulance',
      subtitle: '',
      route: AppRoutes.ambulance,
      icon: Icons.emergency_share_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_b_hospitals',
      title: 'Hospitals',
      subtitle: '',
      route: AppRoutes.hospitals,
      icon: Icons.local_hospital_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.hospital,
      keywords: [],
    ),
    SearchResult(
      id: '_b_physio',
      title: 'Physiotherapy',
      subtitle: '',
      route: AppRoutes.physio,
      icon: Icons.sports_gymnastics_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_b_caregivers',
      title: 'Caregivers',
      subtitle: '',
      route: AppRoutes.caregivers,
      icon: Icons.elderly_rounded,
      color: Color(0xFFEC407A),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_b_medicines',
      title: 'Medicines',
      subtitle: '',
      route: AppRoutes.medicine,
      icon: Icons.medication_rounded,
      color: Color(0xFF2E7D32),
      category: SearchCategory.medicine,
      keywords: [],
    ),
    SearchResult(
      id: '_b_pregnancy',
      title: 'Pregnancy',
      subtitle: '',
      route: AppRoutes.pregnancy,
      icon: Icons.pregnant_woman_rounded,
      color: Color(0xFFC2185B),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_b_equipment',
      title: 'Equipment',
      subtitle: '',
      route: AppRoutes.equipment,
      icon: Icons.medical_information_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.service,
      keywords: [],
    ),
    SearchResult(
      id: '_b_nutrition',
      title: 'Nutrition',
      subtitle: '',
      route: AppRoutes.nutrition,
      icon: Icons.restaurant_menu_rounded,
      color: Color(0xFF558B2F),
      category: SearchCategory.service,
      keywords: [],
    ),
  ];

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults(bool isDark) {
    final filters = _availableFilters;
    return Column(
      children: [
        // Filter chips row
        if (filters.length > 2)
          _FilterRow(
            filters: filters,
            activeFilter: _activeFilter,
            isDark: isDark,
            onSelected: (f) => setState(() => _activeFilter = f),
          ),

        // Results list
        Expanded(
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ── Doctors ──
              if (_firestoreDoctors.isNotEmpty &&
                  (_activeFilter == 'All' || _activeFilter == 'Doctors')) ...[
                _SectionHeader(
                  label: 'DOCTORS',
                  icon: Icons.person_rounded,
                  color: AppColors.primary,
                  isDark: isDark,
                  count: _firestoreDoctors.length,
                  onSeeAll: () => context.push(
                      '/doctors?specialty=${Uri.encodeComponent(_query)}&mode=filter'),
                ),
                ..._firestoreDoctors
                    .take(5)
                    .map((d) => _DoctorCard(
                          doc: d,
                          isDark: isDark,
                          onTap: () => _navigateDoctor(context, d),
                        )),
              ],

              // ── Specialities ──
              if (_staticResults.any(
                      (r) => r.category == SearchCategory.speciality) &&
                  (_activeFilter == 'All' ||
                      _activeFilter == 'Specialities')) ...[
                _SectionHeader(
                  label: 'SPECIALITIES',
                  icon: Icons.category_rounded,
                  color: const Color(0xFF7B1FA2),
                  isDark: isDark,
                ),
                ..._staticResults
                    .where((r) => r.category == SearchCategory.speciality)
                    .take(6)
                    .map((r) => _ResultTile(
                          item: r,
                          isDark: isDark,
                          onTap: () => _navigateResult(context, r),
                        )),
              ],

              // ── Services ──
              if (_staticResults.any((r) =>
                      r.category == SearchCategory.service ||
                      r.category == SearchCategory.hospital ||
                      r.category == SearchCategory.medicine) &&
                  (_activeFilter == 'All' ||
                      _activeFilter == 'Services')) ...[
                _SectionHeader(
                  label: 'SERVICES',
                  icon: Icons.apps_rounded,
                  color: const Color(0xFF0097A7),
                  isDark: isDark,
                ),
                ..._staticResults
                    .where((r) =>
                        r.category == SearchCategory.service ||
                        r.category == SearchCategory.hospital ||
                        r.category == SearchCategory.medicine)
                    .take(6)
                    .map((r) => _ResultTile(
                          item: r,
                          isDark: isDark,
                          onTap: () => _navigateResult(context, r),
                        )),
              ],

              // ── Lab Tests ──
              if (_staticResults
                      .any((r) => r.category == SearchCategory.labTest) &&
                  (_activeFilter == 'All' ||
                      _activeFilter == 'Lab Tests')) ...[
                _SectionHeader(
                  label: 'LAB TESTS',
                  icon: Icons.science_rounded,
                  color: const Color(0xFF0097A7),
                  isDark: isDark,
                ),
                ..._staticResults
                    .where((r) => r.category == SearchCategory.labTest)
                    .take(6)
                    .map((r) => _LabTestTile(
                          item: r,
                          isDark: isDark,
                          onTap: () => _navigateResult(context, r),
                        )),
              ],

              if (_isLoadingFirestore && _firestoreDoctors.isEmpty)
                ...List.generate(4, (_) => const SkeletonListTile()),
            ],
          ),
        ),
      ],
    );
  }

  // ── No Results ────────────────────────────────────────────────────────────

  Widget _buildNoResults(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCard
                  : AppColors.primary.withValues(alpha:0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded,
                size: 36,
                color: isDark ? AppColors.primaryBright : AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'No results for "$_query"',
            style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different spelling or browse\nour services below.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Text(
            'POPULAR SEARCHES',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textHint,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: SearchService.popularSearches
                .map((t) => _TrendingChip(
                      label: t,
                      isDark: isDark,
                      onTap: () => _applyQuery(t),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.doctors),
              icon: const Icon(Icons.person_search_rounded, size: 18),
              label: const Text('Browse All Doctors'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Section Header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final int? count;
  final VoidCallback? onSeeAll;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    this.count,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha:isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: color,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Filter Row
// =============================================================================

class _FilterRow extends StatelessWidget {
  final List<String> filters;
  final String activeFilter;
  final bool isDark;
  final ValueChanged<String> onSelected;

  const _FilterRow({
    required this.filters,
    required this.activeFilter,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final active = f == activeFilter;
          return GestureDetector(
            onTap: () => onSelected(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : isDark
                        ? AppColors.darkCard
                        : AppColors.primary.withValues(alpha:0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                f,
                style: AppTextStyles.labelSmall.copyWith(
                  color: active
                      ? Colors.white
                      : isDark
                          ? Colors.white70
                          : AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Doctor Card
// =============================================================================

class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final bool isDark;
  final VoidCallback onTap;

  const _DoctorCard(
      {required this.doc, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = doc['name'] as String? ?? 'Doctor';
    final spec = doc['specialty'] as String? ?? doc['speciality'] as String? ?? '';
    final qual = doc['qualifications'] as String? ?? '';
    final isOnline = doc['isOnline'] as bool? ?? false;
    final rating = (doc['rating'] as num?)?.toDouble() ?? 0.0;
    final fee = doc['fee'] as int?;
    final exp = doc['experience'] as int?;
    final initial = name.isNotEmpty ? name[0] : 'D';

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.border.withValues(alpha:0.5),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _OnlineBadge(isOnline: isOnline),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    qual.isNotEmpty ? '$spec · $qual' : spec,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (rating > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 12, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          rating.toStringAsFixed(1),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isDark ? Colors.white70 : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (exp != null) ...[
                        Text(
                          '$exp yrs exp',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (fee != null)
                        Text(
                          '₹$fee',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? Colors.white30 : AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  final bool isOnline;
  const _OnlineBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isOnline
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOnline ? 'Online' : 'Offline',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color:
              isOnline ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
        ),
      ),
    );
  }
}

// =============================================================================
// Result Tile (Services & Specialities)
// =============================================================================

class _ResultTile extends StatelessWidget {
  final SearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  const _ResultTile(
      {required this.item, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: item.color.withValues(alpha:isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(item.icon, size: 20, color: item.color),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              style: AppTextStyles.labelLarge.copyWith(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (item.badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.badge!,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: item.color,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: item.subtitle.isNotEmpty
          ? Text(
              item.subtitle,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            )
          : null,
      trailing: Icon(Icons.chevron_right_rounded,
          size: 16,
          color: isDark ? Colors.white24 : AppColors.textHint),
      onTap: onTap,
    );
  }
}

// =============================================================================
// Lab Test Tile
// =============================================================================

class _LabTestTile extends StatelessWidget {
  final SearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  const _LabTestTile(
      {required this.item, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha:isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, size: 20, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0097A7).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Book',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0097A7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty State Widgets
// =============================================================================

class _EmptySectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Widget? trailing;

  const _EmptySectionHeader({
    required this.label,
    required this.icon,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 15,
            color: isDark ? Colors.white54 : AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isDark ? Colors.white70 : AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryChip({
    required this.label,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.border.withValues(alpha:0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                size: 13,
                color: isDark ? Colors.white38 : AppColors.textHint),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? Colors.white70 : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close_rounded,
                  size: 12,
                  color: isDark ? Colors.white30 : AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendingChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _TrendingChip(
      {required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.primary.withValues(alpha:0.15)
              : AppColors.primary.withValues(alpha:0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.primaryBright : AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  final SearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickAccessTile(
      {required this.item, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.border.withValues(alpha:0.5),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha:isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 17, color: item.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: AppTextStyles.labelSmall.copyWith(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                  letterSpacing: 0,
                  fontSize: 11.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseChip extends StatelessWidget {
  final SearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  const _BrowseChip(
      {required this.item, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.border.withValues(alpha:0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 13, color: item.color),
            const SizedBox(width: 5),
            Text(
              item.title,
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? Colors.white70 : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
