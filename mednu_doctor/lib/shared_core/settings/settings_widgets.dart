import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/ux_widgets.dart';
import 'settings_models.dart';

/// Reusable settings tile/card set, promoted from the private
/// `_SettingsTile`/`_SettingsCard` pattern in
/// `features/settings/screens/settings_screen.dart` so future partner
/// roles (and, optionally, a future rewrite of the doctor settings screen)
/// share one implementation instead of five copy-pasted ones.
class SharedSettingsSection extends StatelessWidget {
  final SettingsSectionData data;
  const SharedSettingsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              data.title.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(letterSpacing: 0.6),
            ),
          ),
          PremiumCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < data.items.length; i++) ...[
                  SharedSettingsTile(item: data.items[i]),
                  if (i != data.items.length - 1)
                    const Divider(height: 1, color: AppColors.divider, indent: 56),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SharedSettingsTile extends StatelessWidget {
  final SettingsItemData item;
  const SharedSettingsTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.destructive
        ? AppColors.error
        : (item.iconColor ?? AppColors.primary);

    return InkWell(
      onTap: item.trailing == SettingsItemTrailing.toggle ? null : item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: item.destructive ? AppColors.error : AppColors.textPrimary,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(item.subtitle!, style: AppTextStyles.bodySmall),
                  ],
                ],
              ),
            ),
            _buildTrailing(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing() {
    switch (item.trailing) {
      case SettingsItemTrailing.toggle:
        return Switch.adaptive(
          value: item.toggleValue,
          onChanged: item.onToggle,
          activeThumbColor: AppColors.primary,
        );
      case SettingsItemTrailing.value:
        return Text(item.valueText ?? '', style: AppTextStyles.bodyMedium);
      case SettingsItemTrailing.chevron:
        return const Icon(Icons.chevron_right_rounded, color: AppColors.textHint);
      case SettingsItemTrailing.none:
        return const SizedBox.shrink();
    }
  }
}
