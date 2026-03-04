/* 
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

/// C2PA Flutter Plugin - Content Authenticity for Mobile Apps
///
/// This library provides a Flutter interface to the C2PA (Coalition for Content
/// Provenance and Authenticity) specification, enabling mobile applications to
/// read, create, and verify content credentials embedded in digital media.
///
/// ## Overview
///
/// C2PA is an open technical standard that enables content creators and publishers
/// to embed provenance information directly into media files. This helps establish
/// the origin and history of digital content.
///
/// ## Getting Started
///
/// Create an instance of [C2pa] to access all functionality:
///
/// ```dart
/// final c2pa = C2pa();
///
/// // Check library version
/// final version = await c2pa.getVersion();
/// print('C2PA version: $version');
/// ```
///
/// ## Reading Manifests
///
/// Read C2PA manifests from files or byte data:
///
/// ```dart
/// // Read from file
/// final json = await c2pa.readFile('/path/to/image.jpg');
///
/// // Read with parsed data
/// final manifest = await c2pa.readManifestFromFile('/path/to/image.jpg');
/// if (manifest != null) {
///   print('Active manifest: ${manifest.activeManifest}');
///   print('Validation: ${manifest.validationStatus}');
/// }
/// ```
///
/// ## Signing Content
///
/// Sign content with C2PA manifests using the Builder API:
///
/// ```dart
/// // Create a builder
/// final builder = await c2pa.createBuilder('{"title": "My Photo"}');
///
/// // Configure the manifest
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
///
/// // Sign the content with a PEM signer
/// final result = await builder.sign(
///   sourceData: imageBytes,
///   mimeType: 'image/jpeg',
///   signer: PemSigner(
///     algorithm: SigningAlgorithm.es256,
///     certificatePem: certificatePem,
///     privateKeyPem: privateKeyPem,
///   ),
/// );
///
/// // Use result.signedData
/// builder.dispose();
/// ```
///
/// ## Signer Types
///
/// Multiple signer types are available for different use cases:
///
/// - [PemSigner] - Direct signing with PEM certificate and private key
/// - [CallbackSigner] - Custom callback-based signing (HSM, smart cards)
/// - [KeystoreSigner] - Android Keystore / iOS Keychain
/// - [HardwareSigner] - StrongBox (Android) / Secure Enclave (iOS)
/// - [RemoteSigner] - Remote web service signing
///
/// ## Key Classes
///
/// - [C2pa] - Main entry point for all C2PA operations
/// - [ManifestBuilder] - Builder pattern for creating manifests
/// - [ManifestStoreInfo] - Parsed manifest data with validation info
/// - [C2paSigner] - Base class for all signer types
/// - [SigningAlgorithm] - Supported cryptographic algorithms
///
/// ## See Also
///
/// - [C2PA Specification](https://c2pa.org/specifications/)
/// - [Content Authenticity Initiative](https://contentauthenticity.org/)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'c2pa_platform_interface.dart';
import 'src/manifest_types.dart';

// Export manifest types
export 'src/manifest_types.dart';
export 'src/manifest_validator.dart';
export 'src/settings_validator.dart';

// =============================================================================
// Enums
// =============================================================================

/// Signing algorithms supported by C2PA
enum SigningAlgorithm { es256, es384, es512, ps256, ps384, ps512, ed25519 }

/// Builder intent - specifies what kind of manifest to create
enum ManifestIntent {
  /// New digital creation with specified digital source type.
  /// The Manifest must not have a parent ingredient.
  /// A `c2pa.created` action will be added if not provided.
  create,

  /// Edit of a pre-existing parent asset.
  /// The Manifest must have a parent ingredient.
  /// A parent ingredient will be generated from the source stream if not otherwise provided.
  /// A `c2pa.opened` action will be tied to the parent ingredient.
  edit,

  /// Restricted version of Edit for non-editorial changes.
  /// There must be only one ingredient, as a parent.
  /// No changes can be made to the hashed content of the parent.
  update,
}

/// Validation status for manifest verification
enum ValidationStatus { valid, invalid, unknown }

// =============================================================================
// Signer Types
// =============================================================================

/// Base sealed class for all C2PA signer types.
///
/// Use one of the concrete implementations:
/// - [PemSigner] - Direct signing with PEM certificate and private key
/// - [CallbackSigner] - Custom callback-based signing
/// - [KeystoreSigner] - Android Keystore / iOS Keychain signing
/// - [HardwareSigner] - Hardware-backed signing (StrongBox/Secure Enclave)
/// - [RemoteSigner] - Remote web service signing
sealed class C2paSigner {
  /// The signing algorithm to use.
  SigningAlgorithm get algorithm;

  /// Optional RFC 3161 Time Stamp Authority URL for trusted timestamps.
  String? get tsaUrl;

  /// Convert to a map for platform channel serialization.
  Map<String, dynamic> toMap();
}

/// PEM certificate + private key signer.
///
/// This is the most common signer type where you have direct access to
/// the certificate chain and private key in PEM format.
///
/// ## Example
///
/// ```dart
/// final signer = PemSigner(
///   algorithm: SigningAlgorithm.es256,
///   certificatePem: await File('cert.pem').readAsString(),
///   privateKeyPem: await File('key.pem').readAsString(),
///   tsaUrl: 'http://timestamp.digicert.com',
/// );
/// ```
///
/// ## Supported Algorithms
///
/// - ECDSA: [SigningAlgorithm.es256], [SigningAlgorithm.es384], [SigningAlgorithm.es512]
/// - RSA-PSS: [SigningAlgorithm.ps256], [SigningAlgorithm.ps384], [SigningAlgorithm.ps512]
/// - EdDSA: [SigningAlgorithm.ed25519]
class PemSigner extends C2paSigner {
  @override
  final SigningAlgorithm algorithm;

  /// PEM-encoded X.509 certificate chain.
  final String certificatePem;

  /// PEM-encoded private key (must match the certificate's public key).
  final String privateKeyPem;

  @override
  final String? tsaUrl;

  PemSigner({
    required this.algorithm,
    required this.certificatePem,
    required this.privateKeyPem,
    this.tsaUrl,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'pem',
      'algorithm': algorithm.name,
      'certificatePem': certificatePem,
      'privateKeyPem': privateKeyPem,
    };
    if (tsaUrl != null) map['tsaUrl'] = tsaUrl;
    return map;
  }

  factory PemSigner.fromMap(Map<String, dynamic> map) {
    return PemSigner(
      algorithm: SigningAlgorithm.values.firstWhere(
        (e) => e.name == map['algorithm'],
        orElse: () => SigningAlgorithm.es256,
      ),
      certificatePem: map['certificatePem'] as String,
      privateKeyPem: map['privateKeyPem'] as String,
      tsaUrl: map['tsaUrl'] as String?,
    );
  }
}

/// Custom callback-based signer.
///
/// Use this when you need to implement custom signing logic, such as
/// integrating with a custom HSM, smart card, or other signing service.
///
/// ## Example
///
/// ```dart
/// final signer = CallbackSigner(
///   algorithm: SigningAlgorithm.es256,
///   certificateChainPem: certChain,
///   signCallback: (data) async {
///     // Your custom signing logic here
///     return await myHsm.sign(data);
///   },
/// );
/// ```
class CallbackSigner extends C2paSigner {
  @override
  final SigningAlgorithm algorithm;

  /// PEM-encoded X.509 certificate chain.
  final String certificateChainPem;

  /// Callback function that performs the actual signing.
  /// Receives the data to sign and returns the signature bytes.
  final Future<Uint8List> Function(Uint8List data) signCallback;

  @override
  final String? tsaUrl;

  CallbackSigner({
    required this.algorithm,
    required this.certificateChainPem,
    required this.signCallback,
    this.tsaUrl,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'callback',
      'algorithm': algorithm.name,
      'certificateChainPem': certificateChainPem,
    };
    if (tsaUrl != null) map['tsaUrl'] = tsaUrl;
    return map;
  }
}

/// Android Keystore / iOS Keychain signer.
///
/// Signs using a key stored in the platform's secure key storage:
/// - Android: Android Keystore
/// - iOS: iOS Keychain
///
/// The key must already exist in the keystore/keychain before creating
/// the signer. Use [C2pa.createKey] to generate a new key.
///
/// ## Example
///
/// ```dart
/// final signer = KeystoreSigner(
///   algorithm: SigningAlgorithm.es256,
///   certificateChainPem: certChain,
///   keyAlias: 'my-signing-key',
///   requireUserAuthentication: true, // Requires biometric on Android
/// );
/// ```
///
/// ## Platform Notes
///
/// - Ed25519 is not supported on either platform for keystore signing
/// - On Android with [requireUserAuthentication], a biometric prompt is shown
class KeystoreSigner extends C2paSigner {
  @override
  final SigningAlgorithm algorithm;

  /// PEM-encoded X.509 certificate chain.
  final String certificateChainPem;

  /// The alias/tag identifying the key in the keystore/keychain.
  final String keyAlias;

  /// Whether to require user authentication (biometric) before signing.
  /// On Android, this shows a biometric prompt.
  final bool requireUserAuthentication;

  @override
  final String? tsaUrl;

  KeystoreSigner({
    required this.algorithm,
    required this.certificateChainPem,
    required this.keyAlias,
    this.requireUserAuthentication = false,
    this.tsaUrl,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'keystore',
      'algorithm': algorithm.name,
      'certificateChainPem': certificateChainPem,
      'keyAlias': keyAlias,
      'requireUserAuthentication': requireUserAuthentication,
    };
    if (tsaUrl != null) map['tsaUrl'] = tsaUrl;
    return map;
  }
}

/// Hardware-backed signer (StrongBox on Android, Secure Enclave on iOS).
///
/// Provides the highest level of key protection using dedicated hardware:
/// - Android: StrongBox (requires Android 9.0+ and device support)
/// - iOS: Secure Enclave (requires iPhone 5s or later, not available in Simulator)
///
/// ## Important Limitations
///
/// - Only ES256 algorithm is supported on both platforms
/// - Keys cannot be exported from the hardware
/// - The key must already exist or will be created automatically
///
/// ## Example
///
/// ```dart
/// // Check availability first
/// if (await c2pa.isHardwareSigningAvailable()) {
///   final signer = HardwareSigner(
///     certificateChainPem: certChain,
///     keyAlias: 'my-hardware-key',
///   );
/// }
/// ```
class HardwareSigner extends C2paSigner {
  /// Hardware signing only supports ES256.
  @override
  SigningAlgorithm get algorithm => SigningAlgorithm.es256;

  /// PEM-encoded X.509 certificate chain.
  final String certificateChainPem;

  /// The alias/tag identifying the key in hardware storage.
  final String keyAlias;

  /// Whether to require user authentication before signing.
  /// On iOS, this may trigger Face ID or Touch ID.
  final bool requireUserAuthentication;

  @override
  final String? tsaUrl;

  HardwareSigner({
    required this.certificateChainPem,
    required this.keyAlias,
    this.requireUserAuthentication = false,
    this.tsaUrl,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'hardware',
      'algorithm': algorithm.name,
      'certificateChainPem': certificateChainPem,
      'keyAlias': keyAlias,
      'requireUserAuthentication': requireUserAuthentication,
    };
    if (tsaUrl != null) map['tsaUrl'] = tsaUrl;
    return map;
  }
}

/// Remote web service signer.
///
/// Delegates signing to a remote service where private keys are managed
/// server-side. The service must implement the C2PA web service signing
/// protocol.
///
/// ## Example
///
/// ```dart
/// final signer = RemoteSigner(
///   configurationUrl: 'https://signing.example.com/config',
///   bearerToken: 'your-auth-token',
/// );
/// ```
///
/// ## Service Requirements
///
/// The remote service must provide:
/// - A configuration endpoint returning algorithm, certificate chain, and TSA URL
/// - A signing endpoint that accepts data and returns signatures
class RemoteSigner extends C2paSigner {
  /// Algorithm is determined by the remote service configuration.
  /// This will be set after connecting to the service.
  @override
  SigningAlgorithm get algorithm => _algorithm ?? SigningAlgorithm.es256;
  SigningAlgorithm? _algorithm;

  /// TSA URL is determined by the remote service configuration.
  @override
  String? get tsaUrl => _tsaUrl;
  String? _tsaUrl;

  /// URL to the remote signing service configuration endpoint.
  final String configurationUrl;

  /// Optional bearer token for authentication.
  final String? bearerToken;

  /// Optional custom HTTP headers for requests.
  final Map<String, String>? customHeaders;

  RemoteSigner({
    required this.configurationUrl,
    this.bearerToken,
    this.customHeaders,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': 'remote',
      'configurationUrl': configurationUrl,
    };
    if (bearerToken != null) map['bearerToken'] = bearerToken;
    if (customHeaders != null) map['customHeaders'] = customHeaders;
    return map;
  }
}

/// Settings-based signer for CAWG X.509 identity and other settings-configured signers.
///
/// Creates a signer from a JSON or TOML settings string that contains the
/// signing configuration (algorithm, certificates, keys, etc.).
///
/// This is particularly useful for CAWG X.509 identity signers where the
/// signing configuration is provided via settings.
///
/// ## Example
///
/// ```dart
/// final signer = SettingsSigner(
///   settingsString: '{"version": 1, "signer": {"local": {...}}}',
///   format: 'json',
/// );
/// ```
class SettingsSigner extends C2paSigner {
  /// The settings string containing signer configuration.
  final String settingsString;

  /// The format of the settings string: 'json' or 'toml'.
  final String format;

  /// Algorithm is determined by the settings.
  @override
  SigningAlgorithm get algorithm => SigningAlgorithm.es256;

  /// TSA URL is determined by the settings.
  @override
  String? get tsaUrl => null;

  SettingsSigner({required this.settingsString, this.format = 'json'});

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': 'settings',
      'settings': settingsString,
      'format': format,
    };
  }
}

/// Result of a signing operation
class SignResult {
  final Uint8List signedData;
  final Uint8List? manifestBytes;

  SignResult({required this.signedData, this.manifestBytes});

  /// Size of the signed data in bytes
  int get signedDataSize => signedData.length;

  /// Size of the manifest bytes if available
  int? get manifestSize => manifestBytes?.length;
}

// =============================================================================
// Reader Data Classes
// =============================================================================

/// Options for reading manifests
class ReaderOptions {
  /// Whether to return detailed JSON including validation info
  final bool detailed;

  /// Directory to write resources (thumbnails, etc.)
  final String? dataDir;

  const ReaderOptions({this.detailed = false, this.dataDir});

  Map<String, dynamic> toMap() {
    return {'detailed': detailed, 'dataDir': dataDir};
  }
}

/// Signature information from a manifest
class SignatureInfo {
  /// The issuer of the certificate
  final String? issuer;

  /// When the manifest was signed
  final DateTime? signedAt;

  /// When the certificate expires
  final DateTime? expiresAt;

  /// The signing algorithm used
  final SigningAlgorithm? algorithm;

  /// The certificate serial number
  final String? serialNumber;

  SignatureInfo({
    this.issuer,
    this.signedAt,
    this.expiresAt,
    this.algorithm,
    this.serialNumber,
  });

  factory SignatureInfo.fromMap(Map<String, dynamic> map) {
    final timeStr = map['signed_at'] as String? ?? map['time'] as String?;
    final algStr = map['algorithm'] as String? ?? map['alg'] as String?;
    return SignatureInfo(
      issuer: map['issuer'] as String?,
      signedAt: timeStr != null ? DateTime.tryParse(timeStr) : null,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'] as String)
          : null,
      algorithm: algStr != null
          ? SigningAlgorithm.values.firstWhere(
              (e) => e.name.toLowerCase() == algStr.toLowerCase(),
              orElse: () => SigningAlgorithm.es256,
            )
          : null,
      serialNumber: map['serial_number'] as String? ??
          map['cert_serial_number'] as String?,
    );
  }
}

/// Validation error from manifest verification
class ValidationError {
  /// Error code
  final String code;

  /// Human-readable error message
  final String message;

  /// The manifest label this error relates to (if applicable)
  final String? manifestLabel;

  const ValidationError({
    required this.code,
    required this.message,
    this.manifestLabel,
  });

  factory ValidationError.fromMap(Map<String, dynamic> map) {
    return ValidationError(
      code: map['code'] as String? ?? 'unknown',
      message: map['message'] as String? ?? map['explanation'] as String? ?? 'Unknown error',
      manifestLabel: map['manifest_label'] as String? ?? map['url'] as String?,
    );
  }

  @override
  String toString() => 'ValidationError($code: $message)';
}

/// Information about an assertion in a manifest
class AssertionInfo {
  /// The assertion label (e.g., "c2pa.actions")
  final String label;

  /// The assertion data
  final Map<String, dynamic> data;

  /// Instance identifier if present
  final int? instance;

  AssertionInfo({required this.label, required this.data, this.instance});

  factory AssertionInfo.fromMap(Map<String, dynamic> map) {
    return AssertionInfo(
      label: map['label'] as String? ?? '',
      data: map['data'] as Map<String, dynamic>? ?? {},
      instance: map['instance'] as int?,
    );
  }
}

/// Information about an ingredient in a manifest
class IngredientInfo {
  /// Title of the ingredient
  final String? title;

  /// Format/MIME type
  final String? format;

  /// Instance ID
  final String? instanceId;

  /// Document ID
  final String? documentId;

  /// Relationship to parent manifest
  final Relationship relationship;

  /// Thumbnail URI if present
  final String? thumbnailUri;

  /// The ingredient's manifest if present
  final ManifestInfo? manifest;

  /// Validation status of the ingredient
  final ValidationStatus validationStatus;

  const IngredientInfo({
    this.title,
    this.format,
    this.instanceId,
    this.documentId,
    required this.relationship,
    this.thumbnailUri,
    this.manifest,
    this.validationStatus = ValidationStatus.unknown,
  });

  factory IngredientInfo.fromMap(Map<String, dynamic> map) {
    final relationshipStr = map['relationship'] as String?;
    final relationship = relationshipStr != null
        ? Relationship.fromJson(relationshipStr)
        : Relationship.componentOf;

    return IngredientInfo(
      title: map['title'] as String?,
      format: map['format'] as String?,
      instanceId: map['instance_id'] as String?,
      documentId: map['document_id'] as String?,
      relationship: relationship,
      thumbnailUri: map['thumbnail']?['identifier'] as String?,
      manifest: map['manifest'] != null
          ? ManifestInfo.fromMap(map['manifest'] as Map<String, dynamic>)
          : null,
      validationStatus: _parseValidationStatus(map['validation_status']),
    );
  }

  static ValidationStatus _parseValidationStatus(dynamic status) {
    if (status == null) return ValidationStatus.unknown;
    if (status is String) {
      switch (status.toLowerCase()) {
        case 'valid':
          return ValidationStatus.valid;
        case 'invalid':
          return ValidationStatus.invalid;
        default:
          return ValidationStatus.unknown;
      }
    }
    return ValidationStatus.unknown;
  }
}

/// Information about a single manifest
class ManifestInfo {
  /// The manifest label (unique identifier)
  final String label;

  /// Title of the asset
  final String? title;

  /// Format/MIME type
  final String? format;

  /// Claim generator string
  final String? claimGenerator;

  /// Instance ID
  final String? instanceId;

  /// Signature information
  final SignatureInfo? signature;

  /// List of assertions
  final List<AssertionInfo> assertions;

  /// List of ingredients
  final List<IngredientInfo> ingredients;

  /// Thumbnail URI if present
  final String? thumbnailUri;

  const ManifestInfo({
    required this.label,
    this.title,
    this.format,
    this.claimGenerator,
    this.instanceId,
    this.signature,
    this.assertions = const [],
    this.ingredients = const [],
    this.thumbnailUri,
  });

  factory ManifestInfo.fromMap(Map<String, dynamic> map) {
    return ManifestInfo(
      label: map['label'] as String? ?? '',
      title: map['title'] as String?,
      format: map['format'] as String?,
      claimGenerator: map['claim_generator'] as String?,
      instanceId: map['instance_id'] as String?,
      signature: map['signature_info'] != null
          ? SignatureInfo.fromMap(map['signature_info'] as Map<String, dynamic>)
          : null,
      assertions:
          (map['assertions'] as List<dynamic>?)
              ?.map((a) => AssertionInfo.fromMap(a as Map<String, dynamic>))
              .toList() ??
          [],
      ingredients:
          (map['ingredients'] as List<dynamic>?)
              ?.map((i) => IngredientInfo.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      thumbnailUri: map['thumbnail']?['identifier'] as String?,
    );
  }
}

/// Complete manifest store with all manifests and validation info
class ManifestStoreInfo {
  /// The active manifest label
  final String? activeManifest;

  /// Map of manifest labels to manifest info
  final Map<String, ManifestInfo> manifests;

  /// List of validation errors
  final List<ValidationError> validationErrors;

  /// Overall validation status
  final ValidationStatus validationStatus;

  const ManifestStoreInfo({
    this.activeManifest,
    this.manifests = const {},
    this.validationErrors = const [],
    this.validationStatus = ValidationStatus.unknown,
  });

  /// Get the active manifest if present
  ManifestInfo? get active =>
      activeManifest != null ? manifests[activeManifest] : null;

  factory ManifestStoreInfo.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ManifestStoreInfo.fromMap(map);
  }

  factory ManifestStoreInfo.fromMap(Map<String, dynamic> map) {
    final manifestsMap = <String, ManifestInfo>{};
    final manifestsData = map['manifests'] as Map<String, dynamic>?;
    if (manifestsData != null) {
      for (final entry in manifestsData.entries) {
        manifestsMap[entry.key] = ManifestInfo.fromMap(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return ManifestStoreInfo(
      activeManifest: map['active_manifest'] as String?,
      manifests: manifestsMap,
      validationErrors:
          (map['validation_status'] as List<dynamic>?)
              ?.map((e) => ValidationError.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      validationStatus: _determineValidationStatus(map),
    );
  }

  static ValidationStatus _determineValidationStatus(Map<String, dynamic> map) {
    final errors = map['validation_status'] as List<dynamic>?;
    if (errors == null) return ValidationStatus.unknown;
    if (errors.isEmpty) return ValidationStatus.valid;
    return ValidationStatus.invalid;
  }
}

// =============================================================================
// Builder Data Classes
// =============================================================================

/// Resource data for adding to a builder (thumbnail, icon, etc.)
///
/// This differs from [ResourceRef] in manifest_types.dart which is used
/// for references within the manifest JSON structure.
class BuilderResource {
  /// URI identifier for the resource
  final String uri;

  /// Resource data
  final Uint8List data;

  /// Optional MIME type
  final String? mimeType;

  BuilderResource({required this.uri, required this.data, this.mimeType});

  Map<String, dynamic> toMap() {
    return {'uri': uri, 'data': data, 'mimeType': mimeType};
  }
}

/// Configuration for adding an ingredient to a builder
class IngredientConfig {
  /// Title of the ingredient
  final String? title;

  /// Relationship to the manifest
  final Relationship relationship;

  /// Optional thumbnail
  final BuilderResource? thumbnail;

  /// Additional JSON data for the ingredient
  final Map<String, dynamic>? additionalData;

  IngredientConfig({
    this.title,
    this.relationship = Relationship.componentOf,
    this.thumbnail,
    this.additionalData,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'relationship': relationship.toJson()};
    if (title != null) map['title'] = title;
    if (additionalData != null) map.addAll(additionalData!);
    return map;
  }

  String toJson() => jsonEncode(toMap());
}

/// Configuration for adding an action to a builder
class ActionConfig {
  /// The action identifier (e.g., "c2pa.created", "c2pa.edited")
  final String action;

  /// When the action occurred
  final DateTime? when;

  /// Software agent that performed the action
  final String? softwareAgent;

  /// Digital source type
  final DigitalSourceType? digitalSourceType;

  /// Additional parameters
  final Map<String, dynamic>? parameters;

  ActionConfig({
    required this.action,
    this.when,
    this.softwareAgent,
    this.digitalSourceType,
    this.parameters,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'action': action};
    if (when != null) map['when'] = when!.toIso8601String();
    if (softwareAgent != null) map['softwareAgent'] = softwareAgent;
    if (digitalSourceType != null) {
      map['digitalSourceType'] = digitalSourceType!.url;
    }
    if (parameters != null) map['parameters'] = parameters;
    return map;
  }

  String toJson() => jsonEncode(toMap());
}

/// Options for building manifests
class BuilderOptions {
  /// The intent for this manifest
  final ManifestIntent? intent;

  /// Digital source type (required for create intent)
  final DigitalSourceType? digitalSourceType;

  /// Whether to embed the manifest in the asset
  final bool embed;

  /// Remote URL for cloud-based manifests
  final String? remoteUrl;

  const BuilderOptions({
    this.intent,
    this.digitalSourceType,
    this.embed = true,
    this.remoteUrl,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'embed': embed,
    };
    if (intent != null) map['intent'] = intent!.name;
    if (digitalSourceType != null) map['digitalSourceType'] = digitalSourceType!.url;
    if (remoteUrl != null) map['remoteUrl'] = remoteUrl;
    return map;
  }
}

/// Result from builder sign operations
class BuilderSignResult {
  /// The signed asset data
  final Uint8List signedData;

  /// The manifest bytes (if available)
  final Uint8List? manifestBytes;

  /// Size of the C2PA manifest data
  final int manifestSize;

  BuilderSignResult({
    required this.signedData,
    this.manifestBytes,
    required this.manifestSize,
  });
}

/// Archive data from a builder (for serialization)
class BuilderArchive {
  /// The archive data
  final Uint8List data;

  BuilderArchive({required this.data});
}

// =============================================================================
// ManifestBuilder - Abstract interface for building manifests
// =============================================================================

/// Builder for constructing C2PA manifests.
///
/// Use [C2pa.createBuilder] to create a new builder instance. The builder
/// follows a fluent API pattern where you configure the manifest and then
/// sign it.
///
/// ## Basic Usage
///
/// The manifest JSON passed to [C2pa.createBuilder] should contain the title,
/// claim_generator, and any assertions. These cannot be modified after builder
/// creation as the native C2PA libraries don't support dynamic modification.
///
/// ```dart
/// final manifestJson = jsonEncode({
///   'title': 'My Photo',
///   'claim_generator': 'MyApp/1.0',
///   'assertions': [
///     {
///       'label': 'c2pa.actions',
///       'data': {
///         'actions': [
///           {'action': 'c2pa.created', 'digitalSourceType': '...'}
///         ]
///       }
///     }
///   ]
/// });
///
/// final builder = await c2pa.createBuilder(manifestJson);
///
/// // Set the intent (required)
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
///
/// // Sign and get result
/// final result = await builder.sign(
///   sourceData: imageBytes,
///   mimeType: 'image/jpeg',
///   signerInfo: signerInfo,
/// );
///
/// // Always dispose when done
/// builder.dispose();
/// ```
///
/// ## Adding Ingredients
///
/// For edit operations, add parent or component ingredients:
///
/// ```dart
/// builder.setIntent(ManifestIntent.edit);
/// await builder.addIngredient(
///   data: parentImageBytes,
///   mimeType: 'image/jpeg',
///   config: IngredientConfig(relationship: Relationship.parentOf),
/// );
/// ```
///
/// ## Important
///
/// Always call [dispose] when finished to release native resources.
abstract class ManifestBuilder {
  /// The unique handle for this builder (for internal use)
  int get handle;

  /// Set the builder intent
  void setIntent(ManifestIntent intent, [DigitalSourceType? digitalSourceType]);

  /// Disable embedding the manifest in the asset
  void setNoEmbed();

  /// Set a remote URL for cloud-based manifests
  void setRemoteUrl(String url);

  /// Add a resource (thumbnail, icon, etc.)
  Future<void> addResource(BuilderResource resource);

  /// Add an ingredient from data
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  });

  /// Add an action to the manifest
  void addAction(ActionConfig action);

  /// Export the builder to an archive for later use
  Future<BuilderArchive> toArchive();

  /// Sign the manifest and embed it in the source data
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    required C2paSigner signer,
  });

  /// Dispose of native resources
  void dispose();
}

// =============================================================================
// C2PASettings - Handle-based settings object
// =============================================================================

/// Handle-based C2PA settings for configuring readers, builders, and signers.
///
/// Use [C2paSettings.create] to create a new settings instance, then
/// configure it with [updateFromString] or [setValue].
///
/// ## Example
///
/// ```dart
/// final settings = await C2paSettings.create();
/// await settings.updateFromString('{"version": 1, "verify": {"verify_trust": false}}', 'json');
/// await settings.setValue('verify.verify_after_sign', 'true');
///
/// // Use with context or builder
/// final context = await C2paContext.fromSettings(settings);
///
/// // Always dispose when done
/// settings.dispose();
/// ```
class C2paSettings {
  final int _handle;
  bool _disposed = false;

  C2paSettings._(this._handle);

  /// The native handle for this settings object (for internal use).
  int get handle => _handle;

  /// Create a new empty settings instance with defaults.
  static Future<C2paSettings> create() async {
    final handle = await C2paPlatform.instance.createSettings();
    return C2paSettings._(handle);
  }

  /// Update settings from a JSON or TOML string.
  ///
  /// The [format] should be 'json' or 'toml'.
  Future<void> updateFromString(String settings, String format) {
    _checkDisposed();
    return C2paPlatform.instance.settingsUpdateFromString(
      _handle,
      settings,
      format,
    );
  }

  /// Set an individual setting value using dot notation.
  ///
  /// Example: `await settings.setValue('verify.verify_trust', 'false');`
  Future<void> setValue(String path, String value) {
    _checkDisposed();
    return C2paPlatform.instance.settingsSetValue(_handle, path, value);
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('C2paSettings has been disposed');
    }
  }

  /// Dispose of native resources.
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      C2paPlatform.instance.settingsDispose(_handle);
    }
  }
}

// =============================================================================
// C2PAContext - Handle-based shared configuration context
// =============================================================================

/// Shared configuration context for creating readers and builders.
///
/// A context encapsulates settings and can be shared across multiple
/// Reader and Builder instances.
///
/// ## Example
///
/// ```dart
/// // Default context
/// final context = await C2paContext.create();
///
/// // Context with custom settings
/// final settings = await C2paSettings.create();
/// await settings.updateFromString(settingsJson, 'json');
/// final context = await C2paContext.fromSettings(settings);
///
/// // Use with reader or builder
/// final store = await c2pa.readManifestFromFileWithContext('/path', context);
/// final builder = await c2pa.createBuilderFromContext(context, manifestJson);
///
/// // Always dispose when done
/// context.dispose();
/// ```
class C2paContext {
  final int _handle;
  bool _disposed = false;

  C2paContext._(this._handle);

  /// The native handle for this context (for internal use).
  int get handle => _handle;

  /// Create a new context with default settings.
  static Future<C2paContext> create() async {
    final handle = await C2paPlatform.instance.createContext();
    return C2paContext._(handle);
  }

  /// Create a context from custom settings.
  static Future<C2paContext> fromSettings(C2paSettings settings) async {
    settings._checkDisposed();
    final handle = await C2paPlatform.instance.createContextFromSettings(
      settings._handle,
    );
    return C2paContext._(handle);
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('C2paContext has been disposed');
    }
  }

  /// Dispose of native resources.
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      C2paPlatform.instance.contextDispose(_handle);
    }
  }
}

// =============================================================================
// Certificate Config
// =============================================================================

/// Configuration for X.509 certificate generation
class CertificateConfig {
  final String commonName;
  final String? organization;
  final String? organizationalUnit;
  final String? country;
  final String? state;
  final String? locality;
  final String? email;
  final int? validityDays;

  const CertificateConfig({
    required this.commonName,
    this.organization,
    this.organizationalUnit,
    this.country,
    this.state,
    this.locality,
    this.email,
    this.validityDays,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'commonName': commonName};
    if (organization != null) map['organization'] = organization;
    if (organizationalUnit != null) {
      map['organizationalUnit'] = organizationalUnit;
    }
    if (country != null) map['country'] = country;
    if (state != null) map['state'] = state;
    if (locality != null) map['locality'] = locality;
    if (email != null) map['email'] = email;
    if (validityDays != null) map['validityDays'] = validityDays;
    return map;
  }
}

// =============================================================================
// C2PA Main Class
// =============================================================================

/// Main entry point for C2PA operations.
///
/// This class provides all functionality for reading and creating C2PA
/// content credentials (manifests) in Flutter applications.
///
/// ## Usage
///
/// Create a single instance and reuse it throughout your application:
///
/// ```dart
/// final c2pa = C2pa();
/// ```
///
/// ## Reading Manifests
///
/// Use [readFile] or [readBytes] for raw JSON, or [readManifestFromFile]
/// and [readManifestFromBytes] for parsed [ManifestStoreInfo] objects:
///
/// ```dart
/// final store = await c2pa.readManifestFromFile('/path/to/image.jpg');
/// if (store != null && store.validationStatus == ValidationStatus.valid) {
///   print('Valid manifest from: ${store.active?.claimGenerator}');
/// }
/// ```
///
/// ## Creating Manifests
///
/// Use [createBuilder] to construct manifests with the builder pattern:
///
/// ```dart
/// final builder = await c2pa.createBuilder('{"title": "My Image"}');
/// builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
/// final result = await builder.sign(...);
/// builder.dispose();
/// ```
///
/// ## See Also
///
/// - [ManifestBuilder] for manifest creation
/// - [ManifestStoreInfo] for reading manifest data
/// - [C2paSigner] for signing configuration
class C2pa {
  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  /// Get the platform version (iOS/Android version)
  Future<String?> getPlatformVersion() {
    return C2paPlatform.instance.getPlatformVersion();
  }

  /// Get the C2PA library version
  Future<String?> getVersion() {
    return C2paPlatform.instance.getVersion();
  }

  // ===========================================================================
  // Reader API - Basic
  // ===========================================================================

  /// Read C2PA manifest from a file path
  ///
  /// Returns the manifest JSON string, or null if no manifest found.
  Future<String?> readFile(String path) {
    return C2paPlatform.instance.readFile(path);
  }

  /// Read C2PA manifest from byte data
  ///
  /// Returns the manifest JSON string, or null if no manifest found.
  Future<String?> readBytes(Uint8List data, String mimeType) {
    return C2paPlatform.instance.readBytes(data, mimeType);
  }

  // ===========================================================================
  // Reader API - Enhanced
  // ===========================================================================

  /// Read manifest from a file with detailed information
  ///
  /// Returns a [ManifestStoreInfo] with parsed manifest data and validation info.
  Future<ManifestStoreInfo?> readManifestFromFile(
    String path, {
    ReaderOptions options = const ReaderOptions(),
  }) async {
    final json = await C2paPlatform.instance.readFileDetailed(
      path,
      options.detailed,
      options.dataDir,
    );
    if (json == null) return null;
    return ManifestStoreInfo.fromJson(json);
  }

  /// Read manifest from bytes with detailed information
  ///
  /// Returns a [ManifestStoreInfo] with parsed manifest data and validation info.
  Future<ManifestStoreInfo?> readManifestFromBytes(
    Uint8List data,
    String mimeType, {
    ReaderOptions options = const ReaderOptions(),
  }) async {
    final json = await C2paPlatform.instance.readBytesDetailed(
      data,
      mimeType,
      options.detailed,
    );
    if (json == null) return null;
    return ManifestStoreInfo.fromJson(json);
  }

  /// Extract a resource (thumbnail, etc.) from manifest data
  ///
  /// The [uri] should match an identifier from the manifest JSON.
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) {
    return C2paPlatform.instance.extractResource(data, mimeType, uri);
  }

  /// Read ingredient information from a file
  ///
  /// Returns JSON string with ingredient data.
  Future<String?> readIngredientFromFile(String path, {String? dataDir}) {
    return C2paPlatform.instance.readIngredientFile(path, dataDir);
  }

  /// Get supported MIME types for reading
  Future<List<String>> getSupportedReadMimeTypes() {
    return C2paPlatform.instance.getSupportedReadMimeTypes();
  }

  /// Get supported MIME types for signing
  Future<List<String>> getSupportedSignMimeTypes() {
    return C2paPlatform.instance.getSupportedSignMimeTypes();
  }

  // ===========================================================================
  // Signer API - Basic
  // ===========================================================================

  /// Sign image bytes with a C2PA manifest
  ///
  /// Returns a [SignResult] with the signed data and optional manifest bytes.
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) {
    return C2paPlatform.instance.signBytes(
      sourceData: sourceData,
      mimeType: mimeType,
      manifestJson: manifestJson,
      signer: signer,
    );
  }

  /// Sign a file with a C2PA manifest
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) {
    return C2paPlatform.instance.signFile(
      sourcePath: sourcePath,
      destPath: destPath,
      manifestJson: manifestJson,
      signer: signer,
    );
  }

  // ===========================================================================
  // Builder API
  // ===========================================================================

  /// Create a new manifest builder from a JSON manifest definition
  Future<ManifestBuilder> createBuilder(String manifestJson) {
    return C2paPlatform.instance.createBuilder(manifestJson);
  }

  /// Create a manifest builder from a previously saved archive
  Future<ManifestBuilder> createBuilderFromArchive(Uint8List archiveData) {
    return C2paPlatform.instance.createBuilderFromArchive(archiveData);
  }

  // ===========================================================================
  // Advanced Signing API
  // ===========================================================================

  /// Create a hashed placeholder for later signing
  ///
  /// This is used for advanced signing workflows where the asset
  /// needs to be prepared before the actual signing occurs.
  Future<Uint8List> createHashedPlaceholder({
    required ManifestBuilder builder,
    required int reservedSize,
    required String mimeType,
  }) {
    return C2paPlatform.instance.createHashedPlaceholder(
      builderHandle: builder.handle,
      reservedSize: reservedSize,
      mimeType: mimeType,
    );
  }

  /// Sign a data-hashed embeddable manifest
  ///
  /// This is used after createHashedPlaceholder for advanced signing workflows.
  Future<Uint8List> signHashedEmbeddable({
    required ManifestBuilder builder,
    required C2paSigner signer,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) {
    return C2paPlatform.instance.signHashedEmbeddable(
      builderHandle: builder.handle,
      signer: signer,
      dataHash: dataHash,
      mimeType: mimeType,
      assetData: assetData,
    );
  }

  /// Convert raw manifest bytes to an embeddable format
  ///
  /// A raw manifest (application/c2pa format) cannot be embedded directly.
  /// This converts it to an embeddable format for the specified MIME type.
  ///
  /// **Android note**: This method returns the input unchanged on Android as
  /// the native library does not support this operation. The manifest bytes
  /// from [signHashedEmbeddable] are already in the correct format on Android.
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) {
    return C2paPlatform.instance.formatEmbeddable(
      mimeType: mimeType,
      manifestBytes: manifestBytes,
    );
  }

  /// Get the reserve size needed for a signer
  ///
  /// This is useful for pre-allocating space in assets for the signature.
  /// Note: Only works with [PemSigner] as other signer types need to connect
  /// to their backing stores to determine reserve size.
  Future<int> getSignerReserveSize(C2paSigner signer) {
    return C2paPlatform.instance.getSignerReserveSize(signer);
  }

  // ===========================================================================
  // Key Management API
  // ===========================================================================

  /// Check if hardware-backed signing is available on this device.
  ///
  /// Returns true if:
  /// - Android: StrongBox is available (Android 9.0+ with hardware support)
  /// - iOS: Secure Enclave is available (iPhone 5s+, not in Simulator)
  Future<bool> isHardwareSigningAvailable() {
    return C2paPlatform.instance.isHardwareSigningAvailable();
  }

  /// Create a new key in the platform's secure storage.
  ///
  /// For [KeystoreSigner]: Creates a key in Android Keystore or iOS Keychain.
  /// For [HardwareSigner]: Creates a key in StrongBox or Secure Enclave.
  ///
  /// The [algorithm] parameter is ignored for hardware keys (always ES256).
  ///
  /// Throws if the key already exists or cannot be created.
  Future<void> createKey({
    required String keyAlias,
    SigningAlgorithm algorithm = SigningAlgorithm.es256,
    bool useHardware = false,
  }) {
    return C2paPlatform.instance.createKey(
      keyAlias: keyAlias,
      algorithm: algorithm,
      useHardware: useHardware,
    );
  }

  /// Delete a key from the platform's secure storage.
  ///
  /// Returns true if the key was deleted, false if it didn't exist.
  Future<bool> deleteKey(String keyAlias) {
    return C2paPlatform.instance.deleteKey(keyAlias);
  }

  /// Check if a key exists in the platform's secure storage.
  Future<bool> keyExists(String keyAlias) {
    return C2paPlatform.instance.keyExists(keyAlias);
  }

  /// Export the public key for a stored key as PEM.
  ///
  /// This is useful for obtaining the public key to send to a CA for
  /// certificate enrollment.
  Future<String> exportPublicKey(String keyAlias) {
    return C2paPlatform.instance.exportPublicKey(keyAlias);
  }

  /// Import a private key and certificate chain into the platform's keystore.
  ///
  /// This allows using externally generated keys (e.g., test certificates)
  /// with the Keystore signer. The private key must be in PKCS#8 PEM format.
  ///
  /// Note: On Android, this imports into AndroidKeyStore. The key will not
  /// have hardware protection even if StrongBox is available.
  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) {
    return C2paPlatform.instance.importKey(
      keyAlias: keyAlias,
      privateKeyPem: privateKeyPem,
      certificateChainPem: certificateChainPem,
    );
  }

  /// Create a Certificate Signing Request (CSR) for a hardware-backed key.
  ///
  /// The key must already exist in the platform keystore (created via [createKey]).
  /// Returns a PEM-encoded CSR that can be submitted to a signing server.
  Future<String> createCSR({
    required String keyAlias,
    required String commonName,
    String? organization,
    String? organizationalUnit,
    String? country,
    String? state,
    String? locality,
  }) {
    return C2paPlatform.instance.createCSR(
      keyAlias: keyAlias,
      commonName: commonName,
      organization: organization,
      organizationalUnit: organizationalUnit,
      country: country,
      state: state,
      locality: locality,
    );
  }

  /// Enroll a hardware-backed key with a signing server.
  ///
  /// This creates a hardware key (if it doesn't exist), generates a CSR,
  /// submits it to the signing server, and returns the certificate chain.
  ///
  /// Returns a map containing:
  /// - `certificateChain`: The PEM-encoded certificate chain from the server
  /// - `keyAlias`: The key alias used
  Future<Map<String, dynamic>> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) {
    return C2paPlatform.instance.enrollHardwareKey(
      keyAlias: keyAlias,
      signingServerUrl: signingServerUrl,
      bearerToken: bearerToken,
      commonName: commonName,
      organization: organization,
      useStrongBox: useStrongBox,
    );
  }

  // ===========================================================================
  // Settings API
  // ===========================================================================

  /// Load C2PA settings from a configuration string
  ///
  /// The [format] should be "json" or "toml".
  Future<void> loadSettings(String settings, {String format = 'json'}) {
    return C2paPlatform.instance.loadSettings(settings, format);
  }

  // ===========================================================================
  // Enhanced Reader API
  // ===========================================================================

  /// Read manifest from a file using a shared [C2paContext].
  ///
  /// This allows reading with custom settings configured via
  /// [C2paSettings] and [C2paContext].
  Future<ManifestStoreInfo?> readManifestFromFileWithContext(
    String path,
    C2paContext context, {
    ReaderOptions options = const ReaderOptions(),
  }) async {
    context._checkDisposed();
    final json = await C2paPlatform.instance.readFileWithContext(
      path,
      context._handle,
      options.detailed,
      options.dataDir,
    );
    if (json == null) return null;
    return ManifestStoreInfo.fromJson(json);
  }

  // ===========================================================================
  // Enhanced Builder API
  // ===========================================================================

  /// Create a builder from a shared [C2paContext].
  ///
  /// The context provides shared configuration for the builder.
  Future<ManifestBuilder> createBuilderFromContext(
    C2paContext context,
    String manifestJson,
  ) {
    context._checkDisposed();
    return C2paPlatform.instance.createBuilderWithContext(
      context._handle,
      manifestJson,
    );
  }

  /// Create a builder with custom [C2paSettings] and auto-validation.
  ///
  /// The settings provide configuration for the builder, and the manifest
  /// JSON is automatically validated against the C2PA spec.
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    C2paSettings settings,
  ) {
    settings._checkDisposed();
    return C2paPlatform.instance.createBuilderWithSettings(
      manifestJson,
      settings._handle,
    );
  }

  // ===========================================================================
  // Certificate Manager API
  // ===========================================================================

  /// Create a self-signed certificate chain for testing.
  ///
  /// Generates a 3-tier certificate chain (root CA, intermediate, end-entity)
  /// bound to the key identified by [keyAlias].
  ///
  /// Returns the PEM-encoded certificate chain.
  ///
  /// Note: On iOS, this uses the CertificateManager from c2pa-ios.
  /// On Android, availability depends on the native library.
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    CertificateConfig? config,
  }) {
    return C2paPlatform.instance.createSelfSignedCertificateChain(
      keyAlias: keyAlias,
      config: config?.toMap(),
    );
  }
}
