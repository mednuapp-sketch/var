import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Forced-update gate. Watches `app_config/app_version` =
/// { patient: {minVersion: 'x.y.z', message?}, partner: {...}, updatedAt,
/// updatedBy } and, when this build's version is below `<appKey>.minVersion`,
/// covers the whole app with a non-dismissible "Update required" screen.
///
/// Fails open: missing doc, unreadable doc, network/permission error, signed
/// out, malformed version or unreadable app version never block the app. The
/// live Firestore stream also covers returning to the foreground.
class AppVersionGate extends StatefulWidget {
  const AppVersionGate({super.key, required this.appKey, required this.child});

  /// 'patient' or 'partner'.
  final String appKey;
  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate> {
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mednu.mednu';

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  String? _current;
  String? _minVersion;
  String? _message;

  bool get _blocked {
    final cur = _parse(_current);
    final min = _parse(_minVersion);
    if (cur == null || min == null) return false; // fail open
    for (var i = 0; i < 3; i++) {
      if (cur[i] != min[i]) return cur[i] < min[i];
    }
    return false;
  }

  /// Parses 'x.y.z' (ignores any '+build' / '-pre' suffix). Null if invalid.
  static List<int>? _parse(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    if (m == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _current = info.version);
    }).catchError((_) {});
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _docSub?.cancel();
      _docSub = null;
      if (user == null) return;
      _docSub = FirebaseFirestore.instance
          .collection('app_config')
          .doc('app_version')
          .snapshots()
          .listen((snap) {
        final data = snap.data();
        final sect = data == null ? null : data[widget.appKey];
        String? min;
        String? msg;
        if (sect is Map) {
          final m = sect['minVersion'];
          final t = sect['message'];
          if (m is String) min = m;
          if (t is String && t.trim().isNotEmpty) msg = t.trim();
        }
        if (mounted) {
          setState(() {
            _minVersion = min;
            _message = msg;
          });
        }
      }, onError: (_) {
        // Network / permission error: never block.
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _docSub?.cancel();
    super.dispose();
  }

  Future<void> _openStore() async {
    try {
      await launchUrl(Uri.parse(_playStoreUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked) return widget.child;
    final cs = Theme.of(context).colorScheme;
    final showButton = defaultTargetPlatform == TargetPlatform.android;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: PopScope(
            canPop: false,
            child: Material(
              color: cs.surface,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.system_update_rounded,
                                size: 44, color: cs.primary),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Update required',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _message ??
                                'A newer version of MedNU is available. '
                                    'Please update the app to continue.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              height: 1.5,
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          if (showButton) ...[
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _openStore,
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Update now',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
