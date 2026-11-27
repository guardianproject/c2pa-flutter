## 0.0.4

* Switch to the official contentauth c2pa-android and c2pa-ios 0.0.9 releases (from the redaranj forks)
* Add `getRemoteUrl` and `isManifestEmbedded` to the reader API
* Add `addIngredientFromFile` to the builder, reading the ingredient natively instead of passing bytes through Dart
* Add a typed `C2paSettingsDefinition`, with `C2paSettings.fromDefinition` and `updateFromDefinition`
* Support `settingsSetValue` on iOS
* Align `PredefinedAction` with the C2PA spec action list, adding the font and watermark actions
* **Breaking:** remove `Action.aiGenerated`, `PredefinedAction.aiGenerated` and other non-spec actions; tag AI-generated content with `Action.created(sourceType: DigitalSourceType.trainedAlgorithmicMedia)` instead
* iOS returns `NOT_IMPLEMENTED_IOS` for the hashed-signing and key-import/CSR/hardware-enrollment calls, which are not yet available there

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
