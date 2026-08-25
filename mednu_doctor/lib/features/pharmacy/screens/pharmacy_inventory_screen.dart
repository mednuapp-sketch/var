import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/inventory_item.dart';
import '../providers/pharmacy_providers.dart';
import '../services/pharmacy_inventory_service.dart';
import '../services/pharmacy_profile_service.dart';

/// A pharmacy's own stock — private data at
/// `pharmacy_profiles/{uid}/inventory`, never read by another pharmacy or
/// by patients. Low/out-of-stock items are surfaced with a status color so
/// restocking is a glance, not a search.
class PharmacyInventoryScreen extends ConsumerWidget {
  const PharmacyInventoryScreen({super.key});

  Future<void> _showAddItemSheet(BuildContext context, String pharmacyId) async {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    bool requiresPrescription = false;
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
            // Scrollable: five fields + the switch + the button overflow the
            // available height on short screens once the keyboard is up.
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Inventory Item', style: AppTextStyles.h4),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
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
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stock'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires prescription', style: AppTextStyles.labelMedium),
                  value: requiresPrescription,
                  onChanged: (v) => setSheetState(() => requiresPrescription = v),
                  activeThumbColor: AppColors.primary,
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Add Item',
                  // `addItem` creates a new doc, so without this guard a
                  // fast double-tap adds the same stock item twice.
                  isLoading: saving,
                  onTap: saving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final price = num.tryParse(priceCtrl.text.trim()) ?? 0;
                          final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;
                          if (name.isEmpty || saving) return;
                          setSheetState(() => saving = true);
                          try {
                            await PharmacyInventoryService.addItem(
                              pharmacyId,
                              name: name,
                              brand: brandCtrl.text.trim(),
                              price: price,
                              stock: stock,
                              requiresPrescription: requiresPrescription,
                            );
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          } catch (_) {
                            if (sheetContext.mounted) {
                              setSheetState(() => saving = false);
                              FeedbackService.showError(sheetContext,
                                  'Could not add this item. Check your connection.');
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

    // The sheet's controllers are created per-open and would otherwise leak
    // one set per invocation.
    nameCtrl.dispose();
    brandCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryProvider);
    final uid = PharmacyProfileService.currentUid;

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyInventory,
      title: 'Inventory',
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddItemSheet(context, uid),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
      body: inventoryAsync.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No inventory yet',
              message: 'Add medicines and equipment to track your stock.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: items.length,
            itemBuilder: (context, i) => Dismissible(
              key: ValueKey(items[i].id),
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
                title: 'Remove Item',
                message: 'Remove "${items[i].name}" from your inventory? This cannot be undone.',
                confirmLabel: 'Remove',
                destructive: true,
              ),
              onDismissed: (_) {
                if (uid != null) {
                  PharmacyInventoryService.deleteItem(uid, items[i].id);
                }
              },
              child: _InventoryTile(item: items[i], pharmacyId: uid ?? ''),
            ),
          );
        },
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  final InventoryItem item;
  final String pharmacyId;
  const _InventoryTile({required this.item, required this.pharmacyId});

  Color get _stockColor {
    if (item.isOutOfStock) return AppColors.error;
    if (item.isLowStock) return AppColors.warning;
    return AppColors.success;
  }

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
                Row(
                  children: [
                    Flexible(child: Text(item.name, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis)),
                    if (item.requiresPrescription) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.medical_information_outlined, size: 14, color: AppColors.warning),
                    ],
                  ],
                ),
                if (item.brand.isNotEmpty)
                  Text(item.brand, style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Text(CurrencyFormatter.format(item.price), style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(
                label: item.isOutOfStock ? 'Out of stock' : '${item.stock} in stock',
                color: _stockColor,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    onPressed: item.stock <= 0
                        ? null
                        : () => PharmacyInventoryService.updateStock(pharmacyId, item.id, item.stock - 1),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    onPressed: () => PharmacyInventoryService.updateStock(pharmacyId, item.id, item.stock + 1),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
