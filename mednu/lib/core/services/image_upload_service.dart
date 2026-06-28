import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ImageUploadService {
  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;

  static Future<File?> pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  static Future<File?> pickFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  /// Uploads to `users/{uid}/profile.jpg` and returns the download URL.
  static Future<String> uploadUserProfileImage({
    required File imageFile,
    required String uid,
    void Function(double progress)? onProgress,
  }) =>
      _upload(imageFile, 'users/$uid/profile.jpg', onProgress);

  /// Uploads to `doctors/{uid}/profile.jpg` and returns the download URL.
  static Future<String> uploadDoctorProfileImage({
    required File imageFile,
    required String uid,
    void Function(double progress)? onProgress,
  }) =>
      _upload(imageFile, 'doctors/$uid/profile.jpg', onProgress);

  static Future<String> _upload(
    File file,
    String storagePath,
    void Function(double)? onProgress,
  ) async {
    final ref = _storage.ref().child(storagePath);
    final task = ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    final snapshot = await task;

    // Surface a clear error if the task didn't actually succeed
    // (e.g. Storage rules denied the write without throwing immediately).
    if (snapshot.state != TaskState.success) {
      throw Exception(
        'Upload failed (state: ${snapshot.state}). '
        'Check your Firebase Storage security rules.',
      );
    }

    // Build a permanent, token-free URL. Firebase embeds an access token in
    // getDownloadURL() that can be revoked/invalidated over time. Since the
    // profile image path is public, we drop the token so the stored URL never
    // expires regardless of auth-session changes.
    final signedUrl = await ref.getDownloadURL();
    final uri = Uri.parse(signedUrl);
    return uri.replace(queryParameters: {'alt': 'media'}).toString();
  }

  /// Deletes `users/{uid}/profile.jpg` from Storage. Silently ignores errors.
  static Future<void> deleteUserProfileImage(String uid) async {
    try {
      await _storage.ref().child('users/$uid/profile.jpg').delete();
    } catch (_) {}
  }

  /// Deletes `doctors/{uid}/profile.jpg` from Storage. Silently ignores errors.
  static Future<void> deleteDoctorProfileImage(String uid) async {
    try {
      await _storage.ref().child('doctors/$uid/profile.jpg').delete();
    } catch (_) {}
  }
}
