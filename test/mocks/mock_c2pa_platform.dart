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

  // =============================================================================
  // Version and Platform Info
  // =============================================================================

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

  // =============================================================================
  // Reader API - Basic
  // =============================================================================

  /// When true, every read throws [C2paManifestNotFoundException], as the
  /// native SDKs do for an asset without content credentials.
  bool mockNoManifest = false;

  String _manifestOrThrow(String source) {
    if (mockNoManifest) {
      throw const C2paManifestNotFoundException(
        'ManifestNotFound: no JUMBF data found',
      );
    }
    return mockManifestJson ?? _generateMockManifestJson(source);
  }

  @override
  Future<String> readFile(String path) async {
    _recordCall('readFile', {'path': path});
    _checkError();
    return _manifestOrThrow(path);
  }

  @override
  Future<String> readBytes(Uint8List data, String mimeType) async {
    _recordCall('readBytes', {'dataLength': data.length, 'mimeType': mimeType});
    _checkError();
    return _manifestOrThrow('bytes');
  }

  /// Remote URL returned by the mock for [getRemoteUrl]; null means embedded manifest.
  String? mockRemoteUrl;

  /// Whether the mock reports the manifest as embedded.
  bool mockIsManifestEmbedded = true;

  @override
  Future<String?> getRemoteUrl(String path, {String? mimeType}) async {
    _recordCall('getRemoteUrl', {'path': path, 'mimeType': mimeType});
    _checkError();
    return mockRemoteUrl;
  }

  @override
  Future<bool> isManifestEmbedded(String path, {String? mimeType}) async {
    _recordCall('isManifestEmbedded', {'path': path, 'mimeType': mimeType});
    _checkError();
    return mockIsManifestEmbedded;
  }

  // =============================================================================
  // Reader API - Enhanced
  // =============================================================================

  @override
  Future<String> readFileDetailed(
    String path,
    bool detailed, {
    int? contextHandle,
  }) async {
    _recordCall('readFileDetailed', {
      'path': path,
      'detailed': detailed,
      'contextHandle': contextHandle,
    });
    _checkError();
    return _manifestOrThrow(path);
  }

  @override
  Future<String> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed, {
    int? contextHandle,
  }) async {
    _recordCall('readBytesDetailed', {
      'dataLength': data.length,
      'mimeType': mimeType,
      'detailed': detailed,
      'contextHandle': contextHandle,
    });
    _checkError();
    return _manifestOrThrow('bytes');
  }

  @override
  Future<Uint8List> extractResource(
    Uint8List data,
    String mimeType,
    String uri, {
    int? contextHandle,
  }) async {
    _recordCall('extractResource', {
      'dataLength': data.length,
      'mimeType': mimeType,
      'uri': uri,
      'contextHandle': contextHandle,
    });
    _checkError();
    return mockResourceData ??
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // Minimal JPEG header
  }

  /// crJSON returned by [readCrJson].
  String mockCrJson = '{"@context": "crjson", "manifests": []}';

  @override
  Future<String> readCrJson({
    String? path,
    Uint8List? data,
    String? mimeType,
    int? contextHandle,
  }) async {
    _recordCall('readCrJson', {
      'path': path,
      'dataLength': data?.length,
      'mimeType': mimeType,
      'contextHandle': contextHandle,
    });
    _checkError();
    return mockCrJson;
  }

  @override
  Future<String> readWithManifest({
    String? path,
    Uint8List? data,
    String? mimeType,
    required Uint8List manifestData,
    bool detailed = false,
    int? contextHandle,
  }) async {
    _recordCall('readWithManifest', {
      'path': path,
      'dataLength': data?.length,
      'mimeType': mimeType,
      'manifestDataLength': manifestData.length,
      'detailed': detailed,
      'contextHandle': contextHandle,
    });
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson(path ?? 'bytes');
  }

  @override
  Future<String> readFragment({
    required String initPath,
    required String fragmentPath,
    String? mimeType,
    bool detailed = false,
    int? contextHandle,
  }) async {
    _recordCall('readFragment', {
      'initPath': initPath,
      'fragmentPath': fragmentPath,
      'mimeType': mimeType,
      'detailed': detailed,
      'contextHandle': contextHandle,
    });
    _checkError();
    return mockManifestJson ?? _generateMockManifestJson(initPath);
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

  // =============================================================================
  // Signer API - Basic
  // =============================================================================

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

  // =============================================================================
  // Builder API
  // =============================================================================

  @override
  Future<ManifestBuilder> createBuilder(
    String manifestJson, {
    int? contextHandle,
  }) async {
    _recordCall('createBuilder', {
      'manifestJson': manifestJson,
      'contextHandle': contextHandle,
    });
    _checkError();

    final handle = _nextBuilderId++;
    final builder = MockBuilder(this, handle, manifestJson);
    builders[handle] = builder;
    return builder;
  }

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData, {
    int? contextHandle,
  }) async {
    _recordCall('createBuilderFromArchive', {
      'archiveDataLength': archiveData.length,
      'contextHandle': contextHandle,
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
  Future<void> builderAddIngredientFromFile(
    int handle,
    String path,
    String? mimeType,
    String? ingredientJson,
  ) async {
    _recordCall('builderAddIngredientFromFile', {
      'handle': handle,
      'path': path,
      'mimeType': mimeType,
      'ingredientJson': ingredientJson,
    });
    _checkError();
    builders[handle]?.ingredients.add(
      MockIngredient(Uint8List(0), mimeType ?? '', ingredientJson),
    );
  }

  @override
  Future<void> builderSetBasePath(int handle, String path) async {
    _recordCall('builderSetBasePath', {'handle': handle, 'path': path});
    _checkError();
  }

  @override
  Future<void> builderAddIngredientFromArchive(
    int handle,
    Uint8List archive,
  ) async {
    _recordCall('builderAddIngredientFromArchive', {
      'handle': handle,
      'archiveLength': archive.length,
    });
    _checkError();
  }

  @override
  Future<Uint8List> builderWriteIngredientArchive(
    int handle,
    String ingredientId,
  ) async {
    _recordCall('builderWriteIngredientArchive', {
      'handle': handle,
      'ingredientId': ingredientId,
    });
    _checkError();
    return Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
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
    C2paSigner? signer,
  ) async {
    _recordCall('builderSign', {
      'handle': handle,
      'sourceDataLength': sourceData.length,
      'mimeType': mimeType,
      'algorithm': signer?.algorithm.name,
      'signerType': signer?.runtimeType.toString(),
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
  Future<BuilderFileSignResult> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner? signer, {
    String? mimeType,
  }) async {
    _recordCall('builderSignFile', {
      'handle': handle,
      'sourcePath': sourcePath,
      'destPath': destPath,
      'mimeType': mimeType,
      'algorithm': signer?.algorithm.name,
      'signerType': signer?.runtimeType.toString(),
    });
    _checkError();
    return BuilderFileSignResult(
      manifestBytes: mockManifestBytes,
      manifestSize: mockManifestBytes?.length ?? 1000,
    );
  }

  /// Placeholder size returned by [builderPlaceholder].
  int mockPlaceholderSize = 2048;

  /// Hash type returned by [builderHashType].
  C2paHashType mockHashType = C2paHashType.dataHash;

  @override
  Future<bool> builderNeedsPlaceholder(int handle, String mimeType) async {
    _recordCall('builderNeedsPlaceholder', {
      'handle': handle,
      'mimeType': mimeType,
    });
    _checkError();
    return mockHashType != C2paHashType.boxHash;
  }

  @override
  Future<Uint8List> builderPlaceholder(int handle, String mimeType) async {
    _recordCall('builderPlaceholder', {'handle': handle, 'mimeType': mimeType});
    _checkError();
    return Uint8List(mockPlaceholderSize);
  }

  @override
  Future<void> builderSetDataHashExclusions(
    int handle,
    List<DataHashExclusion> exclusions,
  ) async {
    _recordCall('builderSetDataHashExclusions', {
      'handle': handle,
      'exclusions': exclusions.map((e) => e.toList()).toList(),
    });
    _checkError();
  }

  @override
  Future<void> builderUpdateHashFromBytes(
    int handle,
    String mimeType,
    Uint8List data,
  ) async {
    _recordCall('builderUpdateHashFromBytes', {
      'handle': handle,
      'mimeType': mimeType,
      'dataLength': data.length,
    });
    _checkError();
  }

  @override
  Future<void> builderUpdateHashFromFile(
    int handle,
    String path, {
    String? mimeType,
  }) async {
    _recordCall('builderUpdateHashFromFile', {
      'handle': handle,
      'path': path,
      'mimeType': mimeType,
    });
    _checkError();
  }

  @override
  Future<Uint8List> builderSignEmbeddable(int handle, String mimeType) async {
    _recordCall('builderSignEmbeddable', {
      'handle': handle,
      'mimeType': mimeType,
    });
    _checkError();
    return mockManifestBytes ?? Uint8List(mockPlaceholderSize);
  }

  @override
  Future<C2paHashType> builderHashType(int handle, String mimeType) async {
    _recordCall('builderHashType', {'handle': handle, 'mimeType': mimeType});
    _checkError();
    return mockHashType;
  }

  @override
  Future<void> builderSetFixedSizeMerkle(int handle, int fixedSizeKb) async {
    _recordCall('builderSetFixedSizeMerkle', {
      'handle': handle,
      'fixedSizeKb': fixedSizeKb,
    });
    _checkError();
  }

  @override
  Future<void> builderHashMdatBytes(
    int handle, {
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) async {
    _recordCall('builderHashMdatBytes', {
      'handle': handle,
      'mdatId': mdatId,
      'dataLength': data.length,
      'largeSize': largeSize,
    });
    _checkError();
  }

  @override
  Future<void> builderDispose(int handle) async {
    _recordCall('builderDispose', {'handle': handle});
    builders.remove(handle);
  }

  // =============================================================================
  // Embeddable manifests
  // =============================================================================

  @override
  Future<Uint8List> composeManifest({
    required Uint8List manifestBytes,
    required String mimeType,
  }) async {
    _recordCall('composeManifest', {
      'mimeType': mimeType,
      'manifestBytesLength': manifestBytes.length,
    });
    _checkError();
    return Uint8List.fromList([0xFF, 0xEB, ...manifestBytes]);
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

  // =============================================================================
  // Key Management API
  // =============================================================================

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

  // =============================================================================
  // Settings API - Legacy
  // =============================================================================

  @override
  Future<void> loadSettings(String settings, String format) async {
    _recordCall('loadSettings', {'settings': settings, 'format': format});
    _checkError();
  }

  // =============================================================================
  // Settings API - Handle-based
  // =============================================================================

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
  Future<void> settingsSetValue(int handle, String path, Object value) async {
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

  // =============================================================================
  // Context API - Handle-based
  // =============================================================================

  @override
  Future<int> createContext({
    int? settingsHandle,
    C2paSigner? signer,
    void Function(C2paProgress progress)? onProgress,
    C2paHttpResolver? httpResolver,
  }) async {
    _recordCall('createContext', {
      'settingsHandle': settingsHandle,
      'signerType': signer?.runtimeType.toString(),
      'progress': onProgress != null,
      'httpResolver': httpResolver?.runtimeType.toString(),
    });
    _checkError();

    final handle = _nextContextId++;
    contexts[handle] = MockContext(
      handle,
      settingsHandle: settingsHandle,
      signer: signer,
      onProgress: onProgress,
      httpResolver: httpResolver,
    );
    return handle;
  }

  @override
  Future<void> contextCancel(int handle) async {
    _recordCall('contextCancel', {'handle': handle});
    _checkError();
    contexts[handle]?.cancelled = true;
  }

  @override
  Future<void> contextDispose(int handle) async {
    _recordCall('contextDispose', {'handle': handle});
    contexts.remove(handle);
  }

  // =============================================================================
  // Enhanced Builder API - Context/Settings-based
  // =============================================================================

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

  // =============================================================================
  // Certificate Manager API
  // =============================================================================

  @override
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    CertificateConfig? config,
  }) async {
    _recordCall('createSelfSignedCertificateChain', {
      'keyAlias': keyAlias,
      'config': config?.toMap(),
    });
    _checkError();
    return mockCertificateChain;
  }

  // =============================================================================
  // Helper Methods
  // =============================================================================

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
          'ingredients': <Object>[],
        },
      },
      'validation_status': <Object>[],
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
  Future<void> setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) async {
    _checkDisposed();
    this.intent = intent;
    this.digitalSourceType = digitalSourceType;
  }

  @override
  Future<void> setNoEmbed() async {
    _checkDisposed();
    noEmbed = true;
  }

  @override
  Future<void> setRemoteUrl(String url) async {
    _checkDisposed();
    remoteUrl = url;
  }

  @override
  Future<void> setBasePath(String path) async {
    _checkDisposed();
    await _platform.builderSetBasePath(_handle, path);
  }

  @override
  Future<void> addResource(BuilderResource resource) async {
    _checkDisposed();
    await _platform.builderAddResource(_handle, resource.uri, resource.data);
  }

  @override
  Future<void> addIngredientFromArchive(Uint8List archive) async {
    _checkDisposed();
    await _platform.builderAddIngredientFromArchive(_handle, archive);
  }

  @override
  Future<Uint8List> writeIngredientArchive(String ingredientId) async {
    _checkDisposed();
    return _platform.builderWriteIngredientArchive(_handle, ingredientId);
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
  Future<void> addIngredientFromFile({
    required String path,
    String? mimeType,
    IngredientConfig? config,
  }) async {
    _checkDisposed();
    await _platform.builderAddIngredientFromFile(
      _handle,
      path,
      mimeType,
      config?.toJson(),
    );
  }

  @override
  Future<void> addAction(ActionConfig action) async {
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
    C2paSigner? signer,
  }) async {
    _checkDisposed();
    return _platform.builderSign(_handle, sourceData, mimeType, signer);
  }

  @override
  Future<BuilderFileSignResult> signFile({
    required String sourcePath,
    required String destPath,
    C2paSigner? signer,
    String? mimeType,
  }) async {
    _checkDisposed();
    return _platform.builderSignFile(
      _handle,
      sourcePath,
      destPath,
      signer,
      mimeType: mimeType,
    );
  }

  @override
  Future<bool> needsPlaceholder(String mimeType) async {
    _checkDisposed();
    return _platform.builderNeedsPlaceholder(_handle, mimeType);
  }

  @override
  Future<Uint8List> placeholder(String mimeType) async {
    _checkDisposed();
    return _platform.builderPlaceholder(_handle, mimeType);
  }

  @override
  Future<void> setDataHashExclusions(List<DataHashExclusion> exclusions) async {
    _checkDisposed();
    await _platform.builderSetDataHashExclusions(_handle, exclusions);
  }

  @override
  Future<void> updateHashFromBytes(String mimeType, Uint8List data) async {
    _checkDisposed();
    await _platform.builderUpdateHashFromBytes(_handle, mimeType, data);
  }

  @override
  Future<void> updateHashFromFile(String path, {String? mimeType}) async {
    _checkDisposed();
    await _platform.builderUpdateHashFromFile(
      _handle,
      path,
      mimeType: mimeType,
    );
  }

  @override
  Future<Uint8List> signEmbeddable(String mimeType) async {
    _checkDisposed();
    return _platform.builderSignEmbeddable(_handle, mimeType);
  }

  @override
  Future<C2paHashType> hashType(String mimeType) async {
    _checkDisposed();
    return _platform.builderHashType(_handle, mimeType);
  }

  @override
  Future<void> setFixedSizeMerkle(int fixedSizeKb) async {
    _checkDisposed();
    await _platform.builderSetFixedSizeMerkle(_handle, fixedSizeKb);
  }

  @override
  Future<void> hashMdatBytes({
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) async {
    _checkDisposed();
    await _platform.builderHashMdatBytes(
      _handle,
      mdatId: mdatId,
      data: data,
      largeSize: largeSize,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _platform.builderDispose(_handle);
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
  final Map<String, Object> values = {};

  MockSettings(this.handle);
}

/// Mock context handle for tracking
class MockContext {
  final int handle;
  final int? settingsHandle;
  final C2paSigner? signer;
  final void Function(C2paProgress progress)? onProgress;
  final C2paHttpResolver? httpResolver;
  bool cancelled = false;

  MockContext(
    this.handle, {
    this.settingsHandle,
    this.signer,
    this.onProgress,
    this.httpResolver,
  });
}
