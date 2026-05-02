import 'package:flutter_test/flutter_test.dart';
import 'package:insta_grab/services/settings_service.dart';

void main() {
  group('ImageFormat enum', () {
    test('PNG has correct label and extension', () {
      expect(ImageFormat.png.label, 'PNG');
      expect(ImageFormat.png.extension, 'png');
    });

    test('JPEG has correct label and extension', () {
      expect(ImageFormat.jpeg.label, 'JPEG');
      expect(ImageFormat.jpeg.extension, 'jpg');
    });
  });
}
