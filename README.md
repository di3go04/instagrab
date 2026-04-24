# InstaGrab

Download, crop, and resize images from Instagram share URLs. Flutter app targeting Linux desktop and Android.

## Features

- **URL Input** — Paste any Instagram post/reel/TV share URL
- **Multi-image support** — Carousel posts download all images with thumbnail strip navigation
- **Interactive crop** — Drag-to-crop with aspect ratio presets (Free, 1:1, 4:5, 16:9, 9:16, 4:3, 3:2)
- **Resize** — Manual width/height input with aspect ratio lock, plus quick presets (1080×1080, 1080×1350, etc.)
- **Save** — Export as PNG or JPEG to ~/Pictures/InstaGrab (Linux) or Downloads/InstaGrab (Android)
- **Share intent** — Android share sheet integration (share from Instagram → InstaGrab)

## Setup

```bash
# Clone/copy the lib/ directory and pubspec.yaml into a new Flutter project:
flutter create insta_grab --platforms=linux,android
# Then replace lib/ and pubspec.yaml with these files

# Or if starting fresh, copy everything and run:
cd insta_grab
flutter pub get
flutter run -d linux    # Linux desktop
flutter run -d android  # Android device/emulator
```

## Architecture

```
lib/
├── main.dart                    # App entry, theme
├── screens/
│   ├── home_screen.dart         # URL input, extraction flow
│   └── editor_screen.dart       # Crop + resize UI
├── services/
│   ├── instagram_service.dart   # URL parsing, HTML scraping, image extraction
│   └── image_service.dart       # Download, resize, encode, save
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `http` | HTTP requests for page fetching and image download |
| `html` | HTML parsing for og:image meta tag extraction |
| `crop_your_image` | Pure-Dart interactive crop widget (no native deps) |
| `image` | Cross-platform image decode/resize/encode |
| `path_provider` | Platform-appropriate file paths |
| `share_plus` | Share intent handling |

## Instagram Extraction Strategy

The service uses multiple fallback strategies:
1. Fetch post HTML with mobile user-agent → parse `og:image` meta tags
2. Retry with desktop user-agent → parse meta tags + JSON-LD
3. Fetch `/embed/` endpoint → extract CDN image URLs
4. Scan inline `<script>` blocks for `cdninstagram.com` / `fbcdn.net` URLs

## Notes

- Instagram may rate-limit or block requests from certain IPs. If extraction fails, retry after a moment.
- Private posts cannot be accessed.
- The Android manifest includes a share intent filter so you can share directly from Instagram to InstaGrab.
- The `AndroidManifest.xml` provided here is a reference — after `flutter create`, merge the permissions and intent filters into the generated manifest.
