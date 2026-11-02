import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../../core/widgets/add_to_cart_button.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../../../cart/providers/cart_provider.dart';

import '../../../../core/router/app_router.dart';
/// A single lab's test menu — the "food" screen in the hotel/lab-first
/// browsing flow. Reached from a lab card on [DiagnosticsScreen]; fetches the
/// lab's own profile by id (rather than trusting nav `extra`) so it also
/// works for deep links.
class LabMenuScreen extends ConsumerStatefulWidget {
  final String labId;
  const LabMenuScreen({super.key, required this.labId});

  @override
  ConsumerState<LabMenuScreen> createState() => _LabMenuScreenState();
}

class _LabMenuScreenState extends ConsumerState<LabMenuScreen> {
  static const _themeColor = Color(0xFF0097A7);

  String _query = '';
  Map<String, dynamic>? _lab;
  bool _labLoading = true;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('lab_profiles').doc(widget.labId).get().then((snap) {
      if (!mounted) return;
      setState(() {
        _lab = snap.data();
        _labLoading = false;
      });
    });
  }

  /// Tests the patient has ticked, keyed by test id. Kept across searches so
  /// several tests can be picked and added to the cart in one go.
  final Map<String, Map<String, dynamic>> _selected = {};

  void _toggle(Map<String, dynamic> test) {
    final id = test['id'] as String;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = test;
      }
    });
  }

  int get _selectedTotal =>
      _selected.values.fold(0, (total, t) => total +((t['price'] as num?)?.toInt() ?? 0));

  Future<void> _addSelectedToCart() async {
    final tests = _selected.values.toList();
    if (tests.isEmpty) return;
    final vendorKey = 'lab:${widget.labId}';
    final conflict = ref.read(cartProvider.notifier).conflictFor(type: 'diagnostics', vendorKey: vendorKey);
    if (conflict != null) {
      final labName = (_lab?['name'] as String?) ?? 'this lab';
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace items in cart?'),
          content: Text(
            'Your cart has diagnostics tests from ${conflict.existingVendorName}. '
            'Add tests from $labName instead?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (replace != true || !mounted) return;
      ref.read(cartProvider.notifier).clearType('diagnostics');
    }

    for (final test in tests) {
      ref.read(cartProvider.notifier).addItem(
            type: 'diagnostics',
            serviceName: test['name'] as String,
            themeColor: _themeColor,
            unitAmount: (test['price'] as num?)?.toInt() ?? 0,
            serviceDetails: {
              'testName': test['name'],
              'price': test['price'],
              'reportTime': test['duration'],
              'sourceLabId': widget.labId,
              'sourceTestId': test['id'],
              'labName': _lab?['name'],
            },
          );
    }
    if (!mounted) return;
    setState(_selected.clear);
    FeedbackService.showSuccess(
        context, tests.length == 1 ? '${tests.first['name']} added to cart' : '${tests.length} tests added to cart');
  }

  @override
  Widget build(BuildContext context) {
    final labName = _lab?['name'] as String? ?? 'Lab';
    final address = _lab?['address'] as String? ?? '';
    final rating = ((_lab?['rating'] as num?) ?? 0).toDouble();
    final totalReviews = (_lab?['totalReviews'] as int?) ?? 0;

    return Scaffold(
      backgroundColor: context.appBackground,
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _addSelectedToCart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Add ${_selected.length} test${_selected.length == 1 ? '' : 's'} to cart · ₹$_selectedTotal',
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.safeBack(),
            ),
            actions: const [CartBadgeAction()],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0097A7), Color(0xFF26C6DA)],
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
                                Icon(Icons.biotech_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                Text(_labLoading ? 'Loading…' : labName, style: AppTextStyles.onPrimaryH2),
                                if (!_labLoading) ...[
                                  if (address.isNotEmpty)
                                    Text(address, style: AppTextStyles.onPrimaryBody, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Row(children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      totalReviews > 0 ? '${rating.toStringAsFixed(1)} ($totalReviews)' : 'New',
                                      style: AppTextStyles.onPrimaryBody,
                                    ),
                                  ]),
                                ],
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
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search tests...',
                    prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: context.appTextHint),
                            onPressed: () => setState(() => _query = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: context.appSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('lab_tests_catalogue')
                    .where('sourceLabId', isEqualTo: widget.labId)
                    .where('isActive', isEqualTo: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return AppShimmer(
                      child: Column(children: List.generate(4, (_) => Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        height: 78,
                        decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16)),
                      ))),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  final tests = docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return {
                      'id': (data['sourceTestId'] as String?) ?? d.id,
                      'name': (data['name'] as String? ?? '').trim(),
                      'price': (data['price'] as num?)?.toInt() ?? 0,
                      'duration': (data['duration'] as String? ?? '').trim(),
                    };
                  }).where((t) =>
                      _query.isEmpty || (t['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();

                  if (tests.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.biotech_outlined,
                      title: 'No Tests Available',
                      message: 'This lab has not listed any tests yet.',
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: tests.map((t) {
                      final duration = t['duration'] as String;
                      final picked = _selected.containsKey(t['id']);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggle(t),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: picked ? _themeColor : context.appBorder,
                            width: picked ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(color: _themeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.biotech_rounded, color: _themeColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t['name'] as String, style: AppTextStyles.labelLarge),
                            if (duration.isNotEmpty)
                              Text('Reports in $duration', style: AppTextStyles.bodySmall),
                          ])),
                          Text('₹${t['price']}', style: AppTextStyles.labelLarge.copyWith(color: _themeColor)),
                          const SizedBox(width: 10),
                          Icon(
                            picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: picked ? _themeColor : context.appTextHint,
                            size: 26,
                          ),
                        ]),
                      ));
                    }).toList()),
                  );
                },
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}
