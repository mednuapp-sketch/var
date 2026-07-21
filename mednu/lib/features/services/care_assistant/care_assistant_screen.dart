import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/providers/cart_provider.dart';

// ─────────────────────────────────────────────────────────────
//  Filter state
// ─────────────────────────────────────────────────────────────
class _AssistantFilterState {
  final String gender;   // 'Any' | 'Male' | 'Female'
  final String duration; // key from _durationOptions

  const _AssistantFilterState({this.gender = 'Any', this.duration = 'hourly'});

  bool get hasActiveFilters => gender != 'Any';

  _AssistantFilterState copyWith({String? gender, String? duration}) =>
      _AssistantFilterState(
        gender: gender ?? this.gender,
        duration: duration ?? this.duration,
      );
}

class CareAssistantScreen extends ConsumerStatefulWidget {
  const CareAssistantScreen({super.key});

  @override
  ConsumerState<CareAssistantScreen> createState() => _CareAssistantScreenState();
}

class _CareAssistantScreenState extends ConsumerState<CareAssistantScreen> {
  static const _themeColor = Color(0xFFE65100);

  // Duration tiers offered by every assistant; each maps to a rate field on
  // the Firestore doc. Selecting one drives both the displayed price and the
  // amount added to cart — there is no separate booking-time picker.
  static const _durationOptions = [
    {'key': 'hourly',   'label': 'Hourly',    'rateField': 'rateHourly',   'unit': '/hr'},
    {'key': 'halfDay',  'label': 'Half-day',  'rateField': 'rateHalfDay',  'unit': '/half-day'},
    {'key': 'fullDay',  'label': 'Full-day',  'rateField': 'rateFullDay',  'unit': '/day'},
    {'key': 'multiDay', 'label': 'Multi-day', 'rateField': 'rateMultiDay', 'unit': '/day (multi-day)'},
  ];

  Map<String, dynamic> _durationOption(String key) =>
      _durationOptions.firstWhere((d) => d['key'] == key);

  String _query = '';
  _AssistantFilterState _filters = const _AssistantFilterState();

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssistantFilterSheet(
        initial: _filters,
        durationOptions: _durationOptions,
        onApply: (f) => setState(() => _filters = f),
      ),
    );
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> raw, String id) {
    return {
      'id':           id,
      'name':         raw['name'] as String? ?? 'Care Assistant',
      'gender':       raw['gender'] as String? ?? '',
      'location':     raw['location'] as String? ?? '',
      'specialty':    raw['specialty'] as String? ?? 'Home & Hospital Assistance',
      'experience':   raw['experience'] as String? ?? '',
      'bio':          raw['bio'] as String? ?? '',
      'rating':       (raw['rating'] as num?)?.toDouble() ?? 0.0,
      'isVerified':   raw['isVerified'] as bool? ?? false,
      'rateHourly':   (raw['rateHourly'] as num?)?.toInt() ?? 0,
      'rateHalfDay':  (raw['rateHalfDay'] as num?)?.toInt() ?? 0,
      'rateFullDay':  (raw['rateFullDay'] as num?)?.toInt() ?? 0,
      'rateMultiDay': (raw['rateMultiDay'] as num?)?.toInt() ?? 0,
    };
  }

  int _amountFor(Map<String, dynamic> a, String durationKey) =>
      a[_durationOption(durationKey)['rateField'] as String] as int? ?? 0;

  Future<void> _book(Map<String, dynamic> a) async {
    final durationOpt = _durationOption(_filters.duration);
    final amount = _amountFor(a, _filters.duration);
    ref.read(cartProvider.notifier).addItem(
          type: 'care_assistant',
          serviceName: '${a['name']} – ${a['specialty']}',
          themeColor: _themeColor,
          unitAmount: amount,
          serviceDetails: {
            'assistantId':   a['id'],
            'assistantName': a['name'],
            'gender':        a['gender'],
            'location':      a['location'],
            'specialty':     a['specialty'],
            'duration':      durationOpt['key'],
            'durationLabel': durationOpt['label'],
            'rate':          amount,
            'rating':        a['rating'],
            'isVerified':    a['isVerified'],
          },
        );
    if (mounted) {
      FeedbackService.showSuccess(context, '${a['name']} added to cart');
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    return list.where((a) {
      if (_filters.gender != 'Any' && (a['gender'] as String) != _filters.gender) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return (a['name'] as String).toLowerCase().contains(q) ||
               (a['specialty'] as String).toLowerCase().contains(q) ||
               (a['location'] as String).toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('care_assistants')
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snap) {
          List<Map<String, dynamic>> assistants;

          if (snap.hasError) {
            assistants = [];
          } else if (!snap.hasData) {
            assistants = [];
          } else {
            assistants = snap.data!.docs
                .map((d) => _normalize(Map<String, dynamic>.from(d.data() as Map), d.id))
                .toList();
          }

          final filtered = _applyFilters(assistants);
          final durationOpt = _durationOption(_filters.duration);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: AppSpacing.headerHeight(context),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  IconButton(
                    icon: Stack(children: [
                      const Icon(Icons.tune_rounded, color: Colors.white),
                      if (_filters.hasActiveFilters)
                        Positioned(
                          top: 0, right: 0,
                          child: Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                                color: Colors.amber, shape: BoxShape.circle),
                          ),
                        ),
                    ]),
                    onPressed: _openFilterSheet,
                  ),
                  const CartBadgeAction(),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE65100), Color(0xFFFFA726)],
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
                                    Icon(Icons.support_agent_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                    SizedBox(height: AppSpacing.headerIconGap(context)),
                                    Text('Care Assistant', style: AppTextStyles.onPrimaryH2),
                                    Text('Book a trusted person to help your loved ones', style: AppTextStyles.onPrimaryBody),
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
                    Container(
                      padding: EdgeInsets.all(R.p(context, 16)),
                      decoration: BoxDecoration(
                        color: _themeColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(R.r(context, 16)),
                        border: Border.all(color: _themeColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('What is Care Assistant?',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: _themeColor)),
                        const SizedBox(height: 8),
                        Text(
                          'Book a verified person who will physically accompany your family member to hospital, collect reports, pick up medicines, or any other healthcare task — when you can\'t be there yourself.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextSecondary, height: 1.6),
                        ),
                      ]),
                    ),
                    SizedBox(height: AppSpacing.sectionGap(context)),

                    // Search bar
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name, specialty, city...',
                        prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded, size: 18, color: context.appTextHint),
                                onPressed: () => setState(() => _query = ''))
                            : null,
                        filled: true,
                        fillColor: context.appSurface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.r(context, 14)), borderSide: BorderSide.none),
                      ),
                    ),
                    SizedBox(height: R.h(context, 10)),

                    // Duration selector — drives displayed price on every card below.
                    Text('Duration', style: AppTextStyles.labelLarge),
                    SizedBox(height: R.h(context, 8)),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _durationOptions.map((d) => _Chip(
                        label: d['label'] as String,
                        selected: _filters.duration == d['key'],
                        onTap: () => setState(() => _filters = _filters.copyWith(duration: d['key'] as String)),
                      )).toList(),
                    ),

                    // Active filter summary
                    if (_filters.hasActiveFilters) ...[
                      SizedBox(height: R.h(context, 10)),
                      Row(children: [
                        Icon(Icons.filter_list_rounded, size: 14, color: context.appTextHint),
                        const SizedBox(width: 4),
                        Text('Gender filter active', style: AppTextStyles.labelSmall.copyWith(color: context.appTextHint)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() {
                            _filters = _filters.copyWith(gender: 'Any');
                          }),
                          child: Text('Clear',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: _themeColor,
                                  decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ],

                    SizedBox(height: AppSpacing.sectionGap(context)),

                    // Content
                    if (!snap.hasData && !snap.hasError)
                      _buildSkeleton()
                    else if (snap.hasError)
                      _buildError()
                    else if (assistants.isEmpty)
                      _buildEmpty()
                    else if (filtered.isEmpty)
                      AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matches found',
                        message: 'Try adjusting your search or filters.',
                        actionLabel: 'Clear Filters',
                        onAction: () => setState(() {
                          _query = '';
                          _filters = const _AssistantFilterState();
                        }),
                      )
                    else
                      ...filtered.map((a) {
                        final rating = a['rating'] as double;
                        final isVerified = a['isVerified'] as bool;
                        final amount = _amountFor(a, _filters.duration);
                        return Container(
                          margin: EdgeInsets.only(bottom: R.h(context, 12)),
                          padding: EdgeInsets.all(R.p(context, 16)),
                          decoration: BoxDecoration(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(R.r(context, 18)),
                            border: Border.all(
                              color: isVerified
                                  ? const Color(0xFF2E7D32).withValues(alpha: 0.35)
                                  : context.appBorder,
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Stack(children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                      color: _themeColor.withValues(alpha: 0.15),
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.support_agent_rounded, size: 30, color: _themeColor),
                                ),
                                if (isVerified)
                                  Positioned(
                                    right: 0, bottom: 0,
                                    child: Container(
                                      width: 18, height: 18,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2E7D32),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                                    ),
                                  ),
                              ]),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(a['name'] as String, style: AppTextStyles.labelLarge)),
                                  if (isVerified)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.verified_rounded, size: 11, color: Color(0xFF2E7D32)),
                                        SizedBox(width: 3),
                                        Text('Police Verified', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                                      ]),
                                    ),
                                ]),
                                const SizedBox(height: 2),
                                Text(a['specialty'] as String, style: AppTextStyles.bodySmall),
                                if ((a['location'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.location_on_outlined, size: 13, color: context.appTextHint),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(a['location'] as String,
                                          style: AppTextStyles.labelSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ]),
                                ],
                              ])),
                              const SizedBox(width: 8),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('₹$amount${durationOpt['unit']}',
                                    style: AppTextStyles.labelLarge.copyWith(color: _themeColor)),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _book(a),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(color: _themeColor, borderRadius: BorderRadius.circular(10)),
                                    child: const Text('Add to Cart',
                                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ),
                              ]),
                            ]),
                            const SizedBox(height: 10),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              if ((a['gender'] as String).isNotEmpty)
                                _Badge(label: a['gender'] as String, color: const Color(0xFF6A1B9A)),
                              if ((a['experience'] as String).isNotEmpty)
                                _Badge(label: '${a['experience']} exp', color: const Color(0xFF0097A7)),
                              if (rating > 0)
                                _Badge(label: '⭐ ${rating.toStringAsFixed(1)}', color: Colors.amber.shade700),
                            ]),
                          ]),
                        );
                      }),
                    SizedBox(height: R.h(context, 40)),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return AppShimmer(
      child: Column(children: List.generate(4, (_) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 130,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      ))),
    );
  }

  Widget _buildError() => AppErrorState(message: 'Could not load care assistants. Please try again.');

  Widget _buildEmpty() => const AppEmptyState(
    icon: Icons.support_agent_outlined,
    title: 'No Care Assistants Available',
    message: 'Care assistants will appear here once added.',
    iconColor: _themeColor,
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color)),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE65100) : context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xFFE65100) : context.appBorder,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : context.appTextSecondary)),
    ),
  );
}

class _AssistantFilterSheet extends StatefulWidget {
  final _AssistantFilterState initial;
  final List<Map<String, Object>> durationOptions;
  final ValueChanged<_AssistantFilterState> onApply;
  const _AssistantFilterSheet({
    required this.initial,
    required this.durationOptions,
    required this.onApply,
  });

  @override
  State<_AssistantFilterSheet> createState() => _AssistantFilterSheetState();
}

class _AssistantFilterSheetState extends State<_AssistantFilterSheet> {
  late _AssistantFilterState _state;

  static const _genderOptions = ['Any', 'Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: context.appBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Text('Filter Care Assistants', style: AppTextStyles.h3),
            const Spacer(),
            TextButton(
              onPressed: () => setState(
                  () => _state = const _AssistantFilterState()),
              child: const Text('Reset All'),
            ),
          ]),
          const SizedBox(height: 16),

          // Gender
          Text('Gender', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _genderOptions.map((g) => _Chip(
              label: g,
              selected: _state.gender == g,
              onTap: () => setState(() => _state = _state.copyWith(gender: g)),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Duration
          Text('Duration', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: widget.durationOptions.map((d) => _Chip(
              label: d['label'] as String,
              selected: _state.duration == d['key'],
              onTap: () => setState(() => _state = _state.copyWith(duration: d['key'] as String)),
            )).toList(),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_state);
                Navigator.pop(context);
              },
              child: const Text('Apply Filters'),
            ),
          ),
        ]),
      ),
    );
  }
}
