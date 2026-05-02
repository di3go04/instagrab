import 'package:flutter_test/flutter_test.dart';
import 'package:insta_grab/services/image_service.dart';

void main() {
  group('ImageService.generateFilename', () {
    test('default prefix and extension produce expected format', () {
      final filename = ImageService.generateFilename();
      expect(filename, matches(RegExp(r'^insta_\d{8}_\d{6}\.png$')));
    });

    test('custom prefix and extension are respected', () {
      final filename =
          ImageService.generateFilename(prefix: 'test', ext: 'jpg');
      expect(filename, matches(RegExp(r'^test_\d{8}_\d{6}\.jpg$')));
    });
  });
}
