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
import '../../../core/utils/r.dart';
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
  final _checkupCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
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
    _checkupCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    super.dispose();
  }

  void _populate(Map<String, dynamic>? data) {
    if (_populated || data == null) return;
    _nameCtrl.text = data['name'] as String? ?? '';
    _emailCtrl.text = data['email'] as String? ?? '';
    _dobCtrl.text = data['dob'] as String? ?? '';
    final g = data['gender'] as String? ?? 'Female';
    _gender = ['Female', 'Male', 'Other'].contains(g) ? g : 'Female';
    _checkupCtrl.text = data['lastCheckup'] as String? ?? '';
    _allergiesCtrl.text = data['allergies'] as String? ?? '';
    _conditionsCtrl.text = data['chronicConditions'] as String? ?? '';
    _currentPhotoUrl = data['photoUrl'] as String?;
    _populated = true;
  }

  void _showPhotoOptions() {
    final hasPhoto =
        (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) ||
        _localImage != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 24))),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 12),
              R.p(context, 20), R.p(context, 20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: R.w(context, 40), height: R.h(context, 4),
                margin: EdgeInsets.only(bottom: R.p(context, 20)),
                decoration: BoxDecoration(
                  color: context.appBorder,
                  borderRadius: BorderRadius.circular(R.r(context, 2)),
                ),
              ),
              const Text('Profile Photo',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: R.h(context, 20)),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              SizedBox(height: R.h(context, 12)),
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
                SizedBox(height: R.h(context, 12)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
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
      final storageRef = FirebaseStorage.instance.ref().child('users/$uid/profile.jpg');
      final signedUrl = await storageRef.getDownloadURL();
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
            lastCheckup: _checkupCtrl.text.trim(),
            allergies: _allergiesCtrl.text.trim(),
            chronicConditions: _conditionsCtrl.text.trim(),
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
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 180),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: R.p(context, 8)),
                child: TextButton(
                  onPressed: authState.isLoading ? null : _save,
                  child: authState.isLoading
                      ? SizedBox(
                          width: R.w(context, 18),
                          height: R.h(context, 18),
                          child: const CircularProgressIndicator(
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
                        width: R.w(context, 130),
                        height: R.h(context, 130),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 52),
                                    R.p(context, 20), R.p(context, 16)),
                                child: Row(
                          children: [
                            GestureDetector(
                              onTap: _uploading ? null : _showPhotoOptions,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: R.w(context, 64),
                                    height: R.h(context, 64),
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
                                                  placeholder: (_, __) => Icon(
                                                      Icons.person_rounded,
                                                      size: R.w(context, 34),
                                                      color: Colors.white),
                                                  errorWidget: (_, __, ___) {
                                                    // Old signed URL expired — refresh to permanent URL
                                                    final uid = ref.read(authProvider).user?.uid;
                                                    if (uid != null) _refreshPhotoUrl(uid);
                                                    return Icon(Icons.person_rounded,
                                                        size: R.w(context, 34), color: Colors.white);
                                                  },
                                                )
                                              : Icon(Icons.person_rounded,
                                                  size: R.w(context, 34), color: Colors.white),
                                    ),
                                  ),
                                  if (_uploading)
                                    Container(
                                      width: R.w(context, 64),
                                      height: R.h(context, 64),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: R.w(context, 28),
                                          height: R.h(context, 28),
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
                                        width: R.w(context, 22),
                                        height: R.h(context, 22),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppColors.primary,
                                              width: 1.5),
                                        ),
                                        child: Icon(
                                            Icons.camera_alt_rounded,
                                            size: R.w(context, 11),
                                            color: AppColors.primary),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: R.w(context, 14)),
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
                                  SizedBox(height: R.h(context, 2)),
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
                          );
                        },
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
                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 24),
                    R.p(context, 20), R.p(context, 40)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: R.w(context, 100), height: R.h(context, 13)),
                    SizedBox(height: R.h(context, 8)),
                    SkeletonBox(width: double.infinity, height: R.h(context, 52)),
                    SizedBox(height: R.h(context, 20)),
                    SkeletonBox(width: R.w(context, 100), height: R.h(context, 13)),
                    SizedBox(height: R.h(context, 8)),
                    SkeletonBox(width: double.infinity, height: R.h(context, 52)),
                    SizedBox(height: R.h(context, 20)),
                    SkeletonBox(width: R.w(context, 100), height: R.h(context, 13)),
                    SizedBox(height: R.h(context, 8)),
                    SkeletonBox(width: double.infinity, height: R.h(context, 52)),
                    SizedBox(height: R.h(context, 20)),
                    SkeletonBox(width: R.w(context, 100), height: R.h(context, 13)),
                    SizedBox(height: R.h(context, 8)),
                    SkeletonBox(width: double.infinity, height: R.h(context, 52)),
                  ],
                ),
              ),
              error: (e, _) => AppErrorState(
                message: 'Unable to load profile. Please try again.',
              ),
              data: (_) => Padding(
                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 24),
                    R.p(context, 20), R.p(context, 40)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              _label('Full Name'),
              _field(_nameCtrl, 'Enter your full name',
                  Icons.person_outline_rounded),
              SizedBox(height: R.h(context, 16)),

              _label('Email Address'),
              _field(_emailCtrl, 'Enter email address', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              SizedBox(height: R.h(context, 16)),

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
              SizedBox(height: R.h(context, 16)),

              _label('Gender'),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 4)),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                  border: Border.all(color: context.appBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _gender,
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: context.appTextHint),
                    items: ['Female', 'Male', 'Other']
                        .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text(g, style: AppTextStyles.bodyLarge)))
                        .toList(),
                    onChanged: (v) => setState(() => _gender = v!),
                  ),
                ),
              ),
              SizedBox(height: R.h(context, 16)),

              _label('Last Checkup'),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
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
                      _checkupCtrl.text =
                          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                    });
                  }
                },
                child: AbsorbPointer(
                  child: _field(_checkupCtrl, 'DD/MM/YYYY', Icons.calendar_today_outlined),
                ),
              ),
              SizedBox(height: R.h(context, 16)),

              _label('Allergies'),
              _field(_allergiesCtrl, 'Enter allergies (if any)', Icons.warning_amber_rounded),
              SizedBox(height: R.h(context, 16)),

              _label('Chronic Conditions'),
              _field(_conditionsCtrl, 'Enter chronic conditions (if any)', Icons.monitor_heart_outlined),
              SizedBox(height: R.h(context, 32)),

              _label('Family Members'),
              _FamilyMembersRow(uid: uid),
              SizedBox(height: R.h(context, 16)),

              // Favourite Doctors entry
              _FavouriteDoctorsCard(uid: uid),
              SizedBox(height: R.h(context, 16)),

              // Referral & Rewards entry
              _ReferralEntryCard(uid: uid),
              SizedBox(height: R.h(context, 16)),
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
        padding: EdgeInsets.only(bottom: R.p(context, 8)),
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
          prefixIcon: Icon(icon, color: context.appTextHint, size: R.w(context, 20)),
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
        padding: EdgeInsets.all(R.p(context, 14)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 14)),
          border: Border.all(color: context.appBorder),
        ),
        child: effectiveUid.isEmpty
            ? Row(children: [
                Text('No members added yet', style: AppTextStyles.bodySmall),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded, size: R.w(context, 14), color: context.appTextHint),
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
                                radius: R.w(context, 14),
                                backgroundColor: color.withValues(alpha:0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                      fontWeight: FontWeight.w700, color: color),
                                ),
                              ),
                              SizedBox(width: R.w(context, 6)),
                              Text(
                                relation.isNotEmpty ? relation : name.split(' ').first,
                                style: AppTextStyles.bodySmall,
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    SizedBox(width: R.w(context, 8)),
                    Icon(Icons.arrow_forward_ios_rounded, size: R.w(context, 14), color: context.appTextHint),
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
            padding: EdgeInsets.all(R.p(context, 14)),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(R.r(context, 14)),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(children: [
              Container(
                width: R.w(context, 40),
                height: R.h(context, 40),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(R.r(context, 10)),
                ),
                child: Icon(Icons.favorite_rounded,
                    color: const Color(0xFFE53935), size: R.w(context, 20)),
              ),
              SizedBox(width: R.w(context, 12)),
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
                    SizedBox(height: R.h(context, 2)),
                    Text(
                      snap.connectionState == ConnectionState.waiting
                          ? 'Loading...'
                          : count == 0
                              ? 'No favourites saved yet'
                              : count == 1
                                  ? '1 doctor saved'
                                  : '$count doctors saved',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 8), vertical: R.p(context, 3)),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(R.r(context, 20)),
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
              SizedBox(width: R.w(context, 8)),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: R.w(context, 14), color: context.appTextHint),
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
        padding: EdgeInsets.all(R.p(context, 16)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha:0.07),
              AppColors.secondary.withValues(alpha:0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: R.w(context, 46), height: R.h(context, 46),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.card_giftcard_rounded,
                  color: Colors.white, size: R.w(context, 22)),
            ),
            SizedBox(width: R.w(context, 14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Referral & Rewards',
                      style: AppTextStyles.labelLarge),
                  SizedBox(height: R.h(context, 3)),
                  statsAsync.isLoading
                      ? Text('Loading...',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: context.appTextSecondary))
                      : Text(
                          totalReferrals == 0
                              ? 'Invite friends and earn rewards'
                              : '$totalReferrals referrals · ₹${earned.toStringAsFixed(0)} earned',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: context.appTextSecondary),
                        ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: R.w(context, 14), color: context.appTextHint),
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
          padding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 14)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(R.r(context, 14)),
          ),
          child: Row(children: [
            Container(
              width: R.w(context, 40),
              height: R.h(context, 40),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(R.r(context, 10)),
              ),
              child: Icon(icon, color: color, size: R.w(context, 20)),
            ),
            SizedBox(width: R.w(context, 14)),
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
