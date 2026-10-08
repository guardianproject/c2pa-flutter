# c2pa_flutter

A Flutter plugin for [C2PA](https://c2pa.org/) (Coalition for Content Provenance and Authenticity) that enables reading and signing content credentials on mobile devices.

## Features

- Read C2PA manifests from files or byte arrays
- Sign images with C2PA manifests (embedded content credentials)
- Support for multiple signing algorithms (ES256, ES384, ES512, PS256, PS384, PS512, ED25519)
- Optional Time Stamping Authority (TSA) support
- Native performance via platform-specific C2PA libraries

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 15.0            |
| Android  | API 28 (Android 9.0) |

## Installation

Add `c2pa_flutter` to your `pubspec.yaml`:

```yaml
dependencies:
  c2pa_flutter:
    git:
      url: https://github.com/nicktardif/c2pa-flutter.git
```

Then run:

```bash
flutter pub get
```

## Usage

### Import the package

```dart
import 'package:c2pa_flutter/c2pa.dart';
```

### Create a C2PA instance

```dart
final c2pa = C2pa();
```

### Get C2PA library version

```dart
final version = await c2pa.getVersion();
print('C2PA version: $version');
```

### Read manifest from a file

```dart
final manifestJson = await c2pa.readFile('/path/to/image.jpg');
if (manifestJson != null) {
  // Parse and use the manifest JSON
  print(manifestJson);
}
```

### Read manifest from bytes

```dart
final Uint8List imageData = /* your image bytes */;
final manifestJson = await c2pa.readBytes(imageData, 'image/jpeg');
```

### Sign an image (bytes)

```dart
final signerInfo = SignerInfo(
  algorithm: SigningAlgorithm.es256,
  certificatePem: '''-----BEGIN CERTIFICATE-----
...your certificate...
-----END CERTIFICATE-----''',
  privateKeyPem: '''-----BEGIN PRIVATE KEY-----
...your private key...
-----END PRIVATE KEY-----''',
  tsaUrl: 'http://timestamp.digicert.com', // optional
);

final manifestJson = '''{
  "claim_generator": "MyApp/1.0.0",
  "title": "Signed Photo",
  "assertions": [
    {
      "label": "c2pa.actions",
      "data": {
        "actions": [
          {
            "action": "c2pa.created",
            "digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"
          }
        ]
      }
    }
  ]
}''';

final result = await c2pa.signBytes(
  sourceData: imageData,
  mimeType: 'image/jpeg',
  manifestJson: manifestJson,
  signerInfo: signerInfo,
);

// result.signedData contains the signed image with embedded C2PA manifest
// result.manifestBytes contains the manifest bytes (optional)
```

### Sign an image (file)

```dart
await c2pa.signFile(
  sourcePath: '/path/to/source.jpg',
  destPath: '/path/to/signed.jpg',
  manifestJson: manifestJson,
  signerInfo: signerInfo,
);
```

### Record an edit of large media (files)

`addIngredientFromFile` and `signFile` on a `ManifestBuilder` stream the files
on the native side instead of copying them into Dart memory, so they work for
video ingredients that would not fit through `addIngredient` / `sign`.

```dart
final builder = await c2pa.createBuilder(manifestJson);
builder.setIntent(ManifestIntent.edit);
await builder.addIngredientFromFile(
  path: '/path/to/original.mp4',
  config: const IngredientConfig(relationship: Relationship.parentOf),
);
builder.addAction(const ActionConfig(action: 'c2pa.edited'));
await builder.signFile(
  sourcePath: '/path/to/edited.mp4',
  destPath: '/path/to/edited_signed.mp4',
  signer: signer,
);
builder.dispose();
```

## API Reference

### C2pa

| Method | Description |
|--------|-------------|
| `getVersion()` | Returns the C2PA library version |
| `getPlatformVersion()` | Returns the platform (iOS/Android) version |
| `readFile(path)` | Reads C2PA manifest from a file path |
| `readBytes(data, mimeType)` | Reads C2PA manifest from byte array |
| `signBytes(...)` | Signs bytes and returns signed data with manifest |
| `signFile(...)` | Signs a file and writes to destination path |

### SignerInfo

| Property | Type | Description |
|----------|------|-------------|
| `algorithm` | `SigningAlgorithm` | Signing algorithm to use |
| `certificatePem` | `String` | PEM-encoded certificate chain |
| `privateKeyPem` | `String` | PEM-encoded private key |
| `tsaUrl` | `String?` | Optional Time Stamping Authority URL |

### SigningAlgorithm

- `es256` - ECDSA with P-256 and SHA-256
- `es384` - ECDSA with P-384 and SHA-384
- `es512` - ECDSA with P-521 and SHA-512
- `ps256` - RSASSA-PSS with SHA-256
- `ps384` - RSASSA-PSS with SHA-384
- `ps512` - RSASSA-PSS with SHA-512
- `ed25519` - EdDSA with Ed25519

### SignResult

| Property | Type | Description |
|----------|------|-------------|
| `signedData` | `Uint8List` | The signed image data with embedded manifest |
| `manifestBytes` | `Uint8List?` | The manifest bytes (if available) |

## Supported MIME Types

- `image/jpeg`
- `image/png`
- `image/webp`
- `image/avif`
- `image/heic`
- `image/heif`

## Example

See the [example](example/) directory for a complete sample application demonstrating camera capture with C2PA signing.

## License

See [LICENSE](LICENSE) for details.

## About C2PA

The [Coalition for Content Provenance and Authenticity (C2PA)](https://c2pa.org/) is a standards body that develops technical specifications for certifying the source and history of media content. C2PA manifests provide a tamper-evident way to attach provenance information to digital content.

## Credits

Developed by [Guardian Project](https://guardianproject.info/).
