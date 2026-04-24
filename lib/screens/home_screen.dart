import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/instagram_service.dart';
import '../services/image_service.dart';
import 'editor_screen.dart';

/// Home screen with URL input for Instagram image extraction.
///
/// Accepts Instagram share URLs via text input or clipboard paste,
/// extracts image URLs from the post, downloads them, and navigates
/// to the editor screen for crop/resize operations.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Pastes clipboard content into the URL field.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlController.text = data.text!;
      _urlController.selection = TextSelection.fromPosition(
        TextPosition(offset: _urlController.text.length),
      );
    }
  }

  /// Main extraction flow: validate URL → extract image URLs → download → edit.
  Future<void> _processUrl() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter an Instagram URL');
      return;
    }

    final normalized = InstagramService.normalizeUrl(input);
    if (normalized == null) {
      setState(() => _error = 'Not a valid Instagram post URL');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = 'Extracting image URLs...';
    });

    try {
      // Step 1: Extract image URLs from the post
      final imageUrls = await InstagramService.extractImageUrls(input);

      if (imageUrls.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No images found in this post';
        });
        return;
      }

      setState(() => _status = 'Downloading image (1/${imageUrls.length})...');

      // Step 2: Download all images
      final downloadedImages = <DownloadedImage>[];

      for (var i = 0; i < imageUrls.length; i++) {
        setState(() {
          _status = 'Downloading image (${i + 1}/${imageUrls.length})...';
        });

        try {
          final bytes = await ImageService.downloadImage(imageUrls[i]);
          downloadedImages.add(DownloadedImage(
            url: imageUrls[i],
            bytes: bytes,
          ));
        } catch (e) {
          // Skip images that fail to download, continue with others
          print('Failed to download image ${i + 1}: $e');
        }
      }

      if (downloadedImages.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Failed to download any images from this post';
        });
        return;
      }

      setState(() => _loading = false);

      // Step 3: Navigate to editor
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditorScreen(images: downloadedImages),
          ),
        );
      }
    } on InstagramExtractionException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('InstaGrab'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App icon / header
                Icon(
                  Icons.photo_library_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Grab Instagram Images',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste an Instagram share URL to download, crop, and resize images.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // URL input
                TextField(
                  controller: _urlController,
                  focusNode: _focusNode,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    hintText: 'https://www.instagram.com/p/...',
                    labelText: 'Instagram URL',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Paste from clipboard',
                      onPressed: _loading ? null : _pasteFromClipboard,
                    ),
                    errorText: _error,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _processUrl(),
                ),
                const SizedBox(height: 16),

                // Grab button
                FilledButton.icon(
                  onPressed: _loading ? null : _processUrl,
                  icon: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(_loading ? (_status ?? 'Processing...') : 'Grab Images'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                ),

                const SizedBox(height: 24),

                // Usage hints
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to use',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _hintRow(Icons.share, 'Open Instagram → tap Share → Copy Link'),
                        const SizedBox(height: 4),
                        _hintRow(Icons.paste, 'Paste the link above'),
                        const SizedBox(height: 4),
                        _hintRow(Icons.crop, 'Crop and resize to your needs'),
                        const SizedBox(height: 4),
                        _hintRow(Icons.save_alt, 'Save to your device'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Holds a downloaded image's source URL and raw bytes.
class DownloadedImage {
  /// The CDN URL the image was fetched from.
  final String url;

  /// Raw image bytes (JPEG/PNG/WebP as received).
  final Uint8List bytes;

  const DownloadedImage({required this.url, required this.bytes});
}
