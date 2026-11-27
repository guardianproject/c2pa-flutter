## 0.1.0

Moves to c2pa-swift 0.1.0 and c2pa-android 0.1.2 (c2pa-rs 0.92). Both SDKs now scope all configuration to a context, and the plugin follows them.

### Breaking

* iOS builds need Xcode 26.4 or later (c2pa-swift declares Swift tools 6.3). The SwiftPM dependency is now `github.com/contentauth/c2pa-swift`.
* Android apps must compile with SDK 36 (c2pa-android's AAR metadata requires it).
* Removed `C2pa.readIngredientFromFile`; the SDKs dropped ingredient reading.
* Removed `ReaderOptions.dataDir`; the SDKs no longer write resources to a directory while reading. Use `C2pa.extractResource`.
* Removed `C2pa.createHashedPlaceholder`, `signHashedEmbeddable` and `formatEmbeddable`. Use the new `ManifestBuilder` embeddable methods and `C2pa.composeManifest`.
* `ManifestBuilder` gains abstract methods, so classes outside the package that implement it must add them.
* A `SettingsSigner` can no longer be passed to `ManifestBuilder.sign` or `getSignerReserveSize`, because the SDKs no longer turn settings into a signer. Put the signer in a context's settings and call `sign` without a signer. `C2pa.signBytes` and `C2pa.signFile` still accept it.
* `C2pa.loadSettings` now applies only to readers and builders the plugin creates without a context. The SDKs have no global settings any more.
* Every failure is now a sealed `C2paException` (`C2paManifestNotFoundException`, `C2paCancelledException`, `C2paSdkException`, `C2paInvalidArgumentException`, `C2paUnsupportedException`, `C2paKeyException`, `C2paPlatformException`) instead of a `PlatformException`.
* Reading an asset without a manifest throws `C2paManifestNotFoundException`, as both SDKs do, instead of being documented as returning null. `readFile`, `readBytes`, `readManifestFromFile`, `readManifestFromBytes` and `extractResource` return non-nullable types.
* `ManifestBuilder.setIntent`, `setNoEmbed`, `setRemoteUrl` and `addAction` return futures. `dispose()` on builders, settings and contexts returns a future.
* `C2paSettings.setValue` takes a JSON value (`true`, `42`, `'es256'`, a list) instead of a string. Set objects with `updateFromString`; c2pa-android rejects them here.
* `enrollHardwareKey` returns a `HardwareKeyEnrollment` instead of a map.
* `ValidationStatus` gains `trusted`, read from the SDK's `validation_state`.
* `SignatureInfo.algorithm` is null for an algorithm the plugin does not know, instead of `es256`.
* `createKey` honours `algorithm` (P-256, P-384 or P-521) and rejects anything else. Hardware keys require `es256`.
* Removed `C2pa.readManifestFromFileWithContext`. Pass the context in `ReaderOptions`.
* The package needs Dart 3.13 and Flutter 3.47 or later. CI runs Flutter 3.47.9.
* The Dart, Kotlin and Swift sides now talk through a Pigeon-generated, typed API (`pigeons/c2pa_api.dart`) instead of a hand-written method channel. `MethodChannelC2pa` is replaced by `PigeonC2pa`.
* `C2paPlatform` changes affect only code that calls it directly or implements it:
  * `readFileWithContext` is removed; use `readFileDetailed(path, detailed, contextHandle: ...)`.
  * `createCSR` takes a `CertificateConfig`.
  * `createSelfSignedCertificateChain` takes a `CertificateConfig` instead of a map.
  * `enrollHardwareKey` returns a `HardwareKeyEnrollment`.
  * `C2paHttpResolver.mode` is removed.

### Added

* `C2paContext.create(settings:, signer:, onProgress:, httpResolver:)` and `C2paContext.cancel()`.
* `C2paProgress` / `C2paProgressPhase`, plus HTTP resolvers: `NativeHttpResolver` (URLSession / OkHttp) and `CallbackHttpResolver` (Dart).
* `ManifestBuilder.sign` without a signer, which uses the context signer.
* `ManifestBuilder.signFile`, which streams files natively.
* `ManifestBuilder.setBasePath`, `addIngredientFromArchive` and `writeIngredientArchive`.
* Embeddable manifests: `needsPlaceholder`, `placeholder`, `setDataHashExclusions`, `updateHashFromBytes`, `updateHashFromFile`, `signEmbeddable`, `hashType`, `setFixedSizeMerkle` and `hashMdatBytes`, plus `C2pa.composeManifest`.
* Reading:
  * `C2pa.readCrJsonFromFile` / `readCrJsonFromBytes`
  * `readFileWithManifest` / `readBytesWithManifest`
  * `readFragment` (Android)
  * an optional `context` on `ReaderOptions`, `extractResource` and `createBuilderFromArchive`
* `CawgIdentitySigner`, which combines a claim signer with an X.509 identity signer.
* iOS: `createCSR`, `importKey` (EC keys) and `enrollHardwareKey`.
* Supported MIME types now come from the native SDKs.
* `IngredientInfo.activeManifest`, the label of the ingredient's own manifest.
* Finalizers release builders, settings and contexts that are garbage collected without `dispose()`.
* `RemoteSigner` has a `const` constructor, like the other signers.

### Fixed

* Native calls run in order on a background worker, so signing never blocks the UI thread. `ManifestBuilder.dispose` can no longer free a builder that a running call is still using.
* `addIngredientFromFile` sent its path under the wrong key and never worked.
* Android: signing over an existing, larger destination now truncates it. A missing source or ingredient file now throws instead of being created empty.
* Android: action parameters keep their JSON types.
* Android: `readFileDetailed` and `readBytesDetailed` honour `detailed`.
* iOS: the IPTC source types c2pa-swift does not model (`empty`, `trainedAlgorithmicData`, `computationalCapture`) are recorded instead of falling back to `digitalCapture`.
* iOS: MIME types for `.m4v`, `.m4a`, `.mp3`, `.wav`, `.svg` and `.dng`.
* Builder calls reach the native builder in the order they are made, even when they are not awaited.
* iOS: builders created without a context, `loadSettings` and `SettingsSigner` apply the same default `created_assertion_labels` as Android, so a manifest records the same assertions as created on both platforms.
* iOS: `exportPublicKey` returns a SubjectPublicKeyInfo PEM like Android, not the bare EC point.
* iOS: keychain keys use the tag form c2pa-swift's keychain signer looks up.
* iOS: `deleteKey` deletes keychain keys. It stopped at c2pa-swift's `deleteSecureEnclaveKey`, which reports success even when no Secure Enclave key matched.
* `ManifestInfo.claimGenerator` reads `claim_generator_info` for v2 claims; it was null for every manifest c2pa-rs 0.92 writes.
* `CertificateConfig.email` now reaches the iOS certificate generator; the old channel sent it under a key iOS never read.
* Both platforms reject an HTTP resolver response whose status is out of range instead of wrapping it.

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
