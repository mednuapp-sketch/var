import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../constants/app_colors.dart';

/// Purely presentational — the caller owns persistence (see
/// [WhatsAppOptInService]) since where/when it's safe to write differs by
/// screen (e.g. mid-registration, before the profile doc exists, vs. an
/// existing settings screen).
class WhatsAppOptInTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const WhatsAppOptInTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: context.appPrimary,
      contentPadding: EdgeInsets.zero,
      title: Text('whatsapp_optin.title'.tr()),
      subtitle: Text('whatsapp_optin.subtitle'.tr()),
    );
  }
}
