// Quick CLI smoke test: `dart run tool/smoke_extract.dart <instagram-url>`.
// Intentionally not under test/ so `flutter test` ignores it.
import 'package:insta_grab/services/instagram_service.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/smoke_extract.dart <instagram-url>');
    return;
  }
  try {
    final urls = await InstagramService.extractImageUrls(args.first);
    print('Found ${urls.length} image(s):');
    for (var i = 0; i < urls.length; i++) {
      print('  [$i] ${urls[i]}');
    }
  } on InstagramExtractionException catch (e) {
    print('EXTRACTION FAILED: ${e.message}');
  }
}
