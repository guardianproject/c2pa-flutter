import 'dart:convert';
import 'dart:typed_data';

import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock implementation of C2paPlatform for testing
class MockC2paPlatform extends C2paPlatform with MockPlatformInterfaceMixin {
  // Configurable mock responses
  String platformVersion = 'Mock Platform 1.0';
  String c2paVersion = '1.0.0-mock';
  String? mockManifestJson;
  Uint8List? mockSignedData;
  Uint8List? mockManifestBytes;
  Uint8List? mockResourceData;
  List<String> supportedReadMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
  ];
  List<String> supportedSignMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
  ];
  int mockReserveSize = 10000;

  // Track method calls for verification
  final List<MockMethodCall> methodCalls = [];

  String mockCertificateChain =
      '-----BEGIN CERTIFICATE-----\n'
      'MIIBmjCCAUCgAwIBAgIUMockCertificate0001AAAAAAAAAAAA\n'
      'MAwxCjAIBgNVBAMMAUEwHhcNMjUwMTAxMDAwMDAwWhcNMjYw\n'
      'MTAxMDAwMDAwWjAMMQowCAYDVQQDDAFBMFkwEwYHKoZIzj0C\n'
      'AQYIKoZIzj0DAQcDQgAEMockPublicKeyDataAAAAAAAAAAAA\n'
      '-----END CERTIFICATE-----\n'
      '-----BEGIN CERTIFICATE-----\n'
      'MIIBmjCCAUCgAwIBAgIUMockCACertificate0001AAAAAAAAAA\n'
      'MAwxCjAIBgNVBAMMAUEwHhcNMjUwMTAxMDAwMDAwWhcNMjYw\n'
      'MTAxMDAwMDAwWjAMMQowCAYDVQQDDAFBMFkwEwYHKoZIzj0C\n'
      'AQYIKoZIzj0DAQcDQgAEMockCAPublicKeyDataAAAAAAAAAAAA\n'
      '-----END CERTIFICATE-----';

  // Builder tracking
  final Map<int, MockBuilder> builders = {};
  int _nextBuilderId = 1;

  // Settings tracking
  final Map<int, MockSettings> settings = {};
  int _nextSettingsId = 1;

  // Context tracking
  final Map<int, MockContext> contexts = {};
  int _nextContextId = 1;

  // Error simulation
  bool simulateError = false;
  String? errorMessage;

  void reset() {
    methodCalls.clear();
    builders.clear();
    _nextBuilderId = 1;
    settings.clear();
    _nextSettingsId = 1;
    contexts.clear();
    _nextContextId = 1;
    simulateError = false;
    errorMessage = null;
  }

  void _recordCall(String method, Map<String, dynamic>? arguments) {
    methodCalls.add(MockMethodCall(method, arguments));
  }

  void _checkError() {
    if (simulateError) {
      throw Exception(errorMessage ?? 'Simulated error');
    }
  }

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  @override
  Future<String?> getPlatformVersion() async {
    _recordCall('getPlatformVersion', null);
    _checkError();
    return platformVersion;
  }

  @override
  Future<String?> getVersion() async {
    _recordCall('getVersion', null);
    _checkError();
    return c2paVersion;
  }

  // ===========================================================================
  // Reader API - Basic
  // ===========================================================================

  @override
  Future<String?> readFile(String path) async {
    _recordCall('readFile', {'path': path});
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson(path);
  }

  @override
  Future<String?> readBytes(Uint8List data, String mimeType) async {
    _recordCall('readBytes', {'dataLength': data.length, 'mimeType': mimeType});
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson('bytes');
  }

  // ===========================================================================
  // Reader API - Enhanced
  // ===========================================================================

  @override
  Future<String?> readFileDetailed(
    String path,
    bool detailed,
    String? dataDir,
  ) async {
    _recordCall('readFileDetailed', {
      'path': path,
      'detailed': detailed,
      'dataDir': dataDir,
    });
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson(path);
  }

  @override
  Future<String?> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed,
  ) async {
    _recordCall('readBytesDetailed', {
      'dataLength': data.length,
      'mimeType': mimeType,
      'detailed': detailed,
    });
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson('bytes');
  }

  @override
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) async {
    _recordCall('extractResource', {
      'dataLength': data.length,
      'mimeType': mimeType,
      'uri': uri,
    });
    _checkError();
    return mockResourceData ??
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // Minimal JPEG header
  }

  @override
  Future<String?> readIngredientFile(String path, String? dataDir) async {
    _recordCall('readIngredientFile', {'path': path, 'dataDir': dataDir});
    _checkError();
    return jsonEncode({
      'title': 'Test Ingredient',
      'format': 'image/jpeg',
      'relationship': 'componentOf',
    });
  }

  @override
  Future<List<String>> getSupportedReadMimeTypes() async {
    _recordCall('getSupportedReadMimeTypes', null);
    _checkError();
    return supportedReadMimeTypes;
  }

  @override
  Future<List<String>> getSupportedSignMimeTypes() async {
    _recordCall('getSupportedSignMimeTypes', null);
    _checkError();
    return supportedSignMimeTypes;
  }

  // ===========================================================================
  // Signer API - Basic
  // ===========================================================================

  @override
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) async {
    _recordCall('signBytes', {
      'sourceDataLength': sourceData.length,
      'mimeType': mimeType,
      'manifestJson': manifestJson,
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
    });
    _checkError();

    return SignResult(
      signedData:
          mockSignedData ?? Uint8List.fromList([...sourceData, 0xC2, 0xAA]),
      manifestBytes: mockManifestBytes,
    );
  }

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) async {
    _recordCall('signFile', {
      'sourcePath': sourcePath,
      'destPath': destPath,
      'manifestJson': manifestJson,
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
    });
    _checkError();
  }

  // ===========================================================================
  // Builder API
  // ===========================================================================

  @override
  Future<ManifestBuilder> createBuilder(String manifestJson) async {
    _recordCall('createBuilder', {'manifestJson': manifestJson});
    _checkError();

    final handle = _nextBuilderId++;
    final builder = MockBuilder(this, handle, manifestJson);
    builders[handle] = builder;
    return builder;
  }

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData,
  ) async {
    _recordCall('createBuilderFromArchive', {
      'archiveDataLength': archiveData.length,
    });
    _checkError();

    final handle = _nextBuilderId++;
    final builder = MockBuilder(this, handle, '{}');
    builders[handle] = builder;
    return builder;
  }

  @override
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) async {
    _recordCall('builderSetIntent', {
      'handle': handle,
      'intent': intent.name,
      'digitalSourceType': digitalSourceType?.name,
    });
    _checkError();
    builders[handle]?.intent = intent;
    builders[handle]?.digitalSourceType = digitalSourceType;
  }

  @override
  Future<void> builderSetNoEmbed(int handle) async {
    _recordCall('builderSetNoEmbed', {'handle': handle});
    _checkError();
    builders[handle]?.noEmbed = true;
  }

  @override
  Future<void> builderSetRemoteUrl(int handle, String url) async {
    _recordCall('builderSetRemoteUrl', {'handle': handle, 'url': url});
    _checkError();
    builders[handle]?.remoteUrl = url;
  }

  @override
  Future<void> builderAddResource(
    int handle,
    String uri,
    Uint8List data,
  ) async {
    _recordCall('builderAddResource', {
      'handle': handle,
      'uri': uri,
      'dataLength': data.length,
    });
    _checkError();
    builders[handle]?.resources[uri] = data;
  }

  @override
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) async {
    _recordCall('builderAddIngredient', {
      'handle': handle,
      'dataLength': data.length,
      'mimeType': mimeType,
      'ingredientJson': ingredientJson,
    });
    _checkError();
    builders[handle]?.ingredients.add(
      MockIngredient(data, mimeType, ingredientJson),
    );
  }

  @override
  Future<void> builderAddAction(int handle, String actionJson) async {
    _recordCall('builderAddAction', {
      'handle': handle,
      'actionJson': actionJson,
    });
    _checkError();
    builders[handle]?.actions.add(actionJson);
  }

  @override
  Future<Uint8List> builderToArchive(int handle) async {
    _recordCall('builderToArchive', {'handle': handle});
    _checkError();
    // Return a mock archive
    return Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]); // ZIP header
  }

  @override
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner signer,
  ) async {
    _recordCall('builderSign', {
      'handle': handle,
      'sourceDataLength': sourceData.length,
      'mimeType': mimeType,
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
    });
    _checkError();

    final signedData =
        mockSignedData ?? Uint8List.fromList([...sourceData, 0xC2, 0xAA]);
    return BuilderSignResult(
      signedData: signedData,
      manifestBytes: mockManifestBytes,
      manifestSize: mockManifestBytes?.length ?? 1000,
    );
  }

  @override
  Future<void> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner signer,
  ) async {
    _recordCall('builderSignFile', {
      'handle': handle,
      'sourcePath': sourcePath,
      'destPath': destPath,
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
    });
    _checkError();
  }

  @override
  Future<void> builderDispose(int handle) async {
    _recordCall('builderDispose', {'handle': handle});
    builders.remove(handle);
  }

  // ===========================================================================
  // Advanced Signing API
  // ===========================================================================

  @override
  Future<Uint8List> createHashedPlaceholder({
    required int builderHandle,
    required int reservedSize,
    required String mimeType,
  }) async {
    _recordCall('createHashedPlaceholder', {
      'handle': builderHandle,
      'reservedSize': reservedSize,
      'mimeType': mimeType,
    });
    _checkError();
    return Uint8List(reservedSize);
  }

  @override
  Future<Uint8List> signHashedEmbeddable({
    required int builderHandle,
    required C2paSigner signer,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) async {
    _recordCall('signHashedEmbeddable', {
      'handle': builderHandle,
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
      'dataHash': dataHash,
      'mimeType': mimeType,
      'assetDataLength': assetData?.length,
    });
    _checkError();
    return mockManifestBytes ?? Uint8List.fromList([0xC2, 0xAA, 0x00, 0x01]);
  }

  @override
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) async {
    _recordCall('formatEmbeddable', {
      'mimeType': mimeType,
      'manifestBytesLength': manifestBytes.length,
    });
    _checkError();
    return manifestBytes;
  }

  @override
  Future<int> getSignerReserveSize(C2paSigner signer) async {
    _recordCall('getSignerReserveSize', {
      'algorithm': signer.algorithm.name,
      'signerType': signer.runtimeType.toString(),
    });
    _checkError();
    return mockReserveSize;
  }

  // ===========================================================================
  // Key Management API
  // ===========================================================================

  @override
  Future<bool> isHardwareSigningAvailable() async {
    _recordCall('isHardwareSigningAvailable', null);
    _checkError();
    return false; // Mock returns false for hardware availability
  }

  @override
  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) async {
    _recordCall('createKey', {
      'keyAlias': keyAlias,
      'algorithm': algorithm.name,
      'useHardware': useHardware,
    });
    _checkError();
  }

  @override
  Future<bool> deleteKey(String keyAlias) async {
    _recordCall('deleteKey', {'keyAlias': keyAlias});
    _checkError();
    return true;
  }

  @override
  Future<bool> keyExists(String keyAlias) async {
    _recordCall('keyExists', {'keyAlias': keyAlias});
    _checkError();
    return false;
  }

  @override
  Future<String> exportPublicKey(String keyAlias) async {
    _recordCall('exportPublicKey', {'keyAlias': keyAlias});
    _checkError();
    return '-----BEGIN PUBLIC KEY-----\nMockPublicKey\n-----END PUBLIC KEY-----';
  }

  // ===========================================================================
  // Settings API - Legacy
  // ===========================================================================

  @override
  Future<void> loadSettings(String settings, String format) async {
    _recordCall('loadSettings', {'settings': settings, 'format': format});
    _checkError();
  }

  // ===========================================================================
  // Settings API - Handle-based
  // ===========================================================================

  @override
  Future<int> createSettings() async {
    _recordCall('createSettings', null);
    _checkError();

    final handle = _nextSettingsId++;
    settings[handle] = MockSettings(handle);
    return handle;
  }

  @override
  Future<void> settingsUpdateFromString(
    int handle,
    String settingsStr,
    String format,
  ) async {
    _recordCall('settingsUpdateFromString', {
      'handle': handle,
      'settingsStr': settingsStr,
      'format': format,
    });
    _checkError();
    settings[handle]?.settingsStr = settingsStr;
    settings[handle]?.format = format;
  }

  @override
  Future<void> settingsSetValue(int handle, String path, String value) async {
    _recordCall('settingsSetValue', {
      'handle': handle,
      'path': path,
      'value': value,
    });
    _checkError();
    settings[handle]?.values[path] = value;
  }

  @override
  Future<void> settingsDispose(int handle) async {
    _recordCall('settingsDispose', {'handle': handle});
    settings.remove(handle);
  }

  // ===========================================================================
  // Context API - Handle-based
  // ===========================================================================

  @override
  Future<int> createContext() async {
    _recordCall('createContext', null);
    _checkError();

    final handle = _nextContextId++;
    contexts[handle] = MockContext(handle);
    return handle;
  }

  @override
  Future<int> createContextFromSettings(int settingsHandle) async {
    _recordCall('createContextFromSettings', {
      'settingsHandle': settingsHandle,
    });
    _checkError();

    final handle = _nextContextId++;
    contexts[handle] = MockContext(handle, settingsHandle: settingsHandle);
    return handle;
  }

  @override
  Future<void> contextDispose(int handle) async {
    _recordCall('contextDispose', {'handle': handle});
    contexts.remove(handle);
  }

  // ===========================================================================
  // Enhanced Reader API - Context-based
  // ===========================================================================

  @override
  Future<String?> readFileWithContext(
    String path,
    int contextHandle,
    bool detailed,
    String? dataDir,
  ) async {
    _recordCall('readFileWithContext', {
      'path': path,
      'contextHandle': contextHandle,
      'detailed': detailed,
      'dataDir': dataDir,
    });
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson(path);
  }

  // ===========================================================================
  // Enhanced Builder API - Context/Settings-based
  // ===========================================================================

  @override
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) async {
    _recordCall('createBuilderWithContext', {
      'contextHandle': contextHandle,
      'manifestJson': manifestJson,
    });
    _checkError();

    final handle = _nextBuilderId++;
    final builder = MockBuilder(this, handle, manifestJson);
    builders[handle] = builder;
    return builder;
  }

  @override
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) async {
    _recordCall('createBuilderWithSettings', {
      'manifestJson': manifestJson,
      'settingsHandle': settingsHandle,
    });
    _checkError();

    final handle = _nextBuilderId++;
    final builder = MockBuilder(this, handle, manifestJson);
    builders[handle] = builder;
    return builder;
  }

  // ===========================================================================
  // Certificate Manager API
  // ===========================================================================

  @override
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    Map<String, dynamic>? config,
  }) async {
    _recordCall('createSelfSignedCertificateChain', {
      'keyAlias': keyAlias,
      'config': config,
    });
    _checkError();
    return mockCertificateChain;
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  String _generateMockManifestJson(String source) {
    return jsonEncode({
      'active_manifest': 'mock:urn:uuid:test-manifest-001',
      'manifests': {
        'mock:urn:uuid:test-manifest-001': {
          'label': 'mock:urn:uuid:test-manifest-001',
          'title': 'Mock Test Image',
          'format': 'image/jpeg',
          'claim_generator': 'c2pa_flutter_test/1.0',
          'assertions': [
            {
              'label': 'c2pa.actions',
              'data': {
                'actions': [
                  {
                    'action': 'c2pa.created',
                    'softwareAgent': 'c2pa_flutter_test/1.0',
                  },
                ],
              },
            },
          ],
          'ingredients': [],
        },
      },
      'validation_status': [],
    });
  }
}

/// Record of a method call for verification
class MockMethodCall {
  final String method;
  final Map<String, dynamic>? arguments;
  final DateTime timestamp;

  MockMethodCall(this.method, this.arguments) : timestamp = DateTime.now();

  @override
  String toString() => 'MockMethodCall($method, $arguments)';
}

/// Mock builder for testing
class MockBuilder implements ManifestBuilder {
  final MockC2paPlatform _platform;
  final int _handle;
  final String manifestJson;

  ManifestIntent? intent;
  DigitalSourceType? digitalSourceType;
  bool noEmbed = false;
  String? remoteUrl;
  final Map<String, Uint8List> resources = {};
  final List<MockIngredient> ingredients = [];
  final List<String> actions = [];

  bool _disposed = false;

  MockBuilder(this._platform, this._handle, this.manifestJson);

  @override
  int get handle => _handle;

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('Builder has been disposed');
    }
  }

  @override
  void setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) {
    _checkDisposed();
    this.intent = intent;
    this.digitalSourceType = digitalSourceType;
  }

  @override
  void setNoEmbed() {
    _checkDisposed();
    noEmbed = true;
  }

  @override
  void setRemoteUrl(String url) {
    _checkDisposed();
    remoteUrl = url;
  }

  @override
  Future<void> addResource(BuilderResource resource) async {
    _checkDisposed();
    await _platform.builderAddResource(_handle, resource.uri, resource.data);
  }

  @override
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  }) async {
    _checkDisposed();
    await _platform.builderAddIngredient(
      _handle,
      data,
      mimeType,
      config?.toJson(),
    );
  }

  @override
  void addAction(ActionConfig action) {
    _checkDisposed();
    actions.add(action.toJson());
  }

  @override
  Future<BuilderArchive> toArchive() async {
    _checkDisposed();
    final data = await _platform.builderToArchive(_handle);
    return BuilderArchive(data: data);
  }

  @override
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    required C2paSigner signer,
  }) async {
    _checkDisposed();
    return _platform.builderSign(_handle, sourceData, mimeType, signer);
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _platform.builderDispose(_handle);
    }
  }
}

/// Mock ingredient for tracking
class MockIngredient {
  final Uint8List data;
  final String mimeType;
  final String? configJson;

  MockIngredient(this.data, this.mimeType, this.configJson);
}

/// Mock settings handle for tracking
class MockSettings {
  final int handle;
  String? settingsStr;
  String? format;
  final Map<String, String> values = {};

  MockSettings(this.handle);
}

/// Mock context handle for tracking
class MockContext {
  final int handle;
  final int? settingsHandle;

  MockContext(this.handle, {this.settingsHandle});
}
