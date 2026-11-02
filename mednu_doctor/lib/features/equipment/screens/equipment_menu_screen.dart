import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/equipment_item.dart';
import '../providers/equipment_providers.dart';
import '../services/equipment_inventory_service.dart';
import '../services/equipment_profile_service.dart';
import '../widgets/equipment_item_sheet.dart';

enum _MenuFilter { all, available, soldOut }

/// The vendor's own menu — private data at `equipment_profiles/{uid}/items`.
/// A Cloud Function mirrors every item into the patient-facing catalogue while
/// this vendor is approved, so the price, the unit count and the
/// Available / Sold out switch below are what patients see, live.
class EquipmentMenuScreen extends ConsumerStatefulWidget {
  const EquipmentMenuScreen({super.key});

  @override
  ConsumerState<EquipmentMenuScreen> createState() => _EquipmentMenuScreenState();
}

class _EquipmentMenuScreenState extends ConsumerState<EquipmentMenuScreen> {
  _MenuFilter _filter = _MenuFilter.all;

  bool _matches(EquipmentItem i) {
    switch (_filter) {
      case _MenuFilter.all:
        return true;
      case _MenuFilter.available:
        return i.availability != EquipmentAvailability.soldOut;
      case _MenuFilter.soldOut:
        return i.availability == EquipmentAvailability.soldOut;
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(equipmentItemsProvider);
    final profile = ref.watch(equipmentProfileProvider).valueOrNull;
    final uid = EquipmentProfileService.currentUid;

    return SharedAppShell(
      currentRoute: AppRoutes.equipmentMenu,
      title: 'My Equipment',
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => EquipmentItemSheet.show(context, vendorId: uid),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add equipment', style: TextStyle(color: Colors.white)),
            ),
      body: itemsAsync.when(
        loading: () => const ListLoadingState(hasAvatar: true),
        error: (_, __) => const NetworkErrorState(),
        data: (items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.health_and_safety_outlined,
              title: 'Your menu is empty',
              message: 'Add the equipment you rent or sell — wheelchairs, oxygen concentrators, '
                  'beds. Patients can book them as soon as your shop is approved.',
            );
          }

          final soldOut = items.where((i) => i.availability == EquipmentAvailability.soldOut).length;
          final visible = items.where(_matches).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (profile != null && !profile.isActive)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _InfoBanner(
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.warning,
                    text: 'Your shop is awaiting admin approval. You can build your menu now — '
                        'it goes live for patients the moment you are approved.',
                  ),
                ),
              if (profile != null && profile.isActive && !profile.acceptingOrders)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _InfoBanner(
                    icon: Icons.pause_circle_filled_rounded,
                    color: AppColors.textSecondary,
                    text: 'Your shop is closed, so every item shows as unavailable. '
                        'Re-open it from the dashboard to take orders.',
                  ),
                ),
              _FilterBar(
                filter: _filter,
                total: items.length,
                soldOut: soldOut,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('Nothing here.', style: AppTextStyles.bodySmall)),
                )
              else
                for (final item in visible)
                  _MenuItemCard(key: ValueKey(item.id), item: item, vendorId: uid ?? ''),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _MenuFilter filter;
  final int total;
  final int soldOut;
  final ValueChanged<_MenuFilter> onChanged;
  const _FilterBar({required this.filter, required this.total, required this.soldOut, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(_MenuFilter f, String label) => ChoiceChip(
          label: Text(label),
          selected: filter == f,
          onSelected: (_) => onChanged(f),
          selectedColor: AppColors.primary.withValues(alpha: 0.14),
          labelStyle: AppTextStyles.labelMedium.copyWith(
            color: filter == f ? AppColors.primary : AppColors.textSecondary,
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(_MenuFilter.all, 'All ($total)'),
        chip(_MenuFilter.available, 'Available (${total - soldOut})'),
        chip(_MenuFilter.soldOut, 'Sold out ($soldOut)'),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
          ],
        ),
      );
}

class _MenuItemCard extends StatefulWidget {
  final EquipmentItem item;
  final String vendorId;
  const _MenuItemCard({super.key, required this.item, required this.vendorId});

  @override
  State<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends State<_MenuItemCard> {
  bool _busy = false;

  EquipmentItem get item => widget.item;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy || widget.vendorId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) FeedbackService.showError(context, failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await MedNuConfirmationDialog.show(
      context,
      title: 'Remove equipment',
      message: 'Remove "${item.name}" from your menu? Patients will no longer see it.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => EquipmentInventoryService.deleteItem(widget.vendorId, item.id),
        'Could not remove this item. Check your connection.');
  }

  String _priceLine() {
    final parts = <String>[];
    if (item.offersRent && item.rentPricePerDay > 0) parts.add('₹${item.rentPricePerDay}/day');
    if (item.offersBuy && item.buyPrice > 0) parts.add('Buy ₹${item.buyPrice}');
    return parts.isEmpty ? 'No price set' : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final availability = item.availability;
    final (label, color) = switch (availability) {
      EquipmentAvailability.available => ('Available', AppColors.success),
      EquipmentAvailability.lowStock => ('Only ${item.stock} left', AppColors.warning),
      EquipmentAvailability.soldOut => ('Sold out', AppColors.error),
    };
    final soldOut = availability == EquipmentAvailability.soldOut;

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Opacity(
        opacity: soldOut ? 0.82 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(url: item.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: AppTextStyles.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (item.category.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(item.category, style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Text(_priceLine(), style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                      if (item.deposit > 0)
                        Text('₹${item.deposit} refundable deposit', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                  onSelected: (v) {
                    if (v == 'edit') {
                      EquipmentItemSheet.show(context, vendorId: widget.vendorId, existing: item);
                    } else if (v == 'delete') {
                      _delete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit details')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ],
            ),
            const Divider(height: 22, color: AppColors.divider),
            Row(
              children: [
                StatusBadge(label: label, color: color, dot: true),
                const Spacer(),
                _StockStepper(
                  stock: item.stock,
                  enabled: !_busy,
                  onChanged: (v) => _run(
                    () => EquipmentInventoryService.setStock(widget.vendorId, item.id, v),
                    'Could not update stock.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.isAvailable ? 'Visible & bookable' : 'Marked sold out',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
                Switch.adaptive(
                  value: item.isAvailable,
                  activeTrackColor: AppColors.success,
                  onChanged: _busy
                      ? null
                      : (v) => _run(
                            () => EquipmentInventoryService.setAvailable(widget.vendorId, item.id, v),
                            'Could not update availability.',
                          ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.health_and_safety_rounded, color: AppColors.primary, size: 30),
    );
    if (url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _StockStepper extends StatelessWidget {
  final int stock;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _StockStepper({required this.stock, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: onTap == null ? AppColors.textHint : AppColors.primary),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Units  ', style: AppTextStyles.bodySmall),
        btn(Icons.remove_rounded, 'One fewer', enabled && stock > 0 ? () => onChanged(stock - 1) : null),
        SizedBox(
          width: 36,
          child: Text('$stock', textAlign: TextAlign.center, style: AppTextStyles.labelLarge),
        ),
        btn(Icons.add_rounded, 'One more', enabled ? () => onChanged(stock + 1) : null),
      ],
    );
  }
}
