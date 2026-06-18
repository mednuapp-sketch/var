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

  /// Uploads to `doctors/{uid}/profile.jpg` and returns the download URL.
  static Future<String> uploadDoctorProfileImage({
    required File imageFile,
    required String uid,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref().child('doctors/$uid/profile.jpg');
    final task = ref.putFile(
      imageFile,
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

    if (snapshot.state != TaskState.success) {
      throw Exception(
        'Upload failed (state: ${snapshot.state}). '
        'Check your Firebase Storage security rules.',
      );
    }

    return await ref.getDownloadURL();
  }

  /// Picks a document image from gallery (higher quality for readability).
  static Future<File?> pickDocument() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  /// Picks an image from camera (for photographing physical documents).
  static Future<File?> pickDocumentFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  /// Uploads to `doctors/{uid}/docs/{docType}.jpg` and returns the download URL.
  static Future<String> uploadDoctorDocument({
    required File file,
    required String uid,
    required String docType,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref().child('doctors/$uid/docs/$docType.jpg');
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
    if (snapshot.state != TaskState.success) {
      throw Exception('Upload failed for $docType. Check Storage rules.');
    }
    return await ref.getDownloadURL();
  }

  /// Deletes `doctors/{uid}/profile.jpg` from Storage. Silently ignores errors.
  static Future<void> deleteDoctorProfileImage(String uid) async {
    try {
      await _storage.ref().child('doctors/$uid/profile.jpg').delete();
    } catch (_) {}
  }
}
