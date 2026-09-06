import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../../core/widgets/add_to_cart_button.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../../../cart/providers/cart_provider.dart';

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

  Future<void> _addToCart(Map<String, dynamic> test) async {
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
    if (mounted) FeedbackService.showSuccess(context, '${test['name']} added to cart');
  }

  @override
  Widget build(BuildContext context) {
    final labName = _lab?['name'] as String? ?? 'Lab';
    final address = _lab?['address'] as String? ?? '';
    final rating = ((_lab?['rating'] as num?) ?? 0).toDouble();
    final totalReviews = (_lab?['totalReviews'] as int?) ?? 0;

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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.appBorder),
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
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('₹${t['price']}', style: AppTextStyles.labelLarge.copyWith(color: _themeColor)),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => _addToCart(t),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF0097A7), Color(0xFF26C6DA)]),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Add to Cart', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                          ]),
                        ]),
                      );
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
