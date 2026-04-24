import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// One entry in the on-disk image library.
///
/// Represents an image we grabbed from Instagram, persisted to disk with
/// enough metadata to show in the strip and info pane.
class LibraryImage {
  /// Stable identifier used as the on-disk filename stem.
  final String id;

  /// Instagram post URL this image was extracted from.
  final String sourceUrl;

  /// Instagram shortcode (the `DXfEDOzDZjz` in /p/DXfEDOzDZjz/).
  final String shortcode;

  /// Position within a carousel (0-based); 0 for single-image posts.
  final int carouselIndex;

  /// When this image was downloaded into the library.
  final DateTime grabbedAt;

  final int width;
  final int height;

  /// Size of the original bytes on disk (for display only).
  final int fileSize;

  /// On-disk filename within the library directory.
  final String filename;

  const LibraryImage({
    required this.id,
    required this.sourceUrl,
    required this.shortcode,
    required this.carouselIndex,
    required this.grabbedAt,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.filename,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceUrl': sourceUrl,
        'shortcode': shortcode,
        'carouselIndex': carouselIndex,
        'grabbedAt': grabbedAt.toIso8601String(),
        'width': width,
        'height': height,
        'fileSize': fileSize,
        'filename': filename,
      };

  factory LibraryImage.fromJson(Map<String, dynamic> j) => LibraryImage(
        id: j['id'] as String,
        sourceUrl: j['sourceUrl'] as String,
        shortcode: j['shortcode'] as String,
        carouselIndex: j['carouselIndex'] as int,
        grabbedAt: DateTime.parse(j['grabbedAt'] as String),
        width: j['width'] as int,
        height: j['height'] as int,
        fileSize: j['fileSize'] as int,
        filename: j['filename'] as String,
      );
}

/// Persistent library of grabbed images.
///
/// Storage layout:
///   ~/.local/share/InstaGrab/library/
///     index.json              — list of [LibraryImage]
///     <shortcode>_<i>.<ext>   — raw bytes for each entry
///
/// Edits to a library image are exported elsewhere (see settings save path);
/// the library itself holds only originals and is never mutated after an
/// image is added (aside from delete).
class LibraryService {
  static Directory get _libraryDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return Directory(p.join(home, '.local', 'share', 'InstaGrab', 'library'));
  }

  static File get _indexFile => File(p.join(_libraryDir.path, 'index.json'));

  /// Returns all library entries, newest-first.
  static Future<List<LibraryImage>> list() async {
    if (!await _indexFile.exists()) return const [];
    final raw = await _indexFile.readAsString();
    if (raw.isEmpty) return const [];
    final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final items = decoded.map(LibraryImage.fromJson).toList();
    items.sort((a, b) => b.grabbedAt.compareTo(a.grabbedAt));
    return items;
  }

  /// Adds one image to the library and returns the new [LibraryImage].
  static Future<LibraryImage> add({
    required Uint8List bytes,
    required String sourceUrl,
    required String shortcode,
    required int carouselIndex,
  }) async {
    await _libraryDir.create(recursive: true);

    final decoded = img.decodeImage(bytes);
    final width = decoded?.width ?? 0;
    final height = decoded?.height ?? 0;

    // Filename is deterministic per (shortcode, index) so re-grabbing the
    // same post idempotently overwrites. The library index is deduped below.
    final filename = '${shortcode}_$carouselIndex.jpg';
    final file = File(p.join(_libraryDir.path, filename));
    await file.writeAsBytes(bytes);

    final entry = LibraryImage(
      id: '${shortcode}_$carouselIndex',
      sourceUrl: sourceUrl,
      shortcode: shortcode,
      carouselIndex: carouselIndex,
      grabbedAt: DateTime.now(),
      width: width,
      height: height,
      fileSize: bytes.length,
      filename: filename,
    );

    final existing = await list();
    final deduped = existing.where((e) => e.id != entry.id).toList();
    deduped.insert(0, entry);
    await _writeIndex(deduped);
    return entry;
  }

  /// Reads the original bytes for a library image.
  static Future<Uint8List> readBytes(LibraryImage entry) async {
    final file = File(p.join(_libraryDir.path, entry.filename));
    return file.readAsBytes();
  }

  /// Removes an entry from the index and deletes its on-disk file.
  static Future<void> delete(LibraryImage entry) async {
    final file = File(p.join(_libraryDir.path, entry.filename));
    if (await file.exists()) await file.delete();
    final items = await list();
    items.removeWhere((e) => e.id == entry.id);
    await _writeIndex(items);
  }

  static Future<void> _writeIndex(List<LibraryImage> items) async {
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    await tmp.rename(_indexFile.path);
  }
}
