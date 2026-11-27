# c2pa_flutter example

A sample app for the [c2pa_flutter](../) plugin, and the home of its integration tests.

## The app

- **Home** (`lib/screens/home_screen.dart`) takes a photo with the camera or picks one from the gallery, signs it with a C2PA manifest and saves it.
- **Camera** (`lib/screens/camera_screen.dart`) captures the photo.
- **Verify** (`lib/screens/verify_screen.dart`) reads an image's manifest store and shows its validation status, assertions and ingredients.
- **Settings** (`lib/screens/settings_screen.dart`) chooses how photos are signed: the bundled test certificate, a custom PEM key, a Dart callback signer, the platform keystore, a hardware key (StrongBox / Secure Enclave, with certificate enrollment), a remote signing service, or a signer defined in C2PA settings.

All plugin calls go through `lib/services/c2pa_manager.dart`.

Run it with `flutter run` from this directory. The requirements are the plugin's: Flutter 3.47+, Xcode 26.4+ with Swift Package Manager for iOS, and compileSdk 36 for Android.

## Integration tests

`integration_test/` exercises the plugin against the real c2pa-swift and c2pa-android SDKs, so the tests need a simulator, emulator or device:

```sh
flutter test integration_test/reader_test.dart -d <device>
flutter test integration_test/ -d <device>   # every file
```

| File | Covers |
|---|---|
| `plugin_integration_test.dart` | Plugin wiring, versions, MIME type lists |
| `reader_test.dart` | Unsigned assets and a third-party signed JPEG: JSON, crJSON, thumbnails, embedded state |
| `signer_test.dart` | PEM signing, file signing, builder basics |
| `roundtrip_test.dart` | Sign then read, builder archives, edit-intent chains |
| `error_handling_test.dart` | Invalid inputs and the typed `C2paException`s they raise |
| `sdk_sync_test.dart` | Contexts, progress, cancellation, HTTP resolvers, embeddable manifests, ingredient archives, CAWG |
| `sdk_parity_test.dart` | Scenarios ported from the upstream SDK suites: every algorithm, real callback signatures, BMFF, key management, settings, concurrency |
| `oom_test.dart` | File signing under memory pressure (Android only) |

The fixtures in `assets/` are described in [assets/FIXTURES.md](assets/FIXTURES.md).
