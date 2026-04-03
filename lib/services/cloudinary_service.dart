// Aanchal — Cloudinary Service
//
// Uploads images to Cloudinary using the unsigned upload REST API.
// No SDK required — uses the `http` package already in pubspec.yaml.
//
// ─── How to set up ──────────────────────────────────────────────────
// 1. Sign up at https://cloudinary.com (free tier is plenty)
// 2. Go to Settings → Upload → Upload presets
// 3. Create a NEW preset → set "Signing mode" to UNSIGNED
// 4. Note the preset name and your cloud name from the dashboard
// 5. Replace the two constants below:
//      _cloudName    = your cloud name  (e.g. "dxyz1234")
//      _uploadPreset = your preset name (e.g. "aanchal_unsigned")
// ────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  // ──────────────────────────────────────────────────────────────────
  // ⚙️  CONFIGURE THESE TWO VALUES (can be overridden with --dart-define)
  static const String _cloudName = String.fromEnvironment(
    'AANCHAL_CLOUDINARY_CLOUD_NAME',
    defaultValue: 'dfslawsnm',
  );
  static const String _uploadPreset = String.fromEnvironment(
    'AANCHAL_CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'aanchal_unsigned',
  );
  // ──────────────────────────────────────────────────────────────────

  /// Upload a [file] to Cloudinary and return the secure HTTPS URL.
  ///
  /// Pass [folder] to organise uploads (e.g. 'profile_photos', 'posts').
  /// Throws an [Exception] if the upload fails.
  Future<String> uploadImage(
    File file, {
    String folder = 'aanchal',
    String? publicId,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

    if (publicId != null) {
      request.fields['public_id'] = publicId;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Cloudinary upload failed [${response.statusCode}]: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = json['secure_url'] as String?;
    if (secureUrl == null) {
      throw Exception('Cloudinary response missing secure_url: ${response.body}');
    }
    return secureUrl;
  }

  /// Convenience wrapper: upload a profile photo and return its URL.
  /// Uses the user's uid as the public_id so repeated uploads overwrite
  /// the same asset (no orphaned files accumulate).
  Future<String> uploadProfilePhoto(File file, String uid) {
    return uploadImage(
      file,
      folder: 'aanchal/profile_photos',
      publicId: uid,
    );
  }

  /// Convenience wrapper: upload a community post image.
  Future<String> uploadPostImage(File file, String uid) {
    return uploadImage(
      file,
      folder: 'aanchal/posts',
      publicId: '${uid}_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
