import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/lab_test_item.dart';
import '../providers/lab_providers.dart';
import '../services/lab_profile_service.dart';
import '../services/lab_test_inventory_service.dart';

/// A lab's own test catalogue — private data at `lab_profiles/{uid}/tests`,
/// never read directly by another lab or by patients (a Cloud Function
/// mirror publishes a copy of each test into the patient-facing
/// `lab_tests_catalogue` while this lab is `active` — see
/// `onLabTestInventoryWrite` in functions/index.js — but this subcollection
/// itself stays owner-only). A patient who books a test from this catalogue
/// has their booking routed straight to this lab, rather than into the
/// shared unclaimed queue.
class LabTestInventoryScreen extends ConsumerWidget {
  const LabTestInventoryScreen({super.key});

  Future<void> _showAddTestSheet(BuildContext context, String labId) async {
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final durationCtrl = TextEditingController();
    bool homeCollectionAvailable = false;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Test', style: AppTextStyles.h4),
                  const SizedBox(height: 16),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Test name')),
                  const SizedBox(height: 10),
                  TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category (optional)')),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Price'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: durationCtrl,
                          decoration: const InputDecoration(labelText: 'Report time (e.g. 24 hrs)'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Home sample collection', style: AppTextStyles.labelMedium),
                    value: homeCollectionAvailable,
                    onChanged: (v) => setSheetState(() => homeCollectionAvailable = v),
                    activeThumbColor: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'Add Test',
                    isLoading: saving,
                    onTap: saving
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final price = num.tryParse(priceCtrl.text.trim()) ?? 0;
                            if (name.isEmpty || saving) return;
                            setSheetState(() => saving = true);
                            try {
                              await LabTestInventoryService.addTest(
                                labId,
                                name: name,
                                category: categoryCtrl.text.trim(),
                                price: price,
                                duration: durationCtrl.text.trim(),
                                homeCollectionAvailable: homeCollectionAvailable,
                              );
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            } catch (_) {
                              if (sheetContext.mounted) {
                                setSheetState(() => saving = false);
                                FeedbackService.showError(sheetContext,
                                    'Could not add this test. Check your connection.');
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    categoryCtrl.dispose();
    priceCtrl.dispose();
    durationCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync = ref.watch(labTestInventoryProvider);
    final uid = LabProfileService.currentUid;

    return SharedAppShell(
      currentRoute: AppRoutes.labTestInventory,
      title: 'Test Catalogue',
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddTestSheet(context, uid),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
      body: testsAsync.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (tests) {
          if (tests.isEmpty) {
            return const AppEmptyState(
              icon: Icons.biotech_outlined,
              title: 'No tests yet',
              message: 'Add the tests you offer so patients can find and book them directly.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: tests.length,
            itemBuilder: (context, i) => Dismissible(
              key: ValueKey(tests[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              ),
              confirmDismiss: (_) => MedNuConfirmationDialog.show(
                context,
                title: 'Remove Test',
                message: 'Remove "${tests[i].name}" from your catalogue? This cannot be undone.',
                confirmLabel: 'Remove',
                destructive: true,
              ),
              onDismissed: (_) {
                if (uid != null) {
                  LabTestInventoryService.deleteTest(uid, tests[i].id);
                }
              },
              child: _TestTile(item: tests[i], labId: uid ?? ''),
            ),
          );
        },
      ),
    );
  }
}

class _TestTile extends StatelessWidget {
  final LabTestItem item;
  final String labId;
  const _TestTile({required this.item, required this.labId});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis),
                if (item.category.isNotEmpty)
                  Text(item.category, style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(CurrencyFormatter.format(item.price), style: AppTextStyles.bodyMedium),
                    if (item.duration.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('• Reports in ${item.duration}', style: AppTextStyles.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(
                label: item.isAvailable ? 'Available' : 'Hidden',
                color: item.isAvailable ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Switch(
                value: item.isAvailable,
                onChanged: labId.isEmpty
                    ? null
                    : (v) => LabTestInventoryService.setAvailable(labId, item.id, v),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
