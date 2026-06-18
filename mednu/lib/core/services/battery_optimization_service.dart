import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prompts the user (once, ever) to exempt MedNU from battery optimization.
///
/// Aggressive OEM battery managers (MIUI, ColorOS, FuntouchOS, OneUI) kill
/// the background FCM listener once the app is swiped away, which silently
/// stops appointment reminders, doctor-call alerts and order updates from
/// arriving. Whitelisting the app keeps that listener alive.
///
/// Android-only — iOS has no equivalent restriction.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const _kAskedPrefKey = 'battery_opt_prompt_shown';

  /// Call once after the user is signed in (e.g. from the root app widget's
  /// auth-state listener). Shows a short explainer dialog before the system
  /// permission prompt — bare system dialogs without context get reflexively
  /// denied far more often.
  static Future<void> promptIfNeeded(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAskedPrefKey) == true) return;

      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        await prefs.setBool(_kAskedPrefKey, true);
        return;
      }

      // Mark as asked immediately so a crash or dismissed dialog never
      // re-nags the user on every subsequent launch.
      await prefs.setBool(_kAskedPrefKey, true);

      if (!context.mounted) return;
      final shouldAsk = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Stay notified'),
          content: const Text(
            'To make sure you never miss appointment reminders, doctor '
            'calls, or order updates — even when MedNU is closed — please '
            'allow it to run in the background on the next screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldAsk == true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Non-critical — never block app usage over this.
    }
  }
}
