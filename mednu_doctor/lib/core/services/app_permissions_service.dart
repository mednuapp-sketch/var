import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class _PermissionInfo {
  final Permission permission;
  final IconData icon;
  final String title;
  final String reason;
  const _PermissionInfo(this.permission, this.icon, this.title, this.reason);
}

/// Returns the correct media permission based on platform/Android version.
/// Android 13+ uses READ_MEDIA_IMAGES (Permission.photos).
/// Android ≤12 uses READ_EXTERNAL_STORAGE (Permission.storage).
Permission get _mediaPermission {
  if (Platform.isAndroid) {
    // permission_handler maps Permission.photos → READ_MEDIA_IMAGES on API 33+
    // and gracefully falls back on older APIs.
    return Permission.photos;
  }
  return Permission.storage;
}

List<_PermissionInfo> get _kPermissions => [
  const _PermissionInfo(Permission.camera,     Icons.camera_alt_rounded,  'Camera',          'Take profile photos and participate in video consultations.'),
  const _PermissionInfo(Permission.microphone, Icons.mic_rounded,         'Microphone',      'Talk with patients during live video consultations.'),
  const _PermissionInfo(Permission.location,   Icons.location_on_rounded, 'Location',        'Show your GPS position to nearby patients when you go online.'),
  const _PermissionInfo(Permission.contacts,   Icons.contacts_rounded,    'Contacts',        'Pick emergency contacts for your SOS alert feature.'),
  _PermissionInfo(_mediaPermission, Icons.photo_library_rounded, 'Photos & Media', 'Save prescriptions, access reports and upload profile photos.'),
];


class AppPermissionsService {
  static const _prefKey = 'permissions_sheet_shown_v1';

  static Future<void> checkAndPrompt(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_prefKey) ?? false;

    final toRequest = <_PermissionInfo>[];
    for (final p in _kPermissions) {
      final s = await p.permission.status;
      if (!s.isGranted) toRequest.add(p);
    }

    if (toRequest.isEmpty) return;
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _PermissionsSheet(
        items: toRequest,
        isFirstTime: !alreadyShown,
      ),
    );

    await prefs.setBool(_prefKey, true);
  }
}

class _PermissionsSheet extends StatefulWidget {
  final List<_PermissionInfo> items;
  final bool isFirstTime;
  const _PermissionsSheet({required this.items, required this.isFirstTime});

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late Map<Permission, PermissionStatus> _statuses;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _statuses = {for (final i in widget.items) i.permission: PermissionStatus.denied};
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    for (final info in widget.items) {
      final s = await info.permission.status;
      if (mounted) setState(() => _statuses[info.permission] = s);
    }
  }

  Future<void> _requestAll() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    // Step 1: request each permission via system dialog
    for (final info in widget.items) {
      final s = await info.permission.status;
      if (s.isGranted || s.isPermanentlyDenied) continue;
      await info.permission.request();
    }

    await _refreshStatuses();

    // Step 2: if any are permanently denied after request, direct to App Settings
    final permanentlyDenied = widget.items.where((i) =>
        _statuses[i.permission]?.isPermanentlyDenied ?? false);

    if (permanentlyDenied.isNotEmpty) {
      setState(() => _requesting = false);
      // Show explanation then open settings
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Open App Settings',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            content: Text(
              'Some permissions are blocked. Please enable them in App Settings:\n\n'
              '${permanentlyDenied.map((p) => '• ${p.title}').join('\n')}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        await _refreshStatuses();
      }
    } else {
      setState(() => _requesting = false);
    }

    // Auto-close when all permissions are resolved
    if (mounted &&
        _statuses.values.every((s) => s.isGranted || s.isPermanentlyDenied)) {
      Navigator.pop(context);
    }
  }

  bool get _anyPermanentlyDenied =>
      _statuses.values.any((s) => s.isPermanentlyDenied);

  bool get _allResolved =>
      _statuses.values.every((s) => s.isGranted || s.isPermanentlyDenied);

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      // Max height: 90% of screen so it never goes full screen
      constraints: BoxConstraints(maxHeight: screenH * 0.90),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────────
          Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            widget.isFirstTime ? 'App Permissions Required' : 'Some Permissions Missing',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'MedNU Doctor needs the following permissions to work properly.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
          ),
          const SizedBox(height: 16),

          // ── Scrollable permission list ───────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...widget.items.map((info) => _PermissionRow(
                        info: info,
                        status: _statuses[info.permission] ?? PermissionStatus.denied,
                      )),
                  if (_anyPermanentlyDenied) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withValues(alpha:0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Blocked permissions must be enabled in App Settings.',
                            style: AppTextStyles.caption.copyWith(color: AppColors.warning, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Fixed action buttons — always visible ────────
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    // Always enabled — never null
                    onPressed: _requesting ? null : _requestAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withValues(alpha:0.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _requesting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                    label: Text(
                      _requesting ? 'Requesting…' : 'Grant Permissions',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Skip only shows after first attempt or when all resolved
                if (!widget.isFirstTime || _allResolved) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Skip for now',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final _PermissionInfo info;
  final PermissionStatus status;
  const _PermissionRow({required this.info, required this.status});

  @override
  Widget build(BuildContext context) {
    final isGranted = status.isGranted;
    final isBlocked = status.isPermanentlyDenied;

    final Color badgeColor = isGranted ? AppColors.success : isBlocked ? AppColors.error : AppColors.warning;
    final String badgeLabel = isGranted ? 'Allowed' : isBlocked ? 'Blocked' : 'Not set';
    final IconData badgeIcon = isGranted
        ? Icons.check_circle_rounded
        : isBlocked
            ? Icons.block_rounded
            : Icons.radio_button_unchecked_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted
              ? AppColors.success.withValues(alpha:0.2)
              : isBlocked
                  ? AppColors.error.withValues(alpha:0.2)
                  : AppColors.border,
        ),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(info.icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info.title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
            Text(info.reason, style: AppTextStyles.caption.copyWith(height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(badgeIcon, size: 12, color: badgeColor),
            const SizedBox(width: 4),
            Text(badgeLabel, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: badgeColor)),
          ]),
        ),
      ]),
    );
  }
}
