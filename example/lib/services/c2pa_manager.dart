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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:c2pa_flutter/c2pa.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:asn1lib/asn1lib.dart' as asn1;

/// Signing modes available in the example app
enum SigningMode {
  /// Use bundled test certificates (PEM)
  defaultCerts('Default Certificates', 'Use included test certificates for development'),

  /// User-provided PEM certificate and key
  customPem('Custom PEM', 'Use your own certificate and private key'),

  /// Callback-based signing (demo)
  callback('Callback Signer', 'Demo callback-based signing with test certificates'),

  /// Platform keystore (Android Keystore / iOS Keychain)
  keystore('Keystore', 'Use platform keystore (Android Keystore / iOS Keychain)'),

  /// Hardware-backed signing (StrongBox / Secure Enclave)
  hardware('Hardware Security', 'Use hardware-backed signing (StrongBox / Secure Enclave)'),

  /// Remote signing service
  remote('Remote Signing', 'Use a remote signing service'),

  /// Settings-based signer (JSON/TOML configuration)
  settingsSigner('Settings Signer', 'Use a JSON/TOML settings configuration for signing');

  final String title;
  final String description;

  const SigningMode(this.title, this.description);
}

class C2paManager extends ChangeNotifier {
  static final C2paManager _instance = C2paManager._internal();
  factory C2paManager() => _instance;
  C2paManager._internal() {
    _loadPreferences();
  }

  final C2pa _c2pa = C2pa();

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _lastError;
  String? get lastError => _lastError;

  // Current signing mode
  SigningMode _signingMode = SigningMode.defaultCerts;
  SigningMode get signingMode => _signingMode;
  set signingMode(SigningMode mode) {
    _signingMode = mode;
    _savePreferences();
    notifyListeners();
  }

  // Cached default credentials loaded from assets
  String? _defaultCertificate;
  String? _defaultPrivateKey;

  // Custom PEM credentials
  String? _customCertificate;
  String? _customPrivateKey;

  // Keystore configuration
  String _keystoreKeyAlias = 'c2pa_signing_key';
  String? _keystoreCertificateChain;
  String get keystoreKeyAlias => _keystoreKeyAlias;
  String? get keystoreCertificateChain => _keystoreCertificateChain;
  bool get hasKeystoreConfig => _keystoreCertificateChain != null;

  // Hardware signer configuration
  String _hardwareKeyAlias = 'c2pa_hardware_key';
  String? _hardwareCertificateChain;
  bool _requireBiometric = false;
  String get hardwareKeyAlias => _hardwareKeyAlias;
  String? get hardwareCertificateChain => _hardwareCertificateChain;
  bool get requireBiometric => _requireBiometric;
  bool get hasHardwareConfig => _hardwareCertificateChain != null;

  // Remote signer configuration
  String? _remoteUrl;
  String? _bearerToken;
  String? get remoteUrl => _remoteUrl;
  String? get bearerToken => _bearerToken;
  bool get hasRemoteConfig => _remoteUrl != null && _remoteUrl!.isNotEmpty;

  // Settings signer configuration
  String? _settingsSignerJson;
  String _settingsSignerFormat = 'json';
  String? get settingsSignerJson => _settingsSignerJson;
  String get settingsSignerFormat => _settingsSignerFormat;
  bool get hasSettingsSignerConfig =>
      _settingsSignerJson != null && _settingsSignerJson!.isNotEmpty;

  // Hardware availability cache
  bool? _hardwareAvailable;

  /// Load preferences from storage
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final modeIndex = prefs.getInt('signingMode') ?? 0;
      if (modeIndex >= 0 && modeIndex < SigningMode.values.length) {
        _signingMode = SigningMode.values[modeIndex];
      }

      _customCertificate = prefs.getString('customCertificate');
      _customPrivateKey = prefs.getString('customPrivateKey');

      _keystoreKeyAlias = prefs.getString('keystoreKeyAlias') ?? 'c2pa_signing_key';
      _keystoreCertificateChain = prefs.getString('keystoreCertificateChain');

      _hardwareKeyAlias = prefs.getString('hardwareKeyAlias') ?? 'c2pa_hardware_key';
      _hardwareCertificateChain = prefs.getString('hardwareCertificateChain');
      _requireBiometric = prefs.getBool('requireBiometric') ?? false;

      _remoteUrl = prefs.getString('remoteUrl');
      _bearerToken = prefs.getString('bearerToken');

      _settingsSignerJson = prefs.getString('settingsSignerJson');
      _settingsSignerFormat = prefs.getString('settingsSignerFormat') ?? 'json';

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load preferences: $e');
    }
  }

  /// Save preferences to storage
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('signingMode', _signingMode.index);

      if (_customCertificate != null) {
        await prefs.setString('customCertificate', _customCertificate!);
      }
      if (_customPrivateKey != null) {
        await prefs.setString('customPrivateKey', _customPrivateKey!);
      }

      await prefs.setString('keystoreKeyAlias', _keystoreKeyAlias);
      if (_keystoreCertificateChain != null) {
        await prefs.setString('keystoreCertificateChain', _keystoreCertificateChain!);
      }

      await prefs.setString('hardwareKeyAlias', _hardwareKeyAlias);
      if (_hardwareCertificateChain != null) {
        await prefs.setString('hardwareCertificateChain', _hardwareCertificateChain!);
      }
      await prefs.setBool('requireBiometric', _requireBiometric);

      if (_remoteUrl != null) {
        await prefs.setString('remoteUrl', _remoteUrl!);
      }
      if (_bearerToken != null) {
        await prefs.setString('bearerToken', _bearerToken!);
      }

      if (_settingsSignerJson != null) {
        await prefs.setString('settingsSignerJson', _settingsSignerJson!);
      }
      await prefs.setString('settingsSignerFormat', _settingsSignerFormat);
    } catch (e) {
      debugPrint('Failed to save preferences: $e');
    }
  }

  void setCustomCredentials(String certificate, String privateKey) {
    _customCertificate = certificate;
    _customPrivateKey = privateKey;
    _savePreferences();
    notifyListeners();
  }

  bool get hasCustomCredentials =>
      _customCertificate != null && _customPrivateKey != null;

  void setKeystoreConfig({
    required String keyAlias,
    required String certificateChainPem,
  }) {
    _keystoreKeyAlias = keyAlias;
    _keystoreCertificateChain = certificateChainPem;
    _savePreferences();
    notifyListeners();
  }

  void setHardwareConfig({
    required String keyAlias,
    required String certificateChainPem,
    bool requireBiometric = false,
  }) {
    _hardwareKeyAlias = keyAlias;
    _hardwareCertificateChain = certificateChainPem;
    _requireBiometric = requireBiometric;
    _savePreferences();
    notifyListeners();
  }

  void setRemoteConfig({
    required String url,
    String? bearerToken,
  }) {
    _remoteUrl = url;
    _bearerToken = bearerToken;
    _savePreferences();
    notifyListeners();
  }

  void clearRemoteConfig() {
    _remoteUrl = null;
    _bearerToken = null;
    _savePreferences();
    notifyListeners();
  }

  void setSettingsSignerConfig({
    required String settingsJson,
    String format = 'json',
  }) {
    _settingsSignerJson = settingsJson;
    _settingsSignerFormat = format;
    _savePreferences();
    notifyListeners();
  }

  void clearSettingsSignerConfig() {
    _settingsSignerJson = null;
    _settingsSignerFormat = 'json';
    _savePreferences();
    notifyListeners();
  }

  /// Check if the current signing mode is ready to sign
  bool get isConfigured {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        return true; // Always ready
      case SigningMode.customPem:
        return hasCustomCredentials;
      case SigningMode.callback:
        return true; // Uses default certs for demo
      case SigningMode.keystore:
        return hasKeystoreConfig;
      case SigningMode.hardware:
        return hasHardwareConfig;
      case SigningMode.remote:
        return hasRemoteConfig;
      case SigningMode.settingsSigner:
        return hasSettingsSignerConfig;
    }
  }

  Future<String?> getVersion() async {
    return await _c2pa.getVersion();
  }

  Future<String?> readManifest(String path) async {
    try {
      return await _c2pa.readFile(path);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<String?> readManifestFromBytes(
      Uint8List data, String mimeType) async {
    try {
      return await _c2pa.readBytes(data, mimeType);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Read manifest with structured data
  Future<ManifestStoreInfo?> readManifestEnhanced(String path) async {
    try {
      final json = await _c2pa.readFile(path);
      if (json == null) return null;
      debugPrint('C2PA readFile JSON keys: ${(jsonDecode(json) as Map<String, dynamic>).keys.toList()}');
      final store = ManifestStoreInfo.fromJson(json);
      debugPrint('C2PA parsed: active=${store.activeManifest}, manifests=${store.manifests.length}, status=${store.validationStatus}');
      return store;
    } catch (e) {
      debugPrint('C2PA readManifestEnhanced error: $e');
      _lastError = e.toString();
      return null;
    }
  }

  /// Check if hardware signing is available on this device
  Future<bool> isHardwareSigningAvailable() async {
    if (_hardwareAvailable != null) {
      return _hardwareAvailable!;
    }
    try {
      _hardwareAvailable = await _c2pa.isHardwareSigningAvailable();
      return _hardwareAvailable!;
    } catch (e) {
      debugPrint('Failed to check hardware signing availability: $e');
      _hardwareAvailable = false;
      return false;
    }
  }

  /// Create a hardware-backed key
  Future<bool> createHardwareKey(String keyAlias) async {
    try {
      await _c2pa.createKey(
        keyAlias: keyAlias,
        useHardware: true,
      );
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Create a software keystore key
  Future<bool> createKeystoreKey(String keyAlias) async {
    try {
      await _c2pa.createKey(
        keyAlias: keyAlias,
        useHardware: false,
      );
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Check if a key exists
  Future<bool> keyExists(String keyAlias) async {
    try {
      return await _c2pa.keyExists(keyAlias);
    } catch (e) {
      debugPrint('Failed to check key existence: $e');
      return false;
    }
  }

  /// Export public key for a given alias
  Future<String?> exportPublicKey(String keyAlias) async {
    try {
      return await _c2pa.exportPublicKey(keyAlias);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Delete a key
  Future<bool> deleteKey(String keyAlias) async {
    try {
      await _c2pa.deleteKey(keyAlias);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Load default credentials from assets
  Future<void> _loadDefaultCredentials() async {
    if (_defaultCertificate != null && _defaultPrivateKey != null) {
      return;
    }

    try {
      _defaultCertificate =
          await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
      _defaultPrivateKey =
          await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
    } catch (e) {
      debugPrint('Failed to load default credentials from assets: $e');
      _lastError = 'Failed to load signing credentials';
    }
  }

  /// Sign an image as a new digital capture
  Future<Uint8List?> signImage(Uint8List imageData, String mimeType) async {
    return signImageAsCapture(
      imageData: imageData,
      mimeType: mimeType,
      title: 'Signed Image',
    );
  }

  /// Sign an image as a new digital capture (camera photo)
  Future<Uint8List?> signImageAsCapture({
    required Uint8List imageData,
    required String mimeType,
    required String title,
    String? author,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    ManifestBuilder? builder;
    try {
      final signer = await _getSigner();
      if (signer == null) {
        _lastError = 'No signing credentials available. Please configure in Settings.';
        return null;
      }

      // Create manifest for a new digital capture using type-safe API
      final manifest = ManifestDefinition.created(
        title: title,
        claimGenerator: ClaimGeneratorInfo(
          name: 'C2PA Flutter Example',
          version: '1.0.0',
        ),
        sourceType: DigitalSourceType.digitalCapture,
        additionalAssertions: [
          if (author != null)
            CreativeWorkAssertion(author: author),
        ],
      );

      builder = await _c2pa.createBuilder(manifest.toJsonString());
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      final result = await builder.sign(
        sourceData: imageData,
        mimeType: mimeType,
        signer: signer,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      builder?.dispose();
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Sign an image as edited content
  Future<Uint8List?> signImageAsEdited({
    required Uint8List imageData,
    required String mimeType,
    required String title,
    List<String>? editOperations,
    String? author,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    ManifestBuilder? builder;
    try {
      final signer = await _getSigner();
      if (signer == null) {
        _lastError = 'No signing credentials available. Please configure in Settings.';
        return null;
      }

      // Build list of actions based on edit operations
      final actions = <Action>[];
      for (final op in editOperations ?? ['edited']) {
        switch (op.toLowerCase()) {
          case 'cropped':
            actions.add(Action.cropped(
              softwareAgent: 'C2PA Flutter Example/1.0.0',
              when: DateTime.now().toUtc().toIso8601String(),
            ));
            break;
          case 'filtered':
            actions.add(Action.filtered(
              softwareAgent: 'C2PA Flutter Example/1.0.0',
              when: DateTime.now().toUtc().toIso8601String(),
            ));
            break;
          case 'resized':
            actions.add(Action.resized(
              softwareAgent: 'C2PA Flutter Example/1.0.0',
              when: DateTime.now().toUtc().toIso8601String(),
            ));
            break;
          default:
            actions.add(Action.edited(
              softwareAgent: 'C2PA Flutter Example/1.0.0',
              when: DateTime.now().toUtc().toIso8601String(),
            ));
        }
      }

      // Create manifest for edited content
      final manifest = ManifestDefinition.edited(
        title: title,
        claimGenerator: ClaimGeneratorInfo(
          name: 'C2PA Flutter Example',
          version: '1.0.0',
        ),
        actions: actions.isEmpty ? null : actions,
        additionalAssertions: [
          if (author != null)
            CreativeWorkAssertion(author: author),
        ],
      );

      builder = await _c2pa.createBuilder(manifest.toJsonString());
      builder.setIntent(ManifestIntent.edit);

      final result = await builder.sign(
        sourceData: imageData,
        mimeType: mimeType,
        signer: signer,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      builder?.dispose();
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Sign an AI-generated image
  Future<Uint8List?> signImageAsAiGenerated({
    required Uint8List imageData,
    required String mimeType,
    required String title,
    String? modelName,
    String? prompt,
    bool allowAiTraining = false,
    bool allowDataMining = false,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    ManifestBuilder? builder;
    try {
      final signer = await _getSigner();
      if (signer == null) {
        _lastError = 'No signing credentials available. Please configure in Settings.';
        return null;
      }

      // Build parameters map
      final parameters = <String, String>{};
      if (modelName != null) parameters['model'] = modelName;
      if (prompt != null) parameters['prompt'] = prompt;

      // Build CAWG training/mining entries with extended fields
      final cawgTrainingMiningEntries = <CawgTrainingMiningEntry>[
        CawgTrainingMiningEntry(
          use: 'aiTraining',
          permission: allowAiTraining
              ? TrainingMiningPermission.allowed
              : TrainingMiningPermission.notAllowed,
          aiModelLearningType: 'supervised',
        ),
        CawgTrainingMiningEntry(
          use: 'aiGenerativeTraining',
          permission: allowAiTraining
              ? TrainingMiningPermission.allowed
              : TrainingMiningPermission.notAllowed,
          aiModelLearningType: 'generative',
        ),
        CawgTrainingMiningEntry(
          use: 'dataMining',
          permission: allowDataMining
              ? TrainingMiningPermission.allowed
              : TrainingMiningPermission.notAllowed,
          aiMiningType: 'contentAnalysis',
        ),
        const CawgTrainingMiningEntry(
          use: 'aiInference',
          permission: TrainingMiningPermission.allowed,
        ),
      ];

      // Create manifest with CAWG gathered assertions (proper placement per spec)
      final manifest = ManifestDefinition.withAssertions(
        title: title,
        claimGenerator: ClaimGeneratorInfo(
          name: 'C2PA Flutter Example',
          version: '1.0.0',
        ),
        createdAssertions: [
          ActionsAssertion(actions: [
            Action.created(
              softwareAgent: 'C2PA Flutter Example/1.0.0',
              when: DateTime.now().toUtc().toIso8601String(),
              sourceType: DigitalSourceType.trainedAlgorithmicMedia,
            ),
          ]),
        ],
        gatheredAssertions: [
          CawgTrainingMiningAssertion(entries: cawgTrainingMiningEntries),
        ],
      );

      builder = await _c2pa.createBuilder(manifest.toJsonString());
      builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.trainedAlgorithmicMedia,
      );

      final result = await builder.sign(
        sourceData: imageData,
        mimeType: mimeType,
        signer: signer,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      builder?.dispose();
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Sign an image with custom manifest configuration
  Future<Uint8List?> signImageWithManifest({
    required Uint8List imageData,
    required String mimeType,
    required ManifestDefinition manifest,
    ManifestIntent intent = ManifestIntent.create,
    DigitalSourceType? digitalSourceType,
  }) async {
    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    ManifestBuilder? builder;
    try {
      // Pre-flight manifest validation
      final validation = ManifestValidator.validate(manifest);
      if (validation.hasErrors) {
        _lastError = 'Manifest validation failed: ${validation.errors.join('; ')}';
        return null;
      }
      for (final warning in validation.warnings) {
        debugPrint('ManifestValidator warning: $warning');
      }

      final signer = await _getSigner();
      if (signer == null) {
        _lastError = 'No signing credentials available. Please configure in Settings.';
        return null;
      }

      // Use settings-aware builder when in settingsSigner mode
      if (_signingMode == SigningMode.settingsSigner &&
          _settingsSignerJson != null &&
          _settingsSignerFormat == 'json') {
        final settings = await C2paSettings.create();
        try {
          await settings.updateFromString(_settingsSignerJson!, 'json');
          builder = await _c2pa.createBuilderWithSettings(
            manifest.toJsonString(),
            settings,
          );
        } finally {
          settings.dispose();
        }
      } else {
        builder = await _c2pa.createBuilder(manifest.toJsonString());
      }
      builder.setIntent(intent, digitalSourceType);

      final result = await builder.sign(
        sourceData: imageData,
        mimeType: mimeType,
        signer: signer,
      );

      return result.signedData;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      builder?.dispose();
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<C2paSigner?> _getSigner() async {
    switch (_signingMode) {
      case SigningMode.defaultCerts:
        await _loadDefaultCredentials();
        if (_defaultCertificate == null || _defaultPrivateKey == null) {
          return null;
        }
        return PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _defaultCertificate!,
          privateKeyPem: _defaultPrivateKey!,
        );

      case SigningMode.customPem:
        if (_customCertificate == null || _customPrivateKey == null) {
          return null;
        }
        return PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: _customCertificate!,
          privateKeyPem: _customPrivateKey!,
        );

      case SigningMode.callback:
        // Demo callback signer using default credentials
        await _loadDefaultCredentials();
        if (_defaultCertificate == null || _defaultPrivateKey == null) {
          return null;
        }
        // For demo purposes, we create a CallbackSigner that uses the default
        // certificate chain but performs signing via a callback.
        // In a real app, this would be used for custom HSM integration, etc.
        return CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: _defaultCertificate!,
          signCallback: _demoSignCallback,
        );

      case SigningMode.keystore:
        if (_keystoreCertificateChain == null) {
          return null;
        }
        return KeystoreSigner(
          algorithm: SigningAlgorithm.es256,
          keyAlias: _keystoreKeyAlias,
          certificateChainPem: _keystoreCertificateChain!,
        );

      case SigningMode.hardware:
        if (_hardwareCertificateChain == null) {
          return null;
        }
        return HardwareSigner(
          keyAlias: _hardwareKeyAlias,
          certificateChainPem: _hardwareCertificateChain!,
          requireUserAuthentication: _requireBiometric,
        );

      case SigningMode.remote:
        if (_remoteUrl == null || _remoteUrl!.isEmpty) {
          return null;
        }
        return RemoteSigner(
          configurationUrl: _remoteUrl!,
          bearerToken: _bearerToken,
        );

      case SigningMode.settingsSigner:
        if (_settingsSignerJson == null || _settingsSignerJson!.isEmpty) {
          return null;
        }
        return SettingsSigner(
          settingsString: _settingsSignerJson!,
          format: _settingsSignerFormat,
        );
    }
  }

  /// Demo sign callback - demonstrates custom signing using pointycastle
  /// In a real app this would integrate with HSM or other custom signing infrastructure
  Future<Uint8List> _demoSignCallback(Uint8List data) async {
    debugPrint('CallbackSigner: Received ${data.length} bytes to sign');

    if (_defaultPrivateKey == null) {
      throw StateError('Private key not loaded');
    }

    // Sign directly - ECDSA is fast enough for main thread
    final result = _signDataSync(
      _SigningParams(data: data, privateKeyPem: _defaultPrivateKey!),
    );

    debugPrint('CallbackSigner: Generated ${result.length} byte signature');
    return result;
  }

}

/// Parameters for synchronous signing
class _SigningParams {
  final Uint8List data;
  final String privateKeyPem;

  _SigningParams({required this.data, required this.privateKeyPem});
}

/// Synchronous ECDSA signing using pointycastle
Uint8List _signDataSync(_SigningParams params) {
  // Parse the PKCS#8 private key
  final privateKey = _parsePrivateKeyStatic(params.privateKeyPem);

  // Hash the data with SHA-256 first
  final digest = pc.SHA256Digest();
  final hash = digest.process(params.data);

  // Create ECDSA signer with SHA-256
  // Use FortunaRandom as the secure random source
  final secureRandom = pc.FortunaRandom();
  final seedSource = Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));

  final signer = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
  signer.init(
    true,
    pc.ParametersWithRandom(
      pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey),
      secureRandom,
    ),
  );

  final signature = signer.generateSignature(hash) as pc.ECSignature;

  // Convert signature to DER format (as expected by C2PA)
  return _ecSignatureToDerStatic(signature);
}

/// Parse a PKCS#8 PEM private key into an ECPrivateKey (static version for isolate)
pc.ECPrivateKey _parsePrivateKeyStatic(String pem) {
  // Remove PEM headers and decode base64
  final lines = pem.split('\n')
      .where((line) => !line.startsWith('-----'))
      .join('');
  final bytes = base64.decode(lines);

  // Parse PKCS#8 structure
  final asn1Parser = asn1.ASN1Parser(bytes);
  final topSequence = asn1Parser.nextObject() as asn1.ASN1Sequence;

  // PKCS#8 structure: version, algorithmIdentifier, privateKey
  final privateKeyOctet = topSequence.elements[2] as asn1.ASN1OctetString;

  // Parse the EC private key from the octet string
  final ecParser = asn1.ASN1Parser(privateKeyOctet.contentBytes());
  final ecSequence = ecParser.nextObject() as asn1.ASN1Sequence;

  // EC private key structure: version, privateKey, [0] parameters, [1] publicKey
  final privateKeyBytes = (ecSequence.elements[1] as asn1.ASN1OctetString).contentBytes();
  final d = _bytesToBigIntStatic(Uint8List.fromList(privateKeyBytes));

  // Use P-256 curve parameters
  final domainParams = pc.ECDomainParameters('secp256r1');

  return pc.ECPrivateKey(d, domainParams);
}

/// Convert bytes to BigInt (static version for isolate)
BigInt _bytesToBigIntStatic(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (int i = 0; i < bytes.length; i++) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

/// Convert EC signature to DER format (static version for isolate)
Uint8List _ecSignatureToDerStatic(pc.ECSignature signature) {
  final r = _bigIntToBytesStatic(signature.r);
  final s = _bigIntToBytesStatic(signature.s);

  // DER encode: SEQUENCE { INTEGER r, INTEGER s }
  final rEncoded = _derEncodeIntegerStatic(r);
  final sEncoded = _derEncodeIntegerStatic(s);

  final contentLength = rEncoded.length + sEncoded.length;
  final result = BytesBuilder();

  // SEQUENCE tag
  result.addByte(0x30);
  // Length
  if (contentLength < 128) {
    result.addByte(contentLength);
  } else {
    result.addByte(0x81);
    result.addByte(contentLength);
  }
  // Content
  result.add(rEncoded);
  result.add(sEncoded);

  return result.toBytes();
}

/// Convert BigInt to bytes (static version for isolate)
Uint8List _bigIntToBytesStatic(BigInt value) {
  final bytes = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    bytes.insert(0, (v & BigInt.from(0xff)).toInt());
    v = v >> 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  return Uint8List.fromList(bytes);
}

/// DER encode an integer (static version for isolate)
Uint8List _derEncodeIntegerStatic(Uint8List bytes) {
  // Add leading zero if high bit is set (to keep it positive)
  final needsPadding = bytes.isNotEmpty && (bytes[0] & 0x80) != 0;
  final length = bytes.length + (needsPadding ? 1 : 0);

  final result = BytesBuilder();
  result.addByte(0x02); // INTEGER tag
  result.addByte(length);
  if (needsPadding) result.addByte(0x00);
  result.add(bytes);

  return result.toBytes();
}

