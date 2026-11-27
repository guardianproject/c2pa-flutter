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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'c2pa_platform_interface.dart';
import 'src/c2pa_api.g.dart';

/// Dart-side callbacks attached to one native context.
class _ContextCallbacks {
  final void Function(C2paProgress progress)? onProgress;
  final C2paHttpResolver? httpResolver;
  final List<String> signCallbackIds;

  _ContextCallbacks({
    required this.onProgress,
    required this.httpResolver,
    required this.signCallbackIds,
  });
}

/// [C2paPlatform] implemented over the Pigeon-generated [C2paHostApi], with
/// [C2paFlutterApi] answering the native side's signing, progress and HTTP
/// callbacks.
class PigeonC2pa extends C2paPlatform implements C2paFlutterApi {
  /// [hostApi] replaces the generated API in tests.
  PigeonC2pa({@visibleForTesting C2paHostApi? hostApi})
    : _api = hostApi ?? C2paHostApi();

  final C2paHostApi _api;

  final Map<String, Future<Uint8List> Function(Uint8List)> _signCallbacks = {};
  final Map<int, _ContextCallbacks> _contextCallbacks = {};
  int _nextCallbackId = 0;
  bool _flutterApiRegistered = false;

  /// Calls [body], reporting a native failure as a [C2paException].
  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw C2paException.fromPlatformException(e);
    }
  }

  /// Answers the native side's callbacks from now on. Registered lazily,
  /// since the binding may not exist yet when the platform is created.
  void _ensureFlutterApi() {
    if (_flutterApiRegistered) return;
    _flutterApiRegistered = true;
    C2paFlutterApi.setUp(this);
  }

  // ===========================================================================
  // C2paFlutterApi: calls from the native side
  // ===========================================================================

  @override
  Future<Uint8List> sign(String callbackId, Uint8List data) {
    final callback = _signCallbacks[callbackId];
    if (callback == null) {
      throw PlatformException(
        code: 'CALLBACK_NOT_FOUND',
        message: 'Callback $callbackId not found',
      );
    }
    return callback(data);
  }

  @override
  Future<void> progress(
    int contextHandle,
    String phase,
    int step,
    int total,
  ) async {
    _contextCallbacks[contextHandle]?.onProgress?.call(
      C2paProgress(
        phase: C2paProgressPhase.fromName(phase),
        step: step,
        total: total,
      ),
    );
  }

  @override
  Future<HttpResponseMessage> resolveHttp(
    int contextHandle,
    HttpRequestMessage request,
  ) async {
    final resolver = _contextCallbacks[contextHandle]?.httpResolver;
    if (resolver is! CallbackHttpResolver) {
      throw PlatformException(
        code: 'RESOLVER_NOT_FOUND',
        message: 'No HTTP resolver for context $contextHandle',
      );
    }
    final response = await resolver.resolve(
      C2paHttpRequest(
        url: request.url,
        method: request.method,
        headers: request.headers,
        body: request.body,
      ),
    );
    return HttpResponseMessage(status: response.status, body: response.body);
  }

  // ===========================================================================
  // Signers
  // ===========================================================================

  /// Converts [signer] to its message, registering a Dart callback for every
  /// [CallbackSigner] it contains and recording the callback ids in [ids].
  SignerMessage _signerMessage(C2paSigner signer, List<String> ids) {
    switch (signer) {
      case PemSigner():
        return PemSignerMessage(
          algorithm: _algorithm(signer.algorithm),
          certificatePem: signer.certificatePem,
          privateKeyPem: signer.privateKeyPem,
          tsaUrl: signer.tsaUrl,
        );
      case CallbackSigner():
        _ensureFlutterApi();
        final id = 'callback_${_nextCallbackId++}';
        _signCallbacks[id] = signer.signCallback;
        ids.add(id);
        return CallbackSignerMessage(
          algorithm: _algorithm(signer.algorithm),
          certificateChainPem: signer.certificateChainPem,
          callbackId: id,
          tsaUrl: signer.tsaUrl,
        );
      case KeystoreSigner():
        return KeystoreSignerMessage(
          algorithm: _algorithm(signer.algorithm),
          certificateChainPem: signer.certificateChainPem,
          keyAlias: signer.keyAlias,
          requireUserAuthentication: signer.requireUserAuthentication,
          tsaUrl: signer.tsaUrl,
        );
      case HardwareSigner():
        return HardwareSignerMessage(
          certificateChainPem: signer.certificateChainPem,
          keyAlias: signer.keyAlias,
          requireUserAuthentication: signer.requireUserAuthentication,
          tsaUrl: signer.tsaUrl,
        );
      case RemoteSigner():
        return RemoteSignerMessage(
          configurationUrl: signer.configurationUrl,
          bearerToken: signer.bearerToken,
          customHeaders: signer.customHeaders ?? const {},
        );
      case SettingsSigner():
        return SettingsSignerMessage(
          settings: signer.settingsString,
          format: signer.format,
        );
      case CawgIdentitySigner():
        return CawgIdentitySignerMessage(
          claimSigner: _signerMessage(signer.claimSigner, ids),
          identitySigner: _signerMessage(signer.identitySigner, ids),
          referencedAssertions: signer.referencedAssertions,
          roles: signer.roles,
        );
    }
  }

  static SigningAlgorithmMessage _algorithm(SigningAlgorithm algorithm) =>
      SigningAlgorithmMessage.values.byName(algorithm.name);

  /// Runs [body] with [signer] converted, releasing its callbacks afterwards.
  Future<T> _withSigner<T>(
    C2paSigner? signer,
    Future<T> Function(SignerMessage? message) body,
  ) async {
    if (signer == null) return _call(() => body(null));
    final ids = <String>[];
    final message = _signerMessage(signer, ids);
    try {
      return await _call(() => body(message));
    } finally {
      ids.forEach(_signCallbacks.remove);
    }
  }

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  @override
  Future<String?> getPlatformVersion() => _call(_api.getPlatformVersion);

  @override
  Future<String?> getVersion() => _call(_api.getVersion);

  // ===========================================================================
  // Reader
  // ===========================================================================

  static ReadFormatMessage _format(bool detailed) =>
      detailed ? ReadFormatMessage.detailed : ReadFormatMessage.json;

  @override
  Future<String> readFile(String path) =>
      _call(() => _api.readFile(path, null, ReadFormatMessage.json, null));

  @override
  Future<String> readBytes(Uint8List data, String mimeType) =>
      _call(() => _api.readBytes(data, mimeType, ReadFormatMessage.json, null));

  @override
  Future<String> readFileDetailed(
    String path,
    bool detailed, {
    int? contextHandle,
  }) =>
      _call(() => _api.readFile(path, null, _format(detailed), contextHandle));

  @override
  Future<String> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed, {
    int? contextHandle,
  }) => _call(
    () => _api.readBytes(data, mimeType, _format(detailed), contextHandle),
  );

  @override
  Future<String> readCrJson({
    String? path,
    Uint8List? data,
    String? mimeType,
    int? contextHandle,
  }) {
    if ((path == null) == (data == null)) {
      throw ArgumentError('Provide exactly one of path or data');
    }
    if (data != null) {
      if (mimeType == null) throw ArgumentError.notNull('mimeType');
      return _call(
        () => _api.readBytes(
          data,
          mimeType,
          ReadFormatMessage.crJson,
          contextHandle,
        ),
      );
    }
    return _call(
      () => _api.readFile(
        path!,
        mimeType,
        ReadFormatMessage.crJson,
        contextHandle,
      ),
    );
  }

  @override
  Future<String> readWithManifest({
    String? path,
    Uint8List? data,
    String? mimeType,
    required Uint8List manifestData,
    bool detailed = false,
    int? contextHandle,
  }) {
    if ((path == null) == (data == null)) {
      throw ArgumentError('Provide exactly one of path or data');
    }
    return _call(
      () => _api.readWithManifest(
        path,
        data,
        mimeType,
        manifestData,
        _format(detailed),
        contextHandle,
      ),
    );
  }

  @override
  Future<String> readFragment({
    required String initPath,
    required String fragmentPath,
    String? mimeType,
    bool detailed = false,
    int? contextHandle,
  }) => _call(
    () => _api.readFragment(
      initPath,
      fragmentPath,
      mimeType,
      _format(detailed),
      contextHandle,
    ),
  );

  @override
  Future<Uint8List> extractResource(
    Uint8List data,
    String mimeType,
    String uri, {
    int? contextHandle,
  }) => _call(() => _api.extractResource(data, mimeType, uri, contextHandle));

  @override
  Future<String?> getRemoteUrl(String path, {String? mimeType}) =>
      _call(() => _api.getRemoteUrl(path, mimeType));

  @override
  Future<bool> isManifestEmbedded(String path, {String? mimeType}) =>
      _call(() => _api.isManifestEmbedded(path, mimeType));

  @override
  Future<List<String>> getSupportedReadMimeTypes() =>
      _call(_api.getSupportedReadMimeTypes);

  @override
  Future<List<String>> getSupportedSignMimeTypes() =>
      _call(_api.getSupportedSignMimeTypes);

  // ===========================================================================
  // One-shot signing
  // ===========================================================================

  @override
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) => _withSigner(signer, (message) async {
    final result = await _api.signBytes(
      sourceData,
      mimeType,
      manifestJson,
      message!,
    );
    return SignResult(
      signedData: result.signedData!,
      manifestBytes: result.manifestBytes,
    );
  });

  @override
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) => _withSigner(
    signer,
    (message) => _api.signFile(sourcePath, destPath, manifestJson, message!),
  );

  @override
  Future<int> getSignerReserveSize(C2paSigner signer) =>
      _withSigner(signer, (message) => _api.getSignerReserveSize(message!));

  @override
  Future<Uint8List> composeManifest({
    required Uint8List manifestBytes,
    required String mimeType,
  }) => _call(() => _api.composeManifest(manifestBytes, mimeType));

  // ===========================================================================
  // Builder
  // ===========================================================================

  PigeonManifestBuilder _builder(int handle) =>
      PigeonManifestBuilder(this, handle);

  @override
  Future<ManifestBuilder> createBuilder(
    String manifestJson, {
    int? contextHandle,
  }) async => _builder(
    await _call(() => _api.createBuilder(manifestJson, contextHandle)),
  );

  @override
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData, {
    int? contextHandle,
  }) async => _builder(
    await _call(
      () => _api.createBuilderFromArchive(archiveData, contextHandle),
    ),
  );

  @override
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) => createBuilder(manifestJson, contextHandle: contextHandle);

  @override
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) async => _builder(
    await _call(
      () => _api.createBuilderWithSettings(manifestJson, settingsHandle),
    ),
  );

  @override
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) => _call(
    () => _api.builderSetIntent(
      handle,
      ManifestIntentMessage.values.byName(intent.name),
      digitalSourceType?.name,
    ),
  );

  @override
  Future<void> builderSetNoEmbed(int handle) =>
      _call(() => _api.builderSetNoEmbed(handle));

  @override
  Future<void> builderSetRemoteUrl(int handle, String url) =>
      _call(() => _api.builderSetRemoteUrl(handle, url));

  @override
  Future<void> builderSetBasePath(int handle, String path) =>
      _call(() => _api.builderSetBasePath(handle, path));

  @override
  Future<void> builderAddResource(int handle, String uri, Uint8List data) =>
      _call(() => _api.builderAddResource(handle, uri, data));

  @override
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) => _call(
    () => _api.builderAddIngredient(handle, data, mimeType, ingredientJson),
  );

  @override
  Future<void> builderAddIngredientFromFile(
    int handle,
    String path,
    String? mimeType,
    String? ingredientJson,
  ) => _call(
    () => _api.builderAddIngredientFromFile(
      handle,
      path,
      mimeType,
      ingredientJson,
    ),
  );

  @override
  Future<void> builderAddIngredientFromArchive(int handle, Uint8List archive) =>
      _call(() => _api.builderAddIngredientFromArchive(handle, archive));

  @override
  Future<Uint8List> builderWriteIngredientArchive(
    int handle,
    String ingredientId,
  ) => _call(() => _api.builderWriteIngredientArchive(handle, ingredientId));

  @override
  Future<void> builderAddAction(int handle, String actionJson) =>
      _call(() => _api.builderAddAction(handle, actionJson));

  @override
  Future<Uint8List> builderToArchive(int handle) =>
      _call(() => _api.builderToArchive(handle));

  @override
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner? signer,
  ) => _withSigner(signer, (message) async {
    final result = await _api.builderSign(
      handle,
      sourceData,
      mimeType,
      message,
    );
    return BuilderSignResult(
      signedData: result.signedData!,
      manifestBytes: result.manifestBytes,
      manifestSize: result.manifestSize,
    );
  });

  @override
  Future<BuilderFileSignResult> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner? signer, {
    String? mimeType,
  }) => _withSigner(signer, (message) async {
    final result = await _api.builderSignFile(
      handle,
      sourcePath,
      destPath,
      mimeType,
      message,
    );
    return BuilderFileSignResult(
      manifestBytes: result.manifestBytes,
      manifestSize: result.manifestSize,
    );
  });

  @override
  Future<bool> builderNeedsPlaceholder(int handle, String mimeType) =>
      _call(() => _api.builderNeedsPlaceholder(handle, mimeType));

  @override
  Future<Uint8List> builderPlaceholder(int handle, String mimeType) =>
      _call(() => _api.builderPlaceholder(handle, mimeType));

  @override
  Future<void> builderSetDataHashExclusions(
    int handle,
    List<DataHashExclusion> exclusions,
  ) => _call(
    () => _api.builderSetDataHashExclusions(handle, [
      for (final e in exclusions)
        DataHashExclusionMessage(start: e.start, length: e.length),
    ]),
  );

  @override
  Future<void> builderUpdateHashFromBytes(
    int handle,
    String mimeType,
    Uint8List data,
  ) => _call(() => _api.builderUpdateHashFromBytes(handle, mimeType, data));

  @override
  Future<void> builderUpdateHashFromFile(
    int handle,
    String path, {
    String? mimeType,
  }) => _call(() => _api.builderUpdateHashFromFile(handle, path, mimeType));

  @override
  Future<Uint8List> builderSignEmbeddable(int handle, String mimeType) =>
      _call(() => _api.builderSignEmbeddable(handle, mimeType));

  @override
  Future<C2paHashType> builderHashType(int handle, String mimeType) async {
    final type = await _call(() => _api.builderHashType(handle, mimeType));
    return C2paHashType.values.byName(type.name);
  }

  @override
  Future<void> builderSetFixedSizeMerkle(int handle, int fixedSizeKb) =>
      _call(() => _api.builderSetFixedSizeMerkle(handle, fixedSizeKb));

  @override
  Future<void> builderHashMdatBytes(
    int handle, {
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) => _call(() => _api.builderHashMdatBytes(handle, mdatId, data, largeSize));

  @override
  Future<void> builderDispose(int handle) =>
      _call(() => _api.builderDispose(handle));

  // ===========================================================================
  // Key Management
  // ===========================================================================

  @override
  Future<bool> isHardwareSigningAvailable() =>
      _call(_api.isHardwareSigningAvailable);

  @override
  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) =>
      _call(() => _api.createKey(keyAlias, _algorithm(algorithm), useHardware));

  @override
  Future<bool> deleteKey(String keyAlias) =>
      _call(() => _api.deleteKey(keyAlias));

  @override
  Future<bool> keyExists(String keyAlias) =>
      _call(() => _api.keyExists(keyAlias));

  @override
  Future<String> exportPublicKey(String keyAlias) =>
      _call(() => _api.exportPublicKey(keyAlias));

  @override
  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) =>
      _call(() => _api.importKey(keyAlias, privateKeyPem, certificateChainPem));

  @override
  Future<String> createCSR({
    required String keyAlias,
    required CertificateConfig config,
  }) => _call(() => _api.createCSR(keyAlias, _certificateConfig(config)));

  @override
  Future<HardwareKeyEnrollment> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) async {
    final result = await _call(
      () => _api.enrollHardwareKey(
        keyAlias,
        signingServerUrl,
        bearerToken,
        commonName,
        organization,
        useStrongBox,
      ),
    );
    return HardwareKeyEnrollment(
      keyAlias: result.keyAlias,
      certificateChainPem: result.certificateChainPem,
    );
  }

  @override
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    CertificateConfig? config,
  }) => _call(
    () => _api.createSelfSignedCertificateChain(
      keyAlias,
      config == null ? null : _certificateConfig(config),
    ),
  );

  static CertificateConfigMessage _certificateConfig(CertificateConfig c) =>
      CertificateConfigMessage(
        commonName: c.commonName,
        organization: c.organization,
        organizationalUnit: c.organizationalUnit,
        country: c.country,
        state: c.state,
        locality: c.locality,
        emailAddress: c.email,
        validityDays: c.validityDays,
      );

  // ===========================================================================
  // Settings
  // ===========================================================================

  @override
  Future<void> loadSettings(String settings, String format) =>
      _call(() => _api.loadSettings(settings, format));

  @override
  Future<int> createSettings() => _call(_api.createSettings);

  @override
  Future<void> settingsUpdateFromString(
    int handle,
    String settings,
    String format,
  ) => _call(() => _api.settingsUpdateFromString(handle, settings, format));

  @override
  Future<void> settingsSetValue(int handle, String path, Object value) =>
      _call(() => _api.settingsSetValue(handle, path, jsonEncode(value)));

  @override
  Future<void> settingsDispose(int handle) =>
      _call(() => _api.settingsDispose(handle));

  // ===========================================================================
  // Contexts
  // ===========================================================================

  @override
  Future<int> createContext({
    int? settingsHandle,
    C2paSigner? signer,
    void Function(C2paProgress progress)? onProgress,
    C2paHttpResolver? httpResolver,
  }) async {
    final ids = <String>[];
    final message = signer == null ? null : _signerMessage(signer, ids);
    if (onProgress != null || httpResolver is CallbackHttpResolver) {
      _ensureFlutterApi();
    }
    try {
      final handle = await _call(
        () => _api.createContext(
          settingsHandle,
          message,
          onProgress != null,
          switch (httpResolver) {
            null => null,
            NativeHttpResolver() => HttpResolverModeMessage.native,
            CallbackHttpResolver() => HttpResolverModeMessage.callback,
          },
        ),
      );
      _contextCallbacks[handle] = _ContextCallbacks(
        onProgress: onProgress,
        httpResolver: httpResolver,
        signCallbackIds: ids,
      );
      return handle;
    } catch (_) {
      ids.forEach(_signCallbacks.remove);
      rethrow;
    }
  }

  @override
  Future<void> contextCancel(int handle) =>
      _call(() => _api.contextCancel(handle));

  @override
  Future<void> contextDispose(int handle) async {
    try {
      await _call(() => _api.contextDispose(handle));
    } finally {
      final callbacks = _contextCallbacks.remove(handle);
      callbacks?.signCallbackIds.forEach(_signCallbacks.remove);
    }
  }
}

/// Releases the native builder of a [PigeonManifestBuilder] that was garbage
/// collected without [PigeonManifestBuilder.dispose].
final Finalizer<int> _builderFinalizer = Finalizer<int>(
  (handle) => unawaited(
    C2paPlatform.instance.builderDispose(handle).catchError((Object _) {}),
  ),
);

/// [ManifestBuilder] over [PigeonC2pa].
///
/// Calls run one after another in the order they were made, whether or not
/// the caller awaits each one, so a [sign] issued straight after an
/// un-awaited [addIngredient] still sees the ingredient.
class PigeonManifestBuilder implements ManifestBuilder {
  final PigeonC2pa _platform;
  final int _handle;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();

  PigeonManifestBuilder(this._platform, this._handle) {
    _builderFinalizer.attach(this, _handle, detach: this);
  }

  @override
  int get handle {
    _checkDisposed();
    return _handle;
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('ManifestBuilder has been disposed');
    }
  }

  /// Runs [body] after every earlier call on this builder has finished.
  Future<T> _run<T>(Future<T> Function() body) {
    _checkDisposed();
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> setIntent(
    ManifestIntent intent, [
    DigitalSourceType? digitalSourceType,
  ]) => _run(
    () => _platform.builderSetIntent(_handle, intent, digitalSourceType),
  );

  @override
  Future<void> setNoEmbed() => _run(() => _platform.builderSetNoEmbed(_handle));

  @override
  Future<void> setRemoteUrl(String url) =>
      _run(() => _platform.builderSetRemoteUrl(_handle, url));

  @override
  Future<void> addAction(ActionConfig action) {
    final json = action.toJson();
    return _run(() => _platform.builderAddAction(_handle, json));
  }

  @override
  Future<void> setBasePath(String path) =>
      _run(() => _platform.builderSetBasePath(_handle, path));

  @override
  Future<void> addResource(BuilderResource resource) => _run(
    () => _platform.builderAddResource(_handle, resource.uri, resource.data),
  );

  @override
  Future<void> addIngredient({
    required Uint8List data,
    required String mimeType,
    IngredientConfig? config,
  }) => _run(
    () => _platform.builderAddIngredient(
      _handle,
      data,
      mimeType,
      config?.toJson(),
    ),
  );

  @override
  Future<void> addIngredientFromFile({
    required String path,
    String? mimeType,
    IngredientConfig? config,
  }) => _run(
    () => _platform.builderAddIngredientFromFile(
      _handle,
      path,
      mimeType,
      config?.toJson(),
    ),
  );

  @override
  Future<void> addIngredientFromArchive(Uint8List archive) =>
      _run(() => _platform.builderAddIngredientFromArchive(_handle, archive));

  @override
  Future<Uint8List> writeIngredientArchive(String ingredientId) => _run(
    () => _platform.builderWriteIngredientArchive(_handle, ingredientId),
  );

  @override
  Future<BuilderArchive> toArchive() => _run(() async {
    return BuilderArchive(data: await _platform.builderToArchive(_handle));
  });

  @override
  Future<BuilderSignResult> sign({
    required Uint8List sourceData,
    required String mimeType,
    C2paSigner? signer,
  }) =>
      _run(() => _platform.builderSign(_handle, sourceData, mimeType, signer));

  @override
  Future<BuilderFileSignResult> signFile({
    required String sourcePath,
    required String destPath,
    C2paSigner? signer,
    String? mimeType,
  }) => _run(
    () => _platform.builderSignFile(
      _handle,
      sourcePath,
      destPath,
      signer,
      mimeType: mimeType,
    ),
  );

  @override
  Future<bool> needsPlaceholder(String mimeType) =>
      _run(() => _platform.builderNeedsPlaceholder(_handle, mimeType));

  @override
  Future<Uint8List> placeholder(String mimeType) =>
      _run(() => _platform.builderPlaceholder(_handle, mimeType));

  @override
  Future<void> setDataHashExclusions(List<DataHashExclusion> exclusions) =>
      _run(() => _platform.builderSetDataHashExclusions(_handle, exclusions));

  @override
  Future<void> updateHashFromBytes(String mimeType, Uint8List data) =>
      _run(() => _platform.builderUpdateHashFromBytes(_handle, mimeType, data));

  @override
  Future<void> updateHashFromFile(String path, {String? mimeType}) => _run(
    () =>
        _platform.builderUpdateHashFromFile(_handle, path, mimeType: mimeType),
  );

  @override
  Future<Uint8List> signEmbeddable(String mimeType) =>
      _run(() => _platform.builderSignEmbeddable(_handle, mimeType));

  @override
  Future<C2paHashType> hashType(String mimeType) =>
      _run(() => _platform.builderHashType(_handle, mimeType));

  @override
  Future<void> setFixedSizeMerkle(int fixedSizeKb) =>
      _run(() => _platform.builderSetFixedSizeMerkle(_handle, fixedSizeKb));

  @override
  Future<void> hashMdatBytes({
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) => _run(
    () => _platform.builderHashMdatBytes(
      _handle,
      mdatId: mdatId,
      data: data,
      largeSize: largeSize,
    ),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _builderFinalizer.detach(this);
    await _tail;
    await _platform.builderDispose(_handle);
  }
}
