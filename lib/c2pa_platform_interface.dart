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

import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'c2pa.dart';
import 'c2pa_pigeon.dart';

Never _unimplemented(String method) =>
    throw UnimplementedError('$method() has not been implemented.');

/// Platform interface for C2PA operations.
///
/// Implementations must provide native platform bindings for reading,
/// signing, and verifying C2PA manifests.
abstract class C2paPlatform extends PlatformInterface {
  C2paPlatform() : super(token: _token);

  static final Object _token = Object();

  static C2paPlatform _instance = PigeonC2pa();

  /// Returns the current platform instance.
  static C2paPlatform get instance => _instance;

  /// Sets the platform [instance], verifying the token.
  static set instance(C2paPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ===========================================================================
  // Version and Platform Info
  // ===========================================================================

  /// Returns the platform version string.
  Future<String?> getPlatformVersion() => _unimplemented('getPlatformVersion');

  /// Returns the C2PA library version.
  Future<String?> getVersion() => _unimplemented('getVersion');

  // ===========================================================================
  // Reader
  // ===========================================================================

  /// Reads the manifest store JSON from the file at [path].
  Future<String> readFile(String path) => _unimplemented('readFile');

  /// Reads the manifest store JSON from [data].
  Future<String> readBytes(Uint8List data, String mimeType) =>
      _unimplemented('readBytes');

  /// Reads the manifest store JSON (detailed when [detailed]) from a file.
  Future<String> readFileDetailed(
    String path,
    bool detailed, {
    int? contextHandle,
  }) => _unimplemented('readFileDetailed');

  /// Reads the manifest store JSON (detailed when [detailed]) from bytes.
  Future<String> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed, {
    int? contextHandle,
  }) => _unimplemented('readBytesDetailed');

  /// Reads the manifest store as crJSON from a file ([path]) or bytes
  /// ([data] with [mimeType]).
  Future<String> readCrJson({
    String? path,
    Uint8List? data,
    String? mimeType,
    int? contextHandle,
  }) => _unimplemented('readCrJson');

  /// Reads an asset whose manifest is supplied separately in [manifestData].
  Future<String> readWithManifest({
    String? path,
    Uint8List? data,
    String? mimeType,
    required Uint8List manifestData,
    bool detailed = false,
    int? contextHandle,
  }) => _unimplemented('readWithManifest');

  /// Reads a fragmented BMFF asset from its init segment and one fragment.
  Future<String> readFragment({
    required String initPath,
    required String fragmentPath,
    String? mimeType,
    bool detailed = false,
    int? contextHandle,
  }) => _unimplemented('readFragment');

  /// Extracts the resource [uri] from the manifest store in [data].
  Future<Uint8List> extractResource(
    Uint8List data,
    String mimeType,
    String uri, {
    int? contextHandle,
  }) => _unimplemented('extractResource');

  /// Returns the remote manifest URL of the file at [path], if any.
  Future<String?> getRemoteUrl(String path, {String? mimeType}) =>
      _unimplemented('getRemoteUrl');

  /// Whether the manifest at [path] is embedded (true) or only referenced
  /// remotely (false).
  Future<bool> isManifestEmbedded(String path, {String? mimeType}) =>
      _unimplemented('isManifestEmbedded');

  /// MIME types the native SDK can read.
  Future<List<String>> getSupportedReadMimeTypes() =>
      _unimplemented('getSupportedReadMimeTypes');

  /// MIME types the native SDK can sign.
  Future<List<String>> getSupportedSignMimeTypes() =>
      _unimplemented('getSupportedSignMimeTypes');

  // ===========================================================================
  // One-shot signing
  // ===========================================================================

  /// Signs [sourceData] with [manifestJson] and [signer].
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) => _unimplemented('signBytes');

  /// Signs the file at [sourcePath] into [destPath].
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) => _unimplemented('signFile');

  /// Size in bytes the signer reserves for its signature.
  Future<int> getSignerReserveSize(C2paSigner signer) =>
      _unimplemented('getSignerReserveSize');

  /// Wraps raw `application/c2pa` manifest bytes in the framing [mimeType]
  /// embeds.
  Future<Uint8List> composeManifest({
    required Uint8List manifestBytes,
    required String mimeType,
  }) => _unimplemented('composeManifest');

  // ===========================================================================
  // Builder
  // ===========================================================================

  /// Creates a builder from a manifest definition, optionally on a context.
  Future<ManifestBuilder> createBuilder(
    String manifestJson, {
    int? contextHandle,
  }) => _unimplemented('createBuilder');

  /// Restores a builder from an archive, optionally on a context.
  Future<ManifestBuilder> createBuilderFromArchive(
    Uint8List archiveData, {
    int? contextHandle,
  }) => _unimplemented('createBuilderFromArchive');

  /// Creates a builder on the context [contextHandle].
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) => _unimplemented('createBuilderWithContext');

  /// Creates a builder on a context built from [settingsHandle].
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) => _unimplemented('createBuilderWithSettings');

  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) => _unimplemented('builderSetIntent');

  Future<void> builderSetNoEmbed(int handle) =>
      _unimplemented('builderSetNoEmbed');

  Future<void> builderSetRemoteUrl(int handle, String url) =>
      _unimplemented('builderSetRemoteUrl');

  Future<void> builderSetBasePath(int handle, String path) =>
      _unimplemented('builderSetBasePath');

  Future<void> builderAddResource(int handle, String uri, Uint8List data) =>
      _unimplemented('builderAddResource');

  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) => _unimplemented('builderAddIngredient');

  Future<void> builderAddIngredientFromFile(
    int handle,
    String path,
    String? mimeType,
    String? ingredientJson,
  ) => _unimplemented('builderAddIngredientFromFile');

  Future<void> builderAddIngredientFromArchive(int handle, Uint8List archive) =>
      _unimplemented('builderAddIngredientFromArchive');

  Future<Uint8List> builderWriteIngredientArchive(
    int handle,
    String ingredientId,
  ) => _unimplemented('builderWriteIngredientArchive');

  Future<void> builderAddAction(int handle, String actionJson) =>
      _unimplemented('builderAddAction');

  Future<Uint8List> builderToArchive(int handle) =>
      _unimplemented('builderToArchive');

  /// Signs with [signer], or with the builder's context signer when null.
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner? signer,
  ) => _unimplemented('builderSign');

  /// Signs a file with [signer], or with the context signer when null.
  Future<BuilderFileSignResult> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner? signer, {
    String? mimeType,
  }) => _unimplemented('builderSignFile');

  Future<bool> builderNeedsPlaceholder(int handle, String mimeType) =>
      _unimplemented('builderNeedsPlaceholder');

  Future<Uint8List> builderPlaceholder(int handle, String mimeType) =>
      _unimplemented('builderPlaceholder');

  Future<void> builderSetDataHashExclusions(
    int handle,
    List<DataHashExclusion> exclusions,
  ) => _unimplemented('builderSetDataHashExclusions');

  Future<void> builderUpdateHashFromBytes(
    int handle,
    String mimeType,
    Uint8List data,
  ) => _unimplemented('builderUpdateHashFromBytes');

  Future<void> builderUpdateHashFromFile(
    int handle,
    String path, {
    String? mimeType,
  }) => _unimplemented('builderUpdateHashFromFile');

  Future<Uint8List> builderSignEmbeddable(int handle, String mimeType) =>
      _unimplemented('builderSignEmbeddable');

  Future<C2paHashType> builderHashType(int handle, String mimeType) =>
      _unimplemented('builderHashType');

  Future<void> builderSetFixedSizeMerkle(int handle, int fixedSizeKb) =>
      _unimplemented('builderSetFixedSizeMerkle');

  Future<void> builderHashMdatBytes(
    int handle, {
    required int mdatId,
    required Uint8List data,
    bool largeSize = false,
  }) => _unimplemented('builderHashMdatBytes');

  Future<void> builderDispose(int handle) => _unimplemented('builderDispose');

  // ===========================================================================
  // Key Management
  // ===========================================================================

  Future<bool> isHardwareSigningAvailable() =>
      _unimplemented('isHardwareSigningAvailable');

  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) => _unimplemented('createKey');

  Future<bool> deleteKey(String keyAlias) => _unimplemented('deleteKey');

  Future<bool> keyExists(String keyAlias) => _unimplemented('keyExists');

  Future<String> exportPublicKey(String keyAlias) =>
      _unimplemented('exportPublicKey');

  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) => _unimplemented('importKey');

  Future<String> createCSR({
    required String keyAlias,
    required CertificateConfig config,
  }) => _unimplemented('createCSR');

  Future<HardwareKeyEnrollment> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) => _unimplemented('enrollHardwareKey');

  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    CertificateConfig? config,
  }) => _unimplemented('createSelfSignedCertificateChain');

  // ===========================================================================
  // Settings
  // ===========================================================================

  /// Loads settings applied to readers and builders created without a
  /// context.
  Future<void> loadSettings(String settings, String format) =>
      _unimplemented('loadSettings');

  Future<int> createSettings() => _unimplemented('createSettings');

  Future<void> settingsUpdateFromString(
    int handle,
    String settings,
    String format,
  ) => _unimplemented('settingsUpdateFromString');

  Future<void> settingsSetValue(int handle, String path, Object value) =>
      _unimplemented('settingsSetValue');

  Future<void> settingsDispose(int handle) => _unimplemented('settingsDispose');

  // ===========================================================================
  // Contexts
  // ===========================================================================

  /// Creates a native context. [onProgress] and [httpResolver] stay
  /// registered until [contextDispose].
  Future<int> createContext({
    int? settingsHandle,
    C2paSigner? signer,
    void Function(C2paProgress progress)? onProgress,
    C2paHttpResolver? httpResolver,
  }) => _unimplemented('createContext');

  /// Cancels every operation running on the context.
  Future<void> contextCancel(int handle) => _unimplemented('contextCancel');

  Future<void> contextDispose(int handle) => _unimplemented('contextDispose');
}
