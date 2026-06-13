import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../services/doctor_auth_service.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen>
    with SingleTickerProviderStateMixin {
  String _status = 'pending';
  bool _loading = true;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await DoctorAuthService.getProfile(uid);
      if (!mounted) return;
      final status = profile?['status'] as String? ?? 'pending';
      if (status == 'active') {
        context.go(AppRoutes.dashboard);
        return;
      }
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isSuspended = _status == 'suspended';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Top gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isSuspended
                      ? [const Color(0xFFB71C1C), const Color(0xFFC62828)]
                      : [const Color(0xFF880E4F), const Color(0xFFC2185B), const Color(0xFF7B1FA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.05),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // White card base
          Positioned(
            top: 180,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Column(
                children: [
                  const SizedBox(height: 30),

                  // Status icon with pulse
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Transform.scale(
                      scale: isSuspended ? 1.0 : _pulse.value,
                      child: child,
                    ),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha:0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isSuspended
                            ? Icons.cancel_rounded
                            : Icons.hourglass_top_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    isSuspended ? 'Application Rejected' : 'Verification Pending',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),

                  // Content card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSuspended
                              ? 'Your Application Was Not Approved'
                              : 'Under Review',
                          style: AppTextStyles.h3.copyWith(
                            color: isSuspended ? AppColors.error : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isSuspended
                              ? 'Your application did not meet our verification requirements. Please contact our support team for more information or to resubmit.'
                              : 'Your documents are being reviewed by our medical verification team. This usually takes 24–48 hours.',
                          style: AppTextStyles.bodyMedium.copyWith(height: 1.6),
                        ),
                      ],
                    ),
                  ),

                  if (!isSuspended) ...[
                    const SizedBox(height: 20),

                    // Progress steps
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Application Progress',
                              style: AppTextStyles.labelLarge),
                          const SizedBox(height: 16),
                          ...[
                            _ProgressStep(
                              icon: Icons.check_circle_rounded,
                              label: 'Registration Submitted',
                              sublabel: 'Successfully received',
                              isDone: true,
                            ),
                            _ProgressStep(
                              icon: Icons.pending_rounded,
                              label: 'Document Verification',
                              sublabel: 'In progress — 24-48 hrs',
                              isDone: false,
                            ),
                            _ProgressStep(
                              icon: Icons.pending_rounded,
                              label: 'Profile Approval',
                              sublabel: 'Awaiting document check',
                              isDone: false,
                            ),
                            _ProgressStep(
                              icon: Icons.pending_rounded,
                              label: 'Account Activation',
                              sublabel: 'You\'ll get notified',
                              isDone: false,
                              isLast: true,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha:0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha:0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "We'll notify you via SMS & email once verified. Check back anytime.",
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppColors.primary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await DoctorAuthService.signOut();
                        if (mounted) context.go(AppRoutes.login);
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: Text(
                        isSuspended ? 'Contact Support & Sign Out' : 'Sign Out',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isSuspended ? AppColors.error : AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  if (!isSuspended) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _loading = true);
                          _loadStatus();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Check Status Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isDone;
  final bool isLast;

  const _ProgressStep({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isDone,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.success
                    : AppColors.divider,
                shape: BoxShape.circle,
                border: isDone
                    ? null
                    : Border.all(color: AppColors.border, width: 2),
              ),
              child: Icon(
                isDone ? Icons.check_rounded : Icons.radio_button_unchecked_rounded,
                color: isDone ? Colors.white : AppColors.textHint,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isDone ? AppColors.success.withValues(alpha:0.3) : AppColors.divider,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDone ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
