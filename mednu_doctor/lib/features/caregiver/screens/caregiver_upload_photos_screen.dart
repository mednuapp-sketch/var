import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_visit_service.dart';
import '../widgets/photo_grid.dart';

/// Visit-progress photos — a responsive grid with an "Add Photo" tile
/// (camera or gallery). Each pick is uploaded to Firebase Storage under
/// `visit_photos/{visitId}/...` and its download URL appended to the visit's
/// `photoUrls` array, so the grid renders network images (not local file
/// paths) and the patient can see the same files.
class CaregiverUploadPhotosScreen extends ConsumerWidget {
  final String visitId;
  const CaregiverUploadPhotosScreen({super.key, required this.visitId});

  Future<void> _pick(BuildContext context, WidgetRef ref, ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (file == null) return;
    if (!context.mounted) return;
    FeedbackService.show(context, 'Uploading photo…', type: FeedbackType.info);
    try {
      await CaregiverVisitService.uploadPhoto(visitId: visitId, file: File(file.path));
      if (context.mounted) FeedbackService.showSuccess(context, 'Photo added');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't upload that photo. Please try again.");
      }
    }
  }

  Future<void> _remove(BuildContext context, String url) async {
    try {
      await CaregiverVisitService.removePhoto(visitId, url);
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't remove that photo. Please try again.");
      }
    }
  }

  Future<void> _showSourceSheet(BuildContext context, WidgetRef ref) async {
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
                  _pick(context, ref, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pick(context, ref, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitByIdProvider(visitId));

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
                const SizedBox(height: 16),
                PhotoGrid(
                  photoPaths: visit.photoPaths,
                  onAdd: () => _showSourceSheet(context, ref),
                  onRemove: (url) => _remove(context, url),
                ),
              ],
            ),
    );
  }
}
