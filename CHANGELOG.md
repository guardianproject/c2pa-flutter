## Unreleased

* Add `ManifestBuilder.addIngredientFromFile` and `ManifestBuilder.signFile`, which stream files natively so video ingredients and outputs no longer pass through Dart memory. Classes that implement `ManifestBuilder` must add both methods
* Read file ingredients and run `ManifestBuilder.signFile` off the main thread on Android and iOS, for every signer type
* `ManifestBuilder.dispose` now waits for running builder calls before freeing the native builder, which could crash on Android
* Android: replace an existing destination file when signing to a file instead of overwriting it in place, which left stale bytes after a shorter output
* Android: fail on a missing source or ingredient file instead of creating an empty one
* iOS: recognize `.m4v`, `.m4a`, `.mp3` and `.svg` when deriving the MIME type from a file path, as Android already did

## 0.0.3

* Fix Android OOM crashes in file-based signing by replacing readBytes()/ByteArrayStream with FileStream
* Fix iOS CI integration test failures caused by stale Xcode module cache

## 0.0.2

* Update to latest c2pa-android and c2pa-ios SDKs
* Add manifest builder API for creating and signing content credentials
* Add settings validation and manifest validation APIs
* Add CAWG identity and training/mining assertion support
* Add certificate configuration and hardware signer support
* Expand example app with settings screen and verify screen enhancements
* Add `@immutable` annotations and `const` constructors to data classes
* Add lint rules for const enforcement and trailing commas
* Add dual Apache-2.0/MIT license files
* Fix Package.swift swift-tools-version placement for Swift 6.0 compatibility
* Fix iOS DigitalSourceType mapping for c2pa-ios SDK compatibility

## 0.0.1

* Initial release.
