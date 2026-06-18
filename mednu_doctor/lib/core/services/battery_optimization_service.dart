import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prompts the user (once, ever) to exempt MedNU Doctor from battery
/// optimization.
///
/// Aggressive OEM battery managers (MIUI, ColorOS, FuntouchOS, OneUI) kill
/// the background FCM listener once the app is swiped away, which silently
/// stops incoming-consultation alerts and appointment reminders from
/// arriving. Whitelisting the app keeps that listener alive.
///
/// Android-only — iOS has no equivalent restriction.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const _kAskedPrefKey = 'battery_opt_prompt_shown';

  /// Call once after the doctor is signed in. Shows a short explainer
  /// dialog before the system permission prompt — bare system dialogs
  /// without context get reflexively denied far more often.
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
      // re-nags the doctor on every subsequent launch.
      await prefs.setBool(_kAskedPrefKey, true);

      if (!context.mounted) return;
      final shouldAsk = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Never miss a patient'),
          content: const Text(
            'To make sure incoming consultation requests and appointment '
            'reminders always reach you — even when MedNU Doctor is closed — '
            'please allow it to run in the background on the next screen.',
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
