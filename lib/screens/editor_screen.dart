import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image/image.dart' as img;
import '../services/image_service.dart';
import 'home_screen.dart';

/// Image editor screen with cropping and resizing capabilities.
///
/// For carousel posts, displays a horizontal thumbnail strip to switch
/// between images. The active image can be cropped interactively or
/// resized to specific dimensions.
class EditorScreen extends StatefulWidget {
  /// List of downloaded images from the Instagram post.
  final List<DownloadedImage> images;

  const EditorScreen({super.key, required this.images});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  int _currentIndex = 0;
  final _cropController = CropController();
  bool _isCropping = false;
  bool _isSaving = false;
  Uint8List? _croppedBytes;
  _EditorMode _mode = _EditorMode.crop;

  // Resize controls
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  bool _maintainAspect = true;
  double? _originalAspect;

  // Crop aspect ratio
  double? _cropAspectRatio;

  Uint8List get _activeBytes => _croppedBytes ?? widget.images[_currentIndex].bytes;

  @override
  void initState() {
    super.initState();
    _updateImageInfo();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  /// Updates dimension fields when switching images.
  void _updateImageInfo() {
    final decoded = img.decodeImage(_activeBytes);
    if (decoded != null) {
      _widthController.text = decoded.width.toString();
      _heightController.text = decoded.height.toString();
      _originalAspect = decoded.width / decoded.height;
    }
  }

  /// Switches the active image in a carousel.
  void _selectImage(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _croppedBytes = null;
      _mode = _EditorMode.crop;
    });
    _updateImageInfo();
  }

  /// Executes the crop operation on the current image.
  void _performCrop() {
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  /// Called by CropController when crop completes.
  void _onCropped(Uint8List cropped) {
    setState(() {
      _croppedBytes = cropped;
      _isCropping = false;
    });
    _updateImageInfo();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image cropped'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Resets crop, returning to the original downloaded image.
  void _resetCrop() {
    setState(() {
      _croppedBytes = null;
    });
    _updateImageInfo();
  }

  /// Resizes the image to the dimensions specified in the text fields.
  void _performResize() {
    final w = int.tryParse(_widthController.text);
    final h = int.tryParse(_heightController.text);

    if (w == null || h == null || w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid width and height')),
      );
      return;
    }

    if (w > 10000 || h > 10000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum dimension is 10000px')),
      );
      return;
    }

    final decoded = img.decodeImage(_activeBytes);
    if (decoded == null) return;

    final resized = ImageService.resize(
      decoded,
      width: w,
      height: h,
      maintainAspect: _maintainAspect,
    );

    setState(() {
      _croppedBytes = ImageService.encodePng(resized);
    });
    _updateImageInfo();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Resized to ${resized.width}×${resized.height}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Handles width field changes when aspect ratio is locked.
  void _onWidthChanged(String value) {
    if (!_maintainAspect || _originalAspect == null) return;
    final w = int.tryParse(value);
    if (w != null && w > 0) {
      _heightController.text = (w / _originalAspect!).round().toString();
    }
  }

  /// Handles height field changes when aspect ratio is locked.
  void _onHeightChanged(String value) {
    if (!_maintainAspect || _originalAspect == null) return;
    final h = int.tryParse(value);
    if (h != null && h > 0) {
      _widthController.text = (h * _originalAspect!).round().toString();
    }
  }

  /// Saves the current image (cropped/resized) to the device.
  Future<void> _saveImage({String format = 'png'}) async {
    setState(() => _isSaving = true);

    try {
      final decoded = img.decodeImage(_activeBytes);
      if (decoded == null) throw Exception('Failed to decode image');

      final filename = ImageService.generateFilename(ext: format);
      final bytes = format == 'jpg'
          ? ImageService.encodeJpeg(decoded, quality: 95)
          : ImageService.encodePng(decoded);

      final path = await ImageService.saveImage(bytes, filename: filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $path'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMultiple = widget.images.length > 1;
    final hasCrop = _croppedBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasMultiple
              ? 'Edit Image (${_currentIndex + 1}/${widget.images.length})'
              : 'Edit Image',
        ),
        actions: [
          if (hasCrop)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Reset to original',
              onPressed: _resetCrop,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Save',
            enabled: !_isSaving,
            onSelected: (format) => _saveImage(format: format),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'png', child: Text('Save as PNG')),
              const PopupMenuItem(value: 'jpg', child: Text('Save as JPEG')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Image carousel thumbnails
          if (hasMultiple) _buildThumbnailStrip(theme),

          // Mode selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_EditorMode>(
              segments: const [
                ButtonSegment(
                  value: _EditorMode.crop,
                  icon: Icon(Icons.crop),
                  label: Text('Crop'),
                ),
                ButtonSegment(
                  value: _EditorMode.resize,
                  icon: Icon(Icons.photo_size_select_large),
                  label: Text('Resize'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (modes) {
                setState(() => _mode = modes.first);
              },
            ),
          ),

          // Main editor area
          Expanded(
            child: _mode == _EditorMode.crop
                ? _buildCropView(theme)
                : _buildResizeView(theme),
          ),
        ],
      ),
    );
  }

  /// Builds the horizontal thumbnail strip for carousel posts.
  Widget _buildThumbnailStrip(ThemeData theme) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.images.length,
        itemBuilder: (_, index) {
          final isActive = index == _currentIndex;
          return GestureDetector(
            onTap: () => _selectImage(index),
            child: Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withAlpha(80),
                  width: isActive ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  widget.images[index].bytes,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the interactive crop view using crop_your_image.
  Widget _buildCropView(ThemeData theme) {
    return Column(
      children: [
        // Aspect ratio presets
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _aspectChip('Free', null),
                _aspectChip('1:1', 1.0),
                _aspectChip('4:5', 4 / 5),
                _aspectChip('16:9', 16 / 9),
                _aspectChip('9:16', 9 / 16),
                _aspectChip('4:3', 4 / 3),
                _aspectChip('3:2', 3 / 2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Crop area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Crop(
              key: ValueKey('$_currentIndex-$_cropAspectRatio-${_croppedBytes?.length}'),
              controller: _cropController,
              image: _activeBytes,
              aspectRatio: _cropAspectRatio,
              withCircleUi: false,
              onCropped: _onCropped,
              initialSize: 0.8,
              maskColor: Colors.black.withAlpha(180),
              baseColor: theme.colorScheme.surface,
              cornerDotBuilder: (size, edgeAlignment) => DotControl(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),

        // Crop action button
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isCropping ? null : _performCrop,
            icon: _isCropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.crop),
            label: Text(_isCropping ? 'Cropping...' : 'Apply Crop'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds an aspect ratio chip for the crop preset row.
  Widget _aspectChip(String label, double? ratio) {
    final isSelected = _cropAspectRatio == ratio;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _cropAspectRatio = ratio);
        },
      ),
    );
  }

  /// Builds the resize controls view.
  Widget _buildResizeView(ThemeData theme) {
    return Column(
      children: [
        // Image preview
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Image.memory(
                _activeBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // Resize controls
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          decoration: const InputDecoration(
                            labelText: 'Width',
                            suffixText: 'px',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: _onWidthChanged,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: IconButton(
                          icon: Icon(
                            _maintainAspect ? Icons.link : Icons.link_off,
                            color: _maintainAspect
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _maintainAspect
                              ? 'Unlock aspect ratio'
                              : 'Lock aspect ratio',
                          onPressed: () {
                            setState(() {
                              _maintainAspect = !_maintainAspect;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          decoration: const InputDecoration(
                            labelText: 'Height',
                            suffixText: 'px',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: _onHeightChanged,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Quick resize presets
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _resizePresetChip('1080×1080', 1080, 1080),
                        _resizePresetChip('1080×1350', 1080, 1350),
                        _resizePresetChip('1920×1080', 1920, 1080),
                        _resizePresetChip('800×800', 800, 800),
                        _resizePresetChip('500×500', 500, 500),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  FilledButton.icon(
                    onPressed: _performResize,
                    icon: const Icon(Icons.photo_size_select_large),
                    label: const Text('Apply Resize'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds a quick-resize preset chip.
  Widget _resizePresetChip(String label, int w, int h) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label),
        onPressed: () {
          _widthController.text = w.toString();
          _heightController.text = h.toString();
          _maintainAspect = false;
          _performResize();
        },
      ),
    );
  }
}

enum _EditorMode { crop, resize }
