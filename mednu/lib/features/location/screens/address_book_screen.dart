import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/saved_address.dart';
import '../providers/saved_addresses_provider.dart';
import 'add_edit_address_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AddressBookScreen
// ─────────────────────────────────────────────────────────────────────────────

class AddressBookScreen extends ConsumerWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(savedAddressesProvider);
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => context.pop(),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.primary),
              ),
            ),
          ),
        ),
        title: Text('Address Book',
            style:
                AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _navigateToAdd(context),
              icon: const Icon(Icons.add_rounded,
                  size: 18, color: AppColors.primary),
              label: Text('Add New',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.primary)),
            ),
          ),
        ],
      ),
      body: addressesAsync.when(
        loading: () => const _ShimmerList(),
        error: (e, _) => Center(
          child: AppEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Failed to Load',
            message: 'Could not fetch your saved addresses.',
            iconColor: AppColors.error,
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(savedAddressesProvider),
          ),
        ),
        data: (addresses) => addresses.isEmpty
            ? AppEmptyState(
                icon: Icons.location_off_rounded,
                title: 'No Saved Addresses',
                message:
                    'Add your home, work, or other addresses for faster booking.',
                actionLabel: 'Add Address',
                onAction: () => _navigateToAdd(context),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async =>
                    ref.invalidate(savedAddressesProvider),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: addresses.length,
                  itemBuilder: (_, i) => _AnimatedAddressTile(
                    address: addresses[i],
                    index: i,
                    onEdit: () => _navigateToEdit(context, addresses[i]),
                    onDelete: () =>
                        _confirmDelete(context, ref, addresses[i].id),
                    onSetDefault: () => ref
                        .read(savedAddressesNotifierProvider.notifier)
                        .setDefault(addresses[i].id),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAdd(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Address',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _navigateToAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddEditAddressScreen()),
    );
  }

  void _navigateToEdit(BuildContext context, SavedAddress address) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => AddEditAddressScreen(existing: address)),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, String addressId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Address',
            style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
        content: Text(
          'This address will be permanently removed.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: context.appTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.appTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(savedAddressesNotifierProvider.notifier)
                  .deleteAddress(addressId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete',
                style: TextStyle(
                    fontFamily: 'Poppins', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated address tile with slide-in
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedAddressTile extends StatefulWidget {
  final SavedAddress address;
  final int index;
  final VoidCallback onEdit, onDelete, onSetDefault;
  const _AnimatedAddressTile({
    required this.address,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  State<_AnimatedAddressTile> createState() =>
      _AnimatedAddressTileState();
}

class _AnimatedAddressTileState extends State<_AnimatedAddressTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 280 + widget.index * 60),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: _AddressTile(
          address: widget.address,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete,
          onSetDefault: widget.onSetDefault,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Address tile
// ─────────────────────────────────────────────────────────────────────────────

class _AddressTile extends StatelessWidget {
  final SavedAddress address;
  final VoidCallback onEdit, onDelete, onSetDefault;
  const _AddressTile({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  IconData get _typeIcon {
    switch (address.label.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
      case 'office':
        return Icons.business_center_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color get _typeColor {
    switch (address.label.toLowerCase()) {
      case 'home':
        return AppColors.primary;
      case 'work':
      case 'office':
        return AppColors.secondary;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: address.isDefault
              ? AppColors.primary.withValues(alpha: 0.3)
              : context.appBorder,
          width: address.isDefault ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_typeIcon, color: _typeColor, size: 22),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          address.displayLabel,
                          style: AppTextStyles.labelLarge.copyWith(
                              color: context.appTextPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        _DefaultBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.formattedAddress,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: context.appTextSecondary, height: 1.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.landmark.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 12, color: context.appTextHint),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'Near: ${address.landmark}',
                            style: AppTextStyles.caption
                                .copyWith(color: context.appTextHint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!address.isDefault)
                        _Pill(
                          label: 'Set Default',
                          icon: Icons.check_circle_outline_rounded,
                          color: AppColors.accent,
                          onTap: onSetDefault,
                        ),
                      const Spacer(),
                      _Pill(
                        label: 'Edit',
                        icon: Icons.edit_rounded,
                        color: AppColors.primary,
                        onTap: onEdit,
                      ),
                      const SizedBox(width: 6),
                      _Pill(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.error,
                        onTap: onDelete,
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

class _DefaultBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded,
                size: 10, color: AppColors.primary),
            const SizedBox(width: 3),
            Text('Default',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shimmer list
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppShimmer(
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );
  }
}
