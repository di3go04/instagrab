# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This repo is **source-only** — it ships `lib/`, `pubspec.yaml`, `analysis_options.yaml`, and a reference `android/app/src/main/AndroidManifest.xml`, but **not** the generated Flutter platform scaffolding (no `linux/`, no `android/` Gradle files, no `ios/`, no `.dart_tool/`). Before anything will build you must bootstrap a Flutter project around these files:

```bash
flutter create insta_grab --platforms=linux,android
# then copy lib/, pubspec.yaml, analysis_options.yaml over the generated ones
# and MERGE the intent-filter + permissions from android/app/src/main/AndroidManifest.xml
# into the generated manifest (do not blindly overwrite — the generated manifest has
# additional <queries> entries and theme references that must stay)
```

The package name in the reference manifest is `com.djb.insta_grab` and must match the `applicationId` Gradle uses after `flutter create`.

## Common commands

```bash
flutter pub get                 # fetch deps
flutter run -d linux            # desktop run (dev)
flutter run -d android          # device/emulator run
flutter analyze                 # lint (uses analysis_options.yaml)
flutter test                    # no tests currently exist, but this is the entrypoint
dart format lib/                # format
```

Dart SDK constraint is `>=3.2.0 <4.0.0`. Lints extend `flutter_lints` and additionally require `prefer_const_constructors` + `prefer_const_declarations`; `avoid_print` is **off** (home_screen.dart uses `print` for per-image download failures — this is intentional).

## Architecture

Single-activity, two-screen Material 3 app. Flow:

```
HomeScreen (URL input)
  └─► InstagramService.extractImageUrls(url)     ← lib/services/instagram_service.dart
        ├─ Strategy 1: GET post with mobile UA → parse og:image/twitter:image/JSON-LD
        ├─ Strategy 2: GET with desktop UA (retry)
        └─ Strategy 3: GET {url}embed/ → scan for cdninstagram.com/fbcdn.net URLs
  └─► ImageService.downloadImage(url) per image  ← lib/services/image_service.dart
  └─► EditorScreen(images: List<DownloadedImage>)
        ├─ Crop mode:   crop_your_image Crop widget + aspect presets
        └─ Resize mode: image pkg copyResize with optional aspect lock
              └─► ImageService.saveImage → platform-specific output dir
```

Key invariants to preserve when editing:

- **`InstagramService` is 100% static** (no instance state) and pure-Dart. All four strategies live in this one file and run sequentially — short-circuit on first non-empty result. When adding a strategy, chain it onto `extractImageUrls` in the same "return if non-empty, otherwise continue" pattern and throw `InstagramExtractionException` only after all strategies fail.
- **`ImageService` uses only `package:image`** (pure Dart) for decode/resize/encode — no native codecs. This is the reason the app builds for Linux desktop with no extra plugin work. Don't introduce platform-channel image libs.
- **Output directory is platform-branched** in `ImageService.getOutputDirectory` (Android: `/storage/emulated/0/Download/InstaGrab`, Linux: `$HOME/Pictures/InstaGrab`, else: app documents). The Android manifest declares legacy external storage + `READ_MEDIA_IMAGES` to support this hardcoded path.
- **`DownloadedImage` is defined in `home_screen.dart`** (not in a model file) and imported by `editor_screen.dart`. `EditorScreen` holds the post-edit bytes in `_croppedBytes`; `null` means "show original". `_updateImageInfo` must be called after any op that changes `_activeBytes` so the width/height fields and `_originalAspect` stay in sync.
- **The `Crop` widget is rebuilt via a ValueKey** combining index + aspect ratio + cropped-bytes length. Changing any of these without updating that key will silently leave stale crop state.

## Instagram extraction caveats

Instagram actively rate-limits and sometimes returns empty HTML shells. The layered strategy exists because each one fails independently — do not collapse them. When debugging extraction failures, log the HTTP status and body length from `_fetchAndParse` before adding new parsers; most "no images found" failures are 200s with a login wall rather than parser bugs.

The regex in `_extractUrlsFromScriptText` filters URLs >500 chars (Instagram CDN URLs with very long query strings are usually tracking pixels, not the full-resolution image). Adjust with care.

## Share intent (Android)

The reference manifest registers an `ACTION_SEND` / `text/plain` intent filter so Instagram's "Share → InstaGrab" flow delivers the URL as shared text. **The Dart side does not currently consume this intent** — `HomeScreen` only reads the clipboard via the paste button. If you add share-intent handling, wire it through `share_plus` in `initState` and populate `_urlController` before the first frame.
