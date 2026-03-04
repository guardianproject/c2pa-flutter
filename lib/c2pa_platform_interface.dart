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
import 'c2pa_method_channel.dart';

/// Platform interface for C2PA operations.
///
/// Implementations must provide native platform bindings for reading,
/// signing, and verifying C2PA manifests.
abstract class C2paPlatform extends PlatformInterface {
  C2paPlatform() : super(token: _token);

  static final Object _token = Object();

  static C2paPlatform _instance = MethodChannelC2pa();

  /// Returns the current platform instance.
  static C2paPlatform get instance => _instance;

  /// Sets the platform [instance], verifying the token.
  static set instance(C2paPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // =============================================================================
  // Version and Platform Info
  // =============================================================================

  /// Returns the platform version string.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Returns the C2PA library version.
  Future<String?> getVersion() {
    throw UnimplementedError('getVersion() has not been implemented.');
  }

  // =============================================================================
  // Reader API - Basic
  // =============================================================================

  /// Reads a C2PA manifest from a file at [path].
  Future<String?> readFile(String path) {
    throw UnimplementedError('readFile() has not been implemented.');
  }

  /// Reads a C2PA manifest from [data] bytes with the given [mimeType].
  Future<String?> readBytes(Uint8List data, String mimeType) {
    throw UnimplementedError('readBytes() has not been implemented.');
  }

  // =============================================================================
  // Reader API - Enhanced
  // =============================================================================

  /// Reads a C2PA manifest from a file at [path] with optional [detailed] output and [dataDir].
  Future<String?> readFileDetailed(
    String path,
    bool detailed,
    String? dataDir,
  ) {
    throw UnimplementedError('readFileDetailed() has not been implemented.');
  }

  /// Reads a C2PA manifest from [data] bytes with optional [detailed] output.
  Future<String?> readBytesDetailed(
    Uint8List data,
    String mimeType,
    bool detailed,
  ) {
    throw UnimplementedError('readBytesDetailed() has not been implemented.');
  }

  /// Extracts a resource at [uri] from [data] bytes with the given [mimeType].
  Future<Uint8List?> extractResource(
    Uint8List data,
    String mimeType,
    String uri,
  ) {
    throw UnimplementedError('extractResource() has not been implemented.');
  }

  /// Reads ingredient data from a file at [path] with an optional [dataDir].
  Future<String?> readIngredientFile(String path, String? dataDir) {
    throw UnimplementedError('readIngredientFile() has not been implemented.');
  }

  /// Returns the list of MIME types supported for reading.
  Future<List<String>> getSupportedReadMimeTypes() {
    throw UnimplementedError(
      'getSupportedReadMimeTypes() has not been implemented.',
    );
  }

  /// Returns the list of MIME types supported for signing.
  Future<List<String>> getSupportedSignMimeTypes() {
    throw UnimplementedError(
      'getSupportedSignMimeTypes() has not been implemented.',
    );
  }

  // =============================================================================
  // Signer API - Basic
  // =============================================================================

  /// Signs [sourceData] bytes with the given [mimeType], [manifestJson], and [signer].
  Future<SignResult> signBytes({
    required Uint8List sourceData,
    required String mimeType,
    required String manifestJson,
    required C2paSigner signer,
  }) {
    throw UnimplementedError('signBytes() has not been implemented.');
  }

  /// Signs a file at [sourcePath] and writes the result to [destPath].
  Future<void> signFile({
    required String sourcePath,
    required String destPath,
    required String manifestJson,
    required C2paSigner signer,
  }) {
    throw UnimplementedError('signFile() has not been implemented.');
  }

  // =============================================================================
  // Builder API
  // =============================================================================

  /// Creates a new manifest builder from [manifestJson].
  Future<ManifestBuilder> createBuilder(String manifestJson) {
    throw UnimplementedError('createBuilder() has not been implemented.');
  }

  /// Creates a manifest builder from serialized [archiveData].
  Future<ManifestBuilder> createBuilderFromArchive(Uint8List archiveData) {
    throw UnimplementedError(
      'createBuilderFromArchive() has not been implemented.',
    );
  }

  /// Sets the [intent] and optional [digitalSourceType] on the builder at [handle].
  Future<void> builderSetIntent(
    int handle,
    ManifestIntent intent,
    DigitalSourceType? digitalSourceType,
  ) {
    throw UnimplementedError('builderSetIntent() has not been implemented.');
  }

  /// Disables manifest embedding for the builder at [handle].
  Future<void> builderSetNoEmbed(int handle) {
    throw UnimplementedError('builderSetNoEmbed() has not been implemented.');
  }

  /// Sets a remote manifest [url] on the builder at [handle].
  Future<void> builderSetRemoteUrl(int handle, String url) {
    throw UnimplementedError('builderSetRemoteUrl() has not been implemented.');
  }

  /// Adds a resource with [uri] and [data] to the builder at [handle].
  Future<void> builderAddResource(int handle, String uri, Uint8List data) {
    throw UnimplementedError('builderAddResource() has not been implemented.');
  }

  /// Adds an ingredient from [data] bytes with [mimeType] to the builder at [handle].
  Future<void> builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  ) {
    throw UnimplementedError(
      'builderAddIngredient() has not been implemented.',
    );
  }

  /// Adds an action from [actionJson] to the builder at [handle].
  Future<void> builderAddAction(int handle, String actionJson) {
    throw UnimplementedError('builderAddAction() has not been implemented.');
  }

  /// Serializes the builder at [handle] to an archive byte array.
  Future<Uint8List> builderToArchive(int handle) {
    throw UnimplementedError('builderToArchive() has not been implemented.');
  }

  /// Signs [sourceData] bytes using the builder at [handle] with the given [signer].
  Future<BuilderSignResult> builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    C2paSigner signer,
  ) {
    throw UnimplementedError('builderSign() has not been implemented.');
  }

  /// Signs a file at [sourcePath] using the builder at [handle] and writes to [destPath].
  Future<void> builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    C2paSigner signer,
  ) {
    throw UnimplementedError('builderSignFile() has not been implemented.');
  }

  /// Disposes the builder at [handle] and releases its resources.
  Future<void> builderDispose(int handle) {
    throw UnimplementedError('builderDispose() has not been implemented.');
  }

  // =============================================================================
  // Advanced Signing API
  // =============================================================================

  /// Creates a hashed placeholder for deferred signing with the given [reservedSize] and [mimeType].
  Future<Uint8List> createHashedPlaceholder({
    required int builderHandle,
    required int reservedSize,
    required String mimeType,
  }) {
    throw UnimplementedError(
      'createHashedPlaceholder() has not been implemented.',
    );
  }

  /// Signs a [dataHash] to produce an embeddable manifest using the given [signer].
  Future<Uint8List> signHashedEmbeddable({
    required int builderHandle,
    required C2paSigner signer,
    required String dataHash,
    required String mimeType,
    Uint8List? assetData,
  }) {
    throw UnimplementedError(
      'signHashedEmbeddable() has not been implemented.',
    );
  }

  /// Formats [manifestBytes] as an embeddable manifest for the given [mimeType].
  Future<Uint8List> formatEmbeddable({
    required String mimeType,
    required Uint8List manifestBytes,
  }) {
    throw UnimplementedError('formatEmbeddable() has not been implemented.');
  }

  /// Returns the reserved size needed for the given [signer].
  Future<int> getSignerReserveSize(C2paSigner signer) {
    throw UnimplementedError(
      'getSignerReserveSize() has not been implemented.',
    );
  }

  // =============================================================================
  // Key Management API
  // =============================================================================

  /// Returns whether hardware-backed signing is available on this device.
  Future<bool> isHardwareSigningAvailable() {
    throw UnimplementedError(
      'isHardwareSigningAvailable() has not been implemented.',
    );
  }

  /// Creates a signing key with the given [keyAlias], [algorithm], and hardware preference.
  Future<void> createKey({
    required String keyAlias,
    required SigningAlgorithm algorithm,
    required bool useHardware,
  }) {
    throw UnimplementedError('createKey() has not been implemented.');
  }

  /// Deletes the key identified by [keyAlias].
  Future<bool> deleteKey(String keyAlias) {
    throw UnimplementedError('deleteKey() has not been implemented.');
  }

  /// Returns whether a key with [keyAlias] exists.
  Future<bool> keyExists(String keyAlias) {
    throw UnimplementedError('keyExists() has not been implemented.');
  }

  /// Exports the public key for [keyAlias] as a PEM string.
  Future<String> exportPublicKey(String keyAlias) {
    throw UnimplementedError('exportPublicKey() has not been implemented.');
  }

  /// Imports a private key and certificate chain under [keyAlias].
  Future<void> importKey({
    required String keyAlias,
    required String privateKeyPem,
    required String certificateChainPem,
  }) {
    throw UnimplementedError('importKey() has not been implemented.');
  }

  /// Creates a certificate signing request (CSR) for the key at [keyAlias].
  Future<String> createCSR({
    required String keyAlias,
    required String commonName,
    String? organization,
    String? organizationalUnit,
    String? country,
    String? state,
    String? locality,
  }) {
    throw UnimplementedError('createCSR() has not been implemented.');
  }

  /// Enrolls a hardware key at [keyAlias] with a signing server at [signingServerUrl].
  Future<Map<String, dynamic>> enrollHardwareKey({
    required String keyAlias,
    required String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox = false,
  }) {
    throw UnimplementedError('enrollHardwareKey() has not been implemented.');
  }

  // =============================================================================
  // Settings API
  // =============================================================================

  /// Loads global settings from a [settings] string in the given [format].
  Future<void> loadSettings(String settings, String format) {
    throw UnimplementedError('loadSettings() has not been implemented.');
  }

  // =============================================================================
  // C2PASettings Handle API
  // =============================================================================

  /// Creates a new settings handle.
  Future<int> createSettings() {
    throw UnimplementedError('createSettings() has not been implemented.');
  }

  /// Updates the settings at [handle] from [settingsStr] in the given [format].
  Future<void> settingsUpdateFromString(
    int handle,
    String settingsStr,
    String format,
  ) {
    throw UnimplementedError(
      'settingsUpdateFromString() has not been implemented.',
    );
  }

  /// Sets a single settings [value] at [path] on the settings at [handle].
  Future<void> settingsSetValue(int handle, String path, String value) {
    throw UnimplementedError('settingsSetValue() has not been implemented.');
  }

  /// Disposes the settings at [handle] and releases its resources.
  Future<void> settingsDispose(int handle) {
    throw UnimplementedError('settingsDispose() has not been implemented.');
  }

  // =============================================================================
  // C2PAContext Handle API
  // =============================================================================

  /// Creates a new C2PA context handle with default settings.
  Future<int> createContext() {
    throw UnimplementedError('createContext() has not been implemented.');
  }

  /// Creates a new C2PA context handle from the given [settingsHandle].
  Future<int> createContextFromSettings(int settingsHandle) {
    throw UnimplementedError(
      'createContextFromSettings() has not been implemented.',
    );
  }

  /// Disposes the context at [handle] and releases its resources.
  Future<void> contextDispose(int handle) {
    throw UnimplementedError('contextDispose() has not been implemented.');
  }

  // =============================================================================
  // Enhanced Reader API
  // =============================================================================

  /// Reads a C2PA manifest from a file at [path] using the given [contextHandle].
  Future<String?> readFileWithContext(
    String path,
    int contextHandle,
    bool detailed,
    String? dataDir,
  ) {
    throw UnimplementedError(
      'readFileWithContext() has not been implemented.',
    );
  }

  // =============================================================================
  // Enhanced Builder API
  // =============================================================================

  /// Creates a manifest builder from [manifestJson] using the given [contextHandle].
  Future<ManifestBuilder> createBuilderWithContext(
    int contextHandle,
    String manifestJson,
  ) {
    throw UnimplementedError(
      'createBuilderWithContext() has not been implemented.',
    );
  }

  /// Creates a manifest builder from [manifestJson] using the given [settingsHandle].
  Future<ManifestBuilder> createBuilderWithSettings(
    String manifestJson,
    int settingsHandle,
  ) {
    throw UnimplementedError(
      'createBuilderWithSettings() has not been implemented.',
    );
  }

  // =============================================================================
  // Certificate Manager API
  // =============================================================================

  /// Creates a self-signed certificate chain for the key at [keyAlias].
  Future<String> createSelfSignedCertificateChain({
    required String keyAlias,
    Map<String, dynamic>? config,
  }) {
    throw UnimplementedError(
      'createSelfSignedCertificateChain() has not been implemented.',
    );
  }
}
