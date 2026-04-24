import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service for downloading, resizing, and saving images.
///
/// All image manipulation uses the `image` package for cross-platform
/// compatibility (no native dependencies).
class ImageService {
  /// Downloads an image from a URL and returns the raw bytes.
  ///
  /// Uses appropriate headers to avoid being blocked by CDNs.
  /// Throws [ImageDownloadException] on failure.
  static Future<Uint8List> downloadImage(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/*,*/*;q=0.8',
          'Referer': 'https://www.instagram.com/',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw ImageDownloadException(
          'Download failed with status ${response.statusCode}',
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw ImageDownloadException('Downloaded image is empty');
      }

      return response.bodyBytes;
    } catch (e) {
      if (e is ImageDownloadException) rethrow;
      throw ImageDownloadException('Failed to download image: $e');
    }
  }

  /// Decodes image bytes into an [img.Image] for manipulation.
  ///
  /// Supports JPEG, PNG, WebP, and other formats handled by the `image` package.
  static img.Image? decodeImage(Uint8List bytes) {
    return img.decodeImage(bytes);
  }

  /// Resizes an image to the specified dimensions.
  ///
  /// If [maintainAspect] is true, the image is resized to fit within
  /// the target dimensions while preserving aspect ratio.
  /// Uses Lanczos3 interpolation for high-quality downscaling.
  static img.Image resize(
    img.Image image, {
    required int width,
    required int height,
    bool maintainAspect = true,
  }) {
    if (maintainAspect) {
      final aspectRatio = image.width / image.height;
      final targetRatio = width / height;

      if (aspectRatio > targetRatio) {
        // Width-constrained
        height = (width / aspectRatio).round();
      } else {
        // Height-constrained
        width = (height * aspectRatio).round();
      }
    }

    return img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
  }

  /// Crops an image to the specified rectangle.
  ///
  /// Coordinates are in pixel space relative to the source image.
  static img.Image crop(
    img.Image image, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  /// Encodes an image to PNG bytes.
  static Uint8List encodePng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Encodes an image to JPEG bytes with the specified quality (0-100).
  static Uint8List encodeJpeg(img.Image image, {int quality = 90}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  /// Returns the platform-appropriate downloads/output directory.
  static Future<Directory> getOutputDirectory() async {
    if (Platform.isAndroid) {
      // Use external storage downloads folder
      final dir = Directory('/storage/emulated/0/Download/InstaGrab');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/home';
      final dir = Directory(p.join(home, 'Pictures', 'InstaGrab'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'InstaGrab'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  /// Saves image bytes to a file and returns the file path.
  ///
  /// [filename] should include the extension (.png, .jpg).
  static Future<String> saveImage(
    Uint8List bytes, {
    required String filename,
  }) async {
    final dir = await getOutputDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Generates a timestamped filename for saving.
  static String generateFilename({String prefix = 'insta', String ext = 'png'}) {
    final now = DateTime.now();
    final stamp = '${now.year}${_pad(now.month)}${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return '${prefix}_$stamp.$ext';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// Exception thrown when image download fails.
class ImageDownloadException implements Exception {
  /// Human-readable error message.
  final String message;

  const ImageDownloadException(this.message);

  @override
  String toString() => 'ImageDownloadException: $message';
}
