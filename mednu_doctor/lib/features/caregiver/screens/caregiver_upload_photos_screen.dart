import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_visit_service.dart';
import '../widgets/photo_grid.dart';

const _allowedPhotoTypes = ['jpg', 'jpeg', 'png', 'heic'];
const _maxPhotoSizeMb = 10;

/// Visit-progress photos — a responsive grid with an "Add Photo" tile
/// (camera or gallery). Each pick is validated (size/type) before it ever
/// touches the network, then uploaded to Firebase Storage under
/// `visit_photos/{visitId}/...` with its download URL appended to the
/// visit's `photoUrls` array, so the grid renders network images (not local
/// file paths) and the patient can see the same files.
///
/// Stateful (rather than the previous stateless build) so an in-flight or
/// failed upload has somewhere to live: a picked file that fails must stay
/// visible with a retry action, not silently vanish because nothing besides
/// the confirmed `photoUrls` array was ever tracked.
class CaregiverUploadPhotosScreen extends ConsumerStatefulWidget {
  final String visitId;
  const CaregiverUploadPhotosScreen({super.key, required this.visitId});

  @override
  ConsumerState<CaregiverUploadPhotosScreen> createState() => _CaregiverUploadPhotosScreenState();
}

class _PendingUpload {
  final String localPath;
  bool isFailed = false;
  _PendingUpload(this.localPath);
}

class _CaregiverUploadPhotosScreenState extends ConsumerState<CaregiverUploadPhotosScreen> {
  final List<_PendingUpload> _pending = [];

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file == null) return;
    if (!mounted) return;

    final ext = file.path.split('.').last;
    final typeError = Validators.fileType(ext, _allowedPhotoTypes);
    if (typeError != null) {
      FeedbackService.showError(context, typeError);
      return;
    }
    final bytes = await File(file.path).length();
    if (!mounted) return;
    final sizeError = Validators.fileSize(bytes, maxMb: _maxPhotoSizeMb);
    if (sizeError != null) {
      FeedbackService.showError(context, sizeError);
      return;
    }

    final pending = _PendingUpload(file.path);
    setState(() => _pending.add(pending));
    await _upload(pending);
  }

  Future<void> _upload(_PendingUpload pending) async {
    setState(() => pending.isFailed = false);
    try {
      await CaregiverVisitService.uploadPhoto(visitId: widget.visitId, file: File(pending.localPath));
      if (!mounted) return;
      setState(() => _pending.remove(pending));
      FeedbackService.showSuccess(context, 'Photo added');
    } catch (e) {
      if (!mounted) return;
      setState(() => pending.isFailed = true);
      FeedbackService.showError(context, Validators.friendlyError(e));
    }
  }

  void _cancelPending(_PendingUpload pending) {
    setState(() => _pending.remove(pending));
  }

  Future<void> _remove(String url) async {
    try {
      await CaregiverVisitService.removePhoto(widget.visitId, url);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, Validators.friendlyError(e));
    }
  }

  Future<void> _showSourceSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pick(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pick(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visit = ref.watch(visitByIdProvider(widget.visitId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Visit Photos',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(icon: Icons.search_off_rounded, title: 'Visit not found', message: 'This visit may have been reassigned.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Attach photos documenting the visit — wound care, mobility aids in use, or the prepared care space.',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'JPG, PNG or HEIC · up to ${_maxPhotoSizeMb}MB each',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 16),
                PhotoGrid(
                  photoPaths: visit.photoPaths,
                  pendingPhotos: [
                    for (final p in _pending)
                      PendingPhoto(
                        localPath: p.localPath,
                        isFailed: p.isFailed,
                        onRetry: () => _upload(p),
                        onCancel: () => _cancelPending(p),
                      ),
                  ],
                  onAdd: _showSourceSheet,
                  onRemove: _remove,
                ),
              ],
            ),
    );
  }
}
