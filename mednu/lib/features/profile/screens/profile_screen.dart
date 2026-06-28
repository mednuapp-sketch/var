import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/operation_logger.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../../referral/referral_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String _gender = 'Female';
  bool _populated = false;

  // Photo upload state
  File?   _localImage;
  bool    _uploading      = false;
  double  _uploadProgress = 0;
  String? _currentPhotoUrl;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  void _populate(Map<String, dynamic>? data) {
    if (_populated || data == null) return;
    _nameCtrl.text = data['name'] as String? ?? '';
    _emailCtrl.text = data['email'] as String? ?? '';
    _dobCtrl.text = data['dob'] as String? ?? '';
    final g = data['gender'] as String? ?? 'Female';
    _gender = ['Female', 'Male', 'Other'].contains(g) ? g : 'Female';
    _currentPhotoUrl = data['photoUrl'] as String?;
    _populated = true;
  }

  void _showPhotoOptions() {
    final hasPhoto =
        (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) ||
        _localImage != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Profile Photo',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                color: AppColors.secondary,
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove Photo',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    _removePhoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final uid = ref.read(authProvider).user?.uid;
    if (uid == null) return;

    File? file;
    try {
      file = source == ImageSource.gallery
          ? await ImageUploadService.pickFromGallery()
          : await ImageUploadService.pickFromCamera();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open picker: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (file == null || !mounted) return;

    setState(() {
      _localImage     = file;
      _uploading      = true;
      _uploadProgress = 0;
    });

    try {
      final url = await ImageUploadService.uploadUserProfileImage(
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await ref.read(authProvider.notifier).updatePhotoUrl(url);
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = url;
        _uploading       = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile photo updated!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading   = false;
        _localImage  = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Upload failed: ${_uploadError(e)}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _removePhoto() async {
    final uid = ref.read(authProvider).user?.uid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deleteUserProfileImage(uid);
      await ref.read(authProvider.notifier).updatePhotoUrl('');
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = '';
        _localImage      = null;
        _uploading       = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile photo removed.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Remove failed: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // Migrates an old signed URL (with token) to a permanent token-free URL.
  // Called when CachedNetworkImage fails to load, so existing users auto-heal.
  Future<void> _refreshPhotoUrl(String uid) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('users/$uid/profile.jpg');
      final signedUrl = await ref.getDownloadURL();
      final uri = Uri.parse(signedUrl);
      final stableUrl = uri.replace(queryParameters: {'alt': 'media'}).toString();
      await ref.read(authProvider.notifier).updatePhotoUrl(stableUrl);
      if (mounted) setState(() => _currentPhotoUrl = stableUrl);
    } catch (_) {}
  }

  String _uploadError(Object e) {
    final s = e.toString();
    if (s.contains('network') || s.contains('socket') || s.contains('connection')) {
      return 'Network error. Check your connection.';
    }
    if (s.contains('not-authorized') || s.contains('unauthorized') || s.contains('permission-denied')) {
      return 'Storage permission denied. Check Firebase Storage rules.';
    }
    if (s.contains('quota')) return 'Storage quota exceeded.';
    return s.replaceAll('Exception: ', '');
  }

  Future<void> _save() async {
    FeedbackService.showLoading(context, 'Saving profile...');
    try {
      await ref.read(authProvider.notifier).updateProfile(
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            dob: _dobCtrl.text.trim(),
            gender: _gender,
          );
      await OperationLogger.logSuccess(
        action: OpAction.profileUpdated,
        message: 'Profile updated successfully',
      );
      if (mounted) {
        FeedbackService.dismiss(context);
        FeedbackService.showSuccess(context, 'Profile updated successfully');
        context.pop();
      }
    } catch (e) {
      await OperationLogger.logError(
        action: OpAction.profileUpdated,
        errorDetails: e.toString(),
        message: 'Failed to update profile',
      );
      if (mounted) {
        FeedbackService.showError(
          context,
          'Failed to save profile. Please try again.',
          onRetry: _save,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final uid = authState.user?.uid ?? '';
    final userDocAsync = uid.isNotEmpty
        ? ref.watch(userDocProvider(uid))
        : const AsyncValue<Map<String, dynamic>?>.data(null);

    userDocAsync.whenData(_populate);

    final userName = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Your Profile';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: authState.isLoading ? null : _save,
                  child: authState.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _uploading ? null : _showPhotoOptions,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: _localImage != null
                                          ? Image.file(_localImage!, fit: BoxFit.cover)
                                          : (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty)
                                              ? CachedNetworkImage(
                                                  imageUrl: _currentPhotoUrl!,
                                                  fit: BoxFit.cover,
                                                  placeholder: (_, __) => const Icon(
                                                      Icons.person_rounded,
                                                      size: 34,
                                                      color: Colors.white),
                                                  errorWidget: (_, __, ___) {
                                                    // Old signed URL expired — refresh to permanent URL
                                                    final uid = ref.read(authProvider).user?.uid;
                                                    if (uid != null) _refreshPhotoUrl(uid);
                                                    return const Icon(Icons.person_rounded,
                                                        size: 34, color: Colors.white);
                                                  },
                                                )
                                              : const Icon(Icons.person_rounded,
                                                  size: 34, color: Colors.white),
                                    ),
                                  ),
                                  if (_uploading)
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            value: _uploadProgress > 0
                                                ? _uploadProgress
                                                : null,
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!_uploading)
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppColors.primary,
                                              width: 1.5),
                                        ),
                                        child: const Icon(
                                            Icons.camera_alt_rounded,
                                            size: 11,
                                            color: AppColors.primary),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Edit Profile',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    userName,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: userDocAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 100, height: 13),
                    const SizedBox(height: 8),
                    SkeletonBox(width: double.infinity, height: 52),
                    const SizedBox(height: 20),
                    SkeletonBox(width: 100, height: 13),
                    const SizedBox(height: 8),
                    SkeletonBox(width: double.infinity, height: 52),
                    const SizedBox(height: 20),
                    SkeletonBox(width: 100, height: 13),
                    const SizedBox(height: 8),
                    SkeletonBox(width: double.infinity, height: 52),
                    const SizedBox(height: 20),
                    SkeletonBox(width: 100, height: 13),
                    const SizedBox(height: 8),
                    SkeletonBox(width: double.infinity, height: 52),
                  ],
                ),
              ),
              error: (e, _) => AppErrorState(
                message: 'Unable to load profile. Please try again.',
              ),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              _label('Full Name'),
              _field(_nameCtrl, 'Enter your full name',
                  Icons.person_outline_rounded),
              const SizedBox(height: 16),

              _label('Email Address'),
              _field(_emailCtrl, 'Enter email address', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),

              _label('Date of Birth'),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(1995),
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now(),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(
                            primary: AppColors.primary),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _dobCtrl.text =
                          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                    });
                  }
                },
                child: AbsorbPointer(
                  child: _field(
                      _dobCtrl, 'DD/MM/YYYY', Icons.calendar_today_outlined),
                ),
              ),
              const SizedBox(height: 16),

              _label('Gender'),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _gender,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textHint),
                    items: ['Female', 'Male', 'Other']
                        .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text(g, style: AppTextStyles.bodyLarge)))
                        .toList(),
                    onChanged: (v) => setState(() => _gender = v!),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              _label('Family Members'),
              _FamilyMembersRow(uid: uid),
              const SizedBox(height: 16),

              // Favourite Doctors entry
              _FavouriteDoctorsCard(uid: uid),
              const SizedBox(height: 16),

              // Referral & Rewards entry
              _ReferralEntryCard(uid: uid),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: authState.isLoading ? null : _save,
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppTextStyles.labelLarge),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.textHint, size: 20),
        ),
      );
}

class _FamilyMembersRow extends StatelessWidget {
  final String uid;
  const _FamilyMembersRow({required this.uid});

  static const _colors = [
    Color(0xFFC2185B), Color(0xFF7B1FA2), Color(0xFF1565C0),
    Color(0xFF2E7D32), Color(0xFF00695C), Color(0xFFE65100),
  ];

  @override
  Widget build(BuildContext context) {
    // Use Firestore directly so we always get the latest list
    // regardless of Riverpod auth-state timing.
    final effectiveUid = uid.isNotEmpty
        ? uid
        : FirebaseAuth.instance.currentUser?.uid ?? '';

    return GestureDetector(
      onTap: () => context.push('/profile/family'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: effectiveUid.isEmpty
            ? Row(children: [
                Text('No members added yet', style: AppTextStyles.bodySmall),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textHint),
              ])
            : StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(effectiveUid)
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data() as Map<String, dynamic>?;
                  final raw = data?['familyMembers'];
                  final members = raw is List
                      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
                      : <Map<String, dynamic>>[];

                  return Row(children: [
                    if (members.isEmpty)
                      Expanded(child: Text('No members added yet', style: AppTextStyles.bodySmall))
                    else
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: members.map((m) {
                            final name     = m['name']     as String? ?? '';
                            final relation = m['relation'] as String? ?? '';
                            final color = _colors[name.isNotEmpty ? name.codeUnitAt(0) % _colors.length : 0];
                            return Row(mainAxisSize: MainAxisSize.min, children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: color.withValues(alpha:0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                      fontWeight: FontWeight.w700, color: color),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                relation.isNotEmpty ? relation : name.split(' ').first,
                                style: AppTextStyles.bodySmall,
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textHint),
                  ]);
                },
              ),
      ),
    );
  }
}

// ── Favourite Doctors Card ────────────────────────────────
class _FavouriteDoctorsCard extends StatelessWidget {
  final String uid;
  const _FavouriteDoctorsCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: uid.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('favourite_doctors')
              .snapshots()
          : const Stream.empty(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final count = docs.length;

        return GestureDetector(
          onTap: () => context.push(AppRoutes.favouriteDoctors),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Color(0xFFE53935), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Favourite Doctors',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snap.connectionState == ConnectionState.waiting
                          ? 'Loading...'
                          : count == 0
                              ? 'No favourites saved yet'
                              : count == 1
                                  ? '1 doctor saved'
                                  : '$count doctors saved',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.textHint),
            ]),
          ),
        );
      },
    );
  }
}

// ── Referral Entry Card ───────────────────────────────────
class _ReferralEntryCard extends ConsumerWidget {
  final String uid;
  const _ReferralEntryCard({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(referralStatsProvider);
    final stats = statsAsync.valueOrNull;
    final totalReferrals = stats?['total'] as int? ?? 0;
    final earned = stats?['earned'] as double? ?? 0.0;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.referral),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha:0.07),
              AppColors.secondary.withValues(alpha:0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.card_giftcard_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Referral & Rewards',
                      style: AppTextStyles.labelLarge),
                  const SizedBox(height: 3),
                  statsAsync.isLoading
                      ? Text('Loading...',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary))
                      : Text(
                          totalReferrals == 0
                              ? 'Invite friends and earn rewards'
                              : '$totalReferrals referrals · ₹${earned.toStringAsFixed(0)} earned',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ── Bottom-sheet option tile ──────────────────────────────
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ]),
        ),
      );
}
