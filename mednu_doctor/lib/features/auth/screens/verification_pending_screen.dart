import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../services/doctor_auth_service.dart';
import '../../../shared_core/documents/partner_document_models.dart';
import '../../../shared_core/documents/partner_document_upload_card.dart';
import '../../../shared_core/models/app_role.dart';
import '../../../shared_core/navigation/role_menu.dart';
import '../../../shared_core/providers/role_providers.dart';
import '../../../shared_core/widgets/role_switcher_sheet.dart';
import '../../../shared_core/services/role_prefs.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen>
    with TickerProviderStateMixin {
  String _status = 'pending';
  bool _loading = true;

  // Partner (non-doctor) accounts only: documents the profile still lacks.
  // Registration uploads them before the profile exists, but if the final
  // write ever fails the profile can exist without them — surface the upload
  // here instead of showing a "pending" wait for an application that can't be
  // reviewed.
  String? _partnerRole;
  String? _partnerTypeKey;
  String? _partnerUid;
  List<String> _missingDocs = const [];
  Map<String, dynamic> _documents = const {};
  Map<String, dynamic> _documentVerification = const {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;

  // Re-review request: the owner may write only `resubmittedAt`/`resubmitNote`
  // on their own profile while it is not active (see firestore.rules). Admin
  // clears `resubmittedAt` again when it acts on the profile.
  DocumentReference<Map<String, dynamic>>? _statusRef;
  DateTime? _resubmittedAt;
  bool _resubmitting = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _rotateCtrl;

  @override
  void initState() {
    super.initState();
    _startListening();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // A non-doctor role's approval is recorded on its own `{role}_profiles`
    // doc (that's what Admin's partner-approval flow actually writes) — the
    // sparse `doctors/{uid}` doc created at registration time for those
    // roles stays `status: 'pending'` forever, since nothing ever needs to
    // flip it. Doctor accounts are unaffected: they have no non-doctor
    // `roles` entry, so this resolves to the exact same `doctors/{uid}`
    // watch this screen always used.
    AppRole role = AppRole.doctor;
    try {
      final doctorSnap = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .get();
      final rawRoles = doctorSnap.data()?['roles'];
      final roles = AppRoleX.listFrom(rawRoles);
      // The active role (what the switcher chose), not `roles.first` —
      // otherwise a pending Hospital watched the Doctor doc, saw 'active',
      // bounced to the Doctor dashboard and the router bounced it back.
      final serverRaw = doctorSnap.data()?['activeRole'] as String?;
      role = await RolePrefs.resolveActive(
        roles,
        serverPreferred:
            serverRaw != null ? AppRoleX.fromFirestoreValue(serverRaw) : null,
      );
    } catch (_) {
      // Fall back to watching `doctors/{uid}` (existing behavior) below.
    }

    final statusDocRef = role == AppRole.doctor
        ? FirebaseFirestore.instance.collection('doctors').doc(uid)
        : FirebaseFirestore.instance
              .collection(role.profileCollection)
              .doc(uid);

    _statusRef = statusDocRef;
    _statusSub = statusDocRef.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final status = (snap.data()?['status'] as String?) ?? 'pending';
        if (status == 'active') {
          // Land on the approved role's own home destination rather than
          // hardcoding the Doctor dashboard — for a Doctor account this
          // resolves to the exact same `AppRoutes.dashboard` as before.
          final destination = buildMenuForRole(role);
          context.go(
            destination.isNotEmpty
                ? destination.first.route
                : AppRoutes.dashboard,
          );
          return;
        }
        final data = snap.data();
        final isPartner = role != AppRole.doctor;
        setState(() {
          _status = status;
          _loading = false;
          _partnerRole = isPartner ? role.documentRoleKey : null;
          _partnerTypeKey = isPartner ? role.documentTypeKey : null;
          _partnerUid = uid;
          final ra = data?['resubmittedAt'];
          _resubmittedAt = ra is Timestamp ? ra.toDate() : null;
          _documents = Map<String, dynamic>.from(
              (data?['documents'] as Map?) ?? const {});
          _documentVerification = Map<String, dynamic>.from(
              (data?['documentVerification'] as Map?) ?? const {});
          _missingDocs = isPartner && snap.exists
              ? PartnerDocumentType.missingFor(
                  role.documentTypeKey, data?['documents'])
              : const [];
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  Future<void> _requestReReview() async {
    final ref = _statusRef;
    if (ref == null || _resubmitting) return;
    final noteCtrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request re-review'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Let our team know you have updated your documents or details. '
                'You can add an optional note.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Note for the review team (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, noteCtrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    noteCtrl.dispose();
    if (note == null || !mounted) return;
    setState(() => _resubmitting = true);
    try {
      await ref.update({
        'resubmittedAt': FieldValue.serverTimestamp(),
        'resubmitNote': note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Re-review requested. Our team will take another look.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not send request: $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    await _statusSub?.cancel();
    _startListening();
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
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header — height comes purely from its own content (safe-area
          // inset + illustration + spacing + title + padding), never a
          // hardcoded pixel guess. A fixed-height hero here previously let
          // the title text spill onto the white card below on real devices
          // (extra status-bar/call-banner inset, larger text scale, etc.),
          // where white-on-white made it read as washed out/invisible.
          // Sizing to content makes that overlap structurally impossible.
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSuspended
                    ? [const Color(0xFFB71C1C), const Color(0xFFC62828)]
                    : [
                        AppColors.primaryDark,
                        AppColors.primary,
                        AppColors.secondary,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: -40,
                  right: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
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
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, topInset + 20, 24, 44),
                  // Full width: a Stack top-left-aligns its non-positioned
                  // child, so without this the column shrank to the title's
                  // width and the whole hero sat left of centre.
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Layered status illustration: a rotating dashed ring
                        // (still "in progress"), a pulsing center badge, and
                        // small orbiting accent icons — reads as an active,
                        // living process rather than a single static glyph.
                        _StatusIllustration(
                          isSuspended: isSuspended,
                          pulse: _pulse,
                          rotation: _rotateCtrl,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isSuspended
                              ? 'Application Rejected'
                              : 'Verification Pending',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body — rounded white sheet, nudged up 24px to overlap the
          // header's empty bottom padding for a layered "card floating over
          // the hero" look. The overlap only ever covers gradient padding,
          // never text, since the header's bottom padding (44) exceeds it.
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      child: Column(
                        children: [
                          if ((_missingDocs.isNotEmpty || isSuspended) &&
                              _partnerRole != null &&
                              _partnerUid != null) ...[
                            if (_missingDocs.isNotEmpty)
                              _MissingDocsNotice(missing: _missingDocs),
                            if (_missingDocs.isNotEmpty)
                              const SizedBox(height: 12),
                            PartnerDocumentsSection(
                              role: _partnerRole!,
                              typeKey: _partnerTypeKey,
                              uid: _partnerUid!,
                              documents: _documents,
                              documentVerification: _documentVerification,
                            ),
                            const SizedBox(height: 20),
                          ],
                          // Content card
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
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
                                    color: isSuspended
                                        ? AppColors.error
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  isSuspended
                                      ? 'Your application did not meet our verification requirements. Update your documents below if needed, then tap "Request re-review" and our team will take another look.'
                                      : 'Your documents are being reviewed by our medical verification team. This usually takes 24–48 hours.',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    height: 1.6,
                                  ),
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
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Application Progress',
                                    style: AppTextStyles.labelLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  ...const [
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
                                color: AppColors.primary.withValues(
                                  alpha: 0.06,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
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
                                        fontFamily: 'Inter',
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

                          // Re-review request (rejected, or pending with changes).
                          if (_statusRef != null) ...[
                            if (_resubmittedAt != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.check_circle_rounded,
                                        size: 16, color: AppColors.success),
                                    SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Re-review requested — awaiting our team',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _resubmitting ? null : _requestReReview,
                                  icon: _resubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.replay_rounded,
                                          size: 18),
                                  label: Text(_resubmittedAt != null
                                      ? 'Request re-review again'
                                      : 'Request re-review'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          // Action buttons
                          // A pending service must not trap the account: let
                          // it hop to another of its profiles from here.
                          Consumer(builder: (context, ref, _) {
                            if (!ref.watch(roleEngineProvider).canSwitchRoles) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: () => showRoleSwitcherSheet(context),
                                  icon: const Icon(Icons.swap_horiz_rounded,
                                      size: 18),
                                  label: const Text('Switch profile'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(
                                        color: AppColors.primary),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await DoctorAuthService.signOut();
                                if (mounted && context.mounted)
                                  context.go(AppRoutes.login);
                              },
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: Text(
                                isSuspended
                                    ? 'Contact Support & Sign Out'
                                    : 'Sign Out',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isSuspended
                                    ? AppColors.error
                                    : AppColors.primary,
                                side: BorderSide(
                                    color: isSuspended
                                        ? AppColors.error
                                        : AppColors.primary),
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
                                onPressed: _refreshStatus,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Check Status Again'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A layered "this is actively happening" illustration: a slowly rotating
/// dashed ring, a pulsing centre badge, and three small satellite icons
/// (document / magnifier / shield) fixed at even angles around the ring —
/// reads as a living review process rather than one static glyph.
class _StatusIllustration extends StatelessWidget {
  final bool isSuspended;
  final Animation<double> pulse;
  final Animation<double> rotation;

  const _StatusIllustration({
    required this.isSuspended,
    required this.pulse,
    required this.rotation,
  });

  static const _satellites = [
    (Icons.description_outlined, -1.0), // top-left-ish
    (Icons.search_rounded, 0.0), // right
    (Icons.verified_user_outlined, 1.0), // bottom-left-ish
  ];

  @override
  Widget build(BuildContext context) {
    // Outer box is larger than the ring so the satellite badges (which sit
    // on the ring) are fully inside it and never clipped.
    const box = 164.0;
    const size = 132.0; // ring diameter
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating dashed ring — suppressed for the rejected state, where
          // "still in progress" would be the wrong signal.
          if (!isSuspended)
            AnimatedBuilder(
              animation: rotation,
              builder: (_, __) => Transform.rotate(
                angle: rotation.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _DashedRingPainter(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),

          // Satellite badges, evenly spaced around the ring.
          if (!isSuspended)
            for (var i = 0; i < _satellites.length; i++)
              _SatelliteIcon(
                icon: _satellites[i].$1,
                angle: (2 * math.pi / _satellites.length) * i - (math.pi / 2),
                radius: size / 2 - 1,
              ),

          // Centre badge with the existing pulse animation.
          AnimatedBuilder(
            animation: pulse,
            builder: (_, child) => Transform.scale(
              scale: isSuspended ? 1.0 : pulse.value,
              child: child,
            ),
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isSuspended
                    ? Icons.cancel_rounded
                    : Icons.hourglass_top_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SatelliteIcon extends StatelessWidget {
  final IconData icon;
  final double angle;
  final double radius;

  const _SatelliteIcon({
    required this.icon,
    required this.angle,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final offset = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    return Transform.translate(
      offset: offset,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 15, color: AppColors.primary),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  final Color color;
  const _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final radius = size.width / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    const dashCount = 24;
    const dashFraction = 0.6; // fraction of each segment that is "on"
    for (var i = 0; i < dashCount; i++) {
      final startAngle = (2 * math.pi / dashCount) * i;
      const sweep = (2 * math.pi / dashCount) * dashFraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
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
                color: isDone ? AppColors.success : AppColors.divider,
                shape: BoxShape.circle,
                border: isDone
                    ? null
                    : Border.all(color: AppColors.border, width: 2),
              ),
              child: Icon(
                isDone
                    ? Icons.check_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isDone ? Colors.white : AppColors.textHint,
                size: 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isDone
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.divider,
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
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDone ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: const TextStyle(
                    fontFamily: 'Inter',
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

/// Shown on the pending screen while required verification documents are
/// missing, so an application with nothing to review is never mistaken for
/// one that is simply waiting on admin.
class _MissingDocsNotice extends StatelessWidget {
  final List<String> missing;
  const _MissingDocsNotice({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.upload_file_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Upload your documents',
                    style: AppTextStyles.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Our team can only review your application once these are '
                  'uploaded: ${missing.join(', ')}.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
