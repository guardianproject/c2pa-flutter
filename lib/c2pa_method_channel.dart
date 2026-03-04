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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'c2pa_platform_interface.dart';

/// Method channel implementation of [C2paPlatform]
class MethodChannelC2pa extends C2paPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('org.guardianproject.c2pa');

  // Callback management for CallbackSigner
  final Map<String, Future<Uint8List> Function(Uint8List)> _signCallbacks = {};
  int _nextCallbackId = 0;
  bool _callbackHandlerRegistered = false;

  void _ensureCallbackHandlerRegistered() {
    if (_callbackHandlerRegistered) return;
    _callbackHandlerRegistered = true;
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'signCallback':
        final callbackId = call.arguments['callbackId'] as String;
        final data = call.arguments['data'] as Uint8List;
        final callback = _signCallbacks[callbackId];
        if (callback == null) {
          throw PlatformException(
            code: 'CALLBACK_NOT_FOUND',
            message: 'Callback $callbackId not found',
          );
        }
        return await callback(data);
      default:
        throw UnimplementedError('Method ${call.method} not implemented');
    }
  }

  String _registerCallback(Future<Uint8List> Function(Uint8List) callback) {
    _ensureCallbackHandlerRegistered();
    final id = 'callback_${_nextCallbackId++}';
    _signCallbacks[id] = callback;
    return id;
  }

  void _unregisterCallback(String callbackId) {
    _signCallbacks.remove(callbackId);
  }

  Map<String, dynamic> _serializeSigner(C2paSigner signer) {
    final map = signer.toMap();
    if (signer is CallbackSigner) {
      map['callbackId'] = _registerCallback(signer.signCallback);
    }
    return map;
  }

  // =============================================================================
  // Version and Platform Info
  // =============================================================================

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> getVersion() async {
    final version = await methodChannel.invokeMethod<String>('getVersion');
    return version;
  }

  // =============================================================================
  // Reader API - Basic
  // =============================================================================

  @override
  Future<String?> readFile(String path) async {
    final result = await methodChannel.invokeMethod<String>('readFile', {
      'path': path,
    });
    return result;
  }

  @override
  Future<String?> readBytes(Uint8List data, String mimeType) async {
    final result = await methodChannel.invokeMethod<String>('readBytes', {
      'data': data,
      'mimeType': mimeType,
    });
    return result;
  }

  // =============================================================================
  // Reader API - Enhanced
  // =============================================================================

  @override
  Future<String?> readFileDetailed(
    String path,
    bool detailed,
    String? dataDir,
  ) async {
    final result = await methodChannel.invokeMethod<String>(
      'readFileDetailed',
      {'path': path, 'detailed': detailed, 'dataDir': dataDir},
    );
    return result;
  }

  @override
  Future<String?> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed,
  ) async {
    final result = await methodChannel.invokeMethod<String>(
      'readBytesDetailed',
      {'data': data, 'mimeType': mimeType, 'detailed': detailed},
    );
    return result;
  }

  @override
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'extractResource',
      {'data': data, 'mimeType': mimeType, 'uri': uri},
    );
    return result;
  }

  @override
  Future<String?> readIngredientFile(String path, String? dataDir) async {
    final result = await methodChannel.invokeMethod<String>(
      'readIngredientFile',
      {'path': path, 'dataDir': dataDir},
    );
    return result;
  }

  @override
  Future<List<String>> getSupportedReadMimeTypes() async {
    final result = await methodChannel.invokeMethod<List>(
      'getSupportedReadMimeTypes',
    );
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> getSupportedSignMimeTypes() async {
    final result = await methodChannel.invokeMethod<List>(
      'getSupportedSignMimeTypes',
    );
    return result?.cast<String>() ?? [];
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
    final signerMap = _serializeSigner(signer);
    String? callbackId;
    if (signer is CallbackSigner) {
      callbackId = signerMap['callbackId'] as String;
    }

    try {
      final result = await methodChannel.invokeMethod<Map>('signBytes', {
        'sourceData': sourceData,
        'mimeType': mimeType,
        'manifestJson': manifestJson,
        'signer': signerMap,
      });

      if (result == null) {
        throw PlatformException(
          code: 'ERROR',
          message: 'Sign operation returned null',
        );
      }

      return SignResult(
        signedData: result['signedData'] as Uint8List,
        manifestBytes: result['manifestBytes'] as Uint8List?,
      );
    } finally {
      if (callbackId != null) {
        _unregisterCallback(callbackId);
      }
    }
  }

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) async {
    final signerMap = _serializeSigner(signer);
    String? callbackId;
    if (signer is CallbackSigner) {
      callbackId = signerMap['callbackId'] as String;
    }

    try {
      await methodChannel.invokeMethod<void>('signFile', {
        'sourcePath': sourcePath,
        'destPath': destPath,
        'manifestJson': manifestJson,
        'signer': signerMap,
      });
    } finally {
      if (callbackId != null) {
        _unregisterCallback(callbackId);
      }
    }
  }

  // =============================================================================
  // Builder API
  // =============================================================================

  @override
  Future<ManifestBuilder> createBuilder(String manifestJson) async {
    final handle = await methodChannel.invokeMethod<int>('createBuilder', {
      'manifestJson': manifestJson,
    });

    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder',
      );
    }

    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData,
  ) async {
    final handle = await methodChannel.invokeMethod<int>(
      'createBuilderFromArchive',
      {'archiveData': archiveData},
    );

    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder from archive',
      );
    }

    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) async {
    await methodChannel.invokeMethod<void>('builderSetIntent', {
      'handle': handle,
      'intent': intent.name,
      'digitalSourceType': digitalSourceType?.name,
    });
  }

  @override
  Future<void> builderSetNoEmbed(int handle) async {
    await methodChannel.invokeMethod<void>('builderSetNoEmbed', {
      'handle': handle,
    });
  }

  @override
  Future<void> builderSetRemoteUrl(int handle, String url) async {
    await methodChannel.invokeMethod<void>('builderSetRemoteUrl', {
      'handle': handle,
      'url': url,
    });
  }

  @override
  Future<void> builderAddResource(
    int handle,
    String uri,
    Uint8List data,
  ) async {
    await methodChannel.invokeMethod<void>('builderAddResource', {
      'handle': handle,
      'uri': uri,
      'data': data,
    });
  }

  @override
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) async {
    await methodChannel.invokeMethod<void>('builderAddIngredient', {
      'handle': handle,
      'data': data,
      'mimeType': mimeType,
      'ingredientJson': ingredientJson,
    });
  }

  @override
  Future<void> builderAddAction(int handle, String actionJson) async {
    await methodChannel.invokeMethod<void>('builderAddAction', {
      'handle': handle,
      'actionJson': actionJson,
    });
  }

  @override
  Future<Uint8List> builderToArchive(int handle) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'builderToArchive',
      {'handle': handle},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to export builder to archive',
      );
    }

    return result;
  }

  @override
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner signer,
  ) async {
    final signerMap = _serializeSigner(signer);
    String? callbackId;
    if (signer is CallbackSigner) {
      callbackId = signerMap['callbackId'] as String;
    }

    try {
      final result = await methodChannel.invokeMethod<Map>('builderSign', {
        'handle': handle,
        'sourceData': sourceData,
        'mimeType': mimeType,
        'signer': signerMap,
      });

      if (result == null) {
        throw PlatformException(
          code: 'ERROR',
          message: 'Builder sign operation returned null',
        );
      }

      return BuilderSignResult(
        signedData: result['signedData'] as Uint8List,
        manifestBytes: result['manifestBytes'] as Uint8List?,
        manifestSize: result['manifestSize'] as int? ?? 0,
      );
    } finally {
      if (callbackId != null) {
        _unregisterCallback(callbackId);
      }
    }
  }

  @override
  Future<void> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner signer,
  ) async {
    final signerMap = _serializeSigner(signer);
    String? callbackId;
    if (signer is CallbackSigner) {
      callbackId = signerMap['callbackId'] as String;
    }

    try {
      await methodChannel.invokeMethod<void>('builderSignFile', {
        'handle': handle,
        'sourcePath': sourcePath,
        'destPath': destPath,
        'signer': signerMap,
      });
    } finally {
      if (callbackId != null) {
        _unregisterCallback(callbackId);
      }
    }
  }

  @override
  Future<void> builderDispose(int handle) async {
    await methodChannel.invokeMethod<void>('builderDispose', {
      'handle': handle,
    });
  }

  // =============================================================================
  // Advanced Signing API
  // =============================================================================

  @override
  Future<Uint8List> createHashedPlaceholder({
    required int builderHandle,
    required int reservedSize,
    required String mimeType,
  }) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'createHashedPlaceholder',
      {
        'handle': builderHandle,
        'reservedSize': reservedSize,
        'mimeType': mimeType,
      },
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create hashed placeholder',
      );
    }

    return result;
  }

  @override
  Future<Uint8List> signHashedEmbeddable({
    required int builderHandle,
    required C2paSigner signer,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) async {
    final signerMap = _serializeSigner(signer);
    String? callbackId;
    if (signer is CallbackSigner) {
      callbackId = signerMap['callbackId'] as String;
    }

    try {
      final result = await methodChannel
          .invokeMethod<Uint8List>('signHashedEmbeddable', {
            'handle': builderHandle,
            'signer': signerMap,
            'dataHash': dataHash,
            'mimeType': mimeType,
            'assetData': assetData,
          });

      if (result == null) {
        throw PlatformException(
          code: 'ERROR',
          message: 'Failed to sign hashed embeddable',
        );
      }

      return result;
    } finally {
      if (callbackId != null) {
        _unregisterCallback(callbackId);
      }
    }
  }

  @override
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) async {
    final result = await methodChannel.invokeMethod<Uint8List>(
      'formatEmbeddable',
      {'mimeType': mimeType, 'manifestBytes': manifestBytes},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to format embeddable',
      );
    }

    return result;
  }

  @override
  Future<int> getSignerReserveSize(C2paSigner signer) async {
    final result = await methodChannel.invokeMethod<int>(
      'getSignerReserveSize',
      {'signer': signer.toMap()},
    );

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to get signer reserve size',
      );
    }

    return result;
  }

  // =============================================================================
  // Key Management API
  // =============================================================================

  @override
  Future<bool> isHardwareSigningAvailable() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isHardwareSigningAvailable',
    );
    return result ?? false;
  }

  @override
  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) async {
    await methodChannel.invokeMethod<void>('createKey', {
      'keyAlias': keyAlias,
      'algorithm': algorithm.name,
      'useHardware': useHardware,
    });
  }

  @override
  Future<bool> deleteKey(String keyAlias) async {
    final result = await methodChannel.invokeMethod<bool>('deleteKey', {
      'keyAlias': keyAlias,
    });
    return result ?? false;
  }

  @override
  Future<bool> keyExists(String keyAlias) async {
    final result = await methodChannel.invokeMethod<bool>('keyExists', {
      'keyAlias': keyAlias,
    });
    return result ?? false;
  }

  @override
  Future<String> exportPublicKey(String keyAlias) async {
    final result = await methodChannel.invokeMethod<String>('exportPublicKey', {
      'keyAlias': keyAlias,
    });

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to export public key',
      );
    }

    return result;
  }

  @override
  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) async {
    await methodChannel.invokeMethod<void>('importKey', {
      'keyAlias': keyAlias,
      'privateKeyPem': privateKeyPem,
      'certificateChainPem': certificateChainPem,
    });
  }

  @override
  Future<String> createCSR({
    required String keyAlias,
    required String commonName,
    String? organization,
    String? organizationalUnit,
    String? country,
    String? state,
    String? locality,
  }) async {
    final result = await methodChannel.invokeMethod<String>('createCSR', {
      'keyAlias': keyAlias,
      'commonName': commonName,
      'organization': organization,
      'organizationalUnit': organizationalUnit,
      'country': country,
      'state': state,
      'locality': locality,
    });

    if (result == null) {
      throw PlatformException(code: 'ERROR', message: 'Failed to create CSR');
    }

    return result;
  }

  @override
  Future<Map<String, dynamic>> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) async {
    final result = await methodChannel
        .invokeMethod<Map<dynamic, dynamic>>('enrollHardwareKey', {
          'keyAlias': keyAlias,
          'signingServerUrl': signingServerUrl,
          'bearerToken': bearerToken,
          'commonName': commonName,
          'organization': organization,
          'useStrongBox': useStrongBox,
        });

    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to enroll hardware key',
      );
    }

    return Map<String, dynamic>.from(result);
  }

  // =============================================================================
  // Settings API
  // =============================================================================

  @override
  Future<void> loadSettings(String settings, String format) async {
    await methodChannel.invokeMethod<void>('loadSettings', {
      'settings': settings,
      'format': format,
    });
  }

  // =============================================================================
  // C2PASettings Handle API
  // =============================================================================

  @override
  Future<int> createSettings() async {
    final handle = await methodChannel.invokeMethod<int>('createSettings');
    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create settings',
      );
    }
    return handle;
  }

  @override
  Future<void> settingsUpdateFromString(
    int handle,
    String settingsStr,
    String format,
  ) async {
    await methodChannel.invokeMethod<void>('settingsUpdateFromString', {
      'handle': handle,
      'settings': settingsStr,
      'format': format,
    });
  }

  @override
  Future<void> settingsSetValue(int handle, String path, String value) async {
    await methodChannel.invokeMethod<void>('settingsSetValue', {
      'handle': handle,
      'path': path,
      'value': value,
    });
  }

  @override
  Future<void> settingsDispose(int handle) async {
    await methodChannel.invokeMethod<void>('settingsDispose', {
      'handle': handle,
    });
  }

  // =============================================================================
  // C2PAContext Handle API
  // =============================================================================

  @override
  Future<int> createContext() async {
    final handle = await methodChannel.invokeMethod<int>('createContext');
    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create context',
      );
    }
    return handle;
  }

  @override
  Future<int> createContextFromSettings(int settingsHandle) async {
    final handle = await methodChannel.invokeMethod<int>(
      'createContextFromSettings',
      {'settingsHandle': settingsHandle},
    );
    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create context from settings',
      );
    }
    return handle;
  }

  @override
  Future<void> contextDispose(int handle) async {
    await methodChannel.invokeMethod<void>('contextDispose', {
      'handle': handle,
    });
  }

  // =============================================================================
  // Enhanced Reader API
  // =============================================================================

  @override
  Future<String?> readFileWithContext(
    String path,
    int contextHandle,
    bool detailed,
    String? dataDir,
  ) async {
    final result = await methodChannel
        .invokeMethod<String>('readFileWithContext', {
          'path': path,
          'contextHandle': contextHandle,
          'detailed': detailed,
          'dataDir': dataDir,
        });
    return result;
  }

  // =============================================================================
  // Enhanced Builder API
  // =============================================================================

  @override
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) async {
    final handle = await methodChannel.invokeMethod<int>(
      'createBuilderWithContext',
      {'contextHandle': contextHandle, 'manifestJson': manifestJson},
    );
    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder with context',
      );
    }
    return MethodChannelManifestBuilder(this, handle);
  }

  @override
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) async {
    final handle = await methodChannel.invokeMethod<int>(
      'createBuilderWithSettings',
      {'manifestJson': manifestJson, 'settingsHandle': settingsHandle},
    );
    if (handle == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create builder with settings',
      );
    }
    return MethodChannelManifestBuilder(this, handle);
  }

  // =============================================================================
  // Certificate Manager API
  // =============================================================================

  @override
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    Map<String, dynamic>? config,
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'createSelfSignedCertificateChain',
      {'keyAlias': keyAlias, 'config': config},
    );
    if (result == null) {
      throw PlatformException(
        code: 'ERROR',
        message: 'Failed to create self-signed certificate chain',
      );
    }
    return result;
  }
}

/// Method channel implementation of [ManifestBuilder]
class MethodChannelManifestBuilder implements ManifestBuilder {
  final MethodChannelC2pa _platform;
  final int _handle;
  bool _disposed = false;

  // Pending operations that need to be sent to native
  final List<Map<String, dynamic>> _pendingOperations = [];

  MethodChannelManifestBuilder(this._platform, this._handle);

  @override
  int get handle => _handle;

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('ManifestBuilder has been disposed');
    }
  }

  @override
  void setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) {
    _checkDisposed();
    _pendingOperations.add({
      'type': 'setIntent',
      'intent': intent,
      'digitalSourceType': digitalSourceType,
    });
  }

  @override
  void setNoEmbed() {
    _checkDisposed();
    _pendingOperations.add({'type': 'setNoEmbed'});
  }

  @override
  void setRemoteUrl(String url) {
    _checkDisposed();
    _pendingOperations.add({'type': 'setRemoteUrl', 'url': url});
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
    _pendingOperations.add({
      'type': 'addAction',
      'actionJson': action.toJson(),
    });
  }

  /// Apply all pending operations before signing
  Future<void> _applyPendingOperations() async {
    for (final op in _pendingOperations) {
      switch (op['type']) {
        case 'setIntent':
          await _platform.builderSetIntent(
            _handle,
            op['intent'] as ManifestIntent,
            op['digitalSourceType'] as DigitalSourceType?,
          );
          break;
        case 'setNoEmbed':
          await _platform.builderSetNoEmbed(_handle);
          break;
        case 'setRemoteUrl':
          await _platform.builderSetRemoteUrl(_handle, op['url'] as String);
          break;
        case 'addAction':
          await _platform.builderAddAction(_handle, op['actionJson'] as String);
          break;
      }
    }
    _pendingOperations.clear();
  }

  @override
  Future<BuilderArchive> toArchive() async {
    _checkDisposed();
    await _applyPendingOperations();
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
    await _applyPendingOperations();
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
