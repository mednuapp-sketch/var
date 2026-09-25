import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/router/app_router.dart';
import '../../core/services/feedback_service.dart';
import '../../core/widgets/mednu_components.dart';
import 'account_deletion_service.dart';
import 'settings_models.dart';

/// Shared "Legal" and "Delete Account" rows for every partner role's settings
/// screen, so Privacy Policy / Terms / in-app account deletion (a Google Play
/// requirement) behave identically everywhere.
class AccountSettingsItems {
  AccountSettingsItems._();

  static const privacyPolicyUrl = 'https://mednu.in/privacy-policy';
  static const termsUrl = 'https://mednu.in/terms';

  static Future<void> _open(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        FeedbackService.showError(context, 'Could not open the page. Please try again.');
      }
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, 'Could not open the page. Please try again.');
      }
    }
  }

  /// Privacy Policy + Terms of Service rows — append to the "About" section.
  static List<SettingsItemData> legal(BuildContext context) => [
        SettingsItemData(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          onTap: () => _open(context, privacyPolicyUrl),
        ),
        SettingsItemData(
          icon: Icons.description_outlined,
          title: 'Terms of Service',
          onTap: () => _open(context, termsUrl),
        ),
      ];

  /// Destructive "Delete Account" row — append to the "Account" section.
  /// [role] is the role's firestore value (e.g. 'lab', 'pharmacy', 'doctor').
  static SettingsItemData deleteAccount(BuildContext context, {required String role}) =>
      SettingsItemData(
        icon: Icons.delete_forever_outlined,
        title: 'Delete Account',
        subtitle: 'Request permanent deletion of your account and data',
        destructive: true,
        trailing: SettingsItemTrailing.none,
        onTap: () => confirmAndRequestDeletion(context, role: role),
      );

  static Future<void> confirmAndRequestDeletion(
    BuildContext context, {
    required String role,
  }) async {
    final confirmed = await MedNuConfirmationDialog.show(
      context,
      title: 'Delete your account?',
      message: 'This sends a request to permanently delete your MedNU partner '
          'account and personal data. You will be signed out now and our team '
          'will process the deletion. Records we are legally required to keep '
          '(such as consultation and payment records) may be retained.',
      confirmLabel: 'Request Deletion',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    FeedbackService.showLoading(context, 'Submitting request...');
    try {
      final result = await AccountDeletionService.requestDeletion(role: role);
      if (!context.mounted) return;
      FeedbackService.dismiss(context);
      FeedbackService.showSuccess(
        context,
        result == DeletionRequestResult.alreadyRequested
            ? 'A deletion request is already pending for your account.'
            : 'Deletion request submitted.',
      );
      await FirebaseAuth.instance.signOut();
      if (context.mounted) context.go(AppRoutes.login);
    } catch (_) {
      if (!context.mounted) return;
      FeedbackService.dismiss(context);
      FeedbackService.showError(context, 'Could not submit your request. Please try again.');
    }
  }
}
