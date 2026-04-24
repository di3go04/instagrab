import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

/// Service for extracting image URLs from Instagram share links.
///
/// Uses multiple strategies to extract images:
/// 1. HTML meta tag parsing (og:image)
/// 2. JSON-LD structured data extraction
/// 3. Embedded shared data parsing
class InstagramService {
  /// User-Agent mimicking a mobile browser for better extraction results.
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Desktop user agent as fallback.
  static const _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Normalizes an Instagram share URL to its canonical form.
  ///
  /// Handles various URL formats:
  /// - `https://www.instagram.com/p/XXXXX/`
  /// - `https://www.instagram.com/reel/XXXXX/`
  /// - `https://instagram.com/p/XXXXX/?igsh=...`
  /// - Share URLs with tracking parameters
  ///
  /// Returns the cleaned URL or null if the URL is not a valid Instagram post.
  static String? normalizeUrl(String input) {
    input = input.trim();

    // Handle share text that contains a URL
    final urlMatch = RegExp(
      r'https?://(?:www\.)?instagram\.com/(?:p|reel|tv)/([A-Za-z0-9_-]+)',
    ).firstMatch(input);

    if (urlMatch == null) return null;

    final shortcode = urlMatch.group(1);
    return 'https://www.instagram.com/p/$shortcode/';
  }

  /// Extracts image URLs from an Instagram post.
  ///
  /// Attempts multiple extraction strategies in order of reliability.
  /// Returns a list of image URLs found in the post (carousel posts may
  /// contain multiple images).
  ///
  /// Throws [InstagramExtractionException] if the post cannot be accessed
  /// or no images are found.
  static Future<List<String>> extractImageUrls(String url) async {
    final normalized = normalizeUrl(url);
    if (normalized == null) {
      throw InstagramExtractionException(
        'Invalid Instagram URL. Expected a post, reel, or TV URL.',
      );
    }

    // Strategy 1: Fetch with mobile user agent (often returns simpler HTML)
    var images = await _fetchAndParse(normalized, _mobileUserAgent);
    if (images.isNotEmpty) return images;

    // Strategy 2: Desktop user agent
    images = await _fetchAndParse(normalized, _desktopUserAgent);
    if (images.isNotEmpty) return images;

    // Strategy 3: Try the embed endpoint
    images = await _fetchFromEmbed(normalized);
    if (images.isNotEmpty) return images;

    throw InstagramExtractionException(
      'Could not extract images. The post may be private, deleted, '
      'or Instagram may be blocking requests. Try again in a moment.',
    );
  }

  /// Fetches page HTML and extracts image URLs via meta tags and JSON-LD.
  static Future<List<String>> _fetchAndParse(
    String url,
    String userAgent,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final body = response.body;
      final images = <String>{};

      // Parse og:image meta tags
      final doc = html_parser.parse(body);
      final metaTags = doc.querySelectorAll('meta[property="og:image"]');
      for (final tag in metaTags) {
        final content = tag.attributes['content'];
        if (content != null && content.startsWith('http')) {
          images.add(content);
        }
      }

      // Also check twitter:image
      final twitterTags = doc.querySelectorAll('meta[name="twitter:image"]');
      for (final tag in twitterTags) {
        final content = tag.attributes['content'];
        if (content != null && content.startsWith('http')) {
          images.add(content);
        }
      }

      // Try to find images in JSON-LD
      final scriptTags = doc.querySelectorAll('script[type="application/ld+json"]');
      for (final script in scriptTags) {
        try {
          final json = jsonDecode(script.text);
          _extractFromJsonLd(json, images);
        } catch (_) {}
      }

      // Try to find images in __additionalDataLoaded or shared data scripts
      final allScripts = doc.querySelectorAll('script');
      for (final script in allScripts) {
        final text = script.text;
        _extractUrlsFromScriptText(text, images);
      }

      return images.toList();
    } catch (e) {
      if (e is InstagramExtractionException) rethrow;
      return [];
    }
  }

  /// Extracts image URLs from the Instagram embed endpoint.
  static Future<List<String>> _fetchFromEmbed(String url) async {
    try {
      final embedUrl = '${url}embed/';
      final response = await http.get(
        Uri.parse(embedUrl),
        headers: {
          'User-Agent': _desktopUserAgent,
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final images = <String>{};
      final doc = html_parser.parse(response.body);

      // Embed pages often have the image in an img tag with specific classes
      final imgTags = doc.querySelectorAll('img.EmbeddedMediaImage');
      for (final img in imgTags) {
        final src = img.attributes['src'];
        if (src != null && src.startsWith('http')) {
          images.add(src);
        }
      }

      // Also check all img tags with instagram CDN URLs
      final allImgs = doc.querySelectorAll('img');
      for (final img in allImgs) {
        final src = img.attributes['src'] ?? '';
        if (src.contains('cdninstagram.com') || src.contains('fbcdn.net')) {
          images.add(src);
        }
      }

      return images.toList();
    } catch (_) {
      return [];
    }
  }

  /// Recursively extracts image URLs from JSON-LD structured data.
  static void _extractFromJsonLd(dynamic json, Set<String> images) {
    if (json is Map<String, dynamic>) {
      // Look for image fields
      for (final key in ['image', 'thumbnailUrl', 'contentUrl', 'url']) {
        final value = json[key];
        if (value is String && _isImageUrl(value)) {
          images.add(value);
        } else if (value is List) {
          for (final item in value) {
            if (item is String && _isImageUrl(item)) {
              images.add(item);
            }
          }
        }
      }
      // Recurse
      for (final value in json.values) {
        _extractFromJsonLd(value, images);
      }
    } else if (json is List) {
      for (final item in json) {
        _extractFromJsonLd(item, images);
      }
    }
  }

  /// Scans inline script text for Instagram CDN image URLs.
  static void _extractUrlsFromScriptText(String text, Set<String> images) {
    // Match Instagram CDN URLs in script content
    final regex = RegExp(
      r'https?://[^"'\s]+?(?:cdninstagram\.com|fbcdn\.net)[^"'\s]*?\.(?:jpg|jpeg|png|webp)[^"'\s]*',
    );
    for (final match in regex.allMatches(text)) {
      var url = match.group(0) ?? '';
      // Clean escaped unicode
      url = url.replaceAll(r'\u0026', '&');
      url = url.replaceAll(r'\/', '/');
      // Only keep reasonably-sized image URLs (skip tiny thumbnails)
      if (url.length < 500) {
        images.add(url);
      }
    }
  }

  /// Returns true if the URL looks like an image resource.
  static bool _isImageUrl(String url) {
    return url.startsWith('http') &&
        (url.contains('cdninstagram.com') ||
            url.contains('fbcdn.net') ||
            url.contains('.jpg') ||
            url.contains('.jpeg') ||
            url.contains('.png') ||
            url.contains('.webp'));
  }
}

/// Exception thrown when image extraction from Instagram fails.
class InstagramExtractionException implements Exception {
  /// Human-readable error message describing what went wrong.
  final String message;

  const InstagramExtractionException(this.message);

  @override
  String toString() => 'InstagramExtractionException: $message';
}
