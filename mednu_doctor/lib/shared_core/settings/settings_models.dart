import 'package:flutter/material.dart';

enum SettingsItemTrailing { chevron, toggle, value, none }

@immutable
class SettingsItemData {
  final IconData icon;
  final String title;
  final String? subtitle;
  final SettingsItemTrailing trailing;
  final bool toggleValue;
  final String? valueText;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final Color? iconColor;
  final bool destructive;

  const SettingsItemData({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing = SettingsItemTrailing.chevron,
    this.toggleValue = false,
    this.valueText,
    this.onTap,
    this.onToggle,
    this.iconColor,
    this.destructive = false,
  });
}

@immutable
class SettingsSectionData {
  final String title;
  final List<SettingsItemData> items;

  const SettingsSectionData({required this.title, required this.items});
}
