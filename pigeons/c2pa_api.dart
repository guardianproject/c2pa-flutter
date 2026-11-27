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

// The interface between the Dart plugin and the native plugins. Generate the
// Dart, Kotlin and Swift bindings with `make pigeon` after editing it.
//
// Methods use `@asyncCallback` rather than `@async`: the native plugins run
// each call on their own serial worker and reply through a callback, so the
// coroutine and async/await forms Pigeon generates for `@async` do not fit.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/c2pa_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/org/guardianproject/c2pa/C2paApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'org.guardianproject.c2pa'),
    swiftOut: 'ios/c2pa_flutter/Sources/c2pa_flutter/C2paApi.g.swift',
    swiftOptions: SwiftOptions(),
    copyrightHeader: 'pigeons/copyright_header.txt',
    dartPackageName: 'c2pa_flutter',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
enum SigningAlgorithmMessage { es256, es384, es512, ps256, ps384, ps512, ed25519 }

enum ManifestIntentMessage { create, edit, update }

/// Which JSON form a read returns.
enum ReadFormatMessage { json, detailed, crJson }

/// How a context answers the SDK's HTTP requests.
enum HttpResolverModeMessage { native, callback }

enum HashTypeMessage { dataHash, bmffHash, boxHash }

// ---------------------------------------------------------------------------
// Signers
// ---------------------------------------------------------------------------

sealed class SignerMessage {}

class PemSignerMessage extends SignerMessage {
  PemSignerMessage({
    required this.algorithm,
    required this.certificatePem,
    required this.privateKeyPem,
    this.tsaUrl,
  });

  SigningAlgorithmMessage algorithm;
  String certificatePem;
  String privateKeyPem;
  String? tsaUrl;
}

/// A signer whose signatures come from the Dart callback registered under
/// [callbackId].
class CallbackSignerMessage extends SignerMessage {
  CallbackSignerMessage({
    required this.algorithm,
    required this.certificateChainPem,
    required this.callbackId,
    this.tsaUrl,
  });

  SigningAlgorithmMessage algorithm;
  String certificateChainPem;
  String callbackId;
  String? tsaUrl;
}

class KeystoreSignerMessage extends SignerMessage {
  KeystoreSignerMessage({
    required this.algorithm,
    required this.certificateChainPem,
    required this.keyAlias,
    required this.requireUserAuthentication,
    this.tsaUrl,
  });

  SigningAlgorithmMessage algorithm;
  String certificateChainPem;
  String keyAlias;
  bool requireUserAuthentication;
  String? tsaUrl;
}

class HardwareSignerMessage extends SignerMessage {
  HardwareSignerMessage({
    required this.certificateChainPem,
    required this.keyAlias,
    required this.requireUserAuthentication,
    this.tsaUrl,
  });

  String certificateChainPem;
  String keyAlias;
  bool requireUserAuthentication;
  String? tsaUrl;
}

class RemoteSignerMessage extends SignerMessage {
  RemoteSignerMessage({
    required this.configurationUrl,
    this.bearerToken,
    required this.customHeaders,
  });

  String configurationUrl;
  String? bearerToken;
  Map<String, String> customHeaders;
}

/// A signer described by C2PA settings (`signer.local` or `signer.remote`).
class SettingsSignerMessage extends SignerMessage {
  SettingsSignerMessage({required this.settings, required this.format});

  String settings;
  String format;
}

class CawgIdentitySignerMessage extends SignerMessage {
  CawgIdentitySignerMessage({
    required this.claimSigner,
    required this.identitySigner,
    required this.referencedAssertions,
    required this.roles,
  });

  SignerMessage claimSigner;
  SignerMessage identitySigner;
  List<String> referencedAssertions;
  List<String> roles;
}

// ---------------------------------------------------------------------------
// Other messages
// ---------------------------------------------------------------------------

class SignResultMessage {
  SignResultMessage({
    this.signedData,
    this.manifestBytes,
    required this.manifestSize,
  });

  /// The signed asset, for in-memory signing. Null when signing to a file.
  Uint8List? signedData;
  Uint8List? manifestBytes;
  int manifestSize;
}

class DataHashExclusionMessage {
  DataHashExclusionMessage({required this.start, required this.length});

  int start;
  int length;
}

class CertificateConfigMessage {
  CertificateConfigMessage({
    required this.commonName,
    this.organization,
    this.organizationalUnit,
    this.country,
    this.state,
    this.locality,
    this.emailAddress,
    this.validityDays,
  });

  String commonName;
  String? organization;
  String? organizationalUnit;
  String? country;
  String? state;
  String? locality;
  String? emailAddress;
  int? validityDays;
}

class HardwareKeyEnrollmentMessage {
  HardwareKeyEnrollmentMessage({
    required this.keyAlias,
    required this.certificateChainPem,
  });

  String keyAlias;
  String certificateChainPem;
}

class HttpRequestMessage {
  HttpRequestMessage({
    required this.url,
    required this.method,
    required this.headers,
    this.body,
  });

  String url;
  String method;
  Map<String, String> headers;
  Uint8List? body;
}

class HttpResponseMessage {
  HttpResponseMessage({required this.status, this.body});

  int status;
  Uint8List? body;
}

// ---------------------------------------------------------------------------
// Dart to native
// ---------------------------------------------------------------------------

/// Calls into the native plugin. Methods marked `@asyncCallback` run on the plugin's
/// serial worker (key management on a separate pool) and fail with a
/// `PlatformException` whose code is `C2PA_ERROR`, `INVALID_ARGUMENT`,
/// `INVALID_HANDLE`, `NOT_IMPLEMENTED_IOS`, `NOT_IMPLEMENTED_ANDROID`,
/// `NOT_AVAILABLE`, `KEY_NOT_FOUND`, `ENROLLMENT_ERROR` or `ERROR`.
@HostApi()
abstract class C2paHostApi {
  String getPlatformVersion();

  @asyncCallback
  String getVersion();

  // Reading. A null mimeType for a path means "infer it from the extension".

  @asyncCallback
  String readFile(
    String path,
    String? mimeType,
    ReadFormatMessage format,
    int? contextHandle,
  );

  @asyncCallback
  String readBytes(
    Uint8List data,
    String mimeType,
    ReadFormatMessage format,
    int? contextHandle,
  );

  /// Reads the asset at [path] or in [data] against a separately supplied
  /// manifest store.
  @asyncCallback
  String readWithManifest(
    String? path,
    Uint8List? data,
    String? mimeType,
    Uint8List manifestData,
    ReadFormatMessage format,
    int? contextHandle,
  );

  @asyncCallback
  String readFragment(
    String initPath,
    String fragmentPath,
    String? mimeType,
    ReadFormatMessage format,
    int? contextHandle,
  );

  @asyncCallback
  Uint8List extractResource(
    Uint8List data,
    String mimeType,
    String uri,
    int? contextHandle,
  );

  @asyncCallback
  String? getRemoteUrl(String path, String? mimeType);

  @asyncCallback
  bool isManifestEmbedded(String path, String? mimeType);

  @asyncCallback
  List<String> getSupportedReadMimeTypes();

  @asyncCallback
  List<String> getSupportedSignMimeTypes();

  // One-shot signing.

  @asyncCallback
  SignResultMessage signBytes(
    Uint8List sourceData,
    String mimeType,
    String manifestJson,
    SignerMessage signer,
  );

  @asyncCallback
  void signFile(
    String sourcePath,
    String destPath,
    String manifestJson,
    SignerMessage signer,
  );

  @asyncCallback
  int getSignerReserveSize(SignerMessage signer);

  @asyncCallback
  Uint8List composeManifest(Uint8List manifestBytes, String mimeType);

  // Builders.

  @asyncCallback
  int createBuilder(String manifestJson, int? contextHandle);

  @asyncCallback
  int createBuilderWithSettings(String manifestJson, int settingsHandle);

  @asyncCallback
  int createBuilderFromArchive(Uint8List archiveData, int? contextHandle);

  @asyncCallback
  void builderDispose(int handle);

  @asyncCallback
  void builderSetIntent(
    int handle,
    ManifestIntentMessage intent,
    String? digitalSourceType,
  );

  @asyncCallback
  void builderSetNoEmbed(int handle);

  @asyncCallback
  void builderSetRemoteUrl(int handle, String url);

  @asyncCallback
  void builderSetBasePath(int handle, String path);

  @asyncCallback
  void builderAddResource(int handle, String uri, Uint8List data);

  @asyncCallback
  void builderAddIngredient(
    int handle,
    Uint8List data,
    String mimeType,
    String? ingredientJson,
  );

  @asyncCallback
  void builderAddIngredientFromFile(
    int handle,
    String path,
    String? mimeType,
    String? ingredientJson,
  );

  @asyncCallback
  void builderAddIngredientFromArchive(int handle, Uint8List archiveData);

  @asyncCallback
  Uint8List builderWriteIngredientArchive(int handle, String ingredientId);

  @asyncCallback
  void builderAddAction(int handle, String actionJson);

  @asyncCallback
  Uint8List builderToArchive(int handle);

  /// Signs with [signer], or with the builder's context signer when null.
  @asyncCallback
  SignResultMessage builderSign(
    int handle,
    Uint8List sourceData,
    String mimeType,
    SignerMessage? signer,
  );

  @asyncCallback
  SignResultMessage builderSignFile(
    int handle,
    String sourcePath,
    String destPath,
    String? mimeType,
    SignerMessage? signer,
  );

  @asyncCallback
  bool builderNeedsPlaceholder(int handle, String mimeType);

  @asyncCallback
  Uint8List builderPlaceholder(int handle, String mimeType);

  @asyncCallback
  void builderSetDataHashExclusions(
    int handle,
    List<DataHashExclusionMessage> exclusions,
  );

  @asyncCallback
  void builderUpdateHashFromBytes(int handle, String mimeType, Uint8List data);

  @asyncCallback
  void builderUpdateHashFromFile(int handle, String path, String? mimeType);

  @asyncCallback
  Uint8List builderSignEmbeddable(int handle, String mimeType);

  @asyncCallback
  HashTypeMessage builderHashType(int handle, String mimeType);

  @asyncCallback
  void builderSetFixedSizeMerkle(int handle, int fixedSizeKb);

  @asyncCallback
  void builderHashMdatBytes(
    int handle,
    int mdatId,
    Uint8List data,
    bool largeSize,
  );

  // Key management.

  @asyncCallback
  bool isHardwareSigningAvailable();

  @asyncCallback
  void createKey(
    String keyAlias,
    SigningAlgorithmMessage algorithm,
    bool useHardware,
  );

  @asyncCallback
  bool deleteKey(String keyAlias);

  @asyncCallback
  bool keyExists(String keyAlias);

  @asyncCallback
  String exportPublicKey(String keyAlias);

  @asyncCallback
  void importKey(
    String keyAlias,
    String privateKeyPem,
    String certificateChainPem,
  );

  @asyncCallback
  String createCSR(String keyAlias, CertificateConfigMessage config);

  @asyncCallback
  HardwareKeyEnrollmentMessage enrollHardwareKey(
    String keyAlias,
    String signingServerUrl,
    String? bearerToken,
    String? commonName,
    String? organization,
    bool useStrongBox,
  );

  @asyncCallback
  String createSelfSignedCertificateChain(
    String keyAlias,
    CertificateConfigMessage? config,
  );

  // Settings.

  @asyncCallback
  void loadSettings(String settings, String format);

  @asyncCallback
  int createSettings();

  @asyncCallback
  void settingsUpdateFromString(int handle, String settings, String format);

  /// [jsonValue] is a JSON-encoded value.
  @asyncCallback
  void settingsSetValue(int handle, String path, String jsonValue);

  @asyncCallback
  void settingsDispose(int handle);

  // Contexts.

  @asyncCallback
  int createContext(
    int? settingsHandle,
    SignerMessage? signer,
    bool reportProgress,
    HttpResolverModeMessage? httpResolver,
  );

  /// Runs immediately rather than on the worker, so it reaches an operation
  /// that is occupying the worker.
  void contextCancel(int handle);

  @asyncCallback
  void contextDispose(int handle);
}

// ---------------------------------------------------------------------------
// Native to Dart
// ---------------------------------------------------------------------------

/// Calls from the native plugin into Dart, made while a native operation
/// waits for the answer (except [progress]).
@FlutterApi()
abstract class C2paFlutterApi {
  /// Signs [data] with the Dart callback registered as [callbackId].
  @asyncCallback
  Uint8List sign(String callbackId, Uint8List data);

  /// Reports progress of an operation on the context [contextHandle].
  /// [phase] is the SDK phase name, for example `signing`.
  @asyncCallback
  void progress(int contextHandle, String phase, int step, int total);

  /// Answers an HTTP request for the context [contextHandle].
  @asyncCallback
  HttpResponseMessage resolveHttp(int contextHandle, HttpRequestMessage request);
}
