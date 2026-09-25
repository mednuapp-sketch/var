import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

/// Which of the three follow-up-eligible service lines just completed.
enum FollowUpSource { doctor, nutrition, physio }

/// Shown in real time the moment a Doctor consultation, Dietician
/// consultation, or Physiotherapy session flips to `completed` — pushed from
/// the global listener in `app.dart` regardless of what screen the patient
/// is currently on (same mechanism as the incoming-call popup). Offers a
/// one-tap path to book a follow-up with the same provider.
class FollowUpPromptScreen extends StatelessWidget {
  final FollowUpSource source;
  final String providerId;
  final String providerName;
  final String? providerSpecialty;

  const FollowUpPromptScreen({
    super.key,
    required this.source,
    required this.providerId,
    required this.providerName,
    this.providerSpecialty,
  });

  String get _sessionLabel => switch (source) {
        FollowUpSource.doctor => 'consultation',
        FollowUpSource.nutrition => 'diet consultation',
        FollowUpSource.physio => 'therapy session',
      };

  IconData get _icon => switch (source) {
        FollowUpSource.doctor => Icons.medical_services_rounded,
        FollowUpSource.nutrition => Icons.restaurant_menu_rounded,
        FollowUpSource.physio => Icons.fitness_center_rounded,
      };

  void _bookFollowUp(BuildContext context) {
    context.pop();
    switch (source) {
      case FollowUpSource.doctor:
        context.push('/doctors/$providerId');
      case FollowUpSource.nutrition:
        context.push(AppRoutes.nutritionBookAppointment, extra: {
          'nutritionistId': providerId,
          'nutritionistName': providerName,
        });
      case FollowUpSource.physio:
        context.push('/physio/therapist/$providerId');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon, color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Session Complete',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Your $_sessionLabel with $providerName is complete.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Would you like to book a follow-up appointment?',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: context.appTextSecondary),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _bookFollowUp(context),
                                child: const Center(
                                  child: Text(
                                    'Book Follow-up',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => context.pop(),
                          child: Text(
                            'Maybe Later',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
